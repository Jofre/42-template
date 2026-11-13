# ----------------- conventions: check scripts, twins, run guards, the build graph
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Check scripts, and the rules that grew up beside their fixture trees, in
# this order:
#
#   check scripts: a turned-in script run through ck_run and ck_require,
#   what a run wrote shown through the library's renderer, the preload
#   library's stand-in for a fixed path, a turn-in's stdin;
#   twins: Reloaded's shell exercises that read their Piscine twin's tests,
#   copied with twin_of and without it;
#   what a call says (stable, readings) and its check relies on, a git
#   repository built under no configuration, and the harness's own tests
#   held to the unset;
#   the run's own guards: every FAIL it prints is one it counts (a report
#   from a subshell), a scan that cannot see a module or finds none, a
#   file only the runfiles tree lacks (cvrf), and a module whose REMOTES
#   row is commented out, still scanned (cv4);
#   perf's failing lines, said once; c_twin's cases (c_program's and
#   c_header's), sizes, budgets, units, seeds, corpus layers and
#   prototype.h guard; the cycles row of
#   docs/reference.md; --owns passed by hand (cvo);
#   the build graph no deliverable can break (cv5): what a macro is
#   handed, subject() first, turnin_file(), the runners' stand-in check
#   and _STANDIN_RUNNERS, the stderr pair, --quotes and _RUNNER_CHOICES;
#   who grades a project and a file that is a symbolic link (cvg); and an
#   //oracle arm that writes a project's fixtures (cvo, cvo2).
#
# Check scripts. Every one that ran a turned-in script did it itself, with
# stderr sent to /dev/null, and went on checking after the file was missing;
# ck_run and ck_require exist for that, and this is what keeps the next check
# script on them. One fixture per shape: a direct run (reported), a run
# through ck_run whose command spans two lines, next to a `sh -c` predicate
# (quiet), a first check that is not ck_require (reported), and a script run
# with sh that is never asked whether sh can parse it (reported).
# shellcheck disable=SC2154 # both set in conventions_bazel_run_first_red_hints.sh
mkdir -p "$_cv99/ex04" "$_cv99/ex05" "$_cv99/ex06" "$_cv98/ex06"
{
	printf '%s\n' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "x exists" test -f "$1"' \
		'ck_sh_parses "$1"' 'out=$(cd /tmp && sh "$1" 2>/dev/null)' \
		'ck "prints" test -n "$out"' 'ck_report'
} > "$_cv99/ex04/check.sh"
{
	printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' \
		'ck_require "x exists" test -f "$1"' \
		'ck_sh_parses "$1"' 'raw=$(mktemp)' 'ck_run "$raw" env A=1 \' \
		'	sh "$1"' "ck \"inline\" sh -c 'test -n \"\$1\"' _ x" 'ck_report'
} > "$_cv98/ex06/check.sh"
{
	printf '%s\n' '. "${SHELL_CHECK_LIB:?}"' 'ck "x exists" test -f "$1"' \
		'ck_report'
} > "$_cv99/ex05/check.sh"
{
	printf '%s\n' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "x exists" test -f "$1"' \
		'raw=$(mktemp)' 'ck_run "$raw" sh "$1"' 'ck_report'
} > "$_cv99/ex06/check.sh"
# The same rule when the ck_run goes on over a backslash-newline, which is
# where the sh sits whenever the environment it passes is long (Shell 01
# ex08): reported too.
mkdir -p "$_cv99/ex08"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' \
	'ck_require "x exists" test -f "$1"' 'raw=$(mktemp)' \
	'ck_run "$raw" env A=1 \' '	sh "$1"' 'ck_report' > "$_cv99/ex08/check.sh"
# And not when its ck_sh_parses is indented with a tab, inside an if: the
# rule read [ \t], which inside a bracket POSIX reads as a backslash and a t.
mkdir -p "$_cv98/ex13"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' \
	'ck_require "w exists" test -f "$1"' 'if [ -s "$1" ]; then' '	ck_sh_parses "$1"' 'fi' \
	'raw=$(mktemp)' 'ck_run "$raw" sh "$1"' 'ck "w prints a w" grep -q w "$raw"' 'ck_report' \
	> "$_cv98/ex13/check.sh"
# What a run wrote reaches the log through the library's renderer (ck_eq,
# ck_detail), never printed by the check itself: a variable taken from
# ck_run's file, the file, its .err, and a variable taken from such a
# variable (reported), the file read past ck_run's options (-C DIR, --crlf);
# the same piped on, redirected, handed to ck_eq or ck_detail, or counted,
# and a header naming the file checked (quiet).
mkdir -p "$_cv99/ex77" "$_cv98/ex14"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "w exists" test -f "$1"' \
	'ck_sh_parses "$1"' 'raw=$(mktemp)' 'ck_run -C /tmp --crlf "$raw" sh "$1"' 'out=$(cat "$raw")' \
	'first=$(printf "%s" "$out" | head -n 1)' "printf '  got: %s\\n' \"\$out\"" \
	'head -3 "$raw"' 'cat "$raw.err"' 'echo "$first"' 'ck_report' > "$_cv99/ex77/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "w exists" test -f "$1"' \
	'ck_sh_parses "$1"' "printf '  CHECK: %s\\n' \"\$1\"" 'raw=$(mktemp)' 'ck_run "$raw" sh "$1"' \
	'out=$(cat "$raw")' 'n=$(printf "%s\n" "$out" | wc -l)' 'echo "$n"' \
	'printf "%s\n" "$out" | grep -q w && echo found' 'cat "$raw" > /dev/null' \
	'ck_eq "prints w" "$out" "w"' 'ck_detail "$out"' 'ck_report' > "$_cv98/ex14/check.sh"
# And a check.sh that never loads the library, which every rule above keys
# on, is reported for that rather than let through by all of them.
mkdir -p "$_cv99/ex09"
printf '%s\n' '#!/bin/sh' 'out=$(sh "$1" 2>/dev/null)' 'test -n "$out"' \
	> "$_cv99/ex09/check.sh"
# Every arm below, to the next comment block, asks about one tree, so they
# read ONE run of it, made only where they run (cv5's reason, below), with
# its status (cv_saved).
! st_mine || conv > "$WORK/cv.checks" 2>&1
cv_checks() { cv_saved "$WORK/cv.checks"; }
want_out "conventions: a check script that runs a script itself is reported" \
	'c-piscine/c-piscine-c-99/tests/ex04/check.sh runs a script outside ck_run' -- \
	cv_checks
want_broken_none "conventions: ck_run over two lines and sh -c are not" \
	'c-piscine/c-piscine-c-98/tests/ex06/check.sh' -- \
	cv_checks
want_out "conventions: a first check that is not ck_require is reported" \
	'c-piscine/c-piscine-c-99/tests/ex05/check.sh registers a check before ck_require' -- \
	cv_checks
want_out "conventions: a script run with sh and never parsed is reported" \
	'c-piscine/c-piscine-c-99/tests/ex06/check.sh runs a script with sh and never asks' -- \
	cv_checks
want_out "conventions: ...when its ck_run spans two lines too" \
	'c-piscine/c-piscine-c-99/tests/ex08/check.sh runs a script with sh and never asks' -- \
	cv_checks
want_broken_none "conventions: ...nor when its ck_sh_parses is tab-indented" \
	'c-piscine/c-piscine-c-98/tests/ex13/check.sh runs a script with sh and never asks' -- \
	cv_checks
cv_raw() { cv_saved "$WORK/cv.checks" grep -A8 -F -- "$1 prints what a run wrote without the renderer"; }
want_out "conventions: a check printing a variable from ck_run's file is reported" \
	"line 9: printf '  got: %s" -- cv_raw c-piscine/c-piscine-c-99/tests/ex77/check.sh
want_out "conventions: ...and the file itself, cut with head" 'line 10: head -3 "$raw"' -- \
	cv_raw c-piscine/c-piscine-c-99/tests/ex77/check.sh
want_out "conventions: ...and its .err" 'line 11: cat "$raw.err"' -- \
	cv_raw c-piscine/c-piscine-c-99/tests/ex77/check.sh
want_out "conventions: ...and a variable taken from such a variable" 'line 12: echo "$first"' -- \
	cv_raw c-piscine/c-piscine-c-99/tests/ex77/check.sh
want_broken_none "conventions: ...not piped on, redirected, counted, ck_eq or ck_detail" \
	'c-98/tests/ex14/check.sh prints what a run wrote' -- cv_checks
want_out "conventions: a check.sh that never loads the library is reported" \
	'c-piscine/c-piscine-c-99/tests/ex09/check.sh does not load tools/shell_check.sh' -- \
	cv_checks
rm -f "$WORK/cv.checks"
# The ways past the first rule a reviewer found by mutation: the library's
# own `ck LABEL sh "$1"`, a `timeout` in front, a `sh -c` predicate whose
# script runs the turn-in, env with a flag, and the turn-in run by its own
# name. One fixture holds them all and one run is read by each arm; each
# line's report is also the proof that two offending lines are indented
# alike (the second used to sit at the helper's margin, not the report's).
# And a shell or a program that runs one reached by a path, and the shell
# behind `command -p` (lines 14-17).
# The timeout line is double-quoted, and not for style: conventions' require
# scanner reads a single-quoted $( as a call, and would report this file as
# taking timeout from PATH (see probe_optional above).
mkdir -p "$_cv99/ex10"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'D=$1' \
	'ck_require "x exists" test -f "$D"' 'ck_sh_parses "$D"' \
	'ck "runs" sh "$D"' \
	"out=\$(timeout 5 sh \"\$D\" 2>/dev/null)" \
	"ck \"prints\" sh -c 'sh \"\$1\" | grep -q .' _ \"\$D\"" \
	'env -i sh "$D" > /dev/null' \
	'./"$D"' \
	'"$D" > /dev/null' \
	"ck \"no x\" sh -c '[ -s \"\$1\" ] && ! grep -q x \"\$1\"' _ \"\$D\"" \
	'ck_eq "two more" "$(($1 + 2))" "$((${2} + 1))"' \
	'/usr/local/bin/bash "$D"' '/usr/bin/env sh "$D"' '/usr/bin/timeout 5 sh "$D"' \
	'command -p sh "$D"' \
	'ck_report' > "$_cv99/ex10/check.sh"
# ...and a run below a line whose note or quoted label shows a here-document
# (V170): the <<EOF and the <<x open none, so the run after each is read.
# And a here-document in a $( ) inside double quotes is one, a command's
# input, so the line it holds runs nothing (ex56, the review of V170).
mkdir -p "$_cv98/ex56" "$_cv98/ex57" "$_cv98/ex58"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'D=$1' \
	'ck_require "z exists" test -f "$D"' 'want="$(cat <<EOT' 'sh "$D"' 'EOT' ')"' \
	'ck_report' > "$_cv98/ex56/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'D=$1' \
	'ck_require "x exists" test -f "$D"' 'ck_sh_parses "$D"' \
	'ck "empty" true  # not fed with <<EOF' 'ck "runs" sh "$D"' 'ck_report' > "$_cv98/ex57/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'D=$1' \
	'ck_require "y exists" test -f "$D"' 'ck_sh_parses "$D"' \
	'ck "says <<x" true' 'ck "runs" sh "$D"' 'ck_report' > "$_cv98/ex58/check.sh"
! st_mine || conv > "$WORK/cv_runs.out" 2>&1
cv_runs() { cv_saved "$WORK/cv_runs.out"; }
cv_runs_of() { cv_saved "$WORK/cv_runs.out" grep -A2 -F -- "$1 runs a script outside ck_run"; }
want_out "conventions: ck LABEL sh \"\$D\" is a run outside ck_run" \
	'            line 6: ck "runs" sh "$D"' -- cv_runs
want_out "conventions: ...and so is timeout 5 sh, indented alike" \
	"            line 7: out=\$(timeout 5 sh \"\$D\" 2>/dev/null)" -- cv_runs
want_out "conventions: ...and a sh -c script that runs \$1" \
	"            line 8: ck \"prints\" sh -c 'sh \"\$1\" | grep -q .' _ \"\$D\"" -- cv_runs
want_out "conventions: ...and env with a flag in front of sh" \
	'            line 9: env -i sh "$D"' -- cv_runs
want_out "conventions: ...and the turn-in run by its own path" \
	'            line 10: ./"$D"' -- cv_runs
want_out "conventions: ...and by its own name" \
	'            line 11: "$D" > /dev/null' -- cv_runs
want_broken_none "conventions: a sh -c predicate that only reads it is not" \
	'line 12: ck "no x"' -- cv_runs
want_broken_none "conventions: ...nor \$1 in an arithmetic \$((...))" \
	'line 13: ck_eq' -- cv_runs
want_out "conventions: ...and a shell named by its path" \
	'            line 14: /usr/local/bin/bash "$D"' -- cv_runs
want_out "conventions: ...and env named by its path" \
	'            line 15: /usr/bin/env sh "$D"' -- cv_runs
want_out "conventions: ...and timeout named by its path" \
	'            line 16: /usr/bin/timeout 5 sh "$D"' -- cv_runs
want_out "conventions: ...and a shell behind command -p" \
	'            line 17: command -p sh "$D"' -- cv_runs
want_out "conventions: ...and a run below a note that shows a here-document (V170)" \
	'line 7: ck "runs" sh "$D"' -- cv_runs_of c-piscine/c-piscine-c-98/tests/ex57/check.sh
want_out "conventions: ...and below a quoted label that does" \
	'line 7: ck "runs" sh "$D"' -- cv_runs_of c-piscine/c-piscine-c-98/tests/ex58/check.sh
want_broken_none "conventions: ...never a line of a here-document a quoted \$( ) opens" \
	'c-piscine/c-piscine-c-98/tests/ex56/check.sh runs a script' -- cv_runs
# The preload library that hands a turn-in a fixture in place of a fixed
# path is ck_run's to load, into the turn-in's runs alone: a check that
# preloads it redirects its own reads too. A comment naming it is not a load.
mkdir -p "$_cv99/ex11"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' \
	'# LD_PRELOAD is ck_run'"'"'s, not ours' 'ck_require "x exists" test -f "$1"' \
	'export LD_PRELOAD="$CK_REDIRECT_LIB"' 'ck "reads" true' 'ck_report' \
	> "$_cv99/ex11/check.sh"
! st_mine || conv > "$WORK/cv_pre.out" 2>&1
cv_pre() { cv_saved "$WORK/cv_pre.out"; }
want_out "conventions: a check script that preloads a library is reported" \
	'c-piscine/c-piscine-c-99/tests/ex11/check.sh preloads a library itself' -- cv_pre
want_out "conventions: ...at the line that does it" \
	'    line 5: export LD_PRELOAD="$CK_REDIRECT_LIB"' -- cv_pre
want_broken_none "conventions: ...and not at the comment that names it" \
	'line 3: # LD_PRELOAD' -- cv_pre
# ck_run gives the turn-in /dev/null for stdin, so what a check pipes or
# redirects into it reaches nothing (Shell 01 ex08's loop over its cases).
# A `<` in a quoted argument, `||`, and a loop's own `done < file` are none.
# Toy ex33, its own: these arms once shared ex13 with the stable/script arms
# below, which rewrite their exercise's check.sh, and each group passed only
# because its own conv run came first. //tools:conventions now refuses a toy
# exercise's file written by two blocks.
mkdir -p "$_cv99/ex33"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' \
	'# printf x | ck_run is what this reports' 'ck_require "x exists" test -f "$1"' \
	'raw=$(mktemp)' "printf 'a\\n' | ck_run \"\$raw\" true" 'ck_run "$raw" true < "$1"' \
	'ck_run "$raw" env X="a < b" true' 'false || ck_run "$raw" true' \
	'while read -r l; do ck_run "$raw" true; done < "$1"' \
	'ck_run "$raw" true <<EOF' 'here' 'EOF' 'ck "fed nothing" true' 'ck_report' \
	> "$_cv99/ex33/check.sh"
! st_mine || conv > "$WORK/cv_fed.out" 2>&1
# Its own report alone: the lines of other fixtures' reports are numbered too.
cv_fed() { cv_saved "$WORK/cv_fed.out" sed -n '/ex33\/check.sh feeds ck_run a stdin/,/^  FAIL:/p'; }
want_out "conventions: a check that feeds ck_run a stdin is reported" \
	'c-piscine/c-piscine-c-99/tests/ex33/check.sh feeds ck_run a stdin' -- cv_fed
want_out "conventions: ...at the pipe" "    line 6: printf 'a\\n' | ck_run" -- cv_fed
want_out "conventions: ...at a redirection" '    line 7: ck_run "$raw" true < "$1"' -- cv_fed
want_out "conventions: ...and at a here-document" '    line 11: ck_run "$raw" true <<EOF' -- cv_fed
want_broken_none "conventions: ...not at a < inside quotes" '    line 8:' -- cv_fed
want_broken_none "conventions: ...nor at ||" '    line 9:' -- cv_fed
want_broken_none "conventions: ...nor at a loop's own done < file" '    line 10:' -- cv_fed
want_broken_none "conventions: ...nor at the comment" '    line 3:' -- cv_fed

# Twins. Reloaded's shell exercises read their Piscine twin's tests
# (shell_exercise's twin_of) instead of copies that drifted. The macro refuses
# a test file copied back into the twin's folder; what it cannot read is the
# README there, which must name the folder twin_of reads (reported when it
# does not, quiet when it does).
mkdir -p "$_cv98/ex23" "$_cv98/ex08" "$_cv98/ex09"
printf '%s\n' \
	'shell_exercise(num = "23", mode = "check", twin_of = "//c-piscine/c-piscine-c-99:ex04")' \
	'shell_exercise(' '    num = "08",' '    mode = "check",' \
	'    deliverable = "y.sh",  # its own name, one of the two things that may differ' \
	'    twin_of = "//c-piscine/c-piscine-c-99:ex06",' \
	'    wording = {"files": "all file names that end in y"},  # its subject'"'"'s words, the other' ')' \
	'shell_exercise(num = "09", mode = "check", twin_of = "//c-piscine/c-piscine-c-99:ex07")' \
	>> "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
printf '%s\n' \
	'shell_exercise(' '    num = "04",' '    mode = "check",' \
	'    readings = {"literal": "literal.sh"},' ')' \
	'shell_exercise(num = "06", mode = "check", deliverable = "x.sh", wording = {"files": "all x files"})' \
	>> "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
printf 'The tests are in c-piscine/c-piscine-c-99/tests/ex05/.\n' > "$_cv98/ex23/README.md"
printf 'The tests are in c-piscine/c-piscine-c-99/tests/ex06/.\n' > "$_cv98/ex08/README.md"
printf 'The tests are in c-piscine/c-piscine-c-99/tests/ex07/.\n' > "$_cv98/ex09/README.md"
# And a copy made without twin_of: c-99 ex04's check script, copied into a
# shell exercise of c-98's.
mkdir -p "$_cv98/ex22"
printf '%s\n' 'shell_exercise(num = "22", mode = "check")' \
	>> "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
cp "$_cv99/ex04/check.sh" "$_cv98/ex22/check.sh"
# ...and copied the way a person copies: a header comment of its own, and the
# name it checks changed. Every Reloaded copy differed from its source in a
# comment, two in the archive's name too, and a scan for identical files
# found one of the fourteen. c-99 ex06's script, which shares only its
# library lines with this one, is no copy of it.
mkdir -p "$_cv98/ex24" "$_cv98/ex25"
printf '%s\n' 'shell_exercise(num = "24", mode = "check")' \
	'shell_exercise(num = "25", mode = "diff", deliverable = "z", expected = "out.txt")' \
	>> "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
{
	printf '#!/bin/sh\n# ex24 -- the checks for y.sh, adapted.\n'
	sed 's/"x exists"/"y.sh exists"/' "$_cv99/ex04/check.sh"
} > "$_cv98/ex24/check.sh"
# ...and two scripts alike only in the lines this file requires of every
# check script -- the library's load line, ck_require, ck_sh_parses, a plain
# ck_run, ck_report -- and in one line of their own. Every check script has
# those lines, copied or not; counted, they made these two 6 of 7 lines alike
# and a copy.
mkdir -p "$_cv98/ex12" "$_cv99/ex12"
printf '%s\n' 'shell_exercise(num = "12", mode = "check")' \
	>> "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
printf '%s\n' 'shell_exercise(num = "12", mode = "check")' \
	>> "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
printf '%s\n' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "a.sh exists" test -f "$1"' \
	'ck_sh_parses "$1"' 'raw=$(mktemp)' 'ck_run "$raw" sh "$1"' \
	'ck "prints an a" grep -q a "$raw"' 'ck_report' > "$_cv98/ex12/check.sh"
printf '%s\n' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "b.sh exists" test -f "$1"' \
	'ck_sh_parses "$1"' 'raw=$(mktemp)' 'ck_run "$raw" sh "$1"' \
	'ck "prints no b" test ! -s "$raw"' 'ck_report' > "$_cv99/ex12/check.sh"
# Riding on this run, since the git rule's own run below has a toy library
# of its own: a ck_git_sandbox written `ck_git_sandbox () {`, which still
# runs, is a body the rule cannot cut out, and it leaves a name set. C 98's
# ex98 calls it, and is let off the git rule for it, so the body that cannot
# be read is reported rather than held by nothing.
mkdir -p "$_cv98/ex98"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'ck_git_sandbox' 'git init -q repo' 'ck "g is not empty" test -s "$1"' 'ck_report' \
	> "$_cv98/ex98/check.sh"
printf '%s\n' '# shellcheck shell=sh' 'ck_git_sandbox () {' '	GIT_CONFIG_NOSYSTEM=1' \
	'	HOME=/nonexistent' '	XDG_CONFIG_HOME="$HOME/.config"' \
	'	export GIT_CONFIG_NOSYSTEM HOME XDG_CONFIG_HOME' \
	'	unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR' \
	'	unset GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS' '}' > "$WORK/cv/tools/shell_check.sh"
! st_mine || conv > "$WORK/cv_twin.out" 2>&1
rm -f "$WORK/cv/tools/shell_check.sh"
cv_twin() { cv_saved "$WORK/cv_twin.out"; }
want_out "conventions: a twin README naming another folder is reported" \
	'c-piscine/c-piscine-c-98/tests/ex23/README.md does not name c-piscine/c-piscine-c-99/tests/ex04/' -- \
	cv_twin
want_broken_none "conventions: a twin whose README names its twin is not" \
	'c-piscine/c-piscine-c-98/tests/ex08' -- \
	cv_twin
want_out "conventions: a ck_git_sandbox the rule cannot read, while a check calls it, is reported" \
	'check scripts call ck_git_sandbox or ck_git_init, and this rule cannot read ck_git_sandbox in tools/shell_check.sh' -- \
	cv_twin
want_out "conventions: ...naming the check that calls it" \
	'            c-piscine/c-piscine-c-98/tests/ex98/check.sh' -- cv_twin
# What the call says comes with the tests: a reading given on the exercise's
# call and not on its twin's runs for one project only. The twin that names
# its exercise's arguments the same way, deliverable and wording apart (its
# own file's name, and its own subject's words for what the check quotes), is
# quiet; one that names an exercise with no shell_exercise call is reported
# for that.
want_out "conventions: a twin called unlike its exercise is reported" \
	'readings: (not given) here, {"literal":"literal.sh"} there' -- cv_twin
want_broken_none "conventions: a twin called like it, deliverable and wording apart, is not" \
	"c-piscine/c-piscine-c-98's ex08" -- cv_twin
want_out "conventions: a twin of an exercise no call declares is reported" \
	"c-piscine/c-piscine-c-98's ex09 names a twin that has no shell_exercise call" -- \
	cv_twin
want_out "conventions: a shell test file copied without twin_of is reported" \
	'c-piscine/c-piscine-c-98/tests/ex22/check.sh and c-piscine/c-piscine-c-99/tests/ex04/check.sh' -- \
	cv_twin
want_out "conventions: ...and one whose comment and one word were changed" \
	'c-piscine/c-piscine-c-98/tests/ex24/check.sh and c-piscine/c-piscine-c-99/tests/ex04/check.sh' -- \
	cv_twin
want_broken_none "conventions: two scripts alike in their library lines only are not" \
	'c-piscine/c-piscine-c-99/tests/ex06/check.sh (' -- cv_twin
want_broken_none "conventions: ...nor two alike in the lines it requires" \
	'c-piscine/c-piscine-c-98/tests/ex12/check.sh and' -- cv_twin
# What the scan cannot see it says: under Bazel, a test file outside the
# conventions_srcs glob (the expected files were, and the copy of Shell 00
# ex00's went uncompared); here, a file the call names that is not there.
want_out "conventions: a named test file the copy scan cannot see is reported" \
	'            c-piscine/c-piscine-c-98/tests/ex25/out.txt' -- cv_twin

# What a call says and its check relies on. stable = True makes the second run
# of the generator that ck_stable compares: either without the other stops
# the check (exit 2) when it runs, and this names it before anyone does. And
# script says the turn-in is a script, which the lint targets read: a check
# that asks /bin/sh to parse the turn-in (ck_sh_parses), or a diff that runs
# it (run = True), with no script on the call leaves the file 42 grades
# unlinted, and a script no check parses is linted above basic only. And
# script = "./name" and a check's ck_executable both say the subject runs
# the file as ./name: either alone is reported. A pair that agrees is quiet.
mkdir -p "$_cv99/ex13" "$_cv99/ex14" "$_cv99/ex15" "$_cv99/ex16" "$_cv99/ex17" \
	"$_cv99/ex18" "$_cv99/ex19" "$_cv99/ex20" "$_cv99/ex21"
printf '%s\n' \
	'shell_exercise(num = "13", mode = "check", stable = True)' \
	'shell_exercise(num = "14", mode = "check")' \
	'shell_exercise(num = "15", mode = "check", stable = True, script = "sh")' \
	'shell_exercise(num = "16", mode = "check", script = "bash")' \
	'shell_exercise(num = "17", mode = "diff", deliverable = "w.sh", run = True)' \
	'shell_exercise(' '    num = "18",' '    mode = "diff",' '    deliverable = "v.sh",' \
	'    run = True,' '    script = "sh",' ')' \
	'shell_exercise(num = "19", mode = "check", script = "sh")' \
	'shell_exercise(num = "20", mode = "check", script = "./name")' \
	'shell_exercise(num = "21", mode = "check", script = "./name")' \
	>> "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
for _x in 19 21; do
	printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "q exists" test -f "$1"' \
		'ck_executable "$1"' 'ck_sh_parses "$1"' 'ck "q is not empty" test -s "$1"' \
		'ck_report' > "$_cv99/ex$_x/check.sh"
done
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "r exists" test -f "$1"' \
	'ck_sh_parses "$1"' 'ck "r is not empty" test -s "$1"' 'ck_report' > "$_cv99/ex20/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "p exists" test -f "$1"' \
	'ck "p is not empty" test -s "$1"' 'ck_report' > "$_cv99/ex16/check.sh"
printf 'w\n' > "$_cv99/ex17/expected.txt"
printf 'v\n' > "$_cv99/ex18/expected.txt"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "k exists" test -f "$1"' \
	'ck "k is a key" grep -q "^ssh-" "$1"' 'ck_report' > "$_cv99/ex13/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "m exists" test -f "$1"' \
	'ck_stable "m is the same twice" "$1"' 'ck_report' > "$_cv99/ex14/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "n exists" test -f "$1"' \
	'	ck_sh_parses "$1"' '  ck_stable "n is the same twice" "$1"' \
	'ck "n holds a line" test -s "$1"' 'ck_report' > "$_cv99/ex15/check.sh"
# A check that builds a git repository does it under no configuration but
# its own: ex22 runs git with the host's (reported), ex23 exports a
# GIT_CONFIG_NOSYSTEM, a HOME and an XDG_CONFIG_HOME of its own first
# (quiet), ex24 sets them and never exports HOME (reported), and ex25 only
# names git in a comment (quiet). git is a command wherever one can stand:
# ex26 runs it in a $(...), ex27 after &&, ex29 after if -- each reported,
# as the rule once read git at the start of a line only. ex28 exports the
# first two and not XDG_CONFIG_HOME, whose git/ignore git reads whatever
# HOME says (reported, naming it); ex30 unsets it instead (quiet); and ex31
# names git in a check's label and a grep pattern, which run no git (quiet).
# ex32 runs git through ck_run past its --crlf and --no-redirect options,
# which ck_run's -C was once the only option read past (reported). C 98's
# ex90 runs it first behind command -p, ex91 through env named by its path
# (each reported, at that line, and not at the git after it).
mkdir -p "$_cv99/ex22" "$_cv99/ex23" "$_cv99/ex24" "$_cv99/ex25" "$_cv99/ex26" \
	"$_cv99/ex27" "$_cv99/ex28" "$_cv99/ex29" "$_cv99/ex30" "$_cv99/ex31" "$_cv99/ex32"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'git init -q repo' 'ck "g is not empty" test -s "$1"' 'ck_report' > "$_cv99/ex22/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'GIT_CONFIG_NOSYSTEM=1' 'HOME=$(mktemp -d)' 'XDG_CONFIG_HOME="$HOME/.config"' \
	'export GIT_CONFIG_NOSYSTEM HOME XDG_CONFIG_HOME' 'unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR' 'unset GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT' \
	'(' '	git init -q repo' ')' 'ck "g is not empty" test -s "$1"' 'ck_report' \
	> "$_cv99/ex23/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'export GIT_CONFIG_NOSYSTEM=1' 'HOME=$(mktemp -d)' '	git init -q repo' \
	'ck "g is not empty" test -s "$1"' 'ck_report' > "$_cv99/ex24/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'# the turn-in calls git log; this check does not' \
	'ck "g is not empty" test -s "$1"' 'ck_report' > "$_cv99/ex25/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'h=$(git rev-parse HEAD 2> /dev/null)' 'ck "g names the head" grep -q "$h" "$1"' \
	'ck_report' > "$_cv99/ex26/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'mkdir -p repo' 'cd repo && git init -q' 'ck "g is not empty" test -s "$1"' 'ck_report' \
	> "$_cv99/ex27/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'GIT_CONFIG_NOSYSTEM=1' 'HOME=$(mktemp -d)' 'export GIT_CONFIG_NOSYSTEM HOME' \
	'git init -q repo' 'ck "g is not empty" test -s "$1"' 'ck_report' > "$_cv99/ex28/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'if git diff --quiet; then :; fi' 'ck "g is not empty" test -s "$1"' 'ck_report' \
	> "$_cv99/ex29/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'export GIT_CONFIG_NOSYSTEM=1' 'export HOME="$PWD/home"' 'unset XDG_CONFIG_HOME' 'unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR' 'unset GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT' \
	'git init -q repo' 'ck "g is not empty" test -s "$1"' 'ck_report' > "$_cv99/ex30/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'ck "g says git init" grep -q "git init" "$1"' 'ck_report' > "$_cv99/ex31/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'raw=$(mktemp)' 'ck_run --crlf --no-redirect "$raw" git log' 'ck "g logs" test -s "$raw"' \
	'ck_report' > "$_cv99/ex32/check.sh"
mkdir -p "$_cv98/ex90" "$_cv98/ex91"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'command -p git init -q repo' 'git init -q again' 'ck "g is not empty" test -s "$1"' 'ck_report' \
	> "$_cv98/ex90/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'/usr/bin/env git init -q repo' 'git init -q again' 'ck "g is not empty" test -s "$1"' 'ck_report' \
	> "$_cv98/ex91/check.sh"
# ex34 sets and exports all three, and unsets only some of what a run outside
# Bazel's cleared environment inherits about git (reported, naming the rest).
mkdir -p "$_cv99/ex34"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'GIT_CONFIG_NOSYSTEM=1' 'HOME=$(mktemp -d)' 'XDG_CONFIG_HOME="$HOME/.config"' \
	'export GIT_CONFIG_NOSYSTEM HOME XDG_CONFIG_HOME' 'unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR' \
	'git init -q repo' 'ck "g is not empty" test -s "$1"' 'ck_report' > "$_cv99/ex34/check.sh"
# tools/shell_check.sh's ck_git_sandbox does the same, and a call to it
# before the first git meets the rule: C 98's ex92 calls it first (quiet),
# ex93 runs git before it (reported), and ex94 builds its repository with
# ck_git_init, a git command too, and calls no sandbox (reported). A helper
# whose unset list misses a name is reported: the toy library below.
mkdir -p "$_cv98/ex92" "$_cv98/ex93" "$_cv98/ex94"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'ck_git_sandbox' '( ck_git_init repo || exit 1 ) || ck_broken "no repo"' 'git -C repo log' \
	'ck "g is not empty" test -s "$1"' 'ck_report' > "$_cv98/ex92/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'git init -q repo' 'ck_git_sandbox' 'ck "g is not empty" test -s "$1"' 'ck_report' \
	> "$_cv98/ex93/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "g exists" test -f "$1"' \
	'( ck_git_init repo || exit 1 ) || ck_broken "no repo"' 'ck "g is not empty" test -s "$1"' \
	'ck_report' > "$_cv98/ex94/check.sh"
printf '%s\n' '# shellcheck shell=sh' 'ck_git_sandbox() {' '	GIT_CONFIG_NOSYSTEM=1' \
	'	HOME=/nonexistent' '	XDG_CONFIG_HOME="$HOME/.config"' \
	'	export GIT_CONFIG_NOSYSTEM HOME XDG_CONFIG_HOME' \
	'	unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR' \
	'	unset GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS' '}' > "$WORK/cv/tools/shell_check.sh"
# A check that asks //oracle says so with ck_oracle before it reads $ORACLE,
# so a call without oracle = True is refused with what to add: C 98's ex95
# does (quiet), ex96 runs the reference with no ck_oracle (reported), and
# ex97 keeps the ${ORACLE:?} line ck_oracle replaced, whose abort ended in
# the exit guard's advice to add ck_report (reported).
mkdir -p "$_cv98/ex95" "$_cv98/ex96" "$_cv98/ex97"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "o exists" test -f "$1"' \
	'ck_oracle' 'w=$("$ORACLE" toy_arm)' 'ck "o is the reference" test "$(cat "$1")" = "$w"' \
	'ck_report' > "$_cv98/ex95/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "o exists" test -f "$1"' \
	'w=$("$ORACLE" toy_arm)' 'ck "o is the reference" test "$(cat "$1")" = "$w"' \
	'ck_report' > "$_cv98/ex96/check.sh"
printf '%s\n' '#!/bin/sh' '. "${SHELL_CHECK_LIB:?}"' 'ck_require "o exists" test -f "$1"' \
	'ORACLE=${ORACLE:?this check needs //oracle}' 'ck_oracle' 'w=$("$ORACLE" toy_arm)' \
	'ck "o is the reference" test "$(cat "$1")" = "$w"' 'ck_report' > "$_cv98/ex97/check.sh"
# The harness's own tests are held to the unset too, and to a check
# script's settings: a hand run of selftest.sh inherits a `git rebase -x`
# shell's GIT_DIR (V331), and its git read the host's /etc/gitconfig and
# ~/.gitconfig. git_bare runs git with none unset (reported), git_unset
# unsets the list first and sets nothing (quiet on the unset, reported on
# the settings), git_isolated does both (quiet).
printf '%s\n' '#!/bin/sh' 'set -u' 'git init -q "$1"' > "$WORK/cv/tools/tests/probe_git_bare.sh"
printf '%s\n' '#!/bin/sh' 'set -u' \
	'unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR' \
	'unset GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT' 'git init -q "$1"' \
	> "$WORK/cv/tools/tests/probe_git_unset.sh"
printf '%s\n' '#!/bin/sh' 'set -u' \
	'unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR' \
	'unset GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT' \
	'HOME=$(mktemp -d)' 'XDG_CONFIG_HOME="$HOME/.config"' 'GIT_CONFIG_NOSYSTEM=1' \
	'export HOME XDG_CONFIG_HOME GIT_CONFIG_NOSYSTEM' 'git init -q "$1"' \
	> "$WORK/cv/tools/tests/probe_git_isolated.sh"
! st_mine || conv > "$WORK/cv_calls.out" 2>&1
rm -f "$WORK/cv/tools/tests/probe_git_bare.sh" "$WORK/cv/tools/tests/probe_git_unset.sh" \
	"$WORK/cv/tools/tests/probe_git_isolated.sh" "$WORK/cv/tools/shell_check.sh"
cv_calls() { cv_saved "$WORK/cv_calls.out"; }
want_out "conventions: a check that runs git under the host's configuration is reported" \
	'c-piscine/c-piscine-c-99/tests/ex22/check.sh runs git (line 4)' -- cv_calls
want_broken_none "conventions: ...and one that exports its own first is not" \
	'c-piscine/c-piscine-c-99/tests/ex23/check.sh runs git' -- cv_calls
want_out "conventions: ...as is one that sets HOME and never exports it" \
	'c-piscine/c-piscine-c-99/tests/ex24/check.sh runs git' -- cv_calls
want_broken_none "conventions: ...and git named in a comment is not a git command" \
	'c-piscine/c-piscine-c-99/tests/ex25/check.sh runs git' -- cv_calls
want_out "conventions: ...git in a \$(...) is a git command" \
	'c-piscine/c-piscine-c-99/tests/ex26/check.sh runs git (line 4)' -- cv_calls
want_out "conventions: ...and so is git after &&" \
	'c-piscine/c-piscine-c-99/tests/ex27/check.sh runs git (line 5)' -- cv_calls
want_out "conventions: ...and git after if" \
	'c-piscine/c-piscine-c-99/tests/ex29/check.sh runs git (line 4)' -- cv_calls
want_out "conventions: ...a check that leaves XDG_CONFIG_HOME as it found it is reported" \
	'c-piscine/c-piscine-c-99/tests/ex28/check.sh runs git (line 7)' -- cv_calls
want_out "conventions: ...saying which setting is missing" \
	'Not set and exported before it: XDG_CONFIG_HOME.' -- cv_calls
want_broken_none "conventions: ...and one that unsets it is not" \
	'c-piscine/c-piscine-c-99/tests/ex30/check.sh runs git' -- cv_calls
want_out "conventions: ...a check that leaves GIT_CONFIG_GLOBAL and the rest set is reported" \
	'c-piscine/c-piscine-c-99/tests/ex34/check.sh runs git (line 9) under what the environment says' -- cv_calls
want_out "conventions: ...naming what it did not unset" \
	'Not unset before it: GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT.' -- cv_calls
want_out "conventions: a test under tools/tests that runs git with the host's GIT_DIR is reported" \
	'tools/tests/probe_git_bare.sh runs git (line 3) under what the environment says' -- cv_calls
want_broken_none "conventions: ...and one that unsets it first is not" \
	'tools/tests/probe_git_unset.sh runs git (line 5) under what the environment says' -- cv_calls
want_out "conventions: ...but is, under the host's git configuration" \
	"tools/tests/probe_git_unset.sh runs git (line 5) under the host's configuration" -- cv_calls
want_broken_none "conventions: ...and one that also sets and exports the settings is not" \
	'tools/tests/probe_git_isolated.sh runs git' -- cv_calls
want_broken_none "conventions: ...nor git in a label or a pattern" \
	'c-piscine/c-piscine-c-99/tests/ex31/check.sh runs git' -- cv_calls
want_out "conventions: ...and git run by ck_run past its options is a git command" \
	'c-piscine/c-piscine-c-99/tests/ex32/check.sh runs git (line 5)' -- cv_calls
want_out "conventions: ...and so is git behind command -p" \
	'c-piscine/c-piscine-c-98/tests/ex90/check.sh runs git (line 4)' -- cv_calls
want_out "conventions: ...and behind env named by its path" \
	'c-piscine/c-piscine-c-98/tests/ex91/check.sh runs git (line 4)' -- cv_calls
want_broken_none "conventions: ...and a ck_git_sandbox before the first git meets the rule" \
	'c-piscine/c-piscine-c-98/tests/ex92/check.sh runs git' -- cv_calls
want_out "conventions: ...one after it does not" \
	'c-piscine/c-piscine-c-98/tests/ex93/check.sh runs git (line 4)' -- cv_calls
want_out "conventions: ...and ck_git_init is a git command" \
	'c-piscine/c-piscine-c-98/tests/ex94/check.sh runs git (line 4)' -- cv_calls
want_broken_none "conventions: a check that calls ck_oracle before it reads \$ORACLE is quiet" \
	'c-piscine/c-piscine-c-98/tests/ex95/check.sh reads $ORACLE' -- cv_calls
want_out "conventions: ...one that never calls it is reported" \
	'c-piscine/c-piscine-c-98/tests/ex96/check.sh reads $ORACLE (line 4) before any ck_oracle' -- cv_calls
want_out "conventions: ...and so is the \${ORACLE:?} line it replaced" \
	'c-piscine/c-piscine-c-98/tests/ex97/check.sh reads $ORACLE (line 4) before any ck_oracle' -- cv_calls
want_out "conventions: a ck_git_sandbox that leaves a name set is reported" \
	"tools/shell_check.sh's ck_git_sandbox leaves what the environment says of git" -- cv_calls
want_out "conventions: ...naming it" \
	'Not unset: GIT_CONFIG_COUNT.' -- cv_calls
want_out "conventions: stable = True over a check that never compares is reported" \
	"c-piscine/c-piscine-c-99's ex13 says stable = True" -- cv_calls
want_out "conventions: ck_stable in a check whose call has no stable is reported" \
	'c-piscine/c-piscine-c-99/tests/ex14/check.sh calls ck_stable' -- cv_calls
want_broken_none "conventions: ...and the two together are not" \
	"c-piscine/c-piscine-c-99's ex15 says stable" -- cv_calls
want_broken_none "conventions: ...from either side" \
	'c-piscine/c-piscine-c-99/tests/ex15/check.sh calls ck_stable' -- cv_calls
want_out "conventions: a check that parses the turn-in, on a call with no script, is reported" \
	"c-piscine/c-piscine-c-99's ex04 turns in a script, and its call does not say so" -- cv_calls
want_out "conventions: ...and a diff that runs it" \
	"c-piscine/c-piscine-c-99's ex17 turns in a script" -- cv_calls
want_out "conventions: script on a call whose check never parses it is reported" \
	"c-piscine/c-piscine-c-99's ex16 says script = \"bash\"" -- cv_calls
want_broken_none "conventions: ...and script with ck_sh_parses is not" \
	"c-piscine/c-piscine-c-99's ex15 turns in" -- cv_calls
want_broken_none "conventions: ...nor script on a diff that runs it" \
	"c-piscine/c-piscine-c-99's ex18" -- cv_calls
want_out "conventions: a check that asks for the execute bit, on a call that says \"sh\", is reported" \
	"c-piscine/c-piscine-c-99/tests/ex19/check.sh asks for the execute bit" -- cv_calls
want_out "conventions: ...and \"./name\" over a check that never asks for it" \
	"c-piscine/c-piscine-c-99's ex20 says script = \"./name\"" -- cv_calls
want_broken_none "conventions: ...and the two together are not" \
	"c-piscine/c-piscine-c-99's ex21" -- cv_calls
want_broken_none "conventions: ...from either side" \
	"c-piscine/c-piscine-c-99/tests/ex21/check.sh" -- cv_calls

# Every FAIL the run prints is one it counts. A check whose findings are
# reported from inside a `... | while read` loop runs that loop in a subshell:
# the report prints, the count it adds is thrown away with the subshell, and
# a tree holding nothing else wrong exits 0 under "OK -- every check passed".
# Both the fixture-PATH check and the twin check above were written that way
# once. The fixture tree has plenty wrong with it by now, so the two numbers
# are compared rather than the exit status, read off cv_calls' run: nothing
# has changed the tree since.
cv_counted() {
	_o=$(cv_saved "$WORK/cv_calls.out")
	[ "$?" -lt 2 ] || { printf '%s\n' "$_o"; return 2; }
	_n=$(printf '%s\n' "$_o" | grep -c '^  FAIL: ')
	_c=$(printf '%s\n' "$_o" | sed -n 's/^conventions: FAIL [^0-9]*\([0-9][0-9]*\) convention.*/\1/p')
	printf 'printed %s FAIL line(s), counted %s\n' "$_n" "${_c:-none}"
	[ -n "$_c" ] && [ "$_n" = "$_c" ]
}
want_green "conventions: every FAIL it prints is in its count" -- cv_counted

# The guard that keeps a shrunken scan from reporting the same green, in both of
# the ways it can be starved. A module the table names and the run cannot see
# is a short file list; a table that yields NO module is a parse that failed --
# the exact failure a key-shape regex produced when the modules moved, after
# which every module-walking check above walked nothing and said OK.
mkdir -p "$WORK/cv2/tools" "$WORK/cv3/tools"
cv_submit "c-piscine/c-piscine-c-97" > "$WORK/cv2/tools/submit.sh"
cv_submit "" > "$WORK/cv3/tools/submit.sh"
want_broken "conventions: a module the run cannot see is refused" \
	"cannot see the BUILD file of: c-piscine/c-piscine-c-97" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cv2" "$SH" "$TOOLS/conventions.sh"
want_broken "conventions: a REMOTES table with no module is refused" \
	"found no modules" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cv3" "$SH" "$TOOLS/conventions.sh"

# The third way to be starved: a single file a check reads only where it
# exists (`if [ -f tools/pins.tsv ]`) that nobody declared to the test. Under
# `bazel test` that check stood down in silence on every run, and the pins it
# compares went uncompared. cvrf is a runfiles tree, reached through
# TEST_SRCDIR as a real test reaches its own, holding a module and nothing
# else: refused, naming the file. Every file the refusal names, made, and it
# is not refused -- so what it names is what it needs, the maintainer's two
# files (which a fresh clone lacks) never among them. Under `bazel run` the
# same absence is only a tree without the file, which is how every arm above
# runs, unrefused.
mkdir -p "$WORK/cvrf/_main/tools" "$WORK/cvrf/_main/c-piscine/c-piscine-c-98"
: > "$WORK/cvrf/_main/c-piscine/c-piscine-c-98/BUILD.bazel"
cv_submit "c-piscine/c-piscine-c-98" > "$WORK/cvrf/_main/tools/submit.sh"
cvrf() {
	env BUILD_WORKSPACE_DIRECTORY= TEST_SRCDIR="$WORK/cvrf" TEST_WORKSPACE=_main \
		"$SH" "$TOOLS/conventions.sh" 2>&1
}
# The files a refusal names, one per line; a refusal that names none is not
# one, and says so with 2, so the arm reading it cannot pass on nothing.
cvrf_named() {
	_n=$(cvrf | sed -n 's/^    \([A-Za-z0-9_./-]*\)$/\1/p')
	[ -n "$_n" ] || return 2
	printf '%s\n' "$_n"
}
want_broken "conventions: a guarded file missing from a test's runfiles is refused" \
	"    tools/pins.tsv" -- cvrf
want_broken_none "conventions: ...never for the maintainer's own files" \
	"TODO.md" -- cvrf_named
cvrf_named > "$WORK/cvrf.need"
while IFS= read -r _f; do
	mkdir -p "$WORK/cvrf/_main/$(dirname "$_f")" && : > "$WORK/cvrf/_main/$_f"
done < "$WORK/cvrf.need"
want_broken_none "conventions: ...and each file it names, there, ends the refusal" \
	"missing from the test's runfiles" -- cvrf

# Commenting a row out stops a module being PUSHED; it does not stop it being a
# module. The same two fixture modules, with c-99's row commented out: its
# missing sanitize harness must still be reported (the @addr check).
mkdir -p "$WORK/cv4/tools"
cp -R "$WORK/cv/c-piscine" "$WORK/cv4/"
{
	printf "#!/bin/sh\nREMOTES='\n"
	printf 'c-piscine/c-piscine-c-98=REPLACE_ME\n'
	printf '# c-piscine/c-piscine-c-99=REPLACE_ME   # submitted already\n'
	printf "'\n"
} > "$WORK/cv4/tools/submit.sh"
# Nothing writes to cv4 after this, so its one run is read here and by the
# two arms on its missing tables further down.
! st_mine || env BUILD_WORKSPACE_DIRECTORY="$WORK/cv4" "$SH" "$TOOLS/conventions.sh" > "$WORK/cv4.out" 2>&1
want_out "conventions: a commented-out row's module is still scanned" \
	"c-piscine/c-piscine-c-99/tests/ex07/t.c, a sanitize harness its c_function names" -- \
	cv_saved "$WORK/cv4.out"

# PERF'S FAILING LINES, said once (finding 043): the runner's defaults, c_perf's
# and the two docs that state them. cv8 disagrees in one place -- the memory
# multiple the docs give -- and only inside the section that counts: the right
# number further down the file must not satisfy the rule. cv7 agrees. Each is
# a tree of its own: cv6, which this loop once reused, is the first
# conventions section's, so this run read that section's modules too.
for _cv in cv8 cv7; do
	mkdir -p "$WORK/$_cv/tools" "$WORK/$_cv/docs" "$WORK/$_cv/c-piscine/c-piscine-c-98"
	: > "$WORK/$_cv/c-piscine/c-piscine-c-98/BUILD.bazel"
	cv_submit "c-piscine/c-piscine-c-98" > "$WORK/$_cv/tools/submit.sh"
	printf '#!/bin/sh\nset -u\nGATE_EXPONENT="2.6"\nGATE_SLOWDOWN="5000"\nGATE_MEMORY="200"\n' \
		> "$WORK/$_cv/tools/perf_test.sh"
	printf '| `perf` | complete | past n^2.6, 5000x its time or 200x its memory |\n' \
		> "$WORK/$_cv/docs/reference.md"
done
printf '## The two cost layers\n\nn^2.6, 5000 times its time, 300 times its memory.\n\n## Next\n\n200 times\n' \
	> "$WORK/cv8/docs/testing.md"
printf '## The two cost layers\n\nn^2.6, 5000 times its time, 200 times its memory.\n' \
	> "$WORK/cv7/docs/testing.md"
want_out "conventions: perf's lines and its docs disagreeing is named" \
	'does not say "200 times"' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cv8" "$SH" "$TOOLS/conventions.sh"
want_broken_none "conventions: ...and agreeing is quiet" \
	"perf's failing lines" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cv7" "$SH" "$TOOLS/conventions.sh"

# A C EXERCISE REPEATING ANOTHER MODULE'S (c_twin): Reloaded's tests/ex27 was
# C 10 ex00's, byte for byte, and four more pairs like it, none declared, so
# a fix reached one copy. cvt holds such a pair: undeclared, it is reported;
# declared, it is quiet; declared and drifted -- one hint edited -- it is
# reported again, naming the file. Each state is its own run. A pair is
# named in byte order, whatever the locale: it was the locale's, and the
# arms failed on a machine without the test locale (V338).
mkdir -p "$WORK/cvt/tools" "$WORK/cvt/c-piscine/c-piscine-c-91/tests/ex00" \
	"$WORK/cvt/c-piscine-reloaded/c-piscine-reloaded/tests/ex27"
cv_submit "c-piscine/c-piscine-c-91 c-piscine-reloaded/c-piscine-reloaded" > "$WORK/cvt/tools/submit.sh"
: > "$WORK/cvt/c-piscine/c-piscine-c-91/BUILD.bazel"
: > "$WORK/cvt/c-piscine-reloaded/c-piscine-reloaded/BUILD.bazel"
for _f in show.txt cannot.txt blob.txt; do
	printf 'made up for the selftest: %s\n' "$_f" > "$WORK/cvt/c-piscine/c-piscine-c-91/tests/ex00/$_f"
	cp "$WORK/cvt/c-piscine/c-piscine-c-91/tests/ex00/$_f" "$WORK/cvt/c-piscine-reloaded/c-piscine-reloaded/tests/ex27/$_f"
done
cvt() { env BUILD_WORKSPACE_DIRECTORY="$WORK/cvt" "$SH" "$TOOLS/conventions.sh"; }
want_out "conventions: a test folder copied from another module is reported" \
	"c-piscine-reloaded/c-piscine-reloaded/tests/ex27 and c-piscine/c-piscine-c-91/tests/ex00" -- cvt
printf 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")\n' \
	> "$WORK/cvt/c-piscine-reloaded/c-piscine-reloaded/BUILD.bazel"
want_broken_none "conventions: ...and declared with c_twin, it is not" \
	"c-piscine-c-91/tests/ex00" -- cvt
printf 'an expected line edited in one copy\n' >> "$WORK/cvt/c-piscine-reloaded/c-piscine-reloaded/tests/ex27/blob.txt"
want_out "conventions: ...but a declared twin that drifted is" \
	"blob.txt differs between c-piscine-reloaded/c-piscine-reloaded/tests/ex27 and c-piscine/c-piscine-c-91/tests/ex00" -- cvt
# The two c_program calls' cases, in every layout: written on the call's own
# line (C 11 ex05's), they were read as no cases on both sides and compared
# equal, so a drifted argument passed. And a call whose num is a variable
# cannot be matched, which is said rather than compared equal.
cp "$WORK/cvt/c-piscine/c-piscine-c-91/tests/ex00/blob.txt" \
	"$WORK/cvt/c-piscine-reloaded/c-piscine-reloaded/tests/ex27/blob.txt"
printf 'c_program(num = "00", name = "t", cases = [{"name": "a", "args": ["x"]}])\n' \
	> "$WORK/cvt/c-piscine/c-piscine-c-91/BUILD.bazel"
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'c_program(num = "27", name = "t", cases = [{"name": "a", "args": ["y"]}])' \
	> "$WORK/cvt/c-piscine-reloaded/c-piscine-reloaded/BUILD.bazel"
want_out "conventions: ...and so is a one-line call whose cases drifted" \
	"the cases of c-piscine-reloaded/c-piscine-reloaded's c_program(num = \"27\") differ" -- cvt
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'c_program(' '    num = "27",' '    name = "t",' '    cases = [' \
	'        {"name": "a", "args": ["x"]},  # the same list, laid out' '    ],' ')' \
	> "$WORK/cvt/c-piscine-reloaded/c-piscine-reloaded/BUILD.bazel"
want_broken_none "conventions: ...the same list laid out otherwise is not" \
	"c_program(num = \"27\") differ" -- cvt
# The two c_diff calls' size and the two c_cycles calls' budget: Reloaded's
# ex14 replays C 05 ex05's corpus, and when C 05's was raised to "large" the
# twin stayed "medium", a time limit a correct answer had come near on that
# very corpus, with nothing to say so. Each drift is its own run, then the
# same values laid out otherwise, a comment among them, are quiet.
_cvt_rl=$WORK/cvt/c-piscine-reloaded/c-piscine-reloaded/BUILD.bazel
printf '%s\n' 'c_program(num = "00", name = "t", cases = [{"name": "a", "args": ["x"]}])' \
	'c_diff(num = "00", fn = "ft_toy", harness = "diff_toy.c", oracle_fn = "toy", size = "large")' \
	'c_cycles(num = "00", fn = "ft_toy", oracle_fn = "toy", harness = "diff_toy.c", budget = 90)' \
	> "$WORK/cvt/c-piscine/c-piscine-c-91/BUILD.bazel"
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'c_program(num = "27", name = "t", cases = [{"name": "a", "args": ["x"]}])' \
	'c_diff(num = "27", fn = "ft_toy", harness = "diff_toy.c", oracle_fn = "toy", size = "medium")' \
	'c_cycles(num = "27", fn = "ft_toy", oracle_fn = "toy", harness = "diff_toy.c", budget = 90)' \
	> "$_cvt_rl"
want_out "conventions: ...and a c_diff whose size drifted is reported" \
	"the size of c-piscine-reloaded/c-piscine-reloaded's c_diff(num = \"27\") differs" -- cvt
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'c_program(num = "27", name = "t", cases = [{"name": "a", "args": ["x"]}])' \
	'c_diff(num = "27", fn = "ft_toy", harness = "diff_toy.c", oracle_fn = "toy", size = "large")' \
	'c_cycles(num = "27", fn = "ft_toy", oracle_fn = "toy", harness = "diff_toy.c", budget = 60)' \
	> "$_cvt_rl"
want_out "conventions: ...and so is a c_cycles whose budget drifted" \
	"the budget of c-piscine-reloaded/c-piscine-reloaded's c_cycles(num = \"27\") differs" -- cvt
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'c_program(num = "27", name = "t", cases = [{"name": "a", "args": ["x"]}])' \
	'c_diff(num = "27", fn = "ft_toy", harness = "diff_toy.c", oracle_fn = "toy", size = "large")' \
	> "$_cvt_rl"
want_out "conventions: ...and a twin with no c_cycles where its exercise has one" \
	"the budget of c-piscine-reloaded/c-piscine-reloaded's c_cycles(num = \"27\") differs" -- cvt
# The counts and the syscall budget, in one run: a twin whose c_diff replays
# fewer cases than its exercise's, and whose c_cycles allows a syscall more.
# Both lines are asked of the one report (cvt_kept keeps it for the second).
cvt_kept() { cvt > "$WORK/cvt.out" 2>&1; _r=$?; cat "$WORK/cvt.out"; return "$_r"; }
printf '%s\n' 'c_program(num = "00", name = "t", cases = [{"name": "a", "args": ["x"]}])' \
	'c_diff(num = "00", fn = "ft_toy", harness = "diff_toy.c", oracle_fn = "toy", size = "large", count = 400000)' \
	'c_cycles(num = "00", fn = "ft_toy", oracle_fn = "toy", harness = "diff_toy.c", budget = 90, syscall_budget = 0)' \
	> "$WORK/cvt/c-piscine/c-piscine-c-91/BUILD.bazel"
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'c_program(num = "27", name = "t", cases = [{"name": "a", "args": ["x"]}])' \
	'c_diff(num = "27", fn = "ft_toy", harness = "diff_toy.c", oracle_fn = "toy", size = "large", count = 200000)' \
	'c_cycles(num = "27", fn = "ft_toy", oracle_fn = "toy", harness = "diff_toy.c", budget = 90, syscall_budget = 1)' \
	> "$_cvt_rl"
want_out "conventions: ...and so is a c_diff whose count drifted" \
	"the count of c-piscine-reloaded/c-piscine-reloaded's c_diff(num = \"27\") differs" -- cvt_kept
want_out "conventions: ...and, in the same run, a c_cycles's syscall_budget" \
	"the syscall_budget of c-piscine-reloaded/c-piscine-reloaded's c_cycles(num = \"27\") differs" -- \
	cat "$WORK/cvt.out"
# The seed, which picks the corpus a count is a count of: two equal counts
# of two seeds replay two corpora, and the seed was not compared.
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'c_program(num = "27", name = "t", cases = [{"name": "a", "args": ["x"]}])' \
	'c_diff(num = "27", fn = "ft_toy", harness = "diff_toy.c", oracle_fn = "toy", size = "large", count = 400000, seed = 7)' \
	'c_cycles(num = "27", fn = "ft_toy", oracle_fn = "toy", harness = "diff_toy.c", budget = 90, syscall_budget = 0)' \
	> "$_cvt_rl"
want_out "conventions: ...and so is a c_diff whose seed drifted" \
	"the seed of c-piscine-reloaded/c-piscine-reloaded's c_diff(num = \"27\") differs" -- cvt
printf '%s\n' 'c_program(num = "00", name = "t", cases = [{"name": "a", "args": ["x"]}])' \
	'c_diff(num = "00", fn = "ft_toy", harness = "diff_toy.c", oracle_fn = "toy", size = "large")' \
	'c_cycles(num = "00", fn = "ft_toy", oracle_fn = "toy", harness = "diff_toy.c", budget = 90)' \
	> "$WORK/cvt/c-piscine/c-piscine-c-91/BUILD.bazel"
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'c_program(num = "27", name = "t", cases = [{"name": "a", "args": ["x"]}])' \
	'c_diff(' '    num = "27",' '    fn = "ft_toy",' '    harness = "diff_toy.c",' \
	'    oracle_fn = "toy",' '    # the same size, laid out' '    size = "large",' ')' \
	'c_cycles(' '    num = "27",' '    fn = "ft_toy",' '    oracle_fn = "toy",' \
	'    harness = "diff_toy.c",' '    budget = 90,' ')' \
	> "$_cvt_rl"
want_broken_none "conventions: ...the same size and budget laid out otherwise are not" \
	"differs from //c-piscine/c-piscine-c-91:ex00's" -- cvt
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'[c_program(num = n, name = "t", cases = [{"name": "a", "args": ["x"]}]) for n in ["27"]]' \
	> "$WORK/cvt/c-piscine-reloaded/c-piscine-reloaded/BUILD.bazel"
want_out "conventions: ...and a call it cannot match is named" \
	"cannot be compared" -- cvt
# The two c_header calls' cases: Reloaded's ex22 and ex23 hold their case
# lists, levels and clues there, copied from C 08's, and only c_program's
# were compared, so a level raised on one copy went unseen. A case's level
# drifted is reported; the same list laid out otherwise is not. And the
# c_cycles keys a twin copies beside its budgets: a unit_expr drifted.
printf '%s\n' 'c_header(num = "00", main = "t.c", cases = [{"name": "a", "args": [], "expected": "e.txt", "level": 2}])' \
	> "$WORK/cvt/c-piscine/c-piscine-c-91/BUILD.bazel"
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'c_header(num = "27", main = "t.c", cases = [{"name": "a", "args": [], "expected": "e.txt", "level": 3}])' \
	> "$_cvt_rl"
want_out "conventions: ...and so is a c_header whose case level drifted" \
	"the cases of c-piscine-reloaded/c-piscine-reloaded's c_header(num = \"27\") differ" -- cvt
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'c_header(' '    num = "27",' '    main = "t.c",' '    cases = [' \
	'        {"name": "a", "args": [], "expected": "e.txt", "level": 2},  # laid out' '    ],' ')' \
	> "$_cvt_rl"
want_broken_none "conventions: ...the same c_header cases laid out otherwise are not" \
	"c_header(num = \"27\")" -- cvt
printf '%s\n' 'c_cycles(num = "00", fn = "ft_toy", oracle_fn = "toy", harness = "diff_toy.c", unit_expr = "length($1)/2")' \
	> "$WORK/cvt/c-piscine/c-piscine-c-91/BUILD.bazel"
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'c_cycles(num = "27", fn = "ft_toy", oracle_fn = "toy", harness = "diff_toy.c", unit_expr = "length($1)")' \
	> "$_cvt_rl"
want_out "conventions: ...and so is a c_cycles whose unit_expr drifted" \
	"the unit_expr of c-piscine-reloaded/c-piscine-reloaded's c_cycles(num = \"27\") differs" -- cvt
# A dict compared as a value (c_diff's readings): one copy over several lines
# with a comma after its last entry, as buildifier writes it, the other on one
# line without, is the same value. The comma before "}" was kept, and the two
# were reported as drifted.
printf '%s\n' 'c_diff(' '    num = "00",' '    fn = "ft_toy",' '    harness = "diff_toy.c",' \
	'    oracle_fn = "toy",' '    readings = {' '        "harness": "diff_toy_readings.c",' \
	'        "oracle_fn": "toy_readings",' '    },' ')' \
	> "$WORK/cvt/c-piscine/c-piscine-c-91/BUILD.bazel"
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'c_diff(num = "27", fn = "ft_toy", harness = "diff_toy.c", oracle_fn = "toy", readings = {"harness": "diff_toy_readings.c", "oracle_fn": "toy_readings"})' \
	> "$_cvt_rl"
want_broken_none "conventions: ...two readings that differ by a closing comma are not" \
	"the readings of" -- cvt
# The layers that replay a generated corpus, which no macro with a num
# emits: Reloaded's ex18 and ex19 had none of the argument corpora C 06 runs
# on the programs they repeat. The toy exercise replays one from a table of
# rows; a twin with none is reported, one that writes the same layer out
# call by call is quiet, and one whose count drifted is reported.
printf '_CORPUS_RUNNERS = [\n    "//tools:argv_check.sh",\n]\n' > "$WORK/cvt/tools/defs.bzl"
printf '%s\n' 'TOY_CORPORA = [' '    ("ex00_argv", "00", "toy_params", "200", ["--expect-reordering"]),' ']' \
	'[' '    hand_test(' '        name = stem + "_diff",' '        layer = "diff",' \
	'        srcs = ["//tools:argv_check.sh"],' \
	'        args = ["--bin", "$(location :ex%s_bin)" % num, "--fn", fn, "--count", count] + judging,' \
	'    )' '    for stem, num, fn, count, judging in TOY_CORPORA' ']' \
	> "$WORK/cvt/c-piscine/c-piscine-c-91/BUILD.bazel"
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' > "$_cvt_rl"
want_out "conventions: ...and a twin with none of its corpus layers" \
	"c-piscine-reloaded/c-piscine-reloaded ex27 lacks a corpus layer //c-piscine/c-piscine-c-91:ex00 has" -- cvt
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'hand_test(' '    name = "ex27_argv_diff",' '    layer = "diff",' '    srcs = ["//tools:argv_check.sh"],' \
	'    args = ["--bin", "$(location :ex27_bin)", "--fn", "toy_params", "--count", "200", "--expect-reordering"],' ')' \
	> "$_cvt_rl"
# "corpus layer", which each of the three reports says ("lacks a corpus
# layer", "has a corpus layer", "the corpus layers of ... cannot be
# compared"): "a corpus layer" let a pair that could not be read pass.
want_broken_none "conventions: ...the same layer written out call by call is not" \
	"corpus layer" -- cvt
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' \
	'hand_test(' '    name = "ex27_argv_diff",' '    layer = "diff",' '    srcs = ["//tools:argv_check.sh"],' \
	'    args = ["--bin", "$(location :ex27_bin)", "--fn", "toy_params", "--count", "100", "--expect-reordering"],' ')' \
	> "$_cvt_rl"
want_out "conventions: ...and one whose corpus count drifted is" \
	"c-piscine-reloaded/c-piscine-reloaded ex27 has a corpus layer //c-piscine/c-piscine-c-91:ex00 has not" -- cvt
# A layer is found by the runner it names as a string: one that names it
# through a name -- a row of its table here, for the plain replay and its
# memory twins alike -- was passed over, so a twin with no layer at all
# compared equal to it, on two empty readings. Each call is named, and a
# hand_test whose srcs are all written out, none a corpus runner, is not.
printf '%s\n' 'TOY_CORPORA = [' '    ("ex00_argv", "00", "//tools:argv_check.sh", "toy_params", "200"),' ']' \
	'[' '    hand_test(' '        name = stem + "_diff",' '        layer = "diff",' \
	'        srcs = [run],' \
	'        args = ["--bin", "$(location :ex%s_bin)" % num, "--fn", fn, "--count", count],' \
	'    )' '    for stem, num, run, fn, count in TOY_CORPORA' ']' \
	'[' '    corpus_memory(' '        stem = stem,' '        runner = run,' \
	'        args = ["--fn", fn, "--count", count],' '        data = [],' \
	'    )' '    for stem, num, run, fn, count in TOY_CORPORA' ']' \
	> "$WORK/cvt/c-piscine/c-piscine-c-91/BUILD.bazel"
printf '%s\n' 'c_twin(num = "27", of = "//c-piscine/c-piscine-c-91:ex00")' > "$_cvt_rl"
want_out "conventions: ...a runner named through a name is reported" \
	"a hand_test call whose srcs" -- cvt_kept
want_out "conventions: ...and so is a corpus_memory's runner" \
	"a corpus_memory call whose runner" -- cat "$WORK/cvt.out"
printf '%s\n' 'hand_test(' '    name = "ex00_toy_check",' '    layer = "output",' \
	'    srcs = ["//tools:toy_check.sh"],' '    args = ["--bin", "$(location :ex00_bin)"],' ')' \
	> "$WORK/cvt/c-piscine/c-piscine-c-91/BUILD.bazel"
want_broken_none "conventions: ...and a hand_test whose srcs are written out is not" \
	"corpus layer" -- cvt
rm -f "$WORK/cvt/tools/defs.bzl"
# A copy but for the name of its prototype.h's include guard, which every
# module spells after itself: ten of Reloaded's folders were, and none was
# seen as a copy, so C 01 ex03's fix had nothing to make it reach ex11.
# Beside it, a pair whose prototypes really differ, which is no copy.
_cvt91=$WORK/cvt/c-piscine/c-piscine-c-91/tests
_cvtrl=$WORK/cvt/c-piscine-reloaded/c-piscine-reloaded/tests
mkdir -p "$_cvt91/ex01" "$_cvtrl/ex28" "$_cvt91/ex02" "$_cvtrl/ex29"
for _f in show.txt cannot.txt; do
	printf 'made up for the selftest, a guard apart: %s\n' "$_f" > "$_cvt91/ex01/$_f"
	cp "$_cvt91/ex01/$_f" "$_cvtrl/ex28/$_f"
	printf 'made up for the selftest, a prototype apart: %s\n' "$_f" > "$_cvt91/ex02/$_f"
	cp "$_cvt91/ex02/$_f" "$_cvtrl/ex29/$_f"
done
printf '#ifndef PROTOTYPE_C_PISCINE_C_91_EX01_H\n# define PROTOTYPE_C_PISCINE_C_91_EX01_H\n\nvoid\tft_toy(void);\n\n#endif\n' \
	> "$_cvt91/ex01/prototype.h"
printf '#ifndef PROTOTYPE_C_PISCINE_RELOADED_EX28_H\n# define PROTOTYPE_C_PISCINE_RELOADED_EX28_H\n\nvoid\tft_toy(void);\n\n#endif\n' \
	> "$_cvtrl/ex28/prototype.h"
printf '#ifndef PROTOTYPE_C_PISCINE_C_91_EX02_H\n# define PROTOTYPE_C_PISCINE_C_91_EX02_H\n\nvoid\tft_toy(void);\n\n#endif\n' \
	> "$_cvt91/ex02/prototype.h"
printf '#ifndef PROTOTYPE_C_PISCINE_RELOADED_EX29_H\n# define PROTOTYPE_C_PISCINE_RELOADED_EX29_H\n\nint\tft_toy(int n);\n\n#endif\n' \
	> "$_cvtrl/ex29/prototype.h"
want_out "conventions: a copy but for its include guard's name is reported" \
	"c-piscine-reloaded/c-piscine-reloaded/tests/ex28 and c-piscine/c-piscine-c-91/tests/ex01" -- cvt
want_broken_none "conventions: ...and a pair whose prototypes differ is not" \
	"c-piscine-reloaded/c-piscine-reloaded/tests/ex29 and" -- cvt
rm -rf "$_cvt91/ex01" "$_cvtrl/ex28" "$_cvt91/ex02" "$_cvtrl/ex29"

# Two readers of one oracle arm under one harness name: C 09 ex00 replays
# C 03's strcmp arms with copies of C 03's readers, and nothing tied the
# copies, so a fix to one (a buffer the capacity cases fit in) could leave
# the other reading the corpus as it was. cvar holds two modules that name
# the arm "toy" and the reader diff_toy.c, one on the call, one in a
# readings dict: the same bytes are quiet, an edited copy is named, and one
# that reads differently under a name of its own is quiet again.
_cva88=$WORK/cvar/c-piscine/c-piscine-c-88
_cva87=$WORK/cvar/c-piscine/c-piscine-c-87
mkdir -p "$WORK/cvar/tools" "$_cva88/tests/ex00" "$_cva87/tests/ex03"
cv_submit "c-piscine/c-piscine-c-88 c-piscine/c-piscine-c-87" > "$WORK/cvar/tools/submit.sh"
printf '%s\n' 'c_diff(num = "00", fn = "ft_toy", harness = "diff_toy.c", oracle_fn = "toy")' \
	> "$_cva88/BUILD.bazel"
printf '%s\n' 'c_diff(' '    num = "03",' '    fn = "ft_toy",' '    harness = "diff_other.c",' \
	'    oracle_fn = "other",' '    readings = {' '        "harness": "diff_toy.c",' \
	'        "oracle_fn": "toy",' '    },' ')' > "$_cva87/BUILD.bazel"
printf '/* made up for the selftest: a reader of the arm toy */\n' > "$_cva88/tests/ex00/diff_toy.c"
cp "$_cva88/tests/ex00/diff_toy.c" "$_cva87/tests/ex03/diff_toy.c"
printf '/* made up for the selftest: a reader of the arm other */\n' > "$_cva87/tests/ex03/diff_other.c"
cvar() { env BUILD_WORKSPACE_DIRECTORY="$WORK/cvar" "$SH" "$TOOLS/conventions.sh"; }
want_broken_none "conventions: two readers of one arm, the same bytes, are quiet" \
	"replay one oracle arm" -- cvar
printf '/* and a line edited in one copy */\n' >> "$_cva87/tests/ex03/diff_toy.c"
want_out "conventions: ...and an edited copy is named" \
	"c-piscine/c-piscine-c-88/tests/ex00/diff_toy.c differs from c-piscine/c-piscine-c-87/tests/ex03/diff_toy.c (both replay toy)" -- cvar
mv "$_cva87/tests/ex03/diff_toy.c" "$_cva87/tests/ex03/diff_toy_own.c"
sed 's/"diff_toy.c"/"diff_toy_own.c"/' "$_cva87/BUILD.bazel" > "$WORK/cvar.build"
mv "$WORK/cvar.build" "$_cva87/BUILD.bazel"
want_broken_none "conventions: ...and one with a name of its own is quiet" \
	"replay one oracle arm" -- cvar

# The cycles row of docs/reference.md names the exercises whose c_cycles
# leaves cases out (max_unit): it named two after six more had one. cvm holds
# a module whose call sets it, under a row that names another exercise, then
# the right one.
mkdir -p "$WORK/cvm/tools" "$WORK/cvm/docs" "$WORK/cvm/c-piscine/c-piscine-c-89"
cv_submit "c-piscine/c-piscine-c-89" > "$WORK/cvm/tools/submit.sh"
printf 'c_cycles(\n    num = "05",\n    fn = "ft_toy",  # a toy\n    max_unit = 1000,\n)\n' \
	> "$WORK/cvm/c-piscine/c-piscine-c-89/BUILD.bazel"
printf '| `cycles` | complete | some cases left out (`c_cycles`'"'"' `max_unit`: C 89 ex04), and said |\n' \
	> "$WORK/cvm/docs/reference.md"
want_out "conventions: a cycles row that misses a max_unit call is named" \
	"BUILD: C 89 ex05" -- env BUILD_WORKSPACE_DIRECTORY="$WORK/cvm" "$SH" "$TOOLS/conventions.sh"
printf '| `cycles` | complete | some cases left out (`c_cycles`'"'"' `max_unit`: C 89 ex05), and said |\n' \
	> "$WORK/cvm/docs/reference.md"
want_broken_none "conventions: ...and one that names it is not" \
	"max_unit disagree" -- env BUILD_WORKSPACE_DIRECTORY="$WORK/cvm" "$SH" "$TOOLS/conventions.sh"
# Piscine Reloaded's calls are held too: its corpora are C 01's, C 03's and
# C 07's, capacity cases included, and the rule read the C modules alone.
mkdir -p "$WORK/cvm/c-piscine-reloaded/c-piscine-reloaded"
cv_submit "c-piscine/c-piscine-c-89 c-piscine-reloaded/c-piscine-reloaded" > "$WORK/cvm/tools/submit.sh"
printf 'c_cycles(\n    num = "16",\n    fn = "ft_toy",\n    max_unit = 1000,\n)\n' \
	> "$WORK/cvm/c-piscine-reloaded/c-piscine-reloaded/BUILD.bazel"
want_out "conventions: a cycles row that misses Piscine Reloaded's max_unit call is named" \
	"BUILD: Piscine Reloaded ex16" -- env BUILD_WORKSPACE_DIRECTORY="$WORK/cvm" "$SH" "$TOOLS/conventions.sh"
printf '| `cycles` | complete | some cases left out (`c_cycles`'"'"' `max_unit`: C 89 ex05, Piscine Reloaded ex16), and said |\n' \
	> "$WORK/cvm/docs/reference.md"
want_broken_none "conventions: ...and one that names it is not" \
	"max_unit disagree" -- env BUILD_WORKSPACE_DIRECTORY="$WORK/cvm" "$SH" "$TOOLS/conventions.sh"

# A fixture test's --owns patterns are its BUILD file's: Rush 00's regen.sh
# passed them again by hand, a second copy of one list. cvo holds such a
# script, then (in a toy of its own) one that runs the test instead.
mkdir -p "$WORK/cvo/tools" "$WORK/cvo/c-piscine/c-piscine-c-90/tests/ex00"
cv_submit "c-piscine/c-piscine-c-90" > "$WORK/cvo/tools/submit.sh"
: > "$WORK/cvo/c-piscine/c-piscine-c-90/BUILD.bazel"
printf '#!/bin/sh\nsh tools/oracle_fixtures.sh --fn toy_fixtures --owns "*.txt" --write\n' \
	> "$WORK/cvo/c-piscine/c-piscine-c-90/tests/ex00/regen.sh"
! st_mine || env BUILD_WORKSPACE_DIRECTORY="$WORK/cvo" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvo.owns" 2>&1
want_out "conventions: a script passing --owns beside a project's tests is named" \
	"c-piscine/c-piscine-c-90/tests/ex00/regen.sh:2:" -- \
	cv_saved "$WORK/cvo.owns"
want_out "conventions: ...told to run the unit's test instead" \
	'bazel run //<project>:<unit>_oracle_fixtures -- --write' -- \
	cv_saved "$WORK/cvo.owns"
rm -rf "$WORK/cvo/c-piscine/c-piscine-c-90/tests/ex00" "$WORK/cvo.owns"
mkdir -p "$WORK/cvo/c-piscine/c-piscine-c-90/tests/ex01"
printf '#!/bin/sh\n# the patterns are the BUILD file'"'"'s --owns\nbazel run //c-piscine/c-piscine-c-90:ex01_oracle_fixtures -- --write\n' \
	> "$WORK/cvo/c-piscine/c-piscine-c-90/tests/ex01/regen.sh"
want_broken_none "conventions: ...and one running the test is not" \
	"passes --owns" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvo" "$SH" "$TOOLS/conventions.sh"

# NO DELIVERABLE CAN BREAK THE BUILD GRAPH: the four rules that keep it so,
# each on a planted violation in a workspace of its own (cv5), and the
# acceptable form beside it where there is one. What the rules cannot see --
# that a macro filters what it is given -- //tools/tests:macro_fixtures_test
# proves on toy exercises.
mkdir -p "$WORK/cv5/tools" "$WORK/cv5/c-piscine/c-piscine-c-96" "$WORK/cv5/c-piscine/c-piscine-c-95"
cv_submit "c-piscine/c-piscine-c-96" > "$WORK/cv5/tools/submit.sh"
{
	printf 'def c_function(num, fn, test, hdrs = None):\n    pass\n'
	printf '_STANDIN_RUNNERS = {\n'
	printf '    "//tools:probe_standin.sh": "checks",\n'
	printf '    "//tools:probe_arg.sh": "checks",\n'
	printf '    "//tools:probe_nogate.sh": "gate",\n'
	printf '}\n'
	# The contract's reader may spell the turn-in directory; a macro that
	# spells it itself decides the layout for the subject.
	printf 'def turnin_dir(num):\n    return "deliverable/ex" + num\n'
	printf 'def c_program(num):\n    """Builds deliverable/exNN, which a docstring may say."""\n'
	printf '    return "deliverable/ex%%s/p.c" %% num\n'
	# A layer's headers go on its runner's include path through _inc_args()
	# alone: the per-header loop anywhere else is reported (rule g).
	printf 'def _inc_args(flag, hdrs):\n    args = []\n    for h in hdrs:\n'
	printf '        args += ["--hdr", "$(location %%s)" %% h]\n    return args\n'
	printf 'def _compile_tests(hdrs):\n    common = []\n    for h in hdrs:\n'
	printf '        common += ["--hdr", "$(location %%s)" %% h]\n    return common\n'
	# Last, so the line numbers the arms above name stay put.
	# What a corpus runner's calls must say of standard error: one row whose
	# runner takes the pair, one whose runner never checks the call made it,
	# one whose runner does not take it at all.
	printf '_RUNNER_CHOICES = {\n'
	printf '    "//tools:probe_choice_ok.sh": [_STDERR_CHOICE],\n'
	printf '    "//tools:probe_choice_joined.sh": [_STDERR_CHOICE],\n'
	printf '    "//tools:probe_choice_nocheck.sh": [_STDERR_CHOICE],\n'
	printf '    "//tools:probe_choice_none.sh": [_STDERR_CHOICE],\n'
	# What a one-project runner's calls must hand it: the subject's sentences
	# (--quotes): a row whose runner checks the call did, one whose does not.
	printf '    "//tools:probe_quotes_ok.sh": [_QUOTES_CHOICE],\n'
	printf '    "//tools:probe_quotes_none.sh": [_QUOTES_CHOICE],\n'
	printf '}\n'
	# A macro that judges one function names its call by that function, not
	# by its library (rule f2): _call(num) in a macro _MEMBER_MACROS lists is
	# reported; _call(call) there, one in its docstring, and one in a macro
	# that judges a whole unit are not.
	printf '_MEMBER_MACROS = ["c_cycles", "c_perf"]\n'
	printf 'def c_cycles(num, unit):\n    fail("c_cycles(%%s): no" %% _call(num))\n'
	printf 'def c_perf(num, unit):\n    """Not _call(num), which names the library."""\n'
	printf '    fail("c_perf(%%s): no" %% _call(call))\n'
	printf 'def c_make(num):\n    fail("c_make(%%s): no" %% _call(num))\n'
	# c_make's list of the commands make_test.sh reads through, one short of
	# the toy make_test.sh's MT_WRAPS below (nice), and without its shell.
	printf '_MAKE_LOOKED_THROUGH = ["env", "exec"]\n'
} > "$WORK/cv5/tools/defs.bzl"
printf '%s\n' '#!/bin/sh' '# Usage: make_test' 'set -u' 'MT_WRAPS="env exec nice"' \
	'MT_SHELLS="sh"' 'echo "$MT_WRAPS $MT_SHELLS"' > "$WORK/cv5/tools/make_test.sh"
# A runner that takes a pinned binutils tool's library folder and proves it
# itself, and one that proves it with rl_binutils_pin.
printf '%s\n' '#!/bin/sh' '# Usage: probe --nm-lib FILE' 'set -u' \
	'case "$1" in --nm-lib) L=$2 ;; esac' '[ -d "${L%/*}" ] || exit 2' \
	> "$WORK/cv5/tools/probe_nmlib_own.sh"
printf '%s\n' '#!/bin/sh' '# Usage: probe --objdump-lib FILE' 'set -u' \
	'case "$1" in --objdump-lib) L=$2 ;; esac' 'rl_binutils_pin objdump od "${L%/*}" --objdump-lib libbfd' \
	> "$WORK/cv5/tools/probe_nmlib_ok.sh"
# A .bzl under tools/ that globs the turn-in itself, with and without saying
# the glob may come back empty.
{
	printf 'def m(ex):\n'
	printf '    a = native.glob(["deliverable/%%s/*.c" %% ex])\n'
	printf '    b = native.glob(["deliverable/%%s/*.h" %% ex], allow_empty = True)\n'
	printf '    return a + b\n'
} > "$WORK/cv5/tools/extra.bzl"
{
	printf 'load("@rules_cc//cc:defs.bzl", "cc_binary")\n'
	printf 'SRCS = glob(["deliverable/ex00/*.c"], allow_empty = True)\n'
	printf 'OK_SRCS = turnin_glob(["deliverable/ex01/*.c"])\n'
	printf 'cc_binary(\n    name = "x",\n    srcs = ["deliverable/ex00/a.c"],\n)\n'
	printf 'c_function(\n    num = "01",\n    fn = "f",\n    test = "t.c",\n    hdrs = ["deliverable/ex01/f.h"],\n)\n'
	printf 'sh_test(\n    name = "y",\n    srcs = ["//tools:probe_standin.sh"],\n    data = [":x"],\n)\n'
	printf 'sh_test(\n    name = "z",\n    srcs = ["//tools:probe_standin.sh"],\n    data = [\n        ":x",\n        "//tools:standin.sh",\n    ],\n)\n'
	printf '[\n    c_function(\n        num = n,\n        fn = "g",\n        test = "t.c",\n        hdrs = ["deliverable/ex02/g.h"],\n    )\n    for n in ["02"]\n]\n'
	# make_test.sh reads make's database with tools/make_db.awk: a test of it
	# written by hand without that file in data, and one with it.
	printf 'sh_test(\n    name = "mk",\n    srcs = ["//tools:make_test.sh"],\n)\n'
	printf 'sh_test(\n    name = "mkdb",\n    srcs = ["//tools:make_test.sh"],\n    data = ["//tools:make_db.awk"],\n)\n'
} > "$WORK/cv5/c-piscine/c-piscine-c-96/BUILD.bazel"
# A project under a course folder that is not in the REMOTES table yet is
# still a project: its BUILD file is held to the same rules.
printf 'genrule(\n    name = "g",\n    outs = ["g.txt"],\n    srcs = ["deliverable/ex00/a.c"],\n    cmd = "cat $< > $@",\n)\n' \
	> "$WORK/cv5/c-piscine/c-piscine-c-95/BUILD.bazel"
# A project that opens with its subject contract, as every one must (c-96
# above calls c_function with none).
mkdir -p "$WORK/cv5/c-piscine/c-piscine-c-94"
printf 'subject(\n    grader = "moulinette",\n    group = False,\n    exercises = {},\n)\n\nc_function(num = "00", fn = "f", test = "t.c")\n' \
	> "$WORK/cv5/c-piscine/c-piscine-c-94/BUILD.bazel"
# ...and names one turn-in file the only way a call site may: turnin_file().
printf 'c_function(num = "01", fn = "g", test = "t.c", hdrs = [turnin_file("01", "g.h")])\n' \
	>> "$WORK/cv5/c-piscine/c-piscine-c-94/BUILD.bazel"
# Two runners with a --bin: one that asks whether the program is a stand-in,
# one that never does.
_cv_loop='while [ $# -gt 0 ]; do\n\tcase "$1" in\n\t\t--bin) BIN=$2; shift 2 ;;\n\tesac\ndone\n'
printf "#!/bin/sh\n# Usage: probe\nset -u\nBIN=\"\"\n${_cv_loop}standin_check probe \"\$BIN\" fail\n" \
	> "$WORK/cv5/tools/probe_standin.sh"
printf "#!/bin/sh\n# Usage: probe\nset -u\nBIN=\"\"\n${_cv_loop}\"\$BIN\"\n" \
	> "$WORK/cv5/tools/probe_nostandin.sh"
# A runner that takes its program as a plain argument -- no --bin for the
# option rule to find -- listed in _STANDIN_RUNNERS as checking, and never
# checking; and one listed as a gate that takes no --gate-bin.
printf '#!/bin/sh\n# Usage: probe PROGRAM\nset -u\n"$1"\n' > "$WORK/cv5/tools/probe_arg.sh"
printf '#!/bin/sh\n# Usage: probe PROGRAM\nset -u\n"$1"\n' > "$WORK/cv5/tools/probe_nogate.sh"
# Corpus runners and the stderr pair: listed and checking (quiet); taking the
# pair with no row; listed and never refusing a call without it; listed and
# not taking it. The refusal is a function of each probe's own, so the
# require scanner reads no PATH command into it.
_cv_choice='while [ $# -gt 0 ]; do\n\tcase "$1" in\n\t\t--stderr-empty) E=1; shift ;;\n\t\t*) shift ;;\n\tesac\ndone\n'
_cv_refuse='rl_stderr_choice() { :; }\nrl_stderr_choice\n'
printf "#!/bin/sh\n# Usage: probe\nset -u\nE=0\n${_cv_choice}${_cv_refuse}" \
	> "$WORK/cv5/tools/probe_choice_ok.sh"
printf "#!/bin/sh\n# Usage: probe\nset -u\nE=0\n${_cv_choice}${_cv_refuse}" \
	> "$WORK/cv5/tools/probe_choice_unlisted.sh"
printf "#!/bin/sh\n# Usage: probe\nset -u\nE=0\n${_cv_choice}" \
	> "$WORK/cv5/tools/probe_choice_nocheck.sh"
printf '#!/bin/sh\n# Usage: probe\nset -u\n' > "$WORK/cv5/tools/probe_choice_none.sh"
# ...and one listed and checking whose loop takes the pair in one arm, as
# rl_stderr_opt is called: it takes the pair, so quiet too.
printf '#!/bin/sh\n# Usage: probe\nset -u\nwhile [ $# -gt 0 ]; do\n\tcase "$1" in\n\t\t--stderr-empty | --stderr-ignored) shift ;;\n\t\t*) shift ;;\n\tesac\ndone\nrl_stderr_choice() { :; }\nrl_stderr_choice\n' \
	> "$WORK/cv5/tools/probe_choice_joined.sh"
# And --quotes: listed and checking (quiet); checking with no row; listed and
# never checking.
_cv_quotes='rl_quotes_ready() { :; }\nrl_quotes_ready tie\n'
printf "#!/bin/sh\n# Usage: probe\nset -u\n${_cv_quotes}" > "$WORK/cv5/tools/probe_quotes_ok.sh"
printf "#!/bin/sh\n# Usage: probe\nset -u\n${_cv_quotes}" > "$WORK/cv5/tools/probe_quotes_unlisted.sh"
printf '#!/bin/sh\n# Usage: probe\nset -u\n' > "$WORK/cv5/tools/probe_quotes_none.sh"
# ONE run of the checker over cv5, read by every arm below: each arm is a
# question about the same report, and a run walks the whole workspace (0.2s
# idle, seconds on a loaded box), so sixteen runs cost sixteen times one and
# checked nothing more. It is read with its status (tools/tests/selftest_lib.sh,
# A SAVED RUN OF THE CONVENTIONS CHECK).
# Run only where its arms run, as cv's is.
! st_mine || env BUILD_WORKSPACE_DIRECTORY="$WORK/cv5" "$SH" "$TOOLS/conventions.sh" > "$WORK/cv5.out" 2>&1
cv5_report() { cv_saved "$WORK/cv5.out"; }
# cv5_rule HEADING: only the report of the rule whose FAIL line holds HEADING
# -- where two rules can name the same line, an arm about one of them.
cv5_rule() { cvi_rule cv5 "$1"; }
want_out "conventions: a cc_binary where a student's code can reach is reported" \
	'c-piscine/c-piscine-c-96/BUILD.bazel builds with a cc_binary, cc_library or genrule' -- cv5_report
want_out "conventions: ...so is a genrule, in a project not in REMOTES yet" \
	'c-piscine/c-piscine-c-95/BUILD.bazel builds with a cc_binary, cc_library or genrule' -- cv5_report
want_out "conventions: a BUILD file's bare glob() of a turn-in is reported" \
	'c-piscine/c-piscine-c-96/BUILD.bazel globs a turn-in with glob(), not turnin_glob()' -- cv5_report
want_broken_none "conventions: ...and its turnin_glob() is not" \
	'line 3' -- cv5_rule 'globs a turn-in with glob(), not turnin_glob()'
want_out "conventions: a tools .bzl glob that may not come back empty is reported" \
	'tools/extra.bzl globs a turn-in without allow_empty = True' -- cv5_report
want_broken_none "conventions: ...and one with allow_empty = True is not" \
	'line 3' -- cv5_rule 'globs a turn-in without allow_empty = True'
want_out "conventions: a literal turn-in path outside a macro is reported" \
	'deliverable/ex00/a.c' -- cv5_report
want_broken_none "conventions: ...one handed to a defs.bzl macro is not" \
	'deliverable/ex01/f.h' -- cv5_rule 'names a turn-in file outside a tools/defs.bzl macro'
want_broken_none "conventions: ...nor one in a list comprehension of macro calls" \
	'deliverable/ex02/g.h' -- cv5_rule 'names a turn-in file outside a tools/defs.bzl macro'
# ...but ANY turn-in path spelled in a project's BUILD file decides the layout
# a second time, a macro's argument too: turnin_file() builds it from the
# contract instead, and fails when the contract does not allow the file.
want_out "conventions: a turn-in path spelled at a call site is reported" \
	'c-piscine/c-piscine-c-96/BUILD.bazel spells a turn-in path at a call site' -- cv5_report
want_out "conventions: ...a macro's argument too" \
	'deliverable/ex01/f.h' -- cv5_rule 'spells a turn-in path at a call site'
want_broken_none "conventions: ...never a turnin_file()" \
	'c-piscine-c-94' -- cv5_rule 'spells a turn-in path at a call site'
want_out "conventions: a per-header include loop outside _inc_args() is reported" \
	'(_compile_tests)' -- cv5_rule 'outside _inc_args()'
want_broken_none "conventions: ...the one inside it is not" \
	'(_inc_args)' -- cv5_rule 'outside _inc_args()'
want_out "conventions: a member macro naming its call by its library is reported" \
	'(c_cycles)' -- cv5_rule "names a member macro's call by its library"
want_broken_none "conventions: ...one naming the function, or a docstring, is not" \
	'(c_perf)' -- cv5_rule "names a member macro's call by its library"
want_broken_none "conventions: ...nor a macro that judges a whole unit" \
	'(c_make)' -- cv5_rule "names a member macro's call by its library"
want_out "conventions: a listed runner taking its program as an argument, unchecked" \
	'tools/probe_arg.sh is listed in _STANDIN_RUNNERS as checking for a stand-in, and never does' -- cv5_report
want_out "conventions: ...or one a probe cannot hand a stand-in" \
	'tools/probe_arg.sh is listed in _STANDIN_RUNNERS as checking for a stand-in, and takes its program by no --bin or --student-bin' -- cv5_report
want_broken_none "conventions: ...a listed one that does check is not" \
	'tools/probe_standin.sh is listed in _STANDIN_RUNNERS' -- cv5_report
want_out "conventions: a listed gate runner taking no --gate-bin is reported" \
	'tools/probe_nogate.sh is listed in _STANDIN_RUNNERS as running a program only as its gate' -- cv5_report
want_out "conventions: a runner that never checks for a stand-in is reported" \
	'tools/probe_nostandin.sh runs a built program and never asks' -- cv5_report
want_broken_none "conventions: ...one that does is not" \
	'tools/probe_standin.sh runs a built program' -- cv5_report
want_out "conventions: a hand-written test without standin.sh is reported" \
	'line 14: probe_standin.sh' -- cv5_report
want_broken_none "conventions: ...one that lists it is not" \
	'line 19: probe_standin.sh' -- cv5_report
want_out "conventions: a hand-written test of make_test.sh without make_db.awk is reported" \
	'line 36: make_test.sh' -- cv5_rule 'whose runner reads tools/make_db.awk, without it in data'
want_broken_none "conventions: ...one that lists it is not" \
	'line 40: make_test.sh' -- cv5_rule 'whose runner reads tools/make_db.awk, without it in data'
want_out "conventions: a macro called before any subject() is reported" \
	'c-piscine/c-piscine-c-96/BUILD.bazel calls c_function (line 8) before any subject()' -- cv5_report
want_broken_none "conventions: ...one called after it is not" \
	'c-piscine/c-piscine-c-94/BUILD.bazel calls' -- cv5_report
want_out "conventions: a macro spelling a turn-in directory itself is reported" \
	'line 12 (c_program)' -- cv5_report
want_broken_none "conventions: ...the contract's reader is not" '(turnin_dir)' -- cv5_report
want_broken_none "conventions: ...nor a docstring saying where things go" 'line 11' -- cv5_report
want_out "conventions: an unreadable _STANDIN_RUNNERS table is reported" \
	'has no _STANDIN_RUNNERS table this can read' -- \
	cv_saved "$WORK/cv4.out"
want_out "conventions: a runner taking the stderr pair with no row is reported" \
	'tools/probe_choice_unlisted.sh takes --stderr-empty, and _RUNNER_CHOICES has no row for it' -- cv5_report
want_out "conventions: ...one listed that never refuses a call without it" \
	'tools/probe_choice_nocheck.sh takes --stderr-empty, and never calls rl_stderr_choice' -- cv5_report
want_out "conventions: ...a row for a runner that does not take it" \
	'_RUNNER_CHOICES names tools/probe_choice_none.sh, which takes no --stderr-empty' -- cv5_report
want_broken_none "conventions: ...and a listed runner that checks is not" \
	'probe_choice_ok.sh' -- cv5_rule "standard-error choice and _RUNNER_CHOICES disagree"
want_broken_none "conventions: ...nor one taking the pair in one arm" \
	'probe_choice_joined.sh' -- cv5_rule "standard-error choice and _RUNNER_CHOICES disagree"
want_out "conventions: an unreadable _RUNNER_CHOICES table is reported" \
	'has no _RUNNER_CHOICES table this can read' -- \
	cv_saved "$WORK/cv4.out"
want_out "conventions: a runner that checks its --quotes with no row is reported" \
	'tools/probe_quotes_unlisted.sh calls rl_quotes_ready, and _RUNNER_CHOICES gives it no _QUOTES_CHOICE' -- cv5_report
want_out "conventions: ...a row for a runner that never checks them" \
	'_RUNNER_CHOICES gives tools/probe_quotes_none.sh _QUOTES_CHOICE, and it never calls rl_quotes_ready' -- cv5_report
want_broken_none "conventions: ...and a listed runner that checks is not" \
	'probe_quotes_ok.sh' -- cv5_rule "a runner's --quotes and _RUNNER_CHOICES disagree"
# make_test.sh reads through the commands that only run another, and c_make
# refuses them by a list of its own: the two lists are held equal. A shell,
# read through only given -c, is in neither.
want_out "conventions: c_make's list of looked-through commands drifting from make_test.sh's is reported" \
	'+nice' -- cv5_rule "_MAKE_LOOKED_THROUGH and make_test.sh's MT_WRAPS differ"
want_broken_none "conventions: ...never a shell, read through only given -c" \
	'+sh' -- cv5_rule "_MAKE_LOOKED_THROUGH and make_test.sh's MT_WRAPS differ"
# A runner that takes --nm-lib or --objdump-lib proves the tool's libraries
# with rl_binutils_pin: three runners kept a copy of that proof, and the
# copies drifted (a second --nm-lib folder refused, one exporting its path).
want_out "conventions: a runner taking --nm-lib that never calls rl_binutils_pin is reported" \
	'tools/probe_nmlib_own.sh' -- cv5_rule "takes a binutils tool's library and never proves it with rl_binutils_pin"
want_broken_none "conventions: ...never one that calls it" \
	'probe_nmlib_ok.sh' -- cv5_rule "takes a binutils tool's library and never proves it with rl_binutils_pin"

# WHO GRADES A PROJECT is its subject() contract's, and the runners word it
# through rl_at (conventions rule N, finding 145). Two halves, over cvg:
#
#   * a harness program under tools/ names no grader in its code, in any
#     language a test runs -- the rule once read tools/*.sh alone, so a C or
#     Python helper printing "a KO at the Moulinette" passed -- while a
#     comment or a docstring still may;
#   * a project graded at a defense names the Moulinette nowhere in its
#     tests/. Which projects those are is read from the subject() call's
#     `grader`: the rule once grepped the BUILD file for the text
#     'grader = "defense"', so a comment quoting another project's contract
#     made a Moulinette project a defense one, and a contract it could not
#     read made a defense project nothing at all.
mkdir -p "$WORK/cvg/tools"
for _m in c-90 c-91 c-92 c-93; do mkdir -p "$WORK/cvg/c-piscine/c-piscine-$_m/tests/ex00"; done
cv_submit "c-piscine/c-piscine-c-90 c-piscine/c-piscine-c-91 c-piscine/c-piscine-c-92 c-piscine/c-piscine-c-93" \
	> "$WORK/cvg/tools/submit.sh"
for _m in c-90 c-91 c-92 c-93; do
	printf 'Would the Moulinette take this?\n' > "$WORK/cvg/c-piscine/c-piscine-$_m/tests/ex00/clues.tsv"
done
printf 'subject(\n    grader = "defense",\n    group = True,\n    exercises = {},\n)\n' \
	> "$WORK/cvg/c-piscine/c-piscine-c-93/BUILD.bazel"
printf 'subject(grader = "defense", group = True, exercises = {})\n' \
	> "$WORK/cvg/c-piscine/c-piscine-c-90/BUILD.bazel"
printf 'GRADER = "defense"\n\nsubject(\n    grader = GRADER,\n    group = True,\n    exercises = {},\n)\n' \
	> "$WORK/cvg/c-piscine/c-piscine-c-91/BUILD.bazel"
{
	printf '# Unlike a rush, whose contract says subject(grader = "defense"), this\n'
	printf '# project is graded by a program.\n'
	printf 'subject(\n    grader = "moulinette",\n    group = False,\n    exercises = {},\n)\n'
} > "$WORK/cvg/c-piscine/c-piscine-c-92/BUILD.bazel"
printf '/* What the Moulinette would print. */\n#include <stdio.h>\nint main(void) { puts("a KO at the Moulinette"); return (0); }\n' \
	> "$WORK/cvg/tools/probe_grader.c"
printf '/*\n * as the Moulinette compiles it\n */\nint g_x; // the Moulinette too\n' \
	> "$WORK/cvg/tools/probe_grader_ok.h"
printf '"""Named after the Moulinette."""\nprint("a KO at the Moulinette")\n' \
	> "$WORK/cvg/tools/probe_grader.py"
# A FILE THAT IS A SYMBOLIC LINK, as every file of a runfiles tree is under
# `bazel test`: a rule that reads one through a recursive grep that skips
# links (GNU grep -r does not follow a link it meets on the way down) sees
# nothing there and passes. c-94 is graded at a defense, and its clues.tsv,
# naming the Moulinette, is a link to a file outside the module; its
# ex00_x_output is raised to strict, and two texts name it at robust: one a
# file, one a link -- and a third names it in capitals, once at a level it
# does not sit at, reported, and once at its own, not. And the fixture's
# tools/conventions.sh, read in place of the real one by the rule that
# refuses such a grep there, holds four greps: a recursive one, in two
# spellings, reported; one that follows links, and a sort -r after one,
# not. It is gone before any later run.
mkdir -p "$WORK/cvg/c-piscine/c-piscine-c-94/tests/ex00" "$WORK/cvg_link"
printf 'subject(grader = "defense", group = True, exercises = {})\n' \
	> "$WORK/cvg/c-piscine/c-piscine-c-94/BUILD.bazel"
printf 'Would the Moulinette take this?\n' > "$WORK/cvg_link/clues.tsv"
ln -s "$WORK/cvg_link/clues.tsv" "$WORK/cvg/c-piscine/c-piscine-c-94/tests/ex00/clues.tsv"
printf '_RAISED = {\n    "c-piscine/c-piscine-c-94:ex00_x_output": 2,\n}\n' > "$WORK/cvg/tools/defs.bzl"
printf 'A case of ex00_x_output, at robust.\n' > "$WORK/cvg/c-piscine/c-piscine-c-94/tests/ex00/plain.txt"
printf 'A case of ex00_x_output, at robust.\n' > "$WORK/cvg_link/linked.txt"
ln -s "$WORK/cvg_link/linked.txt" "$WORK/cvg/c-piscine/c-piscine-c-94/tests/ex00/linked.txt"
printf 'Ex00_X_output, at Robust.\nEX00_x_output, at Strict.\n' > "$WORK/cvg/c-piscine/c-piscine-c-94/tests/ex00/cased.txt"
printf '#!/bin/sh\na=$(grep -rn x .)\nb=$(grep -l --recursive x .)\nc=$(grep -Rn x .)\nd=$(grep -n x f | sort -r)\n' \
	> "$WORK/cvg/tools/conventions.sh"
# One run, read by every arm below (see cv5 above for why), and made only
# where they run: unguarded, every shard paid for it.
! st_mine || env BUILD_WORKSPACE_DIRECTORY="$WORK/cvg" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvg.out" 2>&1
rm -f "$WORK/cvg/tools/conventions.sh"
cvg_report() { cv_saved "$WORK/cvg.out"; }
cvg_rule() { cvi_rule cvg "$1"; }
want_out "conventions: a harness C program naming the grader is reported" \
	'tools/probe_grader.c:3:' -- cvg_rule 'a runner names the grader'
want_broken_none "conventions: ...never where a comment does" \
	'probe_grader.c:1:' -- cvg_rule 'a runner names the grader'
want_broken_none "conventions: ...nor a header's comments of both kinds" \
	'probe_grader_ok.h' -- cvg_rule 'a runner names the grader'
want_out "conventions: ...and in Python" \
	'tools/probe_grader.py:2:' -- cvg_rule 'a runner names the grader'
want_broken_none "conventions: ...whose docstring may" \
	'probe_grader.py:1:' -- cvg_rule 'a runner names the grader'
want_out "conventions: a defense project's tests/ naming the Moulinette is reported" \
	'c-piscine/c-piscine-c-93 is graded at a defense' -- cvg_report
want_out "conventions: ...its contract written on one line too" \
	'c-piscine/c-piscine-c-90 is graded at a defense' -- cvg_report
want_broken_none "conventions: ...never one whose comment quotes a defense contract" \
	'c-piscine-c-92 is graded' -- cvg_report
want_out "conventions: a grader that is not a literal is reported" \
	"c-piscine/c-piscine-c-91/BUILD.bazel's subject() gives no grader this check can read" -- cvg_report
want_out "conventions: ...and one whose tests/ says it in a file that is a link" \
	'c-piscine/c-piscine-c-94 is graded at a defense' -- cvg_report
want_out "conventions: a raised target named at another level is reported" \
	'c-piscine/c-piscine-c-94/tests/ex00/plain.txt:1:ex00_x_output, at robust (ex00_x_output sits at strict)' -- \
	cvg_rule 'a text names a raised target at a level it does not sit at'
want_out "conventions: ...in a file that is a link too" \
	'c-piscine/c-piscine-c-94/tests/ex00/linked.txt:1:ex00_x_output, at robust' -- \
	cvg_rule 'a text names a raised target at a level it does not sit at'
want_out "conventions: ...and named in capitals" \
	'c-piscine/c-piscine-c-94/tests/ex00/cased.txt:1:Ex00_X_output, at Robust (ex00_x_output sits at strict)' -- \
	cvg_rule 'a text names a raised target at a level it does not sit at'
want_broken_none "conventions: ...never in capitals at its own level" \
	'cased.txt:2:' -- cvg_rule 'a text names a raised target at a level it does not sit at'
want_out "conventions: a grep of its own that skips symlinks is reported" \
	'tools/conventions.sh:2:' -- cvg_rule 'tools/conventions.sh walks a tree with a grep that skips symlinks'
want_out "conventions: ...spelt long too" \
	'tools/conventions.sh:3:' -- cvg_rule 'tools/conventions.sh walks a tree with a grep that skips symlinks'
for _cvg_l in 4 5; do
	want_broken_none "conventions: ...never one that follows them, nor a sort -r (line $_cvg_l)" \
		"tools/conventions.sh:$_cvg_l:" -- cvg_rule 'tools/conventions.sh walks a tree with a grep that skips symlinks'
done

# An //oracle arm that writes a project's fixtures is passed as --fn by a test
# running oracle_fixtures.sh, or the files it writes are compared by nothing.
# An arm is the name as a string literal in a file of the oracle's source; a
# comment naming one is none. A tree whose oracle source names no such arm at
# all is the search itself broken, reported as such. Held is the value after
# "--fn" in such a test's args, on its line or the next, or the fn of an
# oracle_fixtures() call; the name quoted anywhere else in the file -- a
# comment, another argument -- is not held.
mkdir -p "$WORK/cvo/tools" "$WORK/cvo/oracle/src" "$WORK/cvo/c-piscine/c-piscine-c-89" \
	"$WORK/cvo2/tools" "$WORK/cvo2/oracle/src" "$WORK/cvo2/c-piscine/c-piscine-c-89"
cv_submit "c-piscine/c-piscine-c-89" > "$WORK/cvo/tools/submit.sh"
cv_submit "c-piscine/c-piscine-c-89" > "$WORK/cvo2/tools/submit.sh"
{
	printf 'pub fn generate(name: &str) {\n'
	printf '    // "comment_fixtures" was an arm once\n'
	printf '    match name {\n'
	printf '        "held_fixtures" => held(),\n'
	printf '        "mac_fixtures" => mac(),\n'
	printf '        "next_fixtures" => next(),\n'
	printf '        "toy_fixtures" => toy(),\n'
	printf '        "yy_fixtures" => yy(),\n'
	printf '        "zz_fixtures" => zz(),\n'
	printf '        _ => {}\n    }\n}\n'
} > "$WORK/cvo/oracle/src/toy.rs"
printf 'pub fn generate() {}\n' > "$WORK/cvo2/oracle/src/toy.rs"
{
	printf '# runs tools/oracle_fixtures.sh; the "zz_fixtures" arm is TODO\n'
	printf 'hand_test(\n    name = "ex00_oracle_fixtures",\n    srcs = ["//tools:oracle_fixtures.sh"],\n    args = ["--fn", "held_fixtures"],\n)\n\n'
	printf 'hand_test(\n    name = "ex01_oracle_fixtures",\n    srcs = ["//tools:oracle_fixtures.sh"],\n'
	printf '    args = [\n        "--fn",\n        "next_fixtures",\n        "--owns",\n        "yy_fixtures",\n    ],\n)\n\n'
	printf 'oracle_fixtures(\n    name = "ex02_oracle_fixtures",\n    fn = "mac_fixtures",\n'
	printf '    dir = "tests/ex02/",\n    in_dir_of = "a.txt",\n    owns = ["*.txt"],\n)\n'
} > "$WORK/cvo/c-piscine/c-piscine-c-89/BUILD.bazel"
: > "$WORK/cvo2/c-piscine/c-piscine-c-89/BUILD.bazel"
# Run only where their arms run, as cv's is.
if st_mine; then
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvo" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvo.out" 2>&1
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvo2" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvo2.out" 2>&1
fi
cvo_rule() { cvi_rule "$2" "$1"; }  # cvo_rule HEADLINE TOY
want_out "conventions: an oracle fixtures arm no test compares is reported" \
	'toy_fixtures (oracle/src/toy.rs)' -- cvo_rule 'writes fixtures that no test compares' cvo
want_out "conventions: ...advising the unit's fixtures test" \
	"Declare the project's fixtures test with oracle_fixtures() from" -- \
	cvo_rule 'writes fixtures that no test compares' cvo
want_broken_none "conventions: ...never one a test passes as --fn" \
	'held_fixtures' -- cvo_rule 'writes fixtures that no test compares' cvo
want_broken_none "conventions: ...nor a name in a comment" \
	'comment_fixtures' -- cvo_rule 'writes fixtures that no test compares' cvo
want_broken_none "conventions: ...nor an --fn whose value is on the next line" \
	'next_fixtures' -- cvo_rule 'writes fixtures that no test compares' cvo
want_broken_none "conventions: ...nor the fn of an oracle_fixtures() call" \
	'mac_fixtures' -- cvo_rule 'writes fixtures that no test compares' cvo
want_out "conventions: ...but one only a BUILD comment quotes is reported" \
	'zz_fixtures (oracle/src/toy.rs)' -- cvo_rule 'writes fixtures that no test compares' cvo
want_out "conventions: ...and one only another argument quotes" \
	'yy_fixtures (oracle/src/toy.rs)' -- cvo_rule 'writes fixtures that no test compares' cvo
want_out "conventions: an oracle with no fixtures arm is the search's fault" \
	'no //oracle arm whose name ends in _fixtures was found' -- cvo_rule 'no //oracle arm whose name' cvo2

