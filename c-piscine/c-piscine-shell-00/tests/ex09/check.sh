#!/bin/sh
# ex09 — file(1) driven by the ft_magic database must report the type EXACTLY as
# "42 file" for a file holding the string "42" at the 42nd byte, and must NOT
# report it otherwise. SPEC, in the subject's own words: the string 42 at the
# 42nd byte, reported as "42 file".
#
# Tightening vs. the lenient check:
#   * file(1)'s classification is compared to the spec label BYTE-FOR-BYTE, from a
#     RAW capture that keeps file(1)'s own terminating newline, so any stray byte
#     around the label (extra text, trailing space, a second matched line) is
#     caught rather than silently stripped by a $(...) capture.
#   * the match is proven to require the FULL string "42": a database that only
#     looks at the "4" still classifies the positive sample as "42 file" and
#     passes a stripped-label check, but is caught here by a negative probe.
# The label "42 file" is a SPEC constant taken from the subject, so showing it
# reveals nothing: how a magic database says it is the student's to work out
# from `man magic`.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

M=${1:-ft_magic}
case "$M" in /*) ;; *) M="$PWD/$M";; esac
printf "  CHECK: %s\n" "$M"

# The deliverable is a magic database file.
ck_require "ft_magic database is present" test -f "$M"

# Controlled fixtures in a scratch dir (host-safe: nothing from this box's
# /etc, users, groups, hostname — the samples are crafted from constants).
T=$(mktemp -d)

# --- Positive: the string "42" starting at the 42nd byte ------------------------
# Padding, then "42": counting the file's bytes the way the subject does, the
# "4" is the 42nd byte and the "2" the 43rd.
printf '%41s42' '' > "$T/sample"

# The turn-in is read by file(1), so file(1) is how it runs: through ck_run,
# which shows what file(1) says on stderr about a database it cannot load --
# the one place a mistake in its syntax is ever named. One run, two views:
# the RAW bytes file(1) emits, and the shell-stripped label for a readable
# want/got diagnostic.
raw="$T/out.raw"
ck_run "$raw" file -b -m "$M" "$T/sample"
got=$(cat "$raw")
ck_eq "type label for '42' at the 42nd byte" "$got" "42 file"

# Then the raw bytes, compared to the exact expected output. A $(...) capture
# hides a trailing newline / stray byte; the byte compare does not.
printf '42 file\n' > "$T/want"
ck "file(1) prints exactly '42 file' and nothing else (byte-exact)" cmp -s "$raw" "$T/want"

# file(1) terminates its line normally (guards against a magic that strips it).
ck_final_newline "file(1) output ends with a single newline" "$raw"

# --- Negative: the position must matter ---------------------------------------
# "42" as the very first bytes of the file must NOT be classified as "42 file".
# Asked of a label file(1) printed: with a database it loaded, it always names
# some type ("ASCII text" at the least), and with one it could not load it
# prints nothing at all -- which is not "no match", it is no answer.
printf '42' > "$T/sample0"
ck_run "$T/out0.raw" file -b -m "$M" "$T/sample0"
got0=$(cat "$T/out0.raw")
ck "position is enforced (no match for '42' at the start of the file)" \
	sh -c '[ -n "$1" ] && [ "$1" != "42 file" ]' _ "$got0"

# --- Negative: the FULL string "42" is required, not a lone byte --------------
# A file whose 42nd byte is "4" but whose 43rd byte is NOT "2" must NOT match;
# this rejects a database that looks at one character instead of the whole "42".
printf '%41s4X' '' > "$T/sample4"
ck_run "$T/out4.raw" file -b -m "$M" "$T/sample4"
got4=$(cat "$T/out4.raw")
ck "the exact string '42' is required (a lone '4' must not match)" \
	sh -c '[ -n "$1" ] && [ "$1" != "42 file" ]' _ "$got4"

rm -rf "$T"
ck_report
