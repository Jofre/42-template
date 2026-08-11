#!/bin/sh
# Cost of the student's whole program against an optimised reference doing the
# SAME job (tag "cycles"). Informative only — this layer never fails on the
# number it reports.
#
# ---------------------------------------------------------------------------
# WHY A SECOND COST LAYER, when cycles_check.sh already counts instructions
#
# cycles_check reports instructions per UNIT OF WORK and relies on that number
# reading itself: a byte scan is a load, a compare and an increment, so "3.2 per
# byte" needs no reference at all — the student already knows roughly what one
# byte of scanning ought to cost. That trick stops working the moment the unit
# of work is not something anyone has an intuition for. "29523 instructions per
# solution found" is unreadable: is one solution of a ten-queens search worth
# 3000 instructions, or 300000? Nobody can say, so the figure informs nobody,
# and a budget number invented for it would be a number someone made up.
#
# The figure only becomes information when it stands beside another figure for
# the same job, and the only honest source of that is an implementation that
# actually does the same job. Hence this layer: measure both, print both, and
# let the gap be the thing the student reads.
#
# ---------------------------------------------------------------------------
# WHY IT MUST NEVER GATE
#
# A correct ten-queens search is a correct ten-queens search. A student who
# wrote one has finished the exercise the subject set, and being some multiple
# off an optimised implementation is a completely acceptable place to stand —
# most working software stands there. Failing a correct answer for its cost
# would teach that there is a secret second requirement, which there is not.
#
# So the exit status is 0 whatever the numbers say. The only non-zero exits here
# are the NO_SKIP refusals (this layer's plumbing rotted while pretending to
# pass, exit 1) and harness breakage (exit 2). The ratio itself is never one.
#
# And the report never names the technique that closes the gap. It says where
# the difference LIVES and stops there, because the whole point of measuring
# this is to make a student curious enough to go and find out — from the
# subject, from paper, from the peer on their right. See AGENTS.md §0 and §2:
# open the door, do not push anyone through it.
#
# ---------------------------------------------------------------------------
# WHY WHOLE-PROGRAM TOTALS, not one symbol like cycles_check does
#
# There is no symbol common to both sides — the reference is a different binary
# in a different language. Whole-process instruction counts are the only
# apples-to-apples measurement available, and they are fair here because both
# processes do the same job end to end: run the same search, print the same
# bytes, exit.
#
# Two consequences, both deliberate:
#   * Both totals include process startup and dynamic linking, and the two are
#     not equal: measured here, ~135k instructions for a C binary whose main()
#     just returns, and ~380k for the Rust //oracle on a trivial run (its
#     runtime brings more with it). Both are small next to either side's real
#     work, and the asymmetry is in the safe direction — the side carrying the
#     LARGER fixed cost is the reference, i.e. the denominator, so the printed
#     ratio is a LOWER bound on the algorithmic gap. Erring towards "your code
#     is closer to the reference than it really is" is the only direction a
#     number like this may err in.
#   * Kernel time is invisible to callgrind, exactly as in cycles_check. That is
#     why the write() counts are printed too: when both sides make the same
#     number of syscalls, the kernel time they hide is the same on both sides
#     and cancels out of the ratio. That equality is what makes the comparison a
#     statement about the search rather than about printing, so it is reported
#     rather than assumed.
#
# ---------------------------------------------------------------------------
# WHY --kind EXISTS, i.e. why the closing prose is not one text
#
# Everything above is true of any exercise. The closing paragraphs are not. They
# are the part that has to say WHERE the difference lives, and that depends
# entirely on what the exercise is doing. For a backtracking search the honest
# answer is about the shape of the tree and the price of testing one candidate,
# and that is what --kind search says. For an exercise whose entire job is
# emitting a fixed stream of bytes there is no tree, no candidate and no
# algorithm to be off by a factor on: the same words are not merely unhelpful,
# they send someone hunting through their file for a search that is not in it.
#
# What separates two implementations of a fixed byte stream is how many times
# each one enters the kernel to hand those bytes over — and that is precisely
# the axis the instruction ratio above CANNOT see, because callgrind counts user
# instructions and a syscall's cost is almost entirely on the other side of the
# mode switch. So --kind output replaces the closing block with one written to
# that axis: bytes out, write() calls, and the distance to a floor of one call.
#
# The two kinds share everything else — the same -O2 build, the same two
# profiled runs, the same table, the same refusal to gate. Only the
# interpretation forks, because only the interpretation was ever
# exercise-specific. Text that both kinds need is in a function called from
# both, rather than copied: two copies of a paragraph are two paragraphs that
# will eventually disagree, and the one that drifts is the one nobody reruns.
#
# ---------------------------------------------------------------------------
# Usage:
#   ref_compare.sh --src FILE [--src FILE]... [--inc DIR]... --harness FILE
#                  --symbol NAME --label TEXT
#                  --oracle PATH --oracle-fn FN
#                  --units N --unit-name TEXT
#                  --valgrind PATH --valgrind-tools FILE --callgrind-annotate PATH
#                  [--kind search|output]
#                  [--gate-differ F --gate-bin P --gate-expected F
#                   [--gate-labeled] [--gate-sanitize] [--gate-stdin F]]
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "ref_compare.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat cmp dirname grep head mktemp readlink rm sed tail tr wc
# conventions: optional cc -- probed below; without it neither side of the
# comparison is built, so the layer SKIPs (and refuses under NO_SKIP).
# conventions: optional perl -- see cycles_check.sh; it formats a profile
# valgrind already produced and decides no verdict.

SRCS=""; INCS=""; HARNESS=""; SYM=""; LABEL=""
ORACLE=""; FN=""; UNITS=""; UNIT_NAME="solution"
# What the closing interpretation is about. "search" is the default on purpose:
# it is what every existing caller means, so adding this flag changed no report
# that already existed. See the WHY block above.
KIND="search"
# Same env knob as cycles_check.sh, deliberately NOT a second name for the same
# thing: the two layers must never disagree about what "the student's cost"
# means. The flags actually used are echoed in the header so a non-default build
# cannot silently change the ratio without saying so.
OPT="${CYCLES_OPT:--O2}"
GATE_DIFFER=""; GATE_BIN=""; GATE_EXPECTED=""; GATE_PASS=""

# --inc takes either a directory or a header file: Bazel's $(location) on an
# hdrs entry resolves to the FILE and the compiler needs its directory, while
# an extra_includes entry is already a directory. Same helper, same comment, as
# symbols_test.sh / prototype_check.sh / ilp32_test.sh — a bare `dirname` here
# would silently turn a directory into its PARENT, i.e. add the wrong -I and
# then fail the compile with a missing-header error that names neither cause.
_dir() {
	if [ -d "$1" ]; then printf '%s\n' "$1"; else dirname "$1"; fi
}

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
VALGRIND=""
VGTOOLS=""
CG_ANNOTATE=""

need() { [ "$2" -ge 2 ] || { echo "ref_compare.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--valgrind) need "$1" "$#"; VALGRIND="$2"; shift 2 ;;
		--valgrind-tools) need "$1" "$#"; VGTOOLS="$2"; shift 2 ;;
		--callgrind-annotate) need "$1" "$#"; CG_ANNOTATE="$2"; shift 2 ;;
		--src) need "$1" "$#"; SRCS="$SRCS $2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--harness) need "$1" "$#"; HARNESS="$2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--inc) need "$1" "$#"; INCS="$INCS -I$(_dir "$2")"; shift 2 ;;
		--symbol) need "$1" "$#"; SYM="$2"; shift 2 ;;
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--oracle-fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--units) need "$1" "$#"; UNITS="$2"; shift 2 ;;
		--unit-name) need "$1" "$#"; UNIT_NAME="$2"; shift 2 ;;
		--kind) need "$1" "$#"; KIND="$2"; shift 2 ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-stdin) need "$1" "$#"; GATE_PASS="$GATE_PASS --stdin $2"; shift 2 ;;
		--gate-sanitize) GATE_PASS="$GATE_PASS --sanitize"; shift ;;
		--gate-labeled) GATE_PASS="$GATE_PASS --labeled"; shift ;;
		# The likeliest cause of landing here is not a typo: sh_test tokenises
		# `args` on spaces, so a two-word --label or --unit-name arrives as an
		# extra bare argument. c_files and c_cycles both learned this the hard
		# way, so the error names it rather than leaving someone to rediscover
		# it from "unknown option: implementation".
		*) echo "ref_compare.sh: unknown option: $1" >&2
			echo "                (sh_test tokenises args on spaces — a multi-word" >&2
			echo "                 --label or --unit-name arrives here as extras.)" >&2
			exit 2 ;;
	esac
done

[ -n "$HARNESS" ] && [ -n "$SRCS" ] || {
	echo "ref_compare.sh: need --harness and at least one --src" >&2
	exit 2
}
[ -n "$ORACLE" ] && [ -n "$FN" ] && [ -n "$SYM" ] || {
	echo "ref_compare.sh: need --oracle, --oracle-fn and --symbol" >&2
	exit 2
}
# The unit count is a constant here rather than something summed off a corpus
# (this function takes no input, so there is no corpus to sum). It is the number
# every figure below is divided by, so a missing or junk value would silently
# turn the whole report into nonsense rather than into an error.
[ -n "$UNITS" ] && [ "$UNITS" -gt 0 ] 2>/dev/null || {
	echo "ref_compare.sh: --units must be a positive integer (got: '${UNITS:-}')" >&2
	exit 2
}
# --symbol names the function under test and is what the report calls it when no
# --label is given. It is NOT what gets measured — this layer counts whole
# processes, for the reason in the header — and it is required anyway so that
# every report says out loud which deliverable it is about, the same way
# cycles_check's does.
[ -n "$LABEL" ] || LABEL="$SYM"

# A typo'd --kind must be an error, never a silent fallback to the default. The
# whole reason this flag exists is that the wrong closing text is actively
# misleading — "walk the same tree" printed under ft_print_alphabet would send a
# beginner looking for a search they never wrote — so "--kind ouput" quietly
# becoming "search" is the one failure mode this validation is here to prevent.
# Exit 2, because a mistyped flag is the caller's bug and never the student's.
case "$KIND" in
	search|output) ;;
	*) echo "ref_compare.sh: --kind must be 'search' or 'output' (got: '$KIND')" >&2
		exit 2 ;;
esac

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT INT TERM

# ---------------------------------------------------------------------------
# CORRECTNESS FIRST, exactly as rust_diff.sh, cycles_check.sh, perf_test.sh and
# valgrind_test.sh do it.
#
# A cost figure attached to a wrong answer is worse than no figure: it invites a
# student to optimise a search that does not yet find the right boards, and it
# implies the harness thinks they are done. This layer therefore says nothing at
# all until ex08's own output fixture is green, and says WHY it is saying
# nothing so a silent green is not mistaken for approval.
#
# NO_SKIP=1 (set in CI) forces the gate open, so a layer that has quietly
# stopped measuring is visible the day it happens.
# ---------------------------------------------------------------------------
if [ "${NO_SKIP:-0}" != "1" ] && [ -n "$GATE_DIFFER" ] && [ -n "$GATE_BIN" ] &&
	[ -n "$GATE_EXPECTED" ] && [ -x "$GATE_BIN" ] && [ -f "$GATE_EXPECTED" ]; then
	# shellcheck disable=SC2086
	if ! sh "$GATE_DIFFER" --bin "$GATE_BIN" --expected "$GATE_EXPECTED" \
			$GATE_PASS >/dev/null 2>&1; then
		echo "ref_compare: SKIP — this exercise's output fixture is not passing yet."
		echo "             What a wrong answer costs is not information: the number"
		# The middle clause is the one sentence in this message that names what
		# the exercise DOES, so it is the one sentence that goes wrong when the
		# exercise is not a search. This message is read at the worst possible
		# moment — the student's exercise is red and they came here for a reason —
		# and telling a beginner stuck on ft_print_alphabet about "boards" is how
		# a report teaches someone to stop reading reports. --kind search's wording
		# is untouched, byte for byte.
		if [ "$KIND" = "output" ]; then
			echo "             would describe a program that does not yet emit the right"
			echo "             bytes. This starts comparing once the *_output layer is"
		else
			echo "             would describe a search that does not yet find the right"
			echo "             boards. This starts comparing once the *_output layer is"
		fi
		echo "             green — get it right first, then look at what it cost."
		exit 0
	fi
fi

# ---------------------------------------------------------------------------
# TOOLS. Every skip below is a silent green, and a silent green from an
# informative layer is indistinguishable from a layer with nothing to say — so
# each one honours NO_SKIP=1 by failing and naming itself instead. This is the
# same reasoning as cycles_check.sh's guards, and for the same reason: the
# failure mode that matters is not "callgrind is missing on one laptop", it is
# "this layer stopped producing numbers a year ago and every target stayed
# green".
# ---------------------------------------------------------------------------
# The valgrind this layer runs is FETCHED AND PINNED -- see valgrind_test.sh for
# the reasoning, and cycles_check.sh for the identical probe. No host fallback.
[ -n "$VALGRIND" ] || {
	echo "ref_compare.sh: --valgrind is required (the pinned valgrind.bin)" >&2
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
	echo "ref_compare.sh: pinned valgrind missing or not executable: $VALGRIND" >&2
	exit 2
}
# The tool directory is derived from a FILE inside it, not passed as a
# directory, and that is deliberate: `$(location x)/..` walks through a file
# rather than naming its parent, and `cd && pwd` stops at the runfiles tree,
# whose directories are real while the files in them are symlinks. Resolving the
# file with readlink -f and taking ITS directory is the one form that survives
# both. This repo has been bitten by the other two.
VGTOOLS=$(readlink -f "$VGTOOLS" 2> /dev/null || echo "$VGTOOLS")
VGLIB=$(dirname "$VGTOOLS")
[ -f "$VGLIB/callgrind-amd64-linux" ] || {
	echo "ref_compare.sh: $VGLIB does not hold callgrind-amd64-linux, so the" >&2
	echo "                pinned valgrind cannot run callgrind. Wiring error." >&2
	exit 2
}
VALGRIND_LIB="$VGLIB"
export VALGRIND_LIB
if [ -z "$CG_ANNOTATE" ] || [ ! -f "$CG_ANNOTATE" ] || ! command -v perl > /dev/null 2>&1; then
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: callgrind_annotate (or perl to run it) is unavailable, so"
		echo "             neither side was measured and this layer must not pass silently."
		exit 1
	}
	echo "ref_compare: SKIP — callgrind_annotate/perl not available."
	exit 0
fi
if ! command -v cc >/dev/null 2>&1; then
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no C compiler, so the $OPT binary this layer measures was"
		echo "             never built and there is nothing to compare."
		exit 1
	}
	echo "ref_compare: SKIP — no C compiler."
	exit 0
fi

# ---------------------------------------------------------------------------
# Build our OWN binary, optimised.
#
# Bazel's fastbuild is -O0, where every local is a memory round-trip; measured
# on cycles_check that inflates a count by ~3.6x. Against a reference that is
# already optimised, an -O0 student build would manufacture most of the gap this
# layer then reports — the number would be about the build mode and the student
# would be invited to chase something they did not do. So the comparison is
# -O2 against -O2 and the header says so.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2086
if ! cc $OPT -g -w $INCS "$HARNESS" $SRCS -o "$T/student" 2> "$T/cc.err"; then
	echo "ref_compare: FAIL — could not build the harness at $OPT"
	sed -n '1,15p' "$T/cc.err" | sed 's/^/    /'
	exit 1
fi

# ---------------------------------------------------------------------------
# INTEGRITY: validate the reference BEFORE trusting a number that comes out of
# it. A ratio is a claim about two implementations; if the reference did not do
# the job — renamed arm, half-written arm, an arm that computes but forgets to
# print — the ratio is not merely wrong, it is wrong in the direction that
# flatters or slanders the student for no reason, and nothing else in the suite
# would notice.
#
# The check runs the bench arm plainly (not under callgrind) first: it costs
# milliseconds, and failing here rather than after profiling means a broken
# oracle reports itself immediately.
#
# stdin comes from /dev/null, exactly as the profiled runs below do. This arm is
# the one bench arm in //oracle that reads NOTHING from stdin — every other one
# goes through common::bench_lines(), which blocks until EOF. Point --oracle-fn
# at one of those by mistake, or let this arm grow a stdin read, and an
# inherited terminal turns this line into a hang with no output rather than an
# error: measured, it sat there until it was killed. The runners must be
# unhangable on a bad argument, so the redirect is not optional and is not
# merely for symmetry.
#
# WHAT "correct" MEANS HERE depends on the kind, because the two kinds make
# different promises about the reference's output and each is checked against
# the promise it actually made.
#
#   search: derived from --units rather than hardcoded. The reference emits one
#     line per unit of work plus a final line stating the count, so for
#     --units 724 that is 725 lines whose last is "724" — byte-identical to the
#     exercise's own expected.txt. Deriving it keeps one number, --units, as the
#     single statement of how much work the job is.
#
#   output: the reference's whole contract is that it emits the exercise's
#     expected bytes, so the check is `cmp` against the exercise's own
#     expected.txt, which --gate-expected already names. That is a STRONGER
#     check than any line-arithmetic — it catches a byte, not just a shape —
#     and it is available for free because the gate wiring already passes the
#     file. These exercises' fixtures have no trailing newline (c-00 ex01 is 26
#     bytes, not 27), which is exactly the kind of one-byte difference a line
#     count would wave through and a comparison against the reference would then
#     silently be about.
#
#     If --gate-expected was not passed, this falls back to the non-empty check
#     above and says nothing more. That is a real hole and it is deliberate: the
#     alternative is refusing to run for a caller who wired the layer correctly
#     but minimally, and a layer that exits 2 on a legitimate invocation is
#     worse than one that checks a little less.
#
# Exit 2, not 1 and not a skip: a broken reference is harness breakage, never
# the student's doing, and it must not pass quietly while printing a ratio.
# ---------------------------------------------------------------------------
if ! "$ORACLE" bench "$FN" > "$T/ref.out" 2> "$T/ref.err" < /dev/null ||
	[ ! -s "$T/ref.out" ]; then
	echo "ref_compare: HARNESS ERROR — the reference's bench arm produced nothing"
	echo "             for fn=$FN. Nothing can be compared against it, and no"
	echo "             ratio will be invented in its place. What it said:"
	sed -n '1,5p' "$T/ref.err" | sed 's/^/    /'
	exit 2
fi
if [ "$KIND" = "output" ]; then
	if [ -n "$GATE_EXPECTED" ] && [ -f "$GATE_EXPECTED" ] &&
		! cmp -s "$T/ref.out" "$GATE_EXPECTED"; then
		echo "ref_compare: HARNESS ERROR — the reference did not emit this exercise's"
		echo "             bytes: $(wc -c < "$T/ref.out" | tr -d ' ') of them against the fixture's $(wc -c < "$GATE_EXPECTED" | tr -d ' ')."
		echo "             A reference that prints something else is not doing the"
		echo "             student's job, so neither its instruction count nor its"
		echo "             syscall count describes that job. Fix the oracle's $FN arm."
		exit 2
	fi
else
	REF_LINES=$(wc -l < "$T/ref.out" | tr -d ' ')
	REF_LAST=$(tail -n 1 "$T/ref.out")
	WANT_LINES=$((UNITS + 1))
	if [ "$REF_LINES" != "$WANT_LINES" ] || [ "$REF_LAST" != "$UNITS" ]; then
		echo "ref_compare: HARNESS ERROR — the reference's output is not the shape this"
		echo "             comparison is built on. Expected $WANT_LINES lines ending in"
		echo "             \"$UNITS\"; got $REF_LINES lines ending in \"$REF_LAST\"."
		echo "             The reference must do the WHOLE job, printing included, or"
		echo "             its instruction count excludes work the student is charged"
		echo "             for and the ratio is a lie. Fix the oracle's $FN arm."
		exit 2
	fi
fi

# ---------------------------------------------------------------------------
# Measure. stdout to /dev/null on both sides so neither is charged for the
# terminal or for a pipe, and stdin from /dev/null so a stray read cannot hang a
# profiled run. The reference is run through the SAME wrapper as the student for
# the same reason both are built -O2: any asymmetry in how they are measured
# comes back as a ratio nobody can defend.
# ---------------------------------------------------------------------------
profile() {
	_out="$1"; shift
	"$VALGRIND" --tool=callgrind --callgrind-out-file="$_out" "$@" \
		> /dev/null 2>"$T/vg.err" < /dev/null && return 0
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: callgrind could not profile $1, so there is no instruction"
		echo "             count to compare. What valgrind said:"
		sed -n '1,5p' "$T/vg.err" | sed 's/^/    /'
		exit 1
	}
	echo "ref_compare: SKIP — callgrind could not profile this run."
	sed -n '1,5p' "$T/vg.err" | sed 's/^/    /'
	exit 0
}

# Total instructions executed by the whole process.
#
# callgrind_annotate first, because it is what the rest of this repo parses and
# what a human would run by hand. Its column layout is not an interface anyone
# promised us, though — that is the rot cycles_check.sh's NO_SKIP guards exist
# for — and unlike cycles_check we do not need a per-symbol row, only the
# program total, which callgrind writes into its own output file in a documented
# format. So there is a fallback here that cycles_check cannot have. "totals:"
# and "summary:" carry one number per collected event and Ir is always the
# first, so field 2 is the instruction count.
ir_total() {
	_v=$("$CG_ANNOTATE" --threshold=0 "$1" 2>/dev/null \
		| grep -a 'PROGRAM TOTALS' | head -1 | tr -d ' ,' | grep -oE '^[0-9]+')
	[ -n "$_v" ] || _v=$(awk '/^totals:/ { print $2; exit }' "$1")
	[ -n "$_v" ] || _v=$(awk '/^summary:/ { print $2; exit }' "$1")
	echo "${_v:-0}"
}

# write() calls made by the whole process, which is the number that says whether
# this comparison is about the search or about printing.
#
# callgrind COMPRESSES names — a function is written "fn=(12) write" once and
# bare "fn=(12)" every time after — so the id->name table has to be resolved
# before anything can be matched, and it is fed by both fn= and cfn= lines
# because either may be where a name is first introduced. (cycles_check.sh
# learned this the same way, and got 0 until it did.)
#
# The callee name is matched EXACTLY, not by substring: stdio's internals are
# called _IO_do_write and _IO_file_write, and counting those as syscalls would
# roughly double a printf-using binary's total against a reference that writes
# directly. The @@GLIBC_2.2.5 version suffix is stripped first.
#
# writev counts too, and the column still says write(): a vectored write is the
# same trip into the kernel, and a reference that one day buffers its output
# through something that vectors would otherwise report zero syscalls — which
# reads as "the parse broke" and costs the honest comparison below. Today both
# sides use plain write(), measured: 725 calls each.
write_calls() {
	awk '
		function id(s,   p, q) { p = index(s, "("); q = index(s, ")");
			return (p && q) ? substr(s, p + 1, q - p - 1) : "" }
		function nm(s,   q) { q = index(s, ")");
			return (q && length(s) > q + 1) ? substr(s, q + 2) : "" }
		function base(n) { sub(/@@.*$/, "", n); return n }
		/^fn=/  { i = id($0); n = nm($0); if (n != "") fname[i] = n }
		/^cfn=/ { i = id($0); n = nm($0); if (n != "") fname[i] = n; cur = i }
		/^calls=/ {
			b = base(fname[cur])
			if (b == "write" || b == "__write" || b == "__libc_write" ||
				b == "writev" || b == "__writev") {
				split($0, a, "[= ]"); total += a[2]
			}
		}
		END { print total + 0 }
	' "$1"
}

profile "$T/cg.student" "$T/student"
profile "$T/cg.ref" "$ORACLE" bench "$FN"

IR_STU=$(ir_total "$T/cg.student")
IR_REF=$(ir_total "$T/cg.ref")
if [ "${IR_STU:-0}" -le 0 ] 2>/dev/null || [ "${IR_REF:-0}" -le 0 ] 2>/dev/null; then
	# Both extraction paths came back empty. If this fires for every exercise at
	# once, suspect the parsing above rather than the deliverables.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no instruction total could be read from the callgrind"
		echo "             output (student=$IR_STU reference=$IR_REF). Suspect the"
		echo "             parsing in ir_total(), not the exercise."
		exit 1
	}
	echo "ref_compare: SKIP — could not read an instruction total from callgrind."
	exit 0
fi
W_STU=$(write_calls "$T/cg.student")
W_REF=$(write_calls "$T/cg.ref")

# ---------------------------------------------------------------------------
# HOW MANY BYTES THE STUDENT ACTUALLY EMITTED — kind=output only, because it is
# the only kind that reports it and an unused run is an unused risk.
#
# Measured off the student's own binary rather than taken from --units or from
# the reference's output, for two reasons. The number is about THEM, and under
# NO_SKIP=1 the correctness gate above is deliberately not run, so the student's
# stream is not guaranteed to be the reference's stream at that moment; reading
# the byte count off ref.out would then print the reference's figure under the
# word "yours". And a constant passed in on the command line is a constant that
# can be wrong with nothing to notice — this one cannot.
#
# The run is plain (no callgrind) and costs microseconds. It happens AFTER the
# profiled run above, so a deliverable that never terminates has already hung
# the profiler and this line adds no hazard the layer did not already have.
# The exit status is ignored on purpose: judging correctness is the gate's job,
# and doing it twice in two places is how two places come to disagree.
# ---------------------------------------------------------------------------
BYTES_STU=""
if [ "$KIND" = "output" ]; then
	"$T/student" > "$T/stu.out" 2>/dev/null < /dev/null
	BYTES_STU=$(wc -c < "$T/stu.out" | tr -d ' ')
fi

# ---------------------------------------------------------------------------
# Report.
# ---------------------------------------------------------------------------
per_unit() {
	awk -v i="$1" -v u="$UNITS" 'BEGIN {
		v = i / u
		printf (v >= 100 ? "%.0f" : "%.1f"), v
	}'
}
show_calls() {
	# 0 means the parse found nothing, not that the process made no syscalls —
	# both sides print, so both must write. Say "?" rather than assert a zero
	# the interpretation below would then reason from.
	[ "${1:-0}" -gt 0 ] 2>/dev/null && echo "$1" || echo "?"
}
RATIO=$(awk -v s="$IR_STU" -v r="$IR_REF" 'BEGIN { printf "%.1f", s / r }')

echo "ref_compare: $LABEL against an optimised reference (both $OPT, stdout discarded)"
echo ""
printf '  %-26s %14s %14s %14s\n' "" "INSTRUCTIONS" "PER ${UNIT_NAME}" "write() CALLS"
printf '  %-26s %14s %14s %14s\n' "yours" "$IR_STU" "$(per_unit "$IR_STU")" "$(show_calls "$W_STU")"
printf '  %-26s %14s %14s %14s\n' "reference" "$IR_REF" "$(per_unit "$IR_REF")" "$(show_calls "$W_REF")"
printf '  %-26s %14s %14s\n' "ratio" "" "${RATIO}x"
echo ""
echo "  Counted over $UNITS ${UNIT_NAME}s. Instruction counts are deterministic —"
echo "  the only run-to-run movement is a few instructions of startup that depend"
echo "  on how big the environment is. Both figures include that startup: a fixed"
echo "  cost neither implementation chose, larger on the reference's side than on"
echo "  yours, so it can only pull the ratio towards 1.0 and never away from it."
echo ""

# ---------------------------------------------------------------------------
# The interpretation.
#
# The one thing this must not do is name the technique. "Same tree, same
# syscalls, the difference is in how each candidate is tested" tells a student
# exactly where to look and leaves the looking to them; the sentence that names
# the answer would end the exercise for them, which is precisely what AGENTS.md
# forbids and what makes this repo worth anything. Everything below is written
# to that line and stops at it. That holds for BOTH kinds: --kind output states
# what a syscall costs and what the floor is, and never once says what to do
# with those two facts, because the step between them is the exercise.
#
# The syscall counts also decide what can honestly be claimed. If both sides
# made the same number of write() calls, the kernel time callgrind cannot see is
# the same on both sides and the gap is genuinely about the search. If they did
# NOT, part of the gap is the cost of talking to the kernel more often, and
# saying otherwise would be a comfortable lie — so that case gets its own text.
#
# --kind search's wording assumes the job is a SEARCH ("the same tree", "each
# candidate"), which is true of the exercise this layer was written for and of
# any backtracking exercise it would plausibly be reused for. That is a real
# coupling and it is written down rather than hidden behind vaguer words,
# because vaguer words would cost the student the one concrete thing this layer
# has to offer. --kind output exists so that pointing this macro at an exercise
# with no search in it does not print those paragraphs at someone who would then
# go looking for a tree they never wrote. Any THIRD shape of exercise needs a
# third kind, written to whatever axis actually separates two implementations of
# it — not a fourth vague rewrite of these.
# ---------------------------------------------------------------------------
# same / differ / unknown — three cases, because "differ" and "could not be
# read" are not the same claim and only one of them is about the student.
IO_STATE=$(awk -v a="$W_STU" -v b="$W_REF" 'BEGIN {
	if (a <= 0 || b <= 0) { print "unknown"; exit }
	print (a == b) ? "same" : "differ" }')

# --- text both kinds need, written once ------------------------------------
#
# The single claim callgrind can never make for itself: it counts USER
# instructions, so every microsecond spent on the far side of a mode switch is
# missing from the column above. Whenever the two sides do not make the same
# number of syscalls, that missing time is not equal on the two sides, and the
# printed ratio is therefore a LOWER bound on the real difference rather than an
# estimate of it. Both kinds have to say this and neither may say it slightly
# differently, so it lives here. Each caller writes its own opening line, because
# what the student's count is being weighed against is not the same thing in the
# two kinds — the reference in one, a floor of one call in the other — and the
# opening clause is where that difference belongs.
kernel_cost_is_invisible() {
	echo "  is the cost of entering the kernel more often, which callgrind cannot"
	echo "  even see — so the ratio above UNDERSTATES what it costs in wall time."
}

# The last word, identical in both kinds but for one clause: what the student
# might go and be curious about. Everything else — that this is never a failure,
# that the door is //oracle, and that the better conversation is with the peer on
# their right rather than with a tool — is the same sentence whatever the
# exercise was, and AGENTS.md §1 is why it is the last thing on the page.
closing_door() {
	# $1: the thing they might be curious about, as a noun phrase, continuing
	#     "If you are curious what ___ would look like".
	echo "  Nothing here is a failure and this layer will never fail you for it: your"
	echo "  function is correct, which is what the subject asked for. This is a door,"
	printf '  not a verdict. If you are curious what %s\n' "$1"
	echo "  would look like, that is a fine thing to work out on paper — or to argue"
	echo "  about with the peer on your right, which is where 42 would rather you"
	echo "  took it than to any tool that would simply tell you."
	# Name the door, since it exists and hiding it helps nobody. The reference is
	# Rust on purpose: it can be read but not pasted, so getting it into C means
	# understanding every step and then rebuilding it under constraints Rust does
	# not have -- which is the exercise, not a way around it. See AGENTS.md,
	# "The oracle is a legitimate door".
	echo ""
	echo "  The reference itself is in //oracle (Rust). Reading it is allowed and"
	echo "  will not hand you anything you can paste: getting it into C, under the"
	echo "  Norm, is the same work the exercise is asking for either way."
}

# ---------------------------------------------------------------------------
# WHAT ONE write() COSTS, ON THIS MACHINE, RIGHT NOW — used by --kind output.
#
# The output report has to explain why a syscall is expensive, and this repo's
# own rule for that is to measure the axis rather than assert it (AGENTS.md §2,
# "Better is a question, not a fact": show the number instead of the claim). A
# constant copied from the machine this was written on would be exactly the
# assertion that rule is about — syscall cost moves by more than an order of
# magnitude with the kernel, the CPU and whichever speculative-execution
# mitigations are switched on — so it is measured here, on the machine the
# student is actually sitting at.
#
# BOTH halves are deliberately biased towards making the difference look SMALL:
#   * the destination is /dev/null, the cheapest write() that exists; a pipe, a
#     file or a terminal all cost strictly more, so the figure is a floor on what
#     one call costs rather than an estimate of it;
#   * the memory figure is taken one byte at a time through a volatile pointer,
#     which is the slowest legal way to put a byte somewhere (it blocks both
#     vectorisation and any reordering), so it is an upper bound.
# Erring towards "the gap is smaller than this" is the only direction a number in
# a report that never gates is allowed to err in — the same reasoning as the
# startup asymmetry in the header.
#
# The single-call run is subtracted from the many-call run before dividing, so
# the answer is the MARGINAL cost of a call: the clock reads, the loop and the
# one unavoidable call all cancel out and only the extra trips remain.
#
# BOTH timed runs carry ONE BYTE PER CALL and differ only in how many calls they
# make. That is not an accident of the measurement, it is a constraint on this
# file. Ten lines below the report refuses to name the technique that closes the
# gap, because the step from "a call is expensive and the floor is 1" to a change
# in the student's own file is the whole of what these exercises teach. A probe
# that handed a filled buffer to the kernel in a single call would be that step,
# written out in C, in a file that ships to every student who clones this
# repo — the report's silence upstairs and a worked example
# downstairs, in the same file. Measuring one extra one-byte trip answers exactly
# the question the prose asks ("you pay for the trip once per call regardless of
# how few bytes it carried") and shows nothing else. Verified equivalent: against
# the N-byte-baseline version this replaced, five paired runs agreed to within
# 1%, and both bracket 122ns/call measured end-to-end on two whole processes
# emitting identical bytes. Nothing was traded for the silence.
#
# One consequence, named because it is a real one: with a one-byte baseline the
# subtraction leaves (N-1) calls AND (N-1) bytes of kernel copy, where an N-byte
# baseline cancelled the bytes exactly. So the figure carries the cost of a
# single byte's copy inside the kernel — sub-nanosecond against ~120ns, i.e.
# under 0.3%, and the only term in this whole routine that biases the number
# HIGH rather than low. It is far below the run-to-run spread measured above and
# is recorded here rather than hidden.
#
# Three repetitions, best-of: a scheduler preemption or a migration to a cold
# core inflates a sample and never deflates one, so the minimum is the closest
# thing to an uncontended measurement available without root.
#
# Prints "<ns per write> <ns per byte store>" on success and NOTHING on any
# failure — no compiler, no clock, an ordering that physics forbids. The report
# then drops the sentence and keeps everything else. This must never gate and
# never skip the layer: an unmeasurable machine is not a student's problem.
# ---------------------------------------------------------------------------
syscall_cost() {
	cat > "$T/probe.c" <<'PROBE_EOF'
#include <fcntl.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

#define N 20000
#define STORE_REPS 100

static long	now_ns(void)
{
	struct timespec	t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return ((long)t.tv_sec * 1000000000L + (long)t.tv_nsec);
}

int	main(void)
{
	static char		buf[N];
	volatile char	*v = buf;
	long			one = -1, many = -1, store = -1, d, t0;
	int				fd, rep, i, j;

	fd = open("/dev/null", O_WRONLY);
	if (fd < 0)
		return (1);
	for (rep = 0; rep < 3; rep++)
	{
		t0 = now_ns();
		if (write(fd, (char *)buf, 1) != 1)
			return (1);
		d = now_ns() - t0;
		if (one < 0 || d < one)
			one = d;
		t0 = now_ns();
		for (i = 0; i < N; i++)
			if (write(fd, (char *)buf + i, 1) != 1)
				return (1);
		d = now_ns() - t0;
		if (many < 0 || d < many)
			many = d;
		t0 = now_ns();
		for (j = 0; j < STORE_REPS; j++)
			for (i = 0; i < N; i++)
				v[i] = (char)i;
		d = now_ns() - t0;
		if (store < 0 || d < store)
			store = d;
	}
	printf("%d %ld %ld %ld %ld\n", N, one, many, (long)N * STORE_REPS, store);
	return (0);
}
PROBE_EOF
	# -O2 to match how everything else here is built; the volatile above is what
	# keeps the store loop from being optimised into nothing at that level.
	cc -O2 -w "$T/probe.c" -o "$T/probe" 2>/dev/null || return 0
	"$T/probe" > "$T/probe.out" 2>/dev/null < /dev/null || return 0
	awk '{
		n = $1; one = $2; many = $3; stores = $4; store_ns = $5
		if (n < 2 || stores < 1) exit
		w = (many - one) / (n - 1)
		s = store_ns / stores
		# Sanity, not tuning. A "syscall" that measured cheaper than a memory
		# store, or dearer than 100us, is a preempted run or a clock this code
		# does not understand — not a measurement. Print nothing; a dropped
		# sentence is honest and a made-up number is not.
		if (w <= 0 || w > 100000 || s <= 0 || w <= s) exit
		printf "%.0f %.2f\n", w, s
	}' "$T/probe.out"
}

# ---------------------------------------------------------------------------
# --kind output: the exercise emits a fixed stream of bytes, so the axis that
# separates two implementations is HOW MANY TIMES they cross into the kernel,
# and nothing else. The instruction ratio is not merely secondary here, it is
# actively misleading: c-00 ex01 runs ~136k instructions of which ~135k is
# process startup, against a Rust reference whose startup is ~380k, so the
# printed ratio comes out BELOW 1.0 and would read as "you beat the reference".
# That is why this block does not fall through the ratio<1.5 early exit below —
# it would fire on every one of these exercises and print "nothing to chase"
# over a program making 9899 syscalls to emit 34648 bytes.
#
# It reports the count, the floor and the price of a call. It does not say what
# to do about them; the step from "a call costs 200ns and one call would do" to
# a change in their file is the whole of what this exercise teaches, and handing
# it over would be AGENTS.md §0's do-not-write zone in prose form.
# ---------------------------------------------------------------------------
if [ "$KIND" = "output" ]; then
	if [ "${W_STU:-0}" -le 0 ] 2>/dev/null; then
		echo "  The write() count could not be read out of the profile — and for this"
		echo "  exercise that count IS the measurement, since nearly all of the"
		echo "  instructions above are process startup. Nothing further can be said"
		echo "  honestly, so nothing further is said. Suspect write_calls(), not you."
		exit 0
	fi

	# Divisor is W_STU, which the guard above has just established is positive.
	BYTES_PER_CALL=$(awk -v b="${BYTES_STU:-0}" -v c="$W_STU" 'BEGIN { printf "%.2f", b / c }')

	echo "  This exercise's whole job is to emit a fixed stream of bytes. There is no"
	echo "  search here and no algorithm to be off by a factor on, so the instruction"
	echo "  column above is NOT the lesson: at this size both totals are mostly"
	echo "  process startup — the loader, a language runtime, reaching main() — and"
	echo "  the reference's runtime is a larger one than yours. That ratio is very"
	echo "  nearly a statement about two startups. The measurement that is actually"
	echo "  about the two implementations is this one:"
	echo ""
	printf '  %-26s %14s\n' "bytes emitted" "${BYTES_STU:-?}"
	printf '  %-26s %14s\n' "write() calls" "$W_STU"
	printf '  %-26s %14s\n' "bytes per call" "$BYTES_PER_CALL"
	printf '  %-26s %14s\n' "floor" "1"
	printf '  %-26s %14s\n' "yours, against that floor" "${W_STU}x"
	echo ""

	# At the floor already. This is a legitimate place to be — nothing in the
	# subject forbids it and nothing here should imply the student is missing
	# something when they are not. Say so and stop: a lecture delivered to
	# someone who has already done the thing is how a report loses its reader.
	if [ "$W_STU" -eq 1 ]; then
		echo "  One call for the whole stream: you are at the floor. There is nothing"
		echo "  to chase here. Read the number and move on."
		exit 0
	fi

	if [ "${W_REF:-0}" = "1" ]; then
		echo "  The floor is 1, and it is not hypothetical: the reference hands this"
		echo "  entire stream to the kernel in a single write() call."
	else
		# The reference is contracted to make exactly one call. If the table above
		# says otherwise, the floor is still 1 — it is a property of the job, not
		# of the reference — but this must not claim the reference reached it while
		# the table says it did not. A reader who catches a report contradicting
		# itself stops believing the rest of it, and they are right to.
		echo "  The floor is 1: one write() call carrying the whole stream. (The"
		echo "  reference is contracted to make exactly that one call and the table"
		echo "  above says it made $(show_calls "$W_REF") — that is a harness discrepancy, not yours.)"
	fi
	echo ""

	echo "  A write() is not a function call that happens to be slow. It is a round"
	echo "  trip out of your program: a mode switch into the kernel, the kernel's"
	echo "  own work on the file descriptor and its lock, and a switch back. The"
	echo "  bytes are the cheap part of it. The trip is not, and you pay for the"
	echo "  trip once per call regardless of how few bytes it carried."
	echo ""

	COST=$(syscall_cost)
	if [ -n "$COST" ]; then
		PER_WRITE_NS=${COST% *}
		PER_STORE_NS=${COST#* }
		COST_FACTOR=$(awk -v w="$PER_WRITE_NS" -v s="$PER_STORE_NS" \
			'BEGIN { printf "%.0f", w / s }')
		ABOVE_FLOOR=$((W_STU - 1))
		EXTRA_US=$(awk -v n="$ABOVE_FLOOR" -v w="$PER_WRITE_NS" \
			'BEGIN { printf "%.0f", n * w / 1000 }')
		echo "  Measured on this machine, moments ago: one write() of one byte to"
		echo "  /dev/null costs about ${PER_WRITE_NS}ns, while putting one byte into memory"
		echo "  costs about ${PER_STORE_NS}ns. A factor of roughly ${COST_FACTOR}, for the same byte."
		echo "  /dev/null is the cheapest destination that exists and the memory"
		echo "  figure was taken one byte at a time, the slowest way to take it, so"
		echo "  both ends of that comparison are biased towards making it look"
		echo "  smaller than it really is."
		echo ""
		echo "  At ${PER_WRITE_NS}ns a call, the $ABOVE_FLOOR calls you make above the floor come to"
		echo "  about ${EXTRA_US}us of wall clock — spent, on this run, before your program"
		echo "  got to do anything else."
	else
		echo "  (The price of a call could not be measured on this machine just now,"
		echo "  so no figure is quoted for it. The count above stands on its own.)"
	fi
	echo ""

	printf '  Your %s write() calls against a floor of 1: the whole of that difference\n' \
		"$W_STU"
	kernel_cost_is_invisible
	echo ""
	closing_door "a version that reached that floor"
	exit 0
fi

if awk -v r="$RATIO" 'BEGIN { exit !(r < 1.5) }'; then
	echo "  Your implementation is in the same class as the reference. There is"
	echo "  nothing to chase here — this is what a well-judged solution to this"
	echo "  exercise costs. Read the number and move on."
	exit 0
fi

echo "  Yours does about ${RATIO}x the work of the reference for the same answer."
echo ""

# First, what the syscall counts license us to say — and only that.
if [ "$IO_STATE" = "same" ]; then
	echo "  Both made exactly $W_STU write() calls, so none of this gap is printing;"
	echo "  and both were measured from an optimised native build, so none of it is"
	echo "  the language either. It is all work done between the syscalls."
elif [ "$IO_STATE" = "differ" ]; then
	printf '  Your %s write() calls against the reference'"'"'s %s: part of this gap\n' \
		"$W_STU" "$W_REF"
	kernel_cost_is_invisible
else
	echo "  The write() counts could not be read out of the profile, so how much of"
	echo "  this gap is printing cannot be confirmed here."
fi
echo ""

# Then where the rest of it lives — banded, because the honest answer depends on
# the size. A student walking the SAME tree with a costlier per-candidate test
# lands in single or low double digits (measured: 6.8x here, 10.7x on the
# prototype). A student walking a much larger tree — generating arrangements and
# filtering them afterwards, say — lands two orders of magnitude out, and
# telling THEM to look at the price of one step would point them at the smaller
# of their two problems. So above the band the clue changes to match.
if awk -v r="$RATIO" 'BEGIN { exit !(r < 25) }'; then
	echo "  A gap this size is not about WHICH boards get considered — a search"
	echo "  that ruled out fewer of them would show a far bigger number than this."
	echo "  You and the reference walk essentially the same tree. What differs is"
	echo "  the price of ONE step: how each candidate is tested before it is"
	echo "  accepted. You ask that question one way and the reference asks it"
	echo "  another, and pays less every single time — on a search this size, that"
	echo "  question is asked an enormous number of times."
else
	echo "  A gap this large is more than the price of one step can account for."
	echo "  Look first at how many candidates you consider at all: at what moment"
	echo "  a placement that cannot possibly lead to a full board stops being"
	echo "  followed any further. Then, second, at what testing one candidate"
	echo "  costs you."
fi
echo ""
closing_door "a cheaper version of that test"
exit 0
