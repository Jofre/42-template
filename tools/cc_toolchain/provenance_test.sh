#!/bin/sh
# provenance_test.sh -- does the RESOLVED C++ toolchain run the pinned tools?
#
# Generated into a test by provenance.bzl, with @COMPILER@ and @AR@ replaced by
# what toolchain resolution chose, and @LINK_FLAGS@ by the flags that
# toolchain hands a program's link. Every assertion below reads the LOADER's
# answer -- LD_DEBUG=libs, `calling init:` for each library it loaded and
# `initialize program:` for what it actually ran -- because the failures this
# exists for are all ones where the right file is exec'd and the wrong code
# runs.
set -u

# The external commands this test takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the toolchain under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "provenance_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require cat grep head mktemp rm sed

# Each capture below reads the loader's lines from stderr: an LD_DEBUG_OUTPUT
# set from outside (--test_env) would send them to files of its own, and
# every check would find nothing to read (V276).
unset LD_DEBUG_OUTPUT

COMPILER="@COMPILER@"
AR="@AR@"

# The flags the resolved toolchain gives every program's link (its
# link_flags, and every feature an executable's link turns on; provenance.bzl),
# one a line. The here-document is quoted, so each line is one argument
# exactly as written.
LINK_FLAGS=$(cat <<'LINK_FLAGS_EOF'
@LINK_FLAGS@
LINK_FLAGS_EOF
)

# link ARGS... -- a link with those flags, then ARGS, split at the newlines
# alone and never globbed. The link checks below pass no -B or -fuse-ld of
# their own: that the toolchain's flags route a link to the pinned linkers is
# what they check. They used to pass both, so a link_flags that sent every
# link to the box's linkers left them green.
link() (
	set -f
	IFS='
'
	# shellcheck disable=SC2086 # one flag a line, split at the newlines alone
	"$COMPILER" $LINK_FLAGS "$@"
)

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
# tools/runner_lib.sh's rl_libs_under is the harness's reader of them, and
# tools/conventions.sh holds every other script to it; this test is the one
# it names as keeping its own ("a script reads the loader's lines itself"):
# it asks one substring of each path, and stages no runner_lib.sh. For that
# last reason it also runs its programs under LD_DEBUG=libs itself, beside
# rl_probe_libs, and the rule after that one names it too.
programs() { sed -n 's/.*initialize program: //p' "$1" > "$1.prog"; }
libraries() { sed -n 's/.*calling init: //p' "$1" > "$1.libs"; }

# A test's scratch files go under TEST_TMPDIR, which Bazel empties, and not
# in the machine's /tmp, the TMPDIR Bazel sets when the shell that ran it set
# none (tools/runner_lib.sh, "THE SCRATCH FOLDER").
case ${TMPDIR:-/tmp} in /tmp | /tmp/) [ -z "${TEST_TMPDIR:-}" ] || export TMPDIR="$TEST_TMPDIR" ;; esac
WORK=$(mktemp -d) || { echo "provenance_test.sh: cannot create a scratch directory" >&2; exit 2; }
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
every_under "$WORK/cc.dbg.libs" 'libxml2|libicu' 'clang_12_ubuntu' "the libxml2 and ICU its libLLVM loads are the pinned ones"

# 3. The link: which linker clang CHOSE by name, and what that linker loaded.
#    -fuse-ld=bfd is the bare form tools/defs.bzl and .bazelrc both pass, after
#    the toolchain's own flags, and it used to resolve through PATH to
#    /usr/bin/ld.bfd: the -B in those flags is what finds the pinned one first.
_chosen=$(link -### "$WORK/t.o" -o "$WORK/t" -fuse-ld=bfd 2>&1 |
	grep -oE '"[^"]*ld\.bfd"' | head -1)
case "$_chosen" in
	*tools/cc_toolchain/ld.bfd*) ok "a bare -fuse-ld=bfd finds the pinned wrapper first" ;;
	*) bad "a bare -fuse-ld=bfd finds the pinned wrapper first" "clang chose: ${_chosen:-nothing}" ;;
esac
LD_DEBUG=libs link "$WORK/t.o" -o "$WORK/t" -fuse-ld=bfd > /dev/null 2> "$WORK/ld.dbg"
[ -x "$WORK/t" ] || bad "the pinned ld.bfd links" "$(grep -v '^ *[0-9]*:' "$WORK/ld.dbg" | head -3)"
programs "$WORK/ld.dbg"
every_under "$WORK/ld.dbg.prog" 'ld\.bfd$' 'binutils_x86_64_linux_gnu' "the ld.bfd that ran is the pinned one"
libraries "$WORK/ld.dbg"
every_under "$WORK/ld.dbg.libs" 'libbfd|libctf' 'binutils_x86_64_linux_gnu' "its libbfd and libctf are the pinned ones"

# 4. The default linker, gold, the same way: the one the toolchain's flags
#    name, that it links, and what it ran. Into a file of its own: check 3
#    left an executable t, which a gold that starts and then fails would
#    leave in place, and the loader's lines name the pinned gold either way.
_chosen=$(link -### "$WORK/t.o" -o "$WORK/t.gold" 2>&1 | grep -oE '"[^"]*ld\.gold"' | head -1)
case "$_chosen" in
	*tools/cc_toolchain/ld.gold*) ok "a link with the toolchain's flags picks the pinned gold wrapper" ;;
	*) bad "a link with the toolchain's flags picks the pinned gold wrapper" "clang chose: ${_chosen:-nothing}" ;;
esac
LD_DEBUG=libs link "$WORK/t.o" -o "$WORK/t.gold" > /dev/null 2> "$WORK/gold.dbg"
[ -x "$WORK/t.gold" ] || bad "the pinned ld.gold links" "$(grep -v '^ *[0-9]*:' "$WORK/gold.dbg" | head -3)"
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
echo "provenance: OK -- every tool the resolved toolchain ran came from the"
echo "            pinned tree, and so did each library checked above"
echo "            (libclang-cpp, libLLVM, libxml2, ICU, libbfd, libctf). What"
echo "            the tools load from the box instead is docs/environment.md's"
echo "            list (\"What the harness borrows from the box\"), held to them"
echo "            by //tools/tests:fetched_needed."
