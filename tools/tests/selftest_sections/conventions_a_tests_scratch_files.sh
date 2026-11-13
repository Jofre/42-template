# ------------------------------------------ conventions: a test's scratch files
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A test's program points TMPDIR at TEST_TMPDIR before its first mktemp, and
# every valgrind runs with --vgdb=no (conventions.sh, "A test's scratch files
# go under TEST_TMPDIR"). cvtmp is a toy checkout whose BUILD file and .bzl
# files name test programs every way the rule reads one -- a hand_test's srcs,
# a macro's kwargs["srcs"], a .bzl test rule's script default -- beside a
# sh_binary's and a build rule's, which are no test; one run of conventions.sh,
# read by every arm.
mkdir -p "$WORK/cvtmp/tools/tests" "$WORK/cvtmp/c-piscine/c-piscine-c-90"
cv_submit "c-piscine/c-piscine-c-90" > "$WORK/cvtmp/tools/submit.sh"
: > "$WORK/cvtmp/c-piscine/c-piscine-c-90/BUILD.bazel"
{
	printf '%s\n' 'hand_test(' '    name = "bare",' '    srcs = ["tmp_bare.sh"],' ')'
	for _t in late ok lib nomk gone; do
		printf 'hand_test(name = "%s", srcs = ["tmp_%s.sh"])\n' "$_t" "$_t"
	done
	printf '%s\n' 'py_test(name = "py", srcs = ["tmp_py.py"])' \
		'py_test(name = "py_ok", srcs = ["tmp_py_ok.py"])' \
		'py_test(name = "py_str", srcs = ["tmp_py_str.py"])' \
		'py_test(name = "py_late", srcs = ["tmp_py_late.py"])' \
		'py_test(name = "py_imp", srcs = ["tmp_py_imp.py"])' \
		'sh_binary(name = "bin", srcs = ["tmp_bin.sh"])'
	# A srcs list as buildifier writes it, one element a line; one built
	# in Starlark, which this check cannot read; and one that names the
	# list its value is one of, read from there.
	printf '%s\n' 'TOY_RUNNERS = [' '    "tmp_one.sh",' ']' \
		'hand_test(' '    name = "multi",' '    srcs = [' '        "tmp_multi.sh",' '    ],' ')' \
		'[hand_test(' '    name = "var_" + p,' '    srcs = [p],' ') for p in ["tmp_bare.sh"]]' \
		'[hand_test(' '    name = "one_" + p,' '    srcs = [p],  # one of TOY_RUNNERS' ') for p in TOY_RUNNERS]' \
		'hand_test(name = "nowhere", srcs = [q],  # one of NOWHERE' ')'
	# A comment after the list that quotes a word, and a test whose srcs
	# is no script, which this check does not hold; and one whose script
	# ends in neither .sh nor .py, which it cannot read.
	printf '%s\n' 'hand_test(name = "q", srcs = ["tmp_q.sh"],  # the "runner" one' ')' \
		'cc_test(name = "c", srcs = ["tmp_c.c"])' \
		'hand_test(name = "bash", srcs = ["tmp_bash.bash"])'
	# A mark is held where it sits (V153): a loop over a literal list
	# naming a script NAME does not hold (41), one over a list of this
	# file holding only NAME's scripts (48), and a mark in no loop and no
	# def that checks its value (50).
	printf '%s\n' '[hand_test(' '    name = "lit_" + p,' '    srcs = [p],  # one of TOY_RUNNERS' \
		') for p in ["tmp_one.sh", "tmp_stray.sh"]]' \
		'TOY_CASES = [' '    ("a", "tmp_one.sh"),' ']' \
		'[hand_test(' '    name = "case_" + n,' '    srcs = [p],  # one of TOY_RUNNERS' ') for n, p in TOY_CASES]' \
		'hand_test(name = "loose", srcs = [r],  # one of TOY_RUNNERS' ')'
	# A loop over another list, filtered on NAME, holds nothing (54); one
	# whose list names a label NAME does not hold (58); and one over NAME,
	# filtered, holds the mark (62).
	printf '%s\n' '[hand_test(' '    name = "if_" + p,' '    srcs = [p],  # one of TOY_RUNNERS' \
		') for p in OTHER_TOY if p not in TOY_RUNNERS]' \
		'[hand_test(' '    name = "lab_" + p,' '    srcs = [p],  # one of TOY_RUNNERS' \
		') for p in ["tmp_one.sh", "//tools/tests:tmp_label"]]' \
		'[hand_test(' '    name = "cond_" + p,' '    srcs = [p],  # one of TOY_RUNNERS' \
		') for p in TOY_RUNNERS if p != "tmp_x.sh"]'
} > "$WORK/cvtmp/tools/tests/BUILD.bazel"
printf '%s\n' 'def toy(**kwargs):' '    kwargs["srcs"] = ["//tools:tmp_kw.sh"]' \
	'toy_test = rule(' '    attrs = {"_runner": attr.label(default = ":tmp_rule.sh")},' \
	'    test = True,' ')' 'def toy_else(**kwargs):' '    kwargs["srcs"] = ["//tools:tmp_else.sh"]' \
	> "$WORK/cvtmp/tools/tests/toy_test.bzl"
printf '%s\n' 'toy_build = rule(' '    attrs = {"_script": attr.label(default = ":tmp_build.sh")},' ')' \
	> "$WORK/cvtmp/tools/tests/toy_build.bzl"
# The library, without the line: sourcing it is then no answer of its own.
printf '#!/bin/sh\nRL_NAME=${RL_NAME:-x}\n' > "$WORK/cvtmp/tools/runner_lib.sh"
_cvt_mk='d=$(mktemp -d) || exit 2'
_cvt_tl='case ${TMPDIR:-/tmp} in /tmp | /tmp/) [ -z "${TEST_TMPDIR:-}" ] || export TMPDIR="$TEST_TMPDIR" ;; esac'
for _t in bare bin build rule multi one q; do
	printf '#!/bin/sh\nset -u\n%s\n' "$_cvt_mk" > "$WORK/cvtmp/tools/tests/tmp_$_t.sh"
done
printf '#!/bin/sh\nset -u\n%s\n' "$_cvt_mk" > "$WORK/cvtmp/tools/tmp_kw.sh"
# A mktemp behind else is the first one all the same.
printf '#!/bin/sh\nset -u\nif [ -n "${X:-}" ]; then :; else mktemp -d > /dev/null; fi\n%s\n' "$_cvt_tl" \
	> "$WORK/cvtmp/tools/tmp_else.sh"
printf '#!/bin/sh\nset -u\n%s\n%s\n' "$_cvt_mk" "$_cvt_tl" > "$WORK/cvtmp/tools/tests/tmp_late.sh"
# The word in a require line and in a message is no mktemp it runs.
{ printf '#!/bin/sh\nset -u\n'; cv_require tmp_ok.sh; printf 'require mktemp\necho "mktemp failed"\n%s\n%s\n' \
	"$_cvt_tl" "$_cvt_mk"; } \
	> "$WORK/cvtmp/tools/tests/tmp_ok.sh"
printf '#!/bin/sh\nset -u\n. "$RL_LIB"\n%s\n' "$_cvt_mk" > "$WORK/cvtmp/tools/tests/tmp_lib.sh"
printf '#!/bin/sh\nset -u\necho nothing to keep\n' > "$WORK/cvtmp/tools/tests/tmp_nomk.sh"
printf 'import tempfile\nprint(tempfile.mkdtemp())\n' > "$WORK/cvtmp/tools/tests/tmp_py.py"
printf 'import os\nif os.environ.get("TEST_TMPDIR"):\n    os.environ["TMPDIR"] = os.environ["TEST_TMPDIR"]\n' \
	> "$WORK/cvtmp/tools/tests/tmp_py_ok.py"
# A line that only names both is no assignment; one made after the first
# scratch file is too late; an import of tempfile makes no file yet.
printf 'import os\nprint("TMPDIR comes from TEST_TMPDIR")\n' > "$WORK/cvtmp/tools/tests/tmp_py_str.py"
printf 'import os, tempfile\nd = tempfile.mkdtemp()\nos.environ["TMPDIR"] = os.environ["TEST_TMPDIR"]\n' \
	> "$WORK/cvtmp/tools/tests/tmp_py_late.py"
printf 'import os\nfrom tempfile import mkdtemp\nos.environ["TMPDIR"] = os.environ["TEST_TMPDIR"]\nd = mkdtemp()\n' \
	> "$WORK/cvtmp/tools/tests/tmp_py_imp.py"
# A valgrind as a runner starts one: through rl_run over two lines (3), with
# the option (5), asking only its version (6), under env (7), and named in a
# message (8); behind else, while, elif and until (9-12), and under env
# with a name it unsets (13). A `command -v` (14) looks it up and runs it not.
# And one behind timeout and its duration (15), and behind nohup (16).
cat > "$WORK/cvtmp/tools/tmp_vg.sh" <<'CVT_VG'
#!/bin/sh
set -u
rl_run "$VALGRIND" --tool=callgrind \
	./a.out
rl_run "$VALGRIND" --vgdb=no --tool=callgrind ./a.out
"$VALGRIND" --version
env A=1 valgrind ./a.out
echo "valgrind ./a.out"
if true; then :; else valgrind ./a.out; fi
while valgrind ./b.out; do :; done
if false; then :; elif valgrind ./c.out; then :; fi
until valgrind ./d.out; do :; done
env -u VALGRIND_OPTS valgrind ./e.out
command -v valgrind > /dev/null
timeout 5 valgrind ./f.out
nohup valgrind ./g.out
CVT_VG
# And each run with the host's valgrind settings off first (V227): one after
# rl_vg_env (4), a second with no call since (5), its version (6), one that
# sets VALGRIND_OPTS on its own line (8), one with HOME under env (10),
# one that sets DEBUGINFOD_URLS back on its own line (12, V270), and one
# that sets VALGRIND_OPTS past a name env unsets (14); one behind timeout
# with no call since (15), and one behind nohup and env that sets
# VALGRIND_OPTS (17).
cat > "$WORK/cvtmp/tools/tmp_vgenv.sh" <<'CVT_VG'
#!/bin/sh
set -u
rl_vg_env "$T" || exit 2
rl_run "$VALGRIND" --vgdb=no ./a.out
rl_run "$VALGRIND" --vgdb=no ./b.out
"$VALGRIND" --version
rl_vg_env "$T" || exit 2
VALGRIND_OPTS=-q rl_run "$VALGRIND" --vgdb=no ./c.out
rl_vg_env "$T" || exit 2
env HOME=/tmp "$VALGRIND" --vgdb=no ./d.out
rl_vg_env "$T" || exit 2
DEBUGINFOD_URLS=http://x.invalid rl_run "$VALGRIND" --vgdb=no ./e.out
rl_vg_env "$T" || exit 2
env -u DEBUGINFOD_URLS VALGRIND_OPTS=-q valgrind --vgdb=no ./f.out
timeout 5 valgrind --vgdb=no ./g.out
rl_vg_env "$T" || exit 2
nohup env VALGRIND_OPTS=-q valgrind --vgdb=no ./h.out
CVT_VG
# And a tool outside a test, which removes what it mktemps on a signal too
# (V164): none of its traps, only an EXIT one, an INT one but no TERM,
# signal traps that only exit, EXIT, TERM and INT traps but none on the HUP
# a closed terminal sends (each at line 3); EXIT, TERM, INT and HUP traps;
# INT, TERM and HUP traps that call a function which cleans up, as
# tools/identity.sh does; a mktemp said to be a test's scratch; a runner on
# the library; a mktemp behind else, with no trap. tools/tmp_kw.sh, a
# test's program, is no such tool.
cvt_mt() {  # cvt_mt LINE: a tool that mktemps at line 3, then runs LINE
	printf '#!/bin/sh\nset -u\nT=$(mktemp) || exit 2\n%s\n' "$1"
}
cvt_mt ':' > "$WORK/cvtmp/tools/mkt_none.sh"
cvt_mt "trap 'rm -f \"\$T\"' EXIT" > "$WORK/cvtmp/tools/mkt_exit.sh"
cvt_mt "trap 'rm -f \"\$T\"' EXIT; trap 'exit 130' INT" > "$WORK/cvtmp/tools/mkt_noterm.sh"
cvt_mt "trap 'exit 143' TERM; trap 'exit 130' INT; trap 'exit 129' HUP" > "$WORK/cvtmp/tools/mkt_sigonly.sh"
cvt_mt "trap 'rm -f \"\$T\"' EXIT; trap 'exit 143' TERM; trap 'exit 130' INT" > "$WORK/cvtmp/tools/mkt_nohup.sh"
printf '#!/bin/sh\nset -u\nT=""\nF=""\nT=$(mktemp) || exit 2\ntrap %s EXIT\ntrap %s TERM\ntrap %s INT\ntrap %s HUP\nF=$(mktemp)\n' \
	"'rm -f \"\$T\" \"\$F\"'" "'exit 143'" "'exit 130'" "'exit 129'" > "$WORK/cvtmp/tools/mkt_ok.sh"
printf '#!/bin/sh\nset -u\ngive_up() { rm -f "$T"; exit "$1"; }\nT=""\ntrap %s TERM\ntrap %s INT\ntrap %s HUP\nT=$(mktemp)\n' \
	"'give_up 143'" "'give_up 130'" "'give_up 129'" > "$WORK/cvtmp/tools/mkt_giveup.sh"
printf '#!/bin/sh\nset -u\n# conventions: test scratch -- a toy\nT=$(mktemp)\n' > "$WORK/cvtmp/tools/mkt_marked.sh"
printf '#!/bin/sh\nset -u\n. "$RL_LIB"\nT=$(mktemp)\n' > "$WORK/cvtmp/tools/mkt_lib.sh"
printf '#!/bin/sh\nset -u\nif [ -n "${X:-}" ]; then :; else mktemp > /dev/null; fi\n' > "$WORK/cvtmp/tools/mkt_else.sh"
# And a mktemp whose result is used unchecked (line 3), the same in quotes
# (line 4); one with a check after it and one with a fallback inside it are
# no such thing.
printf '#!/bin/sh\nset -u\nT=$(mktemp -d)\nU="$(mktemp)"\nV=$(mktemp) || exit 2\nW=$(mktemp -d 2> /dev/null || mktemp -d -t x.XXXXXX)\n' \
	> "$WORK/cvtmp/tools/mkt_bare.sh"
# The same in a selftest driver, which tools/tests/ holds.
printf '#!/bin/sh\nset -u\nWORK=$(mktemp -d)\n' > "$WORK/cvtmp/tools/tests/mkt_drv.sh"
! st_mine || env BUILD_WORKSPACE_DIRECTORY="$WORK/cvtmp" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvtmp.out" 2>&1
cvt_rule() { cvi_rule cvtmp 'outside TEST_TMPDIR'; }  # this rule's report of the run above, alone
want_out "conventions: a test program's mktemp with TMPDIR left unset" \
	'tools/tests/tmp_bare.sh:3: mktemp, and TMPDIR never points at TEST_TMPDIR' -- cvt_rule
want_out "conventions: ...and one that sets it only after" \
	'tools/tests/tmp_late.sh:3: mktemp, before line 4 points TMPDIR' -- cvt_rule
want_broken_none "conventions: ...not one that sets it first" 'tmp_ok.sh' -- cvt_rule
want_out "conventions: ...and a mktemp behind else is the first one" \
	'tools/tmp_else.sh:3: mktemp, before line 4 points TMPDIR' -- cvt_rule
want_broken_none "conventions: ...nor one that sources the library" 'tmp_lib.sh' -- cvt_rule
want_out "conventions: ...but a library without the line is reported" \
	'tools/runner_lib.sh: its prologue never points TMPDIR' -- cvt_rule
want_broken_none "conventions: ...nor one that makes no scratch file" 'tmp_nomk.sh' -- cvt_rule
want_broken_none "conventions: ...nor a sh_binary's script" 'tmp_bin.sh' -- cvt_rule
want_out "conventions: a macro's kwargs[\"srcs\"] is a test program" \
	'tools/tmp_kw.sh:3: mktemp' -- cvt_rule
want_out "conventions: ...and a .bzl test rule's script default" \
	'tools/tests/tmp_rule.sh:3: mktemp' -- cvt_rule
want_broken_none "conventions: ...not a build rule's" 'tmp_build.sh' -- cvt_rule
want_out "conventions: a test program that is not there is reported" \
	'tools/tests/BUILD.bazel:' -- cvt_rule
want_out "conventions: ...naming it" 'tmp_gone.sh (a test program this check cannot find)' -- cvt_rule
want_out "conventions: a test's srcs over several lines is read" \
	'tools/tests/tmp_multi.sh:3: mktemp, and TMPDIR never points' -- cvt_rule
want_out "conventions: ...and one built in Starlark is reported, not skipped" \
	"tools/tests/BUILD.bazel:27: srcs = [p] (a test's srcs this check cannot read)" -- cvt_rule
want_out "conventions: ...unless it names the list its value is one of" \
	'tools/tests/tmp_one.sh:3: mktemp, and TMPDIR never points' -- cvt_rule
want_out "conventions: ...which must be a list of strings somewhere" \
	'tools/tests/BUILD.bazel:33: one of NOWHERE, which no BUILD file or .bzl' -- cvt_rule
want_broken_none "conventions: ...and a loop over that list holds the mark" \
	'tools/tests/BUILD.bazel:31:' -- cvt_rule
want_out "conventions: ...while a loop over a list naming another script does not" \
	'tools/tests/BUILD.bazel:41: "tmp_stray.sh", in the list its srcs is read from, is not one of TOY_RUNNERS' -- cvt_rule
want_broken_none "conventions: ...though its scripts of the list are no report" \
	'"tmp_one.sh", in the list' -- cvt_rule
want_broken_none "conventions: ...nor is a loop over a list of this file holding only them" \
	'tools/tests/BUILD.bazel:48:' -- cvt_rule
want_out "conventions: ...and a mark nothing holds is reported" \
	'tools/tests/BUILD.bazel:50: one of TOY_RUNNERS, and nothing holds it there' -- cvt_rule
want_out "conventions: ...nor a loop over another list that only filters on it" \
	'tools/tests/BUILD.bazel:54: one of TOY_RUNNERS, over OTHER_TOY, which this check cannot read' -- cvt_rule
want_out "conventions: ...and a label in the list is held to it too" \
	'tools/tests/BUILD.bazel:58: "//tools/tests:tmp_label", in the list its srcs is read from, is not one of TOY_RUNNERS' -- cvt_rule
want_broken_none "conventions: ...while a loop over it, filtered, holds the mark" \
	'tools/tests/BUILD.bazel:62:' -- cvt_rule
want_out "conventions: a srcs whose comment quotes a word is read" \
	'tools/tests/tmp_q.sh:3: mktemp, and TMPDIR never points' -- cvt_rule
want_broken_none "conventions: ...and is no srcs it cannot read" 'tmp_q.sh"]' -- cvt_rule
want_broken_none "conventions: ...nor is one that holds no script" 'tmp_c.c' -- cvt_rule
want_out "conventions: ...while one whose script is no .sh or .py is reported" \
	'tools/tests/BUILD.bazel:38: "tmp_bash.bash" (a test'"'"'s srcs this check cannot read' -- cvt_rule
want_out "conventions: a Python test program that leaves TMPDIR unset" \
	'tools/tests/tmp_py.py: a Python test program' -- cvt_rule
want_broken_none "conventions: ...not one that sets it" 'tmp_py_ok.py' -- cvt_rule
want_out "conventions: ...but one whose line only names TMPDIR and TEST_TMPDIR is" \
	'tools/tests/tmp_py_str.py: a Python test program' -- cvt_rule
want_out "conventions: ...and one that sets it after its first scratch file" \
	'tools/tests/tmp_py_late.py:2: tempfile, before line 3 sets TMPDIR' -- cvt_rule
want_broken_none "conventions: ...not one that imports tempfile before it" 'tmp_py_imp.py' -- cvt_rule
want_out "conventions: a valgrind without --vgdb=no, over two lines" \
	'tools/tmp_vg.sh:3: valgrind without --vgdb=no' -- cvt_rule
want_out "conventions: ...and one under env" 'tools/tmp_vg.sh:7: valgrind without' -- cvt_rule
want_broken_none "conventions: ...not one with it" 'tools/tmp_vg.sh:5:' -- cvt_rule
want_broken_none "conventions: ...nor one asking its version" 'tools/tmp_vg.sh:6:' -- cvt_rule
want_broken_none "conventions: ...nor a message naming it" 'tools/tmp_vg.sh:8:' -- cvt_rule
want_out "conventions: ...one behind else" 'tools/tmp_vg.sh:9: valgrind without' -- cvt_rule
want_out "conventions: ...behind while" 'tools/tmp_vg.sh:10: valgrind without' -- cvt_rule
want_out "conventions: ...behind elif" 'tools/tmp_vg.sh:11: valgrind without' -- cvt_rule
want_out "conventions: ...behind until" 'tools/tmp_vg.sh:12: valgrind without' -- cvt_rule
want_out "conventions: ...and under env -u NAME" 'tools/tmp_vg.sh:13: valgrind without' -- cvt_rule
want_broken_none "conventions: ...nor a command -v that looks it up" 'tools/tmp_vg.sh:14:' -- cvt_rule
want_out "conventions: ...and one behind timeout" 'tools/tmp_vg.sh:15: valgrind without' -- cvt_rule
want_out "conventions: ...and behind nohup" 'tools/tmp_vg.sh:16: valgrind without' -- cvt_rule
cvt_vgenv() { cvi_rule cvtmp "host's valgrind settings"; }  # the rule on the host's valgrind settings, alone
want_out "conventions: a second valgrind run with no rl_vg_env since" \
	'tools/tmp_vgenv.sh:5: valgrind run with no rl_vg_env before it' -- cvt_vgenv
want_broken_none "conventions: ...not one right after it" 'tools/tmp_vgenv.sh:4:' -- cvt_vgenv
want_broken_none "conventions: ...nor one asking its version" 'tools/tmp_vgenv.sh:6:' -- cvt_vgenv
want_out "conventions: a valgrind run that sets VALGRIND_OPTS itself" \
	'tools/tmp_vgenv.sh:8: valgrind run with a VALGRIND_OPTS, DEBUGINFOD_URLS or HOME of its own' -- cvt_vgenv
want_out "conventions: ...or HOME, under env" \
	'tools/tmp_vgenv.sh:10: valgrind run with a VALGRIND_OPTS, DEBUGINFOD_URLS or HOME' -- cvt_vgenv
want_out "conventions: ...or DEBUGINFOD_URLS" \
	'tools/tmp_vgenv.sh:12: valgrind run with a VALGRIND_OPTS, DEBUGINFOD_URLS or HOME' -- cvt_vgenv
want_out "conventions: ...and a runner that never calls it" \
	'tools/tmp_vg.sh:5: valgrind run with no rl_vg_env before it' -- cvt_vgenv
want_out "conventions: ...and one behind else, unarmed" 'tools/tmp_vg.sh:9: valgrind run with no rl_vg_env' -- cvt_vgenv
want_out "conventions: ...and one behind while, unarmed" 'tools/tmp_vg.sh:10: valgrind run with no rl_vg_env' -- cvt_vgenv
want_out "conventions: ...and one behind elif, unarmed" 'tools/tmp_vg.sh:11: valgrind run with no rl_vg_env' -- cvt_vgenv
want_out "conventions: ...and one behind until, unarmed" 'tools/tmp_vg.sh:12: valgrind run with no rl_vg_env' -- cvt_vgenv
want_out "conventions: ...and one under env -u NAME, unarmed" 'tools/tmp_vg.sh:13: valgrind run with no rl_vg_env' -- cvt_vgenv
want_broken_none "conventions: ...never a command -v that looks it up" 'tools/tmp_vg.sh:14:' -- cvt_vgenv
want_out "conventions: ...and one setting VALGRIND_OPTS past a name env unsets" \
	'tools/tmp_vgenv.sh:14: valgrind run with a VALGRIND_OPTS, DEBUGINFOD_URLS or HOME' -- cvt_vgenv
want_out "conventions: ...and one behind timeout, unarmed" 'tools/tmp_vg.sh:15: valgrind run with no rl_vg_env' -- cvt_vgenv
want_out "conventions: ...and behind nohup, unarmed" 'tools/tmp_vg.sh:16: valgrind run with no rl_vg_env' -- cvt_vgenv
want_out "conventions: ...one behind timeout with no call since" \
	'tools/tmp_vgenv.sh:15: valgrind run with no rl_vg_env before it' -- cvt_vgenv
want_out "conventions: ...and one behind nohup and env that sets VALGRIND_OPTS" \
	'tools/tmp_vgenv.sh:17: valgrind run with a VALGRIND_OPTS, DEBUGINFOD_URLS or HOME' -- cvt_vgenv
cvt_mkt() { cvi_rule cvtmp 'temporary files behind'; }  # the rule on a tool's temporary files, alone
want_out "conventions: a tool's mktemp with no trap at all" \
	'tools/mkt_none.sh:3: mktemp, and no trap on INT, TERM or HUP' -- cvt_mkt
want_out "conventions: ...and one with only an EXIT trap" \
	'tools/mkt_exit.sh:3: mktemp, and no trap on INT, TERM or HUP' -- cvt_mkt
want_out "conventions: ...and one with no TERM trap" \
	'tools/mkt_noterm.sh:3: mktemp, and no trap on TERM or HUP:' -- cvt_mkt
want_out "conventions: ...and signal traps that only exit, with no EXIT one" \
	'tools/mkt_sigonly.sh:3: mktemp, and no EXIT trap' -- cvt_mkt
want_out "conventions: ...and EXIT, TERM and INT traps but no HUP one" \
	'tools/mkt_nohup.sh:3: mktemp, and no trap on HUP:' -- cvt_mkt
want_broken_none "conventions: ...not one with EXIT, TERM, INT and HUP traps" 'mkt_ok.sh' -- cvt_mkt
want_broken_none "conventions: ...nor signal traps calling a cleanup" 'mkt_giveup.sh' -- cvt_mkt
want_broken_none "conventions: ...nor a mktemp said to be a test's" 'mkt_marked.sh' -- cvt_mkt
want_broken_none "conventions: ...nor a runner on the library" 'mkt_lib.sh' -- cvt_mkt
want_out "conventions: ...and a mktemp behind else is one" \
	'tools/mkt_else.sh:3: mktemp, and no trap on INT, TERM or HUP' -- cvt_mkt
want_broken_none "conventions: ...nor a test's program" 'tmp_kw.sh' -- cvt_mkt
cvt_bare() { cvi_rule cvtmp "result is used without a check"; }  # the rule on an unchecked mktemp, alone
want_out "conventions: a mktemp whose result is used unchecked" \
	'tools/mkt_bare.sh:3:T=$(mktemp -d)' -- cvt_bare
want_out "conventions: ...and the same in quotes" 'tools/mkt_bare.sh:4:' -- cvt_bare
want_broken_none "conventions: ...not one checked after it" 'tools/mkt_bare.sh:5:' -- cvt_bare
want_broken_none "conventions: ...nor one with a fallback inside it" 'tools/mkt_bare.sh:6:' -- cvt_bare
want_out "conventions: ...and one in a selftest driver" 'tools/tests/mkt_drv.sh:3:' -- cvt_bare

