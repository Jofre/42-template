# ---------------------------------------------------------------- header_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# c-08 ex00-ex03's only BEHAVIOURAL layer. c_header also emits norm and compile,
# and the compile layer builds this same main() against the header, so a header
# missing a DECLARATION is already caught there. What is caught ONLY here is a
# declaration that exists and is wrong — a macro with the wrong expression, a
# struct whose members are in the wrong order — because this is the only layer
# that runs the resulting program and looks at what it printed. So the two arms
# get separate reds: the compile it does itself, and the diff it delegates. The
# second matters more, since a delegation that silently stopped reaching
# diff_output.sh would leave the compile arm still red and look healthy.
#
# The three headers sit in directories of their own, and the main() is in none of
# them. A quoted #include searches the includer's own directory FIRST, so a main
# next to the good header would keep finding it no matter which -I the runner is
# handed, and both red cases would silently test nothing.
mkdir -p "$WORK/hdr_ok" "$WORK/hdr_bad" "$WORK/hdr_wrong"
printf '#ifndef SELFTEST_H\n# define SELFTEST_H\n# define FT_MSG "hello"\n#endif\n' \
	> "$WORK/hdr_ok/selftest.h"
printf '#ifndef SELFTEST_H\n# define SELFTEST_H\n#endif\n' > "$WORK/hdr_bad/selftest.h"
printf '#ifndef SELFTEST_H\n# define SELFTEST_H\n# define FT_MSG "goodbye"\n#endif\n' \
	> "$WORK/hdr_wrong/selftest.h"
printf '#include <stdio.h>\n#include "selftest.h"\nint main(void){printf("%%s\\n", FT_MSG);return 0;}\n' \
	> "$WORK/hdr_main.c"
printf 'hello\n' > "$WORK/hdr_exp.txt"
want_green "header_check: a complete header passes" -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_ok/selftest.h" --main "$WORK/hdr_main.c" \
		--expected "$WORK/hdr_exp.txt"
want_red   "header_check: a header missing a define fails" -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_bad/selftest.h" --main "$WORK/hdr_main.c" \
		--expected "$WORK/hdr_exp.txt"
want_red   "header_check: a define with the wrong value fails" -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_wrong/selftest.h" --main "$WORK/hdr_main.c" \
		--expected "$WORK/hdr_exp.txt"
# Every path arrives whole. The options forwarded to diff_output.sh, the
# sources and the -I list were joined with blanks and split again unquoted:
# a correct header in a folder named with a blank was "not found" (its -I
# reached the compiler as three words), and a clues file in such a folder
# reached diff_output.sh as two -- a usage error, exit 2, where a wrong
# header was to be judged.
mkdir -p "$WORK/hdr sp/ok dir"
cp "$WORK/hdr_ok/selftest.h" "$WORK/hdr sp/ok dir/selftest.h"
printf 'which value does the subject give it?\n' > "$WORK/hdr sp/clues.tsv"
want_green "header_check: a header in a folder named with a blank is found" -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr sp/ok dir/selftest.h" --main "$WORK/hdr_main.c" \
		--expected "$WORK/hdr_exp.txt" --clues "$WORK/hdr sp/clues.tsv"
want_out   "header_check: ...and a clues path with a blank reaches the comparison whole" \
	'| goodbye$' -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_wrong/selftest.h" --main "$WORK/hdr_main.c" \
		--expected "$WORK/hdr_exp.txt" --clues "$WORK/hdr sp/clues.tsv"

# THE TESTS THAT WAIT FOR AN OUTPUT TEST (--waiting, the list subject()'s
# finalizer writes): a gated layer SKIPs while the output is red and shows
# PASSED in Bazel's summary, which a first red read as a pass. Under any red
# verdict -- a wrong output, a stand-in, a header that does not compile --
# they are named with their level, and when they show PASSED; on a pass, or
# with none waiting, nothing is said. Nor under NO_SKIP=1, where every one
# runs and its verdict is its own: the block said they "show PASSED" there
# beside a red one, and offered the flag already set. And never NO_SKIP=1
# as advice: in a beginner's first red it turns every forced layer red.
# `env -u NO_SKIP`, because the suite runs with NO_SKIP=1.
printf 'ex00_diff (strict)\nex00_perf (complete)\n' > "$WORK/waiting.txt"
: > "$WORK/waiting_none.txt"
wt_diff() { env -u NO_SKIP "$SH" "$TOOLS/diff_output.sh" --expected "$WORK/exp.txt" "$@"; }
want_out   "diff_output: a red verdict names the tests that wait for it" '   ex00_perf (complete)' -- \
	wt_diff --bin "$WORK/bad" --waiting "$WORK/waiting.txt"
want_out   "diff_output: ...saying when they show PASSED" 'A run that includes them' -- \
	wt_diff --bin "$WORK/bad" --waiting "$WORK/waiting.txt"
want_broken_none "diff_output: ...and offering no NO_SKIP=1" 'NO_SKIP' -- \
	wt_diff --bin "$WORK/bad" --waiting "$WORK/waiting.txt"
want_broken_none "diff_output: ...not on a pass" 'WAITING FOR THIS OUTPUT' -- \
	wt_diff --bin "$WORK/ok" --waiting "$WORK/waiting.txt"
want_broken_none "diff_output: ...nor with none waiting" 'WAITING FOR THIS OUTPUT' -- \
	wt_diff --bin "$WORK/bad" --waiting "$WORK/waiting_none.txt"
want_broken_none "diff_output: ...nor under NO_SKIP=1, where they run" 'WAITING FOR THIS OUTPUT' -- \
	env NO_SKIP=1 "$SH" "$TOOLS/diff_output.sh" --expected "$WORK/exp.txt" \
		--bin "$WORK/bad" --waiting "$WORK/waiting.txt"
want_out   "diff_output: a stand-in's red names them too" '   ex00_diff (strict)' -- \
	wt_diff --bin "$STANDIN_BIN" --waiting "$WORK/waiting.txt"
# In a package of units a test's suite is its unit's, not an exercise's
# :exNN, so the runner is told its name (--suite) and the block says that
# one. Only with a list to point it at, and only a name a suite can have.
want_out   "diff_output: --suite names the unit's suite in the block" \
	' :libtoy or //...) shows each one PASSED' -- \
	wt_diff --bin "$WORK/bad" --waiting "$WORK/waiting.txt" --suite libtoy
want_broken_none "diff_output: ...and no :exNN with it" ':exNN' -- \
	wt_diff --bin "$WORK/bad" --waiting "$WORK/waiting.txt" --suite libtoy
want_broken "diff_output: --suite without --waiting is refused" '--suite needs --waiting' -- \
	"$SH" "$TOOLS/diff_output.sh" --expected "$WORK/exp.txt" --bin "$WORK/ok" --suite libtoy
want_broken "diff_output: ...and a --suite no suite can be named" "takes a suite's name" -- \
	wt_diff --bin "$WORK/ok" --waiting "$WORK/waiting.txt" --suite 'Lib-toy'
want_out   "header_check: a header that does not compile names them" '   ex00_perf (complete)' -- \
	env -u NO_SKIP "$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_bad/selftest.h" --main "$WORK/hdr_main.c" \
		--expected "$WORK/hdr_exp.txt" --waiting "$WORK/waiting.txt"
want_out   "header_check: ...under the --suite it is given" ' :libtoy or //...)' -- \
	env -u NO_SKIP "$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_bad/selftest.h" --main "$WORK/hdr_main.c" \
		--expected "$WORK/hdr_exp.txt" --waiting "$WORK/waiting.txt" --suite libtoy
want_broken "header_check: --suite without --waiting is refused" '--suite needs --waiting' -- \
	env -u NO_SKIP "$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_bad/selftest.h" --main "$WORK/hdr_main.c" \
		--expected "$WORK/hdr_exp.txt" --suite libtoy
want_broken "header_check: ...and a --suite no suite can be named" "takes a suite's name" -- \
	env -u NO_SKIP "$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_bad/selftest.h" --main "$WORK/hdr_main.c" \
		--expected "$WORK/hdr_exp.txt" --waiting "$WORK/waiting.txt" --suite 9toy

# --exit, which c-08 ex01 uses to assert that SUCCESS is 0.
#
# The whole reason the flag exists is that a constant a main() RETURNS is
# invisible to a stdout diff, so the arm that carries the weight is the middle
# one: both headers print the identical, correct bytes and differ only in the
# value returned. If --exit ever stopped being forwarded to diff_output.sh, the
# green arms would stay green and only that one would notice.
mkdir -p "$WORK/hdr_rc_ok" "$WORK/hdr_rc_bad"
printf '#ifndef SELFTEST_RC_H\n# define SELFTEST_RC_H\n# define FT_MSG "hello"\n# define FT_RC 0\n#endif\n' \
	> "$WORK/hdr_rc_ok/selftest_rc.h"
printf '#ifndef SELFTEST_RC_H\n# define SELFTEST_RC_H\n# define FT_MSG "hello"\n# define FT_RC 3\n#endif\n' \
	> "$WORK/hdr_rc_bad/selftest_rc.h"
printf '#include <stdio.h>\n#include "selftest_rc.h"\nint main(void){printf("%%s\\n", FT_MSG);return FT_RC;}\n' \
	> "$WORK/hdr_rc_main.c"
want_green "header_check: --exit passes when the returned constant matches" -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_rc_ok/selftest_rc.h" --main "$WORK/hdr_rc_main.c" \
		--expected "$WORK/hdr_exp.txt" --exit 0
want_red   "header_check: --exit fails on a wrong constant that prints correctly" -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_rc_bad/selftest_rc.h" --main "$WORK/hdr_rc_main.c" \
		--expected "$WORK/hdr_exp.txt" --exit 0
# An EMPTY value asserts nothing -- documented at the flag, and worth an arm
# because the alternative reading (assert the exit status is the empty string)
# would turn every caller that passes it through unconditionally into a red.
want_green "header_check: --exit '' asserts nothing" -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_rc_bad/selftest_rc.h" --main "$WORK/hdr_rc_main.c" \
		--expected "$WORK/hdr_exp.txt" --exit ""
# Whose rule the status is, forwarded to diff_output.sh: a status the subject
# does not name is this repo's convention, and the failure says so.
want_out   "header_check: --exit-source convention reaches the report" "this repo's, not the" -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_rc_bad/selftest_rc.h" --main "$WORK/hdr_rc_main.c" \
		--expected "$WORK/hdr_exp.txt" --exit 0 --exit-source convention
# ...and the sentence behind it (a case's exit_quote), as one argument however
# many spaces it holds: a subject's rule is quoted, and so is a reading.
want_out   "header_check: --exit-quote reaches the report whole" 'It says: "the toy header returns 0"' -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_rc_bad/selftest_rc.h" --main "$WORK/hdr_rc_main.c" \
		--expected "$WORK/hdr_exp.txt" --exit 0 --exit-quote 'the toy header returns 0'
want_out   "header_check: ...and a reading is quoted as one" 'The sentence: "the toy header returns 0"' -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_rc_bad/selftest_rc.h" --main "$WORK/hdr_rc_main.c" \
		--expected "$WORK/hdr_exp.txt" --exit 0 --exit-source reading \
		--exit-quote 'the toy header returns 0'

# What a successful compile proved, said in the voice of its failure: a header
# whose program prints nothing used to show an empty table and "0/0".
want_out   "header_check: a compile that worked says so" 'header_check: OK' -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_ok/selftest.h" --main "$WORK/hdr_main.c" \
		--expected "$WORK/hdr_exp.txt"
want_broken_none "header_check: ...and a compile that failed does not" 'header_check: OK' -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_bad/selftest.h" --main "$WORK/hdr_main.c" \
		--expected "$WORK/hdr_exp.txt"

# --harness-src: the runner compiles the fixture itself, so the unbuffered
# stdout every other output fixture links has to reach it this way. A main that
# prints its first case with printf and then crashes keeps that row only if it
# does.
printf '%s\n' '#include <stdio.h>' '#include "selftest.h"' \
	'int main(void) { printf("one\t%s\n", FT_MSG); *(volatile int *)0 = 1; printf("two\t%s\n", FT_MSG); return (0); }' \
	> "$WORK/hdr_crash_main.c"
printf 'one\thello\ntwo\thello\n' > "$WORK/hdr_crash_exp.txt"
want_out   "header_check: --harness-src keeps the rows before a crash" '1/1 passed before it' -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_ok/selftest.h" --main "$WORK/hdr_crash_main.c" \
		--harness-src "$TOOLS/unbuffered_stdout.c" --labeled \
		--expected "$WORK/hdr_crash_exp.txt"
# ...because it forwards --harness-fixture. Without --harness-src the program
# may buffer, so no row may be called the running case.
want_broken_none "header_check: without --harness-src nothing is marked" 'running when' -- \
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/hdr_ok/selftest.h" --main "$WORK/hdr_crash_main.c" --labeled \
		--expected "$WORK/hdr_crash_exp.txt"

# A case's other kinds, and its stdin, reach diff_output.sh, which runs the
# program -- forwarded like --exit, never re-implemented here: any_of
# (--expected-alt), survive, and stdin. The wrong header prints "goodbye".
printf 'goodbye\n' > "$WORK/hdr_alt.txt"
printf '#include <stdio.h>\n#include "selftest.h"\nint main(void){char b[8];if(!fgets(b,sizeof b,stdin))return 0;printf("%%s\\n", FT_MSG);return 0;}\n' \
	> "$WORK/hdr_stdin_main.c"
printf 'go\n' > "$WORK/hdr_in.txt"
hdr_run() {  # hdr_run HEADER MAIN [flags] -- stdin is /dev/null unless --stdin names one
	_h="$1"; _m="$2"; shift 2
	"$SH" "$TOOLS/header_check.sh" --differ "$TOOLS/diff_output.sh" \
		--hdr "$WORK/$_h/selftest.h" --main "$WORK/$_m" "$@" < /dev/null
}
want_green "header_check: any_of reaches the differ" -- \
	hdr_run hdr_wrong hdr_main.c --expected "$WORK/hdr_exp.txt" --expected-alt "$WORK/hdr_alt.txt"
want_green "header_check: survive reaches the differ" -- \
	hdr_run hdr_wrong hdr_main.c --survive
want_green "header_check: stdin reaches the program" -- \
	hdr_run hdr_ok hdr_stdin_main.c --expected "$WORK/hdr_exp.txt" --stdin "$WORK/hdr_in.txt"
want_red   "header_check: ...which prints nothing without it" -- \
	hdr_run hdr_ok hdr_stdin_main.c --expected "$WORK/hdr_exp.txt"

# --shape sources, which is how c_libft's output layer compiles c-09's bundles.
# The arm that carries the weight is the guards-only header: it is what the
# template shipped in c-09 ex01 while that exercise was a bundle, and it must be
# a RED TEST (exit 1), because the cc_binary this replaced turned it into a
# Bazel build error -- which is why that header used to ship filled in, with
# c-08 ex00's answer in it. No caller turns in a header today (ex01 is the
# Makefile alone now), but the shape still takes one, so the arm stays. The
# green arms prove the shape still runs the program, with a header and without
# one (ex00 turns in none). The function is made up; it answers no exercise.
mkdir -p "$WORK/lft/src" "$WORK/lft/inc_ok" "$WORK/lft/inc_stub"
printf 'int\tft_selftest_twice(int n)\n{\n\treturn (n + n);\n}\n' \
	> "$WORK/lft/src/ft_selftest_twice.c"
printf '#ifndef LFT_H\n# define LFT_H\nint\tft_selftest_twice(int n);\n#endif\n' \
	> "$WORK/lft/inc_ok/lft.h"
printf '#ifndef LFT_H\n# define LFT_H\n#endif\n' > "$WORK/lft/inc_stub/lft.h"
printf '#include <stdio.h>\n#include "lft.h"\nint main(void){printf("%%d\\n", ft_selftest_twice(21));return 0;}\n' \
	> "$WORK/lft/main_hdr.c"
printf '#include <stdio.h>\nint ft_selftest_twice(int n);\nint main(void){printf("%%d\\n", ft_selftest_twice(21));return 0;}\n' \
	> "$WORK/lft/main_nohdr.c"
printf '42\n' > "$WORK/lft/exp.txt"
lft_run() {  # lft_run MAIN [--hdr H]
	_m="$1"; shift
	"$SH" "$TOOLS/header_check.sh" --shape sources --differ "$TOOLS/diff_output.sh" \
		--main "$WORK/lft/$_m" --src "$WORK/lft/src/ft_selftest_twice.c" \
		--expected "$WORK/lft/exp.txt" "$@"
}
want_green "header_check: sources shape, with a header, passes" -- \
	lft_run main_hdr.c --hdr "$WORK/lft/inc_ok/lft.h"
want_green "header_check: sources shape, no header, passes" -- lft_run main_nohdr.c
want_red   "header_check: sources, guards-only header: red TEST" -- \
	lft_run main_hdr.c --hdr "$WORK/lft/inc_stub/lft.h"
want_out   "header_check: ... and says what failed to compile" \
	"does not compile against what you turned in" -- \
	lft_run main_hdr.c --hdr "$WORK/lft/inc_stub/lft.h"
want_broken "header_check: sources shape with no --src refuses" "needs at least one --src" -- \
	"$SH" "$TOOLS/header_check.sh" --shape sources --differ "$TOOLS/diff_output.sh" \
		--main "$WORK/lft/main_nohdr.c" --expected "$WORK/lft/exp.txt"
want_broken "header_check: an unknown --shape refuses" "must be header or sources" -- \
	"$SH" "$TOOLS/header_check.sh" --shape sourcse --differ "$TOOLS/diff_output.sh" \
		--main "$WORK/lft/main_nohdr.c" --expected "$WORK/lft/exp.txt"

