#!/bin/sh
# student_build.sh — build a program from a student's files, and never fail
# because of them.
#
# WHY THIS EXISTS.
# Every program a layer runs -- a test harness linked with the student's
# function, the student's own program, its ASan twin, a Makefile project -- is
# built from files the student is still writing. Built as an ordinary Bazel
# action (cc_binary), a syntax error, a warning under -Werror, a leftover main()
# or a missing file was a BUILD error: the targets that needed it printed
# FAILED TO BUILD with no log to read, and before --keep_going the first one
# ended the whole run with every other exercise NO STATUS. The design had
# assumed only stubs reach the build graph, and stubs compile.
#
# So the compile moved into this one action, which ALWAYS produces its output.
# When the student's code builds, the output is the program. When it does not
# -- it does not compile, it does not link, the Makefile names nothing, there is
# no source at all -- the output is a STAND-IN (see tools/standin.sh): a /bin/sh
# script that prints what the build said and exits STANDIN_STATUS. Every test
# that runs it then fails on its own, with the compiler's words in its log, and
# nothing else in the module changes.
#
# Exit 2 is kept for what is not the student's, and it fails the build action,
# loudly, because a stand-in there would blame the student for the machine --
# and a build action that exits 0 is CACHED, so that stand-in would go on being
# served until something else changed. Five kinds:
#
#   * the harness cannot run the build at all: no compiler, a flag this script
#     does not know, an archiver that fails;
#   * a compiler, linker or make that was KILLED or CRASHED rather than
#     answering: an exit status of 126 or more, or the banner a compiler
#     driver prints, as a line of its own, when the tool under it died (an
#     OOM kill on a loaded machine, a compiler bug). Nothing about the
#     student's code is known then;
#   * a file of the HARNESS that does not compile and reads nothing of the
#     student's: no header of theirs, no file of theirs, reached that compile
#     (asked of the preprocessor, -E -H), so the student cannot have caused it.
#     A harness file that includes a turn-in header stays a stand-in: what
#     that header holds (a structure written otherwise, a name it lacks or
#     defines twice) can break the harness first. A harness declares the
#     functions it calls itself (//tools:conventions), so a header holding
#     what its subject asks, a structure alone, breaks nothing there;
#   * a Makefile this runner cannot plan a part from by the rule that builds
#     it (--make-goal): one whose database strays from the shape make prints
#     one in, or that leaves make's database in a file of the tree each time
#     make reads it, or whose rule the dry run that plans the build reads as
#     another, or not at all, or cannot be read as it reads it. A stand-in
#     there would say the Makefile has no such rule, or be built by a rule
#     make has built in, and neither is what the student wrote;
#   * a make that did not finish within MAKE_TMO seconds, and was not seen
#     running make inside itself without end (BOUNDED MAKES, below): a load
#     on the machine slows a dry run as surely as a $(shell sleep) does.
#
# STUDENT_BUILD_STRICT=1 is the maintainer's switch, and exit 1 is its only
# user. EVERY file of the harness's own (a --harness source under tests/) that
# does not compile is then a BUILD failure, the ones that include a turn-in
# header too: `bazel build //... --action_env=STUDENT_BUILD_STRICT=1` on a tree
# whose exercises compile -- the stubs, or answers -- is the check that every
# test program still builds (every template publish runs it, on the stubs).
# Without it, a harness file that includes a turn-in header and does not
# compile is a stand-in like any other, and on a level no sweep reaches it
# would go unseen (docs/testing.md, "A test that never compiled is not a test
# that passed"). A student's own file that does not compile is a stand-in in
# both modes.
#
# HOW IT COMPILES. The caller hands over the toolchain's own command lines --
# tools/student_build.bzl reads them from the C++ toolchain Bazel resolved, so
# the flags, the pinned clang, the pinned linker and --config=gcc are exactly
# what a cc_binary got. Each is a template: @SRC@ and @OBJ@ in the compile line,
# @OUT@ and @OBJS@ in the link line, @LIB@ in the archive line.
#
#   --src F      a source of the student's (or one the grader supplies). By
#                default these go into an ARCHIVE linked after the harness, as a
#                cc_library did: the linker pulls a file in only when something
#                calls into it, so a main() left inside the function's own file
#                is a duplicate, as the grader finds it. A stray main.c beside
#                it never gets here: the macros hand over only the files the
#                subject contract names or allows (tools/defs_contract.bzl,
#                _turnin_files), and the files layer reports the rest.
#   --harness F  a source of the test's own (its main()): always linked.
#   --no-archive link the --src files directly, as a program exercise's are.
#   --makefile M ask `make -Bn` in M's directory which .c files the default goal
#                compiles, and which -I directories it passes, and build those
#                (see "THE MAKEFILE MODE").
#   --includes-out F  with --makefile: also write those -I directories to F,
#                one per line, for the layers that compile the same files
#                outside this action (tools/compile_check.sh --inc-file).
#   --sources-out F  with --makefile: also write the .c files the recipes
#                compile to F, one per line, as paths from the Makefile's
#                directory -- for the files layer, which reports a source the
#                Makefile never builds (tools/files_test.sh --built). Its one
#                line is "unknown" when there is no Makefile or make could not
#                plan the build; it is empty when the recipes compile nothing.
#   --fallback-src F  with --makefile, repeatable: build these instead while
#                there is no Makefile, or while its recipes compile nothing
#                (a stub's only echo) -- see "UNTIL THE MAKEFILE IS WRITTEN".
#   --make-goal G  with --makefile: the program is what `make G` builds, not
#                what a bare `make` builds -- one part of a project whose
#                subject builds that part by a rule of its own -- see "A PART
#                BUILT BY A RULE OF ITS OWN".
#   --kind K     in a contract of units, what the program is built for, for
#                the stand-in's words (tools/standin.sh's standin_noun);
#                without it, "exercise".
#
# Usage:
#   student_build.sh --out PATH [--label TEXT] [--dir DIR]
#                    --cc CC [--cflag F]... [--ld LD] [--lflag F]...
#                    [--ar AR] [--arflag F]... [--copt F]...
#                    [--src F]... [--harness F]... [--no-archive]
#                    [--makefile M] [--make MAKE] [--includes-out F]
#                    [--sources-out F] [--fallback-src F]... [--make-goal G]
#                    [--kind exercise|library|function|project|part]
#
# With no --cflag the compile line is "-c @SRC@ -o @OBJ@" plus any --copt; with
# no --lflag the link line is "-o @OUT@ @OBJS@"; with no --arflag the archive
# line is "rcs @LIB@". That is the form a hand run and the selftest use; Bazel
# always passes the toolchain's own lines.
#
# UNTIL THE MAKEFILE IS WRITTEN (--fallback-src). C 10, C 11 ex05 and Piscine
# Reloaded ex27 turn in "Makefile, and files needed for your program" too, and
# their program is what the Makefile builds: with its sources, and its -I, so
# a turn-in that keeps its header in includes/ and says `-I includes` builds
# as make builds it (it was compiled from every .c of the folder with no -I,
# so it did not build at all). But the program there is most of the exercise
# and the Makefile a line of it, and a student writes and tests the program
# first: a stub Makefile turning every output test into "the Makefile
# compiles no .c files" would hide the program's own results until then. So
# where the caller gives fallback sources, a missing Makefile or one whose
# recipes compile nothing builds those, as the folder's program -- and the
# moment the Makefile names a source, it alone decides. A Makefile make cannot
# plan, or one naming a file that is not there, is still a stand-in: that is
# a Makefile written and broken, not one not written yet. --sources-out and
# --includes-out keep saying what the Makefile itself compiles (nothing), and
# whether it works is make_test.sh's question all along.
#
# THE MAKEFILE MODE. For the modules whose subject mandates a Makefile and then
# says only "and all the necessary files", nobody but the team knows what the
# program is made of. A glob of the directory sweeps in a second front end or a
# kept experiment; a list in the BUILD file goes stale the first time the team
# renames anything. So ASK MAKE: `make -Bn` prints the recipes the default goal
# would run without running them (-B so a stale .o copied in cannot make it
# print nothing), and every .c in them is a file the program is built from.
# Only the SOURCE LIST and the -I DIRECTORIES come from the Makefile -- the
# second so a turn-in that keeps its headers in includes/ builds as make
# builds it; the other flags stay ours, so a Makefile that forgets -Werror
# cannot soften the layers, and the program can still be built under ASan. A
# source the recipes name that is not in the turn-in is a stand-in that says
# which, since make itself would stop there. Each path is read from the
# directory its recipe runs in, a sub-make's (`$(MAKE) -C libft`) included:
# make is asked to print every directory it enters. Whether the Makefile
# ITSELF works is make_test.sh's question, asked separately. rules_foreign_cc's
# make() would run the build the Makefile describes, flags and all -- the half
# deliberately not wanted here.
#
# A PART BUILT BY A RULE OF ITS OWN (--make-goal G). Where a subject is in
# parts and builds one of them with a rule it names ("make bonus"), that part's
# program is what `make -Bn G` plans, and nothing else. Whether the Makefile
# HAS a rule G is asked first, of make's own list of the rules it read --
# `make -pnq`, its database, with the built-in rules and variables `make G`
# reads -- and never of what `make G` says or builds: a file or a folder named
# G makes it answer "Nothing to be done", and a G.c makes a built-in rule
# compile it, so a Makefile with no rule G would have stood for one. A rule G
# that is not there, or one named (in .PHONY, say) with no prerequisite and no
# recipe, is a stand-in saying so, of the EMPTY kind, as an unwritten part is:
# never a program built from the folder's sources instead (--fallback-src is
# refused with it), and never a planning error that names nothing. A rule G
# that the planning's dry run reads as another, or not at all, stops the build,
# which says why: a Makefile that tests MAKEFLAGS can read so. A Makefile make
# cannot read at all is left to the planning below, which shows make's own
# words.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "student_build.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat chmod cmp cp dirname find grep mkdir mktemp rm sed sleep timeout tr

# The contract this writes, shared with every runner that reads it.
_sl="$(dirname "$0")/standin.sh"
[ -f "$_sl" ] || { echo "student_build.sh: $_sl is not staged beside it" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
# The readers of make's database (Makefile mode), shared with make_test.sh.
MAKE_DB="$(CDPATH='' cd "$(dirname "$0")" && pwd)/make_db.awk"
[ -f "$MAKE_DB" ] || { echo "student_build.sh: $MAKE_DB is not staged beside it" >&2; exit 2; }

OUT=""
RL_UNIT_KIND=""
KIND_GIVEN=0
LABEL=""
MAKE_NOTE=""
DIR=""
CC=""
LD=""
AR=""
MAKEFILE=""
MAKE_BIN="make"
MAKE_GOAL=""
GOAL_GIVEN=0
INCLUDES_OUT=""
SOURCES_OUT=""
ARCHIVE=1
# Each list is newline-separated, so a flag holding a space survives (the
# toolchain passes -D__DATE__="redacted"). No --src or flag here holds a newline.
NL='
'
CFLAGS=""
LFLAGS=""
ARFLAGS=""
COPTS=""
SRCS=""
HARNESS=""
FALLBACK=""

need() { [ "$2" -ge 2 ] || { echo "student_build.sh: $1 needs a value" >&2; exit 2; }; }
add() { if [ -z "$1" ]; then printf '%s' "$2"; else printf '%s\n%s' "$1" "$2"; fi; }

while [ $# -gt 0 ]; do
	case "$1" in
		--out) need "$1" "$#"; OUT="$2"; shift 2 ;;
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--kind) need "$1" "$#"; RL_UNIT_KIND="$2"; KIND_GIVEN=1; shift 2 ;;
		--dir) need "$1" "$#"; DIR="$2"; shift 2 ;;
		--cc) need "$1" "$#"; CC="$2"; shift 2 ;;
		--ld) need "$1" "$#"; LD="$2"; shift 2 ;;
		--ar) need "$1" "$#"; AR="$2"; shift 2 ;;
		--cflag) need "$1" "$#"; CFLAGS=$(add "$CFLAGS" "$2"); shift 2 ;;
		--lflag) need "$1" "$#"; LFLAGS=$(add "$LFLAGS" "$2"); shift 2 ;;
		--arflag) need "$1" "$#"; ARFLAGS=$(add "$ARFLAGS" "$2"); shift 2 ;;
		--copt) need "$1" "$#"; COPTS=$(add "$COPTS" "$2"); shift 2 ;;
		--src) need "$1" "$#"; SRCS=$(add "$SRCS" "$2"); shift 2 ;;
		--harness) need "$1" "$#"; HARNESS=$(add "$HARNESS" "$2"); shift 2 ;;
		--no-archive) ARCHIVE=0; shift ;;
		--makefile) need "$1" "$#"; MAKEFILE="$2"; shift 2 ;;
		--make) need "$1" "$#"; MAKE_BIN="$2"; shift 2 ;;
		--includes-out) need "$1" "$#"; INCLUDES_OUT="$2"; shift 2 ;;
		--sources-out) need "$1" "$#"; SOURCES_OUT="$2"; shift 2 ;;
		--fallback-src) need "$1" "$#"; FALLBACK=$(add "$FALLBACK" "$2"); shift 2 ;;
		--make-goal) need "$1" "$#"; MAKE_GOAL="$2"; GOAL_GIVEN=1; shift 2 ;;
		*) echo "student_build.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$OUT" ] || { echo "student_build.sh: --out is required" >&2; exit 2; }
[ -n "$CC" ] || { echo "student_build.sh: --cc is required" >&2; exit 2; }
[ -n "$LD" ] || LD="$CC"
[ -n "$AR" ] || AR="ar"
[ -n "$LABEL" ] || LABEL="$OUT"
# A --kind given names a kind: an empty one is refused like any other word.
if [ "$KIND_GIVEN" = 1 ]; then
	case "$RL_UNIT_KIND" in
		exercise | library | function | project | part) ;;
		*) echo "student_build.sh: --kind is exercise, library, function, project or part, not '$RL_UNIT_KIND'" >&2; exit 2 ;;
	esac
fi
if [ -n "$MAKEFILE" ] && [ -n "$SRCS" ]; then
	echo "student_build.sh: --makefile and --src are exclusive: the Makefile decides" >&2
	exit 2
fi
if [ -n "$FALLBACK" ] && [ -z "$MAKEFILE" ]; then
	echo "student_build.sh: --fallback-src is what a Makefile not written yet stands for, and there is no --makefile" >&2
	exit 2
fi
if [ "$GOAL_GIVEN" = 1 ]; then
	case "$MAKE_GOAL" in
		"" | [-.]* | *[!A-Za-z0-9_.-]*)
			echo "student_build.sh: --make-goal takes a Makefile rule's name (letters, digits, _ . and -, not - or . first), not '$MAKE_GOAL'" >&2
			exit 2 ;;
	esac
	[ -n "$MAKEFILE" ] || {
		echo "student_build.sh: --make-goal names a rule of the Makefile, and there is no --makefile" >&2
		exit 2
	}
	[ -z "$FALLBACK" ] || {
		echo "student_build.sh: --make-goal and --fallback-src are exclusive: a part built by a rule of its own is judged by that rule alone, never by the folder's sources while the rule is not written" >&2
		exit 2
	}
fi
# How the messages below name the planning: a bare `make -Bn`, or the part's.
MK_ASK="make -Bn${MAKE_GOAL:+ $MAKE_GOAL}"
# ...and what it plans: the default goal, or the part's rule.
MK_WHAT="the default goal"
[ -z "$MAKE_GOAL" ] || MK_WHAT="the $MAKE_GOAL rule"
# Written empty first, so it exists whichever way this ends -- a stand-in
# for a missing Makefile included: a declared output the action does not
# write fails the build, which is the one thing this script never does.
if [ -n "$INCLUDES_OUT" ]; then
	[ -n "$MAKEFILE" ] || {
		echo "student_build.sh: --includes-out is the Makefile's -I list, and there is no --makefile" >&2
		exit 2
	}
	: > "$INCLUDES_OUT" || { echo "student_build.sh: cannot write '$INCLUDES_OUT'" >&2; exit 2; }
fi
# The same for the .c list, which reads "unknown" until make has said what it
# compiles: a stand-in written before that (no Makefile, a make that could not
# plan) leaves it so.
if [ -n "$SOURCES_OUT" ]; then
	[ -n "$MAKEFILE" ] || {
		echo "student_build.sh: --sources-out is the Makefile's .c list, and there is no --makefile" >&2
		exit 2
	}
	echo unknown > "$SOURCES_OUT" || { echo "student_build.sh: cannot write '$SOURCES_OUT'" >&2; exit 2; }
fi

# The compiler, the linker and make are found as given, from THIS directory: a
# toolchain path is relative to the exec root (tools/cc_toolchain/clang.sh), and
# the pinned wrappers find their fetched tool relative to it. Nothing here ever
# changes directory, except `make -Bn` in a subshell.
for _tool in "$CC" "$LD"; do
	command -v "$_tool" > /dev/null 2>&1 || {
		echo "student_build.sh: compiler '$_tool' not found" >&2
		exit 2
	}
done
if [ "$ARCHIVE" = 1 ] && [ -n "$SRCS$MAKEFILE" ] && [ -n "$HARNESS" ]; then
	command -v "$AR" > /dev/null 2>&1 || {
		echo "student_build.sh: archiver '$AR' not found" >&2
		exit 2
	}
fi

[ -n "$CFLAGS" ] || CFLAGS=$(printf -- '-c\n@SRC@\n-o\n@OBJ@')
[ -z "$COPTS" ] || CFLAGS=$(add "$CFLAGS" "$COPTS")
[ -n "$LFLAGS" ] || LFLAGS=$(printf -- '-o\n@OUT@\n@OBJS@')
[ -n "$ARFLAGS" ] || ARFLAGS=$(printf -- 'rcs\n@LIB@')

WORK=$(mktemp -d) || { echo "student_build.sh: mktemp failed" >&2; exit 2; }
# bmake_stop: end the make bmake runs, and the subshell that runs bmake
# (BOUNDED MAKES). timeout puts make in a process group of its own, which
# no signal to this script or to its group reaches, so each way out of the
# script ends them first; timeout hands the TERM on to its whole group.
BMAKE_SUB=
bmake_stop() {
	[ -z "$BMAKE_SUB" ] || kill "$BMAKE_SUB" 2> /dev/null
	[ ! -s "$WORK/bmake.pid" ] || kill "$(cat "$WORK/bmake.pid")" 2> /dev/null
	return 0
}
trap 'bmake_stop; rm -rf "$WORK"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP

# ------------------------------------------------------------- the lists
# Every list here is one entry per line, and is only ever walked one line at a
# time, never split on blanks: a file name holds a space as easily as a letter
# ("ft_putchar copy.c" is what a Mac names a duplicate), and a loop over an
# unquoted $SRCS turned that file into two files that do not exist, blaming
# the student's correct code for them. tools/defs.bzl drops such names before
# they reach a build (its _safe()), and this is the second line of that
# defence, for a hand run and for the Makefile mode.
#
#   each LIST FUNCTION -- calls FUNCTION once per non-empty line of LIST, in
#   this shell (never a subshell: the callers collect into globals).
#
#   Not re-entrant (its two variables are globals): a FUNCTION that walks a
#   list of its own does so with its own loop. The FUNCTION's stdin is
#   /dev/null, never the rest of the list.
each() {
	_each_f=$2
	while IFS= read -r _each_l; do
		[ -n "$_each_l" ] || continue
		"$_each_f" "$_each_l" < /dev/null
	done <<-EACH_EOF
	$1
	EACH_EOF
}
# The lines of LIST, each indented, for a message.
indent() { printf '%s\n' "$1" | sed -e '/^$/d' -e 's/^/    /'; }

# ------------------------------------------------------------- the stand-in
# Written, and the script exits 0: the build action succeeded, and what it
# produced is a program that explains itself. The message goes in verbatim --
# colour codes stripped (the toolchain passes -fcolor-diagnostics, which is for
# a terminal, not a log), scratch paths turned back into the files they stand
# for.
#
# Two kinds (tools/standin.sh): BROKE when there was code and it did not
# compile or link, EMPTY when there was nothing to compile -- no .c file, a
# Makefile that compiles none, no Makefile. The second is exactly what an
# exercise nobody has started looks like (a stub Makefile compiles nothing),
# so it must never read as "your code is broken": tools/first_red.sh and
# standin_check word the two differently.
standin() {  # standin broke|empty HEADLINE <<message
	case "$1" in
		broke) _sh=$STANDIN_BROKE ;;
		empty) _sh=$STANDIN_EMPTY ;;
		*) echo "student_build.sh: standin: unknown kind '$1'" >&2; exit 2 ;;
	esac
	{
		echo "#!/bin/sh"
		echo "# $STANDIN_MARK"
		echo "# kind: $1"
		echo "# Written by tools/student_build.sh in place of $LABEL."
		echo "cat >&2 <<'STUDENT_BUILD_EOF_42'"
		echo "$STANDIN_MARK"
		echo "$_sh$2"
		echo "  ($LABEL)"
		echo ""
		tidy
		echo "STUDENT_BUILD_EOF_42"
		echo "exit $STANDIN_STATUS"
	} > "$OUT" || { echo "student_build.sh: cannot write '$OUT'" >&2; exit 2; }
	chmod +x "$OUT"
	exit 0
}
ESC=$(printf '\033')
CR=$(printf '\r')
# sedre PATH: PATH escaped for a sed pattern, where . * [ ] ^ $ \ and the
# delimiter # mean something. The scratch path is one in tidy: a # or a . in
# TMPDIR made it another pattern, or no command at all (F0497).
sedre() { printf '%s' "$1" | sed 's/[][#.*^$\\]/\\&/g'; }
tidy() {
	_tw=$(sedre "$WORK")
	sed -e "s/${ESC}\[[0-9;]*[A-Za-z]//g" -e "s/${CR}\$//" \
		-e "s#$_tw/o/##g" -e "s#$_tw/##g" \
		-e 's#[^ ]*/x86_64-linux-gnu-ld\.gold:#ld:#g' \
		-e 's#[^ ]*/x86_64-linux-gnu-ld\.bfd:#ld:#g' \
		-e 's#[^ ]*/x86_64-linux-gnu-ld:#ld:#g' \
		-e 's/^STUDENT_BUILD_EOF_42$/(end)/'
}

# ------------------------------------------------------- a tool that died
# A compiler, linker or make that was KILLED or CRASHED said nothing about the
# student's code, so it gets no stand-in: a stand-in is written by an action
# that exits 0, Bazel caches it, and correct code would go on being reported as
# "your code did not build" until some input changed. Exit 2 fails the action
# instead, and a failed action is run again on the next build.
#
# Two signs. An exit status of 126 or more: the shell's "could not execute"
# (126, 127) and "killed by signal N" (128+N) -- the OOM killer on a loaded
# machine is a 137. And the banner a driver prints when the tool UNDER it
# died, since the driver itself then exits 1 like any compile error.
#
# A banner counts only as a LINE THE DRIVER PRINTED: at the start of a line,
# in the form the driver prints it (CRASH_BANNER), and never in text of the
# student's that a diagnostic carries. Two ways that text gets there:
#
#   a quoted line  a compiler quotes the source line it complains about --
#                  clang-12 as it is, from column 0 -- so a broken line holding
#                  "internal compiler error" in a string was read as a crash
#                  when any substring counted, and exit 2 left the target
#                  FAILED TO BUILD with no log, the very class this script
#                  removes. A quoted line is always followed by the caret line
#                  pointing into it, which is how unquoted() drops it first.
#   a message      `#error unable to execute command: x` or a failed
#                  _Static_assert makes the compiler print the student's words
#                  AS its message: "t.c:1:2: error: unable to execute command:
#                  x", a line no caret follows. A driver's banner starts with
#                  the DRIVER's name ("clang-12: error: ...", "gcc: fatal
#                  error: ..."), a diagnostic with a place in a file
#                  ("t.c:1:2: error: ..."); a program's name holds no colon, so
#                  the driver banners take a first word without one. gcc's
#                  internal compiler error is the exception: it carries the
#                  place, and its own kind of diagnostic ("t.c:3:1: internal
#                  compiler error: "), which no message of the student's can
#                  forge -- theirs is always "error: " or "warning: " first.
#
# A tool that crashed never exits 0, so a success is never searched. make -Bn
# is judged by its status alone (status-only): what it prints is the
# student's recipes, which may say anything.
CRASH_BANNER='^[^ :]+: (fatal )?error: (.* )?(command failed due to signal|terminated with signal)'
CRASH_BANNER="$CRASH_BANNER"'|^[^ :]+: (fatal )?error: (unable to execute command|Killed signal terminated program|cannot execute )'
CRASH_BANNER="$CRASH_BANNER"'|^[^ ]+: internal compiler error: |^PLEASE submit a bug report'
unquoted() {
	tidy | awk '
		NR > 1 && $0 !~ /^[ \t~^]*\^[ \t~^]*$/ { print prev }
		{ prev = $0 }
		END { if (NR > 0) print prev }'
}
died() {  # died STATUS OUTPUT WHAT [status-only]
	_why=""
	# Which of the two a status of 126 or more was is not read from it: 128+N
	# is also a status a program can return (tools/exit_status says why), and
	# either way the tool said nothing about the code. The status is shown as
	# it was.
	# conventions: not-a-program-status -- the toolchain's own status, in a build action (no tools/exit_status there): 126 or more is "did not answer", and no signal is named
	if [ "$1" -ge 126 ]; then
		_why="it exited $1: it could not be run, or was stopped"
	elif [ "$1" -ne 0 ] && [ "${4:-}" != status-only ] &&
		printf '%s\n' "$2" | unquoted | grep -Eq -- "$CRASH_BANNER"; then
		_why="it crashed"
	fi
	[ -n "$_why" ] || return 0
	echo "student_build.sh: $3 did not answer -- $_why ($LABEL)." >&2
	echo "  A tool that is killed or crashes says nothing about the code it was" >&2
	echo "  given, so this is a failed build, not a stand-in: run it again. If it" >&2
	echo "  fails the same way every time, the toolchain is broken. It said:" >&2
	printf '%s\n' "$2" | tidy | sed 's/^/    /' >&2
	exit 2
}

# BOUNDED MAKES. make runs a recipe line that names $(MAKE) even under -n, so
# a rule that calls itself (`all:` then `$(MAKE) all`) ran a make inside a
# make without end, hundreds of levels a second, and a $(shell sleep ...)
# ran as long as it said: Bazel gives a build action no time limit, so
# `bazel test //...` hung there (F0495). So every make here runs through
# bmake, which stops it after MAKE_TMO seconds, or as soon as it runs
# MAKE_DEPTH processes deep. The depth is read from the process tree (ps),
# and not from what make prints: a sub-make says "make[N]: Entering
# directory" only unless told not to, and --no-print-directory, on the
# $(MAKE) line or in a Makefile's MAKEFLAGS, tells every level not to. No
# dry run of a Makefile goes that deep on its own, the shells a recipe line
# or a $(shell) runs in counted. A "make[MAKE_DEPTH]:" line in its output
# stops it too, which still holds where ps cannot be run. The depth is what
# the Makefile does on any machine: a stand-in, by bounded. The time may be
# the machine's load: exit 2, uncached. MAKE_TMO is generous, since a dry
# run of the largest Makefile here takes well under a second;
# STUDENT_BUILD_MAKE_TIMEOUT sets it for a hand run, and for the
# selftest's arms.
MAKE_TMO=${STUDENT_BUILD_MAKE_TIMEOUT:-120}
case "$MAKE_TMO" in
	"" | *[!0-9]* | 0)
		echo "student_build.sh: STUDENT_BUILD_MAKE_TIMEOUT is a number of seconds, not '$MAKE_TMO'" >&2
		exit 2 ;;
esac
MAKE_DEPTH=40
# bmake_deep PID: whether a process MAKE_DEPTH levels below PID runs (exit
# 0); 1 when none does, or when ps cannot say.
bmake_deep() {
	ps -A -o pid= -o ppid= 2> /dev/null | awk -v top="$1" -v deep="$MAKE_DEPTH" '
		{ kids[$2] = kids[$2] " " $1 }
		END {
			lv[top] = 0
			q[0] = top
			h = 0
			t = 1
			while (h < t) {
				p = q[h++]
				n = split(kids[p], k, " ")
				for (i = 1; i <= n; i++) {
					if (k[i] in lv)
						continue
					lv[k[i]] = lv[p] + 1
					if (lv[k[i]] >= deep)
						exit 0
					q[t++] = k[i]
				}
			}
			exit 1
		}'
}
# bmake OUT ERR COMMAND...: COMMAND, bounded and in the C locale, with its
# stdout in OUT and its stderr in ERR (OUT again for both in one); its
# status, 124 when MAKE_TMO stopped it. $WORK/bmake.deep says the depth did,
# and $WORK/bmake.pid holds its job's PID while it runs. Each caller runs it
# in a subshell started with & and waits for that, its PID in BMAKE_SUB: a
# shell runs a trap only once the command it waits on in the foreground has
# ended, and `wait` is the one wait a signal cuts short.
bmake() {
	_bo=$1
	_be=$2
	shift 2
	rm -f "$WORK/bmake.deep"
	# A build action: no test's limit reaches it, and Bazel bounds it by none.
	# In make's own English, whoever runs the build: make translates its
	# messages, and this script reads them -- the depth below, the lines -w
	# prints around a sub-make, "No targets" -- in English (N155). LANGUAGE
	# is emptied as well as overridden by LC_ALL, as the database makes do.
	if [ "$_bo" = "$_be" ]; then
		# conventions: bounds itself -- a build action (above)
		LANGUAGE='' LC_ALL=C timeout -k 5 "$MAKE_TMO" "$@" > "$_bo" 2>&1 &
	else
		# conventions: bounds itself -- a build action (above)
		LANGUAGE='' LC_ALL=C timeout -k 5 "$MAKE_TMO" "$@" > "$_bo" 2> "$_be" &
	fi
	_bp=$!
	echo "$_bp" > "$WORK/bmake.pid"
	# Looked at often at first, since most makes here end in a few
	# hundredths of a second, and each look is time every build waits.
	_bn=0
	while kill -0 "$_bp" 2> /dev/null; do
		if grep -q "^${MAKE_BIN##*/}\[$MAKE_DEPTH\]: " "$_bo" "$_be" 2> /dev/null ||
			bmake_deep "$_bp"; then
			: > "$WORK/bmake.deep"
			kill "$_bp" 2> /dev/null
			break
		fi
		_bn=$((_bn + 1))
		if [ "$_bn" -le 20 ]; then sleep 0.01; else sleep 0.1; fi
	done
	# A job a signal ended is reported on stderr ("Terminated") by wait.
	wait "$_bp" 2> /dev/null
	_bs=$?
	rm -f "$WORK/bmake.pid"
	return "$_bs"
}
# bounded WHAT STATUS: how a make bmake ran (WHAT, as the student would run
# it) ended, when it was stopped.
bounded() {
	[ -f "$WORK/bmake.deep" ] && standin broke "make runs make inside itself without end." <<-EOF
	  Asked about the build without building it ('$1'), make ran a recipe
	  line that calls \$(MAKE) -- make runs those even then -- and each make
	  it started started another, until the chain was $MAKE_DEPTH deep and
	  this stopped it. A bare 'make' would do the same, without end.

	  Which rule calls make again, and what is the make it starts asked to
	  build?
	EOF
	[ "$2" -eq 124 ] || return 0
	echo "student_build.sh: $1 did not finish within ${MAKE_TMO}s ($LABEL)." >&2
	echo "  A loaded machine slows make down, and so does a Makefile that makes it" >&2
	echo "  wait: what does yours run while make reads it (a \$(shell ...), say)?" >&2
	exit 2
}

# ------------------------------------------------------------ the Makefile
# No Makefile yet, and sources to build until there is one: build those.
if [ -n "$MAKEFILE" ] && [ ! -f "$MAKEFILE" ] && [ -n "$FALLBACK" ]; then
	MAKEFILE=""
	SRCS=$FALLBACK
fi
if [ -n "$MAKEFILE" ]; then
	[ -f "$MAKEFILE" ] || standin empty "there is no Makefile at $MAKEFILE." <<-EOF
	  This $(standin_noun)'s programs are built from what its Makefile compiles, and
	  the turn-in has no Makefile there (the name is case-sensitive: a
	  makefile is not a Makefile).
	EOF
	command -v "$MAKE_BIN" > /dev/null 2>&1 || {
		echo "student_build.sh: no make at '$MAKE_BIN'" >&2
		exit 2
	}
	case "$MAKE_BIN" in
		/*) ;;
		*/*) MAKE_BIN="$PWD/$MAKE_BIN" ;;
	esac
	SRCDIR=$(dirname "$MAKEFILE")
	# A COPY, because the Makefile may include a file make would rebuild even
	# under -n, and the tree here is read-only. The compile below still reads
	# the files in place, so every diagnostic names the path you edit. A copy
	# of the files the links point to (-L), as make_test.sh stages its tree:
	# a sandbox lays its inputs out as symlinks, cp -R kept them, and make
	# wrote a remade include through one into the student's own file, while
	# db_make compared each file with itself (F0494).
	mkdir -p "$WORK/make" && cp -RL "$SRCDIR"/. "$WORK/make"/ 2> /dev/null || {
		echo "student_build.sh: could not stage '$SRCDIR'" >&2
		exit 2
	}
	# -w, and MAKEFLAGS=Bnw on the command line: every directory make runs a
	# recipe in is printed, the sub-makes' too, so each path below is read
	# against the directory it is relative to (THE DIRECTORY A RECIPE RUNS
	# IN). A sub-make prints its own only by default, and not at all under
	# the `MAKEFLAGS += --no-print-directory` many Makefiles carry to keep
	# their output quiet; a MAKEFLAGS given on the command line overrides that
	# assignment, and keeps -B and -n for every sub-make -- a MAKEFLAGS that
	# dropped them would have the sub-make really build.
	# A PART BUILT BY A RULE OF ITS OWN: the rule, from make's database
	# (goal_state: 0 a rule, 1 none, 3 a name with nothing to do). The goal
	# asked for is .DEFAULT, which no rule step uses, so make reads every
	# line, prints its database, and stops on one error of its own: that
	# .DEFAULT has no rule, or that a prerequisite the Makefile gives it has
	# none. The database is trusted only when make read the whole Makefile,
	# which stderr alone cannot say: a $(error) whose text holds a newline
	# ends in that complaint, word for word. So make reads a makefile of
	# this runner's after the one it reads by itself (the first of
	# GNUmakefile, makefile and Makefile), and the variable that sets with
	# override, so that no value the Makefile gives it stands, printed in the
	# last database as set from that file, says the reading got there; its
	# rule for itself keeps make from remaking it with a rule of the
	# student's. The last, because make prints a database each time it reads
	# the Makefile: once it has made a makefile the Makefile includes, it
	# starts again and reads every line anew, and that reading is the one
	# `make G` goes on with, so its database is the one read below. That
	# makefile asks for the database too, adding -pnq to MAKEFLAGS as a
	# Makefile does (with override only when the Makefile set its own
	# MAKEFLAGS with it, which a plain assignment cannot change): so whenever
	# make reads the Makefile, $(MAKEFLAGS) reads as it does under `make G`,
	# and a sub-make that remakes an include is not asked for a dry run, as
	# make leaves -n and -q out of what it passes on while it remakes them. A
	# reading that stops before the end prints no database, then, so a
	# makefile of this runner's read first prints a line each reading starts
	# with, and only a database after the last such line is read; it also
	# empties MAKEFILE_LIST, which the Makefile then reads as under `make G`.
	# But make passes -p on to a sub-make that remakes an include, so it
	# prints a database too, and one whose output is the include leaves that
	# database there, for make to read as lines of the Makefile the next time.
	# So a reading after which a file of the tree holds a database it did not
	# hold before is not trusted: the tree is put back as it was before it, a
	# make asked for no database, and for a goal of this runner's whose rule
	# runs nothing, makes the includes as `make G` makes them, and make is
	# read again, told that the files the first reading made or changed are up
	# to date (-o), so that an include made each time make reads the Makefile
	# is read as that make made it. -o knows a file only by the name it is
	# given, so each is given as a path from the folder make runs in and as
	# one from $(CURDIR); a file the Makefile names another way is remade all
	# the same. A second reading that leaves a database too stops this
	# runner, which says why: a built-in rule would answer the planning below
	# for a rule G the Makefile lacks. A database left in a file outside the
	# tree is not seen.
	# The makefile read last sets .RECIPEPREFIX back to a tab before any rule
	# of its own, so none of its lines reads as a recipe under a prefix the
	# Makefile set last. And make is given both names relative to the folder
	# it runs in, so a space, a # or a $ in the path of this runner's scratch
	# folders is no part of what make reads. Then make ended without an error,
	# or the last line it wrote ends in that complaint: make stops at its
	# first error, so what it printed on the way was none -- a recipe given
	# twice, a $(warning) whose text holds ***, what a $(shell) wrote to
	# stderr (with no newline, the complaint ends that line), a sub-make that
	# failed to remake an optional include. Under -k, from the Makefile's
	# MAKEFLAGS or the environment's, make goes on past an error and its
	# complaint has no "Stop.", and may follow it with a warning of a clock
	# skew (a makefile it read is dated in the future): that is allowed, but a
	# makefile it failed to remake is not -- an include that is not there,
	# whose rules the database lacks. That is a makefile make names so on
	# stderr and its last database marks as failed to be updated: a sub-make
	# that a $(shell) runs says the same words of its own makefiles, which are
	# in no database of this make's. Any other end is an error that stopped
	# the reading, and that Makefile is left to the planning below, which
	# shows make's own words. The complaint is matched in make's own English:
	# make translates its messages, so this one call runs with LC_ALL=C and no
	# LANGUAGE. And make is given the MAKECMDGOALS that `make G` sets, through
	# the environment, so a Makefile that reads it (one that refuses a goal it
	# does not know, say) reads here as it does when G is asked for, and one
	# that sets it itself reads its own value, as under `make G`. The makefile
	# of this runner's read first takes it out of the environment make gives
	# the recipes, so a make a recipe runs reads its own goals, as under
	# `make G`; a $(shell) still passes it on. The database prints each
	# variable with its value, and a
	# value may hold any line, the "# Files" the rules are listed under among
	# them. So the makefile of this runner's also writes a pattern rule named
	# for this run, which make lists among its implicit rules, after every
	# variable, and whose recipes make prints with the tab that makefile set
	# the prefix back to. Each database is read from the line that names that
	# rule on, block by block, as make prints them: a recipe line by line,
	# with each line that goes on in the next (an odd number of backslashes at
	# its end) and that next line, whatever it holds; a target's own variables
	# up to the target's own line; a block after a line that names the
	# Makefile's prefix, with that prefix; the blocks of a :: rule as one; and
	# the files up to the line make prints after them, never the search paths
	# it prints next. A database that strays from that shape, or names a file
	# twice, stops this runner, which says why: it is never left to the
	# planning below, which a Makefile made to stray from it on purpose would
	# reach with no rule G, and a built-in rule would then answer. The last
	# database is trusted only when it was read to that line. A rule G found
	# there is looked for again in the database of a second reading, made as
	# the planning below reads the Makefile (make -Bnw, with MAKEFLAGS=Bnw on
	# the command line, and a makefile of this runner's read last that adds
	# nothing to MAKEFLAGS, so that a sub-make that remakes an include runs as
	# under that planning), which must be trusted too, leaving no database
	# in a file of the tree, and name G with the same prerequisites, and its
	# recipes from the same lines. A Makefile that tests MAKEFLAGS can have a
	# rule G under `make G` and none under that dry run, which a built-in rule
	# would then answer, or another, which would be planned in its place; this
	# runner stops then, and says why. The rules of what G depends on, and the
	# values its recipes use, are not compared. What may still read as lines
	# of a database: a name that holds a newline, and a value of a target's
	# own made to print the lines of a block.
	if [ -n "$MAKE_GOAL" ]; then
		_db_mf=Makefile
		for _db_f in GNUmakefile makefile Makefile; do
			if [ -f "$WORK/make/$_db_f" ]; then
				_db_mf=$_db_f
				break
			fi
		done
		_db_run=${WORK##*/}
		printf '%s\n' "\$(info harness-reading-$_db_run)" 'MAKEFILE_LIST :=' 'unexport MAKECMDGOALS' \
			> "$WORK/pre.mk"
		printf '%s\n' 'override HARNESS_READ_TO_THE_END := yes' 'override .RECIPEPREFIX :=' \
			'ifeq ($(findstring override,$(origin MAKEFLAGS)),)' 'MAKEFLAGS += -pnq' 'else' \
			'override MAKEFLAGS += -pnq' 'endif' '../pre.mk ../probe.mk: ;' \
			"harness-anchor-$_db_run%: ;" > "$WORK/probe.mk"
		printf '%s\n' 'override .RECIPEPREFIX :=' "harness-remade-$_db_run: override .EXTRA_PREREQS :=" \
			".PHONY: harness-remade-$_db_run" "harness-remade-$_db_run: ;" '../pre.mk ../remake.mk: ;' \
			> "$WORK/remake.mk"
		# db_make DB WHAT [SWITCH...]: one reading, its databases in $WORK/DB
		# and what make wrote to stderr in $WORK/DB.err, its status in _db_rc,
		# and in _db_leak 1 when a make it ran wrote a database into a file
		# of the tree, which is then put back as it was before the reading,
		# and the files that reading made or changed are listed in
		# $WORK/DB.made. With _db_old, a list of such files, make takes each
		# as up to date (-o), by both its names.
		db_make() {
			_db_o=$1
			_db_w=$2
			shift 2
			rm -rf "$WORK/staged" && mkdir "$WORK/staged" && cp -pR "$WORK/make"/. "$WORK/staged"/ || {
				echo "student_build.sh: could not stage '$SRCDIR'" >&2
				exit 2
			}
			_db_rc=0
			_db_leak=0
			(cd "$WORK/make" && unset LANGUAGE &&
				if [ -n "$_db_old" ]; then
					_db_cd=$(pwd -P) &&
					while IFS= read -r _db_l; do
						set -- "$@" -o "$_db_l" -o "$_db_cd/$_db_l"
					done < "$_db_old"
				fi &&
				LC_ALL=C && MAKECMDGOALS=$MAKE_GOAL && export LC_ALL MAKECMDGOALS &&
				bmake "$WORK/$_db_o" "$WORK/$_db_o.err" "$MAKE_BIN" "$@" -f ../pre.mk \
					-f "$_db_mf" -f ../probe.mk .DEFAULT) &
			BMAKE_SUB=$!
			wait "$BMAKE_SUB" || _db_rc=$?
			BMAKE_SUB=
			bounded "$_db_w" "$_db_rc"
			died "$_db_rc" "" "$_db_w in $SRCDIR" status-only
			(cd "$WORK/make" && find . -type f -exec grep -l -e '^# Make data base, printed on' {} + \
				2> /dev/null) | {
				while IFS= read -r _db_l; do
					cmp -s "$WORK/make/$_db_l" "$WORK/staged/$_db_l" || { echo leaked; break; }
				done
			} | grep -q leaked && _db_leak=1
			[ "$_db_leak" -eq 0 ] || (cd "$WORK/make" && find . -type f) | {
				while IFS= read -r _db_l; do
					cmp -s "$WORK/make/$_db_l" "$WORK/staged/$_db_l" || printf '%s\n' "${_db_l#./}"
				done
			} > "$WORK/$_db_o.made"
			[ "$_db_leak" -eq 0 ] ||
				{ rm -rf "$WORK/make" && mkdir "$WORK/make" && cp -pR "$WORK/staged"/. "$WORK/make"/; } || {
				echo "student_build.sh: could not stage '$SRCDIR' again" >&2
				exit 2
			}
		}
		# db_read DB: the last database of $WORK/DB, in $WORK/DB.read, and
		# whether it is trusted; one not laid out as make lays one out stops
		# this runner. A reading a database leaked into is not trusted.
		db_read() {
			[ "$_db_leak" -eq 0 ] || return 1
			_db_rd=0
			READING="harness-reading-$_db_run" ANCHOR="harness-anchor-$_db_run%:" \
				PROBE="# 'override' directive (from '../probe.mk', line 1)" \
				awk -v part=read -f "$MAKE_DB" "$WORK/$1" > "$WORK/$1.read" || _db_rd=$?
			if [ "$_db_rd" -eq 3 ]; then
				echo "student_build.sh: cannot tell whether $SRCDIR/$_db_mf has a rule $MAKE_GOAL:" \
					"make's list of its rules (make -p) is not laid out as make lays one out," \
					"which a value or a name that holds lines like make's own can do" >&2
				exit 2
			elif [ "$_db_rd" -gt 1 ]; then
				# Not an answer of the reader's (0, 1 or 3): awk itself failed.
				echo "student_build.sh: could not read make's database of $SRCDIR/$_db_mf" \
					"(awk exited $_db_rd)" >&2
				exit 2
			fi
			[ "$_db_rd" -eq 0 ] &&
				! ERR="$WORK/$1.err" awk -v part=remake -v q="'" -f "$MAKE_DB" "$WORK/$1.read" &&
				{ [ "$_db_rc" -le 1 ] || { [ "$_db_rc" -eq 2 ] &&
					sed -e '$!b' \
						-e '/^[^ :]*: warning:  Clock skew detected\.  Your build may be incomplete\.$/d' \
						"$WORK/$1.err" | sed -n '$p' |
						grep -Eq "\*\*\* No rule to make target ('\.DEFAULT'|'.*', needed by '\.DEFAULT')\.(  Stop\.)?\$"; }; }
		}
		# db_goal DB: the state of the goal in $WORK/DB.read, in _gs, and in
		# $WORK/DB.goal the lines that name it and say where its recipes are.
		db_goal() {
			_gs=0
			GOAL="$WORK/$1.goal" awk -v part=goal -v t="$MAKE_GOAL" -f "$MAKE_DB" "$WORK/$1.read" ||
				_gs=$?
		}
		_db_old=
		db_make db "make -pnq"
		if [ "$_db_leak" -ne 0 ]; then
			cp "$WORK/db.made" "$WORK/db.old"
			_db_rc=0
			(cd "$WORK/make" && unset LANGUAGE &&
				LC_ALL=C && MAKECMDGOALS=$MAKE_GOAL && export LC_ALL MAKECMDGOALS &&
				bmake "$WORK/remade" "$WORK/remade" "$MAKE_BIN" -f ../pre.mk -f "$_db_mf" \
					-f ../remake.mk "harness-remade-$_db_run") &
			BMAKE_SUB=$!
			wait "$BMAKE_SUB" || _db_rc=$?
			BMAKE_SUB=
			bounded "make -pnq" "$_db_rc"
			died "$_db_rc" "" "make, remaking the includes in $SRCDIR," status-only
			_db_old=$WORK/db.old
			db_make db "make -pnq"
			_db_old=
			if [ "$_db_leak" -ne 0 ]; then
				echo "student_build.sh: cannot tell whether $SRCDIR/$_db_mf has a rule $MAKE_GOAL:" \
					"each time make reads it, a make it runs leaves make's database (make -p) in" \
					"a file of the tree, which make may then read as lines of the Makefile" >&2
				exit 2
			fi
		fi
		if db_read db; then
			db_goal db
			case "$_gs" in
				0)
				printf '%s\n' 'override HARNESS_READ_TO_THE_END := yes' 'override .RECIPEPREFIX :=' \
					'../pre.mk ../probe.mk: ;' "harness-anchor-$_db_run%: ;" > "$WORK/probe.mk"
				db_make pdb "make -Bnwp MAKEFLAGS=Bnw" -Bnwp MAKEFLAGS=Bnw
				# A database leaked into that reading says nothing this runner
				# can read of how the dry run reads the Makefile.
				if [ "$_db_leak" -ne 0 ]; then
					echo "student_build.sh: cannot plan 'make $MAKE_GOAL' from $SRCDIR/$_db_mf:" \
						"make reads a rule $MAKE_GOAL there, but read as the dry run this runner plans" \
						"the build with reads it (make -Bnw MAKEFLAGS=Bnw $MAKE_GOAL), it leaves" \
						"make's database in a file of the tree, which make may then read as lines of" \
						"the Makefile" >&2
					exit 2
				fi
				_gs=4
				! db_read pdb || db_goal pdb
				if [ "$_gs" -ne 0 ] || ! cmp -s "$WORK/db.goal" "$WORK/pdb.goal"; then
					echo "student_build.sh: cannot plan 'make $MAKE_GOAL' from $SRCDIR/$_db_mf:" \
						"make reads a rule $MAKE_GOAL there, but the dry run this runner plans the" \
						"build with (make -Bnw MAKEFLAGS=Bnw $MAKE_GOAL) reads none, or another, or" \
						"stops before the end of the Makefile. A Makefile that tests MAKEFLAGS," \
						"which that run sets, can read differently under it" >&2
					exit 2
				fi
				;;
				1) standin empty "your Makefile has no $MAKE_GOAL rule." <<-EOF
				  This program is what 'make $MAKE_GOAL' builds, and make's own list of
				  the rules your Makefile defines (make -p) has none named $MAKE_GOAL.
				  Nothing else stands in for one here: a file or a folder named
				  $MAKE_GOAL, or a source make can compile by itself, would let 'make
				  $MAKE_GOAL' answer without a rule of yours.

				  If this part is not written yet, that is exactly what you should
				  expect to see. If it is: which rule of your Makefile does
				  'make $MAKE_GOAL' run?
				EOF
				;;
				3) standin empty "your Makefile names $MAKE_GOAL and gives it no rule." <<-EOF
				  This program is what 'make $MAKE_GOAL' builds. Your Makefile names
				  $MAKE_GOAL (in .PHONY, say, or as a target alone) but gives it no
				  prerequisite and no recipe, so 'make $MAKE_GOAL' has nothing to do.

				  If this part is not written yet, that is exactly what you should
				  expect to see. If it is: what does make need before it has
				  anything to run for $MAKE_GOAL?
				EOF
				;;
				*) echo "student_build.sh: could not read make's database of $SRCDIR/Makefile" >&2; exit 2 ;;
			esac
		fi
	fi
	(cd "$WORK/make" &&
		bmake "$WORK/recipes" "$WORK/recipes" "$MAKE_BIN" -Bnw MAKEFLAGS=Bnw ${MAKE_GOAL:+"$MAKE_GOAL"}) &
	BMAKE_SUB=$!
	MAKE_RC=0
	wait "$BMAKE_SUB" || MAKE_RC=$?
	BMAKE_SUB=
	RECIPES=$(cat "$WORK/recipes")
	bounded "$MK_ASK" "$MAKE_RC"
	died "$MAKE_RC" "$RECIPES" "$MK_ASK in $SRCDIR" status-only
	# What make said, as the student would read it: without the top
	# directory's own Entering/Leaving lines (-w's, not their Makefile's),
	# and a sub-make's directory from the Makefile's, not from our scratch copy.
	TOP=$(cd "$WORK/make" && pwd -P)
	SHOWN=$(printf '%s\n' "$RECIPES" | awk -v top="$TOP" -v wk="$WORK/make" '
		{
			line = $0
			if (match(line, /^[^ ]+: (Entering|Leaving) directory ./)) {
				pre = substr(line, 1, RLENGTH - 1)
				d = substr(line, RLENGTH + 1)
				sub(/.$/, "", d)
				if (d == top || d == wk) next
				if (index(d, top "/") == 1) { print pre "\047" substr(d, length(top) + 2) "\047"; next }
				if (index(d, wk "/") == 1) { print pre "\047" substr(d, length(wk) + 2) "\047"; next }
			}
			print line
		}')
	# A MAKEFILE WITH NO TARGET -- comments alone, or variables alone, as the
	# stub of an exercise not started can be (C 11 ex05's) -- is make's own
	# "No targets.  Stop.", a refusal to plan, and the same fact as recipes
	# that compile nothing: nothing is written yet. So it is read as that,
	# below, never as a Makefile written and broken, which "could not work
	# out what to build" told a student who had not started it.
	if [ "$MAKE_RC" -ne 0 ] &&
		printf '%s\n' "$RECIPES" | grep -q '^[^ ]*: \*\*\* No targets\.  Stop\.$'; then
		MAKE_RC=0
		RECIPES=""
	fi
	[ "$MAKE_RC" -eq 0 ] || standin broke "'$MK_ASK' could not work out what to build." <<-EOF
	  Nothing was compiled: this is make refusing to plan the build, not
	  your code failing to compile. A file named in the Makefile that is not
	  in the turn-in, or a syntax error in the Makefile, both look like this.

	$SHOWN
	EOF

	# THE DIRECTORY A RECIPE RUNS IN. A Makefile that builds a library first
	# -- `$(MAKE) -C libft`, the shape of nearly every Common Core project
	# after libft -- has that sub-make's recipes run in libft/, and every path
	# in them (a .c, an -I) is relative to libft/, not to the Makefile's own
	# directory. -w above has make say "Entering directory" and "Leaving
	# directory" around each one, so the lines are read in order, with the
	# directory each is in; a path is then resolved from there and named from
	# the Makefile's directory (libft/ft_strlen.c). Read from the top
	# Makefile's directory alone, a sub-make's sources were "not in the
	# turn-in" -- a false stand-in on a correct project.
	#
	# rel_of DIR: DIR (absolute, as make prints it) from the Makefile's
	# directory, "" for that directory itself; exits 1 for a directory
	# outside the turn-in (`$(MAKE) -C ../libft`).
	rel_of() {
		for _ro_top in "$TOP" "$WORK/make"; do
			case "$1" in
				"$_ro_top") printf ''; return 0 ;;
				"$_ro_top"/*) norm_rel "${1#"$_ro_top"/}"; return ;;
			esac
		done
		return 1
	}
	# norm_rel PATH: a relative PATH with its . and .. segments folded and
	# no trailing /, "" for the directory itself; exits 1 when a .. climbs
	# out of the Makefile's directory -- a path outside the turn-in.
	norm_rel() {
		_nr_out=""
		_nr_ifs=$IFS
		IFS=/
		set -f
		# shellcheck disable=SC2086
		set -- $1
		set +f
		IFS=$_nr_ifs
		for _nr_s in "$@"; do
			case "$_nr_s" in
				"" | .) ;;
				..)
					[ -n "$_nr_out" ] || return 1
					case "$_nr_out" in
						*/*) _nr_out=${_nr_out%/*} ;;
						*) _nr_out="" ;;
					esac ;;
				*) _nr_out=${_nr_out:+$_nr_out/}$_nr_s ;;
			esac
		done
		printf '%s' "$_nr_out"
	}
	# resolve TOKEN: TOKEN, a path as a recipe gives it, from the Makefile's
	# directory; exits 1 when it is outside the turn-in (an absolute path, a
	# .. out of it, a sub-make that runs outside it).
	resolve() {
		case "$1" in /*) return 1 ;; esac
		[ "$REL" != "!" ] || return 1
		norm_rel "${REL:+$REL/}$1"
	}

	# Every .c token in a recipe, in order, once. Order is kept so a message
	# reads in the order the Makefile lists them. A token that is not a file
	# here is listed, not silently dropped. A recipe is split on blanks, as
	# the shell that would run it splits it -- make has no way to name a file
	# with a blank in it -- but never globbed HERE: a `cc *.c` recipe means
	# the .c files of the directory the recipe runs in, which is where the
	# pattern is expanded below, never this script's working directory.
	NAMED_MISSING=""
	keep_src() {
		case "$NL$SRCS$NL" in
			*"$NL$1$NL"*) return ;;
		esac
		SRCS=$(add "$SRCS" "$1")
	}
	# Every -I directory the recipes pass, in order, once. A layout with its
	# headers in a folder of their own (srcs/ and includes/, the Common
	# Core's) compiles only because the Makefile says `-I includes`, and the
	# compile below uses our flags, not the Makefile's -- so the include path
	# is the one thing besides the source list that is taken from it. -I and
	# nothing else: a -W or -O of theirs would soften or change what every
	# layer measures, and a -D is a question nobody has settled. A directory
	# is relative to the one its recipe runs in, as make runs it; one outside
	# the turn-in (an absolute path, a ..) would reach files that are not the
	# student's, so it is left out, and said so if the build then fails.
	INCS=""
	INC_SKIPPED=""
	keep_inc() {
		_i=$1
		case "$_i" in
			\"*\" | \'*\') _i=${_i#?}; _i=${_i%?} ;;
		esac
		if ! _i=$(resolve "$_i"); then
			# conventions: not-a-list -- part of a message, printed whole and never split
			INC_SKIPPED="$INC_SKIPPED -I$1"
			return
		fi
		_i=$SRCDIR${_i:+/$_i}
		case "$NL$INCS$NL" in
			*"$NL-I$_i$NL"*) return ;;
		esac
		INCS=$(add "$INCS" "-I$_i")
	}
	keep_c() {
		_tok=$1
		if [ "$REL" = "!" ]; then
			NAMED_MISSING="$NAMED_MISSING $_tok (in a directory outside the turn-in)"
			return
		fi
		case "$_tok" in
			*[*?[]*)
				_hit=""
				for _g in "$SRCDIR${REL:+/$REL}"/$_tok; do
					[ -f "$_g" ] || continue
					_r=$(norm_rel "${_g#"$SRCDIR"/}") || continue
					keep_src "$SRCDIR/$_r"
					_hit=1
				done
				[ -n "$_hit" ] || NAMED_MISSING="$NAMED_MISSING ${REL:+$REL/}$_tok"
				return ;;
		esac
		if ! _r=$(resolve "$_tok"); then
			NAMED_MISSING="$NAMED_MISSING $_tok (outside the turn-in)"
			return
		fi
		if [ ! -f "$SRCDIR/$_r" ]; then
			NAMED_MISSING="$NAMED_MISSING $_r"
			return
		fi
		keep_src "$SRCDIR/$_r"
	}
	REL=""
	STACK=""
	while IFS= read -r _line; do
		case "$_line" in
			*": Entering directory "[\`\']*\')
				case "${_line%%: Entering directory *}" in *" "*) ;; *)
					_d=${_line#*: Entering directory ?}
					_d=${_d%\'}
					STACK="$REL$NL$STACK"
					REL=$(rel_of "$_d") || REL="!"
					continue ;;
				esac ;;
			*": Leaving directory "[\`\']*\')
				case "${_line%%: Leaving directory *}" in *" "*) ;; *)
					REL=${STACK%%"$NL"*}
					STACK=${STACK#*"$NL"}
					continue ;;
				esac ;;
		esac
		set -f
		# shellcheck disable=SC2086
		set -- $_line
		set +f
		_want_inc=""
		for tok in "$@"; do
			if [ -n "$_want_inc" ]; then
				_want_inc=""
				keep_inc "$tok"
				continue
			fi
			case "$tok" in
				-I) _want_inc=1 ;;
				-I*) keep_inc "${tok#-I}" ;;
				*.c) keep_c "${tok#./}" ;;
			esac
		done
	done <<-RECIPES_EOF
	$RECIPES
	RECIPES_EOF
	[ -z "$INCS" ] || CFLAGS=$(add "$CFLAGS" "$INCS")
	if [ -n "$INCLUDES_OUT" ]; then
		printf '%s\n' "$INCS" | sed -n 's/^-I//p' > "$INCLUDES_OUT" || {
			echo "student_build.sh: cannot write '$INCLUDES_OUT'" >&2
			exit 2
		}
	fi
	# Every .c the recipes compile that is in the turn-in, from the
	# Makefile's directory: make planned the build, so this is known now,
	# whether or not what it names then compiles.
	if [ -n "$SOURCES_OUT" ]; then
		: > "$SOURCES_OUT" || { echo "student_build.sh: cannot write '$SOURCES_OUT'" >&2; exit 2; }
		_rel_src() { printf '%s\n' "${1#"$SRCDIR"/}" >> "$SOURCES_OUT"; }
		each "$SRCS" _rel_src
	fi

	# The list the Makefile gave, said FIRST in anything that follows: the
	# compiler's errors can be long, and a reader cut off below them never
	# learns that these files came from their own Makefile.
	if [ -n "$MAKE_GOAL" ]; then
		MAKE_NOTE="  Your Makefile's $MAKE_GOAL rule builds the program from:$NL$(indent "$SRCS")$NL"
	else
		MAKE_NOTE="  Your Makefile builds the program from:$NL$(indent "$SRCS")$NL"
	fi
	[ -z "$INCS" ] || MAKE_NOTE="$MAKE_NOTE  with the include directories it passes:$NL$(indent "$INCS")$NL"
	[ -z "$INC_SKIPPED" ] || MAKE_NOTE="$MAKE_NOTE  (left out, being outside the turn-in:$INC_SKIPPED)$NL"
	MAKE_NOTE="$MAKE_NOTE$NL"

	# A source the recipes name that is not in the turn-in is not something to
	# skip: `make` would fail on it -- "No such file or directory" -- so the
	# program does not build, and the files that are there must not stand in
	# for it (they link, or fail to link, in a way that names neither the
	# Makefile nor the missing file). It is also what a file left out of the
	# push looks like, and a name no layer can carry ("utils (1).c"), which
	# the files layer reports.
	[ -z "$NAMED_MISSING" ] || standin broke "the Makefile names a source that is not in the turn-in." <<-EOF
	  '$MK_ASK' says $MK_WHAT compiles:$NAMED_MISSING
	  and there is no such file in the turn-in ($SRCDIR). Run by the
	  grader, make stops right there. Each path is the one the recipe
	  gives, read from the directory that recipe runs in -- the
	  Makefile's own, or the one a sub-make enters with -C libft -- and
	  named here from the Makefile's: check its spelling and case, and
	  that the file is committed with the rest.

	  This is what it said it would run:

	$SHOWN
	EOF
	# A Makefile whose recipes compile nothing, and sources to build until
	# it does (UNTIL THE MAKEFILE IS WRITTEN): build those.
	if [ -z "$SRCS" ] && [ -n "$FALLBACK" ]; then
		SRCS=$FALLBACK
		MAKE_NOTE="  Your Makefile compiles nothing yet, so the program is built from every$NL  .c file of the folder:$NL$(indent "$SRCS")$NL$NL"
	fi
	if [ -z "$SRCS" ] && [ -n "$MAKE_GOAL" ]; then
		standin empty "'make $MAKE_GOAL' compiles no .c files." <<-EOF
		  '$MK_ASK' was asked what the $MAKE_GOAL rule would run and named no
		  source: either it builds something other than this program, or its
		  recipes never mention the sources by name.

		  If this part is not written yet, that is exactly what you should
		  expect to see.

		  This is what it said it would run:

		$SHOWN
		EOF
	fi
	[ -n "$SRCS" ] || standin empty "the Makefile compiles no .c files." <<-EOF
	  'make -Bn' was asked what the default goal would run and named no
	  source.
	  Either the default goal builds something other than the program (the
	  first target in the file is the default one -- check what that is), or
	  the recipes never mention the sources by name.

	  If this $(standin_noun) is not written yet, that is exactly what you should
	  expect to see: a stub Makefile whose recipes only echo compiles
	  nothing, so there is no program for the run layers to run.

	  This is what it said it would run:

	$SHOWN
	EOF
fi

if [ -z "$SRCS" ] && [ -z "$HARNESS" ]; then
	standin empty "there is no .c file to build${DIR:+ in $DIR}." <<-EOF
	  This test runs a program built from your files, and there are none
	  there. The subject's "Files to turn in" line says which files belong
	  there.
	EOF
fi
_own=""
is_own() { case "$1" in "$DIR"/*) _own=1 ;; esac; }
each "$SRCS" is_own
if [ -n "$DIR" ] && [ -z "$_own" ]; then
	standin empty "none of the files it is built from is in $DIR." <<-EOF
	  This program is built from .c files of yours in $DIR, and none of
	  them is there. The subject's "Files to turn in" line says which
	  files belong there.
	EOF
fi

# ---------------------------------------------------------------- compiling
# One command line from the template, one argument per line, @SRC@ and @OBJ@
# replaced. -frandom-seed gets the path the object stands for rather than the
# scratch one, so two builds of the same files write the same object.
# One sed over the whole template, not one per argument: this runs once per
# file of every program in the repo. The paths are escaped for sed's
# replacement text, where & and the delimiter mean something (sedre, above,
# escapes one for a pattern).
sedrep() { printf '%s' "$1" | sed 's/[#&\\]/\\&/g'; }
expand() {  # expand TEMPLATE SRC OBJ
	_es=$(sedrep "$2")
	_eo=$(sedrep "$3")
	_er=$(sedrep "${2%.c}.o")
	printf '%s\n' "$1" | sed -e "/^-frandom-seed=/s#@OBJ@#$_er#g" \
		-e "s#@SRC@#$_es#g" -e "s#@OBJ@#$_eo#g"
}
# Run the command whose arguments are the lines of $1 (the tool first), with
# the lines as separate words -- IFS is a newline for the expansion only.
run_lines() {  # run_lines ARGS-ONE-PER-LINE
	_old_ifs=$IFS
	IFS=$NL
	set -f
	# shellcheck disable=SC2086
	set -- $1
	set +f
	IFS=$_old_ifs
	"$@"
}

ERRS=""
FAILED=""
compile() {  # compile SRC OBJ
	mkdir -p "$(dirname "$2")"
	_argv=$(printf '%s\n%s' "$CC" "$(expand "$CFLAGS" "$1" "$2")")
	_out=$(run_lines "$_argv" 2>&1)
	_rc=$?
	died "$_rc" "$_out" "the compiler, on $1,"
	if [ "$_rc" -ne 0 ]; then
		FAILED=$(add "$FAILED" "$1")
		ERRS="$ERRS$_out$NL"
	elif [ -n "$_out" ]; then
		ERRS="$ERRS$_out$NL"
	fi
}
objof() { printf '%s/o/%s.o' "$WORK" "${1%.c}"; }

OBJS=""
LIBOBJS=""
# Every file, even after one fails: all of a file's errors, and every file's,
# in one run, the way `make -k` would show them.
compile_harness() {
	case "$1" in *.c) ;; *) return ;; esac
	compile "$1" "$(objof "$1")"
	OBJS=$(add "$OBJS" "$(objof "$1")")
}
compile_src() {
	case "$1" in *.c) ;; *) return ;; esac
	compile "$1" "$(objof "$1")"
	LIBOBJS=$(add "$LIBOBJS" "$(objof "$1")")
}
each "$HARNESS" compile_harness
each "$SRCS" compile_src

# ------------------------------------------------- a harness that fails
# Where a failed file is the harness's own (a --harness source, under tests/),
# the error can still be the student's: the harness compiles against their
# header, and what that header holds (a structure written otherwise, a name
# it lacks or defines twice) can fail there first. Never a declaration of
# the function under test: a harness carries its own (//tools:conventions).
# Or it cannot be: a harness file that no file of the
# student's reaches fails the same whatever they wrote, and blaming them for it
# would send them hunting a bug that is not theirs -- in a stand-in Bazel then
# caches. So ask the preprocessor which headers that compile read (-E -H, the
# same command line otherwise). A header is the student's when it lies in the
# zone (a deliverable/ or generators/ folder), or beside a --src of theirs
# that is not a file of the harness's under tests/. A header that is not
# found at all may be one of theirs that is missing, so it is theirs too.
HARNESS_FAILED=""
_is_harness() {
	case "$NL$HARNESS$NL" in
		*"$NL$1$NL"*) HARNESS_FAILED=$(add "$HARNESS_FAILED" "$1") ;;
	esac
}
each "$FAILED" _is_harness

STUDENT_DIRS=""
_student_dir() {
	case "/$1" in
		*/tests/*) case "/$1" in */deliverable/* | */generators/*) ;; *) return ;; esac ;;
	esac
	_d=$(dirname "$1")
	case "$NL$STUDENT_DIRS$NL" in *"$NL$_d$NL"*) return ;; esac
	STUDENT_DIRS=$(add "$STUDENT_DIRS" "$_d")
}
each "$SRCS" _student_dir
[ -z "$DIR" ] || _student_dir "$DIR/x.c"

reads_student() {  # reads_student HARNESS-SRC -- true when a file of the student's reached it
	_argv=$(printf '%s\n%s\n-E\n-H' "$CC" "$(expand "$CFLAGS" "$1" /dev/null)")
	_pp=$(run_lines "$_argv" 2>&1 > /dev/null)
	_prc=$?
	died "$_prc" "$_pp" "the preprocessor, on $1,"
	[ "$_prc" -eq 0 ] || return 0
	# One header per line, as -H prints them: dots for the depth, a blank,
	# the path. Its own loop, not each(): see there.
	while IFS= read -r _h; do
		[ -n "$_h" ] || continue
		_h=${_h#./}
		case "/$_h" in */deliverable/* | */generators/*) return 0 ;; esac
		case "$NL$STUDENT_DIRS$NL" in *"$NL$(dirname "$_h")$NL"*) return 0 ;; esac
	done <<-READS_EOF
	$(printf '%s\n' "$_pp" | sed -n 's/^\.\{1,\} //p')
	READS_EOF
	return 1
}

if [ -n "$HARNESS_FAILED" ] && [ "${STUDENT_BUILD_STRICT:-0}" = 1 ]; then
	echo "student_build.sh: STUDENT_BUILD_STRICT=1, and a file of the harness" >&2
	echo "  does not compile ($LABEL):" >&2
	indent "$HARNESS_FAILED" >&2
	printf '%s\n' "$ERRS" | tidy >&2
	exit 1
fi
HARNESS_OWN=""
_harness_own() { reads_student "$1" || HARNESS_OWN=$(add "$HARNESS_OWN" "$1"); }
each "$HARNESS_FAILED" _harness_own
if [ -n "$HARNESS_OWN" ]; then
	echo "student_build.sh: a file of the harness does not compile, and no file of" >&2
	echo "  the student's reaches it, so nothing they wrote can have caused it" >&2
	echo "  ($LABEL):" >&2
	indent "$HARNESS_OWN" >&2
	echo "  That is a bug in the test, and it fails the build rather than blaming" >&2
	echo "  their code. What the compiler said:" >&2
	printf '%s\n' "$ERRS" | tidy | sed 's/^/    /' >&2
	exit 2
fi

HARNESS_NOTE=""
[ -z "$HARNESS_FAILED" ] || HARNESS_NOTE="  A file under tests/ is the test's own, compiled against your files:
  what fails there is what your header declares, or does not.
"
if [ -n "$FAILED" ]; then
	_failed=$(indent "$FAILED")
	standin broke "it does not compile." <<-EOF
	$MAKE_NOTE$ERRS
	  It failed in:
	$_failed
	$HARNESS_NOTE  Every layer that runs a program built from these files fails with
	  this message until they compile. The compile layers
	  (exNN_compile_gcc, exNN_compile_clang) say the same about each of your
	  files on its own.
	EOF
fi

# ---------------------------------------------------------------- archiving
# The student's objects as a library the harness links against, so the linker
# takes a file only when something calls into it -- what a cc_library gave, and
# closer to a grader that compiles the files it asked for than a glob is. The
# member names are the objects' paths with / as _, after the object's place in
# the list, so no two collide (ar replaces a member of the same name: a/b_c.o
# and a_b/c.o were one, F0496), and a linker message naming one is turned back
# into the file it came from.
if [ "$ARCHIVE" = 1 ] && [ -n "$HARNESS" ] && [ -n "$LIBOBJS" ]; then
	mkdir -p "$WORK/lib"
	MEMBERS=""
	MAP=""
	_mn=0
	_member() {
		_rel=${1#"$WORK/o/"}
		_mn=$((_mn + 1))
		_m=$_mn-$(printf '%s' "$_rel" | tr '/ ' '__')
		cp "$1" "$WORK/lib/$_m" || { echo "student_build.sh: cannot stage $1" >&2; exit 2; }
		MEMBERS=$(add "$MEMBERS" "$WORK/lib/$_m")
		MAP="$MAP${NL}s#[^ ]*libstudent\\.a($(sedre "$_m"))#$(sedrep "$_rel")#g"
	}
	each "$LIBOBJS" _member
	LIB="$WORK/libstudent.a"
	_argv=$(printf '%s\n%s\n%s' "$AR" "$(printf '%s\n' "$ARFLAGS" | sed "s#@LIB@#$(sedrep "$LIB")#g")" "$MEMBERS")
	if ! _out=$(run_lines "$_argv" 2>&1); then
		echo "student_build.sh: the archiver failed on objects that compiled:" >&2
		printf '%s\n' "$_out" >&2
		exit 2
	fi
	LINKIN=$(add "$OBJS" "$LIB")
else
	MAP=""
	LINKIN=$(add "$OBJS" "$LIBOBJS")
fi

# ------------------------------------------------------------------ linking
# @OBJS@ is a whole argument of its own in the template, so it becomes one
# argument per object, where the toolchain puts its inputs.
_largs=$(printf '%s\n' "$LFLAGS" | while IFS= read -r _a; do
	case "$_a" in
		@OBJS@) printf '%s\n' "$LINKIN" ;;
		*) printf '%s\n' "$_a" | sed "s#@OUT@#$(sedrep "$OUT")#g" ;;
	esac
done)
_argv=$(printf '%s\n%s' "$LD" "$_largs")
_out=$(run_lines "$_argv" 2>&1)
_rc=$?
died "$_rc" "$_out" "the linker"
if [ "$_rc" -ne 0 ]; then
	[ -z "$MAP" ] || _out=$(printf '%s\n' "$_out" | sed -e "${MAP#"$NL"}")
	standin broke "it compiles, and does not link." <<-EOF
	$MAKE_NOTE$ERRS$_out

	  'multiple definition of main' means two entry points: a main() left
	  in a file the subject says holds only a function, or a second file
	  that defines one. 'undefined reference' means a function nobody
	  defines -- a file that is missing, or a name spelled two ways. The
	  compile layers pass in both cases: they compile each file on its own
	  and never link.
	EOF
fi
[ -f "$OUT" ] || { echo "student_build.sh: the link reported success and wrote no '$OUT'" >&2; exit 2; }
exit 0
