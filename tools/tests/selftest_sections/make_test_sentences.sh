# ------------------------------------------------------------------ make_test sentences
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# What a Makefile check applies is a sentence of THE PROJECT'S OWN subject,
# quoted at the call site (--quotes), and a check nobody can quote is refused
# (finding 082: C 09's definitions were quoted at every project). The
# compile commands, every command printed, one touched source rebuilding one
# object, and "Watch out for wildcards!" (findings 097-099, 101, 105) read
# what make ran or planned, never the Makefile's text.
#
# The fixtures compile with a stand-in: bin/cc and bin/gcc copy their input
# operands, end to end, to their -o operand (to stdout without one, as
# `cc -MM` prints), so a planned compile reads as one, no real toolchain
# runs, and nothing here is shaped like an exercise's Makefile -- two sources
# named sel_a and sel_b, and a "library" that is their text. An input with an
# #error line stops it with the compiler's own words for one, FILE:LINE:COL:
# error, which is what the wildcards decoy is.
#
# Its fixtures are its own, beside make_test's rather than in them: MKQ names
# a folder of this section's from here on (mkr reads it), holding the toy
# definitions of the rules and the --graph sentences again, and mksecho the
# Makefile whose recipe only echoes.
MKQ="$WORK/mksentences"
mkdir -p "$MKQ" "$WORK/mksecho"
{
	printf 'print\tToy, p.1: "Print every command."\n'
	printf 'unnecessary\tToy, p.1: "Redo nothing that is done."\n'
	printf 'objects\tToy, p.1: "Each object beside its source."\n'
} > "$MKQ/graph.tsv"
{
	printf 'all\tToy, p.2: "all builds the library."\n'
	printf 'clean\tToy, p.2: "clean removes what the build made on the way."\n'
	printf 'fclean\tToy, p.2: "fclean is clean, and the library too."\n'
	printf 're\tToy, p.2: "re is fclean, then all."\n'
} > "$MKQ/rules.tsv"
printf 'all:\n\techo selftest stub\n' > "$WORK/mksecho/Makefile"
{
	printf 'cc\tToy, p.3: "Compile with cc and -Wall -Wextra -Werror."\n'
	printf 'wildcards\tToy, p.3: "Name every file; our files sit beside yours."\n'
} > "$MKQ/cc.tsv"
cat "$MKQ/graph.tsv" "$MKQ/cc.tsv" > "$MKQ/graphcc.tsv"
cat "$MKQ/cc.tsv" "$MKQ/rules.tsv" > "$MKQ/ccrules.tsv"
mkfake() {  # mkfake DIR: DIR/bin/cc and DIR/bin/gcc, and two sources
	mkdir -p "$WORK/$1/bin"
	for _c in cc gcc; do
		printf '%s\n' '#!/bin/sh' \
			'# The selftest'"'"'s stand-in compiler: its operands, end to end, into -o.' \
			'_o=""' '_i=""' \
			'while [ $# -gt 0 ]; do' \
			'	case "$1" in' \
			'		-o) _o=$2; shift 2 ;;' \
			'		-*) shift ;;' \
			'		*) _i="$_i $1"; shift ;;' \
			'	esac' \
			'done' \
			'# shellcheck disable=SC2086' \
			'for _f in $_i; do' \
			'	_l=$(grep -n "^#error" "$_f" 2> /dev/null | cut -d: -f1 | head -n 1)' \
			'	[ -z "$_l" ] || { echo "$_f:$_l:2: error: #error" >&2; exit 1; }' \
			'done' \
			'# shellcheck disable=SC2086' \
			'if [ -n "$_o" ]; then cat $_i > "$_o"; else cat $_i; fi' > "$WORK/$1/bin/$_c"
		chmod +x "$WORK/$1/bin/$_c"
	done
	printf 'selftest a\n' > "$WORK/$1/sel_a.c"
	printf 'selftest b\n' > "$WORK/$1/sel_b.c"
}
# mkcc DIR FLAGS-A COMPILER-B FLAGS-B HEAD: a Makefile that compiles sel_a.c
# with $(A) and FLAGS-A, sel_b.c with ./bin/COMPILER-B and FLAGS-B, links
# the two with ./bin/cc and no flag at all (a link compiles nothing, so no
# sentence about compiling reaches it), and prints a line that only NAMES a
# compile. HEAD goes first in the file.
mkcc() {
	mkfake "$1"
	{
		printf '%b' "$5"
		printf 'all: libselftest.a\n'
		printf 'libselftest.a: sel_a.o sel_b.o\n\t./bin/cc -o libselftest.a sel_a.o sel_b.o\n'
		printf '\techo "gcc -c sel_a.c is not run"\n'
		printf 'sel_a.o: sel_a.c\n\t$(A) %s -c sel_a.c -o sel_a.o\n' "$2"
		printf 'sel_b.o: sel_b.c\n\t./bin/%s %s -c sel_b.c -o sel_b.o\n' "$3" "$4"
	} > "$WORK/$1/Makefile"
}
# The flags through a variable, as `make -n` expands them: the plan is read,
# not the file.
_mkh='A = ./bin/cc\nF = -Wall -Wextra -Werror\n'
mkcc mkrc_ok '$(F)' cc '-Wall -Wextra -Werror' "$_mkh"
mkcc mkrc_gcc '$(F)' gcc '-Wall -Wextra -Werror' "$_mkh"
mkcc mkrc_noerr '$(F)' cc '-Wall -Wextra' "$_mkh"
mkcc mkrc_order '$(F)' cc '-Werror -Wall -Wextra' "$_mkh"
mkcc mkrc_xcc '$(F)' cc '-Wall -Wextra -Werror' 'A = ./bin/xcc\nF = -Wall -Wextra -Werror\n'
mkcc mkrc_gccbare '$(F)' gcc '' "$_mkh"
cp "$WORK/mkrc_xcc/bin/cc" "$WORK/mkrc_xcc/bin/xcc"
mkrc() {  # mkrc DIR any|ordered [FLAG...]: the compile commands, no rule
	_d=$1
	_o=$2
	shift 2
	mt --rules "" --recipe-cc "$_o" --quotes "$MKQ/cc.tsv" --build-target selftest_build \
		"$@" --anchor "$WORK/$_d/Makefile" --artifact libselftest.a
}
want_green "make_test --recipe-cc: every compile runs cc and the flags" -- mkrc mkrc_ok any
want_out   "make_test --recipe-cc: ...and says how many it judged" \
	'each of the 2 compile commands a bare' -- mkrc mkrc_ok any
want_red   "make_test --recipe-cc: one compile with gcc fails" -- mkrc mkrc_gcc any
want_out   "make_test --recipe-cc: ...naming the compiler it found" 'gcc, not cc' -- \
	mkrc mkrc_gcc any
want_out   "make_test --recipe-cc: ...one of the two, not any" \
	'1 of the 2 compile command(s)' -- mkrc mkrc_gcc any
want_out   "make_test --recipe-cc: ...quoting the call site's sentence" \
	'Toy, p.3: "Compile with cc and -Wall -Wextra -Werror."' -- mkrc mkrc_gcc any
# Every fault of one command, not the first: a gcc with no flags was marked
# "(gcc, not cc)" alone, and the flags came on the next red run (the
# mutation run of 2026-10-03).
want_out   "make_test --recipe-cc: a gcc with no flags is named for both" \
	'(gcc, not cc; no -Wall -Wextra -Werror)' -- mkrc mkrc_gccbare any
want_red   "make_test --recipe-cc: a name that ends in cc is not cc" -- mkrc mkrc_xcc any
want_out   "make_test --recipe-cc: ...and is named" 'xcc, not cc' -- mkrc mkrc_xcc any
want_red   "make_test --recipe-cc: a compile without -Werror fails" -- mkrc mkrc_noerr any
want_out   "make_test --recipe-cc: ...saying which flag" '(no -Werror)' -- mkrc mkrc_noerr any
want_green "make_test --recipe-cc any: the flags in any order" -- mkrc mkrc_order any
want_red   "make_test --recipe-cc ordered: ...not where it says in that order" -- \
	mkrc mkrc_order ordered
want_out   "make_test --recipe-cc ordered: ...and says so" 'out of that order' -- \
	mkrc mkrc_order ordered
# A compile split over two recipe lines with a backslash: `make -n` prints it
# as written, two lines, and the second was once read as a command of its own
# ("-c, not cc"). One logical line, judged once, and printed on one line.
# One explicit rule per object, as every fixture here writes them.
for _s in split:-Werror split_bad:; do
	mkfake "mkrc_${_s%%:*}"
	{
		printf 'all: libselftest.a\nlibselftest.a: sel_a.o sel_b.o\n\t./bin/cc -o libselftest.a sel_a.o sel_b.o\n'
		for _o in sel_a sel_b; do
			printf '%s.o: %s.c\n\t./bin/cc -Wall -Wextra %s \\\n\t\t-c %s.c -o %s.o\n' \
				"$_o" "$_o" "${_s#*:}" "$_o" "$_o"
		done
	} > "$WORK/mkrc_${_s%%:*}/Makefile"
done
want_green "make_test --recipe-cc: a compile split by a backslash is one command" -- \
	mkrc mkrc_split ordered
want_red   "make_test --recipe-cc: ...whose flags are judged whole" -- mkrc mkrc_split_bad ordered
want_out   "make_test --recipe-cc: ...and printed on one line" \
	'./bin/cc -Wall -Wextra -c sel_a.c -o sel_a.o' -- mkrc mkrc_split_bad ordered
# A command that only runs another is looked through to it: env (and its
# assignments), and `sh -c STRING`, whose STRING is a command line. Both
# were once tools that compile nothing, so gcc behind them was not judged.
mkwrap() {  # mkwrap DIR RECIPE: sel_b.o compiled by RECIPE
	mkfake "$1"
	{
		printf 'all: libselftest.a\nlibselftest.a: sel_a.o sel_b.o\n'
		printf '\t./bin/cc -o libselftest.a sel_a.o sel_b.o\n'
		printf 'sel_a.o: sel_a.c\n\t./bin/cc -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n'
		printf 'sel_b.o: sel_b.c\n\t%s\n' "$2"
	} > "$WORK/$1/Makefile"
}
mkwrap mkrc_env 'env -u LC_ALL ./bin/gcc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o'
mkwrap mkrc_shc "sh -c './bin/gcc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o'"
mkwrap mkrc_envok 'env LC_ALL=C ./bin/cc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o'
want_red   "make_test --recipe-cc: gcc behind env fails" -- mkrc mkrc_env any
want_out   "make_test --recipe-cc: ...named" 'gcc, not cc' -- mkrc mkrc_env any
want_red   "make_test --recipe-cc: gcc in sh -c fails" -- mkrc mkrc_shc any
want_out   "make_test --recipe-cc: ...named" 'gcc, not cc' -- mkrc mkrc_shc any
want_green "make_test --recipe-cc: cc behind env and an assignment passes" -- mkrc mkrc_envok any
want_out   "make_test --recipe-cc: ...judged with the rest" \
	'each of the 2 compile commands' -- mkrc mkrc_envok any
# Only a compiler's command is judged. Every command that named a .c used to
# be, unless its word was on a list of tools that compile nothing, and a tool
# missing from that list -- wc, or the text a recipe's $(info) prints -- was
# failed as "another compiler" on a Makefile that compiles with cc and the
# flags. A compiler's name is a closed shape, and a versioned one is in it.
mkrcx() {  # mkrcx DIR EXTRA-A EXTRA-B: both compiles right, and a line more each
	mkfake "$1"
	{
		printf 'all: libselftest.a\nlibselftest.a: sel_a.o sel_b.o\n'
		printf '\t./bin/cc -o libselftest.a sel_a.o sel_b.o\n'
		printf 'sel_a.o: sel_a.c\n\t%s\n\t./bin/cc -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n' "$2"
		printf 'sel_b.o: sel_b.c\n\t%s\n\t./bin/cc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n' "$3"
	} > "$WORK/$1/Makefile"
}
mkrcx mkrc_info '$(info building sel_a.c)' '$(info building sel_b.c)'
mkrcx mkrc_wc 'wc -c sel_a.c > /dev/null' '@wc -c sel_b.c > /dev/null'
want_green "make_test --recipe-cc: what \$(info) prints, naming a .c, is no compile" -- \
	mkrc mkrc_info any
want_green "make_test --recipe-cc: nor is a tool that is no compiler (wc)" -- mkrc mkrc_wc any
want_out   "make_test --recipe-cc: ...and the compiles are judged all the same" \
	'each of the 2 compile commands' -- mkrc mkrc_wc any
mkwrap mkrc_gccv './bin/gcc-12 -Wall -Wextra -Werror -c sel_b.c -o sel_b.o'
cp "$WORK/mkrc_gccv/bin/gcc" "$WORK/mkrc_gccv/bin/gcc-12"
want_red   "make_test --recipe-cc: a versioned gcc is a compiler too" -- mkrc mkrc_gccv any
want_out   "make_test --recipe-cc: ...and is named" 'gcc-12, not cc' -- mkrc mkrc_gccv any
# A compiler that only preprocesses or prints a dependency rule (-E, -M,
# -MM) names every .c and compiles none: a classic `.depend` rule, `cc -MM
# $(SRCS) > .depend`, was failed as a compile with "no -Wall -Wextra -Werror"
# beside two right ones. -MMD on a compile is a compile, and judged.
mkdep() {  # mkdep DIR FLAGS-A COMPILER-B FLAGS-B: a .depend rule, and two compiles
	mkfake "$1"
	{
		printf 'S = sel_a.c sel_b.c\nall: libselftest.a\n'
		printf 'libselftest.a: .depend sel_a.o sel_b.o\n\t./bin/cc -o libselftest.a sel_a.o sel_b.o\n'
		printf '.depend: $(S)\n\t./bin/cc -MM $(S) > .depend\n'
		printf 'sel_a.o: sel_a.c\n\t./bin/cc %s -c sel_a.c -o sel_a.o\n' "$2"
		printf 'sel_b.o: sel_b.c\n\t./bin/%s %s -c sel_b.c -o sel_b.o\n' "$3" "$4"
	} > "$WORK/$1/Makefile"
}
mkdep mkrc_dep '-Wall -Wextra -Werror' cc '-Wall -Wextra -Werror'
mkdep mkrc_dep_gcc '-Wall -Wextra -Werror' gcc '-Wall -Wextra -Werror'
mkdep mkrc_depmd '-Wall -Wextra -Werror -MMD -MP' cc '-MMD -MP'
want_green "make_test --recipe-cc: a cc -MM dependency rule is no compile" -- mkrc mkrc_dep any
want_out   "make_test --recipe-cc: ...and is not counted" \
	'each of the 2 compile commands' -- mkrc mkrc_dep any
want_red   "make_test --recipe-cc: ...while gcc on a real compile beside it fails" -- \
	mkrc mkrc_dep_gcc any
want_out   "make_test --recipe-cc: ...one of the two compiles, the rule not among them" \
	'1 of the 2 compile command(s)' -- mkrc mkrc_dep_gcc any
want_red   "make_test --recipe-cc: -MMD rides on a compile, which is judged" -- \
	mkrc mkrc_depmd any
want_out   "make_test --recipe-cc: ...and its flags read" '(no -Wall -Wextra -Werror)' -- \
	mkrc mkrc_depmd any
# A compile in a shell loop names its .c only once the shell expands it, so
# `make -n` prints the loop and no compile, and gcc in one passed unseen. A
# build of a copy of the tree, with a stand-in for each compiler first on
# PATH, logs what it ran; a compile the plan shows too is counted once,
# matched by its words -- quoted ones included. The fixture's bin/ goes first
# on PATH, so its stand-ins are the compilers found by name.
for _s in loop:gcc loop_ok:cc; do
	mkfake "mkrc_${_s%%:*}"
	{
		printf 'all: libselftest.a\nlibselftest.a: sel_a.c sel_b.c\n'
		printf '\tfor s in sel_a sel_b; do %s -Wall -Wextra -Werror -c $$s.c -o $$s.o; done\n' "${_s#*:}"
		printf '\tcat sel_a.o sel_b.o > libselftest.a\n'
	} > "$WORK/mkrc_${_s%%:*}/Makefile"
done
mkfake mkrc_named
{
	printf 'all: libselftest.a\nlibselftest.a: sel_a.o sel_b.o\n\tcat sel_a.o sel_b.o > libselftest.a\n'
	printf 'sel_a.o: sel_a.c\n\tcc -Wall -Wextra -Werror -DSEL=\047"a b"\047 -c sel_a.c -o sel_a.o\n'
	printf 'sel_b.o: sel_b.c\n\tcc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n'
} > "$WORK/mkrc_named/Makefile"
mkrl() {  # mkrl DIR [FLAG...]: mkrc DIR any, with DIR/bin first on PATH
	_d=$1
	shift
	once env PATH="$WORK/$_d/bin:$PATH" "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" \
		--recipe-cc any --quotes "$MKQ/cc.tsv" --build-target selftest_build "$@" \
		--anchor "$WORK/$_d/Makefile" --artifact libselftest.a
}
want_red   "make_test --recipe-cc: gcc in a shell loop fails" -- mkrl mkrc_loop
want_out   "make_test --recipe-cc: ...named" 'gcc, not cc' -- mkrl mkrc_loop
want_out   "make_test --recipe-cc: ...and said to be out of make -n's plan" \
	"compile command(s) a bare 'make' ran are not in what" -- mkrl mkrc_loop
want_red   "make_test --recipe-only: ...and at strict too" -- mkrl mkrc_loop --recipe-only
want_green "make_test --recipe-cc: cc in a shell loop passes" -- mkrl mkrc_loop_ok
want_out   "make_test --recipe-cc: ...each turn counted" \
	'each of the 2 compile commands' -- mkrl mkrc_loop_ok
want_green "make_test --recipe-cc: a compile both records show passes" -- mkrl mkrc_named
want_out   "make_test --recipe-cc: ...counted once, quoted words and all" \
	'each of the 2 compile commands' -- mkrl mkrc_named
want_broken_none "make_test --recipe-cc: ...and none is out of the plan" \
	'are not in what' -- mkrl mkrc_named
# A redirection is the shell's, never the compiler's: the plan printed `cc
# ... 2> errs.log`, the stand-in logged the compiler's words alone, and the
# one compile was counted twice, once said to be out of the plan.
for _s in redir:cc redir_gcc:gcc; do
	mkfake "mkrc_${_s%%:*}"
	{
		printf 'all: libselftest.a\nlibselftest.a: sel_a.c sel_b.c\n'
		printf '\t%s -Wall -Wextra -Werror sel_a.c sel_b.c -o libselftest.a 2> errs.log >&2\n' \
			"${_s#*:}"
	} > "$WORK/mkrc_${_s%%:*}/Makefile"
done
want_green "make_test --recipe-cc: a compile with its output redirected passes" -- mkrl mkrc_redir
want_out   "make_test --recipe-cc: ...counted once" \
	"the one compile command a bare 'make' runs" -- mkrl mkrc_redir
want_broken_none "make_test --recipe-cc: ...and never said to be out of the plan" \
	'are not in what' -- mkrl mkrc_redir
want_red   "make_test --recipe-cc: gcc with its output redirected fails" -- mkrl mkrc_redir_gcc
want_out   "make_test --recipe-cc: ...as the one compile there is" \
	'1 of the 1 compile command(s)' -- mkrl mkrc_redir_gcc
# Text the Makefile prints is no command: $(info ...) goes to the stream the
# plan is read from, and `$(info gcc -c sel_a.c)` read as a gcc compile and
# failed a Makefile that compiles with cc; one repeating the real compile
# counted it twice. A plan line no build ran, by a compiler stood in for by
# name, is set aside with a NOTE. The premise: gcc the Makefile does run is
# still judged (mkrc_redir_gcc above).
for _s in info_gcc:'gcc -c sel_a.c' info_same:'cc -Wall -Wextra -Werror sel_a.c sel_b.c -o libselftest.a'; do
	mkfake "mkrc_${_s%%:*}"
	{
		printf '$(info %s)\n' "${_s#*:}"
		printf 'all: libselftest.a\nlibselftest.a: sel_a.c sel_b.c\n'
		printf '\tcc -Wall -Wextra -Werror sel_a.c sel_b.c -o libselftest.a\n'
	} > "$WORK/mkrc_${_s%%:*}/Makefile"
done
want_green "make_test --recipe-cc: \$(info gcc ...) is not a gcc compile" -- mkrl mkrc_info_gcc
want_out   "make_test --recipe-cc: ...and is said to be set aside" \
	"printed read like a compile" -- mkrl mkrc_info_gcc
want_green "make_test --recipe-cc: \$(info) repeating the real compile" -- mkrl mkrc_info_same
want_out   "make_test --recipe-cc: ...which is counted once" \
	"the one compile command a bare 'make' runs" -- mkrl mkrc_info_same
# Each compile of a line is judged, not the line's first word, by the rule a
# forbidden command keeps (mkar_infosemi and the branch arms, "make_test
# archiver"): text whose compile follows a ; or a | is text too, and a
# compile in a branch of the shell this box did not take is judged as one,
# on its own line of a .ONESHELL if or case as on the line that opens it --
# those two were set aside as text, and passed. mkrcb writes a right cc
# compile of both sources, then EXTRA on the same recipe; HEAD goes first.
mkrcb() {  # mkrcb DIR EXTRA [HEAD]
	mkfake "$1"
	{
		printf '%b' "${3:-}"
		printf 'all: libselftest.a\nlibselftest.a: sel_a.c sel_b.c\n'
		printf '\tcc -Wall -Wextra -Werror sel_a.c sel_b.c -o libselftest.a\n'
		[ -z "$2" ] || printf '\t%s\n' "$2"
	} > "$WORK/$1/Makefile"
}
mkrcb mkrc_infosemi '' '$(info [sel] building; gcc -c sel_a.c)\n'
mkrcb mkrc_iffalse 'if false; then gcc -c sel_a.c -o sel_x.o; fi'
mkrcb mkrc_ortrue 'true || gcc -c sel_a.c -o sel_x.o'
mkrcb mkrc_andnull '[ -n "" ] && gcc -c sel_a.c -o sel_x.o; true'
mkrcb mkrc_caseno 'case sel_x in sel_y) gcc -c sel_a.c -o sel_x.o ;; esac'
mkrcb mkrc_oneshell "$(printf 'if false; then\n\tgcc -c sel_a.c -o sel_x.o\n\tfi')" '.ONESHELL:\n'
mkrcb mkrc_oscase "$(printf 'case sel_x in sel_y)\n\tgcc -c sel_a.c -o sel_x.o ;;\n\tesac')" '.ONESHELL:\n'
mkrcb mkrc_linepath 'PATH=$(CURDIR)/sel_alt:$$PATH; gcc -c sel_a.c -o sel_x.o'
mkdir -p "$WORK/mkrc_linepath/sel_alt"
mv "$WORK/mkrc_linepath/bin/gcc" "$WORK/mkrc_linepath/sel_alt/gcc"
mkfake mkrc_ifdone
{
	printf 'all: libselftest.a sel_note\nlibselftest.a: sel_a.c sel_b.c\n'
	printf '\tif true; then cc -Wall -Wextra -Werror sel_a.c sel_b.c -o libselftest.a; fi\n'
	printf 'sel_note: libselftest.a\n\t$(info gcc -c sel_a.c stays out of sel)\n'
} > "$WORK/mkrc_ifdone/Makefile"
want_green "make_test --recipe-cc: \$(info x; gcc ...) is not a gcc compile" -- mkrl mkrc_infosemi
want_green "make_test --recipe-only: ...nor at strict" -- mkrl mkrc_infosemi --recipe-only
want_out   "make_test --recipe-cc: ...and is said to be set aside" \
	"printed read like a compile" -- mkrl mkrc_infosemi
want_red   "make_test --recipe-cc: gcc in an if not taken is judged" -- mkrl mkrc_iffalse
want_red   "make_test --recipe-cc: ...after an || not taken" -- mkrl mkrc_ortrue
want_red   "make_test --recipe-cc: ...after an && not taken" -- mkrl mkrc_andnull
want_red   "make_test --recipe-cc: ...in a case not taken" -- mkrl mkrc_caseno
want_red   "make_test --recipe-cc: ...on the next line of a .ONESHELL if" -- mkrl mkrc_oneshell
want_out   "make_test --recipe-cc: ...named" 'gcc, not cc' -- mkrl mkrc_oneshell
want_red   "make_test --recipe-cc: ...and of a .ONESHELL case" -- mkrl mkrc_oscase
want_green "make_test --recipe-cc: text after a closed if is text" -- mkrl mkrc_ifdone
want_red   "make_test --recipe-cc: gcc after PATH= on its line is judged" -- mkrl mkrc_linepath
# A plan line is set aside only where the build's recipes found the
# stand-ins. A Makefile that exports a PATH of its own runs the compiler
# past them, which then log nothing: its gcc compile read as text no build
# ran, and passed. Three ways: the whole PATH ahead of them (nothing logged
# at all); one compiler ahead of them while cc reaches its stand-in (that
# call's PATH finds gcc elsewhere); and one target's PATH alone, where every
# logged call found the stand-ins (the object gcc wrote, which no logged
# compile wrote). Each was green before this.
mkfake mkrc_path_all
{
	printf 'export PATH := $(CURDIR)/bin:$(PATH)\n'
	printf 'all: libselftest.a\nlibselftest.a: sel_a.c sel_b.c\n'
	printf '\tgcc -Wall -Wextra -Werror sel_a.c sel_b.c -o libselftest.a\n'
} > "$WORK/mkrc_path_all/Makefile"
for _s in path_one path_target; do
	mkfake "mkrc_$_s"
	mkdir -p "$WORK/mkrc_$_s/alt"
	cp "$WORK/mkrc_$_s/bin/gcc" "$WORK/mkrc_$_s/alt/gcc"
	{
		[ "$_s" = path_target ] || printf 'export PATH := $(CURDIR)/alt:$(PATH)\n'
		printf 'all: libselftest.a\nlibselftest.a: sel_a.o sel_b.o\n'
		printf '\tcat sel_a.o sel_b.o > libselftest.a\n'
		printf 'sel_a.o: sel_a.c\n\tcc -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n'
		[ "$_s" = path_one ] || printf 'sel_b.o: export PATH := $(CURDIR)/alt:$(PATH)\n'
		printf 'sel_b.o: sel_b.c\n\tgcc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n'
	} > "$WORK/mkrc_$_s/Makefile"
done
want_red   "make_test --recipe-cc: gcc run past the stand-ins by an exported PATH fails" -- \
	mkrl mkrc_path_all
want_out   "make_test --recipe-cc: ...named" 'gcc, not cc' -- mkrl mkrc_path_all
want_red   "make_test --recipe-cc: ...and where cc still reaches its stand-in" -- \
	mkrl mkrc_path_one
want_out   "make_test --recipe-cc: ...named" 'gcc, not cc' -- mkrl mkrc_path_one
want_red   "make_test --recipe-cc: ...and under one target's PATH" -- mkrl mkrc_path_target
want_out   "make_test --recipe-cc: ...named" 'gcc, not cc' -- mkrl mkrc_path_target
want_broken "make_test --recipe-cc: no sentence about cc is refused" "'cc' sentence" -- \
	mt --rules "" --recipe-cc any --anchor "$WORK/mkrc_ok/Makefile" --artifact libselftest.a
printf 'rules\tToy, p.9: "all, clean."\n' > "$MKQ/unknown.tsv"
want_broken "make_test --quotes: a key no check reads is refused" "unknown key 'rules'" -- \
	mt --rules "" --quotes "$MKQ/unknown.tsv" \
		--anchor "$WORK/mkrc_ok/Makefile" --artifact libselftest.a
# Where no compile is planned, and the build's lesson is not its compile
# commands (no --graph), there is nothing to judge, and the build says what
# the Makefile made: mksbin, this section's copy of make_test's mkbin, builds
# its library with no compile at all.
mkdir -p "$WORK/mksbin"
printf 'all:\n\t: > libselftest.a\n' > "$WORK/mksbin/Makefile"
want_green "make_test --recipe-cc: a plan with no compile is not judged" -- \
	mkrc mksbin any
want_out   "make_test --recipe-cc: ...and says so" \
	'no compile command was judged against the sentence about cc' -- mkrc mksbin any
# The compile layers build a student's own sources, and a Makefile turned in
# alone has none: the FAIL names those layers only where they exist.
mkdir -p "$WORK/mkrc_ov"
cp -R "$WORK/mkrc_gcc/bin" "$WORK/mkrc_ov/bin"
printf 'all:\n\t./bin/gcc -Wall -Wextra -Werror -c grader/sel_g.c -o libselftest.a\n' \
	> "$WORK/mkrc_ov/Makefile"
want_out   "make_test --recipe-cc: over the grader's sources, gcc fails" 'gcc, not cc' -- \
	mkrc mkrc_ov any --overlay "$WORK/mkrc_ok/sel_a.c" grader/sel_g.c
want_broken_none "make_test --recipe-cc: ...and names no compile layer" 'compile layers' -- \
	mkrc mkrc_ov any --overlay "$WORK/mkrc_ok/sel_a.c" grader/sel_g.c
want_out   "make_test --recipe-cc: ...which a student's own sources have" 'compile layers' -- \
	mkrc mkrc_gcc any

# --recipe-only, the strict target (exNN_build_recipe), where the sentence
# about cc says what the grader does and binding the recipes is a reading.
want_red   "make_test --recipe-only: gcc fails, as a reading" -- \
	mkrc mkrc_gcc any --recipe-only
want_out   "make_test --recipe-only: ...and says it is one" "is this harness's reading of it" -- \
	mkrc mkrc_gcc any --recipe-only
want_green "make_test --recipe-only: cc and the flags pass" -- mkrc mkrc_ok any --recipe-only
want_green "make_test --recipe-only: no compile planned is a SKIP" -- \
	env -u NO_SKIP "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --recipe-cc any \
		--quotes "$MKQ/cc.tsv" --recipe-only --build-target selftest_build \
		--anchor "$WORK/mksecho/Makefile" --artifact libselftest.a
want_red   "make_test --recipe-only: ...that NO_SKIP=1 turns red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --recipe-cc any \
		--quotes "$MKQ/cc.tsv" --recipe-only --build-target selftest_build \
		--anchor "$WORK/mksecho/Makefile" --artifact libselftest.a
want_out   "make_test --recipe-only: ...and names the build target" \
	'to judge; selftest_build says why' -- \
	env NO_SKIP=1 "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --recipe-cc any \
		--quotes "$MKQ/cc.tsv" --recipe-only --build-target selftest_build \
		--anchor "$WORK/mksecho/Makefile" --artifact libselftest.a
want_broken "make_test --recipe-only: without --recipe-cc it is refused" 'there is no --recipe-cc' -- \
	mt --rules "" --quotes "$MKQ/cc.tsv" --recipe-only \
		--anchor "$WORK/mkrc_ok/Makefile" --artifact libselftest.a
# A creator script: what it RAN (sh -x), a loop's every turn, never its text.
mkfake mkrs_ok
printf '%s\n' 'for s in sel_a sel_b; do' '	./bin/cc -Wall -Wextra -Werror -c "$s.c" -o "$s.o"' \
	'done' 'cat sel_a.o sel_b.o > libselftest.a' > "$WORK/mkrs_ok/build.sh"
mkfake mkrs_gcc
printf '%s\n' 'C=./bin/gcc' '$C -Wall -Wextra -Werror -c sel_a.c -o sel_a.o' \
	'cat sel_a.o > libselftest.a' > "$WORK/mkrs_gcc/build.sh"
mkrs() {  # mkrs DIR: the script's compile commands, alone
	mt --recipe-cc any --quotes "$MKQ/cc.tsv" --recipe-only --script build.sh \
		--anchor "$WORK/$1/build.sh" --artifact libselftest.a
}
want_green "make_test --recipe-only --script: what a loop ran, each turn" -- mkrs mkrs_ok
want_out   "make_test --recipe-only --script: ...counted" \
	"each of the 2 compile commands 'sh build.sh' ran" -- mkrs mkrs_ok
want_red   "make_test --recipe-only --script: gcc behind a variable fails" -- mkrs mkrs_gcc
want_out   "make_test --recipe-only --script: ...named" 'gcc, not cc' -- mkrs mkrs_gcc
# A trace the script hides (set +x) hid its compiles, and the target said
# none ran. A compiler run by name is seen on PATH whatever the trace shows,
# and one the trace does show too is counted once. The fixture's bin/ goes
# first on PATH, so its stand-ins are the compilers found by name.
for _s in hide:gcc hide_ok:cc shown:cc; do
	mkfake "mkrs_${_s%%:*}"
	{
		[ "${_s%%:*}" = shown ] || printf 'set +x\n'
		printf '%s -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n' "${_s#*:}"
		printf 'cat sel_a.o > libselftest.a\n'
	} > "$WORK/mkrs_${_s%%:*}/build.sh"
done
mkrp() {  # mkrp DIR: mkrs, with DIR/bin first on PATH
	env PATH="$WORK/$1/bin:$PATH" "$SH" "$TOOLS/make_test.sh" --nm "$NM" --recipe-cc any \
		--quotes "$MKQ/cc.tsv" --recipe-only --script build.sh \
		--build-target selftest_build --anchor "$WORK/$1/build.sh" --artifact libselftest.a
}
want_red   "make_test --recipe-only --script: gcc run with the trace off fails" -- mkrp mkrs_hide
want_out   "make_test --recipe-only --script: ...named" 'gcc, not cc' -- mkrp mkrs_hide
want_out   "make_test --recipe-only --script: ...and said to be out of the trace" \
	'are not in' -- mkrp mkrs_hide
want_green "make_test --recipe-only --script: cc run with the trace off passes" -- mkrp mkrs_hide_ok
# Every name the pinned toolchain gives a compiler has its stand-in:
# clang-12 and gcc-10 had none, so a compile through one with the trace off
# was in neither record -- a SKIP alone, and beside a compile that was seen,
# an OK. The fixture's bin/ has its own of each, as for cc and gcc, so no
# arm reads the box's.
for _s in hide12:clang-12 hide10:gcc-10 hidemix:clang-12; do
	mkfake "mkrs_${_s%%:*}"
	cp "$WORK/mkrs_${_s%%:*}/bin/cc" "$WORK/mkrs_${_s%%:*}/bin/${_s#*:}"
	{
		[ "${_s%%:*}" != hidemix ] || printf 'cc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n'
		printf 'set +x\n%s -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n' "${_s#*:}"
		printf 'cat sel_a.o > libselftest.a\n'
	} > "$WORK/mkrs_${_s%%:*}/build.sh"
done
want_out   "make_test --recipe-only --script: clang-12 run with the trace off is named" \
	'clang-12, not cc' -- mkrp mkrs_hide12
want_out   "make_test --recipe-only --script: ...and gcc-10" 'gcc-10, not cc' -- mkrp mkrs_hide10
want_red   "make_test --recipe-only --script: ...and fails beside a compile the trace shows" -- \
	mkrp mkrs_hidemix
# The same for a Makefile, whose plan shows the shell variable that holds
# the name and not the name.
mkfake mkrc_var12
cp "$WORK/mkrc_var12/bin/cc" "$WORK/mkrc_var12/bin/clang-12"
{
	printf 'all: libselftest.a\nlibselftest.a: sel_a.o sel_b.o\n\tcat sel_a.o sel_b.o > libselftest.a\n'
	printf 'sel_a.o: sel_a.c\n\tsel_c=clang-12; $$sel_c -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n'
	printf 'sel_b.o: sel_b.c\n\tcc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n'
} > "$WORK/mkrc_var12/Makefile"
want_red   "make_test --recipe-only: clang-12 named by a shell variable fails" -- \
	mkrl mkrc_var12 --recipe-only
want_out   "make_test --recipe-only: ...named" 'clang-12, not cc' -- mkrl mkrc_var12 --recipe-only
want_out   "make_test --recipe-only --script: a compile both records show is one" \
	"the one compile command 'sh build.sh' ran" -- mkrp mkrs_shown
want_broken_none "make_test --recipe-only --script: ...and none is out of the trace" \
	'are not in' -- mkrp mkrs_shown
# A compiler run by its FULL PATH with the trace off is in neither record:
# not in the trace, and not on PATH, where the stand-ins are. Its object is
# in the tree all the same, and the check says that compile went unjudged
# instead of an OK that reads as though every compile was seen.
mkfake mkrs_abspath
printf '%s\n' './bin/cc -Wall -Wextra -Werror -c sel_a.c -o sel_a.o' 'set +x' \
	'"$PWD/bin/gcc" -c sel_b.c -o sel_b.o' 'cat sel_a.o sel_b.o > libselftest.a' \
	> "$WORK/mkrs_abspath/build.sh"
want_out   "make_test --recipe-only --script: a compile by full path, trace off, is said unseen" \
	'were made by a compile neither record saw' -- mkrs mkrs_abspath
want_out   "make_test --recipe-only --script: ...naming its object" '    sel_b.o' -- mkrs mkrs_abspath
want_broken_none "make_test --recipe-only --script: ...and a script with none says nothing of it" \
	'neither record saw' -- mkrs mkrs_ok

# EVERY COMMAND PRINTED (--graph), asked of what the build printed: .SILENT,
# -s in MAKEFLAGS and an @ a variable expands to all run a command unseen,
# and the text check for a leading @ sees none of them.
mkgr() {  # mkgr DIR HEAD DEP-A DEP-B PREFIX: two objects beside their sources
	mkfake "$1"
	{
		printf '%b' "$2"
		printf 'all: libselftest.a\n'
		printf 'libselftest.a: sel_a.o sel_b.o\n\tcat sel_a.o sel_b.o > libselftest.a\n'
		printf 'sel_a.o: %s\n\t%s./bin/cc -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n' \
			"${3:-sel_a.c}" "$5"
		printf 'sel_b.o: %s\n\t./bin/cc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n' \
			"${4:-sel_b.c}"
	} > "$WORK/$1/Makefile"
}
mkgr mkgr_ok '' '' '' ''
mkgr mkgr_silent '.SILENT:\n' '' '' ''
mkgr mkgr_flag 'MAKEFLAGS += -s\n' '' '' ''
mkgr mkgr_var 'Q = @\n' '' '' '$(Q)'
mkgr mkgr_at '' '' '' '@'
mkgr mkgr_all '' 'sel_a.c sel_b.c' 'sel_a.c sel_b.c' ''
mkg() {  # mkg DIR: the --graph checks, and the ordered compile commands
	mt --rules "" --graph --recipe-cc ordered --quotes "$MKQ/graphcc.tsv" \
		--anchor "$WORK/$1/Makefile" --artifact libselftest.a
}
want_green "make_test --graph: every command printed, nothing redone" -- mkg mkgr_ok
want_broken_none "make_test --graph: ...and nothing said to be unseen" 'without printing' -- \
	mkg mkgr_ok
want_red   "make_test --graph: .SILENT runs commands unseen" -- mkg mkgr_silent
want_out   "make_test --graph: ...and names them" \
	'./bin/cc -Wall -Wextra -Werror -c sel_a.c -o sel_a.o' -- mkg mkgr_silent
want_out   "make_test --graph: ...quoting the call site's sentence" \
	'Toy, p.1: "Print every command."' -- mkg mkgr_silent
want_red   "make_test --graph: -s in MAKEFLAGS does too" -- mkg mkgr_flag
want_red   "make_test --graph: so does an @ from a variable" -- mkg mkgr_var
want_out   "make_test --graph: ...seen from what it printed" \
	"'make' ran commands without printing them" -- mkg mkgr_var
want_out   "make_test --graph: a literal @ gets the targeted message" \
	"silenced with '@'" -- mkg mkgr_at
# A command whose output has no newline at its end: make prints the next
# command on the end of that line, and it was printed all the same.
mkgr mkgr_nonl '' '' '' ''
{
	printf '%s\n' 'all: libselftest.a' 'libselftest.a: sel_a.o sel_b.o' \
		"	printf 'archiving: '" '	cat sel_a.o sel_b.o > libselftest.a'
	sed -n '/^sel_a.o:/,$p' "$WORK/mkgr_ok/Makefile"
} > "$WORK/mkgr_nonl/Makefile"
want_green "make_test --graph: a command printed after output with no newline is seen" -- \
	mkg mkgr_nonl
# ONE SOURCE CHANGED, ONE OBJECT REBUILT: nothing redone on an untouched
# tree is also true of a Makefile whose every object depends on every
# source; touching one source tells them apart.
want_red   "make_test --graph: one touched source rebuilding all fails" -- mkg mkgr_all
want_out   "make_test --graph: ...naming the object it should have left" \
	'rebuilt these objects as well as sel_a.o' -- mkg mkgr_all
# An OK says whether that check ran: it stands down where no object sits
# beside its source -- here the archive is compiled straight from them.
want_out   "make_test --graph: ...and the OK says it touched each" \
	'2 source(s) touched, one at a time: sel_a.c sel_b.c.' -- mkg mkgr_ok
# Objects beside their sources in a folder whose name holds a blank: the
# list of objects is one a line, and a path is never split at its blank.
# Its own stand-in compiler, which takes one source, blank and all.
mkdir -p "$WORK/mkgr_blank/a b" "$WORK/mkgr_blank/bin"
printf '%s\n' '#!/bin/sh' '_o=""; _i=""' \
	'while [ $# -gt 0 ]; do case "$1" in -o) _o=$2; shift 2 ;; -*) shift ;; *) _i=$1; shift ;; esac; done' \
	'cat "$_i" > "$_o"' > "$WORK/mkgr_blank/bin/cc"
chmod +x "$WORK/mkgr_blank/bin/cc"
printf 'selftest a\n' > "$WORK/mkgr_blank/a b/sel_a.c"
printf 'selftest b\n' > "$WORK/mkgr_blank/a b/sel_b.c"
printf '%s\n' 'all: libselftest.a' 'libselftest.a: a\ b/sel_a.o a\ b/sel_b.o' \
	'	cat "a b/sel_a.o" "a b/sel_b.o" > libselftest.a' 'a\ b/%.o: a\ b/%.c' \
	'	./bin/cc -Wall -Wextra -Werror -c "$<" -o "$@"' > "$WORK/mkgr_blank/Makefile"
mkgb() {
	mt --rules "" --graph --quotes "$MKQ/graph.tsv" \
		--anchor "$WORK/mkgr_blank/Makefile" --artifact libselftest.a
}
want_green "make_test --graph: objects beside their sources, in a folder with a blank" -- mkgb
want_out   "make_test --graph: ...each source touched in turn" \
	'2 source(s) touched, one at a time: a b/sel_a.c a b/sel_b.c.' -- mkgb
# EACH source, not the first found: an object tied to every source rebuilds
# alone when its own changes and with the others when any other does. Here
# sel_a.o depends on both, so touching sel_a.c alone passed.
mkgr mkgr_onetied '' 'sel_a.c sel_b.c' '' ''
want_red   "make_test --graph: one object tied to every source fails, whichever is touched" -- \
	mkg mkgr_onetied
want_out   "make_test --graph: ...naming the source that showed it" \
	'only sel_b.c was touched' -- mkg mkgr_onetied
# The OK says only what the touch showed: a rule for an object that does
# not name its source rebuilds nothing when that source changes, and "only
# its object was rebuilt" was said over a run that rebuilt none. Of the two
# sources here only sel_b.c rebuilds its object, so the count the OK gives
# is 1; a 2 counted sel_a.c too, beside its own "not seen". (The OK is
# folded at 74 columns; "2 rebuilt only their" sits on one line of it.)
mkgr mkgr_nodep '' ' ' '' ''
want_out   "make_test --graph: a touched source whose object stays is said to" \
	'rebuilt no object, not even sel_a.o' -- mkg mkgr_nodep
want_broken_none "make_test --graph: ...and the OK claims no rebuild" \
	'2 rebuilt only their' -- mkg mkgr_nodep
# ...nor does the FAIL: sel_a.o names sel_b.c and not its own source, so
# touching sel_a.c rebuilt nothing, and touching sel_b.c rebuilt both. The
# FAIL said sel_a.c was touched before "rebuilding its own object alone".
mkgr mkgr_nodep_tied '' 'sel_b.c' '' ''
want_red   "make_test --graph: an object tied to another source fails" -- mkg mkgr_nodep_tied
want_broken_none "make_test --graph: ...never saying an earlier touch rebuilt its own alone" \
	'each rebuilding its own object alone' -- mkg mkgr_nodep_tied
want_out   "make_test --graph: ...but that what it rebuilt was not seen" \
	"with what is rebuilt not seen: sel_a.c ('make' rebuilt no object" -- mkg mkgr_nodep_tied
# The cap is said where it left a pair untouched, counted in pairs: twelve
# sources beside their objects and one object with no source of its name
# were all touched, and the OK still said "At most 12 are touched".
mkgr_many() {  # mkgr_many DIR N: N sources beside their objects, and DIR's extra.o
	mkfake "$1"
	_objs=""
	_i=1
	while [ "$_i" -le "$2" ]; do
		printf 'selftest %s\n' "$_i" > "$WORK/$1/s$_i.c"
		_objs="$_objs s$_i.o"
		_i=$((_i + 1))
	done
	{
		printf 'all: libselftest.a\nlibselftest.a:%s extra.o\n' "$_objs"
		printf '\tcat%s extra.o > libselftest.a\n' "$_objs"
		printf 'extra.o:\n\tprintf x > extra.o\n'
		printf '%%.o: %%.c\n\t./bin/cc -Wall -Wextra -Werror -c $< -o $@\n'
	} > "$WORK/$1/Makefile"
}
mkgr_many mkgr_twelve 12
mkgr_many mkgr_thirteen 13
want_green "make_test --graph: twelve pairs and an object of no source pass" -- mkg mkgr_twelve
want_broken_none "make_test --graph: ...and say no cap, every pair touched" 'At most' -- \
	mkg mkgr_twelve
want_out   "make_test --graph: thirteen pairs say the cap, in pairs" \
	'12 of the 13 are touched' -- mkg mkgr_thirteen
mkfake mkgr_noobj
{
	printf 'all: libselftest.a\n'
	printf 'libselftest.a: sel_a.c sel_b.c\n'
	printf '\t./bin/cc -Wall -Wextra -Werror -c sel_a.c sel_b.c -o libselftest.a\n'
} > "$WORK/mkgr_noobj/Makefile"
want_green "make_test --graph: no object beside a source is not judged" -- mkg mkgr_noobj
want_out   "make_test --graph: ...and the OK says so" \
	'No object sits beside its source, so no source was touched' -- mkg mkgr_noobj

# "Watch out for wildcards!" -- a grader's object where the student's objects
# go (--foreign-object), which no cleaning rule may take: one that deletes by
# pattern does.
mkfo() {  # mkfo DIR CLEAN-RECIPE: an object in sub/, and the three rules
	mkfake "$1"
	mkdir -p "$WORK/$1/sub"
	printf 'selftest a\n' > "$WORK/$1/sub/sel_a.c"
	{
		printf 'all: libselftest.a\n'
		printf 'libselftest.a: sub/sel_a.o\n\tcat sub/sel_a.o > libselftest.a\n'
		printf 'sub/sel_a.o: sub/sel_a.c\n\t./bin/cc -Wall -Wextra -Werror -c sub/sel_a.c -o sub/sel_a.o\n'
		printf 'clean:\n\t%s\n' "$2"
		printf 'fclean:\n\t%s\n\trm -f libselftest.a\n' "$2"
		printf 're:\n\t%s\n\trm -f libselftest.a\n\t$(MAKE) all\n' "$2"
	} > "$WORK/$1/Makefile"
}
mkfo mkfo_named 'rm -f sub/sel_a.o'
mkfo mkfo_pattern 'rm -f sub/*.o'
mkf() {  # mkf DIR: the grader's object in sub/, with the rules defined
	mt --rules clean,fclean,re --foreign-object sub/zz_graders_own_file.o \
		--quotes "$MKQ/ccrules.tsv" --anchor "$WORK/$1/Makefile" --artifact libselftest.a
}
want_green "make_test --foreign-object: named files leave the grader's" -- mkf mkfo_named
want_out   "make_test --foreign-object: ...and the OK says how many runs it judged" \
	'no rule of yours made: 2 run(s).' -- mkf mkfo_named
want_broken_none "make_test --foreign-object: ...never counted as left behind" \
	'left object files behind' -- mkf mkfo_named
want_red   "make_test --foreign-object: a clean by pattern takes it" -- mkf mkfo_pattern
want_out   "make_test --foreign-object: ...and says which file" \
	'sub/zz_graders_own_file.o' -- mkf mkfo_pattern
want_out   "make_test --foreign-object: ...quoting the call site's sentence" \
	'Toy, p.3: "Name every file; our files sit beside yours."' -- mkf mkfo_pattern
want_broken_none "make_test --foreign-object: ...a subject's own words, not the Norm's" \
	'the Norm' -- mkf mkfo_pattern
want_broken "make_test --foreign-object: no sentence about it is refused" "'wildcards' sentence" -- \
	mt --rules clean --foreign-object sub/zz.o --anchor "$WORK/mkfo_named/Makefile" \
		--artifact libselftest.a

# --wildcards-only, the strict target where the rule is the Norm's and the
# subject does not say it (exNN_build_wildcards): a decoy source beside the
# sources the build compiles, and the grader's object beside its objects.
mkfake mkwc_glob
{
	printf 'S = $(wildcard *.c)\n'
	printf 'all: libselftest.a\n'
	printf 'libselftest.a: $(S)\n\t./bin/cc -Wall -Wextra -Werror $(S) -o libselftest.a\n'
	printf 'clean:\n\t:\n'
} > "$WORK/mkwc_glob/Makefile"
mkgr mkwc_named '' '' '' ''
printf 'clean:\n\trm -f sel_a.o sel_b.o\n' >> "$WORK/mkwc_named/Makefile"
mkgr mkwc_pattern '' '' '' ''
printf 'clean:\n\trm -f *.o\n' >> "$WORK/mkwc_pattern/Makefile"
mkw() {  # mkw DIR: the Norm's no *.c, no *.o
	mt --rules clean --wildcards-only --quotes "$MKQ/cc.tsv" --build-target selftest_build \
		--anchor "$WORK/$1/Makefile" --artifact libselftest.a
}
want_red   "make_test --wildcards-only: a Makefile taking *.c compiles the decoy" -- \
	mkw mkwc_glob
want_out   "make_test --wildcards-only: ...and says so" \
	'compiled a source it was never told about' -- mkw mkwc_glob
want_green "make_test --wildcards-only: named sources, named objects" -- mkw mkwc_named
want_out   "make_test --wildcards-only: ...having judged the cleaning run" \
	'left alone an object they did not make (1 run(s))' -- mkw mkwc_named
# What says the decoy was compiled is a compile, never its name: the name
# anywhere in make's output used to fail a default goal that ran `ls`. Each
# witness on its own: the compiler's error at the decoy's line (a silent
# recipe), a printed compile that names it (its errors sent away), and a
# clean tree that built where the decoy's did not (silent, errors away).
mkfake mkwc_ls
{
	printf 'all: libselftest.a\n\tls\n'
	printf 'libselftest.a: sel_a.o sel_b.o\n\tcat sel_a.o sel_b.o > libselftest.a\n'
	printf 'sel_a.o: sel_a.c\n\t./bin/cc -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n'
	printf 'sel_b.o: sel_b.c\n\t./bin/cc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n'
	printf 'clean:\n\trm -f sel_a.o sel_b.o\n'
} > "$WORK/mkwc_ls/Makefile"
mkwg() {  # mkwg DIR PREFIX SUFFIX: every .c in one compile; @ silences it, SUFFIX redirects
	mkfake "$1"
	{
		printf 'S = $(wildcard *.c)\nall: libselftest.a\n'
		printf 'libselftest.a: $(S)\n\t%s./bin/cc -Wall -Wextra -Werror $(S) -o libselftest.a%s\n' \
			"$2" "$3"
		printf 'clean:\n\t:\n'
	} > "$WORK/$1/Makefile"
}
mkwg mkwc_silent @ ''
mkwg mkwc_echoed '' ' 2> /dev/null'
mkwg mkwc_hidden @ ' 2> /dev/null'
want_green "make_test --wildcards-only: a goal that lists the decoy did not compile it" -- \
	mkw mkwc_ls
want_red   "make_test --wildcards-only: a silent compile of it, by the compiler's error" -- \
	mkw mkwc_silent
want_out   "make_test --wildcards-only: ...which it names" \
	"its #error is in make's output" -- mkw mkwc_silent
want_red   "make_test --wildcards-only: a compile with its errors sent away, as printed" -- \
	mkw mkwc_echoed
want_out   "make_test --wildcards-only: ...which it names" \
	'the command that compiled it is in' -- mkw mkwc_echoed
want_red   "make_test --wildcards-only: neither, by the clean tree that built" -- \
	mkw mkwc_hidden
want_out   "make_test --wildcards-only: ...which it names" \
	"the same tree without it built 'libselftest.a'" -- mkw mkwc_hidden
# A sub-make plans its compiles from its own folder: `$(MAKE) -C sel_sub`
# plans `cc ... sel_a.c` for sel_sub/sel_a.c. Read from the top alone, the
# decoy went beside the top Makefile, which a sel_sub/Makefile taking *.c
# never met (a pass), and a sub-make compiling sel_src/x.c from its folder
# left no folder to put it in (a SKIP). The folders the compiler's stand-in
# was handed a source in are read too, so its cc is found by name here.
mkwsub() {  # mkwsub DIR SRCDIR SOURCES: $(MAKE) -C sel_sub, which compiles SOURCES from SRCDIR
	mkfake "$1"
	mkdir -p "$WORK/$1/sel_sub/$2"
	mv "$WORK/$1/sel_a.c" "$WORK/$1/sel_b.c" "$WORK/$1/sel_sub/$2/"
	printf '%s\n' 'all: libselftest.a' 'libselftest.a:' '	$(MAKE) -C sel_sub' \
		'	cp sel_sub/libselftest.a libselftest.a' 'clean:' '	$(MAKE) -C sel_sub clean' \
		> "$WORK/$1/Makefile"
	printf '%s\n' "S = $3" 'all: libselftest.a' 'libselftest.a: $(S)' \
		'	cc -Wall -Wextra -Werror $(S) -o libselftest.a' 'clean:' '	:' \
		> "$WORK/$1/sel_sub/Makefile"
}
mkwsub mkwc_subglob . '$(wildcard *.c)'
mkwsub mkwc_subdir sel_src '$(wildcard sel_src/*.c)'
mkwsub mkwc_subnamed sel_src 'sel_src/sel_a.c sel_src/sel_b.c'
mkws() {  # mkws DIR: mkw, with DIR/bin first on PATH
	once env PATH="$WORK/$1/bin:$PATH" "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules clean \
		--wildcards-only --quotes "$MKQ/cc.tsv" --build-target selftest_build \
		--anchor "$WORK/$1/Makefile" --artifact libselftest.a
}
want_red   "make_test --wildcards-only: a sub-make taking *.c compiles the decoy" -- \
	mkws mkwc_subglob
want_out   "make_test --wildcards-only: ...put beside the sub-make's sources" \
	'    sel_sub/zz_harness_decoy_not_in_your_makefile.c' -- mkws mkwc_subglob
want_red   "make_test --wildcards-only: ...and in a folder under the sub-make's" -- \
	mkws mkwc_subdir
want_out   "make_test --wildcards-only: ...put there" \
	'    sel_sub/sel_src/zz_harness_decoy_not_in_your_makefile.c' -- mkws mkwc_subdir
want_green "make_test --wildcards-only: a sub-make naming its sources passes" -- \
	mkws mkwc_subnamed
want_out   "make_test --wildcards-only: ...having laid the decoy there" \
	'the build compiled no source it was not told about' -- mkws mkwc_subnamed
# An object directory of the build's own (obj/): the grader's object goes
# there too. A clean that deletes by pattern there takes it (red); one that
# removes the directory whole names no file, and is not judged (green, and
# said). It went beside a source only, so obj/*.o passed unseen.
for _s in objpat:'rm -f obj/*.o' objwhole:'rm -rf obj'; do
	mkfake "mkwc_${_s%%:*}"
	{
		printf 'all: libselftest.a\nlibselftest.a: obj/sel_a.o obj/sel_b.o\n'
		printf '\tcat obj/sel_a.o obj/sel_b.o > libselftest.a\n'
		for _x in a b; do
			printf 'obj/sel_%s.o: sel_%s.c\n\tmkdir -p obj\n' "$_x" "$_x"
			printf '\t./bin/cc -Wall -Wextra -Werror -c sel_%s.c -o obj/sel_%s.o\n' "$_x" "$_x"
		done
		printf 'clean:\n\t%s\n' "${_s#*:}"
	} > "$WORK/mkwc_${_s%%:*}/Makefile"
done
want_red   "make_test --wildcards-only: a clean of obj/*.o takes the grader's" -- \
	mkw mkwc_objpat
want_green "make_test --wildcards-only: a clean that removes obj/ whole is no pattern" -- \
	mkw mkwc_objwhole
want_out   "make_test --wildcards-only: ...and is said not to be judged" \
	'removed the object directory of your build' -- mkw mkwc_objwhole
want_red   "make_test --wildcards-only: a clean of *.o takes the grader's" -- \
	mkw mkwc_pattern
want_out   "make_test --wildcards-only: ...and says the rule is the Norm's" \
	'the Norm, which your work must' -- mkw mkwc_pattern
want_green "make_test --wildcards-only: a plan with no compile is a SKIP" -- \
	env -u NO_SKIP "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --wildcards-only \
		--quotes "$MKQ/cc.tsv" --build-target selftest_build \
		--anchor "$WORK/mksecho/Makefile" --artifact libselftest.a
want_red   "make_test --wildcards-only: ...that NO_SKIP=1 turns red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --wildcards-only \
		--quotes "$MKQ/cc.tsv" --build-target selftest_build \
		--anchor "$WORK/mksecho/Makefile" --artifact libselftest.a
want_out   "make_test --wildcards-only: ...and names the build target" \
	'decoy; selftest_build says why' -- \
	env NO_SKIP=1 "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --wildcards-only \
		--quotes "$MKQ/cc.tsv" --build-target selftest_build \
		--anchor "$WORK/mksecho/Makefile" --artifact libselftest.a
want_broken "make_test --wildcards-only: no sentence about it is refused" "'wildcards' sentence" -- \
	mt --rules clean --wildcards-only --quotes "$MKQ/graph.tsv" \
		--anchor "$WORK/mkwc_named/Makefile" --artifact libselftest.a

# WHAT A RULE DOES, where a subject lists it and does not say: this repo's
# convention, judged by exNN_build_rules (--rules-only) at robust and said to
# be ours, never at basic. The rule steps' Makefiles again, in trees of this
# section's: mksre_ok does all four jobs, and mksre_clean's re is built on
# clean.
# shellcheck disable=SC2154 # set in make_test.sh
mkrules mksre_ok 'rm -f sel.o' "$_mkre"
mkrules mksre_clean 'rm -f sel.o' 're:\n\trm -f sel.o\n\t$(MAKE) all\n'
mkr0() {  # mkr0 DIR [MODE]: the rules, with no definition quoted
	mt --rules all,clean,fclean,re --build-target selftest_build ${2:+"$2"} \
		--anchor "$WORK/$1/Makefile" --artifact libselftest.a
}
want_green "make_test: an undefined re's effect is not judged at basic" -- mkr0 mksre_clean
want_out   "make_test: ...and it says which target judges it" \
	"is this repo's convention: selftest_build_rules checks it" -- mkr0 mksre_clean
want_broken_none "make_test: ...where every rule is defined, it says nothing" \
	"this repo's convention" -- mkr mksre_ok
# Where fclean and re are defined by clean and clean is not, the note names
# clean, the definition missing: fclean and re are judged in the subject's
# words except for the part that is clean's.
grep -e '^fclean' -e '^re' "$MKQ/rules.tsv" > "$MKQ/noclean.tsv"
mkrn() {  # mkrn DIR: the rules, with fclean and re defined and clean not
	mt --rules all,clean,fclean,re --build-target selftest_build \
		--quotes "$MKQ/noclean.tsv" --anchor "$WORK/$1/Makefile" --artifact libselftest.a
}
# Both are pinned whole, so a note that named fclean or re among the
# definitions missing ("what clean, fclean and re do") fails each of them.
want_out   "make_test: an undefined clean is named as the definition missing" \
	'does not say what clean does. What it does, and so that' -- mkrn mksre_ok
want_out   "make_test: ...and fclean and re as resting on it" \
	'part of what fclean and re do, is this repo' -- mkrn mksre_ok
want_red   "make_test --rules-only: re built on clean fails the convention" -- \
	mkr0 mksre_clean --rules-only
want_out   "make_test --rules-only: ...said to be this repo's, not a subject's" \
	"So this is this repo's convention, which" -- mkr0 mksre_clean --rules-only
want_green "make_test --rules-only: rules that keep the convention pass" -- \
	mkr0 mksre_ok --rules-only
want_out   "make_test --rules-only: ...counting what it judged" \
	"does what this repo's convention says" -- mkr0 mksre_ok --rules-only
want_green "make_test --rules-only: every rule defined leaves it a SKIP" -- \
	env -u NO_SKIP "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules all,clean,fclean,re \
		--quotes "$MKQ/rules.tsv" --rules-only --build-target selftest_build \
		--anchor "$WORK/mksre_ok/Makefile" --artifact libselftest.a
want_red   "make_test --rules-only: ...that NO_SKIP=1 turns red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules all,clean,fclean,re \
		--quotes "$MKQ/rules.tsv" --rules-only --build-target selftest_build \
		--anchor "$WORK/mksre_ok/Makefile" --artifact libselftest.a
# Where the subject defines the rules, the FAIL quotes its sentences, and
# never calls them a convention.
want_out   "make_test: a defined re's FAIL quotes the definitions" \
	'Toy, p.2: "re is fclean, then all."' -- mkr mksre_clean
want_broken_none "make_test: ...and calls nothing a convention" \
	"this repo's convention" -- mkr mksre_clean

