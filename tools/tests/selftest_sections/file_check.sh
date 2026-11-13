# ------------------------------------------------------------------ file_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The runner behind c-10's diff layer. Its case is a list of flags and a list of
# FILE CONTENTS, which the runner writes to a scratch directory before running
# the binary on those paths.
mkdir -p "$WORK/fc"

# A corpus with the four things a committed fixture never has: an EMPTY file, a
# file containing a NUL, a file over 4096 bytes, and enough cases to clear the
# floor. Line shape: <tag>\t<nflags>\t<flags>\t<nfiles>\t<files>\t<expected>.
_big=$(awk 'BEGIN { s = ""; while (length(s) < 5000) s = s "abcdefghij"; print s }')
{
	printf 'file\t0\t1\t\t\n'
	printf 'file\t0\t1\ta\\0000b\ta\\0000b\n'
	printf 'file\t0\t1\t%s\t%s\n' "$_big" "$_big"
	_i=0
	while [ "$_i" -lt 20 ]; do
		printf 'file\t0\t1\tline%s\\n\tline%s\\n\n' "$_i" "$_i"
		_i=$((_i + 1))
	done
} > "$WORK/fc/corpus.tsv"
printf "#!/bin/sh\ncat '%s'\n" "$WORK/fc/corpus.tsv" > "$WORK/fc/oracle.sh"

# The fake students. Written, not run.
printf '#!/bin/sh\nfor f in "$@"; do cat "$f"; done\n' > "$WORK/fc/good.sh"
printf '#!/bin/sh\nexit 0\n' > "$WORK/fc/silent.sh"
# Stops at the first NUL, which is what a buffer treated as a C string does.
# This arm is the one that caught the runner decoding through a shell variable:
# a variable cannot hold a NUL, so the file reached the program without one and
# this program PASSED 60 of 60.
printf '#!/bin/sh\nfor f in "$@"; do tr -d "\\000" < "$f"; done\n' \
	> "$WORK/fc/eatsnul.sh"
# Reads stdin before its files: without `< /dev/null` on every run it swallows
# the rest of the corpus and the layer reports OK having checked one case.
printf '#!/bin/sh\ncat > /dev/null\nfor f in "$@"; do cat "$f"; done\n' \
	> "$WORK/fc/eatsstdin.sh"
chmod +x "$WORK/fc"/*.sh

# Every call says what stderr is held to (file_check.sh refuses one that does
# not): fc_run ignores it, as a call site whose subject says nothing of it
# would; fc_quiet holds it empty.
fc_run() {  # fc_run PROGRAM [file_check options...]
	_fc=$1; shift
	"$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/$_fc.sh" \
		--oracle "$WORK/fc/oracle.sh" --fn fixture --show 0 \
		--stderr-ignored "the selftest corpus is about stdout" "$@"
}
fc_quiet() {  # fc_quiet PROGRAM [file_check options...]
	_fc=$1; shift
	"$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/$_fc.sh" \
		--oracle "$WORK/fc/oracle.sh" --fn fixture --show 0 --stderr-empty "$@"
}

want_green "file_check: a program matching the reference passes" -- fc_run good
want_red   "file_check: a program that prints nothing is caught" -- fc_run silent
want_red   "file_check: dropping NUL bytes is caught"            -- fc_run eatsnul
want_green "file_check: a program that reads stdin is not starved" -- fc_run eatsstdin

# Same blind spot, same fix: the status is consulted on the path where the
# bytes matched, not only on the path where they did not.
printf '#!/bin/sh\nfor f in "$@"; do cat "$f"; done\nkill -SEGV $$\n' \
	> "$WORK/fc/crashes.sh"
chmod +x "$WORK/fc/crashes.sh"
want_red "file_check: right bytes then a SEGV is not a pass" -- fc_run crashes
# ...but right bytes then a return of 255 is: a status it returned, which
# waitpid() tells from a death by "signal 127" (tools/exit_status).
printf '#!/bin/sh\nfor f in "$@"; do cat "$f"; done\nexit 255\n' \
	> "$WORK/fc/ret255.sh"
chmod +x "$WORK/fc/ret255.sh"
want_green "file_check: right bytes then a return of 255 passes" -- fc_run ret255
# stderr (--stderr-empty): the reference's inputs are all valid, so where a
# call site asks, a message about one of them fails the case even when the
# bytes on stdout are right -- and only there: the Run contract ignores stderr
# unless the subject requires something of it (finding 110).
printf '#!/bin/sh\nfor f in "$@"; do cat "$f"; done\necho "cannot read" >&2\n' \
	> "$WORK/fc/chatty.sh"
chmod +x "$WORK/fc/chatty.sh"
want_green "file_check: a message on stderr is not judged unless asked" -- fc_run chatty
want_out   "file_check: ...and the PASS line says why" 'not judged: the selftest corpus is about stdout' -- \
	fc_run chatty
want_red   "file_check: --stderr-empty fails a message about a valid file" -- \
	fc_quiet chatty
want_out   "file_check: ...naming the fault" 'wrote-to-stderr' -- \
	fc_quiet chatty --show 1
want_out   "file_check: ...showing what it wrote" 'cannot read' -- \
	fc_quiet chatty --show 1
want_out   "file_check: ...and that the bytes were right" 'byte-identical to the reference' -- \
	fc_quiet chatty --show 1
want_broken_none "file_check: ...never said to differ from the reference" \
	'differ from the reference' -- fc_quiet chatty --show 1
want_out   "file_check: ...its headline says what it did" 'wrote to standard error; their output was right' -- \
	fc_quiet chatty --show 1
# ...nor under the hint on the bytes: they were right, and it read
# "a truncation ... at the first NUL" over a report with no truncation.
want_broken_none "file_check: ...nor read by the hint on truncation" \
	'a truncation at the first NUL' -- fc_quiet chatty --show 1
want_green "file_check: --stderr-empty passes a quiet program" -- fc_quiet good
# Its PASS line says what stderr was held to as every corpus runner's does
# (rl_stderr_rule), on a line of its own.
want_out   "file_check: ...its PASS line says nothing reached standard error" \
	'Nothing reached standard error on any of them, as this check requires.' -- fc_quiet good
# A RUN STOPPED FROM OUTSIDE (here its waiter, tools/exit_status, asked to
# stop) says nothing about the program: the harness failed, exit 2, as for a
# program that could not be started. It was the student's "crash".
printf '#!/bin/sh\ngrep -qx line5 "$1" && { kill -TERM $PPID; sleep 1; }\nfor f in "$@"; do cat "$f"; done\n' \
	> "$WORK/fc/waiterkilled.sh"
chmod +x "$WORK/fc/waiterkilled.sh"
want_broken "file_check: a run stopped from outside is no verdict, exit 2" \
	'could not be judged: the program was stopped from outside' -- fc_run waiterkilled
# A sweep the test's limit stops before its first case judged nothing wrong.
want_out   "file_check: a sweep stopped before it judged anything says none differed" \
	'None of the 0 case(s) that ran differed from the reference.' -- \
	env TEST_TIMEOUT=1 RL_MARGIN=1 "$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/good.sh" \
		--oracle "$WORK/fc/oracle.sh" --fn fixture --show 0 --stderr-ignored "the selftest corpus is about stdout"
# A default is not a decision: a call that says nothing of stderr, or both
# things, never ran (exit 2), and says what to pass.
want_broken "file_check: a call that does not say what stderr is held to refuses" \
	'say what standard error is held to' -- \
	"$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/good.sh" \
		--oracle "$WORK/fc/oracle.sh" --fn fixture
want_broken "file_check: ...and one that says both" 'standard error is judged, or it is not' -- \
	fc_quiet good --stderr-ignored "both"
# Both kinds of failure in one run: the headline counts each, and a case whose
# bytes differ shows its stderr as a clue, not as the fault. mixed.sh gets
# line3's file wrong and complains about line5's, which it gets right.
printf '#!/bin/sh\nfor f in "$@"; do\n\tif grep -qx line3 "$f"; then echo wrong; echo "about line3" >&2\n\telif grep -qx line5 "$f"; then cat "$f"; echo "about line5" >&2\n\telse cat "$f"; fi\ndone\n' \
	> "$WORK/fc/mixed.sh"
chmod +x "$WORK/fc/mixed.sh"
want_red   "file_check: a wrong case and a noisy one are both failures" -- fc_quiet mixed
want_out   "file_check: ...the headline counts the wrong one" '1 differ from the reference' -- \
	fc_quiet mixed --show 2
want_out   "file_check: ...and the noisy one apart" '1 more had the right output and wrote to standard error' -- \
	fc_quiet mixed --show 2
want_out   "file_check: ...the wrong one shows its stderr as a clue" 'it also wrote to standard error' -- \
	fc_run mixed --show 2
want_broken_none "file_check: ...never as the fault where stderr is ignored" \
	'where this input should get nothing' -- fc_run mixed --show 2
# The same budget as argv_check's, for the same reason (finding 066).
printf '#!/bin/sh\nexec sleep 20\n' > "$WORK/fc/hangs.sh"; chmod +x "$WORK/fc/hangs.sh"
later_red_out "file_check: a program that never ends is stopped, and said to be" \
	's: an infinite loop, or too slow on' -- $SHORT "$SH" "$TOOLS/file_check.sh" \
		--bin "$WORK/fc/hangs.sh" --oracle "$WORK/fc/oracle.sh" --fn fixture --show 0 \
		--stderr-ignored "the selftest corpus is about stdout"
# ...and a run past its own limit before the test's stops the sweep is
# named, never one of the cases "judged wrong before that" (V84, as
# argv_check's): the first run waits past its 2 s, every other takes 1 s.
printf '#!/bin/sh\nmkdir "$0.first" 2> /dev/null && exec sleep 20\nsleep 1\nfor f in "$@"; do cat "$f"; done\n' \
	> "$WORK/fc/hang_first.sh"
chmod +x "$WORK/fc/hang_first.sh"
later_red_none "file_check: a run past its own limit is not judged wrong at a stop" \
	'judged wrong before that' -- $SHORT FILE_TIMEOUT=2 "$SH" "$TOOLS/file_check.sh" \
		--bin "$WORK/fc/hang_first.sh" --oracle "$WORK/fc/oracle.sh" --fn fixture --show 0 \
		--stderr-ignored "the selftest corpus is about stdout"

# ...and with no stop at all (V85): the file holding line3 waits past its
# own 2 s, every other case is right, and the verdict counted that run among
# the cases that "differ from the reference", under the hint on a buffer
# treated as a string. It did not finish, so it is said apart, red, and
# never judged (ruling R4); no hint about the bytes reads it.
printf '#!/bin/sh\ngrep -qx line3 "$1" && exec sleep 20\nfor f in "$@"; do cat "$f"; done\n' \
	> "$WORK/fc/hang_line3.sh"
chmod +x "$WORK/fc/hang_line3.sh"
fc_hang3() { env FILE_TIMEOUT=2 "$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/hang_line3.sh" \
	--oracle "$WORK/fc/oracle.sh" --fn fixture --show 0 \
	--stderr-ignored "the selftest corpus is about stdout"; }
later_red_out "file_check: a run past its own limit is counted apart" \
	'and 1 did not finish within 2s each' -- fc_hang3
later_red_none "file_check: ...never as a difference" 'differ from the reference' -- fc_hang3
later_red_none "file_check: ...nor read by the hint on the bytes" 'a truncation at the first NUL' -- fc_hang3
# ...nor by its own case: the case block printed "first difference: byte
# 1" and the window around it, over bytes the run never finished writing.
later_red_none "file_check: ...nor shown as a first difference" 'first difference' -- fc_hang3
later_red_out "file_check: ...its case says it was not judged" \
	'not judged: a run that did not finish was not seen to its end' -- fc_hang3
# What it had printed by then is shown, as it is: here the very bytes the
# reference has, which the case once called "byte-identical to the
# reference" -- of a run nobody saw end.
printf '#!/bin/sh\nif %s -qx line3 "$1"; then %s "$1"; exec sleep 20; fi\nfor f in "$@"; do %s "$f"; done\n' grep cat cat \
	> "$WORK/fc/hang_part3.sh"
chmod +x "$WORK/fc/hang_part3.sh"
later_red_out "file_check: ...and shows what it had printed by then" \
	'what it had printed when it was stopped:' -- env FILE_TIMEOUT=2 "$SH" "$TOOLS/file_check.sh" \
		--bin "$WORK/fc/hang_part3.sh" --oracle "$WORK/fc/oracle.sh" --fn fixture --show 0 \
		--stderr-ignored "the selftest corpus is about stdout"
# ...and its got line counts those bytes as the ones it had at the stop: a
# bare "got: 6 bytes" under "expected: 6 bytes" read as a match (V144).
later_red_out "file_check: ...its got line says it was stopped" \
	'got:      6 bytes when it was stopped' -- env FILE_TIMEOUT=2 "$SH" "$TOOLS/file_check.sh" \
		--bin "$WORK/fc/hang_part3.sh" --oracle "$WORK/fc/oracle.sh" --fn fixture --show 0 \
		--stderr-ignored "the selftest corpus is about stdout"
# So does a run stopped at its output budget: what it had written by then.
printf '#!/bin/sh\nif %s -qx line3 "$1"; then exec yes; fi\nfor f in "$@"; do %s "$f"; done\n' grep cat \
	> "$WORK/fc/flood3.sh"
chmod +x "$WORK/fc/flood3.sh"
want_out "file_check: a run stopped at its output budget says so on its got line" \
	'bytes when it was stopped' -- "$SH" "$TOOLS/file_check.sh" \
		--bin "$WORK/fc/flood3.sh" --oracle "$WORK/fc/oracle.sh" --fn fixture --show 0 \
		--stderr-ignored "the selftest corpus is about stdout"

# The floors, each exit 2: a corpus that cannot fail anything is a broken
# harness rather than a wrong deliverable. Exit 2 is every refusal's, an
# unknown option's too, so each arm asks for its floor's own sentence
# (want_broken), over a corpus that lacks what that floor names and nothing
# else: the runner asks in turn, and a corpus of tame text files once
# lacked an empty file as well as a NUL and a large file, was refused for
# the empty file, and reached neither floor it was named for.
fc_floor() {  # fc_floor CORPUS [extra args...] -- file_check over CORPUS, good.sh replaying it
	printf "#!/bin/sh\ncat '%s'\n" "$1" > "$WORK/fc/oracle_f.sh"
	chmod +x "$WORK/fc/oracle_f.sh"
	shift
	"$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/good.sh" \
		--oracle "$WORK/fc/oracle_f.sh" --fn fixture --stderr-empty "$@"
}
# fc_without PROPERTY -- corpus.tsv without its cases that hold PROPERTY: an
# empty file (empty), a NUL (nul), a file over 4096 bytes (big); or with
# every case's expected block emptied (output). Each of its cases is one
# file and no flag, so the file is field 4. What is left keeps every other
# property and clears the count.
fc_without() {
	awk -F '\t' -v p="$1" 'BEGIN { OFS = FS }
		p == "empty" && $4 == "" { next }
		p == "nul" && index($4, "\\0000") { next }
		p == "big" && length($4) > 4096 { next }
		{ if (p == "output") $NF = ""; print }' "$WORK/fc/corpus.tsv"
}

: > "$WORK/fc/empty.tsv"
want_broken "file_check: an EMPTY corpus is a harness error, not 0/0" \
	'fewer than the 20 this layer needs' -- fc_floor "$WORK/fc/empty.tsv"

# No NUL: a program that stops at the first NUL passes.
fc_without nul > "$WORK/fc/tame.tsv"
want_broken "file_check: a corpus of tame text files is refused" \
	'no file containing a NUL' -- fc_floor "$WORK/fc/tame.tsv"
# Nothing large: one that reads its buffer once passes.
fc_without big > "$WORK/fc/small.tsv"
want_broken "file_check: ...and one whose every file is small" \
	'every file is small' -- fc_floor "$WORK/fc/small.tsv"
# No empty file: a read loop that never runs passes.
fc_without empty > "$WORK/fc/noempty.tsv"
want_broken "file_check: ...and one with no EMPTY file" \
	'no EMPTY file in the corpus' -- fc_floor "$WORK/fc/noempty.tsv"
# Every expected block empty: a program that prints nothing passes.
fc_without output > "$WORK/fc/nooutput.tsv"
want_broken "file_check: ...and one whose every expected block is empty" \
	'every expected block is empty' -- fc_floor "$WORK/fc/nooutput.tsv"
# A last line with no newline: `while read` never replays it, and wc -l did
# not count it, so the replay passed one case short -- here, the one case
# good.sh gets wrong. The partial-replay guard refuses it.
{ cat "$WORK/fc/corpus.tsv"; printf 'file\t0\t1\tlast\tnever-printed'; } > "$WORK/fc/unterminated.tsv"
want_broken "file_check: a corpus whose last line has no newline is refused" \
	'Refusing to report on a partial replay' -- fc_floor "$WORK/fc/unterminated.tsv" --show 0

# --expect-transform on a corpus whose output IS its input: that corpus is
# passed by `cat`, which is not what ft_tail or ft_hexdump do.
want_broken "file_check: --expect-transform refuses an identity corpus" \
	'no case whose output differs from its input' -- \
	fc_floor "$WORK/fc/corpus.tsv" --expect-transform

# --expect-substring names a thing the corpus must be able to produce -- for
# hexdump that is the `*` squeeze line, which needs sixteen identical bytes
# twice over and which no committed fixture reaches.
want_broken "file_check: --expect-substring refuses a corpus without it" \
	"no case whose expected output contains 'SQUEEZE-MARKER'" -- \
	fc_floor "$WORK/fc/corpus.tsv" --expect-substring "SQUEEZE-MARKER"

cp "$STANDIN_BIN" "$WORK/fc/built_nothing.sh"
want_red   "file_check: a stand-in is red"                     -- fc_run built_nothing
want_out   "file_check: ...says the code did not build" "$STANDIN_SAYS" -- fc_run built_nothing
want_green "file_check --sanitized: a stand-in is a SKIP" -- \
	env -u NO_SKIP "$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/built_nothing.sh" \
		--oracle "$WORK/fc/oracle.sh" --fn fixture --sanitized
want_red   "file_check --sanitized: ...and NO_SKIP=1 turns it red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/built_nothing.sh" \
		--oracle "$WORK/fc/oracle.sh" --fn fixture --sanitized

# A FAILING CASE IS SHOWN WHERE IT DIFFERS, AND CAN BE RUN AGAIN. The bytes
# were shown from the start of each file, so a program that stopped after one
# 4096-byte read had its difference 900 bytes past what the report printed;
# and the files it read were scratch files, gone with the run.
printf '#!/bin/sh\nfor f in "$@"; do %s -c 4096 "$f"; done\n' head > "$WORK/fc/oneread.sh"
chmod +x "$WORK/fc/oneread.sh"
fc_keep() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/fc/out" TEST_TARGET=//mod:ex00_file_diff \
	"$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/$1.sh" --oracle "$WORK/fc/oracle.sh" --fn fixture \
	--stderr-ignored "the selftest corpus is about stdout"; }
want_red "file_check: one read of 4096 bytes is caught" -- fc_keep oneread
want_out "file_check: ...at the byte where it stopped" 'first difference: byte 4097' -- fc_keep oneread
want_out "file_check: ...shown from just before it, not from the start" 'expected, from byte 4089:' -- \
	fc_keep oneread
want_out "file_check: ...with the command that runs it again" \
	'replay:  ./a.out case-3-file0' -- fc_keep oneread
want_green "file_check: ...on the very file it read" -- \
	"$SH" -c 'n=$(wc -c < "$1"); [ $n -eq 5000 ]' _ "$WORK/fc/out/case-3-file0"
# The bytes around it in the one rendering every runner uses (runner_lib.sh's
# rl_diff_window): `od -c` showed a byte above 0x7f as three octal digits
# ("351") where every other layer's log shows \xe9 (V14).
printf '#!/bin/sh\nfor f in "$@"; do %s l "\\351" < "$f"; done\n' tr > "$WORK/fc/hibyte.sh"
chmod +x "$WORK/fc/hibyte.sh"
want_out "file_check: a byte above 0x7f reads \\xHH, as in every layer" \
	'got,      from byte 1: \xe9ine0\n' -- fc_run hibyte --show 1
fc_caret() { fc_run hibyte --show 1 | grep -qx -- "$(printf '%27s' '')^"; }
want_green "file_check: ...with a ^ under the byte" -- fc_caret
# DIFF_MAX_ROWS (finding 167): this runner showed 6, hard-coded.
want_out "file_check: DIFF_MAX_ROWS caps the cases it prints" \
	'21 more failing case(s) not shown' -- \
	env DIFF_MAX_ROWS=1 "$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/silent.sh" \
		--oracle "$WORK/fc/oracle.sh" --fn fixture --stderr-ignored "the selftest corpus is about stdout"
# stderr is never graded, and said (finding 156).
printf '#!/bin/sh\nfor f in "$@"; do %s "$f"; done\necho "debug" >&2\n' cat > "$WORK/fc/noisy.sh"
chmod +x "$WORK/fc/noisy.sh"
want_green "file_check: a program that also writes to stderr passes" -- fc_run noisy
want_out   "file_check: ...and the report says so" 'also wrote to standard error (not graded' -- \
	fc_run noisy
# THE CORPUS UNDER A SANITIZER (finding 113): memory and endings, never bytes.
printf '#!/bin/sh\nfor f in "$@"; do n=$(%s -c < "$f"); [ $n -lt 4096 ] || { echo "==1==ERROR: AddressSanitizer: heap-buffer-overflow" >&2; kill -ABRT $$; }; done\nexit 0\n' \
	wc > "$WORK/fc/san.sh"
chmod +x "$WORK/fc/san.sh"
fc_san() { "$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/$1.sh" --oracle "$WORK/fc/oracle.sh" \
	--fn fixture --sanitized; }
want_red   "file_check --sanitized: a sanitizer report is red" -- fc_san san
want_out   "file_check --sanitized: ...on the big file's case" 'case 3  [file]  sanitizer' -- fc_san san
want_green "file_check --sanitized: wrong bytes, memory-clean, are not its finding" -- fc_san silent
want_out   "file_check --sanitized: ...and says its arguments were unwatched" \
	'Reads inside the argument strings, or past argv'"'"'s end, are invisible' -- fc_san silent
want_red   "file_check --sanitized: a crash is" -- fc_san crashes
# A report that names a file names the scratch copy the program was given;
# the case keeps it as case-N-fileK, which the report shows -- where it was
# kept. Run by hand there is nowhere to keep it, and the report named a
# file that exists nowhere.
printf '#!/bin/sh\nfor f in "$@"; do n=$(%s -c < "$f"); [ $n -lt 4096 ] || { echo "==1==ERROR: AddressSanitizer: heap-buffer-overflow while reading $f" >&2; kill -ABRT $$; }; done\nexit 0\n' \
	wc > "$WORK/fc/sanpath.sh"
chmod +x "$WORK/fc/sanpath.sh"
fc_sank() { env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/fc/outs" TEST_TARGET=//mod:ex00_file_diff_asan \
	"$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/$1.sh" --oracle "$WORK/fc/oracle.sh" --fn fixture --sanitized; }
fc_sanh() { env -u TEST_UNDECLARED_OUTPUTS_DIR "$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/$1.sh" \
	--oracle "$WORK/fc/oracle.sh" --fn fixture --sanitized; }
want_out   "file_check --sanitized: a report naming a file shows the kept name" \
	'heap-buffer-overflow while reading case-3-file0' -- fc_sank sanpath
want_out   "file_check --sanitized: ...and says it did" \
	'shown by the name it is kept under: case-3-file0)' -- fc_sank sanpath
want_out   "file_check --sanitized: by hand the file is not kept" \
	'replay:  ./a.out <file 0>' -- fc_sanh sanpath
want_broken_none "file_check --sanitized: ...and the report names no kept file" \
	'case-3-file0' -- fc_sanh sanpath

# THE GATE (V251): the replay waits for the exercise's own output test and
# SKIPs while it is red, as every other corpus runner does -- C 10's corpus
# replays were red over a fresh stub at strict, beside the output test that
# already said so. The program under test is silent.sh, red whenever it runs;
# the gate is a diff_output.sh case over good.sh, given one file as its
# --gate-arg: fc_gate_in.txt is green against itself, red against
# fc_gate_no.txt. Without that word the gate prints nothing and is red
# against either, so the arm that runs also proves the word reached it.
printf 'one line\n' > "$WORK/fc/fc_gate_in.txt"
printf 'another line\n' > "$WORK/fc/fc_gate_no.txt"
fc_gate() {  # fc_gate NO_SKIP-VALUE [gate options...]
	_fcg=$1; shift
	env -u NO_SKIP ${_fcg:+NO_SKIP=$_fcg} "$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/silent.sh" \
		--oracle "$WORK/fc/oracle.sh" --fn fixture --show 0 \
		--stderr-ignored "the selftest corpus is about stdout" "$@"
}
FC_GD="$TOOLS/diff_output.sh"
want_green "file_check: SKIPs while its output test is red" -- \
	fc_gate '' --gate-differ "$FC_GD" --gate-bin "$WORK/fc/good.sh" \
	--gate-expected "$WORK/fc/fc_gate_no.txt" --gate-arg "$WORK/fc/fc_gate_in.txt"
want_out   "file_check: ...naming the test it waits for" \
	"SKIP — ex00_show_output, this exercise's own output fixture, is not passing yet" -- \
	fc_gate '' --gate-differ "$FC_GD" --gate-bin "$WORK/fc/good.sh" \
	--gate-expected "$WORK/fc/fc_gate_no.txt" --gate-arg "$WORK/fc/fc_gate_in.txt" \
	--gate-label ex00_show_output
want_red   "file_check: ...and runs once that test is green" -- \
	fc_gate '' --gate-differ "$FC_GD" --gate-bin "$WORK/fc/good.sh" \
	--gate-expected "$WORK/fc/fc_gate_in.txt" --gate-arg "$WORK/fc/fc_gate_in.txt"
want_red   "file_check: ...or when NO_SKIP=1 forces it open" -- \
	fc_gate 1 --gate-differ "$FC_GD" --gate-bin "$WORK/fc/good.sh" \
	--gate-expected "$WORK/fc/fc_gate_no.txt" --gate-arg "$WORK/fc/fc_gate_in.txt"
want_out   "file_check --sanitized: ...and its ASan twin waits the same way" 'SKIP — ex00_show_output' -- \
	env -u NO_SKIP "$SH" "$TOOLS/file_check.sh" --bin "$WORK/fc/silent.sh" \
		--oracle "$WORK/fc/oracle.sh" --fn fixture --sanitized --gate-label ex00_show_output \
		--gate-differ "$FC_GD" --gate-bin "$WORK/fc/good.sh" \
		--gate-expected "$WORK/fc/fc_gate_no.txt" --gate-arg "$WORK/fc/fc_gate_in.txt"
want_broken "file_check: --gate-label with no gate refuses" 'a gate needs' -- \
	fc_gate '' --gate-label ex00_show_output
want_broken "file_check: ...as does --gate-arg with no gate" 'a gate needs' -- \
	fc_gate '' --gate-arg "$WORK/fc/fc_gate_in.txt"
want_broken "file_check: ...or a gate with no --gate-expected" 'a gate needs' -- \
	fc_gate '' --gate-differ "$FC_GD" --gate-bin "$WORK/fc/good.sh"

