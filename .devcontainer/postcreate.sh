#!/bin/sh
# postcreate.sh — devcontainer postCreateCommand, runs once after the container
# is created.
#
# Why this exists: Antigravity (a VS Code fork) does not auto-install the
# extensions declared in customizations.vscode.extensions, and it pulls from the
# Open VSX registry rather than the Microsoft Marketplace. This installs the
# Open-VSX-available subset directly through the Antigravity server CLI.
#
# On stock VS Code (or any non-Antigravity editor) the server binary probed
# below does not exist, so this is a no-op that exits 0 — VS Code installs the
# extensions itself from customizations.vscode.extensions. There are no side
# effects for non-Antigravity users.
#
# Note: the Antigravity CLI currently exits non-zero even on a successful
# install (a post-install analytics error), so success is verified against
# --list-extensions rather than the exit code. The script always exits 0.

set -u

# Extensions that resolve on Open VSX. ms-vscode.cpptools-extension-pack is
# Marketplace-only (absent from Open VSX) and is intentionally omitted — the
# project uses clangd for IntelliSense (see C_Cpp.intelliSenseEngine: disabled).
EXTENSIONS="llvm-vs-code-extensions.vscode-clangd ms-vscode.makefile-tools kube.42header BazelBuild.vscode-bazel"

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
