#!/bin/sh
# ex08 — add_chelou.sh, validated against BOTH of the subject's worked examples.
#
# The expected output for each example IS the answer to the exercise, so it is
# never written here in clear: the check compares a SHA-256 digest of the
# deliverable's output. The test is exactly as strict, but reading this file
# does not hand over the result — which is the whole point of tests/ living
# beside a learning exercise (see AGENTS.md §3: tests may hint, never answer).
# The same rule is why neither the alphabets' roles nor the tools that make the
# arithmetic easy are spelled out here; that reasoning belongs to the student.
#
# TIGHTENING: the sum is printed line-oriented, so the output ends with a final
# newline, and the Moulinette compares stdout byte-for-byte. The old check
# captured with $(...), which strips the trailing newline and was blind to it —
# a deliverable printing the right text with NO newline (printf / echo -n /
# tr -d '\n') passed here yet would KO on the box. We now capture RAW bytes and
# assert the terminator. Whether a final newline is required is a SPEC property
# (line-oriented Example output), not the answer.
#
# WHY EXAMPLE 2 IS HERE. The subject prints TWO worked examples, and this check
# used to run only the first. That is the worst possible choice of a single
# input, because Example 1's operands are small: they fit in a machine word, so
# every fixed-width strategy — $((base#digits)) arithmetic, a hand-rolled
# accumulator in shell integers, anything that ends up in a 64-bit register —
# lands on the SAME bytes as an arbitrary-precision one, digest and trailing
# newline included. Example 1 is therefore precisely the input at which the
# right and the wrong program coincide, and a fixed-width solution scored a
# perfect 3/3 here. Example 2's operands do not fit: 29 digits in a 5-symbol
# alphabet is ~1.9e20 and 28 digits is ~3.7e19, both past UINT64_MAX (1.8e19),
# so a fixed-width solution wraps and prints garbage while a correct one does
# not. A worked example printed in a subject IS a test case; this one hands over
# the exact input that separates the two implementations, and the suite was
# throwing it away. (It costs a correct solution nothing: a working
# add_chelou.sh reproduces the subject's Example 2 result byte-for-byte.)
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-add_chelou.sh}
printf "  CHECK: %s\n" "$D"

ck "add_chelou.sh exists" test -f "$D"

# The two expected strings are the answers themselves, so they are stored as
# digests and never appear here in clear; both comparisons are plain pass/fail
# and neither value is echoed. sha256sum is coreutils and present on the campus
# box, but fall back to cksum rather than skipping the assertion if it ever is
# not — a check that silently stops checking is worse than a coarser one.
#
# PROVENANCE of the two digests (they are fixtures, so they need a source):
# each is the SHA-256 of the string the SUBJECT ITSELF prints as that example's
# result — verified independently of this repo by hashing the text read out of
# the module's subject PDF — and each was cross-checked against a working
# add_chelou.sh's actual stdout on the same inputs. Two independent sources agree,
# which is why they are trustworthy without being readable.
if command -v sha256sum >/dev/null 2>&1; then
	digest() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
	EXPECT1="75c4ec0328d2ec2e8cc1cfecda70808ab55a68645a100cd7b88b18ed9d44fd5d"
	EXPECT2="8af6fa80ee182c0cb5648538f4884858709919ed6fbbcb9088a3fd20dabf0c2a"
else
	# cksum prints "<sum> <bytes>", and that second field is each answer's
	# LENGTH -- which the provenance note above promises is not published here.
	# Keep the sum, drop the length.
	digest() { printf '%s' "$1" | cksum | cut -d' ' -f1; }
	EXPECT1="861911637"
	EXPECT2="4241385134"
fi

# --- Example 1: FT_NBR1=\'?"\"'\  FT_NBR2=rcrdmddd --------------------------
# Capture RAW bytes (with any trailing newline) to a file, and the
# shell-stripped form for the exact-content compare — from the SAME inputs.
raw=$(mktemp)
FT_NBR1='\'"'"'?"\"'"'"'\' FT_NBR2='rcrdmddd' sh "$D" > "$raw" 2>/dev/null
out=$(FT_NBR1='\'"'"'?"\"'"'"'\' FT_NBR2='rcrdmddd' sh "$D" 2>/dev/null)

ck "Example 1: produces the correct result for the sample inputs" \
	test "$(digest "$out")" = "$EXPECT1"

# Terminator: the result line ends with a newline (line-oriented output). This
# is the exact byte the Moulinette checks and the $(...) capture above hides.
ck_final_newline "Example 1: output ends with a final newline (Moulinette byte-matches stdout)" "$raw"

# --- Example 2: the operands that do not fit in a machine word ---------------
# Both values are copied verbatim from the subject; neither contains a single
# quote, so each is a plain single-quoted literal here. FT_NBR1 is 29 symbols
# and FT_NBR2 is 28, in 5-symbol alphabets — see the header for why that matters.
raw2=$(mktemp)
FT_NBR1='\"\"!\"\"!\"\"!\"\"!\"\"!\"\"' FT_NBR2='dcrcmcmooododmrrrmorcmcrmomo' \
	sh "$D" > "$raw2" 2>/dev/null
out2=$(FT_NBR1='\"\"!\"\"!\"\"!\"\"!\"\"!\"\"' FT_NBR2='dcrcmcmooododmrrrmorcmcrmomo' \
	sh "$D" 2>/dev/null)

ck "Example 2: correct on operands larger than a 64-bit word" \
	test "$(digest "$out2")" = "$EXPECT2"

ck_final_newline "Example 2: output ends with a final newline" "$raw2"

rm -f "$raw" "$raw2"
ck_report
