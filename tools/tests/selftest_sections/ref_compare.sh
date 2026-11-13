# ---------------------------------------------------------------- ref_compare
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Its own header names the arms worth having: "the NO_SKIP refusals (this
# layer's plumbing rotted while pretending to measure)". Like cycles_check it
# never fails on the ratio it reports -- the number is informative and nothing
# else -- so a skip that stopped being loud under NO_SKIP=1 is the whole risk.
#
# The argument checks are worth pinning for a second reason recorded in the
# runner: sh_test tokenises `args` on spaces, so a two-word --label arrives as a
# stray argument, and both c_files and c_cycles learned that the hard way.
#
# Its fixtures are its own, beside cycles_check's rather than in them: the
# same toy oracle, written again.
mkdir -p "$WORK/rcmp"
printf '#!/bin/sh\ni=0\nwhile [ $i -lt "$3" ]; do echo "abcdefgh$i"; i=$((i+1)); done\n' \
	> "$WORK/rcmp/oracle.sh"
chmod +x "$WORK/rcmp/oracle.sh"
printf 'int main(void) { return (0); }\n' > "$WORK/rcmp/tiny.c"
want_broken "ref_compare: it refuses without a unit count to divide by" \
	'--units must be a positive integer' -- \
	"$SH" "$TOOLS/ref_compare.sh" --harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/tiny.c" \
		$CYC_VG \
		--oracle "$WORK/rcmp/oracle.sh" --oracle-fn f --symbol probe_sum
want_broken "ref_compare: and a stray argument names its own cause" \
	'tokenises args on spaces' -- \
	"$SH" "$TOOLS/ref_compare.sh" --harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/tiny.c" \
		$CYC_VG \
		--oracle "$WORK/rcmp/oracle.sh" --oracle-fn f --symbol probe_sum \
		--units 1 stray-word
want_broken "ref_compare: a missing --valgrind refuses, never skips" \
	'--valgrind is required' -- \
	"$SH" "$TOOLS/ref_compare.sh" \
		--harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/tiny.c" \
		--oracle "$WORK/rcmp/oracle.sh" --oracle-fn f --symbol probe_sum --units 1
# ...and so does a missing --valgrind-tools, naming it (cycles_check's arm
# says what an empty one was).
want_broken "ref_compare: a missing --valgrind-tools refuses, naming it" \
	'--valgrind-tools is required' -- \
	"$SH" "$TOOLS/ref_compare.sh" --valgrind "$VALGRIND" \
		--harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/tiny.c" \
		--oracle "$WORK/rcmp/oracle.sh" --oracle-fn f --symbol probe_sum --units 1
# Its -O2 build, one side of the ratio, is the pinned clang-12's: it was the
# box's `cc` (TO VERIFY V38's class).
want_broken "ref_compare: no --cc refuses, never takes the box's" '--cc is required' -- \
	"$SH" "$TOOLS/ref_compare.sh" $CYC_VG \
		--harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/tiny.c" \
		--oracle "$WORK/rcmp/oracle.sh" --oracle-fn f --symbol probe_sum --units 1
# And its callgrind stopping at its own startup (V242): the same refusal. The
# harness builds and the reference does one unit of work, so the run reaches
# callgrind.
printf 'int probe_sum(int n) { return (n); }\n' > "$WORK/rcmp/fn.c"
printf '#!/bin/sh\nprintf "one\\n1\\n"\n' > "$WORK/rcmp/bench1.sh"
chmod +x "$WORK/rcmp/bench1.sh"
vg_standins "$WORK/rcmp/vgfake"
want_broken "ref_compare: valgrind stopping at its startup refuses, never skips" \
	'failing to set itself up' -- \
	env -u NO_SKIP "$SH" "$TOOLS/ref_compare.sh" $BUILD_PIN \
		--valgrind "$WORK/rcmp/vgfake/abort" \
		--valgrind-tools "$WORK/rcmp/vgfake/lib/callgrind-amd64-linux" \
		--harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/fn.c" \
		--oracle "$WORK/rcmp/bench1.sh" --oracle-fn f --symbol probe_sum --units 1
want_broken_without "ref_compare: ...naming no ld.so symbols" \
	'ld.so has no debug symbols' -- \
	env -u NO_SKIP "$SH" "$TOOLS/ref_compare.sh" $BUILD_PIN \
		--valgrind "$WORK/rcmp/vgfake/abort" \
		--valgrind-tools "$WORK/rcmp/vgfake/lib/callgrind-amd64-linux" \
		--harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/fn.c" \
		--oracle "$WORK/rcmp/bench1.sh" --oracle-fn f --symbol probe_sum --units 1
# And it starts callgrind with none of the host's settings (V227, vgspy).
want_out "ref_compare: callgrind starts with no host settings" \
	'opts=[unset] debuginfod=[unset] home: another, 0 entries' -- \
	vgspy "$WORK/rcmp/vgfake" "$TOOLS/ref_compare.sh" $BUILD_PIN \
		--valgrind "$WORK/rcmp/vgfake/spy" \
		--valgrind-tools "$WORK/rcmp/vgfake/lib/callgrind-amd64-linux" \
		--harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/fn.c" \
		--oracle "$WORK/rcmp/bench1.sh" --oracle-fn f --symbol probe_sum --units 1
# And callgrind is told where its own tree is, as cycles_check's is.
want_out "ref_compare: callgrind starts with VALGRIND_LIB, the tool's folder" \
	"VALGRIND_LIB=[$(cd "$WORK/rcmp/vgfake/lib" && pwd -P)]" -- \
	vgspy "$WORK/rcmp/vgfake" "$TOOLS/ref_compare.sh" $BUILD_PIN \
		--valgrind "$WORK/rcmp/vgfake/libspy" \
		--valgrind-tools "$WORK/rcmp/vgfake/links/callgrind" \
		--harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/fn.c" \
		--oracle "$WORK/rcmp/bench1.sh" --oracle-fn f --symbol probe_sum --units 1
# ONE READING OF A PROFILE'S NAMES (tools/runner_lib.sh, rl_cg_awk): write()
# under any of glibc's names, and writev, counted, and stdio's own
# _IO_file_write not. This reader matched three names of its own and counted
# 2 of the profiler's 10; cycles_check's, 8.
want_out "ref_compare: write() is counted under every name glibc gives it" \
	'yours                                1000           1000             10' -- \
	env -u NO_SKIP "$SH" "$TOOLS/ref_compare.sh" $BUILD_PIN \
		--valgrind "$WORK/rcmp/vgfake/profile" \
		--valgrind-tools "$WORK/rcmp/vgfake/lib/callgrind-amd64-linux" \
		--harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/fn.c" \
		--oracle "$WORK/rcmp/bench1.sh" --oracle-fn f --symbol probe_sum --units 1
# A gate whose program is not there is said, and the layer runs on (V292):
# it was dropped with nothing said. The run then reaches a callgrind that
# leaves no profile (the spy), and SKIPs.
want_out   "ref_compare: a gate program that is not there is said" \
	'could not be evaluated' -- \
	env -u NO_SKIP "$SH" "$TOOLS/ref_compare.sh" $BUILD_PIN \
		--valgrind "$WORK/rcmp/vgfake/spy" \
		--valgrind-tools "$WORK/rcmp/vgfake/lib/callgrind-amd64-linux" \
		--harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/fn.c" \
		--oracle "$WORK/rcmp/bench1.sh" --oracle-fn f --symbol probe_sum --units 1 \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/rcmp/no-such-gate" \
		--gate-expected "$WORK/rcmp/tiny.c"
# Its gate, as every runner's (rl_gate; the rust_diff section's gate_seen).
# shellcheck disable=SC2086 # GATE_SPY and BUILD_PIN are lists of words without blanks
rcmp_gate() { gate_seen "$1" env "$2" "$SH" "$TOOLS/ref_compare.sh" $BUILD_PIN \
	--valgrind "$WORK/rcmp/vgfake/profile" \
	--valgrind-tools "$WORK/rcmp/vgfake/lib/callgrind-amd64-linux" \
	--harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/fn.c" \
	--oracle "$WORK/rcmp/bench1.sh" --oracle-fn f --symbol probe_sum --units 1 $GATE_SPY; }
want_out "ref_compare: its gate hands the differ --stdin, --sanitize and --labeled" \
	"--expected $WORK/gate_in.txt --stdin $WORK/gate_in.txt --sanitize --labeled" -- \
	rcmp_gate 0 NO_SKIP=0
want_out "ref_compare: ...its exit 1 SKIPs, naming the test" 'SKIP — lbl_output, this exercise' -- \
	rcmp_gate 1 NO_SKIP=0
want_out "ref_compare: ...saying how to run it anyway" '--test_env=NO_SKIP=1 runs it anyway.)' -- \
	rcmp_gate 1 NO_SKIP=0
want_out "ref_compare: ...under its own paragraph" 'What a wrong answer costs is not information' -- \
	rcmp_gate 1 NO_SKIP=0
want_out "ref_compare: ...its exit 2 is said" 'could not be evaluated (exit 2)' -- \
	rcmp_gate 2 NO_SKIP=0
want_out "ref_compare: ...and runs on" 'against an optimised reference' -- rcmp_gate 2 NO_SKIP=0
want_out "ref_compare: ...and NO_SKIP=1 runs without asking it" 'differ: not run' -- \
	rcmp_gate 1 NO_SKIP=1
# NO CORRECTNESS VERDICT WHERE NO CHECK RAN. Under NO_SKIP=1 the gate is not
# asked, and a differ that exits 2 could not answer: either way nothing
# compared the program's output, and the report said "your function is
# correct", called a ratio near 1 "a well-judged solution" and a larger one
# "the work of the reference for the same answer". The profiler's student
# side counts VGFAKE_STUDENT_IR instructions, the reference's 1000: 3000 is
# a ratio of 3.0, which closes on the door, and 1000 one of 1.0.
rcmp_unjudged() {  # rcmp_unjudged NO_SKIP=N GATE-RC -- both ratios' reports, one after the other
	for _ru in 3000 1000; do
		gate_seen "$2" env "$1" VGFAKE_STUDENT_IR="$_ru" "$SH" "$TOOLS/ref_compare.sh" $BUILD_PIN \
			--valgrind "$WORK/rcmp/vgfake/profile" \
			--valgrind-tools "$WORK/rcmp/vgfake/lib/callgrind-amd64-linux" \
			--harness "$WORK/rcmp/tiny.c" --src "$WORK/rcmp/fn.c" \
			--oracle "$WORK/rcmp/bench1.sh" --oracle-fn f --symbol probe_sum --units 1 $GATE_SPY
	done
}
if st_mine; then
	rcmp_unjudged NO_SKIP=1 1 > "$WORK/rcmp/forced.out"
	rcmp_unjudged NO_SKIP=0 2 > "$WORK/rcmp/broken.out"
	rcmp_unjudged NO_SKIP=0 0 > "$WORK/rcmp/judged.out"
fi
for _rw in 'is correct' 'well-judged' 'same answer'; do
	want_broken_none "ref_compare: under NO_SKIP=1 no report says '$_rw'" "$_rw" -- \
		cat "$WORK/rcmp/forced.out"
	want_broken_none "ref_compare: ...nor past a gate that could not answer" "$_rw" -- \
		cat "$WORK/rcmp/broken.out"
	want_out "ref_compare: ...while past a green gate it does" "$_rw" -- \
		cat "$WORK/rcmp/judged.out"
done
