# ----------------------------------------------------------------- shell_test
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The only functional runner for BOTH shell modules: every diff/check test in
# c-piscine-shell-00 and -01 goes through it, so a break here greens two entire
# modules at once. The student's answer is the generator, which this re-runs in a
# throwaway dir, so there are three distinct ways to be wrong and each gets a
# case: produce the wrong content, produce no deliverable at all, or not be valid
# sh in the first place (--mode norm, the layer every stub exercise still runs).
#
# THE RUNNER'S COMMAND LINE: st writes it once, and st_diff, st_run and
# st_files add each mode's fixed tail. Each runs it as it stands, adding no
# environment: an arm that needs some writes it out (`env NAME=VALUE "$SH"
# "$TOOLS/shell_test.sh" ...`) or runs the helper in a subshell that exports
# it. So does an arm whose fixture PATH must reach the runner, which keeps
# the whole `"$SH" "$TOOLS/shell_test.sh"` line (tools/conventions.sh, the
# PATH-fixture rule). An arm that holds a refusal in place passes the
# options it refuses on st, never through a tail that would hide them.
# Plain code, so every shard has them; shell_check's second file uses st.
#
# st MODE GEN [OPTION...] -- shell_test.sh --mode MODE over $WORK/GEN.
st() {
	_st_mode=$1  # the mode, as --mode takes it
	_st_gen=$2  # the generator, under $WORK
	shift 2
	"$SH" "$TOOLS/shell_test.sh" --generator "$WORK/$_st_gen" --mode "$_st_mode" "$@"
}
# st_diff GEN [OPTION...] -- diff mode: out.txt against $WORK/gen_exp.txt.
st_diff() {
	_std_gen=$1  # the generator, under $WORK
	shift
	st diff "$_std_gen" --deliverable out.txt --expected "$WORK/gen_exp.txt" "$@"
}
# st_run GEN [OPTION...] -- diff mode with --run: d.sh run through the
# tree's check library, its output against $WORK/gen_exp.txt.
st_run() {
	_str_gen=$1  # the generator, under $WORK
	shift
	st diff "$_str_gen" --deliverable d.sh --expected "$WORK/gen_exp.txt" --run \
		--check-lib "$TOOLS/shell_check.sh" "$@"
}
# st_files GEN [OPTION...] -- files mode: the tree's files test, the label
# selftest first, --strict last.
st_files() {
	_stf_gen=$1  # the generator, under $WORK
	shift
	st files "$_stf_gen" --files-test "$TOOLS/files_test.sh" --label selftest "$@" --strict
}
printf '#!/bin/sh\nprintf "hello\\n" > out.txt\n' > "$WORK/gen_ok.sh"
printf '#!/bin/sh\nprintf "wrong\\n" > out.txt\n' > "$WORK/gen_bad.sh"
printf '#!/bin/sh\n:\n' > "$WORK/gen_none.sh"
printf 'if [ ; then\n' > "$WORK/gen_syntax.sh"
printf 'hello\n' > "$WORK/gen_exp.txt"
want_green "shell_test: the expected deliverable passes" -- \
	once st_diff gen_ok.sh
want_red   "shell_test: wrong deliverable content fails" -- \
	st_diff gen_bad.sh
want_red   "shell_test: producing no deliverable fails" -- \
	st_diff gen_none.sh
want_red   "shell_test: --mode norm rejects a syntax error" -- \
	st norm gen_syntax.sh
# Run by hand, by a path relative to where it was started, and outside a
# test (no TEST_SRCDIR): tools/exit_status beside it was looked for from the
# scratch folder the runner had moved into, and never found.
st_relative() {  # st_relative ARG... -- shell_test.sh by a relative path, TEST_SRCDIR unset
	(cd "$TOOLS/.." && exec env -u TEST_SRCDIR "$SH" tools/shell_test.sh "$@")
}
want_green "shell_test: run by a relative path, it finds tools/exit_status" -- \
	st_relative --generator "$WORK/gen_ok.sh" --mode diff \
		--deliverable out.txt --expected "$WORK/gen_exp.txt"
# A byte a terminal hides, shown through the one renderer (rl_udiff, V51): a
# carriage return at a line's end read exactly as the expected line did, and
# a NUL turned the whole report into "Binary files X and Y differ", naming
# two scratch files.
printf '#!/bin/sh\nprintf "hello\\r\\n" > out.txt\n' > "$WORK/gen_cr.sh"
printf '#!/bin/sh\nprintf "hello\\000\\n" > out.txt\n' > "$WORK/gen_nul.sh"
want_out   "shell_test: a carriage return in the turn-in is shown" '+hello\x0d$' -- \
	st_diff gen_cr.sh
want_out   "shell_test: ...and a NUL, not 'Binary files'" '+hello\x00$' -- \
	st_diff gen_nul.sh
want_green "shell_test: ...in a log that holds no raw NUL" -- \
	no_raw_nul st_diff gen_nul.sh

# The LINT, which used to run whatever shellcheck the box happened to have and,
# on a box with none, printed a note to stderr and exited 0. Both halves of
# that are wrong -- an unpinned linter makes the verdict depend on the machine
# (its version decides which warnings exist), and a silent pass is the shape
# this whole file exists to catch. It is pinned now, and these arms hold each
# part of the replacement in place.
#
# It is its own mode, lint, at robust: it used to be the second half of norm,
# at basic, where a warning of this repo's own choosing sat in every
# beginner's path (docs/reference.md, "Shell turn-ins"). norm asks `sh -n`
# alone.
#
# SC2164 rather than SC2086: the runner lints at -S warning, so an unquoted
# expansion is only an info and would leave the arm asserting nothing.
printf '#!/bin/sh\ncd /tmp\nls\n' > "$WORK/gen_lint.sh"
printf '#!/bin/sh\ncd /tmp || exit 1\nls\n' > "$WORK/gen_lintok.sh"

want_green "shell_test: --mode norm parses, and lints nothing" -- \
	st norm gen_lint.sh
want_red   "shell_test: the pinned shellcheck rejects a warning" -- \
	st lint gen_lint.sh --shellcheck "$SHELLCHECK"
want_out   "shell_test: ...naming the generator and the tool" \
	'gen_lint.sh -- shellcheck' -- \
	st lint gen_lint.sh --shellcheck "$SHELLCHECK"
want_green "shell_test: a clean generator still passes the lint" -- \
	st lint gen_lintok.sh --shellcheck "$SHELLCHECK"

# And with no pinned binary the layer must SAY it checked less, not imply it
# checked. NO_SKIP=1 is the sweep that turns every such gap red; a skip it
# cannot force is invisible to the only mechanism built to find it.
want_red   "shell_test: NO_SKIP refuses a lint run with no linter" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/shell_test.sh" \
		--generator "$WORK/gen_lint.sh" --mode lint

# The script the generator WRITES. The norm layer used to read the generator
# alone, so nothing linted the file 42 grades (finding 024). With
# --deliverable, lint and posix run the generator and lint the script it
# wrote. Each generator below is a toy that writes a one-line d.sh.
cat > "$WORK/gen_wq.sh" <<'GEN_WQ'
#!/bin/sh
printf '%s\n' 'echo "unterminated' > d.sh
GEN_WQ
cat > "$WORK/gen_weq.sh" <<'GEN_WEQ'
#!/bin/sh
printf '%s\n' 'if [ "$1" == a ]; then echo a; fi' > d.sh
GEN_WEQ
cat > "$WORK/gen_wcd.sh" <<'GEN_WCD'
#!/bin/sh
printf '%s\n' 'cd /tmp' 'ls' > d.sh
GEN_WCD
cat > "$WORK/gen_wok.sh" <<'GEN_WOK'
#!/bin/sh
printf '%s\n' 'echo "a b"' > d.sh
GEN_WOK
printf '#!/bin/sh\nexit 3\n' > "$WORK/gen_fails.sh"
# Without NO_SKIP, whatever the sweep this runs in says: the arms below that
# pin a SKIP would otherwise go red under `bazel test --test_env=NO_SKIP=1`,
# for the reason the NO_SKIP arm among them pins.
stl() {  # stl MODE GENERATOR [OPTION...] -- lint mode MODE on what GENERATOR writes
	_stl_mode=$1  # lint or posix
	_stl_gen=$2  # the generator, under $WORK
	shift 2
	env -u NO_SKIP "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/$_stl_gen" \
		--mode "$_stl_mode" --shellcheck "$SHELLCHECK" --deliverable d.sh --output-test ex00_output "$@"
}
want_red   "shell_test: --mode lint fails a warning in the turn-in" -- \
	once stl lint gen_wcd.sh
want_out   "shell_test: ...naming the script, not the generator" \
	'lint: d.sh, as the generator wrote it' -- once stl lint gen_wcd.sh
want_out   "shell_test: ...and whose rule it is" \
	'rigour this repo adds' -- once stl lint gen_wcd.sh
want_out   "shell_test: ...and which test reads its SC3xxx" \
	'SC3xxx, are ex00_posix'"'"'s' -- once stl lint gen_wcd.sh
want_green "shell_test: --mode lint passes a clean turn-in" -- stl lint gen_wok.sh
# What another test already reports, lint and posix only say they skipped,
# naming that test: a turn-in /bin/sh cannot parse (exNN_output, at basic),
# none written, a generator that fails (both exNN_output's), and a
# generator /bin/sh cannot parse (exNN_norm's).
want_green "shell_test: --mode lint, a turn-in that does not parse is a SKIP" -- \
	once stl lint gen_wq.sh
want_out   "shell_test: ...naming the test that reports it" \
	'/bin/sh cannot parse it; ex00_output reports that' -- once stl lint gen_wq.sh
want_green "shell_test: --mode posix does not judge a parse error either" -- \
	stl posix gen_wq.sh
want_green "shell_test: --mode lint, a skeleton that writes nothing is a SKIP" -- \
	once stl lint gen_none.sh
want_out   "shell_test: ...naming the test that reports it" \
	'ex00_output reports that' -- once stl lint gen_none.sh
want_red   "shell_test: ...and NO_SKIP makes it a failure" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_none.sh" \
		--mode lint --shellcheck "$SHELLCHECK" --deliverable d.sh
want_green "shell_test: --mode lint, a generator that fails is output's to report" -- \
	stl lint gen_fails.sh
want_out   "shell_test: --mode lint, a generator that does not parse is norm's" \
	'ex00_norm reports that' -- stl lint gen_syntax.sh
want_red   "shell_test: ...and a skip never hides the generator's own lint" -- \
	env -u NO_SKIP "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_lint.sh" \
		--mode lint --shellcheck "$SHELLCHECK" --deliverable d.sh
# A POSIX-undefined construct in a script /bin/sh runs is strict's (posix),
# not robust's: lint leaves it there, unless the subject runs the script
# with bash, where it is this repo's rigour and lint's to report.
want_red   "shell_test: --mode posix fails a POSIX-undefined construct" -- \
	once stl posix gen_weq.sh
want_out   "shell_test: ...with shellcheck's code for it" 'SC3014' -- \
	once stl posix gen_weq.sh
want_green "shell_test: ...which lint leaves to posix (--script sh)" -- \
	stl lint gen_weq.sh --script sh
want_red   "shell_test: ...and reports itself for a bash script" -- \
	stl lint gen_weq.sh --script bash
want_green "shell_test: --mode posix leaves other warnings to lint" -- \
	stl posix gen_wcd.sh
# --script ./name: the subject runs it as ./name, so its own #! line picks
# the shell. One that names bash is run by bash, and its POSIX-undefined
# constructs are lint's, as for --script bash; sh, or no #! line at all, is
# the general rule's /bin/sh, and they are posix's. Where they are reported
# is all the #! line decides: the tests run every script with /bin/sh, and
# posix says so, so that its "bash runs it" is not read as how it is graded.
cat > "$WORK/gen_wbash.sh" <<'GEN_WBASH'
#!/bin/sh
printf '%s\n' '#!/usr/bin/env bash' 'if [ "$1" == a ]; then echo a; fi' > d.sh
GEN_WBASH
cat > "$WORK/gen_wsheq.sh" <<'GEN_WSHEQ'
#!/bin/sh
printf '%s\n' '#!/bin/sh' 'if [ "$1" == a ]; then echo a; fi' > d.sh
GEN_WSHEQ
want_green "shell_test: --script ./name, a bash #! line leaves posix nothing" -- \
	once stl posix gen_wbash.sh --script ./name
want_out   "shell_test: ...and says which test reports it" \
	'are ex00_lint'"'"'s to report' -- once stl posix gen_wbash.sh --script ./name
want_out   "shell_test: ...and that the output test still runs it with /bin/sh" \
	'so ex00_output grades what /bin/sh does with it' -- \
	once stl posix gen_wbash.sh --script ./name
want_red   "shell_test: ...which lint does" -- stl lint gen_wbash.sh --script ./name
want_red   "shell_test: --script ./name, a sh #! line is posix's" -- \
	stl posix gen_wsheq.sh --script ./name
want_green "shell_test: ...and not lint's" -- stl lint gen_wsheq.sh --script ./name
want_red   "shell_test: --script ./name, no #! line is posix's too" -- \
	stl posix gen_weq.sh --script ./name
# A script saved with CRLF line ends: its #! line reads '#!/bin/sh' and a
# carriage return, which named the shell "sh<CR>", not sh, and posix passed
# it, naming that shell, having linted nothing.
cat > "$WORK/gen_wcrlf.sh" <<'GEN_WCRLF'
#!/bin/sh
printf '#!/bin/sh\r\necho "${1//a/b}"\r\n' > d.sh
GEN_WCRLF
want_red   "shell_test: --script ./name, a sh #! line ending in a CR is posix's" -- \
	stl posix gen_wcrlf.sh --script ./name
want_broken "shell_test: --script takes how the subject runs it" \
	'--script is sh, ./name or bash' -- stl lint gen_wok.sh --script zsh
want_broken "shell_test: --mode posix without a turn-in is refused" \
	'needs --deliverable' -- \
	st posix gen_wok.sh --shellcheck "$SHELLCHECK"
want_broken "shell_test: --mode posix with --script bash is wiring, refused" \
	'has no posix target' -- stl posix gen_weq.sh --script bash

# The bounds on unverified code. A generator that loops forever or prints without
# end used to be stopped only by Bazel's own timeout, which reports nothing a
# student can act on.
printf '#!/bin/sh\nwhile :; do :; done\n' > "$WORK/gen_hang.sh"
printf '#!/bin/sh\nwhile :; do printf "spam\\n"; done > out.txt\n' > "$WORK/gen_flood.sh"
want_red   "shell_test: a generator that never finishes is stopped" -- \
	env SHELL_TIMEOUT=2 "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_hang.sh" \
		--mode diff --deliverable out.txt --expected "$WORK/gen_exp.txt"
want_red   "shell_test: a generator that floods output is stopped" -- \
	once env SHELL_TIMEOUT=10 "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_flood.sh" \
		--mode diff --deliverable out.txt --expected "$WORK/gen_exp.txt"
# ... and stopped by the `ulimit -f` budget rather than by the timeout: both
# are exit 1, so the arm above stays green with the budget gone (as
# diff_output's does), and only the sentence tells them apart. Each run of
# unverified code has the budget: the generator, its --stable second run
# (gen_flood2 writes out.txt once, then floods it on the run after) and the
# deliverable under --run.
want_out   "shell_test: ...by the output budget, not by the timeout" \
	'the generator kept writing past the output budget' -- \
	once env SHELL_TIMEOUT=10 "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_flood.sh" \
		--mode diff --deliverable out.txt --expected "$WORK/gen_exp.txt"
SELFTEST_FLOOD_ONCE="$WORK/flood-once"
export SELFTEST_FLOOD_ONCE
cat > "$WORK/gen_flood2.sh" <<'GEN_FLOOD2'
#!/bin/sh
if [ -e "$SELFTEST_FLOOD_ONCE" ]; then
	while :; do printf 'spam\n'; done > out.txt
fi
: > "$SELFTEST_FLOOD_ONCE"
printf 'hello\n' > out.txt
GEN_FLOOD2
mkdir -p "$WORK/flood"
ck_toy "$WORK/flood/check.sh" 'ck_require "out.txt exists" test -f out.txt' \
	'ck_stable "out.txt is the same on every run" out.txt'
st_flood2() {  # --stable over gen_flood2.sh, its marker removed first
	rm -f "$SELFTEST_FLOOD_ONCE"
	env SHELL_TIMEOUT=10 "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_flood2.sh" \
		--mode check --check "$WORK/flood/check.sh" --check-lib "$TOOLS/shell_check.sh" --stable
}
want_out   "shell_test: ...on the generator's --stable second run too" \
	"the generator's second run kept writing past the output budget" -- st_flood2
cat > "$WORK/gen_runflood.sh" <<'GEN_RUNFLOOD'
#!/bin/sh
cat > d.sh <<'INNER'
while :; do printf 'spam\n'; done
INNER
GEN_RUNFLOOD
st_runflood() {  # diff --run over a deliverable that floods its output
	env SHELL_TIMEOUT=10 "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_runflood.sh" \
		--mode diff --deliverable d.sh --expected "$WORK/gen_exp.txt" --run \
		--check-lib "$TOOLS/shell_check.sh"
}
want_red   "shell_test: a deliverable that floods output under --run is stopped" -- \
	once st_runflood
want_out   "shell_test: ...by the output budget, not by the timeout" \
	'the deliverable kept writing past the output budget' -- once st_runflood

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
	once st_run gen_runcrash.sh
want_out   "shell_test: ...naming the signal" 'the deliverable was killed by SIGSEGV' -- \
	once st_run gen_runcrash.sh

# How the run ended is read from tools/exit_status, through ck_run's $CK_HOW,
# never from the status: `exit 255` is a return, not a death by "signal 127".
# Diff mode once read every status above 128 as a crash; a --run that drops
# ck_run's line would judge the generator's ending, the last one classified.
cat > "$WORK/gen_run255.sh" <<'GEN_RUN255'
#!/bin/sh
cat > d.sh <<'INNER'
printf 'hello\n'
exit 255
INNER
GEN_RUN255
want_green "shell_test: --run right output, then exit 255, passes" -- \
	once st_run gen_run255.sh
want_out   "shell_test: ...shown as the status it returned" 'exit status 255' -- \
	once st_run gen_run255.sh

# --run keeps what the deliverable wrote to stderr, and its status, and shows
# both -- without failing on them: no shell subject names an exit status, so
# right output with a plain non-zero status is green (the run contract), and
# what used to explain a red went to /dev/null.
cat > "$WORK/gen_runnoisy.sh" <<'GEN_RUNNOISY'
#!/bin/sh
cat > d.sh <<'INNER'
#!/bin/sh
printf 'hello\n'
echo oops-on-stderr >&2
exit 3
INNER
chmod +x d.sh
GEN_RUNNOISY
want_green "shell_test: --run right output, status 3 and stderr pass" -- \
	once st_run gen_runnoisy.sh
want_out   "shell_test: ...and the run's stderr is shown" 'oops-on-stderr' -- \
	once st_run gen_runnoisy.sh
want_out   "shell_test: ...with its exit status" 'exit status 3' -- \
	once st_run gen_runnoisy.sh

# --run runs the deliverable the way every check runs one: through the
# library's ck_run, as `/bin/sh name`, after asking /bin/sh to parse it. It
# ran ./name through its #! line, with no parse check and an excerpt of its
# own: a script whose #! names a shell this box lacks, and without its
# execute bit, failed here and passes as the subjects run it; one that
# prints the right line and then dies on an unclosed `if` passed.
cat > "$WORK/gen_runbang.sh" <<'GEN_RUNBANG'
#!/bin/sh
cat > d.sh <<'INNER'
#!/no/such/shell
printf 'hello\n'
INNER
GEN_RUNBANG
cat > "$WORK/gen_runparse.sh" <<'GEN_RUNPARSE'
#!/bin/sh
cat > d.sh <<'INNER'
#!/bin/sh
printf 'hello\n'
if true; then
	:
INNER
chmod +x d.sh
GEN_RUNPARSE
want_green "shell_test: --run runs it with /bin/sh, not its #! line" -- \
	st_run gen_runbang.sh
want_red   "shell_test: --run fails a script /bin/sh cannot parse" -- \
	once st_run gen_runparse.sh
want_out   "shell_test: ...naming the parse check" '[FAIL] d.sh parses under /bin/sh (sh -n)' -- \
	once st_run gen_runparse.sh
want_broken "shell_test: --run without the check library is refused" \
	'--run needs --check-lib' -- \
	st diff gen_runnoisy.sh --deliverable d.sh --expected "$WORK/gen_exp.txt" --run

# --mode files: what the generator LEFT BEHIND. Both shell subjects forbid extra
# files on p.3 and neither module checked it -- one `echo leftover > oops.txt`
# appended to a generator left every layer green, and //tools:submit pushes the
# scratch dir's contents with `git add -A --force`.
#
# The fixture arm is the one that keeps this from becoming a driver bug charged
# to the student: shell-00 ex07 has 42's resources.tar.gz staged INTO the
# scratch dir by this runner, and counting it as something the student left
# behind would fail a correct answer.
printf '#!/bin/sh\nprintf "hello\\n" > out.txt\nprintf "x\\n" > oops.txt\n' > "$WORK/gen_extra.sh"
printf '#!/bin/sh\nprintf "hello\\n" > out.txt\nprintf "x\\n" > .hidden\n' > "$WORK/gen_dot.sh"
printf 'fixture\n' > "$WORK/gen_fixture.dat"
want_green "shell_test: --mode files passes on exactly the deliverable" -- \
	st_files gen_ok.sh --optional out.txt
want_red   "shell_test: a stray file left behind is caught" -- \
	st_files gen_extra.sh --optional out.txt
want_red   "shell_test: ...including a dotfile" -- \
	st_files gen_dot.sh --optional out.txt
want_green "shell_test: a fixture WE staged is not the student's leftover" -- \
	st_files gen_ok.sh --optional out.txt --fixture "$WORK/gen_fixture.dat"
# --turnin, what shell_exercise passes: the turn-in is named in the report
# whether the generator made it or not, and a generator that made nothing
# (every skeleton on the template) is the output layer's red, not this one's
# (finding 017). What every mode but norm and twin reads is the scratch dir
# the generator ran in, never deliverable/, and the log says so first
# (finding 031).
want_green "shell_test: --turnin, a skeleton that made nothing passes files" -- \
	once st_files gen_none.sh --turnin out.txt
want_out   "shell_test: ...naming the turn-in as not produced" 'out.txt' -- \
	once st_files gen_none.sh --turnin out.txt
want_broken_none "shell_test: ...and not as exactly the files asked for" \
	'exactly the files the subject asks for' -- \
	once st_files gen_none.sh --turnin out.txt
want_out   "shell_test: --turnin, one that made it: present" 'out.txt                      present' -- \
	once st_files gen_ok.sh --turnin out.txt
want_red   "shell_test: --turnin, a stray file beside it still fails" -- \
	st_files gen_extra.sh --turnin out.txt
want_out   "shell_test: files mode says it read the generator's output" \
	'checking a fresh copy built from generators/gen_ok.sh' -- \
	once st_files gen_ok.sh --turnin out.txt
want_out   "shell_test: ...and so does diff mode, not deliverable/" \
	'(not deliverable/gen_ok)' -- \
	once st_diff gen_ok.sh
want_broken_none "shell_test: norm mode runs nothing, and says nothing of it" \
	'checking a fresh copy' -- \
	st norm gen_lintok.sh --shellcheck "$SHELLCHECK"

# --mode twin: a twin's own tests/exNN/ holds its README and nothing else,
# since its tests are read from the exercise it repeats (shell_exercise's
# twin_of). It was a fail() in the macro, which took every target of the
# package down for one file -- vim's swap file beside the README included.
# Now it is one exercise's red; which files count is twin_strays', checked
# by //tools/tests:starlark_unit, and these arms check what the target says.
st_twin() {
	"$SH" "$TOOLS/shell_test.sh" --mode twin --twin-of //m/shell-00:ex08 \
		--twin-tests m/shell-00/tests/ex08/ --label m/reloaded/tests/ex02/ "$@"
}
want_green "shell_test: --mode twin, a README alone passes" -- st_twin
want_red   "shell_test: --mode twin, a stray test file fails" -- \
	once st_twin --stray check.sh
want_out   "shell_test: ...naming it, and where the tests are read from" \
	'      m/shell-00/tests/ex08/' -- once st_twin --stray check.sh
want_out   "shell_test: ...every one of them" '      clues.tsv' -- \
	st_twin --stray check.sh --stray clues.tsv
want_red   "shell_test: --mode twin, a missing README fails" -- \
	st_twin --no-readme
want_out   "shell_test: ...and says how to get it back" \
	'git checkout -- m/reloaded/tests/ex02/README.md' -- st_twin --no-readme
want_broken "shell_test: --mode twin without its twin is refused" \
	'needs --twin-of' -- "$SH" "$TOOLS/shell_test.sh" --mode twin

# --stable: a second run of the generator, in another empty directory, which
# the check compares with shell_check.sh's ck_stable. A generator runs again
# on every generate and every submit, so where the subject fixes the turn-in
# byte for byte, one that differs from run to run is never the file that was
# tested (no exercise has stable = True today: the owner reversed it for
# Shell 00 ex03's key on 2026-10-04). The random generator is a toy: sixteen
# bytes of /dev/urandom. gen_once writes
# out.txt on its first run only: a marker outside both scratch directories
# says it has run, and the one arm that uses it removes it first.
SELFTEST_ONCE="$WORK/stable-once"
export SELFTEST_ONCE
cat > "$WORK/gen_once.sh" <<'GEN_ONCE'
#!/bin/sh
[ -e "$SELFTEST_ONCE" ] && exit 0
: > "$SELFTEST_ONCE"
printf 'hello\n' > out.txt
GEN_ONCE
cat > "$WORK/gen_random.sh" <<'GEN_RANDOM'
#!/bin/sh
od -An -N16 -tx1 /dev/urandom > out.txt
GEN_RANDOM
mkdir -p "$WORK/stable"
ck_toy "$WORK/stable/check.sh" 'ck_require "out.txt exists" test -f out.txt' \
	'ck_stable "out.txt is the same on every run" out.txt'
ck_toy "$WORK/stable/nostable.sh" 'ck_require "out.txt exists" test -f out.txt' \
	'ck "out.txt has something in it" test -s out.txt'
sts() {  # sts GENERATOR CHECK [OPTION...] -- st check, CHECK from $WORK/stable/, the tree's library
	_sts_gen=$1  # the generator, as st takes it
	_sts_check=$2  # the check script, under $WORK/stable/
	shift 2
	st check "$_sts_gen" --check "$WORK/stable/$_sts_check" --check-lib "$TOOLS/shell_check.sh" "$@"
}
want_green "shell_test: --stable, the same bytes twice pass" -- \
	sts gen_ok.sh check.sh --stable
want_red   "shell_test: --stable, other bytes on the second run fail" -- \
	once sts gen_random.sh check.sh --stable
want_out   "shell_test: ...saying the two runs differ" \
	'two runs of the generator wrote two different out.txt' -- \
	once sts gen_random.sh check.sh --stable
rm -f "$SELFTEST_ONCE"
want_out   "shell_test: --stable, a second run that writes nothing fails" \
	'the second run wrote no out.txt' -- sts gen_once.sh check.sh --stable
# What the first run keeps outside the turn-in directory is not the second's:
# that runs under an empty HOME and TMPDIR of its own, XDG_CONFIG_HOME unset.
# These toys make sixteen random bytes once, keep them there, and copy them
# into out.txt on every run -- one HOME gives the same bytes twice, and two
# HOMEs, or two machines, two different files. Under one HOME they passed.
cat > "$WORK/gen_home.sh" <<'GEN_HOME'
#!/bin/sh
[ -f "$HOME/stable-key" ] || od -An -N16 -tx1 /dev/urandom > "$HOME/stable-key"
cp "$HOME/stable-key" out.txt
GEN_HOME
cat > "$WORK/gen_tmpdir.sh" <<'GEN_TMPDIR'
#!/bin/sh
[ -f "${TMPDIR:-/tmp}/stable-key" ] || od -An -N16 -tx1 /dev/urandom > "${TMPDIR:-/tmp}/stable-key"
cp "${TMPDIR:-/tmp}/stable-key" out.txt
GEN_TMPDIR
cat > "$WORK/gen_xdg.sh" <<'GEN_XDG'
#!/bin/sh
d=${XDG_CONFIG_HOME:-$HOME/.config}
mkdir -p "$d"
[ -f "$d/stable-key" ] || od -An -N16 -tx1 /dev/urandom > "$d/stable-key"
cp "$d/stable-key" out.txt
GEN_XDG
mkdir -p "$WORK/stable-home" "$WORK/stable-tmp" "$WORK/stable-xdg"
sts_env() {  # sts_env GENERATOR -- sts GENERATOR check.sh --stable, in the arm's HOME
	(HOME=$WORK/stable-home TMPDIR=$WORK/stable-tmp XDG_CONFIG_HOME=$WORK/stable-xdg
	export HOME TMPDIR XDG_CONFIG_HOME
	sts "$1" check.sh --stable)
}
want_out   "shell_test: --stable, a key kept in HOME and copied fails" \
	'two runs of the generator wrote two different out.txt' -- sts_env gen_home.sh
want_out   "shell_test: ...and one kept in TMPDIR" \
	'two runs of the generator wrote two different out.txt' -- sts_env gen_tmpdir.sh
want_out   "shell_test: ...and one kept in XDG_CONFIG_HOME" \
	'two runs of the generator wrote two different out.txt' -- sts_env gen_xdg.sh
want_green "shell_test: ...while a generator that keeps nothing still passes" -- \
	sts_env gen_ok.sh
want_broken "shell_test: ck_stable with no second run is refused" \
	'stable = True' -- once sts gen_ok.sh check.sh
want_broken "shell_check: ...and its stable line too" \
	"give this exercise's shell_exercise call" -- once sts gen_ok.sh check.sh
want_broken "shell_test: a second run the check never compares is refused" \
	'never calls ck_stable' -- sts gen_ok.sh nostable.sh --stable
# ...on a checklist that would pass. One that failed first and ended early,
# before its ck_stable line, is red as it stands, its FAIL lines kept.
printf '%s\n' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "out.txt exists" test -f out.txt' \
	'ck "out.txt says bye" grep -q bye out.txt' 'ck_report' \
	'ck_stable "out.txt is the same on every run" out.txt' 'ck_report' \
	> "$WORK/stable/early.sh"
want_red   "shell_test: --stable, a check that fails before comparing is red, not broken" -- \
	once sts gen_ok.sh early.sh --stable
want_out   "shell_test: ...and keeps its FAIL line" '[FAIL] out.txt says bye' -- \
	once sts gen_ok.sh early.sh --stable
want_broken "shell_test: --stable is for check mode" 'is for check mode' -- \
	st diff gen_ok.sh --deliverable out.txt --expected "$WORK/gen_exp.txt" --stable

# --wording: the subject's own words for a sentence a check quotes, which is
# how one check serves twins whose subjects word it differently (Shell 01
# ex02's "files", Reloaded ex03's "file names"). They reach the check whole,
# spaces and quotes included, as $SHELL_CHECK_WORDING_<key> (ck_wording), and
# never the generator, which has run by then. A check that quotes words its
# call does not give is wiring, refused -- never a line that quotes nothing.
ck_toy "$WORK/stable/wording.sh" 'ck_require "out.txt exists" test -f out.txt' \
	'ck_wording files' 'printf "quoted: %s\n" "$CK_WORDING"' \
	'ck "the generator saw none of it" test -z "$(grep -v "^hello\$" out.txt)"'
cat > "$WORK/gen_words.sh" <<'GEN_WORDS'
#!/bin/sh
printf 'hello\n' > out.txt
printf '%s' "${SHELL_CHECK_WORDING_files:-}" >> out.txt
GEN_WORDS
want_out   "shell_test: --wording reaches the check whole" \
	'quoted: all file names that end with ".sh"' -- \
	sts gen_ok.sh wording.sh --wording 'files=all file names that end with ".sh"'
want_green "shell_test: ...and never the generator" -- \
	sts gen_words.sh wording.sh --wording 'files=all files ending with .sh'
# A word is data, never a pattern (runner_lib.sh, LISTS OF WORDS): split by
# hand with globbing on, a '*' in a --wording was matched against the files
# the generator left in the scratch folder, and the check quoted a file name.
cat > "$WORK/gen_wglob.sh" <<'GEN_WGLOB'
#!/bin/sh
printf 'hello\n' > out.txt
: > 'files=a.sh'
GEN_WGLOB
want_out   "shell_test: ...a '*' in it reaching the check unglobbed" \
	'quoted: *.sh' -- sts gen_wglob.sh wording.sh --wording 'files=*.sh'
want_broken "shell_test: a check quoting words its call does not give is refused" \
	'gives none: add' -- once sts gen_ok.sh wording.sh
# The call is named by what it tests (RL_UNIT_KIND), "exercise" where nothing
# names one.
want_broken "shell_check: ...an exercise's check names the exercise" \
	"this exercise's shell_exercise call gives none: add" -- once sts gen_ok.sh wording.sh
want_broken "shell_check: ...a part's check names the part" \
	"this part's shell_exercise call gives none: add" -- with_kind part sts gen_ok.sh wording.sh
want_broken "shell_test: --wording takes KEY=TEXT" '--wording is KEY=TEXT' -- \
	sts gen_ok.sh wording.sh --wording 'all files ending with .sh'
want_broken "shell_test: --wording is for check mode" 'a check script quotes it' -- \
	st diff gen_ok.sh --deliverable out.txt --expected "$WORK/gen_exp.txt" \
		--wording 'files=x'
# What a check is handed comes from its call alone (V80). SHELL_CHECK_RERUN,
# a SHELL_CHECK_WORDING_<key> and ORACLE were set only on the paths that give
# them, so one left in the environment of a hand run reached the check as if
# its call had: a second run nobody made, words nobody quoted, an oracle
# nobody named.
sts_leak_rerun() { (SHELL_CHECK_RERUN=$WORK/stable; export SHELL_CHECK_RERUN; sts gen_ok.sh nostable.sh); }
want_green "shell_test: a SHELL_CHECK_RERUN from the environment is no second run" -- \
	sts_leak_rerun
sts_leak_words() {
	(SHELL_CHECK_WORDING_files='words nobody quoted'; export SHELL_CHECK_WORDING_files
	sts gen_ok.sh wording.sh)
}
want_broken "shell_test: ...nor a SHELL_CHECK_WORDING_ the call does not give" \
	'gives none: add' -- sts_leak_words
ck_toy "$WORK/stable/noracle.sh" 'ck_require "out.txt exists" test -f out.txt' \
	'ck "no oracle reached the check" test -z "${ORACLE:-}"'
sts_leak_oracle() { (ORACLE=/bin/true; export ORACLE; sts gen_ok.sh noracle.sh); }
want_green "shell_test: ...nor an ORACLE the call does not name" -- sts_leak_oracle
# A check that asks //oracle, run by a call that does not give it, is
# wiring, refused with what to add to the call. A real one, Shell 01 ex04's:
# its ${ORACLE:?} line once ended the script before ck_report, and the guard
# that caught the end advised adding ck_report.
cp "$ROOT/c-piscine/c-piscine-shell-01/tests/ex04/check.sh" "$WORK/stable/oracle_less.sh"
want_broken "shell_test: a check that asks //oracle, its call giving none, is refused" \
	'does not give it: add oracle = True' -- once sts gen_ok.sh oracle_less.sh
want_broken_without "shell_test: ...and is not told to add a ck_report it has" \
	'Add ck_report' -- once sts gen_ok.sh oracle_less.sh
# ...nor a redirect the call does not declare, in diff --run, where nothing
# else unset it: an LD_PRELOAD reached the turn-in's run. Nor a check
# library, in a check-mode call that names none.
st_leak_redirect() {
	(CK_REDIRECT_LIB=/nonexistent/st_leak.so CK_REDIRECT_FROM=/etc/hostname
	CK_REDIRECT_TO=$WORK/gen_exp.txt
	export CK_REDIRECT_LIB CK_REDIRECT_FROM CK_REDIRECT_TO
	st_run gen_runnoisy.sh)
}
want_broken_none "shell_test: ...nor a CK_REDIRECT_ the call does not declare" \
	'/etc/hostname was' -- once st_leak_redirect
want_broken_none "shell_test: ...whose library the run never loads" \
	'LD_PRELOAD' -- once st_leak_redirect
printf '%s\n' '[ -z "${SHELL_CHECK_LIB:-}" ] && exit 0' \
	'echo "SHELL_CHECK_LIB reached the check: $SHELL_CHECK_LIB"' 'exit 1' > "$WORK/stable/nolib.sh"
st_leak_lib() {
	(SHELL_CHECK_LIB=$TOOLS/shell_check.sh; export SHELL_CHECK_LIB
	st check gen_ok.sh --check "$WORK/stable/nolib.sh")
}
want_green "shell_test: ...nor a SHELL_CHECK_LIB the call does not pass" -- st_leak_lib

# The exercise's hints follow a verdict on the turn-in (exit 1), never a
# broken harness (exit 2): nothing was judged, and shell 01 ex07 printed a
# hint about the student's own steps right under "the fixture no longer shows
# every step" (V278). Each mode, over a toy clues.tsv: a check that calls
# ck_broken, a files test and a diff that cannot run -- and a red check, which
# keeps its hints.
printf 'what does a toy script print first?\n' > "$WORK/st_clues.tsv"
ck_toy "$WORK/st_broken.sh" 'ck_require "out.txt exists" test -f out.txt' \
	'ck_broken "the toy fixture is gone"'
ck_toy "$WORK/st_red.sh" 'ck_require "out.txt exists" test -f out.txt' \
	'ck "out.txt says bye" grep -q bye out.txt'
printf '#!/bin/sh\necho "toy: this harness tool could not run" >&2\nexit 2\n' > "$WORK/st_tool2.sh"
chmod +x "$WORK/st_tool2.sh"
# st_hintless CMD... -- 0 when CMD exits 2 and prints no hint, else what it did.
st_hintless() {
	_sth_out=$("$@" 2>&1)
	_sth_rc=$?
	[ "$_sth_rc" -eq 2 ] || { echo "exit $_sth_rc, not 2"; return 1; }
	case "$_sth_out" in
		*"what does a toy script print first?"*) echo "printed the hint"; return 1 ;;
	esac
	return 0
}
st_ck() {  # st_ck CHECK -- check mode over gen_ok.sh, with the toy hints
	st check gen_ok.sh --check "$WORK/$1" --check-lib "$TOOLS/shell_check.sh" \
		--clues "$WORK/st_clues.tsv"
}
want_broken "shell_test: a check that calls ck_broken is a broken harness" \
	'BROKEN HARNESS: the toy fixture is gone' -- st_ck st_broken.sh
want_green "shell_test: ...with no hint under it" -- st_hintless st_ck st_broken.sh
want_out "shell_test: a red check keeps its hints" 'what does a toy script print first?' -- \
	st_ck st_red.sh
want_green "shell_test: a files test that cannot run prints no hint" -- \
	st_hintless st files gen_ok.sh --files-test "$WORK/st_tool2.sh" --label selftest \
		--optional out.txt --strict --clues "$WORK/st_clues.tsv"
want_green "shell_test: ...nor a diff that cannot run" -- \
	st_hintless st_diff gen_ok.sh --diff "$WORK/st_tool2.sh" --clues "$WORK/st_clues.tsv"


# diff --run's capture of the run (ACTUAL, with its .err and .ended) is this
# runner's scratch, gone on every way out: a refused call and a TERM during
# the run left it in TMPDIR. And a harness that could not run the turn-in --
# a check library that is not there, a ck_run with no tools/exit_status, a
# library with no ck_sh_parses -- is exit 2 with no hint, never "the
# deliverable was stopped from outside" under the exercise's hints.
cat > "$WORK/gen_runterm.sh" <<'GEN_RUNTERM'
#!/bin/sh
cat > d.sh <<'INNER'
echo started >&2
: > "$ST_MARK"
sleep 2
INNER
GEN_RUNTERM
st_tmp_left() {  # st_tmp_left DIR CMD... -- CMD under TMPDIR=DIR, made empty; 1, naming them, when it leaves files there
	_stt=$1
	shift
	rm -rf "$_stt"
	mkdir "$_stt"
	(TMPDIR=$_stt; export TMPDIR; "$@") > "$WORK/st_tmp.out" 2>&1
	_stt_rc=$?
	cat "$WORK/st_tmp.out"
	case "$_stt_rc" in
		2 | 143) ;;
		*) echo "exit $_stt_rc: it was meant to be refused (2) or stopped (143)"; return 2 ;;
	esac
	_stt_left=$(ls -A "$_stt")
	[ -n "$_stt_left" ] || return 0
	echo "left in TMPDIR: $_stt_left"
	return 1
}
st_term_run() {  # diff --run, sent TERM once its deliverable runs
	rm -f "$WORK/st_mark"
	# Written out, never st_run: the TERM is for the runner itself, and
	# $! of a function run in the background is the subshell around it.
	"$SH" "$TOOLS/shell_test.sh" --generator "$WORK/gen_runterm.sh" --mode diff \
		--deliverable d.sh --expected "$WORK/gen_exp.txt" --run \
		--check-lib "$TOOLS/shell_check.sh" --env "ST_MARK=$WORK/st_mark" &
	_stp=$!
	_stn=0
	while [ ! -e "$WORK/st_mark" ] && [ "$_stn" -lt 100 ]; do sleep 0.1; _stn=$((_stn + 1)); done
	kill -TERM "$_stp" 2> /dev/null
	wait "$_stp"
}
want_green "shell_test: --run refused for no --check-lib leaves no scratch file" -- \
	st_tmp_left "$WORK/st_tmpa" st diff gen_runnoisy.sh \
		--deliverable d.sh --expected "$WORK/gen_exp.txt" --run
want_green "shell_test: ...nor does a TERM during the run" -- \
	st_tmp_left "$WORK/st_tmpb" st_term_run
mkdir -p "$WORK/st_lonelib"
cp "$TOOLS/shell_check.sh" "$TOOLS/runner_lib.sh" "$WORK/st_lonelib/"
printf '%s\n' '# shellcheck shell=sh' 'ck_run() { printf "hello\n" > "$1"; CK_HOW="exit 0"; CK_RC=0; }' \
	> "$WORK/st_noparse.sh"
st_runlib() {  # st_runlib LIB -- diff --run over gen_runnoisy.sh through LIB, with the toy hints
	st diff gen_runnoisy.sh --deliverable d.sh --expected "$WORK/gen_exp.txt" --run \
		--check-lib "$1" --clues "$WORK/st_clues.tsv"
}
want_green "shell_test: --run through a check library that is not there: no hint" -- \
	st_hintless st_runlib "$WORK/st_nolib/shell_check.sh"
# The runner by its absolute path, which finds its own tools/exit_status
# beside it with TEST_SRCDIR unset; the library's copy has none beside it.
want_green "shell_test: ...nor through a ck_run with no tools/exit_status" -- \
	st_hintless env -u TEST_SRCDIR "$SH" "$(cd "$TOOLS" && pwd)/shell_test.sh" \
		--generator "$WORK/gen_runnoisy.sh" \
		--mode diff --deliverable d.sh --expected "$WORK/gen_exp.txt" --run \
		--check-lib "$WORK/st_lonelib/shell_check.sh" --clues "$WORK/st_clues.tsv"
want_broken "shell_test: ...nor through a library with no ck_sh_parses" \
	'did not reach ck_sh_parses' -- st_runlib "$WORK/st_noparse.sh"
