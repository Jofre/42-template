# ------------------------------------------------------------------ allocfail
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The layer that makes malloc say no, one allocation at a time. Both directions
# matter more than usual here, because the whole point is a branch that nothing
# else in the repo has ever executed: a version that reds everything would be
# indistinguishable from a working one on the only exercise it is wired to.
cat > "$WORK/af_good.c" <<'AF_GOOD'
#include <stdlib.h>

void	*af_target(void)
{
	char	*p;

	p = malloc(16);
	if (!p)
		return (NULL);
	p[0] = 'x';
	return (p);
}
AF_GOOD
cat > "$WORK/af_bad.c" <<'AF_BAD'
#include <stdlib.h>

void	*af_target(void)
{
	char	*p;

	p = malloc(16);
	p[0] = 'x';
	return (p);
}
AF_BAD
cat > "$WORK/af_case.c" <<'AF_CASE'
void	*af_target(void);

void	*af_case(void)
{
	return (af_target());
}
AF_CASE

# af_probe SRC HARNESS LABEL [FLAG...] -- the function probe as the macro
# runs it: SRC built over HARNESS with the pinned build and the shim.
af_probe() {
	_ap_s=$1
	_ap_h=$2
	_ap_l=$3
	shift 3
	"$SH" "$TOOLS/allocfail_check.sh" $BUILD_PIN --src "$_ap_s" \
		--harness "$_ap_h" --shim "$TOOLS/allocfail_shim.c" --label "$_ap_l" "$@"
}
want_green "allocfail: checking malloc's answer survives a refusal" -- \
	af_probe "$WORK/af_good.c" "$WORK/af_case.c" af_good
want_red   "allocfail: using the pointer regardless is caught" -- \
	af_probe "$WORK/af_bad.c" "$WORK/af_case.c" af_bad
# A scratch folder mktemp cannot make (TMPDIR gone, read-only or full) is a
# refusal, and it never leaves the runner holding an empty WORK: made
# absolute, that was the folder the run started from, and the exit trap
# removed it. The run starts in a folder of its own, holding a file that must
# be there after, and a link to each entry of this one, so the paths the arm
# names still resolve and a removal there removes links, never what they name.
af_notmp() {
	mkdir -p "$WORK/afsent"
	: > "$WORK/afsent/keep"
	for _an_e in * .[!.]*; do
		[ -e "$_an_e" ] && ln -sfn "$PWD/$_an_e" "$WORK/afsent/$_an_e"
	done
	(cd "$WORK/afsent" && TMPDIR=/nonexistent af_probe "$WORK/af_good.c" "$WORK/af_case.c" af_good)
	_an_rc=$?
	[ -f "$WORK/afsent/keep" ] && return "$_an_rc"
	echo "the folder the run started from was removed"
	return 3
}
want_broken "allocfail: no scratch folder is a refusal, and removes nothing" \
	'cannot create a scratch directory' -- af_notmp
# A library member's source whose header only the Makefile's -I reaches
# (--inc-file, tools/student_build.sh --includes-out), compiled as every
# build of the library compiles it (V198).
mkdir -p "$WORK/afinc/inc"
printf 'void\t*af_target(void);\n' > "$WORK/afinc/inc/toy_af.h"
{ printf '#include "toy_af.h"\n'; cat "$WORK/af_good.c"; } > "$WORK/afinc/af_good.c"
printf '%s\n' "$WORK/afinc/inc" > "$WORK/afinc/includes.txt"
want_green "allocfail: a header only the Makefile's -I reaches (--inc-file)" -- \
	af_probe "$WORK/afinc/af_good.c" "$WORK/af_case.c" af_good --inc-file "$WORK/afinc/includes.txt"
# The probe is built with the pinned clang-12 and ld.bfd: it took `cc` from
# the box, then gcc, clang, clang-12 or gcc-10 (TO VERIFY V38).
want_broken "allocfail: --src and no --cc refuses, never takes the box's" \
	'--cc is required with --src' -- \
	"$SH" "$TOOLS/allocfail_check.sh" --src "$WORK/af_good.c" \
		--harness "$WORK/af_case.c" --shim "$TOOLS/allocfail_shim.c" --label af_good
# A pinned toolchain whose link ignores -Wl,--wrap=malloc is the harness's
# fault, exit 2, as one that ignores --wrap=free is: it was a green SKIP, a
# PASSED target that had refused no allocation. The compiler is the pinned
# clang-12 behind a wrapper that drops every --wrap.
printf '#!/bin/sh\nfor _a; do shift; case $_a in -Wl,--wrap=*) ;; *) set -- "$@" "$_a" ;; esac; done\nexec "%s" "$@"\n' \
	"$CLANG" > "$WORK/af_nowrap_cc"
chmod +x "$WORK/af_nowrap_cc"
# shellcheck disable=SC2086
want_broken "allocfail: a link that ignores --wrap=malloc is refused" \
	'does not honour -Wl,--wrap=malloc' -- \
	"$SH" "$TOOLS/allocfail_check.sh" --cc "$WORK/af_nowrap_cc" $CLANG_LIBS --cc-under "$CLANG" \
		--ld "$LD" --ld-lib "$LD_LIB" --src "$WORK/af_good.c" \
		--harness "$WORK/af_case.c" --shim "$TOOLS/allocfail_shim.c" --label af_good
# PAST --max-inject THE SWEEP SAMPLES, TO THE LAST REQUEST. A function that
# allocates through its input checks its first requests and not its last:
# refusing only the first --max-inject never reached it, and the layer said
# "PASS (partial)" over the one unguarded call. af_last_bad's twentieth
# request is used unchecked; with a budget of six, the sweep has to reach it.
cat > "$WORK/af_last_bad.c" <<'AF_LAST'
#include <stdlib.h>

void	*af_target(void)
{
	char	*p[20];
	int		i;

	i = 0;
	while (i < 19)
	{
		p[i] = malloc(8);
		if (!p[i])
		{
			while (--i >= 0)
				free(p[i]);
			return (NULL);
		}
		i++;
	}
	p[19] = malloc(8);
	p[19][0] = 'x';
	while (--i >= 0)
		free(p[i]);
	return (p[19]);
}
AF_LAST
want_red   "allocfail: past --max-inject, the sweep samples to the last request" -- \
	env ALLOCFAIL_MAX=6 "$SH" "$TOOLS/allocfail_check.sh" $BUILD_PIN --src "$WORK/af_last_bad.c" \
		--harness "$WORK/af_case.c" --shim "$TOOLS/allocfail_shim.c" --label af_last_bad
want_out   "allocfail: ...and says which it refused" 'then spread evenly to the last' -- \
	env ALLOCFAIL_MAX=6 "$SH" "$TOOLS/allocfail_check.sh" $BUILD_PIN --src "$WORK/af_last_bad.c" \
		--harness "$WORK/af_case.c" --shim "$TOOLS/allocfail_shim.c" --label af_last_bad
# THE SENTENCE IT APPLIES comes from the call site (--rule, a file the macro
# writes, as valgrind_test.sh's --rule is), and is the only one the report
# quotes; with none, it quotes none. It used to send every exercise to "if an
# error occurs", which one subject says (finding 082).
printf 'Toy, p.5: "Return NULL when memory runs out."\n' > "$WORK/af_contract.txt"
: > "$WORK/af_contract_empty.txt"
want_out   "allocfail: the FAIL quotes the call site's sentence" \
	'Toy, p.5: "Return NULL when memory runs out."' -- \
	af_probe "$WORK/af_bad.c" "$WORK/af_case.c" af_bad --rule "$WORK/af_contract.txt"
want_broken_none "allocfail: ...and without one, quotes nothing" 'call site in BUILD.bazel' -- \
	af_probe "$WORK/af_bad.c" "$WORK/af_case.c" af_bad
want_broken_none "allocfail: ...nor a sentence of another subject" 'if an error occurs' -- \
	af_probe "$WORK/af_bad.c" "$WORK/af_case.c" af_bad
# Nor does its closing text say what "no subject" asks: whether one does is
# the call site's to say, and the runner cannot know (finding 082).
want_broken_none "allocfail: ...nor what no subject asks" 'No subject here' -- \
	af_probe "$WORK/af_bad.c" "$WORK/af_case.c" af_bad --rule "$WORK/af_contract.txt"
want_broken "allocfail: an empty --rule file is refused" 'no sentence in --rule' -- \
	af_probe "$WORK/af_bad.c" "$WORK/af_case.c" af_bad --rule "$WORK/af_contract_empty.txt"
want_broken "allocfail: a --rule file that is not there is refused" 'no sentence in --rule' -- \
	af_probe "$WORK/af_bad.c" "$WORK/af_case.c" af_bad --rule "$WORK/af_no_such_rule.txt"
# AN ERROR THAT IS A VALUE (finding 075). A function whose subject reports the
# error as -1 goes through a harness that turns -1 into NULL and anything else
# into a sentinel pointer -- and the report said "still returned a pointer"
# about a function that had returned 0. The harness now says in words what
# the call returned (af_note), and the row is WRONG-RET, with those words.
cat > "$WORK/af_int_bad.c" <<'AF_INT_BAD'
#include <stdlib.h>

int	af_fill(int **out)
{
	*out = malloc(4 * sizeof(int));
	if (!*out)
		return (0);
	return (4);
}
AF_INT_BAD
cat > "$WORK/af_int_good.c" <<'AF_INT_GOOD'
#include <stdlib.h>

int	af_fill(int **out)
{
	*out = malloc(4 * sizeof(int));
	if (!*out)
		return (-1);
	return (4);
}
AF_INT_GOOD
cat > "$WORK/af_int_case.c" <<'AF_INT_CASE'
#include <stdio.h>

extern const char	*af_note;
static int			g_not_reported;
static char			g_note[64];

int	af_fill(int **out);

void	*af_case(void)
{
	int	*p;
	int	n;

	p = 0;
	n = af_fill(&p);
	if (n == -1)
		return (0);
	snprintf(g_note, sizeof(g_note), "returned %d, not -1", n);
	af_note = g_note;
	if (p)
		return (p);
	return (&g_not_reported);
}
AF_INT_CASE
want_red   "allocfail: a wrong value returned on a refusal is caught" -- \
	af_probe "$WORK/af_int_bad.c" "$WORK/af_int_case.c" af_int_bad
want_out   "allocfail: ...as WRONG-RET, with the value it returned" \
	'WRONG-RET  allocation #1 failed, and it returned 0, not -1' -- \
	af_probe "$WORK/af_int_bad.c" "$WORK/af_int_case.c" af_int_bad
want_broken_none "allocfail: ...never as a pointer it did not return" 'returned a pointer' -- \
	af_probe "$WORK/af_int_bad.c" "$WORK/af_int_case.c" af_int_bad
want_green "allocfail: the error value the harness reads as NULL passes" -- \
	af_probe "$WORK/af_int_good.c" "$WORK/af_int_case.c" af_int_good
# The note is the rest of the report line, after the counts the leak target
# added (live=, bytes=): a note whose own words look like a field is never
# read as one. Read greedily, "seen=9 result=null" in a note made this wrong
# value a green "returned NULL".
sed 's/"returned %d, not -1"/"returned %d, seen=9 result=null live=3"/' \
	"$WORK/af_int_case.c" > "$WORK/af_int_case_words.c"
want_red   "allocfail: a note's words are never read as the report's fields" -- \
	af_probe "$WORK/af_int_bad.c" "$WORK/af_int_case_words.c" af_int_bad
want_out   "allocfail: ...and the row quotes the note whole" \
	'WRONG-RET  allocation #1 failed, and it returned 0, seen=9 result=null live=3' -- \
	af_probe "$WORK/af_int_bad.c" "$WORK/af_int_case_words.c" af_int_bad

# --leaks (finding 084): what a function leaves allocated on a run that
# reported the error, judged by its own target at robust. Two toys that take a
# pair of blocks and report a refused second one; af_drop forgets the first,
# af_tidy hands it back. The basic sweep stays green on both -- it does not ask
# -- and says on that PASS what it did not ask. A toy that does not report the
# error is the basic sweep's finding and NOT JUDGED here, so it is not red
# twice; a toy whose every run fails to report leaves nothing to judge.
for _af in drop tidy; do
	{
		printf '#include <stdlib.h>\n\nvoid\t*af_target(void)\n{\n'
		printf '\tchar\t**pair;\n\n\tpair = malloc(2 * sizeof(char *));\n'
		printf '\tif (!pair)\n\t\treturn (NULL);\n\tpair[0] = malloc(4);\n'
		printf '\tpair[1] = malloc(4);\n\tif (!pair[0] || !pair[1])\n\t{\n'
		[ "$_af" = drop ] || printf '\t\tfree(pair[0]);\n\t\tfree(pair[1]);\n\t\tfree(pair);\n'
		printf '\t\treturn (NULL);\n\t}\n\treturn (pair);\n}\n'
	} > "$WORK/af_$_af.c"
done
af_leaks() {  # af_leaks TOY [--leaks]
	_t=$1; shift
	env -u NO_SKIP "$SH" "$TOOLS/allocfail_check.sh" $BUILD_PIN --src "$WORK/af_$_t.c" \
		--harness "$WORK/af_case.c" --shim "$TOOLS/allocfail_shim.c" --label "af_$_t" "$@"
}
want_green "allocfail: a leak on the error path is not the basic sweep's" -- af_leaks drop
want_out   "allocfail: ...whose PASS says what it did not ask" \
	'What this layer does NOT ask' -- af_leaks drop
want_red   "allocfail --leaks: a block left on the error path is red" -- af_leaks drop --leaks
want_out   "allocfail --leaks: ...and the row says what was left" \
	'block(s), ' -- af_leaks drop --leaks
want_green "allocfail --leaks: releasing it all is green" -- af_leaks tidy --leaks
want_out   "allocfail --leaks: ...and its PASS says whose rule it is" \
	"Whose rule this is: the repo's" -- af_leaks tidy --leaks
# af_mute is refused and hands back a pointer of its own instead of NULL:
# the basic sweep's NOT-NULL, and not this target's to judge.
printf '#include <stdlib.h>\n\nvoid\t*af_target(void)\n{\n\tstatic char\tnone[1];\n\tchar\t\t*p;\n\n\tp = malloc(16);\n\tif (!p)\n\t\treturn (none);\n\tp[0] = 0;\n\treturn (p);\n}\n' \
	> "$WORK/af_mute.c"
want_out   "allocfail --leaks: a run that did not report is not judged" \
	'NOT-JUDGED' -- af_leaks mute --leaks
want_green "allocfail --leaks: ...so nothing judged is a skip" -- af_leaks mute --leaks
want_red   "allocfail --leaks: ...which NO_SKIP=1 makes red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/allocfail_check.sh" $BUILD_PIN --src "$WORK/af_mute.c" \
		--harness "$WORK/af_case.c" --shim "$TOOLS/allocfail_shim.c" --label af_mute --leaks
want_red   "allocfail --leaks: a crash on the error path still fails" -- af_leaks bad --leaks

# --bin: a PROGRAM, whose own main() runs (finding 150). The toy keeps a copy
# of each argument and reports a refused copy on stderr; MODE_* builds the
# variants: one that checks and tidies, one that never looks at malloc's
# answer, one that checks and keeps what it had, one that stops answering;
# and, with AF_BUS, one that raises SIGBUS on a refusal.
# Linked as c_program links exNN_bin_allocfail: beside allocfail_program.c,
# with malloc and free wrapped.
cat > "$WORK/afp.c" <<'AF_PROG'
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int	main(int ac, char **av)
{
	char	**keep;
	int		i;

	keep = malloc(sizeof(char *) * (size_t)ac);
	if (!keep)
		return (1);
	i = 1;
	while (i < ac)
	{
		keep[i] = malloc(strlen(av[i]) + 1);
		if (MODE_CHECK && !keep[i])
		{
			write(2, "no memory\n", 10);
#ifdef AF_BUS
			raise(SIGBUS);
#endif
			while (MODE_TIDY && --i >= 1)
				free(keep[i]);
			if (MODE_TIDY)
				free(keep);
			while (MODE_HANG)
				;
			return (1);
		}
		strcpy(keep[i], av[i]);
		i++;
	}
	while (--i >= 1)
		free(keep[i]);
	free(keep);
	return (0);
}
AF_PROG
# The afp_* toys are this section's arms' alone: built in its own shard.
if st_mine; then
	for _v in good:1:1:0 bad:0:1:0 keep:1:0:0 stuck:1:1:1; do
		IFS=: read -r _n _c _t _h <<AF_V
$_v
AF_V
		toy_cc "$WORK/afp_$_n" -w -DMODE_CHECK="$_c" -DMODE_TIDY="$_t" -DMODE_HANG="$_h" \
			"$WORK/afp.c" "$TOOLS/allocfail_program.c" -Wl,--wrap=malloc -Wl,--wrap=free
	done
	toy_cc "$WORK/afp_bus" -w -DMODE_CHECK=1 -DMODE_TIDY=1 -DMODE_HANG=0 -DAF_BUS \
		"$WORK/afp.c" "$TOOLS/allocfail_program.c" -Wl,--wrap=malloc -Wl,--wrap=free
fi
printf 'int\tmain(void)\n{\n\treturn (0);\n}\n' > "$WORK/afp_none.c"
! st_mine || toy_cc "$WORK/afp_none" -w "$WORK/afp_none.c" "$TOOLS/allocfail_program.c" \
	-Wl,--wrap=malloc -Wl,--wrap=free
afp() {  # afp TOY [FLAG...] -- the toy program on three arguments
	_t=$1; shift
	"$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_$_t" --label "afp_$_t" "$@" -- aa bb cc
}
want_green "allocfail --bin: a program that checks and stops is green" -- afp good
want_red   "allocfail --bin: one that uses a refused block is red" -- afp bad
want_out   "allocfail --bin: ...and the row names the signal" 'CRASH' -- afp bad
# Each signal by the one table every layer reads (rl_signame): this one
# used to read "killed by signal 7" here, and SIGBUS everywhere else.
want_out   "allocfail --bin: ...SIGBUS by its name" 'killed by SIGBUS' -- afp bus
# A plain run that floods its output is said as the flood it was: it read
# "(signal 25)", then "(SIGXFSZ (file size limit exceeded))", the signal
# that stops a write past the budget, which tells the student nothing about
# what their program did.
printf '#!/bin/sh\nexec head -c 20000 /dev/zero\n' > "$WORK/afp_flood"
chmod +x "$WORK/afp_flood"
want_out   "allocfail --bin: a plain run that floods says so" \
	'kept writing past its output budget' -- env ALLOCFAIL_LOG_CAP=4096 \
		"$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_flood" --label afp_flood -- aa
# Every CRASH row stays inside 80 columns, whichever signal it names: the
# sweep table is read in a terminal. Each row is rendered by the runner's
# own signal_name and rows(), for RL_SIG 1..64 and for none at all.
sed -n -e '/^signal_name() {/,/^}/p' -e '/^rows() {/,/^}/p' "$TOOLS/allocfail_check.sh" \
	> "$WORK/af-rows.sh"
af_crash_rows() {  # af_crash_rows -- every CRASH row too wide, unbalanced or unnamed
	"$SH" -c '. "$1"; . "$2"; mkdir -p "$3"; WORK=$3
		RL_SIG=""; _n=0
		while [ "$_n" -le 64 ]; do
			printf "9999\tCRASH\tkilled by %s\n" "$(signal_name)" > "$WORK/sweep"
			rows
			_n=$((_n + 1)); RL_SIG=$_n
		done' _ "$TOOLS/runner_lib.sh" "$WORK/af-rows.sh" "$WORK/afrows" |
		awk '{ o = gsub(/\(/, "("); c = gsub(/\)/, ")") }
			length($0) > 80 || o != c { print "bad: " $0; bad = 1 }
			NR == 1 && index($0, "killed by a stop from outside") == 0 { print "no stop: " $0; bad = 1 }
			END { if (NR != 65) { print NR " rows"; bad = 1 }; exit bad }'
}
want_green "allocfail: every CRASH row fits 80 columns, for any signal" -- af_crash_rows
want_red   "allocfail --bin: one that never ends after a refusal is red" -- \
	env ALLOCFAIL_TIMEOUT=2 "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_stuck" \
		--label afp_stuck -- aa bb cc
# A limit of 0 seconds is refused, as a cap of 0 injections is: the waiter
# arms no alarm for it, so a run that never ends ran until Bazel killed the
# test, with nothing in its log. A program that ends is enough to show it.
want_broken "allocfail --bin: ALLOCFAIL_TIMEOUT=0 is refused" '--timeout must be at least 1' -- \
	env ALLOCFAIL_TIMEOUT=0 "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_good" \
		--label afp_good -- aa bb cc
want_broken "allocfail --bin: ...and so is --timeout 0" '--timeout must be at least 1' -- \
	afp good --timeout 0
want_green "allocfail --bin: what it printed and returned is not judged" -- afp keep
want_red   "allocfail --bin --leaks: a block held at exit is red" -- afp keep --leaks
want_out   "allocfail --bin --leaks: ...and the row says what was held" \
	'still allocated at exit' -- afp keep --leaks
want_green "allocfail --bin --leaks: releasing it all is green" -- afp good --leaks
want_green "allocfail --bin: asking for no memory passes, under NO_SKIP too" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_none" --label afp_none
# ...but is not headed OK: nothing was refused, so nothing was checked, and a
# green that reads like a verdict is the shape design.md ranks worst.
want_out   "allocfail --bin: ...headed NOTHING TO REFUSE" 'NOTHING TO REFUSE' -- \
	env NO_SKIP=1 "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_none" --label afp_none
want_broken_none "allocfail --bin: ...and never OK" 'allocfail_check: OK' -- \
	env NO_SKIP=1 "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_none" --label afp_none

# THE CASE'S RUN, AND ITS GATE'S. A case can hand the program more arguments
# in a file and run it as ./NAME from a folder holding files of its own
# (c_program's argv_file and cwd_files); the sweep runs it that way, and its
# gate too. Rush 02's one-argument case runs beside numbers.dict, and its sweep
# ran from a folder with no dictionary: the gate was red on every correct
# program and SKIPped, and under NO_SKIP=1 only the missing-dictionary path's
# requests were refused. The toy asks for memory only where toy.cfg is beside
# it, and prints whether it found it.
cat > "$WORK/afp_beside.c" <<'AF_BESIDE'
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

int	main(void)
{
	char	*p;
	int		fd;

	fd = open("toy.cfg", O_RDONLY);
	if (fd < 0)
	{
		write(1, "none\n", 5);
		return (0);
	}
	close(fd);
	p = malloc(4);
	if (!p)
		return (1);
	free(p);
	write(1, "found\n", 6);
	return (0);
}
AF_BESIDE
! st_mine || toy_cc "$WORK/afp_beside" -w "$WORK/afp_beside.c" "$TOOLS/allocfail_program.c" \
	-Wl,--wrap=malloc -Wl,--wrap=free
! st_mine || toy_cc "$WORK/afp_beside_plain" -w "$WORK/afp_beside.c"
printf 'found\n' > "$WORK/afp_found.txt"
printf 'a toy file\n' > "$WORK/afp_cfg.txt"
printf 'dd\nee\n' > "$WORK/afp_more.argv"
afp_beside() {  # afp_beside [FLAG...] -- the toy, gated on its own case
	env -u NO_SKIP "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_beside" --label afp_beside \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/afp_beside_plain" \
		--gate-expected "$WORK/afp_found.txt" "$@" --
}
want_out   "allocfail --bin --run-as: the sweep runs from the case's folder" \
	'It asks for memory 1 time(s)' -- \
	afp_beside --run-as toy --cwd-file "toy.cfg=$WORK/afp_cfg.txt"
want_out   "allocfail --bin --run-as: ...and says where it ran" \
	'toy.cfg  a copy of' -- \
	afp_beside --run-as toy --cwd-file "toy.cfg=$WORK/afp_cfg.txt" --show-run bazel-bin/toy
want_out   "allocfail --bin: without the folder, its gate is red" 'SKIP' -- afp_beside
want_broken "allocfail --bin: --cwd-file without --run-as is refused" \
	'--cwd-file stages a file' -- afp_beside --cwd-file "toy.cfg=$WORK/afp_cfg.txt"
want_broken "allocfail: a function's probe takes no run folder" \
	"a function's probe takes none" -- \
	af_probe "$WORK/af_good.c" "$WORK/af_case.c" af_good --run-as toy
want_out   "allocfail --bin --argv-file: the file's arguments follow the others" \
	'It asks for memory 6 time(s)' -- afp good --argv-file "$WORK/afp_more.argv"

# A SURVIVE CASE'S SWEEP (--survive) waits on ANOTHER case, written out
# whole in its --gate-* options, as its valgrind arm does: a program nobody
# has written ends by itself and allocates nothing, so a sweep of it run
# ungated refused nothing and passed (V282). Its gate is handed nothing of
# the sweep's run: afp_beside_plain prints "none" from a folder with no
# toy.cfg, which the gate case expects, and "found" from the sweep's folder.
printf 'none\n' > "$WORK/afp_none.txt"
afp_survive() {  # afp_survive TOY EXPECTED [FLAG...] -- TOY's sweep, a survive case's
	_t=$1; _e=$2; shift 2
	env -u NO_SKIP "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_$_t" --label "afp_$_t" \
		--survive --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/afp_beside_plain" \
		--gate-expected "$WORK/$_e" --gate-label ex00_one_output "$@" -- aa bb cc
}
want_green "allocfail --survive: SKIPs while the case it waits on is red" -- \
	afp_survive bad afp_found.txt
want_out   "allocfail --survive: ...naming that case" \
	"SKIP — ex00_one_output, this exercise's own case, is not passing yet" -- \
	afp_survive bad afp_found.txt
want_out   "allocfail --survive: ...a project's case" \
	"SKIP — ex00_one_output, this project's own case, is not passing yet" -- \
	with_kind project afp_survive bad afp_found.txt
want_out   "allocfail --survive: ...in a survive case's words" 'ends by itself' -- \
	afp_survive bad afp_found.txt
# Its gate is runner_lib.sh's rl_gate, which says this layer's own paragraph
# (RL_GATE_WHY) under a case's SKIP line, and, with no --gate-label to name
# the case, still speaks of a case (RL_GATE_SURVIVE), not an output fixture.
want_out   "allocfail --survive: ...this layer's own" 'allocates nothing' -- \
	afp_survive bad afp_found.txt
want_out   "allocfail --survive: ...and a case still, with no label" \
	"allocfail_check: SKIP — this exercise's own case is not passing yet." -- \
	env -u NO_SKIP "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_bad" --label afp_bad \
		--survive --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/afp_beside_plain" \
		--gate-expected "$WORK/afp_found.txt" -- aa bb cc
want_green "allocfail --survive: runs once that case is green" -- \
	afp_survive good afp_none.txt
want_out   "allocfail --survive: ...sweeping what it asks for" 'It asks for memory 4 time(s)' -- \
	afp_survive good afp_none.txt
want_red   "allocfail --survive: ...and judges it" -- afp_survive bad afp_none.txt
# A GATE THAT CANNOT RUN IS SAID (V292): its program not there or not a
# program, or its expected file not there. The sweep tested both itself
# first and, failing, ran ungated with nothing said -- the vacuous pass over
# a stub the gate is there to stop, with no line saying why.
printf 'not a program\n' > "$WORK/afp_nonexec"
chmod 644 "$WORK/afp_nonexec"
want_out   "allocfail --survive: a gate program that is not there is said" \
	'could not be evaluated' -- \
	env -u NO_SKIP "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_good" --label afp_good \
		--survive --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/no-such-gate" \
		--gate-expected "$WORK/afp_none.txt" -- aa bb cc
want_out   "allocfail --survive: ...as is one that is no program" \
	'could not be evaluated' -- \
	env -u NO_SKIP "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_good" --label afp_good \
		--survive --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/afp_nonexec" \
		--gate-expected "$WORK/afp_none.txt" -- aa bb cc
want_out   "allocfail --bin: ...and an expected file that is not there" \
	'could not be evaluated' -- \
	env -u NO_SKIP "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_beside" --label afp_beside \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/afp_beside_plain" \
		--gate-expected "$WORK/no-such-expected.txt" --
want_red   "allocfail --survive: NO_SKIP=1 runs it without asking" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_bad" --label afp_bad \
		--survive --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/afp_beside_plain" \
		--gate-expected "$WORK/afp_found.txt" -- aa bb cc
want_green "allocfail --survive: its gate is handed none of the sweep's run" -- \
	env -u NO_SKIP "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_beside" --label afp_beside \
		--survive --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/afp_beside_plain" \
		--gate-expected "$WORK/afp_none.txt" --run-as toy --cwd-file "toy.cfg=$WORK/afp_cfg.txt" --
want_out   "allocfail --survive: ...while the sweep runs in its own folder" \
	'It asks for memory 1 time(s)' -- \
	env -u NO_SKIP "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_beside" --label afp_beside \
		--survive --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/afp_beside_plain" \
		--gate-expected "$WORK/afp_none.txt" --run-as toy --cwd-file "toy.cfg=$WORK/afp_cfg.txt" --
# ...and its words are --gate-arg's, never the sweep's: nothing after --,
# and nothing of --argv-file, reaches it. afp_word prints the fixture only
# when its one argument is "hi", afp_bare only when it is given none; each
# asks for memory whatever it is given. Handed the sweep's "zz" or "two",
# the gate was red and the sweep SKIPped (review of V282; valgrind's twins
# are in selftest_slow.sh).
cat > "$WORK/afp_word.c" <<'AF_WORD'
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int	main(int c, char **v)
{
	char	*p;

	p = malloc(4);
	if (!p)
		return (1);
	free(p);
	if (c == 2 && !strcmp(v[1], "hi"))
		write(1, "found\n", 6);
	else
		write(1, "wrong\n", 6);
	return (0);
}
AF_WORD
sed 's/c == 2 \&\& !strcmp(v\[1\], "hi")/c == 1/' "$WORK/afp_word.c" > "$WORK/afp_bare.c"
if st_mine; then
	for _t in word bare; do
		toy_cc "$WORK/afp_$_t" -w "$WORK/afp_$_t.c" "$TOOLS/allocfail_program.c" \
			-Wl,--wrap=malloc -Wl,--wrap=free
		toy_cc "$WORK/afp_${_t}_plain" -w "$WORK/afp_$_t.c"
	done
fi
printf 'zz\n' > "$WORK/afp_word.argv"
afp_wgate() {  # afp_wgate TOY [FLAG...] -- TOY's sweep, gated on its plain twin
	_t=$1; shift
	env -u NO_SKIP "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_$_t" --label "afp_$_t" \
		--survive --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/afp_${_t}_plain" \
		--gate-expected "$WORK/afp_found.txt" --gate-label ex00_one_output "$@"
}
want_out   "allocfail --survive: its gate runs its --gate-arg words, not the case's" \
	'It asks for memory 1 time(s)' -- afp_wgate word --gate-arg hi -- zz
want_out   "allocfail --survive: ...nor the case's argument file" \
	'It asks for memory 1 time(s)' -- \
	afp_wgate word --gate-arg hi --argv-file "$WORK/afp_word.argv" --
want_out   "allocfail --survive: a gate with no word gets none of the case's" \
	'It asks for memory 1 time(s)' -- afp_wgate bare -- two
want_broken "allocfail: --gate-arg without --survive is refused" \
	"is the words of a survive case's gate" -- afp_beside --gate-arg one
want_broken "allocfail: ...and --survive on a function's probe" \
	"is a program case's" -- \
	af_probe "$WORK/af_good.c" "$WORK/af_case.c" af_good --survive

# WHOSE RULE: the call site's, never the runner's. The runner used to print
# one subject's "handle errors coherently" under every program's verdict, C
# 10's included, whose subject has no such sentence. Without --rule it quotes
# no subject; with one it prints that, and only that -- the same --rule FILE a
# function's sweep takes (the arms above), so the two modes agree.
printf '%s\n' 'A TOY RULE, ITS OWN WORDS' > "$WORK/afp_rule.txt"
want_broken_none "allocfail --bin: no --rule, no subject's sentence" 'coherently' -- afp good
want_broken_none "allocfail --bin: ...and no rule heading" 'call site in BUILD.bazel' -- afp good
want_out   "allocfail --bin: --rule is printed under a PASS" 'A TOY RULE, ITS OWN WORDS' -- \
	afp good --rule "$WORK/afp_rule.txt"
want_out   "allocfail --bin: ...and under a FAIL" 'A TOY RULE, ITS OWN WORDS' -- \
	afp bad --rule "$WORK/afp_rule.txt"
want_out   "allocfail --bin --leaks: ...and under the leak target's verdict" 'A TOY RULE, ITS OWN WORDS' -- \
	afp good --leaks --rule "$WORK/afp_rule.txt"

# THE WIRING, proven before anything is judged. A program whose report says
# the shim's own probe was not counted (wrapped=0) was linked without the
# wraps: no refusal could reach it, so "asked for no memory" would be a lie.
# And the control run at K+1, which cannot refuse anything, must end as the
# plain run did, or the sweep is not repeatable. Both are the harness's
# faults (exit 2). Shell toys that write the shim's report line themselves.
printf '#!/bin/sh\nprintf "\\nAF_RESULT arm=%%s seen=0 result=exit live=0 bytes=0 wrapped=0\\n" "${AF_ARM:-0}" > "$AF_REPORT"\n' \
	> "$WORK/afp_unwrapped"
printf '#!/bin/sh\na=${AF_ARM:-0}\nprintf "\\nAF_RESULT arm=%%s seen=2 result=exit live=0 bytes=0 wrapped=1\\n" "$a" > "$AF_REPORT"\n[ "$a" -eq 3 ] && exit 5\nexit 0\n' \
	> "$WORK/afp_drifts"
chmod +x "$WORK/afp_unwrapped" "$WORK/afp_drifts"
want_broken "allocfail --bin: a link without the wraps refuses" \
	'was not linked with' -- afp unwrapped
want_broken "allocfail --bin: a control run that ends differently refuses" \
	'control run is not trustworthy' -- afp drifts

# THE TEST'S OWN LIMIT IS NOT THE PROGRAM'S HANG. A run the test's remaining
# time cut short (RL_CLAMPED) said nothing about the program, and was a
# green SKIP in discovery ("did not end by itself") and a HUNG row in the
# sweep, which tells the student their code never ends. Both runs below are
# shell toys that write the shim's report line themselves; each is run once
# and read by two arms. afp_late sleeps past a 4 s budget; afp_slow3 takes
# 3 s a run, so the first injection starts with 2 s left and is cut.
# afp_lastslow ends at once on every run but the control run (#3, its two
# requests plus one), which sleeps past the 4 s budget: the control run is
# the last of the sweep, so the one the test's limit is likeliest to cut.
printf '#!/bin/sh\nsleep 8\n' > "$WORK/afp_late"
printf '#!/bin/sh\nsleep 3\nprintf "\\nAF_RESULT arm=%%s seen=4 result=exit live=0 bytes=0 wrapped=1\\n" "${AF_ARM:-0}" > "$AF_REPORT"\n' \
	> "$WORK/afp_slow3"
printf '#!/bin/sh\na=${AF_ARM:-0}\n[ "$a" -ne 3 ] || sleep 8\nprintf "\\nAF_RESULT arm=%%s seen=2 result=exit live=0 bytes=0 wrapped=1\\n" "$a" > "$AF_REPORT"\n' \
	> "$WORK/afp_lastslow"
chmod +x "$WORK/afp_late" "$WORK/afp_slow3" "$WORK/afp_lastslow"
if st_mine && mkdir -p "$WORK/afp"; then
	env -u RL_DEADLINE TEST_TIMEOUT=8 RL_MARGIN=4 "$SH" "$TOOLS/allocfail_check.sh" \
		--bin "$WORK/afp_late" --label afp_late -- aa > "$WORK/afp/afp_late.out" 2>&1
	echo "$?" > "$WORK/afp/afp_late.rc"
	env -u RL_DEADLINE TEST_TIMEOUT=9 RL_MARGIN=4 "$SH" "$TOOLS/allocfail_check.sh" \
		--bin "$WORK/afp_slow3" --label afp_slow3 -- aa > "$WORK/afp/afp_slow3.out" 2>&1
	echo "$?" > "$WORK/afp/afp_slow3.rc"
	env -u RL_DEADLINE TEST_TIMEOUT=8 RL_MARGIN=4 "$SH" "$TOOLS/allocfail_check.sh" \
		--bin "$WORK/afp_lastslow" --label afp_lastslow -- aa > "$WORK/afp/afp_lastslow.out" 2>&1
	echo "$?" > "$WORK/afp/afp_lastslow.rc"
fi
afp_saved() {  # afp_saved NAME -- the run saved above: its words, and its status
	cat "$WORK/afp/$1.out"
	return "$(cat "$WORK/afp/$1.rc")"
}
want_out   "allocfail --bin: a plain run the test's limit cut is that limit, red" \
	"this test's own time limit" -- afp_saved afp_late
want_broken_none "allocfail --bin: ...never a SKIP for a run that did not end" \
	'did not end by itself' -- afp_saved afp_late
want_out   "allocfail --bin: an injection the test's limit cut is that limit" \
	"this test's own time limit" -- afp_saved afp_slow3
want_broken_none "allocfail --bin: ...never a HUNG row" 'HUNG' -- afp_saved afp_slow3
want_out   "allocfail --bin: a control run the test's limit cut is that limit" \
	'too slow on the control run' -- afp_saved afp_lastslow
want_broken_none "allocfail --bin: ...never a sweep that is not repeatable" \
	'not trustworthy' -- afp_saved afp_lastslow
# The same in function mode, whose control run is checked at a site of its
# own: a harness that sleeps on the run that arms allocation #2, one past
# the function's one request, so the test's limit cuts it.
cat > "$WORK/af_lastslow_case.c" <<'AF_LS'
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void	*af_target(void);

void	*af_case(void)
{
	char	*a;

	a = getenv("AF_ARM");
	if (a && strcmp(a, "2") == 0)
		sleep(20);
	return (af_target());
}
AF_LS
# shellcheck disable=SC2086
want_out   "allocfail: a function's control run the test's limit cut is that limit" \
	'too slow on the control run' -- env -u RL_DEADLINE TEST_TIMEOUT=10 RL_MARGIN=4 \
	"$SH" "$TOOLS/allocfail_check.sh" $BUILD_PIN --src "$WORK/af_good.c" \
		--harness "$WORK/af_lastslow_case.c" --shim "$TOOLS/allocfail_shim.c" --label af_ls
# A FUNCTION'S PROBE THAT COULD NOT START is the harness's fault, exit 2, as
# a program's is: it was a green SKIP. The runner is reached through a
# folder of links to tools/ whose exit_status is a toy that reports every
# run as one exec could not start.
mkdir -p "$WORK/afnox"
_af_d=$(CDPATH='' cd "$TOOLS" && pwd)
for _af_t in "$_af_d"/*; do ln -sfn "$_af_t" "$WORK/afnox/"; done
rm -f "$WORK/afnox/exit_status"
printf '#!/bin/sh\nwhile [ "$#" -gt 0 ]; do case "$1" in --timeout | --ceiling) shift 2 ;; *) break ;; esac; done\nprintf "noexec Permission denied\\n" > "$1"\nexit 126\n' \
	> "$WORK/afnox/exit_status"
chmod +x "$WORK/afnox/exit_status"
# shellcheck disable=SC2086
want_broken "allocfail: a function's probe that could not start is refused" \
	'could not be judged: the program could not be started' -- \
	"$SH" "$WORK/afnox/allocfail_check.sh" $BUILD_PIN --src "$WORK/af_good.c" \
		--harness "$WORK/af_case.c" --shim "$TOOLS/allocfail_shim.c" --label af_nox

# --leaks needs a plain run that holds nothing: what an error path leaves can
# only be told apart from that. A program that keeps a block on every run
# skips, and NO_SKIP=1 makes that red.
printf '#include <stdlib.h>\n\nint\tmain(void)\n{\n\tchar\t*p;\n\n\tp = malloc(8);\n\tif (!p)\n\t\treturn (1);\n\tp[0] = 0;\n\treturn (p[0]);\n}\n' \
	> "$WORK/afp_holds.c"
! st_mine || toy_cc "$WORK/afp_holds" -w "$WORK/afp_holds.c" "$TOOLS/allocfail_program.c" \
	-Wl,--wrap=malloc -Wl,--wrap=free
want_out   "allocfail --bin --leaks: a plain run that holds a block skips" \
	'already' -- env -u NO_SKIP "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_holds" \
		--label afp_holds --leaks
want_red   "allocfail --bin --leaks: ...which NO_SKIP=1 makes red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_holds" \
		--label afp_holds --leaks

# THE COUNT IS EXACT however many blocks are live at once. The counter's
# table was a fixed 4096 slots, and past it the count was "untracked" for
# good: a program that held 5000 blocks and freed every one was reported as
# holding an unknown number, and --leaks skipped it -- red under NO_SKIP=1.
# A toy that keeps 5000 blocks, frees them all, and tidies on a refusal.
cat > "$WORK/afp_many.c" <<'AF_MANY'
#include <stdlib.h>

int	main(void)
{
	void	**p;
	int		i;

	p = malloc(sizeof(void *) * 5000);
	if (!p)
		return (1);
	i = 0;
	while (i < 5000)
	{
		p[i] = malloc(1);
		if (!p[i])
		{
			while (--i >= 0)
				free(p[i]);
			free(p);
			return (1);
		}
		i++;
	}
	while (--i >= 0)
		free(p[i]);
	free(p);
	return (0);
}
AF_MANY
! st_mine || toy_cc "$WORK/afp_many" -w "$WORK/afp_many.c" "$TOOLS/allocfail_program.c" \
	-Wl,--wrap=malloc -Wl,--wrap=free
want_green "allocfail --bin --leaks: 5000 live blocks, all freed, is clean" -- \
	env NO_SKIP=1 ALLOCFAIL_MAX=8 "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_many" \
		--label afp_many --leaks
want_out   "allocfail --bin: a long count is sampled to the last request" \
	'spread to the last' -- \
	env ALLOCFAIL_MAX=4 "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_good" \
		--label afp_good -- a b c d e f g h i j
want_broken "allocfail --bin: a program and a function probe at once is refused" \
	'Not both' -- "$SH" "$TOOLS/allocfail_check.sh" --bin "$WORK/afp_good" \
		--src "$WORK/af_good.c" --harness "$WORK/af_case.c"

