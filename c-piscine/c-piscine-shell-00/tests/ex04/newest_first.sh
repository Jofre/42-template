#!/bin/sh
# Shell 00 ex04, "sorted by modification date" read in one direction -- its
# ex04_newest_first target, at strict.
#
# The sentence names no direction, and check.sh (basic) accepts the listing
# either way round, newest first or oldest first, as long as the modification
# date alone decides the order. This reads it as the direction `ls` sorts by
# time in when it is asked to (man ls): the newest entry first. Whether 42
# grades a direction at all, the subject does not say -- which is what puts
# this at strict and not at basic (docs/reference.md, "Run contract").
#
# THE FIXTURE is three plain files and nothing else: check.sh has already
# asked of a richer directory everything but the direction. Three names have
# six orders, and every one of them is some key's: the names give two (one
# each way round), the access dates two, the modification dates the two the
# directions are. The order the files are created in, and the order their
# dates are set in, give orders too -- by creation time, and by change time,
# which every touch sets -- and with nothing left over, each has to be one the
# names or the access dates already give. ORDER below is both; the guard after
# the table refuses a fixture where any of those keys, either way round,
# gives the listing expected, so only a listing by modification date, newest
# first, reads as that one here.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-midLS}
case "$D" in /*) ;; *) D="$PWD/$D";; esac
printf "  CHECK: %s, this harness's reading at strict: newest first, the way ls sorts by time\n" "$D"

ck_require "midLS file is delivered" test -f "$D"
ck_sh_parses "$D"

#   entry   modified          accessed
#   kilo    07-01 (oldest)    07-12
#   lima    07-03 (newest)    07-11
#   mike    07-02             07-13 (newest)
#
# ORDER is the order the files are created in, then their modification
# times set in, then their access times: the last touch of each is its
# change time, so the change times run in ORDER too.
FIXTURE='kilo	202607010900	202607120900
lima	202607030900	202607110900
mike	202607020900	202607130900'
ORDER='kilo lima mike'
row() { printf '%s\n' "$FIXTURE" | awk -F'\t' -v n="$1" '$1 == n'; }
NAMES=$(printf '%s\n' "$FIXTURE" | cut -f1 | sort)
# shellcheck disable=SC2086 # one name per word, by design
[ "$(printf '%s\n' $ORDER | sort)" = "$NAMES" ] ||
	ck_broken "ORDER does not name each row of the fixture's table once: $ORDER"

# The listings, derived from the table: listing COLUMN r|"" -> the names
# sorted on that column (1 the name, 2 modified, 3 accessed), descending
# with r. in_order WORDS -> the names in the order given.
listing() {
	printf '%s\n' "$FIXTURE" | sort -t '	' -k"$1,$1$2" |
		awk -F'\t' '{ printf "%s%s", (NR > 1 ? ", " : ""), $1 } END { print "" }'
}
in_order() {
	printf '%s\n' "$@" | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 } END { print "" }'
}
want=$(listing 2 r)
# shellcheck disable=SC2086 # one name per word, by design
_rev=$(printf '%s\n' $ORDER | awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }')
for _k in "1 " "1 r" "3 " "3 r"; do
	# shellcheck disable=SC2086 # the column and the direction, two words
	[ "$(listing $_k)" != "$want" ] ||
		ck_broken "the fixture's listing by column ${_k% *} is the listing by modification date, newest first: the table no longer tells them apart"
done
# shellcheck disable=SC2086 # one name per word, by design
for _o in "$(in_order $ORDER)" "$(in_order $_rev)"; do
	[ "$_o" != "$want" ] ||
		ck_broken "ORDER, the order the files are created and last touched in (their change times), is the listing by modification date, newest first"
done

R=$(mktemp -d)
for name in $ORDER; do
	: > "$R/$name"
done
for name in $ORDER; do
	touch -m -t "$(row "$name" | cut -f2)" "$R/$name"
done
for name in $ORDER; do
	touch -a -t "$(row "$name" | cut -f3)" "$R/$name"
done
for name in $NAMES; do
	[ "$(date -d "@$(stat -c %Y "$R/$name" 2> /dev/null)" +%Y%m%d%H%M 2> /dev/null)" = "$(row "$name" | cut -f2)" ] ||
		ck_broken "the fixture's $name does not carry its modification time from the table"
done

raw=$(mktemp)
ck_run -C "$R" "$raw" sh "$D"
got=$(cat "$raw")
ck "newest modification date first, the direction ls sorts by time in ($want)" \
	test "$got" = "$want"

rm -f "$raw" "$raw.err"
rm -rf "$R"
ck_report
