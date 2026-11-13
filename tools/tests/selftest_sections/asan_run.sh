# ------------------------------------------------------------------ asan_run
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The probe is the driver's, before the first section (selftest.sh, THE
# SANITIZER PROBE): it sets SAN, which later sections read too, and leaves
# its program, an out-of-bounds write, in $WORK/oob. Where it set SAN=0 it
# refused NO_SKIP=1 too, so a skip line here is st_skipped's alone.
if [ "$SAN" = 1 ]; then
	want_red "asan_run: an out-of-bounds write fails" -- \
		"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/oob"
	want_green "asan_run: a clean program passes" -- \
		"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/ok"
	# A program that returns -1 on an error input is memory-clean if it is:
	# its status is 255, which the shell's 128+N reading called signal 127.
	want_green "asan_run: a return of 255 is a return, not a crash" -- \
		"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/emit" -- "$WORK/exp.txt" 255
else
	st_skipped "asan_run: (sanitizer build unavailable)" skipped
fi

# A report's kind is said in words, from its own first line: the headline
# said "a memory error or undefined behaviour" above every report, and its
# next line explained an out-of-bounds read whatever the report was. The
# stand-in writes the lines AddressSanitizer writes for a block freed twice,
# and ends as abort_on_error ends a run.
printf '#!/bin/sh\necho "==1==ERROR: AddressSanitizer: attempting double-free on 0x602000000010 in thread T0:" >&2\necho "SUMMARY: AddressSanitizer: double-free (/x/a.out+0x499f02) in free" >&2\nkill -ABRT $$\n' \
	> "$WORK/san_twice"
chmod +x "$WORK/san_twice"
want_out "asan_run: a block freed twice is named as one" \
	'FAIL — the program freed the same block twice (double-free)' -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/san_twice"
want_broken_none "asan_run: ...and not explained as a read out of bounds" 'out-of-bounds' -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/san_twice"
# A leak report's SUMMARY line counts bytes ("7 byte(s) leaked"): its first
# word is a number, not a kind, and the kind is its ERROR line's. The
# sanitizer options switch leak reports off; a caller's own options can
# switch them back on.
printf '==1==ERROR: LeakSanitizer: detected memory leaks\nSUMMARY: AddressSanitizer: 7 byte(s) leaked in 1 allocation(s).\n' \
	> "$WORK/san_leak.txt"
want_out "rl_sanitized: a leak report is named by its ERROR line" 'kind=memory-leak' -- \
	"$SH" -c '. "$1"; rl_sanitized "$2"; echo "kind=$RL_SAN_KIND"' _ "$TOOLS/runner_lib.sh" "$WORK/san_leak.txt"

# ...AND NO MEMORY LAYER MAY CALL A PROGRAM THAT NEVER BUILT CLEAN. The stand-in
# exits 86, names no sanitizer and dies on no signal, so asan_run.sh used to
# fall straight through to "OK -- memory-clean on this case": nine rush-02 ASan
# targets were green for a program that did not exist. Its contract is to step
# aside, as the gated layers do -- the output layer tells this story -- and
# NO_SKIP=1 turns that into the failure it would otherwise hide.
want_out "asan_run: a never-built program is a SKIP, not memory-clean" \
	'was never built' -- \
	env -u NO_SKIP "$SH" "$TOOLS/asan_run.sh" --bin "$STANDIN_BIN" --label stubbed
# The stand-in's line names what is tested by its kind (standin.sh's
# standin_noun), and says "exercise" where nothing names one.
want_out "standin: ...the output layer of an exercise" \
	'The output layer of this exercise says what the build found.' -- \
	env -u NO_SKIP "$SH" "$TOOLS/asan_run.sh" --bin "$WORK/standin/empty" --label stubbed
want_out "standin: ...the output layer of a library" \
	'The output layer of this library says what the build found.' -- \
	env -u NO_SKIP RL_UNIT_KIND=library "$SH" "$TOOLS/asan_run.sh" --bin "$WORK/standin/empty" \
		--label stubbed
# Its failure guesses what is not written yet, and a function's program is
# its library's build (runner_lib.sh's rl_entry): a build with nothing to
# compile is the library's, and says nothing of one function's file.
want_out "standin: ...an empty build, of an exercise" \
	'to run as stubbed. If this exercise is not written yet, that is' -- \
	env NO_SKIP=1 "$SH" "$TOOLS/asan_run.sh" --bin "$WORK/standin/empty" --label stubbed
want_out "standin: ...and of a function, names its library" \
	'to run as stubbed. If this library is not written yet, that is' -- \
	env NO_SKIP=1 RL_UNIT_KIND=function "$SH" "$TOOLS/asan_run.sh" --bin "$WORK/standin/empty" \
		--label stubbed
want_broken_none "asan_run: ...and it never says memory-clean about it" \
	'memory-clean' -- \
	env -u NO_SKIP "$SH" "$TOOLS/asan_run.sh" --bin "$STANDIN_BIN" --label stubbed
want_red "asan_run: NO_SKIP=1 turns that skip red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/asan_run.sh" --bin "$STANDIN_BIN" --label stubbed
want_out "asan_run: ...says the code did not build" "$STANDIN_SAYS" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/asan_run.sh" --bin "$STANDIN_BIN" --label stubbed

# A SURVIVE CASE'S RUN WAITS ON ITS GATE CASE, as its output test does: it asks
# only that the program ends, and one nobody has written does, memory-clean,
# so do-op's INT_MIN / -1 arm was green on a stub while its output test said
# SKIP (_survive_gate). The gate's program is the plain build: crash fails the
# gate case, sv_gate passes it with no argument. `env -u NO_SKIP`, because the
# suite forces every gate open.
as_gated() {  # as_gated GATE-BIN [NO_SKIP] -- ok's run, gated on GATE-BIN's case
	env NO_SKIP="${2:-0}" "$SH" "$TOOLS/asan_run.sh" --bin "$WORK/ok" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/$1" \
		--gate-expected "$WORK/exp.txt" --gate-label ex00_one_output -- big
}
want_out "asan_run: a survive case waits while its gate case is red" \
	"SKIP — ex00_one_output, this exercise's own case" -- as_gated crash
# The gate's words name what is tested by its kind (rl_noun), and a kind no
# contract has is the harness's fault, refused before anything runs.
want_out "asan_run: ...a function's log says it is a function's" \
	"SKIP — ex00_one_output, this function's own case" -- with_kind function as_gated crash
want_broken "runner_lib: a kind no contract has is the harness's fault" \
	"runner_lib.sh: RL_UNIT_KIND is 'lesson'" -- with_kind lesson as_gated crash
want_broken_none "asan_run: ...saying nothing of memory" 'memory-clean' -- as_gated crash
want_out "asan_run: ...runs once that case is green" 'memory-clean' -- as_gated sv_gate
want_out "asan_run: ...or when NO_SKIP=1 forces it open" 'memory-clean' -- as_gated crash 1

# A run that never reached main is not memory-clean: this layer's verdict is
# how the run ended and nothing else, so it is the one a never-started run
# turned green (review of wave 3). The fixtures are the diff_output arms';
# none is instrumented, and none needs to be -- each is stopped before main.
want_broken "asan_run: a program exec cannot start is refused" \
	'could not be started' -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/noint"
want_broken "asan_run: a program whose .so is gone is refused" \
	'error while loading shared libraries' -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/ldmiss"
want_broken "asan_run: ...and one whose .so lacks a version (exit 1)" \
	"version \`SELFTEST_2' not found" -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/ldver"
# The premise, false: a program that RETURNS 127, with a loader-like line in
# its stderr that does not name it, ran. The old runner refused every 127.
printf '#!/bin/sh\necho "some/other: error while loading shared libraries: x" >&2\nexit 127\n' \
	> "$WORK/ret127"
chmod +x "$WORK/ret127"
want_green "asan_run: a program that returns 127 has returned" -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/ret127"
# A program that writes without end is stopped at an output budget (4 MiB),
# and said to: with no cap it filled the test's scratch folder (1.29 GB in
# two seconds, measured) and was then called too slow. This toy writes 12 MB
# to stderr and stops, so the arm costs little either way.
printf '#!/bin/sh\nexec head -c 12000000 /dev/zero >&2\n' > "$WORK/as_flood"
chmod +x "$WORK/as_flood"
want_out "asan_run: a program writing past its output budget is stopped, and said to be" \
	'kept writing past its output budget' -- "$SH" "$TOOLS/asan_run.sh" --bin "$WORK/as_flood"

# A program case runs the same thing under the sanitizer as in its output
# test: its argument file and its run folder too (diff_output's arms above).
# Two toys that abort -- this layer's failure -- unless the run is the one
# described: one given exactly one empty argument, one beside ./toy.dict.
printf '%s\n' '#include <stdlib.h>' \
	'int main(int ac, char **av) { if (ac != 2 || av[1][0]) abort(); return (0); }' > "$WORK/pc_empty.c"
toy_cc "$WORK/pc_empty" "$WORK/pc_empty.c"
printf '\n' > "$WORK/pc_empty.argv"
printf '%s\n' '#include <stdio.h>' '#include <stdlib.h>' \
	'int main(void) { FILE *f = fopen("toy.dict", "r"); if (!f) abort(); fclose(f); return (0); }' \
	> "$WORK/pc_need.c"
toy_cc "$WORK/pc_need" "$WORK/pc_need.c"
# ...and stdin is /dev/null unless the case names a file (diff_output's arm).
printf '%s\n' '#include <stdlib.h>' '#include <unistd.h>' \
	'int main(void) { char c; if (read(0, &c, 1) > 0) abort(); return (0); }' > "$WORK/pc_nostdin.c"
toy_cc "$WORK/pc_nostdin" "$WORK/pc_nostdin.c"
want_green "asan_run: a case with no stdin reads /dev/null" -- \
	sh -c 'printf "x\n" | "$1" "$2" --bin "$3"' _ "$SH" "$TOOLS/asan_run.sh" "$WORK/pc_nostdin"
want_green "asan_run: --argv-file passes an empty argument" -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/pc_empty" --argv-file "$WORK/pc_empty.argv"
want_red   "asan_run: ...which the run without it lacks" -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/pc_empty"
want_green "asan_run: --run-as runs from a folder holding --cwd-file" -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/pc_need" --run-as toy --cwd-file "toy.dict=$WORK/pc_staged.txt"
want_red   "asan_run: ...which the run from here lacks" -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/pc_need"
want_out   "asan_run: --show-run opens with the run" 'RAN: ./toy' -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/pc_need" --run-as toy --cwd-file "toy.dict=$WORK/pc_staged.txt" \
		--show-run bazel-bin/m/ex00_bin_asan
want_broken "asan_run: --cwd-file with no --run-as refuses" 'stages a file in the folder' -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/pc_need" --cwd-file "toy.dict=$WORK/pc_staged.txt"
want_broken "asan_run: an --argv-file that is not there refuses" 'is not readable' -- \
	"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/pc_empty" --argv-file "$WORK/pc_nothere.argv"
# valgrind_test's own arms need valgrind (selftest_slow); refusing a run it
# cannot describe does not.
want_broken "valgrind_test: --cwd-file with no --run-as refuses" 'stages a file in the folder' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/pc_need" --cwd-file "toy.dict=$WORK/pc_staged.txt"
want_broken "valgrind_test: an --argv-file that is not there refuses" 'is not readable' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/pc_empty" --argv-file "$WORK/pc_nothere.argv"
# --run-as is the program's file name in its run folder, never a path: each
# runner that makes the case's run refuses one (rl_case_check).
for _r in diff_output asan_run valgrind_test allocfail_check; do
	_x=""
	[ "$_r" != diff_output ] || _x="--expected $WORK/pc_staged.txt"
	# shellcheck disable=SC2086 # _x is two words or none
	want_broken "$_r: --run-as takes a file name, never a path" "takes the program's file name" -- \
		"$SH" "$TOOLS/$_r.sh" --bin "$WORK/pc_need" $_x --run-as a/b
done
# --explain prints what a corpus's cases named under --brief, once each, and
# runs nothing (V53; selftest_slow runs a corpus through it).
want_green "valgrind_test: --explain prints a paragraph and runs nothing" -- \
	"$SH" "$TOOLS/valgrind_test.sh" --explain fds --explain trace
want_out   "valgrind_test: ...each in the order asked" 'Reading the trace' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --explain fds --explain trace
want_broken "valgrind_test: ...and refuses a name it has no paragraph for" \
	"no paragraph is named 'nothing'" -- "$SH" "$TOOLS/valgrind_test.sh" --explain nothing
# The rule a memory finding breaks is a paragraph too, said once under a
# corpus's verdict: --brief left it out and nothing said it (the review of
# V53). This harness's own, said to be so, or the subject's sentence where
# the call site quotes one (--rule, c_program's memory_rule; V82).
printf 'Toy, p.1: "Free what you allocate."\n' > "$WORK/vg_rule.txt"
want_out   "valgrind_test: --explain rule states this harness's rule as its own" \
	"It is not a sentence of your subject's" -- "$SH" "$TOOLS/valgrind_test.sh" --explain rule
want_out   "valgrind_test: ...and quotes the subject's sentence given one" \
	'Toy, p.1: "Free what you allocate."' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --explain rule --rule "$WORK/vg_rule.txt"
want_broken_none "valgrind_test: ...never then calling the rule the harness's" \
	'It is not a sentence' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --explain rule --rule "$WORK/vg_rule.txt"
# A subject that says one thing of a leak and another of an invalid access
# (--access-rule): a red quotes the sentence its finding breaks, named under
# --brief rule:access and rule:leak, which --explain prints from the two
# files. Without --access-rule, rule is the one paragraph, as above; the
# runs that pick the paragraphs are selftest_slow's.
printf 'Toy, p.1: "Touch only what you own."\n' > "$WORK/vg_access.txt"
want_out   "valgrind_test: --explain rule:access quotes --access-rule" \
	'Toy, p.1: "Touch only what you own."' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --explain rule:access --access-rule "$WORK/vg_access.txt"
want_out   "valgrind_test: ...under what it applies to" 'to an invalid access or a crash' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --explain rule:access --access-rule "$WORK/vg_access.txt"
want_out   "valgrind_test: --explain rule:leak quotes --rule" \
	'Toy, p.1: "Free what you allocate."' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --explain rule:leak --rule "$WORK/vg_rule.txt" \
		--access-rule "$WORK/vg_access.txt"
want_broken_none "valgrind_test: ...never the access sentence" 'Touch only what you own' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --explain rule:leak --rule "$WORK/vg_rule.txt" \
		--access-rule "$WORK/vg_access.txt"
want_out   "valgrind_test: ...and with no --rule, the leak rule as this harness's" \
	"It is not a sentence of your" -- \
	"$SH" "$TOOLS/valgrind_test.sh" --explain rule:leak --access-rule "$WORK/vg_access.txt"
want_broken_none "valgrind_test: --explain rule never quotes --access-rule" \
	'Touch only what you own' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --explain rule --rule "$WORK/vg_rule.txt" \
		--access-rule "$WORK/vg_access.txt"
want_broken "valgrind_test: --explain rule:access with no --access-rule refuses" \
	'quotes --access-rule, and none was given' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --explain rule:access
: > "$WORK/vg_access_empty.txt"
want_broken "valgrind_test: an empty --access-rule refuses" 'no sentence in --access-rule' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --access-rule "$WORK/vg_access_empty.txt" --explain rule
want_broken "valgrind_test: ...and one that is not there" 'no sentence in --access-rule' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --access-rule "$WORK/vg_access_nothere.txt" --explain rule
want_broken "rl_mem: an empty --access-rule refuses too" 'no sentence in --access-rule' -- \
	"$SH" -c 'RL_NAME=t; . "$1"; rl_mem_opt --valgrind /x; rl_mem_opt --valgrind-tools /y; rl_mem_opt --access-rule "$2"; rl_mem_ready' \
	_ "$TOOLS/runner_lib.sh" "$WORK/vg_access_empty.txt"
want_broken "rl_mem: ...and --access-rule goes with --valgrind" '--access-rule and --rule go with --valgrind' -- \
	"$SH" -c 'RL_NAME=t; . "$1"; rl_mem_opt --access-rule "$2"; rl_mem_ready' \
	_ "$TOOLS/runner_lib.sh" "$WORK/vg_access.txt"

# A VALGRIND THAT NEVER RAN THE PROGRAM IS NO VERDICT (V242). On a box whose
# ld.so has no debug symbols (no libc6-dbg), the pinned valgrind stops at its
# own startup: it writes "Fatal error at startup" to its log and exits 1, the
# program never runs, and the log holds no ERROR SUMMARY. valgrind_test read
# that 1 as the program's own exit status and printed OK over a toy that
# leaked. (cycles_check and ref_compare run callgrind, which does not need
# those symbols and ran such a toy to the end; their arms below hold the same
# refusal for a callgrind that stops at its startup, should one ever do so,
# and that it names no ld.so.) Stand-ins play the three
# ways a run ends with no report: the startup abort, an option valgrind
# refuses (its message on stderr, exit 1), and a run whose log stops after
# the header with exit 0 (what a program that replaces itself with exec
# leaves). They never run the program, so they need no valgrind; the
# real runs are selftest_slow's. vg_standins DIR writes them into DIR, with
# a tool folder at DIR/lib: the cycles_check and ref_compare sections below
# make trees of their own with it.
vg_standins() {
	mkdir -p "$1/lib"
	: > "$1/lib/memcheck-amd64-linux"
	: > "$1/lib/callgrind-amd64-linux"
	cat > "$1/abort" <<'VGFAKE'
#!/bin/sh
# valgrind's own words when ld.so has no symbols memcheck can redirect
# strlen in; the callgrind arms below reuse it as any startup abort.
log=""
for a in "$@"; do
	case "$a" in --log-file=*) log=${a#--log-file=} ;; esac
done
{
	printf '==7== Memcheck, a memory error detector\n==7== \n\n'
	printf 'valgrind:  Fatal error at startup: a function redirection\n'
	printf 'valgrind:  which is mandatory for this platform-tool combination\n'
	printf 'valgrind:  cannot be set up.  Details of the redirection are:\n'
	printf 'valgrind:  whose name matches the pattern:      strlen\n'
	printf 'valgrind:  in an object with soname matching:   ld-linux-x86-64.so.2\n'
	printf 'valgrind:    On Debian, Ubuntu:                 libc6-dbg\n'
	printf 'valgrind:  Cannot continue -- exiting now.  Sorry.\n'
} > "${log:-/dev/stderr}"
exit 1
VGFAKE
	printf '#!/bin/sh\necho "valgrind: Bad option: --toy-option" >&2\nexit 1\n' > "$1/badopt"
	cat > "$1/nosummary" <<'VGFAKE'
#!/bin/sh
log=""
for a in "$@"; do
	case "$a" in --log-file=*) log=${a#--log-file=} ;; esac
done
printf '==7== Memcheck, a memory error detector\n==7== Command: ./toy\n==7== \n' > "${log:-/dev/stderr}"
exit 0
VGFAKE
	chmod +x "$1/abort" "$1/badopt" "$1/nosummary"
	# The spy (V227): writes down the VALGRIND_OPTS, the DEBUGINFOD_URLS
	# (V270) and the HOME it was started with, then exits 1 with no
	# report. DIR/home is the caller's HOME in vgspy, below, and holds a
	# .valgrindrc, as DIR/rcdir does.
	mkdir -p "$1/home" "$1/rcdir"
	printf -- '--tool=none\n' > "$1/home/.valgrindrc"
	printf -- '--tool=none\n' > "$1/rcdir/.valgrindrc"
	cat > "$1/spy" <<'VGFAKE'
#!/bin/sh
if [ "$HOME" = "$VGSPY_HOME" ]; then _h="the caller's"; else _h=another; fi
printf 'opts=[%s] debuginfod=[%s] home: %s, %s entries\n' "${VALGRIND_OPTS-unset}" \
	"${DEBUGINFOD_URLS-unset}" "$_h" \
	"$(ls -A "$HOME" 2> /dev/null | wc -l | tr -d ' ')" > "$VGSPY_OUT"
exit 1
VGFAKE
	chmod +x "$1/spy"
	# The tool folder's spy: writes down the VALGRIND_LIB it was started
	# with, then exits 1 with no report. DIR/links holds a link to each
	# tool, in a folder that holds none, so a runner that took the folder
	# of the link and not of what it points to refuses before the run.
	printf '#!/bin/sh\nprintf "VALGRIND_LIB=[%%s]\\n" "${VALGRIND_LIB-unset}" > "$VGSPY_OUT"\nexit 1\n' \
		> "$1/libspy"
	chmod +x "$1/libspy"
	# The profiler: writes a callgrind profile and runs nothing. The program's own function calls write()
	# under three of the names glibc records it with (5 + 3) and writev (2),
	# and stdio's _IO_file_write once, which is no write() of its own: a
	# reader counts 10. A profile of a program named "student" (ref_compare's
	# side of a ratio) counts VGFAKE_STUDENT_IR instructions, 1000 unset.
	cat > "$1/profile" <<'VGFAKE'
#!/bin/sh
out=""
prog=""
for a in "$@"; do
	case "$a" in
		--callgrind-out-file=*) out=${a#--callgrind-out-file=} ;;
		-*) ;;
		*) [ -n "$prog" ] || prog=$a ;;
	esac
done
ir=1000
case $prog in */student) ir=${VGFAKE_STUDENT_IR:-1000} ;; esac
cat > "$out" <<PROFILE
version: 1
creator: callgrind-3.18.1
events: Ir
ob=(1) $(readlink -f "$prog")
fl=(1) /toy/fn.c
fn=(1) probe_sum
0 100
cob=(2) /toy/libc.so.6
cfi=(2) /toy/write.c
cfn=(2) __GI___libc_write
calls=5 0
0 50
cob=(2)
cfi=(2)
cfn=(3) writev
calls=2 0
0 20
cob=(2)
cfi=(2)
cfn=(4) write@GLIBC_2.2.5
calls=3 0
0 30
cob=(2)
cfi=(2)
cfn=(5) _IO_file_write
calls=1 0
0 10
totals: $ir
PROFILE
VGFAKE
	chmod +x "$1/profile"
	mkdir -p "$1/links"
	ln -sf "$1/lib/memcheck-amd64-linux" "$1/links/memcheck"
	ln -sf "$1/lib/callgrind-amd64-linux" "$1/links/callgrind"
}
# vgspy DIR RUNNER ARG... -- RUNNER over DIR's spy, with the host's valgrind
# settings on: VALGRIND_OPTS, DEBUGINFOD_URLS (with it set, memcheck runs
# debuginfod-find from PATH for each object it has no debug information
# for: V270), and a HOME holding a .valgrindrc. It prints
# what the spy saw, whatever RUNNER then made of a run with no report.
vgspy() {
	_vs=$1
	shift
	rm -f "$_vs/seen"
	env VALGRIND_OPTS=--tool=none DEBUGINFOD_URLS=http://debuginfod.invalid \
		HOME="$_vs/home" VGSPY_HOME="$_vs/home" \
		VGSPY_OUT="$_vs/seen" "$SH" "$@" > /dev/null 2>&1
	cat "$_vs/seen" 2> /dev/null
	return 0
}
vg_standins "$WORK/vgfake"
VGFAKE_MC="--valgrind-tools $WORK/vgfake/lib/memcheck-amd64-linux"
want_broken "valgrind_test: valgrind stopping at its startup is no verdict" \
	'stopped at its own startup' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/pc_nostdin" --valgrind "$WORK/vgfake/abort" $VGFAKE_MC
want_broken "valgrind_test: ...and names the debug symbols it lacked" 'libc6-dbg' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/pc_nostdin" --valgrind "$WORK/vgfake/abort" $VGFAKE_MC
want_broken "valgrind_test: ...showing valgrind's own words" 'Fatal error at startup' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/pc_nostdin" --valgrind "$WORK/vgfake/abort" $VGFAKE_MC
want_broken "valgrind_test: an option valgrind refused is no verdict" \
	'never reached its ERROR SUMMARY' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/pc_nostdin" --valgrind "$WORK/vgfake/badopt" $VGFAKE_MC
want_broken "valgrind_test: ...showing what valgrind said" 'Bad option: --toy-option' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/pc_nostdin" --valgrind "$WORK/vgfake/badopt" $VGFAKE_MC
want_broken "valgrind_test: a log with no ERROR SUMMARY is no OK, even at 0" \
	'never reached its ERROR SUMMARY' -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/pc_nostdin" --valgrind "$WORK/vgfake/nosummary" $VGFAKE_MC

# THE HOST'S VALGRIND SETTINGS NEVER REACH A RUN (V227). valgrind reads
# ~/.valgrindrc, $VALGRIND_OPTS and ./.valgrindrc before its command line,
# which overrides only what it names: VALGRIND_OPTS=--tool=none, or a
# suppression file matching everything in either rc file, printed OK over a
# leak. The spy (vg_standins) is started with no VALGRIND_OPTS, no
# DEBUGINFOD_URLS (V270) and a HOME that is not the caller's and is empty,
# by each of the three runners that start a valgrind (selftest_slow runs
# the real one over a leak, and with a debuginfod-find of its own on PATH).
want_out "valgrind_test: valgrind starts with no host settings" \
	'opts=[unset] debuginfod=[unset] home: another, 0 entries' -- \
	vgspy "$WORK/vgfake" "$TOOLS/valgrind_test.sh" --bin "$WORK/pc_nostdin" \
		--valgrind "$WORK/vgfake/spy" $VGFAKE_MC
# ./.valgrindrc can only be switched off by running from another folder,
# which would move the program's own: the runner refuses it instead.
_vgt=$(cd "$TOOLS" && pwd)/valgrind_test.sh
want_broken "valgrind_test: a .valgrindrc where valgrind runs refuses" \
	'is in the folder valgrind runs from' -- \
	sh -c 'cd "$1" && shift && exec "$@"' _ "$WORK/vgfake/rcdir" \
		"$SH" "$_vgt" --bin "$WORK/pc_nostdin" --valgrind "$WORK/vgfake/spy" $VGFAKE_MC

