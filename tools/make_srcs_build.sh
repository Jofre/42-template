#!/bin/sh
# make_srcs_build.sh — ask the Makefile which files are the program, then build
# it ourselves.
#
# WHY THIS EXISTS.
# Most Piscine exercises have their filenames fixed by the subject, so a BUILD
# file can name them and a glob of deliverable/exNN/*.c is exactly the program.
# The modules that require a Makefile are the exception: the subject says "a
# Makefile and all the necessary files" and stops. What the files are called,
# how many there are, and which of them is the entry point are the team's to
# decide, and the Makefile is where they decided it.
#
# A glob is wrong there, and wrong in a way that looks like a harness bug. It
# picks up every .c in the directory -- a second front end, a scratch file
# someone kept, an alternative main behind another rule -- so the link fails on
# a duplicate symbol while `make` is perfectly happy. Hard-coding the list
# instead just moves the assumption into the BUILD file, where it goes stale
# silently the first time the team renames anything.
#
# So neither: ASK MAKE. `make -Bn` prints the recipes it would run for the
# default goal without running them, and every .c in those recipes is, by
# definition, a file the program is built from. Names, count and entry point all
# come from the team.
#
# WHY IT BUILDS RATHER THAN JUST LISTING.
# Because the source list has to arrive at BUILD time, and Bazel decides its
# actions before any of them run. A cc_binary needs its srcs at analysis, which
# is exactly when the Makefile has not been consulted yet. Doing the compile
# here is what lets the list be discovered at all.
#
# The split is worth stating: the Makefile decides WHICH files, this script
# decides HOW they are compiled. Our own flags, our own sanitizer, our own
# linker -- so a Makefile that forgets -Werror cannot quietly soften the compile
# layers, and an exercise remains testable under ASan even though no student
# Makefile builds an instrumented binary. Whether the Makefile ITSELF works, and
# names its artifact what the subject demands, is make_test.sh's job and stays
# entirely separate.
#
# WHY NOT rules_foreign_cc.
# Its make() rule runs a project's Makefile under Bazel, which is the closest
# thing to a "Makefile to Bazel" tool that exists -- there is no translator, and
# there could not really be a general one. But it runs the build the Makefile
# describes, flags and all, which is the half we specifically do not want; it is
# built around configure/make/make-install libraries with headers to install,
# not a twelve-file student program; and it is a whole toolchain dependency to
# add for something `make -Bn` answers in one line.
#
# Usage:
#   make_srcs_build.sh --anchor <path/to/Makefile> --cc <compiler> --out <bin>
#                      [--cc-lib <file>]... [--copt <flag>]... [--linkopt <flag>]...
#                      [--stub-on-failure]
#
# --cc-lib names a shared library the COMPILER itself needs; its directory goes
# on the loader's search path. Only a fetched compiler needs it, and it is not
# optional there: without it the driver silently loads the box's copies and
# stops being the pinned compiler, with everything still green.
#
# Exit 1 means the deliverable is wrong (make failed, no sources, compile
# failed). Exit 2 means this script could not perform the check.
#
# --stub-on-failure turns the first of those into a program instead: it writes
# an executable that prints the same explanation and exits 1, and returns 0. It
# exists because this runs inside a BUILD action, and an unwritten deliverable
# is the normal state of this repo -- a template's Makefile is a stub whose
# recipes only echo, so it names no sources, which is correct and expected.
# Without the stub that becomes "FAILED TO BUILD" on two dozen targets, which
# reads as a broken harness rather than as work not done yet, and it takes the
# whole module's tests down with it instead of failing them one by one with
# their clues attached. Nothing is hidden: the same text reaches the student
# from the program itself, and the module's own make layer reports the Makefile
# independently.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "make_srcs_build.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require cat chmod cp dirname mktemp rm

ANCHOR=""
CC=""
OUT=""
COPTS=""
LINKOPTS=""
CC_LIBS=""
STUB_ON_FAILURE=0
# The pinned make -- see the note in make_test.sh for why make in particular
# matters here. Defaults to the box's for a hand-run outside Bazel.
MAKE_BIN="make"

need() { [ "$2" -ge 2 ] || { echo "make_srcs_build.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--anchor) need "$1" "$#"; ANCHOR="$2"; shift 2 ;;
		--cc) need "$1" "$#"; CC="$2"; shift 2 ;;
		--cc-lib)
			need "$1" "$#"
			case "$2" in
				/*) _d=$(dirname "$2") ;;
				*) _d=$(dirname "$PWD/$2") ;;
			esac
			[ -d "$_d" ] || {
				echo "make_srcs_build.sh: --cc-lib directory '$_d' does not exist." >&2
				echo "  The compiler would fall back to this machine's libraries" >&2
				echo "  and stop being the pinned one, so this refuses to run." >&2
				exit 2
			}
			CC_LIBS="${CC_LIBS:+$CC_LIBS:}$_d"
			shift 2 ;;
		--make) need "$1" "$#"; MAKE_BIN="$2"; shift 2 ;;
		--out) need "$1" "$#"; OUT="$2"; shift 2 ;;
		--stub-on-failure) STUB_ON_FAILURE=1; shift ;;
		--copt) need "$1" "$#"; COPTS="$COPTS $2"; shift 2 ;;
		--linkopt) need "$1" "$#"; LINKOPTS="$LINKOPTS $2"; shift 2 ;;
		*) echo "make_srcs_build.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$ANCHOR" ] || { echo "make_srcs_build.sh: --anchor is required" >&2; exit 2; }
[ -n "$CC" ] || { echo "make_srcs_build.sh: --cc is required" >&2; exit 2; }
[ -n "$OUT" ] || { echo "make_srcs_build.sh: --out is required" >&2; exit 2; }
[ -f "$ANCHOR" ] || { echo "make_srcs_build.sh: no Makefile at '$ANCHOR'" >&2; exit 2; }

command -v "$MAKE_BIN" > /dev/null 2>&1 || {
	echo "make_srcs_build.sh: no make at '$MAKE_BIN'" >&2
	exit 2
}
if [ -n "$CC_LIBS" ]; then
	LD_LIBRARY_PATH="$CC_LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	export LD_LIBRARY_PATH
fi

command -v "$CC" > /dev/null 2>&1 || {
	echo "make_srcs_build.sh: compiler '$CC' not found" >&2
	exit 2
}

# Absolute, because the build happens after a cd into a scratch directory.
# Both of these: the output path, and -- less obviously -- the compiler, which
# arrives as a runfiles-relative path when it is a FETCHED one rather than a
# name on PATH. A relative compiler path survives the argument check above and
# then dies after the cd as "clang-12: not found", which reads like a missing
# toolchain rather than a stranded path.
case "$OUT" in
	/*) ;;
	*) OUT="$PWD/$OUT" ;;
esac
# Spelled out twice rather than looped over with eval: the loop needed
# indirection to read and write a variable by name, which shellcheck cannot
# follow (SC2154) and a reader has to decode. Two cases are cheaper than either.
case "$CC" in
	/*) ;;
	*/*) CC="$PWD/$CC" ;;
esac
case "$MAKE_BIN" in
	/*) ;;
	*/*) MAKE_BIN="$PWD/$MAKE_BIN" ;;
esac

# Report a deliverable-side failure. With --stub-on-failure, the same words go
# into a program that says them at run time; without it, straight to stderr and
# out. Either way they are said once, in one voice.
fail_deliverable() {
	if [ "$STUB_ON_FAILURE" = 1 ]; then
		{
			echo "#!/bin/sh"
			echo "# Written by tools/make_srcs_build.sh: there was no program to build."
			echo "cat >&2 <<'MSB_EOF'"
			cat
			echo "MSB_EOF"
			echo "exit 1"
		} > "$OUT"
		chmod +x "$OUT"
		exit 0
	fi
	cat >&2
	exit 1
}

SRCDIR=$(dirname "$ANCHOR")
WORK=$(mktemp -d) || { echo "make_srcs_build.sh: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT INT TERM

# The whole directory, because a Makefile may include another file, read a
# header, or reference anything else beside it.
cp -R "$SRCDIR"/. "$WORK"/ 2> /dev/null || {
	echo "make_srcs_build.sh: could not stage '$SRCDIR'" >&2
	exit 2
}
cd "$WORK" || { echo "make_srcs_build.sh: cannot enter scratch dir" >&2; exit 2; }

# -n so nothing is executed, -B so it prints the recipes even when a stale .o
# from a hand-run of make was copied in beside the sources. Without -B, make
# would consider those targets up to date, print almost nothing, and this script
# would conclude the program has no sources at all.
RECIPES=$("$MAKE_BIN" -Bn 2>&1)
MAKE_RC=$?
if [ "$MAKE_RC" -ne 0 ]; then
	fail_deliverable <<-EOF
	make_srcs_build.sh: FAIL — 'make -Bn' could not work out what to build.

	  Nothing was compiled: this is make refusing to plan the build, not
	  your code failing to compile. A missing file named in the sources
	  list, or a syntax error in the Makefile, both look like this.

	$RECIPES
	EOF
fi

# Every .c token in a recipe line, in order, deduplicated. Order is preserved
# rather than sorted so a failure message reads in the order the Makefile lists
# them -- easier to compare against SOURCES by eye.
SRCS=""
for tok in $RECIPES; do
	case "$tok" in
		*.c) ;;
		*) continue ;;
	esac

	# Strip a leading ./ so ./ft_x.c and ft_x.c are not counted twice.
	tok=${tok#./}
	[ -f "$tok" ] || continue
	case " $SRCS " in
		*" $tok "*) continue ;;
	esac
	SRCS="$SRCS $tok"
done

if [ -z "$SRCS" ]; then
	fail_deliverable <<-EOF
	make_srcs_build.sh: FAIL — the Makefile compiles no .c files.

	  'make -Bn' was asked what the default goal would run and named no
	  source. Either the default goal builds something other than the
	  program (the first target in the file is the default one -- check
	  what that is), or the recipes never mention the sources by name.

	  If this exercise is not written yet, that is exactly what you should
	  expect to see: a stub Makefile whose recipes only echo compiles
	  nothing, so there is no program for the run layers to run.

	  This is what it said it would run:

	$RECIPES
	EOF
fi

# shellcheck disable=SC2086
# Word splitting is the point: COPTS, LINKOPTS and SRCS are each a
# space-separated list assembled above, and quoting them would pass each list as
# one argument.
if ! CC_ERR=$($CC $COPTS $SRCS $LINKOPTS -o "$OUT" 2>&1); then
	fail_deliverable <<-EOF
	make_srcs_build.sh: FAIL — those sources do not build into a program.

	$CC_ERR

	  The files came from your own Makefile:
	$(for s in $SRCS; do echo "    $s"; done)

	  A duplicate 'main' here means the Makefile links two entry points
	  into one program. A missing symbol means it links fewer files than
	  the program needs -- the compile layers pass in that case, because
	  they compile each file on its own and never link.
	EOF
fi

exit 0
