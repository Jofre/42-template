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
#                [--harness-src PATH] [--symbolizer PATH --symbolizer-lib PATH]
#                [--gate-differ PATH] [--gate-bin PATH] [--gate-expected PATH]
#                [--gate-stdin PATH] [--gate-sanitize] [--gate-labeled]
#                [--gate-label NAME]
#
#   --oracle        the reference binary (//oracle:oracle)
#   --oracle-fn     which arm of it to generate a corpus from, e.g. c07_strdup
#   --student-bin   the harness binary that replays that corpus
#   --seed          corpus seed (default 1); same seed, same corpus
#   --count         how many cases to generate
#   --clues         a diff_clues.txt legend, printed whole under the hint
#                   heading when a case fails
#   --crash-only    report only crashes, and a replay that ended before its
#                   last case, not value mismatches
#   --harness-src   the harness's source, whose "Line:" comment says what the
#                   corpus columns are
#   --symbolizer    the pinned llvm-symbolizer, and --symbolizer-lib a library
#                   file beside the libLLVM it loads: a sanitizer's frames then
#                   name a function, a file and a line (rl_sanitizers)
#   --gate-*        the exercise's own output fixture and how to run it. This
#                   layer SKIPS unless that fixture passes, so a student whose
#                   output is still red is not buried in differential noise.
#   --gate-label    the output test that fixture is, named in the SKIP line
#                   (c_levels()' audit holds it to that test,
#                   _gate_label_problems). Without it the line says "this
#                   exercise's own output fixture", which names no test.
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

# The shared runner helpers: the time budget, signal traps, how a run ended,
# byte rendering, excerpts and hints (tools/runner_lib.sh, which says why each
# is written once).
RL_NAME=rust_diff
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "rust_diff.sh: tools/runner_lib.sh is not staged (tools/defs_test.bzl's _test() stages it for every test; by hand, run this by its path in the repository)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool ORACLE -- the Rust reference (//oracle), which writes the corpus

ORACLE=""
FN=""
SEED="1"
COUNT="4000"
STUDENT=""
CLUES=""
HARNESS_SRC=""
CRASH_ONLY=0
SYMBOLIZER=""
SYMBOLIZER_LIB=""
GATE_DIFFER=""
GATE_BIN=""
GATE_EXPECTED=""
GATE_PASS=""
GATE_LABEL=""
# How many bytes of one corpus line a report shows: rl_excerpt's width.
SHOW_W=${RL_EXCERPT_WIDTH:-300}

while [ $# -gt 0 ]; do
	case "$1" in
		--oracle) rl_need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--oracle-fn) rl_need "$1" "$#"; FN="$2"; shift 2 ;;
		--seed) rl_need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) rl_need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--student-bin) rl_need "$1" "$#"; STUDENT="$2"; shift 2 ;;
		--clues) rl_need "$1" "$#"; CLUES="$2"; shift 2 ;;
		--harness-src) rl_need "$1" "$#"; HARNESS_SRC="$2"; shift 2 ;;
		--crash-only) CRASH_ONLY=1; shift ;;
		--symbolizer) rl_need "$1" "$#"; SYMBOLIZER="$2"; shift 2 ;;
		--symbolizer-lib) rl_need "$1" "$#"; SYMBOLIZER_LIB="$2"; shift 2 ;;
		--gate-differ) rl_need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) rl_need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) rl_need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-stdin) rl_need "$1" "$#"; rl_list_add GATE_PASS --stdin "$2"; shift 2 ;;
		--gate-sanitize) rl_list_add GATE_PASS --sanitize; shift ;;
		--gate-labeled) rl_list_add GATE_PASS --labeled; shift ;;
		--gate-label) rl_need "$1" "$#"; GATE_LABEL="$2"; shift 2 ;;
		*) echo "rust_diff: unknown arg $1" >&2; exit 2 ;;
	esac
done

# A gate given in part is a wiring mistake (runner_lib.sh, rl_gate_whole).
rl_gate_whole rust_diff "$GATE_DIFFER" "$GATE_BIN" "$GATE_EXPECTED" "$GATE_PASS$GATE_LABEL"

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
# something?", and the SKIP prints the command that asks it of this test.
# The gate is tools/runner_lib.sh's rl_gate, as every runner's is (its WHY THE
# STATUS IS CAPTURED says what a copy of it here once got wrong); the paragraph
# under its SKIP is this layer's own.
RL_GATE_PASS=$GATE_PASS
RL_GATE_NAME=$GATE_LABEL
RL_GATE_WHY="  That fixture is the one worth reading: a labelled table, cases ordered
  from trivial to subtle, and hints attached. This layer replays $COUNT
  generated cases and reports raw divergences — the same failure, told
  far less usefully. Get the *_output layer green and this one starts
  checking the inputs you did not think of."
rl_gate rust_diff "$GATE_DIFFER" "$GATE_BIN" "$GATE_EXPECTED"

# A PROGRAM THAT DID NOT BUILD is a stand-in script that says why (see
# tools/standin.sh). Checked after the gate: a red gate has already skipped
# this layer, and past a green one -- or one NO_SKIP=1 forced open -- a
# stand-in is a failure, told in the compiler's words rather than as a
# report about a program that does not exist.
rl_tool standin.sh
# shellcheck source=tools/standin.sh
. "$RL_TOOL"
standin_check rust_diff "$STUDENT" fail "the program this layer replays"

# --clues here is a diff_clues.txt, not a clues.tsv: a LEGEND, printed whole by
# rl_legend (tools/runner_lib.sh says why a legend is not rationed like hints).

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
# files. It is not a substitute for the curated diff_clues.txt beside the
# harness; it is what an exercise gets for free where none is written.
#
# THE SHAPE IT READS, which //tools:conventions holds every tests/**/diff_*.c
# to (finding 058): within the first 12 lines, a comment line that begins
# with "Line:" -- never the `/*` line itself -- naming every column the
# harness prints, inputs and output alike. The legend is that PARAGRAPH:
# from "Line:" to the first empty comment line or the end of the comment,
# whichever comes first, so the notes a harness keeps below it (why the
# output is captured, what the corpus avoids) stay out of the report.
#
# It used to be scraped from free-form comments: a sentence on the `/*` line
# printed with the `/*` and the words before it, a header with no "Line:"
# printed nothing at all, and a sentence followed by notes printed them too,
# up to the 12-line limit. Now a harness out of shape still gets a line here,
# saying where its columns are described, and "Line:" is cut out of whatever
# it shares a line with.
print_columns() {
	[ -n "$HARNESS_SRC" ] && [ -f "$HARNESS_SRC" ] || return 0
	# awk rather than a sed range: `sed -n '/Line:/,/\*\//p'` does not stop on
	# the line it started on, and a comment closed on the sentence's own line
	# ran on to the NEXT `*/`. awk prints first and tests afterwards.
	_cols=$(sed -n '1,12p' "$HARNESS_SRC" | awk '
		{ line = $0 }
		# The sentence: from "Line:" on, whatever came before it on its line.
		!f {
			i = index(line, "Line:")
			if (i == 0) next
			f = 1
			line = substr(line, i)
		}
		# The lines after it: the paragraph ends at an empty comment line or
		# at a line that only closes the comment.
		f && more {
			if (line ~ /^[ \t]*\*\/[ \t]*$/) exit
			sub(/^[ \t]*\*[ \t]?/, "", line)
			if (line ~ /^[ \t]*$/) exit
		}
		f {
			more = 1
			done = (line ~ /\*\//)
			sub(/[ \t]*\*\/.*$/, "", line)
			if (line != "") print line
			if (done) exit
		}')
	echo "----- what the columns are -----"
	if [ -n "$_cols" ]; then
		printf '%s\n' "$_cols" | sed 's/^/   /'
	else
		echo "   (the harness names none in the shape this layer reads; its header"
		echo "   comment, in $HARNESS_SRC, is where they are described)"
	fi
}

T=$(mktemp -d) || { echo "$RL_NAME.sh: cannot create a scratch directory" >&2; exit 2; }
rl_traps 'rm -rf "$T"'

# Harmless for a normally-built binary; for an ASan/UBSan build they make any
# memory error or UB abort the harness, with its frames symbolised by the
# pinned llvm-symbolizer when one was passed (tools/runner_lib.sh says which
# keys, and why never one from PATH).
rl_sanitizers "$T/sym" "$SYMBOLIZER" "$SYMBOLIZER_LIB"

# A reference that fails is the harness failing: exit 2, nothing was checked
# (it was 1, the code for a wrong program, and so was the floor below).
if ! "$ORACLE" "$FN" "$SEED" "$COUNT" > "$T/exp" 2> "$T/oerr"; then
	echo "rust_diff: reference failed to generate cases (fn=$FN)"
	rl_excerpt "$T/oerr" 10 oracle-stderr.txt >&2
	exit 2
fi

# A corpus that came out empty (or absurdly short) means the reference emitted
# nothing — an unknown fn name the dispatcher swallowed, a count that parsed as
# 0, a generator that returned early. Without this guard the two empty files
# compare equal and the layer reports "OK (0 cases)": a green test that checked
# nothing at all. A differential layer that silently tests nothing is worse
# than no layer, so this refuses (rl_corpus_floor, exit 2).
rl_corpus_floor "$T/exp" "${MIN_DIFF_CASES:-16}" "fn=$FN (asked for $COUNT at seed $SEED)" "$T/oerr"
NCASES=$(wc -l < "$T/exp" | tr -d ' ')

# THE STUDENT RUNS, bounded twice.
#
# In TIME: whatever is left of this test's own limit (rl_tmo, with no per-run
# cap of its own -- one run replays the whole corpus). This runner used to run
# the harness bare, so a slow or looping answer was killed by Bazel with an
# empty log, and the "killed by SIGKILL" report below could never be reached:
# Bazel killed the runner too.
#
# In SIZE: a function that prints without end fills the test's scratch space at
# page-cache speed until something stops it. `ulimit -f` stops it at the
# source, SIGXFSZ, far above anything a correct harness writes: four times the
# corpus it echoes, plus 16 MiB.
EXP_BYTES=$(wc -c < "$T/exp" | tr -d ' ')
OUT_BLOCKS=$(( (EXP_BYTES * 4 + 16777216) / 512 ))
run_student() {  # run_student STDOUT-FILE
	# No time left even to start it: the reference took the whole budget.
	if ! rl_tmo; then
		rl_overrun "the replay of the $NCASES-case corpus (fn=$FN, seed=$SEED)"
		exit 1
	fi
	# DIO_CASE_FILE asks a harness built on tools/diffio.h to write, as it
	# dies, the corpus line it was on (died_case, below): only this runner
	# asks, since its corpus is the one the number counts.
	rm -f "$T/died"
	(
		ulimit -f "$OUT_BLOCKS" 2> /dev/null
		DIO_CASE_FILE=$T/died
		export DIO_CASE_FILE
		rl_run "$STUDENT" < "$T/exp" > "$1" 2> "$T/serr"
	)
}
# A harness that could not be started says nothing about the student's code:
# a wiring error, exit 2, never a verdict.
not_started() {
	if [ "$RL_CAUSE" = noexec ]; then
		echo "rust_diff.sh: the harness $RL_WHY" >&2
		exit 2
	fi
	# Nor does one stopped from outside (rl_unjudged).
	rl_unjudged "the replay (fn=$FN, seed=$SEED)"
	# Nor does one that met a corpus line it cannot hold. It stops itself,
	# saying so (tools/diffio.h, DIO_HARNESS_ERROR), rather than read half a
	# line as a case; what the student's function did never came into it.
	grep -q '^diffio: HARNESS ERROR' "$T/serr" 2> /dev/null || return 0
	echo "rust_diff.sh: the reader harness could not read the corpus (fn=$FN, seed=$SEED):" >&2
	rl_excerpt "$T/serr" 5 harness-error.txt "  " >&2
	exit 2
}

# replay_how PREFIX -- the command that replays one corpus line, a WORD from
# case_word: corpus line N as ONE shell word that gives back its exact bytes
# (rl_shword), never raw (see reproducer, below).
case "$STUDENT" in
	/*) REPLAY_BIN=$STUDENT ;;
	*) REPLAY_BIN=bazel-bin/$STUDENT ;;
esac
replay_how() {
	printf '%s%s runs it on its own:\n' "$1" "printf '%s\\n' WORD | $REPLAY_BIN"
}
case_word() {  # case_word N
	sed -n "${1}{p;q;}" "$T/exp" | LC_ALL=C tr -d '\n' | rl_shword
}
# case_shown N NAME -- corpus line N as case_word writes it; or, when the
# line is longer than a report shows (SHOW_W), kept as test output NAME and
# named, with the command that replays it from there. A word must give back
# every byte, so it cannot be cut, and the corpora hold lines of 20 to 80 KB
# (finding 041): three of them as words were a log of hundreds of KB.
case_shown() {
	sed -n "${1}{p;q;}" "$T/exp" > "$T/case.$1"
	_cs_n=$(($(wc -c < "$T/case.$1") - 1))
	if [ "$_cs_n" -le "$SHOW_W" ]; then
		case_word "$1"
	elif rl_save "$T/case.$1" "$2"; then
		printf '(case %d, a line of %d bytes, too long to show: %s < %s runs it)' \
			"$1" "$_cs_n" "$REPLAY_BIN" "$RL_SAVED"
	else
		printf '(case %d, a line of %d bytes, too long to show; only a run under bazel test keeps it)' \
			"$1" "$_cs_n"
	fi
}

# How far the run got, for a report on one that did not finish: the first line
# the harness had not answered, and the inputs from there. A WINDOW, not a
# single line: stdout is block-buffered when it is a file, so a process that
# dies takes up to a few KiB of already-printed output down with it. The count
# is what was FLUSHED, not what was processed, and the case at fault is at or
# after the first line shown. Claiming otherwise would be a precise-looking
# number that is routinely wrong.
#
# Each line is printed as ONE shell word that gives back its exact bytes
# (rl_shword, tools/runner_lib.sh), never raw. A corpus line carries the
# reference's output after its inputs, and that output can be any byte: C 04
# ex04's bases hold control bytes on purpose (finding 061). Printed raw, a
# control byte was invisible and an ESC could repaint the terminal -- and the
# line could not be replayed either, since a terminal turns its tabs into
# spaces when it is copied.
#
# A run that DIED -- a signal, a sanitizer's abort -- lost what its buffer held,
# so the case it died in may be thousands further on than the first unanswered
# one: "start with these" sent a reader to replay three innocent cases (the
# mutation run of 2026-10-03, c00-c01 M9: case 1 of 400000, where the
# sanitizer twin named #12). With "died" as a third argument the words say so,
# and name the target that replays the corpus on a build that says which case
# it died in.
reproducer() {  # reproducer DONE TOTAL [died]
	[ "$1" -lt "$2" ] || return 0
	echo ""
	if [ "${3:-}" = died ]; then
		echo "  It had answered $1 case(s) when it died, and it writes its answers"
		echo "  through a buffer, which died with it: the case it died in is case"
		echo "  $(($1 + 1)) or one after it, possibly thousands after. This $(rl_noun)'s"
		echo "  _diff_asan target replays the same corpus on a build that names the case."
		echo "  The first inputs it had not answered, each one complete input line,"
		echo "  written as a shell word that gives back its exact bytes, so that"
		replay_how "  "
	else
		echo "  It stopped at or after case $(($1 + 1)). Start with these: each is one"
		echo "  complete input line, written as a shell word that gives back its exact"
		replay_how "  bytes, so that "
	fi
	_rp_i=$(($1 + 1))
	while [ "$_rp_i" -le "$(($1 + 3))" ] && [ "$_rp_i" -le "$2" ]; do
		printf '    %s\n' "$(case_shown "$_rp_i" "case-$_rp_i.txt")"
		_rp_i=$((_rp_i + 1))
	done
}

# died_case -- true when the harness said which corpus case it died on, and
# DIED_CASE is that case. A harness built on tools/diffio.h writes the number
# into the file run_student names in DIO_CASE_FILE as it dies: from the
# sanitizer's death callback for a death ASan reports (finding 051), and
# from a signal handler for the rest, every death of the plain build (V46),
# where the report used to say only that the case was "at or after" the
# first unanswered one, possibly thousands short of it. A number outside
# the corpus is no case.
died_case() {
	DIED_CASE=
	[ -s "$T/died" ] && DIED_CASE=$(LC_ALL=C tr -cd '0-9' < "$T/died")
	[ -n "$DIED_CASE" ] && [ "$DIED_CASE" -ge 1 ] 2> /dev/null && [ "$DIED_CASE" -le "$NCASES" ]
}
# show_died_case -- that case's line, as the reference wrote it, the way
# reproducer gives a line (a shell word and the command that replays it),
# and kept.
show_died_case() {
	echo "  It happened on corpus case #$DIED_CASE of $NCASES. That case, as the reference"
	echo "  wrote it -- the inputs, then the reference's answer -- written as a shell"
	echo "  word that gives back its exact bytes, so that"
	replay_how "  "
	_dc_w=$(case_shown "$DIED_CASE" crashing-case.txt)
	printf '    %s\n' "$_dc_w"
	case "$_dc_w" in
		"(case "*) ;;
		*) rl_save "$T/case.$DIED_CASE" crashing-case.txt && echo "    (kept as $RL_SAVED)" ;;
	esac
}

# crash_where -- which case a --crash-only run that did not end with 0 was
# on. The instrumented harness says so itself (tools/diffio.h's death
# callback): its buffered stdout died with it, so the count of answers
# received is only a lower bound, and the report used to show no input at
# all (finding 051). Without that, where its answers stopped arriving; and a
# harness that answered every case before it ended says that instead of a
# heading with no case under it.
crash_where() {
	if died_case; then
		show_died_case
	elif [ "$NDONE" -ge "$NCASES" ]; then
		echo "  It had answered all $NCASES cases when it ended."
	else
		echo "  The harness did not say which case it was on, so here is where its"
		echo "  answers stopped arriving:"
		reproducer "$NDONE" "$NCASES"
	fi
}

# Whether everything the run DID answer matched: said only when checked. The
# COMPLETE lines on both sides: a run cut short can leave half a line after its
# last newline, and that half is not an answer that differs.
prefix_matched() {  # prefix_matched DONE
	[ "$1" -gt 0 ] || return 1
	head -n "$1" "$T/act" > "$T/act.done"
	head -n "$1" "$T/exp" | cmp -s - "$T/act.done"
}

# Crash-fuzz mode: feed the same corpus through an ASan/UBSan-instrumented
# harness and assert it survives. Value correctness is NOT checked here (a
# memory-safe stub should pass) — this catches out-of-bounds / use-after-free /
# UB that returns the "right" value and so slips past the value diff.
if [ "$CRASH_ONLY" -eq 1 ]; then
	run_student "$T/act"
	rc=$?
	rl_classify "$rc"
	not_started
	NDONE=$(wc -l < "$T/act" | tr -d ' ')
	# AN END WITH 0 IS A PASS ONLY OVER EVERY CASE. A harness prints one line
	# a case (tools/diffio.h's readers, Rush 00's diff_rush.c), so fewer lines
	# than cases is a run that stopped early: an exit(0) in the function ends
	# the harness where it is called, and every case after it never reached
	# this build. It said "OK -- no sanitizer error over N fuzz cases" then,
	# N the reference's count, having checked one. More lines than
	# cases is a function printing lines of its own: a value, which is the
	# diff layer's to judge, never this one's.
	if [ "$rc" -eq 0 ] && [ "$NDONE" -lt "$NCASES" ]; then
		echo "rust_diff: FAIL — the harness ended with exit 0 having answered $NDONE of $NCASES cases (fn=$FN, seed=$SEED),"
		echo "  so case $((NDONE + 1)) of $NCASES and every case after it were never answered, and nothing"
		echo "  says they reached this sanitizer build. A call that ends the program --"
		echo "  exit() in your function -- stops the harness where it is made, with exit 0."
		reproducer "$NDONE" "$NCASES"
		exit 1
	fi
	if [ "$rc" -eq 0 ]; then
		echo "rust_diff: OK — no sanitizer error over $NCASES fuzz cases (fn=$FN, seed=$SEED)"
		exit 0
	fi
	if [ "$RL_CAUSE" = timeout ]; then
		rl_overrun "the input at or after case $((NDONE + 1)) of $NCASES (fn=$FN, seed=$SEED)"
		echo "  Nothing about memory safety was concluded: the replay never ended."
		reproducer "$NDONE" "$NCASES"
		exit 1
	fi
	if [ "$RL_CAUSE" = runaway ]; then
		echo "rust_diff: FAIL — the harness kept printing past $((OUT_BLOCKS * 512)) bytes and was"
		echo "           stopped (fn=$FN, seed=$SEED): a loop whose exit condition is never met."
		reproducer "$NDONE" "$NCASES"
		exit 1
	fi
	# How it ended, in the sanitizer's words when its report is there
	# (rl_sanitized): SIGABRT's own named every cause but that one (V50).
	#
	# AN END WITH NO REPORT IS NO MEMORY ERROR. rl_sanitized's answer was
	# thrown away here (`|| :`), so a harness that returned 3 -- a function
	# that called exit(3) -- was headlined a memory/UB error, and got the
	# paragraph about a READ or a WRITE outside a block, above a report
	# section with no report in it. It is still red, since the harness did
	# not end with 0, but what it says is what happened.
	if ! rl_sanitized "$T/serr"; then
		echo "rust_diff: FAIL — the harness $RL_WHY with no sanitizer report (fn=$FN, seed=$SEED)"
		echo "  The sanitizers reported nothing, so no memory error was seen. A run of"
		echo "  this replay ends with 0 once it has answered every case, and this one"
		echo "  ended otherwise. A call that ends the program -- exit() or abort() in"
		echo "  your function, or an assert() that failed -- stops the harness where it"
		echo "  is made, with that call's own ending."
		echo ""
		crash_where
		echo ""
		if [ -s "$T/serr" ]; then
			echo "  What it wrote to standard error:"
			rl_excerpt "$T/serr" 10 harness-stderr.txt "  "
		else
			echo "  It wrote nothing to standard error."
		fi
		print_columns
		rl_legend "$CLUES"
		exit 1
	fi
	echo "rust_diff: FAIL — memory/UB error on a fuzz input (the harness $RL_WHY; fn=$FN, seed=$SEED)"
	echo ""
	crash_where
	echo ""
	# What the report is, from its own first line (rl_sanitizer_kind): the
	# paragraph below explained an access outside a block, READ or WRITE,
	# whatever the report said. It stays for that kind, and for a
	# report whose kind no line names.
	if [ "$RL_SAN_OOB" = 1 ] || [ -z "$RL_SAN_KIND" ]; then
		echo "  The harness was built with AddressSanitizer and UBSan. They stop the run"
		echo "  at the first access outside a block the program owns, or the first"
		echo "  undefined operation, and the report says which: READ or WRITE, how many"
		echo "  bytes, and how far outside which block. The answer can still have been"
		echo "  right -- this layer does not compare values, the diff layer does -- so"
		echo "  what to look at is what the code touched, not what it printed. The top"
		echo "  frame below is where the access happened."
	else
		echo "  The sanitizer stopped the harness when it $(rl_sanitizer_about)."
		rl_sanitizer_explain "  "
		echo "  The answer can still have been right -- this layer does not compare"
		echo "  values, the diff layer does. The first frame below in your file is"
		echo "  where it happened."
	fi
	# A file and a line only when the pinned symbolizer named them: without
	# --symbolizer every frame is an address, and saying otherwise would send
	# a student looking for a line number that was never printed.
	if [ -n "$SYMBOLIZER" ]; then
		echo "  Each frame names a function and, where it is yours, a file and a line."
	fi
	echo "----- sanitizer report -----"
	rl_sanitizer_report "$T/serr" 45 sanitizer-report.txt "  "
	print_columns
	rl_legend "$CLUES"
	exit 1
fi

# Replay the reference's inputs through the student harness. Do NOT abort on a
# non-zero exit: a crash/UB on some fuzz input is itself a finding to report.
run_student "$T/act"
rc=$?
rl_classify "$rc"
not_started

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

if [ "$RL_CAUSE" = timeout ]; then
	# What it had answered comes first: an answer that already differs is a
	# verdict whatever the machine was doing, so the report then does not
	# read as "ran out of time" alone (RL_WRONG, tools/runner_lib.sh).
	_answered=none
	if [ "$NDONE" -gt 0 ]; then
		if prefix_matched "$NDONE"; then
			_answered=matched
		else
			_answered=differs
			RL_WRONG=$(head -n "$NDONE" "$T/exp" | LC_ALL=C awk '
				NR == FNR { a[FNR] = $0; next }
				$0 != a[FNR] { c++ }
				END { print c + 0 }' "$T/act.done" -)
		fi
	fi
	rl_overrun "the input at or after case $((NDONE + 1)) of $NTOTAL (fn=$FN, seed=$SEED)"
	echo ""
	case "$_answered" in
		none)
			echo "  It had flushed no answer at all, so nothing was compared." ;;
		matched)
			echo "  The $NDONE answers it had flushed all matched the reference, so this is not a"
			echo "  wrong answer so far: the run never finished, and nothing past that point"
			echo "  was compared." ;;
		*)
			echo "  $RL_WRONG of the $NDONE answers it had flushed already differ from the reference,"
			echo "  and the run never finished; nothing past that point was compared." ;;
	esac
	reproducer "$NDONE" "$NTOTAL"
	[ -s "$T/serr" ] && { echo ""; echo "  stderr:"; rl_excerpt "$T/serr" 12 harness-stderr.txt; }
	print_columns
	rl_legend "$CLUES"
	exit 1
fi

if [ "$RL_CAUSE" = runaway ]; then
	echo "rust_diff: FAIL — the harness kept printing past $((OUT_BLOCKS * 512)) bytes and was stopped"
	echo "           (fn=$FN, seed=$SEED). A correct one prints one line per input; this one"
	echo "           printed without end -- a loop whose exit condition is never met."
	reproducer "$NDONE" "$NTOTAL"
	print_columns
	rl_legend "$CLUES"
	exit 1
fi

if [ "$RL_CAUSE" = signal ]; then
	echo "rust_diff: FAIL — the student harness $RL_WHY"
	echo "           (fn=$FN, seed=$SEED)"
	echo ""
	echo "  Output stopped after $NDONE of $NTOTAL cases. So this is not a wrong answer"
	echo "  -- it is a program that stopped existing partway through, and nothing past"
	echo "  that point was compared."
	if prefix_matched "$NDONE"; then
		echo "  Everything it had printed up to there matched."
	elif [ "$NDONE" -gt 0 ]; then
		echo "  Some of what it had printed up to there already differs, too."
	fi
	if [ "$RL_SIG" = 9 ]; then
		echo ""
		echo "  SIGKILL comes from outside the process -- it cannot be caught, and"
		echo "  almost nothing chooses it for itself. With no time limit of this"
		echo "  runner's own involved, that leaves the kernel's out-of-memory killer:"
		echo "  memory that is never freed and grows with every case."
	fi
	# The harness says which case it died on (died_case); one that does
	# not -- a harness reading its corpus without tools/diffio.h -- gets the
	# first cases it had not answered, and the words that say how far off
	# those may be.
	if died_case; then
		echo ""
		show_died_case
	else
		reproducer "$NDONE" "$NTOTAL" died
	fi
	[ -s "$T/serr" ] && { echo ""; echo "  stderr:"; rl_excerpt "$T/serr" 12 harness-stderr.txt; }
	print_columns
	rl_legend "$CLUES"
	exit 1
fi

if [ "$rc" -ne 0 ] && cmp -s "$T/exp" "$T/act"; then
	# Right answers, wrong ending. Kept apart from a divergence for the same
	# reason progname_test.sh separates them: "it printed everything correctly
	# and then returned non-zero" is a different bug from "it printed the wrong
	# thing", and merging the two hides which one happened.
	echo "rust_diff: FAIL — every one of the $NTOTAL cases matched the reference, but"
	echo "           the harness exited $rc rather than 0 (fn=$FN, seed=$SEED)"
	[ -s "$T/serr" ] && { echo "  stderr:"; rl_excerpt "$T/serr" 8 harness-stderr.txt; }
	exit 1
fi

echo "rust_diff: FAIL — student output diverges from the reference (fn=$FN, seed=$SEED)"
if [ "$rc" -ne 0 ]; then
	echo "  NOTE: the student harness $RL_WHY (possible crash / UB on a fuzz input)"
	[ -s "$T/serr" ] && { echo "  stderr:"; rl_excerpt "$T/serr" 8 harness-stderr.txt; }
fi
echo "----- first divergences (reference vs student; leading columns are the inputs) -----"
# exp and act are 1:1 aligned (the harness echoes each input line in order); show
# the full line from each so the format's own columns are visible regardless of
# how many fields it has.
#
# EVERY BYTE VISIBLE (rl_vis, tools/runner_lib.sh). The lines were printed raw,
# and an output column can hold any byte: C 04 ex04's bases carry control bytes
# on purpose, where a base check that refuses them is wrong (finding 061). Raw,
# a reference that wrote \x01\x02 and a student that wrote nothing printed as
# the same line on a terminal, and an ESC in either could repaint it. The awk
# only picks the lines and keeps each, unprinted, for rl_vis to render.
# A student line past the reference's last has no reference line to show, and
# an empty one read as "the reference printed nothing here".
LC_ALL=C awk -v d="$T/div" '
	NR == FNR { ref[FNR] = $0; nref = FNR; next }
	FNR > nref || $0 != ref[FNR] {
		if (n == 15) { more = 1; exit }
		n++
		if (FNR <= nref) { printf "%s", ref[FNR] > (d "." n ".ref"); close(d "." n ".ref") }
		printf "%s", $0 > (d "." n ".act"); close(d "." n ".act")
	}
	END { print n + 0, more + 0 }
' "$T/exp" "$T/act" > "$T/div.n"
read -r _nd _more < "$T/div.n"
# div_line FILE -- one kept line, every byte visible, and a $ where it ended,
# as the output tables mark a line's end: a space at the end of a line is
# no byte the renderer escapes, and "61\ta " read exactly as "61\ta" (V49).
# A $ in the line itself is rendered \x24, so the mark is never the text.
#
# A LINE PAST SHOW_W BYTES is shown to its first SHOW_W, the rest counted and
# no $ after it (rl_vis's WIDTH), and the bytes where the two lines part are
# shown under the pair (rl_diff_window), since a cut can fall before them.
# The corpora hold lines of 20 to 80 KB early in the file (finding 041), and
# a common bug printed every one of the first fifteen whole: a first red log
# of hundreds of KB of hex. Only what is shown is cut; the lines were compared
# whole, and are kept whole as test outputs.
div_line() {
	if [ ! -s "$1" ]; then
		printf '(an empty line)'
		return
	fi
	rl_vis arg "" "$SHOW_W" < "$1"
	[ "$(wc -c < "$1")" -gt "$SHOW_W" ] || printf '$'
}
div_long() {  # div_long FILE -- true when FILE is cut when shown
	[ -f "$1" ] && [ "$(wc -c < "$1")" -gt "$SHOW_W" ]
}
# Rendered first, then printed with the legend of what they show
# (rl_vis_legend), read off the lines alone (div.lines): a fixed one named a
# tab and a backslash under lines that held neither, and a window under a
# pair carries a legend of its own.
div_shown() {  # div_shown TEXT -- one line of the list, and of div.lines
	printf '%s\n' "$1" >> "$T/div.shown"
	printf '%s\n' "$1" >> "$T/div.lines"
}
: > "$T/div.shown"
: > "$T/div.lines"
_i=1
while [ "$_i" -le "$_nd" ]; do
	if [ -f "$T/div.$_i.ref" ]; then
		div_shown "  reference: $(div_line "$T/div.$_i.ref")"
	else
		div_shown "  reference: (no line -- its $NTOTAL cases end before this one)"
	fi
	div_shown "  student  : $(div_line "$T/div.$_i.act")"
	if div_long "$T/div.$_i.ref" || div_long "$T/div.$_i.act"; then
		[ ! -f "$T/div.$_i.ref" ] ||
			rl_diff_window "$T/div.$_i.ref" "$T/div.$_i.act" "    " reference student >> "$T/div.shown"
		if rl_save "$T/div.$_i.act" "divergence-$_i-student.txt"; then
			_kept="divergence-$_i-student.txt"
			! [ -f "$T/div.$_i.ref" ] || ! rl_save "$T/div.$_i.ref" "divergence-$_i-reference.txt" ||
				_kept="divergence-$_i-reference.txt and $_kept"
			echo "    the whole lines: $_kept, in ${RL_SAVED%/*}/" >> "$T/div.shown"
		else
			echo "    (only a run under bazel test keeps the whole lines)" >> "$T/div.shown"
		fi
	fi
	_i=$((_i + 1))
done
cat "$T/div.shown"
[ "$_more" = 1 ] && echo "  ..."
# The note on the $ only under a line that ends in one: a line cut short ends
# in its count of bytes left out, and a $ the line itself holds is \x24.
! grep -q '\$$' "$T/div.lines" || echo "  In the lines above, \$ is where a line ended."
rl_vis_legend "$T/div.lines"
# No line differs, yet the files do. The list was empty then, under a
# headline saying "diverges". Output past the reference's last line is a line
# the list shows, so that leaves two ways: the output is the reference's cut
# short (the run ended early -- an exit() in the function, or its standard
# output closed), or the two differ in a byte no line comparison sees.
if [ "$_nd" -eq 0 ]; then
	_eb=$(wc -c < "$T/exp" | tr -d ' ')
	_ab=$(wc -c < "$T/act" | tr -d ' ')
	if [ "$rc" -eq 0 ]; then _how="ended with exit 0"; else _how="ended as the NOTE above says"; fi
	if [ "$_ab" -lt "$_eb" ] && head -c "$_ab" "$T/exp" | cmp -s - "$T/act"; then
		echo "  No line it printed differs: it printed the first $_ab of the reference's"
		echo "  $_eb bytes and $_how, so case $((NDONE + 1)) of $NTOTAL and every"
		echo "  case after it were never answered."
		reproducer "$NDONE" "$NTOTAL"
	else
		echo "  No line differs as text, yet the bytes do -- a byte that ends a line"
		echo "  early for a line reader, such as a NUL. Where, in cmp's words:"
		# C's words, which every machine has: GNU cmp says "byte" under a
		# UTF-8 locale and "char" under C or a locale that is missing.
		printf '    %s\n' "$(LC_ALL=C cmp "$T/exp" "$T/act" 2>&1 | sed "s|$T/||g")"
	fi
fi
print_columns
rl_legend "$CLUES"
exit 1
