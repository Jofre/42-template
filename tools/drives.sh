# shellcheck shell=sh
# drives.sh — which machine is this, and where may Bazel's state go on it?
#
# SOURCED, never run: one answer to two questions that several scripts used to
# answer each in its own way, and disagree about.
#
#   tools/bazel     the wrapper bazelisk runs: the default output root when no
#                   rc file names one
#   setup.sh        chooses the scratch directory and records it
#   prime.sh        the root its own Bazel runs share with yours
#   init.sh         and env_drift.sh: the campus warning when this checkout's
#                   state sits somewhere shared or quota'd
#   env-audit.sh    reports every candidate drive, and what setup.sh and the
#                   wrapper would choose on that box
#
# WHY ONE FILE. The campus inspection records the drives so that the choice can
# be made from facts (TODO.md D7), and a choice made in one script from facts
# another script reports differently is a guess again. env-audit prints exactly
# what drives_choose decides, on the box being audited.
#
# POSIX sh, taking id, mkdir, rm, sed and tail from PATH. setup.sh, which acts
# on its choice before anything else exists, declares all five; prime.sh, which
# is wired into the login shell and must never refuse, declares the ones it
# calls itself and falls back to the drive list if the rc files cannot be read;
# init.sh, env_drift.sh and the wrapper only print or pass on what it answers,
# so a missing one costs them a warning or a default, never a wrong action. setup.sh sources it before Bazel
# exists, and tools/bazel sources it on every bazel command. drives_describe,
# which only env-audit calls, also uses awk, df and ls, and a missing one shows
# as an empty fact in the report.
#
# THE KNOBS. They change where the facts come from, never what is done with
# them -- the same terms as setup.sh's SETUP_* overrides. //tools/tests:selftest
# needs them because it cannot create /goinfre or become a campus box, and the
# cold-clone rehearsal run before each template publish needs the last one to
# play a machine that never had the old shared root.
#
#   C_PISCINE_CAMPUS=0|1    skip detection and say so
#   C_PISCINE_GOINFRE       stands in for /goinfre
#   C_PISCINE_SGOINFRE      stands in for /sgoinfre
#   C_PISCINE_LEGACY_ROOT   stands in for /tmp/bazelcache (see drives_default_root)
#
# C_PISCINE_SCRATCH is not a knob but the documented override: you said so.

drives_user() {
	printf '%s' "${USER:-$(id -un 2> /dev/null)}"
}

# DRIVES_CAMPUS=1 on a 42 box, and DRIVES_CAMPUS_WHY says how that was decided.
# (Both are read by the callers, which is why the next line is there.)
#
# Offline on purpose: reachability of Vogsphere would need the network, and a
# box that is merely offline would stop being campus. 42 boxes carry /goinfre
# and /sgoinfre; some carry /nfs/homes. Nothing else does.
# shellcheck disable=SC2034
drives_campus() {
	case "${C_PISCINE_CAMPUS:-}" in
		1) DRIVES_CAMPUS=1; DRIVES_CAMPUS_WHY="C_PISCINE_CAMPUS=1"; return 0 ;;
		0) DRIVES_CAMPUS=0; DRIVES_CAMPUS_WHY="C_PISCINE_CAMPUS=0"; return 0 ;;
	esac
	if [ -d "${C_PISCINE_SGOINFRE:-/sgoinfre}" ] || [ -d "${C_PISCINE_GOINFRE:-/goinfre}" ]; then
		DRIVES_CAMPUS=1; DRIVES_CAMPUS_WHY="/goinfre or /sgoinfre exists"
	elif [ -d /nfs/homes ]; then
		DRIVES_CAMPUS=1; DRIVES_CAMPUS_WHY="/nfs/homes exists"
	else
		DRIVES_CAMPUS=0; DRIVES_CAMPUS_WHY="no 42 filesystem markers"
	fi
}

# Writable IN FACT, not by mode: a full or read-only mount passes `-w` and
# fails on the first byte. Creates the directory if it can.
#
# DRIVES_DRY=1 predicts instead, touching nothing: an existing directory by its
# mode, an absent one by its nearest existing parent's. env-audit promises to
# leave the account as it found it, and asks what setup.sh WOULD choose.
#
# The walk up ends at `/` for an absolute path and at the working directory for
# a relative one. It used to end only at `/`: `${_dp%/*}` of a word with no
# slash is the word itself, so a relative path that did not exist looped
# forever, and `C_PISCINE_SCRATCH=myscratch sh tools/setup.sh` hung with no
# output at all. drives_choose refuses a relative C_PISCINE_SCRATCH now, but a
# probe must end whatever it is handed.
drives_probe() {
	if [ "${DRIVES_DRY:-0}" = 1 ]; then
		_dp=$1
		while [ ! -d "$_dp" ]; do
			case "$_dp" in
				*/*) _dp=${_dp%/*}; [ -n "$_dp" ] || _dp=/ ;;
				*) _dp=.; break ;;
			esac
		done
		[ -w "$_dp" ]
		return
	fi
	mkdir -p "$1" 2> /dev/null || return 1
	[ -w "$1" ] || return 1
	( : > "$1/.drives-probe.$$" ) 2> /dev/null || return 1
	rm -f "$1/.drives-probe.$$"
	return 0
}

# DRIVES_SCRATCH: the directory Bazel's big, rebuildable state goes under, and
# DRIVES_WHY, one phrase a person can read. Returns 1 when nothing qualifies,
# with DRIVES_WHY saying why.
#
# CANDIDATES, TRIED IN ORDER, each probed for real:
#   1. C_PISCINE_SCRATCH  you said so; nothing overrules it, and if it cannot
#                         be written that is an error, not a reason to guess.
#                         So is a relative path: it would name a different
#                         directory from every folder a script runs in, and
#                         Bazel refuses a relative output root anyway.
#   2. /goinfre/$USER     a 42 box: large, local, not quota'd. /sgoinfre is
#                         NOT a candidate: it is network-attached and shared,
#                         the wrong tool for a build cache (owner, 2026-08-09).
#   3. $XDG_CACHE_HOME or ~/.cache, then 42-piscine -- any other machine. It
#                         survives a reboot, so the pinned downloads are
#                         fetched once. On campus it is also the quota'd $HOME,
#                         which is why /goinfre comes first.
#   4. /tmp/$USER         last resort, and per-user on purpose: /tmp is shared.
#
# The order is a decision to be revisited from the campus reports: env-audit
# records every drive's size, owner and persistence for exactly that.
drives_choose() {
	DRIVES_SCRATCH=""
	DRIVES_WHY=""
	if [ -n "${C_PISCINE_SCRATCH:-}" ]; then
		case "$C_PISCINE_SCRATCH" in
			/*) ;;
			*)
				DRIVES_WHY="C_PISCINE_SCRATCH is set to '$C_PISCINE_SCRATCH', which must be an absolute path (it starts with /)"
				return 1
				;;
		esac
		if drives_probe "$C_PISCINE_SCRATCH"; then
			DRIVES_SCRATCH=$C_PISCINE_SCRATCH
			DRIVES_WHY="from C_PISCINE_SCRATCH"
			return 0
		fi
		DRIVES_WHY="C_PISCINE_SCRATCH is set to '$C_PISCINE_SCRATCH', which cannot be written to"
		return 1
	fi
	_dr_u=$(drives_user)
	_dr_g=${C_PISCINE_GOINFRE:-/goinfre}
	if [ -d "$_dr_g" ] && drives_probe "$_dr_g/$_dr_u"; then
		DRIVES_SCRATCH="$_dr_g/$_dr_u"
		DRIVES_WHY="/goinfre (42 box: large, local, not quota'd)"
		return 0
	fi
	_dr_c=${XDG_CACHE_HOME:-${HOME:-}/.cache}
	case "$_dr_c" in
		/*)
			if drives_probe "$_dr_c/42-piscine"; then
				DRIVES_SCRATCH="$_dr_c/42-piscine"
				DRIVES_WHY="your cache dir (persists across reboots)"
				return 0
			fi
			;;
	esac
	if drives_probe "/tmp/$_dr_u"; then
		DRIVES_SCRATCH="/tmp/$_dr_u"
		DRIVES_WHY="/tmp (last resort -- cleared on reboot)"
		return 0
	fi
	DRIVES_WHY="no candidate is writable: set C_PISCINE_SCRATCH to a directory you can write"
	return 1
}

# The output_user_root this checkout's rc files set, or nothing. $1 is the
# workspace; any further arguments are the STARTUP options of the command being
# run, which decide which rc files Bazel reads at all.
#
# Last one wins, in the order Bazel reads them: the system rc, the workspace's
# .bazelrc (whose last line imports .bazelrc.local), the home rc, then every
# --bazelrc named on the command line.
drives_rc_root() {
	drives_rc_scan "$@"
	printf '%s' "$_rr_root"
}

# ...and the file that set it: the one line a person edits to move it. The
# campus warning names it, because a root set in ~/.bazelrc is read AFTER this
# checkout's .bazelrc.local, and nothing setup.sh writes there can override it.
drives_rc_root_file() {
	drives_rc_scan "$@"
	printf '%s' "$_rr_file"
}

# The last output_user_root ONE file sets, whatever the rest say. setup.sh's
# record is .bazelrc.local's line, and prime.sh reads the scratch beside it;
# both used to parse it with a sed of their own that knew only the `=` form.
drives_file_root() {
	_rr_root=""
	_rr_file=""
	drives_rc_file "$1"
	printf '%s' "$_rr_root"
}

# Helper to the three above: sets _rr_root and _rr_file.
drives_rc_scan() {
	_rr_ws=$1
	shift
	_rr_sys=1
	_rr_wsrc=1
	_rr_home=1
	_rr_root=""
	_rr_file=""
	# Startup options end at the first word that is not an option: the command.
	# `--bazelrc FILE` takes its value as the next word, and is read after the
	# standard files -- so they are collected first and read last.
	_rr_extra=""
	_rr_next=0
	for _rr_a in "$@"; do
		if [ "$_rr_next" = 1 ]; then
			_rr_extra="$_rr_extra
$_rr_a"
			_rr_next=0
			continue
		fi
		case "$_rr_a" in
			--ignore_all_rc_files) return 0 ;;
			--nosystem_rc) _rr_sys=0 ;;
			--noworkspace_rc) _rr_wsrc=0 ;;
			--nohome_rc) _rr_home=0 ;;
			--bazelrc=*) _rr_extra="$_rr_extra
${_rr_a#--bazelrc=}" ;;
			--bazelrc) _rr_next=1 ;;
			-*) ;;
			*) break ;;
		esac
	done
	[ "$_rr_sys" = 0 ] || drives_rc_file /etc/bazel.bazelrc
	if [ "$_rr_wsrc" = 1 ]; then
		drives_rc_file "$_rr_ws/.bazelrc"
		drives_rc_file "$_rr_ws/.bazelrc.local"
	fi
	[ "$_rr_home" = 0 ] || [ -z "${HOME:-}" ] || drives_rc_file "$HOME/.bazelrc"
	_rr_ifs=$IFS
	IFS='
'
	for _rr_f in $_rr_extra; do
		[ -n "$_rr_f" ] && drives_rc_file "$_rr_f"
	done
	IFS=$_rr_ifs
	return 0
}

# Helper to drives_rc_scan: the last output_user_root one rc file sets, if any,
# into _rr_root, and the file into _rr_file. Both spellings Bazel accepts, `=`
# and a space, quoted or not.
drives_rc_file() {
	[ -r "$1" ] || return 0
	_rf=$(sed -n \
		-e 's/^[[:blank:]]*startup[[:blank:]].*--output_user_root[=[:blank:]][[:blank:]]*\([^[:blank:]]*\).*/\1/p' \
		"$1" 2> /dev/null | tail -n 1)
	_rf=${_rf#\"}
	_rf=${_rf%\"}
	[ -z "$_rf" ] && return 0
	_rr_root=$_rf
	_rr_file=$1
}

# DRIVES_ROOT: the output_user_root a checkout gets when no rc file names one,
# and DRIVES_ROOT_WHY. It is setup.sh's own choice with /bazel appended, so a
# checkout where setup.sh never ran (a second clone, a worktree) behaves as if
# it had, minus the shared disk cache.
#
# ONE EXCEPTION, and it exists so that this change moves nobody's state. Until
# 2026-09-27 .bazelrc sent every checkout without a .bazelrc.local to
# /tmp/bazelcache: one path for every user of a machine, which is the collision
# finding 001 is about. OFF CAMPUS, on a machine where that directory is yours,
# it is per-user in fact, and relocating it would re-download 2 GB of pinned
# tools and leave an orphaned server holding a gigabyte and a half. So it is
# kept there (drives_legacy_kept). On campus it never is: that is the one place
# the path is shared. C_PISCINE_SCRATCH still comes first, because you said so.
# shellcheck disable=SC2034  # DRIVES_ROOT_WHY is read by the callers
drives_default_root() {
	if drives_legacy_kept; then
		DRIVES_ROOT=$DRIVES_LEGACY
		DRIVES_ROOT_WHY="kept where this machine's Bazel state already was (yours, off campus)"
		return 0
	fi
	if drives_choose; then
		DRIVES_ROOT="$DRIVES_SCRATCH/bazel"
		DRIVES_ROOT_WHY=$DRIVES_WHY
		return 0
	fi
	DRIVES_ROOT=""
	DRIVES_ROOT_WHY=$DRIVES_WHY
	return 1
}

# Does the exception above apply here? DRIVES_LEGACY names the old shared root
# either way. setup.sh asks too: it records no root of its own while the
# wrapper is keeping this one, so that re-running it moves nothing either.
drives_legacy_kept() {
	drives_campus
	DRIVES_LEGACY=${C_PISCINE_LEGACY_ROOT:-/tmp/bazelcache}
	[ -z "${C_PISCINE_SCRATCH:-}" ] && [ "$DRIVES_CAMPUS" = 0 ] &&
		[ -d "$DRIVES_LEGACY" ] && [ -O "$DRIVES_LEGACY" ] && [ -w "$DRIVES_LEGACY" ]
}

# The output_user_root that applies to workspace $1: an rc file's if one names
# it, else the default above. Printed; empty when there is none at all (Bazel's
# own ~/.cache/bazel then applies).
drives_bazel_root() {
	_br=$(drives_rc_root "$1")
	if [ -n "$_br" ]; then
		printf '%s' "$_br"
		return 0
	fi
	drives_default_root && printf '%s' "$DRIVES_ROOT"
	return 0
}

# The output base a path under Bazel's tree belongs to: everything before its
# first /execroot/. Under `bazel run` the working directory is a runfiles tree
# inside the output base, so this is what Bazel actually used -- read back from
# Bazel rather than predicted, because a message a script prints about itself is
# not evidence. Returns 1 for a path outside any output base (a hand run).
drives_output_base_of() {
	case "$1" in
		*/execroot/*) printf '%s' "${1%%/execroot/*}" ;;
		*) return 1 ;;
	esac
}

# drives_bazel_root, predicted: the same answer, creating nothing. For the
# scripts that only report or compare a root (env_drift, setup.sh's read-back,
# the warning below) rather than use it.
drives_predicted_root() {
	(
		DRIVES_DRY=1
		drives_bazel_root "$1"
	)
}

# The output base a `bazel run` of script $2 (its $0) uses, read from $1, the
# directory it started in -- or return 1. `bazel run` starts a binary in
# <binary>.runfiles/_main, inside the output base, so that directory under $0
# is the evidence. Any other directory inside an execroot is not: a test runs
# in ITS OWN runfiles tree, often in a sandbox's execroot, and reading that as
# this checkout's state warned about a sandbox and globbed the wrong root
# (//tools/tests:selftest found both).
drives_run_base() {
	case "$2" in
		/*) _rb_self=$2 ;;
		*) _rb_self="$1/$2" ;;
	esac
	case "$1" in
		"$_rb_self.runfiles" | "$_rb_self.runfiles/"*) drives_output_base_of "$1" ;;
		*) return 1 ;;
	esac
}

# Where this checkout's Bazel state is, for the warning below: the output base
# the running `bazel run` uses, if script $3 was started by one in $2, else the
# root Bazel WOULD use for workspace $1, predicted without creating it.
# Printed; empty when there is nothing to say.
drives_state_of() {
	drives_run_base "$2" "$3" && return 0
	drives_predicted_root "$1"
}

# Is path $1 inside $HOME?
drives_under_home() {
	[ -n "${HOME:-}" ] || return 1
	case "$1/" in
		"$HOME"/*) return 0 ;;
	esac
	return 1
}

# Is path $1 this user's alone? Under $HOME, or through a directory named for
# the login (/goinfre/jdoe/..., /tmp/jdoe/..., Bazel's own _bazel_jdoe, a
# hand-written /tmp/bazel-jdoe).
drives_per_user() {
	drives_under_home "$1" && return 0
	_pu=$(drives_user)
	[ -n "$_pu" ] || return 1
	case "$1/" in
		*/"$_pu"/* | *[-_]"$_pu"/*) return 0 ;;
	esac
	return 1
}

# Is root $1 a good place on campus: outside the quota'd home, and the user's
# alone? What the warning below checks, and what it proposes has to pass.
drives_root_ok() {
	! drives_under_home "$1" && drives_per_user "$1"
}

# Print the campus warning for Bazel state at $1 (an output base or root), or
# nothing; $2 is the workspace, whose rc files say where the root comes from.
# Off campus there is nothing to say: one person, one machine. On campus, two
# things go wrong silently -- $HOME is quota'd at about 5 GB against a build of
# 8.9 GB, and a path with no login in it is one a second student collides on
# (their build waits on your lock, or cannot write your directory at all). Both
# are fixed the same way.
#
# THE ADVICE HAS TO WORK WHEN FOLLOWED, which "re-run setup" alone did not:
# setup.sh keeps a root .bazelrc.local already records, a root ~/.bazelrc sets
# is read after .bazelrc.local and wins over it, and where /goinfre cannot be
# written setup chooses the same home folder again. So it names the directory
# to move to, the drive list's own choice predicted without touching anything,
# as C_PISCINE_SCRATCH, which setup.sh records over an older line; names an rc
# file read after .bazelrc.local, whose line has to go; and when no drive here
# qualifies, says that rather than send someone round the same loop.
#
# The server is stopped FIRST, while `bazel` still means this root: a server
# left behind on the old root holds its memory for up to three idle hours
# unless it is killed by PID --
# `bazel --output_user_root=<old> shutdown` does not reach it (.bazelrc,
# "orphaned servers"). //tools/tests:selftest follows the advice and checks
# that the warning is gone.
drives_root_warning() {
	drives_campus
	[ "$DRIVES_CAMPUS" = 1 ] || return 0
	[ -n "$1" ] || return 0
	if drives_under_home "$1"; then
		_rw_what="which is inside your home: a 42 home is capped at about 5 GB,
  and a full build is 8.9 GB, so it fails part-way with a disk error."
	elif ! drives_per_user "$1"; then
		_rw_what="which is not yours alone: a second student on this machine
  collides on it (their build waits on your lock, or cannot write it at all)."
	else
		return 0
	fi
	# An rc file read after .bazelrc.local: the home rc, or a --bazelrc.
	_rw_rc=""
	if [ -n "${2:-}" ]; then
		_rw_rc=$(drives_rc_root_file "$2")
		case "$_rw_rc" in
			"" | /etc/bazel.bazelrc | "$2/.bazelrc" | "$2/.bazelrc.local") _rw_rc="" ;;
		esac
	fi
	# Where to: what the drive list chooses on this machine, predicted, and not
	# from C_PISCINE_SCRATCH -- which may be how the root got here. On a campus
	# box without a writable /goinfre that choice is the cache dir, in the very
	# home this warns about; /tmp/$USER is the per-user place left.
	_rw_to=$(
		C_PISCINE_SCRATCH=""
		DRIVES_DRY=1
		if drives_choose && drives_root_ok "$DRIVES_SCRATCH/bazel"; then
			printf '%s' "$DRIVES_SCRATCH"
		elif drives_probe "/tmp/$(drives_user)" && drives_root_ok "/tmp/$(drives_user)/bazel"; then
			printf '%s' "/tmp/$(drives_user)"
		fi
	)
	printf 'WARNING: Bazel keeps this checkout'\''s state in\n'
	printf '    %s\n' "$1"
	printf '  %s\n' "$_rw_what"
	if [ -n "$_rw_rc" ]; then
		printf '  That root is set in %s, which Bazel reads after this\n' "$_rw_rc"
		printf '  checkout'\''s .bazelrc.local: its line wins over anything setup.sh writes.\n'
	fi
	case "$_rw_to" in
		"")
			printf '  No drive on this machine qualifies by itself: neither %s/%s\n' \
				"${C_PISCINE_GOINFRE:-/goinfre}" "$(drives_user)"
			printf '  nor /tmp/%s can be written. Pick a directory of yours on a local\n' "$(drives_user)"
			printf '  disk with about 9 GB free, and use it below.\n'
			_rw_to="<that directory>"
			;;
		"/tmp/$(drives_user)")
			printf '  %s/%s is absent or cannot be written, so the place below\n' \
				"${C_PISCINE_GOINFRE:-/goinfre}" "$(drives_user)"
			printf '  is in /tmp: yours, but cleared on reboot, and the ~2 GB download\n'
			printf '  repeats after one.\n'
			;;
	esac
	printf '  Move it, in this order: stop the server while `bazel` still means\n'
	printf '  this root (one left behind keeps its memory for up to three idle hours),\n'
	if [ -n "$_rw_rc" ]; then
		printf '  delete the output_user_root line from %s,\n' "$_rw_rc"
	fi
	printf '  then have setup record the new place for THIS checkout (every clone\n'
	printf '  and worktree has its own .bazelrc.local), and open a new shell:\n'
	printf '    bazel shutdown\n'
	printf '    C_PISCINE_SCRATCH=%s sh tools/setup.sh\n' "$_rw_to"
}

# One line per fact about directory $1, for env-audit: whether it exists, who
# owns it and with which mode, the filesystem and its free space and inodes, and
# what that filesystem says about persistence. Everything here is a probe, so a
# missing tool prints as missing rather than stopping the report.
#
# PERSISTENCE is reported as far as it can be detected, which is not far: a
# RAM-backed filesystem (tmpfs, ramfs) is gone at reboot, a network one (nfs,
# cifs, ...) is shared between machines, and anything else is a local disk
# whose cleaning is a campus POLICY -- /goinfre is said to be wiped at logout
# on some campuses, never at others -- that no file on the box records. The
# report says which of the three it saw and leaves the policy to whoever reads
# it on the campus in question.
drives_describe() {
	if [ ! -e "$1" ]; then
		printf '%s\n' "absent"
		return 0
	fi
	# ls -ld rather than stat: stat's format flags differ between GNU and BSD,
	# and ls's long listing is POSIX.
	_dd_ls=$(ls -ld "$1" 2> /dev/null)
	printf 'owner %s, mode %s\n' \
		"$(printf '%s' "$_dd_ls" | awk '{ print $3 ":" $4 }')" \
		"$(printf '%s' "$_dd_ls" | awk '{ print $1 }')"
	_dd_fs=$(df -P -T "$1" 2> /dev/null | awk 'NR == 2 { print $2 }')
	_dd_src=$(df -P "$1" 2> /dev/null | awk 'NR == 2 { print $1 }')
	_dd_mnt=$(df -P "$1" 2> /dev/null | awk 'NR == 2 { print $6 }')
	printf 'filesystem %s, from %s, mounted at %s\n' \
		"${_dd_fs:-(df -T unsupported)}" "${_dd_src:-?}" "${_dd_mnt:-?}"
	printf 'space %s\n' \
		"$(df -P -k "$1" 2> /dev/null | awk 'NR == 2 { printf "%.1f GB free of %.1f GB", $4 / 1048576, $2 / 1048576 }')"
	printf 'inodes %s\n' \
		"$(df -P -i "$1" 2> /dev/null | awk 'NR == 2 { print $4 " free of " $2 }')"
	case "$_dd_fs" in
		tmpfs | ramfs) printf '%s\n' "persistence: RAM-backed, gone at reboot" ;;
		nfs* | cifs | smb* | fuse.* | ceph | gluster* | lustre | afs)
			printf '%s\n' "persistence: network filesystem, shared between machines" ;;
		"") printf '%s\n' "persistence: unknown (no filesystem type)" ;;
		*) printf '%s\n' "persistence: local disk; whether it is cleaned at logout is campus policy, not detectable" ;;
	esac
	# By mode only: env-audit leaves nothing behind, and a full or read-only
	# mount shows in the free space and the filesystem lines above.
	if [ -w "$1" ]; then
		printf '%s\n' "writable by $(drives_user): yes (by mode)"
	else
		printf '%s\n' "writable by $(drives_user): no"
	fi
}
