#!/bin/sh
# Run a binary and compare its captured output against an expected file,
# rendering a legible per-line PASS/FAIL table (not a raw diff).
#
# The table shows EVERY line — passing and failing, in order — because for a
# student who did not write the test, the passing rows document what the
# function is supposed to do. Columns: CASE | EXPECTED | GOT | STATUS.
#
# THE VERDICT IS DECIDED BEFORE ANYTHING IS RENDERED. How the run ended (it
# returned, crashed, or ran out of time), whether the bytes match, and whether
# the exit status is one this case asks for are all settled first, and the
# RESULT line and the hints follow from all of them. They used to be decided in
# three places: the table printed "RESULT: PASS (n/n passed)" from the rows
# alone, a byte check after it blamed "a missing or extra final newline" for
# any difference at all, and a wrong exit status was one line on stderr after
# the PASS -- each with no hints (finding 035).
#
# ROWS ARE COMPARED AS STRINGS. awk's == compares two input fields numerically
# when both look like numbers, so "042" matched "42" and "0257948136 " (a
# trailing space) matched "0257948136" (finding 035).
#
# A FAILING ROW SHOWS ITS BYTES. Both cells are rendered by runner_lib.sh's
# rl_vis_exact -- every byte outside printable ASCII as \xHH, a tab as \t, the
# backslash doubled and a literal $ as \x24 -- and end in $ where the line
# ended, the way `cat -e` marks a line end in the subjects' own transcripts; a
# legend under the table names the marks the SHOWN rows hold (read off the
# cells that are printed, after the row cap has chosen them, so a mark only a
# hidden row held is not named). A NUL, a trailing space or a missing final
# newline used to print as two identical cells marked FAIL (finding 042), and
# an expected line ending in a literal $ as one that ended there. Passing rows
# are printed as they are. A long failing row is cut to a window around its
# first difference (DIFF_CELL_MAX, default 100 bytes).
#
# HARNESS-ESCAPED VALUES. A test program whose value holds a line break (Rush
# 00 prints a whole rectangle as one labeled value) or a NUL (C 02 ex01 shows
# a buffer's NUL bytes) cannot print it raw, so it writes the value in the
# renderer's own notation -- \\ a backslash, \n a line break, \t a tab, \xHH
# in lowercase hex any other byte outside printable ASCII, every other byte as
# it is -- and its fixture says so with --escaped-values (c_function's
# escaped_values; rush_variant always).
# Rendered with rl_vis_exact, those cells were escaped a second time: "/\\\n"
# showed as "/\\\\\\n" under a legend saying \\ is one backslash. With the flag
# they are rendered by rl_vis_noted, which leaves the notation's backslashes
# as they are, and the expected file is checked against the notation first, so
# a harness that declares it and writes another one ("\0") is stopped as a
# harness error. //tools:conventions holds every test program that writes an
# escape of its own to declaring it.
#
# A BINARY EXPECTED FILE is summarised, not tabled: when at least 30% of the
# expected output's bytes are ones a terminal cannot show (NULs included), the
# report is both sizes, the first differing byte and each side's bytes from
# just before it, rendered as the table renders a cell (rl_diff_window).
# Decided by content, so no case has to remember to ask for it.
#
# AFTER A CRASH, A TIMEOUT OR A RUNAWAY the table still shows every row, in
# fixture order, and one plain paragraph says what the ending means (finding
# 064). What the rows MEAN depends on who wrote the program, and the caller
# says which with --harness-fixture:
#   with it     the harness's own test program, which prints one row per case
#               with stdout unbuffered (tools/unbuffered_stdout.c): a line is
#               on the file before the next case runs. The rows before the
#               first missing one are real results, that one is marked as the
#               case that was running, the ones after it read "not reached",
#               and the hints for the marked case come first. The runner
#               checks the premise before it relies on it: a binary without
#               the library's marker is a wiring error (exit 2).
#   without it  a student's own program (c_program), which may buffer its
#               output the way printf does: a crash can take lines it had
#               already produced with it, so a missing row is not where it
#               stopped. Missing rows read "(no line)", nothing is marked, and
#               RESULT says how many lines reached the output.
#
# HOW THE RUN ENDED comes from tools/exit_status, which asks waitpid(), never
# from $?: the shell reports signal N as 128+N, which is also a status a
# program can return (`return (-1);` is 255), and a returned 255 used to be
# read as "died on signal 127".
#
# A PROGRAM'S CASE SAYS WHAT IT RAN (--show-run) and keys its own hints
# (--case). For a function exercise the harness's own program labels every
# row; a program exercise's case is a test of its own, whose rows are bare
# line numbers, and whose invocation -- argv, a fixture's path, stdin, the
# folder -- was nowhere in its report (findings 120, 155). c_program passes
# both, for every case: a RAN line opens the report, and a clues.tsv row may
# name the case.
#
# Usage:
#   diff_output.sh --bin PATH --expected PATH [options] [-- PROG ARGS...]
#   diff_output.sh --bin PATH --survive [options] [-- PROG ARGS...]
#
# Options:
#   --expected-alt PATH      another output this case accepts, repeatable: the
#                            subject leaves the reading open and every reading
#                            is bounded (a case's "any_of"). The output passes
#                            when it is exactly one of them; the table compares
#                            it with the one it matched, or with --expected
#                            when it matched none, and the report names the
#                            others.
#   --survive                compare no output (a case's "survive", in place of
#                            --expected): the case passes when the program ends
#                            by itself -- killed by no signal, in time, without
#                            runaway output -- which every reading of an open
#                            case agrees on. --exit still applies. Its report
#                            says what was run (RAN:), pass or fail: there is
#                            no table to say it.
#   --gate-expected FILE     with --survive only: SKIP while another case of the
#   --gate-arg ARG           exercise is red -- this runner, run first on the
#   --gate-label NAME        same program with --expected FILE and that case's
#   --gate-stream S          arguments (--gate-arg, one per argument, in order),
#   --gate-stdin FILE        stream, stdin, --sanitize and --labeled. A survive
#   --gate-sanitize          case asks only that the program ends by itself, and
#   --gate-labeled           an unwritten one does: green there is no news
#                            (review of WP-52). NAME is that case's target, for
#                            the SKIP line. A gate that cannot answer (exit 2)
#                            runs the case anyway; NO_SKIP=1 runs it always.
#   --stream stdout|stderr   which stream to compare (default: stdout)
#   --stdin PATH             feed this file to the program's stdin
#   --argv-file PATH         more arguments, one per line of PATH, after the
#                            ones given after --: an empty line is an empty
#                            argument, which Bazel's `args` cannot carry
#                            (a case's "argv_file"; rl_argv_words)
#   --run-as NAME            run the program as ./NAME, from a folder of its
#                            own holding a copy of it under that name (a
#                            case's "cwd_files"; rl_rundir). Paths the program
#                            is given are then read from that folder.
#   --cwd-file DEST=PATH     with --run-as, a copy of PATH in that folder, as
#                            DEST; repeatable
#   --show-run PROG          print the run first, as a RAN line naming the
#                            program PROG (where Bazel keeps it), so that it
#                            can be run again from the repository root
#   --waiting FILE           the tests that wait for this one (tools/defs.bzl's
#                            _WAITING, one a line with its level): under a
#                            red verdict, NO_SKIP=1 unset, they are named,
#                            with what Bazel shows for them (rl_waiting)
#   --case NAME              this test is the program case NAME: when it
#                            fails, a clues.tsv row naming NAME fires, as a
#                            row naming a failed table row does
#   --sanitize               a leading 16-hex-digit address column, which ASLR
#                            moves on every run (ft_print_memory's): each row's
#                            address is checked against the one the harness
#                            published on an "@addr <16 hex>" line before the
#                            dump (the line is taken out of the output), then
#                            shown as its offset from the block's first row.
#                            Without a published address, only the width, the
#                            letter case and the +16 step are compared. See the
#                            long comment at the normalisation step itself.
#   --labeled                each output/expected line is "CASE<TAB>VALUE"; the
#                            CASE is shown in its own column. Without this, the
#                            CASE column is just the 1-based line number.
#   --escaped-values         with --labeled: the test program has already written
#                            each VALUE in the renderer's notation (\\ a
#                            backslash, \n a line break, \t a tab, \xHH any
#                            other byte outside printable ASCII), because a value
#                            holding a line break or a NUL cannot travel raw. A
#                            failing cell then keeps the notation's backslashes
#                            instead of doubling them (rl_vis_noted), and every
#                            expected value is checked to be in the notation
#                            before anything runs: a backslash that starts none
#                            of its marks is a harness error (exit 2). See
#                            HARNESS-ESCAPED VALUES below.
#   --clues PATH             a clues.tsv of pedagogic hints (concept groups). When
#                            a test fails, fired hints are shown below the table.
#   --harness-fixture        the binary is the harness's own test program,
#                            linked with tools/unbuffered_stdout.c: see AFTER A
#                            CRASH above. Only defs.bzl's output fixtures and
#                            the runners that compile one with --harness-src
#                            (header_check.sh, ilp32_test.sh) pass it.
#   --exit CODE              also assert the program exits with CODE. Empty
#                            asserts nothing.
#   --exit-source subject|reading|convention|default
#                            whose rule CODE is (default subject), which the
#                            failure says: the subject names it; a sentence of
#                            the subject is READ as naming it ("performs the
#                            same function as the system's tail" read as the
#                            tool's own status), which the Run contract checks
#                            at strict, never at basic; or it is this repo's
#                            convention, checked above basic by the rule in
#                            docs/reference.md ("Run contract"). default is the
#                            convention where the c_program case stated
#                            nothing, and is refused (exit 2) when the expected
#                            output mentions an error: see A DEFAULT IS NOT A
#                            DECISION below.
#   --exit-quote TEXT        the subject's sentence behind --exit, shown with
#                            the explanation when the status is wrong (a case's
#                            "exit_quote").
#   --absent NAME            the case hands the program NAME as a file that
#                            will not open (a case's "missing_file"): if
#                            anything by that name is in the directory the
#                            program runs in, nothing is run and this exits 2.
#                            Repeatable.
#   --exit-only              judge only how the run ended: --exit is required,
#                            the output is not compared. For the robust
#                            exit-status targets (<case>_exit).
#   --note-exit CODE         with no --exit, a plain return other than CODE is
#                            noted under the table (never failed), pointing at
#                            the robust exit-status target that fails it.
#   --status-file PATH       write how the program ended there, as one line:
#                            "exit N", "signal N" (25 is the output budget) or
#                            "timeout", for a caller whose report depends on
#                            HOW it failed: ilp32_test.sh explains a SIGILL
#                            differently from wrong output
#   --                       everything after is passed verbatim to the binary
#
# Env: DIFF_TIMEOUT (seconds, default 30), DIFF_MAX_ROWS (rows of the table, as
#      tools/runner_lib.sh's rl_rows reads it: default 40, 0 = all),
#      DIFF_CELL_MAX (default 100), CLUE_MODE (see below).
#
# Exit status: 0 if output (and exit code, if checked) match, 1 otherwise, 2 if
# the harness itself is broken and nothing was checked.
#
# clues.tsv format (tab-separated, one concept group per line; '#'/blank ignored):
#   <hint text><TAB><member CASE label><TAB><member CASE label>...
# A group's hint fires when ANY of its member cases fails. A line with no member
# labels fires on any failure; when every row passed and only the bytes, the
# exit status or the ending were wrong, those are the only hints shown, since no
# case is to blame. Hints are shown most-fundamental first, those for a case
# that was running when the program died ahead of the rest; the count shown is
# capped (default 3) and overridable with the CLUE_MODE env var (an integer, 0
# or "all" for every one), forwarded by Bazel via --test_env=CLUE_MODE=all.

set -u

# The external commands this runner takes from PATH, declared and probed at
# startup. This is the one place the reasoning is written down; every other
# runner carries the same helper and points here.
#
# WHY DECLARE THEM. The failure without this is silent. `grep -q ... && ...`
# with no grep on the machine does not error -- it reads exactly like "no
# match", so the branch is skipped and a real finding is reported under the
# wrong headline, or not at all. asan_run.sh is the worked example: its
# sanitizer-signature probe is a grep, and without one a genuine ASan report
# would be announced as "died on signal 6".
#
# WHY EXIT 2, NEVER 1. 1 means the thing under test is wrong. 2 means the check
# never ran and a human should look. //tools/tests:selftest's want_red insists
# on exit 1 for exactly this reason, so the two can never be confused.
#
# WHY NOT PIN THEM. The same answer /bin/sh got: the question is whether the
# USAGE is portable, not whether the binary is ours. shellcheck's SC3xxx family
# refuses a bashism statically, //tools/tests:selftest_bash replays every arm
# under a second shell, and //tools:conventions recomputes the list below from
# what the script actually calls, so it cannot go stale. Pinning coreutils would
# buy a guarantee those three already give.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "diff_output.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cmp grep mktemp mv rm tail tr wc

# The shared runner helpers -- the time budget, how a run ended (from
# tools/exit_status), exiting signal traps, excerpts and the one clues.tsv
# rule -- are tools/runner_lib.sh's, which says why each is written once. The
# table below is this runner's own.
RL_NAME=diff_output
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "diff_output.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"

BIN=""
EXPECTED=""
STREAM="stdout"
STDIN_FILE=""
SANITIZE=0
LABELED=0
ESCAPED=0
CLUES_FILE=""
EXPECT_EXIT=""
EXIT_SOURCE="subject"
EXIT_QUOTE=""
EXIT_ONLY=0
NOTE_EXIT=""
STATUS_FILE=""
FIXTURE=0
ALTS=""
SURVIVE=0
ABSENT=""
GATE_EXPECTED=""
GATE_LABEL=""
# The gate case's arguments, each one shell-quoted (rl_shword), for an eval
# that rebuilds them as one list: a variable holds no list, and an argument
# may hold a blank, a newline or any byte.
GATE_ARGV=""
GATE_PASS=""
ARGV_FILE=""
RUN_AS=""
CWD_FILES=""
SHOW_RUN=""
CASE_NAME=""
WAITING=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "diff_output.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--expected) need "$1" "$#"; EXPECTED="$2"; shift 2 ;;
		--expected-alt) need "$1" "$#"; ALTS="$ALTS
$2"; shift 2 ;;
		--survive) SURVIVE=1; shift ;;
		--absent) need "$1" "$#"; ABSENT="$ABSENT
$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-label) need "$1" "$#"; GATE_LABEL="$2"; shift 2 ;;
		--gate-arg) need "$1" "$#"; GATE_ARGV="$GATE_ARGV $(printf '%s' "$2" | rl_shword)"; shift 2 ;;
		--gate-stream) need "$1" "$#"; rl_list_add GATE_PASS --stream "$2"; shift 2 ;;
		--gate-stdin) need "$1" "$#"; rl_list_add GATE_PASS --stdin "$2"; shift 2 ;;
		--gate-sanitize) rl_list_add GATE_PASS --sanitize; shift ;;
		--gate-labeled) rl_list_add GATE_PASS --labeled; shift ;;
		--stream) need "$1" "$#"; STREAM="$2"; shift 2 ;;
		--stdin) need "$1" "$#"; STDIN_FILE="$2"; shift 2 ;;
		--sanitize) SANITIZE=1; shift ;;
		--labeled) LABELED=1; shift ;;
		--escaped-values) ESCAPED=1; shift ;;
		--clues) need "$1" "$#"; CLUES_FILE="$2"; shift 2 ;;
		--exit) need "$1" "$#"; EXPECT_EXIT="$2"; shift 2 ;;
		--exit-source) need "$1" "$#"; EXIT_SOURCE="$2"; shift 2 ;;
		--exit-quote) need "$1" "$#"; EXIT_QUOTE="$2"; shift 2 ;;
		--exit-only) EXIT_ONLY=1; shift ;;
		--note-exit) need "$1" "$#"; NOTE_EXIT="$2"; shift 2 ;;
		--status-file) need "$1" "$#"; STATUS_FILE="$2"; shift 2 ;;
		--harness-fixture) FIXTURE=1; shift ;;
		--argv-file) need "$1" "$#"; ARGV_FILE="$2"; shift 2 ;;
		--run-as) need "$1" "$#"; RUN_AS="$2"; shift 2 ;;
		--cwd-file) need "$1" "$#"; CWD_FILES="$CWD_FILES
$2"; shift 2 ;;
		--show-run) need "$1" "$#"; SHOW_RUN="$2"; shift 2 ;;
		--case) need "$1" "$#"; CASE_NAME="$2"; shift 2 ;;
		--waiting) need "$1" "$#"; WAITING="$2"; shift 2 ;;
		--) shift; break ;;
		*) echo "diff_output.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
# Under a red verdict, the tests that wait for this one (rl_waiting): from
# here on, so a stand-in's red says it too. The cleanup joins it below.
[ -z "$WAITING" ] || [ -f "$WAITING" ] || {
	echo "diff_output.sh: no --waiting file at $WAITING" >&2
	exit 2
}
rl_traps 'rl_waiting $? "$WAITING"'

if [ -z "$BIN" ] || { [ -z "$EXPECTED" ] && [ "$SURVIVE" -eq 0 ]; }; then
	echo "diff_output.sh: --bin and --expected (or --survive) are required" >&2
	exit 2
fi
if [ "$SURVIVE" -eq 1 ] && [ -n "$EXPECTED$ALTS" ]; then
	echo "diff_output.sh: --survive compares no output, so it takes no --expected" >&2
	exit 2
fi
if [ -n "$ALTS" ] && [ -z "$EXPECTED" ]; then
	echo "diff_output.sh: --expected-alt is another output besides --expected" >&2
	exit 2
fi
if [ -n "$GATE_EXPECTED$GATE_ARGV$GATE_PASS$GATE_LABEL" ] && [ "$SURVIVE" -eq 0 ]; then
	echo "diff_output.sh: --gate-* gate a survive case on another case; a case with an" >&2
	echo "               expected output is judged on it, and needs no gate" >&2
	exit 2
fi
if [ -n "$GATE_ARGV$GATE_PASS$GATE_LABEL" ] && [ -z "$GATE_EXPECTED" ]; then
	echo "diff_output.sh: --gate-arg, --gate-label, --gate-stream, --gate-stdin," >&2
	echo "               --gate-sanitize and --gate-labeled describe the case --gate-expected names" >&2
	exit 2
fi
if [ "$ESCAPED" -eq 1 ] && [ "$LABELED" -eq 0 ]; then
	echo "diff_output.sh: --escaped-values says each VALUE of a labeled row is in" >&2
	echo "               the notation, so it needs --labeled" >&2
	exit 2
fi
case "$EXPECT_EXIT" in
	"") ;;
	*[!0-9]*)
		echo "diff_output.sh: --exit needs a status from 0 to 255, not '$EXPECT_EXIT'" >&2
		exit 2 ;;
esac
case "$NOTE_EXIT" in
	"") ;;
	*[!0-9]*)
		echo "diff_output.sh: --note-exit needs a status from 0 to 255, not '$NOTE_EXIT'" >&2
		exit 2 ;;
esac
case "$EXIT_SOURCE" in
	subject | reading | convention | default) ;;
	*) echo "diff_output.sh: --exit-source must be subject, reading, convention or default, not '$EXIT_SOURCE'" >&2
	   exit 2 ;;
esac
# A clue file that is not there would print no hints and say nothing about it:
# Bazel stages every one a target names, so its absence is a wiring error.
if [ -n "$CLUES_FILE" ] && [ ! -r "$CLUES_FILE" ]; then
	echo "diff_output.sh: --clues file '$CLUES_FILE' is not readable" >&2
	exit 2
fi
# --exit-only with nothing to compare the status to would judge nothing and
# pass: a wiring error, never a verdict.
if [ "$EXIT_ONLY" -eq 1 ] && [ -z "$EXPECT_EXIT" ]; then
	echo "diff_output.sh: --exit-only needs --exit: it judges the status and nothing else" >&2
	exit 2
fi
# The run as the case describes it, or no run: an argument file that is not
# there would run the program with fewer arguments, and a staged file without
# a folder to stage it in would be run from somewhere else.
if [ -n "$ARGV_FILE" ] && [ ! -r "$ARGV_FILE" ]; then
	echo "diff_output.sh: --argv-file '$ARGV_FILE' is not readable" >&2
	exit 2
fi
if [ -n "$CWD_FILES" ] && [ -z "$RUN_AS" ]; then
	echo "diff_output.sh: --cwd-file stages a file in the folder --run-as runs the program from" >&2
	exit 2
fi
case "$RUN_AS" in
	*/* | . | ..)
		echo "diff_output.sh: --run-as takes the program's file name, not '$RUN_AS'" >&2
		exit 2 ;;
esac

# A DEFAULT IS NOT A DECISION WHEN THE CASE EXPECTS AN ERROR MESSAGE.
#
# A c_program case that says nothing about its exit status gets a robust twin
# expecting 0, and the twin is told so with --exit-source default. For an
# input the subject answers with an error message, that twin fails a correct
# program returning 1 and calls 0 "the C convention". Every error case in the
# repo was marked invalid_input by hand, and nothing asked for the mark, so a
# new project's first unmarked "Error" would have gone in unnoticed (review of
# wave 3; BSQ's two_maps, one valid map and one "map error", was one). So the
# default is checked against the expected output: one that mentions an error
# stops this twin as a harness error until the case says which it is. A case
# that compares stderr cannot get here: c_program refuses it at loading.
if [ "$EXIT_SOURCE" = default ] && grep -qi 'error' "$EXPECTED" 2> /dev/null; then
	echo "diff_output.sh: the expected output, $EXPECTED, mentions an error, and" >&2
	echo "               its c_program case says nothing about its exit status, so" >&2
	echo "               this twin would demand 0 from a program answering it." >&2
	echo "               Say which it is, in the case: \"invalid_input\": True if the" >&2
	echo "               subject answers this input with an error message (no level" >&2
	echo "               then judges the status), \"invalid_input\": False if it does" >&2
	echo "               not (this twin then expects 0), or \"exit\"" >&2
	echo "               (docs/reference.md, \"Writing a c_program case\")." >&2
	exit 2
fi

# A DECLARED NOTATION IS CHECKED, NOT TRUSTED. --escaped-values renders each
# backslash of a value as the notation's own, which is right only if the test
# program writes that notation: one that declares it and writes "\0" for a NUL
# would show "\0" under a legend that never names it. The expected file was
# written by the same program, so a mark outside the notation there is a
# harness error, found before anything runs. Only the VALUE is read: a CASE
# label is prose ("(pads with \0)").
if [ "$ESCAPED" -eq 1 ]; then
	while IFS= read -r _e; do
		[ -n "$_e" ] || continue
		_bad=$(LC_ALL=C awk '
			{
				v = $0
				p = index(v, "\t")
				if (p == 0) next
				v = substr(v, p + 1)
				n = length(v)
				for (i = 1; i <= n; i++) {
					if (substr(v, i, 1) != "\\") continue
					c = substr(v, i + 1, 1)
					if (c == "\\" || c == "n" || c == "t") { i++; continue }
					if (c == "x" && substr(v, i + 2, 2) ~ /^[0-9a-f][0-9a-f]$/) { i += 3; continue }
					printf "line %d: \"%s\"\n", NR, substr(v, i, 4)
					exit
				}
			}' "$_e")
		[ -z "$_bad" ] && continue
		# printf, not echo: dash's echo reads \0 and \n in its argument.
		# conventions: notation, not a legend -- what a test program must write, for its author
		printf '%s\n' \
			"diff_output.sh: --escaped-values says the test program writes each value" \
			"               in the renderer's notation (\\\\ a backslash, \\n a line" \
			"               break, \\t a tab, \\xHH any other byte outside printable" \
			"               ASCII, in lowercase hex), but ${_e##*/} has a backslash" \
			"               that starts none of them, at $_bad." \
			"               Make the test program write the notation (this file's" \
			"               HARNESS-ESCAPED VALUES), and regenerate the expected file." >&2
		exit 2
	done <<NOTE_EOF
$EXPECTED$ALTS
NOTE_EOF
fi

# A PROGRAM THAT DID NOT BUILD is a stand-in script that says why (see
# tools/standin.sh). Graded as a program, its "output" is empty and its exit
# status arbitrary, and the report would be a table of wrong answers under
# this exercise's hints, none of which is about a build. Say what the build
# said instead, whole, and fail.
case "$0" in */*) _sl_dir=${0%/*} ;; *) _sl_dir=. ;; esac
for _sl in "$_sl_dir/standin.sh" \
	"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
	[ -f "$_sl" ] && break
done
[ -f "$_sl" ] || { echo "diff_output.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
standin_check diff_output "$BIN" fail "the program"

# A SURVIVE CASE'S GATE (--gate-expected). It asks only that the program ends
# by itself, and a program nobody has written does: do-op's stub was green on
# INT_MIN / -1 at strict, two green targets for a program that did nothing
# (review of WP-52). So while the exercise's own case is red this case SKIPs,
# as the memory layers do (valgrind_test.sh's gate, whose rules this keeps):
# skip on 1; on 2 or more, the gate could not answer, so say so and run.
# conventions: harness tool SELF -- this runner, as a survive case's gate, which keeps this test's budget (RL_DEADLINE)
SELF=$0
[ -n "$GATE_LABEL" ] || GATE_LABEL="this exercise's own case"
if [ -n "$GATE_EXPECTED" ] && [ "${NO_SKIP:-0}" != "1" ]; then
	# GATE_PASS is a list (runner_lib.sh, LISTS OF WORDS); GATE_ARGV is shell
	# words, each written by rl_shword, for eval.
	(
		eval "set -- $GATE_ARGV"
		rl_split_on
		# shellcheck disable=SC2086
		sh "$SELF" --bin "$BIN" --expected "$GATE_EXPECTED" $GATE_PASS -- "$@"
	) > /dev/null 2>&1
	_gate_rc=$?
	if [ "$_gate_rc" -ge 2 ]; then
		echo " diff_output: the gate ($GATE_LABEL) could not be"
		echo "              evaluated (exit $_gate_rc), so this case runs anyway rather than going quiet."
	elif [ "$_gate_rc" -eq 1 ]; then
		echo " SKIP — $GATE_LABEL is not passing yet."
		echo ""
		echo "  This case only asks that the program ends by itself, and a program"
		echo "  that does nothing yet does that: green here would say nothing. Get"
		echo "  that case green and this one starts checking."
		echo ""
		echo "  (NO_SKIP=1 runs a waiting layer anyway:"
		echo "   $(rl_noskip_cmd))"
		exit 0
	fi
fi

# WHAT A SURVIVE CASE RAN, said before its verdict, pass or fail: it has no
# table to say it, and "SURVIVED" alone does not say on what (review of
# WP-52). Each argument as one shell word (rl_shword), so the line can be
# copied to run the case again. Not under --show-run: c_program's every case
# then opens with rl_ran's RAN line (below), which also says the argument
# file's words and the run folder, and one RAN line is what a report holds.
if [ "$SURVIVE" -eq 1 ] && [ -z "$SHOW_RUN" ]; then
	_ran=" RAN: ./${BIN##*/}"
	for _a in "$@"; do
		_ran="$_ran $(printf '%s' "$_a" | rl_shword)"
	done
	[ -z "$STDIN_FILE" ] || _ran="$_ran < ${STDIN_FILE##*/}"
	printf '%s\n' "$_ran"
fi

# One scratch directory rather than a mktemp per file: this is the
# most-invoked runner in the repo -- every per-case output test in every module
# goes through it -- and each process it starts is paid by every one of them.
TMPD=$(mktemp -d) || { echo "diff_output.sh: cannot create a scratch directory" >&2; exit 2; }
ACTUAL="$TMPD/actual"
# The stream we are NOT comparing used to go to /dev/null. Keep it: when
# something goes wrong it usually says why (a sanitizer report, a glibc
# "free(): invalid next size", the program's own error message), and throwing it
# away made every failure harder to read than it needed to be.
OTHER="$TMPD/other"
# What the table decided, for the hints that follow the explanation blocks:
# which case was running, which rows failed, and which hints apply at all.
STATE="$TMPD/state"
# The failed case labels, for the hints (rl_clues).
FAILED_F="$TMPD/failed"
TAB=$(printf '\t')
# Its temp files were removed by hand-written `rm -f` on the exit paths
# somebody thought of. A trap covers the ones nobody did: the awk-driven exits
# below, and the signal Bazel sends a test that runs out of time -- which it
# now also ENDS (rl_traps), instead of carrying on without its files.
rl_traps 'rl_waiting $? "$WAITING"; rm -rf "$TMPD"'
# How many rows the table shows: DIFF_MAX_ROWS, read where every differential
# report reads it (tools/runner_lib.sh, rl_rows).
rl_rows ""

# HOW THE RUN ENDED is read from waitpid() by tools/exit_status, never guessed
# from the status: rl_run makes the run through it, and rl_classify reads its
# report (tools/runner_lib.sh, "THE HELPER THAT SAYS HOW A RUN ENDED"). Without
# the helper the runner stops at its first run with a wiring error.

# --harness-fixture's premise, checked rather than trusted: the marker string
# tools/unbuffered_stdout.c puts in every binary it is linked into. A fixture
# without it would have its first missing line called "the case that was
# running" when a crash may have taken buffered lines with it.
if [ "$FIXTURE" -eq 1 ] && ! grep -q -F "tools/unbuffered_stdout: stdout is unbuffered" "$BIN"; then
	echo "diff_output.sh: --harness-fixture on '$BIN', which is not linked with" >&2
	echo "               tools/unbuffered_stdout.c: its rows cannot be read as cases" >&2
	echo "               that finished. Build it with defs.bzl's _output_fixture_binary," >&2
	echo "               or pass the file with --harness-src, or drop --harness-fixture." >&2
	exit 2
fi

# Runaway guard. This runs code nobody has verified: a loop that never
# terminates its condition writes at page-cache speed for the WHOLE Bazel
# timeout — gigabytes into the test tmpdir — and an infinite loop that prints
# nothing burns a core for 60s before Bazel gives up with no explanation the
# student can act on. run_check.sh has carried this pattern for the rush all
# along; every other runner executed student code bare.
#
# `ulimit -f` bounds the output at the source: the kernel kills the writer with
# SIGXFSZ (signal 25) the moment it goes past the budget, so nothing can fill
# the disk. It counts 512-byte blocks. The budget scales off the expected
# output — 32x it, floor 4 MiB — so it is far above any legitimate result and
# far below "fills the container".
# The largest output this case accepts, when it accepts several; none at all
# for a survive case, which the floor below covers.
EXP_BYTES=0
while IFS= read -r _e; do
	[ -n "$_e" ] || continue
	_b=$(wc -c < "$_e" 2>/dev/null || echo 0)
	[ "$_b" -gt "$EXP_BYTES" ] && EXP_BYTES=$_b
done <<EXP_EOF
$EXPECTED$ALTS
EXP_EOF
CAP=$(( EXP_BYTES * 32 ))
[ "$CAP" -lt 4194304 ] && CAP=4194304
BLOCKS=$(( CAP / 512 + 2 ))

# THE INVOCATION, as the case describes it: the arguments after --, then the
# argument file's (rl_argv_words); from the folder --run-as makes, holding the
# program and each --cwd-file (rl_rundir), or from here. Printed first when
# c_program asks (--show-run), so the report opens with what was run.
if [ -n "$ARGV_FILE" ]; then
	_aw=$(rl_argv_words "$ARGV_FILE") || { echo "diff_output.sh: cannot read --argv-file '$ARGV_FILE'" >&2; exit 2; }
	eval "set -- \"\$@\" $_aw"
fi
RUN_BIN=$BIN
RUN_DIR=.
_ran_specs=""
_ran_prog=$SHOW_RUN
_ran_in=$STDIN_FILE
if [ -n "$RUN_AS" ]; then
	RUN_DIR="$TMPD/run"
	rl_rundir "$RUN_DIR" "$RUN_AS" "$BIN" "$CWD_FILES" || exit 2
	RUN_BIN="./$RUN_AS"
	_ran_specs="$RUN_AS=${SHOW_RUN:-$BIN}$CWD_FILES"
	_ran_prog=$RUN_BIN
	# The folder is the program's working directory, so a path given to it
	# from here would no longer resolve.
	case "$STDIN_FILE" in "" | /*) ;; *) STDIN_FILE="$PWD/$STDIN_FILE" ;; esac
fi

# A NAME THE CASE SAYS WILL NOT OPEN, checked: the case marks it
# "missing_file", and a file by that name in the directory the program runs
# in would make the run a different case -- one that opens it -- under the
# missing file's verdict and hints. That is the harness's mistake, not the
# program's, so nothing is run. Looked for where the program runs: the run
# folder --run-as made, which holds only the program and the case's
# "cwd_files", or this directory. It was looked for here whatever the case,
# so a name that was only beside this runner stopped a case run elsewhere,
# and a file the case staged under that name in its run folder was missed.
while IFS= read -r _a; do
	[ -n "$_a" ] || continue
	# A relative name is the program's, opened from where it runs.
	case "$_a" in /*) _ap=$_a ;; *) _ap="$RUN_DIR/$_a" ;; esac
	if [ -e "$_ap" ] || [ -L "$_ap" ]; then
		echo "diff_output.sh: this case hands the program '$_a' as a file that will not" >&2
		if [ "$RUN_DIR" = . ]; then
			echo "               open (--absent, its \"missing_file\"), and $PWD" >&2
		else
			echo "               open (--absent, its \"missing_file\"), and the folder it runs" >&2
			echo "               in (--run-as: the program and each --cwd-file)" >&2
		fi
		echo "               holds something by that name. Give the case a name no file has." >&2
		exit 2
	fi
done <<ABSENT_EOF
$ABSENT
ABSENT_EOF
[ -z "$SHOW_RUN" ] || rl_ran "$_ran_prog" "$_ran_in" "$_ran_specs" "$@"

# An inner timeout, well under Bazel's, so an infinite loop is reported as one
# instead of surfacing as an opaque Bazel timeout. Every test using this runner
# finishes in well under a second. What is left of the test's own limit caps
# DIFF_TIMEOUT too (rl_tmo), so a gate run by another runner cannot outlive it.
if ! rl_tmo "${DIFF_TIMEOUT:-30}"; then
	rl_overrun "this program's run"
	exit 1
fi
TMO=$RL_TMO

# Stdin is the case's file, or /dev/null: never whatever this runner was
# given, which differs between `bazel test`, a hand run and a runner that
# calls this one (valgrind_test.sh's gate pins it the same way). A program
# that reads stdin with none meant for it meets an end of file, not a wait.
RUN_IN=${STDIN_FILE:-/dev/null}
(
	cd "$RUN_DIR" || exit 2
	ulimit -f "$BLOCKS" 2>/dev/null
	if [ "$STREAM" = "stderr" ]; then
		rl_run "$RUN_BIN" "$@" < "$RUN_IN" 2> "$ACTUAL" > "$OTHER"
	else
		rl_run "$RUN_BIN" "$@" < "$RUN_IN" > "$ACTUAL" 2> "$OTHER"
	fi
)
RC=$?

# HOW THE RUN ENDED, named once; every verdict below reads ENDED, never a
# guess from RC. RC is the program's own status when it returned; SIG the
# signal that killed it. rl_classify reads it from tools/exit_status's report,
# which also says when the time limit ended the run.
SIG=""
rl_classify "$RC"
case "$RL_CAUSE" in
	ok | "exit") ENDED=returned; RC=$RL_RC ;;
	signal) ENDED=crash; SIG=$RL_SIG ;;
	# SIGXFSZ: the output budget above stopped it.
	runaway) ENDED=runaway; SIG=$RL_SIG ;;
	"timeout") ENDED=timeout ;;
	noexec)
		echo "diff_output.sh: '$BIN' $RL_WHY" >&2
		exit 2 ;;
	*)
		echo "diff_output.sh: '$BIN' $RL_WHY -- tools/exit_status reported nothing" >&2
		exit 2 ;;
esac
# Before any verdict, so a runaway and a timeout are recorded too.
if [ -n "$STATUS_FILE" ]; then
	case "$ENDED" in
		returned) _st="exit $RC" ;;
		"timeout") _st="timeout" ;;
		*) _st="signal $SIG" ;;
	esac
	printf '%s\n' "$_st" > "$STATUS_FILE" || {
		echo "diff_output.sh: cannot write --status-file '$STATUS_FILE'" >&2
		exit 2
	}
fi

# What the ending means, in one or two plain lines. A program KILLED BY A
# SIGNAL is never correct, however good its output looks: without this a
# function could print byte-perfect output and then segfault on the way out --
# stack smashing, a double free, a bad write past a buffer -- and this layer
# said PASS. The grader does not, and neither should we.
explain_ending() {
	echo " --------------------------------------------------"
	if [ "$ENDED" = timeout ]; then
		echo " TIMEOUT: the program did not finish within ${TMO}s and was stopped."
		echo "          Every case here should finish almost at once, so the one it"
		echo "          was on most likely never ends: a loop whose condition does"
		echo "          not become false on that input."
		if [ "$RL_CLAMPED" = 1 ]; then
			rl__limit
			echo "          ${TMO}s was what was left of $_rl_lim"
			echo "          (TEST_TIMEOUT=${TEST_TIMEOUT:-?}s, less a few seconds to write this report)."
		fi
		# Rows judged wrong before the one it was on are a verdict whatever
		# the machine was doing (RL_WRONG, tools/runner_lib.sh).
		if [ "${RL_WRONG:-0}" -gt 0 ]; then
			echo "          The $RL_WRONG row(s) marked FAIL above it are a verdict all the same."
		fi
		return
	fi
	if [ "$ENDED" = runaway ]; then
		echo " RUNAWAY OUTPUT: the program kept printing past a $CAP-byte budget and"
		if [ "$SURVIVE" -eq 1 ]; then
			echo "                 was stopped. This case expects no particular output."
			echo "                 A loop whose exit condition is never reached prints"
			echo "                 forever."
		else
			echo "                 was stopped. Expected output here is $EXP_BYTES bytes."
			echo "                 A loop whose exit condition is never reached prints"
			echo "                 forever; the rows above are what it printed before."
		fi
		return
	fi
	case "$SIG" in
		4)
			echo " CRASH: the program died on SIGILL (illegal instruction)."
			echo "        Most often a trap the compiler put at an operation C leaves"
			echo "        undefined -- a signed int overflowing, an index past the end of"
			echo "        an array -- which the program then reached. The operation is"
			echo "        wrong on every build; this one stops at it instead of carrying on." ;;
		6)
			echo " CRASH: the program died on SIGABRT (abort)."
			echo "        It was stopped on purpose: most often by the C library, which"
			echo "        found the heap or the stack damaged (a free() of memory malloc"
			echo "        did not hand out, a second free() of the same block, a write past"
			echo "        the end of a buffer), or by an assert() that failed."
			[ -s "$OTHER" ] && echo "        Its own message, below, says which." ;;
		7)
			echo " CRASH: the program died on SIGBUS (bus error)."
			echo "        A memory access the hardware refused: usually a pointer that was"
			echo "        never given a valid address." ;;
		8)
			echo " CRASH: the program died on SIGFPE (arithmetic error)."
			echo "        An integer division or modulo by zero, or INT_MIN / -1." ;;
		11)
			echo " CRASH: the program died on SIGSEGV (invalid memory access)."
			echo "        It read or wrote memory it does not own: a NULL or freed pointer"
			echo "        followed, or an index past the end of an array." ;;
		13)
			echo " CRASH: the program died on SIGPIPE (wrote to a closed pipe)." ;;
		*)
			echo " CRASH: the program died on signal $SIG." ;;
	esac
	echo "        A crash is a failure however right the output looks."
}

# Whose rule an expected exit status is, in the student's terms.
explain_exit_source() {
	if [ "$EXIT_SOURCE" = subject ]; then
		echo "              The subject names this status, so it is part of the verdict"
		echo "              at every level."
		[ -z "$EXIT_QUOTE" ] || echo "              It says: \"$EXIT_QUOTE\""
	elif [ "$EXIT_SOURCE" = reading ]; then
		echo "              The subject gives no number for it. That a sentence of it asks"
		echo "              for this one is this harness's reading, never the subject's,"
		echo "              checked at strict and never at basic (docs/reference.md,"
		echo "              \"Run contract\")."
		[ -z "$EXIT_QUOTE" ] || echo "              The sentence: \"$EXIT_QUOTE\""
	elif [ "$EXPECT_EXIT" = 0 ]; then
		echo "              The subject gives no number for it. Returning 0 from a run"
		echo "              that did its job is the C convention (EXIT_SUCCESS), which"
		echo "              this repo checks at robust: the rule is this repo's, not the"
		echo "              subject's (docs/reference.md, \"Run contract\")."
	else
		echo "              The subject gives no number for it. Expecting $EXPECT_EXIT is this"
		echo "              repo's rule, checked above basic, not the subject's"
		echo "              (docs/reference.md, \"Run contract\")."
	fi
}

# The stream we did not compare, when something failed: it is usually the
# explanation (a sanitizer report, a libc diagnostic, the program's own
# message).
show_other() {
	[ -s "$OTHER" ] || return 0
	if [ "$ENDED" = crash ]; then
		echo " ----- the program's other stream said -----"
		rl_excerpt "$OTHER" 20 other-stream.txt "   "
	else
		echo " ----- also written to $([ "$STREAM" = "stderr" ] && echo stdout || echo stderr) -----"
		rl_excerpt "$OTHER" 10 other-stream.txt "   "
	fi
}

# --exit-only: the robust exit-status target. The output was checked by the
# case's own output target; this one judges how the run ended and nothing else.
if [ "$EXIT_ONLY" -eq 1 ]; then
	if [ "$ENDED" != returned ]; then
		explain_ending
		show_other
		exit 1
	fi
	if [ "$RC" != "$EXPECT_EXIT" ]; then
		echo " EXIT STATUS: FAIL — the program returned $RC; this check expects $EXPECT_EXIT."
		explain_exit_source
		show_other
		exit 1
	fi
	echo " exit status: OK — the program returned $RC, as this check expects."
	exit 0
fi

# A SURVIVE CASE compares no output: a crash, a timeout and a runaway are its
# three failures, read from how the run ended like every other verdict here.
# What it printed is shown only when it failed, as the other stream always is.
if [ "$SURVIVE" -eq 1 ]; then
	if [ "$ENDED" != returned ]; then
		explain_ending
		echo "        This case compares no output: what the subject leaves open"
		echo "        here is what to print, and every reading of it agrees that the"
		echo "        program ends by itself, in time. Not ending that way is a"
		echo "        failure whatever it printed."
		# What it wrote, each stream cut the way every excerpt here is
		# (rl_excerpt: it says what it left out, and keeps the whole text).
		_sv_other=stderr
		[ "$STREAM" != stderr ] || _sv_other=stdout
		if [ -s "$ACTUAL" ]; then
			echo " ----- it wrote to $STREAM -----"
			rl_excerpt "$ACTUAL" 10 "survive-$STREAM.txt" "   "
		fi
		if [ -s "$OTHER" ]; then
			echo " ----- it wrote to $_sv_other -----"
			rl_excerpt "$OTHER" 10 "survive-$_sv_other.txt" "   "
		fi
		# There is no table for a row to name, so every row fires, capped as
		# everywhere (rl_clues with no failed cases, as header_check.sh shows
		# a compile error's) -- unless this test is a named program case:
		# then its own rows and the ones keyed to nothing.
		if [ -n "$CASE_NAME" ]; then
			printf '%s\n' "$CASE_NAME" > "$FAILED_F"
			rl_clues "$CLUES_FILE" "$FAILED_F" "" "$CASE_NAME"
		else
			rl_clues "$CLUES_FILE"
		fi
		exit 1
	fi
	echo " SURVIVED: the program ended by itself, with exit status $RC."
	echo "           This case compares no output -- the subject leaves open"
	echo "           what to print here -- only that the run ends, killed by no"
	echo "           signal, in time, without runaway output."
	if [ -n "$EXPECT_EXIT" ] && [ "$RC" != "$EXPECT_EXIT" ]; then
		echo " --------------------------------------------------"
		echo " EXIT STATUS: FAIL — the program returned $RC; this case expects $EXPECT_EXIT."
		explain_exit_source
		show_other
		exit 1
	fi
	if [ -n "$NOTE_EXIT" ] && [ -z "$EXPECT_EXIT" ] && [ "$RC" != "$NOTE_EXIT" ]; then
		echo " note: the subject names no exit status, so this layer does not fail"
		echo "       on $RC; the robust exit-status check expects $NOTE_EXIT."
	fi
	exit 0
fi

if [ "$SANITIZE" -eq 1 ]; then
	# The address column of a hex dump cannot be compared literally: ASLR moves
	# the stack on every run, so the SAME CORRECT program prints a different
	# number each time. This step used to rewrite the column to sixteen zeros,
	# which threw away everything about it except its width — and then a program
	# that never touched the pointer at all was byte-perfect green. Three
	# implementations were built against c-02 ex12's real harness to confirm it:
	# one printing the same address on every row, one printing sixteen literal
	# zeros with no pointer arithmetic anywhere, and one printing the right value
	# in UPPERCASE hex; all three passed. The committed fixture even DISPLAYED
	# the zeros, so it documented the second of those as the expected answer.
	#
	# THE HARNESS PUBLISHES THE ADDRESS. Only the program knows where its memory
	# is, and the harness's own test program is that program: before each dump
	# it writes the address it is about to pass, as a line of its own,
	#     @addr <16 lowercase hex digits>
	# (c-02 ex12's test_print_memory.c). This step reads each such marker and
	# TAKES IT OUT of the output -- with its newline, so what is compared is
	# exactly what the function wrote, and a row missing its own newline still
	# runs into whatever followed it. The marker opens a block pinned to that
	# address: its k-th address row must print the marker's address plus 16k,
	# literally. A row that does is rewritten to its offset, 16k, which is what
	# the fixture holds; a row that does not keeps the value it printed, marked
	# "(not the address the test passed)", and can never match (finding 048).
	# So a 32-bit truncation, the block's address on every row, or row_index * 16
	# in a 16-digit field is red now, where it used to pass.
	#
	# Compared, then, in a pinned block:
	#   WIDTH — only an exactly-16-hex-digit field followed by ':' is an address
	#           row at all, so a narrower or wider column keeps its raw text and
	#           can never match a fixture.
	#   CASE  — "(UPPERCASE)" is appended when the field contains A-F: the
	#           harness publishes lowercase, as the subject's example prints.
	#   VALUE — the published address plus 16 per row, which is the STEP too.
	#
	# WITHOUT A MARKER (a fixture that publishes nothing) the value is unknowable
	# from out here, and the old rule applies: each address is rewritten to its
	# offset from the first row of its block, a new block starting wherever an
	# address is not the previous one plus 16, or wherever a non-address line
	# interrupts the dump. That compares the width, the case and the +16 step,
	# never the value, and two separate buffers that happen to sit 16 bytes apart
	# would merge. c-02 ex12 is this runner's only --sanitize user and publishes
	# every address, so it never takes that path; it stays for a fixture that
	# cannot publish, and the NOTE above the table says which rule was applied.
	# //tools:conventions refuses a c_function(sanitize = True) whose harness
	# writes no "@addr", so a new one cannot land on it unnoticed.
	#
	# The ilp32 layer replays this same fixture from a zig -m32 build: there a
	# pointer is 32 bits, the harness publishes it zero-extended to sixteen
	# digits, and a correct dump prints it the same way.
	#
	# awk, not sed, because none of this is expressible without state; and awk's
	# `print` always terminates its line, so a program whose output does NOT end
	# in a newline would silently gain one here and the byte-exact guard further
	# down — which exists to catch exactly that — would stop seeing it. So probe
	# the last byte first and hand the answer to awk, whose END rule puts the file
	# back the way it came in.
	#
	# The probe pipes through `tr -d` rather than relying on `$(...)`: command
	# substitution strips trailing NEWLINES, which is the test we want, but the
	# shell also drops NUL bytes from the result, so output ending in a literal
	# NUL read as "ends in a newline" and gained one. `tr -d '\n' | wc -c` is 0
	# only for a real newline. Student output that ends in a NUL is far-fetched,
	# but the old sed preserved it exactly and this step must not quietly differ.
	EOL=1
	LASTB=$(tail -c 1 "$ACTUAL" | tr -d '\n' | wc -c)
	[ -s "$ACTUAL" ] && [ "$LASTB" -ne 0 ] && EOL=0
	rm -f "$ACTUAL.pinned"
	awk -v eol="$EOL" -v pinfile="$ACTUAL.pinned" '
	function ishex16(s,   i) {
		if (length(s) != 16) return 0
		for (i = 1; i <= 16; i++)
			if (index("0123456789abcdef", tolower(substr(s, i, 1))) == 0)
				return 0
		return 1
	}
	# s + 0x10, one digit at a time on the STRING. awk has no integer type, and a
	# 16-hex-digit address does not survive a pass through a double.
	function plus16(s,   i, d, out) {
		out = s
		i = 15
		while (i >= 1) {
			d = index("0123456789abcdef", substr(out, i, 1))
			out = substr(out, 1, i - 1) substr("0123456789abcdef", d % 16 + 1, 1) \
				substr(out, i + 1)
			if (d < 16) return out
			i--
		}
		return out
	}
	# One line of lookahead, so END can decide how to terminate the last one.
	function emit(s) { if (has) printf "%s\n", held; held = s; has = 1 }
	# A marker opens its block: the next address row must be this address.
	function pin(a) { want = a; pinned = 1; off = 0; pend = "" }
	{
		# What the program wrote before a marker, on the marker line itself,
		# carries on into the next line, as it did before the marker cut in --
		# and still belongs to the block before it: the new block opens once
		# that line is read.
		line = carry $0
		carry = ""
		n = length(line)
		if (n >= 22 && substr(line, n - 21, 6) == "@addr " && ishex16(substr(line, n - 15)) \
			&& substr(line, n - 15) == tolower(substr(line, n - 15))) {
			carry = substr(line, 1, n - 22)
			if (!told) { printf "" > pinfile; told = 1 }
			if (carry == "") pin(substr(line, n - 15))
			else pend = substr(line, n - 15)
			next
		}
		field = substr(line, 1, 16)
		isaddr = (substr(line, 17, 1) == ":" && ishex16(field))
		if (pinned && isaddr) {
			low = tolower(field)
			mark = (field ~ /[A-F]/) ? "(UPPERCASE)" : ""
			if (low == want)
				emit(sprintf("%016x%s:%s", off, mark, substr(line, 18)))
			else
				emit(field "(not the address the test passed):" substr(line, 18))
			want = plus16(want)
			off += 16
		} else if (isaddr) {
			low = tolower(field)
			if (open && low == wantu)
				offu += 16
			else
				offu = 0
			wantu = plus16(low)
			open = 1
			mark = (field ~ /[A-F]/) ? "(UPPERCASE)" : ""
			emit(sprintf("%016x%s:%s", offu, mark, substr(line, 18)))
		} else {
			open = 0
			emit(line)
		}
		if (pend != "") pin(pend)
	}
	END {
		# A marker with text of the program before it, and nothing after: that
		# text ended the output, without a newline of its own.
		if (carry != "") {
			if (has) printf "%s\n", held
			printf "%s", carry
		} else if (has) printf "%s%s", held, (eol ? "\n" : "")
	}
	' "$ACTUAL" > "$ACTUAL.s" && mv "$ACTUAL.s" "$ACTUAL"
fi

# ANY OF SEVERAL OUTPUTS (--expected-alt): where the subject leaves the
# reading open and bounds it, the output passes when it is exactly one of
# them. The table compares it with the one it is, or with the first when it
# is none, and says so above the table, with every output it would take.
if [ -n "$ALTS" ]; then
	MATCHED=""
	while IFS= read -r _e; do
		[ -n "$_e" ] || continue
		if cmp -s "$_e" "$ACTUAL"; then
			MATCHED=$_e
			break
		fi
	done <<ALT_EOF
$EXPECTED$ALTS
ALT_EOF
	echo " THIS CASE TAKES ANY OF these outputs, one per reading of a sentence the"
	echo " subject leaves open:"
	while IFS= read -r _e; do
		[ -n "$_e" ] && echo "   * ${_e##*/}"
	done <<ALT_EOF
$EXPECTED$ALTS
ALT_EOF
	if [ -n "$MATCHED" ]; then
		echo " Yours is ${MATCHED##*/}; the table compares it with that one."
		EXPECTED=$MATCHED
	else
		echo " Yours is none of them; the table compares it with ${EXPECTED##*/}."
	fi
fi

# A student who did not write this runner has no way to know their address column
# was rewritten before the comparison, and the table would otherwise show them an
# EXPECTED value ("0000000000000010") that no correct program ever prints. Left
# unexplained that is worse than unhelpful: the obvious way to make the table go
# green is to print the numbers it is showing you, which is precisely the wrong
# answer. So say what was rewritten AND say not to chase it, above the table, in
# the terms the exercise is about.
if [ "$SANITIZE" -eq 1 ] && [ -f "$ACTUAL.pinned" ]; then
	rm -f "$ACTUAL.pinned"
	echo " NOTE: the OS randomises where your memory lives (ASLR), so the address"
	echo "       column cannot be written into a fixture, and neither column below"
	echo "       shows the real value. The test tells this check the address it"
	echo "       passes you before each dump, and every row's address is compared"
	echo "       with it: the first row's must be that address, each next row's 16"
	echo "       more. A row whose address is right is shown as its distance from"
	echo "       the first row, in 16 hex digits, so a correct dump reads"
	echo "       0000000000000000 / ...0010 / ...0020, restarting at zero for each"
	echo "       buffer. A wrong one keeps the value you printed, marked '(not the"
	echo "       address the test passed)'; A-F in it is marked '(UPPERCASE)'. So do"
	echo "       NOT print the numbers you see here: print the real address of each"
	echo "       line's first byte, as the subject asks."
elif [ "$SANITIZE" -eq 1 ]; then
	echo " NOTE: the OS randomises where your memory lives (ASLR), so the address"
	echo "       column below is NOT compared literally — neither column shows the"
	echo "       real value. Both are normalised: every address is replaced by its"
	echo "       distance, in 16 hex digits, from the first row of its block, and a"
	echo "       new block starts wherever an address is not the previous one plus"
	echo "       16. A correct dump therefore reads 0000000000000000 / ...0010 /"
	echo "       ...0020 and restarts at zero for each buffer it is given. Compared:"
	echo "       the column's width, its letter case ('(UPPERCASE)' is appended when"
	echo "       it holds A-F) and the +16 step. Not compared: the address itself,"
	echo "       which this test does not publish — so do NOT print the numbers you"
	echo "       see here. Print the real address of each line's first byte, as the"
	echo "       subject asks."
fi

# ---------------------------------------------------------------------------
# THE FACTS THE VERDICT IS MADE OF, settled before anything is printed.
#
# Few processes, on purpose: every output test in the repo pays for each one,
# and on a loaded machine a fork costs milliseconds. The two sizes come from
# wc (the expected one is already known, from the budget above), the byte
# comparison from cmp, and everything else -- whether each file ends in a
# newline, whether the expected output is text at all -- from the one awk pass
# that renders the table, which reads both files anyway.

BYTES_SAME=0
cmp -s "$EXPECTED" "$ACTUAL" && BYTES_SAME=1
if [ "$BYTES_SAME" -eq 1 ]; then
	GOT_BYTES=$EXP_BYTES
else
	GOT_BYTES=$(wc -c < "$ACTUAL")
fi

EXIT_BAD=0
if [ -n "$EXPECT_EXIT" ] && [ "$ENDED" = returned ] && [ "$RC" != "$EXPECT_EXIT" ]; then
	EXIT_BAD=1
fi

# Labelled and sanitized output is text by construction: no binary test.
TEXTONLY=0
if [ "$LABELED" -eq 1 ] || [ "$SANITIZE" -eq 1 ]; then TEXTONLY=1; fi

# How the ending reads in RESULT, for the table and for the binary summary.
case "$ENDED" in
	"timeout") HOW="ran out of time" ;;
	runaway) HOW="was stopped for printing too much" ;;
	*) HOW="died" ;;
esac

# ---------------------------------------------------------------------------
# THE BINARY SUMMARY: sizes, then where the bytes first part, shown from just
# before that byte in the one rendering every runner uses (rl_diff_window),
# instead of rows.
render_binary() {
	_esz=$((EXP_BYTES))
	_gsz=$((GOT_BYTES))
	echo " BYTES: this case's expected output is a byte stream, not lines of text --"
	echo "        much of it is bytes a terminal cannot show -- so it is compared"
	echo "        byte for byte and summarised here instead of printed."
	printf '   expected  %s bytes\n' "$_esz"
	printf '   got       %s bytes\n' "$_gsz"
	if [ "$BYTES_SAME" -eq 1 ]; then
		BIN_RESULT="all $_esz bytes match"
		return
	fi
	# Past the end of one side means that side is a prefix of the other.
	_first=$(rl_first_diff "$EXPECTED" "$ACTUAL")
	if [ "$_gsz" -eq 0 ]; then
		BIN_RESULT="the program printed nothing; $_esz bytes were expected"
	elif [ "$_first" -gt "$_gsz" ]; then
		BIN_RESULT="the output stops after $_gsz of the $_esz bytes; those match"
	elif [ "$_first" -gt "$_esz" ]; then
		BIN_RESULT="all $_esz expected bytes match, then $((_gsz - _esz)) more follow"
	else
		BIN_RESULT="the bytes differ from byte $_first on"
	fi
	rl_diff_window "$EXPECTED" "$ACTUAL" "   "
}

# ---------------------------------------------------------------------------
# THE TABLE. EXPECTED is read first. It prints the table and the RESULT line,
# writes what it decided to $STATE for the hints, and exits with the whole
# verdict: 0 PASS, 1 FAIL -- or 3, having printed nothing, when the expected
# output turns out to be a byte stream, which render_binary then summarises.
render_table() {
	LC_ALL=C awk -v labeled="$LABELED" -v maxrows="$RL_ROWS" -v fullfile="$TMPD/table" \
		-v cellmax="${DIFF_CELL_MAX:-100}" -v ended="$ENDED" -v rc="$RC" \
		-v how="$HOW" -v fixture="$FIXTURE" \
		-v want_rc="$EXPECT_EXIT" -v exitbad="$EXIT_BAD" \
		-v bytesame="$BYTES_SAME" -v esize="$EXP_BYTES" -v gsize="$GOT_BYTES" \
		-v textonly="$TEXTONLY" -v escaped="$ESCAPED" \
		-v statefile="$STATE" "$RL_AWK_VIS"'
	function pad(s, w,   r) { r = s; while (length(r) < w) r = r " "; return r }
	# A CASE label is text a person reads (rl_vis_text: a control byte as
	# \xHH, the rest as written), and may hold a character of several
	# bytes: its column is as wide as its characters, the bytes 0x80-0xbf
	# that continue one counted with the byte they continue.
	function cols(s,   t) { t = s; gsub(/[\200-\277]/, "", t); return length(t) }
	function padc(s, w,   r, k) { r = s; for (k = cols(s); k < w; k++) r = r " "; return r }
	function dash(w,    r)  { r = ""; while (length(r) < w) r = r "-"; return r }
	# Word-wrapped to w columns, each line indented by one space.
	function wrap(t, w,   nw, words, k, line) {
		nw = split(t, words, " ")
		line = ""
		for (k = 1; k <= nw; k++) {
			if (line != "" && length(line) + 1 + length(words[k]) > w) {
				print " " line
				line = words[k]
			} else line = (line == "") ? words[k] : line " " words[k]
		}
		if (line != "") print " " line
	}
	function firstdiff(a, b,   i, n) {
		n = (length(a) < length(b)) ? length(a) : length(b)
		for (i = 1; i <= n; i++) if (substr(a, i, 1) != substr(b, i, 1)) return i
		return n + 1
	}
	# At most cellmax bytes of s from start, escaped, with "..." where text was
	# cut. Escaping only the window keeps a 34 KB line (c-00 ex06) cheap. A
	# value the test program wrote in the notation (--escaped-values) is
	# rendered by rl_vis_noted, and its window is widened to whole marks, so a
	# cut never leaves half of a "\x00" or a lone backslash at an edge.
	# CLIP is set when this call cut something, for the legend.
	function window(s, start, w,   r, n, i, k, ts, te) {
		n = length(s)
		if (escaped == "1" && (start > 1 || start + w - 1 < n)) {
			ts = 1; te = n
			for (i = 1; i <= n; i = k) {
				k = i + ((substr(s, i, 1) != "\\") ? 1 : (substr(s, i + 1, 1) == "x" ? 4 : 2))
				if (i <= start) ts = i
				if (k - 1 >= start + w - 1) { te = k - 1; break }
			}
			start = ts; w = te - ts + 1
		}
		r = (escaped == "1") ? rl_vis_noted(substr(s, start, w)) : rl_vis_exact(substr(s, start, w))
		CLIP = 0
		if (start > 1) { r = "..." r; CLIP = 1 }
		if (start + w - 1 < n) { r = r "..."; CLIP = 1 }
		return r
	}
	# By name, not FNR == NR: with an EMPTY expected file that test is true
	# for the second file too, and the output was read as the expectation.
	# The line lengths of each file are summed as it is read: a file ends in a
	# newline exactly when its size is those lengths plus one byte per line
	# (awk drops the separator, and counts an unterminated last line as a
	# line), which spares a tail|tr|wc per file. The bytes a terminal cannot
	# show are counted on the expected side for the binary test below.
	FILENAME == ARGV[1] {
		want[FNR] = $0; ne = FNR; elen += length($0)
		if (textonly != "1") { t = $0; odd += gsub(/[^\t\r -~]/, "", t) }
		next
	}
	# A runaway can print millions of lines; past this many beyond the
	# expected ones they are only counted, since no table shows them.
	FNR > ne + 1000 { gmore++; next }
	{ got[FNR] = $0; ng = FNR; glen += length($0) }
	END {
		# A BYTE STREAM, not lines of text: at least 30% of the expected bytes
		# outside printable ASCII, tab, CR and LF. Rows of it are noise at
		# best -- the 20 KB blobs of C 10 used to fill the terminal with raw
		# control bytes and invalid UTF-8 -- and "line 1" of a binary file
		# means nothing. A NUL alone does not make a stream binary: C 00
		# ex00 and the stdin case of C 10 ex01 each hold one inside
		# lines of text, where a row showing \x00 says more than a hex window.
		# Decided on the EXPECTED file, which says what kind of output the
		# case is about; labelled and sanitized output is text by
		# construction.
		if (textonly != "1" && esize > 0 && odd * 10 >= esize * 3) exit 3
		e_nl = (esize > 0 && elen + ne == esize) ? "1" : "0"
		g_nl = (gsize > 0 && gmore == 0 && glen + ng == gsize) ? "1" : "0"
		died = (ended != "returned")
		# THE CASE THAT WAS RUNNING -- only for the test programs the harness
		# wrote, whose output is unbuffered and one row per case
		# (--harness-fixture, checked against the binary before it ran). There every complete line is a
		# case that finished; an unterminated last line is the one cut off
		# mid-way, and otherwise it is the first line never printed. Past the
		# last expected line nothing was running that this table knows about.
		# A program the student wrote may buffer its output, and a crash then
		# takes printed lines with it: nothing is marked there.
		run = 0
		if (died && fixture == "1") {
			run = (ng > 0 && g_nl == "0") ? ng : ng + 1
			# ...unless that unterminated line is the whole last expected
			# line, which ends without a newline too: then every case finished.
			if (run == ng && ng == ne && e_nl == "0" && (want[ne] "") == (got[ng] "")) run = ne + 1
			if (run > ne) run = 0
		}
		n = (ne > ng) ? ne : ng
		hC = "CASE"; hE = "EXPECTED"; hG = "GOT"
		wC = length(hC); wE = length(hE); wG = length(hG)
		fails = 0; passes = 0; pfails = 0
		for (i = 1; i <= n; i++) {
			ehas = (i <= ne); ghas = (i <= ng)
			eline = ehas ? want[i] : ""; gline = ghas ? got[i] : ""
			eval = eline; gval = gline; cse = "line " i; ecase = ""; gcase = ""
			if (labeled == "1") {
				p = index(eline, "\t")
				if (p > 0) { ecase = substr(eline, 1, p - 1); eval = substr(eline, p + 1) }
				q = index(gline, "\t")
				if (q > 0) { gcase = substr(gline, 1, q - 1); gval = substr(gline, q + 1) }
				if (ehas && ecase != "")      cse = ecase
				else if (ghas && gcase != "") cse = gcase
			}
			if (run && i > run)       st = "skip"
			else if (run && i == run) st = "run"
			# Concatenating "" makes both sides strings: awk compares two
			# fields that look numeric AS NUMBERS otherwise, and "042"
			# matched "42".
			else if (ehas && ghas && (eline "") == (gline "")) st = "pass"
			else st = "fail"
			if (st == "pass" || st == "skip") {
				# A passing row through the one renderer too: printed raw, a
				# byte a terminal acts on (an escape sequence, a carriage
				# return) reached it from the output of the program, and a
				# character of several bytes put the row out of line with
				# the others. A long one is cut at its end.
				E[i] = window(eval, 1, cellmax)
				if (CLIP) PCL[i] = 1
				if (st == "pass") {
					G[i] = window(gval, 1, cellmax); passes++
					if (CLIP) PCL[i] = 1
				} else G[i] = "(not run)"
			} else {
				# A row being read: its bytes, where it ends, and -- when it
				# is long -- the window around its first difference. A label
				# that differs is part of what is wrong, so the GOT cell then
				# shows the whole line.
				ev = eval
				gv = (labeled == "1" && ehas && ghas && gcase != ecase) ? gline : gval
				start = 1
				if (length(ev) > cellmax || length(gv) > cellmax) {
					start = firstdiff(ev, gv) - int(cellmax / 4)
					if (start < 1) start = 1
				}
				# The $ goes where the line ended, so a line that did not end
				# -- the last one, with no final newline -- gets none, and the
				# legend mentions $ only when some cell shows one.
				eend = (i < ne || e_nl == "1"); gend = (i < ng || g_nl == "1")
				E[i] = ehas ? window(ev, start, cellmax) (eend ? "$" : "") : "(no line)"
				if (ehas && CLIP) CL[i] = 1
				G[i] = ghas ? window(gv, start, cellmax) (gend ? "$" : "") : "(no line)"
				if (ghas && CLIP) CL[i] = 1
				if ((ehas && eend) || (ghas && gend)) DL[i] = 1
				# The running case printed its label and was cut off before
				# anything else: say so rather than show an empty cell.
				if (st == "run" && ghas && G[i] == "") G[i] = "(nothing yet)"
				if (st == "fail") { fails++; if (ghas) pfails++ }
			}
			C[i] = cse; CD[i] = rl_vis_text(cse); S[i] = st
			if (cols(CD[i]) > wC)  wC = cols(CD[i])
			if (length(E[i]) > wE) wE = length(E[i])
			if (length(G[i]) > wG) wG = length(G[i])
		}
		# An expected output of nothing, and nothing printed, is one honest
		# row -- not an empty table over "PASS (0/0 passed)", which read as a
		# layer that checked nothing.
		if (n == 0) {
			n = 1; C[1] = "the whole output"; CD[1] = C[1]; E[1] = "(nothing)"; G[1] = "(nothing)"
			S[1] = "pass"; empty = 1
			wC = length(C[1]); if (wE < 9) wE = 9; if (wG < 9) wG = 9
		}

		# ROW CAP. A case can have thousands of lines (c-10 ex02 `ccarry`
		# rendered 1092 rows into the log), and the first failing one already
		# says what the rest repeat. The case that was running is always
		# shown, then failing rows, then passing ones, then the rows never
		# reached, until DIFF_MAX_ROWS -- and whatever is shown is printed in
		# the order of the fixture, with a marker where rows were left out, so
		# the table still reads as the output does.
		if (maxrows > 0 && n > maxrows) {
			nsel = 0
			if (run) { sel[run] = 1; nsel++ }
			split("fail pass skip", order, " ")
			for (k = 1; k <= 3; k++)
				for (i = 1; i <= n && nsel < maxrows; i++)
					if (!(i in sel) && S[i] == order[k]) { sel[i] = 1; nsel++ }
		} else {
			for (i = 1; i <= n; i++) sel[i] = 1
		}

		printf " %s | %s | %s | %s\n", pad(hC, wC), pad(hE, wE), pad(hG, wG), "STATUS"
		printf " %s-+-%s-+-%s-+-%s\n", dash(wC), dash(wE), dash(wG), dash(6)
		# EVERY ROW, to a file, when some are left out here: the shell keeps
		# it in test.outputs (rl_save), so the rows the cap hides are one
		# file away rather than nowhere.
		if (maxrows > 0 && n > maxrows) {
			printf " %s | %s | %s | %s\n", pad(hC, wC), pad(hE, wE), pad(hG, wG), "STATUS" > fullfile
			for (i = 1; i <= n; i++) {
				if (S[i] == "pass")      st = "PASS"
				else if (S[i] == "fail") st = "FAIL <"
				else if (S[i] == "skip") st = "not reached"
				else st = "FAIL < running when it ended"
				printf " %s | %s | %s | %s\n", padc(CD[i], wC), pad(E[i], wE), pad(G[i], wG), st > fullfile
			}
			close(fullfile)
		}
		gap = 0; hidden = 0; hidf = 0
		for (i = 1; i <= n; i++) {
			if (!(i in sel)) {
				gap++; hidden++
				if (S[i] == "fail") hidf++
				continue
			}
			if (gap) {
				printf " %s | %s | %s | (%d row%s not shown)\n", pad("...", wC), \
					pad("", wE), pad("", wG), gap, (gap == 1 ? "" : "s")
				gap = 0
			}
			if (S[i] == "pass")      st = "PASS"
			else if (S[i] == "fail") st = "FAIL <"
			else if (S[i] == "skip") st = "not reached"
			else st = "FAIL < running when " (ended == "timeout" ? "time ran out" \
				: (ended == "runaway" ? "its output was cut off" : "the program died"))
			printf " %s | %s | %s | %s\n", padc(CD[i], wC), pad(E[i], wE), pad(G[i], wG), st
		}
		if (gap)
			printf " %s | %s | %s | (%d row%s not shown)\n", pad("...", wC), \
				pad("", wE), pad("", wG), gap, (gap == 1 ? "" : "s")
		if (hidden)
			printf " %d row(s) not shown in all (%d of them failing).  Raise with --test_env=DIFF_MAX_ROWS=N (0 shows every row).\n", \
				hidden, hidf
		if (gmore)
			printf " ... and %d more line(s) after these, not compared one by one.\n", gmore
		printf " %s-+-%s-+-%s-+-%s\n", dash(wC), dash(wE), dash(wG), dash(6)
		# THE LEGEND names only the marks some failing cell that is SHOWN
		# holds: read off the printed cells, after the row cap chose them, so
		# a mark only a hidden row held is not named (runner_lib.sh, THE
		# LEGEND).
		nmarks = 0; dollar = 0; clipped = 0; pclipped = 0
		rl_vis_reset()
		for (i = 1; i <= n; i++) {
			if (!(i in sel)) continue
			rl_vis_scan(E[i]); rl_vis_scan(G[i])
			if (i in PCL) pclipped = 1
			if (S[i] == "pass" || S[i] == "skip") continue
			if (i in DL) dollar = 1
			if (i in CL) clipped = 1
		}
		if (dollar)  mk[++nmarks] = "$ is where a line ended"
		nmarks = rl_vis_marks(mk, nmarks)
		if (clipped) mk[++nmarks] = "... text cut to fit around the first difference"
		if (pclipped) mk[++nmarks] = "... where the rest of a passing value is left out"
		if (nmarks) {
			legend = "In the table, " mk[1]
			for (k = 2; k <= nmarks; k++) legend = legend ((k == nmarks) ? ", and " : ", ") mk[k]
			wrap(legend ".", 76)
		}

		# THE VERDICT, from everything at once.
		if (run == 1) {
			res = sprintf("FAIL  (the program %s in \"%s\", the first case; %d not reached)", \
				how, CD[run], n - run)
		} else if (run) {
			res = sprintf("FAIL  (the program %s in \"%s\": %d/%d passed before it, %d not reached)", \
				how, CD[run], passes, run - 1, n - run)
		} else if (ended == "runaway") {
			# Its output is whatever filled the budget: count what matched of
			# the lines that were expected, not the thousands that were not.
			res = sprintf("FAIL  (the program %s; %d of the %d expected line%s matched before it)", \
				how, passes, ne, (ne == 1 ? "" : "s"))
		} else if (died && fixture != "1" && ng < ne) {
			# Only what reached the output is known: a buffered program loses
			# what was still in its buffer, so this says how many lines
			# arrived, never which case the program stopped in.
			res = sprintf("FAIL  (the program %s with %d of %d line%s in its output", \
				how, ng, ne, (ne == 1 ? "" : "s"))
			if (pfails) res = res sprintf(", %d of them wrong", pfails)
			res = res ")"
		} else if (fails) {
			res = sprintf("FAIL  (%d/%d passed, %d failed)", passes, n, fails)
			if (died) res = res "; then the program " how
		} else if (died) {
			res = "FAIL  (output right; then the program " how ")"
		} else if (bytesame != "1") {
			res = "FAIL  (lines match, bytes differ)"
		} else if (exitbad == "1") {
			res = sprintf("FAIL  (output right; exited %d, this case expects %d)", rc, want_rc)
		} else if (empty) {
			res = "PASS  (the program printed nothing, as expected)"
		} else {
			res = sprintf("PASS  (%d/%d passed)", n, n)
		}
		if (exitbad == "1" && (fails || bytesame != "1") && !died)
			res = res sprintf("; and exited %d, this case expects %d", rc, want_rc)
		print " RESULT: " res
		verdict = (substr(res, 1, 4) == "FAIL")

		# THE BYTES, when every line matched and they still differ. Compared
		# as strings line by line, only the final newline can be left, and the
		# report says so only when that is what the probe found.
		if (verdict && !fails && !run && !died && bytesame != "1") {
			print " --------------------------------------------------"
			print " BYTES: every line matches, but the bytes do not."
			if (ne == ng && e_nl != g_nl) {
				print "        The only difference is the final newline:"
				if (e_nl == "1")
					print "        the expected output ends with one, and this output does not."
				else
					print "        this output ends with one, and the expected output does not."
				print "        Its last line, $ where a line ended (a literal $ reads \\x24):"
				print "          expected: " rl_vis_exact(want[ne]) (e_nl == "1" ? "$" : "")
				print "          got:      " rl_vis_exact(got[ng]) (g_nl == "1" ? "$" : "")
			} else {
				print "        compare the two byte for byte (cmp names the first difference)."
			}
			print "        The grader compares bytes, so this is a failure."
		}

		# For the hints: which case was running, which rows failed, and
		# whether any case is to blame at all -- and, for the footer, whether
		# a program that may buffer stopped short of the expected lines.
		if (died && fixture != "1" && ng < ne) print "short\t" (ng + 0) > statefile
		if (run) print "run\t" C[run] > statefile
		for (i = 1; i <= n; i++) if (S[i] == "fail") print "fail\t" C[i] > statefile
		print "mode\t" ((fails || run) ? "rows" : (verdict ? "catchall" : "none")) > statefile
		close(statefile)
		exit verdict
	}
	' "$EXPECTED" "$ACTUAL"
}

# ---------------------------------------------------------------------------
# THE HINTS, chosen from what the table decided, by the one clues.tsv rule
# every runner shares (rl_clues, tools/runner_lib.sh): a row keyed to the case
# that was running comes first; when no case failed (the bytes, the exit status
# or the ending did), only the rows keyed to no case apply. A program case
# (--case) has failed whatever did: its name is always among the failed.
show_hints() {
	_mode=none; _run=""
	: > "$FAILED_F"
	[ -z "$CASE_NAME" ] || printf '%s\n' "$CASE_NAME" > "$FAILED_F"
	while IFS="$TAB" read -r _k _v; do
		case "$_k" in
			run) _run=$_v; printf '%s\n' "$_v" >> "$FAILED_F" ;;
			fail) printf '%s\n' "$_v" >> "$FAILED_F" ;;
			mode) _mode=$_v ;;
		esac
	done < "$STATE"
	case "$_mode" in
		# Only the rows keyed to no case -- and to this program case, which
		# is what failed: no table row is to blame.
		catchall)
			: > "$FAILED_F"
			[ -z "$CASE_NAME" ] || printf '%s\n' "$CASE_NAME" > "$FAILED_F"
			rl_clues "$CLUES_FILE" "$FAILED_F" "" "$CASE_NAME" ;;
		rows) rl_clues "$CLUES_FILE" "$FAILED_F" "$_run" "$CASE_NAME" ;;
	esac
}

# ---------------------------------------------------------------------------
# THE REPORT: what was compared, then why it failed, then the hints, then the
# other stream.
BINARY=0
render_table
DRC=$?
# The rows the cap left out, kept whole (render_table wrote them only then).
if [ -s "$TMPD/table" ] && rl_save "$TMPD/table" output-table.txt; then
	echo " every row of the table: $RL_SAVED"
fi
# 0 and 1 are a verdict and 3 a byte stream to summarise instead; anything
# else is awk failing, which checked nothing.
case "$DRC" in
	0 | 1) ;;
	3) BINARY=1 ;;
	*)
		echo "diff_output.sh: the table renderer failed (awk exit $DRC)" >&2
		exit 2 ;;
esac
if [ "$BINARY" -eq 1 ]; then
	BIN_RESULT=""
	render_binary
	DRC=0
	if [ "$BYTES_SAME" -eq 1 ] && [ "$ENDED" = returned ] && [ "$EXIT_BAD" -eq 0 ]; then
		echo " RESULT: PASS  ($BIN_RESULT)"
	else
		DRC=1
		if [ "$ENDED" != returned ]; then
			echo " RESULT: FAIL  ($BIN_RESULT; the program $HOW)"
		elif [ "$BYTES_SAME" -eq 0 ]; then
			_tail=""
			[ "$EXIT_BAD" -eq 1 ] && _tail="; and exited $RC, this case expects $EXPECT_EXIT"
			echo " RESULT: FAIL  ($BIN_RESULT$_tail)"
		else
			echo " RESULT: FAIL  (output right; exited $RC, this case expects $EXPECT_EXIT)"
		fi
	fi
	# No row to key a hint to: the ones keyed to no case are what applies.
	if [ "$DRC" -eq 1 ]; then _m=catchall; else _m=none; fi
	printf 'mode\t%s\n' "$_m" > "$STATE"
fi

# What the table decided that the footer needs, read without a process.
MARKED=0; SHORT=""; _nfail=0
while IFS="$TAB" read -r _k _v; do
	case "$_k" in
		run) MARKED=1 ;;
		short) SHORT=$_v ;;
		fail) _nfail=$((_nfail + 1)) ;;
	esac
done < "$STATE"
# Where a row is marked as the one running, the rows above it are real
# results, and a FAIL among them is a verdict (explain_ending). Without the
# mark, a row may be (no line) only because a buffer was lost: no verdict.
[ "$MARKED" -eq 0 ] || RL_WRONG=$_nfail

if [ "$ENDED" != returned ]; then
	explain_ending
	case "$ENDED" in
		"timeout") _i="          " ;;
		runaway) _i="                 " ;;
		*) _i="        " ;;
	esac
	# Where a row is marked, --harness-fixture's premise was checked against the
	# binary before it ran, so the footer can say what the rows mean.
	if [ "$MARKED" -eq 1 ]; then
		echo "${_i}This is one of the harness's own test programs, which prints each"
		echo "${_i}case as it runs: the rows above the marked one are real results,"
		echo "${_i}the marked one is the case that was running, and the rows after"
		echo "${_i}it were never printed."
	elif [ -n "$SHORT" ]; then
		echo "${_i}Only what reached the output is shown. A program whose output is"
		echo "${_i}buffered -- printf's is, when it goes to a file -- loses what is"
		echo "${_i}still in the buffer when it is stopped, so a row reading (no line)"
		echo "${_i}is not necessarily one it never reached."
	fi
elif [ "$EXIT_BAD" -eq 1 ]; then
	echo " --------------------------------------------------"
	echo " EXIT STATUS: the program returned $RC; this case expects $EXPECT_EXIT."
	explain_exit_source
elif [ -n "$NOTE_EXIT" ] && [ -z "$EXPECT_EXIT" ] && [ "$RC" != "$NOTE_EXIT" ]; then
	echo " --------------------------------------------------"
	echo " note: the program returned exit status $RC. The subject names no exit"
	echo "       status, so this layer does not fail on it; the robust exit-status"
	if [ "$NOTE_EXIT" = 0 ]; then
		echo "       check does, because a program that did its job conventionally"
		echo "       returns 0 from main."
	else
		echo "       check does: it expects $NOTE_EXIT here, by this repo's rule, not the subject's."
	fi
	# Which target that is, when Bazel says which one this is: c_program names
	# a case's robust twin exactly as its output test, with _exit for _output.
	case "${TEST_TARGET:-}" in
		*_output) echo "       That check is ${TEST_TARGET%_output}_exit." ;;
	esac
fi

if [ "$DRC" -ne 0 ]; then
	[ -n "$CLUES_FILE" ] && show_hints
	show_other
elif [ -s "$OTHER" ]; then
	# A PASS that also wrote to the other stream: not compared by this case,
	# never graded (docs/reference.md, "Run contract"), and said all the same.
	# A debug line on stderr was green and in no log at all (finding 156),
	# while it is on the screen of anyone who runs the program.
	echo " --------------------------------------------------"
	echo " note: also written to $([ "$STREAM" = "stderr" ] && echo stdout || echo stderr) (not compared by this case):"
	rl_excerpt "$OTHER" 5 other-stream.txt "   | "
fi
exit "$DRC"
