# ----------------------------------------------------------------- asan_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The false green this whole file cites in its header — asan_check.sh exiting 0
# when clang-12 was missing — and until now the one runner named in that header
# with no regression test of its own. It is NOT the repo's only sanitizer layer:
# asan_run.sh, argv_table.sh --memory-only and rust_diff.sh --crash-only all run
# instrumented code. What only this one does is choose the allocation: it is
# compiled together with a probe that hands the student's function a block
# sized to fit exactly, so one step past the end lands in a sanitizer redzone
# instead of on a harmless neighbouring byte — which is what the whole-program
# layers, running on whatever the program happened to allocate, would let
# through. The difference between the two sources below is a single `<` → `<=`.
printf '#include <stdlib.h>\nvoid ft_probe_fill(char *b, int n);\nint main(void){char *b = malloc(4); ft_probe_fill(b, 4); free(b); return 0;}\n' \
	> "$WORK/probe.c"
printf 'void ft_probe_fill(char *b, int n){int i=0;while(i<n){b[i]=(char)i;i++;}}\n' \
	> "$WORK/fill_ok.c"
printf 'void ft_probe_fill(char *b, int n){int i=0;while(i<=n){b[i]=(char)i;i++;}}\n' \
	> "$WORK/fill_oob.c"
# The pinned clang-12 and ld.bfd, handed over as Bazel hands them (BUILD_PIN):
# the runner takes no compiler from the box any more (TO VERIFY V38), so
# these arms need no probe of what the box can build.
# shellcheck disable=SC2086
want_red "asan_check: a one-byte overflow fails" -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_oob.c"
# shellcheck disable=SC2086
want_green "asan_check: staying inside the block passes" -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_ok.c"
# A library member's source whose header only the Makefile's -I reaches
# (--inc-file, tools/student_build.sh --includes-out), as every build of the
# library has it (V198).
mkdir -p "$WORK/asinc/inc"
printf 'void\tft_probe_fill(char *b, int n);\n' > "$WORK/asinc/inc/toy_fill.h"
printf '#include "toy_fill.h"\nvoid ft_probe_fill(char *b, int n){int i=0;while(i<n){b[i]=(char)i;i++;}}\n' \
	> "$WORK/asinc/fill.c"
printf '%s\n' "$WORK/asinc/inc" > "$WORK/asinc/includes.txt"
# shellcheck disable=SC2086
want_green "asan_check: a header only the Makefile's -I reaches (--inc-file)" -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN --inc-file "$WORK/asinc/includes.txt" \
		--probe "$WORK/probe.c" --src "$WORK/asinc/fill.c"
# A function the GRADER links (--lib: C 12's ft_create_elem, from an
# archive of its own) is linked after the sources, uninstrumented.
toy_cc "$WORK/fill_ok.o" -c "$WORK/fill_ok.c"
# shellcheck disable=SC2086
want_green "asan_check: a function from --lib links in" -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --lib "$WORK/fill_ok.o"
# A run that ends with a status and no report (V70). Every such ending read
# "the function accessed memory out of bounds" above no report at all. The
# probes' own NULL checks cannot be what ended it: under the sanitizer a
# failed malloc stops the run with a report and never returns NULL. So this
# toy ends in main, standing for any status the run ends with.
printf '#include <stdio.h>\nvoid ft_probe_fill(char *b, int n);\nint main(void){puts("probe: no block to hand over"); return 2;}\n' \
	> "$WORK/probe_own.c"
# shellcheck disable=SC2086
want_broken_none "asan_check: a probe's own status is no out-of-bounds access" \
	'accessed memory out of bounds' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe_own.c" --src "$WORK/fill_ok.c"
# shellcheck disable=SC2086
want_out "asan_check: ...it says no sanitizer reported anything" \
	'returned 2, and neither sanitizer reported anything' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe_own.c" --src "$WORK/fill_ok.c"
# shellcheck disable=SC2086
want_out "asan_check: ...and shows what the probe printed" 'probe: no block to hand over' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe_own.c" --src "$WORK/fill_ok.c"
# ...and says what most likely ended it: the code it called, by exit, abort or
# a signal. It used to say the probe ends itself when something it checks goes
# wrong, which the sanitizer rules out.
printf '#include <stdlib.h>\nvoid ft_probe_fill(char *b, int n){(void)b;(void)n;exit(1);}\n' \
	> "$WORK/fill_exit.c"
# shellcheck disable=SC2086
want_out "asan_check: ...a function's exit is said to have ended it" \
	'the code it called most likely ended the run itself' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_exit.c"
# A probe whose own setup fails is the harness's fault, exit 2: Libft's fd
# writers' probes make a scratch file under TEST_TMPDIR, and with nowhere to
# make it they ended with a bare 2, which read as the student's function
# ending the run. Each is the real probe, over a stub that writes nothing.
mkdir -p "$WORK/asfd"
_as_lfd=$(CDPATH='' cd "$TOOLS/.." && pwd)/cursus/Milestone_0/Libft/tests
for _af in putstr putendl; do
	printf 'void\tft_%s_fd(char *s, int fd)\n{\n\t(void)s;\n\t(void)fd;\n}\n' "$_af" \
		> "$WORK/asfd/ft_${_af}_fd.c"
	# shellcheck disable=SC2086
	want_broken "asan_check: ft_${_af}_fd's probe with no scratch folder is refused" \
		'could not make its scratch file' -- \
		env TMPDIR="$WORK/asfd" TEST_TMPDIR=/nonexistent "$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
			--probe "$_as_lfd/ft_${_af}_fd/mem_ft_${_af}_fd.c" \
			--src "$WORK/asfd/ft_${_af}_fd.c"
done
# A probed function that writes without end is stopped at an output budget,
# and said to (asan_run's arm says why); this one writes 12 MB and returns.
# A run stopped from outside -- here the function signals its waiter,
# tools/exit_status -- is no verdict at all: exit 2, never the FAIL that
# blames the code it called.
printf '#include <unistd.h>\nvoid ft_probe_fill(char *b, int n){static char z[65536];int i=0;(void)b;(void)n;while(i<184){if(write(1,z,sizeof z)<0)return;i++;}}\n' \
	> "$WORK/fill_flood.c"
printf '#include <signal.h>\n#include <unistd.h>\nvoid ft_probe_fill(char *b, int n){(void)b;(void)n;kill(getppid(),SIGTERM);sleep(2);}\n' \
	> "$WORK/fill_stopped.c"
# shellcheck disable=SC2086
want_out "asan_check: a probe writing past its output budget is stopped, and said to be" \
	'kept writing past its output budget' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_flood.c"
# shellcheck disable=SC2086
want_broken "asan_check: a probe stopped from outside is no verdict, exit 2" \
	'could not be judged: the program was stopped from outside' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_stopped.c"
# shellcheck disable=SC2086
want_out "asan_check: an overflow still reads as one" 'accessed memory out of bounds' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_oob.c"
# A REPORT OF ANOTHER KIND IS NAMED AS ITS KIND. Every report was headed "the
# function accessed memory out of bounds (or hit UB)", and AddressSanitizer
# also stops on what is no access at all: a request bigger than the allocator
# allows, a block freed twice. Each toy below does one of those and touches
# nothing outside a block; the headline says what the report's own first line
# says, in words, with the report's name for it.
printf '#include <stdlib.h>\nvoid ft_probe_fill(char *b, int n){char *p=malloc((size_t)n << 60);(void)b;free(p);}\n' \
	> "$WORK/fill_huge.c"
printf '#include <stdlib.h>\nvoid ft_probe_fill(char *b, int n){char *p=malloc((size_t)n);(void)b;free(p);free(p);}\n' \
	> "$WORK/fill_twice.c"
# shellcheck disable=SC2086
want_out "asan_check: a request too big to allocate is named as one" \
	'FAIL — the function asked for more memory than can be allocated (allocation-size-too-big)' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_huge.c"
# shellcheck disable=SC2086
want_broken_none "asan_check: ...and not as an access out of bounds" 'out of bounds' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_huge.c"
# NO HINT THAT READS AS ADVICE TO SWITCH THE CHECK OFF. The sanitizer ends
# a too-big request's report with "HINT: if you don't care about these
# errors you may set allocator_may_return_null=1", and a stack overflow's
# with "HINT: this may be a false positive if your program uses some custom
# stack unwind mechanism", and both were shown to the student word for word.
# They are left out of what is shown, as the shadow-memory map is, and kept
# in the whole report. The stack toy steps one past a local array through a
# pointer, which UBSan's bounds check cannot see, so AddressSanitizer reports.
printf 'void ft_probe_fill(char *b, int n){char a[4];char *volatile p=a;p[n]=1;b[0]=p[0];}\n' \
	> "$WORK/fill_stackoob.c"
mkdir -p "$WORK/asanhint"
# shellcheck disable=SC2086
want_broken_none "asan_check: ...and no HINT to switch the check off" 'allocator_may_return_null' -- \
	env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/asanhint" TEST_TARGET=//mod:ex00_asan \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_huge.c"
want_out "asan_check: ...which the whole report keeps" 'allocator_may_return_null' -- \
	cat "$WORK/asanhint/sanitizer-report-full.txt"
# shellcheck disable=SC2086
want_out "asan_check: ...and the log says it was left out" \
	'(the HINT line is left out; the whole report is in bazel-testlogs/mod/ex00_asan/test.outputs/sanitizer-report-full.txt)' -- \
	env TEST_UNDECLARED_OUTPUTS_DIR="$WORK/asanhint" TEST_TARGET=//mod:ex00_asan \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_huge.c"
# shellcheck disable=SC2086
want_broken_none "asan_check: a stack overflow's HINT is left out" 'false positive' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_stackoob.c"
# shellcheck disable=SC2086
want_broken_none "asan_check: ...with the line that continues it" 'are* supported' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_stackoob.c"
# shellcheck disable=SC2086
want_out "asan_check: ...the report around it still shown" 'stack-buffer-overflow on address' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_stackoob.c"
# shellcheck disable=SC2086
want_out "asan_check: ...and the note names both things left out" \
	'(the shadow-memory map and the HINT line are left out' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_stackoob.c"
# A SEGV's "Hint: address points to the zero page." says where the address
# was, not how to quiet the check, and stays.
printf 'void ft_probe_fill(char *b, int n){char *volatile p=(char *)16;(void)b;p[0]=(char)n;}\n' \
	> "$WORK/fill_zeropage.c"
# shellcheck disable=SC2086
want_out "asan_check: ...a SEGV's Hint about the address stays" 'Hint: address points to the zero page' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_zeropage.c"
# shellcheck disable=SC2086
want_out "asan_check: a block freed twice is named as one" \
	'FAIL — the function freed the same block twice (double-free)' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_twice.c"
# shellcheck disable=SC2086
want_broken_none "asan_check: ...not as an access out of bounds" 'out of bounds' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_twice.c"
# The probe's own header comment says how the probe sizes its blocks, which
# is what an access out of bounds is measured against and nothing else is.
printf '/* PROBE-HEADER: four bytes, sized to fit exactly. */\n#include <stdlib.h>\nvoid ft_probe_fill(char *b, int n);\nint main(void){char *b = malloc(4); ft_probe_fill(b, 4); free(b); return 0;}\n' \
	> "$WORK/probe_hdr.c"
# shellcheck disable=SC2086
want_broken_none "asan_check: ...nor headed by the probe's sizing" 'PROBE-HEADER' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe_hdr.c" --probe-src "$WORK/probe_hdr.c" --src "$WORK/fill_twice.c"
# shellcheck disable=SC2086
want_out "asan_check: ...which an overflow is still shown" 'PROBE-HEADER' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe_hdr.c" --probe-src "$WORK/probe_hdr.c" --src "$WORK/fill_oob.c"
# Only that header: a sed range looked for a comment's close from the line
# after its opening, so a header on one line printed the probe's code down to
# the next "*/", and a comment opening a later line printed again.
# shellcheck disable=SC2086
want_broken_none "asan_check: ...without the code below a one-line header" '#include <stdlib.h>' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe_hdr.c" --probe-src "$WORK/probe_hdr.c" --src "$WORK/fill_oob.c"
printf '/* PROBE-HEADER: four bytes,\n * sized to fit exactly. */\n#include <stdlib.h>\n/* LATER-COMMENT: not the header. */\nvoid ft_probe_fill(char *b, int n);\n/* Runs it once. */\nint main(void){char *b = malloc(4); ft_probe_fill(b, 4); free(b); return 0;}\n' \
	> "$WORK/probe_hdr2.c"
# shellcheck disable=SC2086
want_broken_none "asan_check: ...or a later comment of the probe" 'LATER-COMMENT' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe_hdr2.c" --probe-src "$WORK/probe_hdr2.c" --src "$WORK/fill_oob.c"
# ...but all of a header written over lines, as most probes' are: a printer
# that stopped at the first line would pass every arm above.
# shellcheck disable=SC2086
want_out "asan_check: ...and all of a header written over lines" 'sized to fit exactly' -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe_hdr2.c" --probe-src "$WORK/probe_hdr2.c" --src "$WORK/fill_oob.c"
# THE COMPILER IS CAMPUS'S, WHATEVER THE BOX HAS. It took the first of
# clang-12, clang, gcc-10, gcc and cc on PATH, under -Werror, and a variable
# set and never read is clang-12's to accept and gcc-10's to refuse: the same
# code red on one machine, green on campus. Now --cc is required, and the
# pinned clang-12 decides.
printf 'void ft_probe_fill(char *b, int n){int i=0;int set;set=n;while(i<n){b[i]=(char)i;i++;}}\n' \
	> "$WORK/fill_unread.c"
# shellcheck disable=SC2086
want_green "asan_check: clang-12 accepts a variable set and never read" -- \
	"$SH" "$TOOLS/asan_check.sh" $BUILD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_unread.c"
want_broken "asan_check: without --cc it refuses, never takes the box's" \
	'--cc is required' -- \
	"$SH" "$TOOLS/asan_check.sh" --probe "$WORK/probe.c" --src "$WORK/fill_ok.c"
want_broken "asan_check: ...and without --ld" '--ld is required' -- \
	"$SH" "$TOOLS/asan_check.sh" --cc "$CLANG" --probe "$WORK/probe.c" --src "$WORK/fill_ok.c"
# THE LINKER'S PROOFS (tools/runner_lib.sh, rl_ld_pin), each a refusal: a
# linker that loads a libbfd from outside its library directory, and a
# compiler whose link would run another ld than the wrapper -- a stand-in
# that answers -### with the box's ld and builds nothing. The directory with
# no libbfd is this section's own, as symbols' is its own. The library the
# linker loads instead used to be the box's, which a box without binutils
# 2.38 does not have (V275); rl_ld_pin's wrapper sets LD_LIBRARY_PATH itself,
# so the linker it is handed is a stand-in that sets it again, to a copy of
# the fetched libraries, as the symbols arms have one, and runs the pinned
# ld.bfd.
mkdir -p "$WORK/ldnolib" "$WORK/ldelsewhere"
cp -L "${NM_LIB%/*}"/lib*.so* "$WORK/ldelsewhere/"
printf '#!/bin/sh\nLD_LIBRARY_PATH="%s/ldelsewhere" exec "%s" "$@"\n' "$WORK" "$LD" > "$WORK/ld_elsewhere"
chmod +x "$WORK/ld_elsewhere"
cat > "$WORK/boxld_cc" <<'BOXLD'
#!/bin/sh
for a in "$@"; do
	[ "$a" = "-###" ] && { echo ' "/usr/bin/ld" "-o" "x"' >&2; exit 0; }
done
exit 0
BOXLD
chmod +x "$WORK/boxld_cc"
# shellcheck disable=SC2086
want_broken "rl_ld_pin: a linker loading another libbfd refuses" \
	"the pinned linker loaded '$WORK/ldelsewhere/" -- \
	"$SH" "$TOOLS/asan_check.sh" --cc "$CLANG" $CLANG_LIBS --ld "$WORK/ld_elsewhere" --ld-lib "$WORK/ldnolib/none" \
		--probe "$WORK/probe.c" --src "$WORK/fill_ok.c"
# shellcheck disable=SC2086
want_broken "rl_ld_pin: a compiler linking with another ld refuses" 'did not take the pinned linker' -- \
	"$SH" "$TOOLS/asan_check.sh" --cc "$WORK/boxld_cc" $LD_PIN \
		--probe "$WORK/probe.c" --src "$WORK/fill_ok.c"
# ...and a linker the loader cannot start (a library this machine lacks):
# its words went into the file the loader's proof reads, which found no
# `calling init:` line for libbfd and refused as "could not observe" which
# one the linker loaded, naming nothing. The stand-in prints what the
# loader prints and exits as it does.
mkdir -p "$WORK/lddead"
printf '#!/bin/sh\necho "$0: error while loading shared libraries: libselftestmiss.so.1: cannot open shared object file: No such file or directory" >&2\nexit 127\n' \
	> "$WORK/lddead/ld.bfd"
chmod +x "$WORK/lddead/ld.bfd"
# shellcheck disable=SC2016 # the script is for the inner shell to expand
want_broken "rl_ld_pin: a linker that cannot start says so" 'the pinned linker cannot start (exit 127)' -- \
	"$SH" -c 'RL_NAME=selftest; . "$1"; rl_ld_pin "$2" "$3" "$4" "$5"' \
		_ "$TOOLS/runner_lib.sh" "$CLANG" "$WORK/lddead/ld.bfd" "$LD_LIB" "$WORK/lddead/w"
# shellcheck disable=SC2016 # the script is for the inner shell to expand
want_broken "rl_ld_pin: ...and names the library it lacks" 'The loader found no libselftestmiss.so.1' -- \
	"$SH" -c 'RL_NAME=selftest; . "$1"; rl_ld_pin "$2" "$3" "$4" "$5"' \
		_ "$TOOLS/runner_lib.sh" "$CLANG" "$WORK/lddead/ld.bfd" "$LD_LIB" "$WORK/lddead/w"
# The two loader proofs of tools/runner_lib.sh every such runner meets
# first -- the pinned linker's (rl_ld_pin) and the symbolizer's
# (rl_sanitizers) -- read the loader's lines from stderr, and an
# LD_DEBUG_OUTPUT set from outside sent them to files of its own: the proofs
# saw none and refused a correct setup (V276).
# shellcheck disable=SC2016 # the script is for the inner shell to expand
want_green "rl_ld_pin: an LD_DEBUG_OUTPUT from outside changes nothing" -- \
	env LD_DEBUG_OUTPUT="$WORK/asan-ld.dbg" \
	"$SH" -c 'RL_NAME=selftest; . "$1"; rl_cc_pin "$2" "$3" "$2"; rl_ld_pin "$2" "$4" "$5" "$6"' \
		_ "$TOOLS/runner_lib.sh" "$CLANG" "$CLANG_LIB_FILES" "$LD" "$LD_LIB" "$WORK/asan_ldenv/ld"
# shellcheck disable=SC2016 # the script is for the inner shell to expand
want_green "rl_sanitizers: ...nor in the symbolizer's proof" -- \
	env LD_DEBUG_OUTPUT="$WORK/asan-ld.dbg" \
	"$SH" -c 'RL_NAME=selftest; . "$1"; rl_sanitizers "$2" "$3" "$4"' \
		_ "$TOOLS/runner_lib.sh" "$WORK/asan_ldenv/sym" "$SYMBOLIZER" "$SYMBOLIZER_LIB"

