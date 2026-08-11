#!/bin/sh
# Header exercise runner (c-08): compile a provided main() against the student's
# header AT TEST TIME, then diff its output.
#
# Why not a cc_binary, which is what every other exercise shape uses: for a
# header exercise the header IS the answer, so an unwritten one does not compile
# — and a cc_binary that does not compile is a Bazel BUILD failure, not a test
# result. The student got a wall of clang diagnostics about a file they never
# wrote (tests/exNN/test_*.c), no CASE/EXPECTED/GOT table, no hint, and
# `bazel test //...` aborted with "FAILED TO BUILD" instead of showing them a
# red test alongside the others. Every other stub in this repo produces a
# legible red test; this shape should too.
#
# Compiling inside the runner turns "the header is not written yet" into exactly
# that: a failing test that says so, with the exercise's clues attached. Same
# trick tools/ilp32_test.sh uses to keep a toolchain problem out of the build
# graph.
#
# Usage:
#   header_check.sh --differ PATH --hdr FILE --main FILE [--src FILE]...
#                   --expected FILE [--clues FILE] [--labeled]
#                   [--exit CODE] [--cc NAME] [-- PROG ARGS...]
#
# Options:
#   --exit CODE   also assert the built program exits with CODE. Same flag,
#                 same wording and same semantics as tools/diff_output.sh's,
#                 because it IS diff_output.sh's — see the note above the
#                 delegation at the bottom of this file.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "header_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require cut dirname grep head mktemp rm sed

DIFFER=""
HDR=""
MAIN=""
SRCS=""
INCS=""
EXPECTED=""
CLUES=""
PASS=""
EXPECT_EXIT=""
CC="${HEADER_CC:-cc}"

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "header_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--differ) need "$1" "$#"; DIFFER="$2"; shift 2 ;;
		--hdr) need "$1" "$#"; HDR="$2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--main) need "$1" "$#"; MAIN="$2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--src) need "$1" "$#"; SRCS="$SRCS $2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--expected) need "$1" "$#"; EXPECTED="$2"; shift 2 ;;
		--clues) need "$1" "$#"; CLUES="$2"; PASS="$PASS --clues $2"; shift 2 ;;
		--labeled) PASS="$PASS --labeled"; shift ;;
		# Kept OUT of $PASS on purpose: $PASS is expanded unquoted (it has to
		# be, to split into separate words), so a value carrying a space or a
		# glob character would be re-split or filename-expanded on its way
		# through. A code is forwarded as its own quoted word instead, so what
		# diff_output.sh receives is byte-for-byte what we received.
		--exit) need "$1" "$#"; EXPECT_EXIT="$2"; shift 2 ;;
		--cc) need "$1" "$#"; CC="$2"; shift 2 ;;
		--) shift; break ;;
		*) echo "header_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$DIFFER" ] && [ -n "$HDR" ] && [ -n "$MAIN" ] && [ -n "$EXPECTED" ] || {
	echo "header_check.sh: need --differ, --hdr, --main and --expected" >&2
	exit 2
}

command -v "$CC" >/dev/null 2>&1 || {
	# NO_SKIP=1: an absent toolchain is a failure, not a quiet pass.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no compiler, and this layer must not report a silent pass."
		exit 1
	}
	echo "header_check: SKIP — no C compiler ('$CC') available."
	exit 0
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# shellcheck disable=SC2086
if ! "$CC" -Wall -Wextra -Werror $INCS "$MAIN" $SRCS -o "$WORK/bin" 2> "$WORK/cc.err"; then
	echo "header_check: FAIL — the test program does not compile against your header."
	echo ""
	echo "  This exercise's deliverable IS the header, so this is the exercise"
	echo "  itself failing, not a broken test. The program below was written to"
	echo "  use everything the subject says your header must declare; every"
	echo "  diagnostic is something it asked for and did not find, or found with"
	echo "  a different shape than the subject specifies."
	echo ""
	echo "  ---------------- what the compiler said ----------------"
	sed -n '1,25p' "$WORK/cc.err" | sed 's/^/  /'
	if [ -n "$CLUES" ] && [ -f "$CLUES" ]; then
		echo "  ---------------- hint ----------------"
		# The clue file is the same TSV the output layer uses; show the hint
		# column only, since there is no per-case table to attach hints to yet.
		cut -f1 "$CLUES" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' \
			| head -3 | sed 's/^/   * /'
	fi
	exit 1
fi

# --exit is FORWARDED, never reimplemented here.
#
# Why the flag exists at all: this runner's only verdict is what the program
# PRINTED. A header exercise can define a macro that a test main() *returns*
# rather than prints, and a returned value is invisible to a stdout diff — so a
# macro defined as anything at all is green here as long as the printing part of
# the fixture is right. --exit is what lets a fixture put such a macro somewhere
# the harness can see it, by making the value the program's exit status.
#
# Why forwarded: diff_output.sh is the process that actually RUNS the binary. It
# owns the ulimit/timeout wrapper, and the exit status only exists inside it —
# out here we would have to run the program a SECOND time to see one, which is a
# different execution with a possibly different result, and would leave two
# copies of the same comparison to drift apart in wording. Handing the flag
# down keeps one implementation and one message ("exit code N, expected M"), so
# the two layers cannot disagree about what an exit code means.
#
# Two consequences of that inherited from diff_output.sh, both intended:
#   - An EMPTY value asserts nothing, because its gate is [ -n "$EXPECT_EXIT" ]
#     and ours is the same test. --exit "" is a no-op in both layers, not an
#     assertion that the program exits with the empty string.
#   - The statuses diff_output.sh intercepts before its assertion — 153 (output
#     budget blown) and 137/124 (its inner timeout) — exit 1 from inside it with
#     their own explanation, so --exit cannot be used to EXPECT one of those.
#     A crash (>128) is likewise a failure on its own terms whatever is asserted.
# And one from us: the compile arm above runs first, so a program that does not
# build fails there and this layer never claims anything about its exit status.
#
# What this runner deliberately does NOT do is decide which code an exercise
# ought to assert. Nothing is checked unless a caller passes --exit. Where a
# subject does not state a value, picking one is a claim about the exercise's
# requirements — a decision for whoever wires the test and for the subject, not
# for the mechanism that measures it.
# shellcheck disable=SC2086
if [ -n "$EXPECT_EXIT" ]; then
	sh "$DIFFER" --bin "$WORK/bin" --expected "$EXPECTED" $PASS \
		--exit "$EXPECT_EXIT" -- "$@"
else
	sh "$DIFFER" --bin "$WORK/bin" --expected "$EXPECTED" $PASS -- "$@"
fi
