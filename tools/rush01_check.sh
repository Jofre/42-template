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
# Usage:
#   rush01_check.sh --bin PATH
#                   { --oracle PATH [--oracle-fn NAME] [--seed N] [--count N]
#                   | --corpus FILE }
#                   [--max-size N] [--max-cases N] [--probe-argc]
#                   [--clues FILE] [--label TEXT] [--timeout SECS]
#                   [--gate-differ F --gate-bin P --gate-expected F
#                    [--gate-arg STR | --gate-arg-file F]]
#
#   --bin PATH          the student's compiled rush01
#   --oracle PATH       the Rust reference (//oracle:oracle); asked for the
#                       corpus as `oracle <fn> <seed> <count>`
#   --oracle-fn NAME    reference function name (default rush01_solve)
#   --seed N            reference seed (default 1) — deterministic by construction
#   --count N           sizes the reference's random tail (default 400)
#   --corpus FILE       use this corpus file instead of running the reference
#   --clues FILE        pedagogic hints (a clues.tsv), printed on failure --
#                       the same meaning as in every other runner here
#   --max-size N        REQUIRE grids up to N x N (default 4). Larger sizes are
#                       still run and still judged if answered with a grid; see
#                       "THE BONUS IS GRADED ONLY IF IT WAS ATTEMPTED" below.
#   --max-cases N       replay at most N corpus cases, spread evenly (0 = all)
#   --probe-argc        also assert the three argv SHAPES the corpus cannot
#                       express: no argument, two arguments, one empty argument.
#                       Opt-in, because "no argument at all" is the runner's
#                       reading of "any other input is an error", not a
#                       transcript the subject prints.
#   --label TEXT        what to call this run in messages
#   --timeout SECS      per-run wall-clock budget (default 10, or RUSH01_TIMEOUT)
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
#   RUSH01_MAX_FAILS   detailed failure blocks to print (default 5). Same reason
#                      diff_output.sh grew DIFF_MAX_ROWS: against a fresh stub
#                      EVERY case fails, and a wall of 900 identical blocks
#                      buries the one thing the student needed to read.
#   RUSH01_MAX_TIMEOUTS  give up after this many runs fail to finish (default 3),
#                      counting both hangs and endless printing. A solver that
#                      does not terminate would otherwise burn cases x timeout
#                      seconds before Bazel killed the layer with nothing
#                      printed at all.
#   NO_SKIP=1          force every gate open (see the gate below)
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
# single case is replayed: if the reference is wrong, this layer says so rather
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
require awk basename cat cp head mktemp rm sed

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
# Sizes 1..MAXSIZE are REQUIRED to be solved. The mandatory 4x4 is always
# required whatever this says; 0 therefore means "the mandatory board and
# nothing else", which is the right default because every other size is a bonus.
# See is_bonus() in the awk program.
MAXSIZE="0"
MAXCASES="0"
PROBE_ARGC=0
LABEL=""
TMO="${RUSH01_TIMEOUT:-10}"
GATE_DIFFER=""
GATE_BIN=""
GATE_EXPECTED=""
GATE_ARG=""
GATE_ARG_SET=0
GATE_ARG_FILE=""
MAX_FAILS="${RUSH01_MAX_FAILS:-5}"
MAX_TIMEOUTS="${RUSH01_MAX_TIMEOUTS:-3}"

# A stray bare digit in the argument list is the fingerprint of the tokenisation
# accident described in the header: someone wrote the 16-digit clue vector into
# sh_test `args` unquoted and Bazel handed us "4" "3" "2" "1" ... as separate
# words. Diagnose it by name — the generic "unknown option: 3" that every other
# runner prints has cost this repo three debugging sessions already.
tokenised_hint() {
	cat >&2 <<-'EOT'

	  This looks like a clue vector that was split into separate arguments.
	  rush01 takes ONE argument containing 16 space-separated digits, and Bazel
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
			if [ "$FN_SET" -eq 0 ]; then FN="$2"; FN_SET=1; else FN="$FN $2"; fi
			shift 2 ;;
		--seed) need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--corpus) need "$1" "$#"; CORPUS="$2"; shift 2 ;;
		--clues) need "$1" "$#"; HINTS="$2"; shift 2 ;;
		--max-size) need "$1" "$#"; MAXSIZE="$2"; shift 2 ;;
		--max-cases) need "$1" "$#"; MAXCASES="$2"; shift 2 ;;
		--probe-argc) PROBE_ARGC=1; shift ;;
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--timeout) need "$1" "$#"; TMO="$2"; shift 2 ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-arg) need "$1" "$#"; GATE_ARG="$2"; GATE_ARG_SET=1; shift 2 ;;
		--gate-arg-file) need "$1" "$#"; GATE_ARG_FILE="$2"; shift 2 ;;
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

if [ -z "$CORPUS" ] && [ -z "$ORACLE" ]; then
	echo "rush01_check: need either --corpus FILE or --oracle PATH" >&2
	exit 2
fi

if [ ! -x "$BIN" ]; then
	echo "rush01_check: FAIL — '$BIN' is not an executable file."
	echo "               Nothing could be run, so nothing was checked."
	exit 1
fi

# awk carries the whole judgement (grid parsing, the Latin-square check, the
# visibility arithmetic). Without it this layer cannot report a pass it can stand
# behind, so there is no quiet-skip path for it at all.
if ! command -v awk >/dev/null 2>&1; then
	echo "rush01_check: FAIL — no awk on this machine, and every check in this"
	echo "               layer is written in awk. It cannot report a pass."
	exit 2
fi

# An inner per-run timeout, well under Bazel's, so a solver that never terminates
# is reported as one rather than surfacing as an opaque Bazel timeout with
# nothing in the log. A 4x4 board is small enough that any terminating solver
# finishes in milliseconds; the generous default is for a very slow one under a
# sanitizer build, not for a hung one.
if command -v timeout >/dev/null 2>&1; then
	RUNNER="timeout -s KILL $TMO"
else
	# NO_SKIP=1: running bare silently removes the hang guard, and a layer must
	# never weaken itself into a green without saying so. Same shape as the
	# probe in tools/argv_table.sh -- including its exit status, which this used
	# to disagree with. Every one of the sixteen NO_SKIP refusals in tools/ exits
	# 1, and that is right: the forced sweep exists to turn a quiet layer into a
	# visible FAILURE, and 2 means "the harness is broken", which selftest.sh's
	# want_red deliberately refuses to count as a detection.
	if [ "${NO_SKIP:-0}" = "1" ]; then
		echo "NO_SKIP set: no 'timeout' command available, so a solver that never"
		echo "             returns could not be detected, and this layer must not"
		echo "             report a pass it cannot stand behind."
		exit 1
	fi
	echo "rush01_check: NOTE — no 'timeout' command; runs are unguarded against hangs."
	RUNNER=""
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM

# ---------------------------------------------------------------------------
# Correctness gate: run the exercise's OWN output fixture first, and skip if it
# is already red.
#
# Identical reasoning to tools/rust_diff.sh and tools/ilp32_test.sh. The
# exercise's *_output layer is the one with pedagogic value — the subject's own
# worked example, a labelled table, hints attached. This layer sweeps hundreds of
# generated clue vectors. A student whose basic case does not work yet learns
# nothing from 900 further failures that all say the same thing; they learn it
# from the one case the subject printed for them.
#
# Fails OPEN by design: no gate, an unrunnable gate binary or a missing fixture
# all let the sweep run. A gate that wrongly SKIPS would turn a real divergence
# green, which is far worse than duplicating a red. Only an unambiguous "the
# fixture ran and did not pass" suppresses this layer.
#
# NO_SKIP=1 forces it open, because in a green suite a suppressed layer and a
# layer with nothing to say look identical:
#     bazel test //... --test_env=NO_SKIP=1
if [ "${NO_SKIP:-0}" = "1" ]; then
	GATE_DIFFER=""
fi

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

if [ -n "$GATE_DIFFER" ] && [ -n "$GATE_BIN" ] && [ -n "$GATE_EXPECTED" ] &&
	[ -x "$GATE_BIN" ] && [ -f "$GATE_EXPECTED" ]; then
	GATE_OK=0
	if [ "$GATE_ARG_SET" -eq 1 ]; then
		sh "$GATE_DIFFER" --bin "$GATE_BIN" --expected "$GATE_EXPECTED" \
			-- "$GATE_ARG" >/dev/null 2>&1 && GATE_OK=1
	else
		sh "$GATE_DIFFER" --bin "$GATE_BIN" --expected "$GATE_EXPECTED" \
			>/dev/null 2>&1 && GATE_OK=1
	fi
	if [ "$GATE_OK" -ne 1 ]; then
		echo "rush01_check: SKIP — this exercise's own output fixture is not passing yet."
		echo ""
		echo "  That fixture is the one worth reading first: it is the example printed"
		echo "  in the subject, with a table and hints attached. This layer replays"
		echo "  hundreds of generated clue vectors and reports which RULE each wrong"
		echo "  grid breaks — the same failure, told far less usefully, several hundred"
		echo "  times over. Get the *_output layer green and this one starts checking"
		echo "  the inputs you did not think of."
		echo "  (bazel test //... --test_env=NO_SKIP=1 runs it anyway.)"
		exit 0
	fi
fi

# ---------------------------------------------------------------------------
# Corpus acquisition.
if [ -n "$CORPUS" ]; then
	if [ ! -f "$CORPUS" ]; then
		echo "rush01_check: --corpus '$CORPUS' does not exist" >&2
		exit 2
	fi
	cp "$CORPUS" "$T/corpus"
	SRC="corpus $CORPUS"
else
	if [ ! -x "$ORACLE" ]; then
		echo "rush01_check: FAIL — the reference '$ORACLE' is not executable."
		echo "               Nothing generated the case list, so nothing was checked."
		exit 2
	fi
	: > "$T/corpus"
	for _fn in $FN; do
		if ! "$ORACLE" "$_fn" "$SEED" "$COUNT" >> "$T/corpus" 2> "$T/oerr"; then
			echo "rush01_check: FAIL — the reference could not generate cases (fn=$_fn)."
			echo "               This is a harness problem, not yours."
			[ -s "$T/oerr" ] && sed 's/^/    /' "$T/oerr" | head -5
			exit 2
		fi
	done
	SRC="fn=$FN, seed=$SEED, count=$COUNT"
fi

# ---------------------------------------------------------------------------
# The judgement itself, in awk: one program, two modes.
#
#   mode=prep   read the corpus, validate every solution the reference claims,
#               normalise each case to "<n>\t<nsol>\t<sols>\t<clue>" and apply
#               --max-size / --max-cases.
#   mode=judge  read ONE run's captured stdout and stderr, decide, and print the
#               verdict block. Exit 0 pass, 1 the student is wrong, 2 the corpus
#               and this checker disagree (see the header).
#
# One file rather than two so that the grid rules — the Latin-square test and the
# visibility arithmetic — exist EXACTLY once and are shared by the corpus
# self-check and the student judgement. If those two ever drifted apart, the
# layer would be validating the student against rules it never applied to the
# reference.
cat > "$T/rush01.awk" <<'AWK_END'
# ---------------------------------------------------------------- shared rules

# How many boxes are visible looking along one line of the grid.
#   kind 1 = down a column (from the top)      kind 3 = along a row (from the left)
#   kind 2 = up a column (from the bottom)     kind 4 = back along a row (from the right)
# A box is visible when it is taller than every box before it — which is exactly
# the subject's "a taller box hides every shorter box behind it".
function seen_line(g, kind, idx,   i, v, mx, c, len) {
	mx = 0
	c = 0
	# A column is GH cells tall; a row is GW cells wide. Conflating the two is
	# invisible on a square board and wrong on every other one.
	len = (kind <= 2) ? GH : GW
	for (i = 1; i <= len; i++) {
		if (kind == 1)      v = g[i "," idx]
		else if (kind == 2) v = g[(GH + 1 - i) "," idx]
		else if (kind == 3) v = g[idx "," i]
		else                v = g[idx "," (GW + 1 - i)]
		if (v > mx) { mx = v; c++ }
	}
	return c
}

function side_name(kind) {
	if (kind == 1) return "the top"
	if (kind == 2) return "the bottom"
	if (kind == 3) return "the left"
	return "the right"
}

# Which clue position k refers to. Sets K_KIND and K_IDX.
function clue_where(k) {
	# Slot layout: GW column clues from the TOP, GW from the BOTTOM, then GH row
	# clues from the LEFT and GH from the RIGHT. With GW == GH this is the
	# familiar 4n layout.
	if (k <= GW)                { K_KIND = 1; K_IDX = k }
	else if (k <= 2 * GW)       { K_KIND = 2; K_IDX = k - GW }
	else if (k <= 2 * GW + GH)  { K_KIND = 3; K_IDX = k - 2 * GW }
	else                        { K_KIND = 4; K_IDX = k - 2 * GW - GH }
}

# Check grid g against clue vector cl. Returns the number of broken rules and
# describes the FIRST one in F_CAT / F_MSG / F_WHY.
#
# The order is deliberate and is the order the subject introduces the rules in:
# the Latin-square property of the rows, then of the columns, then the 4N
# visibility clues in the order they appear in the input string. So the fault a
# student is shown is the earliest one in the terms they already know, not
# whichever the checker happened to notice.
function times(k) { return (k == 2 ? "twice" : k " times") }

function check_grid(g, cl,   r, c, k, v, cnt, got, want, faults, nk) {
	faults = 0
	F_CAT = ""; F_MSG = ""; F_WHY = ""
	nk = 2 * GW + 2 * GH
	# The subject's rule is "each row and each column holds only one box of each
	# size". On a rectangle that cannot hold literally — a column of 2 cells
	# cannot contain one of each of 4 sizes — so the rule that generalises is
	# DISTINCTNESS: heights run 1..GK where GK = max(GW, GH), a row holds GW of
	# them without repeating and a column holds GH. When GW == GH == GK this is
	# the Latin square rule unchanged.
	for (r = 1; r <= GH; r++) {
		for (v = 1; v <= GK; v++) cnt[v] = 0
		for (c = 1; c <= GW; c++) cnt[g[r "," c] + 0]++
		for (v = 1; v <= GK; v++) {
			if (cnt[v] > 1) {
				faults++
				if (faults == 1) {
					F_CAT = "latin-row"
					F_MSG = sprintf("row %d holds the height %d %s.", r, v, times(cnt[v]))
					F_WHY = (GW == GH) \
						? ("Every row must hold each of the heights 1.." GK " exactly once.") \
						: ("Every row holds " GW " different heights from 1.." GK ", so none may repeat.")
				}
			}
		}
	}
	for (c = 1; c <= GW; c++) {
		for (v = 1; v <= GK; v++) cnt[v] = 0
		for (r = 1; r <= GH; r++) cnt[g[r "," c] + 0]++
		for (v = 1; v <= GK; v++) {
			if (cnt[v] > 1) {
				faults++
				if (faults == 1) {
					F_CAT = "latin-col"
					F_MSG = sprintf("column %d holds the height %d %s.", c, v, times(cnt[v]))
					F_WHY = (GW == GH) \
						? ("Every column must hold each of the heights 1.." GK " exactly once.") \
						: ("Every column holds " GH " different heights from 1.." GK ", so none may repeat.")
				}
			}
		}
	}
	for (k = 1; k <= nk; k++) {
		clue_where(k)
		want = cl[k] + 0
		got = seen_line(g, K_KIND, K_IDX)
		if (got != want) {
			faults++
			if (faults == 1) {
				F_CAT = "clue"
				F_MSG = sprintf("%s %d is seen as %d from %s, but clue %d asks for %d.", \
					(K_KIND <= 2 ? "column" : "row"), K_IDX, got, side_name(K_KIND), k, want)
				F_WHY = "A taller box hides every shorter box behind it, so what you see " \
					"from one side is the count of boxes taller than everything in front of them."
			}
		}
	}
	return faults
}

# Split a clue string into cl[1..4n]. Returns n, or 0 if the string is not a
# well-formed vector at all (this is the "any other input is an error" case).
# The board the subject REQUIRES. Every other size — larger or smaller — is the
# optional bonus, which is why this is a specific number and not an upper bound:
# a 4x4-only program cannot solve a 3x3 any more than it can solve a 9x9, and
# failing it for either would be grading an optional part of the subject.
function mandatory_n() { return 4 }

# True when a case of size n is bonus territory for this run: not the mandatory
# board, and outside the range the caller asked to have REQUIRED (--max-size).
function is_bonus(   sz) {
	# A rectangle is never the board the subject requires — and more than that,
	# the rectangular rules are an extension THIS HARNESS defines (the subject
	# says nothing about non-square boards, and cannot: 2W+2H clues do not
	# determine W and H). Grading a student against a convention they were never
	# given would be unfair, so rectangles stay lenient unless the caller has
	# explicitly asked for bonus grading by raising --max-size at all.
	if (GW != GH) return (maxsize <= 0)
	sz = GW
	return (sz != mandatory_n() && sz > maxsize)
}

function parse_clue(s, cl,   i, m, t, w, h, k, flag, fv, rest, lim) {
	GW = 0; GH = 0; GK = 0
	# An optional "-w N " or "-h N " ahead of the clue list gives the board's
	# shape. It is needed for one reason only: a W x H board carries 2W + 2H
	# clues, and that COUNT DOES NOT DETERMINE (W, H) — 16 clues is equally
	# 4x4, 3x5, 5x3, 2x6 or 8x1. Exactly one SQUARE reading exists per count,
	# which is the only reason the mandatory form is readable from a bare list.
	# One number is enough, because the other follows: H = m/2 - W.
	flag = ""
	if (s ~ /^-[wh] [1-9][0-9]* /) {
		flag = substr(s, 2, 1)
		rest = substr(s, 4)
		fv = rest + 0
		sub(/^[0-9]+ /, "", rest)
		s = rest
	}
	if (s !~ /^[1-9]( [1-9])*$/) return 0
	m = split(s, t, " ")
	if (flag == "") {
		if (m % 4 != 0) return 0
		w = m / 4
		h = w
	} else {
		if (m % 2 != 0) return 0
		if (flag == "w") { w = fv; h = m / 2 - w }
		else             { h = fv; w = m / 2 - h }
	}
	if (w < 1 || h < 1) return 0
	if (2 * w + 2 * h != m) return 0
	k = (w > h ? w : h)
	if (k > 9) return 0
	for (i = 1; i <= m; i++) {
		# A clue counts boxes along ONE line, so it can never exceed that
		# line's length: the column clues look down GH cells, the row clues
		# along GW of them.
		lim = (i <= 2 * w) ? h : w
		if (t[i] + 0 > lim) return 0
		cl[i] = t[i] + 0
	}
	GW = w; GH = h; GK = k
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

# Printable rendering of a captured line, so a report can show what came out
# without a stray control byte scrambling the terminal.
function esc(s,   i, ch, out, code) {
	out = ""
	for (i = 1; i <= length(s); i++) {
		ch = substr(s, i, 1)
		if (ch == "\t") { out = out "\\t"; continue }
		if (ch ~ /^[ -~]$/) { out = out ch; continue }
		code = index(BINCHARS, ch)
		out = out (code > 0 ? sprintf("\\x%02x", code) : "\\?")
	}
	return out
}

BEGIN {
	BINCHARS = ""
	if (mode == "prep") prep_init()
}

# ------------------------------------------------------------------- prep mode
# Reads the corpus. Every field after the first is a solution the reference
# CLAIMS; each one is re-derived here against its own clue vector, so a wrong
# reference is caught before it can be used to fail a student.

function prep_init() {
	ntot = 0; nsolvable = 0; nunsolv = 0; nskipped = 0; nbonus = 0; badref = 0
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
	for (i = 1; i <= nalt; i++) {
		ns++
		sols = (sols == "" ? sset[i] : sols " " sset[i])
		# ---- the reference is checked against the rules, not trusted ----
		if (!okc) {
			printf "rush01_check: FAIL — the corpus lists a solution for an input that is\n" \
				"               not a well-formed clue vector: %s\n", esc(clue) > "/dev/stderr"
			badref++
			continue
		}
		delete gg
		if (!load_sol(sset[i], gg)) {
			printf "rush01_check: FAIL — corpus solution %d for \"%s\" is not %d digits\n" \
				"               of a %dx%d grid: %s\n", i, clue, GW * GH, GW, GH, esc(sset[i]) > "/dev/stderr"
			badref++
			continue
		}
		if (check_grid(gg, cl) > 0) {
			printf "rush01_check: FAIL — corpus solution %d for \"%s\" breaks a rule of the\n" \
				"               puzzle it is supposed to solve: %s\n", i, clue, F_MSG > "/dev/stderr"
			badref++
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
	rec[ntot] = (is_bonus() ? 1 : 0) "\t" ns "\t" exh "\t" (sols == "" ? "-" : sols) "\t" clue
}

END {
	if (mode != "prep") judge_end()
	else {
		if (badref > 0) exit 2
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
			if (ff[2] + 0 > 0) ks++; else ku++
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

function say(s) { if (verbose) print s }

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

function verdict(cat, msg, why) {
	print cat >> catfile
	say(" --------------------------------------------------")
	say(sprintf(" CASE %s  argv: %s", caseid, (clue == "" && argvdesc != "" ? argvdesc : "\"" esc(clue) "\"")))
	show_clues()
	if (nsol > 0)
		say(sprintf("   this input HAS %d valid grid%s", nsol, (nsol == 1 ? "" : "s")))
	else if (!okc)
		say("   this is NOT a well-formed input, so the only correct output is Error")
	else
		say("   NO arrangement of the heights satisfies this input")
	show_output()
	say("   FAULT [" cat "] " msg)
	if (why != "") say("     " why)
	if (nerr > 0 && cat != "error-on-stderr") {
		say("   (it also wrote to standard error: " esc(e[1]) ")")
	}
}

# Is line `s` a well-formed row of `w` heights, "d d d d"? Returns "" if it is,
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
						"The subject reads this program through a pipe (`| cat -e`), and a pipe " \
						"carries standard output only.")
					exit 1
				}
			}
			verdict("no-output", "it printed nothing at all.", \
				"An input no arrangement can satisfy is an error, and an error prints Error.")
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
			if (!okc) {
				verdict("false-solution", "it printed a grid, but this is not a well-formed input.", \
					"The only acceptable input is ONE argument holding the clues as digits " \
					"separated by single spaces — 16 of them for the 4x4 board. Anything " \
					"else, including no argument at all, must be treated as an error.")
				exit 1
			}
			faults = check_grid(gg, cl)
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
				"Capital E, the rest lower case, on its own line — the subject prints it verbatim.")
		else if (nout > 1)
			verdict("bad-error-text", \
				sprintf("it printed %d lines; the error output is the single line Error.", nout), \
				"Nothing may accompany it: no message, no blank line, no grid.")
		else
			verdict("bad-error-text", \
				"this input has no solution, so the output must be exactly \"Error\" and a newline.", \
				"Nothing else and nothing besides: not \"error\", not \"Error\" without the " \
				"newline, not a message alongside it.")
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
					"each line \"d d d d\" — nothing else, no heading and no prompt.", GH, GW))
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
	faults = check_grid(gg, cl)

	# The two answers must agree: the corpus lists EVERY grid that satisfies the
	# clues, so "satisfies the rules" and "is in the list" are the same question
	# asked twice. When they disagree the harness is broken, and saying so is the
	# only honest outcome — blaming the student for the reference's mistake is
	# exactly the failure mode this cross-check exists to prevent.
	if (faults == 0 && (key in member)) { print (is_bonus() ? "bonus-ok" : "ok") >> catfile; exit 0 }
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
	if (faults > 0 && (key in member)) {
		print "corpus-inconsistent" >> catfile
		say(" --------------------------------------------------")
		say(" HARNESS PROBLEM, not yours: the corpus lists " key " as a solution for")
		say(" \"" clue "\", but it breaks a rule: " F_MSG)
		exit 2
	}
	verdict(F_CAT, F_MSG, F_WHY sprintf(" (%d rule%s broken in total.)", faults, (faults == 1 ? "" : "s")))
	exit 1
}
AWK_END

# ---------------------------------------------------------------------------
# Normalise the corpus and self-check the reference.
if ! awk -f "$T/rush01.awk" -v mode=prep -v maxsize="$MAXSIZE" \
	-v maxcases="$MAXCASES" -v casefile="$T/cases" -v statsfile="$T/stats" \
	"$T/corpus"; then
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
if [ "$TOTAL" -lt 8 ] || [ "$SOLVABLE" -lt 1 ] || [ "$UNSOLVABLE" -lt 1 ]; then
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

FAILS=0
SHOWN=0
TIMEOUTS=0
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
	# shellcheck disable=SC2086
	$RUNNER "$BIN" "$@" > "$OUT" 2> "$ERRF" < /dev/null
	RUN_RC=$?
	# The sentinel that lets awk see a missing final newline (see the judge-mode
	# comment). Skipped after a SIGXFSZ kill: the capture is already at the
	# ulimit, so appending would kill this shell too.
	[ "$RUN_RC" -eq 153 ] || printf '@' >> "$OUT"
}

# Judge whatever run_one just captured. $1 case id, $2 clue string, $3 solutions,
# $4 a description of the argv when it is not a plain clue string.
judge_one() {
	_id="$1"; _clue="$2"; _sols="$3"; _argvdesc="${4:-}"; _exh="${5:-1}"; _bonus="${6:-0}"
	VERBOSE=0
	[ "$SHOWN" -lt "$MAX_FAILS" ] && VERBOSE=1

	if [ "$RUN_RC" -eq 153 ]; then
		FAILS=$((FAILS + 1))
		echo "runaway" >> "$CATS"
		# Counted with the timeouts: a loop whose exit condition is never reached
		# is the same defect whether it prints or not, and either way there is no
		# point spending the layer's whole budget rediscovering it once per case.
		TIMEOUTS=$((TIMEOUTS + 1))
		if [ "$VERBOSE" -eq 1 ]; then
			SHOWN=$((SHOWN + 1))
			echo " --------------------------------------------------"
			echo " CASE $_id  argv: \"$_clue\""
			echo "   RUNAWAY OUTPUT: it kept printing past a ${RUNAWAY_CAP_MIB} MiB budget and was stopped."
			echo "                   A correct answer here is one grid or the word Error."
		fi
		return 1
	fi
	# A bonus-size case that runs out of time is reporting SLOWNESS, not a wrong
	# answer, and slowness on an optional part of the subject is not a verdict on
	# the required one. An exhaustive search that is fine at 4x4 can take minutes
	# at 7x7 while being perfectly correct — failing the mandatory sweep for that
	# would punish attempting the bonus at all. It also must not count toward
	# MAX_TIMEOUTS, or three slow bonus cases would abandon the whole sweep.
	# (--max-size 9 clears _bonus, so the strict target still holds them to it.)
	if { [ "$RUN_RC" -eq 124 ] || [ "$RUN_RC" -eq 137 ]; } && [ "$_bonus" -eq 1 ]; then
		echo "bonus-slow" >> "$CATS"
		return 0
	fi
	if [ "$RUN_RC" -eq 124 ] || [ "$RUN_RC" -eq 137 ]; then
		FAILS=$((FAILS + 1))
		TIMEOUTS=$((TIMEOUTS + 1))
		echo "timeout" >> "$CATS"
		if [ "$VERBOSE" -eq 1 ]; then
			SHOWN=$((SHOWN + 1))
			echo " --------------------------------------------------"
			echo " CASE $_id  argv: \"$_clue\""
			echo "   TIMEOUT: it did not finish within ${TMO}s."
			echo "            Every case in this layer is one small board; a search that"
			echo "            terminates finishes it in milliseconds."
		fi
		return 1
	fi
	if [ "$RUN_RC" -gt 128 ]; then
		SIG=$((RUN_RC - 128))
		case "$SIG" in
			6)  NAME="SIGABRT (abort: assertion, stack smashing, or a glibc heap error)" ;;
			8)  NAME="SIGFPE (arithmetic error, e.g. division or modulo by zero)" ;;
			11) NAME="SIGSEGV (invalid memory access)" ;;
			13) NAME="SIGPIPE (wrote to a closed pipe)" ;;
			*)  NAME="signal $SIG" ;;
		esac
		FAILS=$((FAILS + 1))
		echo "crash" >> "$CATS"
		if [ "$VERBOSE" -eq 1 ]; then
			SHOWN=$((SHOWN + 1))
			echo " --------------------------------------------------"
			echo " CASE $_id  argv: \"$_clue\""
			echo "   CRASH: it died on $NAME."
			echo "          Whatever it printed first does not matter: a crash is a failure."
			[ -s "$ERRF" ] && sed 's/^/          /' "$ERRF" | head -8
		fi
		return 1
	fi

	awk -f "$T/rush01.awk" -v mode=judge -v clue="$_clue" -v sols="$_sols" \
		-v caseid="$_id" -v argvdesc="$_argvdesc" -v verbose="$VERBOSE" \
		-v exh="$_exh" -v maxsize="$MAXSIZE" \
		-v outfile="$OUT" -v errfile="$ERRF" -v catfile="$CATS" \
		"$OUT" "$ERRF"
	_jrc=$?
	if [ "$_jrc" -eq 0 ]; then
		return 0
	fi
	if [ "$_jrc" -eq 2 ]; then
		HARNESS=$((HARNESS + 1))
		[ "$VERBOSE" -eq 1 ] && SHOWN=$((SHOWN + 1))
		return 2
	fi
	FAILS=$((FAILS + 1))
	[ "$VERBOSE" -eq 1 ] && SHOWN=$((SHOWN + 1))
	return 1
}

# ---------------------------------------------------------------------------
# The sweep. Every clue string comes out of the case file and is handed to the
# program as ONE argument — the interface the subject specifies — which is why
# nothing here goes near sh_test's whitespace tokenisation.
TAB=$(printf '\t')
# CN and CNSOL are read only to position CSOLS and CCLUE: the record is
# "<isbonus>\t<nsol>\t<exh>\t<sols>\t<clue>" and the clue must be LAST so that the spaces it
# is made of survive (with IFS=tab, a space is not a separator, and `read` gives
# every remaining character to the final variable).
# shellcheck disable=SC2034
while IFS="$TAB" read -r CBONUS CNSOL CEXH CSOLS CCLUE; do
	RUN=$((RUN + 1))
	SWEPT=$((SWEPT + 1))
	# A rectangular case carries its shape as a "-w N" / "-h N" prefix inside the
	# clue field, because the clue COUNT cannot express it (2W+2H does not
	# determine W and H). The program must receive that as its own two argv
	# words, with the clue list still a single argument — so it is split here
	# rather than shipped as one string the student would have to re-parse.
	case "$CCLUE" in
		-w\ *|-h\ *)
			CFLAG=${CCLUE%% *}
			CREST=${CCLUE#* }
			CDIM=${CREST%% *}
			run_one "$CFLAG" "$CDIM" "${CREST#* }"
			;;
		*)
			run_one "$CCLUE"
			;;
	esac
	# is_bonus() is decided once, in awk, where the board's shape is known — a
	# rectangle is bonus whatever its dimensions, which no arithmetic on a single
	# "size" number could express. The shell just carries the answer.
	judge_one "$RUN/$TOTAL" "$CCLUE" "$CSOLS" "" "$CEXH" "$CBONUS" || true
	if [ "$TIMEOUTS" -ge "$MAX_TIMEOUTS" ]; then
		STOPPED=1
		echo " --------------------------------------------------"
		echo " STOPPED after $TIMEOUTS run(s) that never finished (a hang, or a loop"
		echo " printing without end). The remaining $((TOTAL - RUN)) case(s) were not"
		echo " tried: with a solver that does not terminate, running them would only"
		echo " spend the layer's whole time budget to print the same thing again."
		break
	fi
done < "$T/cases"

# The loop must have judged every case prep selected. It cannot, unless something
# consumed the case file out from under `read` — which is precisely what a child
# inheriting this loop's stdin used to do (see run_one). That bug's signature was
# a GREEN run reporting one case, so the assertion is kept even though the cause
# is fixed: this layer's entire job is to refuse a pass it has not earned, and a
# silently shortened sweep is the one failure it cannot afford to report as OK.
if [ "$STOPPED" -eq 0 ] && [ "$SWEPT" -ne "$TOTAL" ]; then
	echo "rush01_check: HARNESS FAILURE — the sweep judged $SWEPT of the $TOTAL case(s) it"
	echo "              selected, and did not stop early. The case list was consumed by"
	echo "              something other than this loop, so the cases that were checked are"
	echo "              not the cases that were meant to be. Nothing here is a verdict on"
	echo "              your program."
	exit 2
fi

# ---------------------------------------------------------------------------
# Optional argv-shape probes. The corpus can express any single argument,
# including a malformed or empty one, but it cannot express "no argument" or
# "two arguments" — those are argc, not argv content. Opt-in, because how far
# "This is the only acceptable input" reaches is a reading of the subject, and
# this runner should not impose one on every caller.
if [ "$PROBE_ARGC" -eq 1 ] && [ "$TIMEOUTS" -lt "$MAX_TIMEOUTS" ]; then
	RUN=$((RUN + 1))
	run_one
	judge_one "argc/0" "" "-" "(no argument at all)" || true

	RUN=$((RUN + 1))
	run_one "4 3 2 1 1 2 2 2" "4 3 2 1 1 2 2 2"
	judge_one "argc/2" "" "-" "(two arguments)" || true

	RUN=$((RUN + 1))
	run_one ""
	judge_one "argc/empty" "" "-" "(one empty argument)" || true
fi

# ---------------------------------------------------------------------------
# Verdict.
if [ "$SHOWN" -lt "$FAILS" ] || [ "$SHOWN" -lt "$((FAILS + HARNESS))" ]; then
	echo " --------------------------------------------------"
	echo " ... $((FAILS + HARNESS - SHOWN)) further failing case(s) not shown."
	echo "     Raise with RUSH01_MAX_FAILS (bazel test ... --test_env=RUSH01_MAX_FAILS=50)."
fi

# One line per verdict was appended to $CATS; fold it into a census so the shape
# of the failure is visible even when only five blocks were printed.
if [ -s "$CATS" ]; then
	CENSUS=$(awk '$0 != "ok" && $0 != "bonus-ok" && $0 != "bonus-absent" && $0 != "bonus-slow" { c[$0]++ } END { s = ""; for (k in c) s = s "  " k " x" c[k]; print s }' "$CATS")
else
	CENSUS=""
fi

if [ "$FAILS" -eq 0 ] && [ "$HARNESS" -eq 0 ]; then
	echo "rush01_check: OK — $LABEL: $RUN case(s) validated ($SOLVABLE solvable, $UNSOLVABLE with no"
	echo "              solution$([ "$BONUS" -gt 0 ] && echo ", $BONUS bonus-size case(s)")); $SRC"
	echo "              Each printed grid was checked to be a Latin square and to satisfy"
	echo "              all of its clues; up to 6x6, also to be one of the grids the"
	echo "              reference enumerated."
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
		if [ "$_btried" -gt 0 ]; then
			echo "              bonus: $_btried bonus-size grid(s) solved correctly$([ "$_babsent" -gt 0 ] && echo ", $_babsent answered Error")."
		else
			echo "              bonus: not attempted — all $_babsent bonus-size input(s) answered"
			echo "              Error, which is a correct answer for a 4x4-only program."
		fi
	fi
	exit 0
fi

if [ "$HARNESS" -gt 0 ] && [ "$FAILS" -eq 0 ]; then
	echo "rush01_check: HARNESS FAILURE — the case list and this checker disagree on"
	echo "              $HARNESS case(s). Nothing above is a verdict on your program."
	[ -n "$CENSUS" ] && echo "              by fault:$CENSUS"
	exit 2
fi

echo "rush01_check: FAIL — $LABEL: $FAILS of $RUN case(s) judged wrong; $SRC"
[ -n "$CENSUS" ] && echo "              by fault:$CENSUS"
if [ "$HARNESS" -gt 0 ]; then
	echo "              ($HARNESS further case(s) are a HARNESS problem, not yours.)"
fi
if [ -n "$HINTS" ] && [ -f "$HINTS" ]; then
	echo " --------------------------------------------------"
	echo " HINTS:"
	sed 's/^/   * /' "$HINTS" | head -20
fi
exit 1
