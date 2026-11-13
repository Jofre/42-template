# ----------------------------------------------------------------- shell_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The verdict engine for every check-mode shell exercise. A check.sh that never
# reaches ck_report prints [FAIL] to the log and then exits with whatever its
# last command returned -- so the log says FAIL and Bazel says PASSED. Every
# live check script calls ck_report, which is exactly why this needed a test:
# the hole only opens when someone writes one that does not. Such a script is
# a broken harness (exit 2), whatever its last command returned: it was exit
# 1, a verdict, and the exercise's hints printed under it (V301).
ck_toy "$WORK/ck_ok.sh" 'ck "always true" true'
ck_toy "$WORK/ck_bad.sh" 'ck "always false" false'
printf '. "${SHELL_CHECK_LIB:?}"\nck "always true" true\n' > "$WORK/ck_noreport.sh"
printf '. "${SHELL_CHECK_LIB:?}"\nck "always false" false\n' > "$WORK/ck_noreport_red.sh"
printf '#!/bin/sh\n:\n' > "$WORK/gen_nop.sh"

want_green "shell_check: a check script whose checks all pass is green" -- \
	st check gen_nop.sh --check "$WORK/ck_ok.sh" --check-lib "$TOOLS/shell_check.sh"
want_red   "shell_check: one failing ck fails the exercise" -- \
	st check gen_nop.sh --check "$WORK/ck_bad.sh" --check-lib "$TOOLS/shell_check.sh"
want_broken "shell_check: passing checks but no ck_report is NOT a pass" \
	'without calling ck_report' -- \
	st check gen_nop.sh --check "$WORK/ck_noreport.sh" --check-lib "$TOOLS/shell_check.sh"
want_broken "shell_check: ...nor is a failing one, which is no verdict either" \
	'without calling ck_report' -- \
	st check gen_nop.sh --check "$WORK/ck_noreport_red.sh" --check-lib "$TOOLS/shell_check.sh"
want_green "shell_check: ...and neither prints the exercise's hints" -- \
	st_hintless st_ck ck_noreport_red.sh
want_green "shell_check: ...nor does the passing one" -- \
	st_hintless st_ck ck_noreport.sh

# ck_broken: the harness, not the turn-in, is at fault -- a reference that
# disagrees with the subject's own example. Exit 2 whatever NO_SKIP says, so
# nothing reads it as a verdict on the student's work.
ck_toy "$WORK/ck_broken.sh" 'ck "ran" true' 'ck_broken "the reference disagrees with the subject"'
want_broken "shell_check: ck_broken stops the check as a broken harness" \
	'BROKEN HARNESS: the reference disagrees with the subject' -- \
	ck_toy_run "$WORK/ck_broken.sh"
want_broken "shell_check: ...and NO_SKIP=1 does not make it a verdict" \
	'nothing was judged' -- ck_toy_run "$WORK/ck_broken.sh" NO_SKIP=1

# ck_detail: what a failure names under its line -- the student's own line,
# the input that was used. A line too long for the log (rl_excerpt's width,
# 300 bytes) is cut there and kept whole where Bazel keeps a test's outputs:
# an input a student has to paste back is no use cut.
mkdir -p "$WORK/ckd"
_long=$(awk 'BEGIN { for (i = 0; i < 40; i++) printf "0123456789" }')
ck_toy "$WORK/ckd/long.sh" 'ck "one" false' "ck_detail \"short line\" \"$_long\""
ck_toy "$WORK/ckd/short.sh" 'ck "one" false' 'ck_detail "short line" "another"'
ckd() {
	ck_toy_run "$WORK/ckd/$1" TEST_UNDECLARED_OUTPUTS_DIR="$WORK/ckd/out" \
		TEST_TARGET=//m/p:ex08_output
}
want_out   "shell_check: ck_detail cuts a long line in the log" \
	'[... line cut here, 100 more bytes]' -- ckd long.sh
want_out   "shell_check: ...and says where it is kept whole" \
	'full text in bazel-testlogs/m/p/ex08_output/test.outputs/check-detail-1.txt' -- ckd long.sh
want_green "shell_check: ...where it is, byte for byte" -- \
	sh -c 'printf "short line\n%s\n" "$1" | cmp -s - "$2"' _ "$_long" \
		"$WORK/ckd/out/check-detail-1.txt"
want_broken_none "shell_check: ...and short lines are not kept anywhere" 'full text in' -- \
	ckd short.sh
want_out   "shell_check: by hand there is nowhere, and it says so" \
	'only a run under bazel test keeps the full text' -- \
	ck_toy_run "$WORK/ckd/long.sh" -u TEST_UNDECLARED_OUTPUTS_DIR

# --redirect: a turn-in that opens one fixed path reads a fixture instead
# (Shell 01 ex07's /etc/passwd), through //tools:path_redirect.so, loaded
# into ck_run's runs and nothing else. An invented path here, one that
# exists on no machine, so what is read can only be the fixture. The arms:
# the run reads the fixture, the check's own commands read the real path,
# --no-redirect runs on the real path, the log names the fixture, and a
# library that does not take is said, as a skip, never passed over.
mkdir -p "$WORK/redir"
printf 'fixture line 1\nfixture line 2\n' > "$WORK/redir/fixture"
printf 'not a shared library\n' > "$WORK/redir/not-a-lib.so"
cat > "$WORK/redir/gen.sh" <<'GEN_REDIR'
#!/bin/sh
printf '%s\n' 'head -n 1 /nonexistent-selftest/data' 'echo note >&2' > prog.sh
GEN_REDIR
cat > "$WORK/redir/check.sh" <<'CK_REDIR'
. "${SHELL_CHECK_LIB:?}"
ck_require "prog.sh exists" test -f "$1"
raw=$(mktemp)
if ck_redirected; then
	ck_run "$raw" sh "$1"
	ck "the run read the fixture" grep -qx 'fixture line 1' "$raw"
	ck "the check's own commands read the real path" \
		sh -c '! cat /nonexistent-selftest/data' 2> /dev/null
	ck_run --no-redirect "$raw" sh "$1"
	ck "--no-redirect ran on the real path" test ! -s "$raw"
else
	ck_skipped "the fixture: ${CK_REDIRECT_BROKEN:-no redirect declared}"
fi
rm -f "$raw" "$raw.err"
ck_report
CK_REDIR
# redir NO_SKIP [OPTION...] -- st check over the toys above, prog.sh the
# turn-in: NO_SKIP 1 exports NO_SKIP=1, and 0 unsets it, whatever the
# sweep this runs in says.
redir() {
	(if [ "$1" = 1 ]; then NO_SKIP=1; export NO_SKIP; else unset NO_SKIP; fi
	shift
	st check redir/gen.sh --check "$WORK/redir/check.sh" \
		--check-lib "$TOOLS/shell_check.sh" --deliverable prog.sh "$@")
}
want_green "shell_test: --redirect, the run reads the fixture" -- \
	redir 1 --redirect "/nonexistent-selftest/data=$WORK/redir/fixture" \
		--redirect-lib "$TOOLS/path_redirect.so"
want_out   "shell_test: ...and the log says which file it was" \
	"(/nonexistent-selftest/data was $WORK/redir/fixture)" -- \
	redir 0 --redirect "/nonexistent-selftest/data=$WORK/redir/fixture" \
		--redirect-lib "$TOOLS/path_redirect.so"
want_green "shell_test: no --redirect: a check that needs one skips" -- redir 0
want_red   "shell_test: ...which NO_SKIP=1 turns red" -- redir 1
want_red   "shell_test: a library that does not take is a skip, not a pass" -- \
	redir 1 --redirect "/nonexistent-selftest/data=$WORK/redir/fixture" \
		--redirect-lib "$WORK/redir/not-a-lib.so"
want_out   "shell_test: ...saying the library did not take" 'did not take' -- \
	redir 0 --redirect "/nonexistent-selftest/data=$WORK/redir/fixture" \
		--redirect-lib "$WORK/redir/not-a-lib.so"
want_broken "shell_test: --redirect to a fixture that is not there is refused" \
	'the fixture for /nonexistent-selftest/data is not here' -- \
	redir 0 --redirect "/nonexistent-selftest/data=$WORK/redir/no-such-fixture" \
		--redirect-lib "$TOOLS/path_redirect.so"
want_broken "shell_test: --redirect from a relative path is refused" \
	'--redirect is FROM=PATH' -- \
	redir 0 --redirect "data=$WORK/redir/fixture" --redirect-lib "$TOOLS/path_redirect.so"
want_broken "shell_test: --redirect without its library is refused" \
	'--redirect needs --redirect-lib' -- \
	redir 0 --redirect "/nonexistent-selftest/data=$WORK/redir/fixture"
# A program built with _FILE_OFFSET_BITS=64 reaches glibc's freopen64 when
# its source says freopen (stdio.h renames the call), so the library takes
# that name too: an invented toy that freopens the path onto its standard
# input and prints the first line it reads.
printf '%s\n' '#include <stdio.h>' '' 'int	main(void)' '{' '	char	line[64];' '' \
	'	if (freopen("/nonexistent-selftest/data", "r", stdin) == NULL' \
	'		|| fgets(line, sizeof(line), stdin) == NULL)' \
	'		return (puts("the path was not redirected"), 1);' \
	'	fputs(line, stdout);' '	return (0);' '}' > "$WORK/redir/freopen.c"
! st_mine || toy_cc "$WORK/redir/freopen" -D_FILE_OFFSET_BITS=64 "$WORK/redir/freopen.c"
redir_freopen() {  # the toy under the library, the path redirected
	CK_REDIRECT_FROM=/nonexistent-selftest/data CK_REDIRECT_TO="$WORK/redir/fixture" \
		LD_PRELOAD="$(cd "$TOOLS" && pwd)/path_redirect.so" "$WORK/redir/freopen"
}
want_out "path_redirect: a program built with _FILE_OFFSET_BITS=64 that freopens the path reads the fixture" \
	'fixture line 1' -- redir_freopen

# Shell 01 ex01's, ex08's, ex04's and ex07's check scripts, on stand-in
# oracles: what each does with the reference's answer, which no library arm
# can see. None of
# it answers any exercise: the programs print fixed words, and the oracles
# are shell scripts that print what an arm needs them to.
#
# ex01: whether the comma join was seen is read from the reference's lists,
# never from the program (finding 025). A user in one group, and a second in
# one, is a machine that cannot show it: a skip, red under NO_SKIP=1. A list
# of two, printed as its first name alone, is the mistake it exists to see.
mkdir -p "$WORK/ex01"
printf 'printf "%%s" g1\n' > "$WORK/ex01/print_groups.sh"
chmod +x "$WORK/ex01/print_groups.sh"
ex01_oracle() {
	# $1: what shell01_groups prints for every user; shell01_multigroup
	# names nobody.
	printf '%s\n' '#!/bin/sh' \
		"case \"\$1\" in shell01_groups) printf '%s' '$1' ;; *) exit 1 ;; esac" \
		> "$WORK/ex01/oracle"
	chmod +x "$WORK/ex01/oracle"
}
# Run from the program's folder, as shell_test.sh runs a check, so the
# library is named by its absolute path ($TOOLS is relative).
_ex01_lib=$(cd "$TOOLS" && pwd)/shell_check.sh
ex01() {
	( cd "$WORK/ex01" && env -u NO_SKIP ORACLE="$WORK/ex01/oracle" \
		SHELL_CHECK_LIB="$_ex01_lib" "$SH" \
		"$ROOT/c-piscine/c-piscine-shell-01/tests/ex01/check.sh" print_groups.sh )
}
ex01_noskip() {
	( cd "$WORK/ex01" && env NO_SKIP=1 ORACLE="$WORK/ex01/oracle" \
		SHELL_CHECK_LIB="$_ex01_lib" "$SH" \
		"$ROOT/c-piscine/c-piscine-shell-01/tests/ex01/check.sh" print_groups.sh )
}
ex01_oracle g1
want_out   "shell-01 ex01: one group each: the join is not seen, and it says so" \
	'cannot observe the comma join' -- ex01
want_red   "shell-01 ex01: ...a skip NO_SKIP=1 turns red" -- ex01_noskip
ex01_oracle g1,g2
want_red   "shell-01 ex01: two groups, the first printed alone, fails" -- ex01
want_broken_none "shell-01 ex01: ...and the join is not called unobservable" \
	'cannot observe the comma join' -- ex01
# The current user in one group, and the user database holding another in
# two: shell01_multigroup names that user ('multi', in d1 and d2), and the
# check drives it, ahead of the fixed candidates (none of which exists
# here). A program that prints the primary group alone passed while the
# check tried only the fixed candidates (finding 025).
printf '%s\n' '#!/bin/sh' \
	'case "$1" in' \
	"	shell01_groups) case \"\$2\" in multi) printf %s d1,d2 ;; $(id -un)) printf %s g1 ;; *) exit 1 ;; esac ;;" \
	'	shell01_multigroup) printf %s multi ;;' \
	'	*) exit 1 ;;' \
	'esac' > "$WORK/ex01/oracle"
chmod +x "$WORK/ex01/oracle"
printf '%s\n' 'case "$FT_USER" in multi) printf %s d1 ;; *) printf %s g1 ;; esac' \
	> "$WORK/ex01/print_groups.sh"
want_red   "shell-01 ex01: a user in two groups is driven, and the first alone fails" -- ex01
want_out   "shell-01 ex01: ...on the line for that user" \
	"[FAIL] reads \$FT_USER: a different user yields THAT user's groups (tried 'multi')" -- ex01
want_broken_none "shell-01 ex01: ...and the join is not called unobservable" \
	'cannot observe the comma join' -- ex01
printf '%s\n' 'case "$FT_USER" in multi) printf %s d1,d2 ;; *) printf %s g1 ;; esac' \
	> "$WORK/ex01/print_groups.sh"
want_green "shell-01 ex01: ...and both groups joined by a comma pass" -- ex01
# The reference for the current user failing, or answering nothing, leaves
# nothing to compare with: the harness's fault (exit 2), never a FAIL on the
# program, which a reference that printed nothing once got.
printf '%s\n' '#!/bin/sh' 'exit 1' > "$WORK/ex01/oracle"
want_broken "shell-01 ex01: a reference that fails for the current user judges nothing" \
	"the reference could not list the current user's groups" -- ex01
printf '%s\n' '#!/bin/sh' 'exit 0' > "$WORK/ex01/oracle"
want_broken "shell-01 ex01: ...nor one that answers nothing" \
	"the reference could not list the current user's groups" -- ex01
# A machine with no name for the current user (id -un prints nothing: a
# uid with no passwd entry, as a container can run under) cannot drive the
# program for that user: a host condition, a skip, and never a FAIL.
mkdir -p "$WORK/ex01/noname"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$WORK/ex01/noname/id"
chmod +x "$WORK/ex01/noname/id"
# A user with no name is unknown to the reference, as to the real one.
printf '%s\n' '#!/bin/sh' \
	'case "$1" in shell01_groups) [ -n "$2" ] || exit 1; printf %s g1 ;; *) exit 1 ;; esac' \
	> "$WORK/ex01/oracle"
ex01_noname() {
	( cd "$WORK/ex01" && env -u NO_SKIP PATH="$WORK/ex01/noname:$PATH" \
		ORACLE="$WORK/ex01/oracle" SHELL_CHECK_LIB="$_ex01_lib" "$SH" \
		"$ROOT/c-piscine/c-piscine-shell-01/tests/ex01/check.sh" print_groups.sh )
}
want_out "shell-01 ex01: no name for the current user is a skip" \
	'this machine has no name for the current user' -- ex01_noname
want_broken_none "shell-01 ex01: ...and no FAIL" '[FAIL]' -- ex01_noname

# ex08: the reference has to reproduce the subject's two printed examples
# before it judges anything; one that does not is a broken harness (exit 2),
# never a wrong answer charged to the student.
mkdir -p "$WORK/ex08"
printf 'printf "g\\n"\n' > "$WORK/ex08/add_chelou.sh"
printf '%s\n' '#!/bin/sh' 'printf "wrong\n"' > "$WORK/ex08/oracle"
chmod +x "$WORK/ex08/oracle"
want_broken "shell-01 ex08: a reference that disagrees with the subject judges nothing" \
	"the reference does not reproduce the subject's two examples" -- \
	env -u NO_SKIP ORACLE="$WORK/ex08/oracle" SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
		"$SH" "$ROOT/c-piscine/c-piscine-shell-01/tests/ex08/check.sh" "$WORK/ex08/add_chelou.sh"

# ex05: the check finds the one file it judges by a glob, and judges it by
# that name as it is. Found through ls, an exported QUOTING_STYLE handed it
# the name quoted and escaped, and every line after the name's failed on a
# file it could not open. The toy file's invented name holds a quote and a
# backslash, which every quoting style but the literal one escapes; it is
# not the subject's name, so its own line fails and the others are asked.
mkdir -p "$WORK/ex05"
_ex05_f="$WORK/ex05/x'y\\MaRV"
printf '42' > "$_ex05_f"
chmod 614 "$_ex05_f"
ex05_quoted() {
	env -u NO_SKIP QUOTING_STYLE=shell-escape TMPDIR="$WORK/exck/tmp" \
		SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
		"$SH" "$ROOT/c-piscine/c-piscine-shell-01/tests/ex05/check.sh" "$WORK/ex05"
}
want_out "shell-01 ex05: under an exported QUOTING_STYLE the file is read by its own name" \
	'[PASS] permissions are -rw---xr-- (614)' -- once ex05_quoted
want_out "shell-01 ex05: ...its bytes too" \
	'[PASS] content is byte-for-byte exactly the 2 bytes 42' -- once ex05_quoted

# ex04 (MAC.sh, and Reloaded ex04, which reads the same files): a refused
# output names the student's OWN lines the reference refused, and no other
# (finding 029: a bare FAIL, and a hint about another mistake). The stand-in
# machine has one hardware address, 02:00:00:00:00:01 ($EX04_HW, empty for a
# machine with none), and the loopback's all-zero one, which only --loopback
# (basic's reading) counts, and only beside a hardware address. It answers in
# the real reference's order: a line that is not one of the few it knows
# fails the format first (1), a machine with no hardware address is 4 after
# that, a line that is no one's 3, and the loopback's line alone 5. No text
# pattern: one that recognises a MAC address is a piece of an answer. A
# program printing fixed lines stands in for MAC.sh.
mkdir -p "$WORK/ex04"
cat > "$WORK/ex04/oracle" <<'EX04_ORACLE'
#!/bin/sh
[ "$1" = shell01_hwaddr ] || exit 2
hw=${EX04_HW-02:00:00:00:00:01}
if [ "${2:-}" = --machine ]; then
	[ -n "$hw" ] && exit 0
	exit 4
fi
rc=0
own=0
while IFS= read -r l; do
	case "$l" in
		02:00:00:00:00:0[0-9] | 00:00:00:00:00:00 | ff:ff:ff:ff:ff:ff) ;;
		*) exit 1 ;;
	esac
	[ -n "$hw" ] || continue
	case "$l" in
		"$hw") own=1 ;;
		00:00:00:00:00:00) [ "${2:-}" = --loopback ] || rc=3 ;;
		*) rc=3 ;;
	esac
done
[ -n "$hw" ] || exit 4
[ "$rc" = 0 ] && [ "$own" = 0 ] && exit 5
exit "$rc"
EX04_ORACLE
chmod +x "$WORK/ex04/oracle"
ex04_prints() {
	printf 'printf "%s"\n' "$1" > "$WORK/ex04/MAC.sh"
}
# MAC_CHECK_IFCONFIG names an ifconfig for the scripts' first question (is
# there one?), so these arms run on any machine: MAC.sh here is a printf and
# never calls it.
ex04() {  # ex04 check.sh|literal.sh
	( cd "$WORK/ex04" && env -u NO_SKIP ORACLE="$WORK/ex04/oracle" \
		MAC_CHECK_IFCONFIG=/usr/sbin/ifconfig \
		SHELL_CHECK_LIB="$_ex01_lib" "$SH" \
		"$ROOT/c-piscine/c-piscine-shell-01/tests/ex04/$1" MAC.sh )
}
# ...on a machine with no hardware address.
ex04_nohw() {
	( EX04_HW=""; export EX04_HW; ex04 "$@" )
}
ex04_prints '02:00:00:00:00:01\\nff:ff:ff:ff:ff:ff\\n00:00:00:00:00:00\\n'
want_red   "shell-01 ex04 literal: the loopback's all-zero line fails the hardware reading" -- \
	ex04 literal.sh
want_out   "shell-01 ex04 literal: ...naming that line of the program's own" \
	"not a hardware interface's address: 00:00:00:00:00:00" -- ex04 literal.sh
want_out   "shell-01 ex04 literal: ...and the broadcast line" \
	"not a hardware interface's address: ff:ff:ff:ff:ff:ff" -- ex04 literal.sh
want_broken_none "shell-01 ex04 literal: ...and never a line it accepted" \
	"address: 02:00:00:00:00:01" -- ex04 literal.sh
want_red   "shell-01 ex04: a broadcast line fails" -- ex04 check.sh
want_out   "shell-01 ex04: ...named as the program's own line" \
	"not one of this machine's interface addresses: ff:ff:ff:ff:ff:ff" -- ex04 check.sh
want_out   "shell-01 ex04: ...with a question about broadcast addresses" \
	"Is a broadcast address any one interface's own address?" -- ex04 check.sh
want_broken_none "shell-01 ex04: ...and neither the loopback's line nor a good one is refused" \
	"addresses: 0" -- ex04 check.sh
ex04_prints '02:00:00:00:00:01\\n00:00:00:00:00:00\\n'
want_green "shell-01 ex04: the loopback's line is one reading of the subject, and passes basic" -- \
	ex04 check.sh
ex04_prints '02:00:00:00:00:01\\n02:00:00:00:00:09\\n'
want_broken_none "shell-01 ex04: ...and the question is asked only of a broadcast line" \
	"Is a broadcast address" -- ex04 check.sh
# The loopback's line ALONE is on every Linux machine: a MAC.sh that
# printed it as a constant passed basic everywhere. Beside a hardware
# address it is one reading; instead of one, it is none.
ex04_prints '00:00:00:00:00:00\\n'
want_red   "shell-01 ex04: the loopback's line alone fails" -- ex04 check.sh
want_out   "shell-01 ex04: ...on the line that asks for a hardware address" \
	"[FAIL] at least one address printed is a hardware interface's" -- ex04 check.sh
want_broken_none "shell-01 ex04: ...and is not called some other machine's" \
	"not one of this machine's interface addresses" -- ex04 check.sh
# A machine with no hardware address: a correct MAC.sh prints nothing
# there. literal.sh never asked the machine, and the empty output failed
# its format test: a correct answer red at strict. Both skip it now,
# before the run.
ex04_prints ''
want_green "shell-01 ex04 literal: no hardware address here skips, never fails" -- \
	ex04_nohw literal.sh
want_out   "shell-01 ex04 literal: ...and says why" \
	"this machine publishes no hardware address" -- ex04_nohw literal.sh
want_green "shell-01 ex04: ...as check.sh does" -- ex04_nohw check.sh

# ex07: how the check maps the reference's words to its lines. The stand-in
# reference says one word, on every judging call, and the line that word
# belongs to has to be the only one that fails: a word misspelt in the check
# would pass every output. `c-order` on the whole list must send the windows
# to --order c. The program prints invented names, as many as the range asks
# for; the runs read an invented file through the real preload library.
mkdir -p "$WORK/ex07"
cat > "$WORK/ex07/oracle" <<'EX07_ORACLE'
#!/bin/sh
[ "$1" = shell01_rdwssap ] || exit 2
shift
printf '%s\n' "$*" >> "$EX07_LOG"
case "$1" in
	reaches)
		[ "${EX07_REACHES:-1}" -lt 2 ] || echo 'stand-in: no passwd it could read' >&2
		exit "${EX07_REACHES:-1}" ;;
	orders) exit "${EX07_ORDERS:-0}" ;;
	collates) exit "${EX07_COLLATES:-0}" ;;
	shows)
		[ -n "${EX07_SHOWS:-}" ] || exit 0
		printf '%s\n' "$EX07_SHOWS"
		exit 1 ;;
esac
cat > /dev/null
# A judging call without --passwd is about this machine's own file.
case " $* " in
	*" --passwd "*) printf '%s\n' "${EX07_SAYS:-}" ;;
	*) printf '%s\n' "${EX07_HOST_SAYS:-}" ;;
esac
EX07_ORACLE
chmod +x "$WORK/ex07/oracle"
printf 'n1:x:1:1::/:/bin/sh\n' > "$WORK/ex07/passwd"
ex07_names() {
	printf '%s\n' 'i=$FT_LINE1; s=""' \
		'while [ "$i" -le "$FT_LINE2" ] && [ "$i" -le 20 ]; do s="$s${s:+, }n$i"; i=$((i + 1)); done' \
		'printf "%s." "$s"' > "$WORK/ex07/r_dwssap.sh"
	chmod +x "$WORK/ex07/r_dwssap.sh"
}
_ex07_redir=$(cd "$TOOLS" && pwd)/path_redirect.so
# _e7_host, when set, is what the reference says of this machine's own file
# (otherwise WORDS), and _e7_reaches 0 says that file has logins enough to
# judge (otherwise it has not, and its run is skipped). _e7_coll 1 says the
# test locale collates as bytes do (otherwise it does not), _e7_shows is the
# steps the fixture no longer shows (otherwise none), and _e7_orders 1 says
# the two orders agree on it (otherwise they differ).
ex07() {  # ex07 WORDS check.sh|literal.sh
	: > "$WORK/ex07/log"
	( cd "$WORK/ex07" && env -u NO_SKIP ORACLE="$WORK/ex07/oracle" \
		EX07_SAYS="$1" EX07_LOG="$WORK/ex07/log" EX07_REACHES="${_e7_reaches:-1}" \
		EX07_HOST_SAYS="${_e7_host-$1}" EX07_COLLATES="${_e7_coll:-0}" \
		EX07_SHOWS="${_e7_shows:-}" EX07_ORDERS="${_e7_orders:-0}" \
		CK_REDIRECT_LIB="$_ex07_redir" CK_REDIRECT_FROM=/nonexistent-selftest/passwd \
		CK_REDIRECT_TO="$WORK/ex07/passwd" CK_REDIRECT_NAME=passwd \
		SHELL_CHECK_LIB="$_ex01_lib" "$SH" \
		"$ROOT/c-piscine/c-piscine-shell-01/tests/ex07/$2" r_dwssap.sh )
}
# ex07_fails_only WORD LABEL: with the reference saying WORD, something
# fails, and every line that fails is LABEL's. Each helper here returns 2
# when the check did (ex07_refusing, below).
ex07_fails_only() {
	_e7=$(ex07 "$1" check.sh 2>&1)
	[ "$?" -lt 2 ] || return 2
	_e7f=$(printf '%s\n' "$_e7" | grep -F '[FAIL]')
	[ -n "$_e7f" ] || return 1
	! printf '%s\n' "$_e7f" | grep -vqF -- "$2"
}
# ex07_order WORDS WANT: with the reference saying WORDS on the whole list,
# both windows are judged with --order WANT.
ex07_order() {
	ex07 "$1" check.sh > /dev/null 2>&1
	[ "$?" -lt 2 ] || return 2
	grep -qxF "2 4 --order $2 --passwd $WORK/ex07/passwd" "$WORK/ex07/log" &&
		grep -qxF "7 15 --order $2 --passwd $WORK/ex07/passwd" "$WORK/ex07/log"
}
ex07_names
want_green "shell-01 ex07: the reference finding nothing passes" -- ex07 "" check.sh
want_green "shell-01 ex07: 'comments' fails the comments line, and only it" -- \
	ex07_fails_only comments "comments are removed"
want_green "shell-01 ex07: 'reversed' fails the reversal line, and only it" -- \
	ex07_fails_only reversed "each name is a login from the file, reversed"
want_green "shell-01 ex07: 'lines' fails the lines-kept line, and only it" -- \
	ex07_fails_only lines "the names are the ones the subject's steps keep"
want_green "shell-01 ex07: 'order' fails the order line, and only it" -- \
	ex07_fails_only order "the names are in reverse alphabetical order"
want_green "shell-01 ex07: 'window' fails the window lines, and only them" -- \
	ex07_fails_only window "is exactly entries"
want_green "shell-01 ex07: 'c-order' on the whole list is not a fault" -- \
	ex07 c-order check.sh
want_green "shell-01 ex07: ...and sends the windows to --order c" -- ex07_order c-order c
want_green "shell-01 ex07: ...which are held to the locale's without it" -- ex07_order "" locale
# An output with no names holds every property about names, vacuously: no
# comment printed, nothing out of order. Those lines used to PASS on it.
printf 'printf .\n' > "$WORK/ex07/r_dwssap.sh"
want_out   "shell-01 ex07: no names: says there were none to judge" \
	"[FAIL] prints at least one name" -- ex07 lines check.sh
want_broken_none "shell-01 ex07: ...and passes nothing about them" \
	"[PASS] comments are removed" -- ex07 lines check.sh
want_broken_none "shell-01 ex07: ...not the order either" \
	"[PASS] the names are in reverse alphabetical order" -- ex07 lines check.sh
want_broken_none "shell-01 ex07 literal: ...nor the locale's order" \
	"[PASS] the whole list is in reverse order" -- ex07 "" literal.sh
want_out   "shell-01 ex07 literal: ...saying there were no names" \
	"[FAIL] prints at least one name" -- ex07 "" literal.sh
# Names the invented file rejects and this machine's own file accepts: the
# program read the machine's file some other way than by the path the run
# redirects, and the log asks which file it read. Names both reject, or a
# machine whose file has too few logins to tell, ask nothing.
# ex07_which_after WORDS: the check line printed just above the question.
ex07_which_after() {
	_e7=$(ex07 "$1" check.sh 2>&1)
	[ "$?" -lt 2 ] || return 2
	printf '%s\n' "$_e7" | grep -B1 -F "These names are this machine" | head -1
}
ex07_names
_e7_reaches=0 _e7_host=""
want_out   "shell-01 ex07: names that are this machine's ask which file was read" \
	"which file did r_dwssap.sh read" -- ex07 reversed check.sh
want_out   "shell-01 ex07: ...under the reversal line, which still fails" \
	"[FAIL] each name is a login from the file, reversed" -- ex07 reversed check.sh
_e7_host=""
want_out   "shell-01 ex07: ...under the lines-kept line when only it fails" \
	"each once" -- ex07_which_after lines
_e7_host="reversed"
want_broken_none "shell-01 ex07: ...names both files reject ask nothing" \
	"which file did" -- ex07 reversed check.sh
_e7_reaches=0 _e7_host=""
want_broken_none "shell-01 ex07: ...nor names both files accept" \
	"which file did" -- ex07 "" check.sh
_e7_reaches=1 _e7_host=""
want_broken_none "shell-01 ex07: ...nor does a machine with too few logins to tell" \
	"which file did" -- ex07 reversed check.sh
unset _e7_reaches _e7_host
# A check that judged, printed its lines and then refused (exit 2) checked
# nothing the arms above may count: each helper between them and ex07
# returns 2 then, so want_green and want_out see the harness error.
# ex07_refusing stands a stub in for ex07 that does all three, and asks
# each helper for that 2.
ex07_refusing() (
	ex07() {
		printf '2 4 --order c --passwd %s\n7 15 --order c --passwd %s\n' \
			"$WORK/ex07/passwd" "$WORK/ex07/passwd" > "$WORK/ex07/log"
		printf '[FAIL] comments are removed\nThese names are this machine\n'
		return 2
	}
	ex07_fails_only comments "comments are removed"
	[ "$?" -eq 2 ] || exit 1
	ex07_order c-order c
	[ "$?" -eq 2 ] || exit 1
	ex07_which_after comments > /dev/null
	[ "$?" -eq 2 ] || exit 1
)
want_green "shell-01 ex07: a check that refuses fails these helpers" -- ex07_refusing
# A machine without the test locale collates as bytes do, and the fixture's
# two orders look alike there through no fault of the fixture's: the
# reference says so (collates), and that one property is a skip naming the
# locale, every other line still judged. A fixture that lost a step on a
# machine that has the locale is still the harness's fault (V245).
ex07_names
_e7_coll=1
want_green "shell-01 ex07: a locale that collates as bytes passes the rest" -- \
	ex07 "" check.sh
want_out   "shell-01 ex07: ...the two orders a skip naming the locale" \
	"is not installed, or collates as bytes do: locale -a" -- ex07 "" check.sh
want_out   "shell-01 ex07: ...the other lines still judged" \
	"[FAIL] each name is a login from the file, reversed" -- ex07 reversed check.sh
want_out   "shell-01 ex07 literal: ...its reading a skip, naming it too" \
	"is not installed, or collates as bytes do: locale -a" -- ex07 "" literal.sh
_e7_coll=0 _e7_shows=orders
want_broken "shell-01 ex07: a fixture that lost its two orders is refused" \
	"no longer shows every step (orders)" -- ex07 "" check.sh
_e7_shows="" _e7_orders=1
want_broken "shell-01 ex07 literal: ...and refused there too" \
	"no longer shows" -- ex07 "" literal.sh
# A reference that cannot say how the machine collates (exit 2) leaves
# nothing to judge either check by: the harness's fault, never a skip.
_e7_orders=0 _e7_coll=2
want_broken "shell-01 ex07: a reference that cannot say how this machine collates is refused" \
	"could not say how this machine collates" -- ex07 "" check.sh
want_broken "shell-01 ex07 literal: ...nor can literal.sh judge by it" \
	"could not say how this machine collates" -- ex07 "" literal.sh
unset _e7_coll _e7_shows _e7_orders
# Nor can one that cannot say whether this machine's own file keeps two
# logins (reaches, exit 2): it was read as a machine with too few, and the
# host run became that skip. Asked before the host run, and before names the
# invented file rejects are judged against this machine's file; the refusal
# shows the reference's own words.
ex07_names
_e7_reaches=2
want_broken "shell-01 ex07: a reference that cannot read this machine's file is refused" \
	'shell01_rdwssap reaches answered 2' -- ex07 "" check.sh
want_broken "shell-01 ex07: ...in the reference's own words" \
	'no passwd it could read' -- ex07 "" check.sh
want_broken_without "shell-01 ex07: ...before names are judged against that file" \
	'each name is a login from the file, reversed' -- ex07 reversed check.sh
unset _e7_reaches

