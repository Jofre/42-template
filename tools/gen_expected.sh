#!/bin/sh
# gen_expected.sh — regenerate an exNN expected.txt by running the test harness
# against a TRUSTED REFERENCE implementation, NOT the student's deliverable.
#
# Why: the student's deliverable may be a stub or buggy, so it can never be the
# oracle. Compiling the SAME test_*.c harness against a known-correct reference
# (a libc wrapper for strcmp/atoi/…, or a small hand-audited snippet for custom
# functions) and capturing its stdout yields an expected.txt whose labels,
# ordering and formatting match a real student run by construction — so
# reordering cases or adding new ones can never desync the fixture.
#
# This is a maintenance helper only; it is NOT referenced by any BUILD rule.
#
# Usage:
#   tools/gen_expected.sh <test_harness.c> <reference_impl.c> [extra cc flags...]
#       > c-piscine-c-NN/tests/exNN/expected.txt
#
# The reference_impl.c must define the same ft_* symbol(s) the harness calls.
set -eu

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "gen_expected.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require cc mktemp rm

if [ "$#" -lt 2 ]; then
	echo "usage: gen_expected.sh <test.c> <reference.c> [cc flags...]" >&2
	exit 2
fi

TEST="$1"
REF="$2"
shift 2

BIN="$(mktemp)"
trap 'rm -f "$BIN"' EXIT

# -Wall -Wextra (no -Werror): the reference is dev-only; the student's deliverable
# is what gets -Werror via Bazel. Fail loudly if the reference doesn't compile.
cc -Wall -Wextra "$@" "$TEST" "$REF" -o "$BIN" >&2
"$BIN"
