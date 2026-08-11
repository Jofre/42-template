#!/bin/sh
# Instruction and syscall accounting for ONE function (tag "cycles").
#
# The perf layer measures wall time, which on this harness is mostly harness:
# corpus parsing on both sides, printing on the student's. This one counts
# INSTRUCTIONS instead, via callgrind, attributed to the exercise's own function
# and nothing else. That number is deterministic — same value every run, immune
# to CPU frequency, core migration and whatever else is running — and it excludes
# the harness entirely.
#
# WHY PER UNIT OF WORK, not per call. "500 instructions per call" tells a student
# nothing, because there is nothing to compare it against. Neither available
# anchor survives contact: the Rust reference does not do the same job (its
# o_strlen is s.len(), O(1), against a C ft_strlen that must scan — 2 instructions
# against 354), and a hand-derived "theoretical minimum" would be 74 numbers that
# rot the next time the compiler changes. So the work unit comes from the corpus
# itself: bytes scanned, digits printed, elements sorted. "3.2 instructions per
# byte scanned" needs no reference — a load, a compare and an increment is about
# three, so the number reads itself.
#
# Two things callgrind does NOT count, both deliberate to know about:
#   * kernel instructions. A syscall's cost inside the kernel is invisible;
#     measured, a write()-per-character loop shows 9.9x the instructions of a
#     buffered one where wall time says 24x. Hence the syscall COUNT below,
#     which is exact and needs no pricing.
#   * anything inlined away. The student's ft_* lives in its own translation
#     unit so it is always attributable.
#
# Usage:
#   cycles_check.sh --bin PATH --oracle PATH --oracle-fn FN --symbol NAME
#                   --valgrind PATH --valgrind-tools FILE --callgrind-annotate PATH
#                   [--count N] [--unit-expr AWK] [--unit-name TEXT]
#                   [--gate-differ P --gate-bin P --gate-expected P ...]
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "cycles_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk dirname grep head mktemp readlink rm sed tr wc
# conventions: optional cc -- probed below; without it there is no -O2 binary to
# profile, so the layer SKIPs (and refuses under NO_SKIP) rather than exiting 2.
# conventions: optional perl -- callgrind_annotate is a Perl script that formats
# a profile valgrind already produced, so it decides no verdict; same SKIP path.

BIN=""; ORACLE=""; FN=""; SYM=""; COUNT="3000"
HARNESS=""; SRCS=""; INCS=""; OPT="${CYCLES_OPT:--O2}"
UNIT_EXPR=""; UNIT_NAME="case"; BUDGET=""; SYSCALL_BUDGET=""
GATE_DIFFER=""; GATE_BIN=""; GATE_EXPECTED=""; GATE_PASS=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
VALGRIND=""
VGTOOLS=""
CG_ANNOTATE=""

need() { [ "$2" -ge 2 ] || { echo "cycles_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--valgrind) need "$1" "$#"; VALGRIND="$2"; shift 2 ;;
		--valgrind-tools) need "$1" "$#"; VGTOOLS="$2"; shift 2 ;;
		--callgrind-annotate) need "$1" "$#"; CG_ANNOTATE="$2"; shift 2 ;;
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--harness) need "$1" "$#"; HARNESS="$2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--src) need "$1" "$#"; SRCS="$SRCS $2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--inc) need "$1" "$#"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--oracle-fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--symbol) need "$1" "$#"; SYM="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--unit-expr) need "$1" "$#"; UNIT_EXPR="$2"; shift 2 ;;
		--unit-name) need "$1" "$#"; UNIT_NAME="$2"; shift 2 ;;
		--budget) need "$1" "$#"; BUDGET="$2"; shift 2 ;;
		--syscall-budget) need "$1" "$#"; SYSCALL_BUDGET="$2"; shift 2 ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-stdin) need "$1" "$#"; GATE_PASS="$GATE_PASS --stdin $2"; shift 2 ;;
		--gate-sanitize) GATE_PASS="$GATE_PASS --sanitize"; shift ;;
		--gate-labeled) GATE_PASS="$GATE_PASS --labeled"; shift ;;
		*) echo "cycles_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$ORACLE" ] && [ -n "$FN" ] && [ -n "$SYM" ] || {
	echo "cycles_check.sh: need --oracle, --oracle-fn and --symbol" >&2
	exit 2
}
[ -n "$BIN" ] || [ -n "$HARNESS" ] || {
	echo "cycles_check.sh: need --bin, or --harness plus --src" >&2
	exit 2
}

# EVERY skip in this layer is a silent green, and this is the only layer that
# would ever notice a function that is correct and does an order of magnitude too
# much work — so a skip nobody reads is indistinguishable from a pass. The skips
# below (no callgrind, no compiler, no corpus, profiling failed, symbol absent
# from the profile) between them cover every way this plumbing can rot, and the
# one that motivated guarding all of them is the last: callgrind_annotate's
# output format is not an interface anyone promised us, and a change to it empties
# $IR for every exercise at once. That would retire the entire layer in a single
# upstream release with every target still green, and nothing would say so.
#
# NO_SKIP=1 — set in CI, see rust_diff.sh — turns each of them into a failure that
# names which one fired, so the rot is visible the day it happens rather than
# whenever someone next wonders why nothing has ever been over budget.
# The valgrind these layers run is FETCHED AND PINNED, never found on PATH. No
# host fallback: a missing --valgrind is a wiring error, not a skip. See
# valgrind_test.sh for the full reasoning and for why $VALGRIND_LIB is what
# makes a relocated valgrind work at all.
#
# callgrind_annotate stays a SKIP rather than a hard error: it is a Perl script
# that formats a profile valgrind already produced, so its absence costs this
# layer and nothing else, and pinning an interpreter to read one text file is
# the wrong trade. tools/pins.tsv carries a perl row so a campus move is visible.
[ -n "$VALGRIND" ] || {
	echo "cycles_check: --valgrind is required (the pinned valgrind.bin)" >&2
	exit 2
}
case "$VALGRIND" in
	/*) ;;
	*) VALGRIND="$PWD/$VALGRIND" ;;
esac
case "$CG_ANNOTATE" in
	""|/*) ;;
	*) CG_ANNOTATE="$PWD/$CG_ANNOTATE" ;;
esac
[ -f "$VALGRIND" ] && [ -x "$VALGRIND" ] || {
	echo "cycles_check: pinned valgrind missing or not executable: $VALGRIND" >&2
	exit 2
}
# The directory has to hold the TOOL, not merely exist: a binary that cannot
# find part of its own tree can fall back to the box's copy, report the pinned
# version and go green.
# The tool directory is derived from a FILE inside it, not passed as a
# directory, and that is deliberate: `$(location x)/..` walks through a file
# rather than naming its parent, and `cd && pwd` stops at the runfiles tree,
# whose directories are real while the files in them are symlinks. Resolving the
# file with readlink -f and taking ITS directory is the one form that survives
# both. This repo has been bitten by the other two.
VGTOOLS=$(readlink -f "$VGTOOLS" 2> /dev/null || echo "$VGTOOLS")
VGLIB=$(dirname "$VGTOOLS")
[ -f "$VGLIB/callgrind-amd64-linux" ] || {
	echo "cycles_check: $VGLIB does not hold callgrind-amd64-linux, so the pinned" >&2
	echo "             valgrind cannot run callgrind. Wiring error." >&2
	exit 2
}
VALGRIND_LIB="$VGLIB"
export VALGRIND_LIB
if [ -z "$CG_ANNOTATE" ] || [ ! -f "$CG_ANNOTATE" ] || ! command -v perl > /dev/null 2>&1; then
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: callgrind_annotate (or perl to run it) is unavailable"
		echo "             and this layer must not pass silently."
		exit 1
	}
	echo "cycles_check: SKIP — callgrind_annotate/perl not available."
	exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM

# Same correctness gate as the perf layer: counting the instructions of a wrong
# answer is not information. NO_SKIP=1 forces it open.
if [ "${NO_SKIP:-0}" != "1" ] && [ -n "$GATE_DIFFER" ] && [ -n "$GATE_BIN" ] &&
	[ -n "$GATE_EXPECTED" ] && [ -x "$GATE_BIN" ] && [ -f "$GATE_EXPECTED" ]; then
	# shellcheck disable=SC2086
	if ! sh "$GATE_DIFFER" --bin "$GATE_BIN" --expected "$GATE_EXPECTED" \
			$GATE_PASS >/dev/null 2>&1; then
		echo "cycles_check: SKIP — this exercise's output fixture is not passing yet."
		echo "              Counting the instructions of a wrong answer is not useful;"
		echo "              this starts measuring once the *_output layer is green."
		exit 0
	fi
fi

# Build our OWN binary, optimised.
#
# This layer cannot reuse the harness Bazel already built: `fastbuild` is -O0,
# where every local is a memory round-trip, and that inflates the count by ~3.6x
# — ft_strlen measures 11.4 instructions per byte at -O0 and 3.2 at -O2. The
# whole point of a per-unit figure is that it can be read against what the work
# ought to cost, and 3.2 is the floor (a load, a compare, an increment) while
# 11.4 reads as "three times too slow" for code that is in fact optimal. So the
# number has to come from an optimised build or it measures the build mode.
if [ -n "$HARNESS" ]; then
	if ! command -v cc >/dev/null 2>&1; then
		# NO_SKIP=1: without cc there is no -O2 binary, so nothing was profiled.
		[ "${NO_SKIP:-0}" != "1" ] || {
			echo "NO_SKIP set: no C compiler, so the $OPT binary this layer measures"
			echo "             was never built and no instruction count was taken."
			exit 1
		}
		echo "cycles_check: SKIP — no C compiler."
		exit 0
	fi
	# shellcheck disable=SC2086
	if ! cc $OPT -g -w $INCS "$HARNESS" $SRCS -o "$T/bin" 2> "$T/cc.err"; then
		echo "cycles_check: FAIL — could not build the harness at $OPT"
		sed -n '1,15p' "$T/cc.err" | sed 's/^/    /'
		exit 1
	fi
	BIN="$T/bin"
fi

if ! "$ORACLE" "$FN" 1 "$COUNT" > "$T/corpus" 2>/dev/null || [ ! -s "$T/corpus" ]; then
	# NO_SKIP=1: a renamed or removed oracle fn silently empties the corpus, and
	# the binary would then be profiled against no input at all.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: the reference produced no corpus for fn=$FN, so the"
		echo "             function was never given anything to do."
		exit 1
	}
	echo "cycles_check: SKIP — the reference could not generate a corpus (fn=$FN)."
	exit 0
fi
CASES=$(wc -l < "$T/corpus" | tr -d ' ')

# The unit of work, summed straight off the corpus so it cannot drift from the
# inputs actually used. Default: one unit per case.
if [ -n "$UNIT_EXPR" ]; then
	WORK=$(awk -F'\t' "{ s += $UNIT_EXPR } END { printf \"%d\", s }" "$T/corpus")
else
	WORK=$CASES
fi
[ "${WORK:-0}" -gt 0 ] 2>/dev/null || WORK=$CASES

"$VALGRIND" --tool=callgrind --callgrind-out-file="$T/cg" "$BIN" < "$T/corpus" \
	> /dev/null 2>"$T/vg.err" || {
	# NO_SKIP=1: valgrind failing to run is also how a student's binary crashing
	# under it looks, so this branch is the one most likely to be hiding a real
	# finding rather than a missing tool.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: callgrind could not profile the harness, so there is no"
		echo "             instruction count for $SYM. What valgrind said:"
		sed -n '1,5p' "$T/vg.err" | sed 's/^/    /'
		exit 1
	}
	echo "cycles_check: SKIP — callgrind could not profile the harness."
	sed -n '1,5p' "$T/vg.err" | sed 's/^/    /'
	exit 0
}

# INCLUSIVE cost: the function plus everything it calls. That is the honest
# number — a ft_putstr that calls write() per character should be charged for
# the write(), because calling it was the decision under test.
IR=$("$CG_ANNOTATE" --inclusive=yes --threshold=100 "$T/cg" 2>/dev/null \
	| grep -aE "[:.]$SYM \[" | head -1 | tr -d ' ,' | grep -oE '^[0-9]+')

if [ -z "$IR" ]; then
	# NO_SKIP=1: this is the site the guards above were added for. An empty $IR
	# means either this one exercise's symbol vanished or callgrind_annotate's
	# columns moved under us — and the second case fires for every exercise at
	# once while every target stays green, which is the failure this whole layer
	# exists to make impossible.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no symbol '$SYM' in the callgrind profile, so nothing was"
		echo "             measured. If this fires for every exercise, suspect the"
		echo "             parsing of callgrind_annotate above, not the deliverables."
		exit 1
	}
	echo "cycles_check: SKIP — no symbol '$SYM' in the profile."
	echo "              It may have been inlined, or the deliverable may not define it."
	exit 0
fi

# Calls the function itself makes. callgrind records these as cfn=/calls= pairs
# under the caller, so this counts only what $SYM triggered, not the harness's.
callee_calls() {
	# callgrind COMPRESSES names: a function is written "fn=(12) ft_putstr" the
	# first time and bare "fn=(12)" every time after. Matching on the text alone
	# therefore sees only the first block and reports 0 — which is exactly the
	# wrong answer for the case this layer exists to catch. Resolve the id->name
	# table first, then match on ids.
	awk -v want="$1" -v sym="$SYM" '
		function id(s,   p, q) { p = index(s, "("); q = index(s, ")");
			return (p && q) ? substr(s, p + 1, q - p - 1) : "" }
		function nm(s,   q) { q = index(s, ")");
			return (q && length(s) > q + 1) ? substr(s, q + 2) : "" }
		/^fn=/  { i = id($0); n = nm($0); if (n != "") fname[i] = n; curfn = i }
		/^cfn=/ { i = id($0); n = nm($0); if (n != "") fname[i] = n; curcfn = i }
		/^calls=/ {
			if (index(fname[curfn], sym) > 0 && index(fname[curcfn], want) > 0) {
				split($0, a, "[= ]"); total += a[2]
			}
		}
		END { print total + 0 }
	' "$T/cg"
}
WRITES=$(callee_calls "write")
MALLOCS=$(callee_calls "malloc")

echo "cycles_check: $SYM over $CASES cases (built $OPT)"
echo ""
printf '  instructions      : %s total, inclusive of everything it calls\n' "$IR"
PER_UNIT=$(awk -v i="$IR" -v w="$WORK" 'BEGIN { printf "%.1f", i / w }')
PER_CASE=$(awk -v x="$WRITES" -v c="$CASES" 'BEGIN { printf "%.2f", x / c }')
printf '  per %-14s: %s' "$UNIT_NAME" "$PER_UNIT"
if [ -n "$BUDGET" ]; then
	printf '   (a good implementation manages about %s)\n' "$BUDGET"
else
	printf '\n'
fi
printf '  per call          : %s\n' \
	"$(awk -v i="$IR" -v c="$CASES" 'BEGIN { printf "%.1f", i / c }')"
echo ""
printf '  write() calls     : %s  (%s per case' "$WRITES" "$PER_CASE"
if [ -n "$SYSCALL_BUDGET" ]; then
	printf ', budget %s)\n' "$SYSCALL_BUDGET"
else
	printf ')\n'
fi
printf '  malloc() calls    : %s  (%.2f per case)\n' "$MALLOCS" \
	"$(awk -v x="$MALLOCS" -v c="$CASES" 'BEGIN { printf "%.2f", x / c }')"
echo ""

# The budgets are NUMBERS, never a reference implementation. A target tells you
# where you stand; source code would tell you the answer, which is the one thing
# a test in this repo must never do.
if [ -n "$BUDGET" ]; then
	awk -v got="$PER_UNIT" -v want="$BUDGET" -v u="$UNIT_NAME" 'BEGIN {
		r = got / want
		if (r <= 1.3) printf "  You are at or near the budget for instructions per %s.\n", u
		else if (r <= 3) printf "  About %.1fx the budget per %s — some slack, nothing alarming.\n", r, u
		else printf "  About %.0fx the budget per %s. That is a lot of extra work per unit;\n  what is the loop doing that it need not?\n", r, u
	}'
fi
# NOTHING BELOW CAN FAIL THIS TEST. Every branch here prints; the script ends in
# exit 0 no matter what the numbers say. That is the layer's design — an
# instruction count is something to think about, not a rule — and it is written
# out because the opposite reading was available and this comment used to invite
# it, calling the zero branch an "assertion". It is a statement.
#
# A budget of 0 is the strongest thing a c_cycles target can SAY — "this function
# has no business entering the kernel" — and it was the one value that said
# nothing: `if (want <= 0) exit` was there to stop the ratio below dividing by
# zero, but it discarded the message instead of adapting it, so all 25 of the
# targets written with syscall_budget = 0 printed "budget 0" and no verdict.
# Zero has no meaningful ratio, so it gets its own branch: any syscall at all is
# over it. An ABSENT budget still says nothing, which is why the test outside
# stays `[ -n ... ]` and not a numeric one.
# The branch keeps the original `<= 0` so a typo'd negative budget reads as the
# same assertion rather than dividing into a ratio that would print "at budget".
#
# The zero branch compares the RAW COUNT, not the per-case average: PER_CASE is
# rendered to two decimals, so one stray write() across 3000 cases prints as 0.00
# and would read as "at budget" — exactly the case a zero budget is written for.
if [ -n "$SYSCALL_BUDGET" ]; then
	awk -v got="$PER_CASE" -v total="$WRITES" -v want="$SYSCALL_BUDGET" 'BEGIN {
		if (want + 0 <= 0) {
			if (total + 0 == 0) {
				print "  Syscalls: none, which is the budget for this function."
			} else {
				printf "  %d write() call(s), against a budget of NONE.\n", total
				print "  This function is not budgeted for a single syscall: talking to the"
				print "  kernel is not part of the job the subject gives it. Re-read what it"
				print "  says this function produces, and where that result is meant to go."
			}
			exit
		}
		r = got / want
		if (r <= 1.3) print "  Syscalls are at budget."
		else printf "  %.0fx the syscall budget. Each one is a round trip into the kernel that\n  callgrind cannot even see the cost of — the instruction count above\n  UNDERSTATES what this costs in wall time.\n", r
	}'
fi
echo ""
echo "  Instruction counts are exact and repeat run to run, and exclude the test"
echo "  harness — this is your function and what it calls, nothing else. Read the"
echo "  per-$UNIT_NAME figure: it needs no reference, because you know roughly what"
echo "  one unit of that work costs. A byte scan is a load, a compare and an"
echo "  increment; a few instructions per byte is near the floor, thirty is not."
echo ""
echo "  Kernel time is NOT in these counts, so the syscall numbers stand on their"
echo "  own: one write() per string is the floor, one per CHARACTER is the classic"
echo "  way to be O(n) and still slow."
exit 0
