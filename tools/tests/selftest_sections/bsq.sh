# --------------------------------------------------------------------- bsq
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# c-piscine-bsq's differential runner. Unlike rush02_check.sh this one GATES --
# the subject fixes the answer including the tie-break -- so a false green here
# is a wrong grade rather than a missed second opinion.
#
# The fake oracles emit the corpus format directly, so these arms need neither
# the Rust binary nor a BSQ implementation. The valid maps are square and
# all-empty, or all-obstacle, which makes a CORRECT student expressible as one
# sed: drop the header, turn every empty cell into a full one. That is the whole
# reason the fixture maps are shaped that way.
mkdir -p "$WORK/bs"
{
	_i=2
	while [ "$_i" -le 13 ]; do
		# an N x N all-empty map: the answer covers the whole map
		_row=""; _x=""; _j=0
		while [ "$_j" -lt "$_i" ]; do _row="$_row."; _x="$_x"x; _j=$((_j + 1)); done
		_body=""; _sol=""; _j=0
		while [ "$_j" -lt "$_i" ]; do _body="$_body$_row\\n"; _sol="$_sol$_x\\n"; _j=$((_j + 1)); done
		printf 'ok\t%s\t0\t0\t%s.ox\\n%s\t%s\n' "$_i" "$_i" "$_body" "$_sol"
		# the same size, all obstacle: side 0, printed unchanged
		_orow=""; _j=0
		while [ "$_j" -lt "$_i" ]; do _orow="${_orow}o"; _j=$((_j + 1)); done
		_ob=""; _j=0
		while [ "$_j" -lt "$_i" ]; do _ob="$_ob$_orow\\n"; _j=$((_j + 1)); done
		printf 'ok\t0\t-1\t-1\t%s.ox\\n%s\t%s\n' "$_i" "$_ob" "$_ob"
		_i=$((_i + 1))
	done
} | st_oracle "$WORK/bs/oracle_ok.sh"
# The same, with invalid files mixed in, for multi mode.
{
	printf '#!/bin/sh\n"%s" "%s"\n' "$SH" "$WORK/bs/oracle_ok.sh"
	printf 'i=0\nwhile [ $i -lt 6 ]; do printf %s i=$((i+1)); done\n' \
		"'err:chars_repeat\\t-1\\t-1\\t-1\\t2.oo\\\\n..\\\\n..\\\\n\\tmap error\\\\n\\n';"
} > "$WORK/bs/oracle_mixed.sh"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bs/oracle_empty.sh"

# The fake students below are WRITTEN, not run.
# Correct: drop the header line, fill every empty cell.
printf '#!/bin/sh\nfor f in "$@"; do sed 1d "$f" | sed "s/[.]/x/g"; done\n' \
	> "$WORK/bs/good.sh"
# Prints the file back untouched -- header and all.
printf '#!/bin/sh\nfor f in "$@"; do cat "$f"; done\n' > "$WORK/bs/catty.sh"
# Always claims the file is invalid.
printf '#!/bin/sh\nprintf "map error\\n"\n' > "$WORK/bs/allerr.sh"
# Right bytes, no final newline -- a real Moulinette failure that a
# command-substitution comparison would not see.
printf '#!/bin/sh\nfor f in "$@"; do sed 1d "$f" | sed "s/[.]/x/g" | tr -d "\\n"; done\n' \
	> "$WORK/bs/nonl.sh"
chmod +x "$WORK/bs"/*.sh

# Every call says what stderr is held to (bsq_check.sh refuses one that does
# not with exit 2, as its floors do: so the floor arms below ask for each
# floor's own words too).
BS_WHY="the selftest corpus is about stdout"
# And the subject's sentence a fault quotes (--quotes), from the call site.
BS_QUOTES="$WORK/bs/quotes.tsv"
printf 'tie\tToy, p.1: "the square nearest the top, then the left."\nerror\tToy, p.2: "map error, then a newline."\n' \
	> "$BS_QUOTES"
bs_run() { "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/$1.sh" \
	--oracle "$WORK/bs/$2.sh" --show 0; }

want_green "bsq: a solver matching the reference passes"  -- bs_run good oracle_ok
# THE GATE runs the program as the subject example's own output test does:
# the map is its argument (--gate-arg). It once ran the program with nothing,
# so a correct one read an empty standard input, answered "map error", and
# every BSQ corpus SKIPped on every correct program. A correct solver gated on
# its example must be judged, and a wrong one must wait.
printf '2.ox\n..\n..\n' > "$WORK/bs/example.map"
printf 'xx\nxx\n' > "$WORK/bs/example.txt"
bs_gated() { env NO_SKIP=0 "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/$1.sh" \
	--oracle "$WORK/bs/oracle_ok.sh" --show 0 --gate-differ "$TOOLS/diff_output.sh" \
	--gate-bin "$WORK/bs/$1.sh" --gate-expected "$WORK/bs/example.txt" --gate-arg "$WORK/bs/example.map"; }
want_out   "bsq: a correct solver's gate opens on its example's map" \
	'agree with the reference' -- bs_gated good
want_out   "bsq: ...and a wrong one's waits" \
	"SKIP — this exercise's own output fixture" -- bs_gated catty
want_red   "bsq: printing the map back unchanged fails"   -- bs_run catty oracle_ok
want_red   "bsq: always answering 'map error' fails"      -- bs_run allerr oracle_ok
want_red   "bsq: a missing final newline fails"           -- bs_run nonl oracle_ok
# A run stopped from outside -- here the toy signals its waiter,
# tools/exit_status -- says nothing of the program: exit 2, as rl_mem_run's,
# never a case filed as the student's "crash".
printf '#!/bin/sh\nkill -TERM $PPID; sleep 1\nfor f in "$@"; do sed 1d "$f" | sed "s/[.]/x/g"; done\n' \
	> "$WORK/bs/stopped.sh"
chmod +x "$WORK/bs/stopped.sh"
want_broken "bsq: a run stopped from outside is no crash, exit 2" \
	'could not be judged: the program was stopped from outside' -- bs_run stopped oracle_ok
# WHAT ENDS A LINE (V54): right rows, as many as the map's, and a byte after
# one of them, was FAULT [not-a-map], whose words ask the reader to count the
# lines -- which the case line had just counted right. Its own fault now,
# naming the bytes after the row; a missing final newline stays its own.
printf '#!/bin/sh\nfor f in "$@"; do sed 1d "$f" | sed "s/[.]/x/g" | sed "2s/\\$/ /"; done\n' \
	> "$WORK/bs/rowspace.sh"
printf '#!/bin/sh\nfor f in "$@"; do if grep -q "^2[.]oo" "$f"; then printf "map error \\n"; else sed 1d "$f" | sed "s/[.]/x/g"; fi; done\n' \
	> "$WORK/bs/errspace.sh"
# ...and the answer whole, but for its last newline.
printf '#!/bin/sh\nfor f in "$@"; do printf %%s "$(sed 1d "$f" | sed "s/[.]/x/g")"; done\n' \
	> "$WORK/bs/lastnl.sh"
chmod +x "$WORK/bs/rowspace.sh" "$WORK/bs/errspace.sh" "$WORK/bs/lastnl.sh"
want_out   "bsq: a byte after a right row is its own fault" 'FAULT [line-end]' -- bs_run rowspace oracle_ok
want_out   "bsq: ...naming the byte" 'line 2 has 1 byte(s) more: " "' -- bs_run rowspace oracle_ok
want_broken_none "bsq: ...never not-a-map" 'not-a-map' -- bs_run rowspace oracle_ok
want_out   "bsq: ...and so is one after \"map error\"" 'FAULT [line-end]' -- bs_run errspace oracle_mixed
want_broken_none "bsq: ...never an invalid file accepted" 'accepted-invalid-file' -- bs_run errspace oracle_mixed
# Nothing at all for an invalid file was "answered as a map": nothing was
# answered, and the fault is a missing line, so it is the shape's fault.
printf '#!/bin/sh\nfor f in "$@"; do grep -q "^2[.]oo" "$f" || sed 1d "$f" | sed "s/[.]/x/g"; done\n' \
	> "$WORK/bs/errsilent.sh"
chmod +x "$WORK/bs/errsilent.sh"
want_out   "bsq: no answer to an invalid file is the shape's fault" 'FAULT [not-a-map]' -- \
	bs_run errsilent oracle_mixed
want_broken_none "bsq: ...never \"answered as a map\"" 'answered as a map' -- \
	bs_run errsilent oracle_mixed
want_out   "bsq: a missing last newline stays its own fault" 'FAULT [trailing-newline]' -- bs_run lastnl oracle_ok
want_broken_none "bsq: ...not a line-end" 'line-end' -- bs_run lastnl oracle_ok
# ...and where the line-end message is not printed, the want and got lines
# still show where each line ended (V83): the same space, with a blank line
# after the answer, is FAULT [not-a-map], and "got  | xx " read as "xx".
printf '#!/bin/sh\nfor f in "$@"; do sed 1d "$f" | sed "s/[.]/x/g" | sed "2s/\\$/ /"; echo; done\n' \
	> "$WORK/bs/rowsplus.sh"
chmod +x "$WORK/bs/rowsplus.sh"
want_out   "bsq: a want or got line ends in \$ where the line did" 'got  | xx $' -- \
	bs_run rowsplus oracle_ok
want_out   "bsq: ...and the legend says what the \$ is" '$ is where a line ended' -- \
	bs_run rowsplus oracle_ok
# ...and a line the output does not have ends in nothing: a $ there said a
# line ended that never began, on every case of an empty program.
printf '#!/bin/sh\nfor f in "$@"; do sed 1d "$f" | sed "s/[.]/x/g" | sed "\\$d"; done\n' \
	> "$WORK/bs/lastrow.sh"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bs/silent.sh"
chmod +x "$WORK/bs/lastrow.sh" "$WORK/bs/silent.sh"
want_broken_none "bsq: a line the output does not have ends in no \$" 'got  | $' -- \
	bs_run lastrow oracle_ok
want_broken_none "bsq: ...nor does one an empty output does not have" 'got  | $' -- \
	bs_run silent oracle_ok
# ...and the same status blindness this runner shared with its two siblings: a
# solver that draws the square correctly and then dies is not a solver.
printf '#!/bin/sh\nfor f in "$@"; do sed 1d "$f" | sed "s/[.]/x/g"; done\nkill -SEGV $$\n' \
	> "$WORK/bs/crashes.sh"
chmod +x "$WORK/bs/crashes.sh"
want_red   "bsq: right bytes then a SEGV is not a pass"   -- bs_run crashes oracle_ok
# ...but right bytes then `return (-1);` (status 255) is: it returned, which
# waitpid() tells from a death by "signal 127" (tools/exit_status).
printf '#!/bin/sh\nfor f in "$@"; do sed 1d "$f" | sed "s/[.]/x/g"; done\nexit 255\n' \
	> "$WORK/bs/ret255.sh"
chmod +x "$WORK/bs/ret255.sh"
want_green "bsq: right bytes then a return of 255 passes"  -- bs_run ret255 oracle_ok
# THE GATE IS THE EXAMPLE'S RUN: the map --gate-arg names, handed to the
# program as its output test hands it. BSQ's corpora gated on the program run
# with no map at all, which a correct program answers "map error": every one
# said SKIP on every program that passes the example. `env -u NO_SKIP`: the
# suite runs with NO_SKIP=1, which forces every gate open.
printf '2.ox\n..\n..\n' > "$WORK/bs/gate.map"
printf 'xx\nxx\n' > "$WORK/bs/gate.txt"
bs_gate() {
	_bg=$1
	shift
	env -u NO_SKIP "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/$_bg.sh" \
		--oracle "$WORK/bs/oracle_ok.sh" --show 0 --gate-differ "$TOOLS/diff_output.sh" \
		--gate-bin "$WORK/bs/$_bg.sh" --gate-expected "$WORK/bs/gate.txt" "$@"
}
want_green "bsq: a solver that passes the gate's map is checked" -- \
	bs_gate good --gate-arg "$WORK/bs/gate.map"
want_broken_none "bsq: ...not skipped, as with no map it was" 'SKIP' -- \
	bs_gate good --gate-arg "$WORK/bs/gate.map"
want_out   "bsq: a solver that fails the gate's map is skipped" 'SKIP' -- \
	bs_gate catty --gate-arg "$WORK/bs/gate.map"
want_out   "bsq: ...naming the test it waits for" 'SKIP — ex00_subject_example_output, this exercise' -- \
	bs_gate catty --gate-arg "$WORK/bs/gate.map" --gate-label ex00_subject_example_output
# THE GATE'S SETTINGS ARE THE CALL'S (V36). runner_lib.sh reset RL_GATE_WHY
# when sourced and not RL_GATE_LABEL or RL_GATE_PASS, which this runner never
# sets, so a value in the environment reached its gate: a label turned the
# corpus SKIP into a case's, and a word of the differ's options broke the
# gate, which then said it could not be evaluated.
bs_gate_env() {  # bs_gate_env SOLVER VAR=VALUE -- the gate, with VAR in the environment
	env -u NO_SKIP "$2" "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" \
		--bin "$WORK/bs/$1.sh" --oracle "$WORK/bs/oracle_ok.sh" --show 0 \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/bs/$1.sh" \
		--gate-expected "$WORK/bs/gate.txt" --gate-arg "$WORK/bs/gate.map"
}
want_out   "bsq: a gate label in the environment is not the call's" \
	"SKIP — this exercise's own output fixture" -- bs_gate_env catty RL_GATE_LABEL=elsewhere
want_broken_none "bsq: ...nor are differ options in the environment" \
	'could not be evaluated' -- bs_gate_env good RL_GATE_PASS=--stdin
# STANDARD ERROR, A CHOICE AT EVERY CALL (review of WP-50): this runner kept it
# only to show beside a crash. Now the call says what it is held to.
printf '#!/bin/sh\nfor f in "$@"; do sed 1d "$f" | sed "s/[.]/x/g"; done\necho "a note" >&2\n' \
	> "$WORK/bs/chatty.sh"
chmod +x "$WORK/bs/chatty.sh"
bs_err() { "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-empty --bin "$WORK/bs/$1.sh" \
	--oracle "$WORK/bs/oracle_ok.sh" --show 1; }
want_broken "bsq: a call that says nothing of stderr refuses" \
	'say what standard error is held to' -- \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --bin "$WORK/bs/good.sh" --oracle "$WORK/bs/oracle_ok.sh"
# The subject's sentence a fault quotes comes from the call site (V90): a call
# with none, or with a key this runner does not quote, refuses (exit 2); a
# square of the right size in the wrong one of several places prints it. The
# tie map is one row of three empty cells, beside the all-obstacle map every
# corpus needs.
want_broken "bsq: a call with no --quotes refuses" \
	'--quotes FILE is required' -- \
	"$SH" "$TOOLS/bsq_check.sh" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/good.sh" --oracle "$WORK/bs/oracle_ok.sh"
printf 'grid\tToy, p.1: "another runner\047s key."\n' > "$WORK/bs/quotes_other.tsv"
want_broken "bsq: ...or a key it does not quote" "line 1: unknown key 'grid'" -- \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$WORK/bs/quotes_other.tsv" --stderr-ignored "$BS_WHY" \
	--bin "$WORK/bs/good.sh" --oracle "$WORK/bs/oracle_ok.sh"
{
	printf 'ok\t1\t0\t0\t1.ox\\n...\\n\tx..\\n\n'
	printf 'ok\t0\t-1\t-1\t2.ox\\noo\\noo\\n\too\\noo\\n\n'
} > "$WORK/bs/tie_corpus"
printf "#!/bin/sh\ncat '%s'\n" "$WORK/bs/tie_corpus" > "$WORK/bs/oracle_tie.sh"
printf '#!/bin/sh\nprintf %s\n' "'.x.\\n'" > "$WORK/bs/tie_wrong.sh"
chmod +x "$WORK/bs/oracle_tie.sh" "$WORK/bs/tie_wrong.sh"
want_out "bsq: the wrong one of several biggest squares quotes the call site's sentence" \
	'Toy, p.1: "the square nearest the top, then the left."' -- \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/tie_wrong.sh" \
	--oracle "$WORK/bs/oracle_tie.sh" --fn bsq_tie --show 0 --fixed 2
bs_tie() { "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/$1.sh" \
	--oracle "$WORK/bs/oracle_tie.sh" --fn bsq_tie --show 0 --fixed 2; }
want_out "bsq: ...as a square of the right size in the wrong place" 'FAULT [square-position]' -- bs_tie tie_wrong
# The right square in the right place, painted with the obstacle character:
# its place is not what is wrong, so neither the fault nor the tie sentence
# may say it is. It was "Right size, wrong place" beside a report that put
# both squares at line 1 column 1.
printf '#!/bin/sh\nprintf %s\n' "'o..\\n'" > "$WORK/bs/tie_char.sh"
chmod +x "$WORK/bs/tie_char.sh"
want_out "bsq: a square in its place with the wrong character is no position fault" \
	'FAULT [output]' -- bs_tie tie_char
want_broken_none "bsq: ...never square-position" 'square-position' -- bs_tie tie_char
want_broken_none "bsq: ...nor quoting the tie sentence" 'Toy, p.1' -- bs_tie tie_char
want_green "bsq: a message on stderr is not judged unless asked" -- bs_run chatty oracle_ok
want_out   "bsq: ...and the OK line says why" \
	'not judged: the selftest corpus is about stdout' -- bs_run chatty oracle_ok
want_red   "bsq: --stderr-empty fails a message about a valid map" -- bs_err chatty
want_out   "bsq: ...naming the fault" 'wrote-to-stderr' -- bs_err chatty
want_out   "bsq: ...showing what it wrote" 'a note' -- bs_err chatty
want_green "bsq: --stderr-empty passes a quiet solver" -- bs_err good
# A map that sends the program into a loop: each run's own cap (BSQ_TIMEOUT,
# 10s) is above what the test has left, so the TEST's limit stops the sweep,
# and says where.
printf '#!/bin/sh\nexec sleep 20\n' > "$WORK/bs/hangs.sh"; chmod +x "$WORK/bs/hangs.sh"
later_red_out "bsq: a sweep past the test's limit stops itself, saying so" \
	's: an infinite loop, or too slow on' -- $SHORT "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" \
		--bin "$WORK/bs/hangs.sh" --oracle "$WORK/bs/oracle_ok.sh" --show 0

# A shown failing case keeps the map it ran on, in test.outputs, and says how
# to run it again (finding 174): the corpus is generated and gone with the run.
bs_keep() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/bs/out" TEST_TARGET=//mod:ex00_bsq \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/catty.sh" --oracle "$WORK/bs/oracle_ok.sh" --show 1; }
want_out   "bsq: a shown failing case says how to replay it" \
	'replay: ./bsq case-1.map' -- bs_keep
want_green "bsq: ...and keeps the map it ran on" -- \
	grep -qx '2.ox' "$WORK/bs/out/case-1.map"

# MULTI MODE, MAP BY MAP (finding 174). A failing run of three maps was
# diagnosed as one map -- the classifier compared the group's whole output
# with "map error", so an invalid file that was answered anyway came out as
# "not-a-map", and the tally counted maps on one side and runs on the other.
# Now the output is split at its blank lines, the member that differs is named
# and diagnosed alone, every map of the run is kept, and the tally is in runs.
printf '#!/bin/sh\nn=0\nfor f in "$@"; do\n\t[ "$n" = 0 ] || echo\n\tn=1\n\tsed 1d "$f" | sed "s/[.]/x/g"\ndone\n' \
	> "$WORK/bs/multi_accept.sh"
printf '#!/bin/sh\nn=0\nfor f in "$@"; do\n\t[ "$n" = 0 ] || echo\n\tn=1\n\tif sed -n 1p "$f" | grep -q "oo$"; then echo "map error"; else sed 1d "$f" | sed "s/[.]/x/g"; fi\ndone\n' \
	> "$WORK/bs/multi_good.sh"
# ...and one that writes a line to stderr on every run, which is never graded.
printf '#!/bin/sh\necho "debug: %%s maps" "$#" >&2\nexec "%s" "%s" "$@"\n' "$SH" "$WORK/bs/multi_good.sh" \
	> "$WORK/bs/multi_noisy.sh"
chmod +x "$WORK/bs/multi_accept.sh" "$WORK/bs/multi_good.sh" "$WORK/bs/multi_noisy.sh"
bs_multi() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/bs/mout" TEST_TARGET=//mod:ex00_bsq_multi \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/$1.sh" --oracle "$WORK/bs/oracle_mixed.sh" \
	--mode multi --show 0; }
want_green "bsq multi: each map answered, a blank line between, passes" -- bs_multi multi_good
want_out   "bsq multi: ...and the tally counts runs" \
	'OK — 10/10 runs agree with the reference (30 maps, up to 3 per run)' -- bs_multi multi_good
want_red   "bsq multi: an invalid file answered as a map is red" -- bs_multi multi_accept
want_out   "bsq multi: ...named for what it is" 'FAULT [accepted-invalid-file]' -- bs_multi multi_accept
# What an invalid file prints is the subject's to say, so the fault quotes the
# call site's sentence and says it in no words of its own: "the only output is
# map error" was the runner's, and wrong for a run of several files.
want_out   "bsq multi: ...quoting the call site's sentence" \
	'Toy, p.2: "map error, then a newline."' -- bs_multi multi_accept
want_broken_none "bsq multi: ...and no rule of the runner's" 'The only output is' -- bs_multi multi_accept
want_broken_none "bsq multi: ...never as a problem with the lines printed" \
	'FAULT [not-a-map]' -- bs_multi multi_accept
want_out   "bsq multi: ...naming the map of the run that differs" \
	'map 1 of 3 is the first whose answer differs [err:chars_repeat]' -- bs_multi multi_accept
want_out   "bsq multi: ...its first line and how many lines follow it" \
	'its first line: "2.oo", followed by 2 line(s)' -- bs_multi multi_accept
want_out   "bsq multi: ...runs on both sides of the tally" \
	'FAIL — 8/10 runs agree, 2 differ (30 maps, up to 3 per run).' -- bs_multi multi_accept
want_out   "bsq multi: ...and every map of a failing run is kept to replay" \
	'replay: ./bsq run-9-1.map run-9-2.map run-9-3.map' -- bs_multi multi_accept
want_green "bsq multi: ...holding that run's maps" -- \
	grep -qx '2.oo' "$WORK/bs/mout/run-9-3.map"
want_green "bsq multi: stderr is not graded" -- bs_multi multi_noisy
want_out   "bsq multi: ...but said" '10 case(s) also wrote to standard error (not graded' -- \
	bs_multi multi_noisy
# Every byte of a want or got line is visible: a control byte in a map
# character used to reach the terminal raw, where it prints as nothing.
{
	_i=0
	while [ "$_i" -lt 21 ]; do
		printf 'ok\t1\t0\t0\t2.\\001x\\n.\\001\\n..\\n\tx\\001\\n..\\n\n'
		_i=$((_i + 1))
	done
	printf 'ok\t0\t-1\t-1\t1.o\\001\\no\\n\to\\n\n'
} | st_oracle "$WORK/bs/oracle_ctl.sh"
printf '#!/bin/sh\nfor f in "$@"; do sed 1d "$f"; done\n' > "$WORK/bs/ctl_catty.sh"
chmod +x "$WORK/bs/ctl_catty.sh"
bs_ctl() { "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/ctl_catty.sh" \
	--oracle "$WORK/bs/oracle_ctl.sh" --show 1; }
want_out "bsq: a control byte in a map is shown as \\xHH" 'want | x\x01' -- bs_ctl
want_out "bsq: ...on the got line too" 'got  | .\x01' -- bs_ctl
# The legend under them names the marks the shown lines hold (runner_lib's
# rl_shown_legend): a fixed one named a tab, a backslash and a dollar under
# maps holding none of them.
want_out "bsq: the legend names the marks the shown lines hold" \
	'(byte for byte: \xHH any other byte' -- bs_ctl
want_broken_none "bsq: ...and none they do not" 'a tab' -- bs_ctl
want_broken_none "bsq: ...nor any where they hold no mark" 'a tab' -- bs_keep

# DIFF_MAX_ROWS, the one knob (finding 167): BSQ_MAX_FAILS is gone.
want_out "bsq: DIFF_MAX_ROWS caps the cases it prints" \
	'22 more failing case(s) not shown' -- \
	env DIFF_MAX_ROWS=2 "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/catty.sh" \
		--oracle "$WORK/bs/oracle_ok.sh"
# UNDER A MEMORY CHECKER (finding 113): memory and endings only, never the map.
# The fakes write what a sanitizer writes, and end the way abort_on_error ends
# a run; catty prints every map back wrong and is memory-clean.
printf '#!/bin/sh\nfor f in "$@"; do grep -q "^9[.]" "$f" && { echo "==1==ERROR: AddressSanitizer: heap-buffer-overflow" >&2; kill -ABRT $$; }; done\nexit 0\n' \
	> "$WORK/bs/san9.sh"
chmod +x "$WORK/bs/san9.sh"
bs_san() { "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --bin "$WORK/bs/$1.sh" --oracle "$WORK/bs/oracle_ok.sh" \
	--sanitized; }
want_red   "bsq --sanitized: a sanitizer report is red" -- bs_san san9
want_out   "bsq --sanitized: ...naming the map it came on" 'CASE 15  [sanitizer]' -- bs_san san9
want_out   "bsq --sanitized: ...with the report" 'heap-buffer-overflow' -- bs_san san9
want_green "bsq --sanitized: a wrong but memory-clean answer is not its finding" -- bs_san catty
want_out   "bsq --sanitized: ...and says the maps' names were unwatched" \
	'Reads inside the argument strings, or past argv'"'"'s end, are invisible' -- bs_san catty
want_broken_none "bsq --sanitized: ...but not on standard input, with no argument" \
	'Reads inside the argument strings' -- \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --bin "$WORK/bs/catty.sh" --oracle "$WORK/bs/oracle_ok.sh" \
		--mode stdin --sanitized
want_red   "bsq --sanitized: a crash is" -- bs_san crashes
# A report that names the map names the scratch copy the runner handed the
# program, gone when the test ends; the case keeps it as case-N.map and
# replays it under that name, which the report now shows.
printf '#!/bin/sh\nfor f in "$@"; do grep -q "^9[.]" "$f" && { echo "==1==ERROR: AddressSanitizer: heap-buffer-overflow while reading $f" >&2; kill -ABRT $$; }; done\nexit 0\n' \
	> "$WORK/bs/sanpath9.sh"
chmod +x "$WORK/bs/sanpath9.sh"
# Kept in a folder of its own, as under bazel test.
bs_sank() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/bs/outs" TEST_TARGET=//mod:ex00_bsq_asan \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --bin "$WORK/bs/$1.sh" --oracle "$WORK/bs/oracle_ok.sh" \
	--sanitized; }
want_out   "bsq --sanitized: a report naming the map shows the kept name" \
	'heap-buffer-overflow while reading case-15.map' -- bs_sank sanpath9
want_out   "bsq --sanitized: ...and says it did" \
	'shown by the name it is kept under: case-15.map)' -- bs_sank sanpath9
# ...but only a map that was kept: run by hand, outside bazel test, there is
# nowhere to keep one, and the report named case-15.map, a file that exists
# nowhere, under a line saying the map was not kept.
bs_sanh() { env -u TEST_UNDECLARED_OUTPUTS_DIR "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" \
	--bin "$WORK/bs/$1.sh" --oracle "$WORK/bs/oracle_ok.sh" --sanitized; }
want_out   "bsq --sanitized: by hand the map is said not kept" \
	'generated for this case (a run under bazel test keeps it)' -- bs_sanh sanpath9
want_broken_none "bsq --sanitized: ...and the report names no kept map" 'case-15.map' -- bs_sanh sanpath9
# A RUN THAT DID NOT FINISH IS NOT A FINDING (V48, ruling R4): a program too
# slow for the 9 x 9 maps under the sanitizer was "2 of 24 case(s) under
# ASan/UBSan went wrong", beside a plain replay that says no answer was
# judged wrong. Still red -- two cases were not judged -- and said apart,
# beside a sanitizer report when there is one.
printf '#!/bin/sh\nfor f in "$@"; do grep -q "^9[.]" "$f" && sleep 5; done\nexit 0\n' > "$WORK/bs/slow9.sh"
printf '#!/bin/sh\nfor f in "$@"; do grep -q "^9[.]" "$f" && sleep 5; grep -q "^5[.]" "$f" && { echo "==1==ERROR: AddressSanitizer: heap-buffer-overflow" >&2; kill -ABRT $$; }; done\nexit 0\n' \
	> "$WORK/bs/slow9san5.sh"
chmod +x "$WORK/bs/slow9.sh" "$WORK/bs/slow9san5.sh"
bs_slow() { "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --bin "$WORK/bs/$1.sh" --oracle "$WORK/bs/oracle_ok.sh" \
	--sanitized --timeout 1 --show 0 > "$WORK/bs/$1.out" 2>&1; echo "$?" > "$WORK/bs/$1.rc"; }
! st_mine || { bs_slow slow9; bs_slow slow9san5; }
bs_slow_seen() { cat "$WORK/bs/$1.out"; return "$(cat "$WORK/bs/$1.rc")"; }
want_red   "bsq --sanitized: runs that did not finish are red" -- bs_slow_seen slow9
want_out   "bsq --sanitized: ...said as not finished" \
	'2 of 24 case(s) under ASan/UBSan did not finish in their time' -- bs_slow_seen slow9
want_out   "bsq --sanitized: ...and no case judged wrong" 'No case was judged wrong' -- bs_slow_seen slow9
want_broken_none "bsq --sanitized: ...never as gone wrong" 'went wrong' -- bs_slow_seen slow9
want_out   "bsq --sanitized: ...and apart from a finding beside them" \
	'2 of 24 case(s) under ASan/UBSan went wrong, and 2 did not' -- bs_slow_seen slow9san5
# Multi mode under a checker: a run of three maps is the case, as in the plain
# replay. It used to be refused, so the grouped corpus -- where one map's
# leftovers meet the next map's reading -- was memory-checked by no target.
# san_err dies the way abort_on_error ends a run when any map of it is invalid.
printf '#!/bin/sh\nfor f in "$@"; do grep -q "^2[.]oo" "$f" && { echo "==1==ERROR: AddressSanitizer: heap-use-after-free" >&2; kill -ABRT $$; }; done\nexit 0\n' \
	> "$WORK/bs/san_err.sh"
chmod +x "$WORK/bs/san_err.sh"
bs_san_multi() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/bs/smout" TEST_TARGET=//mod:ex00_bsq_multi_diff_asan \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --bin "$WORK/bs/$1.sh" --oracle "$WORK/bs/oracle_mixed.sh" \
	--mode multi --sanitized --show 0; }
want_red   "bsq --sanitized: multi mode runs a group under the checker" -- bs_san_multi san_err
want_out   "bsq --sanitized: ...naming the run and the maps in it" \
	'RUN 9  [sanitizer]  maps 25-27 of the corpus: err:chars_repeat' -- bs_san_multi san_err
want_out   "bsq --sanitized: ...kept to replay whole" \
	'replay: ./bsq run-9-1.map run-9-2.map run-9-3.map' -- bs_san_multi san_err
want_out   "bsq --sanitized: ...counting runs on both sides" \
	'FAIL — 2 of 10 run(s) under ASan/UBSan went wrong' -- bs_san_multi san_err
want_green "bsq --sanitized: multi mode, a memory-clean program passes" -- bs_san_multi multi_good
want_out   "bsq --sanitized: ...saying every run ran" \
	'all 10 run(s) of the corpus ran under ASan/UBSan' -- bs_san_multi multi_good
# Output without end under a checker is RUNAWAY OUTPUT, as in the plain
# replay. The output went to /dev/null, which `ulimit -f` does not cap, so
# the program ran out its time and was reported as a hang (a review of
# finding 113's runners reproduced it on rush02_check). runaway prints
# without end on the two 2 x 2 maps and answers nothing else.
printf '#!/bin/sh\ngrep -q "^2[.]" "$1" && exec cat /dev/zero\nexit 0\n' > "$WORK/bs/runaway.sh"
chmod +x "$WORK/bs/runaway.sh"
want_out   "bsq --sanitized: output without end is RUNAWAY, not a hang" 'CASE 1  [runaway]' -- \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --bin "$WORK/bs/runaway.sh" --oracle "$WORK/bs/oracle_ok.sh" \
		--sanitized --timeout 3 --show 1
# A run the TEST's limit cut short is not one judged wrong (rl_mem_stopped):
# counted as one, the report blamed "the case(s) judged wrong before that"
# when none was, and never said the machine may only have been busy.
later_red_out "bsq --sanitized: a run cut by the test's limit is not judged wrong" \
	"this test's own time limit" -- $SHORT "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" \
		--bin "$WORK/bs/hangs.sh" --oracle "$WORK/bs/oracle_ok.sh" --sanitized --show 0


# The floors. Each names a wrong program that would otherwise pass, and each is
# exit 2 -- a corpus that cannot fail anything is a broken harness, not a wrong
# deliverable -- with the floor's own sentence, since an unknown option or a
# missing flag is exit 2 too (want_broken).
want_broken "bsq: an EMPTY corpus is a harness error, not 0/0" \
	'fewer than the 20 this layer needs' -- bs_run good oracle_empty

# ...and an oracle that fails says why: its stderr is shown, not discarded.
printf '#!/bin/sh\necho oracle-said-this >&2\nexit 1\n' > "$WORK/bs/oracle_says.sh"
chmod +x "$WORK/bs/oracle_says.sh"
want_broken "bsq: an oracle that fails is shown saying why" 'oracle-said-this' -- \
	bs_run good oracle_says

# multi mode without both classes must refuse: a corpus of valid maps alone
# cannot catch "always print map error", and one of invalid files alone cannot
# catch the opposite.
want_broken "bsq: multi mode refuses a single-class corpus" \
	'--mode multi needs a corpus holding BOTH valid and invalid' -- \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/good.sh" \
		--oracle "$WORK/bs/oracle_ok.sh" --mode multi

# THE ESCAPE, end to end. The corpus carries whole files on one line, and the
# shell decodes them with `printf %b` -- which in dash knows \0NNN and does NOT
# know \xHH. A map whose characters include a backslash has to survive that
# round trip exactly, or every case built on it is compared against the wrong
# bytes, and the layer grades a correct program against a corrupted map.
#
# empty is a SPACE and obstacle is a BACKSLASH here on purpose: both are legal
# map characters (the subject names the space explicitly), and both are exactly
# what an escape gets wrong.
_ESC_F='1 \\x\n \\\n'
_ESC_E='x\\\n'
_ESC_F0='1 \\x\n\\\n'
_ESC_E0='\\\n'
: > "$WORK/bs/esc_corpus"
_i=0
while [ "$_i" -lt 22 ]; do
	printf 'ok\t1\t0\t0\t%s\t%s\n' "$_ESC_F" "$_ESC_E" >> "$WORK/bs/esc_corpus"
	_i=$((_i + 1))
done
# The floor needs a side-0 record too, or the runner rightly refuses the corpus.
printf 'ok\t0\t-1\t-1\t%s\t%s\n' "$_ESC_F0" "$_ESC_E0" >> "$WORK/bs/esc_corpus"
printf "#!/bin/sh\ncat '%s'\n" "$WORK/bs/esc_corpus" > "$WORK/bs/oracle_esc.sh"
# Reads the map and answers it: drop the header, fill the one empty cell. It
# touches BOTH decoded blobs, so a broken escape on either side fails the arm.
printf '#!/bin/sh\nfor f in "$@"; do sed 1d "$f" | sed "s/ /x/"; done\n' \
	> "$WORK/bs/escgood.sh"
chmod +x "$WORK/bs/oracle_esc.sh" "$WORK/bs/escgood.sh"

want_green "bsq: a backslash and a space survive the corpus escape" -- \
	bs_run escgood oracle_esc

# A BLOB THAT STARTS WITH A SPACE keeps it. The records are read back with
# `IFS= read -r` (bsq_check.sh, "EACH RECORD, SPLIT ONCE"), and a plain `read`
# strips leading blanks -- here the expected answer's first cell, a space, the
# subject's own example of a legal map character. The fake answers by looking
# the map up, not by solving it.
{
	_i=0
	while [ "$_i" -lt 21 ]; do
		printf 'ok\t2\t1\t1\t3 ox\\n o \\no  \\no  \\n\t o \\noxx\\noxx\\n\n'
		_i=$((_i + 1))
	done
	printf 'ok\t0\t-1\t-1\t1 ox\\no\\n\to\\n\n'
} > "$WORK/bs/space_corpus"
printf "#!/bin/sh\ncat '%s'\n" "$WORK/bs/space_corpus" > "$WORK/bs/oracle_space.sh"
printf '#!/bin/sh\nfor f in "$@"; do case "$(sed -n 1p "$f")" in "3 ox") printf " o \\noxx\\noxx\\n" ;; *) sed 1d "$f" ;; esac; done\n' \
	> "$WORK/bs/spacey.sh"
chmod +x "$WORK/bs/oracle_space.sh" "$WORK/bs/spacey.sh"
want_green "bsq: an answer that starts with a space keeps it" -- bs_run spacey oracle_space

# A FIXED LIST OF BIG MAPS (--fixed N, the bsq_big targets): a map of 810 000
# cells, and its answer as big, on one corpus record. Splitting that record
# with ${line#*TAB} took dash minutes (quadratic: 6.7 s at 160 KB a blob); it
# is now split once by awk. The fake is good.sh: the map is square and
# all-empty, so its answer is the whole map filled.
_bs_big() {  # _bs_big N -- an N x N all-empty map and its answer, as one record
	awk -v n="$1" 'BEGIN {
		row = ""; full = ""
		for (j = 0; j < n; j++) { row = row "."; full = full "x" }
		m = n ".ox\\n"; a = ""
		for (i = 0; i < n; i++) { m = m row "\\n"; a = a full "\\n" }
		printf "ok\t%d\t0\t0\t%s\t%s\n", n, m, a
	}'
}
{ _bs_big 900; printf 'ok\t0\t-1\t-1\t2.ox\\noo\\noo\\n\too\\noo\\n\n'; } > "$WORK/bs/big_corpus"
printf "#!/bin/sh\ncat '%s'\n" "$WORK/bs/big_corpus" > "$WORK/bs/oracle_big.sh"
chmod +x "$WORK/bs/oracle_big.sh"
bs_fixed() { "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/$1.sh" --oracle "$WORK/bs/oracle_big.sh" \
	--fn bsq_big --show 0 --fixed "$2"; }
bs_big_fast() {
	_bf0=$(date +%s)
	bs_fixed good 2 > "$WORK/bs/big.out" 2>&1
	_bfrc=$?
	_bf1=$(date +%s)
	cat "$WORK/bs/big.out"
	[ "$_bfrc" -eq 0 ] || return "$_bfrc"
	[ $((_bf1 - _bf0)) -lt 30 ] && return 0
	echo "took $((_bf1 - _bf0)) s for two maps"
	return 1
}
want_green "bsq: a map of 810 000 cells is replayed in seconds" -- bs_big_fast
want_red   "bsq: ...and judged: printing it back is still wrong" -- bs_fixed catty 2
want_broken "bsq: --fixed holds the list to its exact count" 'fixed' -- bs_fixed good 3
# Without --fixed, two maps are a seeded corpus too small to prove anything.
want_broken "bsq: ...and without it the floor of 20 holds" \
	'fewer than the 20 this layer needs' -- bs_run good oracle_big
# A count that is not one is a wiring mistake, refused before the corpus is
# read. '1x0' got past a glob that took `*` for "any digits", and the count
# test then failed as a shell error, skipping both floors on the corpus's size.
bs_opt() { "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/good.sh" \
	--oracle "$WORK/bs/oracle_ok.sh" --show 0 "$@"; }
want_broken "bsq: --fixed 1x0 is not a count of maps" '--fixed must be a count of maps' -- bs_opt --fixed 1x0
want_broken "bsq: ...nor --count x a count of maps" '--count must be a count of maps' -- bs_opt --count x
want_broken "bsq: ...nor --group 0 one of maps per run" '--group must be a count of maps' -- bs_opt --group 0
want_broken "bsq: ...nor --seed x a seed" '--seed must be a whole number' -- bs_opt --seed x
# A corpus whose every valid map has a square of side 0 is answered by its own
# rows, so a program that prints each map's rows back (its header dropped)
# passes it. That floor compared the whole file, header included, with the
# answer, so every map "differed" and it never fired.
{
	_i=2
	while [ "$_i" -le 23 ]; do
		_orow=""; _j=0
		while [ "$_j" -lt "$_i" ]; do _orow="${_orow}o"; _j=$((_j + 1)); done
		_ob=""; _j=0
		while [ "$_j" -lt "$_i" ]; do _ob="$_ob$_orow\\n"; _j=$((_j + 1)); done
		printf 'ok\t0\t-1\t-1\t%s.ox\\n%s\t%s\n' "$_i" "$_ob" "$_ob"
		_i=$((_i + 1))
	done
} | st_oracle "$WORK/bs/oracle_zero.sh"
printf '#!/bin/sh\nfor f in "$@"; do sed 1d "$f"; done\n' > "$WORK/bs/rowsback.sh"
chmod +x "$WORK/bs/rowsback.sh"
want_broken "bsq: a corpus a program printing the rows back passes is refused" \
	'prints its rows back' -- bs_run rowsback oracle_zero
# --timeout sets one run's own limit, for the big maps' generous one.
want_out "bsq: --timeout sets one run's own limit" 'did not finish within 1s' -- \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/hangs.sh" --oracle "$WORK/bs/oracle_big.sh" \
		--fixed 2 --timeout 1 --show 0
# ...and a map that did not finish is never called wrong: the subject sets no
# time limit, so that limit guards against a hang and nothing else (the
# owner's ruling R4). The tally used to read "0/2 maps agree, 2 differ" over
# two runs whose output was never compared.
bs_slow() { "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/hangs.sh" \
	--oracle "$WORK/bs/oracle_big.sh" --fixed 2 --timeout 1 --show 0; }
later_red_out "bsq: a map that did not finish is red, never wrong" \
	'No answer was judged wrong' -- bs_slow

# A program that never built is not hundreds of maps it got wrong (finding 173).
cp "$STANDIN_BIN" "$WORK/bs/built_nothing.sh"
want_red   "bsq: a stand-in is red"                            -- bs_run built_nothing oracle_ok
want_out   "bsq: ...says the code did not build" "$STANDIN_SAYS"    -- bs_run built_nothing oracle_ok
want_broken_none "bsq: ...and tallies no map" 'agree' -- bs_run built_nothing oracle_ok
want_out   "bsq --sanitized: a stand-in is a SKIP" 'was never built' -- \
	env -u NO_SKIP "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --bin "$WORK/bs/built_nothing.sh" \
		--oracle "$WORK/bs/oracle_ok.sh" --sanitized
want_red   "bsq --sanitized: ...and NO_SKIP=1 turns it red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --bin "$WORK/bs/built_nothing.sh" \
		--oracle "$WORK/bs/oracle_ok.sh" --sanitized

# A valid map no square fits is printed unchanged, and a failure on one says
# so: it used to report "the biggest square is 0x0, at line 0 column 0".
want_out   "bsq: a side-0 map's failure says no square fits" \
	'no square fits: it is printed unchanged' -- \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/allerr.sh" --oracle "$WORK/bs/oracle_ok.sh" --show 2
want_broken_none "bsq: ...and never names a 0x0 square" 'is 0x0' -- \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/allerr.sh" --oracle "$WORK/bs/oracle_ok.sh" --show 2

# --readings: a readings corpus (bsq_readings) is certain only under the one
# reading its target takes, so a failure says that, and never that a sentence
# of the subject settles the file; --clues prints the hints that state the
# reading, on a failing run only, and never a maintainer's '#' line.
#
# Every record of a readings corpus names the open form it holds (ok:<form>,
# err:<form>), so the fake one is oracle_ok's with each valid map tagged as a
# count written with a leading zero -- the runner cannot see the map's bytes
# say so, and does not need to: what is under test is the words it prints.
printf '# a maintainer note\nWhich reading does this target take?\n' > "$WORK/bs/clues_readings.tsv"
printf '#!/bin/sh\n"%s" "%s" | sed "s/^ok\t/ok:count_leading_zero\t/"\n' \
	"$SH" "$WORK/bs/oracle_ok.sh" > "$WORK/bs/oracle_readings.sh"
printf '#!/bin/sh\n"%s" "%s" | sed "s/^ok\t/ok:made_up_form\t/"\n' \
	"$SH" "$WORK/bs/oracle_ok.sh" > "$WORK/bs/oracle_unworded.sh"
chmod +x "$WORK/bs/oracle_readings.sh" "$WORK/bs/oracle_unworded.sh"
bs_read() { _bsr=$1; shift; "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/$_bsr.sh" \
	--oracle "$WORK/bs/oracle_readings.sh" --show 1 "$@"; }
# A failing case names the form its file holds, not only that it is valid:
# "CASE 5 [ok] ... got map error" once sent a student into the kept map to
# find a missing final newline.
want_out   "bsq: a readings failure names the form the file holds" \
	'the file: its count is written with a leading zero' -- bs_read allerr --readings
# ...and a corpus that cannot say it is refused before a student run: a
# readings record without its form, a form with no sentence, and a form in a
# corpus whose target takes no reading.
want_broken "bsq: a readings record without its form is refused" \
	'without the form it holds' -- "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/good.sh" \
	--oracle "$WORK/bs/oracle_ok.sh" --readings
want_broken "bsq: ...and one whose form has no sentence" \
	'no sentence for' -- "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/good.sh" \
	--oracle "$WORK/bs/oracle_unworded.sh" --readings
want_broken "bsq: ...and an open form outside --readings" \
	'not a --readings corpus' -- bs_run good oracle_readings
want_out   "bsq: --readings names the target's reading on a failure" \
	"under this harness's reading" -- bs_read catty --readings
want_out   "bsq: ...and so does the fault under it" \
	"Under this harness's reading, this file is valid" -- bs_read allerr --readings
# ...and a file the reading makes invalid, answered as a map, quotes the call
# site's sentence for what an invalid file prints, as the fault outside a
# reading does.
{
	printf '#!/bin/sh\n"%s" "%s"\n' "$SH" "$WORK/bs/oracle_readings.sh"
	printf 'printf %s\n' "'err:count_leading_zero\\t-1\\t-1\\t-1\\t02.ox\\\\n..\\\\n..\\\\n\\tmap error\\\\n\\n'"
} > "$WORK/bs/oracle_readings_err.sh"
chmod +x "$WORK/bs/oracle_readings_err.sh"
bs_read_err() { "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/good.sh" \
	--oracle "$WORK/bs/oracle_readings_err.sh" --show 1 --readings; }
want_out   "bsq: ...and an invalid one answered quotes the sentence" \
	'Toy, p.2: "map error, then a newline."' -- bs_read_err
want_broken_none "bsq: ...in no words of the runner's" 'the only output is' -- bs_read_err
want_broken_none "bsq: ...and without it, a failure claims no reading" \
	"this harness's reading" -- "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/catty.sh" \
	--oracle "$WORK/bs/oracle_ok.sh" --show 1
# The full character in a row of the map is an open form too (bsq_readings'
# full_in_body): its record is worded, not refused as a form with no sentence.
{
	printf '#!/bin/sh\n"%s" "%s"\n' "$SH" "$WORK/bs/oracle_readings.sh"
	printf 'printf %s\n' "'err:full_in_body\\t-1\\t-1\\t-1\\t2.ox\\\\n..\\\\n.x\\\\n\\tmap error\\\\n\\n'"
} > "$WORK/bs/oracle_readings_full.sh"
chmod +x "$WORK/bs/oracle_readings_full.sh"
want_out   "bsq: a readings record with the full character in a row names that form" \
	'the file: a row of its map holds its "full" character.' -- \
	"$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" --stderr-ignored "$BS_WHY" --bin "$WORK/bs/good.sh" \
	--oracle "$WORK/bs/oracle_readings_full.sh" --show 1 --readings
want_out   "bsq: a failing run prints its hints" 'Which reading does this target take?' -- \
	bs_read catty --readings --clues "$WORK/bs/clues_readings.tsv"
want_broken_none "bsq: ...never a maintainer's line of them" 'a maintainer note' -- \
	bs_read catty --readings --clues "$WORK/bs/clues_readings.tsv"
want_broken_none "bsq: ...and a passing run none" 'Which reading' -- \
	bs_read good --readings --clues "$WORK/bs/clues_readings.tsv"
# In the program's one clues.tsv, the target's own rows are keyed to the
# name it passes as --case, beside the rows of the program's cases (ruling
# R7): it shows its own, never a case's.
printf 'Which reading does this target take?\treadings\nWhat does open return here?\tmissing_alone\n' \
	> "$WORK/bs/clues_keyed.tsv"
want_out   "bsq: --case shows the rows keyed to the target" 'Which reading does this target take?' -- \
	bs_read catty --readings --clues "$WORK/bs/clues_keyed.tsv" --case readings
want_broken_none "bsq: ...and none keyed to a case of the program" 'What does open return' -- \
	bs_read catty --readings --clues "$WORK/bs/clues_keyed.tsv" --case readings
# ...and a run the test's limit stops is a failing run too: a readings case
# shown before the stop said its hints were below, and the stop printed none.
# The 2x2 maps are printed back (wrong), every other one waits 0.6s, and the
# test's 10s run out before the 24 maps do.
printf '#!/bin/sh\ncase "$(head -c 2 "$1")" in\n  2.) cat "$1" ;;\n  *) sleep 0.6; sed 1d "$1" | sed "s/[.]/x/g" ;;\nesac\n' \
	> "$WORK/bs/slow_catty.sh"
chmod +x "$WORK/bs/slow_catty.sh"
later_red_out "bsq: ...and a run cut short by the test's limit prints them" \
	'Which reading does this target take?' -- $SHORT "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" \
		--stderr-ignored "$BS_WHY" --bin "$WORK/bs/slow_catty.sh" --oracle "$WORK/bs/oracle_readings.sh" \
		--show 1 --readings --clues "$WORK/bs/clues_readings.tsv"
# ...as it names the marks of the want and got lines it showed, as a run
# that ended does.
later_red_out "bsq: ...and names the marks of the lines it showed" \
	'$ is where a line ended.' -- $SHORT "$SH" "$TOOLS/bsq_check.sh" --quotes "$BS_QUOTES" \
		--stderr-ignored "$BS_WHY" --bin "$WORK/bs/slow_catty.sh" --oracle "$WORK/bs/oracle_ok.sh" --show 1

