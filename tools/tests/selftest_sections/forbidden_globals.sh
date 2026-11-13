# --------------------------------------------------------- forbidden_globals
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# NO GLOBAL VARIABLE (forbidden_symbols.sh --globals): a variable defined
# outside every function is red whether it is external, static or const, and
# named at its definition -- in the file that names it, a header's once --
# including the ones clang leaves out of an object unless told to keep them
# (a folded static const, an unused static from a header); one inside a
# function body, a string literal and the C library's headers are not
# variables of that kind and stay green, as a stub does.
mkdir -p "$WORK/fng"
printf 'globals\tA sentence for the selftest, standing in for the call site.\n' > "$WORK/fng/q_globals.tsv"
printf 'int\ttoy_stub(const char *s)\n{\n\t(void)s;\n\treturn (0);\n}\n' > "$WORK/fng/stub.c"
printf 'int\ttoy_total = 0;\n\nint\ttoy_get(void)\n{\n\treturn (toy_total);\n}\n' > "$WORK/fng/gl_extern.c"
printf 'static int\ttoy_seen;\n\nint\ttoy_get(void)\n{\n\treturn (toy_seen++);\n}\n' > "$WORK/fng/gl_static.c"
printf 'const int\ttoy_table[3] = {7, 3, 9};\n\nint\ttoy_get(int i)\n{\n\treturn (toy_table[i]);\n}\n' \
	> "$WORK/fng/gl_const.c"
printf 'int\ttoy_get(void)\n{\n\tstatic int\tcount;\n\n\treturn (count++);\n}\n' > "$WORK/fng/gl_local.c"
printf 'const char\t*toy_get(void)\n{\n\treturn ("a literal");\n}\n' > "$WORK/fng/gl_literal.c"
printf 'static const int\ttoy_rtab[3] = {7, 3, 9};\n\nint\ttoy_get(int i)\n{\n\treturn (toy_rtab[i]);\n}\n' \
	> "$WORK/fng/gl_rtab.c"
# What clang leaves out of the object unless told to keep it: a static const
# whose value it folds into the code, a const pointer it reads the same way,
# and a static a header defines that nothing uses.
printf 'static const int\ttoy_base = 10;\n\nint\ttoy_get(int n)\n{\n\treturn (n / toy_base);\n}\n' \
	> "$WORK/fng/gl_folded.c"
printf 'static const char\t*const toy_digits = "0123456789";\n\nchar\ttoy_get(int n)\n{\n\treturn (toy_digits[n %% 10]);\n}\n' \
	> "$WORK/fng/gl_cptr.c"
printf '#include <ctype.h>\n#include <errno.h>\n#include <fcntl.h>\n#include <limits.h>\n#include <stdarg.h>\n#include <stddef.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nint\ttoy_get(void)\n{\n\treturn (0);\n}\n' \
	> "$WORK/fng/gl_libc.c"
mkdir -p "$WORK/fng/hdr"
printf '#ifndef TOY_HDR_H\n# define TOY_HDR_H\n\nstatic int\ttoy_hidden;\nstatic const char\ttoy_hex[] = "0123456789abcdef";\n\n#endif\n' \
	> "$WORK/fng/hdr/toy_hdr.h"
printf '#include "toy_hdr.h"\n\nint\ttoy_one(void)\n{\n\treturn (0);\n}\n' > "$WORK/fng/hdr/one.c"
printf '#include "toy_hdr.h"\n\nint\ttoy_two(void)\n{\n\treturn (1);\n}\n' > "$WORK/fng/hdr/two.c"
printf 'int\ttoy_second_count;\n\nint\ttoy_second(void)\n{\n\treturn (toy_second_count);\n}\n' \
	> "$WORK/fng/gl_second.c"
# A compiler that refuses -femit-all-decls, as gcc does, and is clang: the
# probe then finds the folded and the unused static gone.
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" != -femit-all-decls ] || exit 1; done\nexec "%s" "$@"\n' \
	"$CC" > "$WORK/fng/cc_noemit.sh"
chmod +x "$WORK/fng/cc_noemit.sh"
# The runner in --globals mode, with the pinned nm and the call site's
# sentence: a function taking "$@", as forbidden_functions' fn_call is.
gl_call() {  # gl_call ARG... -- forbidden_symbols.sh --globals, pinned and quoted, then ARG...
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --quotes "$WORK/fng/q_globals.tsv" --globals "$@"
}
want_red   "forbidden --globals: an external variable fails" -- \
	gl_call --src "$WORK/fng/gl_extern.c"
want_out   "forbidden --globals: ...named at its definition" \
	"    toy_total   (at $WORK/fng/gl_extern.c:1;" -- \
	gl_call --src "$WORK/fng/gl_extern.c"
want_out   "forbidden --globals: ...quoting the call site's sentence" \
	'standing in for the call site' -- \
	gl_call --src "$WORK/fng/gl_extern.c"
want_red   "forbidden --globals: a static one outside a function fails" -- \
	gl_call --src "$WORK/fng/gl_static.c"
want_red   "forbidden --globals: a const table outside a function fails" -- \
	gl_call --src "$WORK/fng/gl_const.c"
want_red   "forbidden --globals: a static const table fails" -- \
	gl_call --src "$WORK/fng/gl_rtab.c"
want_red   "forbidden --globals: a static const the code folds fails" -- \
	gl_call --src "$WORK/fng/gl_folded.c"
want_red   "forbidden --globals: a static const pointer fails" -- \
	gl_call --src "$WORK/fng/gl_cptr.c"
want_red   "forbidden --globals: an unused static in a header fails" -- \
	gl_call --src "$WORK/fng/hdr/one.c"
want_out   "forbidden --globals: ...named in the header" \
	"toy_hdr.h:4; static)" -- \
	gl_call --src "$WORK/fng/hdr/one.c"
gl_once() {
	[ "$(gl_call --src "$WORK/fng/hdr/one.c" --src "$WORK/fng/hdr/two.c" 2>&1 |
		grep -c '^    toy_hex   (at ')" = 1 ]
}
want_green "forbidden --globals: ...once, when two sources include it" -- gl_once
want_red   "forbidden --globals: one in the second source fails" -- \
	gl_call --src "$WORK/fng/stub.c" --src "$WORK/fng/gl_second.c"
want_out   "forbidden --globals: ...named in that source" \
	"    toy_second_count   (at $WORK/fng/gl_second.c:1;" -- \
	gl_call --src "$WORK/fng/stub.c" --src "$WORK/fng/gl_second.c"
want_green "forbidden --globals: a static inside a function passes" -- \
	gl_call --src "$WORK/fng/gl_local.c"
want_green "forbidden --globals: a string literal passes" -- \
	gl_call --src "$WORK/fng/gl_literal.c"
want_green "forbidden --globals: the C library's headers define none" -- \
	gl_call --src "$WORK/fng/gl_libc.c"
want_green "forbidden --globals: a stub passes" -- \
	gl_call --src "$WORK/fng/stub.c"
want_broken "forbidden --globals: no quote is a broken harness" \
	'--quotes FILE is required' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --globals --src "$WORK/fng/gl_extern.c"
want_broken "forbidden --globals: one mode per run" \
	'two checks' -- \
	gl_call --function toy_get= --src "$WORK/fng/gl_extern.c"
want_broken "forbidden --globals: --through is --function's" \
	'--through reads' -- \
	gl_call --through --src "$WORK/fng/gl_extern.c"
want_broken "forbidden --globals: a compile that drops a static is refused" \
	'leaves out of its object' -- \
	env FORBIDDEN_CC="$WORK/fng/cc_noemit.sh" "$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" \
		--quotes "$WORK/fng/q_globals.tsv" --globals --src "$WORK/fng/stub.c"
# symbols_test.sh --functions-only leaves a variable to --globals, so its
# "make it static" advice is given for functions alone.
want_red   "symbols: an exported variable is reported without the flag" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect toy_get --src "$WORK/fng/gl_extern.c"
want_green "symbols --functions-only: ...and not with it" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect toy_get --functions-only \
		--src "$WORK/fng/gl_extern.c"
want_red   "symbols --functions-only: an exported helper still fails" -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$NM_LIB" --expect ft_x --functions-only --src "$WORK/leaky.c"

