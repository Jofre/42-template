# ---------------------------------- conventions: the registry of issued files
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The registry of 42's own files (tools/resources.tsv). Its texts disagreed
# about where each file goes -- "its folder", "wherever you like" -- while the
# harness read exactly one path (findings 016, 161). A made-up project file,
# data.bin, registered with one doc that must name its path: a doc that sends
# the student to "its folder" instead is reported twice over, once for the
# vague place and once for the missing path; the same doc naming the path is
# not. A BUILD glob of one literal name stages a file the checkout may not
# have, which is 42's material's shape, so an unregistered one is reported.
mkdir -p "$WORK/cv/docs"
printf 'c-piscine/c-piscine-c-98\tdata.bin\tc-piscine/c-piscine-c-98/data.bin\tharness\t*data.bin\t-\tdocs/where.md\tthe intranet\n' \
	> "$WORK/cv/tools/resources.tsv"
printf 'fixtures = glob(["data.bin"], allow_empty = True)\n' >> "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
printf 'fixtures = glob(["other.bin"], allow_empty = True)\n' >> "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
printf 'Save data.bin in its folder.\n' > "$WORK/cv/docs/where.md"
! st_mine || conv > "$WORK/cv.where" 2>&1
want_out "conventions: a doc without a registered file's path is reported" \
	"docs/where.md mentions data.bin without its one path" -- \
	cv_saved "$WORK/cv.where"
want_out "conventions: ...and one sending it to 'its folder' too" \
	"a text sends a student to a vague place for 42's data.bin" -- \
	cv_saved "$WORK/cv.where"
want_out "conventions: an unregistered one-file glob is reported" \
	"globs the single file other.bin" -- \
	cv_saved "$WORK/cv.where"
want_broken_none "conventions: ...and a registered one is not" \
	"globs the single file data.bin" -- \
	cv_saved "$WORK/cv.where"
want_out "conventions: a checkout with no tools/subjects.tsv is reported" \
	"tools/subjects.tsv is missing" -- \
	cv_saved "$WORK/cv.where"
rm -f "$WORK/cv.where"
printf 'Save data.bin as c-piscine/c-piscine-c-98/data.bin.\n' > "$WORK/cv/docs/where.md"
want_broken_none "conventions: a doc naming the path is accepted" \
	"docs/where.md mentions data.bin" -- \
	conv

# HOW A BUILD FILE NAMES IT, read as Starlark. The file is not in the template,
# so a label naming it takes the whole package down there, and only there. The
# rule was "BUILD names the file", grepped -- a comment met it -- and the
# one-file-glob detector matched a glob only when it was written on one line,
# which is not how buildifier lays one out. Each fixture is c-98's BUILD file
# with one ending; the original goes back after. The base text has a name of
# its own: _cv98, in first_red_hints and after, is c-98's tests/ folder, and
# cv98 (called from the consumers section too) printing that would write a
# BUILD file holding one path, over which an absence arm passes having
# checked nothing.
cp "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel" "$WORK/cv/b98.orig"
cp "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel" "$WORK/cv/b99.orig"
_cv98_build=$(grep -v 'data.bin' "$WORK/cv/b98.orig")
cv98() { { printf '%s\n' "$_cv98_build"; printf "$@"; } > "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"; }
cv98 '# data.bin is named here, in a comment only\n'
want_out "conventions: a registered file named only in a comment is reported" \
	"BUILD files never name data.bin outside a comment" -- \
	conv
cv98 'x(\n    num = "08",\n    fixtures = ["data.bin"],\n)\n'
want_out "conventions: ...one named as a label is reported" \
	"as a label (in fixtures)" -- \
	conv
cv98 'x(\n    fixtures = glob(\n        ["data.bin"],\n    ),\n)\n'
want_out "conventions: ...one in a glob that may not be empty too" \
	"in a glob without allow_empty = True" -- \
	conv
cv98 'subject(\n    exercises = {\n        "08": exercise(\n            files = ["data.bin"],\n            optional = ["data.bin"],\n        ),\n    },\n)\nx(\n    fixtures = glob(\n        ["data.bin"],\n        allow_empty = True,\n    ),\n)\n'
want_broken_none "conventions: ...but not a name list, nor a glob allowed empty" \
	"breaks the template" -- \
	conv
# A name list is a keyword OF ONE CALL: `file` is c_issued's name, and the
# same keyword of any other call may take a label. The exemption was the
# keyword alone, so this passed.
cv98 'x(\n    num = "08",\n    file = "data.bin",\n)\n'
want_out "conventions: ...but another call's file = is a label" \
	"as a label (in file)" -- \
	conv
# A cwd_files value is what a staged file is CALLED in the run folder (Rush
# 02 stages its own dictionary as 42's numbers.dict): a name, never a label.
# Its key is the label of what is staged, and naming 42's file there is one.
cv98 'x(\n    num = "08",\n    cases = [{\n        "name": "a",\n        "cwd_files": {"tests/ex08/own.bin": "data.bin"},\n        "args": ["1"],\n    }],\n)\n'
want_broken_none "conventions: ...nor the name a cwd_files case stages a file under" \
	"breaks the template" -- \
	conv
cv98 'x(\n    num = "08",\n    cases = [{\n        "name": "a",\n        "cwd_files": {"data.bin": "own.bin", "b": "c"},\n    }],\n)\n'
# c-99's glob laid out over lines is another file, so one run reads both.
{ grep -v 'other.bin' "$WORK/cv/b99.orig"
	printf 'x(\n    fixtures = glob(\n        ["other.bin"],\n        allow_empty = True,\n    ),\n)\n'; } \
	> "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
! st_mine || conv > "$WORK/cv.staged" 2>&1
want_out "conventions: ...but the file a cwd_files case stages is a label" \
	"as a label (in cases)" -- \
	cv_saved "$WORK/cv.staged"
want_out "conventions: an unregistered one-file glob over lines is reported" \
	"globs the single file other.bin" -- \
	cv_saved "$WORK/cv.staged"
rm -f "$WORK/cv.staged"
cp "$WORK/cv/b98.orig" "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
cp "$WORK/cv/b99.orig" "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"


# The registry of each project's subject (tools/subjects.tsv), which the
# template's SUBJECT-PLACEHOLDER.pdf is written from: one row per module of the
# table and none for anything else (tools/subjects.sh check, whose own arms
# are the placeholder's), and a page of the module that says which version it
# describes says the row's, on one line or across two. c-98 holds a subject
# whose bytes are not its row's, which in a clone of the template is a
# student's own download and no error: so this run reports every other wrong
# and not that one. The fixture had no registry until here, which the first
# run of this section reported.
printf 'subject 98\n' > "$WORK/cv/c-piscine/c-piscine-c-98/en.subject.pdf"
_cvsj_x=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
cvsj_row() {  # PROJECT VERSION SHA256
	printf '%s\t%s\t%s\thttps://projects.intra.42.fr/projects/%s\t-\t2026-11-01\n' "$1" "$2" "$3" "${1##*/}"
}
{
	cvsj_row c-piscine/c-piscine-c-98 2 "$_cvsj_x"
	cvsj_row c-piscine/c-piscine-c-97 2 "$_cvsj_x"
} > "$WORK/cv/tools/subjects.tsv"
printf 'This page describes the harness built from\nversion 3 of that subject.\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-98/README.md"
! st_mine || conv > "$WORK/cv.subj" 2>&1
want_out "conventions: a module with no row in tools/subjects.tsv is reported" \
	"no row for the module c-piscine/c-piscine-c-99" -- \
	cv_saved "$WORK/cv.subj"
want_out "conventions: ...and a row that is no module's" \
	"a row for c-piscine/c-piscine-c-97, which is no module" -- \
	cv_saved "$WORK/cv.subj"
want_out "conventions: ...and a page naming another version, across two lines" \
	"c-piscine/c-piscine-c-98/README.md says it describes version 3 of the subject; tools/subjects.tsv has 2" -- \
	cv_saved "$WORK/cv.subj"
want_broken_none "conventions: ...but not a student's own subject, whatever its bytes" \
	"en.subject.pdf" -- \
	cv_saved "$WORK/cv.subj"
rm -f "$WORK/cv.subj"
{
	cvsj_row c-piscine/c-piscine-c-98 3 "$_cvsj_x"
	cvsj_row c-piscine/c-piscine-c-99 1.0 "$_cvsj_x"
} > "$WORK/cv/tools/subjects.tsv"
want_broken_none "conventions: ...and with each put right, tools/subjects.tsv is not named" \
	"tools/subjects.tsv" -- \
	conv
rm -f "$WORK/cv/c-piscine/c-piscine-c-98/en.subject.pdf" "$WORK/cv/c-piscine/c-piscine-c-98/README.md"
