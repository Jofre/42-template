# ------------------------------------------------- prototype_check no-restrict
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# --no-restrict: the restrict qualifier in a prototype of a turned-in file
# (each --src, each --hdr), read from the pinned clang's AST. The types mode
# cannot see it -- a qualifier on a parameter is no part of the function's
# type -- which the first arms pin. Every tree is an invented toy (toy_copy,
# toy_each, toy_x), never a function any subject asks for; the stub is a
# signature, (void) casts and a trivial return, under a header that declares
# nothing, and every quote is the call site's (--quotes).
mkdir -p "$WORK/nr/stub" "$WORK/nr/cdef" "$WORK/nr/hdr" "$WORK/nr/dunder" "$WORK/nr/fp" \
	"$WORK/nr/libc" "$WORK/nr/local" "$WORK/nr/ret" "$WORK/nr/td" "$WORK/nr/lone" \
	"$WORK/nr/broken"
printf 'restrict\tToy, p.1: "No prototype of yours may use the toy qualifier."\n' > "$WORK/nr/q.tsv"
nr_h() {  # nr_h DIR DECLS: DIR/toy.h, guarded, <stddef.h>, then DECLS
	printf '#ifndef TOY_H\n# define TOY_H\n# include <stddef.h>\n%b#endif\n' "$2" > "$WORK/nr/$1/toy.h"
}
nr_c() {  # nr_c DIR PARAMS [DECL]: DIR/toy_copy.c, a stub body; DECL a local variable
	printf '#include <stddef.h>\n#include "toy.h"\n\nvoid\t*toy_copy(%s)\n{\n%b\t(void)s;\n\t(void)n;\n\treturn (d);\n}\n' \
		"$2" "${3:-}" > "$WORK/nr/$1/toy_copy.c"
}
_nr_plain='void *d, const void *s, size_t n'
nr_h stub ''
nr_c stub "$_nr_plain"
nr_h cdef "void\t*toy_copy($_nr_plain);\n"
nr_c cdef 'void *restrict d, const void *s, size_t n'
nr_h hdr 'void\t*toy_copy(void *d,\n\t\tconst void *restrict s, size_t n);\n'
nr_c hdr "$_nr_plain"
nr_h dunder 'void\t*toy_copy(void *__restrict d, const void *s, size_t n);\n'
nr_c dunder 'void *d, const void *__restrict__ s, size_t n'
nr_h fp 'void\ttoy_each(char *s, void (*f)(char *restrict c));\n'
printf '#include "toy.h"\n\nvoid\ttoy_each(char *s, void (*f)(char *c))\n{\n\t(void)s;\n\t(void)f;\n}\n' \
	> "$WORK/nr/fp/toy_each.c"
nr_h libc "void\t*toy_copy($_nr_plain);\n"
printf '#include <string.h>\n#include <stdio.h>\n#include "toy.h"\n\nvoid\t*toy_copy(void *d, const void *s, size_t n)\n{\n\t(void)s;\n\t(void)n;\n\treturn (d);\n}\n' \
	> "$WORK/nr/libc/toy_copy.c"
nr_h local "void\t*toy_copy($_nr_plain);\n"
nr_c local "$_nr_plain" '\tchar\t*restrict\tp;\n\n\tp = d;\n\t(void)p;\n'
nr_h ret 'char\t*restrict\ttoy_ret(int n);\n'
printf '#include "toy.h"\n\nchar\t*restrict\ttoy_ret(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' \
	> "$WORK/nr/ret/toy_ret.c"
# Behind a typedef, inside a function pointer, where no type clang prints
# for the parameter spells restrict out.
nr_h td 'typedef char\t*restrict\tt_rp;\nvoid\ttoy_x(void (*f)(t_rp));\n'
printf '#include "toy.h"\n\nvoid\ttoy_x(void (*f)(char *))\n{\n\t(void)f;\n}\n' > "$WORK/nr/td/toy_x.c"
nr_h lone 'void\ttoy_x(char *restrict p);\n'
printf 'void\ttoy_y(void)\n{\n}\n' > "$WORK/nr/lone/toy_y.c"
nr_h broken ''
printf '#include "toy.h"\n\nvoid\ttoy_y(void)\n{\n\treturn (1)\n}\n' > "$WORK/nr/broken/toy_y.c"
# A path made absolute: $TOOLS, $SH, $CLANG and each --cc-lib may be
# relative to the runfiles root, and some arms run from another folder.
_nr_abs() { case $1 in /*) printf '%s' "$1" ;; */*) printf '%s/%s' "$PWD" "$1" ;; *) printf '%s' "$1" ;; esac; }
# The contract: the toy functions every tree reimplements, by name. Only
# the names are read (the functions it declares itself), so its types need
# not be any tree's.
printf '#include <stddef.h>\nvoid\t*toy_copy(void *d, const void *s, size_t n);\nvoid\ttoy_each(char *s, void (*f)(char *));\nchar\t*toy_ret(int n);\nvoid\ttoy_x(void (*f)(char *));\nint\t\ttoy_ok(char *p);\nsize_t\ttoy_len(const char *s);\nvoid\ttoy_end(char *p);\n' \
	> "$WORK/nr/proto.h"
_nr_run() {  # _nr_run MODE DIR [SRC]: MODE proto (the contract's functions) or all
	_nd=$2
	_ns=${3:-toy_copy.c}
	if [ "$1" = all ]; then set -- --all-functions; else set -- --proto "$WORK/nr/proto.h"; fi
	# shellcheck disable=SC2086
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --no-restrict "$@" \
		--quotes "$WORK/nr/q.tsv" --src "$WORK/nr/$_nd/$_ns" --hdr "$WORK/nr/$_nd/toy.h"
}
nr() {  # nr DIR [SRC]: the runner on one toy tree, its source and its header
	_nr_run proto "$@"
}
nr_all() {  # nr_all DIR [SRC]: the same, every function judged (--all-functions)
	_nr_run all "$@"
}
want_green "prototype: the types mode lets restrict through (why this mode is)" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS \
		--proto "$WORK/nr/cdef/toy.h" --src "$WORK/nr/cdef/toy_copy.c"
want_broken "prototype: the types mode refuses a --quotes it would never read" \
	"belong to --no-restrict and --declares" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --quotes "$WORK/nr/q.tsv" \
		--proto "$WORK/nr/cdef/toy.h" --src "$WORK/nr/cdef/toy_copy.c"
want_green "prototype: --no-restrict passes a stub" -- nr stub
want_red   "prototype: --no-restrict fails restrict in a .c definition" -- nr cdef
want_out   "prototype: ...naming the file:line, the function and the parameter" \
	"toy_copy.c:4: toy_copy(), parameter 1 (d): 'void *restrict'" -- nr cdef
want_out   "prototype: ...and quoting the call site's sentence" \
	'Toy, p.1: "No prototype of yours may use the toy qualifier."' -- nr cdef
want_red   "prototype: --no-restrict fails restrict only in the header" -- nr hdr
want_out   "prototype: ...named at the header's line, the parameter's own" \
	"toy.h:5: toy_copy(), parameter 2 (s)" -- nr hdr
want_broken_none "prototype: ...never at the .c, which writes none" \
	"toy_copy.c:" -- nr hdr
want_out   "prototype: --no-restrict fails __restrict and __restrict__ alike" \
	"toy_copy.c:4: toy_copy(), parameter 2 (s)" -- nr dunder
want_out   "prototype: ...both of them" "toy.h:4: toy_copy(), parameter 1 (d)" -- nr dunder
want_out   "prototype: --no-restrict fails it inside a function-pointer parameter" \
	"toy.h:4: toy_each(), parameter 2 (f): 'void (*)(char *restrict)'" -- nr fp toy_each.c
want_broken_none "prototype: ...and not at the .c that redeclares it without" \
	"toy_each.c:" -- nr fp toy_each.c
want_out   "prototype: --no-restrict fails it on the return type" \
	"toy.h:4: toy_ret(), its return type" -- nr ret toy_ret.c
want_out   "prototype: --no-restrict fails it through a typedef" \
	"toy.h:5: toy_x(), parameter 1 (f): 'void (*)(t_rp)'" -- nr td toy_x.c
want_green "prototype: --no-restrict passes libc's own restrict prototypes" -- nr libc
# ...and leaves them out of the count of what it did not judge: no function
# of the contract's is libc's, and a green log that said restrict appeared in
# 80 places named nothing a student could act on.
want_broken_none "prototype: ...and counts none of them as not judged" "not judged here" -- nr libc
want_green "prototype: --no-restrict passes a local variable declared restrict" -- nr local
want_out   "prototype: --no-restrict reads a header no source includes" \
	"toy.h:4: toy_x(), parameter 1 (p)" -- nr lone toy_y.c
want_red   "prototype: --no-restrict fails a source that does not compile" -- nr broken toy_y.c
# A prototype that begins with a macro -- bool, from <stdbool.h> -- has its
# range begin where the macro is defined; the declaration is still the
# student's, named at its own line (it was passed as the system's).
mkdir -p "$WORK/nr/bool" "$WORK/nr/mac" "$WORK/nr/impl" "$WORK/nr/other" "$WORK/nr/lonebad" \
	"$WORK/nr/sp/inc" "$WORK/nr/sp/src"
nr_h bool '# include <stdbool.h>\n\nbool\ttoy_ok(char *restrict p);\n'
printf '#include "toy.h"\n\nbool\ttoy_ok(char *restrict p)\n{\n\t(void)p;\n\treturn (0);\n}\n' \
	> "$WORK/nr/bool/toy_ok.c"
want_out   "prototype: --no-restrict fails a prototype that begins with bool" \
	"toy.h:6: toy_ok(), parameter 1 (p)" -- nr bool toy_ok.c
want_out   "prototype: ...and its definition, at its own line" \
	"toy_ok.c:3: toy_ok(), parameter 1 (p)" -- nr bool toy_ok.c
# A type macro of the student's own: the line named is the prototype's,
# never the #define's.
nr_h mac '# define T_STR char *\n\nint\ttoy_ok(T_STR restrict p);\n'
printf '#include "toy.h"\n\nint\ttoy_ok(char *p)\n{\n\t(void)p;\n\treturn (0);\n}\n' \
	> "$WORK/nr/mac/toy_ok.c"
want_out   "prototype: --no-restrict names a macro-typed prototype at its line" \
	"toy.h:6: toy_ok(), parameter 1 (p)" -- nr mac toy_ok.c
# A call with no #include makes clang declare the function itself
# (implicit, at the call): not a prototype anyone wrote. The compile layer
# reports the missing include.
nr_h impl 'int\ttoy_ok(char *p);\n'
printf '#include "toy.h"\n\nint\ttoy_ok(char *p)\n{\n\tint\tn;\n\n\tsscanf(p, "%%d", &n);\n\treturn (n);\n}\n' \
	> "$WORK/nr/impl/toy_ok.c"
want_green "prototype: --no-restrict passes a declaration clang made at a call" -- nr_all impl toy_ok.c
want_broken_none "prototype: ...and never names it" "sscanf" -- nr_all impl toy_ok.c
# One restrict prototype of a contract function in a header the call site
# did not name: counted, in the singular, and not called the system's.
nr_h other "void\t*toy_copy($_nr_plain);\n"
printf '#ifndef OTHER_H\n# define OTHER_H\n\nvoid\ttoy_end(char *restrict p);\n#endif\n' > "$WORK/nr/other/other.h"
printf '#include <stddef.h>\n#include "toy.h"\n#include "other.h"\n\nvoid\t*toy_copy(void *d, const void *s, size_t n)\n{\n\t(void)s;\n\t(void)n;\n\treturn (d);\n}\n' \
	> "$WORK/nr/other/toy_copy.c"
want_green "prototype: --no-restrict passes a file the call site does not name" -- nr other
want_out   "prototype: ...counting it, in the singular" \
	"restrict appears in 1 place in a prototype of a file that is not turned in" -- nr other
want_broken_none "prototype: ...without calling it the system's" "the system's" -- nr other
# The same header declaring a function the contract does not: not counted,
# as no function of the contract's is a system header's either.
mkdir -p "$WORK/nr/othernc"
cp "$WORK/nr/other/toy.h" "$WORK/nr/other/toy_copy.c" "$WORK/nr/othernc/"
printf '#ifndef OTHER_H\n# define OTHER_H\n\nvoid\ttoy_o(char *restrict p);\n#endif\n' > "$WORK/nr/othernc/other.h"
want_green "prototype: --no-restrict passes a non-contract function elsewhere" -- nr othernc
want_broken_none "prototype: ...and does not count it" "not judged here" -- nr othernc
# A header that does not compile, included by a source that does not either:
# the source's red, and the header read on its own all the same.
nr_h lonebad 't_nope\t*toy_x(char *restrict p);\n'
printf '#include "toy.h"\n\nvoid\ttoy_y(void)\n{\n}\n' > "$WORK/nr/lonebad/toy_y.c"
want_out   "prototype: --no-restrict reads a header that compiles nowhere" \
	"toy.h:4: toy_x(), parameter 1 (p)" -- nr lonebad toy_y.c
# A header that is not self-contained (size_t, no include), which no source
# includes: clang dumps its declarations all the same, and they are judged
# -- restrict or not -- not called unreadable.
mkdir -p "$WORK/nr/tlh" "$WORK/nr/tlhok"
printf '#ifndef TOY_H\n# define TOY_H\n\nsize_t\ttoy_len(const char *restrict s);\n#endif\n' \
	> "$WORK/nr/tlh/toy.h"
printf '#ifndef TOY_H\n# define TOY_H\n\nsize_t\ttoy_len(const char *s);\n#endif\n' \
	> "$WORK/nr/tlhok/toy.h"
printf '#include <stddef.h>\n\nvoid\ttoy_y(void)\n{\n}\n' > "$WORK/nr/tlh/toy_y.c"
cp "$WORK/nr/tlh/toy_y.c" "$WORK/nr/tlhok/toy_y.c"
want_out   "prototype: --no-restrict reads a header that needs an include" \
	"toy.h:4: toy_len(), parameter 1 (s)" -- nr tlh toy_y.c
want_green "prototype: ...and passes it with none" -- nr tlhok toy_y.c
# A dump with no translation unit in it, from a compiler that dumps one of
# an empty file and nothing of a header read on its own: unreadable, a red.
printf '#!/bin/sh\nfor a in "$@"; do case $a in */main.c) echo "toy: no dump" >&2; exit 1 ;; esac; done\nexec "%s" "$@"\n' \
	"$(_nr_abs "$CLANG")" > "$WORK/nr/nodump_cc"
chmod +x "$WORK/nr/nodump_cc"
nr_nodump() {  # nr_nodump: the lone tree, through that compiler
	# shellcheck disable=SC2086
	"$SH" "$TOOLS/prototype_check.sh" --cc "$WORK/nr/nodump_cc" $CLANG_LIBS --no-restrict \
		--proto "$WORK/nr/proto.h" --quotes "$WORK/nr/q.tsv" \
		--src "$WORK/nr/lone/toy_y.c" --hdr "$WORK/nr/lone/toy.h"
}
want_red   "prototype: --no-restrict fails a header it cannot read" -- nr_nodump
want_out   "prototype: ...saying so" "toy.h cannot be read" -- nr_nodump
# Relative paths, spelled two ways: the source reaches the header as
# ../inc/toy.h, the call site names it inc/toy.h. One file all the same.
printf '#ifndef TOY_H\n# define TOY_H\n# include <stddef.h>\nvoid\t*toy_copy(void *restrict d, const void *s, size_t n);\n#endif\n' \
	> "$WORK/nr/sp/inc/toy.h"
printf '#include "../inc/toy.h"\n\nvoid\t*toy_copy(void *d, const void *s, size_t n)\n{\n\t(void)s;\n\t(void)n;\n\treturn (d);\n}\n' \
	> "$WORK/nr/sp/src/toy_copy.c"
# $TOOLS, $SH, $CLANG and each --cc-lib may be relative to the runfiles
# root, so they are made absolute before the cd.
_nr_tools=$(cd "$TOOLS" && pwd)
_nr_sh=$(_nr_abs "$SH")
_nr_cc=$(_nr_abs "$CLANG")
_nr_libs=""
# shellcheck disable=SC2086
for _w in $CLANG_LIBS; do
	[ "$_w" = --cc-lib ] && continue
	_nr_libs="$_nr_libs --cc-lib $(_nr_abs "$_w")"
done
nr_rel() {  # nr_rel: the runner from inside the sp tree, every path relative
	# shellcheck disable=SC2086
	(cd "$WORK/nr/sp" && "$_nr_sh" "$_nr_tools/prototype_check.sh" --cc "$_nr_cc" $_nr_libs \
		--no-restrict --proto "$WORK/nr/proto.h" --quotes "$WORK/nr/q.tsv" \
		--src src/toy_copy.c --hdr inc/toy.h)
}
want_out   "prototype: --no-restrict knows a header by identity, not spelling" \
	"toy.h:4: toy_copy(), parameter 1 (d)" -- nr_rel
# One header, two sources that include it: each finding once, and counted
# once, however many sources read it.
mkdir -p "$WORK/nr/two"
cp "$WORK/nr/hdr/toy.h" "$WORK/nr/hdr/toy_copy.c" "$WORK/nr/two/"
printf '#include "toy.h"\n\nsize_t\ttoy_len(const char *s)\n{\n\t(void)s;\n\treturn (0);\n}\n' \
	> "$WORK/nr/two/toy_len.c"
nr_two() {  # nr_two: the two-source tree
	# shellcheck disable=SC2086
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --no-restrict \
		--proto "$WORK/nr/proto.h" --quotes "$WORK/nr/q.tsv" --src "$WORK/nr/two/toy_copy.c" \
		--src "$WORK/nr/two/toy_len.c" --hdr "$WORK/nr/two/toy.h"
}
want_out   "prototype: --no-restrict reports a header read twice once" \
	"restrict appears in 1 place in your prototypes" -- nr_two
# restrict on the return type and on a parameter of one function: both
# lines, the return type's no longer hidden by the parameter's. And an
# attribute clang prints after the parameter list is not the list: a
# restrict parameter there is never called the return type's.
mkdir -p "$WORK/nr/rp" "$WORK/nr/attr"
nr_h rp 'char\t*restrict\ttoy_ret(char *restrict p);\n'
printf '#include "toy.h"\n\nchar\t*restrict\ttoy_ret(char *restrict p)\n{\n\treturn (p);\n}\n' \
	> "$WORK/nr/rp/toy_ret.c"
want_out   "prototype: --no-restrict fails the return type beside a parameter" \
	"toy.h:4: toy_ret(), its return type" -- nr rp toy_ret.c
want_out   "prototype: ...and the parameter" "toy.h:4: toy_ret(), parameter 1 (p)" -- nr rp toy_ret.c
nr_h attr 'void\ttoy_end(char *restrict p) __attribute__((noreturn));\n'
printf '#include <stdlib.h>\n#include "toy.h"\n\nvoid\ttoy_end(char *p)\n{\n\t(void)p;\n\texit(0);\n}\n' \
	> "$WORK/nr/attr/toy_end.c"
want_out   "prototype: --no-restrict reads a function with a trailing attribute" \
	"toy.h:4: toy_end(), parameter 1 (p)" -- nr attr toy_end.c
want_broken_none "prototype: ...and never calls it the return type's" \
	"its return type" -- nr attr toy_end.c
# A function declared through a function typedef has its type printed
# sugared, 't_fn':'void (char *restrict)': the restrict is its parameter's,
# never its return type's.
mkdir -p "$WORK/nr/sug"
nr_h sug 'typedef void\tt_fn(char *restrict c);\nt_fn\t\ttoy_k;\n'
printf '#include "toy.h"\n\nvoid\ttoy_y(void)\n{\n}\n' > "$WORK/nr/sug/toy_y.c"
want_out   "prototype: --no-restrict reads a function declared through a typedef" \
	"toy.h:5: toy_k(), parameter 1" -- nr_all sug toy_y.c
want_broken_none "prototype: ...and never calls it the return type's" \
	"its return type" -- nr_all sug toy_y.c
# A folder whose name holds a space: every list (sources, include folders)
# is one word per line, the contract's own compile too.
mkdir -p "$WORK/nr/sp ace"
nr_h "sp ace" "void\t*toy_copy(void *restrict d, const void *s, size_t n);\n"
nr_c "sp ace" "$_nr_plain"
want_out   "prototype: --no-restrict reads a folder whose name holds a space" \
	"toy.h:4: toy_copy(), parameter 1 (d)" -- nr "sp ace"
# A header that swallows every declaration after it -- an unclosed brace
# -- read by the contract too, which then declares nothing: the student's
# red, whether a source includes the header or none does, never exit 2.
mkdir -p "$WORK/nr/brace"
nr_h brace "typedef struct s_toy\n{\n\tint\ta;\n\nvoid\t*toy_copy($_nr_plain);\n"
nr_c brace "$_nr_plain"
printf '#include "toy.h"\n' > "$WORK/nr/brace/proto.h"
printf 'void\t*toy_copy(void *d, const void *s, size_t n);\n' >> "$WORK/nr/brace/proto.h"
nr_brace() {  # nr_brace [--src]: the brace tree against its own contract
	if [ "${1:-}" = --src ]; then set -- --src "$WORK/nr/brace/toy_copy.c"; fi
	# shellcheck disable=SC2086
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --no-restrict \
		--proto "$WORK/nr/brace/proto.h" --quotes "$WORK/nr/q.tsv" "$@" \
		--hdr "$WORK/nr/brace/toy.h"
}
want_red   "prototype: --no-restrict fails a header that swallows the contract" -- nr_brace --src
want_out   "prototype: ...saying nothing of it could be read" \
	"no function proto.h declares could be read" -- nr_brace --src
want_red   "prototype: ...and when no source includes it" -- nr_brace
# A contract that declares nothing while every turned-in file compiles is
# the harness's fault, not the exercise's: exit 2.
printf '#include <stddef.h>\n' > "$WORK/nr/empty_proto.h"
want_broken "prototype: --no-restrict on a contract that declares nothing refuses" \
	"nothing to look for" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --no-restrict \
		--proto "$WORK/nr/empty_proto.h" --quotes "$WORK/nr/q.tsv" \
		--src "$WORK/nr/stub/toy_copy.c" --hdr "$WORK/nr/stub/toy.h"
# Whose prototypes: by default the functions --proto declares, which every
# reading agrees on; a static helper of the student's own is judged only
# under --all-functions, a reading of its own (a strict target's).
mkdir -p "$WORK/nr/help"
nr_h help "void\t*toy_copy($_nr_plain);\n"
printf '#include "toy.h"\n\nstatic void\ttoy_help(char *restrict p)\n{\n\t(void)p;\n}\n\nvoid\t*toy_copy(void *d, const void *s, size_t n)\n{\n\ttoy_help(d);\n\t(void)s;\n\t(void)n;\n\treturn (d);\n}\n' \
	> "$WORK/nr/help/toy_copy.c"
want_green "prototype: --no-restrict passes a restrict helper the contract lacks" -- nr help
want_out   "prototype: ...saying it judged the contract's functions" \
	"no prototype of a function proto.h declares uses" -- nr help
want_broken_none "prototype: ...never that no prototype uses it" \
	"no prototype in the turned-in files uses restrict" -- nr help
want_out   "prototype: --all-functions' OK line speaks of every prototype" \
	"no prototype in the turned-in files uses restrict" -- nr_all stub
want_red   "prototype: --all-functions fails it" -- nr_all help
want_out   "prototype: ...naming it" "toy_copy.c:3: toy_help(), parameter 1 (p)" -- nr_all help
want_out   "prototype: ...as this harness's reading" "is this harness's reading" -- nr_all help
want_broken_none "prototype: ...which the default never says" "harness's reading" -- nr cdef
want_red   "prototype: --all-functions fails a contract function too" -- nr_all cdef
want_broken "prototype: --no-restrict with no --proto nor --all-functions refuses" \
	"judges the functions --proto declares" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --no-restrict \
		--quotes "$WORK/nr/q.tsv" --src "$WORK/nr/cdef/toy_copy.c"
want_broken "prototype: --all-functions with a --proto it would not read refuses" \
	"reads no --proto" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --no-restrict --all-functions \
		--proto "$WORK/nr/proto.h" --quotes "$WORK/nr/q.tsv" --src "$WORK/nr/cdef/toy_copy.c"
want_broken "prototype: --all-functions outside --no-restrict refuses" \
	"belongs to --no-restrict" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --all-functions \
		--proto "$WORK/nr/cdef/toy.h" --src "$WORK/nr/cdef/toy_copy.c"
# The findings in byte order, whatever the caller's locale: a_toy.h after
# B_toy.c, where en_US would put it first. A host with no en_US locale runs
# sort in C all the same, and this arm cannot fail there.
mkdir -p "$WORK/nr/loc"
printf '#ifndef A_TOY_H\n# define A_TOY_H\n\nvoid\ttoy_x(char *restrict p);\n#endif\n' > "$WORK/nr/loc/a_toy.h"
printf '#include "a_toy.h"\n\nvoid\ttoy_x(char *restrict p)\n{\n\t(void)p;\n}\n' > "$WORK/nr/loc/B_toy.c"
nr_loc() {  # nr_loc: exit 0 if B_toy.c's finding comes first under en_US
	# shellcheck disable=SC2086
	LC_ALL=en_US.UTF-8 "$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --no-restrict \
		--all-functions --quotes "$WORK/nr/q.tsv" --src "$WORK/nr/loc/B_toy.c" \
		--hdr "$WORK/nr/loc/a_toy.h" 2>&1 |
		awk '/  B_toy\.c:/ { b = NR } /  a_toy\.h:/ { a = NR } END { exit !(b && a && b < a) }'
}
want_green "prototype: --no-restrict orders its findings in bytes, not the locale" -- nr_loc
want_broken "prototype: --no-restrict with no --quotes refuses" \
	"--quotes FILE is required" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --no-restrict \
		--all-functions --src "$WORK/nr/cdef/toy_copy.c"
want_broken "prototype: --no-restrict on a compiler with no AST dump refuses" \
	"could not dump the AST" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc "$GCC" --no-restrict --all-functions \
		--quotes "$WORK/nr/q.tsv" --src "$WORK/nr/cdef/toy_copy.c"
want_broken "prototype: --no-restrict with no compiler refuses" \
	"is not executable" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc /nonexistent/clang --no-restrict --all-functions \
		--quotes "$WORK/nr/q.tsv" --src "$WORK/nr/cdef/toy_copy.c"

# --declares: a program that includes only the student's header finds every
# function the --proto file itself declares (a reading, at strict). The
# contract includes the student's header for a type, as a project's
# prototype.h may; what that header declares is not the contract's.
mkdir -p "$WORK/dc/proto" "$WORK/dc/all" "$WORK/dc/one" "$WORK/dc/none" "$WORK/dc/conly"
printf 'declares\tToy, p.1: "Files to turn in: toy.h, toy_*.c"\n' > "$WORK/dc/q.tsv"
printf '#ifndef PROTO_TOY_H\n# define PROTO_TOY_H\n# include "toy.h"\nvoid\t*toy_copy(void *d, const void *s, size_t n);\nint\t\ttoy_len(const char *s);\nt_toy\t*toy_new(int a);\n#endif\n' \
	> "$WORK/dc/proto/prototype.h"
dc_h() {  # dc_h DIR DECLS: DIR/toy.h with the type the contract uses, then DECLS
	printf '#ifndef TOY_H\n# define TOY_H\n# include <stddef.h>\n\ntypedef struct s_toy\n{\n\tint\ta;\n}\tt_toy;\n%b#endif\n' \
		"$2" > "$WORK/dc/$1/toy.h"
}
dc_h all 'void\t*toy_copy(void *d, const void *s, size_t n);\nint\t\ttoy_len(const char *s);\nt_toy\t*toy_new(int a);\nint\t\ttoy_extra(void);\n'
dc_h one 'void\t*toy_copy(void *d, const void *s, size_t n);\nt_toy\t*toy_new(int a);\n'
dc_h none ''
dc_h conly ''
printf '#include "toy.h"\n\nint\ttoy_len(const char *s)\n{\n\t(void)s;\n\treturn (0);\n}\n' \
	> "$WORK/dc/conly/toy_len.c"
dc() {  # dc DIR [ARGS...]: the runner on one toy header
	_dd=$1
	shift
	# shellcheck disable=SC2086
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --declares \
		--quotes "$WORK/dc/q.tsv" --proto "$WORK/dc/proto/prototype.h" \
		--hdr "$WORK/dc/$_dd/toy.h" "$@"
}
want_green "prototype: --declares passes a header that declares them all" -- dc all
want_out   "prototype: ...counting the contract's own, not the header's extra" \
	"declares all 3 functions" -- dc all
want_red   "prototype: --declares fails a header missing one" -- dc one
want_out   "prototype: ...naming it" "    toy_len" -- dc one
want_broken_none "prototype: ...and only it" "toy_new" -- dc one
want_out   "prototype: --declares lists all three of a header declaring none" \
	"leaves 3 of" -- dc none
want_out   "prototype: ...each by name" "    toy_new" -- dc none
want_red   "prototype: --declares fails a function declared only in its .c" -- \
	dc conly --src "$WORK/dc/conly/toy_len.c"
want_out   "prototype: ...naming the reading as this harness's" \
	"is this harness's reading" -- dc conly --src "$WORK/dc/conly/toy_len.c"
want_broken "prototype: --declares with no --quotes refuses" \
	"--quotes FILE is required" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --declares \
		--proto "$WORK/dc/proto/prototype.h" --hdr "$WORK/dc/all/toy.h"
# Presence only: a header declaring every function, one with another type,
# is the types mode's red and not this one's.
mkdir -p "$WORK/dc/conf" "$WORK/dc/bad" "$WORK/dc/bproto" "$WORK/dc/bmiss" "$WORK/dc/ball"
dc_h conf 'void\t*toy_copy(void *d, const void *s, size_t n);\nint\t\ttoy_len(char *s);\nt_toy\t*toy_new(int a);\n'
printf '#include "toy.h"\n\nint\ttoy_len(char *s)\n{\n\t(void)s;\n\treturn (0);\n}\n' \
	> "$WORK/dc/conf/toy_len.c"
want_green "prototype: --declares passes a declaration of another type" -- dc conf
want_out   "prototype: ...counting it as declared" "declares all 3 functions" -- dc conf
want_red   "prototype: ...which the types mode fails" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS \
		--proto "$WORK/dc/proto/prototype.h" --src "$WORK/dc/conf/toy_len.c"
# A contract function whose return type is a macro (bool): its range begins
# in <stdbool.h>, and it is the contract's all the same.
printf '#ifndef PROTO_TOY_H\n# define PROTO_TOY_H\n# include <stdbool.h>\n# include "toy.h"\nint\t\ttoy_len(const char *s);\nbool\ttoy_ok(int c);\n#endif\n' \
	> "$WORK/dc/bproto/prototype.h"
dc_h bmiss 'int\t\ttoy_len(const char *s);\n'
dc_h ball '# include <stdbool.h>\nint\t\ttoy_len(const char *s);\nbool\ttoy_ok(int c);\n'
dc_b() {  # dc_b DIR: the runner on one toy header, against the bool contract
	# shellcheck disable=SC2086
	"$SH" "$TOOLS/prototype_check.sh" --cc "$CLANG" $CLANG_LIBS --declares \
		--quotes "$WORK/dc/q.tsv" --proto "$WORK/dc/bproto/prototype.h" --hdr "$WORK/dc/$1/toy.h"
}
want_out   "prototype: --declares counts a contract function returning bool" \
	"declares all 2 functions" -- dc_b ball
want_red   "prototype: --declares fails a header missing a bool one" -- dc_b bmiss
want_out   "prototype: ...naming it" "    toy_ok" -- dc_b bmiss
# A header that does not compile alone, for any reason: the question fits
# any error, not only a missing include.
printf '#ifndef TOY_H\n# define TOY_H\nint\t\ttoy_len(const char *s)\n#endif\n' > "$WORK/dc/bad/toy.h"
want_red   "prototype: --declares fails a header that does not compile alone" -- dc bad
want_out   "prototype: ...asking a question any error fits" \
	"What does the first error above point at?" -- dc bad
# clang places that error at the end of the file that includes the header:
# main.c, by that name alone, its one line as it is -- no path in it, so
# the caret under it points where the error is.
want_out   "prototype: ...naming the including file main.c" "  main.c:1:" -- dc bad
want_out   "prototype: ...showing its line, with no path in it" '  #include "toy.h"' -- dc bad
want_broken_none "prototype: ...never by the runner's folder" "/main.c" -- dc bad
want_broken_none "prototype: ...nor by the runner's old name" "alone.c" -- dc bad
# The usual case: a header that needs an include it does not make, which
# its own sources make first. The red is a reading, quotes the call site,
# and shows the header by the name the call gave it -- never the runner's
# file of one line, nor the folder's physical path.
mkdir -p "$WORK/dc/tn"
printf '#ifndef TOY_H\n# define TOY_H\n\nsize_t\ttoy_len(const char *s);\n#endif\n' > "$WORK/dc/tn/toy.h"
dc_rel() {  # dc_rel: the tn tree, from the dc folder, the header named tn/toy.h
	# shellcheck disable=SC2086
	(cd "$WORK/dc" && "$_nr_sh" "$_nr_tools/prototype_check.sh" --cc "$_nr_cc" $_nr_libs \
		--declares --quotes "$WORK/dc/q.tsv" --proto "$WORK/dc/proto/prototype.h" --hdr tn/toy.h)
}
want_red   "prototype: --declares fails a header missing an include" -- dc_rel
want_out   "prototype: ...as this harness's reading" "is this harness's" -- dc_rel
want_out   "prototype: ...quoting the call site's sentence" \
	'Toy, p.1: "Files to turn in: toy.h, toy_*.c"' -- dc_rel
want_out   "prototype: ...naming the header as the call did" "  tn/toy.h:4:1: error" -- dc_rel
want_broken_none "prototype: ...never by its physical folder" "/dc/tn/toy.h" -- dc_rel
want_broken_none "prototype: ...nor by the runner's own file" "alone.c" -- dc_rel
# The same header with its folder named before by its absolute path (an
# --inc of the call's): clang spells the header by that path, which the
# runner turns back into the name the call gave.
dc_abs() {  # dc_abs: as dc_rel, its folder on --inc by its absolute path first
	# shellcheck disable=SC2086
	(cd "$WORK/dc" && "$_nr_sh" "$_nr_tools/prototype_check.sh" --cc "$_nr_cc" $_nr_libs \
		--declares --quotes "$WORK/dc/q.tsv" --proto "$WORK/dc/proto/prototype.h" \
		--inc "$WORK/dc/tn" --hdr tn/toy.h)
}
want_out   "prototype: ...named so when its folder is on --inc by its absolute path" "  tn/toy.h:4:1: error" -- dc_abs
want_broken_none "prototype: ...never by that path" "/dc/tn/toy.h" -- dc_abs
mkdir -p "$WORK/dc/sp ace"
dc_h "sp ace" 'void\t*toy_copy(void *d, const void *s, size_t n);\nint\t\ttoy_len(const char *s);\nt_toy\t*toy_new(int a);\n'
want_green "prototype: --declares reads a folder whose name holds a space" -- dc "sp ace"
want_broken "prototype: --declares on a compiler with no AST dump refuses" \
	"could not dump the AST" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc "$GCC" --declares --quotes "$WORK/dc/q.tsv" \
		--proto "$WORK/dc/proto/prototype.h" --hdr "$WORK/dc/all/toy.h"
want_broken "prototype: --declares with no compiler refuses" \
	"is not executable" -- \
	"$SH" "$TOOLS/prototype_check.sh" --cc /nonexistent/clang --declares --quotes "$WORK/dc/q.tsv" \
		--proto "$WORK/dc/proto/prototype.h" --hdr "$WORK/dc/all/toy.h"

