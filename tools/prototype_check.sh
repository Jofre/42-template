#!/bin/sh
# Prototype conformance (tag "prototype").
#
# C has no name mangling, so a function whose SIGNATURE differs from the one the
# subject specifies still links. `int ft_strlen(char *)` where the subject says
# `unsigned int`, a `char` parameter where it says `int`, a missing `const` —
# the harness declares one thing, your file defines another, the linker joins
# them anyway, and the only symptom is wrong values (or none at all, on the
# inputs that happen to agree). The Moulinette compiles against ITS declarations
# and simply KOs.
#
# The fix is to put both in one translation unit: force-include the subject's
# declaration while compiling the student's definition, and the compiler reports
# a conflicting type instead of shrugging. -fsyntax-only, so nothing is linked
# or run — this is a contract check, and it is green on a well-formed stub
# exactly like the norm and compile layers.
#
# LANGUAGE STANDARD — do not add -std= here without re-reading this.
# Five c-12 contracts declare a comparator as `int (*cmp)()`, because that is
# what the subject writes for them (ft_list_find, ft_list_remove_if,
# ft_list_sort, ft_sorted_list_insert, ft_sorted_list_merge — while
# ft_list_foreach_if genuinely does say `int (*cmp)(void *, void *)`). Under
# gnu17, which is what clang-12 and gcc-10 default to, an empty parameter list
# means "unspecified", so a student who writes the fully-typed comparator is
# accepted — correctly. Under C23 `()` means `(void)`, and every one of those
# five would start rejecting correct code. If the toolchain or an explicit
# -std= ever moves past gnu17, re-check those five headers first.
#
# Usage:
#   prototype_check.sh --proto FILE --src FILE [--src FILE]... [--inc DIR]...
#                      [--cc NAME]
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "prototype_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require basename dirname mktemp rm sed

PROTO=""
SRCS=""
INCS=""
CC="${PROTOTYPE_CC:-cc}"
CC_LIBS=""

_dir() {
	if [ -d "$1" ]; then printf '%s\n' "$1"; else dirname "$1"; fi
}

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "prototype_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--proto) need "$1" "$#"; PROTO="$2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--src) need "$1" "$#"; SRCS="$SRCS $2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--inc) need "$1" "$#"; INCS="$INCS -I$(_dir "$2")"; shift 2 ;;
		# The directories the fetched compiler's own shared objects live in.
		# A pinned clang that cannot find libclang-cpp does not fail: the loader
		# falls back to this machine's copy and the layer reports on a compiler
		# nobody pinned. Same flag, same reason, same shape as compile_check.sh.
		--cc-lib)
			need "$1" "$#"
			# Absolute: a relative entry in LD_LIBRARY_PATH resolves against the
			# process's cwd, which is not this script's to assume.
			case "$2" in
				/*) _d=$(dirname "$2") ;;
				*) _d=$(dirname "$PWD/$2") ;;
			esac
			CC_LIBS="${CC_LIBS:+$CC_LIBS:}$_d"
			shift 2 ;;
		--cc) need "$1" "$#"; CC="$2"; shift 2 ;;
		*) echo "prototype_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$PROTO" ] && [ -n "$SRCS" ] || {
	echo "prototype_check.sh: need --proto and at least one --src" >&2
	exit 2
}


# Each --cc-lib directory must EXIST. A moved or mistyped one is the quiet
# failure this arrangement is exposed to: the loader falls back to the default
# search path, finds the box's libraries, and the pinned compiler silently stops
# being pinned. Exit 2 -- the harness is misconfigured, the exercise is not
# wrong. Copied deliberately from compile_check.sh rather than abbreviated.
if [ -n "$CC_LIBS" ]; then
	_ifs=$IFS
	IFS=:
	for _d in $CC_LIBS; do
		[ -d "$_d" ] || {
			IFS=$_ifs
			echo "prototype_check.sh: --cc-lib directory '$_d' does not exist." >&2
			echo "  Without it the loader would fall back to this machine's own" >&2
			echo "  libraries and the pinned compiler would silently stop being" >&2
			echo "  pinned, so this refuses to run rather than pass." >&2
			exit 2
		}
	done
	IFS=$_ifs
	LD_LIBRARY_PATH="$CC_LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	export LD_LIBRARY_PATH
fi

# A COMPILER IS NOT OPTIONAL HERE. This layer compiles something and then reads
# the result, so without a compiler it has checked nothing -- and it used to say
# SKIP and exit 0, which is a PASS to Bazel.
#
# MEASURED, before the fetched clang was wired in above: with a PATH holding 580
# coreutils and no compiler, this family reported 116 forbidden + 102 symbols +
# 96 prototype + 7 header SKIPs and went green -- 321 targets, with forbidden
# and prototype at LEVEL 1, inside the submit gate. //c-piscine/c-piscine-rush-02:
# ex00_forbidden went FAIL -> PASS with them, hiding a real "CALLED BUT NOT
# AUTHORISED: printf".
#
# Now that --cc arrives from Bazel as a pinned, sha256-verified clang, an absent
# compiler is no longer a fact about the student's machine: it is a wiring
# error. Exit 2, the code this repo reserves for "the harness is broken, the
# exercise is not wrong" -- never exit 0.
command -v "$CC" > /dev/null 2>&1 || {
	echo "prototype_check: the compiler '$CC' is not executable." >&2
	echo "  This layer compiles before it inspects, so without one it would be" >&2
	echo "  reporting on nothing. Bazel passes the pinned clang through --cc;" >&2
	echo "  if that is missing the target's data is wrong, which is a harness" >&2
	echo "  fault and not a finding about this exercise." >&2
	exit 2
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

RC=0
for src in $SRCS; do
	# shellcheck disable=SC2086
	if ! "$CC" -fsyntax-only -Wall -Wextra $INCS -include "$PROTO" "$src" \
			2> "$WORK/cc.err"; then
		echo "prototype_check: FAIL — $(basename "$src") does not match the signature"
		echo "                 the subject specifies."
		echo ""
		echo "  The subject fixes each function's return type and parameter list."
		echo "  C has no name mangling, so a different signature still LINKS: the"
		echo "  harness declares one shape, your file defines another, and the"
		echo "  only symptom is wrong values. Compiling both together turns that"
		echo "  into the error below. The declaration it is checking against is"
		echo "  in $(basename "$PROTO")."
		echo ""
		echo "  ---------------- what the compiler said ----------------"
		sed -n '1,20p' "$WORK/cc.err" | sed 's/^/  /'
		RC=1
	fi
done

[ "$RC" -eq 0 ] && echo "prototype_check: OK — signatures match the subject."
exit $RC
