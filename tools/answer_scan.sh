#!/bin/sh
# answer_scan.sh — find an exercise's answer anywhere OUTSIDE the zone.
#
#   sh tools/answer_scan.sh            # from the repo root, on a tree WITH answers
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
#          answers and are left out.
#
#   key    one answer has no source in the zone to copy: Shell 00 ex03's
#          turn-in is a public key, and ANY complete ed25519 public key passes
#          its check. So a whole one, anywhere outside the zone, is a hit on
#          its own -- env-audit.sh shipped exactly that as a "test vector".
#
# What it cannot see: an answer too short to be told from an idiom -- a one-line
# C body, a turn-in under six characters. Those are also the answers a copy
# gives away least.
#
# It prints WHERE (file:line, and which answer it matches), never the text, and
# exits 1 if anything matched, 0 if nothing did, 2 if it could not scan -- a
# tree with no answers in it (the template after stubbing) has nothing to look
# for, and saying "clean" there would be a scan that searched nothing.
#
# Maintainer-only files are not scanned: TODO.md and HISTORY.md never leave the
# private repo.

set -u

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "answer_scan.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat dirname find git grep mkdir mktemp rm sed sort tr wc

WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$WS" || exit 2

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# ------------------------------------------------------------------ answers
: > "$TMP/shell"   # normalized line <TAB> source
: > "$TMP/c"       # normalized 3-line run <TAB> source
: > "$TMP/defs"    # line with every blank removed <TAB> source

git ls-files -z -- '*/generators/ex*.sh' > "$TMP/gens.z"
git ls-files -z -- '*/deliverable/*.c' > "$TMP/cs.z"
git ls-files -z -- '*/deliverable/*.h' > "$TMP/hs.z"
git ls-files -z -- '*/deliverable/*Makefile' > "$TMP/mks.z"
[ -s "$TMP/gens.z" ] || [ -s "$TMP/cs.z" ] || [ -s "$TMP/hs.z" ] || [ -s "$TMP/mks.z" ] || {
	echo "answer_scan.sh: nothing tracked in the zone -- nothing to scan for" >&2
	exit 2
}

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

tr '\0' '\n' < "$TMP/gens.z" | while IFS= read -r g; do
	awk -v src="$g" "$NORM"'
		l ~ /^#/ || length(l) < 12 { next }
		{ print l "\t" src }' "$g" >> "$TMP/shell"
	# What the generator writes is the turn-in itself. Run it in a scratch
	# directory; a generator that needs a fixture it cannot find just produces
	# less, which is fine -- its own lines were read above.
	d="$TMP/run"; rm -rf "$d"; mkdir -p "$d"
	( cd "$d" && sh "$WS/$g" ) > /dev/null 2>&1 < /dev/null
	find "$d" -type f 2> /dev/null | while IFS= read -r f; do
		grep -Iq . "$f" 2> /dev/null || continue
		awk -v src="$g (its output)" "$NORM"'
			l ~ /^#/ || length(l) < 6 { next }
			{ print l "\t" src }' "$f" >> "$TMP/shell"
	done
done

tr '\0' '\n' < "$TMP/cs.z" | while IFS= read -r c; do
	awk -v src="$c" "$CKEEP"'
		# Body lines only: depth >= 1 before the line is read. Comments and
		# string contents do not move the depth.
		{
			raw = $0
			line = raw
			gsub(/"[^"]*"/, "\"\"", line)
			sub(/\/\/.*$/, "", line)
			gsub(/\/\*[^*]*\*\//, "", line)
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
		END { flush() }' "$c" >> "$TMP/c"
done
# Headers: a #define with parameters or a value. A bare one is an include
# guard, which every header has and which answers nothing.
tr '\0' '\n' < "$TMP/hs.z" | while IFS= read -r h; do
	awk -v src="$h" '
		/^[ \t]*#[ \t]*define[ \t]+[A-Za-z_][A-Za-z_0-9]*(\(|[ \t]+[^ \t])/ {
			l = $0; gsub(/[ \t]/, "", l)
			if (length(l) >= 12) print l "\t" src
		}' "$h" >> "$TMP/defs"
done
# Makefiles: recipe and assignment lines, not comments, not the stub's echo/:/
# true, not the assignments the subjects spell out for everyone alike.
tr '\0' '\n' < "$TMP/mks.z" | while IFS= read -r m; do
	awk -v src="$m" '
		{ l = $0; gsub(/[ \t]/, "", l) }
		l == "" || l ~ /^#/ { next }
		l ~ /^[-@+]*(echo|:|true)/ { next }
		l ~ /^(NAME|CC|CFLAGS|RM):?=/ { next }
		length(l) >= 12 { print l "\t" src }' "$m" >> "$TMP/defs"
done
sort -u -o "$TMP/shell" "$TMP/shell"
sort -u -o "$TMP/c" "$TMP/c"
sort -u -o "$TMP/defs" "$TMP/defs"
# A stubbed tree -- the public template, or a fresh clone of it -- has files in
# the zone but no answers in them: every generator is a skeleton and every body
# a stub. Reporting "none found" there would be a scan that searched nothing.
if [ ! -s "$TMP/shell" ] && [ ! -s "$TMP/c" ] && [ ! -s "$TMP/defs" ]; then
	echo "answer_scan.sh: the zone holds no answer to look for (a stubbed tree?)" >&2
	exit 2
fi

# ------------------------------------------------------------------ targets
git ls-files -z -- . \
	':(exclude)*/deliverable/*' ':(exclude)*/generators/*' \
	':(exclude)TODO.md' ':(exclude)HISTORY.md' > "$TMP/targets.z"

tr '\0' '\n' < "$TMP/targets.z" | while IFS= read -r t; do
	[ -f "$t" ] || continue
	grep -Iq . "$t" 2> /dev/null || continue
	awk -v shell="$TMP/shell" -v cruns="$TMP/c" -v defs="$TMP/defs" -v file="$t" "$CKEEP
		BEGIN {
			while ((getline e < shell) > 0) { i = index(e, \"\t\"); ns++; SK[ns] = substr(e, 1, i - 1); SV[ns] = substr(e, i + 1) }
			while ((getline e < cruns) > 0) { i = index(e, \"\t\"); C[substr(e, 1, i - 1)] = substr(e, i + 1) }
			while ((getline e < defs) > 0) { i = index(e, \"\t\"); nd++; DK[nd] = substr(e, 1, i - 1); DV[nd] = substr(e, i + 1) }
		}
		$NORM"'
		{
			for (j = 1; j <= ns; j++)
				if (index(l, SK[j])) { printf "%s:%d: an answer line from %s\n", file, NR, SV[j]; break }
			if (match($0, /ssh-ed25519[ \t]+AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+\/]+/) && RLENGTH >= 80)
				printf "%s:%d: a complete ed25519 public key, which passes Shell 00 ex03\n", file, NR
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
		}' "$t"
done > "$TMP/hits"

if [ -s "$TMP/hits" ]; then
	cat "$TMP/hits"
	echo
	echo "answer_scan: FAIL — $(wc -l < "$TMP/hits" | sed 's/ //g') place(s) outside deliverable/ and generators/ carry an answer."
	echo "             AGENTS.md §0: a check derives its reference by construction or from //oracle."
	exit 1
fi
echo "answer_scan: OK — $(wc -l < "$TMP/shell" | sed 's/ //g') shell answer lines, $(wc -l < "$TMP/c" | sed 's/ //g') C runs and $(wc -l < "$TMP/defs" | sed 's/ //g') header/Makefile lines looked for; none outside the zone."
exit 0
