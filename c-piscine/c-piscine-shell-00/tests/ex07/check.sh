#!/bin/sh
# ex07 — b must equal the result of applying sw.diff to a. Both a and sw.diff
# live in the resources.tar.gz fixture, staged into the scratch dir. The edited
# text IS the answer, so the content check is a plain pass/fail (never printed).
#
# WHERE THE EXPECTED b COMES FROM. It cannot be written down here: it is built
# from 42's own a, and this repo does not redistribute 42's material (see the
# SKIP below). It used to be built by running the very command the exercise
# asks for, which put the answer in a file the public template ships. The
# reference is now //oracle's `shell00_diff_apply`: a reader of the diff
# format, in Rust, that replays sw.diff's recorded edits onto a -- something a
# curious student may read and cannot paste (AGENTS.md §0 and §2). It is
# strict: if sw.diff does not describe an edit of this a, it refuses rather
# than guessing, and the check below says so.
# shellcheck source=../../../../tools/shell_check.sh
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

ORACLE=${ORACLE:?this check needs //oracle: declare the exercise with oracle = True}

# Unpack the two inputs into a private temp dir, never next to the deliverable:
# the student's b sits in the current directory, and nothing here may write
# over it or beside it. The reference result goes into the same temp dir.
WANT=""
WORK=$(mktemp -d)
if tar -xf "$RES" -C "$WORK" a sw.diff 2>/dev/null \
	&& "$ORACLE" shell00_diff_apply "$WORK/a" "$WORK/sw.diff" > "$WORK/want" 2>/dev/null; then
	WANT="$WORK/want"
fi

ck "produces a file named b"                     test -f "$B"
ck "fixture yields an a that sw.diff applies to" test -n "$WANT"
ck "b equals a with sw.diff's edits applied"     sh -c '[ -n "$1" ] && cmp -s "$1" "$2"' _ "$WANT" "$B"

rm -rf "$WORK"
ck_report
