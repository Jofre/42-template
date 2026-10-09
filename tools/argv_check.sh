#!/bin/sh
# argv_check.sh — differential check for a program whose input is its ARGUMENTS.
#
# Runs the student's binary once per case against a corpus //oracle generated,
# and reports the first differences as a table.
#
# Usage:
#   argv_check.sh --bin PATH --oracle PATH --fn NAME
#                 [--seed N] [--count N] [--show N] [--expect-reordering]
#                 [--exit-only | --sanitized [--guarded-argv] | --valgrind PATH
#                  --valgrind-tools FILE [--sample N] [--rule FILE]]
#                 (--stderr-empty | --stderr-ignored REASON)
#
#   --show N      how many failing cases to print (default DIFF_MAX_ROWS, 40;
#                 0 prints all); every one is kept in test.outputs either way
#   --exit-only   replay the same corpus and judge only how each run ended: a
#                 plain non-zero return fails, and the output is not compared.
#                 That is the robust exNN_argv_diff_exit target; see below.
#   --sanitized   BIN is the ASan/UBSan build: replay the corpus judging memory
#                 and how each run ended, never the output (exNN_argv_diff_asan;
#                 tools/runner_lib.sh, "A CORPUS UNDER A MEMORY CHECKER").
#                 C 06's subject allows no malloc, so there is no --valgrind
#                 target, though the runner takes one. With --symbolizer PATH
#                 --symbolizer-lib FILE, the pinned llvm-symbolizer names each
#                 frame of a report's stack (runner_lib.sh, rl_sanitizers).
#   --guarded-argv  with --sanitized: BIN is the guarded build (c_argv_table's
#                 exNN_argvguard_bin_asan, tools/argv_guard_main.c): argv and
#                 each argument in a heap block of exactly its size, so a read
#                 past an argument's end, or past argv[argc], is a sanitizer
#                 report. Without it, under --sanitized, the arguments lie
#                 where the kernel put them, which the sanitizer does not
#                 watch, and the verdict says so (finding 071: the corpus
#                 twins ran the unguarded build and said nothing of it).
#   (--note is gone: it carried C 06 ex03's reason for sitting at robust, and
#   that reason is now docs/reference.md's row, which runner_lib.sh's
#   rl__raised prints under the red of every raised test -- one place.)
#   --stderr-empty
#                 a case also fails when the program writes anything to
#                 standard error, its output right or not
#   --stderr-ignored REASON
#                 standard error is not judged: it is shown beside a case
#                 that failed, and the PASS line says why
#
# ONE OF THE LAST TWO IS REQUIRED (exit 2 without it, or with both): what
# standard error is held to is the call site's decision, by the Run contract.
# This runner threw it away on every run, which decided it by default
# (tools/runner_lib.sh, STANDARD ERROR, A CHOICE AT EVERY CALL; review of
# WP-50). tools/defs.bzl refuses such a call while loading (_RUNNER_CHOICES).
# Under --sanitized or --valgrind neither is given: standard error carries the
# checker's report there, and no output is judged.
#
# Env: ARGV_TIMEOUT  seconds one case may run (default 5), capped by what is
#                    left of the test's own limit (tools/runner_lib.sh). After
#                    three cases that run out of their own time the sweep stops
#                    and says how many it did not try.
#      DIFF_MAX_ROWS the default of --show (tools/runner_lib.sh, rl_rows)
#
# NO GATE, unlike bsq_check.sh. That one skips while the exercise's own example
# is red, because replaying hundreds of generated maps then says the same thing
# hundreds of times. c-06's first-red layer is its argv TABLE -- one labelled
# row per hand-written scenario -- and it is a separate target that stays red on
# its own. A wall here collapses to one line anyway: the report shows the first
# --show cases and then tallies the rest by kind, so an unwritten exercise reads
# as "200 of 200 differ, by kind: 200 no-output".
#
# NOT argv[0]. A program that must print its own invocation name needs to be
# COPIED to that name and run there, and tools/progname_test.sh already does
# exactly that, under two names. c-06 ex00 uses that layer; a second one here
# would be a copy.
#
# THE EXIT STATUS is not this layer's verdict, by the rule in docs/reference.md
# ("Run contract"): C 06's subject names none. A signal still fails a case -- a
# crash is never a pass -- but a plain non-zero return is only NOTED here, and
# failed by --exit-only, which replays the SAME generated corpus at robust. Not
# by c_argv_table's exNN_exit: that one replays the table's hand-written rows,
# and a return that only a generated argument provokes -- a byte above 0x7f,
# say -- would be noted here and failed nowhere.
#
# How a run ended is read from waitpid() by tools/exit_status, not guessed
# from the status: the shell reports "killed by signal N" as 128+N, which a
# program can also return (`return (-1);` is 255), so no boundary on the
# number tells the two apart. rl_run and rl_classify (tools/runner_lib.sh) do
# that for every runner.
#
# THE REPORT IS BYTE-EXACT. Every argv:, expected: and got: line goes through
# rl_vis (tools/runner_lib.sh), which prints printable ASCII as it is and every
# other byte as an escape, so a byte above 0x7f, a control byte, a trailing
# space and a missing final newline are all things a student can SEE. There is
# no curated hint list (no diff_clues): the one hint is computed, the property
# every failing case shares when there is one, which says where to look and
# never what to change.
#
# WHY THIS EXISTS BESIDE bsq_check.sh AND rush02_check.sh. Those two each carry
# a corpus shape their subject forced: bsq's cases are FILES and rush-02's is a
# single number with a dictionary. c-06's four programs share one shape -- a
# list of arguments and the bytes they must produce -- and nothing about it is
# specific to c-06, so it is written once here rather than four times there.
#
# ONE EXEC PER CASE, for the reason rush02_check.sh gives: a program that takes
# its input on the command line cannot be streamed. The count stays in the
# hundreds. That is a property of the subject, not a shortcut.
#
# THE CORPUS LINE, and why it is peeled rather than read into fields:
#
#     <tag>\t<nargs>\t<arg1>\t...\t<argN>\t<escaped-expected>
#
# `IFS=$TAB read a b c` cannot parse this. Tab is IFS whitespace, so a RUN of
# tabs is one separator and an empty field vanishes -- and an empty argument is
# one of the four cases this layer exists for. Peeling with ${x%%...} and
# ${x#...} keeps every field, including the empty ones. nargs is in the line so
# that the peel is exact rather than a guess about which tab ends the arguments.
#
# Every field is POSIX-escaped (`\n`, `\t`, `\\`, `\0NNN` octal). dash's
# `printf %b` decodes `\0NNN` and prints `\xHH` back literally, which is why the
# reference emits octal and asserts that it never emits hex.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "argv_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat cmp mktemp rm sed sort tail uniq wc

# The shared runner helpers: the time budget, signal traps, how a run ended,
# byte rendering and excerpts (tools/runner_lib.sh, which says why each is
# written once).
RL_NAME=argv_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "argv_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool ORACLE -- the Rust reference (//oracle), which writes the corpus

BIN=""
ORACLE=""
FN=""
SEED=1
COUNT=200
SHOW=""
# Each case's own cap. A c-06 program answers in milliseconds, so this only
# ever stops one that does not stop; the test's time limit caps it too.
CASE_TMO="${ARGV_TIMEOUT:-5}"
EXPECT_REORDER=0
EXIT_ONLY=0
GUARDED=0
STDERR_EMPTY=0
STDERR_WHY=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "argv_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--seed) need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--show) need "$1" "$#"; SHOW="$2"; shift 2 ;;
		--expect-reordering) EXPECT_REORDER=1; shift ;;
		--exit-only) EXIT_ONLY=1; shift ;;
		--guarded-argv) GUARDED=1; shift ;;
		--stderr-empty) STDERR_EMPTY=1; shift ;;
		--stderr-ignored) need "$1" "$#"; STDERR_WHY="$2"; shift 2 ;;
		--sanitized | --valgrind | --valgrind-tools | --sample | --rule | --symbolizer | --symbolizer-lib)
			rl_mem_opt "$@"; shift "$RL_MEM_SHIFT" ;;
		*) echo "argv_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$BIN" ] || { echo "argv_check.sh: --bin is required" >&2; exit 2; }
[ -n "$ORACLE" ] || { echo "argv_check.sh: --oracle is required" >&2; exit 2; }
[ -n "$FN" ] || { echo "argv_check.sh: --fn is required" >&2; exit 2; }
rl_stderr_choice
[ -x "$BIN" ] || { echo "argv_check.sh: not executable: $BIN" >&2; exit 2; }
[ -x "$ORACLE" ] || { echo "argv_check.sh: not executable: $ORACLE" >&2; exit 2; }
rl_rows "$SHOW"
rl_mem_ready
if [ "$GUARDED" = 1 ] && [ "$RL_MEM" != sanitized ]; then
	echo "argv_check.sh: --guarded-argv describes a replay under the sanitizer; it needs --sanitized" >&2
	exit 2
fi
if [ "$EXIT_ONLY" = 1 ] && [ -n "$RL_MEM" ]; then
	echo "argv_check.sh: --exit-only and --$RL_MEM are two targets, not one: each" >&2
	echo "  judges the same runs its own way." >&2
	exit 2
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
[ -f "$_sl" ] || { echo "argv_check.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
standin_check argv_check "$BIN" "$RL_STANDIN" "the program"

WORK=$(mktemp -d) || exit 2
rl_traps 'rm -rf "$WORK"'


TAB=$(printf '\t')

# Decode one escaped field WITHOUT losing a trailing newline.
#
# `v=$(printf '%b' "$f")` is wrong here and the difference is a whole class of
# case: command substitution strips every trailing newline, so an expected block
# that ENDS in one -- which every one of them does -- would arrive a byte short
# and the layer would report a difference the student did not cause. The
# sentinel dot is the last byte, so nothing of the value is stripped, and it is
# removed afterwards.
#
# Only for the block that is REDIRECTED to a file. A caller writing
# `$(dec "$x")` wraps a second substitution around the first and loses exactly
# what this preserves; the argument peel does the same two lines inline for
# that reason.
dec() {
	_d=$(printf '%b.' "$1")
	printf '%s' "${_d%.}"
}

"$ORACLE" "$FN" "$SEED" "$COUNT" > "$WORK/corpus.tsv" 2> "$WORK/oracle.err" || {
	echo "argv_check: the reference failed to produce a corpus for '$FN'." >&2
	rl_excerpt "$WORK/oracle.err" 10 oracle-stderr.txt >&2
	exit 2
}

CASES=$(wc -l < "$WORK/corpus.tsv")

# Every argv:, expected: and got: line is rendered by rl_vis (runner_lib.sh):
# printable ASCII as it is, the backslash doubled, $ ending a line and a literal
# dollar as \x24, \t, \n inside an argument, \xHH for any other byte, and "(no
# newline at end)" on an unterminated output. Only the first six lines of an
# output are shown; the rest is counted.

# ends_nl FILE -- true when FILE's last byte is a newline.
ends_nl() {
	[ "$(tail -c 1 "$1" | wc -l)" -eq 1 ]
}

# ---------------------------------------------------------------------------
# FLOORS. Every one of these is a corpus that would pass a program that does
# nothing of what the exercise asks, so a corpus failing them is a layer
# reporting OK having checked nothing -- exit 2, not 1.
MIN_CASES=${MIN_ARGV_CASES:-12}
if [ "$CASES" -lt "$MIN_CASES" ]; then
	echo "argv_check: only $CASES cases (floor $MIN_CASES). Refusing to report OK." >&2
	exit 2
fi

# The properties a hand-written case never has, checked ON THE CORPUS rather
# than assumed from the generator's source.
_probe=$(awk -F'\t' '
	{
		n = $2 + 0
		if (n == 0) zero = 1
		if (n >= 2) multi = 1
		for (i = 3; i < 3 + n; i++) {
			if ($i == "") empty = 1
			if ($i ~ /\\/) esc = 1
		}
		if ($NF != "") nonempty = 1
	}
	END { printf "%d %d %d %d %d", zero, multi, empty, esc, nonempty }
' "$WORK/corpus.tsv")
set -- $_probe
[ "$1" = 1 ] || { echo "argv_check: no case with ZERO arguments. A program that prints a newline regardless would pass." >&2; exit 2; }
[ "$2" = 1 ] || { echo "argv_check: no case with two or more arguments." >&2; exit 2; }
[ "$3" = 1 ] || { echo "argv_check: no EMPTY argument. A loop that stops on the first empty string would pass." >&2; exit 2; }
[ "$4" = 1 ] || { echo "argv_check: no argument needing an escape. Whitespace and high bytes are half of what this layer is for." >&2; exit 2; }
[ "$5" = 1 ] || { echo "argv_check: every expected block is empty. A program that prints nothing would pass." >&2; exit 2; }

# For the arms where the ORDER is the answer: at least one case whose expected
# block is not the arguments in the order they were given. Without it a
# `ft_rev_params` corpus of palindromic cases would be passed by a program that
# does not reverse anything at all.
if [ "$EXPECT_REORDER" = 1 ]; then
	_reorder=$(awk -F'\t' '
		{
			n = $2 + 0
			plain = ""
			for (i = 3; i < 3 + n; i++) plain = plain $i "\\n"
			if ($NF != plain) { print "yes"; exit }
		}
	' "$WORK/corpus.tsv")
	[ "$_reorder" = "yes" ] || {
		echo "argv_check: no case where the output order differs from the input order," >&2
		echo "            so a program that just echoes its arguments would pass." >&2
		exit 2
	}
fi

# ---------------------------------------------------------------------------
# THE REPLAY.
#
# Bounded twice, as every sweep here is: in time by rl_sweep_next (each case's
# own cap, and what is left of the test's limit), and in size by `ulimit -f`,
# set once now that the corpus is written: a program printing without end is
# stopped by SIGXFSZ at 8 MiB instead of filling the test's scratch space. A
# case's expected block is a few hundred bytes.
ulimit -f 16384 2> /dev/null || true
FAILED=0
# Of FAILED, the cases whose output was right and which failed only for what
# they wrote to stderr (--stderr-empty): the headline counts them apart.
NOISY_ONLY=0
CHECKED=0
# Cases read from the corpus; CHECKED counts those run, which under memcheck
# is a sample of them.
SEEN=0
# Plain non-zero returns: noted, failed only under --exit-only. See the
# header.
NONZERO=0
NZ_FIRST=""
# Line numbers of the corpus cases that failed, for the family lines below.
LNO=0
: > "$WORK/faults"
: > "$WORK/report"
: > "$WORK/failed_lines"

# What KIND of difference is this? A hundred failures that are all one mistake
# should read as one mistake. The categories are ordered most-specific first.
classify() {  # classify EXPECTED-FILE GOT-FILE (after rl_sweep_ran)
	case "$RL_CAUSE" in
		"timeout") echo "did-not-finish"; return ;;
		"runaway") echo "runaway-output"; return ;;
		"signal") echo "crash"; return ;;
	esac
	if [ ! -s "$2" ] && [ -s "$1" ]; then echo "no-output"; return; fi
	if [ -s "$2" ] && [ ! -s "$1" ]; then echo "output-when-none-expected"; return; fi
	# The bytes agree but for one newline at the very end. Tested BEFORE the
	# order, byte for byte with cmp: `sort` reads an unterminated last line as
	# a whole one, so an output that only lacked its final newline sorted equal
	# to the expected one and was reported as wrong-order -- 160 of 174 cases
	# on a real ex01 that printed its newline between arguments, in the right
	# order every time.
	{ cat "$2"; printf '\n'; } > "$WORK/g_nl"
	if cmp -s "$1" "$WORK/g_nl"; then echo "missing-final-newline"; return; fi
	{ cat "$1"; printf '\n'; } > "$WORK/w_nl"
	if cmp -s "$WORK/w_nl" "$2"; then echo "extra-final-newline"; return; fi
	# Same lines, different order: the content is right and the ordering rule
	# is not. That is ft_rev_params and ft_sort_params's whole exercise, and it
	# is worth saying so rather than printing two blocks of identical text. If
	# the final newline differs as well, both are named.
	#
	# LC_ALL=C, because the corpus contains bytes that are not valid UTF-8 and
	# `sort` under a UTF-8 locale neither orders nor even accepts them
	# reliably. Without it a case whose only fault was the order came out as
	# the vaguer "content", which is the category that tells a student least.
	if LC_ALL=C sort "$1" > "$WORK/s1" 2> /dev/null &&
		LC_ALL=C sort "$2" > "$WORK/s2" 2> /dev/null &&
		cmp -s "$WORK/s1" "$WORK/s2"; then
		if ends_nl "$1" && ! ends_nl "$2"; then
			echo "wrong-order, missing-final-newline"
		elif ! ends_nl "$1" && ends_nl "$2"; then
			echo "wrong-order, extra-final-newline"
		else
			echo "wrong-order"
		fi
		return
	fi
	if [ "$(wc -l < "$1")" -ne "$(wc -l < "$2")" ]; then echo "line-count"; return; fi
	echo "content"
}

# show_argv ARG... -- a failing case's arguments: each byte visible (rl_vis),
# then as a command line that gives the program exactly these bytes again
# (rl_shword), to replay the case by hand.
show_argv() {
	printf '    argv:     '
	if [ "$#" -eq 0 ]; then
		printf '(none)'
	else
		for _a in "$@"; do
			printf '[%s] ' "$(printf '%s' "$_a" | rl_vis arg)"
		done
	fi
	printf '\n    replay:   ./a.out'
	for _a in "$@"; do
		printf ' %s' "$(printf '%s' "$_a" | rl_shword)"
	done
	printf '\n'
}

while IFS= read -r line; do
	# A sweep that has stopped (rl_sweep_ran set RL_STOP) starts no more cases.
	# Checked HERE, at the top: the body below `continue`s past its end.
	[ -z "$RL_STOP" ] || break
	LNO=$((LNO + 1))
	[ -n "$line" ] || continue
	SEEN=$((SEEN + 1))
	tag=${line%%"$TAB"*}; rest=${line#*"$TAB"}
	nargs=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}

	# Peel exactly nargs fields, then whatever is left is the expected block.
	# `set --` builds the real argument vector, so an argument containing a
	# space or a newline stays ONE argument all the way to execve -- which is
	# the difference this layer is looking for in the first place.
	set --
	_i=0
	while [ "$_i" -lt "$nargs" ]; do
		_f=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}
		# The sentinel is stripped HERE and not inside a helper. `$(dec ...)`
		# would be a second command substitution wrapped around the first, and
		# the outer one strips the trailing newline the inner one went to
		# trouble to keep -- which showed up as eleven of a hundred and twenty
		# CORRECT cases reported as differences, every one of them an argument
		# ending in a newline.
		_v=$(printf '%b.' "$_f")
		set -- "$@" "${_v%.}"
		_i=$((_i + 1))
	done
	dec "$rest" > "$WORK/want"

	# UNDER A MEMORY CHECKER the case runs when it is in the sample, and only
	# memory and how it ended are judged (tools/runner_lib.sh, rl_mem_run).
	if [ -n "$RL_MEM" ]; then
		rl_mem_pick "$SEEN" "$CASES" || continue
		rl_sweep_next "$CASE_TMO" || break
		CHECKED=$((CHECKED + 1))
		rl_mem_run --what "case $SEEN" -- "$@"
		[ "$RL_MEM_BAD" = 1 ] || continue
		FAILED=$((FAILED + 1))
		{
			printf '\n  case %d  [%s]  %s\n' "$SEEN" "$tag" "$RL_MEM_KIND"
			show_argv "$@"
			rl_mem_report
		} > "$WORK/block"
		rl_block "$WORK/block" >> "$WORK/report"
		continue
	fi

	# `< /dev/null` on every run. Without it a program that reads stdin
	# consumes the rest of the corpus, the loop ends early, and the layer
	# reports "OK, 1 case" -- green, having checked almost nothing.
	rl_sweep_next "$CASE_TMO" || break
	# stderr goes to a file: --stderr-empty judges it, a case that wrote to
	# it is said either way (rl_stderr), and a dynamic loader that stopped
	# the program before main says so there, which tools/exit_status reads.
	rl_run "$BIN" "$@" < /dev/null > "$WORK/got" 2> "$WORK/err"
	st=$?
	CHECKED=$((CHECKED + 1))
	# How it ended, from waitpid() (rl_classify, through rl_sweep_ran): a
	# return, a signal, the time limit or the output budget.
	rl_sweep_ran "$st"
	rl_stderr "$WORK/err" "case $CHECKED"
	case "$RL_CAUSE" in
		ok | "exit" | "timeout" | runaway | signal) ;;
		*)
			echo "argv_check.sh: case $CHECKED could not be run: the program $RL_WHY" >&2
			exit 2 ;;
	esac

	# A BYTE MATCH IS NOT A PASS IF THE PROGRAM THEN DIED.
	#
	# This compared output and nothing else, so a deliverable that printed the
	# right bytes and segfaulted on the way out was reported as agreeing with
	# the reference. Demonstrated on a real one: a copy of c-06 ex01's
	# ft_print_params that crashes only when an argv byte exceeds 0x7f dies on
	# 134 of 200 generated cases and was green in every layer that exercise
	# owns. The signal table below already existed for the mismatch path; it
	# was simply never reached.
	#
	# tools/argv_table.sh states this rule for its own layer: "this is the
	# one thing this layer must not miss".
	if [ "$RL_CAUSE" = "exit" ]; then
		NONZERO=$((NONZERO + 1))
		[ -n "$NZ_FIRST" ] || NZ_FIRST="case $CHECKED exited $RL_RC"
	fi
	# --exit-only: how the run ended is the whole verdict, and the bytes are
	# exNN_argv_diff's business -- so a wrong output that returned 0 passes.
	if [ "$EXIT_ONLY" = 1 ]; then
		[ "$RL_CAUSE" != ok ] || continue
		_fault=$RL_WHY
	elif [ "$RL_CAUSE" = ok ] || [ "$RL_CAUSE" = "exit" ]; then
		if cmp -s "$WORK/want" "$WORK/got"; then
			# The right bytes: a fault only for a message the call said a
			# valid input does not get (--stderr-empty).
			rl_stderr_noisy "$WORK/err" || continue
			_fault=wrote-to-stderr
			NOISY_ONLY=$((NOISY_ONLY + 1))
		else
			_fault=$(classify "$WORK/want" "$WORK/got")
		fi
	else
		_fault=$(classify "$WORK/want" "$WORK/got")
	fi
	FAILED=$((FAILED + 1))
	echo "$LNO" >> "$WORK/failed_lines"
	echo "$_fault" >> "$WORK/faults"

	{
		printf '\n  case %d  [%s]  %s\n' "$CHECKED" "$tag" "$_fault"
		show_argv "$@"
		if [ "$EXIT_ONLY" = 0 ]; then
			printf '    expected: '; rl_vis lines < "$WORK/want"
			printf '\n    got:      '; rl_vis lines < "$WORK/got"
			printf '\n'
			case "$RL_CAUSE" in
				ok | "exit") ;;
				*) printf '    (it %s)\n' "$RL_WHY" ;;
			esac
		fi
		# What it wrote to stderr: the fault itself under --stderr-empty,
		# and otherwise often the explanation of the difference above.
		if [ -s "$WORK/err" ]; then
			if rl_stderr_noisy "$WORK/err"; then
				printf '    it wrote to standard error, where this input should get nothing:\n'
			else
				printf '    it also wrote to standard error:\n'
			fi
			rl_excerpt "$WORK/err" 3 "stderr-case-$CHECKED.txt" "      "
		fi
	} > "$WORK/block"
	rl_block "$WORK/block" >> "$WORK/report"
done < "$WORK/corpus.tsv"

# The loop must have SEEN the corpus. A program that eats stdin, a corpus whose
# last line has no newline, a `while read` that died on the first case: all of
# them end here with fewer cases run than the file holds, and all of them used
# to be reported as a pass.
if [ -z "$RL_STOP" ] && [ "$SEEN" -ne "$CASES" ]; then
	echo "argv_check: read $SEEN of $CASES cases. Refusing to report on a partial replay." >&2
	exit 2
fi

if [ -n "$RL_MEM" ]; then
	cat "$WORK/report"
	rl_tally
	if [ -n "$RL_STOP" ]; then
		echo ""
		rl_mem_count "$CASES"
		rl_mem_stopped "$CHECKED"
		exit 1
	fi
	rl_mem_tally "$CHECKED" "$CASES"
	_mt=$?
	# What the sanitizer could see of the arguments themselves, pass or fail.
	rl_mem_argv_note "$GUARDED" "A replay on the guarded build (--guarded-argv) puts each one in
  a heap block of its own, where it does."
	exit "$_mt"
fi

# The note on plain non-zero returns, pass or fail: it is not this layer's
# verdict, and a student should still hear about it before the robust target
# tells them. It names the target that replays THESE cases, not the table's.
exit_note() {
	[ "$EXIT_ONLY" = 0 ] || return 0
	[ "$NONZERO" -gt 0 ] || return 0
	echo ""
	echo "  note: $NONZERO of $CHECKED cases returned a non-zero exit status ($NZ_FIRST)."
	echo "        The subject names no exit status, so this layer does not fail on"
	echo "        it. Its robust twin, the _argv_diff_exit target, replays these same"
	echo "        cases and does, because a program that did its job conventionally"
	echo "        returns 0 from main."
}

if [ "$FAILED" -eq 0 ] && [ -z "$RL_STOP" ]; then
	if [ "$EXIT_ONLY" = 1 ]; then
		echo "argv_check: PASS — $CHECKED cases, every one returned 0."
	else
		echo "argv_check: PASS — $CHECKED cases, every one byte-identical to the reference."
	fi
	rl_stderr_rule
	exit_note
	rl_stderr_note
	exit 0
fi

# FAMILY LINES: a property every failing case has while some cases lack it --
# and those, by definition, all passed. Computed from the corpus as generated
# -- its fields are escaped, so a byte's class is read off the escape rather
# than guessed from a rendering -- and printed only when it holds, as a place
# to look. Not for a single failure: one case "shares" every property it has,
# so the lines would describe that case rather than point anywhere.
families() {
	awk -F'\t' -v failed="$WORK/failed_lines" '
		BEGIN { while ((getline l < failed) > 0) bad[l] = 1 }
		# Sets hi and ctl for one escaped field: \\ is a backslash, \n and
		# \t are control bytes, \0NNN is the byte NNN in octal.
		function scan(f,   j, c, d, v, k) {
			for (j = 1; j <= length(f); j++) {
				if (substr(f, j, 1) != "\\") continue
				d = substr(f, j + 1, 1)
				if (d == "n" || d == "t") { ctl = 1; j++; continue }
				if (d != "0") { j++; continue }
				v = 0
				for (k = 2; k <= 4; k++) v = v * 8 + substr(f, j + k, 1)
				if (v >= 128) hi = 1
				else if (v < 32 || v == 127) ctl = 1
				j += 4
			}
		}
		$0 == "" { next }
		{
			n = $2 + 0; hi = 0; ctl = 0; emp = 0
			for (i = 3; i < 3 + n; i++) { if ($i == "") emp = 1; scan($i) }
			p["hi"] = hi; p["ctl"] = ctl; p["emp"] = emp; p["none"] = (n == 0)
			for (k in p) { tot[k] += p[k]; if (NR in bad) fl[k] += p[k] }
			all++
			if (NR in bad) nbad++
		}
		END {
			d["hi"] = "has an argument holding a byte above 0x7f"
			d["ctl"] = "has an argument holding a newline, a tab or another control byte"
			d["emp"] = "has an empty argument"
			d["none"] = "has no arguments at all"
			split("hi ctl emp none", order, " ")
			for (i = 1; i <= 4; i++) {
				k = order[i]
				if (nbad > 1 && fl[k] == nbad && tot[k] < all)
					printf "    * every failing case %s; the %d cases without that all passed\n", d[k], all - tot[k]
			}
		}' "$WORK/corpus.tsv"
}

if [ -n "$RL_STOP" ]; then
	# The cases judged wrong before the sweep stopped, not counting the one
	# the time ran out in (counted in $FAILED, but cut short, not wrong): a verdict,
	# which keeps the report from reading as "ran out of time" alone. Nor any
	# that ran out of its own limit (RL_HANGS, in $FAILED too): not judged
	# (ruling R4), and rl_sweep_stopped names them apart (V84).
	_wrong=$((FAILED - RL_HANGS))
	[ "$RL_STOP" != budget ] || _wrong=$((_wrong - 1))
	rl_sweep_stopped "$CHECKED" "$CASES" "$_wrong"
	# Out of time with nothing wrong so far: said as that, not as "0 differ".
	if [ "$FAILED" -eq 0 ]; then
		echo "  None of the $CHECKED case(s) that ran differed from the reference."
		exit 1
	fi
fi
if [ "$EXIT_ONLY" = 1 ]; then
	echo "argv_check: FAIL — $FAILED of $CHECKED cases did not return 0."
elif [ "$NOISY_ONLY" -eq 0 ]; then
	echo "argv_check: FAIL — $FAILED of $CHECKED cases differ from the reference."
elif [ "$NOISY_ONLY" -eq "$FAILED" ]; then
	echo "argv_check: FAIL — $FAILED of $CHECKED cases wrote to standard error; their output was right."
else
	echo "argv_check: FAIL — $FAILED of $CHECKED cases: $((FAILED - NOISY_ONLY)) differ from the reference, and $NOISY_ONLY more had the right output and wrote to standard error."
fi
cat "$WORK/report"
rl_tally
echo ""
echo "  by kind:"
LC_ALL=C sort "$WORK/faults" | uniq -c | sort -rn | sed 's/^/    /'
_fam=$(families)
if [ -n "$_fam" ]; then
	echo ""
	echo "  what the failing cases share:"
	printf '%s\n' "$_fam"
fi
exit_note
rl_stderr_note
# The marks are named from the lines the report showed (rl_shown_legend): a
# legend written once named a tab, a newline and a backslash under arguments
# that held none of them.
if [ "$EXIT_ONLY" = 1 ]; then
	echo ""
	echo "  Each case above is one invocation, and only how it ended is judged here:"
	echo "  what it printed is the _argv_diff target's business. The subject names no"
	echo "  exit status. This is the robust check, which applies the C convention: a"
	echo "  program that did its job returns 0 from main. A signal is a crash, and fails"
	echo "  at every level."
	echo ""
	echo "  In the argv: line every byte is visible."
	rl_shown_legend '^    argv: +'
	exit 1
fi
echo ""
echo "  Each case above is one invocation. In the argv:, expected: and got: lines"
echo "  every byte is visible: \$ ends a line, and an output whose last line has no"
echo "  newline says so. One space follows each \$ and one comes before a note in"
echo "  parentheses; every other space is a byte, so \"ab \$\" is a line ending in one."
rl_shown_legend '^    (argv|expected|got): +'
exit 1
