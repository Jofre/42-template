#!/bin/sh
# exam_guide.sh — build the final-exam guide's HTML page and PDF from its Markdown.
#
#   sh tools/exam_guide.sh            # from the repo root: rebuild both
#   sh tools/exam_guide.sh --check    # are both built from the Markdown as it is?
#
# c-piscine/c-piscine-exam-prep/FINAL_EXAM_GUIDE.md is the source; the standalone
# page ("The C Piscine Final Exam Guide.html") and FINAL_EXAM_GUIDE.pdf are
# renderings of it, and they ship with it. A rendering nobody rebuilt says what
# the guide used to say, which is why the template build kept the PDF out for as
# long as it did. So each rendering carries the SHA-256 of the Markdown it was
# built from (a <meta> in the page, the Keywords of the PDF), and --check fails
# unless both carry the current one. The template build runs --check before
# every publish.
#
# The page reproduces the one first published: page.html5 is its <head> and
# styles, and the table of contents is pandoc's (the Markdown's own contents
# section is for readers of the .md and is left out). The PDF is the same text
# through build/print.css: DejaVu fonts, Noto Color Emoji by fallback, A4, every
# answer open. Needs pandoc and WeasyPrint, which the tests never do: this is a
# maintainer's tool, run by hand after editing the guide.

set -u

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "exam_guide.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}

WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$WS" || exit 2
D=c-piscine/c-piscine-exam-prep
MD=$D/FINAL_EXAM_GUIDE.md
PAGE="$D/The C Piscine Final Exam Guide.html"
PDF=$D/FINAL_EXAM_GUIDE.pdf
B=$D/build
[ -f "$MD" ] || { echo "exam_guide.sh: $MD not found" >&2; exit 2; }

# A PDF keeps its Keywords as a plain string in its info dictionary, so a byte
# search finds the stamp without a PDF library.
stamped() { [ -f "$1" ] && grep -aq "guide-source-sha256:$SUM" "$1"; }

if [ "${1:-}" = "--check" ]; then
	# Its own, shorter list: the template build runs --check, and that machine
	# needs neither pandoc nor WeasyPrint to compare two stamps.
	require cut grep sha256sum
	SUM=$(sha256sum "$MD" | cut -d' ' -f1)
	bad=""
	stamped "$PAGE" || bad="$bad
    $PAGE"
	stamped "$PDF" || bad="$bad
    $PDF"
	if [ -n "$bad" ]; then
		echo "exam_guide.sh: FAIL — not built from $MD as it is now:$bad"
		echo "  Rebuild them with: sh tools/exam_guide.sh"
		exit 1
	fi
	echo "exam_guide.sh: OK — the page and the PDF are built from the current guide."
	exit 0
fi
[ "$#" -eq 0 ] || { echo "exam_guide.sh: unknown argument: $1" >&2; exit 2; }
require awk cat cut dirname grep mktemp pandoc python3 rm sha256sum weasyprint
SUM=$(sha256sum "$MD" | cut -d' ' -f1)

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM

# The Markdown's own table of contents: from its heading to the next part.
awk '/^### Table of contents$/ { skip = 1; next } skip && /^## / { skip = 0 } !skip' \
	"$MD" > "$T/body.md"

# gfm identifiers keep the anchors the page has always had; -smart keeps
# straight quotes; a wide --columns stops pandoc sizing table columns by line.
render() {
	pandoc "$T/body.md" -f markdown+gfm_auto_identifiers-smart -t html5 -s \
		--toc --toc-depth=3 --columns=100000 \
		--metadata title="The C Piscine Final Exam Guide" \
		--variable source-sha256="$SUM" --template="$1" -o "$2"
}

render "$B/page.html5" "$T/page.html" || exit 2
python3 "$B/guide_post.py" screen "$T/page.html" || exit 2

python3 "$B/guide_post.py" print-template "$B/page.html5" "$B/print.css" \
	> "$T/print.html5" || exit 2
render "$T/print.html5" "$T/print.html" || exit 2
python3 "$B/guide_post.py" print "$T/print.html" || exit 2
weasyprint "$T/print.html" "$T/guide.pdf" 2> "$T/weasy.err" || {
	cat "$T/weasy.err" >&2
	exit 2
}

cat "$T/page.html" > "$PAGE"
cat "$T/guide.pdf" > "$PDF"
stamped "$PAGE" && stamped "$PDF" || {
	echo "exam_guide.sh: built, but the stamp is not in the output -- check the templates" >&2
	exit 2
}
echo "exam_guide.sh: rebuilt '$PAGE' and $PDF from $MD"
