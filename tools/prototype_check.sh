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
# THE SUBJECT'S STRUCTURE, TOO (--layout FILE). C 12 and C 13 print the
# structure every exercise's header must hold, and the grader builds its own
# nodes on it ("From exercise 01 onward, we'll use our ft_create_elem"), so a
# header that lays t_list out differently -- fields swapped, another type, a
# field more -- is a KO however right the function. The student's header is
# the one every test compiles with, so nothing else can see it (finding 132).
# FILE is a header under the project's tests/layout/, named after the header
# it checks (tests/layout/ft_list.h checks the student's ft_list.h): it
# declares the subject's structure under a tag of its own and asserts, with
# _Static_assert, that the student's type has the same field types, offsets
# and size -- what decides whether two programs read one node alike.
#
# --layout-tag FILE is the rest of what the subject prints: the structure's
# tag and the type of each field that points to another node (struct s_list,
# struct s_list *next). A header naming them otherwise lays the node out the
# same, so the grader's own nodes still read right; only code written against
# the subject's header by name -- the grader's tests may be -- tells them
# apart. So it is a file of its own, tests/layout/tag/<header>, and a check of
# its own at strict (tools/defs.bzl, _prototype_test).
#
# Each header a --layout or --layout-tag file checks is force-included by name
# first, found where the student's file finds it, then every --layout, then
# every --layout-tag. With no --proto, the run checks the structure alone: the
# twin exNN_layout_prototype.
#
# WHAT A RED IS ABOUT, read from what failed (finding 133). This runner used
# to print one headline, "does not match the signature", over every compile
# error, whatever caused it. Now, in order:
#
#   the file does not compile on its own (compiled first, alone): a syntax
#       error or a missing header -- the compile layer's red, repeated;
#   a header read twice with no include guard -- prototype.h includes it and
#       so does the file -- which the Norm requires of every header. Decided
#       by fact, never by the word "redefinition" alone: the compiler says
#       the header was included twice ("included multiple times", "unguarded
#       header"), or the second definition is the same line of the same file
#       as the first;
#   a name defined twice in two places: the header defines it, and the file
#       defines it again (a structure written out in the .c instead of
#       included). Not a missing guard, and it used to be reported as one;
#   an error inside a layout file: the structure differs from the subject's
#       (--layout), or is named otherwise (--layout-tag);
#   anything else: the signature the subject specifies.
#
# THE NAMES (--names). A subject may fix the parameters' NAMES as well as
# their types -- Rush 00's "It must take two integer arguments, named x and
# y" -- and a conflicting-types error cannot see a name. With --names this
# runner checks the names instead, and only them (the types are the default
# mode's, at basic): for each function the --proto file declares, the
# definition among the --src files must name its parameters as the
# declaration does. It reads both through the pinned clang's own AST dump
# (-Xclang -ast-dump), never by matching C text: a declaration spread over
# lines, a macro, a comment between two parameters all parse the way the
# compiler parses them. Names change no behaviour and only an evaluator
# reading the code can mark them, so a target of this mode sits at strict
# (tools/defs.bzl's _prototype_names_test). The --proto file must include
# nothing: its own declarations are the whole contract, and a header it
# pulled in would add declarations nobody transcribed.
#
# NO RESTRICT (--no-restrict). A subject may forbid the `restrict` qualifier
# in the student's prototypes, and a conflicting-types error cannot see it:
# clang-12 accepts `void *f(void *restrict d)` against a plain redeclaration
# under -Wall -Wextra -Werror, since a qualifier on a parameter itself is not
# part of the function's type. With --no-restrict this runner reads the
# pinned clang's AST dump of every turned-in file (each --src, and each
# --hdr, the headers the turn-in itself provides: the call site names them,
# from the contract's own list) and reports every declaration or definition
# LOCATED IN ONE OF THOSE FILES, of a function it judges (below), whose
# parameters or return type carry restrict: written restrict, __restrict
# or __restrict__ (clang prints all three as restrict), on a parameter, on
# a pointer inside a parameter -- a function pointer's own parameters
# included -- on the return type, or through a typedef that holds it. Each
# red names the function, the parameter and file:line, and quotes the
# sentence the call site passes (--quotes, key `restrict`).
#
# What counts as a prototype here is the reading every reading agrees on:
# the declaration or definition of a function the --proto file itself
# declares (the ones located in --proto, read as --declares reads them),
# its parameters and its return type. Whether a function of the student's
# own -- a static helper -- has a prototype a subject's sentence covers is
# left open by such a sentence, so it is a reading: --all-functions judges
# every function declared or defined in the turned-in files, takes no
# --proto, and says on its red that it is this harness's reading (a strict
# target's). Its OK line says what it judged, and the default's names the
# --proto file, never the other reading. A local variable declared
# restrict inside a body is not a prototype, and is not judged. A
# declaration that comes from any other file -- libc's own restrict
# prototypes, brought in by #include <string.h> -- is not the student's,
# and is not judged either; the OK line counts them, without
# saying whose they are (a system header's, a grader's, or a file of the
# student's the call site did not name: this runner cannot tell). Nor is a
# declaration clang makes itself at a call with no prototype in sight
# (implicit): nobody wrote it, and the compile layer reports the call. A
# declaration is placed at its name, not where its first word is spelled,
# so `bool f(char *restrict p)` is the student's line, not <stdbool.h>'s.
#
# A file is "turned in" by identity, not by spelling: clang prints a header
# as it found it (./x.h, dir/x.h), so each path is compared by its folder's
# physical path and its name. A --hdr no --src includes is read through
# main.c, a file of one line, #include "<it>", so its declarations are
# judged too -- from the dump, whatever clang's exit status: clang prints
# the whole tree even when the header does not compile on its own (a
# missing include), and whether it must is --declares' question, not this
# one's. Only a dump with no translation unit in it is a red, the header's
# prototypes unread.
#
# DECLARED BY THE HEADER (--declares). A reading, at strict: a program that
# includes the student's header and nothing else of theirs -- as a main an
# evaluator writes may -- must find every function the --proto file itself
# declares (the ones located in --proto, not in the header it includes).
# Each --hdr is included on its own, in a file of one line, and the names of
# the functions that file then declares are read from the AST; a function
# defined in a .c and declared in no header is missing, and so is every
# one of them when a --hdr does not compile included alone (a red of its
# own, which names the reading and quotes the call site as the other does,
# and shows the header by the name the call site gave it and the file of
# one line as main.c, never by the runner's own folder). Only PRESENCE is
# reported: the default mode compiles --proto with the student's header in
# one translation unit, so a declaration whose type conflicts is that red,
# and this one counts the function as declared (the contract's names are
# read from clang's dump of that same compile, which it prints in full even
# when the compile fails).
#
# Both modes read the AST, never C text, the way --names does. A source
# that does not compile is a red (the compile layer says why); a compiler
# that cannot dump an AST at all (not a clang) is exit 2.
#
# Usage:
#   prototype_check.sh [--proto FILE] [--layout FILE]... [--layout-tag FILE]...
#                      --src FILE [--src FILE]...
#                      [--inc DIR]... [--inc-file FILE]
#                      [--grader-hdr FILE [--readme PATH]]...
#                      [--cc NAME] [--names]
#   (at least one of --proto, --layout and --layout-tag; --names takes --proto
#   alone)
#   prototype_check.sh --no-restrict --quotes FILE (--proto FILE | --all-functions)
#                      [--src FILE]... [--hdr FILE]... [--inc DIR]... [--cc NAME]
#   (at least one --src or --hdr)
#   prototype_check.sh --declares --quotes FILE --proto FILE --hdr FILE...
#                      [--src FILE]... [--inc DIR]... [--cc NAME]
#
# --inc-file FILE (any mode) holds the -I directories a Makefile's recipes
# pass, one per line (tools/student_build.sh --includes-out, runner_lib.sh's
# rl_inc_file): a library's header in a subfolder is on the grader's include
# path only through them, so they join --inc's directories.
#
# --hdr FILE is a header the turn-in itself provides. --quotes FILE holds the
# sentence a red quotes, one KEY<TAB>TEXT line (tools/runner_lib.sh,
# rl_quote): key `restrict` for --no-restrict, `declares` for --declares.
#
# --grader-hdr FILE is a header the GRADER brings (the contract's `provided`),
# kept under the project's tests/: on the include path, and named on any red,
# with the -I a compile by hand needs (rl_grader_hdrs); --readme names the
# project's page that shows one.
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
require awk basename cat cut dirname grep mkdir mktemp rm sed sort tr wc

# The shared runner helpers -- exiting signal traps and excerpts that say what
# they left out -- written once in tools/runner_lib.sh.
RL_NAME=prototype_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "prototype_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool CC -- the pinned compiler: it builds, and runs none of what it builds

PROTO=""
LAYOUTS=""
TAGS=""
GRADER_HDRS=""
README=""
SRCS=""
INCS=""
CC="${PROTOTYPE_CC:-cc}"
CC_LIBS=""
NAMES=0
NO_RESTRICT=0
ALL_FN=0
DECLARES=0
HDRS=""
# The include directories of the turn-in alone (every --src's, --hdr's, --inc
# and --grader-hdr): where a program that includes only the student's header
# finds it, with no --proto directory on the path.
TINCS=""

_dir() {
	if [ -d "$1" ]; then printf '%s\n' "$1"; else dirname "$1"; fi
}

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "prototype_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--proto) need "$1" "$#"; PROTO="$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--layout) need "$1" "$#"; rl_list_add LAYOUTS "$2"; shift 2 ;;
		--layout-tag) need "$1" "$#"; rl_list_add TAGS "$2"; shift 2 ;;
		--grader-hdr)
			need "$1" "$#"
			rl_list_add INCS "-I$(_dir "$2")"
			rl_list_add TINCS "-I$(_dir "$2")"
			rl_list_add GRADER_HDRS "$2"
			shift 2 ;;
		--readme) need "$1" "$#"; README="$2"; shift 2 ;;
		--src)
			need "$1" "$#"
			rl_list_add SRCS "$2"
			rl_list_add INCS "-I$(dirname "$2")"
			rl_list_add TINCS "-I$(dirname "$2")"
			shift 2 ;;
		--hdr)
			need "$1" "$#"
			rl_list_add HDRS "$2"
			rl_list_add INCS "-I$(dirname "$2")"
			rl_list_add TINCS "-I$(dirname "$2")"
			shift 2 ;;
		--inc) need "$1" "$#"; rl_list_add INCS "-I$(_dir "$2")"; rl_list_add TINCS "-I$(_dir "$2")"; shift 2 ;;
		--inc-file) need "$1" "$#"; rl_inc_file INCS "$2"; rl_inc_file TINCS "$2"; shift 2 ;;
		--quotes) need "$1" "$#"; rl_quotes_opt "$2"; shift 2 ;;
		--no-restrict) NO_RESTRICT=1; shift ;;
		--all-functions) ALL_FN=1; shift ;;
		--declares) DECLARES=1; shift ;;
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
		--names) NAMES=1; shift ;;
		*) echo "prototype_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ $((NAMES + NO_RESTRICT + DECLARES)) -le 1 ] || {
	echo "prototype_check.sh: --names, --no-restrict and --declares are three checks; give one" >&2
	exit 2
}
[ "$ALL_FN" -eq 0 ] || [ "$NO_RESTRICT" -eq 1 ] || {
	echo "prototype_check.sh: --all-functions belongs to --no-restrict" >&2
	exit 2
}
if [ "$NO_RESTRICT" -eq 1 ]; then
	[ -n "$SRCS$HDRS" ] && [ -z "$LAYOUTS$TAGS" ] || {
		echo "prototype_check.sh: --no-restrict reads the turned-in files (--src, --hdr): give at" >&2
		echo "  least one, and no --layout or --layout-tag, which it does not read" >&2
		exit 2
	}
	# Which functions it judges: the ones --proto declares, or, with
	# --all-functions, every one -- which reads no --proto.
	if [ "$ALL_FN" -eq 1 ]; then
		[ -z "$PROTO" ] || {
			echo "prototype_check.sh: --all-functions judges every function, and reads no --proto" >&2
			exit 2
		}
	else
		[ -n "$PROTO" ] || {
			echo "prototype_check.sh: --no-restrict judges the functions --proto declares: give it," >&2
			echo "  or --all-functions to judge every function in the turned-in files" >&2
			exit 2
		}
	fi
	rl_quotes_ready restrict
elif [ "$DECLARES" -eq 1 ]; then
	[ -n "$PROTO" ] && [ -n "$HDRS" ] && [ -z "$LAYOUTS$TAGS" ] || {
		echo "prototype_check.sh: --declares reads the functions --proto declares, and each --hdr" >&2
		echo "  included on its own: give both, and no --layout or --layout-tag" >&2
		exit 2
	}
	rl_quotes_ready declares
else
	[ -n "$PROTO$LAYOUTS$TAGS" ] && [ -n "$SRCS" ] || {
		echo "prototype_check.sh: need --proto, --layout or --layout-tag, and at least one --src" >&2
		exit 2
	}
	# Read by no message of these modes, so given here they would be
	# dropped without a word.
	[ -z "$HDRS$RL_QUOTES" ] || {
		echo "prototype_check.sh: --hdr and --quotes belong to --no-restrict and --declares" >&2
		exit 2
	}
fi
[ "$NAMES" -eq 0 ] || { [ -n "$PROTO" ] && [ -z "$LAYOUTS$TAGS" ]; } || {
	echo "prototype_check.sh: --names reads the parameters' names from --proto, and" >&2
	echo "  checks nothing else: give it --proto, and no --layout or --layout-tag" >&2
	exit 2
}
# The lists -- sources, include directories, layout files, the grader's
# headers, what is force-included -- are one word per line (runner_lib.sh,
# LISTS OF WORDS), expanded between rl_split_on and rl_split_off.
rl_split_on
for _l in $LAYOUTS $TAGS; do
	[ -f "$_l" ] || {
		echo "prototype_check.sh: layout file '$_l' is not a file" >&2
		exit 2
	}
done
rl_split_off


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
# And it must START: one the loader cannot start failed the compile below,
# and the student's file was reported as not compiling (runner_lib.sh's
# rl_cc_starts, V241).
rl_cc_starts "$CC"

WORK=$(mktemp -d)
rl_traps 'rm -rf "$WORK"'
TAB=$(printf '\t')

# canon PATH: PATH's folder as its physical path, then its name. clang
# prints a header as it found it (./x.h, dir/x.h), and Bazel hands a file
# over by another spelling, so two names are the same file when this agrees.
canon() {
	_cd=$(cd -P -- "$(dirname -- "$1")" 2> /dev/null && pwd -P) || return 1
	printf '%s/%s\n' "$_cd" "$(basename -- "$1")"
}

# ast_probe: exit 2 unless the compiler dumps an AST of an empty file. The
# two modes below read nothing else, so a compiler that cannot (not a clang)
# would otherwise be reported as every file of the turn-in not compiling.
ast_probe() {
	if ! "$CC" -x c -fsyntax-only -fno-color-diagnostics -Xclang -ast-dump /dev/null \
			> "$WORK/probe.ast" 2> "$WORK/cc.err" ||
		! grep -q '^TranslationUnitDecl ' "$WORK/probe.ast"; then
		echo "prototype_check.sh: '$CC' could not dump the AST of an empty file, so nothing" >&2
		echo "  was checked (these modes read clang's -Xclang -ast-dump):" >&2
		rl_excerpt "$WORK/cc.err" 10 compiler-output.txt "  " >&2
		exit 2
	fi
}

# THE AST, READ (ast.awk). clang's text dump prints each node on a line,
# indented by its depth, and a location only by what changed since the last
# one it printed: "file:line:col" when the file changes, "line:L:C" when the
# line does, "col:C" otherwise. So the file a declaration sits in is known
# only by reading every location in order, as this does: the range <...> of
# each node, then a declaration's own location after it.
#     FunctionDecl 0x... prev 0x... <toy.c:3:1, line:11:1> line:3:7 toy 'void *(void *, int)'
#     |-ParmVarDecl 0x... <col:16, col:31> col:31 used d 'void *restrict'
# A declaration belongs to the file of its OWN location -- where its name
# is written -- and is named at that line. Not the start of its range: clang
# prints the spelling there, so a prototype that begins with a macro (bool,
# from <stdbool.h>; a type macro of the student's) would begin in the file
# that defines the macro. The range's start is the fallback only when the
# own location is invalid or "<scratch space>" (a name made by ##). A
# declaration clang made itself, for a call with no prototype in sight
# (flagged implicit), is nobody's prototype and is dropped. It prints
# tagged lines:
#   S <file>                    a file a declaration is in
#   N <file> <name>             a function declared at the top level
#   R <file> <line> <function> <n> <param> <type>
#                               restrict in a prototype: parameter n (its name,
#                               or "-"), or n = 0 for the return type (<type>
#                               is then the function's)
# Each parameter is read on its own line, which holds what that declaration
# writes, and the return type from the function's type (rettype, below); a
# typedef whose type holds restrict counts wherever its name is used.
cat > "$WORK/ast.awk" <<'AST_AWK'
function loc(s,   m) {
	LF = ""
	LL = 0
	if (substr(s, 1, 14) == "<invalid sloc>") return substr(s, 15)
	if (match(s, /^col:[0-9]+/)) { LF = F; LL = L; return substr(s, RLENGTH + 1) }
	if (match(s, /^line:[0-9]+:[0-9]+/)) {
		m = substr(s, 6, RLENGTH - 5)
		sub(/:.*/, "", m)
		L = m + 0; LF = F; LL = L
		return substr(s, RLENGTH + 1)
	}
	if (match(s, /:[0-9]+:[0-9]+/)) {
		F = substr(s, 1, RSTART - 1)
		m = substr(s, RSTART + 1, RLENGTH - 1)
		sub(/:.*/, "", m)
		L = m + 0; LF = F; LL = L
		return substr(s, RSTART + RLENGTH)
	}
	return s
}
function hasr(t,   n, w, i) {
	n = split(t, w, /[^A-Za-z0-9_]+/)
	for (i = 1; i <= n; i++) if (w[i] == "restrict" || (w[i] in rtd)) return 1
	return 0
}
# group(t, i): where the parenthesised group opening at t[i] closes, or 0.
function group(t, i,   d, n) {
	n = length(t)
	d = 0
	for (; i <= n; i++) {
		if (substr(t, i, 1) == "(") d++
		else if (substr(t, i, 1) == ")" && --d == 0) return i
	}
	return 0
}
# rettype(t): a function's type less its own parameter list -- the return
# type. Read from the function's type alone: a redeclaration takes the type
# of the one before it, so its parameters there may hold a qualifier this
# declaration does not write (each parameter's own line holds what it does),
# while a return type that differs is a conflicting-types error. The list is
# the last group, "R (P)"; in "R (*(P))(Q)", a function returning a function
# pointer, it is the group right after the "*", and (Q) is the return type's.
# An attribute clang prints after the list -- 'void (char *) __attribute__((
# noreturn))' -- is dropped first, or its group would pass for the list and
# the parameters' restrict for the return type's.
function rettype(t,   i, j, n, d) {
	for (;;) {
		n = length(t)
		if (substr(t, n, 1) != ")") return t
		d = 0
		for (i = n; i > 0; i--) {
			if (substr(t, i, 1) == ")") d++
			else if (substr(t, i, 1) == "(" && --d == 0) break
		}
		if (i <= 1) return t
		if (substr(t, 1, i - 1) !~ /__attribute__[ ]*$/) break
		t = substr(t, 1, i - 1)
		sub(/[ ]*__attribute__[ ]*$/, "", t)
	}
	if (substr(t, 1, i - 1) !~ /\)[ ]*$/) return substr(t, 1, i - 1)
	if (!match(t, /\*[a-z ]*\(/)) return t
	i = RSTART + RLENGTH - 1
	if (!(j = group(t, i))) return t
	return substr(t, 1, i - 1) substr(t, j + 1)
}
# A function's type printed sugared, 'A':'B' -- declared through a function
# typedef, or with a calling convention -- is read by B, the desugared one:
# A alone holds no parameter list, and the typedef's name in it would pass
# for a return type that holds restrict. The line printed keeps both.
function close_fn(   t, i) {
	t = st[sp]
	if ((i = index(t, "\047:\047")) > 0) t = substr(t, i + 3)
	if (!sk[sp] && hasr(rettype(t)))
		printf "R\t%s\t%d\t%s\t0\t-\t%s\n", sf[sp], sl[sp], sfn[sp], st[sp]
	sp--
}
/^TranslationUnitDecl 0x/ { tu = 1 }
{
	if (!match($0, /[A-Za-z]+ 0x[0-9a-f]+/)) next
	kind = substr($0, RSTART, RLENGTH)
	sub(/ .*/, "", kind)
	depth = RSTART - 1
	rest = substr($0, RSTART + RLENGTH)
	while (sub(/^ (parent|prev) 0x[0-9a-f]+/, "", rest)) ;
	bf = ""; bl = 0
	if (substr(rest, 1, 2) == " <") {
		rest = loc(substr(rest, 3)); bf = LF; bl = LL
		if (substr(rest, 1, 2) == ", ") rest = loc(substr(rest, 3))
		if (substr(rest, 1, 1) == ">") rest = substr(rest, 2)
	}
	while (sp > 0 && depth <= sd[sp]) close_fn()
	if (kind !~ /Decl$/) next
	LF = ""
	if (substr(rest, 1, 1) == " ") rest = loc(substr(rest, 2))
	if (LF != "" && LF !~ /^<scratch space>/) { bf = LF; bl = LL }
	if (bf != "") seen[bf] = 1
	# What is left: flags, the name unless there is none, the type in quotes.
	name = ""
	imp = 0
	n = split(rest, t, " ")
	for (i = 1; i <= n; i++) {
		if (t[i] ~ /^\047/) break
		if (t[i] == "implicit") imp = 1
		if (t[i] ~ /^(used|referenced|implicit|invalid|imported|hidden)$/) continue
		name = t[i]
		break
	}
	type = ""
	if (match(rest, /\047.*\047/)) type = substr(rest, RSTART + 1, RLENGTH - 2)
	if (kind == "TypedefDecl" && name != "" && hasr(type)) rtd[name] = 1
	if (kind == "FunctionDecl") {
		if (depth == 2 && !imp) printf "N\t%s\t%s\n", bf, name
		sp++
		sd[sp] = depth; sfn[sp] = name; sf[sp] = bf; sl[sp] = bl; st[sp] = type
		sn[sp] = 0; sk[sp] = imp
		next
	}
	if (kind == "ParmVarDecl" && sp > 0 && !sk[sp] && depth == sd[sp] + 2) {
		sn[sp]++
		if (hasr(type))
			printf "R\t%s\t%d\t%s\t%d\t%s\t%s\n", sf[sp], (bf == sf[sp] ? bl : sl[sp]), \
				sfn[sp], sn[sp], (name == "" ? "-" : name), type
	}
}
END {
	if (!tu) exit 3
	while (sp > 0) close_fn()
	for (f in seen) printf "S\t%s\n", f
}
AST_AWK

# read_ast DUMP OUT: ast.awk over DUMP into OUT, or exit 2 -- an awk that
# failed, or a dump with no translation unit in it, has read nothing, and
# would otherwise say no prototype holds restrict.
read_ast() {
	awk -f "$WORK/ast.awk" "$1" > "$2" && return 0
	echo "prototype_check.sh: could not read the compiler's AST dump of $3, so nothing" >&2
	echo "  was checked (ast.awk failed, or found no TranslationUnitDecl in it)" >&2
	exit 2
}

# alone HDR: compile main.c, a file whose one line includes HDR by its
# name -- #include "<name>", its folder first on the quote path -- its dump
# into $WORK/src.ast, its messages into $WORK/cc.err with main.c named by
# that name alone and HDR as the call site gave it (the headers beside it
# by that folder too): never the runner's own folder, nor the physical
# path of the header's. Its include line holds no path, so an error clang
# places at its end (a last prototype with no ";") shows that line as it
# is, its caret where the error is.
alone() {
	_hc=$(canon "$1") || _hc=$1
	_hd=$(dirname -- "$_hc")
	mkdir -p "$WORK/m"
	printf '#include "%s"\n' "$(basename -- "$1")" > "$WORK/m/main.c"
	# shellcheck disable=SC2086
	"$CC" -fsyntax-only -fno-color-diagnostics -iquote "$_hd" $TINCS -Xclang -ast-dump \
		"$WORK/m/main.c" > "$WORK/src.ast" 2> "$WORK/cc.raw"
	_arc=$?
	_cd=$(dirname -- "$1")
	[ "$_cd" = . ] && _cd="" || _cd="$_cd/"
	awk -v from="$_hd/" -v to="$_cd" -v me="$WORK/m/" '
		$0 == "In file included from " me "main.c:1:" { next }
		{
			o = ""
			while ((i = index($0, me)) > 0) {
				o = o substr($0, 1, i - 1)
				$0 = substr($0, i + length(me))
			}
			$0 = o $0
			o = ""
			while ((i = index($0, from)) > 0) {
				o = o substr($0, 1, i - 1) to
				$0 = substr($0, i + length(from))
			}
			print o $0
		}' "$WORK/cc.raw" > "$WORK/cc.err"
	return "$_arc"
}

# proto_wanted [soft]: the functions declared IN --proto, by identity, each
# once, in order, into $WORK/want -- or exit 2 when there is none, or with
# soft return 1, the compiler's messages left in $WORK/cc.err. The contract
# is compiled with the header it may include, and a declaration there whose
# type conflicts with the contract's fails that compile -- the types mode's
# red, not these modes' -- while clang dumps the whole tree all the same,
# the conflicting declaration flagged invalid; so the dump is read whatever
# the exit status, and only a dump with no translation unit in it stops the
# check (read_ast, exit 2). Called outside rl_split_on, which it uses
# itself.
proto_wanted() {
	rl_split_on
	# shellcheck disable=SC2086
	"$CC" -x c -fsyntax-only -fno-color-diagnostics $INCS -Xclang -ast-dump "$PROTO" \
		> "$WORK/proto.ast" 2> "$WORK/cc.err"
	rl_split_off
	_pc=$(canon "$PROTO") || _pc=$PROTO
	read_ast "$WORK/proto.ast" "$WORK/one" "$(basename "$PROTO")"
	awk -F'\t' '$1 == "N" { print $2 "\t" $3 }' "$WORK/one" > "$WORK/proto.n"
	: > "$WORK/want"
	while IFS="$TAB" read -r _r _fn; do
		_c=$(canon "$_r") || _c=$_r
		[ "$_c" = "$_pc" ] || continue
		grep -qxF -- "$_fn" "$WORK/want" || printf '%s\n' "$_fn" >> "$WORK/want"
	done < "$WORK/proto.n"
	[ -s "$WORK/want" ] || {
		[ "${1:-}" = soft ] && return 1
		echo "prototype_check.sh: no function declared in $(basename "$PROTO") itself could be read," >&2
		echo "  so there is nothing to look for. The compiler said:" >&2
		rl_excerpt "$WORK/cc.err" 10 compiler-output.txt "  " >&2
		exit 2
	}
}

if [ "$NO_RESTRICT" -eq 1 ]; then
	ast_probe
	: > "$WORK/found"
	: > "$WORK/turnin"
	RC=0
	rl_split_on
	for _f in $SRCS $HDRS; do
		canon "$_f" >> "$WORK/turnin" || printf '%s\n' "$_f" >> "$WORK/turnin"
	done
	for src in $SRCS; do
		# shellcheck disable=SC2086
		if ! "$CC" -fsyntax-only -fno-color-diagnostics $TINCS -Xclang -ast-dump "$src" \
				> "$WORK/src.ast" 2> "$WORK/cc.err"; then
			echo "prototype_check: FAIL — $(basename "$src") does not compile, so its prototypes"
			echo "                 cannot be read. The compile layer says why:"
			echo ""
			rl_excerpt "$WORK/cc.err" 20 compiler-output.txt "  "
			echo ""
			RC=1
			continue
		fi
		read_ast "$WORK/src.ast" "$WORK/one" "$(basename "$src")"
		cat "$WORK/one" >> "$WORK/found"
	done
	_broke=$RC
	# A header no source brought in is read on its own, through a file that
	# includes it and nothing else: from the dump, whatever clang's exit
	# status (NO RESTRICT, at the top). A dump with no translation unit has
	# nothing in it to read.
	awk -F'\t' '$1 == "S" { print $2 }' "$WORK/found" | LC_ALL=C sort -u > "$WORK/files"
	: > "$WORK/seen"
	while IFS= read -r _r; do
		canon "$_r" >> "$WORK/seen"
	done < "$WORK/files"
	for hdr in $HDRS; do
		_hc=$(canon "$hdr") || _hc=$hdr
		grep -qxF -- "$_hc" "$WORK/seen" && continue
		alone "$hdr" || _broke=1
		if ! grep -q '^TranslationUnitDecl ' "$WORK/src.ast"; then
			echo "prototype_check: FAIL — $(basename "$hdr") cannot be read: no file that compiled"
			echo "                 here includes it, and the compiler read nothing of it"
			echo "                 on its own. The compiler said:"
			echo ""
			rl_excerpt "$WORK/cc.err" 20 compiler-output.txt "  "
			echo ""
			RC=1
			continue
		fi
		read_ast "$WORK/src.ast" "$WORK/one" "$(basename "$hdr")"
		cat "$WORK/one" >> "$WORK/found"
	done
	rl_split_off
	# The functions judged: every one, or the ones --proto declares -- read
	# after the turned-in files, since the contract includes the student's
	# header: one that does not compile can swallow every declaration after
	# it (an unclosed brace), and then nothing is read of the contract. That
	# is the student's red when a turned-in file did not compile, and exit 2
	# (the harness's) only when every one did.
	if [ "$ALL_FN" -eq 1 ]; then
		: > "$WORK/want"
	elif [ "$_broke" -eq 0 ]; then
		proto_wanted
	elif ! proto_wanted soft; then
		echo "prototype_check: FAIL — no function $(basename "$PROTO") declares could be read: with"
		echo "                 your files as they are, its own compile stops before them."
		echo "                 The compiler said:"
		echo ""
		rl_excerpt "$WORK/cc.err" 20 compiler-output.txt "  "
		exit 1
	fi
	# Each file a finding names, by identity: "<as printed><TAB><canon>".
	awk -F'\t' '$1 == "R" { print $2 }' "$WORK/found" | LC_ALL=C sort -u > "$WORK/files"
	: > "$WORK/map"
	while IFS= read -r _r; do
		_c=$(canon "$_r") || _c=$_r
		printf '%s\t%s\n' "$_r" "$_c" >> "$WORK/map"
	done < "$WORK/files"
	# Each finding once, however many sources include its header: in a
	# turned-in file, of a function judged here (every one, or the ones
	# --proto declares). One in a file that is not turned in is counted
	# among the others only when its function is one --proto declares: a
	# system header's own prototypes (libc's are full of restrict) are no
	# function of the student's, and a count of them is nothing anyone can
	# act on (a green Libft log said restrict appeared in 80 places, the
	# libft review of 2026-10-13). --all-functions judges the functions the
	# turned-in files declare, so no file outside them has one to count.
	awk -F'\t' -v OFS='\t' -v others="$WORK/others" -v all="$ALL_FN" '
		FILENAME == ARGV[1] { c[$1] = $2; next }
		FILENAME == ARGV[2] { mine[$1] = 1; next }
		FILENAME == ARGV[3] { want[$1] = 1; next }
		$1 != "R" { next }
		{ k = c[$2] SUBSEP $3 SUBSEP $4 SUBSEP $5 }
		!(c[$2] in mine) {
			if (all != 1 && ($4 in want) && !(k in o)) { o[k] = 1; no++ }
			next
		}
		all != 1 && !($4 in want) { next }
		k in done { next }
		{ done[k] = 1; print c[$2], $3, $4, $5, $6, $7 }
		END { print no + 0 > others }' "$WORK/map" "$WORK/turnin" "$WORK/want" "$WORK/found" |
		LC_ALL=C sort -t "$TAB" -k1,1 -k2,2n > "$WORK/mine"
	_others=$(cat "$WORK/others")
	if [ -s "$WORK/mine" ]; then
		_nf=$(wc -l < "$WORK/mine" | tr -d ' ')
		if [ "$_nf" -eq 1 ]; then _places="1 place"; else _places="$_nf places"; fi
		echo "prototype_check: FAIL — restrict appears in $_places in your prototypes:"
		echo ""
		while IFS="$TAB" read -r _c _l _fn _n _p _t; do
			if [ "$_n" = 0 ]; then
				_what="its return type"
			elif [ "$_p" = - ]; then
				_what="parameter $_n"
			else
				_what="parameter $_n ($_p)"
			fi
			echo "  $(basename "$_c"):$_l: $_fn(), $_what: '$_t'"
		done < "$WORK/mine"
		echo ""
		if [ "$ALL_FN" -eq 1 ]; then
			echo "  This check judges every function the turned-in files declare or"
			echo "  define, the helpers of your own included. That the sentence below"
			echo "  covers them too is this harness's reading, never the subject's own"
			echo "  words. The sentence it reads:"
		else
			echo "  The sentence this check applies:"
		fi
		rl_quote restrict | sed 's/^/    /'
		echo ""
		echo "  restrict, __restrict and __restrict__ are one qualifier to the"
		echo "  compiler (it prints all three as restrict), and it can hide in a"
		echo "  typedef a line uses. On a parameter it is no part of the function's"
		echo "  type, so a declaration without it still matches, and no other layer"
		echo "  sees it. Which word in each line above brings it in?"
		exit 1
	fi
	[ "$RC" -eq 0 ] || exit 1
	# By what was judged: the default never states the other reading.
	if [ "$ALL_FN" -eq 1 ]; then
		echo "prototype_check: OK — no prototype in the turned-in files uses restrict."
	else
		echo "prototype_check: OK — no prototype of a function $(basename "$PROTO") declares uses"
		echo "  restrict in the turned-in files."
	fi
	# Where the others are from is not known here: a grader's header, or a
	# file of the student's the call site did not name, that declares a
	# function --proto declares.
	if [ "$_others" -eq 1 ]; then
		echo "  (restrict appears in 1 place in a prototype of a file that is not turned in:"
		echo "  it is not judged here.)"
	elif [ "$_others" -gt 1 ]; then
		echo "  (restrict appears in $_others places in prototypes of files that are not"
		echo "  turned in: they are not judged here.)"
	fi
	exit 0
fi

if [ "$DECLARES" -eq 1 ]; then
	ast_probe
	# Each header alone first: one that does not compile alone is this
	# check's red, and would make the contract's own compile fail too.
	RC=0
	: > "$WORK/have"
	_hdrs=""
	rl_split_on
	for hdr in $HDRS; do
		_hdrs="${_hdrs:+$_hdrs, }$(basename "$hdr")"
		if ! alone "$hdr"; then
			echo "prototype_check: FAIL — $(basename "$hdr") does not compile when a file"
			echo "                 includes it and nothing else. The compiler said:"
			echo ""
			rl_excerpt "$WORK/cc.err" 20 compiler-output.txt "  "
			echo ""
			echo "  That a program including your header, and no other file of yours,"
			echo "  compiles -- as a main an evaluator writes may -- is this harness's"
			echo "  reading, never the subject's own words. The sentence it reads:"
			rl_quote declares | sed 's/^/    /'
			echo ""
			echo "  A program whose first line includes it stops there, before it can"
			echo "  find any declaration. What does the first error above point at?"
			RC=1
			continue
		fi
		read_ast "$WORK/src.ast" "$WORK/one" "$(basename "$hdr")"
		awk -F'\t' '$1 == "N" { print $3 }' "$WORK/one" >> "$WORK/have"
	done
	rl_split_off
	[ "$RC" -eq 0 ] || exit 1
	proto_wanted
	awk 'FILENAME == ARGV[1] { h[$0] = 1; next } !($0 in h)' "$WORK/have" "$WORK/want" > "$WORK/missing"
	_nw=$(wc -l < "$WORK/want" | tr -d ' ')
	if [ -s "$WORK/missing" ]; then
		_nm=$(wc -l < "$WORK/missing" | tr -d ' ')
		echo "prototype_check: FAIL — included on its own, $_hdrs leaves $_nm of"
		echo "                 the $_nw functions undeclared:"
		echo ""
		sed 's/^/    /' "$WORK/missing"
		echo ""
		echo "  That a program including your header, and no other file of yours,"
		echo "  finds every one of them declared there -- as a main an evaluator"
		echo "  writes may -- is this harness's reading, never the subject's own"
		echo "  words. The sentence it reads:"
		rl_quote declares | sed 's/^/    /'
		echo ""
		echo "  A function defined in a .c file is known to another file only"
		echo "  through a declaration it can see. Where would such a program find"
		echo "  the declaration of each name above?"
		exit 1
	fi
	echo "prototype_check: OK — included on its own, $_hdrs declares all $_nw functions."
	exit 0
fi

if [ "$NAMES" -eq 1 ]; then
	# One awk program reads both dumps. A FunctionDecl line and a ParmVarDecl
	# line end the same way -- a location, flags such as "used", the NAME
	# unless there is none, then the type in quotes -- so one function takes
	# the name from either:
	#     FunctionDecl 0x... prev 0x... <file.c:4:1, line:9:1> line:4:6 rush 'void (int, int)'
	#     |-ParmVarDecl 0x... <col:11, col:15> col:15 used x 'int'
	# The range <...> holds no quote and ends at the last "> " before the
	# type, which holds no '>' in C.
	cat > "$WORK/names.awk" <<'NAMES_AWK'
function name_of(line,   t, n, i) {
	sub(/^[^A-Za-z]*[A-Za-z]+Decl 0x[0-9a-f]+ /, "", line)
	sub(/^prev 0x[0-9a-f]+ /, "", line)
	sub(/^<.*> /, "", line)
	n = split(line, t, " ")
	for (i = 2; i <= n; i++) {
		if (t[i] ~ /^'/) return ""
		if (t[i] == "used" || t[i] == "referenced" || t[i] == "implicit" || t[i] == "invalid") continue
		return t[i]
	}
	return ""
}
# mode "proto": every top-level function the prototype file declares, as
# "<name>\t<param> <param>...". A top-level node is "|-X" or "`-X"; its
# children are indented by two more characters.
mode == "proto" && /^[|`]-FunctionDecl / { fn = name_of($0); order[++nf] = fn; ps[fn] = ""; next }
mode == "proto" && /^[|`]-/ { fn = ""; next }
mode == "proto" && fn != "" && /^[| ] [|`]-ParmVarDecl / { ps[fn] = ps[fn] (ps[fn] == "" ? "" : " ") name_of($0); next }
# mode "def": a dump filtered to one name. Each match is a block that opens
# "Dumping <name>:", then the declaration itself unindented and its children
# one level in; a definition is the one with a body (a CompoundStmt child).
mode == "def" && /^Dumping / { take = ($0 == "Dumping " want ":"); fn = ""; next }
mode == "def" && take && /^FunctionDecl / { fn = name_of($0); cur = ""; body = 0; next }
mode == "def" && take && fn == want && /^[|`]-ParmVarDecl / { cur = cur (cur == "" ? "" : " ") name_of($0); next }
mode == "def" && take && fn == want && /^[|`]-CompoundStmt / { found = cur; have = 1; next }
END {
	if (mode == "proto") for (i = 1; i <= nf; i++) printf "%s\t%s\n", order[i], ps[order[i]]
	if (mode == "def" && have) print found
	if (mode == "def" && !have) exit 3
}
NAMES_AWK
	if grep -q '^[[:space:]]*#[[:space:]]*include' "$PROTO"; then
		echo "prototype_check.sh: --names reads $(basename "$PROTO")'s own declarations, and it" >&2
		echo "  includes another file, whose declarations nobody transcribed from the" >&2
		echo "  subject. A names contract includes nothing: it declares the functions" >&2
		echo "  whose parameter names it checks, and declares a type one of them needs" >&2
		echo "  forward (typedef struct s_name t_name;), never by including its header." >&2
		exit 2
	fi
	# shellcheck disable=SC2086
	if ! "$CC" -x c -fsyntax-only -fno-color-diagnostics -Xclang -ast-dump "$PROTO" \
			> "$WORK/proto.ast" 2> "$WORK/cc.err"; then
		echo "prototype_check.sh: the compiler could not read $(basename "$PROTO") (or is not a" >&2
		echo "  clang: --names reads clang's AST dump):" >&2
		rl_excerpt "$WORK/cc.err" 10 compiler-output.txt "  " >&2
		exit 2
	fi
	awk -v mode=proto -f "$WORK/names.awk" "$WORK/proto.ast" > "$WORK/want"
	[ -s "$WORK/want" ] || {
		echo "prototype_check.sh: $(basename "$PROTO") declares no function, so there is no name to check" >&2
		exit 2
	}
	RC=0
	TAB=$(printf '\t')
	# Each source is compiled once, before any function is looked for. One
	# that does not compile is reported here, once, and left out of the
	# search: compiled again for every function, it printed the same excerpt
	# once per name -- twenty times over a library's. A function the sources
	# that compile do not define is then not called missing, since the broken
	# one may define it.
	READ=""
	BROKEN=0
	MISNAMED=0
	rl_split_on
	for src in $SRCS; do
		# shellcheck disable=SC2086
		if "$CC" -fsyntax-only -fno-color-diagnostics $INCS "$src" 2> "$WORK/cc.err"; then
			rl_list_add READ "$src"
			continue
		fi
		echo "prototype_check: FAIL — $(basename "$src") does not compile, so the names of"
		echo "                 its parameters cannot be read. The compile layer says why:"
		echo ""
		rl_excerpt "$WORK/cc.err" 20 compiler-output.txt "  "
		BROKEN=1
		RC=1
	done
	rl_split_off
	# Every function gets its own verdict: the loop used to stop giving any
	# once one had failed, so a second misnamed function said nothing at all.
	while IFS="$TAB" read -r fn want; do
		have=""
		where=""
		rl_split_on
		for src in $READ; do
			# shellcheck disable=SC2086
			if ! "$CC" -fsyntax-only -fno-color-diagnostics $INCS -Xclang -ast-dump \
					-Xclang -ast-dump-filter -Xclang "$fn" "$src" > "$WORK/src.ast" 2> "$WORK/cc.err"; then
				echo "prototype_check.sh: $(basename "$src") compiled, then failed to compile with" >&2
				echo "  -ast-dump, so nothing was checked:" >&2
				rl_excerpt "$WORK/cc.err" 20 compiler-output.txt "  " >&2
				exit 2
			fi
			if got=$(awk -v mode=def -v want="$fn" -f "$WORK/names.awk" "$WORK/src.ast"); then
				have=$got
				where=$(basename "$src")
				break
			fi
		done
		rl_split_off
		if [ -z "$where" ] && [ "$BROKEN" -eq 1 ]; then
			continue
		fi
		if [ -z "$where" ]; then
			echo "prototype_check: FAIL — no file here defines $fn(), so there is no"
			# conventions: the call site's --proto -- the declarations transcribed from the subject
			echo "                 parameter to name. The subject asks for it."
			RC=1
			continue
		fi
		if [ "$have" != "$want" ]; then
			echo "prototype_check: FAIL — $where defines $fn($(printf '%s' "$have" | sed 's/ /, /g')),"
			# conventions: the call site's --names -- set where the call site says the names are fixed
			echo "                 and the subject names its parameters $fn($(printf '%s' "$want" | sed 's/ /, /g'))."
			MISNAMED=1
			RC=1
			continue
		fi
		echo "prototype_check: $where: $fn($(printf '%s' "$want" | sed 's/ /, /g')) -- the subject's names."
	done < "$WORK/want"
	# Said once, after every function's verdict, however many are misnamed.
	if [ "$MISNAMED" -eq 1 ]; then
		echo ""
		# conventions: the call site's --names -- set where the call site says the names are fixed
		echo "  The subject fixes the names as well as the types: the declaration it"
		echo "  prints, with its names, is in $(basename "$PROTO"), which quotes the sentence."
		echo "  A name changes nothing the program does, which is why this sits at"
		echo "  strict: only an evaluator reading your code can mark it."
	fi
	# conventions: the call site's --names -- set where the call site says the names are fixed
	[ "$RC" -eq 0 ] && echo "prototype_check: OK — every parameter is named as the subject names it."
	exit $RC
fi

# What is force-included, in order: the subject's declarations, then each
# header the layout files check, by name (found where the student's file finds
# it), then the subject's structure checked against it, then its names.
# FORCE is a list; HDR is the headers' names, for a message.
FORCE=""
[ -z "$PROTO" ] || rl_list_add FORCE -include "$PROTO"
HDR=""
rl_split_on
for _l in $LAYOUTS $TAGS; do
	_h=$(basename "$_l")
	case " $HDR " in
		*" $_h "*) ;;
		*) HDR="${HDR:+$HDR }$_h"; rl_list_add FORCE -include "$_h" ;;
	esac
done
for _l in $LAYOUTS $TAGS; do
	rl_list_add FORCE -include "$_l"
done
rl_split_off

# The file a signature red names as what it checked against.
_against=$PROTO
# shellcheck disable=SC2086
[ -n "$_against" ] || _against=$(rl_split_on; set -- $LAYOUTS $TAGS; printf '%s' "$1")

# which_failed FILES: the files among FILES the compiler's errors name, one per
# line, each as "    <path>" without a leading ./.
which_failed() {
	for _l in "$@"; do
		grep -qF "$_l" "$WORK/cc.err" && printf '    %s\n' "${_l#./}"
	done
}

# twice: what the compiler's first redefinition says, by fact. Prints
# "guard<TAB>FILE" when the same header was read twice with no guard -- the
# compiler says so ("included multiple times", "unguarded header"), or the
# previous definition is the very line of the very file it found again --
# "twice<TAB>FILE<TAB>PREV" when one name is defined in two places, and
# nothing when there is no redefinition. Each place is "path:line".
twice() {
	awk '
		!e && /: error: .*(redefinition of|redeclaration of|typedef redefinition)/ {
			e = 1
			el = $0
			sub(/: error: .*/, "", el)
			sub(/:[0-9]+$/, "", el)
			next
		}
		e && /(included multiple times|unguarded header)/ {
			print "guard\t" el
			exit
		}
		e && /: note: (previous (definition|declaration)|originally defined here)/ {
			pl = $0
			sub(/: note: .*/, "", pl)
			sub(/:[0-9]+$/, "", pl)
			if (pl == el) print "guard\t" el
			else print "twice\t" el "\t" pl
			exit
		}' "$WORK/cc.err"
}

what_said() {
	echo "  ---------------- what the compiler said ----------------"
	rl_excerpt "$WORK/cc.err" 20 compiler-output.txt "  "
}

RC=0
# The lists are one word per line (runner_lib.sh, LISTS OF WORDS).
rl_split_on
for src in $SRCS; do
	f=$(basename "$src")
	# shellcheck disable=SC2086
	if ! "$CC" -fsyntax-only -Wall -Wextra $INCS "$src" 2> "$WORK/cc.err"; then
		echo "prototype_check: FAIL — $f does not compile on its own, so its"
		echo "                 signature cannot be checked yet."
		echo ""
		echo "  The *_compile_gcc and *_compile_clang layers report the same error"
		echo "  with the flags the grader compiles with; fix it there first, and"
		echo "  this layer checks the signature."
		echo ""
		what_said
		RC=1
		continue
	fi
	# shellcheck disable=SC2086
	"$CC" -fsyntax-only -Wall -Wextra $INCS $FORCE "$src" 2> "$WORK/cc.err" && continue
	RC=1
	_tw=$(twice)
	# shellcheck disable=SC2086
	_lf=$(which_failed $LAYOUTS)
	# shellcheck disable=SC2086
	_tf=$(which_failed $TAGS)
	_twk=$(printf '%s\n' "$_tw" | cut -f1)
	_twf=$(printf '%s\n' "$_tw" | cut -f2)
	_twp=$(printf '%s\n' "$_tw" | cut -f3)
	if [ "$_twk" = guard ]; then
		_twh=${_twf%:*}
		echo "prototype_check: FAIL — ${_twh#./} is read twice in one file,"
		echo "                 and has no include guard."
		echo ""
		echo "  This layer includes your header ahead of $f, as a grader's"
		echo "  own files may, and then $f includes it again. A header whose"
		echo "  contents are not wrapped in #ifndef NAME_H / # define NAME_H /"
		echo "  #endif defines everything a second time. The Norm asks every header"
		echo "  to be protected against double inclusion; which lines below does"
		echo "  the compiler say were defined twice?"
		echo ""
		what_said
	elif [ "$_twk" = twice ]; then
		echo "prototype_check: FAIL — one name is defined in two places: at"
		echo "                 ${_twp#./}, and again at ${_twf#./}."
		echo ""
		echo "  This layer reads the subject's declarations, and the header they"
		echo "  are written against, ahead of $f -- as any file that includes"
		echo "  that header does. A definition a header holds is shared by"
		echo "  including the header; written out a second time where the header"
		echo "  is also read, it is defined twice. Which of the two places is the"
		# conventions: the call site's --proto -- the declarations transcribed from the subject
		echo "  one the subject asks for?"
		echo ""
		what_said
	elif [ -n "$_lf" ]; then
		echo "prototype_check: FAIL — the structure in your $HDR is not the one"
		# conventions: the call site's --layout -- the structure transcribed from the subject
		echo "                 the subject prints."
		echo ""
		# conventions: the call site's --layout -- the structure transcribed from the subject
		echo "  The subject gives the structure your header must hold, field for"
		echo "  field, and the grader's own code is built on it. A field retyped,"
		echo "  reordered, added or removed changes where each one sits in memory,"
		echo "  so your code and the grader's read each other's data wrong."
		echo "  Each check it failed says which field, and they are all in"
		echo "$_lf"
		echo "  beside the subject's own typedef: compare yours with it."
		echo ""
		what_said
	elif [ -n "$_tf" ]; then
		# conventions: the call site's --layout-tag -- the names transcribed from the subject
		echo "prototype_check: FAIL — your $HDR does not name its structure as the"
		echo "                 subject prints it."
		echo ""
		# conventions: the call site's --layout-tag -- the names transcribed from the subject
		echo "  The subject prints the structure's tag (the name after \`struct\`)"
		echo "  and the type of each field that points to another node. Code"
		echo "  written against the subject's header names the structure that way"
		echo "  -- the grader's own tests may -- and does not compile against a"
		echo "  header that names it otherwise, however its fields are laid out."
		echo "  Each check it failed says which name, and they are all in"
		echo "$_tf"
		echo "  Compare them with your typedef."
		echo ""
		what_said
	else
		echo "prototype_check: FAIL — $f does not match the signature"
		# conventions: the call site's --proto -- the declarations transcribed from the subject
		echo "                 the subject specifies."
		echo ""
		# conventions: the call site's --proto -- the declarations transcribed from the subject
		echo "  The subject fixes each function's return type and parameter list."
		echo "  C has no name mangling, so a different signature still LINKS: the"
		echo "  harness declares one shape, your file defines another, and the"
		echo "  only symptom is wrong values. Compiling both together turns that"
		echo "  into the error below. The declaration it is checking against is"
		echo "  in $(basename "$_against")."
		echo ""
		what_said
	fi
done
rl_split_off

if [ "$RC" -ne 0 ] && [ -n "$GRADER_HDRS" ]; then
	rl_split_on
	# shellcheck disable=SC2086
	rl_grader_hdrs "$README" "$SRCS" $GRADER_HDRS
	rl_split_off
fi
if [ "$RC" -eq 0 ]; then
	if [ -n "$PROTO" ] && [ -n "$HDR" ]; then
		echo "prototype_check: OK — signatures match the subject, and $HDR holds its structure."
	elif [ -n "$PROTO" ]; then
		echo "prototype_check: OK — signatures match the subject."
	else
		# conventions: the call site's --layout -- the structure transcribed from the subject
		echo "prototype_check: OK — $HDR holds the structure the subject prints."
	fi
fi
exit $RC
