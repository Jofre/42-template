#!/bin/sh
# Run a deliverable under valgrind/memcheck and fail on any leak or invalid
# memory access (tag "valgrind").
#
# This is the only layer in the suite that can see a block that was allocated
# and then never accounted for. A leak changes no output byte, returns no error
# and crashes nothing, so every diff layer and every sanitizer layer stays green
# on a program that loses every allocation it makes (rust_diff.sh and
# asan_run.sh both set detect_leaks=0 precisely so that leaks are THIS layer's
# finding and not a confusing "out of bounds" headline in theirs). The malloc
# modules are graded on exactly that, which is why every exercise whose subject
# authorises malloc carries this test -- `c_function(malloc = True)` is what
# emits it, so the set follows the subjects rather than a list kept here.
#
# What the exit status means to the caller:
#   0  valgrind was clean — or the layer deliberately SKIPPED and said so
#   1  the student's code has a finding
#   2  the harness itself could not run the check
# Keeping 2 for harness breakage matters here more than anywhere else: this
# script used to conflate valgrind's verdict (--error-exitcode), the child dying
# on a signal, and valgrind not being installed at all (127) into one sentence,
# so a stale container image printed a red MEMORY verdict at students who had
# written nothing wrong.
#
# Usage:
#   valgrind_test.sh --bin PATH --valgrind PATH --valgrind-tools FILE
#                    [--label NAME] [--stdin FILE] [--clues FILE]
#                    [--argv-file FILE] [--run-as NAME [--cwd-file DEST=PATH]...]
#                    [--show-run PROG] [--case NAME]
#                    [--timeout SECS] [--no-leak-check] [--rule FILE]
#                    [--status-file PATH] [--brief]
#                    [--gate-differ FILE --gate-bin PATH --gate-expected FILE
#                     [--gate-expected-alt FILE]... [--gate-stdin FILE]
#                     [--gate-stream NAME] [--gate-sanitize] [--gate-labeled]]
#                    [-- PROG ARGS...]
#   valgrind_test.sh --explain KEY...
#
#   --gate-expected-alt  another output the gated case accepts (a case's
#                    "any_of"), handed to the differ as --expected-alt.
#
#   --argv-file, --run-as, --cwd-file, --show-run and --case mean what
#                    tools/diff_output.sh's options of those names mean, and
#                    the first three reach the gate too: the fixture a case
#                    is gated on is the one its own run produces, from the
#                    same arguments and the same folder (c_program's
#                    "argv_file" and "cwd_files"). --case keys the hints:
#                    this layer has no table, so a clues.tsv row fires when
#                    it names this case, names this layer ("valgrind"), or
#                    names none.
#
#   --status-file PATH  write "timeout" there when the run ran out of its time
#                    (or had none left to start), as a corpus runner needs to
#                    know: a case its test's own limit cut short is not one
#                    memcheck judged (tools/runner_lib.sh, rl_mem_run). A
#                    second line, "clamped S", says the limit that stopped it
#                    was what the TEST had left, S seconds: its own rl_tmo
#                    found less left than --timeout, or the ceiling stopped
#                    the run first (exit_status's "ceiling Q"). The runner
#                    cannot tell from its side: it set the case's cap
#                    before the run, and a busy CPU's queue can carry the
#                    run's wall time to the ceiling before its own time
#                    reaches the cap (V33).
#
#   --brief          one case of a corpus replayed under memcheck (tools/
#                    runner_lib.sh's rl_mem_run): the verdict and its
#                    evidence -- memcheck's report, the descriptors left open,
#                    how the run ended -- and none of the paragraphs that say
#                    what a class of finding means, or the rule a memory
#                    finding breaks ("rule"). Each paragraph left out is
#                    named on a line of --status-file, "explain KEY", and the
#                    runner prints each once, after the cases, with
#                    --explain. A corpus printed the descriptor paragraph
#                    once per case: 25 times, 508 and 700 lines of log for
#                    one mistake (V53).
#   --explain KEY    print the paragraph --brief named KEY, and run nothing.
#                    Repeatable; in the order given. "rule" reads --rule and
#                    --no-leak-check, as the run it explains did.
#
#   --no-leak-check  run memcheck with leak reporting OFF and drop the leak
#                    classes from the classifier, leaving invalid read/write,
#                    invalid free and uninitialised value -- the findings that
#                    need no allocation. For a probe binary that is not the
#                    student's program and is not expected to free what it
#                    allocated.
#   --rule FILE      the sentence of the project's own subject that states a
#                    memory rule, naming where it is from (Rush 02, p.7: "Any
#                    memory allocated on the heap ... must be freed
#                    correctly"). A FAIL quotes it. Without one, a FAIL states
#                    the rule this layer applies and says it is this repo's:
#                    most subjects have no such sentence, and the report used
#                    to send every student to "the paragraph on memory
#                    management" of a subject that has none (finding 082).
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "valgrind_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk basename dirname fold grep head mktemp readlink rm sed

# The shared runner helpers -- time budget, exiting signal traps, how a run
# ended, excerpts, hints -- written once in tools/runner_lib.sh.
RL_NAME=valgrind_test
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "valgrind_test.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool GATE_DIFFER -- tools/diff_output.sh, the output gate, which keeps this test's budget (RL_DEADLINE)

BIN=""
# Leak reporting off: see --no-leak-check in the header.
NO_LEAK_CHECK=0
LABEL=""
STDIN_FILE=""
CLUES=""
# valgrind runs the program on a synthetic CPU: 20-50x slower than native is
# normal, so the inner budget is deliberately looser than run_check.sh's 20s and
# diff_output.sh's 30s. It still has to be well under Bazel's own timeout, or an
# infinite loop surfaces as an opaque Bazel kill with nothing a student can act
# on. Every exercise wired to this layer finishes in well under a second.
TIMEOUT="${VALGRIND_TIMEOUT:-60}"
GATE_DIFFER=""
GATE_BIN=""
GATE_EXPECTED=""
GATE_PASS=""
VALGRIND=""
VGTOOLS=""
ARGV_FILE=""
RUN_AS=""
CWD_FILES=""
SHOW_RUN=""
CASE_NAME=""
RULE=""
STATUS_FILE=""
BRIEF=0
EXPLAIN=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "valgrind_test.sh: $1 needs a value" >&2; exit 2; }; }

# ---------------------------------------------------------------------------
# WHAT A FINDING MEANS, one paragraph per KEY, and one copy of each: printed
# under the finding it explains, or -- for one case of a corpus (--brief) --
# named on a line of --status-file and printed once after the cases by the
# runner (--explain KEY), however many cases it explains. It names the class
# and says how to read the record; never what to change.
class_title() {  # class_title KEY -- the name a class:KEY paragraph leads with
	case "$1" in
		class:invalid-write) echo "INVALID WRITE" ;;
		class:invalid-read) echo "INVALID READ" ;;
		class:invalid-free) echo "INVALID FREE" ;;
		class:uninitialised) echo "UNINITIALISED VALUE" ;;
		class:definitely-lost) echo "DEFINITELY LOST" ;;
		class:indirectly-lost) echo "INDIRECTLY LOST" ;;
		class:possibly-lost) echo "POSSIBLY LOST" ;;
		class:still-reachable) echo "STILL REACHABLE" ;;
		class:other) echo "ANOTHER KIND OF ERROR" ;;
	esac
}
explain() {  # explain KEY -- its paragraph
	case "$1" in
	class:invalid-write)
		echo "  $(class_title "$1") — the program stored a byte outside any block it"
		echo "  owns. This is the most expensive bug class in C: the heap's own"
		echo "  bookkeeping lives immediately after each block, so a program that"
		echo "  writes one byte too far usually keeps running and dies much later,"
		echo "  somewhere with no connection to the code at fault."
		echo "  The 'Address 0x... is N bytes after a block of size M' line under"
		echo "  the trace names the allocation that was overrun and by how much."
		;;
	class:invalid-read)
		echo "  $(class_title "$1") — the program read from an address that is not inside"
		echo "  any block it owns: past the end (or before the start) of an"
		echo "  allocation, or inside one whose lifetime had already ended. What"
		echo "  comes back is whatever happened to be in that memory, which is why"
		echo "  THE OUTPUT CAN STILL LOOK CORRECT and no diff layer sees this."
		echo "  The 'Address 0x...' line under the trace names the allocation that"
		echo "  was overrun and the size it was requested with."
		;;
	class:invalid-free)
		echo "  $(class_title "$1") — the program handed the allocator an address that is"
		echo "  not the start of a live block: one already released, one that was"
		echo "  advanced or reassigned after the allocator returned it, or one that"
		echo "  never came from the allocator at all."
		echo "  Read the trace as 'here is the release', then find every place that"
		echo "  same pointer variable is assigned between the allocation and it."
		;;
	class:uninitialised)
		echo "  $(class_title "$1") — a decision (a branch, or a syscall such as"
		echo "  the write() this project's output goes through) depended on bytes"
		echo "  that were never given a value. Fresh memory from the allocator is"
		echo "  not zeroed; it holds whatever the previous owner left there."
		echo "  This is the class that passes on your machine and fails on"
		echo "  another -- $(rl_at) too -- because the leftover garbage differs"
		echo "  between runs."
		echo "  --track-origins is on, so the report also says where the"
		echo "  uninitialised bytes came from ('Uninitialised value was created"
		echo "  by a heap allocation')."
		;;
	class:definitely-lost)
		echo "  $(class_title "$1") — a block this program allocated was unreachable"
		echo "  when the process ended: no live pointer anywhere still held its"
		echo "  address. The address was overwritten, went out of scope, or was"
		echo "  never propagated back to whatever owns that block's lifetime."
		echo "  The trace in the report is where the block was ALLOCATED, not where"
		echo "  it was lost. Follow that pointer forward through every path out of"
		echo "  the function, the early returns and the error paths included."
		;;
	class:indirectly-lost)
		echo "  $(class_title "$1") — this block is reachable only through another"
		echo "  block that is itself lost: an array of pointers whose outer block"
		echo "  is lost takes every inner allocation down with it."
		echo "  These records are symptoms, not separate mistakes. Read the"
		echo "  'definitely lost' record for the OUTER block first; this count"
		echo "  normally falls to zero on its own once that one is accounted for."
		;;
	class:possibly-lost)
		echo "  $(class_title "$1") — the only surviving pointer to the block points"
		echo "  somewhere INSIDE it rather than at its first byte, so the address"
		echo "  the allocator handed out no longer exists anywhere in the program."
		echo "  This is what a pointer that walks a block looks like when it is the"
		echo "  only copy that was kept."
		;;
	class:still-reachable)
		echo "  $(class_title "$1") — the block was never released, but a live pointer"
		echo "  still held its address at exit, so nothing lost track of it."
		echo "  This layer reports every leak kind on purpose. 'The process was"
		echo "  about to exit anyway' is not the standard the malloc modules are"
		echo "  graded against: a function that allocates is judged on whether the"
		echo "  memory is accounted for, not on whether the OS tidied up after it."
		;;
	class:other)
		echo "  $(class_title "$1") — valgrind reported an error this layer does not"
		echo "  classify into one of the usual leak or invalid-access shapes. Read"
		echo "  the first block of its report: its first line is memcheck's own name"
		echo "  for what went wrong."
		;;
	trace)
		echo "  Reading the trace: the top 'at' line is the innermost frame and is"
		echo "  often inside libc or valgrind's replacement allocator; the 'by' line"
		echo "  under it is your code. Fix the FIRST record and re-run — later records"
		echo "  are frequently consequences of it."
		;;
	rule)
		# The standard, as the call site gives it: the subject's own
		# sentence where it has one (--rule), and otherwise this layer's
		# own rule, said to be this repo's. Never a paragraph of a subject
		# nobody quoted. A corpus said neither once --brief left the
		# paragraph out (the review of V53): only what was judged.
		if [ -n "$RULE" ]; then
			echo "  The sentence this applies:"
			fold -s -w 70 "$RULE" | sed 's/ *$//; s/^/    /'
		else
			echo "  The rule this layer applies: no read or write outside a"
			if [ "${NO_LEAK_CHECK:-0}" = 1 ]; then
				echo "  block, no free of what was not allocated, no decision on a value"
				echo "  never set."
			else
				echo "  block, no free of what was not allocated, no decision on a value"
				echo "  never set, and every block allocated freed by the end of the run."
			fi
			echo "  It is not a sentence of your subject's: it is checked because an"
			echo "  evaluator may run a memory checker on your work."
		fi
		;;
	fds)
		echo "  Every open() hands back a number the kernel holds for you until you"
		echo "  close() it or the process ends. A program that ends promptly gets away"
		echo "  with it; one that opens a file per argument meets the limit for real,"
		echo "  and the limit is a few hundred, not a few million."
		if [ "${VALGRIND_FDS:-}" = "lax" ]; then
			echo "  VALGRIND_FDS=lax, so this is a NOTE rather than a failure."
		else
			echo "  To get past it for now: --test_env=VALGRIND_FDS=lax."
		fi
		;;
	*)
		echo "valgrind_test.sh: --explain: no paragraph is named '$1'" >&2
		exit 2
		;;
	esac
}
# explained KEY -- KEY's paragraph here, or under --brief its name on a line
# of --status-file, for the runner to print once after the cases.
explained() {
	if [ "$BRIEF" = 0 ]; then
		explain "$1"
	elif [ -n "$STATUS_FILE" ]; then
		echo "explain $1" >> "$STATUS_FILE"
	fi
}


while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--valgrind) need "$1" "$#"; VALGRIND="$2"; shift 2 ;;
		--valgrind-tools) need "$1" "$#"; VGTOOLS="$2"; shift 2 ;;
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--stdin) need "$1" "$#"; STDIN_FILE="$2"; shift 2 ;;
		--clues) need "$1" "$#"; CLUES="$2"; shift 2 ;;
		--timeout) need "$1" "$#"; TIMEOUT="$2"; shift 2 ;;
		--status-file) need "$1" "$#"; STATUS_FILE="$2"; shift 2 ;;
		--brief) BRIEF=1; shift ;;
		--explain) need "$1" "$#"; rl_list_add EXPLAIN "$2"; shift 2 ;;
		--gate-differ) need "$1" "$#"; GATE_DIFFER="$2"; shift 2 ;;
		--gate-bin) need "$1" "$#"; GATE_BIN="$2"; shift 2 ;;
		--gate-expected) need "$1" "$#"; GATE_EXPECTED="$2"; shift 2 ;;
		--gate-stdin) need "$1" "$#"; rl_list_add GATE_PASS --stdin "$2"; shift 2 ;;
		--gate-expected-alt) need "$1" "$#"; rl_list_add GATE_PASS --expected-alt "$2"; shift 2 ;;
		--gate-stream) need "$1" "$#"; rl_list_add GATE_PASS --stream "$2"; shift 2 ;;
		--gate-sanitize) rl_list_add GATE_PASS --sanitize; shift ;;
		--gate-labeled) rl_list_add GATE_PASS --labeled; shift ;;
		--no-leak-check) NO_LEAK_CHECK=1; shift ;;
		--argv-file) need "$1" "$#"; ARGV_FILE="$2"; rl_list_add GATE_PASS --argv-file "$2"; shift 2 ;;
		--run-as) need "$1" "$#"; RUN_AS="$2"; rl_list_add GATE_PASS --run-as "$2"; shift 2 ;;
		--cwd-file) need "$1" "$#"; CWD_FILES="$CWD_FILES
$2"; rl_list_add GATE_PASS --cwd-file "$2"; shift 2 ;;
		--show-run) need "$1" "$#"; SHOW_RUN="$2"; shift 2 ;;
		--case) need "$1" "$#"; CASE_NAME="$2"; shift 2 ;;
		--rule)
			need "$1" "$#"
			[ -s "$2" ] || { echo "valgrind_test.sh: no sentence in --rule $2" >&2; exit 2; }
			RULE="$2"; shift 2 ;;
		--) shift; break ;;
		# The binary used to be accepted as a bare first argument. That shape is
		# gone: every caller passes --bin, and keeping a second spelling of the
		# same thing alive is how a reader learns that either is fine and then
		# copies the one nothing else uses.
		*) echo "valgrind_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

# --explain KEY...: the paragraphs the cases of a corpus named (--brief),
# each once, and no run.
if [ -n "$EXPLAIN" ]; then
	_sep=""
	rl_split_on
	for _k in $EXPLAIN; do
		printf '%s' "$_sep"
		_sep=$RL_NL
		explain "$_k"
	done
	rl_split_off
	exit 0
fi

[ -n "$BIN" ] || { echo "valgrind_test.sh: --bin is required" >&2; exit 2; }
# An unreadable or non-executable path is a wiring mistake (a data dep that was
# never declared, a $(location) that resolved to a source file), not a student
# finding — valgrind would answer 127 for it and the old script printed that as
# "leaks/errors".
if ! [ -f "$BIN" ] || ! [ -x "$BIN" ]; then
	echo "valgrind_test.sh: not an executable file: $BIN" >&2
	exit 2
fi
[ -n "$LABEL" ] || LABEL="$(basename "$BIN")"
# The run as the case describes it, or no run (tools/diff_output.sh says why).
if [ -n "$ARGV_FILE" ] && [ ! -r "$ARGV_FILE" ]; then
	echo "valgrind_test.sh: --argv-file '$ARGV_FILE' is not readable" >&2
	exit 2
fi
if [ -n "$CWD_FILES" ] && [ -z "$RUN_AS" ]; then
	echo "valgrind_test.sh: --cwd-file stages a file in the folder --run-as runs the program from" >&2
	exit 2
fi
case "$RUN_AS" in
	*/* | . | ..)
		echo "valgrind_test.sh: --run-as takes the program's file name, not '$RUN_AS'" >&2
		exit 2 ;;
esac

# ---------------------------------------------------------------------------
# The valgrind this layer runs is FETCHED AND PINNED, never found on PATH.
#
# It used to be `command -v valgrind`, and this is the layer where that mattered
# most: memcheck is the only thing in the suite that can see a leak, so its
# answer was the one most worth making independent of which box you sat at.
# There is no host fallback -- a missing --valgrind is a wiring error (exit 2),
# not a skip, because a skip here is indistinguishable from "no leaks".
[ -n "$VALGRIND" ] || {
	echo "valgrind_test.sh: --valgrind is required (the pinned valgrind.bin)" >&2
	echo "                  Pass \$(location @valgrind_ubuntu//:usr/bin/valgrind.bin)." >&2
	exit 2
}

# ABSOLUTISE BEFORE ANYTHING CHANGES DIRECTORY. Both paths arrive
# runfiles-relative, and every previous fetched tool in this repo was broken
# once by a later `cd` turning a working path into a missing one.
case "$VALGRIND" in
	/*) ;;
	*) VALGRIND="$PWD/$VALGRIND" ;;
esac

[ -f "$VALGRIND" ] && [ -x "$VALGRIND" ] || {
	echo "valgrind_test.sh: pinned valgrind is missing or not executable: $VALGRIND" >&2
	exit 2
}

# AND VERIFY IT CAN FIND ITS OWN TREE. This is the failure mode that has caught
# every fetched tool here at least once: a binary that cannot find part of
# itself does not necessarily fail -- it can fall back to the box's copy,
# report the pinned version, and go green. valgrind is packaged for
# /usr/libexec/valgrind and reads $VALGRIND_LIB to be told otherwise, so the
# check is that the directory exists AND holds the tool binary this layer runs.
# Checking the directory alone would pass on an empty one.
[ -n "$VGTOOLS" ] || {
	echo "valgrind_test.sh: --valgrind-tools is required (a file in valgrind's" >&2
	echo "                  own tool directory; it cannot start without one)" >&2
	exit 2
}
# The tool directory is derived from a FILE inside it, not passed as a
# directory, and that is deliberate: `$(location x)/..` walks through a file
# rather than naming its parent, and `cd && pwd` stops at the runfiles tree,
# whose directories are real while the files in them are symlinks. Resolving the
# file with readlink -f and taking ITS directory is the one form that survives
# both. This repo has been bitten by the other two.
VGTOOLS=$(readlink -f "$VGTOOLS" 2> /dev/null || echo "$VGTOOLS")
VGLIB=$(dirname "$VGTOOLS")
[ -f "$VGLIB/memcheck-amd64-linux" ] || {
	echo "valgrind_test.sh: $VGLIB does not hold memcheck-amd64-linux, so the" >&2
	echo "                  pinned valgrind cannot run its own tool. This is a" >&2
	echo "                  wiring error, not a student finding." >&2
	exit 2
}
VALGRIND_LIB="$VGLIB"
export VALGRIND_LIB

# ---------------------------------------------------------------------------
# Correctness gate: run the exercise's own curated fixture first, and SKIP while
# it is still red. Same shape, same argument names and the same fail-open rule
# as tools/rust_diff.sh, so both can be wired from defs.bzl identically.
#
# Alone among the rigour layers this one had no gate, which is the worst place
# to be missing one: a student whose function is still a stub was met with raw
# "indirectly lost" loss records — a report about allocations made by code they
# are about to rewrite — instead of "your output layer is red, fix that first".
# And an unfinished function is frequently memory-clean by accident (a stub that
# allocates nothing leaks nothing), so this layer teaches nothing either way
# until the fixture is green.
#
# Fails OPEN by design: no gate supplied, or a gate that cannot run, means the
# memory check still runs. A gate that wrongly suppressed this layer would turn
# a genuine leak green, which is far worse than duplicating a red.
#
# NO_SKIP=1 opens the gate, and still asks it: a report on a function whose
# output is still wrong can be about structures the test could not reach to
# free -- C 13 ex04's driver frees the tree it can find, and a tree the wrong
# shape used to read as the student's leak (finding 137) -- so when the gate
# is red, every failure below says so right under its headline
# (output_red_note): a run the gate left no time for, a runaway, a timeout, a
# crash, a memory finding, and a descriptor left open.
OUTPUT_RED=0
output_red_note() {
	[ "$OUTPUT_RED" -eq 1 ] || return 0
	echo "  NO_SKIP=1 opened this layer while this exercise's output layer is red"
	echo "  too, so this report may be about a result the test could not take apart"
	echo "  the way it expected. Read *_output first."
	echo ""
}

if [ -n "$GATE_DIFFER" ] && [ -n "$GATE_BIN" ] && [ -n "$GATE_EXPECTED" ] &&
	[ -x "$GATE_BIN" ] && [ -f "$GATE_EXPECTED" ]; then
	# The program's own argv is forwarded to the gate as well: this layer can be
	# emitted per argv case (defs.bzl's _emit_cases), and the fixture that case
	# is gated on is the one produced by the SAME arguments.
	# WHY THE STATUS IS CAPTURED RATHER THAN TESTED WITH `if !`.
	#
	# `if ! <gate>` treats EVERY non-zero the same, and the differ has two
	# meanings for non-zero: 1 is "the student's fixture is red", which is what
	# this gate is for, and 2 is "the differ could not run at all" -- a missing
	# tool, an unreadable expected file, a wiring mistake. Conflating them meant
	# a BROKEN gate silenced the layer it guards and printed a false sentence
	# while doing it.
	#
	# Demonstrated: a program whose fixture PASSES but which leaks 64 bytes was
	# reported as "SKIP -- this exercise's own output fixture is not passing
	# yet", exit 0, burying a real leak. At scale, the entire perf layer went
	# 77/77 green under a PATH shim missing `mv`, because diff_output.sh
	# requires it and exits 2.
	#
	# So: skip on 1, and on 2-or-more say so and RUN ANYWAY. A gate that cannot
	# answer must never be the reason a layer stayed quiet.
	rl_split_on
	# shellcheck disable=SC2086
	sh "$GATE_DIFFER" --bin "$GATE_BIN" --expected "$GATE_EXPECTED" \
			$GATE_PASS -- "$@" >/dev/null 2>&1
	_gate_rc=$?
	rl_split_off
	if [ "$_gate_rc" -ge 2 ]; then
		echo "valgrind_test: the output gate could not be evaluated (exit $_gate_rc),"
		echo "               so this layer is running anyway rather than going quiet."
	elif [ "$_gate_rc" -eq 1 ] && [ "${NO_SKIP:-0}" = "1" ]; then
		OUTPUT_RED=1
	elif [ "$_gate_rc" -eq 1 ]; then
		echo "valgrind_test: SKIP — this exercise's own output fixture is not"
		echo "               passing yet."
		echo ""
		echo "  A memory report on a function that still returns the wrong answer"
		echo "  describes allocations made by code you are about to rewrite. The"
		echo "  *_output layer is the one worth reading right now: a labelled"
		echo "  table, cases ordered from trivial to subtle, hints attached."
		echo "  Get it green and this layer starts checking something new."
		echo ""
		echo "  (NO_SKIP=1 runs a waiting layer anyway:"
		echo "   $(rl_noskip_cmd))"
		exit 0
	fi
fi

# A PROGRAM THAT DID NOT BUILD is a stand-in script that says why (see
# tools/standin.sh). Checked after the gate: a red gate has already skipped
# this layer, and past a green one -- or one NO_SKIP=1 forced open -- a
# stand-in is a failure, told in the compiler's words rather than as a
# report about a program that does not exist.
case "$0" in */*) _sl_dir=${0%/*} ;; *) _sl_dir=. ;; esac
for _sl in "$_sl_dir/standin.sh" \
	"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
	[ -f "$_sl" ] && break
done
[ -f "$_sl" ] || { echo "valgrind_test.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
standin_check valgrind_test "$BIN" fail "${LABEL:-the program}"

WORK=$(mktemp -d)
rl_traps 'rm -rf "$WORK"'

# The run the case describes: its argument file after the arguments after --
# (the gate above was handed the file itself), and its own folder when it has
# one (rl_rundir), which is then valgrind's working directory too.
if [ -n "$ARGV_FILE" ]; then
	_aw=$(rl_argv_words "$ARGV_FILE") || { echo "valgrind_test.sh: cannot read --argv-file '$ARGV_FILE'" >&2; exit 2; }
	eval "set -- \"\$@\" $_aw"
fi
RUN_BIN=$BIN
RUN_DIR=.
_ran_prog=$SHOW_RUN
_ran_in=${STDIN_FILE}
_ran_specs=""
if [ -n "$RUN_AS" ]; then
	RUN_DIR="$WORK/run"
	rl_rundir "$RUN_DIR" "$RUN_AS" "$BIN" "$CWD_FILES" || exit 2
	RUN_BIN="./$RUN_AS"
	_ran_prog=$RUN_BIN
	_ran_specs="$RUN_AS=${SHOW_RUN:-$BIN}$CWD_FILES"
	case "$STDIN_FILE" in "" | /*) ;; *) STDIN_FILE="$PWD/$STDIN_FILE" ;; esac
fi
[ -z "$SHOW_RUN" ] || rl_ran "$_ran_prog" "$_ran_in" "$_ran_specs" "$@"

# valgrind's report goes to its own --log-file rather than being merged into the
# child's stderr. Mixing them (the old '2> "$LOG"') meant the program's own
# diagnostics were classified as valgrind findings and vice versa, and it made
# the ERROR SUMMARY line impossible to trust.
VGLOG="$WORK/vg.log"
CHILDERR="$WORK/child.err"

# Stdin is pinned to /dev/null unless the caller names a file. Inheriting the
# test runner's stdin makes a program that reads it behave differently under
# Bazel, under `bazel run` and in a terminal — a memory layer must not be the
# place where that difference first shows up.
[ -n "$STDIN_FILE" ] || STDIN_FILE=/dev/null

# An inner timeout so an infinite loop is reported as one: --timeout, or what
# is left of the test's own limit if that is less -- the gate above may have
# used some of it, and VALGRIND_TIMEOUT's 60s is the whole of a small test's
# (rl_tmo).
# status_timeout -- the run ran out of its time: say so to --status-file, and
# whether that time was the test's (see --status-file above).
status_timeout() {
	[ -n "$STATUS_FILE" ] || return 0
	echo timeout > "$STATUS_FILE"
	[ "$RL_CLAMPED" != 1 ] || echo "clamped $RL_TMO" >> "$STATUS_FILE"
}
if ! rl_tmo "$TIMEOUT"; then
	status_timeout
	rl_overrun "$LABEL under valgrind"
	output_red_note
	exit 1
fi

# Output cap. This runs code nobody has verified, and both of the files it
# writes are unbounded: a loop that walks off the end of a block records a fresh
# invalid-access context per call site, and a program that prints its own
# diagnostics in a runaway loop fills CHILDERR at page-cache speed. Either can
# put hundreds of megabytes into the test tmpdir before Bazel's timeout notices.
# As in diff_output.sh and run_check.sh, `ulimit -f` bounds it at the source:
# the kernel kills the writer with SIGXFSZ (exit 153) the moment it goes past
# the budget, so nothing can fill the disk. It counts 512-byte blocks.
CAP="${VALGRIND_LOG_CAP:-8388608}"
BLOCKS=$(( CAP / 512 + 2 ))

# --error-exitcode=42 is the whole point of the run: it makes "valgrind found
# something" a value no child process would plausibly return by itself, so the
# verdict can be told apart from the program's own exit status further down.
# --show-leak-kinds/--errors-for-leak-kinds=all count still-reachable blocks as
# errors too, because "the process was about to exit anyway" is not the standard
# the malloc modules are graded against.
# --track-origins=yes costs roughly 2x runtime on programs this small and buys
# the one thing that makes an uninitialised-value report actionable: where the
# uninitialised bytes came from.
# THE LEAK HALF IS SEPARABLE, and one caller needs it separated.
#
# memcheck reports nine classes; only four of them are leaks. Invalid read,
# invalid write, invalid free and uninitialised value need no allocation at all
# -- which is why "this exercise may not allocate, so memcheck has nothing to
# say" is true of the leak half and false of the rest. c_mem_check's probes are
# throwaway mains that allocate an exactly-sized block and exit; asking them to
# free it would be asking the probe to prove something about itself.
#
# So --no-leak-check runs the same memcheck with leak reporting off and takes
# the leak patterns out of the classifier, leaving the classes that are about
# TOUCHING memory rather than accounting for it.
if [ "$NO_LEAK_CHECK" = 1 ]; then
	LEAK_FLAGS="--leak-check=no"
else
	LEAK_FLAGS="--leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all"
fi

# How the run ended is read from waitpid() through tools/exit_status (rl_run,
# rl_classify): valgrind ends the way its client did -- it returns the client's
# status, or kills itself with the signal that killed the client.
# shellcheck disable=SC2086 # LEAK_FLAGS is a list of flags, split on purpose.
(
	cd "$RUN_DIR" || exit 2
	ulimit -f "$BLOCKS" 2>/dev/null
	rl_run "$VALGRIND" \
		$LEAK_FLAGS \
		--track-origins=yes \
		--track-fds=yes \
		--error-exitcode=42 \
		--log-file="$VGLOG" \
		"$RUN_BIN" "$@" < "$STDIN_FILE" > /dev/null 2> "$CHILDERR"
)
RC=$?
rl_classify "$RC"

[ -f "$VGLOG" ] || : > "$VGLOG"

# The classes memcheck reports, in the words it reports them. The leak patterns
# are anchored on "in loss record" deliberately: the LEAK SUMMARY block printed
# at the end of EVERY report contains the words "definitely lost:" even when the
# count is zero, so matching the bare phrase would classify a pure invalid-read
# run as a leak.
ERR_RE='Invalid read of size|Invalid write of size|Invalid free\(\)|Mismatched free\(\)|uninitialised value|uninitialised byte'
LEAK_RE='are definitely lost in loss record|are indirectly lost in loss record|are possibly lost in loss record|are still reachable in loss record'
if [ "$NO_LEAK_CHECK" = 0 ]; then
	ERR_RE="$ERR_RE|$LEAK_RE"
fi

# The pass line has to claim only what was looked for. "no leak" over a run with
# --leak-check=no is the same false statement of record this repo keeps finding
# in its own comments, and it would be printed on every green. Nor does
# memcheck see every invalid access: it knows which bytes of the heap are a
# block and which memory is not mapped, but not where one array on the stack
# ends -- a write past a local array that stays inside the stack lands on
# memory that is addressable, and memcheck says nothing (C 01 ex07's probe
# passed a copy into a 16-int local array that overran it, the mutation run
# of 2026-10-03). So the claim names what it covers, and the OK line says
# what sees the rest: an ASan build. Not "the ASan layers": an exercise can
# have a memcheck target and no ASan one (seven did on 2026-10-03, C 00 ex00
# among them), and this runner is not told which (the wave 6 review).
if [ "$NO_LEAK_CHECK" = 1 ]; then
	CLEAN_CLAIM="no invalid access to the heap or to unmapped memory, no uninitialised value (leaks not checked)"
else
	CLEAN_CLAIM="no leak, no invalid access to the heap or to unmapped memory, no uninitialised value"
fi

log_has_errors() {
	grep -qE "$ERR_RE" "$VGLOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# FILE DESCRIPTORS LEFT OPEN, which is the same mistake as a leaked allocation
# in a different resource, and which nothing here used to look at.
#
# --track-fds=yes makes memcheck print exactly one line:
#
#     FILE DESCRIPTORS: 4 open (3 std) at exit.
#
# The "(N std)" are 0, 1 and 2, inherited rather than opened, so the finding is
# simply open > std. MEASURED: a program that opens a file and returns without
# closing it prints "4 open (3 std)"; the same program with close() prints
# "3 open (3 std)".
#
# IT DOES NOT AFFECT valgrind's EXIT CODE -- also measured: both runs above exit
# 0 with "ERROR SUMMARY: 0 errors". memcheck reports descriptors as information,
# not as an error, so --error-exitcode never fires on them. Reading the line is
# the only way to know.
#
# IT GATES. This shipped as a NOTE first, reasoning that no subject in this repo
# says a descriptor must be closed -- c-10 and bsq merely list close() among the
# functions they allow -- so failing on it would invent a requirement.
#
# The repo owner overruled that, and the ruling is worth recording because it
# settles a whole family of these: a layer exists for a reason, and INSIDE that
# layer the check should be strict even if greens turn red, provided the red is
# a real defect rather than a harness artifact. The subject not naming a rule is
# not the same as the subject licensing the opposite -- a descriptor left open
# is a defect in any C anyone will ever be paid to write, and the exercise that
# opens a file per argument meets the limit for real.
#
# MEASURED BEFORE FLIPPING: all 69 valgrind targets in the repo pass with this
# gating, so the change costs nothing today and only constrains what is written
# next. VALGRIND_FDS=lax turns it back into a note for anyone who needs it.
# COUNT WHAT THE PROGRAM OPENED, not what it INHERITED -- and the difference is
# the whole check. The summary line cannot be used on its own:
#
#     FILE DESCRIPTORS: 4 open (3 std) at exit.
#
# is what a program that opens NOTHING prints under this layer, because
# --log-file gives valgrind its own descriptor and the child inherits it.
# Measured: a program whose entire body is write(1, "x\n", 2) reports 4 open
# (3 std), and valgrind names the fourth as the log file, "<inherited from
# parent>". Counting open > std therefore fails every exercise in the repo,
# including the ones that never call open() -- 24 of 69 targets, all of them
# the harness measuring itself. That is the defect class this repo ranks worst:
# a driver bug charged to the student.
#
# So the stanzas are counted instead. valgrind prints one per descriptor:
#
#     Open file descriptor 3: /path/to/file
#        <inherited from parent>          <- ours, never the student's
#     Open file descriptor 4: /path/to/map
#        at 0x...: open (...)             <- opened by the program under test
#
# Only the second kind counts.
fds_left_open() {
	FD_LEAKED=$(awk '
		/Open file descriptor/ { pending = 1; next }
		pending && /<inherited from parent>/ { pending = 0; next }
		pending && /==/ { n++; pending = 0 }
		END { print n + 0 }
	' "$VGLOG" 2>/dev/null)
	[ -n "$FD_LEAKED" ] || return 1
	[ "$FD_LEAKED" -gt 0 ]
}

# own_log -- the report with every stanza for a descriptor the program
# INHERITED removed, and valgrind's "FILE DESCRIPTORS: N open (M std)" summary
# with them. Both describe the harness, not the student: the inherited stanza
# is valgrind's own log file, and the summary's N counts it. The display used
# to drop only the "<inherited from parent>" line, so the stanza's header --
# "Open file descriptor 3: .../vg.log" -- was printed under a verdict about
# the student's descriptors, naming a file they never opened (finding 171).
# The same stanza-aware reading as fds_left_open, so what is counted and what
# is shown cannot disagree.
own_log() {
	awk '
		/FILE DESCRIPTORS: [0-9]+ open/ { next }
		/Open file descriptor/ { held = $0; next }
		held != "" && /<inherited from parent>/ { held = ""; skip = 1; next }
		held != "" { print held; held = "" }
		skip && /^==[0-9]+== *$/ { skip = 0; next }
		{ skip = 0; print }
		END { if (held != "") print held }
	' "$VGLOG" 2>/dev/null
}

# FD_VERDICT: "fail" when the program left a descriptor open and the gate is
# on, "note" when it did and VALGRIND_FDS=lax, "" when it left none. Decided
# BEFORE the headline, because the headline is the line a reader (and a Bazel
# summary) keeps: it used to say "OK" and the failure came a screen later.
fd_verdict() {
	FD_VERDICT=""
	fds_left_open || return 0
	if [ "${VALGRIND_FDS:-}" = "lax" ]; then
		FD_VERDICT=note
	else
		FD_VERDICT=fail
	fi
}

# The descriptors themselves, once: the stanzas of the ones the program
# opened (never the inherited ones), and what it means (explained fds).
report_fds() {
	[ -n "$FD_VERDICT" ] || return 0
	echo ""
	echo "  DESCRIPTORS LEFT OPEN: $FD_LEAKED opened by this program and not closed."
	if [ "$FD_VERDICT" = fail ] && [ "$OUTPUT_RED" -eq 1 ]; then
		echo ""
		output_red_note
	fi
	own_log | sed 's/^==[0-9]*==[ ]\{0,1\}//' |
		awk '/^Open file descriptor/ { f = 1 } f && /^[[:space:]]*$/ { f = 0 } f' \
		> "$WORK/fds.txt"
	rl_excerpt "$WORK/fds.txt" 12 open-descriptors.txt
	[ "$BRIEF" = 1 ] || echo ""
	explained fds
}

# Lead with the NAME of the bug class, then explain what that class means and
# how to read the record — never what to change. The raw log on its own is the
# reason this layer had a reputation for being unreadable: a first-year reading
# "40 bytes in 1 blocks are indirectly lost in loss record 2 of 3" has no way to
# know that it is a symptom of loss record 3 and not a separate mistake.
# Under --brief the name alone, and the paragraphs once after the cases.
report_findings() {
	_first=$(grep -E "$ERR_RE" "$VGLOG" 2>/dev/null | head -1)
	# Run-time errors are printed as they happen and the leak records only at
	# exit, so the first match is genuinely the first thing that went wrong —
	# for everything except the leaks. Within the leak report valgrind orders
	# the records by block size, not by cause, so the first one is routinely an
	# "indirectly lost" child of a record further down: the three-line leak from
	# a two-level allocation leads with the inner block every time. Re-pick the
	# leak kind by root cause so the headline names the mistake, not its
	# consequence.
	case "$_first" in
	*"in loss record"*)
		for _k in 'are definitely lost in loss record' \
				'are possibly lost in loss record' \
				'are indirectly lost in loss record' \
				'are still reachable in loss record'; do
			if grep -qF "$_k" "$VGLOG" 2>/dev/null; then
				_first="$_k"
				break
			fi
		done
		;;
	esac
	case "$_first" in
	*"Invalid write of size"*) _class=class:invalid-write ;;
	*"Invalid read of size"*) _class=class:invalid-read ;;
	*"Invalid free()"*|*"Mismatched free()"*) _class=class:invalid-free ;;
	*"uninitialised value"*|*"uninitialised byte"*) _class=class:uninitialised ;;
	*"are definitely lost in loss record"*) _class=class:definitely-lost ;;
	*"are indirectly lost in loss record"*) _class=class:indirectly-lost ;;
	*"are possibly lost in loss record"*) _class=class:possibly-lost ;;
	*"are still reachable in loss record"*) _class=class:still-reachable ;;
	*) _class=class:other ;;
	esac
	# Under --brief, the class's name: its paragraph comes after the cases.
	[ "$BRIEF" = 0 ] || echo "  $(class_title "$_class")"
	explained "$_class"
	[ "$BRIEF" = 1 ] || echo ""
	explained trace
	[ "$BRIEF" = 1 ] || echo ""
	echo "  ---------------- valgrind report ----------------"
	# The ==pid== column on every line and the four-line version/copyright banner
	# are pure noise to a reader looking for the record, and they pushed the
	# actual content out of the first screenful.
	own_log | sed 's/^==[0-9]*==[ ]\{0,1\}//' \
		| grep -vE '^(Memcheck, a memory error detector|Copyright \(C\)|Using Valgrind|Using \(and\)|Command:|Parent PID:|For lists of|For counts of|For a detailed)' \
		| sed -e '/./,$!d' > "$WORK/report.txt"
	rl_excerpt "$WORK/report.txt" 60 valgrind-report.txt "  "
	if [ -s "$CHILDERR" ]; then
		echo "  ---------------- the program's own stderr ----------------"
		rl_excerpt "$CHILDERR" 10 program-stderr.txt "  "
	fi
	# Same clues.tsv the output layer uses, by the one rule (rl_clues), as
	# the layer "valgrind": the rows keyed to it -- memory hints, which the
	# output test never shows -- come first, under HINTS, and the rows keyed
	# to nothing (and, for a program case, --case, to the case) after them,
	# under a heading that says they were written for the output test. A
	# row keyed to another case of the output's speaks to that case's
	# output, and does not fire here. Every row fired here, as this layer's
	# own, and a leak was headed by three hints about the output (V55).
	if [ -n "$CASE_NAME" ]; then
		printf '%s\nvalgrind\n' "$CASE_NAME" > "$WORK/failed"
		rl_clues "$CLUES" "$WORK/failed" "" "$CASE_NAME" valgrind
	else
		printf 'valgrind\n' > "$WORK/failed"
		rl_clues "$CLUES" "$WORK/failed" "" "" valgrind
	fi
}

# --- exit status triage ----------------------------------------------------
# SIGXFSZ (runaway): the ulimit above stopped a report that would not stop
# growing. That is a finding in itself, not a harness problem.
if [ "$RL_CAUSE" = runaway ]; then
	echo "valgrind_test: FAIL — $LABEL was stopped after writing more than $CAP"
	echo "               bytes (memory report plus its own stderr)."
	output_red_note
	echo "  Output that size means something is repeating without end: either the"
	echo "  same invalid access recorded from call site after call site, or a loop"
	echo "  whose exit condition is never reached printing as it goes."
	echo "  Only the beginning survived the cut; nothing after it was read."
	report_findings
	exit 1
fi

if [ "$RL_CAUSE" = timeout ]; then
	status_timeout
	rl_overrun "$LABEL under valgrind"
	output_red_note
	echo "  valgrind runs the program on a synthetic CPU, so it is 20-50x slower"
	echo "  than a normal run — but every exercise wired to this layer finishes"
	echo "  in well under a second even so. Nothing about memory was checked."
	exit 1
fi

# 126/127 are the "cannot execute" statuses: valgrind never got as far as
# running the program (a half-installed valgrind whose own vgpreload objects are
# missing, a binary whose interpreter does not exist, a wrapper script with no
# exec bit). Memcheck prints an ERROR SUMMARY line on every run it completes,
# including a clean one, so its ABSENCE is what separates this from a child that
# genuinely chose to return 126 or 127 — and it also stops the layer reporting a
# green pass over a program that never ran. Infrastructure, so exit 2: a red
# MEMORY verdict for a broken image is the exact defect this triage exists to
# prevent.
if [ "$RL_CAUSE" = noexec ] || { { [ "$RC" -eq 127 ] || [ "$RC" -eq 126 ]; } &&
	! grep -q "ERROR SUMMARY" "$VGLOG" 2>/dev/null; }; then
	echo "valgrind_test.sh: valgrind could not run $BIN (exit $RC)" >&2
	rl_excerpt "$VGLOG" 10 valgrind-log.txt "  " >&2
	rl_excerpt "$CHILDERR" 10 program-stderr.txt "  " >&2
	echo "valgrind_test.sh: this is a harness/toolchain failure, not a student" >&2
	echo "                  finding — reporting it as one would be a lie." >&2
	exit 2
fi

# KILLED, not returned (waitpid() says which, not the number): under valgrind
# this is usually the crash that the records below already explain, so name
# the signal first and then show the findings.
if [ "$RL_CAUSE" = signal ] || [ "$RL_CAUSE" = stopped ]; then
	echo " --------------------------------------------------"
	echo " CRASH: $LABEL $RL_WHY."
	echo "        It was killed rather than returning, so this is a failure"
	echo "        regardless of what it managed to print first."
	output_red_note
	if log_has_errors; then
		echo "        valgrind recorded what led to it:"
		echo ""
		report_findings
	elif [ -s "$CHILDERR" ]; then
		echo " ----- the program's stderr said -----"
		rl_excerpt "$CHILDERR" 20 program-stderr.txt "   "
	fi
	exit 1
fi

# The verdict proper. Trust --error-exitcode first, but also believe the report:
# an older valgrind, or errors recorded in a forked child, can leave a non-zero
# ERROR SUMMARY behind while the exit status stays 0, and a memory layer that
# prints OK over a report full of loss records would be worse than no layer.
#
# 42 is valgrind's marker only when valgrind is the one who chose it. A child's
# own status is passed through untouched, so a program whose main returns 42
# arrives here as 42 over a completely clean report: measured, a two-line
# program that just returns 42 was told "is not memory-clean" above a log
# reading "All heap blocks were freed -- no leaks are possible / ERROR SUMMARY:
# 0 errors", and the classifier fell through to "an error it does not classify"
# because there was no error to classify. A student verdict handed to a
# memory-clean program is the same confusion between valgrind's answer and the
# child's that the rest of this triage exists to end, just in the last place it
# could still hide. Memcheck prints an ERROR SUMMARY on every run it completes
# and never says "0 errors" about a run it flagged, so that line settles it —
# and only an explicit zero does: a missing or truncated summary is not
# evidence of innocence, so anything else keeps the exit status' verdict.
VG_VERDICT=0
if [ "$RC" -eq 42 ]; then
	VG_VERDICT=1
	grep -q 'ERROR SUMMARY: 0 errors' "$VGLOG" 2>/dev/null && VG_VERDICT=0
fi

if [ "$VG_VERDICT" -eq 1 ] || log_has_errors; then
	echo "valgrind_test: FAIL — $LABEL is not memory-clean."
	output_red_note
	report_findings
	# The rule it breaks (explain rule): here, or for one case of a corpus
	# once, under the runner's verdict, which says what is judged
	# (tools/runner_lib.sh, rl_mem_tally).
	[ "$BRIEF" = 1 ] || echo ""
	explained rule
	exit 1
fi

HEAP=$(grep 'total heap usage' "$VGLOG" 2>/dev/null | sed 's/^==[0-9]*== *//' | head -1)

# The descriptor verdict rides on the SUCCESS paths: leaving a file open is
# orthogonal to every memory finding, so a run that is clean on memory is
# exactly where it would otherwise never be mentioned. It is decided before
# the headline, and a failing one IS the headline.
fd_verdict
headline() {
	if [ "$FD_VERDICT" = fail ]; then
		echo "valgrind_test: FAIL — $FD_LEAKED descriptor(s) opened by $LABEL were left open"
		echo "               (memory: $CLEAN_CLAIM)"
	elif [ -n "$FD_VERDICT" ]; then
		echo "valgrind_test: OK — $CLEAN_CLAIM ($LABEL)"
		echo "               $FD_LEAKED descriptor(s) left open, reported as a note (VALGRIND_FDS=lax)"
	else
		echo "valgrind_test: OK — $CLEAN_CLAIM, every descriptor it opened closed ($LABEL)"
	fi
	# One case of a corpus: the runner's verdict line says it, once.
	if [ "$BRIEF" = 0 ]; then
		echo "               (memcheck does not see a write past an array on the stack"
		echo "               while it stays inside the stack: an ASan build does)"
	fi
	[ -z "$HEAP" ] || echo "               ${HEAP}"
}
if [ "$RC" -eq 0 ]; then
	headline
	report_fds
	[ "$FD_VERDICT" != fail ] || exit 1
	exit 0
fi

# A non-zero status it RETURNED is the program's own choice of exit code, and
# valgrind found nothing. That is not this layer's business: run_check.sh and the
# *_output layer are the ones that assert exit status. Saying so out loud keeps
# the pass honest rather than silent — the old script failed the student here.
headline
echo "               (the program chose to exit $RC; this layer checks memory,"
echo "                not exit status — that is the *_output layer's job.)"
report_fds
# The SAME verdict as the clean-exit path above, and it has to be. This path's
# gate once tested VALGRIND_FDS = "strict", a value nothing in this tree ever
# sets, so the report said FAILURE and the layer exited 0 -- reproduced with
# two programs differing only in main's return value. A descriptor left open is
# not less of a defect because the program also chose a non-zero exit status.
[ "$FD_VERDICT" != fail ] || exit 1
exit 0
