# ---------------------------------- conventions: registry consumers, CR bytes
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A consumer is a test of the row's own project, which SKIPs naming the path
# while the file is absent. The registry's header promised this was checked,
# and nothing read the column.
printf 'c-piscine/c-piscine-c-98\tdata.bin\tc-piscine/c-piscine-c-98/data.bin\tharness\t*data.bin\t//c-piscine/c-piscine-c-99:ex00_output\tdocs/where.md\tthe intranet\n' \
	> "$WORK/cv/tools/resources.tsv"
want_out "conventions: a consumer outside the row's project is reported" \
	"consumer //c-piscine/c-piscine-c-99:ex00_output is not a target of c-piscine/c-piscine-c-98" -- \
	conv
printf 'c-piscine/c-piscine-c-98\tdata.bin\tc-piscine/c-piscine-c-98/data.bin\tharness\t*data.bin\t//c-piscine/c-piscine-c-98:ex00_output\tdocs/where.md\tthe intranet\n' \
	> "$WORK/cv/tools/resources.tsv"
want_broken_none "conventions: ...and one inside it is not" \
	"consumer //c-piscine" -- \
	conv

# A file the project turns in has its c_issued, whose test is red while the
# file is missing: the template ships no copy and its .gitignore keeps a
# student's out of commits, so nothing else said so (finding 162). Its `file`
# is a name, which c_issued globs, never a label.
_cv_reg=$(cat "$WORK/cv/tools/resources.tsv")
printf 'c-piscine/c-piscine-c-98\tdata.bin\tc-piscine/c-piscine-c-98/data.bin\tturn-in\t*data.bin\t-\tdocs/where.md\tthe intranet\n' \
	> "$WORK/cv/tools/resources.tsv"
want_out "conventions: a turned-in file with no c_issued is reported" \
	'data.bin is turned in, and c-piscine/c-piscine-c-98 has no c_issued' -- \
	conv
cv98 'c_issued(\n    num = "08",\n    file = "data.bin",\n)\nx(\n    fixtures = glob(["data.bin"], allow_empty = True),\n)\n'
! st_mine || conv > "$WORK/cv.issued" 2>&1
want_broken_none "conventions: ...and one with it is not" 'has no c_issued' -- \
	cv_saved "$WORK/cv.issued"
want_broken_none "conventions: ...whose file is a name, not a label" 'breaks the template' -- \
	cv_saved "$WORK/cv.issued"
rm -f "$WORK/cv.issued"
cp "$WORK/cv/b98.orig" "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
printf '%s\n' "$_cv_reg" > "$WORK/cv/tools/resources.tsv"

# The rows' own shape. A path under tests/ was refused as one "the
# template strip spares", which it does not, since it strips the exact name
# wherever it sits; a path whose last name is not the file's was accepted,
# and the strip and the ignore rule, which go by the name, would miss it.
# One run over both rows.
{
	printf '%s\n' "$_cv_reg"
	printf 'c-piscine/c-piscine-c-98\tfix.bin\tc-piscine/c-piscine-c-98/tests/ex08/fix.bin\tharness\t*fix.bin\t-\tdocs/where.md\tthe intranet\n'
	printf 'c-piscine/c-piscine-c-98\todd.bin\tc-piscine/c-piscine-c-98/odd-copy.bin\tharness\t*odd.bin\t-\tdocs/where.md\tthe intranet\n'
} > "$WORK/cv/tools/resources.tsv"
if st_mine; then
	conv > "$WORK/cvrg.out" 2>&1
fi
# That run's report of malformed rows, and its status.
cvrg_rule() { cvi_rule cvrg 'tools/resources.tsv has malformed rows'; }
want_broken_none "conventions: a registered path under tests/ is a row like any other" \
	'fix.bin' -- cvrg_rule
want_out "conventions: ...but one whose last name is not the file's is reported" \
	'odd.bin: path c-piscine/c-piscine-c-98/odd-copy.bin does not end in /odd.bin' -- cvrg_rule
printf '%s\n' "$_cv_reg" > "$WORK/cv/tools/resources.tsv"

# A CR that `* text=auto eol=lf` strips on commit: Rush 02's crlf.dict was
# committed with LF only, so every clone's case tested nothing while the
# checkout that wrote it was green. A file holding a CR must match a -text
# rule of .gitattributes; one with no text rule at all is not checked.
mkdir -p "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex20/fixtures"
printf '1: one\r\n' > "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex20/fixtures/crlf.dict"
printf 'a note\r\n' > "$WORK/cv/c-piscine/c-piscine-c-98/notes.txt"
want_broken_none "conventions: a CR with no text rule in .gitattributes is not checked" \
	'a file holds a CR byte' -- conv
printf '* text=auto eol=lf\n**/tests/ex[0-9][0-9]/fixtures/** -text\n' > "$WORK/cv/.gitattributes"
! st_mine || conv > "$WORK/cv.crlf" 2>&1
want_out "conventions: a CR the text rule strips on commit is reported" \
	'    c-piscine/c-piscine-c-98/notes.txt' -- cv_saved "$WORK/cv.crlf"
want_broken_none "conventions: ...and one a -text rule covers is not" \
	'c-piscine-c-98/tests/ex20/fixtures/crlf.dict' -- cv_saved "$WORK/cv.crlf"
# A lone CR (one no LF follows) makes git take the whole file for binary
# and commit it as it is, CR LFs and all: nothing is stripped, so nothing
# is reported (V-d). The rule named every file holding a CR.
printf 'a\rb\n' > "$WORK/cv/c-piscine/c-piscine-c-98/lone.txt"
printf 'a\rb\r\n' > "$WORK/cv/c-piscine/c-piscine-c-98/mixed.txt"
! st_mine || conv > "$WORK/cv.lonecr" 2>&1
want_broken_none "conventions: ...nor a lone CR, which git keeps" 'c-piscine-c-98/lone.txt' -- cv_saved "$WORK/cv.lonecr"
want_broken_none "conventions: ...nor a CR LF beside one" 'c-piscine-c-98/mixed.txt' -- cv_saved "$WORK/cv.lonecr"
rm -f "$WORK/cv/c-piscine/c-piscine-c-98/lone.txt" "$WORK/cv/c-piscine/c-piscine-c-98/mixed.txt" \
	"$WORK/cv.crlf" "$WORK/cv.lonecr"
rm -f "$WORK/cv/c-piscine/c-piscine-c-98/notes.txt"
want_broken_none "conventions: ...nor, then, anything" 'a file holds a CR byte' -- conv
# A clue, a script or a BUILD file is text the harness reads, never a case's
# bytes: a CR in one is refused even under a -text rule. The rule once
# covered all of tests/, and a CR typed into a clue was committed as it was.
_cr98=$WORK/cv/c-piscine/c-piscine-c-98/tests/ex20
cp "$_cr98/clues.tsv" "$WORK/cv/clues98.orig" 2> /dev/null || : > "$WORK/cv/clues98.orig"
printf 'Which byte ends this line?\r\n' > "$_cr98/clues.tsv"
printf '* text=auto eol=lf\n**/tests/ex[0-9][0-9]/** -text\n' > "$WORK/cv/.gitattributes"
! st_mine || conv > "$WORK/cv.cluecr" 2>&1
want_out "conventions: a CR in a clue is reported under a -text rule" \
	'c-piscine/c-piscine-c-98/tests/ex20/clues.tsv (a harness text file' -- cv_saved "$WORK/cv.cluecr"
want_broken_none "conventions: ...and a fixture's beside it is not" \
	'c-piscine-c-98/tests/ex20/fixtures/crlf.dict' -- cv_saved "$WORK/cv.cluecr"
rm -f "$WORK/cv.cluecr"
cp "$WORK/cv/clues98.orig" "$_cr98/clues.tsv"
[ -s "$_cr98/clues.tsv" ] || rm -f "$_cr98/clues.tsv"
rm -f "$WORK/cv/.gitattributes" "$WORK/cv/clues98.orig" "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex20/fixtures/crlf.dict"

# CHANGELOG.md, in the shape the template build's --chain reads: dated lines,
# and at most one next-publish line, first.
printf '# Changelog\n\n- next publish: pull, then run setup\n- someday: this\n' > "$WORK/cv/CHANGELOG.md"
want_out "conventions: an undated CHANGELOG entry is reported" \
	'line 4: not "- YYYY-MM-DD: what to do"' -- \
	conv
printf '# Changelog\n\n- next publish: pull, then run setup\n- 2026-09-25: first\n' > "$WORK/cv/CHANGELOG.md"
want_broken_none "conventions: ...and a dated one is not" \
	"CHANGELOG.md has entries" -- \
	conv
rm -f "$WORK/cv/CHANGELOG.md"

