#!/bin/sh
# Run a binary and assert only that it BEHAVES: exits with the expected status,
# inside a wall-clock budget, having written a sane amount to stdout.
#
# For deliverables whose output is the student's own choice — rush's main.c is
# free to draw any rectangle it likes — there is nothing to diff, but "it links,
# it runs, it terminates, it actually prints something" is still worth pinning.
#
# Usage:
#   run_check.sh --bin PATH [options] [-- PROG ARGS...]
#
#   --min-bytes N   fail if stdout is shorter than N bytes (default 0)
#   --max-bytes N   fail if stdout is longer than N bytes (default 16777216)
#   --exit CODE     fail unless the program returns CODE: for a status the
#                   subject names, or for --exit-only
#   --note-exit CODE  a plain return other than CODE is NOTED, never failed:
#                   for a subject that names no status (docs/reference.md,
#                   "Run contract"), whose robust twin fails it with
#                   --exit CODE --exit-only
#   --exit-only     judge only how the run ended; output is not checked
#   --exit-source subject|convention
#                   where the status --exit names comes from, which a failure
#                   says (default subject): "convention" for the robust twin of
#                   a --note-exit target, whose subject names no status. The
#                   same flag as diff_output.sh's
#   --timeout SECS  wall-clock budget (default 20), capped by what is left of
#                   the test's own limit
#   --label TEXT    what to call the binary in messages
#
# A run killed by a signal, stopped by the time budget or by the output budget
# fails whatever the flags say.
#
# Exit status: 0 if every assertion holds, 1 otherwise.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "run_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require basename mktemp rm tr wc

# The shared runner helpers -- time budget, exiting signal traps, how a run
# ended, excerpts, hints -- written once in tools/runner_lib.sh.
RL_NAME=run_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "run_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"

BIN=""
MIN=0
MAX=16777216
WANT_EXIT=""
NOTE_EXIT=""
EXIT_ONLY=0
EXIT_SOURCE=subject
TIMEOUT=20
LABEL=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "run_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--min-bytes) need "$1" "$#"; MIN="$2"; shift 2 ;;
		--max-bytes) need "$1" "$#"; MAX="$2"; shift 2 ;;
		--exit) need "$1" "$#"; WANT_EXIT="$2"; shift 2 ;;
		--note-exit) need "$1" "$#"; NOTE_EXIT="$2"; shift 2 ;;
		--exit-only) EXIT_ONLY=1; shift ;;
		--exit-source) need "$1" "$#"; EXIT_SOURCE="$2"; shift 2 ;;
		--timeout) need "$1" "$#"; TIMEOUT="$2"; shift 2 ;;
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--) shift; break ;;
		*) echo "run_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$BIN" ] || { echo "run_check.sh: --bin is required" >&2; exit 2; }
# Non-empty is not the same as runnable. An unstaged or mis-pathed binary makes
# the shell report exit 127, which this layer would otherwise render as
# "exited 127, expected 0" -- a student verdict for a BUILD-file mistake. Exit 2
# says harness error; exit 1 stays reserved for "the code under test is wrong".
[ -x "$BIN" ] || { echo "run_check.sh: '$BIN' is not an executable file" >&2; exit 2; }
[ -n "$LABEL" ] || LABEL="$(basename "$BIN")"
case "$EXIT_SOURCE" in
	subject | convention) ;;
	*) echo "run_check.sh: --exit-source must be subject or convention, not '$EXIT_SOURCE'" >&2
		exit 2 ;;
esac
# --exit-only with nothing to compare the status to would judge nothing and
# pass: a wiring error, never a verdict.
if [ "$EXIT_ONLY" = 1 ] && [ -z "$WANT_EXIT" ]; then
	echo "run_check.sh: --exit-only needs --exit: it judges the status and nothing else" >&2
	exit 2
fi

# A PROGRAM THAT DID NOT BUILD is a stand-in script that says why (see
# tools/standin.sh). Graded as a program, its "output" is empty and its exit
# status arbitrary, and the report would be a table of wrong answers under
# this exercise's hints, none of which is about a build. Say what the build
# said instead, whole, and fail.
case "$0" in */*) _sl_dir=${0%/*} ;; *) _sl_dir=. ;; esac
for _sl in "$_sl_dir/standin.sh" \
	"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
	[ -f "$_sl" ] && break
done
[ -f "$_sl" ] || { echo "run_check.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
standin_check run_check "$BIN" fail "$LABEL"

OUT=$(mktemp)
ERR=$(mktemp)
rl_traps 'rm -f "$OUT" "$ERR"'

# The wall-clock budget: --timeout, or what is left of the test's own limit if
# that is less.
if ! rl_tmo "$TIMEOUT"; then
	rl_overrun "$LABEL"
	exit 1
fi

# --max-bytes has to be a GUARD, not a report: an untested main() that prints in
# a loop writes at page-cache speed for the whole timeout (gigabytes into the
# test tmpdir) if the only check happens after it dies. `ulimit -f` bounds the
# file at the source — the kernel kills the writer with SIGXFSZ (exit 128+25) the
# moment it goes past the budget. It counts 512-byte blocks, hence the rounding.
BLOCKS=$(( MAX / 512 + 2 ))
(
	ulimit -f "$BLOCKS" 2>/dev/null
	rl_run "$BIN" "$@"
) > "$OUT" 2> "$ERR"
RC=$?
rl_classify "$RC"
# Not started at all: nothing about the program is known (exit 2, a wiring
# error, as for a --bin that is not executable above).
if [ "$RL_CAUSE" = noexec ]; then
	echo "run_check.sh: $LABEL $RL_WHY" >&2
	exit 2
fi

BYTES=$(wc -c < "$OUT" | tr -d ' ')
FAIL=0

NOTE=""
if [ "$RL_CAUSE" = runaway ]; then
	echo "run_check: FAIL — $LABEL kept printing past its $MAX-byte budget (runaway loop?)"
	echo "            It was stopped at $BYTES bytes; nothing about its output was checked."
	FAIL=1
elif [ "$RL_CAUSE" = timeout ]; then
	rl_overrun "$LABEL"
	FAIL=1
elif [ "$RL_CAUSE" = signal ] || [ "$RL_CAUSE" = stopped ]; then
	echo "run_check: FAIL — $LABEL $RL_WHY."
	echo "            It was killed rather than returning: a crash, whatever it printed."
	FAIL=1
elif [ -n "$WANT_EXIT" ] && [ "$RC" -ne "$WANT_EXIT" ]; then
	echo "run_check: FAIL — $LABEL exited $RC, expected $WANT_EXIT"
	# Where the status came from is the caller's to say: "the subject names
	# none" under a status the subject does name would be false.
	if [ "$EXIT_SOURCE" = convention ]; then
		echo "            The subject names no exit status. This is the robust check,"
		echo "            which applies the C convention: a program that did its job"
		echo "            returns $WANT_EXIT from main (docs/reference.md, \"Run contract\")."
	else
		echo "            The subject names this status, so it is part of the verdict"
		echo "            at every level."
	fi
	FAIL=1
elif [ -n "$NOTE_EXIT" ] && [ "$RC" -ne "$NOTE_EXIT" ]; then
	NOTE="the program returned exit status $RC"
fi

# --exit-only judges how the run ended and nothing else.
if [ "$EXIT_ONLY" = 1 ]; then
	if [ "$FAIL" -ne 0 ]; then
		rl_excerpt "$ERR" 20 stderr.txt "  "
		exit 1
	fi
	echo "run_check: OK — $LABEL exited $RC, as this check expects."
	exit 0
fi

if [ "$BYTES" -lt "$MIN" ]; then
	echo "run_check: FAIL — $LABEL wrote $BYTES byte(s) to stdout, expected at least $MIN."
	echo "            It has to actually DO something when it runs."
	FAIL=1
fi
if [ "$BYTES" -gt "$MAX" ] && [ "$RL_CAUSE" != runaway ]; then
	echo "run_check: FAIL — $LABEL wrote $BYTES bytes to stdout, above the $MAX budget (runaway loop?)"
	FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
	if [ -s "$ERR" ]; then
		echo "----- stderr -----"
		rl_excerpt "$ERR" 20 stderr.txt "  "
	fi
	if [ -s "$OUT" ]; then
		echo "----- stdout -----"
		rl_excerpt "$OUT" 20 stdout.txt "  "
	fi
	exit 1
fi

echo "run_check: OK — $LABEL exited $RC and wrote $BYTES byte(s) within ${RL_TMO:-$TIMEOUT}s"
if [ -n "$NOTE" ]; then
	echo "  note: $NOTE. The subject names no exit status, so this layer does not"
	echo "        fail on it; the robust exit-status check does, because a program"
	echo "        that did its job conventionally returns $NOTE_EXIT from main."
fi
exit 0
