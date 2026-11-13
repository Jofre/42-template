# ---------------------------------------------------------------- model_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A fixture a model made, held to that model (c_program's `model`, review of
# WP-50): C 10's were made once by `oracle c10_run` and nothing re-ran it, so
# a hand edit or a later fix to the model drifted until a correct program went
# red. A toy model stands in for the oracle, as above: `say WORDS` prints its
# words, `lost NAME` complains on stderr and returns 1, `copy` copies stdin,
# `show NAME` prints the file NAME where it runs.
mkdir -p "$WORK/mdl"
cat > "$WORK/mdl/model" <<'MDL_EOF'
#!/bin/sh
case "$1" in
	say) shift; printf '%s\n' "$*" ;;
	lost) printf 'toy: %s: not here\n' "$2" >&2; exit 1 ;;
	copy) cat ;;
	show) cat "$2" ;;
	*) exit 3 ;;
esac
MDL_EOF
chmod +x "$WORK/mdl/model"
printf 'two words\n' > "$WORK/mdl/said.txt"
printf 'two wordz\n' > "$WORK/mdl/edited.txt"
printf 'toy: gone: not here\n' > "$WORK/mdl/lost.txt"
printf 'fed\n' > "$WORK/mdl/in.txt"
want_green "model_check: a file that is the model's answer passes" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/said.txt" -- say two words
want_red "model_check: a file edited by hand is RED" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/edited.txt" -- say two words
want_out "model_check: ...showing both, byte for byte" 'two wordz$' -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/edited.txt" -- say two words
want_broken_none "model_check: ...with no key where they show no mark" '(byte for byte' -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/edited.txt" -- say two words
printf 'two $words\n' > "$WORK/mdl/dollar.txt"
want_out "model_check: ...and a key to the dollar a file shows" '(byte for byte: \x24 a dollar)' -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/dollar.txt" -- say two words
want_green "model_check: the stream the case compares, and its status" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/lost.txt" --stream stderr --exit 1 -- lost gone
want_red "model_check: a status the model does not return is RED" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/lost.txt" --stream stderr --exit 0 -- lost gone
want_red "model_check: the other stream is not the file" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/lost.txt" -- lost gone
want_green "model_check: the case's standard input reaches the model" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/in.txt" --stdin "$WORK/mdl/in.txt" -- copy
want_broken "model_check: a missing_file that is there refuses" \
	'holds something by that name' -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/lost.txt" --absent "$WORK/mdl/said.txt" -- lost gone
want_broken "model_check: no model words is a wiring error" 'no model words' -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/said.txt" --
# A case's argument file and run folder (c_program's "argv_file" and
# "cwd_files") reach the model as they reach the program: every arm of a case
# runs the same thing (defs_checks.bzl's _case_run), and a model run without them
# answered another run.
printf 'two\nwords\n' > "$WORK/mdl/two.argv"
want_green "model_check: the case's argument file follows its words" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/said.txt" --argv-file "$WORK/mdl/two.argv" -- say
want_red "model_check: ...and without it, the run is another one" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/said.txt" -- say
want_green "model_check: the case's run folder holds its files by name" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/in.txt" --run-as toy --cwd-file "n.dict=$WORK/mdl/in.txt" -- show n.dict
want_red "model_check: ...and without it, the name opens nothing" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/in.txt" -- show n.dict
# A FAIL from a run folder lists what the folder held, each file with where it
# came from (rl_ran), and names no folder: it is a temporary one, removed when
# the check exits, and the report used to say "(from <that folder>)".
want_out "model_check: a FAIL from a run folder lists what it held" \
	"n.dict  a copy of $WORK/mdl/in.txt" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/said.txt" --run-as toy --cwd-file "n.dict=$WORK/mdl/in.txt" -- show n.dict
want_broken_none "model_check: ...and names no folder of its own" '(from ' -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/said.txt" --run-as toy --cwd-file "n.dict=$WORK/mdl/in.txt" -- show n.dict
want_out "model_check: ...and one from here says where it ran" "RAN: oracle say two words" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/edited.txt" -- say two words
# AN ARGUMENT TABLE (c_argv_table's `model`): C 06's and Reloaded's tables
# were emitted once with argv_table.sh --emit and held to nothing after. The
# toy model is the program, run once per row by the real argv_table.sh.
printf 'two\tx\ty\nnone\n' > "$WORK/mdl/scen.tsv"
printf 'two\tx y\nnone\t\n' > "$WORK/mdl/table.txt"
printf 'two\tx y\nnone\tz\n' > "$WORK/mdl/table_edited.txt"
want_green "model_check: a table that is the model's, row for row, passes" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/table.txt" --argv-table "$TOOLS/argv_table.sh" \
	--scenarios "$WORK/mdl/scen.tsv" -- say
want_red "model_check: a table with a row edited by hand is RED" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/table_edited.txt" --argv-table "$TOOLS/argv_table.sh" \
	--scenarios "$WORK/mdl/scen.tsv" -- say
want_out "model_check: ...naming the row, and showing both" 'none\tz$' -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/table_edited.txt" --argv-table "$TOOLS/argv_table.sh" \
	--scenarios "$WORK/mdl/scen.tsv" -- say
want_out "model_check: ...with a key to the tab they show" '(byte for byte: \t a tab)' -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/table_edited.txt" --argv-table "$TOOLS/argv_table.sh" \
	--scenarios "$WORK/mdl/scen.tsv" -- say
want_broken "model_check: a model with no answer on a row is no verdict" \
	'status other than 0' -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/table.txt" --argv-table "$TOOLS/argv_table.sh" \
	--scenarios "$WORK/mdl/scen.tsv" -- lost
want_broken "model_check: a table takes none of a case's options" \
	"none of a case's options" -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/table.txt" --argv-table "$TOOLS/argv_table.sh" \
	--scenarios "$WORK/mdl/scen.tsv" --stdin "$WORK/mdl/in.txt" -- say
want_broken "model_check: a table is made from its scenarios" 'go together' -- \
	"$SH" "$TOOLS/model_check.sh" --oracle "$WORK/mdl/model" \
	--expected "$WORK/mdl/table.txt" --argv-table "$TOOLS/argv_table.sh" -- say

