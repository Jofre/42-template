#!/bin/sh
# Run norminette on the given files (.c and/or .h).
#
# Usage:
#   norminette_test.sh --norminette PATH [--notices-only] [-R RULE ...] FILE...
#
#   --norminette PATH   the pinned norminette to run. Required; there is no
#                       PATH fallback, deliberately (see below).
#   --notices-only      judge norminette's Notices instead of its Errors: fail
#                       on a Notice, and leave any Error to the plain target.
#                       This is the strict-level twin _norm_test emits; see
#                       "NOTICES" below for the reading each one holds.
#   -R RULE             forwarded to norminette, AFTER this script's own
#                       -R CheckForbiddenSourceHeader. norminette keeps only
#                       the LAST -R it is given, so a caller's -R replaces that
#                       one rather than adding to it; c-08 passes -R CheckDefine.
#
# Its own options come first and the loop stops at the first argument that is
# not one of them, because everything after that is forwarded to norminette
# untouched.
# The -R CheckForbiddenSourceHeader flag is the one the C 00-07 and C 09
# subjects tell you to run norminette with, so it is what this layer passes
# when the caller names no other. Which -R took effect is printed on every
# run, never assumed.
#
# This was a bare passthrough, so everything a student saw was norminette's own
# output: a column of codes — TOO_MANY_FUNCS, WRONG_SCOPE_COMMENT — with nothing
# to say that a "code" is the short name of a written rule, and nothing to
# point at the document those rules are written out in. That document is 42's,
# so the message below points at the intranet rather than at a path inside this
# repo -- true wherever it was cloned from, and true on both branches. (The
# private branch does carry 42's material -- the Norm, the subject PDFs, a
# tarball, numbers.dict -- but a path into a clone is still the
# wrong thing to print: the template strips all of it, and the intranet is where
# the current document lives either way.) With no pointer at all, the codes get
# guessed at or googled instead of read.
#
# Working out what a code means IS the exercise, so the codes below are
# reproduced verbatim and are deliberately NOT translated here; a lookup table
# in this file would replace the reading with a dictionary. What is added is
# only where to do the reading.
#
# Everything the caller passes is still forwarded unchanged, after this
# script's own -R; norminette keeps only the last -R, so a caller's replaces
# this script's rather than adding to it (see -R above).

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
# flag must fail rather than leave a variable empty. It was missing here while
# this runner's option handling was a single `case`, which the conventions
# check keyed off `while [ $# -gt 0 ]` could not see. It has that loop now, and
# //tools:conventions checks every runner, not only the flag-parsing ones.
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
require cat grep head mktemp rm sed tr

# conventions: runs no student code -- it runs the pinned norminette over the student's sources
# conventions: harness tool NORM -- the pinned norminette

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "norminette_test.sh: $1 needs a value" >&2; exit 2; }; }

NORM=""
NOTICES_ONLY=0
while [ $# -gt 0 ]; do
	case "$1" in
		--norminette) need "$1" "$#"; NORM="$2"; shift 2 ;;
		--notices-only) NOTICES_ONLY=1; shift ;;
		# Anything else is norminette's: -R pairs, then the files.
		*) break ;;
	esac
done
case "$NORM" in
	""|/*) ;;
	*) NORM="$PWD/$NORM" ;;
esac
[ -n "$NORM" ] && [ -x "$NORM" ] || {
	echo "norminette_test.sh: no pinned norminette supplied (--norminette PATH)" >&2
	exit 2
}

# WHAT NORMINETTE IS ABOUT TO BE ASKED, worked out rather than assumed.
#
# The success line used to be fixed text naming -R CheckForbiddenSourceHeader,
# on every target, including the c-08 headers whose caller passes
# -R CheckDefine. norminette declares -R with one value and keeps the LAST one
# it sees, so those headers were judged under CheckDefine alone while the log
# named the other flag -- and a student who ran norminette with the flag the
# log named got Error! on a file the layer had passed. So the effective rule is
# computed here, from the same argument list norminette receives, in the same
# order: this script's own -R first, the caller's after it.
#
# The files are counted too, because norminette can stop before it reaches
# them all (see PARSE STOP below). Only .c and .h are counted, which is all
# norminette itself will read.
RULE=CheckForbiddenSourceHeader
FILES=""
NFILES=0
_rule_next=0
for _a in "$@"; do
	if [ "$_rule_next" -eq 1 ]; then
		RULE="$_a"
		_rule_next=0
		continue
	fi
	case "$_a" in
		-R) _rule_next=1 ;;
		-R*) RULE="${_a#-R}" ;;
		*.c|*.h) FILES="$FILES $_a"; NFILES=$((NFILES + 1)) ;;
	esac
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# THE VERSION, asked of the binary about to run rather than copied from
# tools/pins.tsv. A student comparing this log with a norminette of their own
# needs the version that produced THIS verdict, and a number typed into a
# message is a number that can go stale. Matched anywhere in the output, not
# on line 1: tools/env_drift.sh records a norminette that prints a banner
# before anything else.
VERSION=$("$NORM" -v 2> /dev/null | sed -n 's/^norminette \([0-9][^ ,]*\).*/\1/p' | head -n 1)

# Captured instead of streamed only so the closing lines can land AFTER the
# report; the report itself is then replayed as norminette wrote it, less its
# colour codes. The status is kept for the one thing it still decides -- a
# status nothing in the output explains is a harness fault -- and NOT for the
# verdict: see ANY FILE below.
#
# THE COLOUR CODES GO. The pinned norminette wraps some messages in ANSI
# colour (INVALID_HEADER's text in ESC[97m, for one) and colours the message
# of a file it cannot parse whatever it is told: its --no-colors reaches the
# error table and not that path. Fine in a terminal, but this output is a
# test.log, read in a saved file or an IDE's test view, where each code is
# noise around the words a student needs (TO VERIFY V57). So they are taken
# out here, every path alike, before anything below reads the output; what
# is left is norminette's text, and the tab that opens a parse stop's line
# with it.
"$NORM" -R CheckForbiddenSourceHeader "$@" > "$WORK/raw" 2>&1
RC=$?
ESC=$(printf '\033')
sed "s/${ESC}\[[0-9;]*m//g" "$WORK/raw" > "$WORK/out"
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

# ANY FILE, not the last one. The pinned norminette (tools/requirements.txt)
# sets its exit status from the errors of the LAST file it checked only --
# `sys.exit(1 if len(file.errors) else 0)`, with `file` the loop variable left
# over. True of 3.3.58; a selftest arm asserts it, so a pin that stops doing
# it goes red there rather than leaving this paragraph wrong. So `bad.c ok.c`
# exited 0 after printing "bad.c: Error!", and since every macro lists the
# headers after the sources, the graded .c files of C 12, C 13, the rushes
# and BSQ were in effect never normed: a green target printed "the Norm is
# satisfied" directly under an Error! line. The verdict is now read from each
# file's own verdict line, which is where norminette itself states it, and
# holds whichever way a later version sets its status.
ERRFILES=$(sed -n 's/: Error!$//p' "$WORK/out" | tr '\n' ' ' | sed 's/ $//')
VERDICTS=$(grep -cE ': (OK|Error)!$' "$WORK/out")
NOTICES=$(grep -c '^Notice: ' "$WORK/out")
TAB=$(printf '\t')

# PARSE STOP. A file norminette cannot parse ends the whole run on the spot:
# it prints that one file's "Error!" and a tab-indented message, and nothing
# for any file before or after it. So fewer verdicts than files is either
# that -- the student's to fix, and said so below -- or the harness handing
# norminette something it skipped, which is status 2 for the reason above.
PARSE_STOP=0
grep -q "^$TAB" "$WORK/out" && PARSE_STOP=1
if [ "$VERDICTS" -lt "$NFILES" ] && [ "$PARSE_STOP" -eq 0 ]; then
	echo "norminette_test.sh: norminette judged $VERDICTS of the $NFILES files it was" >&2
	echo "  given and says nothing about the rest, so this refuses to call the" >&2
	echo "  run either way. The file list comes from BUILD, not from you." >&2
	exit 2
fi
if [ -z "$ERRFILES" ] && [ "$NOTICES" -eq 0 ] && [ "$RC" -ne 0 ]; then
	echo "norminette_test.sh: norminette exited $RC with no Error! and no Notice" >&2
	echo "  in its output, so nothing here explains that status. Refusing to" >&2
	echo "  call it a pass or a Norm failure." >&2
	exit 2
fi

# The facts every verdict below rests on, printed with each of them: which
# norminette, which -R took effect, and the command that asks the same
# question by hand. `bazel run` changes directory before it runs anything,
# hence "$PWD/..." rather than a relative path; it is left for the reader's
# shell to expand, from the root of their own clone.
run_info() {
	echo ""
	echo "  ran:  norminette ${VERSION:-(version unknown: its -v printed none)} (the copy Bazel fetched; tools/pins.tsv)"
	echo "        with -R $RULE -- norminette keeps only the last"
	echo "        -R it is given, so that is the rule that applied."
	echo "  by hand, from the repository root:"
	printf '        bazel run //tools:norminette -- -R %s' "$RULE"
	for _f in $FILES; do
		case "$_f" in
			/*) printf ' %s' "$_f" ;;
			*) printf ' "$PWD/%s"' "$_f" ;;
		esac
	done
	echo ""
}

# NOTICES. norminette prints "OK!" for a file whose only findings are Notices
# (GLOBAL_VAR_DETECTED is the one students meet) and still counts them in its
# exit status. Which of the two a grader goes by is not written in any
# subject, and the old runner passed the status through, so a target went red
# under a log whose only verdict was "OK!" and said nothing more.
#
# A reading the subject does not settle is read at `strict`, never at `basic`
# -- docs/reference.md defines strict as "real, but not certain", a case the
# subject leaves open among them. So the plain norm target passes a
# Notice-only file with the warning below, and _norm_test
# emits a twin, *_norm_notice, raised to strict, which runs this script with
# --notices-only: it fails on a Notice and leaves Errors to the plain target,
# so each of the two is red for one reason only.
if [ "$NOTICES_ONLY" -eq 1 ]; then
	if [ "$NOTICES" -gt 0 ]; then
		echo ""
		echo "norminette_test: FAIL — norminette printed a Notice (above). That a Notice"
		echo "                 fails, as norminette's exit status says it does even for"
		echo "                 a file judged OK!, is this harness's reading, never the"
		echo "                 subject's: no subject says whether 42's grader counts a"
		echo "                 Notice, which is why this target sits at strict while"
		echo "                 the plain norm target only warns. The Notice line says"
		echo "                 what norminette asks you to reconsider."
		run_info
		exit 1
	fi
	if [ "$PARSE_STOP" -eq 1 ]; then
		[ "${NO_SKIP:-0}" != "1" ] || {
			echo "norminette_test: NO_SKIP set: norminette stopped at a file it could"
			echo "                 not parse, so no file was looked at for Notices."
			exit 1
		}
		echo ""
		echo "norminette_test: SKIP — norminette stopped at a file it could not parse,"
		echo "                 so no file was looked at for Notices. The plain norm"
		echo "                 target of this exercise reports that file."
		exit 0
	fi
	echo ""
	echo "norminette_test: OK — no Notice in any file above."
	if [ -n "$ERRFILES" ]; then
		echo "                 (The Error lines are the plain norm target's verdict,"
		echo "                 not this one's.)"
	fi
	run_info
	exit 0
fi

notice_warning() {
	[ "$NOTICES" -gt 0 ] || return 0
	echo ""
	echo "norminette_test: WARNING — norminette printed a Notice (above). A Notice"
	echo "                 alone does not fail this target: norminette judges a"
	echo "                 file whose only findings are Notices OK!. Its exit"
	echo "                 status still counts a Notice as a failure, and no"
	echo "                 subject says which of the two 42's grader goes by: the"
	echo "                 *_notice twin of this target, at strict, holds one"
	echo "                 reading of it. The Notice line says what norminette"
	echo "                 asks you to reconsider."
}

if [ -z "$ERRFILES" ]; then
	echo ""
	echo "norminette_test: OK — no file above has a Norm Error."
	notice_warning
	run_info
	exit 0
fi

echo ""
echo "norminette_test: FAIL — the Norm is not satisfied in: $ERRFILES"
# Said only when it happened, because it is the one case a student could check
# for themselves and be misled by: norminette's own `echo $?` says 0.
if [ "$RC" -eq 0 ]; then
	echo "                 (norminette itself exited 0: its status follows the last"
	echo "                 file it checked, so this layer reads each file's own"
	echo "                 verdict line instead.)"
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
if [ "$PARSE_STOP" -eq 1 ]; then
	echo ""
	echo "norminette could not parse that file, and it stops at the first such"
	echo "file without printing anything for the others: it judged $VERDICTS of the"
	echo "$NFILES files given. Make that one parse, then run this again to see the rest."
fi
notice_warning
run_info
echo ""
echo "  A norminette you run yourself may be another version, with other rules."
echo "  bazel run //tools:env_drift compares yours with the one above."
exit 1
