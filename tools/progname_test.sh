#!/bin/sh
# Verify a program prints its own invocation name (argv[0]) + newline.
#
# argv[0] is non-deterministic under Bazel runfiles, so we copy the binary into a
# scratch directory under a KNOWN name and run it as "./<name>": the expected
# output is then exactly "./<name>\n".
#
# We run it under TWO different names — "a.out" (matching the subject example) and
# a second, unrelated name — and require BOTH to match. A program that hardcodes
# the literal "./a.out" instead of reading argv[0] passes the first run but fails
# the second, so the renamed run is what actually proves argv[0] is being read.
#
# The exit STATUS is checked too, not just the output. A program that prints the
# right line and then dies -- a segfault on the way out, a stray return 1 -- would
# otherwise pass here while failing at evaluation, because a diff of stdout cannot
# see how the process ended.
#
# Usage: progname_test.sh [--diff <diff>] <bin>
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "progname_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require chmod cp mktemp rm sed

# The pinned diff. It defaults to the box's so a hand-run outside Bazel still
# works, and every target passes --diff: unified-diff output is what a student
# reads here, and GNU and BSD do not format it identically.
DIFF="diff"

need() { [ "$2" -ge 2 ] || { echo "progname_test.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--diff) need "$1" "$#"; DIFF="$2"; shift 2 ;;
		--) shift; break ;;
		-*) echo "progname_test.sh: unknown option: $1" >&2; exit 2 ;;
		*) break ;;
	esac
done

# Absolute, for the reason the binary below is: this runner runs things from a
# scratch directory, and a runfiles-relative path does not survive that.
case "$DIFF" in
	*/*)
		case "$DIFF" in
			/*) ;;
			*) DIFF="$PWD/$DIFF" ;;
		esac
		;;
esac

BIN="${1:-}"
if [ -z "$BIN" ]; then
	echo "progname_test.sh: missing binary path" >&2
	exit 2
fi

case "$BIN" in
	/*) ABS="$BIN" ;;
	*) ABS="$PWD/$BIN" ;;
esac

TMP=$(mktemp -d)
# Cleanup on every exit path, not just the last line: the early `exit 2`s below
# and any signal Bazel sends a timed-out test used to leave the directory behind.
trap 'rm -rf "$TMP"' EXIT INT TERM
RC=0

# This runs unverified student code, so bound what it can do before it does it —
# the same reasoning, and the same idiom, as tools/diff_output.sh (grep there for
# "ulimit -f"). The expected output here is one short line, so the budget can be
# far tighter than that runner's while still being orders of magnitude above any
# legitimate result: a loop printing argv[0] forever is stopped by the kernel
# (SIGXFSZ) instead of filling the disk, and an infinite loop that prints nothing
# is stopped by the timeout instead of surfacing as an opaque Bazel timeout the
# student cannot act on. ulimit -f counts 512-byte blocks.
BLOCKS=$(( 4194304 / 512 + 2 ))
TMO="${PROGNAME_TIMEOUT:-10}"
if command -v timeout > /dev/null 2>&1; then
	RUNNER="timeout -s KILL $TMO"
else
	RUNNER=""
fi

# Copy the binary to $TMP/<name>, run it as ./<name>, and require it to print
# exactly "./<name>\n" (its real argv[0]). Sets RC=1 on any mismatch.
run_as() {
	name="$1"
	cp "$ABS" "$TMP/$name" || { echo "progname_test.sh: cannot copy $ABS" >&2; RC=1; return; }
	chmod +x "$TMP/$name"
	# stderr is kept rather than discarded: the same runner is reused for the
	# _progname_asan target, where the sanitizer's report IS the finding and goes
	# to stderr. It stays out of the diff (only stdout is compared) and is shown
	# only when something failed.
	# shellcheck disable=SC2086
	(cd "$TMP" && ulimit -f "$BLOCKS" 2> /dev/null; $RUNNER "./$name") \
		> "$TMP/actual.txt" 2> "$TMP/stderr.txt"
	status=$?
	printf './%s\n' "$name" > "$TMP/expected.txt"
	show_stderr() {
		[ -s "$TMP/stderr.txt" ] || return 0
		printf '      it also wrote this to stderr:\n'
		sed -n '1,25p' "$TMP/stderr.txt" | sed 's/^/        /'
	}
	if ! "$DIFF" -u "$TMP/expected.txt" "$TMP/actual.txt"; then
		printf 'FAIL: run as ./%s -> expected "./%s". ' "$name" "$name"
		printf 'The program must print its own argv[0]; a hardcoded '
		printf '"./a.out" is caught by the renamed run.\n'
		show_stderr
		RC=1
		return
	fi
	# Right output, wrong ending. Separated from the diff so the message can say
	# which of the two happened -- "it printed the correct line and then died" is
	# a different bug from "it printed the wrong line".
	if [ "$status" -ne 0 ]; then
		printf 'FAIL: run as ./%s -> printed the right line, then exited %d.\n' "$name" "$status"
		if [ "$status" = 137 ]; then
			printf '      That is SIGKILL after %ss — it never finished. A program that\n' "$TMO"
			printf '      prints its name should not need any measurable time at all, so\n'
			printf '      look for a loop with no way out.\n'
		elif [ "$status" = 153 ]; then
			printf '      That is SIGXFSZ: it kept printing past the output budget. The\n'
			printf '      expected output is one line, so something is printing in a loop.\n'
		elif [ "$status" -gt 128 ]; then
			printf '      That is signal %d (128 + %d): the program died rather than\n' \
				"$((status - 128))" "$((status - 128))"
			printf '      returning. The output was already flushed, so only the exit\n'
			printf '      status shows it.\n'
		else
			printf '      main must return 0 on success.\n'
		fi
		show_stderr
		RC=1
		return
	fi
	printf 'PASS: run as ./%s -> printed "./%s", exited 0\n' "$name" "$name"
}

run_as a.out
run_as not_a_out

exit $RC
