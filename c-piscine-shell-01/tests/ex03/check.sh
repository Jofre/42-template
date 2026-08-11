#!/bin/sh
# ex03 — count_files.sh must print the total number of regular files AND
# directories in the current tree, counting "." (the starting directory) too.
#
# We stage a KNOWN tree and assert the exact SPEC count on it. The count is a
# property of the fixture we build here (not the exercise's answer), so it is a
# plain pass/fail — no expected value is printed, and the *technique* for
# counting is never shown.
#
# Trailing-newline note: the natural output of this exercise is a `wc -l` count,
# which terminates its single line with a newline. The Moulinette compares stdout
# byte-for-byte, so a solution that strips that final newline (or adds a second
# line / stray spaces) is a real KO. The previous check squashed all whitespace
# with `tr -d '[:space:]'` and was blind to every one of those. We now capture
# the RAW bytes and assert the exact terminator + single-line integer format.
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-count_files.sh}
printf "  CHECK: %s\n" "$D"

ck "count_files.sh exists" test -f "$D"

# Build a deterministic tree the script is run inside. Contents:
#   .              -> 1   (the starting directory itself MUST be counted)
#   count_files.sh -> 1   (a regular file)
#   folder         -> 1   (a subdirectory)
#   folder/a folder/b folder/c -> 3
#   a b c          -> 3
#   link -> (dangling) -> 0   (a SYMLINK: neither a regular file nor a directory)
# Total files+dirs (including ".") = 9, out of 10 entries a recursive walk sees.
#
# WHY THE SYMLINK IS IN THE TREE. The subject asks for "the total number of
# regular files and directories", which is a TYPE PREDICATE — and this tree used
# to contain nothing but regular files and directories. In such a tree "count
# every entry the walk prints" and "count only the files and dirs" are the SAME
# NUMBER, so a deliverable that applies no type predicate at all scored a perfect
# 6/6 here. That is the classic pinned-fixture hole: the staged input was the one
# input at which the right and the wrong program agree, and the exercise's whole
# discriminating axis went unmeasured. The symlink is the cheapest entry that is
# neither a regular file nor a directory: it makes a predicate-less walk report
# 10 while the spec count stays 9, and it costs a correct solution nothing.
# Note the tree already caught the OPPOSITE mistake (regular files only, dropping
# the six directory-and-"." entries), so with this line both halves of "regular
# files AND directories" are finally pinned — under-counting and over-counting.
#
# WHY THE LINK IS DANGLING, AND NOT POINTING AT A REAL FILE. This matters more
# than it looks: it is the difference between closing a hole and opening a worse
# one. Both shapes red the predicate-less walk equally (10 vs 9) — but a link
# that RESOLVES also reds implementations that are legitimately CORRECT, because
# several perfectly ordinary ways of asking "is this a regular file?" answer for
# the link's TARGET rather than the link (following symlinks is documented POSIX
# behaviour for the file-type tests, not a student bug). Against a resolving link
# those forms count the link as a regular file — and so count the SAME underlying
# file twice, once under each name — landing on 10 and failing for a reason that
# has nothing to do with this exercise. A dangling link has no target type to
# inherit, so every one of those forms reports it as neither file nor directory:
# they all land on 9, while the predicate-less walk still lands on 10. Measured,
# every form named in the verification notes, against both tree shapes.
# This is the "when in doubt, assert less" rule: we discriminate on exactly the
# axis the exercise is about (does the count apply a type predicate at all?) and
# on nothing else — symlink RESOLUTION semantics are not what ex03 is teaching.
# (Per this file's own policy above, the technique for counting is never shown:
# the reasoning here is stated in terms of behaviour, never as a command line.)
#
# Degradation: if `ln -s` ever fails (a filesystem with no symlink support), the
# tree falls back to its old 9-entry shape and the assertion below is still
# correct, merely weaker again. A lost discrimination, never a false FAIL.
T=$(mktemp -d)
cp "$D" "$T/count_files.sh" 2>/dev/null
mkdir "$T/folder"
: > "$T/folder/a"; : > "$T/folder/b"; : > "$T/folder/c"
: > "$T/a"; : > "$T/b"; : > "$T/c"
ln -s nonexistent-on-purpose "$T/link" 2>/dev/null

# Capture RAW output (with any trailing newline) once; derive everything from it.
raw=$(mktemp)
( cd "$T" && sh count_files.sh ) > "$raw" 2>/dev/null

# The whitespace-stripped value is used only for the count comparison, so the
# correctness check stays robust to any surrounding whitespace.
got=$(tr -d '[:space:]' < "$raw")
# First line as printed (final newline dropped by head, internal spaces kept),
# so we can assert the count is a bare integer with no padding or stray chars.
first=$(head -n1 "$raw")

# 1) It must actually print something.
ck "prints non-empty output" test -s "$raw"

# 2) Output ends with a newline. `wc -l` terminates its line; a stripped final
#    newline is a byte-for-byte Moulinette KO the old check could not see.
ck_final_newline "output ends with a trailing newline" "$raw"

# 3) Exactly one line — the count and nothing else (no banner, no blank 2nd line).
ck "output is a single line (the count only)" \
	test "$(wc -l < "$raw" | tr -d ' ')" = "1"

# 4) That line is a bare non-negative integer: digits only, no leading/trailing
#    spaces (GNU `wc -l` reading a pipe emits no padding) and no extra text.
ck "output is a bare integer (digits only, no padding or extra text)" \
	sh -c 'case "$1" in ""|*[!0-9]*) exit 1;; *) exit 0;; esac' _ "$first"

# 5) The count itself: every file and dir, including ".", and NOTHING else.
#    Plain pass/fail so the expected count is never printed and the counting
#    method is not shown. The label names the fixture's shape (a fixture fact,
#    not the answer) so a stranger reading a FAIL knows what was staged.
ck "counts only files and dirs, incl. '.' (staged tree: 9 of them + 1 symlink)" \
	test "$got" = "9"

rm -f "$raw"
rm -rf "$T"
ck_report
