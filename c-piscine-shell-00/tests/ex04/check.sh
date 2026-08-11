#!/bin/sh
# ex04 — midLS must list the current dir comma-separated, newest first, with a
# trailing slash on directories (i.e. exactly what the reference listing yields).
#
# `ls -m` terminates its listing with a single trailing newline, and the Moulinette
# compares stdout byte-for-byte, so an answer that strips that newline (e.g. piping
# through `tr -d '\n'`) KOs there while a shell-stripping `$(...)` capture stays
# blind to it. We therefore also capture the RAW bytes and assert the terminator.
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-midLS}
case "$D" in /*) ;; *) D="$PWD/$D";; esac
printf "  CHECK: %s\n" "$D"

ck "midLS file is delivered" test -f "$D"

# Build a known directory: a sub-directory plus two files, with controlled
# modification times so 'newest first' has a single correct order:
#   zfile (newest) > afile > adir/ (oldest)
T=$(mktemp -d)
mkdir -p "$T/adir"
: > "$T/afile"
: > "$T/zfile"
: > "$T/.hidden"
touch -t 202606250900 "$T/adir"
touch -t 202606260900 "$T/afile"
touch -t 202606270900 "$T/zfile"

got=$(cd "$T" && sh "$D" 2>/dev/null)
want=$(cd "$T" && ls -ptm)

# Raw capture (bytes incl. any trailing newline) from the SAME controlled fixture,
# so the exact terminator can be checked; the `$(...)` capture above strips
# trailing newlines and is blind to it.
raw=$(mktemp)
( cd "$T" && sh "$D" 2>/dev/null ) > "$raw"

# Per-entry position in the comma list (1-based), so ordering can be checked.
pos() { printf '%s\n' "$got" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -nxF "$1" | head -n1 | cut -d: -f1; }
pz=$(pos zfile); pa=$(pos afile); pd=$(pos adir/)

ck "entries separated by a comma and a space" sh -c 'case "$1" in *", "*) exit 0;; *) exit 1;; esac' _ "$got"
ck "directories marked with a trailing slash (adir/)" sh -c 'case "$1" in *adir/*) exit 0;; *) exit 1;; esac' _ "$got"
ck "hidden entries (dotfiles) excluded" sh -c 'case "$1" in *.hidden*) exit 1;; *) exit 0;; esac' _ "$got"
ck "newest entry comes first (zfile before afile)" test -n "$pz" -a -n "$pa" -a "${pz:-9}" -lt "${pa:-0}"
ck "older entries follow in date order (afile before adir/)" test -n "$pa" -a -n "$pd" -a "${pa:-9}" -lt "${pd:-0}"
# Exact terminator: `ls -m` ends its listing with a single newline and the
# Moulinette diffs stdout byte-for-byte, so this is a spec property (reveals
# nothing about the answer). An answer that strips the final newline KOs.
ck_final_newline "output ends with a trailing newline (as ls -m emits)" "$raw"
# Authoritative full-listing match (plain pass/fail; the expected value is the
# answer, so it is never printed).
ck "listing matches the reference for this directory" test "$got" = "$want"

rm -f "$raw"
rm -rf "$T"
ck_report
