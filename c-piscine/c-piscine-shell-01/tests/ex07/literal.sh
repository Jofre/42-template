#!/bin/sh
# Shell 01 ex07, "Sort the results in reverse alphabetical order" read
# literally -- its ex07_literal target, at strict.
#
# check.sh (basic) passes either reading of that sentence: bytes, as the C
# locale compares them, or the collation of the locale the test runs in. This
# takes one, the literal one: ALPHABETICAL order, as a dictionary has it, is
# the locale's collation -- the letters first, their case after them -- and
# not the order of the bytes' codes (the Piscine's subjects say "ASCII order"
# where they mean that, as C 06 ex03 does). The locale is this test's,
# LC_ALL=en_US.UTF-8 from .bazelrc. Which one 42's grader reads, the subject
# does not say -- which is what puts this at strict and not at basic
# (docs/reference.md, "Run contract").
#
# Run on the same fixture as check.sh (tests/ex07/passwd, handed to the
# program as /etc/passwd), whose names sort differently under the two
# readings; where the locale is not installed the two are the same order, and
# this says it cannot tell them apart rather than passing.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-r_dwssap.sh}
printf "  CHECK: %s, this harness's reading at strict: \"reverse alphabetical order\" as the locale's (%s)\n" \
	"$D" "${LC_ALL:-${LC_COLLATE:-${LANG:-C}}}"

ck_require "r_dwssap.sh exists" test -f "$D"
ck_sh_parses "$D"

ORACLE=${ORACLE:?this check needs //oracle: declare the exercise with oracle = True}

if ! ck_redirected; then
	ck_skipped "the order on the fixture: ${CK_REDIRECT_BROKEN:-no fixture passwd is declared for this exercise}"
	ck_report
fi
F=$CK_REDIRECT_TO
# Whether the two readings differ on the fixture here, asked before the
# program runs: they do wherever the locale is installed.
if ! "$ORACLE" shell01_rdwssap orders --passwd "$F" 2> /dev/null; then
	ck_skipped "the locale's order and the bytes' are the same here (is ${LC_ALL:-its locale} installed? locale -a), so no output can tell the two readings apart"
	ck_report
fi

raw=$(mktemp)
judge() {
	V=$("$ORACLE" shell01_rdwssap "$@" --order locale --passwd "$F" < "$raw") ||
		{ rm -f "$raw" "$raw.err"; ck_broken "the reference could not judge this output"; }
}
lacks() {
	case " $V " in *" $1 "*) return 1 ;; esac
	return 0
}

# has_names -> whether the output in $raw lists at least one name: anything
# before its final '.'. An output with none is in every order, so the order
# is judged only of names, as check.sh judges it.
has_names() {
	_s=$(cat "$raw")
	_s=${_s%.}
	[ -n "$_s" ]
}

ck_run "$raw" env FT_LINE1=1 FT_LINE2=999 sh "$D"
judge 1 999
if has_names; then
	ck "the whole list is in reverse order as the locale collates it" lacks order
else
	ck "prints at least one name, for the order to be judged on" has_names
fi
for w in "2 4" "7 15"; do
	l1=${w% *}
	l2=${w#* }
	ck_run "$raw" env FT_LINE1="$l1" FT_LINE2="$l2" sh "$D"
	judge "$l1" "$l2"
	ck "range $l1..$l2 is entries $l1 through $l2 of the list in the locale's order" lacks window
done

rm -f "$raw" "$raw.err"
ck_report
