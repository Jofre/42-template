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
# come back to a machine where `bazel test //c-piscine-c-00:basic` takes
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
require cat dirname find id mkdir rmdir sed tail

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
# hand-written one alone.
#
# C_PISCINE_SCRATCH still overrules both, on the same terms as in setup.sh: you
# said so. //tools/tests:selftest also needs it, being unable to write outside
# its sandbox.
if [ -n "${C_PISCINE_SCRATCH:-}" ]; then
	SCRATCH="$C_PISCINE_SCRATCH"
else
	SCRATCH=$(sed -n \
		's|^startup[[:blank:]]*--output_user_root=\([^[:blank:]]*\).*|\1|p' \
		"$WS/.bazelrc.local" 2> /dev/null | tail -n 1)
	SCRATCH=${SCRATCH%/bazel}
	if [ -z "$SCRATCH" ]; then
		if [ -d /goinfre ]; then SCRATCH="/goinfre/${USER:-$(id -un)}"
		else SCRATCH="/tmp/${USER:-$(id -un)}"; fi
	fi
fi

# ---------------------------------------------------------------------------
# WHY THIS DOES NOT BLOCK YOU, which is the whole difficulty with priming from a
# shell profile.
#
# Bazel takes an EXCLUSIVE lock per output base. A background `bazel build`
# holding that lock means the first thing the student types -- `bazel test
# //c-piscine-c-00:basic` -- sits there waiting on it, silently, which is a
# worse version of the problem priming exists to solve. "Bazel hangs" is
# precisely what it would look like.
#
# The fix is that the EXPENSIVE part is not the output base. Measured: the
# repository cache is 2.1 GB and lives at $output_user_root/cache/repos/v1 --
# a SIBLING of the output bases, shared by every one of them. So the background
# run gets its own --output_base and contends with nothing, while everything it
# downloads lands in the cache the interactive build will read. --disk_cache is
# shared for the same reason, so the compiling is not repeated either.
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
	(
		BZ=$(command -v bazelisk 2>/dev/null || command -v bazel 2>/dev/null || true)
		if [ -n "$BZ" ]; then
			"$BZ" --output_base="$SCRATCH/bazel-prime" fetch //... \
				--disk_cache="$SCRATCH/bazel-disk" >"$log" 2>&1 &&
			"$BZ" --output_base="$SCRATCH/bazel-prime" build //... \
				--disk_cache="$SCRATCH/bazel-disk" >>"$log" 2>&1 &&
			: > "$SCRATCH/.prime.done"
		fi
		rmdir "$SCRATCH/.prime.lock" 2>/dev/null || true
	) </dev/null >/dev/null 2>&1 &
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

cat <<'INTRO'
prime: downloading and building everything this repo needs, once.

  Expect this to take a while and to be mostly silent network traffic --
  roughly 2 GB of archives on a cold machine, plus the Rust oracle build.
  It is safe to interrupt and re-run: everything below is cached and resumes.

INTRO

step "1/3  external repositories (compilers, zig, shellcheck, norminette, Rust)"
# `fetch` resolves and downloads every external repo the build references,
# without compiling anything. This is the 2.1 GB.
"$BAZEL" fetch //... || {
	echo "prime: fetch failed -- almost always the network. Re-run when it is back." >&2
	exit 1
}

step "2/3  the Rust oracle (the reference the diff layers compare against)"
# Singled out because it is the longest single build here and the one whose
# absence is least obvious: without it every `diff` layer stalls on first use.
"$BAZEL" build //oracle:oracle

step "3/3  every test binary"
# Builds without running. After this, a test is a comparison rather than a
# compile.
"$BAZEL" build //...

cat <<'DONE'

prime: done. The cache is warm.

  Try it:  bazel test //c-piscine-c-00:basic

  Reds are the point -- every unwritten exercise is one, and turning them
  green is the work. What should NOT happen any more is a long wait first.
DONE
