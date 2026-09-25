#!/bin/sh
# ex05 — git_commit.sh must print the 5 most recent commit hashes, newest first.
# The Moulinette runs `bash git_commit.sh | cat -e` and compares byte-for-byte:
# one full 40-hex hash per line, and the last line newline-terminated too -- the
# subject's cat -e transcript shows a '$' after every hash, the fifth included.
# A stray missing/extra trailing newline is a real KO that a shell-stripping
# `$(...)` capture cannot see, so we also assert the RAW terminator and the
# exact line-terminator count.
# shellcheck source=../../../../tools/shell_check.sh
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
		# Record each commit as it is MADE: the expected answer then comes from
		# the fixture, not from asking git for its history (which is the
		# exercise).
		git rev-parse HEAD >> ../made
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

# Terminator: the subject's `... | cat -e` shows a '$' after every hash
# including the fifth, so the LAST hash ends with a newline too. Assert it
# byte-exactly on the raw output.
ck_final_newline "output ends with a newline (fifth hash on its own terminated line)" "$raw"

# Exactly 5 line terminators — no missing final newline (would be 4) and no
# stray trailing blank line (would be 6). Both are invisible to the $(...) capture
# above but are byte-level KOs on the Moulinette. 5 is a spec constant, not the answer.
nl=$(wc -l < "$raw" | tr -d ' ')
ck_eq "exactly 5 newline-terminated lines (no missing/extra trailing newline)" "$nl" "5"

# Order: the five newest commits, newest first -- the last five hashes the
# fixture recorded, reversed. A plain pass/fail; the hashes are not printed.
want=$(tail -n 5 "$work/made" | awk '{ h[NR] = $0 } END { for (i = NR; i >= 1; i--) print h[i] }')
ck "hashes are the last 5 commits, newest first" [ "$out" = "$want" ]

rm -f "$raw"
rm -rf "$work"
ck_report
