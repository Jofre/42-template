#!/bin/sh
# Run a deliverable under valgrind/memcheck and fail on any leak or invalid
# memory access (tag "valgrind").
#
# This is the only layer in the suite that can see a block that was allocated
# and then never accounted for. A leak changes no output byte, returns no error
# and crashes nothing, so every diff layer and every sanitizer layer stays green
# on a program that loses every allocation it makes (rust_diff.sh and
# asan_run.sh both set detect_leaks=0 precisely so that leaks are THIS layer's
# finding and not a confusing "out of bounds" headline in theirs). The malloc
# modules are graded on exactly that, which is why every exercise whose subject
# authorises malloc carries this test -- `c_function(malloc = True)` is what
# emits it, so the set follows the subjects rather than a list kept here.
#
# What the exit status means to the caller:
#   0  valgrind was clean — or the layer deliberately SKIPPED and said so
#   1  the student's code has a finding
#   2  the harness itself could not run the check
# Keeping 2 for harness breakage matters here more than anywhere else: this
# script used to conflate valgrind's verdict (--error-exitcode), the child dying
# on a signal, and valgrind not being installed at all (127) into one sentence,
# so a stale container image printed a red MEMORY verdict at students who had
# written nothing wrong.
#
# Usage:
#   valgrind_test.sh --bin PATH --valgrind PATH --valgrind-tools FILE
#                    [--label NAME] [--stdin FILE] [--clues FILE]
#                    [--timeout SECS]
#                    [--gate-differ FILE --gate-bin PATH --gate-expected FILE
#                     [--gate-stdin FILE] [--gate-stream NAME]
#                     [--gate-sanitize] [--gate-labeled]]
#                    [-- PROG ARGS...]
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "valgrind_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require basename cut dirname grep head mktemp readlink rm sed

BIN=""
LABEL=""
STDIN_FILE=""
CLUES=""
# valgrind runs the program on a synthetic CPU: 20-50x slower than native is
# normal, so the inner budget is deliberately looser than run_check.sh's 20s and
# diff_output.sh's 30s. It still has to be well under Bazel's own timeout, or an
# infinite loop surfaces as an opaque Bazel kill with nothing a student can act
# on. Every exercise wired to this layer finishes in well under a second.
TIMEOUT="${VALGRIND_TIMEOUT:-60}"
GATE_DIFFER=""
GATE_BIN=""
GATE_EXPECTED=""
GATE_PASS=""
VALGRIND=""
VGTOOLS=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "valgrind_test.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--valgrind) need "$1" "$#"; VALGRIND="$2"; shift 2 ;;
		--valgrind-tools) need "$1" "$#"; VGTOOLS="$2"; shift 2 ;;
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--stdin) need "$1" "$#"; STDIN_FILE="$2"; shift 2 ;;
		--clues) need "$1" "$#"; CLUES="$2"; shift 2 ;;
		--timeout) need "$1" "$#"; TIMEOUT="$2"; shift 2 ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-stdin) need "$1" "$#"; GATE_PASS="$GATE_PASS --stdin $2"; shift 2 ;;
		--gate-stream) need "$1" "$#"; GATE_PASS="$GATE_PASS --stream $2"; shift 2 ;;
		--gate-sanitize) GATE_PASS="$GATE_PASS --sanitize"; shift ;;
		--gate-labeled) GATE_PASS="$GATE_PASS --labeled"; shift ;;
		--) shift; break ;;
		# The binary used to be accepted as a bare first argument. That shape is
		# gone: every caller passes --bin, and keeping a second spelling of the
		# same thing alive is how a reader learns that either is fine and then
		# copies the one nothing else uses.
		*) echo "valgrind_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$BIN" ] || { echo "valgrind_test.sh: --bin is required" >&2; exit 2; }
# An unreadable or non-executable path is a wiring mistake (a data dep that was
# never declared, a $(location) that resolved to a source file), not a student
# finding — valgrind would answer 127 for it and the old script printed that as
# "leaks/errors".
if ! [ -f "$BIN" ] || ! [ -x "$BIN" ]; then
	echo "valgrind_test.sh: not an executable file: $BIN" >&2
	exit 2
fi
[ -n "$LABEL" ] || LABEL="$(basename "$BIN")"

# ---------------------------------------------------------------------------
# The valgrind this layer runs is FETCHED AND PINNED, never found on PATH.
#
# It used to be `command -v valgrind`, and this is the layer where that mattered
# most: memcheck is the only thing in the suite that can see a leak, so its
# answer was the one most worth making independent of which box you sat at.
# There is no host fallback -- a missing --valgrind is a wiring error (exit 2),
# not a skip, because a skip here is indistinguishable from "no leaks".
[ -n "$VALGRIND" ] || {
	echo "valgrind_test.sh: --valgrind is required (the pinned valgrind.bin)" >&2
	echo "                  Pass \$(location @valgrind_ubuntu//:usr/bin/valgrind.bin)." >&2
	exit 2
}

# ABSOLUTISE BEFORE ANYTHING CHANGES DIRECTORY. Both paths arrive
# runfiles-relative, and every previous fetched tool in this repo was broken
# once by a later `cd` turning a working path into a missing one.
case "$VALGRIND" in
	/*) ;;
	*) VALGRIND="$PWD/$VALGRIND" ;;
esac

[ -f "$VALGRIND" ] && [ -x "$VALGRIND" ] || {
	echo "valgrind_test.sh: pinned valgrind is missing or not executable: $VALGRIND" >&2
	exit 2
}

# AND VERIFY IT CAN FIND ITS OWN TREE. This is the failure mode that has caught
# every fetched tool here at least once: a binary that cannot find part of
# itself does not necessarily fail -- it can fall back to the box's copy,
# report the pinned version, and go green. valgrind is packaged for
# /usr/libexec/valgrind and reads $VALGRIND_LIB to be told otherwise, so the
# check is that the directory exists AND holds the tool binary this layer runs.
# Checking the directory alone would pass on an empty one.
[ -n "$VGTOOLS" ] || {
	echo "valgrind_test.sh: --valgrind-tools is required (a file in valgrind's" >&2
	echo "                  own tool directory; it cannot start without one)" >&2
	exit 2
}
# The tool directory is derived from a FILE inside it, not passed as a
# directory, and that is deliberate: `$(location x)/..` walks through a file
# rather than naming its parent, and `cd && pwd` stops at the runfiles tree,
# whose directories are real while the files in them are symlinks. Resolving the
# file with readlink -f and taking ITS directory is the one form that survives
# both. This repo has been bitten by the other two.
VGTOOLS=$(readlink -f "$VGTOOLS" 2> /dev/null || echo "$VGTOOLS")
VGLIB=$(dirname "$VGTOOLS")
[ -f "$VGLIB/memcheck-amd64-linux" ] || {
	echo "valgrind_test.sh: $VGLIB does not hold memcheck-amd64-linux, so the" >&2
	echo "                  pinned valgrind cannot run its own tool. This is a" >&2
	echo "                  wiring error, not a student finding." >&2
	exit 2
}
VALGRIND_LIB="$VGLIB"
export VALGRIND_LIB

# ---------------------------------------------------------------------------
# Correctness gate: run the exercise's own curated fixture first, and SKIP while
# it is still red. Same shape, same argument names and the same fail-open rule
# as tools/rust_diff.sh, so both can be wired from defs.bzl identically.
#
# Alone among the rigour layers this one had no gate, which is the worst place
# to be missing one: a student whose function is still a stub was met with raw
# "indirectly lost" loss records — a report about allocations made by code they
# are about to rewrite — instead of "your output layer is red, fix that first".
# And an unfinished function is frequently memory-clean by accident (a stub that
# allocates nothing leaks nothing), so this layer teaches nothing either way
# until the fixture is green.
#
# Fails OPEN by design: no gate supplied, or a gate that cannot run, means the
# memory check still runs. A gate that wrongly suppressed this layer would turn
# a genuine leak green, which is far worse than duplicating a red.
if [ "${NO_SKIP:-0}" = "1" ]; then
	GATE_DIFFER=""
fi

if [ -n "$GATE_DIFFER" ] && [ -n "$GATE_BIN" ] && [ -n "$GATE_EXPECTED" ] &&
	[ -x "$GATE_BIN" ] && [ -f "$GATE_EXPECTED" ]; then
	# The program's own argv is forwarded to the gate as well: this layer can be
	# emitted per argv case (defs.bzl's _emit_cases), and the fixture that case
	# is gated on is the one produced by the SAME arguments.
	# shellcheck disable=SC2086
	if ! sh "$GATE_DIFFER" --bin "$GATE_BIN" --expected "$GATE_EXPECTED" \
			$GATE_PASS -- "$@" >/dev/null 2>&1; then
		echo "valgrind_test: SKIP — this exercise's own output fixture is not"
		echo "               passing yet."
		echo ""
		echo "  A memory report on a function that still returns the wrong answer"
		echo "  describes allocations made by code you are about to rewrite. The"
		echo "  *_output layer is the one worth reading right now: a labelled"
		echo "  table, cases ordered from trivial to subtle, hints attached."
		echo "  Get it green and this layer starts checking something new."
		echo ""
		echo "  (NO_SKIP=1 forces every gated layer to run anyway:"
		echo "   bazel test //... --test_env=NO_SKIP=1)"
		exit 0
	fi
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# valgrind's report goes to its own --log-file rather than being merged into the
# child's stderr. Mixing them (the old '2> "$LOG"') meant the program's own
# diagnostics were classified as valgrind findings and vice versa, and it made
# the ERROR SUMMARY line impossible to trust.
VGLOG="$WORK/vg.log"
CHILDERR="$WORK/child.err"

# Stdin is pinned to /dev/null unless the caller names a file. Inheriting the
# test runner's stdin makes a program that reads it behave differently under
# Bazel, under `bazel run` and in a terminal — a memory layer must not be the
# place where that difference first shows up.
[ -n "$STDIN_FILE" ] || STDIN_FILE=/dev/null

# An inner timeout so an infinite loop is reported as one. Not every host has
# GNU coreutils' `timeout`, so probe for it and run bare if it is absent — same
# pattern as diff_output.sh and run_check.sh.
if command -v timeout >/dev/null 2>&1; then
	RUNNER="timeout -s KILL $TIMEOUT"
else
	RUNNER=""
fi

# Output cap. This runs code nobody has verified, and both of the files it
# writes are unbounded: a loop that walks off the end of a block records a fresh
# invalid-access context per call site, and a program that prints its own
# diagnostics in a runaway loop fills CHILDERR at page-cache speed. Either can
# put hundreds of megabytes into the test tmpdir before Bazel's timeout notices.
# As in diff_output.sh and run_check.sh, `ulimit -f` bounds it at the source:
# the kernel kills the writer with SIGXFSZ (exit 153) the moment it goes past
# the budget, so nothing can fill the disk. It counts 512-byte blocks.
CAP="${VALGRIND_LOG_CAP:-8388608}"
BLOCKS=$(( CAP / 512 + 2 ))

# --error-exitcode=42 is the whole point of the run: it makes "valgrind found
# something" a value no child process would plausibly return by itself, so the
# verdict can be told apart from the program's own exit status further down.
# --show-leak-kinds/--errors-for-leak-kinds=all count still-reachable blocks as
# errors too, because "the process was about to exit anyway" is not the standard
# the malloc modules are graded against.
# --track-origins=yes costs roughly 2x runtime on programs this small and buys
# the one thing that makes an uninitialised-value report actionable: where the
# uninitialised bytes came from.
# shellcheck disable=SC2086
(
	ulimit -f "$BLOCKS" 2>/dev/null
	$RUNNER "$VALGRIND" \
		--leak-check=full \
		--show-leak-kinds=all \
		--errors-for-leak-kinds=all \
		--track-origins=yes \
		--error-exitcode=42 \
		--log-file="$VGLOG" \
		"$BIN" "$@" < "$STDIN_FILE" > /dev/null 2> "$CHILDERR"
)
RC=$?

[ -f "$VGLOG" ] || : > "$VGLOG"

# The classes memcheck reports, in the words it reports them. The leak patterns
# are anchored on "in loss record" deliberately: the LEAK SUMMARY block printed
# at the end of EVERY report contains the words "definitely lost:" even when the
# count is zero, so matching the bare phrase would classify a pure invalid-read
# run as a leak.
ERR_RE='Invalid read of size|Invalid write of size|Invalid free\(\)|Mismatched free\(\)|uninitialised value|uninitialised byte|are definitely lost in loss record|are indirectly lost in loss record|are possibly lost in loss record|are still reachable in loss record'

log_has_errors() {
	grep -qE "$ERR_RE" "$VGLOG" 2>/dev/null
}

# Lead with the NAME of the bug class, then explain what that class means and
# how to read the record — never what to change. The raw log on its own is the
# reason this layer had a reputation for being unreadable: a first-year reading
# "40 bytes in 1 blocks are indirectly lost in loss record 2 of 3" has no way to
# know that it is a symptom of loss record 3 and not a separate mistake.
report_findings() {
	_first=$(grep -E "$ERR_RE" "$VGLOG" 2>/dev/null | head -1)
	# Run-time errors are printed as they happen and the leak records only at
	# exit, so the first match is genuinely the first thing that went wrong —
	# for everything except the leaks. Within the leak report valgrind orders
	# the records by block size, not by cause, so the first one is routinely an
	# "indirectly lost" child of a record further down: the three-line leak from
	# a two-level allocation leads with the inner block every time. Re-pick the
	# leak kind by root cause so the headline names the mistake, not its
	# consequence.
	case "$_first" in
	*"in loss record"*)
		for _k in 'are definitely lost in loss record' \
				'are possibly lost in loss record' \
				'are indirectly lost in loss record' \
				'are still reachable in loss record'; do
			if grep -qF "$_k" "$VGLOG" 2>/dev/null; then
				_first="$_k"
				break
			fi
		done
		;;
	esac
	case "$_first" in
	*"Invalid write of size"*)
		echo "  INVALID WRITE — the program stored a byte outside any block it"
		echo "  owns. This is the most expensive bug class in C: the heap's own"
		echo "  bookkeeping lives immediately after each block, so a program that"
		echo "  writes one byte too far usually keeps running and dies much later,"
		echo "  somewhere with no connection to the code at fault."
		echo "  The 'Address 0x... is N bytes after a block of size M' line under"
		echo "  the trace names the allocation that was overrun and by how much."
		;;
	*"Invalid read of size"*)
		echo "  INVALID READ — the program read from an address that is not inside"
		echo "  any block it owns: past the end (or before the start) of an"
		echo "  allocation, or inside one whose lifetime had already ended. What"
		echo "  comes back is whatever happened to be in that memory, which is why"
		echo "  THE OUTPUT CAN STILL LOOK CORRECT and no diff layer sees this."
		echo "  The 'Address 0x...' line under the trace names the allocation that"
		echo "  was overrun and the size it was requested with."
		;;
	*"Invalid free()"*|*"Mismatched free()"*)
		echo "  INVALID FREE — the program handed the allocator an address that is"
		echo "  not the start of a live block: one already released, one that was"
		echo "  advanced or reassigned after the allocator returned it, or one that"
		echo "  never came from the allocator at all."
		echo "  Read the trace as 'here is the release', then find every place that"
		echo "  same pointer variable is assigned between the allocation and it."
		;;
	*"uninitialised value"*|*"uninitialised byte"*)
		echo "  UNINITIALISED VALUE — a decision (a branch, or a syscall such as"
		echo "  the write() this project's output goes through) depended on bytes"
		echo "  that were never given a value. Fresh memory from the allocator is"
		echo "  not zeroed; it holds whatever the previous owner left there."
		echo "  This is the class that passes on your machine and fails on the"
		echo "  Moulinette, because the leftover garbage differs between runs."
		echo "  --track-origins is on, so the report also says where the"
		echo "  uninitialised bytes came from ('Uninitialised value was created"
		echo "  by a heap allocation')."
		;;
	*"are definitely lost in loss record"*)
		echo "  DEFINITELY LOST — a block this program allocated was unreachable"
		echo "  when the process ended: no live pointer anywhere still held its"
		echo "  address. The address was overwritten, went out of scope, or was"
		echo "  never propagated back to whatever owns that block's lifetime."
		echo "  The trace below is where the block was ALLOCATED, not where it was"
		echo "  lost. Follow that pointer forward through every path out of the"
		echo "  function, the early returns and the error paths included."
		;;
	*"are indirectly lost in loss record"*)
		echo "  INDIRECTLY LOST — this block is reachable only through another"
		echo "  block that is itself lost: an array of pointers whose outer block"
		echo "  is lost takes every inner allocation down with it."
		echo "  These records are symptoms, not separate mistakes. Read the"
		echo "  'definitely lost' record for the OUTER block first; this count"
		echo "  normally falls to zero on its own once that one is accounted for."
		;;
	*"are possibly lost in loss record"*)
		echo "  POSSIBLY LOST — the only surviving pointer to the block points"
		echo "  somewhere INSIDE it rather than at its first byte, so the address"
		echo "  the allocator handed out no longer exists anywhere in the program."
		echo "  This is what a pointer that walks a block looks like when it is the"
		echo "  only copy that was kept."
		;;
	*"are still reachable in loss record"*)
		echo "  STILL REACHABLE — the block was never released, but a live pointer"
		echo "  still held its address at exit, so nothing lost track of it."
		echo "  This layer reports every leak kind on purpose. 'The process was"
		echo "  about to exit anyway' is not the standard the malloc modules are"
		echo "  graded against: a function that allocates is judged on whether the"
		echo "  memory is accounted for, not on whether the OS tidied up after it."
		;;
	*)
		echo "  valgrind reported an error it does not classify into one of the"
		echo "  usual leak/invalid-access shapes. Read the first block below: its"
		echo "  first line is memcheck's own name for what went wrong."
		;;
	esac
	echo ""
	echo "  Reading the trace: the top 'at' line is the innermost frame and is"
	echo "  often inside libc or valgrind's replacement allocator; the 'by' line"
	echo "  under it is your code. Fix the FIRST record and re-run — later records"
	echo "  are frequently consequences of it."
	echo ""
	echo "  ---------------- valgrind report ----------------"
	# The ==pid== column on every line and the four-line version/copyright banner
	# are pure noise to a reader looking for the record, and they pushed the
	# actual content out of the first screenful.
	sed 's/^==[0-9]*==[ ]\{0,1\}//' "$VGLOG" \
		| grep -vE '^(Memcheck, a memory error detector|Copyright \(C\)|Using Valgrind|Using \(and\)|Command:|Parent PID:|For lists of|For counts of|For a detailed)' \
		| sed -e '/./,$!d' -e 's/^/  /' \
		| head -60
	if [ -s "$CHILDERR" ]; then
		echo "  ---------------- the program's own stderr ----------------"
		sed 's/^/  /' "$CHILDERR" | head -10
	fi
	if [ -n "$CLUES" ] && [ -f "$CLUES" ]; then
		echo "  ---------------- hint ----------------"
		# Same clues.tsv the output layer uses; only the hint column is shown,
		# because this layer has no per-case table to attach hints to.
		cut -f1 "$CLUES" | grep -vE '^[[:space:]]*#|^[[:space:]]*$' \
			| head -3 | sed 's/^/   * /'
	fi
}

# --- exit status triage ----------------------------------------------------
# 153 is 128+SIGXFSZ: the ulimit above stopped a report that would not stop
# growing. That is a finding in itself, not a harness problem.
if [ "$RC" -eq 153 ]; then
	echo "valgrind_test: FAIL — $LABEL was stopped after writing more than $CAP"
	echo "               bytes (memory report plus its own stderr)."
	echo "  Output that size means something is repeating without end: either the"
	echo "  same invalid access recorded from call site after call site, or a loop"
	echo "  whose exit condition is never reached printing as it goes."
	echo "  Only the beginning survived the cut; nothing after it was read."
	report_findings
	exit 1
fi

if [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; then
	echo "valgrind_test: FAIL — $LABEL did not finish within ${TIMEOUT}s"
	echo "               (infinite loop?)."
	echo "  valgrind runs the program on a synthetic CPU, so it is 20-50x slower"
	echo "  than a normal run — but every exercise wired to this layer finishes"
	echo "  in well under a second even so. Nothing about memory was checked."
	exit 1
fi

# 126/127 are the "cannot execute" statuses: valgrind never got as far as
# running the program (a half-installed valgrind whose own vgpreload objects are
# missing, a binary whose interpreter does not exist, a wrapper script with no
# exec bit). Memcheck prints an ERROR SUMMARY line on every run it completes,
# including a clean one, so its ABSENCE is what separates this from a child that
# genuinely chose to return 126 or 127 — and it also stops the layer reporting a
# green pass over a program that never ran. Infrastructure, so exit 2: a red
# MEMORY verdict for a broken image is the exact defect this triage exists to
# prevent.
if { [ "$RC" -eq 127 ] || [ "$RC" -eq 126 ]; } &&
	! grep -q "ERROR SUMMARY" "$VGLOG" 2>/dev/null; then
	echo "valgrind_test.sh: valgrind could not run $BIN (exit $RC)" >&2
	[ -s "$VGLOG" ] && sed 's/^/  /' "$VGLOG" | head -10 >&2
	[ -s "$CHILDERR" ] && sed 's/^/  /' "$CHILDERR" | head -10 >&2
	echo "valgrind_test.sh: this is a harness/toolchain failure, not a student" >&2
	echo "                  finding — reporting it as one would be a lie." >&2
	exit 2
fi

# A status above 128 is 128+signal: the program was KILLED, it did not return.
# Under valgrind this is usually the crash that the records below already
# explain, so name the signal first and then show the findings.
if [ "$RC" -gt 128 ]; then
	SIG=$((RC - 128))
	case "$SIG" in
		4)  NAME="SIGILL (illegal instruction)" ;;
		6)  NAME="SIGABRT (abort: assertion, stack smashing, or a glibc heap error)" ;;
		8)  NAME="SIGFPE (arithmetic error, e.g. division or modulo by zero, or INT_MIN / -1)" ;;
		11) NAME="SIGSEGV (invalid memory access)" ;;
		13) NAME="SIGPIPE (wrote to a closed pipe)" ;;
		*)  NAME="signal $SIG" ;;
	esac
	echo " --------------------------------------------------"
	echo " CRASH: $LABEL died on $NAME."
	echo "        It was killed rather than returning, so this is a failure"
	echo "        regardless of what it managed to print first."
	if log_has_errors; then
		echo "        valgrind recorded what led to it:"
		echo ""
		report_findings
	elif [ -s "$CHILDERR" ]; then
		echo " ----- the program's stderr said -----"
		sed 's/^/   /' "$CHILDERR" | head -20
	fi
	exit 1
fi

# The verdict proper. Trust --error-exitcode first, but also believe the report:
# an older valgrind, or errors recorded in a forked child, can leave a non-zero
# ERROR SUMMARY behind while the exit status stays 0, and a memory layer that
# prints OK over a report full of loss records would be worse than no layer.
#
# 42 is valgrind's marker only when valgrind is the one who chose it. A child's
# own status is passed through untouched, so a program whose main returns 42
# arrives here as 42 over a completely clean report: measured, a two-line
# program that just returns 42 was told "is not memory-clean" above a log
# reading "All heap blocks were freed -- no leaks are possible / ERROR SUMMARY:
# 0 errors", and the classifier fell through to "an error it does not classify"
# because there was no error to classify. A student verdict handed to a
# memory-clean program is the same confusion between valgrind's answer and the
# child's that the rest of this triage exists to end, just in the last place it
# could still hide. Memcheck prints an ERROR SUMMARY on every run it completes
# and never says "0 errors" about a run it flagged, so that line settles it —
# and only an explicit zero does: a missing or truncated summary is not
# evidence of innocence, so anything else keeps the exit status' verdict.
VG_VERDICT=0
if [ "$RC" -eq 42 ]; then
	VG_VERDICT=1
	grep -q 'ERROR SUMMARY: 0 errors' "$VGLOG" 2>/dev/null && VG_VERDICT=0
fi

if [ "$VG_VERDICT" -eq 1 ] || log_has_errors; then
	echo "valgrind_test: FAIL — $LABEL is not memory-clean."
	report_findings
	echo ""
	echo "  What this layer checks is spelled out in the module's subject: the"
	echo "  paragraph on memory management is the standard being applied here."
	exit 1
fi

HEAP=$(grep 'total heap usage' "$VGLOG" 2>/dev/null | sed 's/^==[0-9]*== *//' | head -1)
if [ "$RC" -eq 0 ]; then
	echo "valgrind_test: OK — no leak, no invalid access, no uninitialised value ($LABEL)"
	[ -n "$HEAP" ] && echo "               ${HEAP}"
	exit 0
fi

# A non-zero status below 128 is the program's own choice of exit code, and
# valgrind found nothing. That is not this layer's business: run_check.sh and the
# *_output layer are the ones that assert exit status. Saying so out loud keeps
# the pass honest rather than silent — the old script failed the student here.
echo "valgrind_test: OK — no leak, no invalid access, no uninitialised value ($LABEL)"
[ -n "$HEAP" ] && echo "               ${HEAP}"
echo "               (the program chose to exit $RC; this layer checks memory,"
echo "                not exit status — that is the *_output layer's job.)"
exit 0
