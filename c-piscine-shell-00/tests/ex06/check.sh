#!/bin/sh
# ex06 — git_ignore.sh lists files ignored by git but not tracked.
#
# Hardening note: the Moulinette compares stdout byte-for-byte. `git ls-files`
# prints one path per line, each terminated by a newline — the subject's
# `bash git_ignore.sh | cat -e` example ends EVERY entry (incl. the last) with a
# `$`, i.e. a trailing newline is required. A shell `$(...)` capture silently
# strips that final newline, so we ALSO capture the RAW bytes and assert the
# terminator, then pin the whole listing with an exact match against a CONTROLLED
# fixture we build here. That exact match is a plain pass/fail whose expected
# value is a set of fixture filenames we created — not the solution.
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D="${1:-git_ignore.sh}"
case "$D" in /*) ;; *) D="$PWD/$D" ;; esac
printf "  CHECK: %s\n" "$D"

ck "git_ignore.sh exists"     test -f "$D"
ck "git_ignore.sh executable" test -x "$D"

# Build a fixture repo with a deterministic set of ignored-untracked files:
#   *.log is ignored -> alpha.log, one.log, two.log are ignored + untracked
#   tracked.txt is staged (in the index) -> tracked, so NOT an "other" file
# git ls-files sorts its output, so the expected listing is fully determined and
# host-independent (a global core.excludesfile can only change whether these
# files are ignored — they always are, via the local .gitignore).
git init -q repo 2>/dev/null
cd repo 2>/dev/null || { ck "fixture repo created" false; ck_report; }
git config user.email tester@example.com
git config user.name tester
printf '*.log\n' > .gitignore
: > alpha.log
: > one.log
: > two.log
: > tracked.txt
git add .gitignore tracked.txt

# Capture RAW bytes (with any trailing newline) and the shell-stripped form.
raw=$(mktemp)
sh "$D" > "$raw" 2>/dev/null
out=$(sh "$D" 2>/dev/null)

# 1) An ignored-but-untracked file must appear in the listing.
printf '%s\n' "$out" | grep -qx 'one.log'
ck "lists an ignored-untracked file (one.log)" test "$?" -eq 0

# 2) A tracked file must NOT appear (it is in the index, not an ignored "other").
printf '%s\n' "$out" | grep -qx 'tracked.txt'
ck "does NOT list a tracked file (tracked.txt)" test "$?" -ne 0

# 3) One path per line: exactly the 3 ignored files, newline-separated (not
#    space/comma joined onto one line). Line count is a format property.
nlines=$(printf '%s\n' "$out" | grep -c .)
ck "one path per line (3 ignored files -> 3 lines)" test "$nlines" -eq 3

# 4) Trailing newline present: every entry (including the last) is terminated by
#    a newline, as the subject's `| cat -e` shows. This is the exact-match KO
#    class the `$(...)` capture above is blind to.
ck_final_newline "output ends with a newline (each entry line-terminated)" "$raw"

# 5) Authoritative listing for this controlled fixture: exactly the ignored-
#    untracked files, sorted, one per line. Plain pass/fail — the expected value
#    is a set of fixture filenames we created here, never the solution itself.
want=$(printf 'alpha.log\none.log\ntwo.log')
ck "lists exactly the ignored-untracked files for this fixture" test "$out" = "$want"

rm -f "$raw"
ck_report
