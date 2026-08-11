#!/bin/sh
# reset_headers.sh — rewrite the 42 header of every deliverable source file to a
# consistent identity + art, preserving each file's body byte-for-byte.
#
# The new header comes from tools/gen_header.sh, so it uses ONE source of truth:
#   * identity  -> .vscode/settings.json (42header.username / 42header.email)
#   * art       -> tools/header_art.txt  (with the built-in fallback)
# Created and Updated are both set to now by default, so every file is uniform.
# Pass --keep-created to PRESERVE each file's existing Created (parsed from the
# current header) and move only Updated — useful for a re-stamp that changes just
# identity/art without flattening all the Created dates to one instant.
#
# It only touches files that already have a standard 11-line 42 header (borders
# on line 1 and 11); the body (line 12 onward) is copied through unchanged.
#
# DESTRUCTIVE: edits files in place. Run on a clean git tree so you can review the
# diff (it should only ever touch lines 1-11 of each file).
#
# Usage:
#   tools/reset_headers.sh                    # all c-piscine-*/deliverable .c/.h
#                                             # (the rush modules included)
#   tools/reset_headers.sh <file|dir> ...     # ONLY the given files/dirs (per-folder)
#   tools/reset_headers.sh -n [targets]       # dry-run: list what would change
#   tools/reset_headers.sh -k [targets]       # keep each file's Created (--keep-created)
#
# Per-folder, for natural staggered timestamps (run each module as you finish it):
#   bazel run //tools:reset_headers -- c-piscine-c-00
#   bazel run //tools:reset_headers -- c-piscine-c-00/deliverable/ex08

set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "reset_headers.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require date dirname find grep mktemp mv rm sed sort tail

# Repo root: from `bazel run` it's BUILD_WORKSPACE_DIRECTORY; run directly it's the
# parent of tools/.
cd "${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}" || exit 1
GEN="tools/gen_header.sh"

DRY=0
KEEP_CREATED=0
while [ "$#" -gt 0 ]; do
	case "$1" in
		-n|--dry-run) DRY=1; shift ;;
		-k|--keep-created) KEEP_CREATED=1; shift ;;
		--) shift; break ;;
		-?*) echo "reset_headers.sh: unknown option: $1" >&2; exit 2 ;;
		*) break ;;
	esac
done

if [ "$#" -gt 0 ]; then
	TARGETS="$(find "$@" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null | sort)"
else
	# c-piscine-*, not c-piscine-c-*: the rush modules keep their deliverables in
	# exactly the same place and carry exactly the same 42 headers, and the
	# narrower glob silently missed all 14 of their sources. A tool that
	# re-stamps "every header" and quietly skips a tenth of them is worse than
	# one that never ran -- the template build calls this to scrub identity
	# before publishing, so the files it missed kept a real login.
	TARGETS="$(find c-piscine-*/deliverable -type f \( -name '*.c' -o -name '*.h' \) | sort)"

	# ...plus any file ANYWHERE ELSE that already carries a 42 header.
	#
	# Exactly one does: c-08's tests/ft_stock_str.h. It is normed (it is passed
	# as `hdrs`, and the Norm demands a 42 header on every .h it sees), so it
	# cannot simply lose the header the way the rest of tests/ has none -- and
	# walking deliverable/ alone meant an identity change left it stamped with
	# whatever login it was written under. It was, with an older one.
	#
	# The rule is deliberately "refresh what already has one", never "add one":
	# every other file under tests/ is harness code that the Norm never sees,
	# and stamping those would be inventing a requirement. Nothing has to be
	# listed by name, so a second such file is picked up the day it appears.
	EXTRA="$(grep -rlF --include='*.c' --include='*.h' \
		'/* ************************************************************************** */' \
		c-piscine-*/tests 2> /dev/null | sort)"
	TARGETS="$TARGETS
$EXTRA"
fi

BORDER_RE='^/\* \*\{74\} \*/$'
NOW="$(date '+%Y/%m/%d %H:%M:%S')"
done_n=0
skip_n=0

for f in $TARGETS; do
	# must be a standard 11-line 42 header (border on lines 1 and 11)
	if ! sed -n '1p' "$f" | grep -q "$BORDER_RE" \
		|| ! sed -n '11p' "$f" | grep -q "$BORDER_RE"; then
		echo "skip (no standard 42 header): $f" >&2
		skip_n=$((skip_n + 1))
		continue
	fi
	if [ "$DRY" = 1 ]; then
		echo "would reset: $f"
		done_n=$((done_n + 1))
		continue
	fi
	tmp="$(mktemp)"
	# Both timestamps default to now. With --keep-created, preserve the file's
	# existing Created (header line 8) and move only Updated; fall back to now if it
	# has no parseable Created. Empty login/email -> gen_header uses settings.json.
	if [ "$KEEP_CREATED" = 1 ]; then
		created="$(sed -n '8p' "$f" | sed -n 's/.*Created: \([0-9][0-9/]* [0-9:]*\) by .*/\1/p')"
		[ -n "$created" ] || created="$NOW"
	else
		created="$NOW"
	fi
	if sh "$GEN" "$f" "" "" "$created" "$NOW" > "$tmp"; then
		tail -n +12 "$f" >> "$tmp"   # body, byte-for-byte
		mv "$tmp" "$f"
		done_n=$((done_n + 1))
	else
		rm -f "$tmp"
		echo "gen_header failed: $f" >&2
		skip_n=$((skip_n + 1))
	fi
done

printf 'reset %d file(s); skipped %d.' "$done_n" "$skip_n"
[ "$DRY" = 1 ] && printf '  (dry-run)'
printf '\n'
