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
#   shell_test.sh --generator PATH --mode norm|lint|posix|diff|check|files [options] [-- ARGS...]
#   shell_test.sh --mode twin --twin-of LABEL --twin-tests DIR --label DIR
#                 [--stray NAME]... [--no-readme]
#
#   --generator PATH   $(location) of generators/exNN.sh
#   --mode MODE
#       norm   syntax-check the generator: `sh -n`. Does NOT run anything —
#              stays green on a skeleton stub. Its lint is the next two modes'.
#       lint   the PINNED shellcheck, as sh, at warning level and above: on
#              the generator, and -- with --deliverable, for a turn-in that
#              is a script -- on the script the generator writes. The
#              POSIX-undefined constructs (SC3xxx) in a script /bin/sh runs
#              (--script sh) are left to posix mode. A convention of this
#              repo's own, so shell_exercise places it at robust.
#       posix  the pinned shellcheck, as sh, on the script the generator
#              writes (--deliverable), for the POSIX-undefined constructs
#              alone: /bin/sh is where the subject has it run, and whether
#              that sh accepts one is not certain (strict).
#              Both lint and posix run the generator to get the script. A
#              generator /bin/sh cannot parse, one that fails, one that
#              writes no script, and a script /bin/sh cannot parse are
#              another test's to report (exNN_norm, exNN_output): they SKIP
#              it, saying which, and NO_SKIP=1 turns that into a failure.
#   --shellcheck PATH  $(location) of the pinned shellcheck, for lint and posix.
#   --script sh|./name|bash
#                      lint, posix: how the subject has the turn-in run. sh
#                      (the general rule: executable with /bin/sh) leaves its
#                      POSIX-undefined constructs to posix; bash (the example
#                      runs `bash name`) lints them here. ./name (the example
#                      runs it so) lets the script's own #! line decide: sh,
#                      dash or none is sh's case, any other shell bash's.
#   --output-test NAME lint, posix: the exercise's exNN_output, which reports
#                      a turn-in the generator did not make, or that does not
#                      parse; its exNN_norm reports a generator that does not.
#       diff   run the generator, then diff the deliverable against --expected.
#       check  run the generator, then run --check inside the scratch dir.
#       files  run the generator, then hand everything it LEFT BEHIND to
#              files_test.sh. Both shell subjects say on p.3 "You must not leave
#              any additional files in your directory other than those specified
#              in the assignment", and nothing checked it: a generator whose
#              cleanup half-runs leaves a stray file, every layer stays green,
#              and //tools:submit pushes it with `git add -A --force`.
#       twin   no run at all: a twin's own tests/exNN/ (--label) holds its
#              README and nothing else, since its tests are read from the
#              exercise it repeats (--twin-tests, named by --twin-of on its
#              shell_exercise call). Each --stray is a file there no target
#              reads, --no-readme says the README is missing; either fails.
#   --files-test PATH  $(location) of files_test.sh, for files mode.
#   --required NAME    a name the turn-in must contain (repeatable, files mode).
#   --optional NAME    a name that may be present without being reported.
#   --turnin NAME      a name the subject asks the turn-in to hold, handed to
#                      files_test.sh as --expected: listed as present or not
#                      produced, and never failed on (the output layer says
#                      why a turn-in is missing, with its clues).
#   --strict           an extra file FAILS rather than warns.
#   --label NAME       heading the files report is printed under.
#   --deliverable NAME basename of the produced file (required for diff).
#   --expected PATH    diff mode: the expected-output file.
#   --check PATH       check mode: a property script, run with $1 = deliverable name.
#   --stable           check mode: run the generator a second time, in another
#                      empty directory with the same fixtures and env, under an
#                      empty HOME, TMPDIR and XDG directories of its own (what
#                      the first run kept there is not the second's), and hand
#                      that directory to the check as $SHELL_CHECK_RERUN, where
#                      shell_check.sh's ck_stable compares the two turn-ins. A
#                      generator runs on every generate and every submit, so
#                      where the subject fixes the turn-in byte for byte, one
#                      it writes differently each time is never the one that
#                      was tested.
#   --wording KEY=TEXT check mode: the subject's own words for a sentence the
#                      check quotes, exported to it as $SHELL_CHECK_WORDING_KEY
#                      (shell_check.sh's ck_wording). Repeatable. A check that
#                      two projects share (twin_of) quotes each one's subject.
#   --oracle PATH      check mode: the //oracle binary, exported to the check as
#                      $ORACLE (absolute), for a reference no fixture can build.
#   --run              diff mode: EXECUTE the deliverable and diff its stdout
#                      (default: diff the deliverable's raw file content). It
#                      runs as `/bin/sh NAME`, never through its #! line, after
#                      a parse check, through --check-lib's ck_run.
#   --check-lib PATH   shell_check.sh: exported to a check script (check mode),
#                      and what --run runs the deliverable through (diff mode).
#   --interp NAME      run the deliverable via NAME instead of /bin/sh, for a
#                      subject that names another shell; no parse check.
#   --env K=V          export K=V before running (repeatable).
#   --redirect FROM=PATH  check mode: every run of the turn-in through ck_run
#                      reads the file PATH when it opens the path FROM (one
#                      of them). Proven on this machine before the check
#                      runs; see ck_redirected in shell_check.sh.
#   --redirect-lib PATH   the preload library that does it
#                      (//tools:path_redirect.so), for --redirect.
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
require awk basename cat cmp cp env grep mkdir mktemp rm sed sort tr
# `diff` is NOT in that list, though it was until the require scanner learned to
# read quoted strings: the word was being picked up out of the message
# "--mode must be norm|diff|check", split at the pipe and counted as a command.
# The real diff is always reached through $DIFF -- a path Bazel hands in -- which
# this check excludes by design, and progname_test.sh has the same shape and has
# never declared it. The `DIFF="diff"` default below is for hand-runs only.

# The shared runner helpers -- time budget, exiting signal traps, how a run
# ended, excerpts, hints -- written once in tools/runner_lib.sh.
RL_NAME=shell_test
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "shell_test.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool DIFF -- the pinned diff, which compares two files
# conventions: harness tool SHELLCHECK -- the pinned shellcheck, which reads the generator, or the script it wrote, and runs nothing
# conventions: harness tool FILES_TEST -- tools/files_test.sh, which compares file names and runs nothing

GEN=""
GEN_ARG=""
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
FILES_TEST=""
FREQUIRED=""
FOPTIONAL=""
FTURNIN=""
FSTRICT=0
FLABEL=""
TWIN_OF=""
TWIN_TESTS=""
TWIN_STRAYS=""
TWIN_README=1
REDIRECT_FROM=""
REDIRECT_TO=""
REDIRECT_LIB=""
STABLE=0
WORDINGS=""
SCRIPT="sh"
OUTPUT_TEST=""

abspath() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }

# On failure, print the exercise's foothold hints (a clues.tsv of guidance,
# never answers), by the one rule every runner reads that file with (rl_clues):
# '#' lines are for maintainers, only the hint column is shown, at most
# CLUE_MODE (3) of them. A shell exercise runs as one case, so every row fires.
# Called after a norm/diff/check failure, before exiting non-zero.
print_clue() {
	rl_clues "$CLUES"
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

# What the check script is handed comes from this call alone, as CK_REDIRECT_*
# does (prove_redirect): each of these is exported only on the path that gives
# it, so one left in the environment reached the check as if the call had --
# a second run nobody made, words nobody quoted, an oracle nobody named (V80).
unset SHELL_CHECK_RERUN ORACLE
for _v in $(env | sed -n 's/^\(SHELL_CHECK_WORDING_[A-Za-z0-9_]*\)=.*/\1/p'); do
	unset "$_v"
done

while [ $# -gt 0 ]; do
	case "$1" in
		--diff) need "$1" "$#"; DIFF="$2"; shift 2 ;;
		--shellcheck) need "$1" "$#"; SHELLCHECK=$(abspath "$2"); shift 2 ;;
		--generator) need "$1" "$#"; GEN_ARG=$2; GEN=$(abspath "$2"); shift 2 ;;
		--mode) need "$1" "$#"; MODE="$2"; shift 2 ;;
		--deliverable) need "$1" "$#"; DELIV="$2"; shift 2 ;;
		--expected) need "$1" "$#"; EXPECTED=$(abspath "$2"); shift 2 ;;
		--check) need "$1" "$#"; CHECK=$(abspath "$2"); shift 2 ;;
		--check-lib) need "$1" "$#"; CHECK_LIB=$(abspath "$2"); shift 2 ;;
		--oracle) need "$1" "$#"; ORACLE=$(abspath "$2"); export ORACLE; shift 2 ;;
		--clues) need "$1" "$#"; CLUES=$(abspath "$2"); shift 2 ;;
		--run) RUN=1; shift ;;
		--interp) need "$1" "$#"; INTERP="$2"; shift 2 ;;
		--env) need "$1" "$#"; ENVS="$ENVS
$2"; shift 2 ;;
		--fixture) need "$1" "$#"; FIXTURES="$FIXTURES
$(abspath "$2")"; shift 2 ;;
		--redirect)
			need "$1" "$#"
			case "$2" in
				/*=?*) ;;
				*) echo "shell_test.sh: --redirect is FROM=PATH, FROM an absolute path: '$2'" >&2; exit 2 ;;
			esac
			REDIRECT_FROM=${2%%=*}
			REDIRECT_TO=$(abspath "${2#*=}")
			shift 2 ;;
		--redirect-lib) need "$1" "$#"; REDIRECT_LIB=$(abspath "$2"); shift 2 ;;
		--files-test) need "$1" "$#"; FILES_TEST=$(abspath "$2"); shift 2 ;;
		--required) need "$1" "$#"; rl_list_add FREQUIRED "$2"; shift 2 ;;
		--optional) need "$1" "$#"; rl_list_add FOPTIONAL "$2"; shift 2 ;;
		--turnin) need "$1" "$#"; rl_list_add FTURNIN "$2"; shift 2 ;;
		--strict) FSTRICT=1; shift ;;
		--label) need "$1" "$#"; FLABEL="$2"; shift 2 ;;
		--twin-of) need "$1" "$#"; TWIN_OF="$2"; shift 2 ;;
		--twin-tests) need "$1" "$#"; TWIN_TESTS="$2"; shift 2 ;;
		--stray) need "$1" "$#"; TWIN_STRAYS="$TWIN_STRAYS
$2"; shift 2 ;;
		--no-readme) TWIN_README=0; shift ;;
		--stable) STABLE=1; shift ;;
		--wording)
			need "$1" "$#"
			case "${2%%=*}" in
				"$2" | "" | [!A-Za-z_]* | *[!A-Za-z0-9_]*)
					echo "shell_test.sh: --wording is KEY=TEXT, KEY a name, got '$2'" >&2
					exit 2 ;;
			esac
			WORDINGS="$WORDINGS
$2"
			shift 2
			;;
		--script)
			need "$1" "$#"
			case "$2" in
				sh | ./name | bash) SCRIPT=$2 ;;
				*) echo "shell_test.sh: --script is sh, ./name or bash, got '$2'" >&2; exit 2 ;;
			esac
			shift 2
			;;
		--output-test) need "$1" "$#"; OUTPUT_TEST="$2"; shift 2 ;;
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

# ---- twin: a twin's own tests folder holds its README and nothing else ------
# No generator is run: this is about the folder, not the turn-in. It used to
# be a fail() in shell_exercise, which took down every target of the package
# for one stray file; here it is one exercise's red, saying what to do.
if [ "$MODE" = twin ]; then
	[ -n "$TWIN_OF" ] && [ -n "$TWIN_TESTS" ] && [ -n "$FLABEL" ] || {
		echo "shell_test.sh: --mode twin needs --twin-of, --twin-tests and --label" >&2
		exit 2
	}
	if [ -z "$TWIN_STRAYS" ] && [ "$TWIN_README" = 1 ]; then
		echo "shell_test: OK -- $FLABEL holds only its README."
		echo "  Its tests are read from $TWIN_TESTS"
		echo "  (twin_of = \"$TWIN_OF\")."
		exit 0
	fi
	if [ -n "$TWIN_STRAYS" ]; then
		printf '  STRAY TEST FILE(S) in %s, which no target reads:\n' "$FLABEL"
		printf '%s\n' "$TWIN_STRAYS" | sed '/^$/d; s/^/      /'
		printf '  This exercise repeats %s (twin_of on its shell_exercise\n' "$TWIN_OF"
		printf '  call), so its tests are read from\n'
		printf '      %s\n' "$TWIN_TESTS"
		printf '  and a change made to the file(s) above changes nothing. Make it\n'
		printf '  there, where both projects read it, and delete them here.\n'
	fi
	if [ "$TWIN_README" = 0 ]; then
		printf '  MISSING: %sREADME.md\n' "$FLABEL"
		printf '  It tells whoever opens that folder that the tests are in\n'
		printf '      %s\n' "$TWIN_TESTS"
		printf '  and it keeps the folder in git, from which c_levels() makes the\n'
		printf '  per-exercise suite. Put it back: git checkout -- %sREADME.md\n' "$FLABEL"
	fi
	exit 1
fi

[ -n "$GEN" ] || { echo "shell_test.sh: --generator is required" >&2; exit 2; }
[ -f "$GEN" ] || { echo "shell_test.sh: generator not found: $GEN" >&2; exit 2; }

# ---- norm: just syntax-check the generator (no execution) -------------------
# `sh -n`, and nothing else, at basic: a generator /bin/sh cannot read never
# makes its turn-in, however it is graded. Its shellcheck lint is lint mode's,
# at robust -- a convention of this repo's own, the generator being this
# repo's way of turning a shell exercise in, not a subject's (docs/reference.md,
# "Shell turn-ins"); it used to run here, in every beginner's path.
if [ "$MODE" = norm ]; then
	if ! sh -n "$GEN"; then
		echo "shell_test.sh: '$GEN' has a syntax error" >&2
		exit 1
	fi
	echo "shell_test: OK -- ${GEN_ARG:-$GEN} parses under sh (sh -n)."
	exit 0
fi

# ---- lint, posix: the pinned shellcheck -----------------------------------
LINT_RED=0

# lint_verdict -- lint and posix modes end here, once everything there was to
# lint has been linted.
lint_verdict() {
	[ "$LINT_RED" = 0 ] && exit 0
	echo
	if [ "$MODE" = posix ]; then
		echo "  The subject has this script run with /bin/sh (\"Shell exercises must"
		echo "  be executable with /bin/sh\"), and POSIX leaves each construct above"
		echo "  undefined: one sh runs it and another refuses it, so whether the"
		echo "  grader's does is not certain. man dash shows what a strict sh accepts."
	else
		echo "  shellcheck's warnings are rigour this repo adds (robust): no subject"
		echo "  asks for them. Each finding names its SC code, and the page after it"
		echo "  says what it means and why it can bite."
	fi
	exit 1
}

# lint_skip WHAT WHY WHO -- WHAT could not be linted, for a reason another
# test (WHO) reports: this only says so. What was linted before it still
# decides the verdict.
lint_skip() {
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: $1 was not linted: $2."
		exit 1
	}
	echo "shell_test: SKIP — $1 was not linted: $2; $3 reports that."
	lint_verdict
}

if [ "$MODE" = lint ] || [ "$MODE" = posix ]; then
	if [ "$MODE" = posix ] && [ -z "$DELIV" ]; then
		echo "shell_test.sh: --mode posix needs --deliverable: it lints the turn-in" >&2
		exit 2
	fi
	# A script the subject runs with bash has no posix target: its POSIX-
	# undefined constructs are bash's to run, and lint's to report (robust).
	# Reached, the ./name branch below would have passed it, saying its #!
	# line named bash -- which, for --script bash, nobody had read.
	if [ "$MODE" = posix ] && [ "$SCRIPT" = bash ]; then
		echo "shell_test.sh: --mode posix with --script bash: a script the subject runs with" >&2
		echo "  bash has no posix target (its POSIX-undefined constructs are --mode lint's)." >&2
		exit 2
	fi
	# No pinned binary: nothing was linted. That is a gap, not a pass, and
	# it says so here rather than on stderr.
	if [ -z "$SHELLCHECK" ] || [ ! -x "$SHELLCHECK" ]; then
		[ "${NO_SKIP:-0}" != "1" ] || {
			echo "NO_SKIP set: no pinned shellcheck was supplied, so nothing was linted."
			exit 1
		}
		echo "shell_test: SKIP — no pinned shellcheck supplied; nothing was linted."
		exit 0
	fi
	SC_VERSION=$("$SHELLCHECK" --version 2> /dev/null | sed -n 's/^version: //p')
	LINT_START=$PWD
	# A generator /bin/sh cannot parse is exNN_norm's, at basic, and it can
	# make no script: shellcheck would only say the same thing again.
	NORM_TEST="the norm test"
	POSIX_TEST="the posix test"
	if [ -n "$OUTPUT_TEST" ]; then
		NORM_TEST=${OUTPUT_TEST%_output}_norm
		POSIX_TEST=${OUTPUT_TEST%_output}_posix
	fi
	sh -n "$GEN" 2> /dev/null ||
		lint_skip "the generator" "/bin/sh cannot parse it" "$NORM_TEST"
fi

# sc_lint DIR FILE WHICH WHAT -- lint FILE, found in DIR and shown by that name,
# with the pinned shellcheck as sh at warning level and above. WHICH picks the
# findings that count: all, posix (the POSIX-undefined constructs, SC3xxx,
# alone) or other (all but those). WHAT names the file in the one line this
# prints for it; shellcheck's own report of the findings that count follows
# it. Sets LINT_RED=1 when there are any; exits 2 when shellcheck could not
# read the file at all. --norc: no .shellcheckrc of the host's, or of the
# user's, decides what a finding is.
sc_lint() {
	_sl_dir=$1
	_sl_f=$2
	_sl_which=$3
	_sl_what=$4
	case "$_sl_which" in
		all) _sl_scope="warnings and errors" ;;
		posix) _sl_scope="POSIX-undefined constructs (SC3xxx) only" ;;
		*) _sl_scope="warnings and errors (its POSIX-undefined constructs, SC3xxx, are $POSIX_TEST's)" ;;
	esac
	_sl_out=$(cd "$_sl_dir" && "$SHELLCHECK" --norc -s sh -S warning -f gcc -- "$_sl_f" 2>&1)
	_sl_rc=$?
	if [ "$_sl_rc" -gt 1 ]; then
		echo "shell_test.sh: shellcheck could not read $_sl_what (status $_sl_rc):" >&2
		printf '%s\n' "$_sl_out" >&2
		exit 2
	fi
	_sl_codes=$(printf '%s\n' "$_sl_out" | sed -n 's/.*\[\(SC[0-9][0-9]*\)\]$/\1/p' |
		case "$_sl_which" in
			posix) grep '^SC3' ;;
			other) grep -v '^SC3' ;;
			*) cat ;;
		esac | sort -u | tr '\n' ',')
	_sl_codes=${_sl_codes%,}
	if [ -z "$_sl_codes" ]; then
		printf '%s: %s -- shellcheck %s as sh, %s: OK\n' "$MODE" "$_sl_what" "$SC_VERSION" "$_sl_scope"
		return 0
	fi
	printf '%s: %s -- shellcheck %s as sh, %s: FAIL\n' "$MODE" "$_sl_what" "$SC_VERSION" "$_sl_scope"
	(cd "$_sl_dir" && "$SHELLCHECK" --norc -s sh -S warning --include="$_sl_codes" -- "$_sl_f")
	LINT_RED=1
	return 0
}

if [ "$MODE" = lint ]; then
	sc_lint "$LINT_START" "${GEN_ARG:-$GEN}" all "the generator, ${GEN_ARG:-$GEN}"
	[ -n "$DELIV" ] || lint_verdict
fi

# The modes as words in a variable, not as case patterns: the require scan
# (//tools:conventions) reads a word after '|' as a command, and shellcheck
# refuses a case over a constant word (SC2194).
RUN_MODES=" lint posix diff check files "
case "$RUN_MODES" in
	*" $MODE "*) ;;
	*) echo "shell_test.sh: --mode must be norm|lint|posix|diff|check|files|twin" >&2; exit 2 ;;
esac
if [ "$STABLE" = 1 ] && [ "$MODE" != check ]; then
	echo "shell_test.sh: --stable is for check mode: the check compares the two runs" >&2
	exit 2
fi
if [ -n "$WORDINGS" ] && [ "$MODE" != check ]; then
	echo "shell_test.sh: --wording is for check mode: a check script quotes it" >&2
	exit 2
fi

# ---- diff/check: run the generator in a scratch dir, then validate ----------
WORK=$(mktemp -d)
WORK2=""
ALT2=""
rl_traps 'rm -rf "$WORK" ${WORK2:+"$WORK2"} ${ALT2:+"$ALT2"}'

# stage fixtures (generator inputs and/or run inputs). The lists are newline
# delimited, so split on newline and restore IFS afterwards (never `unset` it —
# referencing an unset IFS would trip `set -u`).
OLD_IFS=${IFS-}
stage() {  # stage DIR -- every fixture into DIR
	IFS='
'
	for f in $FIXTURES; do
		[ -n "$f" ] || continue
		cp -- "$f" "$1/" || { echo "shell_test.sh: cannot stage fixture $f" >&2; exit 2; }
	done
	IFS=$OLD_IFS
}
stage "$WORK"

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
# rather than an opaque Bazel kill with no output at all. SHELL_TIMEOUT caps each
# run, and what is left of the test's own limit caps that (rl_tmo, via
# bound_next).
BLOCKS=$(( 4194304 / 512 + 2 ))
TMO="${SHELL_TIMEOUT:-20}"

# bound_next WHAT -- set up the next run of the student's code (rl_run), or
# stop here, saying so, when the test's own time limit has nothing left for it.
bound_next() {
	if ! rl_tmo "$TMO"; then
		rl_overrun "$1"
		exit 1
	fi
}

# Explain a bounded death once, for whichever run hit it (after rl_classify).
report_limit() {
	case "$RL_CAUSE" in
		"timeout")
			echo "shell_test.sh: $1 was killed after ${RL_TMO}s — it never finished." >&2
			echo "               A generator or deliverable that loops forever looks" >&2
			echo "               exactly like this. Nothing here should take a second." >&2
			[ "$RL_CLAMPED" = 0 ] ||
				echo "               (${RL_TMO}s was what was left of $RL_OVERRUN_MARK.)" >&2
			return 0 ;;
		"runaway")
			echo "shell_test.sh: $1 kept writing past the output budget (SIGXFSZ)." >&2
			echo "               Something is printing in a loop." >&2
			return 0 ;;
	esac
	return 1
}

# What every layer below reads is the scratch dir, never deliverable/: say so
# once, at the top, since the files report and the checks both name the
# turn-in and a reader looks for it there. //tools:generate writes the same
# generator's output to deliverable/exNN, and //tools:submit regenerates
# before it pushes, so what is checked here is what is turned in.
_gen=${GEN##*/}
echo "shell_test: checking a fresh copy built from generators/$_gen in a scratch folder (not deliverable/${_gen%.sh})"

# run the student's generator (it should silently create its deliverable here)
bound_next "the generator"
( ulimit -f "$BLOCKS" 2> /dev/null; rl_run sh "$GEN" )
grc=$?
rl_classify "$grc"
if [ "$grc" -ne 0 ]; then
	# lint and posix have nothing to read: exNN_output says why.
	case "$MODE" in
		lint | posix) lint_skip "$DELIV" "the generator did not run to its end" \
			"${OUTPUT_TEST:-the output test}" ;;
	esac
	report_limit "the generator" ||
		echo "shell_test.sh: generator failed: $GEN" >&2
	print_clue
	exit 1
fi

# ---- lint, posix: the script the generator wrote ----------------------------
# Only once it is there and /bin/sh can parse it: a script that is not, or
# does not, is exNN_output's to report, at basic (ck_sh_parses).
if [ "$MODE" = lint ] || [ "$MODE" = posix ]; then
	[ -f "$DELIV" ] || lint_skip "$DELIV" "the generator wrote none this run" \
		"${OUTPUT_TEST:-the output test}"
	sh -n "$DELIV" 2> /dev/null || lint_skip "$DELIV" "/bin/sh cannot parse it" \
		"${OUTPUT_TEST:-the output test}"
	# Which shell its POSIX-undefined constructs are read for. "./name"
	# leaves that to the script's #! line: execve() honours it, so one that
	# names bash is run by bash when typed as ./name, and a construct POSIX
	# leaves undefined is then as certain as in a script the subject runs
	# with bash. sh or dash, or no #! line at all (the shell the grader types
	# ./name into decides), is the general rule's /bin/sh. This decides where
	# a finding is reported and nothing else: every target that RUNS the
	# script runs it with /bin/sh (ck_run), as the general rule says, so
	# exNN_output grades what /bin/sh does with it, whatever its #! line.
	RUNS_WITH=$SCRIPT
	if [ "$SCRIPT" = ./name ]; then
		RUNS_WITH="sh"
		SHEBANG=$(sed -n '1{/^#!/p;}' "$DELIV")
		if [ -n "$SHEBANG" ]; then
			# The interpreter: the first word after #!, or env's argument.
			INTERP=$(printf '%s\n' "${SHEBANG#??}" | awk '{
				i = 1; n = split($1, p, "/")
				if (p[n] == "env") for (i = 2; i <= NF && $i ~ /^-/; i++) ;
				w = i == 1 ? $1 : $i; n = split(w, p, "/"); print p[n] }')
			# "#!" alone names nothing, and execve() refuses it: the shell
			# ./name was typed into runs it, as with no #! line.
			[ -n "$INTERP" ] || INTERP="sh"
			case "$INTERP" in
				sh | dash) ;;
				*) RUNS_WITH=$INTERP ;;
			esac
		fi
	fi
	if [ "$RUNS_WITH" = sh ]; then
		if [ "$MODE" = posix ]; then
			sc_lint "$WORK" "$DELIV" posix "$DELIV, as the generator wrote it"
		else
			sc_lint "$WORK" "$DELIV" other "$DELIV, as the generator wrote it"
		fi
	elif [ "$MODE" = posix ]; then
		LINT_TEST="the lint test"
		[ -z "$OUTPUT_TEST" ] || LINT_TEST=${OUTPUT_TEST%_output}_lint
		printf 'posix: %s -- OK: its #! line names %s, so run as ./name, the way\n' \
			"$DELIV" "$RUNS_WITH"
		echo "  the subject's example runs it, $RUNS_WITH runs it. Its POSIX-undefined"
		echo "  constructs are $LINT_TEST's to report, with this repo's other rigour"
		echo "  (robust). The tests still run it with /bin/sh, as the general rule says,"
		echo "  so ${OUTPUT_TEST:-the output test} grades what /bin/sh does with it."
	elif [ "$SCRIPT" = bash ]; then
		sc_lint "$WORK" "$DELIV" all "$DELIV, as the generator wrote it (the subject runs it with bash)"
	else
		sc_lint "$WORK" "$DELIV" all "$DELIV, as the generator wrote it (its #! line names $RUNS_WITH)"
	fi
	lint_verdict
fi

# ---- --stable: the same generator again, in another empty directory --------
# Before the check, so the check can judge it (ck_stable). How the second run
# ended is not a verdict here: one that fails, or writes something else, is
# the instability the check names. A bounded death is still said, as for the
# first run, since "the two runs differ" would not explain it.
#
# Under a HOME and a TMPDIR of its own, both empty, with the XDG variables
# unset so that each defaults to a folder of that HOME: the second run stands
# for the next generate, the submit, another machine. A generator that keeps
# what it made outside the turn-in directory -- a key made once in ~/.ssh
# and copied from there on every later run -- wrote the same bytes twice
# under one HOME, and passed, while two machines, or a fresh clone, get two
# different files.
if [ "$STABLE" = 1 ]; then
	WORK2=$(mktemp -d)
	ALT2=$(mktemp -d)
	mkdir "$ALT2/home" "$ALT2/tmp" || {
		echo "shell_test.sh: cannot make the second run's HOME and TMPDIR" >&2; exit 2; }
	stage "$WORK2"
	cd "$WORK2" || { echo "shell_test.sh: cannot enter the second scratch dir" >&2; exit 2; }
	bound_next "the generator's second run"
	(
		ulimit -f "$BLOCKS" 2> /dev/null
		HOME=$ALT2/home
		TMPDIR=$ALT2/tmp
		export HOME TMPDIR
		# Unset, each defaults to a folder of the new HOME.
		unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME \
			XDG_RUNTIME_DIR 2> /dev/null || :
		rl_run sh "$GEN"
	) > /dev/null 2>&1
	rl_classify "$?"
	case "$RL_CAUSE" in
		ok | "exit") ;;
		*) report_limit "the generator's second run" ||
			echo "shell_test.sh: the generator's second run $RL_WHY" >&2 ;;
	esac
	cd "$WORK" || { echo "shell_test.sh: cannot enter scratch dir" >&2; exit 2; }
	SHELL_CHECK_RERUN=$WORK2
	export SHELL_CHECK_RERUN
fi

# ---- files: what the generator LEFT BEHIND ---------------------------------
#
# The scratch dir IS the turn-in directory: generate.sh runs the same generator
# in an empty directory of its own, what it leaves there becomes deliverable/exNN,
# and //tools:submit pushes whatever is there. So the set of names here is
# exactly the set 42 would receive.
#
# Delegated to files_test.sh rather than compared in place, so a student reads
# ONE report for this question whether the module is C or shell -- and so the
# missing/extra asymmetry is decided in one file instead of two.
if [ "$MODE" = files ]; then
	[ -n "$FILES_TEST" ] || {
		echo "shell_test.sh: --files-test is required for files mode" >&2; exit 2; }

	# A FIXTURE IS OURS, NOT THE STUDENT'S. Anything this runner staged into the
	# scratch dir before running the generator would otherwise be reported as a
	# file they left behind -- a driver bug charged to the student, which is the
	# defect class this repo ranks worst after a false green.
	is_fixture() {
		_f=$1
		_oifs=${IFS-}
		IFS='
'
		for _x in $FIXTURES; do
			[ -n "$_x" ] || continue
			if [ "$(basename "$_x")" = "$_f" ]; then
				IFS=$_oifs
				return 0
			fi
		done
		IFS=$_oifs
		return 1
	}

	# Built in the positional parameters: shell-01 ex05's deliverable is a name
	# made of shell metacharacters, so a list held in one string and re-split
	# would come apart on exactly the exercise this most has to survive.
	set -- --label "${FLABEL:-deliverable}"
	[ "$FSTRICT" = 1 ] && set -- "$@" --strict
	# FREQUIRED, FOPTIONAL and FTURNIN are one name per line (runner_lib.sh,
	# LISTS OF WORDS): they used to be joined with blanks and re-split, the
	# very thing this paragraph warns about.
	rl_split_on
	for _r in $FREQUIRED; do set -- "$@" --required "$_r"; done
	for _o in $FOPTIONAL; do set -- "$@" --optional "$_o"; done
	for _e in $FTURNIN; do set -- "$@" --expected "$_e"; done
	rl_split_off
	# Dotfiles included: a stray .gitignore or .DS_Store is exactly the kind of
	# thing a half-run cleanup leaves, and it would be pushed with the rest.
	for _f in * .[!.]* ..?*; do
		[ -e "$_f" ] || [ -L "$_f" ] || continue
		is_fixture "$_f" && continue
		set -- "$@" --actual "$PWD/$_f"
	done
	sh "$FILES_TEST" "$@"
	frc=$?
	[ "$frc" -ne 0 ] && print_clue
	exit "$frc"
fi

# prove_redirect -- export the redirect the check's ck_run applies, once it
# is shown to work here: a program that opens REDIRECT_FROM has to read
# REDIRECT_TO, through the shell's own `<` (its first line, as `read` gets it
# from the fixture itself) and through cat (the whole file, compared byte for
# byte). Neither cuts the file into lines with a text tool: that is one of the
# exercise's own steps, and this runner ships. What cannot take it -- a machine
# whose loader ignores the library, a C library that is not glibc -- is told
# to the check in CK_REDIRECT_BROKEN rather than hidden: its runs then read
# the machine's own file, and it says which properties that leaves unseen.
prove_redirect() {
	unset CK_REDIRECT_LIB CK_REDIRECT_FROM CK_REDIRECT_TO CK_REDIRECT_NAME CK_REDIRECT_BROKEN
	[ -n "$REDIRECT_FROM" ] || return 0
	[ -f "$REDIRECT_TO" ] || {
		echo "shell_test.sh: the fixture for $REDIRECT_FROM is not here: $REDIRECT_TO" >&2; exit 2; }
	[ -f "$REDIRECT_LIB" ] || {
		echo "shell_test.sh: --redirect needs --redirect-lib (//tools:path_redirect.so)" >&2; exit 2; }
	_want=""
	IFS= read -r _want < "$REDIRECT_TO"
	_got=$(env LD_PRELOAD="$REDIRECT_LIB" CK_REDIRECT_FROM="$REDIRECT_FROM" \
		CK_REDIRECT_TO="$REDIRECT_TO" /bin/sh -c \
		'IFS= read -r l < "$1"; printf "%s\n" "$l"
		cat -- "$1" | cmp -s - "$2" && echo whole' \
		redirect-probe "$REDIRECT_FROM" "$REDIRECT_TO" 2>&1)
	if [ -n "$_want" ] && [ "$_got" = "$_want
whole" ]; then
		CK_REDIRECT_LIB=$REDIRECT_LIB
		CK_REDIRECT_FROM=$REDIRECT_FROM
		CK_REDIRECT_TO=$REDIRECT_TO
		# As the repository names it, for the reader: the runfiles path
		# with the runfiles root taken off.
		CK_REDIRECT_NAME=${REDIRECT_TO#"${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/"}
		export CK_REDIRECT_LIB CK_REDIRECT_FROM CK_REDIRECT_TO CK_REDIRECT_NAME
	else
		CK_REDIRECT_BROKEN="a program that opens $REDIRECT_FROM here reads the machine's own file, not the fixture (the preload library did not take)"
		export CK_REDIRECT_BROKEN
	fi
}

if [ "$MODE" = check ]; then
	[ -n "$CHECK" ] || { echo "shell_test.sh: --check is required for check mode" >&2; exit 2; }
	[ -n "$CHECK_LIB" ] && export SHELL_CHECK_LIB="$CHECK_LIB"
	prove_redirect
	# The subject's words, for the check alone: the generator has run.
	IFS='
'
	for kv in $WORDINGS; do
		[ -n "$kv" ] || continue
		export "SHELL_CHECK_WORDING_$kv"
	done
	IFS=$OLD_IFS
	# The checks run the turn-in, so they get what is left of the test's time
	# limit and no more: a script that never ends is then stopped here, and
	# said to be, rather than by Bazel with the log cut short.
	if ! rl_tmo; then
		rl_overrun "the checks on $DELIV"
		exit 1
	fi
	rl_run sh "$CHECK" "$DELIV" "$@"
	crc=$?
	rl_classify "$crc"
	case "$RL_CAUSE" in
		ok | "exit") ;;
		"timeout") rl_overrun "the checks on $DELIV"; crc=1 ;;
		*) echo "shell_test.sh: the checks on $DELIV $RL_WHY" >&2; crc=1 ;;
	esac
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
PARSED=1
if [ "$RUN" = 1 ]; then
	# The run goes through shell_check.sh's ck_run, the one way a turn-in is
	# run anywhere in this harness, and not through a copy of it here: this
	# branch ran ./name through its #! line, with no parse check, and printed
	# its stderr with an excerpt of its own. So a script runs as
	# `/bin/sh name` (the three shell subjects require /bin/sh), is first
	# asked whether /bin/sh can parse it, and what the run wrote to stderr,
	# and how it ended, are shown the way every check shows them. An
	# exercise whose subject names another shell passes --interp, and gets
	# that shell and no parse check. ck_run judges nothing; the library's
	# exit guard, which is for check scripts, is switched off.
	[ -n "$CHECK_LIB" ] || {
		echo "shell_test.sh: --run needs --check-lib: the run goes through its ck_run" >&2
		exit 2
	}
	SHELL_CHECK_LIB=$CHECK_LIB
	export SHELL_CHECK_LIB
	_interp=${INTERP:-sh}
	case "$_interp" in
		sh | /bin/sh)
			# The library's parse check, in a shell of its own, as the
			# run below: loading the library sets its exit guard for
			# check scripts, which is no trap of this runner's.
			_parse=$(sh -c '. "$1"; trap - EXIT; ck_sh_parses "$2"' \
				ck_sh_parses "$CHECK_LIB" "$DELIV")
			case "$_parse" in
				*"[FAIL]"*) PARSED=0; printf '%s\n' "$_parse" ;;
			esac
			;;
	esac
	# The shell that calls ck_run is the run rl_run bounds: the test's time
	# limit and the output budget reach the deliverable through it, and a
	# timeout or a stop from outside is read off it (rl_classify below). How
	# the DELIVERABLE ended is ck_run's to know -- it reads tools/exit_status
	# too -- so the shell hands its line ($CK_HOW) back in a file, and the
	# signal check further down judges that, never the status: a script that
	# ends with `exit 255` returned, it was not killed by "signal 127".
	bound_next "the deliverable"
	rm -f "$ACTUAL.ended"
	( ulimit -f "$BLOCKS" 2> /dev/null
		rl_run sh -c '. "$1"; trap - EXIT; out=$2; shift 2
			ck_run "$out" "$@"
			printf "%s\n" "$CK_HOW" > "$out.ended"
			exit "$CK_RC"' ck_run \
			"$CHECK_LIB" "$ACTUAL" "$_interp" "$DELIV" "$@" )
	RRC=$?
	rl_classify "$RRC"
	case "$RL_CAUSE" in
		ok | "exit")
			# ck_run ran to its end and showed the run, stderr and all: its
			# excerpt is rl_excerpt's, which says what it left out and keeps
			# the whole text. How the deliverable ended is its line.
			rl_classify "$RRC" "$ACTUAL.ended"
			;;
		*)
			# The time limit, or a signal from outside, stopped the shell
			# running it before ck_run could show anything: what the
			# deliverable wrote to stderr until then is shown here.
			if [ -s "$ACTUAL.err" ]; then
				_ran="$_interp $DELIV"
				[ $# -eq 0 ] || _ran="$_ran $*"
				printf '  ran: %s\n' "$_ran"
				printf '       stderr, until it was stopped:\n'
				rl_excerpt "$ACTUAL.err" 5 run-stderr.txt "         "
			fi
			;;
	esac
	rm -f "$ACTUAL.err" "$ACTUAL.ended"
else
	cat -- "$DELIV" > "$ACTUAL"
fi

# A deliverable KILLED BY A SIGNAL is never correct, however good its output
# looks. Only signals, not any non-zero status: no shell subject in either module
# specifies an exit status, and a script whose last command is a failing `test`
# legitimately exits non-zero while having printed exactly the right thing.
# Failing on that would red correct work -- which is why a plain return, of any
# number, is not judged (rl_classify tells a return from a death by asking
# waitpid(), never by the number). Checked before the diff, because a crash
# outranks a byte comparison.
if [ "$RUN" = 1 ] && [ "$RL_CAUSE" != ok ] && [ "$RL_CAUSE" != "exit" ] && [ "$RL_CAUSE" != noexec ]; then
	report_limit "the deliverable" || {
		echo "shell_test.sh: the deliverable $RL_WHY." >&2
		echo "               Output up to that point may still match, which is why" >&2
		echo "               a diff alone can look fine. It is not." >&2
	}
	rm -f "$ACTUAL"
	print_clue
	exit 1
fi

# Through runner_lib.sh's rl_udiff, which renders every byte and marks each
# line's end: printed raw, a carriage return or a trailing space in the turn-in
# read exactly as the expected line did, and a NUL turned the whole report
# into "Binary files X and Y differ", naming two scratch files (V51).
_got="$DELIV, as the generator wrote it"
[ "$RUN" = 0 ] || _got="what $DELIV printed"
rl_udiff "$DIFF" "$EXPECTED" "$ACTUAL" expected "$_got"
DRC=$?
rm -f "$ACTUAL"
# A script /bin/sh cannot parse fails whatever it printed: dash runs a script
# line by line, so one can print every expected line and then die on a syntax
# error further down. Its message is above, where the parse was checked.
[ "$PARSED" = 1 ] || [ "$DRC" -ne 0 ] || DRC=1
[ "$DRC" -ne 0 ] && print_clue
exit $DRC
