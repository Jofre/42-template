#!/bin/sh
# The Norm's header rules the pinned norminette does not check (tag "norm",
# target exNN_norm_header, at strict).
#
# The Norm (en.norm.pdf, version 4.1) says, in III.5, "Header files must be
# protected from double inclusions", and in III.1, "A structure's name must
# start by s_.", "A union's name must start by u_." and "An enum's name must
# start by e_.". The norminette campus runs (3.3.58, pinned here) checks the
# first only where a header already has a guard -- its name, its #define --
# and says nothing at all about a header with none (finding 093); and it
# checks the second only for a name declared OUTSIDE a typedef, so the tag in
# `typedef struct <tag> { ... } t_x;` is never read (finding 089). The norm
# layer's OK therefore says "norminette found no violation", never "the Norm
# is satisfied", and this runner checks the two rules it skips, in every
# header a project turns in (tools/defs.bzl's c_levels() emits one test per
# exercise that turns one in, read from the subject() contract, so a new
# project gets it without a line of its own).
#
# STRICT, not basic: the Norm requires both, but the grader runs norminette,
# which raises neither, so only an evaluator reading the file marks them --
# "real, but not certain" (docs/reference.md, "The four levels").
#
# EACH VERDICT IS BY CONSTRUCTION, never by reading the text for a pattern:
#
#   included twice
#               the pinned clang preprocesses a file that includes the header
#               once and one that includes it twice (-E -P -dD: every line it
#               gives, every #define it keeps), and compares the two with the
#               blank lines left out. Different, it was read twice -- which
#               catches a header of prototypes alone and one of #defines
#               alone, where a compile that includes it twice says nothing.
#               Equal, the second #include added nothing, and that is ALL the
#               OK says: "safe to include twice", never "protected". A guard
#               or #pragma once makes it so; so does a header with nothing a
#               second reading could repeat (empty, comments alone, or only
#               #includes of headers that are themselves guarded), which
#               passes guard or no guard -- an evaluator may still ask for
#               one, and no output can.
#   the prefix  the pinned clang lists the header's tokens as the
#               preprocessor gives them (-Xclang -dump-tokens: comments gone,
#               macros expanded), and each `struct`, `union` or `enum` DEFINED
#               inside a typedef -- `typedef`, the keyword (with `const` or
#               `volatile` before it), a name, then `{` -- has that name read
#               against its prefix. An anonymous one has no name to read. A
#               typedef that only names one defines nothing to read: `typedef
#               struct timeval t_tv;` names libc's, which no student can
#               rename, and `typedef struct x t_x;` names one defined
#               elsewhere, whose name norminette reads where it is defined
#               (STRUCT_TYPE_NAMING and its siblings, for a struct, union or
#               enum defined outside a typedef). Those are the norm layer's,
#               so one name is never two reds.
#
# WHAT IT NEVER PRINTS: the text of a guard, or which lines the second
# #include added -- a broken guard's own #define is one of them -- or a name a
# tag should have. It says which rule, quotes the Norm, and asks a question;
# the exercise's clues say the rest (docs/design.md, "Feedback names the bug
# class, never the algorithm").
#
# A header the preprocessor stops on (an #include that reaches no file, an
# #error) cannot be read either way, and that is a red of its own, never a
# pass: the compile layers say why in the compiler's words.
#
# Usage:
#   header_norm.sh --cc PATH [--cc-lib FILE]... --header FILE...
#                  [--grader-hdr FILE]...
#
#   --cc          the pinned clang (tools/defs.bzl's _pinned_cc_args)
#   --cc-lib      a library it loads; its directory goes first on the loader's
#                 path (runner_lib.sh's rl_cc_pin)
#   --header      a header the project turns in: read by both rules, and its
#                 folder put on the include path, wherever it sits
#   --grader-hdr  a header the grader brings, which a turned-in one may
#                 include: its folder on the include path, never read
#
# THE INCLUDE PATH is generous on purpose: every turned-in header's folder,
# subfolders included, and the grader's. Whether the grader's compile line
# reaches a header is the compile layers' question (tools/defs.bzl's
# _inc_args); this one asks what a header says once it is reached, and a
# header that includes a neighbour by name must not read as unreadable here
# because of where the neighbour sits.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "header_norm.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cmp dirname mktemp rm wc

# The shared runner helpers -- traps, excerpts, the fetched compiler's proof
# (rl_cc_pin), lists of words -- written once in tools/runner_lib.sh.
RL_NAME=header_norm
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "header_norm.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# conventions: runs no student code -- it preprocesses the headers and runs nothing it builds
# conventions: harness tool CC -- the pinned clang: it preprocesses and lists tokens, and runs none of what it reads

CC=""
CC_LIBS=""
HDRS=""
INCS=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "header_norm.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--cc) need "$1" "$#"; CC="$2"; shift 2 ;;
		--cc-lib) need "$1" "$#"; rl_list_add CC_LIBS "$2"; shift 2 ;;
		--header) need "$1" "$#"; rl_list_add HDRS "$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--grader-hdr) need "$1" "$#"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		*) echo "header_norm.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$CC" ] || { echo "header_norm.sh: --cc is required (the pinned clang)" >&2; exit 2; }
[ -n "$HDRS" ] || { echo "header_norm.sh: at least one --header is required" >&2; exit 2; }
rl_cc_pin "$CC" "$CC_LIBS" ""

WORK=$(mktemp -d) || { echo "header_norm.sh: cannot create a scratch directory" >&2; exit 2; }
rl_traps 'rm -rf "$WORK"'

# The token list's reading of the names after `typedef`: one line per
# struct, union or enum DEFINED there -- `typedef`, the keyword, a name, and
# then `{` -- as "LINE KEYWORD NAME VERDICT", VERDICT ok or bad. A typedef that
# only names one (`typedef struct timeval t_tv;`, or the type of a struct
# defined elsewhere) defines nothing here: the name is libc's, or norminette
# reads it where the struct is defined. FILE is the header exactly as it was
# handed to clang, which is how clang names it in each Loc=<...>.
read_tags() {  # read_tags FILE TOKENS
	awk -v f="$1" '
		{
			i = index($0, "Loc=<")
			if (i == 0) next
			loc = substr($0, i + 5)
			if (substr(loc, 1, length(f) + 1) != f ":") next
			rest = substr(loc, length(f) + 2)
			split(rest, lc, ":")
			line = lc[1] + 0
			kind = $1
			text = ""
			q = index($0, "\047")
			if (q > 0) {
				t = substr($0, q + 1)
				e = index(t, "\047")
				if (e > 0) text = substr(t, 1, e - 1)
			}
			if (st == 3) {
				if (kind == "l_brace") {
					want = (kw == "struct") ? "s_" : (kw == "union") ? "u_" : "e_"
					v = (substr(tag, 1, 2) == want) ? "ok" : "bad"
					print kwline, kw, tag, v
				}
				st = 0
				next
			}
			if (st == 2) {
				if (kind == "identifier") {
					st = 3; tag = text
					next
				}
				st = 0
				next
			}
			if (st == 1) {
				if (kind == "const" || kind == "volatile") next
				if (kind == "struct" || kind == "union" || kind == "enum") {
					st = 2; kw = kind; kwline = line
					next
				}
				st = 0
			}
			if (kind == "typedef") st = 1
		}' "$2"
}

# The Norm's sentence for a keyword, from III.1.
norm_rule() {
	case "$1" in
		struct) echo "A structure's name must start by s_." ;;
		union) echo "A union's name must start by u_." ;;
		*) echo "An enum's name must start by e_." ;;
	esac
}

N=0
BAD=0
OKLINES=""
rl_split_on
# shellcheck disable=SC2086 # the lists split into their lines (THE LISTS)
for H in $HDRS; do
	rl_split_off
	N=$((N + 1))
	case "$H" in /*) AH=$H ;; *) AH="$PWD/$H" ;; esac
	if [ ! -f "$AH" ]; then
		echo "header_norm.sh: --header '$H' is not a file" >&2
		exit 2
	fi
	printf '#include "%s"\n' "$AH" > "$WORK/one.c"
	printf '#include "%s"\n#include "%s"\n' "$AH" "$AH" > "$WORK/two.c"
	rl_split_on
	# shellcheck disable=SC2086
	"$CC" -E -P -dD -x c $INCS "$WORK/one.c" > "$WORK/one.i" 2> "$WORK/one.err"
	_r1=$?
	# shellcheck disable=SC2086
	"$CC" -E -P -dD -x c $INCS "$WORK/two.c" > "$WORK/two.i" 2> "$WORK/two.err"
	_r2=$?
	rl_split_off
	if [ "$_r1" -ne 0 ] || [ "$_r2" -ne 0 ]; then
		BAD=$((BAD + 1))
		echo "header_norm: FAIL — $H could not be read: the preprocessor stopped on it,"
		echo "  so neither of the two rules this check reads could be read for it:"
		rl_excerpt "$WORK/one.err" 12 preprocessor-output.txt "    "
		echo "  The compile layers name the same problem in the files that include it."
		echo ""
		rl_split_on
		continue
	fi
	awk 'NF' "$WORK/one.i" > "$WORK/one.n"
	awk 'NF' "$WORK/two.i" > "$WORK/two.n"
	_said=""
	if ! cmp -s "$WORK/one.n" "$WORK/two.n"; then
		BAD=$((BAD + 1))
		_extra=$(( $(wc -l < "$WORK/two.n") - $(wc -l < "$WORK/one.n") ))
		echo "header_norm: FAIL — $H is not protected from double inclusions."
		echo "  Included twice in one file, it gives $_extra more line(s) than included"
		echo "  once: nothing stops the preprocessor from reading it a second time."
		echo "  The Norm, III.5: \"Header files must be protected from double inclusions.\""
		echo "  norminette says nothing about a header that has no such protection, so"
		echo "  only this check, and an evaluator reading the file, will see it."
		echo "  What happens when two files of one program both #include a header, and"
		echo "  what can the header itself say so that a second #include adds nothing?"
		echo ""
		_said=1
	fi
	rl_split_on
	# shellcheck disable=SC2086
	"$CC" -fsyntax-only -Xclang -dump-tokens -x c $INCS "$AH" > /dev/null 2> "$WORK/tokens.txt"
	_rt=$?
	rl_split_off
	if [ "$_rt" -ne 0 ]; then
		BAD=$((BAD + 1))
		echo "header_norm: FAIL — $H could not be read token by token:"
		rl_excerpt "$WORK/tokens.txt" 12 tokens-output.txt "    "
		echo ""
		rl_split_on
		continue
	fi
	read_tags "$AH" "$WORK/tokens.txt" > "$WORK/tags.txt"
	_names=$(awk 'END { print NR }' "$WORK/tags.txt")
	while read -r _line _kw _tag _v; do
		[ "$_v" = bad ] || continue
		BAD=$((BAD + 1))
		_said=1
		echo "header_norm: FAIL — $H, line $_line: the $_kw defined inside the typedef"
		echo "  there is named \"$_tag\"."
		echo "  The Norm, III.1: \"$(norm_rule "$_kw")\""
		echo "  norminette reads that name only for a $_kw defined outside a typedef,"
		echo "  so it passed this one. Which part of that line names the $_kw itself,"
		echo "  and which names the type the typedef makes?"
		echo ""
	done < "$WORK/tags.txt"
	[ -n "$_said" ] || OKLINES="$OKLINES  $H: safe to include twice (included twice, it gives the same lines as once); $_names struct, union or enum name(s) defined inside a typedef, each with the Norm's prefix$RL_NL"
	rl_split_on
done
rl_split_off

if [ "$BAD" -gt 0 ]; then
	echo "header_norm: $BAD finding(s) in $N header(s), read as the pinned ${CC##*/} reads them."
	[ -z "$OKLINES" ] || printf 'The other headers:\n%s' "$OKLINES"
	exit 1
fi
echo "header_norm: OK — $N header(s), read as the pinned ${CC##*/} reads them:"
printf '%s' "$OKLINES"
echo "  These are the two rules of the Norm (III.5 and III.1) that norminette does"
echo "  not check here; the norm layer checks the rest."
exit 0
