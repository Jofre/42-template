#!/bin/sh
# exam_guide.sh — build the C Piscine study guide's HTML page and PDF from its Markdown.
#
# From the repo root, rebuild both:
#   sh tools/exam_guide.sh
# Are both built from the inputs as they are?
#   sh tools/exam_guide.sh --check
# The stamp the inputs give now:
#   sh tools/exam_guide.sh --stamp
#
# c-piscine/c-piscine-exam-prep/FINAL_EXAM_GUIDE.md is the source; the standalone
# page ("The C Piscine Final Exam Guide.html") and FINAL_EXAM_GUIDE.pdf are
# renderings of it, and they ship with it. A rendering nobody rebuilt says what
# the guide used to say, which is why the template build kept the PDF out for as
# long as it did. So each rendering carries a stamp of the inputs it was built
# from (a <meta> in the page, the Keywords of the PDF), and --check fails unless
# both carry the current one. The template build runs --check before every
# publish. The inputs are the Markdown, this script and every file in build/:
# a stamp of the Markdown alone let a change to the build ship beside
# renderings nobody rebuilt.
#
# The page follows the one first published: page.html5 is its <head> and
# styles (less a rule nothing on the page matched), and the table of contents
# is pandoc's (the Markdown's own contents section is for readers of the .md
# and is left out). Both renderings move each self-check answer from under its
# question to the end of its chapter, where a reader meets it after answering
# (build/guide_post.py). The PDF is the same text through build/print.css:
# DejaVu fonts, Noto Color Emoji by fallback, A4, every answer open. Before
# either file is written, a render gate reads the PDF's word boxes and lines
# (pdftotext -bbox-layout, build/render_check.py) and refuses a PDF where two
# words overlap, a word runs past the margin or a line break printed text
# twice: WeasyPrint reports none of them. Needs pandoc, WeasyPrint
# and pdftotext, which the tests never do: this is a maintainer's tool, run by
# hand after editing the guide. The committed files were built with pandoc
# 2.9.2.1, WeasyPrint 54.1 (the PDF's Producer) and pdftotext 22.02.0 from
# poppler-utils, all Ubuntu 22.04's packages; the devcontainer installs none.

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

# The stamp: the SHA-256 of the list of every input's SHA-256 and path -- the
# Markdown, this script, each file in build/ (a folder there, such as Python's
# __pycache__, is none) -- so that changing, adding or renaming any of them
# changes it. In bytewise order, which every machine lists alike.
stamp() {
	_list=$(
		LC_ALL=C
		export LC_ALL
		set -- "$MD" tools/exam_guide.sh
		for _f in "$B"/*; do
			[ -f "$_f" ] && set -- "$@" "$_f"
		done
		sha256sum "$@"
	) || { echo "exam_guide.sh: could not read the build's inputs (above)" >&2; exit 2; }
	SUM=$(printf '%s\n' "$_list" | sha256sum | cut -d' ' -f1)
}

if [ "${1:-}" = "--stamp" ]; then
	require cut sha256sum
	stamp
	echo "$SUM"
	exit 0
fi
if [ "${1:-}" = "--check" ]; then
	# Its own, shorter list: the template build runs --check, and that machine
	# needs neither pandoc nor WeasyPrint to compare two stamps.
	require cut grep sha256sum
	stamp
	bad=""
	stamped "$PAGE" || bad="$bad
    $PAGE"
	stamped "$PDF" || bad="$bad
    $PDF"
	if [ -n "$bad" ]; then
		echo "exam_guide.sh: FAIL — not built from $MD, build/ and this script as they are now:$bad"
		echo "  Rebuild them with: sh tools/exam_guide.sh"
		exit 1
	fi
	echo "exam_guide.sh: OK — the page and the PDF are built from the current guide and build."
	exit 0
fi
[ "$#" -eq 0 ] || { echo "exam_guide.sh: unknown argument: $1" >&2; exit 2; }
require awk cat cut dirname grep mktemp pandoc pdftotext python3 rm sha256sum weasyprint
stamp

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# The rules the render gate cannot see broken on the guide as it is -- a
# column never narrower than its longest word, a code block with a language
# never folded, each answer at the end of its chapter in both renderings --
# checked on planted input before every build (guide_post.py, self-check).
python3 "$B/guide_post.py" self-check "$B/print.css" > "$T/self.err"
case $? in
0) ;;
1)
	echo "exam_guide.sh: FAIL — a layout rule of the renderings no longer holds; nothing was built:" >&2
	cat "$T/self.err" >&2
	echo "  The rules are build/guide_post.py's widths() and answers_last(), and build/print.css." >&2
	exit 1
	;;
*)
	cat "$T/self.err" >&2
	exit 2
	;;
esac

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
pdftotext -bbox-layout "$T/guide.pdf" "$T/words.html" || exit 2
python3 "$B/render_check.py" "$T/print.html" < "$T/words.html" > "$T/render.err"
case $? in
0) ;;
1)
	echo "exam_guide.sh: FAIL — the PDF does not render cleanly; nothing was written:" >&2
	cat "$T/render.err" >&2
	echo "  build/render_check.py says what each fault usually means; the column" >&2
	echo "  widths come from build/guide_post.py, the rest from build/print.css." >&2
	exit 1
	;;
*)
	cat "$T/render.err" >&2
	exit 2
	;;
esac

cat "$T/page.html" > "$PAGE"
cat "$T/guide.pdf" > "$PDF"
stamped "$PAGE" && stamped "$PDF" || {
	echo "exam_guide.sh: built, but the stamp is not in the output -- check the templates" >&2
	exit 2
}
echo "exam_guide.sh: rebuilt '$PAGE' and $PDF from $MD"
