# -------------------------------------------------------------------------- setup
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The script every single user runs, exactly once, before anything else exists
# -- and therefore the one whose failure nobody can debug with the harness,
# because the harness is what it installs. It is driven here OFFLINE through
# SETUP_BAZELISK_URL (a file:// URL) and SETUP_BAZELISK_SHA256, so these arms
# need no network and no campus box.
#
# The red arm is the one that matters: a checksum mismatch must REFUSE, because
# the alternative is chmod +x on whatever that URL served today. setup.sh
# verifies before it makes the file executable, so a rejected download is never
# a thing the machine could run -- the second assertion below is what pins that
# ordering down rather than trusting the comment.
mkdir -p "$WORK/su/repo/tools" "$WORK/su/home"
printf 'fake bazelisk payload\n' > "$WORK/su/payload"
SU_SHA=$(sha256sum "$WORK/su/payload" | cut -d' ' -f1)
cp "$TOOLS/setup.sh" "$WORK/su/repo/tools/setup.sh"
# The drive list setup.sh chooses from, which it sources from the checkout it
# sets up: the same file tools/bazel and env-audit read (tools/drives.sh).
cp "$TOOLS/drives.sh" "$WORK/su/repo/tools/drives.sh"
cp "$TOOLS/identity.sh" "$WORK/su/repo/tools/identity.sh"
# 42's installer, which step 2 runs, and the entry it will not install without.
mkdir -p "$WORK/su/repo/tools/fortytwo"
cp "$TOOLS/42.sh" "$WORK/su/repo/tools/42.sh"
cp "$TOOLS/fortytwo/install.sh" "$WORK/su/repo/tools/fortytwo/install.sh"
: > "$WORK/su/repo/.bazelversion"
printf '# pre-existing line\n' > "$WORK/su/home/.bashrc"

# THE SANDBOX'S ENVIRONMENT, written once: every run of setup.sh here, and of
# init.sh over the sandbox, goes through su_in. Each place the drive choice
# reads is set or cleared in it, because a hand run of this file inherits the
# caller's: C_PISCINE_SCRATCH, then $XDG_CACHE_HOME/42-piscine, made the
# sandbox's setup.sh record a folder on the host, create it, and run its
# toolchain repair over the host's real root. The copies of this line it
# replaces had drifted, and only some cleared XDG_CACHE_HOME.
# C_PISCINE_GOINFRE names a /goinfre that does not exist, so the arms mean the
# same thing on a campus box, where the real one does.
# C_PISCINE_LEGACY_ROOT likewise names an old shared root that does not exist:
# the real /tmp/bazelcache, where the machine running this has one, would be
# kept (see the legacy arm below) and every off-campus arm would record nothing.
# A NAME=VALUE before the command is set for that run too, over these.
su_in() {  # su_in DIR [--bound SECS] [NAME=VALUE...] COMMAND... -- COMMAND in DIR, in the sandbox's environment
	_sui_d=$1
	_sui_b=
	shift
	if [ "${1:-}" = --bound ]; then
		_sui_b=$2
		shift 2
	fi
	set -- env -u BUILD_WORKSPACE_DIRECTORY -u C_PISCINE_SCRATCH \
		-u C_PISCINE_CAMPUS -u C_PISCINE_SGOINFRE \
		HOME="$WORK/su/home" USER=probe XDG_CACHE_HOME= \
		C_PISCINE_GOINFRE="$WORK/su/no-goinfre" C_PISCINE_LEGACY_ROOT="$WORK/su/no-legacy" \
		SETUP_BAZELISK_URL="file://$WORK/su/payload" \
		SETUP_BAZELISK_SHA256="$SU_SHA" SETUP_SKIP_DRIFT=1 "$@"
	# --bound: bounded is a function, which env cannot run, so it runs env.
	( cd "$_sui_d" && if [ -n "$_sui_b" ]; then bounded "$_sui_b" "$@"; else "$@"; fi )
}
su_env() { su_in "$WORK/su/repo" "$@"; }  # su_env [NAME=VALUE...] COMMAND... -- in the sandbox checkout
# "$SH", not a literal `sh`. With `sh` hard-coded, :selftest_bash replayed every
# OTHER arm under bash while silently re-running these setup arms under dash --
# so the one script that runs before Bazel exists, on a machine whose shell
# nobody chose, was the one the cross-shell target never reached.
su_run() {  # su_run SHA [NAME=VALUE...] -- runs setup.sh against the sandbox, offline
	_su_sha=$1
	shift
	su_env SETUP_BAZELISK_SHA256="$_su_sha" "$@" "$SH" tools/setup.sh
}
# su_has PATTERN FILE -- a line of FILE matches PATTERN; if none does, says
# so with what FILE holds, which want_green shows under the arm.
su_has() {
	grep -q -- "$1" "$2" 2> /dev/null && return 0
	printf 'no line matches %s in %s, which holds:\n' "$1" "${2##*/}"
	cat "$2"
	return 1
}
# su_once FILE PATTERN... -- each PATTERN matches exactly one line of FILE.
su_once() {
	_suo_f=$1
	shift
	for _suo_p; do
		_suo_n=$(grep -c -- "$_suo_p" "$_suo_f" 2> /dev/null)
		[ "${_suo_n:-0}" = 1 ] && continue
		printf '%s lines match %s in %s\n' "${_suo_n:-0}" "$_suo_p" "${_suo_f##*/}"
		return 1
	done
}
# su_gone PATH -- nothing is at PATH; if something is, says so.
su_gone() {
	[ ! -e "$1" ] && [ ! -L "$1" ] && return 0
	printf 'still there: %s\n' "$1"
	return 1
}

want_green "setup: a download matching its pin installs" -- su_run "$SU_SHA"
want_green "setup: running it twice is idempotent" -- su_run "$SU_SHA"
# Run as the README says, `sh tools/setup.sh`, by a user whose profile
# exports CDPATH=.: cd looks `tools/..` up through it and prints the folder
# it found, and a lookup that does not empty CDPATH died at its first step.
want_out "setup: an exported CDPATH=. still finds one checkout" \
	"setup: preparing this machine for $WORK/su/repo" -- su_run "$SU_SHA" CDPATH=.
want_green "setup: ...and puts the 42 shim beside bazelisk" -- \
	grep -qF "# 42 shim, written by tools/fortytwo/install.sh" "$WORK/su/home/.local/bin/42"
# A 42 the installer did not write: it is left alone, and the setup goes on.
# The swap is under st_mine: the folder it writes in is made by su_run, an
# arm, so in a shard that skips this section it does not exist, and the swap
# printed "cannot create" and "cannot stat" into that shard's log.
if st_mine; then
	mv "$WORK/su/home/.local/bin/42" "$WORK/su/shim42"
	printf '#!/bin/sh\necho mine\n' > "$WORK/su/home/.local/bin/42"
fi
want_green "setup: a 42 it did not write costs only the name" -- su_run "$SU_SHA"
want_green "setup: ...and is left as it was" -- grep -qx 'echo mine' "$WORK/su/home/.local/bin/42"
! st_mine || mv "$WORK/su/shim42" "$WORK/su/home/.local/bin/42"

want_green "setup: one profile block, prior content intact" -- \
	su_once "$WORK/su/home/.bashrc" '>>> 42 c-piscine setup >>>' 'pre-existing line'

# THE LAST THING IT SAYS is what a student who has never opened a terminal does
# next, so it names the file it wrote for their login shell and tells them to
# open a new terminal. It used to say ". ~/.bashrc", which a zsh login never
# reads, and the campus login shell is zsh (2026-08-09 audit). A getent of the
# sandbox's own makes the login shell zsh, whatever this machine's is; the
# next steps print with SETUP_SKIP_DRIFT=1 too, which every arm here sets.
mkdir -p "$WORK/su/zsh-bin" "$WORK/su/zsh-home"
printf '#!/bin/sh\necho "probe:x:1000:1000::%s:/bin/zsh"\n' "$WORK/su/zsh-home" > "$WORK/su/zsh-bin/getent"
chmod +x "$WORK/su/zsh-bin/getent"
! st_mine || su_env HOME="$WORK/su/zsh-home" PATH="$WORK/su/zsh-bin:$PATH" \
	"$SH" tools/setup.sh > "$WORK/su/zsh.out" 2>&1
want_green "setup: on a zsh login it names ~/.zshrc last" -- \
	grep -qF "open a new one: ~/.zshrc" "$WORK/su/zsh.out"
want_red "setup: ...and never offers . ~/.bashrc" -- grep -qF ". ~/.bashrc" "$WORK/su/zsh.out"
want_green "setup: ...and sends the student to 42 doctor" -- grep -qF "42 doctor" "$WORK/su/zsh.out"
# Its way round a missing 42 is typed in the folder setup ran in, whose tools/
# holds 42.sh: said as a swap rule alone, it failed in the exercise folder the
# README goes on to.
want_green "setup: ...whose way round names the folder" -- \
	grep -qF "in its place, from this folder" "$WORK/su/zsh.out"
# A pins check that did not complete is re-run with 42's command, which
# types the bazel run (V306): --drift, because a plain `42 doctor` on a
# checkout that has not built yet leaves env_drift out. Without
# SETUP_SKIP_DRIFT, the sandbox's bazelisk (the payload, no program) fails
# at once, offline, which is that branch.
! st_mine || su_env env -u SETUP_SKIP_DRIFT "$SH" tools/setup.sh > "$WORK/su/drift.out" 2>&1
want_green "setup: a pins check that did not complete is said" -- \
	grep -qF "env_drift did not complete" "$WORK/su/drift.out"
want_green "setup: ...and re-run with 42 doctor --drift" -- \
	grep -qxF "    42 doctor --drift" "$WORK/su/drift.out"
want_red   "setup: ...never with the bazel run it types" -- \
	grep -qF "bazel run //tools:env_drift" "$WORK/su/drift.out"

# THE CHECKOUT IT SETS UP is BUILD_WORKSPACE_DIRECTORY when that is set, as
# under `bazel run`, and a hand run of this file from a script `bazel run
# --script_path` wrote inherits the real checkout's. Every arm here then set up
# THAT checkout, writing and rewriting its .bazelrc.local, and the sandbox's
# arms went red (V92). The decoy is a checkout setup.sh would accept, so the
# arm is red only because something was written there.
mkdir -p "$WORK/su/decoy/tools"
: > "$WORK/su/decoy/.bazelversion"
cp "$TOOLS/drives.sh" "$WORK/su/decoy/tools/drives.sh"
rm -f "$WORK/su/repo/.bazelrc.local"
! st_mine || ( BUILD_WORKSPACE_DIRECTORY="$WORK/su/decoy"; export BUILD_WORKSPACE_DIRECTORY
	su_run "$SU_SHA" ) > /dev/null 2>&1
want_green "setup: an inherited BUILD_WORKSPACE_DIRECTORY is not set up" -- \
	test ! -e "$WORK/su/decoy/.bazelrc.local"
want_green "setup: ...the sandbox it ran in is" -- test -s "$WORK/su/repo/.bazelrc.local"
# Nor does it take the caller's word for where the cache goes: each of these
# named a folder setup.sh then chose, recorded and created outside the
# sandbox, and its toolchain repair ran over that root. Each run starts from
# no .bazelrc.local, since a recorded root is kept and asks nothing.
su_decoy() {  # su_decoy NAME=VALUE -- su_run, with NAME the caller's, exported
	rm -f "$WORK/su/repo/.bazelrc.local"
	( export "${1?}"; su_run "$SU_SHA" ) > /dev/null 2>&1
}
! st_mine || su_decoy C_PISCINE_SCRATCH="$WORK/su/decoy-scratch"
want_green "setup: an inherited C_PISCINE_SCRATCH is not used" -- su_gone "$WORK/su/decoy-scratch"
! st_mine || su_decoy XDG_CACHE_HOME="$WORK/su/decoy-xdg"
want_green "setup: ...nor an inherited XDG_CACHE_HOME" -- su_gone "$WORK/su/decoy-xdg"

# WHERE THE CACHE GOES, off campus. This script is useful outside the
# devcontainer -- bazelisk is the only thing the suite really needs -- and the
# first version chose on `[ -d /goinfre ]` alone, falling back to /tmp. Two
# things were wrong with that away from campus: a /goinfre that exists but is
# not writable killed the run outright, and /tmp is a RAM-backed tmpfs on many
# Linux desktops, where a full build tree is that much memory.
#
# The sandbox has no /goinfre, so these pin the off-campus path: it lands in the
# cache directory (which survives a reboot, unlike /tmp), and it says so.
want_green "setup: off campus the cache lands somewhere persistent" -- \
	su_has 'output_user_root=.*/\.cache/42-piscine/bazel' "$WORK/su/repo/.bazelrc.local"

# ...and ON campus, in /goinfre/$USER: large, local, not quota'd, and per-user
# by its name. The choice is tools/drives.sh's, the same one tools/bazel makes
# for a checkout where setup.sh never ran and env-audit reports, so this arm
# pins the list all three read. A stand-in /goinfre, since the sandbox cannot
# make the real one.
rm -f "$WORK/su/repo/.bazelrc.local"
mkdir -p "$WORK/su/goinfre"
! st_mine || su_env C_PISCINE_GOINFRE="$WORK/su/goinfre" "$SH" tools/setup.sh > /dev/null 2>&1
want_green "setup: on campus the cache lands in /goinfre/\$USER" -- \
	su_has "output_user_root=$WORK/su/goinfre/probe/bazel\$" "$WORK/su/repo/.bazelrc.local"

# And re-running after an upgrade must not RELOCATE it. The candidate order has
# already changed once; without this every existing install would quietly move
# and re-download 2.1 GB of pinned tools while the old tree kept the space.
mkdir -p "$WORK/su/keep"
printf 'startup --output_user_root=%s/bazel\n' "$WORK/su/keep" > "$WORK/su/repo/.bazelrc.local"
# The line that says so is the proof this branch ran: a setup.sh that died
# early leaves the file as it was written above.
want_out "setup: a recorded root is said to be already chosen" \
	"already chosen for this checkout" -- su_run "$SU_SHA"
want_green "setup: and a second run keeps the choice already made" -- \
	su_has "output_user_root=$WORK/su/keep/bazel" "$WORK/su/repo/.bazelrc.local"

# ...including one this script did NOT write. The branch above says, in its own
# output, ".bazelrc.local: already sets output_user_root -- left alone", so a
# root without setup.sh's `/bazel` suffix is a state the repo produces on
# purpose. The sticky read was anchored to `/bazel$` and matched only setup.sh's
# own output, so on the next run that path went unread and the candidate list
# chose somewhere else -- leaving the free-space check, the tmpfs warning and
# prime.sh's sentinel all describing a directory Bazel does not use.
mkdir -p "$WORK/su/hand"
printf 'startup --output_user_root=%s\n' "$WORK/su/hand" > "$WORK/su/repo/.bazelrc.local"
want_out "setup: a hand-written output_user_root is honoured" \
	"$WORK/su/hand  -- already chosen" -- su_run "$SU_SHA"

# HOW MUCH ROOM A FULL RUN TAKES is tools/drives.sh's DRIVES_FULL_GB, and both
# scratch warnings print it; the free-space one fires below twice that figure.
# A df that puts the scratch on tmpfs with exactly that many gigabytes free
# gets both warnings, each with the figure; twice as many, on a disk, gets
# neither. The df is a toy: the sandbox cannot make a filesystem of a given
# size.
_su_gb=$("$SH" -c '. "$1" && printf %s "$DRIVES_FULL_GB"' _ "$TOOLS/drives.sh")
mkdir -p "$WORK/su/df"
{
	printf '#!/bin/sh\ncase "$*" in\n'
	printf '*-T*) echo "Filesystem Type 1024-blocks Used Available Capacity Mounted"\n'
	printf '\techo "/dev/toy $SU_DF_FS 999999999 0 $SU_DF_KB 0%% /" ;;\n'
	printf '*) echo "Filesystem 1024-blocks Used Available Capacity Mounted"\n'
	printf '\techo "/dev/toy 999999999 0 $SU_DF_KB 0%% /" ;;\nesac\n'
} > "$WORK/su/df/df"
chmod +x "$WORK/su/df/df"
su_df() {  # su_df FS GB -- setup.sh, its scratch on FS with GB gigabytes free
	( PATH="$WORK/su/df:$PATH" SU_DF_FS=$1 SU_DF_KB=$(($2 * 1048576))
	  export PATH SU_DF_FS SU_DF_KB
	  su_run "$SU_SHA" )
}
want_out "setup: a scratch in RAM is warned of, with the figure" \
	"A full run of this repo is ~$_su_gb GB and would be held in memory." -- \
	su_df tmpfs "$_su_gb"
want_out "setup: ...and a full run's room, with the figure" \
	"A full run of this repo is ~$_su_gb GB. Testing one module at a" -- \
	su_df tmpfs "$_su_gb"
want_broken_none "setup: ...never twice that, on a disk" \
	"A full run of this repo is" -- su_df ext4 "$((_su_gb * 2))"
# ...where setup.sh runs to its end: a run that died before the free-space
# check says nothing either.
want_green "setup: ...which runs green there" -- su_df ext4 "$((_su_gb * 2))"

# AND IT REPAIRS A CACHED TOOLCHAIN THAT POINTS AT A TOOL THAT IS GONE.
#
# A campus box could not link after uninstalling Homebrew: Bazel had recorded
# ~/.linuxbrew/bin/ar in local_config_cc when it auto-detected the toolchain,
# detection does not re-run because PATH changed, and every link then died with
# "execvp(...): No such file or directory". setup.sh is what a stuck student is
# told to re-run, so it is where this gets FIXED rather than merely named.
mkdir -p "$WORK/su/keep2"
printf 'startup --output_user_root=%s/keep2/bazel\n' "$WORK/su" > "$WORK/su/repo/.bazelrc.local"
_sucd="$WORK/su/keep2/bazel/abc123/external/rules_cc++cc_configure_extension+local_config_cc"
# The BUILD as rules_cc writes it (read off one this machine's Bazel
# generated): tool_paths opens with its first pair, takes one pair a line,
# and closes on the last. Written on one line, as every fixture here once
# was, it hid that the repair read no path at all from the real file.
su_ccbuild() {  # su_ccbuild AR LD -- $_sucd's BUILD, its ar at AR and its ld at LD
	mkdir -p "$_sucd"
	printf 'cc_toolchain_config(\n    name = "local",\n    cxx_builtin_include_directories = ["/usr/include",\n    "/usr/include/c++/10"],\n    tool_paths = {"ar": "%s",\n        "ld": "%s",\n        "cpp-module-deps-scanner": "deps_scanner_wrapper.sh",\n        "validate_static_library": "validate_static_library.sh"},\n    compile_flags = ["-fstack-protector",\n    "-Wall"],\n)\n' \
		"$1" "$2" > "$_sucd/BUILD"
}
su_ccbuild /nonexistent/brew/bin/ar /bin/sh
: > "$_sucd.marker"
! st_mine || su_run "$SU_SHA" > /dev/null 2>&1
want_green "setup: repairs a toolchain pointing at a gone tool" -- su_gone "$_sucd/BUILD"
# ...on whichever line of the dict the gone tool is.
su_ccbuild /bin/sh /nonexistent/brew/bin/ld
! st_mine || su_run "$SU_SHA" > /dev/null 2>&1
want_green "setup: repairs a toolchain whose gone tool is on a later line" -- su_gone "$_sucd/BUILD"

# ...and it must NOT delete a healthy one. Re-detection is cheap but not free,
# and a step that fires on every run would be indistinguishable from a bug.
su_ccbuild /bin/sh /bin/sh
# Its line is the proof the loop looked at it: the BUILD file stays as
# well when setup.sh dies before the loop, or inside it.
want_out "setup: a healthy cached toolchain is said to resolve" \
	"every cached tool path still resolves" -- su_run "$SU_SHA"
want_green "setup: leaves a healthy cached toolchain alone" -- test -e "$_sucd/BUILD"

# An unwritable C_PISCINE_SCRATCH must say so rather than fall through to a
# directory the user did not ask for: they named a disk for a reason.
mkdir -p "$WORK/su/ro" && chmod 555 "$WORK/su/ro"
# want_red plus want_out, not want_broken: setup.sh is an installer and its
# `die` exits 1 for everything, which is right for a script whose reader is a
# person at a prompt rather than a test harness reading a status.
su_ro() { su_env C_PISCINE_SCRATCH="$WORK/su/ro/x" "$SH" tools/setup.sh; }
want_red "setup: an unwritable C_PISCINE_SCRATCH stops rather than guessing" -- su_ro
want_out "setup: and names the variable it could not use" \
	'C_PISCINE_SCRATCH is set to' -- su_ro

# A RELATIVE C_PISCINE_SCRATCH stops too, at once and saying why. It hung:
# setup.sh predicts the old root before anything else, the prediction walks up
# the path to a directory that exists, and `${p%/*}` of a word with no slash is
# the word -- so `C_PISCINE_SCRATCH=myscratch sh tools/setup.sh` looped with no
# output at all, and init and env_drift on campus with it. Bounded, because
# the failure being pinned is a hang: 124 from `timeout` is want_red's "harness
# error", which fails the arm. Without `timeout` the arms run unbounded.
su_rel() { su_env --bound 60 C_PISCINE_SCRATCH=myscratch "$SH" tools/setup.sh; }
want_red "setup: a relative C_PISCINE_SCRATCH stops, and never hangs" -- su_rel
want_out "setup: ...and says it must be absolute" \
	"C_PISCINE_SCRATCH is set to 'myscratch', which must be an absolute path" -- su_rel
want_green "setup: ...leaving no directory of that name behind" -- \
	test ! -e "$WORK/su/repo/myscratch"
# The predicting walk itself ends for any path it is handed, relative or not.
su_walk() { bounded 60 "$SH" -c '. "$1" && DRIVES_DRY=1 drives_probe no-such/rel/dir' _ "$WORK/su/repo/tools/drives.sh"; }
want_green "drives: a dry probe of a relative path ends" -- su_walk
# Below a plain file, mkdir -p fails, for root too: the prediction says so
# as well. It used to walk past the file to the folder above and call the
# path creatable, so tools/bazel and postcreate.sh stayed silent on a root
# 42 doctor blocked on.
: > "$WORK/su/plain"
su_dry() { "$SH" -c '. "$1" && DRIVES_DRY=1 drives_probe "$2"' _ "$WORK/su/repo/tools/drives.sh" "$1"; }
su_real() { "$SH" -c '. "$1" && drives_probe "$2"' _ "$WORK/su/repo/tools/drives.sh" "$1"; }
want_red "drives: a dry probe below a plain file fails" -- su_dry "$WORK/su/plain/x/bazel"
want_red "drives: ...as the real probe does" -- su_real "$WORK/su/plain/x/bazel"
want_green "drives: ...and a dry probe beside it, below a folder, passes" -- \
	su_dry "$WORK/su/beside/x/bazel"

# The root .bazelrc.local records, read the way every script reads it.
su_root() { "$SH" -c '. "$1/tools/drives.sh" && drives_file_root "$1/.bazelrc.local"' _ "$WORK/su/repo"; }
su_is() { [ "$(su_root)" = "$1" ]; }

# C_PISCINE_SCRATCH OVER A RECORDED ROOT. It is the one way to move a root on
# purpose, and the command the campus warning prints -- but it moved only the
# scratch: .bazelrc.local's old root stayed in force, "left alone", so doing
# what the warning said changed nothing. The old lines stay, as comments.
mkdir -p "$WORK/su/moved"
printf 'startup --output_user_root=%s/keep/bazel
build --disk_cache=%s/keep/bazel-disk
' \
	"$WORK/su" "$WORK/su" > "$WORK/su/repo/.bazelrc.local"
! st_mine || su_env env C_PISCINE_SCRATCH="$WORK/su/moved" "$SH" tools/setup.sh > /dev/null 2>&1
want_green "setup: C_PISCINE_SCRATCH moves a recorded root" -- su_is "$WORK/su/moved/bazel"
want_green "setup: ...and the disk cache with it" -- \
	test "$(grep '^build --disk_cache=' "$WORK/su/repo/.bazelrc.local" | tail -n 1)" = \
	"build --disk_cache=$WORK/su/moved/bazel-disk"
want_green "setup: ...keeping the old line as a comment" -- \
	grep -qF "# replaced by tools/setup.sh: startup --output_user_root=$WORK/su/keep/bazel" \
	"$WORK/su/repo/.bazelrc.local"

# A .bazelrc.local with the cap and no disk cache gets the disk cache. The
# line was looked for by the bare word disk_cache, which the cap's flag
# holds too, so that file never got one.
printf 'startup --output_user_root=%s/keep/bazel\nbuild --experimental_disk_cache_gc_max_size=4G\n' \
	"$WORK/su" > "$WORK/su/repo/.bazelrc.local"
! st_mine || su_run "$SU_SHA" > /dev/null 2>&1
want_green "setup: a cap with no disk cache gets the disk cache" -- \
	grep -q '^build --disk_cache=' "$WORK/su/repo/.bazelrc.local"
want_green "setup: ...and the cap stays the only one" -- \
	sh -c '[ "$(grep -c -- "--experimental_disk_cache_gc_max_size=" "$1")" = 1 ]' _ \
	"$WORK/su/repo/.bazelrc.local"

# A ROOT ~/.bazelrc SETS is read after .bazelrc.local and wins over whatever
# this script records there. It said nothing, and Bazel went on using the other
# root; it reads the root back now and names the file that won.
printf 'startup --output_user_root=%s/elsewhere
' "$WORK/su" > "$WORK/su/home/.bazelrc"
want_out "setup: a root ~/.bazelrc sets over its own is named" \
	"$WORK/su/home/.bazelrc sets output_user_root=$WORK/su/elsewhere" -- su_run "$SU_SHA"
rm -f "$WORK/su/home/.bazelrc"

# THE WRAPPER'S EXCEPTION, here too. Off campus, a checkout that never had a
# .bazelrc.local runs on the old /tmp/bazelcache when it is already yours, and
# tools/bazel keeps it there so that nobody's state moved (its arms below).
# setup.sh chose the cache dir and recorded it, which moved it after all: 2 GB
# fetched again, and the server on the old root left running. Now it records no
# root while the wrapper keeps one, and says so.
rm -f "$WORK/su/repo/.bazelrc.local"
# The old root holds this checkout's output base: the folder Bazel writes
# DO_NOT_BUILD_HERE in, naming its workspace (an empty one is not kept, the
# wrapper's arms below).
mkdir -p "$WORK/su/legacy/base"
printf '%s' "$WORK/su/repo" > "$WORK/su/legacy/base/DO_NOT_BUILD_HERE"
want_out "setup: off campus, the old root it already uses is kept" \
	"tools/bazel keeps $WORK/su/legacy" -- \
	su_env env C_PISCINE_CAMPUS=0 C_PISCINE_LEGACY_ROOT="$WORK/su/legacy" "$SH" tools/setup.sh
want_green "setup: ...and no root is recorded over it" -- su_is ""
rm -rf "$WORK/su/legacy"

# FOLLOWING THE CAMPUS WARNING MOVES THE ROOT, end to end. init (and env_drift)
# warn on a campus box whose checkout keeps its state in the quota'd home. The
# advice was "bazel shutdown; sh tools/setup.sh", and setup.sh kept the root it
# had recorded, so it changed nothing. Here: a root recorded in the home, as
# setup chose it before /goinfre could be written; init on "campus" must name
# the command; that command, run as printed, must move the root; and init must
# then be quiet.
mkdir -p "$WORK/su/goinfre2"
printf 'startup --output_user_root=%s/home/.cache/42-piscine/bazel
' "$WORK/su" \
	> "$WORK/su/repo/.bazelrc.local"
# In the folder this file runs in, not the sandbox's: $TOOLS is relative
# under Bazel.
su_init() {
	su_in . C_PISCINE_CAMPUS=1 C_PISCINE_GOINFRE="$WORK/su/goinfre2" \
		BUILD_WORKSPACE_DIRECTORY="$WORK/su/repo" GIT_CEILING_DIRECTORIES="$WORK" \
		"$SH" "$TOOLS/init.sh" --login probe --email probe@42.fr
}
want_out "setup: the campus warning names the command that moves it" \
	"C_PISCINE_SCRATCH=$WORK/su/goinfre2/probe sh tools/setup.sh" -- su_init
want_out "setup: ...and how big a full build is, from drives.sh" \
	"a full build alone is about $_su_gb GB" -- su_init
if st_mine; then
	_su_to=$(su_init 2>&1 | sed -n 's/^ *C_PISCINE_SCRATCH=\([^ ]*\) sh tools\/setup\.sh$/\1/p' | tail -n 1)
	su_env env C_PISCINE_CAMPUS=1 C_PISCINE_GOINFRE="$WORK/su/goinfre2" \
		C_PISCINE_SCRATCH="${_su_to:-$WORK/su/nothing-printed}" "$SH" tools/setup.sh > /dev/null 2>&1
fi
want_green "setup: ...which records the new root" -- su_is "$WORK/su/goinfre2/probe/bazel"
want_broken_none "setup: ...and init is quiet after it" 'WARNING: Bazel keeps' -- su_init
# ...and a root ~/.bazelrc sets is named, with its line to delete first:
# setup.sh cannot override that file (the arm above), so advice without the
# step would change nothing.
printf 'startup --output_user_root=%s/home/.cache/other\n' "$WORK/su" > "$WORK/su/home/.bazelrc"
want_out "setup: the warning names a ~/.bazelrc line to delete" \
	"delete the output_user_root line from $WORK/su/home/.bazelrc" -- su_init
rm -f "$WORK/su/home/.bazelrc"

rm -rf "$WORK/su/home/.local"
want_red   "setup: a checksum mismatch is refused" -- \
	su_run 0000000000000000000000000000000000000000000000000000000000000000
want_green "setup: the rejected file is not left installed" -- \
	su_gone "$WORK/su/home/.local/bin/bazelisk"

