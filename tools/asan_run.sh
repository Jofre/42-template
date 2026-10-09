#!/bin/sh
# Run an ASan/UBSan-instrumented PROGRAM with a case's argv and assert it
# reports nothing (tag "asan").
#
# c_function exercises get up to three memory layers: valgrind on the fixture,
# the c_mem_check probe under ASan, and c_diff's diff_asan crash-fuzz, whose
# ASan program is the only sanitized build of the unit (there is no separate
# _asan library: each program compiles the unit with its own flags). c_program
# exercises got none: c-06, c-10 and c-11 ex05 — twelve exercises that read
# files, walk argv and index buffers — were never built with a sanitizer at
# all. The valgrind layer only covers the ones that malloc, and stdout diffing
# cannot see an out-of-bounds read that happens to return the right bytes.
#
# Value correctness is NOT checked here; the *_output layer already does that.
# This asks only whether the same run is memory-clean, so it stays meaningful
# even while the output is still wrong.
#
# Usage:
#   asan_run.sh --bin PATH [--label NAME] [--stdin FILE] [--argv-file FILE]
#               [--run-as NAME [--cwd-file DEST=PATH]...] [--show-run PROG]
#               [--symbolizer PATH --symbolizer-lib PATH] [-- ARGS...]
#
# --argv-file, --run-as, --cwd-file and --show-run shape and show the run
# exactly as tools/diff_output.sh's options of those names do, so that a
# program case runs the same thing under the sanitizer as in its output test
# (c_program's "argv_file" and "cwd_files"; tools/runner_lib.sh's
# rl_argv_words, rl_rundir and rl_ran).
#
#   --symbolizer  the pinned llvm-symbolizer, and --symbolizer-lib a library
#                 file beside the libLLVM it loads, so each frame of a report
#                 names a function, a file and a line (tools/runner_lib.sh,
#                 rl_sanitizers).
#
#   --gate-differ PATH --gate-bin PATH --gate-expected FILE [--gate-arg WORD]...
#   [--gate-stdin FILE] [--gate-stream S] [--gate-sanitize] [--gate-labeled]
#   [--gate-label NAME]
#                 a SURVIVE case's gate (c_program, _survive_gate): SKIP while
#                 the exercise's first case at basic -- GATE-BIN run with the
#                 --gate-arg words, compared with --gate-expected by the
#                 differ -- is red. A survive case asks only that the program
#                 ends by itself, and a program nobody has written does, so
#                 its run under the sanitizer was green there too, saying
#                 nothing; diff_output.sh's survive case already waited
#                 (tools/runner_lib.sh's rl_gate, which fails open, and
#                 NO_SKIP=1 forces open).
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
require mktemp rm

# The shared runner helpers -- time budget, exiting signal traps, how a run
# ended, excerpts, hints -- written once in tools/runner_lib.sh.
RL_NAME=asan_run
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "asan_run.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"

BIN=""
LABEL=""
STDIN_FILE=""
ARGV_FILE=""
RUN_AS=""
CWD_FILES=""
SHOW_RUN=""
SYMBOLIZER=""
SYMBOLIZER_LIB=""
GATE_DIFFER=""; GATE_BIN=""; GATE_EXPECTED=""; GATE_ARGS=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "asan_run.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--stdin) need "$1" "$#"; STDIN_FILE="$2"; shift 2 ;;
		--argv-file) need "$1" "$#"; ARGV_FILE="$2"; shift 2 ;;
		--run-as) need "$1" "$#"; RUN_AS="$2"; shift 2 ;;
		--cwd-file) need "$1" "$#"; CWD_FILES="$CWD_FILES
$2"; shift 2 ;;
		--show-run) need "$1" "$#"; SHOW_RUN="$2"; shift 2 ;;
		--symbolizer) need "$1" "$#"; SYMBOLIZER="$2"; shift 2 ;;
		--symbolizer-lib) need "$1" "$#"; SYMBOLIZER_LIB="$2"; shift 2 ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-arg) need "$1" "$#"; rl_list_add GATE_ARGS "$2"; shift 2 ;;
		--gate-stdin) need "$1" "$#"; rl_list_add RL_GATE_PASS --stdin "$2"; shift 2 ;;
		--gate-stream) need "$1" "$#"; rl_list_add RL_GATE_PASS --stream "$2"; shift 2 ;;
		--gate-sanitize) rl_list_add RL_GATE_PASS --sanitize; shift ;;
		--gate-labeled) rl_list_add RL_GATE_PASS --labeled; shift ;;
		--gate-label) need "$1" "$#"; RL_GATE_LABEL="$2"; shift 2 ;;
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
# The same for the other two inputs a case can shape its run with: a run with
# fewer arguments, or from another folder, is not the case's run.
[ -z "$ARGV_FILE" ] || [ -r "$ARGV_FILE" ] || {
	echo "asan_run.sh: --argv-file '$ARGV_FILE' is missing or unreadable" >&2
	exit 2
}
if [ -n "$CWD_FILES" ] && [ -z "$RUN_AS" ]; then
	echo "asan_run.sh: --cwd-file stages a file in the folder --run-as runs the program from" >&2
	exit 2
fi
case "$RUN_AS" in
	*/* | . | ..)
		echo "asan_run.sh: --run-as takes the program's file name, not '$RUN_AS'" >&2
		exit 2 ;;
esac

# Same reasoning as the --bin check: an unchecked mktemp failure leaves ERR
# empty, the `2> "$ERR"` redirection below then fails, the program is never
# started, and the resulting shell status is small and non-zero — which lands on
# the success line as "memory-clean". Fail loudly here so a broken TMPDIR cannot
# masquerade as a passing sanitizer run.
WORK=$(mktemp -d) || {
	echo "asan_run.sh: cannot create a temporary directory for the program's stderr" >&2
	exit 2
}
[ -n "$WORK" ] || { echo "asan_run.sh: mktemp returned no path" >&2; exit 2; }
RUN_DIR=""
RUN_WORK=""
rl_traps 'rm -rf "$WORK"; [ -z "$RUN_WORK" ] || rm -rf "$RUN_WORK"'
ERR="$WORK/stderr"

# The sanitizers' options -- detect_leaks=0 among them, because a leak is the
# valgrind layer's finding, and a LeakSanitizer abort here would red THIS layer
# under an "out of bounds" headline for a missing free -- and the pinned
# symbolizer, set once for every sanitizer runner (tools/runner_lib.sh).
rl_sanitizers "$WORK/sym" "$SYMBOLIZER" "$SYMBOLIZER_LIB"

# How the run ended comes from tools/exit_status (waitpid), never from $?:
# a shell reports signal N as 128+N, which is also a status a program can
# return -- `return (-1);` on an error input is 255, and this layer used to
# fail it as "died on signal 127". rl_run and rl_classify (tools/runner_lib.sh)
# read it, as every runner does.

# NO PROGRAM WAS BUILT, SO THERE IS NOTHING TO CALL MEMORY-CLEAN.
#
# When a student's code does not build, tools/student_build.sh writes a small
# /bin/sh script in the binary's place (see tools/standin.sh), so that every
# test fails one at a time instead of the whole module failing to build. That
# script prints the build failure and exits -- and its status is below 128 and
# names no sanitizer, so this runner used to fall through to "OK -- memory-clean
# on this case". Found on rush-02's stub Makefile: nine ASan targets green for
# a program that did not exist, beside valgrind targets correctly saying SKIP.
# The output layer is already red for this case, and it is the one that shows
# the compiler's words, so this steps aside the same way the gated layers do --
# and NO_SKIP=1 turns the skip into the failure it would otherwise hide.
#
# A survive case's gate comes first (--gate-*, above): while the case it waits
# on is red, there is nothing yet for this run to say.
rl_split_on
# shellcheck disable=SC2086 # a list, one word per line (rl_list_add)
rl_gate asan_run "$GATE_DIFFER" "$GATE_BIN" "$GATE_EXPECTED" $GATE_ARGS
rl_split_off
case "$0" in */*) _sl_dir=${0%/*} ;; *) _sl_dir=. ;; esac
for _sl in "$_sl_dir/standin.sh" \
	"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
	[ -f "$_sl" ] && break
done
[ -f "$_sl" ] || { echo "asan_run.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
standin_check asan_run "$BIN" skip "${LABEL:-the program}"

# An inner timeout, well under Bazel's, so an infinite loop is reported as one
# instead of surfacing as an opaque Bazel timeout: 30s, or what is left of the
# test's own limit if that is less (rl_tmo), enforced by tools/exit_status
# itself. It used to lean on coreutils' `timeout`, which can be absent, and
# calling that unconditionally was once silently fatal to this whole layer:
# the shell answered 127 for EVERY case, which fell through to the success line
# and reported the program "memory-clean" without ever having executed it.
# The run the case describes (see the header): its argument file after the
# arguments after --, and its own folder when it has one.
if [ -n "$ARGV_FILE" ]; then
	_aw=$(rl_argv_words "$ARGV_FILE") || { echo "asan_run.sh: cannot read --argv-file '$ARGV_FILE'" >&2; exit 2; }
	eval "set -- \"\$@\" $_aw"
fi
RUN_BIN=$BIN
_ran_prog=$SHOW_RUN
_ran_in=$STDIN_FILE
_ran_specs=""
if [ -n "$RUN_AS" ]; then
	RUN_WORK=$(mktemp -d) || { echo "asan_run.sh: cannot create a run folder" >&2; exit 2; }
	RUN_DIR="$RUN_WORK/run"
	rl_rundir "$RUN_DIR" "$RUN_AS" "$BIN" "$CWD_FILES" || exit 2
	RUN_BIN="./$RUN_AS"
	_ran_prog=$RUN_BIN
	_ran_specs="$RUN_AS=${SHOW_RUN:-$BIN}$CWD_FILES"
	case "$STDIN_FILE" in "" | /*) ;; *) STDIN_FILE="$PWD/$STDIN_FILE" ;; esac
fi
[ -z "$SHOW_RUN" ] || rl_ran "$_ran_prog" "$_ran_in" "$_ran_specs" "$@"

if ! rl_tmo 30; then
	rl_overrun "${LABEL:-the program}"
	exit 1
fi

# Stdin is the case's file or /dev/null, as in tools/diff_output.sh: never
# what this runner happened to be given.
(cd "${RUN_DIR:-.}" && rl_run "$RUN_BIN" "$@" < "${STDIN_FILE:-/dev/null}" > /dev/null 2> "$ERR")
RC=$?
rl_classify "$RC"

# A sanitizer abort is SIGABRT (abort_on_error=1). The program's own exits
# (a usage error, a missing file, -1 on an error input) are returns and NOT a
# finding here: this layer is about memory, not about exit status.
if [ "$RL_CAUSE" = timeout ]; then
	rl_overrun "${LABEL:-the program}"
	exit 1
fi
if [ "$RL_CAUSE" = stopped ]; then
	echo "asan_run.sh: ${LABEL:-the program} $RL_WHY" >&2
	exit 2
fi

if rl_sanitized "$ERR"; then
	echo "asan_run: FAIL — ${LABEL:-the program} hit a memory error or undefined behaviour."
	echo "          The output layer cannot see this: an out-of-bounds read can"
	echo "          still return the bytes you expected."
	echo "---------------- sanitizer report ----------------"
	rl_sanitizer_report "$ERR" 40 sanitizer-report.txt "  "
	exit 1
fi

# The binary never reached main, which tools/exit_status reports as noexec:
# exec itself failed (the file went away after the check at the top, or names
# an interpreter that is not there), or the dynamic loader stopped it first (a
# shared library, a symbol or a version it needs is missing). Nothing ran, so
# nothing was measured, and a run that never happened proves nothing about
# memory safety. The loader's case is an ordinary exit to waitpid(), 127 or 1,
# so exit_status tells it apart by the loader's own message in "$ERR" (its
# "THE LOADER IS NOT THE PROGRAM"): a version of this branch that trusted exec
# alone called a binary whose .so was deleted "memory-clean (exit 127)". Before
# that, 126 and 127 were guessed to mean this, which a program may also
# return; a program that returns 127 now has returned.
if [ "$RL_CAUSE" = noexec ]; then
	echo "asan_run.sh: ${LABEL:-the program} $RL_WHY" >&2
	if [ -s "$ERR" ]; then
		echo "             ----- its stderr -----" >&2
		rl_excerpt "$ERR" 20 program-stderr.txt "               " >&2
	fi
	exit 2
fi

if [ "$RL_CAUSE" = signal ] || [ "$RL_CAUSE" = runaway ]; then
	echo "asan_run: FAIL — ${LABEL:-the program} $RL_WHY."
	rl_excerpt "$ERR" 20 program-stderr.txt "  "
	exit 1
fi

echo "asan_run: OK — ${LABEL:-the program} is memory-clean on this case (exit $RC)"
exit 0
