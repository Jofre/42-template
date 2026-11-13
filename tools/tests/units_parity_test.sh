#!/bin/sh
# units_parity_test.sh -- the contract as it is read outside Bazel, held to the
# contract the macros read, package by package.
#
# tools/units.awk is the one reader of a subject() call written as text:
# first_red.sh reads a project's units through it from a log, conventions.sh,
# answer_scan.sh and `42` (tools/fortytwo/workspace.py) from a checkout, and
# none of them has Bazel running. Every package with a contract writes what
# the macros computed from the same call (tools/defs.bzl): :units, a row per
# unit, "NAME KIND REQ FOLDER JUDGE LIB", and :test_units, a row per test,
# "TARGET UNIT", sorted by target, each TAB-separated. For every package it
# is handed, this asks:
#
#   units       units.awk's reading of the BUILD.bazel beside :units is
#               :units, byte for byte;
#   test_units  first_red.sh --unit-of, handed :test_units' targets, files
#               each under the unit :test_units gives it, byte for byte; the
#               targets are sorted and none is listed twice; and where the
#               package's :layers is handed too, they are every test it lists;
#   turnin      first_red.sh --turnin names the FOLDER of each exercise or
#               unit of :units (every row but a function's);
#   written     first_red.sh --written lists the exercises or units of
#               :units, functions aside, in their order, mandatory where REQ
#               says so: the floor `submit --written-only` will not push
#               below;
#   graded      first_red.sh --graded reads memory_graded as the package's
#               subject.json holds it;
#   files       units.awk's rows=files reading holds each exercise's or
#               unit's files, optional and provided (its values) as
#               subject.json does, in order; where it says it read a list in
#               part (a row with no STRING), each string it did read is one
#               the JSON lists.
#   goals       units.awk's rows=goals reading holds the goal of each unit
#               that names one (the rule of a shared Makefile that tells a
#               part written) as subject.json does, in :units' order.
#
# A reading that parts from the macros' would judge the wrong folder, file a
# red under another unit, or let --written-only push without a mandatory
# unit; here it is a red naming the package and the rows.
# A contract units.awk cannot read (it exits 2 naming FILE:LINE) is a red as
# well, never a skip: that is the drift this test is for. The selftest's
# "units parity" section proves each arm can go red, on scratch trees.
#
# Usage:
#   units_parity_test.sh --units-awk PATH --first-red PATH
#                        --package UNITS [--package UNITS]... [--layers LAYERS]...
#
#   --units-awk  tools/units.awk
#   --first-red  tools/first_red.sh, with stub_check.sh beside it
#   --package    a package's :units (units.txt); the package's :test_units
#                (test_units.txt), :subject (subject.json) and BUILD.bazel
#                are read beside it
#   --layers     a macro fixture package's :layers (layers.txt), beside its
#                units.txt: a "name runner ..." line per test and a "name
#                suite ..." line per suite
#
# Exit 0: every package agrees. 1: one does not, each named. 2: the check
# could not run (an option missing, a file not staged).
set -u

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "units_parity_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat cmp comm cut diff grep mktemp rm sed sort

RL_NAME=units_parity_test
case $0 in */*) RL_LIB=${0%/*}/../runner_lib.sh ;; *) RL_LIB=../runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "units_parity_test.sh: tools/runner_lib.sh is not staged (tools/defs_test.bzl's _test() stages it for every test; by hand, run this by its path in the repository)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"

UNITS_AWK=""
FIRST_RED=""
PKGS=""
LAYERS=""
NL='
'
TAB=$(printf '\t')
while [ $# -gt 0 ]; do
	case "$1" in
		--units-awk) rl_need "$1" "$#"; UNITS_AWK=$2; shift 2 ;;
		--first-red) rl_need "$1" "$#"; FIRST_RED=$2; shift 2 ;;
		# An empty one too, for either list: the loops below skip a blank
		# line, and a run handed only that passed having checked nothing.
		--package)
			rl_need "$1" "$#"
			[ -n "$2" ] || { echo "units_parity_test.sh: --package needs a value, not an empty word" >&2; exit 2; }
			PKGS="$PKGS$2$NL"
			shift 2 ;;
		--layers)
			rl_need "$1" "$#"
			[ -n "$2" ] || { echo "units_parity_test.sh: --layers needs a value, not an empty word" >&2; exit 2; }
			LAYERS="$LAYERS$2$NL"
			shift 2 ;;
		*) echo "units_parity_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$UNITS_AWK" ] && [ -n "$FIRST_RED" ] && [ -n "$PKGS" ] || {
	echo "units_parity_test.sh: --units-awk, --first-red and a --package at least are required (see its header)" >&2
	exit 2
}
for _f in "$UNITS_AWK" "$FIRST_RED"; do
	[ -f "$_f" ] || { echo "units_parity_test.sh: no file at $_f" >&2; exit 2; }
done

WORK=$(mktemp -d) || { echo "units_parity_test.sh: mktemp failed" >&2; exit 2; }
rl_traps 'rm -rf "$WORK"'

PASS=0
FAIL=0
ok() { printf '  %s: ok\n' "$1"; PASS=$((PASS + 1)); }
# bad WHAT FILE -- WHAT, then FILE's lines through the one renderer: a row's
# TABs and a line's end are bytes the reader has to see.
bad() {
	printf '  %s: FAIL\n' "$1"
	rl_vis block 30 < "$2" | sed 's/^/      /'
	FAIL=$((FAIL + 1))
}
# say FILE TEXT... -- FILE holds the lines TEXT, for bad.
say() { _sf=$1; shift; printf '%s\n' "$@" > "$_sf"; }

units_match() {  # units_match DIR
	_w="units.awk reads $1's contract as the macros do (:units)"
	LC_ALL=C awk -f "$UNITS_AWK" "$1/BUILD.bazel" > "$WORK/u.got" 2> "$WORK/u.err"
	_rc=$?
	if [ "$_rc" -eq 1 ]; then
		say "$WORK/u.err" "units.awk finds no subject( call in $1/BUILD.bazel, and the macros read one there"
		bad "$_w" "$WORK/u.err"
	elif [ "$_rc" -ne 0 ]; then
		# Exit 2: a line of the contract it cannot read, FILE:LINE, quoted.
		bad "$_w" "$WORK/u.err"
	elif ! grep -q . "$1/units.txt"; then
		say "$WORK/u.err" "the macros list no unit for it: an empty :units checks nothing"
		bad "$_w" "$WORK/u.err"
	elif awk -F'\t' 'NF != 6' "$1/units.txt" | grep -q .; then
		{
			echo "rows of :units that are not NAME KIND REQ FOLDER JUDGE LIB:"
			awk -F'\t' 'NF != 6' "$1/units.txt"
		} > "$WORK/u.err"
		bad "$_w" "$WORK/u.err"
	elif cmp -s "$1/units.txt" "$WORK/u.got"; then
		ok "$_w ($(grep -c . "$1/units.txt") units)"
	else
		{
			echo "'<' is :units, the macros' row; '>' is units.awk's"
			diff "$1/units.txt" "$WORK/u.got"
		} > "$WORK/u.err"
		bad "$_w" "$WORK/u.err"
	fi
}

test_units_match() {  # test_units_match DIR
	_w="first_red --unit-of files $1's tests as the macros do (:test_units)"
	_t=$1/test_units.txt
	cut -f1 "$_t" > "$WORK/t.names"
	if ! grep -q . "$_t"; then
		say "$WORK/t.err" "the macros list no test of it: an empty :test_units checks nothing"
		bad "$_w" "$WORK/t.err"
	elif awk -F'\t' 'NF != 2 || $1 == "" || $2 == ""' "$_t" | grep -q .; then
		{
			echo "rows of :test_units that are not TARGET UNIT:"
			awk -F'\t' 'NF != 2 || $1 == "" || $2 == ""' "$_t"
		} > "$WORK/t.err"
		bad "$_w" "$WORK/t.err"
	elif ! LC_ALL=C sort -c -u < "$WORK/t.names" > "$WORK/t.sort" 2>&1; then
		{
			echo "its targets are not in order, or one is listed twice; sort -c -u says:"
			cat "$WORK/t.sort"
		} > "$WORK/t.err"
		bad "$_w" "$WORK/t.err"
	elif ! sh "$FIRST_RED" --unit-of "$1" < "$WORK/t.names" > "$WORK/t.got" 2> "$WORK/t.err"; then
		bad "$_w" "$WORK/t.err"
	elif cmp -s "$_t" "$WORK/t.got"; then
		ok "$_w ($(grep -c . "$_t") tests)"
	else
		{
			echo "'<' is :test_units, the macros' row; '>' is first_red --unit-of's"
			diff "$_t" "$WORK/t.got"
		} > "$WORK/t.err"
		bad "$_w" "$WORK/t.err"
	fi
}

# Every test a macro fixture package declares, as its :layers lists them,
# is a target of its :test_units: a list built before the package's last
# test was declared is short, and every comparison above then passes over
# what it left out. Only that way round: :layers is a list of sh_tests
# made where its names_file stands, and :test_units may hold more.
layers_match() {  # layers_match LAYERS
	_d=${1%/*}
	_w="every test of $_d is in its :test_units"
	[ -f "$_d/test_units.txt" ] || {
		echo "units_parity_test.sh: $1 is handed, and no test_units.txt beside it (its package's --package)" >&2
		exit 2
	}
	awk '$2 != "suite" { print $1 }' "$1" | LC_ALL=C sort -u > "$WORK/l.want"
	cut -f1 "$_d/test_units.txt" | LC_ALL=C sort -u > "$WORK/l.got"
	LC_ALL=C comm -23 "$WORK/l.want" "$WORK/l.got" > "$WORK/l.miss"
	if ! grep -q . "$WORK/l.want"; then
		say "$WORK/l.err" "its :layers lists no test: this compares nothing"
		bad "$_w" "$WORK/l.err"
	elif ! grep -q . "$WORK/l.miss"; then
		ok "$_w ($(grep -c . "$WORK/l.want") tests)"
	else
		{
			echo "tests its :layers lists that :test_units lacks:"
			cat "$WORK/l.miss"
		} > "$WORK/l.err"
		bad "$_w" "$WORK/l.err"
	fi
}

turnin_match() {  # turnin_match DIR
	_w="first_red reads $1's turn-in folders as the macros do"
	: > "$WORK/x.err"
	awk -F'\t' '$2 != "function" { print $1 "\t" $4 }' "$1/units.txt" > "$WORK/x.rows"
	while IFS=$TAB read -r _x_ex _x_want; do
		_x_got=$(sh "$FIRST_RED" --turnin "$1" "$_x_ex" 2>&1)
		[ "$_x_got" = "$_x_want" ] ||
			printf '%s: first_red reads %s, :units says %s\n' "$_x_ex" "$_x_got" "$_x_want" >> "$WORK/x.err"
	done < "$WORK/x.rows"
	if [ -s "$WORK/x.err" ]; then
		bad "$_w" "$WORK/x.err"
	else
		ok "$_w"
	fi
}

# What --written prints is the floor of `submit --written-only`: each
# exercise or unit of the contract (every row but a function's), in its
# order, as "STATE<TAB>NAME<TAB>PART", NAME exNN or the unit's, PART
# mandatory where :units' REQ says so and optional otherwise (REQ "-": the
# contract names no mandatory part). Its STATE is the deliverable's, which
# this does not judge, and must be one of its two words.
written_match() {  # written_match DIR
	_w="first_red --written reads $1's contract as the macros do"
	if ! sh "$FIRST_RED" --written "$1" > "$WORK/w.out" 2> "$WORK/w.err"; then
		bad "$_w" "$WORK/w.err"
		return
	fi
	awk -F'\t' '$2 != "function" { print $1 "\t" ($3 == "mandatory" ? "mandatory" : "optional") }' \
		"$1/units.txt" > "$WORK/w.want"
	awk -F'\t' '{ print $2 "\t" $3 }' "$WORK/w.out" > "$WORK/w.got"
	if awk -F'\t' 'NF != 3 || ($1 != "written" && $1 != "stub")' "$WORK/w.out" | grep -q .; then
		{
			echo "lines it should not print:"
			awk -F'\t' 'NF != 3 || ($1 != "written" && $1 != "stub")' "$WORK/w.out"
		} > "$WORK/w.err"
		bad "$_w" "$WORK/w.err"
	elif cmp -s "$WORK/w.want" "$WORK/w.got"; then
		ok "$_w"
	else
		{
			echo "'<' is :units' exercise and part; '>' is first_red --written's"
			diff "$WORK/w.want" "$WORK/w.got"
		} > "$WORK/w.err"
		bad "$_w" "$WORK/w.err"
	fi
}

# WHETHER THE CONTRACT DECLARES memory_graded, read the way first_red.sh
# reads it (--graded) -- from the subject() call as it is written -- against
# the contract the macros read, the JSON subject() wrote beside it: a graded
# module's valgrind red filed as rigour hides a KO, and an ungraded one's
# filed as a KO overstates one. The reading took `memory_graded = "` for
# the one declaration, and a dict, or one in parentheses, for none.
graded_match() {  # graded_match DIR
	_w="first_red reads whether $1's contract declares memory_graded"
	if grep -q '"memory_graded":{"' "$1/subject.json"; then
		_g_want=graded
	else
		_g_want="not graded"
	fi
	_g_got=$(sh "$FIRST_RED" --graded "$1" 2>&1)
	if [ "$_g_got" = "$_g_want" ]; then
		ok "$_w ($_g_want)"
	else
		say "$WORK/g.err" "it reads '$_g_got', the contract says '$_g_want'"
		bad "$_w" "$WORK/g.err"
	fi
}

# THE FILE LISTS, read as text, against the ones the macros read. Two
# readers take units.awk's rows=files for the contract's lists: the
# conventions rule that names each function a contract turns in, and
# answer_scan's names a contract gives or declares. The JSON subject()
# wrote holds each exercise's or unit's lists as Starlark evaluated them;
# its strings are taken as written there, escapes and all (units.awk reads
# no string with a backslash as a file name, so such a list is read in
# part).
#
# files_json < subject.json -- "NAME<TAB>LIST<TAB>STRING" for each string of
# an exercise's or unit's files or optional list, or a value of its provided
# dict: NAME is exNN for an exercise, the unit's own name for a unit.
files_json() {
	awk '
		{ j = j $0 }
		END {
			L = length(j)
			d = 0
			for (i = 1; i <= L; i++) {
				c = substr(j, i, 1)
				if (c == "\"") {
					s = ""
					for (i++; i <= L; i++) {
						c = substr(j, i, 1)
						if (c == "\\") { s = s c substr(j, i + 1, 1); i++; continue }
						if (c == "\"") break
						s = s c
					}
					# A key when a : follows it in an object.
					if (ty[d] == "{" && substr(j, i + 1, 1) == ":") { key[d] = s; continue }
					if (d == 4 && (key[1] == "exercises" || key[1] == "units") && \
					    ((ty[4] == "[" && (key[3] == "files" || key[3] == "optional")) || \
					     (ty[4] == "{" && key[3] == "provided")))
						printf "%s%s\t%s\t%s\n", (key[1] == "units" ? "" : "ex"), key[2], key[3], s
					continue
				}
				if (c == "{" || c == "[") { d++; ty[d] = c; key[d] = "" }
				else if (c == "}" || c == "]") d--
			}
		}'
}

files_match() {  # files_match DIR
	_w="units.awk reads $1's file lists as the macros do (rows=files)"
	LC_ALL=C awk -v rows=files -f "$UNITS_AWK" "$1/BUILD.bazel" > "$WORK/f.got" 2> "$WORK/f.err"
	_rc=$?
	if [ "$_rc" -ne 0 ]; then
		[ -s "$WORK/f.err" ] || say "$WORK/f.err" "units.awk exited $_rc with rows=files, and said nothing"
		bad "$_w" "$WORK/f.err"
		return
	fi
	LC_ALL=C files_json < "$1/subject.json" > "$WORK/f.want"
	# Per exercise or unit and list: equal, in order; or, read in part, each
	# string read is one the JSON has.
	LC_ALL=C awk -F'\t' '
		{ k = $1 " " $2; keys[k] = 1 }
		FILENAME == ARGV[1] { w[k] = w[k] " [" $3 "]"; has[k, $3] = 1; next }
		$3 == "" { part[k] = 1; next }
		{ g[k] = g[k] " [" $3 "]"; if (!((k, $3) in has)) out[k] = out[k] " [" $3 "]" }
		END {
			for (k in keys)
				if (k in part) {
					if (out[k] != "")
						printf "%s: read in part, and what it read holds%s, which the macros do not list\n", k, out[k]
				} else if (w[k] != g[k])
					printf "%s: the macros list%s; units.awk reads%s\n", k, (w[k] == "" ? " nothing" : w[k]), (g[k] == "" ? " nothing" : g[k])
		}' "$WORK/f.want" "$WORK/f.got" | LC_ALL=C sort > "$WORK/f.err"
	if [ -s "$WORK/f.err" ]; then
		bad "$_w" "$WORK/f.err"
	else
		ok "$_w ($(grep -c . "$WORK/f.want") strings)"
	fi
}

# THE GOALS, read as text, against the ones the macros read: the rule of a
# shared Makefile that tells a part written (JUDGE goal), which first_red
# and submit take from units.awk's rows=goals. A goal misread is a bonus
# told written by the wrong rule, or a part pushed while its rule is missing.
#
# goals_json < subject.json -- "NAME<TAB>GOAL" for each unit whose goal is
# a string, in the JSON's order; goals_match puts them in :units' order.
goals_json() {
	awk '
		{ j = j $0 }
		END {
			L = length(j)
			d = 0
			for (i = 1; i <= L; i++) {
				c = substr(j, i, 1)
				if (c == "\"") {
					s = ""
					for (i++; i <= L; i++) {
						c = substr(j, i, 1)
						if (c == "\\") { s = s c substr(j, i + 1, 1); i++; continue }
						if (c == "\"") break
						s = s c
					}
					if (ty[d] == "{" && substr(j, i + 1, 1) == ":") { key[d] = s; continue }
					if (d == 3 && key[1] == "units" && key[3] == "goal")
						printf "%s\t%s\n", key[2], s
					continue
				}
				if (c == "{" || c == "[") { d++; ty[d] = c; key[d] = "" }
				else if (c == "}" || c == "]") d--
			}
		}'
}

goals_match() {  # goals_match DIR
	_w="units.awk reads $1's goals as the macros do (rows=goals)"
	LC_ALL=C awk -v rows=goals -f "$UNITS_AWK" "$1/BUILD.bazel" > "$WORK/gl.got" 2> "$WORK/gl.err"
	_rc=$?
	if [ "$_rc" -ne 0 ]; then
		[ -s "$WORK/gl.err" ] || say "$WORK/gl.err" "units.awk exited $_rc with rows=goals, and said nothing"
		bad "$_w" "$WORK/gl.err"
		return
	fi
	LC_ALL=C goals_json < "$1/subject.json" > "$WORK/gl.json"
	LC_ALL=C awk -F'\t' 'FILENAME == ARGV[1] { g[$1] = $2; next } ($1 in g) { print $1 "\t" g[$1] }' \
		"$WORK/gl.json" "$1/units.txt" > "$WORK/gl.want"
	if cmp -s "$WORK/gl.want" "$WORK/gl.got"; then
		ok "$_w ($(grep -c . "$WORK/gl.want") goals)"
	else
		{
			echo "'<' is the macros' goals, in :units' order; '>' is units.awk's"
			diff "$WORK/gl.want" "$WORK/gl.got"
		} > "$WORK/gl.err"
		bad "$_w" "$WORK/gl.err"
	fi
}

while IFS= read -r _u; do
	[ -n "$_u" ] || continue
	_d=${_u%/*}
	for _f in "$_u" "$_d/test_units.txt" "$_d/subject.json" "$_d/BUILD.bazel"; do
		[ -f "$_f" ] || {
			echo "units_parity_test.sh: $_f is not staged (the package's :units, :test_units, :subject and :conventions_srcs)" >&2
			exit 2
		}
	done
	units_match "$_d"
	test_units_match "$_d"
	turnin_match "$_d"
	written_match "$_d"
	graded_match "$_d"
	files_match "$_d"
	goals_match "$_d"
done << PKGS_EOF
$PKGS
PKGS_EOF
_nlayers=0
while IFS= read -r _l; do
	[ -n "$_l" ] || continue
	[ -f "$_l" ] || { echo "units_parity_test.sh: no file at $_l" >&2; exit 2; }
	layers_match "$_l"
	_nlayers=$((_nlayers + 1))
done << LAYERS_EOF
$LAYERS
LAYERS_EOF
# A --layers of nothing but a newline is no empty word either, and is a
# blank line of its list: the packages were checked, so the last guard
# below is met, but no layers listing was, and the run is refused.
if [ -n "$LAYERS" ] && [ "$_nlayers" -eq 0 ]; then
	echo "units_parity_test.sh: --layers was given, and no layers listing was checked" >&2
	exit 2
fi

echo ""
if [ "$FAIL" -ne 0 ]; then
	echo "units_parity: FAIL — $FAIL of $((PASS + FAIL)) check(s)."
	exit 1
fi
# A --package of nothing but a newline is no empty word, and is a blank
# line of the list: the loop checked no package, and the run is refused.
[ "$PASS" -gt 0 ] || { echo "units_parity_test.sh: no package was checked" >&2; exit 2; }
echo "units_parity: OK — $PASS check(s)."
exit 0
