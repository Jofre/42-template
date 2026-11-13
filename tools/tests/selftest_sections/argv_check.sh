# ------------------------------------------------------------------ argv_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The runner behind c-06's diff layer. Its corpus is a list of ARGUMENTS and the
# bytes they must produce, and every arm below is a program that would pass a
# weaker comparison.
mkdir -p "$WORK/av"

# A corpus holding, in order: the subject's own example, a case with NO
# arguments, one whose argument is EMPTY, one whose argument ends in a NEWLINE,
# and enough filler to clear the floor. Written by hand rather than taken from
# //oracle so these stay in the fast selftest -- the reference needs a Rust
# build, and what is under test here is the runner.
{
	printf 'args\t3\ta\tb\tc\ta\\nb\\nc\\n\n'
	printf 'args\t0\t\n'
	printf 'args\t2\t\tafter\t\\nafter\\n\n'
	printf 'args\t1\tends\\n\tends\\n\\n\n'
	# `tab\\there`, not `tab\there`: this is printf's FORMAT, so a single
	# backslash-t becomes a real tab and silently adds a field to the line.
	printf 'args\t2\ttwo words\ttab\\there\ttwo words\\ntab\\there\\n\n'
	# Bytes a terminal cannot show: 0x80 and 0xff in one argument, 0x01 in the
	# next. The report has to name them, not print them.
	printf 'args\t2\t\\0200\\0377\t\\0001z\t\\0200\\0377\\n\\0001z\\n\n'
	# A second case with a byte above 0x7f and no control byte, so a family
	# line has two failures to generalise from and only one property they share.
	printf 'args\t2\tcaf\\0351\tok\tcaf\\0351\\nok\\n\n'
	# An argument ENDING in a space, and last, so the report has a real
	# trailing space to keep twice: in the argv line, and at the end of an
	# output that lost its final newline. Nine of the 559 arguments in each
	# c-06 corpus end in one. Then a dollar, which is \x24 in every line.
	printf 'args\t2\tx\tab \tx\\nab \\n\n'
	printf 'args\t2\tc$\td\tc$\\nd\\n\n'
	_i=0
	while [ "$_i" -lt 10 ]; do
		printf 'args\t2\tx%s\ty%s\tx%s\\ny%s\\n\n' "$_i" "$_i" "$_i" "$_i"
		_i=$((_i + 1))
	done
} > "$WORK/av/corpus.tsv"
printf "#!/bin/sh\ncat '%s'\n" "$WORK/av/corpus.tsv" > "$WORK/av/oracle.sh"

# The fake students. Written, not run.
# Correct: one argument per line, a newline after each.
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done\n' > "$WORK/av/good.sh"
# The separator bug: a newline BETWEEN arguments rather than after each. Its
# output differs from the correct one only in the final byte, which is exactly
# what c-06's argv TABLE cannot see (it joins lines, so a missing final newline
# is invisible unless the last line is empty) and what `cmp` sees every time.
# %b, not %s, for the separator: with %s it printed a literal backslash-n, so
# this fixture was red as "line-count" and never had the bug it is named for.
printf '#!/bin/sh\n_s=""\nfor a in "$@"; do printf "%%b%%s" "$_s" "$a"; _s="\\n"; done\n' \
	> "$WORK/av/nonl.sh"
# Stops at the first empty argument, which is the commonest real mistake here
# and which no case anybody types by hand contains.
printf '#!/bin/sh\nfor a in "$@"; do [ -n "$a" ] || break; printf "%%s\\n" "$a"; done\n' \
	> "$WORK/av/stopsempty.sh"
# Reads stdin. Without `< /dev/null` on every run this eats the rest of the
# corpus, the loop ends after one case, and the layer reports "OK, 1 case".
printf '#!/bin/sh\ncat > /dev/null\nfor a in "$@"; do printf "%%s\\n" "$a"; done\n' \
	> "$WORK/av/eatsstdin.sh"
# Every argument but the first, then the first: the right lines in the wrong
# order, which is what "wrong-order" exists to name. It reverses and sorts
# nothing, so it is no exercise's answer.
printf '#!/bin/sh\n[ $# -gt 0 ] || exit 0\n_a="$1"; shift\nfor a in "$@"; do printf "%%s\\n" "$a"; done\nprintf "%%s\\n" "$_a"\n' \
	> "$WORK/av/rotates.sh"
# Right bytes, except that it drops every byte above 0x7f: only the cases with
# such a byte in an argument fail, which is the property the family line has to
# find on its own.
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a" | tr -d "\\200-\\377"; done\n' \
	> "$WORK/av/dropshigh.sh"
# Right bytes, then a plain non-zero return.
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done\nexit 3\n' \
	> "$WORK/av/exits3.sh"
# Right bytes, then a return of 128: the boundary. A signal is 128+N, N >= 1.
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done\nexit 128\n' \
	> "$WORK/av/exits128.sh"
chmod +x "$WORK/av"/*.sh

# Every call says what stderr is held to (argv_check.sh refuses one that does
# not with exit 2, as its floors do: so the floor arms below ask for each
# floor's own words too).
AV_WHY="the selftest corpus is about stdout"
av_run() { "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/$1.sh" \
	--oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 0; }

want_green "argv_check: a program matching the reference passes" -- av_run good
want_red   "argv_check: a newline BETWEEN arguments is caught"   -- av_run nonl
want_red   "argv_check: stopping at an empty argument is caught" -- av_run stopsempty
want_green "argv_check: a program that reads stdin is not starved" -- av_run eatsstdin

# THE REPORT, byte for byte. A missing final newline is named as one even when
# the lines, sorted, are the same -- it used to be called wrong-order, printed
# as expected and got lines that looked identical -- and a byte a terminal
# cannot show is printed as an escape rather than raw.
av_show() { "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/$1.sh" \
	--oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 40; }
want_out   "argv_check: a missing final newline is named as one" \
	'missing-final-newline' -- av_show nonl
want_broken_none "argv_check: ...and never called wrong-order" 'wrong-order' -- av_show nonl
want_out   "argv_check: ...and the unterminated line is marked" \
	'(no newline at end)' -- av_show nonl
want_out   "argv_check: the right lines in another order are wrong-order" \
	'wrong-order' -- av_show rotates
want_out   "argv_check: a byte above 0x7f is printed in hex" '\x80' -- av_show rotates
want_out   "argv_check: ...0xff too, beside it" '\x80\xff' -- av_show rotates
want_out   "argv_check: ...and a control byte" '\x01z' -- av_show rotates
# A trailing space is a byte like any other. The rendering used to trim the
# last space of the whole line, meant for the separator after the last $, and
# took a real one with it: [ab] beside an expected line showing "ab $".
want_out   "argv_check: an argument's trailing space is kept" '[ab ]' -- av_show rotates
want_out   "argv_check: ...and an unterminated line's" \
	'x$ ab  (no newline at end)' -- av_show nonl
want_out   "argv_check: a dollar in an argument is \x24" '[c\x24]' -- av_show rotates
# The legend names the marks the shown lines hold (rl_shown_legend), and no
# other: a fixed one named a newline and a backslash whatever was shown.
want_out   "argv_check: the legend names the marks the shown lines hold" \
	'(byte for byte: \t a tab, \x24 a dollar, and \xHH' -- av_show rotates
want_broken_none "argv_check: ...and none they do not" 'backslash' -- av_show rotates
want_broken_none "argv_check: ...nor any where they hold no mark" 'a tab' -- av_show stopsempty
# grep's own exit status is the verdict: 1 (no raw byte found) is what passes.
# Only the case lines are searched: the verdict line's em dash is UTF-8, and
# so bytes above 0x7f, on purpose. A run with no case line to search is 2, a
# check that never ran: piped straight into the search, an empty stream (the
# runner said nothing, or its case lines changed their margin) was grep's 1,
# the verdict that passes.
av_raw() {
	_avl=$(av_show rotates | LC_ALL=C grep -E '^    (argv|expected|got):') || {
		echo "av_raw: the report holds no case line to search" >&2
		return 2
	}
	printf '%s\n' "$_avl" | LC_ALL=C grep -q "$(printf '[\200-\377]')"
}
want_red   "argv_check: no raw byte above 0x7f reaches a case line" -- av_raw
want_out   "argv_check: the property every failing case shares is named" \
	'above 0x7f' -- av_show dropshigh
want_broken_none "argv_check: ...and only that one" 'control byte' -- av_show dropshigh
# The premise false: no family line where the failures share nothing, or where
# there is only one failure to generalise from.
want_broken_none "argv_check: failures sharing nothing get no family line" \
	'what the failing cases share' -- av_show nonl
want_broken_none "argv_check: one failing case is not a family" \
	'what the failing cases share' -- av_show stopsempty
# --note is gone: it said why C 06 ex03 sits at robust, which a raised
# test's runner now prints from docs/reference.md's row (rl__raised), the
# one place for it.
want_broken "argv_check: --note, a second place for a level's reason, is refused" \
	'unknown option: --note' -- "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/good.sh" \
	--oracle "$WORK/av/oracle.sh" --fn fixture --show 0 --stderr-ignored "$AV_WHY" \
	--note 'This target sits at a level of its own.'
# The exit status, by the rule in docs/reference.md ("Run contract"): noted
# here, failed only by the robust exit-status target.
want_green "argv_check: right bytes then a plain non-zero exit passes" -- av_run exits3
want_out   "argv_check: ...and says so in a note" 'from your subject names an exit' -- av_show exits3
want_out   "argv_check: ...naming the twin that fails it" '_argv_diff_exit' -- av_show exits3
# 128 is a return. It was counted as a crash and printed "killed by signal 0",
# where argv_table.sh and progname_test.sh both call it a plain return.
want_green "argv_check: exit 128 is a return, not a signal" -- av_run exits128
want_out   "argv_check: ...and is noted as one" 'from your subject names an exit' -- av_show exits128
# 255 is `return (-1);`, which the shell's 128+N reading called a death by
# signal 127. The runner asks tools/exit_status how each run ended instead.
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done\nexit 255\n' \
	> "$WORK/av/exits255.sh"
chmod +x "$WORK/av/exits255.sh"
want_green "argv_check: exit 255 is a return, not a signal" -- av_run exits255
want_broken_none "argv_check: ...and never called one" 'signal' -- av_show exits255
# A run that never started (diff_output's fixture): a harness error, not a
# case that printed nothing.
want_broken "argv_check: a program exec cannot start is refused" 'could not be started' -- \
	"$SH" "$TOOLS/argv_check.sh" --bin "$WORK/noint" \
		--oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 0

# A LONG CASE IS SHOWN CUT. C 06's corpora hold an argument of 5000 bytes and
# a list of 1100 arguments (finding 041), and a failing case printed each
# whole: every argument in the argv: line, the replay line with all of them,
# and an expected line of 5000 bytes. Here the toy's corpus gains the two, and
# a program wrong on every case shows each one cut: its first arguments, each
# to its first 300 bytes, the rest counted, its output lines cut the same way,
# and the replay line, which cannot be cut and still run, kept as a file.
{
	cat "$WORK/av/corpus.tsv"
	LC_ALL=C awk 'BEGIN {
		s = ""
		for (i = 0; i < 5000; i++) s = s "x"
		printf "args\t2\t%s\ty\t%s\\ny\\n\n", s, s
		printf "args\t1100"
		for (i = 0; i < 1100; i++) printf "\ta%d", i
		printf "\t"
		for (i = 0; i < 1100; i++) printf "a%d\\n", i
		printf "\n"
	}'
} > "$WORK/av/long.tsv"
printf "#!/bin/sh\ncat '%s'\n" "$WORK/av/long.tsv" > "$WORK/av/long_oracle.sh"
chmod +x "$WORK/av/long_oracle.sh"
av_long() { env "$@" "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/nonl.sh" \
	--oracle "$WORK/av/long_oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 0; }
_av_xs=$(LC_ALL=C awk 'BEGIN { for (i = 0; i < 400; i++) printf "x" }')
want_broken_none "argv_check: a 5000-byte argument is not printed whole" "$_av_xs" -- av_long
want_out "argv_check: ...its rendering says how much was left out" '... (4700 more bytes)' -- av_long
want_out "argv_check: ...and its output line too" '[... line cut here, 4700 more bytes]' -- av_long
want_broken_none "argv_check: 1100 arguments are not listed whole" '[a1099]' -- av_long
want_out "argv_check: ...the ones left out are counted" '... and 1080 more arguments' -- av_long
want_out "argv_check: ...and a long replay line is kept as a file" \
	'replay:   sh bazel-testlogs/mod/ex00_argv_diff/test.outputs/replay-case-' -- \
	av_long TEST_UNDECLARED_OUTPUTS_DIR="$WORK/av/out" TEST_TARGET=//mod:ex00_argv_diff

# A BYTE MATCH IS NOT A PASS IF THE PROGRAM THEN DIED. This runner compared
# output and nothing else, so a deliverable printing the right bytes and
# segfaulting on the way out was "every one byte-identical to the reference".
# Demonstrated on the real c-06 ex01 deliverable: a copy crashing only on an
# argv byte above 0x7f died on 134 of 200 cases and was green in every layer
# that exercise owns.
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done\nkill -SEGV $$\n' \
	> "$WORK/av/crashes.sh"
chmod +x "$WORK/av/crashes.sh"
want_red "argv_check: right bytes then a SEGV is not a pass" -- av_run crashes

# THE TIME BUDGET. This runner ran every case with no limit at all (finding
# 066): one argument list that sent a program into a loop hung the layer until
# Bazel killed it, with nothing in the log. Two limits now, both said aloud:
# each case's own (ARGV_TIMEOUT), after three of which the sweep stops rather
# than spend the test rediscovering the same hang; and the test's own.
printf '#!/bin/sh\nexec sleep 20\n' > "$WORK/av/hangs.sh"
printf '#!/bin/sh\nsleep 1\nfor a in "$@"; do printf "%%s\\n" "$a"; done\n' > "$WORK/av/slow.sh"
chmod +x "$WORK/av/hangs.sh" "$WORK/av/slow.sh"
later_red_out "argv_check: three runs over their own cap stop the sweep" \
	'STOPPED after 3 runs' -- env ARGV_TIMEOUT=1 "$SH" "$TOOLS/argv_check.sh" \
		--bin "$WORK/av/hangs.sh" --oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 0
# The case's own cap raised past the test's budget, so the TEST's limit is the
# one that stops case 1.
later_red_out "argv_check: the test's own limit stops it too, naming the case" \
	'an infinite loop, or too slow on case 1 of' -- \
	$SHORT ARGV_TIMEOUT=20 "$SH" "$TOOLS/argv_check.sh" \
		--bin "$WORK/av/hangs.sh" --oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 0
# Every case finishes, slowly, and the sweep outgrows the test's limit with
# nothing wrong so far: still never a pass, and not blamed on one case.
later_red_out "argv_check: a sweep that ran out of time is never a pass" \
	'were not tried' -- \
	$SHORT "$SH" "$TOOLS/argv_check.sh" \
		--bin "$WORK/av/slow.sh" --oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 0
# The first case runs past its own 2 s, every other takes a second, and the
# test's limit stops the sweep: that run is named, never one of the cases
# "judged wrong before that" (V84, ruling R4). mkdir makes "the first run"
# one run, whichever argument list it is handed.
printf '#!/bin/sh\nmkdir "$0.first" 2> /dev/null && exec sleep 20\nsleep 1\nfor a in "$@"; do printf "%%s\\n" "$a"; done\n' \
	> "$WORK/av/hang_first.sh"
chmod +x "$WORK/av/hang_first.sh"
later_red_none "argv_check: a run past its own limit is not judged wrong at a stop" \
	'judged wrong before that' -- \
	$SHORT ARGV_TIMEOUT=2 "$SH" "$TOOLS/argv_check.sh" \
		--bin "$WORK/av/hang_first.sh" --oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 0
# ...and with no stop at all (V85): the case whose first argument is a waits
# past its own 2 s, every other case is right, and the verdict counted that run
# among the cases that "differ from the reference". It did not finish, so it
# is said apart, red, and never judged (ruling R4).
printf '#!/bin/sh\n[ "$1" = a ] && exec sleep 20\nfor a in "$@"; do printf "%%s\\n" "$a"; done\n' \
	> "$WORK/av/hang_a.sh"
chmod +x "$WORK/av/hang_a.sh"
av_hang_a() { env ARGV_TIMEOUT=2 "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/hang_a.sh" \
	--oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 0; }
later_red_out "argv_check: a run past its own limit is counted apart" \
	'and 1 did not finish within 2s each' -- av_hang_a
later_red_none "argv_check: ...never as a difference" 'differ from the reference' -- av_hang_a
later_term "argv_check: SIGTERM ends it, cleaned up, with 143" -- \
	"$SH" "$TOOLS/argv_check.sh" \
		--bin "$WORK/av/slow.sh" --oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 0

# --exit-only, the robust twin: the SAME corpus, and only how each run ended.
# The bytes are the strict layer's business, so a wrong output returning 0
# passes here.
av_exit() { "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/$1.sh" \
	--oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show "${2:-0}" --exit-only; }
want_red   "argv_check: --exit-only fails a non-zero return" -- av_exit exits3
want_out   "argv_check: ...naming the status" 'returned 3' -- av_exit exits3 40
want_red   "argv_check: --exit-only fails 128 too" -- av_exit exits128
want_red   "argv_check: --exit-only fails a SEGV" -- av_exit crashes
want_green "argv_check: --exit-only ignores wrong bytes" -- av_exit nonl
want_green "argv_check: --exit-only passes a correct program" -- av_exit good
want_out   "argv_check: --exit-only's legend is read off its argv lines" \
	'(byte for byte: \n a line break inside one value, \t a tab, \x24 a dollar, and \xHH' -- \
	av_exit exits3 40
want_broken_none "argv_check: ...and names no mark they do not hold" 'backslash' -- av_exit exits3 40
want_out   "argv_check: --exit-only's headline counts the runs that did not return 0" \
	'19 of 19 cases did not return 0' -- av_exit exits3
# A sweep the test's limit stops before its first case (TEST_TIMEOUT=1, less
# a margin of 1, leaves no time to start one) judged nothing wrong, and says
# so in the mode's own terms: --exit-only compares nothing with the reference.
av_start() { env TEST_TIMEOUT=1 RL_MARGIN=1 "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/good.sh" \
	--oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 0 "$@"; }
want_out   "argv_check: a sweep stopped before it judged anything says none differed" \
	'None of the 0 case(s) that ran differed from the reference.' -- av_start
want_out   "argv_check: ...and under --exit-only, that every one returned 0" \
	'Every one of the 0 case(s) that ran returned 0.' -- av_start --exit-only

# A FAILING CASE CAN BE RUN AGAIN (finding 158's pattern, for every program
# differential): its arguments as a command line giving back their exact
# bytes, beside the rendering meant for reading.
av_keep() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/av/out$1" TEST_TARGET=//mod:ex01_argv_diff \
	DIFF_MAX_ROWS="$1" "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/nonl.sh" \
	--oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY"; }
want_out "argv_check: a failing case says how to replay it" \
	"replay:   ./a.out 'a' 'b' 'c'" -- av_keep 0
# DIFF_MAX_ROWS, the one knob (finding 167): this runner showed 8, hard-coded.
want_out "argv_check: DIFF_MAX_ROWS caps the cases it prints" \
	'more failing case(s) not shown here; all' -- av_keep 2
want_out "argv_check: ...and says how to see more" \
	'Raise with --test_env=DIFF_MAX_ROWS=N' -- av_keep 2
want_green "argv_check: ...keeping every one in test.outputs" -- \
	grep -q "replay:   ./a.out 'x9' 'y9'" "$WORK/av/out2/differences.txt"
# A leading zero is read as the number it writes, by every reader of it: the
# test of how many were printed and the count of those left out.
_av8=""
! st_mine || _av8=$(av_keep 8 2>&1 | grep -o '[0-9]* more failing case(s) not shown here')
want_out "argv_check: DIFF_MAX_ROWS=08 is eight, as 8 is" "${_av8:-a tally under DIFF_MAX_ROWS=8}" -- av_keep 08
# stderr is never graded, and a case that wrote to it is said (finding 156).
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done\necho "debug" >&2\n' \
	> "$WORK/av/noisy.sh"
chmod +x "$WORK/av/noisy.sh"
want_green "argv_check: a program that also writes to stderr passes" -- av_run noisy
want_out   "argv_check: ...and the report says so" 'also wrote to standard error (not graded' -- \
	av_run noisy
# THE CORPUS UNDER A SANITIZER (finding 113), which judges memory and endings,
# never bytes. The fake writes what ASan writes and ends as abort_on_error
# ends a run, on one argument only.
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" != x3 ] || { echo "==1==ERROR: AddressSanitizer: stack-buffer-overflow" >&2; kill -ABRT $$; }; done\nexit 0\n' \
	> "$WORK/av/san.sh"
chmod +x "$WORK/av/san.sh"
av_san() { "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/$1.sh" --oracle "$WORK/av/oracle.sh" \
	--fn fixture --sanitized; }
want_red   "argv_check --sanitized: a sanitizer report is red" -- av_san san
want_out   "argv_check --sanitized: ...naming the case and its argv" "replay:   ./a.out 'x3' 'y3'" -- \
	av_san san
want_out   "argv_check --sanitized: ...with the report" 'stack-buffer-overflow' -- av_san san
want_green "argv_check --sanitized: wrong bytes, memory-clean, are not its finding" -- av_san nonl
want_red   "argv_check --sanitized: a crash is" -- av_san crashes
want_broken "argv_check: --sanitized and --exit-only are two targets" 'two targets, not one' -- \
	"$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/good.sh" --oracle "$WORK/av/oracle.sh" \
		--fn fixture --sanitized --exit-only
# WHAT THE SANITIZER COULD SEE OF THE ARGUMENTS (finding 071): on the plain
# ASan build they lie where the kernel put them, unwatched, and a pass there
# said nothing of it -- C 06 ex03's corpus twins passed a comparison running
# past an argument's terminator. The verdict says which build ran.
want_out   "argv_check --sanitized: a pass says the arguments were unwatched" \
	'Reads inside the argument strings, or past argv'"'"'s end, are invisible' -- av_san nonl
want_out   "argv_check --guarded-argv: ...and on the guarded build, watched" \
	'a read past an argument'"'"'s end, or past argv[argc], is a report' -- \
	"$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/nonl.sh" --oracle "$WORK/av/oracle.sh" \
		--fn fixture --sanitized --guarded-argv
want_broken "argv_check: --guarded-argv goes with --sanitized" 'it needs --sanitized' -- \
	"$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/good.sh" --oracle "$WORK/av/oracle.sh" \
		--fn fixture --guarded-argv --stderr-ignored "$AV_WHY"
# Under a checker the mode is the stderr choice (tools/runner_lib.sh,
# rl_stderr_choice): stderr carries the checker's report, and a choice beside
# it would claim a judgement of the output the replay never makes.
want_green "argv_check --sanitized: no stderr choice is asked for" -- av_san nonl
want_broken "argv_check --sanitized: ...and one given anyway is refused" \
	"under --sanitized standard error carries the checker's report" -- \
	"$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/good.sh" --oracle "$WORK/av/oracle.sh" \
		--fn fixture --sanitized --stderr-ignored "$AV_WHY"
# A REPORT'S FRAMES NAME A FILE AND A LINE (V16): the corpus runners' ASan
# twins were handed no symbolizer, so every frame was a bare offset into a
# binary in Bazel's cache. A real ASan build of an invented program that
# reads one byte past a heap block on the argument x3; the pinned symbolizer
# reaches the report through rl_mem_opt, and without it the frames stay
# bare (symbolize=0, never one from PATH).
cat > "$WORK/av/heap_toy.c" <<'HEAP_TOY'
#include <stdlib.h>
#include <string.h>

int	main(int argc, char **argv)
{
	volatile char	c;
	char			*b;
	int				i;

	i = 1;
	while (i < argc)
	{
		if (strcmp(argv[i], "x3") == 0)
		{
			b = malloc(3);
			memcpy(b, "abc", 3);
			c = b[3];
			(void)c;
			free(b);
		}
		i++;
	}
	return (0);
}
HEAP_TOY
# On a box that can build a sanitized program at all (selftest.sh, THE
# SANITIZER PROBE, which refuses NO_SKIP=1 where it cannot); a toy that does
# not build there is toy_cc's FAIL.
if [ "$SAN" != 1 ]; then
	st_skipped "argv_check --sanitized: (sanitizer build unavailable)" skipped
elif toy_cc "$WORK/av/heap_toy" -g -fsanitize=address,undefined -fno-sanitize-recover=all -fuse-ld=bfd \
		"$WORK/av/heap_toy.c"; then
	av_heap() { "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/heap_toy" --oracle "$WORK/av/oracle.sh" \
		--fn fixture --sanitized "$@"; }
	want_red   "argv_check --sanitized: a heap read past a block is red" -- av_heap
	want_out   "argv_check --sanitized: ...its frames named by file and line" 'heap_toy.c:' -- \
		av_heap --symbolizer "$SYMBOLIZER" --symbolizer-lib "$SYMBOLIZER_LIB"
	want_broken_none "argv_check --sanitized: ...and with no --symbolizer, bare" 'heap_toy.c:' -- \
		av_heap
	# The symbolizer's link lives in a folder of the runner's, which it
	# removes as it does every other scratch file: run by hand, with no
	# Bazel tmp thrown away after it, each run left one in TMPDIR.
	av_symtmp() {
		rm -rf "$WORK/av/symtmp" && mkdir "$WORK/av/symtmp" || return 2
		TMPDIR="$WORK/av/symtmp" av_heap --symbolizer "$SYMBOLIZER" \
			--symbolizer-lib "$SYMBOLIZER_LIB" > /dev/null 2>&1
		[ "$?" -eq 1 ] || { echo "the run did not go red"; return 1; }
		_av_left=$(ls -A "$WORK/av/symtmp")
		[ -z "$_av_left" ] && return 0
		echo "left in TMPDIR: $_av_left"
		return 1
	}
	want_green "argv_check --sanitized: ...and leaves nothing in TMPDIR" -- av_symtmp
fi
want_broken "argv_check: --symbolizer goes with --sanitized" 'go with --sanitized' -- \
	"$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/good.sh" --oracle "$WORK/av/oracle.sh" \
		--fn fixture --stderr-ignored "$AV_WHY" --symbolizer "$SYMBOLIZER" --symbolizer-lib "$SYMBOLIZER_LIB"

# An argument ending in a newline must reach the program INTACT. The decode
# strips a sentinel rather than relying on command substitution, which strips
# every trailing newline -- and getting that wrong reported eleven of a hundred
# and twenty CORRECT cases as differences.
want_out "argv_check: a trailing newline survives the decode" \
	'PASS' -- av_run good

# The floors. Each names a corpus that would be passed by a program doing none
# of what the exercise asks, and each is exit 2: a corpus that cannot fail
# anything is a broken harness, not a wrong deliverable. Exit 2 is every
# refusal's, an unknown option's too, so each arm asks for its floor's own
# sentence (want_broken), over a corpus that lacks what that floor names
# and nothing else: the runner asks in turn, and a corpus lacking two
# things is refused by the first, the other floor reached by no arm.
av_floor() {  # av_floor CORPUS [extra args...] -- argv_check over CORPUS, good.sh replaying it
	printf "#!/bin/sh\ncat '%s'\n" "$1" > "$WORK/av/oracle_f.sh"
	chmod +x "$WORK/av/oracle_f.sh"
	shift
	"$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/good.sh" \
		--oracle "$WORK/av/oracle_f.sh" --fn fixture --stderr-ignored "$AV_WHY" "$@"
}
# av_without PROPERTY -- corpus.tsv without its cases that hold PROPERTY: no
# argument at all (zero), two or more (multi), an empty argument (empty), an
# argument written with an escape (escape); or with every case's expected
# block emptied (output). What is left keeps every other property and
# clears the count, but for multi: two cases are left, neither with an
# empty argument, and its arm adds them.
av_without() {
	awk -F '\t' -v p="$1" 'BEGIN { OFS = FS }
		{
			n = $2 + 0
			if (p == "zero" && n == 0) next
			if (p == "multi" && n >= 2) next
			for (i = 3; i < 3 + n; i++) {
				if (p == "empty" && $i == "") next
				if (p == "escape" && $i ~ /\\/) next
			}
			if (p == "output") $NF = ""
			print
		}' "$WORK/av/corpus.tsv"
}

: > "$WORK/av/empty.tsv"
want_broken "argv_check: an EMPTY corpus is a harness error, not 0/0" \
	'fewer than the 12 this layer needs' -- av_floor "$WORK/av/empty.tsv"

# No argument is empty: a program that stops at the first empty string passes.
av_without empty > "$WORK/av/noedge.tsv"
want_broken "argv_check: a corpus with no empty argument is refused" \
	'no EMPTY argument' -- av_floor "$WORK/av/noedge.tsv"
# Every case has an argument: one that prints a newline for none passes.
av_without zero > "$WORK/av/nozero.tsv"
want_broken "argv_check: ...and one with no case of zero arguments" \
	'no case with ZERO arguments' -- av_floor "$WORK/av/nozero.tsv"
# No case has two arguments: one that prints only its first passes. The
# cases of one argument or none, an empty argument and filler beside them.
{
	av_without multi
	printf 'args\t1\t\t\\n\n'
	_i=0
	while [ "$_i" -lt 10 ]; do
		printf 'args\t1\tx%s\tx%s\\n\n' "$_i" "$_i"
		_i=$((_i + 1))
	done
} > "$WORK/av/nomulti.tsv"
want_broken "argv_check: ...and one with no case of two arguments" \
	'no case with two or more arguments' -- av_floor "$WORK/av/nomulti.tsv"
# No argument needs an escape: whitespace and high bytes go untested.
av_without escape > "$WORK/av/noescape.tsv"
want_broken "argv_check: ...and one with no argument to escape" \
	'no argument needing an escape' -- av_floor "$WORK/av/noescape.tsv"
# Every expected block is empty: a program that prints nothing passes.
av_without output > "$WORK/av/nooutput.tsv"
want_broken "argv_check: ...and one whose every expected block is empty" \
	'every expected block is empty' -- av_floor "$WORK/av/nooutput.tsv"

# --expect-reordering on a corpus whose every expected block is its arguments in
# the order given: that corpus is passed by a program that reverses and sorts
# nothing at all, so the two arms that ask for reordering must refuse it.
want_broken "argv_check: --expect-reordering refuses an in-order corpus" \
	'no case where the output order differs from the input order' -- \
	av_floor "$WORK/av/corpus.tsv" --expect-reordering

# A CORPUS WHOSE LAST LINE HAS NO NEWLINE. `while read` never sees that line,
# and wc -l, which counts newlines, did not count it either, so the two agreed
# and the replay reported a pass one case short -- here, the one case good.sh
# gets wrong. The partial-replay guard counts the corpus as rl_corpus_lines
# does, and refuses.
{ cat "$WORK/av/corpus.tsv"; printf 'args\t1\tlast\tnever-printed\\n'; } > "$WORK/av/unterminated.tsv"
want_broken "argv_check: a corpus whose last line has no newline is refused" \
	'Refusing to report on a partial replay' -- av_floor "$WORK/av/unterminated.tsv" --show 0
# AN EXPECTED BLOCK HOLDING A NUL reaches the comparison whole. It was decoded
# through a shell variable, which drops a NUL, so a program printing the byte
# was told it differed. An argument cannot hold a NUL, so this toy prints one
# for an argument "@", and the corpus gains a case asking for it.
{ cat "$WORK/av/corpus.tsv"; printf 'args\t1\t@\t\\0000\\n\n'; } > "$WORK/av/nul.tsv"
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done | tr "@" "\\000"\n' > "$WORK/av/nul.sh"
chmod +x "$WORK/av/nul.sh"
printf "#!/bin/sh\ncat '%s'\n" "$WORK/av/nul.tsv" > "$WORK/av/nul_oracle.sh"
chmod +x "$WORK/av/nul_oracle.sh"
want_green "argv_check: an expected NUL byte is kept in the comparison" -- \
	"$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/nul.sh" --oracle "$WORK/av/nul_oracle.sh" \
		--fn fixture --stderr-ignored "$AV_WHY" --show 0

cp "$STANDIN_BIN" "$WORK/av/built_nothing.sh"
want_red   "argv_check: a stand-in is red"                     -- av_run built_nothing
want_out   "argv_check: ...says the code did not build" "$STANDIN_SAYS" -- av_run built_nothing
want_green "argv_check --sanitized: a stand-in is a SKIP" -- \
	env -u NO_SKIP "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/built_nothing.sh" \
		--oracle "$WORK/av/oracle.sh" --fn fixture --sanitized
want_red   "argv_check --sanitized: ...and NO_SKIP=1 turns it red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/built_nothing.sh" \
		--oracle "$WORK/av/oracle.sh" --fn fixture --sanitized

# STANDARD ERROR, A CHOICE AT EVERY CALL (review of WP-50). This runner threw
# stderr away on every run; now the call says what it is held to, and a
# message about a valid input fails where it says --stderr-empty.
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done\necho "a note" >&2\n' \
	> "$WORK/av/chatty.sh"
chmod +x "$WORK/av/chatty.sh"
av_err() { "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/$1.sh" \
	--oracle "$WORK/av/oracle.sh" --fn fixture --show 3 --stderr-empty; }
want_broken "argv_check: a call that says nothing of stderr refuses" \
	'say what standard error is held to' -- \
	"$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/good.sh" --oracle "$WORK/av/oracle.sh" --fn fixture
want_broken "argv_check: ...and one that says both" 'both given' -- \
	"$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/good.sh" --oracle "$WORK/av/oracle.sh" \
	--fn fixture --stderr-empty --stderr-ignored "$AV_WHY"
want_green "argv_check: a message on stderr is not judged unless asked" -- av_run chatty
want_out   "argv_check: ...and the PASS line says why" \
	'not judged: the selftest corpus is about stdout' -- av_run chatty
want_red   "argv_check: --stderr-empty fails a message about a valid input" -- av_err chatty
want_out   "argv_check: ...naming the fault" 'wrote-to-stderr' -- av_err chatty
want_out   "argv_check: ...showing what it wrote" 'a note' -- av_err chatty
want_out   "argv_check: ...its headline says what it did" \
	'wrote to standard error; their output was right' -- av_err chatty
want_green "argv_check: --stderr-empty passes a quiet correct program" -- av_err good
# --exit-only judges how each run ended and never reads standard error, so
# with --stderr-empty its PASS line said nothing reached standard error over
# a program that wrote to it on every case. The pair is refused.
want_broken "argv_check: --exit-only with --stderr-empty is refused" \
	'--exit-only judges only how each run ended' -- \
	"$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/chatty.sh" --oracle "$WORK/av/oracle.sh" \
	--fn fixture --show 0 --exit-only --stderr-empty

# THE GATE (V251): the replay waits for the exercise's own output test, as
# every other corpus runner does, and SKIPs while it is red -- a fresh stub
# showed these replays red at strict beside its table, which no list of a
# stub's reds named. The program under test is nonl.sh, red whenever it runs.
# Gate one is a diff_output.sh case over good.sh, which prints nothing when
# run with no argument: an empty fixture is green, av_gate_no.txt red. Gate
# two is the argument table (c_argv_table's exNN_output), handed its rows
# with --gate-scenarios: good.sh passes av_gate_ok.tbl and fails av_gate_no.tbl.
: > "$WORK/av/av_gate_ok.txt"
printf 'x\n' > "$WORK/av/av_gate_no.txt"
printf 'two\ta\tb\n' > "$WORK/av/av_gate.scn"
printf 'two\ta | b\n' > "$WORK/av/av_gate_ok.tbl"
printf 'two\tb | a\n' > "$WORK/av/av_gate_no.tbl"
av_gate() {  # av_gate NO_SKIP-VALUE [gate options...]
	_avg=$1; shift
	env -u NO_SKIP ${_avg:+NO_SKIP=$_avg} "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/nonl.sh" \
		--oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 0 "$@"
}
AV_GD="$TOOLS/diff_output.sh"
AV_GT="$TOOLS/argv_table.sh"
want_green "argv_check: SKIPs while its output test is red" -- \
	av_gate '' --gate-differ "$AV_GD" --gate-bin "$WORK/av/good.sh" --gate-expected "$WORK/av/av_gate_no.txt"
want_out   "argv_check: ...naming the test it waits for" \
	"SKIP — ex01_output, this exercise's own output fixture, is not passing yet" -- \
	av_gate '' --gate-differ "$AV_GD" --gate-bin "$WORK/av/good.sh" --gate-expected "$WORK/av/av_gate_no.txt" \
	--gate-label ex01_output
want_out   "argv_check: ...a part's fixture" \
	"SKIP — ex01_output, this part's own output fixture, is not passing yet" -- \
	with_kind part av_gate '' --gate-differ "$AV_GD" --gate-bin "$WORK/av/good.sh" \
	--gate-expected "$WORK/av/av_gate_no.txt" --gate-label ex01_output
want_red   "argv_check: ...and runs once that test is green" -- \
	av_gate '' --gate-differ "$AV_GD" --gate-bin "$WORK/av/good.sh" --gate-expected "$WORK/av/av_gate_ok.txt"
want_red   "argv_check: ...or when NO_SKIP=1 forces it open" -- \
	av_gate 1 --gate-differ "$AV_GD" --gate-bin "$WORK/av/good.sh" --gate-expected "$WORK/av/av_gate_no.txt"
want_green "argv_check: a red argument table as its gate SKIPs" -- \
	av_gate '' --gate-differ "$AV_GT" --gate-bin "$WORK/av/good.sh" --gate-expected "$WORK/av/av_gate_no.tbl" \
	--gate-scenarios "$WORK/av/av_gate.scn"
want_red   "argv_check: ...and a green one runs" -- \
	av_gate '' --gate-differ "$AV_GT" --gate-bin "$WORK/av/good.sh" --gate-expected "$WORK/av/av_gate_ok.tbl" \
	--gate-scenarios "$WORK/av/av_gate.scn"
want_red   "argv_check: ...a table handed no rows cannot answer, so it runs" -- \
	av_gate '' --gate-differ "$AV_GT" --gate-bin "$WORK/av/good.sh" --gate-expected "$WORK/av/av_gate_no.tbl"
want_broken "argv_check: --gate-label with no gate refuses" 'a gate needs' -- \
	av_gate '' --gate-label ex01_output
want_broken "argv_check: ...as does --gate-scenarios with no gate" 'a gate needs' -- \
	av_gate '' --gate-scenarios "$WORK/av/av_gate.scn"
want_broken "argv_check: ...or a gate with no --gate-bin" 'a gate needs' -- \
	av_gate '' --gate-differ "$AV_GD" --gate-expected "$WORK/av/av_gate_no.txt"
# The SKIP is the gate's whole answer: a stand-in waits for it too, since the
# output test it waits for runs the same program and is red on it already.
want_green "argv_check: a stand-in waits for a red gate" -- \
	env -u NO_SKIP "$SH" "$TOOLS/argv_check.sh" --bin "$WORK/av/built_nothing.sh" \
		--oracle "$WORK/av/oracle.sh" --fn fixture --stderr-ignored "$AV_WHY" --show 0 \
		--gate-differ "$AV_GD" --gate-bin "$WORK/av/good.sh" --gate-expected "$WORK/av/av_gate_no.txt"

