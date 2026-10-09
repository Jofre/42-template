#!/bin/sh
# oracle_fixtures.sh — hold a project's named fixtures to the reference that
# wrote them.
#
# WHY IT EXISTS. A named case reads a map and an expected output from files
# under tests/exNN/, and those files were taken from //oracle once -- "the
# fixture and its expected output are generated from //oracle's first record,
# so the two cannot drift", BSQ's BUILD file said, and nothing held it to that:
# a reference that changed, or a fixture edited by hand, would drift in
# silence, and a correct program would go red on a file nobody could trace
# back to a rule. So the reference writes the files, and this test fails when
# one of them differs from what it writes.
#
# THE RECORDS. `oracle <fn> 0 0` prints one line per file:
#
#     <path><TAB><escaped bytes>
#
# the path relative to the fixtures' directory, the bytes escaped as
# oracle/src/common.rs's esc_posix does (\\, \n, \t, and \0NNN in octal for
# every other byte outside printable ASCII), which `printf %b` decodes in any
# POSIX shell. A path holds only letters, digits, '_', '-', '.' and '/', with
# no empty or ".." segment: a record naming anything else is refused (exit 2),
# never written.
#
# WHAT THE REFERENCE OWNS (--owns GLOB, at least one). The directory holds
# clues.tsv and the harness's own sources too, so a file the records do not
# name is not necessarily this test's business -- but one the project says the
# reference writes is: BSQ's BUILD file says every map and expected output its
# cases read is written by `oracle bsq_fixtures`, and a hand-typed map added
# for the next case, with its hand-typed output, passed here in silence,
# because only the files the reference names were compared. So each --owns
# pattern (relative to the directory, as the shell globs it: '*.txt' is the
# directory's own .txt files, 'fixtures/*.map' those under fixtures/) names
# files the reference writes, and a file it matches that no record names
# fails, UNOWNED. A pattern that matches no file at all is refused (exit 2):
# a typo there would own nothing and check nothing. Under `bazel test` the
# directory holds what the test's data lists, so the data glob and the
# --owns patterns say the same thing. The other half -- a file a named case
# reads that NO pattern matches, which this runner never sees -- is
# c_levels()' audit's: it reads --in-dir-of and --owns from this test's
# arguments, so pass each as its own argument, the directory as
# "$(location tests/exNN/<a file>)" (tools/defs.bzl, _oracle_owner).
#
# Usage:
#   oracle_fixtures.sh --oracle PATH --fn NAME --in-dir-of FILE --owns GLOB...
#                      [--write]
#
#   --oracle PATH     the Rust reference (//oracle:oracle)
#   --fn NAME         its arm that prints the records (bsq_fixtures)
#   --in-dir-of FILE  a file in the fixtures' directory, as $(location ...)
#                     gives it: its directory is where the paths start. A
#                     file rather than a directory because a Bazel label names
#                     files, and $(location) of one is the same path under
#                     `bazel test`, under `bazel run`, and in the workspace.
#   --owns GLOB       repeatable: files the reference writes, which a record
#                     must name (see WHAT THE REFERENCE OWNS). Letters, digits,
#                     '_', '-', '.', '/', '*' and '?' only.
#   --write           rewrite the files instead of comparing them. Under
#                     `bazel run` (BUILD_WORKSPACE_DIRECTORY set) the ones in
#                     the workspace, so
#                         bazel run //<project>:exNN_oracle_fixtures -- --write
#                     is how a change to the reference reaches the fixtures.
#
# Exit status: 0 every file matches (or was written), 1 a file differs, is
# missing or is UNOWNED, 2 the harness broke (no reference, no records, a
# refused path, no --owns or one that matches nothing).
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "oracle_fixtures.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require cmp cp dirname grep mkdir mktemp rm sed tr

# The shared runner helpers -- exiting signal traps, and the one byte renderer
# every table and excerpt uses -- written once in tools/runner_lib.sh.
RL_NAME=oracle_fixtures
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "oracle_fixtures.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"

# conventions: runs no student code -- it compares the harness's fixture files with what the reference writes
# conventions: harness tool ORACLE -- the Rust reference (//oracle), which writes the records

ORACLE=""
FN=""
ANCHOR=""
WRITE=0
OWNS=""

need() { [ "$2" -ge 2 ] || { echo "oracle_fixtures.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--in-dir-of) need "$1" "$#"; ANCHOR="$2"; shift 2 ;;
		--owns)
			need "$1" "$#"
			case "$2" in
				"" | /* | *//* | */ | *[!A-Za-z0-9_./*?-]* | .. | ../* | */.. | */../*)
					echo "oracle_fixtures.sh: --owns '$2': a pattern is relative, with no empty or" >&2
					echo "  '..' part, and holds letters, digits, '_', '-', '.', '/', '*' and '?'." >&2
					exit 2 ;;
			esac
			OWNS="$OWNS$2
"; shift 2 ;;
		--write) WRITE=1; shift ;;
		*) echo "oracle_fixtures.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$ORACLE" ] && [ -n "$FN" ] && [ -n "$ANCHOR" ] || {
	echo "oracle_fixtures.sh: need --oracle, --fn and --in-dir-of" >&2
	exit 2
}
[ -n "$OWNS" ] || {
	echo "oracle_fixtures.sh: need at least one --owns: the files the reference writes." >&2
	echo "  Without it a hand-typed fixture beside them passes unchecked (see" >&2
	echo "  WHAT THE REFERENCE OWNS in this file's header)." >&2
	exit 2
}
[ -x "$ORACLE" ] || { echo "oracle_fixtures.sh: the reference '$ORACLE' is not executable" >&2; exit 2; }

DIR=$(dirname "$ANCHOR")
if [ "$WRITE" -eq 1 ] && [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
	case "$DIR" in
		/*) ;;
		*) DIR="$BUILD_WORKSPACE_DIRECTORY/$DIR" ;;
	esac
fi
[ -d "$DIR" ] || { echo "oracle_fixtures.sh: '$DIR' is not a directory" >&2; exit 2; }

WORK=$(mktemp -d) || { echo "oracle_fixtures.sh: mktemp failed" >&2; exit 2; }
rl_traps 'rm -rf "$WORK"'

if ! "$ORACLE" "$FN" 0 0 > "$WORK/records" 2> "$WORK/err"; then
	echo "oracle_fixtures.sh: the reference could not print '$FN':" >&2
	sed 's/^/    /' "$WORK/err" >&2
	exit 2
fi
[ -s "$WORK/records" ] || { echo "oracle_fixtures.sh: '$FN' printed no record" >&2; exit 2; }

TAB=$(printf '\t')
N=0
BAD=0
while IFS= read -r line; do
	[ -n "$line" ] || continue
	path=${line%%"$TAB"*}
	esc=${line#*"$TAB"}
	case "$path" in
		"" | /* | *//* | */ | *[!A-Za-z0-9_./-]* | .. | ../* | */.. | */../*)
			echo "oracle_fixtures.sh: refusing the record for '$path': a path is letters," >&2
			echo "  digits, '_', '-', '.' and '/', relative, with no empty or '..' part." >&2
			exit 2 ;;
	esac
	[ "$path" != "$line" ] || { echo "oracle_fixtures.sh: a record has no TAB: '$line'" >&2; exit 2; }
	N=$((N + 1))
	printf '%s\n' "$path" >> "$WORK/named"
	printf '%b' "$esc" > "$WORK/want"
	if [ "$WRITE" -eq 1 ]; then
		mkdir -p "$(dirname "$DIR/$path")" && cp "$WORK/want" "$DIR/$path" || {
			echo "oracle_fixtures.sh: cannot write $DIR/$path" >&2
			exit 2
		}
		echo "  wrote $path"
		continue
	fi
	if [ ! -f "$DIR/$path" ]; then
		BAD=$((BAD + 1))
		echo "  MISSING  $path"
		continue
	fi
	if cmp -s "$WORK/want" "$DIR/$path"; then
		echo "  ok       $path"
		continue
	fi
	BAD=$((BAD + 1))
	echo "  DIFFERS  $path"
	# Where they part, "expected" being what the reference writes and "got"
	# the file: the one window every runner shows (runner_lib.sh).
	rl_diff_window "$WORK/want" "$DIR/$path" "           "
done < "$WORK/records"

[ "$N" -gt 0 ] || { echo "oracle_fixtures.sh: '$FN' printed no usable record" >&2; exit 2; }

# What the reference owns and did not write: every file an --owns pattern
# matches must be one a record names. Globbed from inside the directory, one
# pattern at a time, so a pattern that matches nothing is seen as one.
UNOWNED=0
OWNED_LIST=$(printf '%s' "$OWNS" | tr '\n' ' ')
while IFS= read -r _g; do
	[ -n "$_g" ] || continue
	# $_g unquoted on purpose: it is the pattern, and the shell globs it.
	(cd "$DIR" && for _f in $_g; do [ -f "$_f" ] && printf '%s\n' "$_f"; done) > "$WORK/hits"
	if [ ! -s "$WORK/hits" ]; then
		# No file on disk: still a pattern that owns something when a record
		# falls under it (that file is MISSING, reported above).
		_named=0
		while IFS= read -r _p; do
			# shellcheck disable=SC2254 # $_g is the pattern, unquoted on purpose.
			case "$_p" in $_g) _named=1; break ;; esac
		done < "$WORK/named"
		if [ "$_named" -eq 0 ]; then
			echo "oracle_fixtures.sh: --owns '$_g' matches no file in $DIR and no record," >&2
			echo "  so it owns nothing and checks nothing. Fix the pattern, or the test's data." >&2
			exit 2
		fi
	fi
	while IFS= read -r _f; do
		grep -qxF -- "$_f" "$WORK/named" && continue
		UNOWNED=$((UNOWNED + 1))
		echo "  UNOWNED  $_f"
	done < "$WORK/hits"
done << OWNS_END
$OWNS
OWNS_END

if [ "$WRITE" -eq 1 ]; then
	echo "oracle_fixtures: wrote $N file(s) under $DIR from '$FN'"
	if [ "$UNOWNED" -gt 0 ]; then
		echo ""
		echo "oracle_fixtures: FAIL — $UNOWNED file(s) above match --owns and '$FN' writes"
		echo "  none of them. Delete each, or have the reference write it."
		exit 1
	fi
	exit 0
fi
if [ "$BAD" -eq 0 ] && [ "$UNOWNED" -eq 0 ]; then
	echo "oracle_fixtures: OK — all $N file(s) are what '$FN' writes, and it writes"
	echo "  every file matching $OWNED_LIST"
	exit 0
fi
echo ""
if [ "$BAD" -gt 0 ]; then
	echo "oracle_fixtures: FAIL — $BAD of $N file(s) are not what '$FN' writes."
	echo "  These are the harness's own fixtures, never a student's: either the"
	echo "  reference changed and the files were not rewritten, or a file was"
	echo "  edited by hand. Rewrite them from the reference with"
	echo "      bazel run //<this project>:<this test> -- --write"
	echo "  and read the diff before committing it."
fi
if [ "$UNOWNED" -gt 0 ]; then
	echo "oracle_fixtures: FAIL — $UNOWNED file(s) match $OWNED_LIST, which this project"
	echo "  says the reference writes, and '$FN' writes none of them. A fixture or"
	echo "  expected output typed by hand drifts from the reference in silence:"
	echo "  add it to the reference's fixture arm (oracle/src/), then --write."
fi
exit 1
