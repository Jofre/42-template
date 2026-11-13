# --------------------------------------- conventions: every hint file is read
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Each rule over a module's hints reaches its files through globs written for
# an exercise's tests/exNN/ and a unit's tests/<unit>/ (a library's function
# being a unit, with its own), and writes down what it did with each one
# (clue_read). A hint file below those folders, or in a folder named for
# neither an exercise nor a unit of its contract, is one no glob reaches, and
# the rule passes having read less: the sentinel names it, with the rule.
# cvcl's c-88 has clues in tests/ex00/ and two folders below it (deep/er/),
# a readings file under tests/toy/, and a header under
# tests/layout/ that is no hint file. Its c-87 writes an exercise by a name,
# which units.awk cannot read, and c-88 has a tests/ex02 its contract does
# not list: (e2)'s two reports. --clue-ledger writes the counts the rules keep.
# And a name with a blank in it is one file: c-86's unit toyb has a
# 'clues copy.tsv', and c-85's tests/ex00 a 'clues_x y.tsv'. A rule that
# walked its list `for c in $(...)` split each into two names, neither a
# file, read neither, and the sentinel named the file.
_cl_m=c-piscine/c-piscine-c-88
_cl_k=c-piscine/c-piscine-c-87
_cl_u=c-piscine/c-piscine-c-86
_cl_x=c-piscine/c-piscine-c-85
mkdir -p "$WORK/cvcl/tools" "$WORK/cvcl/$_cl_m/tests/ex00/deep/er" \
	"$WORK/cvcl/$_cl_m/tests/ex01" "$WORK/cvcl/$_cl_m/tests/ex02" \
	"$WORK/cvcl/$_cl_m/tests/toy" "$WORK/cvcl/$_cl_m/tests/layout" \
	"$WORK/cvcl/$_cl_k/tests/ex00" "$WORK/cvcl/$_cl_u/tests/toyb" \
	"$WORK/cvcl/$_cl_x/tests/ex00"
cv_submit "$_cl_m $_cl_k $_cl_u $_cl_x" > "$WORK/cvcl/tools/submit.sh"
cat > "$WORK/cvcl/$_cl_m/BUILD.bazel" <<'CVCL_CONTRACT'
subject(
    grader = "moulinette",
    group = False,
    exercises = {
        "00": exercise(page = 1, dir = "ex00/", files = [], allowed = None),
        "01": exercise(page = 2, dir = "ex01/", files = [], allowed = None),
    },
)
CVCL_CONTRACT
: > "$WORK/cvcl/$_cl_m/tests/ex00/expected.txt"
printf 'Is the loop reading one byte past the end?\n' > "$WORK/cvcl/$_cl_m/tests/ex00/clues.tsv"
printf 'Is the loop reading one byte past the end?\n' > "$WORK/cvcl/$_cl_m/tests/ex00/deep/er/clues.tsv"
printf 'A legend line.\n' > "$WORK/cvcl/$_cl_m/tests/ex00/deep/er/diff_clues.txt"
printf 'What does the stub return?\n' > "$WORK/cvcl/$_cl_m/tests/ex01/clues.tsv"
printf 'Which reading is this?\n' > "$WORK/cvcl/$_cl_m/tests/toy/clues_readings.tsv"
printf 'struct s;\n' > "$WORK/cvcl/$_cl_m/tests/layout/toy.h"
cat > "$WORK/cvcl/$_cl_k/BUILD.bazel" <<'CVCL_CONTRACT'
subject(
    grader = "moulinette",
    group = False,
    exercises = {
        "00": TOY_EXERCISE,
    },
)
CVCL_CONTRACT
: > "$WORK/cvcl/$_cl_k/tests/ex00/expected.txt"
cat > "$WORK/cvcl/$_cl_u/BUILD.bazel" <<'CVCL_CONTRACT'
subject(
    grader = "moulinette",
    group = False,
    units = {
        "toyb": unit(page = 1, files = ["Makefile"], allowed = None),
    },
)
CVCL_CONTRACT
printf 'Which byte does the copy stop at?\n' > "$WORK/cvcl/$_cl_u/tests/toyb/clues copy.tsv"
cat > "$WORK/cvcl/$_cl_x/BUILD.bazel" <<'CVCL_CONTRACT'
subject(
    grader = "moulinette",
    group = False,
    exercises = {
        "00": exercise(page = 1, dir = "ex00/", files = [], allowed = None),
    },
)
CVCL_CONTRACT
printf 'Which byte does the copy stop at?\n' > "$WORK/cvcl/$_cl_x/tests/ex00/clues_x y.tsv"
st_mine && env BUILD_WORKSPACE_DIRECTORY="$WORK/cvcl" "$SH" "$TOOLS/conventions.sh" \
	--clue-ledger "$WORK/cvcl.ledger" > "$WORK/cvcl.out" 2>&1
# HINT_RULES is written by hand, and held both ways to the patterns the
# rules read by: a copy of conventions.sh whose row for method's
# diff_*.c names a rule nobody runs instead, run over the same tree.
if st_mine; then
	mkdir -p "$WORK/cvclr"
	cp "$TOOLS/units.awk" "$WORK/cvclr/units.awk"
	awk -v q="'" '$0 == "\tmethod " q "diff_*.c" q " \\" { print "\ttoy-rule " q "toy*.tsv" q " \\"; next } { print }' \
		"$TOOLS/conventions.sh" > "$WORK/cvclr/conventions.sh"
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvcl" "$SH" "$WORK/cvclr/conventions.sh" > "$WORK/cvclr.out" 2>&1
fi
# The ledger a line at a time, each in <...>, so an arm pins a whole line.
cvcl_ledger() { sed 's/.*/<&>/' "$WORK/cvcl.ledger"; }
want_out "conventions: a clues file two folders down is one no rule read" \
	"first-red-steps: $_cl_m/tests/ex00/deep/er/clues.tsv" -- \
	cvi_rule cvcl 'a rule over hints never read a hint file of its kind'
want_out "conventions: ...and a legend beside it" \
	"method: $_cl_m/tests/ex00/deep/er/diff_clues.txt" -- \
	cvi_rule cvcl 'a rule over hints never read a hint file of its kind'
want_out "conventions: ...and a readings file outside an exercise's folder" \
	"readings-level: $_cl_m/tests/toy/clues_readings.tsv" -- \
	cvi_rule cvcl 'a rule over hints never read a hint file of its kind'
want_broken_none "conventions: ...never one in an exercise's folder" \
	"$_cl_m/tests/ex00/clues.tsv" -- \
	cvi_rule cvcl 'a rule over hints never read a hint file of its kind'
want_broken_none "conventions: ...nor a file that is no hint" \
	'layout/toy.h' -- \
	cvi_rule cvcl 'a rule over hints never read a hint file of its kind'
want_broken_none "conventions: ...nor a unit's hint file with a blank in its name" \
	"$_cl_u/tests/toyb/clues copy.tsv" -- \
	cvi_rule cvcl 'a rule over hints never read a hint file of its kind'
want_broken_none "conventions: ...nor an exercise's" \
	"$_cl_x/tests/ex00/clues_x y.tsv" -- \
	cvi_rule cvcl 'a rule over hints never read a hint file of its kind'
want_out "conventions: a pattern a rule reads that HINT_RULES lacks" \
	'method reads diff_*.c, a row HINT_RULES lacks' -- \
	cvi_rule cvclr 'HINT_RULES is not the list of what the rules over hints read'
want_out "conventions: ...and a row of it that no rule reads" \
	'HINT_RULES: toy-rule toy*.tsv, which no rule reads' -- \
	cvi_rule cvclr 'HINT_RULES is not the list of what the rules over hints read'
want_broken_none "conventions: ...never the script as it stands" \
	'HINT_RULES is not the list' -- cv_saved "$WORK/cvcl.out"
want_out "conventions: a contract units.awk cannot read, with its line" \
	"units.awk: $_cl_k/BUILD.bazel:5: \"00\" is not written as exercise(...)" -- \
	cvi_rule cvcl 'tools/units.awk cannot read a subject() contract'
want_out "conventions: a tests/exNN the contract has no exercise for" \
	"$_cl_m/BUILD.bazel: ex02" -- \
	cvi_rule cvcl "a project's tests/exNN has no exercise in its subject() contract"
want_broken_none "conventions: ...never one it has" \
	'BUILD.bazel: ex01' -- \
	cvi_rule cvcl "a project's tests/exNN has no exercise in its subject() contract"
want_out "conventions: --clue-ledger counts the files a rule read" \
	"$(printf '<first-red-steps\t%s\tread\t2>' "$_cl_m")" -- cvcl_ledger
want_out "conventions: ...per rule" \
	"$(printf '<dead-label\t%s\tread\t1>' "$_cl_m")" -- cvcl_ledger
want_out "conventions: ...a unit's hint file with a blank in its name among them" \
	"$(printf '<first-red-steps\t%s\tread\t1>' "$_cl_u")" -- cvcl_ledger
want_out "conventions: ...and those it passed over, with why" \
	"$(printf '<dead-label\t%s\tpassed: no expected.txt beside it, and no c_program case of its folder\t1>' "$_cl_m")" -- \
	cvcl_ledger
want_broken "conventions: --clue-ledger needs a file" \
	'conventions.sh: --clue-ledger needs a value' -- \
	"$SH" "$TOOLS/conventions.sh" --clue-ledger

