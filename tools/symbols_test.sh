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
require awk basename cat comm dirname grep mktemp rm sed sort tr
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
CC_LIBS=""

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
NM_LIBS=""
# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "symbols_test.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--nm) need "$1" "$#"; NM="$2"; shift 2 ;;
		--nm-lib) need "$1" "$#"; NM_LIBS="${NM_LIBS:+$NM_LIBS:}$(dirname "$2")"; shift 2 ;;
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
		--expect) need "$1" "$#"; EXPECT="$2"; shift 2 ;;
		# A function the grader compiles in with the student's file. Repeatable.
		# Exporting one gets its own verdict: the static-helper advice below is
		# exactly wrong for it.
		--provided) need "$1" "$#"; PROVIDED="${PROVIDED:-} $2"; shift 2 ;;
		--src) need "$1" "$#"; SRCS="$SRCS $2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--inc) need "$1" "$#"; INCS="$INCS -I$(_dir "$2")"; shift 2 ;;
		*) echo "symbols_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$NM" ] || { echo "symbols_test.sh: --nm is required (no PATH fallback by design)" >&2; exit 2; }
[ -x "$NM" ] || { echo "symbols_test.sh: --nm '$NM' is not executable" >&2; exit 2; }

# THE PINNED nm's OWN LIBRARIES, and why this is not the same as pinning nm.
#
# binutils ships FRONTENDS. This nm is 44 KB; everything it does is in libbfd,
# which it names as a bare soname with no RPATH and no RUNPATH. Without a path
# to the fetched copy the loader answers from /lib/x86_64-linux-gnu and the
# "pinned" nm is the box's binutils wearing a pinned name -- and it still
# prints the pinned version, because that string is in the frontend's own
# .rodata. On a campus box whose binutils is NOT 2.38 the version-stamped
# soname does not exist at all and the tool would not start.
#
# Exit 2, never 1: a missing directory is a wiring error, not a finding about
# the exercise. Copied deliberately from compile_check.sh's --cc-lib rather
# than abbreviated -- the shape is the argument.
if [ -n "$NM_LIBS" ]; then
	_ifs=$IFS
	IFS=:
	for _d in $NM_LIBS; do
		[ -d "$_d" ] || {
			IFS=$_ifs
			echo "symbols_test.sh: --nm-lib directory '$_d' does not exist." >&2
			echo "  Without it the loader would fall back to this machine's own" >&2
			echo "  binutils libraries and the pinned nm would silently stop" >&2
			echo "  being pinned, so this refuses to run rather than pass." >&2
			exit 2
		}
	done
	IFS=$_ifs
	LD_LIBRARY_PATH="$NM_LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	export LD_LIBRARY_PATH

	# PROVE THE LOADER AGREED, rather than that the flag arrived.
	#
	# The failure being guarded against is exactly one where the right file is
	# exec'd and the wrong code runs, so checking which file we exec proves
	# nothing. ld.so prints `calling init: <path>` for each library it actually
	# LOADED -- the `trying file=` lines above it are only candidates -- so that
	# is what gets read.
	_loaded=$(LD_DEBUG=libs "$NM" --version 2>&1 > /dev/null |
		sed -n 's/.*calling init: //p' | grep -E 'libbfd|libopcodes|libctf')
	if [ -z "$_loaded" ]; then
		echo "symbols_test.sh: could not observe which libraries '$NM' loaded." >&2
		echo "  LD_DEBUG=libs printed no 'calling init:' line for libbfd, so" >&2
		echo "  either this nm is statically linked (in which case delete" >&2
		echo "  --nm-lib and this check together) or the loader does not" >&2
		echo "  support LD_DEBUG. Refusing rather than assuming: the whole" >&2
		echo "  point of the flag is that a wrong answer here is invisible." >&2
		exit 2
	fi
	for _l in $_loaded; do
		case "$_l" in
			"$NM_LIBS"/*) ;;
			*)
				echo "symbols_test.sh: the pinned nm loaded '$_l'." >&2
				echo "  That is not under --nm-lib ('$NM_LIBS'), so the symbol" >&2
				echo "  table this layer is about to read would be parsed by" >&2
				echo "  this machine's binutils rather than the pinned one." >&2
				echo "  A version string proves nothing here: it lives in the" >&2
				echo "  frontend, not in the library that does the work." >&2
				exit 2
				;;
		esac
	done
fi

[ -n "$EXPECT" ] || { echo "symbols_test.sh: --expect is required" >&2; exit 2; }
[ -n "$SRCS" ] || { echo "symbols_test.sh: at least one --src is required" >&2; exit 2; }

# No compiler means no object, and no object means nm reads nothing -- which
# used to reach the compile step and report "could not compile" with exit 1, the
# status that says the DELIVERABLE is wrong. A missing toolchain is not the
# student's bug. Say so, and let NO_SKIP=1 turn it red for the forced sweep.

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
			echo "symbols_test.sh: --cc-lib directory '$_d' does not exist." >&2
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
	echo "symbols_test: the compiler '$CC' is not executable." >&2
	echo "  This layer compiles before it inspects, so without one it would be" >&2
	echo "  reporting on nothing. Bazel passes the pinned clang through --cc;" >&2
	echo "  if that is missing the target's data is wrong, which is a harness" >&2
	echo "  fault and not a finding about this exercise." >&2
	exit 2
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

# Supplied functions come out of EXTRA into a list of their own. Told "make it
# static", a student who wrote their own ft_putchar keeps it -- static, still
# calling write, still a body the subject never asked for.
SUPPLIED=""
for p in ${PROVIDED:-}; do
	if printf '%s\n' "$EXTRA" | grep -qxF "$p"; then
		SUPPLIED="$SUPPLIED $p"
		EXTRA=$(printf '%s\n' "$EXTRA" | grep -vxF "$p" || true)
	fi
done

if [ -z "$MISSING" ] && [ -z "$EXTRA" ] && [ -z "$SUPPLIED" ]; then
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
if [ -n "$SUPPLIED" ]; then
	echo "  DEFINED HERE, BUT SUPPLIED BY THE GRADER:"
	for p in $SUPPLIED; do
		printf '    %s\n' "$p"
	done
	echo "  The grader compiles its own copy of these with your file, so yours is a"
	echo "  second definition and the program does not link. Declare them and call"
	echo "  them; do not write their bodies. (Making yours static would hide the"
	echo "  clash, not the body you were not asked to write.)"
fi
exit 1
