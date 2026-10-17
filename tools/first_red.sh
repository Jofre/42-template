#!/bin/sh
# first_red.sh — turn a wall of red into one next objective.
#
# Usage: for what to do next,
#   bazel test //c-piscine/c-piscine-c-05:basic 2>&1 | sh tools/first_red.sh
# ... and for everything, which needs memory to spare:
#   bazel test //... 2>&1 | sh tools/first_red.sh --all
#
#   --cmd 42      every command the report suggests is written as the `42`
#                 command that runs the same tests (tools/42.sh), not as Bazel's
#   --next FILE   also write the one thing the report names next, as a line
#                 "BUCKET<tab>MODULE<tab>EXERCISE<tab>LABEL" (a dash for a
#                 column it cannot fill; an empty file when nothing is next).
#                 EXERCISE is "exNN FUNCTION" for one function of a library
#                 (A LIBRARY'S FUNCTIONS, below).
#                 BUCKET is build, ko, work, wrong, slow or rigour. `42` reads it
#                 to show that one test's log, in the report's own order.
#   --triage FILE also write every red exercise's bucket, one line each,
#                 "BUCKET<tab>MODULE<tab>EXERCISE", in the report's order:
#                 the verdicts it words, work being "not written yet". BUCKET
#                 is one of --next's, or norun (nothing of it ran); a test of
#                 the whole module is its own EXERCISE (deliverable_files).
#                 An empty file when nothing failed. submit.sh's
#                 --written-only reads it. A library's functions are filed
#                 under their exercise here, one line per bucket: the push
#                 is the whole library, never one of its functions.
#   --written MODDIR  no report, and nothing read from stdin: one line per
#                 exercise of MODDIR's subject() contract, in its order,
#                 "STATE<tab>exNN<tab>PART". STATE is stub where the report
#                 would call it "not written yet" (no file of it holds a body,
#                 as stub_check reads them) and written otherwise; PART is
#                 mandatory where the contract's `mandatory` names it, and
#                 optional otherwise, every exercise of a contract that names
#                 none. Exit 2 when no contract could be read. submit.sh reads
#                 it for the floor --written-only will not push below.
#   --members MODDIR  no report: one line per function of MODDIR's contract,
#                 "exNN<tab>FUNCTION", in its order (the keys of each
#                 exercise's `functions = {...}`); nothing for a project whose
#                 contract has none. Exit 2 when no contract could be read.
#
# Exit 0 = the report is complete. Exit 1 = the run did not complete: something
# did not build, or the run stopped early, so part of it could not say anything,
# and a script piping into this notices. Exit 2 = this script could not run.
#
# Two zoom levels, because "what do I do next" and "how much is left" are
# different questions and the second one is what makes a wall of red feel
# hopeless. The default answers the first and ends with a module-sized picture
# of the second. --all expands that to one line per exercise -- still one line,
# never the two-or-three Bazel prints, because at a hundred failures the log
# paths are noise and the exercise is the unit you actually think in.
#
# THE PROBLEM. A whole-repo run reports every unwritten exercise at once — on a
# fresh clone that is over two hundred red targets, and on a half-finished one
# it is still a hundred. All of it is true and none of it is an instruction.
# "What do I do next?" is not answerable by reading it.
#
# WHY NOT JUST RUN THE TESTS IN ORDER. Because Bazel will not. It schedules
# tests in parallel and promises no order, and it does not deliver one even when
# told to serialise: measured on c-10, three runs of
#
#     bazel test //c-piscine/c-piscine-c-10/... --local_test_jobs=1 --notest_keep_going --nokeep_going
#
# stopped on ex00_build, then ex02_ccarry_output, then ex01_two_output. Same
# command, same tree, three answers. So the run stays parallel and fast, and the
# ORDER is applied to the report, where it is deterministic and free. (The
# --nokeep_going is needed since .bazelrc sets --keep_going: with it on, a c-11
# run under --notest_keep_going ran all 139 tests past the first red one.)
#
# CODE THAT DOES NOT BUILD IS READ FIRST. A student's code never fails the
# Bazel build: a syntax error, a warning under -Werror, a leftover main() or a
# missing file makes the program a STAND-IN (tools/standin.sh) that prints the
# compiler's words, and every test that runs it FAILS with them in its log. So
# a FAILED test is not always a wrong answer: when its log holds the stand-in's
# mark, nothing was built. This reads each FAILED test's log -- printed inline
# under --test_output=errors, or the test.log Bazel names under the FAILED line
# -- and files such an exercise under DOES NOT BUILD, with the first line of
# the log that names one of its files.
#
# Unless there was NOTHING to build: no .c file, no Makefile, a Makefile whose
# default goal compiles nothing. That is an EMPTY stand-in (tools/standin.sh),
# and it is exactly what an exercise nobody has started looks like -- the stub
# Makefile of BSQ and Rush 02 only echoes. Filed under DOES NOT BUILD, a fresh
# clone's report opened "SOMETHING DOES NOT BUILD — fix this first ... graded
# 0" and sent every newcomer to BSQ. So stub_check decides, as it does for a
# red output: over a stub, an empty stand-in is an exercise not written yet;
# over written files (a Makefile whose goal builds something else, a makefile
# that is not a Makefile) it does not build.
#
# A BUILD ERROR is still read too, because the harness can have one: a file of
# its own that does not compile, a download that failed, a module older than
# the stand-in. Then the targets that need it print FAILED TO BUILD, and
# every other target still runs (.bazelrc sets --keep_going); a target Bazel
# cannot analyse is left out of the summary instead. Under --nokeep_going the
# first error ends the run and the rest print NO STATUS. Either way Bazel ends
# with "ERROR: Build did NOT complete successfully", lists only the first few
# FAILED TO BUILD targets, and leaves a target it could not analyse out of its
# summary altogether.
#
# This script used to read the FAILED lines and nothing else, so a build error
# came out as "nothing failed" (no FAILED line: measured on a stub with a
# leftover main() and no -k, "Executed 3 out of 117 tests: 3 tests pass, 1
# fails to build, and 113 were skipped"), or as "not written yet" (a FAILED TO
# BUILD on exNN_output). So the whole log is read first, and when it holds any
# of those markers the report opens with them: DOES NOT BUILD for each exercise
# that does not build, with the first compiler or linker line that names one
# of its turn-in files, and a count of what never ran. "nothing failed" is
# never printed then, and the exit status is 1.
#
# DOES NOT BUILD is said only of an exercise a line of the log ties to your
# files: a compiler or linker line, or a turn-in file that is missing. A
# FAILED TO BUILD label alone is not that: a broken harness file or a download
# that failed gives the same label to answers that pass. Such an exercise is
# listed as DID NOT RUN, under THE BUILD STOPPED when nothing else is wrong. A
# run that stopped for any other reason -- Ctrl-C, a red test under
# --notest_keep_going --nokeep_going -- is reported as stopped, with its first
# error and what never ran. None of it is blamed on your code.
#
# THE ORDER, and why it is not just alphabetical. The reds are not all the same
# kind, and the harness already knows the difference:
#
#   A FRESH STUB passes norm, compile, files, forbidden and prototype, and fails
#   output. That is the whole design of the level ladder.
#
# So a red in one of those five, at basic, USUALLY means you wrote something
# that breaks a rule that scores zero wherever the project is graded. Usually,
# not always — and the exception
# is why this script asks rather than assumes. The same is true of every
# other layer at basic but output -- allocfail, and valgrind where the
# contract grades memory -- which wait for the output and so never run on a
# stub at all.
#
# c-08's deliverable IS a header. A stubbed header defines nothing, so the
# subject's own main() cannot compile against it, and `compile` is red on an
# exercise nobody has started. An earlier version of this script called that
# "something you wrote breaks a rule" on a fresh clone, which is precisely the
# beginner-sends-hunting-a-bug-that-is-not-there failure this repo rates second
# worst.
#
# So for any exercise in that bucket it asks tools/stub_check.sh whether the
# deliverable is still a stub — the tool whose entire job is that question. A
# stub cannot have broken a rule; it demotes to ordinary work.
#
# The same question is asked of a red OUTPUT. A red output on a stub is what an
# unwritten exercise looks like; on a written file it is a bug, and calling a
# finished rush "not written yet" over one wrong file descriptor sent its
# author looking for why Bazel could not see their files.
#
# A TIMEOUT gets no verdict: the test was stopped before it finished, so it
# has a bucket of its own that names no cause. Filed with FAILED, a timed-out
# output on a loaded machine read "what it does is not what the test
# expects". A FAILED whose runner stopped it at the test's time limit, and
# said so, goes in the same bucket (pass 0 below).
#
# A LIBRARY'S FUNCTIONS. A project whose subject has one library turned in,
# every function of it graded on its own, lists them in its contract
# (exercise(functions = {"ft_strlen": [], ...}): each key a function, its
# value what that function may call), and each function's tests are named
# exNN_<function>_<layer> and run together as the suite //<project>:<function>.
# Keyed by exercise alone, forty functions' reds were one line, "ex00 output
# x40", and one written function made every other one "written, and wrong".
# So a target's FUNCTION is the longest key F of its exercise such that its
# name is exNN_F_<something>, and its reds are filed by module, exercise and
# function: shown as "ex00 ft_strlen", run again by that function's suite,
# and called written only when stub_check --defines finds a body in it. A
# target of the whole library (exNN_norm, exNN_build) has no function, and
# is filed by its exercise as before -- first, ahead of every function. Its
# red output is judged by the one file it reads (lib_reads, below: the
# Makefile, README.md), run again by its own label, never by the suite of
# the whole library, and worded after that file; and --next names its label,
# as for a function.
#
# A handful of buckets, one objective, and the rest counted rather than listed.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "first_red.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk dirname find grep mktemp mv rm sed sort tr

# THE TURN-IN FOLDER OF AN EXERCISE, read from its project's subject
# contract -- the subject() call its BUILD.bazel opens with, which every
# macro reads (tools/subject.bzl) -- never guessed from what is on disk.
#
#   turnin_of MODDIR EX   prints "deliverable/exNN" for an entry whose dir is
#                         "exNN/", "deliverable" for dir = None (a subject with
#                         no turn-in directory line: BSQ, the Common Core);
#                         prints nothing and is false when there is no
#                         BUILD.bazel, no subject(), or no entry for EX.
#
# It used to be guessed: deliverable/exNN if that folder existed, else
# deliverable/ itself if no exNN folder did. A BSQ tree that still held the
# old ex00/ folder was then read there instead of at its root, and a project
# that turns in under exNN/ was read at its root as soon as its exNN folder
# was missing -- each a written exercise called "not written yet", or the
# reverse.
#
# The contract is Starlark; this reads the form every project writes it in
# (buildifier's): a line `subject(` at the start, an entry `"NN": exercise(`
# holding one `dir = "..."` or `dir = None`, the call closed by a `)` at the
# start of a line. A comment is dropped before anything is read, so a note
# that mentions `dir = None` is not the contract.
# //tools/tests:macro_fixtures_test holds this reading to the macros' own
# turnin_dir() (each package's :turnin_dirs) for every exercise of every
# project and of the toy ones, and
# //tools:conventions checks that it finds an entry for every tests/exNN
# folder.
turnin_of() {  # turnin_of MODDIR EX
	[ -f "$1/BUILD.bazel" ] || return 1
	_to=$(awk -v key="\"${2#ex}\": exercise(" '
		/^subject\(/ { insub = 1; next }
		insub && /^\)/ { exit }
		!insub { next }
		!inex {
			p = index($0, key)
			if (!p) next
			inex = 1; depth = 0; text = ""
			line = substr($0, p + length(key) - 1)
			sub(/#.*/, "", line)
		}
		inex {
			if (text == "") text = line
			else { line = $0; sub(/#.*/, "", line); text = text " " line }
			depth += gsub(/\(/, "(", line) - gsub(/\)/, ")", line)
			if (depth > 0) next
			if (match(text, /[(, ]dir *= *None[,) ]/)) { print "deliverable"; exit }
			if (match(text, /[(, ]dir *= *"[^"]*"/)) {
				d = substr(text, RSTART, RLENGTH)
				sub(/^[^"]*"/, "", d); sub(/"$/, "", d); sub(/\/$/, "", d)
				print "deliverable/" d
			}
			exit
		}' "$1/BUILD.bazel")
	[ -n "$_to" ] || return 1
	printf '%s\n' "$_to"
}

# stub_check.sh is found NEXT TO THIS SCRIPT, not relative to the working
# directory. A runner that only works when you happen to be standing in the
# repo root is a runner that fails the first time it is called from anywhere
# else -- and this one is meant to be piped into from wherever you ran bazel.
STUB_CHECK="$(dirname "$0")/stub_check.sh"

# Is this exercise written? stub_check.sh answers per file: 0 a stub, 1 holds a
# body, 2 not a kind it reads (numbers.dict, a stray a.out) or a file that is
# neither (empty, or a .c or .h with no 42 header). What 2 counts as is the
# caller's: in the rule bucket a stray file, or a lost header, is itself the
# rule broken, so it counts as written; beside a red output it says nothing
# about the code, so it does not. A shell exercise is its generator, never the
# deliverable/ that the generator writes.
#
# EX can be "exNN FUNCTION", one function of a library (A LIBRARY'S
# FUNCTIONS, above): then the question is that function's body, asked of
# stub_check --defines over every .c and .h of the turn-in folder -- 1 it
# has a body, 0 a stub, 3 no file defines it (not written either), 2 no
# verdict. A file of the library holding another function's body says
# nothing about this one.
is_written() {  # is_written MOD EX UNKNOWN_COUNTS(0|1)
	_m=$(printf '%s' "$1" | sed 's|^//||')
	case "$2" in
		*" "*)
			_iw_fn=${2#* }
			_d=$(turnin_of "$_m" "${2%% *}") || return 1
			_d="$_m/$_d"
			[ -d "$_d" ] || return 1
			_iw_unk=$3
			find "$_d" -type f \( -name '*.c' -o -name '*.h' \) | {
				set --
				while IFS= read -r _f; do
					set -- "$@" "$_f"
				done
				[ $# -gt 0 ] || exit 1
				sh "$STUB_CHECK" --defines "$_iw_fn" "$@" > /dev/null 2>&1
				case $? in
					1) exit 0 ;;
					0 | 3) exit 1 ;;
					*) [ "$_iw_unk" -eq 1 ] && exit 0; exit 1 ;;
				esac
			}
			return ;;
	esac
	if [ -f "$_m/generators/$2.sh" ]; then
		sh "$STUB_CHECK" --file "$_m/generators/$2.sh" > /dev/null 2>&1
		[ $? -eq 1 ]
		return
	fi
	# The exercise's turn-in folder, as its subject contract names it
	# (turnin_of, above). Where there is no contract to read -- a run piped
	# in from outside the workspace -- there is nothing to inspect either.
	_d=$(turnin_of "$_m" "$2") || return 1
	_d="$_m/$_d"
	[ -d "$_d" ] || return 1
	find "$_d" -type f | {
		while IFS= read -r _f; do
			sh "$STUB_CHECK" --file "$_f" > /dev/null 2>&1
			case $? in
				0) ;;
				1) exit 0 ;;
				*) [ "$3" -eq 1 ] && exit 0 ;;
			esac
		done
		exit 1
	}
}

# THE FILE A TEST OF A WHOLE LIBRARY READS. A library's own tests -- a target
# of its exercise with no function, such as exNN_build or exNN_readme (A
# LIBRARY'S FUNCTIONS, above) -- each read one file of the turn-in folder, and
# whether such a red is that file unwritten or that file wrong is the file's
# question, never the whole folder's: asked of the folder, one function
# written made a stub README "written, and it runs". Read from the tail of the
# target's name after exNN_, its layer as _SUFFIX_LAYER spells it:
#
#   build...     the Makefile at the root of the turn-in folder
#   readme...    README.md there
#
# Those are the tails a library's own red output has at basic. Any other
# names no one file: lib_reads LABEL EX prints how the report names the file
# ("the Makefile"), and is false for such a tail, so the caller asks the
# whole folder, as is_written does. lib_read_written MOD EX LABEL says what
# that file is: 0 it holds a body (stub_check 1), 1 a stub, 3 it is missing,
# 4 it is empty (stub_check 2: for these two kinds, nothing in it but blanks),
# 2 when no file is known for the label, and 5 when there is nothing to
# inspect (no contract to read: a run piped in from outside the workspace).
# Each of 1, 3 and 4 is not written, and the report says which: a README
# deleted is not "still a stub"; 5 says nothing about the file.
lib_reads() {  # lib_reads LABEL EX
	_lr=${1##*:}
	_lr=${_lr#"$2"_}
	case "$_lr" in
		build | build_*) echo "the Makefile" ;;
		readme | readme_*) echo "README.md" ;;
		*) return 1 ;;
	esac
}
lib_read_written() {  # lib_read_written MOD EX LABEL
	_lw=$(lib_reads "$3" "$2") || return 2
	_m=$(printf '%s' "$1" | sed 's|^//||')
	_d=$(turnin_of "$_m" "$2") || return 5
	_d="$_m/$_d"
	case "$_lw" in
		"the Makefile") _f="$_d/Makefile" ;;
		*) _f="$_d/README.md" ;;
	esac
	[ -f "$_f" ] || return 3
	sh "$STUB_CHECK" --file "$_f" > /dev/null 2>&1
	case $? in
		1) return 0 ;;
		0) return 1 ;;
		*) return 4 ;;
	esac
}

# THE CONTRACT'S EXERCISES AND ITS MANDATORY PART, read from the subject()
# call the way turnin_of reads it, comments dropped first: every entry
# `"NN": exercise(`, in the order written, and the list `mandatory = [...]`,
# on one line or over several. Prints one exNN a line, nothing for a
# contract with no mandatory list; false with no BUILD.bazel or no subject().
# //tools/tests:macro_fixtures_test holds both readings, through --written,
# to the macros' own (each package's :turnin_dirs and :mandatory).
#
# And `functions`: "exNN<TAB>FUNCTION" for every key of every exercise's
# `functions = {...}`, in order -- the keys only, never the strings in their
# values (what each function may call). tools/fortytwo/workspace.py's
# contract_functions() reads the same keys for the words `42` takes.
#
# A comment starts at the first # that is in no string (dir = "a#b" holds
# none), and a functions block ends at the first } in no string: the way
# conventions.sh (contract_fns) and workspace.py read a line, which
# //tools/tests:fortytwo_test holds the three to.
contract_read() {  # contract_read MODDIR exercises|mandatory|functions
	[ -f "$1/BUILD.bazel" ] || return 1
	awk -v what="$2" '
		# The first position of C in S that is in no string, or 0.
		function bare(s, c,   i, L, ch, q) {
			L = length(s); q = 0
			for (i = 1; i <= L; i++) {
				ch = substr(s, i, 1)
				if (q && ch == "\\") { i++; continue }
				if (ch == "\"") q = !q
				else if (!q && ch == c) return i
			}
			return 0
		}
		/^subject\(/ { insub = 1; found = 1; next }
		insub && /^\)/ { exit }
		!insub { next }
		{
			line = $0
			if ((c = bare(line, "#")) > 0) line = substr(line, 1, c - 1)
			if (what == "functions")
				text = text "\n" line
			else if (what == "exercises") {
				while (match(line, /"[0-9][0-9]": *exercise\(/)) {
					print "ex" substr(line, RSTART + 1, 2)
					line = substr(line, RSTART + RLENGTH)
				}
			} else
				text = text " " line
		}
		END {
			if (!found) exit 1
			if (what == "functions") {
				rest = text
				while (match(rest, /"[0-9]+"[ \t]*:[ \t]*exercise\(|(^|[^A-Za-z0-9_])functions[ \t]*=[ \t]*\{/)) {
					tok = substr(rest, RSTART, RLENGTH)
					rest = substr(rest, RSTART + RLENGTH)
					if (tok ~ /exercise\($/) {
						ex = tok; sub(/^"/, "", ex); sub(/".*$/, "", ex); ex = "ex" ex
						continue
					}
					e = bare(rest, "}")
					body = e ? substr(rest, 1, e - 1) : rest
					rest = e ? substr(rest, e + 1) : ""
					if (ex == "") continue
					while (match(body, /"[^"]+"[ \t\n]*:/)) {
						k = substr(body, RSTART + 1, RLENGTH - 1)
						sub(/"[ \t\n]*:$/, "", k)
						body = substr(body, RSTART + RLENGTH)
						if (!((ex, k) in seen)) { seen[ex, k] = 1; print ex "\t" k }
					}
				}
				exit 0
			}
			if (what != "mandatory" || !match(text, /[(, ]mandatory *= *\[/)) exit 0
			rest = substr(text, RSTART + RLENGTH)
			rest = substr(rest, 1, index(rest, "]") - 1)
			while (match(rest, /"[0-9][0-9]"/)) {
				print "ex" substr(rest, RSTART + 1, 2)
				rest = substr(rest, RSTART + RLENGTH)
			}
		}' "$1/BUILD.bazel"
}

# WHETHER THE CONTRACT SAYS ITS GRADER JUDGES MEMORY: its subject() call
# declares memory_graded (tools/subject.bzl), read as contract_read reads the
# rest, a comment dropped first. True for a module whose valgrind layer then
# sits at basic (tools/defs.bzl's _layer_level), as its targets' tags say.
# Declared is any value but None, however it is spelled -- a dict over
# several lines, a string built in parentheses, a name bound above: what
# that value holds is subject()'s to check, and a value it refuses fails the
# load before any test runs. Only the argument's name is read, never its
# shape: this read the line as `memory_graded = "` and filed a dict, or a
# parenthesised one, as no declaration (//tools/tests:macro_fixtures_test
# holds it to every contract the macros read).
graded_of() {  # graded_of MODDIR
	[ -f "$1/BUILD.bazel" ] || return 1
	awk '
		/^subject\(/ { insub = 1; next }
		insub && /^\)/ { exit }
		!insub { next }
		{ line = $0; sub(/#.*/, "", line); text = text " " line }
		END {
			if (!match(text, /[(, \t]memory_graded[ \t]*=[ \t]*/)) exit 1
			rest = substr(text, RSTART + RLENGTH)
			exit (rest ~ /^None([^A-Za-z0-9_]|$)/)
		}' "$1/BUILD.bazel"
}

# --written MODDIR: each exercise's STATE and PART (see the usage above). The
# judge is is_written's, with what stub_check cannot read left uncounted: the
# one that leaves an exercise "not written yet" in the report, so a floor
# built on this and the report's own words never disagree.
written_of() {  # written_of MODDIR
	[ -f "$STUB_CHECK" ] || { echo "first_red.sh: $STUB_CHECK is not beside it" >&2; return 2; }
	_wo_ex=$(contract_read "$1" exercises) || _wo_ex=""
	if [ -z "$_wo_ex" ]; then
		echo "first_red.sh: no subject() contract with an exercise in $1/BUILD.bazel" >&2
		return 2
	fi
	_wo_mand=$(contract_read "$1" mandatory) || return 2
	_wo_mand=" $(printf '%s\n' "$_wo_mand" | tr '\n' ' ')"
	for _wo_e in $_wo_ex; do
		case "$_wo_mand" in
			*" $_wo_e "*) _wo_p=mandatory ;;
			*) _wo_p=optional ;;
		esac
		if is_written "$1" "$_wo_e" 0; then _wo_s=written; else _wo_s=stub; fi
		printf '%s\t%s\t%s\n' "$_wo_s" "$_wo_e" "$_wo_p"
	done
}

MODE=summary
CMD=bazel
NEXT=""
TRIAGE=""
while [ $# -gt 0 ]; do
	case "$1" in
		--all) MODE=all; shift ;;
		--cmd)
			case "${2:-}" in
				bazel | 42) CMD=$2; shift 2 ;;
				*) echo "first_red.sh: --cmd bazel|42" >&2; exit 2 ;;
			esac ;;
		--next)
			[ $# -ge 2 ] && [ -n "$2" ] || { echo "first_red.sh: --next FILE" >&2; exit 2; }
			NEXT=$2; shift 2 ;;
		--triage)
			[ $# -ge 2 ] && [ -n "$2" ] || { echo "first_red.sh: --triage FILE" >&2; exit 2; }
			TRIAGE=$2; shift 2 ;;
		# The turn-in folder of one exercise, as the report reads it: for
		# the checks that hold this reading to the contract's.
		--turnin)
			[ $# -ge 3 ] || { echo "first_red.sh: --turnin MODDIR EX" >&2; exit 2; }
			turnin_of "$2" "$3"
			exit ;;
		# Whether the module's contract declares memory_graded, as the
		# report reads it ("graded" or "not graded"): for the check that
		# holds this reading to the macros' (graded_of).
		--graded)
			[ $# -ge 2 ] && [ -n "$2" ] || { echo "first_red.sh: --graded MODDIR" >&2; exit 2; }
			if graded_of "$2"; then echo graded; else echo "not graded"; fi
			exit ;;
		--written)
			[ $# -ge 2 ] && [ -n "$2" ] || { echo "first_red.sh: --written MODDIR" >&2; exit 2; }
			written_of "$2"
			exit ;;
		# A library's functions, as the report reads them: for the checks
		# that hold this reading to the contract's.
		--members)
			[ $# -ge 2 ] && [ -n "$2" ] || { echo "first_red.sh: --members MODDIR" >&2; exit 2; }
			contract_read "$2" functions || {
				echo "first_red.sh: no subject() contract in $2/BUILD.bazel" >&2
				exit 2
			}
			exit 0 ;;
		*) echo "first_red.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
# Emptied first, so a report that names nothing next (nothing failed) leaves
# no stale line from an earlier run behind.
if [ -n "$NEXT" ]; then
	: > "$NEXT" || { echo "first_red.sh: cannot write $NEXT" >&2; exit 2; }
fi
if [ -n "$TRIAGE" ]; then
	: > "$TRIAGE" || { echo "first_red.sh: cannot write $TRIAGE" >&2; exit 2; }
fi

# The build stand-in's mark, from the one file that defines it (see
# tools/standin.sh): a test whose log holds it ran a program that never built.
_sl="$(dirname "$0")/standin.sh"
[ -f "$_sl" ] || { echo "first_red.sh: $_sl is not beside it" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"

# THE ONE LAYER A CONTRACT LOWERS to basic, tools/defs.bzl's _GRADED_LAYER:
# where a module's subject() declares memory_graded (graded_of), a red of
# this layer is a KO there, filed as every other basic layer but output is.
# Not every test of
# it waits for an output: c_function's arms do, and c_program's -- a survive
# case's on the case its output test waits for, where _survive_gate finds
# one -- and SKIP on a stub. One kind runs ungated: c_mem_check's probe run.
# (Every memcheck sample of a corpus waits behind a gate, as every corpus
# replay does but a manual one or Rush 00's crash-only sanitizer twin:
# c_levels()' audit, _ungated_diff_problems.) It passes on a stub by
# construction (a stub that allocates nothing leaks nothing and touches no
# block), which the stub-tree run of a real project proves, as it proves
# every other stub-green layer. A second would be a survive case whose
# exercise has no case _survive_gate can wait on (none at basic with one
# expected file and plain arguments, run where the test runs): it runs
# ungated and meets the stand-in of a stub that builds nothing. No module has
# one today.
GRADED_LAYER='valgrind'

# WHICH LAYER A RED TARGET IS, AND AT WHICH LEVEL, read from the tables
# c_levels()' audit holds every test to (tools/defs.bzl, found beside this
# script): _SUFFIX_LAYER maps the end of a target's name to its layer and
# level, _LAYER_LEVEL gives a layer's own level, and _RAISED lists the targets
# raised above it. Only a red AT BASIC is a KO wherever the project is
# graded, so only one at basic is filed as the exercise's work (`output`) or
# as the student's to fix first (every other layer there); every other red is
# rigour. That second half used to be a list of the five layers a stub
# passes, which left a basic allocfail red under ALSO RED (V197). And this
# used to walk a list of its own, which knew `output` and none of
# the other basic output targets -- Rush 00's _defense, _survive and _main, Rush
# 01's _sweep -- and filed them under ALSO RED, "a rigour layer above what the
# grader checks", over a case the subject says the defense runs.
DEFS="$(dirname "$0")/defs.bzl"
[ -f "$DEFS" ] || { echo "first_red.sh: $DEFS is not beside it" >&2; exit 2; }

# THE TESTS OF A WHOLE MODULE, which belong to no exercise (tools/defs.bzl's
# _MODULE_TESTS): deliverable_files, what is pushed outside every exercise's
# folder. Filed under its own name, so the line reads as a target a student
# can run, and never demoted to "not written yet": a stub leaves nothing
# outside the exercise folders, so a red one is always something to fix.
MODULE_TESTS='deliverable_files'
is_module_test() {
	case " $MODULE_TESTS " in
		*" $1 "*) return 0 ;;
		*) return 1 ;;
	esac
}

# The words tools/runner_lib.sh puts in the log of a test whose runner stopped
# it at the test's own time limit (RL_OVERRUN_MARK there): read from the
# library itself, so the two cannot drift. Found beside this script; without
# it, such a test is filed as an ordinary FAILED.
OVERRUN_MARK=$(sed -n 's/^RL_OVERRUN_MARK="\(.*\)"$/\1/p' "$(dirname "$0")/runner_lib.sh" 2> /dev/null)
# And the line it puts above a table that names the failing case
# (RL_TABLE_MARK there), read the same way. Without it no log is said to
# hold a table, and the report words every wrong output "That log says why",
# which is true of any log.
TABLE_MARK=$(sed -n 's/^RL_TABLE_MARK="\(.*\)"$/\1/p' "$(dirname "$0")/runner_lib.sh" 2> /dev/null)
# And the line it puts in the log of a test whose own test program did not
# build (RL_BUILD_MARK there, tools/header_check.sh): nothing ran, so the test
# is filed as an empty stand-in is, under DOES NOT BUILD when its exercise is
# written. Without it, such a test reads as a wrong output.
BUILD_MARK=$(sed -n 's/^RL_BUILD_MARK="\(.*\)"$/\1/p' "$(dirname "$0")/runner_lib.sh" 2> /dev/null)

WORK=$(mktemp) || exit 2
trap 'rm -f "$WORK" "$WORK.log" "$WORK.t" "$WORK.b" "$WORK.m" "$WORK.2" "$WORK.e" "$WORK.l" "$WORK.u" "$WORK.x"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# The tables, one entry per line as buildifier leaves them (the same reading
# //tools:conventions holds docs/reference.md's copies to):
#   S<TAB>suffix<TAB>layer<TAB>level<TAB>layer|own
#                                        one per _SUFFIX_LAYER entry, and
#                                        whether its level is its layer's
#   R<TAB>//package:target<TAB>level     one per _RAISED entry
#   G<TAB>//package                      a red module whose contract lowers
#                                        GRADED_LAYER (added below)
awk '
	/^_LAYER_LEVEL = \{/ { inl = 1; next }
	inl && /^\}/ { inl = 0 }
	inl && /^[ \t]*"[a-z0-9_]+": [0-9]/ {
		k = $1; gsub(/[":]/, "", k)
		v = $2; gsub(/[^0-9]/, "", v)
		lv[k] = v
	}
	/^_SUFFIX_LAYER = \{/ { ins = 1; next }
	ins && /^\}/ { ins = 0 }
	ins && /^[ \t]*"_/ {
		line = $0
		gsub(/[" (),:]/, " ", line)
		split(line, f, " ")
		n++; sfx[n] = f[1]; sly[n] = f[2]; slv[n] = f[3]
	}
	/^_RAISED = \{/ { inr = 1; next }
	inr && /^\}/ { inr = 0 }
	inr && /^[ \t]*"/ {
		line = $0
		gsub(/[",:]/, " ", line)
		split(line, f, " ")
		printf "R\t//%s:%s\t%s\n", f[1], f[2], f[3]
	}
	END {
		for (i = 1; i <= n; i++)
			printf "S\t%s\t%s\t%s\t%s\n", sfx[i], sly[i], (slv[i] == "None") ? lv[sly[i]] : slv[i], \
				(slv[i] == "None") ? "layer" : "own"
	}' "$DEFS" > "$WORK.l"
if ! awk -F'\t' '$1 == "S" && $2 == "_output" && $3 == "output" && $4 == 1 { f = 1 } END { exit !f }' "$WORK.l"; then
	echo "first_red.sh: tools/defs.bzl's _SUFFIX_LAYER reads as empty or has no" >&2
	echo "  _output at basic, so no red could be filed by its level. If the table" >&2
	echo "  moved, move this reader with it." >&2
	exit 2
fi

# The whole log, kept: the build markers can sit anywhere in it, and the FAILED
# lines are read from the same copy. Colour codes go (--color=yes puts them
# around every line Bazel prints), and so do carriage returns, which a progress
# line uses to rewrite itself and which would glue it to the line after.
ESC=$(printf '\033')
tr '\r' '\n' | sed "s/${ESC}\[[0-9;]*[A-Za-z]//g" > "$WORK.log"

# Pass 0: read what Bazel says about the BUILD, before any test verdict.
#
#   $WORK.t  every red target, "label<TAB>run|build|timeout", run = its test
#            failed, build = it never got a test to run (FAILED TO BUILD),
#            timeout = it ran out of time: Bazel stopped it (TIMEOUT), or its
#            runner stopped it first and said so (see below)
#
# A runner that runs student code stops a run a few seconds before Bazel
# would, and says which case it was on (tools/runner_lib.sh), so a test that
# ran out of its time limit is now a FAILED with something in its log rather
# than a silent TIMEOUT. It is still no verdict on the code -- a loaded machine
# stops a correct answer the same way -- so a FAILED whose log says that is
# filed with the TIMEOUTs. The log is the one Bazel names, in "FAIL: //t (see
# PATH)" or on the line under the summary's FAILED, and the words looked for
# are runner_lib.sh's RL_OVERRUN_MARK, which only a run the TEST's limit
# stopped prints: a case that ran out of its own cap is a hang, and stays a
# verdict.
#   $WORK.b  every exercise the build left red, in the order the log names it:
#            "mod<TAB>ex<TAB>what<TAB>line", what = the kind of line kept for
#            it: source, missing, link or test (a line that ties it to the
#            student's files: it does not build), or none (only a FAILED TO
#            BUILD or unanalysed label: it did not run, and nothing says why)
#   $WORK.m  the counts, one "name<TAB>value" per line
#   $WORK.x  every red target whose log holds the table mark (TABLE_MARK,
#            above): one label a line, read by pass 2
#
# An exercise is found three ways: from a FAILED TO BUILD target, from a target
# Bazel could not analyse, and from a compiler or linker line. The last is the
# one a student can act on, so each exercise keeps the first line of the most
# useful kind the log holds for it: one naming a turn-in file (deliverable/...
# with a line number, or a turn-in file that is missing), then a linker line
# that names only an object file, then one in the test program built against
# the turn-in.
awk -F'\t' -v out="$WORK" -v mark="$STANDIN_MARK" -v nomark="$NOTURNIN_MARK" \
	-v broke="$STANDIN_BROKE" -v empty="$STANDIN_EMPTY" -v overmark="$OVERRUN_MARK" \
	-v tablemark="$TABLE_MARK" -v buildmark="$BUILD_MARK" '
	# "//c-piscine/c-piscine-c-11" for a path or label under that project.
	function modof(p) {
		sub(/^\/proc\/self\/cwd\//, "", p)
		sub(/^.*\/execroot\/_main\//, "", p)
		sub(/^\/\//, "", p)
		sub(/:.*$/, "", p)
		sub(/\/(deliverable|tests)\/.*$/, "", p)
		return "//" p
	}
	# The exercise a path names: the folder after deliverable/ or tests/.
	function exofpath(p) {
		if (!sub(/^.*[\/:](deliverable|tests)\//, "", p)) return "-"
		sub(/\/.*$/, "", p)
		return (p ~ /^ex[0-9]+$/) ? p : "-"
	}
	# The exercise a target name belongs to: ex06_bin, ex00_rush03_output.
	function exoftgt(t) {
		sub(/^.*:/, "", t)
		sub(/_.*$/, "", t)
		return (t ~ /^ex[0-9]+$/) ? t : "-"
	}
	# A line as a person reads it: no sandbox prefixes, no object-file paths,
	# the linker by its short name, and never wider than a terminal.
	function tidy(s) {
		gsub(/\t/, " ", s)
		gsub(/\/proc\/self\/cwd\//, "", s)
		gsub(/[^ ]*\/execroot\/_main\//, "", s)
		gsub(/external\/[^ ]*\/(x86_64-linux-gnu-)?ld(\.gold|\.bfd|\.lld)?:/, "ld:", s)
		gsub(/bazel-out\/[^ ]*\/_objs\/[^\/ ]*\//, "", s)
		gsub(/\.pic\.o/, ".o", s)
		sub(/^ERROR: [^ ]*\/BUILD\.bazel:[0-9:]* /, "ERROR: ", s)
		# "failed: (Exit 1): clang.sh failed: error executing CppLink command
		# (from cc_binary rule target //m:ex06_bin) <the command line>": the
		# action and the target are the part a person reads.
		sub(/: \(Exit [0-9]+\): [^ ]+ failed: error executing [A-Za-z]+ command/, "", s)
		if (match(s, /^ERROR: .* failed \(from [^)]*\)/)) s = substr(s, 1, RLENGTH)
		if (length(s) > 150) s = substr(s, 1, 147) "..."
		return s
	}
	# Rank of a line: one naming a file of the student (with its line
	# number) beats a linker line naming only an object file, which beats one
	# in the test program, which beats the bare headline of a stand-in (no
	# Makefile, no .c file), which beats nothing.
	function note(mod, ex, what, line,   k, r) {
		k = mod "\t" ex
		if (!(k in bwhat)) { border[++nb] = k; bwhat[k] = "none"; bline[k] = "-" }
		r = (what == "none") ? 0 : ((what == "standin" || what == "empty") ? 1 : ((what == "test") ? 2 : ((what == "link") ? 3 : 4)))
		if (r > brank[k] + 0) { brank[k] = r; bwhat[k] = what; bline[k] = line }
	}
	# A TEST LOG THAT HOLDS THE STAND-IN MARK. The build never fails on a
	# student code: what does not compile or link becomes a stand-in program
	# (tools/standin.sh), and every test that runs it fails with the words
	# of the compiler in its log. Such a test did not find a wrong answer --
	# nothing was built -- so its exercise goes under DOES NOT BUILD, with the
	# first line of the log that names a file of the student. Read from the
	# log printed inline (--test_output=errors) or from the test.log path
	# Bazel prints under a FAILED line; a copy of the log is all either is.
	function readlog(lbl, path,   l, got) {
		got = 0
		while ((getline l < path) > 0) {
			if (overmark != "" && index(l, overmark)) overrun[lbl] = 1
			if (tablemark != "" && index(l, tablemark) == 1) hastable[lbl] = 1
			if (index(l, mark)) got = 1
			if (buildmark != "" && index(l, buildmark) == 1) { got = 1; unbuilt[lbl] = 1 }
			if (got && index(l, empty)) sempty[lbl] = 1
			if (index(l, nomark) == 1) { got = 1; missing(lbl, l) }
			if (got) standin_line(lbl, l)
		}
		close(path)
		if (got) standin[lbl] = 1
	}
	# A test that had no files to check: the turn-in file is missing.
	function missing(lbl, l) {
		sline[lbl] = tidy(l); swhat[lbl] = "missing"
	}
	# The package of a LABEL: everything before the colon. modof() is for a
	# path, where it cuts at deliverable/ or tests/ -- which a package of the
	# harness own can have in its name (tools/tests/macro_fixtures).
	function modlabel(t) {
		sub(/:.*$/, "", t)
		return t
	}
	# Every log a failed test has (a sharded one has one per shard), once each.
	function addlog(lbl, path) {
		if ((lbl SUBSEP path) in haslog) return
		haslog[lbl, path] = 1
		logof[lbl] = logof[lbl] "\n" path
	}
	# A red target and what it is, in the order the log first names it.
	function status(lbl, st) {
		if (!(lbl in tstat)) tord[++nt] = lbl
		tstat[lbl] = st
	}
	function standin_line(lbl, l,   p) {
		if (lbl in sline && swhat[lbl] != "headline") return
		sub(/^[ \t]+/, "", l)
		if (l ~ /(error|multiple definition|undefined reference)/ &&
		    match(l, /[^ :]*\/deliverable\/[^ :]*:[0-9]+:/)) {
			sline[lbl] = tidy(l); swhat[lbl] = "source"
		} else if (l ~ /multiple definition of|undefined reference to/) {
			sline[lbl] = tidy(l); swhat[lbl] = "link"
		} else if (l ~ /error/ && match(l, /[^ :]*\/tests\/ex[0-9]+\/[^ :]*:[0-9]+:/)) {
			sline[lbl] = tidy(l); swhat[lbl] = "test"
		} else if (!(lbl in sline) && (index(l, broke) || index(l, empty))) {
			p = l; sub(/^[ \t]+/, "", p)
			sline[lbl] = tidy(p); swhat[lbl] = "headline"
		}
	}
	# The log of a test, printed inline by --test_output=errors, is not the
	# build: a compile layer quotes the compiler there on a tree that builds.
	/^=+ Test output for / {
		intest = 1; tlabel = $0
		sub(/^=+ Test output for /, "", tlabel); sub(/:$/, "", tlabel)
		next
	}
	intest && /^=+$/ { intest = 0; next }
	intest {
		if (overmark != "" && index($0, overmark)) overrun[tlabel] = 1
		if (tablemark != "" && index($0, tablemark) == 1) hastable[tlabel] = 1
		if (index($0, mark)) { standin[tlabel] = 1; tmark[tlabel] = 1 }
		if (buildmark != "" && index($0, buildmark) == 1) {
			standin[tlabel] = 1; tmark[tlabel] = 1; unbuilt[tlabel] = 1
		}
		if ((tlabel in tmark) && index($0, empty)) sempty[tlabel] = 1
		if (index($0, nomark) == 1) { standin[tlabel] = 1; missing(tlabel, $0) }
		if (tlabel in tmark) standin_line(tlabel, $0)
		next
	}
	# Where the log of a failed test is: PATH on the line under its FAILED in
	# the summary -- one per shard, under a "Stats over N runs" line, for a
	# sharded test -- and "FAIL: //t (Exit 1) (see PATH)" as it finishes. Read
	# in END (readlog), for the mark of a stand-in and RL_OVERRUN_MARK.
	lastfail != "" && /^[ \t]+\/[^ \t]*test\.log[ \t]*$/ {
		path = $0; gsub(/^[ \t]+|[ \t]+$/, "", path)
		addlog(lastfail, path)
		next
	}
	lastfail != "" && /^[ \t]+Stats over / { next }
	{ lastfail = "" }
	# Compiler and linker lines count only under the ERROR line of the action
	# that failed. The INFO, WARNING and progress lines of Bazel end that block.
	/^(INFO|WARNING|DEBUG|FAIL|TIMEOUT): / || /^\[[0-9]/ { inerr = 0 }
	/^FAIL: \/\// && match($0, /\(see [^)]*test\.log\)/) {
		t = $0; sub(/^FAIL: /, "", t); sub(/[ \t].*$/, "", t)
		addlog(t, substr($0, RSTART + 5, RLENGTH - 6))
	}
	/^ERROR: / { inerr = 1 }
	# Everything after the label, so both "  FAILED in 0.3s" and
	# "  (cached) FAILED in 0.3s" read as a status.
	/^\/\/[^ \t]*:[^ \t]+[ \t]/ {
		inerr = 0
		label = $0; sub(/[ \t].*$/, "", label)
		rest = substr($0, length(label) + 1)
		lastfail = ""
		if (rest ~ /FAILED TO BUILD/) {
			status(label, "build")
			note(modof(label), exoftgt(label), "none", "")
			listed_ftb++
		} else if (rest ~ /[ \t]FAILED( |$)/) {
			# Filed in END, once the line under it has named its log.
			status(label, "run")
			lastfail = label
		}
		# A test that ran out of time is red, and says nothing about why.
		# Reading FAILED alone made a run whose only red was a TIMEOUT "nothing
		# failed"; filing it with FAILED called it a wrong output.
		else if (rest ~ /[ \t]TIMEOUT( |$)/)
			status(label, "timeout")
		else if (rest ~ /NO STATUS/)
			nostatus++
		# Started and never finished: the run was stopped under it (Ctrl-C,
		# or --notest_keep_going cancelling what was still running). No
		# verdict, like NO STATUS -- and like it, not "nothing failed".
		else if (rest ~ /[ \t]INCOMPLETE( |$)/)
			incomplete++
		next
	}
	/Build did NOT complete successfully/ { stopped = 1; next }
	/No test targets were found/ { notests = 1; next }
	# Ctrl-C: the run stopped, and nothing in the build is why.
	/^ERROR: build interrupted/ { interrupted = 1 }
	/^Executed [0-9]+ out of [0-9]+ tests?:/ {
		if (match($0, /[0-9]+ fails? to build/)) ftb = substr($0, RSTART, RLENGTH) + 0
		if (match($0, /[0-9]+ (was|were) skipped/)) skipped = substr($0, RSTART, RLENGTH) + 0
		next
	}
	# A target Bazel could not analyse never reaches the summary at all: a
	# missing Makefile under -k left 28 of the 33 tests of Rush 02 out, and the
	# summary read "Executed 5 out of 5 tests". Counted from the lines that
	# name a TOP-LEVEL target (the WARNING under -k, "build aborted" without
	# it); the "(config: ...) failed" ERROR lines also name the dependencies.
	/errors encountered while analyzing target .\/\// || /Analysis of target .\/\/[^ ]*. .*failed/ {
		t = $0; sub(/^.*target .\/\//, "//", t); sub(/[^A-Za-z0-9_\/.:+-].*$/, "", t)
		if (/errors encountered while analyzing|failed; build aborted/ && !(t in unanalysed)) {
			unanalysed[t] = 1; nana++
		}
		note(modof(t), exoftgt(t), "none", "")
	}
	!inerr { next }
	# The target a build error belongs to, for the linker lines under it,
	# which name object files rather than sources.
	/^ERROR: .* failed: / {
		if (match($0, /rule target \/\/[^ )]+/))
			ctx = substr($0, RSTART + 12, RLENGTH - 12)
		else if (match($0, /(Linking|Compiling) [^ ]+ failed/)) {
			ctx = substr($0, RSTART, RLENGTH)
			sub(/^[A-Za-z]+ /, "", ctx); sub(/ failed$/, "", ctx)
			c = ctx; sub(/\/[^\/]*$/, "", c)
			sub(/^.*\//, "", ctx); ctx = "//" c ":" ctx
		}
	}
	# A turn-in file Bazel was told about and could not find: deleted, or
	# renamed (a makefile is not a Makefile).
	match($0, /\/\/[^ :]*:deliverable\/[^ ]*. (in \$\(location\)|is not a declared)/) ||
	match($0, /missing input file .\/\/[^ :]*:deliverable\/[^ ]*./) {
		f = $0; sub(/^.*\/\//, "//", f); sub(/[^A-Za-z0-9_\/.:+-].*$/, "", f)
		m = modof(f); sub(/^[^:]*:/, "", f)
		note(m, exofpath(":" f), "missing", "missing turn-in file: " substr(m, 3) "/" f)
		if (first == "") first = tidy($0)
		next
	}
	# A compiler or linker line naming a file under deliverable/.
	/(error|multiple definition|undefined reference)/ &&
	match($0, /[^ :]*\/deliverable\/[^ :]*:[0-9]+:/) {
		p = substr($0, RSTART, RLENGTH)
		note(modof(p), exofpath(p), "source", tidy($0))
		if (first == "") first = tidy($0)
		next
	}
	# The same, naming the test program compiled against the student files.
	/error/ && match($0, /[^ :]*\/tests\/ex[0-9]+\/[^ :]*:[0-9]+:/) {
		p = substr($0, RSTART, RLENGTH)
		note(modof(p), exofpath(p), "test", tidy($0))
		if (first == "") first = tidy($0)
		next
	}
	# A linker line naming only object files: the exercise comes from the
	# target the ERROR line above it was building, and only an exercise target
	# (exNN_bin) links a turn-in. The oracle failing to link is the machine.
	/multiple definition of|undefined reference to|undefined symbol/ && ctx != "" &&
	exoftgt(ctx) != "-" {
		note(modof(ctx), exoftgt(ctx), "link", tidy($0))
		if (first == "") first = tidy($0)
		next
	}
	# The first error of any other kind, for when nothing names a file.
	first == "" && /(^ERROR: |error: )/ &&
	!/Build did NOT complete|not all targets were analyzed|build aborted/ {
		first = tidy($0)
	}
	END {
		# A failed test that ran a stand-in is filed with what does not build;
		# one whose stand-in had nothing to build is "empty", which the shell
		# below settles with stub_check. A FAILED that its runner stopped at
		# the time limit of the test ran out of time: its log says so, in the
		# words of RL_OVERRUN_MARK. The log is read here, once every line that
		# names it has been seen, unless the inline copy already said which.
		for (i = 1; i <= nt; i++) {
			t = tord[i]; st = tstat[t]
			nlogs = (st == "run") ? split(logof[t], lp, "\n") : 0
			for (j = 2; j <= nlogs && !(t in standin) && !(t in overrun); j++)
				readlog(t, lp[j])
			if (st == "run" && (t in standin) && (t in sempty)) {
				st = "empty"
				note(modlabel(t), exoftgt(t), "empty", \
					(t in sline) ? sline[t] : "there was nothing to build (" t ")")
			} else if (st == "run" && (t in unbuilt)) {
				# The build mark: its own test program did not build. Over
				# a stub that is the exercise not written yet, as an empty
				# stand-in is, so it is settled the same way, below.
				st = "empty"
				note(modlabel(t), exoftgt(t), "empty", \
					(t in sline) ? sline[t] : "the test program did not build (" t ")")
			} else if (st == "run" && (t in standin)) {
				st = "standin"
				note(modlabel(t), exoftgt(t), (t in swhat) ? (swhat[t] == "headline" ? "standin" : swhat[t]) : "standin", \
					(t in sline) ? sline[t] : "your code did not build (" t ")")
			} else if (st == "run" && (t in overrun)) {
				st = "timeout"
			}
			print t "\t" st > (out ".t")
			if (t in hastable) print t > (out ".x")
		}
		for (i = 1; i <= nb; i++)
			printf "%s\t%s\t%s\n", border[i], bwhat[border[i]], bline[border[i]] > (out ".b")
		printf "stopped\t%d\nnotests\t%d\nnostatus\t%d\nskipped\t%d\n", stopped, notests, nostatus, skipped > (out ".m")
		printf "incomplete\t%d\n", incomplete > (out ".m")
		printf "interrupted\t%d\n", interrupted > (out ".m")
		printf "ftb\t%d\nlisted_ftb\t%d\n", ftb, listed_ftb > (out ".m")
		printf "unanalysed\t%d\nfirst\t%s\n", nana, (first == "" ? "-" : first) > (out ".m")
	}' "$WORK.log"
: >> "$WORK.t"; : >> "$WORK.b"; : >> "$WORK.x"
sort -u "$WORK.t" -o "$WORK.t"

# The functions of every library a red target belongs to, from its module's
# contract (A LIBRARY'S FUNCTIONS, above): "module<TAB>exNN<TAB>FUNCTION".
# Where there is no contract to read -- a run piped in from outside the
# workspace -- a module has none, and its reds are filed by exercise.
: > "$WORK.u"
sed 's/:.*$//' "$WORK.t" | sort -u | while IFS= read -r _um; do
	contract_read "${_um#//}" functions 2> /dev/null |
		sed "s|^|$_um$(printf '\t')|" >> "$WORK.u"
done

# EMPTY stand-ins, settled: over a stub, the exercise is not written yet --
# its tests are ordinary reds ("run"), and it leaves the build list; over
# written files it does not build ("standin"). Where there is nothing to
# inspect (run from outside the workspace), it counts as not written: an empty
# stand-in is far more often a fresh exercise than a broken one.
TAB=$(printf '\t')
: > "$WORK.e"
# (Names of its own: is_written sets _m.)
while IFS="$TAB" read -r _em _ee _ew _el; do
	[ "$_ew" = empty ] || continue
	if is_written "$_em" "$_ee" 0; then _es=written; else _es=unwritten; fi
	printf '%s\t%s\t%s\n' "$_em" "$_ee" "$_es" >> "$WORK.e"
done < "$WORK.b"
# A test whose own test program did not build (the build mark, pass 0) is
# settled the same way, its exercise kept with the compiler's line; one in
# the test program is said to be there, as a build line of that kind is.
if [ -s "$WORK.e" ]; then
	awk -F'\t' -v OFS='\t' '
		FILENAME == ARGV[1] { st[$1 FS $2] = $3; next }
		$3 == "empty" {
			if (st[$1 FS $2] != "written") next
			$3 = ($4 ~ /[^ :]*\/tests\/ex[0-9]+\/[^ :]*:[0-9]+:/) ? "test" : "standin"
		}
		{ print }' "$WORK.e" "$WORK.b" > "$WORK.2" && mv "$WORK.2" "$WORK.b"
fi
# Each empty red, settled with its exercise. One whose exercise is not in
# $WORK.e had a stronger build line beside it (a turn-in file missing, a
# line of the student's quoted, a link or a test program that failed), so
# its exercise is in the build list already, whatever stub_check says, and
# the red is filed with it: its layer is one of those that do not build.
# Left "empty", it was filed by its layer, and the DOES NOT BUILD line named
# only the other layers (V302).
if grep -q "$TAB"'empty$' "$WORK.t"; then
	awk -F'\t' -v OFS='\t' '
		function key(l,   m, t) {
			m = l; sub(/:.*$/, "", m)
			t = l; sub(/^[^:]*:/, "", t); sub(/_.*$/, "", t)
			if (t !~ /^ex[0-9]+$/) t = "-"
			return m FS t
		}
		FILENAME == ARGV[1] { st[$1 FS $2] = $3; next }
		$2 == "empty" { k = key($1); $2 = (!(k in st) || st[k] == "written") ? "standin" : "run" }
		{ print }' "$WORK.e" "$WORK.t" > "$WORK.2" && mv "$WORK.2" "$WORK.t"
fi

meta() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$WORK.m"; }
BROKE=0
if [ -s "$WORK.b" ] || [ "$(meta stopped)" -ne 0 ] || [ "$(meta notests)" -ne 0 ] ||
   [ "$(meta nostatus)" -ne 0 ] || [ "$(meta skipped)" -ne 0 ] || [ "$(meta ftb)" -ne 0 ] ||
   [ "$(meta interrupted)" -ne 0 ] || [ "$(meta incomplete)" -ne 0 ]; then
	BROKE=1
fi

if [ ! -s "$WORK.t" ] && [ "$BROKE" -eq 0 ]; then
	echo "first_red: nothing failed."
	exit 0
fi

# The red modules whose contract lowers GRADED_LAYER to basic, as the
# targets there are tagged.
for _gm in $(sed 's/:.*$//' "$WORK.t" | sort -u); do
	graded_of "${_gm#//}" && printf 'G\t%s\n' "$_gm" >> "$WORK.l"
done

# Pass 1: classify every failing target and aggregate per exercise. The build
# list comes first, so an exercise that does not build is filed as such
# whatever else about it is red: its output cannot be wrong if it never ran.
# One that only did not run is filed below every red that did run, because
# those are established and its missing targets are not.
awk -F'\t' -v glayer="$GRADED_LAYER" -v tables="$WORK.l" \
	-v module_tests="$MODULE_TESTS" -v members="$WORK.u" '
	BEGIN {
		while ((getline ln < members) > 0) {
			split(ln, q, "\t")
			nfns[q[1], q[2]]++
			fnof[q[1], q[2], nfns[q[1], q[2]]] = q[3]
		}
		close(members)
		while ((getline ln < tables) > 0) {
			split(ln, q, "\t")
			if (q[1] == "S") { slay[q[2]] = q[3]; slvl[q[2]] = q[4] + 0; sown[q[2]] = q[5] }
			else if (q[1] == "R") raised[q[2]] = q[3] + 0
			else if (q[1] == "G") graded[q[2]] = 1
		}
		close(tables)
		n = split(module_tests, g, " ")
		for (i = 1; i <= n; i++) whole[g[i]] = 1
	}
	FILENAME == ARGV[1] { if ($3 != "none") nobuild[$1 "\t" $2] = 1; next }
	{
		label = $1; status = $2
		split(label, p, ":")
		mod = p[1]; tgt = p[2]
		ex = tgt; sub(/_.*/, "", ex)
		if (ex !~ /^ex[0-9]+$/) ex = (tgt in whole) ? tgt : "-"
		layer = tgt; sub(/^ex[0-9]+_/, "", layer)

		# The function of a library a target belongs to (see the functions
		# of a library, above): the longest one whose exNN_<function>_ the name
		# starts with. The rest of the name is read as for any other target.
		unit = ex; fn = ""
		if (ex != "-")
			for (j = 1; j <= nfns[mod, ex]; j++) {
				f = fnof[mod, ex, j]
				pre = ex "_" f "_"
				if (length(f) > length(fn) && length(tgt) > length(pre) && \
				    substr(tgt, 1, length(pre)) == pre)
					fn = f
			}
		if (fn != "") {
			unit = ex " " fn
			layer = substr(tgt, length(ex) + length(fn) + 3)
		}
		rank = 0
		if (fn != "")
			for (j = 1; j <= nfns[mod, ex]; j++)
				if (fnof[mod, ex, j] == fn) rank = j

		# c_program cases and rush variants put a case name between the
		# exercise and the layer (ex00_blob_output, ex00_rush03_diff), so the
		# layer is the TAIL: the longest _SUFFIX_LAYER key the name ends
		# with, as the audit in c_levels() reads it. It is also the name a
		# red is filed under, so a red C 11 ex05 reads "exit x17" (the robust
		# exit twins of the Run contract, exNN_<case>_exit) rather than
		# seventeen one-off names. Only a red at basic is a KO: `output` there
		# is the work of the exercise, every other layer there is for the
		# student to fix first, and everything else -- above basic, or raised
		# above it by _RAISED -- is rigour. (No apostrophe in this program:
		# it sits between single quotes.) A test of the whole module
		# (deliverable_files) is its own "exercise", and its layer is the
		# tail of its whole name.
		rest = (tgt in whole) ? "_" tgt : substr(tgt, length(ex) + 1); best = ""
		if (fn != "") rest = "_" layer
		if (ex != "-")
			for (sf in slay)
				if (length(sf) > length(best) && length(sf) <= length(rest) && \
				    substr(rest, length(rest) - length(sf) + 1) == sf)
					best = sf
		if (best != "") {
			probe = substr(best, 2)
			# The level its tags carry: a raise, the contract lowering
			# its layer (memory_graded), or its name.
			low = (mod in graded) && slay[best] == glayer && sown[best] == "layer"
			lvl = (label in raised) ? raised[label] : (low ? 1 : slvl[best])
			kind = (lvl != 1) ? "rigour" : ((slay[best] == "output") ? "work" : "ko")
			# A target _RAISED lists is named as it is: its layer alone
			# read "c-11 ex04 -- output" under ALSO RED, "these produce
			# the right output", while the red one was ex04_reverse_output,
			# a reading of its own (V56). The tail after exNN_, whose own
			# row in docs/reference.md says why it sits where it does.
			if (label in raised) probe = substr(rest, 2)
		} else {
			kind = "rigour"; probe = layer
		}
		# A target that never got a test to run says nothing about the
		# layer it belongs to, only that the build under it failed; one that
		# ran out of time says nothing about its layer either.
		if (status == "build" || status == "standin") kind = "build"
		if (status == "timeout") kind = "slow"

		key = mod "\t" unit
		if (!(key in seen)) {
			seen[key] = 1; order[++nk] = key; kex[key] = mod "\t" ex
			krank[key] = rank
			if (!(kex[key] in xseen)) { xseen[kex[key]] = 1; nx++ }
			if (fn != "") nfn++
		}
		if (kind == "build" && !(key SUBSEP probe in bseen)) {
			bseen[key, probe] = 1
			bwhat[key] = bwhat[key] (bwhat[key] ? ", " : "") probe
		}
		if (kind == "ko" && !(key SUBSEP probe in kseen)) {
			kseen[key, probe] = 1
			kowhat[key] = kowhat[key] (kowhat[key] ? ", " : "") probe
		}
		if (kind == "rigour" && !(key SUBSEP probe in rseen)) {
			rseen[key, probe] = 1
			rigwhat[key] = rigwhat[key] (rigwhat[key] ? ", " : "") probe
		}
		if (kind == "slow") {
			if (!(key SUBSEP probe in sseen)) {
				sseen[key, probe] = 1
				slowwhat[key] = slowwhat[key] (slowwhat[key] ? ", " : "") probe
			}
			if (!(key in sfirst)) sfirst[key] = label
		}
		# The first label of each kind, for one function of a library: the
		# label --next names, since no prefix of target names tells a
		# function from a longer one it begins (ft_one, ft_one_more). And for
		# the library own tests (no function), whose exNN_ prefix every
		# function test begins with too: given no label, `42` showed the
		# first red of that prefix, a function test, under the library line.
		if (nfns[mod, ex] > 0 && !((key, kind) in pfirst)) pfirst[key, kind] = label
		if (kind == "work") {
			work[key] = 1
			if (!(key in wfirst)) wfirst[key] = label
			# Every work label of the library own tests, in order: each
			# reads a file of its own (lib_reads), and the report runs
			# each by its label, never the suite of the whole library.
			if (fn == "" && nfns[mod, ex] > 0)
				wall[key] = wall[key] (wall[key] ? " " : "") label
		}
		# And every rule label of theirs: FIX FIRST runs each by its label
		# too, since `:exNN` is the suite of the whole library.
		if (kind == "ko" && fn == "" && nfns[mod, ex] > 0)
			kall[key] = kall[key] (kall[key] ? " " : "") label
		if (fn == "" && nfns[mod, ex] > 0) klib[key] = 1
		if (!(key SUBSEP probe in lseen)) { lseen[key, probe] = 1; lorder[key] = lorder[key] " " probe }
		lcount[key, probe]++
		ntgt[key]++
		total++
	}
	END {
		# The functions of a library in the order of its contract, never of
		# their labels: the next function is the first one the contract lists
		# that is red, not ft_atoi for sorting first. Each exercise keeps its
		# place, and its own tests (no function) come before its functions.
		for (i = 1; i <= nk; i++) {
			grp = kex[order[i]]
			if (!(grp in gn)) gord[++ng] = grp
			gn[grp]++
			gk[grp, gn[grp]] = order[i]
		}
		nk = 0
		for (gi = 1; gi <= ng; gi++) {
			grp = gord[gi]
			for (i = 2; i <= gn[grp]; i++) {
				t = gk[grp, i]
				for (j = i - 1; j >= 1 && krank[gk[grp, j]] > krank[t]; j--) gk[grp, j + 1] = gk[grp, j]
				gk[grp, j + 1] = t
			}
			for (i = 1; i <= gn[grp]; i++) order[++nk] = gk[grp, i]
		}
		for (i = 1; i <= nk; i++) {
			k = order[i]
			kind = (kex[k] in nobuild) ? "build" \
			     : (kowhat[k] ? "ko" : (work[k] ? "work" \
			     : (slowwhat[k] ? "slow" : (rigwhat[k] ? "rigour" : "norun"))))
			what = (kind == "build" || kind == "norun") ? bwhat[k] \
			     : ((kind == "slow") ? slowwhat[k] \
			     : (kowhat[k] ? kowhat[k] : rigwhat[k]))
			# A dash, never empty: tab is IFS-whitespace, so `read` collapses
			# consecutive tabs and an empty column silently shifts every field
			# after it. Cost an hour once; costs one character to prevent.
			if (what == "") what = "-"
			# The layer multiset, compressed: five red output cases read as
			# "output x5", not as five lines. The count is what tells you
			# whether an exercise is one bad case or entirely unwritten.
			layers = ""
			m = split(lorder[k], ls, " ")
			for (j = 1; j <= m; j++) {
				if (ls[j] == "") continue
				c = lcount[k, ls[j]]
				layers = layers (layers ? " " : "") ls[j] (c > 1 ? " x" c : "")
			}
			first = (k in wfirst) ? wfirst[k] : "-"
			# What failed to build and what ran out of time, whatever the
			# kind: an exercise with a wrong output can have both as well.
			ftb = bwhat[k] ? bwhat[k] : "-"
			slow = slowwhat[k] ? slowwhat[k] : "-"
			sl = (k in sfirst) ? sfirst[k] : "-"
			pick = (kind == "ko" && ((k, "ko") in pfirst)) ? pfirst[k, "ko"] \
			     : ((kind == "rigour" && ((k, "rigour") in pfirst)) ? pfirst[k, "rigour"] : "-")
			# Whether the row is a library own tests (1) or not (0), and
			# their work labels, for pass 2 to judge one file at a time,
			# and their rule labels.
			printf "%s\t%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s\t%s\n", kind, k, what, ntgt[k], \
				first, layers, ftb, slow, sl, pick, (k in klib), ((k in wall) ? wall[k] : "-"), \
				((k in kall) ? kall[k] : "-")
		}
		# The exercises, and apart from them the functions of a library
		# (in the column a row keeps for what is red).
		printf "TOTAL\t%d\t%d\t%d\t0\t-\t-\t-\t-\t-\t-\t0\t-\t-\n", total, nx, nfn
	}' "$WORK.b" "$WORK.t" > "$WORK"

# Pass 2: nothing is called the student's fault until stub_check says the
# deliverable is written. A stub cannot have broken a rule -- c-08's header
# exercises fail `compile` while untouched, because a header that defines
# nothing cannot compile the subject's own main. Demote those to ordinary work.
#
# And nothing written is called unwritten: a red output over a file with a body
# is "wrong", which is a different sentence and a different next step. Where
# there is nothing to inspect (run from outside the workspace), both stay as
# the bucket put them.
#
# A library own tests (lib 1) are judged one file at a time, the file each
# work label reads (lib_read_written), the whole folder only for a label that
# names no one file: the row is wrong at its first label over a written file,
# which it then names, and otherwise work. Its reads column says what the
# report names: for work, "STATE|LABEL reads FILE, ..." (STATE stub, missing,
# empty, unknown, or mixed, when each item then says its own), or a dash when
# one of them names no file; for wrong, the file the named label reads. A
# rule red over a stub library, demoted to work, is run by its rule labels
# (the kall column). And a wrong row that is no library own tests says in
# its last column whether its first label's log holds the table mark (pass
# 0's $WORK.x): 1 when it does, 0 when it does not or no log was read.
: > "$WORK.2"
while IFS="$(printf '\t')" read -r kind mod ex what count first layers ftb slow sl pick lib wall kall; do
	reads="-"
	table="-"
	if [ "$kind" = "ko" ] && ! is_module_test "$ex"; then
		is_written "$mod" "$ex" 1 || kind="work"
	fi
	if [ "$kind" = "work" ] && [ "$lib" = 1 ]; then
		# A rule's red over a stub library, demoted above: its own labels.
		if [ "$wall" = "-" ] && [ "$kall" != "-" ]; then
			wall=$kall
			first=${kall%% *}
		fi
		_pw="" _pall=1 _prd="" _prda="" _pst=""
		for _pl in $wall; do
			[ "$_pl" = "-" ] && { _pall=0; continue; }
			lib_read_written "$mod" "$ex" "$_pl"
			case $? in
				0) _pw=$_pl; break ;;
				1) _ps=stub ;;
				3) _ps=missing ;;
				4) _ps=empty ;;
				5) _ps=unknown ;;
				*)
					_pall=0
					is_written "$mod" "$ex" 0 && { _pw=$_pl; break; }
					continue ;;
			esac
			case "$_pst" in
				"") _pst=$_ps ;;
				"$_ps") ;;
				*) _pst=mixed ;;
			esac
			case "$_ps" in
				stub) _pan=" (a stub)" ;;
				unknown) _pan="" ;;
				*) _pan=" ($_ps)" ;;
			esac
			_prd="$_prd${_prd:+, }${_pl##*:} reads $(lib_reads "$_pl" "$ex")"
			_prda="$_prda${_prda:+, }${_pl##*:} reads $(lib_reads "$_pl" "$ex")$_pan"
		done
		if [ -n "$_pw" ]; then
			kind="wrong"
			first=$_pw
			reads=$(lib_reads "$_pw" "$ex") || reads="-"
		elif [ "$_pall" = 1 ] && [ -n "$_prd" ]; then
			# Each item says its file's state only when they differ.
			[ "$_pst" = mixed ] && _prd=$_prda
			reads="$_pst|$_prd"
		fi
	elif [ "$kind" = "work" ]; then
		is_written "$mod" "$ex" 0 && kind="wrong"
	fi
	if [ "$kind" = "wrong" ] && [ "$lib" != 1 ]; then
		if awk -v l="$first" '$0 == l { f = 1 } END { exit !f }' "$WORK.x"; then table=1; else table=0; fi
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$mod" "$ex" "$what" \
		"$count" "$first" "$layers" "$ftb" "$slow" "$sl" "$pick" "$lib" "$wall" "$reads" "$kall" "$table" >> "$WORK.2"
done < "$WORK"
# Every exercise's verdict, settled, for --triage: the bucket, the module and
# the exercise of each line but the TOTAL. A function of a library is filed
# under its exercise, once per bucket.
if [ -n "$TRIAGE" ]; then
	awk -F'\t' -v OFS='\t' '$1 != "TOTAL" {
		e = $3; sub(/ .*$/, "", e)
		if (!(($1, $2, e) in seen)) { seen[$1, $2, e] = 1; print $1, $2, e }
	}' "$WORK.2" > "$TRIAGE"
fi

# Pass 3: render. What does not build, then one objective, then a module-sized
# picture of what is left -- and with --all, one line per exercise. Never one
# line per TARGET: at a hundred failures the log paths are noise, and "ex00
# output x5 build" says more in a line than six targets do in twelve.
awk -F'\t' -v mode="$MODE" -v broke="$BROKE" -v cmd="$CMD" -v nextf="$NEXT" '
	# A label as a person says it: "c-05", not "//c-piscine/c-piscine-c-05".
	# The course folder goes when the project name already says the course, and
	# the c-piscine- prefix goes because every Piscine module has it. Any other
	# label keeps its path, so //cursus/libft and //tools/tests stay readable.
	# (This used to be one sub() keyed on "//c-piscine-", which stopped matching
	# the day the modules moved under a course folder.)
	function shortname(l,   n, p) {
		sub(/^\/\//, "", l)
		n = split(l, p, "/")
		if (n > 1 && p[n] ~ /^c-piscine-/) l = p[n]
		sub(/^c-piscine-/, "", l)
		return l
	}
	# THE COMMAND THAT RUNS ONE EXERCISE AGAIN, or one target: the Bazel one, or
	# under --cmd 42 the 42 command for the same tests (42 test c-05 ex03).
	# A test of the whole module (deliverable_files) is not an exercise
	# word to 42, so it is named by its label, which 42 runs as it is.
	#
	# One function of a library ("ex00 ft_strlen") is run again by its own
	# suite, //<module>:<function>, which 42 takes as a word.
	function excmd(m, e,   f) {
		if (e ~ /^ex[0-9]+ /) {
			f = e; sub(/^[^ ]* /, "", f)
			return (cmd == "42") ? "42 test " shortname(m) " " f : "bazel test " m ":" f
		}
		if (cmd != "42") return "bazel test " m ":" e
		if (e ~ /^ex[0-9]+$/) return "42 test " shortname(m) " " e
		return "42 test " m ":" e
	}
	function labelcmd(l) {
		return (cmd == "42" ? "42 test " : "bazel test ") l
	}
	# A paragraph of the report, wrapped as its fixed lines are: six spaces
	# in, at most 68 characters of text a line.
	function para(s,   n, w, i, line) {
		n = split(s, w, " ")
		line = ""
		for (i = 1; i <= n; i++) {
			if (line != "" && length(line) + 1 + length(w[i]) > 68) {
				printf "      %s\n", line
				line = ""
			}
			line = (line == "") ? w[i] : line " " w[i]
		}
		if (line != "") printf "      %s\n", line
	}
	# Merge the layers in W into what failed to build of K, each once. The
	# prefix is its own statement: mawk creates ftbw[k] on the left of an
	# assignment before it reads the right, so "(k in ftbw)" there is always
	# true and every list began with ", ".
	function addftb(k, w,   n, a, i, p) {
		if (w == "-") return
		n = split(w, a, ", ")
		for (i = 1; i <= n; i++) {
			if ((k, a[i]) in ftbseen) continue
			ftbseen[k, a[i]] = 1
			p = ((k in ftbw) && ftbw[k] != "-" && ftbw[k] != "") ? ftbw[k] ", " : ""
			ftbw[k] = p a[i]
		}
	}
	function writenext(b, m, e, l) {
		if (nextf == "") return
		printf "%s\t%s\t%s\t%s\n", b, m, e, l > nextf
		close(nextf)
	}
	# THE EXERCISES OF A MODULE ROW, each one red, and a range only where every
	# exercise in it is: "ex00-ex04" read as five red exercises where ex00 did
	# not build, ex04 was red and ex01-ex03 were green (V56). addex M EX notes
	# one; exlist M writes them in order, "ex00, ex04" or "ex00-ex02, ex04".
	function addex(m, e,   v) {
		sub(/ .*$/, "", e)
		v = substr(e, 3) + 0
		if ((m, v) in exred) return
		exred[m, v] = 1
		exw[m, v] = length(e) - 2
		exn[m]++
		exv[m, exn[m]] = v
	}
	function exname(m, v,   w) {
		w = exw[m, v]
		return sprintf("ex%0" w "d", v)
	}
	function exlist(m,   n, i, j, t, a, out, lo) {
		n = exn[m]
		for (i = 1; i <= n; i++) a[i] = exv[m, i]
		for (i = 2; i <= n; i++) {
			t = a[i]
			for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]
			a[j + 1] = t
		}
		out = ""
		i = 1
		while (i <= n) {
			lo = i
			while (i < n && a[i + 1] == a[i] + 1) i++
			out = out (out == "" ? "" : ", ") exname(m, a[lo]) \
				(i > lo ? "-" exname(m, a[i]) : "")
			i++
		}
		if (out == "") out = "-"
		return out
	}
	FILENAME == ARGV[1] { meta[$1] = ($1 == "first") ? $2 : $2 + 0; next }
	# Two lists from one file: what a line ties to the student files (it does
	# not build), and what only a FAILED TO BUILD or unanalysed label names (it
	# did not run). Only the first is ever blamed on the student code.
	FILENAME == ARGV[2] {
		if ($3 == "none") { nnM[++nn] = $1; nnE[nn] = $2; next }
		nbM[++nb] = $1; nbE[nb] = $2; nbW[nb] = $3; nbL[nb] = $4
		nbmod[$1] = 1
		next
	}
	$1 == "TOTAL" { total = $2; nex = $3; nfn = $4 + 0; next }
	{
		mod[++r] = $2; ex[r] = $3
		cnt[r] = $5; lay[r] = $7
		if (!(mod[r] in mseen)) { mseen[mod[r]] = 1; morder[++nm] = mod[r] }
		mred[mod[r]] += $5
		mex[mod[r]]++
		mk[mod[r], $1] = 1
		# The exercises a module row names; a test of the whole module
		# (deliverable_files) has its own line and is not one.
		if ($3 ~ /^ex[0-9]+( |$)/) addex($2, $3)
		# What failed to build, by exercise: the build list names an
		# exercise, never one function of a library, so the rows of a
		# library are merged under it.
		x = $3; sub(/ .*$/, "", x)
		addftb($2 "\t" x, $8)
		# The width of the EVERY EXERCISE column of a module: its exercises and
		# the functions of a library ("ex00 ft_strlen"), never a test of the
		# whole module (deliverable_files), which overflows it as it always
		# has; and per module, so one beside a library prints as alone.
		if ($3 ~ /^ex[0-9]+( |$)/ && length($3) > exwidth[$2]) exwidth[$2] = length($3)
		if ($10 != "-")     { tM[++nt] = $2; tE[nt] = $3; tW[nt] = $9; tL[nt] = $10 }
		if ($1 == "ko")     { koM[++nko] = $2; koE[nko] = $3; koW[nko] = $4; koL[nko] = $11; koA[nko] = $15 }
		if ($1 == "work" || $1 == "wrong") {
			wM[++nw] = $2; wE[nw] = $3; wK[nw] = $1; wT[nw] = $6; wL[nw] = $7
			wLib[nw] = $12; wAll[nw] = $13; wRd[nw] = $14; wTab[nw] = $16
		}
		if ($1 == "rigour") { rM[++nr] = $2; rE[nr] = $3; rW[nr] = $4; rL[nr] = $11 }
	}
	END {
		if (broke && nb > 0)  writenext("build", nbM[1], nbE[1], "-")
		else if (nko)         writenext("ko", koM[1], koE[1], koL[1])
		else if (nw)          writenext(wK[1], wM[1], wE[1], wT[1])
		else if (nt)          writenext("slow", tM[1], tE[1], tL[1])
		else if (nr)          writenext("rigour", rM[1], rE[1], rL[1])
		if (broke) {
			# Whether Bazel counts an INCOMPLETE among "skipped" it does not
			# say, so the larger of the two counts, never their sum.
			never = meta["nostatus"] + meta["incomplete"]
			if (meta["skipped"] > never) never = meta["skipped"]
			# The headline says only what the log shows. DOES NOT BUILD needs a
			# line that ties an exercise to the student files; a build that
			# stopped with no such line -- a broken harness file, a download that
			# failed -- is said to have stopped, and so is a run that stopped for
			# another reason: Ctrl-C, or a failed test under --notest_keep_going
			# --nokeep_going.
			if (nb > 0)
				headline = (never > 0 || meta["notests"]) \
				     ? "THE BUILD STOPPED — part of this run never ran." \
				     : "SOMETHING DOES NOT BUILD."
			else if (meta["interrupted"])
				headline = "THE RUN WAS INTERRUPTED."
			else if (nn > 0)
				headline = "THE BUILD STOPPED — no line names a file of yours."
			else if (meta["notests"] && !meta["stopped"])
				headline = "NO TEST RAN — nothing you asked for is a test."
			else if (never > 0 || meta["notests"])
				headline = "THE RUN STOPPED — part of it never ran."
			else
				headline = "THE BUILD DID NOT COMPLETE."
			printf "\nfirst_red: %s\n", headline
			if (nb > 0) {
				printf "\n  DOES NOT BUILD — fix this first. Code that does not compile or link,\n"
				printf "  or a turn-in file that is missing, is graded 0, and nothing that\n"
				printf "  needs it can run until it builds.\n\n"
			} else if (nn > 0 && !meta["interrupted"]) {
				printf "\n  Bazel could not build part of this run, and no compiler or linker\n"
				printf "  line in the log names a file of yours: this is no verdict on your\n"
				printf "  code. Most often it is a download that failed, or a file of the\n"
				printf "  harness. "
				if (meta["first"] != "-")
					printf "The first error was:\n      %s\n", meta["first"]
				else
					printf "The log holds no error line to show.\n"
				printf "  Run it again: a download that failed often works the second time.\n"
				printf "  If the same error comes back, it is in the harness or the machine,\n"
				printf "  not in your files.\n\n"
			} else if (!meta["interrupted"] && meta["first"] != "-") {
				printf "\n  No line in this log names an exercise that does not build. The\n"
				printf "  first error was:\n      %s\n\n", meta["first"]
			} else
				printf "\n"
			for (i = 1; i <= nb; i++) {
				e = (nbE[i] == "-") ? "" : " " nbE[i]
				printf "      %s%s", nbM[i], e
				k = nbM[i] "\t" nbE[i]
				if ((k in ftbw) && ftbw[k] != "-") printf " — %s", ftbw[k]
				printf "\n"
				if (nbW[i] == "test")
					printf "      in the test program built against your files:\n"
				printf "      %s\n", nbL[i]
				if (nbE[i] != "-") printf "      %s\n", excmd(nbM[i], nbE[i])
				printf "\n"
			}
			# Named by a label and nothing else. Beside something that does not
			# build, that may be why; alone, it is no verdict on anything.
			if (nn > 0) {
				if (nb > 0) {
					printf "  DID NOT RUN — Bazel could not build these either, and no line in\n"
					printf "  the log names a file of theirs. What does not build above may be\n"
					printf "  why; if they are still here once it builds, the cause is in no\n"
					printf "  file of yours.\n\n"
				} else
					printf "  DID NOT RUN — Bazel could not build these:\n\n"
				for (i = 1; i <= nn; i++) {
					e = (nnE[i] == "-") ? "" : " " nnE[i]
					printf "      %s%s", nnM[i], e
					k = nnM[i] "\t" nnE[i]
					if ((k in ftbw) && ftbw[k] != "-") printf " — %s", ftbw[k]
					printf "\n"
				}
				printf "\n"
			}
			if (meta["notests"] && (nb > 0 || nn > 0 || meta["stopped"]))
				printf "  Bazel found no test it could run: the error stopped it first.\n"
			if (never > 0) {
				printf "  %d target(s) never ran or never finished (NO STATUS, INCOMPLETE,\n", never
				printf "  or \"skipped\" in Bazel'"'"'s count). That says nothing about them,\n"
				printf "  good or bad.\n"
			}
			if (meta["unanalysed"] > 0) {
				printf "  Bazel could not analyse %d target(s). Those are left out of its\n", meta["unanalysed"]
				printf "  summary altogether, and out of its \"Executed N out of M\" count:\n"
				printf "  missing from it, not green.\n"
			}
			if (meta["ftb"] > meta["listed_ftb"]) {
				printf "  Bazel counted %d target(s) that failed to build and listed %d.\n", \
					meta["ftb"], meta["listed_ftb"]
			}
			# Only the modules the red list reaches get a line below; one that
			# never got a target listed is added, so the table has no hole, and
			# the count above the table says so.
			for (i = 1; i <= nb + nn; i++) {
				xm = (i <= nb) ? nbM[i] : nnM[i - nb]
				if ((xm in mseen) || (xm in xadded)) continue
				xadded[xm] = 1; xorder[++nx] = xm
			}
			for (i = 1; i <= nx; i++) {
				if (xorder[i] in nbmod) nxb++
				else nxr++
			}
			if (r == 0) {
				if (nb > 0)
					printf "\n  Nothing else in this run can be read until it builds. Fix it, then\n  run again.\n\n"
				else if (nn > 0)
					printf "\n  Nothing else failed, and what could not be built says nothing\n  about your code, good or bad.\n\n"
				else if (meta["notests"] && !meta["stopped"] && cmd == "42")
					printf "  Name a project, an exercise or a layer instead, such as\n  42 test c-05 ex03.\n\n"
				else if (meta["notests"] && !meta["stopped"])
					printf "  Name a test, a suite such as :basic, or a pattern such as\n  //c-piscine/c-piscine-c-05/... instead.\n\n"
				else
					printf "\n  Nothing failed before it stopped, which says nothing about what\n  never ran. Run it again to the end.\n\n"
				exit 0
			}
		}

		printf "\nfirst_red: %d red target(s), %d exercise(s)", total, nex
		if (nfn) printf " (%d function(s) of a library)", nfn
		printf ", %d module(s)", nm
		if (nxb) printf ", and %d more that do not build", nxb
		if (nxr) printf ", and %d more that did not run", nxr
		printf ".\n"

		if (nko) {
			printf "\n  FIX FIRST — these are written, and they break a rule that scores zero\n"
			printf "  wherever the project is graded. A stub does not fail them.\n\n"
			for (i = 1; i <= nko; i++) {
				printf "      %s %s — %s\n", koM[i], koE[i], koW[i]
				# A library own rules (no function): each by its label,
				# since `:exNN` runs the suite of the whole library.
				if (koA[i] != "-") {
					n = split(koA[i], al, " ")
					for (j = 1; j <= n; j++)
						printf "      %s\n", (cmd == "42") ? labelcmd(al[j]) : "bazel test " al[j] " --test_output=errors"
					printf "\n"
				} else
					printf "      %s\n\n", excmd(koM[i], koE[i])
			}
		}

		if (nw) {
			unit = (wE[1] ~ / /) ? "FUNCTION" : "EXERCISE"
			printf "\n  YOUR NEXT %s\n\n", unit
			printf "      %s %s\n", wM[1], wE[1]
			# A library own tests (pass 2): each red one run by its label,
			# and worded after the file it reads, never as the whole
			# library unwritten, nor sent to a table its runner may not
			# print.
			if (wLib[1] == 1 && wK[1] == "work" && wAll[1] != "-") {
				n = split(wAll[1], al, " ")
				for (i = 1; i <= n; i++)
					printf "      %s\n", (cmd == "42") ? labelcmd(al[i]) : "bazel test " al[i] " --test_output=errors"
				printf "\n"
				s = (n > 1) ? "These are tests of the library as a whole, not of one of its functions, and " \
				            : "This is a test of the library as a whole, not of one of its functions, and "
				# wRd: "STATE|LABEL reads FILE, ..." (pass 2). A stub, a
				# file missing and an empty one are each not written, and
				# said as what they are; "mixed" leaves it to each item.
				if (wRd[1] != "-") {
					st = wRd[1]; sub(/\|.*$/, "", st)
					rd = wRd[1]; sub(/^[^|]*\|/, "", rd)
					if (st == "stub")         sv = "is still a stub"
					else if (st == "missing") sv = "is missing"
					else if (st == "empty")   sv = "is empty"
					else                      sv = ""
					if (sv != "")
						s = s ((n > 1) ? "the file each one reads " : "the file it reads ") sv ": "
					else if (st == "mixed")
						s = s "none of the files they read is written yet: "
					else
						s = s ((n > 1) ? "each one reads one file of it: " : "it reads one file of it: ")
					s = s rd ". " ((n > 1) ? "What must each of those files hold for its test to pass? The log of each test says what it found." \
					    : "What must that file hold for the test to pass? Its log says what it found.")
				} else
					s = s "every file of it is still a stub. " \
					    ((n > 1) ? "The log of each test says what it found." : "Its log says what it found.")
				para(s)
			} else if (wLib[1] == 1 && wK[1] == "wrong") {
				printf "      %s\n\n", (cmd == "42") ? labelcmd(wT[1]) : "bazel test " wT[1] " --test_output=errors"
				if (wRd[1] != "-")
					s = toupper(substr(wRd[1], 1, 1)) substr(wRd[1], 2) \
					    " is written, but the test that reads it disagrees. That log says why."
				else
					s = "Part of the library is written, but this test of it as a whole disagrees. That log says why."
				para(s)
			} else if (wK[1] == "work") {
				printf "      %s\n\n", excmd(wM[1], wE[1])
				printf "      Its output layer is red, which is what an unwritten %s looks\n", tolower(unit)
				printf "      like. Write it until that goes green, then run the module again.\n"
			} else if (cmd == "42") {
				# A table only where the log holds one (pass 2, from
				# the table mark): a Makefile build red, a crash under a
				# survive case or a byte-stream summary has none.
				printf "      %s\n\n", excmd(wM[1], wE[1])
				printf "      It is written, and it runs, but what it does is not what the test\n"
				if (wTab[1] == 0)
					printf "      expects (%s). Its log says why.\n", wL[1]
				else
					printf "      expects (%s). The table in its log names the case.\n", wL[1]
			} else {
				printf "      bazel test %s --test_output=errors\n\n", wT[1]
				printf "      It is written, and it runs, but what it does is not what the test\n"
				if (wTab[1] == 0)
					printf "      expects (%s). That log says why.\n", wL[1]
				else
					printf "      expects (%s). The table in that log names the case.\n", wL[1]
			}
		}

		# A test stopped by its timeout printed no verdict, so none is given
		# here: not a wrong output, not a broken rule. Measured: a loaded
		# machine timed out a style gate that passes alone.
		if (nt) {
			printf "\n\n  RAN OUT OF TIME — no verdict. A test that runs out of time is stopped\n"
			printf "  before it can finish: an endless loop, a very slow method, or a machine\n"
			printf "  too loaded to finish in time. Where its runner could, its log names the\n"
			printf "  case it was on. Run it alone; if it still runs out of time, it is the\n"
			printf "  code, not the machine.\n\n"
			for (i = 1; i <= nt; i++) {
				e = (tE[i] == "-") ? "" : " " tE[i]
				printf "      %s%s — %s\n", tM[i], e, tW[i]
				printf "      %s\n\n", labelcmd(tL[i])
			}
		}

		if (nr) {
			printf "\n\n  ALSO RED — these produce the right output; a rigour layer above what\n"
			printf "  the grader checks disagrees. Worth reading, not urgent.\n\n"
			for (i = 1; i <= nr; i++)
				printf "      %s %s — %s\n", rM[i], rE[i], rW[i]
		}

		# The scale, one line per module. This is the part that stops a wall of
		# red reading as hopeless: seven lines say what three hundred did.
		printf "\n\n  EVERYTHING STILL RED\n\n"
		# The module column is 22 wide, wider only for a longer name shown
		# (a project deep under its course, cursus/Milestone_0/Libft), so the
		# counts stay one column and every Piscine table prints as it did.
		mw = 22
		for (i = 1; i <= nm; i++) if (length(shortname(morder[i])) > mw) mw = length(shortname(morder[i]))
		for (i = 1; i <= nx; i++) if (length(shortname(xorder[i])) > mw) mw = length(shortname(xorder[i]))
		mfmt = "      %-" mw "s %5s  %-24s %s\n"
		printf mfmt, "MODULE", "RED", "STATE", "RED EXERCISES"
		for (i = 1; i <= nm; i++) {
			m = morder[i]
			span = exlist(m)
			if (((m, "build") in mk) || (m in nbmod)) state = "does not build"
			else if ((m, "ko") in mk)     state = "written; breaking a rule"
			else if ((m, "wrong") in mk)  state = ((m, "work") in mk) ? "partly written" : "written; wrong output"
			else if ((m, "work") in mk)   state = "not written yet"
			else if ((m, "slow") in mk)   state = "ran out of time"
			else if ((m, "rigour") in mk) state = "written; rigour only"
			else                          state = "did not run"
			short = shortname(m)
			printf mfmt, short, mred[m] + 0, state, span
		}
		# No red target, because none of them ran: "-", not a count of zero.
		for (i = 1; i <= nx; i++) {
			m = xorder[i]
			for (j = 1; j <= nb; j++)
				if (nbM[j] == m && nbE[j] ~ /^ex[0-9]+$/) addex(m, nbE[j])
			for (j = 1; j <= nn; j++)
				if (nnM[j] == m && nnE[j] ~ /^ex[0-9]+$/) addex(m, nnE[j])
			span = exlist(m)
			state = (m in nbmod) ? "does not build" : "did not run"
			printf mfmt, shortname(m), "-", state, span
		}

		if (mode == "all") {
			printf "\n\n  EVERY EXERCISE, one line each\n"
			lastm = ""
			for (i = 1; i <= r; i++) {
				if (mod[i] != lastm) {
					short = shortname(mod[i])
					printf "\n      %s\n", short
					lastm = mod[i]
				}
				w = (mod[i] in exwidth && exwidth[mod[i]] > 6) ? exwidth[mod[i]] : 6
				printf "        %-" w "s %2d  %s\n", ex[i], cnt[i], lay[i]
			}
		} else {
			printf "\n      Add --all for one line per exercise.\n"
		}
		printf "\n"
	}' "$WORK.m" "$WORK.b" "$WORK.2"

[ "$BROKE" -eq 0 ] || exit 1
exit 0
