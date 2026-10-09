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
# HOW THE PROCESS ENDED is checked too, not just the output, by the rule in
# docs/reference.md ("Run contract"). A program that prints the right line and
# then dies -- a segfault on the way out, an abort -- fails here, because a diff
# of stdout cannot see how the process ended and a crash is never a pass. A
# plain non-zero RETURN is another matter: the C 06 subject names no exit
# status, so basic does not fail on one. This runner prints a note instead, and
# --exit-only -- the robust exNN_progname_exit target -- is where it fails.
#
# A MISMATCH IS SHOWN, not summarised: both sides go through runner_lib.sh's
# rl_vis, which prints every byte (a NUL as \x00) and marks each line end with
# $, and the explanation follows the cause. The sentence about a hardcoded "./a.out" is
# printed only when the renamed run really printed "./a.out".
#
# Usage: progname_test.sh [--diff <diff>] [--exit-only] <bin>
#
#   --exit-only  judge only how each run ended: a plain non-zero return fails
#                as well as a crash, and what was printed is not compared.
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
require chmod cmp cp mktemp rm sed

# The shared runner helpers -- time budget, exiting signal traps, how a run
# ended, excerpts, hints -- written once in tools/runner_lib.sh.
RL_NAME=progname_test
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "progname_test.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool DIFF -- the pinned diff, which compares two files

# The pinned diff. It defaults to the box's so a hand-run outside Bazel still
# works, and every target passes --diff: unified-diff output is what a student
# reads here, and GNU and BSD do not format it identically.
DIFF="diff"
EXIT_ONLY=0

need() { [ "$2" -ge 2 ] || { echo "progname_test.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--diff) need "$1" "$#"; DIFF="$2"; shift 2 ;;
		--exit-only) EXIT_ONLY=1; shift ;;
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

# How each run ended comes from tools/exit_status (waitpid), never from $?,
# which reads `return (-1);` (255) as a death by signal 127: rl_run and
# rl_classify (tools/runner_lib.sh) read it, from an absolute path, since the
# runs happen from the scratch directory.

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
[ -f "$_sl" ] || { echo "progname_test.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
standin_check progname_test "$ABS" fail "the program"

TMP=$(mktemp -d)
# Cleanup on every exit path, not just the last line: the early `exit 2`s below
# and any signal Bazel sends a timed-out test used to leave the directory behind.
rl_traps 'rm -rf "$TMP"'
RC=0

# This runs unverified student code, so bound what it can do before it does it —
# the same reasoning, and the same idiom, as tools/diff_output.sh (grep there for
# "ulimit -f"). The expected output here is one short line, so the budget can be
# far tighter than that runner's while still being orders of magnitude above any
# legitimate result: a loop printing argv[0] forever is stopped by the kernel
# (SIGXFSZ) instead of filling the disk, and an infinite loop that prints nothing
# is stopped by the timeout instead of surfacing as an opaque Bazel timeout the
# student cannot act on. ulimit -f counts 512-byte blocks. PROGNAME_TIMEOUT
# caps each run, and what is left of the test's own limit caps that (rl_tmo).
BLOCKS=$(( 4194304 / 512 + 2 ))
TMO="${PROGNAME_TIMEOUT:-10}"

# Copy the binary to $TMP/<name>, run it as ./<name>, and require it to print
# exactly "./<name>\n" (its real argv[0]). Sets RC=1 on any mismatch.
run_as() {
	name="$1"
	cp "$ABS" "$TMP/$name" || { echo "progname_test.sh: cannot copy $ABS" >&2; RC=1; return; }
	chmod +x "$TMP/$name"
	# stderr is kept rather than discarded, so that a failure can show it: a
	# program that printed its name to stderr, or died saying why, explains
	# itself there. It stays out of the diff (only stdout is compared) and is
	# shown only when something failed. (The _progname_asan target is not this
	# runner: it runs the instrumented binary through asan_run.sh.)
	if ! rl_tmo "$TMO"; then
		rl_overrun "the run as ./$name"
		RC=1
		return
	fi
	(cd "$TMP" && ulimit -f "$BLOCKS" 2> /dev/null; rl_run "./$name") \
		> "$TMP/actual.txt" 2> "$TMP/stderr.txt"
	status=$?
	# How it ended (rl_classify): returned, killed by a signal, stopped by the
	# output budget, or stopped by the time limit.
	rl_classify "$status"
	sig=$RL_SIG
	case "$RL_CAUSE" in
		ok | "exit") ended=returned ;;
		"timeout") ended=timeout ;;
		signal | runaway) ended=signal ;;
		*)
			echo "progname_test.sh: ./$name $RL_WHY" >&2
			exit 2 ;;
	esac
	printf './%s\n' "$name" > "$TMP/expected.txt"
	show_stderr() {
		[ -s "$TMP/stderr.txt" ] || return 0
		printf '      it also wrote this to stderr:\n'
		rl_excerpt "$TMP/stderr.txt" 25 "stderr-$name.txt" "        "
	}
	# Every byte of one side, 25 lines at most, through runner_lib.sh's one
	# renderer (rl_vis): what a terminal would hide is \xHH, a NUL \x00, and
	# each line ends with $, the same view as the subject's `| cat -e` -- a $
	# that is in the text reads \x24. It was sed's `l`, octal escapes that no
	# other layer uses and a literal $ that read as a line end.
	show_bytes() {
		printf '      %s, byte for byte ($ = end of line):\n' "$1"
		rl_vis block 25 < "$2" | sed 's/^/        /'
	}
	# The unified diff through runner_lib.sh's rl_udiff, which renders every
	# byte: printed raw, a NUL the program wrote landed in test.log as one
	# (`file` called the log "data", grep a binary file), and without -a the
	# whole report was "Binary files X and Y differ", naming two files this
	# runner deletes on exit (V51).
	if [ "$EXIT_ONLY" = 0 ] && ! cmp -s "$TMP/expected.txt" "$TMP/actual.txt"; then
		rl_udiff "$DIFF" "$TMP/expected.txt" "$TMP/actual.txt" expected printed
		printf 'FAIL: run as ./%s -> expected "./%s" and a newline.\n' "$name" "$name"
		show_bytes expected "$TMP/expected.txt"
		show_bytes printed "$TMP/actual.txt"
		# The explanation follows the cause, never a fixed sentence: the one
		# about hardcoding used to follow every mismatch, including a program
		# that printed its own argv[0] plus one byte too many.
		if [ "$name" != a.out ] && printf './a.out\n' | cmp -s - "$TMP/actual.txt"; then
			printf '      Renamed to %s, it still printed "./a.out": the name is\n' "$name"
			printf '      hardcoded rather than read from argv[0].\n'
		elif [ ! -s "$TMP/actual.txt" ] && [ -s "$TMP/stderr.txt" ]; then
			printf '      There was nothing on stdout, but it wrote to stderr. The\n'
			printf "      subject's example reads stdout, so stdout is what counts.\n"
		else
			printf '      Compare the two byte for byte: the view above is the one\n'
			printf "      cat -e gives in the subject's example.\n"
		fi
		show_stderr
		RC=1
		return
	fi
	# Right output, wrong ending. Separated from the diff so the message can say
	# which of the two happened -- "it printed the correct line and then died" is
	# a different bug from "it printed the wrong line".
	if [ "$ended" = returned ] && [ "$status" -gt 0 ] && [ "$EXIT_ONLY" = 0 ]; then
		printf 'PASS: run as ./%s -> printed "./%s"\n' "$name" "$name"
		printf 'NOTE: ... then returned exit status %d.\n' "$status"
		printf '      The subject names no exit status, so that does not fail here;\n'
		printf '      the robust exit-status check fails it, because a program that\n'
		printf '      did its job conventionally returns 0 from main.\n'
		return
	fi
	if [ "$ended" != returned ] || [ "$status" -ne 0 ]; then
		case "$ended" in
			returned) _what="exited $status" ;;
			"timeout") _what="was stopped after ${RL_TMO}s" ;;
			*) _what="was killed by signal $sig" ;;
		esac
		if [ "$EXIT_ONLY" = 1 ]; then
			printf 'FAIL: run as ./%s -> %s.\n' "$name" "$_what"
		else
			printf 'FAIL: run as ./%s -> printed the right line, then %s.\n' "$name" "$_what"
		fi
		if [ "$ended" = timeout ]; then
			printf '      It never finished. A program that prints its name should not\n'
			printf '      need any measurable time at all, so look for a loop with no\n'
			printf '      way out.\n'
		elif [ "$sig" = 25 ]; then
			printf '      That is SIGXFSZ: it kept printing past the output budget. The\n'
			printf '      expected output is one line, so something is printing in a loop.\n'
		elif [ "$ended" = signal ]; then
			printf '      The program died rather than returning. The output was already\n'
			printf '      flushed, so only how it ended shows it.\n'
		else
			printf '      The subject names no exit status. This is the robust check,\n'
			printf '      which applies the C convention: a program that did its job\n'
			printf '      returns 0 from main.\n'
		fi
		show_stderr
		RC=1
		return
	fi
	if [ "$EXIT_ONLY" = 1 ]; then
		printf 'PASS: run as ./%s -> exited 0\n' "$name"
	else
		printf 'PASS: run as ./%s -> printed "./%s", exited 0\n' "$name" "$name"
	fi
}

run_as a.out
run_as not_a_out

exit $RC
