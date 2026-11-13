#!/bin/sh
# stub_check.sh — prove that no deliverable in this tree holds an answer.
#
# Run it before publishing or sharing a copy of this workspace, over every
# deliverable in the repo:
#
#     sh tools/stub_check.sh
#
# Over one module, while working:
#
#     sh tools/stub_check.sh c-piscine/c-piscine-c-02
#
# And to list the headers approved below, by path:
#
#     sh tools/stub_check.sh --approved
#
# And to ask about ONE function of a library, whose files hold many (a
# project whose contract lists its functions, as a library's does):
#
#     sh tools/stub_check.sh --defines NAME FILE...
#
# which exits 0 when NAME is defined in FILE... and its body is a stub, 1 when
# its body holds more than a stub may (the lines are printed), 3 when no FILE
# defines NAME at all, and 2 when a FILE could not be read: no verdict. The
# body is judged by the same whitelist as a whole .c file (judge_c, below),
# and nothing outside that body is: tools/first_red.sh asks it, so a library
# with one function written is not "written" for every other function in it.
#
# And to ask about ONE rule of a Makefile, for a project in parts where a
# part is built by a rule of its own (`make bonus`) from the files another
# part shares:
#
#     sh tools/stub_check.sh --goal RULE MAKEFILE
#
# which exits 1 when the Makefile is no stub and RULE does something -- it has
# a prerequisite, as make would expand it, or a recipe line that does more
# than one echo -- printing the lines that make it so; 0 when the Makefile is
# a stub (no recipe line in it does more than echo), or RULE does nothing yet
# (no prerequisite, and recipes that only echo); 3 when the Makefile is no
# stub and has no rule RULE; and 2 when the Makefile could not be read, or
# RULE is no rule's name: no verdict. RULE `-` is the default goal: the rule
# a bare `make` runs (goal_rule, below). It reads the text and never runs
# make: tools/first_red.sh asks it on the student's own machine, and make
# runs the $(shell ...) of a Makefile it reads. So it knows a variable's
# value only where that is certain -- set outside every conditional, and
# after every include or eval that could have set it too -- and where the
# answer leans on anything else, it prints the lines it could not tell from
# and exits 1: such a rule counts as written. So does a RULE with no recipe
# of its own (or a :: rule of it with none) that another rule of the
# Makefile may make (a pattern rule, a suffix rule, .DEFAULT), when that
# rule does something. So does every RULE once the Makefile may set
# .EXTRA_PREREQS, whose words make adds to the prerequisites of each rule it
# is set for. What it cannot see: a rule that only an included makefile holds,
# or that an eval writes from a value only such a file sets, or an override
# or a .EXTRA_PREREQS one sets; make's built-in rules, so a Makefile that
# leans on them alone has no recipe and reads as a stub; variables from the
# environment or the command line, which read as unset; a ; in the name of the
# folder make runs in, which $(CURDIR), $(abspath) and $(realpath) may put in
# a rule's list, where it starts a recipe. Nor does it see a target named by
# something it cannot expand, a pattern rule's too: while that target may be
# RULE, it cannot tell, and says so. And what make runs beside a rule is no
# part of RULE: the value of an exported variable, which make expands for
# every recipe line, SHELL, and a $(shell) make runs as it reads the file.
#
# `--file PATH...` judges those files alone, and approves a header only at
# its place in the workspace -- this script's own checkout, or
# BUILD_WORKSPACE_DIRECTORY when set -- so a caller checking another tree (a
# checkout nested in this one, say) names that tree there, as
# tools/answer_scan.sh does, or runs that tree's own tools/stub_check.sh,
# or `42 stubcheck`, from inside it: the checkout is found from this
# script's place, never from the folder it is run in.
#
# Exit 0 = every deliverable is a stub, and nothing was left unread. Exit 1 =
# at least one still has a body, and each offending line is printed with its
# file and line number (a file it refused or never read is named beside them).
# Exit 2 = no verdict: a file it could not read, an index git could not list,
# a workspace it could not enter, or a zone holding no file of a kind it
# reads; or a file that holds no answer and is no stub either -- an empty one,
# or a .c or .h without its 42 header (NEITHER A STUB NOR AN ANSWER, below);
# or, in repo mode, a tracked file nothing here reads -- a kind it does not
# know in the zone, a generators/ file that is no exNN.sh, a file in a third
# place (each named, below). No body found and something left unread is
# never 1: the template build reads 1 as "found an answer: stub it".
#
# NOTE TO WHOEVER EDITS THIS FILE: it SHIPS on the template, so it is bound by
# the same rule it enforces. Describe the shape of an answer; never paste one.
# Both blocks below used to quote real solutions verbatim — three c-01 bodies
# and three finished c-08 headers — which put four paste-ready answers into the
# one file whose entire job is keeping them out. Name the exercise and say what
# shape the mistake had; the reader can look at their own subject.
#
# WHY NOT A HEURISTIC
# -------------------
# The obvious check — "does this file LOOK like a stub" — does not work, and the
# failure is silent in the dangerous direction. A first attempt at one passed
# three real c-01 answers as stubs (ex00, ex01 and ex03): each is a one- or
# two-line assignment through a pointer parameter, so "short and simple" and
# "not implemented" are indistinguishable by shape. Any pattern loose enough to
# tolerate a signature wrapped across two lines is loose enough to swallow a
# single assignment statement.
#
# So this does the opposite: per file kind, it accepts an explicit WHITELIST of
# what a stub may contain, and calls everything else an answer. "Does something"
# and "does nothing" is exactly the distinction being drawn, so there is no
# shape a real implementation can take that this passes.
#
# WHY IT CHECKS FIVE KINDS AND NOT JUST .c
# ----------------------------------------
# It used to check `*/deliverable/*.c` and nothing else, and that is a false
# green of exactly the kind this repo treats as its worst defect class: it
# printed "OK — all 123 deliverable(s) are stubs" over a tree that still
# contained four finished c-08 answers, because c-08's deliverable IS a header
# and a header is not a .c. Measured, not imagined — c-08 ex00 through ex03 each
# turn in a header, all four were complete, and all four shipped in the
# published template with the checker reporting success.
#
# The same blind spot covered rush-00's rush.h (which carried a whole data
# model: one team's structs and macros), c-09's Makefile and
# libft_creator.sh, c-10's four Makefiles, and all 18 shell generators — every
# one of them a deliverable whose answer is not C. So the rule is now: the set
# of files checked is derived from what a module TURNS IN, not from a file
# extension that happened to be convenient.
#
#   *.c        brace depth; inside a body only (void) casts and a trivial return
#   *.h        include guards and nothing else, unless allowlisted below
#   Makefile   recipes may only echo; a real build command is an answer
#   *.sh       no command at all beyond the no-op `:`
#   *.md       blank lines and <!-- --> comments; a line of prose is the
#              student's own (a README the subject has them turn in)
#
# HEADERS THAT ARE NOT ANSWERS
# ----------------------------
# A few deliverable headers legitimately carry content. Each is approved by
# its content AND its place: a line of APPROVED_HEADERS (below) gives the hash
# of the file and a glob of the paths it may sit at, and a copy is approved
# only where both match the same line. Why the path is needed as well is
# written once, beside the list. Why the hash is: an allowlist of paths alone
# would wave a header through whether or not anyone had actually reduced it,
# which is the same blanket exemption this whole script exists to refuse. A
# hash cannot be satisfied by forgetting.
#
# So a copy of ft_list.h in a module no glob covers needs a line of its own,
# or a wider glob, with the sentence saying why it is not an answer there;
# until then it is held to the guards-only rule (*.h, above) like any other
# header. An EDITED copy fails its hash and is held to that rule wherever it
# lives. The hash covers the file BELOW its 42 header, so re-stamping the
# identity does not disturb it.
#
#   ft_list.h (c-12, x18), ft_btree.h (c-13, x8)
#       42 PROVIDES these in the subject. Stubbing one would delete a definition
#       the student was GIVEN, not one they owe.
#
#   libft.h (cursus/Milestone_0/Libft)
#       Its guards and the t_list typedef Libft prints on p.14 ("add the
#       following structure declaration to your libft.h file"), and nothing
#       else: no prototype, no include. The prototypes are the student's to
#       write, so a copy holding any one of them fails its hash.
#
# NOT APPROVED ANY MORE: rush-00's rush.h. It shipped reduced to ft_putchar's
# prototype and a note on static helpers, but the subject's turn-in is three
# named files and no header, so the template ships none: the note lives in
# c-piscine/c-piscine-rush-00/README.md, where the symbols layer's rule is
# explained. A rush.h copied
# from an older template now fails here, which is the point -- `git rm` it and
# drop the include from the rush0N.c stubs.
#
# NOT APPROVED ANY MORE: includes/ft.h (c-09 ex01). It was, with its cost
# written down: its five prototypes are c-08 ex00's whole deliverable, so every
# template handed that exercise over. The reason was the harness -- c_libft
# built tests/ex01/test_libft.c as a cc_binary against this header, so a
# guards-only ft.h made every call an implicit declaration, and under -Werror
# //c-piscine/c-piscine-c-09:ex01_output was a BUILD ERROR that took `bazel test
# //...` down on a fresh clone. c_libft then compiled that program at test time
# inside tools/header_check.sh (--shape sources), so the same stub became one red
# test, and ft.h was held to the guards-only rule like every other header. It
# is not a deliverable at all now: the subject's turn-in is the Makefile alone,
# and the grader's ft.h -- guards only, like Piscine Reloaded ex24's -- lives
# in tests/ex01/grader/, outside the zone. An approval is never the fix for a
# harness that cannot face a stub: fix the harness.
#
# To approve a new one, print its hash with:
#     sh tools/stub_check.sh --hash PATH
# and add a line here: the hash, the glob of the paths it may sit at, and the
# sentence saying why it is not an answer there.
# WHY EACH ENTRY CARRIES A PATH AS WELL AS A HASH. The first version keyed on
# content alone, and that was wrong in the one way that matters: c-09's
# includes/ft.h, approved at the time, and c-08 ex00's ft.h held the SAME FIVE
# PROTOTYPES, byte for byte. Approving c-09's therefore approved c-08 ex00's too
# -- and c-08 ex00 is an exercise whose whole deliverable is that header, so the
# answer shipped and //c-piscine/c-piscine-c-08:ex00_output went GREEN on it.
# Identical bytes, opposite meanings, decided entirely by where the file sits.
#
# So both must match. The hash still stops "nobody reduced this file"; the path
# stops "these bytes are fine somewhere else". Format: <md5> <path-glob> <why>.
APPROVED_HEADERS='
0a8e57bbaf8ff567369c17f0c09bb93c c-piscine/c-piscine-c-12/deliverable/*/ft_list.h provided-by-42
911f5c687454688a48b3b70ac42a9543 c-piscine/c-piscine-c-13/deliverable/*/ft_btree.h provided-by-42
83e1989b53e106f1f281343ce863faa4 cursus/Milestone_0/Libft/deliverable/libft.h printed-by-subject-p14
'

set -u

# It reads no standard input, and the shell is told so. Two callers run it
# inside a `while read` loop whose stdin is their own list of files
# (tools/first_red.sh, tools/answer_scan.sh), and a stub_check that read stdin
# would take the rest of that list for the content of the file it was
# scoring. It did, by way of a refusal that did not stop the run (below): awk
# was handed an empty file name, and awk reads stdin then. A whole-tree run
# from a terminal hung there, and one with text piped in scored that text --
# `echo 'int main(void){return 1;}' | sh tools/stub_check.sh` reported an
# implementation in a file that held none.
exec < /dev/null

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "stub_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk basename cat cut dirname git grep md5sum mktemp rm tr

WS="${BUILD_WORKSPACE_DIRECTORY:-$(CDPATH='' cd "$(dirname "$0")/.." && pwd)}"

# _SC_NO_CR, an awk fragment spliced FIRST into every judge that reads a
# file's lines: body_hash, judge_c, judge_h, judge_mk, goal_rule, judge_sh
# and judge_md. Its rule takes a trailing \r off each line before any rule
# of the judge's own sees it (awk runs a line's rules in order), and
# no_cr(s) does the same for a line read with `getline VAR`, which no rule
# sees: goal_rule's continued lines. A line an editor set to CRLF saves ends
# in \r, and every stub pattern that anchors on a line's end (`;$`,
# `^:[ \t]*$`, `^true[ \t]*$`) missed it, so a stub was reported as an
# answer. judge_c and judge_h were given a strip each; judge_sh and judge_mk,
# given none, went on reporting a CRLF `:` or `true` line as one. One text,
# spliced, so a judge cannot be the one forgotten.
#
# Not spliced into has_header, whose question is whether a border ends in
# \r, nor into is_blank, which counts a \r as a blank wherever it is.
_SC_NO_CR='
		function no_cr(s) { sub(/\r$/, "", s); return s }
		{ $0 = no_cr($0) }'

# whole_comment(s), an awk function spliced into body_hash and judge_h: whether
# s is a comment AND NOTHING ELSE. /^\/\*.*\*\/$/ was not that test. `.*` is
# greedy, so it also matched
#     /* */ int g_answer = 42; /* */
# whose middle is code, and dropped it. Reproduced before this was written:
# that line and no line at all produced the SAME body hash, so one approved
# entry approved the smuggled copy of the same header too. judge_h had a test
# of its own, a line that BEGINS with /*, so `/* x */ int f(void);` above the
# guards passed as part of the 42 header. One text for both, so a fix to it
# reaches both.
#
# Find the FIRST `*/` and require it to end the line. Then a second comment
# further along cannot vouch for whatever sits between them.
_SC_WHOLE_COMMENT='
		function whole_comment(s,   i) {
			if (s !~ /^\/\*/) return 0
			i = index(s, "*/")
			return (i > 0 && substr(s, i + 2) ~ /^[ \t]*$/)
		}'

# The identity of a header, ignoring its 42 header block. Leading lines that are
# a whole C comment on one line (`/* ... */`, which is every line of the 11-line
# 42 block) are dropped until the first line of real content; from there on
# everything counts, so a comment placed further down cannot smuggle text past
# the hash. That is what lets one recorded hash approve all 18 copies of
# ft_list.h across two branches with four different names stamped in them.
#
# EVERY FILE HERE IS READ BY REDIRECTION, never handed to awk as an operand.
# awk takes an operand shaped like an assignment -- `ft_a=b.c`, a bare
# relative name -- for one, sets a variable and reads its standard input
# instead, which is /dev/null here: `--file ft_a=b.c` on an answer said "OK --
# all 1 deliverable(s) are stubs", and `--hash ft_a=b.c` printed the empty
# file's hash. A redirection the shell cannot open fails the command, and the
# caller refuses.
#
# A leading line is dropped only if it is a comment and nothing else
# (whole_comment, above). Each line is hashed without a trailing \r
# (_SC_NO_CR), so a copy saved with CRLF line ends keeps the hash its
# approval names.
body_hash() {
	{ awk "$_SC_NO_CR$_SC_WHOLE_COMMENT"'
		started { print; next }
		!whole_comment($0) && NF { started = 1; print }
	' | md5sum | cut -c1-32; } < "$1"
}

# ONE NAME PER LINE. Every list of paths here is a file read with `while IFS=
# read -r`, one name per line, and none is ever expanded bare. The lists were
# strings walked with `for f in $c_files`, which splits a name at its blanks: a
# staged answer named `ft_x copy.c` -- the name a file manager gives a duplicate
# -- was scored as `ft_x` and `copy.c`, two files that do not exist, and the
# answer itself was never opened. "OK -- all 3 deliverable(s) are stubs", exit
# 0, on a tree whose one answer would have shipped (found rehearsing a template
# publish, 2026-10-03; --file mode did the same, as `awk: cannot open` followed
# by OK). The index is listed with `git ls-files -z`, so git quotes no name
# either; a name that holds a newline splits into lines no index entry has, and
# each of those is refused below, which fails the run.
#
# WHERE THE CONTENT COMES FROM, which is not the same question as where the
# file LIST comes from -- and getting them from two different places is what
# made the second of a publish's two runs a no-op.
#
# Repo mode lists files with `git ls-files`, i.e. from the INDEX, and then every
# checker below used to read that path off DISK. A template publish ran this
# twice: once after stubbing, then again, over the staged tree. Both runs
# read the same working-tree files, so the second one proved nothing the
# first had not. An answer sitting in the index behind a stubbed file on
# disk -- exactly what a forgotten or partial `git add -A` leaves, and
# `git commit` publishes the INDEX -- was reported as a stub.
#
# Reproduced in a scratch repo before this was written: index holding a
# function with a real body, disk holding the (void)/return(0) stub, verdict
# "stub_check: OK — all 1 deliverable(s) are stubs.", exit 0, twice.
#
# So repo mode reads each blob out of the index. --file mode still reads the
# path it was handed: it takes fixtures in a temp dir with no git at all, which
# is what lets the selftest drive this hermetically.
CONTENT_TMP=""

# refuse PATH WHY -- end the run with exit 2. A file this could not read is one
# nothing here verified, so no verdict can follow it. The refusal used to be
# made inside the function that read the blob, which ran in $(...): its
# `exit 2` left only the command substitution, the loop scored an empty file
# name, and the run went on to print OK under its own "Refusing to score it".
# It is made here, in the shell the run is, and it ends the run.
refuse() {
	echo "stub_check: '$1' $2." >&2
	echo "            Refusing to score it, and so the whole run: a file this could" >&2
	echo "            not read is one nothing here has verified." >&2
	exit 2
}

MODE=repo
scope="${1:-}"
case "$scope" in
	--hash)
		[ -n "${2:-}" ] || { echo "stub_check: --hash needs a file" >&2; exit 2; }
		[ -f "$2" ] || { echo "stub_check: no such file: $2" >&2; exit 2; }
		[ -r "$2" ] || { echo "stub_check: cannot read: $2" >&2; exit 2; }
		_bh=$(body_hash "$2") || { echo "stub_check: cannot read: $2" >&2; exit 2; }
		printf '%s %s\n' "$_bh" "$(basename "$2")"
		exit 0 ;;
	--file) MODE="file"; shift ;;
	# One function's body, in the files given (see the usage above): judged
	# below, once judge_c is defined.
	--defines)
		case "${2:-}" in
			"" | [0-9]* | *[!A-Za-z0-9_]*)
				echo "stub_check: --defines needs a function name, then files" >&2
				exit 2 ;;
		esac
		MODE=defines
		DEF_NAME=$2
		shift 2 ;;
	# One rule of a Makefile (see the usage above): judged below, once
	# judge_mk is defined.
	--goal)
		case "${2:-}" in
			- | [A-Za-z0-9_]*) ;;
			*)
				echo "stub_check: --goal needs a rule's name, or - for the default goal, then a Makefile" >&2
				exit 2 ;;
		esac
		case "$2" in
			-) ;;
			*[!A-Za-z0-9_.-]*)
				echo "stub_check: --goal needs a rule's name, or - for the default goal, then a Makefile" >&2
				exit 2 ;;
		esac
		MODE=goal
		GOAL_NAME=$2
		shift 2 ;;
	# The path of every approved header, one per line. tools/answer_scan.sh
	# asks, because an approved header is one the template ships whatever the
	# copy in front of it holds, so its file name belongs to everyone.
	--approved)
		printf '%s\n' "$APPROVED_HEADERS" | awk 'NF { print $2 }'
		exit 0 ;;
	-*) echo "stub_check: unknown option: $scope" >&2; exit 2 ;;
esac

# Three counts, because they are three findings. `bad` is a deliverable this
# checker read and found holding code; `unread` is a file it never opened -- a
# kind it cannot classify, or one sitting in no place a check reads; `refused`
# is one score() read and found to be neither a stub nor an answer (below).
# The summary used to fold the second into the first, and over Rush 02's two
# copies of 42's dictionary it printed "2 of 2 deliverable(s) still contain an
# implementation" where nothing had held code at all: a maintainer reads that
# line as answers about to ship, and goes looking in the wrong files.
bad=0
unread=0
refused=0
untold=0
checked=0
report() { bad=$((bad + 1)); echo "  $1"; echo "$2"; }
report_unread() { unread=$((unread + 1)); echo "  $1"; echo "$2"; }
report_refused() { refused=$((refused + 1)); echo "  $1"; echo "$2"; }

# ---------------------------------------------------------------- C sources
#
# A body line is one that sits at depth >= 1 BEFORE this line opens or closes
# anything. That is what makes a wrapped signature safe: its continuation is
# still at depth 0. Outside function bodies everything is allowed — #include,
# prototypes, and the subject-provided type definitions that must survive.
#
# Each judge_KIND PATH SRC prints one line per thing SRC (PATH's content) holds
# that a stub may not, and nothing for a stub; it fails when SRC cannot be read.
#
# judge_c PATH SRC NAME judges the body of the function NAME and nothing else
# (--defines), and exits 3 when SRC defines no function NAME. A definition is
# a body opened at depth 0, and its name is the word just before the first
# `(` of the text at depth 0 since the last `;`, `}` or preprocessor line: a
# signature wrapped over several lines, or with its return type on a line of
# its own, is still one name.
judge_c() {
	awk -v want="${3:-}" "$_SC_NO_CR"'
		# The function a declaration at depth 0 names, or "".
		function fname(d,   i, pre) {
			while ((i = index(d, ";")) > 0) d = substr(d, i + 1)
			i = index(d, "(")
			if (!i) return ""
			pre = substr(d, 1, i - 1)
			sub(/[ \t]+$/, "", pre)
			return match(pre, /[A-Za-z_][A-Za-z_0-9]*$/) ? substr(pre, RSTART, RLENGTH) : ""
		}

		# Is this run of text, at the depth reached so far, something other than
		# an empty stub body? Depth and the reported line are passed in because
		# a POSIX awk function sees globals anyway and naming them here says
		# which ones it reads.
		function judge(seg, lineno, raw,   t) {
			if (depth < 1 && !pp) decl = decl " " seg
			if (want != "" && curfn != want) return
			t = seg
			gsub(/^[ \t]+|[ \t]+$/, "", t)
			if (depth < 1 || t == "")
				return
			if (t ~ /^\(void\)[A-Za-z_][A-Za-z_0-9]*;$/ ||
			    t ~ /^return[ \t]*\([ \t]*(0|NULL)[ \t]*\);$/ ||
			    t ~ /^return[ \t]*;$/)
				return
			if (lineno != last_reported) {
				printf "    %d: %s\n", lineno, raw
				last_reported = lineno
			}
		}

		# Strip comments and string literals before counting braces, so a brace
		# inside either cannot move the depth. Norm forbids comments inside a
		# function body, but a deliverable may carry a block comment at depth 0.
		{
			line = $0
			gsub(/"[^"]*"/, "\"\"", line)
			gsub(/'"'"'[^'"'"']*'"'"'/, "'"''"'", line)
		}
		#
		# A comment is matched as C reads one: anything up to the first `*/`,
		# stars included. The strip once took only comments with no `*` in
		# them, so "/* (n * size) */" or the lines of stars of the 42 header stayed
		# in the line, and their words were read as the declaration of the
		# function after them (--defines named it "size"). Whole comments go
		# first; what then still opens one runs on to the next lines.
		#
		# A `//` comment is cut after the whole block comments are gone and
		# before an unclosed one is looked for, never before: cut first, the
		# `//` of a URL in "/* see https://... */" took the closing `*/` with
		# it, the comment ran on to the end of the file, and a written body
		# under it passed as a stub (--defines: no such function).
		incomment && line ~ /\*\// { sub(/^([^*]|\*+[^*\/])*\*+\//, "", line); incomment = 0 }
		incomment { next }
		{ gsub(/\/\*([^*]|\*+[^*\/])*\*+\//, "", line); sub(/\/\/.*$/, "", line) }
		line ~ /\/\*/ { sub(/\/\*.*$/, "", line); incomment = 1 }
		# A preprocessor line at depth 0 names no function, and ends whatever
		# text came before it.
		{ pp = (depth == 0 && line ~ /^[ \t]*#/); if (pp) decl = "" }

		# Judge each line AT THE DEPTH ITS OWN BRACES CREATE, by walking it
		# brace by brace, rather than at the depth it had on arrival.
		#
		# Counting the braces afterwards means a line is always scored before
		# its own `{` takes effect, so everything sharing a line with an opening
		# brace sits at depth 0 and is never examined. Reproduced:
		#
		#     int	ft_double(int n) { return (n * 2); }
		#
		# a whole working function on one line, verdict "OK -- all 1
		# deliverable(s) are stubs". So did `{	int i = compute();`.
		#
		# Segments never contain a brace, which is why the two brace-only forms
		# the old test allowed are gone: `{`, `}` and `{}` now produce empty
		# segments and are skipped as empty.
		{
			rest = line
			while (1) {
				p = match(rest, /[{}]/)
				if (p == 0) { judge(rest, NR, $0); break }
				judge(substr(rest, 1, p - 1), NR, $0)
				if (substr(rest, p, 1) == "{") {
					if (depth == 0) {
						curfn = fname(decl)
						if (want != "" && curfn == want) found = 1
					}
					depth++
				} else if (--depth <= 0) {
					depth = 0
					curfn = ""
					decl = ""
				}
				rest = substr(rest, p + 1)
			}
		}
		END { if (want != "" && !found) exit 3 }
	' < "$2"
}

# repo_path PATH -- the path an approval's glob is matched against: the
# file's place in the workspace, however the caller spelled it. Only a
# leading ./ was ever taken off, so `.//`, `/./` and `//` in a path, an
# absolute one and one relative to a module folder each made an approved
# header "an implementation" -- and `42 stubcheck --file` (tools/fortytwo)
# hands over an absolute path every time (V151, V232). So the folder the
# file sits in is resolved (pwd -P, links and all), and so is the
# workspace; a file under the workspace is named by the rest. A file
# outside it -- a fixture tree, or answer_scan's copy of the index when its
# scratch folder is not in the checkout -- has no place there, and keeps
# the path as given, relative to the folder this runs in, with runs of /
# squeezed, /./ dropped and a leading ./ taken off. No `..` is taken out
# of that text: a path outside the workspace that still holds a `..`
# segment names no place at all, and is given nothing (exit 1), because an
# approval glob's `*` would match `..` segments too and approve the same
# bytes somewhere else. No path is matched by its end either, so the same
# bytes anywhere else stay unapproved.
repo_path() {
	_rd=$(CDPATH='' cd -P -- "$(dirname -- "$1")" 2> /dev/null && pwd -P) &&
		_rw=$(CDPATH='' cd -P -- "$WS" 2> /dev/null && pwd -P) &&
		case "$_rd/" in
			"$_rw"/*)
				_rr=${_rd#"$_rw"}
				_rr=${_rr#/}
				printf '%s%s\n' "${_rr:+$_rr/}" "$(basename -- "$1")"
				return 0 ;;
		esac
	RP=$1 awk 'BEGIN {
		p = ENVIRON["RP"]
		gsub(/\/\/+/, "/", p)
		while (sub(/\/\.\//, "/", p)) ;
		while (sub(/^\.\//, "", p)) ;
		if (p ~ /(^|\/)\.\.(\/|$)/) exit 1
		print p
	}'
}

# ---------------------------------------------------------------- C headers
#
# Everything below the 42 header comment must be an include guard. Comments are
# allowed only inside that leading block, each line of it a comment and nothing
# else (whole_comment): a comment further down can describe a whole struct
# layout, so "it is only a comment" is not a reason to let text through here,
# and code sharing a line with a comment is code.
judge_h() {
	_h=$(body_hash "$2") || return 2
	# The path is worked out only for a header whose hash an entry holds.
	_hp=
	case "$APPROVED_HEADERS" in *"$_h "*) _hp=$(repo_path "$1") ;; esac
	_ok=0
	# Both the hash and the path must match the SAME entry.
	echo "$APPROVED_HEADERS" | while read -r _eh _ep _; do
		[ -n "$_eh" ] || continue
		[ -n "$_hp" ] || continue
		[ "$_eh" = "$_h" ] || continue
		# shellcheck disable=SC2254
		case "$_hp" in $_ep) exit 9 ;; esac
	done || _ok=1
	[ "$_ok" -eq 0 ] || return 0
	awk "$_SC_NO_CR$_SC_WHOLE_COMMENT"'
		{ line = $0; gsub(/^[ \t]+|[ \t]+$/, "", line) }
		line == "" { next }
		# The leading 42 header block, and nothing after it: a line there
		# is skipped only when it is a comment and nothing else.
		!seen_code && whole_comment(line) { next }
		line ~ /^#[ \t]*ifndef[ \t]+[A-Za-z_][A-Za-z_0-9]*$/ { seen_code = 1; next }
		line ~ /^#[ \t]*define[ \t]+[A-Za-z_][A-Za-z_0-9]*$/ { seen_code = 1; next }
		line ~ /^#[ \t]*endif/                               { seen_code = 1; next }
		{ seen_code = 1; printf "    %d: %s\n", NR, $0 }
	' < "$2"
}

# --------------------------------------------------------------- Makefiles
#
# A recipe line starts with a TAB. In a stub it may only announce what it would
# do; the moment it invokes a compiler or an archiver it is the answer, because
# for c-09 ex01, c-10 and rush-02 the Makefile IS the exercise. This is the
# first reading, of TAB lines alone, and the one that prints them: a line
# that starts with echo passes it whatever follows the echo. score() and
# --goal give goal_rule's reading of every recipe the last word, so a
# compiler after an echo's `;` or `&&`, or on a rule's own line, is an answer.
judge_mk() {
	awk "$_SC_NO_CR"'
		/^\t/ {
			r = $0
			sub(/^\t[ \t]*/, "", r)
			sub(/^[-@+]+/, "", r)
			if (r !~ /^echo[ \t]/ && r !~ /^true[ \t]*$/ && r !~ /^:[ \t]*$/)
				printf "    %d: %s\n", NR, $0
		}
	' < "$2"
}

# goal_rule SRC GOAL [any] -- what SRC's rules for GOAL do, read from the
# text as GNU make reads it. Exit 0 and the lines that do something, each as
# "    N: line": a rule line whose prerequisites expand to something, or a
# recipe line that does more than one echo (busy, below). 4 when SRC has a
# rule for GOAL and none of its lines does anything; 3 when it has no rule
# for GOAL. 5 when the answer depends on what this reader cannot know, with
# the lines that made it so: --goal counts that as written. GOAL `-` is the
# default goal, the rule a bare make runs: .DEFAULT_GOAL as it expands once
# the whole file is read. Unless the Makefile set it, make sets it to the
# first target, in file order, that neither starts with a `.` (unless it
# holds a /) nor is a suffix rule's name by the suffixes .SUFFIXES named so
# far; a rule with a `%` target gives none. Where a name may be a suffix
# rule's, this reader cannot tell, and says so. With `any` it prints nothing,
# and exits 1 when some recipe line in SRC, whatever its rule, does
# something, 5 when none does but one may (this reader cannot tell), else 0.
#
# A variable's value is known only where it is certain: set outside every
# conditional (the reader evaluates none, and reads both branches' rules), and
# after the last include or eval line that could have set it as well. Any
# expansion that touches something else -- a value a conditional, an include,
# an eval or a shell may have set, a function, what is worked out from an
# automatic variable -- is uncertain, and an uncertain line counts as doing
# something: a part is never read as not written because this reader could not
# tell. As make does, it reads a variable set with = where it is used, a
# rule's targets and prerequisites as it reads their line, and a recipe once
# the whole file is read; a line that starts with a TAB is a recipe only under
# a rule. make gives an automatic variable ($@, $<, $* and the rest, and their
# D and F forms) a value only as it runs the rule, so in a recipe this reader
# reads one as a word an echo may print, and a substitution of one, or a name
# built from one, through a variable that holds it too, as uncertain. It
# reads a variable make itself defines (CC, CFLAGS) the same way in the words
# of an echo, where the file never sets it and has no include or eval. A `;`
# that a rule's targets or prerequisites expand to starts its recipe, so where
# a value may hold one -- in its text, in a file the Makefile includes, in
# what a shell prints -- a rule whose list this reader cannot expand may have
# a recipe it cannot see. A goal with no recipe of its own, or with a :: rule
# that has none, may be made by another rule of the Makefile (a pattern rule,
# a suffix rule, .DEFAULT: the implicit search, below), and one that may and
# does something makes the answer 5 too. So does any goal once the Makefile
# may set .EXTRA_PREREQS, whose words make adds to the prerequisites of each
# rule it is set for, every rule when it is set as any variable is: this
# reader does not follow which. make expands a conditional, and an include,
# export, unexport or vpath line, as it reads it, so an eval there runs then;
# and call runs any function by the name it is given, eval and call among
# them. A != sets a value make expands again where it is used, so once the
# file has one, a value this reader cannot know may hold an eval the text
# never shows.
#
# What it cannot see, said here so nobody reads it as make: a rule that only
# an included makefile holds, or that an eval writes from a value only that
# file sets (an override or a .EXTRA_PREREQS set there too); make's built-in
# rules, so a Makefile that leans on them alone has no recipe and reads as a
# stub; variables from the environment or the command line, which read as
# unset (make's own, CC or MAKEFLAGS, as uncertain, but in the words of a
# recipe line that is an echo, where one the file never sets is a word the
# echo prints, as an automatic variable is); a ; in the name of the
# folder make runs in, which $(CURDIR), $(abspath) and $(realpath) may put in
# a rule's list, where it starts a recipe. A target named by something it
# cannot expand is not seen either, nor is a pattern so named: one reference
# may give several words, any of them a pattern. While one may be GOAL, the
# answer is 5, as it is when make may read a line otherwise than this reader
# (.RECIPEPREFIX, a directive on a line that may be a recipe). What make runs
# beside a rule is no part of the rule, and is not read as one: the value of
# an exported variable, which make expands for every recipe line it runs;
# SHELL, which runs each one; a $(shell) in an assignment, run as make reads
# the file. student_build.sh and make_test.sh ask make's own database instead,
# where make runs anyway.
goal_rule() {
	awk -v goal="$2" -v any="${3:-}" "$_SC_NO_CR"'
		function trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }
		function odd_bs(x,   n) {
			n = 0
			while (n < length(x) && substr(x, length(x) - n, 1) == "\\") n++
			return n % 2
		}
		BEGIN {
			# The variables make sets itself: uncertain until the Makefile
			# sets them.
			n = split("AR ARFLAGS AS CC CHECKOUT,v CO COFLAGS COMPILE.C COMPILE.F " \
			    "COMPILE.S COMPILE.c COMPILE.cc COMPILE.cpp COMPILE.def COMPILE.f " \
			    "COMPILE.m COMPILE.mod COMPILE.p COMPILE.r COMPILE.s CPP CTANGLE " \
			    "CWEAVE CXX F77 F77FLAGS FC GET LD LEX LEX.l LEX.m LINK.C LINK.F " \
			    "LINK.S LINK.c LINK.cc LINK.cpp LINK.f LINK.m LINK.o LINK.p LINK.r " \
			    "LINK.s LINT LINT.c M2C MAKEINFO MAKEFILES MAKE_COMMAND MAKE_HOST " \
			    "MAKE_VERSION OBJC OUTPUT_OPTION PC PREPROCESS.F PREPROCESS.S " \
			    "PREPROCESS.r RM SHELL SUFFIXES TANGLE TEX TEXI2DVI WEAVE YACC " \
			    "YACC.m YACC.y .FEATURES .INCLUDE_DIRS .LIBPATTERNS .LOADED " \
			    ".SHELLFLAGS .SHELLSTATUS .VARIABLES .RECIPEPREFIX .EXTRA_PREREQS " \
			    "CURDIR MAKEFLAGS MFLAGS MAKELEVEL MAKEFILE_LIST MAKEOVERRIDES " \
			    "GNUMAKEFLAGS MAKE_RESTARTS MAKE_TERMOUT MAKE_TERMERR", w, " ")
			for (i = 1; i <= n; i++) { fl[w[i]] = "u"; at[w[i]] = 0; src[w[i]] = "" }
			fl["MAKE"] = "s"; vv["MAKE"] = "make"; at["MAKE"] = 0
			fl["MAKECMDGOALS"] = "s"; vv["MAKECMDGOALS"] = (goal == "-") ? "" : goal
			at["MAKECMDGOALS"] = 0
			fl[".DEFAULT_GOAL"] = "s"; vv[".DEFAULT_GOAL"] = ""; at[".DEFAULT_GOAL"] = 0
			n = split("abspath addprefix addsuffix and basename call dir error eval " \
			    "file filter filter-out findstring firstword flavor foreach guile if " \
			    "info join lastword notdir or origin patsubst realpath shell sort " \
			    "strip subst suffix value warning wildcard word wordlist words", w, " ")
			for (i = 1; i <= n; i++) FUNC[w[i]] = 1
			n = split("@ < ^ + ? * % |", w, " ")
			for (i = 1; i <= n; i++) { AUTO[w[i]] = 1; AUTO[w[i] "D"] = 1; AUTO[w[i] "F"] = 1 }
			# The targets that mean something to make, which no suffix
			# rule is.
			n = split(".PHONY .SUFFIXES .DEFAULT .PRECIOUS .INTERMEDIATE " \
			    ".NOTINTERMEDIATE .SECONDARY .SECONDEXPANSION .DELETE_ON_ERROR " \
			    ".IGNORE .LOW_RESOLUTION_TIME .SILENT .EXPORT_ALL_VARIABLES " \
			    ".NOTPARALLEL .ONESHELL .POSIX .WAIT", w, " ")
			for (i = 1; i <= n; i++) SPECIAL[w[i]] = 1
			ctx = 0; curs = " "; ugen = 0; depth = 0
		}
		# A name as make files it: without the ./ in front, nor the
		# slashes after each (.//x is x); one that was nothing more is ./.
		function dot(x) {
			if (x !~ /^\.\// || length(x) <= 2) return x
			while (x ~ /^\.\// && length(x) > 2) { x = substr(x, 3); sub(/^\/+/, "", x) }
			return (x == "") ? "./" : x
		}
		# A variable: n unset, r set with = (its text kept), s set with :=
		# (its value kept), u not known here.
		function vstate(v) {
			if (chaos) return "u"
			if (v in fl) return (fl[v] != "u" && ugen > at[v]) ? "u" : fl[v]
			return ugen ? "u" : "n"
		}
		function setu(v, n, more) { fl[v] = "u"; at[v] = ugen; src[v] = n " " more }
		# The lines that made v uncertain, into EC.
		function whyvar(v,   k, w, i) {
			if (chaos) { for (k in chaosl) EC[k] = 1; return }
			if ((v in fl) && fl[v] == "u") {
				k = split(src[v], w, " ")
				for (i = 1; i <= k; i++) EC[w[i]] = 1
				return
			}
			EC[ugline[(v in at) ? at[v] + 1 : 1]] = 1
		}
		function ecs(   k, s) { s = ""; for (k in EC) s = s " " k; return s }
		function unsure() { EU = 1; EC[curn] = 1 }
		# s as make expands it: m "i" as it reads a line, "r" as it runs a
		# recipe, once the whole file is read; d how deep in variables. EU is
		# set when anything uncertain was touched, EC holds why.
		function ex(s, m, d,   out, j, c, k, lv, cl, cc) {
			# Past 30 deep, or 20000 expansions for one line, it gives up.
			if (!d) EXN = 0
			if (d > 30 || ++EXN > 20000) { unsure(); return "" }
			out = ""
			while ((j = index(s, "$")) > 0) {
				out = out substr(s, 1, j - 1)
				c = substr(s, j + 1, 1)
				if (c == "") { s = ""; break }
				if (c == "$") { out = out "$"; s = substr(s, j + 2); continue }
				if (c == "(" || c == "{") {
					cl = (c == "(") ? ")" : "}"
					lv = 1
					for (k = j + 2; k <= length(s); k++) {
						cc = substr(s, k, 1)
						if (cc == c) lv++
						else if (cc == cl && --lv == 0) break
					}
					if (lv) { unsure(); s = ""; break }
					out = out ref(substr(s, j + 2, k - j - 2), m, d)
					s = substr(s, k + 1)
					continue
				}
				out = out value(c, m, d)
				s = substr(s, j + 2)
			}
			return out s
		}
		# What is inside a $(...): a function, a substitution of a
		# variable ($(V:a=b), $(V:%.c=%.o)), or a variable. make takes a
		# name for the name of a function when any space follows it: a
		# blank, a newline (in a define), a CR, a vertical tab or a form
		# feed.
		function ref(r, m, d,   fn, i, sb, v, a) {
			if (match(r, /^[a-z-]+[ \t\n\v\f\r]/)) {
				fn = substr(r, 1, RLENGTH - 1)
				if (fn in FUNC) return call(fn, m)
			}
			# AH counts the words value() (below) gives in place of a value:
			# what an automatic variable reads as in a recipe, and, in the
			# words of an echo, a variable make defines that the file never
			# sets (CC). Such a word is no value of the variable, so neither
			# is a name built from one nor a substitution of one ($($@),
			# $(CC:.c=.o)): either is uncertain.
			a = AH
			if (index(r, "$")) r = ex(r, m, d + 1)
			if (AH != a) { unsure(); return "" }
			sb = ""
			if ((i = index(r, ":")) && index(substr(r, i + 1), "=")) {
				sb = substr(r, i + 1)
				r = substr(r, 1, i - 1)
			}
			v = value(r, m, d)
			if (sb != "" && AH != a) { unsure(); return "" }
			return (sb != "" && v != "") ? subst(v, sb) : v
		}
		# A function is uncertain, but for info, warning and error as make
		# reads a line: they expand to nothing (error stops make). Once the
		# file has an eval, or a != that may give one, a function make calls
		# as it reads may run one.
		function call(fn, m) {
			if (m == "i" && evalseen) SFX = 1
			if (m == "i" && (fn == "info" || fn == "warning" || fn == "error")) return ""
			unsure()
			return ""
		}
		function value(nm, m, d,   st, v) {
			# .VARIABLES lists the variables of the environment too, and
			# their names may hold a ; (maysemi).
			if (nm == ".VARIABLES") semiseen = 1
			# make gives an automatic variable its value as it runs the rule,
			# and none as it reads a line. In a recipe it reads here as one
			# word (AH, ref above), which an echo may print, and as
			# uncertain once a target or a prerequisite may hold what sh
			# reads, a ; or a quote (unsafe, below: autou).
			if (nm in AUTO) {
				if (m == "i") return ""
				AH++
				if (autou) { EU = 1; EC[autol] = 1 }
				return "f"
			}
			if (m == "r" && (tsvany || (nm in tsvu) || reval)) {
				EU = 1; EC[tsvany ? tsvanyl : (nm in tsvu) ? tsvu[nm] : curn] = 1
				return ""
			}
			st = vstate(nm)
			if (st == "n") return ""
			# In the words of a recipe line that is an echo (OWNW, set by
			# the END loop), a variable make itself defines and nothing in
			# the file sets -- CC, CFLAGS -- is one word the echo prints
			# (AH, ref above), as an automatic variable is: make or the
			# environment gives it its value, never the Makefile. Not once
			# the file has an include or an eval, either of which may set
			# it.
			if (OWNW && st == "u" && !chaos && !ugen && (nm in fl) && fl[nm] == "u" && src[nm] == "") {
				AH++
				return "f"
			}
			# A value this reader cannot know may hold an eval, once the file
			# has one or a != (bang, below), and make runs it as it reads the
			# line.
			if (st == "u") { EU = 1; whyvar(nm); if (m == "i" && evalseen) SFX = 1; return "" }
			if (st == "s") return vv[nm]
			# A variable that refers to itself is an error to make.
			if (nm in act) { unsure(); return "" }
			act[nm] = 1
			v = ex(vv[nm], m, d + 1)
			delete act[nm]
			return v
		}
		# The words of list with sb ("a=b", or "p%s=q%t") applied, as
		# $(V:a=b) applies it: a word that does not match stays as it is.
		function subst(list, sb,   i, a, b, p1, p2, w, n, k, out, st) {
			i = index(sb, "=")
			a = substr(sb, 1, i - 1)
			b = substr(sb, i + 1)
			if (!index(a, "%")) { a = "%" a; b = "%" b }
			i = index(a, "%")
			p1 = substr(a, 1, i - 1)
			p2 = substr(a, i + 1)
			n = split(list, w, /[ \t]+/)
			out = ""
			for (k = 1; k <= n; k++) {
				if (w[k] == "") continue
				if (length(w[k]) >= length(p1) + length(p2) &&
				    substr(w[k], 1, length(p1)) == p1 &&
				    substr(w[k], length(w[k]) - length(p2) + 1) == p2) {
					st = substr(w[k], length(p1) + 1, length(w[k]) - length(p1) - length(p2))
					i = index(b, "%")
					w[k] = i ? substr(b, 1, i - 1) st substr(b, i + 1) : b
				}
				out = out (out == "" ? "" : " ") w[k]
			}
			return out
		}
		# x up to its first character of stops that is in no reference and
		# no backslash quotes, as make cuts a line: SCHAR is the one found,
		# SREST what follows it. A quoted one stays, without its backslash.
		function scan(x, stops,   i, n, c, d, k, lv, cl, o, nb) {
			o = ""; SCHAR = ""; SREST = ""
			n = length(x)
			for (i = 1; i <= n; i++) {
				c = substr(x, i, 1)
				if (c == "$") {
					d = substr(x, i + 1, 1)
					if (d == "(" || d == "{") {
						cl = (d == "(") ? ")" : "}"
						lv = 1
						for (k = i + 2; k <= n; k++) {
							c = substr(x, k, 1)
							if (c == d) lv++
							else if (c == cl && --lv == 0) break
						}
						o = o substr(x, i, k - i + 1); i = k
						continue
					}
					o = o "$" d; i++
					continue
				}
				if (index(stops, c)) {
					match(o, /\\*$/); nb = RLENGTH
					o = substr(o, 1, length(o) - nb + int(nb / 2))
					if (nb % 2 == 0) { SCHAR = c; SREST = substr(x, i + 1); return o }
				}
				o = o c
			}
			return o
		}
		# The place of the first `:` outside a reference (anywhere, with
		# plain) that no backslash quotes, or 0.
		function colon(x, plain,   i, n, c, d, lv, cl, bs) {
			n = length(x); bs = 0
			for (i = 1; i <= n; i++) {
				c = substr(x, i, 1)
				if (c == "\\") { bs++; continue }
				if (c == ":" && bs % 2 == 0) return i
				bs = 0
				if (c == "$" && !plain) {
					d = substr(x, i + 1, 1)
					if (d == "(" || d == "{") {
						cl = (d == "(") ? ")" : "}"
						lv = 1
						for (i += 2; i <= n; i++) {
							c = substr(x, i, 1)
							if (c == d) lv++
							else if (c == cl && --lv == 0) break
						}
					} else i++
				}
			}
			return 0
		}
		# Whether x is an assignment, as make finds one: PN the name, PO the
		# operator (= := ::= :::= += ?= !=), PV the value. A reference in
		# the name is skipped whole, so its = is no operator.
		function pvd(x,   i, n, c, d, cl, lv, ws, e) {
			sub(/^[ \t]+/, "", x)
			n = length(x); ws = 0; e = 0; PO = ""
			for (i = 1; i <= n; i++) {
				c = substr(x, i, 1)
				if (c == "#") return 0
				if (c == "$") {
					c = substr(x, i + 1, 1)
					if (c == "") return 0
					if (c != "(" && c != "{") { i++; continue }
					cl = (c == "(") ? ")" : "}"
					lv = 1
					for (i += 2; i <= n; i++) {
						d = substr(x, i, 1)
						if (d == cl && --lv == 0) break
						if (d == c) lv++
					}
					continue
				}
				if (c == " " || c == "\t") {
					ws = 1; e = i
					while (i < n && index(" \t", substr(x, i + 1, 1))) i++
					if (i >= n) return 0
					c = substr(x, ++i, 1)
				}
				d = substr(x, i + 1, 1)
				if (c == "=") { PO = "="; if (!e) e = i; i++; break }
				if (d == "=" && index(":+?!", c)) { PO = c "="; if (!e) e = i; i += 2; break }
				if (d == "=") { if (ws) return 0; continue }
				if (c == ":") {
					if (substr(x, i + 1, 2) == ":=") { PO = "::="; if (!e) e = i; i += 3; break }
					if (substr(x, i + 1, 3) == "::=") { PO = ":::="; if (!e) e = i; i += 4; break }
					return 0
				}
				if (ws) return 0
			}
			if (PO == "") return 0
			PN = substr(x, 1, e - 1)
			PV = substr(x, i)
			sub(/^[ \t]+/, "", PV)
			return 1
		}
		# pvd after the words make takes for modifiers, PM: tv for the
		# rest of a rule line, where define and undefine are none.
		function pva(x, tv,   w) {
			PM = ""
			sub(/^[ \t]+/, "", x)
			while (x != "") {
				if (pvd(x)) return 1
				match(x, /^[^ \t]+/)
				w = substr(x, 1, RLENGTH)
				x = substr(x, RLENGTH + 1)
				sub(/^[ \t]+/, "", x)
				if (w == "export" || w == "unexport" || w == "override" || w == "private") PM = PM " " w
				else if (!tv && (w == "define" || w == "undefine")) {
					PM = PM " " w; PN = x; PO = ""; PV = ""
					return 1
				}
				else return 0
			}
			return 0
		}
		function setchaos(n) { chaos = 1; chaosl[n] = 1 }
		# A line that may give .EXTRA_PREREQS words: make adds them to the
		# prerequisites of each rule it is set for, every rule when it is set
		# as any variable is.
		function xpset(n) { xp = 1; xpl[n] = 1 }
		# Whether x calls a function that fn names (a|b), by its name or
		# through call, which runs any function by the name it is given: call
		# itself among them, and one a reference gives.
		function calls(x, fn,   f) {
			if (x ~ ("\\$[({](" fn ")[ \t\n\v\f\r]")) return 1
			while (match(x, /\$[({]call[ \t\n\v\f\r]/)) {
				x = substr(x, RSTART + RLENGTH)
				match(x, /^[^,)}]*/)
				f = substr(x, 1, RLENGTH)
				gsub(/^[ \t\n\v\f\r]+|[ \t\n\v\f\r]+$/, "", f)
				if (index(f, "$") || f == "call" || f ~ ("^(" fn ")$")) return 1
			}
			return 0
		}
		# Whether a value may hold a ;: one in its text, or one that a
		# function may give and the Makefile does not hold (what a shell
		# prints, the text of a file, the names a wildcard finds). A file it
		# includes, and a != (what a shell prints), may give one too. So may
		# the name of a variable, one the Makefile sets or exports or one
		# from the environment, which .VARIABLES lists: a reference to it may
		# give one (value, above, where a reference gives its name). A ; in
		# the targets or prerequisites of a rule, once expanded, starts its
		# recipe, so from here on a rule whose list this reader cannot expand
		# may have a recipe it cannot see (gateu, and ru: ruleline).
		function maysemi(x) {
			if (index(x, ";") || index(x, ".VARIABLES") || calls(x, "shell|file|guile|wildcard"))
				semiseen = 1
		}
		# A != sets a variable to what a shell prints, and make expands that
		# again where the variable is used: a ; may come from it, and so may
		# an eval the Makefile text never shows, which make runs where a
		# line it reads uses the variable.
		function bang() { semiseen = 1; evalseen = 1 }
		# ov[v]: 1 set with override, so a plain assignment to v changes
		# nothing; 2 maybe so; ovl[v] the line that made it maybe.
		function ovset(v, o, n) { if (o == 2 && ov[v] != 2) ovl[v] = n; ov[v] = o }
		# A line that may set PN (PM its modifiers), or may not: PN is not
		# known below it, and with override, nor is a plain assignment to it.
		function mayset(n,   w, o) {
			o = index(PM " ", " override ")
			maysemi(PN); maysemi(PV); if (PO == "!=") bang()
			EU = 0; split("", EC); w = trim(ex(PN, "i", 0)); maysemi(w)
			if ((EU || w == ".EXTRA_PREREQS") && !index(PM " ", " undefine ") && trim(PV) != "") xpset(n)
			if (EU) {
				ugen++; ugline[ugen] = n
				if (o) { ovany = 1; ovanyl = n }
				return
			}
			if (o && index(PM " ", " undefine ")) { if (ov[w] == 1) ovset(w, 2, n) }
			else if (o && ov[w] != 1) ovset(w, 2, n)
			setu(w, n)
		}
		# The rule above ends here: under a conditional, maybe.
		function endctx() {
			if (!depth) { ctx = 0; curs = " "; ccurs = " "; unkcur = 0 }
			else if (ctx == 1) ctx = 2
		}
		function assign(nm, op, raw, ovr, n, unc,   st, e, mb) {
			curn = n
			maysemi(nm); maysemi(raw); if (op == "!=") bang()
			if (index(nm, "$")) {
				EU = 0; split("", EC)
				nm = ex(nm, "i", 0)
				# Any variable may be the one set, with override too.
				if (EU) {
					ugen++; ugline[ugen] = n; if (ovr) { ovany = 1; ovanyl = n }
					if (op != "undefine" && (trim(raw) != "" || unc)) xpset(n)
					return
				}
			}
			nm = trim(nm); maysemi(nm)
			if (nm == ".EXTRA_PREREQS" && op != "undefine" && (trim(raw) != "" || unc)) xpset(n)
			if (nm == ".RECIPEPREFIX") { setchaos(n); return }
			if (nm == ".DEFAULT_GOAL") dgl = n
			st = vstate(nm)
			# ?= on a variable that is set changes nothing, override or not,
			# nor does += with nothing to add; mb: maybe nothing.
			if (op == "?=" && (st == "r" || st == "s")) return
			mb = (op == "?=" && st == "u")
			if (op == "+=" && st != "n") {
				if (raw == "" && !unc) return
				if (st == "s") {
					EU = 0; split("", EC)
					if (ex(raw, "i", 0) == "" && !EU) return
					mb = EU
				}
				if (st == "u") mb = 1
			}
			# A variable set with override ignores a plain assignment, and
			# undefine with override unsets it for good.
			if (!ovr && ov[nm] == 1) return
			if (ovr) {
				if (op == "undefine") ovset(nm, depth ? (ov[nm] ? 2 : 0) : 0, n)
				else if (mb) { if (ov[nm] != 1) ovset(nm, 2, n) }
				else ovset(nm, (depth && ov[nm] != 1) ? 2 : 1, n)
				if (depth || unc) { setu(nm, n); return }
			}
			else if (ov[nm] == 2 || ovany || depth || unc) {
				setu(nm, n, (ov[nm] == 2 ? ovl[nm] : "") (ovany ? " " ovanyl : ""))
				return
			}
			if (op == "undefine") { fl[nm] = "n"; vv[nm] = ""; at[nm] = ugen; return }
			if (op == "!=") { setu(nm, n); return }
			if (st == "u" && (op == "?=" || op == "+=")) {
				split("", EC); whyvar(nm); setu(nm, n, ecs())
				return
			}
			if (op == "?=") {
				if (st != "n") return
				op = "="
			}
			if (op == "+=") {
				if (st == "n") op = "="
				else if (st == "r") { vv[nm] = (vv[nm] == "" ? raw : vv[nm] " " raw); return }
				else {
					EU = 0; split("", EC)
					e = ex(raw, "i", 0)
					if (EU) { setu(nm, n, ecs()); return }
					vv[nm] = (vv[nm] == "" ? e : vv[nm] " " e)
					return
				}
			}
			if (op == "=") { fl[nm] = "r"; vv[nm] = raw; at[nm] = ugen; return }
			EU = 0; split("", EC)
			e = ex(raw, "i", 0)
			if (EU) { setu(nm, n, ecs()); return }
			fl[nm] = "s"; vv[nm] = e; at[nm] = ugen
		}
		# A define body, line by line, to its endef: one line is a value,
		# more (or one a backslash continues) is none this reads. make takes
		# a backslash and newline in it, with the blanks around them, for one
		# space, on each of its lines, a TAB line too; and the name of a
		# function may end a line of it, the newline after the name being the
		# space make reads it by, so the whole body is looked at too.
		function defline(x, n,   y) {
			while (odd_bs(x) && (getline y) > 0) {
				y = no_cr(y); dcont = 1
				x = substr(x, 1, length(x) - 1)
				sub(/[ \t]+$/, "", x); sub(/^[ \t]+/, "", y)
				x = x " " y
			}
			if (substr(x, 1, 1) != "\t") {
				if (x ~ /^[ \t]*define([ \t]|$)/) dlev++
				else if (x ~ /^[ \t]*endef([ \t]|$)/ && --dlev == 0) {
					indef = 0
					maysemi(dbody)
					if (calls(dbody, "eval|guile")) evalseen = 1
					if (pvd(dspec)) { dnm = PN; dop = PO } else { dnm = dspec; dop = "=" }
					assign(dnm, dop, dn == 1 ? dbody : "", index(dpm " ", " override "), defn, dn > 1 || dcont)
					return
				}
			}
			maysemi(x)
			if (calls(x, "eval|guile")) evalseen = 1
			dbody = dn++ ? dbody "\n" x : x
		}
		# A recipe line as make expands it, once the whole file is read:
		# make first takes each backslash and newline inside a reference,
		# with the blanks before them and the spaces after, for one space
		# (its job.c, so that a function sees none of them), which can make
		# the name before them the name of a function. Two backslashes
		# there are no such pair. The rest of the line keeps them, as sh
		# reads it.
		function colref(s,   o, j, c, cl, lv, ch, q, k) {
			o = ""
			while ((j = index(s, "$")) > 0) {
				o = o substr(s, 1, j)
				s = substr(s, j + 1)
				c = substr(s, 1, 1)
				if (c != "(" && c != "{") continue
				cl = (c == "(") ? ")" : "}"
				o = o c; s = substr(s, 2); lv = 0; k = length(o)
				while (s != "") {
					ch = substr(s, 1, 1)
					if (ch == cl && --lv < 0) break
					if (ch == "\\" && substr(s, 2, 1) == "\n") {
						match(substr(o, k + 1), /\\*$/)
						if (RLENGTH % 2) { o = o ch; s = substr(s, 2); continue }
						s = substr(s, 3); sub(/^[ \t\n\v\f\r]+/, "", s)
						q = substr(o, k + 1); sub(/[ \t]+$/, "", q)
						o = substr(o, 1, k) q " "
						continue
					}
					if (ch == c) lv++
					o = o ch; s = substr(s, 2)
				}
			}
			return o s
		}
		function recipe(t, n, tgs) {
			t = colref(t)
			rN++; rl[rN] = n; rt[rN] = t; rtg[rN] = tgs
			# An eval make runs as it expands a recipe may set any variable.
			if (calls(t, "eval|guile")) reval = 1
		}
		function addl(arr, t, n) { arr[t] = arr[t] " " n }
		function unsafe(w) { return w ~ /[;&|<>`"\\$()]/ || index(w, "\047") }
		function autouns(n) { if (!autou) { autou = 1; autol = n } }
		# The first target t of a rule, that is no .name in no pattern
		# rule, sets the default goal while it is empty -- unless override
		# set it.
		function dgcand(t, n,   st) {
			st = vstate(".DEFAULT_GOAL")
			if (st == "u" || (st != "n" && vv[".DEFAULT_GOAL"] != "")) return
			if (ov[".DEFAULT_GOAL"] == 1) return
			if (ov[".DEFAULT_GOAL"] == 2 || ovany) {
				setu(".DEFAULT_GOAL", n, ov[".DEFAULT_GOAL"] == 2 ? ovl[".DEFAULT_GOAL"] : ovanyl)
				dgl = n
				return
			}
			if (st == "n" || depth || t == "") { setu(".DEFAULT_GOAL", n); dgl = n; return }
			fl[".DEFAULT_GOAL"] = "s"; vv[".DEFAULT_GOAL"] = t; at[".DEFAULT_GOAL"] = ugen
			dgl = n
		}
		# A line make reads as a rule: targets, then prerequisites, then
		# the recipe after a ;.
		function ruleline(x, n,   pre, semi, rec, i, tg, rest, tu, m, w, tw, k, j, pat, pr, pu, stat, tgs, why, pn, dc, pb) {
			pre = scan(x, ";#")
			semi = (SCHAR == ";")
			rec = semi ? SREST : ""
			if (!(i = colon(pre))) { lone(pre, semi, n); return }
			tg = substr(pre, 1, i - 1)
			rest = substr(pre, i + 1)
			dc = (substr(rest, 1, 1) == ":")
			if (dc) rest = substr(rest, 2)
			sub(/[ \t]*&[ \t]*$/, "", tg)
			# A target-specific variable is no rule. make tells one by the text
			# before the ;, and gives the ; and what follows back to its value.
			if (pva(rest, 1)) {
				if (semi) PV = PV ";" rec
				endctx()
				if (index(PN, "$")) { tsvany = 1; tsvanyl = n } else tsvu[trim(PN)] = n
				if ((index(PN, "$") || trim(PN) == ".EXTRA_PREREQS") && trim(PV) != "") xpset(n)
				maysemi(PV)
				return
			}
			curn = n; EU = 0; split("", EC)
			tg = ex(tg, "i", 0)
			tu = EU
			m = 0; pat = 0
			if (!tu) {
				k = split(tg, w, /[ \t]+/)
				for (j = 1; j <= k; j++) {
					if (w[j] == "") continue
					w[j] = dot(w[j])
					gsub(/\\:/, ":", w[j])
					tw[++m] = w[j]
					if (index(w[j], "%")) pat = 1
					if (unsafe(w[j])) autouns(n)
				}
			} else autouns(n)
			maysemi(pre)
			curn = n; EU = 0; split("", EC)
			pr = ex(rest, "i", 0)
			pu = EU; why = ecs()
			if (!semi && !pu && (k = index(pr, ";"))) {
				semi = 1; rec = substr(pr, k + 1); pr = substr(pr, 1, k - 1)
			}
			stat = 0
			if (!pu && (k = colon(pr, 1))) { stat = 1; pr = substr(pr, k + 1) }
			gsub(/\|/, " ", pr)
			if (pu) autouns(n)
			else {
				k = split(pr, w, /[ \t]+/)
				for (j = 1; j <= k; j++) if (unsafe(w[j])) autouns(n)
			}
			if ((pu || tu) && semiseen) { gateu = 1; gatel[n] = 1 }
			pn = ""; pb = m
			if (pat && !stat) {
				# A pattern rule (implicit, below): its patterns, and a name
				# of its own its prerequisites and recipe go by. A target
				# with no % on the line keeps the rule: make gives it the
				# rule when such a target comes first, reading the % ones
				# then as plain names (and stops on the line when a % one
				# comes first); here they stay patterns, which can only make
				# the answer 5. pb: the targets with no % before the first
				# with one, the only ones that may be the default goal.
				pn = "%" (++pN); ps[pN] = ""; pl[pN] = n
				k = m; m = 0; pb = -1
				for (j = 1; j <= k; j++) {
					if (!index(tw[j], "%")) { tw[++m] = tw[j]; continue }
					ps[pN] = ps[pN] " " tw[j]
					if (pb < 0) pb = m
				}
			}
			if (!pu && !depth) for (j = 1; j <= m; j++) if (tw[j] == ".PHONY") {
				k = split(pr, w, /[ \t]+/)
				for (i = 1; i <= k; i++) if (w[i] != "") phony[dot(w[i])] = 1
			}
			# The suffixes .SUFFIXES names, under a conditional too: any
			# name, when this reader cannot expand them.
			for (j = 1; j <= m; j++) if (tw[j] == ".SUFFIXES") {
				if (pu) sfxu = 1
				else {
					k = split(pr, w, /[ \t]+/)
					for (i = 1; i <= k; i++) if (w[i] != "") SUFD[w[i]] = 1
				}
			}
			# The context the recipe lines below belong to; ccurs, the
			# targets whose rule is certain to be there: none, after a rule
			# under a conditional, as the lines may belong to that rule or
			# to the one above it.
			if (!depth) { ctx = 1; curs = " "; ccurs = " "; unkcur = 0 }
			else {
				ccurs = " "
				if (ctx == 0) { ctx = 2; curs = " "; unkcur = 0 }
			}
			tgs = " "
			for (j = 1; j <= m; j++) {
				has[tw[j]] = 1
				if (!(tw[j] in tl)) tl[tw[j]] = n
				# Each :: rule of a target is one of its own: dcn counts
				# them, dco says the last has no recipe yet (recd, below).
				if (dc) { dcn[tw[j]]++; dco[tw[j]] = 1 }
				if (!depth) { cert[tw[j]] = 1; ccurs = ccurs tw[j] " " }
				if (!index(tgs, " " tw[j] " ")) tgs = tgs tw[j] " "
				if (!index(curs, " " tw[j] " ")) curs = curs tw[j] " "
				if (pu) { addl(Ul, tw[j], n); uc[n] = why }
				else if (trim(pr) != "") addl(Wl, tw[j], n)
			}
			if (pn != "") {
				tgs = tgs pn " "; curs = curs pn " "
				if (pu) { addl(Ul, pn, n); uc[n] = why }
				else if (trim(pr) != "") addl(Wl, pn, n)
			}
			# Targets it cannot expand may be any, patterns among them: a
			# reference may hold several words, and one may be a %.
			if (tu) { unktgt = 1; unkl[n] = 1; unkcur = 1; dgcand("", n) }
			else for (j = 1; j <= m && j <= pb; j++) {
				if (index(tw[j], "%")) break
				if (tw[j] ~ /^\./ && !index(tw[j], "/")) continue
				# make passes over a name it may take for a suffix rule.
				if (sfxname(tw[j])) { dgcand("", n); break }
				dgcand(tw[j], n)
				break
			}
			if (semi) { recipe(rec, n, tgs); if (!depth) recd(tgs) }
			# A ; it cannot see may start a recipe in what it cannot expand:
			# maybe one, whose lines are those it could not tell from.
			else if (pu && semiseen) { recipe("", n, tgs); ru[rN] = why }
		}
		# Targets that have a recipe for certain, and the :: rule of each
		# that had none so far.
		function recd(s,   k, w, i) {
			k = split(s, w, " ")
			for (i = 1; i <= k; i++) {
				hasrec[w[i]] = 1
				if (dco[w[i]]) { dco[w[i]] = 0; dcr[w[i]]++ }
			}
		}
		# Whether x may be a suffix: one .SUFFIXES named, or any name with
		# a . in front, which the list make starts with may hold.
		function psuf(x) { return x != "" && (sfxu || (x in SUFD) || substr(x, 1, 1) == ".") }
		# Whether t, a name with no . in front, may name a suffix rule, by
		# the suffixes named so far: one of them, or one and then another.
		function sfxname(t,   i) {
			if (sfxu || (t in SUFD)) return 1
			for (i = 2; i <= length(t); i++)
				if ((substr(t, 1, i - 1) in SUFD) && psuf(substr(t, i))) return 1
			return 0
		}
		# A line with no `:`, such as a reference standing alone, make reads
		# as a rule all the same, once it is expanded: nothing, when it
		# expands to nothing; else a rule (or an error) this reader reads
		# again when it can, and is lost on. A function it calls (an eval)
		# may set any variable.
		function lone(pre, semi, n,   e) {
			endctx()
			curn = n; EU = 0; split("", EC)
			e = ex(pre, "i", 0)
			ugen++; ugline[ugen] = n
			if (!EU && trim(e) == "" && !semi) return
			if (!EU && !semi && colon(e) && !index(e, "$") && !index(e, "#")) { ruleline(e, n); return }
			lost = 1; whylost[n] = 1
			ctx = 2; curs = " "; unkcur = 1
		}
		# A directive make expands as it reads it (a conditional, include,
		# export, unexport, vpath): once the file has an eval, or a != that
		# may give one, a function it calls, or a variable it expands, may
		# run one, and leave this reader lost (SFX).
		function rdx(t) {
			if (!evalseen) return
			if (t ~ /\$[({][a-z-]+[ \t\n\v\f\r]/) { SFX = 1; return }
			EU = 0; split("", EC)
			ex(t, "i", 0)
		}
		# A line that is no recipe: an assignment, a directive, or a rule.
		# maybe: a TAB line that may be a recipe instead, so what it sets
		# is uncertain, and what would change how the lines below are read
		# leaves this reader lost.
		function ordinary(x, n, maybe,   t, w) {
			curn = n
			if (calls(x, "eval|guile")) evalseen = 1
			t = scan(x, "#")
			sub(/^[ \t]+/, "", t)
			if (t == "") return
			if (pva(t, 0)) {
				if (index(PM " ", " define ")) {
					if (maybe) { setchaos(n); return }
					endctx()
					indef = 1; dlev = 1; dn = 0; dcont = 0; dbody = ""
					defn = n; dpm = PM; dspec = PN
					return
				}
				if (maybe) { mayset(n); return }
				endctx()
				if (index(PM " ", " undefine ")) assign(PN, "undefine", "", index(PM " ", " override "), n, 0)
				else assign(PN, PO, PV, index(PM " ", " override "), n, 0)
				return
			}
			match(t, /^[^ \t]+/)
			w = substr(t, 1, RLENGTH)
			if (w ~ /^(ifeq|ifneq|ifdef|ifndef|else|endif)$/) {
				if (maybe) { setchaos(n); return }
				rdx(t)
				if (w == "endif") { if (depth) depth--; else { lost = 1; whylost[n] = 1 } }
				else if (w == "else") { if (!depth) { lost = 1; whylost[n] = 1 } }
				else condl[++depth] = n
				return
			}
			if (w == "endef") { if (maybe) setchaos(n); else { lost = 1; whylost[n] = 1 }; return }
			# export and unexport define each variable they name that is
			# not set.
			if (w == "export" || w == "unexport") maysemi(t)
			if (w == "export" || w == "unexport" || w == "vpath") { rdx(t); if (!maybe) endctx(); return }
			if (w ~ /^(include|-include|sinclude|load|-load)$/) {
				rdx(t)
				ugen++; ugline[ugen] = n; semiseen = 1
				if (!maybe) endctx()
				return
			}
			if (substr(x, 1, 1) == "\t") {
				# make: the recipe commences before the first target
				if (maybe) ctx = 1
				else { lost = 1; whylost[n] = 1 }
				return
			}
			ruleline(x, n)
		}
		# A recipe line make might read as an assignment: what it sets is
		# not certain.
		function shaped(t, n) {
			if (pva(t, 0) && !index(PM " ", " define ")) mayset(n)
		}
		# A recipe line as written, from its first command: make passes it
		# on without the TAB after each newline, or the - @ + and blanks
		# before it.
		function bare(t) {
			gsub(/\n\t/, "\n", t)
			sub(/^[-@+ \t]+/, "", t)
			return t
		}
		# The command t starts with, when it is one that runs nothing --
		# echo, true or : -- else "": the word ends at a blank, a newline,
		# a backslash, a ; & | < or >, or the end of t. literal, echoed
		# and busy all ask it, so they never disagree on what is an echo.
		function noop(t,   c) {
			if (!match(t, /^(echo|true|:)/)) return ""
			c = substr(t, RLENGTH + 1, 1)
			return (c == "" || index(" \t\n\\;&|<>", c)) ? substr(t, 1, RLENGTH) : ""
		}
		# A recipe line, as written, that starts with a command no
		# expansion can change and that is no echo: it does something,
		# whatever the rest of it expands to.
		function literal(t,   w) {
			t = bare(t)
			if (noop(t) != "" || !match(t, /^[^ \t\n;&|<>()]+/)) return 0
			w = substr(t, 1, RLENGTH)
			if (w ~ /[$\\"`]/ || index(w, "\047") || w ~ /^#/) return 0
			return 1
		}
		# A recipe line, as written, whose command is echo.
		function echoed(t) {
			return noop(bare(t)) == "echo"
		}
		# A recipe line, expanded, that does more than one echo: one
		# judge_mk would report, or one that starts as a stub line does
		# and runs more -- a second command after an unquoted ; & or |, a
		# redirection (not >&2, below), a command substituted into its
		# words, or a command on a line a comment continues (sh ends a
		# comment at the newline make passes on). Quotes are read as sh
		# reads them; a continued line keeps its backslash and newline, so
		# an echo whose words go on is one echo.
		function busy(r, inner,   i, c, d, q, cm, n) {
			gsub(/\n\t/, "\n", r)
			if (inner) sub(/^[ \t]+/, "", r)
			else sub(/^[-@+ \t]+/, "", r)
			r = trim(r)
			if (r == "") return 0
			if (r ~ /^#/) cm = 1
			else if (noop(r) == "") return 1
			q = 0
			n = length(r)
			for (i = 1; i <= n; i++) {
				c = substr(r, i, 1)
				d = substr(r, i + 1, 1)
				if (cm) {
					# The comment ends here; what follows is a command.
					if (c == "\n") return busy(substr(r, i + 1), 1)
					continue
				}
				if (q == 1) { if (c == "\047") q = 0; continue }
				if (c == "\\") { i++; continue }
				if (c == "`" || (c == "$" && d == "(")) return 1
				if (q == 2) { if (c == "\"") q = 0; continue }
				if (c == "\047") { q = 1; continue }
				if (c == "\"") { q = 2; continue }
				# >&2 or 1>&2, one descriptor made a copy of another (an
				# echo to stderr), opens no file and runs nothing.
				if (c == ">" && substr(r, i, 4) ~ /^>&[0-9]([ \t\n;&|]|$)/) { i += 2; continue }
				if (index(";&|<>\n", c)) return 1
				if (c == "#" && (i == 1 || substr(r, i - 1, 1) ~ /[ \t]/)) cm = 1
			}
			return 0
		}
		function line(x, n,   y, p) {
			if (indef) { defline(x, n); return }
			if (substr(x, 1, 1) == "\t" && ctx) {
				# A recipe line, as make passes it to sh: its backslash
				# and newline kept.
				while (odd_bs(x) && (getline y) > 0) { y = no_cr(y); x = x "\n" y }
				p = x; gsub(/\\\n/, " ", p); text[n] = p
				recipe(substr(x, 2), n, curs)
				if (ctx == 1) {
					if (!depth) recd(ccurs)
					shaped(substr(x, 2), n)
					return
				}
				y = x; gsub(/[ \t]*\\\n[ \t]*/, " ", y)
				ordinary(y, n, 1)
				return
			}
			while (odd_bs(x) && (getline y) > 0) {
				y = no_cr(y)
				x = substr(x, 1, length(x) - 1)
				sub(/[ \t]+$/, "", x); sub(/^[ \t]+/, "", y)
				x = x " " y
			}
			text[n] = x
			ordinary(x, n, 0)
		}
		{
			n = NR
			x = $0
			line(x, n)
			if (SFX) { SFX = 0; ugen++; ugline[ugen] = n; lost = 1; whylost[n] = 1 }
		}
		function show(set,   k, a, m, i, j, t) {
			m = 0
			for (k in set) if (k + 0 > 0) a[++m] = k + 0
			for (i = 2; i <= m; i++) {
				t = a[i]
				for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]
				a[j + 1] = t
			}
			for (i = 1; i <= m; i++) if (a[i] in text) printf "    %d: %s\n", a[i], text[a[i]]
		}
		function addset(set, s,   k, w, i) {
			k = split(s, w, " ")
			for (i = 1; i <= k; i++) set[w[i]] = 1
		}
		# THE IMPLICIT SEARCH. For a goal with no recipe of its own that is
		# not .PHONY, make looks for another rule of the Makefile to make it
		# with: a pattern rule whose pattern fits it (kind p), a suffix rule
		# (s), and, for a name no rule has, the recipe of .DEFAULT (d).
		# Whether make takes one turns on files this reader never looks at,
		# so one with a recipe that gives the goal a prerequisite, or has a
		# recipe line that does something or may, makes the answer 5: un,
		# its lines in WHY. A rule with no recipe makes nothing, unless a ;
		# this reader cannot see may start one (ru, in ruleline). The
		# prerequisites of a pattern rule are those of the goal, and a
		# suffix rule always gives it one, the source its suffix names (make
		# drops any written on the line of a suffix rule); those of .DEFAULT
		# make gives to no goal.
		function imp(t, kind, rline,   k, w, j, r, f) {
			r = 0; f = 0; split("", IW)
			for (k = 1; k <= rN; k++) {
				if (!index(rtg[k], " " t " ")) continue
				r = 1
				if (rv[k] == "") continue
				IW[rl[k]] = 1; f = 1
				if (rv[k] == "u") addset(IW, rc[k])
			}
			if (!r) return
			if (kind == "s") f = 1
			if (kind == "p") {
				k = split(Wl[t] " " Ul[t], w, " ")
				for (j = 1; j <= k; j++) { IW[w[j]] = 1; f = 1; if (w[j] in uc) addset(IW, uc[w[j]]) }
			}
			if (!f) return
			IW[rline] = 1
			for (k in IW) WHY[k] = 1
			un = 1
		}
		# Whether a word of ps, the targets of a pattern rule, fits t: p%s
		# fits a name that starts with p and ends with s, or the part of it
		# after its last /.
		function pmatch(ps, t,   w, n, i, j, bn) {
			bn = t; sub(/^.*\//, "", bn)
			n = split(ps, w, " ")
			for (i = 1; i <= n; i++) {
				j = index(w[i], "%")
				if (pfit(substr(w[i], 1, j - 1), substr(w[i], j + 1), t) ||
				    pfit(substr(w[i], 1, j - 1), substr(w[i], j + 1), bn)) return 1
			}
			return 0
		}
		function pfit(a, b, t) {
			return length(t) >= length(a) + length(b) && substr(t, 1, length(a)) == a &&
			    substr(t, length(t) - length(b) + 1) == b
		}
		# Whether t, a target with no / and no %, may be a suffix rule that
		# makes g, by the suffixes .SUFFIXES named anywhere (psuf, above):
		# one suffix (.c, or a name it named) makes any name, and two
		# (.c.o) a name that ends in the second.
		function sfx(t, g,   i, s) {
			if (t ~ /[\/%]/ || (t in SPECIAL)) return 0
			if (sfxu || (t in SUFD) || t ~ /^\.[^.]+$/) return 1
			for (i = 2; i <= length(t); i++) {
				s = substr(t, i)
				if (psuf(substr(t, 1, i - 1)) && psuf(s) && length(g) > length(s) &&
				    substr(g, length(g) - length(s) + 1) == s) return 1
			}
			return 0
		}
		END {
			if (indef) { lost = 1; whylost[defn] = 1 }
			if (depth) { lost = 1; whylost[condl[depth]] = 1 }
			# Every recipe line, with the values the whole file gave.
			for (k = 1; k <= rN; k++) {
				curn = rl[k]; EU = 0; split("", EC)
				if (k in ru) { rv[k] = "u"; rc[k] = ru[k] }
				else {
					OWNW = echoed(rt[k])
					e = ex(rt[k], "r", 0)
					OWNW = 0
					if (!EU) rv[k] = busy(e, 0) ? "w" : ""
					else { rv[k] = literal(rt[k]) ? "w" : "u"; rc[k] = ecs() }
				}
				if (rv[k] != "") gate = 1
			}
			if (any != "") {
				for (k = 1; k <= rN; k++) if (rv[k] == "w") exit 1
				exit (gate || gateu || lost || chaos) ? 5 : 0
			}
			g = goal
			if (g == "-") {
				curn = 0; EU = 0; split("", EC); SFX = 0
				e = trim(value(".DEFAULT_GOAL", "i", 0))
				k = split(e, w, /[ \t]+/)
				if (EU || SFX || k > 1) {
					for (j in EC) OUT[j] = 1
					for (j in whylost) OUT[j] = 1
					if (dgl) OUT[dgl] = 1
					show(OUT)
					exit 5
				}
				g = dot(e)
			}
			wr = 0; un = 0
			if (g != "") {
				k = split(Wl[g], w, " ")
				for (j = 1; j <= k; j++) { OUT[w[j]] = 1; WHY[w[j]] = 1; wr = 1 }
				k = split(Ul[g], w, " ")
				for (j = 1; j <= k; j++) { OUT[w[j]] = 1; WHY[w[j]] = 1; addset(WHY, uc[w[j]]); un = 1 }
				for (k = 1; k <= rN; k++) {
					if (rv[k] == "" || !index(rtg[k], " " g " ")) continue
					OUT[rl[k]] = 1; WHY[rl[k]] = 1
					if (rv[k] == "w") wr = 1
					else { un = 1; addset(WHY, rc[k]) }
				}
				# A :: rule of g with no recipe is searched for on its own,
				# whatever the other :: rules of g have.
				if (!wr && (!(g in hasrec) || dcn[g] > dcr[g]) && !(g in phony)) {
					for (k = 1; k <= pN; k++) if (pmatch(ps[k], g)) imp("%" k, "p", pl[k])
					for (tn in has) if (sfx(tn, g)) imp(tn, "s", tl[tn])
					if ((".DEFAULT" in has) && !(g in cert)) imp(".DEFAULT", "d", tl[".DEFAULT"])
				}
			}
			# Which rules .EXTRA_PREREQS gives a prerequisite rests on values
			# this reader does not follow, so once it may be set, any may.
			if (!wr && xp && g != "") { for (j in xpl) WHY[j] = 1; un = 1 }
			if (wr) { show(OUT); exit 0 }
			if (un) { show(WHY); exit 5 }
			if (lost || unktgt || chaos) {
				for (j in whylost) WHY[j] = 1
				for (j in unkl) WHY[j] = 1
				for (j in chaosl) WHY[j] = 1
				show(WHY)
				exit 5
			}
			if (g == "" || !(g in has)) exit 3
			exit 4
		}' < "$1"
}

# ------------------------------------------------- shell deliverables + generators
#
# c-09's libft_creator.sh is a turned-in deliverable; the shell modules'
# generators/exNN.sh are the only place a shell answer lives at all. Both ship as
# a description and a no-op, so any command is an answer.
judge_sh() {
	awk "$_SC_NO_CR"'
		{ line = $0; gsub(/^[ \t]+|[ \t]+$/, "", line) }
		line == "" { next }
		line ~ /^#/ { next }
		line ~ /^:[ \t]*$/ { next }
		line ~ /^true[ \t]*$/ { next }
		{ printf "    %d: %s\n", NR, $0 }
	' < "$2"
}

# ------------------------------------------------------------ Markdown
#
# A README a subject has the student turn in is theirs to write, and what it
# says about their project is their answer in prose. Its stub is what the
# template gives them to start from: comments saying what to write, which a
# renderer never shows. So blank lines and <!-- --> blocks are all a stub
# may hold, and every other line is reported -- a heading, a sentence, text
# before a comment opens or after it closes. A comment never closed is
# reported where it opens: the rest of the file is text no block holds.
judge_md() {
	awk "$_SC_NO_CR"'
		{
			line = $0
			while (1) {
				if (incomment) {
					p = index(line, "-->")
					if (!p) { line = ""; break }
					line = substr(line, p + 3)
					incomment = 0
					continue
				}
				sub(/^[ \t\r]+/, "", line)
				if (line == "") break
				if (substr(line, 1, 4) == "<!--") {
					line = substr(line, 5)
					incomment = 1
					opened = NR; openline = $0
					continue
				}
				printf "    %d: %s\n", NR, $0
				break
			}
		}
		END { if (incomment) printf "    %d: %s (a comment never closed)\n", opened, openline }
	' < "$2"
}

# ------------------------------------------- NEITHER A STUB NOR AN ANSWER
#
# Every judge above asks what a file holds that a stub may not, and an empty
# file holds nothing, so it passed: "OK -- all 1 deliverable(s) are stubs" over
# a zero-byte .c. So did a stub's body with no 42 header above it. Neither is an
# answer, and neither is what the template ships: every stub it ships keeps
# something (a 42 header and a signature, a description and a TODO, a rule that
# only echoes), and every .c and .h opens with the 11-line 42 header. A file
# without that header is one reset_headers.sh skips, so the template build
# never re-stamps it and whatever stands in its place ships as it stands; and
# the norm refuses it. So each is refused, with a reason of its own, and the
# run exits 2 (below) unless an answer was found too.
#
# Asked only of a file its judge found nothing in: an answer with no header is
# an answer, and is reported as one. A file that defines nothing at all is
# still a stub when its header is there -- the template ships one, a header and
# a comment.
#
# is_blank KIND SRC -- SRC holds no line but blanks, and, for a script, its
# #! line. That is what empty means here, not zero bytes: the test was
# `[ ! -s ]`, so a generator holding one newline, or nothing but #!/bin/sh,
# and a Makefile holding one newline each passed as a stub, keeping no more
# of what the template gave them than a zero-byte file does.
is_blank() {
	awk -v kind="$1" '
		kind == "sh" && NR == 1 && /^#!/ { next }
		/[^ \t\r]/ { found = 1; exit }
		END { exit (found ? 1 : 0) }' < "$2"
}

# has_header SRC -- the header as reset_headers.sh knows it: its border, a
# comment of 74 stars, on line 1 and on line 11. Exit 2 when those borders
# are there but one or both end in \r, printing the number of each line
# whose border does ("1", "11" or "1 11"): the judges read a line without
# its \r, but reset_headers.sh reads no header in that file and would leave
# its identity as it is, so it is refused as one that nothing re-stamps,
# saying which border. Only the borders are read, so the reason names them
# and no other line: a half-converted file may have one CR border.
has_header() {
	awk 'BEGIN { b = "/* "; for (i = 0; i < 74; i++) b = b "*"; b = b " */" }
		(NR == 1 || NR == 11) && $0 == b { n++ }
		(NR == 1 || NR == 11) && $0 == b "\r" { cr++; at = at (at == "" ? "" : " ") NR }
		END {
			if (n == 2) exit 0
			if (n + cr == 2) { print at; exit 2 }
			exit 1
		}' < "$1"
}

# score KIND PATH -- read PATH, the blob the index holds for it in repo mode,
# judge it as KIND, and report what it holds that a stub may not. Never in a
# $(...): refuse has to end the run, not a subshell.
score() {
	checked=$((checked + 1))
	if [ "$MODE" = file ]; then
		_src=$2
	else
		# git's stderr goes out as it is: a blob it gives prints nothing
		# there, and where it gives none, its line is the one saying why
		# (a path a merge left in conflict: "not at stage 0").
		git show ":$2" > "$CONTENT_TMP" ||
			refuse "$2" "is tracked but its staged content could not be read"
		_src=$CONTENT_TMP
	fi
	# The judge's own status, kept: a file the shell cannot open for its awk
	# fails the judge with nothing printed, and nothing is exactly what a
	# stub prints.
	_out=$("judge_$1" "$2" "$_src") || refuse "$2" "could not be read to the end"
	# A Makefile judge_mk passes is read again by goal_rule, every rule's
	# recipe as make reads it (busy): judge_mk reads TAB lines that start
	# with echo as echoes, so `echo x; cc ...` and `echo x && $(CC) ...`
	# passed, and never sees a recipe after a `;` on a rule's line. --goal
	# has the same last word (below). goal_rule's `any` prints nothing, so
	# the report says what it found: a line that does more than echo (1),
	# or a file this reader could not tell (5), which counts as written too
	# but is no code it found, and is counted apart (untold) for the
	# summary to say so. A 5 comes from a line that uses what the reader
	# cannot know, or from a line it cannot read past (goal_rule's lost and
	# chaos: a stray endif, a define or conditional left open, a lone
	# $(eval ...)), so the text names both, and no example of either: a
	# list of examples went false for every cause it left out, and --goal
	# names the lines.
	if [ "$1" = mk ] && [ -z "$_out" ]; then
		goal_rule "$_src" - any > /dev/null
		case $? in
			0) ;;
			1) _out="$(printf '    %s
    %s
    %s
    %s' \
				"a recipe line does more than echo: a command after a ';', a '&&' or a" \
				"'|', a redirection to a file, a command run inside its words, or a recipe" \
				"after a ';' on a rule's own line. stub_check.sh --goal RULE MAKEFILE names" \
				"a rule's lines.")" ;;
			5)
				untold=$((untold + 1))
				_out="$(printf '    %s
    %s
    %s
    %s' \
				"this reader could not tell whether every recipe line only echoes: a line" \
				"uses what it cannot know, or the file holds a line it cannot read past," \
				"so it counts as written. stub_check.sh --goal RULE MAKEFILE names the" \
				"lines that made it so.")" ;;
			*) refuse "$2" "could not be read to the end" ;;
		esac
	fi
	if [ -n "$_out" ]; then
		report "$2" "$_out"
	elif is_blank "$1" "$_src"; then
		# The #! line is named only where is_blank skipped one.
		_shebang=""
		[ "$1" = sh ] && _shebang=" (and a script's #! line)"
		report_refused "$2" "$(printf '    %s\n    %s\n    %s\n    %s' \
			"is empty: no line in it but blanks$_shebang. It holds no" \
			"answer, and it is no stub either: every stub keeps what the template gave" \
			"it -- a 42 header and a signature, a description and a TODO, a rule that" \
			"only echoes.")"
	else
		case "$1" in
			c | h)
				_crb=$(has_header "$_src")
				case $? in
					0) ;;
					2)
						if [ "$_crb" = "1 11" ]; then
							_crw="$(printf '    %s\n    %s' \
								"has CRLF line ends: both borders of its 42 header, lines 1 and 11, end" \
								"in a carriage return, as an editor set to CRLF saves them.")"
						else
							_crn=11
							[ "$_crb" = 11 ] && _crn=1
							_crw="$(printf '    %s\n    %s' \
								"has a CRLF line end: the border on line $_crb of its 42 header ends in a" \
								"carriage return, and the one on line $_crn does not.")"
						fi
						report_refused "$2" "$(printf '%s\n    %s\n    %s' "$_crw" \
							"reset_headers.sh reads no header there, so nothing would re-stamp it. Save" \
							"it with LF line ends, the ones .gitattributes gives every text file here.")" ;;
					*) report_refused "$2" "$(printf '    %s\n    %s\n    %s' \
						"has no 42 header -- the 11-line block every .c and .h stub opens with," \
						"a border of 74 stars on its first and last line. The norm requires it," \
						"and nothing re-stamps a file without one.")" ;;
				esac ;;
		esac
	fi
}

if [ "$MODE" = defines ]; then
	# Every file vetted first, as --file does, so a bad one leaves no verdict
	# on the others; then NAME's body, wherever it is defined. A function
	# defined twice (a stub left beside the written copy) is written if
	# either body is, and the lines that make it so are printed.
	[ $# -gt 0 ] || { echo "stub_check: --defines $DEF_NAME needs at least one file" >&2; exit 2; }
	for f in "$@"; do
		[ -f "$f" ] || { echo "stub_check: no such file: $f" >&2; exit 2; }
		[ -r "$f" ] || { echo "stub_check: cannot read: $f" >&2; exit 2; }
		case "$f" in
			*.c | *.h) ;;
			*) echo "stub_check: --defines reads C sources and headers, not: $f" >&2; exit 2 ;;
		esac
	done
	_found=0
	_body=0
	for f in "$@"; do
		_out=$(judge_c "$f" "$f" "$DEF_NAME")
		case $? in
			0)
				_found=1
				[ -z "$_out" ] && continue
				_body=1
				echo "  $f"
				echo "$_out" ;;
			3) ;;
			*) refuse "$f" "could not be read to the end" ;;
		esac
	done
	if [ "$_body" -eq 1 ]; then
		echo "stub_check: $DEF_NAME holds more than a stub (above)."
		exit 1
	fi
	if [ "$_found" -eq 1 ]; then
		echo "stub_check: $DEF_NAME is defined, and its body is a stub."
		exit 0
	fi
	echo "stub_check: no file given defines $DEF_NAME."
	exit 3
fi

if [ "$MODE" = goal ]; then
	# The Makefile vetted as --file does, then judged whole (judge_mk): a
	# stub's rules do nothing, whatever they are named. Only then the rule.
	[ $# -eq 1 ] || { echo "stub_check: --goal $GOAL_NAME needs one Makefile" >&2; exit 2; }
	f=$1
	[ -f "$f" ] || { echo "stub_check: no such file: $f" >&2; exit 2; }
	[ -r "$f" ] || { echo "stub_check: cannot read: $f" >&2; exit 2; }
	case "$f" in
		*Makefile | *makefile) ;;
		*) echo "stub_check: --goal reads a Makefile, not: $f" >&2; exit 2 ;;
	esac
	_what="the $GOAL_NAME rule"
	[ "$GOAL_NAME" != - ] || _what="the default goal"
	# judge_mk reads TAB lines alone, so goal_rule's own reading of every
	# recipe line (one after a `;`, one a variable fills) has the last word.
	_out=$(judge_mk "$f" "$f") || refuse "$f" "could not be read to the end"
	if [ -z "$_out" ]; then
		goal_rule "$f" "$GOAL_NAME" any > /dev/null
		case $? in
			0)
				echo "stub_check: $f is a stub: no recipe in it does more than echo, so $_what does nothing yet."
				exit 0 ;;
			1 | 5) ;;
			*) refuse "$f" "could not be read to the end" ;;
		esac
	fi
	_out=$(goal_rule "$f" "$GOAL_NAME")
	case $? in
		0)
			printf '  %s\n' "$f"
			printf '%s\n' "$_out"
			echo "stub_check: $_what of $f does something (above)."
			exit 1 ;;
		5)
			printf '  %s\n' "$f"
			[ -z "$_out" ] || printf '%s\n' "$_out"
			echo "stub_check: could not tell from the line(s) above whether $_what of $f does something, so it counts as written."
			exit 1 ;;
		4)
			echo "stub_check: $_what of $f does nothing yet: no prerequisite, and no recipe line that does more than echo."
			exit 0 ;;
		3)
			if [ "$GOAL_NAME" = - ]; then
				echo "stub_check: $f has no rule a bare make would run."
			else
				echo "stub_check: $f has no $GOAL_NAME rule."
			fi
			exit 3 ;;
		*) refuse "$f" "could not be read to the end" ;;
	esac
fi

if [ "$MODE" = file ]; then
	# Check exactly the paths given, classified by name, with no git. The
	# workspace is read for one thing only, the place in it an approved
	# header is matched at (repo_path, above). This exists so
	# //tools/tests:selftest can drive the checker on known-bad fixtures in a
	# temp dir: the repo mode below is built on `git ls-files`, and a
	# self-test that needs a populated git repository is one that will not
	# run hermetically. Same split, and the same reason, as every other
	# runner the selftest reaches. Every path is vetted before any is scored,
	# so a bad one in the list leaves no verdict on the others.
	[ $# -gt 0 ] || { echo "stub_check: --file needs at least one path" >&2; exit 2; }
	for f in "$@"; do
		[ -f "$f" ] || { echo "stub_check: no such file: $f" >&2; exit 2; }
		[ -r "$f" ] || { echo "stub_check: cannot read: $f" >&2; exit 2; }
		case "$f" in
			*.c | *.h | *Makefile | *.sh | *.md) ;;
			*) echo "stub_check: not a deliverable kind: $f" >&2; exit 2 ;;
		esac
	done
	for f in "$@"; do
		case "$f" in
			*.c)       score c "$f" ;;
			*.h)       score h "$f" ;;
			*Makefile) score mk "$f" ;;
			*.sh)      score sh "$f" ;;
			*.md)      score md "$f" ;;
		esac
	done
else
	# Only repo mode has a workspace to stand in; --file takes the caller's cwd
	# so that a path relative to it still resolves.
	cd "$WS" || { echo "stub_check: cannot enter the workspace $WS: no verdict" >&2; exit 2; }
	_prefix="${scope:-*}"
	LISTS=$(mktemp -d) || { echo "stub_check: cannot create a scratch directory" >&2; exit 2; }
	CONTENT_TMP="$LISTS/content"
	trap 'rm -rf "$LISTS"' EXIT
	trap 'exit 143' TERM
	trap 'exit 130' INT
	trap 'exit 129' HUP

	# ls_index FILE PATHSPEC... -- the INDEX's paths matching PATHSPEC, one per
	# line, into FILE. A listing that fails is a refusal like an unreadable
	# blob: an empty list would read as a tree with nothing to ship. Git's own
	# words go out first: they were thrown away, and where git refuses the
	# folder -- no repository, or one another user owns that safe.directory
	# does not name -- they are the only line saying what to fix.
	ls_index() {
		_lf=$1
		shift
		git ls-files -z -- "$@" > "$_lf.z" || {
			echo "stub_check: git could not list the index (git ls-files -- $*)." >&2
			echo "            Refusing to score anything: an empty listing reads as nothing to ship." >&2
			exit 2
		}
		tr '\0' '\n' < "$_lf.z" > "$_lf"
	}

	# The zone, AGENTS.md §0: everything under a deliverable/ and everything
	# under a generators/, which for a shell module is the only place its
	# answer lives (its deliverable/ is generated and gitignored). The five
	# kinds below are read; ANYTHING ELSE tracked there is a file this checker
	# cannot vouch for, and the rule learned the hard way is that a file kind
	# which is not checked is a file kind that SHIPS. The kinds were once
	# three, and c-08's finished headers went out
	# under an "OK — all 123 deliverable(s) are stubs" verdict because nothing
	# read *.h. The same hole was open one kind further along:
	# c-piscine/c-piscine-rush-02/deliverable/ex00/README.md was a group
	# planning document carrying a teammate's real 42 login and email plus the
	# rush's function-by-function decomposition. reset_headers.sh only walks
	# *.c and *.h so it was never re-stamped, the template build excludes
	# deliverable/ from its staged identity grep, and --file mode exits 2 on
	# such a file -- so nothing in the publish path looked at it at all. (The
	# file is gone now, with the rest of that team's sources; the rule it
	# taught stays. A README.md under deliverable/ is read now, as the md
	# kind: a subject can have one turned in, and its stub is comments.) So
	# any other kind is listed: whether it should be deleted,
	# approved or scrubbed is the maintainer's call; what must not happen is
	# the checker passing in silence over a file it never opened. Under
	# generators/, only generators/exNN.sh is read, and a helper script or a
	# data file beside it is listed the same way.
	ls_index "$LISTS/zone" "$_prefix/deliverable/*" "$_prefix/generators/*"
	: > "$LISTS/other"
	: > "$LISTS/gen_other"
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		case "$f" in
			*/generators/*)
				case "${f##*/generators/}" in
					*/*) echo "$f" >> "$LISTS/gen_other" ;;
					ex*.sh) score sh "$f" ;;
					*) echo "$f" >> "$LISTS/gen_other" ;;
				esac ;;
			*.c) score c "$f" ;;
			*.h) score h "$f" ;;
			*/Makefile) score mk "$f" ;;
			*.sh) score sh "$f" ;;
			*/deliverable/*.md) score md "$f" ;;
			*) echo "$f" >> "$LISTS/other" ;;
		esac
	done < "$LISTS/zone"

	# And the rule §0 calls "no third place": a tracked file in a project folder
	# that is under none of deliverable/, generators/ or tests/ is somewhere this
	# checker never looks. Work written there -- c-piscine-reloaded's ex06/ at
	# the project root, say, where the Vogsphere repo has it -- would reach the
	# template unread. The allowlist is what legitimately lives beside a
	# project: its BUILD file, README and .gitignore, a group project's team
	# file (rush-00's team.bzl, which says what the team owes and holds no
	# code), its subject (or the template's placeholder), and the exam guide,
	# which is a study document rather than a project; and a course folder's
	# own README and .gitignore.
	#
	# Each at its place and nowhere deeper. A project folder is
	# <course>/<project>, or cursus/<Milestone>/<project> (a cursus project
	# may hold only its subject PDF, so no BUILD file can say where one is);
	# its tests/ is the folder directly in it. The names once matched at any
	# depth, so a README.md holding a method in a third-place folder, a PDF,
	# a team.bzl or a tests/ folder of one's own under one, went unread. A
	# deliverable/ or generators/ at any depth is the zone, read above.
	#
	# And 42's issued files, from tools/resources.tsv in the INDEX like
	# everything else here: each row's one registered path, and the placeholder
	# the template build writes for it, <project>/<file>.DOWNLOAD-ME.txt. By
	# exact path and nothing wider. This list used to name resources.tar.gz and
	# *.dict itself, which let any .dict at any project root through -- a stray
	# copy of rush-02's numbers.dict beside its BUILD file, say, which the
	# harness never reads -- and would have called a newly registered file at a
	# project root a third place. The registry's promise is that a row is the
	# whole job.
	res_allow=$(git show :tools/resources.tsv 2> /dev/null | awk -F'\t' '
		!/^#/ && NF >= 3 { print $1 "/" $2 ".DOWNLOAD-ME.txt"; print $3 }')
	#
	# The course folders by name, one line, which //tools:conventions holds
	# to the course folders the tree holds: a new course left out of it is
	# one whose project folders this rule never reads.
	COURSE_NAMES="c-piscine c-piscine-reloaded cursus"
	if [ -z "$scope" ]; then
		for _cn in $COURSE_NAMES; do
			ls_index "$LISTS/course_one" "$_cn/*"
			cat "$LISTS/course_one"
		done > "$LISTS/course"
	else
		ls_index "$LISTS/course" "$_prefix/*"
	fi
	awk -F/ '
		$0 == "" || /\/(deliverable|generators)\// { next }
		$1 == "c-piscine" && $2 == "c-piscine-exam-prep" { next }
		NF == 2 && ($2 == "README.md" || $2 == ".gitignore") { next }
		{ pd = ($1 == "cursus") ? 3 : 2 }
		NF > pd + 1 && $(pd + 1) == "tests" { next }
		NF == pd + 1 && ($NF ~ /^(BUILD\.bazel|README\.md|\.gitignore|team\.bzl)$/ ||
			$NF ~ /\.pdf$|groups_subject\.txt$|subject-ammendment\.md$/) { next }
		{ print }' "$LISTS/course" |
		{ if [ -n "$res_allow" ]; then grep -vxF -e "$res_allow"; else cat; fi; } \
		> "$LISTS/outside" || :
fi

# ------------------------------------------------- kinds nothing can classify
#
# Reported rather than skipped, because "this checker never opened the file" and
# "this file is a stub" are different statements and only one of them was being
# printed. --file mode has always exited 2 on an unknown kind; repo mode dropped
# it on the floor, which is the softer half of the same rule applied to the tree
# that actually gets published.
if [ "$MODE" = repo ]; then
	while IFS= read -r f; do
		report_unread "$f" "$(printf '    %s\n    %s\n' \
			"tracked under deliverable/ but matches no kind this checker knows" \
			"(*.c, *.h, Makefile, *.sh, *.md), so nothing here has looked inside it")"
	done < "$LISTS/other"
	while IFS= read -r f; do
		report_unread "$f" "$(printf '    %s\n    %s\n' \
			"tracked under generators/ but not a generators/exNN.sh, so nothing" \
			"here has looked inside it -- and everything under generators/ is an answer")"
	done < "$LISTS/gen_other"
	while IFS= read -r f; do
		report_unread "$f" "$(printf '    %s\n    %s\n    %s\n' \
			"tracked in a course or project folder but under none of its project's" \
			"deliverable/, generators/ or tests/, and no file a project keeps beside" \
			"them: AGENTS.md §0 says there is no third place, and nothing reads it")"
	done < "$LISTS/outside"
fi

# A zone with no file of a kind this reads is no verdict, said after the
# files it does hold are named: it once stopped here first, so a zone of
# unread files alone said "no deliverables found" and named none of them.
if [ "$checked" -eq 0 ]; then
	echo "stub_check: no deliverables found${scope:+ under $scope}: no verdict" >&2
	[ "$unread" -eq 0 ] || echo "            ($unread file(s) above were never read)" >&2
	exit 2
fi

echo
if [ "$bad" -eq 0 ] && [ "$unread" -eq 0 ] && [ "$refused" -eq 0 ]; then
	echo "stub_check: OK — all $checked deliverable(s) are stubs."
	exit 0
fi
if [ "$refused" -gt 0 ]; then
	echo "stub_check: REFUSED — $refused of $checked deliverable(s) above hold no answer and are"
	echo "            no stub either: each is empty, or has no 42 header that can be"
	echo "            re-stamped. Do what each one says, and run this again."
	[ "$bad" -gt 0 ] || [ "$unread" -gt 0 ] || exit 2
fi
# No body found, and files never read: no verdict (2), never 1, which the
# template build reads as an answer to stub. Otherwise one FAIL stem, its
# words chosen by what the files hold -- code it found, files it could not
# tell (untold), or both -- then what that means, in a line or two, the
# last of them joined by "; and" to the line on unread files below.
if [ "$bad" -eq 0 ]; then
	echo "stub_check: NO VERDICT — none of $checked deliverable(s) holds an implementation, but"
else
	_held="still contain an implementation."
	_first=""
	_last="Every line above them is code that would ship in the template"
	if [ "$untold" -eq "$bad" ]; then
		# Files this reader could not tell, and nothing it found: no "code".
		_held="may contain an implementation."
		_first="This reader could not tell what the recipes above do, so each file"
		_last="counts as written"
	elif [ "$untold" -gt 0 ]; then
		_held="still contain an implementation, or may:"
		_first="$untold of them could not be told apart from code by this reader, and"
		_last="every line above the rest is code that would ship in the template"
	fi
	echo "stub_check: FAIL — $bad of $checked deliverable(s) $_held"
	[ -z "$_first" ] || echo "            $_first"
	echo "            $_last; and"
fi
if [ "$unread" -gt 0 ]; then
	echo "            $unread file(s) above were never read: a kind this checker cannot open,"
	echo "            or a place no check reads. Each may be data rather than code, but"
	echo "            nothing here can vouch for it -- move it where it belongs, or delete it."
else
	echo "            no file was left unread."
fi
[ "$bad" -gt 0 ] || exit 2
exit 1
