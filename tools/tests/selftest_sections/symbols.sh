# ------------------------------------------------------------------- symbols
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
printf 'static int helper(void){return 1;}\nint ft_x(void){return helper();}\n' > "$WORK/static.c"
# leaky.c is forbidden_globals' too: plain code, made in every shard (st_mine).
printf 'int helper(void){return 1;}\nint ft_x(void){return helper();}\n' > "$WORK/leaky.c"
want_green "symbols: a static helper is invisible, so passes" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x --src "$WORK/static.c"
# ...whatever LD_DEBUG_OUTPUT the host sets: the nm proof reads the loader's
# lines from stderr, and one set from outside sent them elsewhere (V276).
want_green "symbols: ...also under an LD_DEBUG_OUTPUT from outside" -- \
	env LD_DEBUG_OUTPUT="$WORK/symbols-ld.dbg" \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x --src "$WORK/static.c"
want_red   "symbols: an exported helper fails" -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x --src "$WORK/leaky.c"
want_out   "symbols: ...and is told what static does" \
	"'static' storage class" -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x --src "$WORK/leaky.c"
want_broken_none "symbols: ...with no word about a main" \
	'DEFINES main()' -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x --src "$WORK/leaky.c"

# A leftover main() beside the function (finding 037). It used to get the
# helper's advice -- make it static -- which -Wall -Wextra -Werror refuses for
# a main; the fix is to move it out of the turn-in. Its own verdict, and the
# static advice must not be among what it is told.
printf 'int ft_x(void){return 1;}\nint main(void){return ft_x();}\n' > "$WORK/sym_main.c"
want_red   "symbols: a leftover main() fails" -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x --src "$WORK/sym_main.c"
want_out   "symbols: ...with a verdict of its own" \
	'compiles its own main() with your file' -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x --src "$WORK/sym_main.c"
want_broken_none "symbols: ...and is never told to make it static" \
	"'static' storage class" -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x --src "$WORK/sym_main.c"
# ...while a subject that asks for a main (--expect names it) passes one.
want_green "symbols: a main the subject asks for passes" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x,main --src "$WORK/sym_main.c"

# A helper one file defines and ANOTHER calls must stay external (C 07 ex04's
# two files), and one nobody else calls must not. And the names that cross are
# found with nm run a number of times that does not grow with the files: it ran
# twice per ordered pair, 3612 times over Libft's 43 files, and that test timed
# out. The counting nm logs each run, then hands over to the real one.
printf 'int sym_shared(void){return 1;}\nint ft_x(void){return 0;}\n' > "$WORK/sym_def.c"
printf 'int sym_shared(void);\nint ft_y(void){return sym_shared();}\n' > "$WORK/sym_use.c"
printf 'int ft_y(void){return 0;}\n' > "$WORK/sym_nouse.c"
want_green "symbols: a helper another file calls may be external" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x,ft_y \
		--src "$WORK/sym_def.c" --src "$WORK/sym_use.c"
# A function is turned in in its library's files (rl_entry), so the files
# its OK line speaks of are the library's.
want_out   "symbols_test: ...a function's files are its library's" \
	"defined in one of this library's files" -- \
	env RL_UNIT_KIND=function "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" \
		--expect ft_x,ft_y --src "$WORK/sym_def.c" --src "$WORK/sym_use.c"
want_red   "symbols: ...one no other file calls may not" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x,ft_y \
		--src "$WORK/sym_def.c" --src "$WORK/sym_nouse.c"
# A name the subject asks for that another file calls is no extra: the OK
# line named ft_x again as "plus ft_x", as if it were a helper.
printf 'int ft_x(void){return 0;}\n' > "$WORK/sym_x.c"
printf 'int ft_x(void);\nint ft_z(void){return ft_x();}\n' > "$WORK/sym_callx.c"
want_out   "symbols: a name asked for and called across files is no extra" \
	'OK — exports exactly: ft_x ft_z' -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x,ft_z \
		--src "$WORK/sym_x.c" --src "$WORK/sym_callx.c"
# ...and the list ends at its last name: it ended in a blank (V234).
want_green "symbols: ...and its OK line ends without a blank" -- \
	sh -c 'o=$("$1" "$2" --nm "$3" --nm-lib "$4" --expect ft_x,ft_z --src "$5" --src "$6") || exit 1
		printf "%s\n" "$o" | grep -qx ".*OK — exports exactly: ft_x ft_z" &&
		! printf "%s\n" "$o" | grep -q " \$"' _ \
	"$SH" "$TOOLS/symbols_test.sh" "$NM" "$NM_LIB" "$WORK/sym_x.c" "$WORK/sym_callx.c"
# --no-cross: where the call site's sentence keeps every helper static in its
# own file, a helper one file defines and another calls is an extra like any
# other, and the red quotes the sentence. It went green, "plus sel_help", with
# no way for a call site to say otherwise. Without the sentence the check never
# ran (exit 2); --quotes in the default mode, which quotes nothing, is refused
# too. A static helper in each file is green. Invented functions.
printf 'int sel_help(int n){return n + 1;}\nint sel_one(int n){return sel_help(n);}\n' > "$WORK/sym_nc_a.c"
printf 'int sel_help(int n);\nint sel_two(int n){return sel_help(n) * 2;}\n' > "$WORK/sym_nc_b.c"
printf 'static int sel_help(int n){return n + 1;}\nint sel_one(int n){return sel_help(n);}\n' > "$WORK/sym_nc_as.c"
printf 'static int sel_help(int n){return n + 3;}\nint sel_two(int n){return sel_help(n) * 2;}\n' > "$WORK/sym_nc_bs.c"
printf 'helpers\tToy, p.1: "Keep each helper static, in its own file."\n' > "$WORK/sym_nc_q.tsv"
want_green "symbols: by default a shared helper still crosses" -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--src "$WORK/sym_nc_a.c" --src "$WORK/sym_nc_b.c"
want_broken_none "symbols: ...and its OK line claims no subject" \
	'subject asks' -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--src "$WORK/sym_nc_a.c" --src "$WORK/sym_nc_b.c"
want_red   "symbols: --no-cross holds a shared helper" -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--no-cross --quotes "$WORK/sym_nc_q.tsv" \
		--src "$WORK/sym_nc_a.c" --src "$WORK/sym_nc_b.c"
want_out   "symbols: ...naming it as not asked for" \
	'    sel_help' -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--no-cross --quotes "$WORK/sym_nc_q.tsv" \
		--src "$WORK/sym_nc_a.c" --src "$WORK/sym_nc_b.c"
want_out   "symbols: ...quoting the call site's sentence" \
	'Toy, p.1: "Keep each helper static, in its own file."' -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--no-cross --quotes "$WORK/sym_nc_q.tsv" \
		--src "$WORK/sym_nc_a.c" --src "$WORK/sym_nc_b.c"
want_broken_none "symbols: ...and never calling it allowed" \
	'is allowed to be' -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--no-cross --quotes "$WORK/sym_nc_q.tsv" \
		--src "$WORK/sym_nc_a.c" --src "$WORK/sym_nc_b.c"
want_broken "symbols: --no-cross without its sentence refuses" \
	'one KEY<TAB>TEXT line for each of: helpers' -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--no-cross --src "$WORK/sym_nc_a.c" --src "$WORK/sym_nc_b.c"
want_broken "symbols: --quotes without --no-cross refuses" \
	'the default mode quotes nothing' -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--quotes "$WORK/sym_nc_q.tsv" --src "$WORK/sym_nc_a.c" --src "$WORK/sym_nc_b.c"
want_green "symbols: --no-cross passes a static helper per file" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--no-cross --quotes "$WORK/sym_nc_q.tsv" \
		--src "$WORK/sym_nc_as.c" --src "$WORK/sym_nc_bs.c"
# --no-cross holds helpers, never a name the call site asks for: one asked-for
# function calling another, in another file, is how a library's files are
# usually written, and no stub tree shows it (stubs call nothing).
want_out   "symbols: --no-cross: a name asked for and called across is no extra" \
	'OK — exports exactly: ft_x ft_z' -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x,ft_z \
		--no-cross --quotes "$WORK/sym_nc_q.tsv" --functions-only \
		--src "$WORK/sym_x.c" --src "$WORK/sym_callx.c"
# The sentence --no-cross quotes is about helper FUNCTIONS. Without
# --functions-only a variable is still this layer's, and the red quoted the
# sentence over it, a requirement the sentence does not make. A variable one
# file defines and another uses crosses as it does by default; one nothing
# else uses is reported, unquoted. Invented names.
printf 'int sel_count = 0;\nint sel_one(void){return sel_count;}\n' > "$WORK/sym_nc_v.c"
printf 'extern int sel_count;\nint sel_two(void){return sel_count * 2;}\n' > "$WORK/sym_nc_vuse.c"
printf 'int sel_two(void){return 2;}\n' > "$WORK/sym_nc_vnouse.c"
want_red   "symbols: --no-cross: a variable nothing else uses is reported" -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--no-cross --quotes "$WORK/sym_nc_q.tsv" \
		--src "$WORK/sym_nc_v.c" --src "$WORK/sym_nc_vnouse.c"
want_broken_none "symbols: ...without the helpers sentence over it" \
	'Keep each helper static' -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--no-cross --quotes "$WORK/sym_nc_q.tsv" \
		--src "$WORK/sym_nc_v.c" --src "$WORK/sym_nc_vnouse.c"
want_green "symbols: --no-cross: a variable two files share still crosses" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--no-cross --quotes "$WORK/sym_nc_q.tsv" \
		--src "$WORK/sym_nc_v.c" --src "$WORK/sym_nc_vuse.c"
# Beside a shared helper, the sentence names the functions it is quoted over.
printf 'int sel_help(int n);\nint sel_count = 0;\nint sel_two(int n){return sel_help(n) * 2;}\n' > "$WORK/sym_nc_bv.c"
want_out   "symbols: ...and beside a helper, quotes over the functions alone" \
	'The requirement, over the function(s) among them: sel_help' -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect sel_one,sel_two \
		--no-cross --quotes "$WORK/sym_nc_q.tsv" \
		--src "$WORK/sym_nc_a.c" --src "$WORK/sym_nc_bv.c"
mkdir -p "$WORK/sym_many"
printf '#!/bin/sh\necho run >> "%s"\nexec "%s" "$@"\n' "$WORK/sym_many/nm_runs" "$NM" > "$WORK/sym_many/nm"
chmod +x "$WORK/sym_many/nm"
: > "$WORK/sym_many/nm_runs"
# The runner's arguments, built in the function's own "$@": twelve sources
# ft_m0.c ... ft_m11.c, each defining its one function, all twelve asked for.
sym_many() {
	set -- --nm "$WORK/sym_many/nm" --nm-lib "$NM_LIB"
	_sm_exp=""
	_sm_i=0
	while [ "$_sm_i" -lt 12 ]; do
		printf 'int ft_m%d(void){return %d;}\n' "$_sm_i" "$_sm_i" > "$WORK/sym_many/ft_m$_sm_i.c"
		set -- "$@" --src "$WORK/sym_many/ft_m$_sm_i.c"
		_sm_exp="$_sm_exp${_sm_exp:+,}ft_m$_sm_i"
		_sm_i=$((_sm_i + 1))
	done
	"$SH" "$TOOLS/symbols_test.sh" "$@" --expect "$_sm_exp"
}
want_green "symbols: twelve files, every function asked for" -- sym_many
_nm_runs=$(wc -l < "$WORK/sym_many/nm_runs")
if [ "$_nm_runs" -le 4 ]; then
	printf '  %-52s %s\n' "symbols: ...with a few nm runs, not one per pair" \
		"ok ($_nm_runs nm runs over twelve objects)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "symbols: ...with a few nm runs, not one per pair" \
		"FAIL < ($_nm_runs nm runs over twelve objects: one per pair of files again)"
	FAIL=$((FAIL + 1))
fi

# AN nm THAT FAILS IS THE HARNESS'S FAULT (TO VERIFY V209). The runner used to
# throw nm's status and stderr away, so a failing nm left the list of defined
# names empty and every asked-for name came out "NOT DEFINED ... check the
# spelling": exit 1, a red on the student for a broken tool, with the tool's
# own words gone. This nm answers --version as the pinned one does (so the
# --nm-lib proof still passes) and fails on every object.
mkdir -p "$WORK/sym_nmfail"
printf '#!/bin/sh\ncase ${1:-} in --version) exec "%s" "$@" ;; esac\necho "toy-nm: cannot read the object" >&2\nexit 1\n' \
	"$NM" > "$WORK/sym_nmfail/nm"
chmod +x "$WORK/sym_nmfail/nm"
want_broken "symbols: a failing nm is a broken harness, exit 2" \
	'(nm failed)' -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$WORK/sym_nmfail/nm" --nm-lib "$NM_LIB" \
		--expect ft_x --src "$WORK/static.c"
want_broken "symbols: ...and shows what nm said" \
	'toy-nm: cannot read the object' -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$WORK/sym_nmfail/nm" --nm-lib "$NM_LIB" \
		--expect ft_x --src "$WORK/static.c"
# The other half: an nm that prints SOME of the table and then fails. It reads
# the first object through the pinned nm, then gives up on the rest, and the
# second object holds the one name --expect does not ask for. Read on without
# its status, that partial table says "exports exactly: toy_kept", exit 0: a
# green over an extra export nobody looked at. An output that is merely not
# empty is no proof nm read everything, so the status decides.
mkdir -p "$WORK/sym_nmpart"
printf '#!/bin/sh\ncase ${1:-} in --version) exec "%s" "$@" ;; esac\n"%s" "$1" || exit 1\necho "toy-nm: gave up after the first object" >&2\nexit 1\n' \
	"$NM" "$NM" > "$WORK/sym_nmpart/nm"
chmod +x "$WORK/sym_nmpart/nm"
printf 'int toy_kept(void){return (1);}\n' > "$WORK/sym_nmpart/a_first.c"
printf 'int toy_extra(void){return (2);}\n' > "$WORK/sym_nmpart/b_second.c"
want_broken "symbols: an nm that stops part-way is a broken harness" \
	'(nm failed)' -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$WORK/sym_nmpart/nm" --nm-lib "$NM_LIB" \
		--expect toy_kept --src "$WORK/sym_nmpart/a_first.c" \
		--src "$WORK/sym_nmpart/b_second.c"

# --provided: a function the GRADER compiles in (Piscine Reloaded's ft_putchar).
# Declaring and calling it is the exercise; defining it is the mistake, and the
# one thing these two layers must say in its own words -- told "calls write" or
# "make it static", a student keeps their copy. Static copies count too for the
# forbidden layer: static dodges the link clash, not the body nobody asked for.
printf 'void selftest_supplied(char c);\nint ft_x(void){selftest_supplied(1);return 0;}\n' \
	> "$WORK/prov_calls.c"
printf 'void selftest_supplied(char c){(void)c;}\nint ft_x(void){selftest_supplied(1);return 0;}\n' \
	> "$WORK/prov_defines.c"
printf 'static void selftest_supplied(char c){(void)c;}\nint ft_x(void){selftest_supplied(1);return 0;}\n' \
	> "$WORK/prov_static.c"
want_green "forbidden: calling a supplied function passes" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed selftest_supplied \
		--provided selftest_supplied --src "$WORK/prov_calls.c"
want_red   "forbidden: defining a supplied function fails" -- \
	once "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed selftest_supplied \
		--provided selftest_supplied --src "$WORK/prov_defines.c"
want_out   "forbidden: ...and says the grader supplies it" \
	'SUPPLIED BY THE GRADER' -- \
	once "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed selftest_supplied \
		--provided selftest_supplied --src "$WORK/prov_defines.c"
want_red   "forbidden: ...a static copy of it too" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed selftest_supplied \
		--provided selftest_supplied --src "$WORK/prov_static.c"
want_red   "symbols: exporting a supplied function fails" -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x \
		--provided selftest_supplied --src "$WORK/prov_defines.c"
want_out   "symbols: ...with a verdict of its own" \
	'SUPPLIED BY THE GRADER' -- \
	once "$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x \
		--provided selftest_supplied --src "$WORK/prov_defines.c"

# THE PIN IS THE LIBRARY, NOT THE FRONTEND. binutils ships a 44 KB nm whose
# work is all in libbfd, named as a bare soname with no RPATH and no RUNPATH --
# so without a path to the fetched copy the loader answers from
# /lib/x86_64-linux-gnu and the pinned nm parses symbol tables with the box's
# binutils. It goes on printing the pinned version either way, because that
# string is in the frontend's own .rodata, which is why pins.tsv read green
# through all of it.
#
# The check that catches this is about RESOLUTION, not about which file gets
# exec'd, so these arms drive it by pointing --nm-lib somewhere real that holds
# no libbfd. Exit 2: a tool that will not load its own library is a wiring
# error, not a finding about anyone's code.
#
# The library nm then loads is a copy of the fetched ones, reached through
# LD_LIBRARY_PATH from outside and not through --nm-lib: a library from
# somewhere else on every machine, as compile_check's assembler arms have it.
# It used to be the box's own, and on a box without binutils 2.38 nm could
# not start, the runner "could not observe" which library it loaded, and the
# arms failed while the runner was right (V275). Each pattern names the
# copy's folder, so an arm that stopped reaching it fails on every box.
mkdir -p "$WORK/nolib" "$WORK/libelsewhere"
cp -L "${NM_LIB%/*}"/lib*.so* "$WORK/libelsewhere/"
want_broken "symbols: nm loading a libbfd from outside --nm-lib is refused" \
	"the pinned nm loaded '$WORK/libelsewhere/" -- \
	env LD_LIBRARY_PATH="$WORK/libelsewhere" \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$WORK/nolib/none" \
		--expect ft_x --src "$WORK/static.c"
want_green "symbols: ...and the staged one is accepted" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" \
		--expect ft_x --src "$WORK/static.c"
want_broken "forbidden: the same refusal, in the layer that gates at level 1" \
	"the pinned nm loaded '$WORK/libelsewhere/" -- \
	env LD_LIBRARY_PATH="$WORK/libelsewhere" \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$WORK/nolib/none" \
		--allowed - --src "$WORK/clean.c"
# --nm-lib may be given more than once, and its library may be in any of its
# folders: each runner tested a loaded library against all of them joined
# into one path, and refused a correct setup as "not under --nm-lib" (V274,
# V277). Here the folder that holds it comes second.
want_green "symbols: the library in the second of two --nm-lib folders" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$WORK/nolib/none" --nm-lib "$NM_LIB" \
		--expect ft_x --src "$WORK/static.c"
want_green "forbidden: ...and in forbidden_symbols" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$WORK/nolib/none" --nm-lib "$NM_LIB" \
		--allowed - --src "$WORK/clean.c"

# TWO FILES OF ONE NAME IN TWO FOLDERS, which a pattern such as
# */*.c allows. Each object was named after its source's basename, so x.c and
# sub/x.c wrote one x.o, the second over the first: nm read one file, and the
# verdict hung on the order -- a name asked for NOT DEFINED (a false red, in
# either order), or a stray global unseen (a false green). Each arm got the
# other verdict before.
mkdir -p "$WORK/symdup/sub" "$WORK/symdup/two"
printf 'int toy_a(void){return 1;}\n' > "$WORK/symdup/x.c"
printf 'int toy_stray(void){return 2;}\n' > "$WORK/symdup/sub/x.c"
printf 'int toy_b(void){return 3;}\n' > "$WORK/symdup/two/x.c"
want_red   "symbols: x.c and sub/x.c are two objects (a stray seen)" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect toy_a \
		--src "$WORK/symdup/sub/x.c" --src "$WORK/symdup/x.c"
want_green "symbols: ...each file's names defined, x.c first" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect toy_a,toy_b \
		--src "$WORK/symdup/x.c" --src "$WORK/symdup/two/x.c"
want_green "symbols: ...and two/x.c first" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect toy_a,toy_b \
		--src "$WORK/symdup/two/x.c" --src "$WORK/symdup/x.c"

# A MAKEFILE'S -I (--inc-file): a library keeping its header in inc/, which
# its Makefile reaches with -I inc, compiled here with no -I found no header
# (V198). The list is what tools/student_build.sh --includes-out writes.
mkdir -p "$WORK/syminc/inc"
printf 'int\ttoy_inc(void);\n' > "$WORK/syminc/inc/toy_inc.h"
printf '#include "toy_inc.h"\nint toy_inc(void){return 3;}\n' > "$WORK/syminc/toy_inc.c"
printf '%s\n' "$WORK/syminc/inc" > "$WORK/syminc/includes.txt"
want_red   "symbols: a header only the Makefile's -I reaches, without it" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect toy_inc \
		--src "$WORK/syminc/toy_inc.c"
want_green "symbols: ...is found through --inc-file" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect toy_inc \
		--inc-file "$WORK/syminc/includes.txt" --src "$WORK/syminc/toy_inc.c"

