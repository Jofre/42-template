# ----------------------------------------------------------------- argv_table
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# For c-06 ex01-ex03 this is the ONLY layer that ever executes the program: the
# verdict is delegated to diff_output.sh with --bin /bin/cat, so that script's
# crash and hang guards are watching `cat`, and everything about the real runs
# has to be judged inside argv_table.sh itself. So both halves get pinned: the
# table comparison it delegates, and the survival check it cannot delegate.
#
# Scenario lines are TAB-separated (<label><TAB><arg>...), and the table this
# produces joins each run's stdout lines with " | ", so the expected file is
# "<label><TAB>a | b". Written with printf so the tabs are real tabs — an editor
# that helpfully expanded them would turn every row into a one-argument run and
# the mismatch would look like a bug in the runner.
#
# The fake programs are shell scripts printing each argument's LENGTH, one per
# line -- a transform no exercise asks for. The runner only execs --bin, so any
# executable will do, and what is under test is the table and the survival
# check, not what the program computes. They used to be C programs printing
# argv[1..] one per line, which is c-06 ex01's answer, in a file that ships on
# the template.
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "${#a}"; done\n' \
	> "$WORK/argv_ok"
printf '#!/bin/sh\nprintf "nope\\n"\n' > "$WORK/argv_bad"
# Prints exactly the right table and THEN dies — the false green fixed in
# 3381bd0, and the shape these exercises actually fail in, since indexing and
# swapping argv pointers emits the correct bytes and crashes on the way out. The
# table it renders reads all PASS; the verdict must still come out red.
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "${#a}"; done\nkill -SEGV $$\n' \
	> "$WORK/argv_crash"
chmod +x "$WORK/argv_ok" "$WORK/argv_bad" "$WORK/argv_crash"
printf 'two\tab\tcde\none\tz\n' > "$WORK/scn.tsv"
printf 'two\t2 | 3\none\t1\n' > "$WORK/table.txt"
want_green "argv_table: the expected table passes" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_ok" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_red   "argv_table: a wrong table fails" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_bad" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_red   "argv_table: RIGHT table then a crash fails" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_crash" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"

# THE EXIT STATUS, by the same rule as the progname arms: the table notes a
# plain non-zero return and passes; --exit-only, the robust exNN_exit target,
# judges nothing but how each run ended, so it fails that return and ignores
# the table.
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "${#a}"; done\nexit 3\n' \
	> "$WORK/argv_rc"
chmod +x "$WORK/argv_rc"
want_green "argv_table: RIGHT table then a plain non-zero exit passes" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_rc" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_out   "argv_table: ...and says so in a note" 'from your subject names an exit' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_rc" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_red   "argv_table: --exit-only fails that plain non-zero exit" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_rc" --exit-only \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
# What the runs wrote to stderr is headed so only when one wrote something: a
# silent non-zero return is the EXIT STATUS block's, and was listed again
# under the stderr heading as "exit status 3", once per run (V52).
want_broken_none "argv_table: a silent non-zero return is not called stderr" 'wrote to stderr' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_rc" --exit-only \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "${#a}"; done\necho "toy says no" >&2\nexit 3\n' \
	> "$WORK/argv_rc_err"
chmod +x "$WORK/argv_rc_err"
want_out   "argv_table: ...while what a run did write is shown" 'toy says no' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_rc_err" --exit-only \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_green "argv_table: --exit-only does not judge the table" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_bad" --exit-only \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_red   "argv_table: --exit-only still fails a crash" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_crash" --exit-only \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
# A return of 255 is a return (tools/exit_status), not a death by signal 127.
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "${#a}"; done\nexit 255\n' \
	> "$WORK/argv_255"
chmod +x "$WORK/argv_255"
want_green "argv_table: RIGHT table then a return of 255 passes" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_255" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_broken_none "argv_table: ...and is not called a signal" 'signal' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_255" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
# --EMIT makes table.txt from a reference program. A clean one prints the
# table; one that returned a status other than 0 has no answer on that row,
# and --emit refused only a crash, a hang or a flood: a reference that exited
# 3 with nothing on stdout wrote a table of empty rows, and exited 0.
want_out "argv_table: --emit prints a clean reference's table" '2 | 3' -- \
	"$SH" "$TOOLS/argv_table.sh" --emit --bin "$WORK/argv_ok" \
		--scenarios "$WORK/scn.tsv"
printf '#!/bin/sh\nexit 3\n' > "$WORK/argv_rc_silent"
chmod +x "$WORK/argv_rc_silent"
want_broken "argv_table: --emit refuses a reference that returned 3" \
	'two: returned exit status 3' -- \
	"$SH" "$TOOLS/argv_table.sh" --emit --bin "$WORK/argv_rc_silent" \
		--scenarios "$WORK/scn.tsv"
want_broken "argv_table: ...and one that printed its row first" \
	'one: returned exit status 3' -- \
	"$SH" "$TOOLS/argv_table.sh" --emit --bin "$WORK/argv_rc" \
		--scenarios "$WORK/scn.tsv"
# A run that never started (diff_output's fixture): a harness error, not a
# table of empty cells.
want_broken "argv_table: a program exec cannot start is refused" 'could not be started' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/noint" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"

# A MISSING FINAL NEWLINE. Joining a run's lines with " | " drops their
# terminators, so the same lengths printed without the last newline joined to
# the same cell and passed: only a row whose last printed line was empty could
# see it (finding 035). The runner now marks the cell.
cat > "$WORK/argv_nonl" <<'NONL'
#!/bin/sh
sep=""
for a in "$@"; do
	printf '%s%s' "$sep" "${#a}"
	sep="
"
done
NONL
chmod +x "$WORK/argv_nonl"
want_red   "argv_table: the right lines with no final newline fail" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_nonl" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_out   "argv_table: ...and the cell says why" '2 | 3 [no final newline]' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_nonl" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_broken_none "argv_table: a run that ends in one is not marked" 'no final newline' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_ok" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"

# The table on a program that never built is red with the compiler's words;
# the memory-only arm steps aside, as asan_run does, unless NO_SKIP=1.
want_red "argv_table: a stand-in is red" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$STANDIN_BIN" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_out "argv_table: ...says the code did not build" "$STANDIN_SAYS" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$STANDIN_BIN" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
want_green "argv_table: --memory-only skips a stand-in" -- \
	env -u NO_SKIP "$SH" "$TOOLS/argv_table.sh" --bin "$STANDIN_BIN" --memory-only \
		--scenarios "$WORK/scn.tsv"
want_red "argv_table: ...and NO_SKIP=1 turns that skip red" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/argv_table.sh" --bin "$STANDIN_BIN" --memory-only \
		--scenarios "$WORK/scn.tsv"
# A run the sanitizer stopped is said to be one (V50): abort_on_error=1 ends
# it with SIGABRT, and the line heading its report named SIGABRT's other
# causes, an assertion, stack smashing or a glibc heap error.
printf '#!/bin/sh\necho "==1==ERROR: AddressSanitizer: stack-buffer-overflow" >&2\nkill -ABRT $$\n' \
	> "$WORK/argv_san"
chmod +x "$WORK/argv_san"
want_red "argv_table: --memory-only fails a run the sanitizer stopped" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_san" --memory-only \
		--scenarios "$WORK/scn.tsv"
want_out "argv_table: ...saying the sanitizer stopped it" 'was stopped by the sanitizer' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_san" --memory-only \
		--scenarios "$WORK/scn.tsv"
want_broken_none "argv_table: ...and not the abort's other causes" 'stack smashing' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_san" --memory-only \
		--scenarios "$WORK/scn.tsv"
# ...and what it reported, from the report's first line: every report read
# "the sanitizer reported an invalid access", a block freed twice among them.
printf '#!/bin/sh\necho "==1==ERROR: AddressSanitizer: attempting double-free on 0x602000000010 in thread T0:" >&2\nkill -ABRT $$\n' \
	> "$WORK/argv_san_twice"
chmod +x "$WORK/argv_san_twice"
want_out "argv_table: ...naming what it reported" \
	'the sanitizer reported that it freed the same block twice (double-free)' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_san_twice" --memory-only \
		--scenarios "$WORK/scn.tsv"
want_broken_none "argv_table: ...never an invalid access it was not" 'invalid access' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_san_twice" --memory-only \
		--scenarios "$WORK/scn.tsv"
# ...nor headed as one above those lines: the summary headline said
# "INVALID MEMORY ACCESS" whatever the lines under it said.
want_broken_none "argv_table: ...nor headed as an invalid access" 'INVALID MEMORY ACCESS' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_san_twice" --memory-only \
		--scenarios "$WORK/scn.tsv"

# THE GUARDED REPLAY (finding 071). argv and its strings sit where the kernel
# put them, back to back on the initial stack, which ASan does not poison: a
# read one byte past an argument's terminator reads the next argument, and the
# plain sanitizer replay says nothing. The toy below reports whether the byte
# after argv[1]'s terminator is zero (PAST=1), or the terminator itself
# (PAST=0), or whether argv[argc + 1] is set (PAST=2) -- a question no
# exercise asks. Built plainly under ASan it is green, and the OK line must
# not claim what it could not see; built as c_argv_table builds
# exNN_argvguard_bin_asan (main wrapped, tools/argv_guard_main.c beside it)
# the same reads are heap-buffer-overflow reports.
if [ "$SAN" -eq 1 ]; then
	cat > "$WORK/argvg.c" <<'ARGVG'
#include <string.h>
#include <unistd.h>

int	main(int argc, char **argv)
{
	char	c;

	c = '-';
	if (PAST == 2)
		c = (char)('0' + (argv[argc + 1] != 0));
	else if (argc > 1)
		c = (char)('0' + (argv[1][strlen(argv[1]) + PAST] != 0));
	write(1, &c, 1);
	write(1, "\n", 1);
	return (0);
}
ARGVG
	for _p in 0 1 2; do
		toy_cc "$WORK/argvg_plain$_p" -w -g -fsanitize=address -DPAST="$_p" \
			"$WORK/argvg.c"
		toy_cc "$WORK/argvg_guard$_p" -w -g -fsanitize=address -DPAST="$_p" -Wl,--wrap=main \
			"$WORK/argvg.c" "$TOOLS/argv_guard_main.c"
	done
	# A main() that reaches its closing brace returns 0: C says so of main
	# alone. The guarded build used to RENAME main (-Dmain=...), which took
	# that away, and under -Werror a correct program's guarded build failed
	# with "non-void function does not return a value" (Piscine Reloaded
	# ex18, seen merging w4-costs). Built with the warnings the student's
	# build has, it must link and replay green.
	cat > "$WORK/argvg_noret.c" <<'ARGVG_NORET'
#include <unistd.h>

int	main(int argc, char **argv)
{
	if (argc > 1)
		write(1, argv[1], 1);
	write(1, "\n", 1);
}
ARGVG_NORET
	toy_cc "$WORK/argvg_guard_noret" -Wall -Wextra -Werror -g -fsanitize=address -Wl,--wrap=main \
		"$WORK/argvg_noret.c" "$TOOLS/argv_guard_main.c"
	argvg() {  # argvg BIN [FLAG...] -- the sanitizer replay of scn.tsv
		_b=$1; shift
		"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/$_b" --memory-only \
			--scenarios "$WORK/scn.tsv" "$@"
	}
	want_green "argv_table: the plain replay cannot see a read past an argument" -- \
		argvg argvg_plain1
	want_out   "argv_table: ...so its OK line says it cannot" 'invisible here' -- \
		argvg argvg_plain1
	want_broken_none "argv_table: ...and claims no out-of-bounds check" \
		'no out-of-bounds access' -- argvg argvg_plain1
	want_red   "argv_table: the guarded replay sees that read" -- \
		argvg argvg_guard1 --guarded-argv
	want_out   "argv_table: ...as a heap-buffer-overflow" 'heap-buffer-overflow' -- \
		argvg argvg_guard1 --guarded-argv
	want_red   "argv_table: ...and a read of argv[argc + 1]" -- \
		argvg argvg_guard2 --guarded-argv
	want_green "argv_table: reading only the terminator stays green" -- \
		argvg argvg_guard0 --guarded-argv
	want_green "argv_table: a main() with no return statement builds guarded, and is green" -- \
		argvg argvg_guard_noret --guarded-argv
	want_out   "argv_table: ...and its OK line says what was guarded" \
		'heap block of exactly its size' -- argvg argvg_guard0 --guarded-argv
	want_broken "argv_table: --guarded-argv outside a sanitizer replay is refused" \
		'needs --memory-only' -- \
		"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argvg_guard0" --guarded-argv \
			--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt"
else
	# The sanitizer probe refused NO_SKIP=1 already (selftest.sh).
	st_skipped "argv_table: guarded replay (sanitizer build unavailable)" skipped
fi

# THE TABLE AS A GATE (V251). c-06's corpus replays wait for this table, so
# under a red verdict it names them (--waiting), as diff_output.sh does for
# every other output test; and rl_gate runs it as it runs any differ, its own
# words after a `--`, which takes nothing after it here: each row is a run's
# arguments, and a word there would be dropped in silence.
printf 'ex01_argv_diff (strict)\nex01_argv_diff_asan (robust)\n' > "$WORK/argv_waiting.txt"
want_out   "argv_table: a red table names the tests that wait for it" '   ex01_argv_diff_asan (robust)' -- \
	env -u NO_SKIP "$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_bad" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt" --waiting "$WORK/argv_waiting.txt"
want_out   "argv_table: ...under the --suite it is given" ' :libtoy or //...)' -- \
	env -u NO_SKIP "$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_bad" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt" --waiting "$WORK/argv_waiting.txt" \
		--suite libtoy
want_broken "argv_table: --suite without --waiting is refused" '--suite needs --waiting' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_ok" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt" --suite libtoy
want_broken "argv_table: ...and a --suite no suite can be named" "takes a suite's name" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_ok" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt" --waiting "$WORK/argv_waiting.txt" \
		--suite lib.toy
want_broken_none "argv_table: ...and a green one does not" 'WAITING FOR THIS OUTPUT' -- \
	env -u NO_SKIP "$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_ok" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt" --waiting "$WORK/argv_waiting.txt"
want_broken "argv_table: a --waiting file that is not there is refused" 'no --waiting file' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_ok" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt" --waiting "$WORK/argv_nowhere.txt"
want_green "argv_table: a closing -- is accepted" -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_ok" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt" --
want_broken "argv_table: ...and a word after it refused" 'no word goes after --' -- \
	"$SH" "$TOOLS/argv_table.sh" --bin "$WORK/argv_ok" \
		--scenarios "$WORK/scn.tsv" --expected "$WORK/table.txt" -- extra

