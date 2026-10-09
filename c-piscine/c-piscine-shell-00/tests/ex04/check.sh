#!/bin/sh
# ex04 — midLS must list the current dir comma-separated, by modification date,
# with a trailing slash on directories.
#
# THE DIRECTION. "Sorted by modification date" names none, so this check
# accepts the listing either way round: newest first or oldest first, as long
# as the modification date alone decides the order (docs/reference.md, "Run
# contract": a sentence the subject leaves ambiguous is not checked at basic).
# One reading of it, the direction `ls` sorts by time in (man ls), is
# newest_first.sh's, the exercise's ex04_newest_first target, at strict.
#
# The comma-separated listing ends with a single trailing newline, and the
# Moulinette compares stdout byte-for-byte, so an answer that strips that newline
# KOs there while a shell-stripping `$(...)` capture stays blind to it. We
# therefore also capture the RAW bytes and assert the terminator.
#
# THE FIXTURE is built so that only the modification date gives the expected
# order. Every entry has a modification time and an access time of its own, in
# two unrelated orders, and they are created (and their times set) in orders
# unrelated to either, so a listing by name, by access, change or creation
# time, either way round, comes out different from the listing by modification
# time in both of its directions. The guard after the table checks each of
# those keys, before anything runs: the name and access columns, the table's
# own row order (creation) and ATIME_ORDER (the last touch of each entry, so
# its change time). The directory
# sits in the middle of the order, so its place is checked too. Beside the
# plain files and the directory there is a file with its execute bit and a
# symbolic link to a regular file: only a directory gets a marker in the
# subject's words, and neither of those is one under any reading. The link's
# target lies outside the directory, dated so that the link sorts in the same
# place by its own date or by its target's. A link to a DIRECTORY is left out:
# whether that is a "directory name" the subject does not say.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-midLS}
case "$D" in /*) ;; *) D="$PWD/$D";; esac
printf "  CHECK: %s\n" "$D"

ck_require "midLS file is delivered" test -f "$D"
# The subject: shell exercises must be executable with /bin/sh.
ck_sh_parses "$D"

# The listed directory, T, and beside it the link's target -- ONE table, which
# the fixture is built from and the expected listing derived from (by sorting
# its rows on the modification column), so the two cannot drift: the listing
# used to be typed out by hand beside the table it was read off.
#
#   entry     kind                 modified          accessed
#   .hidden   file                 07-01 (newest)    06-20
#   charlie   file, execute bit    06-29             07-03
#   echo      file                 06-28             07-02
#   bravo/    directory            06-27             07-01
#   delta     link to ../target    06-26             07-05
#   alpha     file                 06-25 (oldest)    07-04
#   ../target file (not listed)    06-26 08:00       --
#
# The rows are in creation order (bravo, echo, alpha, delta, charlie,
# .hidden); modification times are set in MTIME_ORDER and access times last,
# in ATIME_ORDER, both unrelated to either date order or to the names.
FIXTURE='bravo	dir	202606270900	202607010900
echo	file	202606280900	202607020900
alpha	file	202606250900	202607040900
delta	link	202606260900	202607050900
charlie	exec	202606290900	202607030900
.hidden	file	202607011200	202606200900'
MTIME_ORDER='.hidden charlie echo bravo delta alpha'
ATIME_ORDER='.hidden bravo echo charlie alpha delta'
row() { printf '%s\n' "$FIXTURE" | awk -F'\t' -v n="$1" '$1 == n'; }
# Each order names every row of the table once and nothing else: a row
# added to the table and to neither order would keep the time it was made
# at, and the listing expected from the table would not be the directory's.
NAMES=$(printf '%s\n' "$FIXTURE" | cut -f1 | sort)
for order in "$MTIME_ORDER" "$ATIME_ORDER"; do
	# shellcheck disable=SC2086 # one name per word, by design
	[ "$(printf '%s\n' $order | sort)" = "$NAMES" ] ||
		ck_broken "an order of the fixture does not name each row of its table once: $order"
done
R=$(mktemp -d)
T="$R/here"
mkdir -p "$T"
: > "$R/target"
touch -m -t 202606260800 "$R/target"
printf '%s\n' "$FIXTURE" | while IFS='	' read -r name kind _m _a; do
	case "$kind" in
		dir) mkdir "$T/$name" ;;
		link) ln -s ../target "$T/$name" ;;
		exec) : > "$T/$name"; chmod +x "$T/$name" ;;
		*) : > "$T/$name" ;;
	esac
done
for name in $MTIME_ORDER; do
	touch -h -m -t "$(row "$name" | cut -f3)" "$T/$name"
done
for name in $ATIME_ORDER; do
	touch -h -a -t "$(row "$name" | cut -f4)" "$T/$name"
done
# The fixture took: each entry's modification time is its row's. A machine
# whose filesystem cannot date a link, or a table that lost a row, would
# otherwise grade every answer against a directory nobody described.
for name in $NAMES; do
	# stat, not date -r: date follows the link to its target's own time.
	[ "$(date -d "@$(stat -c %Y "$T/$name" 2> /dev/null)" +%Y%m%d%H%M 2> /dev/null)" = "$(row "$name" | cut -f3)" ] ||
		ck_broken "the fixture's $name does not carry its modification time from the table"
done

# The expected listings, derived from the table: every row but a dotfile,
# sorted on one of its columns, a directory's name with its slash. Computing
# them by running a listing command on the fixture would put the answer in
# this file; the table fixes every name and time, so the order is known from
# it. listing COLUMN r|"" -> the listing sorted on that column (3 modified,
# 4 accessed, 1 the name), descending with r.
listing() {
	printf '%s\n' "$FIXTURE" | awk -F'\t' '$1 !~ /^\./' | sort -t '	' -k"$1,$1$2" |
		awk -F'\t' '{ printf "%s%s%s", (NR > 1 ? ", " : ""), $1, ($2 == "dir" ? "/" : "") } END { print "" }'
}
newest=$(listing 3 r)
oldest=$(listing 3 "")
# Both directions are accepted, so neither may be what another key gives:
# a listing by name, or by access date, either way round, would then pass
# as a listing by modification date.
for _k in "1 " "1 r" "4 " "4 r"; do
	# shellcheck disable=SC2086 # the column and the direction, two words
	_other=$(listing $_k)
	[ "$_other" != "$newest" ] && [ "$_other" != "$oldest" ] ||
		ck_broken "the fixture's listing by column ${_k% *} gives one of the modification-date listings: the table no longer tells them apart"
done
# ...nor the order the entries are created in (the table's rows), nor the
# order of their change times, which every touch sets and so runs in
# ATIME_ORDER, the last one each entry gets. in_order -> the listing of the
# names on stdin, one per line, in that order.
in_order() {
	while IFS= read -r _n; do row "$_n"; done |
		awk -F'\t' '$1 !~ /^\./ { printf "%s%s%s", (n++ ? ", " : ""), $1, ($2 == "dir" ? "/" : "") } END { print "" }'
}
rev_lines() { awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }'; }
CREATED=$(printf '%s\n' "$FIXTURE" | cut -f1)
# shellcheck disable=SC2086 # one name per word, by design
CHANGED=$(printf '%s\n' $ATIME_ORDER)
for _o in "$CREATED" "$CHANGED"; do
	for _other in "$(printf '%s\n' "$_o" | in_order)" "$(printf '%s\n' "$_o" | rev_lines | in_order)"; do
		[ "$_other" != "$newest" ] && [ "$_other" != "$oldest" ] ||
			ck_broken "the order the fixture's entries are created in, or last touched in (their change times), gives one of the modification-date listings"
	done
done

# One run, two views: the raw bytes (incl. any trailing newline) for the
# terminator, and the shell-stripped `$(...)` form for everything else.
raw=$(mktemp)
ck_run -C "$T" "$raw" sh "$D"
got=$(cat "$raw")

# Per-entry position in the comma list (1-based), so ordering can be checked.
pos() { printf '%s\n' "$got" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -nxF "$1" | head -n1 | cut -d: -f1; }
pc=$(pos charlie); pb=$(pos bravo/); pl=$(pos delta)
# The order is judged apart from the markers: an entry is found there with a
# type marker after it (*, @, =, | or >) left out, so a listing whose only
# fault is its markers -- which the line about markers below reports -- is not
# also called unsorted (the mutation run of 2026-10-03, shell00a M2).
pos_any() { printf '%s\n' "$got" | tr ',' '\n' | sed 's/^ *//;s/ *$//;s/[*@=|>]$//' | grep -nxF "$1" | head -n1 | cut -d: -f1; }
oc=$(pos_any charlie); oe=$(pos_any echo); ob=$(pos_any bravo/); ol=$(pos_any delta); oa=$(pos_any alpha)

ck "entries separated by a comma and a space" sh -c 'case "$1" in *", "*) exit 0;; *) exit 1;; esac' _ "$got"
ck "directories marked with a trailing slash (bravo/)" test -n "$pb"
ck "only directories are marked: the executable (charlie) and the link (delta) carry nothing" \
	test -n "$pc" -a -n "$pl"
# An absence is only seen in output that exists: printing nothing is not
# leaving .hidden out.
ck "hidden entries (dotfiles) excluded" sh -c '[ -n "$1" ] && case "$1" in *.hidden*) exit 1;; *) exit 0;; esac' _ "$got"
# The order, either way round: the subject names no direction (THE
# DIRECTION, above).
ck "sorted by modification date, in either direction: charlie, echo, bravo/, delta, alpha, or the reverse" \
	sh -c '[ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ] || exit 1
		{ [ "$1" -lt "$2" ] && [ "$2" -lt "$3" ] && [ "$3" -lt "$4" ] && [ "$4" -lt "$5" ]; } ||
			{ [ "$1" -gt "$2" ] && [ "$2" -gt "$3" ] && [ "$3" -gt "$4" ] && [ "$4" -gt "$5" ]; }' \
	_ "$oc" "$oe" "$ob" "$ol" "$oa"
# Exact terminator: the comma-separated listing ends with a single newline and
# the Moulinette diffs stdout byte-for-byte, so this is a spec property (reveals
# nothing about the answer). An answer that strips the final newline KOs.
ck_final_newline "output ends with a trailing newline (as the comma-separated listing does)" "$raw"
# Authoritative full-listing match (plain pass/fail), in either direction.
ck "listing matches the reference for this directory (newest or oldest first)" \
	sh -c '[ "$1" = "$2" ] || [ "$1" = "$3" ]' _ "$got" "$newest" "$oldest"

rm -f "$raw" "$raw.err"
rm -rf "$R"
ck_report
