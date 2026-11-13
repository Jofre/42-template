# --------------------------------------------------------------- oracle_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The guard on the guard. Every `diff` layer in the repo trusts //oracle to be
# right, so a reference that quietly stopped agreeing with its own tables would
# fail CORRECT student code across 74 targets with nothing above it to notice --
# and this runner is what notices. It had no arm of its own.
#
# The arms use a stand-in rather than the real oracle, deliberately: what is
# being tested is that a non-zero `check` becomes a red test WITH the self-check
# output attached, and building 30 s of Rust to assert that would put this in
# the slow suite for no gain.
mkdir -p "$WORK/orc"
printf '#!/bin/sh\n[ "$1" = check ] || exit 3\necho "all modules agree"\n' \
	> "$WORK/orc/ok"
printf '#!/bin/sh\n[ "$1" = check ] || exit 3\necho "c02: 3 failures"\nexit 1\n' \
	> "$WORK/orc/bad"
chmod +x "$WORK/orc/ok" "$WORK/orc/bad"
want_green "oracle_check: a reference that agrees with itself passes" -- \
	"$SH" "$TOOLS/oracle_check.sh" --oracle "$WORK/orc/ok"
want_red "oracle_check: a reference that fails its own check is RED" -- \
	"$SH" "$TOOLS/oracle_check.sh" --oracle "$WORK/orc/bad"
# The failure text is the point: "the reference is wrong, so do not go hunting
# in your own code" is the one thing a student cannot work out unaided.
want_out "oracle_check: and it says the reference is at fault, not the student" \
	'Fix //oracle first' -- \
	"$SH" "$TOOLS/oracle_check.sh" --oracle "$WORK/orc/bad"
want_out "oracle_check: and shows what the self-check said" 'c02: 3 failures' -- \
	"$SH" "$TOOLS/oracle_check.sh" --oracle "$WORK/orc/bad"
want_broken "oracle_check: a missing reference is a harness error, not a red" \
	'not executable' -- \
	"$SH" "$TOOLS/oracle_check.sh" --oracle "$WORK/orc/nothing-here"

