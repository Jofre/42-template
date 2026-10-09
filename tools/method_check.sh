#!/bin/sh
# The method layer (tag "method", at strict): what a subject says about HOW a
# turn-in is built, which nothing it prints can show (finding 065, 114).
#
# Two questions, one per mode. Each is a sentence of the exercise's own
# subject, quoted at the call site (--rule): a runner quotes no subject of its
# own accord, since every project that calls it would hear it.
#
#   --expect recursive|iterative
#       "Create a recursive function", "must be implemented recursively",
#       "Recursion is required" -- and "Create an iterative function". Read as
#       every reading agrees: RECURSIVE is "some function of the turned-in file
#       is entered again while it is still running" -- the exercise's function
#       itself, a static helper, or two that call each other; ITERATIVE is
#       "none ever is". A closed form or a table is iterative; a loop over an
#       explicit stack of its own is not recursive. Observed, never read from
#       the text: the student's sources, and only those, are compiled at -O0
#       with -finstrument-functions, linked with the exercise's own test
#       program and tools/method_shim.c (neither instrumented), and run once;
#       the shim keeps a stack of the functions running and writes
#       "reentered" the moment one starts while already on it (and ends the
#       run there), or "done" when the run ends with none -- one line per
#       process, so a test program that forks keeps its child's "reentered",
#       which is decisive wherever it happened. Gated on the
#       exercise's own output fixture: a stub calls nothing twice, and an
#       answer that is still wrong has nothing to say about how it is right.
#
#   --fixed-array [--max-bytes N]
#       "You must complete this exercise by declaring a fixed-size array",
#       and where the subject bounds it ("This array should have a size
#       limited to slightly less than 30 ko"), the bound, which the call site
#       states in bytes with its reading. Observed by the pinned gcc, never
#       read from the text: each source is compiled (to assembly, nothing
#       kept) with -Wvla and -Walloca -- a size the program learns as it runs
#       is not a fixed one -- and, with N, -Wlarger-than=N-1, which names
#       every object, on the stack or not, of N bytes or more by the size the
#       compiler gives it. An UPPER bound only: "slightly less than" does not
#       say how much less, and a test that asked for a large buffer would
#       invent a requirement. The object, not the stack frame: a frame holds
#       the function's other variables too, and an array just under the bound
#       would read as over it. Before it reads a single student file it
#       compiles three probes of its own, one each the three warnings must
#       name, so a compiler that stopped reporting one is a broken harness,
#       never a pass. A turn-in gcc cannot compile is the compile layers'
#       red: this SKIPs, and NO_SKIP=1 turns that red. Whether the program
#       declares an array at all is not read.
#
# Usage:
#   method_check.sh --expect recursive|iterative --rule FILE
#                   --harness FILE --shim FILE --src FILE... [--grader-src FILE]...
#                   [--inc FILE]... --cc PATH [--cc-lib FILE]...
#                   --ld PATH --ld-lib FILE...
#                   [--gate-differ P --gate-bin P --gate-expected P
#                    [--gate-sanitize] [--gate-labeled]]
#   method_check.sh --fixed-array [--max-bytes N] --rule FILE
#                   --src FILE... [--inc FILE]... [--inc-file FILE]
#                   --cc PATH [--cc-under FILE]
#
#   --rule FILE     the subject's sentence, as the call site quotes it, with
#                   where it is from (and, for a bound, how it is read)
#   --harness FILE  the exercise's own test program (a main), not instrumented
#   --shim FILE     tools/method_shim.c
#   --src FILE      a source the student turned in
#   --grader-src FILE  a source the grader brings, linked and not instrumented
#   --inc FILE      a header the sources include: its folder joins -I
#   --inc-file FILE the -I directories a Makefile's recipes pass, one per line
#   --cc, --cc-lib, --cc-under  the pinned compiler, proved pinned by
#                   runner_lib.sh's rl_cc_pin (clang for --expect, gcc for
#                   --fixed-array: only gcc names an object's size)
#   --ld, --ld-lib  the pinned ld.bfd and the libraries it loads, for
#                   --expect, which links its probe: proved by rl_ld_pin
#   --gate-sanitize, --gate-labeled  how the output test compares the
#                   fixture the gate replays (diff_output.sh's --sanitize and
#                   --labeled), as the memory layers' gates take them: a
#                   fixture read the other way is red on a right answer, and
#                   the layer would stand down for good
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "method_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk dirname grep mktemp rm sed

# The shared runner helpers -- time budget, exiting signal traps, how a run
# ended, excerpts, the gate, the fetched compiler's proof -- written once in
# tools/runner_lib.sh.
RL_NAME=method_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "method_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool CC -- the pinned compiler: it builds, and runs none of what it builds

MODE=""
EXPECT=""
RULE=""
HARNESS=""
SHIM=""
SRCS=""
GSRCS=""
INCS=""
MAX=""
CC=""
CC_LIBS=""
CC_UNDER=""
LD=""
LD_LIBS=""
GATE_DIFFER=""
GATE_BIN=""
GATE_EXPECTED=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "method_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--expect)
			need "$1" "$#"
			case "$2" in
				recursive | iterative) EXPECT="$2" ;;
				*) echo "method_check.sh: --expect is recursive or iterative, not '$2'" >&2; exit 2 ;;
			esac
			if [ -n "$MODE" ]; then MODE=both; else MODE=expect; fi
			shift 2 ;;
		--fixed-array)
			if [ -n "$MODE" ]; then MODE=both; else MODE=fixed; fi
			shift ;;
		--max-bytes)
			need "$1" "$#"
			case "$2" in
				'' | *[!0-9]* | 0 | 1) echo "method_check.sh: --max-bytes is a number of bytes above 1, not '$2'" >&2; exit 2 ;;
			esac
			MAX="$2"; shift 2 ;;
		--rule) need "$1" "$#"; RULE="$2"; shift 2 ;;
		--harness) need "$1" "$#"; HARNESS="$2"; shift 2 ;;
		--shim) need "$1" "$#"; SHIM="$2"; shift 2 ;;
		--src) need "$1" "$#"; rl_list_add SRCS "$2"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--grader-src) need "$1" "$#"; rl_list_add GSRCS "$2"; shift 2 ;;
		--inc) need "$1" "$#"; rl_list_add INCS "-I$(dirname "$2")"; shift 2 ;;
		--inc-file)
			need "$1" "$#"
			[ -f "$2" ] || { echo "method_check.sh: no include list at $2" >&2; exit 2; }
			while IFS= read -r _i; do
				[ -n "$_i" ] || continue
				rl_list_add INCS "-I$_i"
			done < "$2"
			shift 2 ;;
		--cc) need "$1" "$#"; CC="$2"; shift 2 ;;
		--cc-lib) need "$1" "$#"; rl_list_add CC_LIBS "$2"; shift 2 ;;
		--cc-under) need "$1" "$#"; CC_UNDER="$2"; shift 2 ;;
		--ld) need "$1" "$#"; LD="$2"; shift 2 ;;
		--ld-lib) need "$1" "$#"; rl_list_add LD_LIBS "$2"; shift 2 ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-sanitize) rl_list_add RL_GATE_PASS --sanitize; shift ;;
		--gate-labeled) rl_list_add RL_GATE_PASS --labeled; shift ;;
		*) echo "method_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

case "$MODE" in
	expect | fixed) ;;
	both) echo "method_check.sh: --expect and --fixed-array are two questions: one per test" >&2; exit 2 ;;
	*) echo "method_check.sh: say which question: --expect recursive|iterative, or --fixed-array" >&2; exit 2 ;;
esac
[ -n "$RULE" ] && [ -f "$RULE" ] || {
	echo "method_check.sh: --rule FILE is required: the subject's sentence, as the call site quotes it" >&2
	exit 2
}
[ -n "$SRCS" ] || { echo "method_check.sh: at least one --src is required" >&2; exit 2; }
[ -n "$CC" ] || { echo "method_check.sh: --cc is required (the pinned compiler)" >&2; exit 2; }
if [ "$MODE" = expect ]; then
	[ -n "$HARNESS" ] && [ -f "$HARNESS" ] || { echo "method_check.sh: --expect needs --harness FILE, the exercise's test program" >&2; exit 2; }
	[ -n "$SHIM" ] && [ -f "$SHIM" ] || { echo "method_check.sh: --expect needs --shim FILE (tools/method_shim.c)" >&2; exit 2; }
	[ -z "$MAX" ] || { echo "method_check.sh: --max-bytes goes with --fixed-array" >&2; exit 2; }
	[ -n "$LD" ] || { echo "method_check.sh: --expect needs --ld PATH, the pinned ld.bfd it links its probe with" >&2; exit 2; }
else
	[ -z "$LD" ] || { echo "method_check.sh: --ld goes with --expect: --fixed-array links nothing" >&2; exit 2; }
fi
rl_cc_pin "$CC" "$CC_LIBS" "$CC_UNDER"

WORK=$(mktemp -d) || { echo "method_check.sh: cannot create a scratch directory" >&2; exit 2; }
rl_traps 'rm -rf "$WORK"'

# --expect LINKS its probe, and the clang package has no linker of its own:
# without the pinned one every link ran the box's /usr/bin/ld (TO VERIFY V38).
# tools/runner_lib.sh's rl_ld_pin proves it before the first link.
RL_LDFLAG=""
[ "$MODE" != expect ] || rl_ld_pin "$CC" "$LD" "$LD_LIBS" "$WORK/ld"

# The call site's sentence, indented under the verdict.
say_rule() {
	echo "  The subject, as this exercise's BUILD file quotes it:"
	sed 's/^/    /' "$RULE"
}

# ---------------------------------------------------------------------------
# --fixed-array
if [ "$MODE" = fixed ]; then
	# gcc words its diagnostics in the locale's quotes; read them in C's.
	LC_ALL=C
	export LC_ALL
	WFLAGS=""
	rl_list_add WFLAGS -Wvla -Walloca
	[ -z "$MAX" ] || rl_list_add WFLAGS "-Wlarger-than=$((MAX - 1))"

	# THE PROBES: one object each warning must name, so a compiler that
	# stopped naming one -- another gcc, a clang, which accepts
	# -Wlarger-than= and says nothing -- is a broken harness, not a pass.
	{
		echo "char	method_probe_vla(int n);"
		echo "char	*method_probe_alloca(int n);"
		echo "char	method_probe_vla(int n)"
		echo "{"
		echo "	char	v[n];"
		echo ""
		echo "	v[0] = 0;"
		echo "	return (v[0]);"
		echo "}"
		echo "char	*method_probe_alloca(int n)"
		echo "{"
		echo "	return (__builtin_alloca(n));"
		echo "}"
		[ -z "$MAX" ] || echo "char	g_method_probe[$MAX];"
	} > "$WORK/probe.c"
	rl_split_on
	# shellcheck disable=SC2086 # the lists split into their lines (THE LISTS)
	"$CC" ${RL_LDFLAG:+"$RL_LDFLAG"} -S -o "$WORK/probe.s" $WFLAGS "$WORK/probe.c" > "$WORK/probe.err" 2>&1
	rl_split_off
	for _w in vla alloca ${MAX:+larger-than=}; do
		grep -qF -- "[-W$_w]" "$WORK/probe.err" && continue
		echo "method_check.sh: '${CC##*/}' did not report -W$_w on a probe made to have one:" >&2
		sed 's/^/  /' "$WORK/probe.err" >&2
		echo "  This mode reads gcc's own warnings (-Wvla, -Walloca, -Wlarger-than=)," >&2
		echo "  and a compiler that does not give them would pass every turn-in." >&2
		exit 2
	done

	N=0
	FAILED=""
	: > "$WORK/found.raw"
	rl_split_on
	# shellcheck disable=SC2086 # the lists split into their lines (THE LISTS)
	for s in $SRCS; do
		N=$((N + 1))
		# shellcheck disable=SC2086
		if ! "$CC" ${RL_LDFLAG:+"$RL_LDFLAG"} -S -o "$WORK/s.s" $WFLAGS $INCS "$s" > "$WORK/s.err" 2>&1; then
			FAILED="$s"
			break
		fi
		# Each warning's own location, FILE:LINE:COL, names where the object
		# is: a header the source includes, as often as the source itself.
		awk -v f="$s" '
			/ warning: / && /\[-W(vla|alloca|larger-than=)\]$/ {
				loc = $0
				sub(/: warning: .*/, "", loc)
				file = f
				line = "?"
				if (match(loc, /:[0-9]+(:[0-9]+)?$/)) {
					file = substr(loc, 1, RSTART - 1)
					split(substr(loc, RSTART + 1), lc, ":")
					line = lc[1]
				}
				msg = $0
				sub(/^.*: warning: /, "", msg)
				print file "\t" line "\t" msg
			}' "$WORK/s.err" >> "$WORK/found.raw"
	done
	rl_split_off
	# A header two sources include is compiled, and named, twice: once each.
	awk '!seen[$0]++' "$WORK/found.raw" > "$WORK/found.txt"
	if [ -n "$FAILED" ]; then
		if [ "${NO_SKIP:-0}" = 1 ]; then
			echo "method_check: FAIL — NO_SKIP set, and the pinned ${CC##*/} could not compile"
			echo "  $FAILED, so no array in it was measured:"
			rl_excerpt "$WORK/s.err" 15 compiler-output.txt "    "
			exit 1
		fi
		echo "method_check: SKIP — the pinned ${CC##*/} could not compile $FAILED,"
		echo "  so no array in it could be measured. The compile layers say why, in"
		echo "  the compiler's words; once they are green this test reads the arrays."
		echo "  ($(rl_noskip_cmd) makes this skip red.)"
		exit 0
	fi
	if [ -s "$WORK/found.txt" ]; then
		_k=$(awk 'END { print NR }' "$WORK/found.txt")
		echo "method_check: FAIL — $_k object(s) the subject's fixed-size array rules out:"
		while IFS='	' read -r _f _l _m; do
			case "$_m" in
				*"[-Wlarger-than=]")
					_name=$(printf '%s\n' "$_m" | sed -n "s/^size of '\(.*\)' \([0-9]*\) bytes.*/\1/p")
					_size=$(printf '%s\n' "$_m" | sed -n "s/^size of '.*' \([0-9]*\) bytes.*/\1/p")
					echo "  $_f, line $_l: '$_name' is $_size bytes; this test holds every object to"
					echo "    fewer than $MAX bytes." ;;
				*"[-Wvla]")
					_name=$(printf '%s\n' "$_m" | sed -n "s/.*variable length array '\(.*\)'.*/\1/p")
					echo "  $_f, line $_l: '${_name:-an array}' is an array of variable length: its size"
					echo "    is only known once the program runs, so it is not a fixed one." ;;
				*)
					echo "  $_f, line $_l: alloca() takes stack memory of a size known only once"
					echo "    the program runs, so it is not a fixed-size array." ;;
			esac
		done < "$WORK/found.txt"
		echo ""
		say_rule
		echo "  Measured by the pinned ${CC##*/}, which names each object by the size it"
		echo "  gives it. Which size does your program need to know before it starts, and"
		echo "  how does the process's stack limit (ulimit -s) count it?"
		exit 1
	fi
	echo "method_check: OK — $N file(s) compiled by the pinned ${CC##*/}: no array of variable"
	if [ -n "$MAX" ]; then
		echo "  length, no alloca, and no object of $MAX bytes or more."
	else
		echo "  length and no alloca: every array's size is fixed when it is compiled."
	fi
	say_rule
	echo "  Whether the program declares an array at all is not something this test"
	echo "  reads."
	exit 0
fi

# ---------------------------------------------------------------------------
# --expect recursive|iterative
#
# The gate first: while the exercise's own output fixture is red, there is no
# right answer whose method to read. Its words are this layer's: it replays
# nothing, so the corpus paragraph rl_gate prints by default is not true here.
RL_GATE_WHY="  That fixture is the subject's own example, with a table and hints
  attached. This layer reads HOW a right result is reached -- whether a
  function of yours is entered again while it is still running -- and there
  is nothing to read yet: a stub calls nothing twice, and an answer that is
  still wrong has no right result. Once the *_output layer is green, this
  one reads how it is reached."
rl_gate method_check "$GATE_DIFFER" "$GATE_BIN" "$GATE_EXPECTED"

: > "$WORK/cc.err"
BUILD_OK=1
OBJS=""
_k=0
rl_split_on
# shellcheck disable=SC2086 # the lists split into their lines (THE LISTS)
for s in $SRCS; do
	_k=$((_k + 1))
	"$CC" "$RL_LDFLAG" -c -O0 -finstrument-functions $INCS "$s" -o "$WORK/student_$_k.o" >> "$WORK/cc.err" 2>&1 || BUILD_OK=0
	rl_list_add OBJS "$WORK/student_$_k.o"
done
# shellcheck disable=SC2086
for s in $GSRCS; do
	_k=$((_k + 1))
	"$CC" "$RL_LDFLAG" -c -O0 $INCS "$s" -o "$WORK/grader_$_k.o" >> "$WORK/cc.err" 2>&1 || BUILD_OK=0
	rl_list_add OBJS "$WORK/grader_$_k.o"
done
# shellcheck disable=SC2086
"$CC" "$RL_LDFLAG" -c -O0 $INCS "$HARNESS" -o "$WORK/harness.o" >> "$WORK/cc.err" 2>&1 || BUILD_OK=0
"$CC" "$RL_LDFLAG" -c -O0 "$SHIM" -o "$WORK/shim.o" >> "$WORK/cc.err" 2>&1 || BUILD_OK=0
if [ "$BUILD_OK" -eq 1 ]; then
	# shellcheck disable=SC2086
	"$CC" "$RL_LDFLAG" $OBJS "$WORK/harness.o" "$WORK/shim.o" -o "$WORK/probe" >> "$WORK/cc.err" 2>&1 || BUILD_OK=0
fi
rl_split_off
if [ "$BUILD_OK" -ne 1 ]; then
	echo "method_check: FAIL — the turned-in file did not build with this exercise's test"
	echo "  program and the method layer's recorder, so how it runs was not seen."
	echo "  The compile and output layers say the same in their own words; read"
	echo "  theirs first."
	echo "  ---------------- compiler output ----------------"
	rl_excerpt "$WORK/cc.err" 25 compiler-output.txt "  "
	exit 1
fi

METHOD_REPORT="$WORK/report"
export METHOD_REPORT
rl_tmo || { rl_overrun "the instrumented run"; exit 1; }
(
	# The program's output is not this test's: only how it calls itself.
	ulimit -f 2048 2> /dev/null
	rl_run "$WORK/probe" < /dev/null > /dev/null 2> "$WORK/run.err"
)
rl_classify "$?"

# One line per process that reported (tools/method_shim.c appends): a test
# program that forks has several. A re-entry anywhere is decisive -- the
# process it happened in ended there, and its parent's "done" says nothing of
# it; otherwise a recorder that ran out of room; otherwise "done", with the
# busiest process's counts: a child starts with a copy of its parent's, so a
# sum would count the parent's twice.
WHAT=""
STARTS=0
DEEPEST=0
PROCS=0
if [ -s "$WORK/report" ]; then
	read -r WHAT STARTS DEEPEST PROCS <<_REPORT
$(awk '
	$1 == "reentered" || $1 == "overflow" || $1 == "done" {
		n++
		if ($1 == "reentered" && r == "") r = $1 " " $2 " " $3
		if ($1 == "overflow" && o == "") o = $1 " " $2 " " $3
		if ($2 + 0 > s) s = $2 + 0
		if ($3 + 0 > d) d = $3 + 0
	}
	END {
		if (n == 0) exit
		if (r != "") print r, n
		else if (o != "") print o, n
		else print "done", s + 0, d + 0, n
	}' "$WORK/report")
_REPORT
fi
# Under the counts, when they are not one process's: the reader would take
# them for the whole run's.
procs_note() {
	[ "${PROCS:-0}" -gt 1 ] || return 0
	echo "  (The test program ran as $PROCS processes, each reporting; the counts"
	echo "  are one process's: the one that re-entered, or else the busiest.)"
}
case "$WHAT" in
	reentered | "done") ;;
	overflow)
		echo "method_check.sh: more functions of the turned-in file ran at once than the" >&2
		echo "  recorder holds (tools/method_shim.c's METHOD_DEPTH), with none re-entered." >&2
		exit 2 ;;
	*)
		if [ "$RL_CAUSE" = timeout ]; then
			rl_overrun "the instrumented run of this exercise's test program"
			exit 1
		fi
		echo "method_check: FAIL — the instrumented run $RL_WHY"
		echo "  before it could say whether a function of the turned-in file was entered"
		echo "  again while it ran, so the method the subject asks for was not seen"
		echo "  either way. The output layer runs the same test program without the"
		echo "  recorder: read it first."
		rl_excerpt "$WORK/run.err" 10 run-stderr.txt "    "
		exit 1 ;;
esac
if [ "$STARTS" = 0 ]; then
	echo "method_check.sh: no function of the turned-in file started in the whole run," >&2
	echo "  so -finstrument-functions did not take, or the test program calls none" >&2
	echo "  in a process that reports (a child that ends with _exit(2) writes" >&2
	echo "  nothing): nothing was observed, and that is the harness's fault." >&2
	exit 2
fi

if [ "$EXPECT" = recursive ] && [ "$WHAT" = reentered ]; then
	echo "method_check: OK — recursive: a function of the turned-in file was entered again"
	echo "  while it was still running (at function start $STARTS of the run, $DEEPEST deep),"
	echo "  on this exercise's own test program."
	procs_note
	say_rule
	exit 0
fi
if [ "$EXPECT" = iterative ] && [ "$WHAT" = "done" ]; then
	echo "method_check: OK — iterative: over the whole run of this exercise's own test"
	echo "  program, $STARTS function start(s) in the turned-in file, at most $DEEPEST running"
	echo "  at once, and none was entered again while it was still running."
	procs_note
	say_rule
	exit 0
fi
if [ "$EXPECT" = recursive ]; then
	echo "method_check: FAIL — not recursive: over the whole run of this exercise's own"
	echo "  test program, $STARTS function start(s) in the turned-in file, at most $DEEPEST"
	echo "  running at once, and none was entered again while it was still running:"
	echo "  nothing in the file calls itself, directly or through another of its"
	echo "  functions."
	procs_note
	say_rule
	echo "  This test reads how the result is reached, never the result itself. Where"
	echo "  would your function hand a smaller part of the same work to a call of"
	echo "  itself?"
	exit 1
fi
echo "method_check: FAIL — not iterative: a function of the turned-in file was entered"
echo "  again while it was still running (at function start $STARTS of the run, $DEEPEST"
echo "  deep): it calls itself, directly or through another of its functions."
procs_note
say_rule
echo "  This test reads how the result is reached, never the result itself. What"
echo "  would a loop have to keep from one turn to the next to do the same work?"
exit 1
