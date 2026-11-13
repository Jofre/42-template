# --------------------------------------------------------------- exam_guide
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The study guide ships its Markdown with two renderings, and each rendering
# carries a stamp of what it was built from; --check, which the template build
# runs, refuses one whose stamp is not what the inputs give now. A stamp of the
# Markdown alone let a change to the build itself -- a template, a stylesheet,
# the post-processing, the script -- ship beside renderings nobody rebuilt.
# One toy guide per arm, stamped as a build stamps it (--stamp), then one file
# changed in it; no pandoc runs here.
eg_case() {  # eg_case NAME [COMMAND...]: a current toy, COMMAND run in it, --check
	_eg_d=$WORK/eg/$1
	shift
	_eg_g=$_eg_d/c-piscine/c-piscine-exam-prep
	mkdir -p "$_eg_d/tools" "$_eg_g/build" || return 2
	cp "$TOOLS/exam_guide.sh" "$_eg_d/tools/exam_guide.sh" || return 2
	printf '# A toy guide\n' > "$_eg_g/FINAL_EXAM_GUIDE.md"
	printf 'body { margin: 0; }\n' > "$_eg_g/build/print.css"
	printf '<html></html>\n' > "$_eg_g/build/page.html5"
	_eg_sum=$("$SH" "$_eg_d/tools/exam_guide.sh" --stamp) || return 2
	printf '<meta name="keywords" content="guide-source-sha256:%s">\n' \
		"$_eg_sum" > "$_eg_g/The C Piscine Final Exam Guide.html"
	printf '/Keywords (guide-source-sha256:%s)\n' "$_eg_sum" \
		> "$_eg_g/FINAL_EXAM_GUIDE.pdf"
	if [ "$#" -gt 0 ]; then
		(cd "$_eg_d" && "$@") || return 2
	fi
	"$SH" "$_eg_d/tools/exam_guide.sh" --check
}
EG=c-piscine/c-piscine-exam-prep
want_green "exam_guide: renderings of the inputs as they are pass" -- \
	eg_case fresh
want_red "exam_guide: ... not once the Markdown changes" -- \
	eg_case md sh -c "echo more >> $EG/FINAL_EXAM_GUIDE.md"
want_red "exam_guide: ... nor once a file in build/ changes" -- \
	eg_case css sh -c "echo 'p { margin: 0; }' >> $EG/build/print.css"
want_red "exam_guide: ... nor once a file is added to build/" -- \
	eg_case added sh -c ": > $EG/build/extra.py"
want_red "exam_guide: ... nor once the script changes" -- \
	eg_case script sh -c "echo '# edited' >> tools/exam_guide.sh"
want_red "exam_guide: ... nor once a rendering is missing" -- \
	eg_case gone rm "$EG/FINAL_EXAM_GUIDE.pdf"
want_green "exam_guide: a file outside the inputs does not count" -- \
	eg_case other sh -c "echo x > README.md"
want_green "exam_guide: ... nor does Python's bytecode in build/" -- \
	eg_case pyc sh -c "mkdir $EG/build/__pycache__ && : > $EG/build/__pycache__/x.pyc"


# The guide's two build scripts exit 1 for a fault they found and 2 for a
# check that broke, and tools/exam_guide.sh reads the two apart: 1 prints a
# FAIL that sends the reader to the layout rules. An exception Python did
# not catch ends with 1 too, so a missing print.css read as a layout rule
# that no longer holds. Copies under $WORK, run with -B, so that no
# bytecode reaches build/.
mkdir -p "$WORK/eg_py"
cp "$TOOLS/../$EG/build/guide_post.py" "$TOOLS/../$EG/build/render_check.py" "$WORK/eg_py/"
printf 'pre[class] { white-space: pre; }\n' > "$WORK/eg_py/good.css"
printf 'pre { white-space: pre-wrap; }\n' > "$WORK/eg_py/fault.css"
# A page template with all that print-template changes (below), and one
# with its web fonts link gone and its table of contents' summary reworded.
printf '<html><head>\n<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Toy">\n</head><body>\n<details class="toc"><summary>Table of contents</summary>\n<nav id="TOC" role="doc-toc">\n$table-of-contents$\n</nav></details>\n$body$\n</body></html>\n' \
	> "$WORK/eg_py/page.html5"
printf '<html><head>\n</head><body>\n<details class="toc"><summary>Contents</summary>\n<nav id="TOC" role="doc-toc">\n$table-of-contents$\n</nav></details>\n$body$\n</body></html>\n' \
	> "$WORK/eg_py/moved.html5"
eg_self() {  # eg_self PRINT_CSS PAGE -- guide_post.py self-check
	"$PYTHON" -I -B "$WORK/eg_py/guide_post.py" self-check "$@"
}
want_green "exam_guide: guide_post.py self-check passes a print.css that keeps its rules" -- \
	eg_self "$WORK/eg_py/good.css" "$WORK/eg_py/page.html5"
want_red "exam_guide: ...fails one that breaks a rule" -- \
	eg_self "$WORK/eg_py/fault.css" "$WORK/eg_py/page.html5"
want_red "exam_guide: ...and a page.html5 print-template cannot make the PDF's from" -- \
	eg_self "$WORK/eg_py/good.css" "$WORK/eg_py/moved.html5"
want_broken "exam_guide: ...and over a missing print.css is a broken check" \
	'guide_post.py:' -- eg_self "$WORK/eg_py/nope.css" "$WORK/eg_py/page.html5"
want_broken "exam_guide: guide_post.py with no arguments is a wrong call" \
	'guide_post.py:' -- "$PYTHON" -I -B "$WORK/eg_py/guide_post.py"
printf '<page width="595.0" height="842.0">\n<line xMin="1.0" yMin="1.0" xMax="9.0" yMax="9.0">\n<word xMin="1.0" yMin="1.0" xMax="9.0" yMax="9.0">word</word>\n</line>\n</page>\n' \
	> "$WORK/eg_py/words.html"
eg_render() {  # eg_render SOURCE -- render_check.py over the one word box above
	"$PYTHON" -I -B "$WORK/eg_py/render_check.py" "$1" < "$WORK/eg_py/words.html"
}
want_broken "exam_guide: render_check.py over a missing SOURCE.html is a broken check" \
	'render_check.py:' -- eg_render "$WORK/eg_py/nope.html"

# print-template makes the PDF's template from the page's by four edits:
# the web fonts link out, since the PDF is built offline; print.css in,
# before </head>; and the folded table of contents unfolded, since paper
# cannot click. None was checked to have applied, so a page.html5 that no
# longer had one of them -- a reworded summary, a changed link -- built a
# PDF that fetched web fonts or kept its contents folded, and nothing said
# so. It names each piece it found missing.
eg_tmpl() {  # eg_tmpl PAGE -- guide_post.py print-template over a toy print.css
	"$PYTHON" -I -B "$WORK/eg_py/guide_post.py" print-template "$1" "$WORK/eg_py/good.css"
}
want_green "exam_guide: print-template makes the PDF's template from the page's" -- \
	eg_tmpl "$WORK/eg_py/page.html5"
want_red "exam_guide: ...and fails over a page that lacks what it changes" -- \
	eg_tmpl "$WORK/eg_py/moved.html5"
want_out "exam_guide: ...naming the web fonts link" 'the web fonts link' -- \
	eg_tmpl "$WORK/eg_py/moved.html5"
want_out "exam_guide: ...and the folded table of contents" 'the folded table of contents' -- \
	eg_tmpl "$WORK/eg_py/moved.html5"
