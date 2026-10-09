#!/bin/sh
# Shell 01 ex04 and Piscine Reloaded ex04, "your machine's MAC addresses" read
# one way -- each one's exNN_literal target, at strict, run outside the
# sandbox like the exercise's output test (it reads this machine's
# interfaces).
#
# The kernel publishes an address for every network interface, the loopback
# included, and the loopback's is 00:00:00:00:00:00. Whether that is one of
# "your machine's MAC addresses" the sentence does not say, so check.sh
# (basic) accepts that line and its absence alike. This takes one reading:
# a MAC address belongs to a piece of hardware, and the loopback interface is
# none, so every line printed is the address of one of this machine's
# hardware interfaces, and the loopback's all-zero line is refused. Which
# reading 42's grader takes, the subject does not say -- which is what puts
# this at strict and not at basic (docs/reference.md, "Run contract").
#
# The same question as check.sh, asked of //oracle's shell01_hwaddr without
# --loopback; it answers with an exit code only. A failure names the lines of
# the program's own output it refused, never an address of the machine's.
#
# THE MACHINE, in check.sh's words: a machine without ifconfig, or with no
# hardware address on any interface, is one where a correct MAC.sh cannot run
# or prints nothing, and check.sh skips what it prints there. This did not
# ask, and on such a machine the empty output failed the format test and
# FAILED a correct answer at strict. Both questions are asked of the machine,
# never of what the program printed, and before it runs; what every machine
# can check comes first, as in check.sh.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-MAC.sh}
printf '  CHECK: %s, this harness'"'"'s reading at strict: "your machine'"'"'s MAC addresses" as its hardware interfaces'"'"' only\n' "$D"

# check.sh's probes, word for word (its comment says what each asks):
# MAC_CHECK_IFCONFIG, read before the PATH below changes, and //oracle.
if [ "${MAC_CHECK_IFCONFIG+set}" = set ]; then
	IFCONFIG=$MAC_CHECK_IFCONFIG
	_ifc_given=1
else
	_ifc_given=0
fi
ORACLE=${ORACLE:?this check needs //oracle: declare the exercise with oracle = True}

# ifconfig lives in /usr/sbin (on a 42 machine it's on the user's PATH), as
# in check.sh.
PATH="/usr/sbin:/sbin:$PATH"
export PATH
[ "$_ifc_given" = 1 ] || IFCONFIG=$(command -v ifconfig 2> /dev/null)

ck_require "MAC.sh exists" test -f "$D"
ck_sh_parses "$D"

if [ -z "$IFCONFIG" ]; then
	ck_skipped "what MAC.sh prints: ifconfig is not on this machine, so a MAC.sh written with it cannot run here (a 42 machine has ifconfig)"
	ck_report
fi
"$ORACLE" shell01_hwaddr --machine 2> /dev/null
_any=$?
case "$_any" in
	0) ;;
	4)
		ck_skipped "what MAC.sh prints: this machine publishes no hardware address besides loopback (/sys/class/net), so a correct MAC.sh has none to print"
		ck_report
		;;
	*)
		ck_broken "//oracle shell01_hwaddr --machine answered $_any, not 0 or 4: the reference could not say whether this machine has a hardware address"
		;;
esac

raw=$(mktemp)
ck_run "$raw" sh "$D"
out=$(cat "$raw")

# 4 is a machine that had a hardware address when it was asked above and has
# none now: nothing to tell the two readings apart by.
printf '%s\n' "$out" | "$ORACLE" shell01_hwaddr 2>/dev/null
verdict=$?
case "$verdict" in
	4) ck_skipped "this machine publishes no hardware address, so no output can tell the two readings apart" ;;
	*)
		ck "every line is the address of one of this machine's hardware interfaces (not the loopback's)" \
			test "$verdict" -eq 0
		if [ "$verdict" -eq 3 ]; then
			refused=""
			while IFS= read -r line; do
				printf '%s\n' "$line" | "$ORACLE" shell01_hwaddr 2>/dev/null
				[ $? -eq 3 ] || continue
				refused="$refused${refused:+
}not a hardware interface's address: $line"
			done <<EOF_OUT
$out
EOF_OUT
			ck_detail "$refused"
		fi
		;;
esac

rm -f "$raw" "$raw.err"
ck_report
