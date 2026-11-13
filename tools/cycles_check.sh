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
# A REPORT, NEVER A GATE, on what it measures: the numbers and the budgets only
# change the sentences printed, and a run too long to profile is reported too.
# It fails (exit 1) only when the function crashed under callgrind or did not
# build -- and, under NO_SKIP=1, when nothing was measured -- and exits 2 when
# the harness's own wiring is wrong, a unit expression included.
#
# WHAT A FUNCTION'S CALLS COST. callgrind collects only inside the function
# (--toggle-collect), so a write() or a malloc() made through a helper of the
# student's is the function's, and the allocator's instructions are printed
# apart from the rest: the per-unit figure with them and without them, and the
# budget read against the second. How many blocks to ask for is a choice on an
# axis of its own, and a figure that hid it, or blamed the loop for it, would
# declare a winner.
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
#                   --valgrind PATH --valgrind-tools FILE
#                   [--count N] [--unit-expr AWK] [--unit-name TEXT]
#                   [--max-unit N]
#                   [--gate-differ P --gate-bin P --gate-expected P ...
#                    [--gate-label NAME]]
#   cycles_check.sh --harness FILE --src FILE... [--inc DIR]... [--inc-file FILE]
#                   [--lib FILE]...
#                   --cc PATH [--cc-lib FILE]... [--cc-under FILE]
#                   --ld PATH --ld-lib FILE...
#                   (and the rest as above): build the binary here, at -O2,
#                   with the pinned clang-12 and ld.bfd Bazel fetched (each
#                   with the libraries it loads: tools/runner_lib.sh's
#                   rl_cc_pin and rl_ld_pin), never with the box's `cc`.
#
# --inc-file FILE holds the -I directories a Makefile's recipes pass, one per
# line (tools/student_build.sh --includes-out, runner_lib.sh's rl_inc_file):
# a library's header in a subfolder is on the grader's include path only
# through them.
#
# --lib FILE is an archive the GRADER links (tools/grader_lib.bzl: C 12's own
# ft_create_elem), linked after the sources.
#
#   --max-unit N   leave out every case of more than N units (--unit-expr): the
#                  cases a corpus holds to test CAPACITY -- thousands of words
#                  where the rest have a handful (finding 041) -- which the diff
#                  and diff_asan layers judge. Kept in, two such cases were half
#                  the bytes of C 07's split corpus, and the figure per byte
#                  measured their mix of words rather than the function's
#                  usual cost; the report says how many were left out.
#
#   --gate-label NAME  the output test the gate is, by name, for its SKIP line.
#                  Any --gate-* without all of --gate-differ, --gate-bin and
#                  --gate-expected is a wiring mistake, refused (runner_lib.sh's
#                  rl_gate_whole).
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
require awk cat dirname grep mktemp mv readlink rm tr wc

# The shared runner helpers -- time budget, exiting signal traps, how a run
# ended, excerpts, hints -- written once in tools/runner_lib.sh.
RL_NAME=cycles_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "cycles_check.sh: tools/runner_lib.sh is not staged (tools/defs_test.bzl's _test() stages it for every test; by hand, run this by its path in the repository)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool ORACLE -- the Rust reference (//oracle), which writes the corpus
# conventions: harness tool CC -- the pinned compiler: it builds, and runs none of what it builds

BIN=""; ORACLE=""; FN=""; SYM=""; COUNT="3000"
HARNESS=""; SRCS=""; INCS=""; LIBS=""; OPT="${CYCLES_OPT:--O2}"
UNIT_EXPR=""; UNIT_NAME="case"; BUDGET=""; SYSCALL_BUDGET=""; MAX_UNIT=""
GATE_DIFFER=""; GATE_BIN=""; GATE_EXPECTED=""; GATE_PASS=""; GATE_NAME=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
VALGRIND=""
VGTOOLS=""
CC=""
CC_LIBS=""
CC_UNDER=""
LD=""
LD_LIBS=""

while [ $# -gt 0 ]; do
	case "$1" in
		--valgrind) rl_need "$1" "$#"; VALGRIND="$2"; shift 2 ;;
		--valgrind-tools) rl_need "$1" "$#"; VGTOOLS="$2"; shift 2 ;;
		--bin) rl_need "$1" "$#"; BIN="$2"; shift 2 ;;
		--harness) rl_need "$1" "$#"; HARNESS="$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--src) rl_need "$1" "$#"; rl_list_add SRCS "$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--inc) rl_need "$1" "$#"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--inc-file) rl_need "$1" "$#"; rl_inc_file INCS "$2"; shift 2 ;;
		--lib) rl_need "$1" "$#"; rl_list_add LIBS "$2"; shift 2 ;;
		--oracle) rl_need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--oracle-fn) rl_need "$1" "$#"; FN="$2"; shift 2 ;;
		--symbol) rl_need "$1" "$#"; SYM="$2"; shift 2 ;;
		--count) rl_need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--unit-expr) rl_need "$1" "$#"; UNIT_EXPR="$2"; shift 2 ;;
		--unit-name) rl_need "$1" "$#"; UNIT_NAME="$2"; shift 2 ;;
		--max-unit) rl_need "$1" "$#"; MAX_UNIT="$2"; shift 2 ;;
		--budget) rl_need "$1" "$#"; BUDGET="$2"; shift 2 ;;
		--syscall-budget) rl_need "$1" "$#"; SYSCALL_BUDGET="$2"; shift 2 ;;
		--gate-differ) rl_need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) rl_need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) rl_need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-stdin) rl_need "$1" "$#"; rl_list_add GATE_PASS --stdin "$2"; shift 2 ;;
		--gate-sanitize) rl_list_add GATE_PASS --sanitize; shift ;;
		--gate-labeled) rl_list_add GATE_PASS --labeled; shift ;;
		--gate-label) rl_need "$1" "$#"; GATE_NAME="$2"; shift 2 ;;
		--cc) rl_need "$1" "$#"; CC="$2"; shift 2 ;;
		--cc-lib) rl_need "$1" "$#"; rl_list_add CC_LIBS "$2"; shift 2 ;;
		--cc-under) rl_need "$1" "$#"; CC_UNDER="$2"; shift 2 ;;
		--ld) rl_need "$1" "$#"; LD="$2"; shift 2 ;;
		--ld-lib) rl_need "$1" "$#"; rl_list_add LD_LIBS "$2"; shift 2 ;;
		*) echo "cycles_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

# A gate given in part is a wiring mistake (runner_lib.sh, rl_gate_whole).
rl_gate_whole cycles_check "$GATE_DIFFER" "$GATE_BIN" "$GATE_EXPECTED" "$GATE_PASS$GATE_NAME"

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
# below (a red output gate, no corpus, a run too long to profile, a harness
# that returned non-zero, profiling failed, symbol absent from the profile)
# between them cover every way this plumbing can rot, and the one that
# motivated guarding all of them is the last: a count read the wrong way is
# empty for every exercise at once. It was read off callgrind_annotate's
# columns, an output format nobody promised, so one upstream release could have
# retired the entire layer with every target still green, and nothing would say
# so. It is read off the profile's own totals now (below), and the guard stays.
#
# NO_SKIP=1 — the maintainer's forced sweep, `bazel test //...
# --test_env=NO_SKIP=1`; there is no CI in this repo and this line used to claim
# there was — turns each of them into a failure that
# names which one fired, so the rot is visible the day it happens rather than
# whenever someone next wonders why nothing has ever been over budget.
# The valgrind these layers run is FETCHED AND PINNED, never found on PATH:
# a missing --valgrind or --valgrind-tools is a wiring error, not a skip.
# tools/runner_lib.sh's rl_vg_pin proves it can run callgrind, and says why
# its tool folder, exported as $VALGRIND_LIB, is what makes a relocated
# valgrind work at all.
rl_vg_pin "$VALGRIND" "$VGTOOLS" callgrind || exit 2
VALGRIND=$RL_VG_BIN

T=$(mktemp -d) || { echo "$RL_NAME.sh: cannot create a scratch directory" >&2; exit 2; }
rl_traps 'rm -rf "$T"'

# The correctness gate, tools/runner_lib.sh's rl_gate, as every gated
# runner's is: counting the instructions of a wrong answer is not information.
# NO_SKIP=1 forces it open.
RL_GATE_PASS=$GATE_PASS
RL_GATE_NAME=$GATE_NAME
RL_GATE_WHY="  Counting the instructions of a wrong answer is not useful;
  this starts measuring once the *_output layer is green."
rl_gate cycles_check "$GATE_DIFFER" "$GATE_BIN" "$GATE_EXPECTED"

# A PROGRAM THAT DID NOT BUILD, handed over with --bin, is a stand-in script
# that says why (see tools/standin.sh): profiling it would measure a shell
# printing a compiler error. Checked after the gate, like every gated layer.
# (The harness path below compiles at test time, and reports its own failure.)
rl_tool standin.sh
# shellcheck source=tools/standin.sh
. "$RL_TOOL"
[ -z "$BIN" ] || standin_check cycles_check "$BIN" fail "the program"

# Build our OWN binary, optimised.
#
# This layer cannot reuse the harness Bazel already built: `fastbuild` is -O0,
# where every local is a memory round-trip, and that inflates the count by ~3.6x
# — ft_strlen measures 11.4 instructions per byte at -O0 and 3.2 at -O2. The
# whole point of a per-unit figure is that it can be read against what the work
# ought to cost, and 3.2 is the floor (a load, a compare, an increment) while
# 11.4 reads as "three times too slow" for code that is in fact optimal. So the
# number has to come from an optimised build or it measures the build mode.
#
# WITH THE PINNED COMPILER AND LINKER. It used to be the box's `cc`, so the
# counts were that compiler's -O2 -- gcc's on a box whose cc is gcc, clang's on
# campus, where cc is clang-12 -- and a box with none SKIPped (TO VERIFY V38's
# class). Bazel hands over the fetched clang-12 and ld.bfd, as to every layer
# that compiles, and _test() in tools/defs_test.bzl refuses a test that does
# not (pinned_cc_problem); a build here without them is the harness's fault.
if [ -n "$HARNESS" ]; then
	[ -n "$CC" ] || { echo "cycles_check.sh: --harness builds here, and needs --cc (the pinned clang-12)" >&2; exit 2; }
	[ -n "$LD" ] || { echo "cycles_check.sh: --harness builds here, and needs --ld (the pinned ld.bfd)" >&2; exit 2; }
	rl_cc_pin "$CC" "$CC_LIBS" "$CC_UNDER"
	rl_ld_pin "$CC" "$LD" "$LD_LIBS" "$T/ld"
	# The HARNESS is marked, and nothing else: its debug information names
	# every file under /@harness@/ (-fdebug-prefix-map maps every absolute
	# path, its working directory's and so every relative one's included), so
	# a function of the binary whose file callgrind names there is the
	# harness's -- the callback it hands over included -- and every other one
	# is the student's side: their sources (built with -g), and the grader's
	# --lib archives and the compiler's runtime, built by others with or
	# without debug information. It used to be the other way round -- the
	# harness built without debug information, and a function whose file
	# callgrind does not know ("???") taken for the harness's -- so a grader
	# function the subject makes the student call (C 12's ft_create_elem, a
	# prebuilt archive) read as "the function it was handed", and its malloc()
	# as not the student's. Marking the prefix, not naming the file: callgrind
	# names a function's file after its first instruction, which may be a
	# header's inlined code -- under the same mark here.
	#
	# The lists are one word per line (runner_lib.sh, LISTS OF WORDS), and
	# CYCLES_OPT's flags are split at blanks into one, as they always were.
	OPTS=""
	set -f
	# shellcheck disable=SC2086
	for _o in $OPT; do rl_list_add OPTS "$_o"; done
	set +f
	rl_split_on
	# shellcheck disable=SC2086
	"$CC" "$RL_LDFLAG" $OPTS -g -fdebug-prefix-map=/=/@harness@/ -w $INCS -c "$HARNESS" -o "$T/harness.o" 2> "$T/cc.err" &&
		"$CC" "$RL_LDFLAG" $OPTS -g -w $INCS "$T/harness.o" $SRCS $LIBS -o "$T/bin" 2>> "$T/cc.err"
	_cc_rc=$?
	rl_split_off
	if [ "$_cc_rc" -ne 0 ]; then
		echo "cycles_check: FAIL — could not build the harness at $OPT"
		rl_excerpt "$T/cc.err" 15 compiler-output.txt
		exit 1
	fi
	BIN="$T/bin"
fi

# The oracle's stderr is kept ($T/oerr) and shown either way, as perf_test.sh
# shows it: a renamed arm or a panic says why only there.
if ! "$ORACLE" "$FN" 1 "$COUNT" > "$T/corpus" 2> "$T/oerr" || [ ! -s "$T/corpus" ]; then
	# NO_SKIP=1: a renamed or removed oracle fn silently empties the corpus, and
	# the binary would then be profiled against no input at all.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: the reference produced no corpus for fn=$FN, so the"
		echo "             function was never given anything to do."
		rl_excerpt "$T/oerr" 3 reference-stderr.txt
		exit 1
	}
	echo "cycles_check: SKIP — the reference could not generate a corpus (fn=$FN)."
	rl_excerpt "$T/oerr" 3 reference-stderr.txt
	exit 0
fi
# The capacity cases, left to the diff layers (--max-unit, above).
LEFT_OUT=0
if [ -n "$MAX_UNIT" ]; then
	case "$MAX_UNIT" in
		'' | *[!0-9]*) echo "cycles_check.sh: --max-unit must be a count of units, got '$MAX_UNIT'" >&2; exit 2 ;;
	esac
	[ -n "$UNIT_EXPR" ] || { echo "cycles_check.sh: --max-unit needs --unit-expr, which says what a unit is" >&2; exit 2; }
	LC_ALL=C awk -F'\t' -v max="$MAX_UNIT" -v kept="$T/kept" "{ if (($UNIT_EXPR) > max + 0) n++; else print > kept } END { printf \"%d\", n }" \
		"$T/corpus" > "$T/left" || { echo "cycles_check.sh: could not filter the corpus" >&2; exit 2; }
	LEFT_OUT=$(cat "$T/left")
	if [ ! -s "$T/kept" ]; then
		echo "cycles_check.sh: --max-unit $MAX_UNIT leaves no case of fn=$FN to profile" >&2
		exit 2
	fi
	mv "$T/kept" "$T/corpus"
fi
CASES=$(wc -l < "$T/corpus" | tr -d ' ')

# The unit of work, summed straight off the corpus so it cannot drift from the
# inputs actually used. Default: one unit per case.
#
# The expression is the HARNESS's (the c_cycles call in the module's
# BUILD.bazel), never the student's, so anything wrong with it is exit 2: the
# measurement never ran. It used to fail quietly twice over. awk's error went to
# the log and its status was never read, so an expression Bazel's tokeniser had
# stripped of its quotes (C 12's and C 13's, finding 131) fell back to one unit
# per case, and the per-call figure was printed as "per element" beside a
# per-element budget. And an expression that reads the wrong field -- C 07
# ex03's length($1)/2 over a decimal count, half a "byte" a call (finding 081)
# -- turned a correct answer into "87x over budget". Every unit this layer uses
# is something each case holds at least one of on average (a byte of input, a
# digit, an element), so fewer than one per case is that mistake, not a corpus.
#
# IN BYTES, under LC_ALL=C here and in --max-unit's filter above. The tests
# run under en_US.UTF-8, where an awk that reads multibyte characters (gawk;
# mawk does not) takes length() of a field of raw bytes in characters, and
# warns on stderr of the bytes that are not UTF-8: the same corpus would
# count fewer units on one machine than on another, or be refused below as
# an expression awk could not read. tools/runner_lib.sh runs its own
# byte-reading awk the same way.
if [ -n "$UNIT_EXPR" ]; then
	WORK=$(LC_ALL=C awk -F'\t' "{ s += $UNIT_EXPR } END { printf \"%d\", s }" \
		"$T/corpus" 2> "$T/unit.err")
	_unit_rc=$?
	case "$WORK" in '' | *[!0-9]*) [ "$_unit_rc" != 0 ] || _unit_rc=1 ;; esac
	if [ "$_unit_rc" != 0 ] || [ -s "$T/unit.err" ]; then
		echo "cycles_check: the unit of work could not be counted, so there is no"
		echo "              per-$UNIT_NAME figure. awk refused the unit expression:"
		echo "                $UNIT_EXPR"
		rl_excerpt "$T/unit.err" 5 unit-expr-error.txt
		echo "  That expression is the harness's (the c_cycles call in this module's"
		echo "  BUILD.bazel), not your code: the measurement never ran."
		exit 2
	fi
	if [ "$WORK" -lt "$CASES" ]; then
		echo "cycles_check: the unit expression counts $WORK ${UNIT_NAME}s over $CASES cases,"
		echo "              fewer than one per case, so it is reading the wrong field:"
		echo "                $UNIT_EXPR"
		echo "  That expression is the harness's (the c_cycles call in this module's"
		echo "  BUILD.bazel), not your code: no per-$UNIT_NAME figure is printed."
		exit 2
	fi
else
	WORK=$CASES
fi

# THE PROFILED RUN, bounded by what is left of this test's own limit (rl_tmo:
# no per-run cap of its own -- callgrind runs a program some fifty times slower
# than normal, so one run of the corpus is most of the time there is). It used
# to run bare: a slow or looping function died as a Bazel TIMEOUT with an empty
# log, and a function that crashed under it was reported as callgrind failing to
# profile the harness. How the run ended is decided first, and only a run that
# RETURNED can be blamed on the tool.
# CYCLES_TIMEOUT caps it below that, for a maintainer who wants a slow answer
# reported sooner.
#
# A run that does not finish is REPORTED, like perf's (finding 043): the
# output gate above already passed, so this is a function too costly to
# profile in the time there is -- its cost, the one thing this layer never
# fails on -- and a looping one is the output and diff layers' to name.
# NO_SKIP=1 makes it red, as it makes every layer that measured nothing.
too_long() {
	if [ "${RL_TMO:-}" = 0 ]; then
		echo "cycles_check: NOT MEASURED — the test's own time ran out before $1"
		echo "  could start (TEST_TIMEOUT=${TEST_TIMEOUT:-?}s)."
	elif [ "$RL_CLAMPED" = 1 ]; then
		echo "cycles_check: NOT MEASURED — $1 did not finish within ${RL_TMO}s,"
		echo "  what was left of the test's own limit (TEST_TIMEOUT=${TEST_TIMEOUT:-?}s)."
	else
		echo "cycles_check: NOT MEASURED — $1 did not finish within ${RL_TMO}s"
		echo "  (CYCLES_TIMEOUT)."
	fi
	echo "  That is reported, not failed: this layer never fails on what a function"
	echo "  costs, and this one cost more than could be counted in the time there was."
	echo "  A busy machine slows callgrind down too: run the target on its own to"
	echo "  get a figure."
	[ "${NO_SKIP:-0}" != 1 ] || {
		echo "  NO_SKIP set: nothing was measured, which the sweep reports red."
		exit 1
	}
	exit 0
}
if ! rl_tmo "${CYCLES_TIMEOUT:-}"; then
	too_long "the callgrind run over $CASES cases"
fi
# --toggle-collect: callgrind records only what runs inside $SYM -- its own
# instructions and every call made beneath it, by it or by a helper of the
# student's -- so the call counts and the allocator's cost below are the
# function's, whichever of its own functions made the call. (Recursion is
# handled: collection is on from the outermost entry to its return.)
# --vgdb=no: no FIFOs in TMPDIR for a gdb that never comes, which a run killed
# at its time limit would leave behind.
# The host's valgrind settings are off first (tools/runner_lib.sh, rl_vg_env):
# an option from VALGRIND_OPTS or a ~/.valgrindrc would change what is counted.
rl_vg_env "$T" || exit 2
rl_run "$VALGRIND" --tool=callgrind --vgdb=no --toggle-collect="$SYM" \
	--callgrind-out-file="$T/cg" "$BIN" < "$T/corpus" \
	> /dev/null 2>"$T/vg.err"
VG_RC=$?
rl_classify "$VG_RC"
# A run stopped from outside is no cost and no crash (rl_unjudged). One that
# could not start (noexec) is the SKIP below, as it was.
[ "$RL_CAUSE" != stopped ] || rl_unjudged "the callgrind run of $SYM's harness"
case "$RL_CAUSE" in
	"timeout")
		too_long "the $CASES-case run under callgrind, which runs a program about fifty times slower than normal"
		;;
	"signal" | "runaway")
		echo "cycles_check: FAIL — $SYM's harness $RL_WHY under callgrind."
		echo "  That is a crash on one of these inputs, not a cost: the diff and"
		echo "  diff_asan layers replay the same kind of input and say which. What"
		echo "  valgrind said:"
		rl_excerpt "$T/vg.err" 12 valgrind-output.txt
		exit 1
		;;
esac
# A valgrind that stopped at its own startup (V242) is the machine's setup:
# a SKIP would hide it as this layer standing down. No known cause makes
# callgrind do so today -- the ld.so debug symbols a memcheck run needs are
# memcheck's alone -- so this is a refusal kept in reserve, which names no
# package (tools/runner_lib.sh, rl_vg_aborted).
if [ "$VG_RC" -ne 0 ] && rl_vg_aborted callgrind "$SYM's harness" "$T/vg.err"; then
	exit 2
fi
# A harness that RETURNED non-zero (V291) ran under callgrind to its end:
# valgrind named the command it started, and callgrind wrote its profile.
# Its count is still not taken -- a run that did not end well measured
# nothing -- and the line says the harness returned it, where it used to say
# callgrind could not profile it, which blamed the tool. What the harness
# itself said is shown without valgrind's banner, which explains nothing.
if [ "$VG_RC" -ne 0 ] && [ "$RL_CAUSE" = exit ] && [ -s "$T/cg" ] &&
	grep -q '^==[0-9][0-9]*== Command: ' "$T/vg.err"; then
	grep -v '^==[0-9][0-9]*==' "$T/vg.err" > "$T/harness.err"
	if [ "${NO_SKIP:-0}" = "1" ]; then
		echo "NO_SKIP set: $SYM's harness $RL_WHY under callgrind, so there is"
		echo "             no instruction count for $SYM."
	else
		echo "cycles_check: SKIP — $SYM's harness $RL_WHY under callgrind, so its"
		echo "  count is not taken: only a run that ended normally is counted."
	fi
	if [ -s "$T/harness.err" ]; then
		echo "  What the harness said:"
		rl_excerpt "$T/harness.err" 5 harness-output.txt
	fi
	[ "${NO_SKIP:-0}" != "1" ] || exit 1
	exit 0
fi
if [ "$VG_RC" -ne 0 ]; then
	# NO_SKIP=1: a status valgrind returned itself -- a tool that could not
	# start -- so there is no count.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: callgrind could not profile the harness ($RL_WHY), so"
		echo "             there is no instruction count for $SYM. What valgrind said:"
		rl_excerpt "$T/vg.err" 5 valgrind-output.txt
		exit 1
	}
	echo "cycles_check: SKIP — callgrind could not profile the harness ($RL_WHY)."
	rl_excerpt "$T/vg.err" 5 valgrind-output.txt
	exit 0
fi

# INCLUSIVE cost: the function plus everything it calls. That is the honest
# number — a function that calls write() should be charged for every write() it
# makes, because how often it calls it was the decision under test.
#
# Nothing this runner prints may say how to get under a budget: the numbers
# and the budget, never the technique. Same rule as tools/ref_compare.sh.
#
# The run collected only what ran inside $SYM (--toggle-collect, above), so
# the instruction count the profile itself records -- its "totals:" line,
# tools/runner_lib.sh's rl_cg_total -- IS that inclusive count, and 0 when
# $SYM never ran.
IR=$(rl_cg_total "$T/cg")

if [ -z "$IR" ] || [ "$IR" = 0 ]; then
	# NO_SKIP=1: this is the site the guards above were added for. No count
	# means either this one exercise's symbol vanished or the profile's totals
	# stopped being read -- and the second case fires for every exercise at
	# once while every target stays green, which is the failure this whole layer
	# exists to make impossible.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no symbol '$SYM' in the callgrind profile, so nothing was"
		echo "             measured. If this fires for every exercise, suspect the"
		echo "             reading of the profile's totals (rl_cg_total), not the"
		echo "             deliverables."
		exit 1
	}
	echo "cycles_check: SKIP — no symbol '$SYM' in the profile."
	echo "              It may have been inlined, or the deliverable may not define it."
	exit 0
fi

# What the function's calls cost, read from the profile's call records. The
# run above collected only what ran inside $SYM, and of that a call is the
# STUDENT's when the function making it is theirs: in the binary, and not the
# harness's (the build above marks the harness's files, /@harness@/) -- the
# exercise's, and any the grader brings that it calls. It used to
# count only the calls $SYM made itself: a write() inside a static ft_putchar,
# or a malloc() inside a helper that builds one word, was invisible -- 0
# write() calls for a function writing one byte at a time, as long as it did so
# through a helper the compiler kept out of line. Counting every call inside
# $SYM would be wrong the other way: a function that applies a callback runs
# the HARNESS's callback inside it (btree_apply_prefix, ft_list_sort's cmp),
# and the stdio that callback prints with is not the student's write().
#
# So: write() and malloc() are counted when a student's function calls them;
# the allocator's cost is the inclusive cost of those malloc()/free() calls;
# and a call from a student's function to one of the harness's -- the function
# it was handed -- is the callback, whose cost is shown apart too.
#
# A libc callee is matched on its NAME, exactly: libc's internal helpers
# (_int_malloc, __write_nocancel) are inside the call being counted, and
# counting them too would count it twice. glibc may record a function under an
# alias (__libc_malloc, __GI___libc_write), which is the same function. The
# names, and which of them is write(), are read as ref_compare.sh reads them
# (tools/runner_lib.sh, rl_cg_awk: named, base, is_write).
#
# The profile format (callgrind's "Callgrind Format Specification"): names
# are COMPRESSED -- "fn=(12) ft_putstr" the first time and bare "fn=(12)"
# after, objects and files likewise -- so the id->name tables are built as it
# is read. A function's object and file are the ob= and fl= before its fn=; a
# callee's are the cob= and cfi=/cfl= before its cfn=, or the caller's own
# when there is none. The line after a calls= line is that call's cost,
# inclusive of all it called: "<position> <Ir>".
#
# An object is named by its ABSOLUTE path with every symlink resolved, so
# the program is compared by its resolved path too: $BIN is relative when
# --bin hands it over so, and goes through any symlink of TMPDIR's when it
# was built here, and compared as it was it matched no ob= line -- every
# count below was 0, and a function that wrote on every call printed
# "Syscalls: none". $BIN itself stays as it was given, for every message.
#
# Sets WRITES, MALLOCS, ALLOC_CALLS (malloc, free, calloc, realloc),
# ALLOC_IR, CB_CALLS and CB_IR.
WRITES=0; MALLOCS=0; ALLOC_CALLS=0; ALLOC_IR=0; CB_CALLS=0; CB_IR=0
_bin_real=$(readlink -f "$BIN")
eval "$(awk -v bin="$_bin_real" "$(rl_cg_awk)"'
	pending { pending = 0; if (what == "alloc") air += $2; else if (what == "cb") cbir += $2 }
	/^ob=/ { curob = named("ob", $0); next }
	/^fl=/ { curfl = named("fl", $0); curfi = curfl; next }
	/^f[ie]=/ { curfi = named("fl", $0); next }
	/^fn=/ { named("fn", $0)
		mine = (curob == bin && curfl !~ /^\/@harness@\//); curfi = curfl; next }
	/^cob=/ { cob = named("ob", $0); havecob = 1; next }
	/^cf[il]=/ { cfile = named("fl", $0); havecf = 1; next }
	/^cfn=/ { callee = named("fn", $0); next }
	/^calls=/ {
		split($0, a, "[= ]")
		toob = havecob ? cob : curob
		tofile = havecf ? cfile : curfi
		havecob = 0; havecf = 0
		what = ""
		pending = 1
		if (!mine) next
		if (toob == bin) {
			if (tofile ~ /^\/@harness@\// && callee !~ /@plt$/) { cbc += a[2]; what = "cb" }
			next
		}
		if (is_write(callee)) w += a[2]
		c = base(callee)
		if (c == "malloc") mc += a[2]
		if (c == "malloc" || c == "free" || c == "calloc" || c == "realloc") {
			ac += a[2]; what = "alloc"
		}
	}
	END { printf "WRITES=%.0f MALLOCS=%.0f ALLOC_CALLS=%.0f ALLOC_IR=%.0f CB_CALLS=%.0f CB_IR=%.0f\n",
		w, mc, ac, air, cbc, cbir }
' "$T/cg")"

PER_UNIT=$(awk -v i="$IR" -v w="$WORK" 'BEGIN { printf "%.1f", i / w }')
# The allocator's instructions are counted IN the figure -- a call the function
# makes is part of what it costs -- and also shown apart from it, never taken
# out silently: how many blocks to ask for is the student's choice on an axis of
# its own, and a figure with the allocator removed would hide that cost, while a
# figure with it in would blame the loop for it. The budget, a number measured
# on correct answers, is for the work the function itself does, so it is read
# against the figure without the allocator.
#
# The harness's callback is the other cost a figure can carry that is not the
# function's own: it is shown, and left out of the figure the budget is read
# against, the same way.
NET_UNIT=$(awk -v i="$IR" -v a="$ALLOC_IR" -v c="$CB_IR" -v w="$WORK" \
	'BEGIN { printf "%.1f", (i - a - c) / w }')
case "$ALLOC_CALLS:$CB_CALLS" in
	0:0) _without="" ;;
	*:0) _without="without the allocator" ;;
	0:*) _without="without the harness's callback" ;;
	*) _without="without the allocator or the harness's callback" ;;
esac
PER_CASE=$(awk -v x="$WRITES" -v c="$CASES" 'BEGIN { printf "%.2f", x / c }')

echo "cycles_check: $SYM over $CASES cases (built $OPT)."
echo "  A report: this layer never fails on what it measures, whatever the numbers."
if [ "$LEFT_OUT" -gt 0 ]; then
	echo "  ($LEFT_OUT case(s) of more than $MAX_UNIT ${UNIT_NAME}s each left out: they test capacity,"
	echo "   which the diff layers judge, and would make this figure measure their mix)"
fi
echo ""
printf '  instructions      : %s total, inclusive of everything it calls\n' "$IR"
_budget_note() {
	if [ -n "$BUDGET" ]; then
		printf '   (a good implementation manages about %s)\n' "$BUDGET"
	else
		printf '\n'
	fi
}
if [ -n "$_without" ]; then
	printf '  per %-14s: %s, everything included\n' "$UNIT_NAME" "$PER_UNIT"
	printf '  per %-14s: %s %s' "$UNIT_NAME" "$NET_UNIT" "$_without"
	_budget_note
else
	printf '  per %-14s: %s' "$UNIT_NAME" "$PER_UNIT"
	_budget_note
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
if [ "$ALLOC_CALLS" -gt 0 ]; then
	printf '  allocator         : %s instr in %s malloc()/free() calls (%s per call)\n' \
		"$ALLOC_IR" "$ALLOC_CALLS" \
		"$(awk -v a="$ALLOC_IR" -v c="$ALLOC_CALLS" 'BEGIN { printf "%.1f", a / c }')"
fi
if [ "$CB_CALLS" -gt 0 ]; then
	printf '  harness callback  : %s instr in %s calls to the function it was handed (%s per call)\n' \
		"$CB_IR" "$CB_CALLS" \
		"$(awk -v a="$CB_IR" -v c="$CB_CALLS" 'BEGIN { printf "%.1f", a / c }')"
fi
echo ""

# The budgets are NUMBERS, never a reference implementation. A target tells you
# where you stand; source code would tell you the answer, which is the one thing
# a test in this repo must never do.
#
# Read against the figure WITHOUT the allocator (or a callback), so "what is
# the loop doing" is asked only when the loop is what is over, never when the
# allocator is. The allocator's share is said beside it, as a cost and never as
# advice.
if [ -n "$BUDGET" ]; then
	awk -v got="$NET_UNIT" -v want="$BUDGET" -v u="$UNIT_NAME" -v ir="$IR" \
		-v air="$ALLOC_IR" -v cb="$CB_IR" -v w="$WORK" 'BEGIN {
		r = got / want
		if (r <= 1.3) printf "  You are at or near the budget for instructions per %s.\n", u
		else if (r <= 3) printf "  About %.1fx the budget per %s — some slack, nothing alarming.\n", r, u
		else printf "  About %.0fx the budget per %s. That is a lot of extra work per unit;\n  what is the loop doing that it need not?\n", r, u
		if (air > 0 && ir - cb > 0)
			printf "  With the allocator, %.1fx the budget per %s: malloc() and free() are\n  %.0f%% of what it costs. How many blocks to ask for is a choice, and that\n  is its price.\n", (ir - cb) / w / want, u, 100 * air / (ir - cb)
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
				print "  This function is not budgeted for a single syscall: this target"
				print "  measures it as a job that never talks to the kernel. Re-read what"
				print "  your subject says it produces, and where that result is meant to go."
			}
			exit
		}
		r = got / want
		if (r <= 1.3) print "  Syscalls are at budget."
		else printf "  %.0fx the syscall budget. Each one is a round trip into the kernel that\n  callgrind cannot even see the cost of — the instruction count above\n  UNDERSTATES what this costs in wall time.\n", r
	}'
fi
# What the figure can be read against depends on its unit. A unit of work
# (--unit-expr) is one every answer does the same amount of, so its cost is
# something a student can estimate: c_cycles' unit_expr reads only columns the
# harness's "Line:" names, and //tools:conventions reports one that reads a
# column the reference's corpus adds of its own ("A differential harness
# names its columns in the shape the diff layer reads"), budget or not. With
# none the figure is per case, which has no such floor, and saying "you know
# roughly what one unit costs" of it was false: it can be read against the
# student's own runs and nothing else.
echo ""
echo "  Instruction counts are exact and repeat run to run, and exclude the test"
echo "  harness — this is your function and what it calls, nothing else. Read the"
if [ -n "$UNIT_EXPR" ]; then
	echo "  per-$UNIT_NAME figure: it needs no reference, because you know roughly what"
	echo "  one unit of that work costs. A byte scan is a load, a compare and an"
	echo "  increment; a few instructions per byte is near the floor, thirty is not."
else
	echo "  per-$UNIT_NAME figure against your own runs: this target counts no unit of"
	echo "  work that every answer does the same amount of, so there is no floor to"
	echo "  read it against. Change one thing, run it again, and see which way it moves."
fi
echo ""
echo "  Kernel time is NOT in these counts, so the syscall numbers stand on their"
echo "  own: each write() is a round trip into the kernel, far dearer than the"
echo "  instructions around it, and a budget printed above is the count a good"
echo "  implementation stays within."
exit 0
