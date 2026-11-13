# ------------------------------------ conventions: wider types, named methods
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A hint that answers an overflow with a wider type (finding 060, WP-75):
# a diff legend's "the accumulator's type" and a clue asking for "a wider
# type" (both reported), and one asking whether the value has to be formed
# at all, beside a long string, which is no type (quiet). A diff hint wraps,
# so the phrase is found across a line end, in a readings target's legend
# too (ex35, reported, at the line it starts on); the question about every
# platform, wrapped the same way, is not (ex36). A report cuts its excerpt
# at 70 bytes, never inside a character: a clue whose 69th to 71st bytes
# are one dash ends before it (ex71's second row).
# shellcheck disable=SC2154 # set in conventions_bazel_run_first_red_hints.sh
mkdir -p "$_cv99/ex70" "$_cv99/ex71" "$_cv99/ex72" "$_cv99/ex35" "$_cv99/ex36"
printf '  The input is text.\n    * only long inputs  -> the accumulator%ss\n                           type\n' "'" \
	> "$_cv99/ex35/diff_clues_readings.txt"
printf '  The input is text.\n    * only long inputs  -> does every type the value passes\n                           through hold it on every platform?\n' \
	> "$_cv99/ex36/diff_clues.txt"
printf '  Text in, a number out.\n    * only long inputs  -> the accumulator%ss type\n' "'" \
	> "$_cv99/ex70/diff_clues.txt"
printf 'Which wider type holds the sum?\nWhich wider type holds the sum so that it never overflows on the way\342\200\224 there?\n' \
	> "$_cv99/ex71/clues.tsv"
{
	printf '  Text in, a number out.\n'
	printf '    * only long inputs  -> every value fits an int: does anything computed on the\n'
	printf '                           way to it not fit? Is it held in a long string?\n'
} > "$_cv99/ex72/diff_clues.txt"
! st_mine || conv > "$WORK/cv.widen" 2>&1
want_out "conventions: a legend naming the accumulator's type is reported" \
	'c-99/tests/ex70/diff_clues.txt:2:' -- cv_saved "$WORK/cv.widen"
want_out "conventions: ...and a clue asking for a wider type" \
	'c-99/tests/ex71/clues.tsv:1:' -- cv_saved "$WORK/cv.widen"
want_broken_none "conventions: ...not one asking whether it has to be formed" \
	'c-99/tests/ex72/diff_clues.txt' -- cv_saved "$WORK/cv.widen"
# cv_line_end TEXT RUN: the report line holding TEXT in the saved RUN, with
# its end made visible, read byte by byte, and the run's status.
cv_line_end() {
	_cle_l=$(cv_saved "$2" env LC_ALL=C grep -F -- "$1")
	_cle_rc=$?
	[ -z "$_cle_l" ] || printf '%s\n' "$_cle_l" | LC_ALL=C sed 's/$/|end/'
	return "$_cle_rc"
}
want_out "conventions: ...its excerpt cut before a character, never inside one" \
	'never overflows on the way|end' -- cv_line_end 'c-99/tests/ex71/clues.tsv:2:' "$WORK/cv.widen"
want_out "conventions: ...and a legend's phrase wrapped across a line end, in a readings legend" \
	'c-99/tests/ex35/diff_clues_readings.txt:2:' -- cv_saved "$WORK/cv.widen"
want_out "conventions: ...named at the line it starts on, and the line it ends on" \
	"the accumulator's (wrapped onto line 3)" -- cv_saved "$WORK/cv.widen"
want_broken_none "conventions: ...but not the question about every platform, wrapped" \
	'c-99/tests/ex36/diff_clues.txt' -- cv_saved "$WORK/cv.widen"
rm -f "$WORK/cv.widen"

# A hint that names a loop's inner workings or a step of a known method
# (AGENTS.md section 2): a legend row naming the outer scan, wrapped across a
# line end (reported at the line it starts on), beside "a loop that cannot
# run zero times" (quiet) and a row whose '#' line above it says why it names
# one (quiet, its wrapped line too); a clue that would advance the candidate
# (reported) beside one marked the same way (quiet); "the base case" in an
# exercise whose BUILD call declares method = "recursive" (quiet) and in one
# that declares nothing (reported); and a harness whose "Line:" paragraph
# names the inner loop (reported at its own line of the file) beside one
# whose header carries the marker below the paragraph (quiet) and one whose
# marker sits inside the paragraph, where print_columns would show it to the
# student (reported). A report cuts its excerpt at 70 bytes, never inside a
# character: a clue whose 69th to 71st bytes are one dash ends before it.
# Two orders of steps once got past it, an index that moves before the byte
# at it is printed and a negative number made positive first: a legend row
# of the first shape and a clue row of the second (reported), beside a clue
# asking what a value is before it is written, and one saying the most
# negative int has no positive counterpart (quiet). And three more orders
# (V173): a pointer that steps past the byte, or is advanced, before it is
# copied, and a number negated before printing (reported), beside a clue
# asking whether the scan stops before reading past the end (quiet).
# shellcheck disable=SC2154 # set in conventions_bazel_run_first_red_hints.sh
mkdir -p "$_cv98/ex66" "$_cv98/ex67" "$_cv98/ex68" "$_cv98/ex69"
{
	printf '  The input is a list of numbers.\n'
	printf '    * only long inputs  -> where the outer\n'
	printf '                           scan stops\n'
	printf '    * the empty input   -> a loop that cannot run zero times\n'
	printf '  # conventions: method named -- the toy subject names this method\n'
	printf '    * only primes       -> the bound on the trial\n'
	printf '                           division loop\n'
	printf '    * shifted by one    -> the index moves before the\n'
	printf '                           character at it is printed\n'
} > "$_cv98/ex66/diff_clues.txt"
# ...and a phrase split around a # line, which no run prints: the rule
# ended the phrase there (reported, at lines 10 and 12).
printf '    * only odd inputs   -> where the inner\n  # a note for maintainers\n                           loop stops\n' \
	>> "$_cv98/ex66/diff_clues.txt"
printf '/* Toy harness.\n * Line: <n>\\t<out>. Reads n, then runs the inner\n * loop on it.\n *\n * Not read. */\n' \
	> "$_cv98/ex66/diff_toy.c"
printf '/* Toy harness.\n * Line: <n>\\t<out>. Reads n, then runs the inner\n * loop on it.\n *\n * conventions: method named -- the toy subject names it */\n' \
	> "$_cv98/ex69/diff_toy.c"
printf '/* Toy harness.\n * Line: <n>\\t<out>. Reads n, then runs the inner\n * loop on it.\n * conventions: method named -- the toy subject names it */\n' \
	> "$_cv98/ex68/diff_toy.c"
{
	printf 'Could you advance the candidate until it passes?\n'
	printf '# conventions: method named -- the toy subject asks for this one\n'
	printf 'Could you square the divisor to test it?\n'
	printf 'Could you advance the candidate until it passes, and ask again, each\342\200\224 time?\n'
	printf 'What does a printer that makes a negative number positive do with the smallest one?\n'
	printf 'What is n before it is written in the base?\n'
	printf 'The most negative int has no positive counterpart. Which rows fail?\n'
	printf 'The pointer steps past the byte before it is copied.\n'
	printf 'A printer that negates the number before printing: which row fails?\n'
	printf 'Could you advance the pointer before the byte is copied?\n'
	printf 'Do you stop scanning before reading past the end?\n'
} > "$_cv98/ex67/clues.tsv"
printf 'What does the base case return?\n' > "$_cv98/ex68/clues.tsv"
printf 'What does the base case return?\n' > "$_cv98/ex69/clues.tsv"
cp "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel" "$WORK/cv.method.keep"
printf '\nc_function(\n    num = "68",\n    method = "recursive",\n)\n' \
	>> "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
! st_mine || conv > "$WORK/cv.method" 2>&1
mv "$WORK/cv.method.keep" "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
rm -rf "$_cv98/ex66" "$_cv98/ex67" "$_cv98/ex68" "$_cv98/ex69"
want_out "conventions: a legend naming the outer scan, wrapped, is reported" \
	'c-98/tests/ex66/diff_clues.txt:2:     * only long inputs  -> where the outer (wrapped onto line 3)' -- \
	cv_saved "$WORK/cv.method"
want_broken_none "conventions: ...not a loop that cannot run zero times" \
	'c-98/tests/ex66/diff_clues.txt:4:' -- cv_saved "$WORK/cv.method"
want_broken_none "conventions: ...nor a legend row marked as naming one, wrapped" \
	'c-98/tests/ex66/diff_clues.txt:6:' -- cv_saved "$WORK/cv.method"
want_out "conventions: a clue that advances the candidate is reported" \
	'c-98/tests/ex67/clues.tsv:1:' -- cv_saved "$WORK/cv.method"
want_broken_none "conventions: ...not one marked as naming one" \
	'c-98/tests/ex67/clues.tsv:3:' -- cv_saved "$WORK/cv.method"
want_broken_none "conventions: the base case of an exercise the subject makes recursive is quiet" \
	'c-98/tests/ex68/clues.tsv:1:' -- cv_saved "$WORK/cv.method"
want_out "conventions: ...and reported in one it does not" \
	'c-98/tests/ex69/clues.tsv:1:' -- cv_saved "$WORK/cv.method"
want_out "conventions: a harness's Line: paragraph naming the inner loop is reported" \
	'c-98/tests/ex66/diff_toy.c:2: Line: <n>\t<out>. Reads n, then runs the inner (wrapped onto line 3)' -- \
	cv_saved "$WORK/cv.method"
want_broken_none "conventions: ...not one whose header carries the marker" \
	'c-98/tests/ex69/diff_toy.c:2:' -- cv_saved "$WORK/cv.method"
want_out "conventions: ...but a marker inside the paragraph the student sees exempts nothing" \
	'c-98/tests/ex68/diff_toy.c:2: Line: <n>\t<out>. Reads n, then runs the inner (wrapped onto line 3)' -- \
	cv_saved "$WORK/cv.method"
want_out "conventions: ...its excerpt cut before a character, never inside one" \
	'and ask again, each|end' -- cv_line_end 'c-98/tests/ex67/clues.tsv:4:' "$WORK/cv.method"
want_out "conventions: a legend row on the index moving before the byte is printed is reported" \
	'c-98/tests/ex66/diff_clues.txt:8:     * shifted by one    -> the index moves before the (wrapped onto line 9)' -- \
	cv_saved "$WORK/cv.method"
want_out "conventions: ...and a clue that makes a negative number positive" \
	'c-98/tests/ex67/clues.tsv:5:' -- cv_saved "$WORK/cv.method"
want_broken_none "conventions: ...never one asking what a value is before it is written" \
	'c-98/tests/ex67/clues.tsv:6:' -- cv_saved "$WORK/cv.method"
want_broken_none "conventions: ...nor one saying the smallest int has no positive counterpart" \
	'c-98/tests/ex67/clues.tsv:7:' -- cv_saved "$WORK/cv.method"
want_out "conventions: a clue whose pointer steps past the byte before it is copied" \
	'c-98/tests/ex67/clues.tsv:8:' -- cv_saved "$WORK/cv.method"
want_out "conventions: ...one that negates the number before printing" \
	'c-98/tests/ex67/clues.tsv:9:' -- cv_saved "$WORK/cv.method"
want_out "conventions: ...one that advances the pointer before the byte is copied" \
	'c-98/tests/ex67/clues.tsv:10:' -- cv_saved "$WORK/cv.method"
want_broken_none "conventions: ...never one asking if the scan stops before the end" \
	'c-98/tests/ex67/clues.tsv:11:' -- cv_saved "$WORK/cv.method"
want_out "conventions: a legend phrase split around a # line is read whole" \
	'c-98/tests/ex66/diff_clues.txt:10:     * only odd inputs   -> where the inner (wrapped onto line 12)' -- \
	cv_saved "$WORK/cv.method"
rm -f "$WORK/cv.method"

