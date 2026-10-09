#!/bin/sh
# no_turnin.sh — the test a layer becomes when the files it checks are not there.
#
# A layer that reads the student's files (norm, compile, forbidden, prototype,
# symbols, a runner that compiles at test time) cannot run without them. They
# used to reach the build as literal paths, so a missing one was a Bazel
# "missing input file" -- or, for a glob that must not be empty, an error that
# failed the loading of the whole package -- or they arrived as an empty list,
# and the runner exited 2 as though the harness were broken. None of those says
# the one thing that is true: nothing was turned in there.
#
# tools/defs.bzl's _test() emits this in the layer's place, under the same name,
# tags and level, whenever the glob that finds the layer's files comes back
# empty. It fails -- exit 1, the verdict: a grader finds nothing there either --
# and says where the files were looked for.
#
# --gated: the layer it stands in for is one that SKIPS while its exercise has
# nothing for it to say yet (a correctness gate, or a second reading of a layer
# that already reports). Then this SKIPS too -- exit 0, saying why -- unless
# NO_SKIP=1: the files, norm and compile layers already say the file is
# missing, and a missing file must not be ten more reds than a file that does
# not compile, which those same layers skip.
#
# --misplaced DIR: files were found in DIR, an exNN/ folder under a turn-in
# at the root of deliverable/ -- a subject with no turn-in directory (BSQ,
# the Common Core) turned in the way the modules with one are. Said, with the
# command that moves them up, because "has none of the files" is otherwise all
# a student reads while the files sit one folder down.
#
# Usage:
#   no_turnin.sh --test LABEL --where DIR [--gated] [--misplaced DIR]...
set -u

TEST=""
WHERE=""
GATED=0
MISPLACED=""

need() { [ "$2" -ge 2 ] || { echo "no_turnin.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--test) need "$1" "$#"; TEST="$2"; shift 2 ;;
		--where) need "$1" "$#"; WHERE="$2"; shift 2 ;;
		--gated) GATED=1; shift ;;
		--misplaced) need "$1" "$#"; MISPLACED="$MISPLACED$2
"; shift 2 ;;
		*) echo "no_turnin.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$TEST" ] && [ -n "$WHERE" ] || {
	echo "no_turnin.sh: --test and --where are required" >&2
	exit 2
}

# The opening words are tools/standin.sh's NOTURNIN_MARK, which
# tools/first_red.sh looks for in a test log.
case "$0" in */*) _sl_dir=${0%/*} ;; *) _sl_dir=. ;; esac
for _sl in "$_sl_dir/standin.sh" \
	"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
	[ -f "$_sl" ] && break
done
[ -f "$_sl" ] || { echo "no_turnin.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"

if [ "$GATED" -eq 1 ] && [ "${NO_SKIP:-0}" != 1 ]; then
	echo "no_turnin: SKIP — $WHERE has none of the files $TEST checks,"
	echo "  and this layer stands down until there is something for it to check."
	echo "  The exercise's files, norm and compile layers say what is missing."
	echo "  (NO_SKIP=1 turns this skip red.)"
	exit 0
fi
echo "${NOTURNIN_MARK}$WHERE has none of the files $TEST checks."
echo "  Nothing was checked: there was nothing there to check. The subject's"
echo "  \"Files to turn in\" line says which files belong there, and the"
echo "  exercise's files layer, where it has one, names the ones missing."
# One folder per line: a folder named with a blank is one folder. (This file
# runs nothing and sources no library, so the list is read line by line here
# rather than through runner_lib.sh's LISTS OF WORDS.)
printf '%s' "$MISPLACED" | while IFS= read -r _m; do
	echo ""
	echo "  There are files in $_m/, though. This subject has no turn-in"
	echo "  directory, so they go at the root of deliverable/, not in a folder"
	echo "  of their own:"
	echo "    git mv $_m/* $WHERE/"
done
exit 1
