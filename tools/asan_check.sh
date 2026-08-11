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
#   asan_check.sh --probe <probe.c> --src <student.c> [--src ...] \
#                 [--hdr FILE]... [--inc DIR]... [--note TEXT]
#   --hdr  a header the probe/source need (e.g. ft_stock_str.h); not compiled,
#          its directory is added to -I (mirrors compile_check.sh).
#   --note one line of exercise-specific explanation, printed in place of the
#          generic one when the probe trips. Only for exercises whose fault
#          really does have a single shape — see the failure block at the
#          bottom for why the generic wording has to stay generic.

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

CC="${MEM_CC:-clang-12}"
SRCS=""
INCS=""
NOTE=""
PROBE_SRC=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "asan_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--probe) need "$1" "$#"; SRCS="$SRCS $2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--src)   need "$1" "$#"; SRCS="$SRCS $2"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--hdr)   need "$1" "$#"; INCS="$INCS -I$(dirname "$2")"; shift 2 ;;
		--inc)   need "$1" "$#"; INCS="$INCS -I$2"; shift 2 ;;
		--note)  need "$1" "$#"; NOTE="$2"; shift 2 ;;
		--probe-src) need "$1" "$#"; PROBE_SRC="$2"; shift 2 ;;
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

# This is the layer that catches what stdout-diffing structurally cannot: an
# out-of-bounds access that still returns the right value. A silent green when
# the toolchain is missing is therefore the most expensive default available —
# it removes the only check for that bug class without saying so. Try every
# plausible ASan-capable compiler before giving up, and when none works, say it
# loudly. Set MEM_CC to pin one.
if ! command -v "$CC" >/dev/null 2>&1; then
	for alt in clang-12 clang gcc-10 gcc cc; do
		if command -v "$alt" >/dev/null 2>&1; then
			CC="$alt"
			break
		fi
	done
fi

command -v "$CC" >/dev/null 2>&1 || {
	# NO_SKIP=1: an absent toolchain is a failure, not a quiet pass.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no compiler, and this layer must not report a silent pass."
		exit 1
	}
	echo "asan_check: SKIP — no ASan-capable compiler found (tried MEM_CC,"
	echo "            clang-12, clang, gcc-10, gcc, cc)."
	echo "            WARNING: the memory-safety layer did NOT run. An"
	echo "            out-of-bounds access that returns the correct value is"
	echo "            invisible to every other layer, so this is a real gap,"
	echo "            not a pass. Rebuild the devcontainer to restore it."
	exit 0
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

if ! "$CC" -Wall -Wextra -Werror -g -fno-omit-frame-pointer \
		-fsanitize=address,undefined -fno-sanitize-recover=all \
		$INCS $SRCS -o "$WORK/probe" 2> "$WORK/cc.err"; then
	echo "asan_check: compile FAILED"
	sed -n '1,30p' "$WORK/cc.err"
	exit 1
fi

# detect_leaks=0 deliberately: a leak is the valgrind layer's finding, and
# letting LeakSanitizer abort here would red THIS layer with an
# "out-of-bounds" headline for what is actually a missing free. Matches
# rust_diff.sh, which sets the same pair for the crash-fuzz build.
# The caller's keys go LAST so they win, which is what docs/reference.md
# promises of ASAN_OPTIONS and UBSAN_OPTIONS ("appended after the harness's own,
# so your key wins"). asan_run.sh and rust_diff.sh already did this; these two
# overwrote instead, so anyone setting a key to debug the layer that IS the asan
# layer had it silently discarded.
if ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:${ASAN_OPTIONS:-}" \
		UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1:${UBSAN_OPTIONS:-}" \
		"$WORK/probe" > "$WORK/out" 2>&1; then
	echo "asan_check: PASS — no out-of-bounds access or UB on the probed inputs"
	exit 0
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
	sed -n '1,20p' "$PROBE_SRC" |
		sed -n '/^\/\*/,/\*\//p' |
		sed 's|^/\*[[:space:]]*||; s|^[[:space:]]*\*[[:space:]]\{0,1\}||; s|[[:space:]]*\*/[[:space:]]*$||' |
		grep -v '^[[:space:]]*$' | sed 's/^/            /'
else
	# The closing sentence used to promise the report names "which line of your
	# file". It does not, and in this container it cannot: the image installs
	# clang-12 but no llvm-12, so there is no llvm-symbolizer on PATH and ASan
	# prints every frame as a bare "#0 0x4cb412 (probe+0x4cb412)". Sending a
	# student to look for a line number that was never printed is the same
	# defect as the n/size claim this block replaced, one sentence further
	# down. What the report always carries, symbolizer or not, is the kind and
	# width of the access and its offset from the block it ran off.
	echo "            It touched memory outside a buffer this probe owns. The"
	echo "            probe hands it blocks sized to fit EXACTLY, with nothing"
	echo "            valid on either side, precisely so that a single step past"
	echo "            what it was given lands in a sanitizer redzone instead of"
	echo "            on some harmless neighbouring byte that would have let the"
	echo "            bug through. The report below says which access did it —"
	echo "            READ or WRITE, and of how many bytes — and how far outside"
	echo "            which block it landed."
fi
echo "---------------- sanitizer report (first lines) ----------------"
sed -n '1,35p' "$WORK/out"
exit 1
