# ----------------------------------- conventions: an awk element tested by itself
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# mawk creates NAME[KEY] on the left of an assignment before it reads the
# right, so NAME[KEY] = ((KEY in NAME) ? ...) always takes the true branch:
# first_red.sh's lists of what did not build began ", " in every module. The
# rule reads every script for such an assignment. cvaw holds one of each:
# a single key and several keys (aw_bad.sh, its two lines of awk), and one
# whose test follows a ';' inside a string, still the same statement; and,
# quiet, the prefix computed first, another array tested, a longer name
# that begins with the array's, a comment, and the key tested by a later
# statement on the same line, after a ';' or a '}' (aw_late.sh, which the
# rule once reported: it read the whole rest of the line). Each line is
# printed through %s, so this file never holds the shape it looks for.
mkdir -p "$WORK/cvaw/tools" "$WORK/cvaw/c-piscine/c-piscine-c-77"
cv_submit "c-piscine/c-piscine-c-77" > "$WORK/cvaw/tools/submit.sh"
: > "$WORK/cvaw/c-piscine/c-piscine-c-77/BUILD.bazel"
{
	printf '#!/bin/sh\n'
	printf "awk '{ %s[\$1] = ((\$1 in %s) ? %s[\$1] \", \" : \"\") \$2\n" a a a
	printf '\t%s[\$1, \$2] = ((\$1, \$2) in %s) + 1\n' seen seen
	printf '\t%s[\$1] = "x;y" ((\$1 in %s) ? 1 : 0) }'"'"'\n' c c
} > "$WORK/cvaw/tools/aw_bad.sh"
{
	printf '#!/bin/sh\n'
	printf "awk '{ %s[\$1] = 1; if (\$1 in %s) n++\n" a a
	printf '\tcnt[\$1]++ ; %s[\$1] = \$2; y = (\$1 in %s)\n' x x
	printf '\tif (\$2) { %s[\$1] = \$2 } z = \$1 in %s }'"'"'\n' w w
} > "$WORK/cvaw/tools/aw_late.sh"
{
	printf '#!/bin/sh\n'
	printf "awk '{ p = (\$1 in %s) ? %s[\$1] \", \" : \"\"; %s[\$1] = p \$2\n" a a a
	printf '\tb[\$1] = (\$1 in %s); %s[\$1] = (\$1 in %s) }'"'"'\n' a a ab
	printf '# %s[k] = ((k in %s) ? 1 : 0)\n' a a
} > "$WORK/cvaw/tools/aw_ok.sh"
printf '{ %s[$1] = (($1 in %s) ? 1 : 0) }\n' a a > "$WORK/cvaw/tools/aw_bad.awk"
st_mine && env BUILD_WORKSPACE_DIRECTORY="$WORK/cvaw" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvaw.out" 2>&1
want_out "conventions: an awk element assigned from a test of itself" \
	'tools/aw_bad.sh:2:' -- cvi_rule cvaw 'assigned from a test of itself'
want_out "conventions: ...and one of several keys" \
	'tools/aw_bad.sh:3:' -- cvi_rule cvaw 'assigned from a test of itself'
want_out "conventions: ...and one whose test follows a ';' in a string" \
	'tools/aw_bad.sh:4:' -- cvi_rule cvaw 'assigned from a test of itself'
want_broken_none "conventions: ...never one tested in a statement before it" \
	'aw_ok.sh' -- cvi_rule cvaw 'assigned from a test of itself'
want_broken_none "conventions: ...nor one tested in a statement after it" \
	'aw_late.sh' -- cvi_rule cvaw 'assigned from a test of itself'
want_out "conventions: ...and one in an awk program" \
	'tools/aw_bad.awk:1:' -- cvi_rule cvaw 'assigned from a test of itself'

