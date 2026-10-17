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
# be made from facts (D7), and a choice made in one script from facts
# another script reports differently is a guess again. env-audit prints exactly
# what drives_choose decides, on the box being audited.
#
# POSIX sh, taking id, mkdir, rm, sed and tail from PATH. setup.sh, which acts
# on its choice before anything else exists, declares all five; prime.sh, which
# is wired into the login shell and must never refuse, declares the ones it
# calls itself and falls back to the drive list if the rc files cannot be read;
# init.sh, env_drift.sh and the wrapper only print or pass on what it answers,
# so a missing one costs them a warning or a default, never a wrong action.
# setup.sh sources it before Bazel
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
#   C_PISCINE_DOCKERENV     stands in for /.dockerenv (see drives_in_container)
#   C_PISCINE_SYSTEM_BAZELRC stands in for /etc/bazel.bazelrc (drives_rc_scan)
#
# C_PISCINE_SCRATCH is not a knob but the documented override: you said so.

# WHAT A FULL RUN TAKES, in whole gigabytes rounded up, and the one place the
# figure lives: setup.sh's two warnings print it and its free-space threshold is
# built from it, drives_root_warning below prints it, and every other file that
# needs it points here.
#
# Measured on 2026-10-11, 2822 test targets: a cold `bazel test //...
# --keep_going` left 4.4 GB under a fresh --output_user_root (the output base
# 2.1, the download cache 2.2, the install base 0.2), and a second run with
# setup.sh's disk cache filled that cache with 0.3 GB more. That is the end of a
# run, not its peak. Measure again when the suite has grown, the same way, and
# change this line and its date.
# shellcheck disable=SC2034
DRIVES_FULL_GB=5

drives_user() {
	printf '%s' "${USER:-$(id -un 2> /dev/null)}"
}

# Path $1 with each run of slashes squeezed to one and a trailing one dropped
# (`/` itself kept), for a path that is joined to a name or compared as text.
# A cache dir given as <dir>/ joined into <dir>//42-piscine, which setup.sh
# prints and writes into the --disk_cache line. No tool: the wrapper sources
# this on every bazel command.
drives_tidy() {
	_td=$1
	while :; do
		case "$_td" in
			*//*) _td="${_td%%//*}/${_td#*//}" ;;
			*) break ;;
		esac
	done
	case "$_td" in
		?*/) _td=${_td%/} ;;
	esac
	printf '%s' "$_td"
}

# Whether this runs in a container: the variable the dev container's editor
# sets, or the file Docker writes at the root of every container it starts.
# tools/bazel offers .devcontainer/postcreate.sh's step only there, and
# tools/fortytwo/doctor.py asks the same two questions with the same knob.
drives_in_container() {
	[ -n "${REMOTE_CONTAINERS:-}" ] || [ -e "${C_PISCINE_DOCKERENV:-/.dockerenv}" ]
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
# That parent is the nearest thing that exists, folder or not: a plain file
# on the way is where mkdir -p stops, for root too, so a path below one is
# predicted to fail. The walk used to skip over it to the folder above, and
# called such a path creatable when the real probe said no.
#
# The walk up ends at `/` for an absolute path and at the working directory for
# a relative one. It used to end only at `/`: `${_dp%/*}` of a word with no
# slash is the word itself, so a relative path that did not exist looped
# forever, and `C_PISCINE_SCRATCH=myscratch sh tools/setup.sh` hung with no
# output at all. drives_choose refuses a relative C_PISCINE_SCRATCH now, but a
# probe must end whatever it is handed.
#
# DRIVES_MADE: the topmost folder a real probe's mkdir made, empty when the
# folder was there already (and always, predicting). A caller that refuses
# the place it chose can then take back what choosing it made, and only that:
# .devcontainer/postcreate.sh does, for a place inside the workspace.
drives_probe() {
	# shellcheck disable=SC2034  # read by the callers
	DRIVES_MADE=""
	if [ "${DRIVES_DRY:-0}" = 1 ]; then
		_dp=$1
		while [ ! -e "$_dp" ]; do
			case "$_dp" in
				*/*) _dp=${_dp%/*}; [ -n "$_dp" ] || _dp=/ ;;
				*) _dp=.; break ;;
			esac
		done
		[ -d "$_dp" ] && [ -w "$_dp" ]
		return
	fi
	# The same walk, keeping the last folder that is not there yet.
	_dp=$1
	_dm=""
	while [ ! -d "$_dp" ]; do
		_dm=$_dp
		case "$_dp" in
			*/*) _dp=${_dp%/*}; [ -n "$_dp" ] || _dp=/ ;;
			*) break ;;
		esac
	done
	mkdir -p "$1" 2> /dev/null || return 1
	DRIVES_MADE=$_dm
	[ -w "$1" ] || return 1
	( : > "$1/.drives-probe.$$" ) 2> /dev/null || return 1
	rm -f "$1/.drives-probe.$$"
	return 0
}

# DRIVES_SCRATCH: the directory Bazel's big, rebuildable state goes under, and
# DRIVES_WHY, one phrase a person can read. Returns 1 when nothing qualifies,
# with DRIVES_WHY saying why. DRIVES_MADE is the chosen candidate's probe's.
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
	# shellcheck disable=SC2034  # read by the callers
	DRIVES_MADE=""
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
	_dr_g=$(drives_tidy "${C_PISCINE_GOINFRE:-/goinfre}")
	if [ -d "$_dr_g" ] && drives_probe "$_dr_g/$_dr_u"; then
		DRIVES_SCRATCH="$_dr_g/$_dr_u"
		DRIVES_WHY="/goinfre (42 box: large, local, not quota'd)"
		return 0
	fi
	_dr_c=$(drives_tidy "${XDG_CACHE_HOME:-${HOME:-}/.cache}")
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
# --bazelrc named on the command line. The system rc is the file
# C_PISCINE_SYSTEM_BAZELRC names when it is set: //tools/tests:selftest points
# it at one that does not exist, so that a root a box sets in
# /etc/bazel.bazelrc reaches none of its arms.
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

# Helper to the three above: sets _rr_root and _rr_file. tools/bazel and
# .devcontainer/postcreate.sh call it themselves, for both: _rr_file set
# inside a $(...) is lost with the subshell.
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
	[ "$_rr_sys" = 0 ] || drives_rc_file "${C_PISCINE_SYSTEM_BAZELRC:-/etc/bazel.bazelrc}"
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

# DRIVES_ROOT: the output_user_root workspace $1 gets when no rc file names
# one, and DRIVES_ROOT_WHY. It is setup.sh's own choice with /bazel appended, so
# a checkout where setup.sh never ran (a second clone, a worktree) behaves as if
# it had, minus the shared disk cache.
#
# ONE EXCEPTION, and it exists so that this change moves nobody's state. Until
# 2026-09-27 .bazelrc sent every checkout without a .bazelrc.local to
# /tmp/bazelcache: one path for every user of a machine, which is the collision
# finding 001 is about. OFF CAMPUS, on a machine where that directory is yours,
# it is per-user in fact, and relocating it would re-download 2 GB of pinned
# tools and leave an orphaned server holding a gigabyte and a half. So it is
# kept there, when this checkout's state is in it (drives_legacy_kept). On
# campus it never is: that is the one place the path is shared.
# C_PISCINE_SCRATCH still comes first, because you said so.
# shellcheck disable=SC2034  # DRIVES_ROOT_WHY is read by the callers
drives_default_root() {
	if drives_legacy_kept "${1:-}"; then
		DRIVES_ROOT=$DRIVES_LEGACY
		DRIVES_ROOT_WHY="kept where this checkout's Bazel state already was (yours, off campus)"
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

# Does the exception above apply to workspace $1? DRIVES_LEGACY names the old
# shared root either way. setup.sh asks too: it records no root of its own while
# the wrapper is keeping this one, so that re-running it moves nothing either.
#
# ONLY STATE THAT IS ALREADY THERE is kept, which is what the exception is for:
# the old root has to hold this workspace's output base, and the per-user root
# must not. A folder that is merely yours is not enough. Any copy of the
# repository from before the change, run once on the machine (an old clone, an
# old template checked out to compare), creates the old root, and every
# checkout without a .bazelrc.local then moved into it: a second server on a
# cold output base, the warm one under the per-user root left running. With no
# workspace named nothing is kept.
drives_legacy_kept() {
	drives_campus
	DRIVES_LEGACY=${C_PISCINE_LEGACY_ROOT:-/tmp/bazelcache}
	if ! { [ -z "${C_PISCINE_SCRATCH:-}" ] && [ "$DRIVES_CAMPUS" = 0 ] &&
		[ -d "$DRIVES_LEGACY" ] && [ -O "$DRIVES_LEGACY" ] && [ -w "$DRIVES_LEGACY" ] &&
		[ -n "${1:-}" ] && drives_holds_base "$DRIVES_LEGACY" "$1"; }; then
		return 1
	fi
	# The per-user root, predicted: asking must not create it.
	_lk_own=$(
		DRIVES_DRY=1
		drives_choose && printf '%s' "$DRIVES_SCRATCH/bazel"
	)
	[ -z "$_lk_own" ] || ! drives_holds_base "$_lk_own" "$1"
}

# Does output root $1 hold workspace $2's output base? Bazel names a base after
# the md5 of the workspace's path and writes that path, with no newline, into
# the base's DO_NOT_BUILD_HERE, which is read here instead: md5sum is `md5` on
# a Mac, and a read needs no tool at all. Bazel may have written the physical
# path, so a workspace reached through a symbolic link is compared both ways.
drives_holds_base() {
	_hb_phys=""
	for _hb_f in "$1"/*/DO_NOT_BUILD_HERE; do
		[ -r "$_hb_f" ] || continue
		_hb_ws=""
		IFS= read -r _hb_ws < "$_hb_f" || :
		[ "$_hb_ws" = "$2" ] && return 0
		[ -n "$_hb_phys" ] || _hb_phys=$(cd "$2" 2> /dev/null && pwd -P)
		[ -n "$_hb_phys" ] && [ "$_hb_ws" = "$_hb_phys" ] && return 0
	done
	return 1
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
	drives_default_root "$1" && printf '%s' "$DRIVES_ROOT"
	return 0
}

# The scratch folder tools/prime.sh keeps its log, its lock and the disk cache
# in, for workspace $1. Printed. env-audit.sh reports that log and those caches
# from the same answer, predicted (DRIVES_DRY), and used to keep a copy of
# prime.sh's lookup that nothing held equal.
#
# An absolute C_PISCINE_SCRATCH first, on the same terms as in setup.sh: you
# said so. A relative one is passed over, here and below: it is a different
# directory for every shell that starts in a different folder, and setup.sh
# refuses it, but the prime must never refuse, and drives_choose would refuse
# it and leave /tmp when the list has a better place. Then the folder the rc
# files' root is in: setup.sh records <scratch>/bazel, and a hand-written root
# without the /bazel is its own scratch. Nothing recorded means this checkout
# never ran setup.sh: then the choice setup.sh WOULD make, from the same list,
# which is also the root tools/bazel gives such a checkout, so the two cannot
# disagree. /tmp/$USER when even the list has nothing.
drives_scratch() {
	case "${C_PISCINE_SCRATCH:-}" in
		/*)
			printf '%s' "$C_PISCINE_SCRATCH"
			return 0
			;;
	esac
	_sc=$(drives_rc_root "$1")
	_sc=${_sc%/bazel}
	[ -n "$_sc" ] || _sc=$(
		C_PISCINE_SCRATCH=""
		drives_choose && printf '%s' "$DRIVES_SCRATCH"
	)
	[ -n "$_sc" ] || _sc="/tmp/$(drives_user)"
	printf '%s' "$_sc"
}

# The output base a path under Bazel's tree belongs to: everything before its
# last /execroot/. Under `bazel run` the working directory is a runfiles tree
# inside the output base, so this is what Bazel actually used -- read back from
# Bazel rather than predicted, because a message a script prints about itself is
# not evidence. Returns 1 for a path outside any output base (a hand run). The
# LAST, because an output base can sit inside another's execroot: the
# selftest's fixtures do, in the test's own TEST_TMPDIR, and the first one
# named the sandbox the selftest ran in.
drives_output_base_of() {
	case "$1" in
		*/execroot/*) printf '%s' "${1%/execroot/*}" ;;
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

# Is path $1 inside $HOME? Both tidied: a home given as <dir>/ matched only
# the doubled join drives_choose used to make, <dir>//.cache, and no path
# written with one slash.
drives_under_home() {
	[ -n "${HOME:-}" ] || return 1
	_uh=$(drives_tidy "$HOME")
	case "$(drives_tidy "$1")/" in
		"$_uh"/*) return 0 ;;
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
# things go wrong silently -- $HOME is quota'd at about 5 GB against a full
# build of DRIVES_FULL_GB (above), and a path with no login in it is one a
# second student collides on (their build waits on your lock, or cannot write
# your directory at all). Both are fixed the same way.
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
		_rw_what="which is inside your home: a 42 home is capped at about 5 GB in
  all, and a full build alone is about $DRIVES_FULL_GB GB, so it fails part-way
  with a disk error."
	elif ! drives_per_user "$1"; then
		_rw_what="which is not yours alone: a second student on this machine
  collides on it (their build waits on your lock, or cannot write it at all)."
	else
		return 0
	fi
	# An rc file read after .bazelrc.local: the home rc, or a --bazelrc. The
	# system rc is read before it, whichever file stands in for it.
	_rw_rc=""
	if [ -n "${2:-}" ]; then
		_rw_rc=$(drives_rc_root_file "$2")
		case "$_rw_rc" in
			"" | "${C_PISCINE_SYSTEM_BAZELRC:-/etc/bazel.bazelrc}" | "$2/.bazelrc" | "$2/.bazelrc.local") _rw_rc="" ;;
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
			printf '  disk with %s GB or more free, and use it below.\n' "$((DRIVES_FULL_GB * 2))"
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
# cifs, ...) is shared between machines, a FUSE one is served by a program
# that may keep its files on this machine (fuse-overlayfs, which rootless
# containers use) or on another (sshfs), so only the subtypes that reach
# another machine by design are called network ones (GlusterFS's and CephFS's
# own clients among them: GlusterFS has no client in the kernel, so its mounts
# are all fuse.glusterfs), and anything else is not
# a network filesystem by type, which is all the type tells: a disk of this
# machine's and a volume attached at login look alike (fuseblk, FUSE over a
# block device of this machine's, among them). Its cleaning is a campus POLICY
# -- /goinfre is said to be wiped at logout on some campuses, never at others
# -- that no file on the box records. The
# report says which of the four it saw and leaves the policy to whoever reads
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
	# A total of 0 is a filesystem that keeps no count to report (an NFS
	# server may not), not one with no inodes left.
	printf 'inodes %s\n' \
		"$(df -P -i "$1" 2> /dev/null | awk 'NR == 2 { if ($2 + 0 == 0) print "not reported by the filesystem"; else print $4 " free of " $2 }')"
	case "$_dd_fs" in
		tmpfs | ramfs) printf '%s\n' "persistence: RAM-backed, gone at reboot" ;;
		nfs* | cifs | smb* | ceph | gluster* | lustre | afs | fuse.glusterfs | fuse.ceph-fuse | \
			fuse.sshfs | fuse.s3fs | fuse.rclone | fuse.gcsfuse)
			printf '%s\n' "persistence: network filesystem, shared between machines" ;;
		fuse | fuse.*) printf '%s\n' "persistence: FUSE, served by a program: it may be local or network, which the type does not say; whether it is cleaned at logout is campus policy, not detectable" ;;
		"") printf '%s\n' "persistence: unknown (no filesystem type)" ;;
		*) printf '%s\n' "persistence: not a network filesystem by type (it may still be a volume attached at login); whether it is cleaned at logout is campus policy, not detectable" ;;
	esac
	# By mode only: env-audit leaves nothing behind, and a full or read-only
	# mount shows in the free space and the filesystem lines above.
	if [ -w "$1" ]; then
		printf '%s\n' "writable by $(drives_user): yes (by mode)"
	else
		printf '%s\n' "writable by $(drives_user): no"
	fi
}
