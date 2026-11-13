#!/bin/sh
# Deliverable file-set check (tag "files").
#
# The Moulinette looks at WHICH FILES you turned in before it looks at what they
# do: a required file that is missing is an instant KO, and some projects also
# object to files nobody asked for. No other layer here can see that — a missing
# file is currently a Bazel *analysis* error (a wall of text about a label that
# does not exist, not a test result), and an extra file is invisible entirely,
# yet it still gets pushed to Vogsphere by //tools:submit.
#
# The two halves are deliberately NOT treated alike:
#
#   MISSING a required file  -> FAIL. The subject names its files exactly; there
#                               is no argument to be had.
#   An EXTRA file            -> FAIL with --strict, which is where a subject
#                               forbids one: every Piscine subject does ("You
#                               cannot leave any additional file", "submit only
#                               the files requested"), so every Piscine project
#                               passes it (the subject() contract's `strict`).
#                               Without it, a WARNING, and the test passes: for
#                               a subject that leaves the rest of its list
#                               open, where at a defense you can say why a
#                               file is there. What a subject allows without
#                               naming it (a header, any .c) is --optional,
#                               never an extra.
#   A file the GRADER brings -> the same, under a heading of its own: the
#     (--provided)              subject says the grader supplies it, so the
#                               student never turns one in (Reloaded's
#                               ft_putchar.c, C 08's ft_stock_str.h).
#   An EXPECTED file that is  -> listed as "not produced", and the test still
#     not there (--expected)    passes: another layer owns that finding and
#                               says it better. A shell exercise's turn-in is
#                               the one: its generator made nothing, and the
#                               output layer says so with the exercise's
#                               clues. It is still named here, because a
#                               report with no row for it said "exactly the
#                               files the subject asks for" over a turn-in
#                               that did not exist (finding 017).
#
# The PASS line says only what was established: "exactly the files the
# subject asks for" when every file it names is here and nothing else is; a
# file the subject allows without naming it (--optional) is listed as
# allowed, not required; and a subject that names no file gets a row saying
# so and a PASS that claims nothing more than "nothing it did not allow".
#
# --grader says who grades the project -- moulinette, defense or both, from
# the project's subject() contract -- and words the warning: a person at a
# defense can be told why a file is there, a program cannot.
#
# The actual file list is supplied by the caller (Bazel's glob sees the real
# directory at analysis time; a test sandbox would only ever see files that were
# already declared, which is exactly the blind spot this closes): as
# --actual NAME, one per file, or as --actual-list FILE, one NAME per line --
# how tools/defs.bzl's c_files hands it over, so that a name no label or
# argument list can carry ("ft_putchar (1).c") still arrives whole. Every list
# here is one name per line and is walked a line at a time: a name with a
# blank in it is one name, reported as it is.
#
# A NAME is the file's path from the turn-in directory: "Makefile", or
# "srcs/main.c" where the subject lets files sit in subfolders.
#
# --root says the turn-in directory is the root of deliverable/ -- the
# subject has no "Turn-in directory" line (BSQ, the Common Core). Files found
# under an exNN/ folder there are then most likely an earlier layout's, or a
# habit from the modules that have one, and the report says to move them up.
#
# A name with a / in it is in a SUBFOLDER of the turn-in directory. The
# caller lists the whole tree (c_files globs it), so a copy kept in old/ or
# backup/ is reported like any other file nobody asked for -- git pushes the
# tree, not one level of it -- and a nested copy of a required name is not
# that name (finding 102).
#
# --stray EXERCISES says the folder (or generator) is one the student made
# for an exercise the subject does not have -- deliverable/ex09 where the
# subject stops at ex08 -- and names the ones it has, comma-separated. What
# is in it is reported as extra, whole, and FAILS whatever --strict says: no
# exercise's file list, open or not, reaches a folder of no exercise.
# c_levels() emits this test for it, so a folder of the student's never stops
# the package from loading.
#
# --outside EXERCISES is the same question for the rest of the pushed tree:
# the names are paths from deliverable/ -- files at its root, and in folders
# that are no exercise's (old/, ex5/, "ex05 copy/") -- in a project whose
# subject gives each exercise a turn-in directory. Every one FAILS: a
# Vogsphere repository holds the exercise folders the subject names and
# nothing beside them (every subject: "submit only the files requested"). An
# empty list passes. c_levels() emits this as the module's deliverable_files
# (finding 052).
#
# --built FILE is what the project's Makefile compiles, for a subject whose
# file list is "Makefile and all the necessary files": the .c files `make
# -Bn` named, one per line, as tools/student_build.sh wrote them (paths from
# the turn-in directory). A .c the Makefile never builds is not necessary, so
# it is listed under a heading of its own and counts as an extra file. A first
# line "unknown" says make could not plan the build, and an empty file that it
# compiles nothing (a stub): then no .c is judged, and the report says why
# (finding 164).
#
# A PROJECT IN PARTS, ALL AT THE ROOT. Where a subject is in parts (a
# mandatory part and a bonus, each with its own files) and every part turns
# in at the root of deliverable/, one folder holds every part's files, and a
# test per part that judged the whole folder reported each file nobody asked
# for once per part, and each part's files as extra in every other part's.
# So the folder is judged in two halves:
#
# --extras-elsewhere NAME is a part's own test: it judges the files that part
# names (--required, --optional) and nothing else. A file another part names
# (--sibling, repeatable) is listed as that part's, and every other file is
# counted in one line that sends the reader to NAME, the test that judges
# them -- c_levels() passes deliverable_files. --strict, --provided, --built,
# --program, --stray, --outside and --union are refused there: each is about
# the files no part asks for.
#
# --union is NAME: the whole folder, once, for every part. Every part's
# --required file comes as a --sibling (its own test reports it missing),
# the optional files of every part as --optional, and --provided, --program
# and --strict are the project's; --built is given once for each part whose
# build writes a manifest, and a .c counts as unbuilt only when no part's
# build compiles it, judged only when every part's build planned a list.
# --required, --expected, --extras-elsewhere, --build-target, --stray and
# --outside are refused there.
#
# Usage:
#   files_test.sh --label NAME [--required NAME]... [--optional NAME]...
#                 [--expected NAME]...
#                 [--provided NAME]... [--grader moulinette|defense|both]
#                 [--actual NAME]... [--actual-list FILE] [--strict] [--root]
#                 [--stray EXERCISES | --outside EXERCISES] [--built FILE]
#                 [--build-target NAME] [--program NAME]...
#                 [--sibling NAME]... [--extras-elsewhere TEST | --union]
#
# --program NAME is a program this exercise builds: c_program's name, or
# c_make's artifact. A file of that name in the turn-in is what a build left
# behind, never a file the subject asks for, and it FAILS whatever --strict
# says: a subject that leaves its file list open still asks for the program's
# sources, not the program (WP-59's ruling: build products fail at basic).
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "files_test.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require grep sed sort

# conventions: runs no student code -- it compares the names of the turned-in files with the subject's list

LABEL=""
STRICT=0
ROOT=0
STRAY=""
OUTSIDE=""
BUILT=""
T_BUILD=""
GRADER=""
REQ=""
OPT=""
EXP=""
PROV=""
ACT=""
PROGS=""
# A project in parts (above): the files other parts name, the test the
# files no part asks for are left to, the union mode, and every --built.
SIB=""
ELSEWHERE=""
UNION=0
BUILT_LIST=""
add() { if [ -z "$1" ]; then printf '%s' "$2"; else printf '%s\n%s' "$1" "$2"; fi; }

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "files_test.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--label) need "$1" "$#"; LABEL="$2"; shift 2 ;;
		--required) need "$1" "$#"; REQ=$(add "$REQ" "$2"); shift 2 ;;
		--optional) need "$1" "$#"; OPT=$(add "$OPT" "$2"); shift 2 ;;
		--expected) need "$1" "$#"; EXP=$(add "$EXP" "$2"); shift 2 ;;
		--provided) need "$1" "$#"; PROV=$(add "$PROV" "$2"); shift 2 ;;
		--grader)
			need "$1" "$#"
			case "$2" in
				moulinette | defense | both) GRADER="$2" ;;
				*) echo "files_test.sh: --grader is moulinette, defense or both, not '$2'" >&2; exit 2 ;;
			esac
			shift 2 ;;
		--actual) need "$1" "$#"; ACT=$(add "$ACT" "$2"); shift 2 ;;
		--actual-list)
			need "$1" "$#"
			[ -f "$2" ] || { echo "files_test.sh: no name list at $2" >&2; exit 2; }
			while IFS= read -r _n; do
				[ -n "$_n" ] && ACT=$(add "$ACT" "$_n")
			done < "$2"
			shift 2 ;;
		--strict) STRICT=1; shift ;;
		--root) ROOT=1; shift ;;
		--stray) need "$1" "$#"; STRAY="$2"; shift 2 ;;
		--outside) need "$1" "$#"; OUTSIDE="$2"; shift 2 ;;
		--built)
			need "$1" "$#"
			[ -f "$2" ] || { echo "files_test.sh: no build manifest at $2" >&2; exit 2; }
			BUILT="$2"; BUILT_LIST=$(add "$BUILT_LIST" "$2"); shift 2 ;;
		--build-target) need "$1" "$#"; T_BUILD="$2"; shift 2 ;;
		--program) need "$1" "$#"; PROGS=$(add "$PROGS" "$2"); shift 2 ;;
		--sibling) need "$1" "$#"; SIB=$(add "$SIB" "$2"); shift 2 ;;
		--extras-elsewhere) need "$1" "$#"; ELSEWHERE="$2"; shift 2 ;;
		--union) UNION=1; shift ;;
		*) echo "files_test.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

# What this test tests, in the words below: RL_UNIT_KIND, which
# tools/defs_test.bzl's _test() hands a test of a contract of units, or
# "exercise" (tools/runner_lib.sh's rl_noun, which this script does not
# source).
case "${RL_UNIT_KIND:-}" in
	"") NOUN=exercise ;;
	exercise | library | function | project | part) NOUN=$RL_UNIT_KIND ;;
	*)
		echo "files_test.sh: RL_UNIT_KIND is '$RL_UNIT_KIND', and a unit's kind is" >&2
		echo "  exercise, library, function, project or part (tools/subject.bzl): the harness is broken." >&2
		exit 2 ;;
esac

# The two halves of a project in parts, each refusing what is the other's.
# refuse_with MODE FLAG...: exit 2 naming every FLAG given.
refuse_with() {
	_rw_mode=$1
	shift
	[ "$#" -eq 0 ] && return 0
	echo "files_test.sh: $_rw_mode cannot be combined with:$(printf ' %s' "$@")" >&2
	exit 2
}
if [ -n "$ELSEWHERE" ]; then
	set --
	[ "$STRICT" = 0 ] || set -- "$@" --strict
	[ -z "$PROV" ] || set -- "$@" --provided
	[ -z "$BUILT_LIST" ] || set -- "$@" --built
	[ -z "$PROGS" ] || set -- "$@" --program
	[ -z "$STRAY" ] || set -- "$@" --stray
	[ -z "$OUTSIDE" ] || set -- "$@" --outside
	[ "$UNION" = 0 ] || set -- "$@" --union
	refuse_with "--extras-elsewhere (a part's own files)" "$@"
elif [ "$UNION" = 1 ]; then
	set --
	[ -z "$REQ" ] || set -- "$@" --required
	[ -z "$EXP" ] || set -- "$@" --expected
	[ -z "$T_BUILD" ] || set -- "$@" --build-target
	[ -z "$STRAY" ] || set -- "$@" --stray
	[ -z "$OUTSIDE" ] || set -- "$@" --outside
	refuse_with "--union (the files no part asks for)" "$@"
else
	[ -z "$SIB" ] || {
		echo "files_test.sh: --sibling names another part's file, for --extras-elsewhere or --union" >&2
		exit 2
	}
	if [ "$(printf '%s\n' "$BUILT_LIST" | grep -c .)" -gt 1 ]; then
		echo "files_test.sh: --built is given once, but for --union" >&2
		exit 2
	fi
fi

# has NAME LIST: whether NAME is one of the lines of LIST, compared whole.
has() {
	printf '%s\n' "$2" | grep -qxF -- "$1"
}

echo "files_test: ${LABEL:-deliverable}"
echo ""

# A FOLDER FOR NO EXERCISE OF THIS SUBJECT: everything in it is extra, and
# it FAILS whatever --strict says. --strict is about one exercise's own file
# list, which a subject may leave open ("and files needed for your
# program"); no list reaches a folder that is no exercise's at all.
if [ -n "$STRAY" ]; then
	echo "  THIS IS NO EXERCISE OF THIS SUBJECT. Its exercises are:"
	echo "    $(printf '%s' "$STRAY" | sed 's/,/ /g')"
	echo ""
	if [ -z "$ACT" ]; then
		# Empty to the push: the caller's list leaves out build products,
		# which //tools:submit never pushes either.
		echo "  Nothing in it is pushed: git pushes no empty folder, and //tools:submit"
		echo "  leaves out what a build leaves behind (objects, archives). Delete it."
		echo ""
		echo "  RESULT: PASS (with a warning)"
		exit 0
	fi
	echo "  What is in it, which no exercise grades, and which //tools:submit"
	echo "  pushes with the rest (a generator: the folder it makes):"
	printf '%s\n' "$ACT" | sed 's/^/    /'
	echo ""
	echo "  If it is an exercise's work under the wrong number, it belongs in"
	# conventions: the call site's --stray -- the exercises the contract lists
	echo "  the folder the subject names for that exercise. If not, delete it."
	echo ""
	# conventions: the call site's --stray -- the exercises the contract lists
	echo "  RESULT: FAIL — the subject asks for its own exercises' folders, and"
	echo "  this is none of them."
	exit 1
fi

# THE REST OF THE PUSHED TREE: what sits at the root of deliverable/, or in a
# folder that is no exercise's. The Vogsphere repository is deliverable/
# itself, so all of it is pushed, and no exercise grades any of it.
if [ -n "$OUTSIDE" ]; then
	if [ -z "$ACT" ]; then
		echo "  RESULT: PASS — every file is in the folder of one of this subject's"
		echo "  exercises ($(printf '%s' "$OUTSIDE" | sed 's/,/ /g'))."
		exit 0
	fi
	echo "  THESE ARE IN NO EXERCISE'S FOLDER. This subject gives each exercise a"
	echo "  turn-in directory of its own:"
	echo "    $(printf '%s' "$OUTSIDE" | sed 's/,/ /g')"
	echo "  and these files are beside them, at the root of what is pushed or in"
	echo "  a folder no exercise has:"
	printf '%s\n' "$ACT" | while IFS= read -r f; do
		case "$f" in
			*[[:space:]]*) printf "    '%s'\n" "$f" ;;
			*) printf '    %s\n' "$f" ;;
		esac
	done
	echo ""
	echo "  deliverable/ is the root of the repository //tools:submit pushes, so"
	echo "  every one of them is pushed, and nothing grades it. A folder whose"
	echo "  name is almost an exercise's (ex5, 'ex05 copy') is not that exercise:"
	echo "  the name is the subject's, exactly. Move each file into the exercise"
	echo "  folder it belongs to, or delete it."
	echo ""
	# conventions: the call site's --outside -- the exercises the contract lists
	echo "  RESULT: FAIL — the subject asks for its exercises' folders and"
	echo "  nothing beside them."
	exit 1
fi
MISSING=0
UNMADE=0
if [ "$UNION" = 1 ]; then
	echo "  EVERY FILE NO PART OF THIS PROJECT ASKS FOR, judged once for all of"
	echo "  them. Each part's own files are its own files test's to judge."
else
printf '  %-28s %s\n' "REQUIRED BY THE SUBJECT" "STATUS"
printf '  %-28s %s\n' "----------------------------" "----------"

# conventions: the call site's --required -- none given: the contract lists no file
[ -n "$REQ$EXP" ] || printf '  %-28s %s\n' "(the subject names no file)" "-"
fi
while IFS= read -r f; do
	[ -n "$f" ] || continue
	if has "$f" "$ACT"; then
		printf '  %-28s %s\n' "$f" "present"
	else
		printf '  %-28s %s\n' "$f" "MISSING <"
		MISSING=$((MISSING + 1))
	fi
done <<REQ_EOF
$REQ
REQ_EOF
while IFS= read -r f; do
	[ -n "$f" ] || continue
	if has "$f" "$ACT"; then
		printf '  %-28s %s\n' "$f" "present"
	else
		printf '  %-28s %s\n' "$f" "not produced (the output layer says why)"
		UNMADE=$((UNMADE + 1))
	fi
done <<EXP_EOF
$EXP
EXP_EOF

EXTRA=""
GRADERS=""
ALLOWED=""
SIBS=""
while IFS= read -r f; do
	[ -n "$f" ] || continue
	has "$f" "$REQ" && continue
	has "$f" "$EXP" && continue
	if has "$f" "$OPT"; then
		ALLOWED=$(add "$ALLOWED" "$f")
		continue
	fi
	if [ -n "$SIB" ] && has "$f" "$SIB"; then
		SIBS=$(add "$SIBS" "$f")
		continue
	fi
	if [ -n "$PROV" ] && has "$f" "$PROV"; then
		GRADERS=$(add "$GRADERS" "$f")
		continue
	fi
	EXTRA=$(add "$EXTRA" "$f")
done <<ACT_EOF
$ACT
ACT_EOF

# WHAT THE MAKEFILE BUILDS (--built). A .c the subject allows only as one of
# "all the necessary files" is necessary only if the Makefile compiles it: the
# rest leave ALLOWED for UNBUILT, which counts as extra. Judged only when make
# planned a build that compiles something -- a stub Makefile compiles nothing,
# and a make that failed says nothing -- and said either way.
UNBUILT=""
BUILT_NOTE=""
# Under --union, every part's list: one that could not be planned, or that
# compiles nothing yet, leaves every .c unjudged, and a .c is unbuilt only
# when no list names it.
built_any() {
	printf '%s\n' "$BUILT_LIST" | while IFS= read -r _bl; do
		[ -n "$_bl" ] || continue
		grep -qxF -- "$1" "$_bl" && echo y && break
	done | grep -q y
}
if [ -n "$BUILT" ]; then
	while IFS= read -r _bl; do
		[ -n "$_bl" ] || continue
		_first=""
		IFS= read -r _first < "$_bl" || :
		if [ "$_first" = unknown ]; then
			BUILT_NOTE="unknown"
		elif [ "$BUILT_NOTE" != unknown ] && ! grep -q . "$_bl"; then
			BUILT_NOTE="none"
		fi
	done <<BUILT_EOF
$BUILT_LIST
BUILT_EOF
	if [ -z "$BUILT_NOTE" ]; then
		_kept=""
		while IFS= read -r f; do
			[ -n "$f" ] || continue
			case "$f" in
				*.c)
					if ! built_any "$f"; then
						UNBUILT=$(add "$UNBUILT" "$f")
						continue
					fi ;;
			esac
			_kept=$(add "$_kept" "$f")
		done <<ALLOWED_EOF
$ALLOWED
ALLOWED_EOF
		ALLOWED=$_kept
	fi
fi

if [ -n "$ALLOWED" ]; then
	echo ""
	# conventions: the call site's --optional -- the files the contract allows without listing them
	echo "  ALLOWED, NOT REQUIRED: files the subject lets the turn-in hold without"
	echo "  naming them:"
	printf '%s\n' "$ALLOWED" | sed 's/^/    /'
fi

if [ -n "$GRADERS" ]; then
	echo ""
	# conventions: the call site's --provided -- the files the contract says the grader brings
	echo "  FILES THE GRADER BRINGS, which the subject says it supplies itself:"
	printf '%s\n' "$GRADERS" | sed 's/^/    /'
	echo "  Delete them from the turn-in: the grader uses its own copy, and"
	echo "  yours is one more file it did not ask for. The harness has the"
	echo "  grader's under this project's tests/, and builds with that one."
fi

if [ -n "$SIBS" ]; then
	echo ""
	if [ "$UNION" = 1 ]; then
		echo "  FILES A PART OF THIS PROJECT ASKS FOR, each judged by that part's test:"
	else
		echo "  FILES ANOTHER PART OF THIS PROJECT ASKS FOR, judged by its own test:"
	fi
	printf '%s\n' "$SIBS" | while IFS= read -r f; do
		case "$f" in
			*[[:space:]]*) printf "    '%s'\n" "$f" ;;
			*) printf '    %s\n' "$f" ;;
		esac
	done
fi

# A PART'S OWN TEST (--extras-elsewhere): the files it names, and a pointer
# for the rest, which the folder's own test reports once.
if [ -n "$ELSEWHERE" ]; then
	if [ -n "$EXTRA" ]; then
		echo ""
		echo "  $(printf '%s\n' "$EXTRA" | grep -c .) other file(s) here no part of this project asks for:"
		echo "  $ELSEWHERE reports them, once for the whole folder."
	fi
	echo ""
	if [ "$MISSING" -gt 0 ]; then
		echo "  RESULT: FAIL — $MISSING required file(s) missing."
		# conventions: the call site's --required -- the files the contract lists
		echo "  The subject names the files it wants, exactly. A file that is not"
		echo "  there cannot be graded, whatever the rest of the module does."
		exit 1
	fi
	if [ -z "$REQ" ]; then
		echo "  RESULT: PASS — this part names no file of its own, so which files"
		echo "  it needs is its build's to say."
		exit 0
	fi
	if [ -n "$ALLOWED" ]; then
		echo "  RESULT: PASS — every file this part names is here, and the rest of"
		echo "  its own are files it allows without naming them (above)."
		exit 0
	fi
	echo "  RESULT: PASS — every file this part names is here."
	exit 0
fi

if [ -n "$EXTRA" ]; then
	echo ""
	echo "  FILES THE SUBJECT DID NOT ASK FOR:"
	# Quoted when the name has a blank in it, so where it starts and ends
	# is visible: "ft_putchar copy.c" is ONE file.
	printf '%s\n' "$EXTRA" | while IFS= read -r f; do
		case "$f" in
			*[[:space:]]*) printf "    '%s'\n" "$f" ;;
			*) printf '    %s\n' "$f" ;;
		esac
	done
	if printf '%s\n' "$EXTRA" | grep -q '[^A-Za-z0-9._+/-]'; then
		echo ""
		echo "  A name holding a blank, a parenthesis or any character outside"
		echo "  A-Z a-z 0-9 . _ + - is how a desktop names a copy (ft_putchar copy.c,"
		echo "  ft_putchar (1).c). No other layer here reads such a file: they all"
		echo "  leave it out, so this is the one place it is reported."
	fi
	if printf '%s\n' "$EXTRA" | grep -q /; then
		echo ""
		echo "  A name with a / in it is in a subfolder of the turn-in directory."
		echo "  It is pushed all the same: //tools:submit pushes the whole tree,"
		echo "  and git does not stop at the first level."
	fi
fi

if [ -n "$UNBUILT" ] && [ "$UNION" = 1 ]; then
	echo ""
	echo "  SOURCES NO PART'S BUILD COMPILES, asked of 'make -Bn' for the rule"
	echo "  that builds each part:"
	printf '%s\n' "$UNBUILT" | while IFS= read -r f; do
		case "$f" in
			*[[:space:]]*) printf "    '%s'\n" "$f" ;;
			*) printf '    %s\n' "$f" ;;
		esac
	done
	echo "  This layer counts a source as turned in only when the build of some part"
	echo "  compiles it. One none compiles -- a test main, an old version -- is pushed"
	echo "  with the rest all the same. Does a program need it? Then the Makefile has"
	echo "  to name it. If not, delete it."
elif [ -n "$UNBUILT" ]; then
	echo ""
	echo "  SOURCES YOUR MAKEFILE DOES NOT BUILD, asked of 'make -Bn' (what a bare"
	echo "  'make' would compile):"
	printf '%s\n' "$UNBUILT" | while IFS= read -r f; do
		case "$f" in
			*[[:space:]]*) printf "    '%s'\n" "$f" ;;
			*) printf '    %s\n' "$f" ;;
		esac
	done
	echo "  This layer counts a source as turned in only when the Makefile compiles it."
	echo "  One it never compiles -- a test main, an old version, a bonus it builds"
	echo "  only on request -- is pushed with the rest all the same. Does the"
	echo "  program need it? Then the Makefile has to name it. If not, delete it."
fi
case "$UNION$BUILT_NOTE" in
	1unknown)
		echo ""
		echo "  'make -Bn' could not plan the build of every part (one whose rule is"
		echo "  not written yet, say), so which of the .c files here your Makefile"
		echo "  compiles is not known, and none is judged by it. Each part's build"
		echo "  layer says why." ;;
	1none)
		echo ""
		echo "  The build of a part compiles no .c file yet (a stub, or a rule that"
		echo "  builds something else), so which of the .c files here your Makefile"
		echo "  compiles is not known, and none is judged by it." ;;
	0unknown)
		echo ""
		echo "  'make -Bn' could not plan a build, so which of the .c files here"
		echo "  your Makefile compiles is not known, and none is judged by it."
		echo "  ${T_BUILD:-The build layer} says why make stopped." ;;
	0none)
		echo ""
		echo "  Your Makefile compiles no .c file yet (a stub, or a default goal"
		echo "  that builds something else), so which of the .c files here it"
		echo "  builds is not known, and none is judged by it." ;;
esac

# A root turn-in with its files one folder down: the subject has no turn-in
# directory, so ex00/Makefile is not the Makefile it asks for, and every
# layer says "missing" about files that are right there. Said once, with the
# command that fixes it, because nothing else in the report would.
if [ "$ROOT" -eq 1 ]; then
	_exdirs=$(printf '%s\n' "$EXTRA" | sed -n 's#^\(ex[0-9][0-9]\)/.*#\1#p' | sort -u)
	if [ -n "$_exdirs" ]; then
		echo ""
		echo "  THIS SUBJECT HAS NO TURN-IN DIRECTORY: its files go at the root of"
		echo "  deliverable/ -- the root of the repository that is pushed -- and not"
		echo "  in a folder of their own. To move them up:"
		for _d in $_exdirs; do
			echo "    git mv ${LABEL:+$LABEL/}$_d/* ${LABEL:-deliverable}/"
		done
	fi
fi

echo ""
if [ "$MISSING" -gt 0 ]; then
	echo "  RESULT: FAIL — $MISSING required file(s) missing."
	# conventions: the call site's --required -- the files the contract lists
	echo "  The subject names the files it wants, exactly. A file that is not"
	echo "  there cannot be graded, whatever the rest of the module does."
	exit 1
fi

# A BUILT PROGRAM among the extras: a file named as a program the exercise
# builds, anywhere in the tree. It fails even where extras only warn.
BUILT_PROG=""
if [ -n "$PROGS" ] && [ -n "$EXTRA" ]; then
	BUILT_PROG=$(printf '%s\n' "$EXTRA" | while IFS= read -r f; do
		has "${f##*/}" "$PROGS" && printf '%s\n' "$f"
	done)
fi
if [ -n "$BUILT_PROG" ]; then
	echo ""
	echo "  A BUILT PROGRAM, left in the turn-in:"
	printf '%s\n' "$BUILT_PROG" | sed 's/^/    /'
	echo "  It is named as the program this $NOUN builds: what a build left"
	# conventions: the call site's --program -- a program the contract does not list
	echo "  behind, not a file the subject asks for, and //tools:submit refuses to"
	echo "  push a module holding one. Run your cleaning rule, or delete it."
	if [ "$STRICT" -eq 0 ]; then
		echo ""
		# conventions: the call site's --program -- a program the contract does not list
		echo "  RESULT: FAIL — a built program is no file the subject asks for, even"
		echo "  where it leaves the rest of its file list open."
		exit 1
	fi
fi

if [ -n "$EXTRA$GRADERS$UNBUILT" ]; then
	if [ "$STRICT" -eq 1 ]; then
		echo "  RESULT: FAIL — this subject does not allow extra files."
		exit 1
	fi
	echo "  RESULT: PASS (with a warning)"
	if [ "$UNION" = 1 ]; then
		echo "  Each part's own files are its own test's to judge. The"
		echo "  extra one(s) above are not a"
	elif [ "$UNMADE" -gt 0 ]; then
		# conventions: the call site's --expected -- the files the contract lists that a build makes
		echo "  What the subject asks for and was not produced is the output"
		echo "  layer's to report. The extra one(s) above are not a"
	else
		echo "  Every required file is there. The extra one(s) above are not a"
	fi
	case "$GRADER" in
		defense | both)
			echo "  failure: this project is reviewed by a person, and an extra file is"
			echo "  sometimes justifiable. Be ready to say WHY it exists at the"
			echo "  evaluation, and remember //tools:submit pushes it too." ;;
		*)
			# conventions: the call site's --strict -- not given: the contract allows files beyond its list
			echo "  failure: the subject leaves the rest of its file list open. A"
			echo "  program grades this project, and nobody can tell it why a file is"
			echo "  there -- //tools:submit pushes it with the rest, so if the"
			echo "  program does not need it, delete it." ;;
	esac
	exit 0
fi

# What the PASS says is what was established, and no more.
if [ "$UNION" = 1 ]; then
	if [ -n "$ALLOWED" ]; then
		echo "  RESULT: PASS — nothing here that no part of this project asks for:"
		echo "  the rest are files a part allows without naming them (above)."
		exit 0
	fi
	echo "  RESULT: PASS — nothing here that no part of this project asks for."
	exit 0
fi
if [ "$UNMADE" -gt 0 ]; then
	echo "  RESULT: PASS — nothing here the subject did not ask for. $UNMADE file(s)"
	echo "  it asks for were not produced: the output layer reports that, with"
	echo "  the exercise's hints."
	exit 0
fi
if [ -z "$REQ$EXP" ]; then
	echo "  RESULT: PASS — nothing here the subject did not allow. It names no"
	echo "  file, so which files a turn-in needs is the build's to say."
	exit 0
fi
if [ -n "$ALLOWED" ]; then
	# conventions: the call site's --required -- the files the contract lists
	echo "  RESULT: PASS — every file the subject names is here, and the rest are"
	echo "  files it allows without naming them (above)."
	exit 0
fi
# conventions: the call site's --required -- the files the contract lists
echo "  RESULT: PASS — exactly the files the subject asks for."
exit 0
