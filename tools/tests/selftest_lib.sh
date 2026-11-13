# shellcheck shell=sh
# (sourced by selftest.sh and selftest_slow.sh, never executed -- this
#  directive tells shellcheck the dialect without implying a program.)
#
# selftest_lib.sh -- THE ARM HELPERS, one copy for both drivers.
#
# The helpers that judge an arm (want_*, later_*), show what its command
# said (_st_said) and prove themselves (st_said_meta), the steps both
# drivers take before their first arm (st_shell_guard, st_pin_cc), the one
# builder of every toy (toy_cc) and the one skip line (st_skipped). Each
# driver once carried its own copy, and the copies drifted. selftest_slow.sh's
# had only want_red, want_broken and want_green when three of its arms were
# written against selftest.sh's want_out and want_broken_none, and those arms
# silently did not run (tools/conventions.sh, "calls ... and never defines
# it"). It later grew a want_out of its own and a want_broken_none named
# want_none, and nothing held either to selftest.sh's. //tools:conventions
# now reports a definition of one in a driver or a section: a line that
# starts `name()` or `name ()`, after any blanks ("defines an arm helper
# outside").
#
# What the driver sets before it sources this: TOOLS, WORK, PASS, FAIL and
# ST_NAME, its own name (selftest, selftest_slow), which a refusal of its
# own opens with. What it may set: _st_mine, 0 in a shard's section that is
# not its own (selftest.sh, SHARDS), where every arm returns at once; unset,
# every arm is the driver's.

# The commands this file takes from PATH, probed as a library probes them
# (tools/runner_lib.sh): exit 2, since a missing one means no arm ran.
for _st_t in awk cat chmod find grep mkdir mktemp rm sed sleep; do
	command -v "$_st_t" > /dev/null 2>&1 && continue
	echo "selftest_lib.sh: required command '$_st_t' is not on PATH" >&2
	exit 2
done

# WHAT A FAILED ARM'S COMMAND SAID. Under every FAIL line an arm prints, the
# first lines of what its command wrote, both streams: a runner that refuses
# says why, and an arm that dropped its words left the log only "exit 2 =
# harness error". One loaded run failed 22 rush02 arms that way, the next
# passed, and no log said what had refused; that section alone kept the
# words, through a wrapper of its own, and no other section did (TO VERIFY
# V172). So every helper keeps them, in a scratch file of its own per call
# (`mktemp`, never a fixed name: a command can be an arm itself), and
# _st_said shows them as every layer shows bytes, through runner_lib.sh's
# rl_excerpt -- five lines, the whole text kept as a test output when there
# is more. A pass prints nothing more than it did.
#
# _st_said FILE -- the excerpt, under the FAIL line just printed.
_st_said() {
	if [ ! -s "$1" ]; then
		printf '      (it said nothing)\n'
		return 0
	fi
	# shellcheck disable=SC2016 # the script is for the inner shell to expand
	RL_NAME=$ST_NAME "${SH:-sh}" -c '. "$1"; rl_excerpt "$2" 5 "$3" "      | "' \
		_ "$TOOLS/runner_lib.sh" "$1" "selftest-${1##*/}.txt"
}
# _st_said_text TEXT -- the same, for words an arm captured in a variable.
_st_said_text() {
	_st_sf=$(mktemp "$WORK/said.XXXXXX") || return 0
	[ -z "$1" ] || printf '%s\n' "$1" > "$_st_sf"
	_st_said "$_st_sf"
	rm -f "$_st_sf"
}
# _st_unrooted TEXT -- TEXT with the scratch root, $WORK, written <scratch>,
# as it was given and as `pwd -P` spells it. A refusal names paths under
# $WORK, whose name is mktemp's random letters, and they can spell a word:
# an arm written by hand that asks a runner never said a WORD (OK, FAIL, a
# wrong cause) reads it in this, or a correct refusal reads as one that
# "said 'OK'" (V396: tmp.OK1W13dxsC, tmp.MCOKgDbT57; the compiler pin's
# cc_dead and cc_mute). The helpers below read the raw text: an absence
# arm can be about a path under $WORK itself (tools_bazel's "drives:
# ...and the old root is not named", whose pattern is $WORK/bw/legacy),
# which this text could never show.
_st_unrooted() {
	_st_wp=$(cd "$WORK" 2> /dev/null && pwd -P) || _st_wp=$WORK
	printf '%s\n' "$1" | _ST_R1=$WORK _ST_R2=$_st_wp awk '
		function mask(s, r,   o, i) {
			o = ""
			while (r != "" && (i = index(s, r)) > 0) {
				o = o substr(s, 1, i - 1) "<scratch>"
				s = substr(s, i + length(r))
			}
			return o s
		}
		{ print mask(mask($0, ENVIRON["_ST_R1"]), ENVIRON["_ST_R2"]) }'
}

# want_red / want_green NAME -- COMMAND...
#
# want_red passes ONLY on exit 1, never on "non-zero". Every runner driven from
# here reserves 1 for "the thing under test is wrong" and 2 for "the harness is
# broken" — an unknown option, a missing required flag, an absent compiler under
# NO_SKIP. Treating any non-zero status as a detection conflates exactly the two
# cases that must not be conflated: rename a flag or add a required one, and
# every want_red below would go on printing "ok (red, as required)" while
# checking nothing at all, in the one moment this file exists to notice. That is
# the same false-green shape as the bugs it hunts, one level up. So capture the
# status, and report anything that is not 1 as a check that never ran.
#
# Their words go to a file, not to `$(...)`, which waits for every process
# holding the pipe: a background child the command left behind would hang
# the arm.
want_red() {
	[ "${_st_mine:-1}" = 1 ] || return 0
	_name="$1"; shift; [ "$1" = "--" ] && shift
	_st_f=$(mktemp "$WORK/said.XXXXXX") || _st_f=/dev/null
	"$@" > "$_st_f" 2>&1
	_rc=$?
	case "$_rc" in
		1)
			printf '  %-52s %s\n' "$_name" "ok (red, as required)"
			PASS=$((PASS + 1)) ;;
		0)
			printf '  %-52s %s\n' "$_name" "FAIL < (passed; it must not)"
			FAIL=$((FAIL + 1))
			_st_said "$_st_f" ;;
		*)
			printf '  %-52s %s\n' "$_name" \
				"FAIL < (exit $_rc = harness error; nothing was checked)"
			FAIL=$((FAIL + 1))
			_st_said "$_st_f" ;;
	esac
	[ "$_st_f" = /dev/null ] || rm -f "$_st_f"
}
# want_green tells a red (exit 1, the thing under test is wrong) from a
# harness error (2 or more, nothing was checked), as want_red does: it once
# called both "red", which sends the reader to the code under test when
# the runner never ran.
want_green() {
	[ "${_st_mine:-1}" = 1 ] || return 0
	_name="$1"; shift; [ "$1" = "--" ] && shift
	_st_f=$(mktemp "$WORK/said.XXXXXX") || _st_f=/dev/null
	"$@" > "$_st_f" 2>&1
	_rc=$?
	case "$_rc" in
		0)
			printf '  %-52s %s\n' "$_name" "ok (green, as required)"
			PASS=$((PASS + 1)) ;;
		1)
			printf '  %-52s %s\n' "$_name" "FAIL < (red; it must not be)"
			FAIL=$((FAIL + 1))
			_st_said "$_st_f" ;;
		*)
			printf '  %-52s %s\n' "$_name" \
				"FAIL < (exit $_rc = harness error; nothing was checked)"
			FAIL=$((FAIL + 1))
			_st_said "$_st_f" ;;
	esac
	[ "$_st_f" = /dev/null ] || rm -f "$_st_f"
}

# THE ARMS THAT READ WHAT A COMMAND SAID: want_out, want_broken_none,
# want_broken and want_broken_without, each NAME PAT -- COMMAND... One
# helper judges all four (_st_text_arm, below), as two questions: what the
# status must be, and whether PAT in the command's words is the pass or the
# failure. Each says its verdict in words of its own.
#
# want_out -- the arm for runners whose value is the DIAGNOSIS, not the verdict.
#
# Several checks here would be near-useless if they only went red: "your program
# is wrong" sends a student hunting, while "you built ./rush02 and the subject
# says rush-02" is a two-second fix. That sentence is a feature, and a feature
# with no test rots -- it gets reworded into vagueness, or moved behind a branch
# that stops running, and nothing notices because the exit status is unchanged.
#
# Exit status is deliberately NOT asserted beyond sanity: an explanation is worth
# testing whether it accompanies a pass or a failure. But 2 and above still fail
# the arm, for want_red's reason -- a renamed flag would otherwise leave this
# grepping an error message for a pattern it will never contain and calling that
# a check.
want_out() { _st_text_arm run said "explained itself" "never said '$2'" "$@"; }

# want_broken_none -- the inverse of want_out: the run must have RUN, and must
# NOT contain the text. Needed because the interesting half of a triage is
# what it declines to say.
#
# Exit 2 or above fails the arm, for want_red's reason and with more force here
# than anywhere else: this helper asserts an ABSENCE, so a runner that died
# before printing anything satisfies it perfectly. Its own docstring used to
# promise "the run must succeed" while the code asserted nothing about the
# status at all -- so every arm built on it, including the ones written to prove
# a check stays quiet, would have reported success against a runner that was not
# there. A missing `data` entry is enough to produce exactly that.
#
# 2-or-above rather than "must be 0": several callers point at a runner that
# legitimately exits 1 while the assertion is about one line of its output.
# A saved run of the conventions check carries no status of its own, so an
# arm over one reads it through cv_saved (A SAVED RUN OF THE CONVENTIONS
# CHECK, below), which takes the status back from the run's verdict line.
want_broken_none() {
	_st_text_arm run quiet "stayed quiet, as required" "said '$2'; it must not" "$@"
}

# want_broken — the arm for a runner that REFUSES to run.
#
# Exit 2 means "the harness is misconfigured", and a few checks deliberately use
# it rather than passing: a fetched compiler whose libraries are not where it
# was told they are would otherwise load the box's copies and go green, so the
# only safe answer is to stop. That is a behaviour worth pinning, and neither
# want_red (which treats 2 as a broken harness) nor want_out (same) can say so.
# Both the status AND the explanation are asserted, because a refusal nobody can
# act on is only half of one.
want_broken() {
	_st_text_arm refuse said "refused, and said why" "refused without saying '$2'" "$@"
}

# want_broken_without -- want_broken's refusal, asserting what it must NOT
# say. A refusal that names the wrong cause sends the reader after the wrong
# fix, which the status alone cannot show: cycles_check and ref_compare
# refused a callgrind that stopped at its startup by naming ld.so's debug
# symbols, which only memcheck needs (V242). Exit 2 is required, so a runner
# that died before printing anything does not pass by staying quiet.
want_broken_without() {
	_st_text_arm refuse quiet "refused, naming no wrong cause" "refused saying '$2'; it must not" "$@"
}

# _st_text_arm STATUS PAT_IS OK BAD NAME PAT [--] COMMAND... -- the four
# above. STATUS is `run` (exit 2 or more fails the arm, as a harness error)
# or `refuse` (any exit but 2 fails it); PAT_IS is `said` (PAT in the
# command's words passes the arm) or `quiet` (PAT there fails it). OK is
# what a pass says, and BAD what a FAIL over the words says, PAT in it.
_st_text_arm() {
	[ "${_st_mine:-1}" = 1 ] || return 0
	_st_how=$1; _st_pat_is=$2; _st_ok=$3; _st_bad=$4; shift 4
	_name="$1"; _pat="$2"; shift 2; [ "$1" = "--" ] && shift
	_out=$("$@" 2>&1)
	_rc=$?
	if [ "$_st_how" = run ] && [ "$_rc" -ge 2 ]; then
		printf '  %-52s %s\n' "$_name" \
			"FAIL < (exit $_rc = harness error; nothing was checked)"
		FAIL=$((FAIL + 1))
		_st_said_text "$_out"
		return 0
	fi
	if [ "$_st_how" = refuse ] && [ "$_rc" -ne 2 ]; then
		printf '  %-52s %s\n' "$_name" "FAIL < (exit $_rc; it must refuse with 2)"
		FAIL=$((FAIL + 1))
		_st_said_text "$_out"
		return 0
	fi
	# `--` before the pattern, because a pattern is data and grep would read a
	# leading dash as an option. Found by an arm asserting on the text
	# "--units must be a positive integer": the runner printed exactly that,
	# grep took it for a flag, and the arm reported the message missing.
	if printf '%s' "$_out" | grep -qF -- "$_pat"; then
		_st_said_it=said
	else
		_st_said_it=quiet
	fi
	if [ "$_st_said_it" = "$_st_pat_is" ]; then
		printf '  %-52s %s\n' "$_name" "ok ($_st_ok)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_name" "FAIL < ($_st_bad)"
		FAIL=$((FAIL + 1))
		_st_said_text "$_out"
	fi
}

# A SAVED RUN OF THE CONVENTIONS CHECK. The conventions sections ask one run
# of tools/conventions.sh about one toy tree, many arms over the same run, so
# each run is made once and saved to a file under $WORK. The file holds the
# run's words and not its exit status, and want_out and want_broken_none
# fail an arm only on a status of 2 or more: read with cat, grep or sed, a
# run that stopped before its verdict line (a refusal at start-up, a `set -u`
# trap halfway) said nothing, which every arm asking what it must not say
# then passed. So a saved run is read through these three, which take its
# status back from that line:
#
#   cv_saved FILE [CMD ARGS...]  prints FILE, or what `CMD ARGS... FILE`
#     prints of it (grep -A N -F -- PAT, sed -n RANGE, ...), and returns 1
#     for a run that ended `conventions: FAIL`, 0 for one that ended
#     `conventions: OK`, and 2, saying so on stderr, for one with neither;
#   cv_block FILE HEADLINE  the report of the rule whose FAIL line holds
#     HEADLINE, alone, with the run's status. The headline reaches awk
#     through its environment, so a backslash in it is matched as written;
#   cvi_rule TOY HEADLINE  cv_block over "$WORK/TOY.out", where a section
#     saves each toy tree's run under the toy's name.
#
# A run that stopped before its verdict line says nothing about a rule, so
# it is a harness error (2) through these, never a quiet pass for the
# absence arms. tools/conventions.sh reports a reader of a saved run that is
# none of them, a run piped into another command, and a copy of cv_block's
# awk.
cv_saved() {
	if grep -q '^conventions: FAIL' "$1"; then
		_cvs_rc=1
	elif grep -q '^conventions: OK' "$1"; then
		_cvs_rc=0
	else
		_cvs_rc=2
		printf 'cv_saved: %s holds no verdict line: the run stopped before its end\n' \
			"$(_st_unrooted "$1")" >&2
	fi
	_cvs_f=$1
	if [ "$#" -gt 1 ]; then
		shift
		"$@" "$_cvs_f"
	else
		cat "$_cvs_f"
	fi
	return "$_cvs_rc"
}
cv_block() {
	cv_saved "$1" env CV_BLOCK_HEAD="$2" \
		awk '/^  FAIL: / { on = index($0, ENVIRON["CV_BLOCK_HEAD"]) > 0 } on'
}
cvi_rule() { cv_block "$WORK/$1.out" "$2"; }
# cv_require NAME -- the require() every script carries, its message naming
# NAME, for a toy tree's script: tools/conventions.sh holds each copy to it,
# so a no-op stand-in, `require() { :; }`, is a copy it reports.
cv_require() {
	printf '%s\n' 'require() {' '	for _t in "$@"; do' \
		'		command -v "$_t" > /dev/null 2>&1 && continue' \
		"		echo \"$1: required command '\$_t' is not on PATH\" >&2" \
		'		exit 2' '	done' '}'
}

# ARMS THAT WAIT. Some arms can only be asked by waiting: a runner stopping a
# program that never ends does so at a time limit, and one killed by SIGTERM
# has to be running first. Asked in line, they cost the whole file the sum of
# their waits -- some forty seconds, which under a loaded machine is the
# difference between this target finishing and timing out. So they are
# DEFERRED: each starts in the background where it is written, beside its
# runner's other arms, and its verdict is collected just before the summary,
# having waited while everything after it ran. Fixtures a deferred arm reads
# must not be rewritten further down the file. Under selftest.sh's SHARDS a
# deferred arm is an arm like any other: only the shard that owns its
# section starts it.
LATER="$WORK/later"
mkdir -p "$LATER"
LATER_N=0

# later_status NAME STATUS PATTERN -- COMMAND...: exit STATUS, and PATTERN in
# the output, in one run. later_red_out is the common case, status 1.
later_status() {
	[ "${_st_mine:-1}" = 1 ] || return 0
	_name="$1"; _want="$2"; _pat="$3"; shift 3; [ "$1" = "--" ] && shift
	LATER_N=$((LATER_N + 1))
	_l="$LATER/$LATER_N"
	printf '%s\n' "status" "$_name" "$_want" "$_pat" > "$_l.arm"
	{ "$@" > "$_l.out" 2>&1; echo "$?" > "$_l.rc"; } &
}
later_red_out() {
	_ro_name="$1"; _ro_pat="$2"; shift 2; [ "$1" = "--" ] && shift
	later_status "$_ro_name" 1 "$_ro_pat" -- "$@"
}
# later_red_none NAME PATTERN -- COMMAND...: exit 1, and PATTERN nowhere in
# the output -- what a deferred arm must not say, as want_broken_none asks
# of one in line (V84: a stop between cases that said every case before it
# "ended within its own limit" under one that had not).
later_red_none() {
	[ "${_st_mine:-1}" = 1 ] || return 0
	_name="$1"; _pat="$2"; shift 2; [ "$1" = "--" ] && shift
	LATER_N=$((LATER_N + 1))
	_l="$LATER/$LATER_N"
	printf '%s\n' "none" "$_name" "1" "$_pat" > "$_l.arm"
	{ "$@" > "$_l.out" 2>&1; echo "$?" > "$_l.rc"; } &
}

# later_term NAME -- COMMAND...: the runner is stopped by SIGTERM part way
# through, the way Bazel stops a test that runs out of time, and must then END
# -- with 143, the status a death by SIGTERM reports -- having removed its
# scratch files. A trap that only cleaned up RESUMED the script: it went on
# without its files ("Directory nonexistent") and exited 1 or 0. The command
# runs with TMPDIR pointed at a directory of its own, so "removed its scratch
# files" is "left that directory empty".
later_term() {
	[ "${_st_mine:-1}" = 1 ] || return 0
	_name="$1"; shift; [ "$1" = "--" ] && shift
	LATER_N=$((LATER_N + 1))
	_l="$LATER/$LATER_N"
	mkdir -p "$_l.tmp"
	printf '%s\n' "term" "$_name" > "$_l.arm"
	{
		TMPDIR="$_l.tmp" "$@" > "$_l.out" 2>&1 &
		_pid=$!
		sleep 2
		kill -TERM "$_pid" 2> /dev/null
		wait "$_pid"
		echo "$?" > "$_l.rc"
	} &
}

# later_collect: wait for every deferred arm, and judge each in the order they
# were written.
later_collect() {
	wait
	_i=0
	while [ "$_i" -lt "$LATER_N" ]; do
		_i=$((_i + 1))
		_l="$LATER/$_i"
		_kind=$(sed -n 1p "$_l.arm")
		_name=$(sed -n 2p "$_l.arm")
		_rc=$(cat "$_l.rc" 2> /dev/null)
		[ -n "$_rc" ] || _rc=none
		if [ "$_kind" = term ]; then
			_left=$(find "$_l.tmp" -mindepth 1 2> /dev/null | awk 'END { print NR }')
			if [ "$_rc" != 143 ]; then
				printf '  %-52s %s\n' "$_name" "FAIL < (exit $_rc after SIGTERM; it must end with 143)"
				FAIL=$((FAIL + 1))
				_st_said "$_l.out"
			elif [ "$_left" -ne 0 ]; then
				printf '  %-52s %s\n' "$_name" "FAIL < (ended, but left $_left scratch file(s) behind)"
				FAIL=$((FAIL + 1))
				_st_said "$_l.out"
			elif grep -qE 'nonexistent|No such file' "$_l.out"; then
				printf '  %-52s %s\n' "$_name" "FAIL < (carried on without its scratch files first)"
				FAIL=$((FAIL + 1))
				_st_said "$_l.out"
			else
				printf '  %-52s %s\n' "$_name" "ok (stopped, cleaned up, 143)"
				PASS=$((PASS + 1))
			fi
			continue
		fi
		_want=$(sed -n 3p "$_l.arm")
		_pat=$(sed -n 4p "$_l.arm")
		if [ "$_rc" != "$_want" ]; then
			printf '  %-52s %s\n' "$_name" "FAIL < (exit $_rc; it must be $_want)"
			FAIL=$((FAIL + 1))
			_st_said "$_l.out"
		elif [ "$_kind" = none ]; then
			if grep -qF -- "$_pat" "$_l.out"; then
				printf '  %-52s %s\n' "$_name" "FAIL < (exit $_want, but said '$_pat'; it must not)"
				FAIL=$((FAIL + 1))
				_st_said "$_l.out"
			else
				printf '  %-52s %s\n' "$_name" "ok (exit $_want, and stayed quiet)"
				PASS=$((PASS + 1))
			fi
		elif grep -qF -- "$_pat" "$_l.out"; then
			printf '  %-52s %s\n' "$_name" "ok (exit $_want, and explained itself)"
			PASS=$((PASS + 1))
		else
			printf '  %-52s %s\n' "$_name" "FAIL < (exit $_want, but never said '$_pat')"
			FAIL=$((FAIL + 1))
			_st_said "$_l.out"
		fi
	done
}

# with_kind KIND CMD...: CMD under RL_UNIT_KIND=KIND, in a subshell so that
# nothing after it sees the setting. CMD may be a function of any file the
# driver runs, a section's as well as its own.
with_kind() {
	(
		RL_UNIT_KIND=$1
		export RL_UNIT_KIND
		shift
		"$@"
	)
}

# st_oracle FILE -- FILE, a stand-in reference that prints the rows it is
# handed on stdin, each as it came: a script holding them in a quoted
# here-document, made runnable. The corpus runners read a reference's
# rows from its stdout, so an arm feeds one its corpus this way:
#   { rows...; } | st_oracle "$WORK/<tree>/oracle.sh"
# //tools:conventions reports the here-document's opening written anywhere
# else, as each arm once wrote it out for itself.
st_oracle() {
	{
		printf '#!/bin/sh\ncat <<%sEOF%s\n' "'" "'"
		cat
		printf 'EOF\n'
	} > "$1"
	chmod +x "$1"
}

# WHICH SHELL INTERPRETS THE RUNNERS.
#
# Every arm launches a runner through "$SH" rather than a literal `sh`, so
# the whole driver can be replayed under a different shell. That is the
# point: this repo does NOT pin /bin/sh, and the reason it does not need to is
# that the runners are shell-agnostic -- which is a claim, and a claim about
# behaviour has to be executed rather than asserted.
#
# A comment must not START with the word shellcheck -- that is how a directive
# is spelled, and the linter then fails to parse this paragraph. Said the other
# way round: static linting already refuses a bashism (SC3xxx, at warning level,
# in //tools:conventions). This is the other half: dash and bash disagree about
# things no linter reads, `echo` with escapes being the classic one, and the
# only way to know is to run everything twice.
#
# //tools/tests:selftest_bash is the second run. If the shell named here is not
# installed, that is a SKIP rather than a pass.
#
# st_shell_guard -- sets SH, from SELFTEST_SH, and ends the run when that
# shell is not installed: a SKIP, or exit 2 under NO_SKIP=1. Then, on a
# machine without the test locale, a shell that warns of it on every run
# would put the warning in what the arms read, so the replay runs under C
# there, said in one line (tools/tests/selftest_locale.sh).
st_shell_guard() {
	SH=${SELFTEST_SH:-sh}
	if [ "$SH" != "sh" ] && ! command -v "$SH" > /dev/null 2>&1; then
		[ "${NO_SKIP:-0}" != "1" ] || {
			echo "selftest: SELFTEST_SH=$SH is not installed and NO_SKIP=1 is set," >&2
			echo "          so nothing was checked under it." >&2
			exit 2
		}
		echo "selftest: SKIP — SELFTEST_SH=$SH is not installed on this machine."
		exit 0
	fi
	# shellcheck source=tools/tests/selftest_locale.sh
	. "$TOOLS/tests/selftest_locale.sh"
	st_locale "$SH"
}

# THE COMPILER EVERY FIXTURE IS BUILT WITH: the pinned clang-12, linking with
# the pinned ld.bfd -- what Bazel hands every layer -- never the box's. It
# was `cc` from PATH (SELFTEST_CC's default), so the programs the arms feed
# the runners, and the stand-ins they read, were whatever this machine's
# compiler made of them -- the only arms in the repo that prove the valgrind
# layer can still SEE a leak among them -- and a box with no `cc` skipped
# them all (TO VERIFY V28). The runners' own helpers prove the pair
# (tools/runner_lib.sh: rl_cc_pin, rl_ld_pin) and make them one command, $CC
# (rl_cc_wrap), handed to every arm that builds or that drives a runner with
# a compiler by hand. A pair that fails a proof is exit 2: no arm could have
# checked anything.
#
# st_pin_cc CLANG LIB_FILES -- that proof, over the clang-12 and the
# libraries it loads (one a line) that the driver was handed, with LD and
# LD_LIB; it sets CC.
st_pin_cc() {
	mkdir -p "$WORK/pcc" || exit 2
	# shellcheck disable=SC2016 # the script is for the inner shell to expand
	"$SH" -c 'RL_NAME=$8; . "$1"; rl_cc_pin "$2" "$3" "$2"; rl_ld_pin "$2" "$4" "$5" "$6"; rl_cc_wrap "$2" "$3" "$6" "$7"' \
		_ "$TOOLS/runner_lib.sh" "$1" "$2" "$LD" "$LD_LIB" "$WORK/pcc/ld" "$WORK/pcc/cc" "$ST_NAME" \
		> "$WORK/pcc.err" 2>&1 || {
		echo "$ST_NAME: the pinned clang-12 and ld.bfd failed the runners' own proofs:" >&2
		cat "$WORK/pcc.err" >&2
		exit 2
	}
	# shellcheck disable=SC2034 # read by the driver and its sections
	CC="$WORK/pcc/cc"
}

# A TOY THAT DID NOT BUILD (TO VERIFY V287). Every toy in both drivers was
# once built with its compiler's words sent to /dev/null and its result
# never looked at, so one that did not build turned its arms into tests of
# a missing file. A runner that calls a --bin it cannot run a red
# (rush02_check.sh, bsq_check.sh) passed every want_red arm over it, a
# want_broken_none arm stayed quiet on the refusal, a missing cpu_spin
# skipped the busy-CPU block under a reason that was not true, and a gate
# program that did not build stood its gate down as a red fixture would. So
# each toy is built by toy_cc, which says when one did not build, as a FAIL
# of its own with the compiler's words under it (_st_said), and prints
# nothing when it did, so the count of a good run does not move. A FAIL in
# the plain code of a section another shard owns is undone with the rest of
# that section's tally (selftest.sh, _st_section). //tools:conventions
# refuses a toy built any other way ("builds a toy without toy_cc").
#
# toy_cc [--cc COMPILER] OUT CC-ARGS... -- "$CC" CC-ARGS -o OUT, or
# COMPILER for a toy another compiler builds (the pinned gcc's object, in
# harness memory placement); 0 when OUT was built, and 1 and a FAIL line
# when it was not.
toy_cc() {
	_tc_cc=$CC
	if [ "$1" = --cc ]; then
		_tc_cc=$2
		shift 2
	fi
	_tc_out=$1
	shift
	_tc_err=$(mktemp "$WORK/toycc.XXXXXX") || _tc_err=/dev/null
	rm -f "$_tc_out"
	"$_tc_cc" "$@" -o "$_tc_out" > "$_tc_err" 2>&1
	_tc_rc=$?
	if [ "$_tc_rc" -eq 0 ] && [ -s "$_tc_out" ]; then
		[ "$_tc_err" = /dev/null ] || rm -f "$_tc_err"
		return 0
	fi
	printf '  %-52s %s\n' "toy ${_tc_out#"$WORK"/}" \
		"FAIL < (the toy did not build: the compiler's exit $_tc_rc)"
	FAIL=$((FAIL + 1))
	_st_said "$_tc_err"
	[ "$_tc_err" = /dev/null ] || rm -f "$_tc_err"
	return 1
}
# Proven on invented toys, in a subshell with a tally of its own: one that
# is not C is one FAIL line with the compiler's error under it, one that
# builds prints nothing and counts nothing, and the good one handed to a
# --cc that refuses is that compiler's FAIL, in its words. Each driver asks
# it once, as an arm of its own:
#   want_green "<its arm's name>" -- toy_cc_meta
toy_cc_meta() {
	_tm=$(mktemp "$WORK/toycc_meta.XXXXXX") || return 2
	mkdir -p "$WORK/toycc"
	printf 'int main(void){ this is not C }\n' > "$WORK/toycc/bad.c"
	printf 'int main(void){ return (0); }\n' > "$WORK/toycc/good.c"
	printf '#!/bin/sh\necho "toycc-other: refused" >&2\nexit 3\n' > "$WORK/toycc/other"
	chmod +x "$WORK/toycc/other"
	(
		PASS=0
		FAIL=0
		toy_cc "$WORK/toycc/bad" -w "$WORK/toycc/bad.c"
		echo "after bad: status $? FAIL $FAIL PASS $PASS"
		toy_cc "$WORK/toycc/good" -w "$WORK/toycc/good.c"
		echo "after good: status $? FAIL $FAIL PASS $PASS"
		toy_cc --cc "$WORK/toycc/other" "$WORK/toycc/viaother" -w "$WORK/toycc/good.c"
		echo "after other: status $? FAIL $FAIL PASS $PASS"
	) > "$_tm" 2>&1
	_tm_rc=0
	if [ "$(grep -c 'FAIL < (the toy did not build' "$_tm")" != 2 ] ||
		! grep -q '^  toy toycc/bad  *FAIL < (the toy did not build' "$_tm"; then
		echo "not one FAIL line naming toycc/bad, and one more"
		_tm_rc=1
	fi
	if ! grep -q "^  toy toycc/viaother  *FAIL < (the toy did not build: the compiler's exit 3)" "$_tm" ||
		! grep -q '^      | toycc-other: refused' "$_tm"; then
		echo "the toy handed to --cc was not that compiler's FAIL, in its words"
		_tm_rc=1
	fi
	grep -qx 'after other: status 1 FAIL 2 PASS 0' "$_tm" || {
		echo "the toy handed to --cc was not status 1 and a second FAIL"
		_tm_rc=1
	}
	if ! awk 'prev { if ($0 ~ /^      \| .*error/) ok = 1; prev = 0 }
		/FAIL < \(the toy did not build/ { prev = 1 } END { exit !ok }' "$_tm"; then
		echo "no line of the compiler's error under the FAIL line"
		_tm_rc=1
	fi
	grep -qx 'after bad: status 1 FAIL 1 PASS 0' "$_tm" || {
		echo "the toy that is not C was not status 1 and one FAIL"
		_tm_rc=1
	}
	grep -qx 'after good: status 0 FAIL 1 PASS 0' "$_tm" || {
		echo "the toy that builds was not status 0, or it counted"
		_tm_rc=1
	}
	[ "$_tm_rc" = 0 ] || cat "$_tm"
	rm -f "$_tm"
	return "$_tm_rc"
}

# A BLOCK OF ARMS THIS RUN CANNOT MAKE. Where an input a driver is handed
# (an oracle, a pinned zig, a fixture's stand-ins) was not supplied, or the
# box lacks what a block needs (a sanitizer build, taskset), the block has
# nothing to run. A skip line says so, and NO_SKIP=1, which asks that
# nothing go unchecked, turns it into a refusal, exit 2: a forced run must
# not pass with arms that never ran. Six blocks once wrote that guard by
# hand, and the busy-CPU block's skip had none, so a forced run on a box
# without taskset passed with twelve arms unrun (//tools:conventions,
# "prints a skip line by hand").
#
# st_skipped NAME VERDICT -- the line of an arm that did not run, NAME and
# VERDICT ("skipped", "skipped (why)", "not run here (why)") in an arm's
# columns. Alone where the box decides and NO_SKIP=1 cannot help (no
# /usr/bin/ar here), or where NO_SKIP=1 was refused already, once, before
# the first section (the sanitizer probe, selftest.sh); through
# st_unsupplied where the run's input does.
st_skipped() { printf '  %-52s %s\n' "$1" "$2"; }
# st_unsupplied NAME VERDICT LINE... -- st_skipped's line; under NO_SKIP=1,
# st_no_skip's refusal in LINE... instead.
st_unsupplied() {
	_sun_name=$1
	_sun_verdict=$2
	shift 2
	st_no_skip "$@"
	st_skipped "$_sun_name" "$_sun_verdict"
}
# st_no_skip LINE... -- under NO_SKIP=1, LINE... on stderr, the first after
# "NO_SKIP set: " and the rest under it, and exit 2; otherwise nothing. Alone
# where the skip lines are later sections' (the sanitizer probe, selftest.sh).
st_no_skip() {
	[ "${NO_SKIP:-0}" = 1 ] || return 0
	_sun_pre="NO_SKIP set: "
	for _sun_l in "$@"; do
		printf '%s%s\n' "$_sun_pre" "$_sun_l" >&2
		_sun_pre="             "
	done
	exit 2
}

# WHAT A FAILED ARM SAID, PROVEN (TO VERIFY V172). On a toy that refuses as a
# runner does, each helper above run in a subshell so its tally is not the
# driver's: each shows the toy's words under its FAIL line, want_green calls
# the refusal a harness error and not a red, and want_red shows what a run
# that passed when it must not said, too. Every helper is asked, and each is
# judged on its own line: a count of the toy's words over the whole log let
# one helper that printed them twice hide another that printed nothing
# (st_said_each). Each driver asks it once, as an arm of its own:
#   want_green "<its arm's name>" -- st_said_meta
st_said_toy() { sh -c 'echo "selftest-toy: unknown option" >&2; exit 2'; }
st_said_passes() { sh -c 'echo "selftest-toy: it passed"'; }
# st_said_each LOG NAME... -- the NAMEs whose FAIL line in LOG is missing,
# or is not followed at once by a line of the toy's words.
st_said_each() {
	_se_log=$1
	shift
	awk -v want="$*" '
		BEGIN { n = split(want, w, " ") }
		prev != "" { if (index($0, "| selftest-toy") > 0) ok[prev] = 1; prev = "" }
		$1 ~ /^toy-/ && index($0, "FAIL <") > 0 { prev = $1 }
		END { for (i = 1; i <= n; i++) if (!(w[i] in ok)) printf "%s ", w[i] }
	' "$_se_log"
}
st_said_meta() {
	_sm=$(mktemp "$WORK/said_meta.XXXXXX") || return 2
	(
		# shellcheck disable=SC2034 # counted by the want_* helpers (above)
		PASS=0
		# shellcheck disable=SC2034 # counted by the want_* helpers (above)
		FAIL=0
		# shellcheck disable=SC2034 # read by the later_* helpers (above)
		LATER=$(mktemp -d "$WORK/said_later.XXXXXX") || exit 2
		# shellcheck disable=SC2034 # read by the later_* helpers (above)
		LATER_N=0
		want_red   "toy-red" -- st_said_toy
		want_green "toy-green" -- st_said_toy
		want_out   "toy-out" 'never printed' -- st_said_toy
		want_broken "toy-broken" 'never printed' -- st_said_toy
		want_broken_none "toy-none" 'never printed' -- st_said_toy
		want_broken_without "toy-without" 'selftest-toy' -- st_said_toy
		later_red_out "toy-later" 'never printed' -- st_said_toy
		later_term "toy-term" -- st_said_toy
		later_collect
		want_red   "toy-passes" -- st_said_passes
	) > "$_sm" 2>&1
	_sm_miss=$(st_said_each "$_sm" toy-red toy-green toy-out toy-broken toy-none \
		toy-without toy-later toy-term toy-passes)
	_sm_rc=0
	if [ -n "$_sm_miss" ]; then
		echo "no words under the FAIL line of: $_sm_miss"
		_sm_rc=1
	fi
	if ! grep 'toy-green' "$_sm" | grep -qF 'harness error'; then
		echo "want_green did not call exit 2 a harness error"
		_sm_rc=1
	fi
	if ! grep -qF 'selftest-toy: it passed' "$_sm"; then
		echo "want_red did not show what a run that passed said"
		_sm_rc=1
	fi
	[ "$_sm_rc" = 0 ] || cat "$_sm"
	rm -f "$_sm"
	return "$_sm_rc"
}
