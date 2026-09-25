#!/bin/sh
# placeholder_pdf.sh — write a one-page PDF that says "this is not the subject".
#
#   sh tools/placeholder_pdf.sh OUT.pdf PROJECT
#
# 42's subject PDFs are 42's: the public template does not carry them, and they
# change between versions, so each student downloads the one they are actually
# graded against. What the template carries instead, in every folder that had a
# subject, is SUBJECT-PLACEHOLDER.pdf, written by this script when the template
# is built: a real, openable PDF whose whole content is an instruction. A student
# who opens it learns what to fetch and where to put it, and an agent listing the
# folder sees a file NAMED as a placeholder rather than a missing subject, or a
# subject it might claim to have read.
#
# It is deliberately not named like the subject. The template ignores *.pdf so a
# student's own copy of 42's document never reaches their commits; a placeholder
# tracked under the subject's name would turn their copy into a MODIFICATION of
# a tracked file, which `git add -A` commits whatever the ignore rule says.
#
# Written by hand, byte by byte, because the page is five objects of fixed text
# and the only thing a PDF reader is strict about is the cross-reference table:
# every object's byte offset, ten digits, twenty bytes a line. Those offsets are
# MEASURED from the file as it is written (wc -c), never computed from string
# lengths, so a change to the wording cannot silently misalign them.
set -eu

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "placeholder_pdf.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require wc tr sed

[ "$#" -eq 2 ] || { echo "usage: placeholder_pdf.sh OUT.pdf PROJECT" >&2; exit 2; }
OUT=$1
PROJECT=$2
case "$PROJECT" in
	*[!A-Za-z0-9_.-]*|"") echo "placeholder_pdf.sh: project name must be [A-Za-z0-9_.-]: '$PROJECT'" >&2; exit 2 ;;
esac

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
1. Download the subject of $PROJECT from the 42 intranet.
2. Save it in this folder as en.subject.pdf - or es.subject.pdf, etc.
3. Delete this file.
|
The *.pdf rule in .gitignore keeps your copy out of your commits,
so a fork of this repository cannot republish it by accident."

size() { wc -c < "$OUT" | tr -d ' '; }

: > "$OUT"
printf '%%PDF-1.4\n' >> "$OUT"
o1=$(size); printf '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n' >> "$OUT"
o2=$(size); printf '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n' >> "$OUT"
o3=$(size); printf '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n' >> "$OUT"

# The content stream: first line large, the rest at body size, 18pt apart.
stream=$(printf '%s\n' "$LINES" | sed '
	s/^|$//
	1s/.*/BT \/F1 18 Tf 56 770 Td (&) Tj \/F1 11 Tf ET/
	2,$s/.*/BT \/F1 11 Tf 56 LINE Td (&) Tj ET/' | {
	y=770; n=0
	while IFS= read -r l; do
		n=$((n + 1))
		[ "$n" -gt 1 ] && y=$((y - 18))
		printf '%s\n' "$l" | sed "s/LINE/$y/"
	done
})
len=$(printf '%s' "$stream" | wc -c | tr -d ' ')
o4=$(size); printf '4 0 obj\n<< /Length %d >>\nstream\n%s\nendstream\nendobj\n' "$len" "$stream" >> "$OUT"
o5=$(size); printf '5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n' >> "$OUT"
ox=$(size)
{
	printf 'xref\n0 6\n0000000000 65535 f \n'
	for o in "$o1" "$o2" "$o3" "$o4" "$o5"; do printf '%010d 00000 n \n' "$o"; done
	printf 'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' "$ox"
} >> "$OUT"
