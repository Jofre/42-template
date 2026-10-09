#!/bin/sh
# install.sh -- put the `42` command on PATH.
#
# Usage:
#   sh tools/fortytwo/install.sh [BINDIR]     # BINDIR defaults to ~/.local/bin
#
# It writes one small file, BINDIR/42: a shim that walks up from the folder you
# type in to the checkout around it and runs that checkout's tools/42.sh, so
# every clone and worktree runs its own 42. Outside any checkout it runs this
# one's, named when the shim was written. tools/setup.sh and the dev
# container's postcreate.sh call this; running it again rewrites the shim and
# nothing else.
#
# A BINDIR/42 that this script did not write is left alone: the name is short,
# and something else may own it.
set -u

MARK='# 42 shim, written by tools/fortytwo/install.sh'

WS=$(cd "$(dirname "$0")/../.." && pwd) || exit 2
[ -f "$WS/tools/42.sh" ] || { echo "install.sh: $WS/tools/42.sh is missing" >&2; exit 2; }
BINDIR=${1:-${HOME:?install.sh: HOME is not set}/.local/bin}
SHIM="$BINDIR/42"

if [ -e "$SHIM" ] && ! grep -qF "$MARK" "$SHIM" 2> /dev/null; then
	echo "install.sh: $SHIM exists and is not 42's shim -- left alone." >&2
	echo "            Run 42 as: sh $WS/tools/42.sh" >&2
	exit 1
fi
mkdir -p "$BINDIR" || exit 2

# The checkout baked in below is quoted for the shim's shell: a path with a
# quote in it must not end the string.
q=$(printf '%s' "$WS" | sed "s/'/'\\\\''/g")
tmp="$SHIM.tmp.$$"
cat > "$tmp" << EOF || exit 2
#!/bin/sh
$MARK
# The checkout around the current folder runs; outside one, this checkout:
FALLBACK='$q'
d=\$PWD
while :; do
	if [ -f "\$d/MODULE.bazel" ] && [ -f "\$d/tools/42.sh" ]; then
		exec sh "\$d/tools/42.sh" "\$@"
	fi
	[ "\$d" = / ] && break
	d=\$(dirname "\$d")
done
if [ -f "\$FALLBACK/tools/42.sh" ]; then
	exec sh "\$FALLBACK/tools/42.sh" "\$@"
fi
echo "42: not inside a checkout, and \$FALLBACK is gone. Run tools/fortytwo/install.sh from a checkout again." >&2
exit 2
EOF
chmod 755 "$tmp" && mv "$tmp" "$SHIM" || { rm -f "$tmp"; exit 2; }
echo "42: installed $SHIM"
case ":${PATH:-}:" in
	*":$BINDIR:"*) ;;
	*) echo "42: $BINDIR is not on this shell's PATH. tools/setup.sh adds it to"
	   echo "    your profile; a new terminal then has it." ;;
esac
