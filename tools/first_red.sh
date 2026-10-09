#!/bin/sh
# first_red.sh — turn a wall of red into one next objective.
#
# Usage:
#   bazel test //c-piscine/c-piscine-c-05:basic 2>&1 | sh tools/first_red.sh   # what to do next
#   bazel test //... 2>&1 | sh tools/first_red.sh --all   # ... and everything (needs memory to spare)
#
#   --cmd 42      every command the report suggests is written as the `42`
#                 command that runs the same tests (tools/42.sh), not as Bazel's
#   --next FILE   also write the one thing the report names next, as a line
#                 "BUCKET<tab>MODULE<tab>EXERCISE<tab>LABEL" (a dash for a
#                 column it cannot fill; an empty file when nothing is next).
#                 BUCKET is build, ko, work, wrong, slow or rigour. `42` reads it
#                 to show that one test's log, in the report's own order.
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
# that breaks a rule that scores zero wherever the project is graded. Usually, not always — and the exception
# is why this script asks rather than assumes.
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
require awk dirname find mktemp mv rm sed sort tr

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
# that mentions `dir = None` is not the contract. //tools/tests:turnin_dirs
# holds this reading to the macros' own turnin_dir() for every exercise of
# every project (and macro_fixtures_test on the toy ones), and
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

MODE=summary
CMD=bazel
NEXT=""
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
		# The turn-in folder of one exercise, as the report reads it: for
		# the checks that hold this reading to the contract's.
		--turnin)
			[ $# -ge 3 ] || { echo "first_red.sh: --turnin MODDIR EX" >&2; exit 2; }
			turnin_of "$2" "$3"
			exit ;;
		*) echo "first_red.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
# Emptied first, so a report that names nothing next (nothing failed) leaves
# no stale line from an earlier run behind.
if [ -n "$NEXT" ]; then
	: > "$NEXT" || { echo "first_red.sh: cannot write $NEXT" >&2; exit 2; }
fi

# stub_check.sh is found NEXT TO THIS SCRIPT, not relative to the working
# directory. A runner that only works when you happen to be standing in the
# repo root is a runner that fails the first time it is called from anywhere
# else -- and this one is meant to be piped into from wherever you ran bazel.
STUB_CHECK="$(dirname "$0")/stub_check.sh"

# The build stand-in's mark, from the one file that defines it (see
# tools/standin.sh): a test whose log holds it ran a program that never built.
_sl="$(dirname "$0")/standin.sh"
[ -f "$_sl" ] || { echo "first_red.sh: $_sl is not beside it" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"

# GREEN ON A STUB: the layers a fresh stub passes, as _LAYER_LEVEL in
# tools/defs.bzl names them -- the same claim docs/reference.md makes.
# //tools:conventions fails if a name here stops being a layer.
STUB_GREEN='norm compile files forbidden prototype'

# WHICH LAYER A RED TARGET IS, AND AT WHICH LEVEL, read from the tables
# c_levels()' audit holds every test to (tools/defs.bzl, found beside this
# script): _SUFFIX_LAYER maps the end of a target's name to its layer and
# level, _LAYER_LEVEL gives a layer's own level, and _RAISED lists the targets
# raised above it. Only a red AT BASIC is a KO wherever the project is
# graded, so only one at basic is filed as the student's to fix first (a
# stub-green layer) or as the exercise's work (`output`); every other red is
# rigour. This used to walk a list of its own, which knew `output` and none of
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

WORK=$(mktemp) || exit 2
trap 'rm -f "$WORK" "$WORK.log" "$WORK.t" "$WORK.b" "$WORK.m" "$WORK.2" "$WORK.e" "$WORK.l"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# The tables, one entry per line as buildifier leaves them (the same reading
# //tools:conventions holds docs/reference.md's copies to):
#   S<TAB>suffix<TAB>layer<TAB>level     one per _SUFFIX_LAYER entry
#   R<TAB>//package:target<TAB>level     one per _RAISED entry
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
			printf "S\t%s\t%s\t%s\n", sfx[i], sly[i], (slv[i] == "None") ? lv[sly[i]] : slv[i]
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
#
# An exercise is found three ways: from a FAILED TO BUILD target, from a target
# Bazel could not analyse, and from a compiler or linker line. The last is the
# one a student can act on, so each exercise keeps the first line of the most
# useful kind the log holds for it: one naming a turn-in file (deliverable/...
# with a line number, or a turn-in file that is missing), then a linker line
# that names only an object file, then one in the test program built against
# the turn-in.
awk -F'\t' -v out="$WORK" -v mark="$STANDIN_MARK" -v nomark="$NOTURNIN_MARK" \
	-v broke="$STANDIN_BROKE" -v empty="$STANDIN_EMPTY" -v overmark="$OVERRUN_MARK" '
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
			if (index(l, mark)) got = 1
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
		if (index($0, mark)) { standin[tlabel] = 1; tmark[tlabel] = 1 }
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
			} else if (st == "run" && (t in standin)) {
				st = "standin"
				note(modlabel(t), exoftgt(t), (t in swhat) ? (swhat[t] == "headline" ? "standin" : swhat[t]) : "standin", \
					(t in sline) ? sline[t] : "your code did not build (" t ")")
			} else if (st == "run" && (t in overrun)) {
				st = "timeout"
			}
			print t "\t" st > (out ".t")
		}
		for (i = 1; i <= nb; i++)
			printf "%s\t%s\t%s\n", border[i], bwhat[border[i]], bline[border[i]] > (out ".b")
		printf "stopped\t%d\nnotests\t%d\nnostatus\t%d\nskipped\t%d\n", stopped, notests, nostatus, skipped > (out ".m")
		printf "incomplete\t%d\n", incomplete > (out ".m")
		printf "interrupted\t%d\n", interrupted > (out ".m")
		printf "ftb\t%d\nlisted_ftb\t%d\n", ftb, listed_ftb > (out ".m")
		printf "unanalysed\t%d\nfirst\t%s\n", nana, (first == "" ? "-" : first) > (out ".m")
	}' "$WORK.log"
: >> "$WORK.t"; : >> "$WORK.b"
sort -u "$WORK.t" -o "$WORK.t"

# Is this exercise written? stub_check.sh answers per file: 0 a stub, 1 holds a
# body, 2 not a kind it reads (numbers.dict, a stray a.out). What 2 counts as is
# the caller's: in the rule bucket a stray file is itself the rule broken, so it
# counts as written; beside a red output it says nothing about the code, so it
# does not. A shell exercise is its generator, never the deliverable/ that the
# generator writes.
is_written() {  # is_written MOD EX UNKNOWN_COUNTS(0|1)
	_m=$(printf '%s' "$1" | sed 's|^//||')
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
if [ -s "$WORK.e" ]; then
	awk -F'\t' -v OFS='\t' '
		FILENAME == ARGV[1] { st[$1 FS $2] = $3; next }
		$3 == "empty" { if (st[$1 FS $2] != "written") next; $3 = "standin" }
		{ print }' "$WORK.e" "$WORK.b" > "$WORK.2" && mv "$WORK.2" "$WORK.b"
	awk -F'\t' -v OFS='\t' '
		function key(l,   m, t) {
			m = l; sub(/:.*$/, "", m)
			t = l; sub(/^[^:]*:/, "", t); sub(/_.*$/, "", t)
			if (t !~ /^ex[0-9]+$/) t = "-"
			return m FS t
		}
		FILENAME == ARGV[1] { st[$1 FS $2] = $3; next }
		$2 == "empty" { $2 = (st[key($1)] == "written") ? "standin" : "run" }
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

# Pass 1: classify every failing target and aggregate per exercise. The build
# list comes first, so an exercise that does not build is filed as such
# whatever else about it is red: its output cannot be wrong if it never ran.
# One that only did not run is filed below every red that did run, because
# those are established and its missing targets are not.
awk -F'\t' -v stub_green="$STUB_GREEN" -v tables="$WORK.l" -v module_tests="$MODULE_TESTS" '
	BEGIN {
		n = split(stub_green, g, " ")
		for (i = 1; i <= n; i++) ko[g[i]] = 1
		while ((getline ln < tables) > 0) {
			split(ln, q, "\t")
			if (q[1] == "S") { slay[q[2]] = q[3]; slvl[q[2]] = q[4] + 0 }
			else if (q[1] == "R") raised[q[2]] = q[3] + 0
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

		# c_program cases and rush variants put a case name between the
		# exercise and the layer (ex00_blob_output, ex00_rush03_diff), so the
		# layer is the TAIL: the longest _SUFFIX_LAYER key the name ends
		# with, as the audit in c_levels() reads it. It is also the name a
		# red is filed under, so a red C 11 ex05 reads "exit x17" (the robust
		# exit twins of the Run contract, exNN_<case>_exit) rather than
		# seventeen one-off names. Only a red at basic is a KO: a stub-green
		# layer there is for the student to fix first, `output` there is the
		# work of the exercise, and everything else -- above basic, or raised
		# above it by _RAISED -- is rigour. (No apostrophe in this program:
		# it sits between single quotes.) A test of the whole module
		# (deliverable_files) is its own "exercise", and its layer is the
		# tail of its whole name.
		rest = (tgt in whole) ? "_" tgt : substr(tgt, length(ex) + 1); best = ""
		if (ex != "-")
			for (sf in slay)
				if (length(sf) > length(best) && length(sf) <= length(rest) && \
				    substr(rest, length(rest) - length(sf) + 1) == sf)
					best = sf
		if (best != "") {
			probe = substr(best, 2)
			lvl = (label in raised) ? raised[label] : slvl[best]
			kind = (lvl == 1 && (slay[best] in ko)) ? "ko" \
			     : ((lvl == 1 && slay[best] == "output") ? "work" : "rigour")
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

		key = mod "\t" ex
		if (!(key in seen)) { seen[key] = 1; order[++nk] = key }
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
		if (kind == "work") {
			work[key] = 1
			if (!(key in wfirst)) wfirst[key] = label
		}
		if (!(key SUBSEP probe in lseen)) { lseen[key, probe] = 1; lorder[key] = lorder[key] " " probe }
		lcount[key, probe]++
		ntgt[key]++
		total++
	}
	END {
		for (i = 1; i <= nk; i++) {
			k = order[i]
			kind = (k in nobuild) ? "build" \
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
			printf "%s\t%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\n", kind, k, what, ntgt[k], \
				first, layers, ftb, slow, sl
		}
		printf "TOTAL\t%d\t%d\t-\t0\t-\t-\t-\t-\t-\n", total, nk
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
: > "$WORK.2"
while IFS="$(printf '\t')" read -r kind mod ex what count first layers ftb slow sl; do
	if [ "$kind" = "ko" ] && ! is_module_test "$ex"; then
		is_written "$mod" "$ex" 1 || kind="work"
	fi
	if [ "$kind" = "work" ]; then
		is_written "$mod" "$ex" 0 && kind="wrong"
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$mod" "$ex" "$what" \
		"$count" "$first" "$layers" "$ftb" "$slow" "$sl" >> "$WORK.2"
done < "$WORK"

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
	function excmd(m, e) {
		if (cmd != "42") return "bazel test " m ":" e
		if (e ~ /^ex[0-9]+$/) return "42 test " shortname(m) " " e
		return "42 test " m ":" e
	}
	function labelcmd(l) {
		return (cmd == "42" ? "42 test " : "bazel test ") l
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
	$1 == "TOTAL" { total = $2; nex = $3; next }
	{
		kind[++r] = $1; mod[r] = $2; ex[r] = $3; what[r] = $4
		cnt[r] = $5; lay[r] = $7
		if (!(mod[r] in mseen)) { mseen[mod[r]] = 1; morder[++nm] = mod[r] }
		mred[mod[r]] += $5
		mex[mod[r]]++
		mk[mod[r], $1] = 1
		# The exercises a module row names; a test of the whole module
		# (deliverable_files) has its own line and is not one.
		if ($3 ~ /^ex[0-9]+$/) addex($2, $3)
		ftbw[$2 "\t" $3] = $8
		if ($10 != "-")     { tM[++nt] = $2; tE[nt] = $3; tW[nt] = $9; tL[nt] = $10 }
		if ($1 == "ko")     { koM[++nko] = $2; koE[nko] = $3; koW[nko] = $4 }
		if ($1 == "work" || $1 == "wrong") {
			wM[++nw] = $2; wE[nw] = $3; wK[nw] = $1; wT[nw] = $6; wL[nw] = $7
		}
		if ($1 == "rigour") { rM[++nr] = $2; rE[nr] = $3; rW[nr] = $4 }
	}
	END {
		if (broke && nb > 0)  writenext("build", nbM[1], nbE[1], "-")
		else if (nko)         writenext("ko", koM[1], koE[1], "-")
		else if (nw)          writenext(wK[1], wM[1], wE[1], wT[1])
		else if (nt)          writenext("slow", tM[1], tE[1], tL[1])
		else if (nr)          writenext("rigour", rM[1], rE[1], "-")
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

		printf "\nfirst_red: %d red target(s), %d exercise(s), %d module(s)", total, nex, nm
		if (nxb) printf ", and %d more that do not build", nxb
		if (nxr) printf ", and %d more that did not run", nxr
		printf ".\n"

		if (nko) {
			printf "\n  FIX FIRST — these are written, and they break a rule that scores zero\n"
			printf "  wherever the project is graded. A stub does not fail them.\n\n"
			for (i = 1; i <= nko; i++) {
				printf "      %s %s — %s\n", koM[i], koE[i], koW[i]
				printf "      %s\n\n", excmd(koM[i], koE[i])
			}
		}

		if (nw) {
			printf "\n  YOUR NEXT EXERCISE\n\n"
			printf "      %s %s\n", wM[1], wE[1]
			if (wK[1] == "work") {
				printf "      %s\n\n", excmd(wM[1], wE[1])
				printf "      Its output layer is red, which is what an unwritten exercise looks\n"
				printf "      like. Write it until that goes green, then run the module again.\n"
			} else if (cmd == "42") {
				printf "      %s\n\n", excmd(wM[1], wE[1])
				printf "      It is written, and it runs, but what it does is not what the test\n"
				printf "      expects (%s). The table in its log names the case.\n", wL[1]
			} else {
				printf "      bazel test %s --test_output=errors\n\n", wT[1]
				printf "      It is written, and it runs, but what it does is not what the test\n"
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
		printf "      %-22s %5s  %-24s %s\n", "MODULE", "RED", "STATE", "RED EXERCISES"
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
			printf "      %-22s %5d  %-24s %s\n", short, mred[m], state, span
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
			printf "      %-22s %5s  %-24s %s\n", shortname(m), "-", state, span
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
				printf "        %-6s %2d  %s\n", ex[i], cnt[i], lay[i]
			}
		} else {
			printf "\n      Add --all for one line per exercise.\n"
		}
		printf "\n"
	}' "$WORK.m" "$WORK.b" "$WORK.2"

[ "$BROKE" -eq 0 ] || exit 1
exit 0
