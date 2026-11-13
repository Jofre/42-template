# --------------------------------------------------------------- method_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The method layer (WP-90, findings 065 and 114): what a subject says about
# HOW a turn-in is built, which no output shows. --expect reads, from the
# student's sources compiled with -finstrument-functions and the recorder in
# tools/method_shim.c, whether a function of theirs is entered again while it
# is still running; --fixed-array has the pinned gcc name every array of
# variable length, every alloca, and every object at or past a bound. Every
# function here is an invented toy (toy_digits, a digit counter no exercise
# asks for), written each way a reading must tell apart: a loop, a call to
# itself, a static helper that recurses, two helpers calling each other, a
# loop over a stack of its own, a table.
mkdir -p "$WORK/mc"
printf 'the toy subject, p.1: "Create a toy function."\n' > "$WORK/mc/rule.txt"
printf '#include <stdio.h>\n\nint\ttoy_digits(int n);\n\nint\tmain(void)\n{\n\tprintf("%%d %%d %%d\\n", toy_digits(0), toy_digits(7), toy_digits(12345));\n\treturn (0);\n}\n' \
	> "$WORK/mc/main.c"
printf '#include <stdio.h>\n\nint\tmain(void)\n{\n\tputs("nothing called");\n\treturn (0);\n}\n' > "$WORK/mc/main_none.c"
printf 'int\ttoy_digits(int n)\n{\n\tint\tk;\n\n\tk = 1;\n\twhile (n >= 10)\n\t{\n\t\tn /= 10;\n\t\tk++;\n\t}\n\treturn (k);\n}\n' \
	> "$WORK/mc/loop.c"
printf 'int\ttoy_digits(int n)\n{\n\tif (n < 10)\n\t\treturn (1);\n\treturn (1 + toy_digits(n / 10));\n}\n' \
	> "$WORK/mc/self.c"
printf 'static int\ttoy_walk(int n, int k)\n{\n\tif (n < 10)\n\t\treturn (k);\n\treturn (toy_walk(n / 10, k + 1));\n}\n\nint\ttoy_digits(int n)\n{\n\treturn (toy_walk(n, 1));\n}\n' \
	> "$WORK/mc/helper.c"
printf 'static int\ttoy_odd(int n, int k);\n\nstatic int\ttoy_even(int n, int k)\n{\n\tif (n < 10)\n\t\treturn (k);\n\treturn (toy_odd(n / 10, k + 1));\n}\n\nstatic int\ttoy_odd(int n, int k)\n{\n\tif (n < 10)\n\t\treturn (k);\n\treturn (toy_even(n / 10, k + 1));\n}\n\nint\ttoy_digits(int n)\n{\n\treturn (toy_even(n, 1));\n}\n' \
	> "$WORK/mc/mutual.c"
printf 'int\ttoy_digits(int n)\n{\n\tint\tstack[16];\n\tint\ttop;\n\tint\tk;\n\n\ttop = 0;\n\tstack[top++] = n;\n\tk = 0;\n\twhile (top > 0)\n\t{\n\t\tn = stack[--top];\n\t\tk++;\n\t\tif (n >= 10)\n\t\t\tstack[top++] = n / 10;\n\t}\n\treturn (k);\n}\n' \
	> "$WORK/mc/ownstack.c"
printf 'int\ttoy_digits(int n)\n{\n\tstatic const int\tlimits[] = {10, 100, 1000, 10000, 100000};\n\tint\t\t\t\t\tk;\n\n\tk = 0;\n\twhile (k < 5 && n >= limits[k])\n\t\tk++;\n\treturn (k + 1);\n}\n' \
	> "$WORK/mc/table.c"
printf 'int\ttoy_digits(int n)\n{\n\tint\t*p;\n\n\tp = 0;\n\tif (n > 100)\n\t\treturn (*p);\n\treturn (1);\n}\n' > "$WORK/mc/crash.c"
mc() {  # mc EXPECT SRC [ARGS...]: the --expect mode on one toy
	_me=$1; _ms=$2; shift 2
	# env -u NO_SKIP: the suite's forced sweep would open the gate arms below
	# assert closed; the arm that opens it sets NO_SKIP itself.
	# shellcheck disable=SC2086
	env -u NO_SKIP "$SH" "$TOOLS/method_check.sh" --cc "$CLANG" $CLANG_LIBS $LD_PIN --expect "$_me" \
		--rule "$WORK/mc/rule.txt" --harness "$WORK/mc/main.c" \
		--shim "$TOOLS/method_shim.c" --src "$WORK/mc/$_ms" "$@"
}
want_green "method: a loop is iterative" -- mc iterative loop.c
want_red   "method: ...and not recursive" -- mc recursive loop.c
want_out   "method: ...saying nothing calls itself" 'none was entered again' -- mc recursive loop.c
want_out   "method: ...and quoting the call site's sentence" \
	'the toy subject, p.1: "Create a toy function."' -- mc recursive loop.c
want_out   "method: ...as the exercise's BUILD file quotes it" \
	"The subject, as this exercise's BUILD file quotes it:" -- mc recursive loop.c
# A function has no BUILD file of its own: its library's quotes the sentence
# (runner_lib.sh's rl_entry).
want_out   "method: ...and a function's, as its library's" \
	"The subject, as this library's BUILD file quotes it:" -- with_kind function mc recursive loop.c
want_green "method: a function calling itself is recursive" -- mc recursive self.c
want_red   "method: ...and not iterative" -- mc iterative self.c
want_out   "method: ...saying it calls itself" 'it calls itself, directly or through another' -- \
	mc iterative self.c
want_green "method: a static helper that recurses is recursive" -- mc recursive helper.c
want_red   "method: ...and not iterative" -- mc iterative helper.c
want_green "method: two helpers calling each other are recursive" -- mc recursive mutual.c
want_red   "method: a loop over a stack of its own is not recursive" -- mc recursive ownstack.c
want_green "method: ...and is iterative" -- mc iterative ownstack.c
want_green "method: a table is iterative" -- mc iterative table.c
want_red   "method: a run that crashes before it says is red, not passed" -- mc iterative crash.c
want_out   "method: ...saying the method was not seen" 'was not seen' -- mc iterative crash.c
# A run stopped from outside -- here the test program signals its waiter,
# tools/exit_status -- says nothing of the method: exit 2, never the
# student's FAIL.
printf '#include <signal.h>\n#include <stdio.h>\n#include <unistd.h>\n\nint\ttoy_digits(int n);\n\nint\tmain(void)\n{\n\tkill(getppid(), SIGTERM);\n\tsleep(1);\n\tprintf("%%d\\n", toy_digits(7));\n\treturn (0);\n}\n' \
	> "$WORK/mc/main_stop.c"
want_broken "method: a run stopped from outside is no verdict, exit 2" \
	'could not be judged: the program was stopped from outside' -- \
	mc iterative loop.c --harness "$WORK/mc/main_stop.c"
# A test program that forks: the child calls the function on a number that
# makes a recursive one call itself, the parent on one that does not. Each
# process has its own recorder, and the child's "reentered" must survive the
# parent's "done" (tools/method_shim.c appends one line per process).
printf '#include <stdio.h>\n#include <sys/wait.h>\n#include <unistd.h>\n\nint\ttoy_digits(int n);\n\nint\tmain(void)\n{\n\tpid_t\tpid;\n\tint\t\tst;\n\n\tpid = fork();\n\tif (pid == 0)\n\t{\n\t\tprintf("%%d\\n", toy_digits(12345));\n\t\treturn (0);\n\t}\n\twaitpid(pid, &st, 0);\n\tprintf("%%d\\n", toy_digits(7));\n\treturn (0);\n}\n' \
	> "$WORK/mc/main_fork.c"
want_green "method: a forking test program keeps the child's re-entry" -- \
	mc recursive self.c --harness "$WORK/mc/main_fork.c"
want_out   "method: ...saying the counts are one process's" 'ran as 2 processes' -- \
	mc recursive self.c --harness "$WORK/mc/main_fork.c"
want_red   "method: ...and it is not iterative" -- mc iterative self.c --harness "$WORK/mc/main_fork.c"
want_green "method: a loop under a forking test program is iterative" -- \
	mc iterative loop.c --harness "$WORK/mc/main_fork.c"
want_out   "method: ...whose counts are each the most any process reached" \
	'not necessarily the same process' -- mc iterative loop.c --harness "$WORK/mc/main_fork.c"
want_broken "method: a test program that calls nothing of the file refuses" \
	'no function of the turned-in file started' -- \
	"$SH" "$TOOLS/method_check.sh" --cc "$CLANG" $CLANG_LIBS $LD_PIN --expect iterative \
		--rule "$WORK/mc/rule.txt" --harness "$WORK/mc/main_none.c" \
		--shim "$TOOLS/method_shim.c" --src "$WORK/mc/loop.c"
# THE GATE: while the exercise's own fixture is red there is no right answer
# whose method to read, so the layer stands down -- and NO_SKIP=1 opens it.
toy_cc "$WORK/mc/gate_bin" "$WORK/mc/main.c" "$WORK/mc/loop.c"
printf '1 1 5\n' > "$WORK/mc/right.txt"
printf '9 9 9\n' > "$WORK/mc/wrong.txt"
want_green "method: a red fixture stands it down" -- mc recursive loop.c \
	--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/mc/gate_bin" \
	--gate-expected "$WORK/mc/wrong.txt"
want_out   "method: ...saying so" 'SKIP' -- mc recursive loop.c \
	--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/mc/gate_bin" \
	--gate-expected "$WORK/mc/wrong.txt"
want_out   "method: ...in its own words" 'a stub calls nothing twice' -- mc recursive loop.c \
	--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/mc/gate_bin" \
	--gate-expected "$WORK/mc/wrong.txt"
want_broken_none "method: ...never the corpus layers'" 'replays a generated corpus' -- \
	mc recursive loop.c --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/mc/gate_bin" \
	--gate-expected "$WORK/mc/wrong.txt"
# Its SKIP line names the output test it waits for (--gate-label), as Rush
# 00's main.c names its own: "the output fixture" alone sent a newcomer
# looking for which one.
want_out   "method: ...naming the test it waits for" 'SKIP — ex00_output, this exercise' -- \
	mc recursive loop.c --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/mc/gate_bin" \
	--gate-expected "$WORK/mc/wrong.txt" --gate-label ex00_output
want_red   "method: a green fixture lets it judge" -- mc recursive loop.c \
	--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/mc/gate_bin" \
	--gate-expected "$WORK/mc/right.txt"
want_red   "method: NO_SKIP=1 opens a red gate" -- env NO_SKIP=1 "$SH" "$TOOLS/method_check.sh" \
	--cc "$CLANG" $CLANG_LIBS $LD_PIN --expect recursive --rule "$WORK/mc/rule.txt" \
	--harness "$WORK/mc/main.c" --shim "$TOOLS/method_shim.c" --src "$WORK/mc/loop.c" \
	--gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/mc/gate_bin" \
	--gate-expected "$WORK/mc/wrong.txt"
# The gate reads the fixture as the exercise's output test does: a hex dump's
# (c_function's sanitize) holds offsets where the program prints addresses,
# so read plainly it is red on every right answer and the layer would stand
# down for good. Scripts stand in for the programs: the gate only compares.
printf '#!/bin/sh\nprintf "@addr 00007ffc12345670\\n00007ffc12345670: 4142 AB\\n"\n' > "$WORK/mc/gate_dump"
printf '0000000000000000: 4142 AB\n' > "$WORK/mc/dump.txt"
printf '#!/bin/sh\nprintf "one\\t1\\n"\n' > "$WORK/mc/gate_lab"
printf 'one\t1\n' > "$WORK/mc/lab.txt"
chmod +x "$WORK/mc/gate_dump" "$WORK/mc/gate_lab"
want_red   "method: --gate-sanitize reads a dump's fixture as its output test does" -- \
	mc recursive loop.c --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/mc/gate_dump" \
	--gate-expected "$WORK/mc/dump.txt" --gate-sanitize
want_out   "method: ...which, read plainly, stands it down" 'SKIP' -- \
	mc recursive loop.c --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/mc/gate_dump" \
	--gate-expected "$WORK/mc/dump.txt"
want_red   "method: --gate-labeled reads a labeled fixture" -- \
	mc recursive loop.c --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/mc/gate_lab" \
	--gate-expected "$WORK/mc/lab.txt" --gate-labeled
want_broken "method: --expect takes recursive or iterative" 'recursive or iterative' -- \
	mc sideways loop.c
want_broken "method: no --rule refuses" '--rule FILE is required' -- \
	"$SH" "$TOOLS/method_check.sh" --cc "$CLANG" $CLANG_LIBS $LD_PIN --expect iterative \
		--harness "$WORK/mc/main.c" --shim "$TOOLS/method_shim.c" --src "$WORK/mc/loop.c"
want_broken "method: one question per test" 'two questions' -- mc iterative loop.c --fixed-array
# A header only a Makefile's -I reaches (--inc-file, read by runner_lib.sh's
# rl_inc_file as every runner reads it, V317): the toy's own folder does not
# hold it, so without the list it does not compile. And a list not there.
mkdir -p "$WORK/mc/inc/sub"
printf 'int\ttoy_digits(int n);\n' > "$WORK/mc/inc/sub/toy_digits.h"
{ printf '#include "toy_digits.h"\n\n'; cat "$WORK/mc/loop.c"; } > "$WORK/mc/inc/loop_inc.c"
printf '%s\n' "$WORK/mc/inc/sub" > "$WORK/mc/inc/incs.txt"
want_green "method: a header only --inc-file reaches compiles" -- \
	"$SH" "$TOOLS/method_check.sh" --cc "$CLANG" $CLANG_LIBS $LD_PIN --expect iterative \
		--rule "$WORK/mc/rule.txt" --harness "$WORK/mc/main.c" --shim "$TOOLS/method_shim.c" \
		--src "$WORK/mc/inc/loop_inc.c" --inc-file "$WORK/mc/inc/incs.txt"
want_broken "method: ...and a list that is not there refuses" 'no include list' -- \
	"$SH" "$TOOLS/method_check.sh" --cc "$CLANG" $CLANG_LIBS $LD_PIN --expect iterative \
		--rule "$WORK/mc/rule.txt" --harness "$WORK/mc/main.c" --shim "$TOOLS/method_shim.c" \
		--src "$WORK/mc/inc/loop_inc.c" --inc-file "$WORK/mc/inc/nowhere.txt"

# --fixed-array, with the pinned gcc: the only campus compiler that names an
# object by its size. Its bound is an upper one, and the object is measured,
# never the frame that holds it.
# Each toy only touches its buffer: the check compiles and runs nothing, and a
# body that did I/O would be one exercise's program in a fixture (AGENTS.md
# section 0).
printf 'int\tmain(void)\n{\n\tchar\tbuf[4096];\n\n\tbuf[0] = 0;\n\treturn (buf[0]);\n}\n' \
	> "$WORK/mc/buf_small.c"
for _sz in 40000 30720 30719; do
	sed "s/buf\[4096\]/buf[$_sz]/" "$WORK/mc/buf_small.c" > "$WORK/mc/buf_$_sz.c"
done
printf 'static char\tg_buf[40000];\n\nint\tmain(void)\n{\n\tg_buf[0] = 0;\n\treturn (g_buf[0]);\n}\n' \
	> "$WORK/mc/buf_static.c"
# An object in a header the source includes: named where it is, never under
# the source's name with the header's line number. Two sources include it,
# and it is reported once.
mkdir -p "$WORK/mc/inc"
printf '#ifndef TOY_BIG_H\n# define TOY_BIG_H\n\nstatic char\tg_toy_big[40000];\n\n#endif\n' \
	> "$WORK/mc/inc/toy_big.h"
printf '#include "toy_big.h"\n\nint\tmain(void)\n{\n\tg_toy_big[0] = 0;\n\treturn (g_toy_big[0]);\n}\n' \
	> "$WORK/mc/buf_hdr.c"
printf '#include "toy_big.h"\n\nint\ttoy_other(void)\n{\n\treturn (g_toy_big[1]);\n}\n' \
	> "$WORK/mc/buf_hdr2.c"
printf 'int\tmain(int argc, char **argv)\n{\n\tchar\tbuf[argc * 512];\n\n\t(void)argv;\n\tbuf[0] = 0;\n\treturn (buf[0]);\n}\n' \
	> "$WORK/mc/buf_vla.c"
printf 'int\tmain(int argc, char **argv)\n{\n\tchar\t*buf;\n\n\t(void)argv;\n\tbuf = __builtin_alloca(argc * 512);\n\tbuf[0] = 0;\n\treturn (buf[0]);\n}\n' \
	> "$WORK/mc/buf_alloca.c"
printf 'int\tmain(void)\n{\n\treturn (0)\n}\n' > "$WORK/mc/buf_broken.c"
fa() {  # fa SRC [ARGS...]: the --fixed-array mode, with a toy rule
	_fs=$1; shift
	# env -u NO_SKIP, as mc's: the stand-down arm below asserts the SKIP.
	env -u NO_SKIP "$SH" "$TOOLS/method_check.sh" --fixed-array --rule "$WORK/mc/rule.txt" \
		--cc "$GCC" --cc-under "$GCC" --src "$WORK/mc/$_fs" "$@"
}
want_green "fixed_array: a small array passes the bound" -- fa buf_small.c --max-bytes 30720
want_red   "fixed_array: an array past the bound fails" -- fa buf_40000.c --max-bytes 30720
want_out   "fixed_array: ...naming it and its size" "'buf' is 40000 bytes" -- \
	fa buf_40000.c --max-bytes 30720
want_red   "fixed_array: an array of exactly the bound is not less than it" -- \
	fa buf_30720.c --max-bytes 30720
want_green "fixed_array: one byte less passes" -- fa buf_30719.c --max-bytes 30720
want_red   "fixed_array: a static array past the bound fails too" -- fa buf_static.c --max-bytes 30720
want_green "fixed_array: no bound, no size is judged" -- fa buf_40000.c
# What only --expect reads is refused under --fixed-array, never ignored: a
# gate given to it would read as gated and wait on nothing.
want_broken "fixed_array: a test program is --expect's, refused" \
	'--harness goes with --expect' -- fa buf_small.c --harness "$WORK/mc/main_fork.c"
want_broken "fixed_array: ...and so is a whole gate" '--gate-differ goes with --expect' -- \
	fa buf_small.c --gate-differ "$TOOLS/diff_output.sh" --gate-bin "$WORK/mc/rule.txt" \
	--gate-expected "$WORK/mc/rule.txt"
want_red   "fixed_array: an object in an included header fails" -- \
	fa buf_hdr.c --inc "$WORK/mc/inc/toy_big.h" --max-bytes 30720
want_out   "fixed_array: ...named in the header, on its own line" 'toy_big.h, line 4:' -- \
	fa buf_hdr.c --inc "$WORK/mc/inc/toy_big.h" --max-bytes 30720
want_broken_none "fixed_array: ...never under the source's name" 'buf_hdr.c, line' -- \
	fa buf_hdr.c --inc "$WORK/mc/inc/toy_big.h" --max-bytes 30720
want_out   "fixed_array: ...and once, when two sources include it" \
	'1 object(s) the subject' -- fa buf_hdr.c --src "$WORK/mc/buf_hdr2.c" \
	--inc "$WORK/mc/inc/toy_big.h" --max-bytes 30720
want_red   "fixed_array: an array of variable length fails" -- fa buf_vla.c
want_out   "fixed_array: ...saying its size is not fixed" 'array of variable length' -- fa buf_vla.c
want_red   "fixed_array: alloca fails" -- fa buf_alloca.c
want_green "fixed_array: a file gcc cannot compile stands it down" -- fa buf_broken.c
want_out   "fixed_array: ...naming the compile layers" 'The compile layers say why' -- fa buf_broken.c
want_red   "fixed_array: ...and NO_SKIP=1 makes that red" -- env NO_SKIP=1 "$SH" \
	"$TOOLS/method_check.sh" --fixed-array --rule "$WORK/mc/rule.txt" --cc "$GCC" \
	--cc-under "$GCC" --src "$WORK/mc/buf_broken.c"
want_broken "fixed_array: a compiler that names no size refuses" 'did not report' -- \
	"$SH" "$TOOLS/method_check.sh" --fixed-array --rule "$WORK/mc/rule.txt" \
		--cc "$CLANG" $CLANG_LIBS --max-bytes 30720 --src "$WORK/mc/buf_small.c"
want_broken "fixed_array: a gcc searching someone else's tree refuses" \
	'not searching its own tree' -- fa buf_small.c --cc-under "$WORK/mc/rule.txt"

