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
# Usage:
#   prototype_check.sh [--proto FILE] [--layout FILE]... [--layout-tag FILE]...
#                      --src FILE [--src FILE]...
#                      [--inc DIR]... [--grader-hdr FILE [--readme PATH]]...
#                      [--cc NAME] [--names]
#   (at least one of --proto, --layout and --layout-tag; --names takes --proto
#   alone)
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
require awk basename cat cut dirname grep mktemp rm sed

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
		--grader-hdr) need "$1" "$#"; rl_list_add INCS "-I$(_dir "$2")"; rl_list_add GRADER_HDRS "$2"; shift 2 ;;
		--readme) need "$1" "$#"; README="$2"; shift 2 ;;
		--src) need "$1" "$#"; rl_list_add SRCS "$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--inc) need "$1" "$#"; rl_list_add INCS "-I$(_dir "$2")"; shift 2 ;;
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

[ -n "$PROTO$LAYOUTS$TAGS" ] && [ -n "$SRCS" ] || {
	echo "prototype_check.sh: need --proto, --layout or --layout-tag, and at least one --src" >&2
	exit 2
}
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

WORK=$(mktemp -d)
rl_traps 'rm -rf "$WORK"'

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
		echo "  subject. A names contract includes nothing." >&2
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
	while IFS="$TAB" read -r fn want; do
		have=""
		where=""
		rl_split_on
		for src in $SRCS; do
			# shellcheck disable=SC2086
			if ! "$CC" -fsyntax-only -fno-color-diagnostics $INCS -Xclang -ast-dump \
					-Xclang -ast-dump-filter -Xclang "$fn" "$src" > "$WORK/src.ast" 2> "$WORK/cc.err"; then
				echo "prototype_check: FAIL — $(basename "$src") does not compile, so the names of"
				echo "                 its parameters cannot be read. The compile layer says why:"
				echo ""
				rl_excerpt "$WORK/cc.err" 20 compiler-output.txt "  "
				RC=1
				continue
			fi
			if got=$(awk -v mode=def -v want="$fn" -f "$WORK/names.awk" "$WORK/src.ast"); then
				have=$got
				where=$(basename "$src")
				break
			fi
		done
		rl_split_off
		[ "$RC" -eq 0 ] || continue
		if [ -z "$where" ]; then
			echo "prototype_check: FAIL — no file here defines $fn(), so there is no"
			echo "                 parameter to name. The subject asks for it."
			RC=1
			continue
		fi
		if [ "$have" != "$want" ]; then
			echo "prototype_check: FAIL — $where defines $fn($(printf '%s' "$have" | sed 's/ /, /g')),"
			echo "                 and the subject names its parameters $fn($(printf '%s' "$want" | sed 's/ /, /g'))."
			echo ""
			echo "  The subject fixes the names as well as the types: the declaration it"
			echo "  prints, with its names, is in $(basename "$PROTO"), which quotes the sentence."
			echo "  A name changes nothing the program does, which is why this sits at"
			echo "  strict: only an evaluator reading your code can mark it."
			RC=1
			continue
		fi
		echo "prototype_check: $where: $fn($(printf '%s' "$want" | sed 's/ /, /g')) -- the subject's names."
	done < "$WORK/want"
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
		echo "  The *_compile_* layers report the same error with the flags the"
		echo "  grader compiles with; fix it there first, and this layer checks"
		echo "  the signature."
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
		echo "  one the subject asks for?"
		echo ""
		what_said
	elif [ -n "$_lf" ]; then
		echo "prototype_check: FAIL — the structure in your $HDR is not the one"
		echo "                 the subject prints."
		echo ""
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
		echo "prototype_check: FAIL — your $HDR does not name its structure as the"
		echo "                 subject prints it."
		echo ""
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
		echo "                 the subject specifies."
		echo ""
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
		echo "prototype_check: OK — $HDR holds the structure the subject prints."
	fi
fi
exit $RC
