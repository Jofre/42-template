#!/bin/sh
# file_check.sh — differential check for a program whose input is FILES.
#
# Runs the student's binary once per case against a corpus //oracle generated,
# writing each case's file contents to a scratch directory first, and reports
# the first differences.
#
# Usage:
#   file_check.sh --bin PATH --oracle PATH --fn NAME
#                 [--seed N] [--count N] [--show N]
#                 [--expect-transform] [--expect-substring TEXT]
#                 [--sanitized | --valgrind PATH --valgrind-tools FILE
#                  [--sample N] [--rule FILE] [--access-rule FILE]]
#                 [--gate-differ PATH --gate-bin PATH --gate-expected PATH
#                  [--gate-arg WORD]... [--gate-label NAME]]
#                 (--stderr-empty | --stderr-ignored REASON)
#
#   --show N      how many failing cases to print (default DIFF_MAX_ROWS, 40;
#                 0 prints all); every one is kept in test.outputs either way,
#                 with the files it read
#   --sanitized   BIN is the ASan/UBSan build: replay the corpus judging memory
#                 and how each run ended, never the output (exNN_file_diff_asan);
#                 --symbolizer PATH --symbolizer-lib FILE name each frame of a
#                 report's stack (runner_lib.sh, rl_sanitizers)
#   --valgrind PATH --valgrind-tools FILE [--sample N] [--rule FILE] [--access-rule FILE]
#                 a sample of the corpus under memcheck, leaks included
#                 (exNN_file_valgrind, where the subject allows malloc); both
#                 in tools/runner_lib.sh, "A CORPUS UNDER A MEMORY CHECKER"
#   --gate-differ PATH --gate-bin PATH --gate-expected PATH [--gate-arg WORD]...
#                 the exercise's own output test, which this replay waits for:
#                 GATE-BIN run through GATE-DIFFER (tools/diff_output.sh) with
#                 each --gate-arg one word of its run, against GATE-EXPECTED.
#                 While that test is red this says SKIP and exits 0: a corpus
#                 replayed over a program the test already fails says that red
#                 again, and docs/reference.md ("Which layers wait for which")
#                 says a diff layer never does. NO_SKIP=1 forces it open
#                 (tools/runner_lib.sh, rl_gate). --gate-label NAME is that
#                 test's name, for the SKIP line. Any --gate-* without all of
#                 the first three is refused (rl_gate_whole). tools/defs.bzl's
#                 output_gate() reads all of them off the output test.
#   --stderr-empty   a case also fails when the program writes anything to
#                    standard error. Every input the reference generates is
#                    valid, so a program that does what its subject says has
#                    nothing to report on any of them; but stderr is ignored
#                    unless the subject requires something of it (the Run
#                    contract, docs/reference.md), so the call site asks for
#                    this and quotes the sentence that does.
#   --stderr-ignored REASON
#                    stderr is kept only to be shown beside a case that
#                    failed, and the PASS line says why it was not judged.
#
# ONE OF THE TWO IS REQUIRED (exit 2 without it, or with both), but under
# --sanitized or --valgrind, where neither is given: there standard error
# carries the checker's report and no output is judged. A default is not a
# decision: stderr used to be ignored unless a call site remembered a flag, so
# the next corpus would have ignored it by omission rather than by the
# subject's say-so. tools/defs.bzl refuses such a call while loading
# (_RUNNER_CHOICES); this refusal is for a call made by hand.
#
# Env: FILE_TIMEOUT  seconds one case may run (default 10), capped by what is
#                    left of the test's own limit (tools/runner_lib.sh). After
#                    three cases that run out of their own time the sweep stops
#                    and says how many it did not try.
#      DIFF_MAX_ROWS the default of --show (tools/runner_lib.sh, rl_rows)
#
# WHY THIS EXISTS BESIDE argv_check.sh AND bsq_check.sh. argv_check's case is a
# list of ARGUMENTS; bsq_check's is one map file and a square. c-10's four
# programs need both halves -- flags AND file contents -- and none of the three
# corpora can express another's cases.
#
# ONE EXEC PER CASE, for the reason those two give: a program that takes its
# input as a path cannot be streamed.
#
# THE CORPUS LINE, peeled rather than read into fields:
#
#     <tag>\t<nflags>\t<flag>...\t<nfiles>\t<file>...\t<escaped-expected>
#
# `IFS=$TAB read` cannot parse it: tab is IFS whitespace, so a run of tabs is
# one separator and an EMPTY field vanishes -- and an empty file is the first
# case in this corpus. Both counts are in the line so the peel is exact.
#
# Every field is POSIX-escaped (`\n`, `\t`, `\\`, `\0NNN` octal). dash's
# `printf %b` decodes `\0NNN` and prints `\xHH` back literally, which is why the
# reference emits octal.
#
# THE EXPECTED BYTES NEVER CONTAIN A PATH. Anything that would print the name of
# the file it was given -- ft_tail with two or more files, every error message --
# is excluded from the corpus by the reference, because the path is chosen here
# at run time and a corpus that hardcoded one would be testing this script.
# So every case is a valid input, and its expected standard error is empty:
# --stderr-empty holds a program to that, where the subject says so.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "file_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat cmp grep mktemp rm sed sort uniq wc

# The shared runner helpers: the time budget, signal traps, how a run ended,
# byte rendering and excerpts (tools/runner_lib.sh, which says why each is
# written once).
RL_NAME=file_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "file_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool ORACLE -- the Rust reference (//oracle), which writes the corpus

BIN=""
ORACLE=""
FN=""
SEED=1
COUNT=120
SHOW=""
# Each case's own cap. A c-10 program reads a few files in milliseconds, so this
# only ever stops one that does not stop; the test's time limit caps it too.
CASE_TMO="${FILE_TIMEOUT:-10}"
EXPECT_TRANSFORM=0
EXPECT_SUBSTRING=""
STDERR_EMPTY=0
STDERR_WHY=""
GATE_DIFFER=""; GATE_BIN=""; GATE_EXPECTED=""; GATE_ARGS=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "file_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--seed) need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--show) need "$1" "$#"; SHOW="$2"; shift 2 ;;
		--expect-transform) EXPECT_TRANSFORM=1; shift ;;
		--expect-substring) need "$1" "$#"; EXPECT_SUBSTRING="$2"; shift 2 ;;
		--stderr-empty) STDERR_EMPTY=1; shift ;;
		--stderr-ignored) need "$1" "$#"; STDERR_WHY="$2"; shift 2 ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-arg) need "$1" "$#"; rl_list_add GATE_ARGS "$2"; shift 2 ;;
		--gate-label) need "$1" "$#"; RL_GATE_NAME="$2"; shift 2 ;;
		--sanitized | --valgrind | --valgrind-tools | --sample | --rule | --access-rule | --symbolizer | --symbolizer-lib)
			rl_mem_opt "$@"; shift "$RL_MEM_SHIFT" ;;
		*) echo "file_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
# A gate given in part is a wiring mistake (runner_lib.sh, rl_gate_whole).
rl_gate_whole file_check "$GATE_DIFFER" "$GATE_BIN" "$GATE_EXPECTED" "$GATE_ARGS$RL_GATE_NAME"

[ -n "$BIN" ] || { echo "file_check.sh: --bin is required" >&2; exit 2; }
[ -n "$ORACLE" ] || { echo "file_check.sh: --oracle is required" >&2; exit 2; }
[ -n "$FN" ] || { echo "file_check.sh: --fn is required" >&2; exit 2; }
# Exactly one of the pair, or exit 2 (tools/runner_lib.sh, STANDARD ERROR, A
# CHOICE AT EVERY CALL).
rl_stderr_choice
[ -x "$BIN" ] || { echo "file_check.sh: not executable: $BIN" >&2; exit 2; }
[ -x "$ORACLE" ] || { echo "file_check.sh: not executable: $ORACLE" >&2; exit 2; }
rl_rows "$SHOW"
rl_mem_ready

# THE GATE (--gate-differ above): the output test run as it runs, each
# --gate-arg one word of its run. c_levels()' audit holds the two to each
# other (tools/defs.bzl, _gate_problems).
rl_split_on
# shellcheck disable=SC2086 # a list, one word per line (rl_list_add)
rl_gate file_check "$GATE_DIFFER" "$GATE_BIN" "$GATE_EXPECTED" $GATE_ARGS
rl_split_off

# A PROGRAM THAT DID NOT BUILD is a stand-in script that says why (see
# tools/standin.sh). Graded as a program, its "output" is empty and its exit
# status arbitrary, and the report would be a table of wrong answers under
# this exercise's hints, none of which is about a build. Say what the build
# said instead, whole, and fail. Checked after the gate: a red gate has
# already skipped this layer.
case "$0" in */*) _sl_dir=${0%/*} ;; *) _sl_dir=. ;; esac
for _sl in "$_sl_dir/standin.sh" \
	"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
	[ -f "$_sl" ] && break
done
[ -f "$_sl" ] || { echo "file_check.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
standin_check file_check "$BIN" "$RL_STANDIN" "the program"

WORK=$(mktemp -d) || exit 2
rl_traps 'rm -rf "$WORK"'


TAB=$(printf '\t')

# Decode one escaped field STRAIGHT INTO A FILE, never through a variable.
#
# A shell variable cannot hold a NUL byte -- dash drops it silently, bash warns
# and drops it -- so `_d=$(printf '%b.' "$1"); printf '%s' "${_d%.}" > "$2"`
# writes the file with every NUL missing. That is not a small loss here: a file
# containing a NUL is what separates a correct read loop from one that treats
# its buffer as a C string, and it is the single most valuable case in this
# corpus. The first version of this function did exactly that, and a
# deliberately broken `strlen(buf)` program PASSED 60 of 60.
#
# Redirecting printf's output needs no sentinel either: command substitution is
# what strips trailing newlines, and there is none here.
dec_to() {  # dec_to ESCAPED DEST
	printf '%b' "$1" > "$2"
}

"$ORACLE" "$FN" "$SEED" "$COUNT" > "$WORK/corpus.tsv" 2> "$WORK/oracle.err" || {
	echo "file_check: the reference failed to produce a corpus for '$FN'." >&2
	rl_excerpt "$WORK/oracle.err" 10 oracle-stderr.txt >&2
	exit 2
}

CASES=$(wc -l < "$WORK/corpus.tsv")

# ---------------------------------------------------------------------------
# FLOORS. Each names a corpus that a program doing none of what the exercise
# asks would pass, so failing one is a broken harness -- exit 2, not 1.
MIN_CASES=${MIN_FILE_CASES:-20}
if [ "$CASES" -lt "$MIN_CASES" ]; then
	echo "file_check: only $CASES cases (floor $MIN_CASES). Refusing to report OK." >&2
	exit 2
fi

# What a hand-written fixture never has. Checked ON THE CORPUS rather than
# assumed from the generator's source, because the generator is the thing this
# is meant to keep honest.
_probe=$(awk -F'\t' '
	{
		nf = $2 + 0
		fi = 3 + nf              # index of <nfiles>
		n  = $(fi) + 0
		for (i = fi + 1; i < fi + 1 + n; i++) {
			if ($i == "") empty = 1
			if ($i ~ /\\0000/) nul = 1
			if (length($i) > 4096) big = 1
		}
		if ($NF != "") nonempty = 1
		if ($NF != $(fi + 1)) transformed = 1
	}
	END { printf "%d %d %d %d %d", empty, nul, big, nonempty, transformed }
' "$WORK/corpus.tsv")
set -- $_probe
[ "$1" = 1 ] || { echo "file_check: no EMPTY file in the corpus. A read loop that never runs would pass." >&2; exit 2; }
[ "$2" = 1 ] || { echo "file_check: no file containing a NUL. A program using str* functions would pass." >&2; exit 2; }
[ "$3" = 1 ] || { echo "file_check: every file is small. A fixed-size buffer read once would pass." >&2; exit 2; }
[ "$4" = 1 ] || { echo "file_check: every expected block is empty. A program that prints nothing would pass." >&2; exit 2; }

# For the arms whose answer is not the file itself: at least one case where the
# expected bytes differ from the first file's. Without it a `ft_hexdump` corpus
# could consist entirely of empty files and be passed by `cat`.
if [ "$EXPECT_TRANSFORM" = 1 ] && [ "$5" != 1 ]; then
	echo "file_check: no case whose output differs from its input, so a program" >&2
	echo "            that copies the file would pass." >&2
	exit 2
fi

# An arm may name one thing its corpus must be able to produce -- hexdump's `*`
# squeeze line is the case in point, since it needs sixteen identical bytes
# twice over and no hand-written fixture reaches it.
if [ -n "$EXPECT_SUBSTRING" ]; then
	if ! grep -qF -- "$EXPECT_SUBSTRING" "$WORK/corpus.tsv"; then
		echo "file_check: no case whose expected output contains '$EXPECT_SUBSTRING'." >&2
		exit 2
	fi
fi

# ---------------------------------------------------------------------------
# THE REPLAY.
#
# Bounded twice, as every sweep here is: in time by rl_sweep_next (each case's
# own cap, and what is left of the test's limit), and in size by `ulimit -f`,
# set once now that the corpus is written: a program printing without end is
# stopped by SIGXFSZ instead of filling the test's scratch space. 32 MiB is far
# above any expected block (a hexdump of the corpus's largest file is a few
# hundred KiB) and far below "fills the disk".
ulimit -f 65536 2> /dev/null || true
FAILED=0
# Of FAILED, the cases whose output was right and which failed only for what
# they wrote to stderr (--stderr-empty): the headline counts them apart.
NOISY_ONLY=0
CHECKED=0
: > "$WORK/faults"
: > "$WORK/report"

classify() {  # classify EXPECTED GOT (after rl_sweep_ran)
	case "$RL_CAUSE" in
		"timeout") echo "did-not-finish"; return ;;
		"runaway") echo "runaway-output"; return ;;
		"signal" | "stopped") echo "crash"; return ;;
	esac
	# The right bytes, and a message on stderr about a valid input.
	if cmp -s "$1" "$2"; then echo "wrote-to-stderr"; return; fi
	if [ ! -s "$2" ] && [ -s "$1" ]; then echo "no-output"; return; fi
	if [ -s "$2" ] && [ ! -s "$1" ]; then echo "output-when-none-expected"; return; fi
	_we=$(wc -c < "$1"); _ge=$(wc -c < "$2")
	if [ "$_ge" -lt "$_we" ]; then echo "truncated-$((_we - _ge))-bytes"; return; fi
	if [ "$_ge" -gt "$_we" ]; then echo "extra-$((_ge - _we))-bytes"; return; fi
	echo "same-length-different-bytes"
}

# show_input ARG... -- a failing case's command line: each flag byte-exact
# (rl_vis), each file by its size, the files kept in test.outputs as
# case-N-fileK (tools/runner_lib.sh's rl_keep_input, which a memory report
# then names each kept file by), and the command that runs the case again on
# them. Run by hand outside bazel test, there is nowhere to keep one.
show_input() {
	printf '    flags:   '
	for _a in "$@"; do
		case "$_a" in
			"$WORK"/*) printf ' <file %s>' "${_a#"$WORK"/f}" ;;
			*) printf ' [%s]' "$(printf '%s' "$_a" | rl_vis arg)" ;;
		esac
	done
	printf '\n'
	_i=0
	while [ "$_i" -lt "$nfiles" ]; do
		printf '    file %d:   %s bytes\n' "$_i" "$(wc -c < "$WORK/f$_i")"
		_i=$((_i + 1))
	done
	_kept=""
	_replay=""
	for _a in "$@"; do
		case "$_a" in
			"$WORK"/*)
				_k="case-$CASENO-file${_a#"$WORK"/f}"
				if rl_keep_input "$_a" "$_k"; then
					_kept=${RL_SAVED%/*}
					_replay="$_replay $_k"
				else
					_replay="$_replay <file ${_a#"$WORK"/f}>"
				fi ;;
			*) _replay="$_replay $(printf '%s' "$_a" | rl_shword)" ;;
		esac
	done
	[ -z "$_kept" ] || printf '    kept in: %s/\n' "$_kept"
	printf '    replay:  ./a.out%s\n' "$_replay"
}

CASENO=0
while IFS= read -r line; do
	# A sweep that has stopped (rl_sweep_ran set RL_STOP) starts no more cases.
	# Checked HERE, at the top: the body below `continue`s past its end.
	[ -z "$RL_STOP" ] || break
	[ -n "$line" ] || continue
	tag=${line%%"$TAB"*}; rest=${line#*"$TAB"}
	nflags=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}

	set --
	_i=0
	while [ "$_i" -lt "$nflags" ]; do
		_f=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}
		_v=$(printf '%b.' "$_f")
		set -- "$@" "${_v%.}"
		_i=$((_i + 1))
	done

	nfiles=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}
	rm -f "$WORK"/f[0-9]*
	_i=0
	while [ "$_i" -lt "$nfiles" ]; do
		_f=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}
		dec_to "$_f" "$WORK/f$_i"
		set -- "$@" "$WORK/f$_i"
		_i=$((_i + 1))
	done
	dec_to "$rest" "$WORK/want"

	CASENO=$((CASENO + 1))
	# UNDER A MEMORY CHECKER the case runs when it is in the sample, and only
	# memory and how it ended are judged (tools/runner_lib.sh, rl_mem_run).
	if [ -n "$RL_MEM" ]; then
		rl_mem_pick "$CASENO" "$CASES" || continue
		rl_sweep_next "$CASE_TMO" || break
		CHECKED=$((CHECKED + 1))
		rl_mem_run --what "case $CASENO" -- "$@"
		[ "$RL_MEM_BAD" = 1 ] || continue
		FAILED=$((FAILED + 1))
		{
			printf '\n  case %d  [%s]  %s\n' "$CASENO" "$tag" "$RL_MEM_KIND"
			show_input "$@"
			rl_mem_report
		} > "$WORK/block"
		rl_block "$WORK/block" >> "$WORK/report"
		continue
	fi
	# `< /dev/null` on every run. Without it a program that falls back to stdin
	# -- which ft_cat does by design -- consumes the rest of the corpus, the
	# loop ends early, and the layer reports "OK" having checked one case.
	rl_sweep_next "$CASE_TMO" || break
	# stderr to a file: judged under --stderr-empty, and otherwise never
	# compared, but a case that wrote to it is said (rl_stderr).
	rl_run "$BIN" "$@" < /dev/null > "$WORK/got" 2> "$WORK/err"
	st=$?
	CHECKED=$((CHECKED + 1))
	rl_sweep_ran "$st"
	rl_stderr "$WORK/err" "case $CASENO"
	if [ "$RL_CAUSE" = noexec ]; then
		echo "file_check.sh: case $CHECKED could not be run: the program $RL_WHY" >&2
		exit 2
	fi

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
	# How it ended is rl_classify's, read from waitpid() by tools/exit_status:
	# a return of any number is a return, and only a signal, the time limit or
	# the output budget is not. tools/argv_table.sh states this rule for its
	# own layer: "this is the one thing this layer must not miss".
	case "$RL_CAUSE" in
		ok | "exit") ended=0 ;;
		*) ended=1 ;;
	esac
	# Standard error, where the call site asked for it to stay empty
	# (--stderr-empty): a valid input is no occasion for a message.
	noisy=0
	! rl_stderr_noisy "$WORK/err" || noisy=1
	cmp -s "$WORK/want" "$WORK/got" && [ "$ended" = 0 ] && [ "$noisy" = 0 ] && continue
	FAILED=$((FAILED + 1))
	_fault=$(classify "$WORK/want" "$WORK/got")
	[ "$_fault" != wrote-to-stderr ] || NOISY_ONLY=$((NOISY_ONLY + 1))
	echo "$_fault" >> "$WORK/faults"

	{
		printf '\n  case %d  [%s]  %s\n' "$CASENO" "$tag" "$_fault"
		show_input "$@"
		printf '    expected: %s bytes\n' "$(wc -c < "$WORK/want")"
		# A run this runner stopped (its time limit, its output budget) is
		# counted where it was stopped, and the line says so: "got: 6 bytes"
		# under "expected: 6 bytes" read as a match until the line below
		# (V144; rush02_check.sh's got line also says the stop).
		case "$RL_CAUSE" in
			runaway|timeout) _gotwhen=" when it was stopped" ;;
			*) _gotwhen="" ;;
		esac
		printf '    got:      %s bytes%s\n' "$(wc -c < "$WORK/got")" "$_gotwhen"
		if [ "$RL_CAUSE" = timeout ]; then
			# It did not finish: what it had printed by then is shown, and
			# never compared -- no first difference, and no "identical"
			# either, of bytes it might have gone on writing (V85).
			printf '    (it %s)\n' "$RL_WHY"
			if [ -s "$WORK/got" ]; then
				printf '    what it had printed when it was stopped:\n'
				rl_excerpt "$WORK/got" 3 "printed-case-$CASENO.txt" "      "
			fi
			printf '    not judged: a run that did not finish was not seen to its end\n'
		elif cmp -s "$WORK/want" "$WORK/got"; then
			printf '    the output is byte-identical to the reference\n'
		else
			# The first differing BYTE rather than a text diff: these outputs
			# are binary in general, and "line 4 differs" says nothing about
			# a file that has no lines. Shown from just before it, in the
			# one byte rendering every runner uses (runner_lib.sh).
			rl_diff_window "$WORK/want" "$WORK/got" "    "
		fi
		[ "$ended" = 0 ] || [ "$RL_CAUSE" = timeout ] || printf '    (it %s)\n' "$RL_WHY"
		# What it wrote to stderr: the fault itself under --stderr-empty,
		# and otherwise often the explanation of the difference above.
		if [ -s "$WORK/err" ]; then
			if [ "$noisy" = 1 ]; then
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
# last line has no newline, a `while read` that died on the first case: every
# one of them ends here with fewer cases run than the file holds, and every one
# used to be reported as a pass.
if [ -z "$RL_STOP" ] && [ "$CASENO" -ne "$CASES" ]; then
	echo "file_check: read $CASENO of $CASES cases. Refusing to report on a partial replay." >&2
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
	# The file names and options are arguments: what the sanitizer saw of them.
	rl_mem_argv_note 0
	exit "$_mt"
fi

if [ "$FAILED" -eq 0 ] && [ -z "$RL_STOP" ]; then
	if [ "$STDERR_EMPTY" = 1 ]; then
		echo "file_check: PASS — $CHECKED cases, every one byte-identical to the reference, with nothing on standard error."
	else
		echo "file_check: PASS — $CHECKED cases, every one byte-identical to the reference."
		echo "  Standard error was not judged: $STDERR_WHY"
	fi
	rl_stderr_note
	exit 0
fi

if [ -n "$RL_STOP" ]; then
	# The cases judged wrong before the sweep stopped, not counting the one
	# the time ran out in (counted in $FAILED, but cut short, not wrong): a verdict,
	# which keeps the report from reading as "ran out of time" alone. Nor any
	# that ran out of its own limit (both in RL_DNF, and in $FAILED too): not
	# judged (ruling R4), and rl_sweep_stopped names them apart (V84).
	rl_sweep_stopped "$CHECKED" "$CASES" "$((FAILED - RL_DNF))"
	# Out of time with nothing wrong so far: said as that, not as "0 differ".
	if [ "$FAILED" -eq 0 ]; then
		echo "  None of the $CHECKED case(s) that ran differed from the reference."
		exit 1
	fi
fi
# A run that did not finish (RL_DNF, in $FAILED too) is said apart, and
# never as a case that differs: it was not seen to its end (V85).
WRONG=$((FAILED - RL_DNF))
_differ=$((WRONG - NOISY_ONLY))
rl_dnf_said "$CASE_TMO"
_and=${RL_DNF_SAID:+, and $RL_DNF_SAID}
if [ "$WRONG" -eq 0 ]; then
	echo "file_check: FAIL — $((CHECKED - FAILED)) of $CHECKED cases agree with the reference$_and."
elif [ "$NOISY_ONLY" -eq 0 ]; then
	echo "file_check: FAIL — $WRONG of $CHECKED cases differ from the reference$_and."
elif [ "$_differ" -eq 0 ] && [ "$RL_DNF" -eq 0 ]; then
	echo "file_check: FAIL — $FAILED of $CHECKED cases wrote to standard error; their output was right."
elif [ "$_differ" -eq 0 ]; then
	echo "file_check: FAIL — $FAILED of $CHECKED cases: $NOISY_ONLY had the right output and wrote to standard error$_and."
elif [ "$RL_DNF" -eq 0 ]; then
	echo "file_check: FAIL — $FAILED of $CHECKED cases: $_differ differ from the reference, and $NOISY_ONLY more had the right output and wrote to standard error."
else
	echo "file_check: FAIL — $FAILED of $CHECKED cases: $_differ differ from the reference, $NOISY_ONLY more had the right output and wrote to standard error$_and."
fi
rl_dnf_note "$WRONG"
cat "$WORK/report"
rl_tally
echo ""
echo "  by kind:"
LC_ALL=C sort "$WORK/faults" | uniq -c | sort -rn | sed 's/^/    /'
rl_stderr_note
# A hint about the bytes, so only under a report with a case whose bytes
# differ: never where the only red is a run that did not finish, whose bytes
# were never compared (V85), or a case with the right bytes that wrote to
# standard error (--stderr-empty), which has no truncation to explain.
if [ "$_differ" -gt 0 ]; then
	echo ""
	echo "  A truncation of exactly one buffer's worth is a read loop that runs"
	echo "  once; a truncation at the first NUL is a buffer treated as a string."
fi
if grep -q '^wrote-to-stderr$' "$WORK/faults"; then
	[ "$_differ" -gt 0 ] || echo ""
	echo "  Every file in this corpus exists and can be read: what would a"
	echo "  message about one of them be reporting?"
fi
exit 1
