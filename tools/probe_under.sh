#!/bin/sh
# probe_under.sh — stand another program in for the one a test runs.
#
# WHAT A CASE CATCHES IS MEASURED, NOT BELIEVED. A case list written from a
# subject's example transcript passes every program that gets the transcript
# right, and a case added "for the error path" may catch nothing at all. The
# only way to know which mistakes a list catches is to run it on programs
# that make them, one at a time -- a model of the exercise (//oracle's, where
# there is one) with one mistake put in. This is how such a program is put
# where the student's would be, without touching a BUILD file or a turn-in:
#
#   bazel test //c-piscine/c-piscine-c-10:ex01 --nocache_test_results \
#       --run_under="$PWD/tools/probe_under.sh" \
#       --test_env=PROBE_STANDIN=/abs/path/to/program
#
# Bazel then starts `probe_under.sh RUNNER ARGS...` in each test's place. Every
# program the runner is handed to run -- the value after --bin, --student-bin,
# --gate-bin or --gate-asan-bin; never --baseline-bin, the reference -- becomes
# PROBE_STANDIN, under the file name it replaces, so a stand-in that prints
# basename(argv[0]) prints what the student's program would (exNN_bin). The
# runner is then started exactly as it would have been. The targets that go
# red are the ones that catch the stand-in's mistake.
#
# --nocache_test_results, always: the stand-in is no input Bazel tracks, so a
# stand-in changed at the same path would otherwise get the last one's
# verdicts back from the cache.
#
# Env:
#   PROBE_STANDIN  the stand-in, an absolute path to an executable (required).
#   PROBE_BIN      set for the stand-in: the absolute path of the first program
#                  it replaced, so that it can run it, or wrap it in a mistake.
#
# A stand-in must never be an answer: it wraps a model of the exercise, or the
# student's own program, in ONE mistake (AGENTS.md §0). It is a scratch file
# and is never committed.
set -u

# The external commands this script takes from PATH, probed before anything
# runs; exit 2, never 1: a probe that could not start measured nothing.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "probe_under.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require ln mkdir mktemp

if [ -z "${PROBE_STANDIN:-}" ]; then
	echo "probe_under.sh: set the stand-in: --test_env=PROBE_STANDIN=/abs/path/to/program" >&2
	exit 2
fi
case "$PROBE_STANDIN" in
	/*) ;;
	*) echo "probe_under.sh: PROBE_STANDIN must be absolute: the test runs from its runfiles, not from here ('$PROBE_STANDIN')" >&2
	   exit 2 ;;
esac
if [ ! -f "$PROBE_STANDIN" ] || [ ! -x "$PROBE_STANDIN" ]; then
	echo "probe_under.sh: PROBE_STANDIN is not an executable file: $PROBE_STANDIN" >&2
	exit 2
fi
if [ $# -lt 1 ]; then
	echo "probe_under.sh: no test to run: it is Bazel's --run_under, which passes the test's own command" >&2
	exit 2
fi

# A folder of its own for this run (a retried test reuses TEST_TMPDIR), and in
# it one per program swapped, so two programs with one name never meet.
_dir=$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/probe_under.XXXXXX") ||
	{ echo "probe_under.sh: cannot create a scratch directory" >&2; exit 2; }

# The command again, one word at a time: each word is shifted off the front
# and put back at the end, the one after a program flag replaced.
_next=0
_n=0
_swapped=0
for _a do
	shift
	if [ "$_next" = 1 ]; then
		_next=0
		_n=$((_n + 1))
		mkdir -p "$_dir/$_n" || exit 2
		ln -s "$PROBE_STANDIN" "$_dir/$_n/${_a##*/}" || exit 2
		if [ -z "${PROBE_BIN:-}" ]; then
			case "$_a" in
				/*) PROBE_BIN=$_a ;;
				*) PROBE_BIN="$PWD/$_a" ;;
			esac
			export PROBE_BIN
		fi
		_a="$_dir/$_n/${_a##*/}"
		_swapped=$((_swapped + 1))
	else
		case "$_a" in
			--bin | --student-bin | --gate-bin | --gate-asan-bin) _next=1 ;;
		esac
	fi
	set -- "$@" "$_a"
done

# A test that runs no program of the student's has nothing to stand in for,
# and its verdict says nothing about the stand-in: said, so that a probe
# reading "green" never counts it.
if [ "$_swapped" = 0 ]; then
	echo "probe_under.sh: this test is handed no program to run (no --bin, --student-bin, --gate-bin or --gate-asan-bin): its verdict is not the stand-in's" >&2
fi
exec "$@"
