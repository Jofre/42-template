#!/bin/sh
# Shell 00 ex08 and Piscine Reloaded ex02, read literally -- each one's
# exNN_literal target, at strict.
#
# The subject: "Only one command is allowed", with no ';' or '&&' or other
# chaining. check.sh (basic) reads that the way the shell reads the file: a
# ';', '&&' or '||' joining two commands fails, and so does a second command
# line, while a quoted or escaped ';', which is an argument, passes. This reads
# the same words literally:
#   - no ';' character anywhere in the file, not even a quoted or escaped one,
#     and not even in a comment;
#   - no '&&' anywhere either;
#   - one command, so nothing that joins it to another: no ';', '&&' or
#     '||' between two commands and no second command line (what check.sh
#     fails too), no pipe, and no '&'.
# Which of the two readings 42 applies, the subject does not say -- which is
# what puts this at strict and not at basic (docs/reference.md, "Run
# contract").
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

C=${1:-clean}
printf "  CHECK: %s, this harness's reading at strict: \"only one command\" taken literally\n" "$C"

ck_require "clean file exists" test -f "$C"
ck "no ';' character anywhere in the file (not even a quoted or escaped one)" \
	sh -c 'test -f "$1" && ! grep -qF ";" "$1"' _ "$C"
ck "no '&&' anywhere in the file" \
	sh -c 'test -f "$1" && ! grep -qF "&&" "$1"' _ "$C"
ck_no_operator "one command: no ';' '&&' '||' '|' '&' joining two, no second line" "$C" \
	';' '&&' '||' '|' '&' newline

ck_report
