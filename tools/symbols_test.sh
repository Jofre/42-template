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
#   symbols_test.sh --nm NM --nm-lib LIB... [--cc CC [--cc-lib LIB]...]
#                   --expect NAME[,NAME...] --src FILE [--src FILE]... [--inc DIR]...
#                   [--inc-file FILE]
#                   [--functions-only] [--no-cross --quotes FILE]
#
#   --no-cross        a name one object defines and another object calls is
#                     held like any other: reported under EXPORTED BUT NOT
#                     ASKED FOR unless --expect names it. By default such a
#                     name is let through (see "Symbols that legitimately
#                     CROSS a file boundary" below); a call site whose
#                     subject wants every helper kept to its own file passes
#                     this, and the sentence that says so.
#   --quotes FILE     KEY<TAB>TEXT lines (tools/runner_lib.sh, rl_quote), for
#                     --no-cross alone: `helpers`, the call site's sentence,
#                     which the red quotes. --no-cross without it, and it
#                     without --no-cross, exit 2: the default mode quotes
#                     nothing.
#
#   --inc-file FILE   the -I directories a Makefile's recipes pass, one per
#                     line (tools/student_build.sh --includes-out;
#                     runner_lib.sh's rl_inc_file): a library's header in a
#                     subfolder is on the grader's include path only
#                     through them.
#
#   --functions-only  compare the exported FUNCTIONS alone (nm codes T and W):
#                     an exported variable is left to a check of its own
#                     (forbidden_symbols.sh --globals), which names it as a
#                     variable. Here its only advice would be the helper's --
#                     make it static -- and a static variable outside every
#                     function is still one that check reports.
#
# Exit status: 0 if the exported set matches exactly, 1 otherwise, 2 if the
# check never ran (an option missing or out of place, no compiler, no nm, or
# an nm that failed to read the objects).
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
require awk cat comm dirname env grep mktemp rm sed sort tr

# The shared runner helpers -- exiting signal traps and excerpts that say what
# they left out -- written once in tools/runner_lib.sh.
RL_NAME=symbols_test
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "symbols_test.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool CC -- the pinned compiler: it builds, and runs none of what it builds
# conventions: harness tool NM -- the pinned nm: it reads symbols, and runs nothing

# The compiler is reached through $CC and probed below, like header_check.sh's,
# so it is not in that list: require exits 2 unconditionally, and a box with no
# compiler should make this layer say it checked nothing, not refuse to start.

EXPECT=""
FUNCTIONS_ONLY=0
NO_CROSS=0
SRCS=""
INCS=""
PROVIDED=""

# The compiler that builds the objects nm then reads. Named and overridable like
# header_check.sh's HEADER_CC and prototype_check.sh's PROTOTYPE_CC, rather than
# a bare `cc` buried mid-script: this layer's four sibling runners all let a
# campus box point them at a specific compiler, and two did not.
#
# SYMBOLS_CC is the hand-run default only: every test is handed the pinned
# clang-12 (--cc), which tools/defs.bzl requires of it (_PINNED_CC_RUNNERS,
# pinned_cc_problem), as Bazel's own toolchain builds every other object in
# the repo with the pinned pair (//tools/cc_toolchain). It once compiled with
# the box's `cc` by default, and c_function's inline _symbols test did so
# until the load-time audit caught it (TO VERIFY V38).
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
		# Absolute, as --cc-lib's below: nm runs with these directories on
		# LD_LIBRARY_PATH, where a relative one is resolved against its cwd.
		--nm-lib)
			need "$1" "$#"
			case "$2" in
				/*) _d=$(dirname "$2") ;;
				*) _d=$(dirname "$PWD/$2") ;;
			esac
			NM_LIBS="${NM_LIBS:+$NM_LIBS:}$_d"
			shift 2 ;;
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
		--functions-only) FUNCTIONS_ONLY=1; shift ;;
		--no-cross) NO_CROSS=1; shift ;;
		--quotes) need "$1" "$#"; rl_quotes_opt "$2"; shift 2 ;;
		# A function the grader compiles in with the student's file. Repeatable.
		# Exporting one gets its own verdict: the static-helper advice below is
		# exactly wrong for it.
		--provided) need "$1" "$#"; rl_list_add PROVIDED "$2"; shift 2 ;;
		--src) need "$1" "$#"; rl_list_add SRCS "$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--inc) need "$1" "$#"; rl_list_add INCS "-I$(_dir "$2")"; shift 2 ;;
		--inc-file) need "$1" "$#"; rl_inc_file INCS "$2"; shift 2 ;;
		*) echo "symbols_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$NM" ] || { echo "symbols_test.sh: --nm is required (no PATH fallback by design)" >&2; exit 2; }
[ -x "$NM" ] || { echo "symbols_test.sh: --nm '$NM' is not executable" >&2; exit 2; }
[ -n "$NM_LIBS" ] || {
	echo "symbols_test.sh: --nm needs --nm-lib, the directory of the pinned nm's" >&2
	echo "  own libbfd: without it the loader takes this machine's, and the nm is" >&2
	echo "  pinned in name only (no fallback by design)." >&2
	exit 2
}

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
# The path nm is proved under is the one it runs with (NM_PATH), and it is
# not exported: the compiler's --cc-lib, below, stays out of it (V274).
NM_PATH="$NM_LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# PROVE THE LOADER AGREED, rather than that the flag arrived: the libbfd nm
# loaded, read by runner_lib.sh's rl_libs_under, under one of --nm-lib's
# directories. The failure being guarded against is exactly one where the
# right file is exec'd and the wrong code runs, so checking which file we
# exec proves nothing. In a subshell, so that the scratch file goes whatever
# it finds.
_dbg=$(mktemp) || { echo "symbols_test.sh: cannot create a scratch file" >&2; exit 2; }
env -u LD_DEBUG_OUTPUT LD_LIBRARY_PATH="$NM_PATH" LD_DEBUG=libs "$NM" --version > /dev/null 2> "$_dbg"
(rl_libs_under "the pinned nm" "$_dbg" "$NM_LIBS" libbfd)
_rc=$?
rm -f "$_dbg"
[ "$_rc" -eq 0 ] || exit 2

[ -n "$EXPECT" ] || { echo "symbols_test.sh: --expect is required" >&2; exit 2; }

# The sentence the --no-cross red quotes comes from the call site (runner_lib.sh,
# A SUBJECT'S SENTENCE COMES FROM THE CALL SITE). The default mode quotes none,
# so a --quotes there is a call site's mistake too.
if [ "$NO_CROSS" = 1 ]; then
	rl_quotes_ready helpers
elif [ -n "$RL_QUOTES" ]; then
	echo "symbols_test.sh: --quotes is for --no-cross; the default mode quotes nothing" >&2
	exit 2
fi
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
# And it must START: one the loader cannot start failed the compile below,
# and the student's file was reported as not compiling (runner_lib.sh's
# rl_cc_starts, V241).
rl_cc_starts "$CC"

WORK=$(mktemp -d)
rl_traps 'rm -rf "$WORK"'

# The lists are one word per line (runner_lib.sh, LISTS OF WORDS).
# Each object is numbered, never named after its source: x.c and sub/x.c,
# which a pattern such as */*.c allows, wrote one x.o, the second over the
# first, so nm read one of the two files -- an asked-for name it defines
# NOT DEFINED, or a stray global it defines unseen, by the order they came
# in (§22 item 5). forbidden_symbols.sh numbers its objects so too.
n=0
rl_split_on
# shellcheck disable=SC2086
for s in $SRCS; do
	n=$((n + 1))
	if ! "$CC" -w -c "$s" $INCS -o "$WORK/$n.o" 2> "$WORK/cc.err"; then
		echo "symbols_test: could not compile $s"
		rl_excerpt "$WORK/cc.err" 20 compiler-output.txt ""
		exit 1
	fi
done
rl_split_off

# Defined symbols only: nm marks them with an uppercase code (lowercase = local,
# which is exactly what `static` produces, and exactly what we want to allow).
# --functions-only keeps the codes of code alone (T, and W for a weak one).
CODES='TDBRW'
[ "$FUNCTIONS_ONLY" = 0 ] || CODES='TW'
# ONE nm RUN, and its status read (TO VERIFY V209). Every list below is cut
# from this one output. A failing nm used to be piped on with its stderr
# thrown away, so the defined names came out empty and every asked-for name
# was reported NOT DEFINED, exit 1: a red on the student, with a spelling
# hint, for a tool that never read the objects. That is a broken harness, so
# exit 2 and show what nm said, as forbidden_symbols.sh does, and run it
# under LC_ALL=C as that runner does, so its messages come out untranslated.
if ! LD_LIBRARY_PATH="$NM_PATH" LC_ALL=C "$NM" "$WORK"/*.o > "$WORK/nm.out" 2> "$WORK/nm.err"; then
	echo "symbols_test: cannot read symbols from the compiled objects (nm failed)" >&2
	rl_excerpt "$WORK/nm.err" 5 nm-output.txt "" >&2
	exit 2
fi
awk -v c="^[$CODES]\$" '$2 ~ c { print $3 }' "$WORK/nm.out" | sort -u > "$WORK/have"
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
#
# ONE nm OVER ALL THE OBJECTS, never one per pair. One object never lists a
# name both as defined and as undefined, so "defined in one object and
# undefined in ANOTHER" is "defined in some object and undefined in some
# object": the defined names above, met with every object's undefined ones.
# It was a loop over every ordered pair, two nm runs each: 3612 of them over
# Libft's 43 files, 45 seconds of a 60-second test, which timed out when the
# rest of the module's tests ran beside it.
#
# --no-cross: where the files are the student's own choice (a pattern such as
# ft_*.c) and the call site's sentence keeps every helper to its own file, a
# helper two files share is exactly what the check is for. No function crosses
# then; the ones that would have are kept apart only to say, under the red,
# why `static` alone would not link them. The sentence is about helper
# functions, so a variable (judged here without --functions-only) crosses as
# it does by default, and the sentence is never quoted over one.
awk '$1 == "U" { print $2 }' "$WORK/nm.out" | sort -u > "$WORK/_und"
comm -12 "$WORK/have" "$WORK/_und" > "$WORK/cross"
awk 'NF == 3 && $2 ~ /^[TW]$/ { print $3 }' "$WORK/nm.out" | sort -u > "$WORK/funcs"
if [ "$NO_CROSS" = 1 ]; then
	comm -23 "$WORK/cross" "$WORK/funcs" > "$WORK/cross_kept"
else
	cat "$WORK/cross" > "$WORK/cross_kept"
fi
cat "$WORK/want" "$WORK/cross_kept" | sort -u > "$WORK/allowed"

MISSING=$(comm -13 "$WORK/have" "$WORK/want")
EXTRA=$(comm -23 "$WORK/have" "$WORK/allowed")
# The names that cross and are not asked for: one the subject names is
# exported for that reason already, and listing it again as "plus" would
# call it an extra (one Libft function calling another, in another file).
CROSS=$(comm -12 "$WORK/cross_kept" "$WORK/have" | comm -23 - "$WORK/want")

# Supplied functions come out of EXTRA into a list of their own. Told "make it
# static", a student who wrote their own ft_putchar keeps it -- static, still
# calling write, still a body the subject never asked for.
SUPPLIED=""
rl_split_on
for p in $PROVIDED; do
	if printf '%s\n' "$EXTRA" | grep -qxF "$p"; then
		SUPPLIED="$SUPPLIED $p"
		EXTRA=$(printf '%s\n' "$EXTRA" | grep -vxF "$p" || true)
	fi
done
rl_split_off

# A main() comes out of EXTRA too, for the same reason (finding 037): the
# advice below -- make it static -- is wrong for it. A static main does not
# compile under -Wall -Wextra -Werror (clang and gcc both name -Wmain), and the
# fix is not to hide it but to move it: the grader brings its own main().
# Only where the subject did not ask for one: an exercise whose --expect names
# main never has it in EXTRA.
STRAY_MAIN=0
if printf '%s\n' "$EXTRA" | grep -qxF main; then
	STRAY_MAIN=1
	EXTRA=$(printf '%s\n' "$EXTRA" | grep -vxF main || true)
fi

if [ -z "$MISSING" ] && [ -z "$EXTRA" ] && [ -z "$SUPPLIED" ] && [ "$STRAY_MAIN" -eq 0 ]; then
	if [ -n "$CROSS" ]; then
		echo "symbols_test: OK — exports $(tr '\n' ' ' < "$WORK/want")plus $(printf '%s' "$CROSS" | tr '\n' ' ')"
		echo "              (the extra name(s) are defined in one of this exercise's files"
		echo "               and used by another, so they have to be external, and"
		echo "               this target lets such a name through.)"
	else
		echo "symbols_test: OK — exports exactly: $(tr '\n' ' ' < "$WORK/want" | sed 's/ $//')"
	fi
	exit 0
fi

echo "symbols_test: FAIL"
if [ -n "$MISSING" ]; then
	# conventions: the call site's --expect -- the functions the contract lists
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
	echo "  see what the 'static' storage class does to a name's linkage."
	if [ "$NO_CROSS" = 1 ]; then
		# A shared helper's own line: told "make it static" alone, the
		# student meets a link error in the file that calls it.
		_shared=$(printf '%s\n' "$EXTRA" | grep -xF -f "$WORK/cross" || true)
		if [ -n "$_shared" ]; then
			echo "  Another of this exercise's files calls these, so 'static' alone would"
			echo "  stop that call from linking:"
			printf '%s\n' "$_shared" | sed 's/^/    /'
		fi
		# The sentence is about functions: quoted over those alone, and
		# naming them when a variable is reported beside them.
		_fextra=$(printf '%s\n' "$EXTRA" | grep -xF -f "$WORK/funcs" || true)
		if [ -n "$_fextra" ]; then
			if [ "$_fextra" = "$EXTRA" ]; then
				echo "  The requirement:"
			else
				echo "  The requirement, over the function(s) among them: $(printf '%s' "$_fextra" | tr '\n' ' ' | sed 's/ $//')"
			fi
			rl_quote helpers | sed 's/^/    /'
		fi
	else
		echo "  (A helper that ANOTHER of this exercise's files calls is allowed to be"
		echo "   external; it is only the ones nobody else references that must be static.)"
	fi
fi
if [ "$STRAY_MAIN" -eq 1 ]; then
	echo "  DEFINES main():"
	echo "    main"
	# conventions: the call site's --expect -- the functions the contract lists, and no main
	echo "  The subject asks this file for a function, not a program. The grader"
	echo "  compiles its own main() with your file, and a program with two mains"
	echo "  does not link. Keep the main() you test with in a file of its own:"
	echo "  outside deliverable/, which is what gets pushed -- or, where a"
	echo "  main.c is among the files to turn in, in that one."
	echo "  (Making it static is no way out: -Wall -Wextra -Werror refuses a"
	echo "  static main.)"
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
