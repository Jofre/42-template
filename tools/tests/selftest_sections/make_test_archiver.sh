# ------------------------------------------------------------------ make_test archiver
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# --archiver, --forbidden-command and --forbidden-flag: what makes the
# artifact, and what a recipe may not run or pass, read from what `make -n`
# plans and from what the tools' stand-ins log, never from the Makefile's
# text. A toy subject's sentences. Every fixture compiles its two toy
# sources with mkfake's cc, and its bin/ goes first on PATH, so the ar a
# recipe runs by name is the fixture's own stand-in, and no host tool is
# needed. Its Makefile lines spell no stock line (cda67117): every one names
# the toy library or a toy source, or a variable of this file's own. Its
# trees are its own (a shard runs some sections' arms only).
MKAQ="$WORK/mkarquotes"
mkdir -p "$MKAQ"
{
	printf 'archiver\tToy, p.4: "Make the library with ar."\n'
	printf 'forbidden_command\tToy, p.4: "Never run libtool."\n'
	printf 'forbidden_flag\tToy, p.4: "Never compile with -std=c99."\n'
} > "$MKAQ/ar.tsv"
# mkar DIR LIB-RECIPE [EXTRA-A [HEAD]]: two compiles (EXTRA-A on sel_a's),
# then LIB-RECIPE for the library; HEAD goes first in the file.
mkar() {
	mkfake "$1"
	printf '%s\n' '#!/bin/sh' \
		'# The selftest'"'"'s stand-in archiver: a key, the archive, its members.' \
		'# Long options first (--plugin X), a RELPOS after a key with a, b or i' \
		'# in it, a COUNT after one with N. A key with no r or q in it (t: list)' \
		'# writes nothing.' \
		'while :; do case "$1" in --plugin | --target) shift 2 ;; --*) shift ;; *) break ;; esac; done' \
		'case "$1" in *r* | *q*) ;; *) exit 0 ;; esac' \
		'_k=$1' 'shift' \
		'case "$_k" in *[abi]*) shift ;; esac' 'case "$_k" in *N*) shift ;; esac' \
		'_a=$1' 'shift' 'printf "!<arch>\n" > "$_a"' 'cat "$@" >> "$_a"' \
		> "$WORK/$1/bin/ar"
	printf '%s\n' '#!/bin/sh' \
		'# The selftest'"'"'s stand-in for a tool no recipe may run: writes -o.' \
		'while [ $# -gt 0 ]; do' '	case "$1" in -o) : > "$2"; shift 2 ;; *) shift ;; esac' 'done' \
		> "$WORK/$1/bin/libtool"
	chmod +x "$WORK/$1/bin/ar" "$WORK/$1/bin/libtool"
	{
		printf '%b' "${4:-}"
		printf 'all: libselftest.a\n'
		printf 'libselftest.a: sel_a.o sel_b.o\n\t%s\n' "$2"
		printf 'sel_a.o: sel_a.c\n\tcc -Wall -Wextra -Werror %s -c sel_a.c -o sel_a.o\n' "${3:-}"
		printf 'sel_b.o: sel_b.c\n\tcc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n'
	} > "$WORK/$1/Makefile"
}
mka() {  # mka DIR [FLAG...]: the three checks, with DIR/bin first on PATH
	_d=$1
	shift
	once env PATH="$WORK/$_d/bin:$PATH" "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" \
		--quotes "$MKAQ/ar.tsv" --archiver ar --forbidden-command libtool \
		--forbidden-flag -std=c99 --build-target selftest_build "$@" \
		--anchor "$WORK/$_d/Makefile" --artifact libselftest.a
}
mkar mkar_rcs 'ar rcs libselftest.a sel_a.o sel_b.o'
mkar mkar_dash 'ar -rcs libselftest.a sel_a.o sel_b.o'
mkar mkar_var '$(AR) $(ARFLAGS) libselftest.a sel_a.o sel_b.o'
mkar mkar_loop 'for sel_o in sel_a.o sel_b.o; do ar crs libselftest.a $$sel_o; done'
mkar mkar_chain 'rm -f libselftest.a && ar crs libselftest.a sel_a.o sel_b.o'
mkar mkar_shell "sh -c 'ar rcs libselftest.a sel_a.o sel_b.o'"
mkar mkar_abs '$(CURDIR)/bin/ar rcs libselftest.a sel_a.o sel_b.o'
mkar mkar_shvar 'sel_lib=libselftest.a; ar rcs $$sel_lib sel_a.o sel_b.o'
mkar mkar_c11 'ar rcs libselftest.a sel_a.o sel_b.o' -std=c11
mkar mkar_gnu99 'ar rcs libselftest.a sel_a.o sel_b.o' -std=gnu99
want_green "make_test --archiver: ar rcs makes the library" -- mka mkar_rcs
want_out   "make_test --archiver: ...and says what it judged" \
	"'libselftest.a' is made by ar" -- mka mkar_rcs
want_out   "make_test --forbidden-command: ...and that libtool never ran" \
	"no command a bare 'make' runs is libtool" -- mka mkar_rcs
want_out   "make_test --forbidden-flag: ...nor -std=c99, over both compiles" \
	"none of the 2 compile command(s) a bare 'make' runs passes -std=c99" -- mka mkar_rcs
want_green "make_test --archiver: ar -rcs, a dash before the key" -- mka mkar_dash
want_green "make_test --archiver: \$(AR) \$(ARFLAGS), make's own default" -- mka mkar_var
want_green "make_test --archiver: ar in a shell loop" -- mka mkar_loop
want_green "make_test --archiver: ar after && in a chain" -- mka mkar_chain
want_green "make_test --archiver: ar inside sh -c" -- mka mkar_shell
want_green "make_test --archiver: ar by an absolute path" -- mka mkar_abs
# The library's name in a shell variable: the plan shows $sel_lib, and only
# the stand-in's log of what the shell made of it names the library.
want_green "make_test --archiver: the library named by a shell variable" -- mka mkar_shvar
want_green "make_test --forbidden-flag: -std=c11 is another flag" -- mka mkar_c11
want_green "make_test --forbidden-flag: -std=gnu99 is another flag" -- mka mkar_gnu99
# The box's own ar by its path, where this box has one there: what is
# judged is the command word less its path, whichever ar it is.
mkar mkar_usr '/usr/bin/ar rcs libselftest.a sel_a.o sel_b.o'
if [ -x /usr/bin/ar ]; then
	want_green "make_test --archiver: /usr/bin/ar is ar" -- mka mkar_usr
else
	st_skipped "make_test --archiver: /usr/bin/ar is ar" \
		"skipped (this box has no /usr/bin/ar; mkar_abs proves a path)"
fi
# The library made by another tool: copied, or written by a redirection.
mkar mkar_cp 'cat sel_a.o sel_b.o > sel_tmp.bin && cp sel_tmp.bin libselftest.a'
mkar mkar_cat 'cat sel_a.o sel_b.o > libselftest.a'
want_red   "make_test --archiver: a library cp made fails" -- mka mkar_cp
want_out   "make_test --archiver: ...saying it was not made with ar" \
	"but not with ar" -- mka mkar_cp
want_out   "make_test --archiver: ...naming the tool that names it" '(cp)' -- mka mkar_cp
want_out   "make_test --archiver: ...quoting the call site's sentence" \
	'Toy, p.4: "Make the library with ar."' -- mka mkar_cp
want_red   "make_test --archiver: a library a redirection wrote fails" -- mka mkar_cat
want_out   "make_test --archiver: ...naming the command" '(cat)' -- mka mkar_cat
# What every reading agrees on, and no more: an archive ar wrote under
# another name, or in another directory, and cp or mv then put in place, is
# one ar made on one reading and not on another, so it is not failed here.
# ./ before the name is the same file. And `command -v libtool` runs nothing.
mkar mkar_dot 'ar rcs ./libselftest.a sel_a.o sel_b.o'
mkar mkar_mv 'ar rcs sel_tmp.a sel_a.o sel_b.o && mv sel_tmp.a libselftest.a'
mkar mkar_probe 'command -v libtool > /dev/null; ar rcs libselftest.a sel_a.o sel_b.o'
want_green "make_test --archiver: ./ before the library's name" -- mka mkar_dot
want_green "make_test --archiver: an archive ar wrote, moved in place by mv" -- mka mkar_mv
want_green "make_test --forbidden-command: command -v libtool runs no libtool" -- mka mkar_probe
# libtool, a stand-in in the fixture called by its path: wherever a recipe
# runs it, beside ar or in its place.
mkar mkar_libtool './bin/libtool -static -o libselftest.a sel_a.o sel_b.o'
mkar mkar_libtool_too 'ar rcs libselftest.a sel_a.o sel_b.o && ./bin/libtool -static -o sel_more.a sel_a.o'
want_red   "make_test --forbidden-command: libtool making the library fails" -- \
	mka mkar_libtool
want_out   "make_test --forbidden-command: ...named" '(libtool)' -- mka mkar_libtool
want_out   "make_test --forbidden-command: ...quoting the call site's sentence" \
	'Toy, p.4: "Never run libtool."' -- mka mkar_libtool
want_red   "make_test --forbidden-command: ...and beside ar too" -- mka mkar_libtool_too
want_broken_none "make_test --forbidden-command: ...where ar is not what is blamed" \
	'but not with ar' -- mka mkar_libtool_too
# -std=c99, written on the compile line, or through a variable make expands
# (an implicit rule's CPPFLAGS among them).
mkar mkar_c99 'ar rcs libselftest.a sel_a.o sel_b.o' -std=c99
mkar mkar_c99var 'ar rcs libselftest.a sel_a.o sel_b.o' '$(SEL_STD)' 'SEL_STD = -std=c99\n'
mkfake mkar_c99imp
cp "$WORK/mkar_rcs/bin/ar" "$WORK/mkar_c99imp/bin/ar"
{
	printf 'CPPFLAGS = -std=c99\nall: libselftest.a\n'
	printf 'libselftest.a: sel_a.o sel_b.o\n\tar rcs libselftest.a sel_a.o sel_b.o\n'
} > "$WORK/mkar_c99imp/Makefile"
want_red   "make_test --forbidden-flag: -std=c99 on the compile line fails" -- mka mkar_c99
want_out   "make_test --forbidden-flag: ...one compile of the two" \
	'1 of the 2 compile command(s)' -- mka mkar_c99
want_out   "make_test --forbidden-flag: ...naming the flag" '(-std=c99)' -- mka mkar_c99
want_out   "make_test --forbidden-flag: ...quoting the call site's sentence" \
	'Toy, p.4: "Never compile with -std=c99."' -- mka mkar_c99
want_red   "make_test --forbidden-flag: ...and through a variable" -- mka mkar_c99var
want_red   "make_test --forbidden-flag: ...and through an implicit rule's CPPFLAGS" -- \
	mka mkar_c99imp
want_out   "make_test --forbidden-flag: ...both of its compiles" \
	'2 of the 2 compile command(s)' -- mka mkar_c99imp
# A stub builds nothing, and that is what it is told: none of the three
# speaks before there is a library.
mkdir -p "$WORK/mkar_stub"
printf 'all:\n\techo selftest stub\n' > "$WORK/mkar_stub/Makefile"
want_red   "make_test --archiver: a stub is red, as before" -- mka mkar_stub
want_out   "make_test --archiver: ...for building nothing" 'It created no file at all' -- \
	mka mkar_stub
want_broken_none "make_test --archiver: ...and not for how it would make it" 'libtool' -- \
	mka mkar_stub
# Each check quotes its sentence, or is refused.
printf 'cc\tToy, p.3: "Compile with cc."\n' > "$MKAQ/ar_none.tsv"
want_broken "make_test --archiver: no sentence for it is refused" "'archiver' sentence" -- \
	mt --rules "" --quotes "$MKAQ/ar_none.tsv" --archiver ar \
		--anchor "$WORK/mkar_rcs/Makefile" --artifact libselftest.a
want_broken "make_test --forbidden-command: no sentence for it is refused" \
	"'forbidden_command' sentence" -- \
	mt --rules "" --quotes "$MKAQ/ar_none.tsv" --forbidden-command libtool \
		--anchor "$WORK/mkar_rcs/Makefile" --artifact libselftest.a
want_broken "make_test --forbidden-flag: no sentence for it is refused" \
	"'forbidden_flag' sentence" -- \
	mt --rules "" --quotes "$MKAQ/ar_none.tsv" --forbidden-flag -std=c99 \
		--anchor "$WORK/mkar_rcs/Makefile" --artifact libselftest.a
want_broken "make_test --archiver: a path is no command's name" 'no path or blank' -- \
	mt --rules "" --quotes "$MKAQ/ar.tsv" --archiver /usr/bin/ar \
		--anchor "$WORK/mkar_rcs/Makefile" --artifact libselftest.a
want_broken "make_test --forbidden-flag: a flag starts with -" 'starting with -' -- \
	mt --rules "" --quotes "$MKAQ/ar.tsv" --forbidden-flag std=c99 \
		--anchor "$WORK/mkar_rcs/Makefile" --artifact libselftest.a
want_broken "make_test --archiver: ...nor one it forbids as well" \
	'both the --archiver and a --forbidden-command' -- \
	mt --rules "" --quotes "$MKAQ/ar.tsv" --archiver ar --forbidden-command ar \
		--anchor "$WORK/mkar_rcs/Makefile" --artifact libselftest.a
# A command that only runs another (ccache, env ...) is read through to the
# one it runs, every time, so its own name is never a command word:
# forbidding it, or naming it the archiver, would judge nothing and is
# refused. The Makefile does run ccache, through a stand-in of its own that
# runs the rest. A shell is read through only given -c, so its name is not
# refused: `bash build.sh` is a call of bash, which a forbidden bash catches,
# and `sh -c '...'` is the command line it runs, judged in its place.
mkar mkar_ccache 'ccache ar rcs libselftest.a sel_a.o sel_b.o'
printf '%s\n' '#!/bin/sh' '# The selftest'"'"'s stand-in wrapper: runs the rest.' 'exec "$@"' \
	> "$WORK/mkar_ccache/bin/ccache"
chmod +x "$WORK/mkar_ccache/bin/ccache"
want_broken "make_test --forbidden-command: a wrapper it reads through is refused" \
	'reads through' -- mka mkar_ccache --forbidden-command ccache
want_broken "make_test --forbidden-command: ...env as well" 'reads through' -- \
	mka mkar_ccache --forbidden-command env
mkar mkar_bash 'bash build.sh'
printf '%s\n' 'ar rcs libselftest.a sel_a.o sel_b.o' > "$WORK/mkar_bash/build.sh"
want_red "make_test --forbidden-command: a shell run on a script is a call of it, judged" -- \
	mka mkar_bash --forbidden-command bash
want_out "make_test --forbidden-command: ...and named" '(bash)' -- \
	mka mkar_bash --forbidden-command bash
want_green "make_test --forbidden-command: ...but sh -c is read through to what it runs" -- \
	mka mkar_shell --forbidden-command sh
want_broken "make_test --archiver: ...and a wrapper is no archiver either" 'reads through' -- \
	mka mkar_ccache --archiver env
# Both lists repeat: a second flag, a second command, each judged.
want_red   "make_test --forbidden-flag: a second flag is judged too" -- \
	mka mkar_c11 --forbidden-flag -std=c11
want_out   "make_test --forbidden-flag: ...and named" '(-std=c11)' -- \
	mka mkar_c11 --forbidden-flag -std=c11
want_red   "make_test --forbidden-command: a second command is judged too" -- \
	mka mkar_mv --forbidden-command mv
want_out   "make_test --forbidden-command: ...and named" '(mv)' -- \
	mka mkar_mv --forbidden-command mv
mkdir -p "$WORK/mkar_script"
printf '#!/bin/sh\n: > libselftest.a\n' > "$WORK/mkar_script/sel_build.sh"
want_broken "make_test --archiver: a creator script has no plan to read" \
	'names a creator script' -- \
	mt --quotes "$MKAQ/ar.tsv" --archiver ar --anchor "$WORK/mkar_script/sel_build.sh" \
		--artifact libselftest.a --script sel_build.sh

# A # that starts a word starts the shell's comment, and make prints it with
# the line: neither a command named in it nor an ar named in it is one. In
# a word it is a character like any (an ar by its path, which no stand-in
# logs, so the plan is the only record). And the newline a backslash
# continues into ends the comment: the shell runs what follows.
mkar mkar_cmt 'ar rcs libselftest.a sel_a.o sel_b.o	# sel: (libtool stays out of this)'
mkar mkar_cmtcat 'cat sel_a.o sel_b.o > libselftest.a # sel: (ar rcs libselftest.a once)'
mkar mkar_cmtnl "$(printf 'ar rcs libselftest.a sel_a.o sel_b.o # sel note \\\n\t./bin/libtool -static -o sel_more.a sel_a.o')"
mkar mkar_hash 'echo sel_x#y && ./bin/ar rcs libselftest.a sel_a.o sel_b.o'
want_green "make_test --forbidden-command: libtool in a comment is not run" -- mka mkar_cmt
want_red   "make_test --archiver: ar in a comment makes no library" -- mka mkar_cmtcat
want_out   "make_test --archiver: ...the cat beside it does" '(cat)' -- mka mkar_cmtcat
want_red   "make_test --forbidden-command: a comment ends where its line does" -- \
	mka mkar_cmtnl
want_out   "make_test --forbidden-command: ...and the next line runs" '(libtool)' -- \
	mka mkar_cmtnl
want_green "make_test --archiver: a # inside a word starts no comment" -- mka mkar_hash
# The sentence about cc beside the three, for the arms that judge compiles.
{ cat "$MKAQ/ar.tsv"; printf 'cc\tToy, p.3: "Compile with cc."\n'; } > "$MKAQ/arcc.tsv"
mkfake mkar_cccmt
{
	printf 'all: libselftest.a\n'
	printf 'libselftest.a: sel_a.o sel_b.o\n\t./bin/cc -o libselftest.a sel_a.o sel_b.o\n'
	printf 'sel_a.o: sel_a.c\n\t./bin/cc -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n'
	printf 'sel_b.o: sel_b.c\n\t./bin/cc -Wall -c sel_b.c -o sel_b.o # sel: -Wextra -Werror\n'
} > "$WORK/mkar_cccmt/Makefile"
want_red   "make_test --recipe-cc: a flag in a comment is not passed" -- \
	mt --rules "" --recipe-cc any --quotes "$MKAQ/arcc.tsv" --build-target selftest_build \
		--anchor "$WORK/mkar_cccmt/Makefile" --artifact libselftest.a
want_out   "make_test --recipe-cc: ...the compile is missing it" 'no -Wextra -Werror' -- \
	mt --rules "" --recipe-cc any --quotes "$MKAQ/arcc.tsv" --build-target selftest_build \
		--anchor "$WORK/mkar_cccmt/Makefile" --artifact libselftest.a
# The archive is the operand ar writes, never a member, and a key that
# writes nothing (t) makes nothing. An archive staged in another directory
# and copied in place is one file spelled two ways: by its last component.
mkar mkar_member 'ar rcs sel_other.a sel_a.o && cp sel_a.o libselftest.a'
mkar mkar_tkey 'cat sel_a.o sel_b.o > libselftest.a && ar t libselftest.a'
mkar mkar_cpdir 'mkdir -p sel_dir && ar rcs sel_dir/sel_stage.a sel_a.o sel_b.o && cp ./sel_dir/sel_stage.a libselftest.a'
mkar mkar_cdcp 'mkdir -p sel_dir && cd sel_dir && ar rcs sel_stage.a ../sel_a.o ../sel_b.o; cd .. && cp sel_dir/sel_stage.a libselftest.a'
want_red   "make_test --archiver: an ar member copied in place fails" -- mka mkar_member
want_out   "make_test --archiver: ...as not made with ar" 'but not with ar' -- mka mkar_member
want_red   "make_test --archiver: ar t on the library made nothing" -- mka mkar_tkey
want_green "make_test --archiver: an archive staged in a folder, copied" -- mka mkar_cpdir
want_green "make_test --archiver: ...or made in it after a cd" -- mka mkar_cdcp
# $(info ...) prints to the stream the plan is read from: a line of it is
# no command, either way, where the build that ran to its end logged no
# such call. And an ar line a target's own PATH runs past the stand-in --
# its archive written, by nothing else the plan shows -- stays a command.
mkar mkar_infolt 'ar rcs libselftest.a sel_a.o sel_b.o' '' '$(info libtool stays out of sel)\n'
mkar mkar_infoar 'cat sel_a.o sel_b.o > libselftest.a' '' '$(info ar rcs libselftest.a for sel)\n'
mkar mkar_tpath 'ar rcs libselftest.a sel_a.o sel_b.o' '' \
	'sel_first: sel_a.o sel_b.o libselftest.a\nlibselftest.a: export PATH := $(CURDIR)/bin:$(PATH)\n'
want_green "make_test --forbidden-command: \$(info libtool ...) is no call" -- mka mkar_infolt
want_out   "make_test --forbidden-command: ...and is named as text" \
	"read like a call of" -- mka mkar_infolt
want_red   "make_test --archiver: \$(info ar ...) makes no library" -- mka mkar_infoar
want_green "make_test --archiver: ar run past the stand-in still counts" -- mka mkar_tpath
# A name only the shell spells out: the stand-in logs it, on PATH or not
# (this fixture has no libtool), so the verdict is not the host's.
mkar mkar_hidlt 'ar rcs libselftest.a sel_a.o sel_b.o; sel_t=libtool; $$sel_t -static -o sel_more.a sel_a.o'
rm -f "$WORK/mkar_hidlt/bin/libtool"
want_red   "make_test --forbidden-command: libtool from a shell variable" -- mka mkar_hidlt
want_out   "make_test --forbidden-command: ...shown as the shell ran it" \
	'    libtool -static -o sel_more.a sel_a.o' -- mka mkar_hidlt
# A forbidden name that is a compiler's keeps the compiler's own stand-in,
# so the compile it hides is still judged against the sentence about cc.
mkfake mkar_gcc
cp "$WORK/mkar_rcs/bin/ar" "$WORK/mkar_gcc/bin/ar"
{
	printf 'all: libselftest.a\n'
	printf 'libselftest.a: sel_a.o sel_b.o\n\tar rcs libselftest.a sel_a.o sel_b.o\n'
	printf 'sel_a.o: sel_a.c\n\tsel_c=gcc; $$sel_c -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n'
	printf 'sel_b.o: sel_b.c\n\tcc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n'
} > "$WORK/mkar_gcc/Makefile"
want_out   "make_test --forbidden-command gcc: its compile is still judged" 'gcc, not cc' -- \
	mka mkar_gcc --quotes "$MKAQ/arcc.tsv" --forbidden-command gcc --recipe-cc any
mkar mkar_noname 'for sel_f in libselftest; do cat sel_a.o sel_b.o > $$sel_f.a; done'
want_out   "make_test --archiver: a library no command names, said so" \
	'that a build ran names it either' -- mka mkar_noname
# A RELPOS (the member a, b or i inserts beside) and a --plugin's value come
# before the archive, and neither is it. (A COUNT, N, too; ar takes N only
# with keys that write no archive, so no arm makes one.)
mkar mkar_relpos 'ar rcsb sel_zz.o libselftest.a sel_a.o sel_b.o'
mkar mkar_plugin 'ar --plugin sel_plug.so rcs libselftest.a sel_a.o sel_b.o'
want_green "make_test --archiver: a RELPOS is not the archive" -- mka mkar_relpos
want_green "make_test --archiver: nor is the value of --plugin" -- mka mkar_plugin
# A Makefile that puts a folder of its own first on PATH, for every rule,
# runs libtool past its stand-in -- which logs nothing -- while cc still
# reaches its own: that stand-in records the bypass, and the plan's line is
# a call, not text.
mkar mkar_pathlt "$(printf 'ar rcs libselftest.a sel_a.o sel_b.o\n\tlibtool -static -o sel_more.a sel_a.o')" \
	'' 'export PATH := $(CURDIR)/sel_tl:$(PATH)\n'
mkdir -p "$WORK/mkar_pathlt/sel_tl"
mv "$WORK/mkar_pathlt/bin/libtool" "$WORK/mkar_pathlt/sel_tl/libtool"
want_red   "make_test --forbidden-command: libtool past its stand-in" -- mka mkar_pathlt
want_out   "make_test --forbidden-command: ...is named" '(libtool)' -- mka mkar_pathlt
# A build that stopped before a line ran never logged it: that line is
# still a command, not text (a phantom needs a build that ran to its end).
mkar mkar_stopped "$(printf 'ar rcs libselftest.a sel_a.o sel_b.o\n\tfalse\n\tlibtool -static -o sel_more.a sel_a.o')"
want_out   "make_test --forbidden-command: a line a stopped build never ran" \
	'(libtool)' -- mka mkar_stopped
# A word with a ' in it is logged as the shell would quote it, and reads
# back as the word the plan shows: the call that ran is no text.
mkar mkar_apos "$(printf '%s\n\t%s' 'ar rcs libselftest.a sel_a.o sel_b.o' \
	'libtool -static -o sel_more.a "sel_x'"'"'s.o"')"
want_red   "make_test --forbidden-command: a call with a ' in a word" -- mka mkar_apos
want_broken_none "make_test --forbidden-command: ...is a call, not text" \
	'read like a call of' -- mka mkar_apos
want_out   "make_test --forbidden-command: ...shown as it ran" \
	"    libtool -static -o sel_more.a 'sel_x'\\''s.o'" -- mka mkar_apos
# Text whose tool word is not the first of its line: each command of a
# line is judged, not the line's first word.
mkar mkar_infosemi 'ar rcs libselftest.a sel_a.o sel_b.o' '' '$(info [sel] archiving; libtool is never used here)\n'
want_green "make_test --forbidden-command: \$(info x; libtool ...) is text" -- mka mkar_infosemi
want_out   "make_test --forbidden-command: ...and is named as text" \
	'[sel] archiving; libtool is never used here' -- mka mkar_infosemi
# ...but a PATH set on the line itself may run it past the stand-in.
mkar mkar_linepath "$(printf 'ar rcs libselftest.a sel_a.o sel_b.o\n\tPATH=$(CURDIR)/sel_tl:$$PATH; libtool -static -o sel_more.a sel_a.o')"
mkdir -p "$WORK/mkar_linepath/sel_tl"
mv "$WORK/mkar_linepath/bin/libtool" "$WORK/mkar_linepath/sel_tl/libtool"
want_red   "make_test --forbidden-command: libtool after PATH= on its line" -- mka mkar_linepath
# A call in a branch of the shell the build did not take is still a
# call: on another box the branch may be taken (a test of uname), so it is
# never set aside as text. Every arm here takes no branch on any box, and
# its build returns 0 (a false && last would fail it, and a build that
# failed sets nothing aside). A plain ; is no branch (mkar_infosemi), and a
# line that closes what it opens leaves the next line as it was.
mkar mkar_iffalse "$(printf 'ar rcs libselftest.a sel_a.o sel_b.o\n\tif false; then libtool -static -o sel_more.a sel_a.o; fi')"
mkar mkar_ortrue "$(printf 'ar rcs libselftest.a sel_a.o sel_b.o\n\ttrue || libtool -static -o sel_more.a sel_a.o')"
mkar mkar_andnull "$(printf 'ar rcs libselftest.a sel_a.o sel_b.o\n\t[ -n "" ] && libtool -static -o sel_more.a sel_a.o; true')"
mkar mkar_caseno "$(printf 'ar rcs libselftest.a sel_a.o sel_b.o\n\tcase sel_x in sel_y) libtool -static -o sel_more.a sel_a.o ;; esac')"
mkar mkar_oneshell "$(printf 'ar rcs libselftest.a sel_a.o sel_b.o\n\tif false; then\n\tlibtool -static -o sel_more.a sel_a.o\n\tfi')" \
	'' '.ONESHELL:\n'
want_red   "make_test --forbidden-command: libtool in an if not taken" -- mka mkar_iffalse
want_out   "make_test --forbidden-command: ...is named" '(libtool)' -- mka mkar_iffalse
want_red   "make_test --forbidden-command: ...after an || not taken" -- mka mkar_ortrue
want_red   "make_test --forbidden-command: ...after an && not taken" -- mka mkar_andnull
want_red   "make_test --forbidden-command: ...in a case not taken" -- mka mkar_caseno
want_red   "make_test --forbidden-command: ...on the next line of a .ONESHELL if" -- \
	mka mkar_oneshell
mkar mkar_ifdone "$(printf 'if true; then ar rcs libselftest.a sel_a.o sel_b.o; fi')" '' \
	'sel_all: libselftest.a sel_note\nsel_note: libselftest.a\n\t$(info libtool stays out of sel)\n'
want_green "make_test --forbidden-command: text after a closed if is text" -- mka mkar_ifdone
# Text that opens a loop or an if and no branch carries nothing to the next
# line, however many lines later an && is: the && of a recipe line is over
# at its end, and the text naming libtool after it is text. Each was read
# as a call in a branch, once any later line had an && or an ||.
_mkinfo='sel_all: libselftest.a sel_note\nsel_note: libselftest.a\n\t$(info libtool stays out of sel)\n'
mkar mkar_infofor 'rm -f libselftest.a && ar rcs libselftest.a sel_a.o sel_b.o' '' \
	"\$(info for sel: building)\n$_mkinfo"
mkar mkar_infoif 'rm -f libselftest.a && ar rcs libselftest.a sel_a.o sel_b.o' '' \
	"\$(info if needed, sel is rebuilt)\n$_mkinfo"
want_green "make_test --forbidden-command: text after \$(info for ...) and an && is text" -- \
	mka mkar_infofor
want_green "make_test --forbidden-command: ...and after \$(info if ...)" -- mka mkar_infoif
# ...nor does a branch that opened and closed on one line after it: the
# depth that text leaves open is no if's, and the if's then is over at
# its fi. It was read as a branch for every later line.
mkar mkar_infoiffi 'if true; then ar rcs libselftest.a sel_a.o sel_b.o; fi' '' \
	"\$(info for sel: building)\n$_mkinfo"
want_green "make_test --forbidden-command: ...and after it, a closed if" -- mka mkar_infoiffi
# ...while a .ONESHELL loop whose do stands on a line of its own still
# holds every line up to its done in its branch.
mkar mkar_osdo "$(printf 'ar rcs libselftest.a sel_a.o sel_b.o\n\twhile false\n\tdo\n\tlibtool -static -o sel_more.a sel_a.o\n\tdone')" \
	'' '.ONESHELL:\n'
want_red   "make_test --forbidden-command: ...on a line after a .ONESHELL do of its own" -- \
	mka mkar_osdo
# A .ONESHELL line can leave a branch open at its end too -- an && or an
# ||, or a |, a { or a ( once the line has gone into a branch -- and the
# next line is in it: each of these was read as plain, and the call no
# build ran set aside as text. A } that closes the group ends it.
_mkos='ar rcs libselftest.a sel_a.o sel_b.o'
_mkol='libtool -static -o sel_more.a sel_a.o'
mkar mkar_osand "$(printf '%s\n\tfalse &&\n\t%s\n\ttrue' "$_mkos" "$_mkol")" '' '.ONESHELL:\n'
mkar mkar_osor "$(printf '%s\n\ttrue ||\n\t%s\n\ttrue' "$_mkos" "$_mkol")" '' '.ONESHELL:\n'
mkar mkar_ospipe "$(printf '%s\n\tfalse && echo sel_x |\n\t%s\n\ttrue' "$_mkos" "$_mkol")" '' \
	'.ONESHELL:\n'
mkar mkar_osbrace "$(printf '%s\n\tfalse && {\n\t%s\n\t}\n\ttrue' "$_mkos" "$_mkol")" '' '.ONESHELL:\n'
mkar mkar_osbrace2 "$(printf '%s\n\tfalse &&\n\t{\n\t%s\n\t}\n\ttrue' "$_mkos" "$_mkol")" '' \
	'.ONESHELL:\n'
mkar mkar_osdone "$(printf '%s\n\ttrue || {\n\techo sel_x\n\t}' "$_mkos")" '' \
	'.ONESHELL:\nsel_all: libselftest.a sel_note\nsel_note: libselftest.a\n\t$(info libtool stays out of sel)\n'
want_red   "make_test --forbidden-command: ...after a .ONESHELL line that ends on &&" -- \
	mka mkar_osand
want_red   "make_test --forbidden-command: ...or on ||" -- mka mkar_osor
want_red   "make_test --forbidden-command: ...or on a | in a branch" -- mka mkar_ospipe
want_red   "make_test --forbidden-command: ...or in a { opened after &&" -- mka mkar_osbrace
want_red   "make_test --forbidden-command: ...or in a { on a line of its own" -- mka mkar_osbrace2
want_green "make_test --forbidden-command: text after the } that closes it is text" -- \
	mka mkar_osdone
# The archiver errs the other way: an ar line in a branch no stand-in
# logged made nothing, and a cat made the library (mkar_chain and
# mkar_ifdone: one the build ran counts).
mkar mkar_catorar 'cat sel_a.o sel_b.o > libselftest.a || ar rcs libselftest.a sel_a.o sel_b.o'
mkar mkar_iffalsear "$(printf 'if false; then ar rcs libselftest.a sel_a.o sel_b.o; fi\n\tcat sel_a.o sel_b.o > libselftest.a')"
want_red   "make_test --archiver: ar after an || not taken makes nothing" -- mka mkar_catorar
want_out   "make_test --archiver: ...saying it was not made with ar" \
	"but not with ar" -- mka mkar_catorar
want_out   "make_test --archiver: ...as a branch no build took, not as text" \
	"in a branch of the" -- mka mkar_catorar
want_red   "make_test --archiver: ...nor ar in an if not taken" -- mka mkar_iffalsear
# A known false red, pinned so a change to it is seen: from the plan alone,
# $(info ...) text is not told from a shell line, and a tool after an ||
# in it reads as a call in a branch.
mkar mkar_infoorlt 'ar rcs libselftest.a sel_a.o sel_b.o' '' '$(info [sel] archiving || libtool never)\n'
want_red   "make_test --forbidden-command: \$(info x || libtool ...) is read as a call" -- \
	mka mkar_infoorlt
want_out   "make_test --forbidden-command: ...as a call of libtool" '(libtool)' -- mka mkar_infoorlt
# A forbidden tool that fails the build -- here, as on a box without it,
# one that is not found -- is still named, under the build's FAIL, with
# the sentence.
mkar mkar_ltfail 'libtool -static -o libselftest.a sel_a.o sel_b.o'
printf '%s\n' '#!/bin/sh' 'echo "libtool: selftest: not found" >&2' 'exit 127' \
	> "$WORK/mkar_ltfail/bin/libtool"
want_red   "make_test --forbidden-command: a libtool that fails the build" -- mka mkar_ltfail
want_out   "make_test --forbidden-command: ...is named under the FAIL" \
	'On the way the build calls libtool, which this sentence rules out:' -- mka mkar_ltfail
want_out   "make_test --forbidden-command: ...with the sentence" \
	'Toy, p.4: "Never run libtool."' -- mka mkar_ltfail
mkar mkar_ltnone 'libtool -static -o libselftest.a sel_a.o sel_b.o'
rm -f "$WORK/mkar_ltnone/bin/libtool"
if ! command -v libtool > /dev/null 2>&1; then
	want_out   "make_test --forbidden-command: a libtool this box lacks, named" \
		'On the way the build calls libtool, which this sentence rules out:' -- mka mkar_ltnone
else
	st_skipped "make_test --forbidden-command: a libtool this box lacks, named" \
		"skipped (this box has a libtool; mkar_ltfail proves the line)"
fi
# A libtool whose failure the Makefile ignores (-) makes no library, and
# the build returns 0: still named, with the sentence.
mkar mkar_ltdash '-libtool -static -o libselftest.a sel_a.o sel_b.o'
printf '%s\n' '#!/bin/sh' 'echo "libtool: selftest: refused" >&2' 'exit 1' \
	> "$WORK/mkar_ltdash/bin/libtool"
want_out   "make_test --forbidden-command: a libtool make ignored, named" \
	'On the way the build calls libtool, which this sentence rules out:' -- mka mkar_ltdash
# A build that stopped before it could tell a call from text shows the
# line that reads like one, never "a call".
mkar mkar_failinfo 'ar rcs libselftest.a sel_a.o sel_b.o' '' \
	'$(info [sel] archiving; libtool is never used here)\n'
printf '#error selftest\n' >> "$WORK/mkar_failinfo/sel_b.c"
want_broken_none "make_test --forbidden-command: a failed build claims no call" \
	'shows a call of' -- mka mkar_failinfo
want_out   "make_test --forbidden-command: ...and shows the line" \
	'    [sel] archiving; libtool is never used here' -- mka mkar_failinfo
# A project that asked for none of these checks is told nothing new: no
# compiler is a tool here, and a line of text naming cc is the compile
# check's to set aside.
mkfake mkar_ccinfo
{
	printf '$(info cc -Wall -Wextra -Werror -c sel_a.c, for sel)\n'
	printf 'all: libselftest.a\n'
	printf 'libselftest.a: sel_a.o sel_b.o\n\tcat sel_a.o sel_b.o > libselftest.a\n'
	printf 'sel_a.o: sel_a.c\n\tcc -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n'
	printf 'sel_b.o: sel_b.c\n\tcc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n'
} > "$WORK/mkar_ccinfo/Makefile"
want_broken_none "make_test --recipe-cc alone: no tool's phantom NOTE" 'read like a call of' -- \
	env PATH="$WORK/mkar_ccinfo/bin:$PATH" "$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" \
		--quotes "$MKAQ/arcc.tsv" --recipe-cc any --build-target selftest_build \
		--anchor "$WORK/mkar_ccinfo/Makefile" --artifact libselftest.a
# ...and where it asked for them too, only their tools have phantoms: a
# line of text naming cc gets one NOTE, the compile check's.
mkar mkar_ccinfo3 'ar rcs libselftest.a sel_a.o sel_b.o' '' \
	'$(info cc -Wall -Wextra -Werror -c sel_a.c, for sel)\n'
want_broken_none "make_test --recipe-cc and the three: no tool's NOTE for cc" \
	'read like a call of' -- mka mkar_ccinfo3 --quotes "$MKAQ/arcc.tsv" --recipe-cc any

# THE PINNED TOOLCHAIN A RECIPE RUNS (TO VERIFY V60). Handed the pinned
# tools, as every Bazel test of it is, make_test.sh puts a folder of them
# first on PATH for the whole run, so `cc`, `gcc`, `c99`, `ar` and `ranlib`
# in a recipe are campus's clang-12, gcc-10 and binutils 2.38 on any box.
# Before, they were the box's: "make: cc: No such file or directory" on a
# box with none, and a verdict that changed with the box's compiler. Real
# toy sources here, built by the real tools: two invented functions, one
# with a variable set and never read (gcc warns, clang-12 does not), and a
# PATH with no compiler, assembler, archiver or linker on it at all.
mkdir -p "$WORK/mkpin_nocc" "$WORK/mkpin_box"
_ifs=$IFS
IFS=:
for _d in $PATH; do
	IFS=$_ifs
	for _f in "$_d"/*; do
		_n=${_f##*/}
		case "$_n" in
			cc | c89 | c99 | c89-* | c99-* | gcc | gcc-* | *-gcc | *-gcc-* | clang | clang-* | \
				*-clang* | ar | *-ar | as | *-as | ld | ld.* | *-ld | *-ld.* | ranlib | \
				*-ranlib | cpp | cpp-* | *-cpp* | g++* | c++ | *-g++* | tcc) continue ;;
		esac
		[ -x "$_f" ] && [ ! -e "$WORK/mkpin_nocc/$_n" ] && ln -s "$_f" "$WORK/mkpin_nocc/$_n"
	done
done
IFS=$_ifs
for _n in cc gcc clang c99 ar ranlib as ld; do
	if PATH="$WORK/mkpin_nocc" command -v "$_n" > /dev/null 2>&1; then
		echo "selftest: the PATH with no compiler still finds $_n" >&2
		exit 2
	fi
	# And the box's own, first on PATH in one arm: each says it ran, and fails.
	printf '#!/bin/sh\necho "the box'"'"'s %s ran" >&2\nexit 1\n' "$_n" > "$WORK/mkpin_box/$_n"
	chmod +x "$WORK/mkpin_box/$_n"
done
mkpin() {  # mkpin DIR: two toy sources, sel_a.c's variable set and never read
	mkdir -p "$WORK/$1"
	printf 'int\tsel_one(int n)\n{\n\tint\tseen;\n\n\tseen = n;\n\treturn (n + 1);\n}\n' \
		> "$WORK/$1/sel_a.c"
	printf 'int\tsel_two(int n)\n{\n\treturn (n + 2);\n}\n' > "$WORK/$1/sel_b.c"
}
mkpin mkpin_lib
{
	printf 'all: libselftest.a\nlibselftest.a: sel_a.o sel_b.o\n'
	printf '\tar rc libselftest.a sel_a.o sel_b.o\n\tranlib libselftest.a\n'
	printf 'sel_a.o: sel_a.c\n\tcc -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n'
	printf 'sel_b.o: sel_b.c\n\tcc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n'
} > "$WORK/mkpin_lib/Makefile"
# A program, linked: the C library and its start files reach the link.
mkpin mkpin_prog
printf 'int\tsel_two(int n);\n\nint\tmain(void)\n{\n\treturn (sel_two(-2));\n}\n' \
	> "$WORK/mkpin_prog/sel_main.c"
{
	printf 'all: sel_prog\nsel_prog: sel_main.c sel_b.o\n'
	printf '\tcc -Wall -Wextra -Werror sel_main.c sel_b.o -o sel_prog\n\t./sel_prog\n'
	printf 'sel_b.o: sel_b.c\n\tc99 -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n'
} > "$WORK/mkpin_prog/Makefile"
# Which compiler each name is: clang-12 warns on x = x; and gcc-10 on a
# variable set and never read, and neither on the other's.
mkpin mkpin_self
printf 'int\tsel_one(int n)\n{\n\tn = n;\n\treturn (n + 1);\n}\n' > "$WORK/mkpin_self/sel_a.c"
for _s in self:cc gccset:gcc; do
	[ "${_s%%:*}" = self ] || mkpin "mkpin_${_s%%:*}"
	{
		printf 'all: libselftest.a\nlibselftest.a: sel_a.o\n\tar rc libselftest.a sel_a.o\n'
		printf 'sel_a.o: sel_a.c\n\t%s -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n' "${_s#*:}"
	} > "$WORK/mkpin_${_s%%:*}/Makefile"
done
# A Makefile that puts a folder of its own ahead of the pinned tools runs
# its own gcc, and the stand-ins still record that it went past them.
mkpin mkpin_bypass
mkdir -p "$WORK/mkpin_bypass/alt"
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do case "$1" in -o) : > "$2"; shift 2 ;; *) shift ;; esac; done\n' \
	> "$WORK/mkpin_bypass/alt/gcc"
chmod +x "$WORK/mkpin_bypass/alt/gcc"
{
	printf 'export PATH := $(CURDIR)/alt:$(PATH)\n'
	printf 'all: libselftest.a\nlibselftest.a: sel_a.o sel_b.o\n'
	printf '\tar rc libselftest.a sel_a.o sel_b.o\n'
	printf 'sel_a.o: sel_a.c\n\tcc -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n'
	printf 'sel_b.o: sel_b.c\n\tgcc -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n'
} > "$WORK/mkpin_bypass/Makefile"
mtp() {  # mtp PATH DIR ARTIFACT [FLAG...]: make_test.sh, pinned, under PATH
	_p=$1 _d=$2 _a=$3
	shift 3
	# shellcheck disable=SC2086 # MK_PIN is a list of words, as BUILD_PIN is
	once env PATH="$_p" "$SH" "$TOOLS/make_test.sh" --nm "$NM" $MK_PIN --rules "" \
		--build-target selftest_build "$@" --anchor "$WORK/$_d/Makefile" --artifact "$_a"
}
want_green "make_test, pinned: a library builds on a PATH with no compiler" -- \
	mtp "$WORK/mkpin_nocc" mkpin_lib libselftest.a
want_green "make_test, pinned: ...and a program links, through c99 too" -- \
	mtp "$WORK/mkpin_nocc" mkpin_prog sel_prog
want_green "make_test, pinned: the box's cc, gcc and ar first on PATH never run" -- \
	mtp "$WORK/mkpin_box:$PATH" mkpin_lib libselftest.a
want_broken_none "make_test, pinned: ...not one of them" "the box's" -- \
	mtp "$WORK/mkpin_box:$PATH" mkpin_lib libselftest.a
want_red   "make_test, pinned: cc is clang-12, which fails x = x; under -Werror" -- \
	mtp "$WORK/mkpin_nocc" mkpin_self libselftest.a
want_out   "make_test, pinned: ...in clang's words" '[-Werror,-Wself-assign]' -- \
	mtp "$WORK/mkpin_nocc" mkpin_self libselftest.a
want_red   "make_test, pinned: gcc is gcc-10, which fails a variable never read" -- \
	mtp "$WORK/mkpin_nocc" mkpin_gccset libselftest.a
want_out   "make_test, pinned: ...in gcc's words" '[-Werror=unused-but-set-variable]' -- \
	mtp "$WORK/mkpin_nocc" mkpin_gccset libselftest.a
want_out   "make_test --recipe-cc, pinned: ar and ranlib are no compile" \
	'each of the 2 compile commands' -- \
	mtp "$WORK/mkpin_nocc" mkpin_lib libselftest.a --recipe-cc any --quotes "$MKAQ/arcc.tsv"
want_green "make_test --archiver, pinned: the ar a recipe runs makes the library" -- \
	mtp "$WORK/mkpin_nocc" mkpin_lib libselftest.a --archiver ar --quotes "$MKAQ/ar.tsv"
want_red   "make_test --recipe-cc, pinned: a gcc of the Makefile's own PATH fails" -- \
	mtp "$WORK/mkpin_nocc" mkpin_bypass libselftest.a --recipe-cc any --quotes "$MKAQ/arcc.tsv"
want_out   "make_test --recipe-cc, pinned: ...named" 'gcc, not cc' -- \
	mtp "$WORK/mkpin_nocc" mkpin_bypass libselftest.a --recipe-cc any --quotes "$MKAQ/arcc.tsv"
want_broken "make_test: some pinned tools and not the rest are refused" '--ranlib is missing' -- \
	mt --cc "$CLANG" --ld "$LD" --ld-lib "$LD_LIB" --gcc "$GCC" --as "$AS" --ar "$AR" \
		--rules "" --anchor "$WORK/mkpin_lib/Makefile" --artifact libselftest.a
# ...and so is a library of one of them without the tool (review of V60):
# --cc-lib alone was ignored in silence, and the recipes ran PATH's cc.
want_broken "make_test: a pinned tool's library without the tools is refused" '--cc is missing' -- \
	mt --cc-lib "$CLANG" --rules "" --anchor "$WORK/mkpin_lib/Makefile" --artifact libselftest.a
# A program `gcc -fsanitize=address` builds, which then runs (review of V60).
# The fetched gcc-10's libasan.so is a symlink into libasan6, a package of
# its own; without it gcc fell back to the static runtime, and the link
# stopped at "undefined reference to `signgam'" where campus's links.
mkpin mkpin_asan
printf 'int\tsel_two(int n);\n\nint\tmain(void)\n{\n\treturn (sel_two(-2));\n}\n' \
	> "$WORK/mkpin_asan/sel_main.c"
{
	printf 'all: sel_prog\nsel_prog: sel_main.c sel_b.c\n'
	printf '\tgcc -Wall -Wextra -Werror -fsanitize=address -g sel_main.c sel_b.c -o sel_prog\n'
	printf '\t./sel_prog\n'
} > "$WORK/mkpin_asan/Makefile"
want_green "make_test, pinned: gcc -fsanitize=address links a program, which runs" -- \
	mtp "$WORK/mkpin_nocc" mkpin_asan sel_prog
# The versioned names campus has too: clang-12 (no warning for a variable
# set and never read) and gcc-10.
mkpin mkpin_names
{
	printf 'all: libselftest.a\nlibselftest.a: sel_a.o sel_b.o\n\tar rc libselftest.a sel_a.o sel_b.o\n'
	printf 'sel_a.o: sel_a.c\n\tclang-12 -Wall -Wextra -Werror -c sel_a.c -o sel_a.o\n'
	printf 'sel_b.o: sel_b.c\n\tgcc-10 -Wall -Wextra -Werror -c sel_b.c -o sel_b.o\n'
} > "$WORK/mkpin_names/Makefile"
want_green "make_test, pinned: clang-12 and gcc-10 are the pinned ones" -- \
	mtp "$WORK/mkpin_nocc" mkpin_names libselftest.a
# The loader proofs (the nm's, and each pinned binutils wrapper's) read the
# loader's lines from stderr, and an LD_DEBUG_OUTPUT set from outside sent
# them to files of its own; the proofs saw none and refused (V276).
# shellcheck disable=SC2086 # MK_PIN is a list of words
want_green "make_test, pinned: an LD_DEBUG_OUTPUT from outside changes nothing" -- \
	env LD_DEBUG_OUTPUT="$WORK/mkpin-ld.dbg" PATH="$WORK/mkpin_nocc" \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --nm-lib "$NM_LIB" $MK_PIN --rules "" \
		--build-target selftest_build --anchor "$WORK/mkpin_lib/Makefile" --artifact libselftest.a
# ...nor an LD_DEBUG: the guard that asks the pinned gcc which as and ld it
# takes (-print-prog-name) read the answer with stderr in it, so the loader's
# lines from an LD_DEBUG set from outside were taken for the answer, and the
# runner said the pinned gcc did not take the pinned as (V276). Its lines
# go to a folder of this test's own, not to selftest's outputs (V336).
mkdir -p "$WORK/mkpin-out"
# shellcheck disable=SC2086 # MK_PIN is a list of words
want_green "make_test, pinned: ...nor an LD_DEBUG from outside" -- \
	env LD_DEBUG=libs TEST_UNDECLARED_OUTPUTS_DIR="$WORK/mkpin-out" PATH="$WORK/mkpin_nocc" \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --nm-lib "$NM_LIB" $MK_PIN --rules "" \
		--build-target selftest_build --anchor "$WORK/mkpin_lib/Makefile" --artifact libselftest.a
# ...and a pinned as the loader cannot start (a library this machine lacks):
# its words went into the file the loader's proof reads, which found no
# `calling init:` line for libbfd and refused as "could not observe" which
# one it loaded, naming nothing. The stand-in prints what the loader prints
# and exits as it does.
mkdir -p "$WORK/mkasdead"
printf '#!/bin/sh\necho "$0: error while loading shared libraries: libselftestmiss.so.1: cannot open shared object file: No such file or directory" >&2\nexit 127\n' \
	> "$WORK/mkasdead/as"
chmod +x "$WORK/mkasdead/as"
# shellcheck disable=SC2086 # BUILD_PIN is a list of words
want_broken "make_test, pinned: an as that cannot start says so" \
	'the pinned as cannot start (exit 127)' -- \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" $BUILD_PIN --gcc "$GCC" --as "$WORK/mkasdead/as" \
		--ar "$AR" --ranlib "$RANLIB" --rules "" --build-target selftest_build \
		--anchor "$WORK/mkpin_lib/Makefile" --artifact libselftest.a
# c89 and c99 refuse another standard in their own scripts' words.
for _s in c89:c99:'ANSI/ISO C' c99:c11:'ISO C99'; do
	_c=${_s%%:*} _r=${_s#*:}
	mkpin "mkpin_$_c"
	printf 'all: sel_b.o\nsel_b.o: sel_b.c\n\t%s -std=%s -c sel_b.c -o sel_b.o\n' "$_c" "${_r%%:*}" \
		> "$WORK/mkpin_$_c/Makefile"
	want_out "make_test, pinned: $_c refuses -std=${_r%%:*} as Ubuntu's $_c-gcc does" \
		"$_c called with non ${_r#*:} option -std=${_r%%:*}" -- \
		mtp "$WORK/mkpin_nocc" "mkpin_$_c" sel_b.o
done

