#!/bin/sh
# setup.sh — from a fresh clone to a machine that can run the suite, in one
# command. Run it once per machine:
#
#     sh tools/setup.sh
#
# Then open a new shell (or `. ~/.bashrc`) and:
#
#     bazel run //tools:prime      # optional, but see WHY PRIME below
#     bazel test //c-piscine-c-00:basic
#
# It is the only part of this repo that runs BEFORE Bazel exists, so it cannot
# use any of the machinery everything else relies on. That constraint shapes all
# of it: POSIX sh, no bashisms, and nothing assumed present beyond a shell, git
# and one of three ways to fetch a file.
#
# WHAT IT DOES, and WHERE THE FULL STORY IS.
#
# docs/environment.md carries the user-facing account: the four steps, the
# scratch-path search order, the size table, and what to do when a build dies
# naming nothing. It is written for someone about to run this, which is a reader
# who will never open this file -- so it lives there, and this header keeps only
# what someone EDITING the script needs.
#
#   1. bazelisk into ~/.local/bin, sha256-verified before it is made executable.
#      Not Bazel: bazelisk reads .bazelversion, so the launcher's own version
#      never matters. A bare `bazel` on PATH is deliberately NOT accepted --
#      real Bazel ignores .bazelversion.
#   2. Bazel's state somewhere with room, chosen by TRYING candidates in order
#      and probing each for real writability. The earlier version picked
#      /goinfre on existence alone and then died if it was not writable, with no
#      route forward.
#   3. Those paths into the shell profile, between markers, idempotently.
#   4. //tools:env_drift, which on a campus box answers the question that is
#      otherwise only asked when somebody remembers to.
#
# THREE THINGS THAT CONSTRAIN EVERY EDIT HERE:
#
#   * It runs BEFORE Bazel exists, so it cannot use any of the machinery the
#     rest of the repo relies on: POSIX sh, no bashisms, nothing assumed present
#     beyond a shell, git and one of three ways to fetch a file.
#   * It must stay idempotent, and STICKY: re-running it reads the path already
#     in .bazelrc.local and keeps it. The candidate order has changed once
#     already, and without this every existing install would have silently
#     relocated and re-downloaded 2.1 GB. Idempotence is one of its tested
#     properties, so it has to survive its own edits.
#   * It writes the LOGIN shell's rc file even when that file does not exist.
#     The 2026-08-09 campus audit found the login shell there was /bin/zsh;
#     writing only to files that already exist would have put the block in
#     .bashrc, which zsh never reads, and the whole script would have appeared
#     to work.
#
# NOT DONE HERE, deliberately: your 42 identity. That is `bazel run //tools:init`,
# which needs Bazel, and it asks questions -- this script asks none.

set -eu

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "setup.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk basename cat chmod cut dirname grep id ln mkdir mktemp mv rm sed tail
# conventions: optional python3 -- last resort in both fallback chains below
# (download: wget, curl, then python3; digest: sha256sum, shasum, then python3).
# conventions: optional sha256sum -- first choice of the digest chain; shasum
# and python3 follow. Having all three absent is what the chain reports on.

# ---------------------------------------------------------------------------
# The pins. bazelisk's version does not have to match anyone else's (it reads
# .bazelversion), but the BYTES do: a checksum is the only thing standing
# between "we downloaded a launcher" and "we downloaded and executed whatever
# that URL served today".
BAZELISK_VERSION=v1.29.0
BAZELISK_SHA256=5a408715e932c0250d28bd84555f12edbf70117de42f9181691c736eacc4a992
BAZELISK_URL="https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-linux-amd64"

# Three overrides, and they exist so that //tools/tests:selftest can drive this
# script OFFLINE -- with a file:// URL and a fixture of known hash it can check
# that a good download installs, that a bad one is REFUSED, and that a second
# run does not duplicate the profile block. Without them the only script every
# user runs would be the only one nothing tests, which is the failure mode this
# repo treats as its worst. They are not a supported way to install something
# else: the checksum still has to match, whatever it is set to.
BAZELISK_URL="${SETUP_BAZELISK_URL:-$BAZELISK_URL}"
BAZELISK_SHA256="${SETUP_BAZELISK_SHA256:-$BAZELISK_SHA256}"
SKIP_DRIFT="${SETUP_SKIP_DRIFT:-0}"

MARK_BEGIN="# >>> 42 c-piscine setup >>>"
MARK_END="# <<< 42 c-piscine setup <<<"

say()  { printf '  %s\n' "$*"; }
die()  { printf 'setup.sh: %s\n' "$*" >&2; exit 1; }

WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$WS" || die "cannot enter '$WS'"
[ -f .bazelversion ] || die "this does not look like the repo root ($WS): no .bazelversion"

printf 'setup: preparing this machine for %s\n\n' "$WS"

# ---------------------------------------------------------------------------
# 1. Where the big, rebuildable state goes.
# CANDIDATES, TRIED IN ORDER, and each one has to actually WORK -- the earlier
# version picked on `[ -d /goinfre ]` alone and then died if the directory was
# not writable, which is a plausible state off campus (a stale mount, a
# root-owned leftover) and left someone stuck with no route forward.
#
# The order encodes where the state is least in the way:
#   1. C_PISCINE_SCRATCH  -- you said so; nothing overrules that.
#   2. /goinfre/$USER     -- a 42 box: large, local, not quota'd. This is the
#                            same test tools/env_drift.sh uses to detect campus.
#   3. $XDG_CACHE_HOME or ~/.cache -- ANY OTHER MACHINE. $HOME was avoided for
#                            the campus quota, which does not exist on your own
#                            computer; and unlike /tmp it survives a reboot, so
#                            the 2.1 GB of pinned downloads is fetched once
#                            rather than every time you restart.
#   4. /tmp/$USER         -- last resort. Per-user on purpose: /tmp is shared,
#                            and two people on one path fight over the same lock.
USER_NAME="${USER:-$(id -un)}"
try_scratch() {
	mkdir -p "$1" 2> /dev/null || return 1
	[ -w "$1" ] || return 1
	# Writable by mode is not the same as writable in fact -- a full or
	# read-only mount passes `-w` and fails on the first byte.
	( : > "$1/.setup-probe" ) 2> /dev/null || return 1
	rm -f "$1/.setup-probe"
	return 0
}

SCRATCH=""

# BEFORE ANY CANDIDATE: if this machine already made the choice, keep it.
#
# Re-running setup after an upgrade must not silently relocate the cache. The
# candidate order below changed once already, and without this every existing
# install would have quietly moved to a new directory and re-downloaded 2.1 GB
# of pinned tools while the old tree sat there taking the same space. Idempotence
# is one of this script's tested properties; it has to survive its own edits.
if [ -z "${C_PISCINE_SCRATCH:-}" ] && [ -f "$WS/.bazelrc.local" ]; then
	# Any output_user_root line, not only the one written below. This was
	# anchored to `/bazel$`, so it recognised setup.sh's OWN output and nothing
	# else -- and the branch at "3." below deliberately LEAVES A HAND-WRITTEN
	# ONE ALONE, saying so. On the next run that path went unread, the candidate
	# list chose somewhere else, and everything downstream -- the free-space
	# warning, the filesystem warning, prime.sh's sentinel -- described a
	# directory Bazel does not use. The trailing `/bazel` is stripped if it is
	# there, because that suffix is this script's convention rather than Bazel's.
	PREV=$(sed -n \
		's|^startup[[:blank:]]*--output_user_root=\([^[:blank:]]*\).*|\1|p' \
		"$WS/.bazelrc.local" | tail -n 1)
	PREV=${PREV%/bazel}
	if [ -n "$PREV" ] && try_scratch "$PREV"; then
		SCRATCH="$PREV"
		WHERE="already chosen on this machine (.bazelrc.local)"
	fi
fi

if [ -z "$SCRATCH" ] && [ -n "${C_PISCINE_SCRATCH:-}" ]; then
	try_scratch "$C_PISCINE_SCRATCH" &&
		{ SCRATCH="$C_PISCINE_SCRATCH"; WHERE="from C_PISCINE_SCRATCH"; }
	[ -n "$SCRATCH" ] ||
		die "C_PISCINE_SCRATCH is set to '$C_PISCINE_SCRATCH', which cannot be written to."
fi
if [ -z "$SCRATCH" ] && [ -d /goinfre ]; then
	try_scratch "/goinfre/$USER_NAME" &&
		{ SCRATCH="/goinfre/$USER_NAME"; WHERE="/goinfre (42 box: large, local, not quota'd)"; }
fi
if [ -z "$SCRATCH" ]; then
	CACHE_ROOT="${XDG_CACHE_HOME:-${HOME:-}/.cache}"
	case "$CACHE_ROOT" in
		/*)
			try_scratch "$CACHE_ROOT/42-piscine" &&
				{ SCRATCH="$CACHE_ROOT/42-piscine"; WHERE="your cache dir (persists across reboots)"; }
			;;
	esac
fi
if [ -z "$SCRATCH" ]; then
	try_scratch "/tmp/$USER_NAME" &&
		{ SCRATCH="/tmp/$USER_NAME"; WHERE="/tmp (last resort -- cleared on reboot)"; }
fi
[ -n "$SCRATCH" ] || die "no writable place for Bazel's state. Set C_PISCINE_SCRATCH to one."
say "scratch:  $SCRATCH  -- $WHERE"

# Two ways this goes wrong quietly, both worth one line of warning rather than
# a failure -- the build may well be smaller than the full suite, and it is not
# this script's place to refuse.
#
# RAM-BACKED. Many Linux desktops mount /tmp as tmpfs sized at half of RAM. An
# 8.9 GB build tree there is 8.9 GB of memory, and the machine starts swapping
# or the OOM killer arrives -- neither of which reads as "the cache is in RAM".
# Campus /tmp and the devcontainer's are disk-backed, so this only ever fires
# off campus, which is exactly the case nobody was testing.
SCRATCH_FS=$(df -P -T "$SCRATCH" 2> /dev/null | awk 'NR == 2 { print $2 }')
case "$SCRATCH_FS" in
	tmpfs | ramfs)
		say ""
		say "WARNING: $SCRATCH is on $SCRATCH_FS, which lives in RAM."
		say "         A full run of this repo is ~8.9 GB and would be held in memory."
		say "         Point somewhere on disk instead:"
		say "             C_PISCINE_SCRATCH=\$HOME/.cache/42-piscine sh tools/setup.sh"
		say ""
		;;
esac

# NOT ENOUGH ROOM. The failure without this is a disk error partway through a
# build, which names the wrong cause; see the inode note in the header for the
# other half of that lesson.
SCRATCH_FREE_KB=$(df -P -k "$SCRATCH" 2> /dev/null | awk 'NR == 2 { print $4 }')
case "$SCRATCH_FREE_KB" in
	'' | *[!0-9]*) ;;
	*)
		if [ "$SCRATCH_FREE_KB" -lt 10485760 ]; then
			say ""
			say "WARNING: only $((SCRATCH_FREE_KB / 1024 / 1024)) GB free at $SCRATCH."
			say "         A full run of this repo is ~8.9 GB. Testing one module at a"
			say "         time needs far less, so this is a warning and not a refusal;"
			say "         set C_PISCINE_SCRATCH to somewhere roomier if it bites."
			say ""
		fi
		;;
esac

# ---------------------------------------------------------------------------
# 2. bazelisk into ~/.local/bin.
#
# ~/.local/bin because it needs no root, is on PATH by default on most distros,
# and lives in the one directory that follows you to another machine.
BINDIR="$HOME/.local/bin"
BAZELISK="$BINDIR/bazelisk"
mkdir -p "$BINDIR" || die "cannot create $BINDIR"

fetch() {
	# fetch URL DEST -- python3 first, because norminette is a Python package
	# and so python3 is the one fetcher a 42 box is guaranteed to have. curl is
	# NOT: it is absent from this repo's own devcontainer.
	_u="$1"; _d="$2"
	if command -v python3 >/dev/null 2>&1; then
		python3 -c 'import sys,urllib.request; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])' \
			"$_u" "$_d" && return 0
	fi
	if command -v wget >/dev/null 2>&1; then wget -q -O "$_d" "$_u" && return 0; fi
	if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$_d" "$_u" && return 0; fi
	return 1
}

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; return; fi
	if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; return; fi
	if command -v python3 >/dev/null 2>&1; then
		python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
		return
	fi
	echo ""
}

if [ -x "$BAZELISK" ] && [ "$(sha256_of "$BAZELISK")" = "$BAZELISK_SHA256" ]; then
	say "bazelisk: already installed and matches the pin"
else
	tmp="$BAZELISK.download.$$"
	rm -f "$tmp"
	say "bazelisk: downloading $BAZELISK_VERSION (~7 MB)"
	fetch "$BAZELISK_URL" "$tmp" || {
		rm -f "$tmp"
		die "could not download bazelisk -- none of python3, wget or curl worked.
                  Fetch it by hand from
                      $BAZELISK_URL
                  save it as $BAZELISK, chmod +x it, and re-run this script."
	}
	got=$(sha256_of "$tmp")
	[ -n "$got" ] || { rm -f "$tmp"; die "no sha256 tool available; cannot verify the download"; }
	if [ "$got" != "$BAZELISK_SHA256" ]; then
		rm -f "$tmp"
		die "bazelisk checksum MISMATCH -- refusing to install.
                  expected $BAZELISK_SHA256
                  got      $got"
	fi
	# Verified BEFORE it is made executable, so a bad download is never a file
	# the machine will run.
	chmod +x "$tmp" && mv -f "$tmp" "$BAZELISK" || { rm -f "$tmp"; die "installing bazelisk failed"; }
	say "bazelisk: installed to $BAZELISK (sha256 verified)"
fi

# `bazel` is what every doc and every habit types, and bazelisk is a drop-in.
if [ ! -e "$BINDIR/bazel" ]; then
	ln -sf bazelisk "$BINDIR/bazel" && say "bazelisk: linked as $BINDIR/bazel"
elif [ -L "$BINDIR/bazel" ]; then
	ln -sf bazelisk "$BINDIR/bazel"
else
	say "bazel:    $BINDIR/bazel exists and is not a symlink -- left alone"
fi

# ---------------------------------------------------------------------------
# 3. .bazelrc.local -- the one Bazel flag that moves the most state.
#
# NOT overwritten if it already exists: it is gitignored and per-machine, so it
# is the file most likely to hold something you set on purpose.
if [ -f .bazelrc.local ]; then
	if grep -q 'output_user_root' .bazelrc.local; then
		say ".bazelrc.local: already sets output_user_root -- left alone"
	else
		printf '\n# added by tools/setup.sh\nstartup --output_user_root=%s/bazel\n' "$SCRATCH" \
			>> .bazelrc.local
		say ".bazelrc.local: appended output_user_root"
	fi
else
	cat > .bazelrc.local <<EOF
# Written by tools/setup.sh. Per-machine, gitignored, yours to edit.
#
# One flag, three directories: the output base, the install base and the
# repository cache all live under it. A full run of this repo is 8.9 GB, and a
# 42 \$HOME is usually capped at 5 GB.
startup --output_user_root=$SCRATCH/bazel
EOF
	say ".bazelrc.local: written (output_user_root -> $SCRATCH/bazel)"

# ...and check that Bazel will actually READ it. `try-import` at the top of
# .bazelrc cannot override a startup option set below it -- Bazel keeps the last
# value it reads -- so the line just written would be accepted and then
# discarded. That was true in this repo for a long time, and the only symptom
# was that everything worked, in the wrong directory. A message a script prints
# about itself is not evidence.
IMPORT_LINE=$(grep -n '^try-import %workspace%/\.bazelrc\.local' "$WS/.bazelrc" 2> /dev/null |
	tail -n 1 | cut -d: -f1)
LAST_STARTUP=$(grep -n '^startup ' "$WS/.bazelrc" 2> /dev/null | tail -n 1 | cut -d: -f1)
if [ -n "$IMPORT_LINE" ] && [ -n "$LAST_STARTUP" ] && [ "$IMPORT_LINE" -lt "$LAST_STARTUP" ]; then
	say ""
	say "WARNING: .bazelrc imports .bazelrc.local on line $IMPORT_LINE, above the"
	say "         startup option on line $LAST_STARTUP -- so the redirect just written"
	say "         will be read and then discarded, and Bazel will use the path in"
	say "         .bazelrc instead. Move that try-import to the bottom of .bazelrc."
	say ""
fi
fi

# ---------------------------------------------------------------------------
# 4. The two paths that are ENVIRONMENT and not Bazel flags, into the profile.
#
# Between markers so a second run replaces the block instead of appending one.
# Every shell that could be the login shell gets it: a student who runs this
# under bash and then logs in under zsh would otherwise find nothing set.
block() {
	cat <<EOF
$MARK_BEGIN
# 42 C Piscine. Re-run 'sh tools/setup.sh' to update; edit inside these markers
# and it will be overwritten.
export PATH="\$HOME/.local/bin:\$PATH"
# Where bazelisk keeps the Bazel it downloads (~63 MB), instead of \$HOME/.cache.
export BAZELISK_HOME="$SCRATCH/bazelisk"
# //tools:submit runs its pre-push gate on a separate output base and passes
# --output_base explicitly, which overrides --output_user_root -- so this is the
# one path that flag cannot move.
export SUBMIT_GATE_OUTPUT_BASE="$SCRATCH/bazel-gate"
# Warm the build cache once per machine, in the background, the first time you
# open a terminal. It uses its own Bazel output base, so it CANNOT block a
# command you type; what it fills is the shared 2.1 GB download cache. Delete
# this line, or export NO_C_PISCINE_PRIME=1, to turn it off.
case \$- in
	*i*) [ -n "\${NO_C_PISCINE_PRIME:-}" ] || [ ! -x "$WS/tools/prime.sh" ] ||
		sh "$WS/tools/prime.sh" --background ;;
esac
$MARK_END
EOF
}

install_block() {
	_rc="$1"
	[ -e "$_rc" ] || : > "$_rc" || return 1
	if grep -qF "$MARK_BEGIN" "$_rc" 2>/dev/null; then
		_t="$_rc.setup.$$"
		awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
			index($0, b) { skip = 1 }
			!skip { print }
			index($0, e) { skip = 0 }
		' "$_rc" > "$_t" || return 1
		# Drop a trailing blank run left behind, so repeated runs cannot grow the file.
		awk 'BEGIN{n=0} {lines[NR]=$0} END{last=NR; while (last>0 && lines[last]=="") last--; for(i=1;i<=last;i++) print lines[i]}' \
			"$_t" > "$_t.2" && mv -f "$_t.2" "$_t" || return 1
		{ printf '\n'; block; } >> "$_t" || return 1
		mv -f "$_t" "$_rc" || return 1
		printf 'updated'
	else
		{ printf '\n'; block; } >> "$_rc" || return 1
		printf 'added'
	fi
}

# THE LOGIN SHELL'S rc FILE IS WRITTEN EVEN IF IT DOES NOT EXIST YET. Everything
# else here is written only if it already exists, because creating a ~/.zshrc on
# a machine whose owner does not use zsh is clutter at best and at worst changes
# which file a login shell reads.
#
# But the login shell is the one that decides whether ANY of this took effect,
# and a fresh account may not have its rc file yet. The 2026-08-09 campus audit
# is what turned that from a theory into a bug: on the box audited there, the
# login shell is /bin/zsh (bash, zsh, fish and dash are all installed). Writing
# only to files that exist would have put the block in .bashrc, which zsh never
# reads -- so PATH and the two cache variables would silently not be set, and
# the whole script would appear to have worked.
login_sh=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)
[ -n "$login_sh" ] || login_sh="${SHELL:-}"
case "${login_sh##*/}" in
	zsh)  login_rc="$HOME/.zshrc" ;;
	bash) login_rc="$HOME/.bashrc" ;;
	ksh|mksh) login_rc="$HOME/.kshrc" ;;
	# fish has its own syntax and would not understand the block; sh/dash read
	# .profile. Neither gets a file conjured for it.
	*)    login_rc="" ;;
esac

touched=""
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.kshrc"; do
	if [ ! -f "$rc" ]; then
		[ "$rc" = "$login_rc" ] || continue
		: > "$rc" || die "could not create $rc"
		what=$(install_block "$rc") || die "could not write $rc"
		touched="$touched $(basename "$rc")($what, created -- your login shell)"
		continue
	fi
	what=$(install_block "$rc") || die "could not write $rc"
	touched="$touched $(basename "$rc")($what)"
done
if [ -z "$touched" ]; then
	# No profile at all and a login shell this script cannot write for -- fish,
	# say. bash is the safe default: it is what .devcontainer gives you and what
	# the docs assume, and a ~/.bashrc nobody reads costs nothing.
	what=$(install_block "$HOME/.bashrc") || die "could not write $HOME/.bashrc"
	touched=" .bashrc($what, created -- no shell profile existed)"
fi
say "profile:$touched"
case "${login_sh##*/}" in
	fish)
		say "NOTE: your login shell is fish, whose syntax this block does not use."
		say "      Add these to ~/.config/fish/config.fish by hand:"
		say "        set -gx PATH \$HOME/.local/bin \$PATH"
		say "        set -gx BAZELISK_HOME $SCRATCH/bazelisk"
		say "        set -gx SUBMIT_GATE_OUTPUT_BASE $SCRATCH/bazel-gate" ;;
esac

# Make this shell match, so the env_drift run below and anything the student
# types next work without opening a new terminal.
PATH="$BINDIR:$PATH"
BAZELISK_HOME="$SCRATCH/bazelisk"
SUBMIT_GATE_OUTPUT_BASE="$SCRATCH/bazel-gate"
export PATH BAZELISK_HOME SUBMIT_GATE_OUTPUT_BASE

# ---------------------------------------------------------------------------
# 5. Compare this machine against the pins.
#
# This is the whole point of running it HERE: on a campus box it answers "have
# they upgraded anything since we pinned?", from the box that decides the
# answer. It warns and never fails -- a student who sat at an upgraded machine
# has done nothing wrong, and blocking their first run over it would be absurd.
if [ "$SKIP_DRIFT" = "1" ]; then
	printf '\n'
	say "skipping the pins check (SETUP_SKIP_DRIFT=1)"
	printf '\nsetup: done.\n'
	exit 0
fi
printf '\n'
_drift_out=$(mktemp)
say "checking this machine against tools/pins.tsv (warnings only)..."
printf '\n'
# The status tested has to be BAZELISK's, not sed's. `if ! cmd | sed ...` tests
# the last command in the pipeline, and sed succeeds whatever it was fed -- so
# step 4 of the four this script advertises could fail completely and the run
# still printed "setup: done." with no hint that a check had not happened.
"$BAZELISK" run //tools:env_drift > "$_drift_out" 2>&1
_drift_rc=$?
sed 's/^/  /' "$_drift_out"
rm -f "$_drift_out"
if [ "$_drift_rc" -ne 0 ]; then
	printf '\n'
	say "env_drift did not complete. That is not fatal: it needs Bazel, and this"
	say "is the first time Bazel has run here, so a slow or absent network is the"
	say "usual cause. Re-run it later with: bazel run //tools:env_drift"
fi

printf '\nsetup: done.\n\n'
say "Open a new shell (or: . ~/.bashrc) so PATH and the two variables take effect."
say "Then, in this order:"
say "  bazel run //tools:prime     # download and build everything, once (slow)"
say "  bazel run //tools:init      # your 42 login and email, for file headers"
say "  bazel test //c-piscine-c-00:basic"
