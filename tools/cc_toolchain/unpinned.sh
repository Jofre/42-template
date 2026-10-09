#!/bin/sh
# unpinned.sh -- the tool_path for every tool this toolchain does NOT pin.
#
# A C++ toolchain has to name a cpp, a dwp, a gcov and a c++filt, and nothing
# in this repo invokes any of them: C is preprocessed by the compiler itself,
# and there is no split DWARF, no coverage build and no C++ here. Pointing them
# at /usr/bin would be a quiet fallback to the machine the day something did
# start calling one -- so it fails, loudly, and says which.
echo "pinned toolchain: $(basename "$0") was invoked with: $*" >&2
echo "  This toolchain does not pin that tool, because nothing in this repo" >&2
echo "  used it. Something now does: fetch it in MODULE.bazel and point" >&2
echo "  tools/cc_toolchain's tool_paths at it, rather than at the box's copy." >&2
exit 1
