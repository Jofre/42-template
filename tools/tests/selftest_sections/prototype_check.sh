# -------------------------------------------------------------- prototype_check
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# C has no name mangling, so a definition whose signature disagrees with the
# subject's still LINKS and every other layer sees plausible-looking values. This
# runner is the only thing standing between that and a green, which makes a
# silent pass here indistinguishable from a Moulinette KO nobody predicted.
printf 'int ft_selftest_x(int n);\n' > "$WORK/proto.h"
printf 'int ft_selftest_x(int n){return n;}\n' > "$WORK/proto_ok.c"
printf 'char ft_selftest_x(char n){return n;}\n' > "$WORK/proto_bad.c"
want_green "prototype: a matching signature passes" -- \
	"$SH" "$TOOLS/prototype_check.sh" --proto "$WORK/proto.h" --src "$WORK/proto_ok.c"
want_red   "prototype: a different return/param type fails" -- \
	"$SH" "$TOOLS/prototype_check.sh" --proto "$WORK/proto.h" --src "$WORK/proto_bad.c"
# A header only a Makefile's -I reaches (--inc-file, as tools/student_build.sh
# --includes-out writes it): a library's prototype layer compiled with no -I
# and found none (V198). Each mode reads it, the one that reads the turn-in's
# headers alone (--no-restrict) as well.
mkdir -p "$WORK/protoinc/inc"
printf '#ifndef TOY_PI_H\n# define TOY_PI_H\nint\tft_selftest_x(int n);\n#endif\n' > "$WORK/protoinc/inc/toy_pi.h"
printf '#include "toy_pi.h"\nint ft_selftest_x(int n){return n;}\n' > "$WORK/protoinc/pi.c"
printf '%s\n' "$WORK/protoinc/inc" > "$WORK/protoinc/includes.txt"
printf 'restrict\tA sentence for the selftest, standing in for the call site.\n' > "$WORK/protoinc/q.tsv"
want_red   "prototype: a header only the Makefile's -I reaches, without it" -- \
	"$SH" "$TOOLS/prototype_check.sh" --proto "$WORK/proto.h" --src "$WORK/protoinc/pi.c"
want_green "prototype: ...is found through --inc-file" -- \
	"$SH" "$TOOLS/prototype_check.sh" --proto "$WORK/proto.h" \
		--inc-file "$WORK/protoinc/includes.txt" --src "$WORK/protoinc/pi.c"
want_red   "prototype --no-restrict: the same header, without it" -- \
	"$SH" "$TOOLS/prototype_check.sh" --no-restrict --quotes "$WORK/protoinc/q.tsv" \
		--proto "$WORK/proto.h" --src "$WORK/protoinc/pi.c"
want_green "prototype --no-restrict: ...and so in a mode of its own" -- \
	"$SH" "$TOOLS/prototype_check.sh" --no-restrict --quotes "$WORK/protoinc/q.tsv" \
		--proto "$WORK/proto.h" --inc-file "$WORK/protoinc/includes.txt" \
		--src "$WORK/protoinc/pi.c"

# WHAT A RED IS ABOUT (finding 133), each headline asserted where its premise
# holds, and the signature headline where it does not. Before, every compile
# error of this layer read "does not match the signature": an unguarded
# header, a file that does not compile at all, and (finding 132) a structure
# laid out otherwise than the subject prints it, which --layout now checks.
# The structure is an invented one, t_toy {a, b}, in a layout file named after
# the header it checks, as a project's tests/layout/<header> is.
mkdir -p "$WORK/lay/ok" "$WORK/lay/swapped" "$WORK/lay/unguarded" "$WORK/lay/check" \
	"$WORK/lay/sig"
printf '#ifndef TOY_H\n# define TOY_H\ntypedef struct s_toy\n{\n\tint\t\ta;\n\tchar\t*b;\n}\tt_toy;\nint\ttoy_a(t_toy *t);\n#endif\n' \
	> "$WORK/lay/ok/toy.h"
printf '#ifndef TOY_H\n# define TOY_H\ntypedef struct s_toy\n{\n\tchar\t*b;\n\tint\t\ta;\n}\tt_toy;\nint\ttoy_a(t_toy *t);\n#endif\n' \
	> "$WORK/lay/swapped/toy.h"
printf 'typedef struct s_toy\n{\n\tint\t\ta;\n\tchar\t*b;\n}\tt_toy;\nint\ttoy_a(t_toy *t);\n' \
	> "$WORK/lay/unguarded/toy.h"
for _d in ok swapped unguarded; do
	printf '#include "toy.h"\nint toy_a(t_toy *t){return (t->a);}\n' > "$WORK/lay/$_d/toy_a.c"
done
printf '#include "toy.h"\nint toy_a(t_toy *t){return (t->a)}\n' > "$WORK/lay/ok/broken.c"
printf '#ifndef PROTO_TOY_H\n# define PROTO_TOY_H\n# include "toy.h"\nint\ttoy_a(t_toy *t);\n#endif\n' \
	> "$WORK/lay/proto.h"
# A signature mismatch needs a header that does not declare the function
# itself: with its own prototype, the file does not compile on its own, which
# is the headline above, not this one.
printf '#ifndef TOY_H\n# define TOY_H\ntypedef struct s_toy\n{\n\tint\t\ta;\n\tchar\t*b;\n}\tt_toy;\n#endif\n' \
	> "$WORK/lay/sig/toy.h"
printf '#include "toy.h"\nchar toy_a(t_toy *t){return ((char)t->a);}\n' > "$WORK/lay/sig/toy_bad.c"
printf 'struct s_toy_subject { int a; char *b; };\n_Static_assert(__builtin_offsetof(t_toy, b) == __builtin_offsetof(struct s_toy_subject, b), "toy.h: b is not where the subject puts it");\n' \
	> "$WORK/lay/check/toy.h"
lay() {  # lay DIR SRC [ARGS...]: the runner on one toy tree
	_ld=$1; _ls=$2; shift 2
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CC" --src "$WORK/lay/$_ld/$_ls" "$@"
}
want_green "prototype: the subject's structure, as printed, passes" -- \
	lay ok toy_a.c --proto "$WORK/lay/proto.h" --layout "$WORK/lay/check/toy.h"
want_out "prototype: a structure laid out otherwise says so" \
	"is not the one" -- lay swapped toy_a.c --proto "$WORK/lay/proto.h" --layout "$WORK/lay/check/toy.h"
want_out "prototype: ...and so does --layout alone (the raised twin)" \
	"is not the one" -- lay swapped toy_a.c --layout "$WORK/lay/check/toy.h"
want_green "prototype: --layout alone passes the structure as printed" -- \
	lay ok toy_a.c --layout "$WORK/lay/check/toy.h"
want_out "prototype: a header read twice with no guard says so" \
	"has no include guard" -- lay unguarded toy_a.c --proto "$WORK/lay/proto.h"
want_out "prototype: a file that does not compile says so first" \
	"does not compile on its own" -- lay ok broken.c --proto "$WORK/lay/proto.h"
# The negative premises: a real signature mismatch, with a guarded header and
# the structure as printed, is still the signature's red and nothing else.
want_out "prototype: a signature mismatch keeps its own headline" \
	"does not match the signature" -- \
	lay sig toy_bad.c --proto "$WORK/lay/proto.h" --layout "$WORK/lay/check/toy.h"
want_broken_none "prototype: ...never the include-guard one" \
	"include guard" -- lay sig toy_bad.c --proto "$WORK/lay/proto.h" --layout "$WORK/lay/check/toy.h"
want_broken_none "prototype: ...nor the structure's" \
	"is not the one" -- lay sig toy_bad.c --proto "$WORK/lay/proto.h" --layout "$WORK/lay/check/toy.h"
# NOT EVERY REDEFINITION IS A MISSING GUARD. The headline used to be decided
# by the words "redefinition of" and "previous definition", which a guarded
# header gives too when the student's file defines the structure itself
# instead of including it: "a header was read twice ... has no include
# guard", both statements false (review of WP-47). Now the compiler has to
# say the header was included twice, or the second definition has to be the
# same line of the same file. Here toy.h is guarded and toy_a.c writes t_toy
# out again without including it.
mkdir -p "$WORK/lay/own"
cp "$WORK/lay/ok/toy.h" "$WORK/lay/own/toy.h"
printf 'typedef struct s_toy\n{\n\tint\t\ta;\n\tchar\t*b;\n}\tt_toy;\nint toy_a(t_toy *t){return (t->a);}\n' \
	> "$WORK/lay/own/toy_a.c"
want_broken_none "prototype: a structure written out again is no missing guard" \
	"include guard" -- lay own toy_a.c --proto "$WORK/lay/proto.h" --layout "$WORK/lay/check/toy.h"
want_out "prototype: ...it is one name defined in two places, both named" \
	"one name is defined in two places" -- \
	lay own toy_a.c --proto "$WORK/lay/proto.h" --layout "$WORK/lay/check/toy.h"
want_out "prototype: ...and the guard headline names the unguarded header" \
	"toy.h is read twice in one file" -- lay unguarded toy_a.c --proto "$WORK/lay/proto.h"

# THE STRUCTURE'S NAMES (--layout-tag), apart from its layout: the subject's
# tag, and the type of a field pointing to another node. A header laying t_toy
# out as printed under another tag passes --layout and fails --layout-tag,
# with a headline of its own -- never the structure's, whose "read each
# other's data wrong" would be false there.
mkdir -p "$WORK/lay/tag" "$WORK/lay/renamed"
printf '_Static_assert(__builtin_types_compatible_p(t_toy, struct s_toy), "toy.h: t_toy is not a typedef of struct s_toy");\n' \
	> "$WORK/lay/tag/toy.h"
sed 's/s_toy/s_other/' "$WORK/lay/ok/toy.h" > "$WORK/lay/renamed/toy.h"
cp "$WORK/lay/ok/toy_a.c" "$WORK/lay/renamed/toy_a.c"
want_green "prototype: --layout and --layout-tag together pass the subject's" -- \
	lay ok toy_a.c --layout "$WORK/lay/check/toy.h" --layout-tag "$WORK/lay/tag/toy.h"
want_green "prototype: another tag, laid out alike, passes --layout" -- \
	lay renamed toy_a.c --proto "$WORK/lay/proto.h" --layout "$WORK/lay/check/toy.h"
want_out "prototype: ...and --layout-tag says the names differ" \
	"does not name its structure as the" -- lay renamed toy_a.c --layout-tag "$WORK/lay/tag/toy.h"
want_broken_none "prototype: ...never that the layout does" \
	"is not the one" -- lay renamed toy_a.c --layout-tag "$WORK/lay/tag/toy.h"
# A pass on --layout-tag alone, as the twin of a subject whose names are
# certain runs it, compared the names and nothing of the layout: its OK says
# so, never that the header holds the structure.
want_out "prototype: a pass on --layout-tag alone says the names agree" \
	"names its structure as the subject prints it" -- lay ok toy_a.c --layout-tag "$WORK/lay/tag/toy.h"
want_broken_none "prototype: ...never that the header holds the structure" \
	"holds" -- lay ok toy_a.c --layout-tag "$WORK/lay/tag/toy.h"
want_broken "prototype: a --layout-tag that is not a file refuses" \
	"is not a file" -- lay ok toy_a.c --layout-tag "$WORK/lay/tag/nothing.h"

# A header the GRADER brings (--grader-hdr) is named on a red of this layer
# too, with the -I a compile by hand needs (finding 091); never on a green.
want_out "prototype: a red names a grader's header, and the -I" \
	"is the grader's" -- lay sig toy_bad.c --proto "$WORK/lay/proto.h" \
	--grader-hdr "$WORK/lay/sig/toy.h"
want_broken_none "prototype: ...never on a green" \
	"is the grader's" -- lay ok toy_a.c --proto "$WORK/lay/proto.h" \
	--grader-hdr "$WORK/lay/ok/toy.h"
# The student's own copy beside the source (C 12 ex08 lets one be kept) is
# the one compiled, and the note names it as such.
mkdir -p "$WORK/lay/grader"
cp "$WORK/lay/sig/toy.h" "$WORK/lay/grader/toy.h"
want_out "prototype: ...a copy of the student's own is named as the one read" \
	"is the one compiled here" -- lay sig toy_bad.c --proto "$WORK/lay/proto.h" \
	--grader-hdr "$WORK/lay/grader/toy.h"

# --names: the parameter NAMES a subject fixes (Rush 00's "named x and y"),
# read from the pinned clang's AST dump, never from the C text. The same
# types, other names, is red here and green in the types mode above -- and a
# declaration elsewhere with other names, a definition split over lines, a
# helper whose name holds the function's, all read the way clang reads them.
printf 'void ft_selftest_draw(int x, int y);\n' > "$WORK/proto_names.h"
printf 'static void\tft_selftest_draw_row(int n)\n{\n\t(void)n;\n}\n\nvoid ft_selftest_draw(int w, int h);\nvoid\tft_selftest_draw(int x,\n\t\tint y)\n{\n\t(void)x;\n\t(void)y;\n\tft_selftest_draw_row(1);\n}\n' \
	> "$WORK/names_ok.c"
printf 'void\tft_selftest_draw(int width, int height)\n{\n\t(void)width;\n\t(void)height;\n}\n' > "$WORK/names_bad.c"
printf 'void\tft_selftest_other(int x, int y)\n{\n\t(void)x;\n\t(void)y;\n}\n' > "$WORK/names_none.c"
printf '#include <stddef.h>\nvoid ft_selftest_draw(int x, int y);\n' > "$WORK/proto_names_inc.h"
names_run() {  # names_run PROTO SRC [--cc CC]
	_np=$1; _ns=$2; shift 2
	# shellcheck disable=SC2086
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --names \
		--proto "$WORK/$_np" --src "$WORK/$_ns" "$@"
}
want_green "prototype: --names passes the subject's names" -- names_run proto_names.h names_ok.c
want_red   "prototype: --names fails other names for the same types" -- \
	names_run proto_names.h names_bad.c
want_out   "prototype: ...naming both" 'names its parameters ft_selftest_draw(x, y)' -- \
	names_run proto_names.h names_bad.c
want_green "prototype: ...which the types mode lets through" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS \
		--proto "$WORK/proto_names.h" --src "$WORK/names_bad.c"
want_red   "prototype: --names fails a file with no definition" -- \
	names_run proto_names.h names_none.c
want_broken "prototype: --names refuses a contract that includes a header" \
	'A names contract includes nothing' -- names_run proto_names_inc.h names_ok.c
want_broken "prototype: ...saying how to declare a type it needs" \
	'typedef struct s_name t_name;' -- names_run proto_names_inc.h names_ok.c
# A library's names file (c_library's prototype_names) names a type the
# library's header defines: it declares it forward, including nothing, and
# the file that defines the function includes the header that defines it.
mkdir -p "$WORK/names_lib"
printf 'typedef struct s_selftest_hook t_selftest_hook;\nvoid ft_selftest_hang(t_selftest_hook **rack, t_selftest_hook *coat);\n' \
	> "$WORK/proto_names_fwd.h"
printf '#ifndef SELFTEST_LIB_H\n# define SELFTEST_LIB_H\ntypedef struct s_selftest_hook\n{\n\tint\twidth;\n}\tt_selftest_hook;\n#endif\n' \
	> "$WORK/names_lib/selftest_lib.h"
printf '#include "selftest_lib.h"\n\nvoid\tft_selftest_hang(t_selftest_hook **rack, t_selftest_hook *coat)\n{\n\t(void)rack;\n\t(void)coat;\n}\n' \
	> "$WORK/names_lib/hang_ok.c"
sed 's/\*\*rack, t_selftest_hook \*coat/**peg, t_selftest_hook *hat/; s/(void)rack;/(void)peg;/; s/(void)coat;/(void)hat;/' \
	"$WORK/names_lib/hang_ok.c" > "$WORK/names_lib/hang_bad.c"
want_green "prototype: --names reads a type declared forward" -- \
	names_run proto_names_fwd.h names_lib/hang_ok.c --inc "$WORK/names_lib"
want_red   "prototype: ...and fails other names for it" -- \
	names_run proto_names_fwd.h names_lib/hang_bad.c --inc "$WORK/names_lib"
# Two names in one contract. A broken source is reported once, not once per
# name; and a second misnamed function is reported too, which it was not
# while the first one's red stopped every later verdict.
printf 'void ft_selftest_draw(int x, int y);\nvoid ft_selftest_fill(int w, int h);\n' > "$WORK/proto_names2.h"
printf 'void\tft_selftest_draw(int a, int b)\n{\n\t(void)a;\n\t(void)b;\n}\n\nvoid\tft_selftest_fill(int c, int d)\n{\n\t(void)c;\n\t(void)d;\n}\n' \
	> "$WORK/names_bad2.c"
printf 'void\tft_selftest_fill(int w, int h)\n{\n\t(void)w;\n\t(void)h;\n}\n' > "$WORK/names_fill.c"
printf 'void\tft_selftest_draw(int x, int y)\n{\n\treturn (x + y);\n}\n' > "$WORK/names_broken.c"
want_out   "prototype: --names reports the second misnamed function too" \
	'names its parameters ft_selftest_fill(w, h)' -- names_run proto_names2.h names_bad2.c
want_red   "prototype: --names fails a source that does not compile" -- \
	names_run proto_names2.h names_broken.c --src "$WORK/names_fill.c"
names_broken_count() {
	names_run proto_names2.h names_broken.c --src "$WORK/names_fill.c" > "$WORK/names_broken.out" 2>&1
	echo "$(grep -c 'does not compile' "$WORK/names_broken.out") report(s) of the broken file"
}
want_out   "prototype: ...once, not once per name" '1 report(s) of the broken file' -- names_broken_count
want_out   "prototype: ...still judging the file that compiles" \
	'names_fill.c: ft_selftest_fill(w, h)' -- \
	names_run proto_names2.h names_broken.c --src "$WORK/names_fill.c"

