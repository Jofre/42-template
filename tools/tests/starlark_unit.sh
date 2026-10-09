#!/bin/sh
# starlark_unit.sh -- report the checks starlark_unit.bzl ran at load time.
#
# The checks themselves ran while Bazel loaded //tools/tests (a macro's
# decision is made there, from a glob, and never reaches a runner). Each
# argument is one case: its description when it held, "FAIL ..." with what
# it got and wanted when it did not. This prints them and exits 1 on any
# FAIL, so a disagreement is a red test naming the case rather than a load
# error that takes the package down with it.
#
# Usage:
#   starlark_unit.sh CASE...
set -u

[ $# -gt 0 ] || { echo "starlark_unit.sh: no cases: nothing was checked" >&2; exit 2; }
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
