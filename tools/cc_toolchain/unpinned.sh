#!/bin/sh
# unpinned.sh -- the tool_path for every tool this toolchain does NOT pin.
#
# A C++ toolchain has to name a cpp, a dwp, a gcov and a c++filt, and nothing
# in this repo invokes any of them: C is preprocessed by the compiler itself,
# and there is no split DWARF, no coverage build and no C++ here. Pointing them
# at /usr/bin would be a quiet fallback to the machine the day something did
# start calling one -- so it fails, loudly, and says which.

# The external commands this script takes from PATH, declared and probed
# like the runners' (diff_output.sh says why): exit 2 when one is missing.
# The wrappers beside it, binutils.sh and clang.sh carry a no-require
# marker instead, each with its reason: they run at every call of a pinned
# tool, where a missing dirname already stops them, and a probe there
# would buy nothing.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "unpinned.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require basename

echo "pinned toolchain: $(basename "$0") was invoked with: $*" >&2
echo "  This toolchain does not pin that tool, because nothing in this repo" >&2
echo "  used it. Something now does: fetch it in MODULE.bazel and point" >&2
echo "  tools/cc_toolchain's tool_paths at it, rather than at the box's copy." >&2
exit 1
