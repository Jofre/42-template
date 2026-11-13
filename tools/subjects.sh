#!/bin/sh
# subjects.sh — read and check tools/subjects.tsv, the registry of each
# project's subject: the version the harness was built from, its SHA-256, the
# project's intranet page and a direct link (the file's header says why each).
#
#   sh tools/subjects.sh check         every row well formed, one per project,
#                                      and each project a folder
#   sh tools/subjects.sh check --subjects
#                                      and each project's en.subject.pdf here,
#                                      its SHA-256 the row's: main's checkout,
#                                      which holds the subjects
#   sh tools/subjects.sh get PROJECT   that project's row without its first
#                                      column: version, sha256, page, pdf,
#                                      checked, tab-separated
#
# Run from the repository root. SUBJECTS names another registry (a selftest's).
# Exit 0: all is well, or the row is printed. Exit 1: a problem, each one on
# its own line of stderr, or no row for PROJECT. Exit 2: a usage error, or a
# tool it needs is missing.
#
# One reader for every consumer, so they cannot disagree about what a row
# means. --subjects is for the one checkout that holds the subjects the rows
# were written from: there, //tools:conventions runs it, and so does the
# template build before it strips them, so it never writes a page claiming a
# version whose bytes it did not have. Anywhere else, a project's
# en.subject.pdf is the student's own download, and another version than the
# row's is no error: the placeholder says that where they disagree, the
# student's subject decides. So plain `check` never opens one.
set -eu

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "subjects.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cut sed sha256sum

REG=${SUBJECTS:-tools/subjects.tsv}

usage() {
	echo "usage: subjects.sh check [--subjects] | subjects.sh get PROJECT" >&2
	exit 2
}
[ "$#" -ge 1 ] || usage

# The rows' shape, one problem a line: "FILE:LINE: why". Nothing here reads a
# file but the registry, so the hash check below gets only rows that parsed.
shape() {
	awk -F'\t' '
		function bad(why) { printf "%s:%d: %s\n", FILENAME, FNR, why; broken = 1 }
		function hexlen(s, n) { return length(s) == n && s !~ /[^0-9a-f]/ }
		/^#/ || !NF { next }
		{ n++ }
		NF != 6 { bad("has " NF " columns, not 6 (project version sha256 page pdf checked)"); next }
		$1 !~ /^[A-Za-z0-9_.\/-]+$/ || $1 ~ /\/$/ { bad("project \"" $1 "\" is not a folder path from the repo root") }
		$1 in seen { bad($1 " has a second row (the first is line " seen[$1] ")") }
		{ if (!($1 in seen)) seen[$1] = FNR }
		$2 !~ /^[0-9]+(\.[0-9]+)*$/ { bad($1 ": version \"" $2 "\" is not one as a cover prints it (13, 19.3)") }
		!hexlen($3, 64) { bad($1 ": sha256 \"" $3 "\" is not 64 lowercase hex digits") }
		$4 !~ /^https:\/\/projects\.intra\.42\.fr\/projects\/[A-Za-z0-9_-]+$/ {
			bad($1 ": page \"" $4 "\" is not https://projects.intra.42.fr/projects/<slug>")
		}
		$5 != "-" && $5 !~ /^https:\/\/cdn\.intra\.42\.fr\/pdf\/pdf\/[0-9]+\/en\.subject\.pdf$/ {
			bad($1 ": pdf \"" $5 "\" is neither - nor https://cdn.intra.42.fr/pdf/pdf/<id>/en.subject.pdf")
		}
		$6 !~ /^[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]$/ { bad($1 ": checked \"" $6 "\" is not a date, YYYY-MM-DD") }
		END {
			if (!n) { printf "%s: has no rows\n", FILENAME; broken = 1 }
			exit broken
		}' "$REG"
}

case "$1" in
	check)
		_hash=0
		case "$#:${2:-}" in
			1:) ;;
			2:--subjects) _hash=1 ;;
			*) usage ;;
		esac
		if [ ! -f "$REG" ]; then
			echo "subjects.sh: $REG is missing" >&2
			exit 1
		fi
		_out=$(shape) || { printf '%s\n' "$_out" | sed 's/^/subjects.sh: /' >&2; exit 1; }
		_bad=0
		# Read one row a line, the fields split by tab only: a field never
		# holds one, and a project path never holds a newline (shape, above).
		_rows=$(awk -F'\t' '!/^#/ && NF { print $1 "\t" $3 }' "$REG")
		_tab=$(printf '\t')
		while IFS=$_tab read -r _p _h; do
			[ -n "$_p" ] || continue
			if [ ! -d "$_p" ]; then
				echo "subjects.sh: $REG: $_p is not a folder of this checkout" >&2
				_bad=1
				continue
			fi
			[ "$_hash" = 1 ] || continue
			if [ ! -f "$_p/en.subject.pdf" ]; then
				echo "subjects.sh: $REG has a row for $_p, which has no en.subject.pdf to check it against" >&2
				_bad=1
				continue
			fi
			_got=$(sha256sum "$_p/en.subject.pdf" | cut -d' ' -f1)
			[ "$_got" = "$_h" ] && continue
			printf '%s\n' \
				"subjects.sh: $_p/en.subject.pdf is not the subject $REG records for it:" \
				"  its SHA-256 is $_got, the row's $_h." \
				"  A replaced subject changes its row: version as its cover prints it, this" \
				"  SHA-256, and pdf checked again against the new bytes, or - ." >&2
			_bad=1
		done <<EOF
$_rows
EOF
		exit "$_bad"
		;;
	get)
		[ "$#" -eq 2 ] || usage
		[ -f "$REG" ] || { echo "subjects.sh: $REG is missing" >&2; exit 1; }
		awk -F'\t' -v p="$2" '
			!/^#/ && NF && $1 == p { n++; row = $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 }
			END {
				if (n == 1) { print row; exit 0 }
				if (n) printf "subjects.sh: %s has %d rows in %s\n", p, n, FILENAME > "/dev/stderr"
				else printf "subjects.sh: %s has no row in %s\n", p, FILENAME > "/dev/stderr"
				exit 1
			}' "$REG"
		;;
	*) usage ;;
esac
