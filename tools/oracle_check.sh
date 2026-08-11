#!/bin/sh
# Run the Rust reference's own self-check (//oracle:oracle check).
#
# WHAT IT CHECKS. `oracle check` sums the failure count of every module's
# check() (c00-c13, rush00-rush02, rush01_bonus, bsq). The
# checks come in three kinds,
# all of them INTERNAL to the crate. Kinds 1 and 2 are in every module; kind 3
# is in only two, so do not read it as blanket coverage:
#
#   1. hand-written tables — literal input/output pairs typed into the Rust
#      source and verified once by a human. c09's strcmp table pins the exact
#      byte difference including high bytes (0x80 vs 0x7f -> 1); rush replays
#      the subject's own worked examples from chapters V..IX verbatim (V is
#      Rush00 and IX is Rush04 — checked against the rush-00 subject).
#   2. property assertions over a seeded sweep — things that must hold for
#      every input rather than for a listed one: sort output is ordered AND a
#      multiset permutation of its input; swap and rev are involutions; div_mod
#      satisfies a == (a/b)*b + a%b with |a%b| < |b| and the C remainder sign;
#      atoi/putnbr and convert_base round-trip; strlcat's return equals
#      min(strlen(dest),size)+strlen(src); strncmp agrees in sign with strcmp;
#      split's tokens contain no separator and concatenate back to the input
#      with its separators removed; the btree traversals are permutations of
#      one multiset and infix == sorted.
#      The WIDTH of that sweep is per-module and deliberately NOT uniform, so
#      quote the module's own number and not a round one: c03 5 000, c04
#      20 000 + 5 000, c05 506 exhaustive probes (-5..500) plus 2 000 random,
#      c13 8 000 generated corpora, the rest 20 000 — each off its own fixed
#      seed. rush is not sampled at all: it renders EVERY 1..60 x 1..60 box for
#      all five variants and holds each against a second, independently written
#      construction in the same crate.
#   3. generator self-checks — that the CORPUS still contains what it claims,
#      which nothing else would notice. ONLY c00 and rush do this. c00 asserts
#      its corpus head still pins 0, +/-1 and the i32 boundaries rather than
#      letting them drift into the random tail; rush asserts its size table
#      stays inside the contract, has no duplicates, and still covers both the
#      subject's sizes and the ceiling dimensions.
#
# WHAT IT DOES NOT CHECK, despite what this comment used to say. It never calls
# libc, and it never reads the curated expected.txt fixtures. The crate is
# std-only with zero dependencies, no extern "C" and no unsafe — there is no C
# library on the other side of any comparison, and none of the 6458 lines opens
# a file. Where a hand-written case happens to match a fixture it was
# transcribed by hand, so editing that fixture does NOT make this guard notice;
# the two can drift apart silently. A green run means the references agree with
# their own tables and their own invariants, which is worth having, but it is
# strictly less than agreement with libc or with the fixtures. Do not quote it
# as more than it is: the whole value of this target is that the repo points at
# it to argue its results are trustworthy.
#
# Without this target that self-check is dead code: a regression in a generator
# or a reference would be discovered by a CORRECT student's test going red,
# which is the single worst failure mode this repo has. It runs in well under a
# second, so it is cheap insurance.
#
# Usage:
#   oracle_check.sh --oracle PATH
#
#   --oracle  $(location //oracle:oracle); the reference binary to self-check
#
# Runs the reference against its own hand-transcribed subject examples. It
# guards the guard: a bugged reference would fail correct student code, and
# nothing else in the suite would notice.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "oracle_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require cat mktemp rm sed

ORACLE=""
# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "oracle_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		*) echo "oracle_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$ORACLE" ] || { echo "oracle_check.sh: --oracle is required" >&2; exit 2; }
[ -x "$ORACLE" ] || { echo "oracle_check.sh: $ORACLE is not executable" >&2; exit 2; }

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT INT TERM

if "$ORACLE" check > "$OUT" 2>&1; then
	cat "$OUT"
	exit 0
fi

echo "oracle_check: FAIL — a reference disagrees with its own hand-written table"
echo "              or its own property assertions. A student's correct code may"
echo "              now be graded red by the diff layer. Fix //oracle first."
echo "---------------- self-check output ----------------"
sed 's/^/  /' "$OUT"
exit 1
