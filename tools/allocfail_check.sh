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
# Not every malloc exercise's subject says what the function does when an
# allocation fails, and the ones that do say it differently: C 08 ex04 in its
# own words ("It should return a NULL pointer if an error occurs"), C 07 ex02
# as a value ("The size of range should be returned (or -1 on error)"), C 07
# ex00 and Reloaded ex20 through the man page their subject sends you to (man
# strdup: "It returns NULL if insufficient memory was available"). Most say
# nothing at all, or ask for NULL on LOGICAL conditions -- min >= max, an
# invalid base -- never on a failed allocation. Turning this layer on for
# those would fail correct work against a requirement the harness invented.
#
# So it is wired per exercise via c_function(allocfail = ...), and the call
# site quotes the sentence it enforces (allocfail_rule), which reaches
# this runner as --rule and is the one sentence its report quotes. This
# runner is shared, and a sentence written into it for one subject was once
# quoted at every other (finding 082).
# ---------------------------------------------------------------------------
# WHAT IT ASSERTS — and, just as important, what it does not
#
# For each injected failure, exactly two things:
#   * the program did not crash, and
#   * the call reported the error (returned NULL, or whatever the harness's
#     af_case() translates the subject's error signal into).
#
# It does NOT ask the deliverable to release the blocks it had already taken
# before the failure hit. Not one subject in this repo requires that, and no
# memory checker at 42 ever sees a refused allocation, so a basic layer that
# demanded it would be inventing a requirement — which is how a suite starts
# teaching students to write code for the suite instead of for the subject.
# Leaks on the SUCCESS path are valgrind_test.sh's question, at strict: a
# rule it states as this repo's where the subject has no sentence for it (an
# evaluator may run a memory checker), and as the subject's own words where
# one has (Rush 02's, the call site's memory_rule).
#
# --leaks asks it, as a separate target (exNN_allocfail_leaks, at `robust`:
# this repo's own rigour, never the subject's), and only where the subject
# lets the function call free(). It runs the same sweep with free() wrapped
# too, so the shim can say which blocks the function obtained and never
# released, and judges ONE thing on each run that reported the error: whether
# any of them are still live. How a run ended is judged as everywhere (a
# crash or a hang fails); a run that did not report the error is the basic
# target's finding, NOT JUDGED here, so one mistake is not red twice over.
# Finding 084: a function that leaked every earlier copy on its error path was
# green on every layer, and the PASS line did not say what it had not asked.
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
#   allocfail_check.sh --cc PATH [--cc-lib FILE]... [--cc-under FILE]
#                      --ld PATH --ld-lib FILE...
#                      --src FILE [--src FILE]... [--inc DIR]... --harness FILE
#                      --label TEXT [--max-inject N]
#                      [--gate-differ F --gate-bin P --gate-expected F
#                       [--gate-stdin F] [--gate-stream NAME]
#                       [--gate-sanitize] [--gate-labeled]]
#                      [--shim FILE] [--timeout SECS] [--leaks] [--rule FILE]
#   allocfail_check.sh --bin PROG [--stdin FILE] [--argv-file FILE]
#                      [--run-as NAME [--cwd-file DEST=PATH]...]
#                      [--show-run PROG] [--label TEXT] [--leaks]
#                      [--rule FILE] [gate options as above] -- [ARG...]
#
#   --cc, --cc-lib, --cc-under, --ld, --ld-lib
#                 with --src, the pinned clang-12 and binutils 2.38 Bazel
#                 fetched, each with the libraries it loads: the probe is
#                 compiled and linked with them (tools/runner_lib.sh's
#                 rl_cc_pin and rl_ld_pin), never with a compiler or linker
#                 the box has. Required with --src; --bin builds nothing.
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
#                 Past it the sweep SAMPLES -- the first requests, then spread
#                 evenly to the last (af_points) -- and the report says so.
#                 A cap of 0 is refused, not obeyed — see the check below.
#   --shim        override the path to allocfail_shim.c (normally found next to
#                 this script or under tools/ in the runfiles tree).
#   --leaks       judge what the function left allocated on each run that
#                 reported the error, instead of whether it reported it (see
#                 WHAT IT ASSERTS above).
#   --rule FILE   why this target asks it, in its call site's words: a file
#                 (a names_file the macro writes) holding the subject's own
#                 sentence, naming where it is from -- or the man page it
#                 cites, or the call site's reading of a subject that has
#                 none. Printed under the verdict, and nothing else is quoted
#                 as the standard applied. Without it the report quotes no
#                 subject at all: this runner cannot know which subject it is
#                 reading, and a sentence written into it was once printed for
#                 every exercise and program, C 10's included, whose subject
#                 has no such sentence (finding 082). The same option, and the
#                 same file, as valgrind_test.sh's --rule.
#   --bin PROG    a PROGRAM, run on ARG... (and --stdin), instead of a
#                 function's probe: see "A PROGRAM" below.
#   --argv-file, --run-as, --cwd-file, --show-run
#                 with --bin, the run the case describes, as diff_output.sh
#                 takes them: more arguments from a file, and a folder of its
#                 own to run the program from as ./NAME, holding each
#                 --cwd-file. The gate is handed the same three, so it runs
#                 the case as its output test does (c_program's _case_run).
#                 Rush 02's one-argument cases run beside numbers.dict, and a
#                 sweep that ran them from no such folder refused nothing but
#                 the missing-dictionary path's requests, and its gate, red on
#                 every correct program, skipped it.
#
# A harness whose subject's error is not a pointer says in words what the
# call returned (allocfail_shim.c's af_note); a row where the function
# returned the wrong value is then WRONG-RET, with those words, and never
# "returned a pointer" (finding 075).
#
# Exit status:
#   0  the deliverable survived every injected failure — or the layer skipped
#      and said so
#   1  it crashed, hung, or handed back a pointer built on a failed allocation
#      (or, for a harness with a note, a value other than the error)
#      -- or, with --leaks, crashed, hung, or left a block allocated on a run
#      that reported the error
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
require awk basename cat cp dirname grep mktemp rm sed tr wc

# The shared runner helpers -- time budget, exiting signal traps, how a run
# ended, excerpts, hints -- written once in tools/runner_lib.sh.
RL_NAME=allocfail_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "allocfail_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool CC -- the pinned compiler: it builds, and runs none of what it builds
# conventions: harness tool GATE_DIFFER -- tools/diff_output.sh, the output gate, which keeps this test's budget (RL_DEADLINE)

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
LEAKS=0
PROG=""
PSTDIN=""
RULE=""
ARGV_FILE=""
RUN_AS=""
CWD_FILES=""
SHOW_RUN=""
CC=""
CC_LIBS=""
CC_UNDER=""
LD=""
LD_LIBS=""

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
		--src) need "$1" "$#"; rl_list_add SRCS "$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--harness) need "$1" "$#"; HARNESS="$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--inc) need "$1" "$#"; rl_list_add INCS "-I$(_dir "$2")"; shift 2 ;;
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--max-inject) need "$1" "$#"; MAX_INJECT="$2"; shift 2 ;;
		--shim) need "$1" "$#"; SHIM="$2"; shift 2 ;;
		--timeout) need "$1" "$#"; TIMEOUT="$2"; shift 2 ;;
		--leaks) LEAKS=1; shift ;;
		--rule)
			need "$1" "$#"
			[ -s "$2" ] || { echo "allocfail_check.sh: no sentence in --rule $2" >&2; exit 2; }
			RULE="$2"; shift 2 ;;
		--bin) need "$1" "$#"; PROG="$2"; shift 2 ;;
		--stdin) need "$1" "$#"; PSTDIN="$2"; shift 2 ;;
		--argv-file) need "$1" "$#"; ARGV_FILE="$2"; rl_list_add GATE_PASS --argv-file "$2"; shift 2 ;;
		--run-as) need "$1" "$#"; RUN_AS="$2"; rl_list_add GATE_PASS --run-as "$2"; shift 2 ;;
		--cwd-file) need "$1" "$#"; CWD_FILES="$CWD_FILES
$2"; rl_list_add GATE_PASS --cwd-file "$2"; shift 2 ;;
		--show-run) need "$1" "$#"; SHOW_RUN="$2"; shift 2 ;;
		--gate-expected-alt) need "$1" "$#"; rl_list_add GATE_PASS --expected-alt "$2"; shift 2 ;;
		--) shift; break ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-stdin) need "$1" "$#"; rl_list_add GATE_PASS --stdin "$2"; shift 2 ;;
		--gate-stream) need "$1" "$#"; rl_list_add GATE_PASS --stream "$2"; shift 2 ;;
		--gate-sanitize) rl_list_add GATE_PASS --sanitize; shift ;;
		--gate-labeled) rl_list_add GATE_PASS --labeled; shift ;;
		--cc) need "$1" "$#"; CC="$2"; shift 2 ;;
		--cc-lib) need "$1" "$#"; rl_list_add CC_LIBS "$2"; shift 2 ;;
		--cc-under) need "$1" "$#"; CC_UNDER="$2"; shift 2 ;;
		--ld) need "$1" "$#"; LD="$2"; shift 2 ;;
		--ld-lib) need "$1" "$#"; rl_list_add LD_LIBS "$2"; shift 2 ;;
		*) echo "allocfail_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

# Wiring mistakes are exit 2, never a student verdict: a missing data dep or a
# $(location) that resolved to nothing is not something a deliverable did.
if [ -n "$PROG" ]; then
	[ -z "$HARNESS$SRCS" ] || {
		echo "allocfail_check.sh: --bin runs a program as it was built; --harness and" >&2
		echo "                    --src build a function's probe. Not both." >&2
		exit 2
	}
	[ -f "$PROG" ] || {
		echo "allocfail_check.sh: no such program: $PROG (a wiring problem)" >&2
		exit 2
	}
	[ -z "$PSTDIN" ] || [ -f "$PSTDIN" ] || {
		echo "allocfail_check.sh: no such --stdin file: $PSTDIN (a wiring problem)" >&2
		exit 2
	}
	# The run as the case describes it, or no run (diff_output.sh says why).
	[ -z "$ARGV_FILE" ] || [ -r "$ARGV_FILE" ] || {
		echo "allocfail_check.sh: --argv-file '$ARGV_FILE' is not readable" >&2
		exit 2
	}
	if [ -n "$CWD_FILES" ] && [ -z "$RUN_AS" ]; then
		echo "allocfail_check.sh: --cwd-file stages a file in the folder --run-as runs the program from" >&2
		exit 2
	fi
	case "$RUN_AS" in
		*/* | . | ..)
			echo "allocfail_check.sh: --run-as takes the program's file name, not '$RUN_AS'" >&2
			exit 2 ;;
	esac
	[ -n "$LABEL" ] || LABEL="$(basename "$PROG")"
	[ -z "$CC$LD" ] || {
		echo "allocfail_check.sh: --bin runs a program as it was built; --cc and --ld" >&2
		echo "                    build a function's probe. Not both." >&2
		exit 2
	}
else
[ -n "$CC" ] || { echo "allocfail_check.sh: --cc is required with --src (the pinned clang-12)" >&2; exit 2; }
[ -n "$LD" ] || { echo "allocfail_check.sh: --ld is required with --src (the pinned ld.bfd)" >&2; exit 2; }
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
# (The lists are one word per line: runner_lib.sh's LISTS OF WORDS.)
rl_split_on
for src in $SRCS; do
	[ -f "$src" ] || {
		echo "allocfail_check.sh: no such source file: $src" >&2
		echo "                    This is a wiring problem (a missing data dep or" >&2
		echo "                    a \$(location) that resolved to nothing), not a" >&2
		echo "                    finding about the deliverable." >&2
		exit 2
	}
done
rl_split_off
[ -n "$LABEL" ] || LABEL="$(basename "$HARNESS" .c)"
fi
[ -n "$PROG" ] || [ $# -eq 0 ] || {
	echo "allocfail_check.sh: arguments after -- are a program's (--bin); a function's" >&2
	echo "                    probe takes none: $*" >&2
	exit 2
}
[ -n "$PROG" ] || [ -z "$ARGV_FILE$RUN_AS$CWD_FILES$SHOW_RUN$PSTDIN" ] || {
	echo "allocfail_check.sh: --stdin, --argv-file, --run-as, --cwd-file and --show-run" >&2
	echo "                    shape a program's run (--bin); a function's probe takes none." >&2
	exit 2
}
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

# What the report calls the thing under test.
WHAT=function
[ -z "$PROG" ] || WHAT=program

WORK=$(mktemp -d)
# Absolute: a program's run may be made from a folder of its own (--run-as),
# and the shim's report and the captured streams are named from here.
case "$WORK" in /*) ;; *) WORK="$PWD/$WORK" ;; esac
rl_traps 'rm -rf "$WORK"'

# ---------------------------------------------------------------------------
# Runner. An inner timeout so a loop that never ends is reported as one rather
# than as an opaque Bazel kill: --timeout per run, or what is left of the test's
# own limit if that is less (rl_tmo, in run_arm).
#
# Note what does NOT need this: a retry loop. The shim refuses exactly one
# request per run, so the retry's next attempt succeeds and the run finishes —
# it is caught by the "asked again" comparison in the sweep, not by the clock.

# Output cap: this runs code nobody has verified, on a path nobody has run, and
# a program that prints its own diagnostics in a runaway loop fills the test
# tmpdir at page-cache speed. `ulimit -f` bounds it at the source — the kernel
# kills the writer with SIGXFSZ (exit 153) the moment it goes past. It counts
# 512-byte blocks. A function probe's stdout goes to /dev/null: this layer
# reads a return value, not output; output is the diff layer's question. A
# program's goes to a file, under the same cap: "bounded output" is one of the
# three things its sweep asks.
CAP="${ALLOCFAIL_LOG_CAP:-1048576}"
BLOCKS=$(( CAP / 512 + 2 ))

RC=0
SEEN=0
RESULT=""
NOTE=""
LIVE=0
BYTES=0
WRAPPED=""
# run_arm <n> [ARG...] — run the probe with allocation <n> armed (0 arms
# nothing) and leave the verdict in RC / SEEN / RESULT / NOTE / LIVE / BYTES. RESULT is
# empty when the program never reported, which is itself information: for a
# function, the call did not return; for a program (--bin, run with ARG... on
# --stdin), it ended without returning from main() or calling exit().
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
	# No time left to start this run: say where the sweep got to, and stop.
	# (This function's own stderr is /dev/null -- see above -- so it says it on
	# stdout, which is where the report goes.)
	if ! rl_tmo "$TIMEOUT"; then
		if [ "$1" = 0 ]; then
			rl_overrun "the plain run, with nothing injected"
		else
			rl_overrun "injection #$1"
		fi
		exit 1
	fi
	_arm=$1
	shift
	rm -f "$WORK/report"
	(
		ulimit -f "$BLOCKS" 2>/dev/null
		AF_ARM="$_arm"
		AF_REPORT="$WORK/report"
		export AF_ARM AF_REPORT
		if [ -n "$PROG" ]; then
			# From the case's run folder when it has one (RUN_DIR, made
			# once by program_mode; every other path here is absolute).
			cd "$RUN_DIR" || exit 2
			rl_run "$RUN_BIN" "$@" < "${PSTDIN:-/dev/null}" > "$WORK/out" 2> "$WORK/err"
		else
			rl_run "$WORK/probe" < /dev/null > /dev/null 2> "$WORK/err"
		fi
	)
	RC=$?
	# How it ended, from waitpid() (tools/exit_status).
	rl_classify "$RC"
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
	_rep="$WORK/err"
	[ -z "$PROG" ] || _rep="$WORK/report"
	line=$(awk '/^AF_RESULT /{ last = $0 } END { print last }' "$_rep" 2>/dev/null)
	if [ -n "$line" ]; then
		# The harness's words for what the call returned (af_note), the rest
		# of the line: set where the subject's error is not a pointer. Cut
		# off first, so that no word of it is read as one of the fields.
		NOTE=""
		case "$line" in
			*" note="*)
				NOTE=${line#*" note="}
				line=${line%%" note="*} ;;
		esac
		SEEN=$(echo "$line" | sed -n 's/.* seen=\([0-9]*\).*/\1/p')
		RESULT=$(echo "$line" | sed -n 's/.* result=\([a-z]*\).*/\1/p')
		LIVE=$(echo "$line" | sed -n 's/.* live=\([a-z0-9]*\).*/\1/p')
		BYTES=$(echo "$line" | sed -n 's/.* bytes=\([0-9]*\).*/\1/p')
		WRAPPED=$(echo "$line" | sed -n 's/.* wrapped=\([01]\).*/\1/p')
	else
		SEEN=0
		RESULT=""
		NOTE=""
		LIVE=""
		BYTES=0
		WRAPPED=""
	fi
	[ -n "$SEEN" ] || SEEN=0
} 2>/dev/null

# How a run that did not return is described, from rl_classify: under
# injection the overwhelmingly likely signal is the one you get for using an
# address the allocator never gave you.
signal_name() {
	# Kept short on purpose: these strings go in a table column, and the report
	# has to stay inside 80 columns to be readable in a terminal. What SIGSEGV
	# means on THIS path is explained once, below the table, instead of being
	# repeated on every row.
	case "$RL_SIG" in
		4) echo "SIGILL (illegal instruction)" ;;
		6) echo "SIGABRT (abort: heap error or assertion)" ;;
		8) echo "SIGFPE (arithmetic error)" ;;
		11) echo "SIGSEGV (invalid memory access)" ;;
		9) echo "SIGKILL (killed)" ;;
		"") echo "a stop from outside" ;;
		*) echo "signal $RL_SIG" ;;
	esac
}

# How to describe a run that ended without the call ever returning. Status 0 is
# its own case: the process finished cleanly and simply never came back to its
# caller, which is what an exit() inside the deliverable looks like. Rendering
# that as "exit status 0" would read as though nothing had gone wrong. Called
# right after run_arm, so rl_classify's verdict on that run is still current.
ended_how() {
	case "$RL_CAUSE" in
		"timeout") echo "it did not finish within ${RL_TMO}s" ;;
		signal | runaway | stopped) signal_name ;;
		noexec) echo "it $RL_WHY" ;;
		ok) echo "it exited 0 without returning" ;;
		*) echo "exit status $1" ;;
	esac
}

# not_asked -- what the basic sweep does not ask, said on a PASS as on a FAIL:
# a green that does not say what it left out reads as covering it (finding
# 084: a function that leaked every earlier block on its error path was green
# here, and the PASS line said nothing).
not_asked() {
	echo ""
	echo "  What this layer does NOT ask: whether the blocks obtained before the"
	echo "  refused one are released. That is not graded here; where the subject"
	echo "  lets the function call free(), an exNN_allocfail_leaks target asks it"
	echo "  at robust, as this repo's own rigour."
	echo "  Leaks on the success path are graded by the valgrind layer."
}

# rows -- the sweep table, every row when it is short, otherwise the first
# few that were not ok and a count of the rest.
rows() {
	_rows=$(wc -l < "$WORK/sweep" | tr -d ' ')
	if [ "$_rows" -le 24 ]; then
		awk -F'\t' '{ printf "    #%-4s %-10s %s\n", $1, $2, $3 }' "$WORK/sweep"
	else
		awk -F'\t' -v shown=12 '
			$2 != "ok" {
				bad++
				if (bad <= shown)
					printf "    #%-4s %-10s %s\n", $1, $2, $3
			}
			$2 == "ok" { good++ }
			END {
				if (bad > shown)
					printf "    (%d further injection(s) not ok, not listed)\n", bad - shown
				if (good > 0)
					printf "    (%d injection(s) were handled correctly, not listed)\n", good
			}' "$WORK/sweep"
	fi
}

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
#
# A program's gate replays its case: gate "$@" hands the program's arguments
# to the differ after --, as valgrind_test.sh's gate does.
gate() {
if [ "${NO_SKIP:-0}" = "1" ]; then
	GATE_DIFFER=""
fi

if [ -n "$GATE_DIFFER" ] && [ -n "$GATE_BIN" ] && [ -n "$GATE_EXPECTED" ] &&
	[ -x "$GATE_BIN" ] && [ -f "$GATE_EXPECTED" ]; then
	# WHY THE STATUS IS CAPTURED RATHER THAN TESTED WITH `if !`.
	#
	# `if ! <gate>` treats EVERY non-zero the same, and the differ has two
	# meanings for non-zero: 1 is "the student's fixture is red", which is what
	# this gate is for, and 2 is "the differ could not run at all" -- a missing
	# tool, an unreadable expected file, a wiring mistake. Conflating them meant
	# a BROKEN gate silenced the layer it guards and printed a false sentence
	# while doing it.
	#
	# Demonstrated: a program whose fixture PASSES but which leaks 64 bytes was
	# reported as "SKIP -- this exercise's own output fixture is not passing
	# yet", exit 0, burying a real leak. At scale, the entire perf layer went
	# 77/77 green under a PATH shim missing `mv`, because diff_output.sh
	# requires it and exits 2.
	#
	# So: skip on 1, and on 2-or-more say so and RUN ANYWAY. A gate that cannot
	# answer must never be the reason a layer stayed quiet. GATE_PASS is a
	# list (runner_lib.sh's LISTS OF WORDS).
	rl_split_on
	# shellcheck disable=SC2086
	sh "$GATE_DIFFER" --bin "$GATE_BIN" --expected "$GATE_EXPECTED" \
			$GATE_PASS -- "$@" >/dev/null 2>&1
	_gate_rc=$?
	rl_split_off
	if [ "$_gate_rc" -ge 2 ]; then
		echo "allocfail_check: the output gate could not be evaluated (exit $_gate_rc),"
		echo "                 so this layer is running anyway rather than going quiet."
	elif [ "$_gate_rc" -eq 1 ]; then
		echo "allocfail_check: SKIP — this exercise's own output fixture is not"
		echo "                 passing yet."
		echo ""
		echo "  This layer asks what your ${WHAT} does when an allocation fails."
		echo "  That question only means something once it does the right thing"
		echo "  when the allocation SUCCEEDS — and a stub passes an allocation-"
		echo "  failure sweep for the empty reason that it never allocates. Get"
		echo "  the *_output layer green and this one starts checking something no"
		echo "  other layer in this suite checks."
		echo ""
		echo "  (NO_SKIP=1 runs a waiting layer anyway:"
		echo "   $(rl_noskip_cmd))"
		exit 0
	fi
fi
}

# untracked WHAT -- WHAT's report says live=untracked: the shim could not
# grow its own table of the blocks held (it ran out of memory itself), so the
# count it would have printed is not known. Its table grows with the program
# (tools/allocfail_counter.h); a fixed one used to say this of any run that
# had once held more than 4096 blocks, even after every one was freed.
untracked() {
	echo "allocfail_check.sh: $1 left no count of the blocks it held: the" >&2
	echo "                    shim's own table of them could not grow (the shim" >&2
	echo "                    ran out of memory itself), so its report says" >&2
	echo "                    live=untracked. No verdict rests on a count it did" >&2
	echo "                    not keep." >&2
	exit 2
}

# whose_rule LINE... -- the footer that says whose rule this target applies:
# the lines given, then the call site's --rule, wrapped to the report's width,
# when there is one. Never a subject's sentence of this runner's own: it
# cannot know which subject it is reading (see --rule).
whose_rule() {
	echo ""
	for _wr in "$@"; do echo "  $_wr"; done
	[ -n "$RULE" ] || return 0
	echo "  The rule, as this target's call site in BUILD.bazel states it:"
	print_rule
}

# print_rule -- the call site's --rule file, wrapped to the report's width.
print_rule() {
	awk '{
		n = split($0, w, " ")
		line = ""
		for (i = 1; i <= n; i++) {
			if (line != "" && length(line) + 1 + length(w[i]) > 68) {
				print "    " line
				line = w[i]
			} else
				line = (line == "" ? w[i] : line " " w[i])
		}
		if (line != "") print "    " line
	}' "$RULE"
}

# ---------------------------------------------------------------------------
# run_arm's stderr is /dev/null, so the helper that says how a run ended is
# found HERE, where its absence can still be said.
rl_ready


# ---------------------------------------------------------------------------
# WHICH REQUESTS TO REFUSE, one per line: af_points K M. All K when K <= M (the
# --max-inject budget); past it, a SAMPLE, never the first M: a call that
# allocates through all of its input asks first for what the start of the
# input needs, and refusing only those would leave every later error path
# untried. The first half of the budget goes to the first requests, the rest
# is spread evenly up to the last one, which is always included. Function
# mode once truncated at the first M, and said so; both modes sample now.
af_points() {
	awk -v k="$1" -v m="$2" 'BEGIN {
		if (k <= m) { for (i = 1; i <= k; i++) print i; exit }
		h = int(m / 2)
		for (i = 1; i <= h; i++) print i
		r = m - h
		for (j = 1; j <= r; j++) {
			p = h + int((k - h) * j / r + 0.5)
			if (p > last && p > h) { print p; last = p }
		}
	}'
}

# ---------------------------------------------------------------------------
# A PROGRAM (--bin): its own main() runs, built with tools/allocfail_program.c
# beside it (c_program's exNN_bin_allocfail), on one case's argv and stdin.
#
# What it asks, after each refused allocation, is what every reading of a
# subject's rule for errors agrees on (TODO.md §23, WP-92): the program ends by
# itself -- no signal, within its time -- and its output is bounded. It asserts
# no text and no exit status: what a program prints or returns on this path is
# its subject's to say, and the subject is the call site's to quote (--rule),
# never this runner's. No 42 grader refuses a program an allocation, so this
# is the repo's own rigour, at robust (the _program_allocfail suffix). With
# --leaks it asks instead whether a run that ended by itself still held a
# block at exit -- what the valgrind layer asks of the plain run.
#
# A large count is SAMPLED, not truncated (af_points): a program that parses
# a file allocates through all of it, and the first --max-inject requests
# would all be the parser's.
program_mode() {
	gate "$@"
	# A program that did not build is a stand-in that says why (tools/
	# standin.sh). Checked after the gate, as valgrind_test.sh does: a red gate
	# has already skipped, and past a green one a stand-in is a failure told in
	# the compiler's words.
	case "$0" in */*) _sl_dir=${0%/*} ;; *) _sl_dir=. ;; esac
	for _sl in "$_sl_dir/standin.sh" \
		"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
		[ -f "$_sl" ] && break
	done
	[ -f "$_sl" ] || { echo "allocfail_check.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
	# shellcheck source=tools/standin.sh
	. "$_sl"
	standin_check allocfail_check "$PROG" fail "$LABEL"
	# The run the case describes, as diff_output.sh makes it: the argument
	# file's words after the arguments after -- (the gate above was handed
	# the file itself), and the case's own folder when it has one.
	if [ -n "$ARGV_FILE" ]; then
		_aw=$(rl_argv_words "$ARGV_FILE") || {
			echo "allocfail_check.sh: cannot read --argv-file '$ARGV_FILE'" >&2
			exit 2
		}
		eval "set -- \"\$@\" $_aw"
	fi
	RUN_BIN=$PROG
	RUN_DIR=$PWD
	_ran_prog=$SHOW_RUN
	_ran_in=$PSTDIN
	_ran_specs=""
	case "$RUN_BIN" in /*) ;; *) RUN_BIN="$PWD/$RUN_BIN" ;; esac
	if [ -n "$RUN_AS" ]; then
		RUN_DIR="$WORK/run"
		rl_rundir "$RUN_DIR" "$RUN_AS" "$PROG" "$CWD_FILES" || exit 2
		RUN_BIN="./$RUN_AS"
		_ran_prog=$RUN_BIN
		_ran_specs="$RUN_AS=${SHOW_RUN:-$PROG}$CWD_FILES"
	fi
	case "$PSTDIN" in "" | /*) ;; *) PSTDIN="$PWD/$PSTDIN" ;; esac
	[ -z "$SHOW_RUN" ] || { rl_ran "$_ran_prog" "$_ran_in" "$_ran_specs" "$@"; echo ""; }
	run_arm 0 "$@"
	case "$RL_CAUSE" in
		noexec)
			echo "allocfail_check.sh: the program could not be started: $RL_WHY" >&2
			exit 2 ;;
		"timeout" | signal | runaway | stopped)
			[ "${NO_SKIP:-0}" != "1" ] || {
				echo "NO_SKIP set: the plain run, with nothing refused, did not end by"
				echo "             itself ($(ended_how "$RC")), so no refusal was tested."
				exit 1
			}
			echo "allocfail_check: SKIP — the plain run, with nothing refused, did not"
			echo "                 end by itself ($(ended_how "$RC"))."
			echo "  This layer asks what happens when an allocation FAILS. The output,"
			echo "  asan and valgrind layers run this same case and say what is wrong"
			echo "  on the path where they all succeed."
			exit 0 ;;
	esac
	if [ -z "$RESULT" ]; then
		[ "${NO_SKIP:-0}" != "1" ] || {
			echo "NO_SKIP set: the plain run left no count -- it ended without"
			echo "             returning from main() or calling exit() -- so nothing"
			echo "             was refused."
			exit 1
		}
		echo "allocfail_check: SKIP — the plain run left no count of its allocations:"
		echo "                 it ended without returning from main() or calling exit()."
		exit 0
	fi
	K=$SEEN
	BASE_STATUS=$RC
	# The shim proves the link took the wraps (wrapped=1, see
	# allocfail_program.c): without that, "asked for no memory" and "never
	# counted" read the same, and the second is the harness's fault.
	if [ "$WRAPPED" != 1 ]; then
		echo "allocfail_check.sh: $PROG was not linked with -Wl,--wrap=malloc and" >&2
		echo "                    -Wl,--wrap=free (the shim's own probe was not counted)," >&2
		echo "                    so no refusal could reach it. That is the build's wiring" >&2
		echo "                    (c_program's exNN_bin_allocfail), not the program." >&2
		exit 2
	fi
	# Asking for no memory on this case is a design, not a gap: allocating is
	# allowed, never required, so a program that takes no memory has no
	# refusal to meet, and this stays green under NO_SKIP=1 too. But it is
	# not headed OK: nothing was refused, so nothing was checked, and a
	# green that reads like a verdict is the shape design.md ranks worst.
	if [ "$K" -eq 0 ]; then
		echo "allocfail_check: NOTHING TO REFUSE — $LABEL asked for no memory on"
		echo "                 this case, so no allocation was refused and its"
		echo "                 error paths were not tested."
		echo "                 (The shim's own probe was counted: the wrapping is"
		echo "                 in place, so the 0 is the program's.)"
		echo "  Green, under NO_SKIP=1 too: whether to allocate is the program's"
		echo "  choice, and a run that makes no request has no refusal to meet."
		exit 0
	fi
	if [ "$LEAKS" = 1 ] && [ "$LIVE" = untracked ]; then
		untracked "the plain run, with nothing refused,"
	fi
	if [ "$LEAKS" = 1 ] && [ "${LIVE:-0}" -gt 0 ]; then
		[ "${NO_SKIP:-0}" != "1" ] || {
			echo "NO_SKIP set: the plain run already holds ${LIVE} block(s) at exit,"
			echo "             so the error paths' leftovers could not be told apart."
			exit 1
		}
		echo "allocfail_check: SKIP — the plain run, with nothing refused, already"
		echo "                 holds ${LIVE} block(s) at exit."
		echo "  The valgrind layer reports what the plain run leaves behind; this"
		echo "  target counts what an error path leaves, once the plain run leaves"
		echo "  nothing."
		exit 0
	fi

	# The points to refuse, one per line.
	af_points "$K" "$MAX_INJECT" > "$WORK/points"
	SAMPLED=0
	[ "$K" -le "$MAX_INJECT" ] || SAMPLED=1
	: > "$WORK/sweep"
	FAILURES=0
	HUNG=0
	CRASHED=0
	FLOODED=0
	LEAKED=0
	NOT_JUDGED=0
	FIRST=""
	while IFS= read -r n; do
		run_arm "$n" "$@"
		_bad=1
		case "$RL_CAUSE" in
			"timeout")
				printf '%s\tHUNG\tstill running after %ss\n' "$n" "$RL_TMO" >> "$WORK/sweep"
				HUNG=1 ;;
			runaway)
				printf '%s\tFLOOD\twrote more than %s bytes and was stopped\n' \
					"$n" "$CAP" >> "$WORK/sweep"
				FLOODED=1 ;;
			signal | stopped)
				printf '%s\tCRASH\tkilled by %s\n' "$n" "$(signal_name)" >> "$WORK/sweep"
				CRASHED=1 ;;
			noexec)
				echo "allocfail_check.sh: injection #$n could not start: $RL_WHY" >&2
				exit 2 ;;
			*)
				_bad=0
				if [ -z "$RESULT" ]; then
					printf '%s\tNOT-JUDGED\tended without a count (no exit() or return from main)\n' \
						"$n" >> "$WORK/sweep"
					NOT_JUDGED=$((NOT_JUDGED + 1))
				elif [ "$SEEN" -lt "$n" ]; then
					printf '%s\tNOT-JUDGED\tthis run made only %s request(s): the refusal never fired\n' \
						"$n" "$SEEN" >> "$WORK/sweep"
					NOT_JUDGED=$((NOT_JUDGED + 1))
				elif [ "$LEAKS" = 1 ] && [ "$LIVE" = untracked ]; then
					untracked "injection #$n"
				elif [ "$LEAKS" = 1 ] && [ "${LIVE:-0}" -gt 0 ]; then
					printf '%s\tLEAK\tended by itself; %s block(s), %s byte(s), still allocated at exit\n' \
						"$n" "$LIVE" "$BYTES" >> "$WORK/sweep"
					LEAKED=$((LEAKED + 1))
					_bad=1
				else
					printf '%s\tok\tended by itself (status %s)\n' "$n" "$RC" >> "$WORK/sweep"
				fi ;;
		esac
		if [ "$_bad" = 1 ]; then
			FAILURES=$((FAILURES + 1))
			if [ -z "$FIRST" ]; then
				FIRST=$n
				cp "$WORK/err" "$WORK/first.err" 2>/dev/null
				cp "$WORK/out" "$WORK/first.out" 2>/dev/null
			fi
		fi
		[ "$HUNG" = 0 ] || break
	done < "$WORK/points"

	# The control: one past the last request cannot be refused, so this run
	# must end as the plain one did.
	if [ "$HUNG" = 0 ]; then
		run_arm $((K + 1)) "$@"
		if [ "$RL_CAUSE" != ok ] && [ "$RL_CAUSE" != exit ] || [ "$RC" != "$BASE_STATUS" ] ||
			[ -z "$RESULT" ]; then
			echo "allocfail_check.sh: the control run is not trustworthy for $LABEL." >&2
			echo "                    Arming request #$((K + 1)) cannot refuse anything (the" >&2
			echo "                    plain run made $K), so it should have ended as the plain" >&2
			echo "                    run did (status $BASE_STATUS); it ended: $(ended_how "$RC")." >&2
			echo "                    No verdict rests on a sweep that is not repeatable." >&2
			exit 2
		fi
	fi

	_covered="Each was refused in turn, one per run."
	[ "$SAMPLED" = 0 ] ||
		_covered="$(wc -l < "$WORK/points" | tr -d ' ') were refused, one per run: the first ones, then spread to the last."
	JUDGED=$(( $(wc -l < "$WORK/sweep" | tr -d ' ') - NOT_JUDGED ))
	if [ "$JUDGED" -le 0 ]; then
		[ "${NO_SKIP:-0}" != "1" ] || {
			echo "NO_SKIP set: no refused run could be judged."
			rows
			exit 1
		}
		echo "allocfail_check: SKIP — no refused run could be judged:"
		echo ""
		rows
		exit 0
	fi
	if [ "$FAILURES" -eq 0 ]; then
		if [ "$LEAKS" = 1 ]; then
			echo "allocfail_check: PASS — $LABEL released everything on each error path"
			echo "                 It asks for memory $K time(s) on this case."
			echo "                 $_covered"
			echo "                 Every run that ended by itself held no block at exit."
		else
			echo "allocfail_check: PASS — $LABEL ended by itself after each refusal"
			echo "                 It asks for memory $K time(s) on this case."
			echo "                 $_covered"
			echo "                 Every run ended by itself, within its time, with"
			echo "                 bounded output."
			echo "                 What it printed and the status it returned are not"
			echo "                 judged here."
		fi
		if [ "$NOT_JUDGED" -gt 0 ]; then
			echo "                 $NOT_JUDGED run(s) could not be judged:"
			echo ""
			rows
		fi
		whose_rule "Whose rule this is: the repo's, at robust. No grader at 42 refuses a" \
			"program an allocation."
		exit 0
	fi
	if [ "$CRASHED$HUNG$FLOODED" = 000 ]; then
		echo "allocfail_check: FAIL — $LABEL held memory at exit after a refused allocation"
	else
		echo "allocfail_check: FAIL — $LABEL did not end by itself after a refused allocation"
	fi
	echo ""
	echo "  On this case the program asks for memory $K time(s). Each run below is"
	echo "  the SAME case, with exactly one of those requests refused:"
	echo ""
	rows
	echo ""
	if [ -s "$WORK/first.err" ]; then
		echo "  What run #$FIRST wrote on stderr:"
		rl_excerpt "$WORK/first.err" 12 first-failing-run-stderr.txt "    "
		echo ""
	fi
	if [ "$CRASHED" = 1 ]; then
		echo "  WHAT A CRASH ROW MEANS"
		echo "  malloc answered NULL to request #N, as it may at any time. Where in"
		echo "  your program does that answer go, and who finds out that it was no?"
		echo ""
	fi
	if [ "$FLOODED" = 1 ]; then
		echo "  WHAT A FLOOD ROW MEANS"
		echo "  After the refusal the program kept writing until it was stopped:"
		echo "  what does it repeat once that request has been answered NULL?"
		echo ""
	fi
	if [ "$HUNG" = 1 ]; then
		echo "  WHAT A HUNG ROW MEANS"
		echo "  After the refusal the program never ended: what is it waiting for,"
		echo "  or repeating, once that request has been answered NULL?"
		echo ""
	fi
	if [ "$LEAKED" -gt 0 ]; then
		echo "  WHAT A LEAK ROW MEANS"
		echo "  The program ended by itself, and blocks it had obtained before the"
		echo "  refused request were still allocated at exit. On the path that"
		echo "  stops early, what becomes of what was already built?"
		echo ""
	fi
	echo "  #1 is the first malloc the program reaches on this case, #2 the second;"
	echo "  the row's number is the request that was refused."
	whose_rule "Whose rule this is: the repo's, at robust. No grader at 42 refuses a" \
		"program an allocation. What the program prints and returns on this" \
		"path is not judged."
	exit 1
}
if [ -n "$PROG" ]; then
	program_mode "$@"
fi

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
# Toolchain: the pinned clang-12 and binutils 2.38, never the box's. This layer
# needs no sanitizer, only a linker that understands --wrap, and builds under
# -w -- but a compiler still decides whether code builds at all (an implicit
# declaration is a warning to one compiler and an error to the next), and
# this used to take `cc` from the box, then gcc, clang, clang-12 or gcc-10 --
# so the one layer that executes the error path ran on whatever the machine
# had (TO VERIFY V38: LD_DEBUG showed the box's `cc`, its clang-12, and
# /bin/ld under C 07 ex00_allocfail). Bazel hands both over, tools/defs.bzl refuses a test that
# does not (pinned_cc_problem), and a missing one is exit 2, above.
rl_cc_pin "$CC" "$CC_LIBS" "$CC_UNDER"
rl_ld_pin "$CC" "$LD" "$LD_LIBS" "$WORK/ld"


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
# conventions: harness tool -- wrapprobe is the probe written above, never the student's code
if ! "$CC" "$RL_LDFLAG" -O0 "$WORK/wrapprobe.c" -o "$WORK/wrapprobe" \
		-Wl,--wrap=malloc > "$WORK/wrap.err" 2>&1 || ! "$WORK/wrapprobe"; then
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: this toolchain's linker does not honour"
		echo "             -Wl,--wrap=malloc, so no allocation was ever failed"
		echo "             and nothing was checked. What it said:"
		rl_excerpt "$WORK/wrap.err" 5 wrap-probe.txt
		exit 1
	}
	echo "allocfail_check: SKIP — this linker does not honour -Wl,--wrap=malloc,"
	echo "                 which is how this layer makes an allocation fail."
	echo "                 WARNING: the error path this target asks about was not"
	echo "                 executed. No other layer executes it either."
	exit 0
fi

# With --leaks, free() must be wrapped too, and the same rule applies: a linker
# that ignored --wrap=free would never cross a block off, and every correct
# function would be reported as leaking everything it had taken.
if [ "$LEAKS" = 1 ]; then
	cat > "$WORK/freeprobe.c" <<'PROBE'
#include <stdlib.h>
#include <unistd.h>
void	__wrap_free(void *ptr);

void	__wrap_free(void *ptr)
{
	(void)ptr;
	_exit(0);
}

int	main(void)
{
	free(0);
	return (1);
}
PROBE
	# conventions: harness tool -- freeprobe is the probe written above, never the student's code
	if ! "$CC" "$RL_LDFLAG" -O0 "$WORK/freeprobe.c" -o "$WORK/freeprobe" \
			-Wl,--wrap=free > "$WORK/wrap.err" 2>&1 || ! "$WORK/freeprobe"; then
		echo "allocfail_check.sh: this linker does not honour -Wl,--wrap=free, so no" >&2
		echo "                    block could be counted as released; --leaks cannot" >&2
		echo "                    run here. That is the toolchain, not the deliverable." >&2
		exit 2
	fi
fi

gate

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
CFLAGS=""
rl_list_add CFLAGS "$RL_LDFLAG" -O0 -g -w
OBJS=""
: > "$WORK/cc.err"
BUILD_OK=1
# Object names are NUMBERED, not derived from the basename. Two --src files can
# legitimately share one (a module wired with sources from two exercise
# directories), and a name collision would silently overwrite the first object
# and link the second one twice — surfacing as a duplicate-symbol error that
# reads as the student's mistake and is not.
OBJ_N=0
rl_split_on
for src in $SRCS; do
	OBJ_N=$(( OBJ_N + 1 ))
	obj="$WORK/src$OBJ_N.o"
	# shellcheck disable=SC2086
	if ! "$CC" $CFLAGS $INCS -c "$src" -o "$obj" >> "$WORK/cc.err" 2>&1; then
		BUILD_OK=0
		break
	fi
	rl_list_add OBJS "$obj"
done

if [ "$BUILD_OK" -eq 1 ]; then
	# shellcheck disable=SC2086
	"$CC" $CFLAGS $INCS -Dmalloc=__real_malloc -c "$HARNESS" \
		-o "$WORK/harness.o" >> "$WORK/cc.err" 2>&1 || BUILD_OK=0
fi
if [ "$BUILD_OK" -eq 1 ]; then
	SHIM_DEF=""
	[ "$LEAKS" = 0 ] || SHIM_DEF="-DAF_WRAP_FREE"
	# shellcheck disable=SC2086
	"$CC" $CFLAGS $SHIM_DEF -c "$SHIM" -o "$WORK/shim.o" >> "$WORK/cc.err" 2>&1 || BUILD_OK=0
fi
if [ "$BUILD_OK" -eq 1 ]; then
	# shellcheck disable=SC2086
	# --wrap=free only for --leaks: the basic sweep links exactly as it
	# always has, so its verdict cannot move because a second target exists.
	WRAP_FREE=""
	[ "$LEAKS" = 0 ] || WRAP_FREE="-Wl,--wrap=free"
	# shellcheck disable=SC2086
	"$CC" "$RL_LDFLAG" $OBJS "$WORK/harness.o" "$WORK/shim.o" -o "$WORK/probe" \
		-Wl,--wrap=malloc $WRAP_FREE >> "$WORK/cc.err" 2>&1 || BUILD_OK=0
fi
rl_split_off

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
	rl_excerpt "$WORK/cc.err" 30 compiler-output.txt "  "
	exit 1
fi

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

# The requests refused (af_points): all K, or past --max-inject a sample
# that spreads to the last one.
af_points "$K" "$MAX_INJECT" > "$WORK/points"
SWEPT=$(wc -l < "$WORK/points" | tr -d ' ')
SAMPLED=0
[ "$K" -le "$MAX_INJECT" ] || SAMPLED=1

# ---------------------------------------------------------------------------
# Phase 2 — SWEEP. One run per injected failure; the verdict for each goes into
# a small table so the report can say WHICH allocation was the unguarded one
# rather than only that something went wrong. That distinction is the whole
# pedagogic value: "#3 of 4" points at a line.
: > "$WORK/sweep"
FAILURES=0
HUNG=0
KEPT_ASKING=0
WRONG_RET=0
CRASHED=0
LEAKED=0
NOT_JUDGED=0
INCONCLUSIVE=""
while IFS= read -r n; do
	run_arm "$n"
	if [ "$RL_CAUSE" = timeout ]; then
		printf '%s\tHUNG\tnever returned — still running after %ss\n' \
			"$n" "$RL_TMO" >> "$WORK/sweep"
		FAILURES=$(( FAILURES + 1 ))
		# One hang is a definitive finding and every further injection would
		# cost another full timeout, so stop here rather than spending minutes
		# re-learning it.
		HUNG=1
		break
	elif [ "$RL_CAUSE" = runaway ]; then
		printf '%s\tFLOOD\twrote more than %s bytes and was stopped\n' \
			"$n" "$CAP" >> "$WORK/sweep"
		FAILURES=$(( FAILURES + 1 ))
	elif [ "$RL_CAUSE" = signal ] || [ "$RL_CAUSE" = stopped ]; then
		printf '%s\tCRASH\tkilled by %s\n' "$n" "$(signal_name)" \
			>> "$WORK/sweep"
		FAILURES=$(( FAILURES + 1 ))
		CRASHED=1
	elif [ -z "$RESULT" ] && [ "$LEAKS" = 1 ]; then
		printf '%s\tNOT-JUDGED\tthe call never returned: the allocfail target says so\n' \
			"$n" >> "$WORK/sweep"
		NOT_JUDGED=$(( NOT_JUDGED + 1 ))
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
	elif [ "$RESULT" = "ptr" ] && [ "$LEAKS" = 1 ]; then
		printf '%s\tNOT-JUDGED\tit did not report the error: the allocfail target says so\n' \
			"$n" >> "$WORK/sweep"
		NOT_JUDGED=$(( NOT_JUDGED + 1 ))
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
		#
		# Where the harness said what the call returned (af_note: the
		# subject's error is a value, not a pointer), that is the row, as
		# WRONG-RET: "returned a pointer" would describe the harness's
		# translation, not the function.
		if [ -n "$NOTE" ] && [ "$SEEN" -gt "$n" ]; then
			printf '%s\tWRONG-RET\tit was refused, asked %s more time(s), and %s\n' \
				"$n" "$(( SEEN - n ))" "$NOTE" >> "$WORK/sweep"
			KEPT_ASKING=1
			WRONG_RET=1
		elif [ -n "$NOTE" ]; then
			printf '%s\tWRONG-RET\tallocation #%s failed, and it %s\n' \
				"$n" "$n" "$NOTE" >> "$WORK/sweep"
			WRONG_RET=1
		elif [ "$SEEN" -gt "$n" ]; then
			printf '%s\tNOT-NULL\tit was refused, asked %s more time(s), and returned a pointer\n' \
				"$n" "$(( SEEN - n ))" >> "$WORK/sweep"
			KEPT_ASKING=1
		else
			printf '%s\tNOT-NULL\tallocation #%s failed, and it still returned a pointer\n' \
				"$n" "$n" >> "$WORK/sweep"
		fi
		FAILURES=$(( FAILURES + 1 ))
	elif [ "$LEAKS" = 1 ] && [ "$LIVE" = untracked ]; then
		untracked "injection #$n"
	elif [ "$LEAKS" = 1 ] && [ -z "$LIVE" ]; then
		# A report without the field is no count: a verdict would be a guess.
		echo "allocfail_check.sh: injection #$n's report has no live-block count" >&2
		echo "                    (no live= field): the shim and this script disagree" >&2
		echo "                    about the report line, which is the harness's wiring." >&2
		exit 2
	elif [ "$LEAKS" = 1 ] && [ "$LIVE" -gt 0 ]; then
		printf '%s\tLEAK\treturned NULL, and %s block(s), %s byte(s), are still allocated\n' \
			"$n" "$LIVE" "$BYTES" >> "$WORK/sweep"
		LEAKED=$(( LEAKED + 1 ))
		FAILURES=$(( FAILURES + 1 ))
	elif [ "$LEAKS" = 1 ]; then
		printf '%s\tok\treturned NULL, nothing left allocated\n' "$n" >> "$WORK/sweep"
	else
		printf '%s\tok\treturned NULL, no crash\n' "$n" >> "$WORK/sweep"
	fi
done < "$WORK/points"

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
if [ "$HUNG" -eq 0 ]; then
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
# Report, --leaks. One question: on the runs that reported the error, is
# anything the function obtained still allocated?
if [ "$LEAKS" = 1 ]; then
	JUDGED=$(( $(wc -l < "$WORK/sweep" | tr -d ' ') - NOT_JUDGED ))
	if [ "$JUDGED" -le 0 ]; then
		[ "${NO_SKIP:-0}" != "1" ] || {
			echo "NO_SKIP set: no injected run reported the error, so nothing was left"
			echo "             to judge for leaks. The allocfail target says why."
			exit 1
		}
		echo "allocfail_check: SKIP — no run reported the error, so there is no error"
		echo "                 path whose leftovers to count."
		echo ""
		rows
		echo ""
		echo "  The allocfail target for this exercise asks the question before this"
		echo "  one -- whether the call reports a refused allocation at all -- and it"
		echo "  is red. This target starts counting once it is green."
		exit 0
	fi
	if [ "$FAILURES" -eq 0 ]; then
		_cover="injections 1..$K"
		[ "$SAMPLED" -eq 0 ] || _cover="$SWEPT of the $K requests, the first ones and then spread to the last"
		echo "allocfail_check: PASS — $LABEL released what it had obtained on each"
		echo "                 error path ($_cover)."
		echo "                 Every run that reported the refused allocation left"
		echo "                 none of the blocks it had obtained before it."
		[ "$NOT_JUDGED" -eq 0 ] ||
			echo "                 $NOT_JUDGED run(s) did not report the error and were not judged."
		whose_rule "Whose rule this is: the repo's, at robust. The allocfail target asks" \
			"that the error be reported; releasing what was already obtained is" \
			"the rigour this target adds, and no grader at 42 checks it."
		exit 0
	fi
	echo "allocfail_check: FAIL — $LABEL left memory allocated on an error path"
	echo ""
	echo "  On this input the deliverable asks for memory $K time(s). Each run below"
	echo "  is the SAME input, with exactly one of those requests refused:"
	echo ""
	rows
	echo ""
	if [ "$CRASHED" -eq 1 ] || [ "$HUNG" -eq 1 ]; then
		echo "  A run that crashed or never ended fails here as everywhere; the"
		echo "  allocfail target reports the same run and says more about it."
		echo ""
	fi
	if [ "$LEAKED" -gt 0 ]; then
		echo "  WHAT A LEAK ROW MEANS"
		echo "  The call reported the error, as the allocfail target asks. The blocks"
		echo "  it had obtained before the refused request are still allocated, and"
		echo "  the caller received only the error: what could it use to release them?"
		echo "  #1 is the first malloc the function reaches on this input, #2 the"
		echo "  second; the row's number is the request that was refused."
		echo ""
	fi
	whose_rule "Whose rule this is: the repo's, at robust. The allocfail target asks" \
		"that the error be reported; releasing what was already obtained is the" \
		"rigour this target adds, and no grader at 42 checks it. The allocfail" \
		"target keeps its own verdict."
	exit 1
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
	if [ "$SAMPLED" -eq 1 ]; then
		echo "allocfail_check: PASS (sampled) — $LABEL survived $SWEPT of $K failed allocations"
		echo "                 It asks for memory $K time(s) on this input, more than"
		echo "                 the $MAX_INJECT injections a sweep makes (--max-inject), so"
		echo "                 $SWEPT were refused, one per run: the first ones, then"
		echo "                 spread evenly to the last. Every time, the call reported"
		echo "                 the error and nothing crashed. The other $(( K - SWEPT ))"
		echo "                 requests were NOT refused: this green covers $SWEPT of $K."
		echo "                 The control run (#$(( K + 1 )), which cannot fail) still"
		echo "                 returned a valid pointer."
		not_asked
	else
		echo "allocfail_check: PASS — $LABEL survived every failed allocation"
		echo "                 It asks for memory $K time(s) on this input. Injections"
		echo "                 1..$SWEPT each refused one of those requests; every time,"
		echo "                 the call reported the error and nothing crashed."
		echo "                 The control run (#$(( K + 1 )), which cannot fail) still"
		echo "                 returned a valid pointer, so the sweep was bounded"
		echo "                 where the allocations actually end."
		not_asked
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
rows
echo ""
if [ "$SAMPLED" -eq 1 ]; then
	echo "  $SWEPT of the $K requests were refused (--max-inject): the first ones,"
	echo "  then spread evenly to the last."
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
if [ -n "$RULE" ]; then
	echo "  that \"no\" cannot happen. Your subject decides otherwise, and its"
	echo "  sentence is the standard being applied here, not a house style --"
	echo "  as this target's call site in BUILD.bazel states it:"
	print_rule
else
	echo "  that \"no\" cannot happen. What this function owes its caller when an"
	echo "  allocation fails is its subject's to say: find that sentence."
fi
echo ""
if [ "$WRONG_RET" -eq 1 ]; then
	echo "  WHAT THE WRONG-RET ROWS MEAN"
	echo "  The call returned, and did not crash, but what it returned is not the"
	echo "  value its subject gives for an error. A caller that tests for that"
	echo "  value is told everything went well."
	echo ""
fi
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
	echo "  reporting the error tells the CALLER, who is the one with the context"
	echo "  to decide what happens next. Ask yourself which of the two your code"
	echo "  is doing, and which one its subject describes."
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
echo "  the one that was refused, and at what the function returns after it."
not_asked
exit 1
