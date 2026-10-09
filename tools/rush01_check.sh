#!/bin/sh
# rush01_check.sh — VALIDATE the rush01 grid instead of byte-comparing it.
#
# Why this layer exists at all, and why it is not diff_output.sh
# --------------------------------------------------------------
# Rush01 asks for a 4x4 grid of heights 1..4 where every row and every column
# holds each height exactly once, and the 16 visibility clues are all satisfied.
# The subject then says to display "the first solution you encounter".
#
# All 576 4x4 Latin squares were enumerated for this repo and grouped by how many
# of them a clue vector admits:
#     1 solution : 372 vectors        4 solutions:  28 vectors
#     2 solutions:  34 vectors        6 solutions:   4 vectors
#     438 clue vectors are solvable at all; the other 4294966858 well-formed
#     16-digit inputs (4^16 total) have no solution and must print Error.
#
# For the 66 vectors with more than one solution, WHICH grid is correct depends
# on the order the student's program happens to walk the board in. A fixture with
# one expected grid in it would therefore fail programs that are perfectly
# correct — the repo would be grading a search order the subject never fixed.
#
# So this layer does not compare bytes against one blessed answer. It VALIDATES:
#   * the input has NO solution  -> the program must print exactly "Error\n";
#   * the input HAS solutions    -> the printed grid must be one of them.
# Because the enumeration is exhaustive, membership in that list IS validity, and
# any grid outside it provably breaks one of the subject's own rules.
#
# And when it breaks one, this runner says WHICH — "row 2 holds the height 3
# twice", "column 3 is seen as 2 from the top, but clue 3 asks for 3" — in the
# subject's vocabulary. That is the whole value of this layer over a diff: a byte
# diff can only say "not the expected bytes", which for a puzzle is no help at
# all. It never says anything about HOW to search: naming a technique would be
# handing over the exercise (AGENTS.md §0). It only ever names the RULE that the
# printed grid broke, which is information the subject already gave the student.
#
# Consistency is checked both ways, and that makes this layer self-testing: a
# grid that satisfies every rule but is NOT in the corpus's list, or a grid in
# the list that fails a rule, means the corpus (or this checker) is wrong, not
# the student. That is reported as a HARNESS failure (exit 2), never as theirs.
#
# WHERE THE RULES LIVE
# --------------------
# Not in this file. Which rule a grid breaks — a height repeated in a row or a
# column, the view from each side counted against its clue — is the validity
# half of a rush01 solver. It used to be written out here in awk, shaped enough
# like C to port line for line, in a file every clone of this repo ships. It
# lives in //oracle now, in Rust written mostly with iterators rather than
# C-shaped loops (oracle/src/rush01_validate.rs, with the other references and
# the README that says what reading one costs), and this runner ASKS it, as
# `oracle rush01_validate`, one request per grid:
#
#     request  <W> <H><TAB><clues><TAB><cells>
#     reply    <faults><TAB><category><TAB><message><TAB><why>
#
# The categories and sentences in the reply are the ones this runner has always
# printed; the arm's self-check pins them. What stays here is the SHAPE of an
# answer — is a line a row, how many lines, is it Error — and the verdict
# wording around the reply, none of which says anything about the puzzle.
#
# The corpus's own grids are checked in ONE run of the reference, before the
# sweep. After that a grid the list names needs no second opinion, so the
# reference is asked per case only about a grid the list does NOT name: for a
# correct program that is never, and a sweep costs nothing extra.
#
# WITHOUT --oracle — a hand-written --corpus, as the fast selftest uses, because
# the reference needs a Rust build — there is nothing to ask. A grid is then
# judged by membership in the list alone (for an exhaustive list, the same
# question), the list's own grids are taken on trust, a wrong grid is reported
# as "not one of the listed grids" without naming a rule, and a list carrying
# witness lines ("?", see below) is refused, because a grid it does not name
# cannot be judged at all. Every Bazel target passes --oracle.
#
# Usage:
#   rush01_check.sh --bin PATH
#                   { --oracle PATH [--oracle-fn NAME] [--seed N] [--count N]
#                   | --corpus FILE }
#                   [--max-size N] [--max-cases N] [--probe-argc]
#                   [--probe-shape] [--probes-only]
#                   [--clues FILE [--case NAME]] [--label TEXT] [--timeout SECS]
#                   [--gate-differ F --gate-bin P --gate-expected F
#                    [--gate-arg STR | --gate-arg-file F]]
#                   (--stderr-empty | --stderr-ignored REASON
#                    | --sanitized | --valgrind PATH --valgrind-tools FILE
#                      [--sample N] [--rule FILE])
#   rush01_check.sh --bin PATH --probes-only --probe-shape|--probe-argc...
#                   --gate-arg STR | --gate-arg-file F   [as above]
#
#   --bin PATH          the student's compiled rush01
#   --oracle PATH       the Rust reference (//oracle:oracle); asked for the
#                       corpus as `oracle <fn> <seed> <count>`, and — with or
#                       without --corpus — for every rule verdict, as
#                       `oracle rush01_validate` (see WHERE THE RULES LIVE)
#   --oracle-fn NAME    reference function name (default rush01_solve)
#   --seed N            reference seed (default 1) — deterministic by construction
#   --count N           sizes the reference's random tail (default 400)
#   --corpus FILE       use this corpus file instead of running the reference
#                       to generate one (see WITHOUT --oracle for what is left
#                       when --oracle is not given as well)
#   --clues FILE        pedagogic hints (a clues.tsv), printed on failure --
#                       the same meaning as in every other runner here
#   --case NAME         the name this target's rows are keyed to in the
#                       program's one clues.tsv (its target's name after
#                       exNN_): only those rows and the ones keyed to nothing
#                       are shown, never the rows of the program's cases
#   --max-size N        REQUIRE grids up to N x N (default 4). Larger sizes are
#                       still run and still judged if answered with a grid; see
#                       "THE BONUS IS GRADED ONLY IF IT WAS ATTEMPTED" below.
#   --max-cases N       replay at most N corpus cases, spread evenly (0 = all)
#   --probe-argc        also assert the three argv SHAPES the corpus cannot
#                       express: no argument, two arguments, one empty argument.
#                       Each must print Error: "This is the only acceptable
#                       input", and not one of them is it. The two arguments are
#                       a clue string that is accepted ALONE (the --gate-arg
#                       vector, or the corpus's first solvable one), given
#                       twice, so a program that reads one of them and ignores
#                       the other prints a grid and is caught: with a string
#                       that is an error on its own, Error was right whatever
#                       the program did with argc (finding 153).
#   --probe-shape       also assert the malformed SHAPES of the one argument,
#                       each built from the --gate-arg vector (required): a
#                       leading space, a trailing space, a doubled space, a tab
#                       for a space, a '0' before a digit, a '+' before one.
#                       Each must print Error. That is a READING of "Each
#                       element of the string is a number ranging between '1'
#                       and '4'. This is the only acceptable input": a program
#                       that splits on runs of blanks, or reads each value as a
#                       number, reads the sentence another way. So it belongs
#                       in a strict target that says so (Rush 01's
#                       ex00_readings), never in the basic sweep. A tab cannot
#                       travel through Bazel's `args`, and none of these can be
#                       a corpus line (the corpus is TAB-separated and trims
#                       nothing it does not have to), so they are probes.
#   --probes-only       run the probes asked for and no corpus: no --oracle or
#                       --corpus is needed, --gate-arg is. For a target that
#                       holds a program to what the probes check and nothing
#                       else -- the corpus is another target's.
#   --label TEXT        what to call this run in messages
#   --quotes FILE       the subject's sentences the verdicts quote, one
#                       KEY<TAB>TEXT line each, written at the call site
#                       (tools/defs.bzl's runner_quotes): `error`, the sentence
#                       that fixes the error output. Required, except under a
#                       memory checker (tools/runner_lib.sh, "A SUBJECT'S
#                       SENTENCE COMES FROM THE CALL SITE")
#   --timeout SECS      per-run wall-clock budget (default 10, or RUSH01_TIMEOUT)
#   --show N            how many failing cases to print (default DIFF_MAX_ROWS,
#                       40; 0 prints all); every one is kept in test.outputs
#   --sanitized         BIN is the ASan/UBSan build: replay the cases judging
#                       memory and how each run ended, never the grid
#                       (ex00_sweep_diff_asan); --symbolizer PATH
#                       --symbolizer-lib FILE name each frame of a report's
#                       stack (runner_lib.sh, rl_sanitizers)
#   --valgrind PATH --valgrind-tools FILE [--sample N] [--rule FILE]
#                       a sample of the cases under memcheck, leaks included
#                       (ex00_sweep_valgrind). Both in tools/runner_lib.sh, "A
#                       CORPUS UNDER A MEMORY CHECKER"; the probes asked for
#                       (--probe-argc, --probe-shape) run in either, every one,
#                       from the list the plain replay judges (probe_list)
#
# Exit status: 0 everything validated, 1 the STUDENT's program is wrong,
#              2 the HARNESS is wrong (bad usage, unusable corpus, a corpus that
#              contradicts itself). Bazel reddens on both 1 and 2; the split is
#              for the human reading the log, so nobody spends an afternoon
#              debugging their solver because the reference is broken.
#              (tools/rust_diff.sh reports a broken reference as 1; this runner
#              follows the 0/1/2 split the newer runners use.)
#
# Env:
#   RUSH01_TIMEOUT     seconds per run (default 10)
#   DIFF_MAX_ROWS      the default of --show: against a fresh stub EVERY case
#                      fails, and a wall of 900 identical blocks buries the one
#                      thing the student needed to read (tools/runner_lib.sh,
#                      rl_rows -- one knob for every differential report)
#   RUSH01_MAX_TIMEOUTS  give up after this many runs fail to finish (default 3),
#                      counting both hangs and endless printing. A solver that
#                      does not terminate would otherwise burn cases x timeout
#                      seconds before Bazel killed the layer with nothing
#                      printed at all. Bonus-size runs that run out of time
#                      are counted apart (see THE BONUS below): after this many
#                      of THEM the remaining bonus-size cases are not tried,
#                      and the mandatory ones still are.
#   The whole sweep also stops, and says where, before this test's own time
#   limit (TEST_TIMEOUT, less a margin) would kill it: see runner_lib.sh.
#   NO_SKIP=1          force every gate open (see the gate below)
#
# STANDARD ERROR
# --------------
# A choice at every call, as every corpus runner's (tools/runner_lib.sh,
# rl_stderr_choice; tools/defs.bzl's _RUNNER_CHOICES refuses a call without
# it): --stderr-ignored REASON, and standard error is read, never judged --
# the verdict is on standard output, the stream the Run contract compares --
# or --stderr-empty, and a run whose answer
# is right but which also wrote to standard error fails (wrote-to-stderr).
# Either way it explains a verdict: an "Error" that went there instead of to
# standard output is named as such (error-on-stderr), and anything else it
# holds is shown beside the case. This runner decided it for its one subject
# and took no pair, so it was the one corpus runner whose call said nothing
# of standard error; the judge now reads the choice like the rest.
#
# THE ARGV THAT CONTAINS SPACES
# -----------------------------
# rush01 takes ONE argument holding 16 space-separated digits. Bazel's sh_test
# tokenises `args` on whitespace (see the comment at tools/defs.bzl:430 — this
# repo has been bitten by it repeatedly), so a clue vector written straight into
# `args` arrives as sixteen separate arguments and the interface the subject
# specifies is silently destroyed.
#
# This runner is built so that the sweep NEVER routes a clue vector through
# sh_test args: every clue string comes out of the corpus FILE, and is handed to
# the student as a single quoted word by this script. The only place a clue
# vector would have to survive Bazel is the correctness gate below, and it has
# --gate-arg-file for exactly that reason: point it at a one-line fixture and
# tokenisation cannot touch it. --gate-arg exists for callers who prefer to
# quote inside the BUILD file (Bazel tokenises `args` with Bourne-shell rules, so
# an embedded quote survives) — and if it arrives split anyway, the argument
# parser below recognises the wreckage and says so instead of failing obscurely.
#
# THE BONUS IS GRADED ONLY IF IT WAS ATTEMPTED
# -------------------------------------------
# The subject's bonus is grids up to 9x9, and a bonus is optional: a student who
# implemented only the mandatory 4x4 must not be reddened by this layer. But one
# who reached for the bonus and got it wrong should be. Those are told apart by
# the program's own answer rather than by a flag, so nothing has to be declared:
#
#   a bonus-size input, answered "Error"  -> the size was not handled. That is a
#       legitimate answer for a program whose accepted input is the 4x4 form, so
#       it PASSES. The run still proves the program does not crash, hang, or
#       overrun a buffer on an input four times the size it expects.
#   a bonus-size input, answered with a grid -> the bonus was ATTEMPTED, and the
#       grid is judged in full against the puzzle's rules.
#
# A program that never implemented 9x9 cannot print a 9x9 grid, so it cannot
# fail this. Pass --max-size 9 to drop the leniency and REQUIRE the bonus.
#
# Above 6x6 the corpus lists witnesses rather than every solution — exhaustively
# solving a 7x7 clue vector does not finish (see oracle/src/rush01_bonus.rs) — so
# those lines carry a "?" marker and the membership cross-check is skipped for
# them. Satisfying every rule is what makes a grid correct; membership was only
# ever a second opinion on top.
#
# CORPUS FORMAT (this runner defines it; the reference must emit it)
# -----------------------------------------------------------------
# One case per line, TAB-separated:
#
#     <clue string><TAB><solution><TAB><solution>...
#
#   <clue string>  the exact argv the student receives — 4N digits separated by
#                  single spaces, e.g. "4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2".
#                  Order: N column clues from the TOP, N from the BOTTOM, N row
#                  clues from the LEFT, N from the RIGHT. Malformed strings are
#                  legal corpus entries — they are the "any other input must be
#                  considered an error" cases — and simply carry no solutions.
#   <solution>     N*N digits, row-major, no separators, e.g. "1234234134124123"
#                  for the subject's worked example. `/`, `,`, `|` and spaces are
#                  tolerated INSIDE a solution and stripped, so a reference that
#                  prefers "1234/2341/3412/4123" also reads correctly.
#   no solution    no solution field at all. A trailing TAB with nothing after it
#                  is the same thing, which is what //oracle emits so that every
#                  line has the same shape.
#
# THE SEPARATOR IS A TAB, and `|` is deliberately NOT available for it — `|` is
# stripped from inside a solution field by the rule above, so `<sol>|<sol>` reads
# as one 32-digit grid and is rejected as a malformed corpus. That rejection is
# loud (exit 2, "the case list itself is wrong") and it is the intended
# behaviour: oracle/src/rush01.rs pins the same choice in its `SOL_SEP` constant
# and explains it there. A reader that quietly accepted both would hide a
# reference drifting away from the format instead of stopping the run.
#
# oracle/README.md's rush01 section once described the set as
# "<solution>|<solution>|..." while oracle/src/rush01.rs emitted TAB-separated
# fields. It now says TAB, and names `|` as the separator that is NOT available
# here -- this runner strips `|` from inside a solution field, so one between
# two solutions reads as a 32-digit grid and the whole corpus is rejected. The
# CODE is what this runner is built against either way.
#
# Blank lines and lines starting with '#' are ignored, so a corpus can be
# commented. (A completely EMPTY argv is therefore written as a line holding one
# TAB and nothing else — an empty clue field with no solutions — since a truly
# blank line cannot be told apart from spacing. --probe-argc covers it too.)
# Every listed solution is re-validated against its own clue vector before a
# single case is replayed (by `oracle rush01_validate`, which shares no code
# with the generators): if the reference is wrong, this layer says so rather
# than blaming the student for disagreeing with it.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "rush01_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk basename cat cp mktemp rm sed tr

# The shared runner helpers: the time budget, signal traps, how a run ended,
# excerpts and the clues.tsv rule (tools/runner_lib.sh, which says why each is
# written once).
RL_NAME=rush01_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "rush01_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool ORACLE -- the Rust reference (//oracle), which writes the corpus

BIN=""
ORACLE=""
# Space-separated list: --oracle-fn may be repeated, and the corpora are
# concatenated. That is how the mandatory 4x4 arm and the NxN bonus arm end up in
# ONE sweep — which they have to, because attempt detection only works if a
# bonus-size input is actually put in front of the program. FN_SET tracks whether
# the caller has spoken yet: the first --oracle-fn REPLACES this default, any
# further one adds to it.
FN="rush01_solve"
FN_SET=0
SEED="1"
COUNT="400"
CORPUS=""
HINTS=""
CASE_NAME=""
# Sizes 1..MAXSIZE are REQUIRED to be solved. The mandatory 4x4 is always
# required whatever this says; 0 therefore means "the mandatory board and
# nothing else", which is the right default because every other size is a bonus.
# See is_bonus() in the awk program.
MAXSIZE="0"
# The side of the board the subject REQUIRES. Every other size, larger or
# smaller, is the optional bonus, which is why this is a specific number and
# not an upper bound: a 4x4-only program cannot solve a 3x3 any more than it
# can solve a 9x9, and failing it for either would be grading an optional part
# of the subject.
MANDATORY_N=4
MAXCASES="0"
PROBE_ARGC=0
PROBE_SHAPE=0
PROBES_ONLY=0
LABEL=""
TMO="${RUSH01_TIMEOUT:-10}"
GATE_DIFFER=""
GATE_BIN=""
GATE_EXPECTED=""
GATE_ARG=""
GATE_ARG_SET=0
GATE_ARG_FILE=""
SHOW=""
MAX_TIMEOUTS="${RUSH01_MAX_TIMEOUTS:-3}"

# A stray bare digit in the argument list is the fingerprint of the tokenisation
# accident described in the header: someone wrote the 16-digit clue vector into
# sh_test `args` unquoted and Bazel handed us "4" "3" "2" "1" ... as separate
# words. Diagnose it by name — the generic "unknown option: 3" that every other
# runner prints has cost this repo three debugging sessions already.
tokenised_hint() {
	cat >&2 <<-'EOT'

	  This looks like a clue vector that was split into separate arguments.
	  The program takes ONE argument holding 16 space-separated digits, and Bazel
	  tokenises an sh_test `args` entry on whitespace, so

	      args = ["--gate-arg", "4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2"]

	  arrives here as seventeen words. Either quote it so Bourne tokenisation
	  keeps it whole:

	      args = ["--gate-arg", "'4 3 2 1 1 2 2 2 4 3 2 1 1 2 2 2'"]

	  or — better, because nothing can quietly re-split it later — put the vector
	  on the first line of a fixture file and pass

	      args = ["--gate-arg-file", "$(location tests/exNN/basic_clues.txt)"]

	  The sweep itself never has this problem: its clue vectors are read from the
	  corpus file, not from argv.
	EOT
}

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "rush01_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--oracle-fn)
			if [ "$FN_SET" -eq 0 ]; then FN="$2"; FN_SET=1; else rl_list_add FN "$2"; fi
			shift 2 ;;
		--seed) need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--corpus) need "$1" "$#"; CORPUS="$2"; shift 2 ;;
		--clues) need "$1" "$#"; HINTS="$2"; shift 2 ;;
		--case) need "$1" "$#"; CASE_NAME="$2"; shift 2 ;;
		--max-size) need "$1" "$#"; MAXSIZE="$2"; shift 2 ;;
		--max-cases) need "$1" "$#"; MAXCASES="$2"; shift 2 ;;
		--probe-argc) PROBE_ARGC=1; shift ;;
		--probe-shape) PROBE_SHAPE=1; shift ;;
		--probes-only) PROBES_ONLY=1; shift ;;
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--quotes) need "$1" "$#"; rl_quotes_opt "$2"; shift 2 ;;
		--timeout) need "$1" "$#"; TMO="$2"; shift 2 ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-arg) need "$1" "$#"; GATE_ARG="$2"; GATE_ARG_SET=1; shift 2 ;;
		--gate-arg-file) need "$1" "$#"; GATE_ARG_FILE="$2"; shift 2 ;;
		--show) need "$1" "$#"; SHOW="$2"; shift 2 ;;
		--stderr-empty) STDERR_EMPTY=1; shift ;;
		--stderr-ignored) need "$1" "$#"; STDERR_WHY="$2"; shift 2 ;;
		--sanitized | --valgrind | --valgrind-tools | --sample | --rule | --symbolizer | --symbolizer-lib)
			rl_mem_opt "$@"; shift "$RL_MEM_SHIFT" ;;
		*)
			echo "rush01_check: unknown option: $1" >&2
			case "$1" in
				[1-9]) tokenised_hint ;;
			esac
			exit 2 ;;
	esac
done

[ -n "$BIN" ] || { echo "rush01_check: --bin is required" >&2; exit 2; }
[ -n "$LABEL" ] || LABEL="$(basename "$BIN")"
rl_stderr_choice
rl_quotes_ready error
Q_ERROR=$(rl_quote error)
rl_rows "$SHOW"
rl_mem_ready

if [ "$PROBES_ONLY" -eq 1 ]; then
	if [ "$PROBE_ARGC" -eq 0 ] && [ "$PROBE_SHAPE" -eq 0 ]; then
		echo "rush01_check: --probes-only runs the probes asked for, and none was" >&2
		echo "              (--probe-argc, --probe-shape): it would check nothing." >&2
		exit 2
	fi
	if [ -n "$CORPUS" ]; then
		echo "rush01_check: --probes-only replays no corpus, so --corpus would be ignored" >&2
		exit 2
	fi
elif [ -z "$CORPUS" ] && [ -z "$ORACLE" ]; then
	echo "rush01_check: need either --corpus FILE or --oracle PATH" >&2
	exit 2
fi
# The shape probes vary ONE well-formed vector, and a probes-only run has no
# corpus to take the two-argument probe's from: both need the vector
# --gate-arg (or --gate-arg-file) names. Checked once it has been read, below.

if [ ! -x "$BIN" ]; then
	echo "rush01_check: FAIL — '$BIN' is not an executable file."
	echo "               Nothing could be run, so nothing was checked."
	exit 1
fi

# awk reads every answer (the grid's shape, the line counts, the Error handling)
# and hands the grids to the reference. Without it this layer cannot report a
# pass it can stand behind, so there is no quiet-skip path for it at all.
if ! command -v awk >/dev/null 2>&1; then
	echo "rush01_check: FAIL — no awk on this machine, and this layer reads every"
	echo "               answer in awk. It cannot report a pass."
	exit 2
fi

# The reference is run from inside awk (see WHERE THE RULES LIVE), by a shell
# that has to find it whatever directory it is named relative to — and a bare
# name would even be looked up on PATH. So it is made absolute once, here; the
# messages keep naming it the way the caller did.
ORACLE_SHOWN="$ORACLE"
case "$ORACLE" in
	"" | /*) ;;
	*) ORACLE="$PWD/$ORACLE" ;;
esac

# An inner per-run timeout, well under Bazel's, so a solver that never terminates
# is reported as one rather than surfacing as an opaque Bazel timeout with
# nothing in the log. A 4x4 board is small enough that any terminating solver
# finishes in milliseconds; the generous default is for a very slow one under a
# sanitizer build, not for a hung one. What is left of the test's own limit caps
# it too (rl_tmo, in run_one).

T=$(mktemp -d)
rl_traps 'rm -rf "$T"'

# ---------------------------------------------------------------------------
# Correctness gate (tools/runner_lib.sh's rl_gate, below): the exercise's OWN
# output fixture first, and SKIP while it is red. The exercise's *_output layer
# is the one with pedagogic value -- the subject's own worked example, a
# labelled table, hints attached -- and a student whose basic case does not
# work yet learns nothing from 900 further failures that all say the same
# thing. It fails OPEN, and NO_SKIP=1 forces it open (rl_gate says how).

if [ -n "$GATE_ARG_FILE" ]; then
	if [ ! -f "$GATE_ARG_FILE" ]; then
		echo "rush01_check: --gate-arg-file '$GATE_ARG_FILE' does not exist" >&2
		exit 2
	fi
	# First line, newline stripped: the file holds the single argv the gate run
	# needs, and reading it here is what makes the gate immune to tokenisation.
	IFS= read -r GATE_ARG < "$GATE_ARG_FILE" || true
	GATE_ARG_SET=1
fi

# The probes' base vector (see --probe-shape, --probe-argc): a well-formed
# clue string. A malformed one would make every probe built from it an error
# by construction, whatever the program does with blanks or with argc -- the
# dead probe of finding 153 again -- so it is refused as the harness's
# mistake, never used.
if [ "$PROBE_SHAPE" -eq 1 ] || { [ "$PROBES_ONLY" -eq 1 ] && [ "$PROBE_ARGC" -eq 1 ]; }; then
	if [ "$GATE_ARG_SET" -eq 0 ]; then
		echo "rush01_check: --probe-shape, and --probe-argc with --probes-only, build their" >&2
		echo "              inputs from the vector --gate-arg or --gate-arg-file names, and" >&2
		echo "              none was given." >&2
		exit 2
	fi
fi
if [ "$GATE_ARG_SET" -eq 1 ] && { [ "$PROBE_SHAPE" -eq 1 ] || [ "$PROBE_ARGC" -eq 1 ]; }; then
	# parse_clue's rule (the awk program below), restated for one string:
	# single digits, single spaces, 4N of them, none above N, N at most 9.
	if ! printf '%s\n' "$GATE_ARG" | awk '
		NR == 1 && /^[1-9]( [1-9])*$/ {
			m = split($0, t, " "); n = m / 4
			if (m % 4 == 0 && n <= 9) { ok = 1; for (i = 1; i <= m; i++) if (t[i] + 0 > n) ok = 0 }
		}
		END { exit !ok }'; then
		echo "rush01_check: the probes' base vector \"$GATE_ARG\" is not a well-formed clue" >&2
		echo "              string, so every probe built from it would be an error whatever" >&2
		echo "              the program did: they could catch nothing." >&2
		exit 2
	fi
fi

# The gate runs the program with the one argument the gating case's own output
# test passes (c_levels()' audit holds the two to each other: tools/defs.bzl,
# _gate_problems).
if [ "$GATE_ARG_SET" -eq 1 ]; then
	rl_gate rush01_check "$GATE_DIFFER" "$GATE_BIN" "$GATE_EXPECTED" "$GATE_ARG"
else
	rl_gate rush01_check "$GATE_DIFFER" "$GATE_BIN" "$GATE_EXPECTED"
fi

# A PROGRAM THAT DID NOT BUILD is a stand-in script that says why (see
# tools/standin.sh). Checked after the gate: a red gate has already skipped
# this layer, and past a green one -- or one NO_SKIP=1 forced open -- a
# stand-in is a failure, told in the compiler's words rather than as a
# report about a program that does not exist.
case "$0" in */*) _sl_dir=${0%/*} ;; *) _sl_dir=. ;; esac
for _sl in "$_sl_dir/standin.sh" \
	"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
	[ -f "$_sl" ] && break
done
[ -f "$_sl" ] || { echo "rush01_check.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
standin_check rush01_check "$BIN" "$RL_STANDIN" "${LABEL:-the program}"

# ---------------------------------------------------------------------------
# Corpus acquisition. None for --probes-only: its target replays no corpus.
if [ "$PROBES_ONLY" -eq 1 ]; then
	SRC="probes only, built from \"$GATE_ARG\""
	if [ -n "$ORACLE" ] && [ ! -x "$ORACLE" ]; then
		echo "rush01_check: FAIL — the reference '$ORACLE_SHOWN' is not executable."
		exit 2
	fi
elif [ -n "$CORPUS" ]; then
	if [ ! -f "$CORPUS" ]; then
		echo "rush01_check: --corpus '$CORPUS' does not exist" >&2
		exit 2
	fi
	cp "$CORPUS" "$T/corpus"
	SRC="corpus $CORPUS"
	# Given as well, the reference is what judges the grids (WHERE THE RULES
	# LIVE), so an unusable one is a harness fault here too, not a quiet
	# fall-back to membership alone.
	if [ -n "$ORACLE" ] && [ ! -x "$ORACLE" ]; then
		echo "rush01_check: FAIL — the reference '$ORACLE_SHOWN' is not executable."
		echo "               Nothing could judge the grids, so nothing was checked."
		exit 2
	fi
else
	if [ ! -x "$ORACLE" ]; then
		echo "rush01_check: FAIL — the reference '$ORACLE_SHOWN' is not executable."
		echo "               Nothing generated the case list, so nothing was checked."
		exit 2
	fi
	: > "$T/corpus"
	# FN is one name per line (runner_lib.sh, LISTS OF WORDS).
	rl_split_on
	for _fn in $FN; do
		if ! "$ORACLE" "$_fn" "$SEED" "$COUNT" >> "$T/corpus" 2> "$T/oerr"; then
			echo "rush01_check: FAIL — the reference could not generate cases (fn=$_fn)."
			echo "               This is a harness problem, not yours."
			[ -s "$T/oerr" ] && rl_excerpt "$T/oerr" 5 reference-stderr.txt
			exit 2
		fi
	done
	rl_split_off
	SRC="fn=$(printf '%s' "$FN" | tr '\n' ' '), seed=$SEED, count=$COUNT"
fi

# ---------------------------------------------------------------------------
# The judgement itself, in awk: one program, two modes.
#
#   mode=prep   read the corpus, have the reference validate every solution it
#               claims (one run, batched), normalise each case to
#               "<isbonus>\t<n>\t<nsol>\t<exh>\t<sols>\t<clue>" (n the board's
#               side, 0 for a malformed input) and apply --max-size /
#               --max-cases.
#               Exit 2 the corpus is wrong, 3 it needs --oracle to be judged,
#               4 the reference could not check it.
#   mode=judge  read ONE run's captured stdout and stderr, decide, and print the
#               verdict block. Exit 0 pass, 1 the student is wrong, 2 the corpus
#               and this checker disagree (see the header).
#
# One file rather than two so that the way a grid is handed to the reference —
# the request, the reading of the reply — exists EXACTLY once and is shared by
# the corpus self-check and the student judgement. If those two ever drifted
# apart, the layer would be validating the student against rules it never
# applied to the reference.
#
# The reference is found through the environment, not through -v: RUSH01_ORACLE
# (empty without --oracle) and RUSH01_REQ, the request file. awk hands its
# command line to a shell, and a path that travels as "$RUSH01_ORACLE" inside
# that line can never need quoting, whatever characters it holds.
printf '%s\n' "$RL_AWK_VIS" > "$T/rush01.awk"
cat >> "$T/rush01.awk" <<'AWK_END'
# ---------------------------------------------------------------- shared rules
#
# WHICH RULE A GRID BREAKS IS NOT DECIDED HERE — see WHERE THE RULES LIVE in
# the header. These functions only carry a grid to `oracle rush01_validate` and
# its answer back.

# The reference's command line. Both paths travel in the environment, so the
# shell awk hands this to never sees one it would have to quote.
function validate_cmd() { return "\"$RUSH01_ORACLE\" rush01_validate < \"$RUSH01_REQ\"" }
function have_validator() { return ENVIRON["RUSH01_ORACLE"] != "" }

# One request line: grid g (GH rows of GW cells) against clue vector cl. A cell
# goes out as the NUMBER awk read it as — %.17g round-trips a double exactly —
# because in the no-solution path below a grid is built before every row has
# been shown to be well-formed, and the verdict there has always been computed
# on awk's numeric reading of each token (see WHY A CELL IS A NUMBER in
# oracle/src/rush01_validate.rs).
function grid_request(g, cl,   r, c, k, s) {
	s = GW " " GH "\t"
	for (k = 1; k <= 2 * GW + 2 * GH; k++) s = s (k > 1 ? " " : "") cl[k]
	s = s "\t"
	for (r = 1; r <= GH; r++)
		for (c = 1; c <= GW; c++)
			s = s ((r > 1 || c > 1) ? " " : "") sprintf("%.17g", g[r "," c])
	return s
}

# Read one reply into F_CAT / F_MSG / F_WHY (the first broken rule's category,
# the sentence naming it, and the rule restated). Returns how many rules the
# grid breaks, or -1 when the line is not a reply at all.
function take_reply(line,   f, n) {
	F_CAT = ""; F_MSG = ""; F_WHY = ""
	n = split(line, f, "\t")
	if (n != 4 || f[1] !~ /^[0-9]+$/ || ((f[1] + 0 == 0) != (f[2] == "ok"))) return -1
	if (f[1] + 0 > 0) { F_CAT = f[2]; F_MSG = f[3]; F_WHY = f[4] }
	return f[1] + 0
}

# Ask the reference about ONE grid. Returns the number of broken rules, the
# first described in F_CAT / F_MSG / F_WHY, or -1 when no usable answer came
# back — which is the harness failing, never the student.
function check_grid(g, cl,   req, cmd, line, got) {
	req = ENVIRON["RUSH01_REQ"]
	printf "%s\n", grid_request(g, cl) > req
	close(req)
	cmd = validate_cmd()
	line = ""
	got = (cmd | getline line)
	if (close(cmd) != 0 || got <= 0) return -1
	return take_reply(line)
}

# The board the subject REQUIRES (MANDATORY_N in the shell, which also words
# a TIMEOUT by it).
function mandatory_n() { return mandn + 0 }

# True when a case of size n is bonus territory for this run: not the mandatory
# board, and outside the range the caller asked to have REQUIRED (--max-size).
function is_bonus() {
	return (GW != mandatory_n() && GW > maxsize)
}

# Split a clue string into cl[1..4N] and set the board's side. Returns 1, or 0
# if the string is not a well-formed vector at all (this is the "any other
# input is an error" case).
#
# The board is square: 4N clues are an N x N board, 1 <= N <= 9. That is the
# only shape the subject's input can carry. A rectangle would need its width
# said separately, since 2W + 2H clues do not determine W and H, and anything
# beside the one clue string is, in the subject's words, input that "must be
# considered an error". So no other shape is read here: a flag in front of the
# clues makes the string malformed, and Error is the answer to it.
function parse_clue(s, cl,   i, m, t, n) {
	GW = 0; GH = 0; GK = 0
	if (s !~ /^[1-9]( [1-9])*$/) return 0
	m = split(s, t, " ")
	if (m % 4 != 0) return 0
	n = m / 4
	if (n > 9) return 0
	for (i = 1; i <= m; i++) {
		# A clue counts boxes along ONE line, so it can never exceed that
		# line's length.
		if (t[i] + 0 > n) return 0
		cl[i] = t[i] + 0
	}
	GW = n; GH = n; GK = n
	return 1
}

# Load an N*N-digit row-major string into g. Returns 1 on success.
function load_sol(s, g,   i, r, c, ch) {
	gsub(/[\/,| ]/, "", s)
	if (length(s) != GW * GH) return 0
	for (i = 1; i <= GW * GH; i++) {
		ch = substr(s, i, 1)
		if (ch !~ /^[1-9]$/ || ch + 0 > GK) return 0
		r = int((i - 1) / GW) + 1
		c = ((i - 1) % GW) + 1
		g[r "," c] = ch + 0
	}
	return 1
}

# A captured line, every byte visible: runner_lib.sh's one renderer
# (rl_vis_exact, whose source heads this file), so a report shows what came
# out without a stray control byte scrambling the terminal. This was a copy of
# its own that showed every such byte as "\?" -- a NUL and an escape alike.
function esc(s) {
	return rl_vis_exact(s)
}

BEGIN {
	if (mode == "prep") prep_init()
}

# ------------------------------------------------------------------- prep mode
# Reads the corpus. Every field after the first is a solution the reference
# CLAIMS; each one is re-derived against its own clue vector, so a wrong
# reference is caught before it can be used to fail a student.
#
# The re-derivation is batched: every well-shaped listed grid becomes one line
# of the request file, and `oracle rush01_validate` answers them all in ONE run
# at the end (prep_validate). The complaints about the corpus are therefore
# collected in order as notes and printed afterwards, with each grid's verdict
# filled in where it belongs, so they read exactly as if each had been checked
# on the spot.

function prep_init() {
	ntot = 0; nsolvable = 0; nunsolv = 0; nskipped = 0; nbonus = 0; badref = 0
	nnote = 0; nreq = 0; needoracle = 0
}

function note(s) { notes[++nnote] = s }

# Run the reference once over every request the main rule wrote, keeping each
# reply's fault count and sentence. Exits 4 when it does not answer them all:
# the corpus could not be checked, which is the harness failing.
function prep_validate(   req, cmd, line, n, rc) {
	if (nreq == 0) return
	req = ENVIRON["RUSH01_REQ"]
	close(req)
	cmd = validate_cmd()
	n = 0
	while ((cmd | getline line) > 0) {
		n++
		rfaults[n] = take_reply(line)
		rmsg[n] = F_MSG
		if (rfaults[n] < 0) break
	}
	rc = close(cmd)
	if (rc != 0 || n != nreq || (n > 0 && rfaults[n] < 0)) {
		printf "rush01_check: FAIL — the reference (oracle rush01_validate) answered %d of\n" \
			"               the %d listed grid(s) it was asked about (status %d), so the\n" \
			"               case list could not be checked.\n", \
			(n > 0 && rfaults[n] < 0 ? n - 1 : n), nreq, rc > "/dev/stderr"
		exit 4
	}
}

mode == "prep" {
	if ($0 ~ /^[ \t]*#/) next
	if ($0 == "") next
	nf = split($0, f, "\t")
	clue = f[1]
	okc = parse_clue(clue, cl)
	sols = ""
	ns = 0
	nalt = 0
	# A field of "?" is the reference saying "the solutions that follow are
	# WITNESSES, not the whole set" — see rush01_bonus.rs. Exhaustively solving a
	# 7x7 clue vector does not finish, so above 6x6 the corpus cannot promise
	# completeness and the membership cross-check below has to be turned off for
	# that line. The 4x4 corpus never carries the marker.
	exh = 1
	for (i = 2; i <= nf; i++) {
		if (f[i] == "") continue
		if (f[i] == "?") { exh = 0; continue }
		nalt++
		sset[nalt] = f[i]
	}
	# Witnesses cannot be judged by membership: a correct grid the line does not
	# name is still correct, and only the rule check can say so. Without the
	# reference there is no rule check (WITHOUT --oracle in the header).
	if (!exh && nalt > 0 && !have_validator() && needoracle++ == 0) witness = clue
	for (i = 1; i <= nalt; i++) {
		ns++
		sols = (sols == "" ? sset[i] : sols " " sset[i])
		# ---- the reference is checked against the rules, not trusted ----
		if (!okc) {
			note(sprintf("rush01_check: FAIL — the corpus lists a solution for an input that is\n" \
				"               not a well-formed clue vector: %s\n", esc(clue)))
			badref++
			continue
		}
		delete gg
		if (!load_sol(sset[i], gg)) {
			note(sprintf("rush01_check: FAIL — corpus solution %d for \"%s\" is not %d digits\n" \
				"               of a %dx%d grid: %s\n", i, clue, GW * GH, GW, GH, esc(sset[i])))
			badref++
			continue
		}
		if (have_validator()) {
			printf "%s\n", grid_request(gg, cl) > ENVIRON["RUSH01_REQ"]
			note("")
			pend[nnote] = ++nreq
			pendsol[nnote] = i
			pendclue[nnote] = clue
		}
	}
	delete sset
	# A well-formed vector LARGER than --max-size that has solutions is bonus
	# territory. It is NOT skipped: it is run and judged leniently, which is the
	# only way to tell "did not attempt the bonus" from "attempted it and got it
	# wrong". See the ATTEMPT DETECTION note in judge_end().
	if (is_bonus() && ns > 0) nbonus++
	ntot++
	if (ns > 0) nsolvable++; else nunsolv++
	rec[ntot] = (is_bonus() ? 1 : 0) "\t" (okc ? GW : 0) "\t" ns "\t" exh "\t" \
		(sols == "" ? "-" : sols) "\t" clue
}

END {
	if (mode != "prep") judge_end()
	else {
		prep_validate()
		for (j = 1; j <= nnote; j++) {
			if (!(j in pend)) { printf "%s", notes[j] > "/dev/stderr"; continue }
			if (rfaults[pend[j]] > 0) {
				printf "rush01_check: FAIL — corpus solution %d for \"%s\" breaks a rule of the\n" \
					"               puzzle it is supposed to solve: %s\n", \
					pendsol[j], pendclue[j], rmsg[pend[j]] > "/dev/stderr"
				badref++
			}
		}
		if (badref > 0) exit 2
		if (needoracle > 0) {
			printf "rush01_check: %d line(s) of this case list give witnesses (\"?\"), not every\n" \
				"               solution, and a grid such a line does not name can only be\n" \
				"               judged by the rules — which are the reference's: pass --oracle.\n" \
				"               The first such line: \"%s\"\n", needoracle, witness > "/dev/stderr"
			exit 3
		}
		# --max-cases SAMPLES, it does not truncate: a corpus is ordered
		# (structured cases first, random tail last, bonus sizes wherever the
		# reference put them), so keeping the first N would quietly drop a whole
		# class of case and the layer would report a coverage it never had.
		#
		# The selection is the Bresenham one — keep line i when
		# floor(want*i/ntot) advances — because the obvious "every ntot/want-th
		# line" runs out of budget before the end of the file and drops the
		# tail: at 858 cases and a budget of 40 it stops at line 840 and the
		# last 18 are never tried. This one spans the whole file by
		# construction and always yields exactly `want` cases.
		want = (maxcases > 0 && ntot > maxcases) ? maxcases : ntot
		kept = 0; ks = 0; ku = 0
		for (i = 1; i <= ntot; i++) {
			if (int(want * i / ntot) == int(want * (i - 1) / ntot)) continue
			print rec[i] > casefile
			kept++
			split(rec[i], ff, "\t")
			if (ff[3] + 0 > 0) ks++; else ku++
		}
		close(casefile)
		printf "%d %d %d %d\n", kept, ks, ku, nbonus > statsfile
		close(statsfile)
	}
}

# ------------------------------------------------------------------ judge mode
# Reads the run's captured stdout (file `outfile`) and stderr (file `errfile`).
# The capture always ends in a sentinel '@' appended by the shell, so that a
# MISSING FINAL NEWLINE is visible from in here: "1 2 3 4\n" and "1 2 3 4" are
# the same set of awk records otherwise, and the Moulinette compares bytes.
# FILENAME is compared rather than the usual FNR==NR trick because an EMPTY
# stderr makes awk skip that file entirely and the trick then misattributes
# every line.

mode == "judge" && FILENAME == outfile {
	ntot_out++
	lastrec = $0
	# Only the first few lines are kept: a correct grid is at most 9 of them, and
	# a program printing 100000 lines is already wrong for a reason the count
	# alone explains. Keeping them all would let a runaway build a huge array.
	if (ntot_out <= 64) o[ntot_out] = $0
	next
}
mode == "judge" && FILENAME == errfile {
	nerr++
	if (nerr <= 4) e[nerr] = $0
}

function say(s) { print s }

function show_output(   i, lim) {
	say("   your program printed:")
	if (nout == 0) { say("     (nothing on standard output)"); return }
	lim = (nout > 8 ? 8 : nout)
	for (i = 1; i <= lim; i++) say("     | " esc(o[i]))
	if (nout > lim) say(sprintf("     ... and %d more line(s)", nout - lim))
	if (!eol) say("     (the last line was NOT terminated by a newline)")
}

function show_clues(   k, s, parts) {
	if (n == 0) return
	parts = ""
	for (k = 1; k <= 4 * n; k++) {
		parts = parts cl[k] (k % n == 0 && k < 4 * n ? "  " : (k < 4 * n ? " " : ""))
	}
	say(sprintf("   clues: %s   (%d from %s, %d from %s, %d from %s, %d from %s)", \
		parts, n, "the top", n, "the bottom", n, "the left", n, "the right"))
}

# Why "Error" and a newline is the only right answer to this input, in its
# own terms: a probe is not "an input with no solution" -- it is malformed,
# under a reading (shape) or in its argument list (argc, argc2) -- and a
# FAULT line that said so contradicted the header line just above it.
function error_reason() {
	if (probe == "shape")
		return "under this harness's reading, this argument is not the clue string's one shape"
	# A count, never the subject's sentence about other input (V41's
	# review: the two-argument verdict below had stopped quoting it).
	if (probe == "argc2")
		return "the program was given two arguments, one more than the subject's launch line passes"
	if (probe == "argc")
		return "this argument list is not the one clue string the program takes"
	if (!okc)
		return "this is not a well-formed input"
	return "this input has no solution"
}

function verdict(cat, msg, why) {
	print cat >> catfile
	say(" --------------------------------------------------")
	say(sprintf(" %s %s  argv: %s%s", (probe != "" ? "PROBE" : "CASE"), caseid, \
		(clue == "" && argvdesc != "" ? argvdesc : "\"" esc(clue) "\""), \
		(clue != "" && argvdesc != "" ? "  -- " argvdesc : "")))
	show_clues()
	if (nsol > 0)
		say(sprintf("   this input HAS %d valid grid%s", nsol, (nsol == 1 ? "" : "s")))
	else if (!okc && probe == "shape")
		say("   under this harness's reading, this is NOT a well-formed input,\n" \
		    "   so the only correct output is Error")
	else if (!okc)
		say("   this is NOT a well-formed input, so the only correct output is Error")
	else
		say("   NO arrangement of the heights satisfies this input")
	show_output()
	say("   FAULT [" cat "] " msg)
	# A why of several lines (a quoted sentence, folded) is indented whole.
	gsub(/\n/, "\n     ", why)
	if (why != "") say("     " why)
	if (nerr > 0 && cat != "error-on-stderr") {
		say("   (it also wrote to standard error: " esc(e[1]) ")")
	}
}

# The reference gave no usable answer about this grid. That says nothing about
# the student, so it is a HARNESS verdict (exit 2), never theirs.
function validator_failed() {
	print "validator-failed" >> catfile
	say(" --------------------------------------------------")
	say(" HARNESS PROBLEM, not yours: the reference (oracle rush01_validate) gave no")
	say(" usable answer about the grid printed for \"" clue "\", so it could not be")
	say(" judged.")
	exit 2
}

# What a row of this board looks like, one "d" per height: "d d d d" at 4x4,
# nine of them at 9x9. Built from the board rather than written out, because a
# fixed 4x4 row under a 9x9 case contradicted the sentence it sat in.
function row_shape(   k, r) {
	r = "d"
	for (k = 2; k <= GW; k++) r = r " d"
	return r
}

# Is line `s` a well-formed row of GW heights, "d d d d"? Returns "" if it is,
# otherwise the reason it is not, in the subject's own terms.
function row_fault(s,   m, t, k) {
	if (index(s, "\t") > 0)
		return "it contains a tab; the values are separated by a single space"
	m = split(s, t, "[ ]")
	for (k = 1; k <= m; k++) {
		if (t[k] != "") continue
		if (k == 1) return "it starts with a space"
		if (k == m) return "it ends with a space"
		return "two values are separated by more than one space"
	}
	# GW > 1 guard: on a one-cell-wide board a row IS a single character with no
	# separator in it, so the "run together" reading is exactly the correct
	# output and this check would reject it. Only from two cells up does one
	# token mean the spaces are missing.
	if (GW > 1 && m == 1 && length(t[1]) == GW)
		return sprintf("the %d values are run together; they are separated by single spaces", GW)
	if (m != GW)
		return sprintf("it holds %d value%s, but a row of this grid has %d", m, (m == 1 ? "" : "s"), GW)
	for (k = 1; k <= m; k++) {
		if (t[k] !~ /^[1-9]$/)
			return sprintf("value %d is \"%s\"; each cell holds one digit", k, esc(t[k]))
		if (t[k] + 0 > GK)
			return sprintf("value %d is %s, but the heights of a %dx%d grid run 1..%d", \
				k, t[k], GW, GH, GK)
	}
	return ""
}

function judge_end(   i, k, fault, faults, key, sawrow) {
	okc = parse_clue(clue, cl)
	nsol = 0
	if (sols != "-" && sols != "") {
		nsol = split(sols, sarr, "[ \t]+")
		for (i = 1; i <= nsol; i++) {
			delete gg
			if (load_sol(sarr[i], gg)) {
				key = sarr[i]
				gsub(/[\/,| ]/, "", key)
				member[key] = 1
			}
		}
	}

	# Undo the sentinel: it is the final byte of the capture, always.
	nout = ntot_out
	eol = 1
	if (nout > 0) {
		if (lastrec == "@") {
			nout--
		} else {
			eol = 0
			if (nout <= 64) o[nout] = substr(lastrec, 1, length(lastrec) - 1)
		}
	}

	# ---- the input has no solution: the only correct output is "Error\n" ----
	if (nsol == 0) {
		if (nout == 1 && o[1] == "Error" && eol) { print "ok" >> catfile; exit 0 }
		if (nout == 0) {
			for (i = 1; i <= nerr; i++) {
				if (e[i] ~ /Error/) {
					verdict("error-on-stderr", \
						"nothing was written to standard output; \"Error\" went to standard error.", \
						"The output this test compares is standard output; standard error is not part of it.")
					exit 1
				}
			}
			verdict("no-output", "it printed nothing at all; " error_reason() ".", \
				ENVIRON["RUSH01_Q_ERROR"])
			exit 1
		}
		# A malformed clue vector tells us nothing about the shape, so the only
		# hint left for phrasing the message is what the program actually
		# printed. Assume a square of that many rows, exactly as before.
		if (!okc) { GW = nout; GH = nout; GK = nout }
		sawrow = 0
		for (i = 1; i <= nout && i <= 64; i++) if (row_fault(o[i]) == "") sawrow = 1
		if (sawrow && nout == GH && eol) {
			# It printed a GRID for an input nothing can satisfy. Say which rule
			# that grid breaks — the enumeration behind this corpus guarantees
			# there is one.
			delete gg
			key = ""
			for (i = 1; i <= GH; i++) {
				split(o[i], t2, "[ ]")
				for (k = 1; k <= GW; k++) { gg[i "," k] = t2[k] + 0; key = key t2[k] }
			}
			if (!okc && probe == "argc2") {
				# The probe gives a clue string the program accepts on its own,
				# twice: a grid means one of them was read and the other not.
				verdict("false-solution", \
					"it printed a grid for two arguments: it read one clue string and ignored the other.", \
					"How many arguments does the subject's launch line pass, and which of its " \
					"sentences says what any other input prints?")
				exit 1
			}
			# The reading is the target's hints' to state, never this runner's:
			# a runner states no reading of its own, and quotes no subject
			# (docs/design.md; V41). It says which question decides, and asks.
			if (!okc && probe == "shape") {
				verdict("false-solution", \
					"it printed a grid, but under this harness's reading this argument is not the clue string's one shape.", \
					"Its hints below state that reading. Which sentence of the subject does it " \
					"read, and what does that sentence say any other input prints?")
				exit 1
			}
			if (!okc) {
				verdict("false-solution", "it printed a grid, but this is not a well-formed input.", \
					"No reading of the subject accepts this input. Which of its " \
					"sentences says what any other input prints?")
				exit 1
			}
			if (!have_validator()) {
				verdict("false-solution", "it printed a grid, but no arrangement satisfies these clues.", \
					"The case list gives this input no solution. The only correct output here is Error.")
				exit 1
			}
			faults = check_grid(gg, cl)
			if (faults < 0) validator_failed()
			if (faults == 0) {
				print "corpus-inconsistent" >> catfile
				say(" --------------------------------------------------")
				say(" HARNESS PROBLEM, not yours: for \"" clue "\" the corpus says there is no")
				say(" solution, but the grid printed satisfies every rule. The reference and")
				say(" this checker disagree; the reference needs fixing.")
				exit 2
			}
			verdict("false-solution", \
				"it printed a grid, but no arrangement satisfies these clues — " F_MSG, \
				F_WHY " The only correct output here is Error.")
			exit 1
		}
		# Something else entirely. Name WHICH way it differs from "Error\n", since
		# "your error output is wrong" without saying how is the least useful
		# sentence a test can print.
		if (nout == 1 && o[1] == "Error" && !eol)
			verdict("bad-error-text", "it printed Error, but without the newline after it.", \
				"Output is compared byte for byte: \"Error\" and \"Error\\n\" are different files.")
		else if (nout == 1 && tolower(o[1]) == "error")
			verdict("bad-error-text", "it printed \"" esc(o[1]) "\"; the word is spelled Error.", \
				ENVIRON["RUSH01_Q_ERROR"])
		else if (nout > 1)
			verdict("bad-error-text", \
				sprintf("it printed %d lines; %s.", nout, error_reason()), \
				ENVIRON["RUSH01_Q_ERROR"])
		else
			verdict("bad-error-text", "it printed something else; " error_reason() ".", \
				ENVIRON["RUSH01_Q_ERROR"])
		exit 1
	}

	# ---- the input HAS solutions ----
	#
	# ATTEMPT DETECTION — how a bonus is graded without being required
	# ----------------------------------------------------------------
	# A bonus is optional, so a student who implemented only the mandatory 4x4
	# must never be reddened here. But a student who DID reach for the bonus and
	# got it wrong should be. Those two have to be told apart, and the program
	# itself says which it is:
	#
	#   Error       -> the size was not handled. That is a legitimate answer for
	#                  a program whose accepted input is the 4x4 form, so it
	#                  passes, and the run still proves the program does not
	#                  crash, hang or scribble on a 9x9 input.
	#   a grid      -> the bonus was ATTEMPTED. Nothing but the puzzle's own
	#                  rules can make that grid right, so it is judged in full.
	#
	# No opt-in flag and no honour system: the only way to fail this is to print
	# a grid, which a program that never implemented the size cannot do. Pass
	# --max-size 9 to drop the leniency and require the bonus to be solved.
	if (is_bonus() && nout == 1 && o[1] == "Error" && eol) {
		print "bonus-absent" >> catfile
		exit 0
	}
	if (nout == 1 && o[1] == "Error" && eol) {
		verdict("false-error", \
			sprintf("it printed Error, but %d grid%s satisfies these clues.", nsol, (nsol == 1 ? "" : "s")), \
			"Error is for an input that is malformed or that nothing can satisfy. This one can be.")
		exit 1
	}
	if (nout == 0) {
		verdict("no-output", "it printed nothing at all.", \
			"This input has a solution; the grid has to be displayed, one row per line.")
		exit 1
	}
	# "wrong number of lines" is the right thing to say about four rows and a
	# stray fifth. It is the WRONG thing to say about output that is not a grid
	# in the first place — a lower-case "error", a "Solution:" banner, a prompt —
	# so separate the two before counting anything.
	sawrow = 0
	for (i = 1; i <= nout && i <= 64; i++) if (row_fault(o[i]) == "") sawrow = 1
	if (!sawrow) {
		if (nout <= 2 && tolower(o[1]) ~ /^error/)
			verdict("false-error", \
				sprintf("it printed \"%s\", but %d grid%s satisfies these clues.", esc(o[1]), nsol, \
					(nsol == 1 ? "" : "s")), \
				"Error is for an input that is malformed or that nothing can satisfy. This one can be.")
		else if (nout == GH)
			# The right NUMBER of lines, none of them a valid row: the shape of
			# the answer is there and only the row format is wrong, so say what
			# is wrong with the row rather than the useless "not a grid".
			verdict("row-format", sprintf("line 1 is not a row of this grid: %s.", row_fault(o[1])), \
				"A row is printed as its heights separated by single spaces, e.g. \"1 2 3 4\".")
		else
			verdict("not-a-grid", "the output is not a grid.", \
				sprintf("This input has a solution, so what is displayed is %d lines of %d heights, " \
					"each line \"%s\" — nothing else, no heading and no prompt.", GH, GW, row_shape()))
		exit 1
	}
	if (nout != GH) {
		verdict("wrong-shape", \
			sprintf("it printed %d line%s; a %dx%d grid is %d rows.", nout, (nout == 1 ? "" : "s"), GW, GH, GH), \
			"One row per line, and a newline after each row — including the last.")
		exit 1
	}
	for (i = 1; i <= GH; i++) {
		fault = row_fault(o[i])
		if (fault != "") {
			verdict("row-format", sprintf("line %d is not a row of this grid: %s.", i, fault), \
				"A row is printed as its heights separated by single spaces, e.g. \"1 2 3 4\".")
			exit 1
		}
	}
	if (!eol) {
		verdict("missing-newline", "the last row is not terminated by a newline.", \
			"The grid is correct, but the bytes are not: output is compared byte for byte, " \
			"and \"4 1 2 3\" and \"4 1 2 3\\n\" are different files.")
		exit 1
	}

	delete gg
	key = ""
	for (i = 1; i <= GH; i++) {
		split(o[i], t2, "[ ]")
		for (k = 1; k <= GW; k++) { gg[i "," k] = t2[k] + 0; key = key t2[k] }
	}

	# The two answers must agree: the corpus lists EVERY grid that satisfies the
	# clues, so "satisfies the rules" and "is in the list" are the same question
	# asked twice. When they disagree the harness is broken, and saying so is the
	# only honest outcome — blaming the student for the reference's mistake is
	# exactly the failure mode this cross-check exists to prevent.
	#
	# One direction was settled before the sweep began: prep had the reference
	# check every listed grid against its clues, and refused the whole list if
	# one broke a rule. So a grid the list names is right, and asking again here
	# would only repeat that answer — once per case, for every correct program.
	# Only a grid the list does NOT name goes to the reference.
	if (key in member) { print (is_bonus() ? "bonus-ok" : "ok") >> catfile; exit 0 }
	if (!have_validator()) {
		verdict("not-a-solution", \
			(nsol == 1 ? "the grid printed is not the grid the case list gives for these clues." \
				: sprintf("the grid printed is not one of the %d grids the case list gives for these clues.", nsol)), \
			"This run has no --oracle, so which rule the grid breaks was not worked out.")
		exit 1
	}
	faults = check_grid(gg, cl)
	if (faults < 0) validator_failed()
	# Above 6x6 the corpus lists WITNESSES, not the whole set (exhaustively
	# solving a 7x7 vector does not finish — see rush01_bonus.rs), so "not in the
	# list" carries no information there and the cross-check below would report a
	# harness fault for a perfectly good grid. Satisfying every rule IS being a
	# solution; the membership test only ever added a second opinion.
	if (faults == 0 && !exh) { print (is_bonus() ? "bonus-ok" : "ok") >> catfile; exit 0 }
	if (faults == 0 && !(key in member)) {
		print "corpus-inconsistent" >> catfile
		say(" --------------------------------------------------")
		say(" HARNESS PROBLEM, not yours: the grid printed for \"" clue "\" satisfies every")
		say(" rule of the puzzle, but the corpus does not list it. The corpus is supposed")
		say(" to be exhaustive, so the reference (or this checker) needs fixing.")
		say("   grid: " key)
		exit 2
	}
	verdict(F_CAT, F_MSG, F_WHY sprintf(" (%d rule%s broken in total.)", faults, (faults == 1 ? "" : "s")))
	exit 1
}
AWK_END

# ---------------------------------------------------------------------------
# Normalise the corpus and self-check the reference. With --probes-only there
# is no corpus: an empty case list, and none of the floors below, which are
# about a corpus.
PREP_RC=0
if [ "$PROBES_ONLY" -eq 1 ]; then
	: > "$T/cases"
else
	RUSH01_ORACLE="$ORACLE" RUSH01_REQ="$T/req" LC_ALL=C awk -f "$T/rush01.awk" -v mode=prep \
		-v maxsize="$MAXSIZE" -v mandn="$MANDATORY_N" -v maxcases="$MAXCASES" -v casefile="$T/cases" \
		-v statsfile="$T/stats" "$T/corpus"
	PREP_RC=$?
fi
if [ "$PREP_RC" -eq 3 ]; then
	echo "rush01_check: this case list cannot be judged without --oracle — see above."
	echo "              Nothing about your program was checked."
	exit 2
fi
if [ "$PREP_RC" -eq 4 ]; then
	echo "rush01_check: the reference could not check the case list — see above. This"
	echo "              is a harness problem; nothing about your program was checked."
	exit 2
fi
if [ "$PREP_RC" -ne 0 ]; then
	echo "rush01_check: the case list itself is wrong — see above. Nothing about"
	echo "              your program was checked."
	exit 2
fi

TOTAL=0; SOLVABLE=0; UNSOLVABLE=0; BONUS=0
[ -f "$T/stats" ] && read -r TOTAL SOLVABLE UNSOLVABLE BONUS < "$T/stats"

# A corpus with no solvable case would pass a program that prints Error and
# nothing else; a corpus with no unsolvable case would never check the error path
# at all. Either way the layer would report a green it has not earned — the same
# reasoning as the MIN_DIFF_CASES guard in tools/rust_diff.sh, which exists
# because an empty corpus compares equal to an empty corpus.
if [ "$PROBES_ONLY" -eq 0 ] && { [ "$TOTAL" -lt 8 ] || [ "$SOLVABLE" -lt 1 ] || [ "$UNSOLVABLE" -lt 1 ]; }; then
	echo "rush01_check: FAIL — unusable case list ($SRC):"
	echo "               $TOTAL case(s), $SOLVABLE solvable, $UNSOLVABLE with no solution."
	echo "               A list with no solvable case validates a program that only ever"
	echo "               prints Error; one with no unsolvable case never tests the error"
	echo "               path. This layer reports failure rather than a false green."
	exit 2
fi

# ---------------------------------------------------------------------------
# Runaway guard for everything below, set ONCE rather than per run (a subshell
# per case would cost one fork per case and buy nothing). `ulimit -f` bounds any
# file this shell or its children write: a solver that prints in a loop is killed
# by the kernel with SIGXFSZ (exit 153) instead of filling the test tmpdir at
# page-cache speed for the whole Bazel timeout. It counts 512-byte blocks.
#
# 1 MiB, not the 4 MiB the other runners use, because this layer runs the program
# HUNDREDS of times: at 4 MiB a printing loop spends about two minutes of real
# time writing pages that are thrown away, which on its own can blow the layer's
# Bazel budget. A correct answer here is a few dozen bytes, so 1 MiB is still
# four orders of magnitude above anything legitimate. The corpus is already
# written by this point, so the limit cannot truncate it.
RUNAWAY_CAP_MIB=1
ulimit -f 2048 2>/dev/null || true

OUT="$T/out"
ERRF="$T/err"
CATS="$T/cats"
: > "$CATS"

BLOCK="$T/block"
FAILS=0
TIMEOUTS=0
TIMEOUTS_LARGE=0
# Bonus-size runs that ran out of time, and the bonus-size cases not tried once
# MAX_TIMEOUTS of those had: a slow bonus is excused, but not forever -- 26 of
# them at 10s each once took the sweep to 263s of a 300s limit, with nothing on
# screen saying why.
BONUS_TIMEOUTS=0
BONUS_SKIPPED=0
HARNESS=0
RUN=0
SWEPT=0
STOPPED=0

# Run the student once. Not a subshell: this is called once per case and a fork
# here would double the cost of the sweep.
#
# STDIN IS PINNED TO /dev/null, and that is not hygiene — it is the difference
# between this layer working and this layer reporting a false green. The sweep
# below is a `while read` loop whose OWN stdin is the case file, and a child
# inherits it: a program that reads stdin therefore eats the remaining cases,
# the loop ends after one iteration, and the runner prints
# "OK — 1 case(s) validated" and exits 0. A layer whose whole purpose is to
# refuse a green it has not earned must not have a hole shaped like that.
# tools/argv_table.sh pins it for exactly this reason (its loop reads scenarios
# the same way) and tools/valgrind_test.sh for the related one: a program whose
# behaviour depends on an inherited stdin behaves differently under `bazel test`,
# under `bazel run` and in a terminal, and a test must not be where that first
# shows up. rush01 is handed its input in argv and has no business on stdin, so
# there is nothing legitimate to inherit.
run_one() {
	# No time left to START this run: nothing is judged, and the sweep stops.
	if ! rl_tmo "$TMO"; then
		OUT_OF_TIME=start
		RUN_RC=0
		return 0
	fi
	rl_run "$BIN" "$@" > "$OUT" 2> "$ERRF" < /dev/null
	RUN_RC=$?
	# How it ended, from waitpid() (tools/exit_status): a return of any number
	# is a return; a signal, this run's cap or the output budget is not.
	rl_classify "$RUN_RC"
	if [ "$RL_CAUSE" = noexec ]; then
		echo "rush01_check.sh: the program $RL_WHY" >&2
		exit 2
	fi
	# Killed by the TEST's limit rather than by this run's own cap: the sweep
	# as a whole ran out of time, whatever this one case was doing.
	[ "$RL_CAUSE" = timeout ] && [ "$RL_CLAMPED" = 1 ] && OUT_OF_TIME=during
	# The sentinel that lets awk see a missing final newline (see the judge-mode
	# comment). Skipped after a SIGXFSZ kill: the capture is already at the
	# ulimit, so appending would kill this shell too.
	[ "$RL_CAUSE" = runaway ] || printf '@' >> "$OUT"
	# Written to stderr: never graded, but said (rl_stderr), named as a
	# failing run is: PROBE k/N and CASE n/N, two lists, two denominators.
	if [ -n "$PROBE_KIND" ]; then
		rl_stderr "$ERRF" "probe $((PRUN + 1))/$NPROBE, $# argument(s)"
	else
		rl_stderr "$ERRF" "case $((RUN + 1))/$TOTAL, argv \"$*\""
	fi
}

# Judge whatever run_one just captured. $1 case id, $2 clue string, $3 solutions,
# $4 a description of the argv when it is not a plain clue string, $5 0 when the
# solutions are witnesses rather than all of them, $6 1 for a case graded only if
# attempted, $7 the board's side (0 when the input is malformed).
#
# Its report goes to $BLOCK, and judge() hands the block to rl_block: printed
# while DIFF_MAX_ROWS allows, and kept whole for test.outputs either way.
judge() {
	: > "$BLOCK"
	judge_one "$@" > "$BLOCK"
	_jr=$?
	[ ! -s "$BLOCK" ] || rl_block "$BLOCK"
	return "$_jr"
}
judge_one() {
	_id="$1"; _clue="$2"; _sols="$3"; _argvdesc="${4:-}"; _exh="${5:-1}"; _bonus="${6:-0}"
	_side="${7:-0}"
	# A probe is named PROBE k/N, a corpus case CASE n/N: two lists, two
	# denominators (see the probes, below).
	_word=CASE
	[ -z "$PROBE_KIND" ] || _word=PROBE

	if [ "$RL_CAUSE" = runaway ]; then
		FAILS=$((FAILS + 1))
		echo "runaway" >> "$CATS"
		# Counted with the timeouts: a loop whose exit condition is never reached
		# is the same defect whether it prints or not, and either way there is no
		# point spending the layer's whole budget rediscovering it once per case.
		TIMEOUTS=$((TIMEOUTS + 1))
		echo " --------------------------------------------------"
		echo " $_word $_id  argv: \"$_clue\"${_argvdesc:+  -- $_argvdesc}"
		echo "   RUNAWAY OUTPUT: it kept printing past a ${RUNAWAY_CAP_MIB} MiB budget and was stopped."
		echo "                   A correct answer here is one grid or the word Error."
		return 1
	fi
	# A bonus-size case that runs out of time is reporting SLOWNESS, not a wrong
	# answer, and slowness on an optional part of the subject is not a verdict on
	# the required one. An exhaustive search that is fine at 4x4 can take minutes
	# at 7x7 while being perfectly correct — failing the mandatory sweep for that
	# would punish attempting the bonus at all. It also must not count toward
	# MAX_TIMEOUTS, or three slow bonus cases would abandon the whole sweep.
	# (--max-size 9 clears _bonus, so the 9x9 bonus target, ex00_bonus_9x9, still
	# holds them to it.)
	if [ "$RL_CAUSE" = timeout ] && [ "$_bonus" -eq 1 ]; then
		echo "bonus-slow" >> "$CATS"
		BONUS_TIMEOUTS=$((BONUS_TIMEOUTS + 1))
		return 0
	fi
	# The sentence under a TIMEOUT depends on the board. Up to the mandatory
	# MANDATORY_N x MANDATORY_N any program that stops finishes in
	# milliseconds, so running out of time says something is wrong. Above it, a
	# correct program can simply be slow: from 7x7 up a board has far more
	# arrangements than a 4x4, and a measured correct first attempt took over a
	# minute on one 8x8 case. Telling that student their program never stops
	# would send them hunting a bug they do not have.
	if [ "$RL_CAUSE" = timeout ]; then
		FAILS=$((FAILS + 1))
		TIMEOUTS=$((TIMEOUTS + 1))
		echo "timeout" >> "$CATS"
		[ "$_side" -gt "$MANDATORY_N" ] && TIMEOUTS_LARGE=$((TIMEOUTS_LARGE + 1))
		echo " --------------------------------------------------"
		echo " $_word $_id  argv: \"$_clue\"${_argvdesc:+  -- $_argvdesc}"
		echo "   TIMEOUT: it did not finish within ${RL_TMO}s."
		if [ "$_side" -gt "$MANDATORY_N" ]; then
			echo "            It ran out of time on a large board (${_side}x${_side}). A correct"
			echo "            program can take far longer on one than on a 4x4, so this says"
			echo "            the answer did not arrive in time, not that it would be wrong."
		else
			echo "            Every case in this layer is one small board; a search that"
			echo "            terminates finishes it in milliseconds."
		fi
		return 1
	fi
	if [ "$RL_CAUSE" = signal ] || [ "$RL_CAUSE" = stopped ]; then
		FAILS=$((FAILS + 1))
		echo "crash" >> "$CATS"
		echo " --------------------------------------------------"
		echo " $_word $_id  argv: \"$_clue\"${_argvdesc:+  -- $_argvdesc}"
		echo "   CRASH: it $RL_WHY."
		echo "          Whatever it printed first does not matter: a crash is a failure."
		[ -s "$ERRF" ] && rl_excerpt "$ERRF" 8 "case-$(printf '%s' "$_id" | tr '/' '-')-stderr.txt" "          "
		return 1
	fi

	RUSH01_ORACLE="$ORACLE" RUSH01_REQ="$T/req" RUSH01_Q_ERROR="$Q_ERROR" \
		LC_ALL=C awk -f "$T/rush01.awk" -v mode=judge \
		-v clue="$_clue" -v sols="$_sols" \
		-v caseid="$_id" -v argvdesc="$_argvdesc" -v probe="$PROBE_KIND" \
		-v exh="$_exh" -v maxsize="$MAXSIZE" -v mandn="$MANDATORY_N" \
		-v outfile="$OUT" -v errfile="$ERRF" -v catfile="$CATS" \
		"$OUT" "$ERRF"
	_jrc=$?
	# The right answer, and a message the call said a valid run does not get
	# (--stderr-empty): the message is the fault.
	if [ "$_jrc" -eq 0 ] && rl_stderr_noisy "$ERRF"; then
		FAILS=$((FAILS + 1))
		echo "wrote-to-stderr" >> "$CATS"
		echo " --------------------------------------------------"
		echo " $_word $_id  argv: \"$_clue\"${_argvdesc:+  -- $_argvdesc}"
		echo "   the right answer, and it wrote to standard error, where this check"
		echo "   requires nothing:"
		rl_excerpt "$ERRF" 6 "case-$(printf '%s' "$_id" | tr '/' '-')-stderr.txt" "          "
		return 1
	fi
	if [ "$_jrc" -eq 0 ]; then
		return 0
	fi
	if [ "$_jrc" -eq 2 ]; then
		HARNESS=$((HARNESS + 1))
		return 2
	fi
	FAILS=$((FAILS + 1))
	return 1
}

# ---------------------------------------------------------------------------
# The sweep. Every clue string comes out of the case file and is handed to the
# program as ONE argument — the interface the subject specifies — which is why
# nothing here goes near sh_test's whitespace tokenisation.
TAB=$(printf '\t')
# CNSOL is read only to position CSOLS and CCLUE: the record is
# "<isbonus>\t<n>\t<nsol>\t<exh>\t<sols>\t<clue>" and the clue must be LAST so
# that the spaces it is made of survive (with IFS=tab, a space is not a
# separator, and `read` gives every remaining character to the final variable).
OUT_OF_TIME=""
PROBE_KIND=""

# ---------------------------------------------------------------------------
# The probes: inputs a corpus line cannot carry. "No argument" and "two
# arguments" are argc, not the content of one argument; a tab, and blanks the
# TAB-separated corpus would have to keep verbatim, are safer built here than
# written into a file. Every probe's answer is Error, by construction: none of
# them is "the only acceptable input".
#
# ONE LIST, probe_list, read by both replays through probe_do: the plain one
# judges each probe (probe_one, after the sweep) and the one under a memory
# checker runs each (mem_probe, after its sweep). The memory replay once
# carried its own copy of the argc probes, and kept the old two-argument
# vector when the plain one moved to a clue string accepted alone (finding
# 153): two lists, and the memory twin replayed inputs the target it stands
# for no longer runs.
#
# They are counted apart from the corpus's cases, each with its own
# denominator: the sweep once labelled its cases "CASE n/968" and then reported
# 971 validated, the three probes counted in one number and not the other.
#
# probe_list MODE -- every probe asked for (--probe-argc, --probe-shape), in
# order, each handed to probe_do MODE KIND DESC CLUE [ARG...]. CLUE is the one
# argument as a report shows it ("" when there is not exactly one), DESC what
# the probe varies, the ARGs the program's arguments.
probe_list() {
	_plm=$1
	if [ "$PROBE_ARGC" -eq 1 ]; then
		probe_do "$_plm" argc "(no argument at all)" ""
		probe_do "$_plm" argc2 "(two arguments, each \"$BASE\")" "" "$BASE" "$BASE"
		probe_do "$_plm" argc "(one empty argument)" "" ""
	fi
	if [ "$PROBE_SHAPE" -eq 1 ]; then
		probe_do "$_plm" shape "a space before the first value" " $BASE" " $BASE"
		probe_do "$_plm" shape "a space after the last value" "$BASE " "$BASE "
		_pv=$(printf '%s' "$BASE" | sed 's/ /  /')
		probe_do "$_plm" shape "two spaces between two values" "$_pv" "$_pv"
		_pv=$(printf '%s' "$BASE" | sed "s/ /$TAB/")
		probe_do "$_plm" shape "a tab between two values" "$_pv" "$_pv"
		probe_do "$_plm" shape "a '0' before the first value" "0$BASE" "0$BASE"
		probe_do "$_plm" shape "a '+' before the first value" "+$BASE" "+$BASE"
	fi
}
# probe_do MODE KIND DESC CLUE [ARG...] -- one probe, for the replay MODE
# names: count (NPROBE, before either replay), judge (the plain replay's
# probe_one, after its sweep) or memory (mem_probe, after its sweep).
probe_do() {
	_pdm=$1
	shift
	case "$_pdm" in
		count) NPROBE=$((NPROBE + 1)) ;;
		judge) probe_one "$@" ;;
		memory) mem_probe "$@" ;;
	esac
}
NPROBE=0
PRUN=0
PFAILS=0
BASE=""
probe_list count
if [ "$NPROBE" -gt 0 ]; then
	# The vector the probes are built from. --gate-arg's (the subject's own
	# example, where a target passes one), else the first solvable board of
	# the mandatory size the corpus holds: in both cases a clue string the
	# program has to ACCEPT on its own, so that a probe can catch a program
	# that only looks at part of what it was given.
	if [ "$GATE_ARG_SET" -eq 1 ]; then
		BASE=$GATE_ARG
	else
		BASE=$(awk -F"$TAB" -v n="$MANDATORY_N" '$1 == 0 && $2 == n && $3 > 0 { print $6; exit }' "$T/cases")
	fi
	if [ -z "$BASE" ]; then
		echo "rush01_check: HARNESS FAILURE — no clue string the program must accept on"
		echo "              its own was found to build the probes from (pass --gate-arg)."
		exit 2
	fi
fi

# mem_case WORD ID DESC ARG... -- one run under the memory checker
# (rl_mem_run), and its block when it went wrong: the argv, and the checker's
# report. The grid is not judged: that is the plain sweep's finding. WORD is
# CASE for a corpus case and PROBE for a probe, ID its n/N, DESC what a probe
# varies.
mem_case() {
	_mw=$1; _mid=$2; _mdesc=$3
	shift 3
	RUN=$((RUN + 1))
	if [ "$_mw" = PROBE ]; then
		rl_mem_run --what "probe $_mid" -- "$@"
	else
		rl_mem_run --what "case $_mid" -- "$@"
	fi
	[ "$RL_MEM_BAD" = 1 ] || return 0
	FAILS=$((FAILS + 1))
	{
		echo " --------------------------------------------------"
		if [ "$#" -eq 1 ]; then
			# Every byte visible (rl_vis): a shape probe holds a tab.
			echo " $_mw $_mid  argv: \"$(printf '%s' "$1" | rl_vis arg)\"${_mdesc:+  -- $_mdesc}  [$RL_MEM_KIND]"
		else
			echo " $_mw $_mid  argv: $# argument(s)${_mdesc:+  -- $_mdesc}  [$RL_MEM_KIND]"
		fi
		rl_mem_report
	} > "$BLOCK"
	rl_block "$BLOCK"
}

# mem_probe KIND DESC CLUE [ARG...] -- a probe under a memory checker
# (probe_list memory): every probe runs, none is sampled.
mem_probe() {
	_mpd=$2
	shift 3
	[ -z "$RL_STOP" ] || return 0
	rl_sweep_next "$TMO" || return 0
	PRUN=$((PRUN + 1))
	mem_case PROBE "$PRUN/$NPROBE" "$_mpd" "$@"
}

# shellcheck disable=SC2034
while IFS="$TAB" read -r CBONUS CN CNSOL CEXH CSOLS CCLUE; do
	SWEPT=$((SWEPT + 1))
	# UNDER A MEMORY CHECKER the case runs when it is in the sample, and only
	# memory and how it ended are judged.
	if [ -n "$RL_MEM" ]; then
		rl_mem_pick "$SWEPT" "$TOTAL" || continue
		rl_sweep_next "$TMO" || { SWEPT=$((SWEPT - 1)); break; }
		mem_case CASE "$SWEPT/$TOTAL" "" "$CCLUE"
		[ -z "$RL_STOP" ] || break
		continue
	fi
	# The bonus cap: MAX_TIMEOUTS bonus-size runs have run out of time, so the
	# rest of the bonus sizes are not tried -- the 4x4 cases still are.
	if [ "$CBONUS" -eq 1 ] && [ "$BONUS_TIMEOUTS" -ge "$MAX_TIMEOUTS" ]; then
		BONUS_SKIPPED=$((BONUS_SKIPPED + 1))
		echo "bonus-skipped" >> "$CATS"
		continue
	fi
	run_one "$CCLUE"
	# Out of time for the whole TEST, not this case's own cap: this case is
	# not judged -- its time was cut short, not spent -- and the sweep stops
	# and says where it got to (below). SWEPT counts the cases STARTED, as
	# rl_sweep_stopped reads it: one the time ran out in was started and is
	# the case it names; one there was no time left to start was not.
	if [ -n "$OUT_OF_TIME" ]; then
		[ "$OUT_OF_TIME" != start ] || SWEPT=$((SWEPT - 1))
		break
	fi
	RUN=$((RUN + 1))
	# is_bonus() and the board's side are decided once, in awk, where the clue
	# string is parsed. The shell just carries the answers.
	judge "$RUN/$TOTAL" "$CCLUE" "$CSOLS" "" "$CEXH" "$CBONUS" "$CN" || true
	if [ "$TIMEOUTS" -ge "$MAX_TIMEOUTS" ]; then
		STOPPED=1
		echo " --------------------------------------------------"
		if [ "$TIMEOUTS_LARGE" -eq "$TIMEOUTS" ]; then
			echo " STOPPED after $TIMEOUTS run(s) that ran out of time on a large board."
			echo " The remaining $((TOTAL - RUN)) case(s) were not tried: at this speed they"
			echo " would spend the layer's whole time budget, and the cases above already"
			echo " say what there is to say."
		else
			echo " STOPPED after $TIMEOUTS run(s) that never finished (a hang, or a loop"
			echo " printing without end). The remaining $((TOTAL - RUN)) case(s) were not"
			echo " tried: with a solver that does not terminate, running them would only"
			echo " spend the layer's whole time budget to print the same thing again."
		fi
		break
	fi
done < "$T/cases"

# Under a memory checker: the probes asked for (probe_list, the list the
# plain replay judges), every one of them, and the verdict.
if [ -n "$RL_MEM" ]; then
	rl_mem_count "$TOTAL"
	_mn=$((TOTAL + NPROBE))
	RL_MEM_N=$((RL_MEM_N + NPROBE))
	[ -n "$RL_STOP" ] || probe_list memory
	rl_tally
	if [ -n "$RL_STOP" ]; then
		echo ""
		rl_mem_stopped "$RUN"
		exit 1
	fi
	if [ "$RL_MEM" = sanitized ] && [ "$RUN" -ne "$_mn" ]; then
		echo "rush01_check: HARNESS FAILURE — $RUN of $_mn case(s) ran under the sanitizer," >&2
		echo "              and the sweep did not stop early." >&2
		exit 2
	fi
	rl_mem_tally "$RUN" "$_mn"
	_mt=$?
	# The sixteen values are an argument: what the sanitizer saw of it.
	rl_mem_argv_note 0
	exit "$_mt"
fi

# The loop must have judged every case prep selected. It cannot, unless something
# consumed the case file out from under `read` — which is precisely what a child
# inheriting this loop's stdin used to do (see run_one). That bug's signature was
# a GREEN run reporting one case, so the assertion is kept even though the cause
# is fixed: this layer's entire job is to refuse a pass it has not earned, and a
# silently shortened sweep is the one failure it cannot afford to report as OK.
if [ -n "$OUT_OF_TIME" ]; then
	# The test's own time limit, not a verdict on any one case: say where the
	# sweep got to, and fail -- the cases after it were never judged.
	echo " --------------------------------------------------"
	if [ "$OUT_OF_TIME" = start ]; then
		RL_STOP=start
	else
		RL_STOP=budget
	fi
	# The cases already judged wrong are a verdict whatever the machine
	# was doing: with any, the report does not read as "ran out of time".
	# The runs that ran out of their own limit, a bonus size's included,
	# are this sweep's own count (judge_one's CATS lines; it calls no
	# rl_hang): without it the stop said every case before it "ended within
	# its own limit" (V84). Those of a 4x4 are in $FAILS, and left out of
	# the cases judged wrong: not judged (ruling R4), and named apart.
	_hung=$(awk '$0 == "timeout" || $0 == "bonus-slow" { c++ } END { print c + 0 }' "$CATS")
	_tmo=$(awk '$0 == "timeout" { c++ } END { print c + 0 }' "$CATS")
	rl_sweep_stopped "$SWEPT" "$TOTAL" "$((FAILS - _tmo))" "$_hung"
	STOPPED=1
fi

if [ "$STOPPED" -eq 0 ] && [ "$SWEPT" -ne "$TOTAL" ]; then
	echo "rush01_check: HARNESS FAILURE — the sweep judged $SWEPT of the $TOTAL case(s) it"
	echo "              selected, and did not stop early. The case list was consumed by"
	echo "              something other than this loop, so the cases that were checked are"
	echo "              not the cases that were meant to be. Nothing here is a verdict on"
	echo "              your program."
	exit 2
fi

# ---------------------------------------------------------------------------
# The probes the plain replay judges, from probe_list (defined before the
# sweep, with BASE, the vector they are built from).
#
# probe_one KIND DESC CLUE [ARG...] -- a probe of the plain replay (probe_list
# judge): run the program on ARGs and judge its answer against Error.
probe_one() {
	_pk=$1; _pd=$2; _pc=$3; shift 3
	[ -z "$OUT_OF_TIME" ] || return 0
	[ "$TIMEOUTS" -lt "$MAX_TIMEOUTS" ] || return 0
	PROBE_KIND=$_pk
	run_one "$@"
	if [ -n "$OUT_OF_TIME" ]; then
		PROBE_KIND=""
		return 0
	fi
	PRUN=$((PRUN + 1))
	_pf=$FAILS
	judge "$PRUN/$NPROBE" "$_pc" "-" "$_pd" || true
	PROBE_KIND=""
	[ "$FAILS" -eq "$_pf" ] || PFAILS=$((PFAILS + 1))
}

if [ "$NPROBE" -gt 0 ] && [ "$TIMEOUTS" -lt "$MAX_TIMEOUTS" ] && [ -z "$OUT_OF_TIME" ]; then
	probe_list judge
	if [ -n "$OUT_OF_TIME" ]; then
		echo " --------------------------------------------------"
		rl_overrun "the probes, after the sweep"
	fi
fi

# ---------------------------------------------------------------------------
# Verdict.
rl_tally

# One line per verdict was appended to $CATS; fold it into a census so the shape
# of the failure is visible even when only five blocks were printed.
if [ -s "$CATS" ]; then
	CENSUS=$(awk '$0 != "ok" && $0 != "bonus-ok" && $0 != "bonus-absent" && $0 != "bonus-slow" && $0 != "bonus-skipped" { c[$0]++ } END { s = ""; for (k in c) s = s "  " k " x" c[k]; print s }' "$CATS")
else
	CENSUS=""
fi

# The note on what the runs wrote to stderr (rl_stderr_note): once a probe
# has run, the runs it counts are not all corpus cases, so it counts runs,
# and names the first as CASE n/N or PROBE k/N name it.
stderr_note() {
	if [ "$PRUN" -gt 0 ]; then
		rl_stderr_note "run(s)"
	else
		rl_stderr_note
	fi
}

# What the probes did, in their own count (see the probes, above).
probe_tally() {
	[ "$PRUN" -gt 0 ] || return 0
	echo "              and $PRUN probe(s), argument lists no corpus line can hold:"
	echo "              $((PRUN - PFAILS)) of them answered Error, as each must."
}
if [ "$PROBES_ONLY" -eq 1 ] && [ "$FAILS" -eq 0 ] && [ "$HARNESS" -eq 0 ] && [ -z "$OUT_OF_TIME" ]; then
	echo "rush01_check: OK — $LABEL: all $PRUN probe(s) answered Error; $SRC"
	rl_stderr_rule
	stderr_note
	exit 0
fi
if [ "$FAILS" -eq 0 ] && [ "$HARNESS" -eq 0 ] && [ -z "$OUT_OF_TIME" ]; then
	echo "rush01_check: OK — $LABEL: $RUN case(s) validated ($SOLVABLE solvable, $UNSOLVABLE with no"
	echo "              solution$([ "$BONUS" -gt 0 ] && echo ", $BONUS bonus-size case(s)")); $SRC"
	probe_tally
	if [ -n "$ORACLE" ]; then
		echo "              Each printed grid was checked to be a Latin square and to satisfy"
		echo "              all of its clues; up to 6x6, also to be one of the grids the"
		echo "              reference enumerated."
	else
		echo "              Each printed grid was checked to be one of the grids the case list"
		echo "              gives for its clues. No --oracle, so no rule was re-derived."
	fi
	# The bonus tally is information, not a verdict: both numbers are passes. It
	# is here so a student who DID implement other sizes can see it was noticed,
	# and one who did not can see the layer looked and found nothing to grade.
	if [ "$BONUS" -gt 0 ]; then
		# awk, not `grep -c ... || echo 0`: grep already prints 0 when it matches
		# nothing AND exits 1, so the fallback appended a SECOND zero and the
		# comparison below then choked on "0\n0".
		_btried=$(awk '$0 == "bonus-ok" { c++ } END { print c + 0 }' "$CATS")
		_babsent=$(awk '$0 == "bonus-absent" { c++ } END { print c + 0 }' "$CATS")
		_bslow=$(awk '$0 == "bonus-slow" { c++ } END { print c + 0 }' "$CATS")
		[ "$_bslow" -gt 0 ] && echo "              bonus: $_bslow bonus-size case(s) ran out of time; not counted either way."
		[ "$BONUS_SKIPPED" -gt 0 ] && {
			echo "              bonus: $BONUS_SKIPPED bonus-size case(s) not attempted: the program ran out"
			echo "              of time on $BONUS_TIMEOUTS of them, so the rest would only have spent"
			echo "              this test's time limit. The 4x4 cases were all still judged."
		}
		if [ "$_btried" -gt 0 ]; then
			echo "              bonus: $_btried bonus-size grid(s) solved correctly$([ "$_babsent" -gt 0 ] && echo ", $_babsent answered Error")."
		elif [ "$_babsent" -gt 0 ]; then
			# Only when some answered at all: with every one slow or not
			# tried, "all 0 answered Error" said nothing true.
			echo "              bonus: not attempted — all $_babsent bonus-size input(s) answered"
			echo "              Error, which is a correct answer for a 4x4-only program."
		fi
	fi
	rl_stderr_rule
	stderr_note
	exit 0
fi

if [ "$HARNESS" -gt 0 ] && [ "$FAILS" -eq 0 ] && [ -z "$OUT_OF_TIME" ]; then
	echo "rush01_check: HARNESS FAILURE — the case list and this checker disagree on"
	echo "              $HARNESS case(s). Nothing above is a verdict on your program."
	[ -n "$CENSUS" ] && echo "              by fault:$CENSUS"
	exit 2
fi

if [ -n "$OUT_OF_TIME" ] && [ "$FAILS" -eq 0 ]; then
	echo "rush01_check: FAIL — $LABEL: did not finish; $RUN case(s) and $PRUN probe(s) judged, none wrong; $SRC"
elif [ "$PROBES_ONLY" -eq 1 ]; then
	echo "rush01_check: FAIL — $LABEL: $PFAILS of $PRUN probe(s) judged wrong; $SRC"
else
	echo "rush01_check: FAIL — $LABEL: $((FAILS - PFAILS)) of $RUN case(s) judged wrong; $SRC"
	probe_tally
fi
[ -n "$CENSUS" ] && echo "              by fault:$CENSUS"
if [ "$HARNESS" -gt 0 ]; then
	echo "              ($HARNESS further case(s) are a HARNESS problem, not yours.)"
fi
if [ "$BONUS_SKIPPED" -gt 0 ]; then
	echo "              ($BONUS_SKIPPED bonus-size case(s) not attempted: the program ran out of"
	echo "               time on $BONUS_TIMEOUTS of them.)"
fi
stderr_note
# The one clues.tsv rule (rl_clues): '#' lines are maintainers' and never
# printed, only the hint column is, and at most CLUE_MODE (3) of them. This
# runner printed the file verbatim, comments and all, twenty lines deep.
rl_clues "$HINTS" "" "" "$CASE_NAME"
exit 1
