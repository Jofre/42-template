# ------------------------------------- conventions: a library's function folders
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A library's functions (Libft): its contract makes the library a unit and
# lists them as the keys of its `functions`, and each function is a unit of
# its own, its tests in tests/<function>/ and its targets named
# <function>_<layer>. Every rule that read tests/exNN/ alone passed those
# folders over, green, having read nothing in them. cvlb holds such a
# project, cursus/Milestone_9/Toylib, beside a Piscine module,
# c-piscine/c-piscine-c-79. Its function folders hold, each file once, what
# each rule exists to report, and one that rule must leave quiet:
#   ft_toylen/clues.tsv       a step list in a first-red row (line 2), a wider
#                             type (3), a label no case has (5), a reading
#                             named in other words (6) and with the label (7),
#                             in a file a basic test prints; and, quiet,
#                             numbered steps keyed past the third row (4: a
#                             function is neither a program, whose every case
#                             shows its rows, nor a shell exercise) and "the
#                             base case" (1): this function's call says
#                             method = "recursive";
#   ft_toylen/clues_strict.tsv  the label, quiet: a strict call hands it;
#   ft_toylen/clues_typo.tsv  a label no expected file of the folder holds;
#   ft_toylen/clues_readings.tsv  says robust, where its target,
#                             ft_toylen_readings, sits at strict;
#   ft_toylen/diff_clues.txt  the accumulator's type;
#   ft_toylen/toy.sh          the label in a line a basic test prints;
#   ft_toylen/cyc_toylen.c    the harness a function's c_cycles names, whose
#                             unit counts a hex column unhalved;
#   ft_toylen/helper.c        defines ft_toylen, a key of `functions`, with a
#                             body, and ft_toyvalue, a string of a key's
#                             value, which no function turns in (quiet);
#   ft_toydup/clues.tsv       "the base case", reported: its call says no
#                             method;
#   ft_toydup/diff_clues.txt  a legend: "the base case" (line 1) and a
#                             reading in other words (2), each reported;
#   ft_toydup/diff_toydup.c   a harness whose "Line:" paragraph peels
#                             digits (line 2), reported;
#   ft_toydup/toy.sh          a reading in other words in what it prints
#                             (line 2), reported;
#   ft_toydup/test_toydup.c   the sanitize harness of a function's c_function,
#                             found in its folder (quiet);
#   ft_toydup/expected.txt    the labels of that call, which is labeled and
#                             written on one line (quiet);
#   ft_toydup/mem_toydup.c    the probe a function's c_mem_check names, found
#                             in its folder, with no header (reported);
#   ft_strnstr/               a copy of c-79's ex05, three files: a copy
#                             no c_twin declares; toylib/fixtures/, the same
#                             copy of ex06 in the library's own folder, is no
#                             function's folder (quiet).
# And ft_strnstr, a key, has no page in the toy image (reported), while
# ft_strlcpy's page is there (quiet). The cycles row names Toylib ft_other
# where the function's call sets max_unit (reported), then Toylib ft_toylen
# (quiet), on a second run.
_lb=$WORK/cvlb/cursus/Milestone_9/Toylib
_lb79=$WORK/cvlb/c-piscine/c-piscine-c-79
mkdir -p "$WORK/cvlb/tools" "$WORK/cvlb/docs" "$WORK/cvlb/.devcontainer" \
	"$_lb/tests/ft_toylen" "$_lb/tests/ft_toydup" "$_lb/tests/ft_strnstr" \
	"$_lb/tests/toylib/fixtures" "$_lb79/tests/ex05" "$_lb79/tests/ex06"
cv_submit "c-piscine/c-piscine-c-79 cursus/Milestone_9/Toylib" > "$WORK/cvlb/tools/submit.sh"
: > "$_lb79/BUILD.bazel"
{
	printf 'subject(\n    grader = "moulinette",\n    units = {\n'
	printf '        "toylib": unit(\n'
	printf '            files = ["Makefile", "toylib.h"],\n'
	printf '            functions = {\n'
	printf '                "ft_toylen": [],  # it may call nothing {\n'
	printf '                "ft_toydup": [\n                    "malloc",\n'
	printf '                    "ft_toyvalue",\n                ],\n'
	printf '                "ft_strnstr": [], "ft_strlcpy": [],\n'
	printf '            },\n        ),\n    },\n)\n\n'
	printf 'c_function(\n    unit = "ft_toylen",\n    method = "recursive",\n'
	printf '    clues = "clues_strict.tsv",\n    level = 2,\n)\n\n'
	printf 'c_cycles(\n    unit = "ft_toylen",\n    harness = "cyc_toylen.c",\n'
	printf '    unit_expr = "length($1)",\n    max_unit = 1000,\n)\n\n'
	printf 'c_function(unit = "ft_toydup", sanitize = True, test = "test_toydup.c", labeled = True)\n\n'
	printf 'c_mem_check(unit = "ft_toydup", probe = "mem_toydup.c")\n'
} > "$_lb/BUILD.bazel"
printf 'one\tx\n' > "$_lb/tests/ft_toylen/expected.txt"
{
	printf 'What is the base case here?\tone\n'
	printf 'Fold it, then cut it.\tone\n'
	printf 'Which wider type holds the sum?\tone\n'
	printf '1) Fold it. 2) Cut it.\tone\n'
	printf 'Does it stop?\tnocase\n'
	printf 'Which line does the reading this harness takes keep?\tone\n'
	printf '%s\tone\n' "Which line does this harness's reading keep?"
} > "$_lb/tests/ft_toylen/clues.tsv"
printf '%s\tone\n' "Which line does this harness's reading keep?" \
	> "$_lb/tests/ft_toylen/clues_strict.tsv"
printf 'Which one?\tnolabel\n' > "$_lb/tests/ft_toylen/clues_typo.tsv"
printf 'Which sentence decides, at robust?\n' > "$_lb/tests/ft_toylen/clues_readings.tsv"
printf '  Text in, a number out.\n    * only long inputs  -> the accumulator%ss type\n' "'" \
	> "$_lb/tests/ft_toylen/diff_clues.txt"
printf '#!/bin/sh\necho "%s"\n' "Which line does this harness's reading keep?" \
	> "$_lb/tests/ft_toylen/toy.sh"
printf '/*\n * Line: <hexIn>\\t<count>\n */\nint\tmain(void)\n{\n\treturn (0);\n}\n' \
	> "$_lb/tests/ft_toylen/cyc_toylen.c"
printf 'int\tft_toylen(int n)\n{\n\tn++;\n\treturn (n);\n}\n\nint\tft_toyvalue(int n)\n{\n\tn++;\n\treturn (n);\n}\n' \
	> "$_lb/tests/ft_toylen/helper.c"
printf 'What is the base case here?\n' > "$_lb/tests/ft_toydup/clues.tsv"
printf '    * one long word  -> the base case\n    * two lines  -> the reading this harness takes\n' \
	> "$_lb/tests/ft_toydup/diff_clues.txt"
printf '/*\n * Line: <in>\\t<out>, the count after peeling digits\n */\nint\tmain(void)\n{\n\treturn (0);\n}\n' \
	> "$_lb/tests/ft_toydup/diff_toydup.c"
printf '#!/bin/sh\necho "%s"\n' "Which line does the reading this harness takes keep?" \
	> "$_lb/tests/ft_toydup/toy.sh"
printf 'int\tputs(const char *s);\n\nint\tmain(void)\n{\n\tputs("@addr");\n\treturn (0);\n}\n' \
	> "$_lb/tests/ft_toydup/test_toydup.c"
printf 'two\ty\n' > "$_lb/tests/ft_toydup/expected.txt"
printf 'int\tmain(void)\n{\n\treturn (0);\n}\n' > "$_lb/tests/ft_toydup/mem_toydup.c"
for _f in one.txt two.txt three.txt; do
	printf 'made up for the selftest, a function folder: %s\n' "$_f" > "$_lb79/tests/ex05/$_f"
	cp "$_lb79/tests/ex05/$_f" "$_lb/tests/ft_strnstr/$_f"
	printf 'made up for the selftest, no function folder: %s\n' "$_f" > "$_lb79/tests/ex06/$_f"
	cp "$_lb79/tests/ex06/$_f" "$_lb/tests/toylib/fixtures/$_f"
done
printf 'RUN dpkg-deb --fsys-tarfile /tmp/libbsd-dev.deb | tar -x ./usr/share/man/man3/strlcpy.3bsd.gz\n' \
	> "$WORK/cvlb/.devcontainer/Dockerfile"
printf '| `cycles` | complete | some cases left out (`c_cycles`'"'"' `max_unit`: Toylib ft_other), and said |\n' \
	> "$WORK/cvlb/docs/reference.md"
convlb() { env BUILD_WORKSPACE_DIRECTORY="$WORK/cvlb" "$SH" "$TOOLS/conventions.sh"; }
if st_mine; then
	convlb > "$WORK/cvlb.out" 2>&1
	printf '| `cycles` | complete | some cases left out (`c_cycles`'"'"' `max_unit`: Toylib ft_toylen), and said |\n' \
		> "$WORK/cvlb/docs/reference.md"
	convlb > "$WORK/cvlb2.out" 2>&1
fi
_lbt=cursus/Milestone_9/Toylib/tests
want_out "conventions: a function folder's readings hint names its own target" \
	"$_lbt/ft_toylen/clues_readings.tsv says its target sits at robust, and ft_toylen_readings sits at strict" -- \
	cvi_rule cvlb 'says its target sits at'
want_out "conventions: a function folder's first-red row is read" \
	"$_lbt/ft_toylen/clues.tsv has a first-red hint written as steps" -- \
	cvi_rule cvlb 'has a first-red hint'
want_out "conventions: ...its row 2, an instruction chained" \
	'line 2 (' -- cvi_rule cvlb "$_lbt/ft_toylen/clues.tsv has a first-red hint"
want_broken_none "conventions: ...never a keyed row past the third, a function being no shell exercise" \
	'line 4' -- cvi_rule cvlb "$_lbt/ft_toylen/clues.tsv has a first-red hint"
want_out "conventions: a function folder's clue naming a wider type" \
	"$_lbt/ft_toylen/clues.tsv:3:" -- cvi_rule cvlb 'answers an overflow with a wider type'
want_out "conventions: ...and its legend" \
	"$_lbt/ft_toylen/diff_clues.txt:2:" -- cvi_rule cvlb 'answers an overflow with a wider type'
want_out "conventions: a function folder's clue naming a case it lacks" \
	'line 5: nocase' -- cvi_rule cvlb "$_lbt/ft_toylen/clues.tsv names a case that does not exist"
want_out "conventions: ...and its case's own hint file" \
	"$_lbt/ft_toylen/clues_typo.tsv names a case that no expected file" -- \
	cvi_rule cvlb 'names a case that no expected file'
want_out "conventions: a function's method named where its call asks for none" \
	"$_lbt/ft_toydup/clues.tsv:1:" -- cvi_rule cvlb 'step of a known method'
want_broken_none "conventions: ...never where the function's own call says recursive" \
	"$_lbt/ft_toylen/clues.tsv:1:" -- cvi_rule cvlb 'step of a known method'
want_out "conventions: ...nor in a function folder's legend" \
	"$_lbt/ft_toydup/diff_clues.txt:1:" -- cvi_rule cvlb 'step of a known method'
want_out "conventions: ...nor in its harness's Line: paragraph" \
	"$_lbt/ft_toydup/diff_toydup.c:2:" -- cvi_rule cvlb 'step of a known method'
want_out "conventions: a function folder's clue naming a reading in other words" \
	"$_lbt/ft_toylen/clues.tsv:6:" -- cvi_rule cvlb 'named in other words'
want_out "conventions: ...and in a function folder's legend" \
	"$_lbt/ft_toydup/diff_clues.txt:2:" -- cvi_rule cvlb 'named in other words'
want_out "conventions: ...and in a function folder's script" \
	"$_lbt/ft_toydup/toy.sh:2:" -- cvi_rule cvlb 'named in other words'
want_out "conventions: a function folder's basic clue naming the reading" \
	"$_lbt/ft_toylen/clues.tsv:7:" -- cvi_rule cvlb 'a basic test prints names'
want_out "conventions: ...and a script of its folder" \
	"$_lbt/ft_toylen/toy.sh:2:" -- cvi_rule cvlb 'a basic test prints names'
want_broken_none "conventions: ...never the file the function's strict call hands" \
	'clues_strict.tsv' -- cvi_rule cvlb 'a basic test prints names'
want_out "conventions: a function's c_cycles harness is read in its folder" \
	'length($1) counts <hexIn>, two hex digits a byte' -- cvi_rule cvlb 'c_cycles(unit = "ft_toylen")'"'"'s unit_expr'
want_broken_none "conventions: ...as a function's sanitize harness is" \
	'test_toydup.c' -- cvi_rule cvlb 'sanitize harness'
want_broken_none "conventions: ...nor read by its num where it names a unit" \
	'cannot find its harness' -- cvi_rule cvlb 'sanitize = True'
want_broken_none "conventions: ...and the labels of a labeled call on one line" \
	'Toylib' -- cvi_rule cvlb 'label rule cannot name'
want_out "conventions: ...and the probe of a function's c_mem_check" \
	"$_lbt/ft_toydup/mem_toydup.c:1: opens with no header comment" -- \
	cvi_rule cvlb 'does not open with a header of its own'
want_out "conventions: a library's function defined outside the zone" \
	"$_lbt/ft_toylen/helper.c:1: defines ft_toylen, which cursus/Milestone_9/Toylib toylib turns in (a function of its library)" -- \
	cvi_rule cvlb 'has the student turn in is written outside the zone'
want_broken_none "conventions: ...never a name of a key's value" \
	'ft_toyvalue' -- cvi_rule cvlb 'has the student turn in is written outside the zone'
want_out "conventions: a function folder copied from another module's exercise" \
	"c-piscine/c-piscine-c-79/tests/ex05 and $_lbt/ft_strnstr" -- \
	cvi_rule cvlb "a unit's test folder is a copy"
want_broken_none "conventions: ...never a folder no function is named for" \
	'fixtures' -- cvi_rule cvlb "a unit's test folder is a copy"
# c_twin names whole exercises, and a function's folder is a unit's, no
# exercise's, so the remedy cannot be c_twin.
want_out "conventions: ...saying c_twin cannot declare it" \
	'which c_twin cannot declare' -- cvi_rule cvlb "a unit's test folder is a copy"
want_broken_none "conventions: ...and offering no c_twin call" \
	'c_twin(num =' -- cvi_rule cvlb "a unit's test folder is a copy"
# Its remedy covers both cases: two subjects that differ, and a function
# that truly repeats the other exercise, which nothing can declare yet.
want_out "conventions: ...telling tests whose subjects differ to differ" \
	'If the subjects differ, make their tests differ where the subjects do.' -- \
	cvi_rule cvlb "a unit's test folder is a copy"
want_out "conventions: ...and saying what a true copy waits for" \
	'c_twin takes no unit, and teaching it one is the fix.' -- \
	cvi_rule cvlb "a unit's test folder is a copy"
want_broken_none "conventions: ...nor reported as an exercise's copy" \
	'ft_strnstr' -- cvi_rule cvlb 'a test folder is a copy of another'
want_out "conventions: a library's libbsd-only function, its page not in the image" \
	'turns in ft_strnstr, a function of its library, and the image has no strnstr.3bsd' -- \
	cvi_rule cvlb 'does not carry the manual page'
want_broken_none "conventions: ...never one whose page the image extracts" \
	'strlcpy' -- cvi_rule cvlb 'does not carry the manual page'
want_out "conventions: a cycles row that misses a library function's max_unit call" \
	'BUILD: Toylib ft_toylen' -- cvi_rule cvlb 'max_unit disagree'
want_broken_none "conventions: ...and one that names it is not" \
	'max_unit disagree' -- cvi_rule cvlb2 'max_unit disagree'
# A contract written in single quotes (V218): Starlark and tools/units.awk
# read 'x' as "x", but the copy detector and answer_scan.sh's c_files() and
# artifact readers match "..." alone, so a 'toysq.h' in `files` was no file
# to them, with no red. cvsq's BUILD file has that one and a key of
# `functions`, 'toy_a' (lines 6 and 7), both reported, and an apostrophe in a
# comment (12) and in a double-quoted string with an escaped quote (13),
# quiet; one in a docstring over two lines (14), quiet, and a literal after a
# one-line docstring (16), reported. A BUILD file in a dot folder the repo
# does not track is no file of the harness (text_files(), V113), and is not
# read.
_sq=$WORK/cvsq/cursus/Milestone_9/Toysq
mkdir -p "$WORK/cvsq/tools" "$_sq"
cv_submit "cursus/Milestone_9/Toysq" > "$WORK/cvsq/tools/submit.sh"
{
	printf 'subject(\n    grader = "moulinette",\n    units = {\n'
	printf '        "toysq": unit(\n            allowed = [],\n'
	printf '            files = ["Makefile", %s],\n' "'toysq.h'"
	printf '            functions = {%s: [], "toy_b": []},\n' "'toy_a'"
	printf '        ),\n    },\n)\n\n'
	printf '# The grader%ss own main, in a comment.\n' "'"
	printf 'c_function(unit = "toy_b", quotes = ["the subject%ss \\"own\\" words"])\n' "'"
	printf '"""A docstring, the grader%ss\nown words."""\n' "'"
	printf 'TOY = """one line""" + %s\n' "'tail'"
} > "$_sq/BUILD.bazel"
mkdir -p "$WORK/cvsq/.vendored"
printf 'x = %s\n' "'vendored'" > "$WORK/cvsq/.vendored/BUILD"
if st_mine; then
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvsq" $SH "$TOOLS/conventions.sh" > "$WORK/cvsq.out" 2>&1
fi
want_out "conventions: a contract's function key in single quotes" \
	"cursus/Milestone_9/Toysq/BUILD.bazel:7: 'toy_a'" -- cvi_rule cvsq 'in single quotes'
want_out "conventions: ...and a turned-in file in them" \
	"cursus/Milestone_9/Toysq/BUILD.bazel:6: 'toysq.h'" -- cvi_rule cvsq 'in single quotes'
want_broken_none "conventions: ...never an apostrophe in a comment" \
	'BUILD.bazel:12:' -- cvi_rule cvsq 'in single quotes'
want_broken_none "conventions: ...nor in a double-quoted string" \
	'BUILD.bazel:13:' -- cvi_rule cvsq 'in single quotes'
want_broken_none "conventions: ...nor in a docstring over two lines" \
	'BUILD.bazel:14:' -- cvi_rule cvsq 'in single quotes'
want_out "conventions: ...while a literal after a closed docstring is reported" \
	"cursus/Milestone_9/Toysq/BUILD.bazel:16: 'tail'" -- cvi_rule cvsq 'in single quotes'
want_broken_none "conventions: ...and a BUILD file in an untracked dot folder is not read" \
	'.vendored/BUILD' -- cvi_rule cvsq 'in single quotes'

