#!/bin/sh
# binutils.sh TOOL ARGS... -- run the fetched binutils 2.38 TOOL.
#
# The pinned C++ toolchain's archiver and linkers. Reached through the
# one-line scripts beside it (ar, ld, ld.bfd, ld.gold, nm, objcopy, objdump,
# strip), which exist because clang finds a linker by NAME: `-fuse-ld=bfd`
# makes it search its -B directories for `ld.bfd`, and the toolchain's link
# flags put this directory first. That is how the bare `-fuse-ld=bfd` in
# tools/defs.bzl and .bazelrc now resolves to a pinned linker instead of the
# box's /usr/bin/ld.bfd -- TODO.md §21's refutation #3.
#
# Binutils ships frontends: ld.bfd, ar and friends are small programs over
# libbfd, libctf and libopcodes, named as bare sonames with no RUNPATH. So the
# fetched libraries go on the loader's path here, for the same reason clang.sh
# does it for clang.
set -u
. "$(dirname "$0")/pinned.sh"
[ $# -ge 1 ] || { echo "binutils.sh: which tool?" >&2; exit 2; }
_tool=$1
shift
BINUTILS_REPO=$(pinned_repo binutils_x86_64_linux_gnu) || exit 2
LD_LIBRARY_PATH="$PWD/$BINUTILS_REPO/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "$BINUTILS_REPO/usr/bin/x86_64-linux-gnu-$_tool" "$@"
