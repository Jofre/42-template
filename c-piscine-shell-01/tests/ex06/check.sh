#!/bin/sh
# ex06 — skip.sh must run `ls -l` and print every OTHER line starting from the
# first (lines 1,3,5,...). `ls -l` is line-oriented output: every line, INCLUDING
# the last, is terminated by a newline (the subject's `cat -e` example shows a `$`
# after the final `toto` line). So the correct output ENDS WITH a trailing newline,
# and the Moulinette compares stdout byte-for-byte — a missing (or extra) final
# newline is a real KO that a shell-stripping `$(...)` capture is blind to.
#
# The exact listing IS effectively the answer, so the full-listing match is a PLAIN
# pass/fail and the reference output is never printed. The trailing-newline behavior
# and the "every other line" structure are spec properties, so asserting them
# reveals nothing.
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-skip.sh}
case "$D" in /*) ;; *) D="$PWD/$D";; esac
printf "  CHECK: %s\n" "$D"

ck "skip.sh exists" test -f "$D"

# Build a deterministic listing context in a throw-away directory, identical for
# the student run and the reference: several files so `ls -l` has many lines and
# "every other line" is well-defined. A temp dir keeps this host-safe (independent
# of whatever else sits in the deliverable's directory).
T=$(mktemp -d)
i=1
while [ "$i" -le 9 ]; do : > "$T/$i"; i=$((i + 1)); done

# Capture RAW bytes (with any trailing newline) and the shell-stripped form,
# both produced inside the controlled directory.
raw=$(mktemp)
(cd "$T" && sh "$D") > "$raw" 2>/dev/null
got=$(cd "$T" && sh "$D" 2>/dev/null)
want=$(cd "$T" && ls -l | awk 'NR % 2')

# 1) It must actually print something.
ck "prints non-empty output" test -n "$got"

# 2) Trailing newline REQUIRED: `ls -l` terminates every line (incl. the last),
#    so the correct output ends with a newline. A deliverable that strips the
#    final newline passes the lenient `$(...)` compare below but KOs the Moulinette.
ck_final_newline "output ends with a trailing newline (ls -l is line-terminated)" "$raw"

# 3) Structure: keeps only alternate lines, so the printed line count is exactly
#    ceil(total_lines / 2). With 9 files, `ls -l` prints 10 lines (1 total + 9
#    entries); every other line starting from the first keeps 5. This is a spec
#    property (the "every second line" rule), not the listing content.
full_n=$(cd "$T" && ls -l | wc -l | tr -d ' ')
got_n=$(printf '%s\n' "$got" | wc -l | tr -d ' ')
exp_n=$(( (full_n + 1) / 2 ))
ck "prints every other line: exactly ceil(N/2) lines kept" test "$got_n" = "$exp_n"

# 4) Same listing, alternate lines kept (1st,3rd,5th,...). Plain pass/fail: the
#    expected listing would reveal the answer, so it is not printed.
ck "keeps every other line of \`ls -l\` (1st,3rd,5th,...)" test "$got" = "$want"

rm -f "$raw"
rm -rf "$T"
ck_report
