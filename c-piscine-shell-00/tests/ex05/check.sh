#!/bin/sh
# ex05 — git_commit.sh must print the 5 most recent commit hashes, newest first.
# The Moulinette runs `bash git_commit.sh | cat -e` and compares byte-for-byte:
# each hash is on its own line and the last line is terminated by a newline
# (git's default `git log --format=%H` output). A stray missing/extra trailing
# newline is a real KO that a shell-stripping `$(...)` capture cannot see, so we
# also assert the RAW terminator and the exact line-terminator count.
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

case "${1:-}" in
	/*) D="$1" ;;
	*)  D="$PWD/${1:-git_commit.sh}" ;;
esac
printf "  CHECK: %s\n" "$D"

ck "git_commit.sh exists"      test -f "$D"
ck "git_commit.sh is executable" test -x "$D"

# Build a throwaway repo with 6 commits so "last 5" is a real subset.
# Self-contained fixture => deterministic and host-safe (no reliance on the
# checking machine's own repos/config).
work=$(mktemp -d)
(
	cd "$work" || exit 1
	git init -q repo
	cd repo || exit 1
	git config user.email tester@example.com
	git config user.name tester
	i=1
	while [ "$i" -le 6 ]; do
		echo "$i" > f
		git add f
		git commit -q -m "commit $i"
		i=$((i + 1))
	done
)
repo="$work/repo"

# Shell-stripped capture (for counts/order) AND a byte-exact raw capture (for
# the terminator assertions the stripped form is blind to).
out=$(cd "$repo" && sh "$D")
raw=$(mktemp)
( cd "$repo" && sh "$D" ) > "$raw" 2>/dev/null

# Every printed line must be a 40-char lowercase-hex commit hash, and there must
# be exactly 5 of them — no more (no log noise), no fewer.
total=$(printf '%s\n' "$out" | grep -c .)
hashes=$(printf '%s\n' "$out" | grep -cE '^[0-9a-f]{40}$')
ck_eq "lines printed (count)"        "$total"  "5"
ck_eq "lines that are 40-hex hashes" "$hashes" "5"

# Terminator: git's per-line output ends the LAST hash with a newline, so
# `... | cat -e` shows a '$' after every hash including the fifth. Assert it
# byte-exactly on the raw output.
ck_final_newline "output ends with a newline (fifth hash on its own terminated line)" "$raw"

# Exactly 5 line terminators — no missing final newline (would be 4) and no
# stray trailing blank line (would be 6). Both are invisible to the $(...) capture
# above but are byte-level KOs on the Moulinette. 5 is a spec constant, not the answer.
nl=$(wc -l < "$raw" | tr -d ' ')
ck_eq "exactly 5 newline-terminated lines (no missing/extra trailing newline)" "$nl" "5"

# Order: must match the repo's actual last-5 log, newest first. The exact hash
# sequence is the answer, so this is a plain pass/fail — expected value not shown.
want=$(cd "$repo" && git log -n 5 --format='%H')
ck "hashes are the last 5 commits, newest first" [ "$out" = "$want" ]

rm -f "$raw"
rm -rf "$work"
ck_report
