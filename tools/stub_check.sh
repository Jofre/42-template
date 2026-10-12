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
# Exit 0 = every deliverable is a stub. Exit 1 = at least one still has a body,
# and each offending line is printed with its file and line number. Exit 2 =
# a file it could not read, or an index git could not list: no verdict at all;
# or a file that holds no answer and is no stub either -- an empty one, or a
# .c or .h without its 42 header (NEITHER A STUB NOR AN ANSWER, below).
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
# WHY IT CHECKS FOUR KINDS AND NOT JUST .c
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
#
# HEADERS THAT ARE NOT ANSWERS
# ----------------------------
# A few deliverable headers legitimately carry content. They are approved BY
# CONTENT, not by path, and the reason is worth stating because the first
# version of this list got it wrong: an allowlist of paths would have waved a
# header through whether or not anyone had actually reduced it, which is the
# same blanket exemption this whole script exists to refuse. A hash cannot be
# satisfied by forgetting.
#
# Content-addressing also behaves correctly on its own: a fourth copy of
# ft_list.h appearing in some future module needs no edit here, while an EDITED
# copy fails its hash, falls through to the guards-only rule below, and is
# reported wherever it lives. The hash covers the file BELOW its 42 header, so
# re-stamping the identity does not disturb it.
#
#   ft_list.h (c-12, x18), ft_btree.h (c-13, x8)
#       42 PROVIDES these in the subject. Stubbing one would delete a definition
#       the student was GIVEN, not one they owe.
#
# NOT APPROVED ANY MORE: rush-00's rush.h. It shipped reduced to ft_putchar's
# prototype and a note on static helpers, but the subject's turn-in is three
# named files and no header, so the template ships none: the note lives in
# docs/rushes.md, where the symbols layer's rule is explained. A rush.h copied
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
# inside tools/header_check.sh (--shape libft), so the same stub became one red
# test, and ft.h was held to the guards-only rule like every other header. It
# is not a deliverable at all now: the subject's turn-in is the Makefile alone,
# and the grader's ft.h -- guards only, like Piscine Reloaded ex24's -- lives
# in tests/ex01/grader/, outside the zone. An approval is never the fix for a
# harness that cannot face a stub: fix the harness.
#
# To approve a new one, print its hash with:
#     sh tools/stub_check.sh --hash PATH
# and add the line here WITH the sentence saying why it is not an answer.
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

WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"

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
body_hash() {
	{ awk '
		# A leading line is dropped only if it is a comment AND NOTHING ELSE.
		# /^\/\*.*\*\/$/ was not that test. `.*` is greedy, so it also matched
		#     /* */ int g_answer = 42; /* */
		# whose middle is code, and dropped it. Reproduced before this was
		# written: that line and no line at all produced the SAME body hash, so
		# one approved entry approved the smuggled copy of the same header too.
		#
		# Find the FIRST `*/` and require it to end the line. Then a second
		# comment further along cannot vouch for whatever sits between them.
		function whole_comment(s,   i) {
			if (s !~ /^\/\*/) return 0
			i = index(s, "*/")
			return (i > 0 && substr(s, i + 2) ~ /^[ \t]*$/)
		}
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
judge_c() {
	awk '
		# Is this run of text, at the depth reached so far, something other than
		# an empty stub body? Depth and the reported line are passed in because
		# a POSIX awk function sees globals anyway and naming them here says
		# which ones it reads.
		function judge(seg, lineno, raw,   t) {
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
			sub(/\/\/.*$/, "", line)
		}
		incomment && line ~ /\*\// { sub(/^.*\*\//, "", line); incomment = 0 }
		incomment { next }
		line ~ /\/\*/ && line !~ /\*\// { sub(/\/\*.*$/, "", line); incomment = 1 }
		{ gsub(/\/\*[^*]*\*\//, "", line) }

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
				if (substr(rest, p, 1) == "{")
					depth++
				else if (--depth < 0)
					depth = 0
				rest = substr(rest, p + 1)
			}
		}
	' < "$2"
}

# ---------------------------------------------------------------- C headers
#
# Everything below the 42 header comment must be an include guard. Comments are
# allowed only inside that leading block: a comment further down can describe a
# whole struct layout, so "it is only a comment" is not a reason to let text
# through here.
judge_h() {
	_h=$(body_hash "$2") || return 2
	# The path the entry's glob is matched against, without the ./ a caller
	# may put before it: tools/answer_scan.sh hands every file over as
	# ./<path>, and an approved header spelled so was "an implementation".
	_hp=$1
	while :; do
		case "$_hp" in ./*) _hp=${_hp#./} ;; *) break ;; esac
	done
	_ok=0
	# Both the hash and the path must match the SAME entry.
	echo "$APPROVED_HEADERS" | while read -r _eh _ep _; do
		[ -n "$_eh" ] || continue
		[ "$_eh" = "$_h" ] || continue
		# shellcheck disable=SC2254
		case "$_hp" in $_ep) exit 9 ;; esac
	done || _ok=1
	[ "$_ok" -eq 0 ] || return 0
	awk '
		{ line = $0; gsub(/^[ \t]+|[ \t]+$/, "", line) }
		line == "" { next }
		# The leading 42 header block, and nothing after it.
		!seen_code && line ~ /^\/\*/ { next }
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
# for c-09 ex01, c-10 and rush-02 the Makefile IS the exercise.
judge_mk() {
	awk '
		/^\t/ {
			r = $0
			sub(/^\t[ \t]*/, "", r)
			sub(/^[-@+]+/, "", r)
			if (r !~ /^echo[ \t]/ && r !~ /^true[ \t]*$/ && r !~ /^:[ \t]*$/)
				printf "    %d: %s\n", NR, $0
		}
	' < "$2"
}

# ------------------------------------------------- shell deliverables + generators
#
# c-09's libft_creator.sh is a turned-in deliverable; the shell modules'
# generators/exNN.sh are the only place a shell answer lives at all. Both ship as
# a description and a no-op, so any command is an answer.
judge_sh() {
	awk '
		{ line = $0; gsub(/^[ \t]+|[ \t]+$/, "", line) }
		line == "" { next }
		line ~ /^#/ { next }
		line ~ /^:[ \t]*$/ { next }
		line ~ /^true[ \t]*$/ { next }
		{ printf "    %d: %s\n", NR, $0 }
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
# comment of 74 stars, on line 1 and on line 11.
has_header() {
	awk 'BEGIN { b = "/* "; for (i = 0; i < 74; i++) b = b "*"; b = b " */" }
		(NR == 1 || NR == 11) && $0 == b { n++ }
		END { exit (n == 2 ? 0 : 1) }' < "$1"
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
				has_header "$_src" || report_refused "$2" "$(printf '    %s\n    %s\n    %s' \
					"has no 42 header -- the 11-line block every .c and .h stub opens with," \
					"a border of 74 stars on its first and last line. The norm requires it," \
					"and nothing re-stamps a file without one.")" ;;
		esac
	fi
}

if [ "$MODE" = file ]; then
	# Check exactly the paths given, classified by name, with no git and no
	# workspace. This exists so //tools/tests:selftest can drive the checker on
	# known-bad fixtures in a temp dir: the repo mode below is built on
	# `git ls-files`, and a self-test that needs a populated git repository is
	# one that will not run hermetically. Same split, and the same reason, as
	# every other runner the selftest reaches. Every path is vetted before any
	# is scored, so a bad one in the list leaves no verdict on the others.
	[ $# -gt 0 ] || { echo "stub_check: --file needs at least one path" >&2; exit 2; }
	for f in "$@"; do
		[ -f "$f" ] || { echo "stub_check: no such file: $f" >&2; exit 2; }
		[ -r "$f" ] || { echo "stub_check: cannot read: $f" >&2; exit 2; }
		case "$f" in
			*.c | *.h | *Makefile | *.sh) ;;
			*) echo "stub_check: not a deliverable kind: $f" >&2; exit 2 ;;
		esac
	done
	for f in "$@"; do
		case "$f" in
			*.c)       score c "$f" ;;
			*.h)       score h "$f" ;;
			*Makefile) score mk "$f" ;;
			*.sh)      score sh "$f" ;;
		esac
	done
else
	# Only repo mode has a workspace to stand in; --file takes the caller's cwd
	# so that a path relative to it still resolves.
	cd "$WS" || exit 1
	_prefix="${scope:-*}"
	LISTS=$(mktemp -d)
	CONTENT_TMP="$LISTS/content"
	trap 'rm -rf "$LISTS"' EXIT
	trap 'exit 143' TERM
	trap 'exit 130' INT

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
	# answer lives (its deliverable/ is generated and gitignored). The four
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
	# taught stays.) So such a file is listed: whether it should be deleted,
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
			*) echo "$f" >> "$LISTS/other" ;;
		esac
	done < "$LISTS/zone"

	# And the rule §0 calls "no third place": a tracked file in a project folder
	# that is under none of deliverable/, generators/ or tests/ is somewhere this
	# checker never looks. Work written there -- c-piscine-reloaded's ex06/ at
	# the project root, say, where the Vogsphere repo has it -- would reach the
	# template unread. The allowlist is what legitimately lives beside a
	# project: its BUILD file and README, a group project's team file (rush-00's
	# team.bzl, which says what the team owes and holds no code), its subject
	# (or the template's placeholder), and the exam guide, which is a study
	# document rather than a project.
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
	grep -v '^$' "$LISTS/course" |
		grep -vE '/(deliverable|generators|tests)/' |
		grep -vE '(^|/)(BUILD\.bazel|README\.md|\.gitignore|team\.bzl)$' |
		grep -vE '\.pdf$|groups_subject\.txt$|subject-ammendment\.md$' |
		grep -vE '(^|/)c-piscine-exam-prep/' |
		{ if [ -n "$res_allow" ]; then grep -vxF -e "$res_allow"; else cat; fi; } \
		> "$LISTS/outside" || :
fi

[ "$checked" -gt 0 ] || { echo "stub_check: no deliverables found${scope:+ under $scope}" >&2; exit 1; }

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
			"(*.c, *.h, Makefile, *.sh), so nothing here has looked inside it")"
	done < "$LISTS/other"
	while IFS= read -r f; do
		report_unread "$f" "$(printf '    %s\n    %s\n' \
			"tracked under generators/ but not a generators/exNN.sh, so nothing" \
			"here has looked inside it -- and everything under generators/ is an answer")"
	done < "$LISTS/gen_other"
	while IFS= read -r f; do
		report_unread "$f" "$(printf '    %s\n    %s\n' \
			"tracked in a project folder but under none of deliverable/, generators/" \
			"or tests/: AGENTS.md §0 says there is no third place, and nothing reads it")"
	done < "$LISTS/outside"
fi

echo
if [ "$bad" -eq 0 ] && [ "$unread" -eq 0 ] && [ "$refused" -eq 0 ]; then
	echo "stub_check: OK — all $checked deliverable(s) are stubs."
	exit 0
fi
if [ "$refused" -gt 0 ]; then
	echo "stub_check: REFUSED — $refused of $checked deliverable(s) above hold no answer and are"
	echo "            no stub either: each is empty, or has no 42 header. Put back what it"
	echo "            lost, and run this again."
	[ "$bad" -gt 0 ] || [ "$unread" -gt 0 ] || exit 2
fi
if [ "$bad" -eq 0 ]; then
	echo "stub_check: FAIL — none of $checked deliverable(s) holds an implementation, and"
else
	echo "stub_check: FAIL — $bad of $checked deliverable(s) still contain an implementation."
	echo "            Every line above them is code that would ship in the template; and"
fi
if [ "$unread" -gt 0 ]; then
	echo "            $unread file(s) above were never read: a kind this checker cannot open,"
	echo "            or a place no check reads. Each may be data rather than code, but"
	echo "            nothing here can vouch for it -- move it where it belongs, or delete it."
else
	echo "            no file was left unread."
fi
exit 1
