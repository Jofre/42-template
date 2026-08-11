#!/bin/sh
# rush02_check.sh — differential check for c-piscine-rush-02.
#
# Runs the student's ./rush-02 once per number against a corpus the Rust
# reference generated, and reports the first differences as a table.
#
# WHY THIS IS ONE EXEC PER CASE, unlike every other differential layer here.
# c_diff streams a 400k-line corpus through ONE process reading stdin, which is
# what makes that layer cheap. rush-02 is a program that takes its number on the
# command line, so each case is a fork+exec: the count has to stay in the
# hundreds, not the hundreds of thousands. That is a property of the subject,
# not a shortcut.
#
# WHY THIS NEVER GATES.
# The subject pins four outputs and no composition rule. `forty two` and `one
# hundred thousand` fix the separator and the group/scale shape; they do not
# settle whether 101 reads "one hundred one" or "one hundred and one", nor
# whether a leading group of one is spelled out. Bonus 1 then legalises "-", ","
# and "and" outright. So a disagreement here is EVIDENCE, not a verdict: it may
# mean a bug, or it may mean the team answered a question the subject left open.
# The target that runs this is tagged `manual` for that reason -- run it when you
# want it, and read its output as a second opinion rather than a grade.
#
# Usage:
#   rush02_check.sh --bin PATH --dict PATH --oracle PATH
#                   [--fn NAME] [--seed N] [--count N] [--show N]
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "rush02_check.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require grep mktemp rm tr wc

BIN=""
DICT=""
ORACLE=""
FN="rush02_words"
SEED=1
COUNT=200
SHOW=10

# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "rush02_check.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--bin) need "$1" "$#"; BIN="$2"; shift 2 ;;
		--dict) need "$1" "$#"; DICT="$2"; shift 2 ;;
		--oracle) need "$1" "$#"; ORACLE="$2"; shift 2 ;;
		--fn) need "$1" "$#"; FN="$2"; shift 2 ;;
		--seed) need "$1" "$#"; SEED="$2"; shift 2 ;;
		--count) need "$1" "$#"; COUNT="$2"; shift 2 ;;
		--show) need "$1" "$#"; SHOW="$2"; shift 2 ;;
		*) echo "rush02_check.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

for v in BIN DICT ORACLE; do
	eval "x=\$$v"
	[ -n "$x" ] || { echo "rush02_check.sh: --$(echo $v | tr 'A-Z' 'a-z') is required" >&2; exit 2; }
done

# Absolutise everything before anything changes directory. $(location ...) hands
# us runfiles-root-relative paths, and they stop resolving the moment cwd moves
# -- the trap make_test.sh:67-70 documents for the same reason.
abspath() {
	case "$1" in
		/*) echo "$1" ;;
		*) echo "$PWD/$1" ;;
	esac
}
BIN=$(abspath "$BIN")
DICT=$(abspath "$DICT")
ORACLE=$(abspath "$ORACLE")

[ -x "$BIN" ] || { echo "rush02_check.sh: '$BIN' is not executable" >&2; exit 1; }
[ -r "$DICT" ] || { echo "rush02_check.sh: cannot read dictionary '$DICT'" >&2; exit 1; }

CORPUS=$(mktemp)
# Installed here rather than beside TMPD forty lines down, which is where it
# used to be: three exit paths sit between the two, and each of them leaked the
# corpus. TMPD is empty until then and `rm -f ""` is a no-op, so one trap covers
# both. INT and TERM as well as EXIT, because Bazel kills a slow test.
TMPD=""
trap 'rm -f "$CORPUS" "$TMPD"' EXIT INT TERM
"$ORACLE" "$FN" "$SEED" "$COUNT" > "$CORPUS" 2>/dev/null || {
	echo "rush02_check.sh: the oracle produced no corpus for '$FN'" >&2
	exit 1
}

# An oracle that exits 0 having printed NOTHING is not a pass, and until this
# guard existed it was: the loop below never ran, TOTAL stayed 0, and the report
# read "OK -- 0/0 agree with the reference" while nothing at all had been
# compared. That is the same false green tools/rust_diff.sh grew MIN_DIFF_CASES
# to stop, in the only check this module has.
#
# The floor is deliberately not 1. A corpus of a handful of cases would satisfy
# a literal emptiness test while still saying nothing about a converter, and the
# caller asks for --count 200 by default, so anything two orders below that
# means the reference is broken rather than terse.
MIN_RUSH02_CASES=20
# `|| echo 0` here would be a bug, and was one: grep -c PRINTS 0 and EXITS 1
# when nothing matches, so the fallback appended a second zero, the test became
# `[ "0\n0" -lt 20 ]`, sh called it a bad number, and the guard silently never
# fired -- a guard against a false green, failing the same way.
GOT_CASES=$(grep -c . "$CORPUS" 2>/dev/null) || GOT_CASES=0
if [ "$GOT_CASES" -lt "$MIN_RUSH02_CASES" ]; then
	echo "rush02_check.sh: the reference emitted $GOT_CASES case(s) for '$FN'," >&2
	echo "                 fewer than the $MIN_RUSH02_CASES this layer requires." >&2
	echo "                 Reporting a HARNESS failure rather than '0/0 agree':" >&2
	echo "                 a corpus this small proves nothing about the program." >&2
	exit 2
fi

TOTAL=0
BAD=0
echo "rush02_check: $FN, seed $SEED, $(wc -l < "$CORPUS") cases (one exec each)"
echo ""
printf '  %-24s | %-34s | %s\n' "NUMBER" "EXPECTED" "GOT"
printf '  %-24s-+-%-34s-+-%s\n' "------------------------" \
	"----------------------------------" "---"

# Two corpus shapes, told apart per line by the field count:
#   2 fields  <number>\t<expected>                  -- uses --dict, fixed
#   3 fields  <escaped-dict>\t<number>\t<expected>  -- a generated dictionary
# The escape is rush00's; only \n, \t and \\ can actually occur here, because
# the generator emits printable values only, and printf %b handles those three.
TMPD=$(mktemp)
# No second trap here. `trap` REPLACES the handler rather than adding to it, so
# re-arming it at this point would silently drop the INT and TERM the one above
# installs -- and it is the same command either way, because $TMPD was declared
# empty up there for exactly this reason.

while IFS='	' read -r f1 f2 f3; do
	[ -n "$f1" ] || continue
	if [ -n "$f3" ]; then
		printf '%b' "$f1" > "$TMPD"
		use_dict="$TMPD"; num="$f2"; want="$f3"
	else
		use_dict="$DICT"; num="$f1"; want="$f2"
	fi
	TOTAL=$((TOTAL + 1))
	got=$("$BIN" "$use_dict" "$num" 2>/dev/null)
	if [ "$got" != "$want" ]; then
		BAD=$((BAD + 1))
		if [ "$BAD" -le "$SHOW" ]; then
			printf '  %-24.24s | %-34.34s | %.34s\n' "$num" "$want" "$got"
		fi
	fi
done < "$CORPUS"

echo ""
if [ "$BAD" -eq 0 ]; then
	echo "  RESULT: OK — $TOTAL/$TOTAL agree with the reference."
	exit 0
fi
if [ "$BAD" -gt "$SHOW" ]; then
	echo "  ... $((BAD - SHOW)) more difference(s) not shown."
fi
echo "  RESULT: $((TOTAL - BAD))/$TOTAL agree, $BAD differ."
echo ""
echo "  Read this before changing anything. The subject fixes four outputs and"
echo "  no composition rule, so a difference here is one of two things:"
echo "    * a real bug — the usual case, especially if small numbers differ; or"
echo "    * a choice the subject left to you. It never says whether 101 is"
echo "      'one hundred one' or 'one hundred and one', and bonus 1 explicitly"
echo "      allows '-', ',' and 'and'. The reference picked one reading."
echo "  Compare the SHAPE of the differences: if every row differs the same way,"
echo "  that is a convention, not a bug."
exit 1
