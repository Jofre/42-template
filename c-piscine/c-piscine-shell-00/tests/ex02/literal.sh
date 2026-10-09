#!/bin/sh
# Shell 00 ex02 and Piscine Reloaded ex00, read literally -- each one's
# exNN_literal target, at strict. The archive's name (exo2.tar, exo.tar) is
# the only difference, and it arrives as $1.
#
# The subject ends the exercise with the command that makes the archive:
# `tar -cf <archive> *`. check.sh (basic) grades the tree the archive extracts
# to, so './'-prefixed names, a './' entry, or the hard link recorded the other
# way round all pass there: each extracts to exactly the subject's ls -l. This
# reads that command word for word instead, and asks for the listing it
# writes: the seven bare names in name order (that is how the shell expands
# `*`), and test5 recorded as the link to test3, which it meets first. Whether
# 42 grades that listing, or only the tree, the subject does not say -- which
# is what puts this at strict and not at basic (docs/reference.md, "Run
# contract").
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

TAR=${1:?the archive name, which each BUILD call passes}
N=${TAR##*/}
printf "  CHECK: %s, this harness's reading at strict: as \`tar -cf %s *\` writes it\n" "$TAR" "$N"

ck_require "$N exists" test -f "$TAR"

names=$(tar -tf "$TAR" 2>/dev/null | tr '\n' ' ')
ck_eq "members listed as \`tar -cf $N *\` writes them: bare names, in name order" \
	"${names% }" "test0/ test1 test2/ test3 test4 test5 test6"
ck "test5 is the member recorded as the hard link (to test3), as that command records it" \
	sh -c 'tar -tvf "$1" 2>/dev/null | grep -q " test5 link to test3$"' _ "$TAR"

ck_report
