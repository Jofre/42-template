# --------------------------------------------------------------------- prime
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# prime.sh --background is wired into the shell profile, which makes ONE
# property matter more than the rest: it must never break a login shell. If it
# can exit non-zero, or block, then every terminal opened on a machine where
# something is off greets the student with an error they cannot act on -- from
# a script whose whole purpose is convenience.
#
# So these run it in the hostile cases deliberately: with NO bazel anywhere on
# PATH, and twice in a row. Both must exit 0 and neither may hang.
mkdir -p "$WORK/pr/bin" "$WORK/pr/home"
# `cat` is in this list because prime.sh prints its two explanatory blocks with
# a heredoc, and it declares it. A tool the runner requires but the fixture PATH
# withholds makes the runner exit 2 -- which want_green reports as "red; it must
# not be", i.e. an arm failing for a reason that has nothing to do with what it
# tests. The list has to hold everything the runner declares, minus the one
# tool a given arm is deliberately hiding.
# sleep is the trace's (tools/prime_trace.sh): its sampler waits with it.
for _b in sh "$SH" env mkdir rmdir rm printf cat find id dirname pwd cd sed tail sleep; do
	_p=$(command -v "$_b" 2>/dev/null) && ln -sf "$_p" "$WORK/pr/bin/$_b" 2>/dev/null
done

pr_run() {
	# No `cd` here: $TOOLS is relative (it comes from --anchor), so changing
	# directory first would make "$TOOLS/prime.sh" unopenable -- which is exactly
	# what the first version of this arm did, and what want_green caught.
	env PATH="$WORK/pr/bin" USER=selftestprime HOME="$WORK/pr/home" \
		XDG_STATE_HOME="$WORK/pr/state" C_PISCINE_SCRATCH="$WORK/pr/scratch" \
		"$SH" "$TOOLS/prime.sh" --background >/dev/null 2>&1
}

want_green "prime: --background exits 0 with no bazel on PATH" -- pr_run
want_green "prime: --background is a no-op the second time" -- pr_run

# WHICH SCRATCH IT PICKS, which is a different question from whether it exits 0
# -- and the one that was wrong. setup.sh probes four candidates and records the
# winner in .bazelrc.local; prime.sh guessed again from three unprobed ones, so
# on any machine where setup.sh had a REASON to move (an unwritable /goinfre, a
# /tmp too small for a full run) the two disagreed and prime.sh wrote gigabytes to
# the directory setup.sh had rejected.
#
# The assertion is positive: the path prime.sh announces its log at IS the
# scratch it chose. C_PISCINE_SCRATCH is deliberately absent from this env --
# setting it would answer the question the arm is asking.
mkdir -p "$WORK/pr/ws/tools" "$WORK/pr/recorded"
# The workspace's tools/drives.sh, which prime.sh reads the recorded root with,
# and its tools/prime_trace.sh, which writes the trace.
cp "$TOOLS/drives.sh" "$WORK/pr/ws/tools/drives.sh"
cp "$TOOLS/prime_trace.sh" "$WORK/pr/ws/tools/prime_trace.sh"
printf 'startup --output_user_root=%s/bazel\n' "$WORK/pr/recorded" > "$WORK/pr/ws/.bazelrc.local"
pr_scratch() {
	env PATH="$WORK/pr/bin" USER=selftestprime HOME="$WORK/pr/home" \
		XDG_STATE_HOME="$WORK/pr/state" BUILD_WORKSPACE_DIRECTORY="$WORK/pr/ws" \
		"$SH" "$TOOLS/prime.sh" --background 2>&1
}
want_out "prime: uses the scratch setup.sh recorded" \
	"$WORK/pr/recorded/prime.log" -- pr_scratch

# Without tools/drives.sh, prime.sh names its scratch itself, and a user
# with no name (USER unset, a stand-in id that knows uid 4242 and no name
# for it) gets the uid's folder, never the shared /tmp/ itself. The lines
# are prime.sh's own, run alone: a whole prime would write in the machine's
# /tmp.
sed -n '/^if \[ "\$HAVE_DRIVES" = 1 \]; then$/,/^fi$/p' "$TOOLS/prime.sh" > "$WORK/pr/fallback.sh"
mkdir -p "$WORK/pr/noname"
printf '#!/bin/sh\ncase "$*" in\n\t-u) echo 4242 ;;\n\t*) echo "id: cannot find name for user ID 4242" >&2; exit 1 ;;\nesac\n' \
	> "$WORK/pr/noname/id"
chmod +x "$WORK/pr/noname/id"
pr_noname() {
	grep -q 'C_PISCINE_SCRATCH' "$WORK/pr/fallback.sh" || return 2
	env -u USER -u C_PISCINE_SCRATCH PATH="$WORK/pr/noname:$PATH" HAVE_DRIVES=0 \
		"$SH" -c '. "$1"; printf "[%s]\n" "$SCRATCH"' sh "$WORK/pr/fallback.sh"
}
want_out "prime: no drives.sh, no user name: the scratch is the uid's" \
	'[/tmp/4242]' -- pr_noname

# ...and a hand-written root is read too. setup.sh's own message for an existing
# .bazelrc.local is "already sets output_user_root -- left alone", so a path
# that does not end in /bazel is a state this repo produces on purpose. The read
# was anchored to `/bazel$` and saw only setup.sh's own output.
rm -rf "$WORK/pr/recorded" "$WORK/pr/hand"
mkdir -p "$WORK/pr/hand"
printf 'startup --output_user_root=%s\n' "$WORK/pr/hand" > "$WORK/pr/ws/.bazelrc.local"
want_out "prime: reads a hand-written output_user_root too" \
	"$WORK/pr/hand/prime.log" -- pr_scratch

# The lookup itself, tools/drives.sh's drives_scratch, which env-audit.sh
# also reports the prime's log and caches from: the audit kept a copy of
# prime.sh's lookup, which nothing held equal (V333). An arm a branch, over
# a toy checkout of its own, predicted.
mkdir -p "$WORK/pr/ds/ws" "$WORK/pr/ds/home" "$WORK/pr/ds/goinfre" "$WORK/pr/ds/ro"
pr_ds() {  # pr_ds VAR=VALUE... -- drives_scratch for the toy checkout, in brackets
	env -u C_PISCINE_SCRATCH HOME="$WORK/pr/ds/home" USER=prds \
		XDG_CACHE_HOME="$WORK/pr/ds/home/.cache" C_PISCINE_GOINFRE="$WORK/pr/ds/goinfre" \
		C_PISCINE_CAMPUS=0 DRIVES_DRY=1 "$@" \
		"$SH" -c '. "$1" && printf "[%s]\n" "$(drives_scratch "$2")"' _ "$TOOLS/drives.sh" "$WORK/pr/ds/ws"
}
want_out "prime: the scratch is an absolute C_PISCINE_SCRATCH" \
	"[$WORK/pr/ds/mine]" -- pr_ds C_PISCINE_SCRATCH="$WORK/pr/ds/mine"
want_out "prime: ...else the drive list's choice, never /tmp" \
	"[$WORK/pr/ds/goinfre/prds]" -- pr_ds
want_out "prime: ...which a relative C_PISCINE_SCRATCH does not stop" \
	"[$WORK/pr/ds/goinfre/prds]" -- pr_ds C_PISCINE_SCRATCH=rel
chmod 555 "$WORK/pr/ds/ro"
want_out "prime: ...and /tmp only when no other candidate can be written" \
	"[/tmp/prds]" -- pr_ds C_PISCINE_GOINFRE="$WORK/pr/ds/no-goinfre" \
	XDG_CACHE_HOME="$WORK/pr/ds/ro/cache"
chmod 755 "$WORK/pr/ds/ro"
printf 'startup --output_user_root=%s/bazel\n' "$WORK/pr/ds/recorded" > "$WORK/pr/ds/ws/.bazelrc.local"
want_out "prime: ...the rc files' root, without its /bazel, before the list" \
	"[$WORK/pr/ds/recorded]" -- pr_ds C_PISCINE_SCRATCH=rel
# The arm above that ends in /tmp reaches it through the drive list's own
# last candidate. The lookup's fallback for a list that finds nothing at all
# needs /tmp itself unwritable, which no knob stands for, so the list is a
# stand-in that refuses.
rm -f "$WORK/pr/ds/ws/.bazelrc.local"
pr_ds_none() {  # pr_ds_none -- drives_scratch with a drive list that refuses
	env -u C_PISCINE_SCRATCH HOME="$WORK/pr/ds/home" USER=prds C_PISCINE_CAMPUS=0 \
		DRIVES_DRY=1 "$SH" -c '. "$1" && drives_choose() { return 1; } &&
			printf "[%s]\n" "$(drives_scratch "$2")"' _ "$TOOLS/drives.sh" "$WORK/pr/ds/ws"
}
want_out "prime: ...and /tmp too when the drive list finds nothing" \
	"[/tmp/prds]" -- pr_ds_none

# WHAT IT ACTUALLY RUNS, which is the half no arm above could see: every one of
# them hides bazel from the fixture PATH, so the branch that does the work never
# executed. A campus box reported the consequence -- priming made the machine
# unusable, and it stayed laggy after it FINISHED.
#
# A fake bazelisk that records its own argv turns that branch into something
# testable. It has to be found on PATH under a name prime.sh looks for, and it
# must exit 0 so the `&&` chain reaches the end.
mkdir -p "$WORK/pr/rec"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$WORK/pr/rec/argv.log" \
	> "$WORK/pr/bin/bazelisk"
chmod +x "$WORK/pr/bin/bazelisk"
rm -rf "$WORK/pr/recorded"; mkdir -p "$WORK/pr/recorded"
printf 'startup --output_user_root=%s/bazel\n' "$WORK/pr/recorded" > "$WORK/pr/ws/.bazelrc.local"
: > "$WORK/pr/rec/argv.log"
pr_scratch > /dev/null 2>&1
# The prime runs in a BACKGROUNDED subshell, so the log is written after the
# script has already exited. Wait for the shutdown line rather than sleeping a
# fixed amount, which is the difference between a slow arm and a flaky one.
# Wait for the backgrounded prime to reach its shutdown, with a REAL wait.
#
# The first version spun a bounded counter with no sleep. That is not a wait: it
# completes in milliseconds, so under any load -- another test on the same box,
# a second suite on the machine -- it reaches its assertion before the subshell
# has run and reports a correct prime.sh as broken. It did exactly that,
# intermittently, which is worse than failing every time. One second per turn,
# breaking on the first, costs nothing when things are healthy.
# Done means the SUBSHELL is done, not that it reached the shutdown: prime.sh
# removes the tree AFTER the shutdown line, and the lock directory is the last
# thing it removes. Waiting on the shutdown line alone raced the rm, and on a
# loaded machine the tree was still there when the arm looked (seen 2026-09-26).
pr_wait() {
	_pw=0
	while [ "$_pw" -lt 30 ]; do
		if grep -q 'shutdown' "$WORK/pr/rec/argv.log" 2>/dev/null &&
			[ ! -d "$WORK/pr/recorded/.prime.lock" ]; then
			return 0
		fi
		sleep 1
		_pw=$((_pw + 1))
	done
	return 1
}

pr_wait

pr_recorded() { cat "$WORK/pr/rec/argv.log"; }

# 1. The server is SHUT DOWN. Bazel stays up for three idle hours (.bazelrc says so),
#    and this one uses a private --output_base nothing else will ever reuse, so
#    without this the JVM outlives the login that started it.
want_out "prime: shuts down the server it started" \
	'shutdown' -- pr_recorded
# 2. ...and cannot outlive the session even if the subshell is killed.
want_out "prime: caps the server's idle life" \
	'--max_idle_secs=300' -- pr_recorded
# 3. THE FETCH IS THROTTLED BY THE FLAG THAT ACTUALLY THROTTLES A FETCH.
#    An earlier version of this arm asserted --jobs, on the stated grounds that
#    `bazel fetch` does not inherit .bazelrc's `build` lines. That reason is
#    FALSE -- measured with --announce_rc on the pinned 9.2.0, fetch reports
#    "Inherited 'build' options: ... --local_resources=cpu=HOST_CPUS-2" -- and
#    the arm passed anyway, which is what an arm asserting the wrong thing looks
#    like. Repository rules are not build actions: they are scheduled by
#    --loading_phase_threads and by nothing else. Measured: 16 concurrent
#    repository rules under every combination of --jobs and --local_resources,
#    and 2 under --loading_phase_threads=2.
pr_fetch_line() { grep 'fetch //' "$WORK/pr/rec/argv.log" | head -1; }
want_out "prime: the FETCH half is throttled by loading_phase_threads" \
	'--loading_phase_threads=' -- pr_fetch_line
# 4. ...and the job count is an INTEGER. `cpu=HOST_CPUS*.25` is 1.5 on a
#    six-core box, and Bazel charges an ordinary action 1.0 CPU, so that budget
#    runs the build STRICTLY SERIAL -- measured at 39.2s against 5.0s for the
#    same work. A fraction is the right idea and the wrong arithmetic.
want_broken_none "prime: the budget is not a fraction Bazel rounds to one" \
	'*.25' -- pr_recorded

# ...and the disposable tree is thrown away. An output base for this repo
# is most of a full run's footprint (DRIVES_FULL_GB, tools/drives.sh, says
# what one measured), everything priming produces lives OUTSIDE it (the
# repository cache is a sibling; the compiled actions go to the disk cache), and
# a 42 $HOME is capped around 5 GB. The fake bazelisk never creates the
# directory, so the arm creates it and asserts it is gone afterwards.
# $SCRATCH here is $WORK/pr/recorded -- what pr_scratch's .bazelrc.local names --
# so the base is a directory INSIDE it, not beside it. And .prime.done has to go
# first: the arms above already primed this scratch successfully, and prime.sh's
# first act is to exit 0 when that sentinel exists, so without removing it this
# arm would assert on a run that never happened.
_pb="$WORK/pr/recorded/bazel-prime"
# BOTH sentinels, and the lock is the one that mattered. The arms above each
# leave a backgrounded subshell running; if one still holds .prime.lock when
# this arm fires, prime.sh takes the "lost a race" exit, does nothing at all,
# and the assertion below reads that as a failure to clean up. .prime.done is
# the other: prime.sh's first act is to exit 0 when it exists, and the arms
# above created it by succeeding.
rm -rf "$WORK/pr/recorded/.prime.lock"
rm -f "$WORK/pr/recorded/.prime.done"
mkdir -p "$_pb"
: > "$_pb/marker"
: > "$WORK/pr/rec/argv.log"
pr_scratch > /dev/null 2>&1
# Wait for the subshell to finish (pr_wait), not on the marker: the marker is
# what this arm asserts on, so waiting for it would assert nothing.
pr_wait
if [ -e "$_pb/marker" ]; then
	printf '  %-52s %s\n' "prime: deletes its disposable output base" \
		"FAIL < (gigabytes of scratch left behind)"
	FAIL=$((FAIL + 1))
else
	printf '  %-52s %s\n' "prime: deletes its disposable output base" "ok (green, as required)"
	PASS=$((PASS + 1))
fi

# THE TRACE (tools/prime_trace.sh): every prime samples the machine into a
# file under $HOME as it goes, because a campus box froze during one and
# nothing afterwards said what it had been doing. The prime just above
# succeeded; its trace is the newest.
pr_dir() {  # pr_dir STATE HOST -- where the library puts HOST's traces ("": this one's)
	env PATH="$WORK/pr/bin" HOME="$WORK/pr/home" XDG_STATE_HOME="$1" C_PISCINE_HOST="$2" \
		"$SH" -c '. "$1" && printf "%s" "$TRACE_DIR"' sh "$TOOLS/prime_trace.sh"
}
pr_trace() {  # pr_trace -- the newest trace the fixture's primes wrote
	_pn=""
	for _pf in "$(pr_dir "$WORK/pr/state" "")"/trace-[0-9]*; do
		[ -f "$_pf" ] && _pn=$_pf
	done
	[ -n "$_pn" ] && cat "$_pn"
}
want_out "prime: a background prime writes a trace" 'mode background' -- pr_trace
want_out "prime: ...samples the machine in it" 'S up=' -- pr_trace
want_out "prime: ...and ends it with the prime's status" 'END rc=0' -- pr_trace

# ...AND SAYS WHICH STEP EACH STRETCH OF SAMPLES BELONGS TO. A campus prime
# took 681 s, and its trace could not tell the fetch from the build: the
# choice between a fetch-only prime and the others turns on exactly that
# split. A `P phase=NAME` line marks the start of each step.
pr_order() {  # pr_order A B -- the newest trace has a P line for A, then one for B
	pr_trace | awk -v a="P phase=$1 " -v b="P phase=$2 " '
		index($0 " ", a) == 1 && !sa { sa = NR }
		index($0 " ", b) == 1 && sa && !sb { sb = NR }
		/^P / { print }
		END { if (!(sa && sb)) print "(no P line for " a "followed by one for " b ")"; exit !(sa && sb) }'
}
pr_last() { pr_trace | tail -n 1; }
want_green "prime: the trace marks the fetch, then the build" -- pr_order fetch build
want_green "prime: ...then the shutdown, then the delete" -- pr_order shutdown delete
want_out "prime: ...and the delete's status and result" 'rc=0 left=no' -- pr_trace

# THE DELETE CAN FAIL, AND THE TRACE SAYS SO. Its errors go to /dev/null --
# a login shell must stay quiet -- so the trace is the one place a delete
# that left gigabytes behind can show. An `rm` that fails on the base alone
# stands in for whatever stopped it (a chmod'ed folder does not stop root,
# so it would make this arm depend on who runs it); every other rm, the
# trace's own pruning among them, is the real one. Under `set -eu` a bare
# failing rm would also kill the subshell before END and leave .prime.lock
# behind: the trace's last line is asserted too.
if st_mine; then
	_prm=$(command -v rm)
	rm -f "$WORK/pr/bin/rm"
	printf '#!/bin/sh\ncase "$*" in *bazel-prime*) exit 1 ;; esac\nexec "%s" "$@"\n' "$_prm" \
		> "$WORK/pr/bin/rm"
	chmod +x "$WORK/pr/bin/rm"
	rm -rf "$WORK/pr/recorded/.prime.lock"
	rm -f "$WORK/pr/recorded/.prime.done"
	mkdir -p "$_pb"
	: > "$_pb/marker"
	: > "$WORK/pr/rec/argv.log"
	pr_scratch > /dev/null 2>&1
	pr_wait
	rm -f "$WORK/pr/bin/rm"
	ln -sf "$_prm" "$WORK/pr/bin/rm"
fi
want_out "prime: a delete that fails says so in the trace" 'rc=1 left=yes' -- pr_trace
want_out "prime: ...and the trace still ends" 'END rc=0' -- pr_last

# ...AND THE SAME THROUGH `nice`, the branch every real machine takes. The
# fixture PATH has no nice, so the run above took prime.sh's other rm line;
# without this one, that line alone was held, and a broken `$NICE rm` line
# (its status dropped, or the set -e kill above) stayed green here. The fake
# nice drops `-n N`, runs the rest (the fake rm among it), and logs what it
# ran, so the arm can tell the delete went through it.
if st_mine; then
	printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n[ "$1" = -n ] && shift 2\nexec "$@"\n' \
		"$WORK/pr/rec/nice.log" > "$WORK/pr/bin/nice"
	chmod +x "$WORK/pr/bin/nice"
	: > "$WORK/pr/rec/nice.log"
	rm -f "$WORK/pr/bin/rm"
	printf '#!/bin/sh\ncase "$*" in *bazel-prime*) exit 1 ;; esac\nexec "%s" "$@"\n' "$_prm" \
		> "$WORK/pr/bin/rm"
	chmod +x "$WORK/pr/bin/rm"
	rm -rf "$WORK/pr/recorded/.prime.lock"
	rm -f "$WORK/pr/recorded/.prime.done"
	mkdir -p "$_pb"
	: > "$_pb/marker"
	: > "$WORK/pr/rec/argv.log"
	pr_scratch > /dev/null 2>&1
	pr_wait
	rm -f "$WORK/pr/bin/rm" "$WORK/pr/bin/nice"
	ln -sf "$_prm" "$WORK/pr/bin/rm"
fi
want_out "prime: ...through nice, the delete runs under it" 'rm -rf' -- cat "$WORK/pr/rec/nice.log"
want_out "prime: ...and says that it failed" 'rc=1 left=yes' -- pr_trace
want_out "prime: ...and that trace still ends" 'END rc=0' -- pr_last

# ...but a FAILED prime must KEEP it. Deleting the tree unconditionally was
# strictly worse than never deleting it: the sentinel is written only when both
# halves succeed, so the next attempt would rebuild gigabytes from nothing
# instead of resuming incrementally -- and prime.sh re-fires from every
# interactive shell, so "the next attempt" can mean every terminal you open.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\ncase "$*" in *shutdown*) exit 0 ;; esac\nexit 1\n' \
	"$WORK/pr/rec/argv.log" > "$WORK/pr/bin/bazelisk"
chmod +x "$WORK/pr/bin/bazelisk"
rm -rf "$WORK/pr/recorded/.prime.lock"; rm -f "$WORK/pr/recorded/.prime.done"
mkdir -p "$_pb"; : > "$_pb/marker"
: > "$WORK/pr/rec/argv.log"
pr_scratch > /dev/null 2>&1
pr_wait
if [ -e "$_pb/marker" ]; then
	printf '  %-52s %s\n' "prime: a FAILED prime keeps the tree to resume from" \
		"ok (green, as required)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "prime: a FAILED prime keeps the tree to resume from" \
		"FAIL < (deleted it, so the retry rebuilds gigabytes from nothing)"
	FAIL=$((FAIL + 1))
fi
want_out "prime: ...and its trace ends with the failure's status" 'END rc=1' -- pr_trace

# THE OUTPUT ROOT. prime.sh prefers bazelisk, and under `bazel run` bazelisk
# skips tools/bazel -- so without the flag the prime's 2.1 GB of downloads
# would land in Bazel's own ~/.cache/bazel, a root the interactive build never
# reads, inside the quota'd home on campus. It passes the wrapper's default
# itself; but only when no rc file names a root, because Bazel reads that one
# anyway and the same option from the command line instead restarts a server.
want_broken_none "prime: an rc file's root is left to Bazel" \
	'--output_user_root' -- pr_recorded
rm -f "$WORK/pr/ws/.bazelrc.local"
_prs="$WORK/pr/home/.cache/42-piscine"
: > "$WORK/pr/rec/argv.log"
env PATH="$WORK/pr/bin" USER=selftestprime HOME="$WORK/pr/home" \
	XDG_STATE_HOME="$WORK/pr/state" BUILD_WORKSPACE_DIRECTORY="$WORK/pr/ws" C_PISCINE_CAMPUS=0 \
	C_PISCINE_GOINFRE="$WORK/pr/no-goinfre" C_PISCINE_LEGACY_ROOT="$WORK/pr/no-legacy" \
	"$SH" "$TOOLS/prime.sh" --background > /dev/null 2>&1
_pw=0
while [ "$_pw" -lt 30 ]; do
	if grep -q 'shutdown' "$WORK/pr/rec/argv.log" 2>/dev/null && [ ! -d "$_prs/.prime.lock" ]; then
		break
	fi
	sleep 1
	_pw=$((_pw + 1))
done
want_out "prime: with none, it passes the root tools/bazel would" \
	"--output_user_root=$_prs/bazel" -- pr_recorded
# ...and in the FOREGROUND, which is `bazel run //tools:prime` itself: the path
# where bazelisk has set BAZELISK_SKIP_WRAPPER, so the flag is all that keeps
# its downloads out of Bazel's own ~/.cache/bazel. Every one of its three
# commands -- the fetch, the oracle, the build -- has to carry it. A fake that
# succeeds, so that all three run.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$WORK/pr/rec/argv.log" \
	> "$WORK/pr/bin/bazelisk"
chmod +x "$WORK/pr/bin/bazelisk"
: > "$WORK/pr/rec/argv.log"
env PATH="$WORK/pr/bin" USER=selftestprime HOME="$WORK/pr/home" \
	XDG_STATE_HOME="$WORK/pr/state" BUILD_WORKSPACE_DIRECTORY="$WORK/pr/ws" C_PISCINE_CAMPUS=0 \
	C_PISCINE_GOINFRE="$WORK/pr/no-goinfre" C_PISCINE_LEGACY_ROOT="$WORK/pr/no-legacy" \
	"$SH" "$TOOLS/prime.sh" > /dev/null 2>&1
pr_fg() {  # pr_fg WHAT -- the recorded command line for WHAT carries the root
	grep -F -- "$1" "$WORK/pr/rec/argv.log" | grep -qF -- "--output_user_root=$_prs/bazel"
}
want_green "prime: in the foreground, the fetch gets the root" -- pr_fg 'fetch //...'
want_green "prime: ...and the oracle build" -- pr_fg 'build //oracle:oracle'
want_green "prime: ...and the build of everything" -- pr_fg 'build //...'
want_out "prime: the foreground writes a trace too" 'mode foreground' -- pr_trace
want_out "prime: ...ended when the script is" 'END rc=0' -- pr_trace
want_green "prime: ...and marks its steps in order" -- pr_order fetch oracle
want_green "prime: ...the oracle, then the build" -- pr_order oracle build

# A PRIME THAT STOPPED WITH THE MACHINE is not started again by itself: a box
# that froze while it primed at login would freeze again at every login. Its
# shape is a trace with no END from an earlier boot (C_PISCINE_BOOT_ID stands
# in for the kernel's), planted here as the newest. One with no END from THIS
# boot is a prime still running, and must not stop anything.
_prt=$(pr_dir "$WORK/pr/state" selftest-this-host)
pr_guard() {  # pr_guard -- a background prime, its message, and a wait for it
	rm -rf "$_prs/.prime.lock"
	rm -f "$_prs/.prime.done"
	: > "$WORK/pr/rec/argv.log"
	env PATH="$WORK/pr/bin" USER=selftestprime HOME="$WORK/pr/home" \
		XDG_STATE_HOME="$WORK/pr/state" C_PISCINE_BOOT_ID=selftest-this-boot \
		C_PISCINE_HOST=selftest-this-host \
		BUILD_WORKSPACE_DIRECTORY="$WORK/pr/ws" C_PISCINE_CAMPUS=0 \
		C_PISCINE_GOINFRE="$WORK/pr/no-goinfre" C_PISCINE_LEGACY_ROOT="$WORK/pr/no-legacy" \
		"$SH" "$TOOLS/prime.sh" --background 2>&1
	# Until no prime holds the lock: one the guard failed to stop has then
	# written its command lines.
	_pw=0
	while [ "$_pw" -lt 30 ] && [ -d "$_prs/.prime.lock" ]; do
		sleep 1
		_pw=$((_pw + 1))
	done
}
pr_ran() { grep -q 'fetch //' "$WORK/pr/rec/argv.log"; }
if st_mine; then
	mkdir -p "$_prt"
	printf '42-piscine prime trace 1\nmode background\nboot selftest-earlier-boot\nS up=1\n' \
		> "$_prt/trace-999990"
	pr_guard > "$WORK/pr/guard.out"
fi
want_out "prime: a prime that stopped with the machine says so" \
	'the last prime did not finish' -- cat "$WORK/pr/guard.out"
want_out "prime: ...and names the trace" "$_prt/trace-999990" -- cat "$WORK/pr/guard.out"
want_red "prime: ...and starts nothing" -- pr_ran
if st_mine; then
	mkdir -p "$_prt"
	printf '42-piscine prime trace 1\nmode background\nboot selftest-this-boot\nS up=1\n' \
		> "$_prt/trace-999991"
	pr_guard > /dev/null
fi
want_green "prime: an unfinished trace of this boot stops nothing" -- pr_ran

# ANOTHER MACHINE'S TRACES ARE NOT THIS ONE'S. $HOME may follow a student from
# machine to machine on campus (not confirmed yet), and every trace in it with
# it: a prime still running on the machine they left, or one that machine
# froze in, names a boot that is not this one, and read as this machine's it
# would keep this machine's login prime from ever starting. Each machine keeps
# its own five traces, numbered on their own, so a prime here prunes none of
# another's.
_pro=$(pr_dir "$WORK/pr/state" selftest-other-host)
if st_mine; then
	mkdir -p "$_pro"
	for _pi in 1 2 3 4 5; do
		printf '42-piscine prime trace 1\nmode background\nboot selftest-other-boot\nS up=1\nEND rc=0\n' \
			> "$_pro/trace-99998$_pi"
	done
	pr_guard > /dev/null
fi
pr_other() {  # pr_other -- the other machine's five traces, all still there
	_pc=0
	for _pf in "$_pro"/trace-99998[1-5]; do
		[ -f "$_pf" ] && _pc=$((_pc + 1))
	done
	echo "the other machine's traces left: $_pc of 5"
	[ "$_pc" = 5 ]
}
want_green "prime: a prime here prunes no other machine's trace" -- pr_other
if st_mine; then
	printf '42-piscine prime trace 1\nmode background\nboot selftest-other-boot\nS up=1\n' \
		> "$_pro/trace-999999"
	pr_guard > "$WORK/pr/guard.other"
fi
want_green "prime: another machine's unfinished trace stops nothing here" -- pr_ran
want_broken_none "prime: ...and is not reported as this machine's" \
	'the last prime did not finish' -- cat "$WORK/pr/guard.other"

# THE SAMPLER STOPS WITH ITS PRIME. It watches the process that started it
# and goes when that one does; a sampler left behind by a killed prime would
# write a line every few seconds until the machine stopped. A background
# prime's shape -- a subshell that outlives its script -- killed with no
# chance to end its trace, and a second's interval to keep the arm short.
pr_samples() { grep -c '^S' "$(pr_dir "$WORK/pr/orphan" "")/trace-000001" 2> /dev/null; }
if st_mine; then
	mkdir -p "$WORK/pr/orphan"
	env PATH="$WORK/pr/bin" HOME="$WORK/pr/home" XDG_STATE_HOME="$WORK/pr/orphan" \
		C_PISCINE_TRACE_EVERY=1 "$SH" -c '
			. "$1"
			( trace_start "$1" background; sleep 10 ) < /dev/null > /dev/null 2>&1 &
			echo "$!" > "$2"' sh "$TOOLS/prime_trace.sh" "$WORK/pr/orphan/pid"
	sleep 3
	kill "$(cat "$WORK/pr/orphan/pid")" 2> /dev/null
	sleep 2
	_po1=$(pr_samples)
	sleep 3
	_po2=$(pr_samples)
fi
pr_orphan() {
	echo "samples: ${_po1:-none} two seconds after the kill, ${_po2:-none} three seconds later"
	[ -n "${_po1:-}" ] && [ "$_po1" -ge 2 ] && [ "$_po1" = "${_po2:-}" ]
}
want_green "prime: the sampler stops when its prime is killed" -- pr_orphan

# THE INTERVAL is a whole number of seconds above zero, or the default. "00"
# passed for a number and then divided by zero in the sampler, which stopped
# it before its first sample; "007" would have been read as octal.
pr_every() {  # pr_every VALUE WANT -- C_PISCINE_TRACE_EVERY=VALUE gives WANT
	_pe=$(env C_PISCINE_TRACE_EVERY="$1" "$SH" -c '. "$1" && trace_every' \
		sh "$TOOLS/prime_trace.sh" 2>&1)
	echo "C_PISCINE_TRACE_EVERY=$1 gives: $_pe"
	[ "$_pe" = "$2" ]
}
want_green "prime: a trace interval of 00 is the default" -- pr_every 00 5
want_green "prime: ...one of 007 is seven seconds" -- pr_every 007 7
want_green "prime: ...and one that is no number, the default" -- pr_every 2s 5

