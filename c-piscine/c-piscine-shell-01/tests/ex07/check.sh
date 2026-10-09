#!/bin/sh
# ex07 — r_dwssap.sh: /etc/passwd through the subject's seven steps, printed as
# one line.
#
# WHAT THE PROGRAM READS. The subject fixes the input -- "the output of cat
# /etc/passwd" -- and a machine's own file hides most of the exercise: a
# laptop's has no comment line, so "Remove comments" is never exercised; its
# logins are plain lowercase words, so the two readings of "reverse
# alphabetical order" print the same list; and a small one is too short for
# the subject's own window, lines 7 to 15. The file cannot be replaced (that
# needs root), so the program is handed tests/ex07/passwd when it opens
# /etc/passwd: an invented file with comment lines -- two at the top, one in
# the middle, so the steps' order shows -- and logins whose reversed names
# sort differently by bytes and by the locale's collation. BUILD.bazel
# declares it (`redirect`), the runner proves it takes on this machine, and
# ck_run loads it into the program's runs and nothing else
# (tools/path_redirect.c). The last run is on the machine's own file, with no
# redirect: the same program has to hold there too.
#
# WHAT IT IS JUDGED AGAINST. //oracle's shell01_rdwssap computes the names
# the subject's steps keep from the file the program read, and answers, one
# property at a time, which of them an output breaks: a comment printed as a
# name, a name that is no login read backwards, a name from a line the steps
# drop (or, over the whole range, one missing), names out of reverse order,
# a range that is not exactly those entries. The check prints PASS or FAIL
# for each and never the expected line (finding 026).
#
# THE COLLATION. "Reverse alphabetical order" names none, and the grader's
# locale is not known, so both readings pass here: bytes (the C locale), and
# the collation of the locale this test runs in (LC_ALL=en_US.UTF-8, set in
# .bazelrc). Each window is then held to the order the full list followed.
# ex07_literal, at strict, requires the locale's (literal.sh says why).
#
# THE TERMINATOR. The subject's example ends "...revressta_.$>": the prompt is
# glued onto the final '.', so there is NO trailing newline, and the Moulinette
# compares stdout byte for byte. A $(...) capture strips it, so the raw bytes
# are checked for it.
#
# THE PATH. A program that reads the file other than by opening /etc/passwd
# by that name is not handed the invented one, and its names fail on runs it
# read the machine's file for. Where the invented file rejects them and the
# machine's own accepts them, the log asks, under the first line that failed,
# which file the program read (WHICH FILE IT READ, below).
#
# THE RANGE. "Keep only logins between FT_LINE1 and FT_LINE2 (inclusive)" is
# asked at 1..999 (more lines than any file: the whole list), 2..4 and 7..15
# (the subject's own). A range anchored at line 1 is the one place where
# several readings of the two bounds agree, and 1..3 alone once let a program
# that misread them score 7/7.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-r_dwssap.sh}
printf "  CHECK: %s\n" "$D"

ck_require "r_dwssap.sh exists" test -f "$D"
ck "r_dwssap.sh is readable" test -r "$D"
# The subject's example runs it as ./r_dwssap.sh, so its execute bit is required
# (docs/reference.md, "Run contract").
ck_executable "$D"
# The subject: shell exercises must be executable with /bin/sh.
ck_sh_parses "$D"

ORACLE=${ORACLE:?this check needs //oracle: declare the exercise with oracle = True}

raw=$(mktemp)

# judge FIRST LAST [ARG...] -> the words shell01_rdwssap prints for the output
# in $raw, into $V. The words stay here: none of them is printed.
judge() {
	V=$("$ORACLE" shell01_rdwssap "$@" < "$raw") ||
		{ rm -f "$raw" "$raw.err"; ck_broken "the reference could not judge this output"; }
}
# lacks WORD... -> whether $V holds none of the WORDs.
lacks() {
	for _w do
		case " $V " in *" $_w "*) return 1 ;; esac
	done
	return 0
}
# names FILE -> how many names the output in FILE lists: its pieces between
# commas, the final '.' left out. With the shell's own expansions, so it
# shows nothing about which tools build the list.
names() {
	_s=$(cat "$1")
	_s=${_s%.}
	[ -n "$_s" ] || { echo 0; return; }
	_n=1
	while :; do
		case "$_s" in
			*,*) _s=${_s#*,}; _n=$((_n + 1)) ;;
			*) break ;;
		esac
	done
	echo "$_n"
}
# which_file -> under the line above, when the names the invented file
# rejects are the ones this machine's own file accepts ($HOST_READ), the
# question of which file the run read.
which_file() {
	[ "${HOST_READ:-0}" = 1 ] || return 0
	ck_detail \
		"These names are this machine's own logins, not the invented file's, and the run" \
		"was handed the invented file only where it opens $CK_REDIRECT_FROM by that path:" \
		"which file did $(ck_quote "${D##*/}") read, and how does it reach it?"
}
# shape -> the checks on the form of the line in $raw, whatever it lists.
shape() {
	out=$(cat "$raw")
	ck "produces output" test -n "$out"
	ck_no_final_newline "ends exactly at the final '.' -- no trailing newline" "$raw"
	# Seen only in output that exists: no output has no newline in it either.
	ck "output is a single line (no embedded newlines)" \
		sh -c '[ -n "$1" ] && test "$(printf "%s" "$1" | wc -l | tr -d " ")" -eq 0' _ "$out"
	ck "output ends with a period" \
		sh -c 'case "$1" in *.) exit 0;; *) exit 1;; esac' _ "$out"
	ck "output is a ', '-joined list ending in a period" \
		sh -c 'printf "%s\n" "$1" | grep -qE "^([^ ,]+, )*[^ ,]+\.\$"' _ "$out"
}

# ---- on the fixture ------------------------------------------------------------
if ck_redirected; then
	printf '  /etc/passwd, for every run but the last, is %s:\n' "$CK_REDIRECT_NAME"
	printf '  invented logins, and comment lines, so that every step shows.\n'
	F=$CK_REDIRECT_TO
	# The fixture shows every step only while it keeps what it is for: a
	# comment line first and one between logins, at least 15 names for the
	# subject's window, and names whose byte order and the locale's differ.
	# One edited away and every program that skips that step would pass, so
	# the reference is asked first, and a fixture that lost one is the
	# harness's fault, never the program's.
	_misses=$("$ORACLE" shell01_rdwssap shows --passwd "$F")
	case $? in
		0) ;;
		1) rm -f "$raw"; ck_broken "the fixture $CK_REDIRECT_NAME no longer shows every step ($_misses)" ;;
		*) rm -f "$raw"; ck_broken "the reference could not read the fixture $CK_REDIRECT_NAME" ;;
	esac

	ck_run "$raw" env FT_LINE1=1 FT_LINE2=999 sh "$D"
	shape
	judge 1 999 --passwd "$F"
	# Three of these are about the names printed, and of an output that
	# prints none they hold of nothing: no comment printed, no name that is
	# not reversed, nothing out of order. A PASS says what held, so they are
	# judged only of names; with none, one line says there were none to
	# judge. The fourth asks for the names the steps keep, and fails on its
	# own when they are missing.
	n=$(names "$raw")
	if [ "$n" -gt 0 ]; then
		# WHICH FILE IT READ. The run is handed the invented file only where
		# it opens /etc/passwd by that path. A program that reaches the
		# machine's file some other way -- another spelling of the path,
		# another tool -- prints this machine's logins, and every line below
		# about names failed it as if its names were wrong. So names the
		# invented file rejects are judged against this machine's file too,
		# and when that one accepts them, the log asks which file was read.
		# A question: the subject names `cat /etc/passwd`, and this settles
		# nothing it leaves open.
		HOST_READ=0
		if ! lacks reversed lines && "$ORACLE" shell01_rdwssap reaches 2 2> /dev/null; then
			_fx=$V
			judge 1 999
			lacks reversed lines && HOST_READ=1
			V=$_fx
		fi
		ck "comments are removed: no comment line is printed as a name" lacks comments
		ck "each name is a login from the file, reversed" lacks reversed
		# Said once, under the first of the two lines that failed them.
		lacks reversed || which_file
		ck "the names are the ones the subject's steps keep, each once" lacks lines
		lacks reversed && ! lacks lines && which_file
		ck "the names are in reverse alphabetical order" lacks order
	else
		ck "prints at least one name, for comments, reversal and order to be judged on" \
			test "$n" -gt 0
		ck "the names are the ones the subject's steps keep, each once" lacks lines
	fi
	# The order the whole list followed is the one each window is held to.
	ORDER="locale"
	if ! lacks c-order; then
		ORDER="c"
	fi

	for w in "2 4" "7 15"; do
		l1=${w% *}
		l2=${w#* }
		ck_run "$raw" env FT_LINE1="$l1" FT_LINE2="$l2" sh "$D"
		# Count first: it gives the clearest failure message. "inclusive"
		# means the window holds L2 - L1 + 1 entries, which is the spec.
		ck_eq "range $l1..$l2 keeps exactly ($l2 - $l1 + 1) logins" "$(names "$raw")" "$((l2 - l1 + 1))"
		judge "$l1" "$l2" --order "$ORDER" --passwd "$F"
		ck "range $l1..$l2 is exactly entries $l1 through $l2 of the whole list" lacks window
	done
else
	# The runs read this machine's file, which shows none of these.
	for p in "comments are removed" "the names are the ones the subject's steps keep" \
		"the names are in reverse alphabetical order" "ranges 2..4 and 7..15"; do
		ck_skipped "$p: ${CK_REDIRECT_BROKEN:-no fixture passwd is declared for this exercise}"
	done
fi

# ---- on this machine's own /etc/passwd ------------------------------------------
# The same program on the real file: a program that printed the fixture's
# names from memory would pass everything above. Asked of the file before the
# program runs; a machine with fewer than two logins to keep has nothing to
# show.
if "$ORACLE" shell01_rdwssap reaches 2 2> /dev/null; then
	ck_run --no-redirect "$raw" env FT_LINE1=1 FT_LINE2=999 sh "$D"
	ck_redirected || shape
	judge 1 999
	ck "on this machine's own /etc/passwd too: its logins, reversed, from the lines kept, in order" \
		lacks comments reversed lines order
else
	ck_skipped "this machine's /etc/passwd keeps fewer than two logins, so there is no list to judge on it"
fi

rm -f "$raw" "$raw.err"
ck_report
