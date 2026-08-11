#!/bin/sh
# submit.sh — test, then push each module's deliverable/ to its 42 (Vogsphere) repo.
#
# Run with Bazel (the single entry point):
#     bazel run //tools:submit                     # every module with a remote set
#     bazel run //tools:submit -- c-piscine-c-00   # only the listed module(s)
#     bazel run //tools:submit -- -n               # dry-run: show what would happen
#     bazel run //tools:submit -- -f               # force-push (needed when RE-submitting)
#     bazel run //tools:submit -- --no-gate        # skip the pre-push test gate
#
# For each module that has a remote set in the REMOTES table below, submit:
#   1. (shell modules) regenerates deliverable/ from generators/;
#   2. runs that module's Bazel tests as a GATE — a module with failing tests is
#      reported BLOCKED and is NOT pushed;
#   3. (re)initialises deliverable/ as its own git repo and pushes it.
# You only ever edit the REMOTES table. Leave a URL as REPLACE_ME to skip a module.
#
# How much has to be green before a module is pushed is a LADDER, and each rung
# also runs everything below it:
#     basic     what the Moulinette itself grades — the default
#     strict    + the KOs that depend on the evaluator's main() or on the module
#     robust    + this repo's own differential and sanitizer rigour
#     complete  + portability and cost. Everything. ("all" is a synonym.)
# Pick a rung for ONE run with --gate-level LEVEL. Make it permanent by exporting
# SUBMIT_GATE=LEVEL from your shell profile (yours alone, on this machine), or by
# writing the level into a .submit-level file at the repo root, which is not
# gitignored and so follows the repo to every machine you clone it to. With no
# such file the gate is `basic`. An unknown level is an error, and prints the
# full ladder.
#
# Other options: -b/--branch B (default master), -m/--message M, -h/--help.
#
# Usage:
#   bazel run //tools:submit [-- MODULE...] [--gate-level LEVEL] [--no-gate]
#
#   MODULE          which c-piscine-* module(s) to push; all configured if none
#   --gate-level    which level must be green first (basic|strict|robust|complete)
#   --no-gate       push without running the gate. For emergencies; the gate is
#                   the only thing standing between a red module and 42.

set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "submit.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require cat chmod dirname git grep head mkdir mktemp rm sed tail tr

# Repo root: from `bazel run` it's BUILD_WORKSPACE_DIRECTORY; run directly it's the
# parent of tools/.
WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$WS" || exit 1

# ============================================================================
# REMOTES TABLE — fill in each module's Vogsphere URL (everything after "=").
# "REPLACE_ME" means "not set yet" and is skipped.
# ============================================================================
REMOTES='
c-piscine-c-00=REPLACE_ME
c-piscine-c-01=REPLACE_ME
c-piscine-c-02=REPLACE_ME
c-piscine-c-03=REPLACE_ME
c-piscine-c-04=REPLACE_ME
c-piscine-c-05=REPLACE_ME
c-piscine-c-06=REPLACE_ME
c-piscine-c-07=REPLACE_ME
c-piscine-c-08=REPLACE_ME
c-piscine-c-09=REPLACE_ME
c-piscine-c-10=REPLACE_ME
c-piscine-c-11=REPLACE_ME
c-piscine-c-12=REPLACE_ME
c-piscine-c-13=REPLACE_ME
c-piscine-rush-00=REPLACE_ME
c-piscine-rush-01=REPLACE_ME
c-piscine-rush-02=REPLACE_ME
c-piscine-bsq=REPLACE_ME
c-piscine-shell-00=REPLACE_ME
c-piscine-shell-01=REPLACE_ME
'

show_help() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

DRY=0
FORCE=0
GATE=1
# Which layers must be green before a module is pushed.
#
# The Moulinette grades norm, compilation, output, the turn-in file set and the
# authorised-function list — that is what "gradeable" means, and it is the
# DEFAULT here so this suite never refuses to push work that would score fine.
# The layers above it (symbols, memory, differential, portability, performance)
# are extra rigour this repo adds; they are worth knowing about, but "not as
# rigorous as I would like" is not the same verdict as "not gradeable" and should
# not block a submission for someone who did not opt in.
#
# Raise it for yourself WITHOUT changing what anyone else gets, by exporting the
# variable from your shell profile (.vscode/settings.json is committed, so it is
# the wrong place for a personal setting):
#     export SUBMIT_GATE=complete

# The tag filter for a gate level.
#
# tools/defs.bzl owns which layer sits at which level (_LAYER_LEVEL), and every
# test its macros emit carries CUMULATIVE lvl_* tags: a norm test is tagged
# lvl_basic AND lvl_strict AND lvl_robust AND lvl_complete. So ONE tag selects a
# whole rung, and a layer added to _LAYER_LEVEL is gated here with no edit to
# this file.
#
# This was three hardcoded lists of layer names. They agreed with _LAYER_LEVEL
# the day they were written, and that is the whole problem: a new level-1 layer
# would have been silently left OUT of the gate — which then reports green having
# never run it, the worst failure mode a gate has — until someone remembered
# there was a second file to edit.
#
# `complete` filters on -manual ALONE rather than on lvl_complete, because those
# are not the same set: a test whose layer tag is missing from _LAYER_LEVEL gets
# no lvl_* tag at all, and "everything" has to include the layer nobody has
# classified yet.
#
# -manual at every level so an exercise's opt-in variants (rush's bonus variants
# tag themselves manual) cannot block a push.
#
# The lists below are DOCUMENTATION — why each layer sits where it does, which
# is not something _LAYER_LEVEL can say. Nothing reads them; if they ever drift
# from defs.bzl the gate is still right and only this prose is wrong.
#
# basic  = every layer whose failure is a KO on the Moulinette. Nothing here is
#          this repo being fussy; each one is a way to score zero.
#            norm       norminette is run and is pass/fail
#            compile    the box builds with -Wall -Wextra -Werror
#            output     wrong bytes on stdout
#            files      a missing (or unasked-for) file in the turn-in
#            forbidden  calling something the subject did not authorise
#            prototype  a signature that differs from the subject's. C links a
#                       mismatched signature without complaint, so this shows up
#                       on the box as wrong values rather than as an error — the
#                       layer just names the cause instead of the symptom.
#
# strict = failure modes that depend on the evaluator's code or the module, so
#          they are real but not certain:
#            symbols    a non-static helper can collide with a name in the
#                       main() the Moulinette compiles alongside your file, and
#                       the LINK fails on otherwise perfect code
#            valgrind   leaks, which are graded in the malloc modules
#
# robust = this repo's own correctness rigour, beyond anything 42 checks:
#            diff, diff_asan, asan, allocfail
#
# complete = also portability (ilp32) and cost (perf, cycles). Everything.
gate_tags() {
	case "$1" in
		basic | strict | robust) echo "lvl_$1,-manual" ;;
		complete | all)          echo "-manual" ;;
		*)                       return 1 ;;
	esac
}

# Personal default, in order: SUBMIT_GATE, then the .submit-level file, then
# basic. The file is optional; without one the gate is `basic`, which is the
# level the Moulinette actually grades, so nobody inherits someone else's
# stricter personal bar by cloning.
#
# Write one (a single word: basic, strict, robust or complete) and COMMIT it if
# you want a stricter standard to survive a new shell and follow you to every
# machine you clone this to. That is deliberately the opposite of .bazelrc.local,
# which is per-machine and gitignored.
_level_file="$(dirname "$0")/../.submit-level"
[ -f "$_level_file" ] || _level_file="${BUILD_WORKSPACE_DIRECTORY:-.}/.submit-level"
if [ -z "${SUBMIT_GATE:-}" ] && [ -f "$_level_file" ]; then
	SUBMIT_GATE=$(tr -d " \t\n\r" < "$_level_file")
fi
GATE_LEVEL="${SUBMIT_GATE:-basic}"
BRANCH=master
MSG="Piscine submission"
ONLY=""
# Which of the names in $ONLY actually turned out to be table rows. A name that
# matches none of them used to filter everything out before any counter moved,
# so `bazel run //tools:submit -- c-piscine-c-O0` (letter O for zero) printed the
# summary and exited 0 -- indistinguishable from a submission that worked.
MATCHED=""

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "submit.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		-n|--dry-run) DRY=1; shift ;;
		-f|--force) FORCE=1; shift ;;
		--no-gate) GATE=0; shift ;;
		--gate-level) need "$1" "$#"; GATE_LEVEL="$2"; shift 2 ;;
		-b|--branch) need "$1" "$#"; BRANCH="$2"; shift 2 ;;
		-m|--message) need "$1" "$#"; MSG="$2"; shift 2 ;;
		-h|--help) show_help; exit 0 ;;
		--) shift; break ;;
		-*) echo "submit.sh: unknown option: $1" >&2; exit 2 ;;
		*) ONLY="$ONLY $1"; shift ;;
	esac
done

# Reject an unknown level rather than letting it become an empty tag filter,
# which Bazel reads as "no filter" — i.e. silently gating on everything, the
# opposite of what someone lowering the level was asking for.
if ! gate_tags "$GATE_LEVEL" >/dev/null 2>&1; then
	echo "submit.sh: unknown gate level '$GATE_LEVEL'" >&2
	echo "           valid levels, each also running the ones listed before it:" >&2
	echo "             basic     norm, compile, output, files, forbidden," >&2
	echo "                       prototype — what the Moulinette grades (default)" >&2
	echo "             strict    + symbols, valgrind" >&2
	echo "             robust    + diff, diff_asan, asan, allocfail" >&2
	echo "             complete  + ilp32, perf, cycles — everything this repo has" >&2
	echo "             all       a synonym for complete" >&2
	echo "           set it per-user with:  export SUBMIT_GATE=complete" >&2
	exit 2
fi
for arg in "$@"; do ONLY="$ONLY $arg"; done

# Safety net: never let git's upward repo-discovery escape to the OUTER repo. If a
# module's deliverable/.git is missing (e.g. init failed), an unguarded
# `git -C deliverable` would otherwise walk up and operate on this repo's own .git.
export GIT_CEILING_DIRECTORIES="$PWD"

# Commit identity: your 42 login/email, from the SAME place the kube.42header VS
# Code extension uses — the "42header.username"/"42header.email" keys in
# .vscode/settings.json. Override per run with LOGIN42=... EMAIL42=... .
read_42() {
	sed -n "s/.*\"42header.$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
		.vscode/settings.json 2>/dev/null | head -1
}
LOGIN42="${LOGIN42:-$(read_42 username)}"
EMAIL42="${EMAIL42:-$(read_42 email)}"
if [ -z "$LOGIN42" ] || [ -z "$EMAIL42" ]; then
	echo "submit.sh: no 42 identity found in .vscode/settings.json." >&2
	echo "           Run:  bazel run //tools:init" >&2
	exit 1
fi

# A SEPARATE Bazel output base for the gate: a `bazel run` holds the output-base
# lock for its whole run, so a nested `bazel test` on the SAME base would deadlock.
GATE_BASE="${SUBMIT_GATE_OUTPUT_BASE:-$HOME/.cache/_bazel_submit_gate}"

# ---- SSH-key onboarding helpers --------------------------------------------

# Classify a failed push from its captured stderr. auth = the server answered but
# rejected the key (auto-remediable); conn = the server was unreachable (EXPECTED
# off campus — Vogsphere is campus-only); other = anything else.
classify_push_error() {
	f=$1
	# Auth = the server ANSWERED but rejected the key. Note: "could not read from
	# remote repository" is deliberately NOT here — git prints that trailer for
	# connectivity failures too, which would misclassify an off-campus timeout.
	if grep -qiE 'permission denied \(publickey|denied \(publickey|publickey\)|host key verification failed|too many authentication failures|authentication failed|sign_and_send_pubkey|unprotected private key|access denied|repository not found' "$f"; then
		echo auth
	elif grep -qiE 'could not resolve|name or service not known|temporary failure in name resolution|connection timed out|operation timed out|timed out|connection refused|network is unreachable|no route to host|connection reset|connection closed|kex_exchange_identification|broken pipe' "$f"; then
		echo conn
	else
		echo other
	fi
}

# Print the path to an SSH public key, creating one ONLY if none exists (never
# clobbering an existing key).
ensure_ssh_key() {
	mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" 2>/dev/null
	for k in id_ed25519 id_rsa id_ecdsa id_dsa; do
		if [ -f "$HOME/.ssh/$k.pub" ]; then
			printf '%s\n' "$HOME/.ssh/$k.pub"
			return 0
		fi
	done
	if ssh-keygen -t ed25519 -N '' -C "$EMAIL42" -f "$HOME/.ssh/id_ed25519" -q 2>/dev/null; then
		printf '%s\n' "$HOME/.ssh/id_ed25519.pub"
		return 0
	fi
	if ssh-keygen -t rsa -b 4096 -N '' -C "$EMAIL42" -f "$HOME/.ssh/id_rsa" -q 2>/dev/null; then
		printf '%s\n' "$HOME/.ssh/id_rsa.pub"
		return 0
	fi
	return 1
}

# Add the remote's host key to known_hosts (fixes "Host key verification failed").
remediate_host_key() {
	host=${1#*@}
	host=${host#ssh://}
	host=${host%%/*}
	host=${host%%:*}
	[ -n "$host" ] && ssh-keyscan -H "$host" >> "$HOME/.ssh/known_hosts" 2>/dev/null
}

# Run a module's Bazel tests on the separate output base. 0 = green.
#
# The caller must look at the STATUS, not just at its zero-ness. Bazel reserves 3
# for "the tests ran and some failed"; every other non-zero means the tests never
# ran at all (1 = build or analysis error, 2 = bad command line, 4 = the filter
# matched no test, 36 = a transient local-environment problem, 37 = an internal
# bazel error). Reporting those as "your tests are failing" sends a student off to
# debug code that may be perfect, while the real fault — a typo in a BUILD file, a
# sick server on the gate's own output base — goes unmentioned. So stderr is
# CAPTURED rather than discarded: in that case it is the only evidence there is.
GATE_ERR=""
run_gate() {
	# Probed HERE rather than in `require`, because --no-gate is a legitimate
	# run that needs no bazel at all. Without this a missing bazel surfaces as
	# "Bazel exited 127", which reads as a test failure and blocks the module.
	if ! command -v bazel > /dev/null 2>&1; then
		printf '     bazel is not on PATH, so the gate could not run.\n' >&2
		printf '     Install it, or re-run with --no-gate if you accept the risk.\n' >&2
		return 2
	fi
	GATE_ERR=$(mktemp)
	bazel --output_base="$GATE_BASE" test "//$1/..." \
		--test_tag_filters="$(gate_tags "$GATE_LEVEL")" --keep_going \
		>/dev/null 2>"$GATE_ERR"
}

# Everything the gate did NOT cover, reported but never blocking. A student who
# gates at `basic` should still be told the differential or the sanitizer is
# unhappy — they just should not be stopped from submitting over it.
# At `complete` (and `all`) the gate filter is already -manual, so there is no
# layer ABOVE the gate to advise about. Return success — "nothing to report".
#
# This was written as `[ A ] || [ B ] && return 1`, which sh parses as
# `(A || B) && return 1`: at complete the function returned 1 having run
# nothing, the caller read that as "advisory layers are red", and every module
# of every submit printed a warning that was false by construction.
run_advisory() {
	case "$GATE_LEVEL" in
		complete | all) return 0 ;;
	esac
	bazel --output_base="$GATE_BASE" test "//$1/..." \
		--test_tag_filters=-manual --keep_going >/dev/null 2>&1
}

wanted() {
	[ -z "$ONLY" ] && return 0
	for w in $ONLY; do
		if [ "$w" = "$1" ]; then
			MATCHED="$MATCHED $w"
			return 0
		fi
	done
	return 1
}

OK=0
FAIL=0
SKIPPED=0

# $@ is the git push argv; runs in $dir. Uses $mod, $url, $dir from the caller.
push_with_onboarding() {
	err=$(mktemp)
	if git -C "$dir" "$@" </dev/null 2>"$err"; then
		cat "$err" >&2; rm -f "$err"
		OK=$((OK + 1)); return 0
	fi
	cat "$err" >&2
	case "$(classify_push_error "$err")" in
		conn)
			rm -f "$err"
			printf '     push could not REACH the server (DNS/timeout/refused).\n'
			printf '     This is EXPECTED off campus — Vogsphere is only reachable from a 42\n'
			printf '     campus machine. Your SSH key was NOT touched. Re-run this on campus.\n'
			FAIL=$((FAIL + 1)); return 0 ;;
		auth)
			rm -f "$err"
			printf '     push was REJECTED for SSH-KEY reasons (the server answered but does\n'
			printf '     not recognise your key).\n'
			remediate_host_key "$url"
			pub=$(ensure_ssh_key) || {
				printf '     ERROR: could not find or create an SSH key automatically.\n'
				FAIL=$((FAIL + 1)); return 0; }
			printf '\n     Copy this PUBLIC key into your 42 intranet profile\n'
			printf '       (intra.42.fr -> Settings -> "SSH Keys"), then keep this terminal:\n\n'
			printf '%s\n\n' "$(cat "$pub")"
			printf '     Retrying the push once...\n'
			err2=$(mktemp)
			if git -C "$dir" "$@" </dev/null 2>"$err2"; then
				cat "$err2" >&2; rm -f "$err2"
				printf '     push SUCCEEDED after the key fix.\n'
				OK=$((OK + 1)); return 0
			fi
			cat "$err2" >&2; rm -f "$err2"
			printf '     push STILL failing. Make sure you SAVED the key on the intranet\n'
			printf '     (it can take a moment to propagate), then re-run (add -f if\n'
			printf '     re-submitting).\n'
			FAIL=$((FAIL + 1)); return 0 ;;
		*)
			rm -f "$err"
			printf '     push FAILED for %s.\n' "$mod"
			printf '     (re-submitting? the re-init creates new history — retry with -f to force.)\n'
			FAIL=$((FAIL + 1)); return 0 ;;
	esac
}

submit() {
	mod=$1
	url=$2
	wanted "$mod" || return 0
	case "$mod" in
		*/* | .. | . | "")
			printf 'SKIP  bad module name: %s\n' "$mod"
			SKIPPED=$((SKIPPED + 1)); return 0 ;;
	esac
	if [ -z "$url" ] || [ "$url" = REPLACE_ME ]; then
		printf 'SKIP  %-20s  (no remote set in table)\n' "$mod"
		SKIPPED=$((SKIPPED + 1)); return 0
	fi

	dir="$mod/deliverable"
	is_shell=0
	case "$mod" in *shell*) is_shell=1 ;; esac

	printf '\n==>  %-20s  ->  %s\n' "$mod" "$url"

	if [ "$DRY" = 1 ]; then
		[ "$is_shell" = 1 ] && printf '     dry-run: would regenerate %s from generators/\n' "$dir"
		[ "$GATE" = 1 ] && printf '     dry-run: would gate on  bazel test //%s/... --test_tag_filters=%s  (level: %s; skip if red)\n' \
			"$mod" "$(gate_tags "$GATE_LEVEL")" "$GATE_LEVEL"
		printf '     dry-run: rm -rf %s/.git; git init; add; commit; push%s\n' \
			"$dir" "$( [ "$FORCE" = 1 ] && echo ' --force' )"
		return 0
	fi

	# 1. Gate on the module's tests.
	if [ "$GATE" = 1 ]; then
		printf '     gate: bazel test //%s/... (level: %s)\n' "$mod" "$GATE_LEVEL"
		run_gate "$mod"
		gate_status=$?
		if [ "$gate_status" -ne 0 ]; then
			# Hand over the command the gate ACTUALLY ran — including
			# --keep_going, or the re-run stops at the first failure and shows
			# FEWER reds than the gate saw. "bazel test //mod/..." is the obvious
			# advice and the misleading one: it is a different output base with no
			# tag filter, so it can come back green on the very module the gate
			# just stopped, and the student concludes the submit script is broken.
			gate_cmd="bazel --output_base=$GATE_BASE test //$mod/... --test_tag_filters=$(gate_tags "$GATE_LEVEL") --keep_going"
			if [ "$gate_status" -eq 3 ]; then
				printf '     BLOCKED: tests are FAILING — not pushed. See which, with:\n'
				printf '                %s\n' "$gate_cmd"
				printf '              Then fix them, or bypass the gate with --no-gate.\n'
			else
				printf '     BLOCKED: the gate could not RUN — not pushed. Bazel exited %d, and\n' "$gate_status"
				printf '              only 3 means "tests failed" (1 = build or analysis error,\n'
				printf '              2 = bad command line, 4 = the level matched no test at\n'
				printf '              all, 36/37 = a transient local-environment problem or an\n'
				printf '              internal bazel error). So this is NOT a verdict on your\n'
				printf '              code — and --no-gate would push work that nothing has\n'
				printf '              checked. Bazel'\''s last words:\n'
				if [ -s "$GATE_ERR" ]; then
					tail -n 15 "$GATE_ERR" | sed 's/^/              | /'
				else
					printf '              | (bazel printed nothing to stderr)\n'
				fi
				printf '              Reproduce with:\n'
				printf '                %s\n' "$gate_cmd"
			fi
			rm -f "$GATE_ERR"
			FAIL=$((FAIL + 1)); return 0
		fi
		rm -f "$GATE_ERR"
		if ! run_advisory "$mod"; then
			# Same reason the BLOCKED branch above quotes its own command: a bare
			# `bazel test //mod/...` is a DIFFERENT output base, so it can come
			# back green on exactly what the advisory pass just found red.
			printf '     NOTE: layers above the "%s" gate are red for this module.\n' "$GATE_LEVEL"
			printf '           Not blocking — the Moulinette does not grade them — but worth\n'
			printf '           a look:\n'
			printf '             bazel --output_base=%s test //%s/... --test_tag_filters=-manual --keep_going\n' \
				"$GATE_BASE" "$mod"
		fi
	fi

	# 2. Shell modules: (re)generate the disposable deliverable/ from generators/.
	if [ "$is_shell" = 1 ]; then
		sh tools/generate.sh "$mod" >/dev/null || {
			printf '     ERROR: could not regenerate %s\n' "$dir"
			FAIL=$((FAIL + 1)); return 0; }
	fi

	if [ ! -d "$dir" ]; then
		printf '     SKIP: no %s\n' "$dir"
		SKIPPED=$((SKIPPED + 1)); return 0
	fi

	# 3. Re-init the submission repo and push.
	rm -rf "$dir/.git"
	if ! git -C "$dir" init -q; then
		printf '     git init failed for %s — skipped\n' "$mod"
		FAIL=$((FAIL + 1)); return 0
	fi
	git -C "$dir" symbolic-ref HEAD "refs/heads/$BRANCH"
	git -C "$dir" config core.filemode true
	# --force and an empty excludesFile, so no IGNORE rule can drop a turn-in
	# file. `git add -A` honours them, and two are reachable here: a .gitignore
	# committed inside deliverable/, and the owner's global core.excludesFile.
	# Either would omit a required source from the pushed repo while every local
	# layer stayed green, because the layers read the working tree.
	#
	# The ':(exclude)' pathspecs are NOT ignore rules and still apply -- build
	# products stay out. They are extension-based, though, so a compiled binary
	# named by its subject (bsq, rush-02) is not covered; the check below is.
	git -C "$dir" -c core.excludesFile=/dev/null add -A --force -- . \
		':(exclude)*.o' ':(exclude)*.a' ':(exclude)*.out' ':(exclude)*.gch'
	if git -C "$dir" diff --cached --quiet; then
		printf '     nothing to commit (empty deliverable?) — skipped\n'
		SKIPPED=$((SKIPPED + 1)); return 0
	fi
	# Checked. An unchecked commit falls through to `remote add` and `push`,
	# and the push then fails with "src refspec master does not match any" --
	# which the classifier below reads as `other` and reports as "retry", for a
	# commit that never happened.
	if ! git -C "$dir" -c user.name="$LOGIN42" -c user.email="$EMAIL42" \
			commit -q -m "$MSG"; then
		printf '     git commit failed for %s — not pushed\n' "$mod"
		FAIL=$((FAIL + 1)); return 0
	fi
	git -C "$dir" remote add origin "$url"
	if [ "$FORCE" = 1 ]; then
		set -- push -u --force origin "$BRANCH"
	else
		set -- push -u origin "$BRANCH"
	fi
	push_with_onboarding "$@"
}

# Read the table a LINE at a time, not with `for entry in $REMOTES`.
#
# That loop word-split on IFS, so a line commented out the way anyone would
# comment one out -- "# c-piscine-c-00=git@..." -- became TWO words: a bare "#",
# which the guard skipped, and the entry itself, which was pushed. The one
# gesture a person makes to disable a module was the one that did not work.
#
# docs/submitting.md compounded it by showing an example line with a trailing
# "# comment", which under word-splitting became four more phantom modules,
# each running a gate and each counted in the summary.
# A here-doc, NOT a pipe: `printf ... | while` runs the loop in a subshell, so
# every OK/FAIL/SKIPPED increment inside it would be discarded and the summary
# line would report zeros after a real run.
while IFS= read -r entry; do
	case "$entry" in
		"" | \#*) continue ;;
	esac
	# An entry with no "=" is not a table row. ${entry#*=} returns the string
	# UNCHANGED when there is no match, so "c-piscine-c-00 = git@..." (spaces
	# around the =) yielded a module whose remote was its own name -- not
	# REPLACE_ME, therefore treated as live, and pushed to a URL that is a
	# module name.
	case "$entry" in
		*=*) ;;
		*)
			printf 'SKIP  malformed table line (no "="): %s\n' "$entry"
			continue ;;
	esac
	# An inline comment ends the entry. docs/submitting.md shows a table line
	# written exactly this way -- "c-piscine-c-01=REPLACE_ME   # skipped" -- and
	# without this the whole tail becomes part of the URL, so the row stops
	# reading as REPLACE_ME and is treated as a LIVE remote pointing at prose.
	# Only " #" counts, never a bare '#', because that is what a comment looks
	# like and a URL does not contain one.
	entry=$(printf '%s' "$entry" | sed 's/[[:space:]]#.*$//')
	mod=${entry%%=*}
	url=${entry#*=}
	# Trim blanks around both halves. This table is hand-edited, and
	# "c-piscine-c-01 = git@..." is how a person writes one -- which produced a
	# module named "c-piscine-c-01 " (trailing space) pointed at a URL with a
	# leading space, and then a directory that does not exist. Being liberal
	# about the spacing costs one sed and removes a whole class of confusing
	# "SKIP: no c-piscine-c-01 /deliverable" reports.
	mod=$(printf '%s' "$mod" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
	url=$(printf '%s' "$url" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
	[ -n "$mod" ] && submit "$mod" "$url"
done <<TABLE
$REMOTES
TABLE

# A name that matched no table row is an error, not a quiet no-op. It is almost
# always a typo, and the shape of the mistake -- "it printed the summary and
# exited 0" -- is exactly the shape of a successful run.
UNMATCHED=""
for w in $ONLY; do
	case " $MATCHED " in
		*" $w "*) ;;
		*) UNMATCHED="$UNMATCHED $w" ;;
	esac
done

printf '\n----\nDone: %d pushed, %d failed/blocked, %d skipped.' "$OK" "$FAIL" "$SKIPPED"
[ "$DRY" = 1 ] && printf '  (dry-run)'
printf '\n'
if [ -n "$UNMATCHED" ]; then
	printf '\nNOT A MODULE IN THE TABLE:%s\n' "$UNMATCHED" >&2
	printf 'Nothing was pushed for it. The table is the REMOTES block near the top\n' >&2
	printf 'of this script; a module absent from it is invisible here, not skipped.\n' >&2
	exit 1
fi
[ "$FAIL" -eq 0 ]
