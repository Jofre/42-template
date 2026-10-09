#!/bin/sh
# Re-run an exercise's functional test on an ILP32 target (-m32), where `long`
# is 32 bits — the SAME width as `int`.
#
# Why: a favourite way to survive INT_MIN is to widen — copy the int into a
# `long` so that negating it is representable. That works on the campus box
# because this is an LP64 platform, but C only guarantees `long` to be at least
# 32 bits: it is allowed to be exactly as narrow as `int`, and is on 32-bit Linux
# and on Windows. Code that leans on the widening is then silently wrong at
# exactly the value it was written to handle.
#
# Compiling the SAME harness and the SAME expected output for -m32 turns that
# assumption into a red test instead of a platform accident. Nothing else about
# the exercise changes: same fixture, same cases, same diff.
#
# This needs a compiler that can target 32-bit. Bazel fetches a hermetic zig for
# it; the host fallback needs 32-bit libc headers (libc6-dev-i386 / gcc-multilib).
# If nothing can, the layer SKIPS loudly with exit 0 — like compile_check.sh does
# for a missing compiler — so the suite stays green on a machine that cannot host
# it. NO_SKIP=1 turns every one of those skips red instead: a layer that compiled
# nothing has checked nothing, and the forced sweep exists to say so.
#
# The same compiler also stops the program at UNDEFINED BEHAVIOUR. zig builds in
# debug mode by default, and there it plants a trap at a signed overflow or an
# index out of range: the program dies on SIGILL at that operation, where the
# 64-bit build ran past it silently. That is kept on purpose -- a long that
# overflows at 32 bits then fails at the operation, deterministically, instead
# of printing garbage or looping -- and the report says which of the two it saw.
#
# The report only blames the type model when it knows the 64-bit build passes.
# That is the gate below, and it no longer runs only when a layer would skip:
# it runs the exercise's own 64-bit program (--gate-bin, the binary *_output
# runs) every time and records NATIVE=pass|fail|nobuild|unknown, so a forced
# run (NO_SKIP=1) over a plain bug says "the 64-bit build fails these same
# cases" instead of "passes on the 64-bit build". It used to say the second,
# with `cc` from PATH or no check at all; and then it rebuilt the files itself
# with every warning silenced (-w), so code that *_output reports as not
# building -- a warning under -Werror -- passed this gate, ran here, and was
# reported as "the ordinary 64-bit build passes these cases". The program
# *_output runs is the one place that build is decided.
#
# Usage:
#   ilp32_test.sh --differ PATH --harness FILE --expected FILE
#                 --src FILE [--src FILE]... [--inc DIR]...
#                 [--harness-src FILE]... [--gate-bin PATH]
#                 [--zig PATH]
#                 [--stdin FILE] [--labeled] [--escaped-values] [--clues FILE]
#                 [--sanitize] [--lib32 FILE]...
#
# --stdin, --labeled, --escaped-values, --clues and --sanitize are
# diff_output.sh's, forwarded to both of its runs as they came.
#
# --harness-src FILE is a harness-side source compiled in with the harness
# main in both builds, never a student's: tools/unbuffered_stdout.c, which
# makes the fixture's stdout unbuffered exactly as in the 64-bit output layer,
# so that a crash on this target keeps the rows printed before it.
#
# --gate-bin PATH is the exercise's own 64-bit program, the one *_output runs
# (tools/student_build.sh made it, from the same harness and the same files,
# with the flags every other layer is built with): the gate below. A stand-in
# there (tools/standin.sh) is code that does not build.
#
# --lib32 FILE is a library the GRADER links, at 32 bits: C 12's "From
# exercise 01 onward, we'll use our ft_create_elem" is the grader's
# constructor, built from Rust (tools/grader_lib.bzl) as an i686 archive for
# the 32-bit build (the 64-bit program has its x86_64 twin linked already).
# It is linked after the sources, so a student who defines the function
# anyway keeps theirs, as the grader's link would not (the forbidden layer
# says so).
#
# Nothing else is linked in: never another exercise's files. The `-- FILE...`
# that once took them (c_function's `deps`) went with `deps`, when the
# exercises that used it turned out to call the GRADER's function, which is
# --lib32 above for the 32-bit build, and linked into --gate-bin's program
# already for the 64-bit one (tools/defs.bzl, c_function).
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "ilp32_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require dirname id mkdir mktemp rm

# The shared runner helpers -- exiting signal traps and excerpts that say what
# they left out -- written once in tools/runner_lib.sh.
RL_NAME=ilp32_test
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "ilp32_test.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The stand-in contract, to tell a 64-bit program that did not build from one
# that fails its fixture (--gate-bin).
case "$0" in */*) _sl_dir=${0%/*} ;; *) _sl_dir=. ;; esac
for _sl in "$_sl_dir/standin.sh" \
	"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
	[ -f "$_sl" ] && break
done
[ -f "$_sl" ] || { echo "ilp32_test.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool C32 -- the 32-bit compiler found below, with its flags: it builds, and runs none of what it builds
# conventions: harness tool cc -- each compiler tried in turn for -m32, with a probe written here
# conventions: harness tool ZIG -- the pinned zig, used as a 32-bit compiler
# conventions: harness tool DIFFER -- tools/diff_output.sh, which runs the program it is handed under this test's budget

# conventions: optional cc -- by hand only: read as a command here because
# zig's subcommand is spelled `"$ZIG" cc`. No verdict takes cc from PATH: the
# 64-bit gate runs --gate-bin, and the one PATH compiler left is the hand-run
# -m32 fallback below, reached only without --zig, probed by name and skipped
# without.

ZIG=""
DIFFER=""
HARNESS=""
EXPECTED=""
SRCS=""
HSRCS=""
FIXTURE=""
INCS=""
PASS=""
GATE_BIN=""
LIBS32=""

# --inc takes either a directory or a header file: Bazel's $(location) on an
# hdrs entry resolves to the file, and the compiler needs its directory.
_dir() {
	if [ -d "$1" ]; then printf '%s\n' "$1"; else dirname "$1"; fi
}

# Once per file: a source named twice (a --src the grader supplies, say,
# Reloaded's ft_putchar.c, beside a list that already holds it) is compiled
# once, since a second copy of every function in it would not link.
# The lists are one word per line (runner_lib.sh, LISTS OF WORDS).
_add_src() {
	case "$RL_NL$SRCS$RL_NL" in
		*"$RL_NL$1$RL_NL"*) ;;
		*) rl_list_add SRCS "$1" ;;
	esac
	rl_list_add INCS "-I$(dirname "$1")"
}

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "ilp32_test.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--zig) need "$1" "$#"; ZIG="$2"; shift 2 ;;
		--differ) need "$1" "$#"; DIFFER="$2"; shift 2 ;;
		--harness) need "$1" "$#"; HARNESS="$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--expected) need "$1" "$#"; EXPECTED="$2"; shift 2 ;;
		--src) need "$1" "$#"; _add_src "$2"; shift 2 ;;
		# A harness source is the unbuffered-stdout library, and a fixture
		# built with it is one diff_output.sh may read case by case after a
		# crash: --harness-fixture, whose premise diff_output.sh checks in the binary.
		--harness-src) need "$1" "$#"; rl_list_add HSRCS "$2"; FIXTURE="--harness-fixture"; shift 2 ;;
		--inc) need "$1" "$#"; rl_list_add INCS "-I$(_dir "$2")"; shift 2 ;;
		--stdin) need "$1" "$#"; rl_list_add PASS --stdin "$2"; shift 2 ;;
		--clues) need "$1" "$#"; rl_list_add PASS --clues "$2"; shift 2 ;;
		--labeled) rl_list_add PASS --labeled; shift ;;
		--escaped-values) rl_list_add PASS --escaped-values; shift ;;
		--sanitize) rl_list_add PASS --sanitize; shift ;;
		--lib32) need "$1" "$#"; rl_list_add LIBS32 "$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		*) echo "ilp32_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$DIFFER" ] && [ -n "$HARNESS" ] && [ -n "$EXPECTED" ] && [ -n "$SRCS" ] || {
	echo "ilp32_test.sh: need --differ, --harness, --expected and at least one --src" >&2
	exit 2
}

WORK=$(mktemp -d)
rl_traps 'rm -rf "$WORK"'
printf 'int main(void){return 0;}\n' > "$WORK/probe.c"

# THE 64-BIT GATE: does the ordinary build pass this exercise's own fixture?
#
# If it fails -- an unimplemented stub, a bug that has nothing to do with the
# type model -- a portability layer has nothing to add, and a red here would
# just duplicate the output layer. So this layer SKIPS then, and a red means
# something about the 32-bit build.
#
# It is established EVERY time, not only when it could lead to a skip. Under
# NO_SKIP=1 the layer runs past it, and its report still has to know which of
# the two it is looking at: this gate used to be skipped entirely there, and the
# footer then said "passes on the 64-bit build" over off-by-ones the output
# layer was reporting in the same run, and blamed long in code that had none.
#
#   pass     the program ran its fixture, and passed
#   fail     it ran, and failed
#   nobuild  it is a stand-in: these files do not build as a 64-bit program
#            with the flags every layer uses, and *_output says why
#   unknown  not established: no --gate-bin (a hand run), or the differ could
#            not judge it (exit 2 or more), which is said and fails open
#
# The program is *_output's own, never a rebuild here: a rebuild is a second
# copy of the flags, and it was one that differed (-w) -- a warning under
# -Werror made a stand-in for every other layer and a pass for this one.
NATIVE=unknown
NATIVE_WHY="no 64-bit program was given to this layer (--gate-bin)"
if [ -n "$GATE_BIN" ]; then
	if standin_is "$GATE_BIN"; then
		NATIVE=nobuild
		NATIVE_WHY="these files do not build as a 64-bit program"
	else
		rl_split_on
		# shellcheck disable=SC2086
		sh "$DIFFER" --bin "$GATE_BIN" --expected "$EXPECTED" $FIXTURE $PASS > /dev/null 2>&1
		_gate_rc=$?
		rl_split_off
		case "$_gate_rc" in
			0) NATIVE=pass ;;
			1) NATIVE=fail ;;
			*)
				NATIVE_WHY="the 64-bit program could not be judged (its differ exited $_gate_rc)"
				echo "ilp32_test: $NATIVE_WHY, so this layer is running anyway"
				echo "            rather than going quiet." ;;
		esac
	fi
fi

if [ "$NATIVE" = fail ] && [ "${NO_SKIP:-0}" != "1" ]; then
	echo "ilp32_test: SKIP — the ordinary 64-bit build already fails this exercise's"
	echo "            own fixture, so there is nothing platform-specific to report."
	echo "            Fix the *_output layer first; this one will start checking then."
	exit 0
fi
if [ "$NATIVE" = nobuild ] && [ "${NO_SKIP:-0}" != "1" ]; then
	if [ "$(standin_kind "$GATE_BIN")" = empty ]; then
		echo "ilp32_test: SKIP — there is nothing to build yet, so there is nothing"
		echo "            platform-specific to report."
	else
		echo "ilp32_test: SKIP — your code does not build as a 64-bit program, so there"
		echo "            is nothing platform-specific to report. The *_output layer of"
		echo "            this exercise shows the compiler's words."
	fi
	echo "            (NO_SKIP=1 runs this layer anyway.)"
	exit 0
fi

# Pick a 32-bit compiler. Zig first: it carries its own headers and libc, so it
# needs nothing from the host and works on a campus machine where you cannot
# install packages. Bazel fetches it once (see MODULE.bazel). The system
# compilers are a fallback for a host that happens to have gcc-multilib.
CC32=""
CCFLAGS=""
# The same compiler and flags as a list, for the builds below (CC32 and
# CCFLAGS are what the messages print).
C32=""

if [ -n "$ZIG" ] && [ -x "$ZIG" ]; then
	# zig insists on a writable cache, and rebuilds musl's startup objects from
	# scratch without one — ~15s per test. A cache shared across the suite makes
	# that a one-off; zig locks it itself, so parallel tests are safe. Override
	# with ZIG_CACHE_HOME (a fresh dir restores full isolation).
	# PER USER. This was ${TMPDIR:-/tmp}/zig-cache-42 with no user in the name,
	# and /tmp is shared on a campus box: the first student to run the suite
	# creates it 0755, the second gets AccessDenied, zig fails, and -- before the
	# change below -- the layer fell through to the host compilers and then to a
	# SKIP. All 94 ilp32 targets green, having compiled nothing, for the second
	# person to sit down. The same hazard made Bazel's own output root per-user
	# (tools/drives.sh, finding 001): a shared path in /tmp belongs to whoever
	# created it first.
	ZIG_GLOBAL_CACHE_DIR="${ZIG_CACHE_HOME:-${TMPDIR:-/tmp}/zig-cache-42-${USER:-$(id -un)}}"
	ZIG_LOCAL_CACHE_DIR="$ZIG_GLOBAL_CACHE_DIR"
	mkdir -p "$ZIG_GLOBAL_CACHE_DIR" 2>/dev/null
	export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
	if "$ZIG" cc -target x86-linux-musl -static "$WORK/probe.c" -o "$WORK/probe" 2>"$WORK/zig.err"; then
		CC32="$ZIG cc"
		CCFLAGS="-target x86-linux-musl -static"
		rl_list_add C32 "$ZIG" cc -target x86-linux-musl -static
	else
		# A PINNED TOOL THAT IS PRESENT AND WILL NOT RUN IS A WIRING ERROR, not
		# a fact about the student. Falling through from here reached the host
		# compilers and then a SKIP -- so a broken cache directory, a truncated
		# download or a bad --zig path all ended as a silent green.
		#
		# Only when Bazel SUPPLIED a zig, which is the path every target takes.
		# A hand-run without --zig keeps the documented gcc-multilib fallback
		# below; that is a person choosing to use their own toolchain, not the
		# suite quietly deciding to.
		echo "ilp32_test: the pinned 32-bit compiler was supplied and will not run." >&2
		echo "  $ZIG" >&2
		rl_excerpt "$WORK/zig.err" 10 zig-output.txt "" >&2
		echo "  This is a harness fault, not a finding about the exercise: a" >&2
		echo "  fetched tool that cannot start must never degrade into a skip." >&2
		echo "  The usual cause is an unwritable cache dir -- see ZIG_CACHE_HOME." >&2
		exit 2
	fi
fi

if [ -z "$CC32" ]; then
	for cc in ${ILP32_CC:-} gcc-10 gcc clang-12 cc; do
		[ -n "$cc" ] || continue
		command -v "$cc" >/dev/null 2>&1 || continue
		if "$cc" -m32 "$WORK/probe.c" -o "$WORK/probe" 2>/dev/null; then
			CC32="$cc"
			CCFLAGS="-m32"
			rl_list_add C32 "$cc" -m32
			break
		fi
	done
fi

if [ -z "$CC32" ]; then
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no 32-bit compiler, so this layer compiled nothing and"
		echo "checked nothing. Reported as a failure rather than a silent pass —"
		echo "that is the whole point of the forced sweep."
		exit 1
	}
	echo "ilp32_test: SKIP — no 32-bit compiler available."
	echo "            The hermetic one (zig, fetched by Bazel) failed to run, and no"
	echo "            host compiler can target -m32 (needs gcc-multilib/libc6-dev-i386)."
	rl_excerpt "$WORK/zig.err" 5 zig-output.txt "            "
	exit 0
fi

# Confirm the type model really is ILP32 before claiming anything.
printf '#include <stdio.h>\nint main(void){printf("%%zu %%zu\\n",sizeof(int),sizeof(long));return 0;}\n' \
	> "$WORK/model.c"
rl_split_on
# shellcheck disable=SC2086
$C32 "$WORK/model.c" -o "$WORK/model" 2>/dev/null
_model_rc=$?
rl_split_off
if [ "$_model_rc" -eq 0 ]; then
	# conventions: harness tool -- the model probe written above, never the student's code
	MODEL=$("$WORK/model")
	case "$MODEL" in
		"4 4") ;;
		*)
			[ "${NO_SKIP:-0}" != "1" ] || {
				echo "NO_SKIP set: $CC32 reports sizeof(int) sizeof(long) = $MODEL, not"
				echo "4 4, so this layer never exercised a narrow long and checked nothing."
				exit 1
			}
			echo "ilp32_test: SKIP — $CC32 reports sizeof(int) sizeof(long) = $MODEL, not 4 4"
			exit 0
			;;
	esac
fi

# -Wall -Wextra without -Werror: the campus compilers already gate warnings in
# the *_compile_* layers, and this compiler is a different (newer) clang whose
# extra diagnostics would be noise rather than a finding. What is under test here
# is the type model, not the warning set.
rl_split_on
# shellcheck disable=SC2086
$C32 -Wall -Wextra $INCS "$HARNESS" $HSRCS $SRCS $LIBS32 -o "$WORK/bin" 2> "$WORK/cc.err"
_cc_rc=$?
rl_split_off
if [ "$_cc_rc" -ne 0 ]; then
	case "$NATIVE" in
		pass) echo "ilp32_test: FAIL — builds as a 64-bit program, but not for a 32-bit target ($CC32 $CCFLAGS)" ;;
		nobuild) echo "ilp32_test: FAIL — does not build, and the 64-bit build of the same files fails too, so this is not about the 32-bit target ($CC32 $CCFLAGS)" ;;
		*) echo "ilp32_test: FAIL — does not build for a 32-bit target ($CC32 $CCFLAGS)" ;;
	esac
	rl_excerpt "$WORK/cc.err" 25 compiler-output-32bit.txt ""
	exit 1
fi
[ -s "$WORK/cc.err" ] && { echo "ilp32_test: warnings from the 32-bit build:"; rl_excerpt "$WORK/cc.err" 10 compiler-warnings-32bit.txt "  "; }

echo "ilp32_test: built with $CC32 $CCFLAGS (int and long are both 32 bits here)"
rl_split_on
# shellcheck disable=SC2086
sh "$DIFFER" --bin "$WORK/bin" --expected "$EXPECTED" --status-file "$WORK/status" $FIXTURE $PASS
RC=$?
rl_split_off
[ "$RC" -eq 1 ] || exit "$RC"

# WHAT THE RED MEANS, derived from what ran rather than written once for every
# case. It used to be one paragraph -- "passes on the 64-bit build ... the
# difference is the type model" -- printed under any failure: over plain bugs
# the output layer was reporting in the same run, over timeouts, and over the
# SIGILL above, in answers with no long in them at all.
# How the run ended, as diff_output.sh read it from waitpid(): "exit N",
# "signal N" (25 is its output budget) or "timeout".
STATUS=""
[ -f "$WORK/status" ] && read -r STATUS < "$WORK/status"
echo "----------------------------------------------------------------"
case "$NATIVE" in
	fail)
		echo "  The ordinary 64-bit build fails these same cases (see *_output),"
		echo "  so this red repeats that failure rather than adding one. Fix it"
		echo "  there first: NO_SKIP=1 ran this layer anyway, and without it this"
		echo "  layer would have skipped."
		exit 1 ;;
	nobuild)
		echo "  The ordinary 64-bit build of these files does not compile or link"
		echo "  either (*_output shows why), so this red is not about the 32-bit"
		echo "  target. Fix that first."
		exit 1 ;;
	pass)
		echo "  The ordinary 64-bit build passes these cases; this one does not." ;;
	*)
		echo "  Whether the ordinary 64-bit build passes these cases was not"
		echo "  established ($NATIVE_WHY), so read *_output first:"
		echo "  this red may be the same failure." ;;
esac
case "$STATUS" in
	"signal 4")
		echo "  It stopped on SIGILL, which here is not a crash in the usual sense:"
		echo "  this compiler plants a trap at undefined behaviour -- a signed int"
		echo "  (or a 32-bit long) overflowing, an index past the end of an array --"
		echo "  and stops the program at that operation. The 64-bit build runs past"
		echo "  the same operation silently, but it is just as undefined there."
		echo "  Widening through a long is the usual source on this target, not the"
		echo "  only one. The *_diff_asan or *_asan layer names the line."
		;;
	# A loop that never ends, silent or printing: diff_output.sh says TIMEOUT
	# for the first and RUNAWAY OUTPUT (SIGXFSZ) for the second. The second
	# used to fall through to the crash paragraph below, which pointed at a
	# CRASH line that was never printed and blamed memory layout for a loop.
	"timeout" | "signal 25")
		if [ "$NATIVE" = pass ]; then
			if [ "$STATUS" = "signal 25" ]; then
				echo "  It never stopped printing (see RUNAWAY OUTPUT above)."
			else
				echo "  It did not finish in time (see TIMEOUT above)."
			fi
			echo "  Look for a loop whose counter or bound depends on the width of"
			echo "  long or of a pointer: both are 32 bits here, so a count that"
			echo "  ends past 2^32 on 64-bit can wrap around here and never end."
		fi
		;;
	"signal "*)
		if [ "$NATIVE" = pass ]; then
			echo "  It crashed (see the CRASH line above). Memory is laid out differently"
			echo "  here -- long and pointers are 4 bytes -- so an out-of-bounds access"
			echo "  that landed somewhere harmless on 64-bit may not here. The"
			echo "  *_diff_asan or *_asan layer names the line of a memory error."
		fi
		;;
	*)
		if [ "$NATIVE" = pass ]; then
			echo "  It ran to the end and printed something else, so the difference is"
			echo "  the type model: on this target long is 32 bits, the same width as"
			echo "  int. Any step that relies on a wider type to hold a value an int"
			echo "  cannot hold has nothing to widen into."
		fi
		;;
esac
exit 1
