# ---------------------------------------------------------------- diff_output
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# exp.txt is first_red's too: plain code, made in every shard (st_mine).
printf 'hello\n' > "$WORK/exp.txt"
printf '#include <stdio.h>\nint main(void){printf("hello\\n");return 0;}\n' > "$WORK/ok.c"
toy_cc "$WORK/ok" "$WORK/ok.c"
printf '#include <stdio.h>\nint main(void){printf("wrong\\n");return 0;}\n' > "$WORK/bad.c"
toy_cc "$WORK/bad" "$WORK/bad.c"
# Correct output, then a crash: the exact false green diff_output.sh had.
printf '#include <stdio.h>\nint main(void){printf("hello\\n");fflush(stdout);*(volatile int*)0=1;return 0;}\n' > "$WORK/crash.c"
toy_cc "$WORK/crash" "$WORK/crash.c"
# Prints forever: must be stopped by the ulimit budget, not run for the whole timeout.
printf '#include <stdio.h>\nint main(void){for(;;)printf("spam\\n");}\n' > "$WORK/runaway.c"
toy_cc "$WORK/runaway" "$WORK/runaway.c"

want_green "diff_output: correct output passes" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/ok" --expected "$WORK/exp.txt"
want_red   "diff_output: wrong output fails" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --expected "$WORK/exp.txt"
want_red   "diff_output: right output THEN crash fails" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --expected "$WORK/exp.txt"
want_red   "diff_output: runaway printer is stopped" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/runaway" --expected "$WORK/exp.txt"
# ... and stopped by the `ulimit -f` BUDGET rather than by the 30s timeout. Exit
# 1 alone cannot tell those apart, so the arm above is satisfied by either --
# and the budget is the half its own comment says it exists for: a loop that
# prints forever fills the test tmpdir at page-cache speed for the whole
# timeout, which is the failure the cap prevents and the timeout does not.
want_out "diff_output: ... by the output budget, not by the timeout" \
	"RUNAWAY OUTPUT" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/runaway" --expected "$WORK/exp.txt"

# ---- --sanitize: the address the harness published (finding 048) ----------
#
# A hex dump's address column moves with ASLR, so the fixture holds offsets.
# The harness's test program publishes each address it passes ("@addr" and 16
# hex digits, a line of its own) before the dump; the runner takes the line
# out and holds the k-th row of that dump to the address plus 16k. Without it
# the value was never compared, and a 32-bit truncation passed. Scripts stand
# in for the program here: the address is only text to this runner.
printf '0000000000000000: 4142 AB\n0000000000000010: 4344 CD\ntail\n' > "$WORK/san_exp.txt"
_san_sh() {  # _san_sh NAME LINE... -- a program printing those lines, as they are
	_n=$1; shift
	printf '#!/bin/sh\n' > "$WORK/$_n"
	for _l in "$@"; do printf "printf '%%s' '%s'\n" "$_l" >> "$WORK/$_n"; done
	chmod +x "$WORK/$_n"
}
_nl='
'
_san_sh san_ok "@addr 00007ffc12345670$_nl" "00007ffc12345670: 4142 AB$_nl" \
	"00007ffc12345680: 4344 CD$_nl" "tail$_nl"
_san_sh san_trunc "@addr 00007ffc12345670$_nl" "0000000012345670: 4142 AB$_nl" \
	"0000000012345680: 4344 CD$_nl" "tail$_nl"
_san_sh san_same "@addr 00007ffc12345670$_nl" "00007ffc12345670: 4142 AB$_nl" \
	"00007ffc12345670: 4344 CD$_nl" "tail$_nl"
_san_sh san_upper "@addr 00007ffc1234567a$_nl" "00007FFC1234567A: 4142 AB$_nl" \
	"00007FFC1234568A: 4344 CD$_nl" "tail$_nl"
# A row that did not end its line before the next marker: the marker goes, and
# the row runs into what follows it, as the program wrote it -- never given
# the newline it lacked.
_san_sh san_nonl "@addr 00007ffc12345670$_nl" "00007ffc12345670: 4142 AB$_nl" \
	"00007ffc12345680: 4344 CD" "@addr 00007ffc12345690$_nl" "tail$_nl"
# No marker at all: the old rule, the +16 step from the block's first row.
_san_sh san_unpinned "7fff000000000010: 4142 AB$_nl" "7fff000000000020: 4344 CD$_nl" "tail$_nl"
want_green "diff_output: sanitize passes the published address" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/san_ok" --expected "$WORK/san_exp.txt" --sanitize
want_broken_none "diff_output: ...and the marker is in neither column" '@addr' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/san_trunc" --expected "$WORK/san_exp.txt" --sanitize
want_red   "diff_output: sanitize fails an address cut to 32 bits" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/san_trunc" --expected "$WORK/san_exp.txt" --sanitize
want_out   "diff_output: ...keeping what it printed, marked" \
	'0000000012345670(not the address the test passed)' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/san_trunc" --expected "$WORK/san_exp.txt" --sanitize
want_red   "diff_output: sanitize fails one address on every row" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/san_same" --expected "$WORK/san_exp.txt" --sanitize
want_red   "diff_output: sanitize fails the right address in uppercase" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/san_upper" --expected "$WORK/san_exp.txt" --sanitize
want_red   "diff_output: a row missing its newline gets none from a marker" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/san_nonl" --expected "$WORK/san_exp.txt" --sanitize
want_out   "diff_output: ...and says the address was checked" \
	'every row'"'"'s address is compared' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/san_ok" --expected "$WORK/san_exp.txt" --sanitize
want_green "diff_output: sanitize with no marker compares the +16 step" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/san_unpinned" --expected "$WORK/san_exp.txt" --sanitize
want_out   "diff_output: ...and says the address itself was not" \
	'which this test does not publish' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/san_unpinned" --expected "$WORK/san_exp.txt" --sanitize
# Text of the program's before a marker, and nothing after it: that text
# ended the output, with no newline of its own, and keeps none (the awk's END
# rule). Dropped, the dump's last word went missing; given a newline, a
# program that never wrote one matched a fixture that has it.
_san_sh san_carry "@addr 00007ffc12345670$_nl" "00007ffc12345670: 4142 AB$_nl" \
	"00007ffc12345680: 4344 CD$_nl" "tail" "@addr 00007ffc12345690$_nl"
printf '0000000000000000: 4142 AB\n0000000000000010: 4344 CD\ntail' > "$WORK/san_carry_exp.txt"
want_green "diff_output: text before a last marker ends the output, as written" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/san_carry" --expected "$WORK/san_carry_exp.txt" --sanitize
want_red   "diff_output: ...and is given no newline it did not write" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/san_carry" --expected "$WORK/san_exp.txt" --sanitize

# THE OTHER STREAM ON A PASS (finding 156). A case compares one stream, and
# the other was shown only under a failure: a debug line on stderr, printed on
# every run, was green and in no log. It is never graded, and now it is said.
printf '#include <stdio.h>\nint main(void){printf("hello\\n");fprintf(stderr,"debug: made it here\\n");return 0;}\n' \
	> "$WORK/noisy.c"
toy_cc "$WORK/noisy" "$WORK/noisy.c"
want_green "diff_output: a pass that also wrote to stderr is a pass" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/noisy" --expected "$WORK/exp.txt"
want_out   "diff_output: ...and says so, with what it wrote" \
	'note: also written to stderr (not compared by this case)' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/noisy" --expected "$WORK/exp.txt"
want_out   "diff_output: ...showing it" '| debug: made it here' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/noisy" --expected "$WORK/exp.txt"
want_broken_none "diff_output: ...and a quiet pass says nothing of it" 'also written to' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/ok" --expected "$WORK/exp.txt"
# The rows DIFF_MAX_ROWS leaves out of a table are kept whole in test.outputs.
{ _i=0; while [ "$_i" -lt 30 ]; do printf 'row %s\n' "$_i"; _i=$((_i + 1)); done; } > "$WORK/rows30.txt"
want_out   "diff_output: rows the cap leaves out are kept" 'every row of the table: bazel-testlogs/mod/ex00_output/test.outputs/output-table.txt' -- \
	env DIFF_MAX_ROWS=3 TEST_UNDECLARED_OUTPUTS_DIR="$WORK/rowsout" TEST_TARGET=//mod:ex00_output \
		"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/ok" --expected "$WORK/rows30.txt"
want_green "diff_output: ...every one of them" -- \
	grep -q 'row 29' "$WORK/rowsout/output-table.txt"

# ---- a case's kind: any_of (--expected-alt) and survive (--survive) ---------
#
# An open case is bounded, not untested (docs/design.md): one of the outputs
# its readings allow, or only that the run ends by itself. Either passes what
# a reading allows and nothing else -- and neither is a way to stop checking.
printf 'bye\n' > "$WORK/alt.txt"
printf 'int main(void){for(;;);}\n' > "$WORK/hang.c"
toy_cc "$WORK/hang" "$WORK/hang.c"
want_green "diff_output: any_of passes on its second output" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/ok" --expected "$WORK/alt.txt" \
		--expected-alt "$WORK/exp.txt"
want_out   "diff_output: ...and says which one it is" "Yours is exp.txt" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/ok" --expected "$WORK/alt.txt" \
		--expected-alt "$WORK/exp.txt"
want_red   "diff_output: any_of fails on an output it does not take" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --expected "$WORK/exp.txt" \
		--expected-alt "$WORK/alt.txt"
want_out   "diff_output: ...naming every output it takes" "* alt.txt" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --expected "$WORK/exp.txt" \
		--expected-alt "$WORK/alt.txt"
want_green "diff_output: survive passes whatever is printed" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --survive
want_red   "diff_output: survive fails a crash" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive
# How it ended is read from tools/exit_status, as every verdict here is, so
# the crash is named by its signal and explained as any other crash.
want_out   "diff_output: ...saying it is the crash" "CRASH: the program died on SIGSEGV" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive
want_out   "diff_output: ...and why a survive case fails on it" "agrees that the" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive
printf 'what happens to a pointer nobody set?\n' > "$WORK/survive_clues.tsv"
want_out   "diff_output: ...with the case's hints" "what happens to a pointer" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive --clues "$WORK/survive_clues.tsv"
# ...read by the one clue rule (rl_clues): a maintainer's '#' line is never
# a hint. And what it wrote is an excerpt that says what it left out. The
# survive branch (w3-model) had a reading of its own and a bare head -10,
# which the runner library (w3-runners) exists to replace.
printf '# maintainers only\nwhat happens to a pointer nobody set?\n' > "$WORK/survive_clues_c.tsv"
want_broken_none "diff_output: ...never a '#' line of the clues" 'maintainers only' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive --clues "$WORK/survive_clues_c.tsv"
printf '#include <stdio.h>\nint main(void){int i;for(i=1;i<=30;i++)printf("line %%d\\n",i);fflush(stdout);*(volatile int*)0=1;return 0;}\n' \
	> "$WORK/survive_chatty.c"
toy_cc "$WORK/survive_chatty" "$WORK/survive_chatty.c"
want_out   "diff_output: ...and a cut excerpt says how much it left out" \
	'20 more line(s)' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/survive_chatty" --survive
want_red   "diff_output: survive fails runaway output" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/runaway" --survive
want_red   "diff_output: survive fails a hang" -- \
	env DIFF_TIMEOUT=1 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/hang" --survive
want_red   "diff_output: survive still checks an exit status it is given" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/ok" --survive --exit 3
want_broken "diff_output: survive with an expected output refuses" "takes no --expected" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/ok" --survive --expected "$WORK/exp.txt"
# What it ran, pass or fail: a survive case has no table to say it, and
# "SURVIVED" alone did not say on what (review of WP-52). Each argument one
# shell word, so the line runs the case again.
want_out   "diff_output: survive says what it ran when it passes" "RAN: ./bad 'two words' '-1'" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --survive -- "two words" -1
want_out   "diff_output: ...and when it fails" "RAN: ./crash '-2147483648'" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive -- -2147483648
# THE GATE (--gate-*): a survive case SKIPs while the exercise's own case is
# red, since a program nobody has written ends by itself too -- do-op's stub
# was green on INT_MIN / -1. sv_gate prints the gate case's line and crashes
# on any argument, so the gate case (no argument) can be green while the
# survive case (an argument) crashes. `env -u NO_SKIP`, because the suite runs
# with NO_SKIP=1 (it forces every gate open) and these arms are about the gate.
printf '#include <stdio.h>\nint main(int c,char**v){(void)v;if(c>1)*(volatile int*)0=1;printf("hello\\n");return 0;}\n' \
	> "$WORK/sv_gate.c"
toy_cc "$WORK/sv_gate" "$WORK/sv_gate.c"
want_green "diff_output: survive SKIPs while its gate case is red" -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive \
	--gate-expected "$WORK/exp.txt" --gate-arg one --gate-label ex00_one_output -- big
want_out   "diff_output: ...naming the case to get green first" "diff_output: SKIP — ex00_one_output is not passing yet" -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive \
	--gate-expected "$WORK/exp.txt" --gate-arg one --gate-label ex00_one_output -- big
want_out   "diff_output: ...and this test, never the repo, to force it open" \
	'bazel test //c-piscine/c-piscine-c-88:ex00_big_exit --test_env=NO_SKIP=1' -- \
	env -u NO_SKIP TEST_TARGET=//c-piscine/c-piscine-c-88:ex00_big_exit \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive \
	--gate-expected "$WORK/exp.txt" --gate-arg one --gate-label ex00_one_output -- big
want_red   "diff_output: ...and runs once it is green" -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/sv_gate" --survive \
	--gate-expected "$WORK/exp.txt" --gate-label ex00_one_output -- big
want_red   "diff_output: ...or when NO_SKIP=1 forces it open" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive \
	--gate-expected "$WORK/exp.txt" --gate-arg one -- big
# The gate case's arguments reach it as they are: sv_gate passes its gate
# with none and fails it with one, so a gate that dropped them stays green.
want_green "diff_output: ...handing the gate case its own arguments" -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/sv_gate" --survive \
	--gate-expected "$WORK/exp.txt" --gate-arg "two words" -- big
want_red   "diff_output: a gate that cannot answer runs the case anyway" -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive \
	--gate-expected "$WORK/no-such-expected.txt" -- big
# A survive case over a build that made nothing (the empty stand-in: an
# exercise nobody has started) SKIPs on its red gate, whose case runs the
# same stand-in. It met the stand-in check first and was red (V281), on Rush
# 02's stub four times, while its asan and valgrind arms said SKIP. Past a
# gate NO_SKIP=1 forced open, or a green one, a stand-in is still a build
# failure.
want_green "diff_output: survive on an empty stand-in SKIPs on its red gate" -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/standin/empty" --survive \
	--gate-expected "$WORK/exp.txt" --gate-label ex00_one_output -- big
want_out   "diff_output: ...naming the case it waits for" "diff_output: SKIP — ex00_one_output is not passing yet" -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/standin/empty" --survive \
	--gate-expected "$WORK/exp.txt" --gate-label ex00_one_output -- big
want_red   "diff_output: ...and is a build failure when NO_SKIP=1 opens it" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/standin/empty" --survive \
	--gate-expected "$WORK/exp.txt" --gate-label ex00_one_output -- big
want_out   "diff_output: ...told as one" 'there was nothing to build' -- \
	env NO_SKIP=1 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/standin/empty" --survive \
	--gate-expected "$WORK/exp.txt" --gate-label ex00_one_output -- big
want_out   "diff_output: ...and past a green gate" 'there was nothing to build' -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/standin/empty" --expected "$WORK/exp.txt" \
	--gate-bin "$WORK/ok" --gate-expected "$WORK/exp.txt" --gate-label ex00_one_output
want_broken "diff_output: a gate on a case with an expected output refuses" "needs no gate" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/ok" --expected "$WORK/exp.txt" \
	--gate-expected "$WORK/exp.txt"
# A CASE THAT WAITS FOR ANOTHER PROGRAM'S (--gate-bin): the same code run
# through another test program, whose fixture has the table and the hints.
# While that one is red this one SKIPs, and it is judged once it is green.
# Rush 00's defense case waits so for its variant's labelled table. `bad`
# fails exp.txt and `ok` passes it, so `bad` stands in for both programs.
want_green "diff_output: a case waiting on another's SKIPs" -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --expected "$WORK/exp.txt" \
	--gate-bin "$WORK/bad" --gate-expected "$WORK/exp.txt" --gate-label ex00_one_output
want_out   "diff_output: ...naming that case" "diff_output: SKIP — ex00_one_output is not passing yet" -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --expected "$WORK/exp.txt" \
	--gate-bin "$WORK/bad" --gate-expected "$WORK/exp.txt" --gate-label ex00_one_output
want_out   "diff_output: ...in a waiting case's words" 'fails for the same reason' -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --expected "$WORK/exp.txt" \
	--gate-bin "$WORK/bad" --gate-expected "$WORK/exp.txt" --gate-label ex00_one_output
want_broken_none "diff_output: ...never a survive case's" 'ends by itself' -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --expected "$WORK/exp.txt" \
	--gate-bin "$WORK/bad" --gate-expected "$WORK/exp.txt" --gate-label ex00_one_output
want_red   "diff_output: ...and is judged once that is green" -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --expected "$WORK/exp.txt" \
	--gate-bin "$WORK/ok" --gate-expected "$WORK/exp.txt" --gate-label ex00_one_output
want_red   "diff_output: ...or when NO_SKIP=1 forces it open" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --expected "$WORK/exp.txt" \
	--gate-bin "$WORK/bad" --gate-expected "$WORK/exp.txt" --gate-label ex00_one_output
want_red   "diff_output: ...or when its gate cannot answer" -- \
	env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --expected "$WORK/exp.txt" \
	--gate-bin "$WORK/bad" --gate-expected "$WORK/no-such-expected.txt" --gate-label ex00_one_output

# ---- a case's "missing_file" (--absent) -------------------------------------
#
# The case says this operand will not open; a file by that name where the
# program runs would make it a different case under the same verdict, so the
# runner refuses (2), naming it, and runs nothing.
want_broken "diff_output: a missing_file that is there refuses" "holds something by that name" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/ok" --expected "$WORK/exp.txt" \
	--absent "$WORK/no_such_file_st" --absent "$WORK/exp.txt"
want_green "diff_output: ...and one that is not there runs the case" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/ok" --expected "$WORK/exp.txt" \
	--absent "$WORK/no_such_file_st"

# ---- a program's case: the run it describes, and a report that says it ------
#
# A program's case is a test of its own. Its report said nothing of what had
# been run (finding 120) and no hint could name it (155), and two runs could
# not be cases at all: an empty argument, which Bazel's `args` drops (157),
# and the subject's `./rush-02 42` beside numbers.dict (162). The toys below
# print their arguments, or the first line of ./toy.dict, and answer nothing.
printf '#include <stdio.h>\nint main(int ac, char **av){int i; for (i = 1; i < ac; i++) printf("[%%s]\\n", av[i]); return (0);}\n' \
	> "$WORK/pc_echo.c"
toy_cc "$WORK/pc_echo" "$WORK/pc_echo.c"
printf 'a b\n\n' > "$WORK/pc.argv"
printf '[x]\n[a b]\n[]\n' > "$WORK/pc_echo.txt"
printf 'in\n' > "$WORK/pc_in.txt"
pc_echo() {
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/pc_echo" --expected "$WORK/pc_echo.txt" "$@"
}
# A case with no stdin of its own reads /dev/null, never what the runner was
# handed: a program that reads stdin behaved one way under `bazel test` and
# another in a pipe or a gate (valgrind_test.sh already pinned it). Rush 02's
# argument-count cases, which judge only that the program ends, rely on it.
printf '#include <unistd.h>\nint main(void){char c; while (read(0, &c, 1) == 1) write(1, &c, 1); return (0);}\n' \
	> "$WORK/pc_cat.c"
toy_cc "$WORK/pc_cat" "$WORK/pc_cat.c"
: > "$WORK/pc_nothing.txt"
pc_piped() {
	printf 'leak\n' | "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/pc_cat" --expected "$WORK/pc_nothing.txt" "$@"
}
want_green "diff_output: a case with no stdin reads /dev/null" -- pc_piped
want_green "diff_output: --argv-file passes a spaced and an empty argument" -- \
	pc_echo --argv-file "$WORK/pc.argv" -- x
want_red   "diff_output: ...which the same run without the file lacks" -- pc_echo -- x
want_broken "diff_output: an --argv-file that is not there refuses" 'is not readable' -- \
	pc_echo --argv-file "$WORK/pc_nothere.argv" -- x
want_out   "diff_output: --show-run opens with the run, each word quoted" \
	"RAN: bazel-bin/m/ex00_bin x 'a b' ''" -- \
	pc_echo --show-run bazel-bin/m/ex00_bin --argv-file "$WORK/pc.argv" -- x
want_out   "diff_output: ...and its stdin" "'' < $WORK/pc_in.txt" -- \
	pc_echo --show-run bazel-bin/m/ex00_bin --argv-file "$WORK/pc.argv" --stdin "$WORK/pc_in.txt" -- x
want_out   "diff_output: ...in the exit twin too" 'RAN: bazel-bin/m/ex00_bin x' -- \
	pc_echo --show-run bazel-bin/m/ex00_bin --exit-only --exit 0 --exit-source convention -- x
want_broken_none "diff_output: no RAN line unless asked" 'RAN:' -- pc_echo -- x
printf '%s\n' '#include <stdio.h>' \
	'int main(void) { char b[64]; FILE *f = fopen("toy.dict", "r");' \
	'	if (!f) return (printf("no toy.dict here\n"), 1);' \
	'	if (fgets(b, sizeof b, f)) fputs(b, stdout); fclose(f); return (0); }' > "$WORK/pc_dict.c"
toy_cc "$WORK/pc_dict" "$WORK/pc_dict.c"
printf 'staged\n' > "$WORK/pc_staged.txt"
pc_dict() {
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/pc_dict" --expected "$WORK/pc_staged.txt" "$@"
}
want_green "diff_output: --run-as runs from a folder holding --cwd-file" -- \
	pc_dict --run-as toy --cwd-file "toy.dict=$WORK/pc_staged.txt"
want_red   "diff_output: ...which the run from here lacks" -- pc_dict
want_out   "diff_output: ...and RAN names it as the case runs it" 'RAN: ./toy' -- \
	pc_dict --run-as toy --cwd-file "toy.dict=$WORK/pc_staged.txt" --show-run bazel-bin/m/ex00_bin
want_out   "diff_output: ...with where each file of the folder came from" \
	"toy.dict  a copy of $WORK/pc_staged.txt" -- \
	pc_dict --run-as toy --cwd-file "toy.dict=$WORK/pc_staged.txt" --show-run bazel-bin/m/ex00_bin
want_broken "diff_output: --cwd-file with no --run-as refuses" 'stages a file in the folder' -- \
	pc_dict --cwd-file "toy.dict=$WORK/pc_staged.txt"
want_broken "diff_output: a --cwd-file outside the folder refuses" 'not a file name inside' -- \
	pc_dict --run-as toy --cwd-file "../toy.dict=$WORK/pc_staged.txt"
# "." copies the file in under its OWN name, so the case ran without the file
# it names; the program's own name is where its copy sits. c_program refuses
# both while loading (_case_problem); a runner called by hand refuses them too.
want_broken "diff_output: a --cwd-file named . refuses" 'not a file name inside' -- \
	pc_dict --run-as toy --cwd-file ".=$WORK/pc_staged.txt"
want_broken "diff_output: ...and one under the program's own name" 'not a file name inside' -- \
	pc_dict --run-as toy --cwd-file "toy=$WORK/pc_staged.txt"
# A missing_file is looked for where the program runs: in the run folder when
# the case has one. It was looked for in the runner's own directory whatever
# the case, so a name that was only there stopped a case run elsewhere (2),
# and a file the case staged under that name in its folder was never seen.
# pc_here runs the runner from a directory holding pc_ghost.
mkdir -p "$WORK/pc_here"
: > "$WORK/pc_here/pc_ghost"
# $TOOLS is relative to the runfiles root, so it is made absolute before the cd.
_pc_tools=$(cd "$TOOLS" && pwd)
pc_here() {
	(cd "$WORK/pc_here" && "$SH" "$_pc_tools/diff_output.sh" --bin "$WORK/pc_dict" \
		--expected "$WORK/pc_staged.txt" "$@")
}
want_green "diff_output: --absent with --run-as ignores the runner's own folder" -- \
	pc_here --run-as toy --cwd-file "toy.dict=$WORK/pc_staged.txt" --absent pc_ghost -- pc_ghost
want_broken "diff_output: ...and looks in the run folder, which holds it here" \
	'and the folder it runs' -- \
	pc_dict --run-as toy --cwd-file "toy.dict=$WORK/pc_staged.txt" \
		--cwd-file "pc_ghost=$WORK/pc_staged.txt" --absent pc_ghost -- pc_ghost
want_broken "diff_output: ...and with no run folder, in the runner's own" \
	"and $WORK/pc_here" -- \
	pc_here --absent pc_ghost -- pc_ghost
# A stdin path given relative to the runner's folder still reaches a program
# run from its own folder (--run-as), and the RAN line shows it as given.
pc_relin() {
	(cd "$WORK" && "$SH" "$_pc_tools/diff_output.sh" --bin "$WORK/pc_cat" \
		--expected "$WORK/pc_in.txt" --stdin pc_in.txt --run-as toy --show-run bazel-bin/m/ex00_bin)
}
want_green "diff_output: --run-as reads a relative --stdin from where the runner ran" -- pc_relin
want_out   "diff_output: ...and RAN shows that path as given" 'RAN: ./toy < pc_in.txt' -- pc_relin
# --case: a row naming this case fires on it and no row naming another does;
# the rows naming none still fire. A survive case keys its hints the same way.
printf 'about case a?\ta\nabout case b?\tb\nabout any failure?\n' > "$WORK/pc_clues.tsv"
want_out   "diff_output: --case fires the row naming its case" 'about case a?' -- \
	pc_echo --case a --clues "$WORK/pc_clues.tsv" -- x
want_broken_none "diff_output: ...and no row naming another case" 'about case b?' -- \
	pc_echo --case a --clues "$WORK/pc_clues.tsv" -- x
want_out   "diff_output: ...nor forgets a row naming none" 'about any failure?' -- \
	pc_echo --case a --clues "$WORK/pc_clues.tsv" -- x
printf 'about memory?\tvalgrind\n' >> "$WORK/pc_clues.tsv"
want_broken_none "diff_output: ...nor shows a row keyed to the valgrind layer" 'about memory?' -- \
	pc_echo --case a --clues "$WORK/pc_clues.tsv" -- x
want_out   "diff_output: a survive case keys its hints to its name" 'about case a?' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive --case a --clues "$WORK/pc_clues.tsv"
want_broken_none "diff_output: ...not to another's" 'about case b?' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --survive --case a --clues "$WORK/pc_clues.tsv"
# A row naming the case fires whenever the case fails, like a row naming
# none: the footer must not promise that passing cases frees its slot.
printf 'one?\ta\ntwo?\ta\nthree?\ta\nfour?\ta\n' > "$WORK/pc_clues4.tsv"
want_out   "diff_output: hints hidden behind a case's own are not unlockable" 'passing cases will not' -- \
	pc_echo --case a --clues "$WORK/pc_clues4.tsv" -- x

# ---- the HINTS block, which is what a stuck beginner actually reads ---------
#
# Three separate things were wrong with it, and all three were invisible from
# the exit status, which is why nothing had caught them.
printf 'alpha\nbeta\n' > "$WORK/hexp.txt"
printf '#include <stdio.h>\nint main(void){printf("alpha\\nWRONG\\n");return 0;}\n' > "$WORK/hbad.c"
toy_cc "$WORK/hbad" "$WORK/hbad.c"
hint_run() {
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/hbad" --expected "$WORK/hexp.txt" \
		--labeled --clues "$1"
}

# 1. A row with NO member labels fires on any failure, so it never stops firing
#    until everything passes -- at which point there is no HINTS block at all.
#    Rows past the cap of 3 in such a file are therefore UNREACHABLE, and the
#    footer told the student to "unlock them by passing more cases", which is
#    the one thing that cannot work. Three real clue files are entirely these
#    rows; a rush-02 student was promised seven hints they could never see.
printf 'first\nsecond\nthird\nfourth\nfifth\n' > "$WORK/clue_catchall.tsv"
want_out "diff_output: unreachable hints are not promised as unlockable" \
	"passing cases will not" -- hint_run "$WORK/clue_catchall.tsv"
want_broken_none "diff_output: ... and the false promise is gone" \
	"unlock them by passing more cases)" -- hint_run "$WORK/clue_catchall.tsv"

# 2. Where the hidden hints ARE case-keyed, "pass more cases" is accurate --
#    fixing an earlier case stops its hint firing and lets a later one rise
#    into the cap. That wording must survive for the file shape it is true of.
printf 'catchall\nkeyed-a\tline 2\nkeyed-b\tline 2\nkeyed-c\tline 2\n' \
	> "$WORK/clue_gated.tsv"
want_out "diff_output: case-keyed hints still say 'pass more cases'" \
	"unlock it by passing more cases" -- hint_run "$WORK/clue_gated.tsv"

# 3. When no row names the failing case and the file has no catch-all, this
#    printed NOTHING. 83 cases across 31 exercises are in exactly that state,
#    and they are mostly the boundaries -- INT_MIN, the empty string, "returns
#    dest" -- where a beginner is stuck hardest and can least tell a missing
#    hint from a missing idea. Show what the exercise has, labelled as
#    unmatched so nobody chases the wrong one.
printf 'about-line-1\tline 1\nanother\tline 1\n' > "$WORK/clue_unmatched.tsv"
want_out "diff_output: an uncovered case still gets the exercise's hints" \
	"none matches this case" -- hint_run "$WORK/clue_unmatched.tsv"
want_out "diff_output: ... and they are actually printed" \
	"about-line-1" -- hint_run "$WORK/clue_unmatched.tsv"

# 4. rl_clues itself, on invented rows and labels. FIRST is a case label as
#    the table wrote it, and a label may hold a backslash: read through -v,
#    awk turned "\t" in it into a tab, so the dying case's row was never
#    moved first and sat behind the cap of 3.
rl_clues_of() {  # rl_clues_of CLUES FIRST FAILED-LABEL...: the HINTS block
	_rc_c=$1 _rc_first=$2
	shift 2
	printf '%s\n' "$@" > "$WORK/rc_failed"
	"$SH" -c '. "$1"; rl_clues "$2" "$3" "$4"' _ "$TOOLS/runner_lib.sh" \
		"$_rc_c" "$WORK/rc_failed" "$_rc_first"
}
printf 'hint A\ta\nhint B\tb\nhint C\tc\nhint TABS\tembedded tabs "x\\ty\\tz"\nhint PLAIN\tplain\n' \
	> "$WORK/rc_bs.tsv"
rl_clues_first_bs() {  # the first hint shown when the dying case's label holds a backslash
	rl_clues_of "$WORK/rc_bs.tsv" 'embedded tabs "x\ty\tz"' a b c plain \
		'embedded tabs "x\ty\tz"' | sed -n 's/^   \* //p' | head -n 1
}
want_out "rl_clues: a dying case's label with a backslash still moves its row first" \
	'hint TABS' -- rl_clues_first_bs
# 5. The footer's promise is decided by the rows SHOWN: a hidden row rises
#    only when a shown one stops firing, and only a row keyed to a case
#    does. Shown rows keyed to cases, a catch-all hidden: passing those
#    cases shows it.
printf 'a?\tA\nb?\tB\nc?\tC\nany failure?\n' > "$WORK/rc_keyedshown.tsv"
want_out "rl_clues: hidden behind rows keyed to cases, a catch-all is unlockable" \
	'unlock it by passing more cases' -- rl_clues_of "$WORK/rc_keyedshown.tsv" '' A B C
#    Shown catch-alls, a row keyed to a case hidden: passing cases frees
#    no slot...
printf 'x?\ny?\nz?\nk?\tB\n' > "$WORK/rc_catchshown.tsv"
want_out "rl_clues: hidden behind catch-alls, a keyed row is not promised" \
	'passing cases will not' -- rl_clues_of "$WORK/rc_catchshown.tsv" '' A B
want_broken_none "rl_clues: ...nor said to fire on any failure" \
	'on any failure' -- rl_clues_of "$WORK/rc_catchshown.tsv" '' A B
#    ...unless a FIRST is given: passing the first case makes another first,
#    and its keyed row moves to the top.
want_out "rl_clues: ...unless the first case's order can lift it" \
	'unlock it by passing more cases' -- rl_clues_of "$WORK/rc_catchshown.tsv" A A B

# ---- THE VERDICT, decided before anything is rendered (findings 035, 042, 092)
#
# The table used to decide RESULT from its rows alone, with awk's == (which
# compares two numeric-looking fields AS NUMBERS), and two later checks -- the
# bytes and the exit status -- printed their own lines after a RESULT: PASS,
# with no hints. Every arm below is a program that is right in all but one
# respect, and the respect is the point.
#
# `emit FILE [STATUS]` prints a file and exits with STATUS: any byte stream, any
# ending, with no program behind it that answers anything.
printf '#!/bin/sh\ncat "$1"\nexit "${2:-0}"\n' > "$WORK/emit"
chmod +x "$WORK/emit"
# STATUS may be left out, so the shift is of what there is: `shift 3` over
# two arguments is an error that ends dash's shell, the selftest's own under
# want_red or want_green, and every arm after it with it.
emit_run() {  # emit_run EXPECTED GOT [STATUS] [diff_output flags...]
	_e="$1"; _g="$2"; _s="${3:-0}"
	if [ "$#" -ge 3 ]; then shift 3; else shift "$#"; fi
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/emit" --expected "$_e" "$@" \
		-- "$_g" "$_s"
}
printf 'keyed to line 1?\tline 1\ncaught by any failure?\n' > "$WORK/v_clues.tsv"

# Rows compare as strings: "042" is not "42", and "7 " is not "7". Both went
# red before too, but only through the byte check after a table of PASS rows,
# so the arms assert the ROW.
printf '42\n' > "$WORK/v_42.txt"; printf '042\n' > "$WORK/v_042.txt"
printf '7\n' > "$WORK/v_7.txt"; printf '7 \n' > "$WORK/v_7sp.txt"
want_out   "diff_output: rows compare as strings (042 is not 42)" '0/1 passed, 1 failed' -- \
	emit_run "$WORK/v_42.txt" "$WORK/v_042.txt" 0
want_out   "diff_output: a trailing space fails its row" '0/1 passed, 1 failed' -- \
	emit_run "$WORK/v_7.txt" "$WORK/v_7sp.txt" 0
want_out   "diff_output: ...and the space is visible before the \$" '7 $' -- \
	emit_run "$WORK/v_7.txt" "$WORK/v_7sp.txt" 0
want_out   "diff_output: emit_run without a status is a run that exits 0" '1/1 passed' -- \
	emit_run "$WORK/v_42.txt" "$WORK/v_42.txt"

# A failing row shows its bytes, through the one renderer: a NUL and a byte
# above 0x7f as \xHH -- and a literal $ as \x24, since a $ in a cell is where
# the line ended: an expected line ending in a $ used to read exactly like a
# line that ended there.
printf 'ab\n' > "$WORK/v_ab.txt"; printf 'a\000b\377\n' > "$WORK/v_anb.txt"
want_out   "diff_output: a NUL in a failing row reads \\x00" 'a\x00b\xff$' -- \
	emit_run "$WORK/v_ab.txt" "$WORK/v_anb.txt" 0
printf 'ab$\n' > "$WORK/v_abd.txt"
want_out   "diff_output: a literal \$ in a failing row is not a line end" 'ab\x24$' -- \
	emit_run "$WORK/v_abd.txt" "$WORK/v_ab.txt" 0
want_out   "diff_output: ...and the legend says what \\x24 is" '\x24 a dollar' -- \
	emit_run "$WORK/v_abd.txt" "$WORK/v_ab.txt" 0

# A value the TEST PROGRAM escaped (--escaped-values): Rush 00 prints a whole
# rectangle as one value, a line break as \n and a backslash as \\, and C 02
# ex01 a NUL as \x00. Rendered as raw bytes those cells were escaped a second
# time -- "/\\\n" read "/\\\\\\n" under a legend saying \\ is one backslash.
printf 'r\t/\\\\\\n\\x00\n' > "$WORK/v_esc_e.txt"
printf 'r\t/\\\\\\n\\x00Z\n' > "$WORK/v_esc_g.txt"
want_out   "diff_output: a harness-escaped cell is shown as it was written" \
	'/\\\n\x00$' -- emit_run "$WORK/v_esc_e.txt" "$WORK/v_esc_g.txt" 0 --labeled --escaped-values
want_out   "diff_output: ...and the legend names its \\n" '\n a line break' -- \
	emit_run "$WORK/v_esc_e.txt" "$WORK/v_esc_g.txt" 0 --labeled --escaped-values
# (The legend is wrapped, and where depends on its first words: the
# parenthesis may open on one line and close on the next.)
want_out   "diff_output: ...and says \\x00 is a NUL" 'is a NUL)' -- \
	emit_run "$WORK/v_esc_e.txt" "$WORK/v_esc_g.txt" 0 --labeled --escaped-values
want_out   "diff_output: without the flag the same bytes are raw, and doubled" \
	'/\\\\\\n\\x00$' -- emit_run "$WORK/v_esc_e.txt" "$WORK/v_esc_g.txt" 0 --labeled
# Declared and not kept: an expected file in another notation is the
# harness's error, found before the program runs.
printf 'r\tHi\\0XX\n' > "$WORK/v_esc_bad.txt"
want_broken "diff_output: --escaped-values refuses a value in another notation" \
	'line 1: "\0XX"' -- emit_run "$WORK/v_esc_bad.txt" "$WORK/v_esc_bad.txt" 0 --labeled --escaped-values
want_broken "diff_output: ...and runs only on labeled rows" 'needs --labeled' -- \
	emit_run "$WORK/v_esc_e.txt" "$WORK/v_esc_e.txt" 0 --escaped-values
# A long escaped value is cut on whole marks: the window around the first
# difference starts inside the last \x00, and is widened back to its backslash.
_esc_long=""; _i=0
while [ "$_i" -lt 30 ]; do _esc_long="${_esc_long}\\\\x00"; _i=$((_i + 1)); done
printf "r\t${_esc_long}Y\n" > "$WORK/v_esc_le.txt"
printf "r\t${_esc_long}Z\n" > "$WORK/v_esc_lg.txt"
want_out   "diff_output: ...and a window never cuts a mark in two" '...\x00Y$' -- \
	env DIFF_CELL_MAX=10 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/emit" \
		--expected "$WORK/v_esc_le.txt" --labeled --escaped-values -- "$WORK/v_esc_lg.txt" 0

# The legend names the marks of the rows SHOWN. The row cap hides the second
# failing row, the only one holding a tab: its \t used to be named all the same.
printf 'one\ntwo\tx\n' > "$WORK/v_cap_e.txt"; printf 'One\ntwo\ty\n' > "$WORK/v_cap_g.txt"
want_broken_none "diff_output: a mark only a hidden row holds is not in the legend" \
	'\t a tab' -- env DIFF_MAX_ROWS=1 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/emit" \
		--expected "$WORK/v_cap_e.txt" -- "$WORK/v_cap_g.txt" 0
want_out   "diff_output: ...and one a shown row holds is" '\t a tab' -- \
	emit_run "$WORK/v_cap_e.txt" "$WORK/v_cap_g.txt" 0

# Lines that match and bytes that do not: the final newline, said by name,
# with the hints that are keyed to no case -- a keyed one would point at a row
# that passed.
printf 'x\ny' > "$WORK/v_xy.txt"; printf 'x\ny\n' > "$WORK/v_xynl.txt"
want_red   "diff_output: an extra final newline fails" -- \
	emit_run "$WORK/v_xy.txt" "$WORK/v_xynl.txt" 0
want_out   "diff_output: ...in the RESULT line" 'FAIL  (lines match, bytes differ)' -- \
	emit_run "$WORK/v_xy.txt" "$WORK/v_xynl.txt" 0
want_out   "diff_output: ...naming the final newline" 'only difference is the final newline' -- \
	emit_run "$WORK/v_xy.txt" "$WORK/v_xynl.txt" 0
want_out   "diff_output: ...with the hints keyed to no case" 'caught by any failure?' -- \
	emit_run "$WORK/v_xy.txt" "$WORK/v_xynl.txt" 0 --clues "$WORK/v_clues.tsv"
want_broken_none "diff_output: ...and none keyed to a passing row" 'keyed to line 1?' -- \
	emit_run "$WORK/v_xy.txt" "$WORK/v_xynl.txt" 0 --clues "$WORK/v_clues.tsv"
# The premise false: a row that differs is a row failure, not "the final newline".
printf 'z' > "$WORK/v_z.txt"
want_broken_none "diff_output: a row difference is not blamed on the newline" 'final newline' -- \
	emit_run "$WORK/v_xynl.txt" "$WORK/v_z.txt" 0

# The exit status, inside the verdict and on stdout, in the student's terms.
printf 'x\n' > "$WORK/v_x.txt"
want_red   "diff_output: right output, wrong --exit fails" -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit 0
want_out   "diff_output: ...and RESULT says both statuses" 'output right; exited 3, this case expects 0' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit 0
want_out   "diff_output: ...with hints" 'caught by any failure?' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit 0 --clues "$WORK/v_clues.tsv"
want_out   "diff_output: a subject's status is called the subject's" 'The subject names this status' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit 0
want_out   "diff_output: a convention is called this repo's" "this repo's, not the" -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit 0 --exit-source convention
# A status other than 0 the subject gives no number for is this repo's rule
# too, never a reading: the robust _exit target called it "this / repo's
# reading" over two echo lines until wave 6's review.
want_out   "diff_output: ...and so is a status other than 0, as its rule" \
	"repo's rule, checked above basic, not the subject's" -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit 1 --exit-source convention
want_broken_none "diff_output: ...never as a reading" 'reading' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit 1 --exit-source convention
# A status a sentence of the subject is READ as naming (C 10's "performs the
# same function as the system's tail", finding 115): judged like any status,
# explained as a reading at strict -- never as the subject's word at every
# level -- with the sentence it reads.
want_red   "diff_output: a reading's status is judged" -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit 1 --exit-source reading
want_out   "diff_output: ...and called this harness's reading, checked at strict" \
	"for this one is this harness's reading, never the subject's," -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit 1 --exit-source reading
want_broken_none "diff_output: ...never the subject's word at every level" 'at every level' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit 1 --exit-source reading
want_out   "diff_output: ...quoting the sentence it reads" 'The sentence: "a toy does what its model does"' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit 1 --exit-source reading \
		--exit-quote 'a toy does what its model does'
want_green "diff_output: a reading's status, returned, passes" -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 1 --exit 1 --exit-source reading
want_out   "diff_output: a subject's status is quoted too" 'It says: "the toy returns 0"' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit 0 --exit-quote 'the toy returns 0'
want_broken "diff_output: an unknown --exit-source refuses" 'must be subject, reading, convention or default' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 0 --exit 0 --exit-source mine
# The Run contract's robust twin: how the run ended, and nothing else.
want_red   "diff_output: --exit-only fails a plain non-zero return" -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --exit-only --exit 0 --exit-source convention
want_green "diff_output: --exit-only does not judge the output" -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_z.txt" 0 --exit-only --exit 0 --exit-source convention
want_broken "diff_output: --exit-only with no --exit refuses" 'needs --exit' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 0 --exit-only
# ...and basic only notes a return the subject names no status for.
want_green "diff_output: --note-exit passes a plain non-zero return" -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --note-exit 0
want_out   "diff_output: ...and says so" 'from your subject names an exit' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 3 --note-exit 0
# The note names the check that does fail it, when Bazel says which test this
# is: c_program's twin of exNN_<case>_output is exNN_<case>_exit.
want_out   "diff_output: ...naming the robust twin" 'That check is //m:ex00_a_exit.' -- \
	env TEST_TARGET=//m:ex00_a_output "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/emit" \
		--expected "$WORK/v_x.txt" --note-exit 0 -- "$WORK/v_x.txt" 3
want_broken_none "diff_output: ...and no name it cannot derive" 'That check is' -- \
	env TEST_TARGET=//m:ex00_a_gate "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/emit" \
		--expected "$WORK/v_x.txt" --note-exit 0 -- "$WORK/v_x.txt" 3
# A survive case (a case's "survive", w3-model) takes the same exit flags: its
# basic test notes a return, and a robust twin with --exit-only judges one.
want_green "diff_output: a survive case passes a plain non-zero return" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/emit" --survive --note-exit 0 -- "$WORK/v_x.txt" 3
want_out   "diff_output: ...and notes it" 'the robust exit-status check expects 0' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/emit" --survive --note-exit 0 -- "$WORK/v_x.txt" 3
want_red   "diff_output: --exit-only judges a survive case's return" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/emit" --survive --exit-only --exit 0 \
		--exit-source convention -- "$WORK/v_x.txt" 3

# Nothing expected and nothing printed is one honest row, never "0/0".
: > "$WORK/v_empty.txt"
want_green "diff_output: an empty expectation met passes" -- \
	emit_run "$WORK/v_empty.txt" "$WORK/v_empty.txt" 0
want_out   "diff_output: ...and says the program printed nothing" 'printed nothing, as expected' -- \
	emit_run "$WORK/v_empty.txt" "$WORK/v_empty.txt" 0
want_broken_none "diff_output: ...with no 0/0 table" '0/0' -- \
	emit_run "$WORK/v_empty.txt" "$WORK/v_empty.txt" 0

# A byte stream is summarised by content: offsets and a hex window, not rows
# of raw control bytes. A line of text holding one NUL is still a table.
printf '\001\002\003\004\005\006\007\016\017\020A\n' > "$WORK/v_bin.txt"
printf '\001\002\003\004\005\006\007\016\017\021A\n' > "$WORK/v_bin2.txt"
printf 'some text\000 more text\n' > "$WORK/v_nultext.txt"
want_green "diff_output: identical byte streams pass" -- \
	emit_run "$WORK/v_bin.txt" "$WORK/v_bin.txt" 0
want_red   "diff_output: differing byte streams fail" -- \
	emit_run "$WORK/v_bin.txt" "$WORK/v_bin2.txt" 0
want_out   "diff_output: ...with the first differing byte" 'first difference: byte 10' -- \
	emit_run "$WORK/v_bin.txt" "$WORK/v_bin2.txt" 0
# ...shown as every layer shows bytes (runner_lib.sh's rl_diff_window), where
# this summary printed bare hex after a cmp -l of its own.
want_out   "diff_output: ...in the one byte rendering" \
	'got,      from byte 2: \x02\x03\x04\x05\x06\x07\x0e\x0f\x11A\n' -- \
	emit_run "$WORK/v_bin.txt" "$WORK/v_bin2.txt" 0
want_broken_none "diff_output: text with one NUL is still a table" 'is a byte stream' -- \
	emit_run "$WORK/v_nultext.txt" "$WORK/v_x.txt" 0

# ---- AFTER A CRASH OR A HANG (findings 064, 129) ---------------------------
#
# Five cases in one process, the way every fixture here runs them; case 3
# dies in one of four ways. Linked with tools/unbuffered_stdout.c, as every
# harness output fixture is, and with no setvbuf of its own: the arms below
# are what that library buys, so the library is part of what they test.
# The labels and values are made up and answer no exercise.
printf '%s\n' '#include <stdio.h>' '#include <stdlib.h>' '#include <string.h>' \
	'int main(int ac, char **av)' '{' '	int i;' '	(void)ac;' \
	'	for (i = 1; i <= 5; i++) {' \
	'		if (i == 3 && !strcmp(av[1], "segv")) { printf("case %d\t", i); *(volatile int *)0 = 1; }' \
	'		if (i == 3 && !strcmp(av[1], "abrt")) abort();' \
	'		if (i == 3 && !strcmp(av[1], "ill")) __builtin_trap();' \
	'		if (i == 3 && !strcmp(av[1], "hang")) for (;;) ;' \
	'		printf("case %d\tv%d\n", i, i);' '	}' '	return (0);' '}' > "$WORK/five.c"
toy_cc "$WORK/five" "$WORK/five.c" "$TOOLS/unbuffered_stdout.c"
printf 'case 1\tv1\ncase 2\tv2\ncase 3\tv3\ncase 4\tv4\ncase 5\tv5\n' > "$WORK/five.txt"
# The case-3 hint is the FOURTH row: without its priority, the three hints
# keyed to no case fill the cap and it is never shown.
printf 'any one?\nany two?\nany three?\nabout the third case?\tcase 3\nabout the first case?\tcase 1\n' \
	> "$WORK/five_clues.tsv"
five_run() {  # five_run MODE [DIFF_TIMEOUT]
	env DIFF_TIMEOUT="${2:-30}" "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/five" \
		--harness-fixture --expected "$WORK/five.txt" --labeled --clues "$WORK/five_clues.tsv" -- "$1"
}
want_red   "diff_output: a crash in case 3 of 5 fails" -- five_run segv
want_out   "diff_output: ...keeping the two rows that ran" '2/2 passed before it, 2 not reached' -- \
	five_run segv
want_out   "diff_output: ...marking the case that was running" 'running when the program died' -- \
	five_run segv
want_out   "diff_output: ...and the later ones as not reached" 'not reached' -- five_run segv
want_out   "diff_output: ...with that case's hint first" 'about the third case?' -- five_run segv
want_broken_none "diff_output: ...and no hint for a case that passed" 'about the first case?' -- \
	five_run segv
want_out   "diff_output: SIGSEGV is explained" 'memory it does not own' -- five_run segv
want_out   "diff_output: SIGABRT is explained" 'stopped on purpose' -- five_run abrt
want_out   "diff_output: SIGILL is explained" 'a trap the compiler put' -- five_run ill
want_out   "diff_output: a hang still gets its table" 'running when time ran out' -- \
	five_run hang 1
want_out   "diff_output: ...and the hung case's hint" 'about the third case?' -- \
	five_run hang 1
# The footer's premise false: a program that returned, or that died after
# printing every row, marks no row, so the footer about one must not appear.
want_broken_none "diff_output: no marked-row footer on a plain failure" 'were never printed' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bad" --expected "$WORK/exp.txt"
want_broken_none "diff_output: nor on a crash after the last row" 'were never printed' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --expected "$WORK/exp.txt"

# ---- --harness-fixture: who wrote the program decides what a missing row means
#
# The marking above is true of the harness's own fixtures, which print
# unbuffered, one row per case. A student's program (c_program) may buffer
# its output: this one printf()s three of its four lines and then crashes, so
# the buffer dies with it and nothing reaches the file. Without
# --harness-fixture that must read as "nothing arrived", never as a crash in
# "line 1", the first case (review of 9a0946b).
printf 'l1\nl2\nl3\nl4\n' > "$WORK/buf4.txt"
printf '%s\n' '#include <stdio.h>' \
	'int main(void) { printf("l1\nl2\nl3\n"); *(volatile int *)0 = 1; return (0); }' \
	> "$WORK/bufcrash.c"
toy_cc "$WORK/bufcrash" "$WORK/bufcrash.c"
buf_run() {
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/bufcrash" --expected "$WORK/buf4.txt" "$@"
}
want_red   "diff_output: a buffered program that crashes fails" -- buf_run
want_broken_none "diff_output: ...and is not said to have died in the first case" \
	'the first case' -- buf_run
want_broken_none "diff_output: ...nor to have been running anything" 'running when' -- buf_run
want_out   "diff_output: ...RESULT counts the lines that arrived" '0 of 4 lines in its output' -- buf_run
want_out   "diff_output: ...and says buffering can lose lines" 'not necessarily one it never reached' -- \
	buf_run
# The flag's premise is checked in the binary, not trusted.
want_broken "diff_output: --harness-fixture on a binary without the library refuses" \
	'not linked with' -- buf_run --harness-fixture
# The last expected line ends without a newline and the fixture printed it all
# before dying: every case finished, so no row is marked.
printf 'a\nb' > "$WORK/ab_nonl.txt"
printf '%s\n' '#include <stdio.h>' \
	'int main(void) { printf("a\nb"); *(volatile int *)0 = 1; return (0); }' \
	> "$WORK/abcrash.c"
toy_cc "$WORK/abcrash" "$WORK/abcrash.c" "$TOOLS/unbuffered_stdout.c"
want_out   "diff_output: a crash after an unterminated last row marks nothing" \
	'output right; then the program died' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/abcrash" --harness-fixture --expected "$WORK/ab_nonl.txt"
want_broken_none "diff_output: ...and no row reads running" 'running when' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/abcrash" --harness-fixture --expected "$WORK/ab_nonl.txt"
# The running case printed its label and nothing else.
want_out   "diff_output: a running case cut off after its label reads (nothing yet)" \
	'(nothing yet)' -- five_run segv
# The row cap keeps the running row, and says where rows were left out.
want_out   "diff_output: the row cap keeps the running row" 'running when the program died' -- \
	env DIFF_MAX_ROWS=2 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/five" --harness-fixture \
		--expected "$WORK/five.txt" --labeled -- segv
want_out   "diff_output: ...and marks the rows it left out" '(2 rows not shown)' -- \
	env DIFF_MAX_ROWS=2 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/five" --harness-fixture \
		--expected "$WORK/five.txt" --labeled -- segv
# The marked row is the first one left unfinished, so a fixture must free a
# case's result before that row's newline (V220): one that printed the row
# first and freed it after blamed a crash in free() on the NEXT row, and
# showed the case that crashed as PASS. C 07 ex00's fixture, built over a
# toy that hands back a static block for every call (named apart, the
# fixture's call renamed to it with -D), crashes in its first case's free().
printf '%s\n' 'char	*toy_static_dup(char *src)' '{' '	static char	block[64];' '' \
	'	(void)src;' '	return (block);' '}' > "$WORK/static_dup.c"
_c07_00=$(cd "$TOOLS/.." && pwd)/c-piscine/c-piscine-c-07/tests/ex00
toy_cc "$WORK/static_dup" -Dft_strdup=toy_static_dup \
	"$_c07_00/test_strdup.c" "$WORK/static_dup.c" "$TOOLS/unbuffered_stdout.c"
want_out   "diff_output: a crash in a fixture's free() marks that case's row" \
	'the program died in """ (empty)", the first case' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/static_dup" --harness-fixture --labeled \
		--expected "$_c07_00/expected.txt"
# C 13 ex00's fixture freed its three calls' nodes together after the third
# call's rows, so a crash in the first node's free() was marked on line 9,
# the third call's last row, with the first call's rows shown as passed
# (V303). Built over a toy that hands back one static block for every call
# (named apart, the call renamed with -D; the header is the structure the
# subject prints and nothing more, since the fixture declares its call
# itself), the crash is marked on line 3, the first call's last row.
mkdir -p "$WORK/c13cn"
printf '%s\n' '#ifndef FT_BTREE_H' '# define FT_BTREE_H' \
	'typedef struct s_btree' '{' '	struct s_btree	*left;' '	struct s_btree	*right;' \
	'	void			*item;' '}	t_btree;' '#endif' > "$WORK/c13cn/ft_btree.h"
printf '%s\n' '#include "ft_btree.h"' 'static int	g_zero;' \
	'static t_btree	g_block = {0, 0, &g_zero};' '' 't_btree	*toy_static_node(void *item)' '{' \
	'	(void)item;' '	return (&g_block);' '}' > "$WORK/c13cn/static_node.c"
_c13_00=$(cd "$TOOLS/.." && pwd)/c-piscine/c-piscine-c-13/tests/ex00
toy_cc "$WORK/c13cn/static_node" -I "$WORK/c13cn" -Dbtree_create_node=toy_static_node \
	"$_c13_00/test_btree_create_node.c" "$WORK/c13cn/static_node.c" "$TOOLS/unbuffered_stdout.c"
want_out   "diff_output: ...and C 13 ex00's on the first call's last row" \
	'the program died in "line 3"' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/c13cn/static_node" --harness-fixture \
		--expected "$_c13_00/expected.txt"
# A row says what went wrong, not what it could not see. Libft's
# ft_lstiter fixture checks its 5000-node row call by call up to the 5000th,
# so when the first 5000 calls came in list order and f was called again,
# the row blamed "call 5001" on "node 5001", a node the test never made. It
# names the extra calls instead. Built over a toy that never walks the list
# (named apart, the call renamed with -D; the header holds the structure the
# subject prints and nothing more): it reads the first node's content
# pointer and hands f that pointer and the 5000 after it, one call too many.
mkdir -p "$WORK/lstx"
printf '%s\n' '#ifndef LIBFT_H' '# define LIBFT_H' 'typedef struct s_list' '{' \
	'	void			*content;' '	struct s_list	*next;' '}	t_list;' '#endif' \
	> "$WORK/lstx/libft.h"
printf '%s\n' '#include "libft.h"' \
	'void	toy_iter_extra(t_list *lst, void (*f)(void *))' '{' '	int	*v;' '	int	i;' '' \
	'	if (lst == 0)' '		return ;' '	v = (int *)lst->content;' '	i = 0;' \
	'	while (i <= 5000)' '		f(v + i++);' '}' > "$WORK/lstx/toy_iter_extra.c"
if st_mine; then
	toy_cc "$WORK/lstx/iter_extra" -I "$WORK/lstx" -Dft_lstiter=toy_iter_extra \
		"$(cd "$TOOLS/.." && pwd)/cursus/Milestone_0/Libft/tests/ft_lstiter/test_ft_lstiter.c" \
		"$WORK/lstx/toy_iter_extra.c" "$TOOLS/unbuffered_stdout.c"
fi
want_out   "Libft ft_lstiter fixture: f called once too often is named so" \
	"$(printf '5000 nodes: f called with\t5001 calls, 1 more than the 5000 nodes')" -- \
	"$WORK/lstx/iter_extra"
# A fixture that declares escaped_values writes every value in the notation,
# in every one of its printers. C 03 ex05's three wrote parts of it: one
# printed dest raw, one escaped only a NUL, one never doubled a backslash, so
# a raw backslash and an n read as the line-break mark. Built over a toy
# that writes a backslash, an n and a tab into dest and returns 0 (named
# apart, the call renamed with -D), each row's value must hold them as
# \\, n and \t, and no raw tab past the label's.
mkdir -p "$WORK/lcatesc"
printf '%s\n' 'unsigned int	toy_strlcat_esc(char *dest, char *src, unsigned int size)' '{' \
	'	(void)src;' '	(void)size;' "	dest[0] = '\\\\';" "	dest[1] = 'n';" "	dest[2] = '\\t';" \
	"	dest[3] = '\\0';" '	return (0);' '}' > "$WORK/lcatesc/toy.c"
if st_mine; then
	toy_cc "$WORK/lcatesc/bin" -I "$TOOLS" -Dft_strlcat=toy_strlcat_esc \
		"$(cd "$TOOLS/.." && pwd)/c-piscine/c-piscine-c-03/tests/ex05/test_strlcat.c" \
		"$WORK/lcatesc/toy.c" "$TOOLS/unbuffered_stdout.c"
fi
lcat_esc_run() {
	[ -x "$WORK/lcatesc/bin" ] || { echo "the fixture was not built" >&2; return 2; }
	"$WORK/lcatesc/bin" > "$WORK/lcatesc/out" || return 2
	cat "$WORK/lcatesc/out"
	awk -F'\t' 'NF != 2 || index($2, "\\\\n\\t") == 0 { bad = 1 } END { exit (bad || NR != 15) }' \
		"$WORK/lcatesc/out"
}
want_green "C 03 ex05 fixture: every printer writes the notation it declares" -- lcat_esc_run

# ---- HOW THE RUN ENDED, from waitpid() (tools/exit_status), not from $?
#
# `return (-1);` is the status 255 -- the number a death by "signal 127" would
# give the shell -- and 124 is what a timeout ends with. Both are returns
# here, which basic notes and the robust twin judges: a timeout is the
# helper's report, never a number.
want_green "diff_output: right output and a return of 255 passes basic" -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 255 --note-exit 0
want_broken_none "diff_output: ...is not read as a crash" 'CRASH' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 255 --note-exit 0
want_out   "diff_output: ...and is noted as the status it is" 'returned exit status 255' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 255 --note-exit 0
want_out   "diff_output: --exit-only reads 255 as a return" 'the program returned 255' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 255 --exit-only --exit 0 --exit-source convention
want_broken_none "diff_output: a return of 124 is not a timeout" 'TIMEOUT' -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 124 --note-exit 0
# A c_program case that states nothing about its status gets a twin whose 0
# is a DEFAULT (--exit-source default). On a case expecting an error message
# that default fails a correct program returning 1, so the twin refuses it and
# names the key; a stated decision, or output with no error in it, runs.
printf 'Error\n' > "$WORK/v_err.txt"
want_broken "diff_output: a defaulted status on an error case is refused" \
	'"invalid_input": True' -- \
	emit_run "$WORK/v_err.txt" "$WORK/v_err.txt" 1 --exit-only --exit 0 --exit-source default
want_green "diff_output: ...a stated one runs" -- \
	emit_run "$WORK/v_err.txt" "$WORK/v_err.txt" 0 --exit-only --exit 0 --exit-source convention
want_green "diff_output: ...and so does a default on other output" -- \
	emit_run "$WORK/v_x.txt" "$WORK/v_x.txt" 0 --exit-only --exit 0 --exit-source default
# --exit-only on a run that did not return says how it ended.
want_out   "diff_output: --exit-only on a crash says CRASH" 'CRASH' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/crash" --expected "$WORK/exp.txt" \
		--exit-only --exit 0 --exit-source convention
want_out   "diff_output: --exit-only on a hang says TIMEOUT" 'TIMEOUT' -- \
	env DIFF_TIMEOUT=1 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/five" --expected "$WORK/five.txt" \
		--exit-only --exit 0 --exit-source convention -- hang
# A runaway is the third ending: the table is rendered from what it printed.
want_out   "diff_output: a runaway still gets its table and RESULT" 'stopped for printing too much' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/runaway" --expected "$WORK/exp.txt"
want_out   "diff_output: --status-file says signal, not 128+N" 'signal 11' -- \
	"$SH" -c '"$1" "$2/diff_output.sh" --bin "$3" --expected "$4" --status-file "$5" > /dev/null; cat "$5"' \
		_ "$SH" "$TOOLS" "$WORK/crash" "$WORK/exp.txt" "$WORK/status_file.txt"
# A RUN THAT NEVER STARTED is recorded too (V179): the test's own time had run
# out before the program could start, so --status-file says "notrun". The file
# used to be left unwritten on that path, and ilp32_test.sh, its one reader,
# took the missing line for a run that had ended normally and blamed the type
# model for a run that never happened. An expired RL_DEADLINE is that moment,
# reached without waiting for it.
want_out   "diff_output: --status-file says notrun when no run could start" 'notrun' -- \
	"$SH" -c 'rm -f "$5"; RL_DEADLINE=1 RL_CLOCK=uptime "$1" "$2/diff_output.sh" --bin "$3" --expected "$4" --status-file "$5" > /dev/null; cat "$5"' \
		_ "$SH" "$TOOLS" "$WORK/ok" "$WORK/exp.txt" "$WORK/status_unstarted.txt"
# A TIMEOUT THE TEST'S OWN BUDGET CUT says so on a second line, "clamped S",
# as valgrind_test.sh's does: what was left of the test's time stopped the
# run, not the run's own cap, so a busy machine may be all it was. SHORT's
# nine-second budget against DIFF_TIMEOUT=30 is that case -- nine, not two: a
# two-second one was spent before the run could start often enough, on a
# loaded machine, to write "notrun" instead and turn this arm red at random.
# Deferred, as the wait is. DIFF_TIMEOUT=1 with no deadline is the run's own
# cap, which says no such thing; its arm asks for the one line "timeout", so a
# missing file is no pass.
later_status "diff_output: a timeout the test's budget cut says clamped" 0 'clamped' -- \
	"$SH" -c 'rm -f "$5"; env -u RL_DEADLINE -u RL_BUDGET TEST_TIMEOUT=10 RL_MARGIN=1 DIFF_TIMEOUT=30 "$1" "$2/diff_output.sh" --bin "$3" --harness-fixture --expected "$4" --status-file "$5" -- hang > /dev/null; cat "$5"' \
		_ "$SH" "$TOOLS" "$WORK/five" "$WORK/five.txt" "$WORK/status_cut.txt"
want_out "diff_output: ...and a timeout on its own cap says timeout alone" 'status: only timeout' -- \
	"$SH" -c 'rm -f "$5"; env -u RL_DEADLINE -u RL_BUDGET -u TEST_TIMEOUT DIFF_TIMEOUT=1 "$1" "$2/diff_output.sh" --bin "$3" --harness-fixture --expected "$4" --status-file "$5" -- hang > /dev/null; if [ "$(wc -l < "$5")" = 1 ]; then printf "status: only %s\n" "$(cat "$5")"; else cat "$5"; fi' \
		_ "$SH" "$TOOLS" "$WORK/five" "$WORK/five.txt" "$WORK/status_own.txt"
# The same cut after a row was judged wrong is a verdict: the report drops the
# mark for it (rl__limit) and says the FAIL row stands, so the status drops
# "clamped" too. It once kept it, and ilp32_test.sh, its reader, then said
# "this says nothing yet about this target" under that FAIL row. Here case 2
# expects a value the fixture never prints, and case 3 never ends.
printf 'case 1\tv1\ncase 2\tv9\ncase 3\tv3\ncase 4\tv4\ncase 5\tv5\n' > "$WORK/five_w2.txt"
later_status "diff_output: ...but not after a row was judged wrong" 0 'status: only timeout' -- \
	"$SH" -c 'rm -f "$5"; env -u RL_DEADLINE -u RL_BUDGET TEST_TIMEOUT=10 RL_MARGIN=1 DIFF_TIMEOUT=30 "$1" "$2/diff_output.sh" --bin "$3" --harness-fixture --expected "$4" --status-file "$5" -- hang > /dev/null; if [ "$(wc -l < "$5")" = 1 ]; then printf "status: only %s\n" "$(cat "$5")"; else cat "$5"; fi' \
		_ "$SH" "$TOOLS" "$WORK/five" "$WORK/five_w2.txt" "$WORK/status_wrong_cut.txt"

# THE TIME LIMIT is the helper's own (exit_status --timeout, which rl_run
# passes): it kills the program's process group and RETURNS, reporting
# "timeout". With coreutils' `timeout -s KILL` in front of it, the helper died
# too, and the shell running them announced the SIGKILL with a line of its own,
# "Killed", written into the program's redirected stderr -- the compared
# stream itself, for a case that compares stderr.
printf '#!/bin/sh\nprintf "partial\\n" >&2\nexec sleep 20\n' > "$WORK/hang_err"
chmod +x "$WORK/hang_err"
printf 'never\n' > "$WORK/v_never.txt"
want_out   "diff_output: a case comparing stderr that times out says so" 'TIMEOUT' -- \
	env DIFF_TIMEOUT=1 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/hang_err" \
		--stream stderr --expected "$WORK/v_never.txt"
want_broken_none "diff_output: ...with no shell 'Killed' line in what it got" 'Killed' -- \
	env DIFF_TIMEOUT=1 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/hang_err" \
		--stream stderr --expected "$WORK/v_never.txt"
# AN LD_DEBUG FROM OUTSIDE (V336), a maintainer's --test_env=LD_DEBUG=libs:
# the loader traced every program the runner started onto its stderr, and a
# case comparing stderr read those lines as the program's, red on a correct
# one. Run by hand (no test outputs folder) the tracing is dropped; under
# Bazel it goes to ld_debug.<pid> files in the test's outputs.
printf '#include <unistd.h>\nint main(void){write(1, "out\\n", 4); write(2, "oops\\n", 5); return (0);}\n' > "$WORK/errsay.c"
toy_cc "$WORK/errsay" "$WORK/errsay.c"
printf 'oops\n' > "$WORK/errsay.txt"
printf 'out\n' > "$WORK/outsay.txt"
want_green "diff_output: a case comparing stderr under an LD_DEBUG passes" -- \
	env -u TEST_UNDECLARED_OUTPUTS_DIR -u LD_DEBUG_OUTPUT LD_DEBUG=libs \
		"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/errsay" --stream stderr --expected "$WORK/errsay.txt"
# shellcheck disable=SC2016 # the script is for the inner shell to expand
want_green "diff_output: ...and keeps the loader's lines in the test's outputs" -- \
	"$SH" -c 'mkdir -p "$4" || exit 2
		env -u LD_DEBUG_OUTPUT LD_DEBUG=libs TEST_UNDECLARED_OUTPUTS_DIR="$4" \
			"$1" "$2/diff_output.sh" --bin "$3" --stream stderr --expected "$5" || exit
		for f in "$4"/ld_debug.*; do [ -s "$f" ] && exit 0; done
		echo "no ld_debug.<pid> file in $4"
		exit 1' _ "$SH" "$TOOLS" "$WORK/errsay" "$WORK/lddbg" "$WORK/errsay.txt"
# ...and an LD_DEBUG_OUTPUT the loader cannot open is not kept: the loader
# writes to stdout then, and a case comparing stdout read its lines.
want_green "diff_output: ...and an LD_DEBUG_OUTPUT nobody can write is not kept" -- \
	env -u TEST_UNDECLARED_OUTPUTS_DIR LD_DEBUG=libs LD_DEBUG_OUTPUT="$WORK/lddbg-nowhere/ld" \
		"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/errsay" --stream stdout --expected "$WORK/outsay.txt"
# ...while one it can write, named by its absolute path, is kept as it is:
# the loader's lines for the program under test land there, and none in the
# test's outputs. (The shell's own lines land there whatever the runner
# does, so the program's are what is asked for.)
# shellcheck disable=SC2016 # the script is for the inner shell to expand
want_green "diff_output: ...and a writable LD_DEBUG_OUTPUT is kept" -- \
	"$SH" -c 'mkdir -p "$4" "$5" || exit 2
		env LD_DEBUG=libs LD_DEBUG_OUTPUT="$5/ld" TEST_UNDECLARED_OUTPUTS_DIR="$4" \
			"$1" "$2/diff_output.sh" --bin "$3" --stream stderr --expected "$6" || exit
		for f in "$4"/ld_debug.*; do [ -e "$f" ] && { echo "the trace went to $f"; exit 1; }; done
		cat "$5"/ld.* 2> /dev/null | grep -qF "initialize program: $3" && exit 0
		echo "no trace of the program in $5"
		exit 1' _ "$SH" "$TOOLS" "$WORK/errsay" "$WORK/lddbg-outs" "$WORK/lddbg-kept" "$WORK/errsay.txt"
# And a SIGTERM sent to the helper -- Bazel's, when a test runs out of time --
# kills the program's group at once and says so: a runner used to wait on a
# program that never ends until Bazel's SIGKILL, its own trap never reached.
es_term() {
	"$TOOLS/exit_status" "$WORK/es_term.how" sleep 30 &
	_es=$!
	sleep 1
	kill -TERM "$_es"
	wait "$_es"
	cat "$WORK/es_term.how"
}
want_out   "exit_status: a SIGTERM ends the program's group, and says so" 'stopped 15' -- es_term

# A LIMIT IS THE RUN'S OWN TIME (finding 066): the wait for a CPU on a busy
# machine is given back, up to --ceiling. A program that sleeps waits on no
# queue, so it is stopped at its limit, ceiling or not, with no line saying
# anything was given back (selftest_slow holds the busy CPU's half).
es_sleep() {
	"$TOOLS/exit_status" --timeout 1 --ceiling 30 "$WORK/es_sleep.how" sleep 30
	cat "$WORK/es_sleep.how"
}
want_out   "exit_status: a program that sleeps is stopped at its own limit" 'timeout 1' -- es_sleep
want_broken_none "exit_status: ...with nothing given back" 'queued' -- es_sleep
want_broken_none "exit_status: ...and no ceiling said to have stopped it" 'ceiling' -- es_sleep
# What the report's second line tells the runner: a run stopped at its own
# limit with queue time given back used its OWN seconds; one the ceiling
# stopped first was stopped by the test's limit (RL_CLAMPED, RL_TMO).
rl_rep() {
	printf "$1" > "$WORK/rl_rep.how"
	env -u RL_DEADLINE "$SH" -c '. "$1"; rl_classify 124 "$2"; echo "$RL_WHY|$RL_QUEUED|$RL_CLAMPED|$RL_TMO"' \
		_ "$TOOLS/runner_lib.sh" "$WORK/rl_rep.how"
}
want_out   "runner_lib: queue time given back is said, and the seconds are the run's own" \
	'did not finish within 5s of its own time|7|0|' -- rl_rep 'timeout 5\nqueued 7\n'
want_out   "runner_lib: a run the ceiling stopped was stopped by the test's limit" \
	'did not finish within 9s|3|1|9' -- rl_rep 'timeout 9\nceiling 3\n'

# THE MARGIN a runner keeps back from TEST_TIMEOUT to write its report
# (tools/runner_lib.sh): a tenth, 4 to 20 s. A twentieth -- 3 s of a small
# test's 60 -- was measured too thin under three suites at once: the report was
# printed in full and Bazel's SIGTERM still came first.
rl_budget() { env -u RL_MARGIN -u RL_DEADLINE TEST_TIMEOUT="$1" "$SH" -c '. "$1"; echo "budget $RL_BUDGET"' _ "$TOOLS/runner_lib.sh"; }
want_out   "runner_lib: a small test keeps 6 s of its 60 back" 'budget 54' -- rl_budget 60
want_out   "runner_lib: ...a medium one 20 s of its 300, the most" 'budget 280' -- rl_budget 300
want_out   "runner_lib: ...and never less than 4 s" 'budget 16' -- rl_budget 20

# A REPORT WITH A VERDICT IN HAND carries no RL_OVERRUN_MARK. A sweep that had
# judged cases wrong before the test's time ran out printed the mark as well,
# and tools/first_red.sh filed it as "ran out of time, run it alone" -- hiding
# the wrong answers behind the busy machine (review of wave 3's runners).
rl_stop_with() {
	env TEST_TIMEOUT=60 "$SH" -c '. "$1"; RL_TMO=7; RL_CLAMPED=1; RL_STOP="$2"; rl_sweep_stopped 5 40 "$3"' \
		_ "$TOOLS/runner_lib.sh" "$1" "$2"
}
want_out   "runner_lib: a sweep the test's limit stopped says so" "this test's own time limit" -- \
	rl_stop_with budget 0
want_broken_none "runner_lib: ...not when cases were already judged wrong" "this test's own time limit" -- \
	rl_stop_with budget 2
want_out   "runner_lib: ...which it calls a verdict all the same" 'The 2 case(s) judged wrong before that' -- \
	rl_stop_with budget 2
want_broken_none "runner_lib: ...and one that never started a case, too" "this test's own time limit" -- \
	rl_stop_with start 2

# THE NOTE ON RUNS THAT DID NOT FINISH (rl_dnf_note) keeps near 80 columns
# behind rush01's indent of 14, the widest a caller passes: its first line,
# with no case judged wrong, was 90. The note is read whole first: piped
# straight into the width check, a note that printed nothing, or a
# function that was gone (its "not found" on stderr), had no long line.
rl_dnf_width() {  # rl_dnf_width WRONG: true when the note prints and no line passes 80 columns
	_dw=$(env -u RL_STOP "$SH" -c '. "$1"; RL_DNF=1; RL_STOP=; rl_dnf_note "$2" "              "' \
		_ "$TOOLS/runner_lib.sh" "$1" 2>&1) || { printf '%s\n' "$_dw"; return 2; }
	[ -n "$_dw" ] || { echo 'rl_dnf_note printed nothing'; return 1; }
	printf '%s\n' "$_dw" | awk 'length($0) > 80 { print; bad = 1 } END { exit bad }'
}
want_green "runner_lib: the note on runs not finished fits 80 columns" -- rl_dnf_width 0
want_green "runner_lib: ...with cases judged wrong too" -- rl_dnf_width 2

# A REPLAY LINE IS A SHELL WORD (rl_shword). rush02 printed the number of a
# failing case through rl_vis inside single quotes: a doubled backslash, $ as
# \x24, a byte as \xHH, and a quote that ended the word -- a line that ran
# another input. Each of those, given back byte for byte by the shell.
rl_shword_back() {  # rl_shword_back PRINTF-FORMAT: its bytes, through a word and back
	_rw=$(printf -- "$1" | "$SH" -c '. "$1"; rl_shword' _ "$TOOLS/runner_lib.sh") || return 2
	_back=$("$SH" -c "printf '%s' $_rw" | od -An -tx1)
	_want=$(printf -- "$1" | od -An -tx1)
	[ "$_back" = "$_want" ] && return 0
	echo "word $_rw gave back$_back, not$_want"
	return 1
}
want_green "runner_lib: a replay word keeps a quote, \$ and a backslash" -- \
	rl_shword_back "4'2\$x\\\\y"
want_green "runner_lib: ...a byte that is not printable, and a %" -- \
	rl_shword_back '\001a%%b\377'
want_green "runner_lib: ...and newlines, inside and at the end" -- \
	rl_shword_back '\001a\nb\n\n'
# ...and a word whose bytes start with "-": printf read the format as an
# option (bash: invalid option; dash: Illegal option), so a corpus line of a
# negative number and a tab replayed as an empty line.
want_green "runner_lib: ...and a leading '-' before a byte that is not printable" -- \
	rl_shword_back '-5\t0\n'

# ONE BYTE RENDERER (RL_AWK_VIS). Four renderings drifted: the table showed a
# control byte as ^X and a literal $ as it was, so an expected line ending in
# a $ read exactly as one that ended there; shell_check's excerpt showed any
# control byte as '?'; rl_excerpt left a literal "\x41" looking like a byte.
# Every table and excerpt now goes through the one copy.
rl_vis_of() {  # rl_vis_of MODE PRINTF-FORMAT: the bytes, rendered
	printf "$2" | "$SH" -c '. "$1"; rl_vis "$2"' _ "$TOOLS/runner_lib.sh" "$1"
}
rl_text_of() {  # rl_text_of PRINTF-FORMAT: the bytes as one excerpt line
	printf "$1" > "$WORK/rl_text.txt"
	"$SH" -c '. "$1"; rl_excerpt "$2" 5 t.txt ""' _ "$TOOLS/runner_lib.sh" "$WORK/rl_text.txt"
}
want_out   "runner_lib: exact bytes: a literal \$ is \\x24, the line end \$" 'ab\x24$' -- \
	rl_vis_of lines 'ab$\n'
want_out   "runner_lib: ...a backslash doubled, a tab \\t, a byte \\xHH" 'a\\b\tc\x00\xff$' -- \
	rl_vis_of lines 'a\\b\tc\000\377\n'
want_out   "runner_lib: an excerpt shows a control byte as \\xHH" 'red\x1b[0m' -- \
	rl_text_of 'red\033[0m\n'
want_out   "runner_lib: ...a literal \\x as \\\\x, so \\xHH is always a byte" 'say \\x41' -- \
	rl_text_of 'say \\x41\n'
# Two backslashes before an x are both doubled: doubling the last alone read
# as one backslash and the byte \x41.
want_out   "runner_lib: ...each backslash of a run before an x" 'say \\\\x41' -- \
	rl_text_of 'say \\\\x41\n'
# A backslash before a control byte is doubled too: left single, a backslash
# and the byte 0x01 read "\\x01", which is how the text \x01 reads.
want_out   "runner_lib: ...and of a run before a byte written \\xHH" 'a \\\x01' -- \
	rl_text_of 'a \\\001\n'
want_out   "runner_lib: ...two backslashes before one as well" 'a \\\\\x01' -- \
	rl_text_of 'a \\\\\001\n'
want_broken_none "runner_lib: ...but not a run that ends the line" 'end \\' -- \
	rl_text_of 'end \\\n'
want_out   "runner_lib: ...and every other backslash as it is (a caret stays put)" \
	'write(1, "\n", 1);' -- rl_text_of 'write(1, "\\n", 1);\n'
# A carriage return that ends a line is a byte like any other: a script saved
# with CRLF line ends makes dash print "can't cd to nowhere\r", and the \r is
# the one clue to the cause. It used to be dropped as part of a line ending,
# for one tool that writes CRLF, and every excerpt hid it. --crlf, for a run
# of such a tool, drops it there and nowhere else in the line.
rl_text_crlf() {  # rl_text_crlf PRINTF-FORMAT: the same, under rl_excerpt --crlf
	printf "$1" > "$WORK/rl_text.txt"
	"$SH" -c '. "$1"; rl_excerpt --crlf "$2" 5 t.txt ""' _ "$TOOLS/runner_lib.sh" "$WORK/rl_text.txt"
}
want_out   "runner_lib: ...a carriage return that ends a line, as \\x0d" 'crlf\x0d' -- \
	rl_text_of 'crlf\r\n'
want_out   "runner_lib: ...which --crlf reads as the line's end" 'one' -- \
	rl_text_crlf 'one\r\n'
want_broken_none "runner_lib: ...showing no \\x0d for it" '\x0d' -- \
	rl_text_crlf 'one\r\n'
want_out   "runner_lib: ...and only there: one inside the line is \\x0d" 'a\x0db' -- \
	rl_text_crlf 'a\rb\r\n'
# The window around a first difference (rl_diff_window) names the escapes
# its two lines hold, as a table's legend does: a \xHH with no word of what
# it is reads as four characters the program printed. Nothing escaped,
# nothing named. Invented bytes.
rl_window_of() {  # rl_window_of WANT-FORMAT GOT-FORMAT: the window of the two
	printf "$1" > "$WORK/rl_win_want"
	printf "$2" > "$WORK/rl_win_got"
	"$SH" -c '. "$1"; rl_diff_window "$2" "$3" "  "' _ "$TOOLS/runner_lib.sh" \
		"$WORK/rl_win_want" "$WORK/rl_win_got"
}
want_out   "runner_lib: a difference window names \xHH under its lines" \
	'In the lines above, \n a newline, \t a tab, and \xHH any other byte' -- \
	rl_window_of 'ab\t\351c\n' 'ab\t\351d\n'
want_out   "runner_lib: ...a NUL by name" '(\x00 is a NUL)' -- \
	rl_window_of 'a\000b' 'a\000c'
want_broken_none "runner_lib: ...and with nothing escaped, says nothing" 'In the lines above' -- \
	rl_window_of 'plain words' 'plain wordz'
# A caller whose report names the two sides in its own words passes them, so
# one report keeps one pair of words; the labels are padded to one width and
# the ^ still falls under the byte. Invented bytes.
rl_window_named() {  # the window of "abc" and "abd", its sides named
	printf 'abc' > "$WORK/rl_win_want"
	printf 'abd' > "$WORK/rl_win_got"
	"$SH" -c '. "$1"; rl_diff_window "$2" "$3" "  " reference student' _ \
		"$TOOLS/runner_lib.sh" "$WORK/rl_win_want" "$WORK/rl_win_got"
}
want_out   "runner_lib: a difference window takes its sides' names" \
	'  student,   from byte 1: abd' -- rl_window_named
rl_window_named_caret() {  # true when the ^ line is where the byte is
	rl_window_named | grep -qx -- "  $(printf '%26s' '')^"
}
want_green "runner_lib: ...and puts the ^ under the byte" -- rl_window_named_caret
# A unified diff's legend (rl_udiff) is read off the lines it shows too: a
# mark only a line past MAXLINES holds is never on screen, so it is not
# named. Fifty lines that all differ, a tab on line TAB of the second file
# only, MAX lines of the diff shown. Invented text.
rl_udiff_tab() {  # rl_udiff_tab TAB MAX: the diff, then its legend
	awk 'BEGIN { for (i = 1; i <= 50; i++) print "line " i }' > "$WORK/rl_ud_want"
	awk -v t="$1" 'BEGIN { for (i = 1; i <= 50; i++) print "word" (i == t ? "\t" : " ") i }' \
		> "$WORK/rl_ud_got"
	"$SH" -c '. "$1"; rl_udiff diff "$2" "$3" expected got "$4"' _ "$TOOLS/runner_lib.sh" \
		"$WORK/rl_ud_want" "$WORK/rl_ud_got" "$2"
}
want_broken_none "rl_udiff: a mark only the lines past MAXLINES hold is not named" \
	'\t a tab' -- rl_udiff_tab 45 5
want_out   "rl_udiff: ...one a shown line holds is" '\t a tab' -- rl_udiff_tab 45 200
# ...and the last line of a side that did not end, shown before diff's "\ No
# newline at end of file" and with no $, is a shown line too: its marks are
# named. Invented text.
rl_udiff_nonl() {  # rl_udiff_nonl WANT-FORMAT: the diff of WANT and "a b\n"
	printf "$1" > "$WORK/rl_ud_want"
	printf 'a b\n' > "$WORK/rl_ud_got"
	"$SH" -c '. "$1"; rl_udiff diff "$2" "$3"' _ "$TOOLS/runner_lib.sh" \
		"$WORK/rl_ud_want" "$WORK/rl_ud_got"
}
want_out   "rl_udiff: a mark on a last line that did not end is named" \
	'\t a tab' -- rl_udiff_nonl 'a\tb'
want_out   "rl_udiff: ...a backslash too" '\\ one backslash' -- \
	rl_udiff_nonl 'a\\b'

# ---- A RUN THAT NEVER STARTED is a harness error, never a result
#
# tools/exit_status reports "noexec" when the program never reached main, and
# every runner refuses on it with exit 2. No arm reached that report until a
# review of wave 3 found none did, and found the half it did not cover: exec
# succeeding and the dynamic loader then stopping the program -- an ordinary
# exit 127 to waitpid(), which asan_run called "memory-clean". Three fixtures,
# shared with the other runners' arms below:
#   noint   a script whose #! names an interpreter that does not exist, so
#           execve() itself fails (ENOENT);
#   ldmiss  a C program linked to a shared library that is deleted after the
#           link, so the loader prints "error while loading shared libraries"
#           and exits 127 before main;
#   ldver   one linked against a version of a library the replacement lacks,
#           so the loader exits 1 -- the reason the report is read on any
#           non-zero exit, not only on 127.
# None of them answers anything: they print nothing and name no exercise.
printf '#!/nonexistent/interpreter\nexit 0\n' > "$WORK/noint"
chmod +x "$WORK/noint"
printf 'int selftest_toy(void) { return 0; }\n' > "$WORK/ldtoy.c"
printf 'int selftest_toy(void);\nint main(void) { return selftest_toy(); }\n' > "$WORK/ldmain.c"
mkdir -p "$WORK/ldm" "$WORK/ldv"
toy_cc "$WORK/ldm/libselftesttoy.so" -shared -fPIC "$WORK/ldtoy.c" &&
	toy_cc "$WORK/ldmiss" "$WORK/ldmain.c" -L"$WORK/ldm" -lselftesttoy \
		-Wl,-rpath,"$WORK/ldm"
rm -f "$WORK/ldm/libselftesttoy.so"
printf 'SELFTEST_2 { global: selftest_toy; local: *; };\n' > "$WORK/ldv/new.map"
printf 'SELFTEST_1 { global: selftest_toy; local: *; };\n' > "$WORK/ldv/old.map"
toy_cc "$WORK/ldv/libselftesttoy.so" -shared -fPIC -Wl,--version-script="$WORK/ldv/new.map" \
	"$WORK/ldtoy.c" &&
	toy_cc "$WORK/ldver" "$WORK/ldmain.c" -L"$WORK/ldv" -lselftesttoy \
		-Wl,-rpath,"$WORK/ldv" &&
	toy_cc "$WORK/ldv/libselftesttoy.so" -shared -fPIC -Wl,--version-script="$WORK/ldv/old.map" \
		"$WORK/ldtoy.c"
want_broken "diff_output: a program exec cannot start is refused" \
	'could not be started' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/noint" --expected "$WORK/exp.txt"
# The expected output here is empty, and so is the output of a program that
# never started: without the report this was a PASS.
want_broken "diff_output: a program its loader stops is refused, not PASS" \
	'error while loading shared libraries' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/ldmiss" --expected "$WORK/v_empty.txt"

# ---- THE RENDER PATHS, each a branch that would otherwise regress in silence
#
# The legend names only the marks some failing cell shows: an expectation with
# no final newline against no output shows no $ at all.
printf 'abc' > "$WORK/v_abc_nonl.txt"
want_broken_none "diff_output: no \$ in any cell, no \$ in the legend" 'where a line ended' -- \
	emit_run "$WORK/v_abc_nonl.txt" "$WORK/v_empty.txt" 0
want_out   "diff_output: a \$ that is shown is in the legend" 'In the table, $ is where a line ended' -- \
	emit_run "$WORK/v_7.txt" "$WORK/v_7sp.txt" 0
# A long row is cut to a window around its first difference.
_long_a=""; _i=0
while [ "$_i" -lt 150 ]; do _long_a="${_long_a}a"; _i=$((_i + 1)); done
printf '%sX%s\n' "$_long_a" "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" > "$WORK/v_longx.txt"
printf '%sY%s\n' "$_long_a" "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" > "$WORK/v_longy.txt"
want_out   "diff_output: a long row is windowed on its first difference" '...aaaaaaaaaaX' -- \
	env DIFF_CELL_MAX=40 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/emit" \
		--expected "$WORK/v_longx.txt" -- "$WORK/v_longy.txt" 0
want_out   "diff_output: ...and the legend says text was cut" 'text cut to fit' -- \
	env DIFF_CELL_MAX=40 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/emit" \
		--expected "$WORK/v_longx.txt" -- "$WORK/v_longy.txt" 0
# A label that differs shows the whole GOT line, label and tab included.
printf 'case 1\tv1\n' > "$WORK/v_lab.txt"; printf 'caseX 1\tv1\n' > "$WORK/v_labx.txt"
want_out   "diff_output: a wrong label shows the whole GOT line" 'caseX 1\tv1$' -- \
	emit_run "$WORK/v_lab.txt" "$WORK/v_labx.txt" 0 --labeled
# EVERY CELL through the one renderer, a passing one and a label too. A
# passing row printed its bytes raw: an escape sequence the program wrote
# reached the terminal, and a character of two bytes put the row out of line.
# A label that only the output has (a row past the expected ones) is the
# program's bytes; one of several bytes is as wide as its characters.
_esc=$(printf '\033')
printf '\033[31mred\n' > "$WORK/v_esc.txt"
want_out   "diff_output: a passing row shows an escape byte as \\xHH" '| \x1b[31mred |' -- \
	emit_run "$WORK/v_esc.txt" "$WORK/v_esc.txt" 0
want_broken_none "diff_output: ...and never raw" "$_esc" -- \
	emit_run "$WORK/v_esc.txt" "$WORK/v_esc.txt" 0
want_out   "diff_output: ...with the legend that reads it" 'In the table, \xHH any other byte' -- \
	emit_run "$WORK/v_esc.txt" "$WORK/v_esc.txt" 0
printf 'a\t1\n' > "$WORK/v_lab1.txt"; printf 'a\t1\n\033[2Jx\t9\n' > "$WORK/v_lab1x.txt"
want_out   "diff_output: a label only the output has is rendered" ' \x1b[2Jx | (no line)' -- \
	emit_run "$WORK/v_lab1.txt" "$WORK/v_lab1x.txt" 0 --labeled
want_broken_none "diff_output: ...never raw" "$_esc" -- \
	emit_run "$WORK/v_lab1.txt" "$WORK/v_lab1x.txt" 0 --labeled
printf 'caf\303\251\t1\nx\t2\n' > "$WORK/v_utf.txt"; printf 'caf\303\251\t1\nx\t3\n' > "$WORK/v_utfx.txt"
want_out   "diff_output: a label of several-byte characters is as wide as they are" ' CASE | EXPECTED' -- \
	emit_run "$WORK/v_utf.txt" "$WORK/v_utfx.txt" 0 --labeled
printf '%s\n' "$_long_a" > "$WORK/v_longpass.txt"
want_out   "diff_output: a long passing row is cut at its end" 'aaaaaaaaaa... |' -- \
	env DIFF_CELL_MAX=40 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/emit" \
		--expected "$WORK/v_longpass.txt" -- "$WORK/v_longpass.txt" 0
want_out   "diff_output: ...and the legend says so" 'where the rest of a passing value is left out' -- \
	env DIFF_CELL_MAX=40 "$SH" "$TOOLS/diff_output.sh" --bin "$WORK/emit" \
		--expected "$WORK/v_longpass.txt" -- "$WORK/v_longpass.txt" 0
# The binary summary's three shapes of difference.
printf '\001\002\003\004\005\006\007\016' > "$WORK/v_binpre.txt"
want_out   "diff_output: bytes: a short output is a prefix" 'the output stops after 8 of the 12 bytes' -- \
	emit_run "$WORK/v_bin.txt" "$WORK/v_binpre.txt" 0
want_out   "diff_output: bytes: no output is nothing" 'the program printed nothing' -- \
	emit_run "$WORK/v_bin.txt" "$WORK/v_empty.txt" 0
printf '\001\002\003\004\005\006\007\016\017\020A\n\001\002' > "$WORK/v_binmore.txt"
want_out   "diff_output: bytes: extra output is counted" 'then 2 more follow' -- \
	emit_run "$WORK/v_bin.txt" "$WORK/v_binmore.txt" 0

# A program that never built: red with the compiler's words, and no hints --
# the exercise's clues are about what the program prints, and there is no
# program. It used to print a table of "(no line)" under three of them, with the
# build failure last, cut to ten lines (findings 165, 173). The clues are this
# section's, beside the stand-ins rather than in their tree, which every
# section reads.
mkdir -p "$WORK/dosc"
printf 'a hint that fires on any failure\n' > "$WORK/dosc/clues.tsv"
want_red "diff_output: a stand-in is red, not a wrong output" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$STANDIN_BIN" --expected "$WORK/exp.txt"
want_out "diff_output: ...says the code did not build" "$STANDIN_SAYS" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$STANDIN_BIN" --expected "$WORK/exp.txt"
want_out "diff_output: ...in the compiler's words" "$STANDIN_FILE" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$STANDIN_BIN" --expected "$WORK/exp.txt"
want_out "diff_output: an EMPTY stand-in says there was nothing to build" \
	'nothing to build' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/standin/empty" --expected "$WORK/exp.txt"
want_broken_none "diff_output: ...and never blames the code" 'your code did not build' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/standin/empty" --expected "$WORK/exp.txt"
want_broken_none "diff_output: ...and shows no exercise hints" 'fires on any failure' -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$STANDIN_BIN" --expected "$WORK/exp.txt" \
		--clues "$WORK/dosc/clues.tsv"

# 4. ONE reading rule, in tools/runner_lib.sh (rl_clues), for every runner that
#    prints a clues.tsv -- the maintainer's '#' lines stay out of the HINTS
#    block and only the hint column is shown. rush01_check.sh printed both,
#    twenty lines deep (finding 149); its arm is with its own, below.
printf '# a note for maintainers\nkeyed-a\tline 2\tline 9\n' > "$WORK/clue_comment.tsv"
want_broken_none "diff_output: a '#' line of clues.tsv is never a hint" \
	'a note for maintainers' -- hint_run "$WORK/clue_comment.tsv"
want_broken_none "diff_output: ...nor is a row's member label" \
	'line 9' -- hint_run "$WORK/clue_comment.tsv"
# A test that is a case of its own (--case) shows the rows keyed to it and
# the rows keyed to nothing, with or without a file of failed labels: a
# corpus runner has none to write, and one program's clues.tsv holds the rows
# of all its cases (ruling R7). Without a CASE every row fires, as before.
printf 'Which sweep row?\tsweep\nWhich other case?\tnoarg\nWhich row for all?\n' \
	> "$WORK/clue_keyed.tsv"
rl_clue_run() { "$SH" -c '. "$1"; rl_clues "$2" "" "" "$3"' _ "$TOOLS/runner_lib.sh" "$WORK/clue_keyed.tsv" "$1"; }
want_out "rl_clues: a CASE alone fires its own rows" 'Which sweep row?' -- rl_clue_run sweep
want_out "rl_clues: ...and the rows keyed to nothing" 'Which row for all?' -- rl_clue_run sweep
want_broken_none "rl_clues: ...never another case's" 'Which other case?' -- rl_clue_run sweep
want_out "rl_clues: with no CASE every row fires" 'Which other case?' -- rl_clue_run ""
# CLUE_MODE (V101): 0 shows every hint, as DIFF_MAX_ROWS's 0 shows every
# row, and a value it cannot read says so in the HINTS block rather than
# quietly showing three. The value reaches awk through the environment, so
# a backslash in it is never read as an escape.
printf 'hint one\nhint two\nhint three\nhint four\nhint five\n' > "$WORK/clue_five.tsv"
rl_clue_mode() { env CLUE_MODE="$1" "$SH" -c '. "$1"; rl_clues "$2"' _ "$TOOLS/runner_lib.sh" "$WORK/clue_five.tsv"; }
want_out "rl_clues: CLUE_MODE=0 shows every hint" 'hint five' -- rl_clue_mode 0
want_broken_none "rl_clues: ...and counts none as hidden" 'more --' -- rl_clue_mode 0
want_out "rl_clues: CLUE_MODE=2 shows two" '(3 more -- CLUE_MODE=all shows every one)' -- rl_clue_mode 2
want_out "rl_clues: a CLUE_MODE it cannot read is said to be" 'CLUE_MODE is not understood' -- rl_clue_mode al
want_out "rl_clues: ...and the first three still show" 'hint three' -- rl_clue_mode al
want_broken_none "rl_clues: ...never more" 'hint four' -- rl_clue_mode al
want_out "rl_clues: ...a negative number too" 'CLUE_MODE is not understood' -- rl_clue_mode -1
want_out "rl_clues: ...and a backslash, read as itself" 'CLUE_MODE is not understood' -- rl_clue_mode '\\'
want_broken_none "rl_clues: an unset CLUE_MODE says nothing of it" 'not understood' -- rl_clue_mode ''
# A LAYER that is not the output test (V55): valgrind_test.sh's red printed
# every row of the exercise's file as its own, three output hints over a
# leak. Its own rows (keyed to it) come first, under HINTS; the rows keyed to
# nothing after them, under a heading saying they were written for the
# output test; a row keyed to one of the output's cases not at all.
printf 'Which output case?\tnoarg\nWhich row for all?\nWhich memory row?\tvalgrind\n' \
	> "$WORK/clue_layer.tsv"
printf 'valgrind\n' > "$WORK/clue_layer.failed"
rl_clue_layer() {
	"$SH" -c '. "$1"; rl_clues "$2" "$3" "" "" valgrind' _ "$TOOLS/runner_lib.sh" \
		"$WORK/clue_layer.tsv" "$WORK/clue_layer.failed"
}
# The order and the headings, exactly: the memory row first, under HINTS.
rl_clue_layer_order() {
	rl_clue_layer > "$WORK/clue_layer.out" 2>&1 || return 2
	_lo=$(grep -n -e '^ HINTS' -e '^   \* ' "$WORK/clue_layer.out" | cut -d: -f2- | tr '\n' '|')
	_lw=' HINTS:|   * Which memory row?| HINTS (from this exercise, written for its output test rather than this one):|   * Which row for all?|'
	[ "$_lo" = "$_lw" ] && return 0
	echo "shown: $_lo"
	return 1
}
want_green "rl_clues: a LAYER shows its own rows first, then the output's, said so" -- \
	rl_clue_layer_order
want_broken_none "rl_clues: ...and no row keyed to an output case" 'Which output case?' -- \
	rl_clue_layer
# with_kind KIND CMD... (tools/tests/selftest_lib.sh): CMD under
# RL_UNIT_KIND=KIND, in a subshell.
want_out "HINTS: ...a library's heading names the library" \
	' HINTS (from this library, written for its output test rather than this one):' -- \
	with_kind library rl_clue_layer

# A test _RAISED lists sits above its layer's level, and its red says why,
# from the row docs/reference.md's table has for it (rl__raised): only on a
# red, only where _test() handed it RL_RAISED, and once where one runner
# starts another (header_check.sh's diff_output.sh). A test the table has no
# row for still says its level.
mkdir -p "$WORK/rf/_main/docs"
printf '## Targets raised above their layer\n\n| target | level | why |\n|---|---|---|\n| `//c-piscine/c-piscine-c-99:ex00_toy_output` | strict | a reading | of an open sentence, kept |\n\n## Next\n' \
	> "$WORK/rf/_main/docs/reference.md"
printf 'alpha\nWRONG\n' > "$WORK/raised_got.txt"
raised_run() {  # raised_run TARGET EXPECTED [RL_RAISED]
	env TEST_SRCDIR="$WORK/rf" TEST_WORKSPACE=_main TEST_TARGET="$1" RL_RAISED="${3:-}" \
		"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/hbad" --expected "$2"
}
want_out "rl__raised: a raised red says why it sits there" 'a reading | of an open sentence, kept' -- \
	raised_run //c-piscine/c-piscine-c-99:ex00_toy_output "$WORK/hexp.txt" strict
want_out "rl__raised: ...and at which level" 'WHY THIS TEST IS AT strict' -- \
	raised_run //c-piscine/c-piscine-c-99:ex00_toy_output "$WORK/hexp.txt" strict
want_broken_none "rl__raised: ...a green says nothing" 'WHY THIS TEST' -- \
	raised_run //c-piscine/c-piscine-c-99:ex00_toy_output "$WORK/raised_got.txt" strict
want_broken_none "rl__raised: ...nor a red that is not raised" 'WHY THIS TEST' -- \
	raised_run //c-piscine/c-piscine-c-99:ex00_toy_output "$WORK/hexp.txt"
want_out "rl__raised: a raised test with no row still says its level" 'WHY THIS TEST IS AT robust' -- \
	raised_run //c-piscine/c-piscine-c-99:ex01_toy_output "$WORK/hexp.txt" robust
printf '#!/bin/sh\n. "$1"\nshift\n"$SH" "$@"\n' > "$WORK/raised_outer.sh"
raised_nested() {
	env SH="$SH" TEST_SRCDIR="$WORK/rf" TEST_WORKSPACE=_main RL_RAISED=strict \
		TEST_TARGET=//c-piscine/c-piscine-c-99:ex00_toy_output "$SH" "$WORK/raised_outer.sh" \
		"$TOOLS/runner_lib.sh" "$TOOLS/diff_output.sh" --bin "$WORK/hbad" --expected "$WORK/hexp.txt" |
		grep -c 'WHY THIS TEST IS AT'
}
raised_once() { [ "$(raised_nested)" = 1 ]; }
want_green "rl__raised: a runner that starts another says it once" -- raised_once

# ---- what a runner cuts, it says it cut ---------------------------------------
# The other stream was cut to twenty lines with a bare head, and nothing said so
# (finding 165): a crash's explanation lost its last lines and nobody could
# tell. rl_excerpt shows N lines, counts the rest and keeps the whole text in the
# test's undeclared outputs, which is where Bazel keeps test.outputs/.
printf '#include <stdio.h>\nint main(void){int i;printf("hello\\n");fflush(stdout);for(i=1;i<=30;i++)fprintf(stderr,"diag %%d\\n",i);*(volatile int*)0=1;return 0;}\n' \
	> "$WORK/chatty_crash.c"
toy_cc "$WORK/chatty_crash" "$WORK/chatty_crash.c"
mkdir -p "$WORK/undeclared"
want_out "diff_output: a cut excerpt says how much it left out" \
	'10 more line(s), full text in' -- \
	env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/undeclared" "$SH" "$TOOLS/diff_output.sh" \
		--bin "$WORK/chatty_crash" --expected "$WORK/exp.txt"
want_green "diff_output: ...and the full text is kept" -- \
	grep -q 'diag 30' "$WORK/undeclared/other-stream.txt"
# The NAME is what the kept file is called: an empty one copied it into the
# folder under its scratch name, and the log named the folder (V18).
awk 'BEGIN { for (i = 1; i <= 30; i++) print "line " i }' > "$WORK/rl_long.txt"
want_broken "rl_excerpt: an empty NAME is a wiring mistake" 'no name to keep' -- \
	env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/undeclared" "$SH" -c '. "$1"; rl_excerpt "$2" 5 "" ""' \
	_ "$TOOLS/runner_lib.sh" "$WORK/rl_long.txt"
# --tail: the output of a run that stops where it went wrong keeps its last
# lines too, after the line that says what was left out of the middle.
rl_tail() {  # rl_tail N T: rl_long.txt cut by rl_excerpt --tail T at N, on one line, | for a newline
	printf '|'
	env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/undeclared" "$SH" -c \
		'. "$1"; rl_excerpt --tail "$4" "$2" "$3" tail.txt ""; echo "left out: $RL_LEFT_OUT"' \
		_ "$TOOLS/runner_lib.sh" "$WORK/rl_long.txt" "$1" "$2" | tr '\n' '|'
}
want_out "rl_excerpt --tail: the middle is what is left out" \
	'|line 5|... 22 more line(s), full text in ' -- rl_tail 5 3
want_out "rl_excerpt --tail: ...and the last lines follow" \
	'/tail.txt; the last 3 line(s):|line 28|line 29|line 30|left out: 22|' -- rl_tail 5 3
want_out "rl_excerpt --tail: a file no longer than both is shown whole" \
	'|line 29|line 30|left out: 0|' -- rl_tail 20 10
# A memory report that names the scratch file a runner handed the program
# (memcheck's open descriptors) named a file gone with the test, under lines
# that keep the input by another name. rl_mem_report --as SCRATCH KEPT shows
# the kept name, literally (a path holds dots: "s.p" must not match "sXp"),
# the longer of two scratch paths where one starts the other, and says once
# that it did. An invented report.
printf '%s\n' '==1== Open file descriptor 4: /w/s.p/map.10' \
	'==1== Open file descriptor 3: /w/s.p/map.1' '==1== at /w/sXp/map.1' > "$WORK/rl_as.txt"
rl_as_of() {  # rl_as_of [--as SCRATCH KEPT]...: rl_mem_report over the report above
	# A copy: RL_MEM_OUT is runner_lib.sh's scratch file, removed at its exit.
	cp "$WORK/rl_as.txt" "$WORK/rl_as.out"
	"$SH" -c '. "$1"; shift; RL_MEM=valgrind RL_MEM_KIND=memcheck RL_MEM_RAN=1
		RL_MEM_OUT=$1; shift; rl_mem_report "$@"' _ "$TOOLS/runner_lib.sh" "$WORK/rl_as.out" "$@"
}
want_out "rl_mem_report --as: a scratch path reads as the kept name" \
	'descriptor 3: run-1-1.map' -- rl_as_of --as /w/s.p/map.1 run-1-1.map --as /w/s.p/map.10 run-1-10.map
want_out "rl_mem_report --as: ...the longer where one starts another" \
	'descriptor 4: run-1-10.map' -- rl_as_of --as /w/s.p/map.1 run-1-1.map --as /w/s.p/map.10 run-1-10.map
want_out "rl_mem_report --as: ...a dot matching only a dot" 'at /w/sXp/map.1' -- \
	rl_as_of --as /w/s.p/map.1 run-1-1.map
want_out "rl_mem_report --as: ...saying once which names it showed" \
	'shown by the name it is kept under: run-1-1.map, run-1-10.map)' -- \
	rl_as_of --as /w/s.p/map.1 run-1-1.map --as /w/s.p/map.10 run-1-10.map
want_broken_none "rl_mem_report --as: ...and nothing when it named none" 'kept under' -- \
	rl_as_of --as /w/other run-1.map
want_broken_none "rl_mem_report: ...nor without --as" 'kept under' -- rl_as_of
# rl_keep_input SCRATCH NAME keeps an input and records the pair, which the
# next rl_mem_report shows by its kept name with no --as: three runners kept
# lists of what rl_save had kept to rebuild the pairs from (V147). Forgotten
# once shown, and at the start of each rl_mem_run, so a scratch path a runner
# reuses for every case (BSQ's map) never names an earlier case's file; and
# never recorded where nothing could be kept. The run is stubbed: only the
# bookkeeping is under test. An invented report naming a real scratch file.
mkdir -p "$WORK/rl_ki/s.p" "$WORK/rl_ki/out"
printf 'a map\n' > "$WORK/rl_ki/s.p/map"
printf '==1== Open file descriptor 3: %s\n' "$WORK/rl_ki/s.p/map" > "$WORK/rl_ki.txt"
rl_ki_of() {  # rl_ki_of STEP...: keep, report, run, nokeep, refill, in that order given
	cp "$WORK/rl_ki.txt" "$WORK/rl_ki.out"
	env -u TEST_UNDECLARED_OUTPUTS_DIR "$SH" -c '. "$1"; _k=$2; _d=$3; _r=$4; shift 4
		RL_MEM=valgrind RL_MEM_KIND=memcheck RL_MEM_RAN=1 RL_MEM_OUT=$_r
		RL_MEM_STDOUT=$_d/stdout
		rl_run() { :; }
		rl_sweep_ran() { RL_CAUSE=""; }
		for _s in "$@"; do
			case $_s in
				keep) TEST_UNDECLARED_OUTPUTS_DIR=$_d rl_keep_input "$_k" case-1.map || echo "keep: false" ;;
				nokeep) rl_keep_input "$_k" case-2.map || echo "nokeep: false" ;;
				report) echo "-- report"; rl_mem_report ;;
				run) RL_MEM=sanitized rl_mem_run -- "$_k"; RL_MEM=valgrind; RL_MEM_KIND=memcheck ;;
				refill) cat "$_r.orig" > "$_r" ;;
			esac
		done' _ "$TOOLS/runner_lib.sh" "$WORK/rl_ki/s.p/map" "$WORK/rl_ki/out" "$WORK/rl_ki.out" "$@"
}
cp "$WORK/rl_ki.txt" "$WORK/rl_ki.out.orig"
# The last report's lines alone.
rl_ki_last() { rl_ki_of "$@" | awk '/^-- report$/ { o = "" } { o = o $0 "\n" } END { printf "%s", o }'; }
want_out "rl_keep_input: a bare rl_mem_report shows the input by its kept name" \
	'descriptor 3: case-1.map' -- rl_ki_of keep report
want_out "rl_keep_input: ...saying so once" \
	'shown by the name it is kept under: case-1.map)' -- rl_ki_of keep report
want_broken_none "rl_keep_input: ...forgotten once shown" 'case-1.map' -- \
	rl_ki_last keep report report
want_broken_none "rl_keep_input: ...and at the start of the next case's run" 'case-1.map' -- \
	rl_ki_last keep run refill report
want_out "rl_keep_input: ...false where nothing could be kept" 'nokeep: false' -- \
	rl_ki_of nokeep report
want_broken_none "rl_keep_input: ...which records nothing" 'kept under' -- \
	rl_ki_of nokeep report

# ---- a signal ENDS the runner -------------------------------------------------
# Bazel stops a test that runs out of time with SIGTERM. Every runner's trap
# used to clean up and RESUME, so it went on without its scratch files.
printf '#!/bin/sh\nsleep 3\nprintf "hello\\n"\n' > "$WORK/sleepy.sh"
chmod +x "$WORK/sleepy.sh"
later_term "diff_output: SIGTERM ends it, cleaned up, with 143" -- \
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/sleepy.sh" --expected "$WORK/exp.txt"
# ...and one that lands while rl_mem_report --as writes its report, which is
# a copy of RL_MEM_OUT under the kept names ("$RL_MEM_OUT.as") and, for a
# sanitizer's, that copy less its shadow map (".as.shown"): the library's
# EXIT trap removed RL_MEM_OUT and its ".shown" and left both. Without a
# wait: the excerpt, the last step, sends the signal itself, once both files
# are written. The report and the path are invented.
rl_term_in_report() {
	rm -rf "$WORK/rl_tir"
	mkdir -p "$WORK/rl_tir"
	TMPDIR="$WORK/rl_tir" "$SH" -c '. "$1"
		RL_MEM=sanitized RL_MEM_KIND=sanitizer RL_MEM_RAN=1
		RL_MEM_OUT=$(mktemp) || exit 2
		printf "==1==ERROR: AddressSanitizer: heap-buffer-overflow reading %s\n" "$2" > "$RL_MEM_OUT"
		rl_excerpt() { kill -TERM $$; }
		rl_mem_report --as "$2" case-1.map' _ "$TOOLS/runner_lib.sh" /w/s.p/map > /dev/null 2>&1
	_tir_rc=$?
	_tir_left=$(find "$WORK/rl_tir" -mindepth 1 | sed 's|.*/||' | sort | tr '\n' ' ')
	printf 'exit %s, left: %s\n' "$_tir_rc" "${_tir_left:-nothing}"
}
want_out "rl_mem_report: a SIGTERM while it writes ends it, cleaned up" \
	'exit 143, left: nothing' -- rl_term_in_report
# The report a case's block shows is kept under that case's name (--what),
# not under how many cases the checker ran: a memcheck sample shows "case
# 24" as its third run, and kept memory-case-3.txt, a case not on screen.
# The run, the excerpt and the sanitizer's report are stand-ins that print
# the name they were given.
rl_mem_saved_as() {  # rl_mem_saved_as [--what TEXT]: the names the report is kept under
	"$SH" -c '. "$1"; shift
		RL_MEM=sanitized RL_MEM_RAN=2
		RL_MEM_OUT=$(mktemp) || exit 2
		RL_MEM_STDOUT=$(mktemp) || exit 2
		rl_run() { echo "==1==ERROR: AddressSanitizer: invented" >&2; return 1; }
		rl_sweep_ran() { RL_CAUSE=""; }
		rl_sanitizer_kind() { :; }
		rl_sanitizer_about() { :; }
		rl_sanitizer_report() { echo "kept as $3"; }
		rl_mem_run "$@" -- x
		rl_mem_report' _ "$TOOLS/runner_lib.sh" "$@"
}
want_out "rl_mem_run: a case's report is kept under the name its block shows" \
	'kept as memory-case-24.txt' -- rl_mem_saved_as --what "case 24"
want_out "rl_mem_run: ...a probe's under its own" \
	'kept as memory-probe-3-of-9.txt' -- rl_mem_saved_as --what "probe 3 of 9"
want_out "rl_mem_run: ...and, with no --what, under the run's count" \
	'kept as memory-case-3.txt' -- rl_mem_saved_as
# ...and one that lands while rl_udiff diffs: its scratch file, the unified
# diff it reads back, was the one library file the EXIT trap did not list.
# The differ is a function that sends the signal itself, then prints an
# invented diff of the two files.
rl_term_in_udiff() {
	rm -rf "$WORK/rl_tud"
	mkdir -p "$WORK/rl_tud"
	TMPDIR="$WORK/rl_tud" "$SH" -c '. "$1"
		DIFF() { kill -TERM $$; printf "%s\n" "--- want" "+++ got" "@@ -1 +1 @@" -a +b; return 1; }
		rl_udiff DIFF /w/want /w/got' _ "$TOOLS/runner_lib.sh" > /dev/null 2>&1
	_tud_rc=$?
	_tud_left=$(find "$WORK/rl_tud" -mindepth 1 | sed 's|.*/||' | sort | tr '\n' ' ')
	printf 'exit %s, left: %s\n' "$_tud_rc" "${_tud_left:-nothing}"
}
want_out "rl_udiff: a SIGTERM while it diffs ends it, cleaned up" \
	'exit 143, left: nothing' -- rl_term_in_udiff

