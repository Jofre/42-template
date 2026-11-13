# ---------------------------------------- conventions: a selftest read whole
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A selftest that sources its sections, one file each (selftest.sh, THE
# SECTIONS), is read by the rules on what a selftest does as the program the
# driver and its files make together, as a shard runs it: a helper of the
# driver called in a section, a fixture PATH built in one section and run in
# another, a tree named before the first section, each reported where its
# line is, in the file that holds it (conventions.sh, THE SELFTEST, READ
# WHOLE). Read apart, the driver holds no arm and a section no helper. The
# toy's driver and files are written with @D@ for each $, so the rules
# reading this file see no command of theirs.
mkdir -p "$WORK/cvst/tools/tests/selftest_sections" "$WORK/cvst/m"
cv_submit m > "$WORK/cvst/tools/submit.sh"
: > "$WORK/cvst/m/BUILD.bazel"
stw() {  # stw FILE LINE... -- FILE of the toy, its lines with @D@ for $
	_stw_f=$1
	shift
	printf '%s\n' "$@" | sed 's/@D@/$/g' > "$WORK/cvst/$_stw_f"
}
stw tools/probe_fx.sh '#!/bin/sh' 'set -u' 'require() {' \
	'	for _t in "@D@@"; do' \
	'		command -v "@D@_t" > /dev/null 2>&1 && continue' \
	'		echo "probe_fx.sh: required command '"'"'@D@_t'"'"' is not on PATH" >&2' \
	'		exit 2' '	done' '}' 'require rm' 'rm -f "@D@{TMPDIR:-/tmp}/probe_fx.none"'
# The driver: its helpers, one of the user's knobs unset and the others
# left with its git settings, a tree named before the first section, the
# lines that source its sections (one of each wrong shape too), a section
# line of its own, and want_red after it, printing its verdict (line 25);
# then the line that sources the arm helpers' library, which this tree
# does not have, and a call of a helper only that library would define.
stw tools/tests/selftest.sh '#!/bin/sh' 'set -u' 'require() {' \
	'	for _t in "@D@@"; do' \
	'		command -v "@D@_t" > /dev/null 2>&1 && continue' \
	'		echo "selftest.sh: required command '"'"'@D@_t'"'"' is not on PATH" >&2' \
	'		exit 2' '	done' '}' 'require dirname mkdir mktemp' 'unset SUBMIT_GATE' \
	'WORK=@D@(mktemp -d)' 'want_green() { "@D@@"; }' 'mkdir -p "@D@WORK/stpre"' \
	'ST_PARTS=@D@(cd "@D@(dirname "@D@0")" && pwd)/selftest_sections' \
	'. "@D@ST_PARTS/a.sh"' '. "@D@ST_PARTS/b.sh"' '. "@D@ST_PARTS/d.sh"' \
	'. "@D@ST_PARTS/e.sh"' '. "@D@ST_PARTS/gone.sh"' '. "@D@{ST_PARTS}/c.sh"' \
	'. "@D@ST_PARTS/e.sh"' '# ----- tail' 'want_red() {' \
	'	printf '"'"'  %-52s %s\n'"'"' "@D@1" "ok (red, as required)"' '}' \
	'. "@D@TOOLS/tests/selftest_lib.sh"' 'want_fromlib "tail: a helper of a library not there" -- true'
# Section a: a fixture PATH (line 4), an arm calling a helper nothing
# defines and one calling the driver's, a write into the driver's tree
# (line 9), a toy exercise and a record, a call of od, a helper that runs
# make_test.sh with the pinned nm, a cd shellcheck warns of (line 14), a
# toy check script run with a plain sh (15) and by an arm (16, over two
# lines), and one run through "$SH" (18).
stw tools/tests/selftest_sections/a.sh '# ----- a' '# shellcheck shell=sh' \
	'mkdir -p "@D@WORK/stfx"' \
	'for _t in sh; do' \
	'	ln -sf "@D@(command -v "@D@_t")" "@D@WORK/stfx/@D@_t"' \
	'done' \
	'want_nothing "a: an arm whose helper is defined nowhere" -- true' \
	'want_green "a: an arm calling the driver'"'"'s helper" -- true' \
	': > "@D@WORK/stpre/x"' \
	'mkdir -p "@D@WORK/sttoy/m/tests/ex01"' \
	'printf '"'"'a\n'"'"' > "@D@WORK/strec/TODO.md"' \
	'od -c /dev/null > /dev/null' \
	'xnm() { "@D@SH" "@D@TOOLS/make_test.sh" --nm "@D@NM" "@D@@"; }' \
	'cd "@D@WORK"' \
	'SHELL_CHECK_LIB="@D@TOOLS/shell_check.sh" sh "@D@WORK/stck/check.sh"' \
	'want_green "a: a toy check script run with a plain sh" -- \' \
	'	env -u NO_SKIP SHELL_CHECK_LIB="@D@TOOLS/shell_check.sh" sh "@D@WORK/stck/check.sh"' \
	'SHELL_CHECK_LIB="@D@TOOLS/shell_check.sh" "@D@SH" "@D@WORK/stck/check.sh"'
# Section b: the arm that sets PATH to a's fixture (line 3), the same toy
# and record again (4, 5), need() with no definition, a trap that does not
# exit (7), valgrind with its door open (8), a compiler from PATH (9), \t in
# a bracket (10), git with nothing unset (11), a's helper without --nm-lib
# (12), and want_red's verdict printed by hand, on one line (13) and over
# two (14), then named in a comment (16).
stw tools/tests/selftest_sections/b.sh '# ----- b' '# shellcheck shell=sh' \
	'want_green "b: a fixture PATH" -- env PATH="@D@WORK/stfx" "@D@SH" "@D@TOOLS/probe_fx.sh"' \
	'mkdir -p "@D@WORK/sttoy/m/tests/ex01"' \
	'printf '"'"'b\n'"'"' > "@D@WORK/strec/TODO.md"' \
	'while [ @D@# -gt 0 ]; do case "@D@1" in --x) need "@D@1" "@D@#"; shift 2 ;; *) shift ;; esac; done' \
	'trap '"'"'rm -f "@D@WORK/x"'"'"' INT' \
	'valgrind --tool=memcheck true' \
	'CC=@D@{CC:-cc}' \
	'grep '"'"'^[ \t]*#'"'"' /dev/null' \
	'git init -q "@D@WORK/stgit"' \
	'xnm --symbols x' \
	'printf '"'"'  %-52s %s\n'"'"' "b: a floor" "ok (red, as required)"' \
	'printf '"'"'  %-52s %s\n'"'"' "b: another" \' \
	'	"ok (red, as required)"' \
	'# printf "ok (red, as required)", in a comment'
# The shapes the rule on the sections refuses: c.sh, sourced only by the
# other spelling and opening with no section line; d.sh, holding two
# sections and the tally; an orphan nothing sources; e.sh, sourced twice.
stw tools/tests/selftest_sections/c.sh 'echo c'
stw tools/tests/selftest_sections/d.sh '# ----- d' '# shellcheck shell=sh' ': d' '# ----- d2' '# ===== the tally'
stw tools/tests/selftest_sections/e.sh '# ----- e' '# shellcheck shell=sh' ': e'
stw tools/tests/selftest_sections/orphan.sh '# ----- orphan' '# shellcheck shell=sh' ': orphan'
if st_mine; then
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvst" "$SH" "$TOOLS/conventions.sh" \
		--shellcheck "$SHELLCHECK" > "$WORK/cvst.out" 2>&1
fi
want_out "conventions: a selftest's sections are read with its driver" \
	'tools/tests/selftest.sh calls want_nothing() and never defines it' -- \
	cvi_rule cvst 'calls want_nothing()'
want_broken_none "conventions: ...so a section calls the driver's helpers" \
	'calls want_green()' -- cvi_rule cvst 'calls want_green()'
want_out "conventions: ...and a helper of a library the driver sources, not there" \
	'tools/tests/selftest.sh calls want_fromlib() and never defines it' -- \
	cvi_rule cvst 'calls want_fromlib()'
want_out "conventions: ...a fixture PATH built in one section, run in another" \
	"tools/tests/selftest_sections/a.sh:4's fixture PATH (\$WORK/stfx) is missing what tools/probe_fx.sh requires" -- \
	cvi_rule cvst 'fixture PATH'
want_out "conventions: ...a toy exercise named in two section files" \
	'[a] (tools/tests/selftest_sections/a.sh:10) [b] (tools/tests/selftest_sections/b.sh:4)' -- \
	cvi_rule cvst 'names one toy exercise in two sections'
want_out "conventions: ...a section writing into the driver's tree" \
	'"$WORK/stpre": [a] (tools/tests/selftest_sections/a.sh:9)' -- \
	cvi_rule cvst 'writes from a section into a fixture tree made before the first section'
want_out "conventions: ...a record written by two section files" \
	'written at lines tools/tests/selftest_sections/a.sh:11 tools/tests/selftest_sections/b.sh:5' -- \
	cvi_rule cvst 'file from two statements'
want_out "conventions: ...need() called in a section" \
	'tools/tests/selftest.sh calls need() and never defines it' -- cvi_rule cvst 'calls need()'
want_out "conventions: ...a section's commands in the driver's require list" \
	"tools/tests/selftest.sh's require list does not match what it calls" -- \
	cvi_rule cvst 'require list does not match'
want_out "conventions: ...a section's trap" \
	'    tools/tests/selftest_sections/b.sh:7: trap' -- \
	cvi_rule cvst 'a signal trap cleans up'
want_out "conventions: ...a section's valgrind" \
	'    tools/tests/selftest_sections/b.sh:8: valgrind without --vgdb=no' -- \
	cvi_rule cvst 'runs valgrind with its gdb door open'
want_out "conventions: ...a section's compiler from PATH" \
	'    tools/tests/selftest_sections/b.sh:9: CC=${CC:-cc}' -- \
	cvi_rule cvst 'a runner compiles with a compiler from PATH'
want_out "conventions: ...a section's tab in a bracket" \
	'    tools/tests/selftest_sections/b.sh:10: grep' -- \
	cvi_rule cvst 'writes a tab as'
want_out "conventions: ...a section's git, under the driver's unset" \
	'tools/tests/selftest.sh runs git (tools/tests/selftest_sections/b.sh:11)' -- \
	cvi_rule cvst 'under what the environment says of git'
want_out "conventions: ...and under the host's git configuration" \
	"tools/tests/selftest.sh runs git (tools/tests/selftest_sections/b.sh:11) under the host's configuration" -- \
	cvi_rule cvst "under the host's configuration"
want_out "conventions: a driver that leaves its sections the user's settings is reported" \
	"tools/tests/selftest.sh sources its sections (line 16) under the user's settings" -- \
	cvi_rule cvst "under the user's settings"
want_out "conventions: ...naming the knob it leaves, not the one it unsets" \
	'Not unset before it: CLUE_MODE' -- cvi_rule cvst "under the user's settings"
want_out "conventions: ...and ILP32_CC, the compiler a hand run can export" \
	'Not unset before it: CLUE_MODE ILP32_CC.' -- cvi_rule cvst "under the user's settings"
want_out "conventions: ...a helper of one section called in another" \
	'    tools/tests/selftest_sections/b.sh:12' -- \
	cvi_rule cvst 'pinned nm without --nm-lib'
want_out "conventions: ...and shellcheck reads each section's file" \
	'tools/tests/selftest_sections/a.sh:14:' -- cvi_rule cvst 'shellcheck reports'
want_out "conventions: a section running a toy check script with a plain sh" \
	'tools/tests/selftest_sections/a.sh:15: SHELL_CHECK_LIB=' -- \
	cvi_rule cvst 'runs a toy check script with a plain sh'
want_out "conventions: ...and an arm running one, where it starts" \
	'tools/tests/selftest_sections/a.sh:16: want_green' -- \
	cvi_rule cvst 'runs a toy check script with a plain sh'
want_broken_none "conventions: ...never one run through \"\$SH\"" \
	'a.sh:18' -- cvi_rule cvst 'runs a toy check script with a plain sh'
cvst_verdict() { cvi_rule cvst "prints want_red's verdict outside want_red"; }
want_out "conventions: a section printing want_red's verdict is reported" \
	'    tools/tests/selftest_sections/b.sh:13' -- cvst_verdict
want_out "conventions: ...and one over two lines, where it starts" \
	'    tools/tests/selftest_sections/b.sh:14' -- cvst_verdict
for _l in 'b.sh:15:its second line' 'b.sh:16:a comment' 'selftest.sh:25:want_red itself'; do
	want_broken_none "conventions: ...never ${_l##*:} (${_l%:*})" "${_l%:*}" -- cvst_verdict
done
# The rule on the sections themselves.
want_out "conventions: a section file that is not there is named" \
	'tools/tests/selftest.sh:20: sources tools/tests/selftest_sections/gone.sh, which is not there or is empty' -- \
	cvi_rule cvst 'does not source its sections one file each'
want_out "conventions: ...and a section sourced another way" \
	'tools/tests/selftest.sh:21: sources a section another way' -- \
	cvi_rule cvst 'does not source its sections one file each'
want_out "conventions: ...and one sourced twice" \
	'tools/tests/selftest.sh:22: sources tools/tests/selftest_sections/e.sh a second time (line 19)' -- \
	cvi_rule cvst 'does not source its sections one file each'
want_out "conventions: ...and one sourced by no line" \
	'tools/tests/selftest_sections/orphan.sh: sourced by no line of tools/tests/selftest.sh' -- \
	cvi_rule cvst 'does not source its sections one file each'
want_out "conventions: ...and one that opens with no section line" \
	'tools/tests/selftest_sections/c.sh:1: does not open with its section line' -- \
	cvi_rule cvst 'does not source its sections one file each'
want_out "conventions: ...and one holding a second" \
	'tools/tests/selftest_sections/d.sh:4: a second section line' -- \
	cvi_rule cvst 'does not source its sections one file each'
want_out "conventions: ...and one holding the tally" \
	'tools/tests/selftest_sections/d.sh:5: the tally' -- \
	cvi_rule cvst 'does not source its sections one file each'
want_out "conventions: ...and a section line in the driver" \
	'tools/tests/selftest.sh:23: a section line, in the file that sources its sections' -- \
	cvi_rule cvst 'does not source its sections one file each'
want_broken_none "conventions: ...never a file sourced once, in its shape" \
	'selftest_sections/a.sh' -- cvi_rule cvst 'does not source its sections one file each'



# A saved run of the conventions check is read with its status (selftest_lib.sh,
# A SAVED RUN OF THE CONVENTIONS CHECK). A toy selftest of its own
# (cvsv), written with @D@ for each $ as cvst's is: reported, a run saved and
# read with cat (line 6) or grep (9), a run piped into grep (11), one kept in
# a variable whose status the next line drops (13), a helper reading the run
# of the toy its argument names (18) and a copy of cv_block's awk (19).
# Quiet: the run read through cv_saved (7) or a helper over it (10), a file
# no run wrote (8), an `||` and a `|` in quotes after a run (12), a run whose
# status the next line keeps (15), cv_block itself (20), the name in a regex
# (21), a comment (22), an echo (23) and an arm whose name says "cut" (24).
# A run through a function, conv, is a run: saved and read with cat (26),
# piped (27); a word conv that is no call is not (28).
mkdir -p "$WORK/cvsv/tools/tests" "$WORK/cvsv/m"
cv_submit m > "$WORK/cvsv/tools/submit.sh"
: > "$WORK/cvsv/m/BUILD.bazel"
printf '%s\n' '#!/bin/sh' 'set -u' 'WORK=@D@(mktemp -d)' \
	'CONV="env BUILD_WORKSPACE_DIRECTORY=@D@WORK/x sh tools/conventions.sh"' \
	'@D@CONV > "@D@WORK/x.out" 2>&1' \
	'cat "@D@WORK/x.out"' \
	'cv_saved "@D@WORK/x.out"' \
	'grep -c x "@D@WORK/y.txt"' \
	'grep -F x "@D@WORK/x.out"' \
	'x_said() { cv_saved "@D@WORK/x.out" grep -F x; }' \
	'@D@CONV 2>&1 | grep -F x' \
	'@D@CONV > /dev/null 2>&1 || echo "a|b"' \
	'_x=@D@(@D@CONV 2>&1)' \
	'echo "@D@_x"' \
	'_y=@D@(@D@CONV 2>&1)' \
	'_y_rc=@D@?' \
	'for _t in a b; do env BUILD_WORKSPACE_DIRECTORY="@D@WORK/@D@_t" sh "@D@TOOLS/conventions.sh" > "@D@WORK/@D@_t.out" 2>&1; done' \
	't_rule() { grep -F "@D@2" "@D@WORK/@D@1.out"; }' \
	'x_rule() { awk -v h="@D@1" '"'"'/^  FAIL: / { on = index(@D@0, h) > 0 } on'"'"' "@D@WORK/x.out"; }' \
	'cv_block() { awk '"'"'/^  FAIL: / { on = index(@D@0, ENVIRON["H"]) > 0 } on'"'"' "@D@1"; }' \
	'awk '"'"'/\@D@CONV/ { n++ }'"'"' "@D@WORK/y.txt"' \
	'# cat "@D@WORK/x.out", in a comment' \
	'echo '"'"'cat "@D@WORK/x.out"'"'"'' \
	'want_out "its excerpt cut short" x -- x_end "@D@WORK/x.out"' \
	'conv > "@D@WORK/z.out" 2>&1' \
	'cat "@D@WORK/z.out"' \
	'conv 2>&1 | grep -F x' \
	'mc_seen conv | grep -F x' |
	sed 's/@D@/$/g' > "$WORK/cvsv/tools/tests/selftest.sh"
! st_mine || env BUILD_WORKSPACE_DIRECTORY="$WORK/cvsv" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvsv.out" 2>&1
cvsv_said() { cvi_rule cvsv 'reads a conventions run without its status'; }
want_out "conventions: a saved run read with cat is reported" \
	'line 6: reads "$WORK/x.out" with no status' -- cvsv_said
want_out "conventions: ...and with grep" 'line 9: reads "$WORK/x.out"' -- cvsv_said
want_out "conventions: ...a run piped into another command" \
	'line 11: pipes a run into another command' -- cvsv_said
want_out "conventions: ...a run kept in a variable, its status dropped" \
	'line 13: keeps a run in a variable, and not its status' -- cvsv_said
want_out "conventions: ...a helper reading the run of the toy it is named" \
	'line 18: reads "$WORK/$1.out" with no status' -- cvsv_said
want_out "conventions: a copy of cv_block's awk is reported" \
	"line 19: cuts a rule's report out of a run by hand" -- \
	cvi_rule cvsv "cuts a rule's report out of a conventions run by hand"
want_broken_none "conventions: ...never cv_block itself" 'line 20:' -- \
	cvi_rule cvsv "cuts a rule's report out of a conventions run by hand"
want_out "conventions: ...a run through conv read with cat" \
	'line 26: reads "$WORK/z.out" with no status' -- cvsv_said
want_out "conventions: ...and one piped" 'line 27: pipes a run' -- cvsv_said
for _l in 7:cv_saved 8:'a file no run wrote' 10:'a helper over cv_saved' 12:'a pipe in quotes' \
	15:'a status kept' 21:'a regex' 22:'a comment' 23:'an echo' 24:"an arm's name" \
	28:'a word conv that is no call'; do
	want_broken_none "conventions: ...never ${_l#*:} (line ${_l%%:*})" \
		"line ${_l%%:*}:" -- cvsv_said
done
# The three readers over a copy of that run cut before its verdict line:
# each says so and gives 2, cv_block still printing the report it cut.
! st_mine || sed '/^conventions: /d' "$WORK/cvsv.out" > "$WORK/cvsvcut.out"
want_broken "conventions: cv_saved gives a run with no verdict line status 2" \
	'holds no verdict line' -- cv_saved "$WORK/cvsvcut.out"
want_broken "conventions: ...cv_block too, with the report it cut" \
	'line 6: reads' -- \
	cv_block "$WORK/cvsvcut.out" 'reads a conventions run without its status'
want_broken "conventions: ...and cvi_rule" 'holds no verdict line' -- \
	cvi_rule cvsvcut 'reads a conventions run without its status'

# Arms that ask one tree read one run of it. A toy selftest (cvag), written
# with @D@ for each $: reported, an arm running $CONV as the arm before it did
# (5), one more after a comment and over continuation lines (7), one after
# an arm reading a saved run (12), and a run spelt out over its own tree,
# twice (15). Quiet: the first arm after a statement (4), one after a write
# to the tree (10), one over another tree, $CONVK (13), the first run
# spelt out (14), and the first arm of a section (17). And through the
# function conv: an arm running it as the one before did (21) is reported,
# and one after an arm over another tree, convk (20), is not.
mkdir -p "$WORK/cvag/tools/tests" "$WORK/cvag/m"
cv_submit m > "$WORK/cvag/tools/submit.sh"
: > "$WORK/cvag/m/BUILD.bazel"
printf '%s\n' '#!/bin/sh' 'set -u' \
	'CONV="env BUILD_WORKSPACE_DIRECTORY=@D@WORK/x sh tools/conventions.sh"' \
	'want_out "a" x -- @D@CONV' \
	'want_out "b" y -- @D@CONV' \
	'# a comment between' \
	'want_broken_none "c" z -- \' \
	'	@D@CONV' \
	'printf x > "@D@WORK/x/a.txt"' \
	'want_out "d" x -- @D@CONV' \
	'want_out "e" x -- cv_saved "@D@WORK/x.out"' \
	'want_out "f" x -- @D@CONV' \
	'want_out "g" x -- @D@CONVK' \
	'want_out "h" x -- env BUILD_WORKSPACE_DIRECTORY="@D@WORK/y" sh "@D@TOOLS/conventions.sh"' \
	'want_out "i" x -- env BUILD_WORKSPACE_DIRECTORY="@D@WORK/y" sh "@D@TOOLS/conventions.sh"' \
	'# ------------------------------------------------ a toy section' \
	'want_out "j" x -- env BUILD_WORKSPACE_DIRECTORY="@D@WORK/y" sh "@D@TOOLS/conventions.sh"' \
	'want_out "k" x -- conv' \
	'want_out "l" x -- convk' \
	'want_out "m" x -- conv' \
	'want_out "n" x -- conv' |
	sed 's/@D@/$/g' > "$WORK/cvag/tools/tests/selftest.sh"
! st_mine || env BUILD_WORKSPACE_DIRECTORY="$WORK/cvag" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvag.out" 2>&1
cvag_said() { cvi_rule cvag 'runs conventions.sh again over a tree nothing changed'; }
want_out "conventions: an arm running \$CONV as the arm before it did is reported" \
	'line 5: $CONV, as the arm before it ran' -- cvag_said
want_out "conventions: ...after a comment, over continuation lines" 'line 7: $CONV' -- cvag_said
want_out "conventions: ...after an arm reading a saved run" 'line 12: $CONV' -- cvag_said
want_out "conventions: ...and a run spelt out, twice" \
	'line 15: env BUILD_WORKSPACE_DIRECTORY="$WORK/y" sh "$TOOLS/conventions.sh", as' -- cvag_said
want_out "conventions: ...and a call of conv, as the arm before it ran" \
	'line 21: conv, as the arm before it ran' -- cvag_said
for _l in 4:'the first arm after a statement' 10:'an arm after a write' 13:'another tree' \
	14:'the first run spelt out' 17:"a section's first arm" 20:'conv after convk'; do
	want_broken_none "conventions: ...never ${_l#*:} (line ${_l%%:*})" \
		"line ${_l%%:*}:" -- cvag_said
done
rm -rf "$WORK/cvag" "$WORK/cvag.out"

# A command line with a path in it is a function, never a string run
# unquoted. A toy selftest (cvcmd), @D@ for each $: reported, a string of
# several words naming $WORK or $TOOLS run by an arm (3), after || (5) and
# after then (15). Quiet: a list of options passed as arguments (7), a
# string only ever quoted (9), a single word (11) and a function (13).
mkdir -p "$WORK/cvcmd/tools/tests" "$WORK/cvcmd/m"
cv_submit m > "$WORK/cvcmd/tools/submit.sh"
: > "$WORK/cvcmd/m/BUILD.bazel"
printf '%s\n' '#!/bin/sh' 'set -u' \
	'RUNX="env A=@D@WORK/x sh @D@TOOLS/t.sh"' \
	'want_out "a" x -- @D@RUNX' \
	'RUNY="env A=@D@WORK/y @D@SH t.sh"' \
	'! st_mine || @D@RUNY > "@D@WORK/y.out" 2>&1' \
	'OPTS="--opt @D@WORK/o.txt --flag"' \
	'"@D@SH" "@D@TOOLS/t.sh" @D@OPTS --src a.c' \
	'RUNZ="env A=@D@WORK/z sh @D@TOOLS/t.sh"' \
	'echo "@D@RUNZ"' \
	'ONE="@D@WORK/one"' \
	'@D@ONE' \
	'runw() { env A="@D@WORK/w" "@D@SH" "@D@TOOLS/t.sh"; }' \
	'want_out "b" x -- runw' \
	'RUNV="env A=@D@WORK/v sh t.sh"' \
	'if true; then @D@RUNV; fi' |
	sed 's/@D@/$/g' > "$WORK/cvcmd/tools/tests/selftest.sh"
! st_mine || env BUILD_WORKSPACE_DIRECTORY="$WORK/cvcmd" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvcmd.out" 2>&1
cvcmd_said() { cvi_rule cvcmd 'runs a command line held in a variable'; }
want_out "conventions: a command line in a variable run by an arm is reported" \
	'line 3: RUNX holds a command line, run unquoted at line 4' -- cvcmd_said
want_out "conventions: ...and one run after ||" \
	'line 5: RUNY holds a command line, run unquoted at line 6' -- cvcmd_said
want_out "conventions: ...and after then" \
	'line 15: RUNV holds a command line, run unquoted at line 16' -- cvcmd_said
for _l in 7:'a list of options' 9:'a string only quoted' 11:'a single word' 13:'a function'; do
	want_broken_none "conventions: ...never ${_l#*:} (line ${_l%%:*})" \
		"line ${_l%%:*}:" -- cvcmd_said
done
rm -rf "$WORK/cvcmd" "$WORK/cvcmd.out"
