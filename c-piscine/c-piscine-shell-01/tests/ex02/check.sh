#!/bin/sh
# Shell 01 ex02, and Piscine Reloaded ex03, which repeats it (its BUILD call
# names this file through twin_of) — find_sh.sh: print the basename (with the
# .sh extension removed) of every .sh file found in the tree. Per-property
# checklist (no expected listing printed: the produced name set IS the answer,
# so set-equality is a plain pass/fail).
#
# Trailing-newline hardening: the subject's example pipes through `cat -e` and shows
# EVERY line — the last one included (`find_sh$ file1$ ... file3$`) — ending in `$`,
# so each entry is newline-terminated and the output ends with a newline. The
# Moulinette compares stdout byte-for-byte, but a `$(... | sort)` capture strips the
# terminator and reorders, so we assert the terminator on the RAW bytes instead.
#
# THE TREE holds the names every reading of the subject agrees on, and the
# look-alikes that tell a right answer from the usual slips:
#   - '.sh' inside the name as well as at its end (my.shell.sh, and
#     sub/a.sh.b.sh): the extension is the LAST '.sh', so they are listed as
#     my.shell and a.sh.b;
#   - names that only contain '.sh' (nonfindeable.sh.backup), or end in 'sh'
#     with no '.sh' extension (dotlesssh, sub/dotless.bash): not .sh files;
#   - a DIRECTORY named lib.sh, holding a real .sh file (lib.sh/inner.sh).
# "All files ending with .sh" (Reloaded: "all file names that end with .sh")
# does not settle whether a directory is one of those files: in Unix's own
# vocabulary a directory is a file too. So the directory's own name, lib, may
# be listed or not here, and the file inside it must be, since every reading
# lists that one.
# regular.sh reads "files" as regular files only, at strict (the exercise's
# exNN_regular target); the two subjects' different wording leaves the same
# case open, so one reading serves both.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-find_sh.sh}
case "$D" in /*) ;; *) D="$PWD/$D";; esac
printf "  CHECK: %s\n" "$D"

ck_require "find_sh.sh deliverable exists" test -f "$D"
# The subject's example runs it as ./find_sh.sh, so its execute bit is required
# (docs/reference.md, "Run contract").
ck_executable "$D"
# The subject: shell exercises must be executable with /bin/sh.
ck_sh_parses "$D"

# The tree above, built fresh.
work=$(mktemp -d)
cp "$D" "$work/find_sh.sh" 2>/dev/null
mkdir -p "$work/sub" "$work/lib.sh"
: > "$work/findeable1.sh"
: > "$work/sub/findeable2.sh"
: > "$work/my.shell.sh"
: > "$work/sub/a.sh.b.sh"
: > "$work/lib.sh/inner.sh"
: > "$work/nonfindeable.sh.backup"
: > "$work/nonfindeable.somethingelse"
: > "$work/dotlesssh"
: > "$work/sub/dotless.bash"

# Capture the RAW output once (bytes preserved, including any final newline),
# into a file OUTSIDE the tree: the run must see the fixture and nothing of
# ours. The got file below is written after the run, and is *.txt anyway.
rawf=$(mktemp)
ck_run -C "$work" "$rawf" sh find_sh.sh

# Sorted, order-independent view for the set/format checks (find's order is
# filesystem-dependent, so we normalise by sorting).
got=$(LC_ALL=C sort < "$rawf")
gotf="$work/got.txt"
printf '%s\n' "$got" > "$gotf"

# Positive cases: every real .sh file contributes its bare basename, suffix removed.
ck "lists a top-level .sh file (suffix stripped)"   grep -qx findeable1 "$gotf"
ck "lists a NESTED .sh file (path dropped, suffix stripped)" grep -qx findeable2 "$gotf"
ck "lists the script itself with .sh removed"       grep -qx find_sh "$gotf"
ck "strips only the final .sh: my.shell.sh is listed as my.shell" grep -qx my.shell "$gotf"
ck "...nested too: sub/a.sh.b.sh is listed as a.sh.b" grep -qx a.sh.b "$gotf"
ck "lists a .sh file inside a directory whose own name ends in .sh (lib.sh/inner.sh)" \
	grep -qx inner "$gotf"

# Trap cases. Each absence is only seen in output that exists: a script that
# prints nothing has not ignored the look-alike, it has listed nothing.
ck "ignores the .sh.backup look-alike" \
	sh -c '[ -s "$2" ] && ! grep -q nonfindeable "$1"' _ "$gotf" "$rawf"
ck "ignores names ending in sh with no .sh extension (dotlesssh, dotless.bash)" \
	sh -c '[ -s "$2" ] && ! grep -q dotles "$1"' _ "$gotf" "$rawf"
ck "leaves no .sh extension on any name" \
	sh -c '[ -s "$2" ] && ! grep -q "[.]sh\$" "$1"' _ "$gotf" "$rawf"

# Exact-match hardening (the class Moulinette KOs on):
#  - each entry is newline-terminated, so the whole output ends with a newline;
#  - no stray blank line (an extra newline, or a name printed empty).
ck_final_newline "output ends with a newline (each entry newline-terminated)" "$rawf"
ck "no empty/blank lines in the output" sh -c '[ -s "$1" ] && ! grep -q "^$" "$1"' _ "$rawf"

# Exact set, order-independent: no extras, nothing missing. Pass/fail only.
# The directory's own name is left out of what was printed first, since the
# subject does not say whether it is one of the files (see the top).
want=$(printf '%s\n' find_sh findeable1 findeable2 my.shell a.sh.b inner | LC_ALL=C sort)
core=$(printf '%s\n' "$got" | grep -vx lib)
ck "produced name set matches the reference exactly (lib.sh's own name aside)" \
	test "$core" = "$want"

rm -f "$rawf" "$rawf.err"
rm -rf "$work"
ck_report
