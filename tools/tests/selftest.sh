#!/bin/sh
# Tests for the TEST HARNESS (tag "selftest").
#
# Every false green found in this harness had the same shape: a layer reported OK
# having checked nothing. rust_diff.sh said "OK (0 cases)" on an empty corpus;
# asan_check.sh exited 0 when clang-12 was missing; forbidden_symbols.sh passed
# with an empty symbol list when nm failed; diff_output.sh passed a program that
# printed the right bytes and then segfaulted. Each was found by reading the
# script and asking "can this exit 0 while broken?" — which is exactly the
# question a test can ask automatically, and none existed.
#
# So: known-bad inputs, each of which MUST make its layer red, and known-good
# inputs which must stay green. A runner that stops detecting its bug will fail
# here instead of silently passing every exercise in the repo.
#
# Usage: selftest.sh --anchor PATH-TO-ANY-TOOLS-SCRIPT
#
# The anchor is a file rather than a directory because Bazel's $(rootpath) on a
# filegroup member resolves to the FILE; appending /.. to it yields
# "diff_output.sh/..", which is not a directory. dirname is the honest way to
# get there — and getting this wrong made every check in here go red at once,
# which is how it was found.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "selftest.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat chmod cp cut dirname env git grep head ln mkdir mktemp rm sed sha256sum tail

VALGRIND=""
VGCGTOOLS=""
CG_ANNOTATE=""
ANCHOR=""
NORMINETTE=""
NM=""
SHELLCHECK=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "selftest.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--valgrind) need "$1" "$#"; VALGRIND="$2"; shift 2 ;;
		--valgrind-callgrind-tools) need "$1" "$#"; VGCGTOOLS="$2"; shift 2 ;;
		--callgrind-annotate) need "$1" "$#"; CG_ANNOTATE="$2"; shift 2 ;;
		--anchor) need "$1" "$#"; ANCHOR="$2"; shift 2 ;;
		# Not derivable from the anchor: norminette is a py_binary, so it lands
		# somewhere else in runfiles rather than beside the shell runners.
		--norminette) need "$1" "$#"; NORMINETTE="$2"; shift 2 ;;
		# symbols_test.sh and forbidden_symbols.sh take a SUPPLIED nm with no
		# PATH fallback, so the selftest has to hand them one like Bazel does.
		--nm) need "$1" "$#"; NM="$2"; shift 2 ;;
		# Same reason, for shell_test.sh's norm mode and conventions.sh.
		--shellcheck) need "$1" "$#"; SHELLCHECK="$2"; shift 2 ;;
		*) echo "selftest.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$ANCHOR" ] || { echo "selftest.sh: --anchor is required" >&2; exit 2; }
[ -f "$ANCHOR" ] || { echo "selftest.sh: anchor $ANCHOR does not exist" >&2; exit 2; }
[ -n "$NORMINETTE" ] || { echo "selftest.sh: --norminette is required" >&2; exit 2; }
[ -n "$NM" ] || { echo "selftest.sh: --nm is required" >&2; exit 2; }
[ -n "$SHELLCHECK" ] || { echo "selftest.sh: --shellcheck is required" >&2; exit 2; }
TOOLS=$(dirname "$ANCHOR")

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

PASS=0
FAIL=0

# want_red / want_green NAME -- COMMAND...
#
# want_red passes ONLY on exit 1, never on "non-zero". Every runner driven from
# here reserves 1 for "the thing under test is wrong" and 2 for "the harness is
# broken" — an unknown option, a missing required flag, an absent compiler under
# NO_SKIP. Treating any non-zero status as a detection conflates exactly the two
# cases that must not be conflated: rename a flag or add a required one, and
# every want_red below would go on printing "ok (red, as required)" while
# checking nothing at all, in the one moment this file exists to notice. That is
# the same false-green shape as the bugs it hunts, one level up. So capture the
# status, and report anything that is not 1 as a check that never ran.
want_red() {
	_name="$1"; shift; [ "$1" = "--" ] && shift
	"$@" >/dev/null 2>&1
	_rc=$?
	case "$_rc" in
		1)
			printf '  %-52s %s\n' "$_name" "ok (red, as required)"
			PASS=$((PASS + 1)) ;;
		0)
			printf '  %-52s %s\n' "$_name" "FAIL < (passed; it must not)"
			FAIL=$((FAIL + 1)) ;;
		*)
			printf '  %-52s %s\n' "$_name" \
				"FAIL < (exit $_rc = harness error; nothing was checked)"
			FAIL=$((FAIL + 1)) ;;
	esac
}
want_green() {
	_name="$1"; shift; [ "$1" = "--" ] && shift
	if "$@" >/dev/null 2>&1; then
		printf '  %-52s %s\n' "$_name" "ok (green, as required)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_name" "FAIL < (red; it must not be)"
		FAIL=$((FAIL + 1))
	fi
}

# want_out — the arm for runners whose value is the DIAGNOSIS, not the verdict.
#
# Several checks here would be near-useless if they only went red: "your program
# is wrong" sends a student hunting, while "you built ./rush02 and the subject
# says rush-02" is a two-second fix. That sentence is a feature, and a feature
# with no test rots -- it gets reworded into vagueness, or moved behind a branch
# that stops running, and nothing notices because the exit status is unchanged.
#
# Exit status is deliberately NOT asserted beyond sanity: an explanation is worth
# testing whether it accompanies a pass or a failure. But 2 and above still fail
# the arm, for want_red's reason -- a renamed flag would otherwise leave this
# grepping an error message for a pattern it will never contain and calling that
# a check.
want_out() {
	_name="$1"; _pat="$2"; shift 2; [ "$1" = "--" ] && shift
	_out=$("$@" 2>&1)
	_rc=$?
	if [ "$_rc" -ge 2 ]; then
		printf '  %-52s %s\n' "$_name" \
			"FAIL < (exit $_rc = harness error; nothing was checked)"
		FAIL=$((FAIL + 1))
	# `--` before the pattern, because a pattern is data and grep would read a
	# leading dash as an option. Found by an arm asserting on the text
	# "--units must be a positive integer": the runner printed exactly that,
	# grep took it for a flag, and the arm reported the message missing.
	elif printf '%s' "$_out" | grep -qF -- "$_pat"; then
		printf '  %-52s %s\n' "$_name" "ok (explained itself)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_name" "FAIL < (never said '$_pat')"
		FAIL=$((FAIL + 1))
	fi
}

# want_broken — the arm for a runner that REFUSES to run.
#
# Exit 2 means "the harness is misconfigured", and a few checks deliberately use
# it rather than passing: a fetched compiler whose libraries are not where it
# was told they are would otherwise load the box's copies and go green, so the
# only safe answer is to stop. That is a behaviour worth pinning, and neither
# want_red (which treats 2 as a broken harness) nor want_out (same) can say so.
# Both the status AND the explanation are asserted, because a refusal nobody can
# act on is only half of one.
# The inverse of want_out: the run must have RUN, and must NOT contain the text.
# Needed because the interesting half of a triage is what it declines to say.
#
# Exit 2 or above fails the arm, for want_red's reason and with more force here
# than anywhere else: this helper asserts an ABSENCE, so a runner that died
# before printing anything satisfies it perfectly. Its own docstring used to
# promise "the run must succeed" while the code asserted nothing about the
# status at all -- so every arm built on it, including the ones written to prove
# a check stays quiet, would have reported success against a runner that was not
# there. A missing `data` entry is enough to produce exactly that.
#
# 2-or-above rather than "must be 0": several callers point at a runner that
# legitimately exits 1 while the assertion is about one line of its output.
want_broken_none() {
	_name="$1"; _pat="$2"; shift 2; [ "$1" = "--" ] && shift
	_out=$("$@" 2>&1)
	_rc=$?
	if [ "$_rc" -ge 2 ]; then
		printf '  %-52s %s\n' "$_name" \
			"FAIL < (exit $_rc = harness error; nothing was checked)"
		FAIL=$((FAIL + 1))
	elif printf '%s' "$_out" | grep -qF -- "$_pat"; then
		printf '  %-52s %s\n' "$_name" "FAIL < (said '$_pat'; it must not)"
		FAIL=$((FAIL + 1))
	else
		printf '  %-52s %s\n' "$_name" "ok (stayed quiet, as required)"
		PASS=$((PASS + 1))
	fi
}
want_broken() {
	_name="$1"; _pat="$2"; shift 2; [ "$1" = "--" ] && shift
	_out=$("$@" 2>&1)
	_rc=$?
	if [ "$_rc" -ne 2 ]; then
		printf '  %-52s %s\n' "$_name" "FAIL < (exit $_rc; it must refuse with 2)"
		FAIL=$((FAIL + 1))
	# `--` before the pattern, because a pattern is data and grep would read a
	# leading dash as an option. Found by an arm asserting on the text
	# "--units must be a positive integer": the runner printed exactly that,
	# grep took it for a flag, and the arm reported the message missing.
	elif printf '%s' "$_out" | grep -qF -- "$_pat"; then
		printf '  %-52s %s\n' "$_name" "ok (refused, and said why)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_name" "FAIL < (refused without saying '$_pat')"
		FAIL=$((FAIL + 1))
	fi
}

# WHICH SHELL INTERPRETS THE RUNNERS.
#
# Every arm below launches a runner through "$SH" rather than a literal `sh`,
# so the whole file can be replayed under a different shell. That is the point:
# this repo does NOT pin /bin/sh, and the reason it does not need to is that the
# runners are shell-agnostic -- which is a claim, and a claim about behaviour
# has to be executed rather than asserted.
#
# A comment must not START with the word shellcheck -- that is how a directive
# is spelled, and the linter then fails to parse this paragraph. Said the other
# way round: static linting already refuses a bashism (SC3xxx, at warning level,
# in //tools:conventions). This is the other half: dash and bash disagree about
# things no linter reads, `echo` with escapes being the classic one, and the
# only way to know is to run everything twice.
#
# //tools/tests:selftest_bash is the second run. If the shell named here is not
# installed, that is a SKIP rather than a pass -- see the guard below.
SH=${SELFTEST_SH:-sh}
if [ "$SH" != "sh" ] && ! command -v "$SH" > /dev/null 2>&1; then
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "selftest: SELFTEST_SH=$SH is not installed and NO_SKIP=1 is set," >&2
		echo "          so nothing was checked under it." >&2
		exit 2
	}
	echo "selftest: SKIP — SELFTEST_SH=$SH is not installed on this machine."
	exit 0
fi

CC=${SELFTEST_CC:-cc}
# The NO_SKIP guard this file's own subject matter demands. Without it, a box
# with no compiler runs zero of the checks below and reports success — which is
# the exact false-green shape every arm here exists to hunt, in the file doing
# the hunting. `bazel test ... --test_env=NO_SKIP=1` is the sweep that tells
# "passes everywhere" apart from "skips everywhere", and it can only do that if
# the skip is reachable as a failure. Exit 2, not 1: no check ran, so this is a
# broken harness rather than a detected bug (see want_red above).
command -v "$CC" >/dev/null 2>&1 || {
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "selftest: no C compiler ($CC) and NO_SKIP=1 — nothing could be checked" >&2
		exit 2
	}
	echo "selftest: SKIP — no C compiler"
	exit 0
}

printf 'selftest: does each layer still detect what it exists to detect?\n\n'

# ---------------------------------------------------------------- diff_output
printf 'hello\n' > "$WORK/exp.txt"
printf '#include <stdio.h>\nint main(void){printf("hello\\n");return 0;}\n' > "$WORK/ok.c"
"$CC" -o "$WORK/ok" "$WORK/ok.c" 2>/dev/null
printf '#include <stdio.h>\nint main(void){printf("wrong\\n");return 0;}\n' > "$WORK/bad.c"
"$CC" -o "$WORK/bad" "$WORK/bad.c" 2>/dev/null
# Correct output, then a crash: the exact false green diff_output.sh had.
printf '#include <stdio.h>\nint main(void){printf("hello\\n");fflush(stdout);*(volatile int*)0=1;return 0;}\n' > "$WORK/crash.c"
"$CC" -o "$WORK/crash" "$WORK/crash.c" 2>/dev/null
# Prints forever: must be stopped by the ulimit budget, not run for the whole timeout.
printf '#include <stdio.h>\nint main(void){for(;;)printf("spam\\n");}\n' > "$WORK/runaway.c"
"$CC" -o "$WORK/runaway" "$WORK/runaway.c" 2>/dev/null

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

# ---- the HINTS block, which is what a stuck beginner actually reads ---------
#
# Three separate things were wrong with it, and all three were invisible from
# the exit status, which is why nothing had caught them.
printf 'alpha\nbeta\n' > "$WORK/hexp.txt"
printf '#include <stdio.h>\nint main(void){printf("alpha\\nWRONG\\n");return 0;}\n' > "$WORK/hbad.c"
"$CC" -o "$WORK/hbad" "$WORK/hbad.c" 2>/dev/null
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

# ------------------------------------------------------------------- progname
# This runner had NO arm here at all, which is why it discarded the child's exit
# status unnoticed: it diffed stdout, and a program that printed the right line
# and then died passed. The green arm is as important as the red ones — the runs
# below are what prove the added status check did not simply break the layer.
printf '#include <stdio.h>\nint main(int c,char**v){(void)c;printf("%%s\\n",v[0]);return (0);}\n' \
	> "$WORK/pn_ok.c"
printf '#include <stdio.h>\nint main(int c,char**v){(void)c;printf("%%s\\n",v[0]);return (3);}\n' \
	> "$WORK/pn_rc.c"
printf '#include <stdio.h>\n#include <stdlib.h>\nint main(int c,char**v){(void)c;printf("%%s\\n",v[0]);fflush(stdout);abort();}\n' \
	> "$WORK/pn_abort.c"
printf '#include <stdio.h>\nint main(void){printf("./a.out\\n");return (0);}\n' \
	> "$WORK/pn_hard.c"
for _p in pn_ok pn_rc pn_abort pn_hard; do
	"$CC" -w -o "$WORK/$_p" "$WORK/$_p.c" 2> /dev/null
done

want_green "progname: prints its own argv[0] and exits 0" -- \
	"$SH" "$TOOLS/progname_test.sh" "$WORK/pn_ok"
want_red   "progname: right line THEN a non-zero return fails" -- \
	"$SH" "$TOOLS/progname_test.sh" "$WORK/pn_rc"
want_red   "progname: right line THEN abort() fails" -- \
	"$SH" "$TOOLS/progname_test.sh" "$WORK/pn_abort"
want_red   "progname: a hardcoded \"./a.out\" fails the renamed run" -- \
	"$SH" "$TOOLS/progname_test.sh" "$WORK/pn_hard"

# ------------------------------------------------------------------ rust_diff
printf '#!/bin/sh\nexit 0\n' > "$WORK/empty_oracle"; chmod +x "$WORK/empty_oracle"
printf '#!/bin/sh\ncat >/dev/null\n' > "$WORK/null_student"; chmod +x "$WORK/null_student"
want_red "rust_diff: an EMPTY corpus is not a pass" -- \
	"$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/empty_oracle" --oracle-fn x \
		--seed 1 --count 0 --student-bin "$WORK/null_student"

# The column legend, which every diff target gets for free. It is read out of
# the harness's own header comment rather than written per exercise, so the arm
# that matters is "a real header yields a legend" -- if the sed that extracts it
# ever stops matching, 74 targets quietly go back to printing bare hex and
# nothing else changes to say so.
mkdir -p "$WORK/cols"
cat > "$WORK/cols/diff_thing.c" <<'COLS_SRC'
/* Live-differential reader harness for ft_thing.
 * Line: <hexIn>\t<size>\t<hexOut>. Reads one record, replays it and
 * reprints the result as hex. */
#include "diffio.h"
COLS_SRC
# 40 cases, not 1: rust_diff refuses a corpus too small to prove anything, so a
# one-line fixture never reaches the divergence report at all.
printf '#!/bin/sh\ni=0\nwhile [ $i -lt 40 ]; do printf "%%s\\tb%%s\\n" "$i" "$i"; i=$((i+1)); done\n' \
	> "$WORK/cols/oracle.sh"
printf '#!/bin/sh\ncat >/dev/null\ni=0\nwhile [ $i -lt 40 ]; do printf "%%s\\tZZZ\\n" "$i"; i=$((i+1)); done\n' \
	> "$WORK/cols/student.sh"
chmod +x "$WORK/cols/oracle.sh" "$WORK/cols/student.sh"
# The clue file reaches the student WHOLE. It used to be run through the
# tiered clues.tsv renderer -- first three lines, one bullet each -- which for a
# prose legend meant three fragments of a cut-off opening sentence. The arm
# checks for text on the file's fourth line, which no `head -3` can reach.
printf 'first line\nsecond line\n# a maintainer note, not for students\nthird line\nFOURTH_LINE_MARKER\n' \
	> "$WORK/cols/clues.txt"
want_out "rust_diff: the clue file is printed whole, not head -3" 'FOURTH_LINE_MARKER' -- \
	"$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--clues "$WORK/cols/clues.txt"
want_out "rust_diff: and its # comments are not" 'first line' -- \
	"$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--clues "$WORK/cols/clues.txt"

# The same legend, from a header that closes its comment on the SENTENCE'S OWN
# LINE -- which is how 16 of the 75 harnesses are written. A sed range does not
# stop on the line it started on, so those spilled #includes, the prototype and
# the head of main() into the report. The arm asserts the sentence arrives and
# the next arm asserts the code does not.
cat > "$WORK/cols/diff_oneline.c" <<'ONELINE_SRC'
/* Live-differential reader harness for ft_oneline.
 * Line: <hexOne>\t<hexTwo>. Reads a record and reprints it. */
#include "diffio.h"
int	main(void)
{
	char	SPILLED_CODE_MARKER[8192];
ONELINE_SRC
want_out "rust_diff: a one-line legend is still extracted" 'Line: <hexOne>' -- \
	"$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--harness-src "$WORK/cols/diff_oneline.c"
_spill=$("$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
	--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
	--harness-src "$WORK/cols/diff_oneline.c" 2>&1)
if printf '%s' "$_spill" | grep -q 'SPILLED_CODE_MARKER'; then
	printf '  %-52s %s\n' "rust_diff: and stops at the end of the comment" \
		"FAIL < (source code leaked into the report)"
	FAIL=$((FAIL + 1))
else
	printf '  %-52s %s\n' "rust_diff: and stops at the end of the comment" \
		"ok (nothing after the comment)"
	PASS=$((PASS + 1))
fi

want_out "rust_diff: a divergence explains its hex columns" 'Line: <hexIn>' -- \
	"$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--harness-src "$WORK/cols/diff_thing.c"

# The red above only proves the corpus-size guard fires; it says nothing about
# whether the comparison downstream of it still works. A layer that reds on
# everything is as useless as one that greens on everything — the first time it
# cries wolf over a correct answer it gets switched off — so the passing path
# needs pinning too. The real oracle is //oracle's Rust binary, which this test
# must not depend on (it would drag a Rust build into a "small" shell test); any
# program emitting at least MIN_DIFF_CASES self-describing lines stands in for
# it, and a student harness that echoes the corpus back is what a CORRECT one
# does by construction, since it reprints each input beside its own answer.
printf '#!/bin/sh\ni=0\nwhile [ $i -lt 24 ]; do printf "%%02x\\tcase-%%d\\n" "$i" "$i"; i=$((i+1)); done\n' \
	> "$WORK/mini_oracle"; chmod +x "$WORK/mini_oracle"
printf '#!/bin/sh\ncat\n' > "$WORK/echo_student"; chmod +x "$WORK/echo_student"
# Diverges on the FIRST line only: a corpus is 400k lines in production and the
# bug being fuzzed for is usually one input in thousands, so "detects a wholesale
# difference" is not the property worth testing.
printf '#!/bin/sh\nsed "1s/case/CASE/"\n' > "$WORK/skew_student"; chmod +x "$WORK/skew_student"
want_green "rust_diff: a matching corpus passes" -- \
	"$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --student-bin "$WORK/echo_student"
want_red   "rust_diff: ONE diverging line fails" -- \
	"$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --student-bin "$WORK/skew_student"

# --crash-only, which is the ENTIRE diff_asan layer: 77 targets whose verdict is
# one `rc=$?` and one comparison. It had no arm of any kind. The two above cover
# the value-diff path only, and value-diff and crash-fuzz share no branch --
# crash-only returns before the comparison ever runs.
#
# This is not hypothetical. During the review that produced these arms, an agent
# editing a scratch copy changed that line to `rc=0` -- "the sanitizer verdict is
# discarded; crash-fuzz always passes" -- and every arm in this file stayed
# green. A layer that reports OK having checked nothing is the defect class this
# whole file exists for, and its largest instance was the one place unwatched.
printf '#!/bin/sh\ncat >/dev/null\nexit 0\n' > "$WORK/crash_clean"
# Non-zero is what a sanitizer abort looks like from here: ASan exits 1, and the
# harness is killed by a signal for a hard fault. Either way it is not 0.
printf '#!/bin/sh\ncat >/dev/null\necho "AddressSanitizer: heap-buffer-overflow" >&2\nexit 1\n' \
	> "$WORK/crash_dirty"
chmod +x "$WORK/crash_clean" "$WORK/crash_dirty"

want_green "rust_diff: --crash-only passes a clean replay" -- \
	"$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_clean"
want_red   "rust_diff: --crash-only fails on a sanitizer error" -- \
	"$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_dirty"
want_out "rust_diff: --crash-only shows the sanitizer report" \
	"AddressSanitizer" -- \
	"$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_dirty"

# ----------------------------------------------------------- forbidden_symbols
printf 'int ft_x(void){return 0;}\n' > "$WORK/clean.c"
printf '#include <stdio.h>\nint ft_x(void){printf("no");return 0;}\n' > "$WORK/dirty.c"
want_green "forbidden: a function calling nothing passes" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --allowed - --src "$WORK/clean.c"
want_red   "forbidden: an unauthorised printf fails" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --allowed - --src "$WORK/dirty.c"

# ------------------------------------------------------------------- symbols
printf 'static int helper(void){return 1;}\nint ft_x(void){return helper();}\n' > "$WORK/static.c"
printf 'int helper(void){return 1;}\nint ft_x(void){return helper();}\n' > "$WORK/leaky.c"
want_green "symbols: a static helper is invisible, so passes" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --expect ft_x --src "$WORK/static.c"
want_red   "symbols: an exported helper fails" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --expect ft_x --src "$WORK/leaky.c"

# ------------------------------------------------------------------ asan_run
printf '#include <stdio.h>\nint main(void){char b[8];int i=0;while(i<12){b[i]=(char)i;i++;}printf("%%d\\n",b[0]);return 0;}\n' > "$WORK/oob.c"
# Whether this container can BUILD an instrumented binary at all is a property of
# the toolchain, not of the layer under test, so probe it once and let the
# asan_check section below reuse the answer instead of paying for a second probe.
if "$CC" -g -fsanitize=address,undefined -fno-sanitize-recover=all -fuse-ld=bfd \
		-o "$WORK/oob" "$WORK/oob.c" 2>/dev/null; then
	SAN=1
	want_red "asan_run: an out-of-bounds write fails" -- \
		"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/oob"
	want_green "asan_run: a clean program passes" -- \
		"$SH" "$TOOLS/asan_run.sh" --bin "$WORK/ok"
else
	SAN=0
	# NO_SKIP=1 has to reach this too. Without the guard, a box that cannot link
	# an instrumented binary silently drops the ONLY regression tests the asan
	# layers have -- four arms covering asan_run and asan_check -- and this file
	# still reports success, which is precisely the shape it exists to catch.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no sanitizer build is possible here, so the asan arms" >&2
		echo "             did not run and the asan layers are unproven." >&2
		exit 2
	}
	printf '  %-52s %s\n' "asan_run: (sanitizer build unavailable)" "skipped"
fi

# ----------------------------------------------------------------- asan_check
# The false green this whole file cites in its header — asan_check.sh exiting 0
# when clang-12 was missing — and until now the one runner named in that header
# with no regression test of its own. It is NOT the repo's only sanitizer layer:
# asan_run.sh, argv_table.sh --memory-only and rust_diff.sh --crash-only all run
# instrumented code. What only this one does is choose the allocation: it is
# compiled together with a probe that hands the student's function a block
# sized to fit exactly, so one step past the end lands in a sanitizer redzone
# instead of on a harmless neighbouring byte — which is what the whole-program
# layers, running on whatever the program happened to allocate, would let
# through. The difference between the two sources below is a single `<` → `<=`.
printf '#include <stdlib.h>\nvoid ft_probe_fill(char *b, int n);\nint main(void){char *b = malloc(4); ft_probe_fill(b, 4); free(b); return 0;}\n' \
	> "$WORK/probe.c"
printf 'void ft_probe_fill(char *b, int n){int i=0;while(i<n){b[i]=(char)i;i++;}}\n' \
	> "$WORK/fill_ok.c"
printf 'void ft_probe_fill(char *b, int n){int i=0;while(i<=n){b[i]=(char)i;i++;}}\n' \
	> "$WORK/fill_oob.c"
if [ "$SAN" -eq 1 ]; then
	# MEM_CC is pinned to the compiler the probe above actually validated. Left
	# unpinned, asan_check.sh searches (clang-12, clang, gcc-10, gcc, cc) and may
	# land on a different one than the probe cleared — which would report a
	# toolchain difference here as a defect in the layer's detection logic.
	want_red "asan_check: a one-byte overflow fails" -- \
		env MEM_CC="$CC" "$SH" "$TOOLS/asan_check.sh" \
			--probe "$WORK/probe.c" --src "$WORK/fill_oob.c"
	want_green "asan_check: staying inside the block passes" -- \
		env MEM_CC="$CC" "$SH" "$TOOLS/asan_check.sh" \
			--probe "$WORK/probe.c" --src "$WORK/fill_ok.c"
else
	printf '  %-52s %s\n' "asan_check: (sanitizer build unavailable)" "skipped"
fi

# ------------------------------------------------------------------ files_test
want_green "files: exactly the required set passes" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --actual /x/a.c
want_red   "files: a missing required file fails" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --required b.c --actual /x/a.c
want_green "files: an extra file only warns by default" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --actual /x/a.c --actual /x/z.txt
want_red   "files: --strict makes an extra file fail" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --actual /x/a.c --actual /x/z.txt --strict

# ----------------------------------------------------------------- argv_table
# For c-06 ex01-ex03 this is the ONLY layer that ever executes the program: the
# verdict is delegated to diff_output.sh with --bin /bin/cat, so that script's
# crash and hang guards are watching `cat`, and everything about the real runs
# has to be judged inside argv_table.sh itself. So both halves get pinned: the
# table comparison it delegates, and the survival check it cannot delegate.
#
# Scenario lines are TAB-separated (<label><TAB><arg>...), and the table this
# produces joins each run's stdout lines with " | ", so the expected file is
# "<label><TAB>a | b". Written with printf so the tabs are real tabs — an editor
# that helpfully expanded them would turn every row into a one-argument run and
# the mismatch would look like a bug in the runner.
printf '#include <stdio.h>\nint main(int c, char **v){int i=1;while(i<c){printf("%%s\\n", v[i]);i++;}return 0;}\n' \
	> "$WORK/argv_ok.c"
"$CC" -o "$WORK/argv_ok" "$WORK/argv_ok.c" 2>/dev/null
printf '#include <stdio.h>\nint main(int c, char **v){(void)c;(void)v;printf("nope\\n");return 0;}\n' \
	> "$WORK/argv_bad.c"
"$CC" -o "$WORK/argv_bad" "$WORK/argv_bad.c" 2>/dev/null
# Prints exactly the right table and THEN dies — the false green fixed in
# 3381bd0, and the shape these exercises actually fail in, since indexing and
# swapping argv pointers emits the correct bytes and crashes on the way out. The
# table it renders reads all PASS; the verdict must still come out red.
printf '#include <stdio.h>\nint main(int c, char **v){int i=1;while(i<c){printf("%%s\\n", v[i]);i++;}fflush(stdout);*(volatile int*)0=1;return 0;}\n' \
	> "$WORK/argv_crash.c"
"$CC" -o "$WORK/argv_crash" "$WORK/argv_crash.c" 2>/dev/null
printf 'two\ta\tb\none\tz\n' > "$WORK/scn.tsv"
printf 'two\ta | b\none\tz\n' > "$WORK/table.txt"
want_green "argv_table: the expected table passes" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_ok" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_red   "argv_table: a wrong table fails" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_bad" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_red   "argv_table: RIGHT table then a crash fails" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_crash" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"

# -------------------------------------------------------------- first_red
# Turns a wall of red into one objective. Its whole value is the TRIAGE, so the
# arms check the classification rather than the formatting: a written
# deliverable failing a green-on-a-stub layer must be called out, and a STUB
# failing the same layer must not be -- that second case is c-08 on a fresh
# clone, where a header that defines nothing cannot compile the subject's own
# main, and an earlier version of this script blamed the student for it.
mkdir -p "$WORK/fr/mod/deliverable/ex00"
# ABSOLUTE, before any cd. $TOOLS is runfiles-relative, and these arms have to
# cd into a fake workspace so first_red can find deliverable/ -- which is
# exactly the "handed over relative, then stranded by a later cd" failure this
# repo has hit four times with fetched tools. Resolve it once, here.
FR_TOOLS=$(cd "$TOOLS" && pwd)
printf '//mod:ex00_compile_gcc  FAILED in 0.3s\n' > "$WORK/fr/ko.log"
printf '//mod:ex00_output  FAILED in 0.1s\n'      > "$WORK/fr/work.log"

# A deliverable that is written: (void) casts plus a real statement.
printf 'int\tf(int a)\n{\n\treturn (a + 1);\n}\n' > "$WORK/fr/mod/deliverable/ex00/f.c"
want_out "first_red: a WRITTEN file failing compile is the student's to fix" \
	'FIX FIRST' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/ko.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"

# The same failure over a STUB must not be blamed on anyone.
printf 'int\tf(int a)\n{\n\t(void)a;\n\treturn (0);\n}\n' > "$WORK/fr/mod/deliverable/ex00/f.c"
want_broken_none "first_red: the same failure over a STUB is not blamed" \
	'FIX FIRST' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/ko.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"

want_out "first_red: a red output layer reads as the next exercise" \
	'YOUR NEXT EXERCISE' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/work.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"

want_out "first_red: --all expands to one line per exercise" \
	'EVERY EXERCISE' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --all < "$1/work.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken "first_red: an unknown option refuses" \
	'unknown option' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --nope < "$1/work.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: a clean run says so" \
	'nothing failed' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < /dev/null' _ "$WORK/fr" "$SH" "$FR_TOOLS"

# ---------------------------------------------------------------- header_check
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

# -------------------------------------------------------------- prototype_check
# C has no name mangling, so a definition whose signature disagrees with the
# subject's still LINKS and every other layer sees plausible-looking values. This
# runner is the only thing standing between that and a green, which makes a
# silent pass here indistinguishable from a Moulinette KO nobody predicted.
printf 'int ft_selftest_x(int n);\n' > "$WORK/proto.h"
printf 'int ft_selftest_x(int n){return n;}\n' > "$WORK/proto_ok.c"
printf 'char ft_selftest_x(char n){return n;}\n' > "$WORK/proto_bad.c"
want_green "prototype: a matching signature passes" -- \
	"$SH" "$TOOLS/prototype_check.sh" --proto "$WORK/proto.h" --src "$WORK/proto_ok.c"
want_red   "prototype: a different return/param type fails" -- \
	"$SH" "$TOOLS/prototype_check.sh" --proto "$WORK/proto.h" --src "$WORK/proto_bad.c"

# ------------------------------------------------------------------ make_test
# The `rm -f` added in 6965462. Bazel's data glob sweeps in whatever a hand-run
# of make left behind in deliverable/ — .gitignore hides those from git, not from
# native.glob — and copies it into the scratch build dir, so without that line a
# build script producing NOTHING reported green off the stale artifact. The
# --script arm is the one worth pinning: it never runs the fclean/re hygiene the
# Makefile arm gets, which is what would otherwise have caught the stale copy.
#
# The fixture is a directory of its own because the runner stages the anchor's
# whole DIRECTORY: anchoring anywhere in $WORK would copy every other fixture in
# this file into the build.
mkdir -p "$WORK/mk"
printf '#!/bin/sh\n:\n' > "$WORK/mk/build_none.sh"
printf '#!/bin/sh\n: > libselftest.a\n' > "$WORK/mk/build_ok.sh"
printf 'stale artifact from an earlier hand-run\n' > "$WORK/mk/libselftest.a"
# Is the pinned make really the one that runs? A --make that is accepted and
# then ignored looks exactly like one that works, and the obvious arm does not
# distinguish them: point it at a directory with no Makefile and BOTH a broken
# make and the box's fail, so the red proves nothing.
#
# So the fixture is a Makefile that genuinely builds. The box's make succeeds on
# it (second arm), and a --make that is not make at all must therefore fail
# (first arm). Only the pair is conclusive. --rules "" because this fixture is
# about which make runs, not about clean/fclean/re, and those checks are
# sequentially coupled.
mkdir -p "$WORK/mkbin"
printf 'all:\n\t: > libselftest.a\n' > "$WORK/mkbin/Makefile"
want_red "make_test: --make is used, not accepted and ignored" -- \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --make /bin/false --rules "" \
		--anchor "$WORK/mkbin/Makefile" --artifact libselftest.a
want_green "make_test: and the same fixture builds with a real make" -- \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" \
		--anchor "$WORK/mkbin/Makefile" --artifact libselftest.a

want_red   "make_test: a stale artifact is not a build" -- \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --anchor "$WORK/mk/build_none.sh" \
		--artifact libselftest.a --script build_none.sh
want_green "make_test: a script that really builds passes" -- \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --anchor "$WORK/mk/build_ok.sh" \
		--artifact libselftest.a --script build_ok.sh

# The near-miss name. rush-02's Makefile really did build `rush02`, and the only
# layer in the whole repo that can notice is this one -- everything else
# compiles the sources itself and never asks what the Makefile called its
# output. Two arms, because the value here is entirely in the DIAGNOSIS: red
# alone was already the behaviour, and red plus "you built ./libself-test.a"
# is what makes it a two-second fix instead of a hunt. Anchored in its own
# directory for the reason given above.
mkdir -p "$WORK/mknear"
printf '#!/bin/sh\n: > libself-test.a\n' > "$WORK/mknear/build_near.sh"
want_red   "make_test: a name differing only in punctuation is still wrong" -- \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --anchor "$WORK/mknear/build_near.sh" \
		--artifact libselftest.a --script build_near.sh
want_out   "make_test: it names the near miss instead of dumping ls" \
	'libself-test.a' -- \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --anchor "$WORK/mknear/build_near.sh" \
		--artifact libselftest.a --script build_near.sh

# --------------------------------------------------------------- cycles_check
# This layer CANNOT fail on its numbers -- it says so in its own comment, and
# ends in exit 0 whatever the count. So there is no budget arm to write, and
# everything worth pinning is a REFUSAL: the four skips, each of which is a
# silent green, and each of which NO_SKIP=1 is supposed to turn into a failure
# that names itself. That is the whole safety net under a layer whose normal
# output nobody checks, and it had no arm at all.
#
# The real profiling run lives in :selftest_slow -- callgrind is 20-50x native.
# Everything here exits before valgrind is ever invoked.
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
want_red "cycles_check: a harness that will not build at -O2 is RED" -- \
	"$SH" "$TOOLS/cycles_check.sh" --harness "$WORK/cyc/broken.c" $CYC_VG \
		--callgrind-annotate "$CG_ANNOTATE" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum

# An empty corpus is the dangerous one: the binary would be profiled against no
# input at all and report a count of nothing, which reads like a fast function.
want_green "cycles_check: an empty corpus SKIPs quietly by default" -- \
	env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--callgrind-annotate "$CG_ANNOTATE" \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum
want_red "cycles_check: and NO_SKIP=1 turns that skip RED" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true $CYC_VG \
		--callgrind-annotate "$CG_ANNOTATE" \
		--oracle "$WORK/cyc/empty.sh" --oracle-fn f --symbol probe_sum

# And the skip that would retire the whole layer in one upstream release: no
# callgrind. Hidden the same way the ilp32 arms hide a compiler -- a PATH holding
# only the coreutils the script needs, so it fails for the right reason and not
# because the shell itself went missing. Built here rather than reused from the
# ilp32 section, which runs later in this file: borrowing it made these two arms
# exit 127 against a directory that did not exist yet.
mkdir -p "$WORK/cyc/novg"
# "$SH" is in this list, not just `sh`. These fixtures exist to hide ONE
# tool by handing over a PATH holding only what the runner needs -- and
# under //tools/tests:selftest_bash the runner is launched with bash, which
# then has to be findable too. Without it the arm dies at exit 127 and
# reports the tool it meant to hide as a harness error.
#
# The list is the UNION of what cycles_check.sh and ref_compare.sh declare in
# their `require` lines, plus the shell. It has to be: the probe runs before
# anything else in the runner, so a PATH missing one of them refuses with 2 and
# the arm never reaches the skip it was written to exercise. Adding the probe is
# what revealed that this list was assembled by trial rather than from the
# runners -- it happened to be enough only because nothing checked.
for _t in sh "$SH" mktemp dirname sed rm cat basename wc tr awk cmp grep head tail; do
	ln -sf "$(command -v "$_t")" "$WORK/cyc/novg/$_t" 2> /dev/null
done
# VALGRIND IS PINNED NOW, so "no callgrind" no longer means "not installed".
# What remains absent-able is the OTHER half of that guard: callgrind_annotate,
# a Perl script this repo deliberately does not pin. So the pair below hides
# that, not the binary -- and the pair after it covers the case the pin created,
# where the wiring is wrong and the layer must refuse rather than skip.
want_green "cycles_check: no callgrind_annotate SKIPs quietly by default" -- \
	env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true \
		$CYC_VG --callgrind-annotate "$WORK/cyc/absent-annotate" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
want_red "cycles_check: and NO_SKIP=1 turns THAT skip RED too" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/cycles_check.sh" --bin /bin/true \
		$CYC_VG --callgrind-annotate "$WORK/cyc/absent-annotate" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
want_broken "cycles_check: a missing --valgrind refuses, never skips" \
	'--valgrind is required' -- \
	"$SH" "$TOOLS/cycles_check.sh" --bin /bin/true \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum

# ---------------------------------------------------------------- ref_compare
# Its own header names the arms worth having: "the NO_SKIP refusals (this
# layer's plumbing rotted while pretending to measure)". Like cycles_check it
# never fails on the ratio it reports -- the number is informative and nothing
# else -- so a skip that stopped being loud under NO_SKIP=1 is the whole risk.
#
# The argument checks are worth pinning for a second reason recorded in the
# runner: sh_test tokenises `args` on spaces, so a two-word --label arrives as a
# stray argument, and both c_files and c_cycles learned that the hard way.
printf 'int main(void) { return (0); }\n' > "$WORK/cyc/tiny.c"
want_broken "ref_compare: it refuses without a unit count to divide by" \
	'--units must be a positive integer' -- \
	"$SH" "$TOOLS/ref_compare.sh" --harness "$WORK/cyc/tiny.c" --src "$WORK/cyc/tiny.c" \
		$CYC_VG --callgrind-annotate "$CG_ANNOTATE" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum
want_broken "ref_compare: and a stray argument names its own cause" \
	'tokenises args on spaces' -- \
	"$SH" "$TOOLS/ref_compare.sh" --harness "$WORK/cyc/tiny.c" --src "$WORK/cyc/tiny.c" \
		$CYC_VG --callgrind-annotate "$CG_ANNOTATE" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum \
		--units 1 stray-word
want_green "ref_compare: no callgrind_annotate SKIPs quietly by default" -- \
	env -u NO_SKIP "$SH" "$TOOLS/ref_compare.sh" \
		$CYC_VG --callgrind-annotate "$WORK/cyc/absent-annotate" \
		--harness "$WORK/cyc/tiny.c" --src "$WORK/cyc/tiny.c" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum --units 1
want_red "ref_compare: and NO_SKIP=1 turns that skip RED" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/ref_compare.sh" \
		$CYC_VG --callgrind-annotate "$WORK/cyc/absent-annotate" \
		--harness "$WORK/cyc/tiny.c" --src "$WORK/cyc/tiny.c" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum --units 1
want_broken "ref_compare: a missing --valgrind refuses, never skips" \
	'--valgrind is required' -- \
	"$SH" "$TOOLS/ref_compare.sh" \
		--harness "$WORK/cyc/tiny.c" --src "$WORK/cyc/tiny.c" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum --units 1

# --------------------------------------------------------------- oracle_check
# The guard on the guard. Every `diff` layer in the repo trusts //oracle to be
# right, so a reference that quietly stopped agreeing with its own tables would
# fail CORRECT student code across 74 targets with nothing above it to notice --
# and this runner is what notices. It had no arm of its own.
#
# The arms use a stand-in rather than the real oracle, deliberately: what is
# being tested is that a non-zero `check` becomes a red test WITH the self-check
# output attached, and building 30 s of Rust to assert that would put this in
# the slow suite for no gain.
mkdir -p "$WORK/orc"
printf '#!/bin/sh\n[ "$1" = check ] || exit 3\necho "all modules agree"\n' \
	> "$WORK/orc/ok"
printf '#!/bin/sh\n[ "$1" = check ] || exit 3\necho "c02: 3 failures"\nexit 1\n' \
	> "$WORK/orc/bad"
chmod +x "$WORK/orc/ok" "$WORK/orc/bad"
want_green "oracle_check: a reference that agrees with itself passes" -- \
	"$SH" "$TOOLS/oracle_check.sh" --oracle "$WORK/orc/ok"
want_red "oracle_check: a reference that fails its own check is RED" -- \
	"$SH" "$TOOLS/oracle_check.sh" --oracle "$WORK/orc/bad"
# The failure text is the point: "the reference is wrong, so do not go hunting
# in your own code" is the one thing a student cannot work out unaided.
want_out "oracle_check: and it says the reference is at fault, not the student" \
	'Fix //oracle first' -- \
	"$SH" "$TOOLS/oracle_check.sh" --oracle "$WORK/orc/bad"
want_out "oracle_check: and shows what the self-check said" 'c02: 3 failures' -- \
	"$SH" "$TOOLS/oracle_check.sh" --oracle "$WORK/orc/bad"
want_broken "oracle_check: a missing reference is a harness error, not a red" \
	'not executable' -- \
	"$SH" "$TOOLS/oracle_check.sh" --oracle "$WORK/orc/nothing-here"

# ------------------------------------------------------------------ env_drift
# Not a test layer -- it is the maintainer's answer to "has campus upgraded
# anything?" -- but its grading is comparison logic, and comparison logic that
# stops comparing is the exact shape every other arm in this file hunts. It
# earned these the hard way: two versions of its version extractor returned the
# wrong answer for a pin written as a bare "3.3.58", one of them silently
# grading a correct toolchain as a different major release.
#
# `printf` with a literal tab, because pins.tsv is tab-separated and a fixture
# written with spaces would be read as one enormous tool name -- which grades as
# missing, and would pass a want_red arm while proving nothing.
mkdir -p "$WORK/drift"
_pin() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" campus "$2" "$3" fixture; }

# Exactly what the box reports: no drift, whatever the string looks like.
_pin true "GNU coreutils 8.32" "echo GNU coreutils 8.32" > "$WORK/drift/same.tsv"
want_out "env_drift: a version that matches is not drift" 'true        campus  ok' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/same.tsv"

# A repackaging: same version, different wrapper text. The whole reason the
# expected value stopped being a substring was to keep seeing real differences
# WITHOUT reporting this one.
_pin true "GNU coreutils 8.32" "echo Debian coreutils 8.32-4" > "$WORK/drift/pkg.tsv"
want_out "env_drift: a repackaged same version is forgiven, not hidden" 'ok (repackaged)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/pkg.tsv"

# The one the old substring pin could not see at all: campus moved by a patch
# release. `clang version 12.` swallowed this silently.
_pin true "GNU coreutils 8.32" "echo GNU coreutils 8.32.1" > "$WORK/drift/patch.tsv"
want_out "env_drift: a patch-level move is reported, not swallowed" 'DRIFT (patch)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/patch.tsv"

_pin true "GNU coreutils 8.32" "echo GNU coreutils 9.1" > "$WORK/drift/major.tsv"
want_out "env_drift: a major move is graded as one" 'DRIFT (major)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/major.tsv"

# A pin written as a bare number, which is how the norminette pin is written and
# where both extractor bugs lived. It must grade exactly like any other.
printf 'true\tcampus\t3.3.58\techo 3.3.58\tfixture\n' > "$WORK/drift/bare.tsv"
want_out "env_drift: a bare version number grades like any other" 'true        campus  ok' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/bare.tsv"

# And the third comparison. The pin and the box agree; what BAZEL FETCHED does
# not, which is the case that had nothing watching it until the fetched
# toolchain existed. It must be loud even though the box looks fine.
printf 'true\tcampus\t8.32\techo 8.32\tfixture\tSELFTEST_FETCHED\n' \
	> "$WORK/drift/fetch.tsv"
printf '#!/bin/sh\necho "GNU coreutils 9.9"\n' > "$WORK/drift/fetched.sh"
chmod +x "$WORK/drift/fetched.sh"
want_out "env_drift: a fetch that disagrees with its own pin is loud" 'FETCH DRIFT' -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/fetch.tsv"
want_red "env_drift: --strict fails on fetch drift the box cannot show" -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched.sh" \
		"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/fetch.tsv"

# A campus tool that is ABSENT must reach --strict. It counted into MISSING and
# into neither of the two lists --strict actually looks at, so a box carrying
# none of the pinned tools printed a wall of MISSING and exited 0 -- the one
# kind of machine the flag exists to reject was the one it accepted.
printf 'no-such-tool-42\tcampus\t1.0\tno-such-tool-42 --version\tfixture\n' \
	> "$WORK/drift/absent.tsv"
want_out "env_drift: an absent campus tool is named in the drift list" \
	'no-such-tool-42 (missing)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/absent.tsv"
want_red "env_drift: --strict fails on a campus tool that is not installed" -- \
	"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/absent.tsv"

# An unset HERMETIC_* means the pin-vs-fetch comparison did not happen. It used
# to print an advisory line and `continue` without counting anything, so the
# third of the three comparisons this script calls non-optional could vanish one
# variable at a time while the run still reported no drift.
#
# Two rows, so that ONE of them is set: all of them unset is a hand-run outside
# Bazel, where there is nothing fetched to compare and saying "drift" would cry
# wolf on every standalone invocation. That distinction is the fix, not the
# counter.
{
	printf 'true\tcampus\t8.32\techo 8.32\tfixture\tSELFTEST_FETCHED\n'
	printf 'true\tcampus\t8.32\techo 8.32\tfixture\tSELFTEST_UNSET\n'
} > "$WORK/drift/halfset.tsv"
printf '#!/bin/sh\necho "GNU coreutils 8.32"\n' > "$WORK/drift/fetched_ok.sh"
chmod +x "$WORK/drift/fetched_ok.sh"
want_out "env_drift: an unset HERMETIC_* is a comparison that did not run" \
	'NOT COMPARED' -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched_ok.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/halfset.tsv"
want_red "env_drift: --strict fails when a pinned binary was never compared" -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched_ok.sh" \
		"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/halfset.tsv"

# KIND `fetched`: the box is not consulted. shellcheck, zig and buildifier are
# downloaded against a sha256 and every layer runs the downloaded copy, so this
# machine's apt shellcheck 0.8.0 beside our pinned 0.10.0 is not a finding --
# and reporting it as one would put a permanent red in front of the check whose
# whole value is that a red means something. The box here reports 9.9 and the
# pin says 8.32; the only verdict that may appear is the fetch's.
printf 'true\tfetched\t8.32\ttrue --version\tfixture\tSELFTEST_FETCHED\n' \
	> "$WORK/drift/fetchedkind.tsv"
printf '#!/bin/sh\necho "GNU coreutils 8.32"\n' > "$WORK/drift/fk_ok.sh"
chmod +x "$WORK/drift/fk_ok.sh"
want_broken_none "env_drift: a fetched-kind row ignores the box's copy" \
	'DRIFT' -- \
	env SELFTEST_FETCHED="$WORK/drift/fk_ok.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/fetchedkind.tsv"
# ...and it is still COMPARED. A kind that silences the box half and counts
# nothing would be a row that can never fail -- which is the shape this whole
# file exists to hunt.
printf '#!/bin/sh\necho "GNU coreutils 9.9"\n' > "$WORK/drift/fk_bad.sh"
chmod +x "$WORK/drift/fk_bad.sh"
want_red "env_drift: --strict still fails on a fetched-kind mismatch" -- \
	env SELFTEST_FETCHED="$WORK/drift/fk_bad.sh" \
		"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/fetchedkind.tsv"

# A version command of `-` is "recorded here, deliberately not probed" -- bazel
# and bazelisk, which cannot be asked their version from inside a `bazel run`
# without contending for the lock that run holds. It must say so rather than
# treat `-` as a command, which would report the tool MISSING and, for a
# campus-kind row, fail --strict on a machine with nothing wrong with it.
printf 'bazel\tours\t9.2.0\t-\t.bazelversion\n' > "$WORK/drift/recorded.tsv"
want_out "env_drift: a not-probed pin says so instead of probing" \
	'recorded 9.2.0 (not probed: .bazelversion)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/recorded.tsv"
want_green "env_drift: ...and --strict does not fail on one" -- \
	"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/recorded.tsv"

# THE FIRST LINE WITH A VERSION ON IT, not the first line with content. perl
# forced this once (a blank first line); shellcheck went further -- its
# --version prints a fixed banner first and "version: 0.10.0" on the line after,
# so pinning "the first line with content" pins a string identical in every
# release, i.e. a pin that can never report drift.
# No escape for the space in "version: 0.10.0": the row is a COMMAND, split on
# whitespace, and dash's `printf %b` reads \0400 as a four-digit octal escape
# rather than \040 followed by a zero -- so the fixture printed "version:.10.0"
# and the arm failed on its own quoting rather than on the runner. The banner is
# the point; the space is not.
printf 'true\tcampus\tversion:0.10.0\tprintf %%s\\n Banner version:0.10.0\tfixture\n' \
	> "$WORK/drift/banner.tsv"
want_out "env_drift: a banner before the version is skipped" \
	'true        campus  ok' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/banner.tsv"

# The fetch probe must use the ROW's flags. `zig --version` is an error -- the
# subcommand is `zig version` -- so a hardcoded --version reports the pinned zig
# as unversioned and grades a correct fetch as major drift.
printf 'zig\tfetched\t0.13.0\tzig version\tfixture\tSELFTEST_FETCHED\n' \
	> "$WORK/drift/subcmd.tsv"
printf '#!/bin/sh\n[ "$1" = version ] || { echo "error: unknown flag $1" >&2; exit 1; }\necho 0.13.0\n' \
	> "$WORK/drift/zigish.sh"
chmod +x "$WORK/drift/zigish.sh"
want_out "env_drift: the fetch probe uses the row's own flags" \
	'fetched:  ok (0.13.0)' -- \
	env SELFTEST_FETCHED="$WORK/drift/zigish.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/subcmd.tsv"

# ...but a hand-run with NOTHING set is not a finding: outside Bazel none of the
# HERMETIC_* variables exist, and every standalone --strict would otherwise fail
# for a reason that has nothing to do with the box.
want_green "env_drift: a hand-run outside Bazel is not fetch drift" -- \
	"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/same.tsv"

# A pin that is not a version at all. `default-std <cc>` asks a compiler what
# standard it assumes when nobody says -- the answer that decides whether five
# of c-12's contracts accept correct code -- and it has to grade like any other
# row rather than falling through the version extractor as "no number found".
printf 'true\tcampus\t201710L gnu\tdefault-std %s\tfixture\n' "$CC" \
	> "$WORK/drift/std.tsv"
want_out "env_drift: it can pin a compiler's default standard" 'true        campus  ok' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/std.tsv"
printf 'true\tcampus\t202311L gnu\tdefault-std %s\tfixture\n' "$CC" \
	> "$WORK/drift/std_bad.tsv"
want_out "env_drift: and a moved standard is drift, not a shrug" 'DRIFT' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/std_bad.tsv"

# A row whose NAME is not the name of any binary. glibc is asked with `ldd
# --version`, because a C library has no executable of its own, and testing the
# row name reported the runtime every deliverable links against as MISSING on a
# machine that obviously has it. The presence check has to follow the command.
printf 'not_a_binary_name\tcampus\t8.32\techo 8.32\tfixture\n' > "$WORK/drift/named.tsv"
want_out "env_drift: a row named after no binary is not missing" \
	'not_a_binary_name campus  ok' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/named.tsv"

# A fetched binary whose own libraries are not where it says they are. This
# shipped, briefly, as a path built by appending /.. to a FILE: the directory
# does not exist, the loader falls back to the machine's own libraries, and the
# fetched compiler reports the right version while not being the fetched
# compiler at all. Green, wrong, and invisible -- so the directories are checked
# rather than assumed, and the check has an arm.
want_out "env_drift: libraries that are not there is not a pass" 'UNRUNNABLE' -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched.sh" \
		SELFTEST_FETCHED_LIBS="$WORK/drift/nowhere/libnope.so" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/fetch.tsv"

# --------------------------------------------------------------- compile_check
# The guard on a FETCHED compiler's libraries, and the only thing standing
# between "the pinned compiler" and "a compiler that reports the pinned version
# while being the box's". clang is a 100 KB driver: point it at a library
# directory that does not exist and the loader falls back to the machine's own
# copies, every compile passes, and nothing in the output differs by a single
# character. So a missing directory must stop the run, not soften it.
mkdir -p "$WORK/cclib"
printf 'int main(void) { return (0); }\n' > "$WORK/cclib/ok.c"
want_broken "compile_check: a compiler library that is not there stops the run" \
	'does not exist' -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" \
		--cc-lib "$WORK/cclib/nowhere/libnope.so" --src "$WORK/cclib/ok.c"
# The other half of the same question. A fetched compiler can start perfectly
# and still be using the BOX's cc1 or resource headers, if part of its tree was
# not staged -- same driver, same version banner, different compiler. Both
# compilers print where they will look, so the tree they are looking in is
# checkable; here the answer is deliberately somewhere they will never name.
want_broken "compile_check: a compiler searching someone else's tree stops the run" \
	'not searching its own tree' -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" \
		--cc-under "$WORK/cclib/ok.c" --src "$WORK/cclib/ok.c"
# The assembler. gcc shells out to one; if -B does not land, it silently takes
# the machine's at assembly time and the object is built by a tool nobody
# pinned. `-print-prog-name=as` answers with a path when the compiler found one
# and with the bare word when it did not, so the bare word has to stop the run.
# Pointed at a directory that certainly holds no assembler.
want_broken "compile_check: an assembler it did not find stops the run" \
	'did not take the pinned assembler' -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" \
		--cc-progs "$WORK/cclib/ok.c" --src "$WORK/cclib/ok.c"
want_green "compile_check: and without --cc-lib nothing changes" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/cclib/ok.c"

# ----------------------------------------------------------- make_srcs_build
# The builder for modules whose subject mandates a Makefile and then leaves the
# filenames to the team. Its whole reason to exist is the case the first arm
# sets up: a directory holding TWO entry points, only one of which the Makefile
# compiles. A glob links both and dies on a duplicate symbol -- so the green arm
# here is the proof that asking make gives a different, and correct, answer.
#
# The second arm covers the failure that would otherwise be silent. A Makefile
# whose default goal compiles nothing leaves the source list empty, and an empty
# list is one careless `$CC $SRCS -o out` away from linking successfully and
# producing a program that does nothing -- a false green in the shape this whole
# file exists to hunt.
mkdir -p "$WORK/mksrc"
printf 'int helper(void);\nint helper(void) { return (0); }\n' > "$WORK/mksrc/a.c"
printf 'int helper(void);\nint main(void) { return (helper()); }\n' > "$WORK/mksrc/main_a.c"
printf 'int main(void) { return (1); }\n' > "$WORK/mksrc/main_b.c"
printf 'all:\n\tcc a.c main_a.c -o prog\n' > "$WORK/mksrc/Makefile"
want_green "make_srcs_build: it builds what MAKE compiles, not what globs" -- \
	"$SH" "$TOOLS/make_srcs_build.sh" --anchor "$WORK/mksrc/Makefile" \
		--cc "$CC" --out "$WORK/mksrc_out"

mkdir -p "$WORK/mknone"
printf 'int main(void) { return (0); }\n' > "$WORK/mknone/main.c"
printf 'all:\n\t@:\n' > "$WORK/mknone/Makefile"
want_red "make_srcs_build: a goal that compiles nothing is not a program" -- \
	"$SH" "$TOOLS/make_srcs_build.sh" --anchor "$WORK/mknone/Makefile" \
		--cc "$CC" --out "$WORK/mknone_out"
want_broken "make_srcs_build: the same guard, on the same compiler" \
	'does not exist' -- \
	"$SH" "$TOOLS/make_srcs_build.sh" --anchor "$WORK/mksrc/Makefile" \
		--cc "$CC" --cc-lib "$WORK/mksrc/nowhere/libnope.so" --out "$WORK/mksrc_out2"
# --stub-on-failure: the build action must always produce its output, or an
# unwritten deliverable -- this repo's normal state -- takes a whole module down
# as "FAILED TO BUILD" instead of failing test by test with clues attached. Two
# arms, because the value is split between them: the action succeeds, AND the
# thing it produced still refuses to pretend it is a program.
want_green "make_srcs_build: --stub-on-failure still produces something" -- \
	"$SH" "$TOOLS/make_srcs_build.sh" --anchor "$WORK/mknone/Makefile" \
		--cc "$CC" --out "$WORK/mknone_stub" --stub-on-failure
want_red "make_srcs_build: and what it produced is not a working program" -- \
	"$WORK/mknone_stub"
want_out "make_srcs_build: the stub explains itself when RUN" \
	'compiles no .c files' -- \
	"$WORK/mknone_stub"

want_out "make_srcs_build: it shows what make said it would run" \
	'This is what it said it would run' -- \
	"$SH" "$TOOLS/make_srcs_build.sh" --anchor "$WORK/mknone/Makefile" \
		--cc "$CC" --out "$WORK/mknone_out"

# ---------------------------------------------------------------- shell_check
# ck_skip: the one exercise whose answer is defined by a resource 42 issues and
# this repo does not redistribute (shell-00 ex07). On a fresh clone there is
# nothing to check against -- which is neither a pass nor the student's failure,
# and the difference has to survive, because a skip that reads as a pass is the
# defect class this whole file exists for.
mkdir -p "$WORK/ckskip"
printf '%s\n' \
	'. "${SHELL_CHECK_LIB:?}"' \
	'ck_skip "no fixture here"' \
	'ck "unreachable" true' \
	'ck_report' > "$WORK/ckskip/check.sh"
want_green "shell_check: ck_skip is a skip, not a failure" -- \
	env -u NO_SKIP SHELL_CHECK_LIB="$TOOLS/shell_check.sh" sh "$WORK/ckskip/check.sh"
want_red "shell_check: and NO_SKIP=1 turns it red" -- \
	env NO_SKIP=1 SHELL_CHECK_LIB="$TOOLS/shell_check.sh" sh "$WORK/ckskip/check.sh"
want_out "shell_check: a skip says it checked nothing" 'nothing was checked' -- \
	env -u NO_SKIP SHELL_CHECK_LIB="$TOOLS/shell_check.sh" sh "$WORK/ckskip/check.sh"

# ----------------------------------------------------------------- shell_test
# The only functional runner for BOTH shell modules: every diff/check test in
# c-piscine-shell-00 and -01 goes through it, so a break here greens two entire
# modules at once. The student's answer is the generator, which this re-runs in a
# throwaway dir, so there are three distinct ways to be wrong and each gets a
# case: produce the wrong content, produce no deliverable at all, or not be valid
# sh in the first place (--mode norm, the layer every stub exercise still runs).
printf '#!/bin/sh\nprintf "hello\\n" > out.txt\n' > "$WORK/gen_ok.sh"
printf '#!/bin/sh\nprintf "wrong\\n" > out.txt\n' > "$WORK/gen_bad.sh"
printf '#!/bin/sh\n:\n' > "$WORK/gen_none.sh"
printf 'if [ ; then\n' > "$WORK/gen_syntax.sh"
printf 'hello\n' > "$WORK/gen_exp.txt"
want_green "shell_test: the expected deliverable passes" -- \
	"$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_ok.sh" --mode diff \
		--deliverable out.txt --expected "$WORK/gen_exp.txt"
want_red   "shell_test: wrong deliverable content fails" -- \
	"$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_bad.sh" --mode diff \
		--deliverable out.txt --expected "$WORK/gen_exp.txt"
want_red   "shell_test: producing no deliverable fails" -- \
	"$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_none.sh" --mode diff \
		--deliverable out.txt --expected "$WORK/gen_exp.txt"
want_red   "shell_test: --mode norm rejects a syntax error" -- \
	"$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_syntax.sh" --mode norm

# The other half of norm mode: the LINT, which used to run whatever shellcheck
# the box happened to have and, on a box with none, printed a note to stderr and
# exited 0. Both halves of that are wrong -- an unpinned linter makes the verdict
# depend on the machine (its version decides which warnings exist), and a silent
# pass is the shape this whole file exists to catch. It is pinned now, and these
# three arms hold each part of the replacement in place.
#
# SC2164 rather than SC2086: the runner lints at -S warning, so an unquoted
# expansion is only an info and would leave the arm asserting nothing.
printf '#!/bin/sh\ncd /tmp\nls\n' > "$WORK/gen_lint.sh"
printf '#!/bin/sh\ncd /tmp || exit 1\nls\n' > "$WORK/gen_lintok.sh"

want_red   "shell_test: the pinned shellcheck rejects a warning" -- \
	"$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_lint.sh" --mode norm \
		--shellcheck "$SHELLCHECK"

want_green "shell_test: a clean generator still passes the lint" -- \
	"$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_lintok.sh" --mode norm \
		--shellcheck "$SHELLCHECK"

# And with no pinned binary the layer must SAY it checked less, not imply it
# checked. NO_SKIP=1 is the sweep that turns every such gap red; a skip it
# cannot force is invisible to the only mechanism built to find it.
want_red   "shell_test: NO_SKIP refuses a norm run with no linter" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/shell_test.sh" \
		--generator "$WORK/gen_lint.sh" --mode norm
# The bounds on unverified code. A generator that loops forever or prints without
# end used to be stopped only by Bazel's own timeout, which reports nothing a
# student can act on.
printf '#!/bin/sh\nwhile :; do :; done\n' > "$WORK/gen_hang.sh"
printf '#!/bin/sh\nwhile :; do printf "spam\\n"; done > out.txt\n' > "$WORK/gen_flood.sh"
want_red   "shell_test: a generator that never finishes is stopped" -- \
	env SHELL_TIMEOUT=2 "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_hang.sh" \
		--mode diff --deliverable out.txt --expected "$WORK/gen_exp.txt"
want_red   "shell_test: a generator that floods output is stopped" -- \
	env SHELL_TIMEOUT=10 "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_flood.sh" \
		--mode diff --deliverable out.txt --expected "$WORK/gen_exp.txt"

# --run mode: right output, then death. The status used to be discarded here, so
# a deliverable that printed exactly the expected bytes and then died passed.
# Written with a quoted heredoc rather than printf: the fixture is a script that
# writes a script, and expressing two levels of escaping inside one printf format
# is how the first version of this arm ended up generating a deliverable that
# never crashed -- and passing, while proving nothing.
cat > "$WORK/gen_runcrash.sh" <<'GEN_RUNCRASH'
#!/bin/sh
cat > d.sh <<'INNER'
#!/bin/sh
printf 'hello\n'
kill -SEGV $$
INNER
chmod +x d.sh
GEN_RUNCRASH
want_red   "shell_test: --run right output THEN a signal death fails" -- \
	"$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_runcrash.sh" --mode diff \
		--deliverable d.sh --expected "$WORK/gen_exp.txt" --run

# ----------------------------------------------------------------- shell_check
# The verdict engine for every check-mode shell exercise. A check.sh that never
# reaches ck_report prints [FAIL] to the log and then exits with whatever its
# last command returned -- so the log says FAIL and Bazel says PASSED. All 17
# live check scripts call ck_report, which is exactly why this needed a test:
# the hole only opens when someone writes the eighteenth.
printf '. "${SHELL_CHECK_LIB:?}"\nck "always true" true\nck_report\n' > "$WORK/ck_ok.sh"
printf '. "${SHELL_CHECK_LIB:?}"\nck "always false" false\nck_report\n' > "$WORK/ck_bad.sh"
printf '. "${SHELL_CHECK_LIB:?}"\nck "always true" true\n' > "$WORK/ck_noreport.sh"
printf '#!/bin/sh\n:\n' > "$WORK/gen_nop.sh"

want_green "shell_check: a check script whose checks all pass is green" -- \
	"$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_nop.sh" --mode check \
		--check "$WORK/ck_ok.sh" --check-lib "$TOOLS/shell_check.sh"
want_red   "shell_check: one failing ck fails the exercise" -- \
	"$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_nop.sh" --mode check \
		--check "$WORK/ck_bad.sh" --check-lib "$TOOLS/shell_check.sh"
want_red   "shell_check: passing checks but no ck_report is NOT a pass" -- \
	"$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_nop.sh" --mode check \
		--check "$WORK/ck_noreport.sh" --check-lib "$TOOLS/shell_check.sh"

# --------------------------------------------------------------- compile_check
printf 'int main(void){return (0);}\n' > "$WORK/cc_ok.c"
# -Wall -Wextra -Werror is the point: this is a WARNING, and the layer exists to
# make a warning fail here rather than at the Moulinette.
printf 'int main(void){int x;return (x);}\n' > "$WORK/cc_warn.c"
want_green "compile_check: clean source compiles" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/cc_ok.c"
want_red   "compile_check: a warning is a failure, not a warning" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/cc_warn.c"

# ------------------------------------------------------------------- run_check
printf '#include <stdio.h>\nint main(void){printf("some output\\n");return (0);}\n' \
	> "$WORK/rc_ok.c"
printf '#include <stdio.h>\nint main(void){printf("x\\n");return (4);}\n' > "$WORK/rc_exit.c"
printf 'int main(void){for(;;);}\n' > "$WORK/rc_hang.c"
for _p in rc_ok rc_exit rc_hang; do
	"$CC" -w -o "$WORK/$_p" "$WORK/$_p.c" 2> /dev/null
done
want_green "run_check: a program that runs and exits 0 passes" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 1
want_red   "run_check: the wrong exit status fails" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_exit"
want_red   "run_check: too little output fails" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_ok" --min-bytes 10000
want_red   "run_check: an infinite loop is stopped and failed" -- \
	"$SH" "$TOOLS/run_check.sh" --bin "$WORK/rc_hang" --timeout 2

# ----------------------------------------------------------------- norminette
# The Norm layer decides the verdict for every exercise in the repo, and it is
# the one layer whose tool is a pinned third-party program rather than our own
# shell. What is checked here is the RUNNER: that it forwards files, that it
# distinguishes a norm violation (1) from a broken harness (2), and that it does
# not simply pass everything.
#
# The 42 header is itself a Norm rule, so both fixtures are stamped with one
# from the repo's own generator rather than a hand-aligned copy pasted in here —
# a fixture that failed for the wrong reason would make the green arm useless
# and the red arm meaningless. LOGIN42/EMAIL42 are set so the result does not
# depend on whose .vscode/settings.json this ran against.
_hdr() {
	LOGIN42=selftest EMAIL42=selftest@42.fr \
		"$SH" "$TOOLS/gen_header.sh" "$1" > "$WORK/$1"
}
_hdr norm_ok.c
printf '\nint\tmain(void)\n{\n\treturn (0);\n}\n' >> "$WORK/norm_ok.c"
_hdr norm_bad.c
# Spaces instead of tabs, and a brace on the declaration line: two violations
# that need no knowledge of any exercise.
printf '\nint main(void) {\n    return (0);\n}\n' >> "$WORK/norm_bad.c"
want_green "norminette: a norm-compliant file passes" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_ok.c"
want_red   "norminette: a norm violation fails" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_bad.c"

# ----------------------------------------------------------------------- ilp32
# Only the SKIP guard is exercised here, and NOWHERE ELSE EXERCISES THE REST.
# This used to say the functional arms "belong in a slower target", which reads
# as though :selftest_slow owns them; it does not, and grep for ilp32 there
# returns nothing. So the layer's actual verdict -- build at -m32, run, diff --
# is untested in this repo. Saying so is worth more than implying coverage that
# does not exist: an unproven layer someone believes is proven is the same
# defect class as a green that checked nothing. Writing it needs a fixture whose
# answer differs when long is 32 bits, plus the 32-bit toolchain to run it; see
# TODO.md.
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
# Same rule as $WORK/cyc/novg above: this must cover everything
# ilp32_test.sh's `require` line names, or the probe refuses before the missing
# compiler is ever reached.
for _t in sh "$SH" mktemp dirname sed rm cat basename mkdir; do
	ln -sf "$(command -v "$_t")" "$WORK/nocc/$_t" 2> /dev/null
done
printf 'x\n' > "$WORK/ilp32_exp.txt"
printf 'int main(void){return (0);}\n' > "$WORK/ilp32_h.c"
want_red "ilp32: NO_SKIP=1 turns a missing 32-bit compiler RED" -- \
	env PATH="$WORK/nocc" NO_SKIP=1 "$SH" "$TOOLS/ilp32_test.sh" --zig /nonexistent \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/ilp32_h.c" \
		--expected "$WORK/ilp32_exp.txt" --src "$WORK/ilp32_h.c"
# `env -u NO_SKIP`, not a bare `env`. This arm's whole subject is what happens
# when NO_SKIP is ABSENT, and the sweep that makes it matter is run as
# `--test_env=NO_SKIP=1`, which puts it in this script's environment and hence
# in the child's. Without the -u, the one arm describing the unforced path was
# guaranteed red under the forced sweep -- and a sweep that cannot come back
# green is a sweep nobody runs twice.
want_green "ilp32: without NO_SKIP the same case skips, so the suite stays green" -- \
	env -u NO_SKIP PATH="$WORK/nocc" "$SH" "$TOOLS/ilp32_test.sh" --zig /nonexistent \
		--differ "$TOOLS/diff_output.sh" --harness "$WORK/ilp32_h.c" \
		--expected "$WORK/ilp32_exp.txt" --src "$WORK/ilp32_h.c"

# -------------------------------------------------------------------- require
# Every runner declares the external commands it takes from PATH and probes for
# them at startup. These arms are what make that a mechanism rather than a
# comment.
#
# THE BUG IT EXISTS FOR IS INVISIBLE WITHOUT THEM. `grep -qE "AddressSanitizer"
# "$ERR"` on a box with no grep does not error -- it reads as "no match", so
# asan_run.sh skips its sanitizer branch and announces a real ASan finding as
# "died on signal 6". Nothing in the suite could see that, because every arm we
# have runs on a machine where grep exists.
#
# So the PATH is built to hold everything a runner needs EXCEPT one tool, and
# the arm asserts the message names that tool. A directory holding nothing at
# all would not do: the shell itself would not be found and the runner would die
# 127 before reaching its own first line, which looks like a pass to a status
# check and proves nothing.
mkdir -p "$WORK/req_full" "$WORK/req_nosed"
for _t in sh "$SH" awk cmp head mktemp mv rm sed tail tr wc grep dirname basename; do
	ln -sf "$(command -v "$_t")" "$WORK/req_full/$_t" 2> /dev/null
	[ "$_t" = "sed" ] || ln -sf "$(command -v "$_t")" "$WORK/req_nosed/$_t" 2> /dev/null
done
printf 'x\n' > "$WORK/req_exp.txt"
printf '#!/bin/sh\nprintf "x\\n"\n' > "$WORK/req_bin"
chmod +x "$WORK/req_bin"

# The control. Same runner, same arguments, on a PATH that has everything: it
# must still work, or the two arms below would prove only that the PATH was
# broken.
want_green "require: a complete PATH leaves the runner working" -- \
	env PATH="$WORK/req_full" "$SH" "$TOOLS/diff_output.sh" \
		--bin "$WORK/req_bin" --expected "$WORK/req_exp.txt"

# One tool removed, and the message has to name THAT tool -- not the first in
# the list, and not a generic "something is missing". The whole value of the
# probe is that it turns an invisible degradation into a sentence someone can
# act on.
want_broken "require: a missing tool refuses with 2 and names it" \
	"required command 'sed' is not on PATH" -- \
	env PATH="$WORK/req_nosed" "$SH" "$TOOLS/diff_output.sh" \
		--bin "$WORK/req_bin" --expected "$WORK/req_exp.txt"

# asan_run.sh is the runner the whole item was raised about, so it gets its own
# arm rather than being assumed to behave like its sibling.
want_broken "require: asan_run refuses rather than mis-reporting a finding" \
	"required command 'sed' is not on PATH" -- \
	env PATH="$WORK/req_nosed" "$SH" "$TOOLS/asan_run.sh" --bin "$WORK/req_bin"

# ------------------------------------------------------- a flag with no value
# `--src` at the end of the command line reads $2 under `set -u`, and until the
# guard reached every arm that was a RAW SHELL ERROR whose status depended on
# the shell: dash exits 2 ("2: parameter not set"), bash exits 1 ("$2: unbound
# variable"). Both were measured on this tree before the fix.
#
# That 1 is the problem, and it is worse under :selftest_bash than anywhere
# else: want_red above treats exit 1 as "the runner detected the thing it exists
# to detect", so on bash a runner that had merely FALLEN OVER on its own
# argument list was scored as a correct red. The one target written to catch
# shell divergence was the one blind to it.
#
# Both halves are asserted -- status 2 AND a message naming the flag -- because
# a refusal nobody can act on is only half of one. These arms run under both
# shells, which is the whole point.
for _spec in symbols_test:--src compile_check:--src ilp32_test:--clues \
	asan_check:--hdr prototype_check:--src files_test:--required \
	header_check:--main shell_test:--env valgrind_test:--gate-stdin; do
	_r=${_spec%%:*}
	_flag=${_spec#*:}
	want_broken "need: $_r refuses $_flag with no value, naming it" \
		"$_flag needs a value" -- \
		"$SH" "$TOOLS/$_r.sh" "$_flag"
done

# ---------------------------------------------------------------- conventions
# The style gate, which until now was the one check in the repo with no arm --
# and it is the check that decides whether every OTHER script still declares
# what it takes from PATH. Its detector is a shell parser written in awk, i.e.
# exactly the kind of thing that quietly stops matching and goes on reporting
# OK: the failure this whole file exists for, sitting inside the guard against
# it.
#
# Driven over a THROWAWAY workspace of probe scripts. conventions.sh takes its
# root from $BUILD_WORKSPACE_DIRECTORY, so pointing that at a fixture tree runs
# the real script against known inputs. The run also reports the fixture's
# missing .bazelrc, defs.bzl and reference.md, and that is fine -- every arm
# below asserts on ONE named probe rather than on the exit status.
#
# No --shellcheck is passed on purpose: these arms are about the require
# detector, and linting four probe scripts would only add noise it might trip on.
mkdir -p "$WORK/cv/tools/tests"

# Calls two PATH commands, declares neither.
printf '#!/bin/sh\nset -u\ngit status\ngrep x file\n' \
	> "$WORK/cv/tools/probe_undeclared.sh"

# Declares exactly what it calls, INCLUDING git. This is the arm the old
# vocabulary made impossible: it listed 24 coreutils names, so `git` was
# invisible to the scanner, `used` came back without it, and a correct
# declaration was reported as drift. The check punished the one thing it exists
# to encourage, which is why no script declared git, cc, make or md5sum.
printf '#!/bin/sh\nset -u\nrequire() { :; }\nrequire git grep\ngit status\ngrep x file\n' \
	> "$WORK/cv/tools/probe_declared.sh"

# Names two tools INSIDE quoted messages and calls neither. The scanner splits
# on | ; & ( ) to find command position, so "--mode must be norm|diff|check"
# used to yield a fragment `diff`, and "(nm failed)" a fragment `nm`. Both were
# counted as calls -- a phantom dependency that shell_test.sh actually carried
# in its require line for as long as the check has existed.
{
	printf '#!/bin/sh\nset -u\nrequire() { :; }\nrequire grep\n'
	printf 'echo "--mode must be norm|diff|check"\n'
	printf 'echo "cannot read symbols from x (nm failed)"\n'
	printf 'grep x file\n'
} > "$WORK/cv/tools/probe_quoted.sh"

# Probes for a tool and degrades without it, so it must NOT go in require --
# require exits 2 on absence, which would turn "this layer says less" into "the
# harness is broken". The marker is what says so, and it is per-tool so that
# each exemption is a reviewable sentence rather than a word missing from a list.
#
# The tool name is passed as a printf ARGUMENT rather than written into the
# format string, and that is not style: the require scanner has no idea it is
# reading a line that WRITES shell rather than one that runs it, so
# `... && git status\n' inside a printf reads as a call in command position and
# reports selftest.sh itself as taking git from PATH. Keeping the word out of
# command position is the honest fix -- the alternative is declaring a tool this
# file does not use, and the scanner staying strict about text it cannot
# interpret is the behaviour worth having.
_g="git"
{
	printf '#!/bin/sh\nset -u\nrequire() { :; }\nrequire grep\n'
	printf '# conventions: optional %s -- probed; without it this probe does less\n' "$_g"
	printf 'command -v %s >/dev/null 2>&1 && %s status\n' "$_g" "$_g"
	printf 'grep x file\n'
} > "$WORK/cv/tools/probe_optional.sh"

CONV="env BUILD_WORKSPACE_DIRECTORY=$WORK/cv $SH $TOOLS/conventions.sh"

want_out "conventions: an undeclared PATH command is reported" \
	"probe_undeclared.sh calls PATH commands and declares none" -- \
	$CONV

want_out "conventions: and it NAMES the tools, not just the file" \
	"uses: git grep" -- \
	$CONV

want_broken_none "conventions: a correct declaration incl. git is accepted" \
	"probe_declared.sh" -- \
	$CONV

want_broken_none "conventions: a tool named in a quoted string is not a call" \
	"probe_quoted.sh" -- \
	$CONV

want_broken_none "conventions: 'optional <tool>' exempts a probed tool" \
	"probe_optional.sh" -- \
	$CONV

# The sanitize-pair invariant. c-02 ex12 shipped for months with
# c_function(sanitize = True) and a c_diff that did not gate on it, so the gate
# compared a real address against a fixture of offsets, called a CORRECT
# exercise red, and three layers skipped green forever. Two fixture modules, one
# of each shape, in one run.
mkdir -p "$WORK/cv/c-piscine-c-98" "$WORK/cv/c-piscine-c-99"
{
	printf 'c_function(num = "07", fn = "ft_x", test = "t.c", sanitize = True)\n\n'
	printf 'c_diff(\n    num = "07",\n    fn = "ft_x",\n    harness = "d.c",\n'
	printf '    oracle_fn = "o",\n    gate_sanitize = True,\n)\n'
} > "$WORK/cv/c-piscine-c-98/BUILD.bazel"
{
	printf 'c_function(num = "07", fn = "ft_x", test = "t.c", sanitize = True)\n\n'
	printf 'c_diff(\n    num = "07",\n    fn = "ft_x",\n    harness = "d.c",\n'
	printf '    oracle_fn = "o",\n)\n'
} > "$WORK/cv/c-piscine-c-99/BUILD.bazel"

# submit.sh's gate ladder is a THIRD copy of the layer table -- the one the
# docs-vs-_LAYER_LEVEL check never covered, which is why it lost allocfail and
# told anyone reading it that `robust` ran less than it does. The fixture is
# synthetic on purpose: a made-up layer name keeps the arm from going red the
# day the real layer set changes, which is a property of this check and not of
# this repo's layers.
printf '_LAYER_LEVEL = {\n    "norm": 1,\n    "widget": 3,\n}\n' \
	> "$WORK/cv/tools/defs.bzl"
{
	printf '#!/bin/sh\n'
	printf 'echo "           valid levels, each also running the ones before it:"\n'
	printf 'echo "             basic     norm"\n'
	printf 'echo "           set it per-user with:  export SUBMIT_GATE=complete"\n'
} > "$WORK/cv/tools/submit.sh"

want_out "conventions: a layer missing from submit's ladder is reported" \
	"missing: widget" -- \
	$CONV

want_broken_none "conventions: and a layer the ladder DOES name is not" \
	"missing: norm" -- \
	$CONV

want_out "conventions: an ungated sanitize pair is reported" \
	"c-piscine-c-99/BUILD.bazel has a c_function(sanitize) whose c_diff does not gate on it" -- \
	$CONV

want_broken_none "conventions: a correctly gated sanitize pair is accepted" \
	"c-piscine-c-98/BUILD.bazel has a c_function" -- \
	$CONV

# ------------------------------------------------------------------ allocfail
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

want_green "allocfail: checking malloc's answer survives a refusal" -- \
	"$SH" "$TOOLS/allocfail_check.sh" --src "$WORK/af_good.c" \
		--harness "$WORK/af_case.c" --shim "$TOOLS/allocfail_shim.c" --label af_good
want_red   "allocfail: using the pointer regardless is caught" -- \
	"$SH" "$TOOLS/allocfail_check.sh" --src "$WORK/af_bad.c" \
		--harness "$WORK/af_case.c" --shim "$TOOLS/allocfail_shim.c" --label af_bad

# ------------------------------------------------------------------ stub_check
# The one runner here whose failure is not a red exercise but a PUBLISHED answer.
# stub_check.sh is what stands between the owner's finished work and the template
# branch other people clone, and it has already failed once in exactly the way
# this file exists to catch: it globbed `*/deliverable/*.c`, so it printed
# "OK — all 123 deliverable(s) are stubs" over a tree in which c-08's four
# answers were sitting untouched, because c-08's deliverable IS a header. Those
# four shipped. So did rush-00's rush.h with the owner's struct layout in it, and
# all 18 shell generators, for the same reason: a check that reports on the files
# it happens to look at says nothing about the ones it does not.
#
# Hence one green and one red per KIND, rather than a couple of representative
# cases — the failure mode being guarded against is a whole kind falling out of
# scope, which a passing arm on a neighbouring kind would not notice. The reds
# have the real published SHAPES — a function-like macro, and a lone prototype,
# which is what c-08 ex00 through ex03 each turn in. The fixtures deliberately do
# NOT reproduce those answers: this file ships on the template, so a fixture that
# quoted one would hand it over through the very test that exists to stop it.
# SQUARE and ft_selftest_len are not exercises anywhere in this repo.
#
# --file is used instead of the repo mode because repo mode is built on
# `git ls-files`, and a self-test that needs a populated git repository is one
# that will not run hermetically.
mkdir -p "$WORK/sc"
SC_H='/* ************************************************************************** */
/*                                        stub_check selftest fixture           */
/* ************************************************************************** */'
printf '%s\n\n#ifndef FT_ABS_H\n# define FT_ABS_H\n\n#endif\n' "$SC_H" > "$WORK/sc/guards.h"
printf '%s\n\n#ifndef SC_MACRO_H\n# define SC_MACRO_H\n# define SQUARE(n) ((n) * (n))\n#endif\n' \
	"$SC_H" > "$WORK/sc/macro.h"
printf '%s\n\n#ifndef SC_PROTO_H\n# define SC_PROTO_H\n\nint\tft_selftest_len(char *str);\n\n#endif\n' \
	"$SC_H" > "$WORK/sc/proto.h"
cat > "$WORK/sc/stub.c" <<'SC_STUB'
void	ft_putchar(char c)
{
	(void)c;
}
SC_STUB
cat > "$WORK/sc/answer.c" <<'SC_ANSWER'
#include <unistd.h>

void	ft_putchar(char c)
{
	write(1, &c, 1);
}
SC_ANSWER
printf 'NAME = ft_hexdump\n\nall:\n\t@echo "TODO: build $(NAME)"\n' > "$WORK/sc/Makefile"
mkdir -p "$WORK/sc/real"
printf 'NAME = ft_hexdump\n\nall:\n\tcc -Wall -Wextra -Werror -o $(NAME) main.c\n' \
	> "$WORK/sc/real/Makefile"
printf '#!/bin/sh\n# ex04: describe the deliverable.\n# TODO: write the commands.\n:\n' \
	> "$WORK/sc/ex04.sh"
printf '#!/bin/sh\n# ex04: describe the deliverable.\nmkdir -p a && ln -s a b\n' \
	> "$WORK/sc/real_ex04.sh"

want_green "stub_check: a .c stub passes" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/stub.c"
want_red   "stub_check: a .c with a real body fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/answer.c"
want_green "stub_check: a guards-only .h passes" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/guards.h"
want_red   "stub_check: a .h defining the answer macro fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/macro.h"
want_red   "stub_check: a .h carrying a prototype fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/proto.h"
want_green "stub_check: a Makefile that only echoes passes" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/Makefile"
want_red   "stub_check: a Makefile that compiles fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/real/Makefile"
want_green "stub_check: a generator reduced to ':' passes" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/ex04.sh"
want_red   "stub_check: a generator that still runs commands fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/real_ex04.sh"

# ---- REPO MODE, which is the mode that decides whether answers get published --
#
# Everything above drives --file mode, and --file mode reads the path it is
# handed. Repo mode does something else: it takes the file LIST from the INDEX
# (git ls-files) and used to read the CONTENT from disk. Those are two different
# trees, and `git commit` publishes the first one.
#
# docs/publishing.md tells the maintainer to run this twice -- after stubbing,
# then "again, over the staged tree". Both runs read the same working-tree
# files, so the second proved nothing the first had not, and an answer left in
# the index behind a stubbed file on disk was reported as a stub. That is the
# whole publish gate reporting OK on the one input it exists to reject.
#
# This needs a populated git repository, which is why repo mode had no arm at
# all. It is worth the fixture: this is the only failure in the repo whose blast
# radius is a permanently public answer.
mkdir -p "$WORK/screpo/c-piscine-c-99/deliverable/ex00"
(
	cd "$WORK/screpo" || exit 1
	git init -q .
	git config user.email selftest@example.invalid
	git config user.name selftest
	printf 'int\tft_x(int n)\n{\n\tif (n <= 1)\n\t\treturn (1);\n\treturn (n * ft_x(n - 1));\n}\n' \
		> c-piscine-c-99/deliverable/ex00/ft_x.c
	git add -A && git commit -q -m answer
	# Stub it ON DISK ONLY. The index still holds the answer -- exactly what a
	# forgotten or partial `git add -A` leaves behind.
	printf 'int\tft_x(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' \
		> c-piscine-c-99/deliverable/ex00/ft_x.c
) >/dev/null 2>&1

want_red   "stub_check: an answer STAGED behind a stubbed file is caught" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo" "$SH" "$TOOLS/stub_check.sh"

# And the reverse, so the arm above is not passing for some unrelated reason:
# once the stub is staged too, the same tree is clean.
( cd "$WORK/screpo" && git add -A && git commit -q -m stubbed ) >/dev/null 2>&1
want_green "stub_check: ... and passes once the stub is the staged content" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo" "$SH" "$TOOLS/stub_check.sh"

# A tracked deliverable of a kind no checker knows must be REPORTED, not
# dropped. --file mode has always exited 2 on one; repo mode silently skipped
# it, which is how c-08's four finished headers once shipped under "OK — all 123
# deliverable(s) are stubs". The same hole is open one kind further along today:
# rush-02 turns in a README.md carrying a teammate's real 42 login and email.
(
	cd "$WORK/screpo" || exit 1
	printf '# By: someone <someone@student.42.fr>\n' \
		> c-piscine-c-99/deliverable/ex00/README.md
	git add -A && git commit -q -m readme
) >/dev/null 2>&1
want_red   "stub_check: a deliverable of an unknown kind is reported" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo" "$SH" "$TOOLS/stub_check.sh"

# The approved-header pins are by CONTENT, and this is the arm that proves it.
# The fixture is named ft_list.h and shaped like ft_list.h — a path- or
# basename-keyed allowlist would wave it straight through — but its bytes are
# not the approved ones, so it must go red. That distinction is the whole reason
# the pin is a hash: "someone forgot to reduce rush.h" and "rush.h is the
# reviewed one" are the same path, and only the content tells them apart.
printf '%s\n\n#ifndef FT_LIST_H\n# define FT_LIST_H\n\ntypedef struct s_list\n{\n\tstruct s_list\t*next;\n\tvoid\t\t\t*data;\n}\t\t\t\tt_list;\n\n#endif\n' \
	"$SC_H" > "$WORK/sc/ft_list.h"
want_red   "stub_check: a header is approved by its bytes, not by its name" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/ft_list.h"

# ...and not by its bytes ALONE either. Approval is (hash, path), because the
# first version keyed on content and c-09's includes/ft.h happens to hold the
# same five prototypes as c-08 ex00's ft.h -- so approving one approved the
# other, and c-08 ex00 shipped its answer and went GREEN. Identical bytes,
# opposite meanings, decided by where the file sits. These two are byte-identical
# and neither is at an approved path, so both must be red.
cp "$WORK/sc/ft_list.h" "$WORK/sc/ft_list_elsewhere.h"
want_red   "stub_check: identical bytes, first path" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/ft_list.h"
want_red   "stub_check: identical bytes, second path" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/ft_list_elsewhere.h"

# And the hash itself must ignore the 42 header, or every re-stamp would revoke
# every approval. Same bytes below the block, two different identities in it.
printf '/* By: marvin <marvin@42.fr> */\n#ifndef X_H\n# define X_H\n#endif\n' > "$WORK/sc/h1.h"
printf '/* By: someone <someone@42.fr> */\n#ifndef X_H\n# define X_H\n#endif\n' > "$WORK/sc/h2.h"
_h1=$("$SH" "$TOOLS/stub_check.sh" --hash "$WORK/sc/h1.h" | cut -d' ' -f1)
_h2=$("$SH" "$TOOLS/stub_check.sh" --hash "$WORK/sc/h2.h" | cut -d' ' -f1)
# The emptiness test is the point. This was one `[ "$(...)" = "$(...)" ]`, so a
# --hash mode that printed NOTHING AT ALL compared "" with "" and the arm
# reported success -- an assertion that two hashes agree, satisfied by there
# being no hashes. A 32-character md5 prefix is what it is supposed to produce.
if [ ${#_h1} -ne 32 ] || [ ${#_h2} -ne 32 ]; then
	printf '  %-52s %s\n' "stub_check: --hash ignores the 42 header block" \
		"FAIL < (--hash produced no hash: '$_h1' / '$_h2')"
	FAIL=$((FAIL + 1))
elif [ "$_h1" = "$_h2" ]; then
	printf '  %-52s %s\n' "stub_check: --hash ignores the 42 header block" "ok (green, as required)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "stub_check: --hash ignores the 42 header block" \
		"FAIL < (a re-stamp would revoke every approval)"
	FAIL=$((FAIL + 1))
fi

# ...and it must NOT ignore anything else that shares a line with a comment.
# `^/\*.*\*/$` reads as "a line that is one comment", but `.*` is greedy, so
# it also matched a line whose middle is code between two comment markers.
# Reproduced: the pair below, differing by a whole variable definition,
# produced the same hash -- so an approved entry approved the smuggled copy.
printf '/* By: marvin <marvin@42.fr> */\n/* */ int g_answer = 42; /* */\n#ifndef X_H\n# define X_H\n#endif\n' > "$WORK/sc/h3.h"
_h3=$("$SH" "$TOOLS/stub_check.sh" --hash "$WORK/sc/h3.h" | cut -d' ' -f1)
if [ ${#_h3} -ne 32 ]; then
	printf '  %-52s %s\n' "stub_check: --hash sees code between two comments" \
		"FAIL < (--hash produced no hash: '$_h3')"
	FAIL=$((FAIL + 1))
elif [ "$_h3" != "$_h1" ]; then
	printf '  %-52s %s\n' "stub_check: --hash sees code between two comments" "ok (green, as required)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "stub_check: --hash sees code between two comments" \
		"FAIL < (a definition hashed the same as no line at all)"
	FAIL=$((FAIL + 1))
fi

# THE DEPTH A LINE IS JUDGED AT. Braces used to be counted after the line was
# scored, so everything sharing a line with its own opening brace was scored at
# depth 0 -- outside every function body, where anything is allowed. A whole
# working function written on one line was reported as a stub.
printf 'int\tft_double(int n) { return (n * 2); }\n' > "$WORK/sc/oneline.c"
printf 'int\tft_f(void)\n{\tint i;\n\treturn (0);\n}\n' > "$WORK/sc/braceline.c"
want_red   "stub_check: a whole function on one line is not a stub" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/oneline.c"
want_red   "stub_check: a declaration on the brace line is examined" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/braceline.c"
# ...and the forms a real stub is written in must still pass, on one line too:
# the fix must not turn `{ return (0); }` into a finding.
printf 'int\tft_f(void) { return (0); }\n\nvoid\tft_g(int n) { (void)n; }\n' > "$WORK/sc/onelinestub.c"
want_green "stub_check: a one-line stub body still passes" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/onelinestub.c"

# -------------------------------------------------------------------------- setup
# The script every single user runs, exactly once, before anything else exists
# -- and therefore the one whose failure nobody can debug with the harness,
# because the harness is what it installs. It is driven here OFFLINE through
# SETUP_BAZELISK_URL (a file:// URL) and SETUP_BAZELISK_SHA256, so these arms
# need no network and no campus box.
#
# The red arm is the one that matters: a checksum mismatch must REFUSE, because
# the alternative is chmod +x on whatever that URL served today. setup.sh
# verifies before it makes the file executable, so a rejected download is never
# a thing the machine could run -- the second assertion below is what pins that
# ordering down rather than trusting the comment.
mkdir -p "$WORK/su/repo/tools" "$WORK/su/home"
printf 'fake bazelisk payload\n' > "$WORK/su/payload"
SU_SHA=$(sha256sum "$WORK/su/payload" | cut -d' ' -f1)
cp "$TOOLS/setup.sh" "$WORK/su/repo/tools/setup.sh"
: > "$WORK/su/repo/.bazelversion"
printf '# pre-existing line\n' > "$WORK/su/home/.bashrc"

# "$SH", not a literal `sh`. These five arms are the only coverage setup.sh has,
# and with `sh` hard-coded :selftest_bash replayed every OTHER arm under bash
# while silently re-running these under dash -- so the one script that runs
# before Bazel exists, on a machine whose shell nobody chose, was the one the
# cross-shell target never reached.
su_run() {  # su_run SHA -- runs setup.sh against the sandbox, offline
	( cd "$WORK/su/repo" && env HOME="$WORK/su/home" USER=probe \
		SETUP_BAZELISK_URL="file://$WORK/su/payload" \
		SETUP_BAZELISK_SHA256="$1" SETUP_SKIP_DRIFT=1 \
		"$SH" tools/setup.sh )
}

want_green "setup: a download matching its pin installs" -- su_run "$SU_SHA"
want_green "setup: running it twice is idempotent" -- su_run "$SU_SHA"

if [ "$(grep -c '>>> 42 c-piscine setup >>>' "$WORK/su/home/.bashrc")" = "1" ] &&
   [ "$(grep -c 'pre-existing line' "$WORK/su/home/.bashrc")" = "1" ]; then
	printf '  %-52s %s\n' "setup: one profile block, prior content intact" "ok (green, as required)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "setup: one profile block, prior content intact" \
		"FAIL < (duplicated the block or ate the file)"
	FAIL=$((FAIL + 1))
fi

# WHERE THE CACHE GOES, off campus. This script is useful outside the
# devcontainer -- bazelisk is the only thing the suite really needs -- and the
# first version chose on `[ -d /goinfre ]` alone, falling back to /tmp. Two
# things were wrong with that away from campus: a /goinfre that exists but is
# not writable killed the run outright, and /tmp is a RAM-backed tmpfs on many
# Linux desktops, where an 8.9 GB build tree is 8.9 GB of memory.
#
# The sandbox has no /goinfre, so these pin the off-campus path: it lands in the
# cache directory (which survives a reboot, unlike /tmp), and it says so.
if grep -q 'output_user_root=.*/\.cache/42-piscine/bazel' "$WORK/su/repo/.bazelrc.local"; then
	printf '  %-52s %s\n' "setup: off campus the cache lands somewhere persistent" \
		"ok (green, as required)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "setup: off campus the cache lands somewhere persistent" \
		"FAIL < ($(cat "$WORK/su/repo/.bazelrc.local" 2>/dev/null | tail -1))"
	FAIL=$((FAIL + 1))
fi

# And re-running after an upgrade must not RELOCATE it. The candidate order has
# already changed once; without this every existing install would quietly move
# and re-download 2.1 GB of pinned tools while the old tree kept the space.
mkdir -p "$WORK/su/keep"
printf 'startup --output_user_root=%s/bazel\n' "$WORK/su/keep" > "$WORK/su/repo/.bazelrc.local"
su_run "$SU_SHA" > /dev/null 2>&1
if grep -q "output_user_root=$WORK/su/keep/bazel" "$WORK/su/repo/.bazelrc.local"; then
	printf '  %-52s %s\n' "setup: and a second run keeps the choice already made" \
		"ok (green, as required)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "setup: and a second run keeps the choice already made" \
		"FAIL < (relocated an existing cache)"
	FAIL=$((FAIL + 1))
fi

# ...including one this script did NOT write. The branch above says, in its own
# output, ".bazelrc.local: already sets output_user_root -- left alone", so a
# root without setup.sh's `/bazel` suffix is a state the repo produces on
# purpose. The sticky read was anchored to `/bazel$` and matched only setup.sh's
# own output, so on the next run that path went unread and the candidate list
# chose somewhere else -- leaving the free-space check, the tmpfs warning and
# prime.sh's sentinel all describing a directory Bazel does not use.
mkdir -p "$WORK/su/hand"
printf 'startup --output_user_root=%s\n' "$WORK/su/hand" > "$WORK/su/repo/.bazelrc.local"
want_out "setup: a hand-written output_user_root is honoured" \
	"$WORK/su/hand  -- already chosen" -- su_run "$SU_SHA"

# An unwritable C_PISCINE_SCRATCH must say so rather than fall through to a
# directory the user did not ask for: they named a disk for a reason.
mkdir -p "$WORK/su/ro" && chmod 555 "$WORK/su/ro"
# want_red plus want_out, not want_broken: setup.sh is an installer and its
# `die` exits 1 for everything, which is right for a script whose reader is a
# person at a prompt rather than a test harness reading a status.
su_ro() {
	env HOME="$WORK/su/home" USER=probe C_PISCINE_SCRATCH="$WORK/su/ro/x" \
		SETUP_BAZELISK_URL="file://$WORK/su/payload" \
		SETUP_BAZELISK_SHA256="$SU_SHA" SETUP_SKIP_DRIFT=1 \
		"$SH" "$WORK/su/repo/tools/setup.sh"
}
want_red "setup: an unwritable C_PISCINE_SCRATCH stops rather than guessing" -- su_ro
want_out "setup: and names the variable it could not use" \
	'C_PISCINE_SCRATCH is set to' -- su_ro

rm -rf "$WORK/su/home/.local"
want_red   "setup: a checksum mismatch is refused" -- \
	su_run 0000000000000000000000000000000000000000000000000000000000000000
if [ -e "$WORK/su/home/.local/bin/bazelisk" ]; then
	printf '  %-52s %s\n' "setup: the rejected file is not left installed" \
		"FAIL < (installed it anyway)"
	FAIL=$((FAIL + 1))
else
	printf '  %-52s %s\n' "setup: the rejected file is not left installed" "ok (green, as required)"
	PASS=$((PASS + 1))
fi

# --------------------------------------------------------------------- prime
# prime.sh --background is wired into the shell profile, which makes ONE
# property matter more than the rest: it must never break a login shell. If it
# can exit non-zero, or block, then every terminal opened on a machine where
# something is off greets the student with an error they cannot act on -- from
# a script whose whole purpose is convenience.
#
# So these run it in the hostile cases deliberately: with NO bazel anywhere on
# PATH, and twice in a row. Both must exit 0 and neither may hang.
mkdir -p "$WORK/pr/bin" "$WORK/pr/home"
# `cat` is in this list because prime.sh prints its two explanatory blocks with
# a heredoc, and it declares it. A tool the runner requires but the fixture PATH
# withholds makes the runner exit 2 -- which want_green reports as "red; it must
# not be", i.e. an arm failing for a reason that has nothing to do with what it
# tests. The list has to hold everything the runner declares, minus the one
# tool a given arm is deliberately hiding.
for _b in sh "$SH" env mkdir rmdir rm printf cat find id dirname pwd cd sed tail; do
	_p=$(command -v "$_b" 2>/dev/null) && ln -sf "$_p" "$WORK/pr/bin/$_b" 2>/dev/null
done

pr_run() {
	# No `cd` here: $TOOLS is relative (it comes from --anchor), so changing
	# directory first would make "$TOOLS/prime.sh" unopenable -- which is exactly
	# what the first version of this arm did, and what want_green caught.
	env PATH="$WORK/pr/bin" USER=selftestprime HOME="$WORK/pr/home" \
		C_PISCINE_SCRATCH="$WORK/pr/scratch" \
		"$SH" "$TOOLS/prime.sh" --background >/dev/null 2>&1
}

want_green "prime: --background exits 0 with no bazel on PATH" -- pr_run
want_green "prime: --background is a no-op the second time" -- pr_run

# WHICH SCRATCH IT PICKS, which is a different question from whether it exits 0
# -- and the one that was wrong. setup.sh probes four candidates and records the
# winner in .bazelrc.local; prime.sh guessed again from three unprobed ones, so
# on any machine where setup.sh had a REASON to move (an unwritable /goinfre, a
# /tmp too small for 8.9 GB) the two disagreed and prime.sh wrote gigabytes to
# the directory setup.sh had rejected.
#
# The assertion is positive: the path prime.sh announces its log at IS the
# scratch it chose. C_PISCINE_SCRATCH is deliberately absent from this env --
# setting it would answer the question the arm is asking.
mkdir -p "$WORK/pr/ws" "$WORK/pr/recorded"
printf 'startup --output_user_root=%s/bazel\n' "$WORK/pr/recorded" > "$WORK/pr/ws/.bazelrc.local"
pr_scratch() {
	env PATH="$WORK/pr/bin" USER=selftestprime HOME="$WORK/pr/home" \
		BUILD_WORKSPACE_DIRECTORY="$WORK/pr/ws" \
		"$SH" "$TOOLS/prime.sh" --background 2>&1
}
want_out "prime: uses the scratch setup.sh recorded" \
	"$WORK/pr/recorded/prime.log" -- pr_scratch

# ...and a hand-written root is read too. setup.sh's own message for an existing
# .bazelrc.local is "already sets output_user_root -- left alone", so a path
# that does not end in /bazel is a state this repo produces on purpose. The read
# was anchored to `/bazel$` and saw only setup.sh's own output.
rm -rf "$WORK/pr/recorded" "$WORK/pr/hand"
mkdir -p "$WORK/pr/hand"
printf 'startup --output_user_root=%s\n' "$WORK/pr/hand" > "$WORK/pr/ws/.bazelrc.local"
want_out "prime: reads a hand-written output_user_root too" \
	"$WORK/pr/hand/prime.log" -- pr_scratch

# ------------------------------------------------------------------ rush01
# 1346 lines, and until now not one arm here -- while being the ONLY correctness
# check c-piscine-rush-01 has. It does not diff: the subject asks for "the first
# solution you encounter" and 66 of the 438 solvable clue vectors have more than
# one answer, so it VALIDATES the printed grid instead (a Latin square meeting
# all 16 visibility clues). If that validation ever stopped validating, every
# rush01 submission would pass and nothing else in the repo would notice.
#
# The corpus is written here rather than taken from //oracle so these stay in the
# fast selftest -- the reference needs a Rust build. Its shape is the documented
# one: <16 clues>\t<solution>..., and a line with no solution field means Error
# is the right answer. The six solvable vectors were enumerated independently of
# this repo (all 576 Latin squares of order 4 -> 438 distinct clue vectors, 372
# of them with a unique solution, which reproduces oracle/README.md's figures);
# the four unsolvable ones are vectors that enumeration proves no square yields.
mkdir -p "$WORK/r1"
{
	printf '1 2 2 2 4 1 2 3 1 2 2 2 4 1 2 3\t4321321421431432\n'
	printf '1 2 2 2 4 1 3 2 1 2 3 2 3 2 1 2\t4312324121341423\n'
	printf '1 2 2 2 4 2 1 3 1 2 2 3 3 1 2 2\t4231312424131342\n'
	printf '1 2 2 2 4 2 3 1 1 2 2 3 2 2 3 1\t4213314224311324\n'
	printf '1 2 2 2 4 3 1 2 1 2 3 3 3 3 1 2\t4132342123141243\n'
	printf '1 2 2 2 4 3 2 1 1 2 3 4 2 2 2 1\t4123341223411234\n'
	printf '3 2 4 1 1 1 3 1 2 1 1 4 4 1 2 1\t\n'
	printf '4 1 1 2 1 4 1 2 1 2 3 4 2 1 3 2\t\n'
	printf '1 2 3 1 1 1 2 4 4 3 4 4 3 3 2 2\t\n'
	printf '2 1 3 4 3 4 3 1 1 4 2 3 2 4 4 1\t\n'
} > "$WORK/r1/corpus.tsv"

# A solver that answers each solvable vector correctly and Errors on the rest.
cat > "$WORK/r1/good.sh" <<'R1_GOOD'
#!/bin/sh
case "$1" in
  "1 2 2 2 4 1 2 3 1 2 2 2 4 1 2 3") printf '4 3 2 1\n3 2 1 4\n2 1 4 3\n1 4 3 2\n' ;;
  "1 2 2 2 4 1 3 2 1 2 3 2 3 2 1 2") printf '4 3 1 2\n3 2 4 1\n2 1 3 4\n1 4 2 3\n' ;;
  "1 2 2 2 4 2 1 3 1 2 2 3 3 1 2 2") printf '4 2 3 1\n3 1 2 4\n2 4 1 3\n1 3 4 2\n' ;;
  "1 2 2 2 4 2 3 1 1 2 2 3 2 2 3 1") printf '4 2 1 3\n3 1 4 2\n2 4 3 1\n1 3 2 4\n' ;;
  "1 2 2 2 4 3 1 2 1 2 3 3 3 3 1 2") printf '4 1 3 2\n3 4 2 1\n2 3 1 4\n1 2 4 3\n' ;;
  "1 2 2 2 4 3 2 1 1 2 3 4 2 2 2 1") printf '4 1 2 3\n3 4 1 2\n2 3 4 1\n1 2 3 4\n' ;;
  *) printf 'Error\n' ;;
esac
R1_GOOD
# Always prints ONE valid Latin square. It is a real grid and it satisfies its
# own clues -- for every other vector it is simply the wrong answer, which is
# exactly what a validator that stopped checking the clues would wave through.
printf '#!/bin/sh\nprintf %s\n' "'1 2 3 4\\n2 3 4 1\\n3 4 1 2\\n4 1 2 3\\n'" > "$WORK/r1/wrong.sh"
printf '#!/bin/sh\nprintf %s\n' "'Error\\n'" > "$WORK/r1/allerr.sh"
# Not a Latin square at all: every cell the same height.
printf '#!/bin/sh\nprintf %s\n' "'1 1 1 1\\n1 1 1 1\\n1 1 1 1\\n1 1 1 1\\n'" > "$WORK/r1/notlatin.sh"
chmod +x "$WORK/r1"/*.sh

r1_run() { "$SH" "$TOOLS/rush01_check.sh" --bin "$WORK/r1/$1.sh" \
	--corpus "$WORK/r1/corpus.tsv" --label "selftest-$1"; }

want_green "rush01: a correct solver passes"                    -- r1_run good
want_red   "rush01: a valid grid that ignores the clues fails"   -- r1_run wrong
want_red   "rush01: Error for a solvable vector fails"           -- r1_run allerr
want_red   "rush01: a grid that is not a Latin square fails"     -- r1_run notlatin

# And the guard that protects the guard: a corpus with no unsolvable case would
# validate a program that only ever prints Error. The runner refuses such a
# corpus as a HARNESS error (exit 2), which want_red must NOT accept as a
# detection -- so this is asserted separately.
head -6 "$WORK/r1/corpus.tsv" > "$WORK/r1/solvable_only.tsv"
if "$SH" "$TOOLS/rush01_check.sh" --bin "$WORK/r1/good.sh" \
	--corpus "$WORK/r1/solvable_only.tsv" --label selftest-lopsided >/dev/null 2>&1; then
	printf '  %-52s %s\n' "rush01: a corpus with no Error case is refused" \
		"FAIL < (accepted it)"
	FAIL=$((FAIL + 1))
else
	printf '  %-52s %s\n' "rush01: a corpus with no Error case is refused" \
		"ok (green, as required)"
	PASS=$((PASS + 1))
fi

# ------------------------------------------------------------------ rush02
# The only check c-piscine-rush-02 has, and it had a false green of the exact
# shape this file exists to hunt: an oracle that exited 0 having printed nothing
# left the compare loop with no cases to run, and the report read
# "OK -- 0/0 agree with the reference". Found by writing these arms, not by
# reading the script. tools/rust_diff.sh had already grown MIN_DIFF_CASES for the
# same reason; this runner had not.
#
# The empty-corpus arm asserts exit 2, not 1, and is checked by hand for it: a
# reference that produces nothing is a broken HARNESS, not a wrong student, and
# want_red would rightly refuse to call exit 2 a detection.
mkdir -p "$WORK/r2"
printf '0: zero\n' > "$WORK/r2/dict.txt"
printf '#!/bin/sh\nexit 0\n' > "$WORK/r2/oracle_empty.sh"
{
	printf '#!/bin/sh\ncat <<%sEOF%s\n' "'" "'"
	_i=0
	while [ "$_i" -lt 30 ]; do printf '%s\tn%s\n' "$_i" "$_i"; _i=$((_i + 1)); done
	printf 'EOF\n'
} > "$WORK/r2/oracle_full.sh"
# Agrees with that reference: echoes "n<number>", which is what it emits.
printf '#!/bin/sh\nprintf "n%%s\\n" "$2"\n' > "$WORK/r2/agree.sh"
printf '#!/bin/sh\nprintf "wrong\\n"\n' > "$WORK/r2/disagree.sh"
chmod +x "$WORK/r2"/*.sh

r2_run() { "$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/r2/$1.sh" \
	--dict "$WORK/r2/dict.txt" --oracle "$WORK/r2/$2.sh"; }

want_green "rush02: a converter matching the reference passes" -- r2_run agree oracle_full
want_red   "rush02: one that disagrees everywhere fails"        -- r2_run disagree oracle_full

r2_run agree oracle_empty >/dev/null 2>&1
_r2rc=$?
if [ "$_r2rc" -eq 2 ]; then
	printf '  %-52s %s\n' "rush02: an EMPTY corpus is a harness error, not 0/0" \
		"ok (red, as required)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "rush02: an EMPTY corpus is a harness error, not 0/0" \
		"FAIL < (exit $_r2rc; 0 cases must never read as agreement)"
	FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------------- submit
# The tool that pushes to 42, which had no arm of any kind -- and the defects
# below are all in its REMOTES parser, i.e. in the decision of WHICH module goes
# to WHICH url. Every one of them was reproduced before it was fixed.
#
# Driven with -n (dry-run) and --no-gate over a fixture workspace, so nothing
# runs bazel, nothing touches git, and nothing reaches the network. LOGIN42 and
# EMAIL42 are supplied so the identity check does not short-circuit the parse.
mkdir -p "$WORK/sb/ws/c-piscine-c-00/deliverable" "$WORK/sb/ws/.vscode"
printf '{ "42header.username": "marvin", "42header.email": "marvin@42.fr" }\n' \
	> "$WORK/sb/ws/.vscode/settings.json"

# A copy of the real script with one table row rewritten per fixture.
sb_make() { sed "s|^c-piscine-c-00=.*|$1|" "$TOOLS/submit.sh" > "$WORK/sb/$2.sh"; }
sb_run() {
	env BUILD_WORKSPACE_DIRECTORY="$WORK/sb/ws" LOGIN42=marvin EMAIL42=marvin@42.fr \
		"$SH" "$WORK/sb/$1.sh" -n --no-gate ${2:+"$2"}
}

# 1. A COMMENTED-OUT ROW MUST NOT BE PUSHED. `for entry in $REMOTES` word-split
#    on IFS, so "# c-piscine-c-00=..." became a bare "#" (which the guard
#    skipped) followed by the entry itself (which it did not). The single
#    gesture a person makes to disable a module was the one that did not work.
sb_make '# c-piscine-c-00=git@example.invalid:should-not-run' cmt
want_broken_none "submit: a commented-out table row is not pushed" \
	"should-not-run" -- sb_run cmt

# 2. AN INLINE COMMENT IS NOT PART OF THE URL. docs/submitting.md shows a row
#    written exactly this way; without the fix the tail became the remote, so
#    the row stopped reading as REPLACE_ME and was treated as live.
sb_make 'c-piscine-c-00=REPLACE_ME   # left as REPLACE_ME -> skipped' ic
want_out "submit: an inline comment leaves the row a REPLACE_ME skip" \
	"SKIP  c-piscine-c-00" -- sb_run ic
want_broken_none "submit: ... and does not invent modules from its words" \
	"==>  left" -- sb_run ic

# 3. SPACES AROUND "=" are how a person writes a table row, and produced a
#    module named with a trailing space pointed at a URL with a leading one.
sb_make 'c-piscine-c-00 = git@example.invalid:spaced' sp
want_out "submit: spaces around = still name the module" \
	"==>  c-piscine-c-00 " -- sb_run sp

# 4. A ROW WITH NO "=" is not a table row. ${entry#*=} returns the string
#    UNCHANGED when there is no match, so such a row became a module whose
#    remote was its own name.
sb_make 'c-piscine-c-00-no-equals-here' noeq
want_out "submit: a row with no '=' is reported, not treated as live" \
	"malformed table line" -- sb_run noeq

# 5. A MODULE NAME THAT MATCHES NO ROW must not exit 0. It filtered everything
#    out before any counter moved, so a typo printed the summary and exited 0 --
#    the same output as a submission that worked.
sb_make 'c-piscine-c-00=REPLACE_ME' plain
want_red "submit: a module that is not in the table exits non-zero" -- \
	sb_run plain c-piscine-c-OO
want_green "submit: ... and a real module name still exits 0" -- \
	sb_run plain c-piscine-c-00

# --------------------------------------------------------------------- bsq
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
	printf '#!/bin/sh\ncat <<%sEOF%s\n' "'" "'"
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
	printf 'EOF\n'
} > "$WORK/bs/oracle_ok.sh"
# The same, with invalid files mixed in, for multi mode.
{
	printf '#!/bin/sh\n"%s" "%s"\n' "$SH" "$WORK/bs/oracle_ok.sh"
	printf 'i=0\nwhile [ $i -lt 6 ]; do printf %s i=$((i+1)); done\n' \
		"'err:chars_repeat\\t-1\\t-1\\t-1\\t2.oo\\\\n..\\\\n..\\\\n\\tmap error\\\\n\\n';"
} > "$WORK/bs/oracle_mixed.sh"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bs/oracle_empty.sh"

# The fake students below are WRITTEN, not run, and the tool names in them are
# passed as printf arguments rather than spelled into the format string. The
# require scanner reads a format string as shell -- it has no way to tell a
# printf that emits a script from one that runs commands -- so `| sed ...`
# inside these would be reported as selftest.sh itself taking sed from PATH.
_sd="sed"
_tr="tr"
# Correct: drop the header line, fill every empty cell.
printf '#!/bin/sh\nfor f in "$@"; do %s 1d "$f" | %s "s/[.]/x/g"; done\n' "$_sd" "$_sd" \
	> "$WORK/bs/good.sh"
# Prints the file back untouched -- header and all.
printf '#!/bin/sh\nfor f in "$@"; do %s "$f"; done\n' cat > "$WORK/bs/catty.sh"
# Always claims the file is invalid.
printf '#!/bin/sh\nprintf "map error\\n"\n' > "$WORK/bs/allerr.sh"
# Right bytes, no final newline -- a real Moulinette failure that a
# command-substitution comparison would not see.
printf '#!/bin/sh\nfor f in "$@"; do %s 1d "$f" | %s "s/[.]/x/g" | %s -d "\\n"; done\n' \
	"$_sd" "$_sd" "$_tr" > "$WORK/bs/nonl.sh"
chmod +x "$WORK/bs"/*.sh

bs_run() { "$SH" "$TOOLS/bsq_check.sh" --bin "$WORK/bs/$1.sh" \
	--oracle "$WORK/bs/$2.sh" --show 0; }

want_green "bsq: a solver matching the reference passes"  -- bs_run good oracle_ok
want_red   "bsq: printing the map back unchanged fails"   -- bs_run catty oracle_ok
want_red   "bsq: always answering 'map error' fails"      -- bs_run allerr oracle_ok
want_red   "bsq: a missing final newline fails"           -- bs_run nonl oracle_ok

# The floors. Each names a wrong program that would otherwise pass, and each is
# exit 2 -- a corpus that cannot fail anything is a broken harness, not a wrong
# deliverable, which is why want_red would rightly refuse to count it.
bs_run good oracle_empty > /dev/null 2>&1
_bsrc=$?
if [ "$_bsrc" -eq 2 ]; then
	printf '  %-52s %s\n' "bsq: an EMPTY corpus is a harness error, not 0/0" \
		"ok (red, as required)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "bsq: an EMPTY corpus is a harness error, not 0/0" \
		"FAIL < (exit $_bsrc; it must refuse with 2)"
	FAIL=$((FAIL + 1))
fi

# multi mode without both classes must refuse: a corpus of valid maps alone
# cannot catch "always print map error", and one of invalid files alone cannot
# catch the opposite.
"$SH" "$TOOLS/bsq_check.sh" --bin "$WORK/bs/good.sh" --oracle "$WORK/bs/oracle_ok.sh" \
	--mode multi > /dev/null 2>&1
_bsrc=$?
if [ "$_bsrc" -eq 2 ]; then
	printf '  %-52s %s\n' "bsq: multi mode refuses a single-class corpus" "ok (red, as required)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "bsq: multi mode refuses a single-class corpus" \
		"FAIL < (exit $_bsrc; it must refuse with 2)"
	FAIL=$((FAIL + 1))
fi

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
printf '#!/bin/sh\ncat %s\n' "$WORK/bs/esc_corpus" > "$WORK/bs/oracle_esc.sh"
# Reads the map and answers it: drop the header, fill the one empty cell. It
# touches BOTH decoded blobs, so a broken escape on either side fails the arm.
printf '#!/bin/sh\nfor f in "$@"; do %s 1d "$f" | %s "s/ /x/"; done\n' "$_sd" "$_sd" \
	> "$WORK/bs/escgood.sh"
chmod +x "$WORK/bs/oracle_esc.sh" "$WORK/bs/escgood.sh"

want_green "bsq: a backslash and a space survive the corpus escape" -- \
	bs_run escgood oracle_esc

# ------------------------------------------------------------------ argv_check
# The runner behind c-06's diff layer. Its corpus is a list of ARGUMENTS and the
# bytes they must produce, and every arm below is a program that would pass a
# weaker comparison.
mkdir -p "$WORK/av"

# A corpus holding, in order: the subject's own example, a case with NO
# arguments, one whose argument is EMPTY, one whose argument ends in a NEWLINE,
# and enough filler to clear the floor. Written by hand rather than taken from
# //oracle so these stay in the fast selftest -- the reference needs a Rust
# build, and what is under test here is the runner.
{
	printf 'args\t3\ta\tb\tc\ta\\nb\\nc\\n\n'
	printf 'args\t0\t\n'
	printf 'args\t2\t\tafter\t\\nafter\\n\n'
	printf 'args\t1\tends\\n\tends\\n\\n\n'
	# `tab\\there`, not `tab\there`: this is printf's FORMAT, so a single
	# backslash-t becomes a real tab and silently adds a field to the line.
	printf 'args\t2\ttwo words\ttab\\there\ttwo words\\ntab\\there\\n\n'
	_i=0
	while [ "$_i" -lt 10 ]; do
		printf 'args\t2\tx%s\ty%s\tx%s\\ny%s\\n\n' "$_i" "$_i" "$_i" "$_i"
		_i=$((_i + 1))
	done
} > "$WORK/av/corpus.tsv"
printf '#!/bin/sh\ncat %s\n' "$WORK/av/corpus.tsv" > "$WORK/av/oracle.sh"

# The fake students. Written, not run -- see the note above the bsq ones for why
# the tool names are printf ARGUMENTS and not part of the format string.
_pf="printf"
# Correct: one argument per line, a newline after each.
printf '#!/bin/sh\nfor a in "$@"; do %s "%%s\\n" "$a"; done\n' "$_pf" > "$WORK/av/good.sh"
# The separator bug: a newline BETWEEN arguments rather than after each. Its
# output differs from the correct one only in the final byte, which is exactly
# what c-06's argv TABLE cannot see (it joins lines, so a missing final newline
# is invisible unless the last line is empty) and what `cmp` sees every time.
printf '#!/bin/sh\n_s=""\nfor a in "$@"; do %s "%%s%%s" "$_s" "$a"; _s="\\n"; done\n' \
	"$_pf" > "$WORK/av/nonl.sh"
# Stops at the first empty argument, which is the commonest real mistake here
# and which no case anybody types by hand contains.
printf '#!/bin/sh\nfor a in "$@"; do [ -n "$a" ] || break; %s "%%s\\n" "$a"; done\n' \
	"$_pf" > "$WORK/av/stopsempty.sh"
# Reads stdin. Without `< /dev/null` on every run this eats the rest of the
# corpus, the loop ends after one case, and the layer reports "OK, 1 case".
printf '#!/bin/sh\ncat > /dev/null\nfor a in "$@"; do %s "%%s\\n" "$a"; done\n' \
	"$_pf" > "$WORK/av/eatsstdin.sh"
chmod +x "$WORK/av"/*.sh

av_run() { "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/$1.sh" \
	--oracle "$WORK/av/oracle.sh" --fn fixture --show 0; }

want_green "argv_check: a program matching the reference passes" -- av_run good
want_red   "argv_check: a newline BETWEEN arguments is caught"   -- av_run nonl
want_red   "argv_check: stopping at an empty argument is caught" -- av_run stopsempty
want_green "argv_check: a program that reads stdin is not starved" -- av_run eatsstdin

# An argument ending in a newline must reach the program INTACT. The decode
# strips a sentinel rather than relying on command substitution, which strips
# every trailing newline -- and getting that wrong reported eleven of a hundred
# and twenty CORRECT cases as differences.
want_out "argv_check: a trailing newline survives the decode" \
	'PASS' -- av_run good

# The floors. Each names a corpus that would be passed by a program doing none
# of what the exercise asks, and each is exit 2: a corpus that cannot fail
# anything is a broken harness, not a wrong deliverable.
av_floor() {  # av_floor NAME CORPUS-BUILDER-OUTPUT [extra args...]
	_n="$1"; shift
	printf '#!/bin/sh\ncat %s\n' "$1" > "$WORK/av/oracle_f.sh"
	chmod +x "$WORK/av/oracle_f.sh"
	shift
	"$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/good.sh" \
		--oracle "$WORK/av/oracle_f.sh" --fn fixture "$@" > /dev/null 2>&1
	_rc=$?
	if [ "$_rc" -eq 2 ]; then
		printf '  %-52s %s\n' "$_n" "ok (red, as required)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_n" "FAIL < (exit $_rc; it must refuse with 2)"
		FAIL=$((FAIL + 1))
	fi
}

: > "$WORK/av/empty.tsv"
av_floor "argv_check: an EMPTY corpus is a harness error, not 0/0" "$WORK/av/empty.tsv"

# Every case has arguments and none of them is empty: a program that stops at
# the first empty string, and one that prints a newline for no arguments, both
# pass.
{
	_i=0
	while [ "$_i" -lt 20 ]; do
		printf 'args\t2\tx%s\ty%s\tx%s\\ny%s\\n\n' "$_i" "$_i" "$_i" "$_i"
		_i=$((_i + 1))
	done
} > "$WORK/av/noedge.tsv"
av_floor "argv_check: a corpus with no empty argument is refused" "$WORK/av/noedge.tsv"

# --expect-reordering on a corpus whose every expected block is its arguments in
# the order given: that corpus is passed by a program that reverses and sorts
# nothing at all, so the two arms that ask for reordering must refuse it.
av_floor "argv_check: --expect-reordering refuses an in-order corpus" \
	"$WORK/av/corpus.tsv" --expect-reordering

# ------------------------------------------------------------------ file_check
# The runner behind c-10's diff layer. Its case is a list of flags and a list of
# FILE CONTENTS, which the runner writes to a scratch directory before running
# the binary on those paths.
mkdir -p "$WORK/fc"

# A corpus with the four things a committed fixture never has: an EMPTY file, a
# file containing a NUL, a file over 4096 bytes, and enough cases to clear the
# floor. Line shape: <tag>\t<nflags>\t<flags>\t<nfiles>\t<files>\t<expected>.
_big=$(awk 'BEGIN { s = ""; while (length(s) < 5000) s = s "abcdefghij"; print s }')
{
	printf 'file\t0\t1\t\t\n'
	printf 'file\t0\t1\ta\\0000b\ta\\0000b\n'
	printf 'file\t0\t1\t%s\t%s\n' "$_big" "$_big"
	_i=0
	while [ "$_i" -lt 20 ]; do
		printf 'file\t0\t1\tline%s\\n\tline%s\\n\n' "$_i" "$_i"
		_i=$((_i + 1))
	done
} > "$WORK/fc/corpus.tsv"
printf '#!/bin/sh\ncat %s\n' "$WORK/fc/corpus.tsv" > "$WORK/fc/oracle.sh"

# The fake students. Written, not run -- the tool names are printf ARGUMENTS so
# the require scanner does not read them as selftest.sh's own calls.
printf '#!/bin/sh\nfor f in "$@"; do %s "$f"; done\n' cat > "$WORK/fc/good.sh"
printf '#!/bin/sh\nexit 0\n' > "$WORK/fc/silent.sh"
# Stops at the first NUL, which is what a buffer treated as a C string does.
# This arm is the one that caught the runner decoding through a shell variable:
# a variable cannot hold a NUL, so the file reached the program without one and
# this program PASSED 60 of 60.
printf '#!/bin/sh\nfor f in "$@"; do %s -d "\\000" < "$f"; done\n' tr \
	> "$WORK/fc/eatsnul.sh"
# Reads stdin before its files: without `< /dev/null` on every run it swallows
# the rest of the corpus and the layer reports OK having checked one case.
printf '#!/bin/sh\n%s > /dev/null\nfor f in "$@"; do %s "$f"; done\n' cat cat \
	> "$WORK/fc/eatsstdin.sh"
chmod +x "$WORK/fc"/*.sh

fc_run() { "$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/$1.sh" \
	--oracle "$WORK/fc/oracle.sh" --fn fixture --show 0; }

want_green "file_check: a program matching the reference passes" -- fc_run good
want_red   "file_check: a program that prints nothing is caught" -- fc_run silent
want_red   "file_check: dropping NUL bytes is caught"            -- fc_run eatsnul
want_green "file_check: a program that reads stdin is not starved" -- fc_run eatsstdin

# The floors, each exit 2: a corpus that cannot fail anything is a broken
# harness rather than a wrong deliverable.
fc_floor() {  # fc_floor NAME CORPUS [extra args...]
	_n="$1"; shift
	printf '#!/bin/sh\ncat %s\n' "$1" > "$WORK/fc/oracle_f.sh"
	chmod +x "$WORK/fc/oracle_f.sh"
	shift
	"$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/good.sh" \
		--oracle "$WORK/fc/oracle_f.sh" --fn fixture "$@" > /dev/null 2>&1
	_rc=$?
	if [ "$_rc" -eq 2 ]; then
		printf '  %-52s %s\n' "$_n" "ok (red, as required)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_n" "FAIL < (exit $_rc; it must refuse with 2)"
		FAIL=$((FAIL + 1))
	fi
}

: > "$WORK/fc/empty.tsv"
fc_floor "file_check: an EMPTY corpus is a harness error, not 0/0" "$WORK/fc/empty.tsv"

# No NUL and nothing large: a program that stops at the first NUL, and one that
# reads its buffer once, both pass.
{
	_i=0
	while [ "$_i" -lt 25 ]; do
		printf 'file\t0\t1\tline%s\\n\tline%s\\n\n' "$_i" "$_i"
		_i=$((_i + 1))
	done
} > "$WORK/fc/tame.tsv"
fc_floor "file_check: a corpus of tame text files is refused" "$WORK/fc/tame.tsv"

# --expect-transform on a corpus whose output IS its input: that corpus is
# passed by `cat`, which is not what ft_tail or ft_hexdump do.
fc_floor "file_check: --expect-transform refuses an identity corpus" \
	"$WORK/fc/corpus.tsv" --expect-transform

# --expect-substring names a thing the corpus must be able to produce -- for
# hexdump that is the `*` squeeze line, which needs sixteen identical bytes
# twice over and which no committed fixture reaches.
fc_floor "file_check: --expect-substring refuses a corpus without it" \
	"$WORK/fc/corpus.tsv" --expect-substring "SQUEEZE-MARKER"

# ------------------------------------------------------------- the nm pin
# The three runners that read symbols take a SUPPLIED nm and have no PATH
# fallback, and that is the whole value of the pin -- so it needs an arm, because
# a fallback is exactly the kind of thing someone adds back "to make it work on
# my machine" and nothing else would notice.
#
# The campus audit is why it is not hypothetical: nm there resolved to a
# student's own Homebrew binutils 2.46.1, shadowing the system 2.38 the
# Moulinette uses, so these layers were reading a different tool than the grader.
#
# Exit 2, not 1: a missing nm means nothing was checked, which is a broken
# harness rather than a wrong deliverable -- hence the explicit status test
# instead of want_red.
# Each runner gets a COMPLETE argument list with only --nm missing, and the
# assertion is on the SENTENCE, not merely on the status.
#
# The earlier version invoked each one with no arguments at all and accepted any
# exit 2. Every runner here exits 2 for a dozen reasons -- a missing --expect, a
# missing --src, an unknown option -- so the arm passed on whichever check
# happened to fire first, and a re-added PATH fallback for nm would have left it
# green while the runner quietly read the box's binutils. That is the same
# "green having checked nothing" shape these arms exist to catch, one level up.
want_broken "symbols_test: no PATH fallback for nm" \
	"--nm is required (no PATH fallback by design)" -- \
	"$SH" "$TOOLS/symbols_test.sh" --expect ft_x --src "$WORK/static.c"
want_broken "forbidden_symbols: no PATH fallback for nm" \
	"--nm is required (no PATH fallback by design)" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --allowed write --src "$WORK/static.c"
want_broken "make_test: no PATH fallback for nm" \
	"--nm is required (no PATH fallback by design)" -- \
	"$SH" "$TOOLS/make_test.sh" --anchor "$WORK/static.c" --artifact libft.a

printf '\n  %d checks passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || {
	printf '\n  A runner stopped detecting the thing it exists to detect. That is\n'
	printf '  worse than a red exercise: every test using it now reports OK\n'
	printf '  without checking. Fix the runner before trusting any suite result.\n'
	exit 1
}
exit 0
