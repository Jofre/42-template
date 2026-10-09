#!/bin/sh
# The arms of //tools/tests:starlark_selftest ran while Bazel loaded
# tools/tests/BUILD.bazel: defs.bzl's starlark_selftest() calls each fail()
# guard on an input it must refuse and on one it must accept, and a wrong answer
# fails that load -- so this test exists only when every arm held. It prints
# what was checked, one arm per argument.
#
# --arms N says how many arm names follow, and --apostrophe a sentence holding
# ASCII apostrophes, '$', double quotes and a backslash: both reach this
# script through defs.bzl's
# shell_word, the quoting every hand-written args word takes (an exit_quote to
# diff_output.sh, a reason to a corpus runner), and Bazel's expansion and
# shell-like tokenising of a test's args. A count that differs, or a sentence
# that did not arrive whole, is that quoting broken (exit 1).
#
# Usage: starlark_selftest.sh --arms N --apostrophe SENTENCE ARM...
set -u
[ $# -ge 4 ] && [ "$1" = --arms ] && [ "$3" = --apostrophe ] || {
	echo "starlark_selftest.sh: usage: --arms N --apostrophe SENTENCE ARM..." >&2
	exit 2
}
_n=$2
_ap=$4
shift 4
case "$_n" in "" | *[!0-9]*) echo "starlark_selftest.sh: --arms needs a count, not '$_n'" >&2; exit 2 ;; esac
[ "$_n" -gt 0 ] || { echo "starlark_selftest.sh: no arms were passed" >&2; exit 2; }
if [ "$#" -ne "$_n" ]; then
	echo "starlark_selftest: $_n arm names were passed and $# arrived: Bazel split or joined"
	echo "  one, so the quoting of a test's args (tools/defs.bzl's shell_word) is broken."
	exit 1
fi
if [ "$_ap" != 'the system'\''s tail, as the subject'\''s sentence prints it: $? and $(x) too, $1 == "" and \ as well' ]; then
	echo "starlark_selftest: a sentence with apostrophes, '\$', quotes and a backslash arrived as [$_ap]: the"
	echo "  quoting of a test's args (tools/defs.bzl's shell_word) does not keep it whole."
	exit 1
fi
echo "starlark_selftest: the defs.bzl guards, checked while Bazel loaded this package:"
for _a in "$@"; do
	printf '  %-66s ok\n' "$_a"
done
