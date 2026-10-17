#!/bin/sh
# postcreate.sh — devcontainer postCreateCommand, runs once after the container
# is created. It puts `42` on PATH, gives the container's Bazel a disk cache
# (a ~/.bazelrc of the container's own, below) and, when the checkout's
# .bazelrc.local names a root this container cannot create, a root of its
# own there too, and installs the editor extensions under Antigravity.
#
# An editor may not run it: Antigravity 2.5.5 did not, on two rebuilds
# (docs/environment.md, Dev container). Run by hand, once, it does all of
# it, and a second run adds nothing.
#
# The extensions: Antigravity (a VS Code fork) does not auto-install the
# extensions declared in customizations.vscode.extensions, and it pulls from the
# Open VSX registry rather than the Microsoft Marketplace. This installs the
# Open-VSX-available subset directly through the Antigravity server CLI.
#
# On stock VS Code (or any non-Antigravity editor) the server binary probed
# below does not exist, so this part does nothing — VS Code installs the
# extensions itself from customizations.vscode.extensions.
#
# Note: the Antigravity CLI currently exits non-zero even on a successful
# install (a post-install analytics error), so success is verified against
# --list-extensions rather than the exit code. The script always exits 0.

set -u

# Extensions that resolve on Open VSX. ms-vscode.cpptools-extension-pack is
# Marketplace-only (absent from Open VSX) and is intentionally omitted — the
# project uses clangd for IntelliSense (see C_Cpp.intelliSenseEngine: disabled).
EXTENSIONS="llvm-vs-code-extensions.vscode-clangd ms-vscode.makefile-tools kube.42header BazelBuild.vscode-bazel"

# The checkout this script sits in. Set here, above every step: a published
# copy of this file has one step fewer, and the steps after it read WS too.
WS="$(cd "$(dirname "$0")/.." && pwd)"

# `42`, the front-end over the suite (tools/42.sh), on PATH in this container:
# here, before the Antigravity check below ends the script on other editors.
# The installer leaves alone a 42 it did not write.
sh "$WS/tools/fortytwo/install.sh" ||
	echo "postcreate: 42 is not on PATH (see above); run it as: sh tools/42.sh"

# ---------------------------------------------------------------------------
# A disk cache for this container's Bazel.
#
# What one output base compiled reaches another (a worktree's, the one
# `bazel run //tools:prime` builds into) through a --disk_cache both read, and
# through nothing else. tools/setup.sh writes that line into .bazelrc.local,
# but the container never runs setup.sh, and .bazelrc.local is the wrong file
# here anyway: the workspace is bind-mounted from the host, so a path written
# into it would name this container's folders to a Bazel run on the host in
# the same checkout. So the lines go into the container's own ~/.bazelrc,
# which goes when the container does: the cache where setup.sh would put it
# (tools/drives.sh chooses, for both) and the same 4G cap. No startup option:
# the output root stays the one tools/bazel chooses, unless the next step
# finds one this container cannot create.
#
# A ~/.bazelrc you already have is kept. A line is added only when no line
# there sets its flag, so a disk cache you chose stays yours and a second run
# changes nothing. Bazel reads ~/.bazelrc after a checkout's .bazelrc.local,
# so in this container these lines win over one's. Neither the file nor the
# cache goes inside the workspace.
# ---------------------------------------------------------------------------
in_workspace() {
	case "$1/" in
		"$WS"/*) return 0 ;;
	esac
	return 1
}
refuse_in_workspace() {
	echo "postcreate: the drive list chose $1, inside the workspace,"
	echo "            which the host shares; Bazel gets no disk cache here"
}
# rc_folder FILE -- says so when FILE is a folder, which no line goes into.
rc_folder() {
	[ ! -d "$1" ] || echo "            ($1 is a folder: it has to be a file)"
}
disk_cache_rc() {
	_rc="$HOME/.bazelrc"
	if in_workspace "$_rc"; then
		echo "postcreate: $_rc would be inside the workspace, which the host shares;"
		echo "            Bazel gets no disk cache here"
		return 0
	fi
	if [ ! -r "$WS/tools/drives.sh" ]; then
		echo "postcreate: tools/drives.sh is missing; Bazel gets no disk cache here"
		return 0
	fi
	# shellcheck source=tools/drives.sh
	. "$WS/tools/drives.sh"
	# Predicted first, creating nothing: a place inside the workspace is
	# refused before the drive list's probe makes it.
	DRIVES_DRY=1
	drives_choose
	_dc_st=$?
	unset DRIVES_DRY
	if [ "$_dc_st" = 0 ] && in_workspace "$DRIVES_SCRATCH"; then
		refuse_in_workspace "$DRIVES_SCRATCH"
		return 0
	fi
	if [ "$_dc_st" != 0 ] || ! drives_choose; then
		echo "postcreate: Bazel gets no disk cache here: $DRIVES_WHY."
		return 0
	fi
	# And the real choice again: a candidate the prediction took can fail
	# its real probe, and the list then goes on to the next one, which the
	# prediction never looked at. That probe has made its folder by now, so
	# what it made goes again, from the bottom up to DRIVES_MADE: a folder
	# that was there before is above it, and rmdir takes only an empty one.
	# A trailing or doubled slash would put one folder in the walk twice
	# (b/, then b): one already gone counts as removed, not as one that
	# stays. drives_choose tidies its joins now (V168), so no candidate
	# brings one here; that test is only a defence.
	if in_workspace "$DRIVES_SCRATCH"; then
		refuse_in_workspace "$DRIVES_SCRATCH"
		_made=$DRIVES_SCRATCH
		while [ -n "$DRIVES_MADE" ] && in_workspace "$_made" &&
			[ "$_made" != "$WS" ] &&
			{ rmdir "$_made" 2> /dev/null || [ ! -e "$_made" ]; } &&
			[ "$_made" != "$DRIVES_MADE" ]; do
			_made=${_made%/*}
		done
		return 0
	fi
	_disk="$DRIVES_SCRATCH/bazel-disk"
	_add=""
	grep -q '^[^#]*--disk_cache[=[:blank:]]' "$_rc" 2> /dev/null ||
		_add="build --disk_cache=$_disk"
	grep -q '^[^#]*--experimental_disk_cache_gc_max_size[=[:blank:]]' "$_rc" 2> /dev/null ||
		_add="${_add:+$_add
}build --experimental_disk_cache_gc_max_size=4G"
	if [ -z "$_add" ]; then
		echo "postcreate: $_rc already sets a disk cache and its cap -- left alone"
		return 0
	fi
	# A newline first when the file has content: a blank line before the
	# block, or the end of a last line written without one. The note fits
	# both lines and the cap alone, which is all a ~/.bazelrc that already
	# names a disk cache gets. The shell's own error for a redirection that
	# fails ("postcreate.sh: <line>: cannot create ...") goes, 2> before >>: the
	# else branch names the file, and says when it is a folder (V330).
	if {
		[ ! -s "$_rc" ] || echo
		echo "# added by .devcontainer/postcreate.sh, for Bazel's disk cache"
		printf '%s\n' "$_add"
	} 2> /dev/null >> "$_rc"; then
		echo "postcreate: added to $_rc, for Bazel's disk cache:"
		printf '%s\n' "$_add" | sed 's/^/    /'
	else
		echo "postcreate: could not write $_rc; Bazel gets no disk cache here"
		rc_folder "$_rc"
	fi
}
disk_cache_rc

# ---------------------------------------------------------------------------
# An output root this container can create.
#
# tools/setup.sh, run on the host, records the root it chose in the
# checkout's .bazelrc.local: a folder under the host's home, which the
# container's user cannot create (/home here is root's). Every Bazel run in
# the container then stopped with a bare mkdir FATAL (V239). That file is the
# host's as much as this container's, and a line taken out of it moves the
# host's root, in the very cases tools/setup.sh records one to keep it where
# it is. So it is left alone, and the container's own ~/.bazelrc, which
# Bazel reads after it, gets a startup line naming tools/bazel's default
# here. Only when the root an rc file names cannot be created here: a root
# that can be stays theirs, and a ~/.bazelrc that names one is never given a
# second. tools/bazel and `42 doctor` send whoever meets such a root here.
# ---------------------------------------------------------------------------
output_root_rc() {
	_rc="$HOME/.bazelrc"
	# disk_cache_rc above said so already.
	in_workspace "$_rc" && return 0
	[ -r "$WS/tools/drives.sh" ] || return 0
	# shellcheck source=tools/drives.sh
	. "$WS/tools/drives.sh"
	drives_rc_scan "$WS"
	[ -n "$_rr_root" ] && [ "$_rr_file" != "$_rc" ] || return 0
	_or_root=$_rr_root
	_or_file=$_rr_file
	DRIVES_DRY=1
	if drives_probe "$_or_root"; then
		unset DRIVES_DRY
		return 0
	fi
	echo "postcreate: $_or_file sets the output root $_or_root,"
	echo "            which this container cannot create."
	if ! drives_default_root "$WS" || in_workspace "$DRIVES_ROOT" ||
		! drives_probe "$DRIVES_ROOT"; then
		unset DRIVES_DRY
		echo "            No root of the container's own qualifies either: set"
		echo "            C_PISCINE_SCRATCH to a folder you can write, and run this again."
		return 0
	fi
	unset DRIVES_DRY
	if {
		[ ! -s "$_rc" ] || echo
		echo "# added by .devcontainer/postcreate.sh: $_or_file names a root"
		echo "# this container cannot create, and is the host's to keep"
		echo "startup --output_user_root=$DRIVES_ROOT"
	} 2> /dev/null >> "$_rc"; then
		echo "postcreate: added to $_rc, which Bazel reads after that file (left as"
		echo "            it is: the host reads it too):"
		echo "    startup --output_user_root=$DRIVES_ROOT"
	else
		echo "postcreate: could not write $_rc; Bazel cannot start in this container"
		echo "            until a root it can create is named there."
		rc_folder "$_rc"
	fi
}
output_root_rc

cli=""
for candidate in "$HOME"/.antigravity-ide-server/bin/*/bin/antigravity-ide-server; do
	[ -x "$candidate" ] && cli="$candidate"
done

if [ -z "$cli" ]; then
	echo "postcreate: no Antigravity server found; nothing to do."
	exit 0
fi

echo "postcreate: Antigravity detected, installing extensions from Open VSX..."
for ext in $EXTENSIONS; do
	"$cli" --install-extension "$ext" >/dev/null 2>&1 || true
done

# Verify against the actual installed set (the CLI exit code is unreliable).
installed=$("$cli" --list-extensions 2>/dev/null)
for ext in $EXTENSIONS; do
	if printf '%s\n' "$installed" | grep -qix "$ext"; then
		echo "  ok   $ext"
	else
		echo "  warn $ext did not install (continuing)"
	fi
done

echo "postcreate: done. Reload the Antigravity window to activate new extensions."
exit 0
