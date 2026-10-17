#!/bin/sh
# selftest_slow.sh — the same question as selftest.sh, for the runners that are
# too expensive to ask it of on every build.
#
# WHY IT IS SEPARATE.
# selftest.sh's arms are short processes (a compile, a run, a diff), and it is
# sharded so that each run stays inside its timeout. The runners here cost more
# per arm, and in what they pull in: valgrind runs the program at 20-50x native,
# by design, zig's first compile into an empty cache takes seconds, and the
# Shell 01 arms and C 02 ex10's fixture arm need //oracle's Rust build.
# Folding them in would put that cost and those dependencies on every run of
# the check people run most, and a self-test nobody runs protects nothing.
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
require awk basename cat chmod cmp cp dirname env fold grep ln mkdir mktemp od readlink rm sed sleep

# A test's scratch files go under TEST_TMPDIR, which Bazel empties, and not
# in the machine's /tmp, the TMPDIR Bazel sets when the shell that ran it set
# none (tools/runner_lib.sh, "THE SCRATCH FOLDER").
case ${TMPDIR:-/tmp} in /tmp | /tmp/) [ -z "${TEST_TMPDIR:-}" ] || export TMPDIR="$TEST_TMPDIR" ;; esac

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
STRLCPY_STANDINS=""
STRLCAT_STANDINS=""

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
		# The archive of //oracle:c02_strlcpy_standins, for the arm that
		# builds C 02 ex10's output fixture over each of its two functions.
		--strlcpy-standins) need "$1" "$#"; STRLCPY_STANDINS="$2"; shift 2 ;;
		# The archive of //oracle:c03_strlcat_standins, for the same arm over
		# C 03 ex05's output fixture.
		--strlcat-standins) need "$1" "$#"; STRLCAT_STANDINS="$2"; shift 2 ;;
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
#
# And as there, under every FAIL line, the first lines of what the command
# said (TO VERIFY V172): an arm that dropped them left the log only its
# status, and one that passed when it must not -- the perf gate's arm, twice
# under load (TO VERIFY V235) -- left nothing to say how. _st_said shows them
# through runner_lib.sh's rl_excerpt, as every layer shows bytes, from a
# scratch file of the call's own; want_red and want_green write to a file,
# not to `$(...)`, which would wait on a background child the command left.
#
# _st_said FILE -- the excerpt, under the FAIL line just printed.
_st_said() {
	if [ ! -s "$1" ]; then
		printf '      (it said nothing)\n'
		return 0
	fi
	# shellcheck disable=SC2016 # the script is for the inner shell to expand
	RL_NAME=selftest_slow "${SH:-sh}" -c '. "$1"; rl_excerpt "$2" 5 "$3" "      | "' \
		_ "$TOOLS/runner_lib.sh" "$1" "selftest-${1##*/}.txt"
}
# _st_said_text TEXT -- the same, for words an arm captured in a variable.
_st_said_text() {
	_st_sf=$(mktemp "$WORK/said.XXXXXX") || return 0
	[ -z "$1" ] || printf '%s\n' "$1" > "$_st_sf"
	_st_said "$_st_sf"
	rm -f "$_st_sf"
}
want_red() {
	_name="$1"; shift; [ "$1" = "--" ] && shift
	_st_f=$(mktemp "$WORK/said.XXXXXX") || _st_f=/dev/null
	"$@" > "$_st_f" 2>&1
	_rc=$?
	case "$_rc" in
		1)
			printf '  %-52s %s\n' "$_name" "ok (red, as required)"
			PASS=$((PASS + 1)) ;;
		0)
			printf '  %-52s %s\n' "$_name" "FAIL < (passed; it must not)"
			FAIL=$((FAIL + 1))
			_st_said "$_st_f" ;;
		*)
			printf '  %-52s %s\n' "$_name" \
				"FAIL < (exit $_rc = harness error; nothing was checked)"
			FAIL=$((FAIL + 1))
			_st_said "$_st_f" ;;
	esac
	[ "$_st_f" = /dev/null ] || rm -f "$_st_f"
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
		_st_said_text "$_out"
	elif printf '%s' "$_out" | grep -qF -- "$_pat"; then
		printf '  %-52s %s\n' "$_name" "ok (refused, and said why)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_name" "FAIL < (refused without saying '$_pat')"
		FAIL=$((FAIL + 1))
		_st_said_text "$_out"
	fi
}
# A red (exit 1) is not a harness error (2 or more), here either.
want_green() {
	_name="$1"; shift; [ "$1" = "--" ] && shift
	_st_f=$(mktemp "$WORK/said.XXXXXX") || _st_f=/dev/null
	"$@" > "$_st_f" 2>&1
	_rc=$?
	case "$_rc" in
		0)
			printf '  %-52s %s\n' "$_name" "ok (green, as required)"
			PASS=$((PASS + 1)) ;;
		1)
			printf '  %-52s %s\n' "$_name" "FAIL < (red; it must not be)"
			FAIL=$((FAIL + 1))
			_st_said "$_st_f" ;;
		*)
			printf '  %-52s %s\n' "$_name" \
				"FAIL < (exit $_rc = harness error; nothing was checked)"
			FAIL=$((FAIL + 1))
			_st_said "$_st_f" ;;
	esac
	[ "$_st_f" = /dev/null ] || rm -f "$_st_f"
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
		_st_said_text "$_out"
	elif printf '%s' "$_out" | grep -qF -- "$_pat"; then
		printf '  %-52s %s\n' "$_name" "ok (explained itself)"
		PASS=$((PASS + 1))
	else
		printf '  %-52s %s\n' "$_name" "FAIL < (never said '$_pat')"
		FAIL=$((FAIL + 1))
		_st_said_text "$_out"
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
		_st_said_text "$_out"
	elif printf '%s' "$_out" | grep -qF -- "$_pat"; then
		printf '  %-52s %s\n' "$_name" "FAIL < (said '$_pat'; it must not)"
		FAIL=$((FAIL + 1))
		_st_said_text "$_out"
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
# A machine without the test locale: a shell that warns of it on every run
# would put the warning in what the arms read, so the replay runs under C
# there, said in one line (tools/tests/selftest_locale.sh).
# shellcheck source=tools/tests/selftest_locale.sh
. "$TOOLS/tests/selftest_locale.sh"
st_locale "$SH"

# WHAT A FAILED ARM SAID (TO VERIFY V172). Proven on a toy that refuses as a
# runner does, each helper run in a subshell so its tally is not this
# file's: each shows the toy's words under its FAIL line, want_green calls
# the refusal a harness error and not a red, and want_red shows what a run
# that passed when it must not said, too. Every helper is asked, and each
# is judged on its own line, as in selftest.sh: a count over the whole log
# let one that printed the words twice hide one that printed nothing.
st_said_toy() { sh -c 'echo "selftest-toy: unknown option" >&2; exit 2'; }
st_said_passes() { sh -c 'echo "selftest-toy: it passed"'; }
# st_said_each LOG NAME... -- the NAMEs whose FAIL line in LOG is missing,
# or is not followed at once by a line of the toy's words.
st_said_each() {
	_se_log=$1
	shift
	awk -v want="$*" '
		BEGIN { n = split(want, w, " ") }
		prev != "" { if (index($0, "| selftest-toy") > 0) ok[prev] = 1; prev = "" }
		$1 ~ /^toy-/ && index($0, "FAIL <") > 0 { prev = $1 }
		END { for (i = 1; i <= n; i++) if (!(w[i] in ok)) printf "%s ", w[i] }
	' "$_se_log"
}
st_said_meta() {
	_sm=$(mktemp "$WORK/said_meta.XXXXXX") || return 2
	(
		PASS=0
		FAIL=0
		want_red   "toy-red" -- st_said_toy
		want_green "toy-green" -- st_said_toy
		want_out   "toy-out" 'never printed' -- st_said_toy
		want_broken "toy-broken" 'never printed' -- st_said_toy
		want_none  "toy-none" 'never printed' -- st_said_toy
		want_red   "toy-passes" -- st_said_passes
	) > "$_sm" 2>&1
	_sm_miss=$(st_said_each "$_sm" toy-red toy-green toy-out toy-broken toy-none \
		toy-passes)
	_sm_rc=0
	if [ -n "$_sm_miss" ]; then
		echo "no words under the FAIL line of: $_sm_miss"
		_sm_rc=1
	fi
	if ! grep 'toy-green' "$_sm" | grep -qF 'harness error'; then
		echo "want_green did not call exit 2 a harness error"
		_sm_rc=1
	fi
	if ! grep -qF 'selftest-toy: it passed' "$_sm"; then
		echo "want_red did not show what a run that passed said"
		_sm_rc=1
	fi
	[ "$_sm_rc" = 0 ] || cat "$_sm"
	rm -f "$_sm"
	return "$_sm_rc"
}
want_green "selftest_slow: a failed arm shows what its command said" -- st_said_meta

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

# A TOY THAT DID NOT BUILD (TO VERIFY V287). Every toy below was built with
# its compiler's words sent to /dev/null and its result never looked at, so
# one that did not build turned its arms into tests of a missing file. A
# runner that calls a --bin it cannot run a red (rush02_check.sh,
# bsq_check.sh) passed every want_red arm over it, a want_none arm stayed
# quiet on the refusal, and a missing cpu_spin skipped the busy-CPU block
# under a reason that was not true. So each toy is built by toy_cc, which
# says when one did not build, as a FAIL of its own with the compiler's
# words under it, and prints nothing when it did, so the count of a good
# run does not move. //tools:conventions refuses a toy built here with its
# compiler's words thrown away.
#
# toy_cc OUT CC-ARGS... -- "$CC" CC-ARGS -o OUT; 0 when OUT was built, and
# 1 and a FAIL line when it was not.
toy_cc() {
	_tc_out=$1
	shift
	_tc_err=$(mktemp "$WORK/toycc.XXXXXX") || _tc_err=/dev/null
	rm -f "$_tc_out"
	"$CC" "$@" -o "$_tc_out" > "$_tc_err" 2>&1
	_tc_rc=$?
	if [ "$_tc_rc" -eq 0 ] && [ -s "$_tc_out" ]; then
		[ "$_tc_err" = /dev/null ] || rm -f "$_tc_err"
		return 0
	fi
	printf '  %-52s %s\n' "toy ${_tc_out#"$WORK"/}" \
		"FAIL < (the toy did not build: the compiler's exit $_tc_rc)"
	FAIL=$((FAIL + 1))
	_st_said "$_tc_err"
	[ "$_tc_err" = /dev/null ] || rm -f "$_tc_err"
	return 1
}
# Proven on two invented toys, in a subshell with a tally of its own: one
# that is not C is one FAIL line with the compiler's error under it, and
# one that builds prints nothing and counts nothing.
toy_cc_meta() {
	_tm=$(mktemp "$WORK/toycc_meta.XXXXXX") || return 2
	mkdir -p "$WORK/toycc"
	printf 'int main(void){ this is not C }\n' > "$WORK/toycc/bad.c"
	printf 'int main(void){ return (0); }\n' > "$WORK/toycc/good.c"
	(
		PASS=0
		FAIL=0
		toy_cc "$WORK/toycc/bad" -w "$WORK/toycc/bad.c"
		echo "after bad: status $? FAIL $FAIL PASS $PASS"
		toy_cc "$WORK/toycc/good" -w "$WORK/toycc/good.c"
		echo "after good: status $? FAIL $FAIL PASS $PASS"
	) > "$_tm" 2>&1
	_tm_rc=0
	if [ "$(grep -c 'FAIL < (the toy did not build' "$_tm")" != 1 ] ||
		! grep -q '^  toy toycc/bad  *FAIL < (the toy did not build' "$_tm"; then
		echo "not one FAIL line naming toycc/bad"
		_tm_rc=1
	fi
	if ! awk 'prev { if ($0 ~ /^      \| .*error/) ok = 1; prev = 0 }
		/FAIL < \(the toy did not build/ { prev = 1 } END { exit !ok }' "$_tm"; then
		echo "no line of the compiler's error under the FAIL line"
		_tm_rc=1
	fi
	grep -qx 'after bad: status 1 FAIL 1 PASS 0' "$_tm" || {
		echo "the toy that is not C was not status 1 and one FAIL"
		_tm_rc=1
	}
	grep -qx 'after good: status 0 FAIL 1 PASS 0' "$_tm" || {
		echo "the toy that builds was not status 0, or it counted"
		_tm_rc=1
	}
	[ "$_tm_rc" = 0 ] || cat "$_tm"
	rm -f "$_tm"
	return "$_tm_rc"
}
want_green "selftest_slow: a toy that does not build is a FAIL, with the compiler's words" -- \
	toy_cc_meta

printf 'selftest_slow: does each expensive layer still detect what it exists to detect?\n\n'

# THE STAND-IN. When a student's code does not build, tools/student_build.sh
# writes a stand-in that prints the compiler's words (tools/standin.sh), and
# every layer here meets it: valgrind's arms and perf's read it. Written by the
# builder itself, so an arm fails if either side's wording drifts, and before
# the first section, so it is no section's fixture.
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
toy_cc "$WORK/vg_stack" -w -g -O0 -fno-stack-protector "$WORK/vg_stack.c"

for _p in vg_clean vg_leak vg_oob vg_uninit vg_fdleak vg_fdok vg_fdleak_rc; do
	toy_cc "$WORK/$_p" -w -g -O0 "$WORK/$_p.c"
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
# valgrind_test.sh sources tools/runner_lib.sh, which probes the tools of
# its own `for _rl_t in` line near its top, so this list holds them too.
for _t in sh "$SH" awk basename cat chmod cp date env fold grep head mkdir mktemp od rm sed dirname readlink; do
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

# A program that never built is not a memory report: valgrind over the
# stand-in (STANDIN_BIN, above) would report on /bin/sh.
want_red "valgrind: a stand-in is red, not a memory report" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$STANDIN_BIN"
want_out "valgrind: ...says the code did not build" 'your code did not build' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$STANDIN_BIN"

# THE HOST'S VALGRIND SETTINGS (V227). valgrind reads ~/.valgrindrc,
# $VALGRIND_OPTS and ./.valgrindrc before its command line, which overrides
# only the options it names. Each of these hid the leak: another tool (OK),
# a suppression file that matches every leak of a malloc, from VALGRIND_OPTS
# or from ~/.valgrindrc (OK), and an option that conflicts with the runner's
# own, which made valgrind refuse to start (no verdict, exit 2). The runner
# clears them (tools/runner_lib.sh, rl_vg_env), so the leak stays red.
printf '{\n   toy_every_leak\n   Memcheck:Leak\n   match-leak-kinds: all\n   fun:malloc\n   ...\n}\n' \
	> "$WORK/vg_all.supp"
mkdir -p "$WORK/vg_rchome"
printf -- '--suppressions=%s\n' "$WORK/vg_all.supp" > "$WORK/vg_rchome/.valgrindrc"
want_red "valgrind: a leak stays red under VALGRIND_OPTS=--tool=none" -- \
	env VALGRIND_OPTS=--tool=none "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_leak"
want_red "valgrind: ...and under a suppression file in VALGRIND_OPTS" -- \
	env VALGRIND_OPTS="--suppressions=$WORK/vg_all.supp" \
		"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_leak"
want_red "valgrind: ...and under one in ~/.valgrindrc" -- \
	env HOME="$WORK/vg_rchome" "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_leak"
want_red "valgrind: ...and under an option valgrind would refuse" -- \
	env VALGRIND_OPTS=--undef-value-errors=no \
		"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_leak"
# And DEBUGINFOD_URLS (V270): with it set, memcheck runs debuginfod-find
# from PATH for each object it has no debug information for, so what it
# loads, and whether it asks a server at all, would be the host's. A
# stand-in debuginfod-find first on PATH writes down that it ran: it does
# when memcheck is started by hand, and never through the runner. The
# program is vg_clean built without -g, so its build id is a fresh one no
# machine holds debug information for: memcheck asks about it wherever the
# arms run, whatever debug files the host has for valgrind's own libraries.
# Each arm prints the command's status too, so a runner that stopped before
# memcheck ran cannot pass for one that kept the variable from it.
toy_cc "$WORK/vg_nog" -w -O0 "$WORK/vg_clean.c"
mkdir -p "$WORK/vg_dfind"
printf '#!/bin/sh\necho "$*" >> "${0%%/*}/ran"\nexit 1\n' > "$WORK/vg_dfind/debuginfod-find"
chmod +x "$WORK/vg_dfind/debuginfod-find"
vg_dfind() {  # vg_dfind CMD...: CMD under a host's debuginfod settings
	rm -f "$WORK/vg_dfind/ran"
	env DEBUGINFOD_URLS=http://debuginfod.invalid PATH="$WORK/vg_dfind:$PATH" "$@" > /dev/null 2>&1
	_vgd_rc=$?
	if [ -e "$WORK/vg_dfind/ran" ]; then _vgd=run; else _vgd="not run"; fi
	echo "rc=$_vgd_rc debuginfod-find: $_vgd"
}
want_out "valgrind: a DEBUGINFOD_URLS reaching memcheck runs debuginfod-find" \
	'rc=0 debuginfod-find: run' -- \
	vg_dfind env VALGRIND_LIB="$(dirname "$(readlink -f "$VGTOOLS")")" "$VALGRIND" -q "$WORK/vg_nog"
want_out "valgrind: ...and the runner never lets it reach memcheck" \
	'rc=0 debuginfod-find: not run' -- \
	vg_dfind "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_nog"

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

# A SUBJECT THAT SAYS ONE THING OF A LEAK AND ANOTHER OF AN INVALID ACCESS
# (--access-rule, a contract's memory_graded): each red quotes the sentence
# its finding breaks, once -- the access one for an invalid read, a crash or
# any finding that is no leak, --rule's for a leak, both for a run showing
# both. It quoted the leak sentence over every finding, an invalid read and
# a probe that checks no leak among them.
printf 'Toy, p.4: "Touch only what you own."\n' > "$WORK/vg_access.txt"
printf '#include <stdlib.h>\nint main(void){char*p=malloc(4);char c=p[4];malloc(8);free(p);return (c==0);}\n' \
	> "$WORK/vg_both.c"
printf '#include <stdlib.h>\nint main(void){volatile char*p=0;return (*p);}\n' > "$WORK/vg_crash.c"
# A finding this layer names no class for (a "fishy" size) beside a leak, and
# a crash with a block still held when it was killed: the first quotes both
# sentences, the second the access one alone -- a block a killed process never
# got to free is no leak it made.
printf '#include <stdlib.h>\nint main(void){volatile size_t n=(size_t)-8;malloc(n);malloc(32);return (0);}\n' \
	> "$WORK/vg_fishy.c"
printf '#include <stdlib.h>\nchar*g;int main(void){volatile char*p=0;g=malloc(16);return (*p);}\n' \
	> "$WORK/vg_crash_held.c"
# The same finding made by a forked child, before its parent leaks: the log
# holds the child's ERROR SUMMARY, then the parent's, and only the last one
# was counted, so the child's finding quoted the leak sentence alone.
printf '#include <stdlib.h>\n#include <unistd.h>\n#include <sys/wait.h>\nint main(void){volatile size_t n=(size_t)-8;pid_t p=fork();if(p==0){malloc(n);return (0);}waitpid(p,0,0);malloc(8);malloc(16);return (0);}\n' \
	> "$WORK/vg_fork_fishy.c"
for _p in vg_both vg_crash vg_fishy vg_crash_held vg_fork_fishy; do
	toy_cc "$WORK/$_p" -w -g -O0 "$WORK/$_p.c"
done
vg_rules() {  # vg_rules BIN [FLAG]... -- one run, with both sentences
	_vr_bin=$1; shift
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --rule "$WORK/vg_rule.txt" \
		--access-rule "$WORK/vg_access.txt" "$@" --bin "$WORK/$_vr_bin"
}
# One run per program, each read by several arms (a memcheck run is seconds).
for _p in vg_oob vg_leak vg_both vg_crash vg_fishy vg_crash_held vg_fork_fishy; do
	vg_rules "$_p" > "$WORK/$_p.rules.out" 2>&1
	echo "$?" > "$WORK/$_p.rules.rc"
done
# A leak beside a block valgrind was told to suppress: the ERROR SUMMARY ends
# "(suppressed: 1 from 1)", and the count of contexts read the "from" in it
# too, so a run that only leaks counted two contexts for one loss record and
# quoted the access sentence beside the leak one. Which blocks are suppressed
# is the host's (its default suppressions), so the arm suppresses one itself.
printf '#include <stdlib.h>\nvoid*g;__attribute__((noinline)) void*toy_hidden_take(void){return (malloc(24));}\nint main(void){g=toy_hidden_take();g=0;malloc(8);return (0);}\n' \
	> "$WORK/vg_supp.c"
printf '{\n   toy_hidden\n   Memcheck:Leak\n   match-leak-kinds: all\n   fun:malloc\n   fun:toy_hidden_take\n}\n' \
	> "$WORK/vg_supp.supp"
toy_cc "$WORK/vg_supp" -w -g -O0 "$WORK/vg_supp.c"
# The suppression goes in through valgrind's own tree, a copy of it whose
# default.supp (read from $VALGRIND_LIB) adds the toy's entry. It went in
# through VALGRIND_OPTS, which the runner now clears (V227). The tool is a
# copy, not a link: the runner resolves --valgrind-tools to find the tree.
_vg_tree=$(dirname "$(readlink -f "$VGTOOLS")")
mkdir -p "$WORK/vg_supp_lib"
for _f in memcheck-amd64-linux vgpreload_core-amd64-linux.so vgpreload_memcheck-amd64-linux.so; do
	cp "$_vg_tree/$_f" "$WORK/vg_supp_lib/$_f"
done
cat "$_vg_tree/default.supp" "$WORK/vg_supp.supp" > "$WORK/vg_supp_lib/default.supp" 2> /dev/null
"$SH" "$TOOLS/valgrind_test.sh" --valgrind "$VALGRIND" \
	--valgrind-tools "$WORK/vg_supp_lib/memcheck-amd64-linux" \
	--rule "$WORK/vg_rule.txt" --access-rule "$WORK/vg_access.txt" \
	--bin "$WORK/vg_supp" > "$WORK/vg_supp.rules.out" 2>&1
echo "$?" > "$WORK/vg_supp.rules.rc"
vg_rules_seen() { cat "$WORK/$1.rules.out"; return "$(cat "$WORK/$1.rules.rc")"; }
vg_rules_count() {  # vg_rules_count RUN TEXT -- how many lines of RUN's report hold TEXT
	printf 'lines: %s\n' "$(grep -cF -- "$2" "$WORK/$1.rules.out")"
}
want_out  "valgrind --access-rule: an invalid read quotes the access sentence" \
	'Touch only what you own' -- vg_rules_seen vg_oob
want_none "valgrind --access-rule: ...never the leak sentence" 'Free what you take' -- \
	vg_rules_seen vg_oob
want_out  "valgrind --access-rule: a leak quotes the leak sentence" 'Free what you take' -- \
	vg_rules_seen vg_leak
want_none "valgrind --access-rule: ...never the access sentence" 'Touch only what you own' -- \
	vg_rules_seen vg_leak
want_out  "valgrind --access-rule: a run with both quotes the access one once" 'lines: 1' -- \
	vg_rules_count vg_both 'Touch only what you own'
want_out  "valgrind --access-rule: ...and the leak one once" 'lines: 1' -- \
	vg_rules_count vg_both 'Free what you take'
want_red  "valgrind --access-rule: a crash is red" -- vg_rules_seen vg_crash
want_out  "valgrind --access-rule: ...quoting the access sentence" 'Touch only what you own' -- \
	vg_rules_seen vg_crash
want_out  "valgrind --access-rule: a finding of no named class beside a leak quotes the access one" \
	'lines: 1' -- vg_rules_count vg_fishy 'Touch only what you own'
want_out  "valgrind --access-rule: ...and the leak one" 'lines: 1' -- \
	vg_rules_count vg_fishy 'Free what you take'
want_out  "valgrind --access-rule: ...made by a forked child, the access one too" \
	'lines: 1' -- vg_rules_count vg_fork_fishy 'Touch only what you own'
want_out  "valgrind --access-rule: ...beside its parent's leak sentence" 'lines: 1' -- \
	vg_rules_count vg_fork_fishy 'Free what you take'
want_out  "valgrind --access-rule: (the toy's block was suppressed, so the arms below run)" \
	'(suppressed: 1 from 1)' -- vg_rules_seen vg_supp
want_out  "valgrind --access-rule: a leak beside a suppressed block quotes the leak sentence" \
	'lines: 1' -- vg_rules_count vg_supp 'Free what you take'
want_out  "valgrind --access-rule: ...and never the access one" 'lines: 0' -- \
	vg_rules_count vg_supp 'Touch only what you own'
want_red  "valgrind --access-rule: a crash holding a block is red" -- vg_rules_seen vg_crash_held
want_out  "valgrind --access-rule: ...quoting the access sentence" 'Touch only what you own' -- \
	vg_rules_seen vg_crash_held
want_none "valgrind --access-rule: ...never the leak one, for a block it was killed holding" \
	'Free what you take' -- vg_rules_seen vg_crash_held
# Without --access-rule, as before it: a crash quotes nothing, and the leak
# sentence is the one rule (the arms above).
want_none "valgrind: without --access-rule a crash quotes no sentence" 'The sentence this applies' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --rule "$WORK/vg_rule.txt" --bin "$WORK/vg_crash"
want_out  "valgrind: ...and an invalid read quotes --rule" 'Free what you take' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --rule "$WORK/vg_rule.txt" --bin "$WORK/vg_oob"

# THE TIME BUDGET (finding 066). VALGRIND_TIMEOUT is 60s, which is the whole of
# a small test's limit -- and the output gate runs before it -- so a program
# that never ends was killed by Bazel, with nothing in the log. Each run now
# gets what is left of the test's own limit when that is less, and says so.
# alarm() ends the loop by itself after 20s, so a regression here costs a
# bounded wait and not the whole target.
printf '#include <unistd.h>\nint main(void){alarm(20);for(;;);}\n' > "$WORK/vg_spin.c"
toy_cc "$WORK/vg_spin" -w -g -O0 "$WORK/vg_spin.c"
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
# want_broken_none is selftest.sh's and does not exist here (want_none is this
# file's counterpart), and when these arms were written want_out did not
# either. Calling a helper the file does not define is not an error the shell
# reports usefully: it is "not found", exit 127, swallowed, and the arm
# silently does not run. Three of these arms were written against those two
# and vanished; the count went 17 to 19 instead of 17 to 22 and everything
# still said OK.
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
toy_cc "$WORK/vg_fdleak_mem" -w -g -O0 "$WORK/vg_fdleak_mem.c"
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
toy_cc "$WORK/vg_uninit_wr" -w -g -O0 "$WORK/vg_uninit_wr.c"

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
# A probe run, which checks no leak, quoting the access sentence: its red can
# be no leak, and a graded package hands it no --rule (tools/defs.bzl's
# _graded_rule).
want_out  "valgrind --no-leak-check --access-rule: quotes the access sentence" \
	'Touch only what you own' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --no-leak-check --access-rule "$WORK/vg_access.txt" \
		--bin "$WORK/vg_uninit_wr"
want_none "valgrind --no-leak-check --access-rule: ...and no leak rule at all" 'every block allocated' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --no-leak-check --access-rule "$WORK/vg_access.txt" \
		--bin "$WORK/vg_uninit_wr"
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
toy_cc "$WORK/vg_gate_ok" -w -g -O0 "$WORK/vg_gate_ok.c"
toy_cc "$WORK/vg_gate_bad" -w -g -O0 "$WORK/vg_gate_bad.c"

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
# A gate given --gate-label names the output test it stands for in its SKIP
# line, as every macro-written gate now does, rather than "this exercise's
# own output fixture", which names no test.
want_out   "valgrind: a labelled gate's SKIP names its output test" \
	"SKIP — toy_output, this exercise's own output fixture" -- \
	env -u NO_SKIP "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_gate_bad" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/vg_gate_bad" \
		--gate-expected "$WORK/gate_exp.txt" --gate-label toy_output
# A gate whose program is not there is said, and the layer runs on (V292):
# it was dropped with nothing said.
want_out   "valgrind: a gate program that is not there is said" \
	'could not be evaluated' -- \
	env -u NO_SKIP "$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_clean" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/no-such-gate" \
		--gate-expected "$WORK/gate_exp.txt"

# A SURVIVE CASE'S GATE IS ANOTHER CASE (--survive, c_program's
# _survive_gate): its exercise's first case, written out whole in --gate-arg
# words, and handed nothing of the survive case's own run. It ran ungated, so
# over a stub whose Makefile builds nothing it met the stand-in and was red at
# strict, four times over Rush 02's stub, while the asan arm of the same cases
# said SKIP (V253). The stand-in here is the one a build with nothing to
# compile writes ("NOTHING TO BUILD YET"), as a stub's is.
"$SH" "$TOOLS/student_build.sh" --cc "$CC" --out "$WORK/standin/empty" --label selftest \
	> /dev/null 2>&1 && [ -f "$WORK/standin/empty" ] || {
	echo "selftest_slow: tools/student_build.sh wrote no stand-in for a build with nothing to compile" >&2
	exit 2
}
# vg_survive skip|noskip ARG... -- NO_SKIP unset, or set to 1, in a subshell:
# a function cannot be run through env.
vg_survive() {
	(
		if [ "$1" = noskip ]; then NO_SKIP=1; export NO_SKIP; else unset NO_SKIP; fi
		shift
		"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --survive \
			--gate-differ "$TOOLS/diff_output.sh" --gate-label toy_first_output "$@"
	)
}
want_green "valgrind: a survive case SKIPs a stand-in while its gate is red" -- \
	vg_survive skip --bin "$WORK/standin/empty" \
		--gate-bin "$WORK/standin/empty" --gate-expected "$WORK/gate_exp.txt" \
		--gate-arg one -- two three
want_out   "valgrind: ...naming the case it waits on" \
	'SKIP — toy_first_output, this exercise' -- \
	vg_survive skip --bin "$WORK/standin/empty" \
		--gate-bin "$WORK/standin/empty" --gate-expected "$WORK/gate_exp.txt" \
		--gate-arg one -- two three
want_red   "valgrind: ...and NO_SKIP=1 makes that stand-in red" -- \
	vg_survive noskip --bin "$WORK/standin/empty" \
		--gate-bin "$WORK/standin/empty" --gate-expected "$WORK/gate_exp.txt" \
		--gate-arg one -- two three
want_out   "valgrind: ...saying there was nothing to build" 'nothing to build' -- \
	vg_survive noskip --bin "$WORK/standin/empty" \
		--gate-bin "$WORK/standin/empty" --gate-expected "$WORK/gate_exp.txt" \
		--gate-arg one -- two three
want_red   "valgrind: past a green survive gate, a stand-in is red" -- \
	vg_survive skip --bin "$WORK/standin/empty" \
		--gate-bin "$WORK/vg_gate_ok" --gate-expected "$WORK/gate_exp.txt"
# The gate runs its own words, never the survive case's: this toy prints the
# fixture only when its one argument is "hi", and leaks. Handed the case's
# own "zz", in place of "hi" or after it, the gate would be red and the leak
# skipped. ONE argument: diff_output.sh puts an --argv-file's words after the
# words after --, so a toy reading v[1] alone missed a gate handed the case's
# argument file (review of V253).
printf '#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\nint main(int c, char **v){malloc(64);printf(c == 2 && !strcmp(v[1], "hi") ? "hello\\n" : "wrong\\n");return (0);}\n' \
	> "$WORK/vg_gate_word.c"
toy_cc "$WORK/vg_gate_word" -w -g -O0 "$WORK/vg_gate_word.c"
want_red   "valgrind: a survive gate runs its --gate-arg words, not the case's" -- \
	vg_survive skip --bin "$WORK/vg_gate_word" \
		--gate-bin "$WORK/vg_gate_word" --gate-expected "$WORK/gate_exp.txt" \
		--gate-arg hi -- zz
want_out   "valgrind: ...so the leak is reported" 'DEFINITELY LOST' -- \
	vg_survive skip --bin "$WORK/vg_gate_word" \
		--gate-bin "$WORK/vg_gate_word" --gate-expected "$WORK/gate_exp.txt" \
		--gate-arg hi -- zz
# ...nor its argument file: the case's own --argv-file holds "zz" too.
printf 'zz\n' > "$WORK/vg_gate_word.argv"
want_red   "valgrind: ...nor the case's argument file" -- \
	vg_survive skip --bin "$WORK/vg_gate_word" \
		--gate-bin "$WORK/vg_gate_word" --gate-expected "$WORK/gate_exp.txt" \
		--gate-arg hi --argv-file "$WORK/vg_gate_word.argv"
# A gate case with no argument is still that case, never this one: this toy
# prints the fixture only when it is given no argument and is not run as
# ./toy, and leaks. A runner that chose the gate's words by "a --gate-arg was
# given" handed it the case's "two"; one that handed it the case's run flags
# ran it as ./toy. Either way the gate was red, and the leak skipped. This is
# why --survive is a flag of its own.
printf '#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\nint main(int c, char **v){malloc(64);printf(c == 1 && strcmp(v[0], "./toy") ? "hello\\n" : "wrong\\n");return (0);}\n' \
	> "$WORK/vg_gate_bare.c"
toy_cc "$WORK/vg_gate_bare" -w -g -O0 "$WORK/vg_gate_bare.c"
want_red   "valgrind: a survive gate with no word gets none of the case's" -- \
	vg_survive skip --bin "$WORK/vg_gate_bare" \
		--gate-bin "$WORK/vg_gate_bare" --gate-expected "$WORK/gate_exp.txt" \
		-- two
want_out   "valgrind: ...so the leak is reported" 'DEFINITELY LOST' -- \
	vg_survive skip --bin "$WORK/vg_gate_bare" \
		--gate-bin "$WORK/vg_gate_bare" --gate-expected "$WORK/gate_exp.txt" \
		-- two
want_red   "valgrind: ...nor the name the case runs as" -- \
	vg_survive skip --bin "$WORK/vg_gate_bare" \
		--gate-bin "$WORK/vg_gate_bare" --gate-expected "$WORK/gate_exp.txt" \
		--run-as toy
# A word for a gate that replays this run's own is a wiring mistake.
want_broken "valgrind: --gate-arg without --survive is refused" '(--survive)' -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_gate_word" \
		--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/vg_gate_word" \
		--gate-expected "$WORK/gate_exp.txt" --gate-arg hi

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
toy_cc "$WORK/vg_pc" -w -g -O0 "$WORK/vg_pc.c"
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
toy_cc "$WORK/vg_af" -w -g -O0 "$WORK/vg_af.c"
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
toy_cc "$WORK/mc/conv" -w -g -O0 "$WORK/mc/conv.c"
toy_cc "$WORK/mc/conv_ok" -w -g -O0 "$WORK/mc/conv_ok.c"
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
toy_cc "$WORK/mc/fdconv" -w -g -O0 "$WORK/mc/fdconv.c"
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
toy_cc "$WORK/mc/fdnote" -w -g -O0 "$WORK/mc/fdnote.c"
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
# With --access-rule, a corpus whose cases show an invalid read (the number
# 7) and a leak (14) quotes each sentence once, after the cases, each for
# its own kind; one whose cases only leak quotes the leak one alone.
cat > "$WORK/mc/accleak.c" <<'MC_ACCLEAK'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int ac, char **av)
{
	char	*p;

	if (ac != 3)
		return (1);
	p = malloc(2);
	p[0] = 'n';
	p[1] = 0;
	if (strcmp(av[2], "7") == 0 && p[2] == 'x')
		p[0] = 'x';
	if (strcmp(av[2], "14") != 0)
		free(p);
	printf("n%s\n", av[2]);
	return (0);
}
MC_ACCLEAK
toy_cc "$WORK/mc/accleak" -w -g -O0 "$WORK/mc/accleak.c"
printf 'Toy, p.1: "Touch only what you own."\n' > "$WORK/mc/access.txt"
# shellcheck disable=SC2086 # VG_PASS is several flags, split on purpose
for _mc in accleak fdnote; do
	env VALGRIND_FDS=lax "$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/mc/$_mc" --dict "$WORK/mc/dict.txt" \
		--oracle "$WORK/mc/oracle.sh" $VG_PASS --sample 4 --rule "$WORK/mc/rule.txt" \
		--access-rule "$WORK/mc/access.txt" > "$WORK/mc/${_mc}_acc.out" 2>&1
	echo "$?" > "$WORK/mc/${_mc}_acc.rc"
done
want_red   "corpus --valgrind --access-rule: an invalid read and a leak are red" -- mc_seen accleak_acc
want_out   "corpus --valgrind --access-rule: ...quoting the access sentence once" 'lines: 1' -- \
	mc_count accleak_acc 'Toy, p.1: "Touch only what you own."'
want_out   "corpus --valgrind --access-rule: ...and the leak sentence once" 'lines: 1' -- \
	mc_count accleak_acc 'Toy, p.1: "Free what you allocate."'
want_out   "corpus --valgrind --access-rule: a corpus that only leaks quotes the leak one" 'lines: 1' -- \
	mc_count fdnote_acc 'Toy, p.1: "Free what you allocate."'
want_out   "corpus --valgrind --access-rule: ...and never the access one" 'lines: 0' -- \
	mc_count fdnote_acc 'Touch only what you own'
# A DESCRIPTOR LEFT OPEN ON A SCRATCH FILE is named by the name the case keeps
# it under. bsq_check.sh hands the program a scratch copy of each map, and
# memcheck's stanza said "Open file descriptor 3: <TMPDIR>/tmp.XXXX/map", a
# file gone when the test ends, right below the lines that keep the map as
# case-N.map and replay it under that name; two cases named the same file.
# A toy that opens every map it is given and never closes one, over a corpus
# of four invented maps, two of them one at a time, then two runs of two,
# each kept in a test.outputs folder of its own: a name is shown only for a
# map that was kept.
cat > "$WORK/mc/mapopen.c" <<'MC_MAPOPEN'
#include <fcntl.h>
#include <unistd.h>
int main(int ac, char **av)
{
	int	i;

	i = 1;
	while (i < ac)
		open(av[i++], O_RDONLY);
	write(1, "map error\n", 10);
	return (0);
}
MC_MAPOPEN
toy_cc "$WORK/mc/mapopen" -w -g -O0 "$WORK/mc/mapopen.c"
# The corpus holds what bsq_check.sh's floors ask of one: a map whose answer
# differs from it, one with no square at all, and an invalid one.
{
	printf '#!/bin/sh\ncat <<%sEOF%s\n' "'" "'"
	printf 'ok\t1\t0\t0\t2.ox\\n..\\n.o\\n\tx.\\n.o\\n\n'
	printf 'ok\t0\t-1\t-1\t2.ox\\noo\\noo\\n\too\\noo\\n\n'
	printf 'err:chars_repeat\t-1\t-1\t-1\t2.oo\\n..\\n..\\n\tmap error\\n\n'
	printf 'ok\t1\t0\t0\t2.ox\\n.o\\n..\\n\txo\\n..\\n\n'
	printf 'EOF\n'
} > "$WORK/mc/bsq_oracle.sh"
chmod +x "$WORK/mc/bsq_oracle.sh"
# shellcheck disable=SC2086 # VG_PASS and _bg are several words, split on purpose
for _bm in argv multi; do
	_bg=""
	[ "$_bm" = argv ] || _bg="--group 2"
	env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/mc/out" TEST_TARGET=//mod:ex00_bsq_valgrind \
		"$SH" "$TOOLS/bsq_check.sh" --bin "$WORK/mc/mapopen" --oracle "$WORK/mc/bsq_oracle.sh" \
		--fixed 4 --mode "$_bm" $_bg $VG_PASS --sample 2 > "$WORK/mc/mapopen_$_bm.out" 2>&1
	echo "$?" > "$WORK/mc/mapopen_$_bm.rc"
done
want_red   "bsq --valgrind: a map left open is red" -- mc_seen mapopen_argv
want_out   "bsq --valgrind: ...its descriptor named as the map is kept" \
	': case-4.map' -- mc_seen mapopen_argv
want_out   "bsq --valgrind: ...saying the name was replaced" \
	'shown by the name it is kept under: case-4.map)' -- mc_seen mapopen_argv
want_out   "bsq --valgrind: ...in multi mode, each map of the run by its own" \
	'shown by the name it is kept under: run-2-1.map, run-2-2.map)' -- mc_seen mapopen_multi
# ...and so in the other two runners that hand the program a scratch copy,
# the same toy opening whatever it is given. file_check.sh writes each file
# of a case to a scratch folder and keeps it as case-N-fileK; its corpus
# holds what its floors ask of one (an empty file, a NUL, a file over 4096
# bytes, twenty cases), and two files a case past the third. rush02_check.sh
# writes a case's generated dictionary (a line of three fields) to a scratch
# file and keeps it as case-N.dict. Each passed its own --as and had no arm.
_mc_big=$(awk 'BEGIN { s = ""; while (length(s) < 5000) s = s "abcdefghij"; print s }')
{
	printf '#!/bin/sh\ncat <<%sEOF%s\n' "'" "'"
	printf 'file\t0\t1\t\t\n'
	printf 'file\t0\t1\ta\\0000b\ta\\0000b\n'
	printf 'file\t0\t1\t%s\t%s\n' "$_mc_big" "$_mc_big"
	_i=0
	while [ "$_i" -lt 20 ]; do
		printf 'file\t0\t2\tline%s\\n\tx\\n\tline%s\\nx\\n\n' "$_i" "$_i"
		_i=$((_i + 1))
	done
	printf 'EOF\n'
} > "$WORK/mc/fc_oracle.sh"
{
	printf '#!/bin/sh\ncat <<%sEOF%s\n' "'" "'"
	_i=0
	while [ "$_i" -lt 30 ]; do printf '0: zero\\n\t%s\tn%s\n' "$_i" "$_i"; _i=$((_i + 1)); done
	printf 'EOF\n'
} > "$WORK/mc/r2gen_oracle.sh"
chmod +x "$WORK/mc/fc_oracle.sh" "$WORK/mc/r2gen_oracle.sh"
# shellcheck disable=SC2086 # VG_PASS is several flags, split on purpose
env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/mc/out" TEST_TARGET=//mod:ex00_file_valgrind \
	"$SH" "$TOOLS/file_check.sh" --bin "$WORK/mc/mapopen" --oracle "$WORK/mc/fc_oracle.sh" \
	--fn fixture $VG_PASS --sample 2 > "$WORK/mc/mapopen_fc.out" 2>&1
echo "$?" > "$WORK/mc/mapopen_fc.rc"
# shellcheck disable=SC2086 # VG_PASS is several flags, split on purpose
env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/mc/out" TEST_TARGET=//mod:ex00_valgrind \
	"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/mc/mapopen" --dict "$WORK/mc/dict.txt" \
	--oracle "$WORK/mc/r2gen_oracle.sh" $VG_PASS --sample 2 > "$WORK/mc/mapopen_r2.out" 2>&1
echo "$?" > "$WORK/mc/mapopen_r2.rc"
want_red   "file_check --valgrind: a file left open is red" -- mc_seen mapopen_fc
want_out   "file_check --valgrind: ...its descriptor named as the file is kept" \
	': case-23-file1' -- mc_seen mapopen_fc
want_out   "file_check --valgrind: ...saying the names were replaced" \
	'shown by the name it is kept under: case-23-file0, case-23-file1)' -- mc_seen mapopen_fc
want_red   "rush02 --valgrind: a generated dictionary left open is red" -- mc_seen mapopen_r2
want_out   "rush02 --valgrind: ...its descriptor named as the dictionary is kept" \
	': case-30.dict' -- mc_seen mapopen_r2
want_out   "rush02 --valgrind: ...saying the name was replaced" \
	'shown by the name it is kept under: case-30.dict)' -- mc_seen mapopen_r2
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
toy_cc "$WORK/mc/slow" -w -g -O0 "$WORK/mc/slow.c"
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
# 4 case(s) under memcheck went wrong". RUSH02_TIMEOUT 6 and no test limit:
# the case's own cap stops the poll.
#
# Six, not the three it was: the arm holds only while the other three cases
# of the sample each finish inside the cap, under memcheck, on whatever load
# the machine carries. Its verdict check failed once under four Bazel
# servers and passed on every re-run (TO VERIFY V235), which one more case
# past the cap would explain; nothing kept the log to say. One such case is
# about 0.6 s of its own time on a calm box, and stayed under 2 s with 120
# of them running at once on 24 CPUs; the cap is that time with the queue's
# wait given back, and the wall ceiling is ten times it (rl_tmo). Six leaves
# three times the worst measured, and costs three seconds: the poll waits
# out the whole cap.
# shellcheck disable=SC2086 # VG_PASS is several flags, split on purpose
env -u RL_DEADLINE -u RL_BUDGET -u TEST_TIMEOUT RUSH02_TIMEOUT=6 \
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
# A toy that did not build was measured anyway: perf_test.sh timed a run that
# could not start as one too fast to measure (now a harness error, V286, held
# below), and the gate's red arm would pass on a missing file -- one
# candidate for that arm's two passes under load (V235). toy_cc says so.
toy_cc "$WORK/pf/lin" -O1 "$WORK/pf/lin.c"
toy_cc "$WORK/pf/quad" -O1 "$WORK/pf/quad.c"

pf_run() {  # pf_run BIN [extra args...]
	_bin="$1"; shift
	NO_SKIP=1 "$SH" "$TOOLS/perf_test.sh" --runner "$PERF_RUN" \
		--student-bin "$WORK/pf/$_bin" --oracle "$WORK/pf/oracle.sh" \
		--oracle-fn f --count 16000 --label "selftest-$_bin" "$@"
}

# A gate given in part is refused, as every runner that takes one refuses it
# (tools/runner_lib.sh, rl_gate_whole): it failed open on a missing piece,
# so the option was dropped in silence and the run went on ungated.
want_broken "perf: --gate-stdin with no gate refuses" 'a gate needs' -- \
	pf_run lin --gate-stdin "$WORK/pf/oracle.sh"
want_broken "perf: ...as does a gate with no --gate-differ" 'a gate needs' -- \
	pf_run lin --gate-bin "$WORK/pf/lin" --gate-expected "$WORK/pf/oracle.sh"
want_broken "perf: ...and --gate-label with no gate" 'a gate needs' -- \
	pf_run lin --gate-label ex00_output
# Its SKIP line names the output test it waits for (--gate-label), as every
# gated runner's does: it said "the exercise's own output fixture" on every
# exercise (V169). lin prints a sum, never the oracle script it is compared
# with here, so the gate is red.
pf_gated() {  # pf_gated [FLAG...] -- lin, gated on a fixture it fails
	env -u NO_SKIP "$SH" "$TOOLS/perf_test.sh" --runner "$PERF_RUN" \
		--student-bin "$WORK/pf/lin" --oracle "$WORK/pf/oracle.sh" --oracle-fn f \
		--count 16000 --label selftest-gated --gate-differ "$TOOLS/diff_output.sh" \
		--gate-bin "$WORK/pf/lin" --gate-expected "$WORK/pf/oracle.sh" "$@"
}
want_out   "perf: its SKIP names the test it waits for" \
	"perf_test: SKIP — ex00_output, the exercise's own output fixture, is not passing yet." -- \
	pf_gated --gate-label ex00_output
want_out   "perf: ...and without one, names none" \
	"perf_test: SKIP — the exercise's own output fixture is not passing yet." -- pf_gated

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
	# A MEASURED RUN THAT ENDED IN AN ERROR IS NO SAMPLE (V286). Any status
	# but a timeout, a signal or perf_run's own error became a 0 ms sample,
	# "too fast to measure reliably (good sign)", and the layer passed
	# having timed nothing, under NO_SKIP=1 too: a program that is not there
	# (perf_run's 127) and one that exits 3. One that could not start is
	# the harness's fault (exit 2), naming the status and the program; any
	# other status is the program's (exit 1), naming the status and the
	# size. The second toy echoes its input, and exits 3 only past the
	# 100-case correctness sample, so that sample is green without NO_SKIP
	# and the 200-case floor is the first run to see the status.
	want_broken "perf: a measured program that is not there is a harness error" \
		'ended with status 127' -- pf_run no_such_program
	want_broken "perf: ...and names the program" "$WORK/pf/no_such_program" -- \
		pf_run no_such_program
	printf '#!/bin/sh\nexec cat\n' > "$WORK/pf/echo"
	printf '#!/bin/sh\ncat\nexit 3\n' > "$WORK/pf/echo3"
	printf '#!/bin/sh\nexec awk %s\n' "'{ print } END { if (NR > 100) exit 3 }'" \
		> "$WORK/pf/echo3_floor"
	printf '#!/bin/sh\nexec awk %s\n' "'{ print } END { if (NR == 100) exit 3 }'" \
		> "$WORK/pf/echo3_sample"
	chmod +x "$WORK/pf/echo" "$WORK/pf/echo3" "$WORK/pf/echo3_floor" "$WORK/pf/echo3_sample"
	pf_echo() {  # pf_echo BIN [FLAG...] -- a toy that echoes its input, gates green
		_bin=$1; shift
		env -u NO_SKIP "$SH" "$TOOLS/perf_test.sh" --runner "$PERF_RUN" \
			--student-bin "$WORK/pf/$_bin" --oracle "$WORK/pf/oracle.sh" \
			--oracle-fn f --count 4000 --gate-count 100 --label "selftest-$_bin" "$@"
	}
	want_red   "perf: a measured run that exits 3 fails, past a green gate" -- \
		pf_echo echo3_floor
	want_out   "perf: ...naming the status and the size" \
		'the run over 200 cases exited with status 3' -- pf_echo echo3_floor
	want_none  "perf: ...and is never a sample" 'good sign' -- pf_echo echo3_floor
	# A CORRECTNESS SAMPLE THAT RETURNS NON-ZERO IS NO GREEN GATE (V290).
	# Stage 2 took any exit status but a timeout or a signal as green, so a
	# toy that echoed its input and exited 3 read "all green" above a
	# failed measurement, and one that exited 3 on the sample's size alone
	# was measured and passed. rust_diff fails the same replay, so the gate
	# SKIPs, naming the status -- ahead of the ASan gate, whose own SKIP
	# blames a memory error for it.
	want_green "perf: a correctness sample that returns 3 is no green gate" -- \
		pf_echo echo3
	want_out   "perf: ...its SKIP names the status" \
		'correctness sample returned 3 rather than 0' -- pf_echo echo3
	want_none  "perf: ...and never calls the gates green" 'are all green' -- \
		pf_echo echo3
	want_out   "perf: ...nor measures one that returns 3 on the sample alone" \
		'correctness sample returned 3 rather than 0' -- pf_echo echo3_sample
	want_out   "perf: ...and says so ahead of the ASan gate" \
		'correctness sample returned 3 rather than 0' -- \
		pf_echo echo3 --gate-asan-bin "$WORK/pf/echo3"
	want_green "perf: ...while the same toy exiting 0 is measured" -- \
		pf_echo echo
	# ...at every size it measures, not only the first. This toy is clean
	# over the 200-case floor and the 100-case sample and exits 3 past 500
	# lines, so only the three sizes see it: a measure_sizes that took their
	# status as a sample passed it, "good sign" (review of V286).
	printf '#!/bin/sh\nexec awk %s\n' "'{ print } END { if (NR > 500) exit 3 }'" \
		> "$WORK/pf/echo3_late"
	chmod +x "$WORK/pf/echo3_late"
	want_out   "perf: a size's run that exits 3 fails, past a clean floor" \
		'the run over 1000 cases exited with status 3' -- pf_echo echo3_late
	want_none  "perf: ...and is never a sample" 'good sign' -- pf_echo echo3_late
	# ...and the second reading of a growth over the gate, which measures
	# the three sizes again. This toy is quad, and exits 3 on a size it has
	# been handed before: one run a size (PERF_REPEATS=1), and a correctness
	# sample of a size no reading uses (--gate-count 100: the sample runs
	# under NO_SKIP=1 too), so the first reading is clean and only the
	# second sees it. Judged, it ends the test
	# before the second reading is printed; taken as a sample, the run
	# passed or failed on numbers about a program that stopped early.
	cat > "$WORK/pf/quad_twice" <<PF_TWICE
#!/bin/sh
f=\$(mktemp "$WORK/pf/twice.d/in.XXXXXX") || exit 2
cat > "\$f"
n=\$(wc -l < "\$f" | tr -d ' ')
"$WORK/pf/quad" < "\$f"
rm -f "\$f"
[ ! -e "$WORK/pf/twice.d/seen.\$n" ] || exit 3
: > "$WORK/pf/twice.d/seen.\$n"
PF_TWICE
	chmod +x "$WORK/pf/quad_twice"
	pf_twice() (  # quad_twice, its sizes forgotten, over a n^1.2 gate
		rm -rf "$WORK/pf/twice.d" && mkdir "$WORK/pf/twice.d" || exit 2
		PERF_REPEATS=1
		export PERF_REPEATS
		pf_run quad_twice --gate-exponent 1.2 --gate-count 100
	)
	want_out   "perf: the second reading is judged too" \
		'Measuring again before' -- pf_twice
	want_out   "perf: ...so a run of it that exits 3 fails" \
		'cases exited with status 3' -- pf_twice
	want_none  "perf: ...and is never a sample of that reading" \
		'second reading:' -- pf_twice
	# THE REFERENCE'S RUN is judged as the student's are, and its error
	# names the reference: it named the run's CPU milliseconds, read from
	# the positional parameters measure_best had replaced (review of V286).
	printf '#!/bin/sh\ncat > /dev/null\nexit 3\n' > "$WORK/pf/ref3"
	chmod +x "$WORK/pf/ref3"
	want_broken "perf: a reference that exits 3 is no baseline" \
		"ended with '3'" -- pf_echo echo --baseline-bin "$WORK/pf/ref3"
	want_broken "perf: ...and names the reference" \
		"no baseline to compare with: $WORK/pf/ref3" -- \
		pf_echo echo --baseline-bin "$WORK/pf/ref3"
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
		toy_cc "$WORK/pf/stall$_pf" -O1 "$WORK/pf/stall$_pf.c"
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
	# conventions: writes a program that runs awk -- the length oracle below
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
	toy_cc "$WORK/pf/lenquad" -O1 "$WORK/pf/lenquad.c"
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
#
# WHICH CPU. Every copy of this file once pinned itself to CPU 0: this one
# and its bash twin, which run side by side in every `bazel test //...`, and
# every copy --runs_per_test starts. Twenty copies put sixty busy loops on
# one CPU, a second of CPU then took more than the sixty-second ceiling, and
# these arms went red on load alone (TO VERIFY V235). So a copy pins to a CPU
# it chooses, from those it may run on (`taskset -cp`): one that sat idle
# over a second of /proc/stat, as near as the idlest -- a CPU another copy's
# loops keep busy is never idle -- and among several, one a random seed
# picks, so two copies that look at the same moment seldom take the same
# one. A lock would make the copies take turns instead, and twenty busy
# blocks in turn do not fit the target's timeout.
#
# bm_allowed LIST -- taskset's CPU list (0-3,8, or 0-10:2) as the CPUs it
# names, one comma between.
bm_allowed() {
	printf '%s\n' "$1" | awk -F, '{
		o = ""
		for (i = 1; i <= NF; i++) {
			st = 1
			r = $i
			if (split(r, p, ":") == 2) { r = p[1]; st = p[2] + 0 }
			if (r ~ /^[0-9]+-[0-9]+$/ && st > 0) {
				split(r, q, "-")
				for (c = q[1] + 0; c <= q[2] + 0; c += st) o = o (o == "" ? "" : ",") c
			} else if (r ~ /^[0-9]+$/)
				o = o (o == "" ? "" : ",") r
		}
		print o
	}'
}
# bm_cpu STAT1 STAT2 ALLOWED SEED -- the CPU of ALLOWED to pin to, from two
# readings of /proc/stat: those idle for a share of the time between them
# within a quarter of the idlest's, the SEED picking among them. Nothing,
# exit 1, where the readings name none of ALLOWED. A quarter, and not a
# share of the idlest's own: on a machine busy everywhere every CPU is idle
# a few hundredths of the time, the idlest by chance, and a rule that kept
# only it sent twenty copies started at once to the same CPU again.
bm_cpu() {
	awk -v allowed="$3" -v seed="$4" '
		FNR == 1 { f++ }
		$1 ~ /^cpu[0-9]+$/ {
			c = substr($1, 4) + 0
			t = 0
			for (i = 2; i <= NF; i++) t += $i
			idle[f, c] = $5 + $6
			all[f, c] = t
		}
		END {
			n = split(allowed, al, ",")
			best = -1
			for (i = 1; i <= n; i++) {
				c = al[i] + 0
				if (!((1, c) in idle) || !((2, c) in idle)) continue
				t = all[2, c] - all[1, c]
				if (t <= 0) continue
				d[c] = (idle[2, c] - idle[1, c]) / t
				if (d[c] > best) best = d[c]
			}
			if (best < 0) exit 1
			k = 0
			for (i = 1; i <= n; i++) {
				c = al[i] + 0
				if ((c in d) && d[c] >= best - 0.25) cand[k++] = c
			}
			print cand[seed % k]
		}' "$1" "$2"
}
# bm_from STAT1 STAT2 ALLOWED SEED -- bm_cpu's choice, or, where the
# readings name none of ALLOWED (a container whose /proc/stat numbers its
# CPUs from 0 while taskset names the host's), the SEED's pick of ALLOWED
# with no load to go by: such a box still runs the block below.
bm_from() {
	bm_cpu "$@" || echo "$3" | awk -v seed="$4" '{ n = split($0, al, ","); print al[seed % n + 1] }'
}
# bm_choose -- sets BM_CPU, or leaves it empty where taskset cannot say. The
# seed is read from /dev/urandom, not $$: a sandboxed test runs in a process
# namespace of its own, where two copies' $$ can be the same number.
bm_choose() {
	BM_CPU=""
	command -v taskset > /dev/null 2>&1 && [ -r /proc/stat ] || return 0
	_bm_list=$(taskset -cp $$ 2> /dev/null) || return 0
	_bm_allowed=$(bm_allowed "${_bm_list##*: }")
	[ -n "$_bm_allowed" ] || return 0
	_bm_seed=$(od -An -N2 -tu2 /dev/urandom 2> /dev/null | awk '{ print $1 + 0 }')
	[ -n "$_bm_seed" ] || _bm_seed=$$
	cat /proc/stat > "$WORK/bm_stat.1" 2> /dev/null || return 0
	sleep 1
	cat /proc/stat > "$WORK/bm_stat.2" 2> /dev/null || return 0
	BM_CPU=$(bm_from "$WORK/bm_stat.1" "$WORK/bm_stat.2" "$_bm_allowed" "$_bm_seed")
}
# Proven on readings written here, so on any machine: CPU 0 busy with the
# first copy's loops between the two readings, CPU 1 idle, and the other
# way round; both idle; both busy with other work, idle 16% and 5% of the
# time; and a CPU the run may not use.
mkdir -p "$WORK/bmc"
printf 'cpu  0 0 0 0 0\ncpu0 100 0 0 500 0\ncpu1 100 0 0 500 0\n' > "$WORK/bmc/t1"
printf 'cpu  0 0 0 0 0\ncpu0 200 0 0 500 0\ncpu1 100 0 0 600 0\n' > "$WORK/bmc/busy0"
printf 'cpu  0 0 0 0 0\ncpu0 100 0 0 600 0\ncpu1 200 0 0 500 0\n' > "$WORK/bmc/busy1"
printf 'cpu  0 0 0 0 0\ncpu0 100 0 0 600 0\ncpu1 100 0 0 598 0\n' > "$WORK/bmc/idle"
printf 'cpu  0 0 0 0 0\ncpu0 184 0 0 516 0\ncpu1 195 0 0 505 0\n' > "$WORK/bmc/loaded"
bm_is() {  # bm_is READING ALLOWED SEED WANT
	[ "$(bm_cpu "$WORK/bmc/t1" "$WORK/bmc/$1" "$2" "$3")" = "$4" ]
}
want_green "busy CPU: no copy takes a CPU another keeps busy" -- bm_is busy0 0,1 0 1
want_green "busy CPU: ...whatever its seed" -- bm_is busy0 0,1 1 1
want_green "busy CPU: ...and takes the other way round too" -- bm_is busy1 0,1 1 0
want_green "busy CPU: two idle CPUs are shared out by the seed" -- bm_is idle 0,1 0 0
want_green "busy CPU: ...the other seed taking the other" -- bm_is idle 0,1 1 1
want_green "busy CPU: a box busy everywhere is shared out too" -- bm_is loaded 0,1 0 0
want_green "busy CPU: ...not sent to the CPU idle by chance" -- bm_is loaded 0,1 1 1
want_green "busy CPU: only a CPU the run may use is taken" -- bm_is busy1 1 0 1
bm_from_is() {  # bm_from_is READING ALLOWED SEED WANT
	[ "$(bm_from "$WORK/bmc/t1" "$WORK/bmc/$1" "$2" "$3")" = "$4" ]
}
want_green "busy CPU: readings that name none of the run's CPUs still choose one" -- \
	bm_from_is busy0 4,5 0 4
want_green "busy CPU: ...the seed sharing them out" -- bm_from_is busy0 4,5 1 5
want_green "busy CPU: ...and readings that name them choose by load" -- \
	bm_from_is busy0 0,1 0 1
bm_list_is() { [ "$(bm_allowed "$1")" = "$2" ]; }
want_green "busy CPU: taskset's list is read with its ranges" -- \
	bm_list_is 0,2-4,7 0,2,3,4,7
want_green "busy CPU: ...and with a range's step" -- bm_list_is 0-6:3 0,3,6
# And on this machine, where taskset and /proc/stat can say, a CPU is
# chosen, and one the run may use: a copy that chose none skips the whole
# block below, a skip counts nothing, and a chooser broken by a later edit
# (a list it cannot read, an awk slip) would drop every arm of it quietly.
bm_choose
if command -v taskset > /dev/null 2>&1 && [ -r /proc/stat ] &&
	taskset -cp $$ > /dev/null 2>&1; then
	bm_chose() {
		_bc_list=$(taskset -cp $$ 2> /dev/null)
		case ",$(bm_allowed "${_bc_list##*: }")," in
			*",$BM_CPU,"*) [ -z "$BM_CPU" ] || return 0 ;;
		esac
		echo "taskset -cp says: $_bc_list"
		echo "the CPU chosen: '$BM_CPU'"
		return 1
	}
	want_green "busy CPU: a CPU is chosen where taskset can pin" -- bm_chose
fi
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
toy_cc "$WORK/cpu_spin" -w -O0 "$WORK/cpu_spin.c"
# And only where the kernel counts a task's wait for a CPU: without
# /proc/PID/schedstat nothing is given back, by design (runqueue.h), and the
# arms that need time given back would be red on that machine alone.
if command -v taskset > /dev/null 2>&1 && [ -x "$WORK/cpu_spin" ] && [ -n "$BM_CPU" ] &&
	taskset -c "$BM_CPU" true 2> /dev/null && [ -r /proc/self/schedstat ]; then
	# Its toys are its own, beside perf's and the corpus's rather than in
	# them: perf's toy oracle, and the corpus's oracle and dictionary,
	# written again.
	mkdir -p "$WORK/bm"
	cat > "$WORK/bm/pf_oracle.sh" <<'BM_PF_ORACLE'
#!/bin/sh
# $1 fn, $2 seed, $3 count -- emit <count> corpus lines.
n=$3; i=0
while [ "$i" -lt "$n" ]; do printf '%s\t%s\n' "$i" "$i"; i=$((i + 1)); done
BM_PF_ORACLE
	{
		printf '#!/bin/sh\ncat <<%sEOF%s\n' "'" "'"
		_i=0
		while [ "$_i" -lt 30 ]; do printf '%s\tn%s\n' "$_i" "$_i"; _i=$((_i + 1)); done
		printf 'EOF\n'
	} > "$WORK/bm/mc_oracle.sh"
	chmod +x "$WORK/bm/pf_oracle.sh" "$WORK/bm/mc_oracle.sh"
	printf '0: zero\n' > "$WORK/bm/dict.txt"
	bm_seen() { cat "$WORK/bm/$1.out"; return "$(cat "$WORK/bm/$1.rc")"; }
	_busy=""
	for _b in 1 2 3; do
		taskset -c "$BM_CPU" sh -c 'while :; do :; done' &
		_busy="$_busy $!"
	done
	busy_run() {  # busy_run REPORT [EXIT_STATUS OPTION...] -- one second of CPU on the busy CPU
		_r=$1
		shift
		taskset -c "$BM_CPU" "$TOOLS/exit_status" "$@" "$_r" "$WORK/cpu_spin" 1
		cat "$_r"
	}
	want_out   "exit_status: on a busy CPU, a run given its queue time back ends" 'exit 0' -- \
		busy_run "$WORK/busy_ceil.how" --timeout 2 --ceiling 60
	want_out   "exit_status: ...where a wall clock stopped it" 'timeout 2' -- \
		busy_run "$WORK/busy_wall.how" --timeout 2
	want_out   "perf_run: on a busy CPU, a measurement given its queue time back ends" 'exit=0' -- \
		taskset -c "$BM_CPU" "$PERF_RUN" --timeout 2 --ceiling 60 -- "$WORK/cpu_spin" 1
	# A run that SPINS forever is runnable: it queues as a correct one does,
	# is given that time back too, and is stopped after its limit of its own
	# time -- later in wall time, never on it (runqueue.h). The docs once
	# said a spinner waits on no queue.
	busy_spin() {  # busy_spin REPORT -- a run that never ends, on the busy CPU
		taskset -c "$BM_CPU" "$TOOLS/exit_status" --timeout 2 --ceiling 60 "$1" "$WORK/cpu_spin" 1000
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
		'exit=ceiling' -- taskset -c "$BM_CPU" "$PERF_RUN" --timeout 2 --ceiling 3 -- "$WORK/cpu_spin" 1000
	# A toy that echoes its input, so the correctness sample passes, and
	# spins past 150 lines: the 200-case floor run never ends. PERF_TIMEOUT
	# 8 is less than the test has left, so only the ceiling (what is left,
	# about 15s of wall time) can stop it before its own 8s are spent.
	printf '#include <stdio.h>\nint main(void)\n{\n\tchar b[256];\n\tlong n = 0;\n\tvolatile long x = 0;\n\n\twhile (fgets(b, sizeof b, stdin))\n\t{\n\t\tfputs(b, stdout);\n\t\tn++;\n\t}\n\twhile (n > 150)\n\t\tx++;\n\treturn (0);\n}\n' \
		> "$WORK/bm/spin150.c"
	toy_cc "$WORK/bm/spin150" -O0 "$WORK/bm/spin150.c"
	pf_ceiling() {  # the floor run of a toy that spins, on the busy CPU, stopped by the ceiling
		taskset -c "$BM_CPU" env -u NO_SKIP TEST_TIMEOUT=18 RL_MARGIN=1 PERF_TIMEOUT=8 \
			"$SH" "$TOOLS/perf_test.sh" --runner "$PERF_RUN" --student-bin "$WORK/bm/spin150" \
			--oracle "$WORK/bm/pf_oracle.sh" --oracle-fn f --count 16000 \
			--gate-count 100 --label selftest-spin150
	}
	pf_ceiling > "$WORK/bm/pf_ceiling.out" 2>&1
	want_out   "perf: a run the ceiling stopped is reported as the test's time" \
		'what was left of' -- cat "$WORK/bm/pf_ceiling.out"
	want_none  "perf: ...never as PERF_TIMEOUT, which it did not use" \
		'(PERF_TIMEOUT)' -- cat "$WORK/bm/pf_ceiling.out"
	# A MEMCHECK CASE THE CEILING STOPPED (V33). The case's own cap
	# (RUSH02_TIMEOUT, 10 s) is below what the test has left when the case
	# begins, so the runner does not clamp it; on this CPU the run's queue
	# carries its wall time to the ceiling -- what the test has left --
	# long before its own time reaches the cap. valgrind_test.sh saw
	# "ceiling" and the runner did not: the case was one more memcheck
	# failure, and the stop said each of the first cases "ended within its
	# own limit", one of them judged wrong. A converter that spins on case
	# 15, the second of the sample, under a test limit of 30 s.
	cat > "$WORK/bm/spin.c" <<'MC_SPIN'
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
	toy_cc "$WORK/bm/spin" -w -g -O0 "$WORK/bm/spin.c"
	# shellcheck disable=SC2086 # VG_PASS is several flags, split on purpose
	taskset -c "$BM_CPU" env -u RL_DEADLINE -u RL_BUDGET TEST_TIMEOUT=30 RL_MARGIN=1 \
		"$SH" "$TOOLS/rush02_check.sh" --bin "$WORK/bm/spin" --dict "$WORK/bm/dict.txt" \
		--oracle "$WORK/bm/mc_oracle.sh" $VG_PASS --sample 4 > "$WORK/bm/mc_ceiling.out" 2>&1
	echo "$?" > "$WORK/bm/mc_ceiling.rc"
	want_red   "corpus --valgrind: on a busy CPU, a case the ceiling stopped is red" -- bm_seen mc_ceiling
	want_out   "corpus --valgrind: ...shown as the one running when the time ran out" \
		'the one running when the time ran out' -- bm_seen mc_ceiling
	want_out   "corpus --valgrind: ...marked as not finished, not as memcheck's" \
		'case 15 of 30  [timeout]' -- bm_seen mc_ceiling
	want_none  "corpus --valgrind: ...and never as a case judged wrong" \
		'judged wrong before that' -- bm_seen mc_ceiling
	# shellcheck disable=SC2086 # the busy loops' pids, one word each
	kill $_busy 2> /dev/null
	wait 2> /dev/null
elif [ ! -x "$WORK/cpu_spin" ]; then
	# toy_cc counted the FAIL, above: this only says why nothing ran.
	printf '  %-52s %s\n' "exit_status: a busy CPU's queue time" \
		"not run (its toy cpu_spin did not build: the FAIL above)"
else
	printf '  %-52s %s\n' "exit_status: a busy CPU's queue time" \
		"not run here (no taskset, no CPU it could choose, or no /proc/PID/schedstat)"
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
toy_cc "$WORK/cyc/given.o" -O2 -w -c "$WORK/cyc/given.c"
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
# Its budget is the test's own: what is left of TEST_TIMEOUT once the build
# and the oracle are done stops the run. On a loaded machine those can use a
# small budget up before callgrind starts (V305: at load 160, all of 8s), and
# then the run said "could start", which proves nothing about a run being
# stopped. So a run that never started callgrind is made once more with
# twice the time, still under spin.c's alarm(20), and a second one that never
# started stays red, showing what it said.
cyc_spin() {  # cyc_spin TEST_TIMEOUT -- the never-ending run, into spin_tmo.out
	env -u RL_DEADLINE -u RL_BUDGET TEST_TIMEOUT="$1" RL_MARGIN=1 \
		"$SH" "$TOOLS/cycles_check.sh" $CG_PASS \
		--harness "$WORK/cyc/spin.c" --oracle "$WORK/cyc/oracle.sh" --oracle-fn f \
		--symbol probe_sum --count 300 > "$WORK/cyc/spin_tmo.out" 2>&1
	echo "$?" > "$WORK/cyc/spin_tmo.rc"
}
cyc_spin 8
! grep -qF 'could start' "$WORK/cyc/spin_tmo.out" || cyc_spin 16
cyc_spin_seen() { cat "$WORK/cyc/spin_tmo.out"; return "$(cat "$WORK/cyc/spin_tmo.rc")"; }
want_out  "cycles_check: one that never ends is stopped, and said to be" \
	'did not finish within' -- cyc_spin_seen
want_none "cycles_check: ...once callgrind had started" 'could start' -- cyc_spin_seen
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


# A harness that RETURNED non-zero under callgrind (V291) is no measurement:
# its count is never read, it is a SKIP, red under NO_SKIP=1 as every layer
# that measured nothing is, and the SKIP says the harness returned it -- not
# that callgrind could not profile it, which blamed the tool (finding 066's
# class), and shows what the harness said, without valgrind's banner. A
# runner that read such a run's profile would pass every arm above.
sed 's/return (0);/fprintf(stderr, "toy: refused\\n"); return (3);/' "$WORK/cyc/h.c" \
	> "$WORK/cyc/exit3.c"
env -u NO_SKIP "$SH" "$TOOLS/cycles_check.sh" $CG_PASS --harness "$WORK/cyc/exit3.c" \
	--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum --count 300 \
	> "$WORK/cyc/exit3.out" 2>&1
echo "$?" > "$WORK/cyc/exit3.rc"
cyc_exit3() { cat "$WORK/cyc/exit3.out"; return "$(cat "$WORK/cyc/exit3.rc")"; }
want_green "cycles_check: a harness that returns non-zero is a report" -- cyc_exit3
want_none "cycles_check: ...that counts nothing" 'instructions  ' -- cyc_exit3
want_out  "cycles_check: ...says the harness returned it" 'harness returned 3 under callgrind' -- \
	cyc_exit3
want_none "cycles_check: ...and does not blame callgrind" 'could not profile' -- cyc_exit3
want_out  "cycles_check: ...showing what the harness said" 'toy: refused' -- cyc_exit3
want_none "cycles_check: ...and not valgrind's banner" 'Copyright' -- cyc_exit3
want_red  "cycles_check: ...which NO_SKIP=1 makes red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/cycles_check.sh" $CG_PASS --harness "$WORK/cyc/exit3.c" \
		--oracle "$WORK/cyc/oracle.sh" --oracle-fn f --symbol probe_sum --count 300

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
	# said "The ordinary 64-bit build passes these cases" (V1).
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

	# ONE FILE PER COMPILE (V199). Handed every source in one call, zig
	# compiled them in parallel onto one stderr, and two files' errors came
	# out byte-interleaved, with zig's own "Segmentation fault" now and then.
	# The red is the wrapper: a zig that refuses any call naming two .c
	# files, over two toy sources that build. Beside it, what a reader sees:
	# two files' errors, and their warnings, each line whole. The warnings
	# run is made once, first, and read twice, because zig replays no
	# warning for a file its cache already holds: the wrapper's run of the
	# same files comes after it.
	cat > "$WORK/i32/two_harness.c" <<'ILP32_TWO'
#include <stdio.h>

int	ft_probe_a(int n, int unused);
int	ft_probe_b(int n, int unused);

int	main(void)
{
	printf("%d %d\n", ft_probe_a(1, 0), ft_probe_b(2, 0));
	return (0);
}
ILP32_TWO
	printf 'int\tft_probe_a(int n, int unused)\n{\n\treturn (n + 1);\n}\n' > "$WORK/i32/two_a.c"
	printf 'int\tft_probe_b(int n, int unused)\n{\n\treturn (n + 1);\n}\n' > "$WORK/i32/two_b.c"
	printf '#include "nope_alpha.h"\n\nint\tft_probe_a(int n, int unused)\n{\n\treturn (n + unused);\n}\n' \
		> "$WORK/i32/two_ea.c"
	printf '#include "nope_beta.h"\n\nint\tft_probe_b(int n, int unused)\n{\n\treturn (n + unused);\n}\n' \
		> "$WORK/i32/two_eb.c"
	printf '2 3\n' > "$WORK/i32/two_expected.txt"
	printf '#!/bin/sh\n_n=0\nfor _a; do case $_a in *.c) _n=$((_n + 1)) ;; esac; done\n[ "$_n" -lt 2 ] || { echo "toy zig: $_n sources in one call" >&2; exit 99; }\nexec "%s" "$@"\n' \
		"$ZIG" > "$WORK/i32/onebyone_zig"
	chmod +x "$WORK/i32/onebyone_zig"
	i32_two() {  # i32_two ZIG SRC SRC -- the two-source toy, no 64-bit gate
		"$SH" "$TOOLS/ilp32_test.sh" --zig "$1" --differ "$TOOLS/diff_output.sh" \
			--harness "$WORK/i32/two_harness.c" --expected "$WORK/i32/two_expected.txt" \
			--src "$WORK/i32/$2" --src "$WORK/i32/$3"
	}
	want_out   "ilp32: two files' errors, the first whole" \
		"two_ea.c:1:10: fatal error: 'nope_alpha.h' file not found" -- \
		i32_two "$ZIG" two_ea.c two_eb.c
	want_out   "ilp32: ...and the second" \
		"two_eb.c:1:10: fatal error: 'nope_beta.h' file not found" -- \
		i32_two "$ZIG" two_ea.c two_eb.c
	want_none  "ilp32: ...and no compiler crash" 'Segmentation fault' -- \
		i32_two "$ZIG" two_ea.c two_eb.c
	i32_two "$ZIG" two_a.c two_b.c > "$WORK/i32/two_warns.out" 2>&1
	want_green "ilp32: each source is compiled in a call of its own" -- \
		i32_two "$WORK/i32/onebyone_zig" two_a.c two_b.c
	want_out   "ilp32: two files' warnings, the first whole" \
		"two_a.c:1:27: warning: unused parameter 'unused' [-Wunused-parameter]" -- \
		cat "$WORK/i32/two_warns.out"
	want_out   "ilp32: ...and the second" \
		"two_b.c:1:27: warning: unused parameter 'unused' [-Wunused-parameter]" -- \
		cat "$WORK/i32/two_warns.out"

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
# (`oracle check`).
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
	# conventions: writes a program that runs fold -- the folded sums of shell-01 ex08 below
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
	# literal.sh judges the order as this machine's test locale collates
	# it, and where that locale is missing (or collates as bytes do) it
	# skips, rightly. So this arm runs where //oracle says the locale
	# collates, and says it skipped elsewhere: it FAILED there, with the
	# runner right (V280). The arms below with xx_XX.UTF-8 hold on any
	# machine.
	"$ORACLE" shell01_rdwssap collates 2> /dev/null
	case $? in
		0)
			want_red "shell-01 ex07 literal: the same names fail the window" -- \
				ex07 --check "$S01/ex07/literal.sh" ;;
		1)
			if [ "${NO_SKIP:-0}" = "1" ]; then
				printf '  %-52s %s\n' "shell-01 ex07 literal: the same names fail the window" \
					"FAIL < (NO_SKIP=1, and ${ST_TEST_LOCALE:-the test locale} collates as bytes here)"
				FAIL=$((FAIL + 1))
			else
				printf '  %-52s %s\n' "shell-01 ex07 literal: the same names fail the window" \
					"skipped (${ST_TEST_LOCALE:-the test locale} is not installed, or collates as bytes do: locale -a)"
			fi ;;
		*)
			printf '  %-52s %s\n' "shell-01 ex07 literal: the same names fail the window" \
				"FAIL < (//oracle could not say how this machine collates)"
			FAIL=$((FAIL + 1)) ;;
	esac
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
	# A machine without the test locale (.bazelrc's LC_ALL) collates as bytes
	# do, so the fixture's two orders look alike there through no fault of
	# the fixture's. That is one property this machine cannot show, a skip
	# saying which locale is missing, and every other line is still judged:
	# it was BROKEN HARNESS (exit 2) on every program, a correct one too
	# (V245). xx_XX.UTF-8 is a locale no machine has, so the arms hold on any.
	ex07_noloc() { (LC_ALL=xx_XX.UTF-8; export LC_ALL; ex07 "$@"); }
	want_green "shell-01 ex07: without the locale the fixture still shows its steps" -- \
		env LC_ALL=xx_XX.UTF-8 "$ORACLE" shell01_rdwssap shows --passwd "$S01/ex07/passwd"
	want_red "shell-01 ex07: ...the reference says this locale collates as bytes" -- \
		env LC_ALL=xx_XX.UTF-8 "$ORACLE" shell01_rdwssap collates
	want_red "shell-01 ex07: ...and names that are no login still fail" -- \
		ex07_noloc --check "$S01/ex07/check.sh"
	want_out "shell-01 ex07: ...without the locale, on the property they break" \
		"[FAIL] each name is a login from the file, reversed" -- \
		ex07_noloc --check "$S01/ex07/check.sh"
	want_out "shell-01 ex07: ...the two orders a skip naming the locale" \
		"xx_XX.UTF-8 is not installed, or collates as bytes do: locale -a" -- \
		ex07_noloc --check "$S01/ex07/check.sh"
	want_none "shell-01 ex07: ...never a broken harness" "BROKEN HARNESS" -- \
		ex07_noloc --check "$S01/ex07/check.sh"
	want_out "shell-01 ex07 literal: ...its reading a skip, naming it too" \
		"xx_XX.UTF-8 is not installed, or collates as bytes do: locale -a" -- \
		ex07_noloc --check "$S01/ex07/literal.sh"

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

# ------------------------------------------------- what a fixture leaves open
# An output fixture shows only what the contract fixes (V205). C 02 ex10's
# manual page says nothing of the bytes between the terminator and size, and
# its fixture showed them as they were before the call, so an answer that
# wrote them failed two rows at basic. Here the fixture is built over two
# stand-ins compiled from Rust (//oracle:c02_strlcpy_standins), which differ
# in those bytes alone -- one leaves them, one sets them to 0 -- and each
# must pass every row. Neither is C: a C copy would be the exercise's answer
# outside the zone. The fixture's call is renamed to each (-D), as
# selftest.sh's C 13 ex05 arm renames its toy.
C02_10=$ROOT/c-piscine/c-piscine-c-02/tests/ex10
if [ -n "$STRLCPY_STANDINS" ] && [ -f "$STRLCPY_STANDINS" ]; then
	STRLCPY_STANDINS=$(cd "$(dirname "$STRLCPY_STANDINS")" && pwd)/$(basename "$STRLCPY_STANDINS")
	mkdir -p "$WORK/lcpy"
	for _lk in kept zeroed; do
		"$CC" -Dft_strlcpy="standin_strlcpy_tail_$_lk" -o "$WORK/lcpy/$_lk" \
			"$C02_10/test_strlcpy.c" "$STRLCPY_STANDINS" > "$WORK/lcpy/$_lk.err" 2>&1 ||
			cat "$WORK/lcpy/$_lk.err"
	done
	lcpy() {
		"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/lcpy/$1" \
			--expected "$C02_10/expected.txt" --labeled --escaped-values
	}
	want_green "C 02 ex10 fixture: the tail left as it was passes" -- lcpy kept
	want_green "C 02 ex10 fixture: ...and the tail set to 0 passes too" -- lcpy zeroed
else
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no --strlcpy-standins was supplied, so C 02 ex10's" >&2
		echo "             fixture was not built over its stand-ins." >&2
		exit 2
	}
	printf '  %-52s %s\n' "C 02 ex10 fixture: (no stand-ins)" "skipped"
fi

# The same arm over C 03 ex05's fixture (V283), whose manual page (man 3bsd
# strlcat) is silent on the same window: the bytes between the new
# terminator and size. Its X-filled rows show a fixed number of bytes, and
# nothing else held that number below the window. A third build widens those
# rows to show the window, and there the stand-in that sets it to 0 must
# fail, against an expected written by the one that leaves it: the arm has
# teeth only if the two stand-ins really differ where a row could look.
C03_05=$ROOT/c-piscine/c-piscine-c-03/tests/ex05
if [ -n "$STRLCAT_STANDINS" ] && [ -f "$STRLCAT_STANDINS" ]; then
	STRLCAT_STANDINS=$(cd "$(dirname "$STRLCAT_STANDINS")" && pwd)/$(basename "$STRLCAT_STANDINS")
	mkdir -p "$WORK/lcat"
	sed 's/^\([[:space:]]*test_x(.*, \)[0-9][0-9]*);$/\112);/' "$C03_05/test_strlcat.c" \
		> "$WORK/lcat/wide.c"
	if cmp -s "$C03_05/test_strlcat.c" "$WORK/lcat/wide.c"; then
		echo "HARNESS ERROR: no test_x row of C 03 ex05's fixture was widened;" >&2
		echo "               the arm's sed no longer matches the fixture." >&2
		exit 2
	fi
	for _lk in kept zeroed; do
		for _src in test_strlcat wide; do
			case "$_src" in
				wide) _c=$WORK/lcat/wide.c ;;
				*) _c=$C03_05/test_strlcat.c ;;
			esac
			"$CC" -Dft_strlcat="standin_strlcat_tail_$_lk" \
				-o "$WORK/lcat/$_src.$_lk" "$_c" "$STRLCAT_STANDINS" \
				> "$WORK/lcat/$_src.$_lk.err" 2>&1 || cat "$WORK/lcat/$_src.$_lk.err"
		done
	done
	"$WORK/lcat/wide.kept" > "$WORK/lcat/wide.expected" 2>/dev/null || :
	lcat() {
		"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/lcat/$1" \
			--expected "$2" --labeled --escaped-values
	}
	want_green "C 03 ex05 fixture: the tail left as it was passes" -- \
		lcat test_strlcat.kept "$C03_05/expected.txt"
	want_green "C 03 ex05 fixture: ...and the tail set to 0 passes too" -- \
		lcat test_strlcat.zeroed "$C03_05/expected.txt"
	want_red "C 03 ex05 fixture: a row showing the tail parts them" -- \
		lcat wide.zeroed "$WORK/lcat/wide.expected"
else
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no --strlcat-standins was supplied, so C 03 ex05's" >&2
		echo "             fixture was not built over its stand-ins." >&2
		exit 2
	}
	printf '  %-52s %s\n' "C 03 ex05 fixture: (no stand-ins)" "skipped"
fi

# ------------------------------------- what a plain corpus leaves to a reading
# A c_diff's plain corpus holds only what every reading of the subject agrees
# on (docs/new-project.md, item 44); a case one reading decides is its
# `readings` target's, at strict, whose own hint says which reading (V206).
# The comparison exercises' manual pages promise a sign, so a function that
# returns only the sign passes every plain corpus here, and fails their
# readings targets; libc's own function passes those (a premise about the C
# library, as dirty_malloc's arm in selftest.sh has one). Each harness, oracle
# arm and count is read from the c_diff call in the module's BUILD file, so
# this asks what the suite runs. The toys call libc and are named apart, the
# harness's call renamed to them (-D): nothing outside the zone defines an
# exercise's function.
# rd_call MODULE NUM: "harness|oracle_fn|count|its readings' harness|
# oracle_fn|count", from MODULE's c_diff(num = NUM); an empty field is one
# the call does not set.
rd_call() {
	awk -v n="$2" '
		function val(s, k,   r) {
			if (!match(s, k "[ \t]*[=:][ \t]*(\"[^\"]*\"|[0-9]+)")) return ""
			r = substr(s, RSTART, RLENGTH)
			sub(/^[^=:]*[=:][ \t]*/, "", r)
			gsub(/"/, "", r)
			return r
		}
		function done(t,   rd, p, i) {
			if (val(t, "[(, ]num") != n) return
			rd = ""; p = t
			i = index(t, "readings = {")
			if (i) {
				rd = substr(t, i)
				sub(/}.*/, "", rd)
				p = substr(t, 1, i - 1) substr(t, i + length(rd))
			}
			printf "%s|%s|%s|%s|%s|%s\n", val(p, "[(, ]harness"), val(p, "[(, ]oracle_fn"),
				val(p, "[(, ]count"), val(rd, "\"harness\""), val(rd, "\"oracle_fn\""),
				val(rd, "\"count\"")
		}
		/^c_diff\(/ { inc = 1; t = "" }
		inc {
			t = t " " $0
			if ($0 ~ /^\)/ || ($0 ~ /^c_diff\(/ && $0 ~ /\)[ \t]*$/)) { inc = 0; done(t) }
		}' "$ROOT/$1/BUILD.bazel"
}
if [ -n "$ORACLE" ] && [ -x "$ORACLE" ]; then
	ORACLE=$(cd "$(dirname "$ORACLE")" && pwd)/$(basename "$ORACLE")
	mkdir -p "$WORK/rd"
	printf '%s\n' '#include <string.h>' \
		'int	toy_sign_cmp(char *a, char *b)' '{' '	int	r;' '' '	r = strcmp(a, b);' \
		'	return ((r > 0) - (r < 0));' '}' '' \
		'int	toy_sign_ncmp(char *a, char *b, unsigned int n)' '{' '	int	r;' '' \
		'	r = strncmp(a, b, n);' '	return ((r > 0) - (r < 0));' '}' '' \
		'int	toy_libc_cmp(char *a, char *b)' '{' '	return (strcmp(a, b));' '}' '' \
		'int	toy_libc_ncmp(char *a, char *b, unsigned int n)' '{' \
		'	return (strncmp(a, b, n));' '}' > "$WORK/rd/toys.c"
	# rd_run BIN HARNESS FN COUNT -- the corpus through rust_diff.sh, as the
	# target runs it (seed 1, c_diff's default), its words in the log; exit 2,
	# nothing checked, when the arm has no program to run.
	rd_run() {
		[ -n "$1" ] && [ -x "$1" ] || { echo "no program was built for this arm" >&2; return 2; }
		"$SH" "$TOOLS/rust_diff.sh" --oracle "$ORACLE" --oracle-fn "$3" --seed 1 \
			--count "$4" --student-bin "$1" --harness-src "$2" < /dev/null
	}
	# rd_words FILE... -- red when a file the plain targets ship (the basic
	# fixture, its clues, the plain reader and its legend) says the words the
	# int's reading was stated in before it had a target of its own: the
	# int's reading is the readings target's alone, in its own hint.
	rd_words() {
		_rwb=0
		for _rwf in "$@"; do
			[ -f "$_rwf" ] || { echo "$_rwf: not in this test's data" >&2; return 2; }
			grep -n -i -E 'int itself|exact (int|value)|magnitude' "$_rwf" && _rwb=1
		done
		return "$_rwb"
	}
	while read -r _rm _rn _rf _rw _rx; do
		_rk=$(printf '%s' "$_rm" | sed 's|.*/c-piscine-||; s|.*/||')
		_rt="$ROOT/$_rm/tests/ex$_rn"
		IFS='|' read -r _ph _po _pc _qh _qo _qc <<-EOF2
			$(rd_call "$_rm" "$_rn")
		EOF2
		for _rs in sign libc; do
			for _rh in "$_ph" "$_qh"; do
				[ -n "$_rh" ] || continue
				"$CC" -I "$TOOLS" -D"$_rf=toy_${_rs}_${_rw}" -o "$WORK/rd/$_rk$_rn.$_rs.${_rh%.c}" \
					"$_rt/$_rh" "$WORK/rd/toys.c" < /dev/null > "$WORK/rd/$_rk$_rn.err" 2>&1 ||
					cat "$WORK/rd/$_rk$_rn.err"
			done
		done
		want_green "$_rk ex$_rn plain diff: a sign-only function passes" -- \
			rd_run "$WORK/rd/$_rk$_rn.sign.${_ph%.c}" "$_rt/$_ph" "$_po" "${_pc:-400000}"
		want_green "$_rk ex$_rn plain targets: none reads the int" -- \
			rd_words "$_rt/$_rx" "$_rt/clues.tsv" "$_rt/diff_clues.txt" "$_rt/$_ph"
		if [ -n "$_qh" ] && [ -n "$_qo" ]; then
			want_red "$_rk ex$_rn readings: ...and fails the readings corpus" -- \
				rd_run "$WORK/rd/$_rk$_rn.sign.${_qh%.c}" "$_rt/$_qh" "$_qo" "${_qc:-20000}"
			want_green "$_rk ex$_rn readings: premise, libc's own passes it" -- \
				rd_run "$WORK/rd/$_rk$_rn.libc.${_qh%.c}" "$_rt/$_qh" "$_qo" "${_qc:-20000}"
		else
			printf '  %-52s %s\n' "$_rk ex$_rn readings: the call has a readings harness" \
				"FAIL < (its c_diff names no readings harness and arm)"
			FAIL=$((FAIL + 1))
		fi
	done <<-EOF
		c-piscine/c-piscine-c-03 00 ft_strcmp cmp test_strcmp.c
		c-piscine/c-piscine-c-03 01 ft_strncmp ncmp test_strncmp.c
		c-piscine/c-piscine-c-09 00 ft_strcmp cmp test_libft.c
		c-piscine-reloaded/c-piscine-reloaded 17 ft_strcmp cmp test_strcmp.c
	EOF
	# A program that failed to build is nothing checked, never a red: the
	# want_red arm above would otherwise pass over a reader that never ran.
	want_broken "rd_run: an arm with no program checks nothing" \
		'no program was built' -- rd_run "$WORK/rd/none" none.c c03_strcmp_sign 1
else
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no --oracle was supplied, so the comparison" >&2
		echo "             exercises' corpora were not run over their toys." >&2
		exit 2
	}
	printf '  %-52s %s\n' "plain corpora and readings: (no oracle)" "skipped"
fi

printf '\n  %d checks passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || {
	printf '\n  A runner stopped detecting the thing it exists to detect. That is\n'
	printf '  worse than a red exercise: every test using it now reports OK\n'
	printf '  without checking. Fix the runner before trusting any suite result.\n'
	exit 1
}
exit 0
