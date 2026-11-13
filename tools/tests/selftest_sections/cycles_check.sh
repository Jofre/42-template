# --------------------------------------------------------------- cycles_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# This layer CANNOT fail on its numbers -- it says so in its own comment, and
# ends in exit 0 whatever the count. So there is no budget arm to write, and
# everything worth pinning is a REFUSAL or a SKIP: each skip is a silent
# green, and NO_SKIP=1 is supposed to turn each into a failure that names
# itself. That is the whole safety net under a layer whose normal output
# nobody checks, and it had no arm at all. The skips pinned here: a red
# output gate, no corpus (an empty one, or an oracle that fails), and a
# symbol absent from the profile. A run too long to profile and a harness
# that returned non-zero need a real profiling run, and are pinned in
# :selftest_slow.
#
# The real profiling run lives in :selftest_slow -- callgrind is 20-50x native.
# No arm here starts a real valgrind: an arm that reaches the profiling run
# hands over a stand-in (vg_standins, and nosym below), and the others stop
# before it. What holds that is the text arm beside each status arm, naming
# the exit it was written for: with that exit's guard deleted, the run went
# on to profile with the real valgrind, whose profile of a symbol never
# entered SKIPs (0), or is red under NO_SKIP=1 (1), the very statuses the
# guard returns. Each pair reads one run (once).
mkdir -p "$WORK/cyc"
printf '#!/bin/sh\ni=0\nwhile [ $i -lt "$3" ]; do echo "abcdefgh$i"; i=$((i+1)); done\n' \
	> "$WORK/cyc/oracle.sh"
printf '#!/bin/sh\nexit 0\n' > "$WORK/cyc/empty.sh"
chmod +x "$WORK/cyc/oracle.sh" "$WORK/cyc/empty.sh"
printf 'int main(void) { return (0) }\n' > "$WORK/cyc/broken.c"

# The pinned valgrind and its callgrind tool, handed to every arm below. These
# arms check the two cycles runners, and both now REQUIRE the pin -- so passing
# it is not decoration: without it every arm here would exit 2 on the wiring
# rather than reaching the behaviour it was written to test. Arms that
# deliberately omit it say so and assert the refusal.
CYC_VG="--valgrind $VALGRIND --valgrind-tools $VGCGTOOLS"

want_broken "cycles_check: it refuses without a symbol to attribute to" \
	'need --oracle, --oracle-fn and --symbol' -- \
	"$SH" "$TOOLS/cycles_check.sh" --harness "$WORK/cyc/broken.c" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f
# NO_SKIP is unset: under a sweep's NO_SKIP=1 a run that went past the
# failed build was red as well, on what callgrind made of no program.
want_red "cycles_check: a harness that will not build at -O2 is RED" -- \
	once env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" $BUILD_PIN --harness "$WORK/cyc/broken.c" $CYC_VG \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
want_out "cycles_check: ...saying the build failed" 'could not build the harness' -- \
	once env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" $BUILD_PIN --harness "$WORK/cyc/broken.c" $CYC_VG \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
# A function the GRADER links (--lib, the contract's `linked`) is linked into
# the -O2 build: the harness calls one no --src defines, the build succeeds,
# and the empty corpus then skips as below. Without the --lib it would not
# link, and be the red above.
printf 'int probe_base(int n);\nint main(void) { return (probe_base(0)); }\n' > "$WORK/cyc/uses_lib.c"
printf 'int probe_base(int n) { return (n); }\n' > "$WORK/cyc/lib.c"
toy_cc "$WORK/cyc/lib.o" -c "$WORK/cyc/lib.c"
want_green "cycles_check: a function from --lib links at -O2" -- \
	once env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" $BUILD_PIN --harness "$WORK/cyc/uses_lib.c" \
		--lib "$WORK/cyc/lib.o" $CYC_VG \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum
want_out "cycles_check: ...and the run goes on past the link" 'could not generate a corpus (fn=f)' -- \
	once env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" $BUILD_PIN --harness "$WORK/cyc/uses_lib.c" \
		--lib "$WORK/cyc/lib.o" $CYC_VG \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum
# A library member's source whose header only the Makefile's -I reaches
# (--inc-file, tools/student_build.sh --includes-out) builds at -O2 as every
# build of the library does (V198); the empty corpus then skips as above.
mkdir -p "$WORK/cyc/inc"
printf 'int	probe_base(int n);\n' > "$WORK/cyc/inc/toy_base.h"
printf '#include "toy_base.h"\nint probe_base(int n) { return (n); }\n' > "$WORK/cyc/base_inc.c"
printf '%s\n' "$WORK/cyc/inc" > "$WORK/cyc/includes.txt"
want_green "cycles_check: a header only the Makefile's -I reaches (--inc-file)" -- \
	once env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" $BUILD_PIN --harness "$WORK/cyc/uses_lib.c" \
		--src "$WORK/cyc/base_inc.c" --inc-file "$WORK/cyc/includes.txt" \
		$CYC_VG \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum
want_out "cycles_check: ...and the run goes on past the build" 'could not generate a corpus (fn=f)' -- \
	once env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" $BUILD_PIN --harness "$WORK/cyc/uses_lib.c" \
		--src "$WORK/cyc/base_inc.c" --inc-file "$WORK/cyc/includes.txt" \
		$CYC_VG \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum
# Its -O2 build is the pinned clang-12's, linked by the pinned ld.bfd: it
# used to be the box's `cc`, so the counts were that compiler's, and a box
# with none skipped the layer (TO VERIFY V38's class).
want_broken "cycles_check: a harness to build and no --cc refuses" 'needs --cc' -- \
	"$SH" "$TOOLS/cycles_check.sh" --harness "$WORK/cyc/uses_lib.c" \
		--lib "$WORK/cyc/lib.o" $CYC_VG \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum

# An empty corpus is the dangerous one: the binary would be profiled against no
# input at all and report a count of nothing, which reads like a fast function.
want_green "cycles_check: an empty corpus SKIPs quietly by default" -- \
	once env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum
want_out "cycles_check: ...naming the corpus as what is missing" \
	'SKIP — the reference could not generate a corpus (fn=f)' -- \
	once env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum
want_red "cycles_check: and NO_SKIP=1 turns that skip RED" -- \
	once env NO_SKIP=1 "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum
want_out "cycles_check: ...naming the empty corpus" 'the reference produced no corpus for fn=f' -- \
	once env NO_SKIP=1 "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum
# An oracle that fails says why, in the skip and in the NO_SKIP red alike: its
# stderr is shown, not discarded.
printf '#!/bin/sh\necho oracle-said-this >&2\nexit 1\n' > "$WORK/cyc/says.sh"
chmod +x "$WORK/cyc/says.sh"
want_out "cycles_check: a failing oracle's skip says why" 'oracle-said-this' -- \
	env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--oracle "$WORK/cyc/says.sh" --oracle-fn f --symbol probe_sum
want_out "cycles_check: ...and so does its NO_SKIP red" 'oracle-said-this' -- \
	env NO_SKIP=1 "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--oracle "$WORK/cyc/says.sh" --oracle-fn f --symbol probe_sum
# THE GATE: while the exercise's own output is red there is no right answer
# to count, so the layer SKIPs, naming the output test it waits for
# (--gate-label): "the output fixture" alone sent a newcomer looking for
# which one.
printf '#!/bin/sh\necho some\n' > "$WORK/cyc/gate.sh"
chmod +x "$WORK/cyc/gate.sh"
printf 'other\n' > "$WORK/cyc/gate_no.txt"
want_out "cycles_check: a red gate SKIPs, naming the test it waits for" \
	'SKIP — ex00_output, this exercise' -- \
	env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/cyc/gate.sh" \
		--gate-expected "$WORK/cyc/gate_no.txt" --gate-label ex00_output
# ...and a gate whose program is not there is said, and the layer runs on
# (V292): it was dropped with nothing said.
want_out "cycles_check: a gate program that is not there is said" \
	'could not be evaluated' -- \
	env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/cyc/no-such-gate" \
		--gate-expected "$WORK/cyc/gate_no.txt"

# NO CALLGRIND IS NO SKIP. The valgrind is pinned, so a missing one is the
# wiring's fault, and the layer refuses (exit 2) rather than skips: the
# arms below. Nothing else it reads can be missing either: the count was
# read off callgrind_annotate, a Perl script this repo does not pin, whose
# absence was a skip of its own with a pair of arms; it is read off the
# profile's own totals now (tools/runner_lib.sh, rl_cg_total).
#
# NO FIXTURE PATH HERE, and that is deliberate rather than an omission. One
# was built -- a directory of symlinks at $WORK/cyc/novg, assembled as the
# union of cycles_check.sh's and ref_compare.sh's require lines -- and NO
# ARM EVER SET PATH TO IT. It read as coverage and provided none for as long
# as it existed. //tools:conventions now reports a fixture nobody points
# PATH at, which is how it was found. And what it hid was taken by flag,
# not from PATH, so hiding it from a PATH the runner never searches would
# have proved nothing.
want_broken "cycles_check: a missing --valgrind refuses, never skips" \
	'--valgrind is required' -- \
	"$SH" "$TOOLS/cycles_check.sh" --bin /bin/true \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
# ...and so does a missing --valgrind-tools, naming it. The tool folder is
# the folder of that file, and an empty one was the folder ".": reported as
# ". does not hold callgrind-amd64-linux", which names neither cause, or
# taken as valgrind's tree when the working folder held such a file.
want_broken "cycles_check: a missing --valgrind-tools refuses, naming it" \
	'--valgrind-tools is required' -- \
	"$SH" "$TOOLS/cycles_check.sh" --bin /bin/true --valgrind "$VALGRIND" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum

# THE UNIT OF WORK is the harness's own expression, so a wrong one is exit 2:
# nothing was measured. Both arms were green-and-wrong before (findings 131 and
# 081): an expression awk refused fell back to one unit per case without a
# word, and one reading the wrong field (a decimal count, half a "byte" a call)
# printed a correct answer as many times over budget. Both stop before
# callgrind is ever started.
want_broken "cycles_check: a unit expression awk refuses is a broken harness" \
	'awk refused the unit expression' -- \
	"$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--unit-expr '($1==?0:1)' \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
want_broken "cycles_check: fewer than one unit per case is a broken harness" \
	'fewer than one per case' -- \
	"$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--unit-expr 'length($1)/100' \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
# ...and a unit is counted in BYTES, whatever the machine's awk. The tests
# run under en_US.UTF-8 (.bazelrc), where an awk that reads multibyte
# characters (gawk does, mawk does not) takes length() of a field of raw
# bytes in characters, warns on stderr of the bytes that are not UTF-8,
# and so counts fewer units, or refuses the expression, on one machine than
# on another. So both runs of the expression (--max-unit's filter and the
# sum) are made under LC_ALL=C, as tools/runner_lib.sh's byte-reading awk
# is. A stand-in awk first on PATH writes down the LC_ALL of each run that
# carries the expression, and hands the run to the real one; the runner
# then stops at the count, as the arm above does, before callgrind.
mkdir -p "$WORK/cyc/awkspy"
printf '#!/bin/sh\ncase "$*" in *"$AWKSPY_MARK"*) printf "[%%s]" "${LC_ALL-unset}" >> "$AWKSPY_SEEN" ;; esac\nexec %s "$@"\n' \
	"$(command -v awk)" > "$WORK/cyc/awkspy/awk"
chmod +x "$WORK/cyc/awkspy/awk"
cyc_awk_locale() {  # the LC_ALL each awk run carrying the unit expression had
	rm -f "$WORK/cyc/awkspy/seen"
	env LC_ALL=en_US.UTF-8 AWKSPY_MARK='length($1)/100' AWKSPY_SEEN="$WORK/cyc/awkspy/seen" \
		PATH="$WORK/cyc/awkspy:$PATH" "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--unit-expr 'length($1)/100' --max-unit 1000 \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum > /dev/null 2>&1
	echo "exit $?, the unit expression read under $(cat "$WORK/cyc/awkspy/seen" 2> /dev/null)."
}
want_out "cycles_check: a unit is counted under LC_ALL=C, in bytes" \
	'exit 2, the unit expression read under [C][C].' -- cyc_awk_locale

# A unit is the bytes every answer must read at least once (c_cycles'
# unit_expr), and where the harness's line says where a match is, it says
# how far that is: ft_strchr's and ft_strnstr's lines do, and their calls
# counted every byte of the string, so a match at the first of 5000 bytes
# was 5000 units of work. Each call's unit_expr is read from Libft's BUILD
# file as written there, and summed as cycles_check.sh sums it over lines
# whose floor is known by construction: the match at offset 0 (1 byte),
# no match in "abc" (its 3 bytes and the terminator), and, for strchr, the
# terminator found (the same 4); for strnstr a len that stops the search
# inside big (3) and one past its end (both bytes and the terminator).
_cyu_build=$(cd "$TOOLS/.." && pwd)/cursus/Milestone_0/Libft/BUILD.bazel
_cyu_far=$(printf '%5000s' '' | sed 's/ /e9/g')
# cyu_sum UNIT LINE...: "units=N." -- UNIT's unit_expr summed over LINEs.
cyu_sum() {
	_cyu_e=$(awk -v u="$1" '
		/^c_cycles\(/ { inb = 1; me = 0; next }
		inb && $0 ~ "^[ \t]*unit[ \t]*=[ \t]*\"" u "\"" { me = 1 }
		inb && me && /^[ \t]*unit_expr[ \t]*=/ {
			sub(/^[^"]*"/, ""); sub(/",?[ \t]*$/, ""); gsub(/\\"/, "\""); print; exit
		}
		inb && /^\)/ { inb = 0 }' "$_cyu_build")
	[ -n "$_cyu_e" ] || { echo "no c_cycles(unit = \"$1\") with a unit_expr in $_cyu_build"; return 2; }
	shift
	printf '%s\n' "$@" | LC_ALL=C awk -F'\t' "{ s += $_cyu_e } END { printf \"units=%d.\", s }"
}
_cyu_tab=$(printf '\t')
want_out "cycles_check: ft_strchr's unit is the bytes up to its match" 'units=9.' -- \
	cyu_sum ft_strchr "$_cyu_far${_cyu_tab}233${_cyu_tab}0" \
		"616263${_cyu_tab}120${_cyu_tab}NULL" "616263${_cyu_tab}0${_cyu_tab}3"
want_out "cycles_check: ...and ft_strnstr's up to its match, or len" 'units=7.' -- \
	cyu_sum ft_strnstr "$_cyu_far${_cyu_tab}e9${_cyu_tab}18446744073709551615${_cyu_tab}0" \
		"6162636465${_cyu_tab}7a${_cyu_tab}3${_cyu_tab}NULL" \
		"6162${_cyu_tab}7a${_cyu_tab}18446744073709551615${_cyu_tab}NULL"

# A stand-in handed over with --bin is not profiled: counting the instructions
# of a shell printing a compiler error would be a number about nothing.
want_red "cycles_check: a stand-in is red, not a count" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/cycles_check.sh" --bin "$STANDIN_BIN" $CYC_VG \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
want_out "cycles_check: ...says the code did not build" "$STANDIN_SAYS" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/cycles_check.sh" --bin "$STANDIN_BIN" $CYC_VG \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
# A valgrind that stopped at its own startup (V242, vg_standins above the
# asan_check section): no count, and no SKIP either, which would hide it as
# this layer standing down. callgrind does not need ld.so's debug symbols
# (only memcheck does), so the refusal shows valgrind's words and must not
# send the student after libc6-dbg.
vg_standins "$WORK/cyc/vgfake"
want_broken "cycles_check: valgrind stopping at its startup refuses, never skips" \
	'failing to set itself up' -- \
	env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true \
		--valgrind "$WORK/cyc/vgfake/abort" \
		--valgrind-tools "$WORK/cyc/vgfake/lib/callgrind-amd64-linux" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
want_broken_without "cycles_check: ...naming no ld.so symbols" \
	'ld.so has no debug symbols' -- \
	env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true \
		--valgrind "$WORK/cyc/vgfake/abort" \
		--valgrind-tools "$WORK/cyc/vgfake/lib/callgrind-amd64-linux" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
# ONE READING OF A PROFILE'S NAMES (tools/runner_lib.sh, rl_cg_awk): write()
# under any of glibc's names, and writev, counted, and stdio's own
# _IO_file_write not. This reader left writev out and counted 8 of the
# profiler's 10; ref_compare's, 2.
want_out "cycles_check: write() is counted under every name glibc gives it" \
	'write() calls     : 10 ' -- \
	env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true \
		--valgrind "$WORK/cyc/vgfake/profile" \
		--valgrind-tools "$WORK/cyc/vgfake/lib/callgrind-amd64-linux" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
# And it starts callgrind with none of the host's settings (V227, vgspy).
want_out "cycles_check: callgrind starts with no host settings" \
	'opts=[unset] debuginfod=[unset] home: another, 0 entries' -- \
	vgspy "$WORK/cyc/vgfake" "$TOOLS/cycles_check.sh" --bin /bin/true \
		--valgrind "$WORK/cyc/vgfake/spy" \
		--valgrind-tools "$WORK/cyc/vgfake/lib/callgrind-amd64-linux" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
# And callgrind is told where its own tree is: VALGRIND_LIB, exported, is
# the folder of the file --valgrind-tools names once its links are
# resolved, as Bazel hands over a link in the runfiles tree (libspy).
want_out "cycles_check: callgrind starts with VALGRIND_LIB, the tool's folder" \
	"VALGRIND_LIB=[$(cd "$WORK/cyc/vgfake/lib" && pwd -P)]" -- \
	vgspy "$WORK/cyc/vgfake" "$TOOLS/cycles_check.sh" --bin /bin/true \
		--valgrind "$WORK/cyc/vgfake/libspy" \
		--valgrind-tools "$WORK/cyc/vgfake/links/callgrind" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum

# THE SKIP THE OTHERS WERE GUARDED FOR: a symbol the run never entered (it
# was inlined, or nothing defines it) has a profile whose totals are 0, and
# a count read the wrong way is the same nothing, for every exercise at
# once. The stand-in writes the profile callgrind 3.18 writes for a
# --toggle-collect symbol that never ran, where --callgrind-out-file says,
# and exits 0, as callgrind does. By default that SKIPs, naming the symbol;
# NO_SKIP=1 turns it RED, naming it too.
cat > "$WORK/cyc/vgfake/nosym" <<'VGFAKE'
#!/bin/sh
out=""
for a in "$@"; do
	case "$a" in --callgrind-out-file=*) out=${a#--callgrind-out-file=} ;; esac
done
[ -n "$out" ] || exit 9
printf '# callgrind format\nversion: 1\ncreator: callgrind-3.18.1\npid: 7\n' > "$out"
printf 'cmd:  ./toy\npart: 1\n\npositions: line\nevents: Ir\nsummary: 0\n\n\ntotals: 0\n' >> "$out"
exit 0
VGFAKE
chmod +x "$WORK/cyc/vgfake/nosym"
CYC_NOSYM="--valgrind $WORK/cyc/vgfake/nosym --valgrind-tools $WORK/cyc/vgfake/lib/callgrind-amd64-linux"
want_green "cycles_check: a symbol absent from the profile SKIPs by default" -- \
	env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_NOSYM \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
want_out "cycles_check: ...naming the symbol" "SKIP — no symbol 'probe_sum' in the profile" -- \
	env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_NOSYM \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
want_red "cycles_check: and NO_SKIP=1 turns the absent symbol RED" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_NOSYM \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
want_out "cycles_check: ...naming it too" "no symbol 'probe_sum' in the callgrind profile" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_NOSYM \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum

# Its gate, as every runner's (rl_gate; the rust_diff section's gate_seen).
# shellcheck disable=SC2086 # GATE_SPY and CYC_VG are lists of words without blanks
cc_gate() { gate_seen "$1" env "$2" "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
	--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum $GATE_SPY; }
want_out "cycles_check: its gate hands the differ --stdin, --sanitize and --labeled" \
	"--expected $WORK/gate_in.txt --stdin $WORK/gate_in.txt --sanitize --labeled" -- \
	cc_gate 0 NO_SKIP=0
want_out "cycles_check: ...its exit 1 SKIPs, naming the test" 'SKIP — lbl_output, this exercise' -- \
	cc_gate 1 NO_SKIP=0
want_out "cycles_check: ...saying how to run it anyway" '--test_env=NO_SKIP=1 runs it anyway.)' -- \
	cc_gate 1 NO_SKIP=0
want_out "cycles_check: ...under its own paragraph" 'Counting the instructions of a wrong answer' -- \
	cc_gate 1 NO_SKIP=0
want_out "cycles_check: ...its exit 2 is said" 'could not be evaluated (exit 2)' -- \
	cc_gate 2 NO_SKIP=0
want_out "cycles_check: ...and runs on" 'could not generate a corpus' -- cc_gate 2 NO_SKIP=0
want_out "cycles_check: ...and NO_SKIP=1 runs without asking it" 'differ: not run' -- \
	cc_gate 1 NO_SKIP=1
