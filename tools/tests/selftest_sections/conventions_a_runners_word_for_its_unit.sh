# ------------------------------ conventions: a runner's word for its unit
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A test of a library, of one of its functions, of a project or of a part is
# no exercise, so a runner says what it tests through runner_lib.sh's
# rl_noun, which reads the kind the contract hands it; a runner that writes
# "this exercise" itself says it in a library's log too. cvnw's one runner,
# nw_check.sh, says it in a SKIP line, as "the exercise's own" and in
# capitals, each reported; and, quiet, in a comment and through rl_noun. A
# sentence wrapped over two echo lines says it too: "this" ending one, and
# "exercise" (or "exercise's own", after "the") opening the next, through
# its quote, its redirection and a comment between them.
mkdir -p "$WORK/cvnw/tools" "$WORK/cvnw/c-piscine/c-piscine-c-77"
cv_submit "c-piscine/c-piscine-c-77" > "$WORK/cvnw/tools/submit.sh"
: > "$WORK/cvnw/c-piscine/c-piscine-c-77/BUILD.bazel"
printf '%s\n' '#!/bin/sh' \
	"# this exercise's own case, in a comment" \
	"echo \"nw_check: SKIP — this exercise's own case is not passing yet.\"" \
	"echo \"  the exercise's own output fixture\"" \
	'echo "  AUTHORISED FOR THIS EXERCISE"' \
	"echo \"  this \$(rl_noun)'s own case\"" \
	'echo "nw_check: OK — every call is defined by this"' \
	'echo "          exercise itself or on its list."' \
	'echo "  read the" >&2' \
	'	# a comment between' \
	"printf \"  exercise's own fixture\\n\" >&2" \
	'echo "  every call is defined by this"' \
	'echo "  $(rl_noun) itself or on its list."' \
	'echo "  the"' \
	'echo "  exercise case, of no one"' > "$WORK/cvnw/tools/nw_check.sh"
st_mine && env BUILD_WORKSPACE_DIRECTORY="$WORK/cvnw" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvnw.out" 2>&1
want_out 'conventions: a runner saying "this exercise" itself is reported' \
	'tools/nw_check.sh:3:' -- \
	cvi_rule cvnw 'calls what it tests an exercise'
want_out "conventions: ...and \"the exercise's own\"" \
	'tools/nw_check.sh:4:' -- \
	cvi_rule cvnw 'calls what it tests an exercise'
want_out "conventions: ...in capitals too" \
	'tools/nw_check.sh:5:' -- \
	cvi_rule cvnw 'calls what it tests an exercise'
want_broken_none "conventions: ...never in a comment" \
	'tools/nw_check.sh:2:' -- \
	cvi_rule cvnw 'calls what it tests an exercise'
want_broken_none "conventions: ...nor through rl_noun" \
	'tools/nw_check.sh:6:' -- \
	cvi_rule cvnw 'calls what it tests an exercise'
want_out "conventions: ...nor wrapped over two lines, each named" \
	'tools/nw_check.sh:8:' -- \
	cvi_rule cvnw 'calls what it tests an exercise'
want_out "conventions: ...from the line that ends in \"this\"" \
	'tools/nw_check.sh:7:' -- \
	cvi_rule cvnw 'calls what it tests an exercise'
want_out "conventions: ...or in \"the\", past a comment and a redirection" \
	'tools/nw_check.sh:11:' -- \
	cvi_rule cvnw 'calls what it tests an exercise'
want_broken_none "conventions: ...but never through rl_noun on the next line" \
	'tools/nw_check.sh:13:' -- \
	cvi_rule cvnw 'calls what it tests an exercise'
want_broken_none "conventions: ...nor where \"the\" is not followed by \"exercise's own\"" \
	'tools/nw_check.sh:15:' -- \
	cvi_rule cvnw 'calls what it tests an exercise'
rm -rf "$WORK/cvnw" "$WORK/cvnw.out"

