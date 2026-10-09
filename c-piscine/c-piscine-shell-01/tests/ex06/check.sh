#!/bin/sh
# ex06 — skip.sh must run `ls -l` and print every OTHER line starting from the
# first (lines 1,3,5,...). `ls -l` is line-oriented output: every line, INCLUDING
# the last, is terminated by a newline (the subject's `cat -e` example shows a `$`
# after the final `toto` line). So the correct output ENDS WITH a trailing newline,
# and the Moulinette compares stdout byte-for-byte — a missing (or extra) final
# newline is a real KO that a shell-stripping `$(...)` capture is blind to.
#
# The expected listing is BUILT from the fixture, never computed by filtering a
# listing: that filter is the answer, and a check that runs it ships the answer
# in a file anyone can open. The full-listing match stays a plain pass/fail. The
# trailing-newline behavior and the "every other line" structure are spec
# properties, so asserting them reveals nothing.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-skip.sh}
case "$D" in /*) ;; *) D="$PWD/$D";; esac
printf "  CHECK: %s\n" "$D"

ck_require "skip.sh exists" test -f "$D"
# The subject's example runs it as ./skip.sh, so its execute bit is required
# (docs/reference.md, "Run contract"). The `ls -l` printed just
# above that run shows skip.sh as -rw-rw-r--, a mode ./skip.sh could not run
# under; the rule follows the run, which is the line that needs the bit.
ck_executable "$D"
# The subject: shell exercises must be executable with /bin/sh.
ck_sh_parses "$D"

# Build a deterministic listing context in a throw-away directory, identical for
# the student run and the reference: several files so `ls -l` has many lines and
# "every other line" is well-defined. A temp dir keeps this host-safe (independent
# of whatever else sits in the deliverable's directory).
T=$(mktemp -d)
i=1
while [ "$i" -le 9 ]; do : > "$T/$i"; i=$((i + 1)); done
# One timestamp for all nine: with the same size, links, owner and mode, every
# entry then prints with the same column widths whichever of them `ls` is shown.
touch -t 202606250900 "$T"/[1-9]

# One run inside the controlled directory, two views: the RAW bytes (with any
# trailing newline) and the shell-stripped form of them.
raw=$(mktemp)
ck_run -C "$T" "$raw" sh "$D"
got=$(cat "$raw")
# `ls -l` here is its "total" line, then the nine files in name order. The lines
# to keep (1st, 3rd, 5th, ...) are therefore the total line and files 2, 4, 6, 8,
# and `ls -ld` of those four prints them exactly as the full listing does.
want=$(cd "$T" && { ls -l | head -n 1; ls -ld 2 4 6 8; })

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

# 4) Same listing, alternate lines kept (1st,3rd,5th,...). Plain pass/fail.
ck "keeps every other line of \`ls -l\` (1st,3rd,5th,...)" test "$got" = "$want"

rm -f "$raw" "$raw.err"
rm -rf "$T"
ck_report
