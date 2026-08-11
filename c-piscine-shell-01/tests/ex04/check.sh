#!/bin/sh
# ex04 — MAC.sh must print at least one line, every line a valid MAC address,
# and — per the subject ("each address followed by a line break") — the output
# must END WITH A NEWLINE (the last address is followed by a line break too).
# The Moulinette compares stdout byte-for-byte, so a missing final newline is a
# real KO that the shell-stripping $(...) capture is blind to; we therefore
# assert the terminator on the RAW bytes.
# Host/network-coupled: tagged manual+env+no-sandbox (run with --spawn_strategy=local).
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-MAC.sh}
printf "  CHECK: %s\n" "$D"

# ifconfig lives in /usr/sbin (on a 42 machine it's on the user's PATH).
PATH="/usr/sbin:/sbin:$PATH"
export PATH

ck "MAC.sh exists"      test -f "$D"
ck "MAC.sh is readable" test -r "$D"

# Capture RAW output (with any trailing newline) to a file, then derive the
# shell-stripped form for the per-line property checks.
raw=$(mktemp)
sh "$D" > "$raw" 2>/dev/null
out=$(cat "$raw")

# At least one line of output (needs real interfaces; --spawn_strategy=local).
ck "prints at least one MAC address" test -n "$out"

# Every non-empty line must be exactly a MAC address XX:XX:XX:XX:XX:XX.
bad=$(printf '%s\n' "$out" | grep -cvE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')
ck "every line is a valid MAC (XX:XX:XX:XX:XX:XX)" test "${bad:-1}" -eq 0

# Each address is followed by a line break, INCLUDING the last one, so the
# output ends with a newline (subject: "each address followed by a line break").
# This is the byte-exact terminator the Moulinette enforces.
ck_final_newline "each MAC address is followed by a line break (output ends with a newline)" "$raw"

rm -f "$raw"
ck_report
