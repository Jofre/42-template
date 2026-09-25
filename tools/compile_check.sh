#!/bin/sh
# Compile a C exercise's source(s) with a specific compiler and -Wall -Wextra
# -Werror, failing on ANY diagnostic. Emitted twice per C exercise (clang-12 and
# gcc-10) so each exercise is checked under BOTH compilers present on the 42
# campus box — catching the compiler-specific -Werror warnings the Moulinette
# would flag. A well-formed stub compiles cleanly, exactly like the norm layer.
#
# Usage:
#   compile_check.sh --cc <compiler> [--cc-lib FILE]... [--inc DIR]...
#                    [--hdr FILE]... --src FILE...
#
#   --cc    compiler to invoke -- a name on PATH (gcc-10) or a path to a
#           FETCHED one (the pinned clang, which is not on PATH anywhere)
#   --cc-lib  a shared library the compiler itself needs; its DIRECTORY is put
#           on the loader's search path (repeatable). Only a fetched compiler
#           needs this: clang is a 100 KB driver and everything it does is in
#           libclang-cpp and libLLVM, so without it the driver either fails to
#           start or -- much worse -- silently loads the BOX's copies and stops
#           being the pinned compiler at all.
#   --cc-progs  a file inside the directory holding the SUBPROGRAMS the compiler
#           shells out to -- in practice the assembler. Passed as -B<dir>/,
#           which is also how gcc finds a target-prefixed `x86_64-linux-gnu-as`
#           without anything being renamed. Verified: if the compiler still
#           resolves `as` to a bare name afterwards it would take the machine's
#           assembler, and this refuses to run.
#   --cc-under  a file inside the fetched compiler's own bin directory (the
#           driver itself will do). Asserts the compiler is really looking
#           inside its own tree -- see the check below, which is the difference
#           between a pinned compiler and one that merely starts.
#   --src   a .c source to compile (repeatable); its directory is auto-added to -I
#   --hdr   a header the sources need (repeatable); not compiled, dir added to -I
#   --inc   an extra include directory (repeatable)

set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "compile_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require basename dirname grep mktemp readlink rm

CC=""
SRCS=""
INCS=""
CC_LIBS=""
CC_UNDER=""
CC_PROGS=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "compile_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--cc) need "$1" "$#"; CC="$2"; shift 2 ;;
		--cc-lib)
			need "$1" "$#"
			# A LIBRARY, and its directory is what goes on the search path.
			# The caller names the file rather than the directory because it is
			# Bazel, which expands a label to a file and has no dirname; and
			# because deriving the directory from the driver cannot work --
			# "clang-12/.." walks through a file and resolves to nothing.
			#
			# Absolute, since a relative entry in LD_LIBRARY_PATH is resolved
			# against the process's cwd, which is not this script's to assume.
			case "$2" in
				/*) _d=$(dirname "$2") ;;
				*) _d=$(dirname "$PWD/$2") ;;
			esac
			CC_LIBS="${CC_LIBS:+$CC_LIBS:}$_d"
			shift 2 ;;
		--cc-progs)
			need "$1" "$#"
			_p=$(readlink -f "$2" 2> /dev/null) || _p=""
			[ -n "$_p" ] || _p="$2"
			CC_PROGS=$(cd "$(dirname "$_p")" 2> /dev/null && pwd -P) || CC_PROGS=""
			[ -n "$CC_PROGS" ] || {
				echo "compile_check.sh: --cc-progs '$2' has no directory" >&2
				exit 2
			}
			shift 2 ;;
		--cc-under)
			# Resolve the FILE, then take its directory. Both compilers work
			# out where they really live -- through "..", and through the
			# symlink Bazel stages a runfile as -- before printing anything, so
			# the comparison only works with both sides resolved the same way.
			# Two earlier attempts compared a path the compiler never prints:
			# string surgery on the relative path leaves a "_main/.." in it, and
			# resolving the DIRECTORY stops at the runfiles tree, whose
			# directories are real even though the files in them are links.
			need "$1" "$#"
			_u=$(readlink -f "$2" 2> /dev/null) || _u=""
			[ -n "$_u" ] || _u="$2"
			CC_UNDER=$(cd "$(dirname "$_u")" 2> /dev/null && pwd -P) || CC_UNDER=""
			[ -n "$CC_UNDER" ] || {
				echo "compile_check.sh: --cc-under '$2' has no directory" >&2
				exit 2
			}
			shift 2 ;;
		--src) need "$1" "$#"; SRCS="$SRCS $2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--hdr) need "$1" "$#"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--inc) need "$1" "$#"; INCS="$INCS -I$2"; shift 2 ;;
		*) echo "compile_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$CC" ] || { echo "compile_check.sh: --cc is required" >&2; exit 2; }
[ -n "$SRCS" ] || { echo "compile_check.sh: at least one --src is required" >&2; exit 2; }

# The matched compiler is present on the 42 box and in a devcontainer rebuilt from
# the current Dockerfile. If it is missing (an old image not yet rebuilt), skip
# loudly rather than reporting a false failure for the whole suite.
# Each one must EXIST. A mistyped or moved libdir is the quiet failure this
# whole arrangement is exposed to: the loader simply falls back to the default
# search path, finds the box's libclang-cpp, and every compile passes -- with
# the layer reporting on a compiler nobody pinned, which is the exact thing
# fetching it was meant to prevent. There is no way to notice that from the
# output, so it has to be noticed here. Exit 2: the harness is misconfigured,
# the exercise is not wrong.
if [ -n "$CC_LIBS" ]; then
	_ifs=$IFS
	IFS=:
	for _d in $CC_LIBS; do
		[ -d "$_d" ] || {
			IFS=$_ifs
			echo "compile_check.sh: --cc-lib directory '$_d' does not exist." >&2
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

# What to call the compiler in the output. A fetched one arrives as a runfiles
# path 60 characters long, and "compile_check: ../+deb_archive+clang_12_ubuntu/
# usr/lib/llvm-12/bin/clang-12 OK" tells a student nothing they wanted to know.
CC_NAME=${CC##*/}

# A path resolves as a file; a bare name resolves on PATH. `command -v` answers
# both, which is what lets one runner drive a fetched compiler and a host one.
if ! command -v "$CC" >/dev/null 2>&1; then
	# NO_SKIP=1: an absent toolchain is a failure, not a quiet pass. Without this
	# guard the skip was invisible in exactly the run meant to expose it: compile
	# is a LEVEL 1 layer inside the submit gate at every level, so on an image
	# predating the clang-12/gcc-10 pinning, `bazel test //... --test_env=NO_SKIP=1`
	# — the command whose whole purpose is to tell "quiet because clean" from
	# "quiet because it never ran" — reported a green compile layer for every C
	# exercise in the repo, with nothing ever handed to a compiler.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: '$CC' is not installed, and this layer must not report a silent pass."
		exit 1
	}
	echo "compile_check: '$CC_NAME' not found — SKIP (rebuild the devcontainer to match the 42 box)" >&2
	exit 0
fi

# The assembler, for the compilers that use an external one. -B puts a directory
# at the FRONT of the subprogram search, and gcc accepts the target-prefixed
# name it finds there, so nothing needs renaming.
#
# Then check it took. `-print-prog-name=as` answers with an absolute path when
# the compiler found one and with the bare word "as" when it did not -- and the
# bare word means it will take whatever the machine's PATH offers at assembly
# time, the same silent substitution --cc-lib and --cc-under exist to prevent.
# (clang assembles internally and answers "as" whatever it is passed, which is
# why this is only asked of a caller that supplied --cc-progs.)
BFLAG=""
if [ -n "$CC_PROGS" ]; then
	BFLAG="-B$CC_PROGS/"
	_as=$("$CC" "$BFLAG" -print-prog-name=as 2>&1)
	# UNDER the pinned directory, not merely absolute. "Absolute" is satisfied
	# by /usr/bin/as, which is the machine's -- and clang answers with exactly
	# that whether or not -B found anything, so the weaker test would have
	# called the host assembler a success.
	case "$_as" in
		"$CC_PROGS"/*) ;;
		*)
			echo "compile_check.sh: '$CC_NAME' did not take the pinned assembler." >&2
			echo "" >&2
			echo "  -B$CC_PROGS/ was passed, and -print-prog-name=as answers" >&2
			echo "  '$_as'" >&2
			echo "  which is not inside that directory -- so at assembly time it" >&2
			echo "  would use this machine's assembler, whichever that is." >&2
			echo "  Refusing rather than passing." >&2
			exit 2
			;;
	esac
fi

# Is the fetched compiler actually using the fetched compiler?
#
# Starting is not the same as being pinned. gcc finds cc1 by walking up from its
# own path, and if that tree is not staged it falls back to the box's -- same
# driver, different compiler, no diagnostic. clang does the equivalent with its
# resource directory. Both print where they will look, and both name their own
# root when the fetch is complete, so one question answers it for either:
# does the compiler's own directory appear in its search path?
#
# Only asked when the caller says which directory that is. A compiler installed
# on the box and named by an absolute path is not required to list /usr/bin
# among its search dirs, and failing that would be a false alarm about a
# perfectly ordinary setup.
if [ -n "$CC_UNDER" ]; then
	if ! "$CC" -print-search-dirs 2>&1 | grep -qF "$CC_UNDER"; then
		echo "compile_check.sh: '$CC_NAME' is not searching its own tree." >&2
		echo "" >&2
		echo "  Expected to find: $CC_UNDER" >&2
		echo "  in its -print-search-dirs, and it is not there. The compiler" >&2
		echo "  starts, compiles, and reports the pinned version -- while using" >&2
		echo "  this machine's cc1 or resource headers, because part of the" >&2
		echo "  fetched tree was not staged. Nothing in the output would say so," >&2
		echo "  so this refuses to run instead of passing." >&2
		exit 2
	fi
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

rc=0
for s in $SRCS; do
	if "$CC" ${BFLAG:+"$BFLAG"} -Wall -Wextra -Werror $INCS -c "$s" -o "$WORK/$(basename "$s").o"; then
		echo "compile_check: $CC_NAME OK   $s"
	else
		echo "compile_check: $CC_NAME FAIL $s" >&2
		rc=1
	fi
done
exit $rc
