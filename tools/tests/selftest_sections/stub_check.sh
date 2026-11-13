# ------------------------------------------------------------------ stub_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The one runner here whose failure is not a red exercise but a PUBLISHED answer.
# stub_check.sh is what stands between the owner's finished work and the template
# branch other people clone, and it has already failed once in exactly the way
# this file exists to catch: it globbed `*/deliverable/*.c`, so it printed
# "OK — all 123 deliverable(s) are stubs" over a tree in which c-08's four
# answers were sitting untouched, because c-08's deliverable IS a header. Those
# four shipped. So did rush-00's rush.h with one team's whole data model in it,
# and all 18 shell generators, for the same reason: a check that reports on the files
# it happens to look at says nothing about the ones it does not.
#
# Hence one green and one red per KIND, rather than a couple of representative
# cases — the failure mode being guarded against is a whole kind falling out of
# scope, which a passing arm on a neighbouring kind would not notice. The reds
# have the real published SHAPES — a function-like macro, and a lone prototype,
# which is what c-08 ex00 through ex03 each turn in. The fixtures deliberately do
# NOT reproduce those answers: this file ships on the template, so a fixture that
# quoted one would hand it over through the very test that exists to stop it.
# SQUARE and ft_selftest_len are not exercises anywhere in this repo.
#
# --file is used instead of the repo mode because repo mode is built on
# `git ls-files`, and a self-test that needs a populated git repository is one
# that will not run hermetically.
mkdir -p "$WORK/sc"
# The 42 header every .c and .h stub opens with: eleven lines, a border on the
# first and the last. A stub without one is refused (below), so every stub
# fixture here carries it.
SC_H='/* ************************************************************************** */
/*                                                                            */
/*                                        stub_check selftest fixture           */
/*                                                                            */
/*                                                                            */
/*                                                                            */
/*                                                                            */
/*                                                                            */
/*                                                                            */
/*                                                                            */
/* ************************************************************************** */'
printf '%s\n\n#ifndef FT_ABS_H\n# define FT_ABS_H\n\n#endif\n' "$SC_H" > "$WORK/sc/guards.h"
printf '%s\n\n#ifndef SC_MACRO_H\n# define SC_MACRO_H\n# define SQUARE(n) ((n) * (n))\n#endif\n' \
	"$SC_H" > "$WORK/sc/macro.h"
printf '%s\n\n#ifndef SC_PROTO_H\n# define SC_PROTO_H\n\nint\tft_selftest_len(char *str);\n\n#endif\n' \
	"$SC_H" > "$WORK/sc/proto.h"
# The "real" fixtures are real CODE and deliberately no exercise's answer: the
# selftest ships in the public template, and a known-bad fixture copied from a
# deliverable is an answer in a file anyone can open. A made-up function, a
# made-up program name and a made-up command do the same job.
printf '%s\n\n' "$SC_H" > "$WORK/sc/stub.c"
cat >> "$WORK/sc/stub.c" <<'SC_STUB'
int	ft_selftest_twice(int n)
{
	(void)n;
	return (0);
}
SC_STUB
printf '%s\n\n' "$SC_H" > "$WORK/sc/answer.c"
cat >> "$WORK/sc/answer.c" <<'SC_REAL'
int	ft_selftest_twice(int n)
{
	return (n + n);
}
SC_REAL
printf 'NAME = selftest_prog\n\nall:\n\t@echo "TODO: build $(NAME)"\n' > "$WORK/sc/Makefile"
mkdir -p "$WORK/sc/real"
printf 'NAME = selftest_prog\n\nall:\n\tcc -Wall -Wextra -Werror -o $(NAME) main.c\n' \
	> "$WORK/sc/real/Makefile"
printf '#!/bin/sh\n# ex04: describe the deliverable.\n# TODO: write the commands.\n:\n' \
	> "$WORK/sc/ex04.sh"
printf '#!/bin/sh\n# ex04: describe the deliverable.\nprintf selftest > selftest-output\n' \
	> "$WORK/sc/real_ex04.sh"

want_green "stub_check: a .c stub passes" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/stub.c"
want_red   "stub_check: a .c with a real body fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/answer.c"
want_green "stub_check: a guards-only .h passes" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/guards.h"
want_red   "stub_check: a .h defining the answer macro fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/macro.h"
want_red   "stub_check: a .h carrying a prototype fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/proto.h"
# The same files with CRLF line ends, as an editor set to CRLF saves them.
# The \r stayed on every line judge_c and judge_h read, so no stub pattern
# anchored on the line's end matched, and a stub was reported as an
# answer; body_hash hashed it too, so an approved header's CRLF copy lost
# its approval. The judges read a line without its \r now, and an answer is
# still an answer. A stub is still no stub that ships: reset_headers.sh
# reads no header behind those borders, so nothing would re-stamp it, and
# it is refused -- for its line ends, not as an answer, and not as a file
# with no header.
for _scf in stub.c answer.c guards.h proto.h; do
	awk '{ printf "%s\r\n", $0 }' "$WORK/sc/$_scf" > "$WORK/sc/crlf_$_scf"
done
want_broken "stub_check: a .c stub with CRLF line ends is refused for them" \
	'has CRLF line ends' -- "$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/crlf_stub.c"
want_broken_without "stub_check: ...and not called an answer" \
	'still contain an implementation' -- "$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/crlf_stub.c"
want_red   "stub_check: ...while a .c with a real body still fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/crlf_answer.c"
want_broken "stub_check: a guards-only .h with CRLF line ends is refused for them" \
	'has CRLF line ends' -- "$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/crlf_guards.h"
want_red   "stub_check: ...while a .h carrying a prototype still fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/crlf_proto.h"
# One border with a \r and one without, as a half-converted file has them:
# refused too, and the reason says which border, not that every line of
# the header ends in one, which the reader would check and find false.
awk 'NR == 1 { printf "%s\r\n", $0; next } { print }' "$WORK/sc/stub.c" > "$WORK/sc/cr1_stub.c"
want_broken "stub_check: a header with one CRLF border is refused, naming it" \
	'has a CRLF line end: the border on line 1 of its 42 header ends in a' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/cr1_stub.c"
want_broken "stub_check: ...and the border that has none" \
	'carriage return, and the one on line 11 does not.' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/cr1_stub.c"
sc_same_hash() {  # sc_same_hash A B: --hash gives A and B one hash, and gives one
	_sca=$("$SH" "$TOOLS/stub_check.sh" --hash "$1" | cut -c1-32) || return 1
	_scb=$("$SH" "$TOOLS/stub_check.sh" --hash "$2" | cut -c1-32) || return 1
	[ -n "$_sca" ] && [ "$_sca" = "$_scb" ]
}
want_green "stub_check: a header's hash is the same with CRLF line ends" -- \
	sc_same_hash "$WORK/sc/guards.h" "$WORK/sc/crlf_guards.h"
want_red   "stub_check: ...and still moves with its content" -- \
	sc_same_hash "$WORK/sc/guards.h" "$WORK/sc/crlf_proto.h"
want_green "stub_check: a Makefile that only echoes passes" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/Makefile"
want_red   "stub_check: a Makefile that compiles fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/real/Makefile"
# ...and so does one that compiles after an echo, or on its rule's own line.
# Only a recipe line that STARTED with echo was read as an echo, and a recipe
# after a `;` on the rule line was never read at all: all three passed --file
# and repo mode (the template build's gate) as stubs, where --goal, which
# reads every recipe line as make does (goal_rule), already said otherwise.
mkdir -p "$WORK/sc/mk_semi" "$WORK/sc/mk_and" "$WORK/sc/mk_rule"
printf 'NAME = selftest_prog\n\nall:\n\t@echo "Linking"; cc -o $(NAME) main.c\n' \
	> "$WORK/sc/mk_semi/Makefile"
printf 'NAME = selftest_prog\n\nall:\n\techo building && $(CC) -o $(NAME) main.c\n' \
	> "$WORK/sc/mk_and/Makefile"
printf 'all: ; cc -o selftest_prog main.c\n' > "$WORK/sc/mk_rule/Makefile"
want_red   "stub_check: a Makefile that compiles after an echo; fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_semi/Makefile"
want_red   "stub_check: ...and after an echo &&" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_and/Makefile"
want_red   "stub_check: ...and on its rule's line, after a ;" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_rule/Makefile"
# A recipe that only echoes is a stub whatever its words: make's own
# variables (CC, CFLAGS), which the Makefile never sets, are words the echo
# prints, and >&2 or 1>&2 sends them to stderr, opening no file. All four
# were reported as implementations once goal_rule had the last word.
mkdir -p "$WORK/sc/mk_cc" "$WORK/sc/mk_err" "$WORK/sc/mk_err1" "$WORK/sc/mk_words" \
	"$WORK/sc/mk_untold" "$WORK/sc/mk_mixed"
printf 'NAME = selftest_prog\n\nall:\n\t@echo "TODO: compile with $(CC)"\n' > "$WORK/sc/mk_cc/Makefile"
printf 'NAME = selftest_prog\n\nall:\n\t@echo "TODO" >&2\n' > "$WORK/sc/mk_err/Makefile"
printf 'NAME = selftest_prog\n\nall:\n\t@echo "TODO: $(NAME)" 1>&2\n' > "$WORK/sc/mk_err1/Makefile"
printf 'NAME = selftest_prog\n\nall:\n\t@echo $(NAME) $(CC) $(CFLAGS)\n' > "$WORK/sc/mk_words/Makefile"
want_green "stub_check: an echo whose quoted words name CC is a stub" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_cc/Makefile"
want_green "stub_check: ...and so is an echo to stderr, >&2" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_err/Makefile"
want_green "stub_check: ...or 1>&2, its words naming NAME" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_err1/Makefile"
want_green "stub_check: ...or an echo of make's variables, unquoted" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_words/Makefile"
# Where the word echo ends is read once, for both questions: whether a line
# is an echo, and whether make's own variables are words in it. An echo
# with its >&2 written straight after it, on its rule's line (no TAB line,
# so judge_mk never sees it), was an echo to one and not to the other, and
# so untold; one with a ; straight after it was untold too, not code.
mkdir -p "$WORK/sc/mk_errin" "$WORK/sc/mk_semiin"
printf 'NAME = selftest_prog\n\nall: ; @echo>&2 "TODO: compile with $(CC)"\n' \
	> "$WORK/sc/mk_errin/Makefile"
printf 'NAME = selftest_prog\n\nall: ; @echo;$(CC) -o $(NAME) main.c\n' > "$WORK/sc/mk_semiin/Makefile"
want_green "stub_check: ...or echo>&2 on its rule's line, its words naming CC" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_errin/Makefile"
want_out   "stub_check: an echo; then CC on its rule's line is code it found" \
	'a recipe line does more than echo' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_semiin/Makefile"
# One whose words hold a value only a conditional sets is one this reader
# cannot tell is an echo (the value may close the quote and run a command):
# it counts as written, and it says so, never that it found code. Beside a
# Makefile that compiles, the summary tells the two apart.
printf 'NAME = selftest_prog\nifdef SELFTEST_X\nMSG = hello\nendif\n\nall:\n\t@echo "$(MSG)"\n' \
	> "$WORK/sc/mk_untold/Makefile"
cp "$WORK/sc/mk_untold/Makefile" "$WORK/sc/mk_mixed/Makefile"
want_red   "stub_check: an echo of a value a conditional sets counts as written" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_untold/Makefile"
want_out   "stub_check: ...saying this reader could not tell" 'could not tell' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_untold/Makefile"
want_broken_none "stub_check: ...never that it is code that would ship" \
	'code that would ship in the template' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_untold/Makefile"
want_out   "stub_check: beside one that compiles, each is counted as what it is" \
	'1 of them could not be told apart' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_mixed/Makefile" "$WORK/sc/real/Makefile"
# The other way to be untold: a line this reader cannot read past (a stray
# endif, a define left open), in a file whose one recipe line is a plain
# echo. The reason once named only a line using what the reader cannot
# know, with causes (a conditional, an include, an eval, a function) that
# neither this file nor one substituting make's CC holds.
mkdir -p "$WORK/sc/mk_endif" "$WORK/sc/mk_define" "$WORK/sc/mk_ccsub"
printf 'all:\n\t@echo hi\nendif\n' > "$WORK/sc/mk_endif/Makefile"
printf 'define SELFTEST_X\nall:\n\t@echo hi\n' > "$WORK/sc/mk_define/Makefile"
printf 'all:\n\t@echo "TODO: $(CC:.c=.o)"\n' > "$WORK/sc/mk_ccsub/Makefile"
want_red   "stub_check: a stray endif counts as written" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_endif/Makefile"
want_out   "stub_check: ...for a line this reader cannot read past" \
	'or the file holds a line it cannot read past' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_endif/Makefile"
want_out   "stub_check: ...and so does a define left open" \
	'or the file holds a line it cannot read past' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_define/Makefile"
want_broken_none "stub_check: an untold line is told without causes it lacks" \
	'a value set under a conditional' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/mk_ccsub/Makefile"
want_green "stub_check: a generator reduced to ':' passes" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/ex04.sh"
want_red   "stub_check: a generator that still runs commands fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/real_ex04.sh"
# A generator's stub and a Makefile's, the kinds with no 42 header, saved
# with CRLF line ends. judge_sh and judge_mk kept the \r, so a ':' or a
# 'true' line, which their stub patterns anchor on the line's end, was
# reported as an implementation by --file, the mode first_red.sh asks
# whether a part is written. Every judge reads a line without its \r now
# (_SC_NO_CR), and a command is still a command.
mkdir -p "$WORK/sc/crlf_mk" "$WORK/sc/crlf_real"
awk '{ printf "%s\r\n", $0 }' "$WORK/sc/ex04.sh" > "$WORK/sc/crlf_ex04.sh"
awk '{ printf "%s\r\n", $0 }' "$WORK/sc/real_ex04.sh" > "$WORK/sc/crlf_real_ex04.sh"
awk '{ printf "%s\r\n", $0 }' "$WORK/sc/real/Makefile" > "$WORK/sc/crlf_real/Makefile"
printf 'NAME = selftest_prog\r\n\r\nall:\r\n\ttrue\r\n' > "$WORK/sc/crlf_mk/Makefile"
want_green "stub_check: a generator reduced to ':' with CRLF line ends passes" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/crlf_ex04.sh"
want_red   "stub_check: ...while one that still runs commands fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/crlf_real_ex04.sh"
want_green "stub_check: a Makefile whose recipe is 'true', with CRLF line ends, passes" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/crlf_mk/Makefile"
want_red   "stub_check: ...while one that compiles fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/crlf_real/Makefile"

# NEITHER A STUB NOR AN ANSWER. An empty file holds no code, and a .c with a
# stub's body and no 42 header holds none either, so both read as stubs: "OK
# -- all 1 deliverable(s) are stubs". Neither is what the template ships, and
# a file with no header is one the template build never re-stamps. Each is
# refused, exit 2, with a reason of its own. Their twins: a file that defines
# nothing but keeps its header is still a stub (the template ships one, a
# header and a comment), and an answer with no header is still an answer.
# The empty one's reason names a #! line only for a script, the one kind
# whose #! line it skips: a .c or a Makefile has none to leave out.
mkdir -p "$WORK/sc/bare"
: > "$WORK/sc/bare/empty.c"
: > "$WORK/sc/bare/ex05.sh"
printf 'int\tft_selftest_twice(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' \
	> "$WORK/sc/bare/nohdr.c"
printf '#ifndef SC_BARE_H\n# define SC_BARE_H\n\n#endif\n' > "$WORK/sc/bare/nohdr.h"
printf 'int\tft_selftest_twice(int n)\n{\n\treturn (n + n);\n}\n' \
	> "$WORK/sc/bare/answer.c"
printf '%s\n\n/*\n** Nothing is defined here.\n*/\n' "$SC_H" > "$WORK/sc/bare/comment.c"
want_broken "stub_check: an empty .c is refused, and says so" \
	'is empty: no line in it but blanks. It holds no' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/bare/empty.c"
want_broken "stub_check: ...and so is an empty generator" \
	"is empty: no line in it but blanks (and a script's #! line). It holds no" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/bare/ex05.sh"
want_broken "stub_check: a .c stub with no 42 header is refused" \
	'has no 42 header' -- "$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/bare/nohdr.c"
want_broken "stub_check: ...and so is a .h with no 42 header" \
	'has no 42 header' -- "$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/bare/nohdr.h"
want_green "stub_check: a header and a comment, defining nothing, pass" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/bare/comment.c"
want_red   "stub_check: an answer with no 42 header is still an answer" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/bare/answer.c"
# Empty is no line but blanks, not zero bytes: a generator holding one
# newline, or nothing but its #! line, and a Makefile holding one newline
# keep as little as a zero-byte file, and they passed as stubs because the
# test was `[ ! -s ]`. The twin: a #! line and a `:` is still a stub.
mkdir -p "$WORK/sc/blankonly"
printf '\n' > "$WORK/sc/blankonly/ex06.sh"
printf '#!/bin/sh\n\n' > "$WORK/sc/blankonly/ex07.sh"
printf '\n' > "$WORK/sc/blankonly/Makefile"
printf '#!/bin/sh\n:\n' > "$WORK/sc/blankonly/ex08.sh"
want_broken "stub_check: a generator holding one newline is empty" \
	'is empty' -- "$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/blankonly/ex06.sh"
want_broken "stub_check: ...and so is one holding only its #! line" \
	'is empty' -- "$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/blankonly/ex07.sh"
want_broken "stub_check: ...and a Makefile holding one newline" \
	'is empty: no line in it but blanks. It holds no' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/blankonly/Makefile"
want_green "stub_check: a #! line and a ':' is still a stub" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/blankonly/ex08.sh"

# A README A SUBJECT HAS TURNED IN is the student's prose about their own
# work, and its stub is comments saying what to write. --file read no .md at
# all ("not a deliverable kind", exit 2), and repo mode listed one as never
# read, so a template could ship no README stub without its publish gate
# failing. The kind: blank lines and <!-- --> blocks pass; a heading, text
# beside a comment, or a comment never closed is the student's, and an empty
# README is no stub either.
mkdir -p "$WORK/sc/md"
printf '<!--\n  Say what this project is, and how to build it.\n-->\n\n<!-- and how to use it -->\n' \
	> "$WORK/sc/md/README.md"
printf '<!-- what to write -->\n# A selftest library\n\nIt holds two functions.\n' \
	> "$WORK/sc/md/written.md"
printf '<!-- a note --> and a sentence after it\n' > "$WORK/sc/md/beside.md"
printf '<!-- opened\n\nand never closed\n' > "$WORK/sc/md/open.md"
printf '\n\n' > "$WORK/sc/md/blank.md"
want_green "stub_check: a README of comments is a stub" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/md/README.md"
want_red   "stub_check: a README with a line of prose is written" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/md/written.md"
want_out   "stub_check: ...and the line is named" \
	'2: # A selftest library' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/md/written.md"
want_red   "stub_check: text after a comment closes is written" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/md/beside.md"
want_out   "stub_check: a comment never closed is named" \
	'a comment never closed' -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/md/open.md"
want_broken "stub_check: a README of blank lines is empty" \
	'is empty' -- "$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/md/blank.md"
# The README stub with CRLF line ends, which its judge read as a stub before
# it took _SC_NO_CR (it counts a \r as a blank): pinned with the others.
awk '{ printf "%s\r\n", $0 }' "$WORK/sc/md/README.md" > "$WORK/sc/md/crlf_README.md"
want_green "stub_check: ...and so is one with CRLF line ends" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/md/crlf_README.md"

# --defines NAME FILE...: ONE function's body, for a library whose files hold
# many. tools/first_red.sh asks it per function, so one written function does
# not make every other red of the library read "written, and wrong". Exit 0
# for a stub body, 1 for a body that does more (its lines printed), 3 for a
# NAME no file defines, 2 for no verdict. The fixture holds a stub, a written
# function with its signature wrapped and its return type on a line of its
# own, and a whole function on one line -- made up, like every function here.
printf '%s\n\n#include <unistd.h>\n\nint\tft_selftest_one(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' \
	"$SC_H" > "$WORK/sc/md/lib.c"
printf '\nstatic int\n\tft_selftest_two(int a,\n\t\tint b)\n{\n\tif (a > b)\n\t\treturn (a - b);\n\treturn (b);\n}\n' \
	>> "$WORK/sc/md/lib.c"
printf 'int\tft_selftest_three(void) { return (3); }\n' >> "$WORK/sc/md/lib.c"
printf '%s\n\nint\tft_selftest_four(int n);\n' "$SC_H" > "$WORK/sc/md/proto.h"
# The status as a word, so 3 -- which want_out would take for a broken
# harness -- can be asserted as exactly what it is.
sc_defines() {
	"$SH" "$TOOLS/stub_check.sh" --defines "$@" > /dev/null 2>&1
	echo "status $?"
}
want_out   "stub_check --defines: a stub body is a stub" 'status 0' -- \
	sc_defines ft_selftest_one "$WORK/sc/md/lib.c"
want_out   "stub_check --defines: ...beside a written one" 'status 1' -- \
	sc_defines ft_selftest_two "$WORK/sc/md/lib.c"
want_out   "stub_check --defines: ...whose lines are printed" '25: 	if (a > b)' -- \
	"$SH" "$TOOLS/stub_check.sh" --defines ft_selftest_two "$WORK/sc/md/lib.c"
want_out   "stub_check --defines: a body on its signature's line" 'status 1' -- \
	sc_defines ft_selftest_three "$WORK/sc/md/lib.c"
want_out   "stub_check --defines: a prototype alone defines nothing" 'status 3' -- \
	sc_defines ft_selftest_four "$WORK/sc/md/lib.c" "$WORK/sc/md/proto.h"
want_out   "stub_check --defines: a name only a longer one holds is absent" 'status 3' -- \
	sc_defines ft_selftest_tw "$WORK/sc/md/lib.c"
# --defines reads no 42 header, so the CRLF stub that --file refuses for
# its borders (above) is judged on its body alone: a stub.
want_out   "stub_check --defines: a stub body with CRLF line ends is a stub" 'status 0' -- \
	sc_defines ft_selftest_twice "$WORK/sc/crlf_stub.c"
# A one-line comment holding a `*` before a definition. The strip once
# removed only comments with no `*` inside, so the comment's own text stayed
# in the declaration: "(n * size)" named the function after it "size" (absent,
# exit 3), and "ft_selftest_six(s, n) * ..." gave ft_selftest_seven's body to
# ft_selftest_six (written, exit 1). The 42 header above each, a comment of
# stars, goes the same way.
printf '%s\n\n/* Returns the size (n * size) of the block */\nint\tft_selftest_five(int n)\n{\n\tif (n > 3)\n\t\treturn (n - 3);\n\treturn (n);\n}\n' \
	"$SC_H" > "$WORK/sc/md/star.c"
printf '%s\n\n/* like ft_selftest_six(s, n) * but counts down */\nint\tft_selftest_seven(int n)\n{\n\twhile (n > 9)\n\t\tn -= 9;\n\treturn (n);\n}\n\nint\tft_selftest_six(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' \
	"$SC_H" > "$WORK/sc/md/star_name.c"
want_out   "stub_check --defines: a comment with a star hides no function" 'status 1' -- \
	sc_defines ft_selftest_five "$WORK/sc/md/star.c"
want_out   "stub_check --defines: ...nor names one" 'status 0' -- \
	sc_defines ft_selftest_six "$WORK/sc/md/star_name.c"
want_out   "stub_check --defines: ...nor takes its body" 'status 1' -- \
	sc_defines ft_selftest_seven "$WORK/sc/md/star_name.c"
# A block comment holding `//`, a URL above a function. The `//` strip ran
# before block comments were read, took the closing `*/` with it, and the
# comment then ran on to the end of the file: a written body passed --file
# as a stub and --defines found no function (exit 3, which first_red reads
# as "not written"). The comment on one line, and the last line of a comment
# on two, whose `*/` follows the `//`.
printf '%s\n\n/* see https://example.invalid/selftest */\nint\tft_selftest_eight(int n)\n{\n\twhile (n > 7)\n\t\tn -= 7;\n\treturn (n);\n}\n' \
	"$SC_H" > "$WORK/sc/md/url.c"
printf '%s\n\n/*\n   see https://example.invalid/selftest */\nint\tft_selftest_eight(int n)\n{\n\twhile (n > 7)\n\t\tn -= 7;\n\treturn (n);\n}\n' \
	"$SC_H" > "$WORK/sc/md/url2.c"
want_red   "stub_check: a URL in a comment hides no body" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/md/url.c"
want_out   "stub_check --defines: ...nor hides the function" 'status 1' -- \
	sc_defines ft_selftest_eight "$WORK/sc/md/url.c"
want_red   "stub_check: ...nor a URL on a comment's last line" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/md/url2.c"
want_broken "stub_check --defines: a name that is no C name is refused" \
	'needs a function name' -- "$SH" "$TOOLS/stub_check.sh" --defines 'ft x' "$WORK/sc/md/lib.c"
want_broken "stub_check --defines: ...and so is a file of another kind" \
	'reads C sources and headers' -- \
	"$SH" "$TOOLS/stub_check.sh" --defines ft_selftest_one "$WORK/sc/md/README.md"

# --goal RULE MAKEFILE: one rule of a Makefile, for a part built by a rule of
# its own from files another part shares. 1 when the Makefile is no stub and
# RULE does something (its lines printed), or may, as far as a reader that
# never runs make can tell; 0 when the Makefile is a stub or RULE does nothing
# yet, 3 when the Makefile is no stub and has no rule RULE, 2 for no verdict.
# `-` is the default goal. Every Makefile is invented.
mkdir -p "$WORK/sc/goal"
sc_goal_mk() {  # sc_goal_mk NAME TEXT: $WORK/sc/goal/NAME/Makefile
	mkdir -p "$WORK/sc/goal/$1"
	printf "$2" > "$WORK/sc/goal/$1/Makefile"
}
sc_goal_mk stub 'all:\n\t@echo TODO\nbonus: all\n\t@echo TODO\n.PHONY: all bonus\n'
sc_goal_mk none 'NAME = sorter\nall: $(NAME)\n$(NAME): a.o\n\tcc a.o -o $(NAME)\n'
sc_goal_mk phony 'all:\n\tcc a.c -o sorter\n.PHONY: all bonus\n'
sc_goal_mk echo 'all:\n\tcc a.c -o sorter\nbonus:\n\t@echo later\n'
sc_goal_mk prereq 'all:\n\tcc a.c -o sorter\nbonus: all b.o\n'
sc_goal_mk recipe 'all:\n\tcc a.c -o sorter\nbonus:\n\tcc b.c -o checker\n'
sc_goal_mk var 'B = bonus\nall:\n\tcc a.c -o sorter\n$(B):\n\tcc b.c -o checker\n'
sc_goal_mk tsv 'all:\n\tcc a.c -o sorter\nbonus: CFLAGS += -g\n'
sc_goal_mk inline 'all:\n\tcc a.c -o sorter\nbonus: ; cc b.c -o checker\n'
sc_goal_mk dflt 'NAME = sorter\n.PHONY: all\n$(NAME): a.o\n\tcc a.o -o $(NAME)\nbonus:\n\tcc b.c -o checker\n'
sc_goal_mk dflt_echo 'all:\n\t@echo TODO\n\ncheck:\n\tcc c.c -o checker\n'
# A recipe line that starts with an echo and runs more after it, and the
# prerequisites make itself would see.
sc_goal_mk and 'all:\n\tcc a.c -o sorter\nbonus:\n\t@echo bonus && cc b.c -o checker\n'
sc_goal_mk semi 'all:\n\tcc a.c -o sorter\nbonus:\n\t@echo bonus; cc b.c -o checker\n'
sc_goal_mk cont 'all:\n\tcc a.c -o sorter\nbonus:\n\t@echo bonus; \\\n\tcc b.c -o checker\n'
sc_goal_mk said 'all:\n\tcc a.c -o sorter\nbonus:\n\t@echo "later; then && | more" '"'"'and; this'"'"' \\\n\t\tdone\n'
sc_goal_mk cmt 'all:\n\tcc a.c -o sorter\nbonus:\n\t@# later \\\n\tcc b.c -o checker\n'
sc_goal_mk empty 'B =\nall:\n\tcc a.c -o sorter\nbonus: $(B)\n'
sc_goal_mk esub 'BS =\nBO = $(BS:.c=.o)\nall:\n\tcc a.c -o sorter\nbonus: $(BO)\n'
sc_goal_mk epat 'BS =\nBO = $(BS:%%.c=obj/%%.o)\nall:\n\tcc a.c -o sorter\nbonus: $(BO)\n'
sc_goal_mk fsub 'BS = b.c\nBO = $(BS:.c=.o)\nall:\n\tcc a.c -o sorter\nbonus: $(BO)\n'
sc_goal_mk unset 'all:\n\tcc a.c -o sorter\nbonus: $(B)\n'
sc_goal_mk later 'all:\n\tcc a.c -o sorter\nbonus: $(B)\nB = b.o\n'
sc_goal_mk incl 'include more.mk\nall:\n\tcc a.c -o sorter\nbonus: $(B)\n'
sc_goal_mk func 'all:\n\tcc a.c -o sorter\nbonus: $(wildcard b*.c)\n'
# A line that starts with a TAB is a recipe only under a rule. Above the first
# rule, or after a line that ends a rule (an assignment, or a directive other
# than a conditional), make reads it as any other line: here, an assignment.
sc_goal_mk tab_assign_top '\tBONUS = checker\nall:\n\tcc a.c -o sorter\nbonus: $(BONUS)\n\t@echo b\n'
sc_goal_mk tab_assign 'UNAME := Linux\nifeq ($(UNAME),Linux)\n\tBONUS = checker\nendif\nall:\n\tcc a.c -o sorter\nbonus: $(BONUS)\n\t@echo b\n'
sc_goal_mk tab_assign_ifelse 'UNAME := Linux\nifeq ($(UNAME),Darwin)\n\tBONUS = checker_mac\nelse\n\tBONUS = checker\nendif\nall:\n\tcc a.c -o sorter\nbonus: $(BONUS)\n\t@echo b\n'
sc_goal_mk tab_after_rule 'all:\n\tcc a.c -o sorter\n\nB = x\nifeq (a,a)\n\tBONUS = checker\nendif\nbonus: $(BONUS)\n\t@echo b\n'
# A variable set with = keeps its text, and make expands it where it is used,
# with what the lines below it set.
sc_goal_mk recursive_late 'BSRC =\nBOBJ = $(BSRC:.c=.o)\nBSRC = b.c\nall:\n\tcc a.c -o sorter\nbonus: $(BOBJ)\n\t@echo bonus\n'
sc_goal_mk append_late 'BSRC =\nBOBJ = $(BSRC:.c=.o)\nBSRC += b.c\nall:\n\tcc a.c -o sorter\nbonus: $(BOBJ)\n\t@echo bonus\n'
sc_goal_mk pe_rec_chain 'S =\nO = $(S:.c=.o)\nP = $(O)\nS = b.c\nall:\n\tcc a.c -o sorter\nbonus: $(P)\n\t@echo b\n'
# The reader does not evaluate a conditional, so a value set inside one is not
# known, and neither is the default goal when its first candidate is inside.
sc_goal_mk ifelse 'ifndef NOBONUS\nBSRC = b.c\nelse\nBSRC =\nendif\nall:\n\tcc a.c -o sorter\nbonus: $(BSRC:.c=.o)\n\t@echo bonus\n'
sc_goal_mk ifdef_os_rev 'UNAME := linux\nifeq ($(UNAME),linux)\nBONUS = checker\nelse\nBONUS =\nendif\nall:\n\tcc a.c -o sorter\nbonus: $(BONUS)\n\t@echo bonus\n'
sc_goal_mk dg_ifeq 'ifeq (a,b)\nfirst:\n\t@echo first\nendif\nall: a.o\n\tcc a.o -o sorter\n'
sc_goal_mk dg_var 'NAME = sorter\n.DEFAULT_GOAL := $(NAME)\nclean:\n\t@echo clean\n$(NAME): a.o\n\t@echo link\nother:\n\tcc x.c -o y\n'
# The whole file is judged before the rule: a recipe that echoes and then
# does more is no stub, and neither is one after a `;`.
sc_goal_mk gate_echoand 'NAME = sorter\nall: $(NAME)\n$(NAME): a.c\n\t@echo "Linking" && cc a.c -o $(NAME)\nbonus: b.c\n\t@echo "Linking checker" && cc b.c -o checker\nclean:\n\t@echo "Cleaning" && rm -f checker $(NAME)\n'
sc_goal_mk gate_inline 'all: ; cc a.c -o sorter\nbonus: ; cc b.c -o checker\nclean: ; rm -f sorter checker\n'
# A file saved with CRLF line ends, which make reads as plain ones.
sc_goal_mk crlf_define 'define HELLO\r\n\t@echo hello\r\nendef\r\nall:\r\n\tcc a.c -o sorter\r\nbonus: b.o\r\n\t@echo bonus\r\n'
sc_goal_mk crlf_dg '.DEFAULT_GOAL = bonus\r\nall:\r\n\tcc a.c -o sorter\r\nbonus: b.o\r\n\t@echo bonus\r\n'
sc_goal_mk crlf_empty 'B =\r\nall:\r\n\tcc a.c -o sorter\r\nbonus: $(B)\r\n\t@echo bonus\r\n'
sc_goal_mk crlf_cont 'B =\r\nall:\r\n\tcc a.c -o sorter\r\nbonus: \\\r\n $(B)\r\n\t@echo bonus\r\n'
# make expands a recipe line when it runs it, so an echo can hold more.
sc_goal_mk echo_semi 'MORE = ; cc b.c -o checker\nall:\n\tcc a.c -o sorter\nbonus:\n\t@echo bonus $(MORE)\n'
sc_goal_mk echo_shell 'MORE = $(shell cc b.c -o checker)\nall:\n\tcc a.c -o sorter\nbonus:\n\t@echo bonus $(MORE)\n'
sc_goal_mk incl_empty 'B =\n-include more.mk\nall:\n\tcc a.c -o sorter\nbonus: $(B)\n'
# A variable set with override ignores a plain assignment below it -- unless
# the override line set nothing: ?= on a variable already set, += of nothing,
# or undefine.
sc_goal_mk ovr_name 'N := $(shell echo B)\noverride $(N) = b.o\nB =\nall:\n\tcc a.c -o sorter\nbonus: $(B)\n\t@echo bonus\n'
sc_goal_mk ovr_tab 'ifeq (a,b)\nfoo:\nendif\n\toverride B = b.o\nB =\nall:\n\tcc a.c -o sorter\nbonus: $(B)\n\t@echo bonus\n'
sc_goal_mk ovr_undefine 'B = x.o\noverride undefine B\nB = b.o\nall:\n\tcc a.c -o sorter\nbonus: $(B)\n\t@echo bonus\n'
sc_goal_mk ovr_ifset 'B :=\noverride B ?= x.o\nB = b.o\nall:\n\tcc a.c -o sorter\nbonus: $(B)\n\t@echo bonus\n'
sc_goal_mk ovr_add_none 'B :=\noverride B += $(E)\nB = b.o\nall:\n\tcc a.c -o sorter\nbonus: $(B)\n\t@echo bonus\n'
sc_goal_mk ovr_dg '.DEFAULT_GOAL :=\noverride .DEFAULT_GOAL += $(E)\nclean:\n\t@echo clean\n.DEFAULT_GOAL =\nall: a.o\n\tcc a.o -o sorter\n'
# A backslash keeps a : in a prerequisite's name.
sc_goal_mk esc_colon 'all:\n\tcc a.c -o sorter\nbonus: obj\\:\n\t@echo bonus\n'
# A variable that refers to itself, twice: make refuses it, and a reader that
# expanded it as written would never finish.
sc_goal_mk self_ref 'X = $(X) $(X)\nall:\n\tcc a.c -o sorter\nbonus: $(X)\n\t@echo bonus\n'
# make files a name without the ./ in front of it, nor the slashes after that
# (.//bonus is bonus), and finds the default goal the same way.
sc_goal_mk dot_slash 'D = ./\nall:\n\tcc a.c -o sorter\n$(D)/bonus: b.o\n\t@echo bonus\n'
sc_goal_mk dot_slashes 'all:\n\tcc a.c -o sorter\n.//bonus: b.o\n\t@echo bonus\n'
sc_goal_mk dg_slashes '.DEFAULT_GOAL := .//bonus\nall:\n\tcc a.c -o sorter\nbonus: b.o\n\t@echo bonus\n'
sc_goal_mk dg_dir 'NAME = sorter\nDIR = ./\n.DEFAULT_GOAL := $(NAME)\nclean:\n\t@echo clean\n$(DIR)/$(NAME): a.o\n\t@echo link\nother:\n\tcc x.c -o y\n'
# make sets .SHELLSTATUS itself, after a $(shell).
sc_goal_mk shellstatus 'X := $(shell true)\nall:\n\tcc a.c -o sorter\nbonus: $(.SHELLSTATUS)\n\t@echo bonus\n'
# A goal with no recipe of its own that is not .PHONY: make looks for a rule
# of the Makefile's to make it with (a pattern rule, a suffix rule), and runs
# the recipe of .DEFAULT for a name no rule has. Never for a goal with a
# recipe, nor for a .PHONY one, nor through a pattern the name does not fit.
sc_goal_mk pat_only 'all:\n\tcc a.c -o sorter\nbon%%:\n\tcc b.c -o checker\n'
sc_goal_mk pat_empty 'all:\n\tcc a.c -o sorter\nbonus:\nbon%%:\n\tcc b.c -o checker\n'
sc_goal_mk pat_any 'all:\n\tcc a.c -o sorter\n%%:\n\tcc $@.c -o $@\n'
sc_goal_mk sfx_one 'all:\n\tcc a.c -o sorter\n.c:\n\tcc $< -o $@\n'
sc_goal_mk dflt_rule 'all:\n\tcc a.c -o sorter\n.DEFAULT:\n\tcc b.c -o checker\n'
sc_goal_mk pat_phony 'all:\n\tcc a.c -o sorter\n.PHONY: all bonus\nbon%%:\n\tcc b.c -o checker\n'
sc_goal_mk pat_echo 'all:\n\tcc a.c -o sorter\nbonus:\n\t@echo later\n%%:\n\tcc $@.c -o $@\n'
sc_goal_mk pat_obj 'all:\n\tcc a.c -o sorter\n%%.o: %%.c\n\tcc -c $< -o $@\n'
sc_goal_mk pat_unknown 'all:\n\tcc a.c -o sorter\n-include more.mk\n$(D)/%%.o: %%.c\n\tcc -c $< -o $@\n'
# A reference the reader cannot expand may hold several words, any of them a
# pattern, and one with a % inside may leave no pattern at all: such a rule
# may name any target.
sc_goal_mk pat_cond 'ifdef NOPE\nD = obj\nelse\nD = bon%% x\nendif\nall:\n\tcc a.c -o sorter\n$(D)/%%.o: %%.c\n\tcc -c $< -o $@\n'
sc_goal_mk tgt_inref 'ifdef NOPE\nD = x\nelse\nD = bonus.c\nendif\nall:\n\tcc a.c -o sorter\n$(D:%%.c=%%): x.o\n'
# A rule under a conditional may own the recipe lines after its endif.
sc_goal_mk cond_rule 'all:\n\tcc a.c -o sorter\nbonus:\nifeq (a,a)\nother:\nendif\n\t@echo hi\nbon%%:\n\tcc b.c -o checker\n'
# Each :: rule of a target is one of its own, searched for when it has no
# recipe, whatever the others have.
sc_goal_mk dc_two 'all:\n\tcc a.c -o sorter\nbonus:: ; @echo x\nbonus::\nbon%%:\n\tcc b.c -o checker\n'
sc_goal_mk dc_rec 'all:\n\tcc a.c -o sorter\nbonus:: ; @echo x\nbon%%:\n\tcc b.c -o checker\n'
# A suffix rule gives the goal a prerequisite, the source its suffix names,
# and make drops the ones written on its line. A suffix needs no . in front
# when .SUFFIXES names it, and make passes over a suffix rule's name for the
# default goal, by the suffixes named before that rule.
sc_goal_mk sfx_echo 'all:\n\tcc a.c -o sorter\n.c:\n\t@echo making $@\n'
sc_goal_mk sfx_dep 'all:\n\tcc a.c -o sorter\n.c: x.o\n\tcc $< -o $@\n'
sc_goal_mk sfx_nodot 'all:\n\tcc a.c -o sorter\n.SUFFIXES: _c us\n_cus:\n\tcc $< -o $@\n'
sc_goal_mk sfx_dg '.SUFFIXES: _c us\n_cus:\n\t@echo hi\nall:\n\tcc a.c -o sorter\n'
sc_goal_mk sfx_order '_cus:\n\t@echo hi\n.SUFFIXES: _c us\nall:\n\tcc a.c -o sorter\n'
# A ; in a rule's prerequisites starts its recipe, so a rule whose
# prerequisites the reader cannot expand may have a recipe after all, when a
# value may hold a ;: a pattern rule, a suffix rule and .DEFAULT among them.
# A value may hold one the Makefile never shows: a file it includes, or what
# a shell prints. Where nothing may hold one, a pattern rule with no recipe
# makes nothing.
sc_goal_mk semi_pat 'all:\n\tcc a.c -o sorter\nifdef NOPE\nR =\nelse\nR = ; cc b.c -o checker\nendif\nbon%%: $(R)\n'
sc_goal_mk semi_sfx 'all:\n\tcc a.c -o sorter\nifdef NOPE\nR =\nelse\nR = ; cc b.c -o checker\nendif\n.c: $(R)\n'
sc_goal_mk semi_dflt 'all:\n\tcc a.c -o sorter\nifdef NOPE\nR =\nelse\nR = ; cc b.c -o checker\nendif\n.DEFAULT: $(R)\n'
sc_goal_mk semi_incl 'all:\n\tcc a.c -o sorter\n-include more.mk\nbon%%: $(R)\n'
sc_goal_mk semi_none 'all:\n\tcc a.c -o sorter\nifdef NOPE\nR = b.o\nendif\nbon%%: $(R)\n'
sc_goal_mk semi_gate_incl 'all:\n\t@echo TODO\n-include more.mk\nbonus: $(R)\n'
sc_goal_mk semi_gate_shell 'all:\n\t@echo TODO\nbonus: $(shell cat more.txt)\n'
sc_goal_mk semi_gate_bang 'all:\n\t@echo TODO\nR != cat more.txt\nbonus: $(R)\n'
# And a ; may come from what make itself names: the name of a variable, which
# .VARIABLES lists (export names one too, and so may the environment), or
# what a function prints that call runs, by its name or by one a variable
# gives.
sc_goal_mk semi_vname 'all:\n\tcc a.c -o sorter\na;b := 1\nbon%%: $(word 1,$(subst a, ,$(filter a%%,$(.VARIABLES))))\n'
sc_goal_mk semi_vexport 'all:\n\tcc a.c -o sorter\nexport a;b\nbon%%: $(word 1,$(subst a, ,$(filter a%%,$(.VARIABLES))))\n'
sc_goal_mk semi_venv 'all:\n\tcc a.c -o sorter\nbon%%: $(word 1,$(subst a, ,$(filter a%%,$(.VARIABLES))))\n'
sc_goal_mk semi_call 'all:\n\t@echo TODO\nbonus: $(call shell,cat more.txt)\n'
sc_goal_mk semi_call_pat 'all:\n\tcc a.c -o sorter\nbon%%: $(call shell,cat more.txt)\n'
sc_goal_mk semi_call_name 'F = shell\nall:\n\t@echo TODO\nbonus: $(call $(F),cat more.txt)\n'
# A rule whose targets have a % in some and not in others: make gives it to
# each one without a %, and takes the default goal from the first of those
# that comes before any with a %.
sc_goal_mk mixed 'all:\n\tcc a.c -o sorter\nbonus %%.o:\n\tcc b.c -o checker\n'
sc_goal_mk mixed_pre 'all:\n\tcc a.c -o sorter\nbonus %%.o: b.o\n\t@echo hi\n'
sc_goal_mk mixed_dg 'bonus bon%%:\n\tcc b.c -o checker\nall:\n\t@echo hi\n'
sc_goal_mk mixed_dgpat '.x bon%% bonus:\n\tcc b.c -o checker\nall:\n\t@echo hi\n'
# What follows a rule's ; is its recipe, whatever it holds: a word there with
# a = in it sets no variable of the target's own. One between the : and the ;
# does, and the ; is then part of its value.
sc_goal_mk semi_assign 'all:\n\tcc a.c -o sorter\nbonus:;CFLAGS=-O2 cc b.c -o checker\n'
sc_goal_mk semi_assign_gate 'all:\n\t@echo TODO\nbonus: b.o;X=1 cc b.o -o checker\n'
sc_goal_mk semi_assign_dg 'all:;CC=cc cc a.c -o sorter\nbonus:\n\t@echo TODO\n'
sc_goal_mk semi_tsv 'all:\n\tcc a.c -o sorter\nbonus: X = a;cc b.c\nbonus:\n\t@echo TODO\n'
# make expands an include line as it reads it, and export, unexport and vpath
# lines too, so an eval there may write a rule. So may an eval that a
# variable holds, one that may hold one, and one that call runs.
sc_goal_mk eval_incl 'all:\n\tcc a.c -o sorter\n-include $(eval bonus: checker)\nbonus:\n\t@echo TODO\nchecker:\n\tcc b.c -o checker\n'
sc_goal_mk eval_export 'all:\n\tcc a.c -o sorter\nexport $(eval bonus: checker)\nbonus:\n\t@echo TODO\nchecker:\n\tcc b.c -o checker\n'
sc_goal_mk eval_vpath 'all:\n\tcc a.c -o sorter\nvpath %%.c $(eval bonus: checker)\nbonus:\n\t@echo TODO\nchecker:\n\tcc b.c -o checker\n'
sc_goal_mk eval_ifvar 'V = $(eval bonus: checker)\nifeq ($(V),)\nendif\nall:\n\tcc a.c -o sorter\nbonus:\n\t@echo TODO\nchecker:\n\tcc b.c -o checker\n'
sc_goal_mk eval_unsure 'ifeq (a,a)\nV = $(eval bonus: checker)\nendif\nR := $(V)\nall:\n\tcc a.c -o sorter\nbonus:\n\t@echo TODO\nchecker:\n\tcc b.c -o checker\n'
sc_goal_mk eval_call 'R := $(call eval,bonus: checker)\nall:\n\tcc a.c -o sorter\nbonus:\n\t@echo TODO\nchecker:\n\tcc b.c -o checker\n'
# .EXTRA_PREREQS gives each rule it is set for prerequisites of its own: every
# rule, set as any variable is, and one target's, set as its own.
sc_goal_mk xp_global 'all:\n\t@echo hi\n.EXTRA_PREREQS = checker\nchecker:\n\tcc b.c -o checker\nbonus:\n\t@echo TODO\n'
sc_goal_mk xp_target 'all:\n\tcc a.c -o a\nbonus: .EXTRA_PREREQS = all\n.PHONY: bonus\n'
sc_goal_mk xp_empty 'all:\n\tcc a.c -o a\n.EXTRA_PREREQS =\nbonus:\n\t@echo TODO\n'
# call runs a function by the name it is given, and call is one.
sc_goal_mk semi_callcall 'all:\n\t@echo TODO\nbonus: $(call call,shell,cat more.txt)\n'
sc_goal_mk semi_callcall_pat 'all:\n\tcc a.c -o sorter\nbon%%: $(call call,shell,cat more.txt)\n'
# make reads a name as a function's when any space follows it: a newline, a
# carriage return, and in a recipe a backslash-newline, which make turns into
# one space inside a reference before it expands the line.
sc_goal_mk fn_bsnl 'all:\n\tcc a.c -o sorter\nbonus:\n\t@echo $(shell\\\n\tcc b.c -o checker)\n'
sc_goal_mk fn_bsnl_brace 'all:\n\tcc a.c -o sorter\nbonus:\n\t@echo ${shell\\\n\tcc b.c -o checker}\n'
sc_goal_mk fn_bsnl_gate 'all:\n\t@echo TODO\nbonus:\n\t@echo $(shell\\\n\tcc b.c -o checker)\n'
sc_goal_mk fn_cr 'all:\n\tcc a.c -o sorter\nbonus:\n\t@echo $(shell\rcc b.c -o checker)\n'
sc_goal_mk nl_eval 'all: sorter\nsorter: a.c\n\tcc a.c -o sorter\ndefine R\n$(eval\nbonus: ; cc b.c -o checker)\nendef\nlib: $(R)\n'
sc_goal_mk nl_shell 'all:\n\t@echo TODO\ndefine R\n$(shell\ncat more.txt)\nendef\nbonus: $(R)\n'
# In a define, as on any line that is no recipe, make reads a backslash-newline
# as one space.
sc_goal_mk nl_bsnl 'all: sorter\nsorter: a.c\n\tcc a.c -o sorter\ndefine R\n$(eval\\\nbonus: ; cc b.c -o checker)\nendef\nlib: $(R)\n'
# What a != prints is a value make expands again where it is used, so it may
# hold an eval the Makefile never shows, which a conditional, a rule's
# prerequisites or a := then expand; a TAB line that is no recipe may set it.
sc_goal_mk bang_if 'all: sorter\nsorter: a.c\n\tcc a.c -o sorter\nX != printf %%s \047$$(ev\047\047al bonus: ; cc b.c -o checker)\047\nifeq ($(X),)\nendif\n'
sc_goal_mk bang_rule 'all: sorter\nsorter: a.c\n\tcc a.c -o sorter\nX != echo \047$$(ev\047\047al bonus: b.c)\047\nlib: $(X)\n'
sc_goal_mk bang_set 'all: sorter\nsorter: a.c\n\tcc a.c -o sorter\nX != printf %%s \047$$(ev\047\047al bonus: ; cc b.c -o checker)\047\nY := $(X)\n'
sc_goal_mk bang_tab 'ifeq (a,b)\nfoo:\nendif\n\tX != printf %%s \047$$(ev\047\047al bonus: ; cc b.c -o checker)\047\nY := $(X)\nall:\n\tcc a.c -o sorter\n'
# make gives an automatic variable its value only as it runs the rule, so
# what is worked out from one in a recipe -- a substitution of it, a name
# built from it, through a variable that holds it too -- may be any text,
# a ; cc among it. A plain one is a word an echo prints.
sc_goal_mk auto_subst 'all:\n\tcc a.c -o sorter\nbonus:\n\t@echo $(@:bonus=;cc b.c -o checker)\n'
sc_goal_mk auto_name 'bonus_CMD = cc b.c -o checker\nall:\n\tcc a.c -o sorter\nbonus:\n\t@$($@_CMD)\n'
sc_goal_mk auto_name_end 'CMD_bonus = cc b.c -o checker\nall:\n\tcc a.c -o sorter\nbonus:\n\t$(CMD_$@)\n'
sc_goal_mk auto_var 'V = $@\nall:\n\tcc a.c -o sorter\nbonus:\n\t@echo $(V:bonus=;cc b.c -o checker)\n'
sc_goal_mk auto_var_name 'V = $@\nbonus_CMD = cc b.c -o checker\nall:\n\tcc a.c -o sorter\nbonus:\n\t@$($(V)_CMD)\n'
sc_goal_mk auto_file 'all:\n\tcc a.c -o sorter\nbonus:\n\t@echo ${@F:bonus=;cc b.c -o checker}\n'
sc_goal_mk auto_stem 'all:\n\tcc a.c -o sorter\nbon%%:\n\t@echo $(*:us=;cc b.c -o checker)\n'
sc_goal_mk auto_dg 'all_CMD = cc a.c -o sorter\nall:\n\t@$($@_CMD)\nbonus: all\n\t@echo bonus\n'
sc_goal_mk auto_gate 'all:\n\t@echo $(@:all=;cc a.c -o sorter)\nbonus: all\n\t@echo bonus\n'
sc_goal_mk auto_plain 'all:\n\tcc a.c -o sorter\nbonus:\n\t@echo making $@ $(@F) ${@D} $^\n'
printf 'not a Makefile\n' > "$WORK/sc/goal/recipe/notes.txt"
# The status as a word, as sc_defines gives it.
sc_goal() {
	"$SH" "$TOOLS/stub_check.sh" --goal "$1" "$WORK/sc/goal/$2/Makefile" > /dev/null 2>&1
	echo "status $?"
}
want_out "stub_check --goal: a stub Makefile's rule is a stub" 'status 0' -- sc_goal bonus stub
want_out "stub_check --goal: no rule of that name is absent" 'status 3' -- sc_goal bonus none
want_out "stub_check --goal: ...and .PHONY alone gives none" 'status 3' -- sc_goal bonus phony
want_out "stub_check --goal: a rule that only echoes does nothing" 'status 0' -- sc_goal bonus echo
want_out "stub_check --goal: a prerequisite is something" 'status 1' -- sc_goal bonus prereq
want_out "stub_check --goal: a recipe is something" 'status 1' -- sc_goal bonus recipe
want_out "stub_check --goal: ...whose lines are printed" '4: 	cc b.c -o checker' -- \
	"$SH" "$TOOLS/stub_check.sh" --goal bonus "$WORK/sc/goal/recipe/Makefile"
want_out "stub_check --goal: a target named by a variable counts" 'status 1' -- sc_goal bonus var
want_out "stub_check --goal: a target-specific variable is no rule" 'status 3' -- sc_goal bonus tsv
want_out "stub_check --goal: a recipe after a ; counts" 'status 1' -- sc_goal bonus inline
want_out "stub_check --goal: - is the first rule make would run" 'status 1' -- sc_goal - dflt
want_out "stub_check --goal: ...not a later rule that does more" 'status 0' -- sc_goal - dflt_echo
want_out "stub_check --goal: an echo, then && a compiler, does more" 'status 1' -- sc_goal bonus and
want_out "stub_check --goal: ...and so does an echo; a compiler" 'status 1' -- sc_goal bonus semi
want_out "stub_check --goal: ...and a compiler on the line it continues" 'status 1' -- \
	sc_goal bonus cont
want_out "stub_check --goal: ...but not what an echo says in quotes" 'status 0' -- sc_goal bonus said
want_out "stub_check --goal: a comment ends at the line it continues" 'status 1' -- sc_goal bonus cmt
want_out "stub_check --goal: a prerequisite that expands to nothing is none" 'status 0' -- \
	sc_goal bonus empty
want_out "stub_check --goal: ...a substitution of an empty list is none" 'status 0' -- \
	sc_goal bonus esub
want_out "stub_check --goal: ...nor a pattern substitution of one" 'status 0' -- sc_goal bonus epat
want_out "stub_check --goal: ...but a substitution of files is one" 'status 1' -- sc_goal bonus fsub
want_out "stub_check --goal: a variable nothing has set is empty" 'status 0' -- sc_goal bonus unset
want_out "stub_check --goal: ...even one set further down" 'status 0' -- sc_goal bonus later
want_out "stub_check --goal: ...unless an included file may set it" 'status 1' -- \
	sc_goal bonus incl
want_out "stub_check --goal: a function it cannot expand counts" 'status 1' -- sc_goal bonus func
want_out "stub_check --goal: a TAB line above every rule is no recipe" 'status 1' -- \
	sc_goal bonus tab_assign_top
want_out "stub_check --goal: ...nor one under a conditional there" 'status 1' -- \
	sc_goal bonus tab_assign
want_out "stub_check --goal: ...nor one in its other branch" 'status 1' -- \
	sc_goal bonus tab_assign_ifelse
want_out "stub_check --goal: ...nor one after an assignment ends a rule" 'status 1' -- \
	sc_goal bonus tab_after_rule
want_out "stub_check --goal: ...and it says it could not tell" 'could not tell' -- \
	"$SH" "$TOOLS/stub_check.sh" --goal bonus "$WORK/sc/goal/tab_assign/Makefile"
want_out "stub_check --goal: a variable set with = takes later values" 'status 1' -- \
	sc_goal bonus recursive_late
want_out "stub_check --goal: ...and later appends" 'status 1' -- sc_goal bonus append_late
want_out "stub_check --goal: ...through another variable" 'status 1' -- sc_goal bonus pe_rec_chain
want_out "stub_check --goal: a value a conditional sets is not known" 'status 1' -- \
	sc_goal bonus ifelse
want_out "stub_check --goal: ...whichever branch would empty it" 'status 1' -- \
	sc_goal bonus ifdef_os_rev
want_out "stub_check --goal: ...nor a default goal one may hold" 'status 1' -- sc_goal - dg_ifeq
want_out "stub_check --goal: .DEFAULT_GOAL is expanded" 'status 1' -- sc_goal - dg_var
want_out "stub_check --goal: an echo && a compiler is no stub" 'status 1' -- \
	sc_goal bonus gate_echoand
want_out "stub_check --goal: ...nor is a recipe after a ;" 'status 1' -- sc_goal bonus gate_inline
want_out "stub_check --goal: CRLF line ends close a define" 'status 1' -- \
	sc_goal bonus crlf_define
want_out "stub_check --goal: ...and end a .DEFAULT_GOAL" 'status 1' -- sc_goal - crlf_dg
want_out "stub_check --goal: ...and are no prerequisite" 'status 0' -- sc_goal bonus crlf_empty
want_out "stub_check --goal: ...on a line a backslash continues too" 'status 0' -- \
	sc_goal bonus crlf_cont
want_out "stub_check --goal: an echo of a variable holding ; cc runs cc" 'status 1' -- \
	sc_goal bonus echo_semi
want_out "stub_check --goal: ...and one holding a \$(shell) counts" 'status 1' -- \
	sc_goal bonus echo_shell
want_out "stub_check --goal: an include may set a variable set empty" 'status 1' -- \
	sc_goal bonus incl_empty
want_out "stub_check --goal: an override of a name it cannot expand counts" 'status 1' -- \
	sc_goal bonus ovr_name
want_out "stub_check --goal: ...and so does one on a TAB line that may be no recipe" \
	'status 1' -- sc_goal bonus ovr_tab
want_out "stub_check --goal: an override undefine lets a plain assignment in" 'status 1' -- \
	sc_goal bonus ovr_undefine
want_out "stub_check --goal: ...and so does an override ?= that set nothing" 'status 1' -- \
	sc_goal bonus ovr_ifset
want_out "stub_check --goal: ...and an override += of nothing" 'status 1' -- \
	sc_goal bonus ovr_add_none
want_out "stub_check --goal: ...the default goal's too" 'status 1' -- sc_goal - ovr_dg
want_out "stub_check --goal: a prerequisite named with \\: counts" 'status 1' -- \
	sc_goal bonus esc_colon
want_out "stub_check --goal: a variable that refers to itself ends, and counts" \
	'does something' -- bounded 30 "$SH" "$TOOLS/stub_check.sh" --goal bonus \
	"$WORK/sc/goal/self_ref/Makefile"
want_out "stub_check --goal: ./ and a / after it are no part of a name" 'status 1' -- \
	sc_goal bonus dot_slash
want_out "stub_check --goal: ...nor are ./ and more slashes" 'status 1' -- \
	sc_goal bonus dot_slashes
want_out "stub_check --goal: ...in the default goal either" 'status 1' -- sc_goal - dg_slashes
want_out "stub_check --goal: ...nor in the rule it names" 'status 1' -- sc_goal - dg_dir
want_out "stub_check --goal: .SHELLSTATUS is make's, and may be set" 'status 1' -- \
	sc_goal bonus shellstatus
want_out "stub_check --goal: a pattern rule may make a goal with no rule" 'status 1' -- \
	sc_goal bonus pat_only
want_out "stub_check --goal: ...or one whose rule has no recipe" 'status 1' -- \
	sc_goal bonus pat_empty
want_out "stub_check --goal: ...and so may a rule for any name" 'status 1' -- \
	sc_goal bonus pat_any
want_out "stub_check --goal: ...or a suffix rule" 'status 1' -- sc_goal bonus sfx_one
want_out "stub_check --goal: ...or the recipe of .DEFAULT" 'status 1' -- sc_goal bonus dflt_rule
want_out "stub_check --goal: ...and says it could not tell which rule make takes" \
	'could not tell' -- "$SH" "$TOOLS/stub_check.sh" --goal bonus "$WORK/sc/goal/pat_only/Makefile"
want_out "stub_check --goal: ...but never for a .PHONY goal" 'status 3' -- \
	sc_goal bonus pat_phony
want_out "stub_check --goal: ...nor for a goal with a recipe" 'status 0' -- \
	sc_goal bonus pat_echo
want_out "stub_check --goal: ...nor through a pattern the name does not fit" 'status 3' -- \
	sc_goal bonus pat_obj
want_out "stub_check --goal: ...but one the reader cannot expand may fit any name" \
	'status 1' -- sc_goal bonus pat_unknown
want_out "stub_check --goal: ...as may one a conditional sets" 'status 1' -- \
	sc_goal bonus pat_cond
want_out "stub_check --goal: ...or a % inside a reference" 'status 1' -- sc_goal bonus tgt_inref
want_out "stub_check --goal: recipe lines after an endif may be another rule's" 'status 1' -- \
	sc_goal bonus cond_rule
want_out "stub_check --goal: a :: rule with no recipe is searched for" 'status 1' -- \
	sc_goal bonus dc_two
want_out "stub_check --goal: ...but not one with a recipe" 'status 0' -- sc_goal bonus dc_rec
want_out "stub_check --goal: a suffix rule gives the goal its source" 'status 1' -- \
	sc_goal bonus sfx_echo
want_out "stub_check --goal: ...whatever its own line names" 'status 1' -- sc_goal bonus sfx_dep
want_out "stub_check --goal: ...and its suffixes may have no ." 'status 1' -- \
	sc_goal bonus sfx_nodot
want_out "stub_check --goal: make may pass over one for the default goal" 'status 1' -- \
	sc_goal - sfx_dg
want_out "stub_check --goal: ...by the suffixes named before it" 'status 0' -- \
	sc_goal - sfx_order
want_out "stub_check --goal: a ; a value may hold starts a pattern rule's recipe" 'status 1' -- \
	sc_goal bonus semi_pat
want_out "stub_check --goal: ...and a suffix rule's" 'status 1' -- sc_goal bonus semi_sfx
want_out "stub_check --goal: ...and the recipe of .DEFAULT" 'status 1' -- sc_goal bonus semi_dflt
want_out "stub_check --goal: ...and a file it includes may hold the ;" 'status 1' -- \
	sc_goal bonus semi_incl
want_out "stub_check --goal: ...which it names as what it could not tell from" \
	'3: -include more.mk' -- "$SH" "$TOOLS/stub_check.sh" --goal bonus \
	"$WORK/sc/goal/semi_incl/Makefile"
want_out "stub_check --goal: ...but with no ; to hold, a rule with no recipe makes nothing" \
	'status 3' -- sc_goal bonus semi_none
want_out "stub_check --goal: a rule that may have a recipe so is no stub's" 'status 1' -- \
	sc_goal bonus semi_gate_incl
want_out "stub_check --goal: ...nor is one a \$(shell) may give one" 'status 1' -- \
	sc_goal bonus semi_gate_shell
want_out "stub_check --goal: ...nor one a != may give one" 'status 1' -- \
	sc_goal bonus semi_gate_bang
want_out "stub_check --goal: a variable's name, which .VARIABLES lists, may hold a ;" \
	'status 1' -- sc_goal bonus semi_vname
want_out "stub_check --goal: ...and so may a name export gives" 'status 1' -- \
	sc_goal bonus semi_vexport
want_out "stub_check --goal: ...or one the environment gives" 'status 1' -- \
	sc_goal bonus semi_venv
want_out "stub_check --goal: ...and what call runs a shell to print" 'status 1' -- \
	sc_goal bonus semi_call
want_out "stub_check --goal: ...for a pattern rule's list too" 'status 1' -- \
	sc_goal bonus semi_call_pat
want_out "stub_check --goal: ...and a function call runs by a name it is given" 'status 1' -- \
	sc_goal bonus semi_call_name
want_out "stub_check --goal: a plain target beside one with a % has the rule" 'status 1' -- \
	sc_goal bonus mixed
want_out "stub_check --goal: ...and its prerequisites" 'status 1' -- sc_goal bonus mixed_pre
want_out "stub_check --goal: ...and may be the default goal" 'status 1' -- sc_goal - mixed_dg
want_out "stub_check --goal: ...but not after a target with a %" 'status 0' -- \
	sc_goal - mixed_dgpat
want_out "stub_check --goal: a = after a rule's ; is in its recipe" 'status 1' -- \
	sc_goal bonus semi_assign
want_out "stub_check --goal: ...which is no stub's" 'status 1' -- sc_goal bonus semi_assign_gate
want_out "stub_check --goal: ...and in the default goal's after its ;" 'status 1' -- sc_goal - semi_assign_dg
want_out "stub_check --goal: ...but one before the ; sets a target's own value" 'status 0' -- \
	sc_goal bonus semi_tsv
want_out "stub_check --goal: an eval in an include line may write a rule" 'status 1' -- \
	sc_goal bonus eval_incl
want_out "stub_check --goal: ...and one in an export line" 'status 1' -- sc_goal bonus eval_export
want_out "stub_check --goal: ...and one in a vpath line" 'status 1' -- sc_goal bonus eval_vpath
want_out "stub_check --goal: ...and one a conditional expands from a variable" 'status 1' -- \
	sc_goal bonus eval_ifvar
want_out "stub_check --goal: ...and one a variable it cannot know may hold" 'status 1' -- \
	sc_goal bonus eval_unsure
want_out "stub_check --goal: ...and one that call runs" 'status 1' -- sc_goal bonus eval_call
want_out "stub_check --goal: .EXTRA_PREREQS may give every rule a prerequisite" 'status 1' -- \
	sc_goal bonus xp_global
want_out "stub_check --goal: ...the default goal among them" 'status 1' -- sc_goal - xp_global
want_out "stub_check --goal: ...and a target's own one gives it one" 'status 1' -- \
	sc_goal bonus xp_target
want_out "stub_check --goal: ...but an empty one gives none" 'status 0' -- sc_goal bonus xp_empty
want_out "stub_check --goal: ...and what call runs call to run a shell for" 'status 1' -- \
	sc_goal bonus semi_callcall
want_out "stub_check --goal: ...in a pattern rule's list as well" 'status 1' -- \
	sc_goal bonus semi_callcall_pat
want_out "stub_check --goal: a name before a backslash-newline is a function's" 'status 1' -- \
	sc_goal bonus fn_bsnl
want_out "stub_check --goal: ...in braces too" 'status 1' -- sc_goal bonus fn_bsnl_brace
want_out "stub_check --goal: ...and it is no stub's" 'status 1' -- sc_goal bonus fn_bsnl_gate
want_out "stub_check --goal: ...and so is one before a carriage return" 'status 1' -- \
	sc_goal bonus fn_cr
want_out "stub_check --goal: ...or a newline in a define, an eval's" 'status 1' -- \
	sc_goal bonus nl_eval
want_out "stub_check --goal: ...and a shell's, which is no stub's" 'status 1' -- \
	sc_goal bonus nl_shell
want_out "stub_check --goal: ...and a backslash-newline in a define too" 'status 1' -- \
	sc_goal bonus nl_bsnl
want_out "stub_check --goal: a != may give an eval a conditional expands" 'status 1' -- \
	sc_goal bonus bang_if
want_out "stub_check --goal: ...and one a rule's prerequisites expand" 'status 1' -- \
	sc_goal bonus bang_rule
want_out "stub_check --goal: ...and one a := expands" 'status 1' -- sc_goal bonus bang_set
want_out "stub_check --goal: ...set on a TAB line that is no recipe" 'status 1' -- \
	sc_goal bonus bang_tab
want_out "stub_check --goal: a substitution of an automatic variable may run cc" 'status 1' -- \
	sc_goal bonus auto_subst
want_out "stub_check --goal: ...which it names as what it could not tell from" \
	'4: 	@echo $(@:bonus=;cc b.c -o checker)' -- "$SH" "$TOOLS/stub_check.sh" --goal bonus \
	"$WORK/sc/goal/auto_subst/Makefile"
want_out "stub_check --goal: ...and a name built from one may be any variable's" 'status 1' -- \
	sc_goal bonus auto_name
want_out "stub_check --goal: ...wherever it stands in the name" 'status 1' -- \
	sc_goal bonus auto_name_end
want_out "stub_check --goal: ...and a variable that holds one is as unknown" 'status 1' -- \
	sc_goal bonus auto_var
want_out "stub_check --goal: ...in a name built from it as well" 'status 1' -- \
	sc_goal bonus auto_var_name
want_out "stub_check --goal: ...and so is the F or D form of one" 'status 1' -- \
	sc_goal bonus auto_file
want_out "stub_check --goal: ...and a stem in a pattern rule make may take" 'status 1' -- \
	sc_goal bonus auto_stem
want_out "stub_check --goal: ...and in the default goal's recipe" 'status 1' -- \
	sc_goal - auto_dg
want_out "stub_check --goal: ...and such a recipe is no stub's" 'status 1' -- \
	sc_goal bonus auto_gate
want_out "stub_check --goal: ...but a plain one is a word an echo prints" 'status 0' -- \
	sc_goal bonus auto_plain
want_broken "stub_check --goal: a name that is no rule's is refused" \
	"needs a rule's name" -- "$SH" "$TOOLS/stub_check.sh" --goal '-B' "$WORK/sc/goal/recipe/Makefile"
want_broken "stub_check --goal: ...and so is a file of another kind" \
	'reads a Makefile' -- "$SH" "$TOOLS/stub_check.sh" --goal bonus "$WORK/sc/goal/recipe/notes.txt"

# ---- REPO MODE, which is the mode that decides whether answers get published --
#
# Everything above drives --file mode, and --file mode reads the path it is
# handed. Repo mode does something else: it takes the file LIST from the INDEX
# (git ls-files) and used to read the CONTENT from disk. Those are two different
# trees, and `git commit` publishes the first one.
#
# A template publish ran this twice -- after stubbing, then again, over the
# staged tree. Both runs read the same working-tree files, so the second
# proved nothing the first had not, and an answer left in
# the index behind a stubbed file on disk was reported as a stub. That is the
# whole publish gate reporting OK on the one input it exists to reject.
#
# This needs a populated git repository, which is why repo mode had no arm at
# all. It is worth the fixture: this is the only failure in the repo whose blast
# radius is a permanently public answer.
mkdir -p "$WORK/screpo/c-piscine-c-99/deliverable/ex00"
(
	cd "$WORK/screpo" || exit 1
	git init -q .
	git config user.email selftest@example.invalid
	git config user.name selftest
	# Any body that is not a stub will do, so this one is made up: like
	# ft_selftest_twice and ft_selftest_mix, it answers no exercise. It used to
	# be a working recursive factorial -- c-05 ex01's recursion, shipped in the
	# one file that tests the gate keeping answers out of the template.
	printf 'int\tft_x(int n)\n{\n\tif (n > 7)\n\t\treturn (n - 7);\n\treturn (n * 5);\n}\n' \
		> c-piscine-c-99/deliverable/ex00/ft_x.c
	git add -A && git commit -q -m answer
	# Stub it ON DISK ONLY. The index still holds the answer -- exactly what a
	# forgotten or partial `git add -A` leaves behind.
	printf '%s\n\nint\tft_x(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' "$SC_H" \
		> c-piscine-c-99/deliverable/ex00/ft_x.c
) >/dev/null 2>&1

want_red   "stub_check: an answer STAGED behind a stubbed file is caught" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo" "$SH" "$TOOLS/stub_check.sh"

# And the reverse, so the arm above is not passing for some unrelated reason:
# once the stub is staged too, the same tree is clean.
( cd "$WORK/screpo" && git add -A && git commit -q -m stubbed ) >/dev/null 2>&1
want_green "stub_check: ... and passes once the stub is the staged content" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo" "$SH" "$TOOLS/stub_check.sh"

# Repo mode refuses an empty file and a header-less one too, and names every
# one before it stops: two of them staged beside the stub, two reasons, exit 2.
# Unstaged again after, so the arms below see the tree they were written for.
(
	cd "$WORK/screpo" || exit 1
	mkdir -p c-piscine-c-99/deliverable/ex01
	: > c-piscine-c-99/deliverable/ex01/ft_y.c
	printf 'int\tft_z(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' \
		> c-piscine-c-99/deliverable/ex01/ft_z.c
	git add -A
) >/dev/null 2>&1
# Each by its own reason: the arms asked only for the path and exit 2, so a
# run that gave both files the same reason, or swapped them, passed. The
# output joined, each path to the line after it, says which reason is whose.
sc_reasons() {
	_scr=$(env BUILD_WORKSPACE_DIRECTORY="$1" "$SH" "$TOOLS/stub_check.sh" 2>&1)
	_scs=$?
	printf '%s\n' "$_scr" | awk '{ l = $0; sub(/^ +/, "", l); if (p != "") print p ": " l; p = l }'
	return "$_scs"
}
want_broken "stub_check: a staged empty file is refused" \
	'ex01/ft_y.c: is empty' -- sc_reasons "$WORK/screpo"
want_broken "stub_check: ...and a header-less one beside it" \
	'ex01/ft_z.c: has no 42 header' -- sc_reasons "$WORK/screpo"
( cd "$WORK/screpo" && git rm -rqf c-piscine-c-99/deliverable/ex01 ) >/dev/null 2>&1

# A tracked deliverable of a kind no checker knows must be REPORTED, not
# dropped. --file mode has always exited 2 on one; repo mode silently skipped
# it, which is how c-08's four finished headers once shipped under "OK — all 123
# deliverable(s) are stubs". The same hole was open one kind further along:
# rush-02 turned in a README.md carrying a teammate's real 42 login and email.
# A README.md is a kind of its own now (the arms after these); a notes file
# beside it is still one nothing reads.
(
	cd "$WORK/screpo" || exit 1
	printf 'By: someone <someone@student.42.fr>\n' \
		> c-piscine-c-99/deliverable/ex00/notes.txt
	git add -A && git commit -q -m notes
) >/dev/null 2>&1
# It is no verdict (exit 2), never the 1 of a body found: the template build
# reads 1 as an answer to stub.
want_broken "stub_check: a deliverable of an unknown kind is reported" \
	"c-piscine-c-99/deliverable/ex00/notes.txt" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo" "$SH" "$TOOLS/stub_check.sh"
# ...and counted as a file nothing read, never as an implementation: the tree
# holds one stub and one README, and the summary once said "1 of 1
# deliverable(s) still contain an implementation" over it (Rush 02's two copies
# of 42's dictionary read "2 of 2"), sending a maintainer to hunt an answer in
# files that hold none.
want_broken "stub_check: an unread file is counted apart" \
	"1 file(s) above were never read" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo" "$SH" "$TOOLS/stub_check.sh"
want_broken_without "stub_check: ...and never as an implementation" \
	"still contain an implementation" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo" "$SH" "$TOOLS/stub_check.sh"

# A README.md under deliverable/ is READ, as the md kind: a stub of comments
# beside the stub above is a tree with nothing to ship, and one with a line
# of prose holds the student's own words. It was listed as never read, so the
# template's README stub failed its own publish gate.
(
	cd "$WORK/screpo" || exit 1
	git rm -q c-piscine-c-99/deliverable/ex00/notes.txt
	printf '<!--\n  Say what this project is.\n-->\n' \
		> c-piscine-c-99/deliverable/README.md
	git add -A && git commit -q -m readme-stub
) >/dev/null 2>&1
want_green "stub_check: a staged README stub is a stub" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo" "$SH" "$TOOLS/stub_check.sh"
(
	cd "$WORK/screpo" || exit 1
	printf '<!--\n  Say what this project is.\n-->\nIt is a selftest.\n' \
		> c-piscine-c-99/deliverable/README.md
	git add -A && git commit -q -m readme-written
) >/dev/null 2>&1
want_out   "stub_check: a staged README with prose is reported" \
	"4: It is a selftest." -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo" "$SH" "$TOOLS/stub_check.sh"
want_broken_none "stub_check: ...as read, never as unread" \
	"were never read" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo" "$SH" "$TOOLS/stub_check.sh"
( cd "$WORK/screpo" && git rm -q c-piscine-c-99/deliverable/README.md &&
	git commit -q -m no-readme ) >/dev/null 2>&1

# Where git refuses the folder, the refusal carries git's reason. It used to be
# "git could not list the index" and nothing more, with git's own line thrown
# away: in a checkout owned by another user -- a container, a shared machine --
# that line is the only one saying what to fix. A folder that is no repository
# is one refusal; a repository git calls of dubious ownership is the other,
# made with git's own test switch where this git has it.
mkdir -p "$WORK/scnorepo/c-piscine-c-99/deliverable/ex00"
want_broken "stub_check: where git refuses the folder, it says why" \
	'not a git repository' -- \
	env GIT_CEILING_DIRECTORIES="$WORK" BUILD_WORKSPACE_DIRECTORY="$WORK/scnorepo" \
		"$SH" "$TOOLS/stub_check.sh"
if env GIT_TEST_ASSUME_DIFFERENT_OWNER=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
	git -C "$WORK/screpo" ls-files 2>&1 | grep -q 'dubious ownership'; then
	want_broken "stub_check: ...and a dubious-ownership refusal too" \
		'dubious ownership' -- \
		env GIT_TEST_ASSUME_DIFFERENT_OWNER=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
			BUILD_WORKSPACE_DIRECTORY="$WORK/screpo" "$SH" "$TOOLS/stub_check.sh"
else
	st_skipped "stub_check: ...and a dubious-ownership refusal too" \
		"skipped (this git cannot be made to refuse a folder)"
fi

# AGENTS.md §0's zone is everything under deliverable/ AND everything under
# generators/, with no third place -- and a zone the checker does not read is a
# zone that ships. Two holes, one fixture: a helper beside a generator, and work
# written at a project's root, where Piscine Reloaded's Vogsphere repo keeps its
# exNN/ folders. Each has a green twin, so the reds are not passing for an
# unrelated reason.
mkdir -p "$WORK/screpo2/c-piscine/c-piscine-c-99/deliverable/ex00" \
	"$WORK/screpo2/c-piscine/c-piscine-c-99/generators"
(
	cd "$WORK/screpo2" || exit 1
	git init -q .
	git config user.email selftest@example.invalid
	git config user.name selftest
	printf '%s\n\nint\tft_x(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' "$SC_H" \
		> c-piscine/c-piscine-c-99/deliverable/ex00/ft_x.c
	printf '#!/bin/sh\n# Create z.\n# TODO: write the commands.\n:\n' \
		> c-piscine/c-piscine-c-99/generators/ex00.sh
	: > c-piscine/c-piscine-c-99/BUILD.bazel
	printf '# c-piscine-c-99\n' > c-piscine/c-piscine-c-99/README.md
	git add -A && git commit -q -m stubs
) >/dev/null 2>&1
want_green "stub_check: a project's BUILD, README and stubs are fine" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo2" "$SH" "$TOOLS/stub_check.sh"
# A group project's team file sits there too (rush-00's team.bzl: which variant
# the team owes). It is harness configuration, read by the BUILD file, and it
# ships in the template; the third-place rule must not call it work.
( cd "$WORK/screpo2" && printf 'ASSIGNED = ["00"]\n' > c-piscine/c-piscine-c-99/team.bzl &&
	git add -A && git commit -q -m team ) >/dev/null 2>&1
want_green "stub_check: a project's team.bzl is not a third place" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo2" "$SH" "$TOOLS/stub_check.sh"
( cd "$WORK/screpo2" && printf 'touch z\n' > c-piscine/c-piscine-c-99/generators/helper.sh &&
	git add -A && git commit -q -m helper ) >/dev/null 2>&1
want_broken "stub_check: a non-exNN file under generators/ is reported" \
	"generators/helper.sh" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo2" "$SH" "$TOOLS/stub_check.sh"
( cd "$WORK/screpo2" && git rm -q c-piscine/c-piscine-c-99/generators/helper.sh &&
	mkdir -p c-piscine-reloaded/c-piscine-reloaded/ex06 &&
	printf 'int\tft_x(void)\n{\n\treturn (42);\n}\n' \
		> c-piscine-reloaded/c-piscine-reloaded/ex06/ft_x.c &&
	git add -A && git commit -q -m third-place ) >/dev/null 2>&1
want_broken "stub_check: work outside deliverable/ in a project is reported" \
	"no third place" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo2" "$SH" "$TOOLS/stub_check.sh"

# The template ships a placeholder for each of 42's files in tools/resources.tsv,
# beside its project's BUILD file: <file>.DOWNLOAD-ME.txt. It is allowed by its
# exact registered path and nothing wider -- the same name in another project,
# or any other .txt, is still a third place.
( cd "$WORK/screpo2" && git rm -q -r c-piscine-reloaded &&
	mkdir -p tools c-piscine/c-piscine-c-98 &&
	printf 'c-piscine/c-piscine-c-99\tdata.bin\tc-piscine/c-piscine-c-99/data.bin\tharness\t*data.bin\t-\t-\tfixture\n' \
		> tools/resources.tsv &&
	printf 'download data.bin\n' > c-piscine/c-piscine-c-99/data.bin.DOWNLOAD-ME.txt &&
	git add -A && git commit -q -m placeholder ) >/dev/null 2>&1
want_green "stub_check: a registered file's placeholder is not a third place" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo2" "$SH" "$TOOLS/stub_check.sh"
( cd "$WORK/screpo2" && : > c-piscine/c-piscine-c-98/BUILD.bazel &&
	printf 'download data.bin\n' > c-piscine/c-piscine-c-98/data.bin.DOWNLOAD-ME.txt &&
	git add -A && git commit -q -m elsewhere ) >/dev/null 2>&1
want_broken "stub_check: ...but the same name in another project is" \
	"c-piscine-c-98/data.bin.DOWNLOAD-ME.txt" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo2" "$SH" "$TOOLS/stub_check.sh"

# 42's file itself, at the one path its row names, is not a third place either:
# every consumer of the registry follows from the row, and this list used to
# name resources.tar.gz and *.dict instead -- so a newly registered file at a
# project root was reported, while any .dict anywhere went through. Each has a
# twin: the registered file at another path, and an unregistered .dict.
( cd "$WORK/screpo2" && git rm -q c-piscine/c-piscine-c-98/data.bin.DOWNLOAD-ME.txt &&
	printf 'bytes\n' > c-piscine/c-piscine-c-99/data.bin &&
	git add -A && git commit -q -m registered ) >/dev/null 2>&1
want_green "stub_check: a registered file at its path is not a third place" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo2" "$SH" "$TOOLS/stub_check.sh"
( cd "$WORK/screpo2" && printf 'bytes\n' > c-piscine/c-piscine-c-98/data.bin &&
	git add -A && git commit -q -m unregistered-path ) >/dev/null 2>&1
want_broken "stub_check: ...but the same file at another path is" \
	"c-piscine-c-98/data.bin" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo2" "$SH" "$TOOLS/stub_check.sh"
( cd "$WORK/screpo2" && git rm -q c-piscine/c-piscine-c-98/data.bin &&
	printf 'zero: zero\n' > c-piscine/c-piscine-c-99/words.dict &&
	git add -A && git commit -q -m dict ) >/dev/null 2>&1
want_broken "stub_check: ...and so is a .dict nobody registered" \
	"c-piscine-c-99/words.dict" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo2" "$SH" "$TOOLS/stub_check.sh"

# What a project keeps beside its zone is allowed THERE, and nowhere deeper:
# its BUILD file, README, .gitignore, team file and subject at the project's
# root, and its tests/ there; a course folder's own README. The allowlist
# matched those names at any depth, so a README written in a third-place
# folder, a PDF, a team.bzl or a tests/ folder of one's own under it went
# unread; and the course root's README and a cursus project holding only its
# subject must stay allowed.
mkdir -p "$WORK/screpo5/c-piscine/c-piscine-c-99/deliverable/ex00" \
	"$WORK/screpo5/c-piscine/c-piscine-c-99/tests" "$WORK/screpo5/cursus/Milestone_9/selftest_proj"
(
	cd "$WORK/screpo5" || exit 1
	git init -q .
	git config user.email selftest@example.invalid
	git config user.name selftest
	cp "$WORK/sc/stub.c" c-piscine/c-piscine-c-99/deliverable/ex00/ft_x.c
	: > c-piscine/c-piscine-c-99/BUILD.bazel
	printf 'selftest\n' > c-piscine/c-piscine-c-99/tests/cases.txt
	printf '# cursus\n' > cursus/README.md
	printf '%%PDF-1.4\n' > cursus/Milestone_9/selftest_proj/en.subject.pdf
	git add -A && git commit -q -m allowed
) > /dev/null 2>&1
want_green "stub_check: a course's README and a subject-only project are fine" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo5" "$SH" "$TOOLS/stub_check.sh"
(
	cd "$WORK/screpo5" || exit 1
	mkdir -p c-piscine/c-piscine-c-99/ex06/tests c-piscine/c-piscine-c-99/ex08
	printf 'Notes on the selftest.\n' > c-piscine/c-piscine-c-99/ex06/README.md
	printf '%%PDF-1.4\n' > c-piscine/c-piscine-c-99/ex06/notes.pdf
	printf 'int\tft_x(void)\n{\n\treturn (42);\n}\n' > c-piscine/c-piscine-c-99/ex06/tests/ft_x.c
	printf 'int\tft_x(void);\n' > c-piscine/c-piscine-c-99/ex08/team.bzl
	git add -A && git commit -q -m nested
) > /dev/null 2>&1
want_broken "stub_check: a README in a third place is reported" \
	"c-piscine-c-99/ex06/README.md" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo5" "$SH" "$TOOLS/stub_check.sh"
want_broken "stub_check: ...and a PDF there" "c-piscine-c-99/ex06/notes.pdf" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo5" "$SH" "$TOOLS/stub_check.sh"
want_broken "stub_check: ...and a tests/ folder of its own" "c-piscine-c-99/ex06/tests/ft_x.c" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo5" "$SH" "$TOOLS/stub_check.sh"
want_broken "stub_check: ...and a team.bzl" "c-piscine-c-99/ex08/team.bzl" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo5" "$SH" "$TOOLS/stub_check.sh"

# THE STATUS IS THE VERDICT, in repo mode as in --file: 0 every deliverable
# is a stub, 1 at least one holds a body, and 2 no verdict. Exit 1 also came
# out where no body was found -- files it never read and nothing else, those
# beside a refused file, a zone with no file of a known kind (whose files it
# then never named), a workspace it could not enter -- and the template build
# reads 1 as "found an answer in the INDEX: stub it".
mkdir -p "$WORK/screpo4/c-piscine-c-99/deliverable/ex00"
(
	cd "$WORK/screpo4" || exit 1
	git init -q .
	git config user.email selftest@example.invalid
	git config user.name selftest
	printf 'selftest notes\n' > c-piscine-c-99/deliverable/ex00/notes.txt
	git add -A && git commit -q -m notes
) > /dev/null 2>&1
want_broken "stub_check: a zone of unread files alone names them" \
	"c-piscine-c-99/deliverable/ex00/notes.txt" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo4" "$SH" "$TOOLS/stub_check.sh"
want_broken "stub_check: ...as a zone with no deliverable, no verdict" \
	"no deliverables found" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo4" "$SH" "$TOOLS/stub_check.sh"
( cd "$WORK/screpo4" && : > c-piscine-c-99/deliverable/ex00/ft_y.c &&
	git add -A && git commit -q -m empty ) > /dev/null 2>&1
want_broken "stub_check: a refused file beside an unread one is no verdict" \
	"ex00/ft_y.c" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/screpo4" "$SH" "$TOOLS/stub_check.sh"
want_broken "stub_check: a workspace it cannot enter is no verdict" \
	"cannot enter the workspace" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/sc-no-such-folder" "$SH" "$TOOLS/stub_check.sh"

# The approved-header pins are by CONTENT, and this is the arm that proves it.
# The fixture is named ft_list.h and shaped like ft_list.h — a path- or
# basename-keyed allowlist would wave it straight through — but its bytes are
# not the approved ones, so it must go red. That distinction is the whole reason
# the pin is a hash: "someone forgot to reduce this header" and "this header is
# the reviewed one" are the same path, and only the content tells them apart.
printf '%s\n\n#ifndef FT_LIST_H\n# define FT_LIST_H\n\ntypedef struct s_list\n{\n\tstruct s_list\t*next;\n\tvoid\t\t\t*data;\n}\t\t\t\tt_list;\n\n#endif\n' \
	"$SC_H" > "$WORK/sc/ft_list.h"
want_red   "stub_check: a header is approved by its bytes, not by its name" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/ft_list.h"

# ...and not by its bytes ALONE either. Approval is (hash, path), because the
# first version keyed on content and c-09's includes/ft.h (approved then, not
# now) held the same five prototypes as c-08 ex00's ft.h -- so approving one
# approved the other, and c-08 ex00 shipped its answer and went GREEN. Identical
# bytes, opposite meanings, decided by where the file sits. These two are
# byte-identical and neither is at an approved path, so both must be red.
cp "$WORK/sc/ft_list.h" "$WORK/sc/ft_list_elsewhere.h"
want_red   "stub_check: identical bytes, first path" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/ft_list.h"
want_red   "stub_check: identical bytes, second path" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/ft_list_elsewhere.h"

# ...and its path is the path however it is spelled. answer_scan.sh hands each
# file over as ./<path>, and the glob was matched against the spelling, so an
# approved header there was "an implementation" (`--file ./c-piscine/...
# /ft_list.h` gave 1, the same path without ./ gave 0). No approved header can
# be a fixture here, so the arms run a copy of stub_check.sh whose list holds
# one more entry: a made-up header at a made-up path. Its first arm is what
# proves the copy approves it.
mkdir -p "$WORK/scapp/tree/c-piscine/c-piscine-c-98/deliverable/ex00"
printf '%s\n\n#ifndef SC_KEPT_H\n# define SC_KEPT_H\n\ntypedef struct s_sc_kept\n{\n\tint\tn;\n}\tt_sc_kept;\n\n#endif\n' \
	"$SC_H" > "$WORK/scapp/tree/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h"
_sck=$("$SH" "$TOOLS/stub_check.sh" --hash \
	"$WORK/scapp/tree/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h" | cut -d' ' -f1)
awk -v e="$_sck c-piscine/c-piscine-c-98/deliverable/*/sc_kept.h selftest-fixture" \
	'{ print } /^APPROVED_HEADERS=.$/ { print e }' "$TOOLS/stub_check.sh" > "$WORK/scapp/stub_check.sh"
# sc_app_ws DIR WS PATH -- the copy, run from DIR with WS as its workspace,
# as `bazel run` names one; sc_app PATH, from the tree, the tree's workspace.
sc_app_ws() { ( cd "$1" && env BUILD_WORKSPACE_DIRECTORY="$2" "$SH" "$WORK/scapp/stub_check.sh" --file "$3" ); }
sc_app() { sc_app_ws "$WORK/scapp/tree" "$WORK/scapp/tree" "$1"; }
want_green "stub_check: an approved header at its path passes" -- \
	sc_app c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h
want_green "stub_check: ...and so it does spelled ./<path>" -- \
	sc_app ./c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h
# ...and in every other spelling of that path. Only a leading ./ was taken
# off, so `.//`, `/./` and `//` in it, an absolute path and one relative to a
# module folder each made the approved header "an implementation" -- and
# `42 stubcheck --file` hands over an absolute path every time (V151, V232).
want_green "stub_check: ...spelled .//<path>" -- \
	sc_app .//c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h
want_green "stub_check: ...spelled with /./ in it" -- \
	sc_app c-piscine/./c-piscine-c-98/deliverable/./ex00/sc_kept.h
want_green "stub_check: ...spelled with // in it" -- \
	sc_app c-piscine//c-piscine-c-98/deliverable//ex00/sc_kept.h
# A path is the file's place in the workspace, wherever the check runs from;
# a link to the tree, named as the workspace, is the same tree.
ln -s tree "$WORK/scapp/treelink"
want_green "stub_check: ...given by its absolute path" -- \
	sc_app_ws "$WORK" "$WORK/scapp/tree" \
	"$WORK/scapp/tree/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h"
want_green "stub_check: ...relative to its module's folder" -- \
	sc_app_ws "$WORK/scapp/tree/c-piscine/c-piscine-c-98" "$WORK/scapp/tree" \
	deliverable/ex00/sc_kept.h
want_green "stub_check: ...with a link to the tree as the workspace" -- \
	sc_app_ws "$WORK" "$WORK/scapp/treelink" \
	"$WORK/scapp/tree/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h"
# None of that widens the path rule: the same bytes one folder down are at
# no approved path, however they are spelled, and a path is never matched on
# its end.
mkdir -p "$WORK/scapp/tree/elsewhere/c-piscine/c-piscine-c-98/deliverable/ex00"
cp "$WORK/scapp/tree/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h" \
	"$WORK/scapp/tree/elsewhere/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h"
want_red   "stub_check: ...the same bytes elsewhere, absolute, stay red" -- \
	sc_app_ws "$WORK" "$WORK/scapp/tree" \
	"$WORK/scapp/tree/elsewhere/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h"
want_red   "stub_check: ...and relative to the workspace" -- \
	sc_app_ws "$WORK/scapp/tree" "$WORK/scapp/tree" \
	elsewhere/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h
want_red   "stub_check: ...and from the copy's own folder" -- \
	sc_app_ws "$WORK/scapp/tree/elsewhere" "$WORK/scapp/tree" \
	c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h
# A file outside the workspace has no place in it, so its path is read from
# the folder the check runs in, cleaned up the same way: that is a fixture
# tree's case, and answer_scan's copy of the index when a zone file is not
# on disk.
mkdir -p "$WORK/scapp/otherws"
want_green "stub_check: ...outside the workspace, from where it runs" -- \
	sc_app_ws "$WORK/scapp/tree" "$WORK/scapp/otherws" \
	.//c-piscine/./c-piscine-c-98/deliverable//ex00/sc_kept.h
# ...but a `..` is never taken out of that text, and a path outside the
# workspace that still holds one names no place: an approval glob's `*`
# matches `..` segments too, so the same bytes outside the tree, spelled
# through the approved folder, were approved.
mkdir -p "$WORK/scapp/outside"
cp "$WORK/scapp/tree/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h" \
	"$WORK/scapp/outside/sc_kept.h"
want_red   "stub_check: ...a copy outside, via the approved folder" -- \
	sc_app c-piscine/c-piscine-c-98/deliverable/../../../../outside/sc_kept.h
# With no BUILD_WORKSPACE_DIRECTORY, the workspace is the folder above the
# script's own, which is how a checkout runs it by hand (`sh tools/
# stub_check.sh --file ...`, AGENTS.md section 0) and how V232 was found:
# an absolute path, from anywhere, made the approved header "an
# implementation". So this copy sits where a checkout keeps it.
mkdir -p "$WORK/scapp/tree/tools"
cp "$WORK/scapp/stub_check.sh" "$WORK/scapp/tree/tools/stub_check.sh"
# sc_app_own DIR SCRIPT PATH -- the tree's own copy, as SCRIPT from DIR,
# with no workspace named.
sc_app_own() { ( cd "$1" && unset BUILD_WORKSPACE_DIRECTORY && "$SH" "$2" --file "$3" ); }
want_green "stub_check: ...absolute, no workspace named" -- \
	sc_app_own "$WORK" "$WORK/scapp/tree/tools/stub_check.sh" \
	"$WORK/scapp/tree/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h"
want_green "stub_check: ...module-relative, no workspace named" -- \
	sc_app_own "$WORK/scapp/tree/c-piscine/c-piscine-c-98" ../../tools/stub_check.sh \
	deliverable/ex00/sc_kept.h
want_red   "stub_check: ...one folder down, no workspace named" -- \
	sc_app_own "$WORK" "$WORK/scapp/tree/tools/stub_check.sh" \
	"$WORK/scapp/tree/elsewhere/c-piscine/c-piscine-c-98/deliverable/ex00/sc_kept.h"

# And the hash itself must ignore the 42 header, or every re-stamp would revoke
# every approval. Same bytes below the block, two different identities in it.
printf '/* By: marvin <marvin@42.fr> */\n#ifndef X_H\n# define X_H\n#endif\n' > "$WORK/sc/h1.h"
printf '/* By: someone <someone@42.fr> */\n#ifndef X_H\n# define X_H\n#endif\n' > "$WORK/sc/h2.h"
_h1=$("$SH" "$TOOLS/stub_check.sh" --hash "$WORK/sc/h1.h" | cut -d' ' -f1)
_h2=$("$SH" "$TOOLS/stub_check.sh" --hash "$WORK/sc/h2.h" | cut -d' ' -f1)
# The emptiness test is the point. This was one `[ "$(...)" = "$(...)" ]`, so a
# --hash mode that printed NOTHING AT ALL compared "" with "" and the arm
# reported success -- an assertion that two hashes agree, satisfied by there
# being no hashes. A 32-character md5 prefix is what it is supposed to produce.
if [ ${#_h1} -ne 32 ] || [ ${#_h2} -ne 32 ]; then
	printf '  %-52s %s\n' "stub_check: --hash ignores the 42 header block" \
		"FAIL < (--hash produced no hash: '$_h1' / '$_h2')"
	FAIL=$((FAIL + 1))
elif [ "$_h1" = "$_h2" ]; then
	printf '  %-52s %s\n' "stub_check: --hash ignores the 42 header block" "ok (green, as required)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "stub_check: --hash ignores the 42 header block" \
		"FAIL < (a re-stamp would revoke every approval)"
	FAIL=$((FAIL + 1))
fi

# ...and it must NOT ignore anything else that shares a line with a comment.
# `^/\*.*\*/$` reads as "a line that is one comment", but `.*` is greedy, so
# it also matched a line whose middle is code between two comment markers.
# Reproduced: the pair below, differing by a whole variable definition,
# produced the same hash -- so an approved entry approved the smuggled copy.
printf '/* By: marvin <marvin@42.fr> */\n/* */ int g_answer = 42; /* */\n#ifndef X_H\n# define X_H\n#endif\n' > "$WORK/sc/h3.h"
_h3=$("$SH" "$TOOLS/stub_check.sh" --hash "$WORK/sc/h3.h" | cut -d' ' -f1)
if [ ${#_h3} -ne 32 ]; then
	printf '  %-52s %s\n' "stub_check: --hash sees code between two comments" \
		"FAIL < (--hash produced no hash: '$_h3')"
	FAIL=$((FAIL + 1))
elif [ "$_h3" != "$_h1" ]; then
	printf '  %-52s %s\n' "stub_check: --hash sees code between two comments" "ok (green, as required)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "stub_check: --hash sees code between two comments" \
		"FAIL < (a definition hashed the same as no line at all)"
	FAIL=$((FAIL + 1))
fi
# ...and so does the judge of a header that no entry approves. It skipped
# every line above the guards that began with `/*` as part of the 42 header,
# so a prototype after a comment on the same line passed as a stub; the one
# test of "a comment and nothing else" is whole_comment's, which --hash uses
# above. The same prototype on a line of its own was already red.
printf '%s\n/* x */ void\tft_selftest_f(void);\n/**/ int\tft_selftest_g(char *s);\n\n#ifndef SC_CMT_H\n# define SC_CMT_H\n\n#endif\n' \
	"$SC_H" > "$WORK/sc/cmt_proto.h"
want_red   "stub_check: a .h with code after a leading comment fails" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/cmt_proto.h"

# THE DEPTH A LINE IS JUDGED AT. Braces used to be counted after the line was
# scored, so everything sharing a line with its own opening brace was scored at
# depth 0 -- outside every function body, where anything is allowed. A whole
# working function written on one line was reported as a stub.
printf 'int\tft_double(int n) { return (n * 2); }\n' > "$WORK/sc/oneline.c"
printf 'int\tft_f(void)\n{\tint i;\n\treturn (0);\n}\n' > "$WORK/sc/braceline.c"
want_red   "stub_check: a whole function on one line is not a stub" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/oneline.c"
want_red   "stub_check: a declaration on the brace line is examined" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/braceline.c"
# ...and the forms a real stub is written in must still pass, on one line too:
# the fix must not turn `{ return (0); }` into a finding.
printf '%s\n\nint\tft_f(void) { return (0); }\n\nvoid\tft_g(int n) { (void)n; }\n' "$SC_H" \
	> "$WORK/sc/onelinestub.c"
want_green "stub_check: a one-line stub body still passes" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/onelinestub.c"

# ONE NAME PER LINE (stub_check.sh says so at its lists). They were strings
# walked with `for f in $c_files`, which splits a name at its blanks: a staged
# answer named `ft_x copy.c` -- the name a file manager gives a duplicate --
# was scored as `ft_x` and `copy.c`, two paths the index does not have. The
# refusal for a blob it could not read was made inside $(...), so it ended the
# substitution and not the run, and awk, handed an empty name, read stdin: OK,
# exit 0, over an answer that would have shipped (found rehearsing a template
# publish, 2026-10-03), and a verdict that changed with whatever was piped in. --file
# split the same way, said `awk: cannot open` and then OK. Every arm below was
# red on that code. The repo-mode runs take stdin from /dev/null, so that a
# hand run against a checker that reads it fails here rather than hangs.
mkdir -p "$WORK/sc/blank"
cp "$WORK/sc/answer.c" "$WORK/sc/blank/ft_x copy.c"
cp "$WORK/sc/stub.c" "$WORK/sc/blank/ft_stub copy.c"
want_red   "stub_check: --file reads a name with a blank whole" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/blank/ft_x copy.c"
want_green "stub_check: ...and passes a stub of that name" -- \
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/sc/blank/ft_stub copy.c"
sc_repo() { env BUILD_WORKSPACE_DIRECTORY="$1" "$SH" "$TOOLS/stub_check.sh" < /dev/null; }
# The text of an answer on stdin, over a tree of stubs: the old run scored it
# as the content of `ft_x`, one half of `ft_x (1).c`, and reported it.
sc_piped() {
	printf 'int\tft_selftest_one(void)\n{\n\treturn (1);\n}\n' |
		env BUILD_WORKSPACE_DIRECTORY="$1" "$SH" "$TOOLS/stub_check.sh"
}
mkdir -p "$WORK/screpo3/c-piscine/c-piscine-c-99/deliverable/ex00"
(
	cd "$WORK/screpo3" || exit 1
	git init -q .
	git config user.email selftest@example.invalid
	git config user.name selftest
	cp "$WORK/sc/stub.c" c-piscine/c-piscine-c-99/deliverable/ex00/ft_x.c
	cp "$WORK/sc/stub.c" "c-piscine/c-piscine-c-99/deliverable/ex00/ft_x (1).c"
	git add -A && git commit -q -m stubs
) > /dev/null 2>&1
want_green "stub_check: what is piped in is never scored" -- sc_piped "$WORK/screpo3"
( cd "$WORK/screpo3" && cp "$WORK/sc/answer.c" "c-piscine/c-piscine-c-99/deliverable/ex00/ft_x copy.c" &&
	git add -A && git commit -q -m answer ) > /dev/null 2>&1
want_red   "stub_check: a staged answer named with a blank is caught" -- sc_repo "$WORK/screpo3"
want_out   "stub_check: ...under its whole name" \
	"c-piscine-c-99/deliverable/ex00/ft_x copy.c" -- sc_repo "$WORK/screpo3"
# A name git quotes in a listing -- a byte above 0x7f, here an e with an acute
# accent -- is a name too: listed quoted, it was a path `git show :` could not
# find, and an unread file of no known kind.
( cd "$WORK/screpo3" && git rm -q "c-piscine/c-piscine-c-99/deliverable/ex00/ft_x copy.c" &&
	cp "$WORK/sc/stub.c" "c-piscine/c-piscine-c-99/deliverable/ex00/ft_$(printf '\303\251').c" &&
	git add -A && git commit -q -m accent ) > /dev/null 2>&1
want_green "stub_check: a name git would quote is read as it is" -- sc_repo "$WORK/screpo3"
# And a blob the index cannot give -- a path a merge left in conflict, at
# stages 1 and 2 and not at 0 -- is refused, and the refusal ends the run with
# 2: it was printed, then the file was scored as empty and the run said OK.
(
	cd "$WORK/screpo3" || exit 1
	_scb=$(git hash-object -w "$WORK/sc/stub.c")
	_scf=c-piscine/c-piscine-c-99/deliverable/ex00/ft_x.c
	printf '0 0000000000000000000000000000000000000000\t%s\n' "$_scf" | git update-index --index-info
	printf '100644 %s 1\t%s\n100644 %s 2\t%s\n' "$_scb" "$_scf" "$_scb" "$_scf" |
		git update-index --index-info
) > /dev/null 2>&1
want_broken "stub_check: a blob the index cannot give ends the run" \
	"Refusing to score it, and so the whole run" -- sc_repo "$WORK/screpo3"
# ...with git's reason, which went to /dev/null: the refusal named the file
# and not what git found wrong with it.
want_broken "stub_check: ...and says git's reason" \
	"not at stage 0" -- sc_repo "$WORK/screpo3"
# A bare name shaped like an awk assignment -- `ft_a=b.c`, relative, in the
# directory the run starts from -- was taken by awk for one: awk then read its
# standard input, /dev/null, and an answer under that name was "OK -- all 1
# deliverable(s) are stubs", its --hash the empty file's. Each judge, and the
# hash, now reads its file by redirection.
mkdir -p "$WORK/sc/assign"
cp "$WORK/sc/answer.c" "$WORK/sc/assign/ft_a=b.c"
cp "$WORK/sc/h3.h" "$WORK/sc/assign/ft_a=b.h"
SC_ABS="$(cd "$TOOLS" && pwd)/stub_check.sh"
sc_here() { ( cd "$WORK/sc/assign" && "$SH" "$SC_ABS" "$@" ); }
want_red   "stub_check: --file reads a name shaped like an awk assignment" -- \
	sc_here --file ft_a=b.c
# The hash of that name is its content's: h3.h's, a 32-character md5, never
# the empty input's.
sc_hash_same() {
	_sca=$(sc_here --hash ft_a=b.h | cut -d' ' -f1)
	_scb=$("$SH" "$SC_ABS" --hash "$WORK/sc/h3.h" | cut -d' ' -f1)
	[ ${#_sca} -eq 32 ] && [ "$_sca" = "$_scb" ]
}
want_green "stub_check: --hash of such a name is its content's" -- sc_hash_same

