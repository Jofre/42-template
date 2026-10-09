#!/bin/sh
# Shell 01 ex02 and Piscine Reloaded ex03, "files" read as regular files --
# each one's exNN_regular target, at strict.
#
# "searches for all files ending with .sh" (Reloaded: "all file names that
# end with ".sh""). Whether a directory whose name ends in .sh is one of
# those files, or a directory's name one of those file names, neither subject
# says, and in Unix's own vocabulary a directory is a file too. check.sh
# (basic) grades what both readings agree on: the .sh file inside such a
# directory is listed, and the directory's own name may be or not. This reads
# the sentence as naming regular files only, so the directory's name is not
# listed: the reading Shell 00 ex08's regular.sh applies to clean, whose
# subject says "all files" too. Which one 42 applies is not settled -- which
# is what puts this at strict and not at basic (docs/reference.md, "Run
# contract").
#
# The two subjects' sentences differ, so the one this target's subject says
# comes from its shell_exercise call (wording = {"files": ...}), and the
# check quotes it: a Reloaded student reads Reloaded's words, never Shell
# 01's (ck_wording, tools/shell_check.sh).
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-find_sh.sh}
case "$D" in /*) ;; *) D="$PWD/$D";; esac
ck_wording files
printf '  CHECK: %s\n' "$D"
printf '  The subject says: %s\n' "$CK_WORDING"
printf "  This harness's reading, at strict: it names regular files only, and a\n"
printf '  directory, whatever its name, is not one of them.\n'

ck_require "find_sh.sh deliverable exists" test -f "$D"
ck_sh_parses "$D"

work=$(mktemp -d)
cp "$D" "$work/find_sh.sh" 2>/dev/null
mkdir -p "$work/lib.sh"
: > "$work/findeable1.sh"
: > "$work/lib.sh/inner.sh"

rawf=$(mktemp)
ck_run -C "$work" "$rawf" sh find_sh.sh

# Both regular files are listed, so the absence below is asked of a listing
# that exists and reaches into the directory.
ck "lists a regular .sh file (findeable1)" grep -qx findeable1 "$rawf"
ck "lists the regular .sh file inside lib.sh/ (inner)" grep -qx inner "$rawf"
ck "does not list the directory lib.sh: it is not a regular file" \
	sh -c '[ -s "$1" ] && ! grep -qx lib "$1"' _ "$rawf"

rm -f "$rawf" "$rawf.err"
rm -rf "$work"
ck_report
