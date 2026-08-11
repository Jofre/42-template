#!/bin/sh
# ex07 — b must equal the result of applying sw.diff to a. Both a and sw.diff
# live in the resources.tar.gz fixture, staged into the scratch dir. The patched
# text IS the answer, so the content check is a plain pass/fail (never printed).
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

B=${1:-b}
printf '  CHECK: %s\n' "$B"

# Look for the fixture next to the deliverable first, then in the cwd.
BDIR=$(dirname -- "$B")
RES="$BDIR/resources.tar.gz"
[ -f "$RES" ] || RES="resources.tar.gz"

# The fixture is 42's, and this repo does not redistribute 42's material -- so
# on a fresh clone of the template it is simply not here, and there is nothing
# to check b against. Unlike rush-02's dictionary, which the harness could
# author a replacement for (it is an ARGUMENT to a generic program), this one
# DEFINES the answer: the subject prints the contents of a, and b is those bytes
# with sw.diff applied. A substitute fixture would have the student verify a
# different b from the one they must turn in, which is worse than checking
# nothing.
#
# So: say so, and skip. Not a pass -- see ck_skip in tools/shell_check.sh.
#
# No backticks in that message. It is a double-quoted shell string, so a
# backtick opens a command substitution: the first draft printed
# "check.sh: 1: b: not found" above the explanation, having run the deliverable.
if [ ! -f "$RES" ]; then
	ck_skip "resources.tar.gz is not here.
        It is 42's own file, issued with the subject, and this repo does not
        redistribute 42's material -- so there is nothing for b to be checked
        against. Download it from the intranet into this exercise's directory,
        then run this again. Everything else about ex07 is unaffected."
fi

# Build the reference result in an isolated temp dir so we never clobber files
# next to the deliverable -- and -o is what keeps it there. Without it `patch`
# writes into the file the diff names, which is `b`: the check would then patch
# the STUDENT'S deliverable in place and compare it against itself.
WANT=""
WORK=$(mktemp -d)
if tar -xf "$RES" -C "$WORK" a sw.diff 2>/dev/null \
	&& patch -s -o "$WORK/want" "$WORK/a" "$WORK/sw.diff" 2>/dev/null; then
	WANT="$WORK/want"
fi

ck "produces a file named b"                test -f "$B"
ck "fixture yields a and sw.diff to patch"  test -n "$WANT"
ck "b equals the patched result of a"       sh -c '[ -n "$1" ] && cmp -s "$1" "$2"' _ "$WANT" "$B"

rm -rf "$WORK"
ck_report
