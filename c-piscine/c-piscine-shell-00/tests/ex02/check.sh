#!/bin/sh
# Shell 00 ex02, and Piscine Reloaded ex00, which repeats it (its BUILD call
# names this file through twin_of). The archive must hold the 7 items
# test0..test6 with the exact member TYPE + permission string and the two link
# relationships shown by ls -l in the subject, the exact content SIZE of the
# regular files, and each item's date and time. Only what the subject prints as
# "XX" is ignored: the owner, the group, and the directories' sizes.
#
# The two subjects differ in the archive's name alone -- exo2.tar in Shell 00,
# exo.tar in Reloaded -- and it arrives as $1, from each call's `deliverable`,
# so nothing below spells either.
#
# What this grades is the tree the archive EXTRACTS to, because that tree is
# what the subject's ls -l shows. So each member is looked up by its name
# alone, and three archives that extract to exactly that tree all pass:
#   - members named './test0', './test1', ... (`tar -cf <archive> ./test*`, or
#     `tar -cf <archive> .`, whose extra './' entry is the directory it was run
#     in and adds no item to the listing);
#   - the hard link recorded the other way round, test3 as the link to test5:
#     tar stores the content under whichever name it meets first, and that is
#     test5 whenever test5 is archived first.
# The listing the subject's own `tar -cf <archive> *` writes -- bare names, in
# name order, test5 as the link -- is checked by literal.sh at strict, since
# whether 42 reads the listing as well as the tree is not something the
# subject settles.
#
# A member that is present but wrong shows as wrong, never as missing: looking
# test6 up by its whole `test6 -> test0` line used to report a link with any
# other target as having no permissions and no date. And a member that is
# missing is ONE line, its type-and-permissions line, which says so: its date,
# size and links are graded only when it is there to read them from, so an
# empty archive is seven lines saying what is missing, not twenty.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

TAR=${1:?the archive name, which each BUILD call passes}
N=${TAR##*/}
printf "  CHECK: %s\n" "$TAR"

ck_require "$N exists" test -f "$TAR"
ck "$N is a readable tar archive" tar -tf "$TAR"

# tar -tvf's listing, each name as it extracts: a leading './' dropped from the
# member's name and from a hard link's target (a symbolic link's target is the
# text it stores, and is left exactly as stored), and a bare './' entry dropped
# with its line. The first five fields are mode, owner/group, size, date, time.
tv=$(tar -tvf "$TAR" 2>/dev/null | awk '{
	s = $0
	p = ""
	for (i = 1; i <= 5; i++) {
		if (!match(s, /^[^ ]+ +/)) next
		p = p substr(s, 1, RLENGTH)
		s = substr(s, RLENGTH + 1)
	}
	while (substr(s, 1, 2) == "./") s = substr(s, 3)
	if (s == "" || s == ".") next
	sub(/ link to (\.\/)+/, " link to ", s)
	print p s
}')

# exactly 7 members
n=$(printf '%s\n' "$tv" | grep -c .)
ck_eq "archive holds 7 members" "$n" "7"

# One member's listing line, found by its NAME alone -- whatever follows the
# name ('/', ' -> target', ' link to target') is what gets graded, not how the
# line is found.
lineof() { printf '%s\n' "$tv" | awk -v n="$1" '$6 == n || $6 == n "/" { print; exit }'; }
# Whether the archive holds a member of that name.
here() { [ -n "$(lineof "$1")" ]; }
# Its mode string (tar -tvf field 1), or what was found instead.
modeof() {
	_l=$(lineof "$1")
	if [ -n "$_l" ]; then
		printf '%s\n' "$_l" | awk '{ print $1 }'
	else
		printf 'nothing: no %s in the archive' "$1"
	fi
}

# Each member: correct entry TYPE + permission bits (per the subject's ls -l).
ck_eq "test0/ : directory, perms drwx--xr-x" "$(modeof test0)"  "drwx--xr-x"
ck_eq "test1  : regular file, perms -rwx--xr--" "$(modeof test1)"  "-rwx--xr--"
ck_eq "test2/ : directory, perms dr-x---r--" "$(modeof test2)"  "dr-x---r--"
ck_eq "test4  : regular file, perms -rw-r----x" "$(modeof test4)"  "-rw-r----x"

# test3 and test5 are ONE file under two names: a hard link, which is why the
# subject's ls -l shows a link count of 2 on both. tar stores that file once,
# as a regular member, and records the other name as a link to it (type 'h' in
# place of '-'). Both of them extract to a regular file, which is what ls -l
# shows, so each name's permissions are read with the 'h' taken as that '-'.
asfile() { _m=$(modeof "$1"); case "$_m" in h*) _m="-${_m#h}" ;; esac; printf '%s' "$_m"; }
ck_eq "test3  : regular file, perms -r-----r--" "$(asfile test3)" "-r-----r--"
ck_eq "test5  : regular file, perms -r-----r--" "$(asfile test5)" "-r-----r--"
linkof() { lineof "$1" | sed -n 's/.* link to //p'; }
if here test3 && here test5; then
	l5=$(linkof test5)
	l3=$(linkof test3)
	if [ "$l5" = test3 ] || [ "$l3" = test5 ]; then
		pair="linked"
	elif [ -n "$l5" ]; then
		pair="test5 linked to $l5"
	elif [ -n "$l3" ]; then
		pair="test3 linked to $l3"
	else
		pair="two separate files"
	fi
	ck_eq "test3 and test5 are hard links to one file" "$pair" "linked"
fi

# test6 is a symbolic link to test0 (symlink perms are always lrwxrwxrwx). Its
# target is the text the link stores, which ls -l prints after '->': the subject
# shows exactly test0, 5 bytes.
symof() {
	_t=$(lineof "$1" | sed -n 's/.* -> //p')
	printf '%s' "${_t:-nothing: not a symbolic link}"
}
ck_eq "test6  : symlink entry, perms lrwxrwxrwx" "$(modeof test6)" "lrwxrwxrwx"
here test6 && ck_eq "test6 is a symbolic link to test0" "$(symof test6)" "test0"

# The timestamps. Every line of the subject's listing carries one -- Jun 1, at
# a time of its own -- and they are graded: the subject's only latitude is "a
# year will be accepted instead of the time", which ck_listed_at applies.
# Reloaded words it "if the year is diplayed in the case of the exercise's date
# (1 Jun) is outdated by six month or more", which comes to the same: ls -l
# shows the year in place of the time exactly then. tar keeps each member's
# date and time, and -tvf prints them in full.
stampof() { lineof "$1" | awk '{ print $4, $5 }'; }
for _m in "test0 20:47" "test1 21:46" "test2 22:45" "test3 23:44" \
	"test4 23:43" "test5 23:44" "test6 22:20"; do
	here "${_m% *}" || continue
	ck_listed_at "${_m% *}" "$(stampof "${_m% *}")" 06-01 "${_m#* }"
done

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
# The existence test comes first because `2>/dev/null` after `< "$1"` is too
# late: redirections apply left to right, so the shell's own "cannot open"
# error for a member that is not there reached the checklist, with a sandbox
# path in it. The braces put the whole command under the redirection. Each
# line below is asked only of a member the listing holds, so one that is
# there but is no regular file says so, and is never called missing.
bytes() {
	[ -e "$1" ] || [ -L "$1" ] || { printf 'nothing: it did not extract'; return 0; }
	if [ ! -f "$1" ] || [ -L "$1" ]; then
		printf 'nothing: not a regular file'
		return 0
	fi
	{ wc -c < "$1"; } 2>/dev/null | tr -d ' '
}
here test1 && ck_eq "test1  : content is 4 bytes"  "$(bytes "$X/test1")" "4"
here test3 && ck_eq "test3  : content is 1 byte"   "$(bytes "$X/test3")" "1"
here test4 && ck_eq "test4  : content is 2 bytes"  "$(bytes "$X/test4")" "2"
# tidy up (some extracted members carry write-less perms, so restore first)
chmod -R u+rwx "$X" 2>/dev/null
rm -rf "$X"

ck_report
