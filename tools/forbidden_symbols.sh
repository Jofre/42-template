#!/bin/sh
# Check that an exercise only calls its authorized functions.
#
# Compiles each deliverable source on its own and inspects the object's undefined
# symbols (the functions it actually calls). Any symbol that is neither defined
# by the exercise itself, nor in the authorized list, nor a compiler/runtime
# builtin, is reported as forbidden -- mirroring the Moulinette's allowlist.
#
# Usage:
#   forbidden_symbols.sh --allowed CSV [--hdr HEADER]... [--inc-file FILE]
#                        --src SRC [--src SRC]...
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
#
# Note: compiler-inserted aggregate-copy builtins (memcpy/memmove/memset/...)
# are tolerated since they are emitted by code generation, not written by you --
# but only while your source does not call them itself. See the exemption block
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
require awk basename cat dirname grep head mktemp rm sed sort tr

# The shared runner helpers -- exiting signal traps and excerpts that say what
# they left out -- written once in tools/runner_lib.sh.
RL_NAME=forbidden_symbols
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "forbidden_symbols.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool CC -- the pinned compiler: it builds, and runs none of what it builds
# conventions: harness tool NM -- the pinned nm: it reads symbols, and runs nothing

# The compiler is reached through $CC and probed below, like header_check.sh's,
# so it is not in that list: require exits 2 unconditionally, and a box with no
# compiler should make this layer say it checked nothing, not refuse to start.

ALLOWED=""
INCS=""
SRCS=""
PROVIDED=""

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
need() { [ "$2" -ge 2 ] || { echo "forbidden_symbols.sh: $1 needs a value" >&2; exit 2; }; }

# The compiler whose UNDEFINED-symbol list becomes this layer's verdict. Named
# and overridable like header_check.sh's HEADER_CC, because this is the one
# place a compiler choice genuinely moves the answer: printf("...\n") folded to
# puts, scanf resolved as __isoc99_scanf, a struct copy emitted as memcpy. All
# three are "calls a function the subject did not authorise" to this layer, and
# which of them happen is the compiler's decision.
#
# FORBIDDEN_CC is the hand-run default only: every test is handed the pinned
# clang-12 (--cc), campus's cc, which tools/defs.bzl requires of it
# (_PINNED_CC_RUNNERS, pinned_cc_problem) -- so the folds above are the ones
# campus's compiler makes.
CC="${FORBIDDEN_CC:-cc}"
CC_LIBS=""

while [ $# -gt 0 ]; do
	case "$1" in
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
		--nm) need "$1" "$#"; NM="$2"; shift 2 ;;
		--nm-lib) need "$1" "$#"; NM_LIBS="${NM_LIBS:+$NM_LIBS:}$(dirname "$2")"; shift 2 ;;
		--allowed) need "$1" "$#"; ALLOWED="$2"; shift 2 ;;
		# A function the GRADER compiles in with the student's file (Piscine
		# Reloaded's ft_putchar.c). Repeatable. Calling it is authorised;
		# defining it is the mistake -- see the verdict below.
		--provided) need "$1" "$#"; rl_list_add PROVIDED "$2"; shift 2 ;;
		--hdr) need "$1" "$#"; rl_list_add INCS -I "$(dirname "$2")"; shift 2 ;;
		--inc-file)
			need "$1" "$#"
			[ -f "$2" ] || { echo "forbidden_symbols.sh: no include list at $2" >&2; exit 2; }
			while IFS= read -r _i; do
				[ -z "$_i" ] || rl_list_add INCS -I "$_i"
			done < "$2"
			shift 2 ;;
		--src) need "$1" "$#"; rl_list_add SRCS "$2"; shift 2 ;;
		*) echo "forbidden_symbols.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$NM" ] || { echo "forbidden_symbols.sh: --nm is required (no PATH fallback by design)" >&2; exit 2; }
[ -x "$NM" ] || { echo "forbidden_symbols.sh: --nm '$NM' is not executable" >&2; exit 2; }

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
			echo "forbidden_symbols.sh: --nm-lib directory '$_d' does not exist." >&2
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
		echo "forbidden_symbols.sh: could not observe which libraries '$NM' loaded." >&2
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
				echo "forbidden_symbols.sh: the pinned nm loaded '$_l'." >&2
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

# No compiler means no object, and this layer's whole verdict is the object's
# undefined-symbol list -- an empty one reads as "calls nothing", which is a
# PASS. That is the false green this repo treats as its worst defect class, so
# it is a skip that NO_SKIP=1 can force, never a quiet success.

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
			echo "forbidden_symbols.sh: --cc-lib directory '$_d' does not exist." >&2
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
	echo "forbidden_symbols: the compiler '$CC' is not executable." >&2
	echo "  This layer compiles before it inspects, so without one it would be" >&2
	echo "  reporting on nothing. Bazel passes the pinned clang through --cc;" >&2
	echo "  if that is missing the target's data is wrong, which is a harness" >&2
	echo "  fault and not a finding about this exercise." >&2
	exit 2
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
rl_traps 'rm -rf "$TMP"'
DEF="$TMP/defined"
UND="$TMP/undefined"
: > "$DEF"
: > "$UND"
: > "$TMP/code.raw"
: > "$TMP/hdrs"

# The lists are one word per line (runner_lib.sh, LISTS OF WORDS); the loop
# below splits nothing else.
rl_split_on
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
		rl_excerpt "$TMP/nm.err" 5 nm-output.txt "" >&2
		exit 2
	fi
	awk 'NF == 3 { print $3 }' "$TMP/nm.out" >> "$DEF"
	awk '$1 == "U" { print $2 }' "$TMP/nm.out" >> "$UND"

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
		cat "$TMP/cc.err" >&2
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
		!sys' "$TMP/pp" >> "$TMP/code.raw"
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
# (judge_classifiers below).
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
EXEMPT=""
for b in $BASELINE; do
	uses "$b" && continue
	EXEMPT="$EXEMPT $b"
done

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
judge_classifiers() {
	_named=""
	for _c in $CTYPE_CLASSIFIERS; do
		grep -qxF "$_c" "$DEF" && continue
		uses "_IS${_c#is}" || continue
		if in_list "$_c" $ALLOWED_LIST; then
			CTYPE_SEEN="${CTYPE_SEEN:+$CTYPE_SEEN, }$_c"
			continue
		fi
		_named=1
		printf '%s\t%s\n' "$_c" "$1" >> "$TMP/bad"
	done
	if [ -n "$CTYPE_SEEN" ]; then
		# conventions: not-a-list -- symbol names nm printed, which hold no blank
		ACCEPTED="$ACCEPTED $1"
	elif [ -z "$_named" ]; then
		printf '%s\t%s\n' "a <ctype.h> classifier" "$1" >> "$TMP/bad"
	fi
}

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
	in_list "$sym" $ALLOWED_LIST $EXEMPT && continue
	pub=$(public_of "$sym")
	if [ -z "$pub" ]; then
		printf '%s\t\n' "$sym" >> "$TMP/bad"
	elif [ "$sym" = "__ctype_b_loc" ]; then
		judge_classifiers "$sym"
	elif in_list "$pub" $ALLOWED_LIST $EXEMPT; then
		ACCEPTED="$ACCEPTED $sym"
	else
		printf '%s\t%s\n' "$pub" "$sym" >> "$TMP/bad"
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

TAB=$(printf '\t')
if [ -s "$TMP/bad" ]; then
	echo "forbidden_symbols: FAIL — this exercise calls a function it is not"
	echo "                   authorised to call."
	echo ""
	echo "  CALLED BUT NOT AUTHORISED:"
	while IFS="$TAB" read -r name sym; do
		case "$name" in
			*" "*) at="" ;;
			*) at=$(where "$name") ;;
		esac
		printf '    %s%s\n' "$name" "${at:+   (at $at)}"
		# The symbol nm actually saw, when it is not the name above: without
		# it, a student searching their file for __ctype_b_loc finds nothing.
		if [ -n "$sym" ]; then
			printf '      seen by nm as %s --\n' "$sym"
			printf '      %s\n' "$(why_alias "$sym")"
		fi
	done < "$TMP/bad"
	echo ""
	echo "  AUTHORISED FOR THIS EXERCISE: $SHOWN"
	echo ""
	echo "  That list is not the harness's opinion: it is the \"Allowed functions\""
	echo "  line of this exercise's subject, copied as written, plus any variable"
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
echo "                   exercise itself or on the subject's authorised list."
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
