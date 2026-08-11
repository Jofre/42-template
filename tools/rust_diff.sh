#!/bin/sh
# Live differential test.
#
# Runs the prebuilt Rust reference (//oracle:oracle) to emit a fixed, seeded set
# of self-describing cases:
#     <hexInputs...>\t<reference-output>
# replays the SAME inputs through the student's compiled C harness (which
# reprints <hexInputs...>\t<student-output>), and byte-diffs the two. A mismatch
# prints the exact input plus both outputs, so root cause is never ambiguous.
#
# Deterministic by construction: same oracle binary + same seed + same count =>
# identical cases every run. No wall-clock, no test-time entropy.
#
# Usage:
#   rust_diff.sh --oracle PATH --oracle-fn NAME --student-bin PATH
#                [--seed N] [--count N] [--clues PATH] [--crash-only]
#                [--gate-differ PATH] [--gate-bin PATH] [--gate-expected PATH]
#                [--gate-stdin PATH] [--gate-sanitize] [--gate-labeled]
#
#   --oracle        the reference binary (//oracle:oracle)
#   --oracle-fn     which arm of it to generate a corpus from, e.g. c07_strdup
#   --student-bin   the harness binary that replays that corpus
#   --seed          corpus seed (default 1); same seed, same corpus
#   --count         how many cases to generate
#   --clues         clues.tsv to draw hints from when a case fails
#   --crash-only    report only crashes, not value mismatches
#   --gate-*        the exercise's own output fixture and how to run it. This
#                   layer SKIPS unless that fixture passes, so a student whose
#                   output is still red is not buried in differential noise.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "rust_diff.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat cmp grep head mktemp rm sed tr wc

ORACLE=""
FN=""
SEED="1"
COUNT="4000"
STUDENT=""
CLUES=""
HARNESS_SRC=""
CRASH_ONLY=0
GATE_DIFFER=""
GATE_BIN=""
GATE_EXPECTED=""
GATE_PASS=""
# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "rust_diff.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--oracle-fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--seed) need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--student-bin) need "$1" "$#"; STUDENT="$2"; shift 2 ;;
		--clues) need "$1" "$#"; CLUES="$2"; shift 2 ;;
		--harness-src) need "$1" "$#"; HARNESS_SRC="$2"; shift 2 ;;
		--crash-only) CRASH_ONLY=1; shift ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-stdin) need "$1" "$#"; GATE_PASS="$GATE_PASS --stdin $2"; shift 2 ;;
		--gate-sanitize) GATE_PASS="$GATE_PASS --sanitize"; shift ;;
		--gate-labeled) GATE_PASS="$GATE_PASS --labeled"; shift ;;
		*) echo "rust_diff: unknown arg $1" >&2; exit 2 ;;
	esac
done

# Harmless for a normally-built binary; for an ASan/UBSan build these make any
# memory error or UB abort the harness (non-zero exit). Leaks are covered by the
# valgrind layer, so skip them here to avoid noise on returned-then-freed memory.
export ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:${ASAN_OPTIONS:-}"
export UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1:${UBSAN_OPTIONS:-}"

if [ -z "$ORACLE" ] || [ -z "$FN" ] || [ -z "$STUDENT" ]; then
	echo "rust_diff: need --oracle, --oracle-fn and --student-bin" >&2
	exit 2
fi

# ---------------------------------------------------------------------------
# Correctness gate: run the exercise's own curated fixture first, and SKIP if it
# is already red.
#
# The *_output layer is the one with pedagogic value: a labelled table, the
# cases ordered trivial-to-hard, and a clues.tsv attached. This layer is 400k
# hex lines. When both fail they say the same thing, but only one of them says
# it usefully — and measured across the whole repo, 43 of 43 diff failures were
# duplicating an already-red functional layer. That is the entire red signal of
# this layer, spent on noise, at ~53% of the suite's CPU.
#
# So: get the curated cases right first, then the corpus tells you something new.
# Same reasoning and same shape as the gate in tools/ilp32_test.sh.
#
# Fails OPEN by design. If no gate was supplied, or the gate binary cannot run,
# the differential still runs — a gate that wrongly skips would turn a genuine
# divergence green, which is far worse than duplicating a red. Only an
# unambiguous "the fixture ran and did not pass" suppresses this layer.
# NO_SKIP=1 forces every gated layer to run anyway. A gate that suppresses a
# layer is indistinguishable, in a green suite, from a layer that has nothing to
# say — so there has to be a way to ask "does this actually still check
# something?". Use it before trusting an all-green run:
#     bazel test //... --test_env=NO_SKIP=1
if [ "${NO_SKIP:-0}" = "1" ]; then
	GATE_DIFFER=""
fi

if [ -n "$GATE_DIFFER" ] && [ -n "$GATE_BIN" ] && [ -n "$GATE_EXPECTED" ] &&
	[ -x "$GATE_BIN" ] && [ -f "$GATE_EXPECTED" ]; then
	# shellcheck disable=SC2086
	if ! sh "$GATE_DIFFER" --bin "$GATE_BIN" --expected "$GATE_EXPECTED" \
			$GATE_PASS >/dev/null 2>&1; then
		echo "rust_diff: SKIP — this exercise's own output fixture is not passing yet."
		echo ""
		echo "  That fixture is the one worth reading: a labelled table, cases ordered"
		echo "  from trivial to subtle, and hints attached. This layer replays $COUNT"
		echo "  generated cases and reports raw divergences — the same failure, told"
		echo "  far less usefully. Get the *_output layer green and this one starts"
		echo "  checking the inputs you did not think of."
		exit 0
	fi
fi

# Render clues.tsv the way every other layer does.
#
# The clue file, printed whole.
#
# It used to be rendered the way diff_output.sh renders clues.tsv -- cut -f1,
# take the first three lines, bullet each -- and that is right for a TSV of
# one-line hints attached to named fixture cases, where showing all of them at
# once hands over the answer key for a single failure.
#
# It is wrong here, and the repo's only diff_clues.txt proved it: that file is a
# LEGEND -- how to read a divergence, then which family of failing inputs
# implies what -- and the tiered renderer printed the first three lines of its
# opening paragraph, each prefixed with a bullet, mid-sentence. Three fragments
# of prose that were never three hints.
#
# Two things make printing it whole the right call rather than a concession.
# There are no case names in a differential run, so there is nothing to attach
# hints to and nothing to unlock by passing more cases -- the tiering has no
# input here. And this layer fires only after the curated fixture is green, so
# its reader has already exhausted everything they could reason about; rationing
# the explanation at that point protects nothing.
#
# `#` comments are stripped so a file can carry maintainer notes that never
# reach a student.
print_clues() {
	[ -n "$CLUES" ] && [ -f "$CLUES" ] || return 0
	_body=$(grep -vE '^[[:space:]]*#' "$CLUES")
	[ -n "$_body" ] || return 0
	echo "----- hint -----"
	printf '%s\n' "$_body"
}

# What the hex COLUMNS are, taken from the harness's own header comment.
#
# Every reader harness opens with a "Line: <col>\t<col>..." sentence describing
# the record it parses -- written next to the parsing code, and until now read by
# nobody but a maintainer. Meanwhile this layer printed raw hex with "leading
# columns are the inputs" as the only guidance, and it fires at the worst
# possible moment: it SKIPS while the curated fixture is still red, so a student
# only ever sees it after exhausting every case they could reason about.
#
# Reusing that comment rather than writing a legend per exercise means the legend
# cannot drift from the parser -- they are the same lines -- and it costs no new
# files. It is not a substitute for a real diff_clues.txt (see TODO item 1), it
# is what every exercise gets for free until one is written.
print_columns() {
	[ -n "$HARNESS_SRC" ] && [ -f "$HARNESS_SRC" ] || return 0
	# The sentence runs from "Line:" to the end of the block comment -- and awk
	# rather than a sed range, because `sed -n '/Line:/,/\*\//p'` does not stop
	# on the line it started on. Sixteen of the harnesses here close their
	# comment on the same line as the sentence, so for those the range ran on to
	# the NEXT `*/` -- or to the 12-line limit -- and spilled #includes, the
	# prototype and the head of main() into the report a student reads. awk
	# prints first and tests afterwards, which is exactly the difference.
	_cols=$(sed -n '1,12p' "$HARNESS_SRC" |
		awk '/Line:/ { f = 1 } f { print; if (/\*\//) exit }' |
		sed 's/^[[:space:]]*\*[[:space:]]\{0,1\}//; s|[[:space:]]*\*/[[:space:]]*$||' |
		grep -v '^[[:space:]]*$')
	[ -n "$_cols" ] || return 0
	echo "----- what the columns are -----"
	printf '%s\n' "$_cols" | sed 's/^/   /'
}

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

if ! "$ORACLE" "$FN" "$SEED" "$COUNT" > "$T/exp" 2> "$T/oerr"; then
	echo "rust_diff: reference failed to generate cases (fn=$FN)"
	cat "$T/oerr" >&2
	exit 1
fi

# A corpus that came out empty (or absurdly short) means the reference emitted
# nothing — an unknown fn name the dispatcher swallowed, a count that parsed as
# 0, a generator that returned early. Without this guard the two empty files
# compare equal and the layer reports "OK (0 cases)": a green test that checked
# nothing at all. Fail loudly instead — a differential layer that silently tests
# nothing is worse than no layer.
NCASES=$(wc -l < "$T/exp" | tr -d ' ')
if [ "$NCASES" -lt "${MIN_DIFF_CASES:-16}" ]; then
	echo "rust_diff: FAIL — the reference produced only $NCASES case(s) for fn=$FN"
	echo "           (asked for $COUNT at seed $SEED). This layer tests nothing in"
	echo "           that state, so it reports failure rather than a false green."
	[ -s "$T/oerr" ] && { echo "  reference stderr:"; sed 's/^/    /' "$T/oerr" | head -5; }
	exit 1
fi

# Crash-fuzz mode: feed the same corpus through an ASan/UBSan-instrumented
# harness and assert it survives. Value correctness is NOT checked here (a
# memory-safe stub should pass) — this catches out-of-bounds / use-after-free /
# UB that returns the "right" value and so slips past the value diff.
if [ "$CRASH_ONLY" -eq 1 ]; then
	"$STUDENT" < "$T/exp" > /dev/null 2> "$T/serr"
	rc=$?
	if [ "$rc" -eq 0 ]; then
		echo "rust_diff: OK — no sanitizer error over $(wc -l < "$T/exp" | tr -d ' ') fuzz cases (fn=$FN, seed=$SEED)"
		exit 0
	fi
	echo "rust_diff: FAIL — memory/UB error on a fuzz input (harness exit $rc, fn=$FN, seed=$SEED)"
	echo "----- sanitizer report -----"
	sed 's/^/  /' "$T/serr" | head -45
	exit 1
fi

# Replay the reference's inputs through the student harness. Do NOT abort on a
# non-zero exit: a crash/UB on some fuzz input is itself a finding to report.
"$STUDENT" < "$T/exp" > "$T/act" 2> "$T/serr"
rc=$?

if cmp -s "$T/exp" "$T/act" && [ "$rc" -eq 0 ]; then
	echo "rust_diff: OK ($(wc -l < "$T/exp" | tr -d ' ') cases, fn=$FN, seed=$SEED)"
	exit 0
fi

# HOW the run ended decides what to report, because three unrelated failures
# used to print the same headline -- "student output diverges from the
# reference" -- followed by a divergence list that was usually EMPTY. A process
# killed mid-corpus leaves a truncated $T/act, and a truncated file has no
# DIFFERING line to show: every line it did produce matched. So the layer claimed
# a divergence and then showed none, on the single most likely way a Piscine
# harness dies. "Diverges" is now reserved for what the word means: the program
# ran to completion and printed something else.
NDONE=$(wc -l < "$T/act" | tr -d ' ')
NTOTAL=$(wc -l < "$T/exp" | tr -d ' ')

if [ "$rc" -gt 128 ]; then
	sig=$((rc - 128))
	# Same table as tools/diff_output.sh's crash verdict, so a student meets one
	# vocabulary for a dead process rather than two.
	case "$sig" in
		4)  name="SIGILL (illegal instruction)" ;;
		6)  name="SIGABRT (abort: assertion, stack smashing, or a glibc heap error)" ;;
		8)  name="SIGFPE (arithmetic error, e.g. division or modulo by zero, or INT_MIN / -1)" ;;
		9)  name="SIGKILL (killed from outside — see below)" ;;
		11) name="SIGSEGV (invalid memory access)" ;;
		13) name="SIGPIPE (wrote to a closed pipe)" ;;
		*)  name="signal $sig" ;;
	esac
	echo "rust_diff: FAIL — the student harness was KILLED by $name"
	echo "           (fn=$FN, seed=$SEED)"
	echo ""
	echo "  Output stopped after $NDONE of $NTOTAL cases, and everything up to there"
	echo "  matched. So this is not a wrong answer — it is a program that stopped"
	echo "  existing partway through, and nothing past that point was compared."
	if [ "$sig" = 9 ] || [ "$rc" = 124 ]; then
		echo ""
		echo "  SIGKILL comes from outside the process — it cannot be caught, and"
		echo "  almost nothing chooses it for itself. In practice it is one of two"
		echo "  things: this test's own time limit${TEST_TIMEOUT:+, ${TEST_TIMEOUT}s here}, or the kernel's"
		echo "  out-of-memory killer. Both mean an infinite loop, or memory that is"
		echo "  never freed and grows with every case. If the input below runs fine"
		echo "  on its own, suspect this layer's sizing before your own logic."
	fi
	# A narrowed reproducer is the most useful thing this layer has. It is a
	# WINDOW and not a single line on purpose: stdout is block-buffered when it
	# is a file, so a process that dies takes up to a few KiB of already-printed
	# output down with it. $NDONE therefore counts what was FLUSHED, not what was
	# processed, and the failing case is at or after the first line below.
	# Claiming otherwise would be a precise-looking number that is routinely
	# wrong — worse than the honest range.
	if [ "$NDONE" -lt "$NTOTAL" ]; then
		echo ""
		echo "  It died at or after case $((NDONE + 1)). Start with these (each is a"
		echo "  complete input line — feed one to your harness on its own):"
		sed -n "$((NDONE + 1)),$((NDONE + 3))p" "$T/exp" | sed 's/^/    /'
	fi
	[ -s "$T/serr" ] && { echo ""; echo "  stderr:"; sed 's/^/    /' "$T/serr" | head -12; }
	print_columns
	print_clues
	exit 1
fi

if [ "$rc" -ne 0 ] && cmp -s "$T/exp" "$T/act"; then
	# Right answers, wrong ending. Kept apart from a divergence for the same
	# reason progname_test.sh separates them: "it printed everything correctly
	# and then returned non-zero" is a different bug from "it printed the wrong
	# thing", and merging the two hides which one happened.
	echo "rust_diff: FAIL — every one of the $NTOTAL cases matched the reference, but"
	echo "           the harness exited $rc rather than 0 (fn=$FN, seed=$SEED)"
	[ -s "$T/serr" ] && { echo "  stderr:"; sed 's/^/    /' "$T/serr" | head -8; }
	exit 1
fi

echo "rust_diff: FAIL — student output diverges from the reference (fn=$FN, seed=$SEED)"
if [ "$rc" -ne 0 ]; then
	echo "  NOTE: student harness exited $rc (possible crash / UB on a fuzz input)"
	[ -s "$T/serr" ] && { echo "  stderr:"; sed 's/^/    /' "$T/serr" | head -8; }
fi
echo "----- first divergences (reference vs student; leading columns are the inputs) -----"
# exp and act are 1:1 aligned (the harness echoes each input line in order); show
# the full line from each so the format's own columns are visible regardless of
# how many fields it has.
awk '
	NR == FNR { ref[FNR] = $0; next }
	$0 != ref[FNR] {
		printf "  reference: %s\n  student  : %s\n", ref[FNR], $0
		n++
	}
	n >= 15 { print "  ..."; exit }
' "$T/exp" "$T/act"
print_columns
print_clues
exit 1
