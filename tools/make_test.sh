#!/bin/sh
# Build a Makefile/shell-script deliverable and assert it produces its artifact.
#
# The whole exercise directory is staged into a writable scratch copy (Bazel
# runfiles are read-only), then built. For a Makefile we also exercise the rules
# themselves: that a second `make` does nothing, that the .o files land next to
# their .c, and that clean/fclean/re each mean what the subject says they mean.
#
# Usage:
#   make_test.sh --anchor PATH --artifact NAME [--script NAME] [--symbols a,b,c]
#                [--rules a,b,c] [--graph] [--relink]
#
#   --anchor    $(location) of any file inside the exercise dir (its directory
#               is the subtree that gets staged and built)
#   --artifact  file expected to exist after building (e.g. libft.a)
#   --script    if set, run `sh <script>` instead of `make`
#   --symbols   comma-separated symbols that must be defined in the artifact
#   --rules     which make rules THIS subject mandates, comma-separated, or
#               "-" for none at all (c-piscine-bsq names no rule).
#               Default "clean,fclean,re" -- what every caller wanted before this
#               existed. rush-02's subject names only $(NAME), clean and fclean,
#               so requiring `re` there would fail a correct Makefile on a rule
#               nobody asked for. Note the checks are SEQUENTIALLY COUPLED: the
#               fclean check empties the tree, and something has to refill it
#               before the clean check can tell "clean deleted the artifact"
#               apart from "the artifact was never there". When `re` is not
#               mandated, a plain `make` does that refill instead.
#   --relink    run ONLY the no-unnecessary-work check, worded for a subject
#               that says 'must not relink' and nothing about where objects
#               land. c-piscine-bsq is that subject. --graph implies it.
#   --graph     run the incremental-build checks (no unnecessary work, object
#               placement). These were gated on "the exercise has more than one
#               .c", a proxy this script's own comment below called out as
#               dishonest: it is DORMANT while a team ships one source and ARMS
#               ITSELF the day they split, and its failure text quotes c-09's
#               subject at modules that are not c-09. The gate is now the
#               caller's to set, which is what that comment prescribed.

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
require basename cp dirname find grep head mktemp rm sed sleep sort tr

ANCHOR=""
ARTIFACT=""
SCRIPT=""
SYMS=""
RULES="clean,fclean,re"
GRAPH=0
RELINK=0

# ---------------------------------------------------------------------------
# nm is SUPPLIED, never found. --nm is required and there is no PATH fallback,
# for the reason every pinned tool here has one: a check whose answer depends on
# which binary happened to be first on PATH is not a check. This one is not
# hypothetical -- the 2026-08-09 campus audit caught nm resolving to a student's
# own Homebrew binutils 2.46.1, shadowing the system 2.38 the Moulinette uses.
# Exit 2 rather than 1 if it is missing: nothing was checked, so this is a broken
# harness and not a wrong deliverable.
NM=""
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

while [ $# -gt 0 ]; do
	case "$1" in
		--nm) need "$1" "$#"; NM="$2"; shift 2 ;;
		--make) need "$1" "$#"; MAKE_BIN="$2"; shift 2 ;;
		--anchor) need "$1" "$#"; ANCHOR="$2"; shift 2 ;;
		--artifact) need "$1" "$#"; ARTIFACT="$2"; shift 2 ;;
		--script) need "$1" "$#"; SCRIPT="$2"; shift 2 ;;
		--symbols) need "$1" "$#"; SYMS="$2"; shift 2 ;;
		# "-" is the empty set, spelled so it survives sh_test's tokenisation
		# of `args`; see c_make in tools/defs.bzl.
		--rules) need "$1" "$#"; RULES="$2"; [ "$RULES" = "-" ] && RULES=""; shift 2 ;;
		--graph) GRAPH=1; shift ;;
		--relink) RELINK=1; shift ;;
		*) echo "make_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$NM" ] || { echo "make_test.sh: --nm is required (no PATH fallback by design)" >&2; exit 2; }
[ -x "$NM" ] || { echo "make_test.sh: --nm '$NM' is not executable" >&2; exit 2; }

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

case "$ANCHOR" in
	/*) A="$ANCHOR" ;;
	*) A="$PWD/$ANCHOR" ;;
esac
SRCDIR=$(dirname "$A")

WORK=$(mktemp -d)
# Everything this runner scratches lives under $WORK, and $WORK is removed on
# the way out however that happens. It used to have no cleanup at all: a staged
# COPY OF THE WHOLE EXERCISE TREE, plus three loose mktemp files below, left
# behind on every invocation of every c_make target -- and this is the runner
# that stages a tree, so it leaked the most of any of them. INT and TERM are in
# the list because Bazel kills a timed-out test rather than letting it return.
DRY=""
REF=""
LOG=""
trap 'rm -rf "$WORK"; rm -f "$DRY" "$REF" "$LOG"' EXIT INT TERM
cp -rL "$SRCDIR"/. "$WORK"/ 2> /dev/null
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

cd "$WORK" || { echo "make_test.sh: cannot enter scratch dir" >&2; exit 2; }

# Delete the artifact BEFORE building, so "it exists afterwards" means this run
# produced it. Bazel's data glob sweeps in whatever running make (or the script)
# by hand left in deliverable/ -- .gitignore hides those from git, not from
# native.glob -- and they are copied into this scratch dir with everything else.
# Without this the build layer can report green off a stale archive from an
# earlier hand-run, and the fclean/re hygiene below that would have caught it is
# skipped for the --script arm.
rm -f "$ARTIFACT"

# ---------------------------------------------------- what the recipes SAY
# Runs BEFORE the build, and that is not a style choice: `make -n` on an
# already-built tree prints "Nothing to be done", so every check below would
# read an empty recipe list and fail a perfectly good Makefile. The tree is
# clean here -- c_make's glob excludes build products and the artifact was just
# removed -- so this is the one moment the full command list is visible.
if [ "$GRAPH" = 1 ] && [ -z "$SCRIPT" ]; then
	# 0. WHAT THE RECIPES SAY.
	#
	# Two of the subject's bullets are about the TEXT of the Makefile rather
	# than about what the build produces, and nothing in this repo could see
	# either of them. The flags one matters most: exNN_compile_clang and
	# exNN_compile_gcc compile the sources THEMSELVES, with their own flags,
	# not through the student's Makefile. So a Makefile that omits -Werror is
	# green in every layer here and a KO at the Moulinette -- the exact shape
	# this suite exists to prevent.
	#
	# Read off the recipe text on purpose. Asking make to tell us would mean
	# parsing "Nothing to be done for 'all'", which is GNU's wording and not
	# BSD's, and which a recipe prefixed with @ never prints at all. The text
	# is the same fact under every make.
	#
	# Recipe lines only -- lines beginning with a TAB. A variable assignment
	# like CFLAGS = -Wall -Wextra -Werror is a perfectly good way to write
	# this, and make expands it into the recipe, so the expanded output of
	# `make -n` is what gets searched rather than the raw file.
	DRY=$(mktemp)
	"$MAKE_BIN" -n 2> /dev/null > "$DRY" || true
	if ! grep -qE 'cc([^-]|$).*-Wall[[:space:]]+-Wextra[[:space:]]+-Werror' "$DRY"; then
		{
			echo "make_test.sh: FAIL — no compile command runs cc with"
			echo "  -Wall -Wextra -Werror in that order."
			echo ""
			echo "  The subject's words: 'It should compile the .c files with cc"
			echo "  and with -Wall -Wextra -Werror flags in that order.'"
			echo ""
			echo "  Nothing else in this repo can check that for you. The"
			echo "  exNN_compile_* layers compile your sources with flags THEY"
			echo "  choose, so they stay green no matter what your Makefile"
			echo "  says. The Moulinette reads the Makefile."
			echo ""
			echo "  This is what the expanded recipes looked like:"
			sed -n '1,12p' "$DRY" | sed 's/^/    /'
		} >&2
		exit 1
	fi
	# `make -n` prints a recipe it would run even when silenced with @, but
	# the @ itself does not survive into that output -- so the raw file is
	# where this one has to be read.
	AT=$(grep -n '^	[[:space:]]*@' Makefile 2> /dev/null | head -5)
	if [ -n "$AT" ]; then
		{
			echo "make_test.sh: FAIL — some recipes are silenced with '@'."
			printf '%s\n' "$AT" | sed 's/^/    /'
			echo ""
			echo "  The subject's words: 'Your Makefile should print all the"
			echo "  commands it's running.' A leading @ on a recipe line tells"
			echo "  make to run the command without echoing it, which is exactly"
			echo "  what that bullet forbids. Remove the @."
		} >&2
		exit 1
	fi
fi

if [ -n "$SCRIPT" ]; then
	sh "$SCRIPT" || { echo "make_test.sh: '$SCRIPT' failed" >&2; exit 1; }
else
	"$MAKE_BIN" || { echo "make_test.sh: 'make' failed" >&2; exit 1; }
fi

if [ ! -f "$ARTIFACT" ]; then
	echo "make_test.sh: FAIL — 'make' succeeded but did not produce '$ARTIFACT'." >&2

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

	if [ -n "$NEAR" ]; then
		echo "" >&2
		echo "  It built './$NEAR' instead. Those differ only in punctuation or" >&2
		echo "  case, so this is a naming mismatch and not a build problem: the" >&2
		echo "  subject states the executable's name, and that spelling is the" >&2
		echo "  one the Moulinette runs." >&2
		echo "" >&2
		echo "  Nothing else here can catch this. Every other layer compiles" >&2
		echo "  your sources itself and never asks what the Makefile called its" >&2
		echo "  output, so they all stay green while this is wrong." >&2
	else
		echo "" >&2
		echo "  Nothing in the build directory carries that name, not even close." >&2
		echo "  Check the target the subject asks for against the one your rule" >&2
		echo "  actually names. This is what make left behind:" >&2
		echo "" >&2
		ls -la >&2
	fi
	exit 1
fi

if [ -n "$SYMS" ]; then
	for s in $(echo "$SYMS" | tr ',' ' '); do
		if ! "$NM" "$ARTIFACT" 2> /dev/null | grep -qE "[Tt] $s\$"; then
			echo "make_test.sh: symbol '$s' missing from '$ARTIFACT'" >&2
			exit 1
		fi
	done
fi

# ---------------------------------------------------------------- make hygiene
# Everything below asks about the RULES of the build, so it runs for the Makefile
# arm only. --script is c-09 ex00, whose answer is a shell script: it has no
# all/clean/fclean/re to invoke and no notion of "already up to date", so putting
# it through any of this would red an exercise for not doing something its
# subject never asked for. Hence the guard.
#
# Why this block carries so much weight: ex00 and ex01 build the SAME five
# sources into the SAME libft.a, and the only thing ex01 adds is the dependency
# graph. Assert only "libft.a exists and exports five names" and a single `all:`
# recipe running `cc -c srcs/*.c` then `ar rc` is byte-for-byte as green as a
# real Makefile — i.e. the one thing this exercise teaches would be the one thing
# nothing looks at, and a student could finish it having learned nothing ex00 had
# not already taught them.
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
	# So both are gated, and the gate is the CALLER's: c_libft passes graph = True
	# (c-09 ex01's five sources under srcs/, where "do not recompile what did not
	# change" is the entire lesson), c_make does not (c-10's single translation
	# unit, where there is no graph to get wrong).
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
	if [ "$GRAPH" = 1 ] || [ "$RELINK" = 1 ]; then
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
		# hide a rebuild. It costs one second, once, in the one test that runs it.
		REF=$(mktemp)
		LOG=$(mktemp)
		sleep 1
		if ! "$MAKE_BIN" > "$LOG" 2>&1; then
			{
				echo "make_test.sh: FAIL — running 'make' a second time failed."
				echo "  The first build succeeded, so this is make being asked to"
				echo "  bring an already-built tree up to date and erroring anyway."
				echo "  Read the log below, then ask what the first run left behind"
				echo "  that the second one did not expect to find."
				sed -n '1,20p' "$LOG" | sed 's/^/    /'
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
					echo "  The subject asks for this twice, in two separate bullets:"
					echo "  your Makefile 'should not run any unnecessary commands' and"
					echo "  'should not compile any file unnecessarily'."
					echo "  This is precisely why c-09 ex01 follows ex00: a shell script"
					echo "  can produce the same archive, but it rebuilds the world every"
					echo "  time, because it has no way to know what is already current."
				else
					echo "  Your subject states this as one rule: the Makefile 'must not"
					echo "  relink'. Running make twice with nothing changed in between"
					echo "  must do nothing the second time."
				fi
				echo "  So: for ONE target, what two things does make compare to"
				echo "  decide whether its recipe has to run at all? And what does"
				echo "  it therefore have to be told about every file your build"
				echo "  produces — not just about the archive at the end?"
			} >&2
			exit 1
		fi
	fi

	if [ "$GRAPH" = 1 ]; then

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
				echo "  The subject's words: '.o files should be near their"
				echo "  corresponding .c files.' Where an object lands is not the"
				echo "  compiler's decision to make by default — it is yours, and you"
				echo "  state it in the rule that builds the object. Look at how a"
				echo "  rule names the file it produces versus the file it reads, and"
				echo "  at what that naming buys you once you want ONE rule to cover"
				echo "  every source in the directory."
			} >&2
			exit 1
		fi
	fi

	# 3. fclean = clean, PLUS the final product.
	#
	# GATED, like `re` below and unlike before. --rules documents itself as
	# "which make rules THIS subject mandates", and it decided `re` while
	# fclean and clean ran unconditionally -- so the flag did not mean what it
	# said. No caller is affected (every subject using c_make today mandates
	# both), which is exactly why it could stay wrong: a flag that is honest
	# only because nobody has exercised the other case yet.
	#    Only the artifact half was ever checked here, so an fclean that removes
	#    the archive and leaves every .o behind was green -- and then those .o
	#    get pushed, which the Piscine's instructions forbid. Run this while the
	#    tree is fully built, so the objects it must remove actually exist.
	if has_rule fclean; then
	"$MAKE_BIN" fclean > /dev/null 2>&1
	if [ -f "$ARTIFACT" ]; then
		{
			echo "make_test.sh: FAIL — 'make fclean' did not remove '$ARTIFACT'."
			echo "  fclean is the rule that takes the directory back to what you"
			echo "  turn in: sources and Makefile, nothing your build made."
		} >&2
		exit 1
	fi
	LEFT=$(find . -type f -name '*.o' 2> /dev/null | sed 's|^\./||' | sort)
	if [ -n "$LEFT" ]; then
		{
			echo "make_test.sh: FAIL — 'make fclean' left object files behind:"
			printf '%s\n' "$LEFT" | sed 's/^/    /'
			echo "  fclean removed '$ARTIFACT' but not the temporary files. It is"
			echo "  the stronger of the two cleaning rules, defined as 'like a make"
			echo "  clean, plus removing all the binaries generated with make all'."
			echo "  What is listed above is what you would be handing in — and a"
			echo "  turn-in carries no build output."
			echo "  Read that definition again as a statement about the RULES and"
			echo "  not only about the files: it says fclean IS a clean, plus. Two"
			echo "  rules that each repeat the same file list drift apart the day"
			echo "  that list changes."
		} >&2
		exit 1
	fi

	fi

	if has_rule re; then
		"$MAKE_BIN" re > /dev/null 2>&1
	elif has_rule clean; then
		# This subject does not name `re`. The fclean check above emptied the
		# tree, and the clean check below can only tell "clean deleted the
		# artifact" from "it was never built" if something refills it first.
		# Rebuild the way this subject actually says to build.
		"$MAKE_BIN" > /dev/null 2>&1
	fi
	if [ ! -f "$ARTIFACT" ]; then
		{
			if has_rule re; then
			echo "make_test.sh: FAIL — 'make re' did not rebuild '$ARTIFACT'."
			echo "  re is 'a make fclean followed by a make all', so it has to end"
			echo "  with '$ARTIFACT' present, starting from a directory that has"
			echo "  none. Check what it does, and in which order."
			else
			echo "make_test.sh: FAIL — 'make' did not produce '$ARTIFACT'"
			echo "  after 'make fclean'. The subject builds with 'make fclean'"
			echo "  then 'make', so that pair has to end with it present."
			fi
		} >&2
		exit 1
	fi

	# 4. clean IS NOT fclean. This is the last check because it is the one that
	#    needs a freshly built tree behind it (`make re`, just above) and leaves
	#    the tree in a state nothing after it depends on. It was never invoked
	#    before at all, so a clean that deleted the library instead of the
	#    objects — or as well as them — passed every layer in this repo.
	if has_rule clean; then
	"$MAKE_BIN" clean > /dev/null 2>&1
	if [ ! -f "$ARTIFACT" ]; then
		{
			echo "make_test.sh: FAIL — 'make clean' deleted '$ARTIFACT'."
			echo "  clean has one job: to 'remove all the temporary generated"
			echo "  files'. '$ARTIFACT' is not temporary — it is the thing the"
			echo "  whole Makefile exists to produce, and the subject says so"
			echo "  from the other side too, by defining fclean as a clean PLUS"
			echo "  removing what make all generated. If clean already removed"
			echo "  it, that 'plus' would mean nothing and one of the two rules"
			echo "  you were asked for would have no reason to exist."
			echo "  Which of your rules would someone run to reclaim disk space"
			echo "  without losing the '$ARTIFACT' they just built?"
		} >&2
		exit 1
	fi
	LEFT=$(find . -type f -name '*.o' 2> /dev/null | sed 's|^\./||' | sort)
	if [ -n "$LEFT" ]; then
		{
			echo "make_test.sh: FAIL — 'make clean' left object files behind:"
			printf '%s\n' "$LEFT" | sed 's/^/    /'
			echo "  clean is asked to 'remove all the temporary generated files'"
			echo "  — exactly these, the objects your build produced on the way"
			echo "  to '$ARTIFACT' — while leaving '$ARTIFACT' itself alone."
			echo "  Compare the list your clean deletes against the list of files"
			echo "  your build actually creates, name by name."
		} >&2
		exit 1
	fi
	fi
fi

echo "make_test.sh: OK"
exit 0
