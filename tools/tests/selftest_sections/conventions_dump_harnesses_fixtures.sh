# ------------------------ conventions: dump harnesses, fixtures, module tests
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A dump's harness publishes the address it passes (finding 048): without an
# "@addr" line, diff_output.sh --sanitize compares the column's shape and
# never its value. Both fixture modules have c_function(sanitize = True) on
# ex07's t.c, c-98's writing the marker in code, c-99's only in a comment.
mkdir -p "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex07" "$WORK/cv/c-piscine/c-piscine-c-99/tests/ex07"
printf '#include <stdio.h>\n/* conventions: above 4 GiB -- a toy, which dumps nothing */\nint\tmain(void)\n{\n\tprintf("@addr %%016llx\\n", 0ULL);\n}\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex07/t.c"
# And where the block lives (finding 048): below 4 GiB, as a reader's heap is,
# an address cut to 32 bits is the real one. A reader that turns a pointer
# into a number calls dio_high (tools/diffio.h); a program that publishes an
# address calls it, or says where its blocks are -- c-98's t.c above does.
mkdir -p "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex26" "$WORK/cv/c-piscine/c-piscine-c-99/tests/ex81" \
	"$WORK/cv/c-piscine/c-piscine-c-99/tests/ex82"
printf '#include "diffio.h"\nint\tmain(void)\n{\n\tunsigned char\t*b;\n\n\tb = dio_high(malloc(4), 4);\n\treturn ((uintptr_t)b == 0);\n}\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex26/diff_high.c"
printf '#include "diffio.h"\n/* dio_high( in a comment is no call */\nint\tmain(void)\n{\n\tunsigned char\t*b;\n\n\tb = malloc(4);\n\treturn ((uintptr_t)b == 0);\n}\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-99/tests/ex81/diff_low.c"
printf '#include <stdio.h>\nint\tmain(void)\n{\n\tprintf("@addr %%016llx\\n", 0ULL);\n}\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-99/tests/ex82/t_pub.c"
printf '#include <stdio.h>\n/* no @addr line here */\nint\tmain(void)\n{\n\treturn (0);\n}\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-99/tests/ex07/t.c"
# The harness is found wherever Starlark would find it, and a call whose
# harness cannot be found is reported, never passed over: the rule read only
# a `test = "..."` keyword in a call at column 0 and skipped a harness that
# was not there, so a positional harness, a call in a list comprehension and
# a misnamed harness all went unchecked (each quiet before). So is a call
# that may say sanitize = True where the rule cannot read it: through a **
# splat (read as False, and skipped), or by a position past test (read by a
# copy of c_function's signature); a splat beside a sanitize keyword says
# nothing more. The positions are held to c_function's def: the toy
# tools/defs_function.bzl planted here puts srcs before test, and the one
# the defs.bzl group below reads keeps the order.
mkdir -p "$WORK/cv/c-piscine/c-piscine-c-99/tests/ex80"
printf 'int\tmain(void)\n{\n\treturn (0);\n}\n' > "$WORK/cv/c-piscine/c-piscine-c-99/tests/ex80/t8.c"
cp "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel" "$WORK/cv.addr.keep"
{
	printf '\nc_function("80", "ft_y", "t8.c", sanitize = True)\n\n'
	printf '[\n    c_function(num = n, fn = "ft_z", test = "t.c", sanitize = True)\n'
	printf '    for n in ["09"]\n]\n\n'
	printf 'c_function(num = "10", fn = "ft_v", test = "missing.c", sanitize = True)\n'
	printf 'c_function(num = "11", fn = "ft_s", test = "t8.c", **{"sanitize": True})\n'
	printf 'c_function("12", "ft_p", "t8.c", None, None, "e.txt", True)\n'
	printf 'c_function(num = "13", fn = "ft_q", test = "t8.c", sanitize = False, *pos)\n'
} >> "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
printf 'def c_function(\n        num = None,\n        srcs = None,\n        fn = None,\n        test = None):\n    pass\n' \
	> "$WORK/cv/tools/defs_function.bzl"
! st_mine || conv > "$WORK/cv.addr" 2>&1
mv "$WORK/cv.addr.keep" "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
rm -f "$WORK/cv/tools/defs_function.bzl"
want_out "conventions: a sanitize harness that publishes no @addr is reported" \
	"c-piscine/c-piscine-c-99/tests/ex07/t.c publishes no @addr line" -- cv_saved "$WORK/cv.addr"
want_broken_none "conventions: ...and one that publishes it is not" \
	"c-piscine/c-piscine-c-98/tests/ex07/t.c publishes" -- cv_saved "$WORK/cv.addr"
want_out "conventions: ...a harness passed by position is read" \
	"c-piscine/c-piscine-c-99/tests/ex80/t8.c publishes no @addr line" -- cv_saved "$WORK/cv.addr"
want_out "conventions: ...a call in a comprehension is reported, not passed over" \
	"its num is not a literal" -- cv_saved "$WORK/cv.addr"
want_out "conventions: ...and so is a harness that is not there" \
	"c-piscine/c-piscine-c-99/tests/ex10/missing.c, a sanitize harness its c_function names, does not exist" -- \
	cv_saved "$WORK/cv.addr"
want_out "conventions: ...and so is a call whose sanitize may sit in a ** splat" \
	'Why: its arguments include a ** splat, which may carry sanitize.' -- cv_saved "$WORK/cv.addr"
want_out "conventions: ...or in a position past test" \
	'Why: it passes an argument by position past test, which this check does not read.' -- \
	cv_saved "$WORK/cv.addr"
want_broken_none "conventions: ...never a splat beside a sanitize keyword" \
	'include a * splat' -- cv_saved "$WORK/cv.addr"
want_out "conventions: a c_function def that moves its first parameters is reported" \
	'They are: num srcs fn.' -- cv_saved "$WORK/cv.addr"
want_out "conventions: a reader checking an address below 4 GiB is reported" \
	"c-piscine/c-piscine-c-99/tests/ex81/diff_low.c turns a pointer into a number, and puts no block above 4 GiB" -- \
	cv_saved "$WORK/cv.addr"
want_broken_none "conventions: ...and one that calls dio_high is not" \
	"c-piscine/c-piscine-c-98/tests/ex26/diff_high.c turns a pointer" -- cv_saved "$WORK/cv.addr"
want_out "conventions: a program publishing an address says where its blocks are" \
	"c-piscine/c-piscine-c-99/tests/ex82/t_pub.c publishes an address, and does not say its blocks are above 4 GiB" -- \
	cv_saved "$WORK/cv.addr"
want_broken_none "conventions: ...and one that says so is not" \
	"c-piscine/c-piscine-c-98/tests/ex07/t.c publishes an address" -- cv_saved "$WORK/cv.addr"
rm -rf "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex07" "$WORK/cv/c-piscine/c-piscine-c-99/tests/ex07" \
	"$WORK/cv/c-piscine/c-piscine-c-99/tests/ex80" "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex26" \
	"$WORK/cv/c-piscine/c-piscine-c-99/tests/ex81" "$WORK/cv/c-piscine/c-piscine-c-99/tests/ex82" \
	"$WORK/cv.addr"

# Output fixtures and --harness-fixture. The check is an awk parse of
# defs.bzl, the kind of thing that can quietly stop matching and go on saying
# OK, so each shape it tells apart gets an arm: a fixture built with a plain
# cc_binary, --harness-fixture on a binary the macro did not build with
# _output_fixture_binary, and the correct pairing it must accept. The
# _LAYER_LEVEL fake above is put back after.
cp "$WORK/cv/tools/defs.bzl" "$WORK/cv_defs.bak"
{
	printf '_LAYER_LEVEL = {\n    "norm": 1,\n    "widget": 3,\n}\n\n'
	printf 'def plain(ex):\n    test_f = "tests/%%s/test_x.c" %% ex\n'
	printf '    cc_binary(\n        name = "b",\n        srcs = [test_f],\n    )\n\n'
	printf 'def unbuffered(ex):\n    test_f = "tests/%%s/test_x.c" %% ex\n'
	printf '    _student_bin(\n        name = "c_bin",\n        harness = [test_f],\n        deps = [":f"],\n    )\n\n'
	printf 'def wrongflag(ex):\n    diffbin = ex + "_diffbin"\n'
	printf '    _test(\n        args = [\n            "--bin",\n'
	printf '            "$(location :%%s)" %% diffbin,\n            "--harness-fixture",\n'
	printf '        ],\n    )\n\n'
	printf 'def rightflag(ex):\n    test_f = "tests/%%s/test_x.c" %% ex\n    binname = ex + "_bin"\n'
	printf '    _output_fixture_binary(\n        name = binname,\n        harness = [test_f],\n        deps = [":f"],\n    )\n'
	printf '    _test(\n        args = [\n            "--bin",\n'
	printf '            "$(location :%%s)" %% binname,\n            "--harness-fixture",\n'
	printf '        ],\n    )\n'
} > "$WORK/cv/tools/defs.bzl"
printf 'def c_function(\n        num = None,\n        fn = None,\n        test = None,\n        srcs = None):\n    pass\n' \
	> "$WORK/cv/tools/defs_function.bzl"
# The arms ask about one tree, so they read one run of it.
! st_mine || conv > "$WORK/cv.harmain" 2>&1
want_out "conventions: a cc_binary built from a harness main is reported" \
	'a cc_binary built from a harness main' -- \
	cv_saved "$WORK/cv.harmain"
want_out "conventions: a _student_bin built around a harness main is reported" \
	'a _student_bin built from a harness main, not through _output_fixture_binary' -- \
	cv_saved "$WORK/cv.harmain"
want_broken_none "conventions: ...and an _output_fixture_binary around one is not" \
	'_output_fixture_binary around something' -- \
	cv_saved "$WORK/cv.harmain"
want_out "conventions: --harness-fixture on another binary is reported" \
	'--harness-fixture on diffbin' -- \
	cv_saved "$WORK/cv.harmain"
want_broken_none "conventions: ...and on an _output_fixture_binary it is not" \
	'--harness-fixture on binname' -- \
	cv_saved "$WORK/cv.harmain"
want_broken_none "conventions: ...and a c_function def opening with num, fn, test is not" \
	"c_function's first parameters" -- cv_saved "$WORK/cv.harmain"
rm -f "$WORK/cv.harmain" "$WORK/cv/tools/defs_function.bzl"
cp "$WORK/cv_defs.bak" "$WORK/cv/tools/defs.bzl"
# The tests of a whole module (deliverable_files) are named alike in the
# audit's _MODULE_TESTS, in first_red.sh's MODULE_TESTS and in the docs: one
# first_red does not know is filed as an exercise named '-'.
#
# In the same two runs: the files layers' excludes and //tools:submit's are
# one list of extensions, and a .git directory is left out of the globs --
# submit keeps its scratch repository at deliverable/.git, which git never
# pushes, and the files layers once reported it after every first submit.
# cv_mt: the saved run, with its status (cv_saved), so a run that broke
# fails the arms that look for an absence.
cv_mt() { cv_saved "$WORK/cv.modtests"; }
{
	cat "$WORK/cv_defs.bak"
	printf '\n_MODULE_TESTS = {\n    "deliverable_files": "files",\n}\n'
	printf '\n_BUILD_PRODUCTS = ["*.o", "*.a"]\n'
	printf '\ndef _not_build_products(d):\n    return [d + "/**/" + p for p in _BUILD_PRODUCTS]\n'
	printf '\ndef stray(where):\n    return native.glob([where + "/**"], allow_empty = True)\n'
} > "$WORK/cv/tools/defs.bzl"
_cv_glob=$(grep -n 'native.glob(\[where' "$WORK/cv/tools/defs.bzl" | cut -d: -f1)
{
	# shellcheck disable=SC2154 # set in conventions.sh
	cv_submit "$_cv_mods"
	printf "git add -A -- . ':(exclude)*.o' ':(exclude)*.a' ':(exclude)*.gch'\n"
} > "$WORK/cv/tools/submit.sh"
printf "#!/bin/sh\nMODULE_TESTS='other_files'\n" > "$WORK/cv/tools/first_red.sh"
# The docs name deliverable_files in "Reserved unit names" alone, the table
# of names no unit may take, which every module test is in: that is not where
# a reader looks a red test up, so the docs still never name it. (cv has no
# docs/ here: these two runs write their own, and remove it after.)
mkdir -p "$WORK/cv/docs"
printf '# Reference\n\n## Reserved unit names\n\n| Name | Why |\n|---|---|\n| `deliverable_files` | a target a module declares |\n' \
	> "$WORK/cv/docs/reference.md"
! st_mine || conv > "$WORK/cv.modtests" 2>&1
want_out "conventions: first_red's module tests disagreeing with the audit's" \
	"first_red.sh's MODULE_TESTS disagrees" -- cv_mt
want_out "conventions: ...and one the docs name only as a reserved unit name" \
	'docs/reference.md never names deliverable_files' -- cv_mt
want_out "conventions: the files layers leaving out other files than submit" \
	"leave out other files than //tools:submit" -- cv_mt
want_out "conventions: ...naming the extension only one of them has" \
	"':(exclude)': *.a *.gch *.o" -- cv_mt
want_out "conventions: a glob of the turn-in taking in .git" \
	'take in a .git directory' -- cv_mt
# ...and a glob of a whole tree that does not use the list at all.
want_out "conventions: a glob of a whole tree without _not_build_products" \
	"tools/defs.bzl:$_cv_glob" -- cv_mt
printf "#!/bin/sh\nMODULE_TESTS='deliverable_files'\n" > "$WORK/cv/tools/first_red.sh"
{
	cat "$WORK/cv_defs.bak"
	printf '\n_MODULE_TESTS = {\n    "deliverable_files": "files",\n}\n'
	printf '\n_BUILD_PRODUCTS = ["*.o", "*.a", "*.gch"]\n'
	printf '\ndef _not_build_products(d):\n    return [d + "/**/" + p for p in _BUILD_PRODUCTS] + [d + "/**/.git/**"]\n'
	# The exclude on a line of its own, past a comment with a parenthesis in
	# it; a glob of the harness's own tests/; a docstring naming a glob.
	printf '\ndef stray(where):\n    """Not native.glob([where + "/**"]) alone."""\n'
	printf '    return native.glob(\n        [where + "/**"],\n'
	printf '        # what submit leaves out (and .git)\n'
	printf '        exclude = _not_build_products(where),\n        allow_empty = True,\n    )\n'
	printf '\ndef own(ex):\n    return native.glob(["tests/%%s/**" %% ex], allow_empty = True)\n'
} > "$WORK/cv/tools/defs.bzl"
# ...and named where a reader looks, it is not reported.
printf '\n## Suites\n\n`deliverable_files` is a test of the whole module.\n' >> "$WORK/cv/docs/reference.md"
! st_mine || conv > "$WORK/cv.modtests" 2>&1
rm -rf "$WORK/cv/docs"
want_broken_none "conventions: ...agreeing, they are not reported" \
	"MODULE_TESTS disagrees" -- cv_mt
want_broken_none "conventions: ...nor a module test the docs name outside that table" \
	'docs/reference.md never names deliverable_files' -- cv_mt
want_broken_none "conventions: ...one list of extensions is not" \
	"leave out other files than" -- cv_mt
want_broken_none "conventions: ...nor a glob that leaves .git out" \
	'take in a .git directory' -- cv_mt
want_broken_none "conventions: ...nor a glob of a whole tree through the list" \
	'a glob of a whole turn-in tree' -- cv_mt
rm -f "$WORK/cv/tools/first_red.sh" "$WORK/cv.modtests"
cp "$WORK/cv_defs.bak" "$WORK/cv/tools/defs.bzl"
cv_submit "$_cv_mods" > "$WORK/cv/tools/submit.sh"
