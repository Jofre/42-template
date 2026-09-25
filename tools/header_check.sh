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
# c-09's libft bundles (c_libft, --shape libft) come through here for the same
# reason. ex01 turns in a header beside its sources, and a harness main() that
# reaches the five functions through it is a cc_binary that stops COMPILING the
# moment that header is reduced to its guards: -Werror turns every call into an
# implicit-declaration error, and `bazel test //...` died with "Build did NOT
# complete successfully" on a fresh clone. The template had to ship that header
# filled in to avoid it -- five prototypes that are c-08 ex00's whole answer --
# and tools/stub_check.sh carried an approval saying so. Compiled here, the same
# header is one red ex01_output with the compiler's diagnostics under it, and
# the approval is gone. In that shape the --src files are the DELIVERABLE (in
# c_header they are harness helpers), --hdr is optional (ex00 turns in no
# header) and may repeat, and the failure text says "what you turned in"
# instead of "your header".
#
# Usage:
#   header_check.sh --differ PATH --hdr FILE --main FILE [--src FILE]...
#                   --expected FILE [--clues FILE] [--labeled]
#                   [--shape header|libft] [--inc DIR]...
#                   [--exit CODE] [--cc NAME] [-- PROG ARGS...]
#
# Options:
#   --shape S     header (default): the header is the whole deliverable and
#                 --hdr is required. libft: the --src files and any --hdr are
#                 what the student turned in; see the paragraph above.
#   --inc DIR     one more include directory, for a deliverable whose sources
#                 #include from somewhere other than beside a --hdr.
#   --exit CODE   also assert the built program exits with CODE. Same flag,
#                 same wording and same semantics as tools/diff_output.sh's,
#                 because it IS diff_output.sh's — see the note above the
#                 delegation at the bottom of this file.
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
require cut dirname grep head mktemp rm sed

DIFFER=""
HDR=""
MAIN=""
SRCS=""
INCS=""
EXPECTED=""
CLUES=""
PASS=""
EXPECT_EXIT=""
SHAPE="header"
CC="${HEADER_CC:-cc}"
CC_LIBS=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "header_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--differ) need "$1" "$#"; DIFFER="$2"; shift 2 ;;
		--hdr) need "$1" "$#"; HDR="$2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--main) need "$1" "$#"; MAIN="$2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--src) need "$1" "$#"; SRCS="$SRCS $2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--inc) need "$1" "$#"; INCS="$INCS -I$2"; shift 2 ;;
		--shape)
			need "$1" "$#"
			case "$2" in
				header | libft) SHAPE="$2" ;;
				*) echo "header_check.sh: --shape must be header or libft, not '$2'" >&2
				   exit 2 ;;
			esac
			shift 2 ;;
		--expected) need "$1" "$#"; EXPECTED="$2"; shift 2 ;;
		--clues) need "$1" "$#"; CLUES="$2"; PASS="$PASS --clues $2"; shift 2 ;;
		--labeled) PASS="$PASS --labeled"; shift ;;
		# Kept OUT of $PASS on purpose: $PASS is expanded unquoted (it has to
		# be, to split into separate words), so a value carrying a space or a
		# glob character would be re-split or filename-expanded on its way
		# through. A code is forwarded as its own quoted word instead, so what
		# diff_output.sh receives is byte-for-byte what we received.
		--exit) need "$1" "$#"; EXPECT_EXIT="$2"; shift 2 ;;
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
		--) shift; break ;;
		*) echo "header_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$DIFFER" ] && [ -n "$MAIN" ] && [ -n "$EXPECTED" ] || {
	echo "header_check.sh: need --differ, --hdr, --main and --expected" >&2
	exit 2
}
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

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# shellcheck disable=SC2086
if ! "$CC" -Wall -Wextra -Werror $INCS "$MAIN" $SRCS -o "$WORK/bin" 2> "$WORK/cc.err"; then
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
	sed -n '1,25p' "$WORK/cc.err" | sed 's/^/  /'
	if [ -n "$CLUES" ] && [ -f "$CLUES" ]; then
		echo "  ---------------- hint ----------------"
		# The clue file is the same TSV the output layer uses; show the hint
		# column only, since there is no per-case table to attach hints to yet.
		cut -f1 "$CLUES" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' \
			| head -3 | sed 's/^/   * /'
	fi
	exit 1
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
# down keeps one implementation and one message ("exit code N, expected M"), so
# the two layers cannot disagree about what an exit code means.
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
# for the mechanism that measures it.
# shellcheck disable=SC2086
if [ -n "$EXPECT_EXIT" ]; then
	sh "$DIFFER" --bin "$WORK/bin" --expected "$EXPECTED" $PASS \
		--exit "$EXPECT_EXIT" -- "$@"
else
	sh "$DIFFER" --bin "$WORK/bin" --expected "$EXPECTED" $PASS -- "$@"
fi
