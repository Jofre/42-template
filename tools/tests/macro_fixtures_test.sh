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
#   macro_fixtures_test.sh --dir DIR --diff-output PATH --layers FILE --expected-layers FILE
#                          --root-dir DIR --root-layers FILE --root-expected-layers FILE
#                          --root-files-names FILE --root-includes FILE
#                          --ex14-files-names FILE
#                          --contract-problems FILE --contract-expected FILE
#                          --levels-layers FILE --levels-expected-layers FILE
#                          --harnesses FILE --expected-harnesses FILE
#                          --first-red PATH --turnin-dirs FILE --root-turnin-dirs FILE
#                          --shell-tags FILE --redirect-args FILE --argvguard-builds FILE
#
#   --dir              the fixture package's directory in the runfiles
#   --diff-output      tools/diff_output.sh, the runner every output layer uses
#   --layers           what the macros emitted (the package's :layers)
#   --expected-layers  what they must emit (its layers.expected)
#   --root-*           the same for ./root, the toy turned in at the root of
#                      deliverable/, plus its files layer's name list and the
#                      include directories its Makefile passes
#   --ex14-files-names ex14's files layer's name list: the grader's file in a
#                      subfolder, copied into the turn-in
#   --contract-problems  every contract check's message on a broken contract
#                      (the package's :contract_problems), against
#   --contract-expected  contract_problems.expected beside it
#   --levels-*         the same as --layers for ./levels, the toy module whose
#                      exercises c_levels() finds and audits: its tests and its
#                      suites, the stray folders' files tests among them
#   --harnesses        every program the package builds from a student's
#                      files, and the prototype test its harness names (the
#                      package's :harnesses), against
#   --expected-harnesses  harnesses.expected beside it
#   --lines FILE WANT  (repeatable) a list a macro wrote, which must hold
#                      exactly the lines WANT gives, comma-separated ("-": none)
#                      -- ex04's files layer walking into backup/, the .c lists
#                      the Makefile toys' builds wrote, the files ./levels has
#                      outside every exercise folder
#   --first-red        tools/first_red.sh, whose reading of each exercise's
#                      turn-in folder from the subject() as written is held to
#   --turnin-dirs      the macros' own turnin_dir(), one "exNN FOLDER" line per
#   --root-turnin-dirs exercise (the package's :turnin_dirs, and ./root's)
#   --module-turnin-dirs  the same lines c_levels() emits for a module (its
#                      :turnin_dirs), repeatable: one per module, with the
#                      module's BUILD.bazel beside it, so first_red is held to
#                      every project's contract and not only the toy ones'
#   --shell-tags       where shell_exercise put the toy ex09's tags and
#                      run_tags: one "name tag..." line per test
#   --redirect-args    where shell_exercise put the toy ex23's redirect: one
#                      "name --redirect ... --redirect-lib ..." line per test
#   --argvguard-builds how each guarded-argv program is built: one "name
#                      makefile|missing-makefile|srcs" line per program
set -u

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "macro_fixtures_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require cat diff grep head mktemp od rm sed tr

DIR=""
DIFF_OUTPUT=""
LAYERS=""
EXPECTED_LAYERS=""
ROOT_DIR=""
ROOT_LAYERS=""
ROOT_EXPECTED=""
ROOT_NAMES=""
ROOT_INCLUDES=""
EX14_NAMES=""
PROBLEMS=""
PROBLEMS_EXPECTED=""
LEVELS_LAYERS=""
LEVELS_EXPECTED=""
HARNESSES=""
EXPECTED_HARNESSES=""
LINES=""
FIRST_RED=""
TURNIN_DIRS=""
ROOT_TURNIN_DIRS=""
SHELL_TAGS=""
REDIRECT_ARGS=""
ARGVGUARD_BUILDS=""
MODULE_TURNIN=""
NL='
'
need() { [ "$2" -ge 2 ] || { echo "macro_fixtures_test.sh: $1 needs a value" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
	case "$1" in
		--dir) need "$1" "$#"; DIR="$2"; shift 2 ;;
		--diff-output) need "$1" "$#"; DIFF_OUTPUT="$2"; shift 2 ;;
		--layers) need "$1" "$#"; LAYERS="$2"; shift 2 ;;
		--expected-layers) need "$1" "$#"; EXPECTED_LAYERS="$2"; shift 2 ;;
		--root-dir) need "$1" "$#"; ROOT_DIR="$2"; shift 2 ;;
		--root-layers) need "$1" "$#"; ROOT_LAYERS="$2"; shift 2 ;;
		--root-expected-layers) need "$1" "$#"; ROOT_EXPECTED="$2"; shift 2 ;;
		--root-files-names) need "$1" "$#"; ROOT_NAMES="$2"; shift 2 ;;
		--root-includes) need "$1" "$#"; ROOT_INCLUDES="$2"; shift 2 ;;
		--ex14-files-names) need "$1" "$#"; EX14_NAMES="$2"; shift 2 ;;
		--contract-problems) need "$1" "$#"; PROBLEMS="$2"; shift 2 ;;
		--contract-expected) need "$1" "$#"; PROBLEMS_EXPECTED="$2"; shift 2 ;;
		--levels-layers) need "$1" "$#"; LEVELS_LAYERS="$2"; shift 2 ;;
		--levels-expected-layers) need "$1" "$#"; LEVELS_EXPECTED="$2"; shift 2 ;;
		--harnesses) need "$1" "$#"; HARNESSES="$2"; shift 2 ;;
		--expected-harnesses) need "$1" "$#"; EXPECTED_HARNESSES="$2"; shift 2 ;;
		--lines)
			[ "$#" -ge 3 ] || { echo "macro_fixtures_test.sh: --lines needs FILE and WANT" >&2; exit 2; }
			[ -f "$2" ] || { echo "macro_fixtures_test.sh: no file at $2" >&2; exit 2; }
			LINES="$LINES$2 $3$NL"
			shift 3 ;;
		--first-red) need "$1" "$#"; FIRST_RED="$2"; shift 2 ;;
		--turnin-dirs) need "$1" "$#"; TURNIN_DIRS="$2"; shift 2 ;;
		--root-turnin-dirs) need "$1" "$#"; ROOT_TURNIN_DIRS="$2"; shift 2 ;;
		--module-turnin-dirs) need "$1" "$#"; MODULE_TURNIN="$MODULE_TURNIN$2$NL"; shift 2 ;;
		--shell-tags) need "$1" "$#"; SHELL_TAGS="$2"; shift 2 ;;
		--redirect-args) need "$1" "$#"; REDIRECT_ARGS="$2"; shift 2 ;;
		--argvguard-builds) need "$1" "$#"; ARGVGUARD_BUILDS="$2"; shift 2 ;;
		*) echo "macro_fixtures_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$DIR" ] && [ -n "$DIFF_OUTPUT" ] && [ -n "$LAYERS" ] && [ -n "$EXPECTED_LAYERS" ] &&
	[ -n "$ROOT_DIR" ] && [ -n "$ROOT_LAYERS" ] && [ -n "$ROOT_EXPECTED" ] && [ -n "$ROOT_NAMES" ] &&
	[ -n "$ROOT_INCLUDES" ] && [ -n "$EX14_NAMES" ] && [ -n "$PROBLEMS" ] && [ -n "$PROBLEMS_EXPECTED" ] &&
	[ -n "$LEVELS_LAYERS" ] && [ -n "$LEVELS_EXPECTED" ] && [ -n "$HARNESSES" ] &&
	[ -n "$EXPECTED_HARNESSES" ] && [ -n "$FIRST_RED" ] &&
	[ -n "$TURNIN_DIRS" ] && [ -n "$ROOT_TURNIN_DIRS" ] && [ -n "$SHELL_TAGS" ] && [ -n "$REDIRECT_ARGS" ] && [ -n "$ARGVGUARD_BUILDS" ] || {
	echo "macro_fixtures_test.sh: every option is required (see its header)" >&2
	exit 2
}
for _f in "$LAYERS" "$EXPECTED_LAYERS" "$ROOT_LAYERS" "$ROOT_EXPECTED" "$ROOT_NAMES" \
	"$ROOT_INCLUDES" "$EX14_NAMES" "$PROBLEMS" "$PROBLEMS_EXPECTED" "$LEVELS_LAYERS" "$LEVELS_EXPECTED" \
	"$HARNESSES" "$EXPECTED_HARNESSES" \
	"$FIRST_RED" "$TURNIN_DIRS" "$ROOT_TURNIN_DIRS" "$SHELL_TAGS" "$REDIRECT_ARGS" "$ARGVGUARD_BUILDS" "$DIR/BUILD.bazel" "$ROOT_DIR/BUILD.bazel"; do
	[ -f "$_f" ] || { echo "macro_fixtures_test.sh: no file at $_f" >&2; exit 2; }
done
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

# A real program: an ELF file that runs and prints what the harness prints on
# the stub, 0.
is_program() {  # is_program NAME BIN [OUTPUT]  -- OUTPUT defaults to 0
	[ -f "$2" ] || { bad "$1" "$2 was not built"; return; }
	if [ "$(head -c 4 "$2" | od -An -c | tr -d ' \n')" != '177ELF' ]; then
		bad "$1" "not a program: $(head -n 3 "$2" | tr '\n' ' ')"
		return
	fi
	_o=$("$2" 2>&1)
	_want=${3-0}
	[ "$_o" = "$_want" ] && ok "$1" || bad "$1" "it printed '$_o', not '$_want'"
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

# A turn-in at the root of deliverable/ (./root): no exNN/ folder, sources in
# srcs/, the header in includes/, a Makefile that says so. Its program is
# real only if the build staged the subfolders, took srcs/main.c from
# `make -Bn`, and took `-I includes` from it too -- main.c includes a header
# nothing else would find. And the files layer names each file by its path
# from the root, so a srcs/ file is never mistaken for a top-level one.
is_program "a root turn-in in srcs/ and includes/ builds, -I and all" "$ROOT_DIR/ex00_bin" ""
printf 'Makefile\nincludes/toy_root.h\nsrcs/main.c\n' > "$WORK/root_names"
if diff "$WORK/root_names" "$ROOT_NAMES" > /dev/null 2>&1; then
	ok "its files layer lists the tree, by path from the root"
else
	bad "its files layer lists the tree, by path from the root" \
		"it lists: $(tr '\n' ' ' < "$ROOT_NAMES")"
fi

# ...and the include directories its Makefile passes, as its build wrote them
# for the compile and forbidden layers (--inc-file): the same `make -Bn`, so a
# layer compiling main.c on its own finds toy_root.h exactly where the
# program's build did -- through -I includes, and through nothing else.
if [ "$(cat "$ROOT_INCLUDES")" = "$ROOT_DIR/deliverable/includes" ]; then
	ok "its Makefile's -I reaches the static layers"
else
	bad "its Makefile's -I reaches the static layers" \
		"the list reads: $(tr '\n' ' ' < "$ROOT_INCLUDES")"
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

# A Makefile program with a .c its Makefile never names: the program is built
# from what `make -Bn` names, and the extra file changes nothing it links.
is_program "ex19 builds from toy19.c alone, as its Makefile says" "$DIR/ex19_bin" ""

# A file the grader brings, in a subfolder (C 09 ex01's srcs/): a copy in the
# turn-in is only reported if the files layer looks there.
if grep -qx 'srcs/toy.c' "$EX14_NAMES"; then
	ok "ex14's files layer sees a copy of the grader's srcs/ file"
else
	bad "ex14's files layer sees a copy of the grader's srcs/ file" \
		"it lists: $(tr '\n' ' ' < "$EX14_NAMES")"
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
[ -n "$LINES" ] || { echo "macro_fixtures_test.sh: no --lines given" >&2; exit 2; }
while IFS=' ' read -r _lf _lw; do
	[ -n "$_lf" ] || continue
	_want=""
	[ "$_lw" = - ] || _want=$(printf '%s\n' "$_lw" | tr ',' '\n')
	_name=$(printf '%s' "$_lf" | sed 's#^.*macro_fixtures/##')
	if [ "$(cat "$_lf")" = "$_want" ]; then
		ok "$_name holds what its toy's state gives"
	else
		bad "$_name holds what its toy's state gives" \
			"it reads: $(tr '\n' ' ' < "$_lf"), not: $(printf '%s' "$_want" | tr '\n' ' ')"
	fi
done <<LINES_EOF
$LINES
LINES_EOF

# Every contract check, fed the broken contract it guards against: each case's
# message holds the words contract_problems.expected gives it, and a case
# written to pass says OK. A check that stops firing -- or starts firing on a
# good contract -- is red here, not in a module that happens to trip it.
while IFS= read -r _line; do
	case "$_line" in "" | "#"*) continue ;; esac
	_case=${_line%%"	"*}
	_want=${_line#*"	"}
	_got=$(sed -n "s/^$_case: //p" "$PROBLEMS" | head -n 1)
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
_cases=$(grep -c . "$PROBLEMS")
_listed=$(grep -c '^[^#]' "$PROBLEMS_EXPECTED")
[ "$_cases" = "$_listed" ] && ok "every contract case is in contract_problems.expected" ||
	bad "every contract case is in contract_problems.expected" "$_cases cases, $_listed expected"

# THE TURN-IN FOLDER, read the way tools/first_red.sh reads it -- from the
# subject() call as it is written, since it runs outside Bazel on a log --
# against the folder the macros compute from the same contract (turnin_dir).
# A reading that parts from the macros' names the wrong folder when it asks
# whether an exercise is written, and calls a written one "not written yet".
turnin_match() {  # turnin_match PACKAGE DIR EXPECTED
	_tm_bad=""
	while read -r _tm_ex _tm_want; do
		[ -n "$_tm_ex" ] || continue
		_tm_got=$(sh "$FIRST_RED" --turnin "$2" "$_tm_ex" 2>&1)
		[ "$_tm_got" = "$_tm_want" ] || _tm_bad="$_tm_bad $_tm_ex:'$_tm_got'!='$_tm_want'"
	done < "$3"
	if [ -z "$_tm_bad" ]; then
		ok "first_red reads $1's turn-in folders as the macros do"
	else
		bad "first_red reads $1's turn-in folders as the macros do" "$_tm_bad"
	fi
}
turnin_match tools/tests/macro_fixtures "$DIR" "$TURNIN_DIRS"
turnin_match tools/tests/macro_fixtures/root "$ROOT_DIR" "$ROOT_TURNIN_DIRS"
# Every module's, from the lines c_levels() emits beside its BUILD.bazel. A
# module none is given for is the test's data falling behind: conventions.sh
# holds tools/tests/BUILD.bazel's _MODULES to the REMOTES table, and this list
# is built from the same _MODULES.
[ -n "$MODULE_TURNIN" ] || { echo "macro_fixtures_test.sh: no --module-turnin-dirs given" >&2; exit 2; }
while IFS= read -r _mt_f; do
	[ -n "$_mt_f" ] || continue
	_mt_d=${_mt_f%/*}
	[ -f "$_mt_f" ] && [ -f "$_mt_d/BUILD.bazel" ] || {
		echo "macro_fixtures_test.sh: $_mt_f, or the BUILD.bazel beside it, is not staged" >&2
		exit 2
	}
	turnin_match "$_mt_d" "$_mt_d" "$_mt_f"
done <<MT_EOF
$MODULE_TURNIN
MT_EOF

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

# What the macros emitted, against what they must.
layers_match() {  # layers_match PACKAGE EXPECTED EMITTED
	if diff "$2" "$3" > "$WORK/layers.diff" 2>&1; then
		ok "every layer of $1 emitted as expected ($(grep -c . "$3") tests)"
		return
	fi
	bad "the tests the macros emitted in $1" "they differ from its layers.expected"
	echo ""
	echo "  '<' is in $1/layers.expected and was not emitted;"
	echo "  '>' was emitted and is not in it. A test that is 'no_turnin.sh' reads"
	echo "  NOT TURNED IN; ' gated' means it SKIPs unless NO_SKIP=1; ' staged' and"
	echo "  ' make-includes' say what reaches a compile layer's include path (see"
	echo "  the :layers target in tools/tests/macro_fixtures/BUILD.bazel)."
	sed 's/^/    /' "$WORK/layers.diff"
	echo ""
	echo "  If a macro changed on purpose (a new layer, a layer renamed), check"
	echo "  that every new line is what that exercise's state should give, then:"
	echo "    bazel build //$1:layers &&"
	echo "      cat bazel-bin/$1/layers.txt > $1/layers.expected   (cat, not cp: a"
	echo "      copy of bazel-bin's read-only, executable file keeps its mode)"
}
layers_match tools/tests/macro_fixtures "$EXPECTED_LAYERS" "$LAYERS"
layers_match tools/tests/macro_fixtures/root "$ROOT_EXPECTED" "$ROOT_LAYERS"
layers_match tools/tests/macro_fixtures/levels "$LEVELS_EXPECTED" "$LEVELS_LAYERS"

# The hand measurement in the package's BUILD file ("N tests, R red; ...")
# counts the tests a run of all of them executes, which is the lines of
# layers.expected. Its verdicts cannot be checked here (a test cannot run
# other tests), but its count can: the w4-costs merge added six tests,
# updated the lines of the three exercises that gained them and left the
# count at 173, so a reader comparing a hand run with it saw six tests
# appear from nowhere. A count that changes with layers.expected is
# re-measured with it.
_said=$(sed -n 's/^# \([0-9][0-9]*\) tests, .*/\1/p' "$DIR/BUILD.bazel" | head -n 1)
_have=$(grep -c . "$EXPECTED_LAYERS")
if [ -z "$_said" ]; then
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
if ! grep -q ' prototype_test=' "$HARNESSES"; then
	bad "the harnesses of tools/tests/macro_fixtures" "none carries a prototype_test= tag"
elif diff "$EXPECTED_HARNESSES" "$HARNESSES" > "$WORK/harnesses.diff" 2>&1; then
	ok "every harness names its prototype test ($(grep -c ' prototype_test=' "$HARNESSES") harnesses)"
else
	bad "the programs built in tools/tests/macro_fixtures" "they differ from its harnesses.expected"
	echo ""
	echo "  '<' is in harnesses.expected and was not built so; '>' was built and is"
	echo "  not in it. Each line is a student_binary and the prototype test its"
	echo "  harness names (tools/defs.bzl's _student_bin), UNTAGGED where it names"
	echo "  none, or 'own program' where it links no harness."
	sed 's/^/    /' "$WORK/harnesses.diff"
	echo ""
	echo "  If a macro changed on purpose, check every new line, then:"
	echo "    bazel build //tools/tests/macro_fixtures:harnesses &&"
	echo "      cat bazel-bin/tools/tests/macro_fixtures/harnesses.txt > tools/tests/macro_fixtures/harnesses.expected"
fi

echo ""
if [ "$FAIL" -ne 0 ]; then
	echo "macro_fixtures: FAIL — $FAIL of $((PASS + FAIL)) check(s)."
	exit 1
fi
echo "macro_fixtures: OK — $PASS check(s)."
exit 0
