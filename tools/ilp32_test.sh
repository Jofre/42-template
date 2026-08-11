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
# Usage:
#   ilp32_test.sh --differ PATH --harness FILE --expected FILE
#                 --src FILE [--src FILE]... [--inc DIR]...
#                 [--stdin FILE] [--labeled] [--clues FILE] [--sanitize]
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
require dirname mkdir mktemp rm sed
# conventions: optional cc -- used only to decide whether the ORDINARY 64-bit
# build already fails, which is the gate that keeps this layer quiet while the
# output layer is red. Without it the gate simply does not fire and the 32-bit
# check runs anyway, so a missing cc costs nothing this layer guarantees.

ZIG=""
DIFFER=""
HARNESS=""
EXPECTED=""
SRCS=""
INCS=""
PASS=""

# --inc takes either a directory or a header file: Bazel's $(location) on an
# hdrs entry resolves to the file, and the compiler needs its directory.
_dir() {
	if [ -d "$1" ]; then printf '%s\n' "$1"; else dirname "$1"; fi
}

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "ilp32_test.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--zig) need "$1" "$#"; ZIG="$2"; shift 2 ;;
		--differ) need "$1" "$#"; DIFFER="$2"; shift 2 ;;
		--harness) need "$1" "$#"; HARNESS="$2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--expected) need "$1" "$#"; EXPECTED="$2"; shift 2 ;;
		--src) need "$1" "$#"; SRCS="$SRCS $2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--inc) need "$1" "$#"; INCS="$INCS -I$(_dir "$2")"; shift 2 ;;
		--stdin) need "$1" "$#"; PASS="$PASS --stdin $2"; shift 2 ;;
		--clues) need "$1" "$#"; PASS="$PASS --clues $2"; shift 2 ;;
		--labeled) PASS="$PASS --labeled"; shift ;;
		--sanitize) PASS="$PASS --sanitize"; shift ;;
		*) echo "ilp32_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$DIFFER" ] && [ -n "$HARNESS" ] && [ -n "$EXPECTED" ] && [ -n "$SRCS" ] || {
	echo "ilp32_test.sh: need --differ, --harness, --expected and at least one --src" >&2
	exit 2
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# If the ordinary 64-bit build already fails this exercise's own fixture — an
# unimplemented stub, a bug that has nothing to do with the type model — then a
# portability layer has nothing to add, and a red here would just duplicate the
# output layer. Report SKIP instead, so that an ilp32 failure always means the
# one thing this layer exists to say: "passes here, breaks where long is narrow".
# shellcheck disable=SC2086
# NO_SKIP=1 forces the layer to run even when the 64-bit build already fails,
# so an all-green suite can be checked for layers that are merely quiet.
if [ "${NO_SKIP:-0}" != "1" ] && command -v cc >/dev/null 2>&1 &&
	cc -w $INCS "$HARNESS" $SRCS -o "$WORK/native" 2>/dev/null; then
	# shellcheck disable=SC2086
	if ! sh "$DIFFER" --bin "$WORK/native" --expected "$EXPECTED" $PASS >/dev/null 2>&1; then
		echo "ilp32_test: SKIP — the ordinary 64-bit build already fails this exercise's"
		echo "            own fixture, so there is nothing platform-specific to report."
		echo "            Fix the *_output layer first; this one will start checking then."
		exit 0
	fi
fi

# Pick a 32-bit compiler. Zig first: it carries its own headers and libc, so it
# needs nothing from the host and works on a campus machine where you cannot
# install packages. Bazel fetches it once (see MODULE.bazel). The system
# compilers are a fallback for a host that happens to have gcc-multilib.
CC32=""
CCFLAGS=""
printf 'int main(void){return 0;}\n' > "$WORK/probe.c"

if [ -n "$ZIG" ] && [ -x "$ZIG" ]; then
	# zig insists on a writable cache, and rebuilds musl's startup objects from
	# scratch without one — ~15s per test. A cache shared across the suite makes
	# that a one-off; zig locks it itself, so parallel tests are safe. Override
	# with ZIG_CACHE_HOME (a fresh dir restores full isolation).
	ZIG_GLOBAL_CACHE_DIR="${ZIG_CACHE_HOME:-${TMPDIR:-/tmp}/zig-cache-42}"
	ZIG_LOCAL_CACHE_DIR="$ZIG_GLOBAL_CACHE_DIR"
	mkdir -p "$ZIG_GLOBAL_CACHE_DIR" 2>/dev/null
	export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
	if "$ZIG" cc -target x86-linux-musl -static "$WORK/probe.c" -o "$WORK/probe" 2>"$WORK/zig.err"; then
		CC32="$ZIG cc"
		CCFLAGS="-target x86-linux-musl -static"
	fi
fi

if [ -z "$CC32" ]; then
	for cc in ${ILP32_CC:-} gcc-10 gcc clang-12 cc; do
		[ -n "$cc" ] || continue
		command -v "$cc" >/dev/null 2>&1 || continue
		if "$cc" -m32 "$WORK/probe.c" -o "$WORK/probe" 2>/dev/null; then
			CC32="$cc"
			CCFLAGS="-m32"
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
	[ -s "$WORK/zig.err" ] && sed -n '1,5p' "$WORK/zig.err" | sed 's/^/            /'
	exit 0
fi

# Confirm the type model really is ILP32 before claiming anything.
printf '#include <stdio.h>\nint main(void){printf("%%zu %%zu\\n",sizeof(int),sizeof(long));return 0;}\n' \
	> "$WORK/model.c"
# shellcheck disable=SC2086
if $CC32 $CCFLAGS "$WORK/model.c" -o "$WORK/model" 2>/dev/null; then
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
# shellcheck disable=SC2086
if ! $CC32 $CCFLAGS -Wall -Wextra $INCS "$HARNESS" $SRCS -o "$WORK/bin" 2> "$WORK/cc.err"; then
	echo "ilp32_test: FAIL — does not build for a 32-bit target ($CC32 $CCFLAGS)"
	sed -n '1,25p' "$WORK/cc.err"
	exit 1
fi
[ -s "$WORK/cc.err" ] && { echo "ilp32_test: warnings from the 32-bit build:"; sed -n '1,10p' "$WORK/cc.err" | sed 's/^/  /'; }

echo "ilp32_test: built with $CC32 $CCFLAGS (int and long are both 32 bits here)"
# shellcheck disable=SC2086
sh "$DIFFER" --bin "$WORK/bin" --expected "$EXPECTED" $PASS
RC=$?
if [ "$RC" -ne 0 ]; then
	echo "----------------------------------------------------------------"
	echo "  This exercise passes on the 64-bit build and fails here, so the"
	echo "  difference is the type model: on this target long is 32 bits, the"
	echo "  same width as int. Any step that relies on a wider type to hold a"
	echo "  value an int cannot hold has nothing to widen into."
fi
exit $RC
