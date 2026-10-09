#!/bin/sh
# Header exercise runner (c-08): compile a provided main() against the student's
# header AT TEST TIME, then diff its output.
#
# Why not a cc_binary, which is what every other exercise shape uses: for a
# header exercise the header IS the answer, so an unwritten one does not compile
# — and a cc_binary that does not compile is a Bazel BUILD failure, not a test
# result. The student got a wall of clang diagnostics about a file they never
# wrote (tests/exNN/test_*.c), no CASE/EXPECTED/GOT table, no hint, and
# `bazel test //...` aborted with "FAILED TO BUILD" instead of showing them a
# red test alongside the others. Every other stub in this repo produces a
# legible red test; this shape should too.
#
# Compiling inside the runner turns "the header is not written yet" into exactly
# that: a failing test that says so, with the exercise's clues attached. Same
# trick tools/ilp32_test.sh uses to keep a toolchain problem out of the build
# graph.
#
# c-09's libft bundle (c_libft, --shape libft) comes through here for the same
# reason. c-09 ex01 used to be one, and turned in a header beside its sources: a
# harness main() that reached the five functions through it was a cc_binary
# that stopped COMPILING the moment that header was reduced to its guards --
# -Werror turns every call into an implicit-declaration error, and `bazel test
# //...` died with "Build did NOT complete successfully" on a fresh clone. The
# template had to ship that header filled in to avoid it -- five prototypes that
# are c-08 ex00's whole answer -- and tools/stub_check.sh carried an approval
# saying so. Compiled here, the same header was one red ex01_output with the
# compiler's diagnostics under it, and the approval went. (ex01 is now the
# Makefile alone its subject asks for, built by make_test.sh against the
# grader's files, so today only ex00 uses this shape, with no header.) In this
# shape the --src files are the DELIVERABLE (in c_header they are harness
# helpers), --hdr is optional and may repeat, and the failure text says "what
# you turned in" instead of "your header".
#
# Usage:
#   header_check.sh --differ PATH --hdr FILE --main FILE [--src FILE]...
#                   (--expected FILE [--expected-alt FILE]... | --survive)
#                   [--clues FILE] [--labeled] [--stdin FILE]
#                   [--shape header|libft] [--inc DIR]...
#                   [--harness-src FILE]...
#                   [--exit CODE [--exit-source subject|reading|convention]
#                    [--exit-quote TEXT]]
#                   [--cc NAME] [--ld PATH --ld-lib FILE...]
#                   [--waiting FILE] [-- PROG ARGS...]
#
# Options:
#   --expected-alt FILE, --survive, --stdin FILE
#                 a case's "any_of", its "survive" and its "stdin": handed
#                 to tools/diff_output.sh, which runs the program, as --exit
#                 is (see there for what each means).
#   --shape S     header (default): the header is the whole deliverable and
#                 --hdr is required. libft: the --src files and any --hdr are
#                 what the student turned in; see the paragraph above.
#   --inc DIR     one more include directory, for a deliverable whose sources
#                 #include from somewhere other than beside a --hdr.
#   --harness-src FILE
#                 a harness-side source compiled in beside --main and never
#                 counted as the student's: tools/unbuffered_stdout.c, which
#                 makes the program's stdout unbuffered so that a crash keeps
#                 the rows printed before it (see that file). Passes --harness-fixture
#                 to diff_output.sh, which checks the binary carries it.
#   --exit CODE   also assert the built program exits with CODE. Same flag,
#                 same wording and same semantics as tools/diff_output.sh's,
#                 because it IS diff_output.sh's — see the note above the
#                 delegation at the bottom of this file.
#   --exit-source subject|reading|convention
#                 whose rule CODE is, forwarded with --exit: the wording of a
#                 failure says so (docs/reference.md, "Run contract").
#   --exit-quote TEXT
#                 the subject's sentence behind CODE (a case's "exit_quote"),
#                 forwarded with --exit: a failure quotes it, as a
#                 c_program case's does.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "header_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require dirname mktemp rm

# The shared runner helpers -- time budget, exiting signal traps, how a run
# ended, excerpts, hints -- written once in tools/runner_lib.sh.
RL_NAME=header_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "header_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool CC -- the pinned compiler: it builds, and runs none of what it builds
# conventions: harness tool DIFFER -- tools/diff_output.sh, which runs the program it is handed under this test's budget

DIFFER=""
HDR=""
MAIN=""
SRCS=""
HSRCS=""
INCS=""
EXPECTED=""
CLUES=""
PASS=""
EXPECT_EXIT=""
WAITING=""
EXIT_SOURCE=""
EXIT_QUOTE=""
SURVIVE=0
SHAPE="header"
CC="${HEADER_CC:-cc}"
CC_LIBS=""
LD=""
LD_LIBS=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "header_check.sh: $1 needs a value" >&2; exit 2; }; }

# THE LISTS -- sources, include directories, and the options forwarded to
# diff_output.sh ($PASS) -- are runner_lib.sh's LISTS OF WORDS: one word per
# line, built with rl_list_add and expanded between rl_split_on and
# rl_split_off. They were joined with blanks and expanded bare, so a path
# holding a blank arrived as two words: a --clues or --stdin path in a folder
# named "case 1" reached diff_output.sh as "case" and "1", and the run broke
# with a usage error (exit 2) instead of comparing anything.

while [ $# -gt 0 ]; do
	case "$1" in
		--differ) need "$1" "$#"; DIFFER="$2"; shift 2 ;;
		--hdr) need "$1" "$#"; HDR="$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--main) need "$1" "$#"; MAIN="$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--src) need "$1" "$#"; rl_list_add SRCS "$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		# The unbuffered-stdout library: a program built with it is one
		# diff_output.sh may read case by case after a crash, so it gets
		# --harness-fixture, whose premise diff_output.sh checks in the binary.
		--harness-src) need "$1" "$#"; rl_list_add HSRCS "$2"; rl_list_add PASS --harness-fixture; shift 2 ;;
		--inc) need "$1" "$#"; rl_list_add INCS "-I$2"; shift 2 ;;
		--shape)
			need "$1" "$#"
			case "$2" in
				header | libft) SHAPE="$2" ;;
				*) echo "header_check.sh: --shape must be header or libft, not '$2'" >&2
				   exit 2 ;;
			esac
			shift 2 ;;
		--expected) need "$1" "$#"; EXPECTED="$2"; shift 2 ;;
		--clues) need "$1" "$#"; CLUES="$2"; rl_list_add PASS --clues; rl_list_add PASS "$2"; shift 2 ;;
		--labeled) rl_list_add PASS --labeled; shift ;;
		--expected-alt) need "$1" "$#"; rl_list_add PASS --expected-alt; rl_list_add PASS "$2"; shift 2 ;;
		--stdin) need "$1" "$#"; rl_list_add PASS --stdin; rl_list_add PASS "$2"; shift 2 ;;
		--survive) SURVIVE=1; rl_list_add PASS --survive; shift ;;
		# Kept out of $PASS: the code is compared by value below (--exit), and
		# it and the sentence behind it (--exit-quote) are forwarded as their
		# own quoted words.
		--exit) need "$1" "$#"; EXPECT_EXIT="$2"; shift 2 ;;
		--exit-source) need "$1" "$#"; EXIT_SOURCE="$2"; shift 2 ;;
		--exit-quote) need "$1" "$#"; EXIT_QUOTE="$2"; shift 2 ;;
		# The directories the fetched compiler's own shared objects live in.
		# A pinned clang that cannot find libclang-cpp does not fail: the loader
		# falls back to this machine's copy and the layer reports on a compiler
		# nobody pinned. Same flag, same reason, same shape as compile_check.sh.
		--cc-lib)
			need "$1" "$#"
			# Absolute: a relative entry in LD_LIBRARY_PATH resolves against the
			# process's cwd, which is not this script's to assume.
			case "$2" in
				/*) _d=$(dirname "$2") ;;
				*) _d=$(dirname "$PWD/$2") ;;
			esac
			CC_LIBS="${CC_LIBS:+$CC_LIBS:}$_d"
			shift 2 ;;
		--cc) need "$1" "$#"; CC="$2"; shift 2 ;;
		# The pinned ld.bfd and the libraries it loads: the test program is
		# LINKED here, and the clang package has no linker of its own, so
		# without these every link ran the box's /usr/bin/ld (TO VERIFY V38).
		# tools/runner_lib.sh's rl_ld_pin proves them, below.
		--ld) need "$1" "$#"; LD="$2"; shift 2 ;;
		--ld-lib) need "$1" "$#"; rl_list_add LD_LIBS "$2"; shift 2 ;;
		# The tests of this exercise that wait for this one, named under a
		# red verdict (rl_waiting). Not forwarded: this runner's own red, a
		# compile that failed, is one too.
		--waiting) need "$1" "$#"; WAITING="$2"; shift 2 ;;
		--) shift; break ;;
		*) echo "header_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$DIFFER" ] && [ -n "$MAIN" ] && { [ -n "$EXPECTED" ] || [ "$SURVIVE" -eq 1 ]; } || {
	echo "header_check.sh: need --differ, --hdr, --main and --expected (or --survive)" >&2
	exit 2
}
# The comparison, as diff_output.sh takes it: a survive case has no file.
# $PASS splits into its lines (THE LISTS, above).
rl_split_on
# shellcheck disable=SC2086
if [ -n "$EXPECTED" ]; then
	set -- --expected "$EXPECTED" $PASS -- "$@"
else
	set -- $PASS -- "$@"
fi
rl_split_off
# The header is the whole deliverable of the default shape, so leaving it out is
# a wiring error there. A libft bundle may turn in no header at all (c-09 ex00),
# and what it does turn in is its sources.
if [ "$SHAPE" = header ] && [ -z "$HDR" ]; then
	echo "header_check.sh: need --differ, --hdr, --main and --expected" >&2
	exit 2
fi
if [ "$SHAPE" = libft ] && [ -z "$SRCS" ]; then
	echo "header_check.sh: --shape libft needs at least one --src: the sources" >&2
	echo "                 ARE the deliverable, so without them nothing is tested." >&2
	exit 2
fi


# Each --cc-lib directory must EXIST. A moved or mistyped one is the quiet
# failure this arrangement is exposed to: the loader falls back to the default
# search path, finds the box's libraries, and the pinned compiler silently stops
# being pinned. Exit 2 -- the harness is misconfigured, the exercise is not
# wrong. Copied deliberately from compile_check.sh rather than abbreviated.
if [ -n "$CC_LIBS" ]; then
	_ifs=$IFS
	IFS=:
	for _d in $CC_LIBS; do
		[ -d "$_d" ] || {
			IFS=$_ifs
			echo "header_check.sh: --cc-lib directory '$_d' does not exist." >&2
			echo "  Without it the loader would fall back to this machine's own" >&2
			echo "  libraries and the pinned compiler would silently stop being" >&2
			echo "  pinned, so this refuses to run rather than pass." >&2
			exit 2
		}
	done
	IFS=$_ifs
	LD_LIBRARY_PATH="$CC_LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	export LD_LIBRARY_PATH
fi

# A COMPILER IS NOT OPTIONAL HERE. This layer compiles something and then reads
# the result, so without a compiler it has checked nothing -- and it used to say
# SKIP and exit 0, which is a PASS to Bazel.
#
# MEASURED, before the fetched clang was wired in above: with a PATH holding 580
# coreutils and no compiler, this family reported 116 forbidden + 102 symbols +
# 96 prototype + 7 header SKIPs and went green -- 321 targets, with forbidden
# and prototype at LEVEL 1, inside the submit gate. //c-piscine/c-piscine-rush-02:
# ex00_forbidden went FAIL -> PASS with them, hiding a real "CALLED BUT NOT
# AUTHORISED: printf".
#
# Now that --cc arrives from Bazel as a pinned, sha256-verified clang, an absent
# compiler is no longer a fact about the student's machine: it is a wiring
# error. Exit 2, the code this repo reserves for "the harness is broken, the
# exercise is not wrong" -- never exit 0.
command -v "$CC" > /dev/null 2>&1 || {
	echo "header_check: the compiler '$CC' is not executable." >&2
	echo "  This layer compiles before it inspects, so without one it would be" >&2
	echo "  reporting on nothing. Bazel passes the pinned clang through --cc;" >&2
	echo "  if that is missing the target's data is wrong, which is a harness" >&2
	echo "  fault and not a finding about this exercise." >&2
	exit 2
}

[ -z "$WAITING" ] || [ -f "$WAITING" ] || {
	echo "header_check.sh: no --waiting file at $WAITING" >&2
	exit 2
}
WORK=$(mktemp -d)
rl_traps 'rl_waiting $? "$WAITING"; rm -rf "$WORK"'

# THE LINKER, pinned like the compiler (tools/runner_lib.sh, rl_ld_pin): with
# --ld, every link here runs the fetched ld.bfd, proved before the first one.
# By hand, without it, the compiler links with whatever linker it finds.
RL_LDFLAG=""
[ -z "$LD" ] || rl_ld_pin "$CC" "$LD" "$LD_LIBS" "$WORK/ld"

rl_split_on
# shellcheck disable=SC2086 # the lists split into their lines (THE LISTS)
"$CC" ${RL_LDFLAG:+"$RL_LDFLAG"} -Wall -Wextra -Werror $INCS "$MAIN" $HSRCS $SRCS -o "$WORK/bin" 2> "$WORK/cc.err"
_cc_rc=$?
rl_split_off
if [ "$_cc_rc" -ne 0 ]; then
	if [ "$SHAPE" = libft ]; then
		echo "header_check: FAIL — the test program does not compile against what you turned in."
		echo ""
		echo "  The test program is the harness's file, not yours. It calls every"
		echo "  function this exercise bundles and reaches them only through what"
		echo "  you turned in: your sources, and your header where the subject asks"
		echo "  for one. So this is the exercise failing, not a broken test: every"
		echo "  diagnostic is something it looked for there and did not find, or"
		echo "  found with a different shape than the subject specifies."
	else
		echo "header_check: FAIL — the test program does not compile against your header."
		echo ""
		echo "  This exercise's deliverable IS the header, so this is the exercise"
		echo "  itself failing, not a broken test. The program below was written to"
		echo "  use everything the subject says your header must declare; every"
		echo "  diagnostic is something it asked for and did not find, or found with"
		echo "  a different shape than the subject specifies."
	fi
	echo ""
	echo "  ---------------- what the compiler said ----------------"
	rl_excerpt "$WORK/cc.err" 25 compiler-output.txt "  "
	# The clue file is the same TSV the output layer uses, read by the one
	# rule (rl_clues). No case failed here -- the program never built -- so
	# there is nothing to key a hint on, and the exercise's first ones show.
	rl_clues "$CLUES"
	exit 1
fi

# Say what the compile proved, in the voice of the failure above. On success
# this runner used to hand straight to diff_output.sh, and a header whose test
# program prints nothing (c-08 ex00 and ex03) showed an empty table with
# "PASS (0/0 passed)" -- a layer that looked as though it had checked nothing,
# when the compile against the header was the whole check.
if [ "$SHAPE" = libft ]; then
	echo "header_check: OK — the test program compiled against what you turned in,"
else
	echo "header_check: OK — the test program compiled against your header,"
fi
if [ "$SURVIVE" -eq 1 ]; then
	echo "              under -Wall -Wextra -Werror. How it ends is checked below."
else
	echo "              under -Wall -Wextra -Werror. What it printed is checked below."
fi

# --exit is FORWARDED, never reimplemented here.
#
# Why the flag exists at all: this runner's only verdict is what the program
# PRINTED. A header exercise can define a macro that a test main() *returns*
# rather than prints, and a returned value is invisible to a stdout diff — so a
# macro defined as anything at all is green here as long as the printing part of
# the fixture is right. --exit is what lets a fixture put such a macro somewhere
# the harness can see it, by making the value the program's exit status.
#
# Why forwarded: diff_output.sh is the process that actually RUNS the binary. It
# owns the ulimit/timeout wrapper, and the exit status only exists inside it —
# out here we would have to run the program a SECOND time to see one, which is a
# different execution with a possibly different result, and would leave two
# copies of the same comparison to drift apart in wording. Handing the flag
# down keeps one implementation and one message ("exited N, this case expects
# M", and whose rule M is), so the two layers cannot disagree about what an
# exit code means.
#
# Two consequences of that inherited from diff_output.sh, both intended:
#   - An EMPTY value asserts nothing, because its gate is [ -n "$EXPECT_EXIT" ]
#     and ours is the same test. --exit "" is a no-op in both layers, not an
#     assertion that the program exits with the empty string.
#   - The statuses diff_output.sh intercepts before its assertion — 153 (output
#     budget blown) and 137/124 (its inner timeout) — exit 1 from inside it with
#     their own explanation, so --exit cannot be used to EXPECT one of those.
#     A crash (>128) is likewise a failure on its own terms whatever is asserted.
# And one from us: the compile arm above runs first, so a program that does not
# build fails there and this layer never claims anything about its exit status.
#
# What this runner deliberately does NOT do is decide which code an exercise
# ought to assert. Nothing is checked unless a caller passes --exit. Where a
# subject does not state a value, picking one is a claim about the exercise's
# requirements — a decision for whoever wires the test and for the subject, not
# for the mechanism that measures it. The caller says which with --exit-source,
# and the Run contract (docs/reference.md) says where each may be checked: a
# status the subject names at basic, this repo's convention at robust. c_header
# enforces that at analysis.
if [ -n "$EXPECT_EXIT" ] && [ -n "$EXIT_QUOTE" ]; then
	sh "$DIFFER" --bin "$WORK/bin" --exit "$EXPECT_EXIT" \
		--exit-source "${EXIT_SOURCE:-subject}" --exit-quote "$EXIT_QUOTE" "$@"
elif [ -n "$EXPECT_EXIT" ]; then
	sh "$DIFFER" --bin "$WORK/bin" --exit "$EXPECT_EXIT" \
		--exit-source "${EXIT_SOURCE:-subject}" "$@"
else
	sh "$DIFFER" --bin "$WORK/bin" "$@"
fi
