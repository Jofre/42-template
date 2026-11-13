# ----------------------------------------------------------- forbidden_symbols
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
printf 'int ft_x(void){return 0;}\n' > "$WORK/clean.c"
printf '#include <stdio.h>\nint ft_x(void){printf("no");return 0;}\n' > "$WORK/dirty.c"
want_green "forbidden: a function calling nothing passes" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/clean.c"
# ...whatever LD_DEBUG_OUTPUT the host sets: the nm proof reads the loader's
# lines from stderr, and one set from outside sent them elsewhere (V276).
want_green "forbidden: ...also under an LD_DEBUG_OUTPUT from outside" -- \
	env LD_DEBUG_OUTPUT="$WORK/forbidden-ld.dbg" \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/clean.c"
want_red   "forbidden: an unauthorised printf fails" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/dirty.c"
# A source that does not compile is no verdict (exit 2), and the compiler's
# words reach the log through the renderer, as every other runner's do: an
# escape byte in an include's name is shown, never written raw, and a long
# report is cut with the count of what was left out. It was a bare cat of
# the compiler's stderr (V314). Invented names; 30 uses of undeclared ones
# say more than the 25 lines the excerpt keeps.
printf '#include "\033[2Jtoy_gone.h"\nint ft_x(void){return 0;}\n' > "$WORK/fs_esc.c"
{
	printf 'int ft_x(void)\n{\n'
	for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
		printf '\ttoy_undeclared_%s = 0;\n' "$_i"
	done
	printf '\treturn (0);\n}\n'
} > "$WORK/fs_many.c"
fs_said() {  # its words, whatever its status: the first arm asserts that
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$1" 2>&1
	return 0
}
want_broken "forbidden: a source that does not compile is no verdict" \
	'failed to compile' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/fs_esc.c"
want_out   "forbidden: ...the compiler's escape byte is shown" \
	'\x1b[2Jtoy_gone.h' -- fs_said "$WORK/fs_esc.c"
want_broken_none "forbidden: ...never written raw" \
	"$(printf '\033')" -- fs_said "$WORK/fs_esc.c"
want_out   "forbidden: ...and a long report is cut, saying how much" \
	'more line(s)' -- fs_said "$WORK/fs_many.c"
# --inc-file, read by runner_lib.sh's rl_inc_file as every runner reads it
# (V317): a header only the list's directory reaches, and a list not there.
mkdir -p "$WORK/fsinc/sub"
printf 'int\ttoy_inc(void);\n' > "$WORK/fsinc/sub/toy_inc.h"
printf '#include "toy_inc.h"\n\nint\ttoy_inc(void)\n{\n\treturn (0);\n}\n' > "$WORK/fsinc/toy_inc.c"
printf '%s\n' "$WORK/fsinc/sub" > "$WORK/fsinc/incs.txt"
want_green "forbidden: a header reached through --inc-file compiles" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - \
		--inc-file "$WORK/fsinc/incs.txt" --src "$WORK/fsinc/toy_inc.c"
want_broken "forbidden: ...and a list that is not there refuses" \
	'no include list' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - \
		--inc-file "$WORK/fsinc/nowhere.txt" --src "$WORK/fsinc/toy_inc.c"
# WHO GRADES, from the project's contract (RL_GRADER; runner_lib.sh's rl_at).
# It said "an outright KO at the Moulinette" to a rush team, whom no program
# grades (finding 145).
want_out   "forbidden: a defended project's KO is at the defense" 'KO at the defense' -- \
	env RL_GRADER=defense "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - \
		--src "$WORK/dirty.c"
want_out   "forbidden_symbols: ...AUTHORISED FOR THIS EXERCISE" 'AUTHORISED FOR THIS EXERCISE:' -- \
	env RL_GRADER=defense "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - \
		--src "$WORK/dirty.c"
# WHAT IT TESTS, from the contract's units (RL_UNIT_KIND; runner_lib.sh's
# rl_noun): a function's red names the function, not an exercise.
want_out   "forbidden_symbols: a function's FAIL names the function" \
	'forbidden_symbols: FAIL — this function calls a function it is not' -- \
	env RL_GRADER=defense RL_UNIT_KIND=function "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" \
		--nm-lib "$NM_LIB" --allowed - --src "$WORK/dirty.c"
want_out   "forbidden_symbols: ...and its AUTHORISED line names it" 'AUTHORISED FOR THIS FUNCTION:' -- \
	env RL_GRADER=defense RL_UNIT_KIND=function "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" \
		--nm-lib "$NM_LIB" --allowed - --src "$WORK/dirty.c"
# ...and so does its pass, whose sentence spans two lines of the runner:
# what defines a function is its library (runner_lib.sh's rl_entry).
want_out   "forbidden_symbols: an exercise's OK names the exercise" \
	"exercise itself or on the subject's authorised list." -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/clean.c"
want_out   "forbidden_symbols: ...and a library's, the library" \
	"library itself or on the subject's authorised list." -- \
	env RL_UNIT_KIND=library "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" \
		--allowed - --src "$WORK/clean.c"
want_out   "forbidden_symbols: ...and a function's, its library" \
	"library itself or on the subject's authorised list." -- \
	env RL_UNIT_KIND=function "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" \
		--allowed - --src "$WORK/clean.c"
want_broken_none "forbidden: ...and never at the Moulinette" 'Moulinette' -- \
	env RL_GRADER=defense "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - \
		--src "$WORK/dirty.c"
want_out   "forbidden: a program-graded one's is at the Moulinette" 'KO at the Moulinette' -- \
	env RL_GRADER=both "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - \
		--src "$WORK/dirty.c"
want_out   "forbidden: with no contract, it names no grader" \
	'KO wherever this project is graded' -- \
	env RL_GRADER= "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - \
		--src "$WORK/dirty.c"
want_broken "forbidden: a grader no contract can hold is a broken harness" \
	'moulinette, defense or both' -- \
	env RL_GRADER=peers "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - \
		--src "$WORK/dirty.c"

# THE BASELINE EXEMPTION, both directions. memcpy and friends are tolerated
# because code generation emits them for aggregate copies -- and that tolerance
# used to be unconditional, so a file whose body literally called memcpy passed
# with "Authorised: none — no external function at all".
#
# The green arm is the one that keeps the exemption honest: emitted.c never
# names memcpy, and a local array with a large constant initialiser is the
# shape that makes clang emit the call anyway. One real deliverable has that
# shape -- the ONE object in all 140 that references a baseline symbol -- so
# this arm is what stops the fix from reddening real work. The numbers are
# arbitrary on purpose: an earlier version copied that deliverable's table,
# which said more about how it solved its exercise than a fixture should.
# emitted.c is forbidden_functions' too: plain code, made in every shard
# (st_mine).
printf 'int ft_x(void){char p[16][6] = {{7,3,9,1,4,2},{2,8,4,6,1,1},{5,5,3,7,2,9},{9,9,1,2,6,3}};return p[3][0];}\n' \
	> "$WORK/emitted.c"
printf 'void *memcpy(void *, const void *, unsigned long);\nint ft_x(char *d, char *s){memcpy(d, s, 4);return 0;}\n' \
	> "$WORK/calls_memcpy.c"
printf 'int ft_x(char *d){/* behaves like memcpy(3), without calling it */ d[0] = 1;return 0;}\n' \
	> "$WORK/names_memcpy.c"
want_green "forbidden: a compiler-emitted memcpy is still tolerated" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/emitted.c"
want_red   "forbidden: ...but calling memcpy yourself is not" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/calls_memcpy.c"
want_green "forbidden: naming it in a comment is not calling it" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/names_memcpy.c"
# ...and the case that one cannot reach, since names_memcpy.c emits no memcpy:
# a comment naming memcpy( BESIDE an emitted one. The raw file was read, so
# the comment cost the exemption and turned the emitted call into the
# student's. Then a #define: the file as written holds no memcpy( to find,
# but the code the compiler saw does, so it is the student's call; left
# unused, the same #define is nobody's.
printf 'int ft_x(void){char p[16][6] = {{7,3,9,1,4,2},{2,8,4,6,1,1},{5,5,3,7,2,9},{9,9,1,2,6,3}};/* not memcpy(3) */return p[3][0];}\n' \
	> "$WORK/emitted_named.c"
printf '#include <string.h>\n#define CP memcpy\nint ft_x(char *d, char *s){CP(d, s, 4);return 0;}\n' \
	> "$WORK/alias_memcpy.c"
{ printf '#include <string.h>\n#define CP memcpy\n'; cat "$WORK/emitted.c"; } > "$WORK/unused_alias.c"
want_green "forbidden: an emitted memcpy beside a comment naming it" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/emitted_named.c"
want_red   "forbidden: a memcpy called through a #define is yours" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/alias_memcpy.c"
want_green "forbidden: ...an unused #define of it is not" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/unused_alias.c"
# And the compiler's own spelling of the call: `__builtin_memset(p, 0, n)`
# with an n not known at compile time is `U memset` in the object, as if the
# source said memset, and a word match on memset never saw it, so it was
# forgiven as code generation. Its place is the __builtin_ line.
printf '#include <stddef.h>\n\nvoid\tft_x(void *p, size_t n)\n{\n\t__builtin_memset(p, 0, n);\n}\n' \
	> "$WORK/builtin_memset.c"
want_red   "forbidden: a memset written as __builtin_memset is yours" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/builtin_memset.c"
want_out   "forbidden: ...named at the __builtin_ line" \
	"    memset   (at $WORK/builtin_memset.c:5)" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/builtin_memset.c"
want_out   "forbidden: ...saying how it was written" \
	'written as __builtin_memset' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/builtin_memset.c"

# THE NAME NM SEES IS NOT ALWAYS THE NAME WRITTEN. glibc's headers read errno
# through __errno_location(), rename <libgen.h>'s basename to __xpg_basename
# and expand every <ctype.h> classifier into __ctype_b_loc. The layer compared
# nm's names literally, so C 10 ex01-ex03 -- whose subject says "You may use
# the variable errno" and allows basename -- were red on every honest answer,
# and a student who wrote isspace was told they had called __ctype_b_loc.
#
# Both directions: an allowed public name passes under its internal one, and a
# forbidden one is reported by the name the student wrote, with the symbol nm
# saw beside it. The classifier arms pin the one row nm cannot resolve alone:
# which classifier was written comes from the source, comments excluded.
printf '#include <errno.h>\n#include <libgen.h>\nint ft_x(char *p)\n{\n\tbasename(p);\n\treturn (errno);\n}\n' \
	> "$WORK/fb_errno.c"
printf '#include <ctype.h>\nint ft_x(int c)\n{\n\treturn (isalpha(c));\n}\n' > "$WORK/fb_alpha.c"
printf '#include <ctype.h>\n/* unlike isalpha(3), digits only */\nint ft_x(int c)\n{\n\treturn (isdigit(c));\n}\n' \
	> "$WORK/fb_digit.c"
printf '#include <ctype.h>\nint ft_x(int c)\n{\n\treturn (isdigit(c) + isalpha(c));\n}\n' > "$WORK/fb_both.c"
want_green "forbidden: errno and basename pass under glibc's names" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed errno,basename --src "$WORK/fb_errno.c"
want_red   "forbidden: ...errno is refused where not allowed" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed basename --src "$WORK/fb_errno.c"
want_red   "forbidden: ...and so is basename" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed errno --src "$WORK/fb_errno.c"
want_out   "forbidden: ...reported as errno, with its line" \
	"    errno   (at $WORK/fb_errno.c:6)" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed basename --src "$WORK/fb_errno.c"
want_out   "forbidden: ...then as the symbol nm saw" \
	'seen by nm as __errno_location' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed basename --src "$WORK/fb_errno.c"
want_red   "forbidden: an unauthorised isalpha fails" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/fb_alpha.c"
want_out   "forbidden: ...reported as isalpha, with its line" \
	"    isalpha   (at $WORK/fb_alpha.c:4)" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/fb_alpha.c"
want_green "forbidden: an allowed classifier passes, comment aside" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed isdigit --src "$WORK/fb_digit.c"
want_red   "forbidden: ...but not one it does not allow beside it" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed isdigit --src "$WORK/fb_both.c"
want_out   "forbidden: ...which is named, not the shared symbol" \
	"    isalpha   (at $WORK/fb_both.c:4)" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed isdigit --src "$WORK/fb_both.c"

# WHICH CLASSIFIER comes from the code the compiler saw, not from the file as
# written. A classifier being allowed used to pass __ctype_b_loc whatever the
# source did with it, so `#define MYALPHA isalpha` got through on an exercise
# allowed isdigit, with a green line claiming "an allowed classifier". The
# macro arms go both ways, in the .c file and in the student's own header:
# an alias that is expanded is a use, reported at the line that names it,
# and one that is never expanded is none. With no classifier used by name at
# all, the family is refused rather than forgiven.
printf '#include <ctype.h>\n#define MYALPHA isalpha\nint ft_x(int c)\n{\n\treturn (MYALPHA(c));\n}\n' \
	> "$WORK/fb_macro.c"
printf '#include <ctype.h>\nint ft_x(int c)\n{\n\treturn ((*__ctype_b_loc())[c] & 8);\n}\n' > "$WORK/fb_direct.c"
printf '#include <ctype.h>\n#define FT_NUM isdigit\n#define FT_UP isupper\n' > "$WORK/fb_own.h"
printf '#include "fb_own.h"\nint ft_x(int c)\n{\n\treturn (FT_NUM(c));\n}\n' > "$WORK/fb_hdr_ok.c"
printf '#include "fb_own.h"\nint ft_x(int c)\n{\n\treturn (FT_UP(c));\n}\n' > "$WORK/fb_hdr_bad.c"
want_red   "forbidden: a classifier behind a #define is still judged" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed isdigit --src "$WORK/fb_macro.c"
want_out   "forbidden: ...and named at the line that aliases it" \
	"    isalpha   (at $WORK/fb_macro.c:2)" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed isdigit --src "$WORK/fb_macro.c"
want_green "forbidden: an allowed one through your own header passes" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed isdigit --src "$WORK/fb_hdr_ok.c"
want_out   "forbidden: ...a forbidden one is named in that header" \
	"    isupper   (at $WORK/fb_own.h:3)" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed isdigit --src "$WORK/fb_hdr_bad.c"
want_red   "forbidden: no classifier used by name is not an allowed one" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed isdigit --src "$WORK/fb_direct.c"
want_out   "forbidden: ...and is reported as the family" \
	'a <ctype.h> classifier' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed isdigit --src "$WORK/fb_direct.c"
want_broken_none "forbidden: ...never when the classifier has a name" \
	'a <ctype.h> classifier' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/fb_alpha.c"

# THE NOTES THAT NAME A CAUSE, each with an arm where the cause is absent and
# the note must stay out. A pass that leaned on the alias table says what nm
# saw and what it was read as; a pass on a plain allowed write says nothing of
# the kind. "seen by nm as" belongs to an alias, never to a plain printf. The __ note is for a
# libc-internal name the table does not know -- assert() compiles into
# __assert_fail -- and not for every refusal.
printf '#include <assert.h>\nint ft_x(int c)\n{\n\tassert(c);\n\treturn (c);\n}\n' > "$WORK/fb_assert.c"
printf '#include <unistd.h>\nint ft_x(void)\n{\n\treturn (write(1, "", 0));\n}\n' > "$WORK/fb_write.c"
want_out   "forbidden: a pass through an alias says what nm saw" \
	"(nm saw __errno_location, which is errno)" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed errno,basename --src "$WORK/fb_errno.c"
want_out   "forbidden: ...naming the classifier the source used" \
	"(nm saw __ctype_b_loc, which is isdigit)" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed isdigit --src "$WORK/fb_digit.c"
want_broken_none "forbidden: ...and a pass with no alias says nothing" \
	"(nm saw" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed write --src "$WORK/fb_write.c"
want_broken_none "forbidden: a plain printf has no 'seen by nm as'" \
	'seen by nm as' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/dirty.c"
want_out   "forbidden: an unknown __ name says where those come from" \
	'rarely one you wrote' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/fb_assert.c"
want_broken_none "forbidden: ...and a plain printf does not" \
	'rarely one you wrote' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --allowed - --src "$WORK/dirty.c"

