#!/bin/sh
# Run an ASan/UBSan-instrumented PROGRAM with a case's argv and assert it
# reports nothing (tag "asan").
#
# c_function exercises get three memory layers (the _asan twin library, the
# c_mem_check probe, and the diff_asan crash-fuzz). c_program exercises got
# none: c-06, c-10 and c-11 ex05 — twelve exercises that read files, walk argv
# and index buffers — were never built with a sanitizer at all. The valgrind
# layer only covers the ones that malloc, and stdout diffing cannot see an
# out-of-bounds read that happens to return the right bytes.
#
# Value correctness is NOT checked here; the *_output layer already does that.
# This asks only whether the same run is memory-clean, so it stays meaningful
# even while the output is still wrong.
#
# Usage:
#   asan_run.sh --bin PATH [--label NAME] [--stdin FILE] [-- ARGS...]
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "asan_run.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require grep head mktemp rm sed

BIN=""
LABEL=""
STDIN_FILE=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "asan_run.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--stdin) need "$1" "$#"; STDIN_FILE="$2"; shift 2 ;;
		--) shift; break ;;
		*) echo "asan_run.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$BIN" ] || { echo "asan_run.sh: --bin is required" >&2; exit 2; }

# Check the binary is actually runnable BEFORE running it. Everything below
# reasons about a wait status, and a status produced by a failed exec describes
# the shell, not the student's program — a missing runfile or a non-executable
# path would otherwise be laundered into evidence about memory safety. Catching
# it here also removes the commonest cause of the ambiguous 127 handled further
# down, leaving that branch to deal only with the cases we genuinely cannot tell
# apart.
# -f as well as -x: `[ -x DIR ]` is TRUE for a directory, so `--bin some/dir`
# used to slip past this and land on the 126 branch with wording about a
# permission problem it did not have.
[ -f "$BIN" ] && [ -x "$BIN" ] || {
	echo "asan_run.sh: --bin '$BIN' is missing or not executable" >&2
	exit 2
}

# The same reasoning one step further, for the other input that can stop the run
# before it starts. --stdin names a fixture out of the target's `data`; if it is
# absent or unreadable the `< "$STDIN_FILE"` redirection below fails, the program
# is never started, and the shell's small non-zero status walks straight down to
# the success line — observed as "OK — memory-clean on this case (exit 2)" for a
# case that never ran. diff_output.sh takes the same redirection unguarded and
# can afford to, because there a never-started program also produces no output
# and fails its comparison; this layer has no second signal to catch it with,
# since the exit status IS the entire verdict here.
[ -z "$STDIN_FILE" ] || [ -r "$STDIN_FILE" ] || {
	echo "asan_run.sh: --stdin '$STDIN_FILE' is missing or unreadable" >&2
	exit 2
}

# detect_leaks=0 on purpose: a leak is the valgrind layer's finding, and letting
# LeakSanitizer abort here would red THIS layer under an "out of bounds"
# headline for what is actually a missing free.
export ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:${ASAN_OPTIONS:-}"
export UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1:${UBSAN_OPTIONS:-}"

# Same reasoning as the --bin check: an unchecked mktemp failure leaves ERR
# empty, the `2> "$ERR"` redirection below then fails, the program is never
# started, and the resulting shell status is small and non-zero — which lands on
# the success line as "memory-clean". Fail loudly here so a broken TMPDIR cannot
# masquerade as a passing sanitizer run.
ERR=$(mktemp) || {
	echo "asan_run.sh: cannot create a temporary file for the program's stderr" >&2
	exit 2
}
[ -n "$ERR" ] || { echo "asan_run.sh: mktemp returned no path" >&2; exit 2; }
trap 'rm -f "$ERR"' EXIT INT TERM

# An inner timeout, well under Bazel's, so an infinite loop is reported as one
# instead of surfacing as an opaque Bazel timeout. `timeout` is coreutils and can
# be absent (a slim image, a BSD box without coreutils), and calling it
# unconditionally was silently fatal to this whole layer: the shell answered 127
# for EVERY case, which is below 128 so the crash branch never fired, is neither
# 124 nor 137 so the timeout branch never fired, and "timeout: not found" matches
# no sanitizer pattern — so every run fell through to the success line and
# reported the program "memory-clean" without ever having executed it. Probe
# first and run the binary bare when the tool is missing, the same way
# diff_output.sh does. The fallback costs us the inner timeout, so on such a box
# a hang surfaces as Bazel's own timeout instead of the message below; a wrong
# headline for a real hang is a far cheaper failure than a green light for a run
# that did not happen.
TMO=30
if command -v timeout >/dev/null 2>&1; then
	RUNNER="timeout -s KILL $TMO"
else
	RUNNER=""
fi

if [ -n "$STDIN_FILE" ]; then
	$RUNNER "$BIN" "$@" < "$STDIN_FILE" > /dev/null 2> "$ERR"
else
	$RUNNER "$BIN" "$@" > /dev/null 2> "$ERR"
fi
RC=$?

# A sanitizer abort is 128+SIGABRT. The program's own non-zero exits (a usage
# error, a missing file) are below 128 and are NOT a finding here — this layer
# is about memory, not about exit status. The one exception is 126/127, handled
# further down: those are the statuses that mean the program may never have run,
# so they cannot be waved through as "just an exit status".
if [ "$RC" -eq 137 ] || [ "$RC" -eq 124 ]; then
	echo "asan_run: FAIL — ${LABEL:-the program} did not finish within ${TMO}s (infinite loop?)"
	exit 1
fi

if grep -qE "AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:" "$ERR" 2>/dev/null; then
	echo "asan_run: FAIL — ${LABEL:-the program} hit a memory error or undefined behaviour."
	echo "          The output layer cannot see this: an out-of-bounds read can"
	echo "          still return the bytes you expected."
	echo "---------------- sanitizer report ----------------"
	sed 's/^/  /' "$ERR" | head -40
	exit 1
fi

# 126 and 127 are the statuses a shell (and `timeout`) returns when the exec
# itself failed: the binary could not be started at all — a missing shared
# library, a wrong-architecture object, a runfiles path that disappeared between
# analysis and execution. Nothing ran, so nothing was measured.
#
# They are ALSO legal exit statuses for the student's own program: `return (127);`
# from main is perfectly valid C. A wait status carries no flag distinguishing
# "the kernel could not exec this" from "the program chose to return this", and
# once the process is gone that information is unrecoverable — so this branch
# cannot honestly tell the two apart, and does not pretend to. Given the tie, it
# takes the direction whose worst case is cheapest: exit 2 (harness broke, a
# human looks) rather than the old fall-through to "memory-clean", which deleted
# this layer's entire coverage for the case while displaying a pass. A program
# that may not have run is not evidence of memory safety.
#
# Checked AFTER the sanitizer grep on purpose: if a report did land in stderr the
# binary demonstrably ran, and a real finding outranks this ambiguity. The
# captured stderr is echoed below because it usually resolves the ambiguity for
# whoever reads the log — a failed exec leaves the loader's complaint there,
# whereas a deliberate exit(127) normally leaves it empty.
if [ "$RC" -eq 127 ] || [ "$RC" -eq 126 ]; then
	echo "asan_run.sh: ${LABEL:-the program} ended with status $RC, which means either" >&2
	echo "             'the binary could not be executed' or 'the program returned $RC'." >&2
	echo "             These are indistinguishable from a wait status, so this is" >&2
	echo "             reported as harness breakage rather than a pass: a run that may" >&2
	echo "             never have happened proves nothing about memory safety." >&2
	if [ -s "$ERR" ]; then
		echo "             ----- the program's stderr -----" >&2
		sed 's/^/               /' "$ERR" | head -20 >&2
	fi
	exit 2
fi

if [ "$RC" -gt 128 ]; then
	echo "asan_run: FAIL — ${LABEL:-the program} died on signal $((RC - 128))."
	[ -s "$ERR" ] && sed 's/^/  /' "$ERR" | head -20
	exit 1
fi

echo "asan_run: OK — ${LABEL:-the program} is memory-clean on this case (exit $RC)"
exit 0
