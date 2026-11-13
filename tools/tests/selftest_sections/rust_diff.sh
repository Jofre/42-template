# ------------------------------------------------------------------ rust_diff
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
printf '#!/bin/sh\nexit 0\n' > "$WORK/empty_oracle"; chmod +x "$WORK/empty_oracle"
printf '#!/bin/sh\ncat >/dev/null\n' > "$WORK/null_student"; chmod +x "$WORK/null_student"
# rd ARG... -- one run of rust_diff.sh, made once and replayed to every arm
# that asks the same (selftest.sh, once): no fixture a run here reads is
# written again after it. A run with its own environment is spelt out.
rd() { once "$SH" "$TOOLS/rust_diff.sh" "$@"; }
# rd_sym ARG... -- the same with the pinned symbolizer and its library, each
# one word whatever its path holds: split from one string, a blank in either
# was a bad --symbolizer, and every sanitized arm refused (F0615).
rd_sym() { rd "$@" --symbolizer "$SYMBOLIZER" --symbolizer-lib "$SYMBOLIZER_LIB"; }
# Not a pass, and not a red either: a corpus with no case checked nothing, so
# it is the harness that failed (exit 2), which is how the four sibling
# runners always said it. This one said 1, a wrong program, and so did the
# oracle that fails outright, below.
want_broken "rust_diff: an EMPTY corpus is not a pass" 'fewer than the 16 this layer needs' -- \
	rd --oracle "$WORK/empty_oracle" --oracle-fn x \
		--seed 1 --count 0 --student-bin "$WORK/null_student"
printf '#!/bin/sh\necho "the reference fell over" >&2\nexit 3\n' > "$WORK/fail_oracle"
chmod +x "$WORK/fail_oracle"
want_broken "rust_diff: an oracle that fails is a harness error, not a red" \
	'reference failed to generate cases' -- \
	rd --oracle "$WORK/fail_oracle" --oracle-fn x \
		--seed 1 --count 40 --student-bin "$WORK/null_student"
# ...and what it said reaches the log through the one renderer, cut: it was a
# bare cat, every line and every byte of it. The loud oracle writes 500 lines,
# the first with a control byte in it.
printf '#!/bin/sh\nprintf "bad\\001byte\\n" >&2\ni=1\nwhile [ $i -lt 500 ]; do echo "oracle line $i" >&2; i=$((i+1)); done\nexit 3\n' \
	> "$WORK/loud_oracle"
chmod +x "$WORK/loud_oracle"
RD_CTL=$(printf '\001')
rd_loud() { rd --oracle "$WORK/loud_oracle" --oracle-fn x \
	--seed 1 --count 40 --student-bin "$WORK/null_student"; }
want_broken "rust_diff: ...its stderr cut at ten lines" '490 more line(s)' -- rd_loud
want_broken "rust_diff: ...a control byte in it rendered" 'bad\x01byte' -- rd_loud
want_broken_without "rust_diff: ...and never sent raw" "$RD_CTL" -- rd_loud
want_broken_without "rust_diff: ...nor a line past the cut" 'oracle line 499' -- rd_loud

# The floor's count and refusal (runner_lib.sh's rl_corpus_lines and
# rl_corpus_floor, which five runners call). A case is a line of at least one
# byte: an unterminated last line is one, a blank line is not, which is what
# wc -l gets wrong both ways; an empty or missing file is 0. The floor itself
# is the runner's, and a setting that is no number is refused, never skipped.
printf 'a\nb' > "$WORK/cl_unterminated"
printf 'a\n\nb\n' > "$WORK/cl_blank"
: > "$WORK/cl_empty"
cl_count() {  # cl_count NAME FILE N
	# shellcheck disable=SC2016 # the script is for the inner shell to expand
	want_out "runner_lib: rl_corpus_lines, $1" "count=[$3]" -- \
		"$SH" -c '. "$1"; printf "count=[%s]\n" "$(rl_corpus_lines "$2")"' _ \
			"$TOOLS/runner_lib.sh" "$WORK/$2"
}
cl_count "a last line with no newline is a case" cl_unterminated 2
cl_count "a blank line is none" cl_blank 2
cl_count "an empty file holds 0" cl_empty 0
cl_count "a missing file holds 0" cl_missing 0
# shellcheck disable=SC2016 # the script is for the inner shell to expand
want_broken "runner_lib: rl_corpus_floor refuses a corpus under the floor" \
	'produced 2 case(s) for the toy, fewer than the 3 this layer needs' -- \
	"$SH" -c '. "$1"; o=$(rl_corpus_floor "$2" 3 "the toy" 2>&1); r=$?
		printf "%s\n" "$o" | tr "\n" " " | tr -s " "; exit "$r"' _ \
		"$TOOLS/runner_lib.sh" "$WORK/cl_blank"
# shellcheck disable=SC2016 # the script is for the inner shell to expand
want_green "runner_lib: rl_corpus_floor passes a corpus at the floor" -- \
	"$SH" -c '. "$1"; rl_corpus_floor "$2" 2 "the toy"' _ "$TOOLS/runner_lib.sh" "$WORK/cl_unterminated"
want_broken "runner_lib: rl_corpus_floor refuses a floor that is no number" \
	"the floor '1x' is not a whole number" -- \
	env MIN_DIFF_CASES=1x "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/empty_oracle" --oracle-fn x \
		--seed 1 --count 0 --student-bin "$WORK/null_student"

# The column legend, which every diff target gets for free. It is read out of
# the harness's own header comment rather than written per exercise, so the arm
# that matters is "a real header yields a legend" -- if the sed that extracts it
# ever stops matching, 74 targets quietly go back to printing bare hex and
# nothing else changes to say so.
mkdir -p "$WORK/cols"
cat > "$WORK/cols/diff_thing.c" <<'COLS_SRC'
/* Live-differential reader harness for ft_thing.
 * Line: <hexIn>\t<size>\t<hexOut>. Reads one record, replays it and
 * reprints the result as hex. */
#include "diffio.h"
COLS_SRC
# 40 cases, not 1: rust_diff refuses a corpus too small to prove anything, so a
# one-line fixture never reaches the divergence report at all.
printf '#!/bin/sh\ni=0\nwhile [ $i -lt 40 ]; do printf "%%s\\tb%%s\\n" "$i" "$i"; i=$((i+1)); done\n' \
	> "$WORK/cols/oracle.sh"
printf '#!/bin/sh\ncat >/dev/null\ni=0\nwhile [ $i -lt 40 ]; do printf "%%s\\tZZZ\\n" "$i"; i=$((i+1)); done\n' \
	> "$WORK/cols/student.sh"
chmod +x "$WORK/cols/oracle.sh" "$WORK/cols/student.sh"
# The clue file reaches the student WHOLE. It used to be run through the
# tiered clues.tsv renderer -- first three lines, one bullet each -- which for a
# prose legend meant three fragments of a cut-off opening sentence. The arm
# checks for text on the file's fourth line, which no `head -3` can reach.
printf 'first line\nsecond line\n# a maintainer note, not for students\nthird line\nFOURTH_LINE_MARKER\n' \
	> "$WORK/cols/clues.txt"
want_out "rust_diff: the clue file is printed whole, not head -3" 'FOURTH_LINE_MARKER' -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--clues "$WORK/cols/clues.txt"
want_out "rust_diff: and its # comments are not" 'first line' -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--clues "$WORK/cols/clues.txt"
# The arm above passes whether a '#' line is dropped or not: the note itself
# must not reach the legend, which every diff and diff_asan target prints to
# the student (F0606).
want_broken_none "rust_diff: ...its maintainer note dropped" 'a maintainer note' -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--clues "$WORK/cols/clues.txt"

# The same legend, from a header that closes its comment on the SENTENCE'S OWN
# LINE -- which is how 16 of the 75 harnesses are written. A sed range does not
# stop on the line it started on, so those spilled #includes, the prototype and
# the head of main() into the report. The arm asserts the sentence arrives and
# the next arm asserts the code does not.
cat > "$WORK/cols/diff_oneline.c" <<'ONELINE_SRC'
/* Live-differential reader harness for ft_oneline.
 * Line: <hexOne>\t<hexTwo>. Reads a record and reprints it. */
#include "diffio.h"
int	main(void)
{
	char	SPILLED_CODE_MARKER[8192];
ONELINE_SRC
want_out "rust_diff: a one-line legend is still extracted" 'Line: <hexOne>' -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--harness-src "$WORK/cols/diff_oneline.c"
# A runner that refused (exit 2) says nothing after the comment either, so
# the absence is judged on a run that ran (want_broken_none), and once (F0608).
want_broken_none "rust_diff: and stops at the end of the comment" 'SPILLED_CODE_MARKER' -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--harness-src "$WORK/cols/diff_oneline.c"

want_out "rust_diff: a divergence explains its hex columns" 'Line: <hexIn>' -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--harness-src "$WORK/cols/diff_thing.c"

# Headers out of the shape (finding 058), which //tools:conventions now
# refuses in the repo but a harness written tomorrow may still have: the
# sentence on the `/*` line printed with the `/*` and the words before it; a
# header with no "Line:" printed no legend at all; and notes kept under the
# sentence printed too. The legend is the "Line:" paragraph, cut out of its
# line, and a harness with none still gets a line saying where to look.
printf '/* Harness PREFIX_MARKER for ft_x. Line: <hexA>\\t<n>. */\n#include "diffio.h"\n' \
	> "$WORK/cols/diff_onstar.c"
printf '/* Harness for ft_x: reads records and reprints them. */\n#include "diffio.h"\n' \
	> "$WORK/cols/diff_noline.c"
printf '/* Harness for ft_x.\n * Line: <hexA>\\t<n>. The input,\n * then the result.\n *\n * NOTES_MARKER on how it works. */\n' \
	> "$WORK/cols/diff_notes.c"
want_out "rust_diff: a sentence on the /* line is extracted" 'Line: <hexA>\t<n>.' -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--harness-src "$WORK/cols/diff_onstar.c"
want_broken_none "rust_diff: ...without the words before it" 'PREFIX_MARKER' -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--harness-src "$WORK/cols/diff_onstar.c"
want_out "rust_diff: a header naming no columns says where to look" \
	'names none in the shape this layer reads' -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--harness-src "$WORK/cols/diff_noline.c"
want_out "rust_diff: the legend is the whole paragraph" 'then the result.' -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--harness-src "$WORK/cols/diff_notes.c"
want_broken_none "rust_diff: ...and stops at the empty comment line" 'NOTES_MARKER' -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/cols/student.sh" \
		--harness-src "$WORK/cols/diff_notes.c"

# The red above only proves the corpus-size guard fires; it says nothing about
# whether the comparison downstream of it still works. A layer that reds on
# everything is as useless as one that greens on everything — the first time it
# cries wolf over a correct answer it gets switched off — so the passing path
# needs pinning too. The real oracle is //oracle's Rust binary, which this test
# must not depend on (it would drag a Rust build into a "small" shell test); any
# program emitting at least MIN_DIFF_CASES self-describing lines stands in for
# it, and a student harness that echoes the corpus back is what a CORRECT one
# does by construction, since it reprints each input beside its own answer.
printf '#!/bin/sh\ni=0\nwhile [ $i -lt 24 ]; do printf "%%02x\\tcase-%%d\\n" "$i" "$i"; i=$((i+1)); done\n' \
	> "$WORK/mini_oracle"; chmod +x "$WORK/mini_oracle"
printf '#!/bin/sh\ncat\n' > "$WORK/echo_student"; chmod +x "$WORK/echo_student"
# Diverges on the FIRST line only: a corpus is 400k lines in production and the
# bug being fuzzed for is usually one input in thousands, so "detects a wholesale
# difference" is not the property worth testing.
printf '#!/bin/sh\nsed "1s/case/CASE/"\n' > "$WORK/skew_student"; chmod +x "$WORK/skew_student"
want_green "rust_diff: a matching corpus passes" -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --student-bin "$WORK/echo_student"
# ...and MIN_DIFF_CASES moves the floor it passed (docs/reference.md).
want_broken "rust_diff: MIN_DIFF_CASES raises the floor" 'fewer than the 30 this layer needs' -- \
	env MIN_DIFF_CASES=30 "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --student-bin "$WORK/echo_student"
want_red   "rust_diff: ONE diverging line fails" -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --student-bin "$WORK/skew_student"

# EVERY BYTE OF A DIVERGENCE IS VISIBLE. The reference and student lines were
# printed raw, and an output column can hold any byte -- C 04 ex04's corpus
# seeds bases of control bytes, where a base check that refuses them is the
# mistake being looked for. Raw, "0<TAB>x<0x01>y" and "0<TAB>xy" read the same
# on a terminal. Here the two records differ by that one byte only, and the
# report must show it as \x01 and never print it raw. The same corpus lines
# reach the reproducer under a run that dies, as one replayable shell word.
mkdir -p "$WORK/ctl"
cat > "$WORK/ctl/oracle.sh" <<'CTL_ORACLE'
#!/bin/sh
i=0
while [ $i -lt 40 ]; do printf '%s\tx\001y\n' "$i"; i=$((i + 1)); done
CTL_ORACLE
cat > "$WORK/ctl/student.sh" <<'CTL_STUDENT'
#!/bin/sh
cat > /dev/null
i=0
while [ $i -lt 40 ]; do printf '%s\txy\n' "$i"; i=$((i + 1)); done
CTL_STUDENT
# Answers the first 20 cases right and ends with 0: the corpus cut short.
cat > "$WORK/ctl/short.sh" <<'CTL_SHORT'
#!/bin/sh
head -n 20
CTL_SHORT
# Answers every case right, then prints one line more.
cat > "$WORK/ctl/extra.sh" <<'CTL_EXTRA'
#!/bin/sh
cat
echo EXTRA_LINE_MARKER
CTL_EXTRA
cat > "$WORK/ctl/dies.sh" <<'CTL_DIES'
#!/bin/sh
cat > /dev/null
kill -SEGV $$
CTL_DIES
chmod +x "$WORK/ctl/oracle.sh" "$WORK/ctl/student.sh" "$WORK/ctl/short.sh" \
	"$WORK/ctl/extra.sh" "$WORK/ctl/dies.sh"
_ctl=$(printf '\001')
want_out "rust_diff: a control byte in a divergence shows as \\x01" '0\tx\x01y' -- \
	rd --oracle "$WORK/ctl/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/ctl/student.sh"
want_broken_none "rust_diff: ...and is never printed raw" "$_ctl" -- \
	rd --oracle "$WORK/ctl/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/ctl/student.sh"
# The legend under the lines names the marks they hold, read off them
# (rl_vis_legend): a fixed one named a tab and a backslash under lines that
# held neither.
want_out "rust_diff: the legend names the marks the lines show" 'byte for byte: \t a tab, and \xHH' -- \
	rd --oracle "$WORK/ctl/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/ctl/student.sh"
want_broken_none "rust_diff: ...and none they do not" 'one backslash' -- \
	rd --oracle "$WORK/ctl/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/ctl/student.sh"
# A space at a line's end is no byte the renderer escapes: "61\ta " and
# "61\ta" read the same until each line's end was marked with $, as the
# output tables mark it (V49).
cat > "$WORK/ctl/trail.sh" <<'CTL_TRAIL'
#!/bin/sh
cat > /dev/null
i=0
while [ $i -lt 40 ]; do printf '%s\tx\001y \n' "$i"; i=$((i + 1)); done
CTL_TRAIL
chmod +x "$WORK/ctl/trail.sh"
want_out "rust_diff: a space at a line's end is shown, before its \$" '0\tx\x01y $' -- \
	rd --oracle "$WORK/ctl/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/ctl/trail.sh"
want_out "rust_diff: ...and the legend says what the \$ is" '$ is where a line ended' -- \
	rd --oracle "$WORK/ctl/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/ctl/trail.sh"
want_out "rust_diff: a reproducer line is one shell word" "'0\\011x\\001y'" -- \
	rd --oracle "$WORK/ctl/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/ctl/dies.sh"
want_broken_none "rust_diff: ...holding no raw control byte" "$_ctl" -- \
	rd --oracle "$WORK/ctl/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/ctl/dies.sh"
# A run that died lost its buffer: the first unanswered case is where its
# answers stopped arriving, not where it died, and "start with these" sent a
# reader to replay innocent cases (the mutation run of 2026-10-03).
want_out "rust_diff: a run that died does not call case 1 the cause" \
	'possibly thousands after' -- \
	rd --oracle "$WORK/ctl/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/ctl/dies.sh"
want_broken_none "rust_diff: ...nor tells the reader to start with it" 'Start with these' -- \
	rd --oracle "$WORK/ctl/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/ctl/dies.sh"
# A divergence with no differing line printed an empty list under "diverges".
want_out "rust_diff: a run cut short says which case went unanswered" \
	'so case 21' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --student-bin "$WORK/ctl/short.sh"
want_out "rust_diff: a line past the reference's last says it has none" \
	'its 24 cases end before this one' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --student-bin "$WORK/ctl/extra.sh"
want_broken_none "rust_diff: ...and lines holding no mark get no legend" 'byte for byte' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --student-bin "$WORK/ctl/extra.sh"
# The reproducer names the program where it can be run from the repository
# root. Bazel hands a runner a path relative to the runfiles root, which is
# bazel-bin/ from the repository; every arm above passes an absolute one.
_rd_abs="$(cd "$TOOLS" && pwd)/rust_diff.sh"
want_out "rust_diff: a relative program is named under bazel-bin/ in the reproducer" \
	"WORD | bazel-bin/ctl/short.sh runs it on its own" -- \
	"$SH" -c 'cd "$1" && exec "$2" "$3" --oracle "$4" --oracle-fn x --seed 1 --count 24 \
		--student-bin ctl/short.sh' _ "$WORK" "$SH" "$_rd_abs" "$WORK/mini_oracle"
want_out "rust_diff: ...and an absolute one as it is" \
	"WORD | $WORK/ctl/short.sh runs it on its own" -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --student-bin "$WORK/ctl/short.sh"
# Bytes that differ where no line read as text does: an awk that ends a line
# at a NUL (busybox's) reads "case-23<NUL>" as "case-23". mawk and gawk read
# the NUL, so this stands one in: every file it is handed is cut at a NUL
# first. The report says so and shows cmp's words, never an empty list.
_real_awk=$(command -v awk)
mkdir -p "$WORK/ctl/nulawk"
{
	printf '#!/bin/sh\n'
	printf '# An awk that ends a line at a NUL: each file operand is cut there.\n'
	printf 't=$(mktemp -d) || exit 2\ni=0\nfor a do\n\tshift\n'
	printf '\tif [ -f "$a" ]; then\n\t\ti=$((i + 1))\n'
	printf '\t\tLC_ALL=C sed %s "$a" > "$t/$i"\n' "'s/\\x00.*//'"
	printf '\t\tset -- "$@" "$t/$i"\n\telse\n\t\tset -- "$@" "$a"\n\tfi\ndone\n'
	printf '"%s" "$@"\nrc=$?\nrm -rf "$t"\nexit $rc\n' "$_real_awk"
} > "$WORK/ctl/nulawk/awk"
cat > "$WORK/ctl/nul.sh" <<'CTL_NUL'
#!/bin/sh
t=$(mktemp)
cat > "$t"
n=$(wc -l < "$t")
head -n $((n - 1)) "$t"
printf '%s\000\n' "$(tail -n 1 "$t")"
rm -f "$t"
CTL_NUL
chmod +x "$WORK/ctl/nulawk/awk" "$WORK/ctl/nul.sh"
want_out "rust_diff: bytes that differ where no line does are said, in cmp's words" \
	'No line differs as text, yet the bytes do' -- \
	env PATH="$WORK/ctl/nulawk:$PATH" "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/mini_oracle" \
		--oracle-fn x --seed 1 --count 24 --student-bin "$WORK/ctl/nul.sh"
want_out "rust_diff: ...naming the line" 'differ: char' -- \
	env PATH="$WORK/ctl/nulawk:$PATH" "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/mini_oracle" \
		--oracle-fn x --seed 1 --count 24 --student-bin "$WORK/ctl/nul.sh"

# A LONG LINE IS SHOWN CUT. The corpora hold cases past the round capacities
# (finding 041), lines of 16 to 80 KB early in the file, and a divergence
# printed each line whole: one common bug put hundreds of KB of hex in a first
# red log. Here line 1 is 20 KB of input, and the two answers differ in its
# last byte. Each side is shown to its first 300 bytes and the rest counted,
# and the bytes around the first difference are shown apart, so a cut that
# falls before the difference still says where it is. Only what is shown is
# cut: the comparison is the whole line's. The same line in a reproducer, a
# word that must give back every byte, is kept as a file and named instead.
mkdir -p "$WORK/long"
cat > "$WORK/long/oracle.sh" <<'LONG_ORACLE'
#!/bin/sh
LC_ALL=C awk 'BEGIN {
	s = ""
	for (i = 0; i < 10000; i++) s = s "61"
	print s "\tx"
	for (i = 1; i < 40; i++) printf "%02x\tc%d\n", i, i
}'
LONG_ORACLE
cat > "$WORK/long/student.sh" <<'LONG_STUDENT'
#!/bin/sh
LC_ALL=C sed '1s/x$/y/'
LONG_STUDENT
cat > "$WORK/long/dies.sh" <<'LONG_DIES'
#!/bin/sh
cat > /dev/null
[ -z "${DIO_CASE_FILE:-}" ] || echo 1 > "$DIO_CASE_FILE"
kill -SEGV $$
LONG_DIES
# Dies without saying on which case: the reproducer's window, from case 1.
cat > "$WORK/long/quiet.sh" <<'LONG_QUIET'
#!/bin/sh
cat > /dev/null
kill -SEGV $$
LONG_QUIET
chmod +x "$WORK/long/oracle.sh" "$WORK/long/student.sh" "$WORK/long/dies.sh" \
	"$WORK/long/quiet.sh"
_long_run=$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 200; i++) printf "61" }')
want_broken_none "rust_diff: a 20 KB divergent line is not printed whole" "$_long_run" -- \
	rd --oracle "$WORK/long/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/long/student.sh"
want_out "rust_diff: ...it says how much of it was left out" '... (19702 more bytes)' -- \
	rd --oracle "$WORK/long/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/long/student.sh"
want_out "rust_diff: ...and shows where the two lines part" 'first difference: byte 20002' -- \
	rd --oracle "$WORK/long/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/long/student.sh"
# That window names its two sides as the pair above it does: under a
# "reference:" and a "student  :" line it said "expected" and "got", two pairs
# of words for the same two lines in one report.
want_out "rust_diff: ...naming its sides as the pair does" 'reference, from byte 19994' -- \
	rd --oracle "$WORK/long/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/long/student.sh"
want_broken_none "rust_diff: ...and in no second pair of words" 'expected, from byte' -- \
	rd --oracle "$WORK/long/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/long/student.sh"
# Every line shown was cut, so no $ ends one: the note on what a $ is said so
# under lines that hold none.
want_broken_none "rust_diff: no \$ note when every line shown was cut" 'is where a line ended' -- \
	rd --oracle "$WORK/long/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/long/student.sh"
want_red "rust_diff: ...and still fails on that last byte" -- \
	rd --oracle "$WORK/long/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/long/student.sh"
want_broken_none "rust_diff: a reproducer does not print a 20 KB word" "$_long_run" -- \
	rd --oracle "$WORK/long/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/long/quiet.sh"
want_out "rust_diff: ...it keeps the line as a file and replays from it" \
	'< bazel-testlogs/mod/ex00_diff/test.outputs/case-1.txt' -- \
	env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/long/out" TEST_TARGET=//mod:ex00_diff \
		"$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/long/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$WORK/long/quiet.sh"
want_out "rust_diff: ...or says that only a run under bazel test keeps it" \
	'only a run under bazel test keeps it' -- \
	env -u TEST_UNDECLARED_OUTPUTS_DIR "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/long/oracle.sh" \
		--oracle-fn f --seed 1 --count 40 --student-bin "$WORK/long/quiet.sh"
want_broken_none "rust_diff: a died case's line is not printed whole" "$_long_run" -- \
	rd --oracle "$WORK/long/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --crash-only --student-bin "$WORK/long/dies.sh"

# --crash-only, which is the ENTIRE diff_asan layer: 77 targets whose verdict is
# one `rc=$?` and one comparison. It had no arm of any kind. The two above cover
# the value-diff path only, and value-diff and crash-fuzz share no branch --
# crash-only returns before the comparison ever runs.
#
# This is not hypothetical. During the review that produced these arms, an agent
# editing a scratch copy changed that line to `rc=0` -- "the sanitizer verdict is
# discarded; crash-fuzz always passes" -- and every arm in this file stayed
# green. A layer that reports OK having checked nothing is the defect class this
# whole file exists for, and its largest instance was the one place unwatched.
# A clean replay answers every case, one line each, as every real harness
# does (tools/diffio.h's readers, Rush 00's diff_rush.c): an answer that
# never arrived is a case nothing checked, below.
printf '#!/bin/sh\ncat\nexit 0\n' > "$WORK/crash_clean"
# Non-zero is what a sanitizer abort looks like from here: ASan exits 1, and the
# harness is killed by a signal for a hard fault. Either way it is not 0.
printf '#!/bin/sh\ncat >/dev/null\necho "AddressSanitizer: heap-buffer-overflow" >&2\nexit 1\n' \
	> "$WORK/crash_dirty"
# Answers one case and ends with 0: an exit(0) in the function, which stops
# the harness there. Every case after it never reached the sanitizer build,
# and the run said "OK -- no sanitizer error over 24 fuzz cases".
printf '#!/bin/sh\nIFS= read -r l\nprintf "%%s\\n" "$l"\nexit 0\n' > "$WORK/crash_early"
chmod +x "$WORK/crash_clean" "$WORK/crash_dirty" "$WORK/crash_early"

want_green "rust_diff: --crash-only passes a clean replay" -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_clean"
want_red   "rust_diff: --crash-only fails a replay that ended early with 0" -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_early"
want_out "rust_diff: ...saying which cases were never answered" \
	'case 2 of 24 and every case after it were never answered' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_early"
want_red   "rust_diff: --crash-only fails on a sanitizer error" -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_dirty"
want_out "rust_diff: --crash-only shows the sanitizer report" \
	"AddressSanitizer" -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_dirty"
# The premise of the next footer, false: a harness that never said which case
# it was on gets no "It happened on corpus case" line.
want_broken_none "rust_diff: ...and names no case the harness did not name" \
	'It happened on corpus case' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_dirty"

# HOW IT ENDED, in the sanitizer's words when its report is there (V50):
# abort_on_error=1 ends every finding with SIGABRT, and the header named
# SIGABRT's other causes -- an assertion, stack smashing, a glibc heap error
# -- above the sanitizer's own report. An abort with no report keeps them.
printf '#!/bin/sh\ncat >/dev/null\necho "==1==ERROR: AddressSanitizer: heap-buffer-overflow" >&2\nkill -ABRT $$\n' \
	> "$WORK/crash_san_abrt"
printf '#!/bin/sh\ncat >/dev/null\nkill -ABRT $$\n' > "$WORK/crash_abrt"
chmod +x "$WORK/crash_san_abrt" "$WORK/crash_abrt"
want_out "rust_diff: --crash-only says the sanitizer stopped the run" \
	'the harness was stopped by the sanitizer' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_san_abrt"
want_broken_none "rust_diff: ...and not the abort's other causes" 'stack smashing' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_san_abrt"
want_out "rust_diff: an abort with no report keeps SIGABRT's words" 'stack smashing' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_abrt"
want_broken_none "rust_diff: ...and calls it no memory error" 'memory/UB error' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_abrt"
# AN END WITH NO REPORT IS NO MEMORY ERROR. A harness that answered 7 cases
# and returned 3 -- a function that called exit(3) -- was headlined "memory/UB
# error", and explained as a READ or a WRITE outside a block above an empty
# report. It is red, for the cases it never answered, and says what happened.
printf '#!/bin/sh
head -n 7
exit 3
' > "$WORK/crash_exit3"
chmod +x "$WORK/crash_exit3"
want_red   "rust_diff: --crash-only fails a harness that returned 3" -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_exit3"
want_out "rust_diff: ...saying it ended with no sanitizer report" \
	'the harness returned 3 with no sanitizer report' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_exit3"
want_broken_none "rust_diff: ...calling it no memory error" 'memory/UB error' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_exit3"
want_broken_none "rust_diff: ...and explaining no access" 'READ or WRITE' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_exit3"
# What the report is, in words: the paragraph under every report explained an
# access outside a block, READ or WRITE, whatever the report said.
printf '#!/bin/sh\ncat >/dev/null\necho "==1==ERROR: AddressSanitizer: attempting double-free on 0x602000000010 in thread T0:" >&2\nkill -ABRT $$\n' \
	> "$WORK/crash_san_twice"
chmod +x "$WORK/crash_san_twice"
want_out "rust_diff: --crash-only names a report's kind" \
	'The sanitizer stopped the harness when it freed the same block twice (double-free)' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_san_twice"
want_broken_none "rust_diff: ...explaining no access it was not" 'READ or WRITE' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_san_twice"
want_out "rust_diff: ...and an overflow is still explained as one" 'READ or WRITE' -- \
	rd --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/crash_san_abrt"

# A SANITIZER REPORT A STUDENT CAN READ (finding 051). diff_asan's report used
# to be bare offsets into a binary in Bazel's cache, no input, no legend and no
# hint. Now: the case that crashed (tools/diffio.h's death callback), that
# case's line, frames symbolised by the PINNED llvm-symbolizer (never one from
# PATH), no shadow-memory map, and the column legend and diff hints the value
# branch prints. The toy harness overflows a heap block on corpus case #7.
cat > "$WORK/cols/diff_dio_crash.c" <<'DIO_CRASH'
/* Toy reader harness for the sanitizer report arms.
 * Line: <n>\t<word>. Reprints the record; overflows on n == 6. */
#include "diffio.h"

int	main(void)
{
	char	line[256];
	char	*f[2];
	char	*b;

	while (dio_line(line, sizeof(line)))
	{
		dio_split(line, f, 2);
		b = malloc(4);
		if (strtol(f[0], NULL, 16) == 6)
			b[4] = 1;
		printf("%s\t%s\n", f[0], f[1]);
		free(b);
	}
	return (0);
}
DIO_CRASH
# On a box that can build a sanitized program at all (selftest.sh, THE
# SANITIZER PROBE, which refuses NO_SKIP=1 where it cannot); a toy that does
# not build there is toy_cc's FAIL, never a skip. Built in this section's
# shard alone, as the toys below are: only its arms read them.
if ! st_mine; then
	:
elif [ "$SAN" != 1 ]; then
	st_skipped "diff_asan: (sanitizer build unavailable)" skipped
elif toy_cc "$WORK/dio_crash" -g -fsanitize=address,undefined -fno-sanitize-recover=all \
		-fuse-ld=bfd -I"$TOOLS" "$WORK/cols/diff_dio_crash.c"; then
	want_red "diff_asan: a harness that overflows on case 7 fails" -- \
		rd_sym --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash"
	want_out "diff_asan: ...naming that case" 'on corpus case #7 of 24' -- \
		rd_sym --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash"
	want_out "diff_asan: ...showing its line" "printf -- '06\\011case-6'" -- \
		rd_sym --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash"
	# The death callback only when asked (DIO_CASE_FILE), as in the plain
	# build below: run bare, the sanitized toy names no case.
	"$WORK/mini_oracle" > "$WORK/dio_crash.in"
	want_broken_none "diff_asan: a sanitized harness run bare names no case" 'corpus case' -- \
		env ASAN_OPTIONS=detect_leaks=0 sh -c '"$1" < "$2" 2>&1; exit 0' sh "$WORK/dio_crash" "$WORK/dio_crash.in"
	want_out "diff_asan: ...with frames named by file and line" 'diff_dio_crash.c:' -- \
		rd_sym --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash"
	want_broken_none "diff_asan: ...and no shadow-memory map" 'Shadow bytes around' -- \
		rd_sym --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash"
	want_out "diff_asan: ...but what its columns are" 'Line: <n>' -- \
		rd_sym --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash" \
			--harness-src "$WORK/cols/diff_dio_crash.c"
	want_out "diff_asan: ...and the exercise's diff hints" 'FOURTH_LINE_MARKER' -- \
		rd_sym --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash" \
			--clues "$WORK/cols/clues.txt"
	# The symbolizer reached through a folder whose name holds a blank, as an
	# output base under such a $HOME gives every path here: it is still one
	# word (rd_sym). Its library stays where it is, since the runner refuses
	# a symbolizer that loads one from outside that library's own folder.
	mkdir -p "$WORK/sym dir"
	ln -sf "$(cd "$(dirname "$SYMBOLIZER")" && pwd)/${SYMBOLIZER##*/}" "$WORK/sym dir/${SYMBOLIZER##*/}"
	rd_sym_blank() {
		(
			SYMBOLIZER="$WORK/sym dir/${SYMBOLIZER##*/}"
			rd_sym "$@"
		)
	}
	want_out "diff_asan: ...through a symbolizer path with a blank too" 'diff_dio_crash.c:' -- \
		rd_sym_blank --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash"
	# Without a symbolizer the report is left unsymbolised (symbolize=0), never
	# symbolised by one the environment offers. The environment here OFFERS a
	# working one -- the pinned symbolizer behind a wrapper named as the
	# sanitizer runtime expects, in ASAN_SYMBOLIZER_PATH and first on PATH --
	# so this proves symbolize=0: a runner that left it out would find that
	# one and print file:line. (Without the offer the arm proved nothing on a
	# box that has no llvm-symbolizer, which is every box this repo runs on.)
	# The offered wrapper symbolises, or the arm below it is no proof at all:
	# its premise is checked first.
	case "$SYMBOLIZER" in /*) _esym=$SYMBOLIZER ;; *) _esym=$PWD/$SYMBOLIZER ;; esac
	case "$SYMBOLIZER_LIB" in /*) _esymlib=$SYMBOLIZER_LIB ;; *) _esymlib=$PWD/$SYMBOLIZER_LIB ;; esac
	mkdir -p "$WORK/envsym"
	printf '#!/bin/sh\nLD_LIBRARY_PATH="%s"\nexport LD_LIBRARY_PATH\nexec "%s" "$@"\n' \
		"${_esymlib%/*}" "$_esym" > "$WORK/envsym/llvm-symbolizer"
	chmod +x "$WORK/envsym/llvm-symbolizer"
	want_out "diff_asan: (premise) the offered symbolizer names file:line" 'diff_dio_crash.c:' -- \
		env ASAN_SYMBOLIZER_PATH="$WORK/envsym/llvm-symbolizer" \
			ASAN_OPTIONS=detect_leaks=0 sh -c '"$1" < "$2" 2>&1; exit 0' sh "$WORK/dio_crash" "$WORK/dio_crash.in"
	want_broken_none "diff_asan: no --symbolizer, and the environment's is not used" 'diff_dio_crash.c:' -- \
		env ASAN_SYMBOLIZER_PATH="$WORK/envsym/llvm-symbolizer" PATH="$WORK/envsym:$PATH" \
			"$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash"
	# The wiring faults refuse (exit 2): a symbolizer that is not there, a
	# library directory that is not there, and a directory without its
	# libLLVM, where the loader would lend this machine's (or none).
	want_broken "diff_asan: a missing symbolizer refuses" 'is not an executable file' -- \
		rd --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash" \
			--symbolizer "$WORK/no-such-symbolizer" --symbolizer-lib "$SYMBOLIZER_LIB"
	want_broken "diff_asan: a missing library directory refuses" 'silently stop being pinned' -- \
		rd --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash" \
			--symbolizer "$SYMBOLIZER" --symbolizer-lib "$WORK/no-such-dir/libLLVM-12.so.1"
	mkdir -p "$WORK/nollvm"
	# Only "libLLVM" is asked of this one, and on purpose (V345): what the
	# refusal says depends on the box. One with a libLLVM-12 of its own
	# lends it, and the refusal lists it among the libraries from outside;
	# one without cannot start the symbolizer, and the refusal quotes the
	# loader, which found libLLVM-12.so.1 nowhere. That the library from
	# outside is named, by its path, is asserted on every box by a toy:
	# "sanitizers: a libLLVM from outside with no libxml2 is named", below.
	want_broken "diff_asan: a libLLVM from elsewhere refuses" 'libLLVM' -- \
		rd --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash" \
			--symbolizer "$SYMBOLIZER" --symbolizer-lib "$WORK/nollvm/libLLVM-12.so.1"
	# And what libLLVM loads (V238): libxml2, which a box need not have and
	# the fetch lays beside it, taken from anywhere but that folder. Here
	# the folder holds libLLVM and ICU and no libxml2, and the pinned
	# libxml2 waits in ../lib, where libLLVM's RUNPATH ($ORIGIN/../lib)
	# finds it on any machine, before the box's own folders, under a path
	# that starts with the folder's name.
	mkdir -p "$WORK/xmlsym/sym" "$WORK/xmlsym/lib"
	for _x in libLLVM-12.so.1 libicuuc.so.70 libicudata.so.70; do
		ln -sf "${_esymlib%/*}/$_x" "$WORK/xmlsym/sym/$_x"
	done
	ln -sf "${_esymlib%/*}/libxml2.so.2" "$WORK/xmlsym/lib/libxml2.so.2"
	want_broken "diff_asan: a libxml2 from outside libLLVM's folder refuses" \
		"    $WORK/xmlsym/sym/../lib/libxml2.so.2" -- \
		rd --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_crash" \
			--symbolizer "$SYMBOLIZER" --symbolizer-lib "$WORK/xmlsym/sym/libLLVM-12.so.1"
	# A BLANK IN A PATH (V325), which an output base under a $HOME holding
	# one gives every path here. The loader's lines were split at blanks, so
	# a staged folder named with one was refused as libraries from outside,
	# listed in halves; and a wrapper folder named with one ended the
	# symbolizer's path in the options at the blank, where the sanitizer's
	# parser stopped every run at its start ("expected '='"), unsymbolised.
	mkdir -p "$WORK/sym dir"
	for _x in libLLVM-12.so.1 libxml2.so.2 libicuuc.so.70 libicudata.so.70; do
		ln -sf "${_esymlib%/*}/$_x" "$WORK/sym dir/$_x"
	done
	# shellcheck disable=SC2016 # the script is for the inner shell to expand
	want_green "sanitizers: a staged folder with a blank in its path passes" -- \
		"$SH" -c 'RL_NAME=selftest; . "$1"; rl_sanitizers "$2" "$3" "$4"' _ \
			"$TOOLS/runner_lib.sh" "$WORK/spsym" "$SYMBOLIZER" "$WORK/sym dir/libLLVM-12.so.1"
	# shellcheck disable=SC2016 # the script is for the inner shell to expand
	want_out "sanitizers: a wrapper folder with a blank still symbolises" 'diff_dio_crash.c:' -- \
		"$SH" -c 'RL_NAME=selftest; . "$1"; rl_sanitizers "$2" "$3" "$4"; "$5" < "$6" 2>&1; exit 0' _ \
			"$TOOLS/runner_lib.sh" "$WORK/wrap dir" "$SYMBOLIZER" "$SYMBOLIZER_LIB" \
			"$WORK/dio_crash" "$WORK/dio_crash.in"
	# A QUOTE IN A PATH: the wrapper single-quotes the symbolizer's path and
	# its library folder, and the options double-quote the wrapper's own
	# folder, so each quote is refused only where it would end its quotes.
	# A quote of either kind was refused in any of the three, a staged
	# folder that the wrapper alone holds among them.
	mkdir -p "$WORK/sym\"dir"
	for _x in libLLVM-12.so.1 libxml2.so.2 libicuuc.so.70 libicudata.so.70; do
		ln -sf "${_esymlib%/*}/$_x" "$WORK/sym\"dir/$_x"
	done
	# shellcheck disable=SC2016 # the script is for the inner shell to expand
	want_green "sanitizers: a staged folder with a double quote passes" -- \
		"$SH" -c 'RL_NAME=selftest; . "$1"; rl_sanitizers "$2" "$3" "$4"' _ \
			"$TOOLS/runner_lib.sh" "$WORK/dqsym" "$SYMBOLIZER" "$WORK/sym\"dir/libLLVM-12.so.1"
	# shellcheck disable=SC2016 # the script is for the inner shell to expand
	want_out "sanitizers: a wrapper folder with a single quote symbolises" 'diff_dio_crash.c:' -- \
		"$SH" -c 'RL_NAME=selftest; . "$1"; rl_sanitizers "$2" "$3" "$4"; "$5" < "$6" 2>&1; exit 0' _ \
			"$TOOLS/runner_lib.sh" "$WORK/wrap'dir" "$SYMBOLIZER" "$SYMBOLIZER_LIB" \
			"$WORK/dio_crash" "$WORK/dio_crash.in"
	# shellcheck disable=SC2016 # the script is for the inner shell to expand
	want_broken "sanitizers: a wrapper folder with a double quote names the options" \
		'ASAN_OPTIONS and UBSAN_OPTIONS' -- \
		"$SH" -c 'RL_NAME=selftest; . "$1"; rl_sanitizers "$2" "$3" "$4"' _ \
			"$TOOLS/runner_lib.sh" "$WORK/wrap\"dir" "$SYMBOLIZER" "$SYMBOLIZER_LIB"
fi
# A libLLVM from outside the folder is named even when it loads no libxml2,
# as a box's own libLLVM-12 built without libxml2 would: the check that
# libxml2 was seen came first, and the refusal said only that it could not
# observe libxml2, naming nothing. The toy "symbolizer" finds its toy
# libLLVM-12.so.1 through its RUNPATH, outside the empty folder the wrapper
# puts first, and that library loads nothing. Neither answers anything.
# A toy that fails to build leaves no symbolizer, and the arm fails on the
# refusal that names the missing file rather than libLLVM.
if st_mine; then
	mkdir -p "$WORK/sysllvm/box" "$WORK/sysllvm/staged"
	printf 'int selftest_llvm(void) { return 0; }\n' > "$WORK/sysllvm/llvm.c"
	printf 'int selftest_llvm(void);\nint main(void) { return selftest_llvm(); }\n' \
		> "$WORK/sysllvm/sym.c"
	toy_cc "$WORK/sysllvm/box/libLLVM-12.so.1" -shared -fPIC -Wl,-soname,libLLVM-12.so.1 \
		"$WORK/sysllvm/llvm.c" &&
		toy_cc "$WORK/sysllvm/symbolizer" "$WORK/sysllvm/sym.c" \
			"$WORK/sysllvm/box/libLLVM-12.so.1" \
			-Wl,--enable-new-dtags -Wl,-rpath,"$WORK/sysllvm/box"
fi
# shellcheck disable=SC2016 # the script is for the inner shell to expand
want_broken "sanitizers: a libLLVM from outside with no libxml2 is named" \
	"    $WORK/sysllvm/box/libLLVM-12.so.1" -- \
	"$SH" -c 'RL_NAME=selftest; . "$1"; rl_sanitizers "$2" "$3" "$4"' _ \
		"$TOOLS/runner_lib.sh" "$WORK/sysllvm/wrap" "$WORK/sysllvm/symbolizer" \
		"$WORK/sysllvm/staged/libLLVM-12.so.1"
# A SYMBOLIZER THE LOADER CANNOT START (V322): its libLLVM needs a library
# this machine lacks, as the pinned one needs libedit.so.2, and the loader
# stops it before it does anything. The refusal said only that it "could
# not observe which libLLVM" it loaded, and threw the loader's words away.
# The toy libLLVM-12.so.1 is staged and needs libselftestedit.so.2, which
# is built, linked against, and then removed.
if st_mine; then
	mkdir -p "$WORK/nostart/dep" "$WORK/nostart/staged"
	printf 'int selftest_edit(void) { return 0; }\n' > "$WORK/nostart/edit.c"
	printf 'int selftest_edit(void);\nint selftest_llvm(void) { return selftest_edit(); }\n' \
		> "$WORK/nostart/llvm.c"
	printf 'int selftest_llvm(void);\nint main(void) { return selftest_llvm(); }\n' \
		> "$WORK/nostart/sym.c"
	toy_cc "$WORK/nostart/dep/libselftestedit.so.2" -shared -fPIC -Wl,-soname,libselftestedit.so.2 \
		"$WORK/nostart/edit.c" &&
		toy_cc "$WORK/nostart/staged/libLLVM-12.so.1" -shared -fPIC -Wl,-soname,libLLVM-12.so.1 \
			"$WORK/nostart/llvm.c" "$WORK/nostart/dep/libselftestedit.so.2" &&
		toy_cc "$WORK/nostart/symbolizer" "$WORK/nostart/sym.c" \
			"$WORK/nostart/staged/libLLVM-12.so.1" -Wl,-rpath-link,"$WORK/nostart/dep"
	rm -f "$WORK/nostart/dep/libselftestedit.so.2"
fi
# shellcheck disable=SC2016 # the script is for the inner shell to expand
want_broken "sanitizers: a symbolizer that cannot start names the library" \
	'The loader found no libselftestedit.so.2' -- \
	"$SH" -c 'RL_NAME=selftest; . "$1"; rl_sanitizers "$2" "$3" "$4"' _ \
		"$TOOLS/runner_lib.sh" "$WORK/nostart/wrap" "$WORK/nostart/symbolizer" \
		"$WORK/nostart/staged/libLLVM-12.so.1"
# shellcheck disable=SC2016 # the script is for the inner shell to expand
want_broken "sanitizers: ...and shows what the loader said" \
	'error while loading shared libraries' -- \
	"$SH" -c 'RL_NAME=selftest; . "$1"; rl_sanitizers "$2" "$3" "$4"' _ \
		"$TOOLS/runner_lib.sh" "$WORK/nostart/wrap" "$WORK/nostart/symbolizer" \
		"$WORK/nostart/staged/libLLVM-12.so.1"

# WHICH CASE A PLAIN HARNESS DIED ON (V46). The diff layer runs the harness
# as it is built, with no sanitizer, and one that died took its buffered
# answers with it: the report said "at or after case 1" and listed cases 1-3,
# which pass on their own. tools/diffio.h's plain build counts the lines it
# hands out and, when the runner names a file in DIO_CASE_FILE, writes there
# which one it died on from a signal handler, on a stack of its own, then
# dies of the same signal. The toy reprints each record and dies on its third
# line: a write through NULL, a recursion that never ends (which a handler on
# the stack it exhausted could not run on), abort(), or a trap (an illegal
# instruction, which is how __builtin_trap() ends a run).
cat > "$WORK/cols/diff_dio_die.c" <<'DIO_DIE'
/* Toy reader harness for the plain build's death report.
 * Line: <n>\t<word>. Reprints the record; dies on its third line. */
#include "diffio.h"

static unsigned long	dio_toy_deep(unsigned long n)
{
	volatile char	pad[4096];

	pad[0] = (char)n;
	if (n == 0)
		return (0);
	return (dio_toy_deep(n + 1) + (unsigned long)pad[0]);
}

int	main(int ac, char **av)
{
	char	line[256];
	char	*f[2];
	int		i;

	i = 0;
	while (dio_line(line, sizeof(line)))
	{
		dio_split(line, f, 2);
		if (++i == 3 && ac > 1 && av[1][0] == 'r')
			printf("%lu\n", dio_toy_deep(1));
		else if (i == 3 && ac > 1 && av[1][0] == 'a')
			abort();
		else if (i == 3 && ac > 1 && av[1][0] == 't')
			__builtin_trap();
		else if (i == 3)
			*(volatile int *)NULL = 1;
		printf("%s\t%s\n", f[0], f[1]);
	}
	return (0);
}
DIO_DIE
if ! st_mine; then
	:
elif toy_cc "$WORK/dio_die" -g -O0 -I"$TOOLS" "$WORK/cols/diff_dio_die.c"; then
	for _dm in segv r a; do
		printf '#!/bin/sh\nexec "%s" %s\n' "$WORK/dio_die" "$_dm" > "$WORK/dio_die_$_dm"
		chmod +x "$WORK/dio_die_$_dm"
	done
	want_out "rust_diff: a plain harness that dies names the case" 'on corpus case #3 of 24' -- \
		rd --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --student-bin "$WORK/dio_die_segv"
	# The line as reproducer gives one: a shell word, and the command that
	# replays it (the review of V46 found a raw line, its tab unrendered,
	# and "feed the line to your harness" with no way to).
	want_out "rust_diff: ...showing its line as a shell word" "printf -- '02\\011case-2'" -- \
		rd --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --student-bin "$WORK/dio_die_segv"
	want_out "rust_diff: ...with the command that replays it" "WORD | $WORK/dio_die_segv runs it" -- \
		rd --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --student-bin "$WORK/dio_die_segv"
	# ...and said once: the harness's stderr, shown under the report, is the
	# program's own. The number used to be written there too, and shown a
	# second time.
	want_broken_none "rust_diff: ...and no second copy on stderr" 'corpus case #3:' -- \
		rd --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --student-bin "$WORK/dio_die_segv"
	want_out "rust_diff: ...and still dies of its own signal" 'killed by SIGSEGV' -- \
		rd --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --student-bin "$WORK/dio_die_segv"
	want_broken_none "rust_diff: ...never sending the reader to cases it passed" \
		'possibly thousands after' -- \
		rd --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --student-bin "$WORK/dio_die_segv"
	want_out "rust_diff: a recursion that never ends names it too" 'on corpus case #3 of 24' -- \
		rd --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --student-bin "$WORK/dio_die_r"
	want_out "rust_diff: ...and so does an abort" 'on corpus case #3 of 24' -- \
		rd --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --student-bin "$WORK/dio_die_a"
	# ONLY WHEN ASKED. The number counts rust_diff's corpus, and the same
	# harnesses are run by others: diff_output.sh's --harness-fixture over
	# Rush 00's case files, whose comment lines it would count, and perf and
	# cycles. Written to stderr, it reached those logs with a case number
	# nobody could match (the review of V46: "corpus case #6" for the third
	# case of a file with three comment lines). Run bare, the toy says nothing.
	"$WORK/mini_oracle" > "$WORK/dio_die.in"
	want_broken_none "diffio: a harness run bare names no case" 'corpus case' -- \
		sh -c '"$1" < "$2" 2>&1; exit 0' sh "$WORK/dio_die" "$WORK/dio_die.in"
fi
# The same toy built with ASan, as the diff_asan layer runs it. The death
# callback runs only for a death ASan reports itself, and by default it
# leaves SIGABRT and SIGILL to the program (handle_abort=0, handle_sigill=0):
# an abort() or a trap ended the run with no case named. Built where a
# sanitized program can be, as the overflow toy above is.
if ! st_mine; then
	:
elif [ "$SAN" != 1 ]; then
	st_skipped "diff_asan: (sanitizer build unavailable) for an abort or a trap" skipped
elif toy_cc "$WORK/dio_die_san" -g -fsanitize=address,undefined -fno-sanitize-recover=all \
		-fuse-ld=bfd -I"$TOOLS" "$WORK/cols/diff_dio_die.c"; then
	for _dm in a t; do
		printf '#!/bin/sh\nexec "%s" %s\n' "$WORK/dio_die_san" "$_dm" > "$WORK/dio_die_san_$_dm"
		chmod +x "$WORK/dio_die_san_$_dm"
	done
	want_out "diff_asan: a sanitized harness that aborts names the case" 'on corpus case #3 of 24' -- \
		rd_sym --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_die_san_a"
	want_out "diff_asan: ...and one that traps" 'on corpus case #3 of 24' -- \
		rd_sym --oracle "$WORK/mini_oracle" --oracle-fn x \
			--seed 1 --count 24 --crash-only --student-bin "$WORK/dio_die_san_t"
fi
# The consumer the review found it in: a harness output fixture built on
# tools/diffio.h (Rush 00's test_rush.c and survive_rush.c), its case file
# opening on comment lines, dying on its third case under diff_output.sh.
cat > "$WORK/cols/fix_dio_die.c" <<'FIX_DIO_DIE'
/* Toy harness output fixture: Line: <label>\t<value>, '#' lines skipped.
 * Reprints the record; dies on the label "boom". */
#include "diffio.h"

int	main(void)
{
	char	line[256];
	char	*f[2];

	while (dio_line(line, sizeof(line)))
	{
		if (line[0] == '#' || dio_split(line, f, 2) < 2)
			continue ;
		if (strcmp(f[0], "boom") == 0)
			*(volatile int *)NULL = 1;
		printf("%s\t%s\n", f[0], f[1]);
	}
	return (0);
}
FIX_DIO_DIE
printf '# one\n# two\n# three\nalpha\tA\nbeta\tB\nboom\tC\ndelta\tD\n' > "$WORK/fix_dio_die.tsv"
printf 'alpha\tA\nbeta\tB\nboom\tC\ndelta\tD\n' > "$WORK/fix_dio_die.txt"
if ! st_mine; then
	:
elif toy_cc "$WORK/fix_dio_die" -g -O0 -I"$TOOLS" "$WORK/cols/fix_dio_die.c" "$TOOLS/unbuffered_stdout.c"; then
	fix_dio_run() {
		"$SH" "$TOOLS/diff_output.sh" --bin "$WORK/fix_dio_die" --harness-fixture \
			--expected "$WORK/fix_dio_die.txt" --stdin "$WORK/fix_dio_die.tsv" --labeled
	}
	want_out "diff_output: a diffio fixture that dies marks its case" \
		'running when the program died' -- fix_dio_run
	want_broken_none "diff_output: ...and names no corpus case" 'corpus case' -- fix_dio_run
fi

# A LINE LONGER THAN A HARNESS'S BUFFER (finding 041). dio_line used fgets
# alone, which splits a long line silently: its head came back as one case and
# its tail as the next, each decoded as though whole, and judged against
# answers for cases nobody wrote. Now dio_line refuses one, exit 2, and the
# runner reports a broken harness, not the student; dio_getline takes a line
# of any length. A toy reader with a 16-byte buffer, which only echoes.
cp "$TOOLS/diffio.h" "$WORK/diffio.h"
printf '#include "diffio.h"\nint main(void){char b[16];while(dio_line(b,sizeof(b)))printf("%%s\\n",b);return 0;}\n' \
	> "$WORK/dio_small.c"
printf '#include "diffio.h"\nint main(void){char *b=NULL;size_t c=0;while(dio_getline(&b,&c))printf("%%s\\n",b);free(b);return 0;}\n' \
	> "$WORK/dio_any.c"
! st_mine || toy_cc "$WORK/dio_small" -I "$WORK" "$WORK/dio_small.c"
! st_mine || toy_cc "$WORK/dio_any" -I "$WORK" "$WORK/dio_any.c"
printf 'short\n%s\nlast\n' "0123456789abcdefghijklmnopqrstuvwxyz" > "$WORK/dio_long.txt"
printf '%015d\n%015d' 7 8 > "$WORK/dio_fit.txt"
want_broken "diffio: dio_line refuses a line longer than its buffer" \
	'longer than this harness' -- "$SH" -c '"$1" < "$2"' _ "$WORK/dio_small" "$WORK/dio_long.txt"
want_green "diffio: ...and takes one that fits exactly, newline or not" -- \
	"$SH" -c '[ "$("$1" < "$2")" = "$(printf "%015d\n%015d" 7 8)" ]' _ "$WORK/dio_small" "$WORK/dio_fit.txt"
want_green "diffio: dio_getline takes a line of any length, whole" -- \
	"$SH" -c '"$1" < "$2" | cmp -s - "$2"' _ "$WORK/dio_any" "$WORK/dio_long.txt"
# A DESTINATION WITH NO ROOM FOR ITS TERMINATOR. dio_dest(s, len, cap) copies
# the string and writes its terminator at [len]: a case with cap <= len would
# have the harness write past its own block, which the ASan twin then blames
# on the student. It refuses one instead, exit 2, as dio_line does.
printf '#include "diffio.h"\nint main(int c, char **v){unsigned char *b=dio_dest((const unsigned char *)"abc",3,(size_t)atoi(v[1]));printf("%%s\\n",(char *)b);free(b);(void)c;return 0;}\n' \
	> "$WORK/dio_dest.c"
! st_mine || toy_cc "$WORK/dio_dest" -I "$WORK" "$WORK/dio_dest.c"
want_broken "diffio: dio_dest refuses a cap with no room for the terminator" \
	'dio_dest: a string of len bytes needs a cap above len' -- "$WORK/dio_dest" 3
want_green "diffio: ...and takes one with exactly that room" -- \
	"$SH" -c '[ "$("$1" 4)" = abc ]' _ "$WORK/dio_dest"

# The runner: a harness that stopped itself is a harness error, never a verdict.
{
	printf '#!/bin/sh\ni=0\nwhile [ $i -lt 20 ]; do echo "case-$i"; i=$((i+1)); done\n'
	printf 'echo "%s"\n' "0123456789abcdefghijklmnopqrstuvwxyz"
} > "$WORK/dio_oracle"
chmod +x "$WORK/dio_oracle"
want_broken "rust_diff: a harness that cannot hold a corpus line is a harness error" \
	'could not read the corpus' -- \
	rd --oracle "$WORK/dio_oracle" --oracle-fn x \
		--seed 1 --count 21 --student-bin "$WORK/dio_small"
want_broken "rust_diff: ...under --crash-only too" 'longer than this harness' -- \
	rd --oracle "$WORK/dio_oracle" --oracle-fn x \
		--seed 1 --count 21 --crash-only --student-bin "$WORK/dio_small"
# A CORPUS LINE WITH FEWER FIELDS THAN ITS HARNESS READS. Every reader skipped
# one (`if (dio_split(...) < N) continue ;`) without a word: the value diff
# then blamed the student for answers the harness never printed, and the
# crash-only replay for an exit that came before the cases did. dio_fields
# stops the harness instead, exit 2, which the runner reports as its own
# fault in both modes. A real reader, Libft's ft_memchr one (a block, c and
# n, then the answer), over a toy that returns NULL, named apart and its
# call renamed to it (-D), fed twenty lines of two fields.
printf '#!/bin/sh\ni=0\nwhile [ $i -lt 20 ]; do printf "6162\\t97\\n"; i=$((i+1)); done\n' \
	> "$WORK/short_oracle"
chmod +x "$WORK/short_oracle"
printf '%s\n' '#include <stddef.h>' '' \
	'void	*toy_memchr_null(const void *s, int c, size_t n)' '{' \
	'	(void)s;' '	(void)c;' '	(void)n;' '	return (NULL);' '}' > "$WORK/toy_memchr_null.c"
! st_mine || toy_cc "$WORK/short_memchr" -I "$TOOLS" -Dft_memchr=toy_memchr_null \
	"$TOOLS/../cursus/Milestone_0/Libft/tests/ft_memchr/diff_ft_memchr.c" \
	"$WORK/toy_memchr_null.c"
want_broken "rust_diff: a corpus line with too few fields is a harness error" \
	'could not read the corpus' -- \
	rd --oracle "$WORK/short_oracle" --oracle-fn x \
		--seed 1 --count 20 --student-bin "$WORK/short_memchr"
want_broken "rust_diff: ...naming the line and how many fields it has" \
	'corpus line 1 has 2 field(s), fewer than the 3 this harness reads' -- \
	rd --oracle "$WORK/short_oracle" --oracle-fn x \
		--seed 1 --count 20 --student-bin "$WORK/short_memchr"
want_broken "rust_diff: ...under --crash-only too, never an OK or a FAIL" \
	'could not read the corpus' -- \
	rd --oracle "$WORK/short_oracle" --oracle-fn x \
		--seed 1 --count 20 --crash-only --student-bin "$WORK/short_memchr"

# WHICH ITEM A SEARCH RETURNED. C 13 ex05's reader printed the returned
# item's bytes alone, and the query and every item equal to it have the same
# bytes: a search that handed back data_ref itself, or another of several
# equal items, passed every case. It prints the returned pointer's index in
# the tree now (-1 for a pointer that is no node's item), and the reference
# the index of the item it returns. Two stand-in corpora of one tree each:
# a lone "a", and "m a a", the second "a" hanging right of the first, where
# the reference returns item 1. The toys walk nothing: each hands back a
# fixed pointer, named apart and the reader's call renamed to it (-D), over
# the structure the subject prints. The query's own copy and the item two
# links down are divergences; the item the reference names passes, which is
# the premise that the index the reader prints is the pool's.
mkdir -p "$WORK/c13rd"
printf '%s\n' '#ifndef FT_BTREE_H' '# define FT_BTREE_H' \
	'typedef struct s_btree' '{' '	struct s_btree	*left;' '	struct s_btree	*right;' \
	'	void			*item;' '}	t_btree;' \
	'void	*btree_search_item(t_btree *root, void *data_ref, int (*cmpf)(void *, void *));' \
	'#endif' > "$WORK/c13rd/ft_btree.h"
c13rd_oracle() {  # c13rd_oracle NAME LINE -- an oracle that prints LINE 20 times
	printf '#!/bin/sh\ni=0\nwhile [ $i -lt 20 ]; do printf "%s\\n"; i=$((i+1)); done\n' "$2" \
		> "$WORK/c13rd/$1"
	chmod +x "$WORK/c13rd/$1"
}
c13rd_oracle lone '61\\t-\\t61\\t0\\t61'
c13rd_oracle dup '6d,61,61\\t-,0L,1R\\t61\\t1\\t61'
c13rd_toy() {  # c13rd_toy NAME BODY-LINE... -- a toy built into the reader
	_c13n=$1
	shift
	printf '%s\n' '#include "ft_btree.h"' \
		'void	*btree_search_item(t_btree *root, void *data_ref, int (*cmpf)(void *, void *))' \
		'{' "$@" '}' > "$WORK/c13rd/$_c13n.c"
	toy_cc "$WORK/c13rd/$_c13n" -I "$TOOLS" -I "$WORK/c13rd" -Dbtree_search_item="toy_$_c13n" \
		"$TOOLS/../c-piscine/c-piscine-c-13/tests/ex05/diff_btree_search_item.c" \
		"$WORK/c13rd/$_c13n.c"
}
c13rd() {  # c13rd ORACLE TOY -- the corpus through rust_diff.sh, as the target runs it
	rd --oracle "$WORK/c13rd/$1" --oracle-fn c13_search_item \
		--seed 1 --count 20 --student-bin "$WORK/c13rd/$2"
}
if st_mine; then
	c13rd_toy query '	if (root != (void *)0 && cmpf(root->item, data_ref) == 0)' \
		'		return (data_ref);' '	return ((void *)0);'
	c13rd_toy root '	if (root != (void *)0 && cmpf(root->item, data_ref) == 0)' \
		'		return (root->item);' '	return ((void *)0);'
	c13rd_toy other '	(void)data_ref;' '	(void)cmpf;' '	return (root->left->right->item);'
	c13rd_toy named '	(void)data_ref;' '	(void)cmpf;' '	return (root->left->item);'
fi
want_red "C 13 ex05 reader: the query's own copy is not the tree's item" -- c13rd lone query
want_green "...the root's own item passes (premise)" -- c13rd lone root
want_red "...and an equal item other than the reference's is red" -- c13rd dup other
want_green "...the one the reference names passes (premise)" -- c13rd dup named

# WHERE A RETURNED POINTER POINTS. C 03 ex04's reader printed the bytes
# ft_strstr's pointer points at, up to their NUL: a pointer outside the
# haystack whose bytes are the same -- to_find itself, on a match that ends
# where the haystack ends -- passed. It prints the pointer's offset into the
# haystack now, NULL, or OUTSIDE, as Libft's ft_strnstr reader does. A
# stand-in corpus of one case, "bc" in "abc", at offset 1, 20 lines; the
# toys search nothing: one returns to_find, one the haystack plus a fixed 1.
mkdir -p "$WORK/c03rd"
printf '#!/bin/sh\ni=0\nwhile [ $i -lt 20 ]; do printf "616263\\t6263\\t1\\n"; i=$((i+1)); done\n' \
	> "$WORK/c03rd/oracle"
chmod +x "$WORK/c03rd/oracle"
printf '%s\n' 'char	*ft_strstr(char *str, char *to_find)' '{' '	(void)str;' '	return (to_find);' '}' \
	> "$WORK/c03rd/needle.c"
printf '%s\n' 'char	*ft_strstr(char *str, char *to_find)' '{' '	(void)to_find;' '	return (str + 1);' '}' \
	> "$WORK/c03rd/one.c"
for _c03t in needle one; do
	! st_mine || toy_cc "$WORK/c03rd/$_c03t" -I "$TOOLS" -Dft_strstr="toy_strstr_$_c03t" \
		"$TOOLS/../c-piscine/c-piscine-c-03/tests/ex04/diff_strstr.c" "$WORK/c03rd/$_c03t.c"
done
c03rd() {  # c03rd TOY -- the corpus through rust_diff.sh, as the target runs it
	rd --oracle "$WORK/c03rd/oracle" --oracle-fn c03_strstr \
		--seed 1 --count 20 --student-bin "$WORK/c03rd/$1"
}
want_red "C 03 ex04 reader: returning to_find, the same bytes, diverges" -- c03rd needle
want_out "...said to point OUTSIDE the haystack" '6263\tOUTSIDE' -- c03rd needle
want_green "...and the offset the reference names passes (premise)" -- c03rd one

# A reader harness that never built: the corpus is not replayed through a
# script that prints a compiler error, so there is no "divergence" to report.
want_red "rust_diff: a stand-in is red, not a divergence" -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$STANDIN_BIN"
want_out "rust_diff: ...says the code did not build" "$STANDIN_SAYS" -- \
	rd --oracle "$WORK/cols/oracle.sh" --oracle-fn f \
		--seed 1 --count 40 --student-bin "$STANDIN_BIN"

# THE TIME BUDGET (finding 066). The student's harness ran with no limit at all,
# so a slow or looping answer died as a bare Bazel TIMEOUT with an empty log --
# and the "killed by SIGKILL" report below could never be reached, because
# Bazel killed the runner too. Now the replay gets what is left of the test's
# own limit, and an overrun is said in one sentence naming where it got to.
printf '#!/bin/sh\nexec sleep 20\n' > "$WORK/hang_student"; chmod +x "$WORK/hang_student"
later_red_out "rust_diff: a harness that never ends is stopped, and said" \
	's: an infinite loop, or too slow on the input' -- \
	$SHORT "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --student-bin "$WORK/hang_student"
# ...and says the limit was the TEST's, in the words tools/first_red.sh can
# tell from a run its own cap stopped (RL_OVERRUN_MARK).
later_red_out "rust_diff: ...naming the test's own limit as the one that ran out" \
	"this test's own time limit" -- \
	$SHORT "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --student-bin "$WORK/hang_student"
later_red_out "rust_diff: --crash-only is bounded the same way" \
	's: an infinite loop, or too slow on' -- \
	$SHORT "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/mini_oracle" --oracle-fn x \
		--seed 1 --count 24 --crash-only --student-bin "$WORK/hang_student"

# THE GATE, AS EVERY RUNNER THAT TAKES ONE RUNS IT (tools/runner_lib.sh,
# rl_gate), held for the runners that ran their own copy of it: the differ
# is handed --stdin, --sanitize and --labeled; its exit 1 SKIPs, naming the
# output test; its exit 2 is said and the layer runs on; and NO_SKIP=1 runs
# the layer without asking it. gate_spy.sh is a differ that writes down the
# words it was handed and exits GATE_SPY_RC; gate_seen prints what a run
# said, its status and those words, whatever the status, for arms that read
# one line of it. The cycles_check and ref_compare sections use them too.
printf '#!/bin/sh\nprintf "%%s " "$@" > "$GATE_SPY_ARGV"\nexit "$GATE_SPY_RC"\n' \
	> "$WORK/gate_spy.sh"
chmod +x "$WORK/gate_spy.sh"
: > "$WORK/gate_in.txt"
GATE_SPY="--gate-differ $WORK/gate_spy.sh --gate-bin $WORK/gate_spy.sh --gate-expected $WORK/gate_in.txt --gate-stdin $WORK/gate_in.txt --gate-sanitize --gate-labeled --gate-label lbl_output"
gate_seen() (  # gate_seen RC COMMAND... -- COMMAND over gate_spy.sh exiting RC
	GATE_SPY_RC=$1
	GATE_SPY_ARGV="$WORK/gate_spy.argv"
	export GATE_SPY_RC GATE_SPY_ARGV
	shift
	rm -f "$GATE_SPY_ARGV"
	"$@" 2>&1
	echo "status=$?"
	if [ -f "$GATE_SPY_ARGV" ]; then echo "differ: $(cat "$GATE_SPY_ARGV")"; else echo "differ: not run"; fi
	return 0
)
# shellcheck disable=SC2086 # GATE_SPY is a list of words without blanks
rd_gate() { gate_seen "$1" env "$2" "$SH" "$TOOLS/rust_diff.sh" --oracle "$WORK/empty_oracle" \
	--oracle-fn x --student-bin "$WORK/null_student" $GATE_SPY; }
want_out "rust_diff: its gate hands the differ --stdin, --sanitize and --labeled" \
	"--expected $WORK/gate_in.txt --stdin $WORK/gate_in.txt --sanitize --labeled" -- \
	rd_gate 0 NO_SKIP=0
want_out "rust_diff: ...its exit 1 SKIPs, naming the test" 'SKIP — lbl_output, this exercise' -- \
	rd_gate 1 NO_SKIP=0
# ...with the command that runs it anyway, and under the layer's own
# paragraph (RL_GATE_WHY), never rl_gate's default: the copies of the gate
# these runners kept had dropped the first, and nothing held the second.
want_out "rust_diff: ...saying how to run it anyway" '--test_env=NO_SKIP=1 runs it anyway.)' -- \
	rd_gate 1 NO_SKIP=0
want_out "rust_diff: ...under its own paragraph" 'cases and reports raw divergences' -- \
	rd_gate 1 NO_SKIP=0
want_out "rust_diff: ...its exit 2 is said" 'could not be evaluated (exit 2)' -- \
	rd_gate 2 NO_SKIP=0
want_out "rust_diff: ...and runs on" 'fewer than the 16 this layer needs' -- rd_gate 2 NO_SKIP=0
want_out "rust_diff: ...and NO_SKIP=1 runs without asking it" 'differ: not run' -- \
	rd_gate 1 NO_SKIP=1
