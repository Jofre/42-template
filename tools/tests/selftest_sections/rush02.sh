# ------------------------------------------------------------------ rush02
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The only check c-piscine-rush-02 has, and it had a false green of the exact
# shape this file exists to hunt: an oracle that exited 0 having printed nothing
# left the compare loop with no cases to run, and the report read
# "OK -- 0/0 agree with the reference". Found by writing these arms, not by
# reading the script. tools/rust_diff.sh had already grown MIN_DIFF_CASES for the
# same reason; this runner had not.
#
# The empty-corpus arm asserts exit 2, not 1: a reference that produces
# nothing is a broken HARNESS, not a wrong student. So it is a want_broken,
# the status and the floor's own sentence (rl_corpus_floor's), which no
# other refusal of this runner prints.
mkdir -p "$WORK/r2"
printf '0: zero\n' > "$WORK/r2/dict.txt"
printf '#!/bin/sh\nexit 0\n' > "$WORK/r2/oracle_empty.sh"
{
	_i=0
	while [ "$_i" -lt 30 ]; do printf '%s\tn%s\n' "$_i" "$_i"; _i=$((_i + 1)); done
} | st_oracle "$WORK/r2/oracle_full.sh"
# Agrees with that reference: echoes "n<number>", which is what it emits.
printf '#!/bin/sh\nprintf "n%%s\\n" "$2"\n' > "$WORK/r2/agree.sh"
printf '#!/bin/sh\nprintf "wrong\\n"\n' > "$WORK/r2/disagree.sh"
chmod +x "$WORK/r2"/*.sh

# Every call says what stderr is held to (rush02_check.sh refuses one that
# does not with exit 2, as its floor does: so the floor arm below asks for
# the floor's own words too).
R2_WHY="the selftest corpus is about stdout"
# WHAT A REFUSAL SAID. An arm reads the runner's status, and exit 2 is the
# harness's own fault, never a verdict: one run on a loaded machine failed 22
# of these arms with "exit 2 = harness error" and nothing else, the next run
# passed, and no log said what had refused. This section then called the
# runner through a wrapper of its own that wrote the words to the log, and no
# other section had one (TO VERIFY V172). Every helper now prints them under
# its FAIL line, and st_said_meta (tools/tests/selftest_lib.sh) proves it of
# each, on a toy that refuses as a runner does; its arm is still here.
want_green "rush02: a runner that refuses says why in the log" -- st_said_meta
# And a toy that did not build says so, a FAIL with the compiler's words
# (toy_cc, the same library), rather than leaving this section's runner a
# --bin it calls a red: proven here as selftest_slow.sh proves it.
want_green "selftest: a toy that does not build is a FAIL, with the compiler's words" -- \
	toy_cc_meta
r2_run() { "$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/$1.sh" \
	--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/$2.sh"; }

want_green "rush02: a converter matching the reference passes" -- once r2_run agree oracle_full
want_red   "rush02: one that disagrees everywhere fails"        -- r2_run disagree oracle_full

# THE REPLAY GUARDS the three sibling runners have and this one did not.
#
# eatstdin agrees with the reference on every case it is asked, and reads stdin.
# The compare loop reads the corpus on the shell's own stdin, so without
# `< /dev/null` on the child the FIRST case swallowed the remaining 29 and the
# runner printed "OK — 1/1 agree" under a header announcing 30. It is a pass
# bought by consuming the evidence, and it is the reason a count assertion has
# to exist as well as a redirect: either one alone leaves the other's failure
# mode reportable as success.
#
# crasher prints the right answer and then dies. The child's status was
# discarded, so byte-for-byte agreement over a corpse counted as agreement.
printf '#!/bin/sh\ncat > /dev/null\nprintf "n%%s\\n" "$2"\n' > "$WORK/r2/eatstdin.sh"
printf '#!/bin/sh\nprintf "n%%s\\n" "$2"\nkill -SEGV $$\n' > "$WORK/r2/crasher.sh"
chmod +x "$WORK/r2/eatstdin.sh" "$WORK/r2/crasher.sh"
want_green "rush02: a converter that also reads stdin still replays all cases" -- \
	once r2_run eatstdin oracle_full
want_out "rush02: ...and every case is compared, not just the first" '30/30 agree' -- \
	once r2_run eatstdin oracle_full
want_red   "rush02: the right answer, then a signal death, is not agreement" -- \
	r2_run crasher oracle_full
# ...and the right answer, then `return (-1);`, is: 255 is a status it
# returned, not a death by "signal 127" (tools/exit_status asks waitpid()),
# and no status is this layer's to judge.
printf '#!/bin/sh\nprintf "n%%s\\n" "$2"\nexit 255\n' > "$WORK/r2/ret255.sh"
chmod +x "$WORK/r2/ret255.sh"
want_green "rush02: the right answer and a return of 255 is agreement" -- \
	r2_run ret255 oracle_full
# A run stopped from outside -- here the toy signals its waiter,
# tools/exit_status -- says nothing of the program: exit 2, never a case
# filed as differing from the reference.
printf '#!/bin/sh\nkill -TERM $PPID; sleep 1\nprintf "n%%s\\n" "$2"\n' > "$WORK/r2/stopped.sh"
chmod +x "$WORK/r2/stopped.sh"
want_broken "rush02: a run stopped from outside is no verdict, exit 2" \
	'could not be judged: the program was stopped from outside' -- r2_run stopped oracle_full

# STANDARD ERROR, A CHOICE AT EVERY CALL (review of WP-50): this runner threw
# it away on every run. Now the call says what it is held to.
printf '#!/bin/sh\nprintf "n%%s\\n" "$2"\necho "a note" >&2\n' > "$WORK/r2/chatty.sh"
chmod +x "$WORK/r2/chatty.sh"
r2_err() { "$SH" "$TOOLS/rush02_check.sh" --stderr-empty --show 2 --bin "$WORK/r2/$1.sh" \
	--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh"; }
want_broken "rush02: a call that says nothing of stderr refuses" \
	'say what standard error is held to' -- \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/agree.sh" \
	--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh"
want_green "rush02: a message on stderr is not judged unless asked" -- once r2_run chatty oracle_full
want_out   "rush02: ...and the OK line says why" \
	'not judged: the selftest corpus is about stdout' -- once r2_run chatty oracle_full
want_red   "rush02: --stderr-empty fails a message about a valid input" -- once r2_err chatty
want_out   "rush02: ...showing what it wrote, beside the same words" 'a note' -- once r2_err chatty
want_out   "rush02: ...and not calling the words different" 'the same words, byte for byte' -- \
	once r2_err chatty
want_green "rush02: --stderr-empty passes a quiet converter" -- r2_err agree

# The converter was run with no limit at all (finding 066).
printf '#!/bin/sh\nexec sleep 20\n' > "$WORK/r2/hangs.sh"; chmod +x "$WORK/r2/hangs.sh"
later_red_out "rush02: a converter that never ends is stopped, and said to be" \
	's: an infinite loop, or too slow on' -- \
	$SHORT "$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/hangs.sh" \
		--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh"
# A RUN PAST ITS OWN LIMIT, THEN A STOP BETWEEN CASES (V84). The stop said
# "Each of the first 9 of 30 cases ended within its own limit" and "Either
# the program is slow on every input, or this machine was busy" under case
# 1, which had not; and the plain replay called that case "judged wrong ...
# a verdict all the same". Case 1 waits past its own 2 s, every other case
# takes 0.4 s, and the test's 7 s run out between two of them.
printf '#!/bin/sh\ncase "$2" in\n  0) exec sleep 30 ;;\n  *) sleep 0.4; printf "n%%s\\n" "$2" ;;\nesac\n' \
	> "$WORK/r2/hang_first.sh"
chmod +x "$WORK/r2/hang_first.sh"
r2_hang_first() { env -u RL_DEADLINE -u RL_BUDGET TEST_TIMEOUT=8 RL_MARGIN=1 RUSH02_TIMEOUT=2 \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/hang_first.sh" --dict "$WORK/r2/dict.txt" \
	--oracle "$WORK/r2/oracle_full.sh" "$@"; }
later_red_out "rush02 --sanitized: a stop after a run past its own limit names it" \
	'ran out of their own time limit' -- r2_hang_first --sanitized
later_red_none "rush02 --sanitized: ...never that every case ended within its own" \
	'ended within its own limit' -- r2_hang_first --sanitized
later_red_none "rush02: ...nor, in the plain replay, that it was judged wrong" \
	'judged wrong before that' -- r2_hang_first --stderr-ignored "$R2_WHY"
# ...and the stop names the marks of the lines it showed, as every other end
# of the report does: case 1's expected: line holds a \n, and the stop said
# what $ is and nothing of the \n.
later_red_out "rush02: ...and names the marks of the lines it showed" \
	'(byte for byte: \n a newline)' -- r2_hang_first --stderr-ignored "$R2_WHY"
later_red_out "rush02 --settled: ...as its stop does" \
	'(byte for byte: \n a newline)' -- r2_hang_first --stderr-ignored "$R2_WHY" --settled
# A RUN PAST ITS OWN LIMIT, AND NO STOP (V85). Every case ran, and the verdict
# counted the one that did not finish as a difference -- "29/30 agree, 1
# differ", then "a difference here is one of two things" -- while --settled
# listed it among the rules every reading agrees on. A run that did not
# finish is said, and red, and never judged (ruling R4). The number 0 prints
# "n0 " with no newline, then waits past its own 2 s: what it printed is
# shown to its end (V71).
printf '#!/bin/sh\ncase "$2" in\n  0) printf "n0 "; exec sleep 30 ;;\n  *) printf "n%%s\\n" "$2" ;;\nesac\n' \
	> "$WORK/r2/hang0.sh"
chmod +x "$WORK/r2/hang0.sh"
r2_hang0() { env RUSH02_TIMEOUT=2 "$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" \
	--bin "$WORK/r2/hang0.sh" --dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh" "$@"; }
later_red_out "rush02: a run past its own limit is counted apart" \
	'29/30 agree, and 1 did not finish within 2s each' -- r2_hang0
later_red_none "rush02: ...never as a difference" '1 differ' -- r2_hang0
later_red_out "rush02: ...and what it printed is shown to its end" \
	'having printed: n0 $' -- r2_hang0
later_red_out "rush02 --settled: ...counted apart there too" \
	'and 1 did not finish within 2s each' -- r2_hang0 --settled
later_red_none "rush02 --settled: ...never as a rule every reading agrees on" \
	'a run ends by itself under every reading' -- r2_hang0 --settled

# EVERY BYTE OF A SHOWN CASE (finding 158). The report was a table that cut
# the number at 24 characters and both strings at 34 without a mark, in the
# runner that exists for long numbers, and threw each generated dictionary
# away. Now a case is shown whole, through rl_vis, with where the strings part,
# and its dictionary is kept in test.outputs with the command that replays it.
{
	_i=0
	while [ "$_i" -lt 25 ]; do
		printf '0: zero\\n1: one\t1234567890123456789012345678901234567890\tone two three four five six seven eight nine ten\n'
		_i=$((_i + 1))
	done
} | st_oracle "$WORK/r2/oracle_long.sh"
cat > "$WORK/r2/long_wrong.sh" <<'R2_LONG'
#!/bin/sh
printf 'one two three four five six seven eight nine TEN\001\n'
R2_LONG
chmod +x "$WORK/r2/long_wrong.sh"
r2_long() { once env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/r2/out" TEST_TARGET=//mod:ex00_diff \
	"$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/long_wrong.sh" \
	--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_long.sh"; }
want_out "rush02: a long number is shown whole" \
	'number:   1234567890123456789012345678901234567890' -- r2_long
want_out "rush02: ...and where the two strings part" \
	'^ first difference: byte 46' -- r2_long
# The ^ sits under that byte in the lines above, which show escapes: after a
# \x01 it is further right than the byte count. Checked on a whole line.
r2_caret() { r2_long | grep -qx -- "$1"; }
want_green "rush02: ...with a ^ under it" -- \
	r2_caret "$(printf '%59s' '')^ first difference: byte 46"
# The legend names the marks the shown lines hold, \n as the newline that
# ends the words (rl_shown_legend): a fixed one named a backslash under
# words holding none.
want_out "rush02: the legend names the marks the shown lines hold" \
	'(byte for byte: \n a newline, and \xHH' -- r2_long
want_broken_none "rush02: ...and none they do not" 'backslash' -- r2_long
{
	_i=0
	while [ "$_i" -lt 20 ]; do
		printf '0: zero\\n1: one\t4%s2$x\\\\\001\tone\001two\n' "'"
		_i=$((_i + 1))
	done
} | st_oracle "$WORK/r2/oracle_quote.sh"
printf '#!/bin/sh\nprintf "one\\001twO\\n"\n' > "$WORK/r2/quote_wrong.sh"
chmod +x "$WORK/r2/quote_wrong.sh"
r2_quote() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/r2/outq" TEST_TARGET=//mod:ex00_diff \
	"$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/quote_wrong.sh" \
	--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_quote.sh"; }
r2_quote_caret() { r2_quote | grep -qx -- "$(printf '%23s' '')^ first difference: byte 7"; }
want_green "rush02: ...after an escape, the ^ moves with the rendering" -- r2_quote_caret
# The replay line is a command: its number, run by the shell, is the case's
# own bytes -- a quote, a $, two backslashes and a \001 among them.
r2_replay_back() {
	_rw=$(r2_quote | sed -n 's|^    replay:   ./rush-02 case-1.dict ||p' | head -n 1)
	[ -n "$_rw" ] || { echo "no replay line"; return 1; }
	_back=$("$SH" -c "printf '%s' $_rw" | od -An -tx1)
	_want=$(printf "4'2\$x\\\\\\\\\001" | od -An -tx1)
	[ "$_back" = "$_want" ] && return 0
	echo "replay word $_rw gave back$_back"
	return 1
}
want_green "rush02: ...and its replay line runs that very number" -- r2_replay_back
want_out "rush02: ...a byte that is not printable is shown as one" \
	'nine TEN\x01' -- r2_long
want_out "rush02: ...and its generated dictionary is kept to replay" \
	'kept as bazel-testlogs/mod/ex00_diff/test.outputs/case-1.dict' -- r2_long
# The FIXED dictionary is kept too, so its replay line also runs from
# test.outputs/: it named the dictionary's workspace path, which reached
# nothing from there.
r2_fixed() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/r2/outf" TEST_TARGET=//mod:ex00_diff \
	"$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/disagree.sh" \
	--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh" --show 1; }
want_out "rush02: a case on the fixed dictionary replays from test.outputs" \
	"replay:   ./rush-02 dict.txt '0'" -- r2_fixed
want_green "rush02: ...where that dictionary is kept" -- \
	grep -qx '0: zero' "$WORK/r2/outf/dict.txt"
want_green "rush02: ...holding that case's dictionary" -- \
	grep -qx '1: one' "$WORK/r2/out/case-1.dict"
# A LONG NUMBER IS SHOWN CUT. The corpora hold numbers of about a thousand
# digits, and a failing case printed each whole, its words too: the number:
# line, both outputs and the replay line, a thousand bytes or more each, and
# a ^ thousands of columns to the right. A corpus of such numbers, the first
# on a dictionary of its own and the rest on the fixed one, and a converter
# wrong at the last word of each: the number and both outputs are cut to
# their first 300 bytes, the rest counted, where they part is shown around
# that byte, and the replay line, which cannot be cut and still run, is kept
# as a file. Only what is shown is cut: every case ran on all its bytes.
_r2_num=$(LC_ALL=C awk 'BEGIN { s = "9"; for (i = 1; i < 1000; i++) s = s (i % 10); print s }')
_r2_words=$(LC_ALL=C awk 'BEGIN { s = "nine"; for (i = 1; i < 600; i++) s = s " nine"; print s }')
{
	printf '0: zero\\n9: nine\t%s\t%s\n' "$_r2_num" "$_r2_words"
	_i=1
	while [ "$_i" -lt 20 ]; do printf '%s\t%s\n' "$_r2_num" "$_r2_words"; _i=$((_i + 1)); done
} | st_oracle "$WORK/r2/oracle_huge.sh"
printf '#!/bin/sh\nprintf "%%s\\n" "%s NINE"\n' "${_r2_words% nine}" > "$WORK/r2/huge_wrong.sh"
chmod +x "$WORK/r2/huge_wrong.sh"
r2_huge() { once env -u TEST_UNDECLARED_OUTPUTS_DIR "$@" "$SH" "$TOOLS/rush02_check.sh" \
	--stderr-ignored "$R2_WHY" --bin "$WORK/r2/huge_wrong.sh" --dict "$WORK/r2/dict.txt" \
	--oracle "$WORK/r2/oracle_huge.sh" --show 2; }
r2_hugek() { r2_huge TEST_UNDECLARED_OUTPUTS_DIR="$WORK/r2/outh" TEST_TARGET=//mod:ex00_diff; }
want_broken_none "rush02: a 1000-digit number is not printed whole" \
	"$(printf '%s' "$_r2_num" | cut -c 1-400)" -- r2_hugek
want_out "rush02: ...its rendering says how much was left out" \
	"number:   $(printf '%s' "$_r2_num" | cut -c 1-300) ... (700 more bytes)" -- r2_hugek
want_out "rush02: ...and its outputs, each to its first 300 bytes" \
	' ... (2700 more bytes)' -- r2_hugek
want_out "rush02: ...where they part shown around that byte" \
	'expected, from byte 2988: ' -- r2_hugek
# The report is captured, then its status read, then its lines measured:
# piped straight into awk, a runner that refused after a few short lines
# returned awk's 0, and the arm passed on a report that never came.
r2_widest() {  # r2_widest CMD...: no line CMD prints is longer than a cut one
	_r2o=$("$@")
	_r2rc=$?
	[ "$_r2rc" -le 1 ] || { printf '%s\n' "$_r2o"; return "$_r2rc"; }
	_r2w=$(printf '%s\n' "$_r2o" | LC_ALL=C awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
	[ "$_r2w" -le 400 ] && return 0
	echo "a line of $_r2w bytes"
	return 1
}
want_green "rush02: ...and no line is longer than a cut one" -- r2_widest r2_hugek
want_broken "rush02: the width check does not pass a refusal" 'refused' -- \
	r2_widest sh -c 'echo refused >&2; exit 2'
want_out "rush02: ...a long replay line is kept as a file" \
	'replay:   sh replay-case-1.sh (a command line of 1024 bytes, kept in bazel-testlogs/mod/ex00_diff/test.outputs/' -- \
	r2_hugek
want_out "rush02: ...on the fixed dictionary too" \
	'replay:   sh replay-case-2.sh (a command line of 1021 bytes' -- r2_hugek
# The kept line runs, from where it is kept, that very number on that case's
# dictionary: a ./rush-02 there that prints its arguments.
r2_huge_back() {
	printf '#!/bin/sh\nprintf "%%s %%s\\n" "$1" "$2"\n' > "$WORK/r2/outh/rush-02"
	chmod +x "$WORK/r2/outh/rush-02"
	_r2b=$(cd "$WORK/r2/outh" && sh replay-case-1.sh)
	[ "$_r2b" = "case-1.dict $_r2_num" ] && return 0
	echo "it ran: $(printf '%s' "$_r2b" | cut -c 1-80)"
	return 1
}
want_green "rush02: ...and runs that very case" -- r2_huge_back
want_out "rush02: ...by hand, it is said not kept" \
	'bytes, too long to show; only a run under bazel test keeps it)' -- \
	r2_huge

# ONE KNOB FOR HOW MANY CASES A REPORT SHOWS (finding 167). This runner showed
# ten, hard-coded, while the knob the docs named -- DIFF_MAX_ROWS -- reached
# only the output table: a student who raised it as told saw the same ten. Now
# every differential report reads it (tools/runner_lib.sh, rl_rows), --show
# still wins, and every case it leaves out is kept whole in test.outputs.
r2_rows() {
	_rr_k=$1
	shift
	once env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/r2/rows$_rr_k$#" TEST_TARGET=//mod:ex00_diff \
		DIFF_MAX_ROWS="$_rr_k" "$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" \
		--bin "$WORK/r2/disagree.sh" --dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh" "$@"
}
want_out "rush02: DIFF_MAX_ROWS caps the cases it prints" \
	'10 more failing case(s) not shown here; all 30 are in' -- r2_rows 20
want_out "rush02: ...and says how to see more" \
	'Raise with --test_env=DIFF_MAX_ROWS=N' -- r2_rows 20
r2_count() {
	_rc_n=$(r2_rows 20 | grep -c '^  case [0-9]* of 30$')
	[ "$_rc_n" = 20 ] && return 0
	echo "printed $_rc_n cases"
	return 1
}
want_green "rush02: ...printing exactly that many" -- r2_count
want_green "rush02: ...and keeps all of them in test.outputs" -- \
	"$SH" -c '[ "$(grep -c "^  case [0-9]* of 30$" "$1")" = 30 ]' _ "$WORK/r2/rows200/differences.txt"
want_out "rush02: --show still wins over the knob" \
	'25 more failing case(s) not shown' -- r2_rows 20 --show 5

# THE WHOLE OUTPUT IS COMPARED, trailing newline included. It was read through
# $( ), which drops every trailing newline, so a converter that printed none,
# or two, agreed with the reference.
printf '#!/bin/sh\nprintf "n%%s" "$2"\n' > "$WORK/r2/nonl.sh"
printf '#!/bin/sh\nprintf "n%%s\\n\\n" "$2"\n' > "$WORK/r2/twonl.sh"
chmod +x "$WORK/r2/nonl.sh" "$WORK/r2/twonl.sh"
want_red "rush02: the right words with no final newline disagree" -- once r2_run nonl oracle_full
want_red "rush02: ...and with two of them" -- r2_run twonl oracle_full
want_out "rush02: ...shown as the \\n that is missing" 'expected: n0\n' -- once r2_run nonl oracle_full
# ...and the report says what that \n is, in words a reader can parse, and
# as the two characters its lines show (echo, under dash, would print a
# line break).
want_out "rush02: ...and says the reference prints it" \
	'after the words: the \n at the end' -- once r2_run nonl oracle_full
# ...broken where no line of it reads as a case's field: its second line
# began "expected: line.", the label a case's expected output is shown under.
want_broken_none "rush02: ...in no line that starts as a case's field" \
	'  expected: line.' -- once r2_run nonl oracle_full
# AN OUTPUT THAT ENDS IN A SPACE (V71). rl_vis shows a space as a space, so
# "n0 " at the end of a got: line read exactly as "n0". Each output's end is
# marked with $, as rust_diff's and BSQ's lines are, and the report says so
# once -- in the plain replay and under --settled, whose got: line this
# converter's words fail too.
printf '#!/bin/sh\nprintf "n%%s " "$2"\n' > "$WORK/r2/endspace.sh"
chmod +x "$WORK/r2/endspace.sh"
r2_end() { "$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/endspace.sh" \
	--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh" "$@"; }
want_out "rush02: an output ending in a space shows the space" 'got:      n0 $' -- once r2_end
want_out "rush02 --settled: ...there too" 'got:      n0 $' -- r2_end --settled
r2_end_legend() {  # r2_end_legend [--settled]: the mark is named once
	_r2e_n=$(r2_end "$@" | grep -cF 'In the lines above, $ is where an output ended')
	[ "$_r2e_n" = 1 ] && return 0
	echo "named $_r2e_n times"
	return 1
}
want_green "rush02: ...and the report says once what the mark is" -- r2_end_legend
want_green "rush02 --settled: ...as its report does" -- r2_end_legend --settled
# ...and gives $ no other meaning: a line above it once said \`| cat -e\`
# marks the newline with $, one line before $ was where an output ended.
want_broken_none "rush02: ...and gives \$ no other meaning" 'marks it' -- once r2_end

# STANDARD ERROR IS SHOWN, NEVER GRADED (finding 156). A debug line on stderr
# was discarded here, so it was green and in no log at all, while anyone who
# runs the program sees it above the answer.
printf '#!/bin/sh\nprintf "n%%s\\n" "$2"\necho "debug: got $2" >&2\n' > "$WORK/r2/noisy.sh"
chmod +x "$WORK/r2/noisy.sh"
want_green "rush02: a converter that also writes to stderr still agrees" -- \
	once r2_run noisy oracle_full
want_out "rush02: ...and the report says it did" \
	'30 case(s) also wrote to standard error (not graded' -- once r2_run noisy oracle_full
want_out "rush02: ...showing the first" '| debug: got 0' -- once r2_run noisy oracle_full
want_broken_none "rush02: ...and a quiet one says nothing of it" \
	'standard error' -- once r2_run agree oracle_full
# THE CORPUS UNDER A SANITIZER (finding 113). Every corpus ran on the plain
# build, where a heap overflow that happens to print the right words passes.
# This one copies the number into a 2-byte block: the plain build agrees on
# all 30 cases, and the ASan build overflows from the first two-digit number.
cat > "$WORK/r2/ovf.c" <<'R2_OVF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int ac, char **av)
{
	size_t	n;
	char	*b;

	if (ac != 3)
		return (1);
	n = strlen(av[2]);
	b = malloc(2);
	if (!b)
		return (1);
	memcpy(b, av[2], n + 1);
	printf("n%s\n", av[2]);
	fflush(stdout);
	free(b);
	return (0);
}
R2_OVF
cat > "$WORK/r2/clean.c" <<'R2_CLEAN'
#include <stdio.h>
int main(int ac, char **av)
{
	if (ac != 3)
		return (1);
	printf("n%s\n", av[2]);
	return (0);
}
R2_CLEAN
toy_cc "$WORK/r2/ovf_plain" -w "$WORK/r2/ovf.c"
want_green "rush02: the overflow prints the right words on the plain build" -- \
	"$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/ovf_plain" --dict "$WORK/r2/dict.txt" \
		--oracle "$WORK/r2/oracle_full.sh"
# On a box that can build a sanitized program at all (selftest.sh, THE
# SANITIZER PROBE, which refuses NO_SKIP=1 where it cannot); a toy that does
# not build there is toy_cc's FAIL.
if [ "$SAN" != 1 ]; then
	st_skipped "rush02 --sanitized: (sanitizer build unavailable)" skipped
elif toy_cc "$WORK/r2/ovf_asan" -w -g -fsanitize=address,undefined -fno-sanitize-recover=all -fuse-ld=bfd \
		"$WORK/r2/ovf.c" &&
	toy_cc "$WORK/r2/clean_asan" -w -g -fsanitize=address,undefined -fno-sanitize-recover=all -fuse-ld=bfd \
		"$WORK/r2/clean.c"; then
	r2_san() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/r2/san" TEST_TARGET=//mod:ex00_diff_asan \
		"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/$1" --dict "$WORK/r2/dict.txt" \
		--oracle "$WORK/r2/oracle_full.sh" --sanitized; }
	want_red "rush02 --sanitized: ...and the ASan build is red" -- once r2_san ovf_asan
	want_out "rush02 --sanitized: ...naming the first case it hit" \
		'case 11 of 30  [sanitizer]' -- once r2_san ovf_asan
	want_out "rush02 --sanitized: ...with the sanitizer's own report" \
		'heap-buffer-overflow' -- once r2_san ovf_asan
	want_out "rush02 --sanitized: ...and how to run it again" \
		'replay:   ./rush-02' -- once r2_san ovf_asan
	want_green "rush02 --sanitized: a clean program passes" -- once r2_san clean_asan
	want_out "rush02 --sanitized: ...saying every case ran and what was judged" \
		'all 30 case(s) of the corpus ran under ASan/UBSan' -- once r2_san clean_asan
	want_broken_none "rush02 --sanitized: ...and never that it agrees with the reference" \
		'agree' -- once r2_san clean_asan
fi
# A program that prints the wrong words but is memory-clean passes: under a
# memory checker only memory and the ending are judged.
printf '#!/bin/sh\nprintf "wrong\\n"\n' > "$WORK/r2/wrong_clean.sh"
chmod +x "$WORK/r2/wrong_clean.sh"
want_green "rush02 --sanitized: wrong words are not this arm's finding" -- \
	once "$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/wrong_clean.sh" --dict "$WORK/r2/dict.txt" \
		--oracle "$WORK/r2/oracle_full.sh" --sanitized
# ...and its verdict says the number, an argument, was unwatched (finding
# 071's class; it said nothing before the wave 6 review).
want_out "rush02 --sanitized: ...saying its argument was unwatched" \
	'Reads inside the argument strings, or past argv'"'"'s end, are invisible' -- \
	once "$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/wrong_clean.sh" --dict "$WORK/r2/dict.txt" \
		--oracle "$WORK/r2/oracle_full.sh" --sanitized
# ...but a signal is, whatever it printed.
want_red "rush02 --sanitized: a crash is" -- \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/crasher.sh" --dict "$WORK/r2/dict.txt" \
		--oracle "$WORK/r2/oracle_full.sh" --sanitized
# A report that names a generated dictionary names the scratch file the
# program was given; the case keeps it as case-N.dict, which the report
# shows -- where it was kept. Run by hand there is nowhere to keep it, and
# the report named a file that exists nowhere. A corpus of three fields,
# each line's own dictionary, and a fake that reports on the number 14.
{
	_i=0
	while [ "$_i" -lt 30 ]; do printf '0: zero\\n\t%s\tn%s\n' "$_i" "$_i"; _i=$((_i + 1)); done
} | st_oracle "$WORK/r2/oracle_gen.sh"
printf '#!/bin/sh\n[ "$2" != 14 ] || { echo "==1==ERROR: AddressSanitizer: heap-buffer-overflow while reading $1" >&2; kill -ABRT $$; }\nprintf "n%%s\\n" "$2"\n' \
	> "$WORK/r2/sanpath.sh"
chmod +x "$WORK/r2/sanpath.sh"
r2_sank() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/r2/outs" TEST_TARGET=//mod:ex00_diff_asan \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/sanpath.sh" --dict "$WORK/r2/dict.txt" \
	--oracle "$WORK/r2/oracle_gen.sh" --sanitized; }
r2_sanh() { env -u TEST_UNDECLARED_OUTPUTS_DIR "$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/sanpath.sh" \
	--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_gen.sh" --sanitized; }
want_out "rush02 --sanitized: a report naming the dictionary shows the kept name" \
	'heap-buffer-overflow while reading case-15.dict' -- once r2_sank
want_out "rush02 --sanitized: ...and says it did" \
	'shown by the name it is kept under: case-15.dict)' -- once r2_sank
want_out "rush02 --sanitized: by hand the dictionary is said not kept" \
	'generated for this case (a run under bazel test keeps it)' -- once r2_sanh
want_broken_none "rush02 --sanitized: ...and the report names no kept one" 'case-15.dict' -- once r2_sanh
# ...and so a report that names the fixed dictionary: the case keeps it
# beside the generated ones and replays it by that name, and its report
# named the path the runner was given, which no student has. Run by hand,
# where it is not kept, the report names that path, the one the replay
# line names.
r2_sanf() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/r2/outsf" TEST_TARGET=//mod:ex00_diff_asan \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/sanpath.sh" --dict "$WORK/r2/dict.txt" \
	--oracle "$WORK/r2/oracle_full.sh" --sanitized; }
r2_sanfh() { env -u TEST_UNDECLARED_OUTPUTS_DIR "$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/sanpath.sh" \
	--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh" --sanitized; }
want_out "rush02 --sanitized: a report naming the fixed dictionary shows the kept name" \
	'heap-buffer-overflow while reading dict.txt' -- once r2_sanf
want_out "rush02 --sanitized: ...and says it did" \
	'shown by the name it is kept under: dict.txt)' -- once r2_sanf
want_out "rush02 --sanitized: by hand it names the dictionary's own path" \
	"heap-buffer-overflow while reading $WORK/r2/dict.txt" -- once r2_sanfh
want_broken_none "rush02 --sanitized: ...and no kept name" 'name it is kept under' -- once r2_sanfh
# The checker's options, refused when they cannot mean one thing
# (tools/runner_lib.sh, rl_mem_opt and rl_mem_ready): every corpus runner
# takes them through the same two functions.
want_broken "corpus memory: --sanitized and --valgrind are two targets" 'two targets, not one' -- \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/agree.sh" --dict "$WORK/r2/dict.txt" \
		--oracle "$WORK/r2/oracle_full.sh" --sanitized --valgrind /nonexistent \
		--valgrind-tools /nonexistent
want_broken "corpus memory: --sample goes with --valgrind" 'go with --valgrind' -- \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/agree.sh" --dict "$WORK/r2/dict.txt" \
		--oracle "$WORK/r2/oracle_full.sh" --sanitized --sample 3
want_broken "corpus memory: --rule, the subject's sentence, goes with --valgrind too" \
	'--rule go with --valgrind' -- \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/agree.sh" --dict "$WORK/r2/dict.txt" \
		--oracle "$WORK/r2/oracle_full.sh" --sanitized --rule "$WORK/r2/dict.txt"
want_broken "corpus memory: --valgrind needs its tool directory" 'needs --valgrind-tools' -- \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/agree.sh" --dict "$WORK/r2/dict.txt" \
		--oracle "$WORK/r2/oracle_full.sh" --valgrind /nonexistent

# 0 cases must never read as agreement (the header's false green).
want_broken "rush02: an EMPTY corpus is a harness error, not 0/0" \
	'fewer than the 20 this layer needs' -- \
	"$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/agree.sh" \
		--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_empty.sh"
# An oracle that fails outright checked nothing either, and said 1, a wrong
# program, where the empty corpus above says 2.
printf '#!/bin/sh\necho "the reference fell over" >&2\nexit 3\n' > "$WORK/r2/oracle_fails.sh"
chmod +x "$WORK/r2/oracle_fails.sh"
want_broken "rush02: an oracle that fails is a harness error, not a red" \
	'the oracle produced no corpus' -- \
	"$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/agree.sh" \
		--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_fails.sh"
# ...and is shown saying why: its stderr is not discarded.
printf '#!/bin/sh\necho oracle-said-this >&2\nexit 1\n' > "$WORK/r2/oracle_says.sh"
chmod +x "$WORK/r2/oracle_says.sh"
want_broken "rush02: ...and is shown saying why" 'oracle-said-this' -- \
	"$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/agree.sh" \
		--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_says.sh"

# A converter that never built is not 200 rows that "differ the same way".
cp "$STANDIN_BIN" "$WORK/r2/built_nothing.sh"
want_red   "rush02: a stand-in is red"                         -- once r2_run built_nothing oracle_full
want_out   "rush02: ...says the code did not build" "$STANDIN_SAYS" -- once r2_run built_nothing oracle_full
want_broken_none "rush02: ...and never calls it a convention" 'convention' -- \
	once r2_run built_nothing oracle_full
# Under a memory checker the same stand-in is a SKIP, never memory-clean
# and never a red that repeats the output layer's (tools/runner_lib.sh,
# RL_STANDIN); NO_SKIP=1 turns it red. These are the arms that were red at
# strict and robust on Rush 02's unwritten stub.
want_green "rush02 --sanitized: a stand-in is a SKIP" -- \
	once env -u NO_SKIP "$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/built_nothing.sh" \
		--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh" --sanitized
want_out   "rush02 --sanitized: ...saying it was never built" 'was never built' -- \
	once env -u NO_SKIP "$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/built_nothing.sh" \
		--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh" --sanitized
want_broken_none "rush02 --sanitized: ...and never that it ran clean" 'PASS' -- \
	once env -u NO_SKIP "$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/built_nothing.sh" \
		--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh" --sanitized
want_red   "rush02 --sanitized: ...and NO_SKIP=1 turns it red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/built_nothing.sh" \
		--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh" --sanitized
want_red   "rush02: ...while the plain replay stays red without it" -- \
	env -u NO_SKIP "$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/built_nothing.sh" \
		--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/oracle_full.sh"

# --settled (finding 160): the corpus gates at strict on what every reading
# agrees on, and only that. The toy corpus: numbers below 100 the reference
# spells "one two" with the dictionary below; 100 and up, it says Dict Error.
# None of them is a key of the dictionary, whose spelling every reading
# agrees on (the shapes, below). Each converter breaks one rule, or takes a
# reading the subject leaves open.
printf '1: one\n2 :  two\n3: thr ee\n' > "$WORK/r2/settled.dict"
{
	_i=4
	while [ "$_i" -lt 29 ]; do
		printf '%s\tone two\n1%s0\tDict Error\n' "$_i" "$_i"
		_i=$((_i + 1))
	done
} | st_oracle "$WORK/r2/oracle_settled.sh"
r2_conv() { # NAME WORDS-OUTPUT DICTERR-OUTPUT: a converter printing those
	printf '#!/bin/sh\nif [ "$2" -lt 100 ]; then printf "%s"; else printf "%s"; fi\n' "$2" "$3" \
		> "$WORK/r2/$1.sh"
	chmod +x "$WORK/r2/$1.sh"
}
r2_conv s_agree 'one two\n' 'Dict Error\n'
r2_conv s_and 'one and two\n' 'Dict Error\n'
r2_conv s_bonus 'one-two, thr ee\n' 'one thr ee two\n'
r2_conv s_error 'one two\n' 'Error\n'
r2_conv s_dicterr 'Dict Error\n' 'Dict Error\n'
r2_conv s_english 'one twenty\n' 'Dict Error\n'
r2_conv s_silent '' 'Dict Error\n'
r2_conv s_nonl 'one two' 'Dict Error\n'
r2_settled() { "$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/$1.sh" \
	--dict "$WORK/r2/settled.dict" --oracle "$WORK/r2/oracle_settled.sh" --settled; }
want_green "rush02 --settled: the reference's answers pass" -- r2_settled s_agree
want_red   "rush02: \"and\" fails the whole comparison" -- r2_run s_and oracle_settled
want_green "rush02 --settled: ...but passes here (open)" -- once r2_settled s_and
want_out   "rush02 --settled: ...and is shown as what it is" \
	"passes:   another composition of the number, which this target does not judge" -- once r2_settled s_and
want_out   "rush02 --settled: ...and counted" '25 differ from the reference' -- once r2_settled s_and
# The reference's words with no newline after them: they pass here, which
# judges the words, and were shown and counted as "another composition of
# the number", which they are not.
want_green "rush02 --settled: the same words with no newline pass" -- once r2_settled s_nonl
want_out   "rush02 --settled: ...shown as only the newline differing" \
	"passes:   the same words; only the newline(s) after them differ, which this target does not judge" -- \
	once r2_settled s_nonl
want_broken_none "rush02 --settled: ...never as another composition" 'another composition' -- \
	once r2_settled s_nonl
want_out   "rush02 --settled: ...and counted apart" \
	'0 differ from the reference' -- once r2_settled s_nonl
want_out   "rush02 --settled: ...as what they are" \
	'25 only in the newline(s) after the same words' -- once r2_settled s_nonl
want_green "rush02 --settled: -, \",\", a spaced value, combined scales" -- \
	r2_settled s_bonus
want_red   "rush02 --settled: Error for a valid number fails" -- once r2_settled s_error
want_out   "rush02 --settled: ...and says why" 'Error is for a number that is not a valid' -- once r2_settled s_error
# Its RESULT lists what fails: a run cut at its time limit is not among
# them (counted apart, never judged), so the list names what is.
want_out   "rush02 --settled: ...under a list of what fails" \
	'nothing at all, a crash, or output without end' -- once r2_settled s_error
# The marks its shown lines hold are named, as the plain replay names them:
# --settled printed no byte legend, on a fail or on an OK that showed a
# composition.
want_out   "rush02 --settled: ...whose marks are named" '(byte for byte: \n a newline' -- \
	once r2_settled s_error
want_out   "rush02 --settled: ...as a composition's are" '(byte for byte: \n a newline' -- \
	once r2_settled s_and
want_red   "rush02 --settled: Dict Error where it spells, fails" -- once r2_settled s_dicterr
want_out   "rush02 --settled: ...and says why" 'has every key of the reference dictionary' -- once r2_settled s_dicterr
want_red   "rush02 --settled: words not the dictionary's fail" -- once r2_settled s_english
want_out   "rush02 --settled: ...from the byte they stop" \
	"from byte 5 on, none of it is this dictionary's values" -- once r2_settled s_english
want_red   "rush02 --settled: printing nothing fails" -- r2_settled s_silent
want_red   "rush02 --settled: a signal death still fails" -- r2_settled crasher
# THE SHAPES EVERY READING SPELLS ALIKE, as the named cases at basic hold them:
# a number below 100 with a key of its own is that key's value alone, and a
# round <group> <scale> is the group's value and the scale's. They passed as
# "a reading the subject leaves open" while ex00_teen_output failed them at
# basic (the mutation run of 2026-10-03). A toy dictionary and a corpus of
# those shapes only; each converter spells one shape another way.
printf '3: thr ee\n10: ten\n13 :  thir teen\n70: seven ty\n1000: k\n1000000: mega\n' \
	> "$WORK/r2/shapes.dict"
{
	_i=0
	while [ "$_i" -lt 5 ]; do
		printf '13\tthir teen\n3000000\tthr ee mega\n70000\tseven ty k\n13000\tthir teen k\n'
		_i=$((_i + 1))
	done
} | st_oracle "$WORK/r2/oracle_shapes.sh"
r2_shape() { # NAME CASE-BODY: a converter, by the number it is given
	printf '#!/bin/sh\ncase "$2" in\n%s\nesac\n' "$2" > "$WORK/r2/$1.sh"
	chmod +x "$WORK/r2/$1.sh"
}
_r2_ok='13) echo "thir teen" ;; 3000000) echo "thr ee mega" ;; 70000) echo "seven ty k" ;; 13000) echo "thir teen k" ;;'
r2_shape sh_agree "$_r2_ok"
r2_shape sh_teen "13) echo \"ten thr ee\" ;; ${_r2_ok#*;; }"
r2_shape sh_round "3000000) echo \"thr ee mega k\" ;; $_r2_ok"
r2_shape sh_bonus "13000) echo \"thir teen-k\" ;; $_r2_ok"
r2_shapes() { "$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/$1.sh" \
	--dict "$WORK/r2/shapes.dict" --oracle "$WORK/r2/oracle_shapes.sh" --settled; }
want_green "rush02 --settled: the shapes, spelled by their keys, pass" -- r2_shapes sh_agree
want_red   "rush02 --settled: a teen spelled as two keys fails" -- once r2_shapes sh_teen
want_out   "rush02 --settled: ...and says what every reading spells" \
	'every reading spells this number with its own keys'"'"' values, and only those: thir teen' -- \
	once r2_shapes sh_teen
# ...cut where it is shown, as the expected: and got: lines above it are
# (SHOW_W): a dictionary's value can be as long as the outputs it spells.
r2_shapes_cut() { env RL_EXCERPT_WIDTH=5 "$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" \
	--bin "$WORK/r2/$1.sh" --dict "$WORK/r2/shapes.dict" --oracle "$WORK/r2/oracle_shapes.sh" --settled; }
want_out   "rush02 --settled: ...cut to the width of the lines it sits under" \
	'and only those: thir  ... (4 more bytes)' -- r2_shapes_cut sh_teen
want_red   "rush02 --settled: a round number with a scale too many fails" -- r2_shapes sh_round
want_red   "rush02 --settled: ...and so does another separator in a shape" -- r2_shapes sh_bonus
# A KEY A DICTIONARY ADDS IS NO SHAPE (the wave 6 review). The subject lets a
# dictionary hold keys the reference dictionary lacks, and the reference
# composes without them: 45 beside 40 and 5 is "forty five" there, and the
# value of 45 under the reading that uses the key -- a question the subject
# leaves open, which the shape rule settled the other way, failing the
# reference's own composition. The shapes
# hold only the keys --dict, the reference dictionary, holds; 40 is one, and
# a generated dictionary's 40 spelled with other values still fails.
printf '5: five\n40: forty\n' > "$WORK/r2/added.dict"
{
	_i=0
	while [ "$_i" -lt 25 ]; do
		printf '5: five\\n40: forty\\n45: xyz\t45\tforty five\n'
		printf '5: five\\n40: forty\\n45: xyz\t40\tforty\n'
		_i=$((_i + 1))
	done
} | st_oracle "$WORK/r2/oracle_added.sh"
r2_shape ad_hyphen '45) echo "forty-five" ;; 40) echo "forty" ;;'
r2_shape ad_forty '45) echo "forty five" ;; 40) echo "five forty" ;;'
r2_added() { "$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/$1.sh" \
	--dict "$WORK/r2/added.dict" --oracle "$WORK/r2/oracle_added.sh" --settled; }
want_green "rush02 --settled: a key the dictionary adds settles nothing" -- once r2_added ad_hyphen
want_broken_none "rush02 --settled: ...and is never called the spelling" 'only those: xyz' -- \
	once r2_added ad_hyphen
want_red   "rush02 --settled: ...while a reference key's shape still holds" -- once r2_added ad_forty
want_out   "rush02 --settled: ...and says what every reading spells" \
	'and only those: forty' -- once r2_added ad_forty
# The call's stderr choice holds under --settled too: --stderr-empty fails a
# run that wrote there, whatever its words, and says so; --stderr-ignored
# shows it and passes.
printf '#!/bin/sh\nif [ "$2" -lt 100 ]; then echo "one two"; else echo "Dict Error"; fi\necho "a note" >&2\n' \
	> "$WORK/r2/s_chatty.sh"
chmod +x "$WORK/r2/s_chatty.sh"
r2_settled_quiet() { "$SH" "$TOOLS/rush02_check.sh" --stderr-empty --bin "$WORK/r2/$1.sh" \
	--dict "$WORK/r2/settled.dict" --oracle "$WORK/r2/oracle_settled.sh" --settled; }
want_green "rush02 --settled: a message on stderr is not judged unless asked" -- r2_settled s_chatty
want_red   "rush02 --settled: --stderr-empty fails it" -- once r2_settled_quiet s_chatty
want_out   "rush02 --settled: ...and says why" 'it wrote to standard error, which this check holds empty' -- \
	once r2_settled_quiet s_chatty
want_green "rush02 --settled: --stderr-empty passes a quiet converter" -- r2_settled_quiet s_agree
# A generated dictionary (three fields) is the one its words are read from.
# The number is no key of it, whose spelling every reading would agree on.
{
	_i=0
	while [ "$_i" -lt 25 ]; do printf '5: cinq\\n6:six\t56\tcinq six\n'; _i=$((_i + 1)); done
} | st_oracle "$WORK/r2/oracle_gen.sh"
r2_conv s_gen_own 'six cinq\n' ''
r2_conv s_gen_english 'five\n' ''
want_green "rush02 --settled: a generated dict's values pass" -- \
	"$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/s_gen_own.sh" --dict "$WORK/r2/settled.dict" \
	--oracle "$WORK/r2/oracle_gen.sh" --settled
want_red   "rush02 --settled: ...and words from elsewhere do not" -- \
	"$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/s_gen_english.sh" --dict "$WORK/r2/settled.dict" \
	--oracle "$WORK/r2/oracle_gen.sh" --settled
# The gate (runner_lib.sh's rl_gate), as every diff layer has one: while the
# subject's own example (`BIN DICT 42`) is red, a judging run says SKIP and
# passes; NO_SKIP=1 forces it open; a differ that cannot judge never
# silences it. s_english fails the example; s_gate_ok passes it, then
# answers Error where the reference says Dict Error.
printf 'forty two\n' > "$WORK/r2/forty_two.txt"
printf '#!/bin/sh\nexit 2\n' > "$WORK/r2/differ_broken.sh"
cat > "$WORK/r2/s_gate_ok.sh" <<'R2_GATE'
#!/bin/sh
if [ "$2" = 42 ]; then echo "forty two"; elif [ "$2" -lt 100 ]; then echo "one two"; else echo Error; fi
R2_GATE
chmod +x "$WORK/r2/differ_broken.sh" "$WORK/r2/s_gate_ok.sh"
r2_gated() { # CONVERTER DIFFER [NO_SKIP]
	env NO_SKIP="${3:-0}" "$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/$1.sh" \
		--dict "$WORK/r2/settled.dict" --oracle "$WORK/r2/oracle_settled.sh" --settled \
		--gate-differ "$2" --gate-bin "$WORK/r2/$1.sh" \
		--gate-expected "$WORK/r2/forty_two.txt" --gate-number 42
}
want_green "rush02 --settled: waits while the example is red" -- \
	once r2_gated s_english "$TOOLS/diff_output.sh"
want_out   "rush02 --settled: ...and says so" "SKIP — this exercise's own output fixture" -- \
	once r2_gated s_english "$TOOLS/diff_output.sh"
want_out   "rush02 --settled: ...naming the test it waits for" 'SKIP — ex00_dict_arg_42_output, this exercise' -- \
	env NO_SKIP=0 "$SH" "$TOOLS/rush02_check.sh" --stderr-ignored "$R2_WHY" --bin "$WORK/r2/s_english.sh" \
		--dict "$WORK/r2/settled.dict" --oracle "$WORK/r2/oracle_settled.sh" --settled \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/r2/s_english.sh" \
		--gate-expected "$WORK/r2/forty_two.txt" --gate-number 42 --gate-label ex00_dict_arg_42_output
want_red   "rush02 --settled: ...which NO_SKIP=1 forces open" -- \
	r2_gated s_english "$TOOLS/diff_output.sh" 1
want_red   "rush02 --settled: ...and runs once the example passes" -- \
	r2_gated s_gate_ok "$TOOLS/diff_output.sh"
want_red   "rush02 --settled: a gate that cannot judge never silences it" -- \
	once r2_gated s_english "$WORK/r2/differ_broken.sh"
want_out   "rush02 --settled: ...and says so" 'the output gate could not be evaluated' -- \
	once r2_gated s_english "$WORK/r2/differ_broken.sh"
# The command a SKIP shows to force it open names this test, never the whole
# repo (review of WP-83): TEST_TARGET under Bazel, a module's tests by hand.
r2_gated_as() { # TARGET CONVERTER DIFFER -- r2_gated as Bazel's test TARGET, or by hand ("")
	(
		if [ -n "$1" ]; then TEST_TARGET=$1; export TEST_TARGET; else unset TEST_TARGET; fi
		shift
		r2_gated "$@"
	)
}
want_out   "rush02 --settled: ...naming this test to force it open" \
	'(bazel test //c-piscine/c-piscine-c-88:ex00_toy --test_env=NO_SKIP=1 runs it anyway.)' -- \
	r2_gated_as //c-piscine/c-piscine-c-88:ex00_toy s_english "$TOOLS/diff_output.sh"
want_out   "rush02 --settled: ...and run by hand, a module's tests" \
	'(bazel test //<course>/<project>/... --test_env=NO_SKIP=1 runs it anyway.)' -- \
	r2_gated_as "" s_english "$TOOLS/diff_output.sh"

