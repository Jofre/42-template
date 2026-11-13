# ------------------------------------ conventions: clue labels, program cases
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A clue row may name a program case (c_program's "name"), whose rows are bare
# lines, or "line N" of an output (finding 155); a label naming neither is a
# gate that never opens. An invented c_program with two cases, one of them
# written over several lines as buildifier lays it out, and a clue file with
# no expected.txt beside it: a case's name and any "line N" are accepted, a
# misspelt name is reported. And "line N" past an expected.txt's end.
# Case "one" is labeled (its rows are keyed by their first fields), on one
# line; case "two" is not, over several, with a dict of its own inside it.
printf '%s\n' 'c_program(' '    num = "10",' '    name = "toy",' '    cases = [' \
	'        {"name": "one", "expected": "a.txt", "labeled": True},' '        {' \
	'            "name": "two",' '            "expected": "b.txt",' '            "labeled": False,' \
	'            "cwd_files": {"x.dict": "x"},' '        },' '    ],' ')' \
	>> "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
# shellcheck disable=SC2154 # set in conventions_bazel_run_first_red_hints.sh
mkdir -p "$_cv98/ex10" "$_cv98/ex11"
printf 'Which case is this?\tone\nWhat is on line 3?\tline 3\nWhich case is this?\ttow\nWhich one?\ttwo\n' \
	> "$_cv98/ex10/clues.tsv"
printf 'a\tv\nb\tw\n' > "$_cv98/ex11/expected.txt"
printf 'What is on line 2?\tline 2\nWhat is on line 5?\tline 5\n' > "$_cv98/ex11/clues.tsv"
# cv_dead CLUES: that clue file's dead-label report in the run saved to
# $WORK/cv.dead, made before each group of arms below that reads it.
cv_dead() { cv_saved "$WORK/cv.dead" grep -A4 -F -- "$1 names a case that does not exist"; }
# A label is shown through rl_vis_text, which doubles a backslash before an
# x, so a label naming a byte as \x read doubled in a failing row (V215):
# reported in an expected file's first field (its line 1) and in a clue's
# label field (its line 2, under a '#' note). Quiet: a \t and a \0 in a
# label (the expected file's line 2), a \x in a value (its line 3), the clue
# file's '#' note, and a diff_clues legend, which is prose. Written through
# %s, so no printf reads the backslashes.
# Only a labeled case's expected file has labels (V304): ex31's call says
# labeled = True, its reading "labeled": True (rd.txt, reported), and a
# program's labeled case names p.txt (reported). Quiet: an output no call
# labels (ex32/expected.txt), an input fixture (ex32/stdin.txt), and the
# program's unlabeled case's q.txt.
mkdir -p "$_cv98/ex31" "$_cv98/ex32" "$_cv98/ex33"
printf '%s\t%s\n' 'byte \x80' 1 'tab \t and \0' 2 plain '\xff' > "$_cv98/ex31/expected.txt"
printf '%s\t%s\n' '# a note' '\x41 here' 'Which byte is this?' 'byte \x80' > "$_cv98/ex31/clues.tsv"
printf '%s\t%s\n' 'note \x41' 'a legend line' > "$_cv98/ex31/diff_clues.txt"
printf '%s\t%s\n' 'rd \x41' v > "$_cv98/ex31/rd.txt"
printf '%s\t%s\n' 'x \x41' y > "$_cv98/ex32/expected.txt"
printf '%s\t%s\n' 'raw \x00' input > "$_cv98/ex32/stdin.txt"
printf '%s\t%s\n' 'p \x41' 1 > "$_cv98/ex33/p.txt"
printf '%s\t%s\n' 'q \x42' 2 > "$_cv98/ex33/q.txt"
cp "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel" "$WORK/cv.labels.keep"
printf '%s\n' 'c_function(' '    num = "31",' '    fn = "ft_toy",' '    test = "toy.c",' \
	'    labeled = True,' '    readings = [{"name": "rd", "main": "rd.c", "expected": "rd.txt", "labeled": True}],' \
	')' 'c_program(' '    num = "33",' '    name = "toyp",' '    cases = [' \
	'        {"name": "p", "expected": "p.txt", "labeled": True},' \
	'        {"name": "q", "expected": "q.txt"},' '    ],' ')' \
	>> "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
# The arms below ask about one tree, so they read one run of it (as
# cv.keyed's do), made only where they run: one run of conventions.sh over
# the cv tree where each arm would make its own, in the section that once
# filled a shard.
! st_mine || conv > "$WORK/cv.labels" 2>&1
mv "$WORK/cv.labels.keep" "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
cv_dead_labels() { cv_saved "$WORK/cv.labels" grep -A4 -F -- "$1 names a case that does not exist"; }
want_out "conventions: a clue naming no program case is reported" 'line 3: tow' -- \
	cv_dead_labels c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
want_broken_none "conventions: ...a clue naming one is not" 'line 1: one' -- \
	cv_dead_labels c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
want_broken_none "conventions: ...nor one naming a case laid out over lines" 'line 4: two' -- \
	cv_dead_labels c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
want_broken_none "conventions: ...nor a line of a program's output" 'line 2: line 3' -- \
	cv_dead_labels c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
want_out "conventions: a line past the expected output is reported" 'line 2: line 5' -- \
	cv_dead_labels c-piscine/c-piscine-c-98/tests/ex11/clues.tsv
want_broken_none "conventions: ...one within it is not" 'line 1: line 2' -- \
	cv_dead_labels c-piscine/c-piscine-c-98/tests/ex11/clues.tsv
cv_lbx() { cv_block "$WORK/cv.labels" "a case's label writes a byte as"; }
want_out "conventions: a label writing a byte as \\x is reported" \
	'c-98/tests/ex31/expected.txt:1: byte \x80' -- cv_lbx
want_out "conventions: ...and a clue's label field" \
	'c-98/tests/ex31/clues.tsv:2: byte \x80' -- cv_lbx
want_broken_none "conventions: ...never a \\t or a \\0 in a label" 'expected.txt:2:' -- cv_lbx
want_broken_none "conventions: ...nor a \\x in a value" 'expected.txt:3:' -- cv_lbx
want_broken_none "conventions: ...nor a clue file's '#' note" 'clues.tsv:1:' -- cv_lbx
want_broken_none "conventions: ...nor a diff_clues legend" 'ex31/diff_clues.txt' -- cv_lbx
want_out "conventions: ...and a labeled reading's own expected file" \
	'c-98/tests/ex31/rd.txt:1: rd \x41' -- cv_lbx
want_out "conventions: ...and a labeled program case's" \
	'c-98/tests/ex33/p.txt:1: p \x41' -- cv_lbx
want_broken_none "conventions: ...never an output no call labels" 'ex32/expected.txt' -- cv_lbx
want_broken_none "conventions: ...nor an input fixture" 'ex32/stdin.txt' -- cv_lbx
want_broken_none "conventions: ...nor an unlabeled program case's output" 'ex33/q.txt' -- cv_lbx
rm -rf "$_cv98/ex31" "$_cv98/ex32" "$_cv98/ex33"
# ...and a labeled declaration it cannot place is reported, in a workspace
# of its own (cvlbx): one in a list comprehension, which opens no call in
# the first column, and one whose num is a variable; and so is a file it
# places that is not on disk (ex01's expected.txt), never dropped.
mkdir -p "$WORK/cvlbx/tools" "$WORK/cvlbx/c-piscine/c-piscine-c-94"
cv_submit "c-piscine/c-piscine-c-94" > "$WORK/cvlbx/tools/submit.sh"
printf '%s\n' 'c_function(' '    num = "01",' '    fn = "ft_a",' '    labeled = True,' ')' \
	'[c_function(' '    num = n,' '    fn = "ft_b",' '    labeled = True,' ') for n in ["02"]]' \
	'c_function(' '    num = NUM,' '    fn = "ft_c",' '    labeled = True,' ')' \
	> "$WORK/cvlbx/c-piscine/c-piscine-c-94/BUILD.bazel"
! st_mine || env BUILD_WORKSPACE_DIRECTORY="$WORK/cvlbx" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvlbx.out" 2>&1
cvlbx_odd() { cvi_rule cvlbx 'the \x label rule cannot name'; }
want_out "conventions: a labeled declaration the \\x rule does not see is reported" \
	'c-piscine/c-piscine-c-94/BUILD.bazel: 3 labeled declaration(s), 2 read' -- cvlbx_odd
want_out "conventions: ...and one whose num it cannot read" \
	'c-piscine/c-piscine-c-94: c_function' -- cvlbx_odd
want_out "conventions: ...and a file it places that is not on disk" \
	'c-piscine/c-piscine-c-94/tests/ex01/expected.txt: placed there, and no such file' -- cvlbx_odd
rm -f "$WORK/cv.labels"
# A row keyed to a program case fires on that case's test wherever it sits,
# and the stub fails every case: it is a first-red row, however far down.
# So is one keyed to a line of the output, in a program's file: the rows
# keyed to other cases drop out of each case's test, so it fires from any
# row there. In a file that is no program's, the first three rows are the
# ones that can.
printf 'Case two prints a word.\ttwo\nLine three prints a word.\tline 3\n' >> "$_cv98/ex10/clues.tsv"
! st_mine || conv > "$WORK/cv.rows" 2>&1
want_out "conventions: a row keyed to a program case is a first-red row" \
	'line 5 (no question)' -- cv_rows "$WORK/cv.rows" c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
rm -f "$WORK/cv.rows"
# "valgrind" keys a row to a program's memory arms (valgrind_test.sh); in a
# file that is no program's it names nothing.
printf 'What does valgrind say?\tvalgrind\n' >> "$_cv98/ex10/clues.tsv"
printf 'What does valgrind say?\tvalgrind\n' >> "$_cv98/ex11/clues.tsv"
! st_mine || conv > "$WORK/cv.dead" 2>&1
want_broken_none "conventions: \"valgrind\" is a label in a program's hints" 'line 7: valgrind' -- \
	cv_dead c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
want_out "conventions: ...and in no other file" 'line 3: valgrind' -- \
	cv_dead c-piscine/c-piscine-c-98/tests/ex11/clues.tsv
# A target that replays a corpus through a runner of its own keys its rows
# in the program's one clues.tsv by the name it passes as --case (ruling
# R7): BSQ's and Rush 01's readings once had a clue file each. An invented
# one, the name on the line after "--case" and on its line, and a label no
# test passes (reported). A --case followed by a variable, on the next line
# or on its own, is reported as unreadable, and a word quoted later is no
# label for it: the next quoted string on any later line used to be taken.
cp "$_cv98/ex10/clues.tsv" "$WORK/cv_ex10_keyed.tsv"
cp "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel" "$WORK/cv_b98_keyed"
printf '%s\n' 'hand_test(' '    name = "ex10_sweep",' '    args = [' '        "--case",' \
	'        "sweep",' '    ],' ')' 'hand_test(' '    name = "ex10_shapes",' \
	'    args = ["--case", "shapes"],' ')' 'hand_test(' '    name = "ex10_var",' '    args = [' \
	'        "--case",' '        WHICH,' '    ],' '    data = ["hidden"],' ')' 'hand_test(' \
	'    name = "ex10_inline",' '    args = ["--case", WHICH_TOO, "--x", "other"],' ')' \
	>> "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
printf 'What did the sweep find?\tsweep\nWhich shape?\tshapes\nWhat did it miss?\tswept\nWhere is it?\thidden\n' \
	>> "$_cv98/ex10/clues.tsv"
! st_mine || conv > "$WORK/cv.keyed" 2>&1
cv_dead_in() { cv_saved "$WORK/cv.keyed" grep -A6 -F -- "$1 names a case that does not exist"; }
want_broken_none "conventions: a name a test passes as --case is a label" 'line 8: sweep' -- \
	cv_dead_in c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
want_broken_none "conventions: ...and so is one on the line of its --case" 'line 9: shapes' -- \
	cv_dead_in c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
want_out "conventions: ...while a name no test passes is not" 'line 10: swept' -- \
	cv_dead_in c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
want_out "conventions: ...nor a word quoted after a --case that is no literal" 'line 11: hidden' -- \
	cv_dead_in c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
cv_unread() { cv_saved "$WORK/cv.keyed" grep -A3 -F -- "passes --case a value this check cannot read"; }
want_out "conventions: a --case value on the next line that is no literal is reported" \
	'        WHICH,' -- cv_unread
want_out "conventions: ...and one on its line" 'args = ["--case", WHICH_TOO' -- cv_unread
want_broken_none "conventions: a dead-label check that compared one has no floor to report" \
	'the dead-label check compared none' -- cv_saved "$WORK/cv.keyed"
mv "$WORK/cv_ex10_keyed.tsv" "$_cv98/ex10/clues.tsv"
mv "$WORK/cv_b98_keyed" "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
rm -f "$WORK/cv.keyed"
cv_all_rows() { cv_saved "$WORK/cv.allrows" grep -A8 -F -- "$1 has a first-red hint"; }
! st_mine || conv > "$WORK/cv.allrows" 2>&1
want_out "conventions: ...and so is one that far down keyed to a line" \
	'line 6 (no question)' -- cv_all_rows c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
printf 'Line two prints a word.\tline 2\n' >> "$_cv98/ex11/clues.tsv"
! st_mine || conv > "$WORK/cv.allrows" 2>&1
want_broken_none "conventions: ...but not in a file that is no program's" \
	'line 4 (no question)' -- cv_all_rows c-piscine/c-piscine-c-98/tests/ex11/clues.tsv
rm -f "$WORK/cv.allrows"

# A case's own hint file (clues_<x>.tsv) is held to the labels of the .txt
# files beside it, as clues.tsv is to expected.txt: a label no case has is a
# gate that never opens, and no check held these files' labels to a case.
# shellcheck disable=SC2154 # set in conventions_bazel_run_first_red_hints.sh
mkdir -p "$_cv99/ex44" "$_cv99/ex45"
printf 'wide\t3\n' > "$_cv99/ex44/wide.txt"
printf 'What type is it?\twide\twdie\n' > "$_cv99/ex44/clues_wide.tsv"
printf 'wide\t3\n' > "$_cv99/ex45/wide.txt"
printf 'What type is it?\twide\n' > "$_cv99/ex45/clues_wide.tsv"
# In a program's folder the rule above accepts a case's name, "line N" and
# "valgrind" in a clues_<x>.tsv, and this one must not report what it allows:
# the invented c_program of c-98 ex10, whose folder holds no .txt at all.
# Each file below is reported or not on its own name, so the four arms read
# one run of the tree that holds them all.
printf 'Which case is this?\ttwo\tvalgrind\tline 2\n' > "$_cv98/ex10/clues_args.tsv"
printf 'Which case is this?\ttow\n' > "$_cv98/ex10/clues_typo.tsv"
! st_mine || conv > "$WORK/cv.perkey" 2>&1
want_out "conventions: a per-case clue label with no case is reported" \
	'line 1: wdie' -- \
	cv_saved "$WORK/cv.perkey"
want_broken_none "conventions: ...and one whose case exists is not" \
	'c-99/tests/ex45/clues_wide.tsv names a case' -- \
	cv_saved "$WORK/cv.perkey"
want_broken_none "conventions: ...nor a program's case names, lines and valgrind" \
	'c-98/tests/ex10/clues_args.tsv names a case' -- \
	cv_saved "$WORK/cv.perkey"
want_out "conventions: ...while a misspelt one there still is" \
	'c-98/tests/ex10/clues_typo.tsv names a case that no expected file' -- \
	cv_saved "$WORK/cv.perkey"
rm -f "$WORK/cv.perkey"
# The two rules read a program's folder, and one must not report what the
# other allows (V12): a labeled program case keys its hints to the labels of
# its rows (diff_output.sh puts a failing row's label beside the case's name),
# so a row of its .txt is a label in its own hint file and in clues.tsv. The
# invented case "one" of c-98 ex10 is labeled and expects a.txt; its row's
# label "wide" keys a clues_rows.tsv row and a clues.tsv row, and "wdie"
# names nothing in either. Case "two" is not labeled: its b.txt is a line
# the program prints, keyed "line 1", so its first field keys nothing in
# either file -- a hint keyed to it would never fire.
printf 'wide\t3\n' > "$_cv98/ex10/a.txt"
printf 'Printed words.\n' > "$_cv98/ex10/b.txt"
printf 'Which row is this?\twide\n' > "$_cv98/ex10/clues_rows.tsv"
printf 'Which line is this?\tPrinted words.\n' > "$_cv98/ex10/clues_printed.tsv"
! st_mine || conv > "$WORK/cv.rowkey" 2>&1
want_broken_none "conventions: a labeled program case's row keys its own hint file" \
	'c-98/tests/ex10/clues_rows.tsv names a case' -- cv_saved "$WORK/cv.rowkey"
want_out "conventions: ...an unlabeled case's line does not" \
	'c-98/tests/ex10/clues_printed.tsv names a case that no expected file' -- cv_saved "$WORK/cv.rowkey"
rm -f "$WORK/cv.rowkey"
cp "$_cv98/ex10/clues.tsv" "$WORK/cv_ex10_clues.tsv"
printf 'Which row is this?\twide\nWhich row is that?\twdie\nWhich line is this?\tPrinted words.\n' \
	>> "$_cv98/ex10/clues.tsv"
! st_mine || conv > "$WORK/cv.dead" 2>&1
want_broken_none "conventions: ...and the program's clues.tsv" 'line 8: wide' -- \
	cv_dead c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
want_out "conventions: ...where a label of no row is still reported" 'line 9: wdie' -- \
	cv_dead c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
want_out "conventions: ...and so is an unlabeled case's line" 'line 10: Printed words.' -- \
	cv_dead c-piscine/c-piscine-c-98/tests/ex10/clues.tsv
rm -f "$_cv98/ex10/a.txt" "$_cv98/ex10/b.txt" "$_cv98/ex10/clues_rows.tsv" \
	"$_cv98/ex10/clues_printed.tsv" "$WORK/cv.dead"
mv "$WORK/cv_ex10_clues.tsv" "$_cv98/ex10/clues.tsv"

