# ------------------------------------------------------------------- run_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
printf '#include <stdio.h>\nint main(void){printf("some output\\n");return (0);}\n' \
	> "$WORK/rc_ok.c"
printf '#include <stdio.h>\nint main(void){printf("x\\n");return (4);}\n' > "$WORK/rc_exit.c"
# `return (-1);` is the status 255, the number a death by "signal 127" gives the
# shell. How the run ended is read from waitpid() (tools/exit_status), so it
# is a return: noted at basic, never a crash.
printf '#include <stdio.h>\nint main(void){printf("x\\n");return (-1);}\n' > "$WORK/rc_m1.c"
printf 'int main(void){for(;;);}\n' > "$WORK/rc_hang.c"
for _p in rc_ok rc_exit rc_hang rc_m1; do
	toy_cc "$WORK/$_p" -w "$WORK/$_p.c"
done
want_green "run_check: a program that runs and exits 0 passes" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 1
# THE EXIT STATUS, by the Run contract (docs/reference.md): --exit is a status
# the subject names, and fails at every level; with none named, --note-exit
# only notes a plain non-zero return, and its robust twin fails it with
# --exit-only. Rush 00's own main.c is the caller, and its subject names none.
want_red   "run_check: the wrong exit status fails" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_exit" --exit 0
want_green "run_check: --note-exit only notes it" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_exit" --note-exit 0
want_out   "run_check: ...and says so" 'from your subject names an exit' -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_exit" --note-exit 0
want_red   "run_check: --exit-only is the robust twin that fails it" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_exit" --exit 0 --exit-only
want_green "run_check: --exit-only does not judge the output" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --exit 0 --exit-only --min-bytes 10000
want_broken "run_check: --exit-only with no --exit refuses" 'needs --exit' -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --exit-only
want_red   "run_check: too little output fails" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 10000
want_red   "run_check: an infinite loop is stopped and failed" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_hang" --timeout 2
want_green "run_check: a return of 255 is noted, not failed, at basic" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_m1" --note-exit 0
want_broken_none "run_check: ...and is never called a crash" 'crash' -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_m1" --note-exit 0
# Where a failed status came from is the caller's to say (--exit-source, as
# in diff_output.sh): --exit-only printed that its subject names no exit
# status under every status, a subject-named one included.
want_broken_none "run_check: a status the subject names is never 'names none'" \
	'from your subject names an exit' -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_exit" --exit 0 --exit-only
want_out   "run_check: ...it says the subject names it" 'The subject names this status' -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_exit" --exit 0 --exit-only
want_out   "run_check: --exit-source convention says it is the convention" \
	'from your subject names an exit' -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_exit" --exit 0 --exit-only --exit-source convention
want_broken "run_check: --exit-source takes subject or convention" 'must be subject or convention' -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_exit" --exit 0 --exit-source rule
# Captured stdout is an excerpt that says what it left out (rl_excerpt): it
# was the first 400 bytes, raw, with nothing said about the rest.
printf '#include <stdio.h>\nint main(void){for(int i=0;i<30;i++)printf("line %%d\\n",i);return 0;}\n' \
	> "$WORK/rc_lines.c"
toy_cc "$WORK/rc_lines" -w "$WORK/rc_lines.c"
want_out   "run_check: a failing run's stdout says how much is not shown" '... 10 more line(s)' -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_lines" --min-bytes 100000

want_red   "run_check: a stand-in is red" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$STANDIN_BIN" --min-bytes 1
want_out   "run_check: ...says the code did not build" "$STANDIN_SAYS" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$STANDIN_BIN" --min-bytes 1

# THE GATE (--gate-*, runner_lib.sh's rl_gate): a run that waits for an
# output test SKIPs while that test's fixture is red. Rush 00's own main.c
# waits so for its variant's labelled table: it links the same rush(), and a
# stub there prints nothing here either. rc_ok passes rc_gate_ok.txt and
# fails rc_gate_no.txt; the run under test asks for more than rc_ok prints,
# so it is red whenever it runs. rc_cat prints its stdin: its gate is green
# only when --gate-stdin reaches it.
printf 'some output\n' > "$WORK/rc_gate_ok.txt"
printf 'other output\n' > "$WORK/rc_gate_no.txt"
printf '#!/bin/sh\ncat\n' > "$WORK/rc_cat"
chmod +x "$WORK/rc_cat"
rc_gated() {  # rc_gated EXPECTED [ARG...] -- the run under test, its gate rc_ok against $WORK/EXPECTED
	_rcg=$1
	shift
	env -u NO_SKIP "$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 100000 \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/rc_ok" --gate-expected "$WORK/$_rcg" "$@"
}
want_green "run_check: SKIPs while its output is red" -- once rc_gated rc_gate_no.txt
want_out   "run_check: ...saying so" 'SKIP' -- once rc_gated rc_gate_no.txt
want_out   "run_check: ...in its own words" 'prints something and ends' -- once rc_gated rc_gate_no.txt
want_broken_none "run_check: ...never the corpus layers'" 'replays a generated corpus' -- once rc_gated rc_gate_no.txt
want_red   "run_check: ...and runs once that output is green" -- rc_gated rc_gate_ok.txt
want_red   "run_check: ...or when NO_SKIP=1 forces it open" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 100000 \
	--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/rc_ok" --gate-expected "$WORK/rc_gate_no.txt"
want_red   "run_check: ...handing the gate its stdin" -- \
	env -u NO_SKIP "$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 100000 \
	--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/rc_cat" --gate-expected "$WORK/rc_gate_ok.txt" \
	--gate-stdin "$WORK/rc_gate_ok.txt"
# --gate-label names the output test it waits for, in the SKIP line alone:
# the paragraph under it stays this runner's, never a survive case's.
want_out   "run_check: ...naming the test it waits for" \
	"SKIP — ex00_one_output, this exercise's own output fixture, is not passing yet" -- \
	once rc_gated rc_gate_no.txt --gate-label ex00_one_output
want_out   "run_check: ...under its own words" 'prints something and ends' -- \
	once rc_gated rc_gate_no.txt --gate-label ex00_one_output
want_broken_none "run_check: ...never a survive case's" 'ends by itself' -- \
	once rc_gated rc_gate_no.txt --gate-label ex00_one_output
# A gate is --gate-differ, --gate-bin and --gate-expected together. Any
# --gate-* without all three is a wiring mistake, refused as diff_output.sh
# refuses its own: rl_gate fails open on a missing piece, so the run would
# go on as if no gate had been asked for, and its SKIP line never come.
want_broken "run_check: --gate-label with no gate refuses" 'a gate needs' -- \
	env -u NO_SKIP "$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 100000 \
	--gate-label ex00_one_output
want_broken "run_check: ...as does a gate with no --gate-differ" 'a gate needs' -- \
	env -u NO_SKIP "$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 100000 \
	--gate-bin "$WORK/rc_ok" --gate-expected "$WORK/rc_gate_no.txt" --gate-label ex00_one_output
want_broken "run_check: ...or with no --gate-expected" 'a gate needs' -- \
	env -u NO_SKIP "$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 100000 \
	--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/rc_ok" --gate-label ex00_one_output
want_broken "run_check: ...or with no --gate-bin" 'a gate needs' -- \
	env -u NO_SKIP "$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 100000 \
	--gate-differ "$TOOLS/diff_output.sh" --gate-expected "$WORK/rc_gate_no.txt" --gate-stdin "$WORK/rc_gate_ok.txt"
# A main.c that did not build is red whatever the gate says: the program it
# waits for is built without it, so its red names nothing of main.c.
want_red   "run_check: a stand-in is red while its gate is red" -- \
	env -u NO_SKIP "$SH" "$TOOLS/run_check.sh" --bin "$STANDIN_BIN" --min-bytes 1 \
	--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/rc_ok" --gate-expected "$WORK/rc_gate_no.txt"
# EVERY RUNNER THAT TAKES A GATE refuses one given in part, as run_check.sh
# does above: each fails open on a missing piece, so an option describing a
# gate that is not there was dropped in silence and the run went on ungated.
# A survive case's valgrind arm and allocation-failure sweep were handed
# --gate-stdin with no gate at all (tools/defs_checks.bzl), and asan_run.sh, given
# only --gate-label, said OK and nothing else. (perf_test.sh's are in
# selftest_slow.sh, beside its other arms.)
GATE_D="$TOOLS/diff_output.sh"
want_broken "gates: valgrind_test refuses --gate-stdin with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/rc_ok" --gate-stdin "$WORK/rc_gate_ok.txt"
want_broken "gates: ...valgrind_test, a gate with no --gate-differ" 'a gate needs' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/rc_ok" --gate-bin "$WORK/rc_ok" \
	--gate-expected "$WORK/rc_gate_no.txt"
want_broken "gates: ...valgrind_test, a gate with no --gate-expected" 'a gate needs' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/rc_ok" --gate-differ "$GATE_D" \
	--gate-bin "$WORK/rc_ok" --gate-labeled
want_broken "gates: ...valgrind_test, a gate with no --gate-bin" 'a gate needs' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/rc_ok" --gate-differ "$GATE_D" \
	--gate-expected "$WORK/rc_gate_no.txt" --gate-sanitize
want_broken "gates: ...valgrind_test, --gate-expected-alt alone" 'a gate needs' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/rc_ok" --gate-expected-alt "$WORK/rc_gate_no.txt"
want_broken "gates: allocfail_check refuses --gate-stream with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/rc_ok" --gate-stream stdout
want_broken "gates: ...allocfail_check, a gate with no --gate-differ" 'a gate needs' -- \
	"$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/rc_ok" --gate-bin "$WORK/rc_ok" \
	--gate-expected "$WORK/rc_gate_no.txt"
want_broken "gates: asan_run refuses --gate-label with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/rc_ok" --gate-label ex00_one_output
want_broken "gates: ...asan_run, a gate with no --gate-expected" 'a gate needs' -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/rc_ok" --gate-differ "$GATE_D" \
	--gate-bin "$WORK/rc_ok" --gate-arg one
want_broken "gates: bsq_check refuses --gate-arg with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/bsq_check.sh" --bin "$WORK/rc_ok" --gate-arg one
want_broken "gates: ...bsq_check, a gate with no --gate-differ" 'a gate needs' -- \
	"$SH" "$TOOLS/bsq_check.sh" --bin "$WORK/rc_ok" --gate-bin "$WORK/rc_ok" \
	--gate-expected "$WORK/rc_gate_no.txt"
want_broken "gates: cycles_check refuses --gate-labeled with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/cycles_check.sh" --bin "$WORK/rc_ok" --gate-labeled
want_broken "gates: ...cycles_check, a gate with no --gate-differ" 'a gate needs' -- \
	"$SH" "$TOOLS/cycles_check.sh" --bin "$WORK/rc_ok" --gate-bin "$WORK/rc_ok" \
	--gate-expected "$WORK/rc_gate_no.txt"
want_broken "gates: method_check refuses --gate-sanitize with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/method_check.sh" --gate-sanitize
want_broken "gates: ...method_check, a gate with no --gate-expected" 'a gate needs' -- \
	"$SH" "$TOOLS/method_check.sh" --gate-differ "$GATE_D" --gate-bin "$WORK/rc_ok"
want_broken "gates: ref_compare refuses --gate-labeled with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/ref_compare.sh" --gate-labeled
want_broken "gates: ...ref_compare, a gate with no --gate-bin" 'a gate needs' -- \
	"$SH" "$TOOLS/ref_compare.sh" --gate-differ "$GATE_D" --gate-expected "$WORK/rc_gate_no.txt"
want_broken "gates: rush01_check refuses a gate with no --gate-differ" 'a gate needs' -- \
	"$SH" "$TOOLS/rush01_check.sh" --bin "$WORK/rc_ok" --gate-bin "$WORK/rc_ok" \
	--gate-expected "$WORK/rc_gate_no.txt"
want_broken "gates: ...rush01_check, --gate-label with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/rush01_check.sh" --bin "$WORK/rc_ok" --gate-label ex00_one_output
want_broken "gates: rush02_check refuses --gate-number with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/rc_ok" --gate-number 42
want_broken "gates: ...rush02_check, a gate with no --gate-differ" 'a gate needs' -- \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/rc_ok" --gate-bin "$WORK/rc_ok" \
	--gate-expected "$WORK/rc_gate_no.txt" --gate-number 42
want_broken "gates: rust_diff refuses --gate-stdin with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/rust_diff.sh" --gate-stdin "$WORK/rc_gate_ok.txt"
want_broken "gates: ...rust_diff, a gate with no --gate-expected" 'a gate needs' -- \
	"$SH" "$TOOLS/rust_diff.sh" --gate-differ "$GATE_D" --gate-bin "$WORK/rc_ok"
want_broken "gates: ...rust_diff, --gate-label with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/rust_diff.sh" --gate-label ex00_one_output
want_broken "gates: ...ref_compare, --gate-label with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/ref_compare.sh" --gate-label ex00_one_output
want_broken "gates: ...allocfail_check, --gate-label with no gate" 'a gate needs' -- \
	"$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/rc_ok" --gate-label ex00_one_output
# EVERY RUNNER THAT TAKES A GATE NAMES THE TEST IT WAITS FOR in its SKIP
# line, given --gate-label (V169): rust_diff, ref_compare, allocfail_check
# and perf_test (selftest_slow.sh) took none, and said "this exercise's own
# output fixture" on every exercise, a test a newcomer had to guess. The
# first two say it in rl_gate's words now, as every runner's gate does
# (tools/runner_lib.sh): ref_compare's lacked the "own".
# rc_ok does not print what rc_gate_no.txt holds, so the gate against it is red.
want_out   "gates: rust_diff's SKIP names the test it waits for" \
	"rust_diff: SKIP — ex00_one_output, this exercise's own output fixture, is not passing yet" -- \
	env -u NO_SKIP "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/no-such-oracle" --oracle-fn f \
	--student-bin "$WORK/rc_ok" --gate-differ "$GATE_D" --gate-bin "$WORK/rc_ok" \
	--gate-expected "$WORK/rc_gate_no.txt" --gate-label ex00_one_output
want_out   "gates: ...ref_compare's too" \
	"ref_compare: SKIP — ex00_one_output, this exercise's own output fixture, is not passing yet" -- \
	env -u NO_SKIP "$SH" "$TOOLS/ref_compare.sh" --harness "$WORK/no-such-harness.c" \
	--src "$WORK/no-such-src.c" --oracle "$WORK/no-such-oracle" --oracle-fn f --symbol s \
	--units 1 --unit-name u --gate-differ "$GATE_D" --gate-bin "$WORK/rc_ok" \
	--gate-expected "$WORK/rc_gate_no.txt" --gate-label ex00_one_output
want_out   "gates: ...allocfail_check's too" \
	"allocfail_check: SKIP — ex00_one_output, this exercise's own output fixture, is not passing yet" -- \
	env -u NO_SKIP "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/rc_ok" --gate-differ "$GATE_D" \
	--gate-bin "$WORK/rc_ok" --gate-expected "$WORK/rc_gate_no.txt" --gate-label ex00_one_output
# The gate's words name what is tested by its kind (RL_UNIT_KIND).
want_out   "gates: ...allocfail_check's names a library" \
	"allocfail_check: SKIP — ex00_one_output, this library's own output fixture, is not passing yet" -- \
	env -u NO_SKIP RL_UNIT_KIND=library "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/rc_ok" \
	--gate-differ "$GATE_D" --gate-bin "$WORK/rc_ok" --gate-expected "$WORK/rc_gate_no.txt" \
	--gate-label ex00_one_output
# ...and without one, the line each printed before.
want_out   "gates: ...rust_diff's without one names none" \
	"rust_diff: SKIP — this exercise's own output fixture is not passing yet" -- \
	env -u NO_SKIP "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/no-such-oracle" --oracle-fn f \
	--student-bin "$WORK/rc_ok" --gate-differ "$GATE_D" --gate-bin "$WORK/rc_ok" \
	--gate-expected "$WORK/rc_gate_no.txt"
want_out   "gates: ...rust_diff's names a function" \
	"rust_diff: SKIP — this function's own output fixture is not passing yet" -- \
	env -u NO_SKIP RL_UNIT_KIND=function "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/no-such-oracle" \
	--oracle-fn f --student-bin "$WORK/rc_ok" --gate-differ "$GATE_D" --gate-bin "$WORK/rc_ok" \
	--gate-expected "$WORK/rc_gate_no.txt"
# A GATE THAT CANNOT RUN IS SAID, whichever piece is missing (V292): its
# program not there, or its expected file. Each runner tested both itself
# first and, failing, dropped the gate with nothing said, so a layer whose
# gate was wired to nothing ran ungated in silence. The differ exits 2 for
# both, which the "could not be evaluated" line already reported. rust_diff's
# run then goes on to its empty corpus, a harness error of its own (exit 2:
# runner_lib.sh, A CORPUS TOO SMALL TO PROVE ANYTHING).
printf '#!/bin/sh\nexit 0\n' > "$WORK/gate_empty_oracle.sh"
chmod +x "$WORK/gate_empty_oracle.sh"
want_out   "gates: rl_gate, a gate program that is not there is said" \
	'could not be evaluated' -- \
	env -u NO_SKIP "$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 1 \
	--gate-differ "$GATE_D" --gate-bin "$WORK/no-such-gate" --gate-expected "$WORK/rc_gate_no.txt"
want_out   "gates: ...rl_gate, an expected file that is not there" \
	'could not be evaluated' -- \
	env -u NO_SKIP "$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 1 \
	--gate-differ "$GATE_D" --gate-bin "$WORK/rc_ok" --gate-expected "$WORK/no-such-expected.txt"
want_broken "gates: ...rust_diff, a gate program that is not there" \
	'could not be evaluated' -- \
	env -u NO_SKIP "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/gate_empty_oracle.sh" --oracle-fn f \
	--student-bin "$WORK/rc_ok" --gate-differ "$GATE_D" --gate-bin "$WORK/no-such-gate" \
	--gate-expected "$WORK/rc_gate_no.txt"

