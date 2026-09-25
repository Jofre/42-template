#!/usr/bin/env python3
"""Post-processing for the final-exam guide's two renderings (tools/exam_guide.sh).

    guide_post.py print-template PAGE_TEMPLATE PRINT_CSS   -> stdout
    guide_post.py screen FILE.html                         (in place)
    guide_post.py print FILE.html                          (in place)

print-template derives the PDF's pandoc template from the page's: the same
styles, no web fonts (the PDF is built offline), print.css laid over them, and
a plain "Contents" list instead of the collapsible one.

screen and print fix what this pandoc (2.9) does to the guide's answer blocks:
it wraps <summary> in a paragraph. The screen page gets the <details> back as
written; the PDF gets them as always-open answer boxes, since paper cannot
click. print also gives every table explicit column widths -- print.css lays
tables out `fixed`, and fixed layout without widths makes every column equal.
"""
import html
import re
import sys

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


def widths(table):
    """Column widths in %, from the average text length of each column."""
    cols = {}
    for row in re.findall(r'<tr[^>]*>(.*?)</tr>', table, re.S):
        for i, cell in enumerate(re.findall(r'<t[hd][^>]*>(.*?)</t[hd]>', row, re.S)):
            text = html.unescape(re.sub(r'<[^>]+>', '', cell)).strip()
            cols.setdefault(i, []).append(len(text))
    raw = [max(4.0, min(sum(v) / len(v), 70.0)) for _, v in sorted(cols.items())]
    total = sum(raw)
    return [100.0 * x / total for x in raw] if total else []


def colgroup(match):
    table = match.group(0)
    w = widths(table)
    if not w:
        return table
    cols = ''.join('<col style="width: %.1f%%" />' % x for x in w)
    return table.replace('<table>', '<table><colgroup>' + cols + '</colgroup>', 1)


def main():
    mode = sys.argv[1]
    if mode == 'print-template':
        sys.stdout.write(print_template(sys.argv[2], sys.argv[3]))
        return
    path = sys.argv[2]
    s = open(path, encoding='utf-8').read()
    if mode == 'screen':
        s = DETAILS.sub(r'<details><summary>\1</summary>\n', s)
    elif mode == 'print':
        s = DETAILS.sub(r'<div class="answer"><p class="answer-label">\1</p>', s)
        s = s.replace('</details>', '</div>')
        s = re.sub(r'<table>.*?</table>', colgroup, s, flags=re.S)
    else:
        sys.exit('guide_post.py: unknown mode ' + mode)
    open(path, 'w', encoding='utf-8').write(s)


if __name__ == '__main__':
    main()
