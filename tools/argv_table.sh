#!/bin/sh
# argv_table.sh — run a program once per scenario and present a labeled
# "invocation -> output" PASS/FAIL table (one row per invocation). Designed for
# the small argv programs (c-06: print/rev/sort params) where each run's output
# is short: the run's stdout lines are joined with SEP into a single value, so a
# whole batch of invocations reads as one legible table. A run whose output does
# not end in a newline gets " [no final newline]" after its value, since the
# join would otherwise hide it.
#
# Each scenario line in SCENARIOS is tab-separated: <label>[<TAB><arg>...]. A line
# with no tab has zero args; an empty field is a real empty-string argument.
# Rendering, the PASS/FAIL verdict and clues are delegated to tools/diff_output.sh
# (--labeled), so the table/hint format is identical to every other test. What is
# NOT delegated is whether each run survived. The reporter is handed the already
# collected table with --bin /bin/cat, so ITS crash/timeout/runaway guards watch
# `cat` — which never crashes, never hangs and never floods — and not the
# student's program. Everything about the runs themselves (exit status, signals,
# hangs, runaway output, stderr) therefore has to be judged here, and for c-06
# ex01-ex03 this is the ONLY layer that ever executes the program: a crash this
# script does not notice is a crash nobody notices.
#
# Usage:
#   argv_table.sh --bin PATH --scenarios PATH --expected PATH \
#       [--clues PATH] [--reporter PATH] [--sep STR] [--memory-only] [--exit-only]
#       [--guarded-argv] [--symbolizer PATH --symbolizer-lib PATH]
#
#   --memory-only  run every scenario and apply the survival guards, but do NOT
#                  compare the table. For the sanitizer replay of these same
#                  scenarios, where a byte mismatch is the plain output test's
#                  finding and a sanitizer abort is this one's. Its OK line
#                  claims only what the sanitizer could see: argv and its
#                  strings sit where the kernel put them, on the initial
#                  stack, which ASan does not watch (finding 071).
#   --guarded-argv with --memory-only: the program is the guarded build
#                  (tools/argv_guard_main.c), whose argv and arguments are
#                  heap blocks of exactly their size, so the OK line may claim
#                  reads past them too.
#   --symbolizer   the pinned llvm-symbolizer, and --symbolizer-lib a library
#                  file beside the libLLVM it loads: a sanitizer report's
#                  frames then name a function, a file and a line
#                  (tools/runner_lib.sh, rl_sanitizers).
#   --exit-only    run every scenario and judge only how each run ended: a plain
#                  non-zero return fails as well as a crash, and the table is
#                  not compared. For the robust exit-status target, exNN_exit.
#
# THE EXIT STATUS, by the rule in docs/reference.md ("Run contract"). A run
# killed by a signal fails in every mode: a crash is never a pass. A plain
# non-zero RETURN fails only under --exit-only. The subjects these programs
# come from name no exit status, so the table -- level basic -- does not fail a
# student on one; it prints a note, and the robust target is where it fails.
#
# Env: ARGV_TIMEOUT  seconds allowed per scenario run (default 5), capped by
#                    what is left of the test's own limit
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "argv_table.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat dirname grep mktemp rm sed tail tr wc

# The shared runner helpers -- time budget, exiting signal traps, how a run
# ended, excerpts, hints -- written once in tools/runner_lib.sh.
RL_NAME=argv_table
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "argv_table.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool REPORTER -- tools/diff_output.sh (or --reporter's), which renders the table and runs nothing

BIN=""; SCN=""; EXP=""; CLUES=""; REPORTER=""; SEP=" | "; EMIT=0; MEMONLY=0
EXITONLY=0; SYMBOLIZER=""; SYMBOLIZER_LIB=""; GUARDED=0
TAB=$(printf '\t')

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "argv_table.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--scenarios) need "$1" "$#"; SCN="$2"; shift 2 ;;
		--expected) need "$1" "$#"; EXP="$2"; shift 2 ;;
		--clues) need "$1" "$#"; CLUES="$2"; shift 2 ;;
		--reporter) need "$1" "$#"; REPORTER="$2"; shift 2 ;;
		--sep) need "$1" "$#"; SEP="$2"; shift 2 ;;
		--emit) EMIT=1; shift ;;
		--memory-only) MEMONLY=1; shift ;;
		--exit-only) EXITONLY=1; shift ;;
		--guarded-argv) GUARDED=1; shift ;;
		--symbolizer) need "$1" "$#"; SYMBOLIZER="$2"; shift 2 ;;
		--symbolizer-lib) need "$1" "$#"; SYMBOLIZER_LIB="$2"; shift 2 ;;
		*) echo "argv_table.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
# --emit: print the "label<TAB>joined-output" stream (used to GENERATE the expected
# table from a trusted reference program). Otherwise --expected is required.
if [ -z "$BIN" ] || [ -z "$SCN" ] || { [ "$EMIT" -eq 0 ] && [ "$MEMONLY" -eq 0 ] && [ "$EXITONLY" -eq 0 ] && [ -z "$EXP" ]; }; then
	echo "argv_table.sh: --bin, --scenarios and --expected (unless --emit) are required" >&2
	exit 2
fi
if [ "$GUARDED" -eq 1 ] && [ "$MEMONLY" -eq 0 ]; then
	echo "argv_table.sh: --guarded-argv describes a sanitizer replay; it needs --memory-only" >&2
	exit 2
fi
[ -n "$REPORTER" ] || REPORTER="$(dirname "$0")/diff_output.sh"

# A PROGRAM THAT DID NOT BUILD is a stand-in script that says why (see
# tools/standin.sh). Graded as a program, every scenario would come back empty
# under this exercise's hints, none of which is about a build: say what the
# build said instead, and fail. The memory-only arm steps aside the way
# asan_run.sh does -- the output table beside it tells the story -- unless
# NO_SKIP=1.
case "$0" in */*) _sl_dir=${0%/*} ;; *) _sl_dir=. ;; esac
for _sl in "$_sl_dir/standin.sh" \
	"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/standin.sh"; do
	[ -f "$_sl" ] && break
done
[ -f "$_sl" ] || { echo "argv_table.sh: cannot find tools/standin.sh beside it or in the runfiles" >&2; exit 2; }
# shellcheck source=tools/standin.sh
. "$_sl"
if [ "$MEMONLY" -eq 1 ]; then
	standin_check argv_table "$BIN" skip "the program"
else
	standin_check argv_table "$BIN" fail "the program"
fi

# Runaway guard, same reasoning and same mechanism as tools/diff_output.sh:87-98.
# This runs code nobody has verified, so a loop whose exit condition is never
# reached writes at page-cache speed into the test tmpdir for the whole Bazel
# timeout. `ulimit -f` bounds it at the source — the kernel kills the writer with
# SIGXFSZ (exit 153) the moment it goes past the budget — and it counts 512-byte
# blocks, hence the rounding. The budget is derived from the expected table (32x
# it, floor 4 MiB), which is generous here because the table holds EVERY
# scenario's output while the cap applies to ONE run.
EXP_BYTES=0
[ -n "$EXP" ] && EXP_BYTES=$(wc -c < "$EXP" | tr -d ' ')
CAP=$(( EXP_BYTES * 32 ))
[ "$CAP" -lt 4194304 ] && CAP=4194304
BLOCKS=$(( CAP / 512 + 2 ))

# A second, much tighter cap on what may enter the TABLE. The reporter's awk pads
# every cell out to the widest one a character at a time, so a single multi-
# megabyte cell (still under the ulimit above) turns rendering into a quadratic
# crawl and then prints one unreadable megabyte-wide line. Past this cap the
# value is replaced by its size; the row cannot match the expected table anyway.
CELL_MAX=$(( EXP_BYTES + 4096 ))

# An inner timeout, well under Bazel's 60s for a "small" test, so a loop that
# prints nothing is reported as a hang instead of surfacing as an opaque Bazel
# timeout with nothing the student can act on. It is per SCENARIO, not per test —
# a whole file of hanging scenarios must still fit inside Bazel's budget — which
# is why it is 5s and not diff_output.sh's 30s. Every legitimate run of these
# programs finishes in milliseconds. What is left of the test's own limit caps it
# too, and the sweep stops once RL_MAX_HANGS (3) scenarios have hung
# (rl_sweep_next, rl_sweep_ran).
#
# How each run ended comes from tools/exit_status (waitpid), never from $?,
# which reads `return (-1);` (255) as a death by signal 127: rl_run and
# rl_classify (tools/runner_lib.sh) say so once for every runner.
TMO="${ARGV_TIMEOUT:-5}"
# How many scenarios there are, for a sweep that stops early to say so.
SCN_TOTAL=$(grep -cvE '^(#|$)' "$SCN" 2> /dev/null)

ACTUAL=$(mktemp)
RAW=$(mktemp)
# ERR holds ONE run's stderr (truncated by each run); ERRLOG accumulates the
# interesting ones across scenarios; DIED accumulates one line per run that did
# not finish cleanly. Cleaned by a trap because the script now has several exit
# paths (the --emit refusal, the reporter's verdict, an interrupted Bazel run)
# and the old "rm before each exit" left files behind on every path that was
# added after it.
ERR=$(mktemp)
ERRLOG=$(mktemp)
DIED=$(mktemp)
# One line per run that RETURNED a non-zero status (not a signal): a note in
# the table's modes, the verdict under --exit-only.
NONZERO=$(mktemp)
# Where rl_sanitizers writes the symbolizer's wrapper.
SYMDIR=$(mktemp -d)
rl_traps 'rm -f "$ACTUAL" "$RAW" "$ERR" "$ERRLOG" "$DIED" "$NONZERO"; rm -rf "$SYMDIR"'
# The sanitizers' options and the pinned symbolizer, set once for every
# sanitizer runner (tools/runner_lib.sh). Harmless for the plain program, whose
# runs no sanitizer watches.
rl_sanitizers "$SYMDIR" "$SYMBOLIZER" "$SYMBOLIZER_LIB"

NRUN=0
# SIGNALED distinguishes "the program died on its own" from "the harness had to
# stop it": the pedagogic paragraph about argv bounds belongs to the first case
# only, and telling a student with an infinite loop to go look at their indices
# would send them at the wrong bug.
SIGNALED=0
# Set when any run produced a sanitizer report (see the check inside the loop).
SANITIZED=0
# Set when a run's output was too big to put in the table and was replaced by
# its size. Harmless for a student — the placeholder row cannot match, so the
# comparison already reds it — but --emit has to know, see the refusal below.
TRUNCATED=0
while IFS= read -r line || [ -n "$line" ]; do
	case "$line" in '' | '#'*) continue ;; esac
	case "$line" in
		*"$TAB"*) label="${line%%"$TAB"*}"; argstr="${line#*"$TAB"}"; hasargs=1 ;;
		*) label="$line"; argstr=""; hasargs=0 ;;
	esac
	set --
	if [ "$hasargs" = 1 ]; then
		a="$argstr"
		while : ; do
			case "$a" in
				*"$TAB"*) f="${a%%"$TAB"*}"; a="${a#*"$TAB"}" ;;
				*) set -- "$@" "$a"; break ;;
			esac
			set -- "$@" "$f"
		done
	fi
	# Capture RAW bytes to a file, NOT via out=$(...) — command substitution
	# strips ALL trailing newlines, so a trailing empty-string argument (printed
	# as a blank line) would vanish and the empty-arg scenario be silently
	# ineffective. awk reading the file counts the trailing empty record, so the
	# join preserves trailing blank lines/fields.
	#
	# stderr goes to a file instead of /dev/null: when a run misbehaves it is
	# stderr that says why (a sanitizer report, glibc's "free(): invalid next
	# size", "*** stack smashing detected ***", the program's own message), and
	# throwing it away made every failure here harder to read than it needed to
	# be. stdin is /dev/null because the loop reads the scenarios file on ITS
	# stdin: a program that reads stdin would otherwise swallow the remaining
	# scenario lines and silently shrink the test.
	rl_sweep_next "$TMO" || break
	NRUN=$((NRUN + 1))
	(
		ulimit -f "$BLOCKS" 2>/dev/null
		rl_run "$BIN" "$@"
	) > "$RAW" 2> "$ERR" < /dev/null
	RC=$?
	# How it ended, from waitpid() (rl_classify, through rl_sweep_ran): a
	# return, a signal, the time limit or the output budget.
	rl_sweep_ran "$RC"
	case "$RL_CAUSE" in
		ok | "exit" | "timeout" | runaway | signal) ;;
		*)
			echo "argv_table.sh: '$BIN' $RL_WHY" >&2
			exit 2 ;;
	esac
	RAW_BYTES=$(wc -c < "$RAW" | tr -d ' ')
	if [ "$RAW_BYTES" -gt "$CELL_MAX" ]; then
		joined="(output too large: $RAW_BYTES bytes, not shown)"
		TRUNCATED=1
	else
		joined=$(awk -v s="$SEP" 'NR>1{printf "%s", s} {printf "%s", $0}' "$RAW")
		# A MISSING FINAL NEWLINE, made visible. Joining lines drops their
		# terminators, so "a\nb" and "a\nb\n" used to join to the same cell and
		# only a row whose last printed line was empty could tell them apart
		# (the c-06 BUILD comment kept such rows for that reason alone). A
		# correct run always ends in one, so the marker never reaches a
		# table.txt, and the row it lands on fails as it should. Probed through
		# `tail -c 1 | tr -d | wc -c` rather than $(...), which strips newlines.
		if [ "$RAW_BYTES" -gt 0 ] &&
			[ "$(tail -c 1 "$RAW" | tr -d '\n' | wc -c)" -ne 0 ]; then
			joined="$joined [no final newline]"
		fi
	fi
	printf '%s\t%s\n' "$label" "$joined" >> "$ACTUAL"

	# The exit status used to be dropped on the floor — the run was
	# `"$BIN" "$@" > "$RAW" 2>/dev/null` and nothing ever read $? — and because
	# the verdict is delegated with --bin /bin/cat, no other layer looked at it
	# either. A program that printed the correct table and then segfaulted,
	# aborted on a stack smash or was killed reported PASS. ex01-ex03 index and
	# swap argv pointers, which is precisely the shape of bug that emits the
	# right bytes and dies on the way out, so this is the one thing this layer
	# must not miss. Record what happened per scenario; the verdict is forced
	# after the table so the student still gets to see which rows matched.
	# A plain non-zero return is recorded apart, below: fatal only under
	# --exit-only (see the header), because the subject says nothing about
	# main's return value.
	# A SANITIZER FINDING is read from the report itself, the same way
	# tools/asan_run.sh does, and before the signal: rl_sanitizers sets
	# abort_on_error=1, so the finding ends the run with SIGABRT, and that
	# abort IS the report -- one line for it, not a second "killed by SIGABRT"
	# beside it. (Without abort_on_error the sanitizer exits 1, a plain non-zero
	# return; recognising the report is what kept a real heap-buffer-overflow
	# from reading as "no crash" -- verified against a deliberate off-by-one
	# before this check existed.)
	_sanitized=0
	if rl_sanitized "$ERR"; then
		printf '   %s: the sanitizer reported an invalid access\n' "$label" >> "$DIED"
		SANITIZED=1
		_sanitized=1
	fi
	case "$RL_CAUSE" in
		"runaway")
			printf '   %s: kept printing past its %s-byte budget and was stopped (runaway loop?)\n' \
				"$label" "$CAP" >> "$DIED" ;;
		"timeout")
			printf '   %s: did not finish within %ss (infinite loop?)\n' \
				"$label" "$RL_TMO" >> "$DIED" ;;
		"signal")
			if [ "$_sanitized" -eq 0 ]; then
				printf '   %s: %s\n' "$label" "$RL_WHY" >> "$DIED"
				SIGNALED=1
			fi ;;
	esac
	if [ "$_sanitized" -eq 0 ] && [ "$RL_CAUSE" = "exit" ]; then
		# A plain return, and not the sanitizer's own exit(1): that one is
		# already reported above as what it is.
		printf '   %s: returned exit status %s\n' "$label" "$RC" >> "$NONZERO"
	fi

	# Keep the run's own diagnostics, labeled with the scenario they came from,
	# but only show them further down if the layer actually fails: a passing run
	# that writes to stderr is not this layer's business. Only a run that WROTE
	# something: its label line heads what it wrote. A silent non-zero return
	# used to land here too, and the block headed "what the runs wrote to
	# stderr" listed "exit status 1" five times over and nothing any run wrote
	# -- the EXIT STATUS block again, under a heading that said otherwise.
	if [ -s "$ERR" ]; then
		case "$RL_CAUSE" in
			ok | "exit") _e="exit status $RC" ;;
			*) _e=$RL_WHY ;;
		esac
		printf '   %s: %s\n' "$label" "$_e" >> "$ERRLOG"
		if [ "$_sanitized" -eq 1 ]; then
			rl_sanitizer_report "$ERR" 30 "run-$NRUN-sanitizer-report.txt" "     " >> "$ERRLOG"
		else
			rl_excerpt "$ERR" 10 "run-$NRUN-stderr.txt" "     " >> "$ERRLOG"
		fi
	fi
	[ -z "$RL_STOP" ] || break
done < "$SCN"

# A sweep that stopped early has not run every scenario: it cannot pass, and
# says why among the runs that did not end cleanly.
[ -z "$RL_STOP" ] || rl_sweep_stopped "$NRUN" "$SCN_TOTAL" | sed 's/^/   /' >> "$DIED"

# Zero runs is never a fact about the program. It happens when the scenarios
# file is absent from the test's `data`, is empty, or holds nothing but
# comments: `done < "$SCN"` then simply never executes the body, and every
# variable below keeps the value it was initialised with. In --memory-only mode
# that produced the worst outcome this file is capable of — exit 0 and
# "OK — 0 invocation(s) ran under the sanitizer; no out-of-bounds access, no
# crash, no hang", a layer certifying memory safety it never once looked for.
# In table mode it was only marginally better: the empty table lost the
# comparison and the STUDENT was handed the hints for a file the harness never
# delivered. Neither is a student verdict, so both take the exit-2 path.
if [ "$NRUN" -eq 0 ] && [ -z "$RL_STOP" ]; then
	echo "argv_table.sh: $SCN produced no invocations (missing, empty, or only" >&2
	echo "               comments), so the program was never run and this layer" >&2
	echo "               has nothing it can honestly report about it." >&2
	exit 2
fi

if [ "$EMIT" -eq 1 ]; then
	# --emit builds the expected table from a trusted reference program. If that
	# program crashed, hung or flooded, what it printed is not a fact about the
	# exercise, and writing it to table.txt would freeze the damage into every
	# future run of this test — including making a crash look like the expected
	# behaviour. That is a broken harness, not a failing student, hence exit 2.
	#
	# TRUNCATED is checked alongside DIED because a cell past CELL_MAX never
	# reaches DIED: the run exited 0, it was only too big to print. Emitting it
	# writes the literal string "(output too large: N bytes, not shown)" into
	# table.txt as the expected output, and from then on the test passes only for
	# a program that reproduces the truncation notice — verified by emitting from
	# a reference that prints 9900 bytes for one scenario, which exited 0 and put
	# the placeholder on stdout. Note CELL_MAX is only 4096 here, since --emit
	# runs without --expected to size it from.
	if [ -s "$DIED" ] || [ "$TRUNCATED" -eq 1 ]; then
		echo "argv_table.sh: the reference program did not run cleanly; refusing to" >&2
		echo "               generate an expected table from it:" >&2
		[ "$TRUNCATED" -eq 1 ] && \
			echo "   at least one run printed more than $CELL_MAX bytes, too much to hold in a table cell" >&2
		cat "$DIED" >&2
		[ -s "$ERRLOG" ] && cat "$ERRLOG" >&2
		exit 2
	fi
	cat "$ACTUAL"
	exit 0
fi

# --memory-only skips the table comparison entirely and judges the runs on
# whether they SURVIVED. It exists for the sanitizer arm, which replays these
# same scenarios against the instrumented binary: there, a wrong table is not
# this layer's news — the plain output test already reports it, and a student
# staring at two reds for one unwritten function learns nothing from the second.
# What the instrumented run alone can say is that an access went out of bounds,
# and ASan reports that by aborting, which the crash check below already sees.
# So: same runs, same guards, no byte comparison.
if [ "$MEMONLY" -eq 1 ] || [ "$EXITONLY" -eq 1 ]; then
	rc=0
else
	set -- --bin /bin/cat --expected "$EXP" --labeled
	[ -n "$CLUES" ] && set -- "$@" --clues "$CLUES"
	sh "$REPORTER" "$@" -- "$ACTUAL"
	rc=$?
fi

# A run killed by a signal is never correct, however good the table looks. This
# is checked AFTER the comparison so the rows above still document what each
# invocation was supposed to print, but it OVERRIDES the verdict: a crash
# outranks a byte comparison, exactly as diff_output.sh's own crash verdict has
# it for the runs it owns (search there for "CRASH: the program died on"). It has
# to live here because the process that script watched was /bin/cat, not the
# program under test.
if [ -s "$DIED" ]; then
	echo " --------------------------------------------------"
	if [ "$SANITIZED" -eq 1 ]; then
		echo " INVALID MEMORY ACCESS: the sanitizer stopped an invocation."
	elif [ "$SIGNALED" -eq 1 ]; then
		echo " CRASH: an invocation was killed by a signal:"
	else
		echo " RUN STOPPED: an invocation had to be stopped before it finished:"
	fi
	cat "$DIED"
	echo "        The table above can be all PASS and this still be a failure: the"
	echo "        bytes were already written when the process died, and a run that"
	echo "        had to be stopped printed only as far as it got. The same"
	echo "        program ends the same way $(rl_at)."
	if [ "$SIGNALED" -eq 1 ]; then
		echo "        These programs walk argv, so what argc counts — and therefore"
		echo "        which indices of argv exist at all — is what to re-read in the"
		echo "        subject before anything else."
	fi
	rc=1
fi

# A plain non-zero return: the verdict under --exit-only, a note otherwise.
if [ -s "$NONZERO" ]; then
	echo " --------------------------------------------------"
	if [ "$EXITONLY" -eq 1 ]; then
		echo " EXIT STATUS: an invocation returned a non-zero status:"
		cat "$NONZERO"
		echo "        The subject names no exit status. This is the robust check,"
		echo "        which applies the C convention: a program that did its job"
		echo "        returns 0 from main."
		rc=1
	else
		echo " note: an invocation returned a non-zero status:"
		rl_excerpt "$NONZERO" 5 nonzero-returns.txt ""
		echo "        The subject names no exit status, so this layer does not fail"
		echo "        on it; the robust exit-status check does, because a program"
		echo "        that did its job conventionally returns 0 from main."
	fi
fi

# Show the runs' stderr only now that something has failed: it is usually the
# explanation (sanitizer report, libc diagnostic, the program's own message).
if [ "$rc" -ne 0 ] && [ -s "$ERRLOG" ]; then
	echo " ----- what the runs wrote to stderr -----"
	rl_excerpt "$ERRLOG" 30 runs-stderr.txt ""
fi

# Say something on success too. A layer that prints nothing when it passes is
# indistinguishable from a layer that silently did not run, and this one now
# makes a claim the table cannot make on its own.
if [ "$rc" -eq 0 ]; then
	if [ "$MEMONLY" -eq 1 ] && [ "$GUARDED" -eq 1 ]; then
		echo "argv_table: OK — $NRUN invocation(s) ran under the sanitizer, argv and"
		echo "            each argument in a heap block of exactly its size: no"
		echo "            sanitizer finding, no crash, no hang. A read past an"
		echo "            argument's end or past argv[argc] would have been one."
	elif [ "$MEMONLY" -eq 1 ]; then
		# What it saw, and no more (finding 071): the sanitizer watches the
		# heap and the program's own buffers, not argv's strings, which the
		# kernel laid out back to back where nothing is poisoned.
		echo "argv_table: OK — $NRUN invocation(s) ran under the sanitizer: no"
		echo "            sanitizer finding, no crash, no hang."
		echo "            Reads inside the argument strings, or past argv's end, are"
		echo "            invisible here: the kernel lays them out where the"
		echo "            sanitizer does not watch. The guarded replay beside this"
		echo "            target (exNN_argv_asan) puts each one in a heap block, where"
		echo "            it does."
	elif [ "$EXITONLY" -eq 1 ]; then
		echo "argv_table: OK — $NRUN invocation(s) ran; every one returned 0."
	else
		echo "argv_table: OK — $NRUN invocation(s) ran; none crashed, hung or flooded."
	fi
fi
exit "$rc"
