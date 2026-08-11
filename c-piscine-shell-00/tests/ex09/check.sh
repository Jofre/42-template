#!/bin/sh
# ex09 — file(1) driven by the ft_magic database must report the type EXACTLY as
# "42 file" for a file holding the string "42" at the 42nd byte (0-based offset
# 41), and must NOT report it otherwise. SPEC: type label "42 file", magic offset
# 41, match string "42".
#
# Tightening vs. the lenient check:
#   * file(1)'s classification is compared to the spec label BYTE-FOR-BYTE, from a
#     RAW capture that keeps file(1)'s own terminating newline, so any stray byte
#     around the label (extra text, trailing space, a second matched line) is
#     caught rather than silently stripped by a $(...) capture.
#   * the match is proven to require the FULL string "42": a magic keyed on a
#     single byte ("4") still classifies the positive sample as "42 file" and
#     passes a stripped-label check, but is caught here by a negative probe.
# The label "42 file" is a SPEC constant taken from the subject, so showing it
# reveals nothing about the solution (which is the magic-rule *syntax* itself).
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

M=${1:-ft_magic}
case "$M" in /*) ;; *) M="$PWD/$M";; esac
printf "  CHECK: %s\n" "$M"

# The deliverable is a magic database file.
ck "ft_magic database is present" test -f "$M"

# Controlled fixtures in a scratch dir (host-safe: nothing from this box's
# /etc, users, groups, hostname — the samples are crafted from constants).
T=$(mktemp -d)

# --- Positive: the string "42" starting at the 42nd byte (0-based offset 41) ---
printf '%41s42' '' > "$T/sample"

# Shell-stripped label first, for a readable want/got diagnostic.
got=$(file -b -m "$M" "$T/sample" 2>/dev/null)
ck_eq "type label for '42' at the 42nd byte" "$got" "42 file"

# Then the RAW bytes file(1) emits, compared to the exact expected output. A
# $(...) capture hides a trailing newline / stray byte; the byte compare does not.
raw="$T/out.raw"
file -b -m "$M" "$T/sample" > "$raw" 2>/dev/null
printf '42 file\n' > "$T/want"
ck "file(1) prints exactly '42 file' and nothing else (byte-exact)" cmp -s "$raw" "$T/want"

# file(1) terminates its line normally (guards against a magic that strips it).
ck_final_newline "file(1) output ends with a single newline" "$raw"

# --- Negative: the offset must matter -----------------------------------------
# "42" placed at byte 0 must NOT be classified as "42 file".
printf '42' > "$T/sample0"
got0=$(file -b -m "$M" "$T/sample0" 2>/dev/null)
ck "offset is enforced (no match for '42' at byte 0)" test "$got0" != "42 file"

# --- Negative: the FULL string "42" is required, not a lone byte --------------
# A file whose 42nd byte is "4" but whose 43rd byte is NOT "2" must NOT match;
# this rejects a magic keyed on a single byte instead of the two-char string.
printf '%41s4X' '' > "$T/sample4"
got4=$(file -b -m "$M" "$T/sample4" 2>/dev/null)
ck "the exact string '42' is required (a lone '4' must not match)" test "$got4" != "42 file"

rm -rf "$T"
ck_report
