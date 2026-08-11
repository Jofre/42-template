#!/bin/sh
# Run norminette on the given files (.c and/or .h).
#
# Usage:
#   norminette_test.sh --norminette PATH [-R RULE ...] FILE...
#
#   --norminette PATH   the pinned norminette to run. Required; there is no
#                       PATH fallback, deliberately (see below).
#   -R RULE             extra rules, forwarded verbatim ahead of the file list.
#                       -R CheckForbiddenSourceHeader is always passed and is
#                       not yours to add; c-08 adds -R CheckDefine.
#
# It takes a single leading --norminette rather than the `while [ $# -gt 0 ]`
# loop the other runners use, because everything after it is forwarded to
# norminette untouched.
# The -R CheckForbiddenSourceHeader flag is mandated by several module subjects
# (and used by the Moulinette); it is harmless for the others.
#
# This was a bare passthrough, so everything a student saw was norminette's own
# output: a column of codes — TOO_MANY_FUNCS, WRONG_SCOPE_COMMENT — with nothing
# to say that a "code" is the short name of a written rule, and nothing to
# point at the document those rules are written out in. That document is 42's,
# so the message below points at the intranet rather than at a path inside this
# repo -- true wherever it was cloned from, and true on both branches. (The
# private branch does carry 42's material -- the Norm, the subject PDFs, a
# tarball, two copies of numbers.dict -- but a path into a clone is still the
# wrong thing to print: the template strips all of it, and the intranet is where
# the current document lives either way.) With no pointer at all, the codes get
# guessed at or googled instead of read.
#
# Working out what a code means IS the exercise, so the codes below are
# reproduced verbatim and are deliberately NOT translated here; a lookup table
# in this file would replace the reading with a dictionary. What is added is
# only where to do the reading.
#
# Everything the caller passes is still forwarded unchanged, so extra
# `-R <rule>` tokens ahead of the file list keep working.

# A missing norminette used to leave the shell's 127 as the exit status, which
# Bazel reports exactly like a norm violation: the exercise goes red and the
# student is blamed for a tool that was never installed. 2 is this repo's
# "the harness broke" status and separates the two cases.
# The binary arrives from Bazel, pinned in tools/requirements.txt. It is NOT
# looked up on PATH: norminette's version decides which rules exist, so a host
# copy would make the Norm verdict depend on which machine you sat at -- and the
# verdict is supposed to be the one the Moulinette would give. The devcontainer
# still installs one for running by hand; this layer never uses it.
# `set -u` for the same reason every other runner has it: a renamed or misspelled
# flag must fail rather than leave a variable empty. It was missing here because
# the conventions check that enforces it keys off `while [ $# -gt 0 ]`, and this
# runner's option handling is a single `case` -- so the one live layer runner
# without it was also the one shape the lint could not see. Both are fixed:
# //tools:conventions now checks every runner, not only the flag-parsing ones.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "norminette_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require cat grep mktemp rm

NORM=""
case "${1:-}" in
	# `--norminette` with nothing after it must not become `$2: parameter not
	# set` from `set -u` -- the right exit code wrapped in raw shell. Same guard
	# every other runner spells `need`, in the shape this one's parser takes.
	--norminette)
		[ "$#" -ge 2 ] || {
			echo "norminette_test.sh: --norminette needs a value" >&2
			exit 2
		}
		NORM="$2"
		shift 2
		;;
esac
case "$NORM" in
	""|/*) ;;
	*) NORM="$PWD/$NORM" ;;
esac
[ -n "$NORM" ] && [ -x "$NORM" ] || {
	echo "norminette_test.sh: no pinned norminette supplied (--norminette PATH)" >&2
	exit 2
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# Captured instead of streamed only so the closing lines can land AFTER the
# report; the report itself is then replayed byte for byte. The exit status is
# norminette's own, untouched, so a tool-level failure (an unrecognised flag
# exits 2) keeps the status it came with rather than being flattened into "the
# student failed the Norm" — and the guard below catches the tool-level failures
# that do NOT come with a distinguishing status of their own.
"$NORM" -R CheckForbiddenSourceHeader "$@" > "$WORK/out" 2>&1
RC=$?
cat "$WORK/out"

# norminette prints exactly one "<file>: OK!" or "<file>: Error!" line per file
# it actually read, so an output with neither means it never got as far as
# judging anyone's code. Two ways in, and the bare passthrough mishandled both:
# a path that does not resolve prints "no such file or directory" and exits 1,
# which reads as a student who failed the Norm, and a file it declines as "not
# valid C or C header file" prints that and exits 0, which is this layer going
# green over a file nobody checked — the false green tools/tests/selftest.sh
# exists to hunt. Both are the harness handing norminette the wrong thing (the
# files come from BUILD and are staged by Bazel, so the student cannot cause
# either), and that is what status 2 is for.
if ! grep -qE ': (OK|Error)!' "$WORK/out"; then
	echo "norminette_test.sh: norminette judged no file — see its output above" >&2
	exit 2
fi

if [ "$RC" -eq 0 ]; then
	echo "norminette_test: OK — the Norm is satisfied for every file above"
	echo "                 (checked with -R CheckForbiddenSourceHeader, as the"
	echo "                 Moulinette does)."
	exit 0
fi

# Only when there is actually a code on the screen to look up. A file norminette
# cannot parse at all fails with one line of prose and no rule code ("Nested
# parentheses, braces or brackets are not correctly closed"), and telling that
# student the capitalised names above are codes to look up, when there are none,
# reads as though they missed something. Every real code line carries the
# "(line: N, col: M)" locator; the prose ones do not.
if grep -q '^Error: .*(line:' "$WORK/out"; then
	echo ""
	echo "The capitalised names above are Norm rule codes: one per violation, with"
	echo "the file and the line:column it was found at."
	echo "Each code is the short name of a rule written out in the 42 Norm PDF,"
	echo "which 42 publishes on the intranet — look the code up there."
fi
exit $RC
