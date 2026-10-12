#!/bin/sh
# postcreate.sh — devcontainer postCreateCommand, runs once after the container
# is created. It puts `42` on PATH, gives the container's Bazel a disk cache
# (a ~/.bazelrc of the container's own, below), and installs the editor
# extensions under Antigravity.
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
# the output root stays the one tools/bazel chooses.
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
	# A trailing or doubled slash puts one folder in the walk twice (b/,
	# then b): one already gone counts as removed, not as one that stays.
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
	# names a disk cache gets.
	if {
		[ ! -s "$_rc" ] || echo
		echo "# added by .devcontainer/postcreate.sh, for Bazel's disk cache"
		printf '%s\n' "$_add"
	} >> "$_rc"; then
		echo "postcreate: added to $_rc, for Bazel's disk cache:"
		printf '%s\n' "$_add" | sed 's/^/    /'
	else
		echo "postcreate: could not write $_rc; Bazel gets no disk cache here"
	fi
}
disk_cache_rc

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
