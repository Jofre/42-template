# ------------------------------------------------------------- student_build
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The one builder every program made from a student's files goes through
# (tools/student_build.bzl hands it the toolchain's own command lines; here it
# gets the plain defaults a hand run gets). Its whole contract is two halves,
# and each half has arms: whatever the student's files hold, the build ACTION
# succeeds -- a failed one takes every target that needs it down as FAILED TO
# BUILD, with no log -- and what it produced refuses to pretend it is a
# program, saying why in the compiler's own words.
SB="$TOOLS/student_build.sh"
mkdir -p "$WORK/sb"
printf 'int\ttoy(int n);\n' > "$WORK/sb/toy.h"
printf '#include "toy.h"\n\nint\ttoy(int n)\n{\n\treturn (n * 2);\n}\n' > "$WORK/sb/toy.c"
printf '#include <stdio.h>\n#include "toy.h"\n\nint\tmain(void)\n{\n\tprintf("%%d\\n", toy(21));\n\treturn (0);\n}\n' \
	> "$WORK/sb/harness.c"
printf 'int\ttoy(int n)\n{\n\treturn (n * 2)\n}\n' > "$WORK/sb/syntax.c"
printf 'int\ttoy(int n)\n{\n\treturn (n * 2);\n}\n\nint\tmain(void)\n{\n\treturn (0);\n}\n' \
	> "$WORK/sb/stray_main.c"
printf 'int\tnever_called(void)\n{\n\treturn (0);\n}\n\nint\tmain(void)\n{\n\treturn (1);\n}\n' \
	> "$WORK/sb/extra.c"
sb() { "$SH" "$SB" --cc "$CC" --label selftest "$@"; }
# run_sb OUT: the program it wrote, run, both streams. A stand-in exits the
# reserved 86 by design, which want_out would read as a broken harness; here it
# is the red the arm expects, so it comes back as 1.
run_sb() {
	"$1" 2>&1
	_sb_r=$?
	[ "$_sb_r" -eq 86 ] && return 1
	return "$_sb_r"
}

want_green "student_build: a function and its harness build" -- \
	sb --out "$WORK/sb/ok" --harness "$WORK/sb/harness.c" --src "$WORK/sb/toy.c"
want_out "student_build: ...into a program that runs" '42' -- run_sb "$WORK/sb/ok"
# A file beside the function that nothing calls is ARCHIVED, as a cc_library's
# objects were, so the linker never takes it -- even with a main() in it. The
# files layer is what reports a file the subject did not ask for.
want_green "student_build: an extra file nothing calls changes nothing" -- \
	sb --out "$WORK/sb/extra" --harness "$WORK/sb/harness.c" \
		--src "$WORK/sb/toy.c" --src "$WORK/sb/extra.c"
want_out "student_build: ...its program still runs" '42' -- run_sb "$WORK/sb/extra"

want_green "student_build: a syntax error still builds SOMETHING" -- \
	sb --out "$WORK/sb/syntax" --harness "$WORK/sb/harness.c" --src "$WORK/sb/syntax.c"
want_out "student_build: ...a stand-in, in the compiler's words" 'sb/syntax.c:' -- \
	run_sb "$WORK/sb/syntax"
want_out "student_build: ...that says it does not compile" 'it does not compile' -- \
	run_sb "$WORK/sb/syntax"
# The stand-in's status is the reserved one, never 0 and never a crash: 86.
"$WORK/sb/syntax" > /dev/null 2>&1
_sb_rc=$?
if [ "$_sb_rc" -eq 86 ]; then
	printf '  %-52s %s\n' "student_build: ...and exits the reserved status" "ok (86)"
	PASS=$((PASS + 1))
else
	printf '  %-52s %s\n' "student_build: ...and exits the reserved status" "FAIL < (exit $_sb_rc)"
	FAIL=$((FAIL + 1))
fi

want_green "student_build: a main() beside the function still builds" -- \
	sb --out "$WORK/sb/stray" --harness "$WORK/sb/harness.c" --src "$WORK/sb/stray_main.c"
want_out "student_build: ...a stand-in that does not link" 'does not link' -- \
	run_sb "$WORK/sb/stray"
want_out "student_build: ...naming the second main" 'multiple definition' -- \
	run_sb "$WORK/sb/stray"

want_green "student_build: nothing turned in still builds" -- \
	sb --out "$WORK/sb/none" --harness "$WORK/sb/harness.c" --dir "$WORK/sb/nowhere"
want_out "student_build: ...a stand-in naming where it looked" 'sb/nowhere' -- \
	run_sb "$WORK/sb/none"

# The Makefile mode, for the modules whose subject mandates a Makefile and then
# leaves the filenames to the team. Its reason to exist is the case the first
# arm sets up: a directory holding TWO entry points, only one of which the
# Makefile compiles. A glob links both and dies on a duplicate main -- so the
# green arm is the proof that asking make gives a different, correct answer.
mkdir -p "$WORK/mksrc" "$WORK/mknone" "$WORK/mkgone"
printf 'int helper(void);\nint helper(void) { return (0); }\n' > "$WORK/mksrc/a.c"
printf 'int helper(void);\nint main(void) { return (helper()); }\n' > "$WORK/mksrc/main_a.c"
printf 'int main(void) { return (1); }\n' > "$WORK/mksrc/main_b.c"
printf 'all:\n\tcc a.c main_a.c -o prog\n' > "$WORK/mksrc/Makefile"
printf 'int main(void) { return (0); }\n' > "$WORK/mknone/main.c"
printf 'all:\n\t@:\n' > "$WORK/mknone/Makefile"
want_green "student_build: it builds what MAKE compiles, not what globs" -- \
	sb --makefile "$WORK/mksrc/Makefile" --out "$WORK/mksrc_out" --no-archive
want_green "student_build: ...and that program is real" -- "$WORK/mksrc_out"
# A goal that compiles nothing leaves the source list empty, and an empty list
# is one careless `$CC $SRCS -o out` away from a program that does nothing -- a
# false green in the shape this whole file exists to hunt.
want_green "student_build: a goal that compiles nothing still builds" -- \
	sb --makefile "$WORK/mknone/Makefile" --out "$WORK/mknone_stub" --no-archive
want_red "student_build: ...and what it produced is not a working program" -- \
	run_sb "$WORK/mknone_stub"
want_out "student_build: ...it explains itself when RUN" 'compiles no .c files' -- \
	run_sb "$WORK/mknone_stub"
want_out "student_build: ...and shows what make said it would run" \
	'This is what it said it would run' -- run_sb "$WORK/mknone_stub"
want_green "student_build: no Makefile at all still builds" -- \
	sb --makefile "$WORK/mkgone/Makefile" --out "$WORK/mkgone_stub" --no-archive
want_out "student_build: ...a stand-in saying there is no Makefile" \
	'there is no Makefile at' -- run_sb "$WORK/mkgone_stub"
# Its words name what the program is built for by its kind (--kind, from the
# contract's units), and "exercise" where nothing names one.
want_out "student_build: ...a stand-in saying what its Makefile builds" \
	"This exercise's programs are built from what its Makefile compiles" -- \
	run_sb "$WORK/mkgone_stub"
# sb_lib: the no-Makefile stand-in, built with --kind library, then run. A
# build that fails is the harness's fault here, so it comes back as 2.
sb_lib() {
	sb --makefile "$WORK/mkgone/Makefile" --out "$WORK/mkgone_lib" \
		--no-archive --kind library > /dev/null 2>&1 || return 2
	run_sb "$WORK/mkgone_lib"
}
want_out "student_build: ...a library's stand-in names the library" \
	"This library's programs are built from what its Makefile compiles" -- sb_lib
want_broken "student_build: a --kind no contract has is refused" \
	'student_build.sh: --kind is exercise, library, function, project or part' -- \
	sb --makefile "$WORK/mkgone/Makefile" --out "$WORK/mkgone_lesson" --no-archive --kind lesson
# ...and so is an empty one: a --kind given names a kind, and an empty word is
# none (student_build.bzl passes --kind only with a kind).
want_broken "student_build: ...and so is an empty --kind" \
	"student_build.sh: --kind is exercise, library, function, project or part, not ''" -- \
	sb --makefile "$WORK/mkgone/Makefile" --out "$WORK/mkgone_nokind" --no-archive --kind ""
# A Makefile with no target at all -- comments alone, as C 11 ex05's stub is --
# is make's "No targets.  Stop.": nothing written yet, the same fact as a goal
# that compiles nothing, never "could not work out what to build" (broke).
mkdir -p "$WORK/mkbare"
printf 'int main(void) { return (0); }
' > "$WORK/mkbare/main.c"
printf '# a stub: no target yet
' > "$WORK/mkbare/Makefile"
sb --makefile "$WORK/mkbare/Makefile" --out "$WORK/mkbare_stub" --no-archive > /dev/null 2>&1
want_out "student_build: a Makefile with no target is nothing written yet" \
	'compiles no .c files' -- run_sb "$WORK/mkbare_stub"
want_broken_none "student_build: ...never a Makefile that is broken" \
	'could not work out' -- run_sb "$WORK/mkbare_stub"
# UNTIL THE MAKEFILE IS WRITTEN (--fallback-src): no Makefile, a stub goal or
# no target builds the sources given, and a Makefile that compiles anything
# decides alone -- mksrc's builds a.c and main_a.c, and main_b.c, handed as a
# fallback with its own main, is never linked.
want_green "student_build: a stub goal builds the fallback sources" -- \
	sb --makefile "$WORK/mknone/Makefile" --fallback-src "$WORK/mknone/main.c" \
		--out "$WORK/mknone_fb" --no-archive
want_green "student_build: ...into a real program" -- "$WORK/mknone_fb"
sb --makefile "$WORK/mkbare/Makefile" --fallback-src "$WORK/mkbare/main.c" \
	--out "$WORK/mkbare_fb" --no-archive > /dev/null 2>&1
want_green "student_build: ...so does a Makefile with no target" -- "$WORK/mkbare_fb"
sb --makefile "$WORK/mkgone/Makefile" --fallback-src "$WORK/mknone/main.c" \
	--out "$WORK/mkgone_fb" --no-archive > /dev/null 2>&1
want_green "student_build: ...and no Makefile at all" -- "$WORK/mkgone_fb"
sb --makefile "$WORK/mksrc/Makefile" --fallback-src "$WORK/mksrc/main_b.c" \
	--out "$WORK/mksrc_fb" --no-archive > /dev/null 2>&1
want_green "student_build: a written Makefile decides, not the fallback" -- "$WORK/mksrc_fb"
want_broken "student_build: a fallback with no Makefile mode refuses" \
	'there is no --makefile' -- \
	sb --fallback-src "$WORK/mknone/main.c" --out "$WORK/nofb" --no-archive

# The maintainer's check that every TEST program still compiles: under
# STUDENT_BUILD_STRICT=1 a harness file that does not compile fails the build
# action, as it did when these were cc_binary targets -- or a harness bug on a
# level no sweep reaches would be a stand-in nobody reads. A student's own file
# is a stand-in in both modes.
#
# Without it, a broken harness file that READS a header of the student's is a
# stand-in: a header that does not declare what the subject says fails there
# first. One that reads nothing of theirs cannot have been broken by them, so
# it fails the build in both modes (exit 2): a stand-in there would blame
# them for the test's own bug, and Bazel would cache it.
printf '#include "toy.h"\n\nint\tmain(void)\n{\n\treturn (toy(21)\n}\n' > "$WORK/sb/harness_broken.c"
printf 'int\tmain(void)\n{\n\treturn (21\n}\n' > "$WORK/sb/harness_own.c"
want_red "student_build: STRICT fails the build on a broken harness" -- \
	env STUDENT_BUILD_STRICT=1 "$SH" "$SB" --cc "$CC" --out "$WORK/sb/hb" \
		--harness "$WORK/sb/harness_broken.c" --src "$WORK/sb/toy.c"
want_green "student_build: ...without it, one that reads their header stands in" -- \
	env -u STUDENT_BUILD_STRICT "$SH" "$SB" --cc "$CC" --out "$WORK/sb/hb2" \
		--harness "$WORK/sb/harness_broken.c" --src "$WORK/sb/toy.c"
want_out "student_build: ...a stand-in, for the header it read" 'harness_broken.c' -- \
	run_sb "$WORK/sb/hb2"
want_broken "student_build: a broken harness reading nothing of theirs fails" \
	'no file of' -- \
	env -u STUDENT_BUILD_STRICT "$SH" "$SB" --cc "$CC" --out "$WORK/sb/hb4" \
		--harness "$WORK/sb/harness_own.c" --src "$WORK/sb/toy.c"
want_green "student_build: STRICT still stands in for YOUR broken file" -- \
	env STUDENT_BUILD_STRICT=1 "$SH" "$SB" --cc "$CC" --out "$WORK/sb/hb3" \
		--harness "$WORK/sb/harness.c" --src "$WORK/sb/syntax.c"

# A compiler that is KILLED or crashes said nothing about the code: exit 2,
# which Bazel does not cache, never a stand-in, which it would -- correct code
# reported as "did not build" until something else changed. Measured before
# this: a compiler that SIGKILLs itself left build rc 0 and a stand-in saying
# "Killed ... It failed in: harness.c toy.c".
printf '#!/bin/sh\nkill -9 $$\n' > "$WORK/sb/killed_cc"
chmod +x "$WORK/sb/killed_cc"
want_broken "student_build: a KILLED compiler fails the build, no stand-in" \
	'did not answer' -- \
	"$SH" "$SB" --cc "$WORK/sb/killed_cc" --out "$WORK/sb/killed" \
		--harness "$WORK/sb/harness.c" --src "$WORK/sb/toy.c"
printf '#!/bin/sh\necho "clang-12: error: clang frontend command failed due to signal (use -v to see invocation)" >&2\nexit 1\n' \
	> "$WORK/sb/crashed_cc"
chmod +x "$WORK/sb/crashed_cc"
want_broken "student_build: a compiler whose frontend crashed does too" \
	'did not answer' -- \
	"$SH" "$SB" --cc "$WORK/sb/crashed_cc" --out "$WORK/sb/crashed" \
		--harness "$WORK/sb/harness.c" --src "$WORK/sb/toy.c"
# ...in colour too, as the toolchain's -fcolor-diagnostics prints it, and in
# gcc's form: an internal compiler error on a file, exit 4.
cat > "$WORK/sb/crashed_colour_cc" <<'SB_EOF'
#!/bin/sh
printf '\033[1mclang-12: \033[0m\033[0;1;31merror: \033[0m\033[1mclang frontend command failed due to signal (use -v to see invocation)\033[0m\n' >&2
exit 1
SB_EOF
cat > "$WORK/sb/ice_cc" <<'SB_EOF'
#!/bin/sh
echo "toy.c: In function 'toy':" >&2
echo "toy.c:3:1: internal compiler error: Segmentation fault" >&2
echo "Please submit a full bug report," >&2
exit 4
SB_EOF
chmod +x "$WORK/sb/crashed_colour_cc" "$WORK/sb/ice_cc"
want_broken "student_build: ...a crash banner in colour does too" \
	'did not answer' -- \
	"$SH" "$SB" --cc "$WORK/sb/crashed_colour_cc" --out "$WORK/sb/crashed2" \
		--harness "$WORK/sb/harness.c" --src "$WORK/sb/toy.c"
want_broken "student_build: ...and gcc's internal compiler error" \
	'did not answer' -- \
	"$SH" "$SB" --cc "$WORK/sb/ice_cc" --out "$WORK/sb/crashed3" \
		--harness "$WORK/sb/harness.c" --src "$WORK/sb/toy.c"
# ...but ONLY a line the driver printed. The compiler quotes the student's
# broken line under its error, clang-12 from column 0, and that line may hold
# the same words: it is broken code, a stand-in like any other. Matched as a
# substring, it was a "crash", exit 2, a target FAILED TO BUILD with no log.
# So is a Makefile's recipe: make -Bn prints it, and it may say anything.
printf 'int toy(int n) { const char *s = "internal compiler error"; return n * 2 }\n' \
	> "$WORK/sb/ice_string.c"
printf 'int\ttoy(int n)\n{\n\treturn (n * 2);\n}\nPLEASE submit a bug report\n' \
	> "$WORK/sb/ice_line.c"
mkdir -p "$WORK/mkice"
printf 'all:\n\t@echo "internal compiler error"\n\tPLEASE submit a bug report\n' > "$WORK/mkice/Makefile"
want_green "student_build: a quoted line saying 'internal compiler error'..." -- \
	sb --out "$WORK/sb/ice1" --harness "$WORK/sb/harness.c" --src "$WORK/sb/ice_string.c"
want_out "student_build: ...is broken code, not a crash" 'it does not compile' -- \
	run_sb "$WORK/sb/ice1"
want_green "student_build: a quoted line at column 0 saying 'PLEASE submit'..." -- \
	sb --out "$WORK/sb/ice2" --harness "$WORK/sb/harness.c" --src "$WORK/sb/ice_line.c"
want_out "student_build: ...is broken code too" 'it does not compile' -- \
	run_sb "$WORK/sb/ice2"
# ...nor a MESSAGE that is the student's own words. An #error, or a failed
# _Static_assert, makes the compiler print them as its diagnostic, with no
# caret line under them: "ice_msg.c:1:2: error: clang frontend command failed
# due to signal". A driver's banner starts with the driver's name, never with
# a place in a file, and one that did was a "crash", exit 2, no log.
printf '#error clang frontend command failed due to signal\nint\ttoy(int n)\n{\n\treturn (n * 2);\n}\n' \
	> "$WORK/sb/ice_msg.c"
want_green "student_build: an #error in a crash banner's words..." -- \
	sb --out "$WORK/sb/ice3" --harness "$WORK/sb/harness.c" --src "$WORK/sb/ice_msg.c"
want_out "student_build: ...is the student's message, not a crash" 'it does not compile' -- \
	run_sb "$WORK/sb/ice3"
want_green "student_build: a recipe that prints a crash banner..." -- \
	sb --makefile "$WORK/mkice/Makefile" --out "$WORK/mkice_out" --no-archive
want_out "student_build: ...is a recipe, not a crash of make" 'compiles no .c files' -- \
	run_sb "$WORK/mkice_out"

# A file NAME with a blank or a parenthesis is one file. The lists here were
# split on blanks, so "toy copy.c" became "toy" and "copy.c", and correct code
# was a stand-in saying "no such file or directory: copy.c".
cp "$WORK/sb/toy.c" "$WORK/sb/toy copy.c"
cp "$WORK/sb/toy.c" "$WORK/sb/toy (1).c"
want_green "student_build: a source named with a blank builds" -- \
	sb --out "$WORK/sb/blank" --harness "$WORK/sb/harness.c" --src "$WORK/sb/toy copy.c"
want_out "student_build: ...into the real program" '42' -- run_sb "$WORK/sb/blank"
want_green "student_build: a source named with a ( builds, unarchived" -- \
	sb --out "$WORK/sb/paren" --no-archive --harness "$WORK/sb/harness.c" --src "$WORK/sb/toy (1).c"
want_out "student_build: ...into the real program" '42' -- run_sb "$WORK/sb/paren"

# A Makefile that only echoes -- the stub of an exercise nobody has started --
# has NOTHING to build, which is not broken code: the stand-in says so, and
# says what kind it is, for first_red and every runner to read.
want_out "student_build: a goal compiling nothing is an EMPTY stand-in" \
	'NOTHING TO BUILD YET' -- run_sb "$WORK/mknone_stub"
want_broken_none "student_build: ...never 'your code did not build'" \
	'YOUR CODE DID NOT BUILD' -- run_sb "$WORK/mknone_stub"
want_out "student_build: ...and its kind is on its third line" '# kind: empty' -- \
	head -n 3 "$WORK/mknone_stub"
want_out "student_build: a syntax error's stand-in is of kind broke" '# kind: broke' -- \
	head -n 3 "$WORK/sb/syntax"
# A recipe's `cc *.c` is the .c files of the MAKEFILE's directory, as the
# shell running the recipe would expand it -- never this script's.
mkdir -p "$WORK/mkglob"
printf 'int\thelp(void);\nint\thelp(void)\n{\n\treturn (0);\n}\n' > "$WORK/mkglob/help.c"
printf 'int\thelp(void);\nint\tmain(void)\n{\n\treturn (help());\n}\n' > "$WORK/mkglob/main.c"
printf 'all:\n\tcc -Wall *.c -o prog\n' > "$WORK/mkglob/Makefile"
want_green "student_build: a recipe's *.c is the Makefile's directory" -- \
	sb --makefile "$WORK/mkglob/Makefile" --out "$WORK/mkglob_out" --no-archive
want_green "student_build: ...and that program is real" -- "$WORK/mkglob_out"

# Sources in srcs/, the header in includes/, and a recipe that says -I: the
# Common Core's layout, and one BSQ and Rush 02 allow. The compile uses our
# flags, so the include path is taken from the recipe as well as the file
# list, or the first #include "..." fails (finding 172). Only -I: a -W or -O
# of theirs would change what every layer measures. The recipes only echo --
# `make -Bn` reads the compile line they print, and nothing is run.
mkdir -p "$WORK/mkinc/srcs" "$WORK/mkinc/includes" "$WORK/mkinc2/srcs" "$WORK/mkinc2/includes" \
	"$WORK/mkout/srcs" "$WORK/mkgone2/srcs"
printf 'int\thelp(void);\n' > "$WORK/mkinc/includes/help.h"
printf '#include "help.h"\n\nint\thelp(void)\n{\n\treturn (0);\n}\n' > "$WORK/mkinc/srcs/help.c"
printf '#include "help.h"\n\nint\tmain(void)\n{\n\treturn (help());\n}\n' > "$WORK/mkinc/srcs/main.c"
printf 'all:\n\t@echo cc -Wall -I includes -o prog srcs/main.c srcs/help.c\n' > "$WORK/mkinc/Makefile"
want_green "student_build: a recipe's -I DIR reaches the compile" -- \
	sb --makefile "$WORK/mkinc/Makefile" --out "$WORK/mkinc_out" --no-archive
want_green "student_build: ...and that program is real" -- "$WORK/mkinc_out"
cp "$WORK/mkinc/includes/help.h" "$WORK/mkinc2/includes/"
cp "$WORK/mkinc/srcs/help.c" "$WORK/mkinc/srcs/main.c" "$WORK/mkinc2/srcs/"
printf 'all:\n\t@echo cc -I./includes/ -o prog srcs/main.c srcs/help.c -O2 -Wno-all\n' > "$WORK/mkinc2/Makefile"
want_green "student_build: so does -I./DIR/, written together" -- \
	sb --makefile "$WORK/mkinc2/Makefile" --out "$WORK/mkinc2_out" --no-archive
want_green "student_build: ...into a real program" -- "$WORK/mkinc2_out"
# A directory outside the turn-in is not the student's, so it is left out --
# and said so, when the compile then fails for want of it.
cp "$WORK/mkinc/srcs/help.c" "$WORK/mkinc/srcs/main.c" "$WORK/mkout/srcs/"
printf 'all:\n\t@echo cc -I ../mkinc/includes -o prog srcs/main.c srcs/help.c\n' > "$WORK/mkout/Makefile"
want_green "student_build: a -I outside the turn-in still builds SOMETHING" -- \
	sb --makefile "$WORK/mkout/Makefile" --out "$WORK/mkout_out" --no-archive
want_red "student_build: ...not a program built with it" -- run_sb "$WORK/mkout_out"
want_out "student_build: ...a stand-in saying it was left out" 'outside the turn-in' -- \
	run_sb "$WORK/mkout_out"
# A source the recipe names that is not in the turn-in: make itself stops
# there, so the program is not built from the files that are left -- which
# used to link, or not, in a way that named neither the Makefile nor the file.
cp "$WORK/mkinc/srcs/main.c" "$WORK/mkgone2/srcs/"
printf 'int\thelp(void);\n\nint\thelp(void)\n{\n\treturn (0);\n}\n' > "$WORK/mkgone2/srcs/extra.c"
printf 'all:\n\t@echo cc -o prog srcs/main.c srcs/extra.c srcs/gone.c\n' > "$WORK/mkgone2/Makefile"
cp "$WORK/mkinc/includes/help.h" "$WORK/mkgone2/srcs/"
want_green "student_build: a recipe naming a missing source still builds" -- \
	sb --makefile "$WORK/mkgone2/Makefile" --out "$WORK/mkgone2_out" --no-archive
want_red "student_build: ...not a program from the files that are there" -- \
	run_sb "$WORK/mkgone2_out"
want_out "student_build: ...a stand-in naming the missing file" 'srcs/gone.c' -- \
	run_sb "$WORK/mkgone2_out"
want_out "student_build: ...as a source not in the turn-in" 'not in the turn-in' -- \
	run_sb "$WORK/mkgone2_out"
want_out "student_build: ...and of kind broke, not an exercise not started" '# kind: broke' -- \
	head -n 3 "$WORK/mkgone2_out"

# A SUB-MAKE: the top Makefile builds a library first, `$(MAKE) -C libft`,
# the shape of nearly every Common Core project after libft. That sub-make's
# recipes run in libft/, so their paths -- a .c, an -I -- are relative to
# libft/. Read from the top Makefile's directory, libft's sources were "not
# in the turn-in" and the program a stand-in blaming a correct project. The
# recipes only echo; `make -Bn` runs the $(MAKE) line, as make does under -n.
mkdir -p "$WORK/mksub/libft" "$WORK/mksub/srcs" "$WORK/mksub/includes"
printf 'int\thelp(void);\n' > "$WORK/mksub/includes/help.h"
printf '#include "help.h"\n\nint\thelp(void)\n{\n\treturn (0);\n}\n' > "$WORK/mksub/libft/help.c"
printf '#include "help.h"\n\nint\tmain(void)\n{\n\treturn (help());\n}\n' > "$WORK/mksub/srcs/main.c"
printf 'all:\n\t@echo cc -Wall -I ../includes -c help.c -o help.o\n\t@echo ar rcs libft.a help.o\n' \
	> "$WORK/mksub/libft/Makefile"
printf 'all:\n\t$(MAKE) -C libft\n\t@echo cc -Wall -Iincludes -o prog srcs/main.c -Llibft -lft\n' \
	> "$WORK/mksub/Makefile"
want_green "student_build: a sub-make's sources are read from its directory" -- \
	sb --makefile "$WORK/mksub/Makefile" --out "$WORK/mksub_out" --no-archive \
		--includes-out "$WORK/mksub_inc"
want_green "student_build: ...into a real program" -- "$WORK/mksub_out"
want_out "student_build: ...and its -I ../includes is the top's includes/" \
	"$WORK/mksub/includes" -- cat "$WORK/mksub_inc"
# Many Makefiles quiet their sub-makes with --no-print-directory, the very
# line a sub-make's directory is read from. The build asks make to print it
# anyway (a MAKEFLAGS given on make's command line wins over the Makefile's).
cp -R "$WORK/mksub" "$WORK/mksubq"
{ printf 'MAKEFLAGS += --no-print-directory\n'; cat "$WORK/mksub/Makefile"; } > "$WORK/mksubq/Makefile"
{ printf 'MAKEFLAGS += --no-print-directory\n'; cat "$WORK/mksub/libft/Makefile"; } > "$WORK/mksubq/libft/Makefile"
want_green "student_build: ...even under --no-print-directory" -- \
	sb --makefile "$WORK/mksubq/Makefile" --out "$WORK/mksubq_out" --no-archive
want_green "student_build: ...into a real program" -- "$WORK/mksubq_out"
# A source a sub-make names that is really missing is still one, named from
# the top Makefile's directory.
cp -R "$WORK/mksub" "$WORK/mksubgone"
rm "$WORK/mksubgone/libft/help.c"
want_green "student_build: a sub-make naming a missing source still builds" -- \
	sb --makefile "$WORK/mksubgone/Makefile" --out "$WORK/mksubgone_out" --no-archive
want_out "student_build: ...a stand-in naming it from the top" 'libft/help.c' -- \
	run_sb "$WORK/mksubgone_out"
# The -I list is written whichever way the build ends: a declared output the
# action did not write would fail the build.
want_green "student_build: no Makefile still writes the -I list, empty" -- \
	sb --makefile "$WORK/mksub/no-such/Makefile" --out "$WORK/mknomk_out" --no-archive \
		--includes-out "$WORK/mknomk_inc"
want_green "student_build: ...there, and empty" -- test -f "$WORK/mknomk_inc" -a ! -s "$WORK/mknomk_inc"

# The .c list (--sources-out), for the files layer: every .c the recipes
# compile, as a path from the Makefile's directory, a sub-make's included --
# and never one it does not name. "unknown" where make could not plan the
# build (no Makefile), empty where it compiles nothing (a stub): the files
# layer judges no .c then (finding 164).
printf 'int\tunused(void)\n{\n\treturn (0);\n}\n' > "$WORK/mksub/srcs/unused.c"
want_green "student_build: the .c list names what the recipes compile" -- \
	sb --makefile "$WORK/mksub/Makefile" --out "$WORK/mksub_out2" --no-archive \
		--sources-out "$WORK/mksub_srcs"
want_out "student_build: ...a sub-make's, from the top" 'libft/help.c' -- cat "$WORK/mksub_srcs"
want_out "student_build: ...and the top's own" 'srcs/main.c' -- cat "$WORK/mksub_srcs"
want_broken_none "student_build: ...and never a .c no recipe names" 'unused.c' -- cat "$WORK/mksub_srcs"
rm -f "$WORK/mksub/srcs/unused.c"
want_green "student_build: no Makefile writes the .c list as unknown" -- \
	sb --makefile "$WORK/mksub/no-such/Makefile" --out "$WORK/mknomk_out2" --no-archive \
		--sources-out "$WORK/mknomk_srcs"
want_out "student_build: ...there, saying unknown" 'unknown' -- cat "$WORK/mknomk_srcs"
want_green "student_build: a stub that compiles nothing writes it empty" -- \
	sb --makefile "$WORK/mkice/Makefile" --out "$WORK/mkice_out2" --no-archive \
		--sources-out "$WORK/mkice_srcs"
want_green "student_build: ...there, and empty" -- test -f "$WORK/mkice_srcs" -a ! -s "$WORK/mkice_srcs"
# The planning make's words are read in English too: a make that speaks
# French (xlmake, in make_test's section) under a locale that is not C.
mkdir -p "$WORK/mkcomm"
printf '# nothing written yet\n' > "$WORK/mkcomm/Makefile"
if st_mine; then
	xlmake "$WORK/sbxlplan"
	for _d in mksub mkcomm; do
		env LANGUAGE=fr LC_ALL=fr_FR.UTF-8 "$SH" "$SB" --cc "$CC" --label selftest \
			--make "$WORK/sbxlplan/make" --makefile "$WORK/$_d/Makefile" --out "$WORK/${_d}_xl" \
			--no-archive --sources-out "$WORK/${_d}_xl_srcs" > /dev/null 2>&1
	done
fi
want_green "student_build: a sub-make's build, planned under a make that speaks French" -- \
	run_sb "$WORK/mksub_xl"
want_out "student_build: ...names its sources from the top" 'libft/help.c' -- cat "$WORK/mksub_xl_srcs"
want_green "student_build: a Makefile of comments alone, there, is nothing written yet" -- \
	test -f "$WORK/mkcomm_xl_srcs" -a ! -s "$WORK/mkcomm_xl_srcs"
want_broken_none "student_build: ...never a Makefile make could not plan" \
	'could not work out what to build' -- run_sb "$WORK/mkcomm_xl"

# The one failure that is NOT the student's: the harness cannot build at all.
# That must fail the action, loudly (exit 2), never write a stand-in that
# blames the student for the machine.
want_broken "student_build: no compiler is the harness's failure, not yours" \
	'not found' -- \
	"$SH" "$SB" --cc "$WORK/sb/no-such-cc" --out "$WORK/sb/nocc" --src "$WORK/sb/toy.c"
want_broken "student_build: a flag it does not know stops the run" \
	'unknown option' -- sb --out "$WORK/sb/x" --frobnicate

# A PART BUILT BY A RULE OF ITS OWN (--make-goal G). The program is what
# `make G` builds, never what a bare `make` builds; and a Makefile with no
# rule G is nothing written yet, read from make's own list of its rules --
# never a folder or a file named G, or a G.c a built-in rule compiles, each
# of which lets `make G` answer without a rule of the student's. Every tree
# holds two invented programs, each printing its own name.
for _d in mkgoal mkgoal_var mkgoal_dir mkgoal_src mkgoal_warn mkgoal_phony mkgoal_echo mkgoal_syn; do
	mkdir -p "$WORK/$_d"
	printf '#include <unistd.h>\nint main(void) { write(1, "sorter\\n", 7); return (0); }\n' \
		> "$WORK/$_d/sort_main.c"
	printf '#include <unistd.h>\nint main(void) { write(1, "checker\\n", 8); return (0); }\n' \
		> "$WORK/$_d/check_main.c"
done
printf 'all: sorter\nsorter:\n\tcc sort_main.c -o sorter\nbonus: checker\nchecker:\n\tcc check_main.c -o checker\n.PHONY: all bonus\n' \
	> "$WORK/mkgoal/Makefile"
printf 'B = bonus\nall:\n\tcc sort_main.c -o sorter\n$(B):\n\tcc check_main.c -o checker\n' \
	> "$WORK/mkgoal_var/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\n' > "$WORK/mkgoal_dir/Makefile"
mkdir -p "$WORK/mkgoal_dir/bonus"
printf 'all:\n\tcc sort_main.c -o sorter\n' > "$WORK/mkgoal_src/Makefile"
printf '#include <unistd.h>\nint main(void) { write(1, "builtin\\n", 8); return (0); }\n' \
	> "$WORK/mkgoal_src/bonus.c"
# The same, under a Makefile make warns about as it reads it (a recipe
# given twice): a warning is no reason to stop reading its rules.
printf 'all:\n\tcc sort_main.c -o sorter\nall:\n\tcc sort_main.c -o sorter\n' > "$WORK/mkgoal_warn/Makefile"
cp "$WORK/mkgoal_src/bonus.c" "$WORK/mkgoal_warn/bonus.c"
printf 'all:\n\tcc sort_main.c -o sorter\n.PHONY: all bonus\n' > "$WORK/mkgoal_phony/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\nbonus:\n\t@echo bonus\n' > "$WORK/mkgoal_echo/Makefile"
printf 'all:\n  cc sort_main.c\nbonus:\n\tcc check_main.c\n' > "$WORK/mkgoal_syn/Makefile"
want_green "student_build: --make-goal builds what that rule compiles" -- \
	sb --makefile "$WORK/mkgoal/Makefile" --make-goal bonus --out "$WORK/mkgoal_out" --no-archive
want_out "student_build: ...the program 'make bonus' builds" 'checker' -- run_sb "$WORK/mkgoal_out"
want_broken_none "student_build: ...never the one a bare make builds" 'sorter' -- \
	run_sb "$WORK/mkgoal_out"
sb --makefile "$WORK/mkgoal_var/Makefile" --make-goal bonus --out "$WORK/mkgoal_var_out" \
	--no-archive > /dev/null 2>&1
want_out "student_build: ...a rule named through a variable counts" 'checker' -- \
	run_sb "$WORK/mkgoal_var_out"
sb --makefile "$WORK/mkgoal_dir/Makefile" --make-goal bonus --out "$WORK/mkgoal_dir_out" \
	--no-archive > /dev/null 2>&1
want_red "student_build: a folder named bonus is no bonus rule" -- run_sb "$WORK/mkgoal_dir_out"
want_out "student_build: ...it says the Makefile has no such rule" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_dir_out"
want_out "student_build: ...as nothing written yet" 'NOTHING TO BUILD YET' -- \
	run_sb "$WORK/mkgoal_dir_out"
sb --makefile "$WORK/mkgoal_src/Makefile" --make-goal bonus --out "$WORK/mkgoal_src_out" \
	--no-archive > /dev/null 2>&1
want_out "student_build: a bonus.c make compiles alone is no rule" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_src_out"
want_broken_none "student_build: ...and nothing built-in stands in" 'builtin' -- \
	run_sb "$WORK/mkgoal_src_out"
sb --makefile "$WORK/mkgoal_warn/Makefile" --make-goal bonus --out "$WORK/mkgoal_warn_out" \
	--no-archive > /dev/null 2>&1
want_out "student_build: ...nor under a Makefile make warns about" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_warn_out"
want_broken_none "student_build: ...where nothing built-in stands in either" 'builtin' -- \
	run_sb "$WORK/mkgoal_warn_out"
sb --makefile "$WORK/mkgoal_phony/Makefile" --make-goal bonus --out "$WORK/mkgoal_phony_out" \
	--no-archive > /dev/null 2>&1
want_out "student_build: a name in .PHONY alone is no rule" \
	'names bonus and gives it no rule' -- run_sb "$WORK/mkgoal_phony_out"
sb --makefile "$WORK/mkgoal_echo/Makefile" --make-goal bonus --out "$WORK/mkgoal_echo_out" \
	--no-archive > /dev/null 2>&1
want_out "student_build: a rule that only echoes compiles nothing" \
	"'make bonus' compiles no .c files" -- run_sb "$WORK/mkgoal_echo_out"
sb --makefile "$WORK/mkgoal_syn/Makefile" --make-goal bonus --out "$WORK/mkgoal_syn_out" \
	--no-archive > /dev/null 2>&1
want_out "student_build: a Makefile make cannot read is broken" \
	"'make -Bn bonus' could not work out what to build" -- run_sb "$WORK/mkgoal_syn_out"
want_broken "student_build: --make-goal takes a rule's name" 'takes a Makefile rule' -- \
	sb --makefile "$WORK/mkgoal/Makefile" --make-goal -B --out "$WORK/mkgoal_bad" --no-archive
want_broken "student_build: ...an empty one refuses too" 'takes a Makefile rule' -- \
	sb --makefile "$WORK/mkgoal/Makefile" --make-goal '' --out "$WORK/mkgoal_bad" --no-archive
want_broken "student_build: --make-goal with no Makefile mode refuses" \
	'there is no --makefile' -- \
	sb --make-goal bonus --src "$WORK/mkgoal/check_main.c" --out "$WORK/mkgoal_bad" --no-archive
want_broken "student_build: --make-goal and a fallback refuse" 'are exclusive' -- \
	sb --makefile "$WORK/mkgoal/Makefile" --make-goal bonus \
		--fallback-src "$WORK/mkgoal/check_main.c" --out "$WORK/mkgoal_bad" --no-archive

# A source the part's rule names and the turn-in lacks is said to be that
# rule's: the stand-in names the rule `make -Bn bonus` planned, where a bare
# make's names the default goal (the mkgone2 tree above).
mkdir -p "$WORK/mkgoal_gone"
cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/mkgoal_gone/"
printf 'all:\n\tcc sort_main.c -o sorter\nbonus:\n\tcc check_main.c gone.c -o checker\n' \
	> "$WORK/mkgoal_gone/Makefile"
sb --makefile "$WORK/mkgoal_gone/Makefile" --make-goal bonus --out "$WORK/mkgoal_gone_out" \
	--no-archive > /dev/null 2>&1
want_out "student_build: a source the bonus rule names, missing, is that rule's" \
	"'make -Bn bonus' says the bonus rule compiles: gone.c" -- run_sb "$WORK/mkgoal_gone_out"
want_out "student_build: ...and one a bare make names, the default goal's" \
	"'make -Bn' says the default goal compiles: srcs/gone.c" -- run_sb "$WORK/mkgone2_out"

# Make's database is read when make read the whole Makefile, and the LAST
# line it wrote on stderr is one sign of that (the mtgoal_wstars trees, in
# make_test's section, say why). Each tree has a bonus.c a built-in rule
# compiles, and no bonus rule; the last two stop make before the bonus rule
# after them, one with a $(error) worded as make's own complaint, one with a
# $(shell) that writes that complaint before a $(error).
for _d in mkgoal_wstars mkgoal_shstars mkgoal_submk/sub mkgoal_gfilt mkgoal_mimic mkgoal_shmimic; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/mkgoal_src/bonus.c" \
		"$WORK/${_d%/sub}/"
done
printf '$(warning *** careful)\nall:\n\tcc sort_main.c -o sorter\n' > "$WORK/mkgoal_wstars/Makefile"
printf 'X := $(shell echo "lib: *** not built" >&2)\nall:\n\tcc sort_main.c -o sorter\n' \
	> "$WORK/mkgoal_shstars/Makefile"
printf -- '-include gen.mk\nall:\n\tcc sort_main.c -o sorter\ngen.mk:\n\t$(MAKE) -C sub gen.mk\n' \
	> "$WORK/mkgoal_submk/Makefile"
printf 'other:\n\t@:\n' > "$WORK/mkgoal_submk/sub/Makefile"
printf 'ifneq ($(filter-out all clean fclean re bonus,$(MAKECMDGOALS)),)\n$(error unknown goal: $(MAKECMDGOALS))\nendif\nall:\n\tcc sort_main.c -o sorter\n' \
	> "$WORK/mkgoal_gfilt/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\n$(error No rule to make target '\''.DEFAULT'\'')\nbonus:\n\tcc check_main.c -o checker\n' \
	> "$WORK/mkgoal_mimic/Makefile"
printf 'X := $(shell echo "make: *** No rule to make target '\''.DEFAULT'\''.  Stop." >&2)\n$(error stopped here)\nbonus:\n\tcc check_main.c -o checker\n' \
	> "$WORK/mkgoal_shmimic/Makefile"
if st_mine; then
	for _d in mkgoal_wstars mkgoal_shstars mkgoal_submk mkgoal_gfilt mkgoal_mimic mkgoal_shmimic; do
		sb --makefile "$WORK/$_d/Makefile" --make-goal bonus --out "$WORK/${_d}_out" \
			--no-archive > /dev/null 2>&1
	done
	# The stand-in make that speaks French (xlmake, in make_test's section).
	xlmake "$WORK/sbxlmake"
	env LANGUAGE=fr "$SH" "$SB" --cc "$CC" --label selftest --make "$WORK/sbxlmake/make" \
		--makefile "$WORK/mkgoal_src/Makefile" --make-goal bonus --out "$WORK/mkgoal_xl_out" \
		--no-archive > /dev/null 2>&1
fi
for _d in mkgoal_wstars mkgoal_shstars mkgoal_submk mkgoal_gfilt; do
	want_out "student_build: no bonus rule, whatever came before ($_d)" \
		'your Makefile has no bonus rule' -- run_sb "$WORK/${_d}_out"
	want_broken_none "student_build: ...and nothing built-in stands in ($_d)" 'builtin' -- \
		run_sb "$WORK/${_d}_out"
done
want_broken_none "student_build: a \$(error) worded as make's complaint is not it" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_mimic_out"
want_out "student_build: ...it is a Makefile make cannot read" \
	"'make -Bn bonus' could not work out what to build" -- run_sb "$WORK/mkgoal_mimic_out"
want_broken_none "student_build: the complaint is make's only when it is the last line" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_shmimic_out"
want_out "student_build: ...a Makefile make cannot read too" \
	"'make -Bn bonus' could not work out what to build" -- run_sb "$WORK/mkgoal_shmimic_out"
want_out "student_build: no bonus rule, read from a make that speaks French" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_xl_out"
want_broken_none "student_build: ...and none built-in from it either" 'builtin' -- \
	run_sb "$WORK/mkgoal_xl_out"
# Make read the whole Makefile when it read the runner's makefile after it
# (the mtgoal_nlmimic trees, in make_test's section, say why): a $(error)
# that ends in make's complaint is not it; -k and a $(shell) with no newline
# change only how the complaint ends; an include make could not make leaves
# its rules out of the database; and a Makefile that sets MAKECMDGOALS reads
# its own value.
for _d in mkgoal_nlmimic mkgoal_kflag mkgoal_shnonl mkgoal_mcgset mkgoal_kincl; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/mkgoal_src/bonus.c" \
		"$WORK/$_d/"
done
printf 'define NL\n\n\nendef\nall:\n\tcc sort_main.c -o sorter\n$(error x$(NL)make: *** No rule to make target '\''.DEFAULT'\'')\nbonus: checker\nchecker:\n\tcc check_main.c -o checker\n' \
	> "$WORK/mkgoal_nlmimic/Makefile"
printf 'MAKEFLAGS += -k\nall:\n\tcc sort_main.c -o sorter\n' > "$WORK/mkgoal_kflag/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\nX := $(shell printf '\''no newline after this'\'' >&2)\n' \
	> "$WORK/mkgoal_shnonl/Makefile"
printf 'MAKECMDGOALS := all\nifneq ($(MAKECMDGOALS),all)\n$(error only all)\nendif\nall:\n\tcc sort_main.c -o sorter\n' \
	> "$WORK/mkgoal_mcgset/Makefile"
printf 'MAKEFLAGS += -k\ninclude gone.mk\nall:\n\tcc sort_main.c -o sorter\n' \
	> "$WORK/mkgoal_kincl/Makefile"
if st_mine; then
	for _d in mkgoal_nlmimic mkgoal_kflag mkgoal_shnonl mkgoal_mcgset mkgoal_kincl; do
		sb --makefile "$WORK/$_d/Makefile" --make-goal bonus --out "$WORK/${_d}_out" \
			--no-archive > /dev/null 2>&1
	done
	env MAKEFLAGS=k "$SH" "$SB" --cc "$CC" --label selftest --makefile "$WORK/mkgoal_src/Makefile" \
		--make-goal bonus --out "$WORK/mkgoal_kenv_out" --no-archive > /dev/null 2>&1
fi
want_broken_none "student_build: a \$(error) that ends in make's complaint is not it" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_nlmimic_out"
want_out "student_build: ...it is one make stopped reading" \
	"'make -Bn bonus' could not work out what to build" -- run_sb "$WORK/mkgoal_nlmimic_out"
for _d in mkgoal_kflag mkgoal_shnonl mkgoal_mcgset mkgoal_kenv; do
	want_out "student_build: no bonus rule, read to the end ($_d)" \
		'your Makefile has no bonus rule' -- run_sb "$WORK/${_d}_out"
	want_broken_none "student_build: ...and nothing built-in stands in ($_d)" 'builtin' -- \
		run_sb "$WORK/${_d}_out"
done
want_out "student_build: ...nor past an include it could not make" \
	"'make -Bn bonus' could not work out what to build" -- run_sb "$WORK/mkgoal_kincl_out"
# The database make goes on with is the last it prints, after it made a
# makefile it includes and started again (the mtgoal_rxphony trees, in
# make_test's section, say why); and the makefile make failed to remake is one
# its own database marks so, never a sub-make's.
for _d in mkgoal_rxphony mkgoal_rxconf mkgoal_rxmimic mkgoal_shsubk; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/mkgoal_src/bonus.c" \
		"$WORK/$_d/"
done
printf '.PHONY: all bonus\nall:\n\tcc sort_main.c -o sorter\n-include gen.mk\ngen.mk:\n\tprintf '\''bonus:\\n\\tcc check_main.c -o checker\\n'\'' > gen.mk\n' \
	> "$WORK/mkgoal_rxphony/Makefile"
printf -- '-include config.mk\nconfig.mk:\n\tprintf '\''BONUS_NAME := checker\\n'\'' > config.mk\nall:\n\tcc sort_main.c -o sorter\nbonus: $(BONUS_NAME)\nchecker:\n\tcc check_main.c -o checker\n.PHONY: all bonus\n' \
	> "$WORK/mkgoal_rxconf/Makefile"
printf 'define NL\n\n\nendef\nall:\n\tcc sort_main.c -o sorter\n-include gen.mk\ngen.mk:\n\tprintf '\''ok := 1\\n'\'' > gen.mk\nifdef ok\n$(error x$(NL)make: *** No rule to make target '\''.DEFAULT'\'')\nbonus:\n\tcc check_main.c -o checker\nendif\n' \
	> "$WORK/mkgoal_rxmimic/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\nX := $(shell $(MAKE) -k -f nothere.mk > /dev/null)\n' \
	> "$WORK/mkgoal_shsubk/Makefile"
if st_mine; then
	for _d in mkgoal_rxphony mkgoal_rxconf mkgoal_rxmimic mkgoal_shsubk; do
		sb --makefile "$WORK/$_d/Makefile" --make-goal bonus --out "$WORK/${_d}_out" \
			--no-archive > /dev/null 2>&1
	done
fi
for _d in mkgoal_rxphony mkgoal_rxconf; do
	want_out "student_build: the rule make reads once it made what it includes ($_d)" \
		'checker' -- run_sb "$WORK/${_d}_out"
done
want_broken_none "student_build: ...and a second reading that stops is not read to the end" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_rxmimic_out"
want_out "student_build: ...the second reading is one make stopped" \
	"'make -Bn bonus' could not work out what to build" -- run_sb "$WORK/mkgoal_rxmimic_out"
want_out "student_build: no bonus rule, whatever a sub-make failed to remake" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_shsubk_out"
want_broken_none "student_build: ...and nothing built-in stands in for it" 'builtin' -- \
	run_sb "$WORK/mkgoal_shsubk_out"
# The database holds the built-in variables `make bonus` reads, a value only
# as a value, and under -k make's warning after its complaint (the mtgoal_ccvar
# trees, in make_test's section, say why).
for _d in mkgoal_ccvar mkgoal_sfxvar mkgoal_defhdr mkgoal_defnest mkgoal_valhdr mkgoal_valfiles \
	mkgoal_skew mkgoal_extra; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/mkgoal_src/bonus.c" \
		"$WORK/$_d/"
done
printf 'all:\n\tcc sort_main.c -o sorter\nifdef COMPILE.c\nbonus:\n\tcc check_main.c -o checker\nendif\n' \
	> "$WORK/mkgoal_ccvar/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\nifneq ($(SUFFIXES),)\nbonus:\n\tcc check_main.c -o checker\nendif\n' \
	> "$WORK/mkgoal_sfxvar/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\ndefine TPL\n# Files\nbonus: checker\nendef\n' \
	> "$WORK/mkgoal_defhdr/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\ndefine TPL\ndefine IN\nx\nendef\n# Files\nbonus: checker\nendef\n' \
	> "$WORK/mkgoal_defnest/Makefile"
printf 'define TPL\n\n# Files of the bonus\nbonus: checker\nendef\nS := $(TPL)\nall:\n\tcc sort_main.c -o sorter\n' \
	> "$WORK/mkgoal_valhdr/Makefile"
printf 'define TPL\n\n# Files\nbonus: checker\nendef\nS := $(TPL)\nall:\n\tcc sort_main.c -o sorter\n' \
	> "$WORK/mkgoal_valfiles/Makefile"
printf 'MAKEFLAGS += -k\nX := $(shell touch -t 209901010000 future.mk)\n-include future.mk\nall:\n\tcc sort_main.c -o sorter\n' \
	> "$WORK/mkgoal_skew/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\n.EXTRA_PREREQS := stamp\nstamp:\n\ttouch stamp\n' \
	> "$WORK/mkgoal_extra/Makefile"
if st_mine; then
	for _d in mkgoal_ccvar mkgoal_sfxvar mkgoal_defhdr mkgoal_defnest mkgoal_valhdr mkgoal_valfiles \
		mkgoal_skew mkgoal_extra; do
		sb --makefile "$WORK/$_d/Makefile" --make-goal bonus --out "$WORK/${_d}_out" \
			--no-archive > /dev/null 2>&1
	done
fi
want_out "student_build: a rule under a built-in variable is in the database" 'checker' -- \
	run_sb "$WORK/mkgoal_ccvar_out"
want_out "student_build: ...and one under the suffixes make knows by itself" 'checker' -- \
	run_sb "$WORK/mkgoal_sfxvar_out"
for _d in mkgoal_defhdr mkgoal_defnest mkgoal_valhdr mkgoal_valfiles mkgoal_skew; do
	want_out "student_build: no bonus rule, whatever a value holds or make warns ($_d)" \
		'your Makefile has no bonus rule' -- run_sb "$WORK/${_d}_out"
	want_broken_none "student_build: ...and nothing built-in stands in for that ($_d)" 'builtin' -- \
		run_sb "$WORK/${_d}_out"
done
want_out "student_build: no bonus rule, whatever .EXTRA_PREREQS adds to every rule" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_extra_out"
want_broken_none "student_build: ...and nothing built-in stands in for it there" 'builtin' -- \
	run_sb "$WORK/mkgoal_extra_out"
# The database is read as make prints it, block by block, from the runner's
# rule on: a recipe with the lines that continue it, a target's own variable
# up to the target's own line, the rules to their end and no further, and a
# rule under a prefix of the Makefile's, or a :: rule whose first block does
# nothing, is there (the mtgoal_rpfx trees, in make_test's section, say
# why). The Makefile reads the MAKEFLAGS `make bonus` reads; and a space, a
# # or a $ in the path of the scratch folder is no part of the runner's
# makefile's name.
for _d in mkgoal_rpfx mkgoal_dbreset mkgoal_pfxjoin mkgoal_tsvnl mkgoal_vpath mkgoal_pfxrule \
	mkgoal_dcfirst mkgoal_mflags; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/mkgoal_src/bonus.c" \
		"$WORK/$_d/"
done
printf 'all:\n\tcc sort_main.c -o sorter\n.SUFFIXES: .q .z\n.q.z:\n\t@echo \\\n# Files\n\tonus: checker\n.RECIPEPREFIX := b\n' \
	> "$WORK/mkgoal_rpfx/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\nclean:\n\trm -f sorter \\\n# Make data base, printed on a Monday\n' \
	> "$WORK/mkgoal_dbreset/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\n.RECIPEPREFIX := b\njunk:\nbecho \\\n\nbonus: checker\n.RECIPEPREFIX :=\n' \
	> "$WORK/mkgoal_pfxjoin/Makefile"
printf 'define TPL\n\n\nbonus: checker\nendef\nsorter: S := $(TPL)\nall:\n\tcc sort_main.c -o sorter\n' \
	> "$WORK/mkgoal_tsvnl/Makefile"
printf 'define NL\n\n\nendef\nvpath %%.c x$(NL)$(NL)bonus:checker\nall:\n\tcc sort_main.c -o sorter\n' \
	> "$WORK/mkgoal_vpath/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\n.RECIPEPREFIX := >\nbonus:\n>cc check_main.c -o checker\n' \
	> "$WORK/mkgoal_pfxrule/Makefile"
# make looks for a rule to make the first block of a :: rule that has none,
# and a built-in one would compile bonus.c beside check_main.c.
rm -f "$WORK/mkgoal_dcfirst/bonus.c"
printf 'all:\n\tcc sort_main.c -o sorter\nbonus::\nbonus::\n\tcc check_main.c -o checker\n' \
	> "$WORK/mkgoal_dcfirst/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\nifeq ($(findstring q,$(MAKEFLAGS)),)\nbonus:\n\tcc check_main.c -o checker\nendif\n' \
	> "$WORK/mkgoal_mflags/Makefile"
# Includes are remade as under `make bonus`, a sub-make's among them, and a
# Makefile read again after one reads the MAKEFLAGS `make bonus` reads; a
# .RECIPEPREFIX the Makefile sets last, or a value it gives the runner's own
# variable, does not change how the runner's makefile is read (the
# mtgoal_subgen trees, in make_test's section).
for _d in mkgoal_subgen mkgoal_mfrx mkgoal_pfxh mkgoal_pfxo mkgoal_pfxM mkgoal_hrov; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/$_d/"
done
for _d in mkgoal_pfxh mkgoal_pfxo mkgoal_pfxM mkgoal_hrov; do
	cp "$WORK/mkgoal_src/bonus.c" "$WORK/$_d/bonus.c"
	printf 'all:\n\tcc sort_main.c -o sorter\n' > "$WORK/$_d/Makefile"
done
printf 'all:\n\tcc sort_main.c -o sorter\n-include gen.mk\ngen.mk:\n\t$(MAKE) -f gen.make gen.mk\n' \
	> "$WORK/mkgoal_subgen/Makefile"
printf 'gen.mk:\n\tprintf "bonus: checker\\nchecker: check_main.c\\n\\tcc check_main.c -o checker\\n" > gen.mk\n' \
	> "$WORK/mkgoal_subgen/gen.make"
printf 'all:\n\tcc sort_main.c -o sorter\n-include gen.mk\ngen.mk:\n\tprintf "x := 1\\n" > gen.mk\nifeq ($(findstring q,$(MAKEFLAGS)),)\nbonus:\n\tcc check_main.c -o checker\nendif\n' \
	> "$WORK/mkgoal_mfrx/Makefile"
for _c in h o M; do
	printf '.RECIPEPREFIX := %s\n' "$_c" >> "$WORK/mkgoal_pfx$_c/Makefile"
done
printf 'override HARNESS_READ_TO_THE_END := no\n' >> "$WORK/mkgoal_hrov/Makefile"
if st_mine; then
	for _d in mkgoal_rpfx mkgoal_dbreset mkgoal_pfxjoin mkgoal_tsvnl mkgoal_vpath mkgoal_pfxrule \
		mkgoal_dcfirst mkgoal_mflags mkgoal_subgen mkgoal_mfrx mkgoal_pfxh mkgoal_pfxo mkgoal_pfxM \
		mkgoal_hrov; do
		sb --makefile "$WORK/$_d/Makefile" --make-goal bonus --out "$WORK/${_d}_out" \
			--no-archive > /dev/null 2>&1
	done
	for _c in ' ' '#' '$'; do
		mkdir -p "$WORK/sbtmp/tmp${_c}dir"
		env TMPDIR="$WORK/sbtmp/tmp${_c}dir" "$SH" "$SB" --cc "$CC" --label selftest \
			--makefile "$WORK/mkgoal_src/Makefile" --make-goal bonus \
			--out "$WORK/sbtmp/tmp${_c}dir_out" --no-archive > /dev/null 2>&1
	done
fi
for _d in mkgoal_rpfx mkgoal_dbreset mkgoal_pfxjoin mkgoal_tsvnl mkgoal_vpath; do
	want_out "student_build: no bonus rule, however make prints a recipe or a value ($_d)" \
		'your Makefile has no bonus rule' -- run_sb "$WORK/${_d}_out"
	want_broken_none "student_build: ...and nothing built-in stands in, however it prints ($_d)" \
		'builtin' -- run_sb "$WORK/${_d}_out"
done
for _d in mkgoal_pfxrule mkgoal_dcfirst mkgoal_mflags; do
	want_out "student_build: the bonus rule is there, however make prints it ($_d)" 'checker' -- \
		run_sb "$WORK/${_d}_out"
done
for _d in mkgoal_subgen mkgoal_mfrx; do
	want_out "student_build: the bonus rule is there, however make reads the includes ($_d)" \
		'checker' -- run_sb "$WORK/${_d}_out"
done
for _d in mkgoal_pfxh mkgoal_pfxo mkgoal_pfxM mkgoal_hrov; do
	want_out "student_build: no bonus rule, whatever the Makefile sets last ($_d)" \
		'your Makefile has no bonus rule' -- run_sb "$WORK/${_d}_out"
	want_broken_none "student_build: ...and nothing built-in stands in, whatever it sets ($_d)" \
		'builtin' -- run_sb "$WORK/${_d}_out"
done
# A database a sub-make left in an include while make read its own is not
# read: the tree is put back, its includes are made by a make asked for no
# database, and make is read again, so that the bonus rule that database had
# is not taken for the Makefile's, nor a built-in one built in its place
# (mkgoal_cfgnob). A prerequisite of .DEFAULT make has no rule for ends the
# reading in make's own words too (mkgoal_defpre, mkgoal_defpok; the
# mtgoal_cfgnob trees, in make_test's section).
for _d in mkgoal_cfgnob mkgoal_defpre mkgoal_defpok; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/mkgoal_src/bonus.c" \
		"$WORK/$_d/"
done
printf '#include <unistd.h>\nint main(void) { write(1, "leaked\\n", 7); return (0); }\n' \
	> "$WORK/mkgoal_cfgnob/leak_main.c"
printf 'all:\n\tcc sort_main.c -o sorter\ninclude config.mk\nconfig.mk:\n\t$(MAKE) -s --no-print-directory -f tools.make config > $@\n' \
	> "$WORK/mkgoal_cfgnob/Makefile"
printf 'config:\n\t@echo "X = 1"\nbonus:\n\tcc leak_main.c -o checker\n' > "$WORK/mkgoal_cfgnob/tools.make"
printf '.DEFAULT: nothere\nall:\n\tcc sort_main.c -o sorter\n' > "$WORK/mkgoal_defpre/Makefile"
printf 'MAKEFLAGS += -k\n.DEFAULT: | nothere\nall:\n\tcc sort_main.c -o sorter\n' \
	> "$WORK/mkgoal_defpok/Makefile"
if st_mine; then
	for _d in mkgoal_cfgnob mkgoal_defpre mkgoal_defpok; do
		sb --makefile "$WORK/$_d/Makefile" --make-goal bonus --out "$WORK/${_d}_out" \
			--no-archive > /dev/null 2>&1
	done
fi
want_out "student_build: no bonus rule where a sub-make's database had one (mkgoal_cfgnob)" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_cfgnob_out"
want_broken_none "student_build: ...and the rule that database had is not built (mkgoal_cfgnob)" \
	'leaked' -- run_sb "$WORK/mkgoal_cfgnob_out"
for _d in mkgoal_cfgnob mkgoal_defpre mkgoal_defpok; do
	want_broken_none "student_build: ...and nothing built-in stands in ($_d)" 'builtin' -- \
		run_sb "$WORK/${_d}_out"
done
for _d in mkgoal_defpre mkgoal_defpok; do
	want_out "student_build: no bonus rule, whatever .DEFAULT needs ($_d)" \
		'your Makefile has no bonus rule' -- run_sb "$WORK/${_d}_out"
done
# An include made each time make reads the Makefile would leave a database
# in the second reading too, so that reading takes the files the first one
# made as up to date: no bonus rule, and none built in its place
# (mkgoal_force).
# A second reading that leaves one all the same (here in an include a file
# the makes before it left has it remake) stops the build, which says why
# (mkgoal_forcelate; the mtgoal_force trees, in make_test's section).
for _d in mkgoal_force mkgoal_forcelate; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/mkgoal_src/bonus.c" \
		"$WORK/$_d/"
	printf 'all:\n\t@#nothing\n' > "$WORK/$_d/gen.mk"
done
printf 'all:\n\tcc sort_main.c -o sorter\n-include config.mk\nconfig.mk: $(if $(MAKE_RESTARTS),,FORCE)\n\t@$(MAKE) --no-print-directory -s -f gen.mk > $@\nFORCE:\n' \
	> "$WORK/mkgoal_force/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\n-include a.mk b.mk\na.mk:\n\t@$(MAKE) --no-print-directory -s -f gen.mk > $@\n\t@grep -q "data base" $@ || : > stamp\nb.mk: $(if $(wildcard stamp),$(if $(MAKE_RESTARTS),,FORCE))\n\t@$(MAKE) --no-print-directory -s -f gen.mk > $@\nFORCE:\n' \
	> "$WORK/mkgoal_forcelate/Makefile"
: > "$WORK/mkgoal_forcelate/b.mk"
if st_mine; then
	sb --makefile "$WORK/mkgoal_force/Makefile" --make-goal bonus --out "$WORK/mkgoal_force_out" \
		--no-archive > /dev/null 2>&1
fi
want_out "student_build: no bonus rule, whatever an include made each time holds (mkgoal_force)" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_force_out"
want_broken_none "student_build: ...and nothing built-in stands in for it (mkgoal_force)" \
	'builtin' -- run_sb "$WORK/mkgoal_force_out"
want_broken "student_build: a database each reading leaves stops it (mkgoal_forcelate)" \
	'each time make reads it' -- \
	sb --makefile "$WORK/mkgoal_forcelate/Makefile" --make-goal bonus \
		--out "$WORK/mkgoal_forcelate_out" --no-archive
# No make a recipe runs is given the goal the readings set in MAKECMDGOALS,
# as none is under `make all`, so the include the second reading reads, and
# the one the dry run's reading remakes, are those `make all` and the dry
# run make: the rule all is the same under both, and is built
# (mkgoal_goalsforce). And the second reading remakes no file the first one
# made, by the path from the tree or by $(CURDIR)'s (mkgoal_absforce; the
# mtgoal_goalsforce and mtgoal_absforce trees, in make_test's section).
for _d in mkgoal_goalsforce mkgoal_absforce; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/mkgoal_src/bonus.c" \
		"$WORK/$_d/"
done
printf 'all:\n\tcc sort_main.c -o sorter\n-include config.mk\nconfig.mk: $(if $(MAKE_RESTARTS),,FORCE)\n\t@$(MAKE) --no-print-directory -s -f gen.mk > $@\nFORCE:\n' \
	> "$WORK/mkgoal_goalsforce/Makefile"
printf 'all:\nifeq ($(MAKECMDGOALS),)\n\t@printf "bonus:\\n\\tcc check_main.c -o checker\\n"\nelse\n\t@echo "X = 1"\nendif\n' \
	> "$WORK/mkgoal_goalsforce/gen.mk"
printf 'all:\n\tcc sort_main.c -o sorter\nbonus:\n\tcc check_main.c -o checker\ninclude $(CURDIR)/config.mk\n$(CURDIR)/config.mk: $(if $(MAKE_RESTARTS),,FORCE)\n\t@$(MAKE) --no-print-directory -s -f gen.mk > $@\nFORCE:\n' \
	> "$WORK/mkgoal_absforce/Makefile"
printf 'all:\n\t@#nothing\n' > "$WORK/mkgoal_absforce/gen.mk"
if st_mine; then
	sb --makefile "$WORK/mkgoal_goalsforce/Makefile" --make-goal all \
		--out "$WORK/mkgoal_goalsforce_out" --no-archive > /dev/null 2>&1
	sb --makefile "$WORK/mkgoal_absforce/Makefile" --make-goal bonus \
		--out "$WORK/mkgoal_absforce_out" --no-archive > /dev/null 2>&1
fi
want_out "student_build: the rule all, as make all makes the include (mkgoal_goalsforce)" \
	'sorter' -- run_sb "$WORK/mkgoal_goalsforce_out"
want_out "student_build: the bonus rule, whatever path names the include (mkgoal_absforce)" \
	'checker' -- run_sb "$WORK/mkgoal_absforce_out"
# A line that starts a database, in a value make prints among the variables,
# changes nothing of how the database after it is read, and a database not
# laid out as make lays one out stops the build, which says why (the
# mtgoal_hdrval trees, in make_test's section).
for _d in mkgoal_hdrval mkgoal_fanch; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/mkgoal_src/bonus.c" \
		"$WORK/$_d/"
done
printf 'all:\n\tcc sort_main.c -o sorter\ndefine TPL\n\n# Make data base, printed on x\nendef\nsorter: S := $(TPL)\n' \
	> "$WORK/mkgoal_hdrval/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\ndefine NL\n\n\nendef\nX := $(NL)harness-anchor-$(notdir $(patsubst %%/make,%%,$(CURDIR)))%%:$(NL)\n' \
	> "$WORK/mkgoal_fanch/Makefile"
if st_mine; then
	sb --makefile "$WORK/mkgoal_hdrval/Makefile" --make-goal bonus --out "$WORK/mkgoal_hdrval_out" \
		--no-archive > /dev/null 2>&1
fi
want_out "student_build: no bonus rule, whatever a value holds before the rules (mkgoal_hdrval)" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_hdrval_out"
want_broken_none "student_build: ...and nothing built-in stands in, whatever it holds (mkgoal_hdrval)" \
	'builtin' -- run_sb "$WORK/mkgoal_hdrval_out"
want_broken "student_build: a database not laid out as make lays one out stops it (mkgoal_fanch)" \
	'is not laid out as make lays one out' -- \
	sb --makefile "$WORK/mkgoal_fanch/Makefile" --make-goal bonus --out "$WORK/mkgoal_fanch_out" \
		--no-archive
# ...the database of the dry run the build is planned with too, read after
# the first one was trusted: a Makefile whose value mimics the run's own rule
# only when MAKEFLAGS holds the B that run sets (mkgoal_fanchb).
mkdir -p "$WORK/mkgoal_fanchb"
cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/mkgoal_src/bonus.c" \
	"$WORK/mkgoal_fanchb/"
printf 'all:\n\tcc sort_main.c -o sorter\nbonus:\n\tcc check_main.c -o checker\ndefine NL\n\n\nendef\nifneq (,$(findstring B,$(firstword $(MAKEFLAGS))))\nX := $(NL)harness-anchor-$(notdir $(patsubst %%/make,%%,$(CURDIR)))%%:$(NL)\nendif\n' \
	> "$WORK/mkgoal_fanchb/Makefile"
want_broken "student_build: ...and so does the dry run's, read second (mkgoal_fanchb)" \
	'is not laid out as make lays one out' -- \
	sb --makefile "$WORK/mkgoal_fanchb/Makefile" --make-goal bonus --out "$WORK/mkgoal_fanchb_out" \
		--no-archive
# A rule that is there only when make is not asked for a dry run is one the
# dry run this runner plans with cannot see, and a built-in rule would build
# bonus.c in its place: the build stops and says why (mkgoal_mfn), as it does
# for a rule that is another under the dry run, which would be planned in
# place of the one `make bonus` runs (mkgoal_mfboth). One there only under a
# dry run is not there (mkgoal_mfnot). The reading made as the dry run reads
# the Makefile asks for no -p in MAKEFLAGS, where a MAKEFLAGS the Makefile
# sets with override would pass it on to the sub-make that remakes an
# include: that sub-make runs as under the dry run, so a Makefile with such
# an include reads there as the dry run reads it. A bonus rule the dry run
# cannot see stops the build then too (mkgoal_mfleak), and one it sees is
# built, whichever goal is asked for (mkgoal_ovsub). And a dry run that
# leaves make's database in a file of the tree says nothing this runner can
# read of how the dry run reads the Makefile, so the build stops then too:
# here a sub-make the Makefile asks for a database under a dry run
# (mkgoal_pleak).
for _d in mkgoal_mfn mkgoal_mfnot mkgoal_mfboth mkgoal_mfleak mkgoal_ovsub mkgoal_pleak; do
	mkdir -p "$WORK/$_d"
	cp "$WORK/mkgoal/sort_main.c" "$WORK/mkgoal/check_main.c" "$WORK/mkgoal_src/bonus.c" \
		"$WORK/$_d/"
done
printf 'override MAKEFLAGS += -s\n-include config.mk\nall:\n\tcc sort_main.c -o sorter\nconfig.mk:\n\t$(MAKE) --no-print-directory -f gen.mk > $@\nifeq ($(findstring n,$(MAKEFLAGS)),)\nbonus:\n\tcc check_main.c -o checker\nendif\n' \
	> "$WORK/mkgoal_mfleak/Makefile"
printf 'override MAKEFLAGS += -s\n-include config.mk\nall:\n\tcc sort_main.c -o sorter\nconfig.mk:\n\t$(MAKE) --no-print-directory -f gen.mk > $@\nbonus:\n\tcc check_main.c -o checker\n' \
	> "$WORK/mkgoal_ovsub/Makefile"
printf -- '-include config.mk\nall:\n\tcc sort_main.c -o sorter\nconfig.mk:\n\t$(MAKE) --no-print-directory -s -f gen.mk $(if $(findstring n,$(MAKEFLAGS)),-p) > $@\nbonus:\n\tcc check_main.c -o checker\n' \
	> "$WORK/mkgoal_pleak/Makefile"
for _d in mkgoal_mfleak mkgoal_ovsub mkgoal_pleak; do
	printf 'all:\n\t@#nothing\n' > "$WORK/$_d/gen.mk"
done
printf 'all:\n\tcc sort_main.c -o sorter\nifeq ($(findstring n,$(MAKEFLAGS)),)\nbonus:\n\tcc check_main.c -o checker\nendif\n' \
	> "$WORK/mkgoal_mfn/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\nifneq ($(findstring n,$(MAKEFLAGS)),)\nbonus:\n\tcc check_main.c -o checker\nendif\n' \
	> "$WORK/mkgoal_mfnot/Makefile"
printf 'all:\n\tcc sort_main.c -o sorter\nifeq ($(MAKEFLAGS),)\nbonus:\n\tcc check_main.c -o checker\nelse\nbonus:\n\tcc sort_main.c -o checker\nendif\n' \
	> "$WORK/mkgoal_mfboth/Makefile"
want_broken "student_build: a bonus rule that is another under its dry run stops it (mkgoal_mfboth)" \
	'the dry run' -- \
	sb --makefile "$WORK/mkgoal_mfboth/Makefile" --make-goal bonus --out "$WORK/mkgoal_mfboth_out" \
		--no-archive
if st_mine; then
	sb --makefile "$WORK/mkgoal_mfnot/Makefile" --make-goal bonus --out "$WORK/mkgoal_mfnot_out" \
		--no-archive > /dev/null 2>&1
fi
want_broken "student_build: a bonus rule its dry run cannot see stops it (mkgoal_mfn)" \
	'the dry run' -- \
	sb --makefile "$WORK/mkgoal_mfn/Makefile" --make-goal bonus --out "$WORK/mkgoal_mfn_out" \
		--no-archive
want_broken "student_build: ...and so does one behind an include a sub-make remakes (mkgoal_mfleak)" \
	'reads none, or another' -- \
	sb --makefile "$WORK/mkgoal_mfleak/Makefile" --make-goal bonus \
		--out "$WORK/mkgoal_mfleak_out" --no-archive
if st_mine; then
	for _g in bonus all; do
		sb --makefile "$WORK/mkgoal_ovsub/Makefile" --make-goal "$_g" \
			--out "$WORK/mkgoal_ovsub_${_g}_out" --no-archive > /dev/null 2>&1
	done
fi
want_out "student_build: a bonus rule the dry run sees behind such an include (mkgoal_ovsub)" \
	'checker' -- run_sb "$WORK/mkgoal_ovsub_bonus_out"
want_out "student_build: ...and the rule all (mkgoal_ovsub)" \
	'sorter' -- run_sb "$WORK/mkgoal_ovsub_all_out"
want_broken "student_build: ...and a dry run that leaves a database stops it (mkgoal_pleak)" \
	"leaves make's database in a file of the tree" -- \
	sb --makefile "$WORK/mkgoal_pleak/Makefile" --make-goal bonus \
		--out "$WORK/mkgoal_pleak_out" --no-archive
want_out "student_build: no bonus rule, whatever a dry run would read (mkgoal_mfnot)" \
	'your Makefile has no bonus rule' -- run_sb "$WORK/mkgoal_mfnot_out"
want_broken_none "student_build: ...and nothing built-in stands in for it (mkgoal_mfnot)" \
	'builtin' -- run_sb "$WORK/mkgoal_mfnot_out"
for _c in ' ' '#' '$'; do
	want_out "student_build: no bonus rule, under a TMPDIR that holds a '$_c'" \
		'your Makefile has no bonus rule' -- run_sb "$WORK/sbtmp/tmp${_c}dir_out"
	want_broken_none "student_build: ...and nothing built-in stands in under it ('$_c')" 'builtin' -- \
		run_sb "$WORK/sbtmp/tmp${_c}dir_out"
done

# The archive's members are named for the objects' paths, and two paths
# that differ only in where a / or an _ falls are two members: a/b_c.o and
# a_b/c.o were one, the second written over the first, and the linker said
# the first file's function was defined nowhere.
mkdir -p "$WORK/sbcol/a" "$WORK/sbcol/a_b"
printf 'int\tsel_f1(void)\n{\n\treturn (1);\n}\n' > "$WORK/sbcol/a/b_c.c"
printf 'int\tsel_f2(void)\n{\n\treturn (2);\n}\n' > "$WORK/sbcol/a_b/c.c"
printf '#include <stdio.h>\n\nint\tsel_f1(void);\nint\tsel_f2(void);\n\nint\tmain(void)\n{\n\tprintf("sel %%d\\n", sel_f1() + sel_f2());\n\treturn (0);\n}\n' \
	> "$WORK/sbcol/harness.c"
want_green "student_build: a/b_c.c and a_b/c.c are two members of the archive" -- \
	sb --out "$WORK/sbcol/out" --harness "$WORK/sbcol/harness.c" \
		--src "$WORK/sbcol/a/b_c.c" --src "$WORK/sbcol/a_b/c.c"
want_out "student_build: ...and the program links both" 'sel 3' -- run_sb "$WORK/sbcol/out"
# A path with a # or an & in it -- the scratch folder's, under such a
# TMPDIR, or the program's own -- is a path to sed too: the archive line
# failed (exit 2), an & in --out linked to a file named @OUT@, and a
# stand-in showed the scratch path half stripped.
printf 'int\tmain(void)\n{\n\treturn (sel_undefined());\n}\n' > "$WORK/sb/undef.c"
for _c in '#' '&'; do
	mkdir -p "$WORK/sbtmp/arc${_c}dir" "$WORK/sb/out${_c}dir"
	want_green "student_build: a TMPDIR that holds a '$_c' builds the archive" -- \
		env TMPDIR="$WORK/sbtmp/arc${_c}dir" "$SH" "$SB" --cc "$CC" --label selftest \
			--out "$WORK/sb/arc${_c}" --harness "$WORK/sb/harness.c" --src "$WORK/sb/toy.c"
	want_green "student_build: ...into a program that runs ('$_c')" -- run_sb "$WORK/sb/arc${_c}"
	want_green "student_build: ...and a link error under it builds a stand-in ('$_c')" -- \
		env TMPDIR="$WORK/sbtmp/arc${_c}dir" "$SH" "$SB" --cc "$CC" --label selftest \
			--out "$WORK/sb/undef${_c}" --harness "$WORK/sb/undef.c" --src "$WORK/sb/toy.c" \
			--no-archive
	want_broken_none "student_build: ...naming the object without the scratch path ('$_c')" \
		"${_c}dir/tmp." -- run_sb "$WORK/sb/undef${_c}"
	want_green "student_build: an --out in a folder that holds a '$_c'" -- \
		sb --out "$WORK/sb/out${_c}dir/prog" --harness "$WORK/sb/harness.c" --src "$WORK/sb/toy.c"
	want_green "student_build: ...is the program, not a stand-in ('$_c')" -- \
		run_sb "$WORK/sb/out${_c}dir/prog"
done
# A tree of symlinks, as a sandbox lays out its inputs, is staged as the
# files they point to: make, remaking an include even under -Bn, wrote
# THROUGH the staged link into the file it points to -- the student's own
# -- and the guard against a leaked database compared a file with itself.
# Each arm builds from links into sbln_real/ and asks that file's bytes
# after.
mkdir -p "$WORK/sbln_real" "$WORK/sbln_inc" "$WORK/sbln_db"
printf 'int\tmain(void)\n{\n\treturn (0);\n}\n' > "$WORK/sbln_real/main.c"
printf 'SEL_SRC = main.c\n' > "$WORK/sbln_real/gen.mk"
printf '# nothing\n' > "$WORK/sbln_real/db.mk"
printf 'include gen.mk\nall:\n\tcc $(SEL_SRC) -o sel_prog\ngen.mk:\n\techo "SEL_SRC = main.c # rewritten" > gen.mk\n' \
	> "$WORK/sbln_real/inc.mk"
printf 'include db.mk\nall:\n\tcc main.c -o sel_prog\nbonus:\n\tcc main.c -o sel_bonus\ndb.mk: FORCE\n\tprintf "%%s\\n" "# Make data base, printed on sel" > db.mk\nFORCE:\n' \
	> "$WORK/sbln_real/db_rule.mk"
for _f in main.c gen.mk db.mk; do
	ln -s "$WORK/sbln_real/$_f" "$WORK/sbln_inc/$_f"
	ln -s "$WORK/sbln_real/$_f" "$WORK/sbln_db/$_f"
done
ln -s "$WORK/sbln_real/inc.mk" "$WORK/sbln_inc/Makefile"
ln -s "$WORK/sbln_real/db_rule.mk" "$WORK/sbln_db/Makefile"
cp "$WORK/sbln_real/gen.mk" "$WORK/sbln_real/db.mk" "$WORK/sb/"
# sb_kept FILE ARGS...: student_build ARGS, then whether sbln_real/FILE is
# as it was (its copy in sb/); a build that fails is the harness's fault, 2.
sb_kept() {
	_sk=$1
	shift
	sb "$@" > /dev/null 2>&1 || return 2
	cmp "$WORK/sb/$_sk" "$WORK/sbln_real/$_sk"
}
want_green "student_build: a staged include make remakes is a copy, not the file it links to" -- \
	sb_kept gen.mk --makefile "$WORK/sbln_inc/Makefile" --out "$WORK/sbln_inc_out" --no-archive
want_green "student_build: ...and so is one a database leaks into, under --make-goal" -- \
	sb_kept db.mk --makefile "$WORK/sbln_db/Makefile" --make-goal bonus \
		--out "$WORK/sbln_db_out" --no-archive
# make runs a recipe line that names $(MAKE) even under -n, so a rule that
# calls itself ran a make inside a make without end, and the build action,
# which Bazel bounds by nothing, hung: such a Makefile is stopped, and is
# the student's (a stand-in); a make that only takes too long may be the
# machine's (exit 2). Each arm runs under a bound of its own, so a red one
# cannot hang the selftest.
mkdir -p "$WORK/sbrec" "$WORK/sbslow"
printf 'int\tmain(void)\n{\n\treturn (0);\n}\n' > "$WORK/sbrec/main.c"
cp "$WORK/sbrec/main.c" "$WORK/sbslow/main.c"
printf 'all:\n\t$(MAKE) all\n\tcc main.c -o sel_prog\n' > "$WORK/sbrec/Makefile"
printf 'SEL_X := $(shell sleep 30)\nall:\n\tcc main.c -o sel_prog\n' > "$WORK/sbslow/Makefile"
sb_bound() { timeout -k 5 20 "$SH" "$SB" --cc "$CC" --label selftest "$@"; }
want_green "student_build: a make that runs make inside itself is stopped" -- \
	sb_bound --makefile "$WORK/sbrec/Makefile" --out "$WORK/sbrec_out" --no-archive
want_out "student_build: ...a stand-in saying so" 'make runs make inside itself without end' -- \
	run_sb "$WORK/sbrec_out"
want_green "student_build: ...and under --make-goal, reading make's database" -- \
	sb_bound --makefile "$WORK/sbrec/Makefile" --make-goal all --out "$WORK/sbrec_goal_out" \
		--no-archive
want_out "student_build: ...a stand-in there too" 'make runs make inside itself without end' -- \
	run_sb "$WORK/sbrec_goal_out"
# A sub-make told not to print its directory says no "make[N]:" line at
# any depth: --no-print-directory on the $(MAKE) line beats the w the
# command line hands down, and a Makefile's own MAKEFLAGS += carries it to
# every level. The recursion is still the Makefile's, caught as soon as the
# other. These two stop themselves 60 levels down, held there by a sleep
# longer than their MAKE_TMO, so a guard that misses them ends in that
# limit's exit 2, never in a storm of makes.
mkdir -p "$WORK/sbrec_flag" "$WORK/sbrec_mf"
cp "$WORK/sbrec/main.c" "$WORK/sbrec_flag/main.c"
cp "$WORK/sbrec/main.c" "$WORK/sbrec_mf/main.c"
printf 'all:\n\t$(if $(filter 60,$(MAKELEVEL)),sleep 30,$(MAKE) --no-print-directory all)\n\tcc main.c -o sel_prog\n' \
	> "$WORK/sbrec_flag/Makefile"
printf 'MAKEFLAGS += --no-print-directory\nall:\n\t$(if $(filter 60,$(MAKELEVEL)),sleep 30,$(MAKE) all)\n\tcc main.c -o sel_prog\n' \
	> "$WORK/sbrec_mf/Makefile"
want_green "student_build: ...one whose \$(MAKE) prints no directory too" -- \
	env STUDENT_BUILD_MAKE_TIMEOUT=8 timeout -k 5 20 "$SH" "$SB" --cc "$CC" --label selftest \
		--makefile "$WORK/sbrec_flag/Makefile" --out "$WORK/sbrec_flag_out" --no-archive
want_out "student_build: ...a stand-in saying so" 'make runs make inside itself without end' -- \
	run_sb "$WORK/sbrec_flag_out"
want_green "student_build: ...and one whose MAKEFLAGS says not to print it" -- \
	env STUDENT_BUILD_MAKE_TIMEOUT=8 timeout -k 5 20 "$SH" "$SB" --cc "$CC" --label selftest \
		--makefile "$WORK/sbrec_mf/Makefile" --out "$WORK/sbrec_mf_out" --no-archive
want_out "student_build: ...a stand-in saying so" 'make runs make inside itself without end' -- \
	run_sb "$WORK/sbrec_mf_out"
want_broken "student_build: a make that does not finish in time fails the build" \
	'did not finish within 2s' -- env STUDENT_BUILD_MAKE_TIMEOUT=2 timeout -k 5 20 \
		"$SH" "$SB" --cc "$CC" --label selftest --makefile "$WORK/sbslow/Makefile" \
		--out "$WORK/sbslow_out" --no-archive
# timeout runs make in a process group of its own, which a signal to the
# script, or to the script's group, does not reach: a TERM that Bazel, or a
# Ctrl-C, sends the build must still end its makes, and end it promptly.
# The Makefile's parse waits on nap.sh, whose path, in this run's WORK, is
# how the arm finds what the run left (and kills it, by PID, when red).
mkdir -p "$WORK/sbterm"
cp "$WORK/sbrec/main.c" "$WORK/sbterm/main.c"
printf 'i=0\nwhile [ "$i" -lt 20 ]; do\n\tsleep 1\n\ti=$((i + 1))\ndone\n' > "$WORK/sbterm/nap.sh"
printf 'SEL_X := $(shell sh %s/nap.sh)\nall:\n\tcc main.c -o sel_prog\n' "$WORK/sbterm" \
	> "$WORK/sbterm/Makefile"
# sb_term_left: the PIDs of this run's processes that are still alive.
sb_term_left() {
	ps -A -o pid= -o args= > "$WORK/sbterm.ps" 2> /dev/null
	grep -F "$WORK/sbterm/nap.sh" "$WORK/sbterm.ps" | awk '{ print $1 }'
}
# sb_term_reap: what a red run left, by PID, with KILL: a script that
# ignores TERM passes that on to every child, so the script first (it starts
# no make after this), then any nap.sh still running, which ends the parse
# of the make left behind.
sb_term_reap() {
	kill -KILL "$(cat "$WORK/sbterm.pid" 2> /dev/null)" 2> /dev/null
	_stl=$(sb_term_left)
	# shellcheck disable=SC2086 # one PID a word
	[ -z "$_stl" ] || kill -KILL $_stl 2> /dev/null
}
# sb_term: student_build over that Makefile, sent TERM once nap.sh runs; 0
# when the script and nap.sh are both gone within five seconds of it.
sb_term() {
	rm -f "$WORK/sbterm.pid" "$WORK/sbterm.done"
	(
		env STUDENT_BUILD_MAKE_TIMEOUT=60 "$SH" "$SB" --cc "$CC" --label selftest \
			--makefile "$WORK/sbterm/Makefile" --out "$WORK/sbterm_out" --no-archive &
		echo $! > "$WORK/sbterm.pid"
		wait $!
		: > "$WORK/sbterm.done"
	) > "$WORK/sbterm.said" 2>&1 &
	_stn=0
	until [ -s "$WORK/sbterm.pid" ] && [ -n "$(sb_term_left)" ]; do
		_stn=$((_stn + 1))
		[ "$_stn" -le 100 ] || { echo "nap.sh never started"; sb_term_reap; return 2; }
		sleep 0.1
	done
	kill -TERM "$(cat "$WORK/sbterm.pid")"
	_stn=0
	until [ -f "$WORK/sbterm.done" ] && [ -z "$(sb_term_left)" ]; do
		_stn=$((_stn + 1))
		if [ "$_stn" -gt 50 ]; then
			[ -f "$WORK/sbterm.done" ] || echo "the script was still running 5s after its TERM"
			[ -z "$(sb_term_left)" ] || echo "nap.sh was still running 5s after the TERM"
			sb_term_reap
			_stn=0
			until [ -f "$WORK/sbterm.done" ] || [ "$_stn" -gt 100 ]; do
				_stn=$((_stn + 1))
				sleep 0.1
			done
			return 1
		fi
		sleep 0.1
	done
}
want_green "student_build: a TERM to it ends its makes, and it, at once" -- sb_term
# The same reader, make_db.awk, staged beside this runner: one that fails
# stops it (exit 2), and so does one that is not there. A copy of the
# runner each, its make_db.awk broken on purpose, or gone.
mkdir -p "$WORK/sbdb_mk"
cp "$WORK/sbrec/main.c" "$WORK/sbdb_mk/main.c"
printf 'all:\n\tcc main.c -o sel_prog\n' > "$WORK/sbdb_mk/Makefile"
for _d in sbdb_bad sbdb_none; do
	mkdir -p "$WORK/$_d"
	cp "$SB" "$TOOLS/standin.sh" "$WORK/$_d/"
done
printf 'BEGIN { exit 9 }\n' > "$WORK/sbdb_bad/make_db.awk"
sbdb() {  # sbdb DIR: DIR's copy of student_build.sh, --make-goal all over sbdb_mk
	"$SH" "$WORK/$1/student_build.sh" --cc "$CC" --label selftest \
		--makefile "$WORK/sbdb_mk/Makefile" --make-goal all --out "$WORK/$1_out" --no-archive
}
want_broken "student_build: a make_db.awk that fails stops it" \
	"could not read make's database of" -- sbdb sbdb_bad
want_broken "student_build: ...and so does one not staged" 'make_db.awk is not staged beside it' -- \
	sbdb sbdb_none
