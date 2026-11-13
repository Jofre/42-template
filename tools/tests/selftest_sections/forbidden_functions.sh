# ------------------------------------------------------- forbidden_functions
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# EACH FUNCTION, ITS OWN LIST (forbidden_symbols.sh --function). A union of
# every function's list cannot see one function calling what only another may:
# these arms prove the walk from a function's own section -- a direct call, a
# call through a static helper in the same file, a call through another listed
# function in another file (followed only with --through), a pointer to a
# function kept in data -- and that a stub, a function calling nothing and an
# allowed call stay green. Every name is invented; every body exists only to
# make a reference.
mkdir -p "$WORK/fnf/nolib"
# One sentence per listed function (functions:NAME). The arms below hand
# their names to fn_run, a stand-in for the call site that writes the
# sentences for exactly the names an arm passes, and then runs the runner;
# the arms that test the quotes themselves write a file of their own.
printf 'functions:toy_say\tA sentence for the selftest, standing in for the call site.\n' > "$WORK/fnf/q_say.tsv"
printf 'functions:toy_a\tSentence A, standing in for the call site.\nfunctions:toy_b\tSentence B, standing in for the call site.\n' \
	> "$WORK/fnf/q_ab.tsv"
printf 'functions:toy_a\tSentence A, standing in for the call site.\n' > "$WORK/fnf/q_a.tsv"
printf 'functions:toy_a\tSentence A.\nfunctions:toy_b\tSentence B.\nfunctions:toy_c\tSentence C.\n' > "$WORK/fnf/q_abc.tsv"
printf '#!/bin/sh\nq=$(mktemp "%s/fnf/q.XXXXXX") || exit 2\nprev=\nfor a in "$@"; do\n\t[ "$prev" != --function ] || printf '"'"'functions:%%s\\t%%s\\n'"'"' "${a%%%%=*}" "A sentence for the selftest, standing in for the call site." >> "$q"\n\tprev=$a\ndone\n"%s" "%s/forbidden_symbols.sh" --quotes "$q" "$@"\nst=$?\nrm -f "$q"\nexit $st\n' \
	"$WORK" "$SH" "$TOOLS" > "$WORK/fnf/fn_run.sh"
printf '#include <unistd.h>\n\nint\ttoy_say(int n)\n{\n\treturn ((int)write(1, "", n));\n}\n' \
	> "$WORK/fnf/direct.c"
printf '#include <unistd.h>\n\nstatic int\ttoy_helper(int n)\n{\n\treturn ((int)write(1, "", n));\n}\n\nint\ttoy_wrap(int n)\n{\n\treturn (toy_helper(n));\n}\n' \
	> "$WORK/fnf/helper.c"
printf 'int\ttoy_inner(int n);\n\nint\ttoy_outer(int n)\n{\n\treturn (toy_inner(n));\n}\n' \
	> "$WORK/fnf/outer.c"
printf '#include <unistd.h>\n\nint\ttoy_inner(int n)\n{\n\treturn ((int)write(1, "", n));\n}\n' \
	> "$WORK/fnf/inner.c"
printf 'int\ttoy_none(int n)\n{\n\treturn (n + 1);\n}\n' > "$WORK/fnf/none.c"
printf '#include <unistd.h>\n\nstatic ssize_t\t(*toy_out)(int, const void *, size_t) = write;\n\nint\ttoy_ptr(int n)\n{\n\treturn ((int)toy_out(1, "", n));\n}\n' \
	> "$WORK/fnf/pointer.c"
printf 'int\ttoy_stub(const char *s)\n{\n\t(void)s;\n\treturn (0);\n}\n' > "$WORK/fnf/stub.c"
printf '#include <string.h>\n\nint\ttoy_copy(char *d, char *s)\n{\n\tmemcpy(d, s, 4);\n\treturn (0);\n}\n' \
	> "$WORK/fnf/memcpy.c"
printf '#include <errno.h>\n\nint\ttoy_err(void)\n{\n\treturn (errno);\n}\n' > "$WORK/fnf/errno.c"
printf 'void\ttoy_release(void *p);\n\nvoid\ttoy_user(void *p)\n{\n\ttoy_release(p);\n}\n' \
	> "$WORK/fnf/user.c"
printf '#include <stdlib.h>\n\nvoid\ttoy_release(void *p)\n{\n\tfree(p);\n}\n' > "$WORK/fnf/util.c"
printf '#include <unistd.h>\n\nint\ttoy_a(int n)\n{\n\treturn ((int)write(1, "", n));\n}\n\nint\ttoy_b(int n)\n{\n\treturn ((int)write(2, "", n));\n}\n' \
	> "$WORK/fnf/two.c"
# A name reached through data, at file scope and inside a function, in a file
# whose other function writes the same name on an earlier line.
printf '#include <unistd.h>\n\nint\ttoy_a(int n)\n{\n\treturn ((int)write(1, "", n));\n}\n\nstatic ssize_t\t(*toy_out)(int, const void *, size_t) = write;\n\nint\ttoy_b(int n)\n{\n\treturn ((int)toy_out(1, "", n));\n}\n' \
	> "$WORK/fnf/dataline.c"
printf '#include <unistd.h>\n\nint\ttoy_a(int n)\n{\n\treturn ((int)write(1, "", n));\n}\n\nint\ttoy_b(int n)\n{\n\tstatic ssize_t\t(*out)(int, const void *, size_t) = write;\n\n\treturn ((int)out(1, "", n));\n}\n' \
	> "$WORK/fnf/datalocal.c"
# A listed function, and in another file a static helper of the same name.
printf 'int\ttoy_count(int n)\n{\n\treturn (n + 1);\n}\n' > "$WORK/fnf/named.c"
printf '#include <unistd.h>\n\nstatic int\ttoy_count(int n)\n{\n\treturn ((int)write(1, "", n));\n}\n\nint\ttoy_other(int n)\n{\n\treturn (toy_count(n));\n}\n' \
	> "$WORK/fnf/dupname.c"
# A function whose own code reaches write on a longer road than the one
# through another listed function.
printf 'int\ttoy_end(int n);\nint\ttoy_mid(int n);\n\nstatic int\ttoy_two(int n)\n{\n\treturn (toy_end(n));\n}\n\nstatic int\ttoy_one(int n)\n{\n\treturn (toy_two(n));\n}\n\nint\ttoy_top(int n)\n{\n\treturn (toy_one(n) + toy_mid(n));\n}\n' \
	> "$WORK/fnf/road.c"
printf '#include <unistd.h>\n\nint\ttoy_end(int n)\n{\n\treturn ((int)write(1, "", n));\n}\n\nint\ttoy_mid(int n)\n{\n\treturn (toy_end(n));\n}\n' \
	> "$WORK/fnf/road_end.c"
# A function whose code a section attribute keeps out of a section of its
# own, and a compiler that drops -ffunction-sections, which does the same to
# every function.
printf '#include <unistd.h>\n\nint\ttoy_say(int n) __attribute__((section(".text")));\n\nint\ttoy_say(int n)\n{\n\treturn ((int)write(1, "", n));\n}\n' \
	> "$WORK/fnf/sectioned.c"
printf '#!/bin/sh\nfor a in "$@"; do shift; [ "$a" = -ffunction-sections ] && continue; set -- "$@" "$a"; done\nexec "%s" "$@"\n' \
	"$CC" > "$WORK/fnf/cc_nosections.sh"
chmod +x "$WORK/fnf/cc_nosections.sh"
# A listed name that is a variable's, beside a function: nm lists it as
# defined, and it has no code to walk.
printf 'int\ttoy_say;\n\nint\ttoy_other(void)\n{\n\treturn (toy_say);\n}\n' \
	> "$WORK/fnf/datanamed.c"
# An objdump whose headings come out translated unless LC_ALL=C, as binutils'
# do on a box with its translations installed.
printf '#!/bin/sh\ncase ${LC_ALL:-} in C) exec "%s" "$@" ;; esac\n"%s" "$@" | sed "s/^Disassembly of section /Zerlegung des Abschnitts /"\n' \
	"$OBJDUMP" "$OBJDUMP" > "$WORK/fnf/od_l10n.sh"
chmod +x "$WORK/fnf/od_l10n.sh"
# The runner with the pinned nm and objdump as every call site hands them:
# through fn_run.sh, which writes each listed function's sentence, or
# straight, for an arm that brings its own --quotes. Functions taking "$@":
# a word list split unquoted broke on a path holding a blank or a glob,
# and cost every arm a shellcheck directive. An arm that leaves a pin out,
# or runs under env, spells its command out.
fn_call() {  # fn_call ARG... -- fn_run.sh with the pinned nm and objdump, then ARG...
	"$SH" "$WORK/fnf/fn_run.sh" --nm "$NM" --nm-lib "$NM_LIB" --objdump "$OBJDUMP" --objdump-lib "$NM_LIB" "$@"
}
fnf_sym() {  # fnf_sym ARG... -- forbidden_symbols.sh with the pinned nm, then ARG...
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" "$@"
}
want_red   "forbidden --function: a direct call off the list fails" -- \
	fn_call --function toy_say= --src "$WORK/fnf/direct.c"
want_out   "forbidden --function: ...named at the line that makes it" \
	"    write   (at $WORK/fnf/direct.c:5)" -- \
	fn_call --function toy_say= --src "$WORK/fnf/direct.c"
want_out   "forbidden --function: ...and quoting the call site's sentence" \
	'standing in for the call site' -- \
	fn_call --function toy_say= --src "$WORK/fnf/direct.c"
want_green "forbidden --function: the same call on its list passes" -- \
	fn_call --function toy_say=write --src "$WORK/fnf/direct.c"
want_red   "forbidden --function: a call through a static helper fails" -- \
	fn_call --function toy_wrap=- --src "$WORK/fnf/helper.c"
want_out   "forbidden --function: ...showing the chain" \
	'reached through toy_wrap -> toy_helper -> write' -- \
	fn_call --function toy_wrap=- --src "$WORK/fnf/helper.c"
want_red   "forbidden --function: a pointer to it kept in data fails" -- \
	fn_call --function toy_ptr= --src "$WORK/fnf/pointer.c"
want_out   "forbidden --function: ...through the variable that holds it" \
	'reached through toy_ptr -> toy_out -> write' -- \
	fn_call --function toy_ptr= --src "$WORK/fnf/pointer.c"
want_green "forbidden --function: another listed function is its own (literal)" -- \
	fn_call --function toy_outer= --function toy_inner=write \
		--src "$WORK/fnf/outer.c" --src "$WORK/fnf/inner.c"
want_red   "forbidden --function: ...but counts against the caller with --through" -- \
	fn_call --function toy_outer= --function toy_inner=write \
		--through --src "$WORK/fnf/outer.c" --src "$WORK/fnf/inner.c"
want_out   "forbidden --function: ...across files, chain shown" \
	'reached through toy_outer -> toy_inner -> write' -- \
	fn_call --function toy_outer= --function toy_inner=write \
		--through --src "$WORK/fnf/outer.c" --src "$WORK/fnf/inner.c"
want_out   "forbidden --function: ...saying it is this harness's reading" \
	"this harness's reading" -- \
	fn_call --function toy_outer= --function toy_inner=write \
		--through --src "$WORK/fnf/outer.c" --src "$WORK/fnf/inner.c"
# A red that only the reading makes claims no KO for it: no grader applies
# the reading, so the entry is marked, and the KO is said only of what a
# function's own code reaches -- on any road, however much longer than the
# one through another listed function.
want_out   "forbidden --function: ...marking what only it reaches" \
	'only through another listed function' -- \
	fn_call --function toy_outer= --function toy_inner=write \
		--through --src "$WORK/fnf/outer.c" --src "$WORK/fnf/inner.c"
want_broken_none "forbidden --function: ...and claiming no KO for it" 'outright KO' -- \
	fn_call --function toy_outer= --function toy_inner=write \
		--through --src "$WORK/fnf/outer.c" --src "$WORK/fnf/inner.c"
want_out   "forbidden --function: its own code's use is still a KO" \
	'outright KO' -- \
	fn_call --function toy_top= --function toy_mid=write \
		--through --src "$WORK/fnf/road.c" --src "$WORK/fnf/road_end.c"
want_broken_none "forbidden --function: ...and not marked, on the longer road" \
	'only through another listed function' -- \
	fn_call --function toy_top= --function toy_mid=write \
		--through --src "$WORK/fnf/road.c" --src "$WORK/fnf/road_end.c"
# A static helper named like a listed function in another file is a helper:
# what it uses is its caller's, never the listed function's.
want_green "forbidden --function: a static namesake is not the listed one" -- \
	fn_call --function toy_count= --function toy_other=write \
		--src "$WORK/fnf/named.c" --src "$WORK/fnf/dupname.c"
want_out   "forbidden --function: ...and counts against its caller" \
	'toy_other   may use: none' -- \
	fn_call --function toy_count= --function toy_other= \
		--src "$WORK/fnf/named.c" --src "$WORK/fnf/dupname.c"
# A name reached through data is placed at the data's own definition, or
# nowhere: never at a line where another function names it.
want_out   "forbidden --function: data is placed at its own line" \
	"    write   (at $WORK/fnf/dataline.c:8)" -- \
	fn_call --function toy_a=write --function toy_b= \
		--src "$WORK/fnf/dataline.c"
# Data inside a function is walked too: the arm after these two asks only
# for an absence, which a run that stopped following that data's references
# passed, green and saying OK.
want_red   "forbidden --function: data inside a function still counts against it" -- \
	fn_call --function toy_a=write --function toy_b= \
		--src "$WORK/fnf/datalocal.c"
want_out   "forbidden --function: ...through the data that holds it" \
	'reached through toy_b -> ' -- \
	fn_call --function toy_a=write --function toy_b= \
		--src "$WORK/fnf/datalocal.c"
want_broken_none "forbidden --function: ...and never at another function's" 'datalocal.c:5' -- \
	fn_call --function toy_a=write --function toy_b= \
		--src "$WORK/fnf/datalocal.c"
want_out   "forbidden --function: a red ends on a question" \
	'what does' -- \
	fn_call --function toy_say= --src "$WORK/fnf/direct.c"
# A helper that is not static (the symbols layer reports the missing
# keyword) is still a helper: this check follows it, into another file too,
# and what it uses counts against the function that called it.
want_red   "forbidden --function: a helper that is not static is followed" -- \
	fn_call --function toy_user= \
		--src "$WORK/fnf/user.c" --src "$WORK/fnf/util.c"
want_out   "forbidden --function: ...into its file, chain shown" \
	'reached through toy_user -> toy_release -> free' -- \
	fn_call --function toy_user= \
		--src "$WORK/fnf/user.c" --src "$WORK/fnf/util.c"
# Two functions of one file, one allowed write and one not: the red names the
# line of the one that is not. objdump's headings say which line that is, so
# they are read in the C locale, whatever the caller's.
want_out   "forbidden --function: the line is the function's own" \
	"    write   (at $WORK/fnf/two.c:10)" -- \
	fn_call --function toy_a=write --function toy_b= \
		--src "$WORK/fnf/two.c"
want_out   "forbidden --function: ...also where binutils is translated" \
	"    write   (at $WORK/fnf/two.c:10)" -- \
	env LC_ALL=en_US.UTF-8 "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" \
		--objdump "$WORK/fnf/od_l10n.sh" --objdump-lib "$NM_LIB" --quotes "$WORK/fnf/q_ab.tsv" \
		--function toy_a=write --function toy_b= --src "$WORK/fnf/two.c"
# Each red quotes its own function's sentence, under that function, and a
# function that is green quotes nothing.
want_out   "forbidden --function: a red quotes its own function's sentence" \
	'      Sentence B, standing in for the call site.' -- \
	fnf_sym --objdump "$OBJDUMP" --objdump-lib "$NM_LIB" \
		--quotes "$WORK/fnf/q_ab.tsv" --function toy_a=write --function toy_b= --src "$WORK/fnf/two.c"
want_broken_none "forbidden --function: ...and never a green function's" \
	'Sentence A' -- \
	fnf_sym --objdump "$OBJDUMP" --objdump-lib "$NM_LIB" \
		--quotes "$WORK/fnf/q_ab.tsv" --function toy_a=write --function toy_b= --src "$WORK/fnf/two.c"
want_broken "forbidden --function: a listed function with no sentence is refused" \
	"no line for the key 'functions:toy_b'" -- \
	fnf_sym --objdump "$OBJDUMP" --objdump-lib "$NM_LIB" \
		--quotes "$WORK/fnf/q_a.tsv" --function toy_a=write --function toy_b= --src "$WORK/fnf/two.c"
want_broken "forbidden --function: a sentence for no listed function is refused" \
	"unknown key 'functions:toy_c'" -- \
	fnf_sym --objdump "$OBJDUMP" --objdump-lib "$NM_LIB" \
		--quotes "$WORK/fnf/q_abc.tsv" --function toy_a=write --function toy_b= --src "$WORK/fnf/two.c"
want_green "forbidden --function: an empty list, calling nothing, passes" -- \
	fn_call --function toy_none= --src "$WORK/fnf/none.c"
want_green "forbidden --function: a stub passes, its neighbours unwritten" -- \
	fn_call --function toy_stub=- --function toy_absent=write \
		--through --src "$WORK/fnf/stub.c"
want_out   "forbidden --function: ...noting what it could not check" \
	'toy_absent' -- \
	fn_call --function toy_stub=- --function toy_absent=write \
		--src "$WORK/fnf/stub.c"
# The default mode's forgiveness, no more and no less: a memcpy the compiler
# emitted is nobody's, one the source calls is the function's, and errno is
# judged under the name the student wrote.
want_green "forbidden --function: a compiler-emitted memcpy is tolerated" -- \
	fn_call --function ft_x= --src "$WORK/emitted.c"
want_red   "forbidden --function: ...calling memcpy yourself is not" -- \
	fn_call --function toy_copy= --src "$WORK/fnf/memcpy.c"
want_red   "forbidden --function: ...nor writing it as __builtin_memset" -- \
	fn_call --function ft_x= --src "$WORK/builtin_memset.c"
want_out   "forbidden --function: ...which it says" \
	'written as __builtin_memset' -- \
	fn_call --function ft_x= --src "$WORK/builtin_memset.c"
want_green "forbidden --function: errno passes under glibc's name" -- \
	fn_call --function toy_err=errno --src "$WORK/fnf/errno.c"
want_red   "forbidden --function: ...and is refused off the list" -- \
	fn_call --function toy_err=write --src "$WORK/fnf/errno.c"
# Nothing checked is never a verdict.
want_broken "forbidden --function: no quote is a broken harness" \
	'--quotes FILE is required' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --objdump "$OBJDUMP" --objdump-lib "$NM_LIB" \
		--function toy_say= --src "$WORK/fnf/direct.c"
want_broken "forbidden --function: no objdump is a broken harness" \
	'needs --objdump' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --quotes "$WORK/fnf/q_say.tsv" \
		--function toy_say= --src "$WORK/fnf/direct.c"
# objdump loading libraries from outside --objdump-lib is refused as nm is:
# a copy of the fetched ones on LD_LIBRARY_PATH from outside (V275), with
# nm pinned beside it as every caller pins it (V272). The refusal names the
# copy and never nm's fetched folder, which pin_binutils used to put on
# objdump's path too: each tool is proved under its own directories (V274).
mkdir -p "$WORK/fnf/elsewhere"
cp -L "${NM_LIB%/*}"/lib*.so* "$WORK/fnf/elsewhere/"
want_broken "forbidden --function: objdump loading libraries from outside --objdump-lib is refused" \
	"the pinned objdump loaded '$WORK/fnf/elsewhere/" -- \
	env LD_LIBRARY_PATH="$WORK/fnf/elsewhere" \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --objdump "$OBJDUMP" \
		--objdump-lib "$WORK/fnf/nolib/none" \
		--quotes "$WORK/fnf/q_say.tsv" --function toy_say= --src "$WORK/fnf/direct.c"
# And each tool RUNS under the path it was proved under. With --nm-lib and
# --objdump-lib in two folders, nm proved its own libbfd and then read every
# object with objdump's, which pin_binutils had put ahead of it (V274). An nm
# that records, for each run but the version the proof asks for, which
# libraries the loader gave it (LD_DEBUG_OUTPUT, a file per run).
mkdir -p "$WORK/fnf/libA" "$WORK/fnf/libB" "$WORK/fnf/nmrec"
cp -L "${NM_LIB%/*}"/lib*.so* "$WORK/fnf/libA/"
cp -L "${NM_LIB%/*}"/lib*.so* "$WORK/fnf/libB/"
printf '#!/bin/sh\ncase "$1" in --version) exec "%s" "$@" ;; esac\nLD_DEBUG=libs LD_DEBUG_OUTPUT="%s/fnf/nmrec/ld" exec "%s" "$@"\n' \
	"$NM" "$WORK" "$NM" > "$WORK/fnf/nm_rec.sh"
chmod +x "$WORK/fnf/nm_rec.sh"
fn_nmrec() {  # the run, then the libbfd each of nm's runs loaded
	rm -f "$WORK/fnf/nmrec"/ld.*
	"$SH" "$WORK/fnf/fn_run.sh" --nm "$WORK/fnf/nm_rec.sh" --nm-lib "$WORK/fnf/libA/${NM_LIB##*/}" \
		--objdump "$OBJDUMP" --objdump-lib "$WORK/fnf/libB/${NM_LIB##*/}" \
		--function toy_say=write --src "$WORK/fnf/direct.c" || return
	cat "$WORK/fnf/nmrec"/ld.* 2> /dev/null | grep 'calling init:.*libbfd'
	return 0
}
want_out "forbidden --function: nm runs on the libbfd of its own --nm-lib" \
	"$WORK/fnf/libA/" -- fn_nmrec
want_broken_none "forbidden --function: ...never on --objdump-lib's" \
	"$WORK/fnf/libB/" -- fn_nmrec
want_broken "forbidden --function: a list that is not NAME=CSV is refused" \
	'NAME=CSV' -- \
	fn_call --function toy_say --src "$WORK/fnf/direct.c"
want_broken "forbidden --function: --allowed is the default mode's" \
	'belong to the default mode' -- \
	fn_call --function toy_say= --allowed - \
		--src "$WORK/fnf/direct.c"
want_broken "forbidden --function: a source that does not compile is not a red" \
	'failed to compile' -- \
	fn_call --function broken= --src "$WORK/standin/broken.c"
# A function nm sees defined, whose code has no section of its own, was never
# walked: refused, never the green's "not checked".
want_broken "forbidden --function: a function with no section of its own is refused" \
	'no section' -- \
	fn_call --function toy_say= --src "$WORK/fnf/sectioned.c"
want_broken "forbidden --function: ...as is a compile without -ffunction-sections" \
	'no section' -- \
	env FORBIDDEN_CC="$WORK/fnf/cc_nosections.sh" "$SH" "$WORK/fnf/fn_run.sh" --nm "$NM" --nm-lib "$NM_LIB" \
		--objdump "$OBJDUMP" --objdump-lib "$NM_LIB" --function toy_say= --src "$WORK/fnf/direct.c"
want_broken "forbidden --function: ...and a listed name that is a variable's, said so" \
	'a variable of that name has no code' -- \
	fn_call --function toy_say= --function toy_other= \
		--src "$WORK/fnf/datanamed.c"

# WHICH <ctype.h> CLASSIFIER, LINE BY LINE, FROM A FOLDER REACHED BY A
# SYMBOLIC LINK. A __ctype_b_loc reference is matched to the classifier on
# its own line by FILE:LINE, objdump's spelling of the place against the
# preprocessor's, each cut of the folder ($PWD, or `pwd -P` where a link
# leads there) and of a leading ./ the same way; where the two spell it
# apart, the reference falls back to every classifier of its source, and
# two functions, each allowed its own classifier only, then name each
# other's. Here one is written in a header found by `-I .`, read from a
# folder whose logical and physical paths differ.
mkdir -p "$WORK/fnf/real"
ln -sfn "$WORK/fnf/real" "$WORK/fnf/lnk"
printf '#include <ctype.h>\n\nstatic int\ttoy_alpha(int c)\n{\n\treturn (isalpha(c));\n}\n' \
	> "$WORK/fnf/real/toy_is.h"
printf '#include <ctype.h>\n#include "toy_is.h"\n\nint\ttoy_a(int c)\n{\n\treturn (toy_alpha(c));\n}\n\nint\ttoy_b(int c)\n{\n\treturn (isdigit(c));\n}\n' \
	> "$WORK/fnf/real/lines.c"
fnl_abs() { case $1 in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }
_fnl_sh=$SH
case "$SH" in */*) _fnl_sh=$(fnl_abs "$SH") ;; esac
_fnl_tools=$(fnl_abs "$TOOLS") _fnl_nm=$(fnl_abs "$NM") _fnl_nmlib=$(fnl_abs "$NM_LIB")
_fnl_od=$(fnl_abs "$OBJDUMP")
fnl_run() {  # forbidden_symbols.sh --function from the linked folder, sources named relatively
	(
		cd "$WORK/fnf/lnk" || exit 2
		"$_fnl_sh" "$_fnl_tools/forbidden_symbols.sh" --nm "$_fnl_nm" --nm-lib "$_fnl_nmlib" \
			--objdump "$_fnl_od" --objdump-lib "$_fnl_nmlib" --quotes "$WORK/fnf/q_ab.tsv" \
			--function toy_a=isalpha --function toy_b=isdigit --hdr ./toy_is.h --src lines.c
	)
}
want_green "forbidden --function: each function's classifier read off its own line, through a link" -- \
	fnl_run
# THE <ctype.h> CLASSIFIERS, PER FUNCTION, each way the default mode's arms
# (forbidden_symbols section) judge them for the whole turn-in: the
# classifier on the reference's own line, allowed or not, and two on one
# line; with no class constant on the line, every classifier its source
# uses; a classifier the turn-in defines is none of glibc's; an alias
# behind a #define; and no classifier by name at all, the family.
printf '#include <ctype.h>\n\nint\ttoy_say(int c)\n{\n\treturn (isalpha(c));\n}\n' > "$WORK/fnf/cl_alpha.c"
printf '#include <ctype.h>\n\nint\ttoy_say(int c)\n{\n\treturn (isdigit(c) + isalpha(c));\n}\n' > "$WORK/fnf/cl_both.c"
printf '#include <ctype.h>\n\nint\ttoy_a(int c)\n{\n\treturn ((*__ctype_b_loc())[c] & 8);\n}\n\nint\ttoy_b(int c)\n{\n\treturn (isalpha(c));\n}\n' \
	> "$WORK/fnf/cl_hand.c"
printf '#include <ctype.h>\n\nint\ttoy_say(int c)\n{\n\treturn ((*__ctype_b_loc())[c] & 8);\n}\n' > "$WORK/fnf/cl_direct.c"
printf '#include <ctype.h>\n#define TOY_ALPHA isalpha\n\nint\ttoy_say(int c)\n{\n\treturn (TOY_ALPHA(c));\n}\n' \
	> "$WORK/fnf/cl_macro.c"
printf 'int\tisdigit(int c)\n{\n\treturn (c >= 48 && c <= 57);\n}\n' > "$WORK/fnf/cl_own.c"
printf '#include <ctype.h>\n\nint\ttoy_say(int c)\n{\n\treturn (isdigit(c));\n}\n' > "$WORK/fnf/cl_digit.c"
want_green "forbidden --function: a classifier on its list passes" -- \
	fn_call --function toy_say=isalpha --src "$WORK/fnf/cl_alpha.c"
want_out   "forbidden --function: ...saying which classifier the object's name is" \
	'(toy_say: the object names __ctype_b_loc, which is isalpha)' -- \
	fn_call --function toy_say=isalpha --src "$WORK/fnf/cl_alpha.c"
want_out   "forbidden --function: one off its list is named at its line" \
	"    isalpha   (at $WORK/fnf/cl_alpha.c:5)" -- \
	fn_call --function toy_say=isdigit --src "$WORK/fnf/cl_alpha.c"
want_out   "forbidden --function: ...and seen in the object as the shared name" \
	'seen in the object as __ctype_b_loc' -- \
	fn_call --function toy_say=isdigit --src "$WORK/fnf/cl_alpha.c"
want_out   "forbidden --function: two on one line, the one off its list named" \
	"    isalpha   (at $WORK/fnf/cl_both.c:5)" -- \
	fn_call --function toy_say=isdigit --src "$WORK/fnf/cl_both.c"
want_broken_none "forbidden --function: ...never the one on it" \
	'    isdigit   (at' -- \
	fn_call --function toy_say=isdigit --src "$WORK/fnf/cl_both.c"
want_out   "forbidden --function: no class constant on the line reads its source's" \
	"    isalpha   (at $WORK/fnf/cl_hand.c:5)" -- \
	fn_call --function toy_a=isdigit --function toy_b=isalpha --src "$WORK/fnf/cl_hand.c"
want_out   "forbidden --function: no classifier by name is the family" \
	'a <ctype.h> classifier' -- \
	fn_call --function toy_say=isdigit --src "$WORK/fnf/cl_direct.c"
want_red   "forbidden --function: an alias behind a #define is judged" -- \
	fn_call --function toy_say=isdigit --src "$WORK/fnf/cl_macro.c"
want_out   "forbidden --function: ...as the classifier it stands for" \
	"    isalpha   (at $WORK/fnf/cl_macro.c:" -- \
	fn_call --function toy_say=isdigit --src "$WORK/fnf/cl_macro.c"
want_out   "forbidden --function: a classifier the turn-in defines is not glibc's" \
	'a <ctype.h> classifier' -- \
	fn_call --function toy_say=isalpha --function isdigit=- --src "$WORK/fnf/cl_digit.c" --src "$WORK/fnf/cl_own.c"
want_broken_none "forbidden --function: ...and is never named as one" \
	'    isdigit   (at' -- \
	fn_call --function toy_say=isalpha --function isdigit=- --src "$WORK/fnf/cl_digit.c" --src "$WORK/fnf/cl_own.c"
