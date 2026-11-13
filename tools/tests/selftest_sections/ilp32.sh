# ----------------------------------------------------------------------- ilp32
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Only what happens BEFORE a 32-bit compiler runs is exercised here: the SKIP
# guard, and the 64-bit gate below. The layer's verdict -- build at -m32, run,
# diff, and what the report may blame -- needs the pinned zig, and its arms are
# in :selftest_slow. (This paragraph used to say nothing anywhere tested that
# half, which was true when it was written and stopped being true there.)
#
# What IS pinned here is the regression test for a real false green:
# ilp32_test.sh used to exit 0 on a missing 32-bit compiler
# even under NO_SKIP=1, so on any machine where zig could not run, 94 targets
# went green having compiled nothing — and were invisible to the forced sweep
# built to find exactly that.
#
# The compiler is hidden by handing the runner a PATH holding only the coreutils
# it needs. That is also why this cannot simply unset PATH: the script would
# lose mktemp and fail for the wrong reason, which would pass a want_red arm
# while proving nothing.
mkdir -p "$WORK/nocc"
# A fixture PATH must cover everything ilp32_test.sh's `require` line names,
# and what tools/runner_lib.sh and tools/standin.sh probe (it sources both), or
# the probe refuses before the missing compiler is ever reached. "$SH" is in
# the list, not just `sh`: under //tools/tests:selftest_bash the runner is
# launched with bash, which then has to be findable too, or the arm dies at
# exit 127 and reports the tool it meant to hide as a harness error.
for _t in sh "$SH" mktemp dirname sed rm cat basename mkdir id awk chmod cp date env od grep head readlink; do
	ln -sf "$(command -v "$_t")" "$WORK/nocc/$_t" 2> /dev/null
done
printf 'x\n' > "$WORK/ilp32_exp.txt"
printf 'int main(void){return (0);}\n' > "$WORK/ilp32_h.c"
# ...and red for that reason: a compiler the run finds another way (an
# ILP32_CC whose long is 8 bytes) is red too, on another branch.
want_red "ilp32: NO_SKIP=1 turns a missing 32-bit compiler RED" -- \
	once env PATH="$WORK/nocc" NO_SKIP=1 "$SH" "$TOOLS/ilp32_test.sh" \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/ilp32_h.c" \
		--expected "$WORK/ilp32_exp.txt" --src "$WORK/ilp32_h.c"
want_out "ilp32: ...naming the missing compiler" 'no 32-bit compiler' -- \
	once env PATH="$WORK/nocc" NO_SKIP=1 "$SH" "$TOOLS/ilp32_test.sh" \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/ilp32_h.c" \
		--expected "$WORK/ilp32_exp.txt" --src "$WORK/ilp32_h.c"
# `env -u NO_SKIP`, not a bare `env`. This arm's whole subject is what happens
# when NO_SKIP is ABSENT, and the sweep that makes it matter is run as
# `--test_env=NO_SKIP=1`, which puts it in this script's environment and hence
# in the child's. Without the -u, the one arm describing the unforced path was
# guaranteed red under the forced sweep -- and a sweep that cannot come back
# green is a sweep nobody runs twice.
want_green "ilp32: without NO_SKIP the same case skips, so the suite stays green" -- \
	env -u NO_SKIP PATH="$WORK/nocc" "$SH" "$TOOLS/ilp32_test.sh" \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/ilp32_h.c" \
		--expected "$WORK/ilp32_exp.txt" --src "$WORK/ilp32_h.c"
# A --zig that is given is the compiler, every target's: one that does not
# exist or cannot be run is a wiring error (exit 2), never a fall back to
# the host's compilers or a SKIP that says a zig failed that never ran.
printf 'not a program\n' > "$WORK/ilp32_zig_noexec"
chmod 644 "$WORK/ilp32_zig_noexec"
want_broken "ilp32: a --zig that does not exist is a wiring error, not a skip" \
	'supplied and is not executable' -- \
	env -u NO_SKIP PATH="$WORK/nocc" "$SH" "$TOOLS/ilp32_test.sh" --zig /nonexistent \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/ilp32_h.c" \
		--expected "$WORK/ilp32_exp.txt" --src "$WORK/ilp32_h.c"
want_broken "ilp32: ...nor is one that cannot be run" \
	'supplied and is not executable' -- \
	env -u NO_SKIP PATH="$WORK/nocc" "$SH" "$TOOLS/ilp32_test.sh" --zig "$WORK/ilp32_zig_noexec" \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/ilp32_h.c" \
		--expected "$WORK/ilp32_exp.txt" --src "$WORK/ilp32_h.c"
# A scratch folder mktemp cannot make is a refusal, never a SKIP read off a
# probe that was never written.
want_broken "ilp32: no scratch folder is a refusal, not a skip" \
	'cannot create a scratch directory' -- \
	env -u NO_SKIP TMPDIR=/nonexistent "$SH" "$TOOLS/ilp32_test.sh" --zig /nonexistent \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/ilp32_h.c" \
		--expected "$WORK/ilp32_exp.txt" --src "$WORK/ilp32_h.c"
# A hand run with no --zig never tried one, and its SKIP said the hermetic
# one "failed to run" all the same (V315).
want_broken_none "ilp32: with no --zig, the SKIP says no zig failed" \
	'The hermetic one (zig' -- \
	env -u NO_SKIP PATH="$WORK/nocc" "$SH" "$TOOLS/ilp32_test.sh" \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/ilp32_h.c" \
		--expected "$WORK/ilp32_exp.txt" --src "$WORK/ilp32_h.c"
want_out   "ilp32: ...and that none was given" 'No --zig was given' -- \
	env -u NO_SKIP PATH="$WORK/nocc" "$SH" "$TOOLS/ilp32_test.sh" \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/ilp32_h.c" \
		--expected "$WORK/ilp32_exp.txt" --src "$WORK/ilp32_h.c"

# THE 64-BIT GATE, which decides both whether this layer speaks and what its
# report may claim. It is the program *_output runs (--gate-bin), handed over
# as it is, never rebuilt here: the layer used to rebuild the files itself,
# first with `cc` from PATH, then with the pinned clang and every warning
# silenced (-w) -- so code *_output reports as not building (a warning under
# -Werror) passed this gate, ran, and was said to pass "the ordinary 64-bit
# build". Every arm below reaches a verdict before any 32-bit compiler is
# looked for, so none of them needs one; the functional half, where zig
# builds and runs the program, is in :selftest_slow.
#
# The fixture is wrong on purpose, so a gate program that runs SKIPs saying
# the 64-bit build fails its fixture; a stand-in (STANDIN_BIN, from the top of
# this file, and one built here from code that only warns) SKIPs saying the
# code does not build.
mkdir -p "$WORK/i32g"
cat > "$WORK/i32g/main.c" <<'I32G_MAIN'
#include <stdio.h>

int	ft_probe_twice(int n);

int	main(void)
{
	printf("%d\n", ft_probe_twice(21));
	return (0);
}
I32G_MAIN
cat > "$WORK/i32g/twice.c" <<'I32G_TWICE'
int	ft_probe_twice(int n)
{
	return (n * 2);
}
I32G_TWICE
# Compiles, with a warning: an unused variable, an error under -Werror.
cat > "$WORK/i32g/warns.c" <<'I32G_WARNS'
int	ft_probe_twice(int n)
{
	int	unused;

	return (n * 2);
}
I32G_WARNS
printf 'not the output\n' > "$WORK/i32g/wrong.txt"
# The gate programs only this section's arms run: built in its own shard alone.
if st_mine; then
	toy_cc "$WORK/i32g/runs" "$WORK/i32g/main.c" "$WORK/i32g/twice.c"
	"$SH" "$TOOLS/student_build.sh" --cc "$CC" --out "$WORK/i32g/warns_bin" --label selftest \
		--copt -Wall --copt -Wextra --copt -Werror \
		--harness "$WORK/i32g/main.c" --src "$WORK/i32g/warns.c" > /dev/null 2>&1 &&
		[ -f "$WORK/i32g/warns_bin" ] || {
		echo "selftest: tools/student_build.sh wrote no stand-in for code that only warns" >&2
		exit 2
	}
fi
i32g_run() {
	env -u NO_SKIP "$SH" "$TOOLS/ilp32_test.sh" \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/i32g/main.c" \
		--expected "$WORK/i32g/wrong.txt" --src "$WORK/i32g/twice.c" "$@"
}
want_out "ilp32: a gate program that fails its fixture skips the layer" \
	"already fails this exercise's" -- i32g_run --gate-bin "$WORK/i32g/runs"
want_out "ilp32: a stand-in for a gate skips it, saying the code does not build" \
	"your code does not build as a 64-bit program" -- i32g_run --gate-bin "$STANDIN_BIN"
want_out "ilp32: ...as does code that only warns, which -Werror stopped" \
	"your code does not build as a 64-bit program" -- i32g_run --gate-bin "$WORK/i32g/warns_bin"
want_broken_none "ilp32: ...and that is no failed fixture" \
	"already fails" -- i32g_run --gate-bin "$WORK/i32g/warns_bin"
want_out "ilp32: a stand-in for nothing to build says there is nothing yet" \
	"there is nothing to build yet" -- i32g_run --gate-bin "$WORK/standin/empty"
# A gate the differ cannot judge (exit 2 or more: here a program it cannot
# start) is unknown: said, and the layer goes on rather than going quiet --
# a gate that cannot answer is never why a layer stayed silent.
printf 'not a program\n' > "$WORK/i32g/nonexec"
chmod 644 "$WORK/i32g/nonexec"
want_out "ilp32: a gate the differ cannot judge is said, and runs on" \
	"could not be judged (its differ exited 2)" -- i32g_run --gate-bin "$WORK/i32g/nonexec"
want_broken_none "ilp32: ...and the layer does not skip at the gate" \
	"nothing platform-specific to report" -- i32g_run --gate-bin "$WORK/i32g/nonexec"
# Another exercise's files are never linked in (tools/defs.bzl, c_function:
# `deps` and the `-- FILE...` that carried its files here are gone). A `--`
# is an option this runner does not know, like any other; and so are the
# options of the rebuild the gate once was.
want_broken "ilp32: '--' and another exercise's files after it refuse" \
	"unknown option: --" -- i32g_run --gate-bin "$WORK/i32g/runs" -- "$WORK/i32g/twice.c"
want_broken "ilp32: --cc is no option: the gate is *_output's program" \
	"unknown option: --cc" -- i32g_run --cc "$CC"
want_broken "ilp32: ...nor --lib64, which only that rebuild linked" \
	"unknown option: --lib64" -- i32g_run --lib64 "$WORK/i32g/twice.c"

# WHAT THE REPORT SAYS WHEN THE 32-BIT RUN NEVER HAPPENED (V179). Under load,
# the test's own time ran out after the 64-bit gate had passed and before
# diff_output.sh could start the 32-bit program; the report under its "could
# not start" line then said "this one does not" pass and "It ran to the end
# and printed something else, so the difference is the type model" -- over
# correct code, about a run that never took place.
#
# Reaching that moment here needs a 32-bit build without zig, and a deadline
# that has passed on the 32-bit run only: each stand-in differ below knows the
# gate's run by its program (--bin), and leaves it to the real differ. The compiler is a stand-in,
# ILP32_CC: it builds natively with the -m32 taken out, and builds the type
# model's probe as a script that prints "4 4", the ILP32 answer, so the
# layer goes on as over a real 32-bit compiler. The differ is diff_output.sh itself,
# handed an expired RL_DEADLINE on the one call that carries --status-file:
# the 32-bit run. A third differ reports a timeout the test's own budget cut
# ("timeout", "clamped 2"), which is not the long-width loop the plain timeout
# paragraph names.
mkdir -p "$WORK/i32n"
printf '42\n' > "$WORK/i32n/right.txt"
printf '#!/bin/sh\nfor _a; do case $_a in */model.c) printf "#!/bin/sh\\necho 4 4\\n" > "${_a%%.c}"; chmod +x "${_a%%.c}"; exit 0 ;; esac; done\nfor _a; do shift; [ "$_a" = -m32 ] || set -- "$@" "$_a"; done\nexec "%s" "$@"\n' \
	"$CC" > "$WORK/i32n/cc32"
# The same stand-in, refusing the type model's probe: the layer cannot
# confirm int and long are 32 bits, so it never says they are.
printf '#!/bin/sh\nfor _a; do case $_a in */model.c) echo "cc32: no 32-bit headers here" >&2; exit 1 ;; esac; done\nfor _a; do shift; [ "$_a" = -m32 ] || set -- "$@" "$_a"; done\nexec "%s" "$@"\n' \
	"$CC" > "$WORK/i32n/cc32nomodel"
printf '#!/bin/sh\ncase " $* " in *" --bin %s "*) ;; *" --status-file "*) RL_DEADLINE=1 RL_CLOCK=uptime; export RL_DEADLINE RL_CLOCK ;; esac\nexec "%s" "%s/diff_output.sh" "$@"\n' \
	"$WORK/i32g/runs" "$SH" "$TOOLS" > "$WORK/i32n/starve"
printf '#!/bin/sh\ncase " $* " in *" --bin %s "*) exit 0 ;; esac\n_sf=""\nwhile [ $# -gt 0 ]; do [ "$1" = --status-file ] && _sf=$2; shift; done\n[ -n "$_sf" ] || exit 0\nprintf "timeout\\nclamped 2\\n" > "$_sf"\nexit 1\n' \
	"$WORK/i32g/runs" > "$WORK/i32n/cut"
chmod +x "$WORK/i32n/cc32" "$WORK/i32n/cc32nomodel"
i32n_run() {  # i32n_run DIFFER [CC32]
	env -u NO_SKIP ILP32_CC="${2:-$WORK/i32n/cc32}" "$SH" "$TOOLS/ilp32_test.sh" \
		--differ "$1" --harness "$WORK/i32g/main.c" --gate-bin "$WORK/i32g/runs" \
		--expected "$WORK/i32n/right.txt" --src "$WORK/i32g/twice.c"
}
# The control: the same stand-in compiler, the real differ, no deadline. If
# this were red, every arm below would be red for that reason instead.
want_green "ilp32: (control) the stand-in 32-bit build passes" -- \
	i32n_run "$TOOLS/diff_output.sh"
# A compiler whose type model's probe does not build: nothing confirmed int
# and long are 32 bits, so the layer checked nothing it claims to.
want_red "ilp32: a type model's probe that does not build is red under NO_SKIP=1" -- \
	env NO_SKIP=1 ILP32_CC="$WORK/i32n/cc32nomodel" "$SH" "$TOOLS/ilp32_test.sh" \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/i32g/main.c" --gate-bin "$WORK/i32g/runs" \
		--expected "$WORK/i32n/right.txt" --src "$WORK/i32g/twice.c"
want_out "ilp32: ...and a SKIP without it, showing why" 'no 32-bit headers here' -- \
	i32n_run "$TOOLS/diff_output.sh" "$WORK/i32n/cc32nomodel"
want_broken_none "ilp32: ...never saying int and long are 32 bits" 'both 32 bits here' -- \
	i32n_run "$TOOLS/diff_output.sh" "$WORK/i32n/cc32nomodel"
# A library member's sources, whose header only the Makefile's -I reaches
# (--inc-file, tools/student_build.sh --includes-out): compiled with no -I,
# the 32-bit build found no header and said the code "builds as a 64-bit
# program, but not for a 32-bit target" (V198).
mkdir -p "$WORK/i32inc/inc"
printf 'int\tft_probe_twice(int n);\n' > "$WORK/i32inc/inc/toy_i32.h"
printf '#include "toy_i32.h"\n\nint\tft_probe_twice(int n)\n{\n\treturn (n * 2);\n}\n' \
	> "$WORK/i32inc/twice.c"
printf '%s\n' "$WORK/i32inc/inc" > "$WORK/i32inc/includes.txt"
i32inc_run() {
	env -u NO_SKIP ILP32_CC="$WORK/i32n/cc32" "$SH" "$TOOLS/ilp32_test.sh" \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/i32g/main.c" --gate-bin "$WORK/i32g/runs" \
		--expected "$WORK/i32n/right.txt" --src "$WORK/i32inc/twice.c" "$@"
}
want_red   "ilp32: a header only the Makefile's -I reaches, without it" -- i32inc_run
want_green "ilp32: ...is found through --inc-file" -- \
	i32inc_run --inc-file "$WORK/i32inc/includes.txt"
want_red "ilp32: a 32-bit run that never started is red" -- i32n_run "$WORK/i32n/starve"
want_out "ilp32: ...and the report says it never ran" \
	"The 32-bit program never ran" -- i32n_run "$WORK/i32n/starve"
want_broken_none "ilp32: ...and does not blame the type model" \
	"type model" -- i32n_run "$WORK/i32n/starve"
want_broken_none "ilp32: ...nor say it ran to the end" \
	"ran to the end" -- i32n_run "$WORK/i32n/starve"
want_broken_none "ilp32: ...nor that this build fails where 64-bit passes" \
	"this one does not" -- i32n_run "$WORK/i32n/starve"
# THE GATE'S OWN RUN, CUT BY THE TEST'S TIME. Its differ writes "notrun" (or a
# clamped "timeout") and exits 1, as it does for a failed fixture; read as
# one, the layer skipped green saying the 64-bit build already fails its
# fixture, over a gate program that passes it. Nothing was established, so it
# is unknown: said, and the layer runs on, to a red its 32-bit run explains.
i32t_run() {
	env -u NO_SKIP RL_DEADLINE=1 RL_CLOCK=uptime ILP32_CC="$WORK/i32n/cc32" "$SH" "$TOOLS/ilp32_test.sh" \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/i32g/main.c" --gate-bin "$WORK/i32g/runs" \
		--expected "$WORK/i32n/right.txt" --src "$WORK/i32g/twice.c"
}
want_broken_none "ilp32: a gate the test's time ran out on is no failed fixture" \
	"already fails" -- i32t_run
want_out "ilp32: ...it says the time ran out, and the layer runs on" \
	"time ran out before the 64-bit program" -- i32t_run
want_out "ilp32: ...to a red that says the 32-bit run never happened" \
	"The 32-bit program never ran" -- i32t_run
want_out "ilp32: a timeout the test's budget cut says so" \
	"what was left of the whole test's" -- i32n_run "$WORK/i32n/cut"
want_broken_none "ilp32: ...and does not point at a long-width loop" \
	"Look for a loop" -- i32n_run "$WORK/i32n/cut"
want_broken_none "ilp32: ...nor say this build fails where 64-bit passes" \
	"this one does not" -- i32n_run "$WORK/i32n/cut"
# THE SAME CUT AFTER A ROW WAS JUDGED WRONG is a verdict, and the real differ
# says so ("The 1 row(s) marked FAIL above it are a verdict all the same"),
# leaving its "this test's own time limit" mark out for first_red. This
# report once read "clamped" alone, called it no finding, and put the mark
# back -- first_red then filed a wrong answer as a busy machine. The stand-in
# 32-bit build (STANDIN32, from a second wrapper) prints a wrong first row and
# never ends at the third; the 64-bit gate, built without it, prints all five.
cat > "$WORK/i32n/wh.c" <<'I32N_WH'
#include <stdio.h>

int	main(void)
{
	int	i;

	for (i = 1; i <= 5; i++)
	{
#ifdef STANDIN32
		if (i == 1)
		{
			printf("case 1\tnot v1\n");
			continue ;
		}
		if (i == 3)
			for (;;)
				;
#endif
		printf("case %d\tv%d\n", i, i);
	}
	return (0);
}
I32N_WH
! st_mine || toy_cc "$WORK/i32n/wh_gate" "$WORK/i32n/wh.c" "$TOOLS/unbuffered_stdout.c"
printf '#!/bin/sh\nexec "%s" -DSTANDIN32 "$@"\n' "$WORK/i32n/cc32" > "$WORK/i32n/cc32w"
chmod +x "$WORK/i32n/cc32w"
i32w_run() {
	env -u NO_SKIP -u RL_DEADLINE -u RL_BUDGET TEST_TIMEOUT=10 RL_MARGIN=1 \
		ILP32_CC="$WORK/i32n/cc32w" "$SH" "$TOOLS/ilp32_test.sh" \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/i32n/wh.c" \
		--harness-src "$TOOLS/unbuffered_stdout.c" --gate-bin "$WORK/i32n/wh_gate" \
		--expected "$WORK/five.txt" --src "$WORK/i32g/twice.c"
}
later_red_out "ilp32: a wrong row, then the test's time: the verdict stands" \
	"marked FAIL above it are a verdict" -- i32w_run
later_red_none "ilp32: ...and the report does not call it no finding" \
	"this says nothing" -- i32w_run
later_red_none "ilp32: ...nor carry the mark first_red files as slow" \
	"this test's own time limit" -- i32w_run
# A differ that fails the 32-bit run and records nothing: a broken contract,
# and still no reason to say how the run ended.
printf '#!/bin/sh\ncase " $* " in *" --bin %s "*) exit 0 ;; *" --status-file "*) exit 1 ;; esac\nexit 0\n' \
	"$WORK/i32g/runs" > "$WORK/i32n/mute"
want_out "ilp32: a red with no ending recorded says it was not recorded" \
	"how it ended was" -- i32n_run "$WORK/i32n/mute"
want_broken_none "ilp32: ...and does not blame the type model" \
	"type model" -- i32n_run "$WORK/i32n/mute"

