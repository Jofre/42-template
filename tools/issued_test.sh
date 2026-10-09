#!/bin/sh
# issued_test.sh -- a file 42 issues with a subject, and the subject turns in,
# is in the turn-in (tag "output", basic; tools/defs.bzl's c_issued).
#
# WHY IT EXISTS. Rush 02's one-argument form, `./rush-02 42`, reads
# numbers.dict from where the program runs, and "Files to turn in: Makefile
# and all the necessary files" makes 42's dictionary part of the turn-in. The
# template ships no copy (it is 42's file, tools/resources.tsv), its
# .gitignore keeps a student's copy out of every commit, and nothing said
# when one was missing: a team could push a rush-02 that answers Dict Error
# at the defence while every test was green (finding 162). A SKIP would have
# said it and still exited 0, so submit would have pushed it anyway; this is
# a failure, at basic, beside the program's own output tests.
#
# WHAT IT READS. The registry row whose path is --path: where a student gets
# the file, and that its role is turn-in. The words of the report are the
# registry's, so this message cannot send anyone to another place than the
# strip rule, the ignore rule, the placeholder and the docs do. And the
# names a glob of that path found when Bazel loaded the package (a names
# file, as the files layer reads its list): a label naming the file would
# take the package down on the template, where it is absent by design.
#
# Usage:
#   issued_test.sh --registry FILE --path PATH --found-list FILE
#
#   --registry    tools/resources.tsv
#   --path        where the turn-in holds the file, from the repository root
#                 (the project's turn-in directory and the file's name)
#   --found-list  what the glob of PATH found, one path per line: PATH, or
#                 nothing
#
# Exit: 0 it is there and not empty; 1 it is missing or empty; 2 the harness
# broke (no registry row for PATH, a row whose role is not turn-in, an
# unreadable list).
set -u

# The external commands this runner takes from PATH. See diff_output.sh for
# why they are declared and probed; exit 2, never 1, because this says the
# check never ran rather than that the turn-in is incomplete.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "issued_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk grep wc

# conventions: runs no student code -- it looks for one file of 42's in the turn-in and reads the registry of those files

REGISTRY=""
WANT=""
FOUND=""

need() { [ "$2" -ge 2 ] || { echo "issued_test.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--registry) need "$1" "$#"; REGISTRY="$2"; shift 2 ;;
		--path) need "$1" "$#"; WANT="$2"; shift 2 ;;
		--found-list) need "$1" "$#"; FOUND="$2"; shift 2 ;;
		*) echo "issued_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$REGISTRY" ] && [ -n "$WANT" ] && [ -n "$FOUND" ] || {
	echo "issued_test.sh: need --registry, --path and --found-list" >&2
	exit 2
}
[ -r "$REGISTRY" ] || { echo "issued_test.sh: cannot read the registry '$REGISTRY'" >&2; exit 2; }
[ -r "$FOUND" ] || { echo "issued_test.sh: cannot read the list '$FOUND'" >&2; exit 2; }

# The row: project, file, path, role, strip, consumers, named-in, source.
ROW=$(awk -F'\t' -v p="$WANT" '!/^#/ && NF == 8 && $3 == p' "$REGISTRY")
if [ -z "$ROW" ]; then
	echo "issued_test.sh: tools/resources.tsv has no row whose path is $WANT." >&2
	echo "  c_issued names a file 42 issues: register it there first, with the" >&2
	echo "  path the turn-in holds it at, so the template strips and ignores it." >&2
	exit 2
fi
NAME=$(printf '%s\n' "$ROW" | awk -F'\t' '{ print $2 }')
ROLE=$(printf '%s\n' "$ROW" | awk -F'\t' '{ print $4 }')
SOURCE=$(printf '%s\n' "$ROW" | awk -F'\t' '{ print $8 }')
if [ "$ROLE" != turn-in ]; then
	echo "issued_test.sh: tools/resources.tsv gives $NAME the role '$ROLE', not turn-in:" >&2
	echo "  the tests read it and it is never turned in, so its tests SKIP while it is" >&2
	echo "  absent (its consumers), and no turn-in has to carry it." >&2
	exit 2
fi

if grep -qxF "$WANT" "$FOUND" && [ -s "$WANT" ]; then
	echo "issued: OK — $NAME is in the turn-in, at $WANT ($(wc -c < "$WANT" | awk '{ print $1 }') bytes)."
	exit 0
fi

if grep -qxF "$WANT" "$FOUND"; then
	echo "issued: FAIL — $WANT is empty."
else
	echo "issued: FAIL — $NAME is not in the turn-in: $WANT is missing."
fi
echo ""
echo "  $NAME is 42's file, issued with the subject, and this project turns it in"
echo "  (tools/resources.tsv gives it the role turn-in). Download it from $SOURCE,"
echo "  and save it as"
echo ""
echo "      $WANT"
echo ""
echo "  The template's .gitignore keeps that copy out of your commits, because it"
echo "  is 42's to hand out, and //tools:submit pushes it anyway: it pushes the"
echo "  folder as it is on disk. So every teammate, and every fresh clone,"
echo "  downloads their own."
exit 1
