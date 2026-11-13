# --------------------------------------------------------------- compile_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The guard on a FETCHED compiler's libraries, and the only thing standing
# between "the pinned compiler" and "a compiler that reports the pinned version
# while being the box's". clang is a 100 KB driver: point it at a library
# directory that does not exist and the loader falls back to the machine's own
# copies, every compile passes, and nothing in the output differs by a single
# character. So a missing directory must stop the run, not soften it.
mkdir -p "$WORK/cclib"
printf 'int main(void) { return (0); }\n' > "$WORK/cclib/ok.c"
want_broken "compile_check: a compiler library that is not there stops the run" \
	'does not exist' -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" \
		--cc-lib "$WORK/cclib/nowhere/libnope.so" --src "$WORK/cclib/ok.c"
# The other half of the same question. A fetched compiler can start perfectly
# and still be using the BOX's cc1 or resource headers, if something from
# outside (gcc's GCC_EXEC_PREFIX) moved the tree it looks in -- same driver,
# same version banner, different compiler (V297). Both
# compilers print where they will look, so the tree they are looking in is
# checkable; here the answer is deliberately somewhere they will never name.
want_broken "compile_check: a compiler searching someone else's tree stops the run" \
	'not searching its own tree' -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" \
		--cc-under "$WORK/cclib/ok.c" --src "$WORK/cclib/ok.c"
# The assembler. gcc shells out to one; if -B does not land, it silently takes
# the machine's at assembly time and the object is built by a tool nobody
# pinned. `-print-prog-name=as` answers with a path when the compiler found one
# and with the bare word when it did not, so the bare word has to stop the run.
# Pointed at a directory that certainly holds no assembler, with the
# assembler's libraries (--cc-progs-lib) a --cc-progs cannot do without.
want_broken "compile_check: an assembler it did not find stops the run" \
	'did not take the pinned assembler' -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" \
		--cc-progs "$WORK/cclib/ok.c" --cc-progs-lib "$NM_LIB" --src "$WORK/cclib/ok.c"
want_green "compile_check: and without --cc-lib nothing changes" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/cclib/ok.c"
# And the libraries the assembler loads. The pinned `as` is a frontend over
# libbfd and libopcodes, named by bare soname with no RUNPATH, so without
# their directory on the loader's path it takes the box's copies -- the same
# version where the box has binutils 2.38, and no assembler at all where it
# has another, when every compile of the layer failed as "gcc FAIL" on the
# student's file (TO VERIFY V228). The runner asks the loader which copies
# the assembler gcc runs took, and refuses (exit 2) when it cannot tell,
# when they are not the fetched ones, and when that assembler cannot run.
# Each arm takes a branch whatever binutils the box has: no --cc-progs-lib,
# or one whose folder is not there, is refused before anything runs; a copy
# of the fetched libraries, reached through LD_LIBRARY_PATH from outside and
# not through --cc-progs-lib, is a library from somewhere else on every
# machine; and the assembler that cannot start is a stand-in that fails as
# the loader does.
mkdir -p "$WORK/cclib/nolib" "$WORK/cclib/elsewhere" "$WORK/cclib/dead"
cp -L "${NM_LIB%/*}"/lib*.so* "$WORK/cclib/elsewhere/"
cat > "$WORK/cclib/dead/x86_64-linux-gnu-as" <<'DEADAS'
#!/bin/sh
echo "x86_64-linux-gnu-as: error while loading shared libraries: libopcodes-2.99-system.so: cannot open shared object file: No such file or directory" >&2
exit 127
DEADAS
chmod +x "$WORK/cclib/dead/x86_64-linux-gnu-as"
want_green "compile_check: the pinned assembler with its libraries" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$GCC" --cc-progs "$AS" \
		--cc-progs-lib "$NM_LIB" --src "$WORK/cclib/ok.c"
want_broken "compile_check: an assembler with no --cc-progs-lib stops the run" \
	'needs its --cc-progs-lib' -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$GCC" --cc-progs "$AS" \
		--src "$WORK/cclib/ok.c"
want_broken "compile_check: an assembler library that is not there stops the run" \
	"--cc-progs-lib directory '$WORK/cclib/nowhere' does not exist" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$GCC" --cc-progs "$AS" \
		--cc-progs-lib "$WORK/cclib/nowhere/libnope.so" --src "$WORK/cclib/ok.c"
want_broken "compile_check: an assembler loading another libbfd stops the run" \
	'the pinned assembler loaded' -- \
	env LD_LIBRARY_PATH="$WORK/cclib/elsewhere" \
	"$SH" "$TOOLS/compile_check.sh" --cc "$GCC" --cc-progs "$AS" \
		--cc-progs-lib "$WORK/cclib/nolib/none" --src "$WORK/cclib/ok.c"
want_broken "compile_check: an assembler that cannot start stops the run" \
	'the pinned assembler cannot compile a file' -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$GCC" \
		--cc-progs "$WORK/cclib/dead/x86_64-linux-gnu-as" \
		--cc-progs-lib "$NM_LIB" --src "$WORK/cclib/ok.c"
# A refusal, so exit 2 and no FAIL line with the student's file in it: a
# harness fault reported as the file's FAIL sends the student to code that
# is not wrong.
want_broken_without "compile_check: ...and never names the student's file" \
	"FAIL $WORK/cclib/ok.c" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$GCC" \
		--cc-progs "$WORK/cclib/dead/x86_64-linux-gnu-as" \
		--cc-progs-lib "$NM_LIB" --src "$WORK/cclib/ok.c"
# AN LD_DEBUG FROM OUTSIDE (V276). The proof above reads the loader's
# lines from the compile's stderr, and an LD_DEBUG_OUTPUT set from outside
# (--test_env) sent them to files of its own: the proof saw none and refused
# a correct setup. And the -print-prog-name=as answer was read with stderr
# in it, so an LD_DEBUG set from outside put loader lines in the answer and
# the runner said the pinned assembler was not taken. Both are this setup's
# green, whatever the host's environment holds. The loader's lines go to a
# folder of this test's own, not to selftest's outputs (V336).
mkdir -p "$WORK/cclib-out"
want_green "compile_check: an LD_DEBUG_OUTPUT from outside changes nothing" -- \
	env LD_DEBUG_OUTPUT="$WORK/cclib-ld.dbg" \
	"$SH" "$TOOLS/compile_check.sh" --cc "$GCC" --cc-progs "$AS" \
		--cc-progs-lib "$NM_LIB" --src "$WORK/cclib/ok.c"
want_green "compile_check: ...nor an LD_DEBUG from outside" -- \
	env LD_DEBUG=libs TEST_UNDECLARED_OUTPUTS_DIR="$WORK/cclib-out" \
	"$SH" "$TOOLS/compile_check.sh" --cc "$GCC" --cc-progs "$AS" \
		--cc-progs-lib "$NM_LIB" --src "$WORK/cclib/ok.c"

