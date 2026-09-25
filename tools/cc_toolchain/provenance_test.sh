#!/bin/sh
# provenance_test.sh -- does the RESOLVED C++ toolchain run the pinned tools?
#
# Generated into a test by provenance.bzl, with @COMPILER@ and @AR@ replaced by
# what toolchain resolution chose. Every assertion below reads the LOADER's
# answer -- LD_DEBUG=libs, `calling init:` for each library it loaded and
# `initialize program:` for what it actually ran -- because the failures this
# exists for are all ones where the right file is exec'd and the wrong code
# runs. See TODO.md §21.
set -u

COMPILER="@COMPILER@"
AR="@AR@"

FAIL=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); shift; for l in "$@"; do printf '          %s\n' "$l"; done; }

# every_under FILE PATTERN SUBSTRING LABEL: of the paths in FILE (one per line,
# as the loader reported them), those matching PATTERN must be non-empty, and
# every one must contain SUBSTRING -- the staged repository's name. Wrapper
# scripts never match: the loader reports a script as its interpreter, /bin/sh,
# and the tool it then execs by the path it was exec'd with -- which is the
# thing checked.
#
# A FILE, NOT A PIPE, and that is not style. This first read its list from
# stdin, called as `sed ... | every_under ...` -- and in POSIX sh the last
# command of a pipeline runs in a SUBSHELL, so the FAIL it counted was counted
# in a process that then exited. Mutation-tested, three of four broken
# toolchains printed their FAIL lines and then "provenance: OK", exit 0: the
# exact false green this repo is built against, in the check written to stop
# one.
every_under() {
	_eu=$(grep -E -- "$2" "$1")
	if [ -z "$_eu" ]; then
		bad "$4" "the loader reported no $2 at all, so nothing was checked"
		return
	fi
	_off=$(printf '%s\n' "$_eu" | grep -vF -- "$3")
	if [ -n "$_off" ]; then
		bad "$4" "loaded from outside the pinned tree:" "$_off"
	else
		ok "$4"
	fi
}

# The loader's two kinds of line, from one LD_DEBUG capture, into two files.
programs() { sed -n 's/.*initialize program: //p' "$1" > "$1.prog"; }
libraries() { sed -n 's/.*calling init: //p' "$1" > "$1.libs"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
printf 'int main(void){return (0);}\n' > "$WORK/t.c"

echo "provenance: the C++ toolchain this build resolves"
echo "  compiler: $COMPILER"
echo "  ar:       $AR"
echo ""

# 1. Toolchain resolution chose OURS. If the auto-detected toolchain wins, this
#    is /usr/lib/llvm-12/bin/clang and everything below would be measuring it.
case "$COMPILER" in
	*tools/cc_toolchain/clang.sh) ok "resolution picked //tools/cc_toolchain" ;;
	*) bad "resolution picked //tools/cc_toolchain" "it picked '$COMPILER'" ;;
esac

# 2. The compile: which clang RAN, and which libraries it loaded.
LD_DEBUG=libs "$COMPILER" -c "$WORK/t.c" -o "$WORK/t.o" > /dev/null 2> "$WORK/cc.dbg"
[ -f "$WORK/t.o" ] || bad "the pinned compiler compiles" "$(grep -v '^ *[0-9]*:' "$WORK/cc.dbg" | head -3)"
programs "$WORK/cc.dbg"
every_under "$WORK/cc.dbg.prog" 'clang(-12)?$' 'clang_12_ubuntu' "the compiler that ran is the pinned clang-12"
libraries "$WORK/cc.dbg"
every_under "$WORK/cc.dbg.libs" 'libclang-cpp|libLLVM' 'clang_12_ubuntu' "its libclang-cpp and libLLVM are the pinned ones"

# 3. The link: which linker clang CHOSE by name, and what that linker loaded.
#    -fuse-ld=bfd is the bare form tools/defs.bzl and .bazelrc both pass, and it
#    used to resolve through PATH to /usr/bin/ld.bfd -- §21's refutation #3.
_chosen=$("$COMPILER" -### -fuse-ld=bfd -Btools/cc_toolchain/ "$WORK/t.o" -o "$WORK/t" 2>&1 |
	grep -oE '"[^"]*ld\.bfd"' | head -1)
case "$_chosen" in
	*tools/cc_toolchain/ld.bfd*) ok "a bare -fuse-ld=bfd finds the pinned wrapper first" ;;
	*) bad "a bare -fuse-ld=bfd finds the pinned wrapper first" "clang chose: ${_chosen:-nothing}" ;;
esac
LD_DEBUG=libs "$COMPILER" -fuse-ld=bfd -Btools/cc_toolchain/ "$WORK/t.o" -o "$WORK/t" > /dev/null 2> "$WORK/ld.dbg"
[ -x "$WORK/t" ] || bad "the pinned ld.bfd links" "$(grep -v '^ *[0-9]*:' "$WORK/ld.dbg" | head -3)"
programs "$WORK/ld.dbg"
every_under "$WORK/ld.dbg.prog" 'ld\.bfd$' 'binutils_x86_64_linux_gnu' "the ld.bfd that ran is the pinned one"
libraries "$WORK/ld.dbg"
every_under "$WORK/ld.dbg.libs" 'libbfd|libctf' 'binutils_x86_64_linux_gnu' "its libbfd and libctf are the pinned ones"

# 4. The default linker, gold, the same way.
LD_DEBUG=libs "$COMPILER" -fuse-ld=gold -Btools/cc_toolchain/ "$WORK/t.o" -o "$WORK/t" > /dev/null 2> "$WORK/gold.dbg"
programs "$WORK/gold.dbg"
every_under "$WORK/gold.dbg.prog" 'ld\.gold$' 'binutils_x86_64_linux_gnu' "the default linker (gold) is the pinned one"

# 5. The archiver every cc_library goes through.
LD_DEBUG=libs "$AR" rcs "$WORK/t.a" "$WORK/t.o" > /dev/null 2> "$WORK/ar.dbg"
programs "$WORK/ar.dbg"
every_under "$WORK/ar.dbg.prog" 'ar$' 'binutils_x86_64_linux_gnu' "the ar that ran is the pinned one"
libraries "$WORK/ar.dbg"
every_under "$WORK/ar.dbg.libs" 'libbfd' 'binutils_x86_64_linux_gnu' "its libbfd is the pinned one"

echo ""
if [ "$FAIL" -ne 0 ]; then
	echo "provenance: FAIL -- $FAIL check(s). The toolchain builds, and some of"
	echo "            what it runs is not what MODULE.bazel pins."
	exit 1
fi
echo "provenance: OK -- every tool the resolved toolchain ran, and every library"
echo "            it loaded, came from the pinned tree."
