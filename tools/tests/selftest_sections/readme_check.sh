# ------------------------------------------------------------------ readme_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The README a subject asks for (c_readme). Basic assumes no language, so a
# README in a language the call site never named is green there; --wording
# reads the words the call site gives, and nothing else. Every README below is
# invented, and so are the toy subject's sentences and words (rm_q, rm_w).
mkdir -p "$WORK/rm/p"
_rm_runner=$(cd "$TOOLS" && pwd)/readme_check.sh
printf 'p/README.md\n' > "$WORK/rm/found.list"
printf '%s\n' "$WORK/rm/p/README.md" > "$WORK/rm/found_abs.list"
: > "$WORK/rm/none.list"
{
	printf 'file\tToy, p.1: "A README.md file must be at the root."\n'
	printf 'first-line\tToy, p.1: "The first line must be italicized and read: Made by <login>."\n'
	printf 'sections\tToy, p.1: "A Description section, a Usage section, a Sources section."\n'
} > "$WORK/rm/q.basic"
cp "$WORK/rm/q.basic" "$WORK/rm/q.wording"
{
	printf 'ai\tToy, p.1: "Sources, with how AI was used."\n'
	printf 'language\tToy, p.1: "Write it in English or in Spanish."\n'
} >> "$WORK/rm/q.wording"
# rm_put TEXT -- the README is TEXT, printf's %b read.
rm_put() { printf '%b' "$1" > "$WORK/rm/p/README.md"; }
rm_b() { (cd "$WORK/rm" && "$SH" "$_rm_runner" --path p/README.md --found-list found.list \
	--quotes q.basic --min-sections 3 "$@"); }
rm_w() { (cd "$WORK/rm" && "$SH" "$_rm_runner" --wording --path p/README.md --found-list found.list \
	--quotes q.wording --sentence 'Made by' --sentence 'Hecho por' \
	--section 'Description|Descripción' --section 'Usage|Uso' --section 'Sources|Fuentes' \
	--ai-section 'Sources|Fuentes' --ai-word AI --ai-word IA "$@"); }
_rm_en='*Made by jdoe, asmith.*\n\n# Description\nA toy.\n\n## Usage\nmake toy\n\n## Sources\nman 3 toy. AI was used for nothing.\n'
_rm_es='_Hecho por jdoe._\n\n# Descripción\nUn juguete.\n\n## Uso\nmake toy\n\n## Fuentes\nman 3 toy. No se usó IA.\n'
_rm_ca='*Fet per jdoe.*\n\n# Descripció\nUna joguina.\n\nÚs\n--\nmake toy\n\n## Fonts\nman 3 toy. No hi ha IA.\n'

rm_put "$_rm_ca"
want_green "readme: basic is green on a README in another language" -- rm_b
want_red   "readme: ...and --wording is red on its sentence" -- rm_w
want_out   "readme: ...which it says it does not accept" 'does not begin with a sentence this check accepts' -- rm_w
want_out   "readme: ...naming the reading as the harness's" "this harness's reading, never the subject's" -- rm_w
: > "$WORK/rm/p/README.md"
want_red   "readme: an empty README is red" -- rm_b
want_out   "readme: ...quoting the call site's sentence" 'A README.md file must be at the root.' -- rm_b
want_out   "readme: ...as a fact and a question" 'What do' -- rm_b
want_out   "readme: ...still to be written" 'is still to be written.' -- rm_b
rm_put ' \n\t\n'
want_red   "readme: blank lines alone are empty too" -- rm_b
# The stub (stub_check's md kind) is blank lines and comments: it shows
# nothing, and says so, rather than that its first line is no italics.
rm_put '<!--\n  Say what this toy is.\n-->\n\n<!-- and how to build it -->\n'
want_red   "readme: a README of comments alone (the stub) is red" -- rm_b
want_out   "readme: ...showing nothing" 'shows nothing: it holds only blank lines, HTML' -- rm_b
want_out   "readme: ...and still to be written" 'is still to be written.' -- rm_b
want_red   "readme: a missing README is red" -- \
	sh -c 'cd "$1" && "$2" "$3" --path p/README.md --found-list none.list --quotes q.basic --min-sections 3' _ \
	"$WORK/rm" "$SH" "$_rm_runner"
want_out   "readme: ...saying where it was looked for" 'p/README.md is missing' -- \
	sh -c 'cd "$1" && "$2" "$3" --path p/README.md --found-list none.list --quotes q.basic --min-sections 3' _ \
	"$WORK/rm" "$SH" "$_rm_runner"
rm_put '**Made by jdoe.**\n# Description\n## Usage\n## Sources\n'
want_red   "readme: a first line in bold alone is red" -- rm_b
want_out   "readme: ...and called bold, not italics" 'bold is not' -- rm_b
want_out   "readme: ...with the line shown" 'README.md:1: **Made by jdoe.**' -- rm_b
want_broken_none "readme: ...and no key, where it shows no mark" '(byte for byte' -- rm_b
rm_put '**Made by\tjdoe $x.**\n# Description\n## Usage\n## Sources\n'
want_out   "readme: a line shown with a tab and a dollar has a key to both" \
	'(byte for byte: \t a tab, and \x24 a dollar)' -- rm_b
# A byte-order mark before line 1 is dropped from the reading, as GitHub
# drops it, so it plays no part in a verdict: the line a failure shows is
# the line that was judged, and shows no \xef\xbb\xbf a reader takes for
# the cause.
rm_put '\0357\0273\0277**Made by jdoe.**\n# Description\n## Usage\n## Sources\n'
want_red   "readme: a first line in bold behind a BOM is red too" -- rm_b
want_out   "readme: ...with the line shown as it was judged" 'README.md:1: **Made by jdoe.**' -- rm_b
rm_put '*Made by* jdoe.\n# Description\n## Usage\n## Sources\n'
want_red   "readme: a span that ends before the line does is red" -- rm_b
rm_put '*Made by* *jdoe.*\n# Description\n## Usage\n## Sources\n'
want_red   "readme: two spans with a blank between are red" -- rm_b
rm_put '* Made by jdoe.*\n# Description\n## Usage\n## Sources\n'
want_red   "readme: a list item is no span in italics" -- rm_b
# A heading whose text is in italics: italics on one reading, a heading on
# another, so green at basic, and red under --wording, which reads it as a
# heading. As the line asked for, it is no section heading.
rm_put '# *Made by jdoe.*\n# Description\n## Usage\n## Sources\nAI\n'
want_green "readme: a heading in italics is green at basic" -- rm_b
want_red   "readme: ...and red under --wording" -- rm_w
want_out   "readme: ...which reads no heading as the line" 'never as a heading, even one whose text is in italics' -- rm_w
want_out   "readme: ...as this harness's reading" "this harness's reading, never the subject's" -- rm_w
rm_put '# *Made by jdoe.*\n# Description\n## Usage\n'
want_red   "readme: ...and is not counted as a section" -- rm_b
want_out   "readme: ...so two were found" 'has 2 section heading(s)' -- rm_b
rm_put '<h1><em>Made by jdoe.</em></h1>\n\n# Description\n## Usage\n## Sources\nAI\n'
want_green "readme: an <h1> holding <em> is green at basic" -- rm_b
want_out   "readme: ...and red under --wording, as an <h1>" 'an <h1> to <h6> element' -- rm_w
rm_put '\n\n<em>Made by jdoe.</em>\n# Description\n## Usage\n## Sources\n'
want_green "readme: italics after blank lines are green at basic" -- rm_b
rm_put '\n\n*Made by jdoe.*\n\n# Description\nA toy.\n## Usage\nmake\n## Sources\nAI: none.\n'
want_red   "readme: ...and red under --wording, which reads line 1" -- rm_w
want_out   "readme: ...saying where the first line is" 'The first line that shows something is line 3' -- rm_w
want_out   "readme: ...as this harness's reading" "this harness's reading, never the subject's" -- rm_w
rm_put '*Made by jdoe.*\n# Description\n## Usage\n'
want_red   "readme: two headings are red" -- rm_b
want_out   "readme: ...listing the ones found" 'README.md:3: ## Usage' -- rm_b
rm_put '*Made by jdoe.*\n# Description\n```\n# Usage\n```\n~~~sh\n# Sources\n~~~\n    # Indented\n'
want_red   "readme: a heading in a code block is not counted" -- rm_b
want_out   "readme: ...so one was found" 'has 1 section heading(s)' -- rm_b
rm_put '*Made by jdoe.*\n\nDescription\n===========\n\nUsage\n-----\n\n### Sources\n'
want_green "readme: setext headings are counted" -- rm_b
rm_put '*Made by jdoe.*\n# Description\n## Usage\n\n---\n\n- a list item\n---\n'
want_red   "readme: a rule after a blank line or a list is no heading" -- rm_b
rm_put '*Made by jdoe.*\r\n# Description\r\n## Usage\r\n## Sources\r\nAI\r\n'
want_green "readme: CRLF line ends are read as GitHub reads them" -- rm_b
# A span in italics runs over the lines of its paragraph, and Markdown shows
# it whole: basic reads the paragraph too, and --wording, line 1 alone, says
# so in those words rather than that Markdown shows no italics.
rm_put '*Made by jdoe,\nasmith.*\n# Description\n## Usage\n## Sources\nAI\n'
want_green "readme: italics over two lines of a paragraph are green at basic" -- rm_b
want_red   "readme: ...and red under --wording, which reads line 1 alone" -- rm_w
want_out   "readme: ...saying the span goes on" 'Line 1 by itself does not close its span in italics: the span goes on' -- rm_w
rm_put '*Made by jdoe,\nasmith.\n# Description\n## Usage\n## Sources\n'
want_red   "readme: a span its paragraph never closes is red" -- rm_b
rm_put '**Made by jdoe,\nasmith.**\n# Description\n## Usage\n## Sources\n'
want_out   "readme: a paragraph in bold is called bold" 'bold is not' -- rm_b
rm_put '*Made by\n- jdoe.*\n# Description\n## Usage\n## Sources\n'
want_red   "readme: a list item ends the paragraph a span would cross" -- rm_b
# Indented code: four spaces before a line that starts a block make it code.
rm_put '    *Made by jdoe.*\n# Description\n## Usage\n## Sources\n'
want_red   "readme: a first line indented four spaces is red" -- rm_b
want_out   "readme: ...as one in a code block" 'It sits in a code block' -- rm_b
rm_put '*Made by jdoe.*\n# Description\n## Usage\n\n    make\n---\n'
want_red   "readme: indented code underlined with --- is no heading" -- rm_b
want_out   "readme: ...so two were found" 'has 2 section heading(s)' -- rm_b
# Bold inside the italics is italics still: <em>by <strong>jdoe</strong></em>.
rm_put '*Made by **jdoe***\n# Description\n## Usage\n## Sources\n'
want_green "readme: bold that ends with the italics is green" -- rm_b
rm_put '***jdoe** made this.*\n# Description\n## Usage\n## Sources\n'
want_green "readme: bold that starts with the italics is green" -- rm_b
rm_put '*Made by **jdoe** today.*\n# Description\n## Usage\n## Sources\n'
want_green "readme: bold in the middle of the italics is green" -- rm_b
rm_put '*Made by **jdoe* today.**\n# Description\n## Usage\n## Sources\n'
# A limit the header states: a mark of the span's kind left inside it ends
# it here, where Markdown nests the two and shows the line in italics.
want_red   "readme: a * left inside the italics ends them (a limit)" -- rm_b
# HTML headings: GitHub shows <h1> to <h6> as headings, in an HTML block that
# runs to a blank line, and nothing else in that block.
rm_put '*Made by jdoe.*\n<h2>Description</h2>\nA toy.\n<h2 align="center">\n  Usage\n</h2>\n\n<H3>Sources</H3>\n'
want_green "readme: <h2> and <H3> elements are headings" -- rm_b
rm_put '*Made by jdoe.*\n<div align="center">\n<h1><img src="toy.png"></h1>\n# Not a heading\n</div>\n\n<h2>Description</h2>\n'
want_red   "readme: an empty <h1> and a # in an HTML block are none" -- rm_b
want_out   "readme: ...so one was found" 'has 1 section heading(s)' -- rm_b
rm_put '<h1>*Made by jdoe.*</h1>\n# Description\n## Usage\n## Sources\n'
want_out   "readme: a first line in an <h1> is a heading" 'It is a heading' -- rm_b
want_out   "readme: ...whose * marks Markdown does not read" 'Markdown is not read in an HTML block' -- rm_b
# A line of = or - under the first paragraph makes it a heading.
rm_put '*Made by jdoe.*\nDescription\n===\n## Usage\n## Sources\n'
want_red   "readme: a first line a setext line makes a heading is red" -- rm_b
want_out   "readme: ...and called a heading" 'a line of = or of - under it' -- rm_b
rm_put '*Made by jdoe.*\n---\n# Description\n## Usage\n## Sources\nAI\n'
want_green "readme: italics underlined at once are a heading in italics, green" -- rm_b
want_out   "readme: ...and red under --wording" 'a line of = or of - under it' -- rm_w
# A rule (three or more * - _, blanks between) is no paragraph: no line of
# = or - under it makes a heading, and a list item it looks like is none.
rm_put '*Made by jdoe.*\n\n***\n---\n# Description\n## Usage\n'
want_red   "readme: a rule underlined with --- is no heading" -- rm_b
want_out   "readme: ...so two were found" 'has 2 section heading(s)' -- rm_b
rm_put '*Made by jdoe.*\n\n* * *\nUsage\n---\n# Description\n## Sources\n'
want_green "readme: a rule of * * * is no list item" -- rm_b
# Comments and block tags alone show nothing: the first line is the first
# that shows something, and a heading inside a comment is none.
rm_put '<div align="center">\n\n*Made by jdoe.*\n\n</div>\n\n# Description\n## Usage\n## Sources\n'
want_green "readme: italics inside a centring <div> are green at basic" -- rm_b
rm_put '<p align="center"><i>Made by jdoe.</i></p>\n\n# Description\n## Usage\n## Sources\n'
want_green "readme: <i> inside a centring <p> is green at basic" -- rm_b
rm_put '<div align="center">\n*Made by jdoe.*\n</div>\n\n# Description\n## Usage\n## Sources\n'
want_red   "readme: * marks inside an HTML block are red" -- rm_b
want_out   "readme: ...where Markdown is not read" 'where Markdown is not read' -- rm_b
rm_put '<!-- a note -->\n*Made by jdoe.*\n# Description\n<!--\n## Usage\n-->\n## Sources\n'
want_red   "readme: a heading inside a comment is none" -- rm_b
want_out   "readme: ...and the comment above the italics is passed over" 'has 2 section heading(s)' -- rm_b
rm_put '<!-- a note -->\n*Made by jdoe.*\n# Description\n## Usage\n## Sources\nAI\n'
want_out   "readme: --wording: a comment on line 1 shows nothing" 'It shows nothing' -- rm_w
# In code, Markdown shows a <!-- as it is: it opens no comment that would
# hide the headings after it.
rm_put '*Made by jdoe.*\n\nExample:\n\n    <!-- a comment in HTML\n\n# Description\n## Usage\n## Sources\n'
want_green "readme: a <!-- in an indented code block opens no comment" -- rm_b
rm_put '*Made by jdoe.*\n\nWrite `<!--` to open a comment.\n\n# Description\n## Usage\n## Sources\n'
want_green "readme: ...nor one in a code span" -- rm_b
rm_put '*Made by jdoe.*\n\nA lone ` and then <!-- a comment -->\n\n# Description\n## Usage\n## Sources\n'
want_green "readme: ...while backticks no run closes are text" -- rm_b
rm_put '*Made by jdoe.*\n\nA lone ` and then <!--\n# Description\n-->\n## Usage\n## Sources\n'
want_out   "readme: ...and the <!-- after them opens one" 'has 2 section heading(s)' -- rm_b

rm_put "$_rm_en"
want_green "readme: --wording is green on the first sentence" -- rm_w
want_out   "readme: ...and says what no check judges" 'read by a peer at the evaluation' -- rm_w
want_out   "readme: ...in words no subject owns" 'says, and how well, is read by a peer' -- rm_b
want_broken_none "readme: ...naming no subject's requirement (AI, at basic)" 'AI' -- rm_b
rm_put "$_rm_es"
want_green "readme: --wording is green on the second" -- rm_w
rm_put '*Made by*\n# Description\n## Usage\n## Sources\nAI\n'
want_red   "readme: --wording: a sentence with no login is red" -- rm_w
want_out   "readme: ...saying so" 'names no login' -- rm_w
rm_put '*Made by jdoe and asmith.*\n# Description\n## Usage\n## Sources\nAI\n'
want_red   "readme: --wording: logins not separated by ', ' are red" -- rm_w
# A login in bold or in code is a login still: the marks are not its letters.
rm_put '*Made by **jdoe***\n# Description\n## Usage\n## Sources\nAI\n'
want_green "readme: --wording: a login in bold that ends the italics is green" -- rm_w
rm_put '*Made by __jdoe__, asmith.*\n# Description\n## Usage\n## Sources\nAI\n'
want_green "readme: --wording: a login in __bold__ is green" -- rm_w
rm_put '<i>Made by <b>jdoe</b>, `asmith`.</i>\n# Description\n## Usage\n## Sources\nAI\n'
want_green "readme: --wording: logins in <b> and in code inside <i> are green" -- rm_w
# In an HTML block Markdown is not read: ** there is two characters.
rm_put '<p align="center"><i>Made by **jdoe**</i></p>\n\n# Description\n## Usage\n## Sources\nAI\n'
want_red   "readme: --wording: ** inside an HTML block is no bold" -- rm_w
rm_put '*Made by jdoe.*\n# Description\n## Install\n## Sources\nAI\n'
want_red   "readme: --wording: a section no heading names is red" -- rm_w
want_out   "readme: ...naming it" 'names the section Usage|Uso' -- rm_w
rm_put '*Made by jdoe.*\n# DESCRIPTION\n## 2. usage:\n## Sources\nAI\n'
want_green "readme: --wording: a name is matched in any case, as a word" -- rm_w
rm_put '*Made by jdoe.*\n# Description\n## Usage\nAI here is no use.\n## Sources\nman pages, MAIL, ai.\n# More\nAI\n'
want_red   "readme: --wording: AI named outside its section is red" -- rm_w
want_out   "readme: ...saying which section" 'the section Sources|Fuentes of README.md, from line 5, never mentions AI' -- rm_w
rm_put '*Made by jdoe.*\n# Description\n## Usage\n## Sources\nman pages\n### How IA helped\nnot at all\n'
want_green "readme: --wording: a subsection is part of its section" -- rm_w
rm_put '*Made by jdoe.*\n# Description\n## Usage\n## Sources & AI\n- man 3 toy\n'
want_green "readme: --wording: the section's heading is part of it" -- rm_w
rm_put '*Made by jdoe.*\n# Description\n## Usage\n## Sources\nThe \0342\0200\0234AI\0342\0200\0235 was not used.\n'
want_green "readme: --wording: a word in curly quotes is a word" -- rm_w
rm_put '_Hecho por jdoe._\n# Descripci\0303\0263n\n## Uso\n## Fuentes\nNada de \0302\0253IA\0302\0273.\n'
want_green "readme: --wording: a word in guillemets is a word" -- rm_w
rm_put '*Made by jdoe.*\n# Description\n## Usage\n## Sources\nThe AI\0342\0200\0231s part: none.\n'
want_green "readme: --wording: a word before a curly apostrophe is a word" -- rm_w
rm_put '_Hecho por jdoe._\n# DESCRIPCI\0303\0223N\n## USO\n## FUENTES\nIA\n'
want_green "readme: --wording: an accented capital matches its small letter" -- rm_w
rm_put '_Hecho por jdoe._\n# Descripci\0303\0263n\n## Uso\n## Fuentes\nCaf\0303\0251IA\n'
want_red   "readme: --wording: AI glued to an accented letter is no word" -- rm_w
# The section AI belongs in need not be one of the --section ones; when no
# heading names it, the red is its own.
rm_put "$_rm_en"
want_red   "readme: --wording: an --ai-section no heading names is red" -- rm_w --ai-section Credits
want_out   "readme: ...naming it" 'names the section Credits, where AI is to be mentioned' -- rm_w --ai-section Credits

# Wiring: every quote the mode prints, every option it needs, refused with 2.
for _k in file first-line sections; do
	grep -v "^$_k	" "$WORK/rm/q.basic" > "$WORK/rm/q.no-$_k"
	want_broken "readme: basic without the quote '$_k' refuses" "no line for the key '$_k'" -- \
		rm_b --quotes "q.no-$_k"
done
for _k in file first-line sections ai language; do
	grep -v "^$_k	" "$WORK/rm/q.wording" > "$WORK/rm/q.wno-$_k"
	want_broken "readme: --wording without the quote '$_k' refuses" "no line for the key '$_k'" -- \
		rm_w --quotes "q.wno-$_k"
done
want_broken "readme: no quotes at all refuses" '--quotes FILE is required' -- \
	sh -c 'cd "$1" && "$2" "$3" --path p/README.md --found-list found.list --min-sections 3' _ \
	"$WORK/rm" "$SH" "$_rm_runner"
want_broken "readme: basic refuses a word it would not read" 'read only with --wording' -- \
	rm_b --sentence 'Made by'
want_broken "readme: --wording needs its words" 'needs --sentence, --section' -- \
	sh -c 'cd "$1" && "$2" "$3" --wording --path p/README.md --found-list found.list --quotes q.wording --sentence x' _ \
	"$WORK/rm" "$SH" "$_rm_runner"
want_broken "readme: basic needs --min-sections" '--min-sections N is required' -- \
	sh -c 'cd "$1" && "$2" "$3" --path p/README.md --found-list found.list --quotes q.basic' _ \
	"$WORK/rm" "$SH" "$_rm_runner"
want_broken "readme: --min-sections 00 is no number above 0" "above 0, not '00'" -- \
	rm_b --min-sections 00
want_broken "readme: --wording refuses --min-sections" 'is the basic check' -- \
	rm_w --min-sections 3
want_broken "readme: a value of more than one line refuses" 'takes one line of text' -- \
	rm_w --section "$(printf 'Usage\nUso')"
want_broken "readme: an option with no value refuses" '--path needs a value' -- \
	rm_b --path
# The PATH holds everything the runner requires, and then loses mktemp: a
# control arm on the full PATH first, so the refusal is the one tool's.
mkdir -p "$WORK/rm_path"
for _t in sh "$SH" awk cat chmod cp date dirname env grep mkdir mktemp od readlink rm; do
	ln -sf "$(command -v "$_t")" "$WORK/rm_path/${_t##*/}" 2> /dev/null
done
rm_put "$_rm_en"
want_green "readme: a complete PATH leaves the runner working" -- \
	env PATH="$WORK/rm_path" "$SH" "$TOOLS/readme_check.sh" --path "$WORK/rm/p/README.md" \
	--found-list "$WORK/rm/found_abs.list" --quotes "$WORK/rm/q.basic" --min-sections 3
rm -f "$WORK/rm_path/mktemp"
want_broken "readme: a missing tool refuses with 2 and names it" \
	"required command 'mktemp' is not on PATH" -- \
	env PATH="$WORK/rm_path" "$SH" "$TOOLS/readme_check.sh" --path "$WORK/rm/p/README.md" \
	--found-list "$WORK/rm/found_abs.list" --quotes "$WORK/rm/q.basic" --min-sections 3

