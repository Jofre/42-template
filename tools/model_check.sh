#!/bin/sh
# model_check.sh -- that a program case's expected file is still what the
# model it was made from answers for that case.
#
# WHY. C 10's error-path, standard-input and several-file fixtures, and
# Reloaded ex27's, were made once, by running //oracle's model of the tool
# (`oracle c10_run`) on the case's own arguments, and checked then against the
# tool itself. Nothing held them to the model afterwards: a later fix to the
# model, or a fixture edited by hand, would drift in silence, and the first
# sign would have been a correct program going red (review of WP-50). This
# runs the model on the case the way the output test runs the program -- from
# the same directory, on the same arguments and standard input -- and compares
# the stream the case compares, byte for byte, and the status where the case
# names one ("exit").
#
# It runs nothing of the student's. c_program emits it as exNN[_case]_model
# (layer oracle, complete) for each case with one expected file, where the
# c_program names its `model`. It is green on every turn-in, and red only when
# a fixture and the model disagree -- and until they are reconciled, that
# fixture is not evidence about anyone's program.
#
# Usage:
#   model_check.sh --oracle PATH --expected FILE [--stream stdout|stderr]
#                  [--stdin FILE] [--argv-file FILE]
#                  [--run-as NAME [--cwd-file DEST=SRC]...]
#                  [--exit N] [--absent NAME]... -- WORD...
#
#   --oracle    $(location //oracle:oracle)
#   --expected  the case's expected file
#   --stream    which stream the case compares (default stdout)
#   --stdin     the file the case feeds the program (default: none, /dev/null)
#   --argv-file the case's argument file ("argv_file"): its lines, one
#               argument each, follow the WORDs, as diff_output.sh appends
#               them to the program's (rl_argv_words)
#   --run-as, --cwd-file  the case's run folder ("cwd_files"): the model runs
#               from a folder holding a copy of it as NAME and each SRC as
#               DEST (rl_rundir), as the program does -- c_program hands
#               every runner the same flags (defs.bzl's _case_run)
#   --exit      the status the case names ("exit"); without it, none is compared
#   --absent    a name the case hands over as one that will not open
#               ("missing_file"): if something by that name is where this
#               runs, nothing is run and this exits 2, as diff_output.sh does
#   WORD...     the model's words, then the case's "args": for C 10 ex01,
#               c10_run --prog ex01_bin cat no_such_file_ex01 <a fixture's path>
#
# Exit status: 0 the file (and the status) is the model's answer, 1 it is not,
# 2 the check could not be made.
set -u

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "model_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require cmp mktemp rm

RL_NAME=model_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "model_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"

# conventions: runs no student code -- it runs //oracle's model on a case's arguments
# conventions: harness tool ORACLE -- the Rust reference (//oracle), whose model made the fixture

ORACLE=""
EXPECTED=""
STREAM=stdout
STDIN_FILE=""
EXPECT_EXIT=""
ABSENT=""
ARGV_FILE=""
RUN_AS=""
CWD_FILES=""

need() { [ "$2" -ge 2 ] || { echo "model_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--expected) need "$1" "$#"; EXPECTED="$2"; shift 2 ;;
		--stream) need "$1" "$#"; STREAM="$2"; shift 2 ;;
		--stdin) need "$1" "$#"; STDIN_FILE="$2"; shift 2 ;;
		--exit) need "$1" "$#"; EXPECT_EXIT="$2"; shift 2 ;;
		--absent) need "$1" "$#"; ABSENT="$ABSENT
$2"; shift 2 ;;
		--argv-file) need "$1" "$#"; ARGV_FILE="$2"; shift 2 ;;
		--run-as) need "$1" "$#"; RUN_AS="$2"; shift 2 ;;
		--cwd-file) need "$1" "$#"; CWD_FILES="$CWD_FILES
$2"; shift 2 ;;
		--) shift; break ;;
		*) echo "model_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$ORACLE" ] || { echo "model_check.sh: --oracle is required" >&2; exit 2; }
[ -x "$ORACLE" ] || { echo "model_check.sh: $ORACLE is not executable" >&2; exit 2; }
[ -n "$EXPECTED" ] || { echo "model_check.sh: --expected is required" >&2; exit 2; }
[ -r "$EXPECTED" ] || { echo "model_check.sh: cannot read --expected '$EXPECTED'" >&2; exit 2; }
[ $# -gt 0 ] || { echo "model_check.sh: no model words after --" >&2; exit 2; }
case "$STREAM" in
	stdout | stderr) ;;
	*) echo "model_check.sh: --stream is stdout or stderr, not '$STREAM'" >&2; exit 2 ;;
esac
case "$EXPECT_EXIT" in
	"") ;;
	*[!0-9]*) echo "model_check.sh: --exit needs a status from 0 to 255, not '$EXPECT_EXIT'" >&2; exit 2 ;;
esac
if [ -n "$STDIN_FILE" ] && [ ! -r "$STDIN_FILE" ]; then
	echo "model_check.sh: cannot read --stdin '$STDIN_FILE'" >&2
	exit 2
fi
if [ -n "$CWD_FILES" ] && [ -z "$RUN_AS" ]; then
	echo "model_check.sh: --cwd-file stages a file in the run folder, which --run-as makes" >&2
	exit 2
fi
if [ -n "$ARGV_FILE" ]; then
	_aw=$(rl_argv_words "$ARGV_FILE") || { echo "model_check.sh: cannot read --argv-file '$ARGV_FILE'" >&2; exit 2; }
	eval "set -- \"\$@\" $_aw"
fi

WORK=$(mktemp -d) || exit 2
rl_traps 'rm -rf "$WORK"'

# THE CASE'S RUN FOLDER, when it has one: the model runs where the program
# would, beside the same files under the same names. Every path this runs
# with is made absolute first, since the folder is not where Bazel put them.
# As the case gives them, for the report's RAN line: the files are listed
# where the case names them, as diff_output.sh lists the program's.
ORACLE_GIVEN=$ORACLE
STDIN_GIVEN=$STDIN_FILE
if [ -n "$RUN_AS" ]; then
	case "$ORACLE" in /*) ;; *) ORACLE="$PWD/$ORACLE" ;; esac
	case "$EXPECTED" in /*) ;; *) EXPECTED="$PWD/$EXPECTED" ;; esac
	case "$STDIN_FILE" in "" | /*) ;; *) STDIN_FILE="$PWD/$STDIN_FILE" ;; esac
	rl_rundir "$WORK/run" "$RUN_AS" "$ORACLE" "$CWD_FILES" || exit 2
	cd "$WORK/run" || exit 2
fi

while IFS= read -r _a; do
	[ -n "$_a" ] || continue
	if [ -e "$_a" ] || [ -L "$_a" ]; then
		echo "model_check.sh: the case hands over '$_a' as a name that will not" >&2
		echo "                open (--absent), and $PWD holds something by that name." >&2
		exit 2
	fi
done <<ABSENT_EOF
$ABSENT
ABSENT_EOF

"$ORACLE" "$@" < "${STDIN_FILE:-/dev/null}" > "$WORK/out" 2> "$WORK/err"
RC=$?
if [ "$STREAM" = stderr ]; then
	GOT="$WORK/err"
	WHICH="standard error"
else
	GOT="$WORK/out"
	WHICH="standard output"
fi

SAME=1
cmp -s "$EXPECTED" "$GOT" || SAME=0
STATUS_OK=1
[ -z "$EXPECT_EXIT" ] || [ "$RC" = "$EXPECT_EXIT" ] || STATUS_OK=0

_name=${EXPECTED##*/}
if [ "$SAME" = 1 ] && [ "$STATUS_OK" = 1 ]; then
	if [ -n "$EXPECT_EXIT" ]; then
		echo "model_check: OK — $_name is the model's answer for this case on $WHICH, byte for byte, and so is its status, $RC."
	else
		echo "model_check: OK — $_name is the model's answer for this case on $WHICH, byte for byte."
	fi
	exit 0
fi

echo "model_check: FAIL — the case's expected file, or the status it names, is not"
echo "             what the model it was made from answers for it."
# THE RUN, as every runner says one (rl_ran). A run folder is a temporary
# one, removed when this exits, so it is never named: what it held is listed,
# each file with where it came from, which is what a run by hand rebuilds.
if [ -n "$RUN_AS" ]; then
	rl_ran oracle "$STDIN_GIVEN" "$RUN_AS=$ORACLE_GIVEN$CWD_FILES" "$@"
else
	rl_ran oracle "$STDIN_GIVEN" "" "$@"
	echo "     from $PWD"
fi
if [ "$SAME" = 0 ]; then
	echo "  $WHICH differs from $_name:"
	printf '    the file:   '; rl_vis lines < "$EXPECTED"; printf '\n'
	printf '    the model:  '; rl_vis lines < "$GOT"; printf '\n'
fi
if [ "$STATUS_OK" = 0 ]; then
	echo "  the case names status $EXPECT_EXIT (\"exit\"); the model returned $RC."
fi
if [ "$STREAM" = stdout ]; then
	_other="$WORK/err"
else
	_other="$WORK/out"
fi
if [ -s "$_other" ]; then
	echo "  the model's other stream:"
	rl_excerpt "$_other" 6 model-other-stream.txt "    "
fi
echo ""
echo "  The file was made by this run, so one of the two has moved: the file was"
echo "  edited by hand, or the model changed after the file was made. Find which"
echo "  is right -- the model is checked against the tool it imitates, which is"
echo "  where its answers come from -- and make the other agree: regenerate the"
echo "  file with the run above, from where it says, or fix the model. Until"
echo "  then the case's output test grades programs against a file nothing backs."
exit 1
