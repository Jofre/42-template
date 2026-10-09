# shellcheck shell=sh
# prime_trace.sh — what the machine was doing while a prime ran, written down
# as it went.
#
# SOURCED, never run: prime.sh writes a trace with it, and env-audit.sh reads
# them back, so the two agree on where traces live and on what a trace that
# stopped with the machine looks like.
#
# WHY. A campus box was reported to FREEZE during a prime, needing a hard reset,
# and nothing afterwards said why: memory, swap, the disk queue, or a server
# left behind. A freeze cannot be watched from outside, so every prime,
# background or foreground, samples the machine itself and appends each sample
# to a file, synced to disk at once: after a reset the file still holds the
# last seconds before it. `sh tools/env-audit.sh` puts the traces in its report
# ("Prime traces").
#
# WHERE. ${XDG_STATE_HOME:-$HOME/.local/state}/42-piscine/prime-traces/<host>:
# under $HOME, not in scratch, because $HOME survives a reset and /goinfre may
# not; and in a folder named after the machine, because on campus $HOME
# follows a student from machine to machine, and every trace with it. A trace
# says what one machine did. Read on another, a prime still running where it
# was written would look like one that stopped with this machine, and keep
# this machine's login prime from starting (the review of 2026-10-09). Each
# machine's five newest are kept, numbered on their own; a machine never used
# again keeps its folder, five files at most, until it is deleted.
#
# A trace is a header -- the format line, then one `key value` line each for
# the mode, the machine, the boot it ran in and what the caller adds
# (prime.sh: the CPUs, the budget, the output base) -- then one `S` line per
# sample, and `END rc=N` when the prime finishes:
#
#   S up=SECONDS memavail=KB swapfree=KB dirty=KB writeback=KB pswpin=N
#     pswpout=N pgmajfault=N load1=X [psi_memory=some:X/full:Y ...]
#     bazel_rss=PID:KB,...
#
# (one line). The three counters only grow; their rate is what a reader wants.
# The pressure averages (avg10) appear where the kernel has them, and the RSS
# is every Bazel server's, the background prime's and the checkout's alike.
# A sample every C_PISCINE_TRACE_EVERY seconds, 5 unless set.
#
# A TRACE THAT STOPPED WITH THE MACHINE is one of this machine's with no END
# line, naming a boot other than this one. One with no END from THIS boot is
# a prime still running. A prime stopped by a signal -- a closed terminal, a
# normal shutdown -- writes END with the signal's status (prime.sh's traps),
# so only a machine that stopped without warning leaves a trace like that.
#
# Courtesy, like nice: it takes sh, sleep, sync and ps from PATH, each optional
# -- without sh or sleep there is a first and a last sample and nothing between
# them; without sync a sample may be lost with the machine; without ps there
# is no RSS -- and a trace that cannot be written is skipped without a word. A
# script wired into a login shell must never refuse over it.
#
# THE SAMPLER is a separate `sh` that watches the process that started it, its
# $PPID, and stops when that process is gone. A loop in a subshell could not:
# POSIX sh gives a subshell no way to name its own process, and a sampler left
# behind by a killed prime would sample until the machine stopped.
#
# C_PISCINE_BOOT_ID stands in for the kernel's boot id, and C_PISCINE_HOST for
# the machine's name, so that the selftest can plant a trace from "another
# boot" or "another machine".

# The machine's name, as the kernel has it, made a folder name: a host name is
# letters, digits, dots and dashes, and anything else -- or nothing -- is
# "unknown".
TRACE_HOST="${C_PISCINE_HOST:-}"
if [ -z "$TRACE_HOST" ] && [ -r /proc/sys/kernel/hostname ]; then
	read -r TRACE_HOST < /proc/sys/kernel/hostname || TRACE_HOST=""
fi
if [ -z "$TRACE_HOST" ] && command -v uname > /dev/null 2>&1; then
	TRACE_HOST=$(uname -n 2> /dev/null) || TRACE_HOST=""
fi
case "$TRACE_HOST" in
	'' | .* | *[!A-Za-z0-9._-]*) TRACE_HOST=unknown ;;
esac
TRACE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/42-piscine/prime-traces"
TRACE_DIR="$TRACE_ROOT/$TRACE_HOST"
TRACE=""
TRACE_PID=""
BOOT_ID="${C_PISCINE_BOOT_ID:-}"
if [ -z "$BOOT_ID" ] && [ -r /proc/sys/kernel/random/boot_id ]; then
	read -r BOOT_ID < /proc/sys/kernel/random/boot_id || BOOT_ID=""
fi

# The newest trace, or nothing: the names count up, so the last in glob order.
trace_newest() {
	_tl=""
	for _tf in "$TRACE_DIR"/trace-[0-9]*; do
		[ -f "$_tf" ] && _tl=$_tf
	done
	printf '%s' "$_tl"
}

# Whether trace $1 stopped with the machine (see the header).
trace_froze() {
	_tb=""
	_te=0
	while read -r _tk _tv _tr; do
		case "$_tk" in
			boot) _tb=$_tv ;;
			END) _te=1 ;;
		esac
	done < "$1"
	[ "$_te" = 0 ] && [ -n "$_tb" ] && [ "$_tb" != unknown ] &&
		[ -n "$BOOT_ID" ] && [ "$_tb" != "$BOOT_ID" ]
}

trace_sample() {
	[ -n "$TRACE" ] || return 0
	_su=""
	[ -r /proc/uptime ] && read -r _su _sx < /proc/uptime
	_sm=""; _ss=""; _sd=""; _sw=""
	if [ -r /proc/meminfo ]; then
		while read -r _k _v _u; do
			case "$_k" in
				MemAvailable:) _sm=$_v ;;
				SwapFree:) _ss=$_v ;;
				Dirty:) _sd=$_v ;;
				Writeback:) _sw=$_v ;;
			esac
		done < /proc/meminfo
	fi
	_si=""; _so=""; _sf=""
	if [ -r /proc/vmstat ]; then
		while read -r _k _v; do
			case "$_k" in
				pswpin) _si=$_v ;;
				pswpout) _so=$_v ;;
				pgmajfault) _sf=$_v ;;
			esac
		done < /proc/vmstat
	fi
	_sl=""
	[ -r /proc/loadavg ] && read -r _sl _sx < /proc/loadavg
	_sp=""
	for _r in memory io cpu; do
		[ -r "/proc/pressure/$_r" ] || continue
		_pv=""
		while read -r _k _a _x; do
			_pv="$_pv${_pv:+/}$_k:${_a#avg10=}"
		done < "/proc/pressure/$_r"
		_sp="$_sp psi_$_r=$_pv"
	done
	# A Bazel server names itself bazel(<the checkout's folder>) in ps.
	_sb=""
	if command -v ps > /dev/null 2>&1; then
		_sb=$(ps -eo pid=,rss=,args= 2> /dev/null | while read -r _p _r _a _x; do
			case "$_a" in
				'bazel('*) printf '%s:%s,' "$_p" "$_r" ;;
			esac
		done)
	fi
	printf 'S up=%s memavail=%s swapfree=%s dirty=%s writeback=%s pswpin=%s pswpout=%s pgmajfault=%s load1=%s%s bazel_rss=%s\n' \
		"$_su" "$_sm" "$_ss" "$_sd" "$_sw" "$_si" "$_so" "$_sf" "$_sl" "$_sp" "${_sb%,}" \
		>> "$TRACE" 2> /dev/null || return 0
	if command -v sync > /dev/null 2>&1; then
		sync "$TRACE" 2> /dev/null || :
	fi
	return 0
}

# trace_every: the seconds between two samples, C_PISCINE_TRACE_EVERY when it
# is a whole number above zero, 5 otherwise. Its leading zeros go, so that
# "00" is not a zero to divide by and "010" is not octal to $(( )).
trace_every() {
	_tv=${C_PISCINE_TRACE_EVERY:-}
	case "$_tv" in
		'' | *[!0-9]*) _tv=5 ;;
	esac
	while [ "${_tv#0}" != "$_tv" ]; do _tv=${_tv#0}; done
	printf '%s' "${_tv:-5}"
}

# trace_sampler TRACE: one sample per interval, for as long as the process that
# started this sh lives. Six hours at most, the bound prime.sh puts on a lock.
trace_sampler() {
	TRACE=$1
	_te=$(trace_every)
	_tn=$((21600 / _te))
	command -v sleep > /dev/null 2>&1 || return 0
	while [ "$_tn" -gt 0 ] && sleep "$_te" && kill -0 "$PPID" 2> /dev/null; do
		trace_sample
		_tn=$((_tn - 1))
	done
	return 0
}

# trace_start LIB MODE [LINE...]: a new trace, its header (each LINE is one more
# `key value` line of it) and a first sample, the five newest kept, and a
# sampler behind it. LIB is this file's path, which a sourced file cannot learn
# for itself; the sampler sources it again.
trace_start() {
	_tlib=$1
	_tmode=$2
	shift 2
	[ -r /proc/meminfo ] || return 0
	mkdir -p "$TRACE_DIR" 2> /dev/null || return 0
	_tl=$(trace_newest)
	_tn=${_tl##*/trace-}
	case "$_tn" in
		'' | *[!0-9]*) _tn=0 ;;
	esac
	# One more than the newest, in decimal: a leading zero is octal to $(( )).
	while [ "${_tn#0}" != "$_tn" ]; do _tn=${_tn#0}; done
	_tn=$((${_tn:-0} + 1))
	TRACE=$(printf '%s/trace-%06d' "$TRACE_DIR" "$_tn")
	{
		printf '42-piscine prime trace 1\n'
		printf 'mode %s\n' "$_tmode"
		printf 'host %s\n' "$TRACE_HOST"
		printf 'boot %s\n' "${BOOT_ID:-unknown}"
		for _th; do
			printf '%s\n' "$_th"
		done
	} > "$TRACE" 2> /dev/null || { TRACE=""; return 0; }
	trace_sample
	# This machine's five newest: the oldest go, in glob order.
	_tc=0
	for _tf in "$TRACE_DIR"/trace-[0-9]*; do
		[ -f "$_tf" ] && _tc=$((_tc + 1))
	done
	for _tf in "$TRACE_DIR"/trace-[0-9]*; do
		[ "$_tc" -gt 5 ] || break
		[ -f "$_tf" ] || continue
		rm -f "$_tf"
		_tc=$((_tc - 1))
	done
	command -v sh > /dev/null 2>&1 || return 0
	# shellcheck disable=SC2016 # expanded by the sampler's sh, not here
	sh -c '. "$1" && trace_sampler "$2"' prime_trace "$_tlib" "$TRACE" \
		< /dev/null > /dev/null 2>&1 &
	TRACE_PID=$!
	return 0
}

# trace_end RC: the sampler stopped first, so that no sample lands after END.
trace_end() {
	[ -n "$TRACE" ] || return 0
	if [ -n "$TRACE_PID" ]; then
		kill "$TRACE_PID" 2> /dev/null || :
		wait "$TRACE_PID" 2> /dev/null || :
		TRACE_PID=""
	fi
	trace_sample
	printf 'END rc=%s\n' "$1" >> "$TRACE" 2> /dev/null || :
	if command -v sync > /dev/null 2>&1; then
		sync "$TRACE" 2> /dev/null || :
	fi
	TRACE=""
	return 0
}
