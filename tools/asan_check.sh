#!/bin/sh
# Compile the student's function together with a memory-safety probe under
# AddressSanitizer + UBSan and RUN it. A correct function only ever touches the
# memory it was given; a buggy one reads or writes outside it and the sanitizer
# aborts — so this test fails and prints the report.
#
# This catches the class of bug that returns the CORRECT VALUE via a stray
# out-of-bounds read (e.g. an n-bounded compare whose bound check comes after
# the dereference, or a size-bounded scan that isn't capped) — which pure
# stdout-diffing can never see, because the value is right.
#
# Usage:
#   asan_check.sh --cc PATH [--cc-lib FILE]... [--cc-under FILE] \
#                 --ld PATH --ld-lib FILE... \
#                 --probe <probe.c> --src <student.c> [--src ...] \
#                 [--hdr FILE]... [--inc DIR]... [--lib FILE]... [--note TEXT]
#                 [--symbolizer PATH --symbolizer-lib PATH]
#   --cc   the pinned clang-12 Bazel fetched, with each library it loads
#          (--cc-lib) and a file of its own tree (--cc-under): proved by
#          rl_cc_pin before the first compile (tools/runner_lib.sh).
#   --ld   the pinned ld.bfd, with each library it loads (--ld-lib): the
#          probe is linked with it, proved by rl_ld_pin. Both are required:
#          this layer compiles under -Werror, and another compiler's warnings
#          made the same code red on one machine and green on campus (TO
#          VERIFY V38).
#   --hdr  a header the probe/source need (e.g. ft_stock_str.h); not compiled,
#          its directory is added to -I (mirrors compile_check.sh).
#   --lib  an archive the GRADER links (tools/grader_lib.bzl: C 12's own
#          ft_create_elem), linked after the sources; itself uninstrumented,
#          and its malloc is the sanitizer's like every other.
#   --note one line of exercise-specific explanation, printed in place of the
#          generic one when the probe trips. Only for exercises whose fault
#          really does have a single shape — see the failure block at the
#          bottom for why the generic wording has to stay generic.
#   --symbolizer  the pinned llvm-symbolizer, and --symbolizer-lib a library
#          file beside the libLLVM it loads, so each frame of the report names
#          a function, a file and a line (tools/runner_lib.sh, rl_sanitizers).

set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "asan_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require dirname grep mktemp rm sed

# The shared runner helpers -- time budget, exiting signal traps, how a run
# ended, excerpts, hints -- written once in tools/runner_lib.sh.
RL_NAME=asan_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "asan_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool CC -- the pinned compiler: it builds, and runs none of what it builds

CC=""
CC_LIBS=""
CC_UNDER=""
LD=""
LD_LIBS=""
SRCS=""
INCS=""
LIBS=""
NOTE=""
PROBE_SRC=""
SYMBOLIZER=""
SYMBOLIZER_LIB=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "asan_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--probe) need "$1" "$#"; rl_list_add SRCS "$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--src)   need "$1" "$#"; rl_list_add SRCS "$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--lib)   need "$1" "$#"; rl_list_add LIBS "$2"; shift 2 ;;
		--hdr)   need "$1" "$#"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--inc)   need "$1" "$#"; rl_list_add INCS "-I$2"; shift 2 ;;
		--note)  need "$1" "$#"; NOTE="$2"; shift 2 ;;
		--probe-src) need "$1" "$#"; PROBE_SRC="$2"; shift 2 ;;
		--symbolizer) need "$1" "$#"; SYMBOLIZER="$2"; shift 2 ;;
		--symbolizer-lib) need "$1" "$#"; SYMBOLIZER_LIB="$2"; shift 2 ;;
		--cc) need "$1" "$#"; CC="$2"; shift 2 ;;
		--cc-lib) need "$1" "$#"; rl_list_add CC_LIBS "$2"; shift 2 ;;
		--cc-under) need "$1" "$#"; CC_UNDER="$2"; shift 2 ;;
		--ld) need "$1" "$#"; LD="$2"; shift 2 ;;
		--ld-lib) need "$1" "$#"; rl_list_add LD_LIBS "$2"; shift 2 ;;
		*) echo "asan_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

# A dropped or misspelled flag must not read as a student verdict. Without this,
# a missing --probe leaves SRCS empty, the compile fails on "no input files", and
# the layer reports "compile FAILED" -- which a student reads as "my code does
# not build" when the mistake is in the BUILD file. Exit 2 says harness error;
# exit 1 is reserved for "the code under test is wrong".
if [ -z "$SRCS" ]; then
	echo "asan_check.sh: at least one --probe or --src is required" >&2
	exit 2
fi

# THE PINNED COMPILER AND LINKER, never the box's. This is the layer that
# catches what stdout-diffing structurally cannot -- an out-of-bounds access
# that still returns the right value -- and it compiles under -Wall -Wextra
# -Werror, so the compiler is part of its verdict: it used to take the first
# of clang-12, clang, gcc-10, gcc and cc on PATH, and a variable set and
# never read is accepted by clang-12 and refused by gcc-10 (TO VERIFY V38,
# reproduced). Bazel hands over the campus's clang-12 and binutils 2.38, as
# it does to every other layer that compiles, and tools/defs.bzl refuses a
# test of this runner that hands over neither (pinned_cc_problem). A missing
# one is the harness's fault, so exit 2 -- never a SKIP, which would read as
# a pass of the one layer that sees this bug class.
[ -n "$CC" ] || { echo "asan_check.sh: --cc is required (the pinned clang-12)" >&2; exit 2; }
[ -n "$LD" ] || { echo "asan_check.sh: --ld is required (the pinned ld.bfd)" >&2; exit 2; }
rl_cc_pin "$CC" "$CC_LIBS" "$CC_UNDER"

WORK=$(mktemp -d)
rl_traps 'rm -rf "$WORK"'

# The sanitizers' options -- detect_leaks=0 among them, because a leak is the
# valgrind layer's finding -- and the pinned symbolizer, set once for every
# sanitizer runner by rl_sanitizers (tools/runner_lib.sh), the caller's own
# keys last so they win. Set before the linker's proof, which runs a
# sanitized program of its own.
rl_sanitizers "$WORK/sym" "$SYMBOLIZER" "$SYMBOLIZER_LIB"
rl_ld_pin "$CC" "$LD" "$LD_LIBS" "$WORK/ld" -fsanitize=address,undefined

# The lists are one word per line (runner_lib.sh, LISTS OF WORDS).
rl_split_on
# shellcheck disable=SC2086
"$CC" "$RL_LDFLAG" -Wall -Wextra -Werror -g -fno-omit-frame-pointer \
	-fsanitize=address,undefined -fno-sanitize-recover=all \
	$INCS $SRCS $LIBS -o "$WORK/probe" 2> "$WORK/cc.err"
_cc_rc=$?
rl_split_off
if [ "$_cc_rc" -ne 0 ]; then
	echo "asan_check: compile FAILED"
	rl_excerpt "$WORK/cc.err" 30 compiler-output.txt ""
	exit 1
fi

# The probe calls the student's function, so it runs under the time budget like
# every other run of student code (rl_tmo): 30s, or what is left of the test's
# own limit. A function that never returns on a probed input is named as that,
# not as an out-of-bounds access.
if ! rl_tmo 30; then
	rl_overrun "the probe"
	exit 1
fi
rl_run "$WORK/probe" > "$WORK/out" 2>&1
PRC=$?
rl_classify "$PRC"
if [ "$RL_CAUSE" = ok ]; then
	echo "asan_check: PASS — no out-of-bounds access or UB on the probed inputs"
	exit 0
fi
if [ "$RL_CAUSE" = timeout ]; then
	rl_overrun "the probe"
	exit 1
fi
if [ "$RL_CAUSE" = noexec ]; then
	echo "asan_check.sh: the probe $RL_WHY" >&2
	exit 2
fi

# HOW IT ENDED, asked of the sanitizers' report (rl_sanitized, V50). Every
# ending but OK, a timeout and noexec used to read "the function accessed
# memory out of bounds", above a report that was not there (V70). With no
# report, the header says how the probe ended and that neither sanitizer
# reported anything, and shows what the probe printed. It is a red, not the
# harness's exit 2: the probes' own NULL checks (C 07 ex00's mem_strdup.c,
# C 12 ex15's exit(2)) cannot be what ended it, because under the sanitizer a
# failed malloc stops the run with a report and never returns NULL. So what
# ends a run this way is the code the probe called: an exit, an abort, or a
# signal raised with no report.
if ! rl_sanitized "$WORK/out"; then
	echo "asan_check: FAIL — the probe $RL_WHY, and neither sanitizer reported anything:"
	echo "            no out-of-bounds access or undefined behaviour was seen. Under"
	echo "            the sanitizer the probe's own allocations cannot fail quietly, so"
	echo "            the code it called most likely ended the run itself: a call to"
	echo "            exit or abort, or a signal it raised."
	if [ -s "$WORK/out" ]; then
		echo "---------------- what the probe printed ----------------"
		rl_excerpt "$WORK/out" 20 probe-output.txt ""
	else
		echo "            It printed nothing."
	fi
	exit 1
fi

# The second line used to state, for EVERY probe in the repo, that the function
# "reads/writes past its n/size bound on a non-NUL-terminated input". That is a
# precise diagnosis for the c-02/c-03 string family and a false one everywhere
# else: c-00 ex06 probes ft_print_comb2(void), whose own probe comment says
# "There is no n/size parameter to bound"; c-01 ex07 probes an int array where
# nothing is NUL-terminated in the first place; c-07 ex00's probe names the
# likely fault as "its own malloc is one byte short". A confidently wrong
# diagnosis costs more than a thin one — it sends a student looking for a bound
# that does not exist while the actual fault is named in the report printed
# directly below it. So the default now says only what holds for EVERY probe
# this layer runs, and an exercise whose fault really is n/size-shaped supplies
# its own sentence with --note.
echo "asan_check: FAIL — the function accessed memory out of bounds (or hit UB)."
if [ -n "$NOTE" ]; then
	echo "            $NOTE"
elif [ -n "$PROBE_SRC" ] && [ -f "$PROBE_SRC" ]; then
	# The probe's OWN header comment, rather than a sentence written twice.
	#
	# Every probe opens by saying what it does and what an off-by-one would look
	# like -- "the dest below is a HEAP buffer of EXACTLY strlen(src) + 1 bytes,
	# so a correct strcpy fills dest[0..len] and stops" -- written beside the
	# allocation it describes, and read until now by nobody but a maintainer.
	# That is more use than any generic sentence, and reusing it means the
	# explanation cannot drift from the probe: they are the same lines.
	#
	# --note still wins where a caller wants something else, but no caller has
	# ever needed to: the comment is already the accurate, non-leaking wording.
	# conventions: not-an-excerpt -- the probe's header comment, not output.
	sed -n '1,20p' "$PROBE_SRC" |
		sed -n '/^\/\*/,/\*\//p' |
		sed 's|^/\*[[:space:]]*||; s|^[[:space:]]*\*[[:space:]]\{0,1\}||; s|[[:space:]]*\*/[[:space:]]*$||' |
		grep -v '^[[:space:]]*$' | sed 's/^/            /'
else
	# What the report always carries, symbolizer or not, is the kind and width
	# of the access and its offset from the block it ran off -- so that is what
	# this sentence promises. A file and a line are there only when the pinned
	# symbolizer was handed over (--symbolizer), which is said below the
	# report rather than promised above it.
	echo "            It touched memory outside a buffer this probe owns. The"
	echo "            probe hands it blocks sized to fit EXACTLY, with nothing"
	echo "            valid on either side, precisely so that a single step past"
	echo "            what it was given lands in a sanitizer redzone instead of"
	echo "            on some harmless neighbouring byte that would have let the"
	echo "            bug through. The report below says which access did it —"
	echo "            READ or WRITE, and of how many bytes — and how far outside"
	echo "            which block it landed."
fi
echo "---------------- sanitizer report ----------------"
rl_sanitizer_report "$WORK/out" 35 sanitizer-report.txt ""
if [ -n "$SYMBOLIZER" ]; then
	echo "The top frame is where the access happened; a frame in your file names"
	echo "its line."
fi
exit 1
