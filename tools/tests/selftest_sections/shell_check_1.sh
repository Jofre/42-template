# ---------------------------------------------------------------- shell_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# THE TOY CHECK SCRIPT: the library sourced, a body, then ck_report, the
# shape of every live check.sh. ck_toy writes one and ck_toy_run runs it,
# for this section, shell_test's and this section's second file, so the
# shell a toy runs under is chosen in one place: "$SH", which
# //tools/tests:selftest_bash replays under bash (tools/conventions.sh
# reports a toy run with a plain sh). Plain code, so every shard has them,
# and they name no tree of their own: the caller's FILE is read in its
# section. A script of another shape (no ck_report, or two) is written
# by hand, and a run with a library of its own launched by hand.
#
# ck_toy FILE LINE... -- FILE, each LINE its body.
ck_toy() {
	_ckt_f=$1
	shift
	printf '%s\n' '. "${SHELL_CHECK_LIB:?}"' "$@" 'ck_report' > "$_ckt_f"
}
# ck_toy_run FILE [ENV-ARG...] -- FILE run under "$SH" with the tree's
# library and NO_SKIP unset. Each ENV-ARG is env's, its -u NAME options
# before its NAME=VALUE ones: an arm that wants NO_SKIP=1 passes it.
ck_toy_run() {
	_ckt_f=$1
	shift
	env -u NO_SKIP "$@" SHELL_CHECK_LIB="$TOOLS/shell_check.sh" "$SH" "$_ckt_f"
}

# ck_skip: the one exercise whose answer is defined by a resource 42 issues and
# this repo does not redistribute (shell-00 ex07). On a fresh clone there is
# nothing to check against -- which is neither a pass nor the student's failure,
# and the difference has to survive, because a skip that reads as a pass is the
# defect class this whole file exists for.
mkdir -p "$WORK/ckskip"
ck_toy "$WORK/ckskip/check.sh" 'ck_skip "no fixture here"' 'ck "unreachable" true'
want_green "shell_check: ck_skip is a skip, not a failure" -- \
	ck_toy_run "$WORK/ckskip/check.sh"
want_red "shell_check: and NO_SKIP=1 turns it red" -- \
	ck_toy_run "$WORK/ckskip/check.sh" NO_SKIP=1
want_out "shell_check: a skip says it checked nothing" 'nothing was checked' -- \
	ck_toy_run "$WORK/ckskip/check.sh"

# A library with no tools/runner_lib.sh to render with is wiring, exit 2:
# ck_eq rendered its values in a subshell of its own, so the exit 2 meant
# for that ended the subshell alone, and the check went on to print a FAIL
# with two empty values and blame the turn-in (exit 1).
mkdir -p "$WORK/cklone"
cp "$TOOLS/shell_check.sh" "$WORK/cklone/"
ck_toy "$WORK/cklone/check.sh" 'ck_eq value a b'
want_broken "shell_check: ck_eq with no runner_lib.sh to show its values is wiring" \
	'tools/runner_lib.sh is not beside it' -- \
	env -u TEST_SRCDIR SHELL_CHECK_LIB="$WORK/cklone/shell_check.sh" "$SH" "$WORK/cklone/check.sh"
want_broken_without "shell_check: ...and no FAIL line on the turn-in" '[FAIL]' -- \
	env -u TEST_SRCDIR SHELL_CHECK_LIB="$WORK/cklone/shell_check.sh" "$SH" "$WORK/cklone/check.sh"
# ...and so is one that only quotes a word for a replay line. ck_quote runs
# in its caller's $(...), where that exit 2 ended the subshell alone: the
# word came back empty, and the check went on to a verdict, a PASS when
# nothing read the word and a FAIL when something did. So the library stops
# where it is sourced, in the check script's own shell.
ck_toy "$WORK/cklone/quote.sh" 'q=$(ck_quote "a b")' 'ck x true'
ck_toy "$WORK/cklone/quoted.sh" 'q=$(ck_quote "a b")' \
	'ck "the quoted word is not empty" test -n "$q"'
want_broken "shell_check: ck_quote with no runner_lib.sh is wiring too" \
	'tools/runner_lib.sh is not beside it' -- \
	env -u TEST_SRCDIR SHELL_CHECK_LIB="$WORK/cklone/shell_check.sh" "$SH" "$WORK/cklone/quote.sh"
want_broken_without "shell_check: ...with no RESULT line" 'RESULT:' -- \
	env -u TEST_SRCDIR SHELL_CHECK_LIB="$WORK/cklone/shell_check.sh" "$SH" "$WORK/cklone/quote.sh"
want_broken_without "shell_check: ...nor a FAIL over the word it did not quote" '[FAIL]' -- \
	env -u TEST_SRCDIR SHELL_CHECK_LIB="$WORK/cklone/shell_check.sh" "$SH" "$WORK/cklone/quoted.sh"
# ...and so is a PATH without a tool the library takes: it probes them when
# it is sourced. It probed none, and with no tail ck_no_final_newline read
# the last byte of an output that ends in a newline as nothing, and passed.
# The PATH holds what shell_test.sh and runner_lib.sh take, and all the
# library takes but tail.
mkdir -p "$WORK/ck_notail" "$WORK/cknotail"
for _t in sh "$SH" awk cat chmod cmp cp cut date dirname env grep head ls mkdir mktemp od readlink rm sed sort tr; do
	ln -sf "$(command -v "$_t")" "$WORK/ck_notail/$_t" 2> /dev/null
done
printf '#!/bin/sh\nprintf "hello\\n" > out.txt\n' > "$WORK/cknotail/gen.sh"
ck_toy "$WORK/cknotail/check.sh" 'ck_require "out.txt exists" test -f out.txt' \
	'ck_no_final_newline "out.txt has no final newline" out.txt'
want_broken "shell_check: a PATH without tail stops the library, naming it" \
	"required command 'tail' is not on PATH" -- \
	env PATH="$WORK/ck_notail" "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/cknotail/gen.sh" \
		--mode check --check "$WORK/cknotail/check.sh" --check-lib "$TOOLS/shell_check.sh"
# ...and so is one without ls, which ck_executable reads the mode with: it
# read an empty mode and failed a file whose execute bit is set, with a hint
# to set it. The PATH holds all the arm above holds but ls, and tail.
mkdir -p "$WORK/ck_nols" "$WORK/cknols"
for _t in sh "$SH" awk cat chmod cmp cp cut date dirname env grep head mkdir mktemp od readlink rm sed sort tail tr; do
	ln -sf "$(command -v "$_t")" "$WORK/ck_nols/$_t" 2> /dev/null
done
printf '#!/bin/sh\nprintf "#!/bin/sh\\n" > run.sh\nchmod 755 run.sh\n' > "$WORK/cknols/gen.sh"
ck_toy "$WORK/cknols/check.sh" 'ck_require "run.sh exists" test -f run.sh' 'ck_executable run.sh'
want_broken "shell_check: a PATH without ls stops the library, naming it" \
	"required command 'ls' is not on PATH" -- \
	env PATH="$WORK/ck_nols" "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/cknols/gen.sh" \
		--mode check --check "$WORK/cknols/check.sh" --check-lib "$TOOLS/shell_check.sh"
want_broken_without "shell_check: ...and no FAIL line on a file with the bit" '[FAIL]' -- \
	env PATH="$WORK/ck_nols" "$SH" "$TOOLS/shell_test.sh" --generator "$WORK/cknols/gen.sh" \
		--mode check --check "$WORK/cknols/check.sh" --check-lib "$TOOLS/shell_check.sh"

# ck_listed_at: a subject's `ls -l` timestamp. The date is judged in any year,
# the time only while ls -l would still show it -- within six months, not in the
# future -- since the subjects accept the year in its place. Dated from TODAY so
# no arm goes stale: one written against a fixed year is exactly the bug this
# helper replaced (a check pinned to 2026 that fails a correct archive in 2027).
mkdir -p "$WORK/cklisted"
ckl() {
	ck_toy "$WORK/cklisted/check.sh" "ck_listed_at item \"$1\" $2 $3"
	ck_toy_run "$WORK/cklisted/check.sh"
}
_md=$(date +%m-%d)
want_green "shell_check: ck_listed_at, today at the listed time" -- \
	ckl "$(date +%Y)-$_md 12:34" "$_md" 12:34
want_red   "shell_check: ck_listed_at, today at another time" -- \
	ckl "$(date +%Y)-$_md 12:35" "$_md" 12:34
want_green "shell_check: ck_listed_at, a year ago: the time is not shown" -- \
	ckl "$(( $(date +%Y) - 1 ))-$_md 00:00" "$_md" 12:34
want_green "shell_check: ck_listed_at, a future year: nor is it here" -- \
	ckl "$(( $(date +%Y) + 1 ))-$_md 00:00" "$_md" 12:34
want_red   "shell_check: ck_listed_at, any year, the wrong day" -- \
	ckl "$(( $(date +%Y) - 1 ))-$_md 12:34" 13-45 12:34
# A stamp that is no date at all -- the member was not in the archive -- is one
# failure. It was read as the year 0, "more than six months ago", so it also
# scored a PASS saying the time was not graded because ls -l shows the year:
# seven such passes on an empty archive, each about a date that did not exist.
want_red   "shell_check: ck_listed_at, no date to read" -- \
	ckl " " "$_md" 12:34
want_broken_none "shell_check: ...and no 'time not graded' pass for it" \
	'time not graded' -- ckl " " "$_md" 12:34
# A stamp that is there but is not a date -- month 13, a time with seconds --
# is the same one failure, shown as it came rather than blamed on a missing
# member; and a year with leading zeros is a year, not broken octal.
want_red   "shell_check: ck_listed_at, a stamp that is no date" -- \
	ckl "$(date +%Y)-13-01 12:34" "$_md" 12:34
want_out   "shell_check: ...shown as it came" "got '$(date +%Y)-13-01 12:34'" -- \
	ckl "$(date +%Y)-13-01 12:34" "$_md" 12:34
# ...through the one renderer: the stamp is a field of tar's listing, and
# a member's owner name, printed raw there, can shift the fields and carry
# a terminal's escape bytes into it. It was printed raw into the log.
_ckl_esc=$(printf 'a\033[31mb\tc')
want_out   "shell_check: ...a control byte in it as \\xHH" "got 'a\\x1b[31mb\\tc'" -- \
	ckl "$_ckl_esc" "$_md" 12:34
want_out   "shell_check: ...with the key to those marks under the checklist" \
	'(byte for byte: \t a tab, and \xHH' -- ckl "$_ckl_esc" "$_md" 12:34
want_broken_none "shell_check: ...and no escape byte in the log" "$(printf '\033')" -- \
	ckl "$_ckl_esc" "$_md" 12:34
want_broken_none "shell_check: ...nor a raw tab" "$(printf '\t')" -- \
	ckl "$_ckl_esc" "$_md" 12:34
want_broken_none "shell_check: ...and no 'time not graded' pass for it either" \
	'time not graded' -- ckl "$(date +%Y)-$_md 12:34:56" "$_md" 12:34
want_green "shell_check: ck_listed_at, the year 0999 is read as a number" -- \
	ckl "0999-$_md 00:00" "$_md" 12:34
# Whether ls -l shows the time is a matter of days -- six months, about
# 182 -- and the check counted calendar months, so its answer turned on the
# day it ran: a date 154 days old counted as six months, and its time went
# ungraded under a claim that ls shows the year; a later day of this month,
# in the future, counted as none, and its time was graded. So these run on
# fixed days, from a stand-in date on PATH (never the machine's today), and
# hold the days either side of six months: 181 graded, 182 and 183 not
# (ls may show either, by the hour), 184 not (it shows the year).
mkdir -p "$WORK/ckdate"
cat > "$WORK/ckdate/date" <<'CK_DATE'
#!/bin/sh
# A stand-in date: CKL_TODAY, YYYY-MM-DD, in the formats ck_listed_at asks.
case "$1" in
	+%Y-%m-%d) echo "$CKL_TODAY" ;;
	+%Y) echo "${CKL_TODAY%%-*}" ;;
	+%m) _m=${CKL_TODAY#*-}; echo "${_m%-*}" ;;
	*) echo "stand-in date: no format $*" >&2; exit 2 ;;
esac
CK_DATE
chmod +x "$WORK/ckdate/date"
ckl_on() {  # ckl_on TODAY STAMP MM-DD HH:MM -- ckl, on the day TODAY
	_clo=$1
	shift
	(PATH="$WORK/ckdate:$PATH" CKL_TODAY=$_clo; export PATH CKL_TODAY; ckl "$@")
}
want_red   "shell_check: ck_listed_at, 154 days old: its time is graded" -- \
	ckl_on 2026-10-01 "2026-04-30 12:35" 04-30 12:34
want_green "shell_check: ck_listed_at, later this month: in the future, it is not" -- \
	ckl_on 2026-10-01 "2026-10-20 12:35" 10-20 12:34
want_red   "shell_check: ck_listed_at, 181 days old: graded" -- \
	ckl_on 2026-10-01 "2026-04-03 12:35" 04-03 12:34
want_out   "shell_check: ck_listed_at, 182 days old: ls may show the year" \
	'ls -l may show the year' -- ckl_on 2026-10-01 "2026-04-02 12:35" 04-02 12:34
want_out   "shell_check: ck_listed_at, 183 days old: so may it" \
	'ls -l may show the year' -- ckl_on 2026-10-01 "2026-04-01 12:35" 04-01 12:34
want_out   "shell_check: ck_listed_at, 184 days old: ls shows the year" \
	'ls -l shows the year' -- ckl_on 2026-10-01 "2026-03-31 12:35" 03-31 12:34
want_red   "shell_check: ck_listed_at, 15 days old across a new year: graded" -- \
	ckl_on 2026-01-15 "2025-12-31 12:35" 12-31 12:34
# A today that is no date is wiring, exit 2, before anything is judged. The
# days were counted from it as from any text, so an empty one was read as
# the year 0 and the stamp as some two thousand years in the future, which
# passed with a line saying the time is not graded since ls -l shows the year.
want_broken "shell_check: ck_listed_at, a date that prints nothing" \
	"date +%Y-%m-%d printed" -- ckl_on "" "2026-04-02 12:35" 04-02 12:34
want_broken_without "shell_check: ...and no PASS line" '[PASS]' -- \
	ckl_on "" "2026-04-02 12:35" 04-02 12:34
want_broken "shell_check: ck_listed_at, a date that prints no date" \
	"date +%Y-%m-%d printed 'Fri Nov'" -- ckl_on "Fri Nov" "2026-04-02 12:35" 04-02 12:34
want_broken_without "shell_check: ...and no PASS line either" '[PASS]' -- \
	ckl_on "Fri Nov" "2026-04-02 12:35" 04-02 12:34

# ck_executable: the execute bit, for the exercises whose subject runs the file
# as ./name. It reads the mode of the file it is given -- in a real run, the
# copy the test's own generator run produced -- and says what to do inline,
# because the exercise's clue printed at the end is not about permissions.
mkdir -p "$WORK/ckexec"
printf '#!/bin/sh\n' > "$WORK/ckexec/run.sh"
printf '#!/bin/sh\n' > "$WORK/ckexec/plain.sh"
chmod 755 "$WORK/ckexec/run.sh"
chmod 644 "$WORK/ckexec/plain.sh"
ckx() {
	ck_toy "$WORK/ckexec/check.sh" "ck_executable \"$1\""
	ck_toy_run "$WORK/ckexec/check.sh"
}
want_green "shell_check: ck_executable, mode 755" -- ckx "$WORK/ckexec/run.sh"
want_red   "shell_check: ck_executable, mode 644" -- once ckx "$WORK/ckexec/plain.sh"
want_red   "shell_check: ck_executable, no file at all" -- once ckx "$WORK/ckexec/none.sh"
want_out   "shell_check: ck_executable says how to fix it" 'man chmod' -- \
	once ckx "$WORK/ckexec/plain.sh"
# ...in words of what the check does: the library is shared, and what a
# subject runs is the call site's to say, never a hint of the library's.
want_broken_none "shell_check: ...and makes no claim about a subject" 'the subject' -- \
	once ckx "$WORK/ckexec/plain.sh"
want_broken_none "shell_check: ...but not about a file that is not there" \
	'man chmod' -- once ckx "$WORK/ckexec/none.sh"

# ck_require: the turn-in, first. A check that went on after "x.sh exists"
# failed passed every check that asserts an absence, on the output of nothing:
# a stub scored four PASS lines of seven. The arms: a missing file is one FAIL
# and nothing after it runs; the RESULT line says why from what it found; a
# file that is there lets the rest run.
mkdir -p "$WORK/ckreq"
printf 'echo hi\n' > "$WORK/ckreq/there.sh"
ckq() {
	ck_toy "$WORK/ckreq/check.sh" "ck_require \"the file exists\" test $1 \"$2\"" \
		'ck "no spaces in the output" true'
	ck_toy_run "$WORK/ckreq/check.sh"
}
want_red   "shell_check: ck_require, no file is a failure" -- \
	once ckq -f "$WORK/ckreq/none.sh"
want_broken_none "shell_check: ...and nothing after it is checked" \
	'no spaces in the output' -- once ckq -f "$WORK/ckreq/none.sh"
want_out   "shell_check: ...and the RESULT line says why" \
	'the file does not exist; nothing else was checked' -- \
	once ckq -f "$WORK/ckreq/none.sh"
want_out   "shell_check: a failed requirement on a file that IS there" \
	'the check above failed; nothing else was checked' -- \
	ckq -d "$WORK/ckreq/there.sh"
want_green "shell_check: ck_require, the file is there: the rest runs" -- \
	once ckq -f "$WORK/ckreq/there.sh"
want_out   "shell_check: ...and is reported" '[PASS] no spaces in the output' -- \
	once ckq -f "$WORK/ckreq/there.sh"

# ck_run: the one way a check runs a turn-in. It judges nothing -- a correct
# output with a non-zero status and a line on stderr is still green, since no
# shell subject names an exit status -- and what it adds is the block above
# the checklist, which is what these arms pin. Every construct here fails, or
# writes, the same way under dash and bash, so the arms hold whichever shell
# /bin/sh is: an unclosed `if` is a syntax error in both (exit 2), and the
# message is prefixed with the script's path in both, which the block shows
# as the file's name alone.
mkdir -p "$WORK/ckrun"
printf 'echo hello\necho oops-on-stderr >&2\nexit 3\n' > "$WORK/ckrun/noisy.sh"
printf 'echo hello\n' > "$WORK/ckrun/quiet.sh"
printf 'echo hello\nif true; then\n' > "$WORK/ckrun/unclosed.sh"
printf 'printf "%%s" "$FT_X" >&2\n' > "$WORK/ckrun/env.sh"
ckr() {
	ck_toy "$WORK/ckrun/check.sh" "D=$WORK/ckrun/$1" 'raw=$(mktemp)' \
		'ck_require "it exists" test -f "$D"' \
		'ck_run "$raw" sh "$D"' \
		'ck_run "$raw" sh "$D"' \
		'ck "prints hello" grep -qx hello "$raw"'
	ck_toy_run "$WORK/ckrun/check.sh"
}
want_green "shell_check: ck_run, a status and stderr alone fail nothing" -- \
	once ckr noisy.sh
want_out   "shell_check: ...but the run is shown, and with which shell" \
	'ran: sh noisy.sh  (/bin/sh, not through its #! line)' -- once ckr noisy.sh
# A library every check sources quotes no subject: which shell ran the
# script is what it can say, never that a subject asks for that one.
want_broken_none "shell_check: ...never what a subject requires" \
	'subject' -- once ckr noisy.sh
want_out   "shell_check: ...with its exit status" 'exit status 3' -- once ckr noisy.sh
want_out   "shell_check: ...and what it wrote to stderr" 'oops-on-stderr' -- \
	once ckr noisy.sh
want_out   "shell_check: a repeat of the same run is one line" \
	'the same exit status and stderr as above' -- once ckr noisy.sh
want_broken_none "shell_check: a clean run adds nothing to the log" 'ran:' -- \
	ckr quiet.sh
want_out   "shell_check: a script that dies on a syntax error shows it" \
	'exit status 2' -- once ckr unclosed.sh
want_out   "shell_check: ...in the shell's words, under the file's name" \
	'unclosed.sh: ' -- once ckr unclosed.sh
want_broken_none "shell_check: ...and not under the check's scratch path" \
	"$WORK/ckrun/unclosed.sh" -- once ckr unclosed.sh
# The command is shown as it could be typed back: env assignments first, a
# value with a space in it quoted. And the environment reaches the script.
ck_toy "$WORK/ckrun/envcheck.sh" "D=$WORK/ckrun/env.sh" \
	'raw=$(mktemp)' \
	'ck_require "it exists" test -f "$D"' \
	'ck_run "$raw" env FT_X="a b" sh "$D"' \
	'ck "the variable reached it" grep -qx "a b" "$CK_ERR"'
want_green "shell_check: ck_run passes env assignments to the script" -- \
	ck_toy_run "$WORK/ckrun/envcheck.sh"
want_out   "shell_check: ...and shows them the way they would be typed" \
	"ran: FT_X='a b' sh env.sh" -- ck_toy_run "$WORK/ckrun/envcheck.sh"
# ckc 'CK_RUN LINE' ['CHECK LINE']: a check around one ck_run, on the
# scripts above, with $D, $raw and $DIR ready for the line to use.
mkdir -p "$WORK/ckrun/cdir"
printf 'pwd\n' > "$WORK/ckrun/pwd.sh"
printf 'kill -9 $$\n' > "$WORK/ckrun/sig.sh"
ckc() {
	ck_toy "$WORK/ckrun/one.sh" "D=$WORK/ckrun/$1" \
		"DIR=$WORK/ckrun/cdir" 'raw=$(mktemp)' "$2" "${3:-ck \"ran\" true}"
	ck_toy_run "$WORK/ckrun/one.sh"
}
# The shell's own idiom, FT_X=1 in front of the command with no `env`, used
# to be exec'd as a program: status 127, "FT_X=a b: not found", shown as the
# student's run. The assignment reaches the script now, shown as typed.
want_green "shell_check: ck_run, assignments with no env reach the script" -- \
	ckc env.sh 'ck_run "$raw" FT_X="a b" sh "$D"' 'ck "got it" grep -qx "a b" "$CK_ERR"'
want_out   "shell_check: ...and are shown as typed" "ran: FT_X='a b' sh env.sh" -- \
	ckc env.sh 'ck_run "$raw" FT_X="a b" sh "$D"'
# env with a flag is shown with env, and its sh is still /bin/sh -- env -i
# empties PATH, so a sh that were not mapped would not be found at all.
want_out   "shell_check: env with a flag is shown with env" \
	'ran: env -i FT_X=1 sh env.sh' -- \
	ckc env.sh 'ck_run "$raw" env -i FT_X=1 sh "$D"'
want_green "shell_check: ...and its sh is /bin/sh, found with no PATH" -- \
	ckc env.sh 'ck_run "$raw" env -i FT_X=1 sh "$D"' 'ck "ran" grep -qx 1 "$CK_ERR"'
# -C runs it from DIR: seven check scripts stage a tree there.
want_green "shell_check: ck_run -C runs the script from DIR" -- \
	ckc pwd.sh 'ck_run -C "$DIR" "$raw" sh "$D"' 'ck "in DIR" grep -qx "$DIR" "$raw"'
want_out   "shell_check: a run killed by a signal says which" \
	'killed by signal 9' -- \
	ckc sig.sh 'ck_run "$raw" sh "$D"'
# 255 is what `exit 255` (a C main's `return (-1);`) gives, and also what a
# shell reports for a death by signal 127: only waitpid() tells them apart, so
# the ending comes from tools/exit_status, and a plain return is never called
# a kill.
printf 'exit 255\n' > "$WORK/ckrun/ret255.sh"
want_out   "shell_check: exit 255 is a return, said as one" \
	'exit status 255' -- once ckc ret255.sh 'ck_run "$raw" sh "$D"'
want_broken_none "shell_check: ...and never called a kill" \
	'killed by signal' -- once ckc ret255.sh 'ck_run "$raw" sh "$D"'
# With -C the helper runs from DIR, so a report file named relative to the
# check's own directory landed in DIR and was never found: the same return
# read "stopped from outside". Made absolute before the cd.
want_out   "shell_check: ...also with -C and an output named from here" \
	'exit status 255' -- \
	ckc ret255.sh 'cd "$(mktemp -d)" && ck_run -C "$DIR" rel.out sh "$D"'
# A turn-in some other program reads (ft_magic, through file(1)) is run by
# that program: a clean run shows nothing, a failed one shows the command
# without the /bin/sh note, which is about scripts.
want_broken_none "shell_check: a clean run of another program shows nothing" \
	'ran:' -- ckc quiet.sh 'ck_run "$raw" true'
want_out   "shell_check: a failed one is shown..." 'ran: false' -- \
	once ckc quiet.sh 'ck_run "$raw" false'
want_broken_none "shell_check: ...without the note about /bin/sh" \
	'/bin/sh, not through' -- once ckc quiet.sh 'ck_run "$raw" false'
# A line that ends in \r\n is shown with its carriage return, \x0d: a script
# saved with CRLF line ends makes dash's errors end in one, and it is the one
# clue to the cause. ck_run --crlf, for a program that ends its lines with
# CRLF (ssh-keygen, in Shell 00 ex03's check), shows it as the line's end.
printf 'printf "crlf-line\\r\\n" >&2\nexit 1\n' > "$WORK/ckrun/crlf.sh"
want_out   "shell_check: a CR ending a stderr line is shown as \\x0d" \
	'         crlf-line\x0d' -- ckc crlf.sh 'ck_run "$raw" sh "$D"'
want_out   "shell_check: ...and under --crlf as the line's end" \
	'         crlf-line' -- once ckc crlf.sh 'ck_run --crlf "$raw" sh "$D"'
want_broken_none "shell_check: ...with no \\x0d" \
	'crlf-line\x' -- once ckc crlf.sh 'ck_run --crlf "$raw" sh "$D"'
want_broken_none "shell_check: ...nor a '?' for it" \
	'crlf-line?' -- once ckc crlf.sh 'ck_run --crlf "$raw" sh "$D"'
# The turn-in's stdin is /dev/null, never the check's. A check that runs it
# once per line of a list, in a `while read` loop, handed it the rest of the
# list: a program that reads its stdin swallowed every case after the first,
# and the check judged one of three (Shell 01 ex08, where that read PASS).
printf 'cat > /dev/null\n' > "$WORK/ckrun/drain.sh"
printf 'one\ntwo\nthree\n' > "$WORK/ckrun/cdir/three"
want_green "shell_check: ck_run in a while-read loop runs every line" -- \
	ckc drain.sh 'n=0; while IFS= read -r l; do ck_run "$raw" sh "$D"; n=$((n + 1)); done < "$DIR/three"' \
		'ck "three runs" test "$n" -eq 3'
# ck_eq shows both values through the one renderer, in brackets: a trailing
# blank and a carriage return in a captured value were printed as they came,
# two identical-looking values beside a FAIL.
want_red   "shell_check: ck_eq fails two values that differ in a CR" -- \
	once ckc quiet.sh 'ck_run "$raw" true' "ck_eq \"the value\" \"\$(printf 'a \\r')\" a"
want_out   "shell_check: ...and shows each through the renderer" \
	'(want [a], got [a \x0d])' -- \
	once ckc quiet.sh 'ck_run "$raw" true' "ck_eq \"the value\" \"\$(printf 'a \\r')\" a"
# ...and says what the marks it showed mean, once, under the checklist:
# read off the values it showed, so it names the tab and the dollar here,
# and nothing at all under a checklist whose values held no mark.
want_out   "shell_check: ...with the key to the marks it showed" \
	'(byte for byte: \t a tab, and \x24 a dollar)' -- \
	ckc quiet.sh 'ck_run "$raw" true' "ck_eq \"the value\" \"\$(printf 'a\\tb\$c')\" 'a b'"
want_broken_none "shell_check: ...and none where it showed no mark" 'byte for byte' -- \
	ckc quiet.sh 'ck_run "$raw" true' "ck_eq \"the value\" b a"
# One rule says when a word of a command line may stay bare and how one is
# quoted: runner_lib.sh's rl_cmdline, which writes a runner's RAN: line.
# ck_run's ran: line had a copy of its own, and two copies drift; so each
# word below -- empty, a blank, a quote, a '*', a '^', a '%', a control byte,
# a plain path -- has to come out of both the same.
ck_toy "$WORK/ckrun/parity.sh" 'raw=$(mktemp)' \
	"ck_run \"\$raw\" false '' 'a b' \"it's\" '*' 'x^y' '50%' \"\$(printf 'x\\001y')\" /no/such/plain/path" \
	'rm -f "$raw" "$raw.err"' 'ck "ran" true'
ck_parity() {  # 0 when ck_run's ran: line and rl_cmdline write the same words
	_cpa_ck=$(ck_toy_run "$WORK/ckrun/parity.sh" | sed -n 's/^  ran: //p')
	_cpa_rl=$("$SH" -c '. "$1"; shift; rl_cmdline "$@"' parity "$TOOLS/runner_lib.sh" \
		false '' 'a b' "it's" '*' 'x^y' '50%' "$(printf 'x\001y')" /no/such/plain/path)
	[ -n "$_cpa_ck" ] || { echo "ck_run printed no ran: line"; return 2; }
	[ "$_cpa_ck" = "$_cpa_rl" ] && return 0
	printf 'ran:        %s\nrl_cmdline: %s\n' "$_cpa_ck" "$_cpa_rl"
	return 1
}
want_green "shell_check: ck_run's ran: line writes each word as rl_cmdline does" -- ck_parity
# The ran: line is a command to type back: a word holding a control byte is
# written so the shell gives the byte back (rl_shword), not printed raw.
want_out   "shell_check: a control byte in a ran: line is written, not sent" \
	"\"\$(printf -- 'x\\001y')\"" -- \
	ckc quiet.sh "ck_run \"\$raw\" false \"\$(printf 'x\\001y')\""
# What it shows goes through runner_lib.sh's rl_excerpt, the one renderer
# and the one cut: a control byte is \xHH (it was a '?', which is also a
# byte a script can print), and a cut says what it left out and keeps the
# whole text -- which shell_test.sh used to re-derive from limits of its own.
printf 'printf "bell\\007\\n" >&2\nexit 1\n' > "$WORK/ckrun/bell.sh"
want_out   "shell_check: a control byte on stderr reads \\xHH" 'bell\x07' -- \
	ckc bell.sh 'ck_run "$raw" sh "$D"'
printf 'i=0; while [ $i -lt 8 ]; do echo "diag $i" >&2; i=$((i + 1)); done\nexit 1\n' \
	> "$WORK/ckrun/chatty.sh"
mkdir -p "$WORK/ckrun/outputs"
ckc_kept() (
	TEST_UNDECLARED_OUTPUTS_DIR="$WORK/ckrun/outputs"
	export TEST_UNDECLARED_OUTPUTS_DIR
	ckc "$@"
)
want_out   "shell_check: a long stderr says how much it left out" \
	'3 more line(s), full text in' -- ckc_kept chatty.sh 'ck_run "$raw" sh "$D"'
want_green "shell_check: ...and keeps the whole of it" -- \
	grep -q 'diag 7' "$WORK/ckrun/outputs/run-1-stderr.txt"

# ck_sh_parses: the shell subjects require shell exercises to run under
# /bin/sh, and dash runs a script line by line -- so one that prints the right
# thing and then dies on an unclosed `if` passed every check of its output
# (finding 205: find_sh.sh, 9/9). This is the check that catches it, with the
# shell's own message under the line.
ckp() {
	ck_toy "$WORK/ckrun/parse.sh" "ck_sh_parses \"$WORK/ckrun/$1\""
	ck_toy_run "$WORK/ckrun/parse.sh"
}
want_green "shell_check: ck_sh_parses, a script sh can read" -- ckp quiet.sh
want_red   "shell_check: ck_sh_parses, an unclosed if" -- ckp unclosed.sh
want_out   "shell_check: ...with the shell's own message" 'unclosed.sh: ' -- \
	ckp unclosed.sh
want_red   "shell_check: ck_sh_parses, no file is not a pass" -- ckp none.sh

# ck_no_operator: "only one command" as the shell reads the file. The arms that
# matter are the green ones: a quoted or escaped ';' is an argument, a '#'
# inside a word is text, a redirection's '&' is not a background, and a
# backslash-newline continues a line. The check it replaced grepped the bytes,
# and failed every one of those as "sequencing".
mkdir -p "$WORK/ckops"
cko() {
	_f=$1
	shift
	ck_toy "$WORK/ckops/check.sh" "ck_no_operator \"one command\" \"$WORK/ckops/$_f\" $*"
	ck_toy_run "$WORK/ckops/check.sh"
}
printf '%s\n' "printf '%s\\n' a \\; b" > "$WORK/ckops/escaped"
printf '%s\n' "printf '%s\\n' a ';' \"b;\"" > "$WORK/ckops/quoted"
printf '%s\n' '#!/bin/sh' "echo '#x#' a\\#b # c; d && e" > "$WORK/ckops/comment"
printf '%s\n' 'echo a 2>&1 >|/dev/null' > "$WORK/ckops/redir"
printf '%s\n' 'echo a \' '	b' '' > "$WORK/ckops/continued"
printf '%s\n' 'echo a; echo b' > "$WORK/ckops/semi"
printf '%s\n' 'echo a;' '' > "$WORK/ckops/trailing"
printf '%s\n' 'echo a && echo b' > "$WORK/ckops/and"
printf '%s\n' 'echo a | cat' > "$WORK/ckops/pipe"
printf '%s\n' 'echo a' 'echo b' > "$WORK/ckops/twolines"
printf '%s\n' 'echo a || echo b' > "$WORK/ckops/oror"
want_green "shell_check: ck_no_operator, an escaped ';' is an argument" -- \
	cko escaped "';' '&&' '||'"
want_green "shell_check: ck_no_operator, so is a quoted one" -- \
	cko quoted "';' '&&' '||'"
want_green "shell_check: ck_no_operator, a comment and a '#' in a word" -- \
	cko comment "';' '&&' '||' newline"
want_green "shell_check: ck_no_operator, 2>&1 and >| are redirections" -- \
	cko redir "'&' '|'"
want_green "shell_check: ck_no_operator, a continued line is one line" -- \
	cko continued newline
want_red   "shell_check: ck_no_operator, a ';' between two commands" -- \
	cko semi "';' '&&' '||'"
want_green "shell_check: ck_no_operator, a ';' that ends the only command" -- \
	cko trailing "';' '&&' '||' newline"
want_red   "shell_check: ck_no_operator, '&&' between two commands" -- \
	cko and "';' '&&' '||'"
# '||' is its own operator, never a '|': a list that names only '|' does not
# see it. That is how ex08's literal reading passed `a || b` as "one command".
want_red   "shell_check: ck_no_operator, '||' between two commands" -- \
	cko oror "';' '&&' '||'"
want_green "shell_check: ck_no_operator, a pipe only when asked about" -- \
	cko pipe "';' '&&' '||'"
want_red   "shell_check: ck_no_operator, ...and red when asked" -- \
	cko pipe "'|'"
want_red   "shell_check: ck_no_operator, a second command line" -- \
	cko twolines newline
want_out   "shell_check: ck_no_operator names what it found" "found ';'" -- \
	cko semi "';' '&&' '||'"
want_red   "shell_check: ck_no_operator, no file is not a pass" -- \
	cko missing "';'"

# The two exercises that apply these helpers to one subject sentence each --
# Shell 00 ex02's archive and ex08's clean -- run as scripts. Piscine
# Reloaded's ex00 and ex02 read these same files (twin_of), so one run covers
# both projects. The helper arms above cannot see a check.sh that stops
# applying them: put one back to its old grep and every one of those still
# passes. Nothing here answers either exercise. An archive holds one or two
# members, at whatever mode the box gives them, and each arm reads one line of
# the checklist; clean is a single echo or printf.
#
# Run through "$SH", as shell_test.sh runs a check through sh, and with TMPDIR
# pointed at a directory of their own: finding 018 was the shell's "cannot
# open" error for a missing member reaching the checklist with the check's
# scratch path in it, and that path is what the first two arms look for --
# dash and bash word the error differently, and both print the path.
ROOT=$(cd "$TOOLS/.." && pwd)
mkdir -p "$WORK/exck/tmp" "$WORK/exck/one" "$WORK/exck/pair"
exck() {
	env TMPDIR="$WORK/exck/tmp" SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
		"$SH" "$ROOT/$1" "$2"
}
tar -cf "$WORK/exck/empty.tar" -T /dev/null
# test1 at a mode the subject does not show, stored as './test1': the line
# must report that mode, not "no test1".
printf 'a\n' > "$WORK/exck/one/test1"
chmod 640 "$WORK/exck/one/test1"
( cd "$WORK/exck/one" && tar -cf ../dotted.tar ./test1 )
# One file under the names test3 and test5, archived in both orders: tar
# records whichever name comes second as the link to the first.
printf 'a' > "$WORK/exck/pair/test5"
ln "$WORK/exck/pair/test5" "$WORK/exck/pair/test3"
( cd "$WORK/exck/pair" && tar -cf ../link5.tar test3 test5 &&
	tar -cf ../link3.tar test5 test3 )
_t=c-piscine/c-piscine-shell-00/tests/ex02
want_broken_none "shell-00 ex02: no archive, and no shell error" \
	"$WORK/exck/tmp" -- exck "$_t/check.sh" "$WORK/exck/none.tar"
want_broken_none "shell-00 ex02: an empty archive, and no shell error" \
	"$WORK/exck/tmp" -- once exck "$_t/check.sh" "$WORK/exck/empty.tar"
want_out "shell-00 ex02: a './test1' member is found by its name" \
	'got [-rw-r-----]' -- once exck "$_t/check.sh" "$WORK/exck/dotted.tar"
want_out "shell-00 ex02: test5 recorded as the link to test3" \
	'[PASS] test3 and test5 are hard links' -- \
	exck "$_t/check.sh" "$WORK/exck/link5.tar"
want_out "shell-00 ex02: ...and test3 as the link to test5" \
	'[PASS] test3 and test5 are hard links' -- \
	exck "$_t/check.sh" "$WORK/exck/link3.tar"
# A member that is not there is one line, the one that says so: its date,
# size and links used to be graded too, each line another way of saying it
# was missing -- twenty lines for an empty archive.
want_out "shell-00 ex02: a missing member is said to be missing" \
	'got [nothing: no test4 in the archive]' -- \
	once exck "$_t/check.sh" "$WORK/exck/empty.tar"
want_broken_none "shell-00 ex02: ...and its date is not graded" \
	'no date to read' -- once exck "$_t/check.sh" "$WORK/exck/empty.tar"
want_broken_none "shell-00 ex02: ...nor its size" \
	'content is' -- once exck "$_t/check.sh" "$WORK/exck/empty.tar"
want_broken_none "shell-00 ex02: ...nor its links" \
	'hard links to one file' -- once exck "$_t/check.sh" "$WORK/exck/empty.tar"
# And a member that IS there is graded on each attribute: test1 at the wrong
# mode still has its date and size read.
want_out "shell-00 ex02: a present member's date is still graded" \
	'test1: dated 06-01' -- once exck "$_t/check.sh" "$WORK/exck/dotted.tar"
# ...and its size line says what it is: test1 archived as a directory is
# there, and no regular file, never "not in the archive".
mkdir -p "$WORK/exck/dir/test1"
( cd "$WORK/exck/dir" && tar -cf ../dir1.tar test1 )
want_out "shell-00 ex02: a member of the wrong type is not called missing" \
	'got [nothing: not a regular file]' -- once exck "$_t/check.sh" "$WORK/exck/dir1.tar"
want_broken_none "shell-00 ex02: ...anywhere in its checklist" \
	'not in the archive' -- once exck "$_t/check.sh" "$WORK/exck/dir1.tar"
# clean. check.sh (basic) reads "only one command" as the shell does, and
# literal.sh (strict) reads it word for word -- which must still fail every
# file the basic reading fails: literal.sh once named only '|' '&' and a
# second line, and passed `a || b` as "one command".
printf '%s\n' 'echo a' > "$WORK/exck/one.clean"
_t=c-piscine/c-piscine-shell-00/tests/ex08
_x=${_t%%/tests/*}
_x="${_x##*/c-piscine-} ${_t##*/}"
want_out "$_x: an escaped ';' is one command" \
	'[PASS] is a single command' -- \
	exck "$_t/check.sh" "$WORK/ckops/escaped"
want_out "$_x: '||' joins two" "found '||'" -- \
	exck "$_t/check.sh" "$WORK/ckops/oror"
# Two lines are two commands under every reading of "one command", so
# the basic check fails them too; only the escaped ';' was ambiguous. A
# backslash-continued line is still one.
want_out "$_x: a second command line is two" "found a second command line" -- \
	exck "$_t/check.sh" "$WORK/ckops/twolines"
want_out "$_x: ...a continued line is one" '[PASS] is a single command' -- \
	exck "$_t/check.sh" "$WORK/ckops/continued"
want_green "$_x literal: one plain command" -- \
	exck "$_t/literal.sh" "$WORK/exck/one.clean"
want_red "$_x literal: an escaped ';' is still a ';'" -- \
	exck "$_t/literal.sh" "$WORK/ckops/escaped"
want_red "$_x literal: '||' joins two here too" -- \
	exck "$_t/literal.sh" "$WORK/ckops/oror"
# An absence is asked of output that exists. A clean that displays nothing
# used to pass "does not display the untouched file", and an ft_magic file(1)
# cannot load -- it prints no label at all -- both "must not match" lines: PASS
# lines about output never printed.
printf ':\n' > "$WORK/exck/quiet.clean"
want_out "shell-00 ex08: a clean that displays nothing is not said to skip normal_file" \
	'[FAIL] does not display the untouched file' -- \
	exck "$_t/check.sh" "$WORK/exck/quiet.clean"
# The near misses: a name that fails one half of a pattern survives, and is
# not shown, and the line that says so names it. Each toy clean deletes or
# prints fixed names; none of them searches for anything. On the old fixture
# -- the three backups, normal_file and sub/ -- all of these passed.
printf '%s\n' "rm -f -- '#draft'" > "$WORK/exck/near1.clean"
printf '%s\n' "rm -f -- 'notes#' 'notes~old' '~draft'" > "$WORK/exck/near2.clean"
printf '%s\n' "printf '%s\\n' ./test~ './#test#' ./sub/nested~ './#draft'" \
	> "$WORK/exck/near3.clean"
want_out "$_x: deleting #draft is named" \
	'[FAIL] keeps a file that only starts with # (#draft)' -- \
	exck "$_t/check.sh" "$WORK/exck/near1.clean"
want_out "$_x: ...notes# too" '[FAIL] keeps a file that only ends with # (notes#)' -- \
	once exck "$_t/check.sh" "$WORK/exck/near2.clean"
want_out "$_x: ...notes~old" '[FAIL] keeps a file with ~ inside its name' -- \
	once exck "$_t/check.sh" "$WORK/exck/near2.clean"
want_out "$_x: ...and ~draft" '[FAIL] keeps a file that starts with ~ (~draft)' -- \
	once exck "$_t/check.sh" "$WORK/exck/near2.clean"
want_out "$_x: showing #draft is named" \
	'[FAIL] displays exactly the found backup files' -- \
	exck "$_t/check.sh" "$WORK/exck/near3.clean"
# regular.sh (strict): "files" as regular files, with directories named like
# backups. A clean that shows and deletes the two backup files and nothing
# else passes; one that removes a directory, empty or full, or shows one, is
# named.
printf '%s\n' "rm -f -- 'test~' '#test#' && printf '%s\\n' ./test~ './#test#'" \
	> "$WORK/exck/files.clean"
printf '%s\n' "rmdir -- 'olddir~'" > "$WORK/exck/rmdir.clean"
printf '%s\n' "rm -rf -- '#full#'" > "$WORK/exck/rmrf.clean"
printf '%s\n' "printf '%s\\n' ./test~ './#test#' ./olddir~" > "$WORK/exck/showdir.clean"
want_green "$_x regular: backup files shown and deleted, directories kept" -- \
	exck "$_t/regular.sh" "$WORK/exck/files.clean"
want_out "$_x regular: an empty directory deleted is named" \
	'[FAIL] keeps an empty directory named like a backup (olddir~/)' -- \
	exck "$_t/regular.sh" "$WORK/exck/rmdir.clean"
want_out "$_x regular: ...and a full one" \
	'[FAIL] keeps a directory named like a backup, and the file in it (#full#/keep)' -- \
	exck "$_t/regular.sh" "$WORK/exck/rmrf.clean"
want_out "$_x regular: a directory shown is named" \
	'[FAIL] displays no directory' -- \
	exck "$_t/regular.sh" "$WORK/exck/showdir.clean"
want_red "$_x regular: a clean that does nothing does not pass" -- \
	exck "$_t/regular.sh" "$WORK/exck/quiet.clean"

# midLS: the fixture tells the modification date from the other orders a
# listing can take, and a directory's marker from every other type's. Each
# toy midLS prints one fixed line, never a listing: the one the check expects,
# or the one a listing by another key, or with a marker on every type, gives
# on its fixture (read off the table at the top of the check). On the old
# fixture -- one time per entry, names in date order -- the access-date and
# reversed-name listings were the right one, and nothing carried a marker.
_t=c-piscine/c-piscine-shell-00/tests/ex04
mls() {  # mls NAME LINE -- a toy midLS that prints LINE
	printf 'printf "%%s\\n" %s\n' "'$2'" > "$WORK/exck/$1.midLS"
}
mls want 'charlie, echo, bravo/, delta, alpha'
mls oldest 'alpha, delta, bravo/, echo, charlie'
mls atime 'delta, alpha, charlie, echo, bravo/'
mls rname 'echo, delta, charlie, bravo/, alpha'
mls marks 'charlie*, echo, bravo/, delta@, alpha'
mls noslash 'charlie, echo, bravo, delta, alpha'
want_green "shell-00 ex04: the listing by modification date passes" -- \
	exck "$_t/check.sh" "$WORK/exck/want.midLS"
# The subject names no direction (ruling R5, D3): the other one passes at
# basic too, and only ex04_newest_first, at strict, reads one. The old check
# failed it at basic.
want_green "shell-00 ex04: ...oldest first too, since the subject names no direction" -- \
	exck "$_t/check.sh" "$WORK/exck/oldest.midLS"
want_out "shell-00 ex04: the listing by access date is named" \
	'[FAIL] sorted by modification date, in either direction' -- \
	exck "$_t/check.sh" "$WORK/exck/atime.midLS"
want_out "shell-00 ex04: ...and by name, reversed" \
	'[FAIL] sorted by modification date, in either direction' -- \
	exck "$_t/check.sh" "$WORK/exck/rname.midLS"
# newest_first.sh, the reading: a fixture of its own, three files whose
# names, access dates, creation and change times give no direction of their
# modification dates. Newest first passes; oldest first is named, and so is
# the listing every other key gives, either way round. Three files have six
# orders and the keys take all six, so the creation and change orders are
# the names' (ORDER): the old fixture set the access dates last in the
# newest-first order, so a listing by change time, oldest first, passed it
# wherever the touches fell in different clock ticks.
mls nf_newest 'lima, mike, kilo'
mls nf_oldest 'kilo, mike, lima'
mls nf_name 'kilo, lima, mike'
mls nf_rname 'mike, lima, kilo'
mls nf_atime 'mike, kilo, lima'
mls nf_ratime 'lima, kilo, mike'
want_green "shell-00 ex04 newest_first: newest first passes" -- \
	exck "$_t/newest_first.sh" "$WORK/exck/nf_newest.midLS"
want_out "shell-00 ex04 newest_first: oldest first is named" \
	'[FAIL] newest modification date first' -- \
	exck "$_t/newest_first.sh" "$WORK/exck/nf_oldest.midLS"
for _o in name rname atime ratime; do
	want_out "shell-00 ex04 newest_first: the listing by $_o is named" \
		'[FAIL] newest modification date first' -- \
		exck "$_t/newest_first.sh" "$WORK/exck/nf_$_o.midLS"
done
# The fixture's own guard: a key that gives the listing expected is the
# harness's fault (exit 2), never a verdict on midLS. An order of creation
# and touches that is the listing, either way round, and access dates in
# the modification dates' order.
sed "s/^ORDER='kilo lima mike'\$/ORDER='lima mike kilo'/" \
	"$ROOT/$_t/newest_first.sh" > "$WORK/exck/nf_order.sh"
sed "s/^ORDER='kilo lima mike'\$/ORDER='kilo mike lima'/" \
	"$ROOT/$_t/newest_first.sh" > "$WORK/exck/nf_rorder.sh"
sed 's/^lima	202607030900	202607110900$/lima	202607030900	202607140900/' \
	"$ROOT/$_t/newest_first.sh" > "$WORK/exck/nf_adates.sh"
for _o in order rorder; do
	want_broken "shell-00 ex04 newest_first: a touch order that is the listing is refused ($_o)" \
		'the order the files are created and last touched in' -- \
		env TMPDIR="$WORK/exck/tmp" SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
			"$SH" "$WORK/exck/nf_$_o.sh" "$WORK/exck/nf_newest.midLS"
done
want_broken "shell-00 ex04 newest_first: access dates in the listing's order are refused" \
	'the table no longer tells them apart' -- \
	env TMPDIR="$WORK/exck/tmp" SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
		"$SH" "$WORK/exck/nf_adates.sh" "$WORK/exck/nf_newest.midLS"
# Both directions pass at basic, so neither may be the order another key
# gives: a table whose dates follow the names would pass a listing by name.
# The harness's fault (exit 2), never a verdict on midLS.
sed -e 's/^bravo	dir	202606270900/bravo	dir	202606260900/' \
	-e 's/^echo	file	202606280900/echo	file	202606290900/' \
	-e 's/^delta	link	202606260900/delta	link	202606280900/' \
	-e 's/^charlie	exec	202606290900/charlie	exec	202606270900/' \
	"$ROOT/$_t/check.sh" > "$WORK/exck/check_name_dates.sh"
want_broken "shell-00 ex04: dates in name order are refused" \
	'the table no longer tells them apart' -- \
	env TMPDIR="$WORK/exck/tmp" SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
		"$SH" "$WORK/exck/check_name_dates.sh" "$WORK/exck/want.midLS"
# ...nor the order the entries are last touched in, which is their change
# times' order: access dates set last in the oldest-first order would pass
# a listing by change time. The guard used to read the two columns only.
sed "s/^ATIME_ORDER='.*'\$/ATIME_ORDER='alpha delta bravo echo charlie .hidden'/" \
	"$ROOT/$_t/check.sh" > "$WORK/exck/check_touch_order.sh"
want_broken "shell-00 ex04: access dates set last in a modification-date order are refused" \
	'or last touched in (their change times)' -- \
	env TMPDIR="$WORK/exck/tmp" SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
		"$SH" "$WORK/exck/check_touch_order.sh" "$WORK/exck/want.midLS"
want_out "shell-00 ex04: a marker on every type is named" \
	'[FAIL] only directories are marked' -- \
	once exck "$_t/check.sh" "$WORK/exck/marks.midLS"
# ...and only that: in the right order, a listing whose only fault is its
# markers was also called unsorted, its entries looked up with the markers on
# (the mutation run of 2026-10-03).
want_broken_none "shell-00 ex04: ...and is not also called unsorted" \
	'[FAIL] sorted by modification date' -- \
	once exck "$_t/check.sh" "$WORK/exck/marks.midLS"
# The other way round: in the right order, a directory without its slash
# was also called unsorted, looked up with the slash on. The slash is the
# line about directories' alone.
want_out "shell-00 ex04: a directory without its slash is named" \
	'[FAIL] directories marked with a trailing slash' -- \
	once exck "$_t/check.sh" "$WORK/exck/noslash.midLS"
want_broken_none "shell-00 ex04: ...and that alone, not unsorted too" \
	'[FAIL] sorted by modification date' -- \
	once exck "$_t/check.sh" "$WORK/exck/noslash.midLS"
# A row added to the table and to neither order of the fixture keeps the
# time it was made at, so the listing derived from the table is not the
# directory's: the harness's fault (exit 2), never a verdict on midLS. The
# guard used to walk MTIME_ORDER, and passed such a row by.
sed 's/^echo	file	202606280900	202607020900$/&\nfoxtrot	file	202606300900	202607060900/' \
	"$ROOT/$_t/check.sh" > "$WORK/exck/check_extra_row.sh"
want_broken "shell-00 ex04: a table row in neither order is refused" \
	'does not name each row of its table once' -- \
	env TMPDIR="$WORK/exck/tmp" SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
		"$SH" "$WORK/exck/check_extra_row.sh" "$WORK/exck/want.midLS"

# git_ignore.sh: every source of ignore rules, and what must not be listed.
# Each toy prints a fixed list of the fixture's names and asks git nothing.
# On the old fixture -- one top-level .gitignore, no directory, no tracked
# file a pattern matches -- the top-level-only list was the right one.
_t=c-piscine/c-piscine-shell-00/tests/ex06
gi() {  # gi NAME PATH... -- a toy git_ignore.sh printing PATHs
	_n=$1
	shift
	printf 'printf "%%s\\n"' > "$WORK/exck/$_n.gi"
	for _p do printf " '%s'" "$_p" >> "$WORK/exck/$_n.gi"; done
	printf '\n' >> "$WORK/exck/$_n.gi"
}
gi each .DS_Store alpha.log build/a.o build/b.o local.bak one.log sub/draft.tmp
gi whole .DS_Store alpha.log build/ local.bak one.log sub/draft.tmp
gi toponly .DS_Store alpha.log build/ one.log
gi bare .DS_Store alpha.log build/ draft.tmp local.bak one.log
gi forced .DS_Store alpha.log build/ forced.log local.bak one.log sub/draft.tmp
gi shuffled sub/draft.tmp one.log build/b.o alpha.log local.bak .DS_Store build/a.o
gi deep .DS_Store Zeta.log alpha.log build/a.o build/deep/b.o
gi deepdir .DS_Store Zeta.log alpha.log build/
gi locale alpha.log build/a.o build/deep/b.o .DS_Store Zeta.log
want_green "shell-00 ex06: each ignored file, from every source" -- \
	exck "$_t/check.sh" "$WORK/exck/each.gi"
want_green "shell-00 ex06: ...or build/ as one line" -- \
	exck "$_t/check.sh" "$WORK/exck/whole.gi"
want_green "shell-00 ex06: ...in any order, since the subject names none" -- \
	exck "$_t/check.sh" "$WORK/exck/shuffled.gi"
want_out "shell-00 ex06: .git/info/exclude left out is named" \
	'[FAIL] lists a file .git/info/exclude ignores' -- \
	once exck "$_t/check.sh" "$WORK/exck/toponly.gi"
want_out "shell-00 ex06: ...and sub/.gitignore" \
	'[FAIL] lists a file sub/.gitignore ignores' -- \
	once exck "$_t/check.sh" "$WORK/exck/toponly.gi"
want_out "shell-00 ex06: a nested file by its bare name is named" \
	'[FAIL] lists a file sub/.gitignore ignores, by its path from the top' -- \
	exck "$_t/check.sh" "$WORK/exck/bare.gi"
want_out "shell-00 ex06: a tracked file a pattern matches is named" \
	'[FAIL] does NOT list a tracked file a pattern matches' -- \
	exck "$_t/check.sh" "$WORK/exck/forced.gi"
want_green "shell-00 ex06 literal: each file of an ignored directory" -- \
	exck "$_t/literal.sh" "$WORK/exck/deep.gi"
want_out "shell-00 ex06 literal: the directory in their place is named" \
	'[FAIL] does not list the directory in their place' -- \
	exck "$_t/literal.sh" "$WORK/exck/deepdir.gi"
# The order: git's, byte by byte. The same paths in a locale's order -- what
# a UTF-8 `sort` gives -- are named. check.sh's old exact listing asked for
# byte order at basic; the subject names no order, so it is read here, at
# strict, and check.sh passes any order (the shuffled arm above).
want_out "shell-00 ex06 literal: the paths in another order are named" \
	'[FAIL] lists the paths in the order git prints them' -- \
	exck "$_t/literal.sh" "$WORK/exck/locale.gi"

# A fixture or a reference that cannot be built is the harness's fault (exit
# 2), never a verdict on the turn-in, whose hints a 1 prints. With a git that
# fails, ex05's check named four counts and passed its order on an output of
# nothing, and ex06's two named a "fixture repository created" check; with an
# archive that holds no a or sw.diff, or a reference that refuses them, ex07
# failed b. The toys are no answer: one prints nothing, one an invented line.
# Each run has a TMPDIR of its own, which it must leave empty: a check that
# stops on ck_broken removes its scratch folders first, as its last lines do
# on the way to ck_report, or a hand run leaves them in the machine's /tmp.
mkdir -p "$WORK/exck/badgit" "$WORK/exck/nopgit"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$WORK/exck/badgit/git"
printf '%s\n' '#!/bin/sh' 'case $1 in init) mkdir -p "$3" ;; esac' > "$WORK/exck/nopgit/git"
chmod +x "$WORK/exck/badgit/git" "$WORK/exck/nopgit/git"
printf 'true\n' > "$WORK/exck/quiet.git_commit"
# tmp_left CMD... -- CMD under a TMPDIR of its own: CMD's status when it left
# that folder empty, else 1, naming what it left.
tmp_left() {
	_tl_d=$(mktemp -d "$WORK/exck/tmp_left.XXXXXX") || return 3
	env TMPDIR="$_tl_d" "$@"
	_tl_s=$?
	_tl_l=$(ls -A "$_tl_d")
	rm -rf "$_tl_d"
	[ -z "$_tl_l" ] || { printf 'left behind in its TMPDIR: %s\n' "$_tl_l"; return 1; }
	return "$_tl_s"
}
fixck() {  # fixck GITDIR SCRIPT TOY -- exck with GITDIR's git first on PATH
	tmp_left env PATH="$WORK/exck/$1:$PATH" \
		SHELL_CHECK_LIB="$TOOLS/shell_check.sh" "$SH" "$ROOT/$2" "$3"
}
want_broken "shell-00 ex05: a git fixture that cannot be built is refused" \
	'BROKEN HARNESS: the git fixture repository could not be built' -- \
	fixck badgit c-piscine/c-piscine-shell-00/tests/ex05/check.sh "$WORK/exck/quiet.git_commit"
# ...and one that records no commits, by a git that makes the folder, does
# nothing else and says it did: the old check passed its order line on that
# empty record.
want_broken "shell-00 ex05: ...or that records no commits" \
	'BROKEN HARNESS: the git fixture repository did not record its six commits' -- \
	fixck nopgit c-piscine/c-piscine-shell-00/tests/ex05/check.sh "$WORK/exck/quiet.git_commit"
want_broken "shell-00 ex06: ...and in its check" \
	'BROKEN HARNESS: the git fixture repository could not be built' -- \
	fixck badgit "$_t/check.sh" "$WORK/exck/each.gi"
want_broken "shell-00 ex06 literal: ...and in its reading" \
	'BROKEN HARNESS: the git fixture repository could not be built' -- \
	fixck badgit "$_t/literal.sh" "$WORK/exck/deep.gi"
# ex07: an archive of invented files beside a toy b, and stand-in references
# that refuse (exit 1) or print one invented line.
mkdir -p "$WORK/exck/e7none" "$WORK/exck/e7both" "$WORK/exck/e7src"
printf 'x\n' > "$WORK/exck/e7src/other"
printf 'x\n' > "$WORK/exck/e7src/a"
printf 'x\n' > "$WORK/exck/e7src/sw.diff"
tar -czf "$WORK/exck/e7none/resources.tar.gz" -C "$WORK/exck/e7src" other
tar -czf "$WORK/exck/e7both/resources.tar.gz" -C "$WORK/exck/e7src" a sw.diff
printf 'invented\n' > "$WORK/exck/e7none/b"
printf 'invented\n' > "$WORK/exck/e7both/b"
printf '%s\n' '#!/bin/sh' 'echo "refused" >&2' 'exit 1' > "$WORK/exck/e7refuse"
printf '%s\n' '#!/bin/sh' "printf 'invented\\n'" > "$WORK/exck/e7print"
chmod +x "$WORK/exck/e7refuse" "$WORK/exck/e7print"
e7ck() {  # e7ck DIR ORACLE -- ex07's check on DIR/b, its archive beside it
	tmp_left env ORACLE="$2" SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
		"$SH" "$ROOT/c-piscine/c-piscine-shell-00/tests/ex07/check.sh" "$1/b"
}
want_broken "shell-00 ex07: an archive without a and sw.diff is refused" \
	'BROKEN HARNESS: resources.tar.gz holds no a and sw.diff' -- \
	e7ck "$WORK/exck/e7none" "$WORK/exck/e7print"
want_broken "shell-00 ex07: ...and a reference that refuses them" \
	'BROKEN HARNESS: the reference could not apply sw.diff to a' -- \
	e7ck "$WORK/exck/e7both" "$WORK/exck/e7refuse"
want_green "shell-00 ex07: ...and with a reference that answers, b is judged" -- \
	e7ck "$WORK/exck/e7both" "$WORK/exck/e7print"

# find_sh.sh: the look-alikes. Each toy prints a fixed list of the tree's
# names, and has its execute bit, since the subject runs ./find_sh.sh. On the
# old tree -- '.sh' only ever at a name's end or in a name to reject, no
# directory named *.sh, nothing ending in sh without the dot -- the first two
# slips below printed the right list.
_t=c-piscine/c-piscine-shell-01/tests/ex02
fs() {  # fs NAME WORD... -- a toy find_sh.sh printing WORDs
	_n=$1
	shift
	printf 'printf "%%s\\n"' > "$WORK/exck/$_n.find_sh"
	for _p do printf " '%s'" "$_p" >> "$WORK/exck/$_n.find_sh"; done
	printf '\n' >> "$WORK/exck/$_n.find_sh"
	chmod +x "$WORK/exck/$_n.find_sh"
}
fs withdir find_sh findeable1 findeable2 my.shell a.sh.b inner lib
fs nodir find_sh findeable1 findeable2 my.shell a.sh.b inner
fs first find_sh findeable1 findeable2 myell.sh a.b.sh inner
fs dotless find_sh findeable1 findeable2 my.shell a.sh.b inner dotlesssh
fs noinner find_sh findeable1 findeable2 my.shell a.sh.b
want_green "shell-01 ex02: the tree's names, the directory's among them" -- \
	exck "$_t/check.sh" "$WORK/exck/withdir.find_sh"
want_green "shell-01 ex02: ...or without it" -- \
	exck "$_t/check.sh" "$WORK/exck/nodir.find_sh"
want_out "shell-01 ex02: the first .sh stripped, not the last, is named" \
	'[FAIL] strips only the final .sh' -- \
	exck "$_t/check.sh" "$WORK/exck/first.find_sh"
want_out "shell-01 ex02: a name ending in sh with no dot is named" \
	'[FAIL] ignores names ending in sh with no .sh extension' -- \
	exck "$_t/check.sh" "$WORK/exck/dotless.find_sh"
want_out "shell-01 ex02: the file inside lib.sh/ left out is named" \
	'[FAIL] lists a .sh file inside a directory whose own name ends in .sh' -- \
	exck "$_t/check.sh" "$WORK/exck/noinner.find_sh"
# regular.sh quotes the sentence it reads as the target's own subject says
# it, from the call's wording (Reloaded ex03 words it otherwise).
exckw() {  # exckw WORDS CHECK TURNIN -- exck, the call's wording for "files" given
	env TMPDIR="$WORK/exck/tmp" SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
		SHELL_CHECK_WORDING_files="$1" "$SH" "$ROOT/$2" "$3"
}
want_out "shell-01 ex02 regular: the directory's name listed is named" \
	'[FAIL] does not list the directory lib.sh' -- \
	exckw 'all files ending with .sh' "$_t/regular.sh" "$WORK/exck/withdir.find_sh"
want_green "shell-01 ex02 regular: ...and left out, passes" -- \
	exckw 'all files ending with .sh' "$_t/regular.sh" "$WORK/exck/nodir.find_sh"
want_out "shell-01 ex02 regular: ...quoting the call's words for the sentence" \
	'The subject says: all file names that end with ".sh"' -- \
	exckw 'all file names that end with ".sh"' "$_t/regular.sh" "$WORK/exck/nodir.find_sh"
want_broken "shell-01 ex02 regular: ...and refusing a call that gives none" \
	'gives none: add' -- exck "$_t/regular.sh" "$WORK/exck/nodir.find_sh"
# A kind no contract has is the harness's fault, in a check script too.
want_broken "shell_check: ...and a check script's" "shell_check.sh: RL_UNIT_KIND is 'lesson'" -- \
	with_kind lesson exck "$_t/regular.sh" "$WORK/exck/nodir.find_sh"

printf 'this is not a magic line\n' > "$WORK/exck/broken.magic"
_t=c-piscine/c-piscine-shell-00/tests/ex09
want_out "shell-00 ex09: a database file(1) cannot load does not pass position" \
	"[FAIL] position is enforced" -- once exck "$_t/check.sh" "$WORK/exck/broken.magic"
want_out "shell-00 ex09: ...nor the whole string" \
	"[FAIL] the exact string '42' is required" -- \
	once exck "$_t/check.sh" "$WORK/exck/broken.magic"

# shell-01 ex04 (MAC.sh): what this machine cannot show is a SKIP, asked of
# the HOST before MAC.sh runs -- no ifconfig (MAC_CHECK_IFCONFIG empty), or no
# hardware address (a stand-in for //oracle answering shell01_hwaddr --machine
# with 4, as a container with only loopback does) -- a missing MAC.sh still fails
# first, and NO_SKIP=1 turns a skip red. These are the paths a container user
# takes at basic, in the submit gate. The fixture MAC.sh only parses: no path
# here runs it, and it answers nothing.
mkdir -p "$WORK/mac"
printf ':\n' > "$WORK/mac/MAC.sh"
printf '#!/bin/sh\n[ "$1 ${2:-}" = "shell01_hwaddr --machine" ] && exit "$MAC_ANY"\nexit 9\n' \
	> "$WORK/mac/oracle"
chmod +x "$WORK/mac/oracle"
mac_ck() {  # mac_ck IFCONFIG ANY NO_SKIP MAC.sh
	env MAC_CHECK_IFCONFIG="$1" MAC_ANY="$2" NO_SKIP="$3" ORACLE="$WORK/mac/oracle" \
		TMPDIR="$WORK/exck/tmp" SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
		"$SH" "$ROOT/c-piscine/c-piscine-shell-01/tests/ex04/check.sh" "$4"
}
want_green "shell-01 ex04: no ifconfig here is a skip, not a red" -- \
	mac_ck "" 0 0 "$WORK/mac/MAC.sh"
want_out "shell-01 ex04: ...that says why" 'ifconfig is not on this machine' -- \
	mac_ck "" 0 0 "$WORK/mac/MAC.sh"
want_green "shell-01 ex04: no hardware address is a skip, not a red" -- \
	mac_ck /usr/sbin/ifconfig 4 0 "$WORK/mac/MAC.sh"
want_out "shell-01 ex04: ...that says why" 'publishes no hardware address' -- \
	mac_ck /usr/sbin/ifconfig 4 0 "$WORK/mac/MAC.sh"
want_red "shell-01 ex04: NO_SKIP=1 turns either skip red" -- \
	mac_ck /usr/sbin/ifconfig 4 1 "$WORK/mac/MAC.sh"
want_red "shell-01 ex04: ...and the other" -- \
	mac_ck "" 0 1 "$WORK/mac/MAC.sh"
want_red "shell-01 ex04: a missing MAC.sh fails, before any skip" -- \
	mac_ck "" 4 0 "$WORK/mac/none.sh"
want_broken "shell-01 ex04: an oracle answering neither 0 nor 4 is a broken harness" \
	'answered 9' -- mac_ck /usr/sbin/ifconfig 9 0 "$WORK/mac/MAC.sh"
# The verdict on what MAC.sh printed, and the question asked of each of its
# lines, are the reference's too: an answer outside the set it documents
# is the harness's fault, never two FAILs on the turn-in. The stand-in
# answers 9 to each; the second answers 3 to the whole output and 9 to any
# one line of it, which MAC.sh's two invented lines reach.
want_broken "shell-01 ex04: ...and so is one that cannot judge the output" \
	'shell01_hwaddr --loopback answered 9' -- mac_ck /usr/sbin/ifconfig 0 0 "$WORK/mac/MAC.sh"
mac_lit() {  # mac_lit ANY MAC.sh [ORACLE] -- the strict reading, with an ifconfig
	env MAC_CHECK_IFCONFIG=/usr/sbin/ifconfig MAC_ANY="$1" NO_SKIP=0 \
		ORACLE="${3:-$WORK/mac/oracle}" TMPDIR="$WORK/exck/tmp" \
		SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
		"$SH" "$ROOT/c-piscine/c-piscine-shell-01/tests/ex04/literal.sh" "$2"
}
want_broken "shell-01 ex04 literal: an oracle answering neither 0 nor 4 is a broken harness" \
	'--machine answered 9' -- mac_lit 9 "$WORK/mac/MAC.sh"
want_broken "shell-01 ex04 literal: ...and so is one that cannot judge the output" \
	'shell01_hwaddr answered 9' -- mac_lit 0 "$WORK/mac/MAC.sh"
printf 'printf "one\\ntwo\\n"\n' > "$WORK/mac/two.sh"
printf '%s\n' '#!/bin/sh' '[ "${2:-}" = --machine ] && exit 0' \
	'[ "$(grep -c "")" -gt 1 ] && exit 3' 'exit 9' > "$WORK/mac/oracle_lines"
chmod +x "$WORK/mac/oracle_lines"
mac_lines() {  # mac_lines check.sh|literal.sh -- two.sh, judged by oracle_lines
	env MAC_CHECK_IFCONFIG=/usr/sbin/ifconfig NO_SKIP=0 ORACLE="$WORK/mac/oracle_lines" \
		TMPDIR="$WORK/exck/tmp" SHELL_CHECK_LIB="$TOOLS/shell_check.sh" \
		"$SH" "$ROOT/c-piscine/c-piscine-shell-01/tests/ex04/$1" "$WORK/mac/two.sh"
}
want_broken "shell-01 ex04: ...or one line of it" 'answered 9 for one line' -- mac_lines check.sh
want_broken "shell-01 ex04 literal: ...or one line of it" 'answered 9 for one line' -- \
	mac_lines literal.sh

# ck_skipped: ONE property could not be observed here, while the rest of the
# script still grades. The arm that matters is the third -- the skip has to
# reach the RESULT LINE. Two live check scripts printed `[SKIP] ...` and then
# `RESULT: PASS (7/7 checks)`, a total counting only what ran, so a reader and
# every log scraper saw an unqualified pass over a property nobody checked.
mkdir -p "$WORK/ckskipped"
ck_toy "$WORK/ckskipped/check.sh" 'ck "this one really ran" true' \
	'ck_skipped "no second interface on this box"'
want_green "shell_check: ck_skipped keeps the rest of the script green" -- \
	ck_toy_run "$WORK/ckskipped/check.sh"
want_out "shell_check: a skipped property reaches the RESULT line" '1 skipped' -- \
	ck_toy_run "$WORK/ckskipped/check.sh"
want_red "shell_check: NO_SKIP=1 turns a skipped property red" -- \
	ck_toy_run "$WORK/ckskipped/check.sh" NO_SKIP=1
# And a script with no skips must not grow a note it has nothing to report.
ck_toy "$WORK/ckskipped/none.sh" 'ck "this one really ran" true'
want_broken_none "shell_check: no skips, no note on the RESULT line" 'skipped' -- \
	ck_toy_run "$WORK/ckskipped/none.sh"

# ck_report's floor. Registering NOTHING used to print "RESULT: PASS (0/0
# checks)" and exit 0 -- a green bought by an empty loop or a glob that matched
# no files, in the library backing all 17 check scripts. A script that really
# has nothing to check says so with ck_skip or ck_skipped, and both satisfy the
# floor, which is the second arm here.
ck_toy "$WORK/ckskipped/empty.sh" \
	'while read -r _line; do ck "one per case" true; done < /dev/null'
want_broken "shell_check: registering no checks is not a pass" 'registered no checks' -- \
	ck_toy_run "$WORK/ckskipped/empty.sh"
ck_toy "$WORK/ckskipped/onlyskip.sh" 'ck_skipped "nothing to observe on this host"'
want_green "shell_check: ...but a DECLARED skip satisfies the floor" -- \
	ck_toy_run "$WORK/ckskipped/onlyskip.sh"

