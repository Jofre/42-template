#!/bin/sh
# argv_check.sh — differential check for a program whose input is its ARGUMENTS.
#
# Runs the student's binary once per case against a corpus //oracle generated,
# and reports the first differences as a table.
#
# Usage:
#   argv_check.sh --bin PATH --oracle PATH --fn NAME
#                 [--seed N] [--count N] [--show N] [--expect-reordering]
#
# NO GATE, unlike bsq_check.sh. That one skips while the exercise's own example
# is red, because replaying hundreds of generated maps then says the same thing
# hundreds of times. c-06's first-red layer is its argv TABLE -- one labelled
# row per hand-written scenario -- and it is a separate target that stays red on
# its own. A wall here collapses to one line anyway: the report shows the first
# --show cases and then tallies the rest by kind, so an unwritten exercise reads
# as "200 of 200 differ, by kind: 200 no-output".
#
# NOT argv[0]. A program that must print its own invocation name needs to be
# COPIED to that name and run there, and tools/progname_test.sh already does
# exactly that -- under two names, checking the exit status as well as the
# output. c-06 ex00 uses that layer; a second one here would be a copy.
#
# WHY THIS EXISTS BESIDE bsq_check.sh AND rush02_check.sh. Those two each carry
# a corpus shape their subject forced: bsq's cases are FILES and rush-02's is a
# single number with a dictionary. c-06's four programs share one shape -- a
# list of arguments and the bytes they must produce -- and nothing about it is
# specific to c-06, so it is written once here rather than four times there.
#
# ONE EXEC PER CASE, for the reason rush02_check.sh gives: a program that takes
# its input on the command line cannot be streamed. The count stays in the
# hundreds. That is a property of the subject, not a shortcut.
#
# THE CORPUS LINE, and why it is peeled rather than read into fields:
#
#     <tag>\t<nargs>\t<arg1>\t...\t<argN>\t<escaped-expected>
#
# `IFS=$TAB read a b c` cannot parse this. Tab is IFS whitespace, so a RUN of
# tabs is one separator and an empty field vanishes -- and an empty argument is
# one of the four cases this layer exists for. Peeling with ${x%%...} and
# ${x#...} keeps every field, including the empty ones. nargs is in the line so
# that the peel is exact rather than a guess about which tab ends the arguments.
#
# Every field is POSIX-escaped (`\n`, `\t`, `\\`, `\0NNN` octal). dash's
# `printf %b` decodes `\0NNN` and prints `\xHH` back literally, which is why the
# reference emits octal and asserts that it never emits hex.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "argv_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat cmp mktemp rm sed sort tr uniq wc

BIN=""
ORACLE=""
FN=""
SEED=1
COUNT=200
SHOW=8
EXPECT_REORDER=0

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "argv_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--seed) need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--show) need "$1" "$#"; SHOW="$2"; shift 2 ;;
		--expect-reordering) EXPECT_REORDER=1; shift ;;
		*) echo "argv_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$BIN" ] || { echo "argv_check.sh: --bin is required" >&2; exit 2; }
[ -n "$ORACLE" ] || { echo "argv_check.sh: --oracle is required" >&2; exit 2; }
[ -n "$FN" ] || { echo "argv_check.sh: --fn is required" >&2; exit 2; }
[ -x "$BIN" ] || { echo "argv_check.sh: not executable: $BIN" >&2; exit 2; }
[ -x "$ORACLE" ] || { echo "argv_check.sh: not executable: $ORACLE" >&2; exit 2; }
WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM

TAB=$(printf '\t')

# Decode one escaped field WITHOUT losing a trailing newline.
#
# `v=$(printf '%b' "$f")` is wrong here and the difference is a whole class of
# case: command substitution strips every trailing newline, so an expected block
# that ENDS in one -- which every one of them does -- would arrive a byte short
# and the layer would report a difference the student did not cause. The
# sentinel dot is the last byte, so nothing of the value is stripped, and it is
# removed afterwards.
#
# Only for the block that is REDIRECTED to a file. A caller writing
# `$(dec "$x")` wraps a second substitution around the first and loses exactly
# what this preserves; the argument peel does the same two lines inline for
# that reason.
dec() {
	_d=$(printf '%b.' "$1")
	printf '%s' "${_d%.}"
}

"$ORACLE" "$FN" "$SEED" "$COUNT" > "$WORK/corpus.tsv" 2> "$WORK/oracle.err" || {
	echo "argv_check: the reference failed to produce a corpus for '$FN'." >&2
	sed -n '1,10p' "$WORK/oracle.err" >&2
	exit 2
}

CASES=$(wc -l < "$WORK/corpus.tsv")

# ---------------------------------------------------------------------------
# FLOORS. Every one of these is a corpus that would pass a program that does
# nothing of what the exercise asks, so a corpus failing them is a layer
# reporting OK having checked nothing -- exit 2, not 1.
MIN_CASES=${MIN_ARGV_CASES:-12}
if [ "$CASES" -lt "$MIN_CASES" ]; then
	echo "argv_check: only $CASES cases (floor $MIN_CASES). Refusing to report OK." >&2
	exit 2
fi

# The properties a hand-written case never has, checked ON THE CORPUS rather
# than assumed from the generator's source.
_probe=$(awk -F'\t' '
	{
		n = $2 + 0
		if (n == 0) zero = 1
		if (n >= 2) multi = 1
		for (i = 3; i < 3 + n; i++) {
			if ($i == "") empty = 1
			if ($i ~ /\\/) esc = 1
		}
		if ($NF != "") nonempty = 1
	}
	END { printf "%d %d %d %d %d", zero, multi, empty, esc, nonempty }
' "$WORK/corpus.tsv")
set -- $_probe
[ "$1" = 1 ] || { echo "argv_check: no case with ZERO arguments. A program that prints a newline regardless would pass." >&2; exit 2; }
[ "$2" = 1 ] || { echo "argv_check: no case with two or more arguments." >&2; exit 2; }
[ "$3" = 1 ] || { echo "argv_check: no EMPTY argument. A loop that stops on the first empty string would pass." >&2; exit 2; }
[ "$4" = 1 ] || { echo "argv_check: no argument needing an escape. Whitespace and high bytes are half of what this layer is for." >&2; exit 2; }
[ "$5" = 1 ] || { echo "argv_check: every expected block is empty. A program that prints nothing would pass." >&2; exit 2; }

# For the arms where the ORDER is the answer: at least one case whose expected
# block is not the arguments in the order they were given. Without it a
# `ft_rev_params` corpus of palindromic cases would be passed by a program that
# does not reverse anything at all.
if [ "$EXPECT_REORDER" = 1 ]; then
	_reorder=$(awk -F'\t' '
		{
			n = $2 + 0
			plain = ""
			for (i = 3; i < 3 + n; i++) plain = plain $i "\\n"
			if ($NF != plain) { print "yes"; exit }
		}
	' "$WORK/corpus.tsv")
	[ "$_reorder" = "yes" ] || {
		echo "argv_check: no case where the output order differs from the input order," >&2
		echo "            so a program that just echoes its arguments would pass." >&2
		exit 2
	}
fi

# ---------------------------------------------------------------------------
# THE REPLAY.
FAILED=0
CHECKED=0
: > "$WORK/faults"
: > "$WORK/report"

# What KIND of difference is this? A hundred failures that are all one mistake
# should read as one mistake. The categories are ordered most-specific first.
classify() {  # classify EXPECTED-FILE GOT-FILE STATUS
	if [ "$3" -ge 128 ]; then echo "crash"; return; fi
	if [ ! -s "$2" ] && [ -s "$1" ]; then echo "no-output"; return; fi
	if [ -s "$2" ] && [ ! -s "$1" ]; then echo "output-when-none-expected"; return; fi
	# Same lines, different order: the content is right and the ordering rule
	# is not. That is ft_rev_params and ft_sort_params's whole exercise, and it
	# is worth saying so rather than printing two blocks of identical text.
	#
	# LC_ALL=C, because the corpus contains bytes that are not valid UTF-8 and
	# `sort` under a UTF-8 locale neither orders nor even accepts them
	# reliably. Without it a case whose only fault was the order came out as
	# the vaguer "content", which is the category that tells a student least.
	if LC_ALL=C sort "$1" > "$WORK/s1" 2> /dev/null &&
		LC_ALL=C sort "$2" > "$WORK/s2" 2> /dev/null &&
		cmp -s "$WORK/s1" "$WORK/s2"; then
		echo "wrong-order"
		return
	fi
	# The bytes agree up to the last newline: the only difference is whether
	# the output ends in one.
	if [ "$(cat "$1"; echo x)" = "$(cat "$2"; printf '\n'; echo x)" ]; then
		echo "missing-final-newline"
		return
	fi
	if [ "$(wc -l < "$1")" -ne "$(wc -l < "$2")" ]; then echo "line-count"; return; fi
	echo "content"
}

while IFS= read -r line; do
	[ -n "$line" ] || continue
	tag=${line%%"$TAB"*}; rest=${line#*"$TAB"}
	nargs=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}

	# Peel exactly nargs fields, then whatever is left is the expected block.
	# `set --` builds the real argument vector, so an argument containing a
	# space or a newline stays ONE argument all the way to execve -- which is
	# the difference this layer is looking for in the first place.
	set --
	_i=0
	while [ "$_i" -lt "$nargs" ]; do
		_f=${rest%%"$TAB"*}; rest=${rest#*"$TAB"}
		# The sentinel is stripped HERE and not inside a helper. `$(dec ...)`
		# would be a second command substitution wrapped around the first, and
		# the outer one strips the trailing newline the inner one went to
		# trouble to keep -- which showed up as eleven of a hundred and twenty
		# CORRECT cases reported as differences, every one of them an argument
		# ending in a newline.
		_v=$(printf '%b.' "$_f")
		set -- "$@" "${_v%.}"
		_i=$((_i + 1))
	done
	dec "$rest" > "$WORK/want"

	# `< /dev/null` on every run. Without it a program that reads stdin
	# consumes the rest of the corpus, the loop ends early, and the layer
	# reports "OK, 1 case" -- green, having checked almost nothing.
	"$BIN" "$@" < /dev/null > "$WORK/got" 2> /dev/null
	st=$?
	CHECKED=$((CHECKED + 1))

	if cmp -s "$WORK/want" "$WORK/got"; then
		continue
	fi
	FAILED=$((FAILED + 1))
	_fault=$(classify "$WORK/want" "$WORK/got" "$st")
	echo "$_fault" >> "$WORK/faults"

	[ "$FAILED" -le "$SHOW" ] || continue
	{
		printf '\n  case %d  [%s]  %s\n' "$CHECKED" "$tag" "$_fault"
		printf '    argv:     '
		if [ "$nargs" -eq 0 ]; then
			printf '(none)'
		else
			for _a in "$@"; do
				# Rendered with the escapes visible: an argument that is a
				# newline has to be readable in a report that is itself lines.
				printf '[%s] ' "$(printf '%s' "$_a" | sed -e 's/\\/\\\\/g' | awk '{ printf "%s\\n", $0 }' | sed 's/\\n$//')"
			done
		fi
		printf '\n'
		printf '    expected: '; sed -n '1,6p' "$WORK/want" | sed -e 's/$/$/' | tr '\n' ' '
		printf '\n    got:      '; sed -n '1,6p' "$WORK/got" | sed -e 's/$/$/' | tr '\n' ' '
		printf '\n'
		[ "$st" -lt 128 ] || printf '    (killed by signal %d)\n' "$((st - 128))"
	} >> "$WORK/report"
done < "$WORK/corpus.tsv"

# The loop must have SEEN the corpus. A program that eats stdin, a corpus whose
# last line has no newline, a `while read` that died on the first case: all of
# them end here with fewer cases run than the file holds, and all of them used
# to be reported as a pass.
if [ "$CHECKED" -ne "$CASES" ]; then
	echo "argv_check: ran $CHECKED of $CASES cases. Refusing to report on a partial replay." >&2
	exit 2
fi

if [ "$FAILED" -eq 0 ]; then
	echo "argv_check: PASS — $CHECKED cases, every one byte-identical to the reference."
	exit 0
fi

echo "argv_check: FAIL — $FAILED of $CHECKED cases differ from the reference."
cat "$WORK/report"
echo ""
echo "  by kind:"
LC_ALL=C sort "$WORK/faults" | uniq -c | sort -rn | sed 's/^/    /'
echo ""
echo "  Each line above is one invocation. \$ marks the end of a line, so a"
echo "  missing or extra newline is visible rather than inferred."
exit 1
