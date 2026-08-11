#!/bin/sh
# ex02 — find_sh.sh: print the basename (with the .sh extension removed) of every
# .sh file found in the tree. Per-property checklist (no expected listing printed:
# the produced name set IS the answer, so set-equality is a plain pass/fail).
#
# Trailing-newline hardening: the subject's example pipes through `cat -e` and shows
# EVERY line — the last one included (`find_sh$ file1$ ... file3$`) — ending in `$`,
# so each entry is newline-terminated and the output ends with a newline. The
# Moulinette compares stdout byte-for-byte, but a `$(... | sort)` capture strips the
# terminator and reorders, so we assert the terminator on the RAW bytes instead.
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-find_sh.sh}
case "$D" in /*) ;; *) D="$PWD/$D";; esac
printf "  CHECK: %s\n" "$D"

ck "find_sh.sh deliverable exists" test -f "$D"

# Build a clean tree: a top-level .sh, a NESTED .sh, and two decoys whose names
# only resemble .sh files (one ends in .sh.backup, one in .somethingelse).
work=$(mktemp -d)
cp "$D" "$work/find_sh.sh" 2>/dev/null
mkdir -p "$work/sub"
: > "$work/findeable1.sh"
: > "$work/sub/findeable2.sh"
: > "$work/nonfindeable.sh.backup"
: > "$work/nonfindeable.somethingelse"

# Capture the RAW output once (bytes preserved, including any final newline). The
# helper files below are *.txt, so they are never matched by the *.sh search.
rawf="$work/raw.txt"
(cd "$work" && sh find_sh.sh 2>/dev/null) > "$rawf"

# Sorted, order-independent view for the set/format checks (find's order is
# filesystem-dependent, so we normalise by sorting).
got=$(sort < "$rawf")
gotf="$work/got.txt"
printf '%s\n' "$got" > "$gotf"

# Positive cases: every real .sh file contributes its bare basename, suffix removed.
ck "lists a top-level .sh file (suffix stripped)"   grep -qx findeable1 "$gotf"
ck "lists a NESTED .sh file (path dropped, suffix stripped)" grep -qx findeable2 "$gotf"
ck "lists the script itself with .sh removed"       grep -qx find_sh "$gotf"

# Trap cases: a name that only contains '.sh' (e.g. *.sh.backup) is NOT a .sh file.
ck "ignores the .sh.backup look-alike"  sh -c '! grep -q nonfindeable "$1"' _ "$gotf"
ck "leaves no .sh suffix on any name"   sh -c '! grep -q "[.]sh" "$1"' _ "$gotf"

# Exact-match hardening (the class Moulinette KOs on):
#  - each entry is newline-terminated, so the whole output ends with a newline;
#  - no stray blank line (an extra newline, or a name printed empty).
ck_final_newline "output ends with a newline (each entry newline-terminated)" "$rawf"
ck "no empty/blank lines in the output" sh -c '! grep -q "^$" "$1"' _ "$rawf"

# Exact set, order-independent: no extras, nothing missing. Pass/fail only.
want=$(printf 'find_sh\nfindeable1\nfindeable2\n' | sort)
ck "produced name set matches the reference exactly" test "$got" = "$want"

ck_report
