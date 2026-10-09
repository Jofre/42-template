#!/bin/sh
# bsq_check.sh — differential check for c-piscine-bsq.
#
# A BYTE MATCH IS NOT A PASS IF THE PROGRAM THEN DIED. Every comparison below
# also tests the exit status: this compared output alone, so a deliverable that
# printed the right map and segfaulted on the way out was reported as agreeing
# with the reference. How each run ended is read from waitpid() through
# tools/exit_status (rl_run, rl_classify), and a run that did not return is a
# failed case even where its bytes match.
#
# Runs the student's ./bsq once per map against a corpus the Rust reference
# generated, and reports the first differences as readable diagnoses.
#
# WHY THIS IS ONE EXEC PER CASE, unlike c_diff.
# c_diff streams a 400k-line corpus through ONE process reading stdin, which is
# what makes that layer cheap. It can do that because its subject is a
# FUNCTION: the harness links the student's code and loops in-process. bsq is a
# PROGRAM -- it has its own main, it takes file paths on argv, and each case is
# therefore a fork+exec. The count stays in the hundreds. That is a property of
# the subject, not a shortcut.
#
# WHY THIS ONE GATES, unlike tools/rush02_check.sh.
# rush-02's subject pins four outputs and no composition rule, so a divergence
# there is evidence rather than a verdict and its targets are `manual`. bsq's
# subject settles the answer completely, including the tie: "the square that is
# closest to the top of the map, then the one that is most to the left". There
# is one correct output per map, so this is a real check and it is allowed to
# be red.
#
# THREE MODES. argv (one map per exec), stdin (the map on stdin with no
# arguments), multi (K maps in one exec, which is where the blank line between
# outputs is checked). BSQ's targets hand all three the SAME generator,
# bsq_mixed, valid and invalid maps interleaved: a corpus per transport is
# corpora that drift, and the one nobody noticed was the stdin target's, which
# carried valid maps only and passed a program that answered an invalid map
# on stdin with nothing at all (finding 181). The subject owes "map error"
# whichever way a map arrives.
#
# --readings says the corpus is a READINGS one (bsq_readings): records for
# sentences the subject leaves open, under the one reading the target takes.
# A failure then says "under this harness's reading" rather than that
# the file is simply invalid or valid, names the open form the file holds
# ("its last row has no newline after it"), and the hints (--clues) state the
# reading. Without it, a record is one every reading of the subject agrees on.
#
# THE TAGS. A record is `ok` (a settled valid map), `err:<slug>` (a settled or
# read invalid one) or `ok:<slug>` (a map valid under the reading, whose slug
# is the open form it holds). A readings record always carries its slug, and
# every slug has a sentence in FORMS below: the log once read
# "CASE 5 [ok] ... got map error" under the generic "this file is valid", and
# the student had to open the kept map to find that its last row had no
# newline. So a readings corpus holding a bare `ok`, or a slug this file has
# no sentence for, is refused as a harness fault; so is an `ok:<slug>` in a
# corpus that is not a readings one, where nothing is open.
#
# A FAILING CASE IS SHOWN WHOLE AND CAN BE RUN AGAIN (finding 174). Its map,
# or each map of a multi-mode group, is kept in test.outputs with the command
# that replays it; the want and got lines show every byte (\xHH for one that
# is not printable, which a terminal would otherwise print as nothing); and in
# multi mode the group's output is split at its blank lines and compared map
# by map, so the report names the map that went wrong and diagnoses it as a
# single map -- an invalid file that was answered anyway is
# "accepted-invalid-file", with its first line and its line count, not a
# problem with "the lines you print". The tally counts RUNS in multi mode,
# one per group, on both sides of the "agree".
#
# Usage:
#   bsq_check.sh --bin PATH --oracle PATH
#                [--fn NAME] [--seed N] [--count N] [--fixed N]
#                [--mode argv|stdin|multi] [--group K] [--show N]
#                [--timeout SECS] [--readings] [--clues FILE [--case NAME]]
#                [--sanitized | --valgrind PATH --valgrind-tools FILE
#                 [--sample N] [--rule FILE]]
#                [--gate-differ PATH --gate-bin PATH --gate-expected PATH
#                 [--gate-arg WORD]...]
#                (--stderr-empty | --stderr-ignored REASON) [--quotes FILE]
#
#   --stderr-empty            a case also fails when the program writes
#                             anything to standard error, its output right or not
#   --stderr-ignored REASON   standard error is not judged: it is shown beside
#                             a case that failed, and the OK line says why
#
# ONE OF THE TWO IS REQUIRED (exit 2 without it, or with both): what standard
# error is held to is the call site's decision, by the Run contract. This
# runner kept it only to show beside a crash, which decided it by default
# (tools/runner_lib.sh, STANDARD ERROR, A CHOICE AT EVERY CALL; review of
# WP-50). tools/defs.bzl refuses such a call while loading (_RUNNER_CHOICES).
# Under --sanitized or --valgrind neither is given: standard error carries the
# checker's report there, and no output is judged.
#
#   --quotes FILE    the subject's sentences the faults quote, one KEY<TAB>TEXT
#                  line each, written at the call site (tools/defs.bzl's
#                  runner_quotes): `tie`, the sentence that says which of
#                  several biggest squares is drawn, and `error`, the one
#                  that says what an invalid file prints. Required, except
#                  under --sanitized or --valgrind, which judge no output
#                  (tools/runner_lib.sh, "A SUBJECT'S SENTENCE COMES FROM THE
#                  CALL SITE")
#   --gate-arg WORD  repeatable: one word of the gate's run, in order -- the
#                  arguments the gating case's own output test passes (BSQ's
#                  subject_example: the map's path). Relative paths are taken
#                  from where the runner starts, as the case's are. Without
#                  one the gate ran the program with no map at all, which a
#                  correct program answers with "map error" -- never the
#                  example's square -- so every layer behind it said SKIP on
#                  every program that passes the example.
#   --clues FILE   a clues.tsv, whose hints are shown under a failing run
#                  (tools/runner_lib.sh's rl_clues: its first three rows)
#   --case NAME    the name this target's rows are keyed to in a program's
#                  one clues.tsv (its target's name after exNN_): only those
#                  rows and the ones keyed to nothing are shown, never the
#                  rows of the program's other cases
#   --show N       how many failing cases to print (default DIFF_MAX_ROWS, 40;
#                  0 prints all); every one is kept in test.outputs either way
#   --fixed N      the reference's arm is a FIXED list of exactly N maps, not
#                  a seeded corpus (bsq_long, bsq_big): it must emit exactly
#                  N, and the floor of 20 that guards a seeded corpus does not
#                  apply
#   --sanitized    BIN is the ASan/UBSan build: every run, judging memory and
#                  how each run ended, never the output (ex00_bsq_diff_asan);
#                  --symbolizer PATH --symbolizer-lib FILE name each frame of
#                  a report's stack (runner_lib.sh, rl_sanitizers)
#   --valgrind PATH --valgrind-tools FILE [--sample N] [--rule FILE]
#                  a sample of the runs under memcheck, leaks included
#                  (ex00_bsq_valgrind). In every mode: in multi mode a run
#                  is a group, as in the plain replay, and a report names the
#                  run and keeps its maps -- the second map's reading is where
#                  the first map's leftovers are found. tools/runner_lib.sh,
#                  "A CORPUS UNDER A MEMORY CHECKER"
#   --timeout SECS one run's own limit (default BSQ_TIMEOUT, 10). The long
#                  and big maps take a generous one: it guards against a
#                  hang, never against a slow but correct program -- the
#                  subject sets no time limit. A run that does not finish is
#                  counted apart from one that answered wrong, in the tally
#                  and in the sweep's stop: its output was never compared
#
# Env: BSQ_TIMEOUT    seconds one run may take (default 10)
#      DIFF_MAX_ROWS  the default of --show (tools/runner_lib.sh, rl_rows)
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "bsq_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat cmp grep mkdir mktemp rm sed sort tail uniq wc

# The shared runner helpers: the time budget, signal traps and how a run ended
# (tools/runner_lib.sh, which says why each is written once).
RL_NAME=bsq_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "bsq_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool ORACLE -- the Rust reference (//oracle), which writes the corpus

BIN=""
ORACLE=""
FN="bsq_maps"
SEED=1
COUNT=200
MODE="argv"
GROUP=3
SHOW=""
FIXED=""
TMO=""
GATE_DIFFER=""; GATE_BIN=""; GATE_EXPECTED=""; GATE_ARGS=""
STDERR_EMPTY=0
STDERR_WHY=""
READINGS=0
CLUES=""
CASE_NAME=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "bsq_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--seed) need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--mode) need "$1" "$#"; MODE="$2"; shift 2 ;;
		--group) need "$1" "$#"; GROUP="$2"; shift 2 ;;
		--show) need "$1" "$#"; SHOW="$2"; shift 2 ;;
		--fixed) need "$1" "$#"; FIXED="$2"; shift 2 ;;
		--timeout) need "$1" "$#"; TMO="$2"; shift 2 ;;
		--readings) READINGS=1; shift ;;
		--clues) need "$1" "$#"; CLUES="$2"; shift 2 ;;
		--case) need "$1" "$#"; CASE_NAME="$2"; shift 2 ;;
		--sanitized | --valgrind | --valgrind-tools | --sample | --rule | --symbolizer | --symbolizer-lib)
			rl_mem_opt "$@"; shift "$RL_MEM_SHIFT" ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-arg) need "$1" "$#"; rl_list_add GATE_ARGS "$2"; shift 2 ;;
		--stderr-empty) STDERR_EMPTY=1; shift ;;
		--stderr-ignored) need "$1" "$#"; STDERR_WHY="$2"; shift 2 ;;
		--quotes) need "$1" "$#"; rl_quotes_opt "$2"; shift 2 ;;
		*) echo "bsq_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$BIN" ] || { echo "bsq_check.sh: --bin is required" >&2; exit 2; }
[ -n "$ORACLE" ] || { echo "bsq_check.sh: --oracle is required" >&2; exit 2; }
rl_stderr_choice
rl_quotes_ready "tie error"
Q_TIE=$(rl_quote tie)
Q_ERROR=$(rl_quote error)
case "$MODE" in
	argv|stdin|multi) ;;
	*) echo "bsq_check.sh: --mode must be argv|stdin|multi" >&2; exit 2 ;;
esac
rl_rows "$SHOW"
rl_mem_ready
case "$FIXED" in
	'' | [1-9] | [1-9]*[0-9]) ;;
	*) echo "bsq_check.sh: --fixed must be a count of maps, got '$FIXED'" >&2; exit 2 ;;
esac

# Absolutise everything before anything changes directory. $(location ...) hands
# us runfiles-root-relative paths and they stop resolving the moment cwd moves.
abspath() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }
BIN=$(abspath "$BIN")
ORACLE=$(abspath "$ORACLE")
[ -n "$GATE_DIFFER" ] && GATE_DIFFER=$(abspath "$GATE_DIFFER")
[ -n "$GATE_BIN" ] && GATE_BIN=$(abspath "$GATE_BIN")
[ -n "$GATE_EXPECTED" ] && GATE_EXPECTED=$(abspath "$GATE_EXPECTED")

[ -x "$BIN" ] || { echo "bsq_check.sh: '$BIN' is not executable" >&2; exit 1; }

# ---------------------------------------------------------------------------
# The correctness gate (tools/runner_lib.sh's rl_gate): while the subject's own
# example is red, replaying hundreds of generated maps says the same thing
# hundreds of times less usefully. The gate runs the program as that example's
# output test does -- each --gate-arg one word of the run, the map's path --
# and c_levels()' audit holds the two to each other (tools/defs.bzl,
# _gate_problems). It ran the program with no argument at all, so a correct
# program read an empty standard input, printed "map error", and every corpus
# target SKIPped on every correct tree: green, having checked nothing, wherever
# NO_SKIP=1 was not set.
rl_split_on
# shellcheck disable=SC2086 # a list, one word per line (rl_list_add)
rl_gate bsq_check "$GATE_DIFFER" "$GATE_BIN" "$GATE_EXPECTED" $GATE_ARGS
rl_split_off

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
[ -f "$_sl" ] || { echo "bsq_check.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
standin_check bsq_check "$BIN" "$RL_STANDIN" "the program"

WORK=$(mktemp -d)
rl_traps 'rm -rf "$WORK"'

# The hang guard: each run's own cap, and what is left of the test's limit
# (rl_sweep_next): a program that never returns would otherwise burn the whole
# Bazel timeout with no explanation a student can act on.
[ -n "$TMO" ] || TMO="${BSQ_TIMEOUT:-10}"

CORPUS="$WORK/corpus"
"$ORACLE" "$FN" "$SEED" "$COUNT" > "$CORPUS" 2>/dev/null || {
	echo "bsq_check.sh: the oracle produced no corpus for '$FN'" >&2
	exit 2
}

# ---------------------------------------------------------------------------
# FLOORS. Each one names a wrong program that would otherwise pass, which is the
# only reason a floor is worth having. All of them are exit 2: a corpus that
# cannot fail anything is a broken harness, not a wrong deliverable.
#
# `grep -c` PRINTS 0 and EXITS 1 when nothing matches, so `|| echo 0` would
# append a second zero and the comparison would silently never fire. That was a
# real bug in rush02_check.sh; it is written this way on purpose.
MIN_BSQ_CASES=20
GOT_CASES=$(grep -c . "$CORPUS" 2>/dev/null) || GOT_CASES=0
# A FIXED list (--fixed N) is held to its exact count instead: a seeded corpus
# proves something by its number, a fixed one by each of its maps, and one
# missing is one property nobody checked.
if [ -n "$FIXED" ]; then
	if [ "$GOT_CASES" -ne "$FIXED" ]; then
		echo "bsq_check.sh: the reference emitted $GOT_CASES map(s) for '$FN', a fixed" >&2
		echo "              list this target expects exactly $FIXED of. A harness fault." >&2
		exit 2
	fi
elif [ "$GOT_CASES" -lt "$MIN_BSQ_CASES" ]; then
	echo "bsq_check.sh: the reference emitted $GOT_CASES case(s) for '$FN'," >&2
	echo "              fewer than the $MIN_BSQ_CASES this layer requires." >&2
	echo "              Reporting a HARNESS failure rather than a green run:" >&2
	echo "              a corpus this small proves nothing about the program." >&2
	exit 2
fi

FLOOR=$(awk -F'\t' '
	$1 ~ /^ok(:|$)/ { ok++;  if ($2 == 0) zero++ }
	$1 ~ /^err:/    { err++ }
	$1 ~ /^ok(:|$)/ && $5 != $6 { differs++ }
	END { printf "%d %d %d %d\n", ok+0, err+0, zero+0, differs+0 }' "$CORPUS")
set -- $FLOOR
N_OK=$1; N_ERR=$2; N_ZERO=$3; N_DIFF=$4

if [ "$MODE" = multi ]; then
	if [ "$N_OK" -lt 1 ] || [ "$N_ERR" -lt 1 ]; then
		echo "bsq_check.sh: --mode multi needs a corpus holding BOTH valid and invalid" >&2
		echo "              maps ($N_OK valid, $N_ERR invalid). Without both, a program" >&2
		echo "              that always prints 'map error' — or never does — passes." >&2
		exit 2
	fi
elif [ "$N_OK" -ge 1 ]; then
	if [ "$N_DIFF" -lt 1 ]; then
		echo "bsq_check.sh: no valid map in this corpus has an answer that differs from" >&2
		echo "              its own input, so 'cat' would pass this layer." >&2
		exit 2
	fi
	if [ "$N_ZERO" -lt 1 ]; then
		echo "bsq_check.sh: no map in this corpus has a biggest square of side 0, so a" >&2
		echo "              program that prints 'map error' whenever it finds nothing" >&2
		echo "              would pass. The corpus must contain an all-obstacle map." >&2
		exit 2
	fi
fi

# ---------------------------------------------------------------------------
# THE OPEN FORMS a readings record can hold, one sentence each, keyed by the
# slug oracle/src/bsq.rs's readings() tags it with (see THE TAGS above). A
# failing case prints its sentence, so it says which question it is about.
FORMS="$WORK/forms"
{
	printf '%s\t%s\n' count_leading_zero 'its count is written with a leading zero ("09" for 9)'
	printf '%s\t%s\n' no_final_newline 'its last row has no newline after it'
	printf '%s\t%s\n' count_plus "its count is written with a '+' in front (\"+9\")"
	printf '%s\t%s\n' count_space_before 'a space comes before its count (" 9")'
	printf '%s\t%s\n' count_space_after 'a space comes between its count and the three characters ("9 ")'
} > "$FORMS"

# ---------------------------------------------------------------------------
# CORPUS SELF-VALIDATION, before a single student run. It cannot check
# MAXIMALITY -- that is //oracle:oracle_check's job, and it is done there
# exhaustively -- but it catches a corrupted or mis-escaped record, which would
# otherwise be reported as the student's fault.
BAD_REC=$(awk -F'\t' -v FORMS="$FORMS" -v readings="$READINGS" '
	BEGIN { while ((getline l < FORMS) > 0) { split(l, kv, "\t"); form[kv[1]] = 1 } close(FORMS) }
	NF != 6 { printf "line %d: %d fields, want 6\n", NR, NF; next }
	$1 != "ok" && $1 !~ /^(ok|err):[a-z0-9_]+$/ { printf "line %d: unknown tag %s\n", NR, $1; next }
	readings + 0 == 1 && $1 == "ok" { printf "line %d: a readings record without the form it holds (ok, not ok:<form>)\n", NR }
	readings + 0 == 1 && $1 != "ok" && !(substr($1, index($1, ":") + 1) in form) {
		printf "line %d: %s names a form this runner has no sentence for (add it to FORMS)\n", NR, $1 }
	readings + 0 != 1 && $1 ~ /^ok:/ { printf "line %d: %s names an open form, and this is not a --readings corpus\n", NR, $1 }
	$1 ~ /^ok/ && $2 < 0 { printf "line %d: ok record with side %s\n", NR, $2 }
	$1 ~ /^err:/ && $6 != "map error\\n" { printf "line %d: err record whose expected is not map error\n", NR }
	$1 ~ /^ok/ && $2 > 0 && ($3 < 0 || $4 < 0) { printf "line %d: side %s but corner (%s,%s)\n", NR, $2, $3, $4 }
	' "$CORPUS")
if [ -n "$BAD_REC" ]; then
	echo "bsq_check.sh: the corpus itself is malformed — this is a harness fault," >&2
	echo "              not a deliverable fault:" >&2
	printf '%s\n' "$BAD_REC" | sed 's/^/    /' >&2
	exit 2
fi

# ---------------------------------------------------------------------------
# EACH RECORD, SPLIT ONCE, by awk, into its four numbers (one line of
# $REC/meta per record) and its two escaped blobs (a file each). The loop
# below used to cut every record apart with ${line#*TAB}, which dash does by
# trying every prefix in turn: quadratic in the record, measured at 6.7 s for
# one record of two 160 KB blobs, so a map of a million cells would have taken
# minutes before the program even ran. Read back with `IFS= read -r`, which is
# linear and keeps a blob's leading space (a space is a legal map character).
REC="$WORK/rec"
mkdir "$REC" || { echo "bsq_check.sh: cannot create a scratch directory" >&2; exit 2; }
awk -F'\t' -v d="$REC" '
	length($0) == 0 { next }
	{
		n++
		print $1, $2, $3, $4 > (d "/meta")
		print $5 > (d "/" n ".in"); close(d "/" n ".in")
		print $6 > (d "/" n ".ex"); close(d "/" n ".ex")
	}' "$CORPUS" || { echo "bsq_check.sh: could not split the corpus into records" >&2; exit 2; }

TOTAL=0
BAD=0
RUNS=0
CATS="$WORK/cats"
BLOCK="$WORK/block"
: > "$CATS"

say() { printf '%s\n' "$*"; }

# keep_input ID MAP... -- the map(s) a failing case ran on, kept in test.outputs
# as ID.map (ID-1.map, ID-2.map ... for a multi-mode run)
# with the command that replays them (tools/runner_lib.sh's rl_save). The
# corpus is generated and the scratch files go with the run, so the report
# used to name a case nobody could run again (finding 174).
keep_input() {
	_kc=$1
	shift
	_kk=0
	_knames=""
	for _km in "$@"; do
		_kk=$((_kk + 1))
		if [ "$#" -eq 1 ]; then _kf="$_kc.map"; else _kf="$_kc-$_kk.map"; fi
		if ! rl_save "$_km" "$_kf"; then
			say "   input: generated for this case (a run under bazel test keeps it)"
			return 0
		fi
		_knames="$_knames $_kf"
	done
	[ -n "$_knames" ] || return 0
	say "   input: kept in ${RL_SAVED%/*}/"
	if [ "$MODE" = stdin ]; then
		say "   replay: ./bsq <$_knames"
	else
		say "   replay: ./bsq$_knames"
	fi
}

# diagnose TAG SIDE TOP LEFT WANT GOT MAP -- what KIND of wrong one map's
# answer is, one category, most specific first: appended to $CATS, and the
# explanation printed. WANT and GOT hold that one map's expected and printed
# answer, MAP its input file. Runs only for a failure, so a green run pays
# nothing for it.
diagnose() {
	# -v, not trailing VAR=value operands: an operand assignment is processed
	# when awk reaches it while reading input, so it is still unset inside
	# BEGIN -- which is where this whole program lives. That mistake reads as
	# "your output: 0 lines" on every case, which looks like a finding.
	BSQ_Q_TIE="$Q_TIE" BSQ_Q_ERROR="$Q_ERROR" LC_ALL=C awk -v tag="$1" -v side="$2" -v top="$3" -v left="$4" \
		-v WANT="$5" -v GOT="$6" -v MAP="$7" -v CATS="$CATS" \
		-v readings="$READINGS" -v FORMS="$FORMS" "$RL_AWK_VIS"'
		function pad(w,   r) { r = ""; while (length(r) < w) r = r " "; return r }
		function quote_error(   q) {
			q = ENVIRON["BSQ_Q_ERROR"]
			gsub(/\n/, "\n       ", q)
			print "       " q
		}
		# As many lines as expected, and every line that differs is the
		# expected line with bytes after it -- a row, or "map error" -- so
		# what ends a line is wrong (a space, a carriage return) and nothing
		# before it. It was "not-a-map", whose words ask the reader to count
		# lines that were already counted right, or "accepted-invalid-file"
		# for a "map error" with a space after it.
		function rows_then_more(   i, more) {
			if (nw != ng || nw == 0) return 0
			more = 0
			for (i = 1; i <= nw; i++) {
				if (g[i] == w[i]) continue
				if (length(g[i]) <= length(w[i]) || substr(g[i], 1, length(w[i])) != w[i]) return 0
				more++
			}
			return more > 0
		}
		BEGIN {
			# ok, ok:<form> and err:<form> -- see THE TAGS at the top.
			valid = (tag ~ /^ok(:|$)/)
			slug = (index(tag, ":") > 0) ? substr(tag, index(tag, ":") + 1) : ""
			nw = 0; ng = 0
			while ((getline l < WANT) > 0) { w[++nw] = l }
			while ((getline l < GOT)  > 0) { g[++ng] = l }
			close(WANT); close(GOT)
			# The INPUT, so the student square can be found as "cells you
			# changed" rather than "cells that differ from the reference". Those
			# are not the same set: a square shifted one column differs from the
			# reference in TWO columns, which is not a square, and reporting that
			# as a mis-shaped square would send someone hunting the wrong bug.
			# Line 1 of the file is the header and is not part of the map.
			nrows = 0; hdr = ""
			if (MAP != "") {
				mi = 0
				while ((getline l < MAP) > 0) { mi++; if (mi == 1) hdr = l; else mp[++nrows] = l }
				close(MAP)
			}

			# ---- measure, before deciding anything ----
			minw = 1e9; maxw = 0
			for (i = 1; i <= ng; i++) {
				if (length(g[i]) < minw) minw = length(g[i])
				if (length(g[i]) > maxw) maxw = length(g[i])
			}
			if (ng == 0) { minw = 0; maxw = 0 }
			ewid = (nw > 0) ? length(w[1]) : 0

			lim = (nw > ng) ? nw : ng
			dl = 0; dc = 0
			for (i = 1; i <= lim && dl == 0; i++) {
				if (w[i] != g[i]) {
					dl = i
					n = length(w[i]); m = length(g[i]); k = (n > m) ? n : m
					for (j = 1; j <= k; j++)
						if (substr(w[i], j, 1) != substr(g[i], j, 1)) { dc = j; break }
					if (dc == 0) dc = (n < m ? n : m) + 1
				}
			}

			# ---- what KIND of wrong ----
			kind = "output"
			wmap = (nw == 1 && w[1] == "map error")
			gmap = (ng >= 1 && g[1] == "map error")
			if (rows_then_more())   kind = "line-end"
			else if (wmap && !gmap) kind = "accepted-invalid-file"
			else if (!wmap && gmap) kind = "map-error-unexpected"
			else if (nw == ng && minw == ewid && maxw == ewid && dl == 0) kind = "trailing-newline"
			else if (ng != nw || minw != ewid || maxw != ewid) kind = "not-a-map"
			else if (valid && nrows == ng) {
				# What the student PAINTED: cells that differ from the input.
				gt = -1; gl = -1; gb = -1; gr = -1; nch = 0; onob = 0
				fullc = (side + 0 > 0) ? substr(w[top + 1], left + 1, 1) : ""
				emptyc = (side + 0 > 0) ? substr(mp[top + 1], left + 1, 1) : ""
				for (i = 1; i <= nrows && i <= ng; i++) {
					n = length(mp[i])
					for (j = 1; j <= n; j++) {
						cm = substr(mp[i], j, 1); cg = substr(g[i], j, 1)
						if (cm == cg) continue
						nch++
						if (cm != emptyc) onob++
						if (gt < 0) gt = i
						if (gl < 0 || j < gl) gl = j
						if (i > gb) gb = i
						if (j > gr) gr = j
					}
				}
				gh = gb - gt + 1; gwid = gr - gl + 1
				if (nch == 0) kind = "no-square"
				else if (onob > 0) kind = "overwrote-obstacle"
				else if (gh != gwid || nch != gh * gwid) kind = "square-shape"
				else if (gh != side + 0) kind = "square-size"
				else kind = "square-position"
				sq_side = gh; sq_top = gt; sq_left = gl
			}
			print kind >> CATS
			close(CATS)

			# ---- report ----
			# A readings record is certain only under the reading the target
			# takes: say so, or a student is told a sentence says what it
			# leaves open.
			if (readings + 0 == 1 && tag ~ /^(ok|err):/) {
				print "   under this harness\047s reading, which its hints below state:"
				# The open form this file holds, in words: the question the
				# record is about, before what the reading answers.
				while ((getline l < FORMS) > 0) {
					split(l, kv, "\t")
					if (kv[1] == slug) printf "   the file: %s.\n", kv[2]
				}
				close(FORMS)
			}
			if (valid && side + 0 == 0)
				print "   this map is valid, and no square fits: it is printed unchanged (it has no empty cell)."
			else if (valid)
				printf "   the biggest square is %sx%s, at line %d column %d (1-based).\n", \
					side, side, top + 1, left + 1
			else if (tag ~ /^err:/) {
				printf "   this file is invalid (%s): the only correct output is one \"map error\".\n", \
					substr(tag, 5)
				# What the file says of itself: its first line, and how many lines
				# follow it -- every byte shown, a control byte as \xHH.
				printf "   its first line: \"%s\", followed by %d line(s)\n", rl_vis_exact(hdr), nrows
				if (length(hdr) > 3 && substr(hdr, 1, length(hdr) - 3) ~ /^[0-9]+$/)
					printf "   (the first line announces %s)\n", substr(hdr, 1, length(hdr) - 3)
			}
			printf "   your output: %d line(s), widths %d..%d   (expected %d line(s) of %d)\n", \
				ng, minw, maxw, nw, ewid
			if (dl > 0) {
				printf "   first difference: line %d, column %d\n", dl, dc
				# A window around the difference when the line is long, cut on
				# the raw bytes and then rendered: every byte visible (rl_vis_exact, the
				# rendering of tools/runner_lib.sh), the ^ under the rendering
				# of the bytes before it, so an escape does not push it off.
				lo = 1; hi = (length(w[dl]) > length(g[dl])) ? length(w[dl]) : length(g[dl])
				pre = ""; post = ""
				if (hi > 68) {
					lo = dc - 30; if (lo < 1) lo = 1
					hi = lo + 60
					if (lo > 1) pre = "<"
					post = ">"
				}
				# The end of each line: $ where the window shows where the line
				# ended, so a space before it is seen, > only where the window
				# cut that line (V83). rl_vis_exact writes a dollar in the text
				# as \x24, so a $ here is only ever the end of a line. A side
				# with no line dl at all (an output a line short, or empty)
				# shows nothing: a $ there would say a line ended that never
				# began, and read as a printed empty line.
				printf "     want | %s\n", (dl > nw ? "" : (pre rl_vis_exact(substr(w[dl], lo, hi - lo + 1)) (length(w[dl]) <= hi ? "$" : post)))
				printf "     got  | %s\n", (dl > ng ? "" : (pre rl_vis_exact(substr(g[dl], lo, hi - lo + 1)) (length(g[dl]) <= hi ? "$" : post)))
				printf "            %s%s^\n", (pre == "" ? "" : " "), pad(length(rl_vis_exact(substr(w[dl], lo, dc - lo))))
			}
			if (kind == "line-end")
				printf "   after what it should hold, line %d has %d byte(s) more: \"%s\"\n", \
					dl, length(g[dl]) - length(w[dl]), rl_vis_exact(substr(g[dl], length(w[dl]) + 1))
			if (sq_side > 0 && kind != "no-square")
				printf "   your square is %dx%d, at line %d column %d.\n", \
					sq_side, sq_side, sq_top, sq_left
			printf "   FAULT [%s]\n", kind
			if (kind == "square-position") {
				print "     Right size, wrong place. Where several biggest squares fit, which\n" \
				      "     one is drawn is set by this sentence:"
				q = ENVIRON["BSQ_Q_TIE"]
				gsub(/\n/, "\n       ", q)
				print "       " q
			} else if (kind == "square-size")
				print "     A solid square, but not the biggest one that fits."
			else if (kind == "square-shape")
				print "     The cells you filled are not a square."
			else if (kind == "no-square")
				print "     You printed the map back unchanged. There is a square to draw here."
			else if (kind == "accepted-invalid-file" && readings + 0 == 1) {
				print "     Under this harness\047s reading, this file breaks a validity rule.\n" \
				      "     The subject leaves it open: the hints below state the reading.\n" \
				      "     What a file that breaks one prints is set by this sentence:"
				quote_error()
			} else if (kind == "map-error-unexpected" && readings + 0 == 1)
				print "     Under this harness\047s reading, this file is valid, so it\n" \
				      "     has an answer. The subject leaves it open: the hints below state\n" \
				      "     the reading."
			else if (kind == "accepted-invalid-file") {
				print "     This file breaks one of the rules a valid map follows, and it was\n" \
				      "     answered as a map. Which rule does its first line, or its line\n" \
				      "     count, break? What a file that breaks one prints is set by this\n" \
				      "     sentence:"
				quote_error()
			} else if (kind == "map-error-unexpected")
				print "     This file is valid, so it has an answer. Re-read the validity list\n" \
				      "     and ask which rule you think it breaks."
			else if (kind == "line-end")
				print "     Each line starts with what it should, and the lines are as many as\n" \
				      "     expected; then more follows on the line. What does your program\n" \
				      "     write after a line\047s last expected byte, before the line ends?"
			else if (kind == "not-a-map")
				print "     The shape of the output is wrong before its contents are. Count the\n" \
				      "     lines you print, and remember the first line of the file is a header\n" \
				      "     rather than a row of the map."
			else if (kind == "overwrote-obstacle")
				print "     One of the cells you filled was an obstacle in the input. The\n" \
				      "     square has to fit in EMPTY cells only."
			else if (kind == "trailing-newline")
				print "     Every line of the map, including the last one, ends with a newline."
		}
	' < /dev/null
}

# The members of the group being run in multi mode, one per line of
# $WORK/members: "<tag> <side> <top> <left>", the map $WORK/map.<i> and its
# expected answer $WORK/want.<i>.
member() {  # member I -- sets M_TAG M_SIDE M_TOP M_LEFT
	# shellcheck disable=SC2046 # four words, split on purpose; a tag has no space
	set -- $(sed -n "${1}p" "$WORK/members")
	M_TAG=$1; M_SIDE=$2; M_TOP=$3; M_LEFT=$4
}

# report_single N TAG SIDE TOP LEFT -- one failing map (argv and stdin modes).
report_single() {
	say " --------------------------------------------------"
	if [ "$ENDED" = 1 ]; then
		# How it ended, from rl_sweep_ran: a timeout and runaway output are
		# their own faults, not crashes -- "DIED" sent a student hunting a bad
		# pointer in a program that simply never stopped.
		case "$RL_CAUSE" in
			"timeout") echo "did-not-finish" >> "$CATS" ;;
			"runaway") echo "runaway-output" >> "$CATS" ;;
			*) echo "crash" >> "$CATS" ;;
		esac
		say " CASE $1  [$2]  it $RL_WHY"
		rl_excerpt "$WORK/err" 6 "case-$1-stderr.txt" "     "
	elif cmp -s "$WORK/want" "$WORK/got"; then
		# The right output, and a message the call said a valid run does not
		# get (--stderr-empty): the message is the fault.
		echo "wrote-to-stderr" >> "$CATS"
		say " CASE $1  [$2]  the right output, and it wrote to standard error,"
		say "   where this check requires nothing:"
		rl_excerpt "$WORK/err" 6 "case-$1-stderr.txt" "     "
	else
		say " CASE $1  [$2]"
		diagnose "$2" "$3" "$4" "$5" "$WORK/want" "$WORK/got" "$WORK/map"
		stderr_too "case-$1"
	fi
	keep_input "case-$1" "$WORK/map"
}

# stderr_too NAME -- under a diagnosed answer, what the run also wrote to
# standard error: the fault itself under --stderr-empty, and otherwise often
# the explanation of the difference above.
stderr_too() {
	[ -s "$WORK/err" ] || return 0
	say "   it also wrote to standard error:"
	rl_excerpt "$WORK/err" 3 "$1-stderr.txt" "     "
}

# report_group K -- the failing run RUNS, of K maps (multi mode). The output is
# split where it has a blank line, which the subject puts between two maps'
# answers and which no answer holds, and compared map by map: the first map
# whose answer differs is diagnosed as a single map would be.
report_group() {
	_rk=$1
	_rn="run-$RUNS"
	set --
	_ri=0
	while [ "$_ri" -lt "$_rk" ]; do _ri=$((_ri + 1)); set -- "$@" "$WORK/map.$_ri"; done
	say " --------------------------------------------------"
	say " RUN $RUNS  [maps $((TOTAL - _rk + 1))-$TOTAL of the corpus: $(awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $1 }' "$WORK/members")]"
	if [ "$ENDED" = 1 ]; then
		case "$RL_CAUSE" in
			"timeout") echo "did-not-finish" >> "$CATS" ;;
			"runaway") echo "runaway-output" >> "$CATS" ;;
			*) echo "crash" >> "$CATS" ;;
		esac
		say "   it $RL_WHY"
		rl_excerpt "$WORK/err" 6 "$_rn-stderr.txt" "     "
		keep_input "$_rn" "$@"
		return 0
	fi
	# The right output, and a message the call said a valid run does not get
	# (--stderr-empty): the message is the fault.
	if cmp -s "$WORK/want" "$WORK/got"; then
		echo "wrote-to-stderr" >> "$CATS"
		say "   the right output, and it wrote to standard error, where this check"
		say "   requires nothing:"
		rl_excerpt "$WORK/err" 6 "$_rn-stderr.txt" "     "
		keep_input "$_rn" "$@"
		return 0
	fi
	# The whole output but its final newline, first: split into lines below,
	# that one byte would be invisible.
	if [ -s "$WORK/got" ] && [ "$(tail -c 1 "$WORK/got" | wc -l)" -eq 0 ]; then
		{ cat "$WORK/got"; echo; } > "$WORK/got.nl"
		if cmp -s "$WORK/want" "$WORK/got.nl"; then
			echo "trailing-newline" >> "$CATS"
			say "   FAULT [trailing-newline]"
			say "     Every line of the map, including the last one, ends with a newline."
			keep_input "$_rn" "$@"
			return 0
		fi
	fi
	rm -f "$WORK"/got.[0-9]*
	awk -v dir="$WORK" 'BEGIN { i = 1 } $0 == "" { i++; next } { print > (dir "/got." i) }' "$WORK/got"
	_parts=0
	[ ! -s "$WORK/got" ] || _parts=$(awk '$0 == "" { n++ } END { print n + 1 }' "$WORK/got")
	# The same lines with the blank ones taken out, on both sides: equal,
	# and every map was answered right -- what is wrong is the blank lines.
	awk 'length($0)' "$WORK/want" > "$WORK/want.flat"
	awk 'length($0)' "$WORK/got" > "$WORK/got.flat"
	if cmp -s "$WORK/want.flat" "$WORK/got.flat"; then
		echo "blank-lines" >> "$CATS"
		say "   every map was answered right, but your output has $_parts part(s) where"
		say "   blank lines split it; $_rk maps need $_rk answers with ONE blank line"
		say "   between each two, none before the first and none after the last."
		say "   FAULT [blank-lines]"
		keep_input "$_rn" "$@"
		return 0
	fi
	_ri=0
	while [ "$_ri" -lt "$_rk" ]; do
		_ri=$((_ri + 1))
		[ -f "$WORK/got.$_ri" ] || : > "$WORK/got.$_ri"
		cmp -s "$WORK/want.$_ri" "$WORK/got.$_ri" && continue
		member "$_ri"
		say "   map $_ri of $_rk is the first whose answer differs [$M_TAG]"
		[ "$_parts" -eq "$_rk" ] ||
			say "   (your output has $_parts part(s) where blank lines split it, for $_rk maps)"
		diagnose "$M_TAG" "$M_SIDE" "$M_TOP" "$M_LEFT" "$WORK/want.$_ri" "$WORK/got.$_ri" "$WORK/map.$_ri"
		stderr_too "$_rn"
		keep_input "$_rn" "$@"
		return 0
	done
	# Every map's answer matches, the parts are as many as the maps, yet the
	# bytes differ: what remains is between the parts.
	echo "blank-lines" >> "$CATS"
	say "   every map was answered right; what differs is between the answers."
	say "   FAULT [blank-lines]"
	keep_input "$_rn" "$@"
}

# Runs one case and classifies how it ended (rl_sweep_ran). STARTED is 0 when
# there was no time left to start it: the caller then stops the sweep. ENDED is
# 1 when the run did not RETURN -- a signal, the time limit or the output
# budget ended it -- which tools/exit_status reads from waitpid(): a return of
# any number, 128 and 255 included, is a return.
run_one() {
	# $@ = the map path(s); stdin handled here
	STARTED=0
	rl_sweep_next "$TMO" || return 0
	STARTED=1
	RUNS=$((RUNS + 1))
	if [ "$MODE" = stdin ]; then
		rl_run "$BIN" > "$WORK/got" 2> "$WORK/err" < "$1"
	else
		# < /dev/null is load-bearing: the loop's own stdin is the corpus, a
		# child inherits it, and a program that reads stdin when it was handed
		# argv files would eat the remaining cases -- the loop would end after
		# one iteration and this runner would report "OK, 1 case".
		rl_run "$BIN" "$@" > "$WORK/got" 2> "$WORK/err" < /dev/null
	fi
	_rl_st=$?
	rl_sweep_ran "$_rl_st"
	# Named the way the report names the case: a map, or a run of several.
	if [ "$MODE" = multi ]; then
		rl_stderr "$WORK/err" "run $RUNS"
	else
		rl_stderr "$WORK/err" "case $TOTAL"
	fi
	case "$RL_CAUSE" in
		ok | "exit") ENDED=0 ;;
		noexec)
			echo "bsq_check.sh: the program $RL_WHY" >&2
			exit 2 ;;
		*) ENDED=1 ;;
	esac
	return 0
}

# The output cap, set once now that the corpus is written: a program printing
# without end is stopped by SIGXFSZ at 32 MiB instead of filling the test's
# scratch space. The largest map in the corpus answers in a few KiB.
ulimit -f 65536 2> /dev/null || true

case "$MODE" in
	argv) _how="one exec per map, as its argument" ;;
	stdin) _how="one exec per map, on standard input" ;;
	multi) _how="up to $GROUP maps per exec" ;;
esac
case "$RL_MEM" in
	sanitized) _how="$_how, under ASan/UBSan" ;;
	"valgrind") _how="$_how, $RL_MEM_SAMPLE of them under memcheck" ;;
esac
printf 'bsq_check: %s, seed %s, %s map(s), %s\n\n' "$FN" "$SEED" "$GOT_CASES" "$_how"
# Multi mode's case count, for the sample: one case per run.
NGROUPS=$(( (GOT_CASES + GROUP - 1) / GROUP ))

GN=0
: > "$WORK/want"
: > "$WORK/members"

# run_group -- the maps gathered so far, in one exec, then judged.
run_group() {
	set --
	_gi=0
	while [ "$_gi" -lt "$GN" ]; do _gi=$((_gi + 1)); set -- "$@" "$WORK/map.$_gi"; done
	run_one "$@"
	[ "$STARTED" = 1 ] || return 0
	if ! cmp -s "$WORK/want" "$WORK/got" || [ "$ENDED" = 1 ] || rl_stderr_noisy "$WORK/err"; then
		BAD=$((BAD + 1))
		report_group "$GN" > "$BLOCK"
		rl_block "$BLOCK"
	fi
}

# mem_group -- the maps gathered so far (multi mode) as one run under the
# memory checker, when that run is in the sample. The run is the case: it is
# what the sample picks from, what the report names, and what it keeps to
# replay -- a report from a run of several maps cannot say which map, but the
# run can be replayed whole, and the leftovers of one map met by the reading
# of the next are a path no run of one map reaches.
mem_group() {
	_mg=$(( (TOTAL + GROUP - 1) / GROUP ))
	_mn=$GN
	GN=0
	STARTED=1
	set --
	_gi=0
	while [ "$_gi" -lt "$_mn" ]; do _gi=$((_gi + 1)); set -- "$@" "$WORK/map.$_gi"; done
	_mtags=$(awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $1 }' "$WORK/members")
	: > "$WORK/members"
	rl_mem_pick "$_mg" "$NGROUPS" || return 0
	rl_sweep_next "$TMO" || { STARTED=0; return 0; }
	RUNS=$((RUNS + 1))
	rl_mem_run --what "run $_mg" -- "$@"
	[ "$RL_MEM_BAD" = 1 ] || return 0
	BAD=$((BAD + 1))
	{
		say " --------------------------------------------------"
		say " RUN $_mg  [$RL_MEM_KIND]  maps $((TOTAL - _mn + 1))-$TOTAL of the corpus: $_mtags"
		keep_input "run-$_mg" "$@"
		rl_mem_report
	} > "$BLOCK"
	rl_block "$BLOCK"
}

while read -r tag side top left; do
	TOTAL=$((TOTAL + 1))
	IFS= read -r einp < "$REC/$TOTAL.in"
	IFS= read -r eexp < "$REC/$TOTAL.ex"

	# UNDER A MEMORY CHECKER the map -- or in multi mode the run of maps --
	# runs when it is in the sample, and only memory and how the run ended
	# are judged (tools/runner_lib.sh).
	if [ -n "$RL_MEM" ] && [ "$MODE" = multi ]; then
		GN=$((GN + 1))
		printf '%b' "$einp" > "$WORK/map.$GN"
		printf '%s\n' "$tag" >> "$WORK/members"
		[ "$GN" -lt "$GROUP" ] && continue
		mem_group
		[ "$STARTED" = 1 ] || break
		[ -z "$RL_STOP" ] || break
		continue
	fi
	if [ -n "$RL_MEM" ]; then
		rl_mem_pick "$TOTAL" "$GOT_CASES" || continue
		printf '%b' "$einp" > "$WORK/map"
		rl_sweep_next "$TMO" || { TOTAL=$((TOTAL - 1)); break; }
		RUNS=$((RUNS + 1))
		if [ "$MODE" = stdin ]; then
			rl_mem_run --what "case $TOTAL" --stdin "$WORK/map" --
		else
			rl_mem_run --what "case $TOTAL" -- "$WORK/map"
		fi
		if [ "$RL_MEM_BAD" = 1 ]; then
			BAD=$((BAD + 1))
			{
				say " --------------------------------------------------"
				say " CASE $TOTAL  [$RL_MEM_KIND]  a map tagged $tag"
				keep_input "case-$TOTAL" "$WORK/map"
				rl_mem_report
			} > "$BLOCK"
			rl_block "$BLOCK"
		fi
		[ -z "$RL_STOP" ] || break
		continue
	fi
	if [ "$MODE" = multi ]; then
		GN=$((GN + 1))
		printf '%b' "$einp" > "$WORK/map.$GN"
		printf '%b' "$eexp" > "$WORK/want.$GN"
		printf '%s %s %s %s\n' "$tag" "$side" "$top" "$left" >> "$WORK/members"
		# One blank line BETWEEN outputs: each expected blob already ends in a
		# newline, so a bare newline before every blob but the first is exactly
		# one empty line between them, none before the first, none after the last.
		[ "$GN" -eq 1 ] || printf '\n' >> "$WORK/want"
		cat "$WORK/want.$GN" >> "$WORK/want"
		[ "$GN" -lt "$GROUP" ] && continue
		run_group
		[ "$STARTED" = 1 ] || { TOTAL=$((TOTAL - GN)); break; }
		GN=0; : > "$WORK/want"; : > "$WORK/members"
		[ -z "$RL_STOP" ] || break
		continue
	fi

	printf '%b' "$einp" > "$WORK/map"
	printf '%b' "$eexp" > "$WORK/want"
	run_one "$WORK/map"
	[ "$STARTED" = 1 ] || { TOTAL=$((TOTAL - 1)); break; }
	if ! cmp -s "$WORK/want" "$WORK/got" || [ "$ENDED" = 1 ] || rl_stderr_noisy "$WORK/err"; then
		BAD=$((BAD + 1))
		report_single "$TOTAL" "$tag" "$side" "$top" "$left" > "$BLOCK"
		rl_block "$BLOCK"
	fi
	[ -z "$RL_STOP" ] || break
done < "$REC/meta"

# a trailing partial group in multi mode still has to be run
if [ -z "$RL_STOP" ] && [ "$MODE" = multi ] && [ "$GN" -gt 0 ]; then
	if [ -n "$RL_MEM" ]; then
		mem_group
	else
		run_group
		[ "$STARTED" = 1 ] || TOTAL=$((TOTAL - GN))
	fi
fi

rl_tally
if [ -n "$RL_MEM" ]; then
	# What a checker's case is: a map, or in multi mode a run.
	if [ "$MODE" = multi ]; then
		_mcases=$NGROUPS
		_munit="run(s)"
	else
		_mcases=$GOT_CASES
		_munit="case(s)"
	fi
	if [ -n "$RL_STOP" ]; then
		echo ""
		rl_mem_count "$_mcases"
		rl_mem_stopped "$RUNS"
		exit 1
	fi
	rl_mem_tally "$RUNS" "$_mcases" "$_munit"
	_mt=$?
	# The maps' names are arguments, but on standard input there are none.
	[ "$MODE" = stdin ] || rl_mem_argv_note 0
	exit "$_mt"
fi
echo ""
# What the tally counts: maps, one per run, in argv and stdin modes; RUNS in
# multi mode, where a failing run is one failure whatever the number of maps
# in it -- counting it against the maps made "7 of 355 differ" out of 7 of 119
# runs (finding 174).
if [ "$MODE" = multi ]; then
	_unit="runs"
	_all=$RUNS
	_of=" ($TOTAL maps, up to $GROUP per run)"
else
	_unit="maps"
	_all=$TOTAL
	_of=""
fi
# A run that did not finish in its time was not judged wrong: nothing it
# printed was compared, and BSQ's subject sets no time limit, so the big maps'
# limit is a guard against a hang, never a deadline (the owner's ruling R4).
# Counted in $BAD, since it is not a pass, but told apart from a wrong answer
# in every line below: a correct, slow program on a million cells used to
# read "4/5 maps agree, 1 differ".
_dnf=$(grep -c '^did-not-finish$' "$CATS") || _dnf=0
_wrong=$((BAD - _dnf))
if [ -n "$RL_STOP" ]; then
	# The cases judged wrong before the sweep stopped, not counting any the
	# time ran out in (counted in $BAD, but cut short, not wrong): a verdict,
	# which keeps the report from reading as "ran out of time" alone.
	if [ "$MODE" = multi ]; then
		rl_sweep_stopped "$RUNS" "$NGROUPS" "$_wrong"
	else
		rl_sweep_stopped "$TOTAL" "$GOT_CASES" "$_wrong"
	fi
	exit 1
fi
if [ "$BAD" -eq 0 ]; then
	echo "bsq_check: OK — $_all/$_all $_unit agree with the reference$_of (fn=$FN, seed=$SEED, mode=$MODE)"
	rl_stderr_rule
	rl_stderr_note
	exit 0
fi
echo "  BY FAULT:"
sort "$CATS" | uniq -c | sort -rn | sed 's/^/    /'
rl_stderr_note
# Only where an answer was shown: a run that did not finish has no want and
# got lines. The marks are named from the lines the report showed
# (rl_shown_legend): a legend written once named a tab, a backslash and a
# dollar under maps that held none of them.
if [ "$_wrong" -ne 0 ]; then
	echo ""
	echo "  In the want and got lines, and a file's first line, every byte is"
	echo "  visible. < and > mark a line cut to a window around the difference."
	# Named only under a report that shows one: a want or got line that ends
	# in $ (an escaped dollar is \x24, so the last byte is the mark).
	grep -Eq '^ +(want [|] |got  [|] ).*[$]$' "$RL_SHOWNF" 2> /dev/null &&
		echo "  \$ is where a line ended."
	rl_shown_legend '^ +(want [|] |got  [|] |its first line: ")'
fi
echo ""
if [ "$_dnf" -eq 0 ]; then
	echo "bsq_check: FAIL — $((_all - BAD))/$_all $_unit agree, $BAD differ$_of."
elif [ "$_wrong" -eq 0 ]; then
	echo "bsq_check: FAIL — $((_all - BAD))/$_all $_unit agree, and $_dnf did not finish within"
	echo "  ${TMO}s each$_of. No answer was judged wrong: a run that did not finish printed"
	echo "  nothing that was compared. An infinite loop, or a method too slow for maps"
	echo "  this size: the limit guards against a hang and is no deadline, so only the"
	echo "  first is a fault."
else
	echo "bsq_check: FAIL — $((_all - BAD))/$_all $_unit agree, $_wrong differ, and $_dnf did not"
	echo "  finish within ${TMO}s each$_of."
fi
rl_clues "$CLUES" "" "" "$CASE_NAME"
exit 1
