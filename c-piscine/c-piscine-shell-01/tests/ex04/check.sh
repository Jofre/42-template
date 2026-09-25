#!/bin/sh
# ex04 — MAC.sh must print at least one line, every line a valid MAC address,
# and — per the subject ("each address followed by a line break") — the output
# must END WITH A NEWLINE (the last address is followed by a line break too).
# The Moulinette compares stdout byte-for-byte, so a missing final newline is a
# real KO that the shell-stripping $(...) capture is blind to; we therefore
# assert the terminator on the RAW bytes.
# Host/network-coupled: tagged manual+env+no-sandbox (run with --spawn_strategy=local).
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-MAC.sh}
printf "  CHECK: %s\n" "$D"

# ifconfig lives in /usr/sbin (on a 42 machine it's on the user's PATH).
PATH="/usr/sbin:/sbin:$PATH"
export PATH

# CAN THIS MACHINE SHOW A HARDWARE ADDRESS AT ALL? Asked of the HOST, and asked
# before the deliverable is run even once.
#
# Every assertion below is about output that only exists if some interface has
# an address to print. On a box with nothing but loopback -- a container, a CI
# runner -- a byte-identical CORRECT MAC.sh prints nothing and this script
# reported FAIL 2/5 against it. A red that a different machine would not produce
# is not a finding about the student's work.
#
# The probe counts INTERFACE BLOCKS, not addresses. ifconfig opens one block per
# interface at column 0 with the interface's own name and indents its details
# underneath, so this asks what hardware the box HAS. What any of it is
# ADDRESSED as is the exercise, and a probe that went looking for that would be
# writing the answer into the test. -a, so an interface that is merely down
# still counts: its address exists whether or not the link is up.
#
# Keyed off the host and never off the program: a guard computed from the
# deliverable's own output hands a broken deliverable the power to switch its
# own tests off, which is the bug ex07 in this same module carried.
IFBLOCKS=0
if command -v ifconfig > /dev/null 2>&1; then
	IFBLOCKS=$(ifconfig -a 2> /dev/null | grep -c '^[^[:space:]]')
fi
[ -n "$IFBLOCKS" ] || IFBLOCKS=0
if [ "$IFBLOCKS" -le 1 ]; then
	ck_skip "this machine has no network interface besides loopback (ifconfig lists $IFBLOCKS block(s)), so a correct MAC.sh has no address to print"
fi

ck "MAC.sh exists"      test -f "$D"
ck "MAC.sh is readable" test -r "$D"

# Capture RAW output (with any trailing newline) to a file, then derive the
# shell-stripped form for the per-line property checks.
raw=$(mktemp)
sh "$D" > "$raw" 2>/dev/null
out=$(cat "$raw")

# At least one line of output (needs real interfaces; --spawn_strategy=local).
ck "prints at least one MAC address" test -n "$out"

# Every line must be exactly a MAC address, XX:XX:XX:XX:XX:XX -- and not just
# any well-formed one: one of THIS machine's. Both are asked of //oracle
# (shell01_hwaddr). It reads the addresses the kernel publishes for each
# network interface, loopback and all-zero ones left out, and answers with an
# exit code only; nothing is printed, neither the student's lines nor the
# machine's addresses.
#
# Why not a text pattern here, as this check used to have: a pattern that
# recognises a MAC address is a piece of a common answer, and this file ships
# in the public template. And a pattern alone passed any well-formed address,
# invented or not.
#
#   0  every line is a MAC address, and each is one of this machine's
#   1  some line is not a MAC address at all (a blank line counts)
#   3  every line is a MAC address, but some are not this machine's
#   4  every line is a MAC address; this machine publishes none to compare
ORACLE=${ORACLE:?this check needs //oracle: declare the exercise with oracle = True}
printf '%s\n' "$out" | "$ORACLE" shell01_hwaddr 2>/dev/null
verdict=$?
ck "every line is a valid MAC (XX:XX:XX:XX:XX:XX)" \
	test "$verdict" -eq 0 -o "$verdict" -eq 3 -o "$verdict" -eq 4
if [ "$verdict" -eq 4 ]; then
	# Keyed off the host, never off the program: the oracle answers 4 only
	# after every line has passed the format test, and only because the
	# machine itself has nothing under /sys/class/net to compare with.
	ck_skipped "this machine publishes no hardware address to compare the output with"
else
	ck "every address printed is one of this machine's" test "$verdict" -eq 0
fi

# Each address is followed by a line break, INCLUDING the last one, so the
# output ends with a newline (subject: "each address followed by a line break").
# This is the byte-exact terminator the Moulinette enforces.
ck_final_newline "each MAC address is followed by a line break (output ends with a newline)" "$raw"

rm -f "$raw"
ck_report
