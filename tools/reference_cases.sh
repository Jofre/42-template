#!/bin/sh
# reference_cases.sh — run every named case of a program with //oracle's
# reference in the student's place (c_program's reference = True; layer
# oracle, complete).
#
# WHY IT EXISTS. A named case binds a run -- its arguments, an argument file,
# the folder it runs from -- to the output it expects. Where the expected
# files come from //oracle (tools/oracle_fixtures.sh), that binding was still
# written twice by hand: once in the reference's list of what it writes
# (Rush 02's "forty_two.txt is ref.dict and 42"), once in the case in the
# project's BUILD file. An edited number, a dictionary swapped for another,
# drifted in silence: oracle_fixtures.sh compares file bytes only, and the
# tree the harness is written on holds a stub, on which every case is red
# anyway. So the reference runs each case as the case is written, and this
# fails the case it does not pass.
#
# HOW. `oracle run PROGRAM ARG...` is the reference program; this puts it
# behind a two-line script that execs it by its absolute path, so the differ
# can run it as it runs any program -- by path, or copied into a case's run
# folder as ./PROGRAM (a case's "cwd_files"), where the copy still finds the
# oracle. Each case is then exactly its output test: tools/diff_output.sh,
# given the case's own arguments, with the script as --bin. The differ keeps
# this test's time budget (RL_DEADLINE, exported by tools/runner_lib.sh).
#
# Usage:
#   reference_cases.sh --oracle PATH --program NAME --differ PATH
#                      --case-run NAME COUNT ARG... [--case-run ...]
#
#   --oracle PATH    //oracle:oracle
#   --program NAME   the subject's executable name: `oracle run NAME` is its
#                    reference, and `oracle run --has NAME` says whether
#                    there is one
#   --differ PATH    tools/diff_output.sh
#   --case-run NAME COUNT ARG...
#                    one case: its name, then the COUNT arguments its output
#                    test hands the differ after --bin -- how the output is
#                    compared, how the program is run, `--`, its argv.
#                    Counted rather than ended by a marker, so an argument
#                    can be anything a case can hold. Repeatable; the three
#                    options above come first.
#
# Exit status: 0 the reference passes every case, 1 it fails one, 2 the
# harness broke (no reference for the program, a malformed --case-run, a
# case the differ could not judge).
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the cases are wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "reference_cases.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require cat chmod mkdir mktemp rm

RL_NAME=reference_cases
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "reference_cases.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"

# conventions: harness tool ORACLE DIFFER -- //oracle's reference program, and tools/diff_output.sh, which runs it through rl_run

ORACLE=""
PROGRAM=""
DIFFER=""
N=0

WORK=$(mktemp -d) || { echo "reference_cases.sh: mktemp failed" >&2; exit 2; }
rl_traps 'rm -rf "$WORK"'

need() { [ "$2" -ge 2 ] || { echo "reference_cases.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--program) need "$1" "$#"; PROGRAM="$2"; shift 2 ;;
		--differ) need "$1" "$#"; DIFFER="$2"; shift 2 ;;
		--case-run)
			if [ $# -lt 3 ]; then
				echo "reference_cases.sh: --case-run needs a name and a count" >&2
				exit 2
			fi
			_name=$2
			_n=$3
			shift 3
			case "$_n" in
				'' | *[!0-9]*)
					echo "reference_cases.sh: --case-run $_name: '$_n' is not a count" >&2
					exit 2 ;;
			esac
			if [ "$#" -lt "$_n" ]; then
				echo "reference_cases.sh: --case-run $_name: $_n argument(s) announced, $# left" >&2
				exit 2
			fi
			N=$((N + 1))
			printf '%s' "$_name" > "$WORK/case$N.name"
			# Each argument as one shell word that gives back its exact bytes
			# (rl_cmdline), for the eval below.
			_w=""
			while [ "$_n" -gt 0 ]; do
				_w="$_w $(rl_cmdline "$1")"
				shift
				_n=$((_n - 1))
			done
			printf '%s' "$_w" > "$WORK/case$N.words" ;;
		*) echo "reference_cases.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$ORACLE" ] && [ -n "$PROGRAM" ] && [ -n "$DIFFER" ] || {
	echo "reference_cases.sh: need --oracle, --program and --differ" >&2
	exit 2
}
[ "$N" -gt 0 ] || { echo "reference_cases.sh: no --case-run: nothing to run" >&2; exit 2; }
[ -f "$DIFFER" ] || { echo "reference_cases.sh: the differ '$DIFFER' is not there" >&2; exit 2; }
[ -x "$ORACLE" ] || { echo "reference_cases.sh: the reference '$ORACLE' is not executable" >&2; exit 2; }
case "$ORACLE" in
	/*) ;;
	*) ORACLE="$(pwd)/$ORACLE" ;;
esac
if ! "$ORACLE" run --has "$PROGRAM" > /dev/null 2>&1; then
	echo "reference_cases.sh: //oracle has no reference program named '$PROGRAM'" >&2
	echo "  (oracle run --has $PROGRAM). Give //oracle one under that name, the" >&2
	echo "  subject's executable name, or drop reference = True from the c_program" >&2
	echo "  that asks for it." >&2
	exit 2
fi

# The program the differ runs: by path, or copied into a run folder.
mkdir "$WORK/ref" || { echo "reference_cases.sh: cannot make $WORK/ref" >&2; exit 2; }
REF="$WORK/ref/prog"
printf '#!/bin/sh\nexec %s run %s "$@"\n' "$(rl_cmdline "$ORACLE")" "$(rl_cmdline "$PROGRAM")" > "$REF" &&
	chmod +x "$REF" || { echo "reference_cases.sh: cannot write $REF" >&2; exit 2; }

# --show-run: the report of a case that fails opens with the run it made,
# the reference standing for the program under its own name. So its RAN line
# names the PROGRAM -- `RAN: rush-02 <path> 14`, a run folder's copy listed
# as `rush-02  a copy of rush-02` -- and not a command anyone can paste: what
# ran in its place is `oracle run PROGRAM` with the same arguments, which
# the log says above the cases. This log is the harness's, at complete,
# and runs no student code; a student's RAN lines are their output tests'.
run_case() {
	sh "$DIFFER" --bin "$REF" --show-run "$PROGRAM" "$@"
}

echo "reference_cases: every case, with \`oracle run $PROGRAM\` in the program's place;"
echo "  a RAN line below calls it $PROGRAM, the program's name, with the case's arguments"
FAILS=0
BROKEN=0
i=1
while [ "$i" -le "$N" ]; do
	_name=$(cat "$WORK/case$i.name")
	_words=$(cat "$WORK/case$i.words")
	eval "run_case $_words" > "$WORK/out" 2>&1
	_rc=$?
	case "$_rc" in
		0) echo "  ok     $_name" ;;
		1)
			FAILS=$((FAILS + 1))
			echo "  FAIL   $_name"
			rl_excerpt "$WORK/out" 40 "reference_cases.$_name.log" "         " ;;
		*)
			BROKEN=$((BROKEN + 1))
			echo "  ERROR  $_name: the differ could not judge it (exit $_rc)"
			rl_excerpt "$WORK/out" 40 "reference_cases.$_name.log" "         " ;;
	esac
	i=$((i + 1))
done

echo ""
if [ "$BROKEN" -gt 0 ]; then
	echo "reference_cases: the differ could not judge $BROKEN of $N case(s): a wiring"
	echo "  error (a file the case names is not staged, an option it does not know),"
	echo "  never a verdict on the cases."
	exit 2
fi
if [ "$FAILS" -eq 0 ]; then
	echo "reference_cases: OK — the reference passes all $N case(s), each run as its"
	echo "  output test runs it."
	exit 0
fi
echo "reference_cases: FAIL — the reference does not pass $FAILS of $N case(s)."
echo "  These are the harness's own cases, never a student's: a case's arguments,"
echo "  its argument file or run folder, or the expected file it names was changed"
echo "  without the rest, or the reference changed. Make the case in the project's"
echo "  BUILD.bazel run what its expected file answers -- that file is the"
echo "  reference's, written by its fixtures arm -- and read the report above for"
echo "  what the reference printed instead."
exit 1
