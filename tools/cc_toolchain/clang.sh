#!/bin/sh
# clang.sh -- the pinned C++ toolchain's COMPILER and link driver.
#
# Execs the fetched clang-12 (campus's exact 12.0.1-19ubuntu3) with its own
# libclang-cpp and libLLVM on the loader's path. Both are named by the driver as
# bare sonames with no RPATH and no RUNPATH, so without this the loader takes
# them from the box and 100 KB of pinned driver runs 140 MB of the machine's
# compiler -- still reporting the pinned version, because that string is in the
# driver. //tools/cc_toolchain:provenance_test checks the loader's answer,
# which is the only thing that can tell the two apart.
#
# The clang path stays RELATIVE; LD_LIBRARY_PATH is made absolute. clang runs
# with -no-canonical-prefixes, so the path it is exec'd by is the path it
# reports its resource headers under, and Bazel accepts a header only at the
# exec-root-relative path it staged it at. The loader has no such constraint,
# and an absolute entry cannot change meaning if a child changes directory.
set -u
. "$(dirname "$0")/pinned.sh"
CLANG_REPO=$(pinned_repo clang_12_ubuntu) || exit 2
LD_LIBRARY_PATH="$PWD/$CLANG_REPO/usr/lib/llvm-12/lib:$PWD/$CLANG_REPO/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "$CLANG_REPO/usr/lib/llvm-12/bin/clang-12" "$@"
