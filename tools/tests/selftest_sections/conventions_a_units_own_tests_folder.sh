# ------------------------------------ conventions: a unit's own tests folder
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A project whose subject() contract is divided into units keeps a unit's
# material in tests/<unit>/, and its calls name the unit (unit = "<name>")
# where an exercise's give its number. So every rule that finds a module's
# hints by a tests/exNN/ glob, or a call's part by its num, reads a unit's
# folder and a unit = call as well: one that did not passed BSQ's clues
# unread, and took its c_make for a call it could not read. cvun's c-86 is
# one unit, toyu: clues in tests/toyu/ keyed to a basic case, a strict case
# and two hand-written tests' --case, one more in tests/stray/, a folder of
# no unit, and a file of every kind the rules over hints read, in
# tests/toyu/ and in a folder below it; a c_make and a c_program of toyu
# whose program no .gitignore names, and a call naming both num and unit.
# c-87 is an exercise whose tests/ex00 is a byte copy of tests/toyu, and
# an exercise ex20 with a folder of its own below tests/ex20/. c-88 is one
# unit, exam, whose name begins as an exercise's does, and whose c_program
# names it on the call's opening line. The .gitattributes holds the -text
# rule as **/c-piscine-c-8[67]/tests/*/fixtures/**, which covers the
# fixtures/ folder of c-86's unit and of c-87's exercises, never one a
# folder below those, and none of c-88's.
_un_m=c-piscine/c-piscine-c-86
_un_k=c-piscine/c-piscine-c-87
_un_x=c-piscine/c-piscine-c-88
mkdir -p "$WORK/cvun/tools" "$WORK/cvun/$_un_m/tests/toyu/fixtures" \
	"$WORK/cvun/$_un_m/tests/toyu/more" \
	"$WORK/cvun/$_un_m/tests/stray" "$WORK/cvun/$_un_k/tests/ex20/fixtures" \
	"$WORK/cvun/$_un_k/tests/ex20/ft_x/fixtures" \
	"$WORK/cvun/$_un_x/tests/exam/fixtures"
cv_submit "$_un_m $_un_k $_un_x" > "$WORK/cvun/tools/submit.sh"
printf '* text=auto eol=lf\n**/c-piscine-c-8[67]/tests/*/fixtures/** -text\n' > "$WORK/cvun/.gitattributes"
cat > "$WORK/cvun/$_un_m/BUILD.bazel" <<'CVUN_BUILD'
subject(
    grader = "moulinette",
    group = False,
    units = {
        "toyu": unit(page = 1, files = ["Makefile"], allowed = None),
    },
)

c_make(unit = "toyu", artifact = "toy_unit")

c_program(
    unit = "toyu",
    name = "toy_unit_prog",
    cases = [
        {
            "name": "plain",
            "clues": "clues.tsv",
        },
        {
            "name": "odd",
            "level": 2,
            "clues": "clues.tsv",
        },
    ],
)

hand_test(
    name = "toyu_sweep",
    args = [
        "--case",
        "sweep",
    ],
)

hand_test(
    name = "toyu_re-play",
    args = [
        "--case",
        "replay",
    ],
)

c_program(num = "00", unit = "toyu", name = "toy_both")
CVUN_BUILD
printf '%s\t%s\n' \
	'Is the loop reading one byte past the end?' plain \
	"This harness's reading of the toy's open sentence: which one decides?" odd \
	'What does a replay of many maps reach that one map does not?' sweep \
	"This harness's reading of the toy's other open sentence: which one decides?" plain \
	'What does a second replay of the same input show?' replay \
	> "$WORK/cvun/$_un_m/tests/toyu/clues.tsv"
: > "$WORK/cvun/$_un_m/tests/toyu/expected.txt"
printf 'a\r\nb\r\n' > "$WORK/cvun/$_un_m/tests/toyu/fixtures/crlf.map"
printf 'Which folder is this?\n' > "$WORK/cvun/$_un_m/tests/stray/clues.tsv"
# One file of each kind a rule over hints reads, in tests/toyu/ and in a
# folder below it, so that each of those rules' globs is needed.
for _un_d in "$WORK/cvun/$_un_m/tests/toyu" "$WORK/cvun/$_un_m/tests/toyu/more"; do
	printf 'Which byte comes first?\tline 1\n' > "$_un_d/clues_plain.tsv"
	printf 'Which row does the toy read first?\tfirst\n' > "$_un_d/clues_readings.tsv"
	printf 'Which row differs first?\n' > "$_un_d/diff_clues.txt"
	printf '/* A toy harness. */\n' > "$_un_d/diff_toy.c"
	printf '#!/bin/sh\nexit 0\n' > "$_un_d/check.sh"
done
printf 'Which folder is this?\n' > "$WORK/cvun/$_un_m/tests/toyu/more/clues.tsv"
cat > "$WORK/cvun/$_un_k/BUILD.bazel" <<'CVUN_BUILD'
subject(
    grader = "moulinette",
    group = False,
    exercises = {
        "00": exercise(page = 1, dir = "ex00/", files = [], allowed = None),
        "20": exercise(page = 2, dir = "ex20/", files = [], allowed = None),
    },
)
CVUN_BUILD
cp -R "$WORK/cvun/$_un_m/tests/toyu" "$WORK/cvun/$_un_k/tests/ex00"
printf '1: one\r\n' > "$WORK/cvun/$_un_k/tests/ex20/fixtures/crlf.dict"
printf 'a\r\nb\r\n' > "$WORK/cvun/$_un_k/tests/ex20/ft_x/fixtures/crlf.txt"
cat > "$WORK/cvun/$_un_x/BUILD.bazel" <<'CVUN_BUILD'
subject(
    grader = "moulinette",
    group = False,
    units = {
        "exam": unit(page = 1, files = ["Makefile"], allowed = None),
    },
)

c_program(unit = "exam", name = "toy_exam_prog", cases = [
    {"name": "wide", "clues": "clues.tsv"},
])
CVUN_BUILD
printf '%s\t%s\n' \
	'Does the loop stop at the last byte?' wide \
	'Which line does the loop stop at?' gone \
	> "$WORK/cvun/$_un_x/tests/exam/clues.tsv"
printf 'a\n' > "$WORK/cvun/$_un_x/tests/exam/fixtures/plain.txt"
st_mine && env BUILD_WORKSPACE_DIRECTORY="$WORK/cvun" "$SH" "$TOOLS/conventions.sh" \
	--clue-ledger "$WORK/cvun.ledger" > "$WORK/cvun.out" 2>&1
# How many times the rules read c-86's hint files, from the ledger, as <N>:
# each file of tests/toyu/ and of the folder below it, by every rule of
# its kind.
cvun_read() {
	awk -F'\t' -v m="$_un_m" '$2 == m && $3 == "read" { n += $4 } END { printf "<%d>\n", n }' "$WORK/cvun.ledger"
}
# The lines the calls open on, read from the toy: a call added above moves them.
_un_make=$(grep -n '^c_make(unit = "toyu"' "$WORK/cvun/$_un_m/BUILD.bazel" | cut -d: -f1)
_un_both=$(grep -n '^c_program(num = "00", unit' "$WORK/cvun/$_un_m/BUILD.bazel" | cut -d: -f1)
want_out "conventions: every rule over hints reads a unit's tests/<unit>/" \
	'<60>' -- cvun_read
want_broken_none "conventions: ...and the sentinel names no file there" \
	"$_un_m/tests/toyu/" -- \
	cvi_rule cvun 'a rule over hints never read a hint file of its kind'
want_out "conventions: ...but still one in a folder of no unit" \
	"first-red-steps: $_un_m/tests/stray/clues.tsv" -- \
	cvi_rule cvun 'a rule over hints never read a hint file of its kind'
want_broken_none "conventions: a unit's rows are keyed to its c_program's cases" \
	'line 1: plain' -- \
	cvi_rule cvun "$_un_m/tests/toyu/clues.tsv names a case that does not exist"
want_broken_none "conventions: ...and to a hand-written test's --case" \
	'line 3: sweep' -- \
	cvi_rule cvun "$_un_m/tests/toyu/clues.tsv names a case that does not exist"
want_broken_none "conventions: ...whatever else its name holds" \
	'line 5: replay' -- \
	cvi_rule cvun "$_un_m/tests/toyu/clues.tsv names a case that does not exist"
want_out "conventions: a unit named on a c_program's opening line is read" \
	'line 2: gone' -- \
	cvi_rule cvun "$_un_x/tests/exam/clues.tsv names a case that does not exist"
want_broken_none "conventions: ...and its case is one" \
	'line 1: wide' -- \
	cvi_rule cvun "$_un_x/tests/exam/clues.tsv names a case that does not exist"
# How many times c-88's dead label is reported, as <N>: a unit whose name
# begins with ex is read once, not by an exercise's glob and then again.
cvun_once() {
	_cvu_n=$(cv_saved "$WORK/cvun.out" grep -c "^  FAIL: $_un_x/tests/exam/clues.tsv names a case")
	_cvu_rc=$?
	printf '<%s>\n' "$_cvu_n"
	return "$_cvu_rc"
}
want_out "conventions: ...once, though its name begins as an exercise's" \
	'<1>' -- cvun_once
want_out "conventions: a basic case's row in a unit's clues names a reading" \
	"$_un_m/tests/toyu/clues.tsv:4:" -- \
	cvi_rule cvun "a hint a basic test prints names this harness's reading"
want_broken_none "conventions: ...never a strict case's" \
	"$_un_m/tests/toyu/clues.tsv:2:" -- \
	cvi_rule cvun "a hint a basic test prints names this harness's reading"
want_out "conventions: a unit's c_make program no .gitignore names" \
	"$_un_m/deliverable/toy_unit ($_un_m/BUILD.bazel:$_un_make)" -- \
	cvi_rule cvun 'No .gitignore keeps a program the project builds out of commits'
want_broken_none "conventions: ...not its c_program's beside it" \
	'toy_unit_prog' -- \
	cvi_rule cvun 'No .gitignore keeps a program the project builds out of commits'
want_broken_none "conventions: ...and a call that names a unit is read" \
	"$_un_m/BUILD.bazel:$_un_make:" -- \
	cvi_rule cvun 'A program the project builds cannot be read from its BUILD file'
want_out "conventions: ...but one that names both num and unit is said" \
	"$_un_m/BUILD.bazel:$_un_both: a c_program call whose num, unit or program name is not one string" -- \
	cvi_rule cvun 'A program the project builds cannot be read from its BUILD file'
want_out "conventions: a unit's tests/<unit>/ copied as an exercise's" \
	"$_un_m/tests/toyu and $_un_k/tests/ex00" -- \
	cvi_rule cvun "a unit's test folder is a copy"
want_out "conventions: a CR LF in a fixtures/ folder below an exercise's" \
	"    $_un_k/tests/ex20/ft_x/fixtures/crlf.txt" -- \
	cvi_rule cvun "a file holds a CR byte that .gitattributes' text rule strips"
want_broken_none "conventions: ...never one in a unit's fixtures/" \
	'toyu/fixtures/crlf.map' -- \
	cvi_rule cvun "a file holds a CR byte that .gitattributes' text rule strips"
want_broken_none "conventions: ...nor in an exercise's" \
	'ex20/fixtures/crlf.dict' -- \
	cvi_rule cvun "a file holds a CR byte that .gitattributes' text rule strips"
want_out "conventions: ...and the report names a unit's fixtures/ folder" \
	'tests/<unit>/fixtures/' -- \
	cvi_rule cvun "a file holds a CR byte that .gitattributes' text rule strips"
want_out "conventions: a unit's fixtures/ folder no -text rule covers" \
	"    $_un_x/tests/exam/fixtures/" -- \
	cvi_rule cvun "a fixtures/ folder of an exercise or a unit is not exempt"
want_broken_none "conventions: ...never one a -text rule covers" \
	"$_un_m/tests/toyu/fixtures/" -- \
	cvi_rule cvun "a fixtures/ folder of an exercise or a unit is not exempt"
want_broken_none "conventions: ...nor one below an exercise's" \
	'ft_x/fixtures/' -- \
	cvi_rule cvun "a fixtures/ folder of an exercise or a unit is not exempt"

