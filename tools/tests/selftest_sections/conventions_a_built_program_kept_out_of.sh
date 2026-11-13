# --------------------------- conventions: a built program, kept out of commits
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A program a project builds that no .gitignore names: C 10's four, C 11's
# do-op and Rush 01's rush01 were in none, so a hand-run of make or cc in the
# turn-in left a binary the next `git add -A` committed. A workspace of its
# own (cvgi), one module whose calls are each one way of naming a program: a
# c_make's artifact nothing ignores; a c_program beside a c_make of the same
# exercise (the artifact is what is built); one laid out over lines, with a
# case and a call inside it whose "name" is no program's; one an extension
# rule keeps (*.a); one the project's own .gitignore keeps, and one it takes
# back with a "!" line after the root's names it; a unit's turn-in at the
# folder's root, in a module of its own; a num that is no string; and one
# only a .gitignore in the course's folder keeps, which `bazel test` never
# sees (no conventions_srcs declares one there), so it keeps nothing, and is
# said, as one in the project's tests/ is. And a toy under tools/, which is
# the harness's own.
mkdir -p "$WORK/cvgi/tools/tests/macro_fixtures" "$WORK/cvgi/c-piscine/c-piscine-c-93" "$WORK/cvgi/c-piscine/c-piscine-c-95"
cv_submit "c-piscine/c-piscine-c-93 c-piscine/c-piscine-c-95" > "$WORK/cvgi/tools/submit.sh"
{
	printf 'subject(\n    exercises = {\n'
	for _n in 00 01 02 03 04; do
		printf '        "%s": exercise(dir = "ex%s/", files = ["a.c"]),\n' "$_n" "$_n"
	done
	printf '    },\n)\n\n'
	printf 'c_make(num = "00", artifact = "toy-made")\n\n'
	printf 'c_program(num = "00", name = "toy_made")\n\n'
	printf 'c_program(\n    num = "01",\n    name = "toy_bare",\n'
	printf '    model = toy_model(name = "toy_nested"),\n'
	printf '    cases = [{"name": "toy_case", "args": ["x"]}],\n)\n\n'
	printf 'c_make(num = "02", artifact = "libtoy.a")\n\n'
	printf 'c_program(num = "03", name = "toy_kept")\n\n'
	printf 'c_program(num = "04", name = "toy_again")\n\n'
	printf 'c_program(num = NUM, name = "toy_loop")\n\n'
	printf 'c_program(num = "03", name = "toy_course")\n'
} > "$WORK/cvgi/c-piscine/c-piscine-c-93/BUILD.bazel"
printf 'c-piscine-c-93/deliverable/ex03/toy_course\n' > "$WORK/cvgi/c-piscine/.gitignore"
mkdir -p "$WORK/cvgi/c-piscine/c-piscine-c-93/tests"
printf '*.log\n' > "$WORK/cvgi/c-piscine/c-piscine-c-93/tests/.gitignore"
printf '*.a\nc-piscine/c-piscine-c-93/deliverable/ex04/toy_again\nc-piscine/c-piscine-c-95/deliverable/toy_root\n' \
	> "$WORK/cvgi/.gitignore"
# The project's own is a symbolic link, as every file of a runfiles tree is
# under `bazel test`: a find for -type f alone sees none there.
mkdir -p "$WORK/cvgi_src"
printf '/deliverable/ex03/toy_kept\n!toy_again\n' > "$WORK/cvgi_src/gitignore"
ln -s "$WORK/cvgi_src/gitignore" "$WORK/cvgi/c-piscine/c-piscine-c-93/.gitignore"
printf 'subject(\n    exercises = {\n        "00": exercise(dir = "ex00/", files = ["a.c"]),\n    },\n)\n\nc_program(num = "00", name = "toy_fixture")\n' \
	> "$WORK/cvgi/tools/tests/macro_fixtures/BUILD.bazel"
printf 'subject(\n    units = {\n        "toyroot": unit(files = ["a.c"]),\n    },\n)\n\nc_make(unit = "toyroot", artifact = "toy_root")\n' \
	> "$WORK/cvgi/c-piscine/c-piscine-c-95/BUILD.bazel"
_cvg_out=""
_cvg_rc=0
if st_mine; then
	_cvg_out=$(env BUILD_WORKSPACE_DIRECTORY="$WORK/cvgi" "$SH" "$TOOLS/conventions.sh" 2>&1)
	_cvg_rc=$?
fi
cvg_seen() { printf '%s\n' "$_cvg_out"; return "$_cvg_rc"; }
want_out "conventions: a c_make's program no .gitignore names" \
	'c-piscine/c-piscine-c-93/deliverable/ex00/toy-made (c-piscine/c-piscine-c-93/BUILD.bazel:' -- cvg_seen
want_broken_none "conventions: ...not a c_program's name beside a c_make" \
	'deliverable/ex00/toy_made' -- cvg_seen
want_out "conventions: ...a c_program's, laid out over lines" \
	'c-piscine/c-piscine-c-93/deliverable/ex01/toy_bare (' -- cvg_seen
want_broken_none "conventions: ...not a name in one of its cases" 'toy_case' -- cvg_seen
want_broken_none "conventions: ...nor one a call inside it takes" 'toy_nested' -- cvg_seen
want_broken_none "conventions: ...not one a rule with no slash keeps" 'libtoy.a' -- cvg_seen
want_broken_none "conventions: ...nor one the project's .gitignore keeps" 'toy_kept' -- cvg_seen
want_out "conventions: ...but one it takes back with a ! line" \
	'c-piscine/c-piscine-c-93/deliverable/ex04/toy_again (' -- cvg_seen
want_broken_none "conventions: ...a turn-in at the folder's root, kept" 'toy_root' -- cvg_seen
# The line is the one the toy's call opens on, read from it: a toy call added
# above it moves it.
_cvg_loop=$(grep -n '^c_program(num = NUM' "$WORK/cvgi/c-piscine/c-piscine-c-93/BUILD.bazel" | cut -d: -f1)
want_out "conventions: ...a call it cannot read is said" \
	"c-piscine/c-piscine-c-93/BUILD.bazel:$_cvg_loop: a c_program call whose num, unit or program name is not one string" -- cvg_seen
want_broken_none "conventions: ...and a toy under tools/ is the harness's" 'toy_fixture' -- cvg_seen
want_out "conventions: ...a course folder's .gitignore keeps nothing" \
	'c-piscine/c-piscine-c-93/deliverable/ex03/toy_course (' -- cvg_seen
want_out "conventions: ...and is said" \
	'            c-piscine/.gitignore' -- cvg_seen
want_out "conventions: ...as one in a project's tests/ is" \
	'            c-piscine/c-piscine-c-93/tests/.gitignore' -- cvg_seen
