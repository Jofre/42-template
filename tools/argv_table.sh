#!/bin/sh
# argv_table.sh — run a program once per scenario and present a labeled
# "invocation -> output" PASS/FAIL table (one row per invocation). Designed for
# the small argv programs (c-06: print/rev/sort params) where each run's output
# is short: the run's stdout lines are joined with SEP into a single value, so a
# whole batch of invocations reads as one legible table.
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
#       [--clues PATH] [--reporter PATH] [--sep STR] [--memory-only]
#
#   --memory-only  run every scenario and apply the survival guards, but do NOT
#                  compare the table. For the sanitizer replay of these same
#                  scenarios, where a byte mismatch is the plain output test's
#                  finding and a sanitizer abort is this one's.
#
# Env: ARGV_TIMEOUT  seconds allowed per scenario run (default 5)
#      NO_SKIP=1     refuse to run unguarded when `timeout` is unavailable
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
require awk cat dirname grep head mktemp rm sed tr wc
BIN=""; SCN=""; EXP=""; CLUES=""; REPORTER=""; SEP=" | "; EMIT=0; MEMONLY=0
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
		*) echo "argv_table.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
# --emit: print the "label<TAB>joined-output" stream (used to GENERATE the expected
# table from a trusted reference program). Otherwise --expected is required.
if [ -z "$BIN" ] || [ -z "$SCN" ] || { [ "$EMIT" -eq 0 ] && [ "$MEMONLY" -eq 0 ] && [ -z "$EXP" ]; }; then
	echo "argv_table.sh: --bin, --scenarios and --expected (unless --emit) are required" >&2
	exit 2
fi
[ -n "$REPORTER" ] || REPORTER="$(dirname "$0")/diff_output.sh"

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
# programs finishes in milliseconds.
TMO="${ARGV_TIMEOUT:-5}"
if command -v timeout >/dev/null 2>&1; then
	RUNNER="timeout -s KILL $TMO"
else
	# NO_SKIP=1: running bare silently removes the hang guard, and a layer must
	# not weaken itself into a green without saying so.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no 'timeout' command available, so a scenario that never"
		echo "             returns could not be detected, and this layer must not"
		echo "             report a pass it cannot stand behind."
		exit 1
	}
	RUNNER=""
fi

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
trap 'rm -f "$ACTUAL" "$RAW" "$ERR" "$ERRLOG" "$DIED"' EXIT INT TERM

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
	NRUN=$((NRUN + 1))
	(
		ulimit -f "$BLOCKS" 2>/dev/null
		$RUNNER "$BIN" "$@"
	) > "$RAW" 2> "$ERR" < /dev/null
	RC=$?
	RAW_BYTES=$(wc -c < "$RAW" | tr -d ' ')
	if [ "$RAW_BYTES" -gt "$CELL_MAX" ]; then
		joined="(output too large: $RAW_BYTES bytes, not shown)"
		TRUNCATED=1
	else
		joined=$(awk -v s="$SEP" 'NR>1{printf "%s", s} {printf "%s", $0}' "$RAW")
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
	case "$RC" in
		0) ;;
		153)
			printf '   %s: kept printing past its %s-byte budget and was stopped (runaway loop?)\n' \
				"$label" "$CAP" >> "$DIED" ;;
		124 | 137)
			printf '   %s: did not finish within %ss (infinite loop?)\n' \
				"$label" "$TMO" >> "$DIED" ;;
		*)
			# The shell reports 128+signal, so anything above 128 died rather
			# than returned. A plain non-zero return is deliberately NOT fatal:
			# the subject says nothing about main's return value, and failing on
			# it would red a student whose output is exactly right.
			if [ "$RC" -gt 128 ]; then
				SIG=$((RC - 128))
				case "$SIG" in
					4)  NAME="SIGILL (illegal instruction)" ;;
					6)  NAME="SIGABRT (abort: assertion, stack smashing, or a glibc heap error)" ;;
					8)  NAME="SIGFPE (arithmetic error, e.g. division or modulo by zero)" ;;
					11) NAME="SIGSEGV (invalid memory access)" ;;
					13) NAME="SIGPIPE (wrote to a closed pipe)" ;;
					*)  NAME="signal $SIG" ;;
				esac
				printf '   %s: died on %s\n' "$label" "$NAME" >> "$DIED"
				SIGNALED=1
			fi ;;
	esac

	# A sanitizer finding is NOT a signal by default: AddressSanitizer runs with
	# abort_on_error=0, so it prints its report and calls exit(1). RC is then 1,
	# which the triage above deliberately treats as harmless — the subject says
	# nothing about main's return value. So the instrumented replay has to
	# recognise the report itself, the same way tools/asan_run.sh does, or a real
	# heap-buffer-overflow reads as "no out-of-bounds access, no crash".
	# (Verified against a deliberate off-by-one before this line existed: the arm
	# reported OK.)
	if grep -qE 'AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:' \
		"$ERR" 2> /dev/null; then
		printf '   %s: the sanitizer reported an invalid access\n' "$label" >> "$DIED"
		SANITIZED=1
	fi

	# Keep the run's own diagnostics, labeled with the scenario they came from,
	# but only show them further down if the layer actually fails: a passing run
	# that writes to stderr is not this layer's business.
	if [ "$RC" -ne 0 ] || [ -s "$ERR" ]; then
		printf '   %s: exit status %s\n' "$label" "$RC" >> "$ERRLOG"
		[ -s "$ERR" ] && sed 's/^/     /' "$ERR" | head -10 >> "$ERRLOG"
	fi
done < "$SCN"

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
if [ "$NRUN" -eq 0 ]; then
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
if [ "$MEMONLY" -eq 1 ]; then
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
	echo "        had to be stopped printed only as far as it got. The Moulinette"
	echo "        runs the same program and sees the same ending."
	if [ "$SIGNALED" -eq 1 ]; then
		echo "        These programs walk argv, so what argc counts — and therefore"
		echo "        which indices of argv exist at all — is what to re-read in the"
		echo "        subject before anything else."
	fi
	rc=1
fi

# Show the runs' stderr only now that something has failed: it is usually the
# explanation (sanitizer report, libc diagnostic, the program's own message).
if [ "$rc" -ne 0 ] && [ -s "$ERRLOG" ]; then
	echo " ----- what the runs wrote to stderr -----"
	head -30 "$ERRLOG"
fi

# Say something on success too. A layer that prints nothing when it passes is
# indistinguishable from a layer that silently did not run, and this one now
# makes a claim the table cannot make on its own.
if [ "$rc" -eq 0 ]; then
	if [ "$MEMONLY" -eq 1 ]; then
		echo "argv_table: OK — $NRUN invocation(s) ran under the sanitizer; no"
		echo "            out-of-bounds access, no crash, no hang."
	else
		echo "argv_table: OK — $NRUN invocation(s) ran; none crashed, hung or flooded."
	fi
fi
exit "$rc"
