#!/bin/sh
# Build a Makefile/shell-script deliverable and assert it produces its artifact.
#
# The whole exercise directory is staged into a writable scratch copy (Bazel
# runfiles are read-only), then built. For a Makefile we also exercise the rules
# themselves -- each check the call site asks for, quoting the sentence of the
# project's own subject that requires it (--quotes): the compile commands, a
# second `make` that does nothing, the .o files beside their .c, what clean,
# fclean and re do where the subject defines them (and this repo's convention
# at robust where it only lists them), and "Watch out for wildcards!".
#
# Usage:
#   make_test.sh --anchor PATH --artifact NAME [--script NAME] [--symbols a,b,c]
#                [--rules a,b,c] [--graph] [--relink] [--overlay SRC DEST]...
#                [--quotes FILE] [--recipe-cc any|ordered]
#                [--foreign-object PATH] [--build-target NAME] [--clues FILE]
#                [--exit-only | --rules-only | --recipe-only | --wildcards-only]
#
#   --anchor    $(location) of any file inside the exercise dir (its directory
#               is the subtree that gets staged and built)
#   --artifact  file expected to exist after building (e.g. libft.a)
#   --script    if set, run `sh <script>` instead of `make`. Every message
#               after the build names what ran ('make' or 'sh <script>').
#   --symbols   comma-separated symbols that must be defined in the artifact
#   --rules     which make rules THIS subject mandates, comma-separated, or
#               "-" for none at all (c-piscine-bsq names no rule).
#               Default "clean,fclean,re" -- what every caller wanted before this
#               existed. rush-02's subject names only $(NAME), clean and fclean,
#               so requiring `re` there would fail a correct Makefile on a rule
#               nobody asked for. Each rule's check SETS UP ITS OWN START STATE
#               (see "the rule steps" below) and reads make's exit status and
#               output: they used to lean on whatever the previous check left
#               behind, and `re` was judged on a tree `make all` had just
#               rebuilt, so a Makefile with no re rule at all passed.
#               A name is all, clean, fclean, re, or the artifact's own: C 09
#               ex01 lists "libft.a" among its rules, and rush-02's "$NAME" is
#               the program. `make <artifact>` then has to build it. Any other
#               name is refused (exit 2): a rule this runner cannot check would
#               otherwise be listed as mandated and checked by nobody.
#   --relink    run ONLY the no-unnecessary-work check, worded for a subject
#               that says 'must not relink' and nothing about where objects
#               land. c-piscine-bsq is that subject. --graph implies it.
#   --relink-source subject|norm
#               where that rule comes from, for the failure message: the
#               subject's own words (default; BSQ), or the Norm's, for a
#               project whose subject never mentions relinking (Piscine
#               Reloaded ex24 and ex27). Either way the sentence is the
#               `relink` quote (--quotes); this only says whose it is.
#   --overlay   stage the file SRC into the scratch copy at DEST (relative),
#               before building. For a turn-in that is a Makefile ALONE, built
#               against files the grader supplies: C 09 ex01 and Piscine
#               Reloaded ex24 ("We'll only fetch your Makefile and test it with
#               our files").
#               The harness's own copies are placeholders that compile, never
#               an exercise's answer. Anything the student's tree holds where
#               the grader's files go -- at a DEST, or anywhere in the top
#               directory of one (srcs/, includes/) -- is a FAIL: the grader
#               fetches the Makefile alone, so it is an extra file in the
#               turn-in, and the files layer cannot see it in a subdirectory.
#               DEST is a plain relative path to a file: a leading ./ is
#               dropped, and any other . or .. component, an empty one or a
#               trailing / is refused (exit 2). ./srcs/x.c once made "." the
#               grader's top directory, and every file of the turn-in, the
#               Makefile included, was reported as one the grader supplies.
#   --graph     run the incremental-build checks (no unnecessary work, object
#               placement). These were gated on "the exercise has more than one
#               .c", a proxy this script's own comment below called out as
#               dishonest: it is DORMANT while a team ships one source and ARMS
#               ITSELF the day they split, and its failure text quotes c-09's
#               subject at modules that are not c-09. The gate is now the
#               caller's to set, which is what that comment prescribed.
#   --exit-only judge only how each make run ENDED, for the robust exit-status
#               target (exNN_build_exit). The build and every mandated rule run
#               from the same start states, and each step reads what its run
#               did exactly as it does at basic -- but only to decide whether
#               that run's status is judged: a run that did its job and exits
#               non-zero FAILS, and a run that did not do its job is NOT
#               JUDGED (a rule the Makefile lacks, an all that built nothing,
#               an fclean that left the artifact, a clean that left objects, a
#               re that kept the old artifact, a rebuild that built nothing).
#               Reporting what went wrong is exNN_build's. See "THE EXIT
#               STATUS" below.
#   --clues FILE
#               the exercise's clues.tsv, printed under any FAIL of every
#               target (rl_clues): a Makefile exercise has no case names to
#               key a row on, so every row fires, CLUE_MODE at a time. Reloaded
#               ex24 and C 09 ex01 are a Makefile and nothing else, and their
#               hints were printed by no test until this existed.
#   --build-target NAME
#               the basic target's name, for the messages that send a student
#               from one twin to the other ('NAME' and 'NAME_exit'). c_make
#               passes it, because the macro is what names both; run by hand,
#               the exercise directory's exNN gives exNN_build. It is not read
#               from Bazel's TEST_TARGET: a runner called from inside another
#               test (the selftest) inherits that test's name.
#   --quotes FILE
#               the sentences of the project's own subject (or of the Norm it
#               binds) that the checks below apply, one per line, as
#               KEY<TAB>TEXT, TEXT naming where it is from ('C 09, p.6: "..."').
#               A message quotes the sentence of the check that failed, and
#               nothing else: this runner is shared, and a sentence written
#               into it for one project was once quoted at every other (finding
#               082). The keys: cc, print, unnecessary, objects, relink,
#               wildcards (what a check needs), and all, clean, fclean, re
#               (what a rule does, where the subject says). c_make writes the
#               file from its `quotes`, and refuses a key it does not know.
#               A check a flag asks for and no sentence backs is refused
#               (exit 2): a requirement nobody can quote is one this layer
#               invented.
#
#               WHAT A RULE DOES is judged where the subject says it. A rule
#               the subject lists is required here (make has to know it) at
#               basic, always; what clean, fclean and re DO is judged at basic
#               only where the subject defines it -- C 09 ex01 defines all
#               three -- and otherwise by --rules-only, at robust, against
#               this repo's convention, stated as such. C 10 lists "all, clean,
#               fclean" and says nothing of what they do. all and the
#               artifact's own rule have one job wherever they are listed,
#               building the artifact, and are judged at basic.
#   --recipe-cc any|ordered
#               every command that compiles a .c file runs cc -- the command
#               word itself, with or without a path: gcc and clang are other
#               compilers, and the one found is named -- with -Wall, -Wextra
#               and -Werror, in that order where 'ordered' (C 09 ex01: "in
#               that order"). Read from what make planned, `make -n` on the
#               clean tree, and from every compiler a build of a copy of
#               that tree ran by name, which a stand-in on PATH logs (a
#               loop's compiles are in no plan); never from the Makefile's
#               text. For --script, from the commands the script ran (sh
#               -x), and from every compiler it ran by name, so a trace the
#               script turns off hides none. A command is judged when its
#               word names a C compiler, and no other tool is -- not wc, not
#               what $(info) prints. A command that only runs another (env,
#               sh -c, xargs) is looked through to it. A command that
#               compiles nothing -- a link, an archive -- is not held to it:
#               every subject's sentence is about compiling. Needs the `cc`
#               quote.
#   --foreign-object PATH
#               an object file the build never made, planted at PATH before
#               each cleaning rule runs: 'Watch out for wildcards!' (C 09
#               ex01, Reloaded ex24), from the grader's side -- its own files
#               may sit where your objects do, and a clean that deletes by
#               pattern deletes them too. clean and fclean have to leave it,
#               and it is never counted among the objects they left behind.
#               Needs the `wildcards` quote.
#   --rules-only
#               the robust target (exNN_build_rules): what each rule the
#               subject lists and does not define does, against this repo's
#               convention. Everything basic judges is left to it.
#   --recipe-only
#               the --recipe-cc check alone, for a subject whose sentence about
#               cc is a READING of what binds the Makefile (C 10, C 11 ex05,
#               Reloaded: "Moulinette compiles with ... using cc"), which is
#               strict (exNN_build_recipe). A plan with no compile in it is a
#               SKIP: exNN_build says why.
#   --wildcards-only
#               the Norm's "no *.c, no *.o", at strict (exNN_build_wildcards),
#               for a Makefile whose subject does not say it outright: a decoy
#               source with an #error in it beside the sources the Makefile
#               compiles, and a foreign object beside the objects it makes
#               before each cleaning rule. Nothing else is judged.
#
# Env: MAKE_TIMEOUT  seconds one run of make (or of the script) may take;
#                    unset, what is left of the test's own time limit, which
#                    caps it in any case (tools/runner_lib.sh). A Makefile that
#                    never stops -- a rule that calls itself through $(MAKE), a
#                    $(shell) that waits for input -- is stopped and said to
#                    be, instead of Bazel killing the test with nothing in its
#                    log. Output is capped at 64 MiB the same way (SIGXFSZ).
#
# THE EXIT STATUS, by the rule in docs/reference.md ("Run contract"). No subject
# says how make, or a rule, exits. So at basic -- this runner without
# --exit-only -- a run that did what the subject asks and still exited
# non-zero is a WARNING and the test passes; under --exit-only the same run
# fails. That holds for the build itself, for each mandated rule, and for the
# rebuilds that set up a rule's start state. A run that did NOT do its job
# fails at basic whatever its status, and --exit-only does not judge it:
# how a run ENDED is only a question once it did what it was for, and a run
# that did not is exNN_build's finding, which says why. Judging it again here
# repeated that finding under a false explanation -- "'make all' built
# 'libft.a', and exited with status 2" over make's own "No rule to make target
# 'all'" -- which is the one thing this target must never say.
#
# So under --exit-only each rule step's checks of what its run did, and of
# what the rebuild before it did, still RUN; they decide whether the run is
# judged instead of failing the test. The effect checks of clean, fclean and
# re used to be skipped there outright, and an fclean that left the artifact
# and then stopped on a failing rm was judged on that status -- and its
# second run, "on a tree with nothing to clean", was asked what rm does "when
# the file it names is already gone", over a tree that still held it. A step
# whose first run is not judged makes no second run.

set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "make_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk basename cat chmod cksum comm cp dirname find fold grep head mkdir mktemp rm sed sleep sort touch tr wc

# The shared runner helpers -- the time budget, how a run ended, exiting signal
# traps and excerpts -- written once in tools/runner_lib.sh. The Makefile and
# the creator script are the student's code, and make runs them.
RL_NAME=make_test
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "make_test.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# The harness's own programs this runner starts by path, outside rl_run on
# purpose: //tools:conventions holds every other one to rl_run.
# conventions: harness tool NM -- the pinned nm: it reads symbols, and runs nothing

ANCHOR=""
OVERLAYS=""
ARTIFACT=""
SCRIPT=""
SYMS=""
RULES="clean,fclean,re"
GRAPH=0
RELINK=0
RELINK_SOURCE=subject
EXITONLY=0
T_BUILD=""
# Which target this run is: build (exNN_build, basic), exit (--exit-only),
# rules (--rules-only), recipe (--recipe-only) or wildcards (--wildcards-only).
MODE=build
QUOTES=""
RECIPE_CC=""
FOREIGN=""
CLUES=""

# ---------------------------------------------------------------------------
# nm is SUPPLIED, never found. --nm is required and there is no PATH fallback,
# for the reason every pinned tool here has one: a check whose answer depends on
# which binary happened to be first on PATH is not a check. This one is not
# hypothetical -- the 2026-08-09 campus audit caught nm resolving to a student's
# own Homebrew binutils 2.46.1, shadowing the system 2.38 the Moulinette uses.
# Exit 2 rather than 1 if it is missing: nothing was checked, so this is a broken
# harness and not a wrong deliverable.
NM=""
NM_LIBS=""
# The pinned make. It defaults to the box's so a hand-run outside Bazel still
# works, and every target passes --make. This is the one tool here that is not
# merely how a check is performed but part of what is GRADED: the subject
# requires the student's own Makefile to work, and the Moulinette runs it with
# its own copy of make, so running it here with whatever the machine has meant
# a Makefile could pass locally on a make that resolves things differently.
#
# Recursion inside a Makefile is fine either way: $(MAKE) expands to the make
# that is running, path and all, so a sub-make inherits this one.
MAKE_BIN="make"

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "make_test.sh: $1 needs a value" >&2; exit 2; }; }
# One target, one mode: the four --*-only flags are four different targets.
set_mode() {
	[ "$MODE" = build ] || [ "$MODE" = "$1" ] || {
		echo "make_test.sh: $2 cannot be combined with the --$MODE-only target's flag" >&2
		exit 2
	}
	MODE=$1
}

while [ $# -gt 0 ]; do
	case "$1" in
		--nm) need "$1" "$#"; NM="$2"; shift 2 ;;
		--nm-lib) need "$1" "$#"; NM_LIBS="${NM_LIBS:+$NM_LIBS:}$(dirname "$2")"; shift 2 ;;
		--make) need "$1" "$#"; MAKE_BIN="$2"; shift 2 ;;
		--anchor) need "$1" "$#"; ANCHOR="$2"; shift 2 ;;
		--artifact) need "$1" "$#"; ARTIFACT="$2"; shift 2 ;;
		--script) need "$1" "$#"; SCRIPT="$2"; shift 2 ;;
		--symbols) need "$1" "$#"; SYMS="$2"; shift 2 ;;
		# "-" is the empty set, spelled so it survives sh_test's tokenisation
		# of `args`; see c_make in tools/defs.bzl.
		--rules) need "$1" "$#"; RULES="$2"; [ "$RULES" = "-" ] && RULES=""; shift 2 ;;
		--overlay)
			[ "$#" -ge 3 ] || { echo "make_test.sh: --overlay needs SRC and DEST" >&2; exit 2; }
			# A leading ./ names the same file, so it goes: what the rest of
			# this script reads as the grader's top directory is DEST's first
			# component, and "." there is the whole exercise.
			_odst=$3
			while :; do
				case "$_odst" in
					./*) _odst=${_odst#./} ;;
					*) break ;;
				esac
			done
			case "$_odst" in
				"" | /* | . | .. | ../* | */.. | */../* | */. | */./* | */ | *//*)
					echo "make_test.sh: --overlay DEST must be a relative path to a file inside the exercise, with no . or .. in it: '$3'" >&2
					exit 2 ;;
			esac
			case "$2" in /*) _osrc="$2" ;; *) _osrc="$PWD/$2" ;; esac
			OVERLAYS="${OVERLAYS:+$OVERLAYS
}$_osrc=$_odst"
			shift 3 ;;
		--graph) GRAPH=1; shift ;;
		--exit-only) set_mode exit "$1"; EXITONLY=1; shift ;;
		--rules-only) set_mode rules "$1"; shift ;;
		--recipe-only) set_mode recipe "$1"; shift ;;
		--wildcards-only) set_mode wildcards "$1"; shift ;;
		--quotes)
			need "$1" "$#"
			[ -f "$2" ] || { echo "make_test.sh: no quotes file at $2" >&2; exit 2; }
			case "$2" in /*) QUOTES="$2" ;; *) QUOTES="$PWD/$2" ;; esac
			shift 2 ;;
		--recipe-cc)
			need "$1" "$#"
			case "$2" in
				any | ordered) RECIPE_CC="$2" ;;
				*) echo "make_test.sh: --recipe-cc must be any or ordered: '$2'" >&2; exit 2 ;;
			esac
			shift 2 ;;
		--foreign-object)
			need "$1" "$#"
			case "$2" in
				"" | /* | . | .. | ../* | */.. | */../* | */. | */./* | */ | *//*)
					echo "make_test.sh: --foreign-object must be a relative path to a file inside the exercise: '$2'" >&2
					exit 2 ;;
			esac
			FOREIGN="${2#./}"; shift 2 ;;
		--build-target) need "$1" "$#"; T_BUILD="$2"; shift 2 ;;
		# Absolute, like --quotes: the hints are printed after the `cd` into
		# the scratch copy, where a runfiles-relative path names nothing.
		--clues)
			need "$1" "$#"
			[ -f "$2" ] || { echo "make_test.sh: no clues file at $2" >&2; exit 2; }
			case "$2" in /*) CLUES="$2" ;; *) CLUES="$PWD/$2" ;; esac
			shift 2 ;;
		--relink) RELINK=1; shift ;;
		--relink-source)
			need "$1" "$#"
			case "$2" in
				subject | norm) RELINK_SOURCE="$2" ;;
				*) echo "make_test.sh: --relink-source must be subject or norm: '$2'" >&2; exit 2 ;;
			esac
			shift 2 ;;
		*) echo "make_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$NM" ] || { echo "make_test.sh: --nm is required (no PATH fallback by design)" >&2; exit 2; }
[ -x "$NM" ] || { echo "make_test.sh: --nm '$NM' is not executable" >&2; exit 2; }

# Absolute before anything uses them, like --make below. Bazel hands both over
# as runfiles-relative paths, and the symbols check runs nm after the `cd` into
# the scratch copy, where a relative path names nothing: every c_make that
# listed symbols was red on a Makefile that built correctly. A relative
# LD_LIBRARY_PATH entry is resolved against the cwd too, so the pinned nm would
# have lost its libbfd at the same moment.
case "$NM" in
	/*) ;;
	*) NM="$PWD/$NM" ;;
esac
if [ -n "$NM_LIBS" ]; then
	_abs=""
	_ifs=$IFS
	IFS=:
	for _d in $NM_LIBS; do
		case "$_d" in
			/*) ;;
			*) _d="$PWD/$_d" ;;
		esac
		_abs="${_abs:+$_abs:}$_d"
	done
	IFS=$_ifs
	NM_LIBS=$_abs
fi

# THE PINNED nm's OWN LIBRARIES, and why this is not the same as pinning nm.
#
# binutils ships FRONTENDS. This nm is 44 KB; everything it does is in libbfd,
# which it names as a bare soname with no RPATH and no RUNPATH. Without a path
# to the fetched copy the loader answers from /lib/x86_64-linux-gnu and the
# "pinned" nm is the box's binutils wearing a pinned name -- and it still
# prints the pinned version, because that string is in the frontend's own
# .rodata. On a campus box whose binutils is NOT 2.38 the version-stamped
# soname does not exist at all and the tool would not start.
#
# Exit 2, never 1: a missing directory is a wiring error, not a finding about
# the exercise. Copied deliberately from compile_check.sh's --cc-lib rather
# than abbreviated -- the shape is the argument.
if [ -n "$NM_LIBS" ]; then
	_ifs=$IFS
	IFS=:
	for _d in $NM_LIBS; do
		[ -d "$_d" ] || {
			IFS=$_ifs
			echo "make_test.sh: --nm-lib directory '$_d' does not exist." >&2
			echo "  Without it the loader would fall back to this machine's own" >&2
			echo "  binutils libraries and the pinned nm would silently stop" >&2
			echo "  being pinned, so this refuses to run rather than pass." >&2
			exit 2
		}
	done
	IFS=$_ifs
	LD_LIBRARY_PATH="$NM_LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	export LD_LIBRARY_PATH

	# PROVE THE LOADER AGREED, rather than that the flag arrived.
	#
	# The failure being guarded against is exactly one where the right file is
	# exec'd and the wrong code runs, so checking which file we exec proves
	# nothing. ld.so prints `calling init: <path>` for each library it actually
	# LOADED -- the `trying file=` lines above it are only candidates -- so that
	# is what gets read.
	_loaded=$(LD_DEBUG=libs "$NM" --version 2>&1 > /dev/null |
		sed -n 's/.*calling init: //p' | grep -E 'libbfd|libopcodes|libctf')
	if [ -z "$_loaded" ]; then
		echo "make_test.sh: could not observe which libraries '$NM' loaded." >&2
		echo "  LD_DEBUG=libs printed no 'calling init:' line for libbfd, so" >&2
		echo "  either this nm is statically linked (in which case delete" >&2
		echo "  --nm-lib and this check together) or the loader does not" >&2
		echo "  support LD_DEBUG. Refusing rather than assuming: the whole" >&2
		echo "  point of the flag is that a wrong answer here is invisible." >&2
		exit 2
	fi
	for _l in $_loaded; do
		case "$_l" in
			"$NM_LIBS"/*) ;;
			*)
				echo "make_test.sh: the pinned nm loaded '$_l'." >&2
				echo "  That is not under --nm-lib ('$NM_LIBS'), so the symbol" >&2
				echo "  table this layer is about to read would be parsed by" >&2
				echo "  this machine's binutils rather than the pinned one." >&2
				echo "  A version string proves nothing here: it lives in the" >&2
				echo "  frontend, not in the library that does the work." >&2
				exit 2
				;;
		esac
	done
fi

# Does this subject mandate rule $1?
has_rule() {
	case ",$RULES," in
		*",$1,"*) return 0 ;;
		*) return 1 ;;
	esac
}

if [ -z "$ANCHOR" ] || [ -z "$ARTIFACT" ]; then
	echo "make_test.sh: --anchor and --artifact are required" >&2
	exit 2
fi

# Every rule named in --rules is one a step below checks. has_rule used to
# ignore any other name in silence, so a subject's rule could be written into a
# BUILD file, look mandated, and be checked by nobody.
_ifs=$IFS
IFS=,
for _r in $RULES; do
	case "$_r" in
		all | clean | fclean | re | "$ARTIFACT") ;;
		*)
			IFS=$_ifs
			echo "make_test.sh: --rules names '$_r', which this runner has no check for." >&2
			echo "  It checks all, clean, fclean, re and the artifact's own rule ('$ARTIFACT')." >&2
			exit 2 ;;
	esac
done
IFS=$_ifs

# THE SENTENCES (--quotes), read once and checked: a key this runner does not
# know is a sentence nothing quotes, and a check with no sentence behind it
# is a requirement this layer would be inventing -- both are the call site's
# mistake, so exit 2.
QUOTE_KEYS='cc print unnecessary objects relink wildcards all clean fclean re'
if [ -n "$QUOTES" ]; then
	_bad=$(awk -F'\t' -v keys=" $QUOTE_KEYS " '
		/^[ \t]*(#|$)/ { next }
		NF < 2 || $2 == "" { print NR ": no TAB and sentence after the key"; next }
		index(keys, " " $1 " ") == 0 { print NR ": unknown key \047" $1 "\047" }' "$QUOTES")
	if [ -n "$_bad" ]; then
		{
			echo "make_test.sh: --quotes $QUOTES:"
			printf '%s\n' "$_bad" | sed 's/^/  line /'
			echo "  Each line is KEY<TAB>TEXT, and a KEY is one of: $QUOTE_KEYS"
		} >&2
		exit 2
	fi
fi
# quote KEY: the TEXT of every KEY line, one per line; nothing where none.
quote() {
	[ -n "$QUOTES" ] || return 0
	awk -F'\t' -v k="$1" '$1 == k { sub(/^[^\t]*\t/, ""); print }' "$QUOTES"
}
has_quote() { [ -n "$(quote "$1")" ]; }
# say KEY: the sentence(s) KEY quotes, for a message, folded to fit a
# terminal and indented under the line that introduces them.
say() {
	quote "$1" | fold -s -w 68 | sed 's/ *$//; s/^/    /'
}
# needs_quote FLAG KEY...: FLAG's check is backed by every KEY's sentence.
needs_quote() {
	_nq_flag=$1
	shift
	for _k in "$@"; do
		has_quote "$_k" && continue
		{
			echo "make_test.sh: $_nq_flag checks what the '$_k' sentence requires, and --quotes gives none."
			echo "  Quote the subject's sentence at the call site (c_make's quotes), or drop the"
			echo "  check: a requirement nobody can quote is one this layer would be inventing."
		} >&2
		exit 2
	done
}
[ "$GRAPH" = 0 ] || needs_quote --graph print unnecessary objects
[ -z "$RECIPE_CC" ] || needs_quote --recipe-cc cc
[ -z "$FOREIGN" ] || needs_quote --foreign-object wildcards
[ "$MODE" != wildcards ] || needs_quote --wildcards-only wildcards
# The Norm's sentence comes through --quotes like a subject's: written into
# the runner, it was a second way for one fact to travel, and the first to go
# stale when the Norm is revised.
if [ "$RELINK" = 1 ] && [ "$GRAPH" = 0 ]; then
	needs_quote --relink relink
fi
if [ "$MODE" = recipe ] && [ -z "$RECIPE_CC" ]; then
	echo "make_test.sh: --recipe-only is the --recipe-cc check alone, and there is no --recipe-cc" >&2
	exit 2
fi

case "$ANCHOR" in
	/*) A="$ANCHOR" ;;
	*) A="$PWD/$ANCHOR" ;;
esac
SRCDIR=$(dirname "$A")
# The two targets c_make emits, by name, for the messages that send a student
# from one to the other. --build-target is the macro's own name for them; by
# hand, the exercise directory is exNN. A turn-in at deliverable/ itself (BSQ,
# a Common Core project) has no exNN to guess from, which is why the macro
# says it.
if [ -z "$T_BUILD" ]; then
	EXDIR=$(basename "$SRCDIR")
	case "$EXDIR" in
		ex[0-9]*) T_BUILD="${EXDIR}_build" ;;
		*) T_BUILD="exNN_build" ;;
	esac
fi

WORK=$(mktemp -d)
# Everything this runner scratches lives under $WORK and $AUX, and both are
# removed on the way out however that happens. It used to have no cleanup at
# all: a staged COPY OF THE WHOLE EXERCISE TREE, plus three loose mktemp files,
# left behind on every invocation of every c_make target -- and this is the
# runner that stages a tree, so it leaked the most of any of them. rl_traps
# also ends it on INT and TERM, because Bazel kills a timed-out test rather
# than letting it return. $AUX is a directory of its own, not a corner of
# $WORK: $WORK is the tree make builds, and a file of ours there would be one
# more thing a Makefile's wildcard or clean rule could find.
AUX=$(mktemp -d)
# THE HINTS, under any FAIL: this runner ends a failure with `exit 1` in some
# thirty places, each after its own message, so they are printed on the way
# out rather than at each. Only on 1: 0 passed (or stood down) and 2 is a
# broken harness, neither of which is the student's to think about.
mt_hints() {
	[ "$1" -eq 1 ] || return 0
	rl_clues "$CLUES"
}
rl_traps 'mt_hints $?; rm -rf "$WORK" "$AUX"'
DRY="$AUX/dry"
REF="$AUX/ref"
FUT="$AUX/future"
LOG="$AUX/log"
BEFORE="$AUX/before"
AFTER="$AUX/after"
cp -rL "$SRCDIR"/. "$WORK"/ 2> /dev/null
# The grader's files, where a subject says the grader supplies them. A file the
# student ALSO turned in is a FAIL, not something to overwrite quietly: the
# grader fetches the Makefile alone, so the build judged here would not be the
# one the grader runs. The files layer reports the same copy, under srcs/ or
# includes/ too since it walks the whole tree, for what it is there: a file
# //tools:submit would push (docs/reference.md, "Which layers wait for
# which", says why both do). It is also what anyone does first to try their
# Makefile by hand, which is why the message says where to do that instead.
#
# Not only a file at a DEST: anything in a directory the grader's files go in.
# The subject's srcs/ and includes/ are the grader's whole, so a source of the
# student's own under srcs/ -- one the overlay does not happen to name -- is
# just as extra, and used to be staged beside the grader's without a word. A
# DEST at the top of the exercise claims that one file and nothing else.
#
# Here-documents, not pipes, so the loops run in this shell and their exits
# are this script's.
if [ -n "${OVERLAYS:-}" ]; then
	_theirs=""
	while IFS= read -r _o; do
		_top=${_o#*=}
		_top=${_top%%/*}
		case " $_theirs " in *" $_top "*) continue ;; esac
		_theirs="${_theirs:+$_theirs }$_top"
	done <<OVERLAY_LIST
$OVERLAYS
OVERLAY_LIST
	_extra=$(cd "$WORK" && for _t in $_theirs; do
		[ -e "$_t" ] || [ -L "$_t" ] || continue
		find "$_t" ! -type d
	done | sort)
	# Only exNN_build says so: to the other targets it is exNN_build's
	# finding, and the grader's copies are staged over them below all the same.
	if [ -n "$_extra" ] && [ "$MODE" = build ]; then
		{
			echo "make_test.sh: FAIL — your turn-in holds files where the grader's files go:"
			printf '%s\n' "$_extra" > "$AUX/extra"
			rl_excerpt "$AUX/extra" 20 extra-files.txt
			echo "  The subject fetches your Makefile and nothing else, and builds it"
			echo "  against its own files, so each of these is an extra file in what"
			echo "  you push. Remove them from the exercise directory. To try the"
			echo "  Makefile by hand, copy the grader's files and your Makefile"
			echo "  somewhere OUTSIDE deliverable/ and run make there (the README"
			echo "  shows how)."
		} >&2
		exit 1
	fi
	while IFS= read -r _o; do
		_src=${_o%%=*}
		_dst=${_o#*=}
		mkdir -p "$WORK/$(dirname "$_dst")" && cp -L "$_src" "$WORK/$_dst" || {
			echo "make_test.sh: cannot stage the grader's $_dst" >&2
			exit 2
		}
	done <<OVERLAY_LIST
$OVERLAYS
OVERLAY_LIST
fi
# Absolute before the cd, since Bazel hands the pinned make over as a
# runfiles-relative path and everything below runs from the scratch directory.
case "$MAKE_BIN" in
	*/*)
		case "$MAKE_BIN" in
			/*) ;;
			*) MAKE_BIN="$PWD/$MAKE_BIN" ;;
		esac
		;;
esac

# tools/exit_status is found beside this script, which is named relative to
# where it was started: found now, before the cd below strands that path.
rl_ready

cd "$WORK" || { echo "make_test.sh: cannot enter scratch dir" >&2; exit 2; }

# What ran, for every message after the build. The script arm (C 09 ex00) has
# no Makefile, no target and no rule, and its failure used to say "'make'
# succeeded" and talk about all three.
if [ -n "$SCRIPT" ]; then
	BUILDER="sh $SCRIPT"
	BUILT_BY="script"
else
	BUILDER="make"
	BUILT_BY="Makefile"
fi

# The first lines of what make said (in $LOG, or the file named), indented,
# for a message; the whole of it is kept in test.outputs when there is more.
excerpt() {
	_f=${1:-$LOG}
	if [ -s "$_f" ]; then
		rl_excerpt "$_f" 12 "make-${_f##*/}.txt"
	else
		echo "    (it printed nothing)"
	fi
}

# mk OUT ERR WHAT CMD [ARG...] -- one run of the student's Makefile or script:
# CMD's stdout to OUT, its stderr to ERR ("-": to OUT as well), and its status
# in RC. WHAT is how it would be typed ('make clean'), for a report.
#
# Every run goes through tools/runner_lib.sh (rl_tmo, rl_run): bounded by
# MAKE_TIMEOUT and by what is left of the test's own limit, with how it ended
# read from waitpid(), and its output capped. A run that did not END -- the time
# limit, the output cap or a signal stopped it -- has nothing to judge, and
# ends this runner with a FAIL that says which; that holds under --exit-only
# too, since a run killed rather than returning fails at every level (the Run
# contract). A plain status, of any number, is RC, and the caller's to judge.
# The reports go to stderr, with the FAILs: a run inside $( ) must not have its
# report read as the value.
MK_BLOCKS=131072
mk() {
	_mk_out=$1
	_mk_err=$2
	_mk_what=$3
	shift 3
	if ! rl_tmo "${MAKE_TIMEOUT:-}"; then
		rl_overrun "'$_mk_what'" >&2
		exit 1
	fi
	if [ "$_mk_err" = - ]; then
		( ulimit -f "$MK_BLOCKS" 2> /dev/null; rl_run "$@" ) > "$_mk_out" 2>&1
	else
		( ulimit -f "$MK_BLOCKS" 2> /dev/null; rl_run "$@" ) > "$_mk_out" 2> "$_mk_err"
	fi
	RC=$?
	rl_classify "$RC"
	case "$RL_CAUSE" in
		ok | "exit") return 0 ;;
		noexec)
			echo "make_test.sh: '$_mk_what' $RL_WHY" >&2
			exit 2 ;;
		"timeout") rl_overrun "'$_mk_what'" >&2 ;;
		runaway)
			{
				echo "make_test.sh: FAIL — '$_mk_what' kept writing past $((MK_BLOCKS / 2048)) MiB and was"
				echo "  stopped (SIGXFSZ): something it runs repeats without end."
			} >&2 ;;
		*)
			{
				echo "make_test.sh: FAIL — '$_mk_what' $RL_WHY."
				echo "  It was killed rather than returning, so nothing it did can be judged."
			} >&2 ;;
	esac
	if [ -s "$_mk_out" ]; then
		echo "  What it printed first:" >&2
		rl_excerpt "$_mk_out" 12 make-output.txt >&2
	fi
	exit 1
}

# default_goal -- GOAL, the rule a bare `make` runs: the first one in the file,
# unless .DEFAULT_GOAL names another. -p prints make's database and -q runs no
# recipe; the pinned GNU make writes the goal as `.DEFAULT_GOAL := name`. Empty
# when there is no rule at all. The LAST such line, not the first: a recipe
# that calls $(MAKE) is run even under -n and -q, and that sub-make prints its
# own database -- with its own default goal -- before this one prints make's.
#
# It sets GOAL rather than printing it, and is called in the runner's own
# shell: mk ends the runner (exit 1) on a run that did not return, and inside
# $(default_goal) that exit left only the subshell -- the runner then went on
# to print "Here the default goal is ''" under the report of the overrun.
default_goal() {
	mk "$AUX/db" /dev/null "make -pnq" "$MAKE_BIN" -pnq
	sed -n '/^\.DEFAULT_GOAL := /{s///;h;}; ${x;p;}' "$AUX/db" > "$AUX/goal"
	GOAL=""
	IFS= read -r GOAL < "$AUX/goal" || :
}

# The line every "nothing was built" message ends on, in student_build.sh's
# words, so the build layer and the run layers say the same thing about a stub.
not_written_yet() {
	echo "  If this exercise is not written yet, that is exactly what you should"
	if [ -n "$SCRIPT" ]; then
		echo "  expect to see: a stub script that holds only comments builds nothing."
	else
		echo "  expect to see: a stub Makefile builds nothing -- it has no rule yet,"
		echo "  or its recipes only echo."
	fi
}

# ------------------------------------------------------------ exit statuses
# status_note LABEL WHEN, after a run that did its job, with its status in $RC.
# 0 says nothing. Anything else is, by the header's rule, a WARNING at basic
# and a FAIL under --exit-only, printed where it happened and counted. LABEL
# is what ran, as it would be typed ('make', 'make clean', 'sh x.sh'); WHEN
# completes "'make clean' WHEN exited with status N". Every call counts one
# judged run, for the verdict at the end.
#
# The build's own status is noted once: a bare 'make' that exits non-zero
# does so again each time a rule step rebuilds the tree, and one note says it.
WARNED=0
STATUS_FAILS=0
STATUS_RUNS=0
BUILD_NOTED=0
NOT_JUDGED=0
JUDGE=1
# What the rule steps judged, for the verdicts: the rules whose effect
# exNN_build left to exNN_build_rules, and the definitions the subject does
# not give that they were left for (DEFERRED_KEYS), the checks that one
# made, and the runs the foreign object was looked for after.
DEFERRED=""
DEFERRED_KEYS=""
TOUCHED=""
CONV_CHECKS=0
FOREIGN_CHECKS=0
status_note() {
	# How a run ended is the build's and the exit twin's question only.
	case "$MODE" in
		rules | wildcards) return 0 ;;
	esac
	STATUS_RUNS=$((STATUS_RUNS + 1))
	[ "$RC" -ne 0 ] || return 0
	if [ "$1" = "$BUILDER" ]; then
		[ "$BUILD_NOTED" = 0 ] || return 0
		BUILD_NOTED=1
	fi
	if [ "$EXITONLY" = 1 ]; then
		STATUS_FAILS=$((STATUS_FAILS + 1))
		{
			echo "make_test.sh: FAIL — '$1' $2 exited with status $RC."
			echo "  The subject names no exit status for it. This is the robust check,"
			echo "  which applies the convention that a command that did its job exits"
			echo "  0; whether it did its job is ${T_BUILD}'s to say. It printed:"
			excerpt
			exit_hint "$1" "$2"
		} >&2
		return 0
	fi
	WARNED=1
	echo "make_test.sh: WARNING — '$1' $2 exited with status $RC."
	echo "  It did what your subject asks of it, so this is not a FAIL at this"
	echo "  level: the subject says nothing about how it exits, and a non-zero"
	echo "  exit it does not name is rigour this repo adds, which fails at robust"
	echo "  (${T_BUILD}_exit). It printed:"
	excerpt
	exit_hint "$1" "$2"
}

# not_judged LABEL WHY, in any target but exNN_build, for a rule run that
# did not do its job: it is left out of the verdict, and says so on the log.
# WHY completes "'make all': WHY". What the run did wrong is exNN_build's
# finding, at basic, and this names it rather than explaining it a second
# time.
not_judged() {
	JUDGE=0
	NOT_JUDGED=$((NOT_JUDGED + 1))
	echo "make_test.sh: NOT JUDGED — '$1': $2."
	if [ "$MODE" = exit ]; then
		echo "  A run that did not do its job has no exit status worth judging here;"
	else
		echo "  A rule that is not there, or a tree that did not build, leaves nothing"
		echo "  for this target to judge;"
	fi
	echo "  $T_BUILD says what went wrong."
}

# job_not_done LABEL WHY, where a step's own check has found that its run did
# not do its job. Under --exit-only that run is NOT JUDGED (not_judged, with
# the status it is not judged on) and this returns 0, so the step goes on to
# its next check, which JUDGE now skips. At basic it returns 1, and the
# caller prints its FAIL and exits:
#     job_not_done "make fclean" "it did not remove 'x'" || { FAIL...; exit 1; }
# One helper for every effect check, so no step can skip its checks under
# --exit-only again: that is how clean, fclean and re came to judge runs
# that had not done their job.
job_not_done() {
	[ "$MODE" = exit ] || return 1
	not_judged "$1" "$2 (it exited with status $RC)"
	return 0
}

# rule_note LABEL WHEN: status_note, for a rule run that did its job (run_rule
# and the step's own check say whether it did).
rule_note() {
	[ "$JUDGE" = 1 ] || return 0
	status_note "$@"
}

# The question under a non-zero exit. make stops at the first command that
# fails, so that command is in what it printed; a cleaning rule that meets a
# tree with nothing left to clean is the usual case, and the man page of the
# command that stopped it says what it does then.
exit_hint() {
	case "$1" in
		make*) ;;
		*) return 0 ;;
	esac
	echo "  make stops at the first command that fails, so nothing the rule meant"
	echo "  to run after that command ran."
	case "$2" in
		*"nothing to clean"*)
			echo "  Which command stopped it, and what does that command do when the"
			echo "  file it names is already gone? Its man page says." ;;
		*)
			echo "  Which command stopped it? Its own error is in what make printed." ;;
	esac
}

# Delete the artifact BEFORE building, so "it exists afterwards" means this run
# produced it. Bazel's data glob sweeps in whatever running make (or the script)
# by hand left in deliverable/ -- .gitignore hides those from git, not from
# native.glob -- and they are copied into this scratch dir with everything else.
# Without this the build layer can report green off a stale archive from an
# earlier hand-run, and the fclean/re hygiene below that would have caught it is
# skipped for the --script arm.
rm -f "$ARTIFACT"

# ------------------------------------------------------- the compile commands
# compile_cmds FILE KIND: the commands in FILE that compile a .c file, one
# per line as "VERDICT<TAB>WHY<TAB>LINE<TAB>WORDS": VERDICT is ok or bad,
# held to --recipe-cc, WHY says what is wrong ("gcc, not cc", "no
# -Werror"), LINE is the line of FILE the command is on, and WORDS the
# command's own words, quotes removed, one space apart -- one command
# however a trace quoted it, for telling two records of a run apart.
#
# KIND is make -- what `make -n` printed, where one line may hold several
# commands joined by ; && || | -- or trace -- what `sh -x` printed, one
# command a line, after its +. A command COMPILES when its command word names
# a C compiler (is_cc, below) and it names a .c operand: a link or an archive
# names no .c (every subject's sentence is about compiling). One that only
# preprocesses or prints a dependency rule (-E, -M, -MM) names its .c files
# and compiles none, so it is not judged either. A redirection is no word of
# a command (2> errors.log, >&2): the compiler is never given it. Words are split
# as the shell splits them, quotes included, so a ';' inside quotes ends
# nothing. The compiler is the command word itself, less any path:
# /usr/bin/cc is cc, and gcc is not -- the old check matched the letters cc
# anywhere before the flags, so gcc passed it and clang did not (finding 098).
#
# WHICH WORDS ARE COMPILERS is a list of compiler names, never a list of the
# tools that are not one. The check used to judge every command that named a
# .c unless its word was on a list of tools that only move files about, and
# every tool missing from that list was failed as "another compiler": a
# correct Makefile whose recipe printed $(info building x.c), or ran wc,
# diff or tee on a source, was red at basic in BSQ, Rush 02 and C 09 ex01.
# A compiler's name is a closed shape -- cc, and anything ending in cc (gcc,
# xcc, tcc, icc, x86_64-linux-gnu-gcc), with a version after it (gcc-12),
# clang (clang-14), c89 and c99, a C++ driver (g++, c++) -- and a tool of
# another name is no compiler of any sentence here, so it is left unjudged.
#
# A command that only RUNS another -- env, exec, command, nice, nohup,
# xargs, ccache, distcc -- is looked through to the one it runs, and `sh -c
# 'STRING'` has STRING read as a command line of its own: these used to be in
# the list of tools that compile nothing, so `env gcc -c x.c` was not judged
# at all.
compile_cmds() {
	awk -v kind="$2" -v ordered="$([ "$RECIPE_CC" = ordered ] && echo 1)" '
		BEGIN {
			n = split("do then else elif if ! { time", a, " ")
			for (i = 1; i <= n; i++) lead[a[i]] = 1
			# The commands that run the next word, and their options that
			# take a value of their own.
			n = split("env exec command nice nohup xargs ccache distcc", a, " ")
			for (i = 1; i <= n; i++) wrap[a[i]] = 1
			n = split("env:-u env:-C env:-S nice:-n xargs:-n xargs:-I xargs:-L " \
				"xargs:-P xargs:-d xargs:-s xargs:-a xargs:-E", a, " ")
			for (i = 1; i <= n; i++) takes[a[i]] = 1
			n = split("sh bash dash", a, " ")
			for (i = 1; i <= n; i++) shell[a[i]] = 1
		}
		# Is B, a command word less its path, the name of a C compiler?
		function is_cc(b) {
			return b ~ /cc$/ || b ~ /cc-[0-9][0-9.]*$/ || b ~ /^(c89|c99|icx)$/ ||
				b ~ /clang(-[0-9][0-9.]*)?$/ || b ~ /\+\+(-[0-9][0-9.]*)?$/
		}
		function judge(text,    s, b, j, hasc, st, fw, fx, fe, miss, why, ws) {
			if (nw == 0) return
			s = 1
			while (s <= nw) {
				b = W[s]
				sub(/.*\//, "", b)
				if ((W[s] in lead) || W[s] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { s++; continue }
				if (!(b in wrap)) break
				for (s++; s <= nw && (W[s] ~ /^-/ || (b == "env" && W[s] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)); s++)
					if ((b ":" W[s]) in takes) s++
			}
			if (s > nw) { nw = 0; return }
			b = W[s]
			sub(/.*\//, "", b)
			# sh -c STRING: STRING is the command line, read once this one is.
			if ((b in shell) && s + 2 <= nw && W[s + 1] ~ /^-[a-z]*c[a-z]*$/) {
				inner[++ninner] = W[s + 2]
				nw = 0
				return
			}
			ws = W[s]
			for (j = s + 1; j <= nw; j++) ws = ws " " W[j]
			hasc = 0
			for (j = s + 1; j <= nw; j++)
				if (W[j] ~ /\.c$/ && W[j] !~ /^-/) hasc = 1
			if (!hasc || !is_cc(b)) { nw = 0; return }
			# -E, -M and -MM stop before compiling: they preprocess, or
			# print a dependency rule (cc -MM $(SRCS) > .depend), and
			# compile nothing a sentence about compiling binds. -MD and
			# -MMD are other words, and ride along with a compile.
			for (j = s + 1; j <= nw; j++)
				if (W[j] == "-E" || W[j] == "-M" || W[j] == "-MM") { nw = 0; return }
			# Every fault of the command, not the first: a gcc with no
			# flags was marked "gcc, not cc" alone, so the student who
			# fixed that met the flags on a second red run (the mutation
			# run of 2026-10-03, c09b M1 and c11 M9).
			why = ""
			if (b != "cc")
				why = b ", not cc"
			st = 0; fw = 0; fx = 0; fe = 0
			for (j = s + 1; j <= nw; j++) {
				if (W[j] == "-Wall") { fw = 1; if (st == 0) st = 1 }
				else if (W[j] == "-Wextra") { fx = 1; if (st == 1) st = 2 }
				else if (W[j] == "-Werror") { fe = 1; if (st == 2) st = 3 }
			}
			miss = ""
			if (!fw) miss = miss " -Wall"
			if (!fx) miss = miss " -Wextra"
			if (!fe) miss = miss " -Werror"
			if (miss != "") why = why (why == "" ? "" : "; ") "no" miss
			else if (ordered && st != 3) why = why (why == "" ? "" : "; ") "-Wall -Wextra -Werror out of that order"
			gsub(/\t/, " ", ws)
			printf "%s\t%s\t%s\t%s\n", (why == "" ? "ok" : "bad"), why, text, ws
			nw = 0
		}
		# One command line, split into words and judged command by command.
		# What is printed of it is the line with each run of blanks made one
		# space: a TAB in it would end the field the line is printed in, and
		# a joined line (below) carries the indent of its second half.
		# K is the kind of the file, or "make" for an `sh -c` string: one
		# line that may hold several commands.
		function cmdline(line, k,    i, c, L, t) {
			if (k == "trace") {
				if (line !~ /^\++ /) return
				sub(/^\++ /, "", line)
			} else if (line ~ /^[^ ]*make(\[[0-9]+\])?: /)
				return
			t = line
			gsub(/[ \t]+/, " ", t)
			sub(/^ /, "", t)
			sub(/ $/, "", t)
			nw = 0; cur = ""; inw = 0; q = ""; redir = 0
			L = length(line)
			for (i = 1; i <= L; i++) {
				c = substr(line, i, 1)
				if (q != "") {
					if (c == q) q = ""
					else if (c == "\\" && q == "\"" && i < L) { i++; cur = cur substr(line, i, 1) }
					else cur = cur c
					continue
				}
				if (c == "\047" || c == "\"") { q = c; inw = 1; continue }
				if (c == "\\" && i < L) { i++; cur = cur substr(line, i, 1); inw = 1; continue }
				if (c == " " || c == "\t") {
					if (inw) endword()
					continue
				}
				# A REDIRECTION is no word of the command: the shell takes it
				# off before the command runs, so a compiler is never given
				# it, and the stand-ins (cc_shims) log no trace of it. Kept,
				# `cc ... 2> errors.log` in the plan matched no logged compile,
				# and the one compile was counted twice, once as out of the
				# plan. The operator goes -- an fd number written against it
				# (2>) and the & of >&2 with it, which ends no command -- and
				# so does the word after it, its target. A trace has none:
				# sh -x prints no redirection, and the stand-ins quote a >.
				if (k != "trace" && (c == ">" || c == "<")) {
					if (inw && cur ~ /^[0-9]+$/) { cur = ""; inw = 0 }
					else if (inw) endword()
					while (i < L && index("<>&|", substr(line, i + 1, 1)) > 0) i++
					redir = 1
					continue
				}
				if (k != "trace" && (c == ";" || c == "&" || c == "|" || c == "(" || c == ")")) {
					if (inw) endword()
					redir = 0
					judge(t)
					continue
				}
				cur = cur c
				inw = 1
			}
			if (inw) endword()
			judge(t)
		}
		# endword: the word read so far ends. It is the next word of the
		# command -- or, after a redirection operator, its target, and dropped.
		function endword() {
			if (redir) redir = 0
			else W[++nw] = cur
			cur = ""
			inw = 0
		}
		# oneline LINE: one line of the file, and every `sh -c` string in
		# it, and in those.
		function oneline(l,    x) {
			ninner = 0
			cmdline(l, kind)
			while (ninner > 0) {
				x = inner[ninner--]
				cmdline(x, "make")
			}
		}
		# A recipe line that ends in a backslash goes on to the next, as the
		# shell reads it: make prints the backslash and the newline as they
		# are written, so a compile split over two lines came here as a
		# command "-c x.c -o x.o", and a right one was failed for running
		# "-c, not cc". One logical line is joined back first. sh -x prints
		# each command on one line, and needs none of it.
		kind != "trace" && pend != "" { $0 = pend $0; pend = "" }
		kind != "trace" && match($0, /\\+$/) && RLENGTH % 2 == 1 {
			pend = substr($0, 1, length($0) - 1) " "
			next
		}
		{ oneline($0) }
		END { if (pend != "") oneline(pend) }' "$1"
}

# cc_shims: $AUX/ccshim/, a stand-in for each compiler a script or a recipe
# can run by name, which writes the call to $AUX/ccshim.log and runs the
# compiler it stands in for. What a creator script compiles is read from its
# trace (sh -x), and a trace can be hidden -- `set +x`, `exec 2>/dev/null`, a
# block with its stderr sent away -- which made exNN_build_recipe SKIP,
# saying no compile ran. What a Makefile compiles is read from `make -n`,
# which prints a shell loop and not its turns. A compiler run by name goes
# through PATH whatever the trace or the plan shows. Only a compiler that is
# there gets one, so a name that is not found stays not found.
#
# Each word is logged as sh -x would print it, in single quotes when it holds
# anything but letters, digits and . _ / = + : , @ % ^ -, so compile_cmds
# reads back the very words the compiler was given: a compile is matched to
# its line in the plan by its words, and -DX=\"y\" logged bare read as
# -DX=y, one more compile than ran.
cc_shims() {
	mkdir -p "$AUX/ccshim"
	: > "$AUX/ccshim.log"
	: > "$AUX/ccshim.bypass"
	for _n in cc gcc clang c89 c99; do
		_r=$(command -v "$_n" 2> /dev/null) || continue
		case "$_r" in /*) ;; *) continue ;; esac
		{
			echo '#!/bin/sh'
			echo "# make_test.sh: logs this call of $_n, then runs it."
			echo "{ printf '+ %s' '$_n'"
			cat <<'SHIM_EOF'
  for a in "$@"; do
    case "$a" in
      '' | *[!A-Za-z0-9_./=+:,@%^-]*)
        printf " '%s'" "$(printf '%s' "$a" | sed "s/'/'\\\\''/g")" ;;
      *) printf ' %s' "$a" ;;
    esac
  done
  echo
SHIM_EOF
			echo "} >> '$AUX/ccshim.log'"
			# And each compiler name this call's PATH finds elsewhere than
			# its stand-in: a Makefile that puts a folder of its own first
			# on PATH runs the compiler past the stand-ins, which then log
			# nothing of it (merge_compiles' phantoms).
			echo "for _x in cc gcc clang c89 c99; do [ ! -x '$AUX/ccshim/'\"\$_x\" ] ||" \
				"[ \"\$(command -v \"\$_x\" 2> /dev/null)\" = '$AUX/ccshim/'\"\$_x\" ] ||" \
				"echo \"\$_x\"; done >> '$AUX/ccshim.bypass'"
			echo "exec '$_r' \"\$@\""
		} > "$AUX/ccshim/$_n"
		chmod +x "$AUX/ccshim/$_n"
	done
}

# merge_compiles FIRST SHIM: $AUX/recipe_all, every compile FIRST holds
# (compile_cmds' records of the trace or the plan) and every one in SHIM (of
# the stand-ins' log) that FIRST does not: one command in both is counted
# once, matched by its words. What only SHIM holds is in $AUX/recipe_hidden
# as well, for the NOTE that says where it came from.
#
# A plan prints a loop's compile before the shell expands it -- `gcc -c $s.c`
# -- and the stand-ins log each turn. Such a line is a TEMPLATE: a word with
# a $ in it matches any word that starts and ends as it does around its one
# variable (any word at all, with two). A template some logged compile
# matches is left out, and the compiles it stands for are judged in its
# place: counting both said "3 of the 3" over a loop that ran two.
#
# PHANTOMS (1, from plan_compiles) lets a plan line no build ran be set
# aside as text the Makefile printed, and WRITTEN names, one per line, the
# files that build wrote (their last component).
merge_compiles() {
	: > "$AUX/recipe_hidden"
	: > "$AUX/recipe_phantom"
	# The compilers whose stand-in the build's recipes FOUND by name: a plan
	# line that runs one of these by that bare name, and that no stand-in
	# logged, ran nowhere. Only where some stand-in was reached at all (a
	# build whose stand-ins logged nothing may have run every compiler past
	# them), and less every name a call's PATH found elsewhere -- a Makefile
	# that exports a PATH of its own, $(CURDIR)/bin or /usr/bin first, runs
	# that compiler unlogged (cc_shims' ccshim.bypass).
	_mc_shimmed=
	if [ -s "$AUX/ccshim.log" ]; then
		for _mc_f in "$AUX"/ccshim/*; do
			[ -f "$_mc_f" ] || continue
			_mc_n=${_mc_f##*/}
			grep -qxF -- "$_mc_n" "$AUX/ccshim.bypass" 2> /dev/null ||
				_mc_shimmed="$_mc_shimmed$_mc_n "
		done
	fi
	awk -F'\t' -v hidden="$AUX/recipe_hidden" -v phantom="$AUX/recipe_phantom" \
		-v phantoms="${3:-0}" -v shimmed=" $_mc_shimmed" -v written="${4:-/dev/null}" '
		# The last components of the files the compile W writes: what
		# follows -o; else, with -c, each source as its .o; else a.out.
		function outs(w, o,    nw3, ww, i, out, hasc, k, b) {
			nw3 = split(w, ww, " ")
			out = ""
			hasc = 0
			for (i = 1; i <= nw3; i++) {
				if (ww[i] == "-o" && i < nw3) out = ww[i + 1]
				else if (ww[i] ~ /^-o./) out = substr(ww[i], 3)
				else if (ww[i] == "-c") hasc = 1
			}
			k = 0
			if (out != "") { sub(/.*\//, "", out); o[++k] = out; return k }
			if (!hasc) { o[++k] = "a.out"; return k }
			for (i = 1; i <= nw3; i++)
				if (ww[i] ~ /\.c$/) { b = ww[i]; sub(/.*\//, "", b); sub(/\.c$/, ".o", b); o[++k] = b }
			return k
		}
		BEGIN { while ((getline l < written) > 0) wrote[l] = 1 }
		# Does the logged command W match the template T, word by word?
		function fits(t, w,    nt, nw2, tw, ww, i, a, b, p, q) {
			nt = split(t, tw, " ")
			nw2 = split(w, ww, " ")
			if (nt != nw2) return 0
			for (i = 1; i <= nt; i++) {
				if (index(tw[i], "$") == 0) {
					if (tw[i] != ww[i]) return 0
					continue
				}
				a = tw[i]
				p = substr(a, 1, index(a, "$") - 1)
				b = substr(a, index(a, "$") + 1)
				if (index(b, "$") > 0) continue
				sub(/^(\{[A-Za-z_][A-Za-z0-9_]*\}|[A-Za-z_][A-Za-z0-9_]*|[0-9@*#?])/, "", b)
				q = b
				if (length(ww[i]) < length(p) + length(q)) return 0
				if (substr(ww[i], 1, length(p)) != p) return 0
				if (q != "" && substr(ww[i], length(ww[i]) - length(q) + 1) != q) return 0
			}
			return 1
		}
		FILENAME == ARGV[1] {
			first[++nf] = $0
			fw[nf] = $4
			if (index($4, "$") == 0) n[$4]++
			next
		}
		{ shim[++ns] = $0; sw[ns] = $4 }
		END {
			# Every file a logged compile wrote, by name.
			for (j = 1; j <= ns; j++) {
				k = outs(sw[j], so)
				for (x = 1; x <= k; x++) logged_out[so[x]] = 1
			}
			for (j = 1; j <= ns; j++) {
				if (n[sw[j]] > 0) { n[sw[j]]--; continue }
				for (i = 1; i <= nf; i++)
					if (index(fw[i], "$") > 0 && fits(fw[i], sw[j])) used[i] = 1
				late[j] = 1
			}
			for (i = 1; i <= nf; i++) {
				if (used[i]) continue
				# A PHANTOM: a line the plan printed that reads as a compile
				# by a compiler stood in for by name, which no build ran.
				# $(info ...) and $(warning ...) print to the same stream as
				# the commands make -n plans, and `$(info gcc -c x.c)` read
				# as a gcc compile -- failed, or counted twice beside the
				# one it repeated. Only where the plan line starts with
				# that compiler (a wrapper -- ccache, env -- may run one
				# past the stand-ins), the build it is checked against
				# ran to its end (phantoms = 1, plan_compiles), and that
				# compiler was found as its stand-in (shimmed). And where
				# nothing else wrote what it would have: a file of its
				# output name the build wrote, and no logged compile did,
				# was written by something the stand-ins did not see --
				# that compiler run under a PATH one target sets.
				if (phantoms == 1 && index(fw[i], "$") == 0 && n[fw[i]] > 0) {
					split(fw[i], cw, " ")
					split(first[i], ff, "\t")
					split(ff[3], lw, " ")
					unseen_out = 0
					k = outs(fw[i], po)
					for (x = 1; x <= k; x++)
						if ((po[x] in wrote) && !(po[x] in logged_out)) unseen_out = 1
					if (cw[1] == lw[1] && index(cw[1], "/") == 0 && !unseen_out &&
					    index(shimmed, " " cw[1] " ") > 0) {
						n[fw[i]]--
						print first[i] > phantom
						continue
					}
				}
				print first[i]
			}
			for (j = 1; j <= ns; j++)
				if (late[j]) { print shim[j] > hidden; print shim[j] }
		}' \
		"$1" "$2" > "$AUX/recipe_all"
}

# made_objects DIR BEFORE: the objects under DIR that are not in the list
# BEFORE (made_objects DIR /dev/null, taken before the build), one per line,
# relative to DIR -- what a build made. Not -newer than a stamp: a file's
# time is the kernel's coarse clock, and a compile in the same tick as the
# stamp read as made before it.
made_objects() {
	(cd "$1" && find . -type f -name '*.o' 2> /dev/null) | sed 's|^\./||' | sort |
		{ if [ -s "$2" ]; then grep -vxF -f "$2"; else cat; fi; } || :
}

# tree_sums: every file under the current directory with its checksum and
# size, sorted -- what a build wrote is the lines that differ after it.
tree_sums() {
	find . -type f 2> /dev/null | while IFS= read -r _ts_f; do
		cksum "$_ts_f" 2> /dev/null
	done | LC_ALL=C sort || :
}

# unseen_compiles MADE: $AUX/recipe_unseen, the objects in the file MADE
# (made_objects) that no compile in $AUX/recipe_all accounts for -- none
# names a source of that object's name -- where the tree holds a source of
# that name, so a compile of it made them. Both records -- the trace or the
# plan, and the stand-ins on PATH -- see a compiler called by name; one
# called by its full path (/usr/bin/gcc) while the trace is off (set +x, a
# block with its stderr sent away), or inside a loop make -n prints but
# does not expand, escapes both. Its object does not: what made it went
# unjudged, and the check says so rather than claim every compile was seen.
unseen_compiles() {
	awk -F'\t' '$1 == "ok" || $1 == "bad" {
		n = split($4, w, " ")
		for (i = 1; i <= n; i++) if (w[i] ~ /\.c$/) { s = w[i]; sub(/.*\//, "", s); sub(/\.c$/, "", s); print s }
	}' "$AUX/recipe_all" | sort -u > "$AUX/seen_stems"
	while IFS= read -r _uo; do
		[ -n "$_uo" ] || continue
		_us=${_uo##*/}
		_us=${_us%.o}
		grep -qxF -- "$_us" "$AUX/seen_stems" && continue
		[ -n "$(find . -type f -name "$_us.c" 2> /dev/null | head -n 1)" ] || continue
		printf '%s\n' "$_uo"
	done < "$1" > "$AUX/recipe_unseen"
	[ -s "$AUX/recipe_unseen" ] || return 0
	echo "make_test.sh: NOTE — $(wc -l < "$AUX/recipe_unseen" | tr -d ' ') object(s) were made by a compile neither record saw:"
	rl_excerpt "$AUX/recipe_unseen" 10 unseen-objects.txt
	echo "  A compiler run by its full path while the trace is off, or inside a loop"
	echo "  'make -n' prints but does not expand, is seen by neither the plan (or"
	echo "  trace) nor the stand-ins on PATH. Those compiles were not judged: run"
	echo "  the compiler by its name, cc, where its commands can be read."
}

# plan_compiles: $AUX/recipe_all, the compile commands of a bare `make`, and
# DRY_RC, the status of `make -n`. Two records, as the --script arm has two.
# What `make -n` PLANS, into $DRY, on the clean tree. And what a build RAN:
# a compile in a shell loop, fed by xargs or run from $(shell ...) names its
# .c only once the shell has expanded it, so the plan shows the loop and no
# compile at all, and gcc in one passed the recipe check unseen. So a COPY of
# the clean tree is built once, with a stand-in for each compiler first on
# PATH (cc_shims), and every compile a stand-in logged that the plan does not
# show is judged with the rest. A copy, never the tree: every check after
# this one reads the tree as it was before any build, the build itself
# included. How that build ends is not judged here; the real one is.
plan_compiles() {
	mk "$DRY" - "make -n" "$MAKE_BIN" -n
	DRY_RC=$RC
	compile_cmds "$DRY" make > "$AUX/recipe_plan"
	rm -rf "$AUX/shimtree"
	mkdir "$AUX/shimtree" && cp -R "$WORK"/. "$AUX/shimtree"/ || {
		echo "make_test.sh: cannot copy the tree to build it with the compilers logged" >&2
		exit 2
	}
	cc_shims
	_pc_path=$PATH
	PATH="$AUX/ccshim:$PATH"
	export PATH
	cd "$AUX/shimtree" || { echo "make_test.sh: cannot enter the copy of the tree" >&2; exit 2; }
	made_objects "$AUX/shimtree" /dev/null > "$AUX/shim_before"
	tree_sums > "$AUX/shim_sums_before"
	mk "$AUX/shimbuild" - "make" "$MAKE_BIN"
	made_objects "$AUX/shimtree" "$AUX/shim_before" > "$AUX/shim_made"
	# Every file the build wrote or changed, by its last component, for
	# merge_compiles' phantoms. By content, not by time (made_objects).
	tree_sums | LC_ALL=C comm -13 "$AUX/shim_sums_before" - |
		awk '{ p = $0; sub(/^[^ ]* [^ ]* /, "", p); sub(/.*\//, "", p); print p }' |
		sort -u > "$AUX/shim_written"
	# Whether the clean tree builds: decoy_verdict's last witness.
	SHIM_BUILT=0
	[ ! -f "$ARTIFACT" ] || SHIM_BUILT=1
	cd "$WORK" || { echo "make_test.sh: cannot go back to the scratch dir" >&2; exit 2; }
	PATH=$_pc_path
	export PATH
	rm -rf "$AUX/shimtree"
	RC=$DRY_RC
	compile_cmds "$AUX/ccshim.log" trace > "$AUX/recipe_shim"
	merge_compiles "$AUX/recipe_plan" "$AUX/recipe_shim" "$SHIM_BUILT" "$AUX/shim_written"
	unseen_compiles "$AUX/shim_made"
	if [ -s "$AUX/recipe_phantom" ]; then
		echo "make_test.sh: NOTE — $(wc -l < "$AUX/recipe_phantom" | tr -d ' ') line(s) 'make -n' printed read like a compile, and no"
		echo "  build ran them: text the Makefile prints (\$(info ...), \$(warning ...)),"
		echo "  not a command. Not judged:"
		awk -F'\t' '{ print "    " $3 }' "$AUX/recipe_phantom" | sort -u
	fi
	if [ -s "$AUX/recipe_hidden" ]; then
		echo "make_test.sh: NOTE — $(wc -l < "$AUX/recipe_hidden" | tr -d ' ') compile command(s) a bare 'make' ran are not in what"
		echo "  'make -n' printed (a loop, xargs or \$(shell ...) shows its compiles only"
		if [ "$MODE" = wildcards ]; then
			echo "  when it runs); they ran a compiler by name, and their sources count with"
			echo "  the rest."
		else
			echo "  when it runs); they ran a compiler by name, and are judged with the rest."
		fi
	fi
}

# recipe_fail: the FAIL for the compile commands compile_cmds judged bad (in
# $AUX/recipe_all), each with what is wrong with it, under the sentence the
# check applies. Exits 1.
recipe_fail() {
	grep '^bad' "$AUX/recipe_all" | awk -F'\t' '!seen[$3 FS $2]++ { print $3; print "      (" $2 ")" }' \
		> "$AUX/recipe_bad"
	_rb=$(grep -c '^bad' "$AUX/recipe_all")
	_rn=$(grep -c '^ok\|^bad' "$AUX/recipe_all")
	if [ "$RECIPE_CC" = ordered ]; then
		_rw="cc with -Wall -Wextra -Werror, in that order"
	else
		_rw="cc with -Wall, -Wextra and -Werror"
	fi
	{
		if [ -n "$SCRIPT" ]; then
			echo "make_test.sh: FAIL — $_rb of the $_rn compile command(s) 'sh $SCRIPT' ran do not"
		else
			echo "make_test.sh: FAIL — $_rb of the $_rn compile command(s) a bare 'make' runs do not"
		fi
		echo "  run $_rw:"
		rl_excerpt "$AUX/recipe_bad" 20 compile-commands.txt
		echo ""
		echo "  The sentence this applies:"
		say cc
		if [ "$MODE" = recipe ]; then
			echo "  It says how your work is compiled. That it binds the commands your"
			echo "  $BUILT_BY runs too is this harness's reading of it, never the"
			echo "  subject's, which is why this fails at strict and not at basic."
		fi
		# Only where the student's sources are compiled by layers of their
		# own: a Makefile turned in alone builds the grader's (--overlay).
		if [ -z "${OVERLAYS:-}" ]; then
			echo "  Nothing else here reads these commands: the compile layers build"
			echo "  your sources with flags of their own, so they stay green whatever"
			echo "  your $BUILT_BY says."
		fi
	} >&2
	exit 1
}

# recipe_ok: the line that says the compile commands were judged, and how
# many -- an OK further down says nothing about them otherwise.
recipe_ok() {
	if [ "$RECIPE_CC" = ordered ]; then
		_rw="cc with -Wall -Wextra -Werror, in that order"
	else
		_rw="cc with -Wall, -Wextra and -Werror"
	fi
	_rk=$(grep -c '^ok' "$AUX/recipe_all")
	if [ "$_rk" -eq 1 ]; then
		echo "make_test.sh: the one compile command $1 uses $_rw."
	else
		echo "make_test.sh: each of the $_rk compile commands $1 uses $_rw."
	fi
}

# ---------------------------------------------------- what the recipes SAY
# Runs BEFORE the build, and that is not a style choice: `make -n` on an
# already-built tree prints "Nothing to be done", so every check below would
# read an empty recipe list and fail a perfectly good Makefile. The tree is
# clean here -- c_make's glob excludes build products and the artifact was just
# removed -- so this is the one moment the full command list is visible.
#
# What make PLANNED, expanded: a variable assignment like CFLAGS = -Wall
# -Wextra -Werror is a perfectly good way to write this, and `make -n` prints
# the commands with it expanded, so the plan is read and not the file.
#
# make's own error is KEPT, and its status read. Both used to be thrown away,
# so a Makefile with no rule at all -- the stub every exercise starts from --
# was told its flags were in the wrong order, over an empty listing. The
# compile commands are only worth judging once make planned one.
#
# Every compile, not one. The check used to ask whether ANY line held cc and
# the flags, so a Makefile that compiled one file right and the rest with gcc
# passed (finding 097), and it ran for C 09 ex01 alone; it runs wherever the
# call site quotes a sentence about cc (--recipe-cc).
if [ "$MODE" = build ] && [ -z "$SCRIPT" ] && { [ -n "$RECIPE_CC" ] || [ "$GRAPH" = 1 ]; }; then
	plan_compiles
	# Nothing to judge. Where the build's own lesson is its compile commands
	# and their graph (--graph: C 09 ex01), a plan with no compile in it is the
	# finding. Elsewhere it is only nothing to judge: the build below says what
	# a Makefile that compiles nothing produced, and a recipe check that saw
	# no compile claims none was right.
	if ! grep -q '^ok\|^bad' "$AUX/recipe_all" && [ "$GRAPH" = 0 ]; then
		if [ "$DRY_RC" -eq 0 ]; then
			echo "make_test.sh: NOTE — no compile command was judged against the sentence about cc:"
			echo "  'make -n' planned no command that compiles a .c file, and a build ran none."
		else
			echo "make_test.sh: NOTE — no compile command was judged against the sentence about cc:"
			echo "  'make -n' could not plan a build (status $DRY_RC), and a build ran no compile."
		fi
	elif ! grep -q '^ok\|^bad' "$AUX/recipe_all"; then
		{
			if [ "$DRY_RC" -ne 0 ]; then
				echo "make_test.sh: FAIL — 'make -n' could not plan a build: it exited"
				echo "  with status $DRY_RC."
			else
				echo "make_test.sh: FAIL — 'make -n' planned no compile command, and a build"
				echo "  ran none: no command a bare 'make' runs compiles a .c file."
			fi
			echo "  make said:"
			excerpt "$DRY"
			if grep -q 'No targets' "$DRY"; then
				echo "  Your Makefile has no rule yet, so make has nothing to run."
				not_written_yet
			elif [ "$DRY_RC" -ne 0 ]; then
				# Not a stub: make read rules and could not follow them.
				# Its own error names the file or rule it stopped on.
				echo "  make stopped before it could list the commands it would run."
				echo "  Its error, above, names the file or the rule it stopped on."
			else
				default_goal
				echo "  A bare 'make' runs one rule, the default goal: the first rule in"
				echo "  the file. Here the default goal is '$GOAL'."
				not_written_yet
			fi
		} >&2
		exit 1
	fi
	if [ -n "$RECIPE_CC" ] && grep -q '^bad' "$AUX/recipe_all"; then
		recipe_fail
	fi
	if [ -n "$RECIPE_CC" ] && grep -q '^ok' "$AUX/recipe_all"; then
		recipe_ok "a bare 'make' runs"
	fi
	# `make -n` prints a recipe it would run even when silenced with @, but
	# the @ itself does not survive into that output -- so the raw file is
	# where this one has to be read. The targeted message for the usual
	# case; every other way of silencing a command (.SILENT, -s in MAKEFLAGS,
	# an @ that comes from a variable) is caught after the build, by what it
	# printed.
	AT=$(grep -n '^	[[:space:]]*@' Makefile 2> /dev/null | head -5)
	if [ "$GRAPH" = 1 ] && [ -n "$AT" ]; then
		{
			echo "make_test.sh: FAIL — some recipes are silenced with '@'."
			printf '%s\n' "$AT" | sed 's/^/    /'
			echo ""
			echo "  The sentence this applies:"
			say print
			echo "  A leading @ on a recipe line tells make to run the command without"
			echo "  echoing it. Remove the @."
		} >&2
		exit 1
	fi
fi

# ------------------------------------------ exNN_build_recipe (--recipe-only)
# The compile commands alone, where the sentence about cc is a reading of
# what binds the build (strict). For a Makefile, from what `make -n` plans
# on the clean tree. For a creator script (C 09 ex00's "will compile the
# source files appropriately"), from what the script RAN: `sh -x` prints
# every command after expansion, a loop's every turn, so a variable or a
# loop hides nothing -- and nothing is read from its text.
if [ "$MODE" = recipe ]; then
	if [ -n "$SCRIPT" ]; then
		cc_shims
		_path=$PATH
		PATH="$AUX/ccshim:$PATH"
		export PATH
		made_objects . /dev/null > "$AUX/script_before"
		mk "$LOG" "$AUX/trace" "sh -x $SCRIPT" sh -x "$SCRIPT"
		PATH=$_path
		export PATH
		made_objects . "$AUX/script_before" > "$AUX/script_made"
		compile_cmds "$AUX/trace" trace > "$AUX/recipe_trace"
		compile_cmds "$AUX/ccshim.log" trace > "$AUX/recipe_shim"
		# Every compile the trace shows, and every one a stand-in logged
		# that it does not.
		merge_compiles "$AUX/recipe_trace" "$AUX/recipe_shim"
		if [ -s "$AUX/recipe_hidden" ]; then
			echo "make_test.sh: NOTE — $(wc -l < "$AUX/recipe_hidden" | tr -d ' ') compile command(s) 'sh $SCRIPT' ran are not in"
			echo "  its trace (sh -x); they ran a compiler by name, and are judged with the rest."
		fi
		unseen_compiles "$AUX/script_made"
		_none="'sh $SCRIPT' ran no command that compiles a .c file (it exited with status $RC)"
		[ ! -s "$AUX/recipe_unseen" ] ||
			_none="'sh $SCRIPT' made object(s) by no compile either record saw (the NOTE above)"
	else
		plan_compiles
		_none="neither 'make -n' (it exited with status $DRY_RC) nor a build planned or ran a command that compiles a .c file"
		[ ! -s "$AUX/recipe_unseen" ] ||
			_none="a build made object(s) by no compile 'make -n' or the stand-ins saw (the NOTE above)"
	fi
	if ! grep -q '^ok\|^bad' "$AUX/recipe_all"; then
		[ "${NO_SKIP:-0}" != "1" ] || {
			echo "NO_SKIP set: $_none, so there was no compile command to judge; $T_BUILD says why." >&2
			exit 1
		}
		echo "SKIP — $_none, so there is no compile command to judge; $T_BUILD says why."
		exit 0
	fi
	grep -q '^bad' "$AUX/recipe_all" && recipe_fail
	if [ -n "$SCRIPT" ]; then
		recipe_ok "'sh $SCRIPT' ran"
	else
		recipe_ok "a bare 'make' runs"
	fi
	echo "make_test.sh: OK"
	exit 0
fi

# -------------------------------------- exNN_build_wildcards (--wildcards-only)
# The Norm's "no *.c, no *.o", asked of the Makefile the only way it can be
# without reading its text: a source nobody named, and an object nobody
# built, each put where a pattern would find it. The DECOY goes beside every
# source the Makefile compiles (the directories of the .c files `make -n`
# plans and a build runs -- plan_compiles -- as the grader's own files could
# sit beside yours); a Makefile that names its sources never touches it, and
# one that takes *.c compiles it -- and the decoy is an #error that says so. The FOREIGN OBJECT goes beside
# the objects the build made, before each cleaning rule (see ensure_foreign).
DECOY="zz_harness_decoy_not_in_your_makefile.c"
if [ "$MODE" = wildcards ]; then
	plan_compiles
	# Every .c operand of a compile planned or run, as a directory of this
	# tree.
	awk -F'\t' '$1 == "ok" || $1 == "bad" { print $3 }' "$AUX/recipe_all" |
		tr ' \t;&|()' '\n\n\n\n\n\n\n' | sed -n 's/^["'\'']*\(.*\.c\)["'\'']*$/\1/p' |
		while IFS= read -r _c; do
			_d=$(dirname "$_c")
			case "$_d" in /* | .. | ../* | */.. | */../*) continue ;; esac
			[ -d "$_d" ] && printf '%s\n' "$_d"
		done | sort -u > "$AUX/decoy_dirs"
	if [ ! -s "$AUX/decoy_dirs" ]; then
		[ "${NO_SKIP:-0}" != "1" ] || {
			echo "NO_SKIP set: neither 'make -n' (it exited with status $DRY_RC) nor a build planned or ran a command that compiles a .c file, so there was nowhere to put a decoy; $T_BUILD says why." >&2
			exit 1
		}
		echo "SKIP — neither 'make -n' (it exited with status $DRY_RC) nor a build planned or ran a command that compiles a .c file, so there is nothing to judge; $T_BUILD says why."
		exit 0
	fi
	while IFS= read -r _d; do
		{
			echo "/* Put here by the harness, not by you: a source your Makefile was never"
			echo " * told about, beside the ones it compiles. */"
			echo "#error \"your Makefile compiled a source it does not name: the Norm asks for every source to be named (no *.c)\""
		} > "$_d/$DECOY"
	done < "$AUX/decoy_dirs"
fi

# decoy_verdict: after the build under --wildcards-only. A build that
# compiled the decoy compiled a source nobody named: FAIL, quoting the
# sentence. What says it did is the COMPILE, never the decoy's name: the name
# alone was matched anywhere in make's output once, so a default goal that
# ran `ls` failed for listing it. Three witnesses, any one enough --
#   the compiler's own error for the decoy's #error, at its file and line
#     (`zz_...c:3:2: error:`), which no listing prints;
#   a compile make printed that names it as an operand (compile_cmds over
#     the lines that name it), for a compiler whose errors go elsewhere;
#   and, for a recipe that is silent and sends its errors away, a clean copy
#     of this tree that built '$ARTIFACT' (plan_compiles' build, before any
#     decoy was laid) where this tree, which differs by the decoy alone,
#     built nothing.
decoy_verdict() {
	_dw=""
	_dre=$(printf '%s' "$DECOY" | sed 's/\./\\./g')
	if grep -qE "$_dre:[0-9]+(:[0-9]+)?: (fatal )?error" "$LOG"; then
		_dw="its #error is in make's output, above"
	elif grep -F "$DECOY" "$LOG" > "$AUX/decoy_lines" &&
		compile_cmds "$AUX/decoy_lines" make | awk -F'\t' -v d="$DECOY" '
			{
				n = split($4, w, " ")
				for (i = 1; i <= n; i++)
					if (w[i] == d || substr(w[i], length(w[i]) - length(d)) == "/" d) f = 1
			}
			END { exit !f }'; then
		_dw="the command that compiled it is in make's output, above"
	elif [ "$SHIM_BUILT" = 1 ] && [ ! -f "$ARTIFACT" ]; then
		_dw="the same tree without it built '$ARTIFACT', and with it the build failed"
	fi
	[ -n "$_dw" ] || return 0
	{
		echo "make_test.sh: FAIL — your Makefile compiled a source it was never told about."
		echo "  Before the build, a decoy source was put beside yours:"
		sed "s#\$#/$DECOY#; s#^\\./##; s#^#    #" "$AUX/decoy_dirs"
		echo "  and the build compiled it: $_dw."
		echo "  A Makefile that names each of its sources never meets it; one that"
		echo "  takes every .c it finds compiles whatever is there."
		echo ""
		echo "  The sentence this applies:"
		say wildcards
		echo "  Your subject does not say it outright; the Norm, which your work must"
		echo "  follow, does, for every Makefile. So this fails at strict."
	} >&2
	exit 1
}

# The tree as it stood before the build, so that "built nothing" can be told
# apart from "built something under another name" afterwards.
find . -type f | sort > "$BEFORE"

# Into $LOG and then shown, rather than straight to the log: what it said is
# read below, to name a Makefile with no rule at all.
if [ -n "$SCRIPT" ]; then
	mk "$LOG" - "sh $SCRIPT" sh "$SCRIPT"
else
	mk "$LOG" - "make" "$MAKE_BIN"
fi
cat "$LOG"

# The decoy, read first (exNN_build_wildcards): a build that stopped on it
# compiled a source nobody named.
[ "$MODE" != wildcards ] || decoy_verdict

# Every target but exNN_build judges runs that did their job. A build that
# produced no '$ARTIFACT' did not, whatever it exited with, and every rule
# step needs the tree it would have built: exNN_build is the finding here,
# and says why. Under NO_SKIP=1 the stand-down is red, so a layer that
# stood down everywhere cannot read as one that passed -- and that red
# names exNN_build as the SKIP does: the mutation run of 2026-10-03 found
# C 09 ex01's build_exit red under NO_SKIP over a globbed source list,
# saying only that nothing could be judged (c09b M6), where the finding is
# the build's.
if [ "$MODE" != build ] && [ ! -f "$ARTIFACT" ]; then
	[ "${NO_SKIP:-0}" != "1" ] || {
		echo "NO_SKIP set: '$BUILDER' built no '$ARTIFACT' (it exited with status $RC), so no run had a job done that this target could judge; $T_BUILD says why." >&2
		exit 1
	}
	echo "SKIP — '$BUILDER' built no '$ARTIFACT' (it exited with status $RC), so no run did its job; $T_BUILD says why."
	exit 0
fi

# Built nothing AND exited non-zero: the build failed, and make's own error
# is above.
if [ "$RC" -ne 0 ] && [ ! -f "$ARTIFACT" ]; then
	{
		echo "make_test.sh: FAIL — '$BUILDER' exited with status $RC and did not produce"
		echo "  '$ARTIFACT' (its output is above)."
		if [ -z "$SCRIPT" ] && grep -q 'No targets' "$LOG"; then
			echo "  Your Makefile has no rule yet, so make has nothing to run."
			not_written_yet
		fi
	} >&2
	exit 1
fi

if [ ! -f "$ARTIFACT" ]; then
	if [ -n "$SCRIPT" ]; then
		echo "make_test.sh: FAIL — '$BUILDER' ran but did not produce '$ARTIFACT'." >&2
	else
		echo "make_test.sh: FAIL — 'make' succeeded but did not produce '$ARTIFACT'." >&2
	fi

	# The overwhelmingly common cause is a name that is nearly right: a hyphen
	# dropped, an underscore instead, a capital. `make` is perfectly happy and
	# every other layer here goes green, because they compile the sources
	# themselves and never look at what the Makefile named its output. The
	# Moulinette looks for the name the subject gave, so a near miss is a zero.
	#
	# Comparing on letters and digits alone -- punctuation and case discarded --
	# is what turns "there is no rush-02" into "you built rush02", which is the
	# difference between a puzzle and a fix.
	SQUASH=$(printf '%s' "$ARTIFACT" | tr -d '_-' | tr 'A-Z' 'a-z')
	NEAR=""
	for f in *; do
		[ -f "$f" ] || continue

		# Sources and objects are excluded, not "everything that is not
		# executable": c_make is also used where the artifact is an archive,
		# and libft.a carries no execute bit, so a check for one would go
		# quiet on exactly the modules that build a library.
		case "$f" in *.o | *.c | *.h) continue ;; esac
		if [ "$(printf '%s' "$f" | tr -d '_-' | tr 'A-Z' 'a-z')" = "$SQUASH" ]; then
			NEAR="$f"
			break
		fi
	done

	# What the build created: the tree now, less the tree before it. Empty
	# means nothing was built at all -- a stub, or a first rule that is not the
	# one that builds -- which is not a naming problem, and used to be reported
	# as one ("check the target ... your rule actually names").
	find . -type f | sort > "$AFTER"
	NEW=$(grep -vxF -f "$BEFORE" "$AFTER" | sed 's|^\./||')

	if [ -n "$NEAR" ]; then
		echo "" >&2
		echo "  It built './$NEAR' instead. Those differ only in punctuation or" >&2
		echo "  case, so this is a naming mismatch and not a build problem: the" >&2
		echo "  subject gives the name '$ARTIFACT', and that spelling is the one" >&2
		echo "  looked for $(rl_at)." >&2
		echo "" >&2
		echo "  Nothing else here can catch this. Every other layer compiles" >&2
		echo "  your sources itself and never asks what your $BUILT_BY called its" >&2
		echo "  output, so they all stay green while this is wrong." >&2
	elif [ -z "$NEW" ]; then
		{
			echo ""
			echo "  It created no file at all: nothing was built."
			if [ -z "$SCRIPT" ]; then
				default_goal
				echo "  A bare 'make' runs one rule, the default goal: the first rule in"
				echo "  the file. Here the default goal is '$GOAL', and nothing it ran"
				if [ "$GOAL" = "$ARTIFACT" ]; then
					echo "  created a file -- not even '$ARTIFACT', which it is named after."
				else
					echo "  created a file. Is that the rule that builds '$ARTIFACT'?"
				fi
			fi
			not_written_yet
		} >&2
	else
		{
			echo ""
			echo "  It created these files, and none of them is named '$ARTIFACT':"
			printf '%s\n' "$NEW" > "$AUX/new"
			rl_excerpt "$AUX/new" 20 new-files.txt
			echo "  Compare the name the subject gives with the one your $BUILT_BY"
			echo "  gives its output."
		} >&2
	fi
	exit 1
fi

# It built '$ARTIFACT'. Whether it also exited 0 is the run contract's question.
BUILD_RC=$RC
status_note "$BUILDER" "built '$ARTIFACT', and"

if [ -n "$SYMS" ] && [ "$MODE" = build ]; then
	# AN ARCHIVE WITH NO MEMBER is news of its own. `ar rcs libft.a` over a
	# source list that came out empty still writes the archive -- its magic
	# line and nothing after it -- and the check below then said only that
	# the first symbol was missing, leaving the student to infer from a bare
	# `ar` line that nothing had been compiled at all. Read from the file,
	# by the format: an archive is its 8-byte magic line followed by its
	# members, so one of 8 bytes holds none. Where the sources should be is
	# not said here: that is the exercise's question (its hints ask it).
	case "$(head -c 8 "$ARTIFACT" 2> /dev/null)" in
		'!<arch>' | '!<thin>')
			if [ "$(wc -c < "$ARTIFACT" | tr -d ' ')" -le 8 ]; then
				{
					echo "make_test.sh: FAIL — '$BUILDER' built '$ARTIFACT', and it is an empty archive:"
					echo "  not one object file went into it, so none of the functions the"
					echo "  subject asks for is there. The command that made it is in the"
					echo "  output above: which files did it put in the archive, and which"
					echo "  source files did your $BUILT_BY compile before it?"
				} >&2
				exit 1
			fi ;;
	esac
	for s in $(echo "$SYMS" | tr ',' ' '); do
		if ! "$NM" "$ARTIFACT" 2> /dev/null | grep -qE "[Tt] $s\$"; then
			echo "make_test.sh: symbol '$s' missing from '$ARTIFACT'" >&2
			exit 1
		fi
	done
fi

# EVERY COMMAND PRINTED (--graph: C 09 ex01's "should print all the commands
# it's running"). Asked of what make PRINTED while it built, never of the
# Makefile's text: each command make planned (`make -n`, above; its own
# messages left out) has to be a line of what the real build printed, as
# make prints every command it runs unless told not to. The @ check above
# reads the text for the usual case; this one sees every other way of
# running a command without printing it -- .SILENT, -s in MAKEFLAGS, an @
# that a variable expands to -- which the text check could not (finding 101).
#
# A command is seen when a line of the build log ENDS with it, not only when
# a line IS it: a command whose output ends without a newline (printf
# "archiving: ", echo -n) leaves make to print the next command on the end
# of that line, and an exact match then failed a Makefile that printed every
# command, saying it had not.
if [ "$MODE" = build ] && [ "$GRAPH" = 1 ] && [ -z "$SCRIPT" ]; then
	grep -v '^[^ ]*make\(\[[0-9]*\]\)\{0,1\}: ' "$DRY" | awk 'NF && !seen[$0]++' > "$AUX/planned"
	awk 'FILENAME == ARGV[1] { want[++n] = $0; next }
		{
			for (i = 1; i <= n; i++) {
				if (i in found) continue
				L = length(want[i])
				if (length($0) >= L && substr($0, length($0) - L + 1) == want[i]) found[i] = 1
			}
		}
		END { for (i = 1; i <= n; i++) if (!(i in found)) print want[i] }' \
		"$AUX/planned" "$LOG" > "$AUX/unseen"
	if [ -s "$AUX/unseen" ]; then
		{
			echo "make_test.sh: FAIL — 'make' ran commands without printing them:"
			rl_excerpt "$AUX/unseen" 20 unprinted-commands.txt
			echo "  Each was planned by 'make -n' and is not a line of what the build"
			echo "  printed (above)."
			echo ""
			echo "  The sentence this applies:"
			say print
			echo "  What tells make to run a command without echoing it? A leading @ is"
			echo "  one way; a special target and a flag are others."
		} >&2
		exit 1
	fi
fi

# ---------------------------------------------------------------- make hygiene
# Everything below asks about the RULES of the build, so it runs for the Makefile
# arm only. --script is c-09 ex00, whose answer is a shell script: it has no
# all/clean/fclean/re to invoke and no notion of "already up to date", so putting
# it through any of this would red an exercise for not doing something its
# subject never asked for. Hence the guard.
#
# Why this block carries so much weight: ex00 and ex01 build the SAME five
# sources into the SAME libft.a (ex01's are the grader's, staged by --overlay),
# and the only thing ex01 adds is the dependency graph. Assert only "libft.a
# exists and exports five names" and a single `all:` recipe that recompiles
# and re-archives everything on every run is
# byte-for-byte as green as a real Makefile — i.e. the one thing this exercise
# teaches would be the one thing nothing looks at, and a student could finish it
# having learned nothing ex00 had not already taught them.
if [ -z "$SCRIPT" ]; then
	# A literal newline, for accumulating report lines in a variable.
	NL='
'

	# THE GATE below covers checks 1 and 2 together, because they are the same
	# two-sided lesson and because they come from the same place: they are
	# requirements that ONLY c-09 ex01's subject makes. Verbatim, three separate
	# bullets —
	#     "Your Makefile should not run any unnecessary commands."
	#     "Your Makefile should not compile any file unnecessarily."
	#     ".o files should be near their corresponding .c files."
	# — the first two saying the same thing twice, which is a fair signal of where
	# the grade lives.
	#
	# This runner is shared, and the other module on it asks for none of that.
	# c-10 ex00-03 are Makefile-arm exercises whose subject says only "The
	# submission directory should contain a Makefile with the following rules:
	# all, clean, fclean": no word on relinking, no word on where objects land.
	# Each builds ONE source file, the module's own stub hands the student an
	# `all:` with no prerequisites so the most literal way to fill it in always
	# relinks, and putting that single object in an obj/ subdirectory is a
	# perfectly good answer there. Red-ing either would fail an exercise for
	# disobeying a requirement its subject never made — worse than the hole these
	# checks close — and it would do it while quoting c-09's subject at a student
	# reading c-10's, which is worse still.
	#
	# So both are gated, and the gate is the CALLER's: c-09 ex01's c_make call
	# passes graph = True (five sources under the grader's srcs/, where "do not
	# recompile what did not change" is the entire lesson), c-10's do not (a
	# single translation unit, where there is no graph to get wrong).
	#
	# This used to be inferred from `find . -name '*.c' | wc -l` being > 1. That
	# proxy was replaced rather than kept because it is invisible and it drifts:
	# it happens to select c-09 today only because c-10's exercises have one
	# source each, and it would arm itself against any module the day a team split
	# their code across files — rush-02, whose subject is literally "Makefile and
	# all the necessary files" for a team of several, would have tripped it the
	# first time anyone added a second .c, and been told off in c-09's words for
	# breaking a rule its own subject never states. What a subject demands is not
	# something to deduce from a file count; it is something the BUILD file knows.
	if { [ "$GRAPH" = 1 ] || [ "$RELINK" = 1 ]; } && [ "$MODE" = build ]; then
		# 1. NO UNNECESSARY WORK.
		#
		# How it is observed: the build above already produced everything, so a
		# second `make` has nothing legitimate to do. Drop a reference file, run
		# make again, and ask the filesystem which files came out with an mtime
		# later than that reference. Those, and only those, are work the second
		# run did.
		#
		# Why timestamps rather than reading make's output: "Nothing to be done
		# for 'all'" is GNU make's wording, BSD make phrases it differently, and
		# a student who prefixes their recipes with @ prints nothing either way.
		# An mtime is the same observable fact under every implementation.
		#
		# Why the sleep: it makes the comparison independent of the filesystem's
		# timestamp resolution (10ms on the devcontainer's overlayfs, a whole
		# second on some others). After a full second, anything make rewrites is
		# unambiguously newer than the reference, so a coarse clock can no longer
		# hide a rebuild. It costs one second here, and one more in the re step
		# below, which asks the same kind of question.
		#
		# A second run that exits non-zero is a FAIL here only when the first
		# one exited 0: then the second did something the first did not, on a
		# tree with nothing left to do. When the first exited non-zero too, the
		# second is the same behaviour, already noted above by the run contract.
		touch "$REF"
		sleep 1
		mk "$LOG" - "make" "$MAKE_BIN"
		if [ "$RC" -ne 0 ] && [ "$BUILD_RC" -eq 0 ]; then
			{
				echo "make_test.sh: FAIL — running 'make' a second time failed."
				echo "  The first build succeeded, so this is make being asked to"
				echo "  bring an already-built tree up to date and erroring anyway."
				echo "  Read the log below, then ask what the first run left behind"
				echo "  that the second one did not expect to find."
				rl_excerpt "$LOG" 20 make-second-run.txt
			} >&2
			exit 1
		fi
		REDONE=$(find . -type f -newer "$REF" 2> /dev/null | sed 's|^\./||' | sort)
		if [ -n "$REDONE" ]; then
			{
				echo "make_test.sh: FAIL — 'make' redid work that was already done."
				echo "  Nothing changed between the two runs, and the second one"
				echo "  still rewrote:"
				printf '%s\n' "$REDONE" | sed 's/^/    /'
				if [ "$GRAPH" = 1 ]; then
					echo "  The sentences this applies:"
					say unnecessary
					echo "  A shell script can produce the same archive, but it rebuilds"
					echo "  everything every time: it has no way to know what is already"
					echo "  current. A Makefile can know."
				elif [ "$RELINK_SOURCE" = norm ]; then
					echo "  Your subject does not say it; the Norm, which covers every"
					echo "  Makefile you turn in, does:"
					say relink
					echo "  Running make twice with nothing changed in between must do"
					echo "  nothing the second time."
				else
					echo "  The sentence this applies:"
					say relink
					echo "  Running make twice with nothing changed in between must do"
					echo "  nothing the second time."
				fi
				echo "  So: for ONE target, what two things does make compare to"
				echo "  decide whether its recipe has to run at all? And what does"
				echo "  it therefore have to be told about every file your build"
				echo "  produces — not just about the archive at the end?"
			} >&2
			exit 1
		fi
	fi

	if [ "$GRAPH" = 1 ] && [ "$MODE" = build ]; then

		# 2. WHERE THE OBJECTS LIVE. Same lesson from the other side: naming the
		#    object after the source it came from, in the source's own directory,
		#    is what lets a single rule stand for all five files.
		#
		#    Judged conservatively on purpose (a layer that reds a CORRECT answer
		#    is worse than the hole it closes):
		#      - an .o with a same-named .c in its own directory  -> fine;
		#      - an .o with no same-named .c anywhere             -> not judged, it
		#        is not this layer's business what else a build produces;
		#      - only an .o whose .c demonstrably lives somewhere ELSE is reported.
		#    A build that leaves no .o at all is not reported here either — check 1
		#    above already has everything to say about that shape.
		OBJS=$(find . -type f -name '*.o' 2> /dev/null | sed 's|^\./||' | sort)
		MISPLACED=""
		for o in $OBJS; do
			d=$(dirname "$o")
			b=$(basename "$o" .o)
			[ -f "$d/$b.c" ] && continue
			c=$(find . -type f -name "$b.c" 2> /dev/null | sed 's|^\./||' | head -1)
			[ -n "$c" ] || continue
			MISPLACED="$MISPLACED    $c  ->  $o$NL"
		done
		if [ -n "$MISPLACED" ]; then
			{
				echo "make_test.sh: FAIL — the .o files are not near their .c files."
				echo "  Each of these sources produced an object somewhere else:"
				printf '%s' "$MISPLACED"
				echo "  The sentence this applies:"
				say objects
				echo "  Where an object lands is not the compiler's decision to make by"
				echo "  default — it is yours, and you state it in the rule that builds"
				echo "  the object. Look at how a rule names the file it produces versus"
				echo "  the file it reads, and at what that naming buys you once you want"
				echo "  ONE rule to cover every source in the directory."
			} >&2
			exit 1
		fi

		# 2b. ONE SOURCE CHANGED, ONE OBJECT REBUILT. Check 1 sees the tree
		#     with nothing changed, which a Makefile that makes every object
		#     depend on every source also passes: it is up to date until one
		#     file changes, and then it compiles them all (finding 099). So
		#     each source that has its object beside it is touched in turn,
		#     and make run again: the object of that source is the only one
		#     it may rebuild. EACH, not the first found: a rule that ties
		#     every object to one source (main.o: main.c $(SRCS)) rebuilds
		#     one object when that source changes and all of them when any
		#     other does, and the first pair found was often the one that
		#     passed. At most TOUCH_MAX (12) pairs, a second each, so a
		#     large project's test stays inside its time. Only objects are
		#     judged -- the archive is rewritten, rightly -- and a tree with
		#     no source and object side by side is not judged here (check 2
		#     has said what it has to about where objects go).
		TOUCH_MAX=12
		PAIRS=""
		_np=0
		# Every pair there is, touched or not: the cap is said only where
		# it left one untouched, never for an object no source sits beside.
		_npairs=0
		for o in $OBJS; do
			[ -f "${o%.o}.c" ] || continue
			_npairs=$((_npairs + 1))
			[ "$_np" -lt "$TOUCH_MAX" ] || continue
			_np=$((_np + 1))
			rl_list_add PAIRS "$o"
		done
		_touched=""
		# The sources whose touch rebuilt their own object and no other,
		# which the FAIL names as what came before it -- not every source
		# touched: one whose run showed nothing (make stopped, or rebuilt
		# no object) is _unseen's.
		_alone=""
		_unseen=""
		_rebuilt=0
		rl_split_on
		for PAIR in $PAIRS; do
			# The list is expanded; what runs below (mk, rl_run) splits
			# words the ordinary way.
			rl_split_off
			touch "$REF"
			sleep 1
			touch "${PAIR%.o}.c"
			mk "$LOG" - "make" "$MAKE_BIN"
			OTHERS=$(find . -type f -name '*.o' -newer "$REF" 2> /dev/null |
				sed 's|^\./||' | grep -vxF -- "$PAIR" | sort)
			if [ -n "$OTHERS" ]; then
				{
					echo "make_test.sh: FAIL — one source changed, and 'make' recompiled others."
					echo "  After a full build, only ${PAIR%.o}.c was touched, and 'make' then"
					echo "  rebuilt these objects as well as ${PAIR}:"
					printf '%s\n' "$OTHERS" | sed 's/^/    /'
					[ -z "$_alone" ] ||
						echo "  (Touched before it, one at a time, each rebuilding its own object alone:$_alone.)"
					[ -z "$_unseen" ] ||
						echo "  (Touched before it too, with what is rebuilt not seen:$_unseen.)"
					echo ""
					echo "  The sentences this applies:"
					say unnecessary
					echo "  What does the rule that makes each object say it depends on, and"
					echo "  what does its recipe compile?"
				} >&2
				exit 1
			fi
			# What the run showed, and no more: a rule for the object that
			# does not name its source rebuilds nothing when the source
			# changes, and a make that stopped rebuilt what it reached.
			# Either way "only its object" was not seen for that source.
			if [ "$RC" -ne 0 ]; then
				_unseen="$_unseen ${PAIR%.o}.c ('make' exited with status $RC)"
			elif [ -z "$(find "$PAIR" -newer "$REF" 2> /dev/null)" ]; then
				_unseen="$_unseen ${PAIR%.o}.c ('make' rebuilt no object, not even ${PAIR})"
			else
				_rebuilt=$((_rebuilt + 1))
				_alone="$_alone ${PAIR%.o}.c"
			fi
			_touched="$_touched ${PAIR%.o}.c"
		done
		rl_split_off
		if [ "$_np" -gt 0 ]; then
			TOUCHED="$_np source(s) touched, one at a time:$_touched."
			if [ "$_rebuilt" -gt 0 ]; then
				TOUCHED="$TOUCHED $_rebuilt rebuilt only their own object."
			fi
			if [ -n "$_unseen" ]; then
				TOUCHED="$TOUCHED Whether only its object is rebuilt was not seen for:$_unseen."
			fi
			if [ "$_npairs" -gt "$_np" ]; then
				TOUCHED="$TOUCHED (At most $TOUCH_MAX of the $_npairs are touched, a second each.)"
			fi
		else
			TOUCHED="No object sits beside its source, so no source was touched to see what is rebuilt."
		fi
	fi

	# THE RULE STEPS. Each one SETS UP ITS OWN START STATE and says what it
	# needs, instead of inheriting whatever the step before it left behind.
	# They used to be chained -- fclean emptied the tree, `make all` refilled
	# it, `re` ran on that and was judged by the artifact being there -- so
	# the day `all` was checked between fclean and re, re's start state
	# silently became "fully built", and a Makefile with NO re rule passed
	# (Piscine Reloaded ex24). Each step also reads make's exit status and
	# output. Both used to go to /dev/null, so a missing rule was blamed on
	# what the rule does, and make's own one-line diagnosis was never shown.
	#
	# The exit status. A subject that asks for a rule says what the rule must
	# DO, never how it exits: a rule that did its job and still exited
	# non-zero -- the usual case is a clean that errors when there is nothing
	# left to remove -- goes through rule_note (the header's rule: a WARNING
	# here, a FAIL under --exit-only). A MISSING rule the subject mandates is a
	# FAIL, and so is a rule whose effect is wrong. Under --exit-only both are
	# still found -- run_rule finds the first, each step's own checks the
	# second, through job_not_done -- and the run is NOT JUDGED: it has no
	# exit status worth judging, and exNN_build reports what it did wrong.
	# Every effect check is guarded by JUDGE, so a run found wrong once is not
	# counted twice, and a cleaning rule's second run ("on a tree with nothing
	# to clean") is made only when its first was judged: only then is that
	# tree what the words say.
	LAST=""
	# Set when a rebuild under --exit-only made nothing: every step after
	# needs a built tree, so none of them runs (at basic that is a FAIL, and
	# the runner stops there as well).
	STUCK=0

	# run_rule RULE: run `make RULE` from the tree as it stands, into $LOG,
	# with its status in $RC. A rule the Makefile does not have stops here, in
	# make's words (the pinned GNU make's wording is stable). Under
	# --exit-only it is NOT JUDGED instead: a missing rule is exNN_build's
	# finding, and the exit status make gives it is make's own error, not
	# the rule's.
	#
	# Missing has a second shape: a rule named in .PHONY and defined nowhere
	# else. make knows the name, finds nothing to do for it, says "Nothing to
	# be done for 're'" and exits 0 -- which read as a re that ran, and was
	# then blamed on what re did. Told apart by make's own database, where
	# such a target has neither a prerequisite nor a recipe.
	#
	# JUDGE says whether rule_note judges this run's status; a step's own
	# check can still clear it (an all that built nothing).
	run_rule() {
		LAST=$1
		JUDGE=1
		mk "$LOG" - "make $1" "$MAKE_BIN" "$1"
		if [ "$RC" -ne 0 ]; then
			grep -qF "No rule to make target '$1'." "$LOG" || return 0
			if [ "$MODE" != build ]; then
				not_judged "make $1" "your Makefile has no $1 rule (make said \"No rule to make target '$1'\")"
				return 0
			fi
			{
				echo "make_test.sh: FAIL — your Makefile has no $1 rule."
				echo "  Your subject lists '$1' among the rules your Makefile must have,"
				echo "  and 'make $1' stopped with make's own error:"
				excerpt
			} >&2
			exit 1
		fi
		grep -qF "Nothing to be done for '$1'" "$LOG" || return 0
		rule_is_empty "$1" || return 0
		if [ "$MODE" != build ]; then
			not_judged "make $1" "your Makefile names $1 but gives it no rule, so it did nothing"
			return 0
		fi
		{
			echo "make_test.sh: FAIL — your Makefile has no $1 rule."
			echo "  Your subject lists '$1' among the rules your Makefile must have."
			echo "  Your Makefile names '$1' (in .PHONY, say) but gives it no rule of"
			echo "  its own: no prerequisite and no recipe. So 'make $1' did nothing"
			echo "  and exited 0. make said:"
			excerpt
			echo "  Declaring a target phony says it is not a file; what does make"
			echo "  still need before it has anything to run for it?"
		} >&2
		exit 1
	}

	# rule_is_empty RULE: 0 when make's database has RULE as a target with no
	# prerequisite and no recipe. -p prints the database, -q runs no recipe,
	# and the goal .DEFAULT is one no rule step uses; only its "# Files"
	# section is read, and a "# Not a target:" entry is not one.
	rule_is_empty() {
		mk "$AUX/db" /dev/null "make -npq .DEFAULT" "$MAKE_BIN" -npq .DEFAULT
		awk -v t="$1" '
			/^# Files/ { files = 1; next }
			!files { next }
			inb && /^$/ { exit }
			inb && /^#  recipe to execute/ { recipe = 1; next }
			inb { next }
			/^# Not a target:/ { nt = 1; next }
			index($0, t ":") == 1 && !nt {
				rest = substr($0, length(t) + 2)
				if (rest ~ /^:/) exit
				inb = 1; found = 1
				if (rest !~ /^[ \t]*$/) prereq = 1
				next
			}
			{ nt = 0 }
			END { exit !(found && !prereq && !recipe) }' "$AUX/db"
	}

	# make_said RULE, inside a FAIL message: what make printed, so the student
	# sees what the rule actually ran. When it exited non-zero that comes
	# with the status, because make's own error names the rule and the line
	# that stopped it -- which no check of the resulting files can.
	make_said() {
		if [ "$RC" -ne 0 ]; then
			echo "  'make $1' exited with status $RC. make said:"
		else
			echo "  This is what 'make $1' ran:"
		fi
		excerpt
		echo ""
	}

	# The start state most steps need: a fully built tree. A bare `make` is
	# how the build above produced one, and on an up-to-date tree it does
	# nothing. After a cleaning rule it is "make fclean then make", which is
	# how rush-02's subject builds. A rebuild that exits non-zero having
	# built it is the build's own status again (status_note says it once).
	#
	# A rebuild that made nothing did not do its job: a FAIL at basic, and
	# under --exit-only NOT JUDGED, with this step and every one after it left
	# unrun (STUCK), since each starts from a built tree. It returns 1 then,
	# so a step is written `if has_rule X && ensure_built X; then`. It used to
	# exit 1 with exNN_build's own message, in the exit twin.
	ensure_built() {  # ensure_built STEP
		[ "$STUCK" = 0 ] || return 1
		mk "$LOG" - "make" "$MAKE_BIN"
		if [ -f "$ARTIFACT" ]; then
			status_note "$BUILDER" "rebuilding '$ARTIFACT' for the $1 check"
			return 0
		fi
		if [ "$MODE" != build ]; then
			STUCK=1
			if [ -n "$LAST" ]; then
				not_judged "make" "it did not rebuild '$ARTIFACT' after 'make $LAST' (it exited with status $RC), so the $1 check and every rule check after it did not run"
			else
				not_judged "make" "it did not rebuild '$ARTIFACT' before the $1 check (it exited with status $RC), so that check and every rule check after it did not run"
			fi
			return 1
		fi
		{
			if [ -n "$LAST" ]; then
				echo "make_test.sh: FAIL — 'make' did not rebuild '$ARTIFACT' after 'make $LAST'."
				echo "  The first build produced it, so ask what 'make $LAST' removed or"
				echo "  left behind that a build cannot recover from."
			else
				echo "make_test.sh: FAIL — 'make' did not rebuild '$ARTIFACT' before the $1 check."
			fi
			echo "  The $1 check starts from a fully built tree, and a bare 'make' is"
			echo "  how it gets one. make said:"
			excerpt
		} >&2
		exit 1
	}

	# WHICH TARGET JUDGES WHAT A RULE DOES. A rule the subject lists has to
	# exist, at basic, always (run_rule). What clean, fclean and re DO is
	# judged at basic only where the subject defines it, with the sentence
	# quoted (--quotes: clean, fclean, re); a subject that lists a rule and
	# says nothing more -- C 10's "all, clean, fclean" -- leaves it to this
	# repo's convention, which exNN_build_rules applies at robust and says is
	# ours (finding 082: every message here used to quote C 09's definitions
	# at every project). exNN_build_exit reads every check, only to know
	# whether a run did its job; exNN_build_wildcards reads none of them.
	#
	# judged KEY...: whether this target judges a check that rests on the
	# definitions KEY... -- all quoted: exNN_build's; one missing:
	# exNN_build_rules'.
	judged() {
		case "$MODE" in
			exit) return 0 ;;
			wildcards) return 1 ;;
		esac
		_jd=1
		for _k in "$@"; do
			has_quote "$_k" && continue
			_jd=0
			[ "$MODE" = build ] || continue
			case " $DEFERRED_KEYS " in
				*" $_k "*) ;;
				*) DEFERRED_KEYS="${DEFERRED_KEYS:+$DEFERRED_KEYS }$_k" ;;
			esac
		done
		if [ "$MODE" = build ]; then
			[ "$_jd" = 0 ] || return 0
			case " $DEFERRED " in
				*" $LAST "*) ;;
				*) DEFERRED="${DEFERRED:+$DEFERRED }$LAST" ;;
			esac
			return 1
		fi
		[ "$_jd" = 0 ] || return 1
		CONV_CHECKS=$((CONV_CHECKS + 1))
		return 0
	}
	# basis RULE KEY...: under a FAIL, what the check applied -- the
	# subject's sentences where every KEY is quoted, or else this repo's
	# convention for RULE, said to be one.
	basis() {
		_b_rule=$1
		shift
		_b_all=1
		for _k in "$@"; do
			has_quote "$_k" || _b_all=0
		done
		if [ "$_b_all" = 1 ]; then
			echo "  The sentences this applies:"
			for _k in "$@"; do
				say "$_k"
			done
			return 0
		fi
		echo "  Your subject lists '$_b_rule' among the rules your Makefile must have, and"
		echo "  does not say all of what it does. So this is this repo's convention, which"
		echo "  it checks at robust and no grader is bound by:"
		case "$_b_rule" in
			clean) echo "clean removes the files the build made on the way to '$ARTIFACT' -- its objects -- and leaves '$ARTIFACT' itself." ;;
			fclean) echo "fclean does what clean does, and removes '$ARTIFACT' as well." ;;
			re) echo "re does what fclean does, then builds '$ARTIFACT' again." ;;
		esac | fold -s -w 68 | sed 's/ *$//; s/^/    /'
		for _k in "$@"; do
			has_quote "$_k" || continue
			echo "  What your subject does say:"
			say "$_k"
		done
	}

	# THE FOREIGN OBJECT (--foreign-object; under --wildcards-only, beside
	# every object the build made next to its source): a file that looks
	# like an object and that no rule of the Makefile made, put there just
	# before each cleaning rule runs. The grader's own files can sit where
	# yours do -- "We'll only fetch your Makefile and test it with our
	# files" -- and a clean that deletes by pattern (rm -f *.o) deletes
	# them too. It has to survive clean and fclean, and it is never among
	# the objects a rule is said to have left behind (finding 105).
	#
	# Under --wildcards-only it goes in every directory the build put an
	# object in: beside a source, and in an object directory of its own
	# (obj/). The second is the Makefile's to delete WHOLE -- `rm -rf obj`
	# names no file, so it is no pattern -- and a run that took the
	# directory with it is not judged; one that left the directory and took
	# the object (`rm -f obj/*.o`) deleted by pattern. It used to go beside
	# a source only, so an obj/ Makefile's pattern clean was never seen
	# (FOREIGN_WHOLE lists the planted objects whose directory may go).
	FOREIGN_WHOLE=""
	FOREIGN_TOOK_DIR=0  # cleaning runs that took every planted object with its directory
	if [ "$MODE" = wildcards ]; then
		find . -type f -name '*.o' 2> /dev/null | sed 's|^\./||' | while IFS= read -r _o; do
			dirname "$_o"
		done | sort -u | sed 's#$#/zz_graders_own_file.o#; s#^\./##' > "$AUX/foreign"
		FOREIGN=$(cat "$AUX/foreign")
		# The directories holding no source the build compiled beside its
		# objects: where a directory gone whole is not a pattern.
		FOREIGN_WHOLE=$(printf '%s\n' "$FOREIGN" | while IFS= read -r _f; do
			_fd=$(dirname "$_f")
			[ -n "$(find "$_fd" -maxdepth 1 -type f -name '*.c' 2> /dev/null | head -n 1)" ] ||
				printf '%s\n' "$_f"
		done)
	elif [ "$MODE" != build ]; then
		FOREIGN=""
	fi
	plant_foreign() {
		[ -n "$FOREIGN" ] || return 0
		printf '%s\n' "$FOREIGN" | while IFS= read -r _f; do
			mkdir -p "$(dirname "$_f")" &&
				printf 'not an object: a file of the grader'\''s, which no rule of yours made\n' > "$_f"
		done
	}
	# foreign_gone RULE: FAIL when RULE's run deleted a planted object.
	foreign_gone() {
		[ -n "$FOREIGN" ] || return 0
		[ "$JUDGE" = 1 ] || return 0
		_gone=$(printf '%s\n' "$FOREIGN" | while IFS= read -r _f; do
			[ -e "$_f" ] && continue
			# An object directory of its own, gone whole: no pattern.
			if [ ! -d "$(dirname "$_f")" ] &&
				printf '%s\n' "$FOREIGN_WHOLE" | grep -qxF -- "$_f"; then
				continue
			fi
			printf '%s\n' "$_f"
		done)
		# A run that left none of them where it was put took every one with
		# its directory, which judged nothing.
		if printf '%s\n' "$FOREIGN" | while IFS= read -r _f; do
			[ -e "$_f" ] && echo kept
		done | grep -q kept; then
			FOREIGN_CHECKS=$((FOREIGN_CHECKS + 1))
		else
			FOREIGN_TOOK_DIR=$((FOREIGN_TOOK_DIR + 1))
		fi
		[ -n "$_gone" ] || return 0
		{
			echo "make_test.sh: FAIL — 'make $1' deleted a file your build never made:"
			printf '%s\n' "$_gone" | sed 's/^/    /'
			echo "  It was put there after the build, and looks like an object, as the"
			echo "  grader's own files can sit beside yours. A rule that deletes by"
			echo "  pattern deletes whatever matches; which files does yours name?"
			echo ""
			echo "  The sentence this applies:"
			say wildcards
			if [ "$MODE" = wildcards ]; then
				echo "  Your subject does not say it outright; the Norm, which your work must"
				echo "  follow, does, for every Makefile. So this fails at strict."
			fi
			make_said "$1"
		} >&2
		exit 1
	}
	# objs_left: the objects in the tree, less the planted ones.
	objs_left() {
		find . -type f -name '*.o' 2> /dev/null | sed 's|^\./||' | sort |
			grep -vxF -e "$FOREIGN" -e "" || :
	}

	# 3. fclean = clean, PLUS the final product. From a fully built tree, so
	#    the objects it must remove exist.
	#
	# GATED, like `re` below: --rules says which make rules THIS subject
	# mandates, and a rule it does not name is not checked.
	#    Only the artifact half was ever checked here, so an fclean that removes
	#    the archive and leaves every .o behind was green -- and then those .o
	#    get pushed, which the Piscine's instructions forbid.
	if has_rule fclean && ensure_built fclean; then
	plant_foreign
	run_rule fclean
	foreign_gone fclean
	if [ "$JUDGE" = 1 ] && judged fclean && [ -f "$ARTIFACT" ]; then
		job_not_done "make fclean" "it did not remove '$ARTIFACT'" || {
			echo "make_test.sh: FAIL — 'make fclean' did not remove '$ARTIFACT'."
			make_said fclean
			basis fclean fclean
			exit 1
		} >&2
	fi
	LEFT=$(objs_left)
	if [ "$JUDGE" = 1 ] && judged fclean clean && [ -n "$LEFT" ]; then
		job_not_done "make fclean" "it left object files behind" || {
			echo "make_test.sh: FAIL — 'make fclean' left object files behind:"
			printf '%s\n' "$LEFT" | sed 's/^/    /'
			make_said fclean
			echo "  What is listed above is what you would be handing in, and a turn-in"
			echo "  carries no build output."
			basis fclean fclean clean
			echo "  If fclean IS a clean, plus, which of your rules could it run instead of"
			echo "  repeating a list of files that will drift apart from clean's?"
			exit 1
		} >&2
	fi
	rule_note "make fclean" "on a fully built tree"
	# And once more on the tree it has just emptied. Nothing to remove is a
	# normal state for a cleaning rule to meet -- rush-02's subject builds
	# with `make fclean` then `make`, on a fresh clone. Only after a first run
	# that was judged: the tree is empty only if that run emptied it.
	if [ "$JUDGE" = 1 ] && [ "$MODE" != wildcards ]; then
		run_rule fclean
		rule_note "make fclean" "on a tree with nothing to clean"
	fi
	fi

	# 3b. all IS a rule of its own. The build above ran a bare `make`, which
	#     runs whatever rule comes FIRST in the file -- so a Makefile with no
	#     `all`, or an `all` that builds nothing, was green here whenever its
	#     first rule happened to build the artifact. Nothing else runs `make
	#     all` by name: `re` is often written without it. The artifact goes
	#     first, so "present afterwards" means this call built it.
	#     It built '$ARTIFACT' and exited non-zero: rule_note, like any rule
	#     that did its job. It built nothing: a FAIL at basic wherever the
	#     subject lists all -- building the artifact is the one thing every
	#     reading of a rule named all agrees on -- and elsewhere NOT JUDGED.
	#     exNN_build_rules and exNN_build_wildcards leave it alone.
	if has_rule all && [ "$MODE" != rules ] && [ "$MODE" != wildcards ] && ensure_built all; then
	rm -f "$ARTIFACT"
	run_rule all
	if [ "$JUDGE" = 1 ] && [ ! -f "$ARTIFACT" ]; then
		job_not_done "make all" "it built no '$ARTIFACT'" || {
			echo "make_test.sh: FAIL — 'make all' did not build '$ARTIFACT'."
			echo "  Your subject lists 'all' among the rules your Makefile must"
			echo "  have. A bare 'make' runs whichever rule comes first in the"
			echo "  file, which is why the build above could pass without it;"
			echo "  'make all' names the rule, so it has to exist and has to"
			echo "  produce '$ARTIFACT' on its own. It exited with status $RC,"
			echo "  and make said:"
			excerpt
			if has_quote all; then
				echo "  The sentence this applies:"
				say all
			fi
			exit 1
		} >&2
	fi
	rule_note "make all" "built '$ARTIFACT', and"
	fi

	# 3b'. The artifact's own rule, where the subject lists it: C 09 ex01's
	#      "and of course libft.a", rush-02's "$NAME". Same shape as all: it
	#      has to exist, and build '$ARTIFACT' on its own. Removed first, or
	#      make would find the file current and have nothing to do.
	if has_rule "$ARTIFACT" && [ "$MODE" != rules ] && [ "$MODE" != wildcards ] && ensure_built "$ARTIFACT"; then
	rm -f "$ARTIFACT"
	run_rule "$ARTIFACT"
	if [ "$JUDGE" = 1 ] && [ ! -f "$ARTIFACT" ]; then
		job_not_done "make $ARTIFACT" "it built no '$ARTIFACT'" || {
			echo "make_test.sh: FAIL — 'make $ARTIFACT' did not build '$ARTIFACT'."
			echo "  Your subject lists '$ARTIFACT' among the rules your Makefile must"
			echo "  have: a rule named after what it builds. It exited with status"
			echo "  $RC, and make said:"
			excerpt
			exit 1
		} >&2
	fi
	rule_note "make $ARTIFACT" "built '$ARTIFACT', and"
	fi

	# 3c. re is fclean followed by all, checked by its EFFECT, from a fully
	#     built tree: the one start state where an re that never cleans looks
	#     different from one that does. On an empty tree -- where re used to
	#     run -- both simply build.
	#
	#     Two observations, both timestamps, for the reason check 1 gives:
	#       - every object after re is newer than a marker dropped just
	#         before it, so re compiled each of them again (fclean's clean
	#         half), and did not just re-archive what was there;
	#       - the artifact is not the one that was there before. That one is
	#         dated in the future first: a re that removes it builds a new
	#         one, dated now, while a re that does not -- one built on clean,
	#         say -- leaves make believing the old one is newer than the
	#         objects it just rebuilt, so make keeps it, and the future date
	#         is still on it. Stale members of an old archive survive exactly
	#         that way, which is what re's fclean half exists to prevent.
	#     A Makefile whose archive rule rewrites the artifact on every run
	#     passes the second one without removing anything; check 1 is what
	#     catches that shape, where the subject asks for it.
	if has_rule re && [ "$MODE" != wildcards ] && ensure_built re; then
	touch -t 209901010000 "$FUT"
	touch -r "$FUT" "$ARTIFACT"
	touch "$REF"
	sleep 1
	run_rule re
	if [ "$JUDGE" = 1 ] && judged re && [ ! -f "$ARTIFACT" ]; then
		job_not_done "make re" "it did not rebuild '$ARTIFACT'" || {
			echo "make_test.sh: FAIL — 'make re' did not rebuild '$ARTIFACT'."
			make_said re
			echo "  From a fully built tree, re has to end with '$ARTIFACT' present, built"
			echo "  again. Check what it does, and in which order."
			basis re re
			exit 1
		} >&2
	fi
	if [ "$JUDGE" = 1 ] && judged re fclean && [ -z "$(find "$FUT" -newer "$ARTIFACT" 2> /dev/null)" ]; then
		job_not_done "make re" "it left the old '$ARTIFACT' in place" || {
			echo "make_test.sh: FAIL — 'make re' left the old '$ARTIFACT' in place."
			make_said re
			echo "  After re, the '$ARTIFACT' in the directory has to be one that re"
			echo "  built, never the one that was there before."
			echo "  To tell them apart, this check dated the old one in the future"
			echo "  before running 'make re' (make's 'modification time in the"
			echo "  future' and 'clock skew' warnings, if it printed them, come from"
			echo "  that). A re that removes it builds a new one. One that does not"
			echo "  leaves make believing the old one is up to date, and it stays,"
			echo "  with whatever it held from builds before."
			basis re re fclean
			echo "  Which of your rules removes '$ARTIFACT', and does re run it?"
			exit 1
		} >&2
	fi
	OLD=$(find . -type f -name '*.o' ! -newer "$REF" 2> /dev/null | sed 's|^\./||' | sort |
		grep -vxF -e "$FOREIGN" -e "" || :)
	if [ "$JUDGE" = 1 ] && judged re fclean clean && [ -n "$OLD" ]; then
		job_not_done "make re" "it kept object files from before it ran" || {
			echo "make_test.sh: FAIL — 'make re' kept object files from before it ran:"
			printf '%s\n' "$OLD" | sed 's/^/    /'
			make_said re
			echo "  Every object after re has to be one it compiled again. These were"
			echo "  not touched."
			basis re re fclean clean
			exit 1
		} >&2
	fi
	rule_note "make re" "on a fully built tree"
	fi

	# 4. clean IS NOT fclean, from a fully built tree of its own. It was never
	#    invoked before at all, so a clean that deleted the library instead of
	#    the objects — or as well as them — passed every layer in this repo.
	if has_rule clean && ensure_built clean; then
	plant_foreign
	run_rule clean
	foreign_gone clean
	if [ "$JUDGE" = 1 ] && judged clean && [ ! -f "$ARTIFACT" ]; then
		job_not_done "make clean" "it deleted '$ARTIFACT'" || {
			echo "make_test.sh: FAIL — 'make clean' deleted '$ARTIFACT'."
			make_said clean
			basis clean clean
			echo "  Which of your rules would someone run to reclaim disk space"
			echo "  without losing the '$ARTIFACT' they just built?"
			exit 1
		} >&2
	fi
	LEFT=$(objs_left)
	if [ "$JUDGE" = 1 ] && judged clean && [ -n "$LEFT" ]; then
		job_not_done "make clean" "it left object files behind" || {
			echo "make_test.sh: FAIL — 'make clean' left object files behind:"
			printf '%s\n' "$LEFT" | sed 's/^/    /'
			make_said clean
			basis clean clean
			echo "  Compare the list your clean deletes against the list of files"
			echo "  your build actually creates, name by name."
			exit 1
		} >&2
	fi
	rule_note "make clean" "on a fully built tree"
	if [ "$JUDGE" = 1 ] && [ "$MODE" != wildcards ]; then
		run_rule clean
		rule_note "make clean" "on a tree with nothing to clean"
	fi
	fi
fi

# The verdict, from what ran. Runs left out are counted, so an OK over a
# Makefile missing a rule does not read as one that has them all.
if [ "$EXITONLY" = 1 ]; then
	_nj=""
	[ "$NOT_JUDGED" = 0 ] || _nj=" $NOT_JUDGED run(s) were not judged (above); $T_BUILD says why."
	if [ "$STATUS_FAILS" -gt 0 ]; then
		echo "make_test.sh: FAIL — $STATUS_FAILS of the $STATUS_RUNS run(s) judged here exited non-zero (above).$_nj" >&2
		exit 1
	fi
	echo "make_test.sh: OK — every one of the $STATUS_RUNS run(s) judged here exited 0.$_nj"
	exit 0
fi
_nj=""
[ "$NOT_JUDGED" = 0 ] || _nj=" $NOT_JUDGED run(s) were not judged (above); $T_BUILD says why."
if [ "$MODE" = rules ]; then
	if [ "$CONV_CHECKS" = 0 ]; then
		[ "${NO_SKIP:-0}" != "1" ] || {
			echo "NO_SKIP set: no rule here was judged by this repo's convention.$_nj" >&2
			exit 1
		}
		echo "SKIP — no rule here was judged by this repo's convention.$_nj"
		exit 0
	fi
	echo "make_test.sh: OK — each rule your subject lists without saying what it does"
	echo "  does what this repo's convention says ($CONV_CHECKS check(s)).$_nj"
	exit 0
fi
if [ "$MODE" = wildcards ]; then
	echo "make_test.sh: OK — the build compiled no source it was not told about."
	if [ -z "$FOREIGN" ]; then
		echo "  The build made no object, so no object of the grader's was put where a"
		echo "  pattern would find it, and the cleaning rules were not judged."
	elif [ "$FOREIGN_CHECKS" = 0 ] && [ "$FOREIGN_TOOK_DIR" = 0 ]; then
		echo "  No cleaning rule your subject lists ran, so none was asked to leave an"
		echo "  object it did not make alone.$_nj"
	else
		[ "$FOREIGN_CHECKS" = 0 ] ||
			echo "  The cleaning rules left alone an object they did not make ($FOREIGN_CHECKS run(s)).$_nj"
		if [ "$FOREIGN_TOOK_DIR" != 0 ]; then
			echo "  $FOREIGN_TOOK_DIR cleaning run(s) removed the object directory of your build's own"
			echo "  whole, with the object put there: that names no file, so it is no"
			echo "  pattern, and those runs were not judged."
		fi
	fi
	exit 0
fi
if [ "$WARNED" = 1 ]; then
	echo "make_test.sh: OK, with a warning (above): ${T_BUILD}_exit, at robust, fails on it"
else
	echo "make_test.sh: OK"
fi
# What the checks that may stand down did, so an OK says they ran: one
# source touched (--graph), and the grader's object planted before each
# cleaning rule (--foreign-object).
[ -z "$TOUCHED" ] || printf '%s\n' "$TOUCHED" | fold -s -w 74 | sed 's/ *$//; s/^/  /'
if [ -n "$FOREIGN" ] && [ -z "$SCRIPT" ]; then
	if [ "$FOREIGN_CHECKS" = 0 ]; then
		echo "  No cleaning rule ran, so none was asked to leave alone the object put"
		echo "  where the grader's files go ($FOREIGN)."
	else
		echo "  The cleaning rules left alone the object put where the grader's files"
		echo "  go ($FOREIGN), which no rule of yours made: $FOREIGN_CHECKS run(s)."
	fi
fi
# What this target left to exNN_build_rules, said, so an OK here is not read
# as a verdict on what those rules do. It names the DEFINITIONS the subject
# does not give, and apart from them the rules that rest on one: Reloaded's
# ex24 defines fclean and re by clean and not clean, and a note that said its
# subject lists "fclean, re and clean without saying what each does" said
# something false about the subject (finding 082's class).
#
# and_list WORD...: "a", "a and b", "a, b and c".
and_list() {
	printf '%s\n' "$@" | awk '{ w[NR] = $0 }
		END {
			for (i = 1; i <= NR; i++)
				printf "%s%s", (i == 1 ? "" : (i == NR ? " and " : ", ")), w[i]
		}'
}
if [ -n "$DEFERRED" ]; then
	# The definitions in the order the rules build on each other, and the
	# rules that are not among them.
	_dk=""
	for _k in clean fclean re $DEFERRED_KEYS; do
		case " $DEFERRED_KEYS " in *" $_k "*) ;; *) continue ;; esac
		case " $_dk " in *" $_k "*) continue ;; esac
		_dk="${_dk:+$_dk }$_k"
	done
	_do=""
	for _r in $DEFERRED; do
		case " $_dk " in *" $_r "*) continue ;; esac
		_do="${_do:+$_do }$_r"
	done
	# shellcheck disable=SC2086 # word lists, split on purpose
	case "$_dk" in
		*" "*) _dv="do"; _dp="they do"; _dn=$(and_list $_dk) ;;
		*) _dv="does"; _dp="it does"; _dn=$_dk ;;
	esac
	if [ -z "$_do" ]; then
		echo "  Your subject does not say what $_dn $_dv, so what $_dp"
		echo "  is this repo's convention: ${T_BUILD}_rules checks it, at robust."
	else
		# shellcheck disable=SC2086 # a word list, split on purpose
		case "$_do" in
			*" "*) _ov="do"; _on=$(and_list $_do) ;;
			*) _ov="does"; _on=$_do ;;
		esac
		echo "  Your subject does not say what $_dn $_dv. What $_dp, and so that"
		echo "  part of what $_on $_ov, is this repo's convention: ${T_BUILD}_rules"
		echo "  checks it, at robust."
	fi
fi
exit 0
