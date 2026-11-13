# ---------------------------------------------------------------- header_norm
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The Norm's two header rules the pinned norminette skips (WP-89, findings 093
# and 089): "Header files must be protected from double inclusions", decided
# by preprocessing a file that includes the header once and one that includes
# it twice, and a struct, union or enum named inside a typedef without its
# prefix, read from the pinned clang's own token list. Each verdict where its
# premise holds, and its message absent where it does not; every header is an
# invented toy. Two messages it must never print: the guard's own text, and a
# name a tag should have.
mkdir -p "$WORK/hn/sub"
hn() {  # hn ARGS...: the runner, with the pinned clang
	# shellcheck disable=SC2086
	"$SH" "$TOOLS/header_norm.sh" --cc "$CLANG" $CLANG_LIBS "$@"
}
printf '#ifndef TOY_BOX_H\n# define TOY_BOX_H\n# include <stddef.h>\n/* typedef struct nope { int a; } t_nope; */\ntypedef struct s_box\n{\n\tint\t\t\ta;\n\tstruct s_box\t*next;\n}\tt_box;\ntypedef union u_cell\n{\n\tint\ti;\n}\tt_cell;\ntypedef enum e_hue\n{\n\tTOY_RED\n}\tt_hue;\ntypedef struct\n{\n\tint\tz;\n}\tt_anon;\ntypedef const struct s_box\tt_cbox;\nint\ttoy_box(t_box *b);\n#endif\n' \
	> "$WORK/hn/toy_box.h"
printf 'int\ttoy_one(int n);\n' > "$WORK/hn/toy_proto.h"
printf '#define TOY_K 3\n' > "$WORK/hn/toy_def.h"
printf '#pragma once\n\nint\ttoy_two(void);\n' > "$WORK/hn/toy_once.h"
printf '#ifndef TOY_HALF_H\nint\ttoy_half(void);\n#endif\n#define TOY_HALF_H\n' > "$WORK/hn/toy_half.h"
printf '#ifndef TOY_TAG_H\n# define TOY_TAG_H\ntypedef struct box\n{\n\tint\ta;\n}\tt_box;\n#endif\n' \
	> "$WORK/hn/toy_tag.h"
printf '#ifndef TOY_UNI_H\n# define TOY_UNI_H\ntypedef union cell\n{\n\tint\ti;\n}\tt_cell;\n#endif\n' \
	> "$WORK/hn/toy_uni.h"
printf '#ifndef TOY_HUE_H\n# define TOY_HUE_H\ntypedef enum hue\n{\n\tTOY_BLUE\n}\tt_hue;\n#endif\n' \
	> "$WORK/hn/toy_hue.h"
printf '#ifndef TOY_FREE_H\n# define TOY_FREE_H\nstruct toy_free\n{\n\tint\ta;\n};\n#endif\n' \
	> "$WORK/hn/toy_free.h"
printf '#ifndef TOY_MISS_H\n# define TOY_MISS_H\n# include "toy_nowhere.h"\n#endif\n' > "$WORK/hn/toy_miss.h"
# Typedefs that DEFINE nothing: one naming libc's struct, which no student can
# rename, and one naming a struct defined above it, outside any typedef, whose
# bad name is norminette's (STRUCT_TYPE_NAMING) and must not be red twice.
printf '#ifndef TOY_TV_H\n# define TOY_TV_H\n# include <sys/time.h>\ntypedef struct timeval\tt_tv;\n#endif\n' \
	> "$WORK/hn/toy_tv.h"
printf '#ifndef TOY_LATER_H\n# define TOY_LATER_H\nstruct toy_later\n{\n\tint\ta;\n};\ntypedef struct toy_later\tt_later;\n#endif\n' \
	> "$WORK/hn/toy_later.h"
printf '#ifndef TOY_CTAG_H\n# define TOY_CTAG_H\ntypedef const struct cbox\n{\n\tint\ta;\n}\tt_cbox;\n#endif\n' \
	> "$WORK/hn/toy_ctag.h"
# A header a second inclusion cannot repeat, with no guard: safe to include
# twice, which is all the OK may say -- never "protected".
printf '# include <stddef.h>\n' > "$WORK/hn/toy_bare.h"
# A turned-in header that includes one the grader brings, from another folder.
mkdir -p "$WORK/hn/grader"
# Its tag has no prefix: never read, the grader's header is not the student's.
printf '#ifndef TOY_GIVEN_H\n# define TOY_GIVEN_H\ntypedef struct given\n{\n\tint\ta;\n}\tt_given;\n#endif\n' \
	> "$WORK/hn/grader/toy_given.h"
printf '#ifndef TOY_USES_H\n# define TOY_USES_H\n# include "toy_given.h"\nint\ttoy_uses(void);\n#endif\n' > "$WORK/hn/toy_uses.h"
printf '#ifndef TOY_SIB_H\n# define TOY_SIB_H\nint\ttoy_sib(void);\n#endif\n' > "$WORK/hn/sub/toy_sib.h"
printf '#ifndef TOY_INNER_H\n# define TOY_INNER_H\n# include "toy_sib.h"\n#endif\n' > "$WORK/hn/sub/toy_inner.h"
want_green "header_norm: a protected header, every tag prefixed, passes" -- \
	hn --header "$WORK/hn/toy_box.h"
want_out   "header_norm: ...and says what it read" \
	'toy_box.h: safe to include twice (included twice, it gives the same lines' -- \
	hn --header "$WORK/hn/toy_box.h"
want_green "header_norm: a header with nothing to repeat, unguarded, passes" -- \
	hn --header "$WORK/hn/toy_bare.h"
want_out   "header_norm: ...as safe to include twice" 'toy_bare.h: safe to include twice' -- \
	hn --header "$WORK/hn/toy_bare.h"
want_broken_none "header_norm: ...and never as protected" 'protected' -- \
	hn --header "$WORK/hn/toy_bare.h"
want_red   "header_norm: a header of prototypes alone, unprotected, fails" -- \
	hn --header "$WORK/hn/toy_proto.h"
want_out   "header_norm: ...as not protected from double inclusions" \
	'toy_proto.h is not protected from double inclusions' -- hn --header "$WORK/hn/toy_proto.h"
want_red   "header_norm: a header of #defines alone, unprotected, fails" -- \
	hn --header "$WORK/hn/toy_def.h"
want_green "header_norm: #pragma once protects it too" -- hn --header "$WORK/hn/toy_once.h"
want_red   "header_norm: a guard whose #define comes too late fails" -- \
	hn --header "$WORK/hn/toy_half.h"
want_broken_none "header_norm: ...and never prints the guard's name" \
	'TOY_HALF_H' -- hn --header "$WORK/hn/toy_half.h"
want_broken_none "header_norm: ...nor a directive" '#ifndef' -- hn --header "$WORK/hn/toy_half.h"
want_red   "header_norm: a struct named inside a typedef with no s_ fails" -- \
	hn --header "$WORK/hn/toy_tag.h"
want_out   "header_norm: ...quoting the Norm's rule for it" \
	"A structure's name must start by s_." -- hn --header "$WORK/hn/toy_tag.h"
want_broken_none "header_norm: ...and never the name it should have" \
	's_box' -- hn --header "$WORK/hn/toy_tag.h"
want_out   "header_norm: a union named inside a typedef with no u_ fails" \
	"A union's name must start by u_." -- hn --header "$WORK/hn/toy_uni.h"
want_out   "header_norm: an enum named inside a typedef with no e_ fails" \
	"An enum's name must start by e_." -- hn --header "$WORK/hn/toy_hue.h"
want_red   "header_norm: ...red, not merely said" -- hn --header "$WORK/hn/toy_hue.h"
want_green "header_norm: a struct named outside a typedef is norminette's" -- \
	hn --header "$WORK/hn/toy_free.h"
want_broken_none "header_norm: ...and is not reported here twice" \
	'must start by' -- hn --header "$WORK/hn/toy_free.h"
want_green "header_norm: a typedef naming libc's struct defines nothing to read" -- \
	hn --header "$WORK/hn/toy_tv.h"
want_green "header_norm: a typedef of a struct defined outside one is norminette's" -- \
	hn --header "$WORK/hn/toy_later.h"
want_broken_none "header_norm: ...and is not reported here twice" \
	'must start by' -- hn --header "$WORK/hn/toy_later.h"
want_red   "header_norm: a const struct defined inside a typedef is read too" -- \
	hn --header "$WORK/hn/toy_ctag.h"
want_green "header_norm: a header including the grader's, from its folder, passes" -- \
	hn --header "$WORK/hn/toy_uses.h" --grader-hdr "$WORK/hn/grader/toy_given.h"
want_red   "header_norm: ...and without --grader-hdr cannot be read" -- \
	hn --header "$WORK/hn/toy_uses.h"
want_out   "header_norm: ...saying so" 'the preprocessor stopped on it' -- \
	hn --header "$WORK/hn/toy_uses.h"
want_broken_none "header_norm: the grader's header is never read for the rules" \
	'must start by' -- hn --header "$WORK/hn/toy_uses.h" --grader-hdr "$WORK/hn/grader/toy_given.h"
want_red   "header_norm: a header the preprocessor stops on is red, not passed" -- \
	hn --header "$WORK/hn/toy_miss.h"
want_out   "header_norm: ...saying it could not be read" \
	'the preprocessor stopped on it' -- hn --header "$WORK/hn/toy_miss.h"
want_green "header_norm: a header includes its neighbour in its own folder" -- \
	hn --header "$WORK/hn/sub/toy_inner.h" --header "$WORK/hn/sub/toy_sib.h"
want_red   "header_norm: one bad header among good ones is red" -- \
	hn --header "$WORK/hn/toy_box.h" --header "$WORK/hn/toy_proto.h"
want_broken_none "header_norm: ...and only it is named" \
	'toy_box.h is not protected' -- hn --header "$WORK/hn/toy_box.h" --header "$WORK/hn/toy_proto.h"
want_broken "header_norm: no header to read refuses" 'at least one --header' -- hn
want_broken "header_norm: no compiler refuses" '--cc is required' -- \
	"$SH" "$TOOLS/header_norm.sh" --header "$WORK/hn/toy_box.h"
want_broken "header_norm: a compiler library that is not there refuses" 'does not exist' -- \
	"$SH" "$TOOLS/header_norm.sh" --cc "$CLANG" --cc-lib "$WORK/hn/nowhere/libnope.so" \
		--header "$WORK/hn/toy_box.h"

