#!/bin/sh
# stub_check.sh — prove that no deliverable in this tree holds an answer.
#
# Run it before publishing or sharing a copy of this workspace:
#
#     sh tools/stub_check.sh            # every deliverable in the repo
#     sh tools/stub_check.sh c-piscine-c-02   # one module, while working
#
# Exit 0 = every deliverable is a stub. Exit 1 = at least one still has a body,
# and each offending line is printed with its file and line number.
#
# NOTE TO WHOEVER EDITS THIS FILE: it SHIPS on the template, so it is bound by
# the same rule it enforces. Describe the shape of an answer; never paste one.
# Both blocks below used to quote real solutions verbatim — three c-01 bodies and
# three finished c-08 headers — which put four paste-ready answers into the one
# file whose entire job is keeping them out. Name the exercise and say what shape
# the mistake had; the reader can look at their own subject.
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
# turn in a header, all four were complete, and all four shipped in the published
# template with the checker reporting success.
#
# The same blind spot covered rush-00's rush.h (which carried the owner's
# s_shape / s_icons / s_position data model), c-09's Makefile and
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
# Three deliverable headers legitimately carry content. They are approved BY
# CONTENT, not by path, and the reason is worth stating because the first
# version of this list got it wrong: an allowlist of paths would have waved
# rush.h through whether or not anyone had actually reduced it, which is the
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
#   rush.h (rush-00)
#       Student-authored, but reduced by hand and reviewed. The approved content
#       is ft_putchar's prototype plus the note explaining why every rush0N.c
#       must keep its helpers static — that note is the pedagogy behind the
#       module's symbols layer, and it is a hint, not an answer. The owner's
#       s_shape / s_position / s_icons definitions and the RUSH0N icon macros
#       hash differently and are NOT approved.
#
#   includes/ft.h (c-09 ex01)
#       The uncomfortable one, approved with its cost written down rather than
#       waved through. Its five prototypes ARE what c-08 ex00 asks the student to
#       write, so shipping it does hand over a later reader another module's
#       exercise. It is approved anyway because stubbing it is worse, and the
#       difference was measured, not guessed: c_libft builds tests/ex01/
#       test_libft.c as a cc_binary against this header, so with the prototypes
#       gone the call sites are implicit declarations, and under -Werror
#       //c-piscine-c-09:ex01_output stops being a RED TEST and becomes a BUILD
#       ERROR. That takes `bazel test //...` down with "Build did NOT complete
#       successfully" on a fresh clone — the first command the README tells a
#       newcomer to run — instead of showing them the red test they are supposed
#       to turn green.
#
#       What is leaked is small and the subject leaks it anyway: c-08 ex00 NAMES
#       all five functions, and their signatures are ones the student wrote
#       themselves back in c-00 and c-01. What is broken by stubbing it is the
#       harness, for everyone, on day one. If c_libft ever compiles its test
#       through a runner instead of a cc_binary, revisit this — the red test
#       would then be reachable and this approval could go.
#
# To approve a new one, print its hash with:
#     sh tools/stub_check.sh --hash PATH
# and add the line here WITH the sentence saying why it is not an answer.
# WHY EACH ENTRY CARRIES A PATH AS WELL AS A HASH. The first version keyed on
# content alone, and that was wrong in the one way that matters: c-09's
# includes/ft.h and c-08 ex00's ft.h hold the SAME FIVE PROTOTYPES, byte for
# byte. Approving c-09's therefore approved c-08 ex00's too -- and c-08 ex00 is
# an exercise whose whole deliverable is that header, so the answer shipped and
# //c-piscine-c-08:ex00_output went GREEN on it. Identical bytes, opposite
# meanings, decided entirely by where the file sits.
#
# So both must match. The hash still stops "nobody reduced this file"; the path
# stops "these bytes are fine somewhere else". Format: <md5> <path-glob> <why>.
APPROVED_HEADERS='
0a8e57bbaf8ff567369c17f0c09bb93c c-piscine-c-12/deliverable/*/ft_list.h provided-by-42
911f5c687454688a48b3b70ac42a9543 c-piscine-c-13/deliverable/*/ft_btree.h provided-by-42
35693185426d45ffe2dc66cae797d277 c-piscine-rush-00/deliverable/ex00/rush.h reduced-and-reviewed
a8eea41d1f9755a2bab284696f70aa18 c-piscine-c-09/deliverable/ex01/includes/ft.h see-note-above
'

set -u

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
require awk basename cut dirname git grep md5sum mktemp rm

WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"

# The identity of a header, ignoring its 42 header block. Leading lines that are
# a whole C comment on one line (`/* ... */`, which is every line of the 11-line
# 42 block) are dropped until the first line of real content; from there on
# everything counts, so a comment placed further down cannot smuggle text past
# the hash. That is what lets one recorded hash approve all 18 copies of
# ft_list.h across two branches with four different names stamped in them.
body_hash() {
	awk '
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
	' "$1" | md5sum | cut -c1-32
}

# WHERE THE CONTENT COMES FROM, which is not the same question as where the
# file LIST comes from -- and getting them from two different places is what
# made the second half of the publish runbook a no-op.
#
# Repo mode lists files with `git ls-files`, i.e. from the INDEX, and then every
# checker below used to read that path off DISK. docs/publishing.md tells the
# maintainer to run this twice: once after stubbing, then "again, over the
# staged tree". Both runs read the same working-tree files, so the second one
# proved nothing the first had not. An answer sitting in the index behind a
# stubbed file on disk -- exactly what a forgotten or partial `git add -A`
# leaves, and `git commit` publishes the INDEX -- was reported as a stub.
#
# Reproduced in a scratch repo before this was written: index holding a
# recursive factorial, disk holding the (void)/return(0) stub, verdict
# "stub_check: OK — all 1 deliverable(s) are stubs.", exit 0, twice.
#
# So repo mode now reads each blob out of the index. --file mode still reads the
# path it was handed: it takes fixtures in a temp dir with no git at all, which
# is what lets the selftest drive this hermetically.
CONTENT_TMP=""
content_of() {
	if [ "$MODE" = file ]; then
		printf '%s' "$1"
		return 0
	fi
	git show ":$1" > "$CONTENT_TMP" 2>/dev/null || {
		echo "stub_check: '$1' is tracked but its staged content could not be read." >&2
		echo "            Refusing to score it. An unreadable file used to reach awk," >&2
		echo "            produce no output, and be counted as a verified stub." >&2
		exit 2
	}
	printf '%s' "$CONTENT_TMP"
}

MODE=repo
scope="${1:-}"
case "$scope" in
	--hash)
		[ -n "${2:-}" ] || { echo "stub_check: --hash needs a file" >&2; exit 2; }
		[ -f "$2" ] || { echo "stub_check: no such file: $2" >&2; exit 2; }
		printf '%s %s\n' "$(body_hash "$2")" "$(basename "$2")"
		exit 0 ;;
	--file) MODE="file"; shift ;;
	-*) echo "stub_check: unknown option: $scope" >&2; exit 2 ;;
esac

c_files=""; h_files=""; mk_files=""; sh_files=""

if [ "$MODE" = file ]; then
	# Check exactly the paths given, classified by name, with no git and no
	# workspace. This exists so //tools/tests:selftest can drive the checker on
	# known-bad fixtures in a temp dir: the repo mode below is built on
	# `git ls-files`, and a self-test that needs a populated git repository is
	# one that will not run hermetically. Same split, and the same reason, as
	# every other runner the selftest reaches.
	[ $# -gt 0 ] || { echo "stub_check: --file needs at least one path" >&2; exit 2; }
	for f in "$@"; do
		[ -f "$f" ] || { echo "stub_check: no such file: $f" >&2; exit 2; }
		case "$f" in
			*.c)       c_files="$c_files $f" ;;
			*.h)       h_files="$h_files $f" ;;
			*Makefile) mk_files="$mk_files $f" ;;
			*.sh)      sh_files="$sh_files $f" ;;
			*) echo "stub_check: not a deliverable kind: $f" >&2; exit 2 ;;
		esac
	done
else
	# Only repo mode has a workspace to stand in; --file takes the caller's cwd
	# so that a path relative to it still resolves.
	cd "$WS" || exit 1
	_prefix="${scope:-*}"
	CONTENT_TMP=$(mktemp)
	trap 'rm -f "$CONTENT_TMP"' EXIT INT TERM

	# The four deliverable kinds, plus the shell modules' generators — which are
	# not under deliverable/ at all. For a shell module `deliverable/` is
	# generated and gitignored, so the generator IS the turn-in and the only
	# place its answer can live; leaving it out would exempt two whole modules.
	ls_deliverable() {
		# $1 = glob suffix, e.g. '*.c'
		git ls-files "$_prefix/deliverable/$1" "$_prefix/deliverable/*/$1" \
		             "$_prefix/deliverable/*/*/$1" 2>/dev/null
	}

	c_files=$(ls_deliverable '*.c')
	h_files=$(ls_deliverable '*.h')
	mk_files=$(ls_deliverable 'Makefile')
	sh_files=$(ls_deliverable '*.sh')
	gen_files=$(git ls-files "$_prefix/generators/ex*.sh" 2>/dev/null)
	sh_files=$(printf '%s\n%s\n' "$sh_files" "$gen_files" | grep -v '^$' || true)

	# ANYTHING ELSE tracked under deliverable/ is a file this checker cannot
	# vouch for, and the rule learned the hard way (HISTORY.md item 0, lesson 2) is
	# that a file kind which is not checked is a file kind that SHIPS. The four
	# globs above were once three, and c-08's finished headers went out under an
	# "OK — all 123 deliverable(s) are stubs" verdict because nothing listed
	# *.h. The same hole is open today one kind further along:
	# c-piscine-rush-02/deliverable/ex00/README.md is a group planning document
	# carrying a teammate's real 42 login and email plus the rush's
	# function-by-function decomposition. reset_headers.sh only walks *.c and
	# *.h so it is never re-stamped, make_template.sh excludes deliverable/ from
	# its staged identity grep, and --file mode exits 2 on it -- so nothing in
	# the publish path looks at it at all.
	#
	# Listing it is the whole fix. Whether it should be deleted, approved or
	# scrubbed is the maintainer's call; what must not happen is the checker
	# passing in silence over a file it never opened.
	other_files=$(git ls-files "$_prefix/deliverable/*" 2>/dev/null |
		grep -vE '\.(c|h|sh)$|/Makefile$' || true)
fi

all=$(printf '%s\n%s\n%s\n%s\n' "$c_files" "$h_files" "$mk_files" "$sh_files" | grep -v '^$' || true)
[ -n "$all" ] || { echo "stub_check: no deliverables found${scope:+ under $scope}" >&2; exit 1; }

bad=0
checked=0
report() { bad=$((bad + 1)); echo "  $1"; echo "$2"; }

# ---------------------------------------------------------------- C sources
#
# A body line is one that sits at depth >= 1 BEFORE this line opens or closes
# anything. That is what makes a wrapped signature safe: its continuation is
# still at depth 0. Outside function bodies everything is allowed — #include,
# prototypes, and the subject-provided type definitions that must survive.
for f in $c_files; do
	checked=$((checked + 1))
	src=$(content_of "$f")
	out=$(awk '
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
	' "$src")
	[ -n "$out" ] && report "$f" "$out"
done

# ---------------------------------------------------------------- C headers
#
# Everything below the 42 header comment must be an include guard. Comments are
# allowed only inside that leading block: a comment further down is how the
# owner's rush.h described its own struct layout, so "it is only a comment" is
# not a reason to let text through here.
for f in $h_files; do
	checked=$((checked + 1))
	src=$(content_of "$f")
	_h=$(body_hash "$src")
	_ok=0
	# Both the hash and the path must match the SAME entry.
	echo "$APPROVED_HEADERS" | while read -r _eh _ep _; do
		[ -n "$_eh" ] || continue
		[ "$_eh" = "$_h" ] || continue
		# shellcheck disable=SC2254
		case "$f" in $_ep) exit 9 ;; esac
	done || _ok=1
	[ "$_ok" -eq 0 ] || continue
	out=$(awk '
		{ line = $0; gsub(/^[ \t]+|[ \t]+$/, "", line) }
		line == "" { next }
		# The leading 42 header block, and nothing after it.
		!seen_code && line ~ /^\/\*/ { next }
		line ~ /^#[ \t]*ifndef[ \t]+[A-Za-z_][A-Za-z_0-9]*$/ { seen_code = 1; next }
		line ~ /^#[ \t]*define[ \t]+[A-Za-z_][A-Za-z_0-9]*$/ { seen_code = 1; next }
		line ~ /^#[ \t]*endif/                               { seen_code = 1; next }
		{ seen_code = 1; printf "    %d: %s\n", NR, $0 }
	' "$src")
	[ -n "$out" ] && report "$f" "$out"
done

# --------------------------------------------------------------- Makefiles
#
# A recipe line starts with a TAB. In a stub it may only announce what it would
# do; the moment it invokes a compiler or an archiver it is the answer, because
# for c-09 ex01, c-10 and rush-02 the Makefile IS the exercise.
for f in $mk_files; do
	checked=$((checked + 1))
	src=$(content_of "$f")
	out=$(awk '
		/^\t/ {
			r = $0
			sub(/^\t[ \t]*/, "", r)
			sub(/^[-@+]+/, "", r)
			if (r !~ /^echo[ \t]/ && r !~ /^true[ \t]*$/ && r !~ /^:[ \t]*$/)
				printf "    %d: %s\n", NR, $0
		}
	' "$src")
	[ -n "$out" ] && report "$f" "$out"
done

# ------------------------------------------------- shell deliverables + generators
#
# c-09's libft_creator.sh is a turned-in deliverable; the shell modules'
# generators/exNN.sh are the only place a shell answer lives at all. Both ship as
# a description and a no-op, so any command is an answer.
for f in $sh_files; do
	checked=$((checked + 1))
	src=$(content_of "$f")
	out=$(awk '
		{ line = $0; gsub(/^[ \t]+|[ \t]+$/, "", line) }
		line == "" { next }
		line ~ /^#/ { next }
		line ~ /^:[ \t]*$/ { next }
		line ~ /^true[ \t]*$/ { next }
		{ printf "    %d: %s\n", NR, $0 }
	' "$src")
	[ -n "$out" ] && report "$f" "$out"
done

# ------------------------------------------------- kinds nothing can classify
#
# Reported rather than skipped, because "this checker never opened the file" and
# "this file is a stub" are different statements and only one of them was being
# printed. --file mode has always exited 2 on an unknown kind; repo mode dropped
# it on the floor, which is the softer half of the same rule applied to the tree
# that actually gets published.
for f in ${other_files:-}; do
	report "$f" "$(printf '    %s\n    %s\n' \
		"tracked under deliverable/ but matches no kind this checker knows" \
		"(*.c, *.h, Makefile, *.sh), so nothing here has looked inside it")"
done

echo
if [ "$bad" -eq 0 ]; then
	echo "stub_check: OK — all $checked deliverable(s) are stubs."
	exit 0
fi
echo "stub_check: FAIL — $bad of $checked deliverable(s) still contain an implementation."
echo "            Every line above is code that would ship in the template."
exit 1
