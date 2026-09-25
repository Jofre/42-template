#!/bin/sh
# Print a norminette-valid 42 header for a source file, stamped with your 42
# identity. Useful from the CLI when you don't have the kube.42header VS Code
# extension (e.g. a terminal-only workflow).
#
# The header has two parts:
#   * a fixed STRUCTURE (the box borders + the filename / By: / Created: /
#     Updated: fields) — this is what norminette actually checks, and
#   * a swappable ASCII-ART canvas on the right-hand side.
#
# norminette validates the header with a regex: it requires the exact top/bottom
# star borders and the four structural fields, but the art region is unchecked.
# So you may draw ANYTHING in the art canvas, as long as:
#
#     ART CANVAS = up to 9 rows, each up to 33 columns.
#     * No "*/" anywhere (it would close the C comment).
#     * Lines are kept at 80 columns total (the art is padded for you).
#     * The top and bottom "*" borders are NOT part of the canvas (fixed frame).
#
# The art is read from an external file so you can swap it freely:
#     $HEADER_ART  (env)         else  <repo>/tools/header_art.txt
# If that file is missing, too big, or contains "*/", the BUILT-IN art below is
# used instead (and a note is printed to stderr), so a broken art file can never
# produce a broken header. Always verify with:  norminette <file>
#
# Usage:
#   gen_header.sh <filename> [login] [email] [created] [updated]
#     login/email default to $LOGIN42/$EMAIL42, then the 42header.* keys in
#     .vscode/settings.json. created/updated default to now. Only <filename>
#     is required.

set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "gen_header.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk basename cat date dirname grep head mktemp rm sed tr wc

ART_ROWS=9
ART_COLS=33

ROOT="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"
SETTINGS="$ROOT/.vscode/settings.json"
ART_FILE="${HEADER_ART:-$ROOT/tools/header_art.txt}"

FN="${1:-}"
[ -n "$FN" ] || { echo "gen_header.sh: missing filename" >&2; exit 2; }
FN="$(basename "$FN")"

read_42() {
	sed -n "s/.*\"42header.$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
		"$SETTINGS" 2>/dev/null | head -1
}
LOGIN="${2:-${LOGIN42:-$(read_42 username)}}"
MAIL="${3:-${EMAIL42:-$(read_42 email)}}"
: "${LOGIN:=marvin}"
: "${MAIL:=marvin@42.fr}"

NOW="$(date '+%Y/%m/%d %H:%M:%S')"
CREATED="${4:-$NOW}"
UPDATED="${5:-$NOW}"

# Built-in fallback art (9 rows, <=25 cols, no "*/").
default_art() {
	cat <<'ART'

             :::      ::::::::
           :+:      :+:    :+:
         +:+ +:+         +:+
       +#+  +:+       +#+
     +#+#+#+#+#+   +#+
          #+#    #+#
         ###   ########.fr

ART
}

# Choose the art source: the file if it exists AND is valid, else the built-in.
art_source() {
	if [ -f "$ART_FILE" ]; then
		if grep -q '\*/' "$ART_FILE"; then
			echo "gen_header.sh: '$ART_FILE' contains '*/' — using built-in art" >&2
		elif [ "$(wc -l < "$ART_FILE")" -gt "$ART_ROWS" ]; then
			echo "gen_header.sh: '$ART_FILE' has more than $ART_ROWS rows — using built-in art" >&2
		elif awk -v w="$ART_COLS" '{ if (length($0) > w) bad = 1 } END { exit bad + 0 }' "$ART_FILE"; then
			cat "$ART_FILE"
			return
		else
			echo "gen_header.sh: '$ART_FILE' has a row wider than $ART_COLS cols — using built-in art" >&2
		fi
	fi
	default_art
}

# Normalise to exactly ART_ROWS lines, each exactly ART_COLS wide.
ART_TMP="$(mktemp)"
trap 'rm -f "$ART_TMP"' EXIT
art_source | awk -v rows="$ART_ROWS" -v cols="$ART_COLS" '
	NR <= rows { printf "%-*.*s\n", cols, cols, $0; c++ }
	END { while (c < rows) { printf "%-*.*s\n", cols, cols, ""; c++ } }
' > "$ART_TMP"

art() { sed -n "${1}p" "$ART_TMP"; }

STARS="$(printf '%074d' 0 | tr 0 '*')"
SW=$((75 - ART_COLS))   # structural field width (= 42); inner rows use a flush */

# Inner rows: /* (3) + struct(SW) + art(ART_COLS) + */ (2) = 80. Borders keep ' */'.
# The art reaches the last column before */ so the canvas is as wide as norminette
# allows (it only mandates the borders and the By:/Created:/Updated:/filename fields).
printf '/* %s */\n' "$STARS"
printf "/* %-${SW}.${SW}s%-${ART_COLS}.${ART_COLS}s*/\n" ""                              "$(art 1)"
printf "/* %-${SW}.${SW}s%-${ART_COLS}.${ART_COLS}s*/\n" ""                              "$(art 2)"
printf "/* %-${SW}.${SW}s%-${ART_COLS}.${ART_COLS}s*/\n" "  $FN"                         "$(art 3)"
printf "/* %-${SW}.${SW}s%-${ART_COLS}.${ART_COLS}s*/\n" ""                              "$(art 4)"
printf "/* %-${SW}.${SW}s%-${ART_COLS}.${ART_COLS}s*/\n" "  By: $LOGIN <$MAIL>"          "$(art 5)"
printf "/* %-${SW}.${SW}s%-${ART_COLS}.${ART_COLS}s*/\n" ""                              "$(art 6)"
printf "/* %-${SW}.${SW}s%-${ART_COLS}.${ART_COLS}s*/\n" "  Created: $CREATED by $LOGIN" "$(art 7)"
printf "/* %-${SW}.${SW}s%-${ART_COLS}.${ART_COLS}s*/\n" "  Updated: $UPDATED by $LOGIN" "$(art 8)"
printf "/* %-${SW}.${SW}s%-${ART_COLS}.${ART_COLS}s*/\n" ""                              "$(art 9)"
printf '/* %s */\n' "$STARS"
