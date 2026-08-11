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
require cat chmod dirname env grep ln mkdir mktemp rm

ANCHOR=""
PERF_RUN=""
VALGRIND=""
VGTOOLS=""
VGCGTOOLS=""
CG_ANNOTATE=""
ZIG=""

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
		*) echo "selftest_slow.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$ANCHOR" ] || { echo "selftest_slow.sh: --anchor is required" >&2; exit 2; }
[ -f "$ANCHOR" ] || { echo "selftest_slow.sh: anchor $ANCHOR does not exist" >&2; exit 2; }
TOOLS=$(dirname "$ANCHOR")

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

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

CC=${SELFTEST_CC:-cc}
# NO_SKIP=1 must reach this. Everything below needs a compiler, including the
# only arms in the repo that prove the valgrind layer can still SEE a leak -- so
# without the guard a compiler-less box exits 0 having checked none of it, and
# the forced sweep, whose entire job is finding layers that are merely quiet,
# cannot tell that from a clean run.
command -v "$CC" > /dev/null 2>&1 || {
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no C compiler ('$CC'), so none of the slow arms ran and" >&2
		echo "             the valgrind and perf layers are unproven." >&2
		exit 2
	}
	echo "selftest_slow: SKIP — no C compiler"
	exit 0
}
# A hard error rather than a skip, for the same reason it is one in the layer:
# a skip here is indistinguishable from "the leak layer is fine".
[ -n "$VALGRIND" ] && [ -x "$VALGRIND" ] || {
	echo "selftest_slow: --valgrind is required (the pinned valgrind.bin)" >&2
	exit 2
}
VG_PASS="--valgrind $VALGRIND --valgrind-tools $VGTOOLS"
CG_PASS="--valgrind $VALGRIND --valgrind-tools $VGCGTOOLS --callgrind-annotate $CG_ANNOTATE"

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
for _p in vg_clean vg_leak vg_oob vg_uninit; do
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
for _t in sh "$SH" basename cut grep head mktemp rm sed dirname readlink; do
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

want_green "valgrind: a program that frees what it allocates passes" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_clean"
want_red   "valgrind: a leak is detected" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_leak"
want_red   "valgrind: a read past the end of a block is detected" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_oob"
want_red   "valgrind: use of an uninitialised heap byte is detected" -- \
	"$SH" "$TOOLS/valgrind_test.sh" $VG_PASS --bin "$WORK/vg_uninit"

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
else
	printf '  %-52s %s\n' "perf: --runner was not supplied" \
		"FAIL < (nothing was measured)"
	FAIL=$((FAIL + 1))
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

# ----------------------------------------------------------------------- ilp32
# The layer's VERDICT -- build the same fixture at -m32, run it, diff it -- was
# tested nowhere. Both arms in the fast selftest stop at the missing-compiler
# SKIP, and that file's own comment claimed the functional half "belongs in a
# slower target", which read as though this one already had it. It did not.
#
# The fixture is the lesson the layer exists for: surviving INT_MIN by widening
# into a `long`. That works on this LP64 box and is wrong wherever `long` is no
# wider than `int` -- which C permits, and 32-bit Linux does.
mkdir -p "$WORK/i32"
cat > "$WORK/i32/harness.c" <<'ILP32_H'
/* Line: prints |INT_MIN| as a 64-bit value. */
#include <stdio.h>

long long	ft_probe_abs(int n);

int	main(void)
{
	printf("%lld\n", ft_probe_abs(-2147483647 - 1));
	return (0);
}
ILP32_H
# Portable: the negation happens in a type that is 64 bits everywhere.
cat > "$WORK/i32/ok.c" <<'ILP32_OK'
long long	ft_probe_abs(int n)
{
	if (n < 0)
		return (-(long long)n);
	return ((long long)n);
}
ILP32_OK
# The mistake: widen into `long`, negate there. 2147483648 on LP64; on ILP32 the
# negation overflows and the value comes back INT_MIN again.
cat > "$WORK/i32/bad.c" <<'ILP32_BAD'
long long	ft_probe_abs(int n)
{
	long	x;

	x = n;
	if (x < 0)
		x = -x;
	return ((long long)x);
}
ILP32_BAD
printf '2147483648\n' > "$WORK/i32/expected.txt"

i32_run() {
	"$SH" "$TOOLS/ilp32_test.sh" --zig "$ZIG" \
		--differ "$TOOLS/diff_output.sh" \
		--harness "$WORK/i32/harness.c" \
		--expected "$WORK/i32/expected.txt" \
		--src "$WORK/i32/$1.c"
}

if [ -n "$ZIG" ] && [ -x "$ZIG" ]; then
	want_green "ilp32: code that is portable passes at -m32" -- i32_run ok
	want_red   "ilp32: widening INT_MIN into a long fails at -m32" -- i32_run bad
else
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no --zig was supplied, so the ilp32 layer's verdict" >&2
		echo "             was not exercised at all." >&2
		exit 2
	}
	printf '  %-52s %s\n' "ilp32: (no pinned zig supplied)" "skipped"
fi

printf '\n  %d checks passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || {
	printf '\n  A runner stopped detecting the thing it exists to detect. That is\n'
	printf '  worse than a red exercise: every test using it now reports OK\n'
	printf '  without checking. Fix the runner before trusting any suite result.\n'
	exit 1
}
exit 0
