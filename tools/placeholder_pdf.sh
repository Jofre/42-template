#!/bin/sh
# placeholder_pdf.sh — write a one-page PDF that says "this is not the subject".
#
#   sh tools/placeholder_pdf.sh OUT.pdf PROJECT VERSION SHA256 PAGE PDF [EXTRA]
#
# VERSION, SHA256, PAGE and PDF are the project's row of tools/subjects.tsv:
# the version of the English subject the harness was built from, that file's
# SHA-256, the project's page on the intranet and a direct link to that
# version, or - where none is known. Every line of the page that is a URL is
# also a link a PDF reader opens with a click.
#
# EXTRA is optional text for one project, printed after the steps: more of
# 42's material that project needs, and the exact path it goes to (shell-00's
# resources.tar.gz). One page line per line of EXTRA, a line reading "|" is a
# blank one, and it is plain ASCII with no ( ) or \, like the rest of the page.
#
# 42's subject PDFs are 42's: the public template does not carry them, and they
# change between versions, so each student downloads the one they are actually
# graded against. What the template carries instead, in every folder that had a
# subject, is SUBJECT-PLACEHOLDER.pdf, written by this script when the template
# is built: a real, openable PDF whose whole content is an instruction. A student
# who opens it learns what to fetch, from where, and where to put it, and which
# version the harness was written against; an agent listing the folder sees a
# file NAMED as a placeholder rather than a missing subject, or a subject it
# might claim to have read.
#
# It is deliberately not named like the subject. The template ignores *.pdf so a
# student's own copy of 42's document never reaches their commits; a placeholder
# tracked under the subject's name would turn their copy into a MODIFICATION of
# a tracked file, which `git add -A` commits whatever the ignore rule says.
#
# Written by hand, byte by byte, because the page is a handful of objects of
# fixed text and the only thing a PDF reader is strict about is the
# cross-reference table: every object's byte offset, ten digits, twenty bytes a
# line. Those offsets are MEASURED from the file as it is written (wc -c), never
# computed from string lengths, so a change to the wording cannot silently
# misalign them. The objects: 1 the catalog, 2 the page tree, 3 the page, 4 its
# text, 5 the font, and from 6 one link annotation per URL line.
set -eu

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "placeholder_pdf.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require wc tr awk

[ "$#" -eq 6 ] || [ "$#" -eq 7 ] ||
	{ echo "usage: placeholder_pdf.sh OUT.pdf PROJECT VERSION SHA256 PAGE PDF [EXTRA]" >&2; exit 2; }
OUT=$1
PROJECT=$2
VERSION=$3
SHA256=$4
PAGE=$5
PDF=$6
EXTRA=${7:-}
case "$PROJECT" in
	*[!A-Za-z0-9_.-]*|"") echo "placeholder_pdf.sh: project name must be [A-Za-z0-9_.-]: '$PROJECT'" >&2; exit 2 ;;
esac
# The row's fields are printed as they are, so each is held to what its column
# allows (tools/subjects.sh checks the same of the registry): none can hold a
# ( ) or \, the three characters a PDF string would need escaped.
case "$VERSION" in
	*[!0-9.]*|""|.*|*.) echo "placeholder_pdf.sh: version must be digits and dots: '$VERSION'" >&2; exit 2 ;;
esac
case "$SHA256" in
	*[!0-9a-f]*) echo "placeholder_pdf.sh: sha256 must be 64 lowercase hex digits: '$SHA256'" >&2; exit 2 ;;
esac
[ "${#SHA256}" -eq 64 ] ||
	{ echo "placeholder_pdf.sh: sha256 must be 64 lowercase hex digits: '$SHA256'" >&2; exit 2; }
case "$PAGE" in
	https://*) ;;
	*) echo "placeholder_pdf.sh: page must be an https:// URL: '$PAGE'" >&2; exit 2 ;;
esac
case "$PDF" in
	-|https://*) ;;
	*) echo "placeholder_pdf.sh: pdf must be an https:// URL or -: '$PDF'" >&2; exit 2 ;;
esac
for _u in "$PAGE" "$PDF"; do
	case "$_u" in
		*[!A-Za-z0-9:/._~%?=\&+-]*) echo "placeholder_pdf.sh: a URL holds a character the page cannot print: '$_u'" >&2; exit 2 ;;
	esac
done
# The same three characters, and anything outside printable ASCII, which the
# page's Helvetica would draw as something else.
case "$EXTRA" in
	*[\(\)\\]*) echo "placeholder_pdf.sh: the extra text cannot hold ( ) or \\" >&2; exit 2 ;;
esac
if [ -n "$(printf '%s' "$EXTRA" | LC_ALL=C tr -d '\n -~')" ]; then
	echo "placeholder_pdf.sh: the extra text must be printable ASCII" >&2
	exit 2
fi

# The page text, one PDF string per line. Plain ASCII, and no ( ) or \ -- those
# are the three characters a PDF string would need escaped.
LINES="PLACEHOLDER - this is NOT the subject.
|
Project: $PROJECT
|
The subject PDF is 42's document, so this repository does not ship it:
it is not ours to republish, and 42 revises subjects between versions.
Use the exact version you are graded against.
|
This harness was built from version $VERSION of the English subject,
the file whose SHA-256 is
$SHA256
|
The project's page on the 42 intranet - log in first. It offers the
subject in the language your 42 profile is set to:
$PAGE"
[ "$PDF" = - ] || LINES="$LINES
|
That version of the English subject, to download directly:
$PDF"
LINES="$LINES
|
1. Download the subject of $PROJECT from the intranet.
2. Save it in this folder as en.subject.pdf - or es.subject.pdf, etc.
3. Check which version you have: for the English file, run
   sha256sum en.subject.pdf  here, and the hash above means it is the
   one this harness was built from. A translation numbers its versions
   on its own, so only the English file can be compared. Where your
   subject and the harness disagree, your subject decides.
4. Delete this file.
|
The *.pdf rule in .gitignore keeps your copy out of your commits,
so a copy of this repository cannot republish it by accident."
[ -z "$EXTRA" ] || LINES="$LINES
|
$EXTRA"

size() { wc -c < "$OUT" | tr -d ' '; }

# Each page line's place: the first large at y 770, the rest at body size,
# 18pt apart. One reading of the lines for the text and the links alike, so a
# link sits on the line it opens.
placed=$(printf '%s\n' "$LINES" | awk '
	{ y = NR == 1 ? 770 : 770 - 18 * (NR - 1); t = $0; if (t == "|") t = ""; print y "\t" t }')

# The links: one per line that is a URL, its box the line's width at 11pt
# Helvetica (an average glyph of a URL is under 0.6 em, 6.6pt) and its height.
links=$(printf '%s\n' "$placed" | awk -F'\t' '
	$2 ~ /^https:\/\// { printf "%d %d %d %d\t%s\n", 56, $1 - 3, 56 + int(length($2) * 6.6 + 0.5), $1 + 10, $2 }')
n_links=0
[ -z "$links" ] || n_links=$(printf '%s\n' "$links" | wc -l | tr -d ' ')
annots=""
_i=0
while [ "$_i" -lt "$n_links" ]; do
	annots="$annots${annots:+ }$((6 + _i)) 0 R"
	_i=$((_i + 1))
done

: > "$OUT"
printf '%%PDF-1.4\n' >> "$OUT"
o1=$(size); printf '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n' >> "$OUT"
o2=$(size); printf '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n' >> "$OUT"
o3=$(size); printf '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >>%s >>\nendobj\n' \
	"${annots:+ /Annots [$annots]}" >> "$OUT"

# The content stream: first line large, the rest at body size.
stream=$(printf '%s\n' "$placed" | awk -F'\t' '
	NR == 1 { printf "BT /F1 18 Tf 56 %d Td (%s) Tj /F1 11 Tf ET\n", $1, $2; next }
	{ printf "BT /F1 11 Tf 56 %d Td (%s) Tj ET\n", $1, $2 }')
len=$(printf '%s' "$stream" | wc -c | tr -d ' ')
o4=$(size); printf '4 0 obj\n<< /Length %d >>\nstream\n%s\nendstream\nendobj\n' "$len" "$stream" >> "$OUT"
o5=$(size); printf '5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n' >> "$OUT"
offs="$o1 $o2 $o3 $o4 $o5"
_i=6
_tab=$(printf '\t')
while IFS=$_tab read -r _rect _uri; do
	[ -n "$_uri" ] || continue
	_o=$(size)
	printf '%d 0 obj\n<< /Type /Annot /Subtype /Link /Rect [%s] /Border [0 0 0] /A << /S /URI /URI (%s) >> >>\nendobj\n' \
		"$_i" "$_rect" "$_uri" >> "$OUT"
	offs="$offs $_o"
	_i=$((_i + 1))
done <<EOF
$links
EOF
ox=$(size)
{
	printf 'xref\n0 %d\n0000000000 65535 f \n' "$_i"
	for o in $offs; do printf '%010d 00000 n \n' "$o"; done
	printf 'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' "$_i" "$ox"
} >> "$OUT"
