#!/bin/sh
# argv_guard.sh — assert that Bazel handed this test ONE argument containing
# spaces, not sixteen arguments. Tag "selftest": it never runs the student's
# program and it is green the moment the harness is wired correctly.
#
# WHY THIS EXISTS
#
# rush01's entire interface is one argv string with spaces in it:
#
#     ./rush01 "4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2"
#
# and `sh_test`'s `args` attribute is Bourne-shell TOKENISED before it reaches
# the runner. This repo has been bitten by that three times already (c_files'
# --label, c_cycles' --unit-name and --unit-expr; see the fail()s in
# tools/defs.bzl), and every time the symptom was the same: a red test blaming
# something that was not the cause. Those three were all fixed by forbidding
# spaces — which is not available here, because the space-separated string IS
# the interface the subject fixes. So the string is written QUOTED in
# BUILD.bazel and relies on Bourne tokenisation honouring the quotes, i.e. on
#
#     args = ["\"4 3 2 1 ...\""]     ->   one token:   4 3 2 1 ...
#
# rather than sixteen. (The 438-vector sweep does NOT depend on this: it reads
# its clue vectors from a corpus file and its gate's argv from a one-line
# fixture. Only the byte-exact cases in BUILD.bazel have to quote, because
# c_program can only take an invocation from `args`.)
#
# Everything downstream of Bazel was verified by hand:
# tools/diff_output.sh, tools/asan_run.sh and tools/valgrind_test.sh (including
# the `-- "$@"` it forwards to its correctness gate) all pass a spaced argument
# through intact.
#
# Bazel's own tokeniser was checked too, without running a build: `args` is
# expanded through com.google.devtools.build.lib.shell.ShellUtils.tokenize, and
# disassembling that method out of the installed A-server.jar shows it
# special-cases exactly five bytes — 0x09 tab, 0x20 space, 0x22 ", 0x27 ' and
# 0x5c backslash. Those are Bourne quoting rules, so a double-quoted word is one
# token. The guard therefore documents a property that HOLDS today; it is here as
# a regression check, because if it ever stops holding the damage is silent and
# expensive: every invocation becomes argc == 17, a CORRECT rush01 answers Error
# to all of them, and the student is told their working program is wrong.
#
# This guard turns that into a test that says so in one line. It is the FIRST
# thing to read if the output cases fail on a program you believe is right.
#
# Exit status follows the house convention: 0 pass, 2 the harness itself is
# broken. Never 1 — nothing here can be the student's fault.

set -u

# Hardcoded rather than passed in, on purpose: a --want flag would be tokenised
# by the very mechanism this script exists to check, so it could not be trusted
# to arrive intact. Keep this identical to SUBJECT_CLUES in ../../BUILD.bazel.
WANT='4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2'

if [ "$#" -eq 1 ] && [ "$1" = "$WANT" ]; then
	echo "argv_guard: OK — Bazel delivered the clue string as ONE argument."
	echo "            argv[1] = [$1]"
	exit 0
fi

echo "argv_guard: HARNESS BROKEN — this is not your program's fault." >&2
echo "" >&2
echo "  The subject's clue string must reach the program as a SINGLE argument" >&2
echo "  that contains spaces:" >&2
echo "" >&2
echo "      ./rush01 \"$WANT\"" >&2
echo "" >&2
echo "  This test asked Bazel for exactly that and got $# argument(s):" >&2
i=1
for a in "$@"; do
	echo "      argv[$i] = [$a]" >&2
	i=$((i + 1))
done
echo "" >&2
ARGC=$(($# + 1))
if [ "$#" -ne 1 ]; then
	echo "  sh_test tokenises its \`args\` on whitespace, and the quotes that were" >&2
	echo "  supposed to hold the string together were not honoured. EVERY output" >&2
	echo "  case in this exercise is now running a different program invocation" >&2
	echo "  than the subject describes — a correct rush01 sees argc = $ARGC," >&2
	echo "  calls it malformed input and prints Error, so it is reported as wrong." >&2
	echo "" >&2
	echo "  Fix the HARNESS, not the exercise, and do not reshape the subject's" >&2
	echo "  interface to fit the harness: the one argument with spaces in it is" >&2
	echo "  what the subject fixes and what the evaluator will type." >&2
	echo "  tools/argv_table.sh already solves this problem for c-06 by reading" >&2
	echo "  each invocation out of a TAB-separated scenarios file instead of out" >&2
	echo "  of \`args\` — that is the shape to move these cases to." >&2
else
	echo "  One argument arrived, but not the one that was asked for. The string" >&2
	echo "  in BUILD.bazel and the one in this script have drifted apart; they" >&2
	echo "  are two copies of the same constant and must stay identical." >&2
fi
exit 2
