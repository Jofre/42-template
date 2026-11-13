# ------------------------------------------------------------ reference_cases
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Every named case of a program, run with //oracle's reference in the
# student's place (c_program's reference = True): a case whose run and
# expected file drifted apart is red on any tree. A fake oracle answers `run
# --has toy` and `run toy ARG...`, which prints the first line of the toy.dict
# in the folder it runs from, if there is one, then each argument -- or,
# for a first argument "open", nothing, a reason on stderr and status 2: no
# answer, as a reference says for a run the subject leaves open.
mkdir -p "$WORK/rc"
{
	printf '%s\n' '#!/bin/sh' '[ "$1" = run ] || exit 2' 'shift' \
		'if [ "$1" = --has ]; then [ "$2" = toy ]; exit; fi' \
		'[ "$1" = toy ] || exit 2' 'shift' \
		'if [ "${1-}" = open ]; then echo "oracle run toy: no answer: open run" >&2; exit 2; fi' \
		'[ -f toy.dict ] && head -n 1 toy.dict' \
		'for a in "$@"; do printf "%s\n" "$a"; done'
} > "$WORK/rc/oracle.sh"
chmod +x "$WORK/rc/oracle.sh"
printf 'x\n' > "$WORK/rc/x.txt"
printf 'y\n' > "$WORK/rc/y.txt"
printf '\n' > "$WORK/rc/empty_line.txt"
printf '\n' > "$WORK/rc/empty.argv"
printf 'word\n' > "$WORK/rc/d.dict"
printf 'word\nx\n' > "$WORK/rc/word_x.txt"
rc_run() { "$SH" "$TOOLS/reference_cases.sh" --oracle "$WORK/rc/oracle.sh" --program toy \
	--differ "$TOOLS/diff_output.sh" "$@"; }
want_green "reference_cases: a case the reference passes is green" -- \
	rc_run --case-run plain 4 --expected "$WORK/rc/x.txt" -- x
want_red   "reference_cases: a case whose argv no longer gives its file is red" -- \
	rc_run --case-run plain 4 --expected "$WORK/rc/x.txt" -- x \
	--case-run drift 4 --expected "$WORK/rc/x.txt" -- y
want_out   "reference_cases: ...naming it" 'FAIL   drift' -- \
	rc_run --case-run plain 4 --expected "$WORK/rc/x.txt" -- x \
	--case-run drift 4 --expected "$WORK/rc/x.txt" -- y
want_out   "reference_cases: ...with the run it made" 'RAN: toy y' -- \
	rc_run --case-run drift 4 --expected "$WORK/rc/x.txt" -- y
# That RAN line calls the reference by the program's name, which no shell
# can run as it stands: the log says what ran in its place.
want_out   "reference_cases: ...and says what that RAN line stands for" \
	'a RAN line below calls it toy, the program'"'"'s name' -- \
	rc_run --case-run drift 4 --expected "$WORK/rc/x.txt" -- y
# What shapes the run reaches the reference as it reaches the program: an
# empty argument from a file, the folder a case runs from (where the copy of
# the reference still finds the oracle), the files a case accepts, and an
# argument that looks like an option, which the count carries through.
want_green "reference_cases: an argument file reaches the reference" -- \
	rc_run --case-run argfile 5 --expected "$WORK/rc/empty_line.txt" --argv-file "$WORK/rc/empty.argv" --
want_green "reference_cases: ...and so does a run folder" -- \
	rc_run --case-run folder 8 --expected "$WORK/rc/word_x.txt" --run-as toy \
	--cwd-file "toy.dict=$WORK/rc/d.dict" -- x
want_red   "reference_cases: ...whose file is the case's" -- \
	rc_run --case-run folder 8 --expected "$WORK/rc/x.txt" --run-as toy \
	--cwd-file "toy.dict=$WORK/rc/d.dict" -- x
want_green "reference_cases: either of the files a case accepts" -- \
	rc_run --case-run alt 6 --expected "$WORK/rc/x.txt" --expected-alt "$WORK/rc/y.txt" -- y
want_out   "reference_cases: an argument after -- is the program's" 'FAIL   dashes' -- \
	rc_run --case-run dashes 5 --expected "$WORK/rc/x.txt" -- --case-run x
# A run the reference has no answer for: printing nothing is an answer a
# program can give, so an empty expected file would pass the differ, and a
# case would settle what the subject leaves open. Only a survive case, which
# compares no output, may make such a run; an argument "--survive" after --
# is the program's, not the case's.
: > "$WORK/rc/nothing.txt"
want_red   "reference_cases: a case held to a run the reference has no answer for is red" -- \
	rc_run --case-run open 4 --expected "$WORK/rc/nothing.txt" -- open
want_out   "reference_cases: ...naming the case and quoting the reference's reason" \
	'no answer: open run' -- rc_run --case-run open 4 --expected "$WORK/rc/nothing.txt" -- open
want_out   "reference_cases: ...in the case's own FAIL line" 'FAIL   open: the reference has no answer' -- \
	rc_run --case-run open 4 --expected "$WORK/rc/nothing.txt" -- open
want_green "reference_cases: ...but a survive case may make that run" -- \
	rc_run --case-run open 3 --survive -- open
want_red   "reference_cases: ...and an argument --survive after -- does not make one" -- \
	rc_run --case-run open 5 --expected "$WORK/rc/nothing.txt" -- open --survive
want_broken "reference_cases: a program //oracle has no reference for is refused" \
	"no reference program named 'other'" -- \
	"$SH" "$TOOLS/reference_cases.sh" --oracle "$WORK/rc/oracle.sh" --program other \
	--differ "$TOOLS/diff_output.sh" --case-run plain 4 --expected "$WORK/rc/x.txt" -- x
want_broken "reference_cases: a count past the arguments is refused" '3 argument(s) announced, 2 left' -- \
	rc_run --case-run short 3 -- x
want_broken "reference_cases: no case is refused" 'nothing to run' -- rc_run
want_broken "reference_cases: a case the differ cannot judge is no verdict" 'could not judge' -- \
	rc_run --case-run lost 4 --expected "$WORK/rc/missing.txt" -- x

