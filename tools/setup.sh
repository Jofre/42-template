#!/bin/sh
# setup.sh — from a fresh clone to a machine that can run the suite, in one
# command. Run it once in every checkout -- every clone and every worktree:
#
#     sh tools/setup.sh
#
# Once per CHECKOUT, not per machine: the Bazel root it chooses is written to
# .bazelrc.local, which is gitignored and belongs to the checkout it sits in.
# A second clone without one still gets a per-user root -- tools/bazel, the
# wrapper bazelisk runs, supplies the same choice (tools/drives.sh) -- but not
# the shared disk cache that lets tools/prime.sh's work reach your build.
# Re-running it is always safe: it is idempotent, and it keeps a choice
# already made -- unless C_PISCINE_SCRATCH names another, which it records.
#
# Then close the terminal and open a new one -- only a new one reads the PATH
# this writes into the login shell's rc file -- and, back in the checkout:
#
#     42 doctor
#     42 init
#
# Its last lines say the same, naming the rc file it wrote (next_steps below).
# They leave out `bazel run //tools:prime`: the profile block already starts
# it in the background (WHY IT EXISTS AT ALL, below), and priming has been
# reported to freeze a campus box for a long time.
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
#   2. Bazel's state somewhere with room, chosen by tools/drives.sh: candidates
#      TRIED in order, each probed for real writability. The earlier version
#      picked /goinfre on existence alone and then died if it was not writable,
#      with no route forward.
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
#     properties, so it has to survive its own edits. C_PISCINE_SCRATCH is the
#     one way to move it on purpose, and it does move it: the campus warning
#     in init and env_drift names that command.
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
require awk basename cat chmod cut dirname grep id ln mkdir mktemp mv rm sed tail tr
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
#
# CHOSEN BY tools/drives.sh, the one place the candidates live: the wrapper
# tools/bazel uses the same choice for a checkout where this script never ran,
# and tools/env-audit.sh reports what it decides on the box being audited. Its
# header has the order and the reasons. Each candidate is PROBED for real
# writability -- the first version picked /goinfre on existence alone and then
# died if it was not writable, a plausible state off campus (a stale mount, a
# root-owned leftover), leaving someone stuck with no route forward.
[ -r "$WS/tools/drives.sh" ] || die "tools/drives.sh is missing from $WS -- is this checkout complete?"
# shellcheck source=drives.sh
. "$WS/tools/drives.sh"

SCRATCH=""
# The output_user_root this checkout is to have: $SCRATCH/bazel, except where a
# root recorded by hand has no /bazel on the end.
ROOT=""
# 1 when .bazelrc.local's root line is to be replaced rather than kept.
REPLACE=0
# 1 when no root is recorded at all, because the wrapper is keeping this
# checkout's state where it already is (below).
KEEP_LEGACY=0

# What .bazelrc.local records, read the way tools/drives.sh reads every rc file
# (both of Bazel's spellings), not with a sed of this script's own.
#
# Any output_user_root line, not only the one written below. This was anchored
# to `/bazel$`, so it recognised setup.sh's OWN output and nothing else -- and
# the branch at "3." below deliberately LEAVES A HAND-WRITTEN ONE ALONE, saying
# so. On the next run that path went unread, the candidate list chose somewhere
# else, and everything downstream -- the free-space warning, the filesystem
# warning, prime.sh's sentinel -- described a directory Bazel does not use. The
# trailing `/bazel` is stripped where it is there, because that suffix is this
# script's convention rather than Bazel's.
PREV_ROOT=$(drives_file_root "$WS/.bazelrc.local")
# Where this checkout's state is before this run, predicted without creating
# anything, so that a move is said out loud at the end of step 3.
OLD_ROOT=$(drives_predicted_root "$WS")

if [ -n "${C_PISCINE_SCRATCH:-}" ]; then
	# YOU SAID SO, and that includes over a root recorded before. It used to be
	# honoured for everything but the one line that matters: the scratch became
	# C_PISCINE_SCRATCH while .bazelrc.local went on naming the old root, "left
	# alone". It is what the campus warning (init, env_drift) tells someone to
	# run, so it has to move the root.
	drives_choose || die "$DRIVES_WHY."
	SCRATCH=$DRIVES_SCRATCH
	WHERE=$DRIVES_WHY
	ROOT="$SCRATCH/bazel"
	[ -z "$PREV_ROOT" ] || [ "$PREV_ROOT" = "$ROOT" ] || REPLACE=1
elif [ -n "$PREV_ROOT" ] && drives_probe "${PREV_ROOT%/bazel}"; then
	# BEFORE ANY CANDIDATE: if this checkout already made the choice, keep it.
	#
	# Re-running setup after an upgrade must not silently relocate the cache.
	# The candidate order changed once already, and without this every existing
	# install would have quietly moved to a new directory and re-downloaded
	# 2.1 GB of pinned tools while the old tree sat there taking the same space.
	# Idempotence is one of this script's tested properties; it has to survive
	# its own edits.
	SCRATCH=${PREV_ROOT%/bazel}
	ROOT=$PREV_ROOT
	WHERE="already chosen for this checkout (.bazelrc.local)"
else
	# A recorded root that cannot be written any more is replaced: Bazel could
	# not use it either.
	[ -z "$PREV_ROOT" ] || REPLACE=1
	drives_choose || die "$DRIVES_WHY."
	SCRATCH=$DRIVES_SCRATCH
	WHERE=$DRIVES_WHY
	ROOT="$SCRATCH/bazel"
	# THE WRAPPER'S ONE EXCEPTION, kept here too. A checkout no rc file gives a
	# root runs on the one tools/bazel supplies, and off campus that is the old
	# /tmp/bazelcache when it is already yours (drives_default_root), so that
	# nobody's state moved. Recording $SCRATCH/bazel would move it after all: a
	# 2 GB download again, and a server left running on the old root. So no
	# root is recorded, the wrapper goes on keeping that one, and once it is
	# gone (a reboot clears /tmp) the wrapper moves to $SCRATCH/bazel by itself.
	# The scratch still takes the disk cache and the rest.
	if [ -z "$PREV_ROOT" ] && [ -z "$(drives_rc_root "$WS")" ] && drives_legacy_kept; then
		KEEP_LEGACY=1
		ROOT=$DRIVES_LEGACY
		WHERE="$WHERE; Bazel's own state stays in $ROOT, where it already is"
	fi
fi
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
# 2. bazelisk, and the `42` command, into ~/.local/bin.
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

# `42`, the front-end over the suite (tools/42.sh), as a shim beside them. The
# installer leaves alone a 42 it did not write; that costs the short name only
# (`sh tools/42.sh` works the same), so it never stops the setup.
{ sh "$WS/tools/fortytwo/install.sh" "$BINDIR" || :; } 2>&1 | sed 's/^/  /'

# ---------------------------------------------------------------------------
# 3. .bazelrc.local -- the one Bazel flag that moves the most state.
#
# NOT overwritten if it already exists: it is gitignored and per-checkout, so it
# is the file most likely to hold something you set on purpose.
# THE DISK CACHE IS CHECKED SEPARATELY from output_user_root, and it has to be:
# an install that predates this line has the one and not the other, and testing
# only for output_user_root would leave every existing machine without it
# forever.
#
# WHY IT EXISTS AT ALL. tools/prime.sh compiles the whole repo in the background
# into its OWN --output_base, so that it never holds the lock the student's
# interactive build needs. The compiled results reach that build through one
# route only -- a --disk_cache both of them pass. Until this was written, only
# prime.sh passed it: it filled a cache that nothing on earth ever read, so the
# entire `build //...` half of priming was thrown away, and the first
# interactive `bazel test` recompiled all of it. prime.sh's own comment claimed
# the opposite.
#
# BOUNDED, because a disk cache has no size limit by default and this one lives
# in scratch that a 42 $HOME caps at 5 GB. 4 GB holds this repo's outputs with
# room to spare, and Bazel collects it in the background once it is idle.
add_local_line() {  # add_local_line <grep-key> <line> <what>
	grep -q "$1" .bazelrc.local 2>/dev/null && return 0
	printf '\n# added by tools/setup.sh\n%s\n' "$2" >> .bazelrc.local
	say ".bazelrc.local: appended $3"
}

# Every line of .bazelrc.local setting what sed pattern $1 matches becomes a
# comment saying it was replaced, and $2 goes at the end, where it wins. Written
# back in place, like init's settings.json, so the file keeps mode and owner.
replace_local_line() {  # replace_local_line <sed-pattern> <line> <what>
	_rl=$(mktemp) || die "cannot create a temporary file"
	if sed "/$1/s|^|# replaced by tools/setup.sh: |" .bazelrc.local > "$_rl" &&
		printf '\n# added by tools/setup.sh\n%s\n' "$2" >> "$_rl" &&
		cat "$_rl" > .bazelrc.local; then
		rm -f "$_rl"
		say ".bazelrc.local: replaced $3"
	else
		rm -f "$_rl"
		die "could not rewrite .bazelrc.local"
	fi
}
ROOT_PAT='^[[:blank:]]*startup[[:blank:]].*--output_user_root'
DISK_PAT='^[[:blank:]]*build[[:blank:]].*--disk_cache[=[:blank:]]'

if [ -f .bazelrc.local ]; then
	if [ "$REPLACE" = 1 ]; then
		replace_local_line "$ROOT_PAT" "startup --output_user_root=$ROOT" \
			"output_user_root (it was $PREV_ROOT)"
		# The disk cache sat beside the old root, so it moves with it.
		if grep -q "$DISK_PAT" .bazelrc.local; then
			replace_local_line "$DISK_PAT" "build --disk_cache=$SCRATCH/bazel-disk" \
				"the disk cache, now $SCRATCH/bazel-disk"
		fi
	elif [ -n "$PREV_ROOT" ]; then
		say ".bazelrc.local: already sets output_user_root -- left alone"
	elif [ "$KEEP_LEGACY" = 1 ]; then
		say ".bazelrc.local: no output_user_root -- tools/bazel keeps $ROOT"
	else
		add_local_line "$ROOT_PAT" \
			"startup --output_user_root=$ROOT" "output_user_root"
	fi
	add_local_line 'disk_cache' \
		"build --disk_cache=$SCRATCH/bazel-disk" "the shared disk cache"
	add_local_line 'disk_cache_gc_max_size' \
		"build --experimental_disk_cache_gc_max_size=4G" "a 4G cap on that cache"
else
	if [ "$KEEP_LEGACY" = 1 ]; then
		ROOT_LINES="# No output_user_root here: this checkout's Bazel state is in
# $ROOT, where it already was, and tools/bazel keeps it there
# (yours, off campus). Once that folder is gone, the wrapper moves it to
# $SCRATCH/bazel by itself."
	else
		ROOT_LINES="startup --output_user_root=$ROOT"
	fi
	cat > .bazelrc.local <<EOF
# Written by tools/setup.sh. For THIS checkout only (every clone and worktree
# has its own), gitignored, yours to edit.
#
# One flag, three directories: the output base, the install base and the
# repository cache all live under it. A full run of this repo is 8.9 GB, and a
# 42 \$HOME is usually capped at 5 GB.
$ROOT_LINES

# How the background prime's work reaches this build.
#
# tools/prime.sh builds into its own --output_base so it never holds the lock
# this build needs -- which means its compiled outputs are in a tree nothing
# else opens. They arrive here through this cache and nowhere else, so without
# this line the whole build half of priming is discarded and the first
# \`bazel test\` compiles everything again.
#
# Capped, because a disk cache grows without limit by default and scratch is
# quota'd. Bazel collects it once idle.
build --disk_cache=$SCRATCH/bazel-disk
build --experimental_disk_cache_gc_max_size=4G
EOF
	if [ "$KEEP_LEGACY" = 1 ]; then
		say ".bazelrc.local: written (no output_user_root: tools/bazel keeps $ROOT; disk cache -> $SCRATCH/bazel-disk)"
	else
		say ".bazelrc.local: written (output_user_root -> $ROOT, disk cache -> $SCRATCH/bazel-disk)"
	fi

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

# THE ROOT BAZEL WILL USE, read back from every rc file the way drives.sh reads
# them, against the one just recorded -- for the same reason as the check
# above. ~/.bazelrc is read AFTER .bazelrc.local, so a root set there wins
# whatever this script writes; and following the campus warning's advice used
# to end here with the old root still in force and nothing said.
NEW_ROOT=$(drives_predicted_root "$WS")
if [ -n "$ROOT" ] && [ "$NEW_ROOT" != "$ROOT" ]; then
	_won=$(drives_rc_root_file "$WS")
	say ""
	say "WARNING: Bazel will not use $ROOT:"
	say "         ${_won:-an rc file} sets output_user_root=$NEW_ROOT, and Bazel reads it"
	say "         after .bazelrc.local. Delete that line (after \`bazel shutdown\`,"
	say "         while \`bazel\` still means that root), then re-run this script."
	say ""
elif [ -n "$OLD_ROOT" ] && [ "$OLD_ROOT" != "$NEW_ROOT" ]; then
	# A move, which costs a download and can leave a server behind: said once,
	# with the old place named so it can be cleaned up.
	say ""
	say "NOTE: this checkout's Bazel state moves from $OLD_ROOT"
	say "      to $NEW_ROOT. The ~2 GB of downloads are fetched again there. A"
	say "      server still running on the old root keeps its memory for up to"
	say "      three idle hours unless killed by PID (.bazelrc has the line that"
	say "      lists them); once none is, the old folder can be deleted."
	say ""
fi

# ---------------------------------------------------------------------------
# 4. PATH, and the one path that is ENVIRONMENT and not a Bazel flag
#    (BAZELISK_HOME), into the profile.
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
# reads -- so PATH and BAZELISK_HOME would silently not be set, and the whole
# script would appear to have worked.
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
		say "        set -gx BAZELISK_HOME $SCRATCH/bazelisk" ;;
esac

# Make this shell match, so the env_drift run below and anything the student
# types next work without opening a new terminal.
PATH="$BINDIR:$PATH"
BAZELISK_HOME="$SCRATCH/bazelisk"
export PATH BAZELISK_HOME

# ---------------------------------------------------------------------------
# 5. REPAIR a cached C++ toolchain that points at a tool which is gone.
#
# THE FAILURE THIS EXISTS FOR, reported from a campus box:
#
#     execvp(/home/<user>/.linuxbrew/bin/ar): No such file or directory
#     Linking c-piscine/c-piscine-c-12/libft_list_size_asan.a failed
#
# `cc_binary` uses Bazel's AUTO-DETECTED toolchain -- deferred deliberately;
# making it hermetic is a rules_cc job. Detection runs ONCE per output base and
# writes ABSOLUTE paths into local_config_cc's BUILD as
# `tool_paths = {"ar": "...", ...}`. It does not re-run because PATH changed.
#
# So: Homebrew on PATH when it ran records ~/.linuxbrew/bin/ar. Uninstall
# Homebrew -- which this repo RECOMMENDS, because that brew shadows the pinned
# binutils and makes ar and nm read 2.46.1 against the system 2.38 -- and every
# link fails from then on. Two pieces of correct advice that together are a
# trap.
#
# THIS SCRIPT IS WHERE IT GETS FIXED, not merely named. //tools:env_drift
# reports it, but a report is the wrong answer to a build that cannot link:
# setup.sh is what a stuck student is told to re-run, and the repair is exactly
# what re-running should mean. Deleting a local_config_cc makes Bazel re-detect
# on the next command; the repository cache is a SIBLING of the output base and
# is untouched, so nothing is re-downloaded.
#
# Conservative on purpose: it removes a repo ONLY when a recorded absolute path
# is missing, never on a hunch, and it is silent when everything resolves.
printf '\n'
say "checking the C++ toolchain Bazel cached for this machine..."
_tc_fixed=0
# The root Bazel uses (step 3's read-back), not $SCRATCH/bazel: a root recorded
# by hand, or the one the wrapper keeps, is somewhere else.
for _cc in "${NEW_ROOT:-$ROOT}"/*/external/*local_config_cc/BUILD; do
	[ -f "$_cc" ] || continue
	_tc_bad=""
	for _tp in $(sed -n 's/.*tool_paths = {\(.*\)}.*/\1/p' "$_cc" |
			tr ',' '\n' | sed -n 's/.*"\(\/[^"]*\)".*/\1/p' | sort -u); do
		[ -x "$_tp" ] || _tc_bad="$_tc_bad $_tp"
	done
	[ -n "$_tc_bad" ] || continue
	_tc_dir=${_cc%/BUILD}
	say "  stale:$_tc_bad"
	say "  re-detecting: $(basename "$_tc_dir")"
	rm -rf "$_tc_dir" "$_tc_dir.marker" "$(dirname "$_tc_dir")/@$(basename "$_tc_dir").marker"
	_tc_fixed=$((_tc_fixed + 1))
done
if [ "$_tc_fixed" -gt 0 ]; then
	say "  repaired $_tc_fixed cached toolchain(s) -- the next bazel command re-detects."
	say "  Nothing is re-downloaded: the repository cache is a sibling and survives."
else
	say "  every cached tool path still resolves"
fi

# ---------------------------------------------------------------------------
# 6. Compare this machine against the pins.
#
# This is the whole point of running it HERE: on a campus box it answers "have
# they upgraded anything since we pinned?", from the box that decides the
# answer. It warns and never fails -- a student who sat at an upgraded machine
# has done nothing wrong, and blocking their first run over it would be absurd.
#
# What to do next is said last, on both ways out, because whoever runs this
# may never have opened a terminal before: a new terminal first, the file that
# makes it work named, and the way round it for when it still does not.
next_steps() {
	_bin_shown=\~/${BINDIR#"$HOME"/}
	_ws_shown=$WS
	case "$WS" in
		*[!A-Za-z0-9_./+-]*) _ws_shown="'$(printf '%s' "$WS" | sed "s/'/'\\\\''/g")'" ;;
	esac
	printf '\nsetup: done.\n\n'
	if [ -n "$login_rc" ]; then
		say "Next, close this terminal and open a new one: ~/${login_rc#"$HOME"/} now puts"
		say "$_bin_shown, where 42 is, on your PATH, and a terminal reads that file"
		say "only when it opens."
	elif [ "${login_sh##*/}" = fish ]; then
		say "Next, add the lines in the NOTE above to ~/.config/fish/config.fish, then"
		say "close this terminal and open a new one: a terminal reads that file only"
		say "when it opens."
	else
		say "Next, close this terminal and open a new one: what this wrote into"
		say "$(printf '%s' "$touched" | sed 's/([^)]*)//g; s/^ *//') puts $_bin_shown, where 42 is, on your PATH,"
		say "and a terminal reads those files only when it opens."
	fi
	# No `# comment` after a command: a zsh login does not strip it, and the
	# words after # reach the command (interactive_comments is off by default).
	say "In the new terminal, come back to this folder:"
	printf '\n'
	say "  cd $_ws_shown"
	printf '\n'
	say "Then check the machine, and say who you are (your 42 login and email):"
	printf '\n'
	say "  42 doctor"
	say "  42 init"
	printf '\n'
	say "If the new terminal says \"command not found\" about 42, type sh tools/42.sh"
	say "in its place, from this folder, naming the project and the exercise:"
	say "sh tools/42.sh doctor, sh tools/42.sh test c-00 ex01. It is the same program."
	say "README.md goes on from there."
}
if [ "$SKIP_DRIFT" = "1" ]; then
	printf '\n'
	say "skipping the pins check (SETUP_SKIP_DRIFT=1)"
	next_steps
	exit 0
fi
printf '\n'
_drift_out=$(mktemp)
say "checking this machine against tools/pins.tsv (warnings only)..."
say "the first time, this downloads the pinned tools: it can take several"
say "minutes, and prints nothing until it ends."
printf '\n'
# The status tested has to be BAZELISK's, not sed's. `if ! cmd | sed ...` tests
# the last command in the pipeline, and sed succeeds whatever it was fed -- so
# step 4 of the four this script advertises could fail completely and the run
# still printed "setup: done." with no hint that a check had not happened.
#
# ...and it has to be CAPTURED without `set -e` seeing it. A bare
# `cmd > file; rc=$?` under `set -e` never reaches the second half: a failing
# env_drift ended setup.sh right there, silently, with the whole
# "did not complete, that is not fatal" branch below unreachable.
_drift_rc=0
"$BAZELISK" run //tools:env_drift > "$_drift_out" 2>&1 || _drift_rc=$?
sed 's/^/  /' "$_drift_out"
rm -f "$_drift_out"
if [ "$_drift_rc" -ne 0 ]; then
	printf '\n'
	say "env_drift did not complete (exit $_drift_rc; its output is above). That is"
	say "not fatal: it needs Bazel, and on a first run a slow or absent network is"
	say "the usual cause. Re-run it later with: bazel run //tools:env_drift"
fi

next_steps
