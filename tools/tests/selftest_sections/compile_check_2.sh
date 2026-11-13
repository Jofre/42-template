# --------------------------------------------------------------- compile_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
printf 'int main(void){return (0);}\n' > "$WORK/cc_ok.c"
# -Wall -Wextra -Werror is the point: this is a WARNING, and the layer exists to
# make a warning fail here rather than at the Moulinette.
printf 'int main(void){int x;return (x);}\n' > "$WORK/cc_warn.c"
want_green "compile_check: clean source compiles" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/cc_ok.c"
want_red   "compile_check: a warning is a failure, not a warning" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/cc_warn.c"
# The include path is the GRADER's. A header in a subfolder of the turn-in is
# staged (--staged-hdr) and on no path by itself: `cc *.c` finds it only
# through a #include that names the folder, and a Makefile project through
# the -I its recipes pass (--inc-file). --hdr puts a header's directory on
# the path, which is right beside the sources and was the false green in a
# subfolder: every staged header's directory went on -I, and a turn-in the
# grader cannot compile passed (a turn-in whose header sat in includes/).
mkdir -p "$WORK/ccinc/includes"
printf '#ifndef TOY_H\n# define TOY_H\nint\ttoy(void);\n#endif\n' > "$WORK/ccinc/includes/toy.h"
printf '#include "toy.h"\n\nint\ttoy(void)\n{\n\treturn (0);\n}\n' > "$WORK/ccinc/byname.c"
printf '#include "includes/toy.h"\n\nint\ttoy(void)\n{\n\treturn (0);\n}\n' > "$WORK/ccinc/bypath.c"
printf '%s/includes\n' "$WORK/ccinc" > "$WORK/ccinc/make_includes.txt"
: > "$WORK/ccinc/no_includes.txt"
want_red   "compile_check: a staged header in a subfolder is on no path" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccinc/byname.c" \
		--staged-hdr "$WORK/ccinc/includes/toy.h"
want_out   "compile_check: ...and the failure says what would reach it" \
	'#include the header by its path' -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccinc/byname.c" \
		--staged-hdr "$WORK/ccinc/includes/toy.h"
want_green "compile_check: ...a #include naming the folder reaches it" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccinc/bypath.c" \
		--staged-hdr "$WORK/ccinc/includes/toy.h"
want_green "compile_check: ...and so does the Makefile's -I (--inc-file)" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccinc/byname.c" \
		--staged-hdr "$WORK/ccinc/includes/toy.h" --inc-file "$WORK/ccinc/make_includes.txt"
want_red   "compile_check: a Makefile that passes no -I does not" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccinc/byname.c" \
		--staged-hdr "$WORK/ccinc/includes/toy.h" --inc-file "$WORK/ccinc/no_includes.txt"
want_out   "compile_check: ...and says the Makefile passes none" \
	'your Makefile passes: none' -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccinc/byname.c" \
		--staged-hdr "$WORK/ccinc/includes/toy.h" --inc-file "$WORK/ccinc/no_includes.txt"
want_broken "compile_check: an include list that is not there refuses" 'no include list' -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccinc/byname.c" \
		--inc-file "$WORK/ccinc/no-such-list"
# A red for another cause, the header reached through the Makefile's -I: no
# word about a header no #include reaches. A library's syntax error in one
# file was followed by just that, about the header the others had found
# (V198).
printf '#include "toy.h"\n\nint\ttoy(void)\n{\n\treturn (0)\n}\n' > "$WORK/ccinc/broken.c"
want_red   "compile_check: a syntax error is red, the header reached" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccinc/broken.c" \
		--staged-hdr "$WORK/ccinc/includes/toy.h" --inc-file "$WORK/ccinc/make_includes.txt"
want_broken_none "compile_check: ...with no word of a subfolder no -I reaches" \
	'These headers sit in a subfolder' -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccinc/broken.c" \
		--staged-hdr "$WORK/ccinc/includes/toy.h" --inc-file "$WORK/ccinc/make_includes.txt"
# A header the GRADER brings (C 08's ft_stock_str.h, kept under tests/) is
# on the path, and a red names where it is and the -I a compile by hand needs
# (finding 091) -- and the project's page, where there is one. The premise
# false, no note: a red with no such header, and a green with one.
mkdir -p "$WORK/ccgr/tests" "$WORK/ccgr/ex04"
printf '#ifndef GR_H\n# define GR_H\ntypedef struct s_gr\n{\n\tint\tn;\n}\tt_gr;\n#endif\n' \
	> "$WORK/ccgr/tests/gr.h"
printf '#include "gr.h"\n\nint\tgr_n(t_gr *g)\n{\n\treturn (g->n);\n}\n' > "$WORK/ccgr/ex04/ok.c"
printf '#include "gr.h"\n\nint\tgr_n(t_gr *g)\n{\n\treturn (g->m);\n}\n' > "$WORK/ccgr/ex04/bad.c"
want_green "compile_check: a grader's header is on the path" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccgr/ex04/ok.c" \
		--grader-hdr "$WORK/ccgr/tests/gr.h"
want_out   "compile_check: ...a red names it, and the -I by hand" \
	"compiles with -I $WORK/ccgr/tests" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccgr/ex04/bad.c" \
		--grader-hdr "$WORK/ccgr/tests/gr.h" --readme "toy/README.md"
want_out   "compile_check: ...and the project's page" \
	"toy/README.md shows one" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccgr/ex04/bad.c" \
		--grader-hdr "$WORK/ccgr/tests/gr.h" --readme "toy/README.md"
want_broken_none "compile_check: ...never on a green" "is the grader's" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccgr/ex04/ok.c" \
		--grader-hdr "$WORK/ccgr/tests/gr.h"
want_broken_none "compile_check: ...nor on a red with no grader's header" "is the grader's" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/cc_warn.c"
# Where the subject lets the student keep a copy of their own (C 12 ex08's
# `optional`), that copy, beside the source, is the one a quoted #include
# reads, and the note says so -- not "never yours", nor the -I to a copy the
# compile never read (review of WP-78).
mkdir -p "$WORK/ccgr/own"
cp "$WORK/ccgr/tests/gr.h" "$WORK/ccgr/own/gr.h"
cp "$WORK/ccgr/ex04/bad.c" "$WORK/ccgr/own/bad.c"
want_out   "compile_check: ...a copy kept beside the source is named as compiled" \
	"$WORK/ccgr/own/gr.h" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccgr/own/bad.c" \
		--grader-hdr "$WORK/ccgr/tests/gr.h"
want_broken_none "compile_check: ...and never called not yours to turn in" "never yours" -- \
	"$SH" "$TOOLS/compile_check.sh" --cc "$CC" --src "$WORK/ccgr/own/bad.c" \
		--grader-hdr "$WORK/ccgr/tests/gr.h"

