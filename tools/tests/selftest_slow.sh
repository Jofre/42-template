#!/bin/sh
# selftest_slow.sh — the same question as selftest.sh, for the runners that are
# too expensive to ask it of on every build.
#
# WHY IT IS SEPARATE.
# selftest.sh is size = "small" and finishes in seconds, which is what makes it
# something you run constantly. The runners here need valgrind (20-50x slower
# than native, by design) or a Rust oracle build, and folding them into that
# target would turn a two-second check into a minute-long one — at which point
# people stop running it, and a self-test nobody runs protects nothing.
#
# WHY valgrind_test.sh IS THE ONE THAT MATTERED MOST.
# It is the least redundant layer in the suite: the ONLY one that can see a
# leak. rust_diff.sh and asan_run.sh both set detect_leaks=0 deliberately
# (valgrind_test.sh's own header says why), so if valgrind ever rewords its
# findings and this runner's ERR_RE stops matching, ~60 _valgrind targets report
# clean forever and nothing else in the repo notices. That regex is a string
# match against another project's output; it is exactly the kind of thing that
# breaks silently on an upgrade, which is what a self-test is for.
#
# Usage:
#   selftest_slow.sh --anchor PATH-TO-ANY-TOOLS-SCRIPT
#
# The anchor is a file rather than a directory, for the same reason as in
# selftest.sh: $(rootpath) on a filegroup member resolves to the FILE.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "selftest_slow.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk basename cat chmod cp dirname env fold grep ln mkdir mktemp rm sed

ANCHOR=""
PERF_RUN=""
VALGRIND=""
VGTOOLS=""
VGCGTOOLS=""
CG_ANNOTATE=""
ZIG=""
PCC=""
PCC_LIBS=""
PCC_LIB_FILES=""
LD=""
LD_LIB=""
ORACLE=""
REDIRECT_LIB=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "selftest_slow.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--anchor) need "$1" "$#"; ANCHOR="$2"; shift 2 ;;
		# The PINNED valgrind, handed down to every arm below. These arms exist
		# to prove the leak layer still detects a leak, so they have to exercise
		# the same binary the layer grades with -- checking one valgrind while
		# the suite runs another would make this file agree with nothing.
		--valgrind) need "$1" "$#"; VALGRIND="$2"; shift 2 ;;
		--valgrind-tools) need "$1" "$#"; VGTOOLS="$2"; shift 2 ;;
		--valgrind-callgrind-tools) need "$1" "$#"; VGCGTOOLS="$2"; shift 2 ;;
		--callgrind-annotate) need "$1" "$#"; CG_ANNOTATE="$2"; shift 2 ;;
		# //tools:perf_run is a cc_binary, so like norminette in the fast
		# selftest it lands elsewhere in runfiles and cannot be derived from
		# the anchor.
		--perf-run) need "$1" "$#"; PERF_RUN="$2"; shift 2 ;;
		# The pinned 32-bit compiler, for the ilp32 arms below.
		--zig) need "$1" "$#"; ZIG="$2"; shift 2 ;;
		# The pinned 64-bit clang and each library it loads, for every
		# program the arms build ($CC, below) and the cycles arms' -O2 build.
		--cc) need "$1" "$#"; PCC="$2"; shift 2 ;;
		--cc-lib)
			need "$1" "$#"
			PCC_LIBS="$PCC_LIBS --cc-lib $2"
			PCC_LIB_FILES="${PCC_LIB_FILES:+$PCC_LIB_FILES
}$2"
			shift 2 ;;
		# The pinned ld.bfd and a library beside the libbfd it loads:
		# cycles_check.sh links its -O2 build with them (rl_ld_pin, TO
		# VERIFY V38), as Bazel hands them over.
		--ld) need "$1" "$#"; LD="$2"; shift 2 ;;
		--ld-lib) need "$1" "$#"; LD_LIB="$2"; shift 2 ;;
		# //oracle's Rust binary and the preload library, for the Shell 01
		# check scripts' arms below: each is a build of its own, which is
		# what puts those arms here rather than in the fast selftest.
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--redirect-lib) need "$1" "$#"; REDIRECT_LIB="$2"; shift 2 ;;
		*) echo "selftest_slow.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$ANCHOR" ] || { echo "selftest_slow.sh: --anchor is required" >&2; exit 2; }
[ -f "$ANCHOR" ] || { echo "selftest_slow.sh: anchor $ANCHOR does not exist" >&2; exit 2; }
TOOLS=$(dirname "$ANCHOR")
# The stand-in contract (standin_is), for the ilp32 arms' gates.
# shellcheck source=tools/standin.sh
. "$TOOLS/standin.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

PASS=0
FAIL=0

# Same contract as selftest.sh: want_red passes ONLY on exit 1. 2 means the
# harness broke and NOTHING was checked, which must never be mistaken for a
# detection -- that is the same false-green shape these files exist to hunt, one
# level up.
want_red() {
	_name="$1"; shift; [ "$1" = "--" ] && shift
	"$@" > /dev/null 2>&1
	_rc=$?
	case "$_rc" in
		1)
			printf '  %-52s %s\n' "$_name" "ok (red, as required)"
			PASS=$((PASS + 1)) ;;
		0)
			printf '  %-52s %s\n' "$_name" "FAIL < (passed; it must not)"
			FAIL=$((FAIL + 1)) ;;
		*)
			printf '  %-52s %s\n' "$_name" \
				"FAIL < (exit $_rc = harness error; nothing was checked)"
			FAIL=$((FAIL + 1)) ;;
	esac
}
# Same as selftest.sh's: exit 2 AND a message that says which wiring is wrong.
# Kept separate from want_red because 2 and 1 mean different things here -- 1 is
# a finding in the code under test, 2 is that nothing was measured.
want_broken() {
	_name="$1"; _pat="$2"; shift 2; [ "$1" = "--" ] && shift
	_out=$("$@" 2>&1)
	_rc=$?
	if [ "$_rc" -ne 2 ]; then
		printf '  %-52s %s\n' "$_name" "FAIL < (exit $_rc; it must refuse with 2)"
		FAIL=$((FAIL + 1))
	elif printf '%s' "$_out" | grep -qF -- "$_pat"; then
		printf '  %-52s %s\n' "$_name" "ok (refused, and said why)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_name" "FAIL < (refused without saying '$_pat')"
		FAIL=$((FAIL + 1))
	fi
}
want_green() {
	_name="$1"; shift; [ "$1" = "--" ] && shift
	if "$@" > /dev/null 2>&1; then
		printf '  %-52s %s\n' "$_name" "ok (green, as required)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_name" "FAIL < (red; it must not be)"
		FAIL=$((FAIL + 1))
	fi
}
# selftest.sh's want_out and want_broken_none, for a report whose WORDS are the
# finding: the run must have run (exit 0 or 1, never 2), and its output must
# contain -- or must not contain -- the text. A footer that names a cause is
# only right if it is also absent where that cause is not.
want_out() {
	_name="$1"; _pat="$2"; shift 2; [ "$1" = "--" ] && shift
	_out=$("$@" 2>&1)
	_rc=$?
	if [ "$_rc" -ge 2 ]; then
		printf '  %-52s %s\n' "$_name" \
			"FAIL < (exit $_rc = harness error; nothing was checked)"
		FAIL=$((FAIL + 1))
	elif printf '%s' "$_out" | grep -qF -- "$_pat"; then
		printf '  %-52s %s\n' "$_name" "ok (explained itself)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_name" "FAIL < (never said '$_pat')"
		FAIL=$((FAIL + 1))
	fi
}
want_none() {
	_name="$1"; _pat="$2"; shift 2; [ "$1" = "--" ] && shift
	_out=$("$@" 2>&1)
	_rc=$?
	if [ "$_rc" -ge 2 ]; then
		printf '  %-52s %s\n' "$_name" \
			"FAIL < (exit $_rc = harness error; nothing was checked)"
		FAIL=$((FAIL + 1))
	elif printf '%s' "$_out" | grep -qF -- "$_pat"; then
		printf '  %-52s %s\n' "$_name" "FAIL < (said '$_pat'; it must not)"
		FAIL=$((FAIL + 1))
	else
		printf '  %-52s %s\n' "$_name" "ok (stayed quiet, as required)"
		PASS=$((PASS + 1))
	fi
}

# WHICH SHELL INTERPRETS THE RUNNERS.
#
# Every arm below launches a runner through "$SH" rather than a literal `sh`,
# so the whole file can be replayed under a different shell. That is the point:
# this repo does NOT pin /bin/sh, and the reason it does not need to is that the
# runners are shell-agnostic -- which is a claim, and a claim about behaviour
# has to be executed rather than asserted.
#
# A comment must not START with the word shellcheck -- that is how a directive
# is spelled, and the linter then fails to parse this paragraph. Said the other
# way round: static linting already refuses a bashism (SC3xxx, at warning level,
# in //tools:conventions). This is the other half: dash and bash disagree about
# things no linter reads, `echo` with escapes being the classic one, and the
# only way to know is to run everything twice.
#
# //tools/tests:selftest_bash is the second run. If the shell named here is not
# installed, that is a SKIP rather than a pass -- see the guard below.
SH=${SELFTEST_SH:-sh}
if [ "$SH" != "sh" ] && ! command -v "$SH" > /dev/null 2>&1; then
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "selftest: SELFTEST_SH=$SH is not installed and NO_SKIP=1 is set," >&2
		echo "          so nothing was checked under it." >&2
		exit 2
	}
	echo "selftest: SKIP — SELFTEST_SH=$SH is not installed on this machine."
	exit 0
fi

# THE COMPILER EVERY FIXTURE HERE IS BUILT WITH, as in selftest.sh: the
# pinned clang-12 linking with the pinned ld.bfd, proved by the runners' own
# helpers and made one command by rl_cc_wrap (tools/runner_lib.sh). It was
# `cc` from PATH (SELFTEST_CC's default) -- the only arms in the repo that
# prove the valgrind layer can still SEE a leak were built by whatever this
# machine's compiler made of them, and a box without one skipped them all
# (TO VERIFY V28). A pair that fails a proof is exit 2: nothing was checked.
[ -n "$PCC" ] && [ -n "$LD" ] && [ -n "$LD_LIB" ] || {
	echo "selftest_slow: --cc, --ld and --ld-lib are required (the pinned clang-12 and ld.bfd)" >&2
	exit 2
}
mkdir -p "$WORK/pcc" || exit 2
# shellcheck disable=SC2016 # the script is for the inner shell to expand
"$SH" -c 'RL_NAME=selftest_slow; . "$1"; rl_cc_pin "$2" "$3" "$2"; rl_ld_pin "$2" "$4" "$5" "$6"; rl_cc_wrap "$2" "$3" "$6" "$7"' \
	_ "$TOOLS/runner_lib.sh" "$PCC" "$PCC_LIB_FILES" "$LD" "$LD_LIB" "$WORK/pcc/ld" "$WORK/pcc/cc" \
	> "$WORK/pcc.err" 2>&1 || {
	echo "selftest_slow: the pinned clang-12 and ld.bfd failed the runners' own proofs:" >&2
	cat "$WORK/pcc.err" >&2
	exit 2
}
CC="$WORK/pcc/cc"
# A hard error rather than a skip, for the same reason it is one in the layer:
# a skip here is indistinguishable from "the leak layer is fine".
[ -n "$VALGRIND" ] && [ -x "$VALGRIND" ] || {
	echo "selftest_slow: --valgrind is required (the pinned valgrind.bin)" >&2
	exit 2
}
VG_PASS="--valgrind $VALGRIND --valgrind-tools $VGTOOLS"
CG_PASS="--valgrind $VALGRIND --valgrind-tools $VGCGTOOLS --callgrind-annotate $CG_ANNOTATE"
# And the pinned build every --harness arm's -O2 binary is made with, as
# tools/defs.bzl hands it over (_pinned_build_args): cycles_check.sh refuses
# to build without it, where it used to take the box's `cc` (TO VERIFY V38).
CG_PASS="$CG_PASS --cc $PCC$PCC_LIBS --cc-under $PCC --ld $LD --ld-lib $LD_LIB"

printf 'selftest_slow: does each expensive layer still detect what it exists to detect?\n\n'

# ---------------------------------------------------------------- valgrind
printf '#include <stdlib.h>\nint main(void){void*p=malloc(64);free(p);return (0);}\n' \
	> "$WORK/vg_clean.c"
printf '#include <stdlib.h>\nint main(void){malloc(64);return (0);}\n' \
	> "$WORK/vg_leak.c"
# Reads one byte past a heap block: "Invalid read of size 1". A DIFFERENT arm of
# ERR_RE from the leak cases, so an upgrade that broke only one of the two
# families would still be caught.
printf '#include <stdlib.h>\nint main(void){char*p=malloc(4);char c=p[4];free(p);return (c==0);}\n' \
	> "$WORK/vg_oob.c"
# Uses a heap byte that was never written: "uninitialised value".
printf '#include <stdlib.h>\nint main(void){char*p=malloc(4);int r=0;if(p[0])r=1;free(p);return (r&0);}\n' \
	> "$WORK/vg_uninit.c"
# DESCRIPTORS. vg_fdleak opens a file and returns without closing it; vg_fdok
# closes it. vg_clean above opens NOTHING, which is the third case and the one
# that matters most -- see the arms below.
printf '#include <fcntl.h>\n#include <unistd.h>\nint main(void){int f=open("/etc/hostname",O_RDONLY);char b[4];if(read(f,b,4)<0)return(1);return (0);}\n' \
	> "$WORK/vg_fdleak.c"
printf '#include <fcntl.h>\n#include <unistd.h>\nint main(void){int f=open("/etc/hostname",O_RDONLY);char b[4];if(read(f,b,4)<0)return(1);close(f);return (0);}\n' \
	> "$WORK/vg_fdok.c"
# The SAME leak, over a program that also chooses a non-zero exit status. That
# is a second code path in the runner -- valgrind found nothing, so the child's
# own status carries it there -- and the gate on that path used to read
# VALGRIND_FDS = "strict", a value nothing in this tree sets. The report said
# "This is a FAILURE" and the layer exited 0.
printf '#include <fcntl.h>\n#include <unistd.h>\nint main(void){int f=open("/etc/hostname",O_RDONLY);char b[4];if(read(f,b,4)<0)return(1);return (3);}\n' \
	> "$WORK/vg_fdleak_rc.c"

# A write one past a local array that stays inside the stack: memory memcheck
# holds addressable, so it reports nothing. The arm below is about what the OK
# line claims, not about catching this: the ASan layers do. No loop the write
# could restart, and no stack protector whose canary it could hit (the array
# is the only thing the write touches, whatever the compiler puts beside it).
printf 'int main(void){volatile char a[8];volatile int k=8;volatile char pad[16];pad[0]=0;a[k]=1;return (pad[0]&0);}\n' \
	> "$WORK/vg_stack.c"
"$CC" -w -g -O0 -fno-stack-protector -o "$WORK/vg_stack" "$WORK/vg_stack.c" 2> /dev/null

for _p in vg_clean vg_leak vg_oob vg_uninit vg_fdleak vg_fdok vg_fdleak_rc; do
	"$CC" -w -g -O0 -o "$WORK/$_p" "$WORK/$_p.c" 2> /dev/null
done

# IS IT ACTUALLY THE PINNED ONE? The failure this guards against is the one
# that has caught every fetched tool in this repo at least once: a binary that
# cannot find part of its own tree does not necessarily fail -- it falls back to
# the box's copy, reports the pinned version, and goes green. Nothing in the
# output distinguishes the two.
#
# So: run the layer with a PATH that holds no valgrind at all. If it still
# detects the leak, the detection cannot have come from the host.
mkdir -p "$WORK/novg_path"
# The list must hold everything valgrind_test.sh DECLARES, minus the one tool
# this arm is deliberately hiding. A runner that requires a tool the fixture
# PATH withholds exits 2, and want_red reports that as "nothing was checked" --
# an arm failing for a reason that has nothing to do with what it tests.
# valgrind_test.sh sources tools/runner_lib.sh, which probes cat, chmod, cp,
# date, grep, mkdir and od itself.
for _t in sh "$SH" awk basename cat chmod cp date fold grep head mkdir mktemp od rm sed dirname readlink; do
	ln -sf "$(command -v "$_t")" "$WORK/novg_path/$_t" 2> /dev/null
done
want_red "valgrind: the leak is found with NO valgrind on PATH" -- \
	env PATH="$WORK/novg_path" "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS \
		--bin "$WORK/vg_leak"

# And the wiring errors, which must refuse rather than skip: a skip in this
# layer is indistinguishable from "no leaks".
want_broken "valgrind: a missing --valgrind refuses, never skips" \
	"--valgrind is required" -- \
	"$SH" "$TOOLS/valgrind_test.sh" --bin "$WORK/vg_leak"
want_broken "valgrind: a tools dir without memcheck refuses" \
	"does not hold memcheck-amd64-linux" -- \
	"$SH" "$TOOLS/valgrind_test.sh" --valgrind "$VALGRIND" \
		--valgrind-tools "$WORK/novg_path/sh" --bin "$WORK/vg_leak"

# A program that never built is not a memory report. When a student's code does
# not build, tools/student_build.sh writes a stand-in that prints the compiler's
# words (tools/standin.sh); valgrind over it would report on /bin/sh. Written
# by the builder itself, so the arm fails if either side's wording drifts.
mkdir -p "$WORK/standin"
printf 'int\tbroken(void)\n{\n\treturn (0)\n}\n' > "$WORK/standin/broken.c"
printf 'int\tmain(void)\n{\n\treturn (0);\n}\n' > "$WORK/standin/main.c"
"$SH" "$TOOLS/student_build.sh" --cc "$CC" --out "$WORK/standin/prog" --label selftest \
	--harness "$WORK/standin/main.c" --src "$WORK/standin/broken.c" > /dev/null 2>&1 &&
	[ -f "$WORK/standin/prog" ] || {
	echo "selftest_slow: tools/student_build.sh wrote no stand-in for a syntax error" >&2
	exit 2
}
STANDIN_BIN="$WORK/standin/prog"
want_red "valgrind: a stand-in is red, not a memory report" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$STANDIN_BIN"
want_out "valgrind: ...says the code did not build" 'your code did not build' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$STANDIN_BIN"

want_green "valgrind: a program that frees what it allocates passes" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_clean"
want_red   "valgrind: a leak is detected" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_leak"
want_red   "valgrind: a read past the end of a block is detected" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_oob"
want_red   "valgrind: use of an uninitialised heap byte is detected" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_uninit"
# What memcheck cannot see, said where it passes (a verdict says only what
# ran): its OK line claimed "no invalid access" over a program that wrote past
# a local array.
want_green "valgrind: a write past a local array is not memcheck's to see" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_stack"
want_out   "valgrind: ...and its OK line says so" 'past an array on the stack' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_stack"
want_none "valgrind: ...and claims no invalid access but of the heap" \
	'no invalid access,' -- "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_stack"
# ...and names what sees it without promising a layer: seven exercises with a
# memcheck target have no ASan one, and this runner is not told which.
want_out  "valgrind: ...it says an ASan build sees it" 'an ASan build does' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_stack"
want_none "valgrind: ...and promises no ASan layer the exercise may lack" 'the ASan layers' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_stack"

# THE STANDARD A FAIL NAMES (finding 082): the call site's sentence where the
# subject states one (--rule), and otherwise the rule this layer applies, said
# to be this repo's -- never "the paragraph on memory management" of a subject
# that has none, which every red memcheck used to cite.
printf 'Toy, p.4: "Free what you take."\n' > "$WORK/vg_rule.txt"
want_out  "valgrind: a leak's FAIL quotes the call site's sentence" \
	'Toy, p.4: "Free what you take."' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --rule "$WORK/vg_rule.txt" --bin "$WORK/vg_leak"
want_out  "valgrind: ...and with none, the rule it applies, as this repo's" \
	"It is not a sentence of your subject's" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_leak"
want_none "valgrind: ...never a paragraph of the subject" 'paragraph on memory' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_leak"
# Nor a level: which level a target runs at is the target's (its tags), and
# the text said "at strict" for every one of them.
want_none "valgrind: ...nor the level, which is the target's" 'at strict' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_leak"

# THE TIME BUDGET (finding 066). VALGRIND_TIMEOUT is 60s, which is the whole of
# a small test's limit -- and the output gate runs before it -- so a program
# that never ends was killed by Bazel, with nothing in the log. Each run now
# gets what is left of the test's own limit when that is less, and says so.
# alarm() ends the loop by itself after 20s, so a regression here costs a
# bounded wait and not the whole target.
printf '#include <unistd.h>\nint main(void){alarm(20);for(;;);}\n' > "$WORK/vg_spin.c"
"$CC" -w -g -O0 -o "$WORK/vg_spin" "$WORK/vg_spin.c" 2> /dev/null
want_red   "valgrind: a program that never ends is stopped" -- \
	env TEST_TIMEOUT=6 RL_MARGIN=1 "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_spin"
want_out   "valgrind: ...inside the test's own limit, and says so" \
	"what was left of this test's own time limit" -- \
	env TEST_TIMEOUT=6 RL_MARGIN=1 "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_spin"

# ---------------------------------------------------------------- descriptors
# A FILE LEFT OPEN is the same mistake as a leaked allocation in a different
# resource. --track-fds=yes finds it; --error-exitcode never fires on it, so the
# line has to be read.
#
# THE THIRD ARM IS THE IMPORTANT ONE. The summary line valgrind prints --
# "FILE DESCRIPTORS: 4 open (3 std) at exit" -- is what a program that opens
# NOTHING reports under this layer, because --log-file gives valgrind a
# descriptor the child inherits. A check built on `open > std` therefore failed
# 24 of the repo's 69 valgrind targets, every one of them the harness measuring
# itself. vg_clean opens no file at all, so it is the guard against that
# returning.
# Only want_red/want_green/want_broken exist in this file -- want_out and
# want_broken_none are selftest.sh's. Calling one here is not an error the shell
# reports usefully: it is "not found", exit 127, swallowed, and the arm silently
# does not run. Three of these arms were written that way and vanished; the
# count went 17 to 19 instead of 17 to 22 and everything still said OK.
#
# Every property below is expressible as a STATUS anyway, which is the stronger
# assertion of the two.
want_red   "valgrind: a descriptor left open FAILS by default" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdleak"
want_green "valgrind: ...and VALGRIND_FDS=lax turns it back into a note" -- \
	env VALGRIND_FDS=lax "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS \
		--bin "$WORK/vg_fdleak"
want_green "valgrind: a CLOSED descriptor passes" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdok"
# THE OTHER PATH TO THE SAME VERDICT. When the child chooses a non-zero exit
# status and valgrind found nothing, the runner leaves by a different branch --
# and that branch's gate tested VALGRIND_FDS = "strict", which nothing sets, so
# it printed "DESCRIPTORS LEFT OPEN ... This is a FAILURE" and exited 0. The
# pair below pins both directions, because a gate that only ever fires is as
# wrong as one that never does.
want_red   "valgrind: a descriptor left open FAILS on the exit-status path too" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdleak_rc"
want_green "valgrind: ...and lax turns THAT one back into a note as well" -- \
	env VALGRIND_FDS=lax "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS \
		--bin "$WORK/vg_fdleak_rc"
# THE VERDICT COMES FIRST (finding 171). A descriptor failure used to open
# with "valgrind_test: OK", the failure a screen further down; it showed the
# stanza of valgrind's OWN log file (only the "<inherited from parent>" line
# was dropped), and it explained itself twice. The headline is the line a
# reader and a Bazel summary keep, so it is what these arms read.
want_out   "valgrind: a descriptor left open is the FAIL headline" \
	'valgrind_test: FAIL — 1 descriptor(s) opened by' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdleak"
want_none  "valgrind: ...never under an OK line" 'valgrind_test: OK' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdleak"
want_out   "valgrind: ...naming the file the program opened" \
	': /etc/hostname' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdleak"
want_none  "valgrind: ...and never valgrind's own log" 'vg.log' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdleak"
want_out   "valgrind: ...with the escape spelled for bazel" \
	'--test_env=VALGRIND_FDS=lax' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdleak"
# Said once: count the explanation's first line in the report.
_fd_out=$("$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdleak" 2>&1)
_fd_n=$(printf '%s\n' "$_fd_out" | grep -c 'hands back a number the kernel holds')
if [ "$_fd_n" -eq 1 ]; then
	printf '  %-52s %s\n' "valgrind: ...and explains itself once" "ok (said once)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "valgrind: ...and explains itself once" \
		"FAIL < (the explanation appears $_fd_n times)"
	FAIL=$((FAIL + 1))
fi
want_out   "valgrind: a closed descriptor's OK says it checked them" \
	'every descriptor it opened closed' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdok"
# The raw report under a MEMORY finding is filtered the same way: vg_fdleak_mem
# leaks a block and closes everything it opened, so the only descriptor stanza
# valgrind prints is its own log's, and the report must not show it.
printf '#include <stdlib.h>\n#include <fcntl.h>\n#include <unistd.h>\nint main(void){int f=open("/etc/hostname",O_RDONLY);close(f);return (malloc(8)==0);}\n' \
	> "$WORK/vg_fdleak_mem.c"
"$CC" -w -g -O0 -o "$WORK/vg_fdleak_mem" "$WORK/vg_fdleak_mem.c" 2> /dev/null
want_out   "valgrind: a leak with every descriptor closed is still a leak" \
	'DEFINITELY LOST' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdleak_mem"
want_none  "valgrind: ...and its raw report drops the harness's own log" \
	'Open file descriptor' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdleak_mem"

# ------------------------------------------------------------- --no-leak-check
# THE CLASS ASan STRUCTURALLY CANNOT SEE, which is the whole reason c_mem_check
# now runs its probe under memcheck as well.
#
# NO-MALLOC-ALLOWED drops the valgrind layer wherever a subject forbids malloc,
# on the ground that there is no allocation to report on. True of the LEAK half
# only: invalid read, invalid write, invalid free and uninitialised value need
# no allocation at all, and ASan has no uninitialised-memory checker.
#
# vg_uninit_wr is the exact shape c-00 ex06/ex08, c-02 ex11/ex12 and c-04
# ex02/ex04 are built out of -- a fixed 4-byte buffer with 3 bytes filled, all 4
# handed to write(). Measured: ASan+UBSan with -fno-sanitize-recover=all exits
# 0 on it, and memcheck says "Syscall param write(buf) points to uninitialised
# byte(s)".
printf '#include <unistd.h>\nint main(void){char b[4];b[0]=97;b[1]=98;b[2]=99;if(write(1,b,4)<0)return(1);return (0);}\n' \
	> "$WORK/vg_uninit_wr.c"
"$CC" -w -g -O0 -o "$WORK/vg_uninit_wr" "$WORK/vg_uninit_wr.c" 2> /dev/null

want_red   "valgrind: --no-leak-check still sees an uninitialised write()" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --no-leak-check \
		--bin "$WORK/vg_uninit_wr"
# ...and its FAIL states the rule it applied, which has no leak half.
want_out   "valgrind: ...stating the rule it applied" 'no decision on a value' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --no-leak-check \
		--bin "$WORK/vg_uninit_wr"
want_none  "valgrind: ...and no leak rule it did not apply" 'every block allocated' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --no-leak-check \
		--bin "$WORK/vg_uninit_wr"
# The other half: it really does stop reporting leaks, and the pair is what
# makes the flag safe for a probe binary that is ours and is not expected to
# free what it allocated. vg_leak is red WITHOUT the flag three arms above.
want_green "valgrind: ...and stops reporting the leak it is told to ignore" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --no-leak-check --bin "$WORK/vg_leak"
# And the pass line must not claim what was never looked for. A green that says
# "no leak" over a --leak-check=no run is the false statement of record this
# repo keeps finding in its own comments, printed on every single pass.
#
# Written out rather than through want_broken_none, which is selftest.sh's:
# calling a helper this file does not define is "not found", exit 127, swallowed
# -- and the arm silently does not run, which is the trap the header above
# records three arms already fell into.
# shellcheck disable=SC2086
_nlc_out=$("$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --no-leak-check \
	--bin "$WORK/vg_clean" 2>&1)
_nlc_rc=$?
if [ "$_nlc_rc" -ne 0 ]; then
	printf '  %-52s %s\n' "valgrind: a --no-leak-check pass does not claim 'no leak'" \
		"FAIL < (exit $_nlc_rc; the run must succeed)"
	FAIL=$((FAIL + 1))
elif printf '%s' "$_nlc_out" | grep -qF -- 'no leak,'; then
	printf '  %-52s %s\n' "valgrind: a --no-leak-check pass does not claim 'no leak'" \
		"FAIL < (claimed 'no leak' having not looked)"
	FAIL=$((FAIL + 1))
else
	printf '  %-52s %s\n' "valgrind: a --no-leak-check pass does not claim 'no leak'" \
		"ok (claimed only what it checked)"
	PASS=$((PASS + 1))
fi
# THE GUARD AGAINST THE FALSE POSITIVE. vg_clean opens no file at all, and under
# a check built on valgrind's "N open (M std)" summary it FAILED -- because
# --log-file gives valgrind a descriptor the child inherits. That shape failed
# 24 of the repo's 69 valgrind targets, every one the harness measuring itself.
want_green "valgrind: valgrind's OWN log fd is not the student's" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_clean"

# The --gate-* skip: this layer stays quiet while the exercise's own output
# fixture is red, so a student is not buried in memory findings before their
# function returns the right answer. The risk is a gate that fires ALWAYS, which
# would silence the only leak detector in the repo. Both directions are checked.
printf 'hello\n' > "$WORK/gate_exp.txt"
printf '#include <stdio.h>\n#include <stdlib.h>\nint main(void){malloc(64);printf("hello\\n");return (0);}\n' \
	> "$WORK/vg_gate_ok.c"
printf '#include <stdio.h>\n#include <stdlib.h>\nint main(void){malloc(64);printf("wrong\\n");return (0);}\n' \
	> "$WORK/vg_gate_bad.c"
"$CC" -w -g -O0 -o "$WORK/vg_gate_ok" "$WORK/vg_gate_ok.c" 2> /dev/null
"$CC" -w -g -O0 -o "$WORK/vg_gate_bad" "$WORK/vg_gate_bad.c" 2> /dev/null

# `env -u NO_SKIP`, for the reason the arm three lines below exists: this pair
# CONTRASTS the gate closed against the gate forced open, so the first half has
# to run with NO_SKIP absent. Under `--test_env=NO_SKIP=1` -- the sweep these
# arms are written for -- it inherited the variable and was guaranteed red. The
# fast suite had the identical bug in its ilp32 arm; a suite that cannot come
# back green is a suite nobody runs twice.
want_green "valgrind: the gate skips a leak while the fixture is still red" -- \
	env -u NO_SKIP "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_gate_bad" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/vg_gate_bad" \
		--gate-expected "$WORK/gate_exp.txt"
want_red   "valgrind: with the fixture green, the same leak IS reported" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_gate_ok" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/vg_gate_ok" \
		--gate-expected "$WORK/gate_exp.txt"
want_red   "valgrind: NO_SKIP=1 forces the gate open on a red fixture" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_gate_bad" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/vg_gate_bad" \
		--gate-expected "$WORK/gate_exp.txt"
# ...and, opened that way, it says the output layer is red too, first: a
# report on a wrong answer can be about what the test could not take apart
# (finding 137). The premise false -- the fixture green, NO_SKIP=1 all the
# same -- and the same leak is reported without the note.
want_out   "valgrind: ...and says the output layer is red too" \
	"output layer is red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_gate_bad" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/vg_gate_bad" \
		--gate-expected "$WORK/gate_exp.txt"
want_none  "valgrind: ...never when the fixture is green" \
	"output layer is red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_gate_ok" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/vg_gate_ok" \
		--gate-expected "$WORK/gate_exp.txt"
# Every failure says so, not only a memory finding (review of WP-95): a
# descriptor left open (vg_fdleak prints nothing, so its fixture is red), and
# a run the gate left no time for -- vg_spin never ends, so the gate spends
# the whole of a 6-second test on it and the run under valgrind cannot start.
want_out   "valgrind: ...and so does a descriptor left open" \
	"output layer is red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_fdleak" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/vg_fdleak" \
		--gate-expected "$WORK/gate_exp.txt"
want_out   "valgrind: ...and a run the gate left no time for" \
	"output layer is red" -- \
	env NO_SKIP=1 TEST_TIMEOUT=6 RL_MARGIN=1 "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS \
		--bin "$WORK/vg_spin" --gate-differ "$TOOLS/diff_output.sh" \
		--gate-bin "$WORK/vg_spin" --gate-expected "$WORK/gate_exp.txt"
# A case that takes any of several outputs (its "any_of") gates on all of
# them: its fixture is green when the output is ONE of them, so the leak is
# reported rather than skipped behind a gate that knew only the first.
printf 'other\n' > "$WORK/gate_other.txt"
want_red   "valgrind: an any_of gate is open on its second output" -- \
	env -u NO_SKIP "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_gate_ok" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/vg_gate_ok" \
		--gate-expected "$WORK/gate_other.txt" --gate-expected-alt "$WORK/gate_exp.txt"

# A GATE THAT CANNOT ANSWER MUST NOT SILENCE THE LAYER.
#
# The gate used to be `if ! sh "$GATE_DIFFER"`, which treats every non-zero
# alike -- but the differ means TWO things by non-zero: 1 is "the student's
# fixture is red", which the gate exists for, and 2 is "the differ could not run
# at all". Conflated, a BROKEN gate suppressed the layer AND printed "this
# exercise's own output fixture is not passing yet", which was simply false.
#
# Demonstrated at scale before the fix: the whole perf layer went 77/77 green
# under a PATH shim missing `mv`, because diff_output.sh requires it and exits 2.
printf 'anything\n' > "$WORK/vg_gate_expected"
want_red "valgrind: a leak is still reported when the GATE is broken" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_leak" \
		--gate-differ "$WORK/no_such_differ.sh" \
		--gate-bin "$WORK/vg_leak" --gate-expected "$WORK/vg_gate_expected"

# A PROGRAM CASE RUNS THE SAME THING HERE AS IN ITS OUTPUT TEST: its argument
# file and its run folder (c_program's "argv_file" and "cwd_files"), and its
# gate is run that way too. This toy prints the first line of ./toy.dict and
# leaks; run from anywhere else it prints another line, so a gate that was
# not handed the folder would read the fixture as red and skip the leak.
printf '%s\n' '#include <stdio.h>' '#include <stdlib.h>' \
	'int main(void) { char b[64]; FILE *f = fopen("toy.dict", "r"); malloc(64);' \
	'	if (!f) return (printf("no toy.dict here\n"), 1);' \
	'	if (fgets(b, sizeof b, f)) fputs(b, stdout); fclose(f); return (0); }' > "$WORK/vg_pc.c"
"$CC" -w -g -O0 -o "$WORK/vg_pc" "$WORK/vg_pc.c" 2> /dev/null
printf 'staged\n' > "$WORK/vg_pc_staged.txt"
vg_pc() {
	env -u NO_SKIP "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_pc" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/vg_pc" \
		--gate-expected "$WORK/vg_pc_staged.txt" "$@"
}
want_red   "valgrind: a run folder reaches the gate, which opens" -- \
	vg_pc --run-as toy --cwd-file "toy.dict=$WORK/vg_pc_staged.txt"
want_out   "valgrind: ...and the leak is reported, not skipped" 'DEFINITELY LOST' -- \
	vg_pc --run-as toy --cwd-file "toy.dict=$WORK/vg_pc_staged.txt"
want_out   "valgrind: ...under a RAN line naming the folder's files" 'toy.dict  a copy of' -- \
	vg_pc --run-as toy --cwd-file "toy.dict=$WORK/vg_pc_staged.txt" --show-run bazel-bin/m/ex00_bin
want_green "valgrind: without the folder, the same gate is red and skips" -- vg_pc
# Its hints: a row naming this case or this layer, and rows naming none;
# never another case's.
printf 'about case a?\ta\nabout case b?\tb\nabout any failure?\nabout memory?\tvalgrind\n' > "$WORK/vg_pc_clues.tsv"
want_out   "valgrind: --case fires the row naming its case" 'about case a?' -- \
	vg_pc --run-as toy --cwd-file "toy.dict=$WORK/vg_pc_staged.txt" --case a --clues "$WORK/vg_pc_clues.tsv"
want_none "valgrind: ...and no row naming another" 'about case b?' -- \
	vg_pc --run-as toy --cwd-file "toy.dict=$WORK/vg_pc_staged.txt" --case a --clues "$WORK/vg_pc_clues.tsv"
want_out   "valgrind: ...and a row naming this layer" 'about memory?' -- \
	vg_pc --run-as toy --cwd-file "toy.dict=$WORK/vg_pc_staged.txt" --case a --clues "$WORK/vg_pc_clues.tsv"
# With no case (a c_function's memcheck), every row fired as this layer's own:
# C 13 ex04's leak was headed by its three output hints (V55). Now the row
# naming this layer, and the rows naming none, said to be the output's; a
# row naming one of the output's cases, never.
want_none "valgrind: no --case, and no row naming an output case" 'about case a?' -- \
	vg_pc --run-as toy --cwd-file "toy.dict=$WORK/vg_pc_staged.txt" --clues "$WORK/vg_pc_clues.tsv"
want_out   "valgrind: ...the row naming this layer" 'about memory?' -- \
	vg_pc --run-as toy --cwd-file "toy.dict=$WORK/vg_pc_staged.txt" --clues "$WORK/vg_pc_clues.tsv"
want_out   "valgrind: ...and the rows naming none, said to be the output's" \
	'written for its output test rather than this one' -- \
	vg_pc --run-as toy --cwd-file "toy.dict=$WORK/vg_pc_staged.txt" --clues "$WORK/vg_pc_clues.tsv"
# Its argument file, in the run AND in the gate. This toy leaks only when it
# is given exactly one argument and that argument is empty -- what an argument
# file holding one empty line says, and what `args` cannot -- and prints a line
# saying which run it got. Without the file the gate's fixture is red and the
# layer skips; a gate run without the file would skip the leak here, and a run
# without it would find none: either half dropped turns the first arm green.
printf '%s\n' '#include <stdio.h>' '#include <stdlib.h>' \
	'int main(int ac, char **av) { if (ac == 2 && !av[1][0]) { malloc(64);' \
	'	return (printf("one empty argument\n"), 0); } return (printf("%d arguments\n", ac - 1), 0); }' \
	> "$WORK/vg_af.c"
"$CC" -w -g -O0 -o "$WORK/vg_af" "$WORK/vg_af.c" 2> /dev/null
printf 'one empty argument\n' > "$WORK/vg_af_expected.txt"
printf '\n' > "$WORK/vg_af.argv"
vg_af() {
	env -u NO_SKIP "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_af" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/vg_af" \
		--gate-expected "$WORK/vg_af_expected.txt" "$@"
}
want_red   "valgrind: an argument file reaches the run and the gate" -- \
	vg_af --argv-file "$WORK/vg_af.argv"
want_out   "valgrind: ...and the leak it makes is reported" 'DEFINITELY LOST' -- \
	vg_af --argv-file "$WORK/vg_af.argv"
want_out   "valgrind: ...under a RAN line showing the empty argument" "RAN: m/ex00_bin ''" -- \
	vg_af --argv-file "$WORK/vg_af.argv" --show-run m/ex00_bin
want_green "valgrind: without the file, the same gate is red and skips" -- vg_af
want_out   "valgrind: ...and says it skipped" 'SKIP' -- vg_af

# ------------------------------------------------------- a corpus under memcheck
# The memory layers ran the hand-written cases only; every generated corpus ran
# on the plain build, where a leak changes no byte (finding 113). A corpus
# runner's --valgrind replays a sample of its corpus through valgrind_test.sh
# (tools/runner_lib.sh, "A CORPUS UNDER A MEMORY CHECKER"). Shown here on
# rush02_check.sh, the smallest corpus format: a converter that frees its copy
# of the number except when the number has two digits, which no hand-written
# case of the fake corpus below would reach.
mkdir -p "$WORK/mc"
printf '0: zero\n' > "$WORK/mc/dict.txt"
{
	printf '#!/bin/sh\ncat <<%sEOF%s\n' "'" "'"
	_i=0
	while [ "$_i" -lt 30 ]; do printf '%s\tn%s\n' "$_i" "$_i"; _i=$((_i + 1)); done
	printf 'EOF\n'
} > "$WORK/mc/oracle.sh"
chmod +x "$WORK/mc/oracle.sh"
cat > "$WORK/mc/conv.c" <<'MC_CONV'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int ac, char **av)
{
	char	*b;

	if (ac != 3)
		return (1);
	b = malloc(strlen(av[2]) + 1);
	if (!b)
		return (1);
	strcpy(b, av[2]);
	printf("n%s\n", b);
	if (b[1] == '\0')
		free(b);
	return (0);
}
MC_CONV
sed 's/if (b\[1\] == .\\0.)//' "$WORK/mc/conv.c" > "$WORK/mc/conv_ok.c"
"$CC" -w -g -O0 -o "$WORK/mc/conv" "$WORK/mc/conv.c" 2> /dev/null
"$CC" -w -g -O0 -o "$WORK/mc/conv_ok" "$WORK/mc/conv_ok.c" 2> /dev/null
# One run per program, each read by several arms: a memcheck run is seconds,
# and on a loaded machine many of them are this target's whole time limit.
# shellcheck disable=SC2086 # VG_PASS is several flags, split on purpose
for _mc in conv conv_ok; do
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/mc/$_mc" --dict "$WORK/mc/dict.txt" \
		--oracle "$WORK/mc/oracle.sh" $VG_PASS --sample 4 > "$WORK/mc/$_mc.out" 2>&1
	echo "$?" > "$WORK/mc/$_mc.rc"
done
mc_seen() { cat "$WORK/mc/$1.out"; return "$(cat "$WORK/mc/$1.rc")"; }
want_green "corpus --valgrind: the leaking converter agrees on the plain replay" -- \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/mc/conv" --dict "$WORK/mc/dict.txt" \
		--oracle "$WORK/mc/oracle.sh" --stderr-ignored "the toy corpus asks nothing of it"
# The memcheck replays above make no stderr choice: under a checker the mode
# is the choice (tools/runner_lib.sh, rl_stderr_choice). One that makes one
# anyway is refused.
# shellcheck disable=SC2086 # VG_PASS is several flags, split on purpose
want_broken "corpus --valgrind: ...and a stderr choice beside it is refused" \
	"under --valgrind standard error carries the checker's report" -- \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/mc/conv" --dict "$WORK/mc/dict.txt" \
		--oracle "$WORK/mc/oracle.sh" $VG_PASS --stderr-empty
# The sample is spread evenly over the corpus (cases 8, 15, 23 and 30 of 30),
# never its head: cases 1-10 are the one-digit numbers this converter frees,
# so a sample of the first four would pass it.
want_red   "corpus --valgrind: ...and its sample under memcheck is red" -- mc_seen conv
want_out   "corpus --valgrind: ...naming the first case the leak is on" 'case 15 of 30  [memcheck]' -- \
	mc_seen conv
want_out   "corpus --valgrind: ...with memcheck's own report" 'definitely lost' -- mc_seen conv
want_out   "corpus --valgrind: ...and the tally" '3 of 4 case(s) under memcheck went wrong' -- mc_seen conv
want_green "corpus --valgrind: a converter that frees passes" -- mc_seen conv_ok
# WHAT A FINDING MEANS IS SAID ONCE (V53): each case's block carried
# valgrind_test.sh's paragraphs, so a sample of 25 printed the descriptor
# paragraph 25 times. A converter that leaves the dictionary open on every
# case: the paragraph once, after the cases, and the descriptor in each.
cat > "$WORK/mc/fdconv.c" <<'MC_FD'
#include <fcntl.h>
#include <stdio.h>
int main(int ac, char **av)
{
	if (ac != 3)
		return (1);
	open(av[1], O_RDONLY);
	printf("n%s\n", av[2]);
	return (0);
}
MC_FD
"$CC" -w -g -O0 -o "$WORK/mc/fdconv" "$WORK/mc/fdconv.c" 2> /dev/null
# shellcheck disable=SC2086 # VG_PASS is several flags, split on purpose
"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/mc/fdconv" --dict "$WORK/mc/dict.txt" \
	--oracle "$WORK/mc/oracle.sh" $VG_PASS --sample 4 > "$WORK/mc/fdconv.out" 2>&1
echo "$?" > "$WORK/mc/fdconv.rc"
mc_count() {  # mc_count RUN TEXT -- how many lines of RUN's report hold TEXT
	printf 'lines: %s\n' "$(grep -cF -- "$2" "$WORK/mc/$1.out")"
}
want_red   "corpus --valgrind: a descriptor left open on every case is red" -- mc_seen fdconv
want_out   "corpus --valgrind: ...each case naming it" 'lines: 4' -- \
	mc_count fdconv 'DESCRIPTORS LEFT OPEN: 1 opened by this program'
want_out   "corpus --valgrind: ...and saying what it means once" 'lines: 1' -- \
	mc_count fdconv 'Every open() hands back a number'
want_out   "corpus --valgrind: ...as a leak's class is, over three cases" 'lines: 1' -- \
	mc_count conv 'DEFINITELY LOST —'
# ...and the rule a leak breaks, once, as a fixed case's arm states it: this
# harness's, said to be so, where the call site quotes no sentence of the
# subject's. --brief left it out and nothing said it (the review of V53).
want_out   "corpus --valgrind: ...and the rule it applies, once" 'lines: 1' -- \
	mc_count conv 'The rule this layer applies'
want_out   "corpus --valgrind: ...said to be this harness's" 'lines: 1' -- \
	mc_count conv "It is not a sentence of your subject's"
want_out   "corpus --valgrind: ...saying how many of the corpus ran" \
	"4 of the corpus's 30 case(s), spread evenly over it," -- mc_seen conv_ok
# ...and only of the cases it shows. Under VALGRIND_FDS=lax a descriptor left
# open is a note, and its case passes and is not shown: a converter that
# leaves the dictionary open on case 8 (the number 7) and leaks on case 15
# (14) printed the descriptor paragraph, "this is a NOTE rather than a
# failure", under the leak's verdict, about no report above it.
cat > "$WORK/mc/fdnote.c" <<'MC_FDNOTE'
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int ac, char **av)
{
	if (ac != 3)
		return (1);
	if (strcmp(av[2], "7") == 0)
		open(av[1], O_RDONLY);
	if (strcmp(av[2], "14") == 0)
		strcpy(malloc(8), "x");
	printf("n%s\n", av[2]);
	return (0);
}
MC_FDNOTE
"$CC" -w -g -O0 -o "$WORK/mc/fdnote" "$WORK/mc/fdnote.c" 2> /dev/null
# shellcheck disable=SC2086 # VG_PASS is several flags, split on purpose
# Its call quotes the subject's sentence (--rule, c_program's memory_rule,
# V82), which the verdict quotes once, in place of this harness's rule.
printf 'Toy, p.1: "Free what you allocate."\n' > "$WORK/mc/rule.txt"
env VALGRIND_FDS=lax "$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/mc/fdnote" --dict "$WORK/mc/dict.txt" \
	--oracle "$WORK/mc/oracle.sh" $VG_PASS --sample 4 --rule "$WORK/mc/rule.txt" > "$WORK/mc/fdnote.out" 2>&1
echo "$?" > "$WORK/mc/fdnote.rc"
want_red   "corpus --valgrind: a leak beside a passing case's descriptor note is red" -- mc_seen fdnote
want_out   "corpus --valgrind: ...explaining the leak" 'lines: 1' -- \
	mc_count fdnote 'DEFINITELY LOST —'
want_none  "corpus --valgrind: ...and never the note no case shown holds" \
	'Every open() hands back a number' -- mc_seen fdnote
want_out   "corpus --valgrind --rule: ...quoting the subject's sentence once" 'lines: 1' -- \
	mc_count fdnote 'Toy, p.1: "Free what you allocate."'
want_none  "corpus --valgrind --rule: ...never calling the rule the harness's" \
	'It is not a sentence' -- mc_seen fdnote
# A CASE THE TEST'S OWN LIMIT CUT SHORT is not one memcheck judged. The ASan
# replay stops as a budget there (rl_sweep_ran); under memcheck the cut case
# was one more failure, and the stop said "each of the first 2 of 4 cases
# ended within its own limit" over a case that had not. A converter that
# waits two minutes on the number of case 15, the second of the sample,
# under a test limit of 14 s, of which a case may take 10 s: what is left of
# the limit cuts it first.
cat > "$WORK/mc/slow.c" <<'MC_SLOW'
#include <poll.h>
#include <stdio.h>
#include <string.h>
int main(int ac, char **av)
{
	if (ac != 3)
		return (1);
	if (strcmp(av[2], "14") == 0)
		poll(NULL, 0, 120000);
	printf("n%s\n", av[2]);
	return (0);
}
MC_SLOW
"$CC" -w -g -O0 -o "$WORK/mc/slow" "$WORK/mc/slow.c" 2> /dev/null
# shellcheck disable=SC2086 # VG_PASS is several flags, split on purpose
env -u RL_DEADLINE -u RL_BUDGET TEST_TIMEOUT=14 \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/mc/slow" --dict "$WORK/mc/dict.txt" \
	--oracle "$WORK/mc/oracle.sh" $VG_PASS --sample 4 > "$WORK/mc/slow.out" 2>&1
echo "$?" > "$WORK/mc/slow.rc"
want_red   "corpus --valgrind: a case cut by the test's limit is red" -- mc_seen slow
want_out   "corpus --valgrind: ...shown as the one running when the time ran out" \
	'the one running when the time ran out' -- mc_seen slow
want_out   "corpus --valgrind: ...the case marked as cut, not as memcheck's" \
	'case 15 of 30  [timeout]' -- mc_seen slow
want_none  "corpus --valgrind: ...and never counted as a case judged wrong" \
	'judged wrong before that' -- mc_seen slow
# ...and a case that ran out of ITS OWN time, the test's to spare, is not
# memcheck's finding either (V48, ruling R4): it was "[memcheck]", and "1 of
# 4 case(s) under memcheck went wrong". RUSH02_TIMEOUT 3 and no test limit:
# the case's own cap stops the poll.
# shellcheck disable=SC2086 # VG_PASS is several flags, split on purpose
env -u RL_DEADLINE -u RL_BUDGET -u TEST_TIMEOUT RUSH02_TIMEOUT=3 \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/mc/slow" --dict "$WORK/mc/dict.txt" \
	--oracle "$WORK/mc/oracle.sh" $VG_PASS --sample 4 > "$WORK/mc/slowcap.out" 2>&1
echo "$?" > "$WORK/mc/slowcap.rc"
want_red   "corpus --valgrind: a case past its own limit is red" -- mc_seen slowcap
want_out   "corpus --valgrind: ...marked as not finished, not as memcheck's" \
	'case 15 of 30  [timeout]' -- mc_seen slowcap
want_out   "corpus --valgrind: ...and said apart in the verdict" \
	'1 of 4 case(s) under memcheck did not finish in their time' -- mc_seen slowcap
want_none  "corpus --valgrind: ...never as gone wrong" 'went wrong' -- mc_seen slowcap

# ------------------------------------------------------------------- perf
# perf_test.sh was substantially rewritten and none of the rewrite was covered:
# CPU time from wait4() instead of wall clock, best-of-PERF_REPEATS sampling, a
# least-squares fit over three sizes instead of two points, and monotonicity as a
# data-quality gate. Every one of those exists to stop the layer failing CORRECT
# code because the machine was busy, which is a failure mode you cannot notice by
# running it once and seeing green.
#
# It lives here rather than in the fast selftest because the signal is the point:
# the growth exponent cannot be fitted from a workload too small to measure, and
# at 4000 cases even the quadratic student reports "too fast to measure reliably"
# -- verified, not assumed. 16000 gives n^2.00 and costs a few seconds.
#
# --oracle is faked with a shell script. The runner only asks it for a corpus of
# N lines, so nothing here needs //oracle's Rust build.
#
# NO_SKIP=1 is required, and that is the layer working: perf_test gates on the
# correctness layer first, and these synthetic students deliberately do not agree
# with a fake reference, so without it every arm below would SKIP and pass while
# measuring nothing.
mkdir -p "$WORK/pf"
cat > "$WORK/pf/oracle.sh" <<'PF_ORACLE'
#!/bin/sh
# $1 fn, $2 seed, $3 count -- emit <count> corpus lines.
n=$3; i=0
while [ "$i" -lt "$n" ]; do printf '%s\t%s\n' "$i" "$i"; i=$((i + 1)); done
PF_ORACLE
chmod +x "$WORK/pf/oracle.sh"

# Linear in the number of cases: reads each line once.
cat > "$WORK/pf/lin.c" <<'PF_LIN'
#include <stdio.h>
int main(void)
{
	char	b[256];
	long	s = 0;

	while (fgets(b, sizeof b, stdin))
		s += b[0];
	printf("%ld\n", s);
	return (0);
}
PF_LIN
# Quadratic: counts the cases, then does n*n work. This is the shape the layer
# exists to catch -- correct output, cost that explodes with the input.
cat > "$WORK/pf/quad.c" <<'PF_QUAD'
#include <stdio.h>
int main(void)
{
	char			b[256];
	long			n = 0;
	long			i;
	long			j;
	volatile long	s = 0;

	while (fgets(b, sizeof b, stdin))
		n++;
	i = 0;
	while (i < n)
	{
		j = 0;
		while (j < n)
		{
			s += (i * j) ^ (i + j);
			j++;
		}
		i++;
	}
	printf("%ld\n", (long)s);
	return (0);
}
PF_QUAD
"$CC" -O1 -o "$WORK/pf/lin" "$WORK/pf/lin.c" 2>/dev/null
"$CC" -O1 -o "$WORK/pf/quad" "$WORK/pf/quad.c" 2>/dev/null

pf_run() {  # pf_run BIN [extra args...]
	_bin="$1"; shift
	NO_SKIP=1 "$SH" "$TOOLS/perf_test.sh" --runner "$PERF_RUN" \
		--student-bin "$WORK/pf/$_bin" --oracle "$WORK/pf/oracle.sh" \
		--oracle-fn f --count 16000 --label "selftest-$_bin" "$@"
}

if [ -n "$PERF_RUN" ] && [ -x "$PERF_RUN" ]; then
	want_green "perf: linear growth passes a n^1.5 gate" -- \
		pf_run lin --gate-exponent 1.5
	want_red   "perf: quadratic growth trips the same gate" -- \
		pf_run quad --gate-exponent 1.5
	# The layer is INFORMATIVE unless a gate is set. A version that failed on
	# cost alone would redden 24 correct exercises, which is why this arm exists
	# alongside the one above.
	want_green "perf: without a gate, cost alone never fails" -- \
		pf_run quad
	# A reader that never built is not measured: its "cost" would be a shell
	# printing a compiler error. Past the gates (NO_SKIP=1 forces them open,
	# as pf_run does), a stand-in is a failure in the compiler's words.
	cp "$STANDIN_BIN" "$WORK/pf/built_nothing"
	want_red   "perf: a stand-in is red, not a measurement" -- \
		pf_run built_nothing
	want_out   "perf: ...says the code did not build" 'your code did not build' -- \
		pf_run built_nothing
	# THE GATE'S OWN RUNS are bounded too (finding 066). Stage two replays a
	# sample of the corpus through the student's program, and ran it with no
	# limit at all: a program that never ends hung the layer until Bazel killed
	# it. Now it is stopped at the test's own limit and the gate says why.
	printf '#!/bin/sh\nexec sleep 30\n' > "$WORK/pf/hang"
	chmod +x "$WORK/pf/hang"
	want_out   "perf: a gate run that never ends is stopped and named" \
		'correctness sample did not finish within' -- \
		env TEST_TIMEOUT=6 RL_MARGIN=1 NO_SKIP=1 "$SH" "$TOOLS/perf_test.sh" \
			--runner "$PERF_RUN" --student-bin "$WORK/pf/hang" \
			--oracle "$WORK/pf/oracle.sh" --oracle-fn f --count 16000 --label selftest-hang
	want_red   "perf: ...and under NO_SKIP=1, measuring nothing is red" -- \
		env PERF_TIMEOUT=1 NO_SKIP=1 "$SH" "$TOOLS/perf_test.sh" \
			--runner "$PERF_RUN" --student-bin "$WORK/pf/hang" \
			--oracle "$WORK/pf/oracle.sh" --oracle-fn f --count 16000 --label selftest-hang
	# A SIZE PAST ITS LIMIT IS NOT A VERDICT (finding 043). A fixed 25s wall
	# clock failed the layer outright, a bar far below the 5000x the layer
	# calls its line, and a correct ft_sqrt went red on a busy machine. Now the
	# sizes are halved and measured again, and a layer that could time no size
	# at all reports it and passes -- red only under NO_SKIP=1. The toys echo
	# their input, so the correctness sample (--gate-count 100) is green
	# without NO_SKIP, and stall past a number of lines.
	for _pf in 1000 150; do
		printf '#include <stdio.h>\n#include <unistd.h>\nint main(void)\n{\n\tchar b[256];\n\tlong n = 0;\n\n\twhile (fgets(b, sizeof b, stdin))\n\t{\n\t\tfputs(b, stdout);\n\t\tn++;\n\t}\n\tif (n > %s)\n\t\tsleep(30);\n\treturn (0);\n}\n' \
			"$_pf" > "$WORK/pf/stall$_pf.c"
		"$CC" -O1 -o "$WORK/pf/stall$_pf" "$WORK/pf/stall$_pf.c" 2>/dev/null
	done
	pf_stall() {  # pf_stall LINES -- a toy that stalls past LINES lines
		env -u NO_SKIP PERF_TIMEOUT=1 "$SH" "$TOOLS/perf_test.sh" \
			--runner "$PERF_RUN" --student-bin "$WORK/pf/stall$1" \
			--oracle "$WORK/pf/oracle.sh" --oracle-fn f --count 16000 \
			--gate-count 100 --label "selftest-stall$1"
	}
	want_green "perf: a size past its limit is measured again, halved" -- \
		pf_stall 1000
	want_out   "perf: ...and says so" 'halving every size' -- pf_stall 1000
	want_green "perf: no size within its limit is reported, never failed" -- \
		pf_stall 150
	want_out   "perf: ...and says nothing was measured" 'NOT MEASURED' -- \
		pf_stall 150
	want_red   "perf: ...which NO_SKIP=1 makes red" -- \
		env NO_SKIP=1 PERF_TIMEOUT=1 "$SH" "$TOOLS/perf_test.sh" \
			--runner "$PERF_RUN" --student-bin "$WORK/pf/stall150" \
			--oracle "$WORK/pf/oracle.sh" --oracle-fn f --count 16000 \
			--gate-count 100 --label selftest-stall150

	# THE LENGTH SERIES (finding 044): how one call grows with its input, from
	# an oracle arm that takes a length. The case-count exponent cannot see it
	# -- a toy doing L*L work per line is linear in the number of lines -- and
	# it is reported, never gated: a gate of 1.5 on the case count leaves this
	# quadratic-in-length toy green. A harness that finds a wrong result at a
	# length exits 3, and that length is reported, not timed.
	cat > "$WORK/pf/len_oracle.sh" <<'PF_LEN'
#!/bin/sh
# $1 fn, $2 seed, $3 cases[, $4 length] -- with a length, <cases> lines of
# <length> bytes; without, the case-count corpus oracle.sh writes.
[ -n "${4:-}" ] || exec "${0%/*}/oracle.sh" "$@"
awk -v n="$3" -v l="$4" 'BEGIN { s = ""; for (i = 0; i < l; i++) s = s "x"
	for (j = 0; j < n; j++) print s }'
PF_LEN
	chmod +x "$WORK/pf/len_oracle.sh"
	cat > "$WORK/pf/lenquad.c" <<'PF_LQ'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv)
{
	char			*l = NULL;
	size_t			cap = 0;
	long			n;
	long			i;
	long			j;
	volatile long	s = 0;

	(void)argv;
	while (getline(&l, &cap, stdin) > 0)
	{
		n = (long)strlen(l);
		for (i = 0; i < n; i++)
			for (j = 0; j < n; j++)
				s += (i * j) ^ (i + j);
		if (argc > 1)
			return (3);
	}
	free(l);
	printf("%ld\n", (long)s);
	return (0);
}
PF_LQ
	"$CC" -O1 -o "$WORK/pf/lenquad" "$WORK/pf/lenquad.c" 2>/dev/null
	printf '#!/bin/sh\nexec "%s" wrong\n' "$WORK/pf/lenquad" > "$WORK/pf/lenwrong"
	chmod +x "$WORK/pf/lenwrong"
	pf_len() {  # pf_len HARNESS
		pf_run lin --gate-exponent 1.5 --length-oracle-fn g \
			--length-bin "$WORK/pf/$1" --length-base 250 --length-cases 20 \
			--oracle "$WORK/pf/len_oracle.sh"
	}
	want_green "perf: a quadratic length exponent is never gated" -- pf_len lenquad
	want_out   "perf: ...and is reported" 'grows about L^' -- pf_len lenquad
	want_out   "perf: a wrong result at a length is not timed" \
		'the result was wrong' -- pf_len lenwrong
	# ...but an oracle arm that writes nothing is the wiring rotting, which
	# NO_SKIP=1 (pf_run sets it) is there to see.
	printf '#!/bin/sh\n[ -n "${4:-}" ] && exit 0\nexec "%s" "$@"\n' \
		"$WORK/pf/oracle.sh" > "$WORK/pf/len_empty.sh"
	chmod +x "$WORK/pf/len_empty.sh"
	want_red   "perf: a length arm that writes nothing is red under NO_SKIP" -- \
		pf_run lin --length-oracle-fn g --length-bin "$WORK/pf/lenquad" \
			--oracle "$WORK/pf/len_empty.sh"
	# A crash inside the series is a crash, named as one, as it is in the
	# case-count series: never "the length harness returned N", a harness
	# fault, and never timed.
	printf '#!/bin/sh\nkill -SEGV $$\n' > "$WORK/pf/lensegv"
	chmod +x "$WORK/pf/lensegv"
	want_red   "perf: a crash in the length series is red" -- pf_len lensegv
	want_out   "perf: ...and named as one" 'was killed by SIGSEGV' -- pf_len lensegv
	# A length harness that did not build is a build verdict in the
	# compiler's words, as the measured program's is (_STANDIN_RUNNERS).
	cp "$STANDIN_BIN" "$WORK/pf/len_built_nothing"
	want_red   "perf: a length harness that did not build is red" -- \
		pf_len len_built_nothing
	want_out   "perf: ...says its code did not build" 'length harness' -- \
		pf_len len_built_nothing
	# HOW A MEASURED RUN ENDED, from wait4(), never as 128+N: perf_run said
	# 139 for a SIGSEGV and 255 for `return (-1);` alike above 128, and 137 for
	# its own time limit and for the kernel's out-of-memory killer alike.
	want_out   "perf_run: a return of 255 is exit=255" 'exit=255' -- \
		"$PERF_RUN" -- /bin/sh -c 'exit 255'
	want_out   "perf_run: a death by SIGSEGV is exit=sig11" 'exit=sig11' -- \
		"$PERF_RUN" -- /bin/sh -c 'kill -SEGV $$'
	want_out   "perf_run: its own time limit is exit=timeout" 'exit=timeout' -- \
		"$PERF_RUN" --timeout 1 -- /bin/sh -c 'exec sleep 5'
	# A crash during a measurement is named, not measured.
	printf '#!/bin/sh\nkill -SEGV $$\n' > "$WORK/pf/segv"
	chmod +x "$WORK/pf/segv"
	want_out   "perf: a crash in a measured run is named as one" \
		'was killed by SIGSEGV' -- pf_run segv
else
	printf '  %-52s %s\n' "perf: --runner was not supplied" \
		"FAIL < (nothing was measured)"
	FAIL=$((FAIL + 1))
fi

# ------------------------------------------------------------ a busy machine
# A LIMIT IS THE RUN'S OWN TIME (finding 066): wall time less what the run
# waited on the run queue for a CPU, given back up to a ceiling (--ceiling,
# what the test has left; tools/runqueue.h). A per-run cap was a wall clock,
# and on a machine running two suites at once a correct program spent it
# waiting: argv_diff, survive and perf went red, or measured nothing, on
# load alone. Here the run, pinned to one CPU with three busy loops, needs
# one second of CPU and gets a two-second limit: given its queue time back
# it ends; without a ceiling it is stopped, as every run used to be. A
# program that sleeps waits on no queue and is stopped at its limit (the
# fast suite's arm). Its time is in CPU seconds, so the arm does not depend
# on how fast this machine is.
# conventions: optional taskset -- pins the run and the busy loops to one CPU; without it these arms do not run, and say so
cat > "$WORK/cpu_spin.c" <<'CPU_SPIN'
#include <stdlib.h>
#include <time.h>

/* Spins until it has used argv[1] seconds of CPU, whatever else runs. */
int	main(int argc, char **argv)
{
	volatile unsigned long	x;
	double					want;

	(void)argc;
	want = atof(argv[1]);
	x = 0;
	while ((double)clock() / CLOCKS_PER_SEC < want)
		x++;
	return (0);
}
CPU_SPIN
"$CC" -w -O0 -o "$WORK/cpu_spin" "$WORK/cpu_spin.c" 2> /dev/null
# And only where the kernel counts a task's wait for a CPU: without
# /proc/PID/schedstat nothing is given back, by design (runqueue.h), and the
# arms that need time given back would be red on that machine alone.
if command -v taskset > /dev/null 2>&1 && [ -x "$WORK/cpu_spin" ] && taskset -c 0 true 2> /dev/null &&
	[ -r /proc/self/schedstat ]; then
	_busy=""
	for _b in 1 2 3; do
		taskset -c 0 sh -c 'while :; do :; done' &
		_busy="$_busy $!"
	done
	busy_run() {  # busy_run REPORT [EXIT_STATUS OPTION...] -- one second of CPU on the busy CPU
		_r=$1
		shift
		taskset -c 0 "$TOOLS/exit_status" "$@" "$_r" "$WORK/cpu_spin" 1
		cat "$_r"
	}
	want_out   "exit_status: on a busy CPU, a run given its queue time back ends" 'exit 0' -- \
		busy_run "$WORK/busy_ceil.how" --timeout 2 --ceiling 60
	want_out   "exit_status: ...where a wall clock stopped it" 'timeout 2' -- \
		busy_run "$WORK/busy_wall.how" --timeout 2
	want_out   "perf_run: on a busy CPU, a measurement given its queue time back ends" 'exit=0' -- \
		taskset -c 0 "$PERF_RUN" --timeout 2 --ceiling 60 -- "$WORK/cpu_spin" 1
	# A run that SPINS forever is runnable: it queues as a correct one does,
	# is given that time back too, and is stopped after its limit of its own
	# time -- later in wall time, never on it (runqueue.h). The docs once
	# said a spinner waits on no queue.
	busy_spin() {  # busy_spin REPORT -- a run that never ends, on the busy CPU
		taskset -c 0 "$TOOLS/exit_status" --timeout 2 --ceiling 60 "$1" "$WORK/cpu_spin" 1000
		cat "$1"
	}
	want_out   "exit_status: on a busy CPU, a run that spins is stopped at its own limit" \
		'timeout 2' -- busy_spin "$WORK/busy_spin.how"
	want_out   "exit_status: ...given back the time it queued, as a correct run is" \
		'queued ' -- busy_spin "$WORK/busy_spin2.how"
	# A run the CEILING stopped used less than its own limit, and perf_run
	# said "timeout" for both: perf_test then reported a ceiling stop as
	# "did not finish within 8s (PERF_TIMEOUT)" -- eight seconds of its own
	# it never used. perf_run says "ceiling", and perf_test reports what was
	# left of the test, as rl_classify does for exit_status's "ceiling Q".
	want_out   "perf_run: on a busy CPU, a run the ceiling stopped is exit=ceiling" \
		'exit=ceiling' -- taskset -c 0 "$PERF_RUN" --timeout 2 --ceiling 3 -- "$WORK/cpu_spin" 1000
	# A toy that echoes its input, so the correctness sample passes, and
	# spins past 150 lines: the 200-case floor run never ends. PERF_TIMEOUT
	# 8 is less than the test has left, so only the ceiling (what is left,
	# about 15s of wall time) can stop it before its own 8s are spent.
	printf '#include <stdio.h>\nint main(void)\n{\n\tchar b[256];\n\tlong n = 0;\n\tvolatile long x = 0;\n\n\twhile (fgets(b, sizeof b, stdin))\n\t{\n\t\tfputs(b, stdout);\n\t\tn++;\n\t}\n\twhile (n > 150)\n\t\tx++;\n\treturn (0);\n}\n' \
		> "$WORK/pf/spin150.c"
	"$CC" -O0 -o "$WORK/pf/spin150" "$WORK/pf/spin150.c" 2> /dev/null
	pf_ceiling() {  # the floor run of a toy that spins, on the busy CPU, stopped by the ceiling
		taskset -c 0 env -u NO_SKIP TEST_TIMEOUT=18 RL_MARGIN=1 PERF_TIMEOUT=8 \
			"$SH" "$TOOLS/perf_test.sh" --runner "$PERF_RUN" --student-bin "$WORK/pf/spin150" \
			--oracle "$WORK/pf/oracle.sh" --oracle-fn f --count 16000 \
			--gate-count 100 --label selftest-spin150
	}
	pf_ceiling > "$WORK/pf/ceiling.out" 2>&1
	want_out   "perf: a run the ceiling stopped is reported as the test's time" \
		'what was left of' -- cat "$WORK/pf/ceiling.out"
	want_none  "perf: ...never as PERF_TIMEOUT, which it did not use" \
		'(PERF_TIMEOUT)' -- cat "$WORK/pf/ceiling.out"
	# A MEMCHECK CASE THE CEILING STOPPED (V33). The case's own cap
	# (RUSH02_TIMEOUT, 10 s) is below what the test has left when the case
	# begins, so the runner does not clamp it; on this CPU the run's queue
	# carries its wall time to the ceiling -- what the test has left --
	# long before its own time reaches the cap. valgrind_test.sh saw
	# "ceiling" and the runner did not: the case was one more memcheck
	# failure, and the stop said each of the first cases "ended within its
	# own limit", one of them judged wrong. A converter that spins on case
	# 15, the second of the sample, under a test limit of 30 s.
	cat > "$WORK/mc/spin.c" <<'MC_SPIN'
#include <stdio.h>
#include <string.h>
int main(int ac, char **av)
{
	volatile unsigned long	x;

	if (ac != 3)
		return (1);
	x = 0;
	if (strcmp(av[2], "14") == 0)
		for (;;)
			x++;
	printf("n%s\n", av[2]);
	return (0);
}
MC_SPIN
	"$CC" -w -g -O0 -o "$WORK/mc/spin" "$WORK/mc/spin.c" 2> /dev/null
	# shellcheck disable=SC2086 # VG_PASS is several flags, split on purpose
	taskset -c 0 env -u RL_DEADLINE -u RL_BUDGET TEST_TIMEOUT=30 RL_MARGIN=1 \
		"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/mc/spin" --dict "$WORK/mc/dict.txt" \
		--oracle "$WORK/mc/oracle.sh" $VG_PASS --sample 4 > "$WORK/mc/ceiling.out" 2>&1
	echo "$?" > "$WORK/mc/ceiling.rc"
	want_red   "corpus --valgrind: on a busy CPU, a case the ceiling stopped is red" -- mc_seen ceiling
	want_out   "corpus --valgrind: ...shown as the one running when the time ran out" \
		'the one running when the time ran out' -- mc_seen ceiling
	want_out   "corpus --valgrind: ...marked as not finished, not as memcheck's" \
		'case 15 of 30  [timeout]' -- mc_seen ceiling
	want_none  "corpus --valgrind: ...and never as a case judged wrong" \
		'judged wrong before that' -- mc_seen ceiling
	# shellcheck disable=SC2086 # the busy loops' pids, one word each
	kill $_busy 2> /dev/null
	wait 2> /dev/null
else
	printf '  %-52s %s\n' "exit_status: a busy CPU's queue time" \
		"not run here (no taskset, no CPU 0 to pin to, or no /proc/PID/schedstat)"
fi

# ------------------------------------------------------------- cycles_check
# The one arm that has to actually PROFILE, which is why it is here: callgrind
# runs the program on a synthetic CPU at 20-50x native. Everything else about
# this runner -- its four skips, its argument checks -- is pinned in the fast
# suite, where none of it reaches valgrind.
#
# What this pins is the property the layer's own comment states in capitals and
# that no other arm can see: NOTHING BELOW CAN FAIL THIS TEST. A budget is
# something to think about, not a rule, so a run 15x over budget still exits 0.
# That is one `exit 1` away from turning 25 informational targets into failing
# ones, and the only thing standing in the way is a comment.
#
# noinline is load-bearing: at -O2 the compiler inlines a function this small,
# no symbol survives in the profile, and the runner SKIPs -- which would pass
# this arm while measuring nothing.
mkdir -p "$WORK/cyc"
cat > "$WORK/cyc/h.c" <<'CYC_SRC'
#include <stdio.h>
int	probe_sum(const char *s);
__attribute__((noinline)) int	probe_sum(const char *s)
{
	int	n;

	n = 0;
	while (*s)
		n += *s++;
	return (n);
}
int	main(void)
{
	char	l[4096];
	long	t;

	t = 0;
	while (fgets(l, sizeof l, stdin))
		t += probe_sum(l);
	printf("%ld\n", t);
	return (0);
}
CYC_SRC
printf '#!/bin/sh\ni=0\nwhile [ $i -lt "$3" ]; do echo "abcdefgh$i"; i=$((i+1)); done\n' \
	> "$WORK/cyc/oracle.sh"
chmod +x "$WORK/cyc/oracle.sh"

_cycout=$("$SH" "$TOOLS/cycles_check.sh" $CG_PASS --harness "$WORK/cyc/h.c" \
	--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum \
	--count 300 --budget 5 2>&1)
_cycrc=$?
if [ "$_cycrc" -ne 0 ]; then
	printf '  %-52s %s\n' "cycles_check: 15x over budget is still not a failure" \
		"FAIL < (exit $_cycrc; this layer must never fail on its numbers)"
	FAIL=$((FAIL + 1))
elif printf '%s' "$_cycout" | grep -q 'instructions'; then
	printf '  %-52s %s\n' "cycles_check: 15x over budget is still not a failure" \
		"ok (measured, and said so without failing)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "cycles_check: 15x over budget is still not a failure" \
		"FAIL < (exit 0 having profiled nothing -- SKIP in disguise)"
	FAIL=$((FAIL + 1))
fi

# And that it really attributed the count to the named function rather than to
# the whole program: the harness reads stdin and calls printf, so a per-call
# figure that swallowed those would be wildly larger.
if printf '%s' "$_cycout" | grep -q 'per call'; then
	printf '  %-52s %s\n' "cycles_check: and attributes the count to the symbol" \
		"ok (per-call figure present)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "cycles_check: and attributes the count to the symbol" \
		"FAIL < (no per-call figure; the symbol was not found)"
	FAIL=$((FAIL + 1))
fi

# Over its budget on the loop alone, it asks what the loop is doing.
printf '%s\n' "$_cycout" > "$WORK/cyc/plain.out"
want_out  "cycles_check: over budget on the loop, it asks about the loop" \
	'what is the loop doing' -- cat "$WORK/cyc/plain.out"
want_none "cycles_check: ...and shows no allocator where none ran" \
	'allocator' -- cat "$WORK/cyc/plain.out"

# WHAT THE FUNCTION'S CALLS COST, whichever of the student's functions made
# them (findings 081, 131). A toy whose loop is a few instructions a byte, but
# which asks for a block per byte and writes through a helper: the allocator is
# most of its cost. The old runner counted only the calls the symbol made
# itself, so the helpers' write() and malloc() were 0, the allocator was
# charged to the loop, and the budget line asked "what is the loop doing" of a
# loop that was within it. Now the allocator is shown apart, the figure without
# it is the one read against the budget, and a helper's calls are the
# function's. The toy's function is a --src of its own, as an exercise's is:
# the runner tells the student's calls from the harness's by file.
cat > "$WORK/cyc/alloc_fn.c" <<'CYC_SRC'
#include <stdlib.h>
#include <unistd.h>
__attribute__((noinline)) static char	*grab(size_t n)
{
	return (malloc(n));
}
__attribute__((noinline)) static void	say(const char *s)
{
	write(1, s, 0);
}
int	probe_blocks(const char *s)
{
	int		i;
	char	*p;

	i = 0;
	while (s[i])
	{
		p = grab(64);
		if (p)
			p[0] = s[i];
		free(p);
		i++;
	}
	say(s);
	return (i);
}
CYC_SRC
cat > "$WORK/cyc/alloc_h.c" <<'CYC_SRC'
#include <stdio.h>
int	probe_blocks(const char *s);
int	main(void)
{
	char	l[4096];
	long	t;

	t = 0;
	while (fgets(l, sizeof l, stdin))
		t += probe_blocks(l);
	printf("%ld\n", t);
	return (0);
}
CYC_SRC
"$SH" "$TOOLS/cycles_check.sh" $CG_PASS --harness "$WORK/cyc/alloc_h.c" \
	--src "$WORK/cyc/alloc_fn.c" \
	--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_blocks \
	--count 300 --unit-expr 'length($1)' --unit-name byte --budget 40 \
	> "$WORK/cyc/alloc.out" 2>&1
want_out  "cycles_check: the allocator's cost is shown apart" \
	'allocator         :' -- cat "$WORK/cyc/alloc.out"
want_out  "cycles_check: ...and its share of the figure is said" \
	'malloc() and free() are' -- cat "$WORK/cyc/alloc.out"
want_none "cycles_check: ...and the loop is not blamed for it" \
	'what is the loop doing' -- cat "$WORK/cyc/alloc.out"
want_out  "cycles_check: a helper's write() calls are the function's" \
	'write() calls     : 300 ' -- cat "$WORK/cyc/alloc.out"
want_none "cycles_check: ...and so are its malloc() calls" \
	'malloc() calls    : 0 ' -- cat "$WORK/cyc/alloc.out"

# A CALLBACK THE HARNESS HANDS OVER runs inside the function but is not its
# work: here it prints through stdio, whose write() calls are the harness's.
# Counting everything inside the symbol charged them to the student -- a
# btree_apply_prefix "not budgeted for a single syscall" made 73 -- so the
# callback's cost is shown apart, and its calls are not the function's.
cat > "$WORK/cyc/cb_fn.c" <<'CYC_SRC'
int	probe_apply(const char *s, void (*f)(char))
{
	int	i;

	i = 0;
	while (s[i])
		f(s[i++]);
	return (i);
}
CYC_SRC
cat > "$WORK/cyc/cb_h.c" <<'CYC_SRC'
#include <stdio.h>
int	probe_apply(const char *s, void (*f)(char));
static void	show(char c)
{
	putchar(c);
}
int	main(void)
{
	char	l[4096];
	long	t;

	t = 0;
	while (fgets(l, sizeof l, stdin))
		t += probe_apply(l, show);
	printf("%ld\n", t);
	return (0);
}
CYC_SRC
"$SH" "$TOOLS/cycles_check.sh" $CG_PASS --harness "$WORK/cyc/cb_h.c" \
	--src "$WORK/cyc/cb_fn.c" \
	--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_apply \
	--count 300 --unit-expr 'length($1)' --unit-name byte --syscall-budget 0 \
	> "$WORK/cyc/cb.out" 2>&1
want_out  "cycles_check: a harness callback's cost is shown apart" \
	'harness callback  :' -- cat "$WORK/cyc/cb.out"
want_out  "cycles_check: ...and its write() calls are not the function's" \
	'write() calls     : 0 ' -- cat "$WORK/cyc/cb.out"

# A FUNCTION THE GRADER BRINGS is the student's to call, not a callback
# (V17): C 12's ft_create_elem reaches the build as a --lib archive built by
# others, here an object compiled without debug information. The harness was
# told apart by having none, so such a function read as "the function it was
# handed" and its malloc() as not the student's.
cat > "$WORK/cyc/given.c" <<'CYC_SRC'
#include <stdlib.h>
__attribute__((noinline)) void	*probe_given(size_t n)
{
	return (malloc(n));
}
CYC_SRC
cat > "$WORK/cyc/given_fn.c" <<'CYC_SRC'
#include <stdlib.h>
void	*probe_given(size_t n);
int	probe_make(const char *s)
{
	int		i;
	char	*p;

	i = 0;
	while (s[i])
	{
		p = probe_given(16);
		if (p)
			p[0] = s[i];
		free(p);
		i++;
	}
	return (i);
}
CYC_SRC
sed 's/probe_blocks/probe_make/g' "$WORK/cyc/alloc_h.c" > "$WORK/cyc/given_h.c"
"$CC" -O2 -w -c "$WORK/cyc/given.c" -o "$WORK/cyc/given.o" 2> /dev/null
"$SH" "$TOOLS/cycles_check.sh" $CG_PASS --harness "$WORK/cyc/given_h.c" \
	--src "$WORK/cyc/given_fn.c" --lib "$WORK/cyc/given.o" \
	--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_make \
	--count 300 --unit-expr 'length($1)' --unit-name byte \
	> "$WORK/cyc/given.out" 2>&1
# One malloc() per byte of the 300 lines: 10 of 10 bytes, 90 of 11, 200 of 12.
want_out  "cycles_check: the malloc() a grader's function makes is the student's" \
	'malloc() calls    : 3490 ' -- cat "$WORK/cyc/given.out"
want_none "cycles_check: ...and that function is not a callback" \
	'harness callback' -- cat "$WORK/cyc/given.out"

# A CORPUS'S CAPACITY CASES ARE LEFT OUT WHEN ASKED (--max-unit). C 07's
# split corpus gained two strings of hundreds and thousands of words to test
# capacity (finding 041), half its bytes: the figure per byte then measured
# their mix, and nothing said so. Here one case of 3000 bytes among 299 short
# ones is left out, and the report says how many and why.
_big=""
_i=0
while [ "$_i" -lt 300 ]; do _big="${_big}xxxxxxxxxx"; _i=$((_i + 1)); done
printf '%s\n' "$_big" > "$WORK/cyc/big.txt"
printf '#!/bin/sh\n"%s" "%s" "$1" "$2" 299\ncat "%s"\n' "$SH" "$WORK/cyc/oracle.sh" \
	"$WORK/cyc/big.txt" > "$WORK/cyc/oracle_big.sh"
chmod +x "$WORK/cyc/oracle_big.sh"
want_out  "cycles_check: --max-unit leaves the capacity cases out, saying so" \
	'(1 case(s) of more than 100 bytes each left out' -- \
	"$SH" "$TOOLS/cycles_check.sh" $CG_PASS --harness "$WORK/cyc/h.c" \
		--oracle "$WORK/cyc/oracle_big.sh" --oracle-fn f --symbol probe_sum \
		--count 300 --unit-expr 'length($1)' --unit-name byte --max-unit 100
want_out  "cycles_check: ...and profiles the rest" 'cycles_check: probe_sum over 299 cases' -- \
	"$SH" "$TOOLS/cycles_check.sh" $CG_PASS --harness "$WORK/cyc/h.c" \
		--oracle "$WORK/cyc/oracle_big.sh" --oracle-fn f --symbol probe_sum \
		--count 300 --unit-expr 'length($1)' --unit-name byte --max-unit 100

# HOW THE PROFILED RUN ENDED (finding 066). callgrind ran with no limit, and
# every way it could end badly was reported as "callgrind could not profile the
# harness" -- a SKIP, exit 0 -- including a function that crashed and one that
# never returned. A crash is a crash, a hang is stopped at the test's own limit
# and said to be, and neither is blamed on the tool. alarm() bounds the spinning
# one by itself, so a regression costs 20s and not the whole target.
sed 's/n += \*s++;/n += *s++; if (n > 500) *(volatile int *)0 = 1;/' \
	"$WORK/cyc/h.c" > "$WORK/cyc/crash.c"
sed 's/t = 0;/t = 0; alarm(20); for (;;) ;/; s/#include <stdio.h>/#include <stdio.h>\
#include <unistd.h>/' "$WORK/cyc/h.c" > "$WORK/cyc/spin.c"
want_red  "cycles_check: a harness that crashes under callgrind fails" -- \
	"$SH" "$TOOLS/cycles_check.sh" $CG_PASS --harness "$WORK/cyc/crash.c" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum --count 300
want_none "cycles_check: ...and is not blamed on callgrind" 'could not profile' -- \
	"$SH" "$TOOLS/cycles_check.sh" $CG_PASS --harness "$WORK/cyc/crash.c" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum --count 300
want_out  "cycles_check: one that never ends is stopped, and said to be" \
	'did not finish within' -- \
	env TEST_TIMEOUT=8 RL_MARGIN=1 "$SH" "$TOOLS/cycles_check.sh" $CG_PASS \
		--harness "$WORK/cyc/spin.c" --oracle "$WORK/cyc/oracle.sh" --oracle-fn f \
		--symbol probe_sum --count 300
want_out  "cycles_check: a crash names its signal" 'SIGSEGV' -- \
	"$SH" "$TOOLS/cycles_check.sh" $CG_PASS --harness "$WORK/cyc/crash.c" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum --count 300
# A run too long to profile is the function's COST, which this layer never
# fails on (finding 043): reported, and red only under NO_SKIP=1, where a
# layer that measured nothing is. CYCLES_TIMEOUT is its own limit, below the
# test's.
want_green "cycles_check: a run too long to profile is a report" -- \
	env -u NO_SKIP CYCLES_TIMEOUT=3 "$SH" "$TOOLS/cycles_check.sh" $CG_PASS \
		--harness "$WORK/cyc/spin.c" --oracle "$WORK/cyc/oracle.sh" --oracle-fn f \
		--symbol probe_sum --count 300
want_none "cycles_check: ...and is not headed FAIL" 'FAIL' -- \
	env -u NO_SKIP CYCLES_TIMEOUT=3 "$SH" "$TOOLS/cycles_check.sh" $CG_PASS \
		--harness "$WORK/cyc/spin.c" --oracle "$WORK/cyc/oracle.sh" --oracle-fn f \
		--symbol probe_sum --count 300
want_red  "cycles_check: ...which NO_SKIP=1 makes red" -- \
	env NO_SKIP=1 CYCLES_TIMEOUT=3 "$SH" "$TOOLS/cycles_check.sh" $CG_PASS \
		--harness "$WORK/cyc/spin.c" --oracle "$WORK/cyc/oracle.sh" --oracle-fn f \
		--symbol probe_sum --count 300

# ----------------------------------------------------------------------- ilp32
# The layer's VERDICT -- build the same fixture at -m32, run it, diff it -- was
# tested nowhere. The fast selftest's arms stop before any 32-bit compiler runs,
# and that file's own comment claimed the functional half "belongs in a slower
# target", which read as though this one already had it. It did not.
#
# The fixture is the property the layer exists for -- arithmetic that quietly
# assumes `long` is 64 bits. That works on this LP64 box and is wrong wherever
# `long` is no wider than `int`, which C permits and 32-bit Linux does. It is a
# byte count no exercise asks for, on purpose: this file ships on the template,
# and it used to demonstrate the property on a step c-00 ex07's ft_putnbr turns
# on, the portable version and the broken one side by side.
#
# UNSIGNED arithmetic, so the broken version is well defined: on ILP32 it wraps
# modulo 2^32 and prints a wrong number every time, rather than hitting signed
# overflow or an over-wide shift, which are undefined and could print anything.
mkdir -p "$WORK/i32"
cat > "$WORK/i32/harness.c" <<'ILP32_H'
/* Line: prints the size of 5 GiB, in bytes, as a 64-bit value. */
#include <stdio.h>

long long	ft_probe_bytes(int gib);

int	main(void)
{
	printf("%lld\n", ft_probe_bytes(5));
	return (0);
}
ILP32_H
# Portable: the product is formed in a type that is 64 bits everywhere.
cat > "$WORK/i32/ok.c" <<'ILP32_OK'
long long	ft_probe_bytes(int gib)
{
	return ((long long)gib * 1073741824LL);
}
ILP32_OK
# The mistake: form it in `unsigned long`. 5368709120 on LP64; on ILP32 it wraps
# past 2^32 and comes back as 1073741824.
cat > "$WORK/i32/bad.c" <<'ILP32_BAD'
long long	ft_probe_bytes(int gib)
{
	unsigned long	b;

	b = (unsigned long)gib * 1073741824UL;
	return ((long long)b);
}
ILP32_BAD
printf '5368709120\n' > "$WORK/i32/expected.txt"

# THE 64-BIT GATE is the program *_output runs (--gate-bin), never a rebuild
# here: tools/student_build.sh makes it from the same harness and files, with
# -Wall -Wextra -Werror as every layer's build has them, into a stand-in when
# they do not build. i32_gate NAME HARNESS SRC... writes $WORK/i32/gate_NAME.
# The layer once rebuilt the files itself with every warning silenced (-w),
# and so ran -- and blamed the type model for -- code that *_output reported
# as not building.
#
# Built with the PINNED clang (--cc, its libraries on the loader's path, as
# tools/cc_toolchain/clang.sh runs it), and each gate held to what its toy is:
# a stand-in exactly for the three that do not build here -- `calls` (it
# calls a function no file it is handed defines), `narrow` (it compiles only
# where long is 32 bits) and `warns` (a warning under -Werror) -- and a
# program for every other. A host compiler that warned on a clean toy made
# its gate a stand-in, and the arm a SKIP that still passed.
I32_STANDINS=" calls narrow warns "
i32_gate() {
	_gname=$1
	_gout="$WORK/i32/gate_$1"
	_gh="$WORK/i32/$2"
	shift 2
	_gsrcs=""
	for _f in "$@"; do _gsrcs="$_gsrcs --src $WORK/i32/$_f"; done
	# shellcheck disable=SC2086
	"$SH" "$TOOLS/student_build.sh" --cc "$I32_CC" --out "$_gout" --label i32 \
		--copt -Wall --copt -Wextra --copt -Werror \
		--harness "$_gh" --harness "$TOOLS/unbuffered_stdout.c" $_gsrcs > /dev/null 2>&1 &&
		[ -f "$_gout" ] || {
		echo "selftest_slow: tools/student_build.sh wrote no 64-bit program for gate_$_gname" >&2
		exit 2
	}
	case "$I32_STANDINS" in
		*" $_gname "*)
			standin_is "$_gout" || {
				echo "selftest_slow: gate_$_gname built, and its toy is one that must not" >&2
				exit 2
			} ;;
		*)
			if standin_is "$_gout"; then
				echo "selftest_slow: gate_$_gname is a stand-in; its toy builds cleanly:" >&2
				sed -n '1,40p' "$_gout" >&2
				exit 2
			fi ;;
	esac
}

i32_run() {
	"$SH" "$TOOLS/ilp32_test.sh" --zig "$ZIG" --gate-bin "$WORK/i32/gate_$1" \
		--differ "$TOOLS/diff_output.sh" \
		--harness "$WORK/i32/harness.c" \
		--expected "$WORK/i32/expected.txt" \
		--src "$WORK/i32/$1.c"
}

# WHAT THE FOOTER MAY CLAIM. It used to be one paragraph for every red --
# "passes on the 64-bit build ... the difference is the type model" -- and it
# was false twice over. Under NO_SKIP=1 the 64-bit check was skipped, so it was
# printed over plain bugs the output layer reported in the same run; and zig's
# debug build stops a program on SIGILL at undefined behaviour, so it was
# printed over signed overflows in answers with no long anywhere. Every cause
# the footer names gets an arm where that cause is absent.
#
# A plain bug: the 64-bit build fails the same case. No long, no overflow.
cat > "$WORK/i32/offby1.c" <<'ILP32_OFF'
long long	ft_probe_bytes(int gib)
{
	return ((long long)gib * 1073741824LL + 1);
}
ILP32_OFF
# Signed overflow in plain int, the build-up-then-negate shape: the 64-bit
# build at -O0 wraps twice and lands on the expected value by accident, and
# the 32-bit build traps at the addition. There is no long in it.
cat > "$WORK/i32/ub_harness.c" <<'ILP32_UBH'
/* Line: the negated sum of 2147483640 and 8. */
#include <stdio.h>

int	ft_probe_negsum(int a, int b);

int	main(void)
{
	printf("%d\n", ft_probe_negsum(2147483640, 8));
	return (0);
}
ILP32_UBH
cat > "$WORK/i32/ub.c" <<'ILP32_UB'
int	ft_probe_negsum(int a, int b)
{
	int	s;

	s = a + b;
	return (-s);
}
ILP32_UB
printf '%s\n' -2147483648 > "$WORK/i32/ub_expected.txt"
# A call into another file: this file calls a function only a second file
# defines, handed over as another --src, as an exercise of two files is. (A
# file of ANOTHER exercise is never handed over: `deps`, and the `--` that
# carried its files here, are gone -- tools/defs.bzl, c_function.)
cat > "$WORK/i32/calls.c" <<'ILP32_CALLS'
long long	ft_probe_gib(int gib);

long long	ft_probe_bytes(int gib)
{
	return (ft_probe_gib(gib) * 1024LL);
}
ILP32_CALLS
cat > "$WORK/i32/earlier.c" <<'ILP32_EARLIER'
long long	ft_probe_gib(int gib)
{
	return ((long long)gib * 1048576LL);
}
ILP32_EARLIER
# Builds only where long is 32 bits, so the 64-bit program is a stand-in while
# the 32-bit build runs and prints the wrong thing: a path to the footer that
# says the 64-bit build does not compile either.
cat > "$WORK/i32/narrow.c" <<'ILP32_NARROW'
typedef char	t_probe_narrow[sizeof(long) == 4 ? 1 : -1];

long long	ft_probe_bytes(int gib)
{
	return ((long long)gib);
}
ILP32_NARROW
# The runs that end without a verdict on the output: a crash, a loop that
# never ends and prints nothing, and one that never ends and prints. Each is
# fine on 64-bit and goes wrong only where long is 32 bits, so the footer's
# "64-bit passes" premise holds and only its sentence about the cause varies.
# Each paragraph is checked for the words that belong to the others: a runaway
# (SIGXFSZ, 153) once fell through to "It crashed (see the CRASH line above)"
# over a report that had no CRASH line.
#
# A crash: a length that is 1 on 64-bit and wraps to about 2^32 here, read
# past the end of a table until the reads leave mapped memory.
cat > "$WORK/i32/crash.c" <<'ILP32_CRASH'
long long	ft_probe_bytes(int gib)
{
	static const char	tab[8] = {1, 1, 1, 1, 1, 1, 1, 1};
	const char			*p;
	unsigned long		n;
	unsigned long		i;
	long long			sum;

	n = (((unsigned long)gib * 1073741824UL) >> 30) - 4;
	p = tab;
	sum = 0;
	i = 0;
	while (i < n)
		sum += p[i++];
	return (sum + 5368709119LL);
}
ILP32_CRASH
# A loop: an unsigned long counted from 2^32 - 6 to 2^32 + 5. Eleven steps on
# 64-bit; here the counter wraps at 2^32 and never reaches the bound.
cat > "$WORK/i32/loop_harness.c" <<'ILP32_LOOPH'
/* Line: how many steps a counter takes from 2^32 - 6 to 2^32 + 5. */
#include <stdio.h>

long long	ft_probe_steps(int n);

int	main(void)
{
	printf("%lld\n", ft_probe_steps(5));
	return (0);
}
ILP32_LOOPH
cat > "$WORK/i32/loop.c" <<'ILP32_LOOP'
long long	ft_probe_steps(int n)
{
	unsigned long	i;
	long long		steps;

	steps = 0;
	i = 4294967290UL;
	while (i < 4294967296ULL + n)
	{
		i++;
		steps++;
	}
	return (steps);
}
ILP32_LOOP
printf '11\n' > "$WORK/i32/loop_expected.txt"
# The same loop, printing a dot per step: here it runs into diff_output.sh's
# output budget (SIGXFSZ) long before any timeout.
cat > "$WORK/i32/runaway.c" <<'ILP32_RUNAWAY'
#include <stdio.h>

long long	ft_probe_steps(int n)
{
	unsigned long	i;
	long long		steps;

	steps = 0;
	i = 4294967290UL;
	while (i < 4294967296ULL + n)
	{
		putchar('.');
		i++;
		steps++;
	}
	return (steps);
}
ILP32_RUNAWAY
printf '...........11\n' > "$WORK/i32/runaway_expected.txt"

# Two labelled cases, the second of which dies. The harness prints with printf
# and never unbuffers stdout itself: --harness-src hands the runner the library
# every output fixture links (tools/unbuffered_stdout.c), in both of its
# builds, and the row printed before the crash survives only if it arrived.
cat > "$WORK/i32/crash_harness.c" <<'ILP32_CRH'
/* Line: two labelled cases; the second one dies. */
#include <stdio.h>

long long	ft_probe_bytes(int gib);

int	main(void)
{
	printf("one\t%lld\n", ft_probe_bytes(5));
	*(volatile int *)0 = 1;
	printf("two\t%lld\n", ft_probe_bytes(5));
	return (0);
}
ILP32_CRH
printf 'one\t5368709120\ntwo\t5368709120\n' > "$WORK/i32/crash_expected.txt"

# Compiles, but only with a warning (-Wextra's unused parameter), and gets
# the type model wrong: the 64-bit program *_output runs is a stand-in, as
# -Werror makes it, and the 32-bit build (warnings shown, never fatal) runs.
cat > "$WORK/i32/warns.c" <<'ILP32_WARNS'
long long	ft_probe_bytes(int gib, int unused)
{
	unsigned long	b;

	b = (unsigned long)gib * 1073741824UL;
	return ((long long)b);
}
ILP32_WARNS
cat > "$WORK/i32/warns_harness.c" <<'ILP32_WARNSH'
/* Line: prints the size of 5 GiB, in bytes, as a 64-bit value. */
#include <stdio.h>

long long	ft_probe_bytes(int gib, int unused);

int	main(void)
{
	printf("%lld\n", ft_probe_bytes(5, 0));
	return (0);
}
ILP32_WARNSH

# i32_x NOSKIP GATE HARNESS EXPECTED SRC [ARG...]: one run with NO_SKIP set to
# NOSKIP (0 is the unforced path) over the program gate_GATE, ARG passed on as
# given -- `-- FILE` included.
i32_x() {
	_ns=$1; _g=$2; _h=$3; _e=$4; _s=$5; shift 5
	env NO_SKIP="$_ns" "$SH" "$TOOLS/ilp32_test.sh" --zig "$ZIG" \
		--gate-bin "$WORK/i32/gate_$_g" \
		--differ "$TOOLS/diff_output.sh" \
		--harness "$WORK/i32/$_h" --expected "$WORK/i32/$_e" \
		--src "$WORK/i32/$_s" "$@"
}
# The looping toy under a 2-second budget instead of diff_output.sh's 30. The
# 64-bit gate is under it too, and finishes the same loop in eleven steps.
i32_tmo() {
	env DIFF_TIMEOUT=2 "$SH" "$TOOLS/ilp32_test.sh" --zig "$ZIG" \
		--gate-bin "$WORK/i32/gate_loop" \
		--differ "$TOOLS/diff_output.sh" \
		--harness "$WORK/i32/loop_harness.c" \
		--expected "$WORK/i32/loop_expected.txt" --src "$WORK/i32/loop.c"
}
# The same run with no --gate-bin at all, as by hand: the 64-bit result is
# unknown.
i32_nocc() {
	"$SH" "$TOOLS/ilp32_test.sh" --zig "$ZIG" \
		--differ "$TOOLS/diff_output.sh" \
		--harness "$WORK/i32/harness.c" \
		--expected "$WORK/i32/expected.txt" \
		--src "$WORK/i32/$1.c"
}

if [ -n "$ZIG" ] && [ -x "$ZIG" ] && [ -n "$PCC" ] && [ -x "$PCC" ]; then
	# The pinned clang, with its own libclang-cpp and libLLVM first on the
	# loader's path, linking with the pinned ld.bfd: $CC, above (rl_cc_wrap).
	# Its own wrapper here put the libraries on the path and left the link
	# to the box's /usr/bin/ld (TO VERIFY V28).
	I32_CC="$CC"
	# Every 64-bit program the arms below hand over, as *_output would run it.
	i32_gate ok harness.c ok.c
	i32_gate bad harness.c bad.c
	i32_gate offby1 harness.c offby1.c
	i32_gate ub ub_harness.c ub.c
	i32_gate calls_two harness.c calls.c earlier.c
	i32_gate calls harness.c calls.c
	i32_gate narrow harness.c narrow.c
	i32_gate crash harness.c crash.c
	i32_gate crash_harness crash_harness.c ok.c
	i32_gate loop loop_harness.c loop.c
	i32_gate runaway loop_harness.c runaway.c
	i32_gate warns warns_harness.c warns.c

	want_green "ilp32: code that is portable passes at -m32" -- i32_run ok
	want_red   "ilp32: a product needing a 64-bit long fails at -m32" -- i32_run bad
	want_out   "ilp32: and blames the type model: 64-bit passes" \
		"the type model" -- i32_run bad
	want_none  "ilp32: and does not say the build trapped" \
		"a trap at undefined behaviour" -- i32_run bad
	want_none  "ilp32: nor that the 64-bit build fails it too" \
		"fails these same cases" -- i32_run bad

	want_red   "ilp32: NO_SKIP=1 over a plain bug is red" -- \
		i32_x 1 offby1 harness.c expected.txt offby1.c
	want_out   "ilp32: and says the 64-bit build fails it too" \
		"fails these same cases" -- i32_x 1 offby1 harness.c expected.txt offby1.c
	want_none  "ilp32: and does not blame the type model" \
		"type model" -- i32_x 1 offby1 harness.c expected.txt offby1.c
	want_green "ilp32: unforced, the same plain bug skips" -- \
		i32_x 0 offby1 harness.c expected.txt offby1.c

	want_red   "ilp32: a signed overflow with no long is red" -- \
		i32_x 0 ub ub_harness.c ub_expected.txt ub.c
	want_out   "ilp32: and says the build traps undefined behaviour" \
		"a trap at undefined behaviour" -- i32_x 0 ub ub_harness.c ub_expected.txt ub.c
	want_none  "ilp32: and does not blame the type model" \
		"type model" -- i32_x 0 ub ub_harness.c ub_expected.txt ub.c

	want_out   "ilp32: with no --gate-bin the 64-bit result is unknown" \
		"was not" -- i32_nocc bad
	want_none  "ilp32: so it does not blame the type model" \
		"type model" -- i32_nocc bad

	want_green "ilp32: a call into a second --src links" -- \
		i32_x 0 calls_two harness.c expected.txt calls.c --src "$WORK/i32/earlier.c"
	want_red   "ilp32: forced, without that file it cannot link" -- \
		i32_x 1 calls harness.c expected.txt calls.c
	want_out   "ilp32: and says the 64-bit build cannot either" \
		"the 64-bit build of the same files fails too" -- \
		i32_x 1 calls harness.c expected.txt calls.c
	want_none  "ilp32: and does not blame the type model" \
		"type model" -- i32_x 1 calls harness.c expected.txt calls.c
	want_out   "ilp32: forced, 32-bit-only code: 64-bit did not build" \
		"does not compile or link" -- \
		i32_x 1 narrow harness.c expected.txt narrow.c
	want_none  "ilp32: and does not blame the type model" \
		"type model" -- i32_x 1 narrow harness.c expected.txt narrow.c
	want_green "ilp32: unforced, the same 64-bit nobuild skips" -- \
		i32_x 0 narrow harness.c expected.txt narrow.c

	# CODE THAT ONLY WARNS: *_output's program is a stand-in (-Werror), and
	# this layer once rebuilt the files with -w, passed its gate, ran them and
	# said "The ordinary 64-bit build passes these cases" (TODO.md's V1).
	want_out   "ilp32: unforced, code that does not build as *_output's skips" \
		"your code does not build as a 64-bit program" -- \
		i32_x 0 warns warns_harness.c expected.txt warns.c
	want_red   "ilp32: forced, it runs and is red" -- \
		i32_x 1 warns warns_harness.c expected.txt warns.c
	want_out   "ilp32: and says the 64-bit build does not build either" \
		"does not compile or link" -- i32_x 1 warns warns_harness.c expected.txt warns.c
	want_none  "ilp32: and never says the 64-bit build passes" \
		"64-bit build passes" -- i32_x 1 warns warns_harness.c expected.txt warns.c
	want_none  "ilp32: nor blames the type model" \
		"type model" -- i32_x 1 warns warns_harness.c expected.txt warns.c

	want_out   "ilp32: --harness-src keeps the rows before a crash" \
		"1/1 passed before it" -- \
		i32_x 1 crash_harness crash_harness.c crash_expected.txt ok.c --labeled \
		--harness-src "$TOOLS/unbuffered_stdout.c"

	want_red   "ilp32: a read that wraps at 32 bits crashes" -- \
		i32_x 0 crash harness.c expected.txt crash.c
	want_out   "ilp32: and says it crashed" \
		"It crashed" -- i32_x 0 crash harness.c expected.txt crash.c
	want_none  "ilp32: and does not blame the type model" \
		"type model" -- i32_x 0 crash harness.c expected.txt crash.c
	# Two runs, not three: each waits out the 2-second budget, and the footer
	# is only ever printed on a red.
	want_out   "ilp32: a loop that wraps at 32 bits times out" \
		"did not finish in time" -- i32_tmo
	want_none  "ilp32: and does not say it crashed" \
		"crashed" -- i32_tmo
	want_red   "ilp32: a printing loop that wraps runs away" -- \
		i32_x 0 runaway loop_harness.c runaway_expected.txt runaway.c
	want_out   "ilp32: and says it never stopped printing" \
		"never stopped printing" -- \
		i32_x 0 runaway loop_harness.c runaway_expected.txt runaway.c
	want_none  "ilp32: and does not say it crashed" \
		"crashed" -- i32_x 0 runaway loop_harness.c runaway_expected.txt runaway.c

	# A PINNED TOOL THAT IS PRESENT AND WILL NOT RUN IS A WIRING ERROR.
	#
	# The zig cache used to be ${TMPDIR:-/tmp}/zig-cache-42 with no user in the
	# name. /tmp is shared on a campus box, so the second student to run the
	# suite hit AccessDenied on the first one's directory, zig failed, and the
	# layer fell through to the host compilers and then to a SKIP: all 94 ilp32
	# targets green, having compiled nothing, for everyone but the first person
	# to sit down.
	#
	# An unwritable cache is the cheapest way to reproduce "the fetched compiler
	# will not start", which is what this asserts refuses rather than skips.
	mkdir -p "$WORK/i32/rocache"
	chmod 555 "$WORK/i32/rocache"
	want_broken "ilp32: a pinned zig that cannot run refuses, never skips" \
		"will not run" -- \
		env ZIG_CACHE_HOME="$WORK/i32/rocache/denied" \
			"$SH" "$TOOLS/ilp32_test.sh" --zig "$ZIG" --gate-bin "$WORK/i32/gate_ok" \
			--differ "$TOOLS/diff_output.sh" \
			--harness "$WORK/i32/harness.c" \
			--expected "$WORK/i32/expected.txt" --src "$WORK/i32/ok.c"
	chmod 755 "$WORK/i32/rocache"
else
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no --zig or no --cc was supplied, so the ilp32 layer's" >&2
		echo "             verdict was not exercised at all." >&2
		exit 2
	}
	printf '  %-52s %s\n' "ilp32: (no pinned zig or clang supplied)" "skipped"
fi

# ------------------------------------------------------------ shell-01 checks
# Shell 01 ex07's and ex08's check scripts, with //oracle's references and the
# preload library they run with in the suite: that each reference judges a
# program's output, property by property, and never prints what it computes.
# The arms run the checks through shell_test.sh, as a module does, on toy
# generators whose programs print fixed words or hand their input to //oracle
# itself: none of them answers either exercise. ex08's reference prints its
# sum, so a program that calls it is a correct one, and each mistake the
# finding named is made around that same call, one at a time: the pair that
# names it fails and the program is otherwise right (finding 033). ex07's
# reference only judges, so its green is the module's own run on real
# answers. What each reference computes is checked by its own tables
# (oracle/src/shell01.rs, `oracle check`).
ROOT=$(cd "$TOOLS/.." && pwd)
S01=$ROOT/c-piscine/c-piscine-shell-01/tests
if [ -n "$ORACLE" ] && [ -x "$ORACLE" ] && [ -n "$REDIRECT_LIB" ] && [ -f "$REDIRECT_LIB" ]; then
	ORACLE=$(cd "$(dirname "$ORACLE")" && pwd)/$(basename "$ORACLE")
	REDIRECT_LIB=$(cd "$(dirname "$REDIRECT_LIB")" && pwd)/$(basename "$REDIRECT_LIB")
	mkdir -p "$WORK/s01"
	# gen_print NAME WORDS: a generator whose program prints WORDS, a
	# backslash escape in them read as printf's %b reads one.
	gen_print() {
		printf '%s\n' '#!/bin/sh' \
			"printf '%s\\n' 'printf \"%b\" \"$2\"' > $1" "chmod +x $1" > "$WORK/s01/gen-$1"
	}
	# gen_prog NAME LINE...: a generator whose program is the LINEs.
	gen_prog() {
		_gp=$1
		shift
		{
			printf '%s\n' '#!/bin/sh' "cat > $_gp <<'PROG'"
			printf '%s\n' "$@"
			printf '%s\n' 'PROG' "chmod +x $_gp"
		} > "$WORK/s01/gen-$_gp"
	}
	# s01 NAME ARG...: the check through shell_test.sh, on gen-NAME. Its
	# variable is its own: want_red and want_green keep the arm's name in
	# _name while they run it, and print it afterwards.
	s01() {
		_s01_d=$1
		shift
		env -u NO_SKIP "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/s01/gen-$_s01_d" \
			--mode check --check-lib "$TOOLS/shell_check.sh" --oracle "$ORACLE" \
			--deliverable "$_s01_d" "$@"
	}
	ex07() {
		s01 r_dwssap.sh --redirect "/etc/passwd=$S01/ex07/passwd" \
			--redirect-lib "$REDIRECT_LIB" "$@"
	}
	gen_print r_dwssap.sh 'zz, yy.'
	want_red "shell-01 ex07: names that are no login fail" -- \
		ex07 --check "$S01/ex07/check.sh"
	want_out "shell-01 ex07: ...on the property they break" \
		"[FAIL] each name is a login from the file, reversed" -- \
		ex07 --check "$S01/ex07/check.sh"
	want_out "shell-01 ex07: ...and not on one they keep" \
		"[PASS] comments are removed: no comment line is printed as a name" -- \
		ex07 --check "$S01/ex07/check.sh"
	want_out "shell-01 ex07: the program read the fixture as /etc/passwd" \
		"/etc/passwd, for every run but the last, is" -- \
		ex07 --check "$S01/ex07/check.sh"
	want_out "shell-01 ex07: ...and the machine's own file last" \
		"[FAIL] on this machine's own /etc/passwd too" -- \
		ex07 --check "$S01/ex07/check.sh"
	want_red "shell-01 ex07 literal: the same names fail the window" -- \
		ex07 --check "$S01/ex07/literal.sh"
	# The fixture shows every step only while it keeps its comment lines, its
	# 15 names and its two orders: a copy with the comments taken out is the
	# harness's fault, said as such (exit 2), never a verdict on a program.
	grep -v '^#' "$S01/ex07/passwd" > "$WORK/s01/passwd_nocomments"
	want_broken "shell-01 ex07: a fixture that lost its comments is refused" \
		'no longer shows every step (comment-first comment-later)' -- \
		s01 r_dwssap.sh --redirect "/etc/passwd=$WORK/s01/passwd_nocomments" \
			--redirect-lib "$REDIRECT_LIB" --check "$S01/ex07/check.sh"
	# Without the fixture the steps it shows cannot be judged: skipped, and
	# said, never passed.
	want_out "shell-01 ex07: no redirect: the fixture's steps are skipped" \
		"[SKIP] comments are removed" -- \
		s01 r_dwssap.sh --check "$S01/ex07/check.sh"

	# ex08: a program that prints the zero digit for every pair. Right for
	# the zero sum, and for no other class the check names, which shows the
	# classes are told apart, and that a failing pair is named by its input.
	gen_print add_chelou.sh 'g\n'
	want_red "shell-01 ex08: the zero digit for every pair fails" -- \
		s01 add_chelou.sh --check "$S01/ex08/check.sh"
	want_out "shell-01 ex08: ...but not on the zero sum" "[PASS] a zero sum" -- \
		s01 add_chelou.sh --check "$S01/ex08/check.sh"
	want_out "shell-01 ex08: ...and on a long sum" "[FAIL] a sum more than 70 digits long" -- \
		s01 add_chelou.sh --check "$S01/ex08/check.sh"
	want_out "shell-01 ex08: ...naming the input to run it again" \
		"to run it again, from a folder holding a file named q" -- \
		s01 add_chelou.sh --check "$S01/ex08/check.sh"

	# ex08 against the reference itself. The program hands its input to
	# //oracle (ck_run's runs inherit $ORACLE from shell_test.sh), so it is
	# right on every pair; the checks may say nothing else of it.
	ex08() { s01 add_chelou.sh --check "$S01/ex08/check.sh"; }
	gen_prog add_chelou.sh '"$ORACLE" shell01_chelou'
	want_green "shell-01 ex08: the reference's own sum passes every pair" -- ex08
	# A sum folded onto lines of 69 characters, each but the last ending in
	# a backslash (finding 033's mutation): the subject's two examples are
	# short, and pass.
	gen_prog add_chelou.sh '"$ORACLE" shell01_chelou | fold -w 69 | sed '"'"'$!s/$/\\/'"'"
	want_red "shell-01 ex08: a sum folded onto two lines fails" -- ex08
	want_out "shell-01 ex08: ...on the long sum" "[FAIL] a sum more than 70 digits long" -- ex08
	want_out "shell-01 ex08: ...and on nothing shorter" "[PASS] operands of very different lengths" -- ex08
	want_out "shell-01 ex08: ...where both examples pass" \
		"[PASS] Example 2: the subject's result for operands larger than a 64-bit word" -- ex08
	# The same program, reading its stdin first. The check runs the pairs in
	# a loop that reads their list on stdin, and a program that inherited it
	# swallowed every pair after the first: PASS 7/7, the long sum never run.
	gen_prog add_chelou.sh 'cat > /dev/null' \
		'"$ORACLE" shell01_chelou | fold -w 69 | sed '"'"'$!s/$/\\/'"'"
	want_red "shell-01 ex08: a program that reads its stdin runs every pair" -- ex08
	want_out "shell-01 ex08: ...and still fails on the long sum" \
		"[FAIL] a sum more than 70 digits long" -- ex08
	# FT_NBR1 read through printf's %b, which turns two backslashes into
	# one: neither example has two side by side.
	gen_prog add_chelou.sh 'FT_NBR1=$(printf '"'"'%b'"'"' "$FT_NBR1") "$ORACLE" shell01_chelou'
	want_out "shell-01 ex08: backslash escapes read in FT_NBR1 fail" \
		"[FAIL] backslashes side by side in FT_NBR1" -- ex08
	want_out "shell-01 ex08: ...where both examples pass" \
		"[PASS] Example 1: the subject's result for its first pair" -- ex08
	# FT_NBR1 expanded unquoted: a lone '?' matches the one-letter file in
	# the folder the check runs from.
	gen_prog add_chelou.sh 'set -- $FT_NBR1' 'FT_NBR1=$1 "$ORACLE" shell01_chelou'
	want_out "shell-01 ex08: FT_NBR1 expanded as a pattern fails" \
		"[FAIL] a lone '?' as FT_NBR1" -- ex08
	want_out "shell-01 ex08: ...and passes the pairs no file matches" \
		"[PASS] question marks in FT_NBR1" -- ex08
else
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no --oracle or --redirect-lib was supplied, so the" >&2
		echo "             Shell 01 check scripts were not exercised." >&2
		exit 2
	}
	printf '  %-52s %s\n' "shell-01 checks: (no oracle or preload library)" "skipped"
fi

printf '\n  %d checks passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || {
	printf '\n  A runner stopped detecting the thing it exists to detect. That is\n'
	printf '  worse than a red exercise: every test using it now reports OK\n'
	printf '  without checking. Fix the runner before trusting any suite result.\n'
	exit 1
}
exit 0
