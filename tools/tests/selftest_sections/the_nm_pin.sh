# ------------------------------------------------------------- the nm pin
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The three runners that read symbols take a SUPPLIED nm and have no PATH
# fallback, and that is the whole value of the pin -- so it needs an arm, because
# a fallback is exactly the kind of thing someone adds back "to make it work on
# my machine" and nothing else would notice.
#
# The campus audit is why it is not hypothetical: nm there resolved to a
# student's own Homebrew binutils 2.46.1, shadowing the system 2.38 the
# Moulinette uses, so these layers were reading a different tool than the grader.
#
# Exit 2, not 1: a missing nm means nothing was checked, which is a broken
# harness rather than a wrong deliverable -- hence the explicit status test
# instead of want_red.
# Each runner gets a COMPLETE argument list with only --nm missing, and the
# assertion is on the SENTENCE, not merely on the status.
#
# The earlier version invoked each one with no arguments at all and accepted any
# exit 2. Every runner here exits 2 for a dozen reasons -- a missing --expect, a
# missing --src, an unknown option -- so the arm passed on whichever check
# happened to fire first, and a re-added PATH fallback for nm would have left it
# green while the runner quietly read the box's binutils. That is the same
# "green having checked nothing" shape these arms exist to catch, one level up.
want_broken "symbols_test: no PATH fallback for nm" \
	"--nm is required (no PATH fallback by design)" -- \
	"$SH" "$TOOLS/symbols_test.sh" --expect ft_x --src "$WORK/static.c"
want_broken "forbidden_symbols: no PATH fallback for nm" \
	"--nm is required (no PATH fallback by design)" -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --allowed write --src "$WORK/static.c"
want_broken "make_test: no PATH fallback for nm" \
	"--nm is required (no PATH fallback by design)" -- \
	"$SH" "$TOOLS/make_test.sh" --build-target selftest_build \
		--anchor "$WORK/static.c" --artifact libft.a
# ...nor one without its library (V272). Each runner proved the loader took
# libbfd from --nm-lib only when --nm-lib came, and without it went green on
# whatever libbfd the box had: a pinned nm in name only. Each arm passes a
# complete argument list with only the library missing; make_test.sh runs
# nm under --symbols alone, and objdump is held to --objdump-lib the same way.
# Each refuses before it reads a file, so this section's toys are bare.
mkdir -p "$WORK/nmpin"
printf 'all:\n\t: > libtoy.a\n' > "$WORK/nmpin/Makefile"
printf 'functions:toy_say\tA sentence for the selftest.\n' > "$WORK/nmpin/q_say.tsv"
printf 'int\ttoy_say(int n)\n{\n\treturn (n);\n}\n' > "$WORK/nmpin/direct.c"
# conventions: nm unpinned -- the refusal of an nm without its library is the arm
want_broken "symbols_test: --nm without --nm-lib is a broken harness" \
	'--nm needs --nm-lib' -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --expect ft_x --src "$WORK/static.c"
# conventions: nm unpinned -- the refusal of an nm without its library is the arm
want_broken "forbidden_symbols: --nm without --nm-lib is a broken harness" \
	'--nm needs --nm-lib' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --allowed - --src "$WORK/clean.c"
# conventions: nm unpinned -- the refusal of an nm without its library is the arm
want_broken "make_test: --symbols with --nm and no --nm-lib is a broken harness" \
	'which needs --nm-lib' -- \
	"$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --build-target selftest_build \
		--anchor "$WORK/nmpin/Makefile" --artifact libtoy.a --symbols toy_say
want_broken "forbidden_symbols: --objdump without --objdump-lib is a broken harness" \
	'--objdump needs --objdump-lib' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --objdump "$OBJDUMP" \
		--quotes "$WORK/nmpin/q_say.tsv" --function toy_say= --src "$WORK/nmpin/direct.c"
# ...nor with a library folder that is not there: each refuses in
# rl_binutils_pin's one sentence, whichever tool and flag (make_test.sh's arm
# is in its own section).
want_broken "symbols_test: a --nm-lib folder that is not there is refused" \
	"symbols_test.sh: --nm-lib directory '$WORK/nmpin/gone' does not exist." -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --nm-lib "$WORK/nmpin/gone/libbfd.so" \
		--expect ft_x --src "$WORK/static.c"
want_broken "forbidden_symbols: a --nm-lib folder that is not there is refused" \
	"forbidden_symbols.sh: --nm-lib directory '$WORK/nmpin/gone' does not exist." -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$WORK/nmpin/gone/libbfd.so" \
		--allowed - --src "$WORK/clean.c"
want_broken "forbidden_symbols: ...and an --objdump-lib folder" \
	"forbidden_symbols.sh: --objdump-lib directory '$WORK/nmpin/gone' does not exist." -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" --objdump "$OBJDUMP" \
		--objdump-lib "$WORK/nmpin/gone/libbfd.so" --quotes "$WORK/nmpin/q_say.tsv" \
		--function toy_say= --src "$WORK/nmpin/direct.c"

# ...nor one the loader cannot start (a library this machine lacks). Its
# words went into the file the loader's proof reads, which then found no
# `calling init:` line for libbfd and refused as "could not observe" which
# one it loaded, naming nothing. The stand-in prints what the loader prints
# and exits as it does; each refusal says the tool did not start, and names
# the library.
mkdir -p "$WORK/nmdead"
for _nd in nm objdump; do
	printf '#!/bin/sh\necho "$0: error while loading shared libraries: libselftestmiss.so.1: cannot open shared object file: No such file or directory" >&2\nexit 127\n' \
		> "$WORK/nmdead/$_nd"
	chmod +x "$WORK/nmdead/$_nd"
done
want_broken "symbols_test: an nm that cannot start says so" \
	'the pinned nm cannot start (exit 127)' -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$WORK/nmdead/nm" --nm-lib "$NM_LIB" \
		--expect ft_x --src "$WORK/static.c"
want_broken "symbols_test: ...and names the library it lacks" \
	'The loader found no libselftestmiss.so.1' -- \
	"$SH" "$TOOLS/symbols_test.sh" --nm "$WORK/nmdead/nm" --nm-lib "$NM_LIB" \
		--expect ft_x --src "$WORK/static.c"
want_broken "forbidden_symbols: an nm that cannot start says so" \
	'the pinned nm cannot start (exit 127)' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$WORK/nmdead/nm" --nm-lib "$NM_LIB" \
		--allowed - --src "$WORK/clean.c"
want_broken "forbidden_symbols: ...and an objdump" \
	'the pinned objdump cannot start (exit 127)' -- \
	"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" --nm-lib "$NM_LIB" \
		--objdump "$WORK/nmdead/objdump" --objdump-lib "$NM_LIB" \
		--quotes "$WORK/nmpin/q_say.tsv" --function toy_say= --src "$WORK/nmpin/direct.c"
want_broken "make_test: an nm that cannot start says so" \
	'the pinned nm cannot start (exit 127)' -- \
	"$SH" "$TOOLS/make_test.sh" --nm "$WORK/nmdead/nm" --nm-lib "$NM_LIB" --rules "" \
		--build-target selftest_build --anchor "$WORK/nmpin/Makefile" --artifact libtoy.a \
		--symbols toy_say
