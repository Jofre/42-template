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
# AN ARGUMENT TABLE (--argv-table, c_argv_table's exNN_model) is the same
# question asked of every row at once. Its table.txt was emitted once, by
# hand, with `argv_table.sh --emit` from a reference program, and nothing
# held it to one afterwards. Here the model stands in that program's place:
# argv_table.sh --emit runs it once per row of the scenarios file, as the
# table was made, and the stream it prints is compared with the file.
#
# Usage:
#   model_check.sh --oracle PATH --expected FILE [--stream stdout|stderr]
#                  [--stdin FILE] [--argv-file FILE]
#                  [--run-as NAME [--cwd-file DEST=SRC]...]
#                  [--exit N] [--absent NAME]... -- WORD...
#   model_check.sh --oracle PATH --expected TABLE --argv-table PATH
#                  --scenarios FILE -- WORD...
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
#   --argv-table  tools/argv_table.sh: the expected file is an argument
#               table, and the model's words are the program it is made from
#               (C 06 ex01: c06_run print), run once per row of --scenarios.
#               Takes none of the case options above.
#   --scenarios the table's scenarios file
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
require awk chmod cmp mktemp rm

RL_NAME=model_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "model_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"

# conventions: runs no student code -- it runs //oracle's model on a case's arguments
# conventions: harness tool ORACLE -- the Rust reference (//oracle), whose model made the fixture
# conventions: harness tool TABLE -- tools/argv_table.sh, which runs the model, never a student's program, once per row

ORACLE=""
EXPECTED=""
STREAM=stdout
STDIN_FILE=""
EXPECT_EXIT=""
ABSENT=""
ARGV_FILE=""
RUN_AS=""
CWD_FILES=""
TABLE=""
SCENARIOS=""
CASE_OPT=""

need() { [ "$2" -ge 2 ] || { echo "model_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--expected) need "$1" "$#"; EXPECTED="$2"; shift 2 ;;
		--stream) need "$1" "$#"; STREAM="$2"; CASE_OPT=$1; shift 2 ;;
		--stdin) need "$1" "$#"; STDIN_FILE="$2"; CASE_OPT=$1; shift 2 ;;
		--exit) need "$1" "$#"; EXPECT_EXIT="$2"; CASE_OPT=$1; shift 2 ;;
		--absent) need "$1" "$#"; ABSENT="$ABSENT
$2"; CASE_OPT=$1; shift 2 ;;
		--argv-file) need "$1" "$#"; ARGV_FILE="$2"; CASE_OPT=$1; shift 2 ;;
		--run-as) need "$1" "$#"; RUN_AS="$2"; CASE_OPT=$1; shift 2 ;;
		--cwd-file) need "$1" "$#"; CWD_FILES="$CWD_FILES
$2"; CASE_OPT=$1; shift 2 ;;
		--argv-table) need "$1" "$#"; TABLE="$2"; shift 2 ;;
		--scenarios) need "$1" "$#"; SCENARIOS="$2"; shift 2 ;;
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
if [ -n "$TABLE$SCENARIOS" ]; then
	[ -n "$TABLE" ] && [ -n "$SCENARIOS" ] || {
		echo "model_check.sh: --argv-table and --scenarios go together: the table is made from its scenarios" >&2
		exit 2
	}
	[ -z "$CASE_OPT" ] || {
		echo "model_check.sh: --argv-table checks a whole table, run row by row from --scenarios;" >&2
		echo "                it takes none of a case's options (given: $CASE_OPT)" >&2
		exit 2
	}
	[ -f "$TABLE" ] || { echo "model_check.sh: --argv-table '$TABLE' is not there" >&2; exit 2; }
	[ -r "$SCENARIOS" ] || { echo "model_check.sh: cannot read --scenarios '$SCENARIOS'" >&2; exit 2; }
fi

WORK=$(mktemp -d) || exit 2
rl_traps 'rm -rf "$WORK"'

# AN ARGUMENT TABLE: the model behind a small script, which argv_table.sh
# --emit runs as the program, once per row, from here. The script notes a
# row the model gave no answer for (a status other than 0): --emit refuses
# that run as it refuses a crash, and the note is what lets the refusal name
# the model's command rather than only the script that stood in for it.
if [ -n "$TABLE" ]; then
	case "$ORACLE" in /*) ;; *) ORACLE="$PWD/$ORACLE" ;; esac
	printf '#!/bin/sh\n%s "$@"\n_rc=$?\n[ "$_rc" = 0 ] || echo "$_rc" >> %s\nexit "$_rc"\n' \
		"$(rl_cmdline "$ORACLE" "$@")" "$(rl_cmdline "$WORK/no_answer")" > "$WORK/model" &&
		chmod +x "$WORK/model" || { echo "model_check.sh: cannot write $WORK/model" >&2; exit 2; }
	sh "$TABLE" --emit --bin "$WORK/model" --scenarios "$SCENARIOS" > "$WORK/out" 2> "$WORK/err"
	_rc=$?
	if [ -s "$WORK/no_answer" ]; then
		echo "model_check.sh: the model returned a status other than 0 on a row of" >&2
		echo "                ${SCENARIOS##*/} (oracle $(rl_cmdline "$@")): it has no answer" >&2
		echo "                there, so the table cannot be checked against it." >&2
		exit 2
	fi
	if [ "$_rc" != 0 ]; then
		echo "model_check.sh: argv_table.sh --emit could not make the table from the model" >&2
		echo "                (exit $_rc); what it said:" >&2
		rl_excerpt "$WORK/err" 20 model-table-emit.txt "    " >&2
		exit 2
	fi
	_name=${EXPECTED##*/}
	if cmp -s "$EXPECTED" "$WORK/out"; then
		echo "model_check: OK — $_name is the table the model makes, row for row, from ${SCENARIOS##*/}."
		exit 0
	fi
	echo "model_check: FAIL — the expected table is not the one the model makes"
	echo "             from its scenarios."
	echo "  The model: oracle $(rl_cmdline "$@"), run once per row of ${SCENARIOS##*/}"
	echo "  by argv_table.sh --emit."
	# Each row that differs, both ways, five at most: a row is one line.
	: > "$WORK/rows"
	LC_ALL=C awk -v w="$WORK" '
		FILENAME == ARGV[1] { e[FNR] = $0; ne = FNR; next }
		{ g[FNR] = $0; ng = FNR }
		END {
			n = (ne > ng) ? ne : ng
			for (i = 1; i <= n && k < 5; i++) {
				if ((i in e) && (i in g) && e[i] == g[i]) continue
				k++
				printf "%d\n", i > (w "/rows")
				if (i in e) printf "%s\n", e[i] > (w "/e" k); else printf "" > (w "/e" k)
				if (i in g) printf "%s\n", g[i] > (w "/g" k); else printf "" > (w "/g" k)
			}
		}' "$EXPECTED" "$WORK/out"
	_k=0
	while IFS= read -r _row; do
		_k=$((_k + 1))
		echo "  row $_row:"
		printf '    the file:   '; rl_vis lines < "$WORK/e$_k"; printf '\n'
		printf '    the model:  '; rl_vis lines < "$WORK/g$_k"; printf '\n'
	done < "$WORK/rows"
	[ "$_k" -gt 0 ] || echo "  Every row reads the same, and the files still differ: in how the last row ends."
	echo ""
	echo "  The table was emitted from a reference program, and one of the two has"
	echo "  moved: the file was edited by hand, a row of the scenarios changed"
	echo "  without it, or the model changed. Find which is right, and make the"
	echo "  other agree: emit the table again with argv_table.sh --emit, the model"
	echo "  above as --bin, or fix the model. Until then the table grades programs"
	echo "  against rows nothing backs."
	exit 1
fi

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
