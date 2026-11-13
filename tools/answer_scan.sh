#!/bin/sh
# answer_scan.sh — find an exercise's answer anywhere OUTSIDE the zone.
#
# From the repo root, on a tree WITH answers:
#   sh tools/answer_scan.sh
# The file names the subject contracts of BUILD files declare (one BUILD
# file on standard input when none is named):
#   sh tools/answer_scan.sh --declared [BUILD...]
# The checkout this file lives in, which is how the maintainer's test
# //tools/tests:answer_scan runs it (below):
#   answer_scan.sh --worktree
#
# --declared is the one reader of those lists: the template build's last
# check hands it the INDEX's BUILD files, so the two gates cannot disagree
# about which names the subject gives. It reads a contract through
# tools/units.awk, found beside it: the one reader of a contract's text
# outside Bazel.
#
# AGENTS.md §0: answers live under deliverable/ and generators/, and nowhere
# else -- not in a test, a fixture, a clue, a diagnostic script or a doc. The
# template build stubs the zone; this is what catches the answer that was copied
# OUT of it. It was written after four shell checks, a selftest fixture and
# env-audit.sh were all found carrying answers in the published template: the
# checks computed their expected value with the exercise's own command, and the
# audit ran three answers to watch them work. Every one of those was invisible to
# stub_check, which only ever looks inside the zone.
#
# So it runs where the answers ARE (main, or the template build before
# stubbing) and asks, for each one, whether it appears in any other tracked text
# file:
#
#   shell  every command line of every generators/exNN.sh (12 characters or
#          more), and every line of what the generator writes when run in a
#          scratch directory (6 or more: a turn-in can be one short command).
#          Searched as a SUBSTRING of every line elsewhere, with quotes, runs of
#          blanks and variable names ignored -- the leaks this was written for
#          sat inside a longer line (want=$(...)), one re-quoted and one with
#          its variable renamed. Comments and shebangs are not answers.
#          A script turned in from deliverable/ (C 09 ex00's, a *.sh there)
#          is the same answer in another place: its command lines are read
#          the same way, and never run -- it is a turn-in, not a generator,
#          and running one could compile, or delete, what it was written
#          for. A turn-in script whose name is not *.sh is not read yet,
#          and stops the run until a project that moves one under
#          deliverable/ adds its pathspec here (UNREAD BY ANY CLASS, below).
#   C      every run of FOUR consecutive lines inside a function body of a
#          deliverable .c file, compared as a run, blanks ignored. Lines that say
#          nothing about the answer are left out of the runs: braces, stub
#          lines ((void)x; and a bare return), declarations (int i;) and
#          zero initialisers (i = 0;). Measured on this tree, three-line runs
#          of what remained still matched a test's own print helper; four do
#          not, and a copied body of any real length is far longer than four.
#   defs   every macro with a body in a deliverable header (C 08's, Reloaded
#          ex22's -- a #define is the whole answer there), and every command and
#          assignment line of a deliverable Makefile (C 10, Reloaded ex24 and
#          ex27, BSQ ...), 12 characters or more. Compared with ALL blanks
#          removed, on both sides: `# define` and `#define` are the same line.
#          Include guards, stub lines (echo, :, true) and the assignments the
#          subjects dictate word for word (NAME, CC, CFLAGS, RM) are not
#          answers and are left out. So is a Makefile line that is nothing
#          but paths the subject gives (see names, below): C 09 ex01's
#          srcs/ft_strcmp.c is the grader's file, and its BUILD file names
#          it where the harness stages that file.
#
#   key    one answer has no source in the zone to copy: Shell 00 ex03's
#          turn-in is a public key, and ANY complete ed25519 public key passes
#          its check. So a whole one, anywhere outside the zone, is a hit on
#          its own -- env-audit.sh shipped exactly that as a "test vector".
#
#   names  what only the answers NAME: every struct, union and enum tag, type
#          name, macro and static function a deliverable defines, and every
#          deliverable's file name. A design leaks without a line of its code:
#          the published template shipped comments naming one team's rush-00
#          structs and a scratch file the template did not even contain, and
#          those are exactly the choices a subject that fixes no names leaves
#          to the student. A name is not reported when the SUBJECT gives it --
#          it appears in a module's tests/ code or data (a test, a fixture, an
#          expected output, a prototype.h), or is a `_`-bounded part of a name
#          there, or the subject contract declares it (a library's
#          <function>.c included, where one of its file patterns, Libft's
#          ft_*.c, takes it), or it is a path the
#          contract's `provided` puts the grader's files at -- nor when a STUB
#          keeps it:
#          an include guard, anything in a file stub_check.sh accepts as it
#          stands, and the file name of a header stub_check.sh approves. A clue
#          or a Markdown file under tests/ gives nothing: it is prose, the very
#          text this class reads, and a clue that leaked a name would otherwise
#          vouch for it everywhere, itself included. Matched as a whole word.
#          COMMON_NAMES below lists, with reasons, the few names the harness's
#          own prose uses as examples.
#
# What it cannot see: an answer too short to be told from an idiom -- a one-line
# C body, a turn-in under six characters. Those are also the answers a copy
# gives away least. Nor a name that is one lowercase word, like a helper called
# by a single plain word: prose is made of those, and neither prose nor code
# form tells a leaked one from the harness's own vocabulary (measured -- see the
# names list below). A coined one-word helper named in shipped text passes
# unseen. Nor two kinds of zone file no class reads, each let by for its
# reason (UNREAD BY ANY CLASS, below): a README.md at the root of a
# deliverable/, and a file 42 issues with a subject.
#
# It prints WHERE (file:line, and which answer it matches -- for a name, the
# name and what defines it), never the text, and exits 1 if anything matched, 0
# if nothing did, 2 if it could not scan -- a tree with no answers in it (the
# template after stubbing) has nothing to look for, and saying "clean" there
# would be a scan that searched nothing; and a file of the zone it could not
# read is an answer it never looked for, so that ends the run with 2 as well,
# and so does one of a kind no class reads.
# A tracked file of the zone that is missing from the work tree -- deleted
# and not yet staged, or a throwaway tree holding other answers -- is no such
# file: its answer is in the index, and is read from there (and said so).
#
# Maintainer-only files are not scanned: TODO.md, the folder todo/ beside it
# and HISTORY.md never leave the private repo.
#
# WHERE IT RUNS. The template build ran it, and nothing else did: an
# answer's identifiers copied out of the zone on main, in nine places, once,
# were found at publish time, by a gate that then refused to publish (TO
# VERIFY V29). So the maintainer's branch also runs it as a test,
# //tools/tests:answer_scan, in every `bazel test //...` -- each stream's own
# run and every merge's -- which the template does not ship: a student's tree
# holds answers of their own, and what this reports there is not measured. A
# test sees no BUILD_WORKSPACE_DIRECTORY, and its $0 is a link in the runfiles
# tree, so --worktree reads the checkout off the link's target: the tree as it
# stands, tracked files only, as the template build reads it. Undeclared
# input, so the test is never cached (tags external).
#
# conventions: runs no student code -- it reads the tracked tree; the only programs it starts are the zone's generators, in a scratch folder, to read what they write
# conventions: harness tool STUB_CHECK -- tools/stub_check.sh, which reads a file and runs nothing

set -u

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "answer_scan.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat dirname find git grep mkdir mktemp mv readlink rm sed setsid sort tr wc

# A test's scratch files go under TEST_TMPDIR, which Bazel empties, and not
# in the machine's /tmp, the TMPDIR Bazel sets when the shell that ran it set
# none (tools/runner_lib.sh, "THE SCRATCH FOLDER").
case ${TMPDIR:-/tmp} in /tmp | /tmp/) [ -z "${TEST_TMPDIR:-}" ] || export TMPDIR="$TEST_TMPDIR" ;; esac

MODE=scan
FROM_SELF=0
case "${1:-}" in
	"") ;;
	--declared) MODE=declared; shift ;;
	--worktree) FROM_SELF=1 ;;
	*) echo "answer_scan.sh: unknown argument '$1' (--declared, or --worktree)" >&2; exit 2 ;;
esac

# The bare file names a project's subject contract declares: each unit's
# `files` and `optional` lists, as tools/units.awk reads them (its file
# rows). A string with a slash or a wildcard is a path or a glob's argument,
# not a name.
#
# C_FILES_CALL reads the `required` and `optional` lists of a c_files()
# call, which BUILD files held before the contract and c_files() takes no
# longer (tools/defs_files.bzl). Only --declared reads with it, for one case:
# verifying a template index from before subject(). A scan never meets such
# a file -- it reads the BUILD files of its own tree, which Bazel would refuse
# with one -- so it reads the contract alone.
C_FILES_CALL='
{ sub(/#.*/, "") }
!inc && /(^|[^A-Za-z_0-9])c_files[ \t]*\(/ {
	inc = 1; depth = 0; s = $0; sub(/.*c_files[ \t]*/, "", s)
}
inc {
	if (s == "") s = $0
	while (s != "") {
		if (match(s, /^"[^"]*"/)) {
			v = substr(s, 2, RLENGTH - 2)
			if (ld > 0 && v !~ /[\/*]/ && v != "") print v
			s = substr(s, RLENGTH + 1); continue
		}
		if (match(s, /^[A-Za-z_][A-Za-z_0-9]*/)) {
			w = substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1)
			if (depth == 1 && ld == 0) want = (w == "required" || w == "optional")
			continue
		}
		c = substr(s, 1, 1); s = substr(s, 2)
		if (c == "(") depth++
		else if (c == ")") { if (--depth == 0) { inc = 0; want = 0; ld = 0; break } }
		else if (c == "[") { if (ld > 0 || want) ld++ }
		else if (c == "]") { if (ld > 0) ld-- }
		else if (c == "," && depth == 1 && ld == 0) want = 0
	}
	s = ""
}'
# tools/units.awk: beside this script first (the template build runs
# SOURCE's copies of both from one folder, and the selftest runs this from
# the runfiles' tools/), then the workspace's, once WS is known (below).
UNITS_AWK="$(CDPATH='' cd "$(dirname "$0")" && pwd)/units.awk"
# contract_files BUILD LIST... -- the strings of those lists of BUILD's
# subject() contract (files, optional; provided: its destinations), one a
# line, as tools/units.awk reads them. Nothing for a file with no contract.
# False, with units.awk's own words on stderr, for one it cannot read.
# A files or optional list it reads only in part (joined with + to a name
# or a call it does not follow, as one rush's is) gives the names it did
# read, and true, with a line on stderr naming the BUILD file, the unit and
# the list: a name only the unread part gives is then not given, so a
# mention of it outside the zone is reported as an answer's, and the line
# says why. Refusing it instead would end every scan at that rush. A
# provided dict read in part is dropped without a word (Reloaded's PUTCHAR,
# in the scan below).
contract_files() {
	_cf_rows=$(LC_ALL=C awk -v rows=files -f "$UNITS_AWK" "$1")
	case $? in
		0 | 1) ;;
		*)
			echo "answer_scan.sh: tools/units.awk cannot read the subject() contract of $1 (above)" >&2
			return 2 ;;
	esac
	_cf_b=$1
	shift
	printf '%s\n' "$_cf_rows" | awk -F'\t' -v lists=" $* " -v b="$_cf_b" '
		!index(lists, " " $2 " ") { next }
		$3 != "" { print $3; next }
		$2 != "provided" {
			printf "answer_scan.sh: %s: %s\047s %s is read in part (tools/units.awk): a name only its unread part gives is not given\n", b, $1, $2 > "/dev/stderr"
		}'
}
if [ "$MODE" = declared ]; then
	[ -f "$UNITS_AWK" ] || {
		echo "answer_scan.sh: --declared: no units.awk beside this script, the reader of a subject() contract" >&2
		exit 2
	}
	# One BUILD file on standard input, as `--declared < BUILD.bazel`.
	if [ $# -eq 0 ]; then
		_dt=$(mktemp) || exit 2
		cat > "$_dt"
		set -- "$_dt"
	fi
	_drc=0
	for _db in "$@"; do
		_dn=$(contract_files "$_db" files optional) || _drc=2
		printf '%s\n' "$_dn" | awk '$0 != "" && !/[\/*]/'
		awk "$C_FILES_CALL" < "$_db"
	done
	[ -z "${_dt:-}" ] || rm -f "$_dt"
	exit "$_drc"
fi

if [ "$FROM_SELF" = 1 ]; then
	# The checkout whose tools/answer_scan.sh this is (WHERE IT RUNS, above):
	# $0 is a link to it, through the runfiles tree, and only that file says
	# which tree. A link that leads anywhere else, or to no git checkout, is
	# a wiring error: a scan of the wrong tree, or of none, would read clean.
	_self=$(readlink -f "$0" 2> /dev/null) || _self=""
	case "$_self" in
		*/tools/answer_scan.sh) WS=${_self%/tools/answer_scan.sh} ;;
		*)
			echo "answer_scan.sh: --worktree: $0 leads to '${_self:-nothing}', not to a checkout's tools/answer_scan.sh" >&2
			exit 2 ;;
	esac
	# git's own words go out with the refusal: where git refuses a checkout
	# another user owns, they are the only line saying what to fix.
	git -C "$WS" rev-parse --is-inside-work-tree > /dev/null || {
		echo "answer_scan.sh: --worktree: $WS, where this file lives, is not a git checkout" >&2
		exit 2
	}
else
	WS="${BUILD_WORKSPACE_DIRECTORY:-$(CDPATH='' cd "$(dirname "$0")/.." && pwd)}"
fi

# stub_check.sh is the authority on what a stub keeps, so the names class asks
# it rather than keeping a second copy of its rules. Beside this script first:
# the selftest runs this on a fixture repo that has no tools/. Then the
# workspace's: `bazel run` starts this from bazel-bin/tools/, and stub_check.sh
# is not there.
STUB_CHECK="$(CDPATH='' cd "$(dirname "$0")" && pwd)/stub_check.sh"
[ -f "$STUB_CHECK" ] || STUB_CHECK="$WS/tools/stub_check.sh"
[ -f "$STUB_CHECK" ] || {
	echo "answer_scan.sh: no stub_check.sh beside this script or in $WS/tools -- it decides what a stub keeps" >&2
	exit 2
}

# Made absolute: the zone loop below runs it from the root of the index's
# copy as well as from here.
case "$STUB_CHECK" in /*) ;; *) STUB_CHECK=$(pwd)/$STUB_CHECK ;; esac

# tools/units.awk, as stub_check.sh is found: beside this script (above),
# then the workspace's. After stub_check.sh, whose refusal names it first.
[ -f "$UNITS_AWK" ] || UNITS_AWK="$WS/tools/units.awk"
[ -f "$UNITS_AWK" ] || {
	echo "answer_scan.sh: no units.awk beside this script or in $WS/tools -- it reads the subject contracts" >&2
	exit 2
}

cd "$WS" || exit 2

# Names the harness's own prose uses as plain examples, one per line with the
# reason. Nothing else is exempt by name: a name belongs here only when using it
# tells a reader nothing about how any answer is built.
COMMON_NAMES='
is_whitespace symbols_test.sh names it as the stock example of a helper that must be static
'

TMP=$(mktemp -d) || exit 2
# A signal that stops the scan while a generator of the tree runs (a test's
# limit, the template build's bound on the scan, a ^C) ends that generator
# and every process it started, and names it (below, where the generators
# run). Each runs in a session of its own, so its pid is its process
# group's, and the group is killed whole: killing the generator's shell
# alone left the child it waited on running after the scan was gone. Its
# pid too, for a generator stopped before it left this group.
_as_gen=""
_as_pid=""
as_stop() {  # as_stop STATUS -- stopped by a signal: end the running generator's group, name it, exit STATUS
	if [ -n "$_as_pid" ]; then
		kill -s KILL -- "-$_as_pid" "$_as_pid" 2> /dev/null
		echo "answer_scan.sh: stopped while $_as_gen ran; the scan did not finish" >&2
	fi
	exit "$1"
}
trap 'rm -rf "$TMP"' EXIT
trap 'as_stop 143' TERM
trap 'as_stop 130' INT
trap 'as_stop 129' HUP

# ------------------------------------------------------------------ answers
: > "$TMP/shell"   # normalized line <TAB> source
: > "$TMP/c"       # normalized 3-line run <TAB> source
: > "$TMP/defs"    # line with every blank removed <TAB> source

# ONE NAME PER LINE, and every loop over the zone in this shell. Each list is
# `git ls-files -z` through tr: listed without -z, git quotes a name holding a
# byte above 0x7f ("ft_acc\303\251.c"), and a quoted name is no file -- the
# zone's listing below was such a one, and an answer named with an accent had
# its definitions never read, so a static helper only it names passed unseen
# in a harness file. And each loop reads its list by redirection, not from a
# pipe: a pipe's loop is a subshell, where unread() below would end the loop
# and not the run.
#
# unread FILE -- end the run: a file of the zone this could not read is one
# whose answer was never looked for, so no verdict on the tree can follow.
unread() {
	echo "answer_scan.sh: '$1' is tracked in the zone but could not be read." >&2
	echo "             Refusing the whole run: its answer was never looked for, so" >&2
	echo "             no verdict on the tree can follow." >&2
	exit 2
}
# zone_list FILE PATHSPEC... -- the tracked paths matching PATHSPEC into FILE,
# one per line, as they are.
zone_list() {
	_zl=$1
	shift
	git ls-files -z -- "$@" > "$_zl.z" || {
		echo "answer_scan.sh: git could not list the index (git ls-files -- $*)" >&2
		exit 2
	}
	tr '\0' '\n' < "$_zl.z" > "$_zl"
}
# ABSENT FROM THE WORK TREE. A tracked file of the zone that is not on disk
# -- a deletion not yet staged, or a throwaway tree laid over with another
# set of answers -- was "could not be read", exit 2: the maintainer's test
# went red on an unstaged delete, and on every tree whose answers are not
# the index's (review of W7-V29). Its answer is still in the index, and an
# answer copied out of the zone before the delete is still a leak, so it is
# read from there: copied once into $TMP/index/<path>, and every reader
# below takes that copy (zat). A path the index cannot give either is
# unread, as before, and git's stderr goes out as it is: a blob it gives
# prints nothing there, and where it gives none (a blob missing from the
# object store, a path a merge left in conflict), its line says why.
zone_list "$TMP/tracked" '*/deliverable/*' '*/generators/*'
while IFS= read -r f; do
	{ [ -e "$f" ] || [ -L "$f" ]; } && continue
	mkdir -p "$TMP/index/${f%/*}" || unread "$f"
	git show ":$f" > "$TMP/index/$f" || unread "$f"
	echo "answer_scan.sh: '$f' is tracked and not in the work tree: its answer is read from the index." >&2
done < "$TMP/tracked"
# zat PATH -- sets _zat to where the zone file PATH is read: the work tree's
# copy, or the index's (above).
zat() {
	_zat=$1
	[ -e "$1" ] || [ -L "$1" ] || _zat=$TMP/index/$1
}

zone_list "$TMP/gens" '*/generators/ex*.sh'
zone_list "$TMP/cs" '*/deliverable/*.c'
zone_list "$TMP/hs" '*/deliverable/*.h'
zone_list "$TMP/mks" '*/deliverable/*Makefile'
zone_list "$TMP/dsh" '*/deliverable/*.sh'
[ -s "$TMP/gens" ] || [ -s "$TMP/cs" ] || [ -s "$TMP/hs" ] || [ -s "$TMP/mks" ] ||
	[ -s "$TMP/dsh" ] || {
	echo "answer_scan.sh: nothing tracked in the zone -- nothing to scan for" >&2
	exit 2
}
# UNREAD BY ANY CLASS. The lists above read a zone file by its kind, and a
# file of any other kind was never compared with anything: a script turned
# in with no .sh in its name, or a generator not named exNN.sh, had a line
# of it copied into a doc and the scan said OK (V309). The zone is set by
# role, not by kind (AGENTS.md §0), so a tracked file of it that no list
# reads ends the run, exit 2, until its kind is added to a class in the same
# change: a C++ project's first .cpp is one. stub_check.sh refuses a
# deliverable of a kind it does not know too, and adding a kind there makes
# this scan read nothing more: hence this check. Two kinds are let by, each
# for its reason, and nothing else:
#   - a README.md at the root of a deliverable/: prose a Common Core subject
#     asks for, and whether it is read, and how, is the owner's open
#     question (TO VERIFY V207);
#   - a file 42 issues with a subject, at the path tools/resources.tsv
#     registers for it (in the index, like everything here), as stub_check.sh
#     takes them: rush-02's numbers.dict is 42's data, not an answer.
git show :tools/resources.tsv 2> /dev/null |
	awk -F'\t' '!/^#/ && NF >= 3 { print $3 }' > "$TMP/issued"
cat "$TMP/gens" "$TMP/cs" "$TMP/hs" "$TMP/mks" "$TMP/dsh" "$TMP/issued" |
	awk 'NR == FNR { read[$0] = 1; next }
		!($0 in read) && $0 !~ /\/deliverable\/README\.md$/' - "$TMP/tracked" > "$TMP/unclaimed"
if [ -s "$TMP/unclaimed" ]; then
	while IFS= read -r f; do
		echo "answer_scan.sh: '$f' is tracked in the zone, and no class here reads it." >&2
	done < "$TMP/unclaimed"
	echo "             Refusing the whole run: an answer in it would never be looked" >&2
	echo "             for. Add its kind to a class here, in the same change." >&2
	exit 2
fi

# A C body line worth comparing, as awk: not a brace, not a stub line, not a
# plain declaration, not a zero initialiser. Shared by both sides.
CKEEP='function ckeep(r) {
	if (r == "" || r == "{" || r == "}") return 0
	if (r ~ /^\(void\)[A-Za-z_][A-Za-z_0-9]*;$/) return 0
	if (r ~ /^return( ?\((0|NULL)\))?;$/) return 0
	if (r ~ /^(unsigned |signed |const |static )*(int|char|long|short|size_t|t_[a-z_]+)( ?\*+ ?| )[A-Za-z_][A-Za-z_0-9]*(\[[^]]*\])?;$/) return 0
	if (r ~ /^[A-Za-z_][A-Za-z_0-9]* = (0|NULL);$/) return 0
	return 1
}'

# Normalize: drop quotes, name every variable $V, squeeze blanks, trim. Shared
# by both sides.
NORM='{ l = $0; gsub(/["'"'"']/, "", l); gsub(/\$\{?[A-Za-z_][A-Za-z_0-9]*\}?/, "$V", l); gsub(/[ \t]+/, " ", l); sub(/^ /, "", l); sub(/ $/, "", l) }'

# A C line with its comments dropped and its literals emptied, as awk: code(s)
# reads it character by character, keeping in st whether a block comment or a
# literal is still open, so a /* that sits in a string, a '}' char literal or a
# comment over several lines is told apart from code. A regex pass cannot tell
# them apart. Shared by the C-run reader and CDEFS (below); st starts empty in
# each file.
CLEX='
function code(s,   out, i, c, n) {
	out = ""; n = length(s)
	for (i = 1; i <= n; i++) {
		c = substr(s, i, 1)
		if (st == "/*") {
			if (c == "*" && substr(s, i + 1, 1) == "/") { st = ""; i++ }
			continue
		}
		if (st != "") {
			if (c == "\\") i++
			else if (c == st) { out = out c; st = "" }
			continue
		}
		if (c == "/" && substr(s, i + 1, 1) == "*") { st = "/*"; i++; out = out " "; continue }
		if (c == "/" && substr(s, i + 1, 1) == "/") break
		if (c == "\"" || c == "\047") st = c
		out = out c
	}
	if (st != "/*") st = ""
	return out
}
'

while IFS= read -r g; do
	zat "$g"
	awk -v src="$g" "$NORM"'
		l ~ /^#/ || length(l) < 12 { next }
		{ print l "\t" src }' < "$_zat" >> "$TMP/shell" || unread "$g"
	# What the generator writes is the turn-in itself. Run it in a scratch
	# directory; a generator that needs a fixture it cannot find just produces
	# less, which is fine -- its own lines were read above. It is the tree's
	# own code, and one that never ended hung the scan with nothing naming
	# it. This file is a test's runner, so it sets no limit of its own
	# (tools/conventions.sh, "Student code runs under the time budget"): the
	# test's limit stops it there, and the template build bounds the whole
	# scan where it runs it. The generator runs in the background of a
	# `wait`, which a signal interrupts, so whatever stops the scan ends that
	# generator too and names it (as_stop): a test runner may forward its
	# TERM to this process alone. It runs in a session of its own (setsid),
	# whose process group as_stop kills whole, the children it waits on
	# included. setsid and not `set -m`: dash turns job control off where no
	# terminal is, as under a test. So a signal sent to the scan's group
	# reaches the generator only through as_stop, and a KILL to the scan,
	# which no trap sees, leaves it running. setsid forks only for a group's
	# leader, which a job of this shell, with no job control, never is; -w
	# keeps the wait whole even then. The cd is in the sh it starts, so
	# setsid, sh and the generator are one pid, the one $! holds.
	d="$TMP/run"; rm -rf "$d"; mkdir -p "$d"
	case "$_zat" in /*) _zg=$_zat ;; *) _zg=$WS/$_zat ;; esac
	_as_gen=$g
	# conventions: harness tool -- no test's input: a generator of the tree under scan, run once in a scratch folder only to read what it writes
	setsid -w sh -c 'cd "$1" && exec sh "$2"' answer_scan.sh "$d" "$_zg" > /dev/null 2>&1 < /dev/null &
	_as_pid=$!
	wait "$_as_pid"
	_as_pid=""
	find "$d" -type f 2> /dev/null | while IFS= read -r f; do
		grep -Iq . "$f" 2> /dev/null || continue
		awk -v src="$g (its output)" "$NORM"'
			l ~ /^#/ || length(l) < 6 { next }
			{ print l "\t" src }' < "$f" >> "$TMP/shell"
	done
done < "$TMP/gens"
# A script turned in from deliverable/: its own lines, as a generator's are
# read above, and nothing it would write -- it is never run (the header).
while IFS= read -r g; do
	zat "$g"
	awk -v src="$g" "$NORM"'
		l ~ /^#/ || length(l) < 12 { next }
		{ print l "\t" src }' < "$_zat" >> "$TMP/shell" || unread "$g"
done < "$TMP/dsh"

while IFS= read -r c; do
	zat "$c"
	awk -v src="$c" "$CKEEP$CLEX"'
		# Body lines only: depth >= 1 before the line is read. Comments and
		# literals do not move the depth: braces are counted on code(raw).
		{
			raw = $0
			line = code(raw)
			if (depth >= 1) {
				l = raw
				gsub(/[ \t]+/, " ", l); sub(/^ /, "", l); sub(/ $/, "", l)
				if (ckeep(l)) body[++n] = l
			}
			o = gsub(/\{/, "{", line); cl = gsub(/\}/, "}", line)
			depth += o - cl
			if (depth < 1 && n > 0) { flush() }
		}
		function flush(   i) {
			for (i = 1; i + 3 <= n; i++)
				print body[i] " | " body[i + 1] " | " body[i + 2] " | " body[i + 3] "\t" src
			n = 0
		}
		END { flush() }' < "$_zat" >> "$TMP/c" || unread "$c"
done < "$TMP/cs"
# Headers: a #define with parameters or a value. A bare one is an include
# guard, which every header has and which answers nothing.
while IFS= read -r h; do
	zat "$h"
	awk -v src="$h" '
		/^[ \t]*#[ \t]*define[ \t]+[A-Za-z_][A-Za-z_0-9]*(\(|[ \t]+[^ \t])/ {
			l = $0; gsub(/[ \t]/, "", l)
			if (length(l) >= 12) print l "\t" src
		}' < "$_zat" >> "$TMP/defs" || unread "$h"
done < "$TMP/hs"
# Makefiles: recipe and assignment lines, not comments, not the stub's echo/:/
# true, not the assignments the subjects spell out for everyone alike. A line
# that is only paths -- a continued list of sources -- is also noted in
# $TMP/pathlines, with its paths: once the subject's names are known (below),
# one whose every path the subject gives is no answer line.
: > "$TMP/pathlines"   # line with every blank removed <TAB> its paths
while IFS= read -r m; do
	zat "$m"
	awk -v src="$m" -v pl="$TMP/pathlines" '
		{ l = $0; gsub(/[ \t]/, "", l) }
		l == "" || l ~ /^#/ { next }
		l ~ /^[-@+]*(echo|:|true)/ { next }
		l ~ /^(NAME|CC|CFLAGS|RM):?=/ { next }
		length(l) >= 12 {
			print l "\t" src
			p = $0; sub(/\\[ \t]*$/, "", p)
			if (p ~ /^[ \t]*[A-Za-z0-9_.\/-]+([ \t]+[A-Za-z0-9_.\/-]+)*[ \t]*$/)
				print l "\t" p >> pl
		}' < "$_zat" >> "$TMP/defs" || unread "$m"
done < "$TMP/mks"
sort -u -o "$TMP/shell" "$TMP/shell"
sort -u -o "$TMP/c" "$TMP/c"
sort -u -o "$TMP/defs" "$TMP/defs"

# ------------------------------------------------------------------ names
# What a C file defines, as kind <TAB> name <TAB> file. Comments are dropped and
# literals emptied first, character by character (code(), in CLEX above): a
# regex pass cannot tell a `/*` that opens a comment from one inside a string,
# and a macro whose value holds one hid every definition after it. The C-run
# reader had the same blind spot, a '}' char literal ending every later body's
# comparison. An include guard is not reported,
# because every stub keeps it.
CDEFS="$CLEX"'
# A name reserved to the implementation -- a _ and then an uppercase letter or
# another _: _GNU_SOURCE, _DEFAULT_SOURCE, __attribute__ -- belongs to the C
# library and the compiler, so it says nothing of whose answer defined it, and
# a harness file that defines the same one (tools/path_redirect.c) was a hit
# on a tree whose answer did.
function emit(kind, name) {
	if (name ~ /^[A-Za-z_][A-Za-z_0-9]*$/ && !(name in KW) && name !~ /^_[A-Z_]/)
		print kind "\t" name "\t" src
}
BEGIN {
	n = split("auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while", k, " ")
	for (i = 1; i <= n; i++) KW[k[i]] = 1
}
FNR == 1 { st = ""; pend = ""; td = ""; split("", IFN) }
{
	l = code($0)
	# `struct s_x` ending a line opens a definition only if `{` comes next.
	if (pend != "" && l !~ /^[ \t]*$/) {
		if (l ~ /^[ \t]*\{/) emit("tag", pend)
		pend = ""
	}
	if (match(l, /^[ \t]*#[ \t]*ifndef[ \t]+[A-Za-z_][A-Za-z_0-9]*/)) {
		m = substr(l, RSTART, RLENGTH); sub(/.*ifndef[ \t]+/, "", m); IFN[m] = 1
	}
	if (match(l, /^[ \t]*#[ \t]*define[ \t]+[A-Za-z_][A-Za-z_0-9]*/)) {
		m = substr(l, RSTART, RLENGTH); rest = substr(l, RSTART + RLENGTH)
		sub(/.*define[ \t]+/, "", m)
		if (!((m in IFN) && rest ~ /^[ \t]*$/)) emit("macro", m)
		next
	}
	if (match(l, /(struct|union|enum)[ \t]+[A-Za-z_][A-Za-z_0-9]*[ \t]*(\{|$)/)) {
		m = substr(l, RSTART, RLENGTH); sub(/^(struct|union|enum)[ \t]+/, "", m)
		if (m ~ /\{$/) { sub(/[ \t]*\{$/, "", m); emit("tag", m) }
		else { sub(/[ \t]*$/, "", m); pend = m }
	}
	# A typedef ends at the first `;` outside its braces; its name is the last
	# word before it, or the one in `(*name)` for a function pointer.
	if (td == "" && l ~ /^[ \t]*typedef[ \t]/) td = " "
	if (td != "") {
		td = td " " l
		t = td; o = gsub(/\{/, "{", t); cl = gsub(/\}/, "}", t)
		if (o == cl && index(l, ";")) {
			t = td; sub(/;[^;]*$/, "", t); m = ""
			if (match(t, /\([ \t]*\*[ \t]*[A-Za-z_][A-Za-z_0-9]*[ \t]*\)/)) {
				m = substr(t, RSTART + 1, RLENGTH - 2); gsub(/[ \t*]/, "", m)
			} else {
				sub(/([ \t]*\[[^]]*\])+[ \t]*$/, "", t); sub(/[ \t]+$/, "", t)
				if (match(t, /[A-Za-z_][A-Za-z_0-9]*$/)) m = substr(t, RSTART, RLENGTH)
			}
			emit("typedef", m); td = ""
		}
	}
	if (l ~ /^static[ \t]/ && match(l, /[A-Za-z_][A-Za-z_0-9]*[ \t]*\(/) &&
	    index(substr(l, 1, RSTART), "=") == 0) {
		m = substr(l, RSTART, RLENGTH); sub(/[ \t]*\($/, "", m); emit("static", m)
	}
}'

# Everything in the zone, sorted by what a stub makes of it.
sh "$STUB_CHECK" --approved > "$TMP/approved" || {
	echo "answer_scan.sh: stub_check.sh --approved failed" >&2
	exit 2
}
: > "$TMP/named"   # kind <TAB> name <TAB> where it is defined
: > "$TMP/csrc"    # the C files whose definitions are the answer's own
zone_list "$TMP/zone" '*/deliverable/*'
while IFS= read -r f; do
	# A file stub_check accepts as it stands ships as it stands; one it could
	# not read (exit 2) is one nothing here has read either. Exit 2 is also a
	# file it read and refused, empty, with no 42 header, or with one whose
	# border ends in a carriage return, so its own words go out with the
	# refusal: "could not be read" over a file read whole sent the reader
	# looking for a permission problem. A CRLF stub was exit 1 until
	# stub_check read lines without their \r, and was scanned as an answer;
	# it ends the run now, as every file the template build would refuse does.
	case "$f" in
		*.c|*.h)
			_sc=0
			zat "$f"
			# Handed over by its repository path, from the root it sits
			# under (the index's copy has one too), and that root named as
			# the workspace: stub_check approves a header at its place in
			# the workspace, and $TMP/index/<path> is no such place -- nor,
			# with a scratch folder inside the checkout, is
			# <scratch>/index/<path> under this one.
			_zr=.
			case "$_zat" in "$TMP/index/"*) _zr=$TMP/index ;; esac
			( cd "$_zr" && BUILD_WORKSPACE_DIRECTORY=$(pwd) sh "$STUB_CHECK" --file "./$f" ) > "$TMP/stub_check.out" 2>&1 || _sc=$?
			case "$_sc" in
				0) continue ;;
				1) echo "$f" >> "$TMP/csrc" ;;
				*)
					cat "$TMP/stub_check.out" >&2
					echo "answer_scan.sh: stub_check.sh refused '$f' (above, exit $_sc)." >&2
					echo "             Refusing the whole run: a file of the zone it has no verdict" >&2
					echo "             on is one whose answer was never looked for." >&2
					exit 2 ;;
			esac ;;
	esac
	# An approved header ships too -- reduced, but under the same name.
	_approved=0
	while IFS= read -r _g; do
		# shellcheck disable=SC2254
		case "$f" in $_g) _approved=1 ;; esac
	done < "$TMP/approved"
	[ "$_approved" -eq 1 ] || printf 'file\t%s\t%s\n' "${f##*/}" "$f" >> "$TMP/named"
done < "$TMP/zone"
while IFS= read -r c; do
	zat "$c"
	awk -v src="$c" "$CDEFS" < "$_zat" >> "$TMP/named" || unread "$c"
done < "$TMP/csrc"

# What the subject names: every word in a module's tests/, every name the
# subject contract declares, every program a Makefile must build (a BUILD
# file's artifact = "..."), and every `_`-bounded run of any of them -- a
# function ft_draw_big_box would give big_box, a helper name the exercise's own
# title supplies. tools/tests/ is the harness's, not a subject's, so it vouches
# for nothing. Neither does a clue (clues.tsv, diff_clues.txt ...) or a
# Markdown file: that is prose, which this class reads, and a name one leaked
# would otherwise be given by the leak itself. A clue that says "the program"
# by its subject name is still covered, by the artifact.
SPLIT='{
	l = $0
	while (match(l, /[A-Za-z0-9_.-]+/)) {
		w = substr(l, RSTART, RLENGTH); l = substr(l, RSTART + RLENGTH)
		sub(/\.+$/, "", w); print w
		n = split(w, id, /[^A-Za-z0-9_]+/)
		for (i = 1; i <= n; i++) {
			np = split(id[i], p, "_")
			for (a = 1; a <= np; a++) {
				s = p[a]; print s
				for (b = a + 1; b <= np; b++) { s = s "_" p[b]; print s }
			}
		}
	}
}'
# Both listings through zone_list, as every other here: neither status was
# read, and a git that failed there left the names a subject gives unknown,
# so the scan went on and called the tree clean.
zone_list "$TMP/tests" '*/tests/*' ':(exclude)tools/*'
while IFS= read -r t; do
	case "${t##*/}" in *clues*|*.md) continue ;; esac
	[ -f "$t" ] && awk "$SPLIT" < "$t" 2> /dev/null
done < "$TMP/tests" > "$TMP/given"
zone_list "$TMP/builds" '*BUILD.bazel' '*/BUILD' 'BUILD'
while IFS= read -r b; do
	{ contract_files "$b" files optional || : > "$TMP/unread"; } | awk '!/[\/*]/'
	awk '{ sub(/#.*/, "") }
		{
			while (match($0, /artifact[ \t]*=[ \t]*"[^"]*"/)) {
				m = substr($0, RSTART, RLENGTH); $0 = substr($0, RSTART + RLENGTH)
				sub(/^[^"]*"/, "", m); sub(/"$/, "", m); print m
			}
		}' < "$b"
	# Where a unit's `provided` puts the grader's files: each entry's
	# destination, the path the subject gives them ("srcs/ft_strcmp.c"), as
	# tools/units.awk reads them. It reads no string from a dict a BUILD file
	# names once and passes by name (Reloaded's PUTCHAR); its files are under
	# tests/, whose contents are given. A contract it cannot read was said
	# by the call above.
	contract_files "$b" provided 2> /dev/null || : > "$TMP/unread"
	# A library's file for each function its contract names, where one of
	# its file patterns takes it: Libft's "ft_*.c" with ft_strnstr among its
	# functions gives ft_strnstr.c, a name the subject fixes, not the answer.
	# Without this, a name the harness's prose rightly uses was a hit as soon
	# as the student's own ft_strnstr.c stopped being a stub.
	_pats=$(contract_files "$b" files optional 2> /dev/null | awk '/[*]/ && !/\//')
	# A pattern is matched as a glob of * and ? (awk, so the shell never
	# expands it against the files where the scan runs).
	[ -z "$_pats" ] || LC_ALL=C awk -f "$UNITS_AWK" "$b" 2> /dev/null |
		LC_ALL=C awk -F'\t' -v pats="$_pats" '
			BEGIN {
				n = split(pats, P, "\n")
				for (i = 1; i <= n; i++) {
					r = ""
					for (j = 1; j <= length(P[i]); j++) {
						c = substr(P[i], j, 1)
						if (c == "*") r = r ".*"
						else if (c == "?") r = r "."
						else if (c ~ /[A-Za-z0-9_-]/) r = r c
						else r = r "[" c "]"
					}
					R[i] = "^" r "$"
				}
			}
			$2 == "function" {
				for (i = 1; i <= n; i++)
					if (($1 ".c") ~ R[i]) { print $1 ".c"; break }
			}'

done < "$TMP/builds" | awk "$SPLIT" >> "$TMP/given"
if [ -e "$TMP/unread" ]; then
	echo "answer_scan.sh: a subject() contract could not be read (above), so the names the subjects give are unknown -- nothing was scanned" >&2
	exit 2
fi
printf '%s\n' "$COMMON_NAMES" | awk 'NF { print $1 }' >> "$TMP/given"
sort -u -o "$TMP/given" "$TMP/given"

# A Makefile line that is only paths the subject gives says nothing of the
# answer: every word of every path is given. A line naming only C 09 ex01's
# srcs/ft_strcmp.c -- the grader's file, which its subject contract names as a
# `provided` destination -- was a hit on a correct Makefile until this.
awk -F '\t' -v given="$TMP/given" -v pl="$TMP/pathlines" '
	BEGIN {
		while ((getline g < given) > 0) G[g] = 1
		while ((getline e < pl) > 0) {
			i = index(e, "\t"); k = substr(e, 1, i - 1)
			n = split(substr(e, i + 1), w, /[^A-Za-z0-9_.-]+/); ok = 1
			for (j = 1; j <= n; j++) {
				sub(/\.+$/, "", w[j])
				if (w[j] != "" && !(w[j] in G)) ok = 0
			}
			if (ok) drop[k] = 1
		}
	}
	!($1 in drop)' "$TMP/defs" > "$TMP/defs.kept" && mv "$TMP/defs.kept" "$TMP/defs"

# name <TAB> kind <TAB> where: the first definition of each name nobody gives.
# A single lowercase word is left out too. The harness's prose is made of such
# words, and a whole-word match of one against every doc reports the dictionary:
# on the answers of a second author, a few plain English words used as helper
# names were most of what this class found, and not one was a leak. Keeping them
# only where they read as code, straight before a `(` or inside backticks, was
# tried and measured on the same answers: every hit was still noise, because the
# harness's own code and docs call their own helpers the same plain words, in
# exactly that form. So this is an accepted miss, and the header says so. The
# Norm's s_ / t_ / e_ / u_ prefixes, capitals and file extensions keep every
# other kind out of it.
awk -F '\t' -v given="$TMP/given" '
	BEGIN { while ((getline g < given) > 0) G[g] = 1 }
	$2 ~ /^[a-z]+$/ { next }
	!($2 in G) && !($2 in done) { done[$2] = 1; print $2 "\t" $1 "\t" $3 }
' "$TMP/named" > "$TMP/names"
# A stubbed tree -- the public template, or a fresh clone of it -- has files in
# the zone but no answers in them: every generator is a skeleton and every body
# a stub. Reporting "none found" there would be a scan that searched nothing.
if [ ! -s "$TMP/shell" ] && [ ! -s "$TMP/c" ] && [ ! -s "$TMP/defs" ]; then
	echo "answer_scan.sh: the zone holds no answer to look for (a stubbed tree?)" >&2
	exit 2
fi

# ------------------------------------------------------------------ targets
# Through zone_list, which refuses a git that failed: a listing it never
# checked left the loop nothing to read, and that was called clean. And a
# scan that read no file at all searched nothing, so it says so (exit 2),
# never OK.
zone_list "$TMP/targets" . \
	':(exclude)*/deliverable/*' ':(exclude)*/generators/*' \
	':(exclude)TODO.md' ':(exclude)todo/' ':(exclude)HISTORY.md'

_nread=0
while IFS= read -r t; do
	[ -f "$t" ] || continue
	grep -Iq . -- "$t" 2> /dev/null || continue
	_nread=$((_nread + 1))
	# By redirection, as every read here: an operand shaped like an awk
	# assignment (a root file named `x=y.txt`) is taken for one, and awk then
	# reads its standard input -- this loop's list of files, which it would
	# scan as the file's text, ending the loop unseen.
	awk -v shell="$TMP/shell" -v cruns="$TMP/c" -v defs="$TMP/defs" -v names="$TMP/names" \
		-v file="$t" "$CKEEP
		BEGIN {
			while ((getline e < shell) > 0) { i = index(e, \"\t\"); ns++; SK[ns] = substr(e, 1, i - 1); SV[ns] = substr(e, i + 1) }
			while ((getline e < cruns) > 0) { i = index(e, \"\t\"); C[substr(e, 1, i - 1)] = substr(e, i + 1) }
			while ((getline e < defs) > 0) { i = index(e, \"\t\"); nd++; DK[nd] = substr(e, 1, i - 1); DV[nd] = substr(e, i + 1) }
			while ((getline e < names) > 0) { split(e, f, \"\t\"); NK[f[1]] = f[2]; NS[f[1]] = f[3] }
			KIND[\"tag\"] = \"a struct, union or enum tag\"; KIND[\"typedef\"] = \"a type name\"
			KIND[\"macro\"] = \"a macro\"; KIND[\"static\"] = \"a static function\"
			KIND[\"file\"] = \"a file name\"
		}
		$NORM"'
		# A name: every word, whole, and every identifier inside it -- so
		# deliverable/ex00/x.c yields x.c, and s_x/s_y yields both.
		{
			n = $0; split("", seen)
			while (match(n, /[A-Za-z0-9_.-]+/)) {
				wd = substr(n, RSTART, RLENGTH); n = substr(n, RSTART + RLENGTH)
				sub(/\.+$/, "", wd)
				np = split(wd, part, /[^A-Za-z0-9_]+/); part[np + 1] = wd
				for (j = 1; j <= np + 1; j++) {
					q = part[j]
					if (!(q in NK) || (q in seen)) continue
					seen[q] = 1
					printf "%s:%d: %s -- %s from %s, which no test and no stub names\n", file, NR, q, KIND[NK[q]], NS[q]
				}
			}
		}
		{
			for (j = 1; j <= ns; j++)
				if (index(l, SK[j])) { printf "%s:%d: an answer line from %s\n", file, NR, SV[j]; break }
			if (match($0, /ssh-ed25519[ \t]+AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+\/]+/) && RLENGTH >= 80)
				printf "%s:%d: a complete ed25519 public key, which passes the exercise whose turn-in is one\n", file, NR
			d = $0; gsub(/[ \t]/, "", d)
			for (j = 1; j <= nd; j++)
				if (index(d, DK[j])) { printf "%s:%d: an answer line from %s\n", file, NR, DV[j]; break }
			r = $0; gsub(/[ \t]+/, " ", r); sub(/^ /, "", r); sub(/ $/, "", r)
			if (ckeep(r)) {
				k++; w[k] = r; at[k] = NR
				if (k >= 4) {
					key = w[k - 3] " | " w[k - 2] " | " w[k - 1] " | " w[k]
					if (key in C) printf "%s:%d: four lines of %s\n", file, at[k - 3], C[key]
				}
			}
		}' < "$t"
done < "$TMP/targets" > "$TMP/hits"
if [ "$_nread" -eq 0 ]; then
	echo "answer_scan.sh: no file outside the zone was read, so nothing was searched." >&2
	exit 2
fi

if [ -s "$TMP/hits" ]; then
	cat "$TMP/hits"
	echo
	echo "answer_scan: FAIL — $(wc -l < "$TMP/hits" | sed 's/ //g') place(s) outside deliverable/ and generators/ carry an answer, or a name only the answers use."
	echo "             AGENTS.md §0: a check derives its reference by construction or from //oracle,"
	echo "             and prose describes an answer's shape, never what its author named things."
	exit 1
fi
echo "answer_scan: OK — $(wc -l < "$TMP/shell" | sed 's/ //g') shell answer lines, $(wc -l < "$TMP/c" | sed 's/ //g') C runs, $(wc -l < "$TMP/defs" | sed 's/ //g') header/Makefile lines and $(wc -l < "$TMP/names" | sed 's/ //g') names looked for; none outside the zone."
exit 0
