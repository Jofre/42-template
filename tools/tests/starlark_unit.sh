#!/bin/sh
# starlark_unit.sh -- report the checks starlark_unit.bzl ran at load time.
#
# The checks themselves ran while Bazel loaded //tools/tests (a macro's
# decision is made there, from a glob, and never reaches a runner; a fail()
# guard's arms are written beside it, in tools/defs_module.bzl). Each
# argument is one case: its description when it held, "FAIL ..." with what
# it got and wanted when it did not. This prints them and exits 1 on any
# FAIL, so a disagreement is a red test naming the case rather than a load
# error that takes the package down with it.
#
# --cases N says how many cases follow, and --apostrophe a sentence holding
# ASCII apostrophes, '$', double quotes and a backslash: both reach this
# script through defs.bzl's shell_word, the quoting every hand-written args
# word takes (an exit_quote to diff_output.sh, a reason to a corpus runner),
# and Bazel's expansion and shell-like tokenising of a test's args. A count
# that differs, or a sentence that did not arrive whole, is that quoting
# broken (exit 1): a case split in two would otherwise read as two that held.
#
# Usage:
#   starlark_unit.sh --cases N --apostrophe SENTENCE CASE...
set -u

[ $# -ge 4 ] && [ "$1" = --cases ] && [ "$3" = --apostrophe ] || {
	echo "starlark_unit.sh: usage: --cases N --apostrophe SENTENCE CASE..." >&2
	exit 2
}
_n=$2
_ap=$4
shift 4
case "$_n" in "" | *[!0-9]*) echo "starlark_unit.sh: --cases needs a count, not '$_n'" >&2; exit 2 ;; esac
[ "$_n" -gt 0 ] && [ $# -gt 0 ] || { echo "starlark_unit.sh: no cases: nothing was checked" >&2; exit 2; }
if [ "$#" -ne "$_n" ]; then
	echo "starlark_unit: $_n cases were passed and $# arrived: Bazel split or joined"
	echo "  one, so the quoting of a test's args (tools/defs.bzl's shell_word) is broken."
	exit 1
fi
if [ "$_ap" != 'the system'\''s tail, as the subject'\''s sentence prints it: $? and $(x) too, $1 == "" and \ as well' ]; then
	echo "starlark_unit: a sentence with apostrophes, '\$', quotes and a backslash arrived as [$_ap]: the"
	echo "  quoting of a test's args (tools/defs.bzl's shell_word) does not keep it whole."
	exit 1
fi
fails=0
for c in "$@"; do
	case "$c" in
		"FAIL "*) fails=$((fails + 1)); printf '  %s\n' "$c" ;;
		*) printf '  ok   %s\n' "$c" ;;
	esac
done
if [ "$fails" -gt 0 ]; then
	printf 'starlark_unit: FAIL -- %d of %d case(s)\n' "$fails" "$#"
	exit 1
fi
printf 'starlark_unit: OK (%d cases)\n' "$#"
