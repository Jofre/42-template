# ------------------------------------------------------------------- progname
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# This runner had NO arm here at all, which is why it discarded the child's exit
# status unnoticed: it diffed stdout, and a program that printed the right line
# and then died passed. The green arm is as important as the red ones — the runs
# below are what prove the added status check did not simply break the layer.
#
# The fixtures are SHELL SCRIPTS, not C. The runner only copies --bin to a known
# name and execs it as ./<name>, and a script's $0 is exactly that name -- while
# a C fixture printing its argv[0] is c-06 ex00's whole answer, which is what
# these used to be, in a file that ships on the template.
# no_raw_nul COMMAND... -- the command ran (exit 0 or 1), and nothing it
# wrote, on either stream, holds a NUL byte: a log with one is "data" to
# `file` and a binary file to grep (V51).
no_raw_nul() {
	"$@" > "$WORK/no_raw_nul.out" 2>&1
	[ "$?" -lt 2 ] || return 2
	[ "$(tr -d '\000' < "$WORK/no_raw_nul.out" | wc -c)" -eq "$(wc -c < "$WORK/no_raw_nul.out")" ]
}
printf '#!/bin/sh\nprintf "%%s\\n" "$0"\n' > "$WORK/pn_ok"
printf '#!/bin/sh\nprintf "%%s\\n" "$0"\nexit 3\n' > "$WORK/pn_rc"
printf '#!/bin/sh\nprintf "%%s\\n" "$0"\nkill -ABRT $$\n' > "$WORK/pn_abort"
printf '#!/bin/sh\nprintf "./a.out\\n"\n' > "$WORK/pn_hard"
# One byte too many: the name, a NUL, then the newline. diff calls that a binary
# file, and without -a its whole report was "Binary files X and Y differ".
printf '#!/bin/sh\nprintf "%%s\\000\\n" "$0"\n' > "$WORK/pn_nul"
# The right name, on the wrong stream.
printf '#!/bin/sh\nprintf "%%s\\n" "$0" >&2\n' > "$WORK/pn_err"
chmod +x "$WORK/pn_ok" "$WORK/pn_rc" "$WORK/pn_abort" "$WORK/pn_hard" \
	"$WORK/pn_nul" "$WORK/pn_err"

want_green "progname: prints its own name and exits 0" -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_ok"
# A binary the runner cannot copy into its scratch folder is the harness's
# fault, never a verdict on the program: exit 2.
mkdir -p "$WORK/pn_dir"
want_broken "progname: a binary it cannot copy is refused, not failed" 'cannot copy' -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_dir"
# THE EXIT STATUS, by the rule in docs/reference.md ("Run contract"): the C 06
# subject names none, so a plain non-zero return is noted at basic and failed
# only by --exit-only, which is the robust exNN_progname_exit target. A signal
# is a crash, and fails both.
want_green "progname: right line THEN a plain non-zero return passes" -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_rc"
want_out   "progname: ...and says so in a note" 'from your subject names an exit' -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_rc"
want_red   "progname: --exit-only fails that plain non-zero return" -- \
	"$SH" "$TOOLS/progname_test.sh" --exit-only --bin "$WORK/pn_rc"
want_green "progname: --exit-only does not judge what was printed" -- \
	"$SH" "$TOOLS/progname_test.sh" --exit-only --bin "$WORK/pn_hard"
want_red   "progname: right line THEN a SIGABRT fails" -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_abort"
want_red   "progname: --exit-only fails the SIGABRT too" -- \
	"$SH" "$TOOLS/progname_test.sh" --exit-only --bin "$WORK/pn_abort"
# `return (-1);` is 255, which the shell's 128+N reading called signal 127:
# the runner asks tools/exit_status instead, so it is a return, noted at basic.
printf '#!/bin/sh\nprintf "%%s\\n" "$0"\nexit 255\n' > "$WORK/pn_255"
chmod +x "$WORK/pn_255"
want_green "progname: right line THEN a return of 255 passes" -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_255"
want_broken_none "progname: ...and is not called a signal" 'signal' -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_255"
want_out   "progname: --exit-only fails it as a return" 'exited 255' -- \
	"$SH" "$TOOLS/progname_test.sh" --exit-only --bin "$WORK/pn_255"
# A run that never started (the fixture is diff_output's, above): a harness
# error, not a program that printed nothing.
want_broken "progname: a program exec cannot start is refused" 'could not be started' -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/noint"
want_red   "progname: a hardcoded \"./a.out\" fails the renamed run" -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_hard"
want_out   "progname: ...and is named as a hardcoded name" 'hardcoded' -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_hard"
# A mismatch is SHOWN, byte for byte, and explained by its cause: the hardcode
# sentence used to follow every mismatch, including these two, where the
# program does print its own argv[0].
want_red   "progname: a NUL after the name fails" -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_nul"
want_out   "progname: ...and the NUL is shown, not 'Binary files'" '\x00$' -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_nul"
want_broken_none "progname: ...and is not blamed on a hardcoded name" 'hardcoded' -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_nul"
# The unified diff above the byte views copied that NUL into the log raw, so
# `file` called test.log "data" and grep a binary file (V51): every line of
# a log goes through the one renderer, the diff's too (rl_udiff).
want_green "progname: ...and the log holds no raw NUL" -- \
	no_raw_nul "$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_nul"
want_out   "progname: the name on stderr says stdout was empty" 'nothing on stdout' -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_err"
want_broken_none "progname: ...and that is not blamed on one either" 'hardcoded' -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_err"
# A run that ended badly before it printed anything is a mismatch too, and
# its report names how it ended: it used to say only "Compare the two byte
# for byte" under an empty output, about a crash or a loop.
printf '#!/bin/sh\nkill -SEGV $$\n' > "$WORK/pn_segv"
printf '#!/bin/sh\nexec sleep 30\n' > "$WORK/pn_hang"
chmod +x "$WORK/pn_segv" "$WORK/pn_hang"
want_out   "progname: a crash before any output is named" 'killed by SIGSEGV' -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_segv"
want_out   "progname: ...and so is a run that never finished" 'did not finish within 1s' -- \
	env PROGNAME_TIMEOUT=1 "$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pn_hang"

# The program by --bin alone: handed over bare, tools/probe_under.sh could
# not stand another in for it (it swaps the word after a program flag).
want_broken "progname: a program handed over as a plain argument is refused" \
	'handed over as --bin' -- "$SH" "$TOOLS/progname_test.sh" "$WORK/pn_ok"

want_red "progname: a stand-in is red" -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$STANDIN_BIN"
want_out "progname: ...says the code did not build" "$STANDIN_SAYS" -- \
	"$SH" "$TOOLS/progname_test.sh" --bin "$STANDIN_BIN"

