# shellcheck shell=sh
# (sourced library, never executed, so it has no shebang -- this directive
#  tells shellcheck the dialect without implying the file is a program.)
#
# runner_lib.sh — what every runner that runs student code or prints hints has
# to get right, written once.
#
# WHY IT EXISTS. Each runner used to carry its own copy of these concerns, and
# the copies drifted: rust_diff.sh ran a student's harness with no time limit at
# all, so a slow answer died as a bare Bazel TIMEOUT with an empty log (finding
# 066); the rush-01 sweep excused every slow bonus case until Bazel killed it
# with nothing printed (148); about thirty signal traps deleted their scratch
# directory on SIGTERM and then carried on without it ("Directory
# nonexistent"); rush01_check.sh printed clues.tsv's maintainer comments as
# hints (149); diff_output.sh cut a program's stderr to ten lines and never said
# so (165). Each was the same mistake made in one more file. The helpers below
# are the one copy, and tools/conventions.sh refuses the hand-rolled forms, so
# the next runner cannot grow its own.
#
# HOW A RUNNER USES IT. After its own `require` line, a runner sets RL_NAME and
# sources this file:
#
#     RL_NAME=rust_diff
#     case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
#     [ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
#     [ -f "$RL_LIB" ] || { echo "rust_diff.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
#     # shellcheck source=tools/runner_lib.sh
#     . "$RL_LIB"
#
# Two places, because a runner is reached two ways: beside it in tools/ (run by
# hand, by the selftest, or as a gate by another runner), and from a Bazel test,
# whose $0 is the TARGET's name in its own package -- so there the file is found
# through the runfiles tree, and only if the target lists //tools:runner_lib.sh
# in its data (defs.bzl's _test() adds it to every test it emits; a sh_test
# written by hand lists it itself). A runner that runs student code (rl_tmo,
# rl_run) needs //tools:exit_status beside it the same way: defs.bzl's
# _EXIT_STATUS_RUNNERS, and //tools:conventions checks both.
#
# THE HELPERS, each described where it is defined:
#
#   the time budget    RL_DEADLINE, rl_tmo, rl_run, rl_overrun, rl_hang,
#                      rl_sweep_next / rl_sweep_ran / rl_sweep_stopped
#   signal handling    rl_traps
#   how a run ended    rl_classify (from tools/exit_status), rl_signame
#   lists of words     RL_NL, rl_list_add, rl_split_on / rl_split_off
#   byte rendering     RL_AWK_VIS (rl_vis_exact, rl_vis_text, rl_vis_noted),
#                      rl_vis, rl_vis_legend, rl_shword, rl_first_diff,
#                      rl_caret, rl_diff_window, rl_udiff
#   the invocation     rl_cmdline, rl_argv_words, rl_rundir, rl_ran
#   long output        rl_excerpt, rl_save
#   a report's length  rl_rows, rl_block, rl_tally (DIFF_MAX_ROWS),
#                      rl_shown_legend
#   the other stream   rl_stderr, rl_stderr_note
#   a corpus under a memory checker
#                      rl_mem_opt, rl_mem_ready, rl_mem_pick, rl_mem_run,
#                      rl_mem_report, rl_mem_tally, rl_mem_argv_note
#   sanitizer runs     rl_sanitizers (options, the pinned symbolizer),
#                      rl_sanitized, rl_sanitizer_report
#   hints              rl_clues (clues.tsv), rl_legend (diff_clues.txt)
#   who waits for it   rl_waiting, on a red exit of an output test
#   why it is raised   rl__raised, on a red exit of a test _RAISED lists
#   a grader's header  rl_grader_hdrs, after a compile that failed
#   a fetched compiler rl_cc_pin, proved pinned before the first compile
#   a fetched linker   rl_ld_pin, proved pinned before the first link;
#                      rl_cc_wrap, the two as one command
#   a corpus's stderr  rl_stderr_choice, rl_stderr_noisy, rl_stderr_rule
#   who grades         rl_at (RL_GRADER, from the subject contract)
#
# Everything here is POSIX sh and reads its inputs under `set -u`, so every
# optional variable is written ${VAR:-}.
#
# What this file takes from PATH is probed here, not in each caller's require
# list: tools/conventions.sh computes a runner's list from the runner's own
# text, and checks this list against this file's text the same way.
for _rl_t in awk cat chmod cp date dirname grep mkdir mktemp od readlink rm; do
	command -v "$_rl_t" > /dev/null 2>&1 && continue
	echo "runner_lib.sh: required command '$_rl_t' is not on PATH" >&2
	exit 2
done
RL_NAME=${RL_NAME:-${0##*/}}

# ---------------------------------------------------------------------------
# LISTS OF WORDS.
#
# A runner gathers words from its command line -- every --src, every -I, the
# options it forwards to diff_output.sh -- and hands them on to a compiler or
# another runner. They were joined with a blank and expanded bare, so a path
# holding a blank arrived as two words, and one holding a * was matched
# against the working directory on its way through: a correct header "not
# found", a clues path a usage error (header_check.sh, ilp32_test.sh). A list
# is one word per line instead, built with rl_list_add and expanded between
# rl_split_on and rl_split_off, which split an unquoted expansion at newlines
# only and turn globbing off:
#
#     rl_list_add SRCS "$2"
#     rl_list_add INCS "-I$(dirname "$2")"
#     ...
#     rl_split_on
#     # shellcheck disable=SC2086
#     "$CC" -Wall $INCS $SRCS -o "$out"
#     _rc=$?
#     rl_split_off
#
# Between the two, EVERY unquoted expansion splits at newlines alone, so a
# variable of constant flags meant to split at blanks is a list too, and a
# loop that reads a line with `read` sets IFS for itself. A word never holds a
# newline, and is never empty. //tools:conventions refuses a list built by
# joining a word from the command line with a blank (VAR="$VAR $2").
RL_NL='
'
rl_list_add() {  # rl_list_add VAR WORD... -- append each WORD to the list in VAR
	_rl_lv=$1
	shift
	for _rl_lw in "$@"; do
		eval "_rl_lc=\${$_rl_lv}"
		if [ -z "$_rl_lc" ]; then
			eval "$_rl_lv=\$_rl_lw"
		else
			eval "$_rl_lv=\$_rl_lc\$RL_NL\$_rl_lw"
		fi
	done
}
rl_split_on() { _rl_split_ifs=$IFS; IFS=$RL_NL; set -f; }
rl_split_off() { IFS=$_rl_split_ifs; set +f; }

# ---------------------------------------------------------------------------
# THE TIME BUDGET.
#
# Bazel gives every test TEST_TIMEOUT seconds and then kills it. A runner that
# is still running student code at that moment prints nothing: the log holds
# Bazel's "-- Test timed out --" and the student learns neither which input nor
# why. So each runner stops itself FIRST, a margin before Bazel would, and says
# which case it was on.
#
# RL_DEADLINE is the moment (seconds since the epoch) this test must be done
# by: TEST_TIMEOUT from when the first runner of the test started, less the
# margin. It is EXPORTED, so a runner that calls another -- a gate running
# diff_output.sh -- shares one deadline instead of each granting itself the
# whole limit again.
#
# The margin is what the runner needs after the last run to print its verdict,
# plus what Bazel's clock had already counted before this runner started (its
# test wrapper, the shell): a tenth of the limit, at least 4s and at most 20s
# (6s of a small test's 60, 20s of a medium's 300). A twentieth, 3s of a
# small test's, was measured too thin: on a machine running three suites at
# once (load 70 on 24 cores) rust_diff stopped a slow correct answer at its
# deadline, printed its whole report, and Bazel's SIGTERM still arrived
# before it could exit -- a TIMEOUT again, with the report above it.
# RL_MARGIN overrides it (the selftest sets it to 1 to keep its arms short).
# Without TEST_TIMEOUT -- a runner run by hand -- there is no deadline, and
# only each runner's own per-run cap applies.
#
# THE CLOCK IS READ WITHOUT A FORK. rl_tmo reads it before every run, and a
# sweep makes hundreds of runs: `$(date +%s)` there is two processes a case,
# which on a loaded machine cost the selftest over a minute. /proc/uptime is
# read with the shell's own `read`; `date` is the fallback where there is no
# /proc. RL_CLOCK names which clock RL_DEADLINE was taken on, and travels with
# it, so a runner a gate starts compares the deadline against the same clock.
#
# Whole seconds, each rounded the SAFE way: the deadline from the start rounded
# down, and each run's limit from the moment rounded UP (RL_NOW_UP), so a run
# never ends past the deadline. Rounded down both ways, a run could end up to
# a second past it, taken out of the margin the report is written in.
rl__now() {  # sets RL_NOW and RL_NOW_UP, seconds on the clock RL_CLOCK names
	if [ "${RL_CLOCK:-uptime}" = uptime ] &&
		read -r _rl_up _rl_idle < /proc/uptime 2> /dev/null; then
		RL_CLOCK=uptime
		RL_NOW=${_rl_up%%.*}
		case "$_rl_up" in
			*.*[1-9]*) RL_NOW_UP=$((RL_NOW + 1)) ;;
			*) RL_NOW_UP=$RL_NOW ;;
		esac
	else
		RL_CLOCK="date"
		RL_NOW=$(date +%s)
		# A whole second is all `date +%s` says: the next one is the safe side.
		RL_NOW_UP=$((RL_NOW + 1))
	fi
}

if [ -z "${RL_DEADLINE:-}" ]; then
	case "${TEST_TIMEOUT:-}" in
		'' | *[!0-9]*) ;;
		*)
			case "${RL_MARGIN:-}" in
				'' | *[!0-9]*)
					_rl_margin=$((TEST_TIMEOUT / 10))
					[ "$_rl_margin" -ge 4 ] || _rl_margin=4
					[ "$_rl_margin" -le 20 ] || _rl_margin=20
					;;
				*) _rl_margin=$RL_MARGIN ;;
			esac
			RL_BUDGET=$((TEST_TIMEOUT - _rl_margin))
			[ "$RL_BUDGET" -ge 1 ] || RL_BUDGET=1
			rl__now
			RL_DEADLINE=$((RL_NOW + RL_BUDGET))
			export RL_DEADLINE RL_BUDGET RL_CLOCK
			;;
	esac
fi
RL_BUDGET=${RL_BUDGET:-}

RL_TMO=""
RL_CLAMPED=0
RL_CEIL=""
RL_QUEUED=0

# rl_tmo [CAP] -- set up the NEXT run of student code, which rl_run then makes.
#
#   RL_TMO      the seconds this run may take: CAP, or what is left of the
#               budget if that is less. Empty when there is neither.
#   RL_CLAMPED  1 when the budget, not CAP, set RL_TMO: a run killed then was
#               stopped by the test's own time limit, and says so.
#
#   RL_CEIL     the most wall time the run may take: what is left of the
#               budget, or ten times CAP where there is none. CAP bounds the
#               run's OWN time -- wall time less what it waited on the run
#               queue for a CPU -- and the queue's share is given back up to
#               RL_CEIL (tools/exit_status, tools/runqueue.h): a per-run cap
#               was a wall clock, and on a machine running two suites at once
#               a correct program spent it waiting for a CPU (finding 066).
#
# Returns 1, with RL_TMO 0, when less than a second is left: a runner must not
# START another run then, and reports rl_overrun instead.
#
# The limit is enforced by tools/exit_status itself (--timeout), which kills
# the program's whole process group with SIGKILL -- a program stuck in a loop
# may have a handler, or be blocked, and KILL cannot be caught -- and then
# RETURNS, with a report saying so. It used to be `timeout -s KILL N` in front
# of the helper, which killed the helper too: no report, and a shell line,
# "Killed", written into the student's own stderr file.
#
# It also finds tools/exit_status (below) the first time, in the runner's own
# shell: rl_run is often called in a subshell, `( ulimit -f N; rl_run ... )`,
# where a variable it set, or an exit it made, would not reach the runner.
rl_tmo() {
	rl__waiter
	RL_TMO=${1:-}
	RL_CLAMPED=0
	RL_CEIL=""
	RL_QUEUED=0
	if [ -n "${RL_DEADLINE:-}" ]; then
		rl__now
		_rl_left=$((RL_DEADLINE - RL_NOW_UP))
		if [ "$_rl_left" -lt 1 ]; then
			RL_TMO=0
			RL_CLAMPED=1
			return 1
		fi
		if [ -z "$RL_TMO" ] || [ "$_rl_left" -lt "$RL_TMO" ]; then
			RL_TMO=$_rl_left
			RL_CLAMPED=1
		fi
		RL_CEIL=$_rl_left
	elif [ -n "$RL_TMO" ]; then
		RL_CEIL=$((RL_TMO * 10))
	fi
	return 0
}

# ---------------------------------------------------------------------------
# THE HELPER THAT SAYS HOW A RUN ENDED (tools/exit_status.c).
#
# The shell reports a program killed by signal N as the status 128+N, which is
# also a status a program can RETURN: `return (-1);` from main is 255, the
# number a death by "signal 127" would give. Reading every status above 128 as
# a crash told a student whose program returned -1 on an error input that it
# had died, and failed it where the Run contract judges no status at all.
# Once the process is gone the shell has nothing else to go on; waitpid() does.
# tools/exit_status runs the program, waits for it, and writes one line --
# "exit N", "signal N", "noexec WHY", "timeout S" or "stopped N" -- to
# RL_HOWF, which rl_classify reads. No line at all means the helper itself was
# killed from outside.
#
# Found beside the runner when another runner or the selftest calls it by path,
# in the test's runfiles when it IS the test (its $0 is then the target's name,
# in the module's folder), and in bazel-bin when it is run by hand from tools/.
# defs.bzl's _test() stages it for every test that names a runner calling
# rl_run. Without it the ending would be guessed from the status again, so its
# absence is a wiring error, never a fallback. Absolute, because some runners
# run the program from a scratch directory.
RL_WAITER=""
RL_HOWF=""
rl__waiter() {
	[ -z "$RL_WAITER" ] || return 0
	case "$0" in */*) _rl_here=${0%/*} ;; *) _rl_here=. ;; esac
	for _rl_w in "$_rl_here/exit_status" \
		"${TEST_SRCDIR:+$TEST_SRCDIR/${TEST_WORKSPACE:-_main}/tools/exit_status}" \
		"$_rl_here/../bazel-bin/tools/exit_status"; do
		[ -n "$_rl_w" ] && [ -x "$_rl_w" ] && { RL_WAITER=$_rl_w; break; }
	done
	if [ -z "$RL_WAITER" ]; then
		echo "${RL_NAME}: tools/exit_status is not in this test's data, so how the" >&2
		echo "  program ends could not be told apart from what it returns. Add" >&2
		echo "  //tools:exit_status beside this runner (defs.bzl's _test() does it for" >&2
		echo "  every macro-made test; by hand: bazel build //tools:exit_status)." >&2
		exit 2
	fi
	case "$RL_WAITER" in /*) ;; *) RL_WAITER="$PWD/$RL_WAITER" ;; esac
	RL_HOWF=$(mktemp) || { echo "${RL_NAME}: cannot create a scratch file" >&2; exit 2; }
}

# rl_ready -- find tools/exit_status now. rl_tmo does it on its first call; a
# runner whose run function sends its own stderr to /dev/null calls this
# first, so that a missing helper is said rather than swallowed.
rl_ready() {
	rl__waiter
}

# rl_run CMD [ARG...] -- one run of student code, under the limit rl_tmo set
# and through tools/exit_status. Its status is the one the shell would have
# given; how the run ended is rl_classify's to say. Redirections go on the call:
#
#     rl_tmo "$CAP" || { rl_overrun "case 3"; exit 1; }
#     rl_run "$BIN" "$arg" < "$IN" > "$OUT" 2> "$ERR"
#     rl_classify "$?"
#
# A program that runs another (valgrind, callgrind) is the CMD, and the program
# under test its argument: the helper then reports how valgrind ended, which
# mirrors how its client did.
rl_run() {
	if [ -z "$RL_WAITER" ]; then
		echo "${RL_NAME}: rl_run before rl_tmo -- a bug in this runner" >&2
		exit 2
	fi
	if [ -n "$RL_TMO" ]; then
		"$RL_WAITER" --timeout "$RL_TMO" --ceiling "${RL_CEIL:-$RL_TMO}" "$RL_HOWF" "$@"
	else
		"$RL_WAITER" "$RL_HOWF" "$@"
	fi
}

# rl_overrun WHAT -- the one sentence for a run the time limit stopped.
#
#     did not finish within 52s: an infinite loop, or too slow on case 12 of 200
#
# WHAT names where it was: a case, an input, "the 50000-case run". The second
# line says where the number came from when it was the TEST's limit rather than
# a per-run one, because "52s" out of nowhere reads like a bug in the harness.
# Both readings are offered because the runner cannot tell them apart: a
# correct program that is too slow on the largest inputs, and one that never
# stops, look the same from outside.
#
# RL_OVERRUN_MARK is in every report of a run the TEST's limit stopped -- here,
# rl_sweep_stopped's, and the runners' own notes (diff_output, perf_test,
# shell_test) -- and in no report of a run its own cap stopped. A reader of
# test logs (tools/first_red.sh) can so tell "the test ran out of time,
# perhaps on a busy machine" from "this input never ends", as it tells a Bazel
# TIMEOUT from a FAILED.
#
# RL_WRONG is how many cases the runner had already judged wrong when the time
# ran out (rl_sweep_stopped takes it as its third argument). Those are a
# verdict whatever the machine was doing, so a report with any does NOT carry
# the mark: first_red files the test with the wrong answers it found, where it
# once filed "5 of 40 cases judged wrong" as "machine busy, run it alone". The
# words that replace the mark (rl__limit) say the same thing without it.
#
# RL_HUNG is how many runs had run out of their OWN limit by then
# (rl_sweep_stopped's fourth argument, RL_HANGS by default). Not a verdict --
# nothing judged them (the owner's ruling R4) -- and not the machine either:
# a run's own limit counts its own time, and rl_tmo gives back what it waited
# for a CPU. So a report with any names them (rl__hung_note), drops the mark,
# as first_red files a hang with the failures, and gives no "busy machine"
# advice: running the target on its own stops the same runs at the same
# limit. A stop between cases once said "Each of the first 9 of 30 cases
# ended within its own limit" under a case that had not, and blamed a busy
# machine (V84).
RL_OVERRUN_MARK="this test's own time limit"
RL_WRONG=0
RL_HUNG=0
rl__limit() {  # the test's limit, named with the mark only when no case was judged wrong or hung
	if [ "${RL_WRONG:-0}" -gt 0 ] || [ "${RL_HUNG:-0}" -gt 0 ]; then
		_rl_lim="the time limit of the test"
	else
		_rl_lim=$RL_OVERRUN_MARK
	fi
}
rl__wrong_note() {
	[ "${RL_WRONG:-0}" -gt 0 ] || return 0
	echo "  The $RL_WRONG case(s) judged wrong before that are a verdict all the same: a"
	echo "  busy machine slows a program down, it does not change its answers."
}
rl__hung_note() {  # rl__hung_note WHERE -- "among them", "before that"
	[ "${RL_HUNG:-0}" -gt 0 ] || return 0
	echo "  $RL_HUNG run(s) $1 ran out of their own time limit: an infinite loop, or a"
	echo "  program too slow for its input. That limit counts a run's own time, not its"
	echo "  wait for a CPU, so running the target on its own will not change it."
}
rl_overrun() {
	rl__limit
	if [ "${RL_TMO:-}" = 0 ]; then
		echo "${RL_NAME}: FAIL — $_rl_lim ran out before $1 could start."
		echo "  Everything before it took the whole of TEST_TIMEOUT=${TEST_TIMEOUT:-?}s."
		if [ "${RL_WRONG:-0}" -eq 0 ] && [ "${RL_HUNG:-0}" -eq 0 ]; then
			echo "  If each run above finished quickly, this machine was busy: run the target"
			echo "  again on its own."
		fi
		rl__hung_note "before it"
		rl__wrong_note
		return 0
	fi
	echo "${RL_NAME}: FAIL — did not finish within ${RL_TMO:-?}s: an infinite loop, or too slow on $1."
	if [ "${RL_QUEUED:-0}" -ge 1 ] && [ "$RL_CLAMPED" = 0 ]; then
		echo "  Those are its own seconds: it also waited ${RL_QUEUED}s for a CPU on this busy"
		echo "  machine, and that wait was given back, so the limit is not the machine's."
	fi
	if [ "$RL_CLAMPED" = 1 ] && [ -n "${TEST_TIMEOUT:-}" ]; then
		echo "  ${RL_TMO:-?}s is what was left of $_rl_lim (TEST_TIMEOUT=${TEST_TIMEOUT}s),"
		echo "  less a few seconds kept back to write this report. Without that margin Bazel"
		echo "  would have killed the test with nothing in its log."
		if [ "${RL_WRONG:-0}" -eq 0 ] && [ "${RL_HUNG:-0}" -eq 0 ]; then
			echo "  A machine busy with other work slows every run down too: if the target"
			echo "  passes when you run it on its own, that was all it was."
		fi
	fi
	rl__hung_note "before it"
	rl__wrong_note
}

# rl_hang -- count one run that ran out of its own cap; true once RL_MAX_HANGS
# (default 3) have. A sweep runs hundreds of cases, each with its own cap, and a
# program that never terminates would spend cases x cap seconds rediscovering
# it. Three is enough to say so.
RL_HANGS=0
rl_hang() {
	RL_HANGS=$((RL_HANGS + 1))
	[ "$RL_HANGS" -ge "${RL_MAX_HANGS:-3}" ]
}

# A SWEEP -- one run per case, hundreds of cases -- in three calls:
#
#     while <next case>; do
#             rl_sweep_next "$CAP" || break        # time left to start it?
#             DONE=$((DONE + 1))                   # started: counted
#             rl_run "$BIN" ... ; st=$?
#             rl_sweep_ran "$st"                   # sets RL_CAUSE, RL_WHY
#             ... judge the case ...
#             [ -z "$RL_STOP" ] || break
#     done
#     [ -z "$RL_STOP" ] || rl_sweep_stopped "$DONE" "$TOTAL" "$WRONG"
#
# RL_STOP says why the sweep ended early: "hangs" (RL_MAX_HANGS runs hit their
# own cap), "budget" (the test's time limit ran out during a case) or "start"
# (it ran out before the next case could begin). A sweep that stopped early has
# not seen every case, so it must not report a pass -- and it is not a harness
# fault either, which is what "ran 12 of 200 cases" used to be taken for.
#
# DONE counts the cases STARTED, the one the time ran out in included: "budget"
# names case DONE as the one running, and all three say TOTAL - DONE were not
# tried. WRONG, how many of them were judged wrong, is RL_WRONG (rl_overrun);
# HUNG, how many ran out of their own limit before the test's did, is RL_HUNG,
# RL_HANGS where the runner leaves it out (a runner that counts its own, as
# rush01_check.sh's sweep does, passes it).
RL_STOP=""
rl_sweep_next() {  # rl_sweep_next CAP
	rl_tmo "$1" && return 0
	RL_STOP=start
	return 1
}
rl_sweep_ran() {  # rl_sweep_ran STATUS
	rl_classify "$1"
	[ "$RL_CAUSE" = timeout ] || return 0
	if [ "$RL_CLAMPED" = 1 ]; then
		RL_STOP=budget
	elif rl_hang; then
		RL_STOP=hangs
	fi
	return 0
}
rl_sweep_stopped() {  # rl_sweep_stopped DONE TOTAL [WRONG [HUNG]]
	RL_WRONG=${3:-0}
	RL_HUNG=${4:-$RL_HANGS}
	rl__limit
	case "$RL_STOP" in
		hangs)
			echo "${RL_NAME}: STOPPED after $RL_HANGS runs that did not finish within their"
			echo "  ${RL_TMO}s each: an infinite loop, or a program too slow for these inputs."
			echo "  The remaining $(($2 - $1)) of $2 case(s) were not tried: they would only spend"
			echo "  this test's time limit saying the same thing again."
			;;
		budget)
			rl_overrun "case $1 of $2, the one running when the time ran out"
			echo "  The remaining $(($2 - $1)) case(s) were not tried."
			;;
		start)
			# The sweep as a whole outgrew the test's limit. Where every run
			# so far ended inside its own, slow on every case or a busy
			# machine; where some ran out of theirs, those (RL_HUNG, above).
			if [ "$RL_HUNG" -gt 0 ]; then
				echo "${RL_NAME}: FAIL — the sweep did not finish within ${RL_BUDGET:-?}s. The first"
				echo "  $1 of $2 cases took all of $_rl_lim (TEST_TIMEOUT=${TEST_TIMEOUT:-?}s,"
				echo "  less a few seconds to write this report), so the remaining $(($2 - $1))"
				echo "  case(s) were not tried."
				rl__hung_note "among them"
			else
				echo "${RL_NAME}: FAIL — the sweep did not finish within ${RL_BUDGET:-?}s. Each of the first"
				echo "  $1 of $2 cases ended within its own limit, but together they took all of"
				echo "  $_rl_lim (TEST_TIMEOUT=${TEST_TIMEOUT:-?}s, less a few seconds to write"
				echo "  this report), so the remaining $(($2 - $1)) case(s) were not tried."
				if [ "${RL_WRONG:-0}" -eq 0 ]; then
					echo "  Either the program is slow on every input, or this machine was busy with"
					echo "  other work: run the target on its own to tell which."
				fi
			fi
			rl__wrong_note
			;;
	esac
}

# ---------------------------------------------------------------------------
# SIGNAL HANDLING.
#
# rl_traps CLEANUP -- run CLEANUP on every way out, and make a signal END the
# runner.
#
# `trap 'rm -rf "$T"' EXIT INT TERM` does not do that, and about thirty
# scripts had it. In dash a trap that does not exit RESUMES the script after it
# runs, so on Bazel's SIGTERM the scratch directory was deleted and the runner
# went on without it -- printing "Directory nonexistent", then a verdict about
# files that were gone, and sometimes exiting 0. Here the signal traps exit,
# with the status a signal death reports (128+N: TERM 143, INT 130, HUP 129),
# and the EXIT trap does the cleanup on the way out, once.
#
# CLEANUP is stored, not expanded: rl_traps 'rm -rf "$T"' removes whatever $T
# holds when the runner exits. A script that does not source this file writes
# the same three lines itself:
#
#     trap 'rm -rf "$T"' EXIT
#     trap 'exit 143' TERM
#     trap 'exit 130' INT
#
# One limit no trap can lift: a shell runs a trap only once its foreground
# command returns, so a TERM that lands while student code runs waits for that
# run to end. That is why every run is bounded by rl_tmo's deadline, which ends
# it before Bazel's own limit would.
rl_traps() {
	# shellcheck disable=SC2064,SC2154 # $1 is the caller's command text,
	# stored as written: its own variables are expanded when the trap runs,
	# not here, and so is _rl_st, which the trap sets. The status is kept for
	# rl__raised, and handed back to the caller's command as $? -- rl_waiting
	# reads it there.
	trap "_rl_st=\$?
(exit \$_rl_st)
$1
rl__raised \$_rl_st
rl__cleanup" EXIT
	trap 'rl__signalled TERM 143' TERM
	trap 'rl__signalled INT 130' INT
	trap 'rl__signalled HUP 129' HUP
}
# The library's own scratch file (rl_run's report). Its EXIT trap is set when
# the library is sourced, and rl_traps keeps it after the caller's cleanup.
rl__cleanup() {
	for _rl_f in "$RL_HOWF" "${RL_LISTF:-}" "${RL_SHOWNF:-}" "${RL_SHOWNF:+$RL_SHOWNF.legend}" \
		"${RL_ERRF:-}" "${RL_MEM_OUT:-}" \
		"${RL_MEM_OUT:+$RL_MEM_OUT.shown}" "${RL_MEM_STDOUT:-}" "${RL_MEM_STATUS:-}"; do
		[ -z "$_rl_f" ] || rm -f "$_rl_f"
	done
	# rl_mem_ready's folder for the pinned symbolizer's link (--symbolizer).
	[ -z "${RL_MEM_SYMD:-}" ] || rm -rf "$RL_MEM_SYMD"
}
rl__signalled() {
	if [ "$1" = TERM ] && [ -n "${TEST_TIMEOUT:-}" ]; then
		echo "${RL_NAME}: stopped by SIGTERM -- most likely Bazel's own time limit"
		echo "  (TEST_TIMEOUT=${TEST_TIMEOUT}s) ran out before this runner's did."
	else
		echo "${RL_NAME}: stopped by SIG$1."
	fi
	exit "$2"
}

# WHY A TEST SITS ABOVE ITS LAYER.
#
# rl__raised STATUS -- under a red test (STATUS 1) that its BUILD file placed
# above the level its name gives it, why it sits there. Such a test is listed
# in tools/defs.bzl's _RAISED, and _test() hands it the level as RL_RAISED
# and stages docs/reference.md beside it, whose table "Targets raised above
# their layer" gives the reason -- held to _RAISED row for row by
# //tools:conventions. So the reason is written once, in that table, and a
# red at strict or robust says why it is not basic's, which only C 06 ex03's
# report used to, through an argv_check.sh option of its own (--note, since
# removed; c_levels()' audit refuses a --note on a raised test). Called from
# the EXIT trap, after the runner's own report.
#
# RL_RAISED is read once, here, and taken out of the environment: a runner
# that starts another one (header_check.sh's diff_output.sh, a corpus
# runner's gate) says it, and the one it starts does not say it again.
RL__RAISED=${RL_RAISED:-}
unset RL_RAISED
rl__raised() {
	[ "${1:-}" = 1 ] && [ -n "$RL__RAISED" ] || return 0
	_rl_doc="${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/docs/reference.md"
	_rl_why=""
	if [ -f "$_rl_doc" ] && [ -n "${TEST_TARGET:-}" ]; then
		_rl_why=$(awk -F'|' -v t="\`${TEST_TARGET}\`" '
			/^## / { sec = $0 }
			sec == "## Targets raised above their layer" && NF >= 5 {
				a = $2; gsub(/^ +| +$/, "", a)
				if (a != t) next
				w = $4
				for (i = 5; i < NF; i++) w = w "|" $i
				gsub(/^ +| +$/, "", w)
				print w
				exit
			}' "$_rl_doc")
	fi
	echo " --------------------------------------------------"
	echo " WHY THIS TEST IS AT ${RL__RAISED}, above its layer's own level:"
	if [ -n "$_rl_why" ]; then
		printf '%s\n' "$_rl_why" | awk '{
			n = split($0, w, " "); line = ""
			for (i = 1; i <= n; i++) {
				if (line != "" && length(line) + 1 + length(w[i]) > 72) { print "   " line; line = "" }
				line = (line == "") ? w[i] : line " " w[i]
			}
			if (line != "") print "   " line
		}'
	fi
	echo "   (docs/reference.md, \"Targets raised above their layer\")"
}

# Set once here, so a runner that sources this file ends on a signal and
# removes the library's file even before it calls rl_traps.
trap '_rl_st=$?; rl__raised "$_rl_st"; rl__cleanup' EXIT
trap 'rl__signalled TERM 143' TERM
trap 'rl__signalled INT 130' INT
trap 'rl__signalled HUP 129' HUP

# ---------------------------------------------------------------------------
# HOW A RUN ENDED.
#
# rl_signame N -- a signal's name, with what it usually means in a Piscine
# program. One table, so a student meets one vocabulary for a dead process
# whichever layer reports it.
rl_signame() {
	case "$1" in
		1) echo "SIGHUP (hangup)" ;;
		2) echo "SIGINT (interrupted)" ;;
		3) echo "SIGQUIT (quit)" ;;
		4) echo "SIGILL (illegal instruction: usually a trap the compiler planted at undefined behaviour)" ;;
		5) echo "SIGTRAP (trace trap)" ;;
		6) echo "SIGABRT (abort: assertion, stack smashing, or a glibc heap error)" ;;
		7) echo "SIGBUS (bus error: an access the memory system cannot perform)" ;;
		8) echo "SIGFPE (arithmetic error, e.g. division or modulo by zero, or INT_MIN / -1)" ;;
		9) echo "SIGKILL (killed from outside: most often the kernel's out-of-memory killer)" ;;
		11) echo "SIGSEGV (invalid memory access)" ;;
		13) echo "SIGPIPE (wrote to a closed pipe)" ;;
		14) echo "SIGALRM (alarm clock)" ;;
		15) echo "SIGTERM (asked to stop)" ;;
		24) echo "SIGXCPU (CPU time limit exceeded)" ;;
		25) echo "SIGXFSZ (file size limit exceeded: output past its budget)" ;;
		*) echo "signal $1" ;;
	esac
}

# RL_CAUSE and RL_SIG are reset when the library is sourced, as every setting
# it reads with an empty default is: rl_sanitized reads both as ${NAME:-},
# also where no run was classified yet, so a value left in the environment (a
# --test_env, a hand run) would have chosen its words for a probe that never
# died of SIGABRT (V36's rule, which met them merging w7-memory).
RL_CAUSE=""
RL_SIG=""

# rl_classify STATUS [REPORT] -- how the run rl_run just made ended. STATUS is
# its $?. REPORT, when given, is a file holding tools/exit_status's line for a
# run made one level down, inside the run rl_run made: shell_test.sh's diff
# --run runs the deliverable through shell_check.sh's ck_run, in a shell that
# rl_run bounds, and hands ck_run's $CK_HOW back here, so the deliverable's
# ending is read the one way every other is. STATUS is then that run's status.
#
#   RL_CAUSE   ok | exit | timeout | runaway | signal | noexec | stopped
#   RL_RC      the status the program returned, for ok and exit
#   RL_SIG     the signal number, for signal and runaway
#   RL_WHY     the phrase for a report: "returned 3", "was killed by SIGSEGV
#              (invalid memory access)", "did not finish within 10s"
#
# Read from tools/exit_status's report, never from STATUS alone:
#   exit N      ok (N = 0) or exit. Any N, 128 and 255 included: a return.
#   signal N    signal -- or runaway for 25, SIGXFSZ, which is the runner's
#               `ulimit -f` stopping a program that printed without end. Its
#               own cause, because "crashed" would send a student looking for
#               a bad pointer.
#   noexec WHY  it could not be started, which says nothing about the student's
#               code: the runner decides whether that is a harness error.
#               exec failing is always seen; the dynamic loader stopping the
#               program before main only when its stderr goes to a file
#               (tools/exit_status, "THE LOADER IS NOT THE PROGRAM").
#   timeout S   the limit rl_tmo set ran out, and the program's group was
#               killed.
#   stopped N   the helper received signal N -- Bazel's SIGTERM, a Ctrl-C --
#               and killed the program's group: the run was ended from outside
#               the program, and the runner's own trap follows.
#   no report   the helper itself was killed from outside: "stopped" as well.
#
# What a plain non-zero return COSTS is not decided here: that is the Run
# contract in docs/reference.md (a note at basic where the subject names no
# status, a failure at robust). This only says which it was.
# shellcheck disable=SC2034 # RL_WHY, RL_RC and RL_SIG are the caller's to read.
rl_classify() {
	RL_SIG=""
	RL_RC=""
	_rl_how=""
	_rl_n=""
	_rl_rep=${2:-$RL_HOWF}
	_rl_more=""
	_rl_q=""
	[ -n "$_rl_rep" ] && [ -s "$_rl_rep" ] && {
		read -r _rl_how _rl_n
		read -r _rl_more _rl_q || :
	} < "$_rl_rep"
	case "$_rl_how" in
		exit)
			RL_RC=$_rl_n
			if [ "$_rl_n" = 0 ]; then RL_CAUSE=ok; else RL_CAUSE="exit"; fi
			RL_WHY="returned $_rl_n"
			;;
		signal)
			RL_SIG=$_rl_n
			if [ "$_rl_n" = 25 ]; then
				RL_CAUSE=runaway
				RL_WHY="kept writing past its output budget and was stopped"
			else
				RL_CAUSE=signal
				RL_WHY="was killed by $(rl_signame "$_rl_n")"
			fi
			;;
		noexec)
			RL_CAUSE=noexec
			RL_WHY="could not be started ($_rl_n)"
			;;
		"timeout")
			RL_CAUSE="timeout"
			RL_WHY="did not finish within ${_rl_n}s"
			# A second line: how much waiting for a CPU was given back
			# ("queued Q"), or that the ceiling -- what was left of the
			# test's limit -- stopped it first ("ceiling Q").
			case "$_rl_more" in
				queued)
					RL_QUEUED=${_rl_q:-0}
					RL_WHY="did not finish within ${_rl_n}s of its own time"
					;;
				ceiling)
					RL_QUEUED=${_rl_q:-0}
					RL_TMO=$_rl_n
					RL_CLAMPED=1
					;;
			esac
			;;
		stopped)
			RL_CAUSE=stopped
			RL_WHY="was stopped from outside, by $(rl_signame "$_rl_n"), before it ended"
			;;
		*)
			RL_CAUSE=stopped
			RL_WHY="was stopped from outside before it ended (status $1)"
			;;
	esac
	# One report per run: a later rl_classify without a run in between must
	# not read this one again.
	[ -z "$RL_HOWF" ] || : > "$RL_HOWF"
}

# ---------------------------------------------------------------------------
# THE ONE BYTE RENDERER.
#
# Every table and every excerpt a runner prints shows captured bytes, and there
# were four ways of doing it: diff_output's table (a control byte as ^X, a byte
# above 0x7f as \xHH, a literal $ or backslash as it was), rl_vis (\xHH, the
# backslash doubled, a $ as \x24), rl_excerpt (\xHH for a control byte only)
# and shell_check's excerpt (a '?'). So one byte read "^A" in one layer's log
# and "\x01" in the next, a '?' in a script's stderr could have been any
# control byte, and an expected line ENDING in a literal $ rendered exactly as
# one that ended there. RL_AWK_VIS is the one copy, as awk source that an awk
# program of a runner's starts with, run under LC_ALL=C so that a character is
# a byte:
#
#     LC_ALL=C awk "$RL_AWK_VIS"'
#         { print rl_vis_exact($0) }'
#
# One escape character, the backslash, and one form for a byte, \xHH in
# lowercase hex -- no ^X, whose caret would have to be escaped in every
# compiler's caret line. Two modes, because bytes are shown for two reasons:
#
#   rl_vis_exact(S)  bytes that are COMPARED: a failing cell of a table, an
#                    argument, a case's output. Every byte outside printable
#                    ASCII is \xHH, but a tab is \t; the backslash is doubled;
#                    and a $ is \x24, so a $ in the rendering is always a line
#                    end, which the caller writes where one was.
#   rl_vis_text(S)   text that is READ: a compiler's diagnostics, a program's
#                    stderr. Only what a terminal would act on -- a control byte
#                    other than tab, and DEL -- is \xHH, and a backslash
#                    that would read as the start of one is doubled: each
#                    backslash of a run before an x, or before a byte written
#                    \xHH, so the text "\x01" is "\\x01", a backslash and
#                    the byte 0x01 are "\\\x01", and \xHH always means a
#                    byte. A carriage
#                    return that ends the line is part of a CRLF line ending
#                    (ssh-keygen writes them) and is dropped. Every other byte
#                    stays as it is: a backslash elsewhere, a $, UTF-8 text --
#                    and so the caret line a compiler prints under a quoted
#                    source line still points at the right column, which a
#                    backslash doubled before it would move.
#
#   rl_vis_noted(S)  bytes that are compared, but that a TEST PROGRAM has
#                    already written in this notation (diff_output.sh
#                    --escaped-values): a value that cannot travel raw -- a line
#                    break inside one row, a NUL -- is written \n or \xHH by the
#                    harness, and a backslash in the value is \\. Rendering such
#                    a cell with rl_vis_exact doubled every backslash a second
#                    time: Rush 00's "/\\\n" read "/\\\\\\n", a reader counted
#                    three backslashes and a letter n. So here a backslash is
#                    left as it is -- it is the notation's own -- and every other
#                    byte is rendered as rl_vis_exact renders it (a raw $ as
#                    \x24, a raw control byte as \xHH). THE NOTATION is the one
#                    rl_vis arg writes: \\ a backslash, \n a line break, \t a
#                    tab, \xHH (lowercase) any other byte outside printable
#                    ASCII; docs/testing.md names it for a harness author.
#
# rl_vis_byte(HH) renders one byte given as two lowercase hex digits (od -tx1
# writes them), as rl_vis_exact does.
#
# THE LEGEND is read off what is SHOWN, never off what was rendered: a table
# renders every failing row and then shows only some of them (its row cap), and
# a legend built while rendering named marks no shown row held. rl_vis_reset()
# forgets the marks; rl_vis_scan(T) records the escapes the rendered text T
# holds, reading each backslash with what follows it, so a doubled backslash is
# one mark and the "x24" after it is text; rl_vis_marks(M, N) then appends to
# the array M, after its element N, one phrase per mark recorded ("\t a tab",
# ...) and returns the new count. rl_vis_marks(M, N, 1) says \n is a newline,
# for a byte stream rendered on one line (rl_diff_window), where no value
# holds it.
RL_AWK_VIS='
BEGIN {
	for (_rlv_i = 0; _rlv_i < 256; _rlv_i++) {
		_rlv_h = sprintf("%02x", _rlv_i)
		_rlv_c = sprintf("%c", _rlv_i)
		_rlv_hex[_rlv_c] = _rlv_h
		_rlv_x[_rlv_h] = (_rlv_i >= 32 && _rlv_i < 127) ? _rlv_c : "\\x" _rlv_h
		if ((_rlv_i < 32 && _rlv_i != 9) || _rlv_i == 127) _rlv_ctl[_rlv_c] = "\\x" _rlv_h
	}
	_rlv_x["09"] = "\\t"
	_rlv_x["24"] = "\\x24"
	_rlv_x["5c"] = "\\\\"
}
function rl_vis_byte(h) { return _rlv_x[h] }
function rl_vis_exact(s,   i, n, c, r) {
	r = ""
	n = length(s)
	for (i = 1; i <= n; i++) {
		c = substr(s, i, 1)
		r = r rl_vis_byte((c in _rlv_hex) ? _rlv_hex[c] : "00")
	}
	return r
}
function rl_vis_noted(s,   i, n, c, r) {
	r = ""
	n = length(s)
	for (i = 1; i <= n; i++) {
		c = substr(s, i, 1)
		if (c == "\\") r = r c
		else r = r rl_vis_byte((c in _rlv_hex) ? _rlv_hex[c] : "00")
	}
	return r
}
function rl_vis_scan(t,   i, n, c) {
	n = length(t)
	for (i = 1; i < n; i++) {
		if (substr(t, i, 1) != "\\") continue
		c = substr(t, i + 1, 1)
		if (c == "\\") _rlv_used["b"] = 1
		else if (c == "t") _rlv_used["t"] = 1
		else if (c == "n") _rlv_used["n"] = 1
		else if (c == "x" && substr(t, i + 2, 2) ~ /^[0-9a-f][0-9a-f]$/) {
			if (substr(t, i + 2, 2) == "24") _rlv_used["d"] = 1
			else _rlv_used["x"] = 1
			if (substr(t, i + 2, 2) == "00") _rlv_used["z"] = 1
			i += 2
		}
		i++
	}
}
function rl_vis_text(s,   i, n, c, r, k, run) {
	sub(/\r$/, "", s)
	r = ""
	n = length(s)
	for (i = 1; i <= n; i++) {
		c = substr(s, i, 1)
		if (c in _rlv_ctl) r = r _rlv_ctl[c]
		else if (c == "\\") {
			# A run of backslashes before an x, or before a byte this writes
			# as \xHH, is doubled whole. Doubling only the last one wrote
			# "\\x41" as "\\\x41", which reads as one backslash and the byte
			# \x41; doubling none before a control byte wrote a backslash
			# and the byte 0x01 as "\\x01", which is how the text \x01 reads.
			for (k = i; k <= n && substr(s, k, 1) == "\\"; k++) ;
			run = substr(s, i, k - i)
			c = substr(s, k, 1)
			r = r ((c == "x" || (c != "" && (c in _rlv_ctl))) ? run run : run)
			i = k - 1
		}
		else r = r c
	}
	return r
}
function rl_vis_reset() { split("", _rlv_used) }
function rl_vis_marks(m, n, stream) {
	if ("n" in _rlv_used) m[++n] = stream ? "\\n a newline" : "\\n a line break inside one value"
	if ("t" in _rlv_used) m[++n] = "\\t a tab"
	if ("b" in _rlv_used) m[++n] = "\\\\ one backslash"
	if ("d" in _rlv_used) m[++n] = "\\x24 a dollar"
	if ("x" in _rlv_used) m[++n] = "\\xHH any other byte outside printable ASCII, in hex" \
		(("z" in _rlv_used) ? " (\\x00 is a NUL)" : "")
	return n
}
'

# rl_vis MODE [MAXLINES] -- stdin, every byte of it rendered by rl_vis_exact
# (above), with its newlines shown by MODE:
#
#   arg     \n, on one line (an argument, a field)
#   lines   $, then one space before the next line's first byte, all on one
#           line (a table cell)
#   block   $, then a real newline (a multi-line output)
#
# In lines and block modes an unterminated last line says "(no newline at end)",
# empty input says "(nothing)", and after MAXLINES lines (default 6 for lines,
# 40 for block) the rest is counted, not shown.
#
# Read through od, not by awk lines: od sees every byte, a NUL and the last
# newline included. The separator is written late, when the next byte arrives,
# never trimmed afterwards: trimming the last space of a rendering once removed
# a REAL one ("ab " shown as "ab").
# rl_vis_legend FILE [INDENT] [STREAM] -- one line naming the marks the text
# in FILE holds, as rl_vis and rl_vis_exact render them ("\t a tab", "\\
# one backslash", ...), or nothing when it holds none. THE LEGEND is read off
# what is shown (rl_vis_scan, below): a legend written once as fixed text
# named marks no shown line held. FILE is the rendered text, as printed.
# STREAM 1 says \n is a newline, for values whose newline is their own end
# (rl_vis_marks); without it, \n is a line break inside one value.
rl_vis_legend() {
	[ -s "${1:-}" ] || return 0
	LC_ALL=C awk -v ind="${2-  }" -v stream="${3:-0}" "$RL_AWK_VIS"'
		{ rl_vis_scan($0) }
		END {
			n = rl_vis_marks(m, 0, stream + 0)
			if (!n) exit
			s = m[1]
			for (k = 2; k <= n; k++) s = s ((k == n) ? ", and " : ", ") m[k]
			print ind "(byte for byte: " s ")"
		}' "$1"
}
rl_vis() {
	LC_ALL=C od -An -v -tx1 | rl__vis_od "$@"
}
# rl__vis_od MODE [MAXLINES] -- rl_vis's table, on bytes already written out by
# `od -An -v -tx1`: for a caller that has them that way (rl_caret).
rl__vis_od() {
	LC_ALL=C awk -v mode="$1" -v max="${2:-}" "$RL_AWK_VIS"'
		BEGIN { if (max == "") max = (mode == "block") ? 40 : 6 }
		{
			for (i = 1; i <= NF; i++) {
				last = $i
				if (stop) { more++; continue }
				if (last == "0a") {
					if (mode == "arg") { out = out "\\n"; continue }
					out = out "$"
					sep = 1
					if (++lines >= max + 0) stop = 1
					continue
				}
				if (sep) { out = out (mode == "block" ? "\n" : " "); sep = 0 }
				out = out rl_vis_byte(last)
			}
		}
		END {
			if (mode != "arg") {
				if (last == "") out = "(nothing)"
				else if (more) out = out (mode == "block" ? "\n" : " ") "... (" more " more bytes)"
				else if (last != "0a") out = out " (no newline at end)"
			}
			printf "%s", out
			if (mode == "block") printf "\n"
		}'
}

# rl_shword -- stdin as ONE shell word that gives back its exact bytes: for a
# line a student copies to run a case again. rl_vis is for reading, and its
# rendering is not that -- it doubles a backslash and writes $ as \x24 -- so a
# replay line built from it ran a different input. Printable bytes and
# newlines go in single quotes, a ' as '\''. A string holding any other byte
# is written "$(printf '...')", each such byte as \ooo (octal, which printf's
# format reads) and % as %%, so the line stays printable; newlines at its very
# end, which $( ) would drop, follow in single quotes. Empty input is ''.
rl_shword() {
	LC_ALL=C od -An -v -tx1 | LC_ALL=C awk '
		BEGIN { for (i = 0; i < 256; i++) val[sprintf("%02x", i)] = i }
		{ for (i = 1; i <= NF; i++) b[++n] = val[$i] }
		function sq(c) { return (c == 39) ? "\047\\\047\047" : sprintf("%c", c) }
		END {
			plain = 1
			for (i = 1; i <= n; i++) if ((b[i] < 32 || b[i] > 126) && b[i] != 10) plain = 0
			if (plain) {
				out = "\047"
				for (i = 1; i <= n; i++) out = out sq(b[i])
				printf "%s\047", out
				exit
			}
			t = n
			while (t > 0 && b[t] == 10) t--
			# printf --: a format starting with "-" (a negative number in a
			# corpus line) was read as an option, and the replay fed the
			# program an empty line (the mutation run of 2026-10-03). POSIX
			# has a utility with no options discard a first "--".
			out = "\"$(printf -- \047"
			for (i = 1; i <= t; i++) {
				c = b[i]
				if (c == 37) out = out "%%"
				else if (c == 92) out = out "\\\\"
				else if (c >= 32 && c <= 126) out = out sq(c)
				else out = out sprintf("\\%03o", c)
			}
			out = out "\047)\""
			if (t < n) {
				out = out "\047"
				for (i = t + 1; i <= n; i++) out = out "\n"
				out = out "\047"
			}
			printf "%s", out
		}'
}

# rl_first_diff A B -- the offset, counted from 1, of the first byte where
# files A and B differ, or of the byte just past the shorter one when it is a
# prefix of the other; 0 when they are the same. From od, like rl_vis: a NUL
# or a byte above 0x7f is a byte like any other, where a shell string drops
# the one and a UTF-8 locale mangles the other.
rl_first_diff() {
	{ LC_ALL=C od -An -v -tx1 "$1"; echo "-"; LC_ALL=C od -An -v -tx1 "$2"; } |
		LC_ALL=C awk '
			$1 == "-" { second = 1; next }
			!second { for (i = 1; i <= NF; i++) a[++na] = $i; next }
			{
				for (i = 1; i <= NF && !at; i++) {
					nb++
					if (nb > na || a[nb] != $i) at = nb
				}
			}
			END {
				if (!at && nb != na) at = (nb < na ? nb : na) + 1
				print at + 0
			}'
}

# rl_caret FILE N -- a ^ under byte N of FILE as `rl_vis arg < FILE` shows it:
# as many spaces as the rendering of the bytes before it takes, then ^. An
# escape (\x01, \n, \\) is several columns wide, so the byte count would drift
# one column per escape. The width is measured on rl_vis's own rendering of
# those bytes, so the two cannot disagree.
rl_caret() {
	LC_ALL=C od -An -v -tx1 -N $(($2 - 1)) "$1" | rl__vis_od arg | LC_ALL=C awk '
		{ n += length($0) }
		END { s = ""; while (length(s) < n) s = s " "; printf "%s^", s }'
}

# rl_diff_window WANT GOT [INDENT] -- where file GOT first parts from file
# WANT, for a reader: the byte, counted from 1 as cmp counts it, then each
# side from up to 8 bytes before it, 32 bytes at most, rendered by rl_vis arg,
# a ^ under that byte, and a legend naming the escapes the two lines hold, as
# a table's does (rl_vis_marks). Each line starts with INDENT. Prints nothing
# when the two are the same.
#
#     first difference: byte 12
#     expected, from byte 4: lo, world\n
#     got,      from byte 4: lo, World\n
#                                  ^
#     In the lines above, \n a newline.
#
# The one way a runner shows the bytes around a first difference. There were
# two, neither through the renderer, and each found the byte its own way:
# file_check.sh printed `od -c` (octal escapes, a byte above 0x7f as three
# digits) and diff_output.sh's byte-stream summary `od -tx1` (bare hex) after
# its own `cmp -l`, so one byte read differently in the two layers' logs.
# Starting a little before the byte, rather than at the file's start, is what
# shows it at all: a difference deep in a 70 KiB file is not in its first
# bytes. The bytes before it are the same on both sides, so their renderings
# are as wide, and one ^ points into both lines.
rl_diff_window() {
	_rl_at=$(rl_first_diff "$1" "$2")
	[ "$_rl_at" -gt 0 ] || return 0
	_rl_from=1
	[ "$_rl_at" -le 9 ] || _rl_from=$((_rl_at - 8))
	_rl_in=${3:-}
	printf '%sfirst difference: byte %d\n' "$_rl_in" "$_rl_at"
	_rl_lab="expected, from byte $_rl_from: "
	_rl_ww=$(rl__window "$1" "$_rl_from")
	_rl_wg=$(rl__window "$2" "$_rl_from")
	printf '%s%s%s\n' "$_rl_in" "$_rl_lab" "$_rl_ww"
	printf '%sgot,      from byte %d: %s\n' "$_rl_in" "$_rl_from" "$_rl_wg"
	# The ^: the label's width, then the rendering of the bytes before the
	# difference (WANT's; GOT's are the same bytes).
	{
		[ "$_rl_at" -le "$_rl_from" ] ||
			LC_ALL=C od -An -v -tx1 -j $((_rl_from - 1)) -N $((_rl_at - _rl_from)) "$1"
	} | rl__vis_od arg | LC_ALL=C awk -v ind="$_rl_in" -v lab="$_rl_lab" '
		{ n += length($0) }
		END { n += length(lab); s = ""; while (length(s) < n) s = s " "; printf "%s%s^\n", ind, s }'
	# The legend, read off the two lines shown: a \xHH in a log with no
	# word of what it is reads as four characters the program printed.
	printf '%s\n%s\n' "$_rl_ww" "$_rl_wg" | LC_ALL=C awk -v ind="$_rl_in" "$RL_AWK_VIS"'
		{ rl_vis_scan($0) }
		END {
			n = rl_vis_marks(m, 0, 1)
			if (!n) exit
			s = "In the lines above, " m[1]
			for (k = 2; k <= n; k++) s = s ((k == n) ? ", and " : ", ") m[k]
			# At most 76 columns after the indent, as in a table legend.
			nw = split(s ".", w, " ")
			l = ""
			for (k = 1; k <= nw; k++) {
				if (l != "" && length(l) + 1 + length(w[k]) > 76) { print ind l; l = w[k] }
				else l = (l == "") ? w[k] : l " " w[k]
			}
			print ind l
		}'
}
# rl__window FILE FROM -- 32 bytes of FILE from byte FROM (counted from 1), as
# rl_vis arg renders them, then how many bytes follow, or what it is when the
# file ends before FROM. od refuses to skip past the end of its input, saying
# so on stderr; here that is the "nothing" case, not an error.
rl__window() {
	_rl_w=$(LC_ALL=C od -An -v -tx1 -j $(($2 - 1)) -N 32 "$1" 2> /dev/null | rl__vis_od arg)
	if [ -z "$_rl_w" ]; then
		printf '(nothing: it ends before this byte)'
		return
	fi
	_rl_more=$(LC_ALL=C od -An -v -tx1 -j $(($2 + 31)) "$1" 2> /dev/null | LC_ALL=C awk '{ n += NF } END { print n + 0 }')
	if [ "$_rl_more" -gt 0 ]; then
		printf '%s ... (%d more bytes)' "$_rl_w" "$_rl_more"
	else
		printf '%s' "$_rl_w"
	fi
}

# rl_udiff DIFF WANT GOT [WANT_LABEL [GOT_LABEL [MAXLINES]]] -- the unified
# diff of file GOT against file WANT, made by DIFF (the pinned diff a runner
# is handed) and shown through the one renderer: the text of every line as
# rl_vis_exact renders it, its end marked with $, and under the diff a legend
# naming the marks it holds. Returns DIFF's status: 0 the same, 1 different,
# 2 or more trouble (DIFF's message is on stderr).
#
#     --- expected
#     +++ printed
#     @@ -1 +1 @@
#     -Q$
#     +Q\x0d$
#     In the lines above, $ is where a line ended, and \xHH any other ...
#
# A diff printed raw reached the log byte for byte: a NUL a program printed
# made test.log "data" to `file` and a "binary file" to grep, a carriage
# return or a trailing space read the same as nothing at all, and without -a
# a NUL turned the whole report into "Binary files X and Y differ", naming two
# scratch files the runner had already deleted (V51). The lines diff writes
# itself -- the two headers, a hunk's @@ line, "\ No newline at end of file"
# -- are shown as written, and the line before that last one gets no $: it
# did not end. The sides are named WANT_LABEL and GOT_LABEL (default
# "expected" and "got"), never by their scratch paths. MAXLINES (default 40)
# lines of the diff are shown, and the rest counted.
rl_udiff() {
	_rl_ud=$(mktemp) || { echo "${RL_NAME}: cannot create a scratch file" >&2; exit 2; }
	"$1" -a -u -L "${4:-expected}" -L "${5:-got}" "$2" "$3" > "$_rl_ud"
	_rl_ud_rc=$?
	LC_ALL=C od -An -v -tx1 "$_rl_ud" | LC_ALL=C awk -v max="${6:-40}" "$RL_AWK_VIS"'
		# One line of the diff, from its bytes b[1..nb]. Every byte goes
		# through the renderer but the backslash that opens the note diff
		# writes itself, "\ No newline at end of file", which the renderer
		# would double. A line of text (after the two headers, not a hunk @@
		# line, not the note) gets a $ at its end, which the note takes back.
		function line(   s, i) {
			n++
			note = (n > 2 && b[1] == "5c")
			text = (n > 2 && b[1] != "40" && !note)
			s = note ? "\\" : rl_vis_byte(b[1])
			for (i = 2; i <= nb; i++) s = s rl_vis_byte(b[i])
			if (note && end[n - 1]) end[n - 1] = 0
			out[n] = s
			end[n] = text
			if (text) body = body substr(s, 2) "\n"
			nb = 0
		}
		{ for (i = 1; i <= NF; i++) if ($i == "0a") line(); else b[++nb] = $i }
		END {
			if (nb) line()
			if (n == 0) exit
			for (i = 1; i <= n && i <= max + 0; i++) {
				print out[i] (end[i] ? "$" : "")
				if (end[i]) dollar = 1
			}
			if (n > max + 0) print "... " (n - max) " more line(s) of the diff not shown"
			rl_vis_scan(body)
			c = 0
			if (dollar) m[++c] = "$ is where a line ended"
			c = rl_vis_marks(m, c, 1)
			if (!c) exit
			s = "In the lines above, " m[1]
			for (i = 2; i <= c; i++) s = s ((i == c) ? ", and " : ", ") m[i]
			nw = split(s ".", w, " ")
			l = ""
			for (i = 1; i <= nw; i++) {
				if (l != "" && length(l) + 1 + length(w[i]) > 76) { print l; l = w[i] }
				else l = (l == "") ? w[i] : l " " w[i]
			}
			print l
		}'
	rm -f "$_rl_ud"
	return "$_rl_ud_rc"
}

# ---------------------------------------------------------------------------
# THE INVOCATION: what a program's case ran, as a line that runs it again.
#
# A program exercise's case is a test of its own, and its report was a table
# and hints with no word of what had been run -- the arguments, a fixture's
# path, the stdin, the folder (finding 120). To see the run for themselves a
# student had to find the case in the module's BUILD.bazel and rebuild the
# command by hand. So a runner handed a case (--show-run) prints it first:
#
#     RAN: bazel-bin/c-piscine/c-piscine-c-11/ex05_bin 42 '*' 21
#
# which runs it again from the repository root once `bazel test` has built
# it: a fixture is named by its path in the repository, which is what Bazel
# hands a test, and the program by where Bazel keeps it.

# rl_cmdline WORD... -- the words as one shell command line, no newline: a
# word of only [A-Za-z0-9_./:=+,%@-] as it is, any other -- an empty one, a
# space, a '*', a quote, a byte a terminal cannot show -- as rl_shword writes
# it, so that the line gives the program the same bytes. No process at all
# for a plain word: every case of every program module prints one.
rl_cmdline() {
	_rl_sep=""
	for _rl_a in "$@"; do
		case "$_rl_a" in
			'' | *[!A-Za-z0-9_./:=+,%@-]*) _rl_a=$(printf '%s' "$_rl_a" | rl_shword) ;;
		esac
		printf '%s%s' "$_rl_sep" "$_rl_a"
		_rl_sep=" "
	done
}

# rl_argv_words FILE -- the arguments FILE holds, one per line, as shell words
# for the caller to append to its own:
#
#     _w=$(rl_argv_words "$F") || { echo "cannot read $F" >&2; exit 2; }
#     eval "set -- \"\$@\" $_w"
#
# An empty line is an empty argument, and a last line with no newline after it
# is an argument too; an empty file holds none. Bazel's `args` cannot carry an
# empty argument at all -- it drops "" -- nor a space without quotes embedded
# in the string, so a case that needs one takes its arguments from a file
# (c_program's "argv_file"). Returns 1 when FILE cannot be read.
rl_argv_words() {
	[ -r "$1" ] || return 1
	_rl_sep=""
	while IFS= read -r _rl_l || [ -n "$_rl_l" ]; do
		printf '%s%s' "$_rl_sep" "$(printf '%s' "$_rl_l" | rl_shword)"
		_rl_sep=" "
	done < "$1"
}

# rl_rundir DIR NAME BIN SPECS -- make DIR, a folder to run BIN from as ./NAME,
# holding a copy of BIN as NAME and, for each line DEST=SRC of SPECS, a copy
# of SRC as DEST. The subject's transcript runs `./rush-02 42` where
# numbers.dict sits, and the case that tests that form runs there too
# (c_program's "cwd_files"). BIN is copied rather than linked: a program that
# looks for its files beside itself finds them either way, and a link would
# hand it the path of Bazel's copy instead. DEST is a path inside DIR, every
# part of it a name ("." would copy SRC in under its own name), and never NAME
# or under it: that is where the program sits. Returns 1, having said why on
# stderr, when anything fails: a folder that is not the one the case
# describes would test something else.
rl_rundir() {
	_rl_d=$1
	_rl_n=$2
	# cp gives a new file the mode of the one it copies, so the copy runs.
	{ mkdir "$_rl_d" && cp "$3" "$_rl_d/$_rl_n" && [ -x "$_rl_d/$_rl_n" ]; } || {
		echo "${RL_NAME}: cannot make a run folder holding $3 as $_rl_n" >&2
		return 1
	}
	# A here-document, not `for s in $4`: an unquoted expansion is also a glob.
	while IFS= read -r _rl_s; do
		[ -n "$_rl_s" ] || continue
		_rl_dest=${_rl_s%%=*}
		_rl_src=${_rl_s#*=}
		case "$_rl_dest" in
			'' | /* | */ | *//* | . | ./* | */. | */./* | .. | ../* | */.. | */../* | \
				"$_rl_n" | "$_rl_n"/*)
				echo "${RL_NAME}: '$_rl_dest' is not a file name inside the run folder" >&2
				return 1 ;;
			*/*) mkdir -p "$_rl_d/${_rl_dest%/*}" || return 1 ;;
		esac
		cp "$_rl_src" "$_rl_d/$_rl_dest" || {
			echo "${RL_NAME}: cannot copy $_rl_src into the run folder as $_rl_dest" >&2
			return 1
		}
	done <<RL_EOF
$4
RL_EOF
}

# rl_ran PROG STDIN SPECS ARG... -- the RAN line: PROG and the ARGs as
# rl_cmdline writes them, then `< STDIN` when STDIN is not empty. SPECS is
# rl_rundir's, lines of DEST=SRC, and not empty when the run was made from a
# run folder: the folder's files are listed under the line, each with where
# it came from, the program first (PROG is then ./NAME, and its first line
# says NAME=where Bazel keeps the program).
rl_ran() {
	_rl_p=$1
	_rl_in=$2
	_rl_specs=$3
	shift 3
	printf 'RAN: %s' "$(rl_cmdline "$_rl_p" "$@")"
	[ -z "$_rl_in" ] || printf ' < %s' "$(rl_cmdline "$_rl_in")"
	printf '\n'
	[ -n "$_rl_specs" ] || return 0
	printf '     from a folder that holds only:\n'
	printf '%s\n' "$_rl_specs" | awk -F= '
		NF { n++; d[n] = $1; s[n] = substr($0, length($1) + 2); if (length($1) > w) w = length($1) }
		END {
			for (i = 1; i <= n; i++) {
				p = d[i]
				while (length(p) < w) p = p " "
				printf "       %s  a copy of %s\n", p, s[i]
			}
		}'
}

# ---------------------------------------------------------------------------
# LONG OUTPUT.
#
# rl_excerpt FILE N NAME [PREFIX] -- the first N lines of FILE, each behind
# PREFIX (default four spaces), then -- only if something was left out --
#
#     ... K more line(s), full text in bazel-testlogs/<package>/<target>/test.outputs/NAME
#
# with the whole file saved there. A bare `| head -N` on captured output used to
# be the only form in the runners, and it never said how much it dropped: a
# build failure's explanation was cut under unrelated hints and nobody could
# tell. Each line is rendered by rl_vis_text (THE ONE BYTE RENDERER, above), so
# a stray escape sequence cannot repaint the terminal, and a line longer than
# RL_EXCERPT_WIDTH (300) bytes is cut with a marker saying so.
rl_excerpt() {
	[ -s "$1" ] || return 0
	_rl_pre=${4-    }
	_rl_w=${RL_EXCERPT_WIDTH:-300}
	LC_ALL=C awk -v n="$2" -v pre="$_rl_pre" -v w="$_rl_w" "$RL_AWK_VIS"'
		NR > n { exit }
		{
			line = $0
			sub(/\r$/, "", line)
			extra = length(line) - w
			if (extra > 0) line = substr(line, 1, w)
			out = rl_vis_text(line)
			if (extra > 0) out = out " [... line cut here, " extra " more bytes]"
			print pre out
		}' "$1"
	# What was left out: lines past N, or a shown line cut at the width.
	_rl_n=$(LC_ALL=C awk -v n="$2" -v w="$_rl_w" '
		{ sub(/\r$/, "") }
		NR <= n && length($0) > w { cut = 1 }
		END { printf "%d %d", NR, cut + 0 }' "$1")
	_rl_total=${_rl_n% *}
	_rl_cut=${_rl_n#* }
	[ "$_rl_total" -gt "$2" ] || [ "$_rl_cut" = 1 ] || return 0
	if [ "$_rl_total" -gt "$2" ]; then
		_rl_more="... $((_rl_total - $2)) more line(s)"
	else
		_rl_more="... (a line was cut)"
	fi
	if rl_save "$1" "$3"; then
		echo "${_rl_pre}${_rl_more}, full text in $RL_SAVED"
	else
		echo "${_rl_pre}${_rl_more} not shown (only a run under bazel test keeps the full text)"
	fi
}

# rl_save FILE NAME -- keep FILE as a test output; RL_SAVED says where. False
# when there is nowhere to keep it.
#
# TEST_UNDECLARED_OUTPUTS_DIR is Bazel's: whatever lands there is kept after
# the test, under bazel-testlogs/<package>/<target>/test.outputs/. Run by hand
# there is no such place, and the caller says so rather than naming a path that
# does not exist. It is also how a runner keeps a failing INPUT for a student
# to replay by hand -- a generated map, a dictionary, a corpus line.
#
# NAME is what the kept file is called, and the log names it. An empty one
# copied FILE into the folder under its scratch name and named the folder
# ("full text in .../test.outputs/"), so it is a wiring mistake (exit 2),
# refused before anything is kept, by hand too.
rl_save() {
	RL_SAVED=""
	[ -n "${2:-}" ] || {
		echo "${RL_NAME}: rl_save: no name to keep $1 under (the caller's NAME is empty)" >&2
		exit 2
	}
	[ -n "${TEST_UNDECLARED_OUTPUTS_DIR:-}" ] || return 1
	mkdir -p "$TEST_UNDECLARED_OUTPUTS_DIR" 2> /dev/null || return 1
	cp "$1" "$TEST_UNDECLARED_OUTPUTS_DIR/$2" 2> /dev/null || return 1
	_rl_t=${TEST_TARGET:-}
	case "$_rl_t" in
		//*:*)
			_rl_t=${_rl_t#//}
			RL_SAVED="bazel-testlogs/${_rl_t%%:*}/${_rl_t#*:}/test.outputs/$2"
			;;
		*) RL_SAVED="this test's test.outputs/$2" ;;
	esac
}

# rl_gate NAME DIFFER BIN EXPECTED [ARG...] -- the correctness gate in front
# of a layer that replays a corpus (docs/reference.md, "Which layers wait for
# which"). While the exercise's own output fixture is red -- BIN run with the
# ARGs through DIFFER (tools/diff_output.sh) against EXPECTED -- it says SKIP
# and EXITS 0: a corpus replayed over a program the subject's own example
# fails reports the same failure hundreds of times, far less usefully than
# the fixture's table and hints do.
#
# It fails OPEN. NO_SKIP=1, a gate not wired (an empty argument), a BIN that
# cannot run and an EXPECTED that is not there all let the layer run, and so
# does a DIFFER that could not judge (exit 2 or more: a missing tool, a
# wiring mistake), which is said: a gate that cannot answer must never be why
# a layer stayed quiet. Only "the fixture ran and is red" (exit 1) skips.
# Every corpus runner with a gate calls it (//tools:conventions refuses one
# that runs its --gate-differ itself), and so does method_check, which
# replays nothing; c_levels()' audit holds the ARGs to an output test that
# runs the program the same way (tools/defs.bzl, _gate_problems): BSQ's gate
# once ran the program with no map at all, so every BSQ corpus SKIPped on
# every correct program.
#
# Three optional settings. For a gate whose case is run in a way ARGs cannot
# say: RL_GATE_PASS, a list (LISTS OF WORDS) of the differ's own options that
# shape the run -- --stdin FILE, --stream S, --sanitize, --labeled -- passed
# before the `--`; and RL_GATE_LABEL, the gating case's name, for the SKIP
# line (asan_run.sh's survive cases, gated on their exercise's first case).
# And RL_GATE_WHY, the paragraph under the SKIP line: why THIS layer waits,
# in lines already indented. Unset, it is the corpus one below, which is
# true of a layer that replays inputs and of nothing else: the method layer
# replays nothing, and a newcomer reads this paragraph on every exercise not
# written yet, so a layer that waits for another reason says its own.
#
# All three are reset here, when the library is sourced, and a runner sets
# its own after that: bsq_check.sh and both rush runners set none, so a
# value left in the environment (a --test_env, a hand run) reached their
# gates -- an RL_GATE_LABEL there turned the corpus SKIP into a case's, and
# an RL_GATE_PASS handed the differ options the call never gave (V36).
# //tools:conventions refuses a setting this library reads with an empty
# default and never resets.
RL_GATE_WHY=""
RL_GATE_PASS=""
RL_GATE_LABEL=""
rl_gate() {
	_rl_gn=$1 _rl_gd=$2 _rl_gb=$3 _rl_ge=$4
	shift 4
	[ "${NO_SKIP:-0}" != 1 ] && [ -n "$_rl_gd" ] && [ -n "$_rl_gb" ] && [ -n "$_rl_ge" ] &&
		[ -x "$_rl_gb" ] && [ -f "$_rl_ge" ] || return 0
	# The differ's options, then --, then the ARGs: RL_GATE_PASS's words are
	# appended, and the ARGs rotated behind them. Not with rl_split_on, which
	# a caller expanding its own list of ARGs is already inside -- the two do
	# not nest, and the caller's IFS would stay split at newlines after.
	_rl_gc=$#
	while IFS= read -r _rl_gw; do
		[ -z "$_rl_gw" ] || set -- "$@" "$_rl_gw"
	done <<-RL_GATE_PASS
	${RL_GATE_PASS:-}
	RL_GATE_PASS
	set -- "$@" --
	while [ "$_rl_gc" -gt 0 ]; do
		set -- "$@" "$1"
		shift
		_rl_gc=$((_rl_gc - 1))
	done
	# conventions: harness tool -- the differ keeps this test's budget (RL_DEADLINE) and runs BIN through rl_run
	sh "$_rl_gd" --bin "$_rl_gb" --expected "$_rl_ge" "$@" > /dev/null 2>&1
	_rl_grc=$?
	if [ "$_rl_grc" -ge 2 ]; then
		echo "$_rl_gn: the output gate could not be evaluated (exit $_rl_grc),"
		echo "  so this layer is running anyway rather than going quiet."
		return 0
	fi
	[ "$_rl_grc" -eq 1 ] || return 0
	if [ -n "${RL_GATE_LABEL:-}" ]; then
		echo "$_rl_gn: SKIP — $RL_GATE_LABEL, this exercise's own case, is not passing yet."
		echo ""
		echo "  This run only asks that the program ends by itself, and a program that"
		echo "  does nothing yet does that: green here would say nothing. Get that case"
		echo "  green and this one starts checking."
	else
		echo "$_rl_gn: SKIP — this exercise's own output fixture is not passing yet."
		echo ""
		if [ -n "${RL_GATE_WHY:-}" ]; then
			printf '%s\n' "$RL_GATE_WHY"
		else
			echo "  That fixture is the subject's own example, with a table and hints"
			echo "  attached. This layer replays a generated corpus over the same program"
			echo "  and would report the same failure, far less usefully: get the"
			echo "  *_output layer green and this one starts checking the inputs you did"
			echo "  not think of."
		fi
	fi
	echo "  ($(rl_noskip_cmd) runs it anyway.)"
	exit 0
}

# rl_noskip_cmd -- the command that runs THIS test with its skip forced open
# (NO_SKIP=1), for a SKIP paragraph to print. A newcomer copies what a log
# shows, and the skips used to show `bazel test //... --test_env=NO_SKIP=1`:
# the whole repo, the heaviest command there is, on a campus box with about
# 2.5 GB free (finding 006; review of WP-83). Under Bazel it names this test
# (TEST_TARGET, //package:name); run by hand there is none to name, so it
# names a module's tests, with the module left for the reader to fill in.
# //tools:conventions refuses a runner that prints a whole-repo test.
rl_noskip_cmd() {
	case "${TEST_TARGET:-}" in
		//*:*) printf 'bazel test %s --test_env=NO_SKIP=1\n' "$TEST_TARGET" ;;
		*) printf 'bazel test //<course>/<project>/... --test_env=NO_SKIP=1\n' ;;
	esac
}

# ---------------------------------------------------------------------------
# HOW MANY FAILING CASES A REPORT SHOWS.
#
# A differential report prints one block per failing case, and against a stub
# every case fails, so each report stops somewhere. Each runner used to pick
# its own place -- 10 in rush-02's, 8 in argv_check's, 6 in file_check's,
# BSQ_MAX_FAILS and RUSH01_MAX_FAILS in two more -- while the one knob the docs
# named, DIFF_MAX_ROWS, reached only the output table: a student who raised it
# as told saw the same ten rows (finding 167). One knob now, read here, with
# one default, and every case the report leaves out is kept in test.outputs.
#
# rl_rows [SHOW] -- RL_ROWS, how many failing cases to print: SHOW (the
#     runner's --show) when given, else DIFF_MAX_ROWS, else 40. 0 prints all.
# rl_block FILE -- one failing case's report, from FILE: printed while fewer
#     than RL_ROWS have been, and kept whole either way. A block printed is
#     also kept apart (RL_SHOWNF), for rl_shown_legend.
# rl_tally [NAME] -- under the report, when some were left out: how many,
#     where all of them are (test.outputs/NAME, default differences.txt), and
#     how to print more.
# rl_shown_legend ERE [INDENT] [STREAM] -- the legend (rl_vis_legend) of the
#     bytes the printed blocks showed: on each of their lines that the
#     extended regular expression ERE matches, the text after the match. ERE
#     names the labels a runner prints rendered bytes under ("want | ",
#     "expected: "); the rest of a block -- a replay line's shell quoting, an
#     excerpt of stderr, a hint -- is no rendering of the case's bytes, and
#     read whole it named marks no want or got line held. Three runners
#     printed a fixed legend under want and got lines -- "\t a tab, \\ a
#     backslash, \x24 a dollar" under maps holding none of them -- and
#     //tools:conventions now refuses one.
RL_ROWS=40
RL_BLOCKS=0
RL_LISTF=""
RL_SHOWNF=""
rl_rows() {
	RL_ROWS=${1:-${DIFF_MAX_ROWS:-40}}
	case "$RL_ROWS" in
		'' | *[!0-9]*)
			echo "${RL_NAME}: DIFF_MAX_ROWS (or --show) must be a number, 0 for all: got '$RL_ROWS'" >&2
			exit 2 ;;
	esac
}
rl_block() {
	RL_BLOCKS=$((RL_BLOCKS + 1))
	if [ -z "$RL_LISTF" ]; then
		RL_LISTF=$(mktemp) || { echo "${RL_NAME}: cannot create a scratch file" >&2; exit 2; }
	fi
	cat "$1" >> "$RL_LISTF"
	[ "$RL_ROWS" -ne 0 ] && [ "$RL_BLOCKS" -gt "$RL_ROWS" ] && return 0
	cat "$1"
	if [ -z "$RL_SHOWNF" ]; then
		RL_SHOWNF=$(mktemp) || { echo "${RL_NAME}: cannot create a scratch file" >&2; exit 2; }
	fi
	cat "$1" >> "$RL_SHOWNF"
}
rl_shown_legend() {
	[ -n "$RL_SHOWNF" ] && [ -s "$RL_SHOWNF" ] || return 0
	# Through the environment, not -v: awk reads escapes in a -v value, and
	# a backslash in the expression would arrive as something else.
	RL__ERE="$1" LC_ALL=C awk 'match($0, ENVIRON["RL__ERE"]) { print substr($0, RSTART + RLENGTH) }' \
		"$RL_SHOWNF" > "$RL_SHOWNF.legend"
	rl_vis_legend "$RL_SHOWNF.legend" "${2-  }" "${3:-0}"
}
rl_tally() {
	[ "$RL_ROWS" -ne 0 ] && [ "$RL_BLOCKS" -gt "$RL_ROWS" ] || return 0
	echo ""
	if rl_save "$RL_LISTF" "${1:-differences.txt}"; then
		echo "  ... $((RL_BLOCKS - RL_ROWS)) more failing case(s) not shown here; all $RL_BLOCKS are in"
		echo "      $RL_SAVED"
	else
		echo "  ... $((RL_BLOCKS - RL_ROWS)) more failing case(s) not shown (a run under bazel test keeps all $RL_BLOCKS)."
	fi
	echo "      Raise with --test_env=DIFF_MAX_ROWS=N (0 shows every one)."
}

# ---------------------------------------------------------------------------
# WHAT A PROGRAM ALSO WROTE.
#
# A case compares one stream. The other is shown under a failing case, and on
# a passing one it used to be shown nowhere: a debug line a program wrote to
# standard error on every run stayed green and invisible in every log, while
# anyone running the program in a terminal sees it above the answer (finding
# 156). It is never graded -- no subject here asks anything of stderr
# (docs/reference.md, "Run contract") -- but it is said.
#
# rl_stderr FILE WHAT -- after a run whose stderr went to FILE: counted when
#     not empty, and the first such one kept, WHAT naming its case.
# rl_stderr_note [NOUN] -- "N case(s) also wrote to standard error (not
#     graded)", with the first one's text. Silent when none did, and under a
#     corpus runner's --stderr-empty, where such a case is a failure and its
#     report says so (rl_stderr_noisy); rl_stderr_rule says what stderr was
#     held to. NOUN replaces "case(s)" for a runner whose runs are not all
#     cases: Rush 01's probes are counted apart from its corpus, and "2
#     case(s)" over two probes named cases that had written nothing.
RL_ERRS=0
RL_ERR_WHAT=""
RL_ERRF=""
rl_stderr() {
	[ -s "$1" ] || return 0
	RL_ERRS=$((RL_ERRS + 1))
	[ "$RL_ERRS" -eq 1 ] || return 0
	RL_ERR_WHAT=$2
	RL_ERRF=$(mktemp) || { echo "${RL_NAME}: cannot create a scratch file" >&2; exit 2; }
	cp "$1" "$RL_ERRF"
}
rl_stderr_note() {
	[ "$RL_ERRS" -gt 0 ] || return 0
	[ "$STDERR_EMPTY" != 1 ] || return 0
	echo ""
	echo "  note: $RL_ERRS ${1:-case(s)} also wrote to standard error (not graded: no case here"
	echo "        compares it). Whoever runs the program in a terminal sees it above"
	echo "        the answer. The first, $RL_ERR_WHAT:"
	rl_excerpt "$RL_ERRF" 5 stderr-first-case.txt "        | "
}

# ---------------------------------------------------------------------------
# A CORPUS UNDER A MEMORY CHECKER (finding 113).
#
# The memory layers ran the hand-written cases only: c_program attaches an
# ASan and a valgrind arm to each FIXED case, and every generated corpus --
# Rush 01's sweep, Rush 02's numbers, BSQ's maps, C 06's arguments, C 10's
# files -- ran on the plain build, where an overflow that happens to print the
# right bytes passes and a leak changes no byte at all. So a path only a
# generated input reaches (a search that found nothing, a long number, a big
# map, a file past one buffer) was never memory-checked. Each corpus runner
# now replays its corpus under a checker when asked, through this section:
#
#   --sanitized     BIN is the ASan/UBSan build (:exNN_bin_asan). Every case
#                   runs, and only memory and how each run ended are judged:
#                   a sanitizer report, a signal, runaway output. The
#                   output is not compared -- that is the plain replay's
#                   finding, and a wrong answer under a sanitizer is not a
#                   memory error -- but it is written to a scratch file, never
#                   /dev/null: the runner's `ulimit -f` caps a file and not
#                   /dev/null, so a program printing without end ran out its
#                   time instead and was reported as a hang. Leaks are not
#                   looked for (detect_leaks=0, as in every ASan arm): they
#                   are memcheck's. With --symbolizer PATH --symbolizer-lib
#                   FILE, the pinned llvm-symbolizer names each frame of a
#                   report's stack, as in every ASan arm (rl_sanitizers).
#   --valgrind PATH --valgrind-tools FILE [--sample N]
#                   N cases (RL_MEM_SAMPLE, 25), spread evenly over the corpus
#                   -- never its head, which is where the simplest inputs are
#                   -- each run under memcheck through tools/valgrind_test.sh:
#                   leaks, invalid access to the heap or unmapped memory,
#                   uninitialised values, descriptors left open, exactly as
#                   a fixed case's _valgrind arm judges one run. memcheck is
#                   20-50x slower, hence the sample.
#   --rule FILE     with --valgrind: the subject's own sentence about memory
#                   (c_program's memory_rule, which corpus_memory() hands
#                   over), quoted once under a red verdict; without it the
#                   verdict states the rule it applies as this harness's,
#                   as a fixed case's _valgrind arm does. A corpus quoted
#                   neither (V82).
#
# A RUN THAT DID NOT FINISH is said, and never judged wrong: what it would
# have done next was not seen, and no subject here sets a time limit, so an
# infinite loop and a program too slow for the input under a checker look
# the same (the owner's ruling R4, for BSQ's big maps). It is counted apart
# (RL_MEM_DNF), the verdict line says "did not finish", and the target is
# still red: a replay with a case nobody judged has not passed. Under either
# checker such runs count towards RL_MAX_HANGS, as in a plain replay. A memory
# replay once told a correct, slow program's run "went wrong" beside the
# plain replay's "No answer was judged wrong" (V48).
#
# In a runner:
#
#     --sanitized | --valgrind | --valgrind-tools | --sample | \
#     --symbolizer | --symbolizer-lib | --rule)
#             rl_mem_opt "$@"; shift "$RL_MEM_SHIFT" ;;     # option loop
#     rl_mem_ready                                          # after it
#     standin_check NAME "$BIN" "$RL_STANDIN" ...           # tools/standin.sh
#     ...
#     rl_mem_pick K M || continue          # this case in the sample?
#     rl_sweep_next "$CAP" || break        # time left to start it
#     rl_mem_run [--stdin FILE] -- ARG...  # BIN under the checker
#     [ "$RL_MEM_BAD" = 0 ] || { <the case, how to replay it>; rl_mem_report; }
#     ...
#     rl_mem_tally DONE M                  # the verdict line, 0 or 1
#     rl_mem_argv_note GUARDED [HOW]       # input in argv: what ASan saw of it
#     rl_mem_count M; rl_mem_stopped DONE  # or, when the sweep stopped early
#
# RL_MEM is "" for an ordinary replay, "sanitized" or "valgrind".
#
# A PROGRAM THAT NEVER BUILT is the output layer's story, not a memory
# checker's: a memory arm on a build stand-in (tools/standin.sh) SKIPs, as
# asan_run.sh, argv_table.sh --memory-only and valgrind_test.sh's gate do, and
# NO_SKIP=1 turns that red. RL_STANDIN is the mode each runner hands
# standin_check: "fail" for an ordinary replay -- the stand-in is its red --
# and "skip" under a memory checker. Without it, Rush 02's memory arms were
# red at strict and robust on the unwritten stub, two reds saying again what
# its output layer already says.
RL_STANDIN=fail
RL_MEM=""
# shellcheck disable=SC2034 # the caller's to read: how many words to shift
RL_MEM_SHIFT=1
RL_VG=""
RL_VGTOOLS=""
RL_MEM_SAMPLE=""
RL_MEM_RULE=""
RL_MEM_SYM=""
RL_MEM_SYMLIB=""
RL_MEM_SYMD=""
RL_MEM_RAN=0
RL_MEM_FAILS=0
RL_MEM_DNF=0
RL_MEM_EXPLAIN=""
RL_MEM_KIND=""
RL_MEM_BAD=0
RL_MEM_OUT=""
RL_MEM_STDOUT=""
RL_MEM_STATUS=""
RL_VG_TEST=""
# shellcheck disable=SC2034 # RL_MEM_SHIFT is the caller's, to shift by
rl_mem_opt() {
	case "$1" in
		--sanitized)
			RL_MEM_SHIFT=1
			[ "$RL_MEM" != valgrind ] || rl__mem_both
			RL_MEM=sanitized ;;
		--valgrind | --valgrind-tools | --sample | --rule | --symbolizer | --symbolizer-lib)
			[ "$#" -ge 2 ] || { echo "${RL_NAME}: $1 needs a value" >&2; exit 2; }
			RL_MEM_SHIFT=2
			case "$1" in
				--valgrind)
					[ "$RL_MEM" != sanitized ] || rl__mem_both
					RL_VG=$2
					RL_MEM=valgrind ;;
				--valgrind-tools) RL_VGTOOLS=$2 ;;
				--sample) RL_MEM_SAMPLE=$2 ;;
				--rule) RL_MEM_RULE=$2 ;;
				--symbolizer) RL_MEM_SYM=$2 ;;
				--symbolizer-lib) RL_MEM_SYMLIB=$2 ;;
			esac ;;
		*) echo "${RL_NAME}: rl_mem_opt: not a memory-checker option: $1" >&2; exit 2 ;;
	esac
}
rl__mem_both() {
	echo "${RL_NAME}: --sanitized and --valgrind are two targets, not one: each" >&2
	echo "  judges its own runs, and a case run under both would be judged twice." >&2
	exit 2
}
# rl_mem_ready -- check the options rl_mem_opt took, and set up the checker.
rl_mem_ready() {
	if [ -n "$RL_VGTOOLS$RL_MEM_SAMPLE$RL_MEM_RULE" ] && [ "$RL_MEM" != valgrind ]; then
		echo "${RL_NAME}: --valgrind-tools, --sample and --rule go with --valgrind" >&2
		exit 2
	fi
	if [ -n "$RL_MEM_SYM$RL_MEM_SYMLIB" ] && [ "$RL_MEM" != sanitized ]; then
		echo "${RL_NAME}: --symbolizer and --symbolizer-lib go with --sanitized" >&2
		exit 2
	fi
	case "$RL_MEM" in
		sanitized)
			# The settings of every ASan arm (asan_run.sh, rust_diff.sh), from
			# the one place that sets them (rl_sanitizers): stop at the first
			# report, as SIGABRT, and leave leaks to memcheck. And the pinned
			# symbolizer, as every ASan arm has it, so a report's frames name
			# a file and a line (corpus_memory() hands it over; tools/defs.bzl,
			# _SYMBOLIZER_RUNNERS): without it each frame was a bare offset
			# into a binary in Bazel's cache. Never one a PATH search finds:
			# with no --symbolizer the frames are left unsymbolised.
			# Its folder is the library's, removed by rl__cleanup: a run by
			# hand (no Bazel tmp to throw away) left one per run in TMPDIR.
			if [ -n "$RL_MEM_SYM" ]; then
				RL_MEM_SYMD=$(mktemp -d) || { echo "${RL_NAME}: cannot create a scratch folder" >&2; exit 2; }
				rl_sanitizers "$RL_MEM_SYMD" "$RL_MEM_SYM" "$RL_MEM_SYMLIB"
			else
				rl_sanitizers ""
			fi
			;;
		"valgrind")
			[ -n "$RL_VGTOOLS" ] || { echo "${RL_NAME}: --valgrind needs --valgrind-tools" >&2; exit 2; }
			RL_MEM_SAMPLE=${RL_MEM_SAMPLE:-25}
			case "$RL_MEM_SAMPLE" in
				'' | *[!0-9]* | 0) echo "${RL_NAME}: --sample must be a count of cases, got '$RL_MEM_SAMPLE'" >&2; exit 2 ;;
			esac
			case "$RL_VG" in /*) ;; *) RL_VG="$PWD/$RL_VG" ;; esac
			case "$RL_VGTOOLS" in /*) ;; *) RL_VGTOOLS="$PWD/$RL_VGTOOLS" ;; esac
			if [ -n "$RL_MEM_RULE" ]; then
				[ -s "$RL_MEM_RULE" ] || { echo "${RL_NAME}: no sentence in --rule $RL_MEM_RULE" >&2; exit 2; }
				case "$RL_MEM_RULE" in /*) ;; *) RL_MEM_RULE="$PWD/$RL_MEM_RULE" ;; esac
			fi
			case "$0" in */*) _rl_here=${0%/*} ;; *) _rl_here=. ;; esac
			for RL_VG_TEST in "$_rl_here/valgrind_test.sh" \
				"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/valgrind_test.sh"; do
				[ -f "$RL_VG_TEST" ] && break
			done
			[ -f "$RL_VG_TEST" ] || {
				echo "${RL_NAME}: --valgrind runs each case through tools/valgrind_test.sh, which" >&2
				echo "  is not beside this runner or in the runfiles (list //tools:valgrind_test.sh)" >&2
				exit 2
			}
			;;
	esac
	# shellcheck disable=SC2034 # the caller's, for standin_check
	[ -z "$RL_MEM" ] || RL_STANDIN=skip
	RL_MEM_OUT=$(mktemp) || { echo "${RL_NAME}: cannot create a scratch file" >&2; exit 2; }
	RL_MEM_STDOUT=$(mktemp) || { echo "${RL_NAME}: cannot create a scratch file" >&2; exit 2; }
	RL_MEM_STATUS=$(mktemp) || { echo "${RL_NAME}: cannot create a scratch file" >&2; exit 2; }
}
# rl_mem_pick K M -- true when case K of M runs: every case under --sanitized,
# and under --valgrind the RL_MEM_SAMPLE spread evenly, the last case always
# among them (K is picked when K * N / M passes a whole number).
rl_mem_pick() {
	[ "$RL_MEM" = valgrind ] || return 0
	[ "$RL_MEM_SAMPLE" -lt "$2" ] || return 0
	[ $(($1 * RL_MEM_SAMPLE / $2)) -ne $(( ($1 - 1) * RL_MEM_SAMPLE / $2)) ]
}
# rl_mem_count M -- RL_MEM_N, how many of M cases the checker runs: all of
# them, or the sample when it is smaller. What a stopped sweep counts against.
# shellcheck disable=SC2034 # the caller's to read
RL_MEM_N=0
# shellcheck disable=SC2034 # RL_MEM_N is the caller's to read
rl_mem_count() {
	RL_MEM_N=$1
	[ "$RL_MEM" != valgrind ] || [ "$RL_MEM_SAMPLE" -ge "$1" ] || RL_MEM_N=$RL_MEM_SAMPLE
}
# rl_mem_run [--what TEXT] [--stdin FILE] -- ARG... -- one case of BIN under
# the checker, after rl_sweep_next; TEXT names it in memcheck's report ("case
# 15 of 30"), as the runner's own block does. Sets RL_MEM_BAD (1 when the
# case is to be shown: it went wrong, or did not finish), RL_MEM_KIND
# (sanitizer, crash, timeout, runaway, memcheck) and RL_MEM_OUT, the report to
# show; a timeout is counted in RL_MEM_DNF as well as RL_MEM_FAILS. Exits 2
# when the run could not be made at all.
rl_mem_run() {
	_rl_in=/dev/null
	RL_MEM_RAN=$((RL_MEM_RAN + 1))
	_rl_what="case $RL_MEM_RAN"
	if [ "$1" = --what ]; then _rl_what=$2; shift 2; fi
	if [ "$1" = --stdin ]; then _rl_in=$2; shift 2; fi
	[ "$1" != -- ] || shift
	RL_MEM_BAD=0
	RL_MEM_KIND=""
	: > "$RL_MEM_OUT"
	if [ "$RL_MEM" = valgrind ]; then
		# valgrind_test.sh is the one place a run is judged under memcheck;
		# it inherits this test's deadline (RL_DEADLINE), and its own limit
		# is what rl_sweep_next left this case.
		#
		# A RUN THE TEST'S OWN LIMIT CUT SHORT is not one memcheck judged.
		# valgrind_test.sh says when its run ran out of time (--status-file),
		# and when that time was what the test had left (RL_CLAMPED, from
		# rl_sweep_next) the sweep stops as a budget, the way rl_sweep_ran
		# stops the ASan replay: the case is shown as the one running when the
		# time ran out, and rl_mem_stopped leaves it out of the count of cases
		# judged wrong. It used to be one more memcheck failure, under "each of
		# the first N cases ended within its own limit".
		: > "$RL_MEM_STATUS"
		# conventions: harness tool RL_VG_TEST -- tools/valgrind_test.sh, which runs the case under memcheck through rl_run and keeps this test's budget (RL_DEADLINE)
		#
		# --brief: the case's verdict and evidence alone. What each class of
		# finding means is named on a line of the status file, "explain
		# KEY", and said once, after the cases (rl__mem_explain): every case
		# used to carry it, 25 times in a 25-case sample (V53).
		sh "$RL_VG_TEST" --bin "$BIN" --valgrind "$RL_VG" --valgrind-tools "$RL_VGTOOLS" \
			--label "$_rl_what" --timeout "${RL_TMO:-60}" --stdin "$_rl_in" \
			--status-file "$RL_MEM_STATUS" --brief -- "$@" > "$RL_MEM_OUT" 2>&1
		case $? in
			0) ;;
			1) RL_MEM_BAD=1; RL_MEM_KIND=memcheck ;;
			*)
				echo "${RL_NAME}: valgrind_test.sh could not judge a case (a harness fault):" >&2
				rl_excerpt "$RL_MEM_OUT" 20 memcheck-harness.txt "  " >&2
				exit 2 ;;
		esac
		# A run that ran out of its time was not judged (A RUN THAT DID NOT
		# FINISH, above): its red was memcheck's, "[memcheck]", before. The
		# test's own limit stopped it when this side clamped the case's cap
		# before the run (RL_CLAMPED, from rl_sweep_next), or when the run
		# says so ("clamped S"): its own rl_tmo found less left, or the
		# ceiling -- what the test had left -- stopped it first, which only
		# the run knows. Counted as one more memcheck failure on a busy CPU,
		# the stop said "each of the first N cases ended within its own
		# limit" over a case that had not, and that one case judged wrong
		# (V33).
		#
		# Only a case that is shown (RL_MEM_BAD) adds its paragraphs: one
		# that passed with a note -- a descriptor left open under
		# VALGRIND_FDS=lax names "fds" too -- had its paragraph printed
		# under a leak's verdict, about a report no case above held (the
		# review of V53).
		if [ "$RL_MEM_BAD" = 1 ]; then
			while read -r _rl_k _rl_v; do
				[ "$_rl_k" = explain ] && [ -n "$_rl_v" ] || continue
				case "$RL_NL$RL_MEM_EXPLAIN$RL_NL" in
					*"$RL_NL$_rl_v$RL_NL"*) ;;
					*) rl_list_add RL_MEM_EXPLAIN "$_rl_v" ;;
				esac
			done < "$RL_MEM_STATUS"
		fi
		if [ "$RL_MEM_BAD" = 1 ] && grep -qx timeout "$RL_MEM_STATUS" 2> /dev/null; then
			RL_MEM_KIND="timeout"
			while read -r _rl_k _rl_v; do
				[ "$_rl_k" = clamped ] || continue
				RL_CLAMPED=1
				RL_TMO=$_rl_v
			done < "$RL_MEM_STATUS"
			if [ "$RL_CLAMPED" = 1 ]; then
				RL_STOP=budget
				RL_WHY="was still running under memcheck when the test's time ran out"
			else
				RL_WHY="did not finish within ${RL_TMO:-?}s under memcheck"
				! rl_hang || RL_STOP=hangs
			fi
		fi
		rl__mem_count
		return 0
	fi
	# A file, so that `ulimit -f` can stop a program printing without end
	# (runaway); its bytes are never read.
	rl_run "$BIN" "$@" < "$_rl_in" > "$RL_MEM_STDOUT" 2> "$RL_MEM_OUT"
	rl_sweep_ran "$?"
	: > "$RL_MEM_STDOUT"
	case "$RL_CAUSE" in
		noexec | stopped)
			echo "${RL_NAME}: case $RL_MEM_RAN could not be run: the program $RL_WHY" >&2
			exit 2 ;;
		"timeout") RL_MEM_BAD=1; RL_MEM_KIND="timeout" ;;
		runaway) RL_MEM_BAD=1; RL_MEM_KIND=runaway ;;
	esac
	if rl_sanitized "$RL_MEM_OUT"; then
		RL_MEM_BAD=1
		RL_MEM_KIND=sanitizer
	elif [ "$RL_CAUSE" = signal ]; then
		RL_MEM_BAD=1
		RL_MEM_KIND=crash
	fi
	rl__mem_count
	return 0
}
rl__mem_count() {  # the case rl_mem_run just made, into the tallies
	[ "$RL_MEM_BAD" = 1 ] || return 0
	RL_MEM_FAILS=$((RL_MEM_FAILS + 1))
	[ "$RL_MEM_KIND" != timeout ] || RL_MEM_DNF=$((RL_MEM_DNF + 1))
}
# rl_mem_report -- under a failing case's own lines: what went wrong, and the
# checker's report.
rl_mem_report() {
	case "$RL_MEM_KIND" in
		sanitizer)
			echo "    the sanitizer stopped it at its first finding; its report:"
			# Without its shadow-memory map, as every sanitizer runner shows
			# one; the whole report is kept beside it.
			rl_sanitizer_report "$RL_MEM_OUT" 30 "memory-case-$RL_MEM_RAN.txt" "      | "
			return 0 ;;
		crash) echo "    it $RL_WHY, with no sanitizer report:" ;;
		"timeout")
			# The test's own time ran out in it: rl_sweep_stopped says why below.
			if [ "$RL_STOP" = budget ]; then
				echo "    it $RL_WHY."
			else
				echo "    it $RL_WHY:"
				echo "    an infinite loop, or too slow for this input."
			fi
			echo "    Not judged: what it would have done next was not seen."
			# Under memcheck the report is valgrind_test.sh's own words for
			# the same overrun, written for a fixed case.
			[ "$RL_MEM" != valgrind ] || return 0 ;;
		runaway) echo "    it $RL_WHY" ;;
		memcheck) echo "    memcheck's report:" ;;
	esac
	rl_excerpt "$RL_MEM_OUT" 30 "memory-case-$RL_MEM_RAN.txt" "      | "
}
# rl_mem_tally DONE TOTAL [UNIT] -- the verdict line under the cases; returns
# 1 when any case went wrong or did not finish, which it says apart (A RUN
# THAT DID NOT FINISH, above). DONE is how many of the TOTAL cases were
# started; UNIT names a case where it is not one input ("run(s)": BSQ's
# groups).
rl_mem_tally() {
	echo ""
	_rl_u=${3:-case(s)}
	if [ "$RL_MEM" = sanitized ]; then
		_rl_what="ASan/UBSan"
		if [ "$1" -eq "$2" ]; then
			_rl_ran="all $2 $_rl_u of the corpus ran under $_rl_what"
		else
			_rl_ran="$1 of the corpus's $2 $_rl_u ran under $_rl_what"
		fi
		_rl_judged="a sanitizer report, a signal or runaway output; never the output itself, which the plain replay compares, and never a run that did not finish, which is said apart"
	else
		_rl_what="memcheck"
		_rl_ran="$RL_MEM_RAN of the corpus's $2 $_rl_u, spread evenly over it, ran under memcheck"
		_rl_judged="leaks, invalid access to the heap or to unmapped memory (not a write past an array on the stack that stays inside it), uninitialised values and descriptors left open, as each case's own _valgrind arm judges one run; never the output, and never a run that did not finish, which is said apart"
	fi
	if [ "$RL_MEM_FAILS" -eq 0 ]; then
		echo "${RL_NAME}: PASS — $_rl_ran."
		echo "  Judged: $_rl_judged."
		return 0
	fi
	_rl_wrong=$((RL_MEM_FAILS - RL_MEM_DNF))
	if [ "$RL_MEM_DNF" -eq 0 ]; then
		echo "${RL_NAME}: FAIL — $_rl_wrong of $RL_MEM_RAN $_rl_u under $_rl_what went wrong ($_rl_ran)."
	elif [ "$_rl_wrong" -eq 0 ]; then
		echo "${RL_NAME}: FAIL — $RL_MEM_DNF of $RL_MEM_RAN $_rl_u under $_rl_what did not finish in their time ($_rl_ran)."
		echo "  No case was judged wrong: a run that did not finish was not seen to its end."
		echo "  An infinite loop, or a program too slow for these inputs under $_rl_what."
	else
		echo "${RL_NAME}: FAIL — $_rl_wrong of $RL_MEM_RAN $_rl_u under $_rl_what went wrong, and $RL_MEM_DNF did not"
		echo "  finish in their time, which were not judged ($_rl_ran)."
	fi
	echo "  Judged: $_rl_judged."
	rl__mem_explain
	return 1
}
# rl__mem_explain -- under the verdict of a memcheck replay, what each class of
# finding its cases showed means, each once (valgrind_test.sh --explain), and
# last the rule a memory finding breaks: the subject's sentence (--rule), or
# this harness's, said to be its own.
rl__mem_explain() {
	[ "$RL_MEM" = valgrind ] && [ -n "$RL_MEM_EXPLAIN" ] || return 0
	echo ""
	echo "  What memcheck's reports above mean, said once for every case:"
	echo ""
	rl_split_on
	set --
	_rl_rule=0
	for _rl_k in $RL_MEM_EXPLAIN; do
		if [ "$_rl_k" = rule ]; then
			_rl_rule=1
		else
			set -- "$@" --explain "$_rl_k"
		fi
	done
	rl_split_off
	[ "$_rl_rule" = 0 ] || set -- "$@" --explain rule
	[ -z "$RL_MEM_RULE" ] || set -- "$@" --rule "$RL_MEM_RULE"
	# conventions: harness tool RL_VG_TEST -- tools/valgrind_test.sh, printing paragraphs and running nothing
	sh "$RL_VG_TEST" "$@" || {
		echo "${RL_NAME}: valgrind_test.sh could not explain its own findings (a harness fault)" >&2
		exit 2
	}
}
# rl_mem_argv_note GUARDED [HOW] -- after rl_mem_tally, under --sanitized: what
# the sanitizer could see of the program's arguments, pass or fail (finding
# 071). A program whose input is its arguments reads them where the kernel put
# them, which the sanitizer does not watch: a read past an argument's
# terminator reads the next one's bytes and says nothing, and a PASS said
# nothing of that. GUARDED 1: the run was a guarded build (c_argv_table's
# :exNN_argvguard_bin_asan, tools/argv_guard_main.c), each argument in a heap
# block of exactly its size. HOW, with 0: a sentence on the build that would
# watch them, where the exercise has one. Every corpus runner that hands the
# program arguments says it: argv_check.sh, rush01_check.sh, rush02_check.sh,
# file_check.sh and bsq_check.sh outside its standard-input mode (the wave 6
# review: Rush 01's sweep, whose input is its argument, said nothing).
rl_mem_argv_note() {
	[ "${RL_MEM:-}" = sanitized ] || return 0
	if [ "$1" = 1 ]; then
		echo "  Each run's argv and every argument sat in a heap block of exactly its"
		echo "  size: a read past an argument's end, or past argv[argc], is a report."
		return 0
	fi
	echo "  Reads inside the argument strings, or past argv's end, are invisible"
	echo "  here: the kernel lays the arguments out where the sanitizer does not"
	if [ -n "${2:-}" ]; then
		echo "  watch. $2"
	else
		echo "  watch."
	fi
}
# rl_mem_stopped DONE -- after rl_mem_count: the report of a replay under a
# checker that stopped early (rl_sweep_stopped), DONE of RL_MEM_N started. Its
# count of cases judged wrong leaves out every run that did not finish -- the
# one the test's time ran out in, and any that ran out of its own -- which
# were cut short, not judged; read from the checker's own tally, so no runner
# keeps a second one to pass.
rl_mem_stopped() {
	rl_sweep_stopped "$1" "$RL_MEM_N" "$((RL_MEM_FAILS - RL_MEM_DNF))"
	rl__mem_explain
}

# ---------------------------------------------------------------------------
# SANITIZER RUNS.
#
# rl_sanitizers DIR [SYMBOLIZER LIBFILE] -- export ASAN_OPTIONS and
# UBSAN_OPTIONS for the runs of an instrumented program that follow. The
# harness's keys come first and the caller's own last, so a key someone sets
# to debug a layer wins (docs/reference.md). Every runner that reads a
# sanitizer's report sets them here, so they cannot drift apart:
#
#   detect_leaks=0      a leak is the valgrind layer's finding; LeakSanitizer
#                       here would red a memory-SAFETY layer for a missing free
#   abort_on_error=1    a finding ends the run with SIGABRT, a death no program
#                       chooses by returning
#   halt_on_error=1     the same for UBSan, with its stack printed
#   print_legend=0      the shadow-byte legend is a table for a maintainer
#
# THE SYMBOLIZER, and never one from PATH. Without one every frame is a bare
# offset into a binary in Bazel's cache, "#0 0x4cb9c1 (probe+0x4cb9c1)", which
# a student cannot map to a line (finding 051). SYMBOLIZER is the pinned
# llvm-symbolizer (tools/pins.tsv) and LIBFILE a library file beside the
# libLLVM it loads: like nm and clang it is a frontend that names its library
# as a bare soname, and a box that has a libLLVM-12 of its own would otherwise
# lend it silently. So it is run through a wrapper in DIR -- named
# llvm-symbolizer, which is how the sanitizer runtime picks its protocol --
# that puts LIBFILE's directory first on the loader's path, and the loader is
# asked, once, which libLLVM it actually loaded. With no SYMBOLIZER the
# report is left unsymbolised (symbolize=0) rather than symbolised by
# whatever `llvm-symbolizer` a PATH search finds, which would make the same
# report read differently on two machines.
#
# A wiring fault -- a symbolizer that is not there, a library directory that
# is not, a loader that took libLLVM from somewhere else -- exits 2.
rl_sanitizers() {
	_rl_sym=${2:-}
	_rl_symopt="symbolize=0"
	if [ -n "$_rl_sym" ]; then
		case "$_rl_sym" in /*) ;; *) _rl_sym="$PWD/$_rl_sym" ;; esac
		_rl_symlib=${3:-}
		case "$_rl_symlib" in "") ;; /*) ;; *) _rl_symlib="$PWD/$_rl_symlib" ;; esac
		_rl_symdir=${_rl_symlib%/*}
		if ! [ -f "$_rl_sym" ] || ! [ -x "$_rl_sym" ]; then
			echo "$RL_NAME: the symbolizer '$_rl_sym' is not an executable file" >&2
			exit 2
		fi
		if [ -z "$_rl_symlib" ] || ! [ -d "$_rl_symdir" ]; then
			echo "$RL_NAME: the symbolizer's library directory '$_rl_symdir' does not exist." >&2
			echo "  Without it the loader would take this machine's libLLVM, and the" >&2
			echo "  pinned symbolizer would silently stop being pinned." >&2
			exit 2
		fi
		case "$_rl_sym$_rl_symdir$1" in
			*"'"*)
				echo "$RL_NAME: a path with a single quote in it cannot be put in the symbolizer's wrapper" >&2
				exit 2 ;;
		esac
		mkdir -p "$1" || exit 2
		printf "#!/bin/sh\nLD_LIBRARY_PATH='%s'\nexport LD_LIBRARY_PATH\nexec '%s' \"\$@\"\n" \
			"$_rl_symdir" "$_rl_sym" > "$1/llvm-symbolizer" || exit 2
		chmod +x "$1/llvm-symbolizer" || exit 2
		# PROVE THE LOADER AGREED: `calling init:` names each library ld.so
		# actually loaded, where `trying file=` lists only candidates.
		_rl_loaded=$(LD_DEBUG=libs "$1/llvm-symbolizer" --version 2>&1 > /dev/null |
			awk '/calling init:/ && /libLLVM/ { sub(/.*calling init: /, ""); print }')
		if [ -z "$_rl_loaded" ]; then
			echo "$RL_NAME: could not observe which libLLVM the symbolizer loaded" >&2
			echo "  (LD_DEBUG=libs printed no 'calling init:' line for it)." >&2
			exit 2
		fi
		for _rl_l in $_rl_loaded; do
			case "$_rl_l" in
				"$_rl_symdir"/*) ;;
				*)
					echo "$RL_NAME: the pinned symbolizer loaded '$_rl_l'," >&2
					echo "  which is not under '$_rl_symdir': it would symbolise with" >&2
					echo "  this machine's libLLVM rather than the pinned one." >&2
					exit 2 ;;
			esac
		done
		_rl_symopt="symbolize=1:external_symbolizer_path=$1/llvm-symbolizer"
	fi
	ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:print_legend=0:$_rl_symopt:${ASAN_OPTIONS:-}"
	UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1:$_rl_symopt:${UBSAN_OPTIONS:-}"
	export ASAN_OPTIONS UBSAN_OPTIONS
}

# rl_sanitized FILE -- true when FILE, a run's captured stderr, holds a
# sanitizer's report: the one test of it (asan_run.sh, argv_table.sh and
# rl_mem_run each grepped for it, and rust_diff.sh's replay did not ask).
# Called after rl_classify, it also words how the run ended: abort_on_error=1
# (rl_sanitizers, above) ends a run with SIGABRT at the sanitizer's first
# finding, and rl_signame's words for SIGABRT -- an assertion, stack smashing
# or a glibc heap error -- named every cause but that one, above the
# sanitizer's own report (V50). So where the run died of SIGABRT and the
# report is there, RL_WHY says the sanitizer stopped it; SIGABRT's own words
# stay for an abort with no report.
rl_sanitized() {
	grep -qE 'AddressSanitizer|UndefinedBehaviorSanitizer|LeakSanitizer|runtime error:' "$1" 2> /dev/null ||
		return 1
	if [ "${RL_CAUSE:-}" = signal ] && [ "${RL_SIG:-}" = 6 ]; then
		# shellcheck disable=SC2034 # RL_WHY is the caller's to read.
		RL_WHY="was stopped by the sanitizer, at its first finding"
	fi
	return 0
}

# rl_sanitizer_report FILE N NAME [PREFIX] -- a sanitizer's report, the way
# rl_excerpt shows any captured output, less its shadow-memory map: the
# "Shadow bytes around the buggy address" block is forty lines of hex that
# answer a question the lines above it already answered in words ("0 bytes to
# the right of 3-byte region"), and it used to be what a cut report ended on.
# The whole report is kept as NAME with "-full" before its extension when a
# map was left out, and the note says where.
rl_sanitizer_report() {
	[ -s "$1" ] || return 0
	_rl_mapped=$(LC_ALL=C awk -v out="$1.shown" '
		/^[[:space:]]*Shadow bytes around the buggy address/ { inmap = 1; n++; next }
		inmap && /^[[:space:]]*(=>)?0x[0-9a-f]+:/ { n++; next }
		{ inmap = 0; print > out }
		END { close(out); print n + 0 }' "$1")
	[ -f "$1.shown" ] || : > "$1.shown"
	rl_excerpt "$1.shown" "$2" "$3" "${4-    }"
	[ "${_rl_mapped:-0}" -gt 0 ] || return 0
	case "$3" in
		*.*) _rl_full="${3%.*}-full.${3##*.}" ;;
		*) _rl_full="$3-full" ;;
	esac
	if rl_save "$1" "$_rl_full"; then
		echo "${4-    }(the shadow-memory map is left out; the whole report is in $RL_SAVED)"
	else
		echo "${4-    }(the shadow-memory map is left out)"
	fi
}

# ---------------------------------------------------------------------------
# HINTS.
#
# rl_clues FILE [FAILED [FIRST [CASE [LAYER]]]] -- the one way a clues.tsv is
# read.
#
#   <hint><TAB><case label><TAB><case label>...
#
# '#' lines and blank lines are for maintainers and never printed; only the
# hint column is. At most CLUE_MODE hints are shown (default 3; a number, or
# "all", or 0 for all, as DIFF_MAX_ROWS's 0 shows every row), in file order,
# which is most-fundamental first by the files' own convention. A value it
# cannot read shows three and says so, last in the HINTS block (V101: "al"
# showed three in silence). It reaches awk through ENVIRON, never -v, which
# would read a backslash in it as an escape. Which rows fire depends on what
# the runner knows:
#
#   no FAILED        a runner with no case names to key on, and no CASE (a
#                    compile that failed, a hint file of one test's own):
#                    every row fires.
#   FAILED, a file   of failed case labels, one per line. A row fires when one
#                    of its labels is in it, and a row with no label fires on
#                    any failure. An EMPTY file means something failed that no
#                    case is to blame for (the bytes, the exit status): only
#                    the rows with no label fire, and none may be all there is.
#   FIRST            the label of the case that was running when the program
#                    died: its rows are shown before the others.
#   CASE             the name of the case this test IS (c_program's case
#                    name, or a corpus runner's target, --case): it has
#                    failed whatever did, so it counts as failed with or
#                    without a FAILED file (`rl_clues FILE "" "" CASE`), and
#                    a row keyed to it fires on this test and on no other.
#                    A program case has no table of named cases, and every
#                    row of its file used to be keyed to nothing, so the
#                    same first three hints showed on every case and the one
#                    that fitted stayed hidden (finding 155). Such a row
#                    counts as keyed to nothing for the footer: passing
#                    another case never frees its slot here.
#   LAYER            the key of a layer that is not the output test
#                    (valgrind_test.sh's "valgrind"), whose red is about
#                    something the output cannot show. Its own rows -- keyed
#                    to LAYER -- are shown first, under HINTS; every other
#                    row that fires was written for the output test, and is
#                    shown after them under a heading that says so. A
#                    memcheck red used to print C 13 ex04's three output
#                    hints (a pointer to a pointer, a comparison's sign, the
#                    prototype layer) as its own, under a leak none of them
#                    speaks to, while the output test was green (V55). And
#                    when nothing fires, nothing is shown: the exercise's
#                    first rows, offered elsewhere as "showing what this
#                    exercise has", are the output's too.
#
# The footer under a capped list says how to see the rest, and only promises
# what is true: "pass more cases" frees a slot only for a CASE-KEYED row, since
# a row with no label fires until everything passes. When no row names a
# failing case, the exercise's first hints are shown, said to be unmatched so
# nobody chases the wrong one.
rl_clues() {
	[ -n "${1:-}" ] && [ -f "$1" ] || return 0
	CLUE_MODE="${CLUE_MODE:-}" awk -v cluefile="$1" -v failfile="${2:-}" -v first="${3:-}" -v self="${4:-}" -v layer="${5:-}" '
	function dash(w,    r)  { r = ""; while (length(r) < w) r = r "-"; return r }
	# The end of a HINTS block, after its last line.
	function done() {
		if (badmode)
			print "   (CLUE_MODE is not understood: it takes all, 0 for all, or a number of hints; showing 3)"
		exit
	}
	BEGIN {
		keyed = (failfile != "" || self != "")
		nfailed = 0
		if (failfile != "") while ((getline l < failfile) > 0) if (l != "") { failed[l] = 1; nfailed++ }
		if (self != "" && !(self in failed)) { failed[self] = 1; nfailed++ }
		nall = 0
		while ((getline line < cluefile) > 0) {
			if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) continue
			nf = split(line, f, "\t")
			nall++
			aclue[nall] = f[1]
			fire = 0; top = 0; always = (nf <= 1)
			if (nf <= 1 || !keyed) fire = 1
			else for (j = 2; j <= nf; j++) {
				if (f[j] in failed) fire = 1
				if (first != "" && f[j] == first) top = 1
				if (self != "" && f[j] == self) always = 1
			}
			if (!fire) continue
			# Under a LAYER, a row not keyed to it was written for the
			# output test: kept apart, and shown after the rows keyed to
			# it, which fire on every red of the layer as a row keyed to
			# nothing does on every failure.
			own = 0
			if (layer != "") for (j = 2; j <= nf; j++) if (f[j] == layer) own = 1
			if (own) always = 1
			if (layer != "" && !own) { n3++; c3[n3] = f[1]; k3[n3] = always; continue }
			if (top) { n1++; c1[n1] = f[1]; k1[n1] = always }
			else     { n2++; c2[n2] = f[1]; k2[n2] = always }
		}
		if (nall == 0) exit
		nfired = 0
		for (k = 1; k <= n1; k++) { nfired++; fclue[nfired] = c1[k]; fcatch[nfired] = k1[k] }
		for (k = 1; k <= n2; k++) { nfired++; fclue[nfired] = c2[k]; fcatch[nfired] = k2[k] }
		nown = nfired
		for (k = 1; k <= n3; k++) { nfired++; fclue[nfired] = c3[k]; fcatch[nfired] = k3[k] }
		limit = 3; badmode = 0
		cluemode = ENVIRON["CLUE_MODE"]
		if (cluemode == "all") limit = nall
		else if (cluemode ~ /^[0-9]+$/) limit = ((cluemode + 0) > 0) ? cluemode + 0 : nall
		else if (cluemode != "") badmode = 1

		# No case to blame and no row keyed to nothing: nothing applies, and a
		# hint keyed to a case would point at code that works.
		if (keyed && nfailed == 0 && nfired == 0) exit

		if (nfired == 0) {
			if (layer != "") exit
			shown = (nall < limit) ? nall : limit
			print " " dash(50)
			print " HINTS (none matches this case -- showing what this exercise has):"
			for (k = 1; k <= shown; k++) print "   * " aclue[k]
			if (nall > shown)
				printf "   (%d more -- CLUE_MODE=all shows every one)\n", nall - shown
			done()
		}
		shown = (nfired < limit) ? nfired : limit
		print " " dash(50)
		if (nown > 0) print " HINTS:"
		for (k = 1; k <= shown; k++) {
			if (k == nown + 1 && layer != "")
				print " HINTS (from this exercise, written for its output test rather than this one):"
			print "   * " fclue[k]
		}
		if (nfired <= shown) done()
		if (!keyed) {
			printf "   (%d more -- CLUE_MODE=all shows every one)\n", nfired - shown
			done()
		}
		gated = 0
		for (k = shown + 1; k <= nfired; k++) if (!fcatch[k]) gated = 1
		if (gated)
			printf "   (%d more hidden hint%s -- unlock %s by passing more cases, or CLUE_MODE=all)\n", \
				nfired - shown, (nfired - shown == 1 ? "" : "s"), \
				(nfired - shown == 1 ? "it" : "them")
		else
			printf "   (%d more hidden hint%s -- CLUE_MODE=all shows %s; passing cases will not, %s fire%s on any failure)\n", \
				nfired - shown, (nfired - shown == 1 ? "" : "s"), \
				(nfired - shown == 1 ? "it" : "them"), \
				(nfired - shown == 1 ? "it" : "they"), \
				(nfired - shown == 1 ? "s" : "")
		done()
	}'
}

# rl_waiting STATUS FILE -- under a red output test (STATUS 1), the tests that
# wait for it, read from FILE (one a line, "<test> (<level>)"; subject()'s
# finalizer writes it, tools/defs.bzl's _WAITING), and what Bazel shows for
# them when they run.
#
# A layer gated on the exercise's output (docs/reference.md, "Which layers wait
# for which") stands down while that output is red: it says SKIP in its log and
# exits 0, and Bazel has no way for a test that ran to call itself skipped
# (Bazel 9.2: a test target is PASSED or FAILED; a skipped test CASE in its
# test.xml shows only under --test_summary=detailed, only on a run that
# executed it -- a cached result carries no test case -- and a test.xml of
# the runner's own replaces Bazel's, whose <system-out> holds the log; so no
# runner writes one: HISTORY.md, V25). So the summary under a
# first red listed them as PASSED beside the one red test, and they read as
# "tests that pass because it compiles". The red log is the one a student
# reads, and is where this is said. Called first in a runner's rl_traps
# command, so STATUS is the runner's own exit status. Nothing on any other
# status, or with no FILE, or an empty one.
#
# SAID ONLY WHERE IT IS TRUE, AND FOR THE RUN A BEGINNER MAKES. Under
# NO_SKIP=1 -- every whole-suite run, and docs/testing.md's way to prove a
# tree green -- none of them waits: each runs and its verdict is its own, so
# nothing is said. And `:basic`, or this test by name, runs none of the ones
# above basic, so the block says when they show PASSED (a run that includes
# them) and each line its level; it never offers NO_SKIP=1, which turns every
# forced layer red at once in front of someone who wrote nothing yet.
rl_waiting() {
	[ "$1" = 1 ] && [ -n "${2:-}" ] && [ -s "$2" ] || return 0
	[ "${NO_SKIP:-0}" != 1 ] || return 0
	echo " --------------------------------------------------"
	echo " WAITING FOR THIS OUTPUT: until this test passes, the tests below check"
	echo " nothing. A run that includes them (the level named, a higher one, :exNN"
	echo " or //...) shows each one PASSED while its log says SKIP: not a pass."
	rl_excerpt "$2" 12 waiting-tests.txt "   "
}

# rl_legend FILE -- a diff_clues.txt, printed whole under "----- hint -----".
#
# Not a clues.tsv: a legend is prose (how to read a divergence, then which
# FAMILY of failing inputs implies what), and a differential run has no case
# names to key rows on. It fires only after the curated fixture is green, so
# rationing it protects nothing, and cutting it at three lines once printed
# three fragments of its first sentence. '#' lines are still maintainers' only.
rl_legend() {
	[ -n "${1:-}" ] && [ -f "$1" ] || return 0
	_rl_body=$(awk '!/^[ \t]*#/' "$1")
	[ -n "$_rl_body" ] || return 0
	echo "----- hint -----"
	printf '%s\n' "$_rl_body"
}

# rl_grader_hdrs README SRCS FILE... -- after the student's code failed to
# compile, where the headers the GRADER brings are, and how a compile by hand
# finds them.
#
# A header a subject says 42 provides (C 08's ft_stock_str.h, the ft_list.h
# C 12 ex08 compiles against) is never the student's to write or turn in, so
# the harness keeps its copy under the project's tests/ and every layer puts
# that folder on the include path. A compile by hand without that -I fails on
# the first #include of it, which reads like the student's own mistake, and
# nothing said where the file was (finding 091). FILE is each such header, as
# the test was handed it (its path in the repository); README is the project's
# page that shows a compile by hand, or "" where it has none.
#
# SRCS is the student's sources, as one argument holding a list (one per
# line: LISTS OF WORDS, above; "" for none), because a student may keep a
# copy of their own where the subject allows it (C 12 ex08's `optional`), and
# then THAT copy is the one compiled: a quoted #include finds the file beside
# the source first. The note says so, by fact -- a file of that name beside
# one of SRCS -- instead of pointing at a copy the compile never read. It is
# read line by line, so it reads the same inside rl_split_on or out of it.
rl_grader_hdrs() {
	_rl_rd=${1:-}
	_rl_ss=${2:-}
	shift 2
	[ $# -gt 0 ] || return 0
	echo ""
	for _rl_h in "$@"; do
		_rl_own=""
		while IFS= read -r _rl_s; do
			[ -n "$_rl_s" ] || continue
			_rl_c="${_rl_s%/*}/${_rl_h##*/}"
			case "$_rl_s" in */*) ;; *) _rl_c="${_rl_h##*/}" ;; esac
			# Not the grader's copy itself, where a source sits beside it.
			[ "${_rl_c#./}" != "${_rl_h#./}" ] && [ -f "$_rl_c" ] && { _rl_own=$_rl_c; break; }
		done <<_RL_SRCS
$_rl_ss
_RL_SRCS
		if [ -n "$_rl_own" ]; then
			echo "  ${_rl_h##*/} is the grader's: the subject says it is provided. You keep"
			echo "  a copy of your own beside your sources,"
			echo "    $_rl_own"
			echo "  and that copy is the one compiled here -- a quoted #include finds the"
			echo "  file beside the source first -- not this repository's, at"
			echo "    $_rl_h"
			continue
		fi
		echo "  ${_rl_h##*/} is the grader's: the subject says it is provided, so it is"
		echo "  never yours to write or to turn in. This repository keeps its copy at"
		echo "    $_rl_h"
		echo "  and this layer compiles with -I ${_rl_h%/*}: a compile by hand needs"
		echo "  the same -I."
	done
	[ -z "$_rl_rd" ] || echo "  $_rl_rd shows one."
}

# ---------------------------------------------------------------------------
# A FETCHED COMPILER, PROVED BEFORE IT IS USED.
#
# A compiler Bazel fetched and pinned can start, print the pinned version and
# still be the machine's: clang is a 100 KB driver whose work is done by
# libclang-cpp and libLLVM, which the loader takes from the box when the
# fetched directory is not on its path; gcc finds cc1 by walking up from its
# own path, and takes the box's when that tree was not staged; and gcc shells
# out to an assembler it looks for on PATH unless -B points it at the pinned
# one. None of the three changes a byte of the output, so each is checked
# before the first compile, and each failure is exit 2: the harness is wired
# wrong, the exercise is not wrong.
#
# compile_check.sh, header_check.sh, prototype_check.sh, symbols_test.sh,
# forbidden_symbols.sh, ilp32_test.sh and make_test.sh each carry a copy of
# the library half, written before this existed; the runners written since
# call this. None of those since assembles anything (header_norm.sh
# preprocesses, method_check.sh's --fixed-array stops at -S), so the third
# proof -- the pinned assembler, compile_check.sh's --cc-progs -- is not here
# yet: it comes with the first runner that assembles and calls this, with
# its arms, rather than as code no runner reaches.
#
# rl_cc_pin CC LIBS UNDER
#   CC     the compiler, a path to the fetched one (or a name on PATH)
#   LIBS   the shared libraries it loads, one per line (LISTS OF WORDS, the
#          runner's --cc-lib files; "" for none): each one's directory must
#          exist, and is put first on LD_LIBRARY_PATH, exported
#   UNDER  a file inside the compiler's own tree (--cc-under), or "": the
#          compiler must name that tree in its -print-search-dirs
rl_cc_pin() {
	_rl_cc=$1 _rl_libs=$2 _rl_under=$3
	_rl_dirs=""
	while IFS= read -r _rl_l; do
		[ -n "$_rl_l" ] || continue
		case "$_rl_l" in
			/*) _rl_d=$(dirname "$_rl_l") ;;
			*) _rl_d=$(dirname "$PWD/$_rl_l") ;;
		esac
		[ -d "$_rl_d" ] || {
			echo "$RL_NAME.sh: --cc-lib directory '$_rl_d' does not exist." >&2
			echo "  Without it the loader would fall back to this machine's own" >&2
			echo "  libraries and the pinned compiler would silently stop being" >&2
			echo "  pinned, so this refuses to run rather than pass." >&2
			exit 2
		}
		_rl_dirs="${_rl_dirs:+$_rl_dirs:}$_rl_d"
	done <<_RL_LIBS
$_rl_libs
_RL_LIBS
	if [ -n "$_rl_dirs" ]; then
		LD_LIBRARY_PATH="$_rl_dirs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
		export LD_LIBRARY_PATH
	fi
	command -v "$_rl_cc" > /dev/null 2>&1 || {
		echo "$RL_NAME.sh: the compiler '$_rl_cc' is not executable." >&2
		echo "  This layer compiles before it reads anything, so without one it" >&2
		echo "  would be reporting on nothing. Bazel passes the pinned one through" >&2
		echo "  --cc; if that is missing the target's data is wrong, which is a" >&2
		echo "  harness fault and not a finding about this exercise." >&2
		exit 2
	}
	if [ -n "$_rl_under" ]; then
		_rl_u=$(readlink -f "$_rl_under" 2> /dev/null) || _rl_u=""
		[ -n "$_rl_u" ] || _rl_u=$_rl_under
		_rl_u=$(cd "$(dirname "$_rl_u")" 2> /dev/null && pwd -P) || _rl_u=""
		[ -n "$_rl_u" ] || {
			echo "$RL_NAME.sh: --cc-under '$_rl_under' has no directory" >&2
			exit 2
		}
		"$_rl_cc" -print-search-dirs 2>&1 | grep -qF "$_rl_u" || {
			echo "$RL_NAME.sh: '${_rl_cc##*/}' is not searching its own tree:" >&2
			echo "  $_rl_u is not in its -print-search-dirs, so it would compile" >&2
			echo "  with this machine's cc1 or resource headers while reporting the" >&2
			echo "  pinned version. Refusing rather than passing." >&2
			exit 2
		}
	fi
	return 0
}

# ---------------------------------------------------------------------------
# A FETCHED LINKER, PROVED BEFORE IT IS USED.
#
# A runner that LINKS what it compiles -- asan_check.sh's probe,
# allocfail_check.sh's sweep, header_check.sh's mains, method_check.sh's
# trace -- had a pinned clang (or none) and the box's linker: the clang
# driver looks for `ld` in its -B directories, then beside itself, then on
# PATH, and the fetched clang package has none, so every such link ran
# /usr/bin/ld (TO VERIFY V38: LD_DEBUG showed /bin/ld under C 07's asan and
# allocfail targets). Bazel's own C toolchain links with the pinned binutils
# 2.38 (//tools/cc_toolchain), and these links now do too.
#
# The pinned ld.bfd is a frontend over libbfd and libctf, named by bare
# soname with no RUNPATH, so it is reached through a wrapper that puts their
# directory on the loader's path -- the shape rl_sanitizers gives the
# symbolizer. The wrapper is named `ld` and `ld.bfd` in a directory the
# compiler is handed with -B, which it searches first for both names: plain
# `ld` is what a link without -fuse-ld runs (bfd, as on campus, where
# /usr/bin/ld is ld.bfd), and `ld.bfd` what -fuse-ld=bfd runs. -B is no
# link-only flag -- a compile ignores it without a warning, where
# -fuse-ld=bfd under -Werror is an error on a compile -- so a runner puts
# RL_LDFLAG on every command it runs the compiler with, and cannot get the
# link wrong by forgetting which of them link. Nothing here can see a command
# written without it, so tools/conventions.sh reads every file that calls
# this for one (header_check.sh and method_check.sh had it on their link line
# alone: review of W7-V38).
#
# Three proofs, each a refusal (exit 2: the harness is wired wrong, the code
# under test is not wrong), because each failure looks like a pass:
#   - the loader took libbfd and libctf from the directories given
#     (LD_DEBUG=libs, `calling init:`), not from the box;
#   - the driver, handed -B, names the wrapper as the program it links
#     with (-###): a -B directory that does not exist is ignored without a
#     word, and the link then runs the box's ld;
#   - a program that does nothing, compiled and linked with the runner's
#     own FLAGS (-fsanitize=...) through it, links and runs. Without this a
#     wrapper that cannot link would surface on the first real link, as the
#     student's "compile FAILED".
#
# rl_ld_pin CC LD LIBS DIR [FLAG...]
#   CC    the compiler, already proved by rl_cc_pin
#   LD    the fetched ld.bfd (a runner's --ld)
#   LIBS  the libraries it loads, one per line (LISTS OF WORDS, the runner's
#         --ld-lib files): each one's directory must exist
#   DIR   a scratch directory of the runner's, made here, for the wrappers
#   FLAG  the runner's own flags that change what a link needs
# Sets RL_LDFLAG, the one flag every compiler command of the runner takes,
# quoted as one word: -BDIR/.
rl_ld_pin() {
	_rl_cc=$1 _rl_ld=$2 _rl_libs=$3 _rl_lw=$4
	shift 4
	case "$_rl_ld" in /*) ;; *) _rl_ld="$PWD/$_rl_ld" ;; esac
	if ! [ -f "$_rl_ld" ] || ! [ -x "$_rl_ld" ]; then
		echo "$RL_NAME.sh: the linker '$_rl_ld' is not an executable file." >&2
		echo "  Bazel passes the pinned ld.bfd through --ld; if that is missing the" >&2
		echo "  target's data is wrong, which is a harness fault and not a finding" >&2
		echo "  about this exercise." >&2
		exit 2
	fi
	_rl_dirs=""
	while IFS= read -r _rl_l; do
		[ -n "$_rl_l" ] || continue
		case "$_rl_l" in
			/*) _rl_d=$(dirname "$_rl_l") ;;
			*) _rl_d=$(dirname "$PWD/$_rl_l") ;;
		esac
		[ -d "$_rl_d" ] || {
			echo "$RL_NAME.sh: --ld-lib directory '$_rl_d' does not exist." >&2
			echo "  Without it the loader would take this machine's libbfd, and the" >&2
			echo "  pinned linker would silently stop being pinned." >&2
			exit 2
		}
		_rl_dirs="${_rl_dirs:+$_rl_dirs:}$_rl_d"
	done <<_RL_LIBS
$_rl_libs
_RL_LIBS
	[ -n "$_rl_dirs" ] || {
		echo "$RL_NAME.sh: --ld needs its --ld-lib: the pinned ld.bfd loads libbfd and" >&2
		echo "  libctf by bare name, and without their directory the loader takes" >&2
		echo "  this machine's." >&2
		exit 2
	}
	case "$_rl_ld$_rl_dirs$_rl_lw" in
		*"'"*)
			echo "$RL_NAME.sh: a path with a single quote in it cannot be put in the linker's wrapper" >&2
			exit 2 ;;
	esac
	mkdir -p "$_rl_lw" || exit 2
	for _rl_n in ld ld.bfd; do
		printf "#!/bin/sh\nLD_LIBRARY_PATH='%s'\nexport LD_LIBRARY_PATH\nexec '%s' \"\$@\"\n" \
			"$_rl_dirs" "$_rl_ld" > "$_rl_lw/$_rl_n" || exit 2
		chmod +x "$_rl_lw/$_rl_n" || exit 2
	done
	# PROVE THE LOADER AGREED, as rl_sanitizers does for the symbolizer.
	# conventions: harness tool -- the pinned linker's wrapper, written above
	_rl_loaded=$(LD_DEBUG=libs "$_rl_lw/ld" --version 2>&1 > /dev/null |
		awk '/calling init:/ && (/libbfd/ || /libctf/) { sub(/.*calling init: /, ""); print }')
	case "$_rl_loaded" in
		*libbfd*) ;;
		*)
			echo "$RL_NAME.sh: could not observe which libbfd the pinned linker loaded" >&2
			echo "  (LD_DEBUG=libs printed no 'calling init:' line for it)." >&2
			exit 2 ;;
	esac
	for _rl_l in $_rl_loaded; do
		_rl_ok=0
		_rl_rest=$_rl_dirs
		while [ -n "$_rl_rest" ]; do
			_rl_d=${_rl_rest%%:*}
			case "$_rl_rest" in *:*) _rl_rest=${_rl_rest#*:} ;; *) _rl_rest="" ;; esac
			case "$_rl_l" in "$_rl_d"/*) _rl_ok=1 ;; esac
		done
		[ "$_rl_ok" = 1 ] || {
			echo "$RL_NAME.sh: the pinned linker loaded '$_rl_l'," >&2
			echo "  which is not under $_rl_dirs: it would link with this" >&2
			echo "  machine's binutils rather than the pinned one." >&2
			exit 2
		}
	done
	# PROVE THE DRIVER TAKES IT: the program -### names for the link.
	printf 'int\tmain(void)\n{\n\treturn (0);\n}\n' > "$_rl_lw/nothing.c" || exit 2
	_rl_said=$("$_rl_cc" "-B$_rl_lw/" "$@" -### "$_rl_lw/nothing.c" -o "$_rl_lw/nothing" 2>&1)
	case "$_rl_said" in
		*"\"$_rl_lw/ld\""* | *"\"$_rl_lw/ld.bfd\""*) ;;
		*)
			echo "$RL_NAME.sh: '${_rl_cc##*/}' did not take the pinned linker." >&2
			echo "  -B$_rl_lw/ was passed, and the link it plans (-###) runs another" >&2
			echo "  program -- this machine's ld, whichever that is:" >&2
			printf '%s\n' "$_rl_said" | awk 'END { print "    " substr($0, 1, 200) }' >&2
			echo "  Refusing rather than passing." >&2
			exit 2 ;;
	esac
	# AND THAT IT LINKS: a program that does nothing, built with the
	# runner's own flags, links and ends with 0.
	if ! "$_rl_cc" "-B$_rl_lw/" "$@" "$_rl_lw/nothing.c" -o "$_rl_lw/nothing" \
			> "$_rl_lw/nothing.err" 2>&1; then
		echo "$RL_NAME.sh: the pinned compiler and linker cannot build a program that" >&2
		echo "  does nothing, so a failure to build here would say nothing about the" >&2
		echo "  code under test. What they said:" >&2
		rl_excerpt "$_rl_lw/nothing.err" 10 linker-probe.txt >&2
		exit 2
	fi
	# conventions: harness tool -- the do-nothing program built just above
	"$_rl_lw/nothing" > /dev/null 2>&1 || {
		echo "$RL_NAME.sh: a program that does nothing, built with the pinned linker," >&2
		echo "  did not end with 0. Refusing rather than reporting on this toolchain." >&2
		exit 2
	}
	# shellcheck disable=SC2034 # read by the runner that called rl_ld_pin
	RL_LDFLAG="-B$_rl_lw/"
	return 0
}

# rl_cc_wrap CC LIBS LDDIR OUT -- write OUT, a script that runs CC with the
# directory of each of LIBS (one per line, as rl_cc_pin takes them) first on
# the loader's path, and -BLDDIR/ -- the wrappers rl_ld_pin wrote there --
# before its own arguments: the pinned compiler AND linker as one command,
# for a caller that hands a compiler to something that takes neither
# --cc-lib nor --ld. The selftests build every fixture with one, and hand it
# to the runners they drive by hand as their compiler; it used to be the
# box's `cc` (TO VERIFY V28). Call it after rl_cc_pin and rl_ld_pin have
# proved CC, LIBS and LDDIR.
rl_cc_wrap() {
	_rl_cw_cc=$1 _rl_cw_libs=$2 _rl_cw_ld=$3 _rl_cw_out=$4
	case "$_rl_cw_cc" in /*) ;; *) _rl_cw_cc="$PWD/$_rl_cw_cc" ;; esac
	case "$_rl_cw_ld" in /*) ;; *) _rl_cw_ld="$PWD/$_rl_cw_ld" ;; esac
	_rl_cw_dirs=""
	while IFS= read -r _rl_l; do
		[ -n "$_rl_l" ] || continue
		case "$_rl_l" in
			/*) _rl_d=$(dirname "$_rl_l") ;;
			*) _rl_d=$(dirname "$PWD/$_rl_l") ;;
		esac
		_rl_cw_dirs="${_rl_cw_dirs:+$_rl_cw_dirs:}$_rl_d"
	done <<_RL_CW
$_rl_cw_libs
_RL_CW
	case "$_rl_cw_cc$_rl_cw_dirs$_rl_cw_ld" in
		*"'"*)
			echo "$RL_NAME: a path with a single quote in it cannot be put in the compiler's wrapper" >&2
			exit 2 ;;
	esac
	printf "#!/bin/sh\nLD_LIBRARY_PATH='%s'\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\nexport LD_LIBRARY_PATH\nexec '%s' '-B%s/' \"\$@\"\n" \
		"$_rl_cw_dirs" "$_rl_cw_cc" "$_rl_cw_ld" > "$_rl_cw_out" || exit 2
	chmod +x "$_rl_cw_out" || exit 2
}

# ---------------------------------------------------------------------------
# STANDARD ERROR, A CHOICE AT EVERY CALL.
#
# A corpus runner runs a program once per generated input and compares its
# standard output; what its standard error is held to is the call site's
# decision, by the Run contract (docs/reference.md): ignored unless the
# subject requires something of it. A default is not a decision. file_check.sh
# ignored stderr unless a call remembered --stderr-empty, and argv_check.sh,
# bsq_check.sh and rush02_check.sh threw it away on every run, so the next
# corpus would have ignored it by omission rather than by its subject's say-so
# (review of WP-50). Each of them now takes the same pair, parsed into
# STDERR_EMPTY (1 for --stderr-empty) and STDERR_WHY (--stderr-ignored's
# REASON), and tools/defs.bzl refuses, while loading, a call that makes the
# choice zero or two times (_RUNNER_CHOICES), as these refuse a call by hand:
#
#   --stderr-empty            a run that writes anything to stderr fails, its
#                             output right or not: every generated input is
#                             valid, and the call site quotes the sentence
#                             that gives a valid input no message
#   --stderr-ignored REASON   stderr is not judged; it is still shown beside
#                             a case that failed, and the PASS line says why
#
# UNDER A MEMORY CHECKER (--sanitized, --valgrind: "A CORPUS UNDER A MEMORY
# CHECKER" above) the mode is the choice, and neither flag is given: standard
# error is where the checker writes its report, which is what such a replay
# reads, and no output is judged, so "held empty" or "ignored because ..."
# would each claim something that replay does not do. tools/defs.bzl's
# _runner_choice_problem says the same while loading.
#
# The two variables are set here, when this file is sourced, so that every
# helper reads them set -- in a runner that takes no pair too, and in a
# corpus runner's replay under a memory checker -- and neither is a knob of
# the environment: a runner that takes the pair sets them from its options.
STDERR_EMPTY=0
STDERR_WHY=""

# rl_stderr_choice -- exit 2 unless exactly one was given, or, under a memory
# checker, unless none was. Call it after the option loop (RL_MEM is set by
# rl_mem_opt there).
rl_stderr_choice() {
	if [ -n "${RL_MEM:-}" ]; then
		if [ "$STDERR_EMPTY" = 1 ] || [ -n "$STDERR_WHY" ]; then
			echo "$RL_NAME.sh: --stderr-empty and --stderr-ignored go with a replay that compares output; under --$RL_MEM standard error carries the checker's report, and no output is judged" >&2
			exit 2
		fi
		return 0
	fi
	if [ "$STDERR_EMPTY" = 1 ] && [ -n "$STDERR_WHY" ]; then
		echo "$RL_NAME.sh: --stderr-empty and --stderr-ignored both given: standard error is judged, or it is not" >&2
		exit 2
	fi
	if [ "$STDERR_EMPTY" != 1 ] && [ -z "$STDERR_WHY" ]; then
		echo "$RL_NAME.sh: say what standard error is held to: --stderr-empty (a valid input gets no message) or --stderr-ignored REASON" >&2
		exit 2
	fi
}

# rl_stderr_noisy FILE -- true when FILE (a run's stderr) is a fault: the call
# held stderr empty and the run wrote to it.
rl_stderr_noisy() {
	[ "$STDERR_EMPTY" = 1 ] && [ -s "$1" ]
}

# rl_stderr_rule -- the PASS line's second line: what stderr was held to.
# (rl_stderr_note, under WHAT A PROGRAM ALSO WROTE, is the other half: the
# cases that wrote to it anyway.)
rl_stderr_rule() {
	if [ "$STDERR_EMPTY" = 1 ]; then
		echo "  Nothing reached standard error on any of them, as this check requires."
	else
		echo "  Standard error was not judged: $STDERR_WHY"
	fi
}

# ---------------------------------------------------------------------------
# A SUBJECT'S SENTENCE COMES FROM THE CALL SITE (--quotes FILE).
#
# A runner only one project calls is still not where that project's subject is
# written. rush01_check.sh told its reader "the subject prints it verbatim",
# and bsq_check.sh restated BSQ's tie rule in words of its own: each a second
# copy of a sentence, with no page beside it, and the first to go stale when
# 42 revises the subject (V90; the owner's ruling, 2026-10-09). So a sentence
# a message quotes arrives the way make_test.sh's do: a file of KEY<TAB>TEXT
# lines, written once in the project's BUILD.bazel through tools/defs.bzl's
# runner_quotes(), each TEXT saying where it is from. A runner that takes one
# parses --quotes with rl_quotes_opt, calls rl_quotes_ready with the keys it
# quotes after its option loop, and prints one with rl_quote; tools/defs.bzl's
# _RUNNER_CHOICES refuses, while loading, a call that passes none.
#
# UNDER A MEMORY CHECKER no output is judged and no message quotes anything,
# so there the file is not required.
RL_QUOTES=""

# rl_quotes_opt FILE -- the option loop's --quotes: FILE exists, and is kept
# absolute, since a runner may change directory before it reads it.
rl_quotes_opt() {
	[ -f "$1" ] || { echo "$RL_NAME.sh: no quotes file at $1" >&2; exit 2; }
	case "$1" in
		/*) RL_QUOTES=$1 ;;
		*) RL_QUOTES=$PWD/$1 ;;
	esac
}

# rl_quotes_ready KEYS -- exit 2 unless --quotes gave a file whose every line
# is KEY<TAB>TEXT, each KEY one of KEYS (blank-separated), and every one of
# KEYS has a line. A key nothing quotes and a message with no sentence behind
# it are both the call site's mistake.
rl_quotes_ready() {
	if [ -z "$RL_QUOTES" ]; then
		[ -n "${RL_MEM:-}" ] && return 0
		{
			echo "$RL_NAME.sh: --quotes FILE is required: the subject's sentences this runner's messages quote, one KEY<TAB>TEXT line for each of: $1"
			echo "  Write them at the call site, each with where it is from (tools/defs.bzl's runner_quotes)."
		} >&2
		exit 2
	fi
	_rq_bad=$(awk -F'\t' -v keys=" $1 " '
		/^[ \t]*(#|$)/ { next }
		NF < 2 || $2 == "" { print "  line " NR ": no TAB and sentence after the key"; next }
		index(keys, " " $1 " ") == 0 { print "  line " NR ": unknown key \047" $1 "\047"; next }
		{ seen[$1] = 1 }
		END {
			n = split(keys, k, " ")
			for (i = 1; i <= n; i++)
				if (!(k[i] in seen)) print "  no line for the key \047" k[i] "\047"
		}' "$RL_QUOTES")
	[ -z "$_rq_bad" ] && return 0
	{
		echo "$RL_NAME.sh: --quotes $RL_QUOTES:"
		printf '%s\n' "$_rq_bad"
		echo "  Each line is KEY<TAB>TEXT, one for each of: $1"
	} >&2
	exit 2
}

# rl_quote KEY -- KEY's sentence, folded at blanks into lines of at most 66
# bytes (a longer word keeps a line of its own), for a message to indent;
# nothing without --quotes.
rl_quote() {
	[ -n "$RL_QUOTES" ] || return 0
	awk -F'\t' -v k="$1" '
		$1 != k { next }
		{
			sub(/^[^\t]*\t/, "")
			n = split($0, w, " ")
			l = ""
			for (i = 1; i <= n; i++) {
				if (l != "" && length(l) + 1 + length(w[i]) > 66) { print l; l = w[i] }
				else l = (l == "" ? w[i] : l " " w[i])
			}
			if (l != "") print l
		}' "$RL_QUOTES"
}

# ---------------------------------------------------------------------------
# WHO GRADES THIS PROJECT.
#
# What a failure costs depends on who reads the turn-in: the Moulinette, a
# program (every Piscine module and BSQ, which peers evaluate too), or the
# evaluators at a defense (the rushes: "This assignment is not verified by a
# program"). The project's subject() contract says which, in its `grader`
# field, and tools/defs.bzl's _test() hands it to every test it declares as
# RL_GRADER: moulinette, defense or both. So a runner never names a grader of
# its own. Every one of them named the Moulinette, and told a rush team that a
# forbidden call was "an outright KO at the Moulinette", which grades no rush
# (finding 145). Unset -- a runner run by hand, or a test outside every
# project -- is worded without naming anyone.
#
# A sentence names the grader through a place, never as the subject of a
# verb, so it reads the same whoever grades: "an outright KO $(rl_at)",
# "the spelling looked for $(rl_at)".
#
#   rl_at      "at the Moulinette" (moulinette, both), "at the defense"
#              (defense), "wherever this project is graded" (unset)
#
# (tools/files_test.sh, which runs no student code and does not source this
# file, takes the same field as --grader, and words its advice by it.)
#
# //tools:conventions refuses a runner line that prints "Moulinette" itself.
case "${RL_GRADER:-}" in
	"" | moulinette | defense | both) ;;
	*)
		echo "runner_lib.sh: RL_GRADER is '$RL_GRADER', and a project's grader is" >&2
		echo "  moulinette, defense or both (tools/subject.bzl): the harness is broken." >&2
		exit 2 ;;
esac

rl_at() {
	case "${RL_GRADER:-}" in
		moulinette | both) printf 'at the Moulinette' ;;
		defense) printf 'at the defense' ;;
		*) printf 'wherever this project is graded' ;;
	esac
}
