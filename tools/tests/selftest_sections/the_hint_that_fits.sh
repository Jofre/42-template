# ------------------------------------------------------------ the hint that fits
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A program's clue rows are keyed to its cases and three are shown, most
# fundamental first (runner_lib.sh, rl_clues), so a row keyed to every case
# comes first on a case it does not speak to, and the row that does can fall
# behind the three (finding 155). The mutation run of 2026-10-03 found it
# twice: BSQ's "where does map error go" was the sixth row keyed to dup_chars,
# hidden, and Rush 01's argument-count row came after the output shape on
# twoargs; C 11 ex05's, below. Each module's own file, read as its output
# test reads it.
clue_shown() { "$SH" -c '. "$1"; rl_clues "$2" "" "" "$3"' _ "$TOOLS/runner_lib.sh" "$1" "$2" < /dev/null; }
clue_first() { clue_shown "$@" | sed -n 's/^   \* //p' | head -n 1; }
# EVERY CASE A FILE NAMES, AND THE ROW THAT FITS IT, which must be among the
# three it shows: a table per file, "<case> <the row's opening words>", a
# line for each row that fits (finding 155 was three spot checks, and the
# cases nobody had picked -- stdin_map, two_maps, error_then_map -- went on
# hiding theirs). A case the file names that the table lacks is red too, so
# a case added to a file comes with the row that fits it.
clue_untabled() {  # clue_untabled CLUES TABLE -- red when CLUES names a case TABLE lacks
	# 2, a harness error, when CLUES cannot be read: an awk that read
	# nothing found no case untabled, and the arm was green over no file.
	[ -r "$1" ] || { echo "no clue file at $1"; return 2; }
	_cu=$(awk -F '\t' '
		NR == FNR { split($0, w, " "); tabled[w[1]] = 1; next }
		/^[ \t]*#/ || /^[ \t]*$/ { next }
		{ for (i = 2; i <= NF; i++) if (!($i in tabled) && !($i in told)) { told[$i] = 1; printf " %s", $i } }
	' "$2" "$1") || return 2
	[ -z "$_cu" ] && return 0
	echo "named by $1 and in no row of the table:$_cu"
	return 1
}
cat > "$WORK/ct_bsq" <<'CLUE_TABLE'
subject_example Beside the subject's example of ./bsq example_file
one_cell Beside the subject's example of ./bsq example_file
no_empty_cell A map with no empty cell at all
dup_chars Where does the subject say "map error" is displayed
ragged_line Where does the subject say "map error" is displayed
undeclared_char Where does the subject say "map error" is displayed
two_maps With more than one file, the subject puts an empty line
two_maps Where does the subject say "map error" is displayed
missing_alone This run names a file that does not exist
map_then_missing This run names a file that does not exist
map_then_missing With more than one file, the subject puts an empty line
missing_then_map This run names a file that does not exist
missing_then_map With more than one file, the subject puts an empty line
error_then_map With more than one file, the subject puts an empty line
error_then_map Where does the subject say "map error" is displayed
tall_map The first line is not a row of the map
stdin_map With no arguments, where does the subject say the map comes from
count_zero How many lines does this file's first line promise
count_short How many lines does this file's first line promise
nonprintable_char The subject asks three things of the last three characters
zero_width How many cells does each line of this map hold
space_char The subject says the space, or digits, can be among
digit_chars The subject says the space, or digits, can be among
tie_top_first Two squares of the biggest size fit in this map
no_final_newline The subject says the lines of a map are "separated
full_in_body A row of this map holds the "full" character
stdin_invalid With no argument, where does the subject say the map comes from? Is anything
readings This harness's reading of the count, at strict
readings This harness's reading of the "full" character, at strict
CLUE_TABLE
cat > "$WORK/ct_rush01" <<'CLUE_TABLE'
subject What does the subject's `| cat -e` transcript show
noarg The program is handed exactly ONE argument
twoargs The program is handed exactly ONE argument
fifteen The program is handed exactly ONE argument
seventeen The program is handed exactly ONE argument
zero The program is handed exactly ONE argument
five The program is handed exactly ONE argument
nonnumeric The program is handed exactly ONE argument
unsolvable Every value here is a digit from '1' to '4'
unsolvable_near_miss Every value here is a digit from '1' to '4'
sweep The program is handed exactly ONE argument
sweep The sixteen views are one rule a solution has to keep
readings This harness's reading, at strict, never the subject's, of
bonus_9x9 How many values does the argument hold for a board of N by N
CLUE_TABLE
_ct_bsq="$ROOT/c-piscine/c-piscine-bsq/tests/bsq/clues.tsv"
_ct_r01="$ROOT/c-piscine/c-piscine-rush-01/tests/ex00/clues.tsv"
while read -r _ct_case _ct_row; do
	want_out "clues: BSQ's $_ct_case shows the row that fits it" "$_ct_row" -- \
		clue_shown "$_ct_bsq" "$_ct_case"
done < "$WORK/ct_bsq"
want_green "clues: ...and the table has every case BSQ's file names" -- \
	clue_untabled "$_ct_bsq" "$WORK/ct_bsq"
while read -r _ct_case _ct_row; do
	want_out "clues: Rush 01's $_ct_case shows the row that fits it" "$_ct_row" -- \
		clue_shown "$_ct_r01" "$_ct_case"
done < "$WORK/ct_rush01"
want_green "clues: ...and the table has every case Rush 01's file names" -- \
	clue_untabled "$_ct_r01" "$WORK/ct_rush01"
want_broken "clues: a clue file that is not there is no green" "no clue file at" -- \
	clue_untabled "$WORK/no_such_clues.tsv" "$WORK/ct_bsq"
want_out "clues: Rush 01's twoargs opens on the argument count" \
	'The program is handed exactly ONE argument' -- \
	clue_first "$ROOT/c-piscine/c-piscine-rush-01/tests/ex00/clues.tsv" twoargs
want_out "clues: ...and unsolvable on what no solution prints" \
	'Every value here is a digit' -- \
	clue_first "$ROOT/c-piscine/c-piscine-rush-01/tests/ex00/clues.tsv" unsolvable
# C 11 ex05 (c11 M6): one paragraph about argv, atoi, the operators and the
# divisor was keyed to seventeen cases and opened each; a remainder that came
# out wrong was asked about by nothing.
want_out "clues: C 11 ex05's mod opens on the operation's result" \
	'Which operation did this case ask for' -- \
	clue_first "$ROOT/c-piscine/c-piscine-c-11/tests/ex05/clues.tsv" mod
want_out "clues: ...and unknownword on the operators the subject lists" \
	'Which operators does the subject list' -- \
	clue_first "$ROOT/c-piscine/c-piscine-c-11/tests/ex05/clues.tsv" unknownword

