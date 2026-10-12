#!/usr/bin/env python3
"""Post-processing for the C Piscine study guide's two renderings (tools/exam_guide.sh).

    guide_post.py print-template PAGE_TEMPLATE PRINT_CSS   -> stdout
    guide_post.py screen FILE.html                         (in place)
    guide_post.py print FILE.html                          (in place)
    guide_post.py self-check PRINT_CSS                     exit 1 on a fault

print-template derives the PDF's pandoc template from the page's: the same
styles, no web fonts (the PDF is built offline), print.css laid over them, and
a plain "Contents" list instead of the collapsible one.

screen and print move each self-check answer to the end of its chapter, where
a reader meets it after answering, and leave a link under its question. They
also undo what this pandoc (2.9) does to an answer block: it wraps <summary>
in a paragraph. The screen page gets each answer as a <details>, folded; the
PDF gets them as always-open answer boxes, since paper cannot click. print
also gives every table explicit column widths -- print.css lays tables out
`fixed`, and fixed layout without widths makes every column equal -- and keeps
inline code from breaking anywhere but between its words.
"""
import html
import re
import sys

# An answer block as pandoc 2.9 writes it, which answers_last() leaves in
# no rendering.
DETAILS = re.compile(r'<details>\n<p><summary>(.*?)</summary></p>')


def print_template(page, css):
    t = open(page, encoding='utf-8').read()
    t = re.sub(r'<link rel="stylesheet" href="https://fonts\.googleapis\.com[^>]*>\n', '', t)
    style = open(css, encoding='utf-8').read()
    t = t.replace('</head>', '<style>\n' + style + '</style>\n</head>', 1)
    t = re.sub(r'<details class="toc"><summary>Table of contents</summary>\n',
               '<p class="toc-title">Contents</p>\n', t)
    t = t.replace('</nav></details>', '</nav>', 1)
    return t


# The printed line and what a cell's word needs on it, in points: A4 less
# print.css's 16 mm margins; a character of the table's 8 pt text, rounded up
# (DejaVu Sans averages under it, and a code span's 6.7 pt DejaVu Sans Mono
# takes 4.05); and a cell's padding and borders, with a code span's own.
LINE_PT = 504.0
CHAR_PT = 4.5
CELL_PT = 20.0


def widths(table):
    """Column widths in %, from the average text length of each column.

    A column's share is raised to at least the length of its longest
    whitespace-separated word, header included, before the shares are
    normalised. Fixed layout never widens a column for its content: a word
    wider than its column was broken at a hyphen (`-fsanitize=...` came out
    as "-" over "fsanitize=..."), and a word of code, which inline_code()
    keeps whole, runs over the next cell's text instead -- which the render
    gate in tools/exam_guide.sh refuses.

    That share is a fraction of the sum of all shares, not a width, so beside
    long prose a long word still got too narrow a column: three prose columns
    (each capped at 70) and a 48-character flag gave the flag 19% of the
    line, and it ran 48 pt past the margin. So each column also has a floor
    in points -- its longest word's printed width and the cell around it --
    and a column below its floor is set to it, the others sharing what is
    left as before.
    """
    cols = {}
    longest = {}
    for row in re.findall(r'<tr[^>]*>(.*?)</tr>', table, re.S):
        for i, cell in enumerate(re.findall(r'<t[hd][^>]*>(.*?)</t[hd]>', row, re.S)):
            text = html.unescape(re.sub(r'<[^>]+>', '', cell)).strip()
            cols.setdefault(i, []).append(len(text))
            word = max((len(w) for w in text.split()), default=0)
            longest[i] = max(longest.get(i, 0), word)
    raw = [max(4.0, min(sum(v) / len(v), 70.0), float(longest[i]))
           for i, v in sorted(cols.items())]
    if not raw:
        return []
    floor = [100.0 * (longest[i] * CHAR_PT + CELL_PT) / LINE_PT
             for i in range(len(raw))]
    if sum(floor) >= 100.0:
        # Its words cannot all fit side by side: the render gate says so.
        return [100.0 * f / sum(floor) for f in floor]
    fixed = {}
    while True:
        free = [i for i in range(len(raw)) if i not in fixed]
        left = 100.0 - sum(fixed.values())
        total = sum(raw[i] for i in free)
        share = {i: left * raw[i] / total for i in free}
        under = [i for i in free if share[i] < floor[i]]
        if not under:
            break
        for i in under:
            fixed[i] = floor[i]
    return [fixed[i] if i in fixed else share[i] for i in range(len(raw))]


# Inline code breaks only between its words. Every whitespace-separated word of
# a span goes in a <span class="nb">, which print.css makes an inline-block:
# WeasyPrint breaks after any hyphen, and `sort -s -n -k1,1` came out of a
# table cell as "sort -s -n -" over "k1,1". In a paragraph or a list item,
# print.css also keeps a whole span on one line, unless it is longer than this
# many characters -- more than half a line on its own -- and so marked `wrap`:
# kept whole, it would leave a ragged gap behind it, and one longer than the
# line would wrap inside its own box.
LONG_CODE = 48


def inline_code(s):
    """Put each word of every inline <code> in a .nb span; mark long ones."""
    def mark(m):
        text = html.unescape(re.sub(r'<[^>]+>', '', m.group(1)))
        words = re.sub(r'(\S+)', r'<span class="nb">\1</span>', m.group(1))
        if len(text) <= LONG_CODE:
            return '<code>' + words + '</code>'
        return '<code class="wrap">' + words + '</code>'
    parts = re.split(r'(<pre[^>]*>.*?</pre>)', s, flags=re.S)
    for i in range(0, len(parts), 2):
        parts[i] = re.sub(r'<code>([^<]*)</code>', mark, parts[i])
    return ''.join(parts)


def colgroup(match):
    table = match.group(0)
    w = widths(table)
    if not w:
        return table
    cols = ''.join('<col style="width: %.1f%%" />' % x for x in w)
    return table.replace('<table>', '<table><colgroup>' + cols + '</colgroup>', 1)


# The table widths() once laid out too narrow (V21): three prose columns, each
# share capped at 70, beside one 47-character word of code. Invented words.
PLANTED_PROSE = ('a sentence of plain words, long enough that its share of '
                 'the line is capped at seventy characters')
PLANTED_WORD = '--an-invented-option=with,a,long,list,of,values'


# A self-check question and the answer block under it, as pandoc 2.9 writes
# them (a paragraph is one line at the build's --columns): the question's
# number, then the answer's text.
QA = re.compile(r'(<p><strong>(Q\d+)\.[^\n]*</strong></p>\n)'
                r'<details>\n<p><summary>.*?</summary></p>\n(.*?)</details>\n',
                re.S)
# Where a chapter starts: a part (h2) or a chapter (h3) heading.
CHAPTER = re.compile(r'(?=<h[23][ >])')


def answers_last(s, block):
    """Move each self-check answer to the end of its chapter.

    A reader is to answer before reading the answer, and one printed under
    its question is read first: on paper always, since paper cannot fold.
    So each chapter's answers go after everything else in it, under a
    heading of their own and in order, each made by block(id, label, text);
    the question keeps a link to its answer.
    """
    out = []
    for part in CHAPTER.split(s):
        head = re.match(r'<h[23] id="([^"]+)"', part)
        chapter = head.group(1) if head else 'top'
        found = []

        def take(m):
            ref = 'answer-%s-%s' % (chapter, m.group(2).lower())
            found.append(block(ref, 'Answer to ' + m.group(2), m.group(3)))
            return (m.group(1) + '<p class="answer-link"><a href="#%s">'
                    'Answer: end of the chapter</a></p>\n' % ref)
        part = QA.sub(take, part)
        if found:
            answers = ('<h4 id="answers-%s">Self-check answers</h4>\n'
                       % chapter + ''.join(found))
            if '</body>' in part:
                part = part.replace('</body>', answers + '</body>', 1)
            else:
                part = part + answers
        out.append(part)
    s = ''.join(out)
    stray = DETAILS.search(s)
    if stray:
        sys.exit('guide_post.py: an answer block follows no "**Qn. ...**" '
                 'question, so it has no chapter end to go to: %r'
                 % s[stray.start():stray.start() + 120])
    return s


def screen(s):
    """The page: each answer folded, at the end of its chapter."""
    return answers_last(s, lambda ref, label, text: (
        '<details id="%s"><summary>%s</summary>\n%s</details>\n'
        % (ref, label, text)))


def printed(s):
    """The PDF's HTML: answers open at the end of each chapter, tables with
    widths, code kept whole."""
    s = answers_last(s, lambda ref, label, text: (
        '<div class="answer" id="%s"><p class="answer-label">%s</p>\n%s</div>\n'
        % (ref, label, text)))
    s = re.sub(r'<table>.*?</table>', colgroup, s, flags=re.S)
    return inline_code(s)


RENDER = {'screen': screen, 'print': printed}

# A chapter as pandoc 2.9 writes one: a self-check question and its answer,
# a section after them, then the next chapter. Invented words.
PLANTED_CHAPTER = ('<h3 id="planted">Planted</h3>\n'
                   '<h4 id="self-check-planted">Self-check</h4>\n'
                   '<p><strong>Q1. A planted question?</strong></p>\n'
                   '<details>\n<p><summary>Answer</summary></p>\n\n'
                   '<p>A planted answer.</p>\n</details>\n'
                   '<h4 id="pitfalls-planted">Pitfalls</h4>\n'
                   '<p>A planted pitfall.</p>\n'
                   '<h3 id="next">Next</h3>\n<p>The next chapter.</p>\n')


def self_check(css_path):
    """The layout rules no build of the guide as it is can show broken.

    The render gate reads the PDF of the guide as it is: a table the guide
    does not hold yet, or a code block it does not hold yet, is never
    rendered, so a rule that stopped holding goes unseen until one is
    written; and nothing reads where an answer lands. So the three rules are
    checked here on their own, before every build (tools/exam_guide.sh):
      - widths() gives a column at least the width its longest word prints,
        on the planted table above (V21: it gave the word's column 119.6 pt
        of the 231.5 it needs, and the gate refused the build);
      - print.css keeps every block with a language unfolded (V20: a folded
        recipe line is another command, and the gate cannot see a fold);
      - both renderings print a self-check answer once, after the rest of
        its chapter, on the planted chapter above (the PDF printed each
        answer open under its question, read before it was answered).

    Returns a list of sentences, empty when all three hold.
    """
    problems = []
    cells = ''.join('<td>%s</td>' % PLANTED_PROSE for _ in range(3))
    table = ('<table><tr><th>One</th><th>Two</th><th>Three</th><th>Word</th></tr>'
             '<tr>%s<td><code>%s</code></td></tr></table>' % (cells, PLANTED_WORD))
    w = widths(table)
    need = len(PLANTED_WORD) * CHAR_PT + CELL_PT
    got = w[3] * LINE_PT / 100.0 if len(w) == 4 else 0.0
    if got + 0.01 < need:
        problems.append('widths() gives a %d-character word beside three prose '
                        'columns %.1f pt of the %.1f it prints in: a column is '
                        'never narrower than its longest word (V21)'
                        % (len(PLANTED_WORD), got, need))
    for mode, render in sorted(RENDER.items()):
        out = render(PLANTED_CHAPTER)
        at = [out.find(t) for t in ('A planted question', 'A planted pitfall',
                                    'A planted answer', '<h3 id="next"')]
        if -1 in at or at != sorted(at) or out.count('A planted answer') != 1:
            problems.append('the %s rendering does not print a self-check '
                            'answer once, at the end of its chapter: a '
                            'reader answers before reading it, and an '
                            'answer printed under its question is read '
                            'first' % mode)
    css = open(css_path, encoding='utf-8').read()
    css = re.sub(r'/\*.*?\*/', '', css, flags=re.S)
    if not re.search(r'(^|[\s,}])pre\[class\]\s*(,[^{]*)?\{[^}]*white-space:\s*pre\s*[;}]', css):
        problems.append('%s does not keep a code block with a language '
                        'unfolded (pre[class] { white-space: pre; }): folded, '
                        'a recipe line is another command, and the render gate '
                        'cannot see a fold (V20)' % css_path)
    return problems


def main():
    mode = sys.argv[1]
    if mode == 'print-template':
        sys.stdout.write(print_template(sys.argv[2], sys.argv[3]))
        return
    if mode == 'self-check':
        problems = self_check(sys.argv[2])
        for p in problems:
            print('  ' + p)
        sys.exit(1 if problems else 0)
    if mode not in RENDER:
        sys.exit('guide_post.py: unknown mode ' + mode)
    path = sys.argv[2]
    s = open(path, encoding='utf-8').read()
    open(path, 'w', encoding='utf-8').write(RENDER[mode](s))


if __name__ == '__main__':
    main()
