# -------------------------------------------------------------- first_red
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Turns a wall of red into one objective. Its whole value is the TRIAGE, so the
# arms check the classification rather than the formatting: a written
# deliverable failing a green-on-a-stub layer must be called out, and a STUB
# failing the same layer must not be -- that second case is c-08 on a fresh
# clone, where a header that defines nothing cannot compile the subject's own
# main, and an earlier version of this script blamed the student for it.
mkdir -p "$WORK/fr/mod/deliverable/ex00"
# fr_contract MODDIR NN=DIR... -- the module's subject contract, which is
# where first_red reads each exercise's turn-in folder from: DIR "ex00/".
fr_contract() {
	_frc=$1
	shift
	{
		printf 'subject(\n    grader = "moulinette",\n    group = False,\n    exercises = {\n'
		for _fre in "$@"; do
			printf '        "%s": exercise(page = 1, dir = "%s", files = [], allowed = None),\n' \
				"${_fre%%=*}" "${_fre#*=}"
		done
		printf '    },\n)\n'
	} > "$_frc/BUILD.bazel"
}
# fr_root MODDIR -- a contract of units instead, for a subject with no
# turn-in directory line: its one unit, toyroot, turns in at the root of
# deliverable/.
fr_root() {
	printf 'subject(\n    grader = "moulinette",\n    group = False,\n    units = {\n%s\n    },\n)\n' \
		'        "toyroot": unit(page = 1, files = [], allowed = None),' > "$1/BUILD.bazel"
}
fr_contract "$WORK/fr/mod" 00=ex00/ 01=ex01/
# ABSOLUTE, before any cd. $TOOLS is runfiles-relative, and these arms have to
# cd into a fake workspace so first_red can find deliverable/ -- which is
# exactly the "handed over relative, then stranded by a later cd" failure this
# repo has hit four times with fetched tools. Resolve it once, here.
FR_TOOLS=$(cd "$TOOLS" && pwd)
printf '//mod:ex00_compile_gcc  FAILED in 0.3s\n' > "$WORK/fr/ko.log"
printf '//mod:ex00_output  FAILED in 0.1s\n'      > "$WORK/fr/work.log"

# A stub opens with the 11-line 42 header, as every one the template ships
# does: stub_check refuses a file without it, and first_red then counts a red
# rule over it as the student's.
FR_H=$(awk 'BEGIN { b = "/* "; for (i = 0; i < 74; i++) b = b "*"; b = b " */"
	print b; for (i = 0; i < 9; i++) printf "/*%76s*/\n", ""; print b }')
# A deliverable that is written: (void) casts plus a real statement.
printf 'int\tf(int a)\n{\n\treturn (a + 1);\n}\n' > "$WORK/fr/mod/deliverable/ex00/f.c"
want_out "first_red: a WRITTEN file failing compile is the student's to fix" \
	'FIX FIRST' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/ko.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"

# The same failure over a STUB must not be blamed on anyone.
printf '%s\n\nint\tf(int a)\n{\n\t(void)a;\n\treturn (0);\n}\n' "$FR_H" \
	> "$WORK/fr/mod/deliverable/ex00/f.c"
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
# The two options the 42 command reads it with (tools/fortytwo/report.py):
# --cmd 42 words each suggestion as the 42 command to type, and --next FILE
# writes the first red as one line of TSV, the line 42 picks a log from.
want_out "first_red: --cmd 42 suggests the 42 command" \
	'42 test mod ex00' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --cmd 42 < "$1/work.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ... and no bazel command beside it" \
	'bazel test' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --cmd 42 < "$1/work.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: --next writes the first red as TSV" \
	"$(printf 'work\t//mod\tex00\t//mod:ex00_output')" -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --next "$1/next.tsv" < "$1/work.log" > /dev/null && cat "$1/next.tsv"' \
	_ "$WORK/fr" "$SH" "$FR_TOOLS"
# --triage FILE writes each red exercise's verdict, the one the report words,
# as "KIND<tab>MODULE<tab>EXERCISE": what submit's --written-only reads. Over
# the stub above, ex00's red output is "work", an exercise not written yet.
want_out "first_red: --triage writes each exercise's verdict" \
	"$(printf 'work\t//mod\tex00')" -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --triage "$1/triage.tsv" < "$1/work.log" > /dev/null && cat "$1/triage.tsv"' \
	_ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken "first_red: --triage needs a file" \
	'--triage FILE' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --triage < "$1/work.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken "first_red: --cmd takes bazel or 42" \
	'--cmd bazel|42' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --cmd make < "$1/work.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# A test of the WHOLE module (deliverable_files: files outside every exercise
# folder) belongs to no exercise. It is filed under its own name, as a target
# a student can run, and never as an exercise not written yet: over the stub
# above, a files red of an exercise is demoted, and this one must not be.
printf '//mod:deliverable_files  FAILED in 0.1s\n' > "$WORK/fr/whole.log"
want_out "first_red: a red deliverable_files is to fix first" \
	'bazel test //mod:deliverable_files' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/whole.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ...never the next exercise to write" \
	'YOUR NEXT EXERCISE' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/whole.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"

# A TIMEOUT is red too. Captured from a loaded run in which the style gate ran
# out of time: a triage reading FAILED lines alone never listed it, and with
# nothing else red it said "nothing failed".
cat > "$WORK/fr/timeout.log" <<'FR_TIMEOUT'
TIMEOUT: //tools/tests:conventions (Summary)
//tools/tests:conventions                                               TIMEOUT in 60.2s

Executed 780 out of 780 tests: 771 tests pass and 9 fail locally.
FR_TIMEOUT
want_broken_none "first_red: a TIMEOUT is not 'nothing failed'" \
	'nothing failed' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/timeout.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ... it is counted red" \
	'1 red target(s)' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/timeout.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# INCOMPLETE: a test that started and was stopped under it, by a Ctrl-C or by
# --notest_keep_going cancelling what was still running. It says nothing, like
# NO STATUS, and a triage that reads neither called such a run clean.
cat > "$WORK/fr/incomplete.log" <<'FR_INCOMPLETE'
//tools/tests:selftest                                               INCOMPLETE

Executed 1 out of 2 tests: 1 test passes.
FR_INCOMPLETE
want_red "first_red: an INCOMPLETE run is not complete" -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/incomplete.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ... and says a target never finished" \
	'1 target(s) never ran or never finished' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/incomplete.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# ... and it names no cause. Filed with FAILED, a TIMEOUT on a written output
# read "what it does is not what the test expects ... The table in that log
# names the case", over a log that has no table, from a run the machine's load
# had slowed.
printf 'int\tf(int a)\n{\n\treturn (a + 1);\n}\n' > "$WORK/fr/mod/deliverable/ex00/f.c"
printf '//mod:ex00_output  TIMEOUT in 60.0s\n' > "$WORK/fr/slow.log"
want_out "first_red: a TIMEOUT on a written output ran out of time" \
	'RAN OUT OF TIME' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/slow.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ... is never called a wrong output" \
	'wrong output' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/slow.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# A FAILED its runner stopped at the TEST's own time limit is filed with the
# TIMEOUTs too: the runner stops a run a few seconds before Bazel would and
# says so, in tools/runner_lib.sh's RL_OVERRUN_MARK, and a loaded machine
# stops a correct answer the same way. The log is read where Bazel names it,
# in "FAIL: ... (see PATH)" or on the line under the summary's FAILED. The
# logs are the library's own words, so a change to them reaches these arms.
# A case that ran out of its OWN cap is a hang, and stays a verdict.
mkdir -p "$WORK/fr/over" "$WORK/fr/hang"
env TEST_TIMEOUT=60 "$SH" -c '. "$1"; RL_TMO=7; RL_CLAMPED=1; rl_overrun "case 3 of 200"' \
	_ "$FR_TOOLS/runner_lib.sh" > "$WORK/fr/over/test.log" 2>&1
env TEST_TIMEOUT=60 "$SH" -c '. "$1"; RL_TMO=10; RL_CLAMPED=0; rl_overrun "case 3 of 200"' \
	_ "$FR_TOOLS/runner_lib.sh" > "$WORK/fr/hang/test.log" 2>&1
printf 'FAIL: //mod:ex00_output (Exit 1) (see %s)\n//mod:ex00_output  FAILED in 9.0s\n' \
	"$WORK/fr/over/test.log" > "$WORK/fr/over1.log"
printf '//mod:ex00_output  FAILED in 9.0s\n  %s\n' "$WORK/fr/over/test.log" > "$WORK/fr/over2.log"
printf '//mod:ex00_output  FAILED in 9.0s\n  %s\n' "$WORK/fr/hang/test.log" > "$WORK/fr/hang.log"
want_out "first_red: a runner stopped at the test's limit ran out of time" \
	'RAN OUT OF TIME' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/over1.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ... is never called a wrong output" \
	'not what the test' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/over1.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ... found by the summary's log line too" \
	'RAN OUT OF TIME' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/over2.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: a case over its own cap is still a verdict" \
	'not what the test' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/hang.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ... and never 'ran out of time'" \
	'RAN OUT OF TIME' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/hang.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# A sweep that had judged cases WRONG before the test's time ran out: its log
# has the runner's own wrong answers and then the sweep's stop. Filed with the
# timeouts, the wrong answers were hidden behind "machine busy, run it alone"
# (review of wave 3's runners). The log is the library's own words again.
mkdir -p "$WORK/fr/wrong"
env TEST_TIMEOUT=60 "$SH" -c '. "$1"; RL_NAME=sweep
	echo "sweep: FAIL — 2 of 5 case(s) judged wrong"
	RL_TMO=7; RL_CLAMPED=1; RL_STOP=budget; rl_sweep_stopped 5 40 2' \
	_ "$FR_TOOLS/runner_lib.sh" > "$WORK/fr/wrong/test.log" 2>&1
printf '//mod:ex00_output  FAILED in 9.0s\n  %s\n' "$WORK/fr/wrong/test.log" > "$WORK/fr/wrong.log"
want_out "first_red: a sweep with wrong answers, then out of time, is a verdict" \
	'not what the test' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/wrong.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ... never 'ran out of time'" \
	'RAN OUT OF TIME' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/wrong.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# A SHARDED test has one log per shard, listed under a "Stats over N runs"
# line in the summary, and the mark can be in any of them. The stand-in
# reader took only the first log line; the overrun reader dropped the path
# once a Stats line came between (the merge of the two readers, wave 3).
mkdir -p "$WORK/fr/shard1" "$WORK/fr/shard2"
printf 'a runner that finished its shard\n' > "$WORK/fr/shard1/test.log"
cp "$WORK/fr/over/test.log" "$WORK/fr/shard2/test.log"
printf '//mod:ex00_output  FAILED in 2 out of 2 in 9.0s\n  Stats over 2 runs: max = 9.0s, min = 1.0s, avg = 5.0s, dev = 4.0s\n  %s\n  %s\n' \
	"$WORK/fr/shard1/test.log" "$WORK/fr/shard2/test.log" > "$WORK/fr/sharded.log"
want_out "first_red: a mark in the second shard's log is read too" \
	'RAN OUT OF TIME' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/sharded.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# The Run contract's robust exit twins, one per c_program case, are one layer:
# a red C 11 ex05 read as seventeen one-off names (add_exit, sub_exit, ...).
printf '//mod:ex00_add_exit  FAILED in 0.1s\n//mod:ex00_sub_exit  FAILED in 0.1s\n' \
	> "$WORK/fr/exit.log"
want_out "first_red: exNN_<case>_exit targets are one exit layer" 'exit x2' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --all < "$1/exit.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ... nor sent to a table it has not got" \
	'names the case' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/slow.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# A red is filed by the level its target sits at, read from tools/defs_levels.bzl's
# _SUFFIX_LAYER and _RAISED -- never from a list of first_red's own, which
# knew `output` alone and filed Rush 00's _defense (the case the subject says
# the defense runs, at basic) under ALSO RED, "a rigour layer above what the
# grader checks". A raised output case is rigour, and a stub-green layer
# raised to strict (the names a subject gives, _prototype_names) is not FIX
# FIRST.
printf 'int\tf(int a)\n{\n\treturn (a + 1);\n}\n' > "$WORK/fr/mod/deliverable/ex00/f.c"
printf '//mod:ex00_rush03_defense  FAILED in 0.1s\n' > "$WORK/fr/defense.log"
printf '//mod:ex00_rush03_prototype_names  FAILED in 0.1s\n' > "$WORK/fr/names.log"
printf '//tools/tests/macro_fixtures/levels:ex00_raised_output  FAILED in 0.1s\n' \
	> "$WORK/fr/raised.log"
want_out "first_red: a basic output target of another name is the work" \
	'written; wrong output' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/defense.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ... never ALSO RED" 'ALSO RED' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/defense.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: a stub-green layer raised to strict is not FIX FIRST" \
	'FIX FIRST' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/names.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: an output case _RAISED puts above basic is rigour" 'ALSO RED' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/raised.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# ...and named as it is (V56): its layer alone read "ex00 -- output" under
# ALSO RED, whose words are "these produce the right output".
want_out "first_red: ALSO RED names a raised target as it is" 'ex00 — raised_output' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/raised.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# Every basic layer but output is FIX FIRST on a written exercise, not only
# the five a stub passes: a basic allocfail red, which waits for the output
# and so means the output is right, was filed under ALSO RED's "a rigour
# layer above what the grader checks" (V197). Its robust _leaks twin stays
# rigour.
printf '//mod:ex00_allocfail  FAILED in 0.1s\n' > "$WORK/fr/allocfail.log"
printf '//mod:ex00_allocfail_leaks  FAILED in 0.1s\n' > "$WORK/fr/allocfail_leaks.log"
want_out "first_red: a basic allocfail red is FIX FIRST" 'FIX FIRST' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/allocfail.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ... never ALSO RED" 'ALSO RED' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/allocfail.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...while its robust _leaks twin is rigour" 'ALSO RED' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/allocfail_leaks.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# A contract that declares memory_graded puts the valgrind layer at basic
# (tools/defs_levels.bzl's _layer_level), and the targets' tags say so: a red there
# is a KO, FIX FIRST, never ALSO RED's "a rigour layer above what the grader
# checks". Read from the module's own contract, a comment that names the
# field being none; the same red elsewhere stays rigour.
mkdir -p "$WORK/fr/gmod/deliverable/ex00" "$WORK/fr/cmod/deliverable/ex00"
fr_graded() {  # fr_graded MODDIR PREFIX -- PREFIX "" declares it, "# " only mentions it
	printf 'subject(\n    grader = "both",\n    group = False,\n    %smemory_graded = {\n    %s    "access": "Toy, p.1: \\"Touch only what you own.\\"",\n    %s    "leaks": "Toy, p.1: \\"Free what you allocate.\\"",\n    %s},\n    exercises = {\n        "00": exercise(page = 1, dir = "ex00/", files = [], allowed = None),\n    },\n)\n' \
		"$2" "$2" "$2" "$2" > "$1/BUILD.bazel"
	printf 'int\tf(int a)\n{\n\treturn (a + 1);\n}\n' > "$1/deliverable/ex00/f.c"
}
fr_graded "$WORK/fr/gmod" ""
fr_graded "$WORK/fr/cmod" "# "
printf '//gmod:ex00_memcheck  FAILED in 0.1s\n' > "$WORK/fr/graded.log"
printf '//cmod:ex00_memcheck  FAILED in 0.1s\n' > "$WORK/fr/graded_comment.log"
printf '//mod:ex00_memcheck  FAILED in 0.1s\n' > "$WORK/fr/ungraded.log"
want_out "first_red: a valgrind red where the contract declares memory_graded is FIX FIRST" \
	'FIX FIRST' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/graded.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ... never ALSO RED" 'ALSO RED' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/graded.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...and where a comment only names the field, ALSO RED" 'ALSO RED' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/graded_comment.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...as everywhere the contract does not declare it" 'ALSO RED' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/ungraded.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# Declared is any value but None, however Starlark spells it: the reading
# took `memory_graded = "` as the one declaration, and filed a dict, or one
# in parentheses, as none (//tools/tests:units_parity holds the reading to
# every contract the macros read).
fr_spelled() {  # fr_spelled NAME VALUE-LINES -- a module whose memory_graded is spelled so
	mkdir -p "$WORK/fr/$1"
	printf 'subject(\n    grader = "both",\n    group = False,\n%s\n    exercises = {\n        "00": exercise(page = 1, dir = "ex00/", files = [], allowed = None),\n    },\n)\n' \
		"$2" > "$WORK/fr/$1/BUILD.bazel"
}
fr_spelled gparen '    memory_graded = (\n        _TOY_GRADED\n    ),'
fr_spelled gname '    memory_graded=_TOY_GRADED,'
fr_spelled gnone '    memory_graded = None,'
fr_spelled gnonex '    memory_graded = Nonesuch,'
# What --graded reads, as "reads: <it>." (grep -F: "graded" is in "not graded").
fr_reads() { printf 'reads: %s.\n' "$("$SH" "$FR_TOOLS/first_red.sh" --graded "$1")"; }
want_out "first_red --graded: a dict over several lines is a declaration" 'reads: graded.' -- \
	fr_reads "$WORK/fr/gmod"
want_out "first_red --graded: ...a comment naming the field is none" 'reads: not graded.' -- \
	fr_reads "$WORK/fr/cmod"
want_out "first_red --graded: ...a value in parentheses is one" 'reads: graded.' -- \
	fr_reads "$WORK/fr/gparen"
want_out "first_red --graded: ...a name bound above is one" 'reads: graded.' -- \
	fr_reads "$WORK/fr/gname"
want_out "first_red --graded: ...None is none" 'reads: not graded.' -- \
	fr_reads "$WORK/fr/gnone"
want_out "first_red --graded: ...but a name that begins None is one" 'reads: graded.' -- \
	fr_reads "$WORK/fr/gnonex"
# A module row lists the exercises that are red, a range only where every
# one in it is: "ex00-ex05" read as six red exercises over three (V56).
printf '//mod:ex00_output  FAILED in 0.1s\n//mod:ex04_output  FAILED in 0.1s\n//mod:ex05_output  FAILED in 0.1s\n' \
	> "$WORK/fr/gaps.log"
want_out "first_red: a module row lists its red exercises" 'ex00, ex04-ex05' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/gaps.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ...never a span over green ones" 'ex00-ex05' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/gaps.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# Every other file beside it, and the refusal that names this one: each file
# it reads is refused in the same words, so with units.awk missing too the
# arm passed on that refusal, and went on passing with the check of
# defs_levels.bzl deleted.
want_broken "first_red: without tools/defs_levels.bzl beside it, it refuses" \
	'defs_levels.bzl is not beside it' -- \
	"$SH" -c 'mkdir -p "$1/nodefs" && cp "$3/first_red.sh" "$3/standin.sh" "$3/runner_lib.sh" "$3/units.awk" "$3/stub_check.sh" "$1/nodefs/" && cd "$1" && "$2" "$1/nodefs/first_red.sh" < "$1/defense.log"' \
	_ "$WORK/fr" "$SH" "$FR_TOOLS"
# And without tools/units.awk beside it, the one reader of a contract's text:
# every exercise, folder and function of a module would be unknown, and every
# red filed as if the module had none. Each mode that reads a contract says so.
st_mine && mkdir -p "$WORK/fr/nounits" && cp "$FR_TOOLS/first_red.sh" "$FR_TOOLS/standin.sh" \
	"$FR_TOOLS/runner_lib.sh" "$FR_TOOLS/defs_levels.bzl" "$FR_TOOLS/stub_check.sh" "$WORK/fr/nounits/"
want_broken "first_red: without tools/units.awk beside it, it refuses" \
	'units.awk is not beside it' -- \
	"$SH" -c 'cd "$1" && "$2" "$1/nounits/first_red.sh" < "$1/defense.log"' _ "$WORK/fr" "$SH"
want_broken "first_red: ...--written refuses as well" 'units.awk is not beside it' -- \
	"$SH" "$WORK/fr/nounits/first_red.sh" --written "$WORK/fr/mod"
want_broken "first_red: ...--turnin as well" 'units.awk is not beside it' -- \
	"$SH" "$WORK/fr/nounits/first_red.sh" --turnin "$WORK/fr/mod" ex00
want_broken "first_red: ...and --unit-of refuses too" 'units.awk is not beside it' -- \
	"$SH" -c '"$1" "$2" --unit-of "$3" < /dev/null' _ "$SH" "$WORK/fr/nounits/first_red.sh" "$WORK/fr/mod"
# And the one layer a contract lowers to basic, read from the same file as
# every other level fact: a copy typed into first_red.sh kept filing a red of
# the old layer as the student's to fix first once the build named another.
st_mine && mkdir -p "$WORK/fr/nograded" && cp "$FR_TOOLS/first_red.sh" "$FR_TOOLS/standin.sh" \
	"$FR_TOOLS/runner_lib.sh" "$FR_TOOLS/units.awk" "$FR_TOOLS/stub_check.sh" "$WORK/fr/nograded/" &&
	sed '/^_GRADED_LAYER = /d' "$FR_TOOLS/defs_levels.bzl" > "$WORK/fr/nograded/defs_levels.bzl"
want_broken "first_red: a defs_levels.bzl without _GRADED_LAYER makes it refuse" \
	'_GRADED_LAYER' -- \
	"$SH" -c 'cd "$1" && "$2" "$1/nograded/first_red.sh" < "$1/defense.log"' _ "$WORK/fr" "$SH"

# A red OUTPUT over a WRITTEN file is a bug, not an unwritten exercise. Calling
# a finished rush "not written yet" over one wrong file descriptor sent its
# author looking for why Bazel could not see their files. Same toy, both ways,
# and a second exercise left a stub for the module that is only partly done.
printf 'int\tf(int a)\n{\n\treturn (a + 1);\n}\n' > "$WORK/fr/mod/deliverable/ex00/f.c"
want_out "first_red: written + red output is not unwritten" \
	'written; wrong output' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/work.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ... and never gets the stub sentence" \
	'what an unwritten exercise looks' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/work.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
mkdir -p "$WORK/fr/mod/deliverable/ex01"
printf '%s\n\nint\tg(int a)\n{\n\t(void)a;\n\treturn (0);\n}\n' "$FR_H" \
	> "$WORK/fr/mod/deliverable/ex01/g.c"
printf '//mod:ex00_output  FAILED in 0.1s\n//mod:ex01_output  FAILED in 0.1s\n' > "$WORK/fr/mix.log"
want_out "first_red: written + stub in one module is partly" \
	'partly written' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/mix.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# A shell exercise is its generator: deliverable/ is only what it wrote.
mkdir -p "$WORK/fr/shmod/generators"
printf '#!/bin/sh\ntouch z\n' > "$WORK/fr/shmod/generators/ex00.sh"
printf '//shmod:ex00_output  FAILED in 0.1s\n' > "$WORK/fr/sh.log"
want_out "first_red: a written generator is written" \
	'written; wrong output' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/sh.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"

# A BUILD error, read from REAL Bazel output: stubs broken in a throwaway copy
# of the tree, the run captured, then trimmed (the workspace path shortened,
# progress lines and most PASSED and NO STATUS lines dropped). A triage that
# reads only FAILED lines printed "nothing failed" and exited 0 when no test
# ran at all, and "not written yet" on an exercise whose output FAILED TO
# BUILD.
FR_RUN='cd "$1" && "$2" "$3/first_red.sh" < "$1/$4"'
#
# A leftover main() in C 01 ex06, run WITHOUT --keep_going: the link fails,
# and 113 of the module's 117 targets never run.
cat > "$WORK/fr/link_nok.log" <<'FR_LINK'
INFO: Analyzed 143 targets (1 packages loaded, 223 targets configured).
ERROR: /home/you/42/c-piscine/c-piscine-c-01/BUILD.bazel:49:11: Linking c-piscine/c-piscine-c-01/ex06_bin failed: (Exit 1): clang.sh failed: error executing CppLink command (from cc_binary rule target //c-piscine/c-piscine-c-01:ex06_bin) tools/cc_toolchain/clang.sh @bazel-out/k8-fastbuild/bin/c-piscine/c-piscine-c-01/ex06_bin-0.params
Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging
external/+deb_archive+binutils_x86_64_linux_gnu/usr/bin/x86_64-linux-gnu-ld.gold: error: bazel-out/k8-fastbuild/bin/c-piscine/c-piscine-c-01/_objs/ft_strlen/ft_strlen.pic.o: multiple definition of 'main'
external/+deb_archive+binutils_x86_64_linux_gnu/usr/bin/x86_64-linux-gnu-ld.gold: bazel-out/k8-fastbuild/bin/c-piscine/c-piscine-c-01/_objs/ex06_bin/test_strlen.pic.o: previous definition here
clang: error: linker command failed with exit code 1 (use -v to see invocation)
INFO: Elapsed time: 1.722s, Critical Path: 0.70s
ERROR: Build did NOT complete successfully
//c-piscine/c-piscine-c-01:ex00_compile_clang                         NO STATUS
//c-piscine/c-piscine-c-01:ex00_compile_gcc                           NO STATUS
//c-piscine/c-piscine-c-01:ex06_output                          FAILED TO BUILD

Executed 3 out of 117 tests: 3 tests pass, 1 fails to build, and 113 were skipped.
FR_LINK
want_red "first_red: a stopped build exits 1" -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" link_nok.log
want_out "first_red: a link error is DOES NOT BUILD" \
	'DOES NOT BUILD' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" link_nok.log
want_out "first_red: ... with the linker's own line" \
	"ft_strlen.o: multiple definition of 'main'" -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" link_nok.log
want_out "first_red: ... and says the rest never ran" \
	'113 target(s) never ran' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" link_nok.log

# A missing semicolon in C 11 ex00, WITH --keep_going: everything else ran, and
# ex00's output is FAILED TO BUILD -- which is not an unwritten exercise.
cat > "$WORK/fr/compile_k.log" <<'FR_COMPILE'
INFO: Analyzed 162 targets (0 packages loaded, 0 targets configured).
ERROR: /home/you/42/c-piscine/c-piscine-c-11/BUILD.bazel:3:11: Compiling c-piscine/c-piscine-c-11/deliverable/ex00/ft_foreach.c failed: (Exit 1): clang.sh failed: error executing CppCompile command (from cc_library rule target //c-piscine/c-piscine-c-11:ft_foreach) tools/cc_toolchain/clang.sh -U_FORTIFY_SOURCE -fstack-protector -Wall -Wthread-safety -Wself-assign -Wno-free-nonheap-object -fcolor-diagnostics -fno-omit-frame-pointer -MD -MF ... (remaining 22 arguments skipped)

Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging
c-piscine/c-piscine-c-11/deliverable/ex00/ft_foreach.c:16:3: error: expected expression
        (void)length;
         ^
c-piscine/c-piscine-c-11/deliverable/ex00/ft_foreach.c:13:31: error: unused parameter 'length' [-Werror,-Wunused-parameter]
void    ft_foreach(int *tab, int length, void (*f)(int))
                                 ^
2 errors generated.
FAIL: //c-piscine/c-piscine-c-11:ex00_compile_gcc (Exit 1) (see /tmp/bazelcache/x/execroot/_main/bazel-out/k8-fastbuild/testlogs/c-piscine/c-piscine-c-11/ex00_compile_gcc/test.log)
INFO: Build succeeded for only 153 of 162 top-level targets
ERROR: Build did NOT complete successfully
//c-piscine/c-piscine-c-11:ex00_diff                            FAILED TO BUILD
//c-piscine/c-piscine-c-11:ex00_diff_asan                       FAILED TO BUILD
//c-piscine/c-piscine-c-11:ex00_memcheck                        FAILED TO BUILD
//c-piscine/c-piscine-c-11:ex00_output                          FAILED TO BUILD
//c-piscine/c-piscine-c-11:ex00_perf                            FAILED TO BUILD
(Skipping other failed to build tests)
//c-piscine/c-piscine-c-11:ex00_norm                                     PASSED in 1.4s
//c-piscine/c-piscine-c-11:ex00_compile_gcc                              FAILED in 0.1s

Executed 108 out of 139 tests: 105 tests pass, 6 fail to build, and 28 fail locally.
FR_COMPILE
want_out "first_red: a compile error shows the compiler line" \
	'deliverable/ex00/ft_foreach.c:16:3: error: expected expression' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" compile_k.log
want_broken_none "first_red: FAILED TO BUILD is not 'not written yet'" \
	'not written yet' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" compile_k.log
want_out "first_red: Bazel's short FAILED TO BUILD list is flagged" \
	'counted 6 target(s) that failed to build and listed 5' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" compile_k.log
# The layers that did not build, as a list that starts with its first layer.
# Merged one layer at a time (a library's functions share their exercise's
# line), the list once began ", " under mawk, which creates the element on
# the left of an assignment before it reads the right: "ex03 — , memcheck,
# output", for every module. The whole line, so a stray separator anywhere
# in it is red.
cat > "$WORK/fr/two_ftb.log" <<'FR_TWO'
ERROR: /home/you/42/c-piscine/c-piscine-c-05/BUILD.bazel:3:11: Compiling c-piscine/c-piscine-c-05/deliverable/ex03/ft_recursive_power.c failed: (Exit 1): clang.sh failed: error executing CppCompile command (from cc_library rule target //c-piscine/c-piscine-c-05:ft_recursive_power) tools/cc_toolchain/clang.sh -MD -MF ... (remaining 22 arguments skipped)
c-piscine/c-piscine-c-05/deliverable/ex03/ft_recursive_power.c:16:3: error: expected expression
1 error generated.
ERROR: Build did NOT complete successfully
//c-piscine/c-piscine-c-05:ex03_memcheck                        FAILED TO BUILD
//c-piscine/c-piscine-c-05:ex03_output                          FAILED TO BUILD

Executed 0 out of 2 tests: 2 fail to build.
FR_TWO
want_out "first_red: what did not build is listed from its first layer" \
	'|      //c-piscine/c-piscine-c-05 ex03 — memcheck, output|' -- \
	"$SH" -c "$FR_RUN"' | sed -n "/ — memcheck/s/.*/|&|/p"' _ "$WORK/fr" "$SH" "$FR_TOOLS" two_ftb.log
want_broken_none "first_red: ...and never with a separator first" ' — , ' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" compile_k.log

# Bazel lists the first five FAILED TO BUILD targets and no more, so a module
# can be named by its compiler line alone. Crafted from the capture above: its
# compiler line, none of its FAILED TO BUILD lines, and a red in C 10. The
# table once left such a module out while the triage named it, and its count
# said one module where the table showed two.
cat > "$WORK/fr/unlisted_k.log" <<'FR_UNLISTED'
ERROR: /home/you/42/c-piscine/c-piscine-c-11/BUILD.bazel:3:11: Compiling c-piscine/c-piscine-c-11/deliverable/ex00/ft_foreach.c failed: (Exit 1): clang.sh failed: error executing CppCompile command (from cc_library rule target //c-piscine/c-piscine-c-11:ft_foreach) tools/cc_toolchain/clang.sh -U_FORTIFY_SOURCE -fstack-protector -Wall -Wthread-safety -Wself-assign -Wno-free-nonheap-object -fcolor-diagnostics -fno-omit-frame-pointer -MD -MF ... (remaining 22 arguments skipped)
c-piscine/c-piscine-c-11/deliverable/ex00/ft_foreach.c:16:3: error: expected expression
2 errors generated.
ERROR: Build did NOT complete successfully
//c-piscine/c-piscine-c-10:ex01_two_output                               FAILED in 0.1s

Executed 250 out of 256 tests: 249 tests pass, 6 fail to build, and 1 fails locally.
FR_UNLISTED
want_out "first_red: a module named by a compiler line alone has a row" \
	"$(printf '      %-22s %5s  %-24s %s' c-11 - 'does not build' ex00)" -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" unlisted_k.log
want_out "first_red: ... and the count above the table says so" \
	'and 1 more that do not build' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" unlisted_k.log

# C 13 ex03 with ft_btree.h deleted, WITH --keep_going: Bazel names the
# turn-in file as a missing input, and the file is what the student has to put
# back.
cat > "$WORK/fr/missing_k.log" <<'FR_MISSING'
ERROR: /home/you/42/c-piscine/c-piscine-c-13/BUILD.bazel:55:11: RunfilesTree c-piscine/c-piscine-c-13/ex03_forbidden.runfiles failed: missing input file '//c-piscine/c-piscine-c-13:deliverable/ex03/ft_btree.h'
ERROR: /home/you/42/c-piscine/c-piscine-c-13/BUILD.bazel:55:11: RunfilesTree c-piscine/c-piscine-c-13/ex03_forbidden.runfiles failed: 1 input file(s) do not exist
ERROR: /home/you/42/c-piscine/c-piscine-c-13/BUILD.bazel:55:11: Compiling c-piscine/c-piscine-c-13/deliverable/ex03/btree_apply_suffix.c failed: missing input file '//c-piscine/c-piscine-c-13:deliverable/ex03/ft_btree.h'
INFO: Analyzed 134 targets (0 packages loaded, 0 targets configured).
INFO: Build succeeded for only 119 of 134 top-level targets
ERROR: Build did NOT complete successfully
//c-piscine/c-piscine-c-13:ex03_compile_clang                   FAILED TO BUILD
//c-piscine/c-piscine-c-13:ex03_compile_gcc                     FAILED TO BUILD
(Skipping other failed to build tests)
//c-piscine/c-piscine-c-13:ex03_files                                    FAILED in 0.1s

Executed 73 out of 109 tests: 89 tests pass, 12 fail to build, and 8 fail locally.
FR_MISSING
want_out "first_red: a missing turn-in file is named" \
	'missing turn-in file: c-piscine/c-piscine-c-13/deliverable/ex03/ft_btree.h' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" missing_k.log

# Rush 02's Makefile renamed to makefile, WITHOUT --keep_going: analysis fails,
# and Bazel runs no test at all -- not even the files layer that would say so.
cat > "$WORK/fr/analysis_nok.log" <<'FR_ANALYSIS'
ERROR: /home/you/42/c-piscine/c-piscine-rush-02/BUILD.bazel:42:7: in args attribute of sh_test rule //c-piscine/c-piscine-rush-02:ex00_build: label '//c-piscine/c-piscine-rush-02:deliverable/ex00/Makefile' in $(location) expression is not a declared prerequisite of this rule. Since this rule was created by the macro 'c_make', the error might have been caused by the macro implementation
ERROR: /home/you/42/c-piscine/c-piscine-rush-02/BUILD.bazel:42:7: Analysis of target '//c-piscine/c-piscine-rush-02:ex00_build' (config: 76b99e4) failed
Use --verbose_failures to see the command lines of failed build steps.
ERROR: Analysis of target '//c-piscine/c-piscine-rush-02:ex00_build' failed; build aborted
INFO: Elapsed time: 0.473s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
ERROR: Build did NOT complete successfully
ERROR: No test targets were found, yet testing was requested
FR_ANALYSIS
want_out "first_red: no test ran: the missing Makefile is named" \
	'missing turn-in file: c-piscine/c-piscine-rush-02/deliverable/ex00/Makefile' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" analysis_nok.log
want_broken_none "first_red: no test ran is never 'nothing failed'" \
	'nothing failed' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" analysis_nok.log

# The same, WITH --keep_going: the rest runs, and the targets Bazel could not
# analyse drop out of the summary, which then reads "Executed 5 out of 5
# tests". The capture listed 29 such targets; five are kept here.
cat > "$WORK/fr/analysis_k.log" <<'FR_ANALYSIS_K'
ERROR: /home/you/42/c-piscine/c-piscine-rush-02/BUILD.bazel:42:7: in args attribute of sh_test rule //c-piscine/c-piscine-rush-02:ex00_build: label '//c-piscine/c-piscine-rush-02:deliverable/ex00/Makefile' in $(location) expression is not a declared prerequisite of this rule. Since this rule was created by the macro 'c_make', the error might have been caused by the macro implementation
ERROR: /home/you/42/c-piscine/c-piscine-rush-02/BUILD.bazel:42:7: Analysis of target '//c-piscine/c-piscine-rush-02:ex00_build' (config: 76b99e4) failed
ERROR: /home/you/42/c-piscine/c-piscine-rush-02/BUILD.bazel:77:10: Analysis of target '//c-piscine/c-piscine-rush-02:ex00_bin_asan_build' (config: f74d281) failed
INFO: Analyzed 35 targets (0 packages loaded, 0 targets configured).
WARNING: errors encountered while analyzing target '//c-piscine/c-piscine-rush-02:ex00_custom_value_valgrind', it will not be built.
Analysis failed
WARNING: errors encountered while analyzing target '//c-piscine/c-piscine-rush-02:ex00_subject_error_output', it will not be built.
Analysis failed
WARNING: errors encountered while analyzing target '//c-piscine/c-piscine-rush-02:ex00_build', it will not be built.
WARNING: errors encountered while analyzing target '//c-piscine/c-piscine-rush-02:ex00_subject_42_output', it will not be built.
Analysis failed
WARNING: errors encountered while analyzing target '//c-piscine/c-piscine-rush-02:ex00_bin_build', it will not be built.
INFO: Build succeeded for only 6 of 35 top-level targets
INFO: Found 1 target and 5 test targets...
ERROR: command succeeded, but not all targets were analyzed
ERROR: Build did NOT complete successfully
//c-piscine/c-piscine-rush-02:ex00_files                                 FAILED in 0.0s

Executed 5 out of 5 tests: 4 tests pass and 1 fails locally.
FR_ANALYSIS_K
want_out "first_red: a target Bazel could not analyse is counted" \
	'could not analyse 5 target(s)' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" analysis_k.log
want_out "first_red: ... and the missing Makefile is named" \
	'missing turn-in file: c-piscine/c-piscine-rush-02/deliverable/ex00/Makefile' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" analysis_k.log

# The negative premises. A run can stop with nothing wrong in the build, and
# DOES NOT BUILD would then send the student hunting a compile error that is
# not there. A red test under --notest_keep_going --nokeep_going (C 11, stubs
# that build) ends the run:
cat > "$WORK/fr/testabort_nok.log" <<'FR_TESTABORT'
INFO: Analyzed 162 targets (0 packages loaded, 0 targets configured).
FAIL: //c-piscine/c-piscine-c-11:ex05_unknownword_output (Exit 1) (see /tmp/bazelcache/x/execroot/_main/bazel-out/k8-fastbuild/testlogs/c-piscine/c-piscine-c-11/ex05_unknownword_output/test.log)
ERROR: /home/you/42/c-piscine/c-piscine-c-11/BUILD.bazel:30:10: Testing //c-piscine/c-piscine-c-11:ex05_unknownword_output failed: Test failed, aborting
Use --verbose_failures to see the command lines of failed build steps.
ERROR: Test failed, aborting
INFO: Elapsed time: 0.640s, Critical Path: 0.24s
INFO: Build completed, 1 test FAILED, 25 total actions
//c-piscine/c-piscine-c-11:ex00_compile_clang                         NO STATUS
//c-piscine/c-piscine-c-11:ex05_unknownword_output                       FAILED in 0.1s

Executed 1 out of 139 tests: 1 fails locally and 138 were skipped.
FR_TESTABORT
want_broken_none "first_red: a run a red test stopped is no build error" \
	'DOES NOT BUILD' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" testabort_nok.log
want_out "first_red: ... it says the run stopped, and what never ran" \
	'138 target(s) never ran' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" testabort_nok.log
want_red "first_red: ... and exits 1" -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" testabort_nok.log

# Ctrl-C part way through the same module:
cat > "$WORK/fr/interrupt.log" <<'FR_INTERRUPT'
INFO: Analyzed 162 targets (0 packages loaded, 0 targets configured).
FAIL: //c-piscine/c-piscine-c-11:ex01_output (Exit 1) (see /tmp/bazelcache/x/execroot/_main/bazel-out/k8-fastbuild/testlogs/c-piscine/c-piscine-c-11/ex01_output/test.log)

Bazel caught interrupt signal; cancelling pending invocation.

ERROR: build interrupted
INFO: Elapsed time: 4.014s, Critical Path: 2.50s
INFO: 140 processes: 8 internal, 264 processwrapper-sandbox.
ERROR: Build did NOT complete successfully
//c-piscine/c-piscine-c-11:ex01_output                                   FAILED in 0.1s

Executed 132 out of 139 tests: 110 tests pass, 22 fail locally, and 7 were skipped.
FR_INTERRUPT
want_out "first_red: an interrupted run says so" \
	'INTERRUPTED' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" interrupt.log
want_broken_none "first_red: ... and blames no build" \
	'DOES NOT BUILD' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" interrupt.log

# A command that named no test at all (a binary, here): Bazel builds it and
# exits 4. Nothing failed, and nothing was checked either.
cat > "$WORK/fr/notest.log" <<'FR_NOTEST'
INFO: Analyzed target //tools:norminette (0 packages loaded, 0 targets configured).
INFO: Found 1 target and 0 test targets...
Target //tools:norminette up-to-date:
  bazel-bin/tools/norminette
INFO: Elapsed time: 0.597s, Critical Path: 0.05s
INFO: 4 processes: 4 internal.
INFO: Build completed successfully, 4 total actions
ERROR: No test targets were found, yet testing was requested
FR_NOTEST
want_out "first_red: a command with no test in it says so" \
	'NO TEST RAN' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" notest.log
want_broken_none "first_red: ... and blames no build for it" \
	'DOES NOT BUILD' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" notest.log

# And compiler lines inside a TEST log, printed by --test_output=errors on a
# tree that builds: C 08 ex00's stub header, which the compile layer cannot
# build the subject's main against. A red test, not a build error.
cat > "$WORK/fr/testout.log" <<'FR_TESTOUT'
INFO: Analyzed 2 targets (1 packages loaded, 5 targets configured).
FAIL: //c-piscine/c-piscine-c-08:ex00_compile_clang (Exit 1) (see /tmp/bazelcache/x/execroot/_main/bazel-out/k8-fastbuild/testlogs/c-piscine/c-piscine-c-08/ex00_compile_clang/test.log)
INFO: From Testing //c-piscine/c-piscine-c-08:ex00_compile_clang:
==================== Test output for //c-piscine/c-piscine-c-08:ex00_compile_clang:
c-piscine/c-piscine-c-08/tests/ex00/test_ft_h.c:12:2: error: implicit declaration of function 'ft_putchar' is invalid in C99 [-Werror,-Wimplicit-function-declaration]
8 errors generated.
compile_check: clang-12 FAIL c-piscine/c-piscine-c-08/tests/ex00/test_ft_h.c
================================================================================
INFO: Found 2 test targets...
INFO: Build completed, 1 test FAILED, 11 total actions
//c-piscine/c-piscine-c-08:ex00_norm                                     PASSED in 2.9s
//c-piscine/c-piscine-c-08:ex00_compile_clang                            FAILED in 0.5s

Executed 2 out of 2 tests: 1 test passes and 1 fails locally.
FR_TESTOUT
want_broken_none "first_red: a compiler line in a test log is no build" \
	'DOES NOT BUILD' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" testout.log
want_green "first_red: ... and exits 0" -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" testout.log

# And a build error in no file of the student's: the oracle's entry point broken
# (an unclosed delimiter) under C 01 answers that pass, WITH --keep_going. Its
# diff and perf targets say FAILED TO BUILD like a compile error would, and the
# triage once called that "DOES NOT BUILD ... graded 0" over two exercises
# nobody had touched. No line names a file of theirs, so it is a stop, not a
# verdict. The capture listed 94 PASSED lines; two are kept.
cat > "$WORK/fr/harness_k.log" <<'FR_HARNESS'
INFO: Analyzed 143 targets (0 packages loaded, 160 targets configured).
ERROR: /home/you/42/oracle/BUILD.bazel:9:12: Compiling Rust bin oracle (24 files) failed: (Exit 1): process_wrapper failed: error executing Rustc command (from rust_binary rule target //oracle:oracle) bazel-out/k8-opt-exec/bin/external/rules_rust+/util/process_wrapper/process_wrapper --subst 'pwd=${pwd}' --subst 'exec_root=${exec_root}' --subst 'output_base=${output_base}' -- ... (remaining 2 arguments skipped)

Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging
error: this file contains an unclosed delimiter
   --> oracle/src/main.rs:160:14
    |
160 | fn broken( {
    |          - -^
    |          | |
    |          | unclosed delimiter
    |          unclosed delimiter

error: aborting due to 1 previous error

INFO: Build succeeded for only 120 of 143 top-level targets
INFO: Found 26 targets and 117 test targets...
ERROR: Build did NOT complete successfully
//c-piscine/c-piscine-c-01:ex02_diff                            FAILED TO BUILD
//c-piscine/c-piscine-c-01:ex02_diff_asan                       FAILED TO BUILD
//c-piscine/c-piscine-c-01:ex02_perf                            FAILED TO BUILD
//c-piscine/c-piscine-c-01:ex03_diff                            FAILED TO BUILD
//c-piscine/c-piscine-c-01:ex03_diff_asan                       FAILED TO BUILD
(Skipping other failed to build tests)
//c-piscine/c-piscine-c-01:ex02_output                                   PASSED in 0.2s
//c-piscine/c-piscine-c-01:ex03_output                                   PASSED in 0.2s

Executed 94 out of 117 tests: 94 tests pass and 23 fail to build.
FR_HARNESS
want_broken_none "first_red: a broken harness file is no DOES NOT BUILD" \
	'DOES NOT BUILD' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" harness_k.log
want_broken_none "first_red: ... and grades nothing 0" \
	'graded 0' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" harness_k.log
want_out "first_red: ... it says no line names the student's files" \
	'no line names a file of yours' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" harness_k.log
want_out "first_red: ... quotes the harness's own error" \
	'ERROR: Compiling Rust bin oracle (24 files) failed' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" harness_k.log
want_out "first_red: ... and the module did not run" \
	"$(printf '      %-22s %5d  %-24s %s' c-01 5 'did not run' ex02-ex03)" -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" harness_k.log
want_red "first_red: ... and exits 1, since part of it never ran" -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" harness_k.log
# The bare label, with no exercise and no error line at all.
printf '//tools/tests:selftest                              FAILED TO BUILD\n' > "$WORK/fr/label.log"
want_broken_none "first_red: a FAILED TO BUILD label alone blames no one" \
	'DOES NOT BUILD' -- \
	"$SH" -c "$FR_RUN" _ "$WORK/fr" "$SH" "$FR_TOOLS" label.log

# CODE THAT DOES NOT BUILD fails its tests, not the build: its programs are
# stand-ins (tools/standin.sh), and a FAILED test whose log holds the stand-in's
# mark found no wrong answer -- nothing was built. first_red reads the logs
# and files such an exercise under DOES NOT BUILD, with the compiler's line,
# never "not written yet". Two ways a log reaches it: printed inline by
# --test_output=errors, and as the test.log path Bazel prints under a FAILED
# line. The logs below are the runner's real output on the real stand-in.
mkdir -p "$WORK/fr/logs/standin" "$WORK/fr/logs/noturnin" "$WORK/fr/logs/plain"
printf 'int\tf(int a)\n{\n\treturn (a + 1);\n}\n' > "$WORK/fr/mod/deliverable/ex00/f.c"
"$SH" "$TOOLS/diff_output.sh" --bin "$STANDIN_BIN" --expected "$WORK/exp.txt" \
	> "$WORK/fr/logs/standin/test.log" 2>&1
{
	printf '==================== Test output for //mod:ex00_output:\n'
	cat "$WORK/fr/logs/standin/test.log"
	printf '================================================================================\n'
	printf '//mod:ex00_output  FAILED in 0.1s\n'
} > "$WORK/fr/standin_inline.log"
printf '//mod:ex00_output  FAILED in 0.1s\n  %s\n' "$WORK/fr/logs/standin/test.log" \
	> "$WORK/fr/standin_path.log"
for _frl in standin_inline standin_path; do
	want_out "first_red: a stand-in in a test log does not build ($_frl)" \
		'DOES NOT BUILD' -- \
		"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/$4.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS" "$_frl"
	want_out "first_red: ...and says what the build said ($_frl)" \
		'YOUR CODE DID NOT BUILD' -- \
		"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/$4.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS" "$_frl"
	want_broken_none "first_red: ...never a wrong output ($_frl)" \
		'wrong output' -- \
		"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/$4.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS" "$_frl"
done
# The compiler's line naming a turn-in file is the one it shows, over the
# stand-in's headline.
{
	printf '==================== Test output for //mod:ex00_output:\n'
	printf 'diff_output: FAIL — your code did not build\n'
	printf '  42-harness stand-in: no program was built from your code\n'
	printf '  YOUR CODE DID NOT BUILD — it does not compile.\n'
	printf '  mod/deliverable/ex00/f.c:4:1: error: expected ";" after return statement\n'
	printf '================================================================================\n'
	printf '//mod:ex00_output  FAILED in 0.1s\n'
} > "$WORK/fr/standin_line.log"
want_out "first_red: ...naming the file and line the compiler named" \
	'mod/deliverable/ex00/f.c:4:1' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/standin_line.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# A turn-in file that is not there fails its layers as NOT TURNED IN tests
# (tools/no_turnin.sh); that is the same bucket.
printf '//mod:ex00_norm  FAILED in 0.1s\n  %s\n' "$WORK/fr/logs/noturnin/test.log" > "$WORK/fr/noturnin.log"
"$SH" "$TOOLS/no_turnin.sh" --test //mod:ex00_norm --where mod/deliverable/ex00 \
	> "$WORK/fr/logs/noturnin/test.log" 2>&1
want_out "first_red: a file not turned in does not build either" \
	'NOT TURNED IN' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/noturnin.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# A GATED layer (ilp32, allocfail, cycles, norm's Notice reading) skips while
# its exercise has nothing to say; with nothing turned in it skips too, and
# NO_SKIP=1 turns that red like every other skip. It used to be red: one
# missing file was ten more reds at robust and complete than a file that does
# not compile, whose gated layers skip.
want_green "no_turnin: a gated layer with nothing turned in skips" -- \
	env -u NO_SKIP "$SH" "$TOOLS/no_turnin.sh" --test //mod:ex00_ilp32 \
		--where mod/deliverable/ex00 --gated
want_out "no_turnin: ...and says so" 'SKIP' -- \
	env -u NO_SKIP "$SH" "$TOOLS/no_turnin.sh" --test //mod:ex00_ilp32 \
		--where mod/deliverable/ex00 --gated
want_red "no_turnin: ...NO_SKIP=1 turns that skip red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/no_turnin.sh" --test //mod:ex00_ilp32 \
		--where mod/deliverable/ex00 --gated
want_red "no_turnin: an ungated layer is red without NO_SKIP" -- \
	env -u NO_SKIP "$SH" "$TOOLS/no_turnin.sh" --test //mod:ex00_norm \
		--where mod/deliverable/ex00
# A turn-in at the root of deliverable/ with its files one folder down, in an
# exNN/ the subject never names (tools/defs_test.bzl's _test() passes
# --misplaced when it finds one): "has none of the files" is true, and the command that moves
# them up is what the student needs next.
want_out "no_turnin: files kept in an exNN/ of a root turn-in: move up" \
	'git mv mod/deliverable/ex00/* mod/deliverable/' -- \
	env -u NO_SKIP "$SH" "$TOOLS/no_turnin.sh" --test //mod:ex00_norm \
		--where mod/deliverable --misplaced mod/deliverable/ex00
want_broken_none "no_turnin: ...never without such a folder" 'git mv' -- \
	env -u NO_SKIP "$SH" "$TOOLS/no_turnin.sh" --test //mod:ex00_norm \
		--where mod/deliverable

# AN EXERCISE NOT STARTED IS NOT BROKEN CODE. The stub Makefile of BSQ and
# Rush 02 only echoes, so the builder has nothing to compile and writes an
# EMPTY stand-in. Filed under DOES NOT BUILD, the README's
# `bazel test //... | sh tools/first_red.sh` sent every fresh clone to BSQ
# first, "graded 0". Over a stub it is an exercise not written yet; over a
# written Makefile that compiles nothing it does not build. The log is the
# output layer's real output on the builder's real stand-in.
mkdir -p "$WORK/fr/stubmk/deliverable/ex00" "$WORK/fr/wrmk/deliverable/ex00" "$WORK/fr/logs/empty"
printf 'NAME = prog\nSRC  =\n\n$(NAME):\n\t@echo "TODO: build $(NAME) from $(SRC)"\n\n.PHONY:\n' \
	> "$WORK/fr/stubmk/deliverable/ex00/Makefile"
printf 'NAME = prog\n\n$(NAME):\n\t@echo linking\n\tcc -o $(NAME) src/main.c\n' \
	> "$WORK/fr/wrmk/deliverable/ex00/Makefile"
fr_contract "$WORK/fr/stubmk" 00=ex00/
fr_contract "$WORK/fr/wrmk" 00=ex00/
"$SH" "$TOOLS/student_build.sh" --cc "$CC" --out "$WORK/fr/logs/empty/prog" --no-archive \
	--makefile "$WORK/fr/stubmk/deliverable/ex00/Makefile" > /dev/null 2>&1
: > "$WORK/fr/logs/empty/expected.txt"
"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/fr/logs/empty/prog" \
	--expected "$WORK/fr/logs/empty/expected.txt" > "$WORK/fr/logs/empty/test.log" 2>&1
for _frm in stubmk wrmk; do
	{
		printf '==================== Test output for //%s:ex00_output:\n' "$_frm"
		cat "$WORK/fr/logs/empty/test.log"
		printf '================================================================================\n'
		printf '//%s:ex00_output  FAILED in 0.1s\n' "$_frm"
	} > "$WORK/fr/empty_$_frm.log"
done
want_broken_none "first_red: an empty stand-in over a stub is no DOES NOT BUILD" \
	'DOES NOT BUILD' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/empty_stubmk.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...it is the next exercise, not written yet" \
	'not written yet' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/empty_stubmk.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_green "first_red: ...and the report is complete (exit 0)" -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/empty_stubmk.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: an empty stand-in over a WRITTEN Makefile does not build" \
	'DOES NOT BUILD' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/empty_wrmk.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...saying what the build found" \
	'compiles no .c files' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/empty_wrmk.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# The same two, turned in at the ROOT of deliverable/ by the one unit of a
# contract of units -- BSQ's layout, and every Common Core project's: there
# is no deliverable/ex00 to look in, and the Makefile is
# deliverable/Makefile. Looked for under ex00/ alone, a written one read as
# not written yet, and the broken build as the next exercise.
mkdir -p "$WORK/fr/stubroot/deliverable" "$WORK/fr/wrroot/deliverable/srcs"
cp "$WORK/fr/stubmk/deliverable/ex00/Makefile" "$WORK/fr/stubroot/deliverable/Makefile"
cp "$WORK/fr/wrmk/deliverable/ex00/Makefile" "$WORK/fr/wrroot/deliverable/Makefile"
fr_root "$WORK/fr/stubroot"
fr_root "$WORK/fr/wrroot"
# THE FOLDER IS THE CONTRACT'S, NEVER A GUESS. It was guessed: deliverable/ex00
# when that folder existed, else deliverable/ when no exNN folder did. So a
# root turn-in that still held an old ex00/ -- BSQ's layout before it moved to
# the root -- was read in that leftover folder, and an exNN/ turn-in whose
# folder was missing was read at the root.
mkdir -p "$WORK/fr/oldroot/deliverable/ex00" "$WORK/fr/noex/deliverable"
cp "$WORK/fr/wrmk/deliverable/ex00/Makefile" "$WORK/fr/oldroot/deliverable/Makefile"
cp "$WORK/fr/stubmk/deliverable/ex00/Makefile" "$WORK/fr/oldroot/deliverable/ex00/Makefile"
cp "$WORK/fr/wrmk/deliverable/ex00/Makefile" "$WORK/fr/noex/deliverable/Makefile"
fr_root "$WORK/fr/oldroot"
fr_contract "$WORK/fr/noex" 00=ex00/
# Each module's red output test, by its unit: MODULE:UNIT.
for _frm in stubroot:toyroot wrroot:toyroot oldroot:toyroot noex:ex00; do
	_fru=${_frm#*:}
	_frm=${_frm%%:*}
	{
		printf '==================== Test output for //%s:%s_output:\n' "$_frm" "$_fru"
		cat "$WORK/fr/logs/empty/test.log"
		printf '================================================================================\n'
		printf '//%s:%s_output  FAILED in 0.1s\n' "$_frm" "$_fru"
	} > "$WORK/fr/empty_$_frm.log"
done
want_out "first_red: a root turn-in's written Makefile does not build" \
	'DOES NOT BUILD' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/empty_wrroot.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ...and a root turn-in's stub one is no DOES NOT BUILD" \
	'DOES NOT BUILD' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/empty_stubroot.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: a root turn-in is read at the root, not in an old ex00/" \
	'DOES NOT BUILD' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/empty_oldroot.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ...and an ex00/ turn-in never at the root" \
	'DOES NOT BUILD' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/empty_noex.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: --turnin reads a contract's dir" 'deliverable/ex01' -- \
	"$SH" "$FR_TOOLS/first_red.sh" --turnin "$WORK/fr/mod" ex01
want_out "first_red: ...and a unit's as the root" '<deliverable>' -- \
	"$SH" -c '"$1" "$2" --turnin "$3" toyroot | sed "s/.*/<&>/"' _ "$SH" "$FR_TOOLS/first_red.sh" "$WORK/fr/wrroot"
want_red "first_red: ...and guesses nothing without an entry" -- \
	"$SH" "$FR_TOOLS/first_red.sh" --turnin "$WORK/fr/mod" ex07
want_red "first_red: --turnin takes exNN, never a bare number" -- \
	"$SH" "$FR_TOOLS/first_red.sh" --turnin "$WORK/fr/mod" 00
# A contract units.awk cannot read -- valid Starlark, but no exercise written
# out -- stops every mode that reads it, with units.awk's line: read some
# other way, its folders, and so every "not written yet", would be a guess.
mkdir -p "$WORK/fr/compr"
printf 'subject(\n    exercises = {k: exercise(dir = "ex00/") for k in ["00"]},\n)\n' > "$WORK/fr/compr/BUILD.bazel"
printf '//compr:ex00_output  FAILED in 0.1s\n' > "$WORK/fr/compr.log"
want_broken "first_red: a contract units.awk cannot read stops the report" \
	'cannot read the subject() contract of //compr' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/compr.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken "first_red: ...and says units.awk's line" 'units.awk: compr/BUILD.bazel:2: ' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/compr.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# A module the log names only on a compiler's line: is_written asks its
# contract for the folder too, so the report stops the same way.
printf 'ERROR: %s/compr/BUILD.bazel:5:1: Compiling compr/deliverable/x.c failed\ncompr/deliverable/x.c:3:1: error: expected ;\n' \
	"$WORK/fr" > "$WORK/fr/compr_build.log"
want_broken "first_red: ...a module named only by a build line stops it too" \
	'cannot read the subject() contract of //compr' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/compr_build.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken "first_red: ...--written stops on it too" '/compr/BUILD.bazel:2: ' -- \
	"$SH" "$FR_TOOLS/first_red.sh" --written "$WORK/fr/compr"
want_broken "first_red: ...--turnin too" '/compr/BUILD.bazel:2: ' -- \
	"$SH" "$FR_TOOLS/first_red.sh" --turnin "$WORK/fr/compr" ex00
want_broken "first_red: ...and --unit-of stops on it" '/compr/BUILD.bazel:2: ' -- \
	"$SH" -c '"$1" "$2" --unit-of "$3" < /dev/null' _ "$SH" "$FR_TOOLS/first_red.sh" "$WORK/fr/compr"
# A LIBRARY'S FUNCTIONS. A library of a contract of units lists its
# functions (units = {"libfr": unit(functions = {...})}), each a unit of its
# own, with tests named <function>_<layer> and a suite per function. Keyed
# by the library alone, every function's output was one line, "output x3",
# and one written function made every other red read "written, and wrong".
# So reds are filed by function -- the key whose name, then _, the target
# begins with: the underscore is part of the prefix, so ft_selftest_one_
# never claims ft_selftest_onemore_output -- shown by the function's name,
# run again by its suite, and called written only when stub_check --defines
# finds a body in it. The fixture: one function written, one a stub, one
# defined nowhere; a comment naming a key and the values' strings are no key.
mkdir -p "$WORK/fr/lib/deliverable"
cat > "$WORK/fr/lib/BUILD.bazel" <<'FR_LIB'
subject(
    grader = "both",
    group = False,
    units = {
        "libfr": unit(page = 1, files = ["Makefile"], allowed = ["malloc"],
            functions = {
                "ft_selftest_one": [],  # "ft_selftest_not": [] is a comment
                "ft_selftest_onemore": ["malloc"],
                "ft_selftest_two": [],
            }),
    },
)
FR_LIB
printf '%s\n\nint\tft_selftest_one(int n)\n{\n\treturn (n + 1);\n}\n\nint\tft_selftest_two(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' \
	"$FR_H" > "$WORK/fr/lib/deliverable/lib.c"
{
	printf '//lib:ft_selftest_one_output  FAILED in 0.1s\n'
	printf '//lib:ft_selftest_two_output  FAILED in 0.1s\n'
	printf '//lib:ft_selftest_two_valgrind  FAILED in 0.1s\n'
	printf '//lib:ft_selftest_onemore_output  FAILED in 0.1s\n'
} > "$WORK/fr/lib.log"
printf '//lib:ft_selftest_one_output  FAILED in 0.1s\n' > "$WORK/fr/lib_one.log"
printf '//lib:ft_selftest_two_output  FAILED in 0.1s\n//lib:ft_selftest_onemore_output  FAILED in 0.1s\n' \
	> "$WORK/fr/lib_next.log"
printf '//lib:ft_selftest_two_output  FAILED in 0.1s\n' > "$WORK/fr/lib_two.log"
printf '//lib:ft_selftest_one_valgrind  FAILED in 0.1s\n//lib:ft_selftest_onemore_valgrind  FAILED in 0.1s\n' \
	> "$WORK/fr/lib_rig.log"
# The functions, as first_red reads them: through tools/units.awk, whose
# rows put each function right after its library, in that library's folder.
want_out "units.awk: a library's functions, each a row after its library" \
	"$(printf 'ft_selftest_onemore\tfunction\t-\tdeliverable\tdefines\tlibfr')" -- \
	env LC_ALL=C awk -f "$FR_TOOLS/units.awk" "$WORK/fr/lib/BUILD.bazel"
want_broken_none "units.awk: ...never a key in a comment" 'ft_selftest_not' -- \
	env LC_ALL=C awk -f "$FR_TOOLS/units.awk" "$WORK/fr/lib/BUILD.bazel"
want_broken_none "units.awk: ...nor a function a value names" 'malloc' -- \
	env LC_ALL=C awk -f "$FR_TOOLS/units.awk" "$WORK/fr/lib/BUILD.bazel"
want_broken "first_red: --members is gone" 'unknown option' -- \
	"$SH" "$FR_TOOLS/first_red.sh" --members "$WORK/fr/lib"
# --unit-of: the unit each test belongs to, read from its name -- for the
# check that holds this reading to the one the macros wrote in its tags. Each
# line comes back between < and >, so an arm pins a whole line:
# ft_selftest_one is the start of ft_selftest_onemore, and a pattern with no
# end would match a line that ends in more too. A prefix is a name, then _,
# so ft_selftest_one_ never claims ft_selftest_onemore_output. The same
# library is written a second time with its functions the other way round,
# so a reading that drops the underscore and keeps the first match, or the
# last, is wrong in one of the two.
fr_unit_of() {  # fr_unit_of MODDIR -- five target names through --unit-of
	_fuo=$(printf 'ft_selftest_onemore_output\nft_selftest_one_output\nlibfr_norm\ndeliverable_files\nex05_files\n' |
		"$SH" "$FR_TOOLS/first_red.sh" --unit-of "$1")
	_fuo_rc=$?
	[ -z "$_fuo" ] || printf '%s\n' "$_fuo" | sed 's/.*/<&>/'
	return "$_fuo_rc"
}
mkdir -p "$WORK/fr/librev" "$WORK/fr/nocontract"
cat > "$WORK/fr/librev/BUILD.bazel" <<'FR_LIBREV'
subject(
    units = {
        "libfr": unit(page = 1, files = ["Makefile"], allowed = ["malloc"],
            functions = {
                "ft_selftest_onemore": ["malloc"],
                "ft_selftest_one": [],
            }),
    },
)
FR_LIBREV
printf 'c_levels()\n' > "$WORK/fr/nocontract/BUILD.bazel"
want_out "first_red --unit-of: the longest function a name starts with" \
	"$(printf '<ft_selftest_onemore_output\tft_selftest_onemore>')" -- \
	fr_unit_of "$WORK/fr/lib"
want_out "first_red --unit-of: ...whichever order they are listed in" \
	"$(printf '<ft_selftest_onemore_output\tft_selftest_onemore>')" -- \
	fr_unit_of "$WORK/fr/librev"
want_out "first_red --unit-of: ...the shorter one is still its own" \
	"$(printf '<ft_selftest_one_output\tft_selftest_one>')" -- \
	fr_unit_of "$WORK/fr/lib"
want_out "first_red --unit-of: a test of no function is its library's" \
	"$(printf '<libfr_norm\tlibfr>')" -- fr_unit_of "$WORK/fr/lib"
want_out "first_red --unit-of: a test of the whole module is no unit's" \
	"$(printf '<deliverable_files\t->')" -- fr_unit_of "$WORK/fr/lib"
want_out "first_red --unit-of: an exNN the contract lacks is still exNN" \
	"$(printf '<ex05_files\tex05>')" -- fr_unit_of "$WORK/fr/lib"
want_broken "first_red --unit-of: with no contract, it refuses" \
	'no subject() contract' -- fr_unit_of "$WORK/fr/nocontract"
# A function's row carries its library's folder, but --turnin answers for a
# unit with a folder of its own: a function is asked about through its
# library.
want_red "first_red: --turnin of a function name finds no folder of its own" -- \
	"$SH" "$FR_TOOLS/first_red.sh" --turnin "$WORK/fr/lib" ft_selftest_one
want_out "first_red: a library's reds are filed by function" \
	'ft_selftest_two' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --all < "$1/lib.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ...never as the library's output xN" 'output x' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --all < "$1/lib.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...and counted as functions" '1 library (3 of its functions)' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/lib.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: the longest function a name starts with is its own" \
	'ft_selftest_onemore' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --all < "$1/lib.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: the next function is run by its own suite" \
	'bazel test //lib:ft_selftest_onemore' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/lib_next.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...and named as a function" 'YOUR NEXT FUNCTION' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/lib.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: a written function with a red output is wrong" \
	'written; wrong output' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/lib_one.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: a stub beside it is not written yet" \
	'not written yet' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/lib_two.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ...never wrong for the other's body" 'wrong output' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/lib_two.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# (The contract lists ft_selftest_one first, so it is the next; its label is
# its own, never the one of ft_selftest_onemore, whose name begins with it.)
want_out "first_red: --next names a function and its own red label" \
	"$(printf 'rigour\t//lib\tft_selftest_one\t//lib:ft_selftest_one_valgrind')" -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --next "$1/next_lib.tsv" < "$1/lib_rig.log" > /dev/null && cat "$1/next_lib.tsv"' \
	_ "$WORK/fr" "$SH" "$FR_TOOLS"
# The next function is the first red one the contract lists, never the first
# by label: two stubs, the contract's first sorting last, both red. Picked by
# label, the report sent the student to ft_selftest_alpha (ft_atoi in a
# library, for sorting first) whatever order the subject gives.
mkdir -p "$WORK/fr/lib2/deliverable"
cat > "$WORK/fr/lib2/BUILD.bazel" <<'FR_LIB2'
subject(
    grader = "both",
    group = False,
    units = {
        "libfr": unit(page = 1, files = ["Makefile"], allowed = [],
            functions = {
                "ft_selftest_zeta": [],
                "ft_selftest_alpha": [],
            }),
    },
)
FR_LIB2
printf '%s\n\nint\tft_selftest_zeta(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n\nint\tft_selftest_alpha(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' \
	"$FR_H" > "$WORK/fr/lib2/deliverable/lib.c"
printf '//lib2:ft_selftest_alpha_output  FAILED in 0.1s\n//lib2:ft_selftest_zeta_output  FAILED in 0.1s\n' \
	> "$WORK/fr/lib2.log"
want_out "first_red: the next function is the contract's first red one" \
	"$(printf '//lib2\tft_selftest_zeta\t')" -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --next "$1/next_lib2.tsv" < "$1/lib2.log" > /dev/null && cat "$1/next_lib2.tsv"' \
	_ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...and the report runs it" 'bazel test //lib2:ft_selftest_zeta' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/lib2.log" | sed -n "/YOUR NEXT FUNCTION/,\$p"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# A PROJECT OF NAMED UNITS: a library whose functions are units of their own
# (one written, one a stub, one defined nowhere), and a project that is one
# unit. Its reds are filed by unit name, never by an exercise.
mkdir -p "$WORK/fr/nlib/deliverable" "$WORK/fr/nproj/deliverable"
cat > "$WORK/fr/nlib/BUILD.bazel" <<'FR_NLIB'
subject(
    grader = "both",
    group = False,
    units = {
        "libselftest": unit(page = 1, files = ["Makefile"], allowed = ["malloc"],
            functions = {
                "st_alpha": [],
                "st_beta": ["malloc"],
                "st_gamma": [],
            }),
    },
)
FR_NLIB
printf '%s\n\nint\tst_alpha(int n)\n{\n\treturn (n + 1);\n}\n\nint\tst_beta(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' \
	"$FR_H" > "$WORK/fr/nlib/deliverable/lib.c"
cat > "$WORK/fr/nproj/BUILD.bazel" <<'FR_NPROJ'
subject(
    grader = "both",
    group = False,
    units = {
        "selftest_prog": unit(page = 1, files = ["Makefile"], allowed = None),
    },
)
FR_NPROJ
printf '%s\n\nint\tmain(void)\n{\n\treturn (0);\n}\n' "$FR_H" > "$WORK/fr/nproj/deliverable/main.c"
printf '//nlib:st_gamma_output  FAILED in 0.1s\n//nlib:st_beta_output  FAILED in 0.1s\n//nlib:st_beta_valgrind  FAILED in 0.1s\n' \
	> "$WORK/fr/nlib.log"
printf '//nlib:libselftest_build  FAILED in 0.1s\n//nlib:st_beta_output  FAILED in 0.1s\n' > "$WORK/fr/nlib_own.log"
printf '//nproj:selftest_prog_output  FAILED in 0.1s\n//nproj:selftest_prog_norm  FAILED in 0.1s\n' > "$WORK/fr/nproj.log"
printf '//mod:ex00_output  FAILED in 0.1s\n//nlib:st_beta_output  FAILED in 0.1s\n//nproj:selftest_prog_output  FAILED in 0.1s\n' \
	> "$WORK/fr/nmixed.log"
cat > "$WORK/fr/nbuild.log" <<'FR_NBUILD'
ERROR: /home/you/42/nlib/BUILD.bazel:9:11: Compiling nlib/tests/st_beta/main.c failed: (Exit 1): clang.sh failed: error executing CppCompile command (from cc_binary rule target //nlib:st_beta_output_bin) tools/cc_toolchain/clang.sh -Wall (remaining 22 arguments skipped)
nlib/tests/st_beta/main.c:4:2: error: expected expression
1 error generated.
ERROR: Build did NOT complete successfully
//nlib:st_beta_output                                    FAILED TO BUILD

Executed 0 out of 1 test: 1 fails to build.
FR_NBUILD
want_out "first_red: named units are counted by their kind" \
	'2 red target(s), 1 library (1 of its functions), 1 module(s).' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/nlib_own.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...a project as one" '2 red target(s), 1 project, 1 module(s).' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/nproj.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...and an exercise beside them as before" \
	'3 red target(s), 1 exercise(s), 1 library (1 of its functions), 1 project, 3 module(s).' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/nmixed.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: a named function is next by its contract's order" \
	"$(printf 'work\t//nlib\tst_beta\t//nlib:st_beta_output')" -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --next "$1/next_nlib.tsv" < "$1/nlib.log" > /dev/null && cat "$1/next_nlib.tsv"' \
	_ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...named as a function, by its name alone" \
	'      //nlib st_beta' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/nlib.log" | sed -n "/YOUR NEXT FUNCTION/,\$p"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...run again by its own suite" 'bazel test //nlib:st_beta' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/nlib.log" | sed -n "/YOUR NEXT FUNCTION/,\$p"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...and as 42 takes it under --cmd 42" '42 test nlib st_beta' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --cmd 42 < "$1/nlib.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: --triage files a function under its library" \
	"$(printf 'work\t//nlib\tlibselftest')" -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --triage "$1/tri_nlib.tsv" < "$1/nlib.log" > /dev/null && cat "$1/tri_nlib.tsv"' \
	_ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: the library's own test comes before its functions" \
	'YOUR NEXT LIBRARY' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/nlib_own.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: a project of one unit is next as a project" 'YOUR NEXT PROJECT' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/nproj.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...run again by its name" '42 test nproj selftest_prog' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --cmd 42 < "$1/nproj.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: the table names the units of a named project" \
	'|      nlib                       3  not written yet          libselftest|' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/nlib.log" | sed "s/.*/|&|/"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...under the heading RED PARTS" 'RED PARTS' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/nlib.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: --all lists a named function by its name" \
	'|        st_beta   2  output valgrind|' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --all < "$1/nlib.log" | sed "s/.*/|&|/"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: a test program under tests/<unit> does not build" \
	'SOMETHING DOES NOT BUILD' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/nbuild.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...and the whole library is run again" 'bazel test //nlib/...' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/nbuild.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# --all's column of exercises and units is as wide as those of its own
# module, never a test of the whole module (deliverable_files overflows it,
# as it always has) nor another module's library: padded to the widest label
# of the run, every existing module's rows changed layout. Each row whole,
# between bars.
printf '//mod:ex00_output  FAILED in 0.1s\n//mod:deliverable_files  FAILED in 0.1s\n//lib:ft_selftest_onemore_output  FAILED in 0.1s\n//lib:ft_selftest_two_output  FAILED in 0.1s\n' \
	> "$WORK/fr/wide.log"
want_out "first_red: --all keeps an exercise row as it was" '|        ex00    1  output|' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --all < "$1/wide.log" | sed "s/.*/|&|/"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...and pads a function row to its library" \
	'|        ft_selftest_two      1  output|' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --all < "$1/wide.log" | sed "s/.*/|&|/"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# EVERYTHING STILL RED's module column is 22 wide, as it always was, and
# wider for a longer name: a project deep under a folder of its own pushed
# its own counts out of line with every other row's. Each row from its
# start up to its count. A Common Core project is named as 42 names it, by
# its folder's own name in lower case (cursus/Milestone_9/Toylibrary is
# toylibrary), in the table and in each command the report suggests.
mkdir -p "$WORK/fr/deep/Milestone_9/Toylibrary/deliverable" "$WORK/fr/cursus/Milestone_9/Toylibrary/deliverable"
for _frd in deep/Milestone_9/Toylibrary cursus/Milestone_9/Toylibrary; do
	cp "$WORK/fr/lib/BUILD.bazel" "$WORK/fr/$_frd/BUILD.bazel"
	cp "$WORK/fr/lib/deliverable/lib.c" "$WORK/fr/$_frd/deliverable/lib.c"
done
printf '//mod:ex00_output  FAILED in 0.1s\n//deep/Milestone_9/Toylibrary:ft_selftest_two_output  FAILED in 0.1s\n' \
	> "$WORK/fr/deep.log"
printf '//mod:ex00_output  FAILED in 0.1s\n//cursus/Milestone_9/Toylibrary:ft_selftest_two_output  FAILED in 0.1s\n' \
	> "$WORK/fr/cdeep.log"
printf '//mod:ex00_output  FAILED in 0.1s\n' > "$WORK/fr/mod_only.log"
want_out "first_red: the module column is 22 wide, as it was" '|      mod                        1  ' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/mod_only.log" | sed "s/^/|/"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...wider for a deep project's name" '|      deep/Milestone_9/Toylibrary     1  ' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/deep.log" | sed "s/^/|/"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...and every row's count in that one column" '|      mod                             1  ' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/deep.log" | sed "s/^/|/"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: a Common Core project is named as 42 names it" \
	'|      toylibrary                 1  ' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/cdeep.log" | sed "s/^/|/"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
want_out "first_red: ...in the command it suggests" '42 test toylibrary ft_selftest_two' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --cmd 42 --all < "$1/cdeep.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"
# Joined on one line, so a line missing or written twice is seen: grep -F
# takes a pattern holding a newline as two patterns, either of which passes.
want_out "first_red: --triage files a library's functions under it" \
	'work,//lib,libfr;wrong,//lib,libfr;' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --triage "$1/triage_lib.tsv" < "$1/lib.log" > /dev/null && sort "$1/triage_lib.tsv" | tr "\t\n" ",;"' \
	_ "$WORK/fr" "$SH" "$FR_TOOLS"
# A LIBRARY'S OWN TESTS: a target of the library, of no function
# (libfr_build, libfr_readme), reads one file of the turn-in, and whether its
# red is that file unwritten or wrong is that file's question. Asked of the
# whole folder, one written function made the stub README "written, and it
# runs, but ... The table in that log names the case" (no table: its runner
# prints none), and on a fresh tree the next step was the suite of the whole
# library, as an unwritten library. Three trees, each a copy of one
# toy library with a stub Makefile, a stub README.md and two stub functions:
# untouched (libown), one function written (libown2), the README written
# (libown3). The reds are a fresh tree's: build, readme and two outputs.
for _fro in libown libown2 libown3; do
	mkdir -p "$WORK/fr/$_fro/deliverable"
	cat > "$WORK/fr/$_fro/BUILD.bazel" <<'FR_LIBOWN'
subject(
    grader = "both",
    group = False,
    units = {
        "libfr": unit(page = 1, files = ["Makefile", "README.md"], allowed = [],
            functions = {
                "ft_selftest_one": [],
                "ft_selftest_two": [],
            }),
    },
)
FR_LIBOWN
	printf 'NAME = libselftest.a\n\n$(NAME):\n\t@echo "TODO: $(NAME)"\n\nall: $(NAME)\n' \
		> "$WORK/fr/$_fro/deliverable/Makefile"
	printf '<!--\n  A toy README stub: what it holds is yours to write.\n-->\n' \
		> "$WORK/fr/$_fro/deliverable/README.md"
	printf '%s\n\nint\tft_selftest_one(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n\nint\tft_selftest_two(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' \
		"$FR_H" > "$WORK/fr/$_fro/deliverable/lib.c"
	{
		printf '//%s:libfr_build  FAILED in 0.1s\n' "$_fro"
		printf '//%s:libfr_readme  FAILED in 0.1s\n' "$_fro"
		printf '//%s:ft_selftest_one_output  FAILED in 0.1s\n' "$_fro"
		printf '//%s:ft_selftest_two_output  FAILED in 0.1s\n' "$_fro"
	} > "$WORK/fr/$_fro.log"
done
printf '%s\n\nint\tft_selftest_one(int n)\n{\n\treturn (n * 3 + 1);\n}\n\nint\tft_selftest_two(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' \
	"$FR_H" > "$WORK/fr/libown2/deliverable/lib.c"
printf '*A toy first line.*\n\n# One\n\nSome words.\n' > "$WORK/fr/libown3/deliverable/README.md"
# fr_own MODULE [OPTION...] -- the report over that tree twice: each line
# ended by a bar (so a label is told from a longer one it begins), then all of
# it on one line, so a sentence the report wraps is still one pattern. Its
# status is the report's.
fr_own() {
	_fron=$1
	shift
	_fro_out=$(cd "$WORK/fr" && "$SH" "$FR_TOOLS/first_red.sh" "$@" < "$WORK/fr/$_fron.log")
	_fro_rc=$?
	printf '%s\n' "$_fro_out" | sed 's/[ ]*$/|/'
	printf '%s\n' "$_fro_out" | tr '\n' ' ' | tr -s ' '
	return "$_fro_rc"
}
want_out "first_red: a library's own red is run by its label" \
	'bazel test //libown:libfr_build --test_output=errors|' -- fr_own libown
want_out "first_red: ...each of them" \
	'bazel test //libown:libfr_readme --test_output=errors|' -- fr_own libown
want_broken_none "first_red: ...never by the whole library's suite" \
	'bazel test //libown:libfr|' -- fr_own libown
want_broken_none "first_red: ...nor called an unwritten library" \
	'what an unwritten library' -- fr_own libown
want_out "first_red: ...and says the file each one reads" \
	'libfr_build reads the Makefile, libfr_readme reads README.md.' -- fr_own libown
want_out "first_red: ...and as 42 takes it under --cmd 42" \
	'42 test //libown:libfr_readme|' -- fr_own libown --cmd 42
want_out "first_red: --next names the library's own red label" \
	"$(printf 'work\t//libown\tlibfr\t//libown:libfr_build')" -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --next "$1/next_own.tsv" < "$1/libown.log" > /dev/null && cat "$1/next_own.tsv"' \
	_ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: a written function leaves a stub README unwritten" \
	'It is written' -- fr_own libown2
want_out "first_red: ...still the file each one reads" \
	'libfr_build reads the Makefile, libfr_readme reads README.md.' -- fr_own libown2
want_out "first_red: a written README with its red is wrong" \
	'README.md is written, but the test that reads it disagrees.' -- fr_own libown3
want_out "first_red: ...run by that test's label" \
	'bazel test //libown3:libfr_readme --test_output=errors|' -- fr_own libown3
want_out "first_red: ...which --next names" \
	"$(printf 'wrong\t//libown3\tlibfr\t//libown3:libfr_readme')" -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --next "$1/next_own3.tsv" < "$1/libown3.log" > /dev/null && cat "$1/next_own3.tsv"' \
	_ "$WORK/fr" "$SH" "$FR_TOOLS"
want_broken_none "first_red: ...and sent to no table its runner never prints" \
	'The table in' -- fr_own libown3
# A library's own red in the rigour bucket names its label in --next, as a
# function's does: given none, 42 picked the first red by a prefix of names,
# which a function's test could begin with as well, and showed that log
# under the library's line.
printf '//libown:libfr_symbols  FAILED in 0.1s\n//libown:ft_selftest_one_diff  FAILED in 0.1s\n' \
	> "$WORK/fr/libown_rig.log"
want_out "first_red: --next names a library's own rigour red" \
	"$(printf 'rigour\t//libown\tlibfr\t//libown:libfr_symbols')" -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --next "$1/next_own_rig.tsv" < "$1/libown_rig.log" > /dev/null && cat "$1/next_own_rig.tsv"' \
	_ "$WORK/fr" "$SH" "$FR_TOOLS"
# ...and a rule of the whole library red over a stub library, not written
# yet, is run by that label too, never by the whole library's suite.
printf '//libown:libfr_norm  FAILED in 0.1s\n//libown:ft_selftest_one_output  FAILED in 0.1s\n' \
	> "$WORK/fr/libown_norm.log"
want_out "first_red: a library's own rule over a stub is run by its label" \
	'bazel test //libown:libfr_norm --test_output=errors|' -- fr_own libown_norm
# ...and so is each rule of the whole library that is red over a WRITTEN
# library, under FIX FIRST: it printed the suite of the whole library,
# `bazel test //<module>:libfr`, for a red libfr_norm.
printf '//libown2:libfr_files  FAILED in 0.1s\n//libown2:libfr_norm  FAILED in 0.1s\n//libown2:ft_selftest_two_output  FAILED in 0.1s\n' \
	> "$WORK/fr/libown2_ko.log"
want_out "first_red: FIX FIRST runs a library's own rule by its label" \
	'bazel test //libown2:libfr_files --test_output=errors|' -- fr_own libown2_ko
want_out "first_red: ...each of them" \
	'bazel test //libown2:libfr_norm --test_output=errors|' -- fr_own libown2_ko
want_broken_none "first_red: ...never by the whole library's suite" \
	'bazel test //libown2:libfr|' -- fr_own libown2_ko
# A library with a function written and only its own tests red over the stub
# Makefile and README.md is not written yet in --triage, the verdict
# submit --written-only reads (docs/submitting.md): the files those tests read
# are as unwritten as a function still a stub, and the library goes to 42 as
# it is on disk. It used to be "wrong", the folder asked for the README.
printf '//libown2:libfr_build  FAILED in 0.1s\n//libown2:libfr_readme  FAILED in 0.1s\n' \
	> "$WORK/fr/libown2_own.log"
want_out "first_red: --triage, stub Makefile and README over a written function" \
	'work,//libown2,libfr;' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" --triage "$1/triage_own2.tsv" < "$1/libown2_own.log" > /dev/null && sort "$1/triage_own2.tsv" | tr "\t\n" ",;"' \
	_ "$WORK/fr" "$SH" "$FR_TOOLS"
# A file that is missing, or empty, is not written either, but it is not
# "still a stub": a README deleted was told it was the stub.
for _fro in libown4 libown5; do
	mkdir -p "$WORK/fr/$_fro"
	cp -R "$WORK/fr/libown/BUILD.bazel" "$WORK/fr/libown/deliverable" "$WORK/fr/$_fro/"
	sed "s|//libown:|//$_fro:|" "$WORK/fr/libown.log" > "$WORK/fr/$_fro.log"
done
rm "$WORK/fr/libown4/deliverable/README.md"
: > "$WORK/fr/libown5/deliverable/README.md"
want_out "first_red: a missing README is called missing" \
	'libfr_build reads the Makefile (a stub), libfr_readme reads README.md (missing).' -- fr_own libown4
want_broken_none "first_red: ...never still a stub" \
	'is still a stub' -- fr_own libown4
want_out "first_red: an empty README is called empty" \
	'libfr_readme reads README.md (empty).' -- fr_own libown5
printf '//libown4:libfr_readme  FAILED in 0.1s\n' > "$WORK/fr/libown4_one.log"
want_out "first_red: ...and alone, the file it reads is missing" \
	'the file it reads is missing: libfr_readme reads README.md.' -- fr_own libown4_one
# "The table in that log names the case" only over a log that holds one,
# which is what the table mark says (runner_lib.sh, RL_TABLE_MARK): a
# Makefile build's red (exNN_build) has none, nor a shell exercise's output,
# whose script is diffed as a whole, nor a log that was never read. It was
# decided from the target's name, by a list kept by hand, and every _output
# was "a table": the --survive report of a program that crashes with no
# arguments (Rush 02's four basic survive cases) and the byte-stream summary
# of C 10's blobs were both sent to a table their log does not have (V231).
mkdir -p "$WORK/fr/pmk/deliverable/ex00" "$WORK/fr/pshm/generators"
fr_contract "$WORK/fr/pmk" 00=ex00/
printf '%s\n\nint\tsf_toy_twice(int n)\n{\n\treturn (n + n);\n}\n' "$FR_H" \
	> "$WORK/fr/pmk/deliverable/ex00/sf_toy_twice.c"
printf '#!/bin/sh\nprintf "%%s\\n" toy > sf_toy.txt\n' > "$WORK/fr/pshm/generators/ex00.sh"
printf '//pmk:ex00_build  FAILED in 0.1s\n' > "$WORK/fr/pmk_build.log"
printf '//pmk:ex00_output  FAILED in 0.1s\n' > "$WORK/fr/pmk_bare.log"
printf '//pshm:ex00_output  FAILED in 0.1s\n' > "$WORK/fr/pshm_out.log"
want_out "first_red: a written Makefile build red is sent to its log" \
	'expects (build). That log says why.' -- fr_own pmk_build
want_broken_none "first_red: ...never to a table" \
	'The table in' -- fr_own pmk_build
want_out "first_red: ...as 42 says it" \
	'expects (build). Its log says why.' -- fr_own pmk_build --cmd 42
want_out "first_red: a shell exercise's red output has no table either" \
	'That log says why.' -- fr_own pshm_out
want_out "first_red: an output red whose log was never read names no table" \
	'expects (output). That log says why.' -- fr_own pmk_bare
# Real logs, each the runner's own over a toy: a table with a failing row,
# a survive case's crash, a byte-stream summary. Each is read both ways
# first_red reads a log: from the test.log path under its FAILED line, and
# printed inline by --test_output=errors.
if st_mine; then
	mkdir -p "$WORK/fr/logs/tab" "$WORK/fr/logs/sv" "$WORK/fr/logs/bin"
	printf 'one\ntwo\n' > "$WORK/fr/tab_exp.txt"
	printf '#!/bin/sh\nprintf "one\\nsix\\n"\n' > "$WORK/fr/tab_prog"
	printf 'int main(int c, char **v) { (void)c; return (v[1][0]); }\n' > "$WORK/fr/sv_prog.c"
	toy_cc "$WORK/fr/sv_prog" "$WORK/fr/sv_prog.c"
	printf '\001\002\003\004\005\006\016\017\020\021\022\023' > "$WORK/fr/bin_exp.txt"
	printf '#!/bin/sh\nprintf "\\001\\002"\n' > "$WORK/fr/bin_prog"
	chmod +x "$WORK/fr/tab_prog" "$WORK/fr/bin_prog"
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/fr/tab_prog" --expected "$WORK/fr/tab_exp.txt" \
		> "$WORK/fr/logs/tab/test.log" 2>&1
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/fr/sv_prog" --survive --case args_none -- \
		> "$WORK/fr/logs/sv/test.log" 2>&1
	"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/fr/bin_prog" --expected "$WORK/fr/bin_exp.txt" \
		> "$WORK/fr/logs/bin/test.log" 2>&1
	for _frt in tab sv bin; do
		case $_frt in
			sv) _frl=//pmk:ex00_args_none_output ;;
			*) _frl=//pmk:ex00_output ;;
		esac
		printf '%s  FAILED in 0.1s\n  %s\n' "$_frl" "$WORK/fr/logs/$_frt/test.log" \
			> "$WORK/fr/pmk_$_frt.log"
		{
			printf '==================== Test output for %s:\n' "$_frl"
			cat "$WORK/fr/logs/$_frt/test.log"
			printf '================================================================================\n'
			printf '%s  FAILED in 0.1s\n' "$_frl"
		} > "$WORK/fr/pmk_${_frt}_in.log"
	done
fi
# The premises: each runner's log is what the arm says it is.
want_out "first_red: (premise) the table's log has a failing row" 'FAIL <' -- \
	cat "$WORK/fr/logs/tab/test.log"
want_out "first_red: (premise) the survive log is a crash" 'CRASH:' -- \
	cat "$WORK/fr/logs/sv/test.log"
want_out "first_red: (premise) the byte-stream log is a summary" 'BYTES' -- \
	cat "$WORK/fr/logs/bin/test.log"
want_out "first_red: an output case's red still names its table" \
	'expects (output). The table in that log names the case.' -- fr_own pmk_tab
want_out "first_red: ...as 42 says it" \
	'expects (output). The table in its log names the case.' -- fr_own pmk_tab --cmd 42
want_out "first_red: ...and from the log printed inline" \
	'expects (output). The table in that log names the case.' -- fr_own pmk_tab_in
want_out "first_red: a survive case's crash is sent to its log" \
	'expects (output). That log says why.' -- fr_own pmk_sv
want_broken_none "first_red: ...never to a table it does not have" \
	'The table in' -- fr_own pmk_sv
want_broken_none "first_red: ...nor from the log printed inline" \
	'The table in' -- fr_own pmk_sv_in
want_out "first_red: a byte-stream summary is sent to its log" \
	'expects (output). That log says why.' -- fr_own pmk_bin
want_broken_none "first_red: ...never to a table" \
	'The table in' -- fr_own pmk_bin
# The sweeps' failing cases are blocks (rl_block), and the first one printed
# has the mark above it, once: not above a block the row cap leaves out, and
# never twice.
fr_blocks() {
	(
		# shellcheck disable=SC2034 # runner_lib.sh names itself by it
		RL_NAME=selftest
		. "$TOOLS/runner_lib.sh"
		rl_rows "$1"
		printf ' CASE 1 of 3\n' > "$WORK/fr/blk"
		rl_block "$WORK/fr/blk"
		rl_block "$WORK/fr/blk"
		rl_block "$WORK/fr/blk"
	) | awk -v m="$(sed -n 's/^RL_TABLE_MARK="\(.*\)"$/\1/p' "$TOOLS/runner_lib.sh")" '
		m != "" && index($0, m) == 1 { n++; if (NR != 1) late = 1 }
		END { printf "%d mark(s)%s\n", n, late ? ", not first" : "" }'
}
want_out "first_red: the first failing case a sweep prints has the mark" '1 mark(s)' -- fr_blocks 2
want_broken_none "first_red: ...above it" 'not first' -- fr_blocks 2
want_out "first_red: ...once, every block printed" '1 mark(s)' -- fr_blocks 0
# A test that builds its own test program against the turn-in and cannot
# (header_check.sh, over a toy header) ran nothing: its log holds the build
# mark (runner_lib.sh, RL_BUILD_MARK), and over a written exercise it is filed
# with what does not build, the compiler's line quoted, one in the test
# program said to be there. Over a stub, guards only, it is what an unwritten
# exercise looks like. It was read as a wrong output, "It is written, and it
# runs", the module's row "written; wrong output", with the compile layer
# green (V231).
if st_mine; then
	for _frm in hbl hbc hbs; do
		mkdir -p "$WORK/fr/$_frm/deliverable/ex00" "$WORK/fr/$_frm/tests/ex00" "$WORK/fr/logs/$_frm"
		fr_contract "$WORK/fr/$_frm" 00=ex00/
		printf '#include <stdio.h>\n#include "sf_toy.h"\n\nint\tmain(void)\n{\n\tprintf("%%d\\n", SF_TWICE(21));\n\treturn (0);\n}\n' \
			> "$WORK/fr/$_frm/tests/ex00/main.c"
		printf '42\n' > "$WORK/fr/$_frm/tests/ex00/exp.txt"
	done
	# hbl declares a helper and never defines it (the link fails), hbc has no
	# SF_TWICE (the test program does not compile), hbs is guards only.
	printf '%s\n#ifndef SF_TOY_H\n# define SF_TOY_H\n\nint\tsf_toy_helper(int n);\n# define SF_TWICE(n) (sf_toy_helper(n))\n\n#endif\n' \
		"$FR_H" > "$WORK/fr/hbl/deliverable/ex00/sf_toy.h"
	printf '%s\n#ifndef SF_TOY_H\n# define SF_TOY_H\n\nint\tsf_toy_helper(int n);\n\n#endif\n' \
		"$FR_H" > "$WORK/fr/hbc/deliverable/ex00/sf_toy.h"
	printf '%s\n#ifndef SF_TOY_H\n# define SF_TOY_H\n\n#endif\n' "$FR_H" > "$WORK/fr/hbs/deliverable/ex00/sf_toy.h"
	for _frm in hbl hbc hbs; do
		(cd "$WORK/fr" && "$SH" "$FR_TOOLS/header_check.sh" --differ "$FR_TOOLS/diff_output.sh" \
			--hdr "$_frm/deliverable/ex00/sf_toy.h" --main "$_frm/tests/ex00/main.c" \
			--expected "$_frm/tests/ex00/exp.txt") > "$WORK/fr/logs/$_frm/test.log" 2>&1
		printf '//%s:ex00_compile_gcc  PASSED in 0.1s\n//%s:ex00_output  FAILED in 0.1s\n  %s\n' \
			"$_frm" "$_frm" "$WORK/fr/logs/$_frm/test.log" > "$WORK/fr/$_frm.log"
		{
			printf '==================== Test output for //%s:ex00_output:\n' "$_frm"
			cat "$WORK/fr/logs/$_frm/test.log"
			printf '================================================================================\n'
			printf '//%s:ex00_output  FAILED in 0.1s\n' "$_frm"
		} > "$WORK/fr/${_frm}_in.log"
	done
fi
want_out "first_red: (premise) the link failure's log is header_check's" 'undefined reference to' -- \
	cat "$WORK/fr/logs/hbl/test.log"
want_out "first_red: (premise) ...with the build mark at the start of a line" '1 mark(s)' -- \
	awk -v m="$(sed -n 's/^RL_BUILD_MARK="\(.*\)"$/\1/p' "$TOOLS/runner_lib.sh")" '
		m != "" && index($0, m) == 1 { n++ } END { printf "%d mark(s)\n", n }' "$WORK/fr/logs/hbl/test.log"
want_out "first_red: (premise) the test program's log names the test program" 'hbc/tests/ex00/main.c:' -- \
	cat "$WORK/fr/logs/hbc/test.log"
want_out "first_red: (premise) the stub's log has the build mark too" '1 mark(s)' -- \
	awk -v m="$(sed -n 's/^RL_BUILD_MARK="\(.*\)"$/\1/p' "$TOOLS/runner_lib.sh")" '
		m != "" && index($0, m) == 1 { n++ } END { printf "%d mark(s)\n", n }' "$WORK/fr/logs/hbs/test.log"
want_out "first_red: a written header whose test program does not link does not build" \
	'DOES NOT BUILD' -- fr_own hbl
want_out "first_red: ...the linker's line quoted" "undefined reference to \`sf_toy_helper'" -- fr_own hbl
want_broken_none "first_red: ...and nothing said to run" 'it runs' -- fr_own hbl
want_out "first_red: ...nor its row 'wrong output'" 'does not build' -- fr_own hbl
want_out "first_red: ...and from the log printed inline" 'DOES NOT BUILD' -- fr_own hbl_in
want_broken_none "first_red: ...nothing said to run there either" 'it runs' -- fr_own hbl_in
want_out "first_red: a test program that does not compile against it does not build" \
	'in the test program built against your files:' -- fr_own hbc
want_out "first_red: ...and from the log printed inline" \
	'in the test program built against your files:' -- fr_own hbc_in
want_out "first_red: a stub header whose test program does not build is not written yet" \
	'not written yet' -- fr_own hbs
want_broken_none "first_red: ...never blamed as a build" 'DOES NOT BUILD' -- fr_own hbs
want_broken_none "first_red: ...nor from the log printed inline" 'DOES NOT BUILD' -- fr_own hbs_in
# An empty red (the build mark, or an empty stand-in) whose exercise already
# has a stronger build line from a sibling test -- a quoted line of the
# student's, a file not turned in -- is filed with that exercise, its layer
# named on the DOES NOT BUILD line. It was settled only when the whole
# exercise was empty, and its layer was left off the line: "ex00 -- ilp32"
# for "ex00 -- ilp32, output". hbx's ex01 is a stub whose output layer had
# an empty stand-in, which takes the other branch ("run") for the rest
# (V302).
if st_mine; then
	mkdir -p "$WORK/fr/hbx/deliverable/ex00" "$WORK/fr/hbx/deliverable/ex01" "$WORK/fr/logs/hbx"
	fr_contract "$WORK/fr/hbx" 00=ex00/ 01=ex01/
	cp "$WORK/fr/hbl/deliverable/ex00/sf_toy.h" "$WORK/fr/hbx/deliverable/ex00/sf_toy.h"
	cp "$WORK/fr/stubmk/deliverable/ex00/Makefile" "$WORK/fr/hbx/deliverable/ex01/Makefile"
	"$SH" "$TOOLS/no_turnin.sh" --test //hbx:ex01_norm --where hbx/deliverable/ex01 \
		> "$WORK/fr/logs/hbx/test.log" 2>&1
	{
		printf '==================== Test output for //hbx:ex00_ilp32:\n'
		printf 'ilp32: FAIL — your code did not build\n'
		printf '  42-harness stand-in: no program was built from your code\n'
		printf '  YOUR CODE DID NOT BUILD — it does not compile.\n'
		printf '  hbx/deliverable/ex00/sf_toy.h:16:1: error: unknown type name "itn"\n'
		printf '================================================================================\n'
		printf '//hbx:ex00_ilp32  FAILED in 0.1s\n'
		printf '//hbx:ex00_output  FAILED in 0.1s\n  %s\n' "$WORK/fr/logs/hbl/test.log"
	} > "$WORK/fr/hbx.log"
	{
		cat "$WORK/fr/hbx.log"
		printf '//hbx:ex01_output  FAILED in 0.1s\n  %s\n' "$WORK/fr/logs/empty/test.log"
	} > "$WORK/fr/hbx_run.log"
	{
		printf '//hbx:ex01_norm  FAILED in 0.1s\n  %s\n' "$WORK/fr/logs/hbx/test.log"
		printf '//hbx:ex01_output  FAILED in 0.1s\n  %s\n' "$WORK/fr/logs/empty/test.log"
	} > "$WORK/fr/hbx_nt.log"
fi
want_out "first_red: a build-marked red beside a quoted line names both layers" \
	'//hbx ex00 — ilp32, output|' -- fr_own hbx
want_out "first_red: ...and so with another exercise's empty stand-in in the run" \
	'//hbx ex00 — ilp32, output|' -- fr_own hbx_run
want_out "first_red: ...which is still the next exercise" \
	'YOUR NEXT EXERCISE //hbx ex01 ' -- fr_own hbx_run
want_out "first_red: an empty stand-in beside a file not turned in names both layers" \
	'//hbx ex01 — norm, output|' -- fr_own hbx_nt
# The premise, negated: a FAILED output whose log holds no mark is a wrong
# answer, and must not be filed as a build failure.
printf 'diff_output: FAIL — 1 of 1 line(s) differ\n' > "$WORK/fr/logs/plain/test.log"
printf '//mod:ex00_output  FAILED in 0.1s\n  %s\n' "$WORK/fr/logs/plain/test.log" > "$WORK/fr/plain.log"
want_broken_none "first_red: a log with no mark is not a build failure" \
	'DOES NOT BUILD' -- \
	"$SH" -c 'cd "$1" && "$2" "$3/first_red.sh" < "$1/plain.log"' _ "$WORK/fr" "$SH" "$FR_TOOLS"

