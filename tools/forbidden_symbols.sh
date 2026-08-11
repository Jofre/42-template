#!/bin/sh
# Check that an exercise only calls its authorized functions.
#
# Compiles each deliverable source on its own and inspects the object's undefined
# symbols (the functions it actually calls). Any symbol that is neither defined
# by the exercise itself, nor in the authorized list, nor a compiler/runtime
# builtin, is reported as forbidden -- mirroring the Moulinette's allowlist.
#
# Usage:
#   forbidden_symbols.sh --allowed CSV [--hdr HEADER]... --src SRC [--src SRC]...
#
#   --allowed CSV   comma-separated authorized function names ("-" = none)
#   --hdr HEADER    a provided header the sources include; its directory is
#                   added to the compiler include path (repeatable)
#   --src SRC       an deliverable source file to inspect (repeatable)
#
# Note: compiler-inserted aggregate-copy builtins (memcpy/memmove/memset/...)
# are tolerated since they are emitted by code generation, not written by you.
#
# -fno-builtin, on the other hand, is what makes the inspection honest. clang
# knows abs(), strlen() and friends by name and is free to replace a call with
# an inline expansion or a constant -- at which point the object file has no
# undefined symbol and nm reports a clean bill of health for code that called a
# function it was not allowed to call. The Moulinette reads the SOURCE, so the
# optimisation would hide the violation from us and not from it.
#
# set -u matches symbols_test.sh, the sibling layer that reads the same nm
# output. Without it an unset variable expands to empty and the verdict loop
# silently iterates over nothing, so the test passes having inspected no
# symbols at all.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "forbidden_symbols.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk basename cat dirname grep mktemp rm sed sort tr
# The compiler is reached through $CC and probed below, like header_check.sh's,
# so it is not in that list: require exits 2 unconditionally, and a box with no
# compiler should make this layer say it checked nothing, not refuse to start.

ALLOWED=""
INCS=""
SRCS=""

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
need() { [ "$2" -ge 2 ] || { echo "forbidden_symbols.sh: $1 needs a value" >&2; exit 2; }; }

# The compiler whose UNDEFINED-symbol list becomes this layer's verdict. Named
# and overridable like header_check.sh's HEADER_CC, because this is the one
# place a compiler choice genuinely moves the answer: printf("...\n") folded to
# puts, scanf resolved as __isoc99_scanf, a struct copy emitted as memcpy. All
# three are "calls a function the subject did not authorise" to this layer, and
# which of them happen is the compiler's decision.
#
# Still not PINNED -- see symbols_test.sh for why doing it here alone would put
# this layer out of step with every object Bazel builds with the box's compiler.
CC="${FORBIDDEN_CC:-cc}"

while [ $# -gt 0 ]; do
	case "$1" in
		--cc) need "$1" "$#"; CC="$2"; shift 2 ;;
		--nm) need "$1" "$#"; NM="$2"; shift 2 ;;
		--allowed) need "$1" "$#"; ALLOWED="$2"; shift 2 ;;
		--hdr) need "$1" "$#"; INCS="$INCS -I $(dirname "$2")"; shift 2 ;;
		--src) need "$1" "$#"; SRCS="$SRCS $2"; shift 2 ;;
		*) echo "forbidden_symbols.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$NM" ] || { echo "forbidden_symbols.sh: --nm is required (no PATH fallback by design)" >&2; exit 2; }
[ -x "$NM" ] || { echo "forbidden_symbols.sh: --nm '$NM' is not executable" >&2; exit 2; }

# No compiler means no object, and this layer's whole verdict is the object's
# undefined-symbol list -- an empty one reads as "calls nothing", which is a
# PASS. That is the false green this repo treats as its worst defect class, so
# it is a skip that NO_SKIP=1 can force, never a quiet success.
command -v "$CC" >/dev/null 2>&1 || {
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no compiler ('$CC'), so nothing was compiled and no"
		echo "             call was inspected."
		exit 1
	}
	echo "forbidden_symbols: SKIP — no C compiler ('$CC') available."
	exit 0
}

if [ "$ALLOWED" = "-" ]; then
	ALLOWED=""
fi
if [ -z "$SRCS" ]; then
	echo "forbidden_symbols.sh: no source files given" >&2
	exit 2
fi

BASELINE="memcpy memmove memset mempcpy bcopy bzero _GLOBAL_OFFSET_TABLE_ __stack_chk_fail"

TMP=$(mktemp -d)
# One trap instead of the three hand-written `rm -rf "$TMP"` that used to sit on
# the exit paths: those covered the failures somebody remembered, and nothing
# covered a signal or a path added later.
trap 'rm -rf "$TMP"' EXIT INT TERM
DEF="$TMP/defined"
UND="$TMP/undefined"
: > "$DEF"
: > "$UND"

for src in $SRCS; do
	dir=$(dirname "$src")
	obj="$TMP/$(basename "$src").o"
	# shellcheck disable=SC2086
	if ! "$CC" -c -fno-stack-protector -fno-builtin -Wall "$src" -I "$dir" $INCS -o "$obj" 2> "$TMP/cc.err"; then
		echo "forbidden_symbols.sh: failed to compile $src" >&2
		cat "$TMP/cc.err" >&2
		exit 2
	fi
	# nm failing (absent, or handed an object it cannot read) would leave both
	# lists empty and make the verdict loop below iterate over nothing —
	# reporting PASS having inspected no symbols. Treat it as infrastructure
	# breakage, not as an exercise that calls nothing.
	if ! "$NM" "$obj" > "$TMP/nm.out" 2> "$TMP/nm.err"; then
		echo "forbidden_symbols: cannot read symbols from $src (nm failed)" >&2
		sed -n '1,5p' "$TMP/nm.err" >&2
		exit 2
	fi
	awk 'NF == 3 { print $3 }' "$TMP/nm.out" >> "$DEF"
	awk '$1 == "U" { print $2 }' "$TMP/nm.out" >> "$UND"
done

ALLOWED_LIST=$(echo "$ALLOWED" | tr ',' ' ')
BAD=""
for sym in $(sort -u "$UND"); do
	if grep -qxF "$sym" "$DEF"; then
		continue
	fi
	ok=0
	for a in $ALLOWED_LIST $BASELINE; do
		if [ "$sym" = "$a" ]; then
			ok=1
			break
		fi
	done
	if [ "$ok" -eq 0 ]; then
		# Collected rather than printed as they are found, so the verdict can
		# show the offending set and the authorised set side by side below.
		BAD="$BAD $sym"
	fi
done

# The whole verdict used to be one bare line per symbol — "FORBIDDEN function
# used: printf" — which is the least this layer could say. It never showed the
# list that WAS allowed, although this script is holding it in $ALLOWED; it
# never said where that list comes from, so it reads like a rule the harness
# invented; it never said the consequence, so it is filed next to a Norm warning
# as a matter of taste; and on success it printed nothing at all, which is
# indistinguishable from a layer that did not run. A beginner takes
# "FORBIDDEN: printf" to mean printf is banned in C, rather than "this exercise
# is allowed a named set of functions and printf is not in it".
if [ -n "$ALLOWED_LIST" ]; then
	SHOWN="$ALLOWED_LIST"
else
	# Plenty of subjects authorise nothing at all, so an empty list is a real
	# answer and not a value that failed to arrive; printing a blank after the
	# label would read as the second.
	SHOWN="none — no external function at all"
fi

if [ -n "$BAD" ]; then
	echo "forbidden_symbols: FAIL — this exercise calls a function it is not"
	echo "                   authorised to call."
	echo ""
	echo "  CALLED BUT NOT AUTHORISED:"
	for sym in $BAD; do
		printf '    %s\n' "$sym"
	done
	echo ""
	echo "  AUTHORISED FOR THIS EXERCISE: $SHOWN"
	echo ""
	echo "  That list is not the harness's opinion: it is the \"Allowed functions\""
	echo "  line of this exercise's subject, copied as written. Calling anything"
	echo "  outside it is an outright KO at the Moulinette — a zero on the"
	echo "  exercise no matter how right the output looks — not a style remark"
	echo "  you can defend later. Re-read that line in the subject and build what"
	echo "  you need out of what it does give you."
	exit 1
fi

echo "forbidden_symbols: OK — every function called is either defined by this"
echo "                   exercise itself or on the subject's authorised list."
echo "                   Authorised: $SHOWN"
exit 0
