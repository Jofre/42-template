#!/bin/sh
# macro_fixtures_test.sh — no deliverable can break the build graph, proven on
# toy exercises in every broken state, on every run.
#
# The package //tools/tests/macro_fixtures declares invented exercises through
# the same macros every module uses -- one that builds, and one each with a
# syntax error, a main() beside the function, nothing turned in (plus a literal
# path to a header that is not there), a file the subject never asked for, two
# copies named the way a desktop names them, a Makefile program with no
# Makefile, one with the stub Makefile of an exercise not started, and a
# program with a syntax error on a line that quotes a crash banner. See its
# BUILD file.
#
# What this checks, in three parts:
#
#   1. That it BUILDS at all: its data are the programs built from those
#      exercises and the list of the tests their macros emitted, so a package
#      that no longer loads, a literal deliverable path Bazel cannot find, a
#      file name that breaks a label, or a compile that fails the build action
#      is this test FAILED TO BUILD.
#   2. The programs: each broken one is a stand-in of the right KIND that
#      says, in the compiler's words, why nothing was built -- and a runner
#      handed one says so instead of grading it -- while the exercises that
#      build are ordinary programs, unaffected by their broken neighbours.
#   3. What was emitted: every test of the package, with its runner, against
#      layers.expected -- so each layer of an exercise with nothing turned in
#      is a NOT TURNED IN test (gated where its layer is), and no layer of an
#      exercise whose files are there is one. And every program built from a
#      student's files, with the prototype test its harness names, against
#      harnesses.expected -- so a harness whose tag stopped being written is
#      red here, where c_levels()' audit would only have seen no harness. And
#      for a c_function reading, which main its program links: ./levels
#      ex03's two programs are run.
#
# What it cannot check is each fixture test's VERDICT: a test cannot run other
# tests. Those are measured by hand, with the command in the package's BUILD
# file, and listed there; the count of tests that measurement states is held
# to layers.expected here.
#
# Usage:
#   macro_fixtures_test.sh --dir DIR --diff-output PATH
#                          --ex14-files-names FILE
#                          --contract-problems FILE... --contract-expected FILE
#                          --toy PACKAGE LAYERS EXPECTED...
#                          --harnesses FILE --expected-harnesses FILE
#                          --lines FILE WANT...
#                          --shell-tags FILE --redirect-args FILE --argvguard-builds FILE
#                          --knobs FILE --expected-knobs FILE
#
#   --dir              the fixture package's directory in the runfiles
#   --diff-output      tools/diff_output.sh, the runner every output layer uses
#   --ex14-files-names ex14's files layer's name list: the grader's file in a
#                      subfolder, copied into the turn-in
#   --contract-problems  every contract check's message on a broken contract
#                      (the package's :contract_problems), against
#   --contract-expected  contract_problems.expected beside it.
#                      --contract-problems repeats: after the top fixture's,
#                      a toy's :contract_problems, the calls it refuses,
#                      whose cases contract_problems.expected holds too
#   --toy PACKAGE LAYERS EXPECTED  (repeatable) a fixture package whose tests
#                      are listed: its folder from the workspace root, what
#                      its macros emitted (its :layers) and what they must
#                      emit (its layers.expected). tools/tests/BUILD.bazel
#                      gives one for each package of _LAYERED_FIXTURES, DIR's
#                      among them: ./levels, the toy module whose exercises
#                      c_levels() finds and audits; ./graded, the toy project
#                      whose subject() declares memory_graded; the toys
#                      divided into named units (./named_*). A toy library's
#                      layers are also read for each function's own tests
#                      (unit_tests)
#   --harnesses        every program the package builds from a student's
#                      files, and the prototype test its harness names (the
#                      package's :harnesses), against
#   --expected-harnesses  harnesses.expected beside it
#   --lines FILE WANT  (repeatable) a list a macro wrote, which must hold
#                      exactly the lines WANT gives, comma-separated ("-": none)
#                      -- ex04's files layer walking into backup/, the .c lists
#                      the Makefile toys' builds wrote, the files ./levels has
#                      outside every exercise folder, the root toy's files and
#                      its Makefile's -I (./named_prog), who waits for an
#                      output test
#   --shell-tags       where shell_exercise put the toy ex09's tags and
#                      run_tags: one "name tag..." line per test
#   --redirect-args    where shell_exercise put the toy ex23's redirect: one
#                      "name --redirect ... --redirect-lib ..." line per test
#   --argvguard-builds how each guarded-argv program is built: one "name
#                      makefile|missing-makefile|srcs" line per program
#   --knobs            what each knob no project turns gave the targets it
#                      shapes, in ./knobs (its :knobs), against
#   --expected-knobs   knobs.expected beside it
set -u

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "macro_fixtures_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat diff grep head mktemp od rm sed sort tr uniq

RL_NAME=macro_fixtures_test
case $0 in */*) RL_LIB=${0%/*}/../runner_lib.sh ;; *) RL_LIB=../runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "macro_fixtures_test.sh: tools/runner_lib.sh is not staged (tools/defs_test.bzl's _test() stages it for every test; by hand, run this by its path in the repository)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"

# A test's scratch files go under TEST_TMPDIR, which Bazel empties, and not
# in the machine's /tmp, the TMPDIR Bazel sets when the shell that ran it set
# none (tools/runner_lib.sh, "THE SCRATCH FOLDER").
case ${TMPDIR:-/tmp} in /tmp | /tmp/) [ -z "${TEST_TMPDIR:-}" ] || export TMPDIR="$TEST_TMPDIR" ;; esac

DIR=""
DIFF_OUTPUT=""
EX14_NAMES=""
PROBLEMS=""
PROBLEMS_EXPECTED=""
TOYS=""
HARNESSES=""
EXPECTED_HARNESSES=""
LINES=""
SHELL_TAGS=""
REDIRECT_ARGS=""
ARGVGUARD_BUILDS=""
KNOBS=""
EXPECTED_KNOBS=""
NL='
'
while [ $# -gt 0 ]; do
	case "$1" in
		--dir) rl_need "$1" "$#"; DIR="$2"; shift 2 ;;
		--diff-output) rl_need "$1" "$#"; DIFF_OUTPUT="$2"; shift 2 ;;
		--ex14-files-names) rl_need "$1" "$#"; EX14_NAMES="$2"; shift 2 ;;
		--contract-problems)
			rl_need "$1" "$#"
			[ -f "$2" ] || { echo "macro_fixtures_test.sh: no file at $2" >&2; exit 2; }
			PROBLEMS="$PROBLEMS$2$NL"
			shift 2 ;;
		--contract-expected) rl_need "$1" "$#"; PROBLEMS_EXPECTED="$2"; shift 2 ;;
		--toy)
			[ "$#" -ge 4 ] || { echo "macro_fixtures_test.sh: --toy needs PACKAGE, LAYERS and EXPECTED" >&2; exit 2; }
			TOYS="$TOYS$2 $3 $4$NL"
			shift 4 ;;
		--harnesses) rl_need "$1" "$#"; HARNESSES="$2"; shift 2 ;;
		--expected-harnesses) rl_need "$1" "$#"; EXPECTED_HARNESSES="$2"; shift 2 ;;
		--lines)
			[ "$#" -ge 3 ] || { echo "macro_fixtures_test.sh: --lines needs FILE and WANT" >&2; exit 2; }
			[ -f "$2" ] || { echo "macro_fixtures_test.sh: no file at $2" >&2; exit 2; }
			LINES="$LINES$2 $3$NL"
			shift 3 ;;
		--shell-tags) rl_need "$1" "$#"; SHELL_TAGS="$2"; shift 2 ;;
		--redirect-args) rl_need "$1" "$#"; REDIRECT_ARGS="$2"; shift 2 ;;
		--argvguard-builds) rl_need "$1" "$#"; ARGVGUARD_BUILDS="$2"; shift 2 ;;
		--knobs) rl_need "$1" "$#"; KNOBS="$2"; shift 2 ;;
		--expected-knobs) rl_need "$1" "$#"; EXPECTED_KNOBS="$2"; shift 2 ;;
		*) echo "macro_fixtures_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$DIR" ] && [ -n "$DIFF_OUTPUT" ] &&
	[ -n "$EX14_NAMES" ] && [ -n "$PROBLEMS" ] && [ -n "$PROBLEMS_EXPECTED" ] &&
	[ -n "$HARNESSES" ] && [ -n "$TOYS" ] && [ -n "$EXPECTED_HARNESSES" ] &&
	[ -n "$LINES" ] && [ -n "$SHELL_TAGS" ] && [ -n "$REDIRECT_ARGS" ] && [ -n "$ARGVGUARD_BUILDS" ] &&
	[ -n "$KNOBS" ] && [ -n "$EXPECTED_KNOBS" ] || {
	echo "macro_fixtures_test.sh: every option is required (see its header)" >&2
	exit 2
}
for _f in "$EX14_NAMES" "$PROBLEMS_EXPECTED" "$HARNESSES" "$EXPECTED_HARNESSES" \
	"$SHELL_TAGS" "$REDIRECT_ARGS" "$ARGVGUARD_BUILDS" \
	"$KNOBS" "$EXPECTED_KNOBS" "$DIR/BUILD.bazel"; do
	[ -f "$_f" ] || { echo "macro_fixtures_test.sh: no file at $_f" >&2; exit 2; }
done
while IFS=' ' read -r _tp _tl _te; do
	[ -n "$_tp" ] || continue
	for _f in "$_tl" "$_te"; do
		[ -f "$_f" ] || { echo "macro_fixtures_test.sh: no file at $_f" >&2; exit 2; }
	done
done <<TOYS_EOF
$TOYS
TOYS_EOF
[ -f "$DIFF_OUTPUT" ] || { echo "macro_fixtures_test.sh: no runner at $DIFF_OUTPUT" >&2; exit 2; }

# The contract: the mark and the status, from the file that defines them.
_sl="${DIFF_OUTPUT%/*}/standin.sh"
[ -f "$_sl" ] || { echo "macro_fixtures_test.sh: $_sl is not staged" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

PASS=0
FAIL=0
ok() { printf '  %-60s ok\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  %-60s FAIL < %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

# THE LISTINGS THE MACROS WRITE, each against the .expected file beside it:
# the tests a package emitted, the programs built from a student's files,
# the knobs no project turns. One compare and one recipe for all three:
# written three times, the copies drifted, one without a floor (an empty
# listing passed as "0 tests") and two without the recipe's caveat.
#
# listing_match OK_TEXT BAD_LABEL BAD_TEXT FLOOR_ERE FLOOR_MSG EXPECTED EMITTED
# -- ok OK_TEXT where EMITTED holds a line matching FLOOR_ERE and is
# EXPECTED byte for byte (0); else bad BAD_LABEL, with FLOOR_MSG where the
# floor failed (2) or BAD_TEXT where the two differ (1), the diff left at
# $WORK/listing.diff for the caller's legend.
listing_match() {
	if ! grep -q -- "$4" "$7"; then
		bad "$2" "$5"
		return 2
	fi
	if diff "$6" "$7" > "$WORK/listing.diff" 2>&1; then
		ok "$1"
		return 0
	fi
	bad "$2" "$3"
	return 1
}
# regen_recipe TARGET BAZEL_BIN_TXT EXPECTED_PATH -- the commands that
# write a listing's .expected from what was emitted.
regen_recipe() {
	echo "    bazel build //$1 &&"
	echo "      cat bazel-bin/$2 > $3   (cat, not cp: a"
	echo "      copy of bazel-bin's read-only, executable file keeps its mode)"
}

# A real program: an ELF file that runs and prints what the harness prints on
# the stub, 0.
is_program() {  # is_program NAME BIN [OUTPUT]  -- OUTPUT defaults to 0
	[ -f "$2" ] || { bad "$1" "$2 was not built"; return; }
	if [ "$(head -c 4 "$2" | od -An -c | tr -d ' \n')" != '177ELF' ]; then
		bad "$1" "not a program: $(head -n 3 "$2" | rl_vis lines 3 300)"
		return
	fi
	_o=$("$2" 2>&1)
	_want=${3-0}
	[ "$_o" = "$_want" ] && ok "$1" ||
		bad "$1" "it printed '$(printf '%s' "$_o" | rl_vis arg 1 300)', not '$(printf '%s' "$_want" | rl_vis arg)'"
}

# A stand-in that explains itself: the mark, the kind, the reserved status,
# and the words that name what went wrong.
is_standin() {  # is_standin NAME BIN broke|empty WORDS...
	_n=$1; _b=$2; _k=$3; shift 3
	[ -f "$_b" ] || { bad "$_n" "$_b was not built"; return; }
	standin_is "$_b" || { bad "$_n" "a real program was built"; return; }
	[ "$(standin_kind "$_b")" = "$_k" ] || { bad "$_n" "a stand-in of kind $(standin_kind "$_b"), not $_k"; return; }
	sh "$_b" > "$WORK/out" 2>&1
	_rc=$?
	[ "$_rc" -eq "$STANDIN_STATUS" ] || { bad "$_n" "it exited $_rc, not $STANDIN_STATUS"; return; }
	grep -qF -- "$STANDIN_MARK" "$WORK/out" || { bad "$_n" "it never printed the mark"; return; }
	for _w in "$@"; do
		grep -qF -- "$_w" "$WORK/out" || { bad "$_n" "it never said '$_w'"; return; }
	done
	ok "$_n"
}

echo "macro_fixtures: every broken state fails its own programs, and nothing else"

is_program "ex00 builds, and its program runs" "$DIR/ex00_bin"
is_program "ex04's extra file changes nothing it links" "$DIR/ex04_bin"
is_program "ex05's copies named with a blank and a ( change nothing" "$DIR/ex05_bin"
is_standin "ex01's syntax error is a stand-in, in the compiler's words" "$DIR/ex01_bin" broke \
	"does not compile" "deliverable/ex01/toy_twice.c:" "error:"
is_standin "ex02's second main() does not link, and says where" "$DIR/ex02_bin" broke \
	"does not link" "multiple definition of" "deliverable/ex02/toy_twice.o"
is_standin "ex03, with nothing turned in, says so" "$DIR/ex03_bin" empty \
	"none of the files it is built from" "deliverable/ex03"
is_standin "ex06, a Makefile program with no Makefile, says so" "$DIR/ex06_bin" empty \
	"there is no Makefile at" "deliverable/ex06/Makefile"
is_standin "...and so does its sanitizer twin" "$DIR/ex06_bin_asan" empty \
	"there is no Makefile at" "deliverable/ex06/Makefile"
is_standin "...and its allocation-failure twin" "$DIR/ex06_bin_allocfail" empty \
	"there is no Makefile at" "deliverable/ex06/Makefile"
is_standin "ex10's stub Makefile has nothing to build, not broken code" "$DIR/ex10_bin" empty \
	"$STANDIN_EMPTY" "compiles no .c files"
# Its broken line holds the words a compiler that crashed prints, and the
# compiler quotes that line under its error: it is still broken code, and
# still a stand-in, never a build that "crashed" (exit 2, no log).
is_standin "ex11's program with a syntax error is a stand-in" "$DIR/ex11_bin" broke \
	"$STANDIN_BROKE" "deliverable/ex11/toy.c:" "internal compiler error"
is_standin "...and so is its sanitizer twin" "$DIR/ex11_bin_asan" broke \
	"$STANDIN_BROKE" "deliverable/ex11/toy.c:" "internal compiler error"
is_standin "...and its allocation-failure twin" "$DIR/ex11_bin_allocfail" broke \
	"$STANDIN_BROKE" "deliverable/ex11/toy.c:" "internal compiler error"

# The runner every output layer uses, handed a stand-in: red (exit 1, never 2),
# the compiler's words, and no exercise hints -- none of them is about a build.
# A hint with no member case fires on any failure: it would be printed on
# any red that ran the program at all.
printf 'think about the loop bound\n' > "$WORK/clues.tsv"
printf '0\n' > "$WORK/expected.txt"
sh "$DIFF_OUTPUT" --bin "$DIR/ex01_bin" --expected "$WORK/expected.txt" \
	--clues "$WORK/clues.tsv" > "$WORK/diff" 2>&1
_rc=$?
if [ "$_rc" -ne 1 ]; then
	bad "the output layer is red on a stand-in" "exit $_rc"
elif ! grep -qF 'your code did not build' "$WORK/diff" ||
	! grep -qF 'deliverable/ex01/toy_twice.c:' "$WORK/diff"; then
	bad "the output layer is red on a stand-in" "it never said why"
elif grep -qF 'loop bound' "$WORK/diff"; then
	bad "the output layer is red on a stand-in" "it printed the exercise's hints"
else
	ok "the output layer is red on a stand-in, and says why"
fi

# An exercise not started is not broken code: the output layer handed ex10's
# empty stand-in says there was nothing to build, never "your code did not
# build".
: > "$WORK/empty.txt"
sh "$DIFF_OUTPUT" --bin "$DIR/ex10_bin" --expected "$WORK/empty.txt" > "$WORK/diff10" 2>&1
_rc=$?
if [ "$_rc" -ne 1 ]; then
	bad "the output layer is red on an empty stand-in" "exit $_rc"
elif grep -qF 'your code did not build' "$WORK/diff10"; then
	bad "the output layer is red on an empty stand-in" "it blamed the code"
elif ! grep -qF 'nothing to build' "$WORK/diff10"; then
	bad "the output layer is red on an empty stand-in" "it never said there was nothing to build"
else
	ok "the output layer on an empty stand-in: nothing to build"
fi

# THE INCLUDE PATH IS THE GRADER'S. ex12 and ex13 are compiled the way Rush
# 01's grader compiles, `cc *.c` with no -I, and keep their header in
# includes/. ex12 includes it by name, which that compile cannot find -- so
# its program is a stand-in saying so (and so are its compile layers, by
# hand); ex13 names the folder, and builds.
is_standin "ex12's header in includes/, included by name, is not found" "$DIR/ex12_bin" broke \
	"does not compile" "toy12.h" "deliverable/ex12/main.c:"
is_program "ex13's header included as includes/toy13.h builds" "$DIR/ex13_bin" ""
is_program "...and so does its allocation-failure twin, the shim beside it" \
	"$DIR/ex13_bin_allocfail" ""

# C 10'S PROGRAMS, c_program(makefile = "once_written"). ex27's Makefile is a
# stub that compiles nothing, so its program is its folder's sources -- a
# student's program is tested before the Makefile exists -- and ex28's is
# written: its program is what the Makefile compiles, toy28.c with
# `-I includes`, so the header it includes by name is found, and the second
# main() in toy28_unused.c is never linked. Before, both were built from
# every .c with no -I: ex28 did not build at all.
is_program "ex27's stub Makefile: the program is its sources" "$DIR/ex27_bin" ""
is_program "ex28's written Makefile decides, -I and all" "$DIR/ex28_bin" ""

# A function the GRADER links (C 12's ft_create_elem, the contract's
# `linked`): ex15's harness calls toy_base, which only the Rust library its
# contract names defines. Its program is real, and prints the stub's 0 and
# the grader's 21, only where the macros linked that library.
is_program "ex15 links the function its grader brings" "$DIR/ex15_bin" "$(printf '0\n21')"
# ...and a reading of ex15 (c_function's `readings`) is a program of its own,
# built the same way, the grader's function included.
is_program "ex15's reading links it too" "$DIR/ex15_reading_bin" "0 1"

# A reading whose harness writes its value in the table's notation says so
# in its own case ("escaped_values"), and its target is handed
# --escaped-values (" escaped" in layers.expected), as the exercise's own
# output test is. Before, no reading could ask for it: the runner escaped
# the notation's backslashes a second time, so a NUL showed as \\x00 under
# a legend calling \\ one backslash. Run here with the flags its target
# gets: its fixture passes, and a wrong row shows each byte once, under the
# legend's line for a byte outside printable ASCII.
_esc_fix="$DIR/tests/ex15/reading_escaped.txt"
sh "$DIFF_OUTPUT" --bin "$DIR/ex15_escaped_bin" --harness-fixture --expected "$_esc_fix" \
	--labeled --escaped-values > "$WORK/esc_ok" 2>&1
_rc=$?
[ "$_rc" -eq 0 ] && ok "ex15's escaped reading passes on its fixture" ||
	bad "ex15's escaped reading passes on its fixture" "exit $_rc: $(rl_vis lines 5 300 < "$WORK/esc_ok")"
printf 'bytes\t\\x01\\xffX\n' > "$WORK/esc_wrong.txt"
sh "$DIFF_OUTPUT" --bin "$DIR/ex15_escaped_bin" --harness-fixture --expected "$WORK/esc_wrong.txt" \
	--labeled --escaped-values > "$WORK/esc_bad" 2>&1
_rc=$?
if [ "$_rc" -ne 1 ]; then
	bad "...and a wrong row shows its bytes once" "exit $_rc, not 1"
elif ! grep -qF 'x00' "$WORK/esc_bad" || grep -qF '\\x00' "$WORK/esc_bad"; then
	bad "...and a wrong row shows its bytes once" "$(grep -F 'x00' "$WORK/esc_bad" | rl_vis lines 2 300)"
elif ! grep -qF '\xHH any other byte outside' "$WORK/esc_bad" ||
	grep -qF 'one backslash' "$WORK/esc_bad"; then
	bad "...and a wrong row shows its bytes once" "the legend: $(grep -e 'byte outside' -e 'backslash' "$WORK/esc_bad" | rl_vis lines 2 300)"
else
	ok "...and a wrong row shows its bytes once, under the legend for them"
fi

# A c_function's `readings` (./levels ex03): each reading is a program of its
# own, built from the main its case names over the exercise's files. Its
# target name, runner and level are in layers.expected, and none of them says
# WHICH main it links: a loop that built every reading from the exercise's own
# `test` would emit the same targets and go on passing, the open case never
# run. So the two programs run here, each printing the row only its own main
# prints.
is_program "levels ex03's own output test runs test_toy.c" \
	"$DIR/levels/ex03_bin" "$(printf 'zero\t0')"
is_program "...and its reading, ex03_open, runs test_toy_open.c" \
	"$DIR/levels/ex03_open_bin" "$(printf 'negative\t0')"

# The toy libraries and the root toy, declared as named units: each program
# is its unit's own, by the unit's name. A function of a library links the
# library through its Makefile and runs its OWN main, from tests/<function>/,
# which prints the row only it prints. In ./named_lib the Makefile is a stub
# that compiles nothing yet, so the library's sources stand in. In
# ./named_lib_make it is written, and each function's program is built from
# what `make -Bn` says it compiles, -I inc and all: the library's sources
# standing in would not find inc/toy13.h, so a real program there is one
# built from the plan. In ./named_lib_broken a source does not compile, and
# every function's program is a stand-in in the compiler's words, toy_left's
# too, whose own file compiles -- the archive both link holds toy_right.c --
# and none is built from anything else in silence. The root program is real
# only if the build staged the subfolders, took srcs/main.c from `make -Bn`,
# and took `-I includes` from it too: main.c includes a header nothing else
# would find.
is_program "named_lib's toy_len runs its own test_toy_len.c" \
	"$DIR/named_lib/toy_len_bin" "$(printf 'zero\t0')"
is_program "...and toy_dup its own test_toy_dup.c" \
	"$DIR/named_lib/toy_dup_bin" "$(printf 'null\t1')"
is_program "...and toy_cat its own test_toy_cat.c" \
	"$DIR/named_lib/toy_cat_bin" "$(printf 'null\t1')"
is_program "...and toy_cat's reading, open, its own test_toy_cat_open.c" \
	"$DIR/named_lib/toy_cat_open_bin" "$(printf 'from_null\t1')"
is_program "named_lib_make's toy_up is built from its Makefile's plan, -I and all" \
	"$DIR/named_lib_make/toy_up_bin" "$(printf 'up\t0')"
is_program "...and so is toy_down" \
	"$DIR/named_lib_make/toy_down_bin" "$(printf 'down\t0')"
is_standin "named_lib_broken's toy_right does not compile, in the compiler's words" \
	"$DIR/named_lib_broken/toy_right_bin" broke "does not compile" "toy_right.c"
is_standin "...and toy_left, which links the same archive, says the same" \
	"$DIR/named_lib_broken/toy_left_bin" broke "does not compile" "toy_right.c"
is_program "named_prog's program, in srcs/ and includes/, builds, -I and all" \
	"$DIR/named_prog/toy_root_bin" ""

# A root divided into parts: each part's program is its own, built and run.
# Which sources each named_units_files part's library takes is pinned by
# --lines (its :units_srcs): the two parts' stubs print the same, so a
# program built from the other part's files would print it too.
is_program "named_units_files' base runs its own test_toy_tally.c" \
	"$DIR/named_units_files/base_bin" "$(printf 'zero\t0')"
is_program "...and bonus its own test_toy_tally_bonus.c" \
	"$DIR/named_units_files/bonus_bin" "$(printf 'bonus\t0')"
is_program "named_units_programs' sorter is what a bare make builds" \
	"$DIR/named_units_programs/sorter_bin" ""
is_program "...and checker what make bonus builds" \
	"$DIR/named_units_programs/checker_bin" ""
is_program "named_units_same's base links its own library target of toy_fmt" \
	"$DIR/named_units_same/base_bin" "$(printf 'zero\t0')"
is_program "...and bonus its own, from the same files" \
	"$DIR/named_units_same/bonus_bin" "$(printf 'bonus\t0')"

# A Makefile program with a .c its Makefile never names: the program is built
# from what `make -Bn` names, and the extra file changes nothing it links.
is_program "ex19 builds from toy19.c alone, as its Makefile says" "$DIR/ex19_bin" ""

# A file the grader brings, in a subfolder (C 09 ex01's srcs/): a copy in the
# turn-in is only reported if the files layer looks there.
if grep -qx 'srcs/toy.c' "$EX14_NAMES"; then
	ok "ex14's files layer sees a copy of the grader's srcs/ file"
else
	bad "ex14's files layer sees a copy of the grader's srcs/ file" \
		"it lists: $(rl_vis lines 40 300 < "$EX14_NAMES")"
fi

# THE LISTS THE MACROS WROTE for the files layer, each against what its toy's
# state must give: ex04's layer walks the whole turn-in (backup/toy_twice.c,
# by path, is not the toy_twice.c the subject asks for); a Makefile toy's
# build writes the .c files `make -Bn` names -- "unknown" with no Makefile
# (ex06), nothing for a stub (ex10), and toy19.c but never toy19_unused.c
# (ex19); a Makefile is built for that list alone only where no program's
# build writes it (make_bins: ex20, never ex19); a rush's .c that is no
# shared file and no variant is normed by a target of its own (ex21's
# toy_switch.c, and nothing else); and ./levels' deliverable_files lists what
# is in no exercise folder.
while IFS=' ' read -r _lf _lw; do
	[ -n "$_lf" ] || continue
	_want=""
	[ "$_lw" = - ] || _want=$(printf '%s\n' "$_lw" | tr ',' '\n')
	_name=$(printf '%s' "$_lf" | sed 's#^.*macro_fixtures/##')
	if [ "$(cat "$_lf")" = "$_want" ]; then
		ok "$_name holds what its toy's state gives"
	else
		bad "$_name holds what its toy's state gives" \
			"it reads: $(rl_vis lines 40 300 < "$_lf"), not: $(
				{ [ -z "$_want" ] || printf '%s\n' "$_want"; } | rl_vis lines 40)"
	fi
done <<LINES_EOF
$LINES
LINES_EOF

# Every contract check, fed the broken contract it guards against: each case's
# message holds the words contract_problems.expected gives it, and a case
# written to pass says OK. A check that stops firing -- or starts firing on a
# good contract -- is red here, not in a module that happens to trip it. The
# toys' own lists, of the calls each refuses, are read as one with the top
# fixture's, their cases named after the toy.
while IFS= read -r _pf; do
	[ -z "$_pf" ] || cat "$_pf"
done > "$WORK/problems" <<PROBLEMS_EOF
$PROBLEMS
PROBLEMS_EOF
PROBLEMS="$WORK/problems"
while IFS= read -r _line; do
	case "$_line" in "" | "#"*) continue ;; esac
	_case=${_line%%"	"*}
	_want=${_line#*"	"}
	_got=$(awk -v c="$_case" 'index($0, c ": ") == 1 { print substr($0, length(c) + 3); exit }' "$PROBLEMS")
	if [ -z "$_got" ]; then
		bad "contract check: $_case" "no such case in :contract_problems"
	elif [ "$_want" = OK ]; then
		[ "$_got" = OK ] && ok "contract check: $_case passes" || bad "contract check: $_case passes" "$_got"
	else
		case "$_got" in
			*"$_want"*) ok "contract check: $_case" ;;
			*) bad "contract check: $_case" "it says: $_got" ;;
		esac
	fi
done < "$PROBLEMS_EXPECTED"
# ...and every case is listed there, once: by name, since counts that
# agree hid a case left out behind one listed twice. The floor: a side with
# no case compares nothing. The two files are told apart by name, never by
# FNR == NR, which an empty first file makes true of the second as well:
# contract_problems.expected's rows were then read as the cases emitted.
_unlisted=$(awk -F'\t' '
	FILENAME == ARGV[1] { if ((i = index($0, ": ")) > 0) have[substr($0, 1, i - 1)] = 1; next }
	$0 == "" || /^#/ { next }
	{ listed[$1] = 1 }
	END { for (c in have) if (!(c in listed)) print c }' "$PROBLEMS" "$PROBLEMS_EXPECTED" |
	sort | tr '\n' ' ' | sed 's/ $//')
_twice=$(awk -F'\t' '$0 != "" && !/^#/ { print $1 }' "$PROBLEMS_EXPECTED" | sort | uniq -d |
	tr '\n' ' ' | sed 's/ $//')
if ! grep -q -- ': ' "$PROBLEMS"; then
	bad "every contract case is in contract_problems.expected" \
		"its listing is empty: :contract_problems printed no case"
elif ! grep -v '^#' "$PROBLEMS_EXPECTED" | grep -q .; then
	bad "every contract case is in contract_problems.expected" \
		"its listing is empty: contract_problems.expected has no case"
elif [ -z "$_unlisted$_twice" ]; then
	ok "every contract case is in contract_problems.expected"
else
	bad "every contract case is in contract_problems.expected" \
		"not listed: ${_unlisted:-none}; listed twice: ${_twice:-none}"
fi

# WHERE A SHELL EXERCISE'S TAGS LAND. `tags` go on every test that judges the
# turn-in, `run_tags` only on the ones that run it: Shell 01 ex04's output
# test runs outside the sandbox to see the machine's interfaces, and its
# files layer, which runs the generator alone, has no reason to. The norm
# layer takes neither, nor does the lint of a turn-in that is no script (the
# toy's: `script` unset), which reads the generator alone. A test that runs
# the turn-in of an "env" exercise is "external" too, so Bazel never serves
# its result from the cache: what it read of the machine is no input of
# Bazel's, and a cached PASS outlived a change to it (V102).
printf '%s\n' "ex09_files env" "ex09_lint" "ex09_norm" "ex09_output env external no-sandbox" > "$WORK/shell_tags.want"
if diff "$WORK/shell_tags.want" "$SHELL_TAGS" > "$WORK/shell_tags.diff" 2>&1; then
	ok "shell_exercise puts tags and run_tags where each belongs"
else
	bad "shell_exercise puts tags and run_tags where each belongs" "$(cat "$WORK/shell_tags.diff")"
fi

# WHERE A SHELL EXERCISE'S REDIRECT LANDS. Every test that runs the turn-in
# through a check script -- the output test and each reading -- reads the
# fixture in place of the path, through the preload library; a test that
# runs no check (files, norm, lint, posix) is handed neither. The redirect's
# effect on a run is the selftest's (shell_test: --redirect).
_rd='/etc/toy.conf=$(location tests/ex23/toy.conf) --redirect-lib $(location //tools:path_redirect.so)'
printf '%s\n' "ex23_files" "ex23_lint" "ex23_norm" "ex23_output --redirect $_rd" \
	"ex23_posix" "ex23_regular --redirect $_rd" > "$WORK/redirect_args.want"
if diff "$WORK/redirect_args.want" "$REDIRECT_ARGS" > "$WORK/redirect_args.diff" 2>&1; then
	ok "shell_exercise hands its redirect to every test that runs a check, and no other"
else
	bad "shell_exercise hands its redirect to every test that runs a check, and no other" \
		"$(cat "$WORK/redirect_args.diff")"
fi

# A GUARDED-ARGV PROGRAM IS BUILT AS ITS GRADED ONE IS. c_argv_table's
# exNN_argv_asan replays the table with argv in blocks of exactly their
# size, linking the program's own sources with main wrapped: from c_program's
# source list, or -- the toy ex24, a Makefile program -- through the same
# Makefile, where it used to be refused while loading. And the toy ex29,
# makefile = "once_written" with a stub Makefile: its graded program is the
# folder's sources, and the guarded one took the Makefile alone, an empty
# stand-in beside a real program (V35). It takes the sources too.
printf '%s\n' "ex24_argvguard_bin_asan makefile" "ex29_argvguard_bin_asan makefile+srcs" \
	> "$WORK/argvguard.want"
if diff "$WORK/argvguard.want" "$ARGVGUARD_BUILDS" > "$WORK/argvguard.diff" 2>&1; then
	ok "a Makefile program's guarded-argv build goes through its Makefile"
else
	bad "a Makefile program's guarded-argv build goes through its Makefile" "$(cat "$WORK/argvguard.diff")"
fi
is_program "ex29's stub Makefile: the guarded program is its sources" "$DIR/ex29_argvguard_bin_asan" ""

# What the macros emitted, against what they must, for every package --toy
# names. The floor: a listing with no line in it compares nothing.
layers_match() {  # layers_match PACKAGE EXPECTED EMITTED
	listing_match "every layer of $1 emitted as expected ($(grep -c . "$3") tests)" \
		"the tests the macros emitted in $1" "they differ from its layers.expected" \
		. "its listing is empty" "$2" "$3"
	[ "$?" -eq 1 ] || return
	echo ""
	echo "  '<' is in $1/layers.expected and was not emitted;"
	echo "  '>' was emitted and is not in it. A test that is 'no_turnin.sh' reads"
	echo "  NOT TURNED IN; ' gated' means it SKIPs unless NO_SKIP=1; ' staged' and"
	echo "  ' make-includes' say what reaches a compile layer's include path (see"
	echo "  the :layers target in tools/tests/macro_fixtures/BUILD.bazel)."
	sed 's/^/    /' "$WORK/listing.diff"
	echo ""
	echo "  If a macro changed on purpose (a new layer, a layer renamed), check"
	echo "  that every new line is what that exercise's state should give, then:"
	regen_recipe "$1:layers" "$1/layers.txt" "$1/layers.expected"
}
while IFS=' ' read -r _tp _tl _te; do
	[ -n "$_tp" ] || continue
	layers_match "$_tp" "$_te" "$_tl"
done <<TOYS_EOF
$TOYS
TOYS_EOF

# EACH FUNCTION OF A LIBRARY HAS EXACTLY ITS OWN TESTS: the tests carrying
# unit=<function> in a toy library (./named_lib, ./named_lib_make,
# ./named_lib_broken), read from the tags the macros gave them, against the
# list each function's calls must emit -- written here, from the calls in
# the toy's BUILD file, not copied from its layers.expected, which is
# regenerated from what was emitted. A layer a function's call dropped, a
# test of one function tagged as another's, or one of the whole library's
# tagged as a function's, is red here by name.
toy_field() {  # toy_field PACKAGE N -- field N of the --toy row naming PACKAGE (2 :layers, 3 .expected)
	printf '%s\n' "$TOYS" | awk -v want="$1" -v n="$2" '$1 == want { print $n; exit }'
}
toy_layers() {  # toy_layers TOY -- the :layers file --toy gave for ./TOY
	toy_field "tools/tests/macro_fixtures/$1" 2
}
unit_tests() {  # unit_tests LAYERS UNIT -- that unit's tests in one toy, one line, sorted
	awk -v want="unit=$2" '$2 == "suite" { next } { for (i = 3; i <= NF; i++) if ($i == want) { print $1; next } }' \
		"$1" | sort | tr '\n' ' ' | sed 's/ $//'
}
while IFS='|' read -r _toy _u _want; do
	[ -n "$_toy" ] || continue
	_tl=$(toy_layers "$_toy")
	if [ -z "$_tl" ]; then
		bad "the tests of library function $_u are its own, all of them" "no --toy names ./$_toy"
		continue
	fi
	_got=$(unit_tests "$_tl" "$_u")
	if [ "$_got" = "$_want" ]; then
		ok "the tests of library function $_u ($_toy) are its own, all of them"
	else
		bad "the tests of library function $_u ($_toy) are its own, all of them" "they are: $_got"
	fi
done <<'UNITS_EOF'
named_lib|toy_cat|toy_cat_allocfail toy_cat_allocfail_leaks toy_cat_diff toy_cat_diff_asan toy_cat_ilp32 toy_cat_open_output toy_cat_output toy_cat_perf toy_cat_readings toy_cat_readings_diff_asan toy_cat_valgrind
named_lib|toy_dup|toy_dup_diff toy_dup_diff_asan toy_dup_ilp32 toy_dup_output toy_dup_readings toy_dup_valgrind
named_lib|toy_len|toy_len_asan toy_len_cycles toy_len_diff toy_len_diff_asan toy_len_ilp32 toy_len_memcheck toy_len_output toy_len_perf toy_len_probe_memcheck
named_lib_make|toy_down|toy_down_ilp32 toy_down_memcheck toy_down_output
named_lib_make|toy_up|toy_up_ilp32 toy_up_memcheck toy_up_method toy_up_output
named_lib_broken|toy_left|toy_left_ilp32 toy_left_memcheck toy_left_output
named_lib_broken|toy_right|toy_right_ilp32 toy_right_memcheck toy_right_output
UNITS_EOF
# ...and no test of the three is tagged as a unit that is neither a library
# nor a function the lists above name.
_uall=$(for _toy in named_lib named_lib_make named_lib_broken; do
	_tl=$(toy_layers "$_toy")
	[ -z "$_tl" ] || grep -o ' unit=[^ ]*' "$_tl"
done | sed 's/^ unit=//' | grep -vxE 'libtoy|libtoy13|libtoy14' | sort -u | tr '\n' ' ' | sed 's/ $//')
[ "$_uall" = "toy_cat toy_down toy_dup toy_left toy_len toy_right toy_up" ] &&
	ok "no test is tagged as a function no list above names" ||
	bad "no test is tagged as a function no list above names" "the tags name: $_uall"

# The hand measurement in the package's BUILD file ("N tests, R red; ...")
# counts the tests a run of all of them executes, which is the lines of
# layers.expected. Its verdicts cannot be checked here (a test cannot run
# other tests), but its count can: the w4-costs merge added six tests,
# updated the lines of the three exercises that gained them and left the
# count at 173, so a reader comparing a hand run with it saw six tests
# appear from nowhere. A count that changes with layers.expected is
# re-measured with it.
_said=$(sed -n 's/^# \([0-9][0-9]*\) tests, .*/\1/p' "$DIR/BUILD.bazel" | head -n 1)
_dl=$(toy_field "$DIR" 3)
_have=$([ -z "$_dl" ] || grep -c . "$_dl")
if [ -z "$_dl" ]; then
	bad "the BUILD file's hand-measured count" "no --toy names $DIR, whose layers.expected it is held to"
elif [ -z "$_said" ]; then
	bad "the BUILD file's hand-measured count" \
		"no '# N tests, R red' line in $DIR/BUILD.bazel to hold to layers.expected"
elif [ "$_said" -eq "$_have" ]; then
	ok "the BUILD file's hand-measured count is layers.expected's ($_have)"
else
	bad "the BUILD file's hand-measured count" \
		"it says $_said tests, and layers.expected lists $_have: re-measure the reds with the command above it"
fi

# Every program built from a student's files, and the prototype test its
# harness names. A harness with no prototype_test= tag reads UNTAGGED, and one
# missing from the list was not built at all; either differs from the file.
# The floor: a listing with no harness in it lists nothing worth comparing.
listing_match "every harness names its prototype test ($(grep -c ' prototype_test=' "$HARNESSES") harnesses)" \
	"the programs built in tools/tests/macro_fixtures" "they differ from its harnesses.expected" \
	' prototype_test=' "none carries a prototype_test= tag" "$EXPECTED_HARNESSES" "$HARNESSES"
if [ "$?" -eq 1 ]; then
	echo ""
	echo "  '<' is in harnesses.expected and was not built so; '>' was built and is"
	echo "  not in it. Each line is a student_binary and the prototype test its"
	echo "  harness names (tools/defs_contract.bzl's _student_bin), UNTAGGED where it names"
	echo "  none, or 'own program' where it links no harness."
	sed 's/^/    /' "$WORK/listing.diff"
	echo ""
	echo "  If a macro changed on purpose, check every new line, then:"
	regen_recipe tools/tests/macro_fixtures:harnesses tools/tests/macro_fixtures/harnesses.txt \
		tools/tests/macro_fixtures/harnesses.expected
fi

# EVERY KNOB NO PROJECT TURNS (./knobs): a macro's parameter or a case's key
# that no module passes, set on a toy, and what the targets it shapes were
# given, against knobs.expected. A knob nothing calls is a branch nothing
# ran; this is where one that stops doing what its docstring says goes red.
# The floor: a listing with no line in it compares nothing.
listing_match "every knob no project turns does what it says ($(grep -c . "$KNOBS") probes)" \
	"the knobs of tools/tests/macro_fixtures/knobs" "they differ from its knobs.expected" \
	. "its listing is empty" "$EXPECTED_KNOBS" "$KNOBS"
if [ "$?" -eq 1 ]; then
	echo ""
	echo "  '<' is in knobs.expected and was not emitted so; '>' was emitted and is"
	echo "  not in it. Each line is a knob, a target it shapes, what was asked of"
	echo "  that target and what it holds (see :knobs in the package's BUILD file)."
	sed 's/^/    /' "$WORK/listing.diff"
	echo ""
	echo "  If a macro changed on purpose, check every new line against the knob's"
	echo "  docstring, then:"
	regen_recipe tools/tests/macro_fixtures/knobs:knobs tools/tests/macro_fixtures/knobs/knobs.txt \
		tools/tests/macro_fixtures/knobs/knobs.expected
fi
# ...and one knob only a build shows: student_lib's hdrs and includes. ex06's
# source includes a header that sits in inc/, which only the unit's own
# include directory reaches, so its program is real only if both did.
is_program "a unit's hdrs and includes reach the programs that link it" "$DIR/knobs/ex06_diffbin"

echo ""
if [ "$FAIL" -ne 0 ]; then
	echo "macro_fixtures: FAIL — $FAIL of $((PASS + FAIL)) check(s)."
	exit 1
fi
echo "macro_fixtures: OK — $PASS check(s)."
exit 0
