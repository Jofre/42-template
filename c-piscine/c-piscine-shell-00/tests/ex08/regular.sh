#!/bin/sh
# Shell 00 ex08 and Piscine Reloaded ex02, "files" read as regular files --
# each one's exNN_regular target, at strict.
#
# "Searches for all files ... that end with ~ (tilde) or, start and end with
# # (hash)" (Reloaded: "all files ... with a name ending by ~, or with a name
# that start and end by #"). Whether a DIRECTORY named that way is one of
# those files, the subject does not say, and man find, which it points to,
# calls every entry a file. check.sh (basic) holds no such directory. This
# reads "files" as regular files only: a directory named like a backup, empty
# or not, is neither displayed nor deleted, and neither is what it holds. It
# is the reading Shell 01 ex02's regular.sh applies to find_sh.sh, which has
# the same words. Which one 42 applies is not settled -- which is what puts
# this at strict and not at basic (docs/reference.md, "Run contract").
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

C=${1:-clean}
case "$C" in
	/*) CA=$C ;;
	*)  CA=$(pwd)/$C ;;
esac
printf "  CHECK: %s, this harness's reading at strict: \"files\" as regular files only\n" "$C"

ck_require "clean file exists" test -f "$CA"
ck_sh_parses "$CA"

# Two backup files, so a clean that does nothing does not pass, and a
# directory of each pattern, empty and holding an ordinary file.
SB=$(mktemp -d)
: > "$SB/test~"
: > "$SB/#test#"
mkdir -p "$SB/olddir~" "$SB/#olddir#" "$SB/full~" "$SB/#full#"
: > "$SB/full~/keep"
: > "$SB/#full#/keep"

raw=$(mktemp)
ck_run -C "$SB" "$raw" sh "$CA"

ck "deletes the backup files (test~, #test#)" \
	sh -c '! [ -e "$1/test~" ] && ! [ -e "$1/#test#" ]' _ "$SB"
ck "keeps an empty directory named like a backup (olddir~/)" test -d "$SB/olddir~"
ck "keeps an empty directory named like a backup (#olddir#/)" test -d "$SB/#olddir#"
ck "keeps a directory named like a backup, and the file in it (full~/keep)" \
	test -f "$SB/full~/keep"
ck "keeps a directory named like a backup, and the file in it (#full#/keep)" \
	test -f "$SB/#full#/keep"
# Asked of a display that exists: one that shows nothing has not left the
# directories out.
ck "displays no directory (olddir~, #olddir#, full~, #full#)" \
	sh -c '[ -s "$1" ] && ! sed "s:/*\$::; s:.*/::" "$1" | grep -qx -e "olddir~" -e "#olddir#" -e "full~" -e "#full#"' \
	_ "$raw"

chmod -R u+rwx "$SB" 2> /dev/null
rm -rf "$SB"
rm -f "$raw" "$raw.err"
ck_report
