#!/bin/sh
# ex01 — testShell00.tar must hold exactly one member: a 40-byte file named
# testShell00 with permissions -r--r-xr-x and mtime 2026-06-01 23:42.
# Emits a per-property PASS/FAIL checklist via shell_check.sh.
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?shell_check library not provided}"

TAR=${1:-testShell00.tar}
printf '  CHECK: %s\n' "$TAR"
ck "the archive $TAR is produced" test -f "$TAR"
if [ -f "$TAR" ]; then
	ck "is a readable tar archive" tar -tf "$TAR"
	ck_eq "holds exactly one member" "$(tar -tf "$TAR" 2>/dev/null | wc -l | tr -d ' ')" "1"
	# tar -tvf line: <perms> <owner/group> <size> <date> <time> <name>
	# shellcheck disable=SC2046
	set -- $(tar -tvf "$TAR" 2>/dev/null | head -1)
	ck_eq "member is named testShell00" "${6:-}" "testShell00"
	ck_eq "member permissions" "${1:-}" "-r--r-xr-x"
	ck_eq "member size in bytes" "${3:-}" "40"
	ck_eq "member modification date" "${4:-}" "2026-06-01"
	ck_eq "member modification time" "${5:-}" "23:42"
fi
ck_report
