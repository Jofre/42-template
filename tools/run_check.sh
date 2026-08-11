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
#   --exit CODE     expected exit status (default 0)
#   --timeout SECS  wall-clock budget (default 20)
#   --label TEXT    what to call the binary in messages
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
require basename head mktemp rm sed tr wc
# conventions: optional timeout -- probed in run_it(); without it the program is
# run unbounded, so --timeout stops being enforced while the exit-status, output
# size and `ulimit -f` guards still are. Nine runners probe timeout this way and
# they do not agree on what to do when it is missing (argv_table.sh refuses with
# exit 1, rush01_check.sh with exit 2, the other seven degrade silently); that
# is one behaviour, so it belongs in one place.

BIN=""
MIN=0
MAX=16777216
WANT_EXIT=0
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

OUT=$(mktemp)
ERR=$(mktemp)
trap 'rm -f "$OUT" "$ERR"' EXIT INT TERM

run_it() {
	if command -v timeout >/dev/null 2>&1; then
		timeout -s KILL "$TIMEOUT" "$BIN" "$@"
	else
		"$BIN" "$@"
	fi
}

# --max-bytes has to be a GUARD, not a report: an untested main() that prints in
# a loop writes at page-cache speed for the whole timeout (gigabytes into the
# test tmpdir) if the only check happens after it dies. `ulimit -f` bounds the
# file at the source — the kernel kills the writer with SIGXFSZ (exit 128+25) the
# moment it goes past the budget. It counts 512-byte blocks, hence the rounding.
BLOCKS=$(( MAX / 512 + 2 ))
(
	ulimit -f "$BLOCKS" 2>/dev/null
	run_it "$@"
) > "$OUT" 2> "$ERR"
RC=$?

BYTES=$(wc -c < "$OUT" | tr -d ' ')
FAIL=0

if [ "$RC" -eq 153 ]; then
	echo "run_check: FAIL — $LABEL kept printing past its $MAX-byte budget (runaway loop?)"
	echo "            It was stopped at $BYTES bytes; nothing about its output was checked."
	FAIL=1
elif [ "$RC" -eq 137 ] || [ "$RC" -eq 124 ]; then
	echo "run_check: FAIL — $LABEL did not finish within ${TIMEOUT}s (infinite loop?)"
	FAIL=1
elif [ "$RC" -ne "$WANT_EXIT" ]; then
	echo "run_check: FAIL — $LABEL exited $RC, expected $WANT_EXIT"
	[ "$RC" -gt 128 ] && echo "            (a status above 128 means it died on signal $((RC - 128)) — a crash)"
	FAIL=1
fi

if [ "$BYTES" -lt "$MIN" ]; then
	echo "run_check: FAIL — $LABEL wrote $BYTES byte(s) to stdout, expected at least $MIN."
	echo "            It has to actually DO something when it runs."
	FAIL=1
fi
if [ "$BYTES" -gt "$MAX" ] && [ "$RC" -ne 153 ]; then
	echo "run_check: FAIL — $LABEL wrote $BYTES bytes to stdout, above the $MAX budget (runaway loop?)"
	FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
	if [ -s "$ERR" ]; then
		echo "----- stderr -----"
		sed 's/^/  /' "$ERR" | head -20
	fi
	if [ -s "$OUT" ]; then
		echo "----- first lines of stdout -----"
		head -c 400 "$OUT" | sed 's/^/  /'
		echo ""
	fi
	exit 1
fi

echo "run_check: OK — $LABEL exited $RC and wrote $BYTES byte(s) within ${TIMEOUT}s"
exit 0
