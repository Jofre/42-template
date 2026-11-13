#!/bin/sh
# Check that an exercise only calls its authorized functions -- and, in its two
# other modes, that each FUNCTION does, or that the turn-in defines no global
# variable.
#
# Compiles each deliverable source on its own and inspects the object's undefined
# symbols (the functions it actually calls). Any symbol that is neither defined
# by the exercise itself, nor in the authorized list, nor a compiler/runtime
# builtin, is reported as forbidden -- mirroring the Moulinette's allowlist.
#
# Usage:
#   forbidden_symbols.sh --nm NM --nm-lib LIB... [--cc CC [--cc-lib LIB]...]
#                        [--hdr HEADER]... [--inc-file FILE] --src SRC...
#                        then ONE of:
#     [--allowed CSV] [--provided NAME]...       the whole turn-in, one list
#     --globals --quotes FILE                    no global variable at all
#     --function NAME=CSV... [--through]
#       --objdump OBJDUMP --objdump-lib LIB... --quotes FILE
#                                                each function, its own list
#
#   --allowed CSV   comma-separated authorized function names ("-" = none),
#                   plus any variable the subject allows by name (errno)
#   --hdr HEADER    a provided header the sources include; its directory is
#                   added to the compiler include path (repeatable)
#   --inc-file FILE include directories, one per line, each added to the path:
#                   the -I a Makefile's recipes pass (see compile_check.sh --
#                   the include path is the grader's, and a header in a
#                   subfolder is on it only through the Makefile's -I)
#   --src SRC       an deliverable source file to inspect (repeatable)
#   --quotes FILE   KEY<TAB>TEXT lines (tools/runner_lib.sh, rl_quote): the
#                   sentence each red of the two other modes quotes --
#                   `globals` for --globals, and for --function one key
#                   `functions:NAME` per NAME, quoted under that function.
#
# --globals: every data object a turned-in file defines OUTSIDE every function
# is a red: external or static, const or not, initialised or not -- nm codes
# B b D d R r C V v G g S s, read from a -g compile so `nm -l` can say on
# which line it was defined. One defined INSIDE a function body (a `static`
# local) is not one: the compiler names it with a '.' in it (clang-12 f.k,
# gcc k.2), which no name written in C holds, and that is how it is told
# apart. A string literal has no symbol at all, so it is never seen. clang
# leaves out of an object a static it folded or never used, so this compile
# adds -femit-all-decls, and proves on a probe that the variables stay (A
# COMPILE THAT KEEPS EVERY VARIABLE, below); one the compile drops is exit 2.
# A header's variable is in the object of every file that includes it, and is
# named once.
#
# --function NAME=CSV (repeatable; CSV may be empty or "-": calls nothing):
# NAME may reference only the external symbols in ITS list. Each source is
# compiled as for the default mode plus -ffunction-sections -fdata-sections,
# so every function and every data object sits in a section of its own, and
# the pinned objdump's relocations of a function's section are exactly what
# that function's code references. From NAME's section the check follows
# every reference into the turn-in -- a static helper, a helper that is not
# static, a data object (a table of function pointers) -- transitively, each
# section once, so a cycle ends; what it reaches that no turned-in file
# defines is what NAME uses, and counts against NAME's list. A reference to
# another function named by a --function is NOT followed (it is checked
# against its own list) and is not forbidden either; with --through it IS
# followed, and what it uses counts against the caller's list too, the red
# showing the chain (caller -> other -> symbol). Such a red is the reading's
# alone, so it says so and claims no KO: the walk first goes everywhere it
# can WITHOUT entering another listed function, and only then, under
# --through, on into them, so a name it reaches only that way is marked, and
# one the function's own code reaches as well is not.
#   A listed function is the definition the other files can call -- global or
# weak -- and a static one only where no file defines it so: a static helper
# of the same name in another file is a helper like any other, followed by
# whatever calls it and never mistaken for the listed function.
#   Each listed function's code must sit in a section named .text.NAME, which
# -ffunction-sections gives it. One nm sees defined that has no such section
# (a compile that ignored the flag, a section attribute) could not be walked,
# so it is exit 2, never "not checked".
#   What it cannot see: a function called through a pointer the function was
# HANDED (a parameter) leaves no relocation naming its target, so that call
# is nobody's in this check -- the place the pointer was taken from (a
# function or table that names it) is where it is seen, against that
# place's list. A name reached through data is reported at the data
# object's own definition, where `nm -l` gives one (a variable at file
# scope), and at no place where it does not (a static inside a function):
# never at a line some other code names it on.
#   A NAME no turned-in file defines is not this check's business -- the
# function's own tests say it is missing -- so it is noted on the way out,
# never red.
#   The compiler/runtime symbols forgiven are exactly the default mode's:
# BASELINE below (memcpy and friends, only while no source names them), and
# the names glibc's headers compile a public name into (public_of, judged in
# the public name against NAME's list). Nothing else.
#
# A missing --quotes, objdump or nm, a compile that fails (the compile layer's
# red, not this one's) or a mix of modes is exit 2: nothing was checked.
#
# Note: compiler-inserted aggregate-copy builtins (memcpy/memmove/memset/...)
# are tolerated since they are emitted by code generation, not written by you --
# but only while your source does not call them itself, by name or as
# __builtin_<name>. See the exemption block
# further down: the tolerance is for what the compiler emitted, never for what
# you wrote.
#
# Note too that nm does not always see the name you wrote. glibc's headers turn
# some public names into internal ones -- errno into a call to
# __errno_location(), <libgen.h>'s basename into __xpg_basename, the <ctype.h>
# classifiers into __ctype_b_loc -- so this layer maps them back through the
# alias table below (public_of) before it judges or reports anything. The
# allowed list is written in the subject's names, and so is the verdict.
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
require awk cat dirname grep head mkdir mktemp rm sed sort tr

# The shared runner helpers -- exiting signal traps and excerpts that say what
# they left out -- written once in tools/runner_lib.sh.
RL_NAME=forbidden_symbols
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "forbidden_symbols.sh: tools/runner_lib.sh is not staged (tools/defs_test.bzl's _test() stages it for every test; by hand, run this by its path in the repository)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool CC -- the pinned compiler: it builds, and runs none of what it builds
# conventions: harness tool NM -- the pinned nm: it reads symbols, and runs nothing
# conventions: harness tool OBJDUMP -- the pinned objdump: it reads relocations, and runs nothing

# The compiler is reached through $CC and probed below, like header_check.sh's,
# so it is not in that list: require exits 2 unconditionally, and a box with no
# compiler should make this layer say it checked nothing, not refuse to start.

ALLOWED=""
ALLOWED_GIVEN=0
INCS=""
SRCS=""
PROVIDED=""
# The two other modes (header): --globals, and --function's NAME=CSV pairs,
# one per line, with --through's reading.
GLOBALS=0
FUNCS=""
THROUGH=0

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
# objdump, for --function alone, supplied the same way and for the same reason.
OBJDUMP=""
OBJDUMP_LIBS=""
# The directory a library flag's file is in, absolute.
abs_dir() {
	case "$1" in
		/*) dirname "$1" ;;
		*) dirname "$PWD/$1" ;;
	esac
}

# The compiler whose UNDEFINED-symbol list becomes this layer's verdict. Named
# and overridable like header_check.sh's HEADER_CC, because this is the one
# place a compiler choice genuinely moves the answer: printf("...\n") folded to
# puts, scanf resolved as __isoc99_scanf, a struct copy emitted as memcpy. All
# three are "calls a function the subject did not authorise" to this layer, and
# which of them happen is the compiler's decision.
#
# FORBIDDEN_CC is the hand-run default only: every test is handed the pinned
# clang-12 (--cc), campus's cc, which the macros require of it
# (tools/defs_toolchain.bzl's _PINNED_CC_RUNNERS and pinned_cc_problem) -- so
# the folds above are the ones campus's compiler makes.
CC="${FORBIDDEN_CC:-cc}"
CC_LIBS=""

while [ $# -gt 0 ]; do
	case "$1" in
		# The fetched compiler's own shared objects, one per line (LISTS OF
		# WORDS). A pinned clang that cannot find libclang-cpp does not fail:
		# the loader falls back to this machine's copy and the layer reports on
		# a compiler nobody pinned. rl_cc_pin, below, proves them.
		--cc-lib) rl_need "$1" "$#"; rl_list_add CC_LIBS "$2"; shift 2 ;;
		--cc) rl_need "$1" "$#"; CC="$2"; shift 2 ;;
		--nm) rl_need "$1" "$#"; NM="$2"; shift 2 ;;
		# Absolute, as --cc-lib's: each tool runs with its directories on
		# LD_LIBRARY_PATH (rl_binutils_pin), where a relative one would be
		# resolved against whatever directory the tool runs in.
		--nm-lib) rl_need "$1" "$#"; NM_LIBS="${NM_LIBS:+$NM_LIBS:}$(abs_dir "$2")"; shift 2 ;;
		--objdump) rl_need "$1" "$#"; OBJDUMP="$2"; shift 2 ;;
		--objdump-lib) rl_need "$1" "$#"; OBJDUMP_LIBS="${OBJDUMP_LIBS:+$OBJDUMP_LIBS:}$(abs_dir "$2")"; shift 2 ;;
		--allowed) rl_need "$1" "$#"; ALLOWED="$2"; ALLOWED_GIVEN=1; shift 2 ;;
		--globals) GLOBALS=1; shift ;;
		--function) rl_need "$1" "$#"; rl_list_add FUNCS "$2"; shift 2 ;;
		--through) THROUGH=1; shift ;;
		--quotes) rl_need "$1" "$#"; rl_quotes_opt "$2"; shift 2 ;;
		# A function the GRADER compiles in with the student's file (Piscine
		# Reloaded's ft_putchar.c). Repeatable. Calling it is authorised;
		# defining it is the mistake -- see the verdict below.
		--provided) rl_need "$1" "$#"; rl_list_add PROVIDED "$2"; shift 2 ;;
		--hdr) rl_need "$1" "$#"; rl_list_add INCS -I "$(dirname "$2")"; shift 2 ;;
		--inc-file) rl_need "$1" "$#"; rl_inc_file INCS "$2"; shift 2 ;;
		--src) rl_need "$1" "$#"; rl_list_add SRCS "$2"; shift 2 ;;
		*) echo "forbidden_symbols.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

# WHICH MODE (header). One per run: each is a target of its own, and a run that
# mixed two would print two verdicts under one exit status.
MODE=union
[ "$GLOBALS" = 0 ] || MODE=globals
if [ -n "$FUNCS" ]; then
	[ "$MODE" = union ] || {
		echo "forbidden_symbols.sh: --globals and --function are two checks; run each on its own" >&2
		exit 2
	}
	MODE=function
fi
if [ "$MODE" != union ] && { [ "$ALLOWED_GIVEN" = 1 ] || [ -n "$PROVIDED" ]; }; then
	echo "forbidden_symbols.sh: --allowed and --provided belong to the default mode, not to --$MODE" >&2
	exit 2
fi
[ "$THROUGH" = 0 ] || [ "$MODE" = function ] || {
	echo "forbidden_symbols.sh: --through reads --function's lists, and none was given" >&2
	exit 2
}
# The sentence each red quotes comes from the call site (runner_lib.sh, A
# SUBJECT'S SENTENCE COMES FROM THE CALL SITE). The default mode quotes none,
# so a file handed to it would be read by nothing.
case $MODE in
	union)
		[ -z "$RL_QUOTES" ] || {
			echo "forbidden_symbols.sh: --quotes is for --globals and --function; the default mode quotes nothing" >&2
			exit 2
		} ;;
	globals) rl_quotes_ready globals ;;
esac
if [ "$MODE" = function ]; then
	# NAME=CSV, a C name and a list of them, which may be empty ("" or "-").
	_bad=$(printf '%s\n' "$FUNCS" |
		grep -vE '^[A-Za-z_][A-Za-z0-9_]*=(-|[A-Za-z_][A-Za-z0-9_]*(,[A-Za-z_][A-Za-z0-9_]*)*)?$')
	[ -z "$_bad" ] || {
		echo "forbidden_symbols.sh: each --function is NAME=CSV (CSV empty or - for none); not:" >&2
		printf '  %s\n' "$_bad" >&2
		exit 2
	}
	_dup=$(printf '%s\n' "$FUNCS" | sed 's/=.*//' | sort | awk 'seen[$0]++ == 1')
	[ -z "$_dup" ] || {
		echo "forbidden_symbols.sh: two --function lists for one name: $_dup" >&2
		exit 2
	}
	# One sentence per function, `functions:NAME`: each function's list is
	# its own box's, so the line its red quotes is too -- no one sentence is
	# true of every function's list.
	rl_quotes_ready "$(printf '%s\n' "$FUNCS" | sed 's/=.*//; s/^/functions:/' | tr '\n' ' ')"
	[ -n "$OBJDUMP" ] || { echo "forbidden_symbols.sh: --function needs --objdump (no PATH fallback by design)" >&2; exit 2; }
	[ -x "$OBJDUMP" ] || { echo "forbidden_symbols.sh: --objdump '$OBJDUMP' is not executable" >&2; exit 2; }
	[ -n "$OBJDUMP_LIBS" ] || {
		echo "forbidden_symbols.sh: --objdump needs --objdump-lib, the directory of the" >&2
		echo "  pinned objdump's own libbfd: without it the loader takes this machine's" >&2
		echo "  (no fallback by design: see THE PINNED nm's OWN LIBRARIES in" >&2
		echo "  tools/runner_lib.sh)." >&2
		exit 2
	}
fi

[ -n "$NM" ] || { echo "forbidden_symbols.sh: --nm is required (no PATH fallback by design)" >&2; exit 2; }
[ -x "$NM" ] || { echo "forbidden_symbols.sh: --nm '$NM' is not executable" >&2; exit 2; }
[ -n "$NM_LIBS" ] || {
	echo "forbidden_symbols.sh: --nm needs --nm-lib, the directory of the pinned nm's" >&2
	echo "  own libbfd: without it the loader takes this machine's, and the nm is" >&2
	echo "  pinned in name only (no fallback by design)." >&2
	exit 2
}

# THE PINNED nm and objdump, each proved to load its own libraries, and
# each with its own path (tools/runner_lib.sh, rl_binutils_pin: THE PINNED
# nm's OWN LIBRARIES, EACH TOOL ITS OWN PATH). The path a tool is proved
# under is the one every run of it is given (NM_PATH, OBJDUMP_PATH), and
# nothing is exported: the compiler's --cc-lib, below, reaches neither.
# nm's work is libbfd's; objdump's is libbfd's, libopcodes' and libctf's.
rl_binutils_pin nm "$NM" "$NM_LIBS" --nm-lib libbfd
NM_PATH=$RL_PB_PATH
OBJDUMP_PATH=""
if [ "$MODE" = function ]; then
	rl_binutils_pin objdump "$OBJDUMP" "$OBJDUMP_LIBS" --objdump-lib libbfd libopcodes libctf
	OBJDUMP_PATH=$RL_PB_PATH
fi

# THE PINNED COMPILER, proved before the first compile (tools/runner_lib.sh,
# rl_cc_pin): each --cc-lib directory exists and goes first on the exported
# LD_LIBRARY_PATH, the compiler is there and starts, and the loader took its
# libraries from those directories, with the libxml2 and ICU a libLLVM loads
# (V321). Each failure is exit 2. This runner kept its own copy of the first
# three, written before rl_cc_pin, and never made the last: a pinned clang on
# this machine's libxml2 or ICU passed here while rl_cc_pin refused it.
#
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
# And it must START (rl_cc_starts, V241): the --globals probe below read a
# compiler the loader could not start as one that "leaves out of its object a
# static", with the loader's words in no log.
rl_cc_pin "$CC" "$CC_LIBS" ""

if [ "$ALLOWED" = "-" ]; then
	ALLOWED=""
fi
if [ -z "$SRCS" ]; then
	echo "forbidden_symbols.sh: no source files given" >&2
	exit 2
fi

BASELINE="memcpy memmove memset mempcpy bcopy bzero _GLOBAL_OFFSET_TABLE_ __stack_chk_fail"

TMP=$(mktemp -d) || { echo "$RL_NAME.sh: cannot create a scratch directory" >&2; exit 2; }
# One trap instead of the three hand-written `rm -rf "$TMP"` that used to sit on
# the exit paths: those covered the failures somebody remembered, and nothing
# covered a signal or a path added later.
rl_traps 'rm -rf "$TMP"'
DEF="$TMP/defined"
UND="$TMP/undefined"
: > "$DEF"
: > "$UND"
: > "$TMP/code.raw"
: > "$TMP/hdrs"
# What the two other modes read from each object, one line per symbol or
# reference, each led by the source's number (n below): the data objects
# --globals reports, and --function's symbol table and relocations.
: > "$TMP/globals"
: > "$TMP/fsyms"
: > "$TMP/frels"
: > "$TMP/flocs"
: > "$TMP/fdlocs"
: > "$TMP/isat"

# The compile of the two other modes adds, to the default mode's, -g for
# `nm -l`'s file:line, and a section per function and per data object for
# --function's relocations (header). Neither changes which symbols an object
# defines or references, and neither is an -O: the code read is the grader's.
# One word per line, as INCS is: the loop splits on newlines alone.
XFLAGS=""
[ "$MODE" = union ] || rl_list_add XFLAGS -g -ffunction-sections -fdata-sections
HERE_P=$(pwd -P)
# A source's path as every record below spells it: less this folder -- its
# logical path ($PWD, pwd's) or its physical one (HERE_P), which differ where
# a symbolic link leads here -- and less a leading ./. objdump's places
# (flocs), nm -l's (fdlocs) and the preprocessor's (isat) are matched by
# FILE:LINE, so they must be cut alike: one function, put at the start of
# each of those programs, which are handed pwd="$PWD/" and phys="$HERE_P/".
# (place(), below, is the shell's own, with its fallback for an empty one.)
FS_AWK_REL='function rel(p) {
	if (index(p, pwd) == 1) p = substr(p, length(pwd) + 1)
	else if (index(p, phys) == 1) p = substr(p, length(phys) + 1)
	sub(/^\.\//, "", p)
	return p
}'
# nm_read LABEL [FLAG...] -- the pinned nm, under the path it was proved
# under, over this source's object into $TMP/nm.out. nm failing (absent, or
# handed an object it cannot read) would leave every list read from it empty
# and the verdict iterate over nothing -- a PASS having inspected no symbols
# -- so it is a harness fault, exit 2, naming LABEL.
nm_read() {
	_nr_label=$1
	shift
	if ! LD_LIBRARY_PATH="$NM_PATH" LC_ALL=C "$NM" "$@" "$obj" > "$TMP/nm.out" 2> "$TMP/nm.err"; then
		echo "forbidden_symbols: cannot read symbols from $src ($_nr_label failed)" >&2
		rl_excerpt "$TMP/nm.err" 5 nm-output.txt "" >&2
		exit 2
	fi
}

# --globals: A COMPILE THAT KEEPS EVERY VARIABLE IT WAS GIVEN, proven before
# it is trusted. clang, even with no -O, leaves out of the object a static it
# has no use for: a `static const int` whose value it folded into the code
# that reads it, a `static const char *const` it read the same way, and a
# static a header defines that nothing uses -- which no warning reports, since
# -Wunused does not look in headers. Each is a variable outside every
# function, and an object without it says "none here". -femit-all-decls makes
# clang keep them; gcc keeps them already, and refuses the flag. So the flag
# is used when the compiler takes it, and either way a probe -- a folded
# static const and an unused static, both from a header -- must come out of
# the compile as two variables in the object, or nothing was checked: exit 2.
if [ "$MODE" = globals ]; then
	mkdir "$TMP/probe"
	printf 'static const int\tprobe_folded = 3;\nstatic int\tprobe_unused;\n' > "$TMP/probe/probe.h"
	printf '#include "probe.h"\n\nint\tprobe_get(int n)\n{\n\treturn (n / probe_folded);\n}\n' \
		> "$TMP/probe/probe.c"
	# probe_keeps [FLAG] -- whether the compile, with FLAG, keeps both: 0 it
	# does, 1 the object lacks one, 2 the probe did not compile, 3 nm could
	# not read the object. Three faults, each told apart from the others: a
	# compiler that cannot compile a file of the harness's own is not one
	# that leaves a variable out.
	probe_keeps() {
		rl_split_on
		# shellcheck disable=SC2086
		"$CC" -c -fno-stack-protector -fno-builtin -Wall $XFLAGS "$@" "$TMP/probe/probe.c" \
			-o "$TMP/probe/probe.o" > "$TMP/probe/cc.err" 2>&1 || { rl_split_off; return 2; }
		rl_split_off
		LD_LIBRARY_PATH="$NM_PATH" LC_ALL=C "$NM" "$TMP/probe/probe.o" 2> "$TMP/probe/nm.err" > "$TMP/probe/nm.out" || return 3
		awk '$2 ~ /^[BbDdRrCVvGgSs]$/ && ($3 == "probe_folded" || $3 == "probe_unused") { c++ }
			END { exit c != 2 }' "$TMP/probe/nm.out"
	}
	# gcc refuses -femit-all-decls, so a failure with the flag is no finding;
	# the compile without it decides.
	if probe_keeps -femit-all-decls; then
		rl_list_add XFLAGS -femit-all-decls
	else
		probe_keeps
		_pk=$?
		case $_pk in
			0) ;;
			2)
				echo "forbidden_symbols.sh: the compiler '$CC' could not compile the --globals" >&2
				echo "  probe, a file of the harness's own (a static const and an unused" >&2
				echo "  static, from a header), so it cannot be trusted with yours:" >&2
				echo "  nothing was checked. The compile, without -femit-all-decls, said:" >&2
				rl_excerpt "$TMP/probe/cc.err" 10 globals-probe.txt >&2
				exit 2
				;;
			3)
				echo "forbidden_symbols.sh: nm ('$NM') could not read the object the --globals" >&2
				echo "  probe compiled to, so nothing was checked. It said:" >&2
				rl_excerpt "$TMP/probe/nm.err" 10 globals-probe-nm.txt >&2
				exit 2
				;;
			*)
				echo "forbidden_symbols.sh: the compiler '$CC' leaves out of its object a static" >&2
				echo "  variable it has no use for (a folded static const, an unused static from" >&2
				echo "  a header), with and without -femit-all-decls. This check reads the" >&2
				echo "  object, so it would report such a variable as absent: nothing was checked." >&2
				exit 2
				;;
		esac
	fi
fi

# The lists are one word per line (runner_lib.sh, LISTS OF WORDS); the loop
# below splits nothing else.
n=0
rl_split_on
for src in $SRCS; do
	n=$((n + 1))
	dir=$(dirname "$src")
	# Numbered, not named after the source: two files of one name in two
	# folders would otherwise share an object.
	obj="$TMP/$n.o"
	# shellcheck disable=SC2086
	if ! "$CC" -c -fno-stack-protector -fno-builtin -Wall $XFLAGS "$src" -I "$dir" $INCS -o "$obj" 2> "$TMP/cc.err"; then
		echo "forbidden_symbols.sh: failed to compile $src" >&2
		rl_excerpt "$TMP/cc.err" 25 compiler-output.txt "  " >&2
		exit 2
	fi
	nm_read nm
	awk 'NF == 3 { print $3 }' "$TMP/nm.out" >> "$DEF"
	awk '$1 == "U" { print $2 }' "$TMP/nm.out" >> "$UND"

	# --globals: each data object this object defines, with the file:line
	# `nm -l` reads from the debug information -- code, name, place. A name
	# with a '.' is one the compiler made for a static INSIDE a function
	# (header), never one written at file scope.
	if [ "$MODE" = globals ]; then
		nm_read "nm -l" -l
		awk -F'\t' -v n="$n" '{
			k = split($1, w, " ")
			if (k != 3 || w[2] !~ /^[BbDdRrCVvGgSs]$/ || w[3] ~ /[.]/) next
			print n "\t" w[2] "\t" w[3] "\t" $2
		}' "$TMP/nm.out" >> "$TMP/globals"
	fi

	# --function: the symbol table (source, name, section, binding, type),
	# every relocation (source, the section it is in, what it names, its
	# offset), and the source line each relocation in code comes from --
	# objdump's -t, -r and -d -l -r, read as binutils 2.38 prints them:
	# `VALUE FLAGS SECTION<TAB>SIZE NAME`, the seven flag columns at fixed
	# places; `OFFSET TYPE VALUE` under `RELOCATION RECORDS FOR [SECTION]:`;
	# and, in a disassembly, a `FILE:LINE` line wherever the line changes and
	# a `<TAB>OFFSET: TYPE<TAB>VALUE` line under each instruction that holds
	# a relocation. Offsets lose their leading zeros, so the two spellings
	# meet; a FILE loses this directory and a leading ./, as place() does.
	# Run under LC_ALL=C, as nm is, because binutils translates its headings
	# ("Disassembly of section") where a translation is installed, and a
	# heading this reads by its English words would then never be seen.
	if [ "$MODE" = function ]; then
		if ! LD_LIBRARY_PATH="$OBJDUMP_PATH" LC_ALL=C "$OBJDUMP" -t "$obj" > "$TMP/od.t" 2> "$TMP/od.err" ||
			! LD_LIBRARY_PATH="$OBJDUMP_PATH" LC_ALL=C "$OBJDUMP" -r "$obj" > "$TMP/od.r" 2>> "$TMP/od.err" ||
			! LD_LIBRARY_PATH="$OBJDUMP_PATH" LC_ALL=C "$OBJDUMP" -d -l -r "$obj" > "$TMP/od.d" 2>> "$TMP/od.err"; then
			echo "forbidden_symbols: cannot read $src's object (objdump failed)" >&2
			rl_excerpt "$TMP/od.err" 5 objdump-output.txt "" >&2
			exit 2
		fi
		awk -v n="$n" '
			/^[0-9a-f]+ / && index($0, "\t") {
				fl = substr($0, index($0, " ") + 1, 7)
				rest = substr($0, index($0, " ") + 9)
				t = index(rest, "\t")
				sec = substr(rest, 1, t - 1)
				k = split(substr(rest, t + 1), w, " ")
				print n "\t" w[k] "\t" sec "\t" substr(fl, 1, 1) substr(fl, 2, 1) "\t" substr(fl, 7, 1)
			}' "$TMP/od.t" >> "$TMP/fsyms"
		awk -v n="$n" '
			/^RELOCATION RECORDS FOR \[/ {
				sec = $0
				sub(/^RELOCATION RECORDS FOR \[/, "", sec)
				sub(/\]:$/, "", sec)
				next
			}
			sec != "" && /^[0-9a-f]+ / && NF >= 3 {
				v = $3
				sub(/[-+]0x[0-9a-f]+$/, "", v)
				o = $1
				sub(/^0+/, "", o)
				print n "\t" sec "\t" v "\t" (o == "" ? "0" : o)
			}' "$TMP/od.r" >> "$TMP/frels"
		awk -v n="$n" -v pwd="$PWD/" -v phys="$HERE_P/" "$FS_AWK_REL"'
			/^Disassembly of section / {
				sec = $4
				sub(/:$/, "", sec)
				loc = "-"
				next
			}
			/^[^ \t].*:[0-9]+( \(discriminator [0-9]+\))?$/ {
				loc = $0
				sub(/ \(discriminator [0-9]+\)$/, "", loc)
				loc = rel(loc)
				next
			}
			sec != "" && /^\t+[0-9a-f]+: R_/ {
				o = $1
				sub(/:$/, "", o)
				sub(/^0+/, "", o)
				print n "\t" sec "\t" (o == "" ? "0" : o) "\t" loc
			}' "$TMP/od.d" >> "$TMP/flocs"
		# And where each data object is defined (source, name, FILE:LINE),
		# from `nm -l` as --globals reads it: a name reached through data
		# has no line of code, and is reported at that definition (header).
		nm_read "nm -l" -l
		awk -F'\t' -v n="$n" -v pwd="$PWD/" -v phys="$HERE_P/" "$FS_AWK_REL"'{
			k = split($1, w, " ")
			if (k != 3 || w[2] !~ /^[BbDdRrCVvGgSs]$/ || $2 == "") next
			print n "\t" w[3] "\t" rel($2)
		}' "$TMP/nm.out" >> "$TMP/fdlocs"
	fi

	# THE CODE THE COMPILER SAW: the same source, preprocessed with the same
	# flags, keeping only the lines that came from a file of the exercise's
	# own -- the student's sources and headers, and any header the grader
	# provides. A line marker `# N "file" FLAGS` opens each stretch of the
	# output, and flag 3 marks a system header's, which are dropped: <ctype.h>
	# names every classifier and <string.h> declares memcpy, and neither is a
	# use by anyone. The files the markers name are kept too, as the headers a
	# place may be reported from (THE FILES A PLACE IS REPORTED FROM, below).
	# shellcheck disable=SC2086
	if ! "$CC" -E -fno-builtin "$src" -I "$dir" $INCS > "$TMP/pp" 2> "$TMP/cc.err"; then
		echo "forbidden_symbols.sh: failed to preprocess $src" >&2
		rl_excerpt "$TMP/cc.err" 25 preprocessor-output.txt "  " >&2
		exit 2
	fi
	awk -v hdrs="$TMP/hdrs" '
		/^# [0-9]+ "/ {
			sys = 0
			for (k = 4; k <= NF; k++) if ($k == "3") sys = 1
			f = $3; gsub(/"/, "", f)
			if (!sys && f ~ /\.h$/) print f >> hdrs
			next
		}
		/^#/ { next }
		!sys' "$TMP/pp" > "$TMP/pp.$n"
	cat "$TMP/pp.$n" >> "$TMP/code.raw"
	# --function: which <ctype.h> class constant each line of the code the
	# compiler saw holds (source, FILE:LINE, the classifier it stands for),
	# literals left out. glibc expands isalpha(c) into a mask with _ISalpha
	# on the line the call is written on, so the line a __ctype_b_loc
	# relocation comes from says which classifier that call is (THE <ctype.h>
	# CLASSIFIERS, below).
	if [ "$MODE" = function ]; then
		awk -v n="$n" -v pwd="$PWD/" -v phys="$HERE_P/" "$FS_AWK_REL"'
			/^# [0-9]+ "/ {
				ln = $2 - 1
				f = $3
				gsub(/"/, "", f)
				f = rel(f)
				next
			}
			{
				ln++
				l = $0
				gsub(/"([^"\\]|\\.)*"/, "", l)
				gsub(/\047([^\047\\]|\\.)*\047/, "", l)
				while (match(l, /_IS[a-z]+/)) {
					print n "\t" f ":" ln "\tis" substr(l, RSTART + 3, RLENGTH - 3)
					l = substr(l, RSTART + RLENGTH)
				}
			}' "$TMP/pp" >> "$TMP/isat"
	fi
done
rl_split_off

ALLOWED_LIST=$(echo "$ALLOWED" | tr ',' ' ')

# blank FILE -- FILE with its comments, string and character literals turned
# into spaces, line for line.
#
# Every question below that reads the source -- "does it call memcpy itself?",
# "which classifier did it use?", "on which line?" -- is about code, and a
# grep over the raw text also answers it for prose: `/* like isspace(3) */`
# and `"isspace("` each name one. Blanking with spaces keeps every line number
# where it was, so a place reported from a blanked copy is a place in the
# student's file.
blank() {
	awk '
		{
			out = ""; n = length($0); j = 1
			while (j <= n) {
				c = substr($0, j, 1); d = substr($0, j, 2)
				if (blk) {
					if (d == "*/") { blk = 0; out = out "  "; j += 2 }
					else { out = out " "; j++ }
					continue
				}
				if (q != "") {
					if (c == "\\") { out = out "  "; j += 2; continue }
					if (c == q) q = ""
					out = out (q == "" ? c : " "); j++
					continue
				}
				if (d == "/*") { blk = 1; out = out "  "; j += 2; continue }
				if (d == "//") break
				if (c == "\"" || c == "\047") q = c
				out = out c; j++
			}
			q = ""
			print out
		}' "$1"
}

# uses NAME -- whether the code the compiler saw names NAME, as a word.
#
# This, and not a scan of the files as written, is what the verdicts below
# ask, because a macro is only a use where it is expanded. `#define CP
# memcpy` followed by `CP(d, s, n)` is a memcpy the student wrote, and it
# shows here as `memcpy(d, s, n)`; the same #define left unused shows as
# nothing, and costs nothing. A macro in the student's own header is read
# the same way as one in the .c file. The preprocessor has already dropped
# the comments; blank() drops the literals.
blank "$TMP/code.raw" > "$TMP/code"
uses() {
	grep -qE "(^|[^A-Za-z0-9_])$1([^A-Za-z0-9_]|\$)" "$TMP/code"
}

# THE FILES A PLACE IS REPORTED FROM: every source, then every header of the
# exercise's own the preprocessor opened, each blanked. The verdict is decided
# above; this only answers "where?", so a student told they used isalpha is
# pointed at the line that says so, even when that line is a #define in their
# header. Sources first, so a place in the .c file is the first one reported.
# One word per line, as every list here is.
SCAN=$SRCS
while IFS= read -r _h; do
	[ -n "$_h" ] && rl_list_add SCAN "$_h"
done <<HDRS_EOF
$(sort -u "$TMP/hdrs")
HDRS_EOF
i=0
rl_split_on
for f in $SCAN; do
	i=$((i + 1))
	blank "$f" > "$TMP/strip.$i"
done
rl_split_off

# where NAME -- up to three file:line places the scanned files name NAME as a
# word, joined by ", ", or nothing. A word, not a call shape, so a #define
# that aliases a function is found as well as the call. The one line that
# names a function without using it is an #include: <errno.h> names errno,
# <signal.h> names signal.
where() {
	_i=0
	rl_split_on
	for _s in $SCAN; do
		_i=$((_i + 1))
		grep -nE "(^|[^A-Za-z0-9_])$1([^A-Za-z0-9_]|\$)" "$TMP/strip.$_i" |
			grep -vE '^[0-9]+:[[:space:]]*#[[:space:]]*include' |
			sed "s|^\\([0-9]*\\):.*|$_s:\\1|"
	# conventions: not-an-excerpt -- at most three places, by design (above).
	done | head -n 3 | tr '\n' ' ' | sed 's/ $//; s/ /, /g'
	rl_split_off
}

in_list() {
	_n="$1"
	shift
	for _x in "$@"; do
		[ "$_n" = "$_x" ] && return 0
	done
	return 1
}

# THE ALIAS TABLE: the name a student writes, for each name glibc's headers
# compile it into. nm reports the second; the subject, and the student, only
# ever see the first. Without this the layer rejected what C 10 allows in so
# many words -- "You may use the variable errno" -- because <errno.h> reads
# that variable through a call to __errno_location(), and it told a student
# who wrote isspace that they had called __ctype_b_loc, a name that appears
# nowhere in their file.
#
# Each row is a fact about glibc, the campus libc, checked with nm on objects
# the pinned clang built: errno, <libgen.h>'s basename, the scanf family and
# the <ctype.h> classifiers at -O0, which is this layer's compile;
# toupper/tolower only at -O1 and up, and the FORTIFY *_chk names only under
# -D_FORTIFY_SOURCE with optimisation on. This compile turns on neither, so
# those last rows cost nothing today and keep a flag change honest.
#
# __ctype_b_loc is the one row that is not one-to-one: isalpha, isdigit,
# isspace and the rest all compile into that same call, so nm cannot say which
# was written. The verdict asks the preprocessed source instead
# (judge, below).
CTYPE_CLASSIFIERS="isalnum isalpha isblank iscntrl isdigit isgraph islower isprint ispunct isspace isupper isxdigit"
public_of() {
	case "$1" in
		__errno_location) echo errno ;;
		__xpg_basename) echo basename ;;
		__ctype_b_loc) echo "$CTYPE_CLASSIFIERS" ;;
		__ctype_toupper_loc) echo toupper ;;
		__ctype_tolower_loc) echo tolower ;;
		__isoc99_*) echo "${1#__isoc99_}" ;;
		__isoc23_*) echo "${1#__isoc23_}" ;;
		__*_chk) _p="${1#__}"; echo "${_p%_chk}" ;;
	esac
}
# why_alias SYM -- one line saying what turned the student's name into SYM.
why_alias() {
	case "$1" in
		__errno_location) echo "<errno.h> reads the variable errno through this call" ;;
		__xpg_basename) echo "<libgen.h> renames basename to this" ;;
		__ctype_b_loc) echo "<ctype.h> expands its is* classifiers into this call" ;;
		__ctype_to*_loc) echo "<ctype.h> expands toupper/tolower into this call" ;;
		__isoc99_*|__isoc23_*) echo "a libc header renames the call to this version" ;;
		__*_chk) echo "_FORTIFY_SOURCE swaps the call for this checked version" ;;
	esac
}

# A SUPPLIED FUNCTION THE STUDENT WROTE ANYWAY. "If ft_putchar() is an
# authorized function, we will compile your code with our ft_putchar.c": the
# grader's copy and the student's then meet in one program, and two definitions
# of one function do not link -- a compile error at the Moulinette however right
# the output is. Nothing else here can say so. The output layer links whichever
# copy the linker reaches first and goes green, and the verdict below would only
# report the `write` inside the student's copy, which names a symptom and sends
# them looking for another way to print. Any definition counts, static
# included: a static copy dodges the clash but is still a body this exercise
# never asked for, and it still needs a call nothing authorises.
PROVIDED_DEF=""
rl_split_on
for p in $PROVIDED; do
	if grep -qxF "$p" "$DEF"; then
		PROVIDED_DEF="$PROVIDED_DEF $p"
	fi
done
rl_split_off
if [ -n "$PROVIDED_DEF" ]; then
	echo "forbidden_symbols: FAIL — your code DEFINES a function the grader supplies."
	echo ""
	echo "  DEFINED HERE, SUPPLIED BY THE GRADER:"
	for p in $PROVIDED_DEF; do
		printf '    %s\n' "$p"
	done
	echo ""
	echo "  The grader compiles its own copy of these together with your file, so"
	echo "  yours would be a second definition of the same function: the program"
	echo "  does not link, and the exercise fails before a single test runs."
	echo "  Declare the function -- one prototype line, as the stub starts with --"
	echo "  and call it. Never write its body, and never turn in a file for it."
	exit 1
fi

# THE BASELINE EXEMPTION IS CONDITIONAL ON THE SOURCE, and it has to be.
#
# memcpy/memmove/memset/mempcpy/bcopy/bzero are tolerated because CODE
# GENERATION emits them: an aggregate initialiser or a struct assignment
# becomes a call the source never wrote. That is real and the exemption is
# load-bearing -- compiling all 140 deliverable .c files with this layer's own
# flags produced exactly ONE object referencing any of them: a rush source with
# `U memcpy`, emitted for the initialiser of a large local array, and with no
# such call anywhere in the file.
#
# Applied unconditionally, though, it also forgave the call you DID write. A
# file whose body is literally `memcpy(dest, src, n); bzero(dest + n, 0);`
# passed this layer with "Authorised: none — no external function at all",
# which is the exact opposite of what it exists to say. So the question is now
# the one the Moulinette asks and the header above already describes: does the
# SOURCE call it? A symbol the source calls belongs to the exercise, whatever
# else the compiler may separately have emitted it for.
#
# Asked of the code the compiler saw, through uses(). A deliverable that
# merely names memcpy in a comment has not called it, and failing it for prose
# would be the false-red class this repo ranks alongside false greens. The raw
# file used to be read here, so `/* like memcpy(3) */` beside an emitted
# memcpy cost the exemption. And a call-shaped match on the file as written
# forgave `#define CP memcpy` followed by `CP(d, s, n)`, which is a memcpy
# the student wrote. Written without \< or \b, which are GNU extensions this
# file cannot assume.
#
# __stack_chk_fail cannot arise at all -- the compile above passes
# -fno-stack-protector -- and _GLOBAL_OFFSET_TABLE_ is not a function anyone
# writes; both simply never match, at no cost.
#
# `__builtin_memset(p, 0, n)` is the same call spelled the compiler's way:
# where it is not inlined it is `U memset` in the object, exactly as if the
# source said memset. A word match on memset cannot see it, so it was forgiven
# as code generation in both modes. It counts as a use here, and BUILTIN keeps
# which names were written only that way, so the red can point at the line.
EXEMPT=""
BUILTIN=""
for b in $BASELINE; do
	uses "$b" && continue
	if uses "__builtin_$b"; then
		BUILTIN="$BUILTIN $b"
		continue
	fi
	EXEMPT="$EXEMPT $b"
done
# builtin_note NAME INDENT -- the line saying NAME was written as its
# __builtin_ spelling, when it was; nothing otherwise.
builtin_note() {
	# shellcheck disable=SC2086 # $BUILTIN: a list of C names, one per word
	in_list "$1" $BUILTIN || return 0
	printf '%swritten as __builtin_%s, which the compiler turns into this call\n' "$2" "$1"
}

# THE <ctype.h> CLASSIFIERS, judged from the preprocessed source because nm
# cannot.
#
# All twelve compile into one call to __ctype_b_loc, so the object says "some
# classifier" and never which. The code the compiler saw does: glibc expands
# each classifier into that call masked with its own class constant --
# isalpha(c) into `(*__ctype_b_loc())[c] & _ISalpha` -- so `_IS` plus the
# name without its `is` says which one ran, macro aliases included. Each
# classifier used that the subject does not authorise is reported by name,
# and __ctype_b_loc passes only when one that IS authorised was used: never
# merely because the subject authorises some classifier, which let
# `#define MYALPHA isalpha` through on an exercise allowed isdigit. When no
# class constant shows at all (__ctype_b_loc reached by hand), the report
# names the family rather than the symbol: refused, since nothing authorised
# was seen to be used.
#
# judge SYM LIST USED -- the verdict on one symbol an object references, in
# LIST's terms (a list of C names, one per word), for both modes: the whole
# turn-in's list, and --function's per function. Each mode writes its own
# row from what this sets, and says which classifiers count as used: USED
# is ctype_used's HOW, below. The two modes kept a copy each, and a rule
# found in one (the MYALPHA alias, a classifier the turn-in defines) had to
# be made twice. Sets:
#   JV_KIND   skip (on LIST, or EXEMPT), bad, accept, or ctype
#   JV_PUB    the name the student wrote (public_of), or "" for one the
#             alias table does not know (bad, under its own name)
#   JV_SEEN   ctype: the classifiers used that LIST allows, ", " apart
#   JV_NAMED  ctype: those used that it does not, one a line, in order
# A classifier the turn-in defines is its own function, never glibc's.
# Its own names start with _jv_: POSIX sh has no `local`, and the callers'
# loops hold f, sym, list, pub, j, loc and _c.
# shellcheck disable=SC2086 # LIST and EXEMPT: lists of C names, one per word
judge() {
	JV_KIND="" JV_PUB="" JV_SEEN="" JV_NAMED=""
	if in_list "$1" $2 $EXEMPT; then
		JV_KIND=skip
		return 0
	fi
	JV_PUB=$(public_of "$1")
	if [ -z "$JV_PUB" ]; then
		JV_KIND=bad
	elif [ "$1" = __ctype_b_loc ]; then
		JV_KIND=ctype
		for _jv_c in $CTYPE_CLASSIFIERS; do
			grep -qxF "$_jv_c" "$DEF" && continue
			ctype_used "$3" "$_jv_c" || continue
			if in_list "$_jv_c" $2; then
				JV_SEEN="${JV_SEEN:+$JV_SEEN, }$_jv_c"
			else
				JV_NAMED="$JV_NAMED$_jv_c$RL_NL"
			fi
		done
	elif in_list "$JV_PUB" $2 $EXEMPT; then
		JV_KIND=accept
	else
		JV_KIND=bad
	fi
	return 0
}
# ctype_used HOW CLASSIFIER -- whether CLASSIFIER counts as used: HOW is
# code, the default mode's, for its class constant anywhere in the code the
# compiler saw, the whole turn-in's; or line, --function's, for the
# classifiers on the reference's own line (_on, from isat), or where there
# is none, its class constant in its source's code ($TMP/code.$j).
ctype_used() {
	case "$1" in
		code) uses "_IS${2#is}" ;;
		line)
			if [ -n "$_on" ]; then
				printf '%s\n' "$_on" | grep -qxF "$2"
			else
				grep -qE "(^|[^A-Za-z0-9_])_IS${2#is}([^A-Za-z0-9_]|\$)" "$TMP/code.$j"
			fi ;;
	esac
}

TAB=$(printf '\t')

# place LOC NAME -- where a definition is: `nm -l`'s FILE:LINE with this
# directory taken off (Bazel runs a test from its runfiles, where a source's
# path is the one it was handed as), or, when the debug information gave
# none, the first place a scanned file names NAME. The directory as the
# compiler saw it too (HERE_P): it writes getcwd()'s, which a symlink in
# $PWD would make another spelling of the same place. A leading ./ goes
# too: a header found through `-I .` is named DIR/./toy.h.
place() {
	_pl=$1
	case "$_pl" in
		"$PWD"/*) _pl=${_pl#"$PWD"/} ;;
		"$HERE_P"/*) _pl=${_pl#"$HERE_P"/} ;;
	esac
	case "$_pl" in
		./*) printf '%s' "${_pl#./}" ;;
		?*) printf '%s' "$_pl" ;;
		*) where "$2" | sed 's/, .*//' ;;
	esac
}

# ---------------------------------------------------------------------------
# --globals: THE VERDICT. Every data object defined outside a function is
# named, at its definition, with what makes it one (header): visible to
# other files or static, and read-only where it is const.
if [ "$MODE" = globals ]; then
	if [ ! -s "$TMP/globals" ]; then
		echo "forbidden_symbols: OK — no file here defines a variable outside a function."
		exit 0
	fi
	echo "forbidden_symbols: FAIL — a variable is defined outside every function."
	echo ""
	echo "  DEFINED OUTSIDE EVERY FUNCTION:"
	while IFS="$TAB" read -r _gi code name loc; do
		case "$code" in
			[a-z]) kind="static" ;;
			*) kind="visible to the other files" ;;
		esac
		case "$code" in
			[Rr]) kind="$kind, read-only (const)" ;;
		esac
		at=$(place "$loc" "$name")
		printf '    %s   (at %s; %s)\n' "$name" "${at:-an unknown place}" "$kind"
	# Once each: a header's variable is in the object of every file that
	# includes it, at the same place.
	done < "$TMP/globals" | awk '!seen[$0]++'
	echo ""
	rl_quote globals | sed 's/^/    /'
	echo ""
	echo "  To this check a variable declared outside every function body is a"
	echo "  global variable whether it is static, const or neither -- each name"
	echo "  above is one -- and one declared inside a body is not. Breaking that"
	echo "  rule is a KO $(rl_at),"
	echo "  however right the output looks. What does each of these hold, and"
	echo "  which function needs it?"
	exit 1
fi

# ---------------------------------------------------------------------------
# --function: WHAT EACH FUNCTION REACHES (header). The sections of every
# object are the nodes, a relocation is an edge from the section it sits in
# to what it names, and each listed function is walked from its own section
# -- breadth first, so the chain shown is a shortest one, and each section
# once, so a cycle ends. A name the turn-in defines is a node (its section);
# a name it does not is where the walk stops, and is what the function uses.
# A listed function is its global (or weak) definition's section, a static
# one's only where none is global (header), and another listed function is
# where the first walk stops: the second, under --through alone, goes on
# from each such stop into everything the first did not reach, and what it
# finds is marked as found that way. A listed name nobody defines is not
# reported at all (header).
#
# Out: freach, one line per place a function's walk names an outside name --
# the function, the name, the chain that first reached it, the source whose
# object names it, the FILE:LINE of that reference (from data, the data
# object's own definition; "-" where there is none), and 1 where only the
# second walk reached it, 0 otherwise -- and fmissing, the listed names that
# have no section of their own to walk from.
if [ "$MODE" = function ]; then
	printf '%s\n' "$FUNCS" | awk '{
		i = index($0, "="); l = substr($0, i + 1)
		if (l == "-") l = ""
		gsub(/,/, " ", l)
		print substr($0, 1, i - 1) "\t" l
	}' > "$TMP/flist"
	: > "$TMP/freach"
	: > "$TMP/fmissing"
	awk -F'\t' -v through="$THROUGH" -v reach="$TMP/freach" -v missing="$TMP/fmissing" '
		function lab(node,    s) {
			if (node in label) return label[node]
			s = node; sub(/^[^|]*\|/, "", s); return s
		}
		function chain(node) {
			return (node in par) ? chain(par[node]) " -> " lab(node) : lab(node)
		}
		# walk(V): breadth first from the queue, for function f. The first
		# walk (V 0) stops at another listed function, keeping each stop
		# for the second (V 1), which follows everything.
		function walk(v,    cur, m, j, tl, e, t, s, o, pl) {
			while (qh < qt) {
				cur = q[++qh]
				m = split(substr(adj[cur], 2), tl, "\034")
				for (j = 1; j <= m; j++) {
					split(tl[j], e, "\035")
					t = e[1]
					if (t ~ /^X\|/) {
						s = substr(t, 3)
						if (s in listed) continue
						o = cur; sub(/\|.*/, "", o)
						pl = e[2]
						if (pl == "-" && ((o "|" lab(cur)) in dloc)) pl = dloc[o "|" lab(cur)]
						if ((s, pl) in told) continue
						told[s, pl] = 1
						print f "\t" s "\t" chain(cur) " -> " s "\t" o "\t" pl "\t" v > reach
						continue
					}
					if (t in seen) continue
					if (v == 0 && (t in lnode) && lnode[t] != f) {
						if (through == 1) { stop[++ns] = t; spar[ns] = cur }
						continue
					}
					seen[t] = 1; par[t] = cur; q[++qt] = t
				}
			}
		}
		# The symbol tables: where each name is defined, which section is
		# whose, and the globals another object may reach.
		FILENAME == ARGV[1] {
			if ($3 ~ /^\*/) next
			node = $1 "|" $3
			at[$1, $2] = $3
			if (($5 == "F" || $5 == "O") && !(node in label)) label[node] = $2
			glob = substr($4, 1, 1) == "g" || substr($4, 2, 1) == "w"
			if (glob && !($2 in gdef)) gdef[$2] = node
			if ($5 == "F" && $3 == ".text." $2) {
				if (glob) gfn[$2] = gfn[$2] "\034" node
				else sfn[$2] = sfn[$2] "\034" node
			}
			next
		}
		# The places, by source, section and offset; then each data
		# object at its definition, by source and name.
		FILENAME == ARGV[2] { loc[$1 "|" $2 "|" $3] = $4; next }
		FILENAME == ARGV[3] { dloc[$1 "|" $2] = $3; next }
		# The relocations, each resolved to a node or to an outside name,
		# with the place it was written.
		FILENAME == ARGV[4] {
			t = $3
			if (t == "" || t ~ /^\*/) next
			if (t ~ /^\./) to = $1 "|" t
			else if (($1, t) in at) to = $1 "|" at[$1, t]
			else if (t in gdef) to = gdef[t]
			else to = "X|" t
			w = $1 "|" $2 "|" $4
			adj[$1 "|" $2] = adj[$1 "|" $2] "\034" to "\035" ((w in loc) ? loc[w] : "-")
			next
		}
		{ listed[$1] = 1; order[++nl] = $1 }
		END {
			# The sections of each listed function, and whose each one is.
			for (i = 1; i <= nl; i++) {
				f = order[i]
				own[f] = (f in gfn) ? gfn[f] : sfn[f]
				k = split(substr(own[f], 2), st, "\034")
				for (j = 1; j <= k; j++) lnode[st[j]] = f
			}
			for (i = 1; i <= nl; i++) {
				f = order[i]
				if (own[f] == "") { print f > missing; continue }
				split("", seen); split("", par); split("", told)
				qh = 0; qt = 0; ns = 0
				k = split(substr(own[f], 2), st, "\034")
				for (j = 1; j <= k; j++) { seen[st[j]] = 1; q[++qt] = st[j] }
				walk(0)
				for (j = 1; j <= ns; j++) {
					if (stop[j] in seen) continue
					seen[stop[j]] = 1; par[stop[j]] = spar[j]; q[++qt] = stop[j]
				}
				walk(1)
			}
		}' "$TMP/fsyms" "$TMP/flocs" "$TMP/fdlocs" "$TMP/frels" "$TMP/flist" || {
		echo "forbidden_symbols: could not walk the objects' references (awk failed)" >&2
		exit 2
	}

	# A LISTED FUNCTION WITH NO SECTION OF ITS OWN was never walked. One no
	# file defines is the function's own tests' to report (header); one nm
	# sees defined is not missing at all -- its code sits in a section the
	# walk does not start from (a compile that ignored -ffunction-sections,
	# a section attribute, an alias of another function), or the name is a
	# variable's, so nothing was checked for it: exit 2, never the "not
	# checked" note of a green.
	_nosec=""
	while IFS= read -r _m; do
		grep -qxF "$_m" "$DEF" && _nosec="$_nosec $_m"
	done < "$TMP/fmissing"
	if [ -n "$_nosec" ]; then
		echo "forbidden_symbols.sh: nm lists these names as defined, but no section" >&2
		echo "  .text.NAME holds their code, which is where this check starts reading" >&2
		echo "  what a function uses, so nothing was checked for them:" >&2
		echo " $_nosec" >&2
		echo "  The compile is asked for -ffunction-sections. A compiler that ignores it," >&2
		echo "  a section attribute, or an alias of another function puts the code" >&2
		echo "  elsewhere; and a variable of that name has no code at all." >&2
		exit 2
	fi

	# THE VERDICT, one function at a time and in its own list's terms. What
	# is forgiven is exactly the default mode's (header): $EXEMPT, decided
	# from the code the compiler saw, and a glibc-internal name judged as
	# the public one it stands for.
	#
	# __ctype_b_loc says only "a classifier", so which one each reference is
	# comes from the code the compiler saw ON ITS LINE (isat): a classifier
	# not on the function's list is named, and one that is passes. Where the
	# line is unknown or holds no class constant, every classifier its
	# source uses must be on the list -- the default mode's rule read per
	# source -- which can name a neighbouring function's classifier (a red,
	# never a green). None named anywhere is none allowed, reported as the
	# family.
	: > "$TMP/fbad"
	FACCEPTED=""
	while IFS="$TAB" read -r f sym chain j loc via; do
		list=$(awk -F'\t' -v f="$f" '$1 == f { print $2 }' "$TMP/flist")
		_on=""
		if [ "$sym" = __ctype_b_loc ]; then
			[ "$loc" = - ] || _on=$(awk -F'\t' -v j="$j" -v l="$loc" \
				'$1 == j && $2 == l { print $3 }' "$TMP/isat")
			if [ -z "$_on" ]; then
				[ -f "$TMP/code.$j" ] || blank "$TMP/pp.$j" > "$TMP/code.$j"
			fi
		fi
		judge "$sym" "$list" line
		case "$JV_KIND" in
			skip) ;;
			accept) FACCEPTED="$FACCEPTED$f$TAB$sym$TAB$JV_PUB$RL_NL" ;;
			bad)
				# "-": no other symbol. An empty field would vanish, since a
				# TAB in IFS is white space and runs of it are one separator.
				if [ -z "$JV_PUB" ]; then
					printf '%s\t%s\t-\t%s\t%s\t%s\n' "$f" "$sym" "$chain" "$loc" "$via" >> "$TMP/fbad"
				else
					printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$JV_PUB" "$sym" "$chain" "$loc" "$via" >> "$TMP/fbad"
				fi ;;
			ctype)
				if [ -n "$JV_NAMED" ]; then
					printf '%s' "$JV_NAMED" | while IFS= read -r _c; do
						printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$_c" "$sym" "$chain" "$loc" "$via"
					done >> "$TMP/fbad"
				elif [ -n "$JV_SEEN" ]; then
					FACCEPTED="$FACCEPTED$f$TAB$sym$TAB$JV_SEEN$RL_NL"
				else
					printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "a <ctype.h> classifier" "$sym" "$chain" "$loc" "$via" >> "$TMP/fbad"
				fi ;;
		esac
	done < "$TMP/freach"

	# The reading --through applies, said wherever its verdict is.
	through_note() {
		[ "$THROUGH" = 1 ] || return 0
		echo "  This target also counts, against a function's own list, what the"
		echo "  other listed functions it calls use: this harness's reading, never"
		echo "  the subject's."
	}

	if [ -s "$TMP/fbad" ]; then
		# One entry per function and name, in the lists' order: the first
		# chain that reached it, up to three places it was written, and
		# whether it was reached ONLY through another listed function (the
		# second walk). Where the function's own code reaches it too, the
		# entry is that code's: its chain and its places.
		awk -F'\t' '
			FILENAME == ARGV[1] { order[++nf] = $1; next }
			{
				k = $1 SUBSEP $2
				if (!(k in had)) { had[k] = 1; seq[$1] = seq[$1] SUBSEP $2 }
				kd = k SUBSEP ($6 == "1" ? "v" : "d")
				if (!(kd in sym)) { sym[kd] = $3; ch[kd] = $4 }
				if ($5 != "-" && cnt[kd] < 3 && index(", " pl[kd] ", ", ", " $5 ", ") == 0) {
					pl[kd] = (pl[kd] == "" ? $5 : pl[kd] ", " $5); cnt[kd]++
				}
			}
			END {
				for (i = 1; i <= nf; i++) {
					f = order[i]
					m = split(substr(seq[f], 2), nm, SUBSEP)
					for (j = 1; j <= m; j++) {
						k = f SUBSEP nm[j]
						v = ((k SUBSEP "d") in sym) ? 0 : 1
						kd = k SUBSEP (v ? "v" : "d")
						print f "\t" nm[j] "\t" sym[kd] "\t" ch[kd] "\t" (pl[kd] == "" ? "-" : pl[kd]) "\t" v
					}
				}
			}' "$TMP/flist" "$TMP/fbad" > "$TMP/fbad.grouped"
		echo "forbidden_symbols: FAIL — a function uses something its own list"
		echo "                   does not allow."
		while IFS="$TAB" read -r f _l; do
			grep -q "^$f$TAB" "$TMP/fbad.grouped" || continue
			echo ""
			printf '  %s   may use: %s\n' "$f" "${_l:-none — no external function at all}"
			while IFS="$TAB" read -r _f name sym chain at via; do
				[ "$_f" = "$f" ] || continue
				# "-": no place to give -- a reference from a static inside
				# a function, whose definition nm -l does not place. Never
				# where(), which would name the first line ANY code names
				# it on, another function's as readily as this one's.
				[ "$at" != - ] || at=""
				printf '    %s%s\n' "$name" "${at:+   (at $at)}"
				builtin_note "$name" "      "
				case "$chain" in
					"$f -> "*" -> "*) printf '      reached through %s\n' "$chain" ;;
				esac
				[ "$via" = 0 ] || printf '      only through another listed function: counted here by this harness'"'"'s reading\n'
				if [ "$sym" != - ]; then
					printf '      seen in the object as %s --\n' "$sym"
					printf '      %s\n' "$(why_alias "$sym")"
				fi
			done < "$TMP/fbad.grouped"
			rl_quote "functions:$f" | sed 's/^/      /'
		done < "$TMP/flist"
		echo ""
		# The KO is said of what a function's own code uses, and only then:
		# a name reached only through another listed function is a red of
		# this target's reading, which no grader was ever asked to apply.
		if awk -F'\t' '$6 == 0 { found = 1 } END { exit !found }' "$TMP/fbad.grouped"; then
			echo "  Each function is held to its own list, not to what the whole"
			echo "  turn-in may use together: a name one function may use can still be"
			echo "  one another may not. A name its own code uses outside that list is"
			echo "  an outright KO $(rl_at),"
			echo "  however right the output looks."
		fi
		if awk -F'\t' '$6 == 1 { found = 1 } END { exit !found }' "$TMP/fbad.grouped"; then
			echo "  A name marked \"only through another listed function\" is not in the"
			echo "  code of the function it is counted against: this target counts it"
			echo "  there as this harness's reading, never the subject's. Whether the"
			echo "  other function's own code breaks ITS list is the"
			echo "  _forbidden_functions target's to say."
		else
			through_note
		fi
		echo "  Which part of each function above needs each name, and what does"
		echo "  its own list leave it to do that with?"
		exit 1
	fi

	echo "forbidden_symbols: OK — each function uses only what its own list allows."
	printf '%s' "$FACCEPTED" | sort -u | while IFS="$TAB" read -r f sym pub; do
		[ -n "$f" ] && echo "                   ($f: the object names $sym, which is $pub)"
	done
	if [ -s "$TMP/fmissing" ]; then
		echo "                   Not defined by any file here, so not checked:"
		echo "                   $(tr '\n' ' ' < "$TMP/fmissing")"
		echo "                   (whether each is missing is its own tests' to say)"
	fi
	through_note
	exit 0
fi

# Collected rather than printed as they are found, so the verdict can show the
# offending set and the authorised set side by side below. One line per name:
# the name as the student wrote it, a tab, and the symbol nm saw when that is
# a different one.
: > "$TMP/bad"
ACCEPTED=""
CTYPE_SEEN=""
for sym in $(sort -u "$UND"); do
	if grep -qxF "$sym" "$DEF"; then
		continue
	fi
	judge "$sym" "$ALLOWED_LIST" code
	case "$JV_KIND" in
		skip) ;;
		# conventions: not-a-list -- symbol names nm printed, which hold no blank
		accept) ACCEPTED="$ACCEPTED $sym" ;;
		bad)
			if [ -z "$JV_PUB" ]; then
				printf '%s\t\n' "$sym" >> "$TMP/bad"
			else
				printf '%s\t%s\n' "$JV_PUB" "$sym" >> "$TMP/bad"
			fi ;;
		ctype)
			printf '%s' "$JV_NAMED" | while IFS= read -r _c; do
				printf '%s\t%s\n' "$_c" "$sym"
			done >> "$TMP/bad"
			CTYPE_SEEN=$JV_SEEN
			if [ -n "$CTYPE_SEEN" ]; then
				# conventions: not-a-list -- symbol names nm printed, which hold no blank
				ACCEPTED="$ACCEPTED $sym"
			elif [ -z "$JV_NAMED" ]; then
				printf '%s\t%s\n' "a <ctype.h> classifier" "$sym" >> "$TMP/bad"
			fi ;;
	esac
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

if [ -s "$TMP/bad" ]; then
	echo "forbidden_symbols: FAIL — this $(rl_noun) calls a function it is not"
	echo "                   authorised to call."
	echo ""
	echo "  CALLED BUT NOT AUTHORISED:"
	while IFS="$TAB" read -r name sym; do
		case "$name" in
			*" "*) at="" ;;
			*) at=$(where "$name") ;;
		esac
		# A name written only as its __builtin_ spelling has no place of its
		# own: the place is that spelling's.
		case "$at$name" in
			*" "*) ;;
			"$name") at=$(where "__builtin_$name") ;;
		esac
		printf '    %s%s\n' "$name" "${at:+   (at $at)}"
		builtin_note "$name" "      "
		# The symbol nm actually saw, when it is not the name above: without
		# it, a student searching their file for __ctype_b_loc finds nothing.
		if [ -n "$sym" ]; then
			printf '      seen by nm as %s --\n' "$sym"
			printf '      %s\n' "$(why_alias "$sym")"
		fi
	done < "$TMP/bad"
	echo ""
	echo "  AUTHORISED FOR THIS $(rl_noun | tr '[:lower:]' '[:upper:]'): $SHOWN"
	echo ""
	echo "  That list is not the harness's opinion: it is the \"Allowed functions\""
	echo "  line of this $(rl_noun)'s subject, copied as written, plus any variable"
	# conventions: the call site's --allowed -- the functions and variables the contract lists
	echo "  the subject allows by name. Calling anything outside it is an outright"
	echo "  KO $(rl_at) — a zero on the exercise no matter how right the output"
	echo "  looks — not a style remark you can defend later. Re-read that line in"
	echo "  the subject and build what you need out of what it does give you."
	# A __ name the table above does not know. It is still reported -- an
	# unknown symbol is never forgiven -- but it is almost never a name the
	# student typed, and saying where such names come from is the difference
	# between a search of their own file and a search of the harness.
	if awk -F"$TAB" '$1 ~ /^__/ && $2 == "" { found = 1 } END { exit !found }' "$TMP/bad"; then
		echo ""
		echo "  A name that starts with __ is rarely one you wrote: a C library"
		echo "  header can turn a call, a macro or a variable into an internal name"
		echo "  like that. Look in your file for what you used from a header."
	fi
	exit 1
fi

echo "forbidden_symbols: OK — every function called is either defined by this"
echo "                   $(rl_entry) itself or on the subject's authorised list."
echo "                   Authorised: $SHOWN"
# Said on the green path too, so a pass that relied on the alias table shows
# what it read: "nothing forbidden" and "__errno_location read as errno" are
# different claims, and only one of them is visible in the student's file.
for sym in $ACCEPTED; do
	case "$sym" in
		__ctype_b_loc) pub="$CTYPE_SEEN" ;;
		*) pub=$(public_of "$sym") ;;
	esac
	echo "                   (nm saw $sym, which is $pub)"
done
exit 0
