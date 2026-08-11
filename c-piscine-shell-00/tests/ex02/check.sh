#!/bin/sh
# ex02 — exo2.tar must hold the 7 items test0..test6 with the exact member
# TYPE + permission string and the two link relationships shown by ls -l in the
# subject, AND the exact content SIZE of the regular files. The owner/group,
# date and time columns are intentionally ignored (they read "XX" / vary).
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

TAR=${1:-exo2.tar}
printf "  CHECK: %s\n" "$TAR"

ck "exo2.tar exists" test -f "$TAR"
ck "exo2.tar is a readable tar archive" tar -tf "$TAR"

tv=$(tar -tvf "$TAR" 2>/dev/null)

# exactly 7 members
n=$(printf '%s\n' "$tv" | grep -c .)
ck_eq "archive holds 7 members" "$n" "7"

# mode string (tar -tvf field 1) for a member matched by the given regex
modeof() { printf '%s\n' "$tv" | grep -E "$1" | awk '{print $1; exit}'; }

# Each member: correct entry TYPE + permission bits (per the subject's ls -l).
ck_eq "test0/ : directory, perms drwx--xr-x" "$(modeof ' test0/$')"  "drwx--xr-x"
ck_eq "test1  : regular file, perms -rwx--xr--" "$(modeof ' test1$')"  "-rwx--xr--"
ck_eq "test2/ : directory, perms dr-x---r--" "$(modeof ' test2/$')"  "dr-x---r--"
ck_eq "test3  : regular file, perms -r-----r--" "$(modeof ' test3$')"  "-r-----r--"
ck_eq "test4  : regular file, perms -rw-r----x" "$(modeof ' test4$')"  "-rw-r----x"

# test5 is a hard link to test3: tar marks the member type 'h' and records the
# link target. Its own perms must read -r-----r-- (the 'h' replaces the leading '-').
ck_eq "test5  : hard-link entry, perms hr-----r--" \
	"$(modeof ' test5 link to test3$')" "hr-----r--"
ck "test5 is a hard link to test3" \
	sh -c 'printf "%s\n" "$1" | grep -qE " test5 link to test3$"' _ "$tv"

# test6 is a symbolic link to test0 (symlink perms are always lrwxrwxrwx).
ck_eq "test6  : symlink entry, perms lrwxrwxrwx" \
	"$(modeof ' test6 -> test0$')" "lrwxrwxrwx"
ck "test6 is a symbolic link to test0" \
	sh -c 'printf "%s\n" "$1" | grep -qE " test6 -> test0$"' _ "$tv"

# Content SIZE of the regular members. The subject's ls -l prints these as
# concrete byte counts (test1 -> 4, test4 -> 2, test3 -> 1), NOT the ignorable
# "XX", so they are graded properties. The size is the member's content byte
# count baked into the archive: deterministic and independent of host, locale
# and timezone. We measure it by extracting the members and counting bytes,
# which is format-agnostic across tar variants rather than trusting a rendered
# size column. These are subject constants (a count), so plain ck_eq is fine —
# it reveals nothing about HOW the archive is built.
X=$(mktemp -d)
tar -xf "$TAR" -C "$X" 2>/dev/null
bytes() { wc -c < "$1" 2>/dev/null | tr -d ' '; }
ck_eq "test1  : content is 4 bytes"  "$(bytes "$X/test1")" "4"
ck_eq "test3  : content is 1 byte"   "$(bytes "$X/test3")" "1"
ck_eq "test4  : content is 2 bytes"  "$(bytes "$X/test4")" "2"
# tidy up (some extracted members carry write-less perms, so restore first)
chmod -R u+rwx "$X" 2>/dev/null
rm -rf "$X"

ck_report
