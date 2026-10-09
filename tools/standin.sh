# shellcheck shell=sh
# (sourced library, never executed, so it has no shebang -- this directive
#  tells shellcheck the dialect without implying the file is a program.)
#
# standin.sh -- the BUILD STAND-IN contract, written once for the writer and
# every reader.
#
# WHY A STAND-IN. Every program a layer runs is built from the student's files
# by tools/student_build.sh, inside a Bazel build action. A build action that
# fails is a BUILD error: its tests print FAILED TO BUILD with no log, and
# before --keep_going it ended the whole run. So the build never fails on the
# student's code. When the code does not compile or link, or there is nothing
# to build, it writes a STAND-IN in the program's place: a small /bin/sh script
# that prints why, on stderr, and exits STANDIN_STATUS. Its tests then fail one
# at a time, with the compiler's own words in their logs.
#
# THE CONTRACT, which is what this file is:
#
#   STANDIN_MARK    a fixed line. It is the stand-in's second line (a comment,
#                   so it can be found without running anything) and the first
#                   line it prints. tools/first_red.sh finds it in test logs and
#                   files the exercise under DOES NOT BUILD -- or, for an EMPTY
#                   stand-in over a stub, under what is not written yet.
#   STANDIN_STATUS  the stand-in's exit status. Reserved: no runner gives 86 a
#                   meaning of its own, and it is below 126, so a runner that
#                   does not know about stand-ins still reads it as a plain
#                   failure and never as a crash, a timeout or a missing binary.
#   STANDIN_BROKE   the headline of a stand-in for code that is THERE and does
#   STANDIN_EMPTY   not compile or link, and of one for a build that had
#                   NOTHING to compile: no .c file, no Makefile, a Makefile
#                   whose default goal compiles no source. The second is what
#                   an exercise nobody has started looks like -- the stub
#                   Makefile of BSQ or Rush 02 only echoes -- so it must never
#                   read as broken code. Each is the first line the stand-in
#                   prints after the mark, and the stand-in's third line says
#                   which (`# kind: broke|empty`, read by standin_kind).
#                   tools/first_red.sh files an EMPTY stand-in over a stub as
#                   "not written yet", and over written files as not building.
#
# A runner that runs a built program sources this file and calls standin_check
# on the program before it runs it. A program handed over only as a
# correctness gate (--gate-bin) is run by tools/diff_output.sh, which checks it
# there. //tools:conventions refuses a runner that takes --bin or --student-bin
# and does not call standin_check, and tools/defs.bzl refuses, while loading, a
# test that hands a student_binary to a runner not in its _STANDIN_RUNNERS.
#
# How a runner finds this file: beside itself when it is run by path (a hand
# run, the selftest), else in the test's runfiles, where tools/defs.bzl's
# _test() stages it for every test it emits (a hand-written sh_test lists
# //tools:standin.sh in its data; conventions checks that too):
#
#   for _sl in "$(dirname "$0")/standin.sh" \
#       "${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
#       [ -f "$_sl" ] && break
#   done
#   [ -f "$_sl" ] || { echo "<runner>: tools/standin.sh is not staged" >&2; exit 2; }
#   . "$_sl"

STANDIN_MARK='42-harness stand-in: no program was built from your code'

# Its sibling: the opening words of a test that had no files to check at all
# (tools/no_turnin.sh). Not a stand-in -- nothing was built or run -- but the
# same news for tools/first_red.sh: a file of the turn-in is missing.
# shellcheck disable=SC2034
NOTURNIN_MARK='NOT TURNED IN — '
# Read by the writer, tools/student_build.sh, which sources this file.
# shellcheck disable=SC2034
STANDIN_STATUS=86
# The two headlines (see the contract above). first_red.sh matches them as
# fixed strings, so the words are the contract: change them here only.
# shellcheck disable=SC2034
STANDIN_BROKE='YOUR CODE DID NOT BUILD — '
# shellcheck disable=SC2034
STANDIN_EMPTY='NOTHING TO BUILD YET — '

# What this file takes from PATH, probed here rather than in each caller's
# require list: //tools:conventions computes a runner's list from the runner's
# own text, and the failure being guarded is the silent one -- no grep reads as
# "not a stand-in", and the runner then grades a program that does not exist.
for _sl_t in grep head sed; do
	command -v "$_sl_t" > /dev/null 2>&1 && continue
	echo "standin.sh: required command '$_sl_t' is not on PATH" >&2
	exit 2
done

# standin_is BIN -- true when BIN is a stand-in. Read, never run: the mark sits
# in the first few hundred bytes of the script, and a real program's first
# bytes are an ELF header.
standin_is() {
	[ -f "$1" ] || return 1
	head -c 512 "$1" 2> /dev/null | grep -qF "$STANDIN_MARK"
}

# standin_kind BIN -- prints "empty" when BIN is a stand-in for a build that
# had nothing to compile, "broke" otherwise. Read from its third line, never
# run.
standin_kind() {
	if head -n 3 "$1" 2> /dev/null | grep -qx '# kind: empty'; then
		echo empty
	else
		echo broke
	fi
}

# standin_check RUNNER BIN MODE [WHAT]
#
# Returns when BIN is a real program. When it is a stand-in, this reports and
# EXITS the calling runner:
#
#   MODE fail   print the stand-in's own explanation -- the compiler's or the
#               linker's words, whole: they are bounded, and cutting them is
#               how an explanation loses the line that mattered -- and exit 1.
#               No exercise hints: none of them is about a build.
#   MODE skip   the runner's own contract says another layer tells this story
#               (asan_run.sh: the output layer). Say so in one line and exit 0.
#               NO_SKIP=1 turns it into MODE fail, like every other skip in
#               this repo.
#
# A runner with a correctness gate calls this AFTER the gate, in MODE fail: a
# gate that is red has already skipped the layer, and one that is green -- or
# forced open by NO_SKIP=1 -- leaves a stand-in nothing to be but a failure.
#
# WHAT names the program in the message, e.g. "ex03/ft_foo"; default "the
# program".
#
# The wording follows the kind: "your code did not build" is said of code that
# is there and does not compile or link, never of a build that had nothing to
# compile, which is what an exercise nobody has started looks like.
standin_check() {
	_sc_runner=$1
	_sc_bin=$2
	_sc_mode=$3
	_sc_what=${4:-the program}
	standin_is "$_sc_bin" || return 0
	_sc_kind=$(standin_kind "$_sc_bin")
	if [ "$_sc_mode" = skip ] && [ "${NO_SKIP:-0}" != 1 ]; then
		if [ "$_sc_kind" = empty ]; then
			echo "$_sc_runner: SKIP — $_sc_what was never built: there is nothing to build yet."
			echo "  The output layer of this exercise says what the build found."
		else
			echo "$_sc_runner: SKIP — $_sc_what was never built: your code did not build."
			echo "  The output layer of this exercise shows the compiler's words."
		fi
		echo "  (NO_SKIP=1 turns this skip red.)"
		exit 0
	fi
	if [ "$_sc_kind" = empty ]; then
		echo "$_sc_runner: FAIL — there was nothing to build, so there is no program"
		echo "  to run as $_sc_what. If this exercise is not written yet, that is"
		echo "  expected. What the build said:"
	else
		echo "$_sc_runner: FAIL — your code did not build: there was no program to run"
		echo "  as $_sc_what. What the build said:"
	fi
	echo ""
	# The stand-in prints on stderr, and exits STANDIN_STATUS by design.
	sh "$_sc_bin" < /dev/null 2>&1 | sed 's/^/  /'
	exit 1
}
