# ------------------------------------- conventions: a reading named in a hint
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The owner's ruling of 2026-10-03 (AGENTS.md section 2): only the strict
# target that tests a reading states it, in its own hint and its row of
# docs/reference.md, as "this harness's reading", never as the subject's,
# and no basic hint names it. Before the rule, a reading went by seven names,
# and two of Rush 02's rows stating a strict reading were keyed to the basic
# case beside it as well. cvn holds one toy project, each shape once: a
# program whose keyed clues.tsv has a row keyed to its strict case alone
# (quiet), one keyed to its basic case too (reported), one keyed to nothing
# (reported), one naming the reading by a verb (reported); a function whose
# basic clues.tsv names it (reported) and whose reading's own file does
# (quiet); a diff legend that names it by the label (quiet) and by another
# name wrapped over two lines (reported); a shell exercise whose check.sh
# prints the label (reported) and whose reading's script does (quiet); a
# runner that calls a rule of its own a reading (reported); a raised
# target's why stating its reading with a verb (reported); and a page that
# names it by another name (reported), names the target that holds one
# (quiet), and describes a target in a verb (quiet: pages may). Wave 6's
# review added: a runner naming it over two echo lines, as the reference's,
# or as what "this check reads" a sentence as (reported); a clue file a call
# hands its basic tests and a reading hands too (reported); a row keyed to a
# readings corpus's --case (quiet); the label above strict, in a row keyed
# to a robust case and in a robust reading's own file (reported under its
# own heading), and in a readings corpus's legend raised to robust
# (reported there, V42's review); the one exemption by name, which the toy
# lacks (reported as one that exempts nothing); and a reading stated with
# the label in a row of reference.md no target owns and on another page
# (reported), and in the row of the target that tests it or a raised
# target's (quiet).
_cvr_m=c-piscine/c-piscine-c-84
_cvr=$WORK/cvn/$_cvr_m/tests
mkdir -p "$WORK/cvn/tools" "$WORK/cvn/docs" "$_cvr/ex00" "$_cvr/ex01" "$_cvr/ex02" "$_cvr/ex03" "$_cvr/ex04" \
	"$_cvr/ex05"
cv_submit "$_cvr_m" > "$WORK/cvn/tools/submit.sh"
printf '%s\n' \
	'c_program(num = "00", name = "toy", cases = [' \
	'    {"name": "plain", "args": ["1"], "expected": "plain.txt", "clues": "clues.tsv"},' \
	'    {"name": "open", "args": ["2"], "expected": "open.txt", "level": 2, "clues": "clues.tsv"},' \
	'    {"name": "wide", "args": ["3"], "expected": "wide.txt", "level": 3, "clues": "clues.tsv"},' \
	'])' \
	'' \
	'hand_test(' \
	'    name = "ex00_readings",' \
	'    args = [' \
	'        "--case",' \
	'        "readings",' \
	'    ],' \
	')' \
	'' \
	'c_function(' \
	'    num = "01",' \
	'    fn = "ft_toy",' \
	'    test = "test_toy.c",' \
	'    clues = "clues.tsv",' \
	'    readings = [{' \
	'        "name": "either",' \
	'        "main": "test_toy_either.c",' \
	'        "expected": "either.txt",' \
	'        "clues": "clues_either.tsv",' \
	'        "level": 2,' \
	'    }, {' \
	'        "name": "wide",' \
	'        "main": "test_toy_wide.c",' \
	'        "expected": "wide.txt",' \
	'        "clues": "clues_wide.tsv",' \
	'        "level": 3,' \
	'    }],' \
	')' \
	'' \
	'c_function(' \
	'    num = "03",' \
	'    fn = "ft_toy_too",' \
	'    test = "test_toy_too.c",' \
	'    clues = "clues_shared.tsv",' \
	'    readings = [{' \
	'        "name": "either",' \
	'        "main": "test_toy_too_either.c",' \
	'        "expected": "either.txt",' \
	'        "clues": "clues_shared.tsv",' \
	'        "level": 2,' \
	'    }],' \
	')' \
	'' \
	'shell_exercise(' \
	'    num = "02",' \
	'    mode = "check",' \
	'    readings = {"literal": "literal.sh"},' \
	')' \
	'' \
	'c_diff(' \
	'    num = "04",' \
	'    fn = "ft_toy",' \
	'    harness = "diff_toy.c",' \
	'    oracle_fn = "toy",' \
	'    diff_clues = "diff_clues.txt",' \
	'    readings = {"oracle_fn": "toy_readings", "diff_clues": "diff_clues_readings.txt"},' \
	')' \
	'' \
	'c_diff(' \
	'    num = "05",' \
	'    fn = "ft_toy_raised",' \
	'    harness = "diff_toy_raised.c",' \
	'    oracle_fn = "toy_raised",' \
	'    readings = {' \
	'        "diff_clues": "diff_clues_readings.txt",' \
	'        "level": 3,' \
	'        "oracle_fn": "toy_raised_readings",' \
	'    },' \
	')' > "$WORK/cvn/$_cvr_m/BUILD.bazel"
printf 'x\n' > "$_cvr/ex00/plain.txt"
printf 'y\n' > "$_cvr/ex00/open.txt"
_cvr_l="this harness's reading"
{
	printf 'Which sentence decides? %s, at strict: an open toy is a toy.\topen\n' "$_cvr_l"
	printf 'Which sentence decides? %s, at strict: a toy.\tplain\topen\n' "$_cvr_l"
	printf 'Is %s the one you took?\n' "$_cvr_l"
	printf 'Which sentence decides? It never says, and strict reads it as a toy.\tplain\n'
	printf 'Which sentence decides? It never says, and this harness reads the sentence as no.\tplain\n'
	printf 'Which sentence decides? %s, at strict: the corpus counts.\treadings\n' "$_cvr_l"
	printf 'Which sentence decides? %s, at robust: a wide toy.\twide\n' "$_cvr_l"
} > "$_cvr/ex00/clues.tsv"
printf 'z\n' > "$_cvr/ex00/wide.txt"
printf 'Which sentence decides? %s, at robust: wide counts.\tcase\n' "$_cvr_l" \
	> "$_cvr/ex01/clues_wide.tsv"
printf 'Which sentence decides? %s, at strict: either way counts.\n' "$_cvr_l" \
	> "$_cvr/ex03/clues_shared.tsv"
printf 'case\tz\n' > "$_cvr/ex01/either.txt"
printf 'Which sentence decides? %s is that a toy counts.\n' "$_cvr_l" > "$_cvr/ex01/clues.tsv"
# Its second row's 69th to 71st bytes are one dash: a report cuts its
# excerpt at 70 bytes, and before the dash, never inside it.
printf 'Which sentence decides? %s is that a toy counts,\342\200\224 every one.\n' "$_cvr_l" \
	>> "$_cvr/ex01/clues.tsv"
printf 'Which sentence decides? %s, at strict: either way counts.\tcase\n' "$_cvr_l" \
	> "$_cvr/ex01/clues_either.tsv"
{
	printf '  One toy per line.\n'
	printf '    * any of them -> %s, at strict, is that a toy is a\n' "$_cvr_l"
	printf '                     toy. Which sentence decides?\n'
	printf '    * only big toys -> the reading this\n'
	printf '                     repo takes is that big toys count.\n'
} > "$_cvr/ex01/diff_clues.txt"
# A c_diff whose plain corpus's legend names the reading, wrapped over two
# lines (reported: its corpus holds what every reading agrees on, V42), and
# its readings corpus's legend, which states it (quiet).
printf '%s\n' '  One toy per line.' "    * any of them -> which sentence decides? this harness's" \
	'                     reading, at strict, is that a toy counts.' > "$_cvr/ex04/diff_clues.txt"
printf '  Every toy here is open.\n    * any of them -> %s, at strict, is that it counts.\n' "$_cvr_l" \
	> "$_cvr/ex04/diff_clues_readings.txt"
# ...and a readings corpus raised to robust ("level": 3), whose legend states
# the reading: printed above strict, where only a convention of this repo's
# sits (reported). C 04's and C 07's ASan twins once printed a strict
# reading's legend at robust; they are handed none now (defs.bzl).
printf '  Every toy here is wide.\n    * any of them -> %s is that it counts.\n' "$_cvr_l" \
	> "$_cvr/ex05/diff_clues_readings.txt"
printf '#!/bin/sh\nprintf "  CHECK: %%s, %s at strict: literal\\n" "$1"\n' "$_cvr_l" \
	> "$_cvr/ex02/literal.sh"
printf '#!/bin/sh\n# %s is not named in a comment.\nprintf "  CHECK: %%s, %s: either\\n" "$1"\n' \
	"$_cvr_l" "$_cvr_l" > "$_cvr/ex02/check.sh"
printf '#!/bin/sh\nset -u\necho "it expects 0, which is this repo'"'"'s reading."\n' \
	> "$WORK/cvn/tools/probe_reading.sh"
{
	printf '#!/bin/sh\nset -u\n'
	printf 'echo "  Expecting 3 is this"\n'
	printf 'echo "  repo'"'"'s reading, checked above basic."\n'
	printf 'echo "  It differs from the reference'"'"'s reading of the toy."\n'
	printf 'echo "  It never says, and this check reads the sentence as a toy."\n'
	printf 'echo "  This harness reads the toy from standard input, one line at a time."\n'
	printf 'echo "  so neither of the two rules this check reads could be read."\n'
} > "$WORK/cvn/tools/probe_wrapped.sh"
# A runner that states a reading after its label (V41's review): Rush 01's
# runner printed "Under this harness's reading (its hints below), the values
# are single digits ..." (line 3, reported), and the same shapes after a
# colon over two lines, after "is", and with no comma (reported); beside
# them the label pointing at the input at hand, at the hints in an awk
# string's \047, and at whose a rule named first is (quiet).
{
	printf '#!/bin/sh\nset -u\n'
	printf 'echo "  Under %s (its hints below), the values are single"\n' "$_cvr_l"
	printf 'echo "  digits."\n'
	printf 'echo "  It printed a grid, but under %s, this argument is not the one shape."\n' "$_cvr_l"
	printf 'echo "  It printed a grid, but under this harness'"'"'s"\n'
	printf 'echo "  reading: the values are digits."\n'
	printf '%s\n' "echo '   under this harness\\047s reading, which its hints below state:'"
	printf 'echo "  That a toy counts is %s, never the subject'"'"'s."\n' "$_cvr_l"
	printf 'echo "  %s is that a toy counts."\n' "$_cvr_l"
	printf 'echo "  under %s the values are digits."\n' "$_cvr_l"
} > "$WORK/cvn/tools/probe_label.sh"
{
	printf '# Reference\n\n## Targets raised above their layer\n\n'
	printf '| target | level | why |\n|---|---|---|\n'
	printf '| `//%s:ex00_open_output` | strict | an open toy: this target reads it as a toy |\n' "$_cvr_m"
	printf '\n| suffix | layer | level | what it checks |\n|---|---|---|---|\n'
	printf '| `_toy` | `output` | strict | a toy sentence: %s is that a toy counts |\n' "$_cvr_l"
	printf '| Toy ex00 | either way | `exNN_literal`, %s: a toy counts |\n' "$_cvr_l"
} > "$WORK/cvn/docs/reference.md"
{
	printf '# Toys\n\nAt strict, `ex00_open_output` holds one reading, as this repo'"'"'s reading.\n'
	printf 'This table reads the map from standard input,\n'
	printf 'and the target that holds one reading names it.\n'
	printf 'The toy'"'"'s open sentence: this harness'"'"'s\n'
	printf 'reading is that a toy counts.\n'
	printf 'Its hints say which, as %s and never the subject'"'"'s.\n' "$_cvr_l"
	printf '| Toy ex00 | either way | `exNN_literal`, %s: a toy counts |\n' "$_cvr_l"
	# Two lines whose 79th to 81st bytes are one dash (the excerpt is 80):
	# a reading stated on one line, and over two.
	_cvr_p='A toy counted twice is a toy all the same, and the rest goes on as it went, so'
	printf '%s\342\200\224 %s is that a toy counts.\n' "$_cvr_p" "$_cvr_l"
	printf '%s\342\200\224 and so this harness'"'"'s\nreading is that a toy counts.\n' "$_cvr_p"
} > "$WORK/cvn/README.md"
# The same dash at the same bytes in what a runner prints: another name for
# a reading (3, and 5 over two lines), and a reading stated after its label
# (8, and 10 over two lines). A comment line parts them.
_cvr_e='echo "  A toy counted twice is a toy all the same, and the rest goes on as it,'
{
	printf '#!/bin/sh\nset -u\n'
	printf '%s\342\200\224 this repo'"'"'s reading."\n#\n' "$_cvr_e"
	printf '%s\342\200\224 is this"\necho "  repo'"'"'s reading, checked above basic."\n#\n' "$_cvr_e"
	printf '%s\342\200\224 under %s: the values are digits."\n#\n' "$_cvr_e" "$_cvr_l"
	printf '%s\342\200\224 under this harness'"'"'s"\necho "  reading: the values are digits."\n' "$_cvr_e"
} > "$WORK/cvn/tools/probe_cut.sh"
# A first-red row whose 59th to 61st bytes are one dash (the excerpt is 60).
printf 'A toy is counted once, whatever its size or colour may be,\342\200\224 every one.\n' \
	>> "$_cvr/ex01/clues.tsv"
# A sentence wraps over a line no student is shown, or after a blank: a
# legend's or a script's # line, which the rules ended a sentence at (a
# page's heading still ends one), and a legend line's trailing blank,
# which the legend rules read as two spaces. Reported: another name for a
# reading over a legend's # line (ex01/diff_clues.txt 6, onto 8) and a
# runner's comment (probe_wrapped.sh 9, onto 11); a reading stated after
# its label over a runner's comment (probe_label.sh 12, onto 14); the
# label wrapped after a trailing blank in a plain legend (ex04 4, onto 5)
# and in a legend raised above strict (ex05 3, onto 4), and over a
# legend's # line (ex04 6, onto 8); and the label wrapped over two echo
# lines of the check.sh a basic test runs (ex02 4, onto 5).
printf '%s\n' '    * only small toys -> the reading this' '  # a note for maintainers' \
	'                     repo takes is that small toys count.' >> "$_cvr/ex01/diff_clues.txt"
printf '%s\n' 'echo "  Expecting 4 is this"' '# a comment between' \
	'echo "  repo'"'"'s reading, checked above basic."' >> "$WORK/cvn/tools/probe_wrapped.sh"
printf '%s\n' 'echo "  It printed a grid, but under this harness'"'"'s"' '# a comment between' \
	'echo "  reading: the values are digits."' >> "$WORK/cvn/tools/probe_label.sh"
printf '%s\n' "    * only big toys -> which sentence decides? this harness's " \
	'                     reading, at strict, is that big toys count.' \
	"    * only odd toys -> which sentence decides? this harness's" '  # a note for maintainers' \
	'                     reading, at strict, is that odd toys count.' >> "$_cvr/ex04/diff_clues.txt"
printf '%s\n' "    * big ones -> this harness's " '                  reading is that they count too.' \
	>> "$_cvr/ex05/diff_clues_readings.txt"
printf '%s\n' 'echo "  CHECK: this harness'"'"'s"' 'echo "  reading: either"' >> "$_cvr/ex02/check.sh"
if st_mine; then
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvn" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvn.out" 2>&1
fi
want_out "conventions: a reading named by a verb in a keyed row is reported" \
	"$_cvr_m/tests/ex00/clues.tsv:4:" -- cvi_rule cvn 'a reading is named in other words'
want_out "conventions: ...and by another name wrapped over a legend's lines" \
	"$_cvr_m/tests/ex01/diff_clues.txt:4:" -- cvi_rule cvn 'a reading is named in other words'
want_out "conventions: ...and by a runner" \
	'tools/probe_reading.sh:3:' -- cvi_rule cvn 'a reading is named in other words'
want_out "conventions: ...and by a runner over two echo lines" \
	'tools/probe_wrapped.sh:3: echo "  Expecting 3 is this" (wrapped onto line 4)' -- \
	cvi_rule cvn 'a reading is named in other words'
want_out "conventions: ...and as the reference's" \
	'tools/probe_wrapped.sh:5:' -- cvi_rule cvn 'a reading is named in other words'
want_out "conventions: ...and as what this check reads a sentence as" \
	'tools/probe_wrapped.sh:6:' -- cvi_rule cvn 'a reading is named in other words'
want_out "conventions: ...and over a legend's # line" \
	"$_cvr_m/tests/ex01/diff_clues.txt:6:     * only small toys -> the reading this (wrapped onto line 8)" -- \
	cvi_rule cvn 'a reading is named in other words'
want_out "conventions: ...and over a runner's comment" \
	'tools/probe_wrapped.sh:9: echo "  Expecting 4 is this" (wrapped onto line 11)' -- \
	cvi_rule cvn 'a reading is named in other words'
want_out "conventions: ...and as what this harness reads it as, words between" \
	"$_cvr_m/tests/ex00/clues.tsv:5:" -- cvi_rule cvn 'a reading is named in other words'
want_broken_none "conventions: ...never what this harness reads from where" \
	'tools/probe_wrapped.sh:7:' -- cvi_rule cvn 'a reading is named in other words'
want_broken_none "conventions: ...nor the rules a check reads" \
	'tools/probe_wrapped.sh:8:' -- cvi_rule cvn 'a reading is named in other words'
want_out "conventions: ...and by a raised target's why" \
	'docs/reference.md:7:' -- cvi_rule cvn 'a reading is named in other words'
want_out "conventions: ...and by a page" \
	'README.md:3:' -- cvi_rule cvn 'a reading is named in other words'
want_broken_none "conventions: ...never a page's own verbs" \
	'README.md:4:' -- cvi_rule cvn 'a reading is named in other words'
want_broken_none "conventions: ...nor a page naming the target that holds one" \
	'README.md:5:' -- cvi_rule cvn 'a reading is named in other words'
want_out "conventions: a runner stating a reading after its label is reported" \
	'tools/probe_label.sh:3:' -- cvi_rule cvn 'a runner states a reading after its label'
want_out "conventions: ...and after a colon, over two lines" \
	'tools/probe_label.sh:6: echo "  It printed a grid, but under this harness'"'"'s" (wrapped onto line 7)' -- \
	cvi_rule cvn 'a runner states a reading after its label'
want_out "conventions: ...and after is" \
	'tools/probe_label.sh:10:' -- cvi_rule cvn 'a runner states a reading after its label'
want_out "conventions: ...and with no comma" \
	'tools/probe_label.sh:11:' -- cvi_rule cvn 'a runner states a reading after its label'
want_broken_none "conventions: ...never the label pointing at this input" \
	'tools/probe_label.sh:5:' -- cvi_rule cvn 'a runner states a reading after its label'
want_broken_none "conventions: ...nor at the hints, in an awk string" \
	'tools/probe_label.sh:8:' -- cvi_rule cvn 'a runner states a reading after its label'
want_broken_none "conventions: ...nor saying whose a rule named first is" \
	'tools/probe_label.sh:9:' -- cvi_rule cvn 'a runner states a reading after its label'
want_out "conventions: ...and after a colon, over a comment" \
	'tools/probe_label.sh:12: echo "  It printed a grid, but under this harness'"'"'s" (wrapped onto line 14)' -- \
	cvi_rule cvn 'a runner states a reading after its label'
# A page states a reading only in its target's own row of reference.md: the
# target-name table stated two shell readings a second time (wave 6).
want_out "conventions: a reading stated in a row of reference.md no target owns is reported" \
	'docs/reference.md:11:' -- cvi_rule cvn 'a page states a reading outside'
want_broken_none "conventions: ...never in the row of the target that tests it" \
	'docs/reference.md:12:' -- cvi_rule cvn 'a page states a reading outside'
want_broken_none "conventions: ...nor in a raised target's row" \
	'docs/reference.md:7:' -- cvi_rule cvn 'a page states a reading outside'
want_out "conventions: ...and on another page, over two lines" \
	'README.md:6: The toy'"'"'s open sentence: this harness'"'"'s (wrapped onto line 7)' -- \
	cvi_rule cvn 'a page states a reading outside'
want_broken_none "conventions: ...never a page saying whose a reading is" \
	'README.md:8:' -- cvi_rule cvn 'a page states a reading outside'
want_out "conventions: ...while a target's row on a page other than reference.md is" \
	'README.md:9:' -- cvi_rule cvn 'a page states a reading outside'
want_broken_none "conventions: ...nor a legend's line that says the label" \
	"$_cvr_m/tests/ex01/diff_clues.txt:2:" -- cvi_rule cvn 'a reading is named in other words'
want_out "conventions: the label in a row keyed to a basic case is reported" \
	"$_cvr_m/tests/ex00/clues.tsv:2:" -- cvi_rule cvn 'a hint a basic test prints names'
want_out "conventions: ...and in a row keyed to nothing" \
	'(keyed to no case, so every case)' -- cvi_rule cvn 'a hint a basic test prints names'
want_out "conventions: ...and in a basic function's clue file" \
	"$_cvr_m/tests/ex01/clues.tsv:1:" -- cvi_rule cvn 'a hint a basic test prints names'
# The report line, with its end made visible, read byte by byte, and the
# run's status.
cvn_line_end() {
	_cvn_l=$(cv_saved "$WORK/cvn.out" env LC_ALL=C grep -F -- "$1")
	_cvn_rc=$?
	[ -z "$_cvn_l" ] || printf '%s\n' "$_cvn_l" | LC_ALL=C sed 's/$/|end/'
	return "$_cvn_rc"
}
want_out "conventions: ...its excerpt cut before a character, never inside one" \
	'is that a toy counts,|end' -- cvn_line_end "$_cvr_m/tests/ex01/clues.tsv:2:"
want_out "conventions: ...as every report of a reading cuts it: a runner's line" \
	'goes on as it,|end' -- cvn_line_end 'tools/probe_cut.sh:3:'
want_out "conventions: ...a runner's line wrapped onto the next" \
	'goes on as it, (wrapped onto line 6)|end' -- cvn_line_end 'tools/probe_cut.sh:5:'
want_out "conventions: ...a runner's line stating it after its label" \
	'goes on as it,|end' -- cvn_line_end 'tools/probe_cut.sh:8:'
want_out "conventions: ...and that line wrapped onto the next" \
	'goes on as it, (wrapped onto line 11)|end' -- cvn_line_end 'tools/probe_cut.sh:10:'
want_out "conventions: ...a page's line stating it" \
	'goes on as it went, so|end' -- cvn_line_end 'README.md:10:'
want_out "conventions: ...and that line wrapped onto the next" \
	'goes on as it went, so (wrapped onto line 12)|end' -- cvn_line_end 'README.md:11:'
want_out "conventions: a first-red row's excerpt is cut before a character too" \
	'or colour may be,...|end' -- cvn_line_end 'line 3 (no question): A toy is counted once'
want_out "conventions: ...and in the check.sh a basic output test runs" \
	"$_cvr_m/tests/ex02/check.sh:3:" -- cvi_rule cvn 'a hint a basic test prints names'
want_out "conventions: ...wrapped over two of its echo lines too" \
	"$_cvr_m/tests/ex02/check.sh:4: echo \"  CHECK: this harness's\" (wrapped onto line 5)" -- \
	cvi_rule cvn 'a hint a basic test prints names'
want_broken_none "conventions: ...never in a row keyed to strict cases alone" \
	"$_cvr_m/tests/ex00/clues.tsv:1:" -- cvi_rule cvn 'a hint a basic test prints names'
want_broken_none "conventions: ...nor in a reading's own clue file" \
	'clues_either.tsv' -- cvi_rule cvn 'a hint a basic test prints names'
want_broken_none "conventions: ...nor in the script a shell reading names" \
	'literal.sh' -- cvi_rule cvn 'a hint a basic test prints names'
want_broken_none "conventions: ...nor in a check script's comment" \
	"$_cvr_m/tests/ex02/check.sh:2:" -- cvi_rule cvn 'a hint a basic test prints names'
want_out "conventions: ...and in a clue file a call hands its basic tests and a reading too" \
	"$_cvr_m/tests/ex03/clues_shared.tsv:1:" -- cvi_rule cvn 'a hint a basic test prints names'
want_broken_none "conventions: ...never in a row keyed to a readings corpus's --case" \
	"$_cvr_m/tests/ex00/clues.tsv:6:" -- cvi_rule cvn 'a hint a basic test prints names'
want_broken_none "conventions: ...which is no reading above strict either" \
	"$_cvr_m/tests/ex00/clues.tsv:6:" -- cvi_rule cvn 'a hint a test above strict prints'
# Above strict, the ruling's "strict target" is passed: a case there is a
# convention of this repo's, or a reading at the wrong level.
want_out "conventions: the label in a row keyed to a case above strict is reported" \
	"$_cvr_m/tests/ex00/clues.tsv:7:" -- cvi_rule cvn 'a hint a test above strict prints'
want_out "conventions: ...and in a reading's own clue file, at robust" \
	"$_cvr_m/tests/ex01/clues_wide.tsv:1:" -- cvi_rule cvn 'a hint a test above strict prints'
want_broken_none "conventions: ...never a reading's at strict" \
	'clues_either.tsv' -- cvi_rule cvn 'a hint a test above strict prints'
want_broken_none "conventions: ...nor one keyed to a strict case" \
	"$_cvr_m/tests/ex00/clues.tsv:1:" -- cvi_rule cvn 'a hint a test above strict prints'
want_out "conventions: ...and in a readings corpus's legend raised above strict" \
	"$_cvr_m/tests/ex05/diff_clues_readings.txt:2:" -- cvi_rule cvn 'a hint a test above strict prints'
want_out "conventions: ...wrapped after a trailing blank too" \
	"$_cvr_m/tests/ex05/diff_clues_readings.txt:3:     * big ones -> this harness's  (wrapped onto line 4)" -- \
	cvi_rule cvn 'a hint a test above strict prints'
want_broken_none "conventions: ...never a readings corpus's legend at strict" \
	"$_cvr_m/tests/ex04/diff_clues_readings.txt" -- cvi_rule cvn 'a hint a test above strict prints'
want_out "conventions: a plain diff corpus's legend naming the reading is reported" \
	"$_cvr_m/tests/ex04/diff_clues.txt:2:" -- cvi_rule cvn 'a plain diff corpus'
want_out "conventions: ...wrapped after a trailing blank" \
	"$_cvr_m/tests/ex04/diff_clues.txt:4:" -- cvi_rule cvn 'a plain diff corpus'
want_out "conventions: ...or over a # line, which no run prints" \
	"$_cvr_m/tests/ex04/diff_clues.txt:6:" -- cvi_rule cvn 'a plain diff corpus'
want_broken_none "conventions: ...never its readings corpus's legend" \
	'diff_clues_readings.txt' -- cvi_rule cvn 'a plain diff corpus'

