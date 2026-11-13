# ------------------------------------------------------------- the shard deal
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The deal at the top of this file (SHARD WEIGHTS), on a toy: this file's
# header, to the line that ends the deal, over six sections of its own, with
# a table beside it, run by SELFTEST_DEAL=print, which deals and runs no arm.
# Section a holds five arms and the rest one each, so a deal by count and a
# deal by the table part ways; f sits in a block the template build strips,
# whose markers are spelt in two halves here because that build refuses to
# publish the word whole. A refusal is exit 2 and says which row or section.
mkdir -p "$WORK/deal"
_dp=PRIVATE-
_do=ONLY
{
	sed -n '1,/^fi$/p' "$ST_SELF"
	printf '# ----- a\n'
	for _i in 1 2 3 4 5; do printf 'want_green "a%s" -- true\n' "$_i"; done
	for _s in b c d e; do printf '# ----- %s\nwant_green "%s" -- true\n' "$_s" "$_s"; done
	printf '# %s%s BLOCK: a toy\n# ----- f\nwant_green "f" -- true\n# END %s%s\n' \
		"$_dp" "$_do" "$_dp" "$_do"
	printf '# ===== the tally\n'
} > "$WORK/deal/selftest.sh"
# deal_run N: the toy dealt over N shards, with whatever table is beside it;
# deal_with FILE N: with FILE for its table; deal_toy ROWS [N]: with ROWS
# (printf %b) and f's row in its block, over N shards (2).
# A test run's own variables are unset, since print mode refuses them;
# deal_in VAR runs the deal with VAR set again, as a test run sets it.
deal_run() {
	env -u SELFTEST_SHARD -u SELFTEST_SHARD_FILE -u TEST_SHARD_STATUS_FILE \
		-u XML_OUTPUT_FILE TEST_TOTAL_SHARDS="$1" TEST_SHARD_INDEX=0 \
		SELFTEST_DEAL=print "$SH" "$WORK/deal/selftest.sh"
}
deal_in() {
	cp "$WORK/deal/good.tsv" "$WORK/deal/selftest_costs.tsv" &&
	env -u SELFTEST_SHARD -u SELFTEST_SHARD_FILE -u TEST_SHARD_STATUS_FILE \
		-u XML_OUTPUT_FILE "$1=$WORK/deal/test_run.out" TEST_TOTAL_SHARDS=2 \
		TEST_SHARD_INDEX=0 SELFTEST_DEAL=print "$SH" "$WORK/deal/selftest.sh"
}
deal_with() { cp "$1" "$WORK/deal/selftest_costs.tsv" && deal_run "$2"; }
deal_toy() {
	{
		printf '%b' "$1"
		printf '# %s%s BLOCK: a toy\nf\t1\n# END %s%s\n' "$_dp" "$_do" "$_dp" "$_do"
	} > "$WORK/deal/rows.tsv"
	deal_with "$WORK/deal/rows.tsv" "${2:-2}"
}
deal_none() { rm -f "$WORK/deal/selftest_costs.tsv"; deal_run 2; }
# deal_in's table, sound, so it has nothing else to refuse.
printf 'a\t1\nb\t10\nc\t10\nd\t6\ne\t6\n# %s%s BLOCK: a toy\nf\t1\n# END %s%s\n' \
	"$_dp" "$_do" "$_dp" "$_do" > "$WORK/deal/good.tsv"
# By count, a (five arms) would take a shard alone; by the table it costs
# least, and goes with the shard the others leave lightest.
want_out "the shard deal: sections are dealt by the table's seconds" \
	'shard 1 of 2: 17.0s  b | d | a' -- deal_toy 'a\t1\nb\t10\nc\t10\nd\t6\ne\t6\n'
want_out "the shard deal: ...one it leaves out by its count, named" \
	'weighed by their count: "e"' -- deal_toy 'a\t1\nb\t10\nc\t10\nd\t6\n'
want_broken "the shard deal: a row naming no section is refused" \
	'names section "g", which this file does not have' -- \
	deal_toy 'a\t1\nb\t10\nc\t10\nd\t6\ne\t6\ng\t1\n'
want_broken "the shard deal: a row that is no row is refused" \
	'is not a row of section<TAB>seconds' -- deal_toy 'a 1\n'
want_broken "the shard deal: a section listed twice is refused" \
	'lists section "a" a second time' -- \
	deal_toy 'a\t1\na\t2\nb\t10\nc\t10\nd\t6\ne\t6\n'
want_broken "the shard deal: no table is refused" \
	'no table of section costs' -- deal_none
want_broken "the shard deal: a section near a shard's mean is refused" \
	'section "b" costs 30.0s, over three quarters of a shard' -- \
	deal_toy 'a\t1\nb\t30\nc\t1\nd\t1\ne\t1\n'
want_broken "the shard deal: a deal over 15% above the mean is refused" \
	'the shards are uneven: shard 1 carries 12.0s' -- \
	deal_toy 'a\t0\nb\t6\nc\t6\nd\t6\ne\t0\n'
printf 'a\t1\nb\t10\nc\t10\nd\t6\ne\t6\nf\t1\n' > "$WORK/deal/f_bare.tsv"
want_broken "the shard deal: a stripped section's row outside its block is refused" \
	'section "f" sits in a block the template build strips, and its row does not' -- \
	deal_with "$WORK/deal/f_bare.tsv" 2
want_broken "the shard deal: ...and a row in one whose section is not" \
	'section "e" sits in no block the template build strips, and its row does' -- \
	deal_toy "a\t1\nb\t10\nc\t10\nd\t6\n# ${_dp}${_do} BLOCK: a toy\ne\t6\n# END ${_dp}${_do}\n"
# Print mode inside a test run would pass every shard having run no arm;
# the table beside it is sound, so nothing else is refused.
want_broken "the shard deal: print mode in a sharded test run is refused" \
	'so a test run refuses it' -- deal_in TEST_SHARD_STATUS_FILE
want_broken "the shard deal: ...and in any test run Bazel makes" \
	'so a test run refuses it' -- deal_in XML_OUTPUT_FILE
# The table's upkeep (TO VERIFY V285). The deal reads only the table, so a
# listed section that grows keeps its row, and neither refusal can see it;
# selftest_costs.sh reads the shards' logs back against the table. A toy
# table of six sections, C's row in a block the template build strips, and
# two runs of three shards' logs, written as a shard prints them: one where
# every section took about three times its row (a loaded machine: nothing to
# say), and one where C took four times its row and the rest theirs (an arm
# grown inside a listed section: named, with the shards it made uneven).
_sc=$(dirname "$ST_SELF")/selftest_costs.sh
mkdir -p "$WORK/deal/sc"
printf '# a toy\nA\t10.0\nB\t10.0\n# %s%s BLOCK: a toy\nC\t10.0\n# END %s%s\nD\t10.0\nE\t12.5\nF\t10.0\n' \
	"$_dp" "$_do" "$_dp" "$_do" > "$WORK/deal/sc/t.tsv"
sc_log() {  # sc_log RUN SHARD NAME=SECONDS... -- one shard's log
	mkdir -p "$WORK/deal/sc/$1/$2"
	_scl="$WORK/deal/sc/$1/$2/test.log"
	shift 2
	for _kv in "$@"; do
		printf '  [section %s: %ss, its arms]\n' "${_kv%%=*}" "${_kv#*=}"
	done > "$_scl"
	printf '  [section Z: 9.00s, plain code only]\n' >> "$_scl"
}
sc_log loaded shard_1_of_3 A=30.00 B=30.00
sc_log loaded shard_2_of_3 C=30.00 D=30.00
sc_log loaded shard_3_of_3 E=30.00 F=30.00
sc_log grown shard_1_of_3 A=10.00 B=10.00
sc_log grown shard_2_of_3 C=40.00 D=10.00
sc_log grown shard_3_of_3 E=10.00 F=10.00 G=4.00
sc_run() {  # sc_run RUN [SHARD...] -- the check over RUN's logs (all three)
	_scr=$1
	shift
	[ $# -gt 0 ] || set -- shard_1_of_3 shard_2_of_3 shard_3_of_3
	_scs=""
	for _s in "$@"; do _scs="$_scs $WORK/deal/sc/$_scr/$_s/test.log"; done
	# shellcheck disable=SC2086 # one word per log; the scratch path has no space
	"$SH" "$_sc" --table "$WORK/deal/sc/t.tsv" $_scs
}
want_green "the shard deal: a run slower in every section still fits its table" -- \
	sc_run loaded
want_red "the shard deal: ...a section grown inside its row does not" -- sc_run grown
want_out "the shard deal: ...named against its row, on the table's scale" \
	'"C": its row says 10.0s; it took 40.0s' -- sc_run grown
want_out "the shard deal: ...with the deal's refusal on what the shards measured" \
	'the shards are uneven: shard_2_of_3/test.log took 50.0s' -- sc_run grown
want_out "the shard deal: ...and a section with no row" '"G": no row' -- sc_run grown
want_broken_none "the shard deal: ...but not a section that kept to its row" '"A":' -- \
	sc_run grown
want_broken "the shard deal: a log that is not there is refused" 'no log at' -- \
	sc_run none
want_broken "the shard deal: ...and one with no section's seconds" \
	'has no "[section NAME: Ns, its arms]" line' -- \
	"$SH" "$_sc" --table "$WORK/deal/sc/t.tsv" "$WORK/deal/sc/t.tsv"
# The table rebuilt from the first two shards of the grown run: C's measured
# seconds in C's block, E and F kept (in no log read) and said to be, G
# absent; and --write puts the same table in place of the old.
sc_rebuilt() {  # sc_rebuilt rebuild|write
	cp "$WORK/deal/sc/t.tsv" "$WORK/deal/sc/w.tsv"
	_scw=$1
	"$SH" "$_sc" "--$_scw" --table "$WORK/deal/sc/w.tsv" \
		"$WORK/deal/sc/grown/shard_1_of_3/test.log" \
		"$WORK/deal/sc/grown/shard_2_of_3/test.log" > "$WORK/deal/sc/out" 2> "$WORK/deal/sc/err"
	_scrc=$?
	[ "$_scrc" = 0 ] || { cat "$WORK/deal/sc/err"; return "$_scrc"; }
	[ "$_scw" = rebuild ] || cp "$WORK/deal/sc/w.tsv" "$WORK/deal/sc/out"
	printf '# a toy\nA\t10.0\nB\t10.0\n# %s%s BLOCK: a toy\nC\t40.0\n# END %s%s\nD\t10.0\nE\t12.5\nF\t10.0\n' \
		"$_dp" "$_do" "$_dp" "$_do" > "$WORK/deal/sc/want"
	if ! cmp -s "$WORK/deal/sc/want" "$WORK/deal/sc/out"; then
		echo "the table it made:"
		cat "$WORK/deal/sc/out"
		return 1
	fi
	[ "$_scw" = write ] && return 0
	grep -qF '"E" is in no log read, so its row is kept' "$WORK/deal/sc/err" || {
		echo "no word of E's row kept:"
		cat "$WORK/deal/sc/err"
		return 1
	}
}
want_green "the shard deal: the table rebuilt from the logs keeps its blocks" -- \
	sc_rebuilt rebuild
want_green "the shard deal: ...and --write puts it in place" -- sc_rebuilt write
# And this file's own deal, over the shards tools/tests/BUILD.bazel gives
# it, which a hand run otherwise never makes: a shard's TEST_TOTAL_SHARDS
# is shard_count, and a hand run takes 8, which mirrors it.
_deal_n=${TEST_TOTAL_SHARDS:-8}
[ "$_deal_n" -gt 1 ] 2>/dev/null || _deal_n=8
want_out "the shard deal: this file and its table deal over Bazel's shards" \
	"shard $_deal_n of $_deal_n: " -- env -u SELFTEST_SHARD \
		-u SELFTEST_SHARD_FILE -u TEST_SHARD_STATUS_FILE -u XML_OUTPUT_FILE \
		TEST_TOTAL_SHARDS="$_deal_n" TEST_SHARD_INDEX=0 SELFTEST_DEAL=print \
		"$SH" "$ST_SELF"

