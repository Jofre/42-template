#!/bin/sh
# Check that a deliverable exports EXACTLY the function(s) the subject asks for,
# and keeps everything else to itself.
#
# Why this is worth a test layer of its own: the Moulinette and your evaluator
# compile your file together with a main() you have never seen. Every function
# you define without `static` is a name reserved in that shared namespace, so a
# helper called ft_strlen, length or is_whitespace can collide with theirs and
# the link fails — on code that is otherwise perfect, with an error that points
# at a file you did not write. Marking helpers static gives them internal
# linkage: they stay usable inside your file and stop existing outside it.
#
# The check is on DEFINED global symbols (nm codes T/D/B/R/W), not on calls.
#
# Usage:
#   symbols_test.sh --expect NAME[,NAME...] --src FILE [--src FILE]... [--inc DIR]...
#
# Exit status: 0 if the exported set matches exactly, 1 otherwise.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "symbols_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk basename cat comm dirname mktemp rm sed sort tr
# The compiler is reached through $CC and probed below, like header_check.sh's,
# so it is not in that list: require exits 2 unconditionally, and a box with no
# compiler should make this layer say it checked nothing, not refuse to start.

EXPECT=""
SRCS=""
INCS=""

# The compiler that builds the objects nm then reads. Named and overridable like
# header_check.sh's HEADER_CC and prototype_check.sh's PROTOTYPE_CC, rather than
# a bare `cc` buried mid-script: this layer's four sibling runners all let a
# campus box point them at a specific compiler, and two did not.
#
# It is NOT pinned, and that is a deliberate limit rather than an oversight. The
# defined-symbol set this layer reads (a function is named what the source names
# it) barely moves between compilers, and Bazel's own cc_library builds every
# other object in the repo with the box's compiler too -- pinning here alone
# would make this layer disagree with the objects the rest of the suite reads.
# Making the whole cc_binary toolchain hermetic is a rules_cc job; see TODO.md's hermeticity survey.
CC="${SYMBOLS_CC:-cc}"

# --inc takes either a directory or a header file: Bazel's $(location) on an
# hdrs entry resolves to the file, and the compiler needs its directory.
_dir() {
	if [ -d "$1" ]; then printf '%s\n' "$1"; else dirname "$1"; fi
}

# ---------------------------------------------------------------------------
# nm is SUPPLIED, never found. --nm is required and there is no PATH fallback,
# for the reason every pinned tool here has one: a check whose answer depends on
# which binary happened to be first on PATH is not a check. This one is not
# hypothetical -- the 2026-08-09 campus audit caught nm resolving to a student's
# own Homebrew binutils 2.46.1, shadowing the system 2.38 the Moulinette uses.
# Exit 2 rather than 1 if it is missing: nothing was checked, so this is a broken
# harness and not a wrong deliverable.
NM=""
# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "symbols_test.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--nm) need "$1" "$#"; NM="$2"; shift 2 ;;
		--cc) need "$1" "$#"; CC="$2"; shift 2 ;;
		--expect) need "$1" "$#"; EXPECT="$2"; shift 2 ;;
		--src) need "$1" "$#"; SRCS="$SRCS $2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--inc) need "$1" "$#"; INCS="$INCS -I$(_dir "$2")"; shift 2 ;;
		*) echo "symbols_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$NM" ] || { echo "symbols_test.sh: --nm is required (no PATH fallback by design)" >&2; exit 2; }
[ -x "$NM" ] || { echo "symbols_test.sh: --nm '$NM' is not executable" >&2; exit 2; }

[ -n "$EXPECT" ] || { echo "symbols_test.sh: --expect is required" >&2; exit 2; }
[ -n "$SRCS" ] || { echo "symbols_test.sh: at least one --src is required" >&2; exit 2; }

# No compiler means no object, and no object means nm reads nothing -- which
# used to reach the compile step and report "could not compile" with exit 1, the
# status that says the DELIVERABLE is wrong. A missing toolchain is not the
# student's bug. Say so, and let NO_SKIP=1 turn it red for the forced sweep.
command -v "$CC" >/dev/null 2>&1 || {
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no compiler ('$CC'), so no object was built and no"
		echo "             symbol was inspected."
		exit 1
	}
	echo "symbols_test: SKIP — no C compiler ('$CC') available."
	exit 0
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# shellcheck disable=SC2086
for s in $SRCS; do
	if ! "$CC" -w -c "$s" $INCS -o "$WORK/$(basename "$s").o" 2> "$WORK/cc.err"; then
		echo "symbols_test: could not compile $s"
		sed -n '1,20p' "$WORK/cc.err"
		exit 1
	fi
done

# Defined symbols only: nm marks them with an uppercase code (lowercase = local,
# which is exactly what `static` produces, and exactly what we want to allow).
"$NM" "$WORK"/*.o 2>/dev/null | awk '$2 ~ /^[TDBRW]$/ { print $3 }' | sort -u > "$WORK/have"
printf '%s\n' "$EXPECT" | tr ',' '\n' | sed '/^$/d' | sort -u > "$WORK/want"

# Symbols that legitimately CROSS a file boundary.
#
# Some subjects ask for more than one file — c-07 ex04 turns in both
# ft_convert_base.c and ft_convert_base2.c — and a helper that one file defines
# and the other calls MUST have external linkage. `static` is not an option
# there; it would not link. Demanding that such an exercise export only the
# subject's function is asking for something the subject itself made impossible.
#
# So: a defined symbol is justified when ANOTHER object in the same exercise
# lists it as undefined. That still rejects a stray global nothing else uses,
# which is the collision risk this layer exists for. With a single source file
# nothing can qualify, so single-file exercises are unaffected.
: > "$WORK/cross"
for o in "$WORK"/*.o; do
	for other in "$WORK"/*.o; do
		[ "$o" = "$other" ] && continue
		"$NM" "$o" 2>/dev/null | awk '$2 ~ /^[TDBRW]$/ { print $3 }' | sort -u > "$WORK/_def"
		"$NM" "$other" 2>/dev/null | awk '$1 == "U" { print $2 }' | sort -u > "$WORK/_und"
		comm -12 "$WORK/_def" "$WORK/_und" >> "$WORK/cross"
	done
done
sort -u -o "$WORK/cross" "$WORK/cross"
cat "$WORK/want" "$WORK/cross" | sort -u > "$WORK/allowed"

MISSING=$(comm -13 "$WORK/have" "$WORK/want")
EXTRA=$(comm -23 "$WORK/have" "$WORK/allowed")
CROSS=$(comm -12 "$WORK/cross" "$WORK/have")

if [ -z "$MISSING" ] && [ -z "$EXTRA" ]; then
	if [ -n "$CROSS" ]; then
		echo "symbols_test: OK — exports $(tr '\n' ' ' < "$WORK/want")plus $(printf '%s' "$CROSS" | tr '\n' ' ')"
		echo "              (the extra name(s) are defined in one of this exercise's files"
		echo "               and called from another, so they have to be external — the"
		echo "               subject asks for both files.)"
	else
		echo "symbols_test: OK — exports exactly: $(tr '\n' ' ' < "$WORK/want")"
	fi
	exit 0
fi

echo "symbols_test: FAIL"
if [ -n "$MISSING" ]; then
	echo "  NOT DEFINED (the subject asks for these):"
	printf '%s\n' "$MISSING" | sed 's/^/    /'
	echo "  Check the spelling of the function name against the subject."
fi
if [ -n "$EXTRA" ]; then
	echo "  EXPORTED BUT NOT ASKED FOR:"
	printf '%s\n' "$EXTRA" | sed 's/^/    /'
	echo "  These names are visible to the linker, so they collide with anything of"
	echo "  the same name in the main() your evaluator compiles alongside your file."
	echo "  A helper only your file uses does not need to be visible outside it —"
	echo "  see what the 'static' storage class does to a function's linkage."
	echo "  (A helper that ANOTHER of this exercise's files calls is allowed to be"
	echo "   external; it is only the ones nobody else references that must be static.)"
fi
exit 1
