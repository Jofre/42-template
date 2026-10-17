#!/bin/sh
# readme_check.sh -- the README.md a subject asks the turn-in to carry, read
# as Markdown (tag "output"; tools/defs.bzl's c_readme): exNN_readme at basic,
# and exNN_readme_wording, with --wording, at strict.
#
# WHY IT EXISTS. Some subjects ask for a README.md at the root of the
# repository that is turned in, whose first line is in italics and says who
# made the project, and which holds sections the subject names. The files
# layer only asks that the file be there, and it is green on the stub, which
# shows nothing; nothing read what was in it, so a README that a peer would
# send back at the evaluation was green in every layer.
#
# TWO MODES, because the subject lets the README be written in more than one
# language, and a check that read the subject's words would fail one written
# in another.
#
#   basic (the default) assumes no language. It asks only what holds in every
#   language:
#     - the file is in the turn-in, and shows something: a README of blank
#       lines and HTML comments (the stub) is still to be written;
#     - its first line that shows something is, from its first character to
#       its last, one span in italics: the line by itself, the paragraph it
#       starts (a span in italics may run over the lines of its paragraph,
#       and Markdown shows them as one), or the text of a heading it is or
#       starts, since a heading's text may be in italics too;
#     - it has at least --min-sections section headings, that first line not
#       counted when it is a heading in italics.
#   --wording (strict) is this harness's reading of the same sentences, in the
#   words the call site accepts. Nothing here holds those words: every
#   sentence, section name and word arrives as an argument.
#     - line 1 itself, with nothing above it, is one span in italics, closed
#       on that line, and no heading;
#     - inside it, one of the --sentence texts, word for word (runs of blanks
#       count as one), then one or more logins separated by ", ", and an
#       optional final period. A login is letters, digits, - and _, or a
#       Markdown link [login](address), and may be in bold or in `code`;
#     - for each --section, a heading (any level) whose text holds one of its
#       |-separated names as a word, in any case (the letters of ASCII and
#       of Latin-1, written in UTF-8, are folded; other bytes are compared
#       as they are);
#     - in the section --ai-section names (its heading to the next heading of
#       the same level or a higher one, the heading included), one of the
#       --ai-word words, as a word of its own and in the case it is given.
#       Quotes, guillemets, dashes and the Spanish opening marks, written in
#       UTF-8, end a word as a blank does.
#
# WHAT IT NEVER JUDGES, and says so in every verdict: what the README says,
# and how well. No check can read that; a peer does, at the evaluation.
#
# HOW THE MARKDOWN IS READ (CommonMark, as GitHub shows it, cut down to what
# these checks need):
#   italics   the whole line between one * or one _ on each side (*x*, _x_),
#             or bold and italics together (***x***, ___x___, **_x_**,
#             __*x*__, _**x**_, *__x__*), or HTML's <i>x</i> or <em>x</em>,
#             which GitHub also shows in italics. **x** and __x__ alone are
#             bold, not italics. The span must not close before the line ends
#             (*a* b *c* is two spans), must not start or end with a blank
#             (* x* is a list item), and a \* or \_ is a character, not a
#             mark; so is an _ between two letters or digits, and anything in
#             `code`. A span in bold inside the italics (*by **jdoe***,
#             *a **b** c*) is part of them. Blanks at the end of the line are
#             ignored; up to three spaces before it too.
#   paragraph lines that follow one another, joined by a blank as Markdown
#             joins them. A list item (-, +, * or 1. and a blank) or a quote
#             (>) starts a block of its own.
#   headings  ATX: one to six # at the start of a line (after up to three
#             spaces), then a blank or the end of the line, with some text.
#             Setext: a paragraph underlined by a line of = or of -. HTML: an
#             <h1> to <h6> element, in an HTML block, at the level its tag
#             says. A line in a fenced code block (``` or ~~~) or an indented
#             one (four spaces or a tab, after a blank line) is no heading.
#   HTML      an HTML block is a line that starts with <h1>..<h6>, <div>, <p>,
#             <table> and the like, up to a blank line. Markdown is not read
#             in it: only <i> or <em> show italics there. Its block tags show
#             nothing, so a line of them alone (<div align="center">, </p>)
#             is passed over, and <p><i>x</i></p> shows the line <i>x</i>.
#   comments  <!-- --> shows nothing, over as many lines as it runs (to the
#             end of the file when it is never closed): a line that holds
#             only comments is passed over, and a heading inside one is none.
#             In a code span or a code block a <!-- is shown as it is.
#   limits    a block inside a list item is read as if the list were not
#             there; a mark of the span's kind left inside it, even one
#             Markdown prints as it is (a * with blanks on both sides), ends
#             the span here; a code span is read within its line, so a <!--
#             on the next line of one opens a comment here; and what follows
#             the --> of a comment that starts a line is read as Markdown,
#             where Markdown takes it as HTML.
#   the file  a UTF-8 byte-order mark before line 1 and a carriage return at
#             the end of a line (a file saved with CRLF endings) are dropped,
#             as GitHub drops them.
#
# Usage:
#   readme_check.sh --path PATH --found-list FILE --quotes FILE --min-sections N
#   readme_check.sh --wording --path PATH --found-list FILE --quotes FILE
#                   --sentence TEXT... --section NAMES... --ai-section NAMES
#                   --ai-word WORD...
#
#   --path         the README, from the repository root (the project's turn-in
#                  root and the file's name)
#   --found-list   what the glob of PATH found when Bazel loaded the package,
#                  one path per line: PATH, or nothing. A label naming the
#                  file would take the package down when it is missing.
#   --quotes FILE  the subject's sentences, KEY<TAB>TEXT (tools/defs.bzl's
#                  runner_quotes). Keys: file, first-line, sections; with
#                  --wording also ai and language.
#   --min-sections N  (basic) how many section headings, at least
#   --sentence TEXT   (--wording, repeated) a first-line sentence it accepts,
#                  up to the logins
#   --section NAMES   (--wording, repeated) one required section: its names,
#                  separated by |
#   --ai-section NAMES  (--wording) the section that must mention AI, as one
#                  --section names it
#   --ai-word WORD    (--wording, repeated) a word that names AI there
#
# Exit: 0 every check holds; 1 one does not (the file missing or empty
# included); 2 the harness broke (an option missing or out of place, a quote
# missing, an unreadable list).
set -u

# The external commands this runner takes from PATH. See diff_output.sh for
# why they are declared and probed; exit 2, never 1, because this says the
# check never ran rather than that the turn-in is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "readme_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk grep mktemp rm

# The shared runner helpers -- the quotes (rl_quote), the one renderer of a
# line's bytes (rl_vis) -- written once in tools/runner_lib.sh.
RL_NAME=readme_check
case $0 in */*) RL_LIB=${0%/*}/runner_lib.sh ;; *) RL_LIB=./runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "readme_check.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"
# conventions: runs no student code -- it reads one Markdown file of the turn-in

WANT=""
FOUND=""
WORDING=0
MIN=""
SENTENCES=""
SECTIONS=""
AI_SECTION=""
AI_WORDS=""
GIVEN_WORDING=""

need() { [ "$2" -ge 2 ] || { echo "readme_check.sh: $1 needs a value" >&2; exit 2; }; }

# A value of a list option: one line of text, never empty.
oneline() {
	case "$2" in
		'' | *"$RL_NL"*)
			echo "readme_check.sh: $1 takes one line of text, not '$2'" >&2
			exit 2 ;;
	esac
}

while [ $# -gt 0 ]; do
	case "$1" in
		--path) need "$1" "$#"; WANT="$2"; shift 2 ;;
		--found-list) need "$1" "$#"; FOUND="$2"; shift 2 ;;
		--quotes) need "$1" "$#"; rl_quotes_opt "$2"; shift 2 ;;
		--min-sections) need "$1" "$#"; MIN="$2"; shift 2 ;;
		--wording) WORDING=1; shift ;;
		--sentence) need "$1" "$#"; oneline "$1" "$2"; rl_list_add SENTENCES "$2"; GIVEN_WORDING="$1"; shift 2 ;;
		--section) need "$1" "$#"; oneline "$1" "$2"; rl_list_add SECTIONS "$2"; GIVEN_WORDING="$1"; shift 2 ;;
		--ai-section) need "$1" "$#"; oneline "$1" "$2"; AI_SECTION="$2"; GIVEN_WORDING="$1"; shift 2 ;;
		--ai-word) need "$1" "$#"; oneline "$1" "$2"; rl_list_add AI_WORDS "$2"; GIVEN_WORDING="$1"; shift 2 ;;
		*) echo "readme_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$WANT" ] && [ -n "$FOUND" ] || {
	echo "readme_check.sh: need --path and --found-list" >&2
	exit 2
}
[ -r "$FOUND" ] || { echo "readme_check.sh: cannot read the list '$FOUND'" >&2; exit 2; }
if [ "$WORDING" = 1 ]; then
	[ -z "$MIN" ] || {
		echo "readme_check.sh: --min-sections is the basic check's; --wording looks each --section up by name" >&2
		exit 2
	}
	[ -n "$SENTENCES" ] && [ -n "$SECTIONS" ] && [ -n "$AI_SECTION" ] && [ -n "$AI_WORDS" ] || {
		echo "readme_check.sh: --wording needs --sentence, --section, --ai-section and --ai-word: the words it accepts come from the call site" >&2
		exit 2
	}
	rl_quotes_ready "file first-line sections ai language"
	TAG=readme_wording
else
	[ -z "$GIVEN_WORDING" ] || {
		echo "readme_check.sh: $GIVEN_WORDING is read only with --wording; the basic check assumes no language" >&2
		exit 2
	}
	# Digits alone, and one of them not 0: "00" is no number above 0.
	case "$MIN" in
		'' | *[!0-9]*) _min_ok=0 ;;
		*[1-9]*) _min_ok=1 ;;
		*) _min_ok=0 ;;
	esac
	[ "$_min_ok" = 1 ] || {
		echo "readme_check.sh: --min-sections N is required, N a whole number above 0, not '$MIN'" >&2
		exit 2
	}
	rl_quotes_ready "file first-line sections"
	TAG=readme
fi
NAME=${WANT##*/}

# quoted KEY -- the subject's sentence for KEY, indented under a message.
quoted() {
	echo "  The requirement:"
	rl_quote "$1" | while IFS= read -r _q; do echo "    $_q"; done
}

# shown N -- line N of the README, every byte through the one renderer.
shown() {
	_l=$(awk -v n="$1" 'NR == n { sub(/\r$/, ""); print; exit }' "$WANT")
	printf '    %s:%s: ' "$NAME" "$1"
	printf '%s' "$_l" | rl_vis arg 1 160
	echo ""
}

# What no check reads, said in words no subject owns: which parts a peer
# weighs is the subject's to say, never a runner's.
never_judged() {
	echo "  What $NAME says, and how well, is read by a peer at the evaluation:"
	echo "  no check here judges it."
}

# THE FILE.
if ! grep -qxF "$WANT" "$FOUND" || [ ! -f "$WANT" ]; then
	echo "$TAG: FAIL — there is no $NAME in the turn-in: $WANT is missing."
	echo ""
	quoted file
	echo ""
	echo "  The files layer names it too. Was it renamed, moved into a folder, or"
	echo "  left out of the commit?"
	exit 1
fi

WORK=$(mktemp -d) || { echo "readme_check.sh: cannot create a scratch directory" >&2; exit 2; }
rl_traps 'rm -rf "$WORK"'

# THE READING: one pass of awk over the file, which prints what it found, one
# fact per line (TAB-separated), for the messages below to word.
#   EMPTY                              no line holds more than blanks
#   HIDDEN                             no line shows anything (comments,
#                                      block tags alone)
#   FIRST   N  VERDICT                 the first line that shows something
#   LINE1   VERDICT                    line 1 itself (--wording)
#   HEAD    N  LEVEL                   a heading, at line N
#   SENTENCE VERDICT                   line 1's words (--wording)
#   SECTION I  N                       --section number I, first heading at N (0: none)
#   AI      N  W                       the AI section's heading at N (0: none),
#                                      the line a word was found at (0: none)
# A VERDICT on italics is ok, blank, hidden, code, heading, hheading (an
# <hN> one), setext, html, bold or notwhole (and wrapped, for LINE1); on the
# words, ok, nosentence, nologin or form.
RM_SENTENCES=$SENTENCES RM_SECTIONS=$SECTIONS RM_AI_SECTION=$AI_SECTION RM_AI_WORDS=$AI_WORDS \
	LC_ALL=C awk -v wording="$WORDING" '
	function isw(c) { return c != "" && (c ~ /[A-Za-z0-9]/ || c >= "\200") }
	# s with the punctuation that UTF-8 writes in more than one byte -- curly
	# quotes and apostrophes, guillemets, dashes, an ellipsis, a no-break
	# space, the Spanish opening marks -- turned to blanks, so that a word
	# beside one (AI in curly quotes or guillemets, or before a curly
	# apostrophe) is still a word of its own.
	function punct(s) {
		gsub(/\342\200\230|\342\200\231|\342\200\234|\342\200\235|\342\200\223|\342\200\224|\342\200\246/, " ", s)
		gsub(/\302\240|\302\241|\302\253|\302\273|\302\277/, " ", s)
		return s
	}
	# s with the capitals of Latin-1 written in UTF-8 (À to Þ, not ×) turned to
	# their small letters, as tolower() does for ASCII: DESCRIPCIÓN reads as
	# descripción.
	function fold(s,    i, j) {
		for (i = 1; i <= nfold; i++)
			while ((j = index(s, FU[i])) > 0)
				s = substr(s, 1, j - 1) FL[i] substr(s, j + 2)
		return s
	}
	# Whether w occurs in s with no letter, digit or non-ASCII byte touching it.
	function hasword(s, w,    off, i, b, a) {
		if (w == "") return 0
		s = punct(s)
		off = 0
		while ((i = index(substr(s, off + 1), w)) > 0) {
			b = (off + i > 1) ? substr(s, off + i - 1, 1) : ""
			a = substr(s, off + i + length(w), 1)
			if (!isw(b) && !isw(a)) return 1
			off += i
		}
		return 0
	}
	function rev(s,    r, i) { r = ""; for (i = length(s); i > 0; i--) r = r substr(s, i, 1); return r }
	function norm(s) { gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
	# The italics verdict on line s; INNER is the text inside the marks. With
	# htmlonly (a line of an HTML block, where Markdown is not read), only
	# <i> and <em> make italics.
	function ital(s, incode, htmlonly,    t, lo, tag, cl, x, y, p, q) {
		INNER = ""
		if (s ~ /^[ \t]*$/) return "blank"
		if (incode) return "code"
		t = s
		sub(/[ \t]+$/, "", t)
		if (t ~ /^ ? ? ?#+([ \t]|$)/ && t !~ /^ ? ? ?#######/) return "heading"
		sub(/^ +/, "", t)
		lo = tolower(t)
		if (lo ~ /^<(i|em)>/) {
			tag = (substr(lo, 2, 1) == "i" && substr(lo, 3, 1) == ">") ? "i" : "em"
			cl = "</" tag ">"
			x = substr(t, length(tag) + 3)
			if (length(x) <= length(cl) || substr(tolower(x), length(x) - length(cl) + 1) != cl)
				return "notwhole"
			x = substr(x, 1, length(x) - length(cl))
			if (index(tolower(x), cl) || x ~ /^[ \t]*$/) return "notwhole"
			INNER = x
			return "ok"
		}
		if (htmlonly) return "notwhole"
		p = ""; q = ""
		if (match(t, /^[*_]+/)) p = substr(t, 1, RLENGTH)
		if (match(t, /[*_]+$/)) q = substr(t, RSTART)
		if (p == "" || q == "" || length(p) + length(q) >= length(t)) return "notwhole"
		x = substr(t, length(p) + 1, length(t) - length(p) - length(q))
		# A span in bold that ends or starts with the italics (*by **jdoe***,
		# ***jdoe** made*): its two marks belong to the text inside, and are
		# paired there, below.
		if (q != rev(p)) {
			if (length(q) == length(p) + 2 && substr(q, 3) == rev(p) && substr(q, 1, 2) ~ /^(\*\*|__)$/) {
				x = x substr(q, 1, 2)
				q = substr(q, 3)
			} else if (length(p) == length(q) + 2 && substr(p, 1, length(q)) == rev(q) && substr(p, length(q) + 1) ~ /^(\*\*|__)$/) {
				x = substr(p, length(q) + 1) x
				p = substr(p, 1, length(q))
			} else
				return "notwhole"
		}
		if (x ~ /^[ \t]/ || x ~ /[ \t]$/ || x ~ /\\$/) return "notwhole"
		y = x
		gsub(/\\[*_]/, "", y)
		gsub(/`[^`]*`/, "", y)
		while (match(y, /[A-Za-z0-9]_+[A-Za-z0-9]/))
			y = substr(y, 1, RSTART) substr(y, RSTART + RLENGTH - 1)
		# A span in bold inside the italics (*by **jdoe** today*): Markdown
		# shows it in bold and in italics, so its marks are no end of the span.
		while (match(y, /\*\*[^* \t]([^*]*[^* \t])?\*\*/))
			y = substr(y, 1, RSTART - 1) substr(y, RSTART + 2, RLENGTH - 4) substr(y, RSTART + RLENGTH)
		while (match(y, /__[^_ \t]([^_]*[^_ \t])?__/))
			y = substr(y, 1, RSTART - 1) substr(y, RSTART + 2, RLENGTH - 4) substr(y, RSTART + RLENGTH)
		if ((index(p, "*") && index(y, "*")) || (index(p, "_") && index(y, "_"))) return "notwhole"
		if (p == "**" || p == "__") return "bold"
		if (p == "*" || p == "_" || p == "***" || p == "___" || p == "**_" || p == "__*" || p == "_**" || p == "*__") {
			INNER = x
			return "ok"
		}
		return "notwhole"
	}
	# x without the marks of a span in bold or in code inside it, which leave
	# its words as they are: **jdoe**, __jdoe__ (not between two letters or
	# digits, where an _ is a character), `jdoe`, and the HTML tags <b>,
	# <strong> and <code>. In an HTML block (html), Markdown is not read:
	# the tags alone are marks there.
	function plain(x, html,    m, lead, trail) {
		if (!html) {
			while (match(x, /\*\*[^* \t]([^*]*[^* \t])?\*\*/))
				x = substr(x, 1, RSTART - 1) substr(x, RSTART + 2, RLENGTH - 4) substr(x, RSTART + RLENGTH)
			while (match(x, /(^|[^A-Za-z0-9_])__[^_ \t]([^_]*[^_ \t])?__([^A-Za-z0-9_]|$)/)) {
				m = substr(x, RSTART, RLENGTH)
				lead = (substr(m, 1, 1) == "_") ? 0 : 1
				trail = (substr(m, RLENGTH, 1) == "_") ? 0 : 1
				x = substr(x, 1, RSTART - 1) substr(m, 1, lead) \
					substr(m, lead + 3, RLENGTH - lead - trail - 4) \
					substr(m, RLENGTH - trail + 1) substr(x, RSTART + RLENGTH)
			}
			while (match(x, /`[^`]+`/))
				x = substr(x, 1, RSTART - 1) substr(x, RSTART + 1, RLENGTH - 2) substr(x, RSTART + RLENGTH)
		}
		while (match(tolower(x), /<\/?(b|strong|code)>/))
			x = substr(x, 1, RSTART - 1) substr(x, RSTART + RLENGTH)
		return x
	}
	# The words of line 1, inside its italics.
	function words(x, html,    n, i, s, r, L) {
		L = "([A-Za-z0-9][A-Za-z0-9_-]*|\\[[^]]+\\]\\([^)]+\\))"
		n = norm(plain(x, html))
		for (i = 1; i <= nsen; i++) {
			s = norm(sen[i])
			if (s == "" || substr(n, 1, length(s)) != s) continue
			r = substr(n, length(s) + 1)
			if (r ~ /^ ?\.?$/) return "nologin"
			if (substr(r, 1, 1) != " ") continue
			r = substr(r, 2)
			if (r ~ ("^" L "(, " L ")*\\.?$")) return "ok"
			return "form"
		}
		return "nosentence"
	}
	# Whether heading text h names one of the |-separated names in alts.
	function names(h, alts,    n, a, i, lo) {
		lo = fold(tolower(h))
		gsub(/[*_`]/, "", lo)
		n = split(alts, a, "|")
		for (i = 1; i <= n; i++)
			if (hasword(lo, fold(tolower(norm(a[i]))))) return 1
		return 0
	}
	function heading(n, lev, text) {
		nh++
		hl[nh] = n; hv[nh] = lev; ht[nh] = text
	}
	# The verdict on line n: what its block makes it, or else its italics.
	# A heading whose text is one span in italics is a line in italics, but
	# under strict, which reads the line asked for as no heading.
	function verdict(n, strict,    k, v) {
		if (code[n]) return "code"
		if (hid[n]) return "hidden"
		k = kind[n]
		if (k == "heading" || k == "setext") {
			if (hk[n] == "html") k = "hheading"
			if (strict) return k
			v = (hk[n] == "html") ? ital(hraw[n], 0, 1) : ital(hin[n], 0, 0)
			return (v == "ok") ? "ok" : k
		}
		if (k == "html") return (ital(hin[n], 0, 1) == "ok") ? "ok" : "html"
		return ital(raw[n], 0, 0)
	}
	# Where in s a run of exactly n backticks starts; 0 where none does.
	function btrun(s, n,    off) {
		off = 0
		while (match(s, /`+/)) {
			if (RLENGTH == n) return off + RSTART
			off += RSTART + RLENGTH - 1
			s = substr(s, RSTART + RLENGTH)
		}
		return 0
	}
	# s without the <!-- --> comments in it, which Markdown does not show;
	# incom carries a comment that runs on to the next line. With spans, a
	# code span (a run of backticks up to the next run as long) shows its
	# text as it is, a <!-- in it included; backticks that no run closes
	# are text.
	function uncomment(s, spans,    out, i, j, n, r) {
		out = ""
		while (1) {
			if (incom) {
				if (!(i = index(s, "-->"))) return out
				s = substr(s, i + 3)
				incom = 0
				continue
			}
			i = index(s, "<!--")
			j = spans ? index(s, "`") : 0
			if (j && (!i || j < i)) {
				match(substr(s, j), /^`+/)
				n = RLENGTH
				r = btrun(substr(s, j + n), n)
				if (r) n += r - 1 + n
				out = out substr(s, 1, j + n - 1)
				s = substr(s, j + n)
				continue
			}
			if (!i) return out s
			out = out substr(s, 1, i - 1)
			s = substr(s, i + 4)
			incom = 1
		}
	}
	# What line s of an HTML block shows: the block tags that open or close
	# around it taken off (<div align="center">, </p>), and its blanks.
	function bare(s,    bt) {
		bt = "<\\/?(address|article|aside|blockquote|center|details|div|dl|figure|footer|header|main|nav|ol|p|section|summary|table|ul)([ \t][^>]*)?\\/?>"
		sub(/^[ \t]+/, "", s)
		while (match(tolower(s), "^" bt "[ \t]*")) s = substr(s, RLENGTH + 1)
		while (match(tolower(s), "[ \t]*" bt "[ \t]*$")) s = substr(s, 1, RSTART - 1)
		sub(/[ \t]+$/, "", s)
		return s
	}
	# Line n of an HTML block: passed over when it shows nothing, a heading
	# when what it shows starts with <hN>, and otherwise a line of HTML.
	function htmlline(s, n,    b) {
		hscan(s, n)
		b = bare(s)
		if (b == "") { hid[n] = 1; return }
		if (!first) first = n
		if (tolower(b) ~ /^<h[1-6]([ \t>]|\/>|$)/) { kind[n] = "heading"; hk[n] = "html" }
		else { kind[n] = "html"; hin[n] = b }
	}
	# Line n of an HTML block: an <hN> element in it opens a heading, and its
	# </hN> closes it; the text between, without tags, is its text, and with
	# them (hraw), what its italics are read in.
	function hscan(s, n,    x, c) {
		if (!hopen) {
			if (!match(s, /<[hH][1-6]([ \t>]|\/>|$)/)) return
			hopen = 1; hstart = n; hlev = substr(s, RSTART + 2, 1)
			htext = substr(s, RSTART)
		} else
			htext = htext " " s
		c = index(tolower(htext), "</h" hlev ">")
		if (!c) return
		x = substr(htext, 1, c - 1)
		sub(/^<[^>]*>/, "", x)
		hraw[hstart] = norm(x)
		gsub(/<[^>]*>/, " ", x)
		x = norm(x)
		if (x != "") heading(hstart, hlev, x)
		hopen = 0
	}
	BEGIN {
		nsen = split(ENVIRON["RM_SENTENCES"], sen, "\n")
		nsec = split(ENVIRON["RM_SECTIONS"], secs, "\n")
		naiw = split(ENVIRON["RM_AI_WORDS"], aiw, "\n")
		aisec = ENVIRON["RM_AI_SECTION"]
		first = 0; fence = ""; para = ""; nh = 0; html = 0; hopen = 0
		nfold = 0
		# The second byte of each capital: 0200 to 0236, but 0227 (the sign x).
		for (c = 0; c < 31; c++)
			if (c != 23) {
				nfold++
				FU[nfold] = sprintf("\303%c", 128 + c)
				FL[nfold] = sprintf("\303%c", 160 + c)
			}
	}
	{
		line = $0
		if (NR == 1) sub(/^\357\273\277/, "", line)
		sub(/\r$/, "", line)
		raw[NR] = line
		if (fence != "") {
			code[NR] = 1
			t = line
			sub(/^ ? ? ?/, "", t)
			sub(/[ \t]+$/, "", t)
			if (substr(t, 1, 1) == substr(fence, 1, 1) && length(t) >= length(fence) && t ~ /^(`+|~+)$/)
				fence = ""
			next
		}
		# A comment shows nothing: a line it leaves blank is passed over
		# (hid), and ends a paragraph, as a comment starting a line does in
		# Markdown, but not an HTML block, which only a blank line ends.
		wasin = incom
		blank = (line ~ /^[ \t]*$/)
		if (!blank) any = 1
		# An indented line after a blank one is code, which shows a <!-- as
		# it is: no comment opens in it.
		if (!incom && !html && !blank && para == "" && line ~ /^(    | ? ? ?\t)/) {
			if (!first) first = NR
			code[NR] = 1
			next
		}
		line = uncomment(line, !html)
		raw[NR] = line
		if (line ~ /^[ \t]*$/) {
			para = ""
			if (!blank) hid[NR] = 1
			else if (!wasin) { html = 0; hopen = 0 }
			next
		}
		# Inside an HTML block: raw HTML up to a blank line, read for its
		# <hN> elements and for what each line shows.
		if (html) { htmlline(line, NR); next }
		if (match(line, /^ ? ? ?(```+|~~~+)/)) {
			f = substr(line, RSTART, RLENGTH)
			sub(/^ +/, "", f)
			if (!(substr(f, 1, 1) == "`" && index(substr(line, RSTART + RLENGTH), "`"))) {
				if (!first) first = NR
				fence = f
				code[NR] = 1
				para = ""
				next
			}
		}
		if (para == "" && line ~ /^(    | ? ? ?\t)/) { if (!first) first = NR; code[NR] = 1; next }
		# An HTML block, as a tag of the kinds that start one (the sixth kind
		# in CommonMark, cut down to the tags a README uses) starts it.
		t = tolower(line)
		if (t ~ /^ ? ? ?<\/?(address|article|aside|blockquote|center|details|div|dl|figure|footer|h[1-6]|header|hr|main|nav|ol|p|section|summary|table|ul)([ \t>]|\/>|$)/) {
			html = 1
			para = ""
			htmlline(line, NR)
			next
		}
		if (!first) first = NR
		if (line ~ /^ ? ? ?#+([ \t]|$)/ && line !~ /^ ? ? ?#######/) {
			t = line
			sub(/^ *#+[ \t]*/, "", t)
			sub(/[ \t]+#+[ \t]*$/, "", t)
			sub(/^#+[ \t]*$/, "", t)
			sub(/[ \t]+$/, "", t)
			match(line, /#+/)
			if (t != "") heading(NR, RLENGTH, t)
			kind[NR] = "heading"
			hin[NR] = t
			para = ""
			next
		}
		if (para != "" && !nosetext && line ~ /^ ? ? ?(=+|-+)[ \t]*$/) {
			heading(pstart, (line ~ /=/) ? 1 : 2, para)
			kind[pstart] = "setext"
			hin[pstart] = para
			para = ""
			next
		}
		if (line ~ /^ ? ? ?([-*_][ \t]*)([-*_][ \t]*)([-*_][ \t]*)+$/) { para = ""; next }
		# A paragraph, its lines joined by one blank as Markdown joins them
		# (PT, from line pstart to line PE). A list item or a quote starts a
		# block of its own, and no line of = or - under it makes a heading.
		t = line
		sub(/^[ \t]+/, "", t)
		sub(/[ \t]+$/, "", t)
		islist = (line ~ /^ ? ? ?([-+*]|[0-9]+[.)])([ \t]|$)/ || line ~ /^ ? ? ?>/)
		if (para == "" || islist) {
			pstart = NR
			para = t
			nosetext = islist
		} else
			para = para " " t
		PT[pstart] = para
		PE[pstart] = NR
	}
	END {
		if (!first) { print (any ? "HIDDEN" : "EMPTY"); exit }
		# A span in italics may run over the lines of its paragraph, and
		# Markdown shows it whole: the first line is in italics on either
		# reading, the line by itself or the paragraph it starts.
		v = verdict(first, 0)
		if (v == "notwhole" && (first in PE) && PE[first] > first) {
			w = ital(PT[first], 0, 0)
			if (w == "ok" || w == "bold") v = w
		}
		print "FIRST\t" first "\t" v
		# A heading in italics that is that line is the line, not a section.
		skip = (v == "ok" && (kind[first] == "heading" || kind[first] == "setext")) ? first : 0
		for (i = 1; i <= nh; i++) if (hl[i] != skip) print "HEAD\t" hl[i] "\t" hv[i]
		if (!wording) exit
		v = verdict(1, 1)
		inner = INNER
		if (v == "notwhole" && (1 in PE) && PE[1] > 1 && ital(PT[1], 0, 0) == "ok") {
			v = "wrapped"
			print "WRAP\t" PE[1]
		}
		print "LINE1\t" v
		if (v == "ok") print "SENTENCE\t" words(inner, kind[1] == "html")
		for (s = 1; s <= nsec; s++) {
			at = 0
			for (i = 1; i <= nh && !at; i++) if (names(ht[i], secs[s])) at = hl[i]
			print "SECTION\t" s "\t" at
		}
		at = 0; found = 0
		for (i = 1; i <= nh && !found; i++) {
			if (!names(ht[i], aisec)) continue
			if (!at) at = hl[i]
			stop = NR + 1
			for (j = i + 1; j <= nh; j++) if (hv[j] <= hv[i]) { stop = hl[j]; break }
			for (l = hl[i]; l < stop && !found; l++)
				for (w = 1; w <= naiw && !found; w++)
					if (hasword(raw[l], aiw[w])) { found = l; at = hl[i] }
		}
		print "AI\t" at "\t" found
	}' "$WANT" > "$WORK/facts" || {
	echo "readme_check.sh: awk could not read $WANT" >&2
	exit 2
}

fact() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$WORK/facts"; }
fact3() { awk -F'\t' -v k="$1" '$1 == k { print $3; exit }' "$WORK/facts"; }

if grep -qx EMPTY "$WORK/facts" || grep -qx HIDDEN "$WORK/facts"; then
	if grep -qx EMPTY "$WORK/facts"; then
		echo "$TAG: FAIL — $WANT is empty: it holds no line that is not blank. It"
		echo "  is still to be written."
	else
		echo "$TAG: FAIL — $WANT shows nothing: it holds only blank lines, HTML"
		echo "  comments (<!-- -->) and tags alone on their lines, which Markdown does"
		echo "  not show. It is still to be written."
	fi
	echo ""
	quoted file
	echo ""
	echo "  Someone who has never seen this project opens this file first. What do"
	echo "  they need to find in it?"
	exit 1
fi

BAD=0
OK=""
NHEAD=$(awk -F'\t' '$1 == "HEAD" { n++ } END { print n + 0 }' "$WORK/facts")

# Why a line is not one span in italics, by verdict. A heading is one at
# basic only when its text is not in italics; under --wording, any heading.
why_not() {
	case "$1" in
		blank) echo "  It is blank." ;;
		hidden)
			echo "  It shows nothing: an HTML comment (<!-- -->), or a tag such as <div>"
			echo "  alone on its line, is not shown." ;;
		code)
			echo "  It sits in a code block (a \`\`\` or ~~~ fence, or four spaces or a"
			echo "  tab before it), which Markdown shows as code, not in italics." ;;
		heading | hheading | setext)
			case "$1" in
				heading) echo "  It is a heading: it starts with #." ;;
				hheading) echo "  It is a heading: an <h1> to <h6> element, in an HTML block." ;;
				*)
					echo "  It is a heading: a line of = or of - under it, or under the lines"
					echo "  that follow it, makes Markdown show them as one." ;;
			esac
			if [ "$WORDING" = 1 ]; then
				echo "  Here the line asked for is read as a line of text in italics, and"
				echo "  never as a heading, even one whose text is in italics."
			else
				echo "  Its text is not one span in italics."
				[ "$1" != hheading ] || {
					echo "  Markdown is not read in an HTML block: there, only <i> or <em>"
					echo "  show italics."
				}
			fi ;;
		html)
			echo "  It sits in an HTML block (it starts with, or follows, a tag such as"
			echo "  <div> or <p>, up to a blank line), where Markdown is not read: only"
			echo "  <i> or <em> show italics there." ;;
		bold)
			echo "  It is in bold: two marks on each side make bold, and bold is not"
			echo "  italics." ;;
		*)
			echo "  Markdown does not show it in italics from its first character to its"
			echo "  last: part of it, or all of it, is outside a span in italics." ;;
	esac
}

heads_shown() {
	awk -F'\t' '$1 == "HEAD" && ++n <= 12 { print $2 }' "$WORK/facts" > "$WORK/heads"
	while IFS= read -r _n; do shown "$_n"; done < "$WORK/heads"
}

if [ "$WORDING" = 0 ]; then
	FIRST=$(fact FIRST)
	V=$(fact3 FIRST)
	if [ "$V" = ok ]; then
		OK="${OK}  the first line that shows something (line $FIRST) is in italics$RL_NL"
	else
		BAD=$((BAD + 1))
		echo "$TAG: FAIL — the first line of $NAME that shows something, line $FIRST, is"
		echo "  not one span in italics:"
		shown "$FIRST"
		why_not "$V"
		echo ""
		quoted first-line
		echo ""
		echo "  How does Markdown mark a span of text as italics, and does that span"
		echo "  run from the first character of this line to its last?"
		echo ""
	fi
	if [ "$NHEAD" -ge "$MIN" ]; then
		OK="${OK}  $NHEAD section heading(s), $MIN at least$RL_NL"
	else
		BAD=$((BAD + 1))
		echo "$TAG: FAIL — $NAME has $NHEAD section heading(s); at least $MIN sections are asked for."
		if [ "$NHEAD" -gt 0 ]; then
			echo "  The heading(s) found:"
			heads_shown
		fi
		echo "  A heading here is a line that starts with one to six #, then a blank"
		echo "  and some text, a line of text underlined with === or ---, or an <h1>"
		echo "  to <h6> element, outside a code block and a comment. A first line in"
		echo "  italics is not counted, even as a heading."
		echo ""
		quoted sections
		echo ""
		echo "  Which sections does a reader of $NAME look for, and does each one start"
		echo "  with a heading?"
		echo ""
	fi
	if [ "$BAD" -gt 0 ]; then
		never_judged
		exit 1
	fi
	echo "$TAG: OK — $WANT:"
	printf '%s' "$OK"
	echo "  No language is assumed here: a stricter test reads the words themselves."
	never_judged
	exit 0
fi

# --wording: the strict target's reading, in the words the call site
# accepts. A runner points at a reading and never states one: the strict
# target's row of docs/reference.md states it (tools/conventions.sh, "A
# runner points at a reading").
reading() {
	echo "  The check above is this harness's reading, never the subject's: a peer"
	echo "  may read the requirement otherwise."
}
accepted() {
	echo "  The sentences this check accepts, each followed by the login(s):"
	rl_split_on
	for _s in $SENTENCES; do
		rl_split_off
		printf '      '
		printf '%s' "$_s" | rl_vis arg 1 160
		echo ""
		rl_split_on
	done
	rl_split_off
}

V=$(fact LINE1)
if [ "$V" != ok ]; then
	BAD=$((BAD + 1))
	echo "$TAG: FAIL — line 1 of $NAME is not one span in italics:"
	shown 1
	if [ "$V" = wrapped ]; then
		_end=$(fact WRAP)
		echo "  Line 1 by itself does not close its span in italics: the span goes on"
		echo "  to line $_end, and Markdown shows lines 1 to $_end as one paragraph in"
		echo "  italics. Here, the span, the sentence and the login(s) are looked for"
		echo "  on line 1 alone."
	else
		why_not "$V"
	fi
	case "$V" in
		blank | hidden)
			echo "  The first line that shows something is line $(fact FIRST), with"
			echo "  lines above it that show nothing." ;;
	esac
	echo ""
	quoted first-line
	reading
	echo ""
else
	S=$(fact SENTENCE)
	case "$S" in
		ok) OK="${OK}  line 1 is in italics, and reads an accepted sentence and the login(s)$RL_NL" ;;
		*)
			BAD=$((BAD + 1))
			case "$S" in
				nosentence) echo "$TAG: FAIL — line 1 of $NAME does not begin with a sentence this check accepts:" ;;
				nologin) echo "$TAG: FAIL — line 1 of $NAME names no login after its sentence:" ;;
				*) echo "$TAG: FAIL — after its sentence, line 1 of $NAME does not read as login(s) separated by \", \":" ;;
			esac
			shown 1
			accepted
			echo "  A login is letters, digits, - and _ (or a Markdown link around one);"
			echo "  several are separated by a comma and a blank, and a period may end the"
			echo "  line."
			echo ""
			quoted first-line
			quoted language
			reading
			echo ""
			;;
	esac
fi

I=0
rl_split_on
for _sec in $SECTIONS; do
	rl_split_off
	I=$((I + 1))
	AT=$(awk -F'\t' -v i="$I" '$1 == "SECTION" && $2 == i { print $3; exit }' "$WORK/facts")
	if [ "${AT:-0}" -gt 0 ]; then
		OK="${OK}  a heading names the section $_sec (line $AT)$RL_NL"
	else
		BAD=$((BAD + 1))
		echo "$TAG: FAIL — no heading of $NAME names the section $_sec."
		echo "  This check looks for one of those names (| separates them) as a word"
		echo "  of a heading's text, at any level and in any case."
		if [ "$NHEAD" -gt 0 ]; then
			echo "  The heading(s) found:"
			heads_shown
		else
			echo "  It found no heading at all."
		fi
		echo ""
		quoted sections
		reading
		echo ""
	fi
	rl_split_on
done
rl_split_off

AIAT=$(fact AI)
AIW=$(fact3 AI)
if [ "${AIAT:-0}" -gt 0 ] && [ "${AIW:-0}" -gt 0 ]; then
	OK="${OK}  the section $AI_SECTION (line $AIAT) mentions AI, at line $AIW$RL_NL"
elif [ "${AIAT:-0}" -gt 0 ]; then
	BAD=$((BAD + 1))
	_ws=$(printf '%s' "$AI_WORDS" | awk 'BEGIN { ORS = "" } { print (NR > 1 ? ", " : "") $0 }')
	echo "$TAG: FAIL — the section $AI_SECTION of $NAME, from line $AIAT, never mentions AI."
	echo "  None of these words is in it as a word of its own, in the case shown:"
	printf '      '
	printf '%s' "$_ws" | rl_vis arg 1 160
	echo ""
	echo "  (The section runs from its heading to the next heading of the same"
	echo "  level or a higher one.)"
	echo ""
	quoted ai
	reading
	echo ""
fi
# A section --ai-section names that has no heading at all is the --section
# report's when it is one of them, and said here only when it is not.
if [ "${AIAT:-0}" -eq 0 ]; then
	case "$RL_NL$SECTIONS$RL_NL" in
		*"$RL_NL$AI_SECTION$RL_NL"*) ;;
		*)
			BAD=$((BAD + 1))
			echo "$TAG: FAIL — no heading of $NAME names the section $AI_SECTION, where AI is to be mentioned."
			echo ""
			quoted ai
			reading
			echo ""
			;;
	esac
fi

if [ "$BAD" -gt 0 ]; then
	never_judged
	exit 1
fi
echo "$TAG: OK — $WANT, read in the words this check was given:"
printf '%s' "$OK"
never_judged
exit 0
