#!/bin/sh
# Shell 01 ex04, and Piscine Reloaded ex04, which repeats it (its BUILD call
# names this file through twin_of).
# MAC.sh must print at least one line, every line a valid MAC address,
# and — per the subject ("each address followed by a line break") — the output
# must END WITH A NEWLINE (the last address is followed by a line break too).
# The Moulinette compares stdout byte-for-byte, so a missing final newline is a
# real KO that the shell-stripping $(...) capture is blind to; we therefore
# assert the terminator on the RAW bytes.
# Host/network-coupled: its output test runs outside the sandbox (run_tags in
# the BUILD file), and what this machine cannot show is a SKIP, below.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-MAC.sh}
printf "  CHECK: %s\n" "$D"

# THE PROBES, each overridable so the branches below can be proven on any
# machine (//tools/tests:selftest runs them): MAC_CHECK_IFCONFIG names the
# ifconfig to look for -- a path, or empty for "this machine has none" -- and
# is read BEFORE the PATH below changes, which would otherwise put the host's
# own first; ORACLE is //oracle, which every run of this check is handed.
if [ "${MAC_CHECK_IFCONFIG+set}" = set ]; then
	IFCONFIG=$MAC_CHECK_IFCONFIG
	_ifc_given=1
else
	_ifc_given=0
fi
ORACLE=${ORACLE:?this check needs //oracle: declare the exercise with oracle = True}

# ifconfig lives in /usr/sbin (on a 42 machine it's on the user's PATH), and
# MAC.sh is run with this PATH.
PATH="/usr/sbin:/sbin:$PATH"
export PATH
[ "$_ifc_given" = 1 ] || IFCONFIG=$(command -v ifconfig 2> /dev/null)

# What every machine can check comes first: a missing MAC.sh fails even where
# the machine has nothing to show, which is where it now runs by default.
ck_require "MAC.sh exists" test -f "$D"
ck "MAC.sh is readable" test -r "$D"
# The subject: shell exercises must be executable with /bin/sh.
ck_sh_parses "$D"

# CAN THIS MACHINE SHOW A HARDWARE ADDRESS AT ALL? Asked of the HOST, and asked
# before the deliverable is run even once. Where it cannot, the rest of the
# checklist is one [SKIP] line, which NO_SKIP=1 turns red.
#
# Every assertion below is about output that only exists if some interface has
# an address to print. On a box with nothing but loopback -- a container, a CI
# runner -- a byte-identical CORRECT MAC.sh prints nothing and this script
# reported FAIL 2/5 against it. A red that a different machine would not produce
# is not a finding about the student's work.
#
# Two questions, each of the host:
#   - the tool the subject points at (man ifconfig). A machine without
#     ifconfig cannot run a MAC.sh written with it, however right it is: a
#     42 machine has one, and a container may not.
#   - an address to show. //oracle's shell01_hwaddr --machine reads it where
#     the verdict below reads the addresses MAC.sh must print (/sys/class/net,
#     loopback and all-zero ones left out), so the skip and the verdict are one
#     source of truth: asked only whether there is ANY address, and answering
#     with an exit code alone, never an address. A box whose only interface
#     besides loopback is a tunnel has none, and a correct MAC.sh prints
#     nothing there.
# literal.sh asks both questions too, in the same words.
#
# Keyed off the host and never off the program: a guard computed from the
# deliverable's own output hands a broken deliverable the power to switch its
# own tests off, which is the bug Shell 01 ex07 carried.
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
		# The reference itself failed: a broken harness, not a skip.
		ck_broken "//oracle shell01_hwaddr --machine answered $_any, not 0 or 4: the reference could not say whether this machine has a hardware address"
		;;
esac

# Capture RAW output (with any trailing newline) to a file, then derive the
# shell-stripped form for the per-line property checks.
raw=$(mktemp)
ck_run "$raw" sh "$D"
out=$(cat "$raw")

# At least one line of output (there is an interface to show: checked above).
ck "prints at least one MAC address" test -n "$out"

# Every line must be exactly a MAC address, XX:XX:XX:XX:XX:XX -- and not just
# any well-formed one: one of THIS machine's. Both are asked of //oracle
# (shell01_hwaddr). It reads the addresses the kernel publishes for each
# network interface and answers with an exit code only; nothing is printed,
# neither the student's lines nor the machine's addresses.
#
# Why not a text pattern here, as this check used to have: a pattern that
# recognises a MAC address is a piece of a common answer, and this file ships
# in the public template. And a pattern alone passed any well-formed address,
# invented or not.
#
#   0  every line is a MAC address, each is one of this machine's, and at
#      least one is a hardware interface's
#   1  some line is not a MAC address at all (a blank line counts)
#   3  every line is a MAC address, but some are not this machine's
#   4  every line is a MAC address; this machine publishes none to compare
#   5  every line is this machine's, and each is the loopback's
#
# --loopback: "your machine's MAC addresses" may or may not take in the
# 00:00:00:00:00:00 the kernel publishes for the loopback interface, and the
# subject does not say, so this level accepts that line and its absence alike
# -- beside the hardware interfaces' addresses, never instead of them. That
# line alone is on every Linux machine, so a MAC.sh that printed it as a
# constant would pass anywhere; that is 5, and a failure here.
# literal.sh (ex04_literal, strict) takes one reading: the hardware
# interfaces' addresses, and nothing else.
printf '%s\n' "$out" | "$ORACLE" shell01_hwaddr --loopback 2>/dev/null
verdict=$?
ck "every line is a valid MAC (XX:XX:XX:XX:XX:XX)" \
	test "$verdict" -eq 0 -o "$verdict" -eq 3 -o "$verdict" -eq 4 -o "$verdict" -eq 5
if [ "$verdict" -eq 4 ]; then
	# Keyed off the host, never off the program: the oracle answers 4 only
	# after every line has passed the format test, and only because the
	# machine itself has nothing under /sys/class/net to compare with. After
	# the --machine question above, only a race reaches this: the machine
	# lost its last hardware address while the program ran.
	ck_skipped "this machine publishes no hardware address to compare the output with"
else
	ck "every address printed is one of this machine's" \
		test "$verdict" -eq 0 -o "$verdict" -eq 5
	if [ "$verdict" -eq 3 ]; then
		# Which of the student's OWN lines were refused, asked of the
		# oracle one line at a time: what is shown is what the program
		# printed, and never an address of the machine's it did not.
		refused=""
		broadcast=0
		while IFS= read -r line; do
			printf '%s\n' "$line" | "$ORACLE" shell01_hwaddr --loopback 2>/dev/null
			[ $? -eq 3 ] || continue
			refused="$refused${refused:+
}not one of this machine's interface addresses: $line"
			case "$line" in
				[Ff][Ff]:[Ff][Ff]:[Ff][Ff]:[Ff][Ff]:[Ff][Ff]:[Ff][Ff]) broadcast=1 ;;
			esac
		done <<EOF_OUT
$out
EOF_OUT
		ck_detail "$refused"
		[ "$broadcast" = 0 ] ||
			ck_detail "Is a broadcast address any one interface's own address?"
	elif [ "$verdict" -eq 0 ] || [ "$verdict" -eq 5 ]; then
		# Asked only of an output whose every line is this machine's: of
		# any other, the lines that are no one's are the failure to read
		# first, and a PASS here would stand on lines refused above.
		ck "at least one address printed is a hardware interface's (the loopback's alone is not)" \
			test "$verdict" -eq 0
		[ "$verdict" -eq 0 ] ||
			ck_detail "Every line printed is the loopback interface's. Is the loopback a piece of hardware, and which other interfaces does this machine have?"
	fi
fi

# Each address is followed by a line break, INCLUDING the last one, so the
# output ends with a newline (subject: "each address followed by a line break").
# This is the byte-exact terminator the Moulinette enforces.
ck_final_newline "each MAC address is followed by a line break (output ends with a newline)" "$raw"

rm -f "$raw" "$raw.err"
ck_report
