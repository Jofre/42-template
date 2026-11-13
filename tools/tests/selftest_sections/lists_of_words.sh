# ------------------------------------------------------------ LISTS OF WORDS
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A runner's words from its command line -- every --src, an -I per header,
# what it forwards -- are one word per line (runner_lib.sh's rl_list_add,
# expanded between rl_split_on and rl_split_off). They were joined with a
# blank and expanded bare in eight runners, so a path holding a blank
# arrived as two words and the compiler said "no such file". The library,
# then each runner that compiles what it is handed, on a source and a header
# in folders named with a blank -- and a * in a name, which must not glob.
rl_words() {  # rl_words: three words through a list, each in brackets
	"$SH" -c '. "$1"; L=""; rl_list_add L "a b" "-I/x y" "*"; rl_split_on
		printf "[%s]" $L; rl_split_off; printf "\n"' _ "$TOOLS/runner_lib.sh"
}
want_out "runner_lib: a list keeps a blank and a * inside one word" \
	'[a b][-I/x y][*]' -- rl_words
mkdir -p "$WORK/lw dir/inc dir"
printf 'int ft_selftest_x(int n);\n' > "$WORK/lw dir/inc dir/lw.h"
printf '#include "lw.h"\nint ft_selftest_x(int n){return n;}\n' > "$WORK/lw dir/lw ok.c"
want_green "compile_check: a source and a header in folders with a blank" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/lw dir/lw ok.c" \
		--inc "$WORK/lw dir/inc dir"
want_green "prototype: ...the same, against the subject's signature" -- \
	"$SH" "$TOOLS/prototype_check.sh" --proto "$WORK/proto.h" \
		--src "$WORK/lw dir/lw ok.c" --inc "$WORK/lw dir/inc dir"
want_green "symbols: ...the same, exporting only its function" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_selftest_x \
		--src "$WORK/lw dir/lw ok.c" --inc "$WORK/lw dir/inc dir"
want_green "forbidden: ...the same, calling nothing" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - \
		--src "$WORK/lw dir/lw ok.c" --hdr "$WORK/lw dir/inc dir/lw.h"

