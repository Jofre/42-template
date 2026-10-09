#!/bin/sh
# prime.sh — do all the slow, once-per-machine work now, instead of in the
# middle of checking an exercise.
#
#     bazel run //tools:prime
#
# WHY THIS EXISTS. Nothing here is downloaded or built until something needs it,
# so on a fresh machine the FIRST `bazel test` pays for the whole toolchain at
# once: the pinned Bazel, then every external repo (measured at 2.1 GB in the
# repository cache), then the Rust oracle and every test binary. That is a long
# quiet wait arriving at the least convenient moment -- and the usual response
# to it is to assume something has hung.
#
# The cost does not go away. This makes it SCHEDULABLE: start it, walk away,
# come back to a machine where `bazel test //c-piscine/c-piscine-c-00:basic` takes
# seconds.
#
# It matters MORE as this repo gets more hermetic, not less. Every tool pinned
# instead of taken from the host is another thing on that first fetch, so the
# honest effect of finishing the hermeticity work is a worse first run unless
# this exists.
#
# WHY NOT JUST `bazel test //...`. That would also RUN every test in the repo
# (over 1 600 of them), which on
# a fresh clone reports a screen of reds that are entirely expected -- every
# unwritten exercise -- and takes far longer. Priming is about having the inputs
# ready, not about learning anything. `bazel fetch` and `bazel build` are the
# right primitives.

#
# --background: fire once per machine from a shell profile, without ever making
# the student wait. See WHY THIS DOES NOT BLOCK YOU below.

set -eu

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "prime.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
# conventions: optional nice -- priming stops yielding CPU to the interactive
# conventions: optional ionice -- priming stops yielding DISK to the interactive
# session. Both are courtesy, not correctness: without them the prime still
# produces exactly the same cache, it just competes for the machine instead of
# waiting for it. A script wired into a login shell must never refuse to run.
# sed and tail are tools/drives.sh's, for reading the rc files; see its header.
require cat dirname find id mkdir rm rmdir

WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$WS" || { echo "prime.sh: cannot enter '$WS'" >&2; exit 1; }

# WHERE THIS MACHINE'S BUILD STATE LIVES has one answer, and setup.sh already
# made it: it probes four candidates for writability and records the winner in
# .bazelrc.local. This used to guess again from three UNPROBED ones, so the two
# could disagree -- and they disagree exactly when setup.sh had a reason to move.
# A box with a /goinfre that exists and is not writable, or a /tmp too small for
# 8.9 GB, gets $HOME/.cache/42-piscine from setup.sh and /goinfre or /tmp from
# here. Then this writes its own output base and disk cache -- gigabytes -- to a
# directory setup.sh REJECTED, the sentinel lands somewhere the interactive
# build never looks, and the priming it did warms a cache nothing reads.
#
# So: read what setup.sh recorded, and guess only when there is nothing to read.
# The read must accept any output_user_root line, not just the one setup.sh
# writes -- .bazelrc.local is explicitly "yours to edit", and setup.sh leaves a
# hand-written one alone. It is tools/drives.sh's read of every rc file, the
# one the wrapper makes, rather than a sed of this script's own that knew only
# the `=` spelling and only .bazelrc.local: a root ~/.bazelrc sets wins over
# that file, and is where Bazel's state then actually is.
#
# C_PISCINE_SCRATCH still overrules both, on the same terms as in setup.sh: you
# said so. //tools/tests:selftest also needs it, being unable to write outside
# its sandbox. An absolute one only, as there: a relative path is a different
# directory for every shell that starts in a different folder. setup.sh refuses
# one; this script, which must never refuse, passes over it.
#
# Without tools/drives.sh -- an incomplete checkout -- this still runs, in
# /tmp/$USER: a script wired into a login shell must never refuse.
HAVE_DRIVES=0
if [ -r "$WS/tools/drives.sh" ]; then
	# shellcheck source=drives.sh
	. "$WS/tools/drives.sh"
	HAVE_DRIVES=1
fi
RC_ROOT=""
[ "$HAVE_DRIVES" = 0 ] || RC_ROOT=$(drives_rc_root "$WS")
case "${C_PISCINE_SCRATCH:-}" in
	/*) SCRATCH="$C_PISCINE_SCRATCH" ;;
	*)
		SCRATCH=${RC_ROOT%/bazel}
		# Nothing recorded: this checkout never ran setup.sh. The choice
		# setup.sh WOULD make, from the same list -- which is also the root
		# tools/bazel gives such a checkout, so the two cannot disagree.
		# A relative C_PISCINE_SCRATCH is passed over here too, not only
		# above: drives_choose would refuse it, and this would land in
		# /tmp/$USER when the list has a better place.
		if [ -z "$SCRATCH" ] && [ "$HAVE_DRIVES" = 1 ]; then
			SCRATCH=$(
				C_PISCINE_SCRATCH=""
				drives_choose && printf '%s' "$DRIVES_SCRATCH"
			)
		fi
		[ -n "$SCRATCH" ] || SCRATCH="/tmp/${USER:-$(id -un)}"
		;;
esac

# AND THE ROOT, passed explicitly on every command below rather than left to
# tools/bazel. A `bazel` typed at a prompt goes through that wrapper, which
# supplies a per-user root when no rc file names one. This script does not
# always: under `bazel run //tools:prime` bazelisk has set
# BAZELISK_SKIP_WRAPPER for everything below it, and this script prefers
# bazelisk -- so without the flag the prime would fall back to Bazel's own
# ~/.cache/bazel, and its 2.1 GB of downloads would land in a repository cache
# the interactive build never reads: on campus, inside the quota'd $HOME. The
# same root the wrapper would pick (drives_default_root), so the two agree.
#
# ONLY when no rc file names one. Bazel reads an rc file's root whoever starts
# it, and the same option arriving from the command line instead is a different
# startup command line: the server this `bazel run` left behind would be
# restarted for it.
ROOT_OPT=""
if [ "$HAVE_DRIVES" = 1 ] && [ -z "$RC_ROOT" ] && drives_default_root; then
	ROOT_OPT="--output_user_root=$DRIVES_ROOT"
fi

# THE TRACE: what the machine did while this primed, sampled into a file under
# $HOME as it went (tools/prime_trace.sh says why: a campus box froze during a
# prime, and nothing afterwards said what it had been doing). Every prime
# writes one, background or foreground. Without the file -- an incomplete
# checkout -- there is no trace, and the prime is the same.
HAVE_TRACE=0
if [ -r "$WS/tools/prime_trace.sh" ]; then
	# shellcheck source=prime_trace.sh
	. "$WS/tools/prime_trace.sh"
	HAVE_TRACE=1
fi

# ---------------------------------------------------------------------------
# THE BUDGET, shared by the background and the foreground paths.
#
# A QUARTER OF THE MACHINE, AS AN INTEGER, FLOOR OF TWO. `cpu=HOST_CPUS*.25`
# reads like the same thing and is not: Bazel charges an ordinary action 1.0
# CPU, so on a six-core box that budget is 1.5 and the build runs STRICTLY
# SERIAL. Measured: twelve independent actions reached max concurrency 1 on a
# 6-CPU host, and `cpu=1.5` took 39.2s against 5.0s for identical work. A
# fraction is the right idea and the wrong arithmetic -- it has to be rounded
# before Bazel sees it, and it must never round to one.
_cpus=$(nproc 2>/dev/null || echo 4)
_jobs=$((_cpus / 4))
[ "$_jobs" -ge 2 ] || _jobs=2
#
# --loading_phase_threads IS THE ONE THAT THROTTLES A FETCH, and the other two
# do not. `bazel fetch` DOES inherit .bazelrc's `build` lines -- measured with
# --announce_rc on the pinned 9.2.0: "Inherited 'build' options: ...
# --local_resources=cpu=HOST_CPUS-2" -- so an earlier comment here claiming the
# fetch escaped the repo's CPU limit was simply wrong. The real reason a fetch
# ignores it is that REPOSITORY RULES ARE NOT BUILD ACTIONS: they are not
# scheduled against --jobs or --local_resources at all. Measured: 16 concurrent
# repository rules under every combination of those two, and 2 under
# --loading_phase_threads=2.
BUDGET="--jobs=$_jobs --local_resources=cpu=$_jobs --loading_phase_threads=$_jobs"

# YIELD, rather than compete. A background build at normal priority contends on
# equal terms with the person at the keyboard, and what a person feels is I/O:
# a process can sit at nice 19 and still saturate the disk queue, which is what
# `ionice -c 3` (idle class) exists for. Both are PROBED and optional -- missing
# either degrades the courtesy, not the result, and a script wired into a login
# shell must never refuse to run over a tool it merely prefers.
NICE=""
command -v nice > /dev/null 2>&1 && NICE="nice -n 19"
command -v ionice > /dev/null 2>&1 && NICE="$NICE ionice -c 3"

# ---------------------------------------------------------------------------
# WHY THIS DOES NOT BLOCK YOU, which is the whole difficulty with priming from a
# shell profile.
#
# Bazel takes an EXCLUSIVE lock per output base. A background `bazel build`
# holding that lock means the first thing the student types -- `bazel test
# //c-piscine/c-piscine-c-00:basic` -- sits there waiting on it, silently, which is a
# worse version of the problem priming exists to solve. "Bazel hangs" is
# precisely what it would look like.
#
# The fix is that the EXPENSIVE part is not the output base. Measured: the
# repository cache is 2.1 GB and lives at $output_user_root/cache/repos/v1 --
# a SIBLING of the output bases, shared by every one of them. So the background
# run gets its own --output_base and contends with nothing, while everything it
# downloads lands in the cache the interactive build will read.
#
# The COMPILING travels by a second route, and that route was broken. Compiled
# actions reach the interactive build only through a --disk_cache that BOTH
# passes -- and for a long time only this script passed it. It filled a cache
# nothing read, so the entire `build //...` half below was discarded and the
# first interactive `bazel test` compiled all of it again. This comment used to
# claim the opposite. tools/setup.sh now writes the matching `build
# --disk_cache=` into .bazelrc.local, bounded at 4G, and appends it to installs
# that predate the line.
#
# Once per MACHINE, not once per shell: the sentinel lives in scratch, which is
# wiped with /tmp or /goinfre, so a new machine primes again and a new terminal
# does not. The lock directory is mkdir, which is atomic -- ten terminals opened
# at once start one prime between them.
if [ "${1:-}" = "--background" ]; then
	# `[ -e X ] && exit 0` would be wrong here, and the selftest caught it: under
	# `set -e` a leading test that FAILS makes the whole and-list the statement's
	# status, so the common case -- not yet primed -- exited 1. Harmless where
	# the profile calls this, but a script wired into shell startup has no
	# business ever returning failure. An `if` says what is meant.
	if [ -e "$SCRATCH/.prime.done" ]; then exit 0; fi
	# A PRIME THAT STOPPED WITH THE MACHINE is not started again by itself: a
	# box that froze while it primed at login would freeze again at every
	# login. Its trace -- this machine's newest, with no END and a boot before
	# this one -- is the evidence the freeze left, so this says where it is
	# and how to go on. A prime run by hand writes a newer trace, which lifts
	# this; so does deleting the file. Another machine's traces, which $HOME
	# brings along on campus, are in folders of their own and stop nothing.
	if [ "$HAVE_TRACE" = 1 ]; then
		_last=$(trace_newest)
		if [ -n "$_last" ] && trace_froze "$_last"; then
			printf 'c-piscine: the last prime did not finish, and this machine has restarted\n' >&2
			printf '           since: if it froze, the prime may be why, so it does not start again\n' >&2
			printf '           by itself. What the machine was doing is in %s.\n' "$_last" >&2
			printf '           To put it in a report:  cd %s && sh tools/env-audit.sh\n' "$WS" >&2
			printf '           To prime anyway:        cd %s && bazel run //tools:prime\n' "$WS" >&2
			exit 0
		fi
	fi
	mkdir -p "$SCRATCH" 2>/dev/null || exit 0
	# A lock LEFT BEHIND is not a lock held. The cleanup below runs in a
	# backgrounded subshell, so a closed terminal, a reboot or the OOM killer
	# leaves the directory there -- and this used to read that as "someone else
	# has it" and exit 0 forever after. The result is silent: priming simply
	# never happens again on that machine, and the only symptom is that the
	# first build a student runs is the slow one this script exists to avoid.
	#
	# A lock older than six hours is stale by construction: the work it guards
	# is a fetch and a build, and neither takes that long even on a cold campus
	# box over a slow network.
	if [ -d "$SCRATCH/.prime.lock" ]; then
		if [ -z "$(find "$SCRATCH/.prime.lock" -maxdepth 0 -mmin +360 2>/dev/null)" ]; then
			exit 0                                    # someone else has it
		fi
		rmdir "$SCRATCH/.prime.lock" 2>/dev/null || true
	fi
	mkdir "$SCRATCH/.prime.lock" 2>/dev/null || exit 0   # lost a race; fine
	log="$SCRATCH/prime.log"
	printf 'c-piscine: warming the build cache in the background (log: %s)\n' "$log" >&2
	printf '           it will not block anything you type; first run only.\n' >&2
	# ------------------------------------------------------------------ budget
	#
	# THIS RUNS WHILE SOMEBODY IS USING THE MACHINE, which is the whole premise:
	# it is launched from a login shell so the student can walk away. On a campus
	# box that machine is also SHARED, and the failure reported from one was that
	# priming made it unusable -- not slow, unusable, down to a browser tab --
	# and stayed laggy after it finished. Three separate things caused that, and
	# all three are budget rather than logic.
	#
	# 1. IT OUTRANKED EVERYTHING. A background build at normal priority competes
	#    on equal terms with the interactive session, and the part a person
	#    actually feels is I/O, not CPU. `nice` alone does not fix that: a
	#    process can be at nice 19 and still saturate the disk queue. `ionice -c3`
	#    (idle class) is what makes the difference on a spinning or network-backed
	#    filer, which is what a campus $HOME usually is.
	#
	#    Both are PROBED, not required. nice is POSIX and effectively always
	#    there; ionice is util-linux and is not on every box. Missing either one
	#    degrades the courtesy, not the result, so this must never refuse to run
	#    over them -- the whole point of the script is to work unattended.
	#
	# 2. IT IGNORED THE REPO'S OWN CPU LIMIT. .bazelrc sets
	#    `build --local_resources=cpu=HOST_CPUS-2`, and `bazel fetch` DOES NOT
	#    INHERIT IT -- rc lines for `build` reach build/test/run/coverage, and
	#    fetch is its own command. So the fetch half ran unthrottled. Both halves
	#    now carry the budget explicitly.
	#
	#    HOST_CPUS-2 is also the wrong shape here even where it does apply: it
	#    reserves two cores of a machine this process does not own, and on a
	#    shared box HOST_CPUS counts everyone's cores. A FRACTION is the honest
	#    budget for work nobody is waiting on.
	#
	# 3. IT LEFT ITS SERVER RUNNING. Bazel does not exit when a command finishes
	#    -- .bazelrc's "WHAT ACTUALLY KEEPS THE BOX ALIVE" says so -- and this uses a
	#    SEPARATE --output_base, so the JVM it starts is one nothing else will
	#    ever reuse or shut down. It sat there until the default idle timeout,
	#    which is hours. It is now capped at five minutes AND shut down
	#    explicitly, whether the build succeeded or not.

	(
		BZ=$(command -v bazelisk 2>/dev/null || command -v bazel 2>/dev/null || true)
		# One place that knows how to invoke the prime server, so the budget and
		# the nice/ionice prefix cannot be applied to one half and forgotten on
		# the other -- which is exactly the bug this replaces, where `fetch` ran
		# unthrottled because the rc limit only reaches `build`.
		#
		# --max_idle_secs is a STARTUP option, so it goes before the command. It
		# is the backstop for the explicit shutdown below: if this subshell is
		# killed -- closed terminal, logout, OOM -- the server still goes away on
		# its own instead of outliving the session that started it.
		prime_bazel() {  # prime_bazel <bazel-command>
			# shellcheck disable=SC2086
			$NICE "$BZ" $ROOT_OPT --output_base="$SCRATCH/bazel-prime" --max_idle_secs=300 \
				"$1" //... --disk_cache="$SCRATCH/bazel-disk" $BUDGET
		}
		if [ -n "$BZ" ]; then
			# The trace ends with this subshell: on a signal too, with its
			# status, so that only a machine that stopped without warning
			# leaves a trace with no END.
			if [ "$HAVE_TRACE" = 1 ]; then
				trace_start "$WS/tools/prime_trace.sh" background "nproc $_cpus" \
					"budget $BUDGET" "base $SCRATCH/bazel-prime"
				trap 'trace_end 129; exit 129' HUP
				trap 'trace_end 143; exit 143' TERM
			fi
			_prc=0
			prime_bazel fetch > "$log" 2>&1 &&
			prime_bazel build >> "$log" 2>&1 &&
			: > "$SCRATCH/.prime.done" || _prc=$?
			# UNCONDITIONAL, and outside the && chain on purpose: a prime that
			# FAILED still started a server, and leaving that one behind is the
			# case that actually happened. `|| true` because a server that never
			# started is not an error to report from a login shell.
			# shellcheck disable=SC2086
			$NICE "$BZ" $ROOT_OPT --output_base="$SCRATCH/bazel-prime" shutdown >> "$log" 2>&1 || true
			# AND THROW THE TREE AWAY. Measured on a warm devcontainer: an
			# output base for this repo is 8.7-9.5 GB, while everything priming
			# exists to produce lives OUTSIDE it -- the 2.1 GB repository cache
			# is a sibling shared by every base, and the compiled actions went
			# to the disk cache above. So this directory is 9 GB of scratch that
			# has already handed over everything of value, on a machine whose
			# $HOME a 42 campus caps at 5 GB.
			#
			# After the shutdown, never before: removing an output base under a
			# live server is how you get a Bazel that reports impossible errors
			# until someone works out the tree moved beneath it.
			#
			# ONLY ON SUCCESS, and niced like everything else here. Both were
			# wrong in the first version: unconditional, it deleted the tree
			# after a FAILED prime too, so the next attempt rebuilt 9 GB from
			# nothing instead of resuming incrementally -- strictly worse than
			# leaving it. And un-niced it unlinks two million directory entries
			# (measured: 2,042,009) at normal I/O priority, which is precisely
			# the burst this script exists to keep off the interactive session.
			#
			# Two branches only so that `rm` sits in COMMAND POSITION.
			# //tools:conventions scans for that to keep the require list above
			# honest, and it cannot see a command hidden behind a variable
			# prefix -- and $NICE is legitimately empty on a box without nice.
			# Dropping `rm` from require to satisfy the scanner would be the
			# wrong repair: the call is real, so the declaration is right.
			if [ -e "$SCRATCH/.prime.done" ]; then
				if [ -n "$NICE" ]; then
					# shellcheck disable=SC2086
					$NICE rm -rf "$SCRATCH/bazel-prime" 2>/dev/null || true
				else
					rm -rf "$SCRATCH/bazel-prime" 2>/dev/null || true
				fi
			fi
			# After the delete, which is two million unlinks: heavy I/O
			# belongs inside what the trace watches.
			[ "$HAVE_TRACE" = 0 ] || trace_end "$_prc"
		fi
		rmdir "$SCRATCH/.prime.lock" 2>/dev/null || true
	) </dev/null > /dev/null 2>&1 &
	exit 0
fi

# Bazel is already running (it is running this), so re-entering it needs the
# launcher rather than the server we are inside. bazelisk is what setup.sh
# installs and what everything else calls; if a plain `bazel` is what is on
# PATH, that works too.
BAZEL=$(command -v bazelisk 2>/dev/null || command -v bazel 2>/dev/null || true)
[ -n "$BAZEL" ] || {
	echo "prime.sh: no bazelisk or bazel on PATH." >&2
	echo "          Run 'sh tools/setup.sh' first, then open a new shell." >&2
	exit 1
}

step() { printf '\n=== %s\n' "$*"; }

# The trace ends when this script does, with its status: a failed step, an
# interrupt or a closed terminal included.
if [ "$HAVE_TRACE" = 1 ]; then
	trace_start "$WS/tools/prime_trace.sh" foreground "nproc $_cpus" \
		"budget $BUDGET" "base this checkout's own"
	trap 'trace_end $?' EXIT
	trap 'exit 129' HUP
	trap 'exit 130' INT
	trap 'exit 143' TERM
fi

cat <<'INTRO'
prime: downloading and building everything this repo needs, once.

  Expect this to take a while and to be mostly silent network traffic --
  roughly 2 GB of archives on a cold machine, plus the Rust oracle build.
  It is safe to interrupt and re-run: everything below is cached and resumes.

INTRO

step "1/3  external repositories (compilers, zig, shellcheck, norminette, Rust)"
# `fetch` resolves and downloads every external repo the build references,
# without compiling anything. This is the 2.1 GB.
# shellcheck disable=SC2086
$NICE "$BAZEL" $ROOT_OPT fetch //... $BUDGET || {
	echo "prime: fetch failed -- almost always the network. Re-run when it is back." >&2
	exit 1
}

step "2/3  the Rust oracle (the reference the diff layers compare against)"
# Singled out because it is the longest single build here and the one whose
# absence is least obvious: without it every `diff` layer stalls on first use.
# shellcheck disable=SC2086
$NICE "$BAZEL" $ROOT_OPT build //oracle:oracle $BUDGET

step "3/3  every test binary"
# Builds without running. After this, a test is a comparison rather than a
# compile.
# shellcheck disable=SC2086
$NICE "$BAZEL" $ROOT_OPT build //... $BUDGET

cat <<'DONE'

prime: done. The cache is warm.

  Try it:  bazel test //c-piscine/c-piscine-c-00:basic

  Reds are the point -- every unwritten exercise is one, and turning them
  green is the work. What should NOT happen any more is a long wait first.
DONE
