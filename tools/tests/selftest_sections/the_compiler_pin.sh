# ------------------------------------------------------- the compiler pin
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The four runners that COMPILE before they inspect -- forbidden, symbols,
# prototype, header -- each defaulted to `cc` from PATH and reported SKIP,
# exit 0, when it was absent. Measured: 321 targets green having compiled
# nothing, with forbidden and prototype at LEVEL 1 inside the submit gate, and
# //c-piscine/c-piscine-rush-02:ex00_forbidden going FAIL -> PASS with them.
#
# Bazel now passes the pinned clang through --cc, so an absent compiler is a
# WIRING error rather than a fact about the machine. Exit 2, never 0.
#
# EACH RUNNER GETS ITS OWN FLAGS, and the first version of this did not: it
# passed the union to all four, so forbidden and header died on "required
# command 'grep' is not on PATH" and prototype on "unknown option: --allowed".
# All four exited 2, the arm went green, and it had never reached the compiler
# probe at all -- which a mutation caught only because the mutation failed to
# flip it.
mkdir -p "$WORK/ccp"
printf 'int ft_x(void){return (0);}\n' > "$WORK/ccp/s.c"
printf 'int ft_x(void);\n' > "$WORK/ccp/p.h"
printf 'int main(void){return (0);}\n' > "$WORK/ccp/m.c"
: > "$WORK/ccp/e.txt"
# The PINNED nm, not `command -v nm`. These four arms are about the COMPILER
# being absent, so nm is only scaffolding -- but on a box with no host nm the
# scaffolding decided the verdict: the runners would exit 2 on "--nm is
# required", and an arm that took any exit 2 would pass having never reached
# the compiler probe it exists for. The selftest is handed a sha256-pinned nm
# on its own command line; use that.
_ccnm=$NM

# Any exit 2 was accepted, and these arms now hand the runners --nm-lib, whose
# pin is checked (a directory, then the loader's proof) before the compiler
# probe: a refusal of nm's library would have passed for the compiler's. So
# each is a want_broken, the status AND the compiler's own sentence, which
# every runner here prints in the same words. A status other than 2 is the
# SKIP this section is about, 321 targets green on nothing; the right status
# without the sentence is another check that fired first.
CC_ABSENT="the compiler '/nonexistent/clang' is not executable"
want_broken "forbidden: an absent compiler refuses, never skips" "$CC_ABSENT" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --cc /nonexistent/clang --nm "$_ccnm" --nm-lib "$NM_LIB" \
		--allowed "" --src "$WORK/ccp/s.c"
want_broken "symbols: an absent compiler refuses, never skips" "$CC_ABSENT" -- \
	"$SH" "$TOOLS/symbols_test.sh" --cc /nonexistent/clang --nm "$_ccnm" --nm-lib "$NM_LIB" \
		--expect ft_x --src "$WORK/ccp/s.c"
want_broken "prototype: an absent compiler refuses, never skips" "$CC_ABSENT" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc /nonexistent/clang \
		--proto "$WORK/ccp/p.h" --src "$WORK/ccp/s.c"
want_broken "header: an absent compiler refuses, never skips" "$CC_ABSENT" -- \
	"$SH" "$TOOLS/header_check.sh" --cc /nonexistent/clang --hdr "$WORK/ccp/p.h" \
		--main "$WORK/ccp/m.c" --expected "$WORK/ccp/e.txt" \
		--differ "$TOOLS/diff_output.sh"
# compile_check.sh said "not found -- SKIP (rebuild the devcontainer)", exit
# 0, from before both campus compilers were fetched: it is a wiring fault now.
want_broken "compile_check: an absent compiler refuses, never skips" "$CC_ABSENT" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc /nonexistent/clang --src "$WORK/ccp/s.c"

# A COMPILER THAT IS THERE AND CANNOT START (V241): the fetched clang-12 on
# a box without a library it loads dies in the loader, exit 127. Each proof
# after it read that as something else -- -print-search-dirs into a grep
# said "not searching its own tree" by the relative path Bazel passes, and
# passed by accident by an absolute one, whose loader error names the
# directory (compile_check.sh then said FAIL over the student's file); the
# --globals probe said the compiler "leaves out of its object a static" --
# and the loader's line was in no log. The stand-in prints what the loader
# prints and exits as it does. Every arm: exit 2, the start refused, the
# library named, and none of the wrong causes.
mkdir -p "$WORK/ccp/dead/bin"
printf '#!/bin/sh\necho "$0: error while loading shared libraries: libtoy.so.2: cannot open shared object file: No such file or directory" >&2\nexit 127\n' \
	> "$WORK/ccp/dead/bin/clang-12"
chmod +x "$WORK/ccp/dead/bin/clang-12"
# TOOLS is relative and may hold no slash, which _nr_abs keeps as it is.
_ccp_abs_tools=$(cd "$TOOLS" && pwd -P)
_ccp_abs_sh=$(_nr_abs "$SH")
_ccp_abs_nm=$(_nr_abs "$NM")
_ccp_abs_nmlib=$(_nr_abs "$NM_LIB")
_ccp_abs_ld=$(_nr_abs "$LD")
_ccp_abs_ldlib=$(_nr_abs "$LD_LIB")
printf 'globals\tA sentence for the selftest, standing in for the call site.\n' > "$WORK/ccp/q.tsv"
cc_dead() {  # cc_dead NAME REL|ABS RUNNER ARGS... -- @CC@ in ARGS is the dead compiler
	_n=$1 _how=$2 _r=$3
	shift 3
	if [ "$_how" = rel ]; then _dcc=dead/bin/clang-12; else _dcc=$WORK/ccp/dead/bin/clang-12; fi
	_i=$#
	while [ "$_i" -gt 0 ]; do
		_a=$1
		shift
		[ "$_a" != @CC@ ] || _a=$_dcc
		set -- "$@" "$_a"
		_i=$((_i - 1))
	done
	_out=$(cd "$WORK/ccp" && "$_ccp_abs_sh" "$_ccp_abs_tools/$_r" "$@" 2>&1)
	_rc=$?
	_why=""
	[ "$_rc" -eq 2 ] || _why="exit $_rc; it must refuse with 2"
	for _p in "cannot start (exit 127)" "The loader found no libtoy.so.2"; do
		[ -n "$_why" ] || printf '%s' "$_out" | grep -qF -- "$_p" || _why="never said '$_p'"
	done
	# A wrong cause is looked for in its words, not in the paths it names
	# under the scratch root (V396).
	_said=$(_st_unrooted "$_out")
	for _p in "not searching its own tree" "leaves out of its object" "FAIL"; do
		[ -n "$_why" ] || ! printf '%s' "$_said" | grep -qF -- "$_p" || _why="said '$_p'"
	done
	if [ -z "$_why" ]; then
		printf '  %-52s %s\n' "$_n" "ok (refused, naming the loader)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_n" "FAIL < ($_why)"
		FAIL=$((FAIL + 1))
		_st_said_text "$_out"
	fi
}
for _how in rel abs; do
	cc_dead "compile_check: a compiler that cannot start ($_how)" "$_how" compile_check.sh \
		--cc @CC@ --cc-under @CC@ --src "$WORK/ccp/s.c"
	cc_dead "rl_cc_pin: a compiler that cannot start ($_how)" "$_how" asan_check.sh \
		--cc @CC@ --cc-under @CC@ --ld "$_ccp_abs_ld" --ld-lib "$_ccp_abs_ldlib" \
		--probe "$WORK/ccp/m.c" --src "$WORK/ccp/s.c"
	cc_dead "forbidden --globals: a compiler that cannot start ($_how)" "$_how" forbidden_symbols.sh \
		--cc @CC@ --nm "$_ccp_abs_nm" --nm-lib "$_ccp_abs_nmlib" --quotes "$WORK/ccp/q.tsv" \
		--globals --src "$WORK/ccp/s.c"
	# And the three that said the student's file does not compile.
	cc_dead "prototype: a compiler that cannot start ($_how)" "$_how" prototype_check.sh \
		--cc @CC@ --proto "$WORK/ccp/p.h" --src "$WORK/ccp/s.c"
	cc_dead "symbols: a compiler that cannot start ($_how)" "$_how" symbols_test.sh \
		--cc @CC@ --nm "$_ccp_abs_nm" --nm-lib "$_ccp_abs_nmlib" --expect ft_x --src "$WORK/ccp/s.c"
	cc_dead "header: a compiler that cannot start ($_how)" "$_how" header_check.sh \
		--cc @CC@ --hdr "$WORK/ccp/p.h" --main "$WORK/ccp/m.c" --expected "$WORK/ccp/e.txt" \
		--differ "$_ccp_abs_tools/diff_output.sh"
done

# A COMPILER THAT STARTS AND THEN FAILS (V241's review): it answers
# --version, so rl_cc_starts lets it by, and fails everything else with an
# error naming itself, as a driver run by an absolute path does. The proof
# of its tree read -print-search-dirs' standard error along with its output
# and no status, so that error, naming the directory, passed it, and
# compile_check.sh went on to say FAIL over the student's file; the --globals
# probe said the compiler "leaves out of its object a static" over a probe
# that never compiled. Each arm: exit 2, the right cause, the wrong one never.
mkdir -p "$WORK/ccp/mute/bin"
printf '#!/bin/sh
case "$1" in --version) echo "toy clang version 0"; exit 0 ;; esac
echo "$0: error: toy-only failure, nothing done" >&2
exit 1
' \
	> "$WORK/ccp/mute/bin/clang-12"
chmod +x "$WORK/ccp/mute/bin/clang-12"
cc_mute() {  # cc_mute NAME WANT NOTWANT RUNNER ARGS... -- @CC@ in ARGS is the stand-in, by absolute path
	_n=$1 _want=$2 _not=$3 _r=$4
	shift 4
	_i=$#
	while [ "$_i" -gt 0 ]; do
		_a=$1
		shift
		[ "$_a" != @CC@ ] || _a=$WORK/ccp/mute/bin/clang-12
		set -- "$@" "$_a"
		_i=$((_i - 1))
	done
	_out=$(cd "$WORK/ccp" && "$_ccp_abs_sh" "$_ccp_abs_tools/$_r" "$@" 2>&1)
	_rc=$?
	_why=""
	[ "$_rc" -eq 2 ] || _why="exit $_rc; it must refuse with 2"
	[ -n "$_why" ] || printf '%s' "$_out" | grep -qF -- "$_want" || _why="never said '$_want'"
	# A wrong cause is looked for in its words, not in the paths it names
	# under the scratch root (V396).
	_said=$(_st_unrooted "$_out")
	for _p in "$_not" "FAIL" "cannot start"; do
		[ -n "$_why" ] || ! printf '%s' "$_said" | grep -qF -- "$_p" || _why="said '$_p'"
	done
	if [ -z "$_why" ]; then
		printf '  %-52s %s\n' "$_n" "ok (refused, for the right cause)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_n" "FAIL < ($_why)"
		FAIL=$((FAIL + 1))
		_st_said_text "$_out"
	fi
}
cc_mute "compile_check: -print-search-dirs failing, its error naming the tree" \
	"not searching its own tree" "OK" compile_check.sh \
	--cc @CC@ --cc-under @CC@ --src "$WORK/ccp/s.c"
cc_mute "rl_cc_pin: -print-search-dirs failing, its error naming the tree" \
	"not searching its own tree" "pinned linker" asan_check.sh \
	--cc @CC@ --cc-under @CC@ --ld "$_ccp_abs_ld" --ld-lib "$_ccp_abs_ldlib" \
	--probe "$WORK/ccp/m.c" --src "$WORK/ccp/s.c"
cc_mute "forbidden --globals: a probe that does not compile says so" \
	"could not compile the --globals" "leaves out of its object" forbidden_symbols.sh \
	--cc @CC@ --nm "$_ccp_abs_nm" --nm-lib "$_ccp_abs_nmlib" --quotes "$WORK/ccp/q.tsv" \
	--globals --src "$WORK/ccp/s.c"
cc_mute "forbidden --globals: ...and shows what the compile said" \
	"toy-only failure, nothing done" "leaves out of its object" forbidden_symbols.sh \
	--cc @CC@ --nm "$_ccp_abs_nm" --nm-lib "$_ccp_abs_nmlib" --quotes "$WORK/ccp/q.tsv" \
	--globals --src "$WORK/ccp/s.c"

# UNDER A SCRATCH ROOT THAT SPELLS A WRONG CAUSE (V396). Both refusals
# above name their stand-in's path, under $WORK, and $WORK's name is
# mktemp's: random letters, which spelled OK once (tmp.OK1W13dxsC), and
# the arm went red on a correct refusal, "said 'OK'". The same two arms
# again, $WORK pointed for them at a folder named as mktemp might name it,
# holding both short words the arms look for.
_ccp_work=$WORK
mkdir -p "$WORK/tmp.OKFAIL/ccp"
cp -R "$WORK/ccp/mute" "$WORK/ccp/dead" "$WORK/ccp/s.c" "$WORK/tmp.OKFAIL/ccp/"
WORK=$_ccp_work/tmp.OKFAIL
cc_mute "compile_check: a mute compiler, the scratch root named OK" \
	"not searching its own tree" "OK" compile_check.sh \
	--cc @CC@ --cc-under @CC@ --src "$WORK/ccp/s.c"
cc_dead "compile_check: a dead compiler, the scratch root named FAIL" abs compile_check.sh \
	--cc @CC@ --cc-under @CC@ --src "$WORK/ccp/s.c"
WORK=$_ccp_work

# AN NM THAT CANNOT READ THE PROBE (V241's second review): the compile
# works and nm, which answers --version as the pinned one does (that is the
# loader's proof), fails on the object. The probe then said the compiler
# "leaves out of its object a static", blaming a compiler that kept both.
mkdir -p "$WORK/ccp/badnm"
printf '#!/bin/sh\ncase "$1" in --version) exec "%s" "$@" ;; esac\necho "$0: toy nm failure, nothing read" >&2\nexit 1\n' \
	"$_ccp_abs_nm" > "$WORK/ccp/badnm/nm"
chmod +x "$WORK/ccp/badnm/nm"
want_broken "forbidden --globals: an nm that cannot read the probe says so" \
	'could not read the object' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$WORK/ccp/badnm/nm" --nm-lib "$NM_LIB" \
		--quotes "$WORK/ccp/q.tsv" --globals --src "$WORK/ccp/s.c"
want_broken "forbidden --globals: ...and shows what nm said" \
	'toy nm failure, nothing read' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$WORK/ccp/badnm/nm" --nm-lib "$NM_LIB" \
		--quotes "$WORK/ccp/q.tsv" --globals --src "$WORK/ccp/s.c"
want_broken_without "forbidden --globals: ...and never blames the compiler" \
	'leaves out of its object' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$WORK/ccp/badnm/nm" --nm-lib "$NM_LIB" \
		--quotes "$WORK/ccp/q.tsv" --globals --src "$WORK/ccp/s.c"

# IN ITS FOLDER, NOT BELOW IT (V323). rl_libs_under, the loader's proof
# behind the pinned linker, assembler and compiler, took any loaded path
# that began with a folder's own, so a library found through a RUNPATH of
# $ORIGIN/../lib ("<folder>/../lib/x") or in a subfolder passed as staged.
# And of several libraries from elsewhere it named the first line's, which
# the loader writes for a library's own libraries first: ICU's where the
# cause was libLLVM. Hand-written loader lines take each branch on any
# machine.
mkdir -p "$WORK/lu"
lu() {  # lu NAME LINE... -- rl_libs_under over these `calling init:` lines, for libLLVM then libbfd, in $WORK/lu/lib
	_lu=$1
	shift
	for _l in "$@"; do printf '     1:\tcalling init: %s\n' "$_l"; done > "$WORK/lu/$_lu.debug"
	# shellcheck disable=SC2016 # the script is for the inner shell to expand
	"$SH" -c 'RL_NAME=selftest; . "$1"; rl_libs_under "the toy" "$2" "$3" libLLVM libbfd' _ \
		"$TOOLS/runner_lib.sh" "$WORK/lu/$_lu.debug" "$WORK/lu/lib"
}
want_green  "rl_libs_under: libraries in their folder pass" -- \
	lu in "$WORK/lu/lib/libbfd-2.38-system.so" "$WORK/lu/lib/libLLVM-12.so.1"
want_broken "rl_libs_under: one reached through ../ refuses" \
	"loaded '$WORK/lu/lib/../other/libbfd-2.38-system.so'" -- \
	lu up "$WORK/lu/lib/../other/libbfd-2.38-system.so" "$WORK/lu/lib/libLLVM-12.so.1"
want_broken "rl_libs_under: one in a subfolder refuses" \
	"loaded '$WORK/lu/lib/sub/libbfd-2.38-system.so'" -- \
	lu sub "$WORK/lu/lib/sub/libbfd-2.38-system.so" "$WORK/lu/lib/libLLVM-12.so.1"
want_broken "rl_libs_under: the first name's outsider is the one named" \
	"loaded '$WORK/lu/box/libLLVM-12.so.1'" -- \
	lu order "$WORK/lu/box/libbfd-2.38-system.so" "$WORK/lu/box/libLLVM-12.so.1"

# WHICH LIBRARIES THE PINNED CLANG LOADED (V321). rl_cc_pin put the folders
# of its libraries first on the loader's path and asked no more, and a
# library a folder lacks is found wherever the loader looks next, while
# clang starts and prints the pinned version all the same. Each tree here
# links the real pinned libraries into folders of its own: all of them,
# which passes; libxml2 only in ../lib, where libLLVM's RUNPATH
# ($ORIGIN/../lib) finds it on any machine, under a path that starts with
# the folder's own; and no libLLVM at all, with one on an LD_LIBRARY_PATH
# from outside.
_cpl_cpp="" _cpl_llvm=""
while IFS= read -r _cpl_f; do
	case "${_cpl_f##*/}" in
		libclang-cpp*) _cpl_cpp=$(_nr_abs "$_cpl_f") ;;
		libLLVM*) _cpl_llvm=$(_nr_abs "$_cpl_f") ;;
	esac
done <<_CPL
$CLANG_LIB_FILES
_CPL
mkdir -p "$WORK/cpl/all/llvm" "$WORK/cpl/all/x86" "$WORK/cpl/rp/llvm" "$WORK/cpl/rp/usr/lib/x86" \
	"$WORK/cpl/rp/usr/lib/lib" "$WORK/cpl/out/llvm" "$WORK/cpl/out/x86" "$WORK/cpl/out/outer"
for _d in all rp out; do ln -sf "$_cpl_cpp" "$WORK/cpl/$_d/llvm/libclang-cpp.so.12"; done
for _x in libLLVM-12.so.1 libxml2.so.2 libicuuc.so.70 libicudata.so.70; do
	ln -sf "${_cpl_llvm%/*}/$_x" "$WORK/cpl/all/x86/$_x"
	case $_x in
		libxml2*) ln -sf "${_cpl_llvm%/*}/$_x" "$WORK/cpl/rp/usr/lib/lib/$_x" ;;
		*) ln -sf "${_cpl_llvm%/*}/$_x" "$WORK/cpl/rp/usr/lib/x86/$_x" ;;
	esac
	case $_x in
		libLLVM*) ln -sf "${_cpl_llvm%/*}/$_x" "$WORK/cpl/out/outer/$_x" ;;
		*) ln -sf "${_cpl_llvm%/*}/$_x" "$WORK/cpl/out/x86/$_x" ;;
	esac
done
cpl() {  # cpl TREE FOLDER [OUTER] -- rl_cc_pin over the pinned clang, its libLLVM named in TREE/FOLDER
	# shellcheck disable=SC2016 # the script is for the inner shell to expand
	set -- 'RL_NAME=selftest; [ -z "$4" ] || { LD_LIBRARY_PATH=$4; export LD_LIBRARY_PATH; }
. "$1"; rl_cc_pin "$2" "$3" ""' "$TOOLS/runner_lib.sh" "$CLANG" "$WORK/cpl/$1/llvm/libclang-cpp.so.12
$WORK/cpl/$1/$2/libLLVM-12.so.1" "${3:-}"
	"$SH" -c "$1" _ "$2" "$3" "$4" "$5"
}
want_green "rl_cc_pin: the pinned clang on its staged libraries passes" -- cpl all x86
want_broken "rl_cc_pin: a libxml2 through libLLVM's RUNPATH refuses" \
	"loaded '$WORK/cpl/rp/usr/lib/x86/../lib/libxml2.so.2'" -- cpl rp usr/lib/x86
want_broken "rl_cc_pin: a libLLVM from an LD_LIBRARY_PATH outside refuses" \
	"loaded '$WORK/cpl/out/outer/libLLVM-12.so.1'" -- cpl out x86 "$WORK/cpl/out/outer"
# Its scratch file of the loader's lines goes with every answer, a refusal
# too: a hand run's TMPDIR is a /tmp that every user of the machine shares.
cpl_tmp() {  # cpl_tmp -- cpl's RUNPATH tree with a TMPDIR of its own; 0 when it refused (2) and left that folder empty
	rm -rf "$WORK/cpl/tmp"
	mkdir -p "$WORK/cpl/tmp"
	(
		TMPDIR=$WORK/cpl/tmp
		export TMPDIR
		cpl rp usr/lib/x86
	) > /dev/null 2>&1
	_cpl_rc=$?
	[ "$_cpl_rc" -eq 2 ] || { echo "rl_cc_pin exited $_cpl_rc, not 2"; return 1; }
	for _cpl_f in "$WORK/cpl/tmp"/* "$WORK/cpl/tmp"/.[!.]*; do
		[ ! -e "$_cpl_f" ] || { echo "left in its TMPDIR: ${_cpl_f##*/}"; return 1; }
	done
}
want_green "rl_cc_pin: ...and leaves no scratch file behind" -- cpl_tmp
# The same three trees through each runner that compiles before it inspects.
# These five kept a copy of rl_cc_pin's first half, written before it: each
# --cc-lib directory exists, is put on the loader's path, and the compiler
# starts. None asked the loader which libraries it took, so a pinned clang on
# this machine's libxml2 or ICU passed there while rl_cc_pin refused it.
cplr() {  # cplr TREE FOLDER OUTER RUNNER ARG... -- RUNNER over the pinned clang, as cpl's TREE/FOLDER, with LD_LIBRARY_PATH=OUTER from outside when OUTER is not ""
	_cpr_t=$1 _cpr_f=$2 _cpr_o=$3 _cpr_r=$4
	shift 4
	(
		[ -z "$_cpr_o" ] || { LD_LIBRARY_PATH=$_cpr_o; export LD_LIBRARY_PATH; }
		"$SH" "$TOOLS/$_cpr_r" --cc "$CLANG" --cc-lib "$WORK/cpl/$_cpr_t/llvm/libclang-cpp.so.12" \
			--cc-lib "$WORK/cpl/$_cpr_t/$_cpr_f/libLLVM-12.so.1" "$@"
	)
}
cpl_runner() {  # cpl_runner NAME RUNNER ARG... -- cpl's three trees, handed to RUNNER as its --cc-lib
	_cpr_n=$1
	shift
	want_green "$_cpr_n: the pinned clang on its staged libraries passes" -- \
		cplr all x86 "" "$@"
	want_broken "$_cpr_n: a libxml2 through libLLVM's RUNPATH refuses" \
		"loaded '$WORK/cpl/rp/usr/lib/x86/../lib/libxml2.so.2'" -- cplr rp usr/lib/x86 "" "$@"
	want_broken "$_cpr_n: a libLLVM from an LD_LIBRARY_PATH outside refuses" \
		"loaded '$WORK/cpl/out/outer/libLLVM-12.so.1'" -- cplr out x86 "$WORK/cpl/out/outer" "$@"
}
cpl_runner forbidden forbidden_symbols.sh --nm "$_ccnm" --nm-lib "$NM_LIB" \
	--allowed "" --src "$WORK/ccp/s.c"
cpl_runner symbols symbols_test.sh --nm "$_ccnm" --nm-lib "$NM_LIB" \
	--expect ft_x --src "$WORK/ccp/s.c"
cpl_runner prototype prototype_check.sh --proto "$WORK/ccp/p.h" --src "$WORK/ccp/s.c"
cpl_runner header header_check.sh --hdr "$WORK/ccp/p.h" --main "$WORK/ccp/m.c" \
	--expected "$WORK/ccp/e.txt" --differ "$TOOLS/diff_output.sh"
# compile_check.sh kept its own copy longest, for the assembler's libbfd its
# gcc arm passed as --cc-lib (now --cc-progs-lib, proved apart).
cpl_runner compile_check compile_check.sh --src "$WORK/ccp/s.c"


# WHICH LINKER THE TOOLCHAIN'S OWN LINK FLAGS PICK (//tools/cc_toolchain's
# provenance_test). Its link checks passed -B and -fuse-ld themselves, so a
# link_flags without -Btools/cc_toolchain/, or back on -fuse-ld=/usr/bin/
# ld.gold, sent every link to the box's linkers and the test still said OK.
# It links with the flags the resolved toolchain hands every program's link
# now (@LINK_FLAGS@, provenance.bzl): here the template is filled in with
# three sets of them, in a toy tree whose tools/cc_toolchain holds a clang.sh
# that runs the pinned clang and two linker wrappers clang can find by name.
# Only the lines that say which linker clang picked (its -### plan) are
# asked about; the toy's wrappers link nothing.
mkdir -p "$WORK/prov/tools/cc_toolchain"
_prov_dirs=$(printf '%s\n' "$CLANG_LIB_FILES" | while IFS= read -r _pl; do
	[ -n "$_pl" ] || continue
	case "$_pl" in /*) ;; *) _pl=$PWD/$_pl ;; esac
	printf '%s:' "${_pl%/*}"
done)
case "$CLANG" in /*) _prov_cc=$CLANG ;; *) _prov_cc=$PWD/$CLANG ;; esac
printf '#!/bin/sh\nLD_LIBRARY_PATH="%s"\nexport LD_LIBRARY_PATH\nexec "%s" "$@"\n' \
	"${_prov_dirs%:}" "$_prov_cc" > "$WORK/prov/tools/cc_toolchain/clang.sh"
for _pw in ld.bfd ld.gold; do
	printf '#!/bin/sh\nexit 1\n' > "$WORK/prov/tools/cc_toolchain/$_pw"
done
chmod +x "$WORK/prov/tools/cc_toolchain/clang.sh" "$WORK/prov/tools/cc_toolchain/ld.bfd" \
	"$WORK/prov/tools/cc_toolchain/ld.gold"
# prov_run FLAG... -- the template, filled in with the FLAGs as its link
# flags (one a line, as provenance.bzl writes them), run in the toy tree.
prov_run() {
	sed -e "s#@COMPILER@#$WORK/prov/tools/cc_toolchain/clang.sh#" -e "s#@AR@#$AR#" \
		"$TOOLS/cc_toolchain/provenance_test.sh" |
		awk -v flags="$(printf '%s\n' "$@")" '$0 == "@LINK_FLAGS@" { print flags; next } { print }' \
		> "$WORK/prov/provenance_test.sh"
	(cd "$WORK/prov" && "$SH" ./provenance_test.sh)
}
want_out "provenance: the toolchain's -B finds the pinned ld.bfd" \
	'ok    a bare -fuse-ld=bfd finds the pinned wrapper first' -- \
	prov_run -fuse-ld=gold -Btools/cc_toolchain/
want_out "provenance: ...and the pinned gold" \
	'ok    a link with the toolchain'"'"'s flags picks the pinned gold' -- \
	prov_run -fuse-ld=gold -Btools/cc_toolchain/
want_out "provenance: link flags without the -B are caught" \
	'FAIL  a bare -fuse-ld=bfd finds the pinned wrapper first' -- \
	prov_run -fuse-ld=gold
want_out "provenance: ...and so is gold named by the box's path" \
	'FAIL  a link with the toolchain'"'"'s flags picks the pinned gold' -- \
	prov_run -fuse-ld=/usr/bin/ld.gold -Btools/cc_toolchain/
# A pinned gold that starts and then fails to link: the loader's lines name
# the pinned ld.gold all the same, so only the link's own output says it
# failed -- and check 3's bfd link has already left an executable t behind.
# A stand-in clang.sh and ar, in a toy tree of their own, print the loader's
# lines a pinned run would (the template runs them under LD_DEBUG=libs, so
# the shell's own lines come too, and name nothing the checks ask about),
# and link into -o with whichever linker the last -fuse-ld names, gold
# failing where PROVG_GOLD=fail.
mkdir -p "$WORK/provg/tools/cc_toolchain"
printf '%s\n' '#!/bin/sh' \
	'# The selftest'"'"'s stand-in clang: the loader'"'"'s lines, then the link.' \
	'o=""; ld=gold; plan=0; cc=0' \
	'while [ $# -gt 0 ]; do' \
	'	case $1 in -o) o=$2; shift ;; -fuse-ld=bfd) ld=bfd ;; -fuse-ld=*) ld=gold ;; -###) plan=1 ;; -c) cc=1 ;; esac' \
	'	shift' 'done' \
	'p=/x/external/clang_12_ubuntu; b=/x/external/binutils_x86_64_linux_gnu' \
	'if [ "$plan" = 1 ]; then printf '"'"' "%s/tools/cc_toolchain/ld.%s"\n'"'"' "$PWD" "$ld" >&2; exit 0; fi' \
	'if [ "$cc" = 1 ]; then' \
	'	printf '"'"'1:\tinitialize program: %s\n'"'"' "$p/bin/clang-12" >&2' \
	'	for l in libclang-cpp.so.12 libLLVM-12.so.1 libxml2.so.2 libicuuc.so.66; do' \
	'		printf '"'"'1:\tcalling init: %s/lib/%s\n'"'"' "$p" "$l" >&2' \
	'	done' \
	'	: > "$o"' '	exit 0' 'fi' \
	'printf '"'"'1:\tinitialize program: %s/bin/ld.%s\n'"'"' "$b" "$ld" >&2' \
	'[ "$ld" = bfd ] && printf '"'"'1:\tcalling init: %s/lib/%s\n'"'"' "$b" libbfd-2.34.so "$b" libctf.so.0 >&2' \
	'if [ "$ld" = gold ] && [ "${PROVG_GOLD:-}" = fail ]; then' \
	'	echo "ld.gold: fatal error: a link that starts and fails" >&2' '	exit 1' 'fi' \
	'printf '"'"'#!/bin/sh\n'"'"' > "$o"' 'chmod +x "$o"' \
	> "$WORK/provg/tools/cc_toolchain/clang.sh"
printf '%s\n' '#!/bin/sh' '# The selftest'"'"'s stand-in ar: the loader'"'"'s lines.' \
	'b=/x/external/binutils_x86_64_linux_gnu' \
	'printf '"'"'1:\tinitialize program: %s/bin/ar\n1:\tcalling init: %s/lib/libbfd-2.34.so\n'"'"' "$b" "$b" >&2' \
	> "$WORK/provg/tools/cc_toolchain/ar"
chmod +x "$WORK/provg/tools/cc_toolchain/clang.sh" "$WORK/provg/tools/cc_toolchain/ar"
# provg_run GOLD: the template over the stand-ins, its gold linking or not.
provg_run() {
	sed -e "s#@COMPILER@#$WORK/provg/tools/cc_toolchain/clang.sh#" \
		-e "s#@AR@#$WORK/provg/tools/cc_toolchain/ar#" \
		"$TOOLS/cc_toolchain/provenance_test.sh" |
		awk '$0 == "@LINK_FLAGS@" { print "-fuse-ld=gold"; print "-Btools/cc_toolchain/"; next } { print }' \
		> "$WORK/provg/provenance_test.sh"
	(cd "$WORK/provg" && env PROVG_GOLD="$1" "$SH" ./provenance_test.sh)
}
want_green "provenance: a pinned toolchain whose every tool runs and links is OK" -- provg_run ok
want_out "provenance: a pinned gold that starts and fails to link is caught" \
	'FAIL  the pinned ld.gold links' -- provg_run fail
want_red "provenance: ...and the test fails" -- provg_run fail

# THE SLOW SELFTEST'S OWN PINS: the valgrind it runs and the two files that
# name its tool folder, memcheck's and callgrind's. Only --valgrind was
# required: a hand run without --valgrind-tools left a bare option in the
# words handed to every memcheck arm, which took the next word as its value,
# so each arm failed on "unknown option" and named nothing that was missing.
# Each is a wiring error, exit 2 and the option's name, before any arm or
# the compiler's proof runs, so these arms hand over no compiler at all, and
# the callgrind file stands in for memcheck's, which this suite is not given.
want_broken "selftest_slow: a missing --valgrind-tools refuses, naming it" \
	'--valgrind-tools is required' -- \
	"$SH" "$TOOLS/tests/selftest_slow.sh" --anchor "$TOOLS/diff_output.sh" \
		--valgrind "$VALGRIND" --valgrind-callgrind-tools "$VGCGTOOLS"
want_broken "selftest_slow: ...and so does a missing --valgrind-callgrind-tools" \
	'--valgrind-callgrind-tools is required' -- \
	"$SH" "$TOOLS/tests/selftest_slow.sh" --anchor "$TOOLS/diff_output.sh" \
		--valgrind "$VALGRIND" --valgrind-tools "$VGCGTOOLS"
want_broken "selftest_slow: ...and a missing --valgrind, before the compiler's" \
	'--valgrind is required' -- \
	"$SH" "$TOOLS/tests/selftest_slow.sh" --anchor "$TOOLS/diff_output.sh"
# A --valgrind that was given but names no program is not a missing one:
# the refusal says which, as the layers' probe (rl_vg_pin) does.
want_broken "selftest_slow: ...and one given that is not a program says so" \
	'pinned valgrind missing or not executable: '"$WORK/no-valgrind.bin" -- \
	"$SH" "$TOOLS/tests/selftest_slow.sh" --anchor "$TOOLS/diff_output.sh" \
		--valgrind "$WORK/no-valgrind.bin" --valgrind-tools "$VGCGTOOLS" --valgrind-callgrind-tools "$VGCGTOOLS"
