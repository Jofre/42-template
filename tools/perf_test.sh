#!/bin/sh
# Performance layer (tag "perf") — SCAFFOLDING, informative by default.
#
# ---------------------------------------------------------------------------
# WHAT THIS IS FOR
#
# Every other layer asks "is the answer right?". None asks "did you get there in
# a sane amount of work?", and the Piscine is full of exercises where a correct
# answer can be arrived at absurdly slowly: a primality test that trial-divides
# to nb instead of stopping early, a strlen called inside its own loop condition
# so an O(n) walk becomes O(n^2), a list length recomputed per element, a sort
# that rebuilds the array every swap. Those pass every existing layer.
#
# This layer reports that cost. It is deliberately NOT a pass/fail style gate:
# being 20x slower than a reference is a perfectly acceptable place for a
# student to be, and failing them for it would teach the wrong lesson.
#
# WHEN IT FAILS -- this repo's own lines, at the `complete` level, listed in
# docs/testing.md ("The two cost layers") and in the banner below; nothing else
# here exits 1:
#
#   * the time over the CASE COUNT grows at n^GATE_EXPONENT (2.6) or steeper,
#     and a second measurement from scratch agrees;
#   * in ratio mode, GATE_SLOWDOWN (5000) times the reference's time, or
#     GATE_MEMORY (200) times its peak memory;
#   * a measured run that crashes (killed by a signal): a crash fails at every
#     level (docs/reference.md, Run contract).
#
# A run that does not finish within its limit is NOT one of them: a fixed wall
# clock establishes neither an exponent nor a ratio. The sizes are halved and
# measured again, and if even the smallest does not finish, that is reported
# and the test passes -- unless NO_SKIP=1, the maintainer's sweep, under which
# a layer that measured nothing is red. The LENGTH series (below) is reported
# and never gated: how one call grows with its input is the algorithm, and a
# gate on it would recommend one.
#
# ---------------------------------------------------------------------------
# TWO MODES
#
# 1. SCALING (works today, needs no reference). Run the student's own harness
#    over N, 2N and 4N cases and fit the growth exponent p in cost ~ n^p. A
#    linear function lands near p=1; an accidental quadratic lands near p=2.
#    This is the pedagogically interesting number and it needs no baseline at
#    all, because the student is compared only against themselves.
#
# 2. RATIO (needs --baseline-bin). Time the student against a reference binary
#    replaying the SAME corpus, and report the slowdown and memory multiples.
#    NOTE: the //oracle binary cannot be used as that baseline as it stands —
#    `oracle <fn> <seed> <count>` GENERATES cases (seeded RNG, hex encoding,
#    formatting, ~90% of a diff test's cost) rather than replaying them, so
#    timing it measures the generator, not the reference implementation. Adding
#    `oracle bench <fn>` EXISTS now: it reads a corpus on stdin and computes the
#    reference answers without generating or printing them, which is the shape a
#    baseline needs. Pass it here as --baseline-bin and ratio mode lights up. In
#    the meantime this script reports scaling only and says so.
#
# ---------------------------------------------------------------------------
# 3. LENGTH (needs --length-oracle-fn). SCALING varies the number of cases,
#    each one a small input, so it measures how many calls add up -- a cubic
#    sort over arrays of a dozen ints is linear in how many arrays there are.
#    This varies the LENGTH of one input instead: a fixed number of cases at
#    lengths L, 2L and 4L, from an oracle arm that takes the length
#    (`oracle <arm> <seed> <cases> <length>`), replayed through a harness that
#    reads a line of any length (--length-bin). The fitted exponent is how
#    one call's cost grows with its input. Reported, never gated.
#
# Usage:
#   perf_test.sh --runner PATH --student-bin PATH --oracle PATH --oracle-fn FN
#                [--seed N] [--count N] [--baseline-bin PATH]
#                [--gate-exponent F] [--gate-slowdown F] [--gate-memory F]
#                [--length-oracle-fn FN --length-bin PATH
#                 [--length-base L] [--length-cases K]]
#                [--label NAME]
#
# Exit status: 0 unless a GATE threshold is exceeded or a run crashed (see
# "WHEN IT FAILS" above); 2 when the harness itself could not run.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "perf_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cmp cut mktemp rm sed

# The shared runner helpers -- time budget, exiting signal traps, how a run
# ended, excerpts, hints -- written once in tools/runner_lib.sh.
RL_NAME=perf_test
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "perf_test.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool GATE_DIFFER -- tools/diff_output.sh, the output gate, which keeps this test's budget (RL_DEADLINE)
# conventions: harness tool ORACLE -- the Rust reference (//oracle), which writes the corpus
# conventions: harness tool RUNNER -- tools/perf_run, which runs the student's harness with --timeout from rl_tmo and reports how it ended

RUNNER=""
STUDENT=""
BASELINE=""
BASELINE_ORACLE=0
ORACLE=""
FN=""
SEED="1"
COUNT="200000"
LABEL=""
LEN_FN=""
LEN_BIN=""
LEN_BASE="250"
LEN_CASES="20"

# ---- correctness gate (see the "PERFORMANCE IS LAST" note below) ------------
GATE_DIFFER=""
GATE_BIN=""
GATE_EXPECTED=""
GATE_ASAN_BIN=""
GATE_PASS=""
GATE_COUNT="4000"

# Gate thresholds. Chosen to be far outside "slow but reasonable": p=2.6 is well
# past a clean quadratic, so an honest O(n^2) still only warns; 5000x slowdown
# and 200x memory are the "this looks like it would break something" band the
# layer exists to catch. Override per exercise from the BUILD file.
GATE_EXPONENT="2.6"
GATE_SLOWDOWN="5000"
GATE_MEMORY="200"

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "perf_test.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--runner) need "$1" "$#"; RUNNER="$2"; shift 2 ;;
		--student-bin) need "$1" "$#"; STUDENT="$2"; shift 2 ;;
		--baseline-bin) need "$1" "$#"; BASELINE="$2"; shift 2 ;;
		--baseline-oracle) BASELINE_ORACLE=1; shift ;;
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--oracle-fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--seed) need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--length-oracle-fn) need "$1" "$#"; LEN_FN="$2"; shift 2 ;;
		--length-bin) need "$1" "$#"; LEN_BIN="$2"; shift 2 ;;
		--length-base) need "$1" "$#"; LEN_BASE="$2"; shift 2 ;;
		--length-cases) need "$1" "$#"; LEN_CASES="$2"; shift 2 ;;
		--gate-exponent) need "$1" "$#"; GATE_EXPONENT="$2"; shift 2 ;;
		--gate-slowdown) need "$1" "$#"; GATE_SLOWDOWN="$2"; shift 2 ;;
		--gate-memory) need "$1" "$#"; GATE_MEMORY="$2"; shift 2 ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-asan-bin) need "$1" "$#"; GATE_ASAN_BIN="$2"; shift 2 ;;
		--gate-count) need "$1" "$#"; GATE_COUNT="$2"; shift 2 ;;
		--gate-stdin) need "$1" "$#"; rl_list_add GATE_PASS --stdin "$2"; shift 2 ;;
		--gate-sanitize) rl_list_add GATE_PASS --sanitize; shift ;;
		--gate-labeled) rl_list_add GATE_PASS --labeled; shift ;;
		*) echo "perf_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$RUNNER" ] && [ -n "$STUDENT" ] && [ -n "$ORACLE" ] && [ -n "$FN" ] || {
	echo "perf_test.sh: need --runner, --student-bin, --oracle and --oracle-fn" >&2
	exit 2
}
if [ -n "$LEN_FN" ] && [ -z "$LEN_BIN" ]; then
	echo "perf_test.sh: --length-oracle-fn needs --length-bin, the harness that reads its lines" >&2
	exit 2
fi
case "$LEN_BASE:$LEN_CASES" in
	*[!0-9:]* | :* | *:) echo "perf_test.sh: --length-base and --length-cases take whole numbers" >&2; exit 2 ;;
esac

T=$(mktemp -d)
rl_traps 'rm -rf "$T"'

# One measurement: echoes "<wall_ms> <cpu_ms> <rss_kb> <exit> <limit_s>
# <clamped>". Takes a corpus and then a COMMAND (possibly with arguments, e.g.
# `oracle bench c05_is_prime`). Each run is bounded by perf_run's own alarm:
# PERF_TIMEOUT of the run's own time -- the wait for a CPU on a busy machine
# given back, up to what the test has left (RL_CEIL; tools/runqueue.h) --
# or what is left of this test's limit if that is less (rl_tmo),
# and the limit it actually got travels with the numbers -- measure runs in a
# subshell, so the caller cannot read RL_TMO itself. No time left to start at
# all is the exit field "start". A run the ceiling stopped (perf_run's
# "ceiling") used less than its own limit: it is a "timeout" whose limit is
# the ceiling, clamped -- what was left of the test, as rl_classify reads
# exit_status's "ceiling Q" -- never "did not finish within 25s
# (PERF_TIMEOUT)", which it did not use.
measure() {
	_corpus="$1"; shift
	if ! rl_tmo "${PERF_TIMEOUT:-25}"; then
		echo "0 0 0 start 0 1"; return
	fi
	_out=$("$RUNNER" --stdin "$_corpus" --timeout "$RL_TMO" --ceiling "${RL_CEIL:-$RL_TMO}" -- "$@" 2>/dev/null) || {
		echo "0 0 0 error $RL_TMO $RL_CLAMPED"; return
	}
	echo "$_out" | sed -n \
		's/^ms=\([0-9]*\) cpums=\([0-9]*\) rss=\([0-9]*\) exit=\([a-z0-9]*\)$/\1 \2 \3 \4/p' |
		awk -v t="$RL_TMO" -v c="$RL_CLAMPED" -v ceil="${RL_CEIL:-$RL_TMO}" '
			$4 == "ceiling" { $4 = "timeout"; print $0, ceil, 1; next }
			{ print $0, t, c }'
}

# not_measured WHY -- the report for a measurement that could not be taken
# because the time ran out: a size that did not finish within its limit even
# after halving, or no time left in the test to start one. A wall clock
# establishes neither a growth exponent nor a ratio, so this is never one of the
# gates (the header's "WHEN IT FAILS"): it is reported and the test passes. It
# used to fail outright after a fixed 25s, a bar far lower than the 5000x the
# same script calls the line, and a correct ft_sqrt that took 19s on a quiet
# machine went red on a busy one (finding 043). Under NO_SKIP=1 a layer that
# measured nothing is red, as everywhere.
not_measured() {
	echo ""
	echo "  NOT MEASURED: $1"
	echo "  A time limit establishes neither a growth exponent nor a ratio, so this"
	echo "  is reported, not failed: none of the lines this layer fails on was"
	echo "  measured."
	if [ "${NO_SKIP:-0}" = 1 ]; then
		echo "  NO_SKIP set: this layer measured nothing, which the sweep reports red."
		exit 1
	fi
	exit 0
}

# limit_note LIMIT CLAMPED -- what the limit a run got was.
limit_note() {
	if [ "$2" = 1 ]; then
		echo "${1}s (what was left of $RL_OVERRUN_MARK, TEST_TIMEOUT=${TEST_TIMEOUT:-?}s)"
	else
		echo "${1}s (PERF_TIMEOUT)"
	fi
}

# out_of_time WHAT -- no time was left to start WHAT.
out_of_time() {
	not_measured "the test's own time ran out before $1 could start."
}

# How many times to measure each size, keeping the FASTEST sample.
#
# The growth exponent used to be fitted from one sample at each of two sizes,
# which made "how busy was this machine for those two milliseconds" a direct
# input to a verdict a student is shown. It is dual-severity, which is what makes
# it worth the extra runs: noise on the LAST point inflates the exponent and reds
# honest code, while the same noise on the FIRST point deflates it -- a genuinely
# quadratic function whose first sample landed 3.7x high measures p = 1.05 and is
# reported as "linear-ish, nothing to worry about".
#
# Minimum rather than mean or median: interference can only ever make a run
# SLOWER. There is no mechanism by which the machine hands a function time it did
# not spend, so the smallest of N samples is the closest any of them got to the
# work itself, and averaging just mixes the clean sample back together with the
# dirty ones.
PERF_REPEATS="${PERF_REPEATS:-3}"

# ...but only while a sample is SHORT. What the repeats guard against is a
# millisecond-scale sample that one scheduling accident doubled; the cost
# is the fitted figure, CPU time, which counts no time the run spent
# descheduled. A sample of two CPU-seconds or more has nothing a second
# run would correct, and three of them cost a correct but slow answer (C 05
# ex05's ft_sqrt: 5, 10 and 20 s) two thirds of its test's time for
# nothing -- on a busy machine, the time the test ran out of (finding 066).
PERF_REPEAT_MS=2000

measure_best() {
	_best=""
	_i=0
	while [ "$_i" -lt "$PERF_REPEATS" ]; do
		_s=$(measure "$@")
		# A run that did not end normally is not a slow sample -- a run the
		# time limit stopped (the sizes are halved), or a crash (a finding).
		# Return it immediately rather than letting a faster sibling run take
		# the minimum and hide it.
		if [ "$(printf '%s\n' "$_s" | cut -d' ' -f4)" != 0 ]; then
			echo "$_s"
			return
		fi
		_best=$(printf '%s\n%s\n' "$_best" "$_s" | awk '
			NF == 0 { next }
			{ if (best == "" || $2 < bestcpu) { best = $0; bestcpu = $2 } }
			END { print best }')
		_i=$((_i + 1))
		[ "$(printf '%s\n' "$_s" | cut -d' ' -f2)" -lt "$PERF_REPEAT_MS" ] || break
	done
	echo "$_best"
}

# ---------------------------------------------------------------------------
# PERFORMANCE IS LAST.
#
# There is an order to what is worth a student's attention, and it is not the
# order the test names happen to sort in. Thinking about how FAST a function is
# while it still reads out of bounds is wasted effort, and thinking about out-of-
# bounds reads while it does not yet produce the right answer is wasted effort
# too. So this layer refuses to say anything until, in order:
#
#   1. the exercise's own output fixture passes   (is the answer right at all?)
#   2. the differential corpus agrees             (is it right on inputs you
#                                                  did not hand-pick?)
#   3. the ASan/UBSan build survives that corpus  (is it memory-safe?)
#
# and only then measures cost. When a stage is not green the layer SKIPs (exit
# 0) naming the stage, so the student's attention stays on the one red test that
# matters rather than being split across a performance report they cannot act on
# yet. This mirrors tools/ilp32_test.sh, which skips for the same reason.
#
# A false SKIP here is cheap in a way it would not be for a correctness layer:
# this layer is informative, so the worst case is a report arriving one fix
# later than it could have.
# ---------------------------------------------------------------------------
# NO_SKIP=1 forces measurement even while correctness is red (see rust_diff.sh).
GATES_FORCED=0

skip_gate() {
	if [ "${NO_SKIP:-0}" = "1" ]; then
		echo "perf_test: NO_SKIP set — measuring anyway despite: $1"
		# Remembered, because the summary below used to announce that output,
		# differential and memory-safety were "all green for this exercise"
		# directly underneath the lines saying they were not. Under NO_SKIP the
		# gates are forced open, which is the opposite of them having passed.
		GATES_FORCED=1
		return 0
	fi
	echo "perf_test: SKIP — $1"
	echo ""
	echo "  Performance is the last thing worth your attention, and only once the"
	echo "  answer is right and the memory access is safe. There is nothing here"
	echo "  you could act on yet, so this layer stays quiet and will start"
	echo "  measuring as soon as that test is green."
	exit 0
}

# A corpus the reference could not produce is OUR defect, not a state of the
# exercise: every gate above describes something the student can go and fix,
# this one means fn=$FN names nothing or the oracle is broken. It still skips by
# default, because this layer is informative and must not block anyone on a
# harness bug — but NO_SKIP=1 turns it red, so the forced sweep can find a layer
# that measured nothing and said nothing. Same shape as cycles_check.sh.
# An oracle arm can also exit 0 having printed NOTHING -- an fn name the
# dispatcher did not recognise, a generator that returned early. The file then
# exists, the command succeeded, and every measurement below is of a program fed
# an empty stdin: a real timing of no work at all, which would be reported as a
# splendid result. rust_diff.sh guards the same hole with MIN_DIFF_CASES; this is
# the same guard in the place that measures rather than compares.
corpus_ok() {
	[ -s "$1" ] && return 0
	echo "  perf_test: the reference produced an EMPTY corpus for fn=$FN."
	echo "  Measuring a program on no input at all would report a fast result for"
	echo "  work that never happened, so nothing is measured."
	return 1
}

skip_corpus() {
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "  NO_SKIP set: the reference produced no corpus for fn=$FN, so this"
		echo "  layer measured nothing. That is a harness bug, not an exercise state."
		rl_excerpt "$T/oerr" 3 reference-stderr.txt
		exit 1
	}
	echo "  perf_test: SKIP — the reference could not generate a corpus (fn=$FN)"
	rl_excerpt "$T/oerr" 3 reference-stderr.txt
	exit 0
}

# --- stage 1: does it produce the right output at all? ---
if [ -n "$GATE_DIFFER" ] && [ -n "$GATE_BIN" ] && [ -n "$GATE_EXPECTED" ]; then
	# GATE_PASS is one word per line (runner_lib.sh, LISTS OF WORDS).
	rl_split_on
	# shellcheck disable=SC2086
	sh "$GATE_DIFFER" --bin "$GATE_BIN" --expected "$GATE_EXPECTED" \
			$GATE_PASS >/dev/null 2>&1
	_gate_rc=$?
	rl_split_off
	if [ "$_gate_rc" -ne 0 ]; then
		skip_gate "the exercise's own output fixture is not passing yet."
	fi
fi

# --- stage 2: does it agree with the reference on inputs it did not choose? ---
# A sample of the corpus, GATE_COUNT cases, bounded like every run of student
# code here (rl_tmo). A run that never ends is not "diverges": it is named.
if "$ORACLE" "$FN" "$SEED" "$GATE_COUNT" > "$T/gate_corpus" 2>/dev/null; then
	if [ -s "$T/gate_corpus" ]; then
		rl_tmo "${PERF_TIMEOUT:-25}" || out_of_time "the $GATE_COUNT-case correctness sample"
		rl_run "$STUDENT" < "$T/gate_corpus" > "$T/gate_out" 2>/dev/null
		rl_classify "$?"
		if [ "$RL_CAUSE" = timeout ]; then
			skip_gate "the $GATE_COUNT-case correctness sample did not finish within ${RL_TMO}s."
		elif [ "$RL_CAUSE" != ok ] && [ "$RL_CAUSE" != "exit" ]; then
			skip_gate "the $GATE_COUNT-case correctness sample $RL_WHY."
		elif ! cmp -s "$T/gate_corpus" "$T/gate_out"; then
			skip_gate "the differential layer still diverges from the reference."
		fi
	fi
fi

# --- stage 3: is it memory-safe over that same corpus? ---
if [ -n "$GATE_ASAN_BIN" ] && [ -s "$T/gate_corpus" ]; then
	rl_tmo "${PERF_TIMEOUT:-25}" || out_of_time "the sanitizer run of the correctness sample"
	# The sanitizers' options, set once for every runner (rl_sanitizers,
	# tools/runner_lib.sh), the caller's keys last so they win. No symbolizer:
	# this run's report is never shown, only whether there was one.
	# conventions: shows no sanitizer report -- a gate: a red one skips this layer, and the diff_asan target says why
	if ! (
		rl_sanitizers "$T/sym"
		rl_run "$GATE_ASAN_BIN" < "$T/gate_corpus" > /dev/null 2>&1
	); then
		skip_gate "the ASan/UBSan build reports a memory or UB error, or did not finish."
	fi
fi

# A PROGRAM THAT DID NOT BUILD is a stand-in script that says why (see
# tools/standin.sh). Checked after the gate: a red gate has already skipped
# this layer, and past a green one -- or one NO_SKIP=1 forced open -- a
# stand-in is a failure, told in the compiler's words rather than as a
# report about a program that does not exist.
case "$0" in */*) _sl_dir=${0%/*} ;; *) _sl_dir=. ;; esac
for _sl in "$_sl_dir/standin.sh" \
	"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
	[ -f "$_sl" ] && break
done
[ -f "$_sl" ] || { echo "perf_test.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
standin_check perf_test "$STUDENT" fail "${LABEL:-the program}"
# The length harness is built from the same files, so it is a stand-in when
# they do not build -- and when they do, it is still a binary of its own that
# can fail to, and it would otherwise end as "the length harness returned 1",
# a harness fault, where a build verdict belongs (_STANDIN_RUNNERS: every
# program this runner is handed is checked).
[ -z "$LEN_BIN" ] || standin_check perf_test "$LEN_BIN" fail "${LABEL:-the program}'s length harness"

echo "perf_test: ${LABEL:-$FN} (seed=$SEED)"
if [ "$GATES_FORCED" = 1 ]; then
	echo "  NO_SKIP is set, so the correctness gates above were FORCED OPEN rather"
	echo "  than passed. The numbers below are real measurements of code that does"
	echo "  not yet do the right thing, which makes them a curiosity and not"
	echo "  something to act on. Fix the red layer first."
else
	echo "  Correctness first: the output fixture, and a $GATE_COUNT-case sample of the"
	echo "  differential corpus with and without the sanitizers, are all green, so"
	echo "  cost is now worth looking at."
fi
echo ""
echo "  NOTE: this layer REPORTS cost so you can think about it. It fails in"
echo "        three cases only, this repo's own lines at the complete level:"
echo "        time over the case count growing at n^$GATE_EXPONENT or steeper (measured"
echo "        twice); against the reference, ${GATE_SLOWDOWN}x its time or ${GATE_MEMORY}x its"
echo "        peak memory; and a run that crashes. Being several times slower"
echo "        than a reference is fine, and a run too slow to finish is reported."
echo ""

# ---------------------------------------------------------------- scaling mode
N1=$((COUNT / 4))
N2=$((COUNT / 2))
N3=$COUNT
[ "$N1" -ge 1000 ] || N1=1000
[ "$N2" -gt "$N1" ] || N2=$((N1 * 2))
[ "$N3" -gt "$N2" ] || N3=$((N2 * 2))
# How far the sizes may be halved when one does not finish within its limit.
PERF_MIN_CASES="${PERF_MIN_CASES:-125}"

# Establish the memory FLOOR first: a run over a tiny corpus. Peak RSS always
# includes the process image, libc, and the harness's own buffers — on the order
# of 1.5 MiB before the student's function has allocated a single byte — so the
# raw number hides exactly the part worth looking at. Everything below is
# reported both raw and above this floor.
if ! "$ORACLE" "$FN" "$SEED" 200 > "$T/corpus.floor" 2>"$T/oerr" ||
	! corpus_ok "$T/corpus.floor"; then
	skip_corpus
fi
# shellcheck disable=SC2046
set -- $(measure "$T/corpus.floor" "$STUDENT")
[ "$4" != start ] || out_of_time "the 200-case floor run"
[ "$4" != timeout ] ||
	not_measured "even 200 cases did not finish within $(limit_note "$5" "$6"), so no size could be timed."
FLOOR=$3
[ "$FLOOR" -gt 0 ] 2>/dev/null || FLOOR=0

# crashed N HOW -- a measured run killed by a signal: a finding, never a sample.
# perf_run says which from wait4() ("sigN"), never as 128+N.
crashed() {
	echo ""
	echo "  CRASHED: the run over $1 was killed by $(rl_signame "${2#sig}")."
	echo "  Nothing was measured; the diff_asan layer replays these inputs and"
	echo "  says where."
	exit 1
}

# measure_sizes -- the three sizes, best of PERF_REPEATS each, as a table.
# Returns 0, or 1 when one did not finish within its limit (TIMED_N,
# TIMED_LIMIT, TIMED_CLAMPED say which). A crash ends the test here.
measure_sizes() {
	printf '  %-9s %9s %9s %11s %13s %7s\n' \
		"CASES" "WALL(ms)" "CPU(ms)" "PEAK(KiB)" "ABOVE FLOOR" "EXIT"
	i=0
	for n in $N1 $N2 $N3; do
		if ! "$ORACLE" "$FN" "$SEED" "$n" > "$T/corpus.$n" 2>"$T/oerr" ||
			! corpus_ok "$T/corpus.$n"; then
			skip_corpus
		fi
		# Word splitting is the point: measure_best() returns six fields.
		# shellcheck disable=SC2046
		set -- $(measure_best "$T/corpus.$n" "$STUDENT")
		[ "$4" != start ] || out_of_time "the $n-case run"
		_above=$(( $3 - FLOOR ))
		[ "$_above" -ge 0 ] || _above=0
		eval "MS$i=$1; CPU$i=$2; RSS$i=$3; ABOVE$i=$_above; EX$i=$4"
		printf '  %-9s %9s %9s %11s %13s %7s\n' "$n" "$1" "$2" "$3" "$_above" "$4"
		case "$4" in
			"timeout") TIMED_N=$n; TIMED_LIMIT=$5; TIMED_CLAMPED=$6; return 1 ;;
			sig*) crashed "$n cases" "$4" ;;
			error)
				echo "perf_test.sh: perf_run could not run the $n-case measurement" >&2
				exit 2 ;;
		esac
		i=$((i + 1))
	done
	return 0
}

# A size that does not finish within its limit is not a verdict: halve all
# three and measure again, down to PERF_MIN_CASES at the smallest.
while ! measure_sizes; do
	if [ $((N1 / 2)) -lt "$PERF_MIN_CASES" ]; then
		not_measured "the $TIMED_N-case run did not finish within $(limit_note "$TIMED_LIMIT" "$TIMED_CLAMPED"), and the sizes cannot be halved again ($N1 cases is the smallest)."
	fi
	echo ""
	echo "  The $TIMED_N-case run did not finish within $(limit_note "$TIMED_LIMIT" "$TIMED_CLAMPED")."
	echo "  That is not a verdict: halving every size and measuring again."
	echo ""
	N1=$((N1 / 2)); N2=$((N2 / 2)); N3=$((N3 / 2))
done
echo "  (floor = ${FLOOR} KiB: the process, libc and the harness's own buffers,"
echo "   measured over 200 cases before your function does any real work.)"

# Growth exponent p, fitted by least squares on log(cost) against log(cases)
# across ALL THREE points.
#
# It used to be log(t3/t1)/log(n3/n1) -- the two endpoints, one sample each, on
# wall time. Three things were wrong with that and all three are fixed here:
# the samples are now the best of PERF_REPEATS runs, the cost is CPU time rather
# than wall time, and the middle point is no longer thrown away. A straight line
# through two points fits them exactly no matter where they are, so it could not
# tell a clean measurement from a disturbed one; three points can at least
# disagree, and the monotonicity check below acts on it when they do.
#
# awk, not bc: bc is not guaranteed present and awk is already a hard dependency
# of diff_output.sh. Timings under ~15ms are dominated by process startup and
# cannot support an exponent, so they are reported as "too fast to measure".
fit_exponent() {  # T1 T2 T3 [X1 X2 X3]: the x values default to the case counts
	awk -v t1="$1" -v t2="$2" -v t3="$3" -v n1="${4:-$N1}" -v n2="${5:-$N2}" \
		-v n3="${6:-$N3}" '
		BEGIN {
			if (t1 < 15 || t3 < 15) { print "na"; exit }
			if (t1 <= 0 || t2 <= 0 || t3 <= 0) { print "na"; exit }
			if (n3 <= n1) { print "na"; exit }
			x[1] = log(n1); x[2] = log(n2); x[3] = log(n3)
			y[1] = log(t1); y[2] = log(t2); y[3] = log(t3)
			for (i = 1; i <= 3; i++) { sx += x[i]; sy += y[i] }
			mx = sx / 3; my = sy / 3
			for (i = 1; i <= 3; i++) {
				num += (x[i] - mx) * (y[i] - my)
				den += (x[i] - mx) * (x[i] - mx)
			}
			if (den <= 0) { print "na"; exit }
			printf "%.2f", num / den
		}'
}

is_monotone() {
	awk -v a="$1" -v b="$2" -v c="$3" 'BEGIN { exit !(a <= b && b <= c) }'
}

over_gate() {
	awk -v p="$1" -v g="$GATE_EXPONENT" 'BEGIN { exit !(p >= g) }'
}

EXPONENT=$(fit_exponent "$CPU0" "$CPU1" "$CPU2")

# Do the three points actually describe growth?
#
# More work cannot take less time, so cost should rise with the case count. When
# it does not -- 291ms, 157ms, 313ms was a real run in this tree -- the machine
# was doing something else during the measurement and the fitted line is
# describing that, not the code. The exponent is still REPORTED, because it is
# information; it is not allowed to FAIL anyone, because a gate is a claim and
# this data does not support one. Erring toward not-gating is the safe direction:
# the cost of staying quiet is a performance note arriving one run later, and the
# cost of the alternative is telling a student their correct code is broken.
MONOTONE=1
if [ "$EXPONENT" != "na" ]; then
	is_monotone "$CPU0" "$CPU1" "$CPU2" || MONOTONE=0
fi

# Memory growth over the SAME three points, reported as a GROWTH FACTOR rather
# than as an exponent. Peak RSS is quantised to page/allocator granularity and
# is genuinely noisy — a function that allocates nothing measures 1592, 1592,
# 1500 KiB across the three runs, i.e. the last point lands BELOW the floor. An
# exponent over numbers like that is meaningless (and log(0) is -inf), whereas
# "the workload grew 4x and peak memory grew 1.0x" survives the noise and is
# easier to read besides.
#
# Compare raw peaks, so the constant floor cancels, and refuse to claim anything
# until growth clears a noise band.
MEM_NOISE_KIB="${MEM_NOISE_KIB:-512}"
MEMGROW=$(awk -v r1="$RSS0" -v r3="$RSS2" -v fl="$FLOOR" -v noise="$MEM_NOISE_KIB" '
	BEGIN {
		if (r3 - r1 < noise) { print "flat"; exit }
		a1 = r1 - fl; a3 = r3 - fl
		if (a1 < 1) a1 = 1
		printf "%.1f", a3 / a1
	}')
CASEGROW=$(awk -v n1="$N1" -v n3="$N3" 'BEGIN { printf "%.0f", n3 / n1 }')

RC=0
if [ "$EXPONENT" = "na" ]; then
	echo ""
	echo "  time         : too fast to measure reliably at this size (good sign)"
else
	echo ""
	echo "  time         : grows about n^$EXPONENT over ${N1}..${N3} cases"
	VERDICT=$(awk -v p="$EXPONENT" 'BEGIN {
		if (p < 1.35) print "linear-ish"
		else if (p < 1.8) print "somewhat super-linear — worth a look"
		else if (p < 2.4) print "looks quadratic — is there a scan inside a scan?"
		else print "worse than quadratic"
	}')
	echo "                 ($VERDICT)"
	# WHAT n IS. Every case is one call on one corpus line, and most lines are
	# short, so this is how the cost of many calls adds up -- not how one call
	# grows with a longer input: a cubic sort over arrays of a dozen ints is
	# linear in how many arrays it is handed (finding 044). The longest line
	# is printed so the reader knows how small "small" is.
	echo "                 n is the number of CASES, each one call on one input"
	echo "                 (the longest is $(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' "$T/corpus.$N3") bytes of corpus line). It is not how one"
	echo "                 call grows with a longer input$(if [ -n "$LEN_FN" ]; then echo ": the length series"; else echo "."; fi)"
	[ -z "$LEN_FN" ] || echo "                 below measures that."
	if [ "$MONOTONE" = 0 ]; then
		echo ""
		echo "  NOT GATING: the three timings did not rise with the case count"
		echo "        (${CPU0}ms, ${CPU1}ms, ${CPU2}ms of CPU for ${N1}, ${N2}, ${N3} cases)."
		echo "        More work cannot take less time, so something outside this"
		echo "        program was competing for the machine and the exponent above"
		echo "        is partly describing that. It is reported for information and"
		echo "        deliberately not allowed to fail this test. Re-run on a quiet"
		echo "        machine if you want a number to act on."
	elif over_gate "$EXPONENT"; then
		# CONFIRM BEFORE FAILING.
		#
		# Taking the best of PERF_REPEATS runs removes most measurement noise,
		# and the monotonicity check above catches the shapes where noise
		# DEFLATED the exponent. Neither catches the remaining case: a spike on
		# the LAST point inflates the exponent while leaving the three timings
		# still rising, so it looks like clean evidence of quadratic growth.
		#
		# That case is the one that matters most, because it is the only way this
		# layer can tell a student their correct code is broken. So the gate --
		# and only the gate -- measures again from scratch and has to survive the
		# second reading. Noise does not reproduce; that is what makes it noise.
		# A function that is genuinely quadratic is quadratic every time it is
		# asked, so the honest failure is unaffected and the accidental one
		# disappears. The extra runs are paid for only on the path that was about
		# to fail, so nothing costs more in the normal case.
		echo ""
		echo "  n^$EXPONENT is over the gate ($GATE_EXPONENT). Measuring again before"
		echo "  calling it a failure — a verdict this expensive should not rest on"
		echo "  one reading of a shared machine."
		R0=$(measure_best "$T/corpus.$N1" "$STUDENT" | cut -d' ' -f2)
		R1=$(measure_best "$T/corpus.$N2" "$STUDENT" | cut -d' ' -f2)
		R2=$(measure_best "$T/corpus.$N3" "$STUDENT" | cut -d' ' -f2)
		EXPONENT2=$(fit_exponent "$R0" "$R1" "$R2")
		echo "  second reading: ${R0}ms, ${R1}ms, ${R2}ms of CPU — n^$EXPONENT2"
		if [ "$EXPONENT2" != "na" ] && is_monotone "$R0" "$R1" "$R2" &&
			over_gate "$EXPONENT2"; then
			echo ""
			echo "  GATE: growth of n^$EXPONENT is steep enough that this would stop"
			echo "        finishing on a larger input, and a second independent"
			echo "        measurement agreed (n^$EXPONENT2). That is the one"
			echo "        performance result treated as a failure rather than as"
			echo "        information."
			RC=1
		else
			echo ""
			echo "  NOT GATING: the second measurement did not reproduce it. The"
			echo "        first reading was most likely this machine being busy"
			echo "        rather than your code being slow, so this is reported"
			echo "        and not failed. If you see it repeatedly, it is real."
		fi
	fi
fi

# ---- memory, reported beside time so the trade-off between them is visible ---
if [ "$MEMGROW" = "flat" ]; then
	echo "  memory       : flat — ${CASEGROW}x the workload did not raise peak use"
	echo "                 beyond measurement noise (${MEM_NOISE_KIB} KiB). Whatever you"
	echo "                 allocate, you release or reuse."
else
	echo "  memory       : ${CASEGROW}x the workload raised peak use ${MEMGROW}x above the floor"
	awk -v g="$MEMGROW" -v c="$CASEGROW" 'BEGIN {
		if (g < 1.3)
			print "                 (essentially constant)"
		else if (g < c * 0.5)
			print "                 (grows, but slower than the workload)"
		else {
			print "                 (grows in step with the case count: something"
			print "                  allocated per case is not being released. The"
			print "                  valgrind layer decides whether that is a leak —"
			print "                  this only says the footprint tracks the workload.)"
		}
	}'
fi

# The point of showing both: there is no single right answer here. Trading
# memory for speed (a lookup table, a precomputed buffer) and trading speed for
# memory (recomputing instead of storing) are both legitimate engineering
# choices, and the subject does not pick one for you. What matters is that the
# choice is deliberate rather than accidental.
echo ""
echo "  Read the two together. Neither number is a score, and there is no"
echo "  correct pair: spending memory to save time (a table you look up instead"
echo "  of a value you recompute) and spending time to save memory (recomputing"
echo "  instead of storing) are both real, defensible choices. What this layer"
echo "  is asking is whether the trade you made was one you MEANT to make."

# ----------------------------------------------------------------- length mode
# How ONE call's cost grows with its input's length: LEN_CASES cases at lengths
# L, 2L and 4L (oracle arm LEN_FN, `oracle <arm> <seed> <cases> <length>`),
# replayed through LEN_BIN, a harness that reads a line of any length. Best of
# PERF_REPEATS each, CPU time, the same fit as above.
#
# REPORTED, NEVER GATED. For the exercises that have it (a sort, a split) the
# exponent IS the algorithm, and C 12's cost comment refuses a sorting budget
# for the reason that applies here: any line drawn on it would recommend the
# algorithm it was drawn from. So it says what doubling the input does, as a
# number, and nothing about which number to want.
#
# The length adapts both ways: a run under 15ms of CPU cannot carry an
# exponent (process start-up is most of it), so while the shortest is, L
# doubles (four times at most); a run that does not finish within its limit
# halves it (to 8 at least). Each harness checks its
# own result -- the function's output at these lengths is compared with
# nothing else -- and a wrong one is exit 3: that is reported, not timed.
#
# Nothing here changes the exit status but a crash, and, under NO_SKIP=1, a
# series whose oracle arm wrote nothing: that is the wiring rotting, which the
# sweep exists to see. A wrong result, or a length too slow to finish, is the
# function's, and the case-count series above has already measured something.
length_series() {
	_L=$LEN_BASE
	_grow=0
	echo ""
	echo "  length       : $LEN_CASES cases at each of three lengths, one input growing"
	while :; do
		_l1=$_L; _l2=$((_L * 2)); _l3=$((_L * 4))
		_ok=1
		_cpus=""
		for _len in $_l1 $_l2 $_l3; do
			if ! "$ORACLE" "$LEN_FN" "$SEED" "$LEN_CASES" "$_len" > "$T/len.$_len" 2> "$T/oerr" ||
				! [ -s "$T/len.$_len" ]; then
				echo "                 the reference could not generate length $_len (fn=$LEN_FN)."
				rl_excerpt "$T/oerr" 3 reference-stderr.txt
				[ "${NO_SKIP:-0}" != 1 ] || { echo "  NO_SKIP set: the length series measured nothing."; RC=1; }
				return
			fi
			# shellcheck disable=SC2046
			set -- $(measure_best "$T/len.$_len" "$LEN_BIN")
			case "$4" in
				# conventions: not-a-list -- CPU times measure_best printed, numbers with no blank
				0) _cpus="$_cpus $2" ;;
				start)
					echo "                 the test's own time ran out before length $_len could start."
					return ;;
				"timeout") _ok=0; break ;;
				sig*) crashed "$LEN_CASES cases of length $_len" "$4" ;;
				error)
					echo "perf_test.sh: perf_run could not run the length-$_len measurement" >&2
					exit 2 ;;
				3)
					echo "                 at length $_len the result was wrong, so it was not timed:"
					echo "                 the cost of a wrong answer is not information. A capacity"
					echo "                 of your own that a long input passes is one way to get there."
					return ;;
				*)
					echo "perf_test.sh: the length harness returned $4 at length $_len" >&2
					exit 2 ;;
			esac
		done
		if [ "$_ok" = 0 ]; then
			if [ $((_L / 2)) -lt 8 ]; then
				echo "                 even length $_len did not finish within its limit, so no"
				echo "                 exponent could be fitted. That is reported, never failed."
				return
			fi
			echo "                 length $_len did not finish within its limit: halving the lengths."
			_L=$((_L / 2))
			continue
		fi
		# shellcheck disable=SC2086
		set -- $_cpus
		if [ "$1" -lt 15 ] && [ "$_grow" -lt 4 ]; then
			_L=$((_L * 2))
			_grow=$((_grow + 1))
			continue
		fi
		break
	done
	printf '                 %-8s %9s\n' "LENGTH" "CPU(ms)"
	printf '                 %-8s %9s\n' "$_l1" "$1" "$_l2" "$2" "$_l3" "$3"
	_p=$(fit_exponent "$1" "$2" "$3" "$_l1" "$_l2" "$_l3")
	if [ "$_p" = na ]; then
		echo "                 too fast to time even at these lengths: no exponent is fitted."
		return
	fi
	echo "                 grows about L^$_p with the length of one input: doubling it"
	echo "                 multiplies a call's cost by about $(awk -v p="$_p" 'BEGIN { printf "%.1f", 2 ^ p }')."
	is_monotone "$1" "$2" "$3" ||
		echo "                 (the timings did not rise with the length: a busy machine; re-run)"
	echo "                 Reported, never failed: how one call grows with its input is"
	echo "                 the method you chose, and which growth to want is yours to weigh."
}
[ -z "$LEN_FN" ] || length_series

# ------------------------------------------------------------------ ratio mode
# The reference baseline. `oracle bench <fn>` reads the corpus and computes the
# reference answers without generating or printing, so it does the same work the
# student's function does. Not every function has a bench arm yet; one that does
# not exits non-zero, and this falls back to scaling rather than inventing a
# ratio.
if [ "$BASELINE_ORACLE" = "1" ] && [ -z "$BASELINE" ]; then
	if "$ORACLE" bench "$FN" < "$T/corpus.floor" >/dev/null 2>&1; then
		BASELINE="$ORACLE"
		set -- "$T/corpus.$N3" "$ORACLE" bench "$FN"
	else
		echo ""
		echo "  reference    : not compared — //oracle has no bench arm for $FN yet,"
		echo "                 so there is nothing that replays this corpus to time"
		echo "                 against. The scaling numbers above stand on their own."
		exit $RC
	fi
elif [ -n "$BASELINE" ]; then
	set -- "$T/corpus.$N3" "$BASELINE"
else
	echo ""
	echo "  reference    : not compared — no baseline was supplied."
	exit $RC
fi

# shellcheck disable=SC2046
set -- $(measure_best "$@")
if [ "$4" = start ]; then
	echo ""
	echo "  reference    : not timed — the test's own time ran out first. The scaling"
	echo "                 figures above stand on their own."
	exit $RC
fi
BMS=$1; BRSS=$3
echo ""
printf '  reference    : %s ms, %s KiB peak\n' "$BMS" "$BRSS"

# Dividing by a near-zero baseline produces a number that means nothing. Below
# this floor the timer's own resolution and process startup dominate what the
# reference actually did, so say that rather than print a ratio (or a bare "na",
# which reads like a bug and was how this surfaced).
if [ "${BMS:-0}" -lt "${PERF_MIN_BASELINE_MS:-20}" ]; then
	echo "                 too fast to time at this size — the reference finishes in"
	echo "                 under ${PERF_MIN_BASELINE_MS:-20}ms, where process startup and timer"
	echo "                 resolution dominate. No ratio is reported, because dividing"
	echo "                 by that number would not mean anything. The scaling figures"
	echo "                 above are unaffected."
	exit $RC
fi
SLOW=$(awk -v s="$MS2" -v b="$BMS" 'BEGIN { if (b <= 0) print "na"; else printf "%.1f", s / b }')
MEM=$(awk -v s="$RSS2" -v b="$BRSS" 'BEGIN { if (b <= 0) print "na"; else printf "%.1f", s / b }')
echo "  vs reference : ${SLOW}x time, ${MEM}x peak memory"
# Both timings include their harness: reading the corpus, splitting fields,
# hex-decoding — and on the student's side, PRINTING the result, which the
# reference deliberately does not do. Measured, those overheads dominate: a
# ft_strlen harness comes out at 0.5x purely because the C reader parses the
# corpus faster than the Rust one, and a ft_putstr harness at 247x purely
# because it writes and the reference does not. Neither number says anything
# about the function. Only a gap far larger than any harness difference could
# explain is worth acting on, so that is the only band this interprets.
awk -v s="$SLOW" 'BEGIN {
	if (s == "na") exit
	if (s < 20) {
		print "                 Within the range where the two harnesses'"'"' own overhead"
		print "                 (corpus parsing on both sides, printing on yours) accounts"
		print "                 for the difference. Nothing here is about your function —"
		print "                 read the scaling figures above instead."
		exit
	}
	if (s < 200) {
		print "                 Larger than harness overhead explains. Worth a look at how"
		print "                 much work you do per case — though if your function WRITES"
		print "                 its output, some of this is the cost of doing that at all."
		exit
	}
	print "                 Orders of magnitude. Once compiled both do similar work per"
	print "                 iteration, so a gap this size means far MORE iterations —"
	print "                 an implementation choice rather than a language one."
}'
if [ "$SLOW" != "na" ] && awk -v s="$SLOW" -v g="$GATE_SLOWDOWN" 'BEGIN { exit !(s >= g) }'; then
	echo "  GATE: ${SLOW}x slower than the reference is beyond 'slow but fine'."
	RC=1
fi
if [ "$MEM" != "na" ] && awk -v m="$MEM" -v g="$GATE_MEMORY" 'BEGIN { exit !(m >= g) }'; then
	echo "  GATE: ${MEM}x the reference's peak memory suggests an unbounded"
	echo "        allocation rather than a merely wasteful one."
	RC=1
fi
exit $RC
