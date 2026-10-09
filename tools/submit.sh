#!/bin/sh
# submit.sh — test, then push each module's deliverable/ to its 42 (Vogsphere) repo.
#
# Run with Bazel (the single entry point):
#     bazel run //tools:submit                     # every module with a remote set
#     bazel run //tools:submit -- c-piscine-c-00   # only the listed module(s): the
#                                                  # project's name, or its path
#                                                  # (c-piscine/c-piscine-c-00)
#     bazel run //tools:submit -- -n               # dry-run: show what would happen,
#                                                  # and list the files it would push
#     bazel run //tools:submit -- --no-gate        # skip the pre-push test gate
#
# Your Vogsphere URLs go in .submit-remotes at the repo root, one KEY=URL line
# per module, KEY being the module's path (c-piscine/c-piscine-c-00) or its
# project name alone (c-piscine-c-00). A module with no URL there is skipped.
# The REMOTES table below is the list of modules and never needs editing.
#
# For each module with a URL, submit:
#   1. runs that module's Bazel tests as a GATE — a module with failing tests is
#      reported BLOCKED and is NOT pushed;
#   2. (generator modules) regenerates deliverable/ from generators/;
#   3. fetches the remote, commits deliverable/ AS IT IS ON DISK on top of what
#      the remote already holds, and pushes. Never with --force: a re-submit is
#      an ordinary push, and what a teammate pushed to a group repository stays
#      in its history (a NOTE names what your push changes on its tip). What
#      exactly is pushed: see stage_deliverable below, or docs/submitting.md
#      ("What gets pushed").
#
# How much has to be green before a module is pushed is one of the four
# levels, basic to complete, each running everything below it too; "all" is a
# synonym for complete. docs/reference.md ("The four levels", "The layers") says
# what each one means and runs. Pick a level for ONE run with --gate-level
# LEVEL. Make it permanent by exporting SUBMIT_GATE=LEVEL from your shell
# profile (yours alone, on this machine), or by writing the level into a
# .submit-level file at the repo root, which is not gitignored and so follows
# the repo to every machine you clone it to. With no such file the gate is
# `basic`. An unknown level is an error, and lists the levels with the layers
# each one runs, read from docs/reference.md.
#
# Other options: -b/--branch B (default master), -m/--message M, -h/--help.
#
# Usage:
#   bazel run //tools:submit [-- MODULE...] [--gate-level LEVEL] [--no-gate]
#
#   MODULE          which module(s) to push, by the table's path or by the
#                   project's name alone; all configured if none
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
require awk cat chmod dirname git grep head mkdir mktemp od rm sed sort tail tr

# Repo root: from `bazel run` it's BUILD_WORKSPACE_DIRECTORY; run directly it's the
# parent of tools/.
WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$WS" || exit 1

# ============================================================================
# REMOTES TABLE — every module this script can push, as a path from the repo
# root. It is ALSO the repo's module registry (conventions.sh counts these keys),
# so it is shared, tracked harness: your URLs do not go here but in
# .submit-remotes, one KEY=URL line each, which overrides the REPLACE_ME below.
# Not here: a URL is a per-student identifier (an intra UUID and a login), and
# this is a harness file that every copy of tools/ overwrites.
# "REPLACE_ME" means "not set yet" and is skipped.
# ============================================================================
REMOTES='
c-piscine/c-piscine-c-00=REPLACE_ME
c-piscine/c-piscine-c-01=REPLACE_ME
c-piscine/c-piscine-c-02=REPLACE_ME
c-piscine/c-piscine-c-03=REPLACE_ME
c-piscine/c-piscine-c-04=REPLACE_ME
c-piscine/c-piscine-c-05=REPLACE_ME
c-piscine/c-piscine-c-06=REPLACE_ME
c-piscine/c-piscine-c-07=REPLACE_ME
c-piscine/c-piscine-c-08=REPLACE_ME
c-piscine/c-piscine-c-09=REPLACE_ME
c-piscine/c-piscine-c-10=REPLACE_ME
c-piscine/c-piscine-c-11=REPLACE_ME
c-piscine/c-piscine-c-12=REPLACE_ME
c-piscine/c-piscine-c-13=REPLACE_ME
c-piscine/c-piscine-rush-00=REPLACE_ME
c-piscine/c-piscine-rush-01=REPLACE_ME
c-piscine/c-piscine-rush-02=REPLACE_ME
c-piscine/c-piscine-bsq=REPLACE_ME
c-piscine/c-piscine-shell-00=REPLACE_ME
c-piscine/c-piscine-shell-01=REPLACE_ME
c-piscine-reloaded/c-piscine-reloaded=REPLACE_ME
'

show_help() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

DRY=0
GATE=1
# Which layers must be green before a module is pushed.
#
# `basic` -- every layer whose failure is a KO wherever the project is graded,
# at the Moulinette or at a defense -- is the
# DEFAULT here, so this suite never refuses to push work that would score fine.
# The levels above it are worth knowing about, but "not as rigorous as I would
# like" is not the same verdict as "not gradeable" and should not block a
# submission for someone who did not opt in.
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
# -manual at every level, though it is not what keeps a manual test out: the
# gate runs //<module>/..., and a /... pattern never reaches one (Bazel's
# wildcard leaves it out; `manual` in a filter's include list is ignored). It
# says the same thing twice so that an exercise's opt-in targets (rush's bonus
# variants, docs/reference.md's "Manual targets") could not block a push even
# if a gate named a target.
#
# Which layer sits at which level, and why, is not repeated here: the level is
# _LAYER_LEVEL's in tools/defs.bzl, with the reason beside each entry, and
# docs/reference.md is the one written copy, checked against it. This file used
# to carry a third, which lost allocfail from its level; //tools:conventions now
# refuses a copy anywhere else.
gate_tags() {
	case "$1" in
		basic | strict | robust) echo "lvl_$1,-manual" ;;
		complete | all)          echo "-manual" ;;
		*)                       return 1 ;;
	esac
}

# Personal default, in order: SUBMIT_GATE, then the .submit-level file, then
# basic. The file is optional; without one the gate is `basic`, which is the
# level the grader actually KOs on, so nobody inherits someone else's
# stricter personal bar by cloning.
#
# Write one (a single word: basic, strict, robust or complete) and COMMIT it if
# you want a stricter standard to survive a new shell and follow you to every
# machine you clone this to. That is deliberately the opposite of .bazelrc.local,
# which is per-checkout and gitignored.
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

# A module named on the command line, as the table spells it. Tab completion
# writes a directory with a trailing '/', and since the modules moved under a
# course folder (c-piscine/c-piscine-c-00) the completed form is the one people
# type -- and an exact string compare against the table then said "NOT A MODULE
# IN THE TABLE" about a module that is in it.
norm_arg() { printf '%s' "$1" | sed 's:/*$::'; }
# ...and a name that normalises to nothing ("", "/") is a usage error, not a
# filter that silently matches no row and exits 0.
add_only() {
	_a=$(norm_arg "$1")
	[ -n "$_a" ] || { echo "submit.sh: empty module name: '$1'" >&2; exit 2; }
	ONLY="$ONLY $_a"
}

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "submit.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		-n|--dry-run) DRY=1; shift ;;
		# Refused rather than ignored, so nobody believes they forced
		# something. Every submit builds on the remote's history, so a
		# re-submit never needs it -- and on a group repository, forcing would
		# replace whatever a teammate pushed.
		-f|--force)
			echo "submit.sh: -f is gone: submit never force-pushes." >&2
			echo "  Each submit commits on top of what the Vogsphere repository already" >&2
			echo "  holds, so a re-submit is an ordinary push, and what a teammate pushed" >&2
			echo "  to a group repository stays in its history. Run it again without -f." >&2
			exit 2 ;;
		--no-gate) GATE=0; shift ;;
		--gate-level) need "$1" "$#"; GATE_LEVEL="$2"; shift 2 ;;
		-b|--branch) need "$1" "$#"; BRANCH="$2"; shift 2 ;;
		-m|--message) need "$1" "$#"; MSG="$2"; shift 2 ;;
		-h|--help) show_help; exit 0 ;;
		--) shift; break ;;
		-*) echo "submit.sh: unknown option: $1" >&2; exit 2 ;;
		*) add_only "$1"; shift ;;
	esac
done

# The levels and the layers each one adds, read from docs/reference.md's layer
# table when it asks for them -- the one place the ladder is written down -- so
# this help cannot drift from it. oracle and selftest are left out: they live
# outside every module, where no gate reaches. With no table to read, the level
# names alone.
print_ladder() {
	_ladder=$(awk -F'|' '
		/^\| `[a-z0-9_]+` \| (basic|strict|robust|complete) \|/ {
			t = $2; gsub(/[ `]/, "", t); l = $3; gsub(/ /, "", l)
			if (t == "oracle" || t == "selftest") next
			L[l] = L[l] (L[l] == "" ? "" : ", ") t
		}
		END {
			n = split("basic strict robust complete", o, " ")
			for (i = 1; i <= n; i++)
				if (o[i] in L)
					printf "             %-9s %s%s\n", o[i], (i > 1 ? "+ " : ""), L[o[i]]
		}' docs/reference.md 2> /dev/null)
	if [ -n "$_ladder" ]; then
		printf '%s\n' "$_ladder"
	else
		echo "             basic, strict, robust, complete"
	fi
}

# Reject an unknown level rather than letting it become an empty tag filter,
# which Bazel reads as "no filter" — i.e. silently gating on everything, the
# opposite of what someone lowering the level was asking for.
if ! gate_tags "$GATE_LEVEL" >/dev/null 2>&1; then
	echo "submit.sh: unknown gate level '$GATE_LEVEL'" >&2
	echo "           valid levels, each also running the ones listed before it" >&2
	echo "           (basic is the default, and all is a synonym for complete):" >&2
	print_ladder >&2
	echo "           What each one means: docs/reference.md, \"The four levels\"." >&2
	echo "           set it per-user with:  export SUBMIT_GATE=complete" >&2
	exit 2
fi
for arg in "$@"; do add_only "$arg"; done

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

# THE GATE RUNS BAZEL AS YOU WOULD TYPE IT: the same output base as every
# `bazel test` you ran before submitting, with no startup option of its own.
# It had an output base of its own, on the belief that `bazel run` holds the
# main one's lock while the program it started runs, so that a `bazel test`
# inside it would deadlock. It holds none: the server lets go before the
# program starts (a toy on Bazel 9.2.0: a plain `bazel test`, and a `bazel
# shutdown` too, inside `bazel run` came back at once). And the `bazel` this
# script finds is the one a prompt finds, tools/bazel first on PATH (that
# script's header, HOW IT IS RUN). The second base cost a second server -- a
# JVM, on an 8 GB campus box -- and a second build of everything.
#
# BUT IT TRUSTS NOTHING THAT SERVER REMEMBERS. A file saved while a test ran
# can leave a result cached for the file's other contents -- a PASS, or even a
# compiled program -- and a later run serves it again (HISTORY.md, V111). A
# watch loop that ran while you edited is exactly what leaves one, and a gate
# that read it would push code its own tests fail. The full repair
# docs/testing.md gives is a `bazel shutdown`, then a run with
# --nocache_test_results and --use_action_cache=false, so the gate makes it:
# before its first module it shuts the server down -- a command still running
# on it finishes first -- and every gate runs with both flags. The module's
# tests are built and run again, which takes longer than a cached run. The
# advisory pass after it is a note, not a gate, and runs as you would type it.
GATE_FRESH=0
GATE_FLAGS="--keep_going --nocache_test_results --use_action_cache=false"

# ---- SSH-key onboarding helpers --------------------------------------------

# Classify a failed fetch or push from its captured stderr. auth = the server
# answered but rejected the key (the host key is fixed here; the student's own key
# is shown to them for registering, never created); conn = the server was
# unreachable (EXPECTED off campus — Vogsphere is campus-only); behind = the push
# was refused because the remote moved on since the fetch; other = anything else.
classify_push_error() {
	f=$1
	# First: a refused push can also say "failed to push some refs", which
	# is no network word, but it must never read as `other` and send the
	# student looking for a flag to force it.
	if grep -qiE '\[rejected\]|non-fast-forward|fetch first|stale info' "$f"; then
		echo behind
		return
	fi
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

# Print the path to the student's existing SSH public key, or return 1 if there
# is none. It never CREATES one, and that is deliberate: making an SSH key pair
# is itself a Piscine exercise (shell-00 ex03), and a tool that does it for you
# is that exercise's answer sitting in the harness. The caller tells the student
# how to make one themselves.
#
# Only the default names are looked at, because those are the keys ssh offers
# without being told to: a key saved under another name would print fine here,
# get registered, and still not be the one the push authenticates with.
existing_ssh_key() {
	for k in id_ed25519 id_rsa id_ecdsa id_dsa; do
		if [ -f "$HOME/.ssh/$k.pub" ]; then
			printf '%s\n' "$HOME/.ssh/$k.pub"
			return 0
		fi
	done
	return 1
}

# Add the remote's host key to known_hosts (fixes "Host key verification failed").
# ~/.ssh is created first if it is missing, with the permissions ssh insists on,
# so the known_hosts line has somewhere to go even before any key exists.
remediate_host_key() {
	host=${1#*@}
	host=${host#ssh://}
	host=${host%%/*}
	host=${host%%:*}
	mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" 2>/dev/null
	[ -n "$host" ] && ssh-keyscan -H "$host" >> "$HOME/.ssh/known_hosts" 2>/dev/null
}

# Run a module's Bazel tests. 0 = green.
#
# The caller must look at the STATUS, not just at its zero-ness. Bazel reserves 3
# for "the tests ran and some failed", and 1 for a build or analysis error: under
# --keep_going the rest of the module still ran. Code of the student's that does
# not compile or link, or a turn-in file that is missing, is a 3 now: it fails
# its own tests (tools/student_build.sh, tools/no_turnin.sh), never the build.
# A 1 is the harness's -- a file of its own, a download that failed -- or a
# module older than that. Every other non-zero means the tests never ran at all (2 = bad command
# line, 4 = the filter matched no test, 36 = a transient local-environment
# problem, 37 = an internal bazel error). Reporting those as "your tests are
# failing" sends a student off to debug code that may be perfect, while the real
# fault — a typo in a BUILD file, a Bazel server in trouble —
# goes unmentioned. So stderr is CAPTURED rather than discarded: for 1 it holds
# the compiler's lines, and for the rest it is the only evidence there is.
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
	# No startup option: the output base is the one your own commands use. The
	# server is shut down once, before the first module, and every gate trusts
	# no cached result (BUT IT TRUSTS NOTHING THAT SERVER REMEMBERS, above). A
	# command already running on it goes first, and the line printed before
	# the gate says so. A shutdown that fails is not the gate's verdict: the
	# gate runs anyway, with both flags.
	if [ "$GATE_FRESH" = 0 ]; then
		GATE_FRESH=1
		bazel shutdown > /dev/null 2>&1 || :
	fi
	# shellcheck disable=SC2086 # GATE_FLAGS is several words, none of them quoted
	bazel test "//$1/..." \
		--test_tag_filters="$(gate_tags "$GATE_LEVEL")" $GATE_FLAGS \
		>/dev/null 2>"$GATE_ERR"
}

# The lines of the gate's stderr that tie a build error to the student's files:
# a compiler line naming a turn-in file, a turn-in file Bazel was told about and
# could not find, a compiler line in the test program built against them, or a
# linker line under the failed link of an exercise target (exNN_bin: only those
# link a turn-in). The same test tools/first_red.sh uses before it says DOES NOT
# BUILD. None of them means the build stopped somewhere else: a download that
# failed, or a harness file.
gate_own_lines() {
	[ -s "$GATE_ERR" ] || return 0
	awk '
		# A test log (--test_output=errors in a .bazelrc.local) is not the
		# build: a compile layer quotes the compiler there on a tree that builds.
		/^=+ Test output for / { intest = 1; next }
		intest && /^=+$/ { intest = 0; next }
		intest { next }
		/^ERROR: / { exlink = ($0 ~ /rule target \/\/[^ )]*:ex[0-9]+_/) }
		/deliverable\/[^ :]*:[0-9]+:/ && /error|multiple definition|undefined reference/ { print; next }
		/missing input file|not a declared prerequisite/ && /:deliverable\// { print; next }
		/\/tests\/ex[0-9]+\/[^ :]*:[0-9]+:/ && /error/ { print; next }
		/multiple definition of|undefined reference to|undefined symbol/ && exlink { print; next }
	' "$GATE_ERR"
}

# What the gate's files tests said, for a module they stopped: which files
# are missing, or would be pushed and should not be. The rule is theirs --
# the files layer, and the module's deliverable_files for what is outside
# every exercise folder -- and this is only their report, from the log each
# names on the gate's stderr ("FAIL: //mod:t (Exit 1) (see .../test.log)"), from its
# first table to its RESULT line. A file nobody asked for is the one red a
# student can fix without reading any code, so it is shown here, not left
# behind a command to run.
gate_files_reports() {
	[ -s "$GATE_ERR" ] || return 0
	sed -n "s#^FAIL: //$mod:\([A-Za-z0-9_]*files\) .*(see \(.*\))\$#\1 \2#p" "$GATE_ERR" |
		while read -r _ft _fl; do
			[ -f "$_fl" ] || continue
			printf '              %s:\n' "$_ft"
			sed -n '/^files_test:/,/RESULT:/p' "$_fl" | sed -e '1d' -e '/^[[:space:]]*$/d' |
				head -n 20 | sed 's/^/              /'
		done
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
# ADV_OUT holds what the advisory pass said, because a warning that cannot name
# the layer is a warning nobody acts on. Both streams used to go to /dev/null
# and the function returned a bare boolean, so the NOTE below could only say
# "something above the gate is red" -- about the one set of tests a student
# submitting at `basic` never otherwise hears about.
ADV_OUT=""
run_advisory() {
	case "$GATE_LEVEL" in
		complete | all) return 0 ;;
	esac
	[ -n "$ADV_OUT" ] || ADV_OUT=$(mktemp)
	bazel test "//$1/..." \
		--test_tag_filters=-manual --keep_going > "$ADV_OUT" 2>&1
}

# The failing TARGETS of that run, so the note names what is red rather than
# that something is. Bazel prints one `//target FAILED in …` line per failing
# test.
#
# Targets rather than layer names, which was the first attempt: a layer has to
# be recovered by stripping the target name, and the strip is wrong for every
# shape with a case in the middle -- exNN_diff_asan reads as "asan", and
# ex00_rush03_output as "rush03_output". A label is exact, and it is also the
# thing the reader can paste back into bazel.
advisory_failures() {
	[ -s "$ADV_OUT" ] || return 0
	sed -n 's|^\(//[^ ]*\) *FAILED.*|\1|p' "$ADV_OUT" | sort -u
}

wanted() {
	[ -z "$ONLY" ] && return 0
	_hit=1
	for w in $ONLY; do
		# The full path from the table, or the project's own name: each project
		# folder is named exactly as 42 names the project, so
		# `submit -- c-piscine-c-00` still means c-piscine/c-piscine-c-00.
		# Every spelling that matches is recorded, not only the first, or naming
		# one module both ways would report the second as NOT A MODULE.
		if [ "$w" = "$1" ] || [ "$w" = "${1##*/}" ]; then
			MATCHED="$MATCHED $w"
			_hit=0
		fi
	done
	return $_hit
}

OK=0
FAIL=0
SKIPPED=0

# $@ is a git argv that talks to the remote (the fetch, then the push); runs in
# $dir. 0 = it worked. Otherwise it has said why, and the caller counts the
# failure. Uses $mod, $url, $dir from the caller. The fetch is the first contact
# with the server, so it is the one that meets a missing key or an off-campus
# network, and it gets the same onboarding the push always had.
remote_git() {
	_what=$1
	err=$(mktemp)
	if git -C "$dir" "$@" </dev/null 2>"$err"; then
		cat "$err" >&2; rm -f "$err"
		return 0
	fi
	cat "$err" >&2
	case "$(classify_push_error "$err")" in
		conn)
			rm -f "$err"
			printf '     %s could not REACH the server (DNS/timeout/refused).\n' "$_what"
			printf '     This is EXPECTED off campus — Vogsphere is only reachable from a 42\n'
			printf '     campus machine. Your SSH key was NOT touched. Re-run this on campus.\n'
			return 1 ;;
		auth)
			rm -f "$err"
			printf '     %s was REJECTED for SSH-KEY reasons (the server answered but does\n' "$_what"
			printf '     not recognise your key).\n'
			remediate_host_key "$url"
			pub=$(existing_ssh_key) || {
				printf '     You have no SSH key yet (no ~/.ssh/id_*.pub under a default\n'
				printf '     name), so there is nothing to register. This tool will not\n'
				printf '     make one for you: creating an SSH key pair is your own work\n'
				printf '     (man ssh-keygen, and your c-piscine-shell-00 ex03). Create one\n'
				printf '     under a default name, add its PUBLIC half to your 42 intranet\n'
				printf '     profile (intra.42.fr -> Settings -> "SSH Keys"), then re-run.\n'
				return 1; }
			printf '\n     Copy this PUBLIC key into your 42 intranet profile\n'
			printf '       (intra.42.fr -> Settings -> "SSH Keys"), then keep this terminal:\n\n'
			printf '%s\n\n' "$(cat "$pub")"
			printf '     Retrying the %s once...\n' "$_what"
			err2=$(mktemp)
			if git -C "$dir" "$@" </dev/null 2>"$err2"; then
				cat "$err2" >&2; rm -f "$err2"
				printf '     %s SUCCEEDED after the key fix.\n' "$_what"
				return 0
			fi
			cat "$err2" >&2; rm -f "$err2"
			printf '     %s STILL failing. Make sure you SAVED the key on the intranet\n' "$_what"
			printf '     (it can take a moment to propagate), then re-run.\n'
			return 1 ;;
		behind)
			rm -f "$err"
			printf '     push REJECTED: the repository moved on after the fetch above --\n'
			printf '     someone (a teammate?) pushed to it in between. Run submit again: it\n'
			printf '     fetches again and builds on top of what they pushed. It never\n'
			printf '     forces, because forcing would erase their work.\n'
			return 1 ;;
		*)
			rm -f "$err"
			printf '     %s FAILED for %s (git'\''s own words are above).\n' "$_what" "$mod"
			return 1 ;;
	esac
}

# The ONE place that decides what is pushed: deliverable/ as it is on disk.
# Not what you committed -- your own commits play no part -- and ignored files
# included: --force and an empty excludesFile, so no IGNORE rule can drop a
# turn-in file. `git add -A` honours them, and two are reachable here: a
# .gitignore committed inside deliverable/, and the owner's global
# core.excludesFile. Either would omit a required source from the pushed repo
# while every local layer stayed green, because the layers read the working tree.
#
# The ':(exclude)' pathspecs are NOT ignore rules and still apply -- build
# products stay out. They are extension-based, though, so a compiled program
# (bsq, rush-02, an a.out renamed) would be pushed if it were there, and
# built_programs below refuses the module instead.
#
# "$@" picks the index: nothing for deliverable/.git, or
# --git-dir=D --work-tree=. for the dry run's scratch one, so the list -n
# prints and the push cannot disagree.
stage_deliverable() {
	git -C "$dir" "$@" -c core.excludesFile=/dev/null add -A --force -- . \
		':(exclude)*.o' ':(exclude)*.a' ':(exclude)*.out' ':(exclude)*.gch'
}

# The files stage_deliverable stages, one per line, from a scratch index, so
# nothing about the deliverable changes: what the dry run lists and what
# built_programs reads are the push's own list. Fails when git does.
#
# Each name exactly as it is on disk: -z, turned into lines. A plain
# ls-files C-quotes any name holding a '"', a '\' or a control character --
# core.quotePath=false covers bytes above 0x7f and nothing else -- and a
# quoted name is no file's, so built_programs never looked inside one. Shell
# 01 ex05's turn-in is named with exactly those characters. What -z cannot be
# given back in lines is a name holding a newline itself: it comes out split,
# and built_programs cannot read it (no subject names such a file).
pushed_files() {
	_gd=$(mktemp -d) || return 1
	if git --git-dir="$_gd" init -q && stage_deliverable --git-dir="$_gd" --work-tree=.; then
		git --git-dir="$_gd" ls-files -z > "$_gd/pushed.z"
		_prc=$?
		[ "$_prc" -ne 0 ] || tr '\000' '\n' < "$_gd/pushed.z"
	else
		_prc=1
	fi
	rm -rf "$_gd"
	return "$_prc"
}

# The dry run's answer to "what would be pushed".
list_pushed() {
	if [ ! -d "$dir" ]; then
		printf '     dry-run: no %s yet, so nothing to list\n' "$dir"
		return 0
	fi
	if _list=$(pushed_files); then
		if [ -z "$_list" ]; then
			printf '     dry-run: %s holds nothing to push\n' "$dir"
		else
			printf '     dry-run: would push these %d file(s), from %s as it is now:\n' \
				"$(printf '%s\n' "$_list" | grep -c .)" "$dir"
			printf '%s\n' "$_list" | sed 's/^/                /'
		fi
	else
		printf '     dry-run: could not list %s (git failed above)\n' "$dir"
	fi
}

# A built program among the files the push would carry, one per line: an ELF
# file (what cc and ld write on Linux, whatever it is called), a Mach-O one
# (what they write on a campus Mac), or a file named like a program a c_make()
# in the module's BUILD file builds -- the name the subject gives it, whatever
# it holds. The Mach-O magic is read in both byte orders, 32- and 64-bit; a
# universal ("fat") binary is left out, because its magic, cafebabe, is also
# a Java class file's, and it takes two -arch flags no Makefile here passes.
# The tests never read one: they build from the sources, and the build layer
# deletes the program before it starts. So pushing one pushes a tree nobody
# tested, and the subjects ask for the files they name, not for what those
# files build. Symbolic links are left alone: git records the link, not what
# it points to.
built_programs() {
	[ -d "$dir" ] || return 0
	_names=$(sed -n 's/^[[:space:]]*artifact[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
		"$mod/BUILD.bazel" 2> /dev/null)
	pushed_files | while IFS= read -r _f; do
		_p="$dir/$_f"
		[ -f "$_p" ] && [ ! -L "$_p" ] || continue
		if [ -n "$_names" ] && printf '%s\n' "$_names" | grep -qxF -- "${_f##*/}"; then
			printf '%s\n' "$_f"
		else
			case "$(od -An -tx1 -N4 "$_p" 2> /dev/null | tr -d ' \n')" in
				7f454c46 | cffaedfe | cefaedfe | feedfacf | feedface)
					printf '%s\n' "$_f" ;;
			esac
		fi
	done
}

# A module id is a path from the repo root to a project folder, one or more
# components deep (c-piscine/c-piscine-c-00). It used to be refused outright if
# it contained a '/', which was right while every module sat at the root and
# became a silent no-op the day they moved under a course folder: every row
# printed "bad module name", nothing was pushed, and the run exited 0. What must
# still be refused is anything that could climb out of the repo or name the
# repo itself: an absolute path, an empty component, '.' or '..'.
valid_mod() {
	case "$1" in
		"" | /* | */ | *//*) return 1 ;;
	esac
	_rest=$1
	while :; do
		_c=${_rest%%/*}
		case "$_c" in
			"" | . | ..) return 1 ;;
		esac
		[ "$_rest" = "$_c" ] && return 0
		_rest=${_rest#*/}
	done
}

# The newest commit in $1's history by EMAIL42 -- your own last push there -- or
# nothing if you have never pushed to it. Compared the way the NOTE below
# decides the tip is not yours: the author's address, exactly.
last_push_by_you() {
	git -C "$dir" log --format='%H %ae' "$1" | while read -r _h _e; do
		[ "$_e" = "$EMAIL42" ] && { printf '%s\n' "$_h"; break; }
	done
}

# Of the files in $1 (one per line), those someone else changed on the tip $2
# since your last push $3: every commit after yours is someone else's. Not every
# file that differs from the tip -- a file of yours that you edited while a
# teammate pushed only OTHER files is still yours, not theirs.
changed_since() {
	_cs=$(mktemp) || return 0
	git -C "$dir" -c core.quotePath=false diff --name-only "$3" "$2" > "$_cs"
	printf '%s\n' "$1" | grep -Fx -f "$_cs"
	rm -f "$_cs"
}

# Print the lines of $1 indented under a NOTE, ten at most, and a count of the
# rest.
list_some() {
	printf '%s\n' "$1" | sed -n '1,10s/^/             /p'
	_n=$(printf '%s\n' "$1" | grep -c .)
	[ "$_n" -gt 10 ] && printf '             ... and %d more\n' "$((_n - 10))"
	return 0
}

submit() {
	mod=$1
	url=$2
	wanted "$mod" || return 0
	if [ -z "$url" ] || [ "$url" = REPLACE_ME ]; then
		printf 'SKIP  %-20s  (no URL for it in .submit-remotes)\n' "$mod"
		SKIPPED=$((SKIPPED + 1)); return 0
	fi
	# A row WITH a remote whose id the guard refuses is a failure, not a skip:
	# its URL says someone meant to push it. Counting it as skipped used to end
	# the run with exit 0 having pushed nothing -- the exact shape of a
	# submission that worked.
	if ! valid_mod "$mod"; then
		printf 'FAIL  bad module name: %s\n' "$mod"
		FAIL=$((FAIL + 1)); return 0
	fi
	# After the REPLACE_ME skip, so the rows nobody has filled in yet do not all
	# have to exist to be skipped. A row WITH a remote must name a project folder:
	# `//$mod/...` is the gate and `$mod/deliverable` is what gets pushed, and a
	# typo in the key would otherwise gate on nothing and push nothing.
	if [ ! -f "$mod/BUILD.bazel" ]; then
		printf 'FAIL  %-20s  not a project folder (no %s/BUILD.bazel)\n' "$mod" "$mod"
		FAIL=$((FAIL + 1)); return 0
	fi

	dir="$mod/deliverable"
	# Generator-backed if it HAS generators/, not if its name contains "shell":
	# the name test misfired on the cursus's minishell (no generators) and
	# missed Piscine Reloaded (shell exercises, no "shell" in the name).
	is_shell=0
	[ -d "$mod/generators" ] && is_shell=1

	printf '\n==>  %-20s  ->  %s\n' "$mod" "$url"

	# A built program is refused before anything else runs, gate included:
	# nothing that gate could say makes the push the tree it tested. Generating
	# a module's deliverable does not remove one either -- generate.sh refuses
	# to replace a folder holding a file its generator did not write.
	_progs=$(built_programs)
	if [ -n "$_progs" ]; then
		if [ "$DRY" = 1 ]; then
			printf '     dry-run: would be BLOCKED -- %s holds a built program:\n' "$dir"
		else
			printf '     BLOCKED: %s holds a built program -- not pushed:\n' "$dir"
		fi
		printf '%s\n' "$_progs" | sed -n '1,10s/^/                /p'
		printf '              Every file there is pushed, and the tests never read this one:\n'
		printf '              they build from your sources. The subject asks for the files\n'
		printf '              it names, not for what they build. Remove it (with make fclean)\n'
		printf '              before submitting.\n'
		FAIL=$((FAIL + 1))
		[ "$DRY" = 1 ] && list_pushed
		return 0
	fi

	if [ "$DRY" = 1 ]; then
		[ "$GATE" = 1 ] && printf '     dry-run: would gate on  bazel test //%s/... --test_tag_filters=%s %s  (level: %s; skip if red)\n' \
			"$mod" "$(gate_tags "$GATE_LEVEL")" "$GATE_FLAGS" "$GATE_LEVEL"
		[ "$is_shell" = 1 ] && printf '     dry-run: would regenerate %s from generators/\n' "$dir"
		printf '     dry-run: would fetch the remote, commit on top of its %s branch (a first\n' "$BRANCH"
		printf '              commit if it has none) and push; never --force\n'
		[ "$is_shell" = 1 ] && printf '     dry-run: (the list below is before the regeneration above)\n'
		list_pushed
		return 0
	fi

	# 1. Gate on the module's tests.
	if [ "$GATE" = 1 ]; then
		printf '     gate: bazel test //%s/... (level: %s)\n' "$mod" "$GATE_LEVEL"
		printf '           (after any bazel command still running in this checkout; it\n'
		printf '           builds and runs the tests again, trusting no cached result)\n'
		run_gate "$mod"
		gate_status=$?
		if [ "$gate_status" -ne 0 ]; then
			# Hand over the command the gate ACTUALLY ran — including
			# --keep_going, or the re-run stops at the first failure and shows
			# FEWER reds than the gate saw; the tag filter, or it shows the
			# levels above this one too, and not which reds stopped the push;
			# and the two flags that trust no cache, or it could serve the
			# very result the gate would not trust.
			gate_cmd="bazel test //$mod/... --test_tag_filters=$(gate_tags "$GATE_LEVEL") $GATE_FLAGS"
			if [ "$gate_status" -eq 3 ]; then
				printf '     BLOCKED: tests are FAILING — not pushed. See which, with:\n'
				printf '                %s\n' "$gate_cmd"
				printf '              Then fix them, or bypass the gate with --no-gate.\n'
				gate_files_reports
			elif [ "$gate_status" -eq 1 ]; then
				# 1 is a build or analysis error, and this used to share the
				# branch below, which calls the exit "NOT a verdict on your
				# code". A student's code that does not compile no longer
				# arrives here -- it fails its own tests, exit 3 -- but a
				# download that failed or a broken harness file does, and
				# those name no file of the student's. The headline follows
				# the lines: DOES NOT BUILD only when one of them names a file
				# of yours. The run keeps going past it (.bazelrc), so the
				# first errors are in the log either way.
				_own=$(gate_own_lines)
				if [ -n "$_own" ]; then
					printf '     BLOCKED: the module does NOT BUILD — not pushed. Bazel exited 1,\n'
					printf '              and these lines name your files: code that does not\n'
					printf '              compile or link (a syntax error, a warning under -Werror,\n'
					printf '              a leftover main()), or a turn-in file that is missing,\n'
					printf '              which scores 0 wherever the project is graded.\n'
					printf '%s\n' "$_own" | head -n 6 | sed 's/^/              | /'
					printf '              Which exercise does not build, and why:\n'
				else
					printf '     BLOCKED: the build STOPPED — not pushed. Bazel exited 1, and no\n'
					printf '              line of its errors names a file of yours: most often a\n'
					printf '              download that failed, or a file of the harness. Nothing\n'
					printf '              has checked this module, so it is not pushed. The first\n'
					printf '              errors:\n'
					if grep -qE '^ERROR: |(^|: )(fatal )?error(\[[A-Z0-9]+\])?: ' "$GATE_ERR" 2> /dev/null; then
						# The action and its target, not the command line
						# that follows them.
						grep -E '^ERROR: |(^|: )(fatal )?error(\[[A-Z0-9]+\])?: ' "$GATE_ERR" |
							grep -v 'Build did NOT complete' | head -n 6 |
							sed -e 's/: (Exit [0-9]*): [^ ]* failed: error executing [A-Za-z]* command//' \
								-e 's/\( failed (from [^)]*)\).*/\1/' -e 's/^/              | /'
					else
						tail -n 15 "$GATE_ERR" 2> /dev/null | sed 's/^/              | /'
					fi
					printf '              Run it again (a download often works the second time).\n'
					printf '              What stopped, and where:\n'
				fi
				printf '                %s 2>&1 | sh tools/first_red.sh\n' "$gate_cmd"
			else
				printf '     BLOCKED: the gate could not RUN — not pushed. Bazel exited %d.\n' "$gate_status"
				printf '              Only 3 ("tests failed") and 1 ("does not build") are\n'
				printf '              verdicts on the module (2 = bad command line, 4 = the level\n'
				printf '              matched no test at all, 36/37 = a transient local-environment\n'
				printf '              problem or an internal bazel error). So this is NOT a verdict\n'
				printf '              on your code — and --no-gate would push work that nothing\n'
				printf '              has checked. Bazel'\''s last words:\n'
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
			# Same reason the BLOCKED branch above quotes its own command: the
			# student re-runs exactly the run that found these reds.
			#
			# This used to say "Not blocking — the Moulinette does not grade
			# them", which is the only sentence a student gating at `basic` ever
			# reads about the layers the gate skipped, and it told them to
			# disregard it. Nobody knows what the Moulinette runs; what IS known
			# is that these layers are above the rung this run chose, and that
			# the choice was the student's to make. Say that, name what is red,
			# and let them decide.
			_advn=$(advisory_failures | grep -c .)
			printf '     NOTE: %s test(s) above the "%s" gate are red for this module:\n' \
				"$_advn" "$GATE_LEVEL"
			advisory_failures | sed -n '1,6p' | sed 's/^/             /'
			[ "$_advn" -gt 6 ] && printf '             ... and %d more\n' "$((_advn - 6))"
			printf '           Not blocking: you chose the "%s" rung, and this is what sits\n' "$GATE_LEVEL"
			printf '           above it. Whether 42 exercises any of it is not something this\n'
			printf '           script can tell you — a red here is still a real finding about\n'
			printf '           the code. Read it with:\n'
			printf '             bazel test //%s/... --test_tag_filters=-manual --keep_going\n' "$mod"
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

	# 3. Commit the deliverable on top of what the remote holds, and push.
	#
	# The new commit's parent is the remote branch's tip, fetched just before,
	# so a re-submit is a fast-forward and nothing is ever forced: on a group
	# repository, forcing would replace whatever a teammate pushed. Only a first
	# submit, to a remote without that branch, makes a root commit.
	#
	# deliverable/.git is rebuilt from nothing each time: it is this script's
	# scratch space, and the remote is the only history that counts.
	rm -rf "$dir/.git"
	if ! git -C "$dir" init -q; then
		printf '     git init failed for %s — skipped\n' "$mod"
		FAIL=$((FAIL + 1)); return 0
	fi
	git -C "$dir" symbolic-ref HEAD "refs/heads/$BRANCH"
	git -C "$dir" config core.filemode true
	git -C "$dir" remote add origin "$url"
	# Every branch rather than $BRANCH alone: fetching a branch the remote does
	# not have is an error, fetching all of none is not -- so a first submit to
	# an empty repository is not mistaken for a server that could not be reached.
	if ! remote_git fetch -q origin '+refs/heads/*:refs/remotes/origin/*'; then
		FAIL=$((FAIL + 1)); return 0
	fi
	_tip="refs/remotes/origin/$BRANCH"
	if git -C "$dir" rev-parse -q --verify "$_tip^{commit}" > /dev/null; then
		git -C "$dir" update-ref "refs/heads/$BRANCH" "$_tip"
	else
		_tip=""
	fi
	# The index starts empty, so after this it holds exactly the deliverable
	# on disk: a file the remote has and the disk does not is not in it, and
	# the commit removes it -- the tree pushed is always the tree you have.
	if ! stage_deliverable; then
		printf '     git add failed for %s — not pushed\n' "$mod"
		FAIL=$((FAIL + 1)); return 0
	fi
	if [ -z "$(git -C "$dir" ls-files | head -n 1)" ]; then
		printf '     nothing to push (empty deliverable?) — skipped\n'
		SKIPPED=$((SKIPPED + 1)); return 0
	fi
	if git -C "$dir" diff --cached --quiet; then
		printf '     already there: the remote'\''s %s holds exactly this deliverable — nothing pushed\n' "$BRANCH"
		SKIPPED=$((SKIPPED + 1)); return 0
	fi
	# Said before it happens, because on a group repository it is what a
	# teammate would want to know. The tip becomes this deliverable, so a file
	# the remote has and the disk does not leaves the tip; and when the last
	# push was not yours, each file someone else changed since your own last
	# push, and that differs from yours, is replaced by your version. Nothing
	# is erased -- it all stays in the repository's history, which is what
	# never forcing buys -- but the tip is what is graded.
	if [ -n "$_tip" ]; then
		_who=$(git -C "$dir" log -1 --format='%an <%ae>' "$_tip")
		_gone=$(git -C "$dir" -c core.quotePath=false diff --cached --name-only --diff-filter=D)
		_theirs=""
		if [ "$(git -C "$dir" log -1 --format='%ae' "$_tip")" != "$EMAIL42" ]; then
			_theirs=$(git -C "$dir" -c core.quotePath=false diff --cached --name-only --diff-filter=M)
			_mine=$(last_push_by_you "$_tip")
			[ -z "$_theirs" ] || [ -z "$_mine" ] ||
				_theirs=$(changed_since "$_theirs" "$_tip" "$_mine")
		fi
		if [ -n "$_gone" ]; then
			printf '     NOTE: the remote has files your deliverable/ does not, and this push\n'
			printf '           takes them off its tip (they stay in its history). Its last\n'
			printf '           commit is by %s:\n' "$_who"
			list_some "$_gone"
		fi
		if [ -n "$_theirs" ]; then
			printf '     NOTE: the last push to this repository was not yours but %s,\n' "$_who"
			if [ -n "$_mine" ]; then
				printf '           and these files were changed there after your own last push\n'
			else
				printf '           and you have never pushed to it, so these files there are\n'
				printf '           all someone else'\''s\n'
			fi
			printf '           and differ from yours. Your version replaces theirs on the tip\n'
			printf '           (theirs stays in its history):\n'
			list_some "$_theirs"
		fi
	fi
	# Checked. An unchecked commit falls through to the push, which then fails
	# with "src refspec master does not match any" -- which the classifier
	# reads as `other`, for a commit that never happened.
	if ! git -C "$dir" -c user.name="$LOGIN42" -c user.email="$EMAIL42" \
			commit -q -m "$MSG"; then
		printf '     git commit failed for %s — not pushed\n' "$mod"
		FAIL=$((FAIL + 1)); return 0
	fi
	if remote_git push -u origin "$BRANCH"; then
		OK=$((OK + 1))
	else
		FAIL=$((FAIL + 1))
	fi
}

# One line of the REMOTES table or of .submit-remotes -> $mod and $url. Both are
# written by hand and read the same way, for the reasons below. Returns 1 for a
# line that is not a row: blank, a comment, or malformed ($2 names the file in
# that report).
parse_row() {
	# Leading blanks first, so an indented "# ..." is still a comment.
	_e=$(printf '%s' "$1" | sed 's/^[[:space:]]*//')
	case "$_e" in
		"" | \#*) return 1 ;;
	esac
	# An entry with no "=" is not a table row. ${entry#*=} returns the string
	# UNCHANGED when there is no match, so "c-piscine-c-00 = git@..." (spaces
	# around the =) yielded a module whose remote was its own name -- not
	# REPLACE_ME, therefore treated as live, and pushed to a URL that is a
	# module name.
	case "$_e" in
		*=*) ;;
		*)
			printf 'SKIP  malformed %s line (no "="): %s\n' "$2" "$1"
			return 1 ;;
	esac
	# An inline comment ends the entry. docs/submitting.md shows a table line
	# written exactly this way -- "c-piscine-c-01=REPLACE_ME   # skipped" -- and
	# without this the whole tail becomes part of the URL, so the row stops
	# reading as REPLACE_ME and is treated as a LIVE remote pointing at prose.
	# Only " #" counts, never a bare '#', because that is what a comment looks
	# like and a URL does not contain one.
	_e=$(printf '%s' "$_e" | sed 's/[[:space:]]#.*$//')
	mod=${_e%%=*}
	url=${_e#*=}
	# Trim blanks around both halves. This table is hand-edited, and
	# "c-piscine-c-01 = git@..." is how a person writes one -- which produced a
	# module named "c-piscine-c-01 " (trailing space) pointed at a URL with a
	# leading space, and then a directory that does not exist. Being liberal
	# about the spacing costs one sed and removes a whole class of confusing
	# "SKIP: no c-piscine-c-01 /deliverable" reports.
	mod=$(printf '%s' "$mod" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s:/*$::')
	url=$(printf '%s' "$url" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
	[ -n "$mod" ]
}

# .submit-remotes: the student's URLs, one KEY=URL line per module, read once
# into OVR as "key=url" lines. Tracked in the student's own clone, like
# .submit-level, so it follows them to every machine; the template does not
# carry one (the template build removes it). The last line may lack its newline --
# an editor that does not add one must not lose a URL.
OVR_FILE=.submit-remotes
OVR=""
if [ -f "$OVR_FILE" ]; then
	while IFS= read -r entry || [ -n "$entry" ]; do
		parse_row "$entry" "$OVR_FILE" || continue
		OVR="$OVR$mod=$url
"
	done < "$OVR_FILE"
fi

# The URL .submit-remotes gives module $1, keyed by its path or by its project
# name alone (the two spellings the command line accepts), in $ovr_url; how
# many lines named it in $ovr_n. Every key that names a module is remembered in
# OVR_USED, so the ones that name none can be reported at the end.
OVR_USED=""
ovr_lookup() {
	ovr_url=""
	ovr_n=0
	while IFS= read -r _o; do
		[ -n "$_o" ] || continue
		_k=${_o%%=*}
		if [ "$_k" = "$1" ] || [ "$_k" = "${1##*/}" ]; then
			ovr_url=${_o#*=}
			ovr_n=$((ovr_n + 1))
			OVR_USED="$OVR_USED $_k"
		fi
	done <<OVERRIDES
$OVR
OVERRIDES
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
	parse_row "$entry" table || continue
	ovr_lookup "$mod"
	# Two URLs for one module: pushing to either is a guess about which
	# repository the grade comes from, so neither is used.
	if [ "$ovr_n" -gt 1 ]; then
		if wanted "$mod"; then
			printf 'FAIL  %-20s  %s gives it %d URLs: keep one\n' "$mod" "$OVR_FILE" "$ovr_n"
			FAIL=$((FAIL + 1))
		fi
		continue
	fi
	[ "$ovr_n" -eq 1 ] && url=$ovr_url
	submit "$mod" "$url"
done <<TABLE
$REMOTES
TABLE

# A .submit-remotes key that names no module is a URL that goes nowhere: almost
# always a typo in the key, and the module the student meant is then silently
# SKIPPED as having no URL. Same rule as a name on the command line, below.
UNKNOWN=""
while IFS= read -r _o; do
	[ -n "$_o" ] || continue
	_k=${_o%%=*}
	case " $OVR_USED " in
		*" $_k "*) ;;
		*) UNKNOWN="$UNKNOWN $_k" ;;
	esac
done <<OVERRIDES
$OVR
OVERRIDES

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

[ -n "$ADV_OUT" ] && rm -f "$ADV_OUT"

printf '\n----\nDone: %d pushed, %d failed/blocked, %d skipped.' "$OK" "$FAIL" "$SKIPPED"
[ "$DRY" = 1 ] && printf '  (dry-run)'
printf '\n'
_rc=0
if [ -n "$UNMATCHED" ]; then
	printf '\nNOT A MODULE IN THE TABLE:%s\n' "$UNMATCHED" >&2
	printf 'Nothing was pushed for it. The table is the REMOTES block near the top\n' >&2
	printf 'of this script; a module absent from it is invisible here, not skipped.\n' >&2
	_rc=1
fi
if [ -n "$UNKNOWN" ]; then
	printf '\nIN %s BUT NOT A MODULE:%s\n' "$OVR_FILE" "$UNKNOWN" >&2
	printf 'Its URL was used for nothing. A key is a module path from the REMOTES\n' >&2
	printf 'block near the top of this script (c-piscine/c-piscine-c-00), or its\n' >&2
	printf 'project name alone (c-piscine-c-00).\n' >&2
	_rc=1
fi
[ "$_rc" -eq 0 ] || exit "$_rc"
[ "$FAIL" -eq 0 ]
