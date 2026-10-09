#!/usr/bin/env python3
"""The PDF's render gate (tools/exam_guide.sh): is every word readable, once?

    pdftotext -bbox-layout FILE.pdf - | render_check.py SOURCE.html

Reads the word boxes and lines pdftotext prints, and fails on three faults
WeasyPrint renders without a word of warning:

  - two words on one page overlap: a table column narrower than its longest
    word, which fixed layout lets run over the next cell;
  - a word runs past the right margin: a word of code longer than the line,
    which print.css never breaks, or a line of a code block with a language
    (```sh, ```c, ```makefile) longer than the page, which it never folds
    (folded, "> /dev/" over "null 2>&1" is another command, and a recipe
    line a broken Makefile). The margins in print.css are the same on
    both sides, so the right one is taken from the left: the smallest left
    edge of any word;
  - a line ends with the very words the next line starts with, and SOURCE.html,
    the page the PDF was rendered from, never has them twice in a row: text
    WeasyPrint 54 printed twice at a line break.

Prints each fault with its page and its words and exits 1 if there is any;
exits 2 on a wrong call or on input that holds no words at all.
"""
import html
import re
import sys

PAGE = re.compile(r'<page width="([\d.]+)"[^>]*>(.*?)</page>', re.S)
LINE = re.compile(r'<line [^>]*>(.*?)</line>', re.S)
WORD = re.compile(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" '
                  r'yMax="([\d.]+)">(.*?)</word>', re.S)
# A word, or one character of punctuation: a code span's padding makes
# pdftotext split "lines;" and "./books" differently from the source.
TOKEN = re.compile(r'\w+|\S')
# Points. Neighbouring words touch (the TOC's leader dots share an edge); a
# real collision is several points deep.
SLACK = 0.5


def source_text(path):
    """SOURCE.html's text as one string of tokens, each followed by a space."""
    s = open(path, encoding='utf-8').read()
    s = re.sub(r'<(br|p|div|li|tr|td|th|h\d|pre|ul|ol|table|nav)\b[^>]*>', ' ', s)
    s = html.unescape(re.sub(r'<[^>]+>', '', s))
    return ' ' + ' '.join(TOKEN.findall(s)) + ' '


def overlaps(n, width, left, words, faults):
    words = sorted(words, key=lambda w: w[1])
    for i, a in enumerate(words):
        if a[2] > width - left + SLACK:
            faults.append('page %d: "%s" runs %.1f pt past the right margin'
                          % (n, a[4], a[2] - (width - left)))
        # Sorted by top edge: once a word starts below a's bottom edge, so
        # does every word after it.
        for b in words[i + 1:]:
            if b[1] >= a[3] - SLACK:
                break
            dx = min(a[2], b[2]) - max(a[0], b[0])
            dy = min(a[3], b[3]) - max(a[1], b[1])
            if dx > SLACK and dy > SLACK:
                faults.append('page %d: "%s" and "%s" overlap (%.1f x %.1f pt)'
                              % (n, a[4], b[4], dx, dy))


def repeats(n, lines, source, faults):
    for a, b in zip(lines, lines[1:]):
        for k in range(min(len(a), len(b)), 0, -1):
            if a[-k:] == b[:k]:
                # Two lines that are nothing but the same words are a column
                # pdftotext read down: `int` over `int` in a block of aligned
                # declarations, `silent` over `silent` in a table.
                if len(a) == k == len(b):
                    break
                twice = ' ' + ' '.join(a[-k:] + b[:k]) + ' '
                if twice not in source:
                    faults.append('page %d: printed twice at a line break: "%s"'
                                  % (n, ' '.join(b[:k])))
                break


def main():
    if len(sys.argv) != 2:
        print('usage: pdftotext -bbox-layout FILE.pdf - | render_check.py SOURCE.html',
              file=sys.stderr)
        sys.exit(2)
    pages = []
    for width, body in PAGE.findall(sys.stdin.read()):
        lines = [[(float(a), float(b), float(c), float(d), html.unescape(t))
                  for a, b, c, d, t in WORD.findall(line)]
                 for line in LINE.findall(body)]
        pages.append((float(width), lines))
    words = [w for _, lines in pages for line in lines for w in line]
    if not words:
        print('render_check.py: no words in the input -- is it pdftotext -bbox-layout output?',
              file=sys.stderr)
        sys.exit(2)
    left = min(w[0] for w in words)
    source = source_text(sys.argv[1])
    faults = []
    for n, (width, lines) in enumerate(pages, 1):
        overlaps(n, width, left, [w for line in lines for w in line], faults)
        tokens = [TOKEN.findall(' '.join(w[4] for w in line)) for line in lines]
        repeats(n, [t for t in tokens if t], source, faults)
    for f in faults:
        print('  ' + f)
    sys.exit(1 if faults else 0)


if __name__ == '__main__':
    main()
