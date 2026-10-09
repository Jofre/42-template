#!/bin/sh
# ex08 — add_chelou.sh: the sum of two numbers written in bases of their own,
# in a third.
#
# WHAT IS COMPARED WITH WHAT. The subject prints two worked examples, and
# they are run first: their results are the subject's own text, so they are
# kept here as SHA-256 digests, never in clear. Then a set of pairs from
# //oracle's shell01_chelou, one for each class of input a program can get
# wrong while still passing both examples: zero as either operand and as the
# sum, each digit of FT_NBR1's base that the shell treats specially (the
# quotes, the backslash, '?', '!'), backslashes side by side, a lone '?', a
# sum more than 70 digits long, operands of very different lengths. Every one
# is a valid input ("takes numbers from FT_NBR1 ... and FT_NBR2"), and each
# has one answer, so they are basic: the subject's two examples are the only
# inputs it prints, not the only ones it asks about (finding 033). The
# reference's result for each pair goes to a file and is compared with the
# program's byte for byte; it is never printed. A failure prints the pair,
# quoted so it can be pasted back, and nothing else.
#
# The oracle has to agree with the subject before anything is judged by it:
# it reproduces both examples' digests, or this stops as a broken harness
# (exit 2) and judges nothing.
#
# The runs are made from a folder holding a one-letter file, so a '?' the
# shell expands as a pattern turns into that name instead of staying the
# digit it is.
#
# THE TERMINATOR. The sum is printed as a line, so the output ends with a
# newline, and the Moulinette compares stdout byte for byte. A $(...)
# capture strips it, so the examples' raw bytes are checked for it; the pairs
# compare what comes before it, so a missing newline fails one line and not
# every pair.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-add_chelou.sh}
printf "  CHECK: %s\n" "$D"

ck_require "add_chelou.sh exists" test -f "$D"
# The subject: shell exercises must be executable with /bin/sh.
ck_sh_parses "$D"

ORACLE=${ORACLE:?this check needs //oracle: declare the exercise with oracle = True}

# The two examples' results are stored as digests, and neither value is echoed.
# sha256sum is coreutils and present on the campus box; cksum is the fallback
# rather than skipping the comparison if it ever is not.
#
# PROVENANCE: each is the SHA-256 of the string the SUBJECT ITSELF prints as
# that example's result, hashed from the text of the module's subject PDF,
# and each agrees with //oracle's shell01_chelou on the same inputs, which is
# checked below on every run.
if command -v sha256sum >/dev/null 2>&1; then
	digest() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
	EXPECT1="75c4ec0328d2ec2e8cc1cfecda70808ab55a68645a100cd7b88b18ed9d44fd5d"
	EXPECT2="8af6fa80ee182c0cb5648538f4884858709919ed6fbbcb9088a3fd20dabf0c2a"
else
	# cksum prints "<sum> <bytes>", and that second field is each answer's
	# LENGTH, which is not published here either. Keep the sum.
	digest() { printf '%s' "$1" | cksum | cut -d' ' -f1; }
	EXPECT1="861911637"
	EXPECT2="4241385134"
fi

work=$(mktemp -d)
mkdir "$work/run"
: > "$work/run/q"
case "$D" in
	/*) DA=$D ;;
	*) DA=$PWD/$D ;;
esac

# body FILE -> FILE's bytes without the one newline that ends a line, on
# stdout: a line printed with its newline and the same line without one read
# the same here, and ck_final_newline judges that byte on its own.
body() {
	awk 'NR > 1 { printf "\n" } { printf "%s", $0 }' "$1"
}

# ref N1 N2 FILE -> the reference's result for the pair, into FILE.
ref() {
	env FT_NBR1="$1" FT_NBR2="$2" "$ORACLE" shell01_chelou > "$3" 2> /dev/null
}

# The reference against the subject's two examples, before it judges anything.
E1A='\'"'"'?"\"'"'"'\'
E1B='rcrdmddd'
E2A='\"\"!\"\"!\"\"!\"\"!\"\"!\"\"'
E2B='dcrcmcmooododmrrrmorcmcrmomo'
if ! ref "$E1A" "$E1B" "$work/ref1" || ! ref "$E2A" "$E2B" "$work/ref2" ||
	[ "$(digest "$(body "$work/ref1")")" != "$EXPECT1" ] ||
	[ "$(digest "$(body "$work/ref2")")" != "$EXPECT2" ]; then
	rm -rf "$work"
	ck_broken "the reference does not reproduce the subject's two examples"
fi

# --- the subject's Example 1 --------------------------------------------------
raw=$work/out
ck_run -C "$work/run" "$raw" env FT_NBR1="$E1A" FT_NBR2="$E1B" sh "$DA"
ck "Example 1: the subject's result for its first pair" \
	test "$(digest "$(body "$raw")")" = "$EXPECT1"
ck_final_newline "Example 1: output ends with a final newline (Moulinette byte-matches stdout)" "$raw"

# --- the subject's Example 2: operands that do not fit in a machine word ------
ck_run -C "$work/run" "$raw" env FT_NBR1="$E2A" FT_NBR2="$E2B" sh "$DA"
ck "Example 2: the subject's result for operands larger than a 64-bit word" \
	test "$(digest "$(body "$raw")")" = "$EXPECT2"
ck_final_newline "Example 2: output ends with a final newline" "$raw"

# --- one pair for each class of input -----------------------------------------
if ! "$ORACLE" shell01_chelou cases 42 > "$work/cases" 2> /dev/null ||
	[ ! -s "$work/cases" ]; then
	rm -rf "$work"
	ck_broken "the reference gave no pairs to run"
fi
# Every pair is judged, or none is: the loop reads the list on its own
# stdin, and ck_run gives the program /dev/null, so a program that reads its
# stdin cannot swallow the pairs after the one it was run on. Counted all the
# same, since a PASS over pairs that never ran is the one result this check
# must not give.
listed=$(wc -l < "$work/cases" | tr -d ' ')
judged=0
while IFS='	' read -r label a b; do
	judged=$((judged + 1))
	ref "$a" "$b" "$work/ref" || {
		rm -rf "$work"
		ck_broken "the reference refused its own pair ($label)"
	}
	ck_run -C "$work/run" "$raw" env FT_NBR1="$a" FT_NBR2="$b" sh "$DA"
	body "$raw" > "$work/got"
	body "$work/ref" > "$work/want"
	ck "$label" cmp -s "$work/got" "$work/want"
	if ! cmp -s "$work/got" "$work/want"; then
		ck_detail "to run it again, from a folder holding a file named q as this check's runs do:" \
			"FT_NBR1=$(ck_quote "$a") FT_NBR2=$(ck_quote "$b") sh $D"
	fi
done < "$work/cases"
if [ "$judged" != "$listed" ]; then
	rm -rf "$work"
	ck_broken "the reference listed $listed pairs and $judged were judged"
fi

rm -rf "$work"
ck_report
