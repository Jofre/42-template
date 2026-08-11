#!/bin/sh
# Validate a shell-piscine exercise.
#
# In the shell piscine the student's ANSWER is the generator script
# (generators/exNN.sh): a sequence of shell commands that, run with the current
# directory as an empty scratch dir, creates the exercise's deliverable(s) there.
# This runner re-runs that generator in a throwaway dir and checks the result, so
# tests never depend on the (gitignored, disposable) deliverable/ tree on disk.
#
# Usage:
#   shell_test.sh --generator PATH --mode norm|diff|check [options] [-- ARGS...]
#
#   --generator PATH   $(location) of generators/exNN.sh
#   --mode MODE
#       norm   syntax-check the generator: `sh -n`, then the PINNED shellcheck.
#              Does NOT run anything — stays green on a skeleton stub.
#   --shellcheck PATH  $(location) of the pinned shellcheck, for norm mode.
#       diff   run the generator, then diff the deliverable against --expected.
#       check  run the generator, then run --check inside the scratch dir.
#   --deliverable NAME basename of the produced file (required for diff).
#   --expected PATH    diff mode: the expected-output file.
#   --check PATH       check mode: a property script, run with $1 = deliverable name.
#   --run              diff mode: EXECUTE the deliverable and diff its stdout
#                      (default: diff the deliverable's raw file content).
#   --interp NAME      run the deliverable via NAME (sh/bash) instead of ./NAME.
#   --env K=V          export K=V before running (repeatable).
#   --fixture PATH     stage this file into the scratch dir before running (repeatable);
#                      covers generator inputs (e.g. resources.tar.gz) and run inputs.
#   --                 remaining args are passed to the deliverable (diff --run)
#                      or to the check script.
#
# Exit status: 0 on success, non-zero on any failure.

set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "shell_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require cat cp grep mktemp rm sed
# `diff` is NOT in that list, though it was until the require scanner learned to
# read quoted strings: the word was being picked up out of the message
# "--mode must be norm|diff|check", split at the pipe and counted as a command.
# The real diff is always reached through $DIFF -- a path Bazel hands in -- which
# this check excludes by design, and progname_test.sh has the same shape and has
# never declared it. The `DIFF="diff"` default below is for hand-runs only.

GEN=""
MODE=""
DELIV=""
EXPECTED=""
CHECK=""
CHECK_LIB=""
CLUES=""
RUN=0
INTERP=""
ENVS=""
FIXTURES=""

abspath() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }

# On failure, print the exercise's foothold hint (a clues.tsv of guidance, never
# answers). Called after a norm/diff/check failure, before exiting non-zero.
print_clue() {
	[ -n "$CLUES" ] && [ -f "$CLUES" ] || return 0
	printf '  ------------------------------\n'
	printf '  HINT:\n'
	grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$CLUES" | sed 's/^/    /'
}

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
# The pinned diff. Defaults to the box's so a hand-run outside Bazel still
# works; the targets pass --diff, because this output goes straight to a
# student and GNU and BSD do not format a unified diff identically.
DIFF="diff"

# The pinned shellcheck. NO host fallback, by design: shellcheck's version
# decides which warnings exist, so `command -v shellcheck` made a student's
# norm verdict depend on which machine they sat at -- red on a box with a
# newer copy, green with none installed at all, and the "none installed"
# branch exited 0 while saying so only on stderr, where nobody reads it.
# //tools:conventions had already been through this and pinned its own copy;
# this is the same binary, reaching the layer that grades people.
SHELLCHECK=""

need() { [ "$2" -ge 2 ] || { echo "shell_test.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--diff) need "$1" "$#"; DIFF="$2"; shift 2 ;;
		--shellcheck) need "$1" "$#"; SHELLCHECK=$(abspath "$2"); shift 2 ;;
		--generator) need "$1" "$#"; GEN=$(abspath "$2"); shift 2 ;;
		--mode) need "$1" "$#"; MODE="$2"; shift 2 ;;
		--deliverable) need "$1" "$#"; DELIV="$2"; shift 2 ;;
		--expected) need "$1" "$#"; EXPECTED=$(abspath "$2"); shift 2 ;;
		--check) need "$1" "$#"; CHECK=$(abspath "$2"); shift 2 ;;
		--check-lib) need "$1" "$#"; CHECK_LIB=$(abspath "$2"); shift 2 ;;
		--clues) need "$1" "$#"; CLUES=$(abspath "$2"); shift 2 ;;
		--run) RUN=1; shift ;;
		--interp) need "$1" "$#"; INTERP="$2"; shift 2 ;;
		--env) need "$1" "$#"; ENVS="$ENVS
$2"; shift 2 ;;
		--fixture) need "$1" "$#"; FIXTURES="$FIXTURES
$(abspath "$2")"; shift 2 ;;
		--) shift; break ;;
		*) echo "shell_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

# Absolute, because this runner cds into a scratch directory before it diffs,
# and Bazel hands the pinned diff over as a runfiles-RELATIVE path. Without
# this the whole layer dies with "diff: not found" -- exit 127, which reads as
# a broken box rather than a stranded path.
case "$DIFF" in
	*/*)
		case "$DIFF" in
			/*) ;;
			*) DIFF="$PWD/$DIFF" ;;
		esac
		;;
esac

[ -n "$GEN" ] || { echo "shell_test.sh: --generator is required" >&2; exit 2; }
[ -f "$GEN" ] || { echo "shell_test.sh: generator not found: $GEN" >&2; exit 2; }

# ---- norm: just syntax-check the generator (no execution) -------------------
if [ "$MODE" = norm ]; then
	if ! sh -n "$GEN"; then
		echo "shell_test.sh: '$GEN' has a syntax error" >&2
		exit 1
	fi
	if [ -n "$SHELLCHECK" ] && [ -x "$SHELLCHECK" ]; then
		"$SHELLCHECK" -s sh -S warning "$GEN" || exit 1
		exit 0
	fi
	# No pinned binary: `sh -n` ran, so a syntax error is still caught, but the
	# half of this layer that finds unquoted expansions and the rest of SC2xxx
	# did not. That is a gap, not a pass, and it says so here rather than on
	# stderr where the old message went to die.
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: no pinned shellcheck was supplied, so this generator was"
		echo "             only parsed (sh -n) and never linted."
		exit 1
	}
	echo "shell_test: SKIP — no pinned shellcheck supplied; syntax check only."
	exit 0
fi

[ "$MODE" = diff ] || [ "$MODE" = check ] || {
	echo "shell_test.sh: --mode must be norm|diff|check" >&2; exit 2; }

# ---- diff/check: run the generator in a scratch dir, then validate ----------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# stage fixtures (generator inputs and/or run inputs). The lists are newline
# delimited, so split on newline and restore IFS afterwards (never `unset` it —
# referencing an unset IFS would trip `set -u`).
OLD_IFS=${IFS-}
IFS='
'
for f in $FIXTURES; do
	[ -n "$f" ] || continue
	cp -- "$f" "$WORK/" || { echo "shell_test.sh: cannot stage fixture $f" >&2; exit 2; }
done
IFS=$OLD_IFS

cd "$WORK" || { echo "shell_test.sh: cannot enter scratch dir" >&2; exit 2; }

# don't let a host FT_* leak in and make a test pass for the wrong reason
unset FT_USER FT_LINE1 FT_LINE2 FT_NBR1 FT_NBR2 2>/dev/null || true
IFS='
'
for kv in $ENVS; do
	[ -n "$kv" ] || continue
	export "${kv?}"
done
IFS=$OLD_IFS

# Bound what unverified code can do before running any of it — the same idiom
# every C-side runner carries (grep tools/diff_output.sh for "ulimit -f"), and
# the reason it belongs here too is that this is the ONLY functional runner
# either shell module has. `ulimit -f` counts 512-byte blocks and makes the
# kernel kill a runaway writer with SIGXFSZ instead of letting it fill the disk;
# the inner timeout turns an infinite loop into a message a student can act on
# rather than an opaque Bazel kill with no output at all.
BLOCKS=$(( 4194304 / 512 + 2 ))
TMO="${SHELL_TIMEOUT:-20}"
if command -v timeout > /dev/null 2>&1; then
	RUNNER="timeout -s KILL $TMO"
else
	RUNNER=""
fi

# Explain a bounded death once, for whichever run hit it.
report_limit() {
	case "$2" in
		137)
			echo "shell_test.sh: $1 was killed after ${TMO}s — it never finished." >&2
			echo "               A generator or deliverable that loops forever looks" >&2
			echo "               exactly like this. Nothing here should take a second." >&2
			return 0 ;;
		153)
			echo "shell_test.sh: $1 kept writing past the output budget (SIGXFSZ)." >&2
			echo "               Something is printing in a loop." >&2
			return 0 ;;
	esac
	return 1
}

# run the student's generator (it should silently create its deliverable here)
# shellcheck disable=SC2086
( ulimit -f "$BLOCKS" 2> /dev/null; $RUNNER sh "$GEN" )
grc=$?
if [ "$grc" -ne 0 ]; then
	report_limit "the generator" "$grc" ||
		echo "shell_test.sh: generator failed: $GEN" >&2
	print_clue
	exit 1
fi

if [ "$MODE" = check ]; then
	[ -n "$CHECK" ] || { echo "shell_test.sh: --check is required for check mode" >&2; exit 2; }
	[ -n "$CHECK_LIB" ] && export SHELL_CHECK_LIB="$CHECK_LIB"
	sh "$CHECK" "$DELIV" "$@"
	crc=$?
	[ "$crc" -ne 0 ] && print_clue
	exit "$crc"
fi

# diff mode
[ -n "$DELIV" ] || { echo "shell_test.sh: --deliverable is required for diff mode" >&2; exit 2; }
[ -n "$EXPECTED" ] || { echo "shell_test.sh: --expected is required for diff mode" >&2; exit 2; }
if [ ! -e "$DELIV" ]; then
	echo "shell_test.sh: deliverable '$DELIV' was not produced by the generator" >&2
	ls -la >&2
	print_clue
	exit 1
fi

ACTUAL=$(mktemp)
RRC=0
if [ "$RUN" = 1 ]; then
	# shellcheck disable=SC2086
	if [ -n "$INTERP" ]; then
		( ulimit -f "$BLOCKS" 2> /dev/null; $RUNNER "$INTERP" "$DELIV" "$@" ) \
			> "$ACTUAL" 2> /dev/null
	else
		( ulimit -f "$BLOCKS" 2> /dev/null; $RUNNER "./$DELIV" "$@" ) \
			> "$ACTUAL" 2> /dev/null
	fi
	RRC=$?
else
	cat -- "$DELIV" > "$ACTUAL"
fi

# A deliverable KILLED BY A SIGNAL is never correct, however good its output
# looks. Only signals, not any non-zero status: no shell subject in either module
# specifies an exit status, and a script whose last command is a failing `test`
# legitimately exits non-zero while having printed exactly the right thing.
# Failing on that would red correct work — which is why the line is drawn at 128
# rather than at 0. Checked before the diff, because a crash outranks a byte
# comparison.
if [ "$RRC" -gt 128 ]; then
	report_limit "the deliverable" "$RRC" || {
		echo "shell_test.sh: the deliverable died on signal $((RRC - 128))." >&2
		echo "               Output up to that point may still match, which is why" >&2
		echo "               a diff alone can look fine. It is not." >&2
	}
	rm -f "$ACTUAL"
	print_clue
	exit 1
fi

"$DIFF" -u "$EXPECTED" "$ACTUAL"
DRC=$?
rm -f "$ACTUAL"
[ "$DRC" -ne 0 ] && print_clue
exit $DRC
