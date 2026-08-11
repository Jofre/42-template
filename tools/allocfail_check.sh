#!/bin/sh
# Allocation-failure layer (tag "allocfail") — run the deliverable repeatedly
# with ONE of its own malloc() calls forced to fail, and check it does what its
# subject says it must: report the error instead of using the pointer.
#
# ---------------------------------------------------------------------------
# THE HOLE THIS CLOSES
#
# Where a subject says "it should return a NULL pointer if an error occurs", no
# layer in this suite had ever executed that branch. The diff layers compare
# output; valgrind observes the
# success path; ASan observes the success path; ilp32 rebuilds the success path
# for 32-bit. malloc never once refused, on any exercise, in any layer — so an
# implementation that never looks at what malloc returned was byte-identical,
# leak-identical and sanitizer-identical to one that does. The NULL branch was
# not weakly tested, it was DEAD CODE, and dead code is the code most likely to
# be wrong: nothing has ever run it, including the person who wrote it.
#
# This layer makes the allocator say no, one allocation at a time.
#
# ---------------------------------------------------------------------------
# WHY IT IS OPT-IN PER EXERCISE, AND MUST STAY THAT WAY
#
# This header used to open by asserting that EVERY malloc exercise's subject
# carries that sentence. It does not, and the difference decides how this layer
# may be used. Across every C-Piscine subject (checked 2026-08-08) it is stated
# exactly once, in c-08 ex04 ft_strs_to_tab: "It should return a NULL pointer if
# an error occurs."
#
# c-07 is the instructive counter-example. Six of its exercises allocate, and
# the NULL returns its subject asks for are LOGICAL conditions — min >= max, an
# invalid base — never allocation failure. c-11, c-12 and c-13 say nothing about
# it at all. Turning this layer on for those would fail correct work against a
# requirement the harness invented, which is the same mistake every c_files
# block in this repo already refuses to make: "pinning them would invent a
# requirement."
#
# So it is wired per exercise via c_function(allocfail = ...), and the call site
# is expected to quote the sentence it is enforcing. ft_strdup is a genuinely
# arguable case — "Reproduce the behavior of the function strdup (man strdup)",
# and man strdup does say it returns NULL on error — but that is an inference
# across two documents, not a line of the subject, and it belongs to the repo
# owner rather than to whoever is next editing this file.
# ---------------------------------------------------------------------------
# WHAT IT ASSERTS — and, just as important, what it does not
#
# For each injected failure, exactly two things:
#   * the program did not crash, and
#   * the call reported the error (returned NULL, or whatever the harness's
#     af_case() translates the subject's error signal into).
#
# It does NOT ask the deliverable to release the blocks it had already taken
# before the failure hit. Not one subject in this repo requires that, and a test
# that demands it would be inventing a requirement — which is how a suite starts
# teaching students to write code for the suite instead of for the subject.
# Leaks on the SUCCESS path are a genuine requirement and are graded, by
# valgrind_test.sh, which owns that question. Nothing here looks at leaks at all.
#
# ---------------------------------------------------------------------------
# HOW IT WORKS
#
# tools/allocfail_shim.c supplies main() and a __wrap_malloc that counts the
# deliverable's allocations and refuses the n-th one, with n taken from AF_ARM.
# The mechanism, the scoping (why libc's and the harness's own allocations are
# not counted) and the harness contract — one function, `void *af_case(void)` —
# are all documented at length in that file. Read it before writing a harness.
#
# The sweep is two-phase on purpose:
#   1. DISCOVER. Run once with nothing armed and read back how many allocations
#      the deliverable made on this input. Call it K. K is a property of the
#      code under test, not something the wiring has to know and keep in sync —
#      an exercise whose implementation changes shape keeps being fully covered
#      without anyone editing a BUILD file.
#   2. SWEEP. Run once per n in 1..K, plus one control run at K+1 where the
#      injection cannot fire. The control is not ceremony: it proves the sweep
#      was bounded at the right place and that arming the shim at all does not
#      perturb a run, so a green from phase 2 cannot be a green from a broken
#      harness.
#
# Usage:
#   allocfail_check.sh --src FILE [--src FILE]... [--inc DIR]... --harness FILE
#                      --label TEXT [--max-inject N]
#                      [--gate-differ F --gate-bin P --gate-expected F
#                       [--gate-stdin F] [--gate-stream NAME]
#                       [--gate-sanitize] [--gate-labeled]]
#                      [--shim FILE] [--timeout SECS]
#
#   --src         a deliverable source. Compiled untouched, exactly as the other
#                 layers compile it; its malloc calls are the ones injected into.
#   --harness     the exercise's af_case() file (see allocfail_shim.c).
#   --inc DIR     added to the include path. Accepts a header FILE too and uses
#                 its directory -- Bazel's $(location) on an hdrs entry resolves
#                 to the file, and the compiler needs the directory. Same
#                 behaviour as symbols_test.sh and ilp32_test.sh, which carry
#                 the identical helper for the identical reason.
#   --label TEXT  what to call the thing under test in the report.
#   --max-inject  cap on the number of injections (at least 1), so a deliverable
#                 that allocates per element cannot make this layer unbounded.
#                 A cap of 0 is refused, not obeyed — see the check below.
#   --shim        override the path to allocfail_shim.c (normally found next to
#                 this script or under tools/ in the runfiles tree).
#
# Exit status:
#   0  the deliverable survived every injected failure — or the layer skipped
#      and said so
#   1  it crashed, hung, or handed back a pointer built on a failed allocation
#   2  the harness itself could not run the check
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "allocfail_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk basename cat dirname grep mktemp rm sed tr wc

SRCS=""
INCS=""
HARNESS=""
LABEL=""
SHIM=""
# 64 injections is far more than any exercise in this repo needs (a small
# ft_split harness makes a handful) and is still under a second of process
# spawns. The cap exists for the pathological case: a deliverable that allocates
# once per element, given a harness input someone later grows, would otherwise
# turn a bounded layer into an open-ended one. When K exceeds it the report says
# so rather than quietly narrowing what was checked.
MAX_INJECT="${ALLOCFAIL_MAX:-64}"
# Per-run wall clock. The classic wrong answer to a failed allocation, after
# "use it anyway", is to retry it in a loop; under injection that loop never
# ends. A hang has to be bounded and named, or it surfaces as an opaque Bazel
# kill with nothing a student can act on.
TIMEOUT="${ALLOCFAIL_TIMEOUT:-10}"
GATE_DIFFER=""
GATE_BIN=""
GATE_EXPECTED=""
GATE_PASS=""

# --inc takes either a directory or a header file: Bazel's $(location) on an
# hdrs entry resolves to the file, and the compiler needs its directory.
_dir() {
	if [ -d "$1" ]; then printf '%s\n' "$1"; else dirname "$1"; fi
}

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "allocfail_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--src) need "$1" "$#"; SRCS="$SRCS $2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--harness) need "$1" "$#"; HARNESS="$2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--inc) need "$1" "$#"; INCS="$INCS -I$(_dir "$2")"; shift 2 ;;
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--max-inject) need "$1" "$#"; MAX_INJECT="$2"; shift 2 ;;
		--shim) need "$1" "$#"; SHIM="$2"; shift 2 ;;
		--timeout) need "$1" "$#"; TIMEOUT="$2"; shift 2 ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-stdin) need "$1" "$#"; GATE_PASS="$GATE_PASS --stdin $2"; shift 2 ;;
		--gate-stream) need "$1" "$#"; GATE_PASS="$GATE_PASS --stream $2"; shift 2 ;;
		--gate-sanitize) GATE_PASS="$GATE_PASS --sanitize"; shift ;;
		--gate-labeled) GATE_PASS="$GATE_PASS --labeled"; shift ;;
		*) echo "allocfail_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

# Wiring mistakes are exit 2, never a student verdict: a missing data dep or a
# $(location) that resolved to nothing is not something a deliverable did.
[ -n "$HARNESS" ] || {
	echo "allocfail_check.sh: --harness is required" >&2
	exit 2
}
[ -n "$SRCS" ] || {
	echo "allocfail_check.sh: at least one --src is required" >&2
	exit 2
}
[ -f "$HARNESS" ] || {
	echo "allocfail_check.sh: no such harness file: $HARNESS" >&2
	exit 2
}
# The same rule has to apply to --src, and for the same reason. A --src that
# does not exist is a $(location) that resolved to nothing or a typo in a BUILD
# file — a wiring mistake, exactly like a missing --harness. Left unchecked it
# reaches the compiler, which says "no such file or directory", and the build
# branch below then reports FAIL (exit 1) with text inviting the student to go
# read the compile layer for a finding that does not exist there. Blaming a
# deliverable for a path the deliverable never chose is the one failure mode
# this layer can least afford: it exists to be believed about a branch nothing
# else executes, and a layer that cries wolf about wiring stops being believed.
for src in $SRCS; do
	[ -f "$src" ] || {
		echo "allocfail_check.sh: no such source file: $src" >&2
		echo "                    This is a wiring problem (a missing data dep or" >&2
		echo "                    a \$(location) that resolved to nothing), not a" >&2
		echo "                    finding about the deliverable." >&2
		exit 2
	}
done
[ -n "$LABEL" ] || LABEL="$(basename "$HARNESS" .c)"
case "$MAX_INJECT" in
	''|*[!0-9]*)
		echo "allocfail_check.sh: --max-inject must be a number: $MAX_INJECT" >&2
		exit 2 ;;
esac
# A cap of zero is refused rather than obeyed. Obeying it means sweeping nothing
# and then reporting PASS — and a PASS from this layer is a claim that the error
# path was executed and behaved, which would be false. This is the precise shape
# of the hole the layer was built to close (an assertion everyone believes has
# run, that never ran), so it must not be reintroduced by a configuration value.
# ALLOCFAIL_MAX=0 reaches here too, which is the point: an env var is the easiest
# way to silence a layer by accident.
if [ "$MAX_INJECT" -lt 1 ]; then
	echo "allocfail_check.sh: --max-inject must be at least 1 (got $MAX_INJECT)." >&2
	echo "                    A cap of zero would run no injection at all and then" >&2
	echo "                    report a pass — a green asserting that an error path" >&2
	echo "                    behaved, from a run that never reached it. If the" >&2
	echo "                    intent is to switch this layer off, do it in the" >&2
	echo "                    BUILD file where it is visible, not with a cap." >&2
	exit 2
fi
# --timeout is validated for the same reason and with more urgency than it looks
# to need: it is passed straight to timeout(1), which answers a malformed
# duration with exit 125 WITHOUT running anything. That status lands on the
# discovery run, which reads it as "the deliverable did not survive a plain
# run", and the layer then emits a SKIP that tells the student to go read the
# output and ASan layers. A typo in a BUILD file would be reported as a silent
# green pointing at the wrong exercise. Measured before this check existed.
case "$TIMEOUT" in
	''|*[!0-9]*)
		echo "allocfail_check.sh: --timeout must be a whole number of seconds:" >&2
		echo "                    $TIMEOUT" >&2
		exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Locate the shim. Under Bazel this script runs from the runfiles tree with the
# shim declared as a data dep, so it sits either beside the script or at
# tools/allocfail_shim.c from the runfiles root; run by hand from the workspace,
# the first candidate finds it. ALLOCFAIL_SHIM overrides everything.
if [ -z "$SHIM" ]; then
	for cand in \
		"${ALLOCFAIL_SHIM:-}" \
		"$(dirname "$0")/allocfail_shim.c" \
		"tools/allocfail_shim.c" \
		"${TEST_SRCDIR:-}/${TEST_WORKSPACE:-}/tools/allocfail_shim.c"; do
		if [ -n "$cand" ] && [ -f "$cand" ]; then
			SHIM="$cand"
			break
		fi
	done
fi
if [ -z "$SHIM" ] || [ ! -f "$SHIM" ]; then
	echo "allocfail_check.sh: cannot find allocfail_shim.c (looked beside this" >&2
	echo "                    script and under tools/). Pass --shim, or set" >&2
	echo "                    ALLOCFAIL_SHIM. This is a wiring problem, not a" >&2
	echo "                    finding about the deliverable." >&2
	exit 2
fi

# ---------------------------------------------------------------------------
# Toolchain. Any C compiler will do — this layer needs no sanitizer, only a
# linker that understands --wrap — but a silent green when none is present is
# the most expensive default available, because this is the ONLY layer that
# executes the error path at all. Same pattern and same reasoning as
# asan_check.sh: try the plausible compilers, then say loudly what did not run.
CC="${ALLOCFAIL_CC:-cc}"
if ! command -v "$CC" >/dev/null 2>&1; then
	for alt in cc gcc clang clang-12 gcc-10; do
		if command -v "$alt" >/dev/null 2>&1; then
			CC="$alt"
			break
		fi
	done
fi

command -v "$CC" >/dev/null 2>&1 || {
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no C compiler, so the allocation-failure sweep never"
		echo "             ran and this layer must not report a silent pass."
		exit 1
	}
	echo "allocfail_check: SKIP — no C compiler found (tried ALLOCFAIL_CC, cc,"
	echo "                 gcc, clang, clang-12, gcc-10)."
	echo "                 WARNING: the allocation-failure layer did NOT run."
	echo "                 Nothing else in this suite ever makes a malloc fail,"
	echo "                 so the subject's 'returns NULL if an error occurs'"
	echo "                 went unchecked. That is a real gap, not a pass."
	exit 0
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# ---------------------------------------------------------------------------
# Probe that --wrap actually works here, and RUN the probe rather than only
# linking it. A linker that accepted the flag and ignored it would leave every
# injection silently landing on the real allocator: every run would succeed,
# every exercise would go green, and the layer would assert precisely nothing
# while looking healthy. The probe's __wrap_malloc always refuses, so the probe
# exits 0 only if the interception is genuinely in effect.
cat > "$WORK/wrapprobe.c" <<'PROBE'
#include <stdlib.h>
void	*__wrap_malloc(size_t size);

void	*__wrap_malloc(size_t size)
{
	(void)size;
	return (0);
}

int	main(void)
{
	if (malloc(1) == 0)
		return (0);
	return (1);
}
PROBE
if ! "$CC" -O0 "$WORK/wrapprobe.c" -o "$WORK/wrapprobe" \
		-Wl,--wrap=malloc > "$WORK/wrap.err" 2>&1 || ! "$WORK/wrapprobe"; then
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: this toolchain's linker does not honour"
		echo "             -Wl,--wrap=malloc, so no allocation was ever failed"
		echo "             and nothing was checked. What it said:"
		sed -n '1,5p' "$WORK/wrap.err" | sed 's/^/    /'
		exit 1
	}
	echo "allocfail_check: SKIP — this linker does not honour -Wl,--wrap=malloc,"
	echo "                 which is how this layer makes an allocation fail."
	echo "                 WARNING: the error path the subject specifies was not"
	echo "                 executed. No other layer executes it either."
	exit 0
fi

# ---------------------------------------------------------------------------
# Correctness gate: run the exercise's own curated fixture first and SKIP while
# it is still red. Same shape, same flag names and the same fail-open rule as
# valgrind_test.sh and cycles_check.sh, so defs.bzl wires all three identically.
#
# The reason this layer in particular must be gated: a stub that returns NULL
# without allocating anything passes an allocation-failure sweep trivially and
# vacuously — there is nothing to inject into. Reporting that as a green would
# be the worst possible lie, and reporting it as a red would blame a student for
# not having written the function yet. It is neither; it is "come back when the
# output layer is green", which is what the skip says.
#
# Fails OPEN by design: no gate, or a gate that cannot run, means the sweep
# still runs. A gate that wrongly suppressed this layer would turn a real
# finding green, which is worse than duplicating a red.
if [ "${NO_SKIP:-0}" = "1" ]; then
	GATE_DIFFER=""
fi

if [ -n "$GATE_DIFFER" ] && [ -n "$GATE_BIN" ] && [ -n "$GATE_EXPECTED" ] &&
	[ -x "$GATE_BIN" ] && [ -f "$GATE_EXPECTED" ]; then
	# shellcheck disable=SC2086
	if ! sh "$GATE_DIFFER" --bin "$GATE_BIN" --expected "$GATE_EXPECTED" \
			$GATE_PASS >/dev/null 2>&1; then
		echo "allocfail_check: SKIP — this exercise's own output fixture is not"
		echo "                 passing yet."
		echo ""
		echo "  This layer asks what your function does when an allocation fails."
		echo "  That question only means something once it does the right thing"
		echo "  when the allocation SUCCEEDS — and a function that is still a stub"
		echo "  passes an allocation-failure sweep for the empty reason that it"
		echo "  never allocates. Get the *_output layer green and this one starts"
		echo "  checking something no other layer in this suite checks."
		echo ""
		echo "  (NO_SKIP=1 forces every gated layer to run anyway:"
		echo "   bazel test //... --test_env=NO_SKIP=1)"
		exit 0
	fi
fi

# ---------------------------------------------------------------------------
# Build.
#
# -O0 and -w, both deliberate. -O0 because this layer is about which branch runs,
# not about speed, and an unoptimised build keeps the malloc call sites in
# one-to-one correspondence with the source the student is about to re-read.
# -w because warnings are compile_check.sh's finding: a second red here for the
# same unused variable teaches nothing, and the -D below can produce diagnostics
# that belong to nobody.
#
# The harness — and ONLY the harness — is compiled with -Dmalloc=__real_malloc,
# so allocations the TEST code makes to build its inputs go straight to the real
# allocator: uncounted and never injected. Without it a harness that heap-builds
# a string would shift every injection index by one and would eventually swallow
# the injected NULL itself, crashing the scaffolding and reporting it as the
# student's failure. See allocfail_shim.c for the full account.
CFLAGS="-O0 -g -w"
OBJS=""
: > "$WORK/cc.err"
BUILD_OK=1
# Object names are NUMBERED, not derived from the basename. Two --src files can
# legitimately share one (a module wired with sources from two exercise
# directories), and a name collision would silently overwrite the first object
# and link the second one twice — surfacing as a duplicate-symbol error that
# reads as the student's mistake and is not.
OBJ_N=0
for src in $SRCS; do
	OBJ_N=$(( OBJ_N + 1 ))
	obj="$WORK/src$OBJ_N.o"
	# shellcheck disable=SC2086
	if ! "$CC" $CFLAGS $INCS -c "$src" -o "$obj" >> "$WORK/cc.err" 2>&1; then
		BUILD_OK=0
		break
	fi
	OBJS="$OBJS $obj"
done

if [ "$BUILD_OK" -eq 1 ]; then
	# shellcheck disable=SC2086
	"$CC" $CFLAGS $INCS -Dmalloc=__real_malloc -c "$HARNESS" \
		-o "$WORK/harness.o" >> "$WORK/cc.err" 2>&1 || BUILD_OK=0
fi
if [ "$BUILD_OK" -eq 1 ]; then
	# shellcheck disable=SC2086
	"$CC" $CFLAGS -c "$SHIM" -o "$WORK/shim.o" >> "$WORK/cc.err" 2>&1 || BUILD_OK=0
fi
if [ "$BUILD_OK" -eq 1 ]; then
	# shellcheck disable=SC2086
	"$CC" $OBJS "$WORK/harness.o" "$WORK/shim.o" -o "$WORK/probe" \
		-Wl,--wrap=malloc >> "$WORK/cc.err" 2>&1 || BUILD_OK=0
fi

if [ "$BUILD_OK" -ne 1 ]; then
	# Two of the ways this link fails are OUR mistakes, not the deliverable's,
	# and both are indistinguishable from a student error in the raw output. A
	# layer that blames a student for its own wiring is worse than one that does
	# not exist, so name them and exit 2.
	if grep -qa "multiple definition of .main" "$WORK/cc.err" 2>/dev/null; then
		echo "allocfail_check.sh: this deliverable defines main(), and so does the" >&2
		echo "                    shim, so the two cannot be linked together." >&2
		echo "                    This layer calls ONE function and inspects what" >&2
		echo "                    it returns; an exercise that is a whole program" >&2
		echo "                    has no such value, and should not be wired to it." >&2
		exit 2
	fi
	if grep -qa "undefined \(reference\|symbol\).*af_case" "$WORK/cc.err" 2>/dev/null; then
		echo "allocfail_check.sh: the harness does not define af_case()." >&2
		echo "                    The contract is one function:" >&2
		echo "                        void	*af_case(void);" >&2
		echo "                    It performs one call into the deliverable and" >&2
		echo "                    returns the pointer it produced, or NULL if the" >&2
		echo "                    deliverable reported the error. See the comment" >&2
		echo "                    block in tools/allocfail_shim.c." >&2
		exit 2
	fi
	echo "allocfail_check: FAIL — could not build the deliverable with the"
	echo "                 allocation-failure shim."
	echo "  The compile layer's report is the one to read first: if the function"
	echo "  does not build there either, this is the same finding seen twice."
	echo "  ---------------- compiler output ----------------"
	sed -n '1,30p' "$WORK/cc.err" | sed 's/^/  /'
	exit 1
fi

# ---------------------------------------------------------------------------
# Runner. An inner timeout so a loop that never ends is reported as one rather
# than as an opaque Bazel kill; not every host has GNU coreutils' `timeout`, so
# probe for it and run bare if absent — same pattern as valgrind_test.sh and
# diff_output.sh. Without it the only bound left is Bazel's own test timeout,
# which is a worse report but still a bounded one.
#
# Note what does NOT need this: a retry loop. The shim refuses exactly one
# request per run, so the retry's next attempt succeeds and the run finishes —
# it is caught by the "asked again" comparison in the sweep, not by the clock.
if command -v timeout >/dev/null 2>&1; then
	RUNNER="timeout -s KILL $TIMEOUT"
else
	RUNNER=""
fi

# Output cap: this runs code nobody has verified, on a path nobody has run, and
# a program that prints its own diagnostics in a runaway loop fills the test
# tmpdir at page-cache speed. `ulimit -f` bounds it at the source — the kernel
# kills the writer with SIGXFSZ (exit 153) the moment it goes past. It counts
# 512-byte blocks. The program's stdout goes to /dev/null: this layer reads a
# return value, not output; output is the diff layer's question.
CAP="${ALLOCFAIL_LOG_CAP:-1048576}"
BLOCKS=$(( CAP / 512 + 2 ))

RC=0
SEEN=0
RESULT=""
# run_arm <n> — run the probe with allocation <n> armed (0 arms nothing) and
# leave the verdict in RC / SEEN / RESULT. RESULT is empty when the program
# never reported, which is itself information: it means the call did not return.
#
# The whole function runs with ITS OWN stderr on /dev/null (the redirection on
# the closing brace). That does not discard the probe's stderr — the inner
# `2> "$WORK/err"` captures that explicitly, before this takes effect. What it
# suppresses is the shell's job-control notice: a shell prints "Segmentation
# fault" of its own accord when a foreground child dies on a signal, and here a
# crash is the expected case rather than an accident. Left in, a failing
# exercise printed one bare "Segmentation fault" line per injection ahead of a
# report that names the same signal precisely — and out of order with it, the
# two going to different streams. The redirection belongs on the function rather
# than on the subshell because a shell may exec the last command of a subshell
# in place, in which case the notice comes from the shell running THIS function
# and not from the subshell at all (verified on both dash and bash).
run_arm() {
	: > "$WORK/err"
	(
		ulimit -f "$BLOCKS" 2>/dev/null
		# shellcheck disable=SC2086
		AF_ARM="$1" $RUNNER "$WORK/probe" > /dev/null 2> "$WORK/err"
	)
	RC=$?
	# The LAST report line, so a harness that writes its own diagnostics to
	# stderr cannot be mistaken for the shim.
	#
	# One awk rather than `grep | tail`, and the reason is worth stating: every
	# way this parse can come back empty is reported as "the call never
	# returned", so a missing utility would be indistinguishable from a
	# deliverable that called exit(). Measured, with `tail` absent from PATH the
	# layer reported a correct implementation as having ended early. awk is
	# already required further down for the report, so this both shortens the
	# pipeline and leaves one dependency where there were three.
	line=$(awk '/^AF_RESULT /{ last = $0 } END { print last }' "$WORK/err" 2>/dev/null)
	if [ -n "$line" ]; then
		SEEN=$(echo "$line" | sed -n 's/.* seen=\([0-9]*\).*/\1/p')
		RESULT=$(echo "$line" | sed -n 's/.* result=\([a-z]*\).*/\1/p')
	else
		SEEN=0
		RESULT=""
	fi
	[ -n "$SEEN" ] || SEEN=0
} 2>/dev/null

# How a non-zero status is described. A status above 128 is 128+signal: the
# program was KILLED, it did not return, and under injection the overwhelmingly
# likely signal is the one you get for using an address the allocator never gave
# you.
signal_name() {
	# Kept short on purpose: these strings go in a table column, and the report
	# has to stay inside 80 columns to be readable in a terminal. What SIGSEGV
	# means on THIS path is explained once, below the table, instead of being
	# repeated on every row.
	case "$1" in
		132) echo "SIGILL (illegal instruction)" ;;
		134) echo "SIGABRT (abort: heap error or assertion)" ;;
		136) echo "SIGFPE (arithmetic error)" ;;
		139) echo "SIGSEGV (invalid memory access)" ;;
		137) echo "SIGKILL (killed)" ;;
		*)
			if [ "$1" -gt 128 ]; then
				echo "signal $(( $1 - 128 ))"
			else
				echo "exit status $1"
			fi ;;
	esac
}

# How to describe a run that ended without the call ever returning. Status 0 is
# its own case: the process finished cleanly and simply never came back to its
# caller, which is what an exit() inside the deliverable looks like. Rendering
# that as "exit status 0" would read as though nothing had gone wrong.
ended_how() {
	if [ "$1" -ne 0 ]; then
		signal_name "$1"
	else
		echo "it exited 0 without returning"
	fi
}

# ---------------------------------------------------------------------------
# Phase 1 — DISCOVER. Nothing armed: how many allocations does this input cost?
run_arm 0
BASE_RC=$RC
BASE_WHY="$(ended_how "$BASE_RC")"
if [ "$BASE_RC" -ne 0 ] || [ -z "$RESULT" ]; then
	# The deliverable does not survive its own harness with NOTHING injected.
	# That is a real problem but it is not THIS layer's finding — the output,
	# ASan and valgrind layers all run that same success path and are built to
	# explain it. Saying "your error path is broken" about a program that never
	# reached the error path would be a lie with a confident tone.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: the harness did not complete a plain run with nothing"
		echo "             injected ($BASE_WHY), so no allocation"
		echo "             failure was ever tested. Read the output/ASan layers"
		echo "             for this exercise first."
		exit 1
	}
	echo "allocfail_check: SKIP — the harness did not complete even with nothing"
	echo "                 injected ($BASE_WHY)."
	echo "  This layer only asks what happens when an allocation FAILS. Something"
	echo "  is already wrong on the path where they all succeed, and the output,"
	echo "  ASan and valgrind layers are the ones that explain that."
	exit 0
fi

if [ "$RESULT" = "null" ]; then
	# It reported the error without anything having failed. There is no success
	# path to interrupt, so there is nothing here to inject into.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: the deliverable already reports failure when NOTHING is"
		echo "             injected, so the allocation-failure sweep had no"
		echo "             success path to interrupt and checked nothing."
		exit 1
	}
	echo "allocfail_check: SKIP — with nothing injected, the call already reports"
	echo "                 failure, so there is no success path to interrupt."
	echo "  A stub that returns NULL passes an allocation-failure sweep for the"
	echo "  emptiest of reasons. The *_output layer is the one to read now."
	exit 0
fi

K=$SEEN
if [ "$K" -eq 0 ]; then
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: the deliverable made no allocation on this input, so"
		echo "             there was nothing to fail and nothing was checked."
		echo "             If it should be allocating, suspect the harness input"
		echo "             or the wiring, not the sweep."
		exit 1
	}
	echo "allocfail_check: SKIP — the deliverable made no allocation on this"
	echo "                 input, so there is nothing to fail."
	echo "  If this function is supposed to allocate, the harness's af_case() is"
	echo "  probably giving it an input that takes an early exit."
	exit 0
fi

SWEPT=$K
TRUNCATED=0
if [ "$K" -gt "$MAX_INJECT" ]; then
	SWEPT=$MAX_INJECT
	TRUNCATED=1
fi

# ---------------------------------------------------------------------------
# Phase 2 — SWEEP. One run per injected failure; the verdict for each goes into
# a small table so the report can say WHICH allocation was the unguarded one
# rather than only that something went wrong. That distinction is the whole
# pedagogic value: "#3 of 4" points at a line.
: > "$WORK/sweep"
FAILURES=0
HUNG=0
KEPT_ASKING=0
CRASHED=0
INCONCLUSIVE=""
n=1
while [ "$n" -le "$SWEPT" ]; do
	run_arm "$n"
	if [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; then
		printf '%s\tHUNG\tnever returned — still running after %ss\n' \
			"$n" "$TIMEOUT" >> "$WORK/sweep"
		FAILURES=$(( FAILURES + 1 ))
		# One hang is a definitive finding and every further injection would
		# cost another full timeout, so stop here rather than spending minutes
		# re-learning it.
		HUNG=1
		break
	elif [ "$RC" -eq 153 ]; then
		printf '%s\tFLOOD\twrote more than %s bytes and was stopped\n' \
			"$n" "$CAP" >> "$WORK/sweep"
		FAILURES=$(( FAILURES + 1 ))
	elif [ "$RC" -gt 128 ]; then
		printf '%s\tCRASH\tkilled by %s\n' "$n" "$(signal_name "$RC")" \
			>> "$WORK/sweep"
		FAILURES=$(( FAILURES + 1 ))
		CRASHED=1
	elif [ -z "$RESULT" ]; then
		# It ended without the shim ever reporting: the call never returned to
		# its caller. Ending the process is not the same as returning NULL to
		# whoever called you, and no correct implementation does it, so this is
		# a finding rather than a skip.
		printf '%s\tNORETURN\tthe call never returned (%s)\n' \
			"$n" "$(ended_how "$RC")" >> "$WORK/sweep"
		FAILURES=$(( FAILURES + 1 ))
	elif [ "$SEEN" -lt "$n" ]; then
		# The injection never fired: this run asked for fewer allocations than
		# the baseline did, so execution diverged for a reason that is not the
		# injection. Nothing can be concluded from the result, and concluding
		# anything anyway would risk reddening a correct implementation — which
		# is a worse outcome than the hole this layer exists to close.
		INCONCLUSIVE="injection #$n never fired (the run made only $SEEN allocation(s))"
		break
	elif [ "$RESULT" = "ptr" ]; then
		# Two different mistakes land here and they deserve different words.
		# seen == n: the refusal was the last request made, so the pointer that
		#   came back was built on top of it.
		# seen > n : the function was refused and then went on asking. That is
		#   either a retry loop or a fill loop that never noticed, and calling
		#   it "still returned a pointer" without saying so would describe the
		#   symptom while hiding the decision that caused it. Note the shim
		#   refuses exactly ONE request per run, so a retry's second attempt
		#   succeeds — which is why a retry loop shows up here rather than as a
		#   hang, and why the count of extra requests is worth printing.
		if [ "$SEEN" -gt "$n" ]; then
			printf '%s\tNOT-NULL\tit was refused, asked %s more time(s), and returned a pointer\n' \
				"$n" "$(( SEEN - n ))" >> "$WORK/sweep"
			KEPT_ASKING=1
		else
			printf '%s\tNOT-NULL\tallocation #%s failed, and it still returned a pointer\n' \
				"$n" "$n" >> "$WORK/sweep"
		fi
		FAILURES=$(( FAILURES + 1 ))
	else
		printf '%s\tok\treturned NULL, no crash\n' "$n" >> "$WORK/sweep"
	fi
	n=$(( n + 1 ))
done

if [ -n "$INCONCLUSIVE" ]; then
	echo "allocfail_check.sh: could not draw a conclusion for $LABEL:" >&2
	echo "                    $INCONCLUSIVE" >&2
	echo "                    The plain run allocated $K time(s), so the same run" >&2
	echo "                    with a later allocation armed should have reached" >&2
	echo "                    the same point. Something makes this deliverable" >&2
	echo "                    take a different path from one run to the next —" >&2
	echo "                    reading uninitialised memory is the usual cause," >&2
	echo "                    and valgrind's layer is the one that names it." >&2
	echo "                    Reporting a verdict on a run whose injection never" >&2
	echo "                    fired would be worse than reporting none." >&2
	exit 2
fi

# ---------------------------------------------------------------------------
# The control run. Arm one past the last allocation the deliverable makes: the
# refusal cannot fire, so this run must behave exactly like the plain one. It is
# what stops a green here from being a green produced by a broken sweep — if
# arming the shim perturbed a run by itself, or if the count K were wrong, this
# is where it shows.
if [ "$TRUNCATED" -eq 0 ] && [ "$HUNG" -eq 0 ]; then
	run_arm $(( K + 1 ))
	if [ "$RC" -ne 0 ] || [ "$RESULT" != "ptr" ]; then
		echo "allocfail_check.sh: the control run is not trustworthy for $LABEL." >&2
		echo "                    Arming allocation #$(( K + 1 )) cannot refuse anything," >&2
		echo "                    because the plain run only made $K, so this run should" >&2
		echo "                    have been identical to the plain one. It was not" >&2
		echo "                    (status $RC, result '${RESULT:-none}')." >&2
		echo "                    Every verdict above rests on the sweep being" >&2
		echo "                    bounded where the allocations end, so no verdict" >&2
		echo "                    is reported at all." >&2
		exit 2
	fi
fi

# ---------------------------------------------------------------------------
# Report.
if [ "$FAILURES" -eq 0 ]; then
	# The truncated case gets its own headline, not a footnote under a shared
	# one. "Survived every failed allocation" is a claim about all K of them; on
	# a truncated sweep it is not true, and the FIRST line is the part that
	# survives being quoted, skimmed, or reduced to one line in a Bazel summary
	# where the body never appears at all. A green that covered a fifth of the
	# allocations must not be able to read like a green that covered all of
	# them — that is this layer's own founding complaint about the suite it
	# joined, and it would be a poor joke to reproduce it here.
	if [ "$TRUNCATED" -eq 1 ]; then
		echo "allocfail_check: PASS (partial) — $LABEL survived injections 1..$SWEPT"
		echo "                 It asks for memory $K time(s) on this input, and each"
		echo "                 of the first $SWEPT injections refused one of those"
		echo "                 requests; every time, the call reported the error and"
		echo "                 nothing crashed."
		echo "                 Allocations $(( SWEPT + 1 ))..$K were NOT exercised: the sweep is"
		echo "                 bounded at $MAX_INJECT injections (--max-inject). This green"
		echo "                 covers $SWEPT of $K, not all of them."
	else
		echo "allocfail_check: PASS — $LABEL survived every failed allocation"
		echo "                 It asks for memory $K time(s) on this input. Injections"
		echo "                 1..$SWEPT each refused one of those requests; every time,"
		echo "                 the call reported the error and nothing crashed."
		echo "                 The control run (#$(( K + 1 )), which cannot fail) still"
		echo "                 returned a valid pointer, so the sweep was bounded"
		echo "                 where the allocations actually end."
	fi
	exit 0
fi

echo "allocfail_check: FAIL — $LABEL did not survive a failed allocation"
echo ""
# The label is not repeated in this sentence on purpose: it can be long, and the
# line has to stay inside 80 columns for a report that is read in a terminal.
echo "  On this input the deliverable asks for memory $K time(s). Each run below"
echo "  is the SAME input, with exactly one of those requests refused:"
echo ""
# Short sweeps print in full: the rows that PASSED are the interesting context
# for the ones that did not ("#1 was fine, #2 onwards were not" points at a
# line). Long sweeps would bury the report under forty identical crash rows, so
# they print the first few failures and then say honestly how many of each kind
# were left out — a truncation that does not say what it dropped is how a report
# starts being read as the whole story.
ROWS=$(wc -l < "$WORK/sweep" | tr -d ' ')
if [ "$ROWS" -le 24 ]; then
	awk -F'\t' '{ printf "    #%-4s %-9s %s\n", $1, $2, $3 }' "$WORK/sweep"
else
	awk -F'\t' -v shown=12 '
		$2 != "ok" {
			bad++
			if (bad <= shown)
				printf "    #%-4s %-9s %s\n", $1, $2, $3
		}
		$2 == "ok" { good++ }
		END {
			if (bad > shown)
				printf "    (%d further injection(s) failed too, not listed)\n", bad - shown
			if (good > 0)
				printf "    (%d injection(s) were handled correctly, not listed)\n", good
		}' "$WORK/sweep"
fi
echo ""
if [ "$TRUNCATED" -eq 1 ]; then
	echo "  Only the first $SWEPT of $K allocations were injected (--max-inject)."
	echo ""
fi
echo "  WHAT CHANGED, AND WHAT DID NOT"
echo "  The input did not change. The code did not change. The only difference"
echo "  from a normal run is that one call to malloc answered NULL — which the"
echo "  real allocator is allowed to do at any time, and does under memory"
echo "  pressure, on a request for a size that came out wrong, or when the"
echo "  process is at its limit."
echo ""
echo "  malloc's return value is not a formality: it is the allocator's ANSWER,"
echo "  and \"no\" is one of the answers it is permitted to give. Code that stores"
echo "  that answer in a pointer and then uses the pointer regardless has decided"
echo "  that \"no\" cannot happen. Your subject decides otherwise — find the"
echo "  sentence about what this function returns \"if an error occurs\"; that"
echo "  sentence is the standard being applied here, not a house style."
echo ""
if [ "$CRASHED" -eq 1 ]; then
	echo "  WHAT THE CRASH ROWS MEAN"
	echo "  SIGSEGV on this path is not a mystery to debug: NULL is address zero,"
	echo "  and address zero is deliberately mapped to nothing at all so that"
	echo "  using it is caught instantly rather than corrupting something. The"
	echo "  program wrote to (or read from) the address the allocator handed back"
	echo "  when it declined the request, as though it were memory it owned."
	echo "  Which is to say: the crash is not a second bug on top of the missing"
	echo "  check — it IS the missing check, seen from the outside."
	echo ""
fi
if [ "$KEPT_ASKING" -eq 1 ]; then
	echo "  ONE OF THOSE RUNS KEPT ASKING"
	echo "  A row above shows the function being refused and then requesting"
	echo "  memory again before returning a pointer. Only ONE request is refused"
	echo "  per run here, so the next one succeeded and the run finished — on a"
	echo "  machine that is genuinely out of memory it would not have. Asking"
	echo "  again is a bet that the allocator's answer will change on its own;"
	echo "  the contract in the subject is that the function tells its CALLER,"
	echo "  who is the one with the context to decide what happens next. Ask"
	echo "  yourself which of the two your code is doing, and which one the"
	echo "  sentence in the subject describes."
	echo ""
fi
echo "  WHY YOU HAVE NEVER SEEN THIS FAIL BEFORE"
echo "  Because until this run, nothing had ever executed that path. Every other"
echo "  layer — the output diff, the fuzzer, ASan, valgrind, the 32-bit build —"
echo "  ran with an allocator that always said yes. An error path that nothing"
echo "  has ever run is not weakly tested code, it is code that has never"
echo "  executed once, including on the machine of the person who wrote it. That"
echo "  is exactly where mistakes survive."
echo ""
echo "  For each failing row above, the number is WHICH request was refused: #1"
echo "  is the first malloc the function reaches on this input, #2 the second."
echo "  Count them in your own source and look at what happens to the value of"
echo "  the one that was refused."
echo ""
echo "  (What this layer does NOT ask: it does not require you to release blocks"
echo "  you had already obtained before the failure. No subject here asks for"
echo "  that, so it is not graded here. Leaks on the success path are graded, by"
echo "  the valgrind layer.)"
exit 1
