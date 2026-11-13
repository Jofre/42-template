# ---------------------------------------------------------------- conventions
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The style gate, which until now was the one check in the repo with no arm --
# and it is the check that decides whether every OTHER script still declares
# what it takes from PATH. Its detector is a shell parser written in awk, i.e.
# exactly the kind of thing that quietly stops matching and goes on reporting
# OK: the failure this whole file exists for, sitting inside the guard against
# it.
#
# Driven over a THROWAWAY workspace of probe scripts. conventions.sh takes its
# root from $BUILD_WORKSPACE_DIRECTORY, so pointing that at a fixture tree runs
# the real script against known inputs. The run also reports the fixture's
# missing .bazelrc, defs.bzl and reference.md, and that is fine -- every arm
# below asserts on ONE named probe rather than on the exit status.
#
# No --shellcheck is passed on purpose: these arms are about the require
# detector, and linting four probe scripts would only add noise it might trip on.
mkdir -p "$WORK/cv/tools/tests"

# The modules conventions.sh walks are the REMOTES table's keys, so the fixture
# needs a table before any arm runs: without one the script refuses (exit 2),
# which is the behaviour pinned further down. The two fixture modules sit under
# a course folder, as the real ones do, so the walk is proven one level deep.
_cv_mods="c-piscine/c-piscine-c-98 c-piscine/c-piscine-c-99"
for _m in $_cv_mods; do mkdir -p "$WORK/cv/$_m" && : > "$WORK/cv/$_m/BUILD.bazel"; done

# Calls two PATH commands, declares neither.
printf '#!/bin/sh\nset -u\ngit status\ngrep x file\n' \
	> "$WORK/cv/tools/probe_undeclared.sh"
# ...and one in the toolchain's folder and one in the installer's, each
# calling grep: the rule once read tools/ and tools/tests/ alone.
mkdir -p "$WORK/cv/tools/cc_toolchain" "$WORK/cv/tools/fortytwo"
for _cvd in cc_toolchain fortytwo; do
	printf '#!/bin/sh\nset -u\ngrep x file\n' > "$WORK/cv/tools/$_cvd/probe_req.sh"
done
# ...and the two rules that read the same list of scripts, each held one
# folder down: an installer script calling need() it never defines, and a
# toolchain script whose require() does nothing.
printf '#!/bin/sh\nset -u\nwhile [ $# -gt 0 ]; do case "$1" in --x) need "$1" "$#"; shift 2 ;; *) shift ;; esac; done\n' \
	> "$WORK/cv/tools/fortytwo/probe_need.sh"
printf '#!/bin/sh\nset -u\nrequire() { :; }\nrequire grep\ngrep x file\n' > "$WORK/cv/tools/cc_toolchain/probe_reqnoop.sh"

# Declares exactly what it calls, INCLUDING git. This is the arm the old
# vocabulary made impossible: it listed 24 coreutils names, so `git` was
# invisible to the scanner, `used` came back without it, and a correct
# declaration was reported as drift. The check punished the one thing it exists
# to encourage, which is why no script declared git, cc, make or md5sum.
{ printf '#!/bin/sh\nset -u\n'; cv_require probe_declared.sh; printf 'require git grep\ngit status\ngrep x file\n'; } \
	> "$WORK/cv/tools/probe_declared.sh"
# The same declaration, through a copy of the helper that drifted: one that
# does nothing, and one that exits 1 for a missing tool, turning "the check
# never ran" into a red. The list matches what each calls, so only the body
# can tell them from the helper.
{ printf '#!/bin/sh\nset -u\nrequire() { :; }\n'; printf 'require git grep\ngit status\ngrep x file\n'; } \
	> "$WORK/cv/tools/probe_reqnoop.sh"
{ printf '#!/bin/sh\nset -u\n'; cv_require probe_reqexit.sh | sed 's/exit 2$/exit 1/'
	printf 'require git grep\ngit status\ngrep x file\n'; } > "$WORK/cv/tools/probe_reqexit.sh"

# Names two tools INSIDE quoted messages and calls neither. The scanner splits
# on | ; & ( ) to find command position, so "--mode must be norm|diff|check"
# used to yield a fragment `diff`, and "(nm failed)" a fragment `nm`. Both were
# counted as calls -- a phantom dependency that shell_test.sh actually carried
# in its require line for as long as the check has existed.
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_quoted.sh
	printf 'require grep\n'
	printf 'echo "--mode must be norm|diff|check"\n'
	printf 'echo "cannot read symbols from x (nm failed)"\n'
	printf 'grep x file\n'
} > "$WORK/cv/tools/probe_quoted.sh"
# Names a tool INSIDE a single-quoted awk program: an awk variable after a `;`,
# and one at the start of a line of a program that spans lines. Both are the
# program's text, not calls; the scanner once read each as a call to nm (V115).
# Each declares the awk it calls, so a scanner that saw no call at all is red.
{ printf '#!/bin/sh\nset -u\n'; cv_require probe_awkvar.sh; printf 'require awk\nawk \047{ a = 1; nm = 2 }\047 file\n'; } \
	> "$WORK/cv/tools/probe_awkvar.sh"
{ printf '#!/bin/sh\nset -u\n'; cv_require probe_awkvar2.sh; printf 'require awk\nawk \047\n\tBEGIN { a = 1 }\nnm = 2\n\047 file\n'; } \
	> "$WORK/cv/tools/probe_awkvar2.sh"
# The two shapes the old line scanner split into calls, inside a program
# spanning lines: a regex literal of alternatives, and an empty string given
# to a variable named like a tool, after a `;` and at the start of a line.
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_awkvar3.sh
	printf 'require awk\nawk \047\n'
	printf '\t$0 ~ /(cat|sed|fold|tee)([[:blank:]]|$)/ { a = 1; nm = "" }\n'
	printf 'nm = ""\n\047 file\n'
} > "$WORK/cv/tools/probe_awkvar3.sh"
# ...while what runs from a word is a call all the same: the string sh -c
# runs, a $( ) inside an arithmetic expansion, a command a helper is handed
# after `--`, each the only use of its tool. And a tool only a program the
# script writes runs is a call once declared so, and drift until then.
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_wordrun.sh
	printf 'require cmp env tail wc\nrun() { "$@"; }\n'
	printf 'env X=1 /bin/sh -c \047tail -n 1 "$1"\047 _ f\n'
	printf 'n=$(( $(wc -l < f) + 1 ))\n'
	printf 'run "name" -- cmp a b\n'
} > "$WORK/cv/tools/probe_wordrun.sh"
# The string a shell runs, whatever flags come with -c: in one cluster, apart
# from it, and a simple double-quoted string.
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_wordrun2.sh
	printf 'require od sort uniq\n'
	printf 'sh -ec \047sort f\047\n'
	printf 'sh -e -c \047od f\047\n'
	printf 'sh -c "uniq f"\n'
} > "$WORK/cv/tools/probe_wordrun2.sh"
for _cvp in probe_writes probe_writes_bare; do
	{
		printf '#!/bin/sh\nset -u\n'
		cv_require "$_cvp.sh"
		printf 'require fold\n'
		[ "$_cvp" = probe_writes ] &&
			printf '# conventions: writes a program that runs fold -- the toy program\n'
		printf 'gen() { printf "%%s\\n" "$@" > prog; }\ngen \047x | fold -w 3\047\n'
	} > "$WORK/cv/tools/$_cvp.sh"
done
# The marker without its reason declares nothing, and a tool it names goes
# through what every call does: one declared optional is exempt, and a word
# no vocabulary holds is no command to probe.
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_writes_bald.sh
	printf 'require fold\n'
	printf '# conventions: writes a program that runs fold\n'
	printf 'gen() { printf "%%s\\n" "$@" > prog; }\ngen \047x | fold -w 3\047\n'
} > "$WORK/cv/tools/probe_writes_bald.sh"
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_writes_opt.sh
	printf 'require grep\n'
	printf '# conventions: optional fold -- probed; without it the toy program is not written\n'
	printf '# conventions: writes a program that runs fold -- the toy program\n'
	printf '# conventions: writes a program that runs frobnicate -- no command of the vocabulary\n'
	printf 'gen() { printf "%%s\\n" "$@" > prog; }\ngen \047x | fold -w 3 | frobnicate\047\n'
	printf 'grep x file\n'
} > "$WORK/cv/tools/probe_writes_opt.sh"
# What a command runs is a call too: behind env, xargs, nohup and stdbuf,
# and behind time, which is a keyword. Each runs a tool no other line does.
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_reqwrap.sh
	printf 'require grep\nx=$(env LC_ALL=C sort f)\nprintf x | xargs -0 grep -l x\n'
	printf 'nohup cut -c1 f\nstdbuf -oL head f\ntime tr a b\n'
} > "$WORK/cv/tools/probe_reqwrap.sh"
# What follows `--` is read as a call after any command word no vocabulary
# holds, a function that never runs it included: an over-count kept on
# purpose (the require list's comment says why), and pinned here.
{ printf '#!/bin/sh\nset -u\n'; cv_require probe_dashdash.sh; printf 'require grep\nf() { :; }\nf x -- sort\ngrep x file\n'; } \
	> "$WORK/cv/tools/probe_dashdash.sh"
# A comment pointing at a line of a file by its number, bare and in a code
# span, is reported; output it quotes (a message in quotes, one quoted over
# two lines, a diagnostic with a colon after the number) and a line of code
# are not. In a page: prose is read, a fenced block and a quoted message are
# not. The numbers are in the format strings, so no comment here holds one.
# A """ in a shell comment opens no docstring: the line of code after it is
# not read, and a comment after that is. Nor is it three quotes, the last
# opening one the pointer after it would sit in (line 12, V141).
printf '%s\n' '#!/bin/sh' '# see tools/defs.bzl:9999' '# see `tools/defs.bzl:12` for the rest' \
	'# it printed "patch failed: README.md:16" and stopped' '# deliverable/ex00/a.c:3:1: error: x' \
	'echo "x.sh:12"' '# it printed "error: patch failed:' '# README.md:16", and stopped' \
	'# a docstring opens with """' 'echo "x.sh:12"' '# see tools/defs.bzl:7' \
	'# a docstring opens with """, as tools/v.sh:8 does' \
	> "$WORK/cv/tools/probe_ptr.sh"
# A docstring is read from the """ that opens it to the one that closes it:
# on its opening line, on its closing line, and when it is one line long.
# A comment naming one is read as the .sh one is (line 7).
printf '%s\n' 'def f():' '    """See tools/x.sh:4 for it."""' 'def g():' \
	'    """Opens on tools/y.sh:5, and' '    closes on tools/z.sh:6."""' 'x = "tools/w.sh:7"' \
	'# a docstring opens with """, as tools/v.sh:8 does' \
	> "$WORK/cv/tools/probe_ptr.py"
mkdir -p "$WORK/cv/docs"
# A version, and a host and its port, whose last part is no file kind of
# the tree, are no file and its line.
printf '%s\n' '# Probe' 'See tools/x.sh:4 for it.' '```' 'a.sh:3 printed here' '```' \
	'It printed `error: a.c:5 broke`.' 'The proxy is proxy.example.com:3128.' \
	'It changed in v1.2:3 of the format.' > "$WORK/cv/docs/probe_ptr.md"

# Probes for a tool and degrades without it, so it must NOT go in require --
# require exits 2 on absence, which would turn "this layer says less" into "the
# harness is broken". The marker is what says so, and it is per-tool so that
# each exemption is a reviewable sentence rather than a word missing from a list.
#
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_optional.sh
	printf 'require grep\n'
	printf '# conventions: optional git -- probed; without it this probe does less\n'
	printf 'command -v git >/dev/null 2>&1 && git status\n'
	printf 'grep x file\n'
} > "$WORK/cv/tools/probe_optional.sh"
# Either exemption without its reason exempts nothing: the tool an optional
# line names is a call as any other, and a script marked no-require is held
# to a require list like any other.
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_optional_bald.sh
	printf 'require grep\n'
	printf '# conventions: optional git\n'
	printf 'command -v git >/dev/null 2>&1 && git status\n'
	printf 'grep x file\n'
} > "$WORK/cv/tools/probe_optional_bald.sh"
printf '#!/bin/sh\nset -u\n# conventions: no-require\ngrep x file\n' \
	> "$WORK/cv/tools/probe_norequire_bald.sh"

# THE SHARED RUNNER CONCERNS (tools/runner_lib.sh), one probe each way.
#
# A signal trap that cleans up and does not exit resumes the script without
# its files (finding 066). The four-line form, a cleanup on EXIT and an
# exit on TERM, INT and HUP, is the fix, and is quiet.
printf '#!/bin/sh\nset -u\nx=$(mktemp)\ntrap %s EXIT INT TERM\n' "'rm -f \"\$x\"'" \
	> "$WORK/cv/tools/probe_trap.sh"
printf '#!/bin/sh\nset -u\nx=$(mktemp) || exit 2\ntrap %s EXIT\ntrap %s TERM\ntrap %s INT\ntrap %s HUP\n' \
	"'rm -f \"\$x\"'" "'exit 143'" "'exit 130'" "'exit 129'" > "$WORK/cv/tools/probe_trap_ok.sh"
# In a runner that sources the library, even that correct form replaces the
# library's own EXIT trap: there only rl_traps may set one.
printf '#!/bin/sh\nset -u\n. "$RL_LIB"\nx=$(mktemp)\ntrap %s EXIT\n' \
	"'rm -f \"\$x\"'" > "$WORK/cv/tools/probe_libtrap.sh"
# A script that reads the loader's `calling init:` lines itself, beside
# runner_lib.sh's rl_libs_under (V277), and one that names them in a comment
# and calls rl_libs_under.
printf '#!/bin/sh\nset -u\nsed -n %s "$1"\n' "'s/.*calling init: //p'" > "$WORK/cv/tools/probe_ldparse.sh"
printf '#!/bin/sh\nset -u\n# the `calling init:` lines, read by rl_libs_under\nrl_libs_under "a tool" "$1" "$2" libbfd\n' \
	> "$WORK/cv/tools/probe_ldparse_ok.sh"
# The same reading one folder down: the rule reads every harness script
# (tool_scripts), not tools/*.sh alone.
printf '#!/bin/sh\nset -u\necho "${1#*calling init: }"\n' > "$WORK/cv/tools/cc_toolchain/probe_ldparse.sh"
# ...and one that runs a tool under LD_DEBUG=libs itself, beside
# rl_probe_libs, and one that names it in a comment and calls rl_probe_libs.
printf '#!/bin/sh\nset -u\nenv -u LD_DEBUG_OUTPUT LD_DEBUG=libs "$1" --version 2> "$2"\n' \
	> "$WORK/cv/tools/probe_ldprobe.sh"
printf '#!/bin/sh\nset -u\n# under LD_DEBUG=libs, by rl_probe_libs\nrl_probe_libs "a tool" "$2" t.txt "$1"\n' \
	> "$WORK/cv/tools/probe_ldprobe_ok.sh"
# The same probe one folder down: this rule too reads every harness script.
printf '#!/bin/sh\nset -u\nLD_DEBUG=libs "$1" --version 2> "$2"\n' > "$WORK/cv/tools/cc_toolchain/probe_ldprobe.sh"
# A runner reading its --inc-file list itself, beside rl_inc_file (V317), in
# an arm of several lines; and one calling rl_inc_file on one line.
{
	printf '#!/bin/sh\nset -u\nwhile [ $# -gt 0 ]; do\n\tcase "$1" in\n'
	printf '\t\t--inc-file)\n\t\t\twhile IFS= read -r i; do INCS="$INCS -I$i"; done < "$2"\n\t\t\tshift 2 ;;\n'
	printf '\t\t*) exit 2 ;;\n\tesac\ndone\n'
} > "$WORK/cv/tools/probe_incfile.sh"
{
	printf '#!/bin/sh\nset -u\nwhile [ $# -gt 0 ]; do\n\tcase "$1" in\n'
	printf '\t\t--inc-file) rl_inc_file INCS "$2"; shift 2 ;;\n'
	printf '\t\t*) exit 2 ;;\n\tesac\ndone\n'
} > "$WORK/cv/tools/probe_incfile_ok.sh"
# A runner that takes the program under test, bounds a run itself and runs it
# bare -- three findings of the budget rule in one file -- and its fixed form,
# which sources the library and runs the program with rl_run. The bound is
# also spelt where a command stands behind if, while, env and exec (11-14),
# and behind setsid, a program that runs another (15): the bound is reported,
# and so is the program it runs.
{
	printf '#!/bin/sh\nset -u\nwhile [ $# -gt 0 ]; do\n\tcase "$1" in\n'
	printf '\t\t--bin) BIN="$2"; shift 2 ;;\n\t\t*) exit 2 ;;\n\tesac\ndone\n'
	printf 'RUNNER="timeout -s KILL 5"\n"$BIN" x > /dev/null\n'
	printf 'if timeout 5 "$BIN"; then :; fi\nwhile timeout 1 "$BIN"; do break; done\n'
	printf 'env A=1 timeout 5 "$BIN"\nexec timeout 5 "$BIN"\n'
	printf 'setsid timeout 5 "$BIN"\n'
} > "$WORK/cv/tools/probe_budget.sh"
# A tool that runs outside every test, so it has no test's limit to keep,
# bounds a run with timeout and says why on the line above (the marker held
# to the comments right above it, as the harness tool one is): quiet. The
# same marker above another line covers only that one.
{ printf '#!/bin/sh\nset -u\n'; cv_require probe_bound_ok.sh
	printf 'require timeout\n# conventions: bounds itself -- a toy run by no test\ntimeout 5 sh x.sh\n'; } \
	> "$WORK/cv/tools/probe_bound_ok.sh"
{ printf '#!/bin/sh\nset -u\n'; cv_require probe_bound_far.sh
	printf 'require timeout\n# conventions: bounds itself -- a toy run by no test\ntimeout 5 sh x.sh\n'
	printf 'timeout 5 sh y.sh\n'; } > "$WORK/cv/tools/probe_bound_far.sh"
# The same marker in a runner exempts nothing: a runner keeps its test's
# limit. One that sources the library, and one a test names in its srcs
# (below) that does not.
{ printf '#!/bin/sh\nset -u\n'; cv_require probe_bound_lib.sh
	printf 'require timeout\n. "$RL_LIB"\n# conventions: bounds itself -- a runner saying so\ntimeout 5 sh x.sh\n'; } \
	> "$WORK/cv/tools/probe_bound_lib.sh"
{ printf '#!/bin/sh\nset -u\n'; cv_require probe_bound_test.sh
	printf 'require timeout\n# conventions: bounds itself -- a runner saying so\ntimeout 5 sh x.sh\n'; } \
	> "$WORK/cv/tools/probe_bound_test.sh"
{
	printf '#!/bin/sh\nset -u\nwhile [ $# -gt 0 ]; do\n\tcase "$1" in\n'
	printf '\t\t--bin) [ $# -ge 2 ] || exit 2; BIN="$2"; shift 2 ;;\n\t\t*) exit 2 ;;\n\tesac\ndone\n'
	printf '. "$RL_LIB"\nrl_tmo 5 || exit 1\nrl_run "$BIN" x > /dev/null\n'
	printf 'A=1 \\\n\trl_run "$BIN" y > /dev/null\n'
	# A case on the program's name runs nothing (14).
	printf 'case "$BIN" in *) : ;; esac\n'
} > "$WORK/cv/tools/probe_budget_ok.sh"
# A script that names the option loop only in a comment, and skips with no
# NO_SKIP guard: no runner, to the SKIP rule as to the set -u and Usage ones,
# which read one list of runners.
printf '#!/bin/sh\n# A runner reads its options in: while [ $# -gt 0 ]; do ... done\necho "SKIP \342\200\224 no foo"\nexit 0\n' \
	> "$WORK/cv/tools/probe_doc_loop.sh"
# A test naming the fixed form as its runner. (It stages neither file the
# runner needs, which a staging walk once reported; _test() stages both for
# every test now, and refuses a copy listed by hand.)
{
	printf 'sh_test(\n    name = "ex00_bare",\n    srcs = ["//tools:probe_budget_ok.sh"],\n'
	printf '    data = [":ex00_bin"],\n)\n\n'
	# What makes a script a runner is that a test names it in its srcs --
	# whatever it is called and whatever options it takes -- and a
	# sh_binary's srcs is not a test.
	printf 'sh_test(\n    name = "ex00_budget",\n    srcs = ["//tools:probe_budget.sh"],\n)\n\n'
	printf 'sh_test(\n    name = "ex00_cut",\n    srcs = ["//tools:probe_cut.sh"],\n)\n\n'
	printf 'sh_test(\n    name = "ex00_bound",\n    srcs = ["//tools:probe_bound_test.sh"],\n)\n\n'
	printf 'sh_binary(\n    name = "tool",\n    srcs = ["//tools:probe_bin.sh"],\n)\n'
} > "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
printf '#!/bin/sh\nset -u\n:\n' > "$WORK/cv/tools/probe_bin.sh"
# A runner that sources the library and cuts captured output with a bare head;
# and the three forms that are not an excerpt: a value taken into a variable, a
# line marked as not being one, and rl_excerpt itself.
{
	printf '#!/bin/sh\nset -u\n. "$RL_LIB"\n'
	printf 'sed "s/^/  /" "$ERR" | head -10\n'
} > "$WORK/cv/tools/probe_excerpt.sh"
{
	printf '#!/bin/sh\nset -u\n. "$RL_LIB"\n'
	printf 'v=$(head -5 "$ERR")\n'
	printf '# conventions: not-an-excerpt -- a source file header, not output\n'
	printf 'head -20 "$SRC" > /dev/null\n'
	printf 'rl_excerpt "$ERR" 10 err.txt\n'
} > "$WORK/cv/tools/probe_excerpt_ok.sh"
# A runner printing what a run wrote raw: a file rl_run's output went to
# (4), one a group around rl_run wrote (6), one a function wrote through
# its argument (9); and the forms that are not: a value, a copy to a file,
# a pipe, rl_excerpt, a marked line, a group sent to a file, and a file no
# run wrote.
{
	printf '#!/bin/sh\nset -u\n. "$RL_LIB"\n'
	printf 'rl_run "$BIN" > "$OUT" 2> "$ERR"; cat "$OUT"\n'
	printf '( ulimit -f 8; rl_run "$BIN" ) > "$LOG" 2>&1\n'
	printf 'cat "$LOG"\n'
	printf 'mkr() { _o=$1; shift; ( rl_run "$@" ) > "$_o" 2>&1; }\n'
	printf 'mkr "$BUILT" "$BIN"\n'
	printf 'tail "$BUILT" >&2\n'
	printf 'v=$(cat "$OUT")\n'
	printf 'head -1 "$ERR" > "$T/copy"\n'
	printf 'cat "$LOG" | wc -l\n'
	printf 'rl_excerpt "$ERR" 10 err.txt\n'
	printf '# conventions: shown-raw -- a probe of the marker\n'
	printf 'cat "$ERR"\n'
	printf '{ cat "$OUT"; echo; } > "$T/nl"\n'
	printf 'cat "$OTHER"\n'
} > "$WORK/cv/tools/probe_rawcap.sh"
# A runner reading clues.tsv itself, and one that only forwards and tests it.
printf '#!/bin/sh\nset -u\ncut -f1 "$CLUES" > /dev/null\n' > "$WORK/cv/tools/probe_clue.sh"
printf '#!/bin/sh\nset -u\n[ -f "$CLUES" ] && set -- --clues "$CLUES"\nrl_clues "$CLUES"\n' \
	> "$WORK/cv/tools/probe_clue_ok.sh"

# THE SHAPES THE FIRST RULES MISSED (review of wave 3's runner library): each
# was reproduced on a probe runner and passed. A runner is what a test names
# in its srcs, not an option spelled --bin; a program started by path is the
# student's whatever runs it; a trap is found wherever a command starts; an
# excerpt is any cut of a stream's start; a clue file is whatever an option
# arm stores it in. Line numbers are asserted exactly, so a rule that starts
# flagging the forms beside them is caught too.
{
	printf '#!/bin/sh\nset -u\n. "$RL_LIB"\n'
	printf 'while [ $# -gt 0 ]; do\n\tcase "$1" in\n'
	printf '\t\t--prog) [ $# -ge 2 ] || exit 2; PROG="$2"; shift 2 ;;\n\t\t*) exit 2 ;;\n\tesac\ndone\n'
	printf '"$PROG" a\n'
	printf 'env A=1 "$PROG" b\n'
	printf 'valgrind --quiet "$PROG" c\n'
	printf 'setarch "$(uname -m)" -R "$PROG" d\n'
	printf '"$WORK/probe" e\n'
	printf 'x=$("$PROG" f)\n'
	printf 'rl_run "$PROG" g\n'
	printf '# conventions: harness tool CC -- a pinned compiler\n'
	printf '"$CC" -c x.c\n'
	printf '# conventions: harness tool -- a probe this runner wrote\n'
	printf '"$WORK/model"\n'
} > "$WORK/cv/tools/probe_shapes.sh"
{
	printf '#!/bin/sh\nset -u\n'
	printf '# conventions: runs no student code -- a probe of the excerpt rule\n'
	printf 'sed "s/^/  /" "$ERR" | head -20\n'
	printf 'tail -n 20 "$E"\n'
	printf 'head -c 400 "$OUT" | sed "s/^/  /"\n'
	printf 'awk %s "$E"\n' "'NR<=5'"
	printf 'echo "$(head -20 "$E")"\n'
	printf 'v=$(head -5 "$ERR")\n'
	printf 'tail -n +2 "$E"\n'
	printf 'head -n 5 "$E" > "$T/x"\n'
	printf 'head -n "$1" a | cmp -s - b\n'
	printf 'head -1 "$E"\n'
	printf '# conventions: not-an-excerpt -- a header comment, not output\n'
	printf 'head -20 "$SRC"\n'
	# A path that only starts like the terminal's is a file (16); /dev/tty
	# and a quoted /dev/stderr are the terminal (17, 18).
	printf 'head -n 3 "$E" > /dev/stderr.log\n'
	printf 'head -n 3 "$E" > /dev/tty\n'
	printf 'head -n 3 "$E" > "/dev/stderr"\n'
} > "$WORK/cv/tools/probe_cut.sh"
{
	printf '#!/bin/sh\nset -u\n'
	printf 'T=$(mktemp -d); trap %s EXIT INT TERM\n' "'rm -rf \"\$T\"'"
	printf 'if true; then trap %s INT; fi\n' "'rm -f x'"
	printf 'trap %s EXIT\ntrap %s TERM\n' "'rm -f y'" "'exit 143'"
} > "$WORK/cv/tools/probe_trap2.sh"
# ...and where elif starts one (3).
printf '#!/bin/sh\nset -u\nif false; then :; elif trap %s INT; then :; fi\n' "'rm -f z'" \
	> "$WORK/cv/tools/probe_trap3.sh"
_cl_arm='while [ $# -gt 0 ]; do\n\tcase "$1" in\n\t\t%s) [ $# -ge 2 ] || exit 2; %s="$2"; shift 2 ;;\n\t\t*) exit 2 ;;\n\tesac\ndone\n'
{
	printf '#!/bin/sh\nset -u\n'
	# shellcheck disable=SC2059 # the format is the arm, kept in one place
	printf "$_cl_arm" --clues C
	printf 'cut -f1 "$C"\n'
} > "$WORK/cv/tools/probe_clue2.sh"
{
	printf '#!/bin/sh\nset -u\n'
	# shellcheck disable=SC2059 # the format is the arm, kept in one place
	printf "$_cl_arm" --hints H
	printf 'X="$H"\n[ -f "$X" ] && echo "hints in $X"\n'
	printf 'while read -r l; do echo "$l"; done < "$X"\n'
	printf 'rl_clues "$X"\n'
} > "$WORK/cv/tools/probe_clue3.sh"
# A sourced library declares what it takes from PATH in its own probe loop,
# checked like a require line: this one says awk and calls sed.
{
	printf '# shellcheck shell=sh\nfor _pl_t in awk; do\n'
	printf '\tcommand -v "$_pl_t" > /dev/null 2>&1 || exit 2\ndone\n'
	printf 'pl_x() { sed -n 1p "$1"; }\n'
} > "$WORK/cv/tools/probe_lib.sh"
# ...and one with no loop at all is no exemption: it was skipped, as if it
# called nothing, while shell_check.sh called tail with no probe, and a
# missing tail made a newline check pass. One that calls nothing is quiet.
printf '# shellcheck shell=sh
pl_y() { tail -n 1 "$1"; }\n' > "$WORK/cv/tools/probe_libnoloop.sh"
printf '# shellcheck shell=sh
pl_z() { printf "%%s\\n" "$1"; }\n' > "$WORK/cv/tools/probe_libnone.sh"
# ls is a call it sees too: shell_check.sh's ck_executable read the mode
# with ls, unprobed, and the check, whose list of tools had no ls, said nothing.
printf '# shellcheck shell=sh
pl_w() { ls -l "$1"; }\n' > "$WORK/cv/tools/probe_libls.sh"

# A generated exercise's clues.tsv names its module, exercise and turn-in on
# its first line (finding 019: one had another edition's title instead).
mkdir -p "$WORK/cv/c-piscine/c-piscine-c-98/generators" \
	"$WORK/cv/c-piscine/c-piscine-c-98/tests/ex00" "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex01"
printf '#!/bin/sh\n# ex00 -- made up\n:\n' > "$WORK/cv/c-piscine/c-piscine-c-98/generators/ex00.sh"
printf '#!/bin/sh\n# ex01 -- made up\n:\n' > "$WORK/cv/c-piscine/c-piscine-c-98/generators/ex01.sh"
printf '# clues.tsv for ex00 (Un titre)\n' > "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex00/clues.tsv"
printf '# clues.tsv for c-piscine-c-98 ex01 (made_up.sh)\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex01/clues.tsv"

# A function a grader_library() crate exports is never DEFINED in C outside
# the zone -- that is the answer of the exercise that writes it -- and a
# declaration, which a test needs to call it, is fine. An invented crate
# exporting cv_graded; one file defines it (its signature over two lines,
# as the Norm wraps one), one only declares it.
#
# Each call's `exports` is what the subject contract checks a `linked` name
# against (tools/subject.bzl), so it must be the crate's #[no_mangle]
# functions exactly: cv_grader's is; cv_other lists, one per line, a name its
# crate never exports (cv_two), which would pass the contract and link in no
# program.
mkdir -p "$WORK/cv/oracle/grader"
{
	printf 'grader_library(\n    name = "cv_grader",\n    src = "grader/cv.rs",\n'
	printf '    exports = ["cv_graded"],\n)\n\n'
	printf 'grader_library(\n    name = "cv_other",\n    src = "grader/cv_other.rs",\n'
	printf '    exports = [\n        "cv_one",\n        "cv_two",\n    ],\n)\n'
} > "$WORK/cv/oracle/BUILD.bazel"
printf '#![no_std]\n/// Invented.\n#[no_mangle]\npub extern "C" fn cv_graded(n: i32) -> i32 {\n    n\n}\n' \
	> "$WORK/cv/oracle/grader/cv.rs"
printf '#![no_std]\n/// Invented.\n#[no_mangle]\npub extern "C" fn cv_one() -> i32 {\n    1\n}\n' \
	> "$WORK/cv/oracle/grader/cv_other.rs"
printf 'int\tcv_graded(int n,\n\t\tint unused)\n{\n\treturn (n);\n}\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex00/graded_copy.c"
printf 'int\tcv_graded(int n);\n\nint\tcv_uses(void)\n{\n\treturn (cv_graded(1));\n}\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-98/tests/ex01/graded_call.c"
# Before any `linked` is chosen, a function the student turns in is never
# written outside the zone either: every name a contract's `files` gives a
# source for (X.c turns in X; main.c is a program) may be defined outside
# deliverable/ and generators/ as a stub only. An invented project, c-97, whose
# ex00 turns in cv_owed.c and ft_putchar.c and whose ex01 lists cv_split.c and
# main.c over several lines. Reported: a "provided" C copy of cv_owed that does
# the work (the shape Reloaded's ft_putchar.c set), a cv_split whose return
# type sits on the line above an indented name, and the stdio ft_putchar at a
# path no exemption names. Not reported: a placeholder stub and a
# declaration, a main() calling cv_split, the copy in deliverable/ (the zone),
# and the same stdio ft_putchar at the one path the rule exempts.
mkdir -p "$WORK/cv/c-piscine/c-piscine-c-97/tests/ex00" "$WORK/cv/c-piscine/c-piscine-c-97/tests/ex01" \
	"$WORK/cv/c-piscine/c-piscine-c-97/tests/ex02/provided" "$WORK/cv/c-piscine/c-piscine-c-97/deliverable/ex00" \
	"$WORK/cv/c-piscine-reloaded/c-piscine-reloaded/tests"
{
	printf 'subject(\n    grader = "moulinette",\n    group = False,\n    exercises = {\n'
	printf '        "00": exercise(page = 1, dir = "ex00/", files = ["cv_owed.c", "ft_putchar.c"], allowed = []),\n'
	printf '        "01": exercise(\n            page = 2,\n            dir = "ex01/",\n'
	printf '            files = [\n                "cv_split.c",\n                "main.c",\n            ],\n'
	printf '            allowed = [],\n        ),\n    },\n)\n'
} > "$WORK/cv/c-piscine/c-piscine-c-97/BUILD.bazel"
_cv_owed='int\tcv_owed(int n)\n{\n\treturn (n * 2);\n}\n'
# shellcheck disable=SC2059 # the format is the fixture, kept in one place
printf "$_cv_owed" > "$WORK/cv/c-piscine/c-piscine-c-97/tests/ex02/provided/cv_owed.c"
# shellcheck disable=SC2059 # the format is the fixture, kept in one place
printf "$_cv_owed" > "$WORK/cv/c-piscine/c-piscine-c-97/deliverable/ex00/cv_owed.c"
printf '/* { */\nint\tcv_owed(int n);\n\nint\tcv_owed(int n)\n{\n\t(void)n;\n\treturn (0);\n}\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-97/tests/ex00/placeholder.c"
printf 'char\n\t**cv_split(char *s)\n{\n\twhile (*s)\n\t\ts++;\n\treturn (0);\n}\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-97/tests/ex01/split_copy.c"
printf 'char\t**cv_split(char *s);\n\nint\tmain(void)\n{\n\treturn (cv_split("x") != 0);\n}\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-97/tests/ex01/main_harness.c"
_cv_stdio='#include <stdio.h>\n\nvoid\tft_putchar(char c)\n{\n\tfputc(c, stdout);\n}\n'
# shellcheck disable=SC2059 # the format is the fixture, kept in one place
printf "$_cv_stdio" > "$WORK/cv/c-piscine-reloaded/c-piscine-reloaded/tests/ft_putchar.c"
# shellcheck disable=SC2059 # the format is the fixture, kept in one place
printf "$_cv_stdio" > "$WORK/cv/c-piscine/c-piscine-c-97/tests/ft_putchar.c"
# The Rust toolchain and the i686 core the grader's functions are compiled
# against are one version (tools/grader_lib.bzl): rustc loads a core only
# from its own version, so a bump of one download alone is reported. Here the
# toolchain says 1.2.3 and the rust-std 1.2.4.
printf 'rust.toolchain(\n    edition = "2021",\n    versions = ["1.2.3"],\n)\nhttp_archive(\n    name = "rust_std_i686_musl",\n    strip_prefix = "rust-std-1.2.4-i686-unknown-linux-musl/x",\n    urls = ["https://example.invalid/rust-std-1.2.4-i686-unknown-linux-musl.tar.xz"],\n)\n' \
	> "$WORK/cv/MODULE.bazel"
# The interpreter, named at three sites: python.defaults and python.toolchain
# agree with the python row (3.9.1), pip.parse names another (3.9.2).
printf 'python.defaults(python_version = "3.9.1")\npython.toolchain(python_version = "3.9.1")\npip.parse(\n    hub_name = "cv",\n    python_version = "3.9.2",\n)\n' \
	>> "$WORK/cv/MODULE.bazel"
# And tools/pins.tsv states both versions, held to MODULE.bazel like zig's:
# its rustc row agrees with the toolchain (1.2.3), its rust-std row names a
# version MODULE.bazel fetches nowhere (1.2.5).
printf 'rustc\tfetched\trustc 1.2.3 (0 2026-01-01)\trustc --version\tMODULE.bazel\nrust-std-i686\tfetched\t1.2.5\t-\tMODULE.bazel\npython\tfetched\tPython 3.9.1\tpython3 --version\tMODULE.bazel\n' \
	> "$WORK/cv/tools/pins.tsv"

# A script rendering bytes with an escape of its own, in each form it can
# take -- a \x before a formatted hex byte, a caret before a byte plus 64, a
# class of control bytes replaced, sed's `l` -- beside the one renderer and a
# comment that names a form; and a grep and a sed that write a tab as \t
# inside [ ], beside a grep -P, an awk program and [[:blank:]], which are not.
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_render.sh
	cat <<'PROBE_RENDER'
require awk cmp od sed tr
awk '{ printf "\\x%02x", 1 }' "$1"
awk '{ print "^" sprintf("%c", 1 + 64) }' "$1"
sed 's/[[:cntrl:]]/?/g' "$1"
sed -n '1,25l' "$1"
# sed -n '1,25l' is how it used to be shown
awk "$RL_AWK_VIS"'{ print rl_vis_exact($0) }' "$1"
od -An -c "$1"
x=$(od -An -tx1 -v -j 16 -N 16 "$1")
x=$(cmp -l "$1" "$2" | awk '{ print $1; exit }')
x=$(cmp "$1" "$2" 2> /dev/null | sed -n 's/.* byte \([0-9]*\).*/\1/p')
x=$(od -t c "$1")
# od -c "$1" is how it used to be shown
x=$(od -An -tx1 -N4 "$1" | tr -d ' ')
cmp -s "$1" "$2" || echo "$x"
PROBE_RENDER
} > "$WORK/cv/tools/probe_render.sh"
# A diff shown raw, in each form a runner wrote one -- the pinned diff a
# runner is handed, a bare diff, after an `if !` and in a command
# substitution -- beside the library's rl_udiff, a diff that only answers
# whether two files differ (-q, stdout to /dev/null), cmp, `git diff`, and
# the word "diff" as an argument (V51).
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_udiff.sh
	printf 'require cmp diff git\n. "$RL_LIB"\n'
	printf '# conventions: harness tool DIFF -- the pinned diff, which compares two files\n'
	printf '"$DIFF" -a -u -L want -L got "$1" "$2"\n'
	printf 'diff -u "$1" "$2"\n'
	printf 'if ! diff "$1" "$2"; then :; fi\n'
	printf 'rl_udiff "$DIFF" "$1" "$2" expected got\n'
	printf 'diff -q "$1" "$2" || :\n'
	printf '"$DIFF" "$1" "$2" > /dev/null 2>&1 || :\n'
	printf 'cmp -s "$1" "$2" || :\n'
	printf 'git -C "$1" diff --name-only\n'
	printf 'cap "diff" diff --version\n'
	printf 'x=$("$DIFF" -u "$1" "$2" 2> /dev/null)\n'
	printf '# diff -u "$1" "$2" is how it used to be shown\n'
} > "$WORK/cv/tools/probe_udiff.sh"
# A legend of the renderer's marks written as fixed text, in a here-document
# and in a printf, beside the same words in a comment, a message marked as
# stating the notation for a harness author (over its continuation lines),
# the library's own legend and a sentence that names a tab with no mark.
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_legend.sh
	cat <<'PROBE_LEGEND'
require cat
. "$RL_LIB"
cat << 'LEGEND'
  \t is a tab, \\ a backslash, and \xHH any other byte.
LEGEND
printf '%s\n' '  (\x24 a dollar)'
# \\ a backslash, in a comment, is no legend
# conventions: notation, not a legend -- a message to the harness author
printf '%s\n' \
	"  in the notation (\\\\ a backslash, \\n a line" \
	"  break, \\t a tab)" >&2
rl_vis_legend "$1"
echo "  a tab between two values"
printf '%s\n' '  \n a newline'
PROBE_LEGEND
} > "$WORK/cv/tools/probe_legend.sh"
# A word of a test's args quoted by hand, beside shell_word's own body and a
# comment that names the idiom: only the hand-written quoting is reported --
# an apostrophe replaced, a '$' doubled, and the naive forms that open or
# close a single quote around a value, which split at its first apostrophe.
# Possessives and an apostrophe inside a word are no quote.
cat > "$WORK/cv/tools/probe_quote.bzl" <<'PROBE_QUOTE'
def shell_word(text):
    return "'" + text.replace("$", "$$").replace("'", "'\\''") + "'"

def toy(name):
    # name.replace("'", "") in a comment quotes nothing
    return ["--why", "'" + name.replace("'", "'\"'\"'") + "'"]

def toy_naive(name, n):
    a = ["--why", "'%s'" % name]
    b = ["--why", "'" + name + "'"]
    c = ["--expr", n.replace("$", "$$")]
    d = ["--why", "--x='%r'" % name]
    e = "%s's own fixtures" % name
    f = name + "'s files"
    g = "it's " + name
    return a + b + c + d + [e, f, g]
PROBE_QUOTE
# A project whose contract tools/units.awk cannot read: its entries come from
# a comprehension, so no "NN": exercise( line names the exercise it tests.
mkdir -p "$WORK/cv/c-piscine/c-piscine-c-89/tests/ex00"
: > "$WORK/cv/c-piscine/c-piscine-c-89/tests/ex00/expected.txt"
cat > "$WORK/cv/c-piscine/c-piscine-c-89/BUILD.bazel" <<'PROBE_CONTRACT'
subject(
    grader = "moulinette",
    group = False,
    exercises = {n: exercise(page = 1, dir = "ex%s/" % n, files = [], allowed = None) for n in ["00"]},
)
PROBE_CONTRACT
mkdir -p "$WORK/cv/c-piscine/c-piscine-c-88/tests/ex00" "$WORK/cv/c-piscine/c-piscine-c-88/tests/ex01"
: > "$WORK/cv/c-piscine/c-piscine-c-88/tests/ex00/expected.txt"
: > "$WORK/cv/c-piscine/c-piscine-c-88/tests/ex01/expected.txt"
cat > "$WORK/cv/c-piscine/c-piscine-c-88/BUILD.bazel" <<'PROBE_CONTRACT'
subject(
    grader = "moulinette",
    group = False,
    exercises = {
        "00": exercise(page = 1, dir = "ex00/", files = [], allowed = None),
        "01": exercise(
            page = 2,
            dir = "ex01/",
            files = [],
            allowed = None,
        ),
    },
)
PROBE_CONTRACT
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_blank.sh
	cat <<'PROBE_BLANK'
require awk grep sed
grep -q '^[ \t]*x' "$1"
sed -n 's/^[ \t]*//p' "$1"
grep -Pq '^[\t]x' "$1"
awk '/grep/ && /^[ \t]/' "$1"
grep -q '^[[:blank:]]*x' "$1"
PROBE_BLANK
} > "$WORK/cv/tools/probe_blank.sh"
# Test programs that write an escape of their own, in a made-up module: one
# whose c_function does not declare it (printf and putchar, beside a comment
# that only names the notation and a call that passes one as an input), one
# whose c_function does, a c_diff harness that exports_files also names,
# and a header no call names.
_cv_esc=c-piscine/c-piscine-c-98/tests
cat > "$WORK/cv/$_cv_esc/ex00/test_esc.c" <<'PROBE_ESC'
#include <stdio.h>
/* Shows a NUL as "\\0" -- a comment, not a print. */
int	main(void)
{
	ft_puts("\\x41");
	printf("\\0");
	putchar('\\');
	ft_putchar('\\');
	return (0);
}
PROBE_ESC
printf '#include <stdio.h>\nint\tmain(void)\n{\n\tprintf("\\\\x00");\n}\n' \
	> "$WORK/cv/$_cv_esc/ex01/test_esc_ok.c"
printf '#include <stdio.h>\nint\tmain(void)\n{\n\tprintf("\\\\n");\n}\n' \
	> "$WORK/cv/$_cv_esc/ex01/diff_esc.c"
printf 'static void\tshow(void)\n{\n\tprintf("\\\\\\\\");\n}\n' \
	> "$WORK/cv/$_cv_esc/ex01/orphan_esc.h"
# And one that is a symlink, as every file of a runfiles tree is under
# `bazel test` (V23): the rule found its files with -type f and read
# nothing there. Its target lies outside tests/, so only the link is read.
mkdir -p "$WORK/cv_esc_src" "$WORK/cv/$_cv_esc/ex02"
printf '#include <stdio.h>\nint\tmain(void)\n{\n\tprintf("\\\\x41");\n}\n' \
	> "$WORK/cv_esc_src/linked_esc.c"
ln -s "$WORK/cv_esc_src/linked_esc.c" "$WORK/cv/$_cv_esc/ex02/test_link.c"
# And one that writes the notation through tools/notation.h, with no escape
# of its own in sight: its include and its nt_ call write one. Reported
# under a c_function without escaped_values (test_nt.c), quiet under one
# with it (test_nt_ok.c, the same file).
mkdir -p "$WORK/cv/$_cv_esc/ex03"
printf '#include <stdio.h>\n#include "notation.h"\n\nint\tmain(void)\n{\n\tnt_puts("a\\tb");\n\tprintf("\\n");\n\treturn (0);\n}\n' \
	> "$WORK/cv/$_cv_esc/ex03/test_nt.c"
cp "$WORK/cv/$_cv_esc/ex03/test_nt.c" "$WORK/cv/$_cv_esc/ex03/test_nt_ok.c"
# The same through tools/fd_capture.h, whose rows are in the notation: its
# include alone writes one (test_fc.c, reported at line 1).
printf '#include "fd_capture.h"\n\nint\tmain(void)\n{\n\tfc_start();\n\tfc_show("x");\n\tfc_stop();\n\treturn (0);\n}\n' \
	> "$WORK/cv/$_cv_esc/ex03/test_fc.c"
# A reading's main is judged by its own case, never by the call's flag (V214):
# a reading's target is handed --escaped-values only where its case says
# "escaped_values". Reported: read_esc.c, a reading's main in a call that
# says escaped_values = True while its own case does not. Quiet: read_esc_ok.c,
# whose case says it in the same call, and read_esc_own.c, whose case says
# it in a call that does not.
printf '#include <stdio.h>\nint\tmain(void)\n{\n\tprintf("\\\\x%%02x", 1);\n}\n' \
	> "$WORK/cv/$_cv_esc/ex01/read_esc.c"
cp "$WORK/cv/$_cv_esc/ex01/read_esc.c" "$WORK/cv/$_cv_esc/ex01/read_esc_ok.c"
cp "$WORK/cv/$_cv_esc/ex01/read_esc.c" "$WORK/cv/$_cv_esc/ex00/read_esc_own.c"
# Every call that names the file must declare the notation, not one of them:
# both_esc.c is the test of a c_function that says escaped_values = True and
# the main of a c_header case, which no flag reaches. Reported.
cp "$WORK/cv/$_cv_esc/ex01/read_esc.c" "$WORK/cv/$_cv_esc/ex01/both_esc.c"
{
	printf 'c_function(\n    num = "00",\n    fn = "ft_a",\n    test = "test_esc.c",\n    labeled = True,\n'
	printf '    readings = [{"name": "own", "main": "read_esc_own.c", "expected": "o.txt",\n'
	printf '                 "labeled": True, "escaped_values": True, "level": 2}],\n)\n\n'
	printf 'c_function(\n    num = "01",\n    fn = "ft_b",\n    test = "test_esc_ok.c",\n'
	printf '    labeled = True,\n    escaped_values = True,\n'
	printf '    readings = [\n        {"name": "r", "main": "read_esc.c", "expected": "r.txt", "labeled": True, "level": 2},\n'
	printf '        {\n            "name": "s",\n            "main": "read_esc_ok.c",\n'
	printf '            "expected": "s.txt",\n            "labeled": True,\n'
	printf '            "escaped_values": True,\n            "level": 2,\n        },\n    ],\n)\n\n'
	printf 'c_diff(num = "01", fn = "ft_b", harness = "diff_esc.c", oracle_fn = "o")\n\n'
	printf 'exports_files(["tests/ex01/diff_esc.c"], visibility = ["//tools/tests:__pkg__"])\n\n'
	printf 'c_function(num = "02", fn = "ft_c", test = "test_link.c", labeled = True)\n\n'
	printf 'c_function(num = "03", fn = "ft_n", test = "test_nt.c", labeled = True)\n\n'
	printf 'c_function(num = "03", fn = "ft_f", test = "test_fc.c", labeled = True)\n\n'
	printf 'c_function(\n    num = "03",\n    fn = "ft_m",\n    test = "test_nt_ok.c",\n'
	printf '    labeled = True,\n    escaped_values = True,\n)\n\n'
	printf 'c_function(\n    num = "01",\n    fn = "ft_e",\n    test = "both_esc.c",\n'
	printf '    labeled = True,\n    escaped_values = True,\n)\n\n'
	printf 'c_header(\n    num = "01",\n    main = "hdr_main.c",\n'
	printf '    cases = [{"name": "both", "main": "both_esc.c", "expected": "b.txt"}],\n)\n'
} > "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"

cv_submit() {
	printf '#!/bin/sh\n'
	printf "REMOTES='\n"
	for _m in $1; do printf '%s=REPLACE_ME\n' "$_m"; done
	printf "'\n"
}
cv_submit "$_cv_mods" > "$WORK/cv/tools/submit.sh"

# A sanitizer's options set by hand (finding 051): the keys drift, and the
# symbolizer is whatever a PATH search finds. rl_sanitizers is the one place.
_san="ASAN"
printf '#!/bin/sh\nset -u\n%s_OPTIONS="detect_leaks=0:${%s_OPTIONS:-}"\nexport %s_OPTIONS\n' \
	"$_san" "$_san" "$_san" > "$WORK/cv/tools/probe_sanopts.sh"
printf '#!/bin/sh\nset -u\n# conventions: runs no student code -- a probe\n# conventions: shows no sanitizer report -- a probe\nrl_sanitizers "$T/sym"\n' \
	> "$WORK/cv/tools/probe_sanopts_ok.sh"
# A runner that looks for a sanitizer's report itself (V50): a grep of the
# banners and an awk pattern, beside rl_sanitized, a sentence that names the
# sanitizer and a comment.
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_sanrep.sh
	cat <<'PROBE_SANREP'
require awk grep
# conventions: runs no student code -- a probe
grep -qE 'AddressSanitizer|UndefinedBehaviorSanitizer' "$1" && echo found
if rl_sanitized "$1"; then echo found; fi
echo "  The harness was built with AddressSanitizer and UBSan."
awk '/runtime error:/ { n++ } END { print n + 0 }' "$1"
# grep -q AddressSanitizer is how it used to be asked
PROBE_SANREP
} > "$WORK/cv/tools/probe_sanrep.sh"
# A runner that symbolises a sanitizer's report (rl_sanitizers with a
# symbolizer) and is in no _SYMBOLIZER_RUNNERS row: _test() would never ask a
# test of it for --symbolizer. The fixture has no defs.bzl, so no row at all.
printf '#!/bin/sh\nset -u\n# conventions: runs no student code -- a probe\n# conventions: shows no sanitizer report -- a probe\nrl_sanitizers "$T/sym" "$SYMBOLIZER" "$SYMBOLIZER_LIB"\n' \
	> "$WORK/cv/tools/probe_sym_unlisted.sh"
# A runner that sets the sanitizers up and never asks how its run ended (the
# review of V50: rust_diff.sh's replay before V50, asan_check.sh before V70),
# beside one that asks rl_sanitized, one that runs through rl_mem_run, and
# one marked as showing no report. Each names rl_sanitized in a comment, which
# is no asking. And a module's own tests/*.sh that looks for a report itself:
# the rule on that read tools/*.sh alone.
{
	printf '#!/bin/sh\nset -u\n# conventions: runs no student code -- a probe\n'
	printf '# rl_sanitized is not asked here\nrl_sanitizers "$T/sym"\nrl_run "$1" 2> "$T/err"\n'
} > "$WORK/cv/tools/probe_sanask.sh"
{
	printf '#!/bin/sh\nset -u\n# conventions: runs no student code -- a probe\n'
	printf 'rl_sanitizers "$T/sym"\nrl_run "$1" 2> "$T/err"\nrl_classify "$?"\nrl_sanitized "$T/err" || :\n'
} > "$WORK/cv/tools/probe_sanask_ok.sh"
{
	printf '#!/bin/sh\nset -u\n# conventions: runs no student code -- a probe\n'
	printf 'rl_sanitizers "$T/sym"\nrl_mem_run asan "$1"\n'
} > "$WORK/cv/tools/probe_sanask_mem.sh"
{
	printf '#!/bin/sh\nset -u\n# conventions: runs no student code -- a probe\n'
	printf '# conventions: shows no sanitizer report -- a gate whose report is never shown\n'
	printf 'rl_sanitizers "$T/sym"\nrl_run "$1" > /dev/null 2>&1\n'
} > "$WORK/cv/tools/probe_sanask_gate.sh"
_sanw="AddressSanitizer"
printf '#!/bin/sh\nset -u\ngrep -q %s "$1" && echo found\n' "$_sanw" \
	> "$WORK/cv/$_cv_esc/probe_sanrep_mod.sh"
# A runner that shows a memory report and keeps a file through a plain
# rl_save, where rl_keep_input would record the pair its report names the
# input by (V147): at the top level, in a function, and one whose marker is
# not on the line above. Beside one that keeps its input with rl_keep_input
# and marks the rl_save keeping its replay line, and one with an rl_save and
# no memory report, whose rl_mem_report is only in a comment.
{
	printf '#!/bin/sh\nset -u\nrl_save "$WORK/map" case-1.map || :\n'
	printf 'keep() {\n\trl_save "$1" "$2"\n}\n'
	printf '# conventions: rl_save keeps no input -- a marker one line too far\n\n'
	printf 'rl_save "$WORK/replay" replay-1.sh || :\nrl_mem_report\n'
} > "$WORK/cv/tools/probe_keepin_check.sh"
{
	printf '#!/bin/sh\nset -u\nrl_keep_input "$WORK/map" case-1.map || :\n'
	printf '# rl_save "$WORK/map" case-1.map, said in a comment\n'
	printf '# conventions: rl_save keeps no input -- the replay line\n'
	printf 'rl_save "$WORK/replay" replay-1.sh || :\nrl_mem_report\n'
} > "$WORK/cv/tools/probe_keepin_ok_check.sh"
printf '#!/bin/sh\nset -u\nrl_save "$WORK/map" case-1.map || :\n# rl_mem_report is not called here\n' \
	> "$WORK/cv/tools/probe_keepin_noreport_check.sh"
# A Rust compile that lets rustc's warnings through: they reached a student's
# first run as "1 warning emitted" in the middle of a cold build (a needless
# `mut` in the oracle). Two invented packages and a rule file: a rust_binary
# whose flags deny nothing (its comment names the flag, which is not code), one
# that denies warnings, and a .bzl whose action runs the toolchain's rustc
# with a flag list that does not.
mkdir -p "$WORK/cv/rustwarn" "$WORK/cv/rustquiet"
printf 'rust_binary(\n    name = "w",\n    # "-Dwarnings" belongs here\n    rustc_flags = ["-Copt-level=2"],\n)\n' \
	> "$WORK/cv/rustwarn/BUILD.bazel"
printf 'rust_binary(\n    name = "q",\n    rustc_flags = [\n        "-Copt-level=2",\n        "-Dwarnings",\n    ],\n)\n' \
	> "$WORK/cv/rustquiet/BUILD.bazel"
printf '_FLAGS = ["-Copt-level=2"]\n\ndef _r(ctx, tc):\n    ctx.actions.run(\n        executable = tc.rustc,\n        arguments = _FLAGS,\n    )\n' \
	> "$WORK/cv/tools/probe_rustc.bzl"
# Each compile, not each file: a second target of a package whose first one
# denies warnings (passed by the per-file rule), beside a target and a rule
# that take the flag from a list of their file's.
mkdir -p "$WORK/cv/rusttwo" "$WORK/cv/rustlist"
printf 'rust_binary(\n    name = "a",\n    rustc_flags = ["-Dwarnings"],\n)\n\nrust_test(\n    name = "t",\n    crate = ":a",\n)\n' \
	> "$WORK/cv/rusttwo/BUILD.bazel"
printf '_F = [\n    "-Copt-level=2",\n    "-Dwarnings",\n]\n\nrust_binary(\n    name = "l",\n    rustc_flags = _F,\n)\n' \
	> "$WORK/cv/rustlist/BUILD.bazel"
printf '_FLAGS = [\n    "-Dwarnings",\n]\n\ndef _r(ctx, tc):\n    ctx.actions.run(\n        executable = tc.rustc,\n        arguments = _FLAGS,\n    )\n' \
	> "$WORK/cv/tools/probe_rustc_ok.bzl"
# Two pages linking each other (V40): a relative link names a file or folder
# from its page's folder, an anchor a heading's id as GitHub makes it -- an em
# dash dropped, a code span's _ kept, emphasis gone, a repeated heading's id
# numbered -- or an <a id>. Three links are broken: a missing page, an
# anchor no heading has, and a path above the tree; the rest, and what code
# or a scheme holds, are not. V40's review added three headings whose ids
# GitHub makes as the rule now does -- a section sign, an arrow and a
# multiplication sign dropped, a capital of Latin-1 and of Latin Extended-A
# lowered (a heading like "OPEN — after the restructure (§22)" has the
# first shape) -- and a footnote's definition, which is no link.
mkdir -p "$WORK/cv/docs"
printf '%s\n' '# Linked' '' '## Part one — the toolkit' '' '## The `_TOY_TABLE` list' '' \
	'## _Emphasis_ and toy_name' '' '## Twice' '' '## Twice' '' '<a id="kept"></a>' '' \
	'## OPEN — after the restructure (§22), done' '' '## Arrows → here' '' '## Ça × Œuvre' \
	> "$WORK/cv/docs/linked.md"
printf '%s\n' '# Links' '' \
	'[a](linked.md) [b](linked.md#part-one--the-toolkit) [c](linked.md#the-_toy_table-list)' \
	'[d](linked.md#emphasis-and-toy_name) [e](linked.md#twice-1) [f](linked.md#kept) [g](#links)' \
	'[h](../tools) [i](https://example.invalid/x#y) `[j](nowhere.md)`' '' '```' '[k](nowhere.md)' '```' '' \
	'[ref]: ../tools/' '[gone](missing.md)' '[bad](linked.md#part-one-the-toolkit)' \
	'[up](../../outside.md)' '[l](linked.md#open--after-the-restructure-22-done)' \
	'[m](linked.md#arrows--here) [n](linked.md#ça--œuvre)' '' '[^1]: A footnote, no link.' \
	> "$WORK/cv/docs/links.md"
# The toy tree's one TODO.md, written by this one statement for every block
# that reads it (V26: the line the template build's arms read, below, was
# once a second write of the file, each block green only while its own run
# came first).
{
	printf '# TODO\n\n**A lead** (today).\n- *Seen:* x\n'
} > "$WORK/cv/TODO.md"
# ...and the toy's one HISTORY.md.
printf '%s\n' '# History' '' '## TO VERIFY leads, settled' '' '- **V30, settled** -- FIXED.' \
	> "$WORK/cv/HISTORY.md"
# A selftest whose two blocks write one toy exercise's check script, which is
# how two groups of conventions arms once judged each other's file: ex05's is
# written twice; ex06's once, and ex07's appended to twice, which is no
# rewrite. The lines are a selftest's, shaped as this file writes its toys.
{
	printf '%s\n' '#!/bin/sh' "printf 'a\\n' > \"\$_cv99/ex05/check.sh\""
	printf '%s\n' "printf 'b\\n' > \"\$_cv99/ex06/check.sh\""
	printf '%s\n' "printf 'c\\n' >> \"\$_cv99/ex07/check.sh\""
	printf '%s\n' "printf 'd\\n' >> \"\$_cv99/ex07/check.sh\""
	printf '%s\n' "printf 'e\\n' > \"\$_cv99/ex05/check.sh\""
	# ...and arms calling helpers the file does not define, which run as
	# "not found" and drop out of the tally (V47): one at the start of a
	# line, one behind `! st_mine ||`, one as an `if`'s condition. A helper
	# it defines, and one a comment names, are not reported. (The names are
	# spelt through $_cvw so this file's own lines call none of them.)
	_cvw=want
	printf '%s\n' 'want_here() { :; }' 'want_here "a" -- true' "${_cvw}_nothing \"b\" -- true" \
		"! st_mine || ${_cvw}_gone \"c\" -- true" "if later_absent \"d\" -- true; then :; fi" \
		"# ${_cvw}_ghost is what an old arm called"
	# ...and a fixture tree's TODO.md written by two statements (V26), beside
	# a HISTORY.md written once and appended to; and a plan's file under its
	# todo/ written by two, beside another plan's written by one; and a third
	# plan's written by two through a variable holding its folder, $_cvl and
	# ${_cvl}, which a fourth's, written after _cvl names another folder,
	# does not share.
	printf '%s\n' "printf 'a\\n' > \"\$WORK/cv/TODO.md\"" "printf 'b\\n' > \"\$WORK/cv/HISTORY.md\"" \
		"printf 'c\\n' >> \"\$WORK/cv/HISTORY.md\"" "printf 'd\\n' > \"\$WORK/cv/TODO.md\"" \
		"printf 'e\\n' > \"\$WORK/cv/todo/plans/p1.md\"" "printf 'f\\n' > \"\$WORK/cv/todo/plans/p2.md\"" \
		"printf 'g\\n' > \"\$WORK/cv/todo/plans/p1.md\"" '_cvl=todo/plans' \
		"printf 'h\\n' > \"\$WORK/cv/\$_cvl/p3.md\"" "printf 'i\\n' > \"\$WORK/cv/\${_cvl}/p3.md\"" \
		"printf 'j\\n' > \"\$WORK/cv/\$_cvl/p4.md\"" '_cvl=notes' "printf 'k\\n' > \"\$WORK/cv/\$_cvl/p4.md\""
	# ...and the toys a merge once gave two blocks (V37): ex90 written through
	# a loop's variable and by a statement of its own, ex91 made by two
	# statements (one a helper's, through its $1), ex92 named in two sections.
	# The loop's other toy, ex93, is used once (quiet).
	printf '%s\n' "for _e in ex90 ex93; do" "	printf 'f\\n' > \"\$_cv99/\$_e/diff_x.c\"" "done" \
		"printf 'g\\n' > \"\$_cv99/ex90/diff_x.c\"" "_mk() {" "	mkdir -p \"\$_cv99/\$1\"" "}" \
		"mkdir -p \"\$_cv99/ex91\"" "_mk ex91" "mkdir -p \"\$_cv99/ex92\""
	# ...and V37's review: a stderr capture (2>) and a capture of both
	# streams (&>) truncate a toy's file as > does (ex94, ex95), and a
	# helper written on one line that names a toy outright makes it where
	# it is defined (ex96, made there and by a statement of its own).
	printf '%s\n' "printf 'i\\n' > \"\$_cv99/ex94/out.txt\"" "true 2> \"\$_cv99/ex94/out.txt\"" \
		"printf 'j\\n' > \"\$_cv99/ex95/out.txt\"" "true &> \"\$_cv99/ex95/out.txt\"" \
		"_mk96() { mkdir -p \"\$_cv99/ex96\"; }" "mkdir -p \"\$_cv99/ex96\""
	# ...and a helper on one line continued with a backslash, the shape of
	# r2_run: read from its first line alone, it was a helper over many
	# lines, its first line dropped and its body run on to the next } (ex97,
	# made there and by a statement of its own; ex98's file, written
	# through its $1 by two calls).
	printf '%s\n' "_mk97() { mkdir -p \\" "	\"\$_cv99/ex97\"; }" "mkdir -p \"\$_cv99/ex97\"" \
		"_wr98() { printf 'k\\n' > \"\$_cv99/ex98/\$1\" \\" "	2> /dev/null; }" "_wr98 out.txt" "_wr98 out.txt"
	# ...and the fixture trees two sections share (V93): tt_shared named
	# outright in one section and through a loop's variable in the next,
	# tt_looped through a loop's variable in both, tt_alias through a
	# variable holding its path. Quiet: tt_own and tt_loop, each one
	# section's (tt_own named in the other only in a comment), cv and
	# tt_pre (named before the first section) in both, and tt_file.log, a
	# file, which is no tree.
	printf '%s\n' "mkdir -p \"\$WORK/tt_pre\" \"\$WORK/tt_premk\" \"\$WORK/tt_prer\""
	# (and the trees V154's writes go into, below.)
	printf '%s\n' "mkdir -p \"\$WORK/tt_precp\" \"\$WORK/tt_pregit\" \"\$WORK/tt_pretouch\" \"\$WORK/tt_preln\"" \
		"mkdir -p \"\$WORK/tt_pretee\" \"\$WORK/tt_prerm\" \"\$WORK/tt_premv\" \"\$WORK/tt_presed\"" \
		"mkdir -p \"\$WORK/tt_presub\" \"\$WORK/tt_pretest\" \"\$WORK/tt_preif\" \"\$WORK/tt_prebq\"" \
		"mkdir -p \"\$WORK/tt_preshift\""
	printf '%s\n' "# ------------------------------------------------------- another section" \
		"printf 'h\\n' > \"\$_cv99/ex92/check.sh\""
	printf '%s\n' "mkdir -p \"\$WORK/tt_shared/tools\" \"\$WORK/tt_own\"" ": > \"\$WORK/tt_own/a\"" \
		"_tt=\"\$WORK/tt_alias\"" "mkdir -p \"\$_tt/d\"" \
		"for _t in tt_looped; do : > \"\$WORK/\$_t/a\"; done" ": > \"\$WORK/tt_pre/a\"" \
		": > \"\$WORK/cv/a\"" ": > \"\$WORK/tt_file.log\""
	printf '%s\n' "# ------------------------------------------------------- a third section" \
		"# \"\$WORK/tt_own/b\", in a comment" "for _t in tt_loop tt_shared tt_looped; do" \
		"	: > \"\$WORK/\$_t/b\"" "done" ": > \"\$_tt/b\"" \
		": > \"\$WORK/tt_pre/b\"" ": > \"\$WORK/cv/b\"" "cat \"\$WORK/tt_file.log\""
	# ...and V93's review: a variable that held a tree's path in one
	# section and is a loop's variable, or read's, in another holds a
	# word there, and names no tree (tt_var, tt_read: quiet).
	printf '%s\n' "_tv=\"\$WORK/tt_var\"" ": > \"\$_tv/a\"" "_tr=\"\$WORK/tt_read/a\"" ": > \"\$_tr\""
	printf '%s\n' "# ------------------------------------------------------- a fourth section" \
		"for _tv in x y; do echo \"\$_tv\"; done" "read -r _tr < /dev/null" "echo \"\$_tr\""
	# ...and the trees a helper names (V93's review): tt_arg and tt_argl
	# through its positional parameter (a word the call passes, the loop's
	# word for "$_a"), tt_body outright in its body, each called in two
	# sections. Quiet: tt_only, named by a helper of the fourth section the
	# fifth alone calls, and tt_not, which the fifth passes to printf beside
	# the helper's name, no call. The other report: tt_pre (above) and
	# tt_premk are written into from a section, though made before the
	# first; tt_prer, only read there, and cv are not.
	printf '%s\n' "_tt_mk() {" "	_d=\$1" "	mkdir -p \"\$WORK/\$_d\"" "	: > \"\$WORK/\$1/f\"" \
		"	: > \"\$WORK/tt_body/x\"" "}" "_tt_only() { : > \"\$WORK/tt_only/x\"; }" \
		"_tt_mk tt_arg" "for _a in tt_argl; do _tt_mk \"\$_a\"; done" ": > \"\$WORK/tt_not/a\""
	printf '%s\n' "# ------------------------------------------------------- a fifth section" \
		"want_here \"x\" -- _tt_mk tt_arg" "want_here \"y\" -- \\" "	_tt_mk tt_argl" \
		"_tt_only" "printf '%s\\n' _tt_mk tt_not" "mkdir -p \"\$WORK/tt_premk/d\"" \
		"cat \"\$WORK/tt_prer/a\""
	# ...and a helper whose usage comment shows a here-document (V170):
	# the <<msg there opens none, so what follows is read, ex89 made by two
	# statements and tt_hdc named in the fifth section and a sixth.
	printf '%s\n' "_h89() {  # _h89 TEXT <<msg" "	printf '%s\\n' \"\$1\"" "}" \
		"mkdir -p \"\$_cv99/ex89\"" "mkdir -p \"\$_cv99/ex89\"" ": > \"\$WORK/tt_hdc/a\"" \
		"# ------------------------------------------------------- a sixth section" \
		": > \"\$WORK/tt_hdc/b\""
	# ...and the other ways a section writes into a tree made before the
	# first (V154): cp, git init, touch, ln, tee, rm, mv and sed -i; a helper
	# called in a quoted $( ), in a test's $( ) and an if's, and in
	# backticks; and one that shifts before it reads $1. Each is reported.
	printf '%s\n' "cp a \"\$WORK/tt_precp/\"" "git init -q \"\$WORK/tt_pregit/r\"" \
		"touch \"\$WORK/tt_pretouch/a\"" "ln -s a \"\$WORK/tt_preln/b\"" \
		"echo x | tee \"\$WORK/tt_pretee/a\" > /dev/null" "rm -f \"\$WORK/tt_prerm/a\"" \
		"mv a \"\$WORK/tt_premv/\"" "sed -i 's/a/b/' \"\$WORK/tt_presed/a\"" \
		"_h154() {" "	: > \"\$WORK/\$1/x\"" "}" "_v=\"\$(_h154 tt_presub)\"" \
		"[ \"\$(_h154 tt_pretest)\" = x ]" "if [ -n \"\$(_h154 tt_preif)\" ]; then :; fi" \
		"_w=\`_h154 tt_prebq\`" \
		"_s154() {" "	shift" "	: > \"\$WORK/\$1/y\"" "}" "_s154 skip tt_preshift"
} > "$WORK/cv/tools/tests/selftest_toys.sh"
# A selftest's toys are built by toy_cc (V287): a "$CC" at the head of a
# command is reported, its words thrown away or kept in a file only printed,
# on a line of its own or after && on a line before, in a driver or a
# section, and so is the pinned gcc's or any "$..._CC"; a comment naming
# that form, a toy_cc call (with --cc too), an argument, an assignment and
# a probe marked as one are not. And a skip line is
# st_unsupplied's or st_skipped's: one printed by hand is reported, with a
# reason or without, and a call of either (its verdict on a continuation
# line) and an arm's quoted words are not. A section that reads _st_mine
# is reported too, and one whose comment names it is not.
printf '%s\n' '#!/bin/sh' '"$CC" -w -o "$WORK/tc_lost" "$WORK/tc_lost.c" 2> /dev/null' \
	'# "$CC" -o "$WORK/tc_note" "$WORK/tc_note.c" 2> /dev/null' \
	'"$CC" -o "$WORK/tc_kept" "$WORK/tc_kept.c" > "$WORK/tc_kept.err" 2>&1 || cat "$WORK/tc_kept.err"' \
	'toy_cc "$WORK/tc_mine" -w "$WORK/tc_mine.c"' \
	'toy_cc "$WORK/tc_first" -w "$WORK/tc_first.c" &&' \
	'	"$CC" -w -o "$WORK/tc_chain" "$WORK/tc_chain.c" \' \
	'		2> /dev/null' \
	'printf "exec %s -m32\n" \' \
	'	"$CC" > "$WORK/tc_word"' \
	'X_CC="$CC" sb --cc "$CC" --out "$WORK/tc_arg"' \
	'# conventions: a probe -- whether the box links a sanitized program at all' \
	'if "$CC" -fsanitize=address -o "$WORK/tc_probe" "$WORK/tc_probe.c" > /dev/null 2>&1; then :; fi' \
	'if "$CC" -fsanitize=address -o "$WORK/tc_bare" "$WORK/tc_bare.c" 2> /dev/null; then :; fi' \
	'printf "  %-52s %s\n" "toy: (no input)" "skipped"' \
	'st_unsupplied "toy: (no input either)" \' \
	'	"not run here (no input)" "no input was supplied."' \
	"want_out \"toy: a skip is said\" 'skipped' -- true" \
	'printf "  %-52s %s\n" "toy: (no tool)" "skipped (this box has no tool)"' \
	'st_skipped "toy: (no tool either)" \' \
	'	"skipped (this box has no tool)"' \
	'! st_mine || { "$GCC" -B"$WORK/tc_gccb/" -c -o "$WORK/tc_gcc.o" "$WORK/tc_gcc.c" 2> /dev/null &&' \
	'	toy_cc "$WORK/tc_gcc" "$WORK/tc_gcc.o"; }' \
	'toy_cc --cc "$GCC" "$WORK/tc_gcc.o" -c "$WORK/tc_gcc.c"' \
	'"$I32_CC" -o "$WORK/tc_i32" "$WORK/tc_i32.c"' > "$WORK/cv/tools/tests/selftest_slow_toys.sh"
# Every head a command takes (V287 again): after elif, while or until,
# behind env NAME=VALUE, timeout N, bounded N or an assignment, and "${CC}"
# or a bare $CC, each reported; an argument behind env, an assignment's
# quoted words, a printf's quoted text, an argument inside $( ) and
# toy_cc's own body are not.
printf '%s\n' '#!/bin/sh' \
	'if [ "$SAN" != 1 ]; then :; elif "$CC" -fsanitize=address -o "$WORK/th_elif" "$WORK/th_elif.c" 2> /dev/null; then :; fi' \
	'while "$CC" -o "$WORK/th_while" "$WORK/th_while.c" 2> /dev/null; do break; done' \
	'until "$CC" -o "$WORK/th_until" "$WORK/th_until.c" 2> /dev/null; do break; done' \
	'env ASAN_OPTIONS=detect_leaks=0 "$CC" -o "$WORK/th_env" "$WORK/th_env.c" 2> /dev/null' \
	'timeout 20 "$CC" -o "$WORK/th_timeout" "$WORK/th_timeout.c" 2> /dev/null' \
	'bounded 20 "$CC" -o "$WORK/th_bounded" "$WORK/th_bounded.c" 2> /dev/null' \
	'"${CC}" -o "$WORK/th_braced" "$WORK/th_braced.c" 2> /dev/null' \
	'$CC -o "$WORK/th_bare" "$WORK/th_bare.c" 2> /dev/null' \
	'CFLAGS=-w "$CC" -o "$WORK/th_assign" "$WORK/th_assign.c" 2> /dev/null' \
	'env A=1 "$SH" "$TOOLS/student_build.sh" --cc "$CC" --out "$WORK/th_arg"' \
	'TH_PIN="--cc $CC --cc-under $CC"' \
	"printf '%s\\n' 'elif \"\$CC\" -o x x.c; then' > \"\$WORK/th_text\"" \
	'_th=$(th_abs "$CC")' \
	'toy_cc() {' \
	'	"$CC" "$@" -o "$_tc_out" > "$_tc_err" 2>&1' \
	'}' > "$WORK/cv/tools/tests/selftest_toy_heads.sh"
mkdir -p "$WORK/cv/tools/tests/selftest_sections"
printf '%s\n' '# ---- toys' '"$CC" -o "$WORK/tc_section" "$WORK/tc_section.c"' \
	'[ "$_st_mine" = 1 ] || exit 0' '# not _st_mine: st_mine is the question' \
	> "$WORK/cv/tools/tests/selftest_sections/toys.sh"
# The arm helpers' one home (tools/tests/selftest_lib.sh): a toy library
# and a toy driver that sources it. The driver calls the library's helper,
# which it does not define itself (quiet: the library is read in the line's
# place), defines its own want_red, and writes a stand-in reference's
# here-document by hand (each reported); the library's own definition and
# here-document are not. It calls want_spaced too, which the library
# spells `name () {` (quiet as well). The driver's copies of two more
# library helpers are reported, each spelt as the library spells it:
# st_inblock indented in a block (a tab, as the perf block's are),
# st_libonly as `name () {`. The here-document's opening is spelt with @P@
# for each %, so this file writes none of its own.
printf '%s\n' '# shellcheck shell=sh' 'want_fromlib() { :; }' \
	"printf '#!/bin/sh\\ncat <<@P@sEOF@P@s\\n' \"'\" \"'\"" 'st_libonly () { :; }' \
	'if true; then' "$(printf '\t')st_inblock() { :; }" 'fi' 'want_spaced () { :; }' |
	sed 's/@P@/%/g' > "$WORK/cv/tools/tests/selftest_lib.sh"
printf '%s\n' '#!/bin/sh' '. "$TOOLS/tests/selftest_lib.sh"' 'want_fromlib "a" -- true' \
	'want_red() { :; }' "printf '#!/bin/sh\\ncat <<@P@sEOF@P@s\\n' \"'\" \"'\" > \"\$WORK/x.sh\"" \
	'if true; then' "$(printf '\t')st_inblock() { :; }" 'fi' 'st_libonly () { :; }' \
	'want_spaced "b" -- true' |
	sed 's/@P@/%/g' > "$WORK/cv/tools/tests/selftest_libuse.sh"
# conv: conventions.sh over the cv tree. A function and not a string run
# unquoted, so a blank in $WORK or $TOOLS splits no path (the conventions
# rule on a command line held in a variable).
conv() { env BUILD_WORKSPACE_DIRECTORY="$WORK/cv" "$SH" "$TOOLS/conventions.sh"; }

# The five probes are reported or not each under its own name: one run.
! st_mine || conv > "$WORK/cv.probes" 2>&1
want_out "conventions: an undeclared PATH command is reported" \
	"probe_undeclared.sh calls PATH commands and declares none" -- \
	cv_saved "$WORK/cv.probes"

want_out "conventions: and it NAMES the tools, not just the file" \
	"uses: git grep" -- \
	cv_saved "$WORK/cv.probes"
want_out "conventions: ...in the toolchain's folder too" \
	"tools/cc_toolchain/probe_req.sh calls PATH commands and declares none" -- \
	cv_saved "$WORK/cv.probes"
want_out "conventions: ...and in the installer's" \
	"tools/fortytwo/probe_req.sh calls PATH commands and declares none" -- \
	cv_saved "$WORK/cv.probes"
want_out "conventions: an installer script calling need() it never defines" \
	"tools/fortytwo/probe_need.sh calls need() and never defines it" -- \
	cv_saved "$WORK/cv.probes"
want_out "conventions: ...and a toolchain script's no-op require()" \
	"tools/cc_toolchain/probe_reqnoop.sh:3: its require() is not the helper every script carries" -- \
	cv_saved "$WORK/cv.probes"

want_broken_none "conventions: a correct declaration incl. git is accepted" \
	"probe_declared.sh" -- \
	cv_saved "$WORK/cv.probes"
want_out "conventions: a no-op require() is reported, whatever its list" \
	"tools/probe_reqnoop.sh:3: its require() is not the helper every script carries" -- \
	cv_saved "$WORK/cv.probes"
want_out "conventions: ...and one that exits 1, naming its line" \
	'                exit 1' -- cv_block "$WORK/cv.probes" 'tools/probe_reqexit.sh:3: its require()'

want_broken_none "conventions: a tool named in a quoted string is not a call" \
	"probe_quoted.sh" -- \
	cv_saved "$WORK/cv.probes"

want_broken_none "conventions: 'optional <tool>' exempts a probed tool" \
	"probe_optional.sh" -- \
	cv_saved "$WORK/cv.probes"
rm -f "$WORK/cv.probes"

# A selftest arm that hands a runner the pinned nm hands it --nm-lib too
# (TO VERIFY V210): reported on one line, over continuation lines, in a
# variable, and at the call of a helper that hands make_test.sh its own
# arguments; let through with --nm-lib on a continuation line, in a
# make_test.sh command that reads no symbols, under the marker on the line
# above or at the end of the command's own line, and at a call of the helper
# that reads no symbols. (This printf is one command, and it names --nm-lib,
# so the rule passes it over without a marker.) The shared run of the cv
# tree below reads it, and its arms follow that run.
printf '%s\n' '#!/bin/sh' \
	'"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --expect toy_a --src a.c' \
	'"$SH" "$TOOLS/forbidden_symbols.sh" --nm "$NM" \' '	--allowed - --src a.c' \
	'TOY_RUN="--nm $NM --globals"' \
	'"$SH" "$TOOLS/make_test.sh" --nm "$NM" --symbols toy_a --anchor a.c' \
	'"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" \' '	--nm-lib "$NM_LIB" --expect toy_a --src a.c' \
	'"$SH" "$TOOLS/make_test.sh" --nm "$NM" --rules "" --anchor a.c' \
	'# conventions: nm unpinned -- the toy arm refuses before nm runs' \
	'"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --expect toy_b --src a.c' \
	'"$SH" "$TOOLS/symbols_test.sh" --nm "$NM" --expect toy_c --src a.c  # conventions: nm unpinned -- the toy arm refuses before nm runs' \
	'toy_mt() {  # a helper: make_test.sh, with what the call passes' \
	'	"$SH" "$TOOLS/make_test.sh" --nm "$NM" "$@"' \
	'}' \
	'toy_mt --symbols toy_a --anchor a.c' \
	'toy_mt --rules "" --anchor a.c' \
	> "$WORK/cv/tools/tests/selftest_nmpin.sh"

# A FIXTURE PATH and the runners it drives (V188, V211, V337), in a workspace
# of its own (cvfx): toy runners, a toy runner_lib.sh and standin.sh, and a
# selftest file of loops that link a fixture and arms that run one. Reported:
# a fixture no arm uses, one lacking its runner's own tool, one lacking what
# its runner's library probes (standin.sh, sourced indented), a runner called
# through a variable, one lacking what a literal runner needs while another
# section's runner is named first (the false green), the first of two folders
# one loop fills, run by a second runner, a link into no readable folder,
# and a folder with a '-' and a '.' lacking its runner's own tool; and one
# lacking what standin.sh probes, found by runner_lib's rl_tool (fxt), the
# form every runner that sources runner_lib uses -- whose own hand-written
# lookup (fxh) is reported.
# Quiet: a folder with a '-' and a '.', and the variable-called fixture
# against the next section's runner (the false red). And the one-statement
# rule's TODO.md, written twice into a tree with a '-'. The tree's root holds
# a file named a20, which the unnamed-runner report's line (20) must never
# be read as: an unquoted ?20 would glob to it, and the report vanish.
mkdir -p "$WORK/cvfx/tools/tests" "$WORK/cvfx/c-piscine/c-piscine-c-93"
cv_submit "c-piscine/c-piscine-c-93" > "$WORK/cvfx/tools/submit.sh"
printf '\n' > "$WORK/cvfx/c-piscine/c-piscine-c-93/BUILD.bazel"
: > "$WORK/cvfx/a20"
printf '%s\n' '#!/bin/sh' 'for _rl_t in awk cat; do' '	command -v "$_rl_t" > /dev/null || exit 2' 'done' \
	> "$WORK/cvfx/tools/runner_lib.sh"
printf '%s\n' '#!/bin/sh' 'for _sl_t in grep head sed; do' '	command -v "$_sl_t" > /dev/null || exit 2' 'done' \
	> "$WORK/cvfx/tools/standin.sh"
printf '%s\n' '#!/bin/sh' 'require mktemp rm' '. "$RL_LIB"' > "$WORK/cvfx/tools/fxa_check.sh"
printf '%s\n' '#!/bin/sh' 'require cmp sort uniq' > "$WORK/cvfx/tools/fxb_check.sh"
printf '%s\n' '#!/bin/sh' 'require mktemp wc' > "$WORK/cvfx/tools/fxc_check.sh"
printf '%s\n' '#!/bin/sh' 'require mktemp' 'if true; then' '	. "$_sl"' 'fi' > "$WORK/cvfx/tools/fxs_check.sh"
printf '%s\n' '#!/bin/sh' 'require mktemp' '. "$RL_LIB"' 'load() {' '	rl_tool standin.sh' \
	'	. "$RL_TOOL"' '}' > "$WORK/cvfx/tools/fxt_check.sh"
printf '%s\n' '#!/bin/sh' 'require mktemp' '. "$RL_LIB"' 'for _sl in "$0" x; do' '	[ -f "$_sl" ] && break' \
	'done' '. "$_sl"' > "$WORK/cvfx/tools/fxh_check.sh"
_fxw='>'
printf '%s\n' '#!/bin/sh' \
	'# ------------------------------------------------------- a folder with a dash' \
	'for _t in sh awk cat mktemp rm; do' '	ln -sf "$(command -v "$_t")" "$WORK/in-x.d/$_t"' 'done' \
	'want_green "toy" -- \' '	env PATH="$WORK/in-x.d" "$SH" "$TOOLS/fxa_check.sh"' \
	'for _t in sh awk cat mktemp rm; do' '	ln -sf "$(command -v "$_t")" "$WORK/fx_unused/$_t"' 'done' \
	'for _t in sh awk cat mktemp; do' '	ln -sf "$(command -v "$_t")" "$WORK/fx_short/$_t"' 'done' \
	'want_green "toy" -- env PATH="$WORK/fx_short" "$SH" "$TOOLS/fxa_check.sh"' \
	'# ------------------------------------------------------- a runner in a variable' \
	'_r="$TOOLS/fxa_check.sh"' \
	'for _t in sh awk cat mktemp rm; do' '	ln -sf "$(command -v "$_t")" "$WORK/fx_var/$_t"' 'done' \
	'want_green "toy" -- env PATH="$WORK/fx_var" "$SH" "$_r"' \
	'# ------------------------------------------------------- another runner named first' \
	'for _t in sh cmp sort uniq; do' '	ln -sf "$(command -v "$_t")" "$WORK/fx_hide/$_t"' 'done' \
	'want_green "toy" -- "$SH" "$TOOLS/fxb_check.sh"' \
	'want_green "toy" -- env PATH="$WORK/fx_hide" \' '	"$SH" "$TOOLS/fxa_check.sh"' \
	'# ------------------------------------------------------- two runners, two folders' \
	'for _t in sh awk cat mktemp rm; do' '	ln -sf "$(command -v "$_t")" "$WORK/fx_p1/$_t"' \
	'	ln -sf "$(command -v "$_t")" "$WORK/fx_p2/$_t"' 'done' \
	'want_green "toy" -- env PATH="$WORK/fx_p2" "$SH" "$TOOLS/fxa_check.sh"' \
	'want_green "toy" -- env PATH="$WORK/fx_p1" "$SH" "$TOOLS/fxa_check.sh"' \
	'want_green "toy" -- env PATH="$WORK/fx_p1" "$SH" "$TOOLS/fxc_check.sh"' \
	'# ------------------------------------------------------- standin, and a folder unread' \
	'for _t in sh mktemp grep head; do' '	ln -sf "$(command -v "$_t")" "$WORK/fx_sl/$_t"' 'done' \
	'want_green "toy" -- env PATH="$WORK/fx_sl" "$SH" "$TOOLS/fxs_check.sh"' \
	'for _t in sh mktemp; do' '	ln -sf "$(command -v "$_t")" "$WORK/$_t"' 'done' \
	"echo a $_fxw \"\$WORK/t-x/TODO.md\"" "echo b $_fxw \"\$WORK/t-x/TODO.md\"" \
	'# ------------------------------------------------------- the next section' \
	'want_green "toy" -- "$SH" "$TOOLS/fxb_check.sh"' \
	'# ------------------------------------------------------- a dash, and a miss' \
	'for _t in sh awk cat mktemp; do' '	ln -sf "$(command -v "$_t")" "$WORK/in-y.d/$_t"' 'done' \
	'want_green "toy" -- env PATH="$WORK/in-y.d" "$SH" "$TOOLS/fxa_check.sh"' \
	'# ------------------------------------------------------- standin through rl_tool' \
	'for _t in sh mktemp awk cat grep head; do' '	ln -sf "$(command -v "$_t")" "$WORK/fx_tl/$_t"' 'done' \
	'want_green "toy" -- env PATH="$WORK/fx_tl" "$SH" "$TOOLS/fxt_check.sh"' \
	> "$WORK/cvfx/tools/tests/selftest_fx.sh"
# Its stdin is a pipe that never ends: the tree has no .bzl, and a reader of
# conventions.sh handed the empty list of them falls back on its stdin, so a
# run from a terminal waited there for good.
! st_mine || {
	awk 'BEGIN { for (;;) print "y" }' 2> /dev/null |
		bounded 300 env BUILD_WORKSPACE_DIRECTORY="$WORK/cvfx" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvfx.out" 2>&1
	echo "$?" > "$WORK/cvfx.rc"
}
want_green "conventions: a tree with no .bzl, its stdin never read" -- test "$(cat "$WORK/cvfx.rc")" != 124
cvfx_seen() { cv_saved "$WORK/cvfx.out"; }
cvfx_rule() { cvi_rule cvfx "$1"; }  # cvfx_rule HEADLINE -- that report of the run above, alone
cvfx_at() { cv_saved "$WORK/cvfx.out" grep -E "selftest_fx\\.sh:$1([^0-9]|\$)"; }
want_broken_none "conventions: a fixture PATH in a folder with a '-' is read" \
	'selftest_fx' -- cvfx_at 3
want_out "conventions: a fixture PATH no arm uses is reported" \
	'selftest_fx.sh:8 builds a fixture PATH ($WORK/fx_unused) that no arm uses' -- cvfx_seen
want_out "conventions: ...one lacking a tool its runner requires" \
	'missing: rm' -- cvfx_rule 'selftest_fx.sh:11'"'"'s fixture PATH'
want_out "conventions: ...a runner called through a variable" \
	'selftest_fx.sh:20 runs the fixture PATH $WORK/fx_var with a runner this check cannot name' -- cvfx_seen
want_broken_none "conventions: ...never held to the next section's runner" \
	'requires' -- cvfx_rule 'selftest_fx.sh:17'
want_out "conventions: ...its own runner, though another's is named first" \
	'missing: mktemp rm awk cat' -- cvfx_rule 'selftest_fx.sh:22'"'"'s fixture PATH'
want_out "conventions: ...every runner, and every folder a loop fills" \
	'missing: wc' -- cvfx_rule 'selftest_fx.sh:29'"'"'s fixture PATH'
want_broken_none "conventions: ...never a folder whose runners it holds" \
	'($WORK/fx_p2)' -- cvfx_seen
want_out "conventions: ...what standin.sh probes, sourced indented" \
	'missing: sed' -- cvfx_rule 'selftest_fx.sh:37'"'"'s fixture PATH'
want_out "conventions: ...and a link into no folder it can read" \
	'selftest_fx.sh:41 links a fixture PATH (for _t in sh mktemp; do) into a folder this check cannot read' -- cvfx_seen
want_out "conventions: a TODO.md written twice in a tree with a '-'" \
	'"$WORK/t-x/TODO.md", written at lines 44 45' -- cvfx_seen
want_out "conventions: ...and a folder with a '-' lacking its runner's tool" \
	'missing: rm' -- cvfx_rule 'selftest_fx.sh:49'"'"'s fixture PATH'
want_out "conventions: ...what standin.sh probes, found by rl_tool" \
	'missing: sed' -- cvfx_rule 'selftest_fx.sh:54'"'"'s fixture PATH'
want_out "conventions: a runner_lib runner finding standin.sh by hand is reported" \
	'tools/fxh_check.sh finds tools/standin.sh by hand' -- cvfx_seen
want_broken_none "conventions: ...not one that sources no runner_lib" \
	'fxs_check.sh finds tools/standin.sh' -- cvfx_seen

# A runner's message names only target suffixes that exist (V222), in a
# workspace of its own (cvsx) whose _SUFFIX_LAYER and docs/reference.md
# agree: a suffix renamed in both together (_gadget, now _gizmo_twin) leaves
# the table check quiet, and the runner still naming the old one is
# reported, as is a family (exNN_widget_*). Quiet: a key named in each of
# the three shapes, a student build's suffix, one tools/defs.bzl appends
# as a literal, a corpus stem's _diff, a comment, a case pattern and a
# shell variable, a file's glob (find -name, a case label over files) and
# a line marked as no target name; a case label over a target's name is
# still read. And a second workspace (cvsy) whose runners name none.
mkdir -p "$WORK/cvsx/tools" "$WORK/cvsx/docs" "$WORK/cvsx/c-piscine/c-piscine-c-92"
cv_submit "c-piscine/c-piscine-c-92" > "$WORK/cvsx/tools/submit.sh"
printf '\n' > "$WORK/cvsx/c-piscine/c-piscine-c-92/BUILD.bazel"
printf '%s\n' '_LAYER_LEVEL = {' '    "widget": 1,' '    "gizmo": 3,' '}' '' \
	'_SUFFIX_LAYER = {' '    "_diff": ("widget", None),' '    "_gizmo_twin": ("gizmo", None),' \
	'    "_widget": ("widget", None),' '}' '' \
	'_STUDENT_BIN_SUFFIXES = ("bin", "bin_asan")' '' \
	'def toy(ex):' '    return ex + "_widget_guard"' > "$WORK/cvsx/tools/defs.bzl"
printf '%s\n' '## Target names' '' '| Suffix | Layer | Level |' '|---|---|---|' \
	'| `_diff` | `widget` | basic |' '| `_gizmo_twin` | `gizmo` | robust |' \
	'| `_widget` | `widget` | basic |' > "$WORK/cvsx/docs/reference.md"
printf '%s\n' '#!/bin/sh' \
	'echo "  the _widget target says more."' \
	'echo "  Read *_widget first; its exNN_gizmo_twin waits."' \
	'echo "  an exNN_bin_asan build, an exNN_widget_guard replay"' \
	'echo "  the _corpus_diff target replays it"' \
	'echo "  the _gadget target holds the rest."' \
	'echo "  the exNN_widget_* layers say why."' \
	'# the _nothing target, in a comment' \
	'case "$1" in __*_chk) ;; esac' \
	'echo "$_cv target"' \
	"find . -name '*_test.c' -print" \
	'case "$1" in *_bonus.c) ;; esac' \
	'# conventions: not a target name -- a sed pattern over words' \
	"sed 's/ *_trim\$//'" \
	'case "$TEST_TARGET" in *_gadget) ;; esac' > "$WORK/cvsx/tools/sx_check.sh"
mkdir -p "$WORK/cvsy"
cp -R "$WORK/cvsx/tools" "$WORK/cvsx/docs" "$WORK/cvsx/c-piscine" "$WORK/cvsy/"
printf '%s\n' '#!/bin/sh' 'echo "  no target named here."' > "$WORK/cvsy/tools/sx_check.sh"
if st_mine; then
	for _t in cvsx cvsy; do
		env BUILD_WORKSPACE_DIRECTORY="$WORK/$_t" "$SH" "$TOOLS/conventions.sh" > "$WORK/$_t.out" 2>&1
	done
fi
cvsx_sfx() { cvi_rule cvsx "a runner's message names a target suffix that does not exist"; }
want_out "conventions: a runner naming a suffix renamed in the table and the docs is reported" \
	'tools/sx_check.sh:6: _gadget (no target ends in it)' -- cvsx_sfx
want_out "conventions: ...and one naming a family of targets" \
	'tools/sx_check.sh:7: _widget_* (a family, not a target)' -- cvsx_sfx
want_broken_none "conventions: ...while the table check is quiet on that rename" \
	"disagrees with tools/defs_levels.bzl's _SUFFIX_LAYER" -- cvi_rule cvsx "disagrees with"
want_out "conventions: ...and a case label over a target's name" \
	'tools/sx_check.sh:15: _gadget (no target ends in it)' -- cvsx_sfx
for _l in 2 3 4 5 8 9 10 11 12 14; do
	want_broken_none "conventions: ...never line $_l of the toy runner" \
		"tools/sx_check.sh:$_l:" -- cvsx_sfx
done
want_out "conventions: a run that reads no suffix in the runners is reported" \
	'read no name in tools/*.sh' -- cvi_rule cvsy "the check on the target suffixes"
rm -rf "$WORK/cvsx" "$WORK/cvsy" "$WORK/cvsx.out" "$WORK/cvsy.out"

# Two modules of tools/submit.sh's REMOTES table that share a short name
# (the name 42 and .submit-remotes take): a Common Core project is its own
# folder's name in lower case, at any depth under cursus/, so two folders
# of one name under two milestones share it, and a Piscine folder under a
# second course shares its own. The rule runs submit.sh's short_name(), cut
# out of the script: the real one in cvsn and cvsn2, in cvsn3 one spelled
# so the rule cannot cut it out, and in cvsn4 one it cuts out that does not
# run (a case never closed), each of which it says rather than pass.
cvsn_tree() {  # cvsn_tree TOY "MODULE..."
	mkdir -p "$WORK/$1/tools"
	for _m in $2; do
		mkdir -p "$WORK/$1/$_m"
		printf '\n' > "$WORK/$1/$_m/BUILD.bazel"
	done
	cv_submit "$2" > "$WORK/$1/tools/submit.sh"
}
cvsn_tree cvsn "c-piscine/c-piscine-c-91 cursus/Milestone_0/Libft cursus/Milestone_9/LIBFT cursus/Milestone_8/c-piscine-c-91 cursus/Milestone_7/Other"
cvsn_tree cvsn2 "c-piscine/c-piscine-c-91 cursus/Milestone_0/Libft cursus/Milestone_7/Other"
cvsn_tree cvsn3 "c-piscine/c-piscine-c-91"
cvsn_tree cvsn4 "c-piscine/c-piscine-c-91"
for _t in cvsn cvsn2; do
	{
		awk '/^short_name\(\) \{$/ { f = 1 } f { print } f && /^\}$/ { exit }' "$TOOLS/submit.sh"
		printf '%s\n' 'while read -r m; do' '	short_name "$m"' 'done'
	} >> "$WORK/$_t/tools/submit.sh"
done
printf '%s\n' 'short_name()' '{' '	_sn=$1' '}' 'while read -r m; do' '	short_name "$m"' 'done' \
	>> "$WORK/cvsn3/tools/submit.sh"
printf '%s\n' 'short_name() {' '	case "$1" in' '		*) _sn=$1 ;;' '}' 'while read -r m; do' '	short_name "$m"' 'done' \
	>> "$WORK/cvsn4/tools/submit.sh"
if st_mine; then
	for _t in cvsn cvsn2 cvsn3 cvsn4; do
		env BUILD_WORKSPACE_DIRECTORY="$WORK/$_t" "$SH" "$TOOLS/conventions.sh" > "$WORK/$_t.out" 2>&1
	done
fi
want_out "conventions: two Common Core folders of one name under two milestones are reported" \
	'libft: cursus/Milestone_0/Libft cursus/Milestone_9/LIBFT' -- cvi_rule cvsn 'share a short name'
want_out "conventions: ...and a Piscine folder under a second course" \
	'c-91: c-piscine/c-piscine-c-91 cursus/Milestone_8/c-piscine-c-91' -- cvi_rule cvsn 'share a short name'
want_broken_none "conventions: ...never a module whose short name is its own" \
	'Other' -- cvi_rule cvsn 'share a short name'
want_broken_none "conventions: a table whose short names differ is not reported" \
	'share a short name' -- cvi_rule cvsn2 'share a short name'
want_out "conventions: a short_name() the rule cannot cut out is said, not passed" \
	'tools/submit.sh calls short_name, and this rule cannot find its definition' -- cvi_rule cvsn3 'short_name'
want_out "conventions: ...and so is one that does not run" \
	"tools/submit.sh's short_name() failed when run over the REMOTES table's modules" -- cvi_rule cvsn4 'short_name'
rm -rf "$WORK/cvsn" "$WORK/cvsn2" "$WORK/cvsn3" "$WORK/cvsn4" \
	"$WORK/cvsn.out" "$WORK/cvsn2.out" "$WORK/cvsn3.out" "$WORK/cvsn4.out"

# The names no unit may take (tools/defs_contract.bzl's _RESERVED_UNIT_NAMES), in a
# workspace of its own (cvrn): the list holds frob, which docs/reference.md's
# table does not, and tools/fortytwo/workspace.py names strict as a level and
# norminette as a layer, which the list does not hold. basic is in all three, and neither report names
# it. A workspace.py whose LEVELS is split over lines (cvrm) is reported as
# one the check cannot read, never as one that names nothing.
mkdir -p "$WORK/cvrn/tools/fortytwo" "$WORK/cvrn/docs" "$WORK/cvrn/c-piscine/c-piscine-c-92"
cv_submit "c-piscine/c-piscine-c-92" > "$WORK/cvrn/tools/submit.sh"
printf '\n' > "$WORK/cvrn/c-piscine/c-piscine-c-92/BUILD.bazel"
printf '%s\n' '_RESERVED_UNIT_NAMES = [' '    "all",' '    "basic",' '    "frob",' ']' \
	> "$WORK/cvrn/tools/defs.bzl"
printf '%s\n' '## Reserved unit names' '' '| Name | Why |' '|---|---|' \
	'| `all` | a level `42` takes |' '| `basic` | a level |' > "$WORK/cvrn/docs/reference.md"
printf '%s\n' 'LEVELS = ("basic", "all", "strict")' '' \
	'LAYER_ALIASES = {"norminette": "norm"}' > "$WORK/cvrn/tools/fortytwo/workspace.py"
mkdir -p "$WORK/cvrm"
cp -R "$WORK/cvrn/tools" "$WORK/cvrn/docs" "$WORK/cvrn/c-piscine" "$WORK/cvrm/"
printf '%s\n' 'LEVELS = (' '    "basic",' ')' '' 'LAYER_ALIASES = {"norminette": "norm"}' \
	> "$WORK/cvrm/tools/fortytwo/workspace.py"
if st_mine; then
	for _t in cvrn cvrm; do
		env BUILD_WORKSPACE_DIRECTORY="$WORK/$_t" "$SH" "$TOOLS/conventions.sh" > "$WORK/$_t.out" 2>&1
	done
fi
cvrn_ws() { cvi_rule cvrn "_RESERVED_UNIT_NAMES lacks"; }
want_out "conventions: a reserved unit name the docs' table lacks is reported" \
	'frob' -- cvi_rule cvrn "disagrees with tools/defs.bzl's _RESERVED_UNIT_NAMES"
want_out "conventions: ...and a level 42 reads, which the list lacks" \
	'strict' -- cvrn_ws
want_out "conventions: ...and a word 42 reads as a layer, which the list lacks" \
	'norminette' -- cvrn_ws
want_broken_none "conventions: ...never a word the list holds" \
	'basic' -- cvrn_ws
want_out "conventions: ...and a workspace.py it cannot read that way is reported" \
	'has no LEVELS = (...)' -- cvi_rule cvrm "tools/fortytwo/workspace.py"
rm -rf "$WORK/cvrn" "$WORK/cvrm" "$WORK/cvrn.out" "$WORK/cvrm.out"

# The macros' source is tools/defs.bzl and the files it loads, in a
# workspace of its own (cvdf): its tools/defs.bzl loads defs_a.bzl over two
# lines and defs_c.bzl on one, and its docstring maps defs_a.bzl alone.
# defs_b.bzl, which it does not load, is reported, as is _dup, defined in
# defs_a.bzl and defs_b.bzl; a BUILD file and a tools/*.bzl that load a
# defs_a.bzl round tools/defs.bzl; and in the map defs_c.bzl, which has no
# entry, _ghost, which no file defines, and _in_c, listed under defs_a.bzl
# and defined in defs_c.bzl. Quiet: the re-export widget = _widget, a name
# in a docstring, a "//tools:defs_a.bzl" that is a data list's and not a
# load's, and a starred name in the map. And a rule that reads a table by
# name reads it in a loaded file: _RESERVED_UNIT_NAMES lives in defs_a.bzl,
# and its frob, which docs/reference.md lacks, is reported. And a load-time
# check harness never fail()s: reported, harness_bad.bzl's fail() (line 5)
# and the one in defs_a.bzl's starlark_selftest_arms (17); quiet, a harness
# that appends a row, naming fail() in its docstring and a comment, and
# defs_c.bzl's guard, which is a guard's fail(). And a pointer names the file
# that defines its name (toy_ptr.bzl): reported, a name no file defines (on
# one line, wrapped onto the next, and in a message joined from strings), a
# NAME in FILE that another file defines, a prefix no name of its file starts
# with, and a file that is not there; quiet, a name its file defines or re-exports, a prefix one of its
# names starts with, a word of prose and a shell variable. The same, of a
# file named with no folder (defs.bzl's NAME, (defs.bzl, NAME)), of NAME
# (tools/defs.bzl) on one line and wrapped, of tools/defs.bzl hands ...
# (NAME on one line and wrapped, and of a message echoed a line at a time
# are reported; quiet, such a NAME its file defines, a public word before a
# (tools/defs_c.bzl), the tail of it, and a file in a list of files. A
# name defs_c.bzl's docstring holds at the start of a line, _DOC_ONLY = and
# def _doc_fn(, is no definition, to this rule as to the two above it. And
# a C source's comment, a " * " line going on with what the line above it
# began: reported, a name no file defines, in a .c wrapped and in a .h on
# one line; quiet, a name its file defines.
mkdir -p "$WORK/cvdf/tools/tests" "$WORK/cvdf/docs" "$WORK/cvdf/c-piscine/c-piscine-c-83"
cv_submit "c-piscine/c-piscine-c-83" > "$WORK/cvdf/tools/submit.sh"
printf '%s\n' 'load("//tools:defs_a.bzl", "widget")' '' 'filegroup(' '    name = "srcs",' \
	'    srcs = [' '        "//tools:defs_a.bzl",' '    ],' ')' > "$WORK/cvdf/c-piscine/c-piscine-c-83/BUILD.bazel"
printf '%s\n' '"""The toy macros.' '' '_dup = 9' '' 'WHERE THE MACROS LIVE. The map:' '' \
	'  defs_a.bzl  the widget: widget, _RESERVED_UNIT_NAMES, _ghost, _in_c,' \
	'              _gone_*' '"""' '' 'load(' '    ":defs_a.bzl",' '    _widget = "widget",' ')' \
	'load(":defs_c.bzl", _c_gadget = "c_gadget")' '' 'widget = _widget' 'c_gadget = _c_gadget' \
	> "$WORK/cvdf/tools/defs.bzl"
printf '%s\n' '"""The widget."""' '' '_RESERVED_UNIT_NAMES = [' '    "all",' '    "basic",' '    "frob",' ']' '' \
	'_dup = 1' '' 'def widget():' '    return _dup' '' 'def starlark_selftest_arms():' \
	'    arms = []' '    if not arms:' '        fail("an arm answered wrong")' '    return arms' \
	> "$WORK/cvdf/tools/defs_a.bzl"
printf '%s\n' '"""Loaded by nobody."""' '' '_dup = 2' > "$WORK/cvdf/tools/defs_b.bzl"
printf '%s\n' '"""The gadget.' '' '_DOC_ONLY = 1' 'def _doc_fn(x):' '"""' '' '_in_c = 3' '' \
	'def c_gadget():' '    return _in_c' '' \
	'def c_guard(x):' '    if x:' '        fail("a guard refuses its call")' > "$WORK/cvdf/tools/defs_c.bzl"
printf '%s\n' '"""A toy harness."""' '' 'def toy_unit(cases):' '    if not cases:' \
	'        fail("no cases")' > "$WORK/cvdf/tools/tests/harness_bad.bzl"
printf '%s\n' '"""A toy harness: it never calls fail(), it appends a row."""' '' \
	'def toy_unit(cases, got):' '    # a fail( here would take the package down' \
	'    cases.append("FAIL toy: got %r" % got)' > "$WORK/cvdf/tools/tests/harness_ok.bzl"
printf '%s\n' 'load(":defs_a.bzl", "widget")' '' 'def toy():' '    return widget()' > "$WORK/cvdf/tools/toy.bzl"
printf '%s\n' '## Reserved unit names' '' '| Name | Why |' '|---|---|' \
	'| `all` | a level `42` takes |' '| `basic` | a level |' > "$WORK/cvdf/docs/reference.md"
cat > "$WORK/cvdf/tools/toy_ptr.bzl" <<'EOF'
# The table is tools/defs.bzl's _NOT_THERE, the widget tools/defs_a.bzl's widget().
# A wrapped one is tools/defs.bzl's
# _ALSO_GONE, a re-export tools/defs.bzl's widget, prose tools/defs.bzl's docstring.
# A variable, $_x in tools/defs.bzl, and _in_c in tools/defs_a.bzl.
# Prefixes: tools/defs_a.bzl's _RESERVED_* and tools/defs_c.bzl's _RESERVED_*.
# And a file that is not there: (tools/defs_z.bzl, _in_c).
MSG = ("a message joined from strings, naming tools/defs.bzl's " +
       "_JOINED_GONE")
# Bare: defs.bzl's _BARE_GONE, defs_a.bzl's widget(), (defs.bzl, _COMMA_GONE).
# Paren: _PAREN_GONE (tools/defs.bzl), _in_c (tools/defs_c.bzl), memory_x (tools/defs_c.bzl).
# A list of files: defs.bzl, run_check.sh and toy.bzl.
# tools/defs.bzl hands it over (_HANDS_GONE), and tools/defs.bzl hands them
# to a runner (_HANDS_WRAPPED).
# A wrapped one of _WRAPPED_PAREN
# (tools/defs.bzl) is read on.
echo "  a message printed a line at a time, tools/defs.bzl's" >&2
echo "  _ECHO_GONE stages it" >&2
# A docstring's line is no definition: tools/defs_c.bzl's _DOC_ONLY, _doc_fn() in tools/defs_c.bzl.
EOF
printf '%s\n' '/* A C comment: (tools/defs.bzl,' ' * _C_GONE), and defs_c.bzl'"'"'s' \
	' * _in_c, which it defines. */' 'int	toy_ptr;' > "$WORK/cvdf/tools/toy_ptr.c"
printf '%s\n' '/* A header: defs.bzl'"'"'s _H_GONE. */' > "$WORK/cvdf/tools/toy_ptr.h"
# A file with blanks in its name is read like any other, and blinds the rule
# to no other file; a turn-in's file is never read.
printf '%s\n' '/* defs.bzl'"'"'s _BLANK_GONE. */' > "$WORK/cvdf/tools/toy blank (1).h"
mkdir -p "$WORK/cvdf/tools/td/deliverable"
printf '%s\n' '/* defs.bzl'"'"'s _TURNIN_GONE. */' > "$WORK/cvdf/tools/td/deliverable/toy.c"
if st_mine; then
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvdf" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvdf.out" 2>&1
fi
cvdf_dup() { cvi_rule cvdf "a name is defined in two files of the macros' source"; }
cvdf_round() { cvi_rule cvdf "a file loads a tools/defs_*.bzl, round tools/defs.bzl"; }
cvdf_map() { cvi_rule cvdf "tools/defs.bzl's map of the macros' files is wrong"; }
cvdf_fail() { cvi_rule cvdf "a load-time check harness calls fail()"; }
cvdf_ptr() { cvi_rule cvdf "a pointer names a file that does not define the name it points at"; }
want_out "conventions: a tools/defs_*.bzl tools/defs.bzl does not load is reported" \
	'    tools/defs_b.bzl' -- cvi_rule cvdf "a file of the macros' source is one tools/defs.bzl does not load"
for _f in defs_a defs_c; do
	want_broken_none "conventions: ...never $_f.bzl, loaded over two lines or on one" \
		"tools/$_f.bzl" -- cvi_rule cvdf "a file of the macros' source is one tools/defs.bzl does not load"
done
want_out "conventions: a name two files of the macros' source define is reported" \
	'_dup: tools/defs_a.bzl:9, tools/defs_b.bzl:3' -- cvdf_dup
want_broken_none "conventions: ...never a re-export" \
	'widget' -- cvdf_dup
want_broken_none "conventions: ...nor a name in a docstring" \
	'tools/defs.bzl:' -- cvdf_dup
want_out "conventions: a BUILD file that loads a tools/defs_*.bzl is reported" \
	'c-piscine/c-piscine-c-83/BUILD.bazel:1://tools:defs_a.bzl' -- cvdf_round
want_out "conventions: ...and a tools/*.bzl that does" \
	'tools/toy.bzl:1::defs_a.bzl' -- cvdf_round
want_broken_none "conventions: ...never a data list that names one" \
	'BUILD.bazel:6:' -- cvdf_round
want_out "conventions: a tools/defs_*.bzl with no entry in the map is reported" \
	'tools/defs_c.bzl: has no entry in the map' -- cvdf_map
want_out "conventions: ...and a name the map lists that no file defines" \
	'tools/defs_a.bzl: lists _ghost, which no file of the macros'"'"' source defines' -- cvdf_map
want_out "conventions: ...and a name listed under a file that does not define it" \
	'tools/defs_a.bzl: lists _in_c, which tools/defs_c.bzl defines' -- cvdf_map
for _w in _gone _RESERVED_UNIT_NAMES widget; do
	want_broken_none "conventions: ...never $_w, starred or its file's" \
		"lists $_w" -- cvdf_map
done
want_out "conventions: a table a rule reads by name is read in a loaded file" \
	'frob' -- cvi_rule cvdf "disagrees with tools/defs_a.bzl's _RESERVED_UNIT_NAMES"
want_out "conventions: a load-time check harness that calls fail() is reported" \
	'tools/tests/harness_bad.bzl:5: fail(' -- cvdf_fail
want_out "conventions: ...and a fail() in the guards' arms" \
	'tools/defs_a.bzl:17: fail(' -- cvdf_fail
want_broken_none "conventions: ...never a harness that appends a row" \
	'harness_ok.bzl' -- cvdf_fail
want_broken_none "conventions: ...nor a guard's own fail()" 'defs_c.bzl' -- cvdf_fail
want_out "conventions: a pointer to a name its file does not define is reported" \
	'tools/toy_ptr.bzl:1: tools/defs.bzl, which does not define _NOT_THERE (no tools/*.bzl does)' -- cvdf_ptr
want_out "conventions: ...and one wrapped onto the next line" \
	'tools/toy_ptr.bzl:2: tools/defs.bzl, which does not define _ALSO_GONE' -- cvdf_ptr
want_out "conventions: ...and one in a message joined from strings" \
	'tools/toy_ptr.bzl:7: tools/defs.bzl, which does not define _JOINED_GONE' -- cvdf_ptr
want_out "conventions: ...and NAME in FILE, saying which file defines it" \
	'tools/toy_ptr.bzl:4: tools/defs_a.bzl, which does not define _in_c (tools/defs_c.bzl does)' -- cvdf_ptr
want_out "conventions: ...and a prefix no name of its file starts with" \
	'tools/toy_ptr.bzl:5: tools/defs_c.bzl, which defines no name starting _RESERVED_*' -- cvdf_ptr
want_out "conventions: ...and a file that does not exist" \
	'tools/toy_ptr.bzl:6: tools/defs_z.bzl, which does not exist' -- cvdf_ptr
want_out "conventions: ...and a file named with no folder, defs.bzl's NAME" \
	'tools/toy_ptr.bzl:9: tools/defs.bzl, which does not define _BARE_GONE' -- cvdf_ptr
want_out "conventions: ...and (defs.bzl, NAME)" \
	'tools/toy_ptr.bzl:9: tools/defs.bzl, which does not define _COMMA_GONE' -- cvdf_ptr
want_out "conventions: ...and NAME (tools/defs.bzl)" \
	'tools/toy_ptr.bzl:10: tools/defs.bzl, which does not define _PAREN_GONE' -- cvdf_ptr
want_out "conventions: ...and one whose (tools/defs.bzl) opens the next line" \
	'tools/toy_ptr.bzl:14: tools/defs.bzl, which does not define _WRAPPED_PAREN' -- cvdf_ptr
want_out "conventions: ...and tools/defs.bzl hands ... (NAME" \
	'tools/toy_ptr.bzl:12: tools/defs.bzl, which does not define _HANDS_GONE' -- cvdf_ptr
want_out "conventions: ...and one whose (NAME is on the next line" \
	'tools/toy_ptr.bzl:12: tools/defs.bzl, which does not define _HANDS_WRAPPED' -- cvdf_ptr
want_out "conventions: ...and one in a message echoed a line at a time" \
	'tools/toy_ptr.bzl:16: tools/defs.bzl, which does not define _ECHO_GONE' -- cvdf_ptr
want_out "conventions: ...and a name its file holds only in a docstring" \
	'tools/toy_ptr.bzl:18: tools/defs_c.bzl, which does not define _DOC_ONLY (no tools/*.bzl does)' -- cvdf_ptr
want_out "conventions: ...a def as well" \
	'tools/toy_ptr.bzl:18: tools/defs_c.bzl, which does not define _doc_fn (no tools/*.bzl does)' -- cvdf_ptr
want_out "conventions: ...and one in a C comment, wrapped" \
	'tools/toy_ptr.c:1: tools/defs.bzl, which does not define _C_GONE' -- cvdf_ptr
want_out "conventions: ...and one in a header" \
	'tools/toy_ptr.h:1: tools/defs.bzl, which does not define _H_GONE' -- cvdf_ptr
want_broken_none "conventions: ...never a C comment's name its file defines" \
	'toy_ptr.c:2' -- cvdf_ptr
want_out "conventions: ...and one in a file with blanks in its name" \
	'tools/toy blank (1).h:1: tools/defs.bzl, which does not define _BLANK_GONE' -- cvdf_ptr
want_broken_none "conventions: ...never one in a turn-in's file" \
	'_TURNIN_GONE' -- cvdf_ptr
for _w in 'toy_ptr.bzl:9: tools/defs_a.bzl' 'toy_ptr.bzl:10: tools/defs_c.bzl' memory run_check; do
	want_broken_none "conventions: ...never $_w" "$_w" -- cvdf_ptr
done
for _w in widget docstring _x 'defs_a.bzl, which defines no name'; do
	want_broken_none "conventions: ...never $_w" "$_w" -- cvdf_ptr
done
rm -rf "$WORK/cvdf" "$WORK/cvdf.out"
# A file the pointer rule cannot read -- a dangling link, which its find
# takes -- is reported with awk's status, never passed with nothing read.
if st_mine; then
	mkdir -p "$WORK/cvda/tools" "$WORK/cvda/c-piscine/c-piscine-c-93"
	cv_submit "c-piscine/c-piscine-c-93" > "$WORK/cvda/tools/submit.sh"
	printf '\n' > "$WORK/cvda/c-piscine/c-piscine-c-93/BUILD.bazel"
	cp "$TOOLS/units.awk" "$WORK/cvda/tools/units.awk"
	ln -s nowhere.sh "$WORK/cvda/tools/dangling.sh"
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvda" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvda.out" 2>&1
fi
want_out "conventions: ...and a file it cannot read is reported, never passed" \
	"the rule's awk stopped (status" -- \
	cvi_rule cvda "a pointer names a file that does not define the name it points at"
rm -rf "$WORK/cvda" "$WORK/cvda.out"

# Every macro fixture package with a subject() contract is listed in
# tools/tests/BUILD.bazel's _FIXTURE_PACKAGES, in a workspace of its own
# (cvfp): unlisted opens a contract and is not in the list, and is reported;
# listed is in it, and plain has no contract, and neither is named.
#
# And each listed package ends with its toys_analysed, the analysed() call
# //tools/tests:macro_fixtures_test reaches every toy through: listed2 has a
# test after it, listed3 none at all and listed4 a comprehension of tests
# after one written over several lines, and each is reported; listed ends
# with it on one line, exports_files() after, and listed5 over several
# lines, its comment above it, and neither is named. Its deps are read where
# it is called: listed6 takes them from a list of the rules read above it,
# which misses every toy declared between the two, and is reported.
mkdir -p "$WORK/cvfp/tools/tests/macro_fixtures/listed" "$WORK/cvfp/tools/tests/macro_fixtures/unlisted" \
	"$WORK/cvfp/tools/tests/macro_fixtures/listed2" "$WORK/cvfp/tools/tests/macro_fixtures/listed3" \
	"$WORK/cvfp/tools/tests/macro_fixtures/listed4" "$WORK/cvfp/tools/tests/macro_fixtures/listed5" \
	"$WORK/cvfp/tools/tests/macro_fixtures/listed6" \
	"$WORK/cvfp/tools/tests/macro_fixtures/plain" "$WORK/cvfp/c-piscine/c-piscine-c-92"
cv_submit "c-piscine/c-piscine-c-92" > "$WORK/cvfp/tools/submit.sh"
printf '\n' > "$WORK/cvfp/c-piscine/c-piscine-c-92/BUILD.bazel"
cp "$TOOLS/units.awk" "$WORK/cvfp/tools/units.awk"
printf '%s\n' '_FIXTURE_PACKAGES = [' '    "//tools/tests/macro_fixtures/listed",' \
	'    "//tools/tests/macro_fixtures/listed2",' '    "//tools/tests/macro_fixtures/listed3",' \
	'    "//tools/tests/macro_fixtures/listed4",' '    "//tools/tests/macro_fixtures/listed5",' \
	'    "//tools/tests/macro_fixtures/listed6",' ']' \
	> "$WORK/cvfp/tools/tests/BUILD.bazel"
for _t in listed listed2 listed3 listed4 listed5 listed6 unlisted; do
	printf '%s\n' 'subject(' '    grader = "both",' '    group = False,' '    units = {' \
		'        "toy": unit(page = 1, files = ["Makefile"], allowed = None),' '    },' ')' \
		> "$WORK/cvfp/tools/tests/macro_fixtures/$_t/BUILD.bazel"
done
printf '%s\n' 'analysed(name = "toys_analysed", testonly = True, deps = [":" + r for r in existing_rules()])' \
	'exports_files(["x"])' >> "$WORK/cvfp/tools/tests/macro_fixtures/listed/BUILD.bazel"
printf '%s\n' '_RULES = existing_rules()' '' \
	'hand_test(name = "toy_late", layer = "selftest", srcs = ["t.sh"], tags = ["manual"])' '' \
	'analysed(' '    name = "toys_analysed",' '    testonly = True,' \
	'    # its deps, from existing_rules() read above' \
	'    deps = sorted([":" + r for r, a in _RULES.items() if "manual" in (a.get("tags") or [])]),' \
	')' 'exports_files([' '    "existing_rules()",' '])' \
	>> "$WORK/cvfp/tools/tests/macro_fixtures/listed6/BUILD.bazel"
printf '%s\n' 'analysed(name = "toys_analysed", testonly = True, deps = [])' \
	'hand_test(name = "toy_late", layer = "selftest", srcs = ["t.sh"])' \
	>> "$WORK/cvfp/tools/tests/macro_fixtures/listed2/BUILD.bazel"
printf '%s\n' 'analysed(' '    name = "toys_analysed",' '    testonly = True,' '    deps = [],' ')' \
	'[hand_test(name = "toy_" + n, layer = "selftest", srcs = ["t.sh"]) for n in ["a"]]' \
	>> "$WORK/cvfp/tools/tests/macro_fixtures/listed4/BUILD.bazel"
printf '%s\n' '' '# EVERY TOY ANALYSED: the last call.' 'analysed(' '    name = "toys_analysed",' \
	'    testonly = True,' \
	'    deps = sorted([":" + r for r, a in existing_rules().items() if "manual" in (a.get("tags") or [])]),' \
	')' '' 'exports_files(["x"])' \
	>> "$WORK/cvfp/tools/tests/macro_fixtures/listed5/BUILD.bazel"
printf '%s\n' 'exports_files(["toy.txt"])' > "$WORK/cvfp/tools/tests/macro_fixtures/plain/BUILD.bazel"
if st_mine; then
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvfp" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvfp.out" 2>&1
fi
cvfp_rule() { cvi_rule cvfp "is not in tools/tests/BUILD.bazel's _FIXTURE_PACKAGES"; }
want_out "conventions: a fixture package with a contract, not in _FIXTURE_PACKAGES, is reported" \
	'tools/tests/macro_fixtures/unlisted/BUILD.bazel' -- cvfp_rule
want_broken_none "conventions: ...never one the list holds" \
	'macro_fixtures/listed/' -- cvfp_rule
want_broken_none "conventions: ...nor one with no contract" \
	'plain' -- cvfp_rule
cvta_rule() { cvi_rule cvfp "does not end with its toys_analysed"; }
want_out "conventions: a fixture package with a test after its toys_analysed is reported" \
	'tools/tests/macro_fixtures/listed2/BUILD.bazel: its last call is hand_test(' -- cvta_rule
want_out "conventions: ...and one with no toys_analysed at all" \
	'tools/tests/macro_fixtures/listed3/BUILD.bazel: its last call is subject(' -- cvta_rule
want_out "conventions: ...and a comprehension of tests after it" \
	'tools/tests/macro_fixtures/listed4/BUILD.bazel: its last call is [hand_test(' -- cvta_rule
want_broken_none "conventions: ...never one that ends with it on one line, exports_files() after" \
	'macro_fixtures/listed/BUILD.bazel' -- cvta_rule
want_broken_none "conventions: ...nor one that ends with it over several lines" \
	'macro_fixtures/listed5/BUILD.bazel' -- cvta_rule
want_broken_none "conventions: ...nor, for that rule, one whose deps it read above it" \
	'macro_fixtures/listed6/BUILD.bazel' -- cvta_rule
cvtr_rule() { cvi_rule cvfp "takes its deps from no existing_rules() of its own"; }
want_out "conventions: a toys_analysed whose deps were read above it is reported" \
	'    tools/tests/macro_fixtures/listed6/BUILD.bazel' -- cvtr_rule
want_broken_none "conventions: ...never one that reads them where it is called" \
	'macro_fixtures/listed/BUILD.bazel' -- cvtr_rule
want_broken_none "conventions: ...over several lines too" \
	'macro_fixtures/listed5/BUILD.bazel' -- cvtr_rule
rm -rf "$WORK/cvfp" "$WORK/cvfp.out"

# A runner that quotes one subject of its own accord (finding 082): its
# message names a project and a page. A comment may say where a rule came
# from, and a program's own name (./rush-02) is no project's.
{
	printf '#!/bin/sh\nset -u\n. "$RL_LIB"\n'
	printf '# C 09, p.6 is where this rule came from, for whoever maintains it\n'
	printf 'echo "  C 09, p.6: \\"Print every command.\\""\n'
	printf "printf '    replay: ./rush-02 x\\\\n'\n"
	printf 'echo "  The sentence this applies, from the call site:"\n'
	# A project's name split over two messages is read whole (V162): 9. The
	# comment above them ends no block (V319), so the block opens at the
	# program's name (6), and is reported at the first message its claim
	# needs, never there.
	printf '# Two messages that print one after the other\n'
	printf 'echo "  a toy written for C"\n'
	printf 'echo "  98 alone."\n'
} > "$WORK/cv/tools/probe_quote.sh"
# A library the runners or the check scripts source is no runner, and what
# it prints reaches the same logs: shell_check.sh's messages were read by
# no rule. One that says what "the subject" says, in a function.
printf '# shellcheck shell=sh\n# A library a check script sources.\nsay_it() {\n\tprintf %s\n}\n' \
	"'  the subject says so.\\n'" > "$WORK/cv/tools/probe_saylib.sh"
printf '%s\n' '#!/bin/sh' 'set -u' '. "$RL_LIB"' '# shellcheck source=tools/probe_saylib.sh' \
	'. "${0%/*}/probe_saylib.sh"' 'say_it' > "$WORK/cv/tools/probe_saysrc.sh"
# Quiet: the same in a library no runner and no check script sources, which
# prints to a terminal (drives.sh, sourced by setup.sh), never to a log.
printf '# shellcheck shell=sh\n# A library setup sources.\nsay_it() {\n\tprintf %s\n}\n' \
	"'  the subject says so.\\n'" > "$WORK/cv/tools/probe_termlib.sh"
# A # line of a here-document cat prints is no comment, and it prints: it
# was skipped unjudged, so a project's name there reached the log (13, and
# 19: a > inside a quoted program is no redirection, and awk prints the
# here-document's lines to its standard output). Quiet: one in a
# here-document written to a file, that file's comment (16).
printf '%s\n' '#!/bin/sh' 'set -u' '. "$RL_LIB"' "$(cv_require probe_hdquote.sh)" 'require cat awk' \
	'cat <<EOF' '# C 98 says so' 'EOF' 'cat > "$T/x.awk" <<'"'EOF'" \
	"# C 98's rule, a comment of the program it writes" 'EOF' \
	"awk '\$1 > 0' <<EOF" '# C 98 says so' 'EOF' > "$WORK/cv/tools/probe_hdquote.sh"

# THE ENVIRONMENT TABLE (finding 167). A runner that reads a knob the table
# does not list, or lists with another default, and a row nothing reads: the
# table is where a student looks a knob up, and DIFF_MAX_ROWS was documented
# for every report while one runner read it. The probe sources the library,
# which is what makes it a runner; PROBE_WORDS's default is given in words,
# which the check leaves to a reader. PROBE_PFX is read only as the start of
# PROBE_PFX_LONG's name, which reads it no more than nothing does.
{
	printf '#!/bin/sh\nset -u\n. "$RL_LIB"\n'
	printf 'A="${PROBE_KNOB:-8}"\nB="${PROBE_NEW:-3}"\nC="${PROBE_WORDS:-5}"\n'
	printf 'D="${PROBE_SET:-4}"\nPROBE_SET=1\nE="${PROBE_PFX_LONG:-1}"\n'
	printf 'echo "$A$B$C$D$E$PROBE_SET"\n'
} > "$WORK/cv/tools/probe_knob.sh"
mkdir -p "$WORK/cv/docs"
{
	printf '# Reference\n\n## Environment variables\n\n'
	printf '| variable | default | does |\n|---|---|---|\n'
	printf '| `PROBE_KNOB` | `7` | a knob |\n'
	printf '| `PROBE_WORDS` | a few | a knob whose default is words |\n'
	printf '| `PROBE_DEAD`, `PROBE_PFX`, `PROBE_PFX_LONG` | `1` | knobs nothing reads, or only a longer name does |\n'
	printf '\n## Run targets\n\n| `PROBE_AFTER` | `2` | not in the table |\n'
	# The raised targets' why cells, which rl__raised prints under a red, read
	# as hints are (lines 19-21): one written as steps, one naming a wider
	# type, and one saying which reading the target holds.
	printf '\n## Targets raised above their layer\n\n| target | level | why |\n|---|---|---|\n'
	printf '| `//m:ex00_a_output` | strict | first read the number, then check its sign |\n'
	printf '| `//m:ex00_b_output` | strict | a value that needs a wider type than `int` |\n'
	printf '| `//m:ex00_c_output` | strict | a case the subject leaves open: this target holds a reading |\n'
} > "$WORK/cv/docs/reference.md"

# A file list of conventions.sh's own that skips symlinks, as a runfiles tree
# is made of (V23), beside one that asks for both: only the first is
# reported (its arm is under cv_lines, below). The fixture's
# tools/conventions.sh is read in place of the real one, and is gone before
# any later run.
printf '#!/bin/sh\nx=$(find . -type f -name y)\ny=$(find . \\( -type f -o -type l \\) -name y)\n' \
	> "$WORK/cv/tools/conventions.sh"
# Two memory probes of the toy module: one whose header -- the part
# asan_check.sh prints under a red -- names where the oracle lives, one whose
# header names the oracle by no path and keeps its label further down, in a
# comment nobody is shown (the mutation run of 2026-10-03: C 13 ex07's printed
# the path of the oracle's C 13 file). A file of the oracle's source is named
# in no comment at all, which the rule after the BUILD one holds.
printf '/* Probe for ft_a: draws as oracle/src/c98.rs does. */\nint\tmain(void)\n{\n\treturn (0);\n}\n' \
	> "$WORK/cv/$_cv_esc/ex00/mem_door.c"
{
	printf '/* Probe for ft_a: hands it a block of exactly its size. */\n'
	_cvi=0
	while [ "$_cvi" -lt 20 ]; do printf '\n'; _cvi=$((_cvi + 1)); done
	printf '/* The corpus comes from //oracle, for the maintainer. */\nint\tmain(void)\n{\n\treturn (0);\n}\n'
} > "$WORK/cv/$_cv_esc/ex00/mem_quiet.c"
# A one-line header ends on its own line: the comment below it is not
# printed, so the rule reads it no more than asan_check.sh shows it.
printf '/* Probe for ft_a: hands it a block of exactly its size. */\n/* The corpus comes from //oracle, for the maintainer. */\nint\tmain(void)\n{\n\treturn (0);\n}\n' \
	> "$WORK/cv/$_cv_esc/ex00/mem_after.c"
# One run of the check for the arms below, read one way each: each run walks
# the whole fixture tree, and the arms only differ in what they look for.
# Its status travels with its words, so a run that broke (exit 2) still fails
# every arm rather than letting the "is not reported" ones pass on nothing.
# Run only where these arms run: a shard that skips them skips it too. The
# fixture's conventions.sh goes in every shard, run or not. The arms over
# selftest_nmpin.sh, written further up, read this run too.
_cv_out=""
_cv_rc=0
if st_mine; then
	_cv_out=$(conv 2>&1)
	_cv_rc=$?
fi
rm -f "$WORK/cv/tools/conventions.sh" "$WORK/cv/tools/tests/selftest_slow_toys.sh" \
	"$WORK/cv/tools/tests/selftest_toy_heads.sh" \
	"$WORK/cv/tools/tests/selftest_nmpin.sh" "$WORK/cv/tools/tests/selftest_lib.sh" \
	"$WORK/cv/tools/tests/selftest_libuse.sh"
rm -rf "$WORK/cv/tools/tests/selftest_sections"
cv_seen() { printf '%s\n' "$_cv_out"; return "$_cv_rc"; }
cv_nm() {  # the run's report of selftest_nmpin.sh, a line each, and its status
	printf '%s\n' "$_cv_out" | grep -F 'selftest_nmpin.sh:' | sed 's/^[[:space:]]*//; s/$/|/'
	return "$_cv_rc"
}
want_out "conventions: an arm passing --nm without --nm-lib is reported" \
	'pinned nm without --nm-lib' -- cv_seen
want_out "conventions: ...on its own line" 'selftest_nmpin.sh:2|' -- cv_nm
want_out "conventions: ...over continuation lines, at the first" 'selftest_nmpin.sh:3|' -- cv_nm
want_out "conventions: ...in a variable of arguments" 'selftest_nmpin.sh:5|' -- cv_nm
want_out "conventions: ...in a make_test.sh that reads symbols" 'selftest_nmpin.sh:6|' -- cv_nm
want_broken_none "conventions: ...never with --nm-lib on a continuation line" \
	'selftest_nmpin.sh:7|' -- cv_nm
want_broken_none "conventions: ...nor in a make_test.sh that reads none" \
	'selftest_nmpin.sh:9|' -- cv_nm
want_broken_none "conventions: ...nor under its marker" 'selftest_nmpin.sh:11|' -- cv_nm
want_broken_none "conventions: ...nor with the marker ending its own line" \
	'selftest_nmpin.sh:12|' -- cv_nm
want_broken_none "conventions: ...nor in the helper's own body" \
	'selftest_nmpin.sh:14|' -- cv_nm
want_out "conventions: ...at a helper's call that reads symbols" \
	'selftest_nmpin.sh:16|' -- cv_nm
want_broken_none "conventions: ...never at one that reads none" \
	'selftest_nmpin.sh:17|' -- cv_nm
want_out "conventions: a probe header naming where the oracle lives is reported" \
	"$_cv_esc/ex00/mem_door.c:1:" -- cv_seen
want_broken_none "conventions: ...not one whose printed header names none" \
	'mem_quiet.c' -- cv_seen
want_broken_none "conventions: ...nor the comment below a one-line header" \
	'mem_after.c' -- cv_seen
rm -f "$WORK/cv/$_cv_esc/ex00/mem_door.c" "$WORK/cv/$_cv_esc/ex00/mem_quiet.c" \
	"$WORK/cv/$_cv_esc/ex00/mem_after.c"
want_out "conventions: a raised target's why written as steps is reported" \
	'docs/reference.md:19 (an instruction chained' -- cv_seen
want_out "conventions: ...and one naming a wider type" 'docs/reference.md:20: a value' -- cv_seen
want_broken_none "conventions: ...but not one saying which reading it holds" \
	'docs/reference.md:21' -- cv_seen
want_out "conventions: a sanitizer's options set by hand are reported" \
	'tools/probe_sanopts.sh:3:' -- cv_seen
want_broken_none "conventions: ...and rl_sanitizers is not" \
	'tools/probe_sanopts_ok.sh:' -- cv_seen
want_out "conventions: a symbolising runner outside _SYMBOLIZER_RUNNERS is reported" \
	'probe_sym_unlisted.sh symbolises a sanitizer' -- cv_seen
want_broken_none "conventions: ...and one that symbolises nothing is not" \
	'probe_sanopts_ok.sh symbolises' -- cv_seen
want_out "conventions: a runner that never asks how its sanitized run ended" \
	'tools/probe_sanask.sh:5: rl_sanitizers' -- cv_seen
want_broken_none "conventions: ...not one that asks rl_sanitized" 'probe_sanask_ok.sh:' -- cv_seen
want_broken_none "conventions: ...nor one that runs through rl_mem_run" 'probe_sanask_mem.sh:' -- cv_seen
want_broken_none "conventions: ...nor one marked as showing no report" 'probe_sanask_gate.sh:' -- cv_seen
want_out "conventions: a module's tests/*.sh looking for a report itself" \
	"$_cv_esc/probe_sanrep_mod.sh:3:" -- cv_seen
want_out "conventions: a runner showing a memory report keeps a file by a plain rl_save" \
	'tools/probe_keepin_check.sh:3: rl_save "$WORK/map" case-1.map || :' -- cv_seen
want_out "conventions: ...in a function too" 'tools/probe_keepin_check.sh:5: rl_save "$1" "$2"' -- cv_seen
want_out "conventions: ...and under a marker not on the line above" \
	'tools/probe_keepin_check.sh:9: rl_save "$WORK/replay" replay-1.sh || :' -- cv_seen
want_broken_none "conventions: ...not one keeping its input with rl_keep_input, its replay marked" \
	'probe_keepin_ok_check.sh:' -- cv_seen
want_broken_none "conventions: ...nor one that shows no memory report" \
	'probe_keepin_noreport_check.sh:' -- cv_seen
want_out "conventions: a rust_binary that does not deny warnings is reported" \
	'    rustwarn/BUILD.bazel' -- cv_seen
want_out "conventions: ...and so is a rule that runs rustc without the flag" \
	'    tools/probe_rustc.bzl' -- cv_seen
want_broken_none "conventions: ...and one that denies them is not" \
	'rustquiet/BUILD.bazel' -- cv_seen
want_out "conventions: a second rust target is held to the flag on its own" \
	'    rusttwo/BUILD.bazel:6 (a rules_rust target)' -- cv_seen
want_broken_none "conventions: ...its first one, which names it, is not reported" \
	'rusttwo/BUILD.bazel:1' -- cv_seen
want_broken_none "conventions: ...nor a target whose flags are a list holding it" \
	'rustlist/BUILD.bazel' -- cv_seen
want_broken_none "conventions: ...nor a rule whose flag list holds it" \
	'probe_rustc_ok.bzl' -- cv_seen
# The toy-file report without its ex05 line: nothing else may be in it.
cv_tw_rest() { printf '%s\n' "$_cv_out" | grep -vF '"$_cv99/ex05/check.sh"'; return "$_cv_rc"; }
# The links reported under the link rule, exactly: the three broken ones.
cv_lk() {
	[ "$_cv_rc" -lt 2 ] || return 2
	_lk=$(printf '%s\n' "$_cv_out" | awk '
		/a page links to a file, folder or heading that is not there/ { on = 1; next }
		on && /^ +docs\/links\.md:[0-9]+: / { print $2 }
		on && !/^ +docs\// { on = 0 }' | LC_ALL=C sort | tr '\n' ' ')
	[ "$_lk" = "../../outside.md linked.md#part-one-the-toolkit missing.md " ] && return 0
	echo "reported: $_lk"
	return 1
}
want_green "conventions: a page's broken links and anchors are named, and no other" -- cv_lk
want_out "conventions: a toy exercise's file written by two blocks is reported" \
	'"$_cv99/ex05/check.sh", written at lines 2 6' -- cv_seen
want_broken_none "conventions: ...and one written once, or appended to, is not" \
	'"$_cv99/ex0' -- cv_tw_rest
want_out "conventions: an arm calling a helper its file lacks is reported" \
	'selftest_toys.sh calls want_nothing() and never defines it' -- cv_seen
want_out "conventions: ...and so is one behind a ! ... ||" \
	'selftest_toys.sh calls want_gone() and never defines it' -- cv_seen
want_out "conventions: ...or as an if's condition" \
	'selftest_toys.sh calls later_absent() and never defines it' -- cv_seen
want_broken_none "conventions: ...but not a helper the file defines" 'calls want_here()' -- cv_seen
want_broken_none "conventions: ...nor one a comment names" 'calls want_ghost()' -- cv_seen
want_broken_none "conventions: ...nor one the library its driver sources defines" \
	'calls want_fromlib()' -- cv_seen
want_broken_none "conventions: ...however the library spells it" 'calls want_spaced()' -- cv_seen
want_out "conventions: a driver's own copy of an arm helper is reported" \
	'tools/tests/selftest_libuse.sh:4: want_red()' -- cv_seen
want_out "conventions: ...and one indented in a block" \
	'tools/tests/selftest_libuse.sh:7: st_inblock()' -- cv_seen
want_out "conventions: ...and one spelt name () {" \
	'tools/tests/selftest_libuse.sh:9: st_libonly()' -- cv_seen
want_broken_none "conventions: ...never the library's own" 'selftest_lib.sh:2: want_fromlib()' -- cv_seen
want_out "conventions: a stand-in reference written by hand is reported" \
	'tools/tests/selftest_libuse.sh:5: writes the here-document st_oracle writes' -- cv_seen
want_broken_none "conventions: ...never the library's" \
	'selftest_lib.sh:3: writes the here-document' -- cv_seen
want_out "conventions: a slow selftest toy built with its compiler's words thrown away is reported" \
	'tools/tests/selftest_slow_toys.sh:2: "$CC" -w -o "$WORK/tc_lost"' -- cv_seen
want_broken_none "conventions: ...not one a comment names" 'selftest_slow_toys.sh:3:' -- cv_seen
want_out "conventions: ...and one that keeps them in a file it only prints" \
	'tools/tests/selftest_slow_toys.sh:4: "$CC" -o "$WORK/tc_kept"' -- cv_seen
want_broken_none "conventions: ...nor a toy_cc call" 'selftest_slow_toys.sh:5:' -- cv_seen
want_out "conventions: ...and one after && on the line before" \
	'tools/tests/selftest_slow_toys.sh:7: ' -- cv_seen
want_broken_none "conventions: ...never a printf's word on a continuation line" \
	'selftest_slow_toys.sh:10:' -- cv_seen
want_broken_none "conventions: ...an assignment or an argument" 'selftest_slow_toys.sh:11:' -- cv_seen
want_broken_none "conventions: ...or a probe marked as one" 'selftest_slow_toys.sh:13:' -- cv_seen
want_out "conventions: ...but an unmarked probe is reported" \
	'tools/tests/selftest_slow_toys.sh:14: if "$CC"' -- cv_seen
want_out "conventions: ...and a section's toy too" \
	'tools/tests/selftest_sections/toys.sh:2: "$CC" -o "$WORK/tc_section"' -- cv_seen
want_out "conventions: ...and one the pinned gcc builds, after {" \
	'tools/tests/selftest_slow_toys.sh:22: ! st_mine || { "$GCC"' -- cv_seen
want_out "conventions: ...or any compiler named *_CC" \
	'tools/tests/selftest_slow_toys.sh:25: "$I32_CC"' -- cv_seen
want_broken_none "conventions: ...never the compiler toy_cc --cc is handed" \
	'selftest_slow_toys.sh:24:' -- cv_seen
want_out "conventions: ...and one after elif" \
	'tools/tests/selftest_toy_heads.sh:2: if [' -- cv_seen
want_out "conventions: ...after while" \
	'tools/tests/selftest_toy_heads.sh:3: while' -- cv_seen
want_out "conventions: ...after until" \
	'tools/tests/selftest_toy_heads.sh:4: until' -- cv_seen
want_out "conventions: ...behind env NAME=VALUE" \
	'tools/tests/selftest_toy_heads.sh:5: env' -- cv_seen
want_out "conventions: ...behind timeout N" \
	'tools/tests/selftest_toy_heads.sh:6: timeout' -- cv_seen
want_out "conventions: ...behind bounded N" \
	'tools/tests/selftest_toy_heads.sh:7: bounded' -- cv_seen
want_out "conventions: ...spelt \"\${CC}\"" \
	'tools/tests/selftest_toy_heads.sh:8: "${CC}"' -- cv_seen
want_out "conventions: ...spelt bare, \$CC" \
	'tools/tests/selftest_toy_heads.sh:9: $CC' -- cv_seen
want_out "conventions: ...behind an assignment" \
	'tools/tests/selftest_toy_heads.sh:10: CFLAGS=-w' -- cv_seen
want_broken_none "conventions: ...never an argument behind env" \
	'selftest_toy_heads.sh:11:' -- cv_seen
want_broken_none "conventions: ...an assignment's quoted words" \
	'selftest_toy_heads.sh:12:' -- cv_seen
want_broken_none "conventions: ...a printf's quoted text" \
	'selftest_toy_heads.sh:13:' -- cv_seen
want_broken_none "conventions: ...an argument inside \$( )" \
	'selftest_toy_heads.sh:14:' -- cv_seen
want_broken_none "conventions: ...or toy_cc's own body" \
	'selftest_toy_heads.sh:16:' -- cv_seen
want_out "conventions: a skip line printed by hand is reported" \
	'tools/tests/selftest_slow_toys.sh:15: printf' -- cv_seen
want_broken_none "conventions: ...never st_unsupplied's, its verdict on the next line" \
	'selftest_slow_toys.sh:17:' -- cv_seen
want_broken_none "conventions: ...nor an arm's quoted words" 'selftest_slow_toys.sh:18:' -- cv_seen
want_out "conventions: ...and one with a reason, by hand, is reported" \
	'tools/tests/selftest_slow_toys.sh:19: printf' -- cv_seen
want_broken_none "conventions: ...never st_skipped's, its verdict on the next line" \
	'selftest_slow_toys.sh:21:' -- cv_seen
want_out "conventions: a section that reads the shard flag st_mine reads is reported" \
	'tools/tests/selftest_sections/toys.sh:3: [ "$_st_mine" = 1 ]' -- cv_seen
want_broken_none "conventions: ...never a comment that names it" \
	'selftest_sections/toys.sh:4:' -- cv_seen
want_out "conventions: a toy written through a loop and by a statement is reported" \
	'"$_cv99/ex90/diff_x.c", written at lines' -- cv_seen
want_out "conventions: a toy made by two statements, one a helper's, is reported" \
	'"$_cv99/ex91", made at lines' -- cv_seen
want_out "conventions: a toy named in two sections is reported" \
	'"$_cv99/ex92": [(no section)]' -- cv_seen
want_broken_none "conventions: ...and the loop's other toy, used once, is not" '"$_cv99/ex93' -- cv_seen
want_out "conventions: a toy's file written by > and by 2> is reported" \
	'"$_cv99/ex94/out.txt", written at lines' -- cv_seen
want_out "conventions: ...and by > and by &>" \
	'"$_cv99/ex95/out.txt", written at lines' -- cv_seen
want_out "conventions: a toy made in a one-line helper and by a statement is reported" \
	'"$_cv99/ex96", made at lines' -- cv_seen
want_out "conventions: ...and in one continued over two lines" \
	'"$_cv99/ex97", made at lines' -- cv_seen
want_out "conventions: ...and below a usage comment that shows a here-document (V170)" \
	'"$_cv99/ex89", made at lines' -- cv_seen
want_out "conventions: ...a toy's file written through such a helper's \$1 by two calls" \
	'"$_cv99/ex98/out.txt", written at lines' -- cv_seen
want_out "conventions: a fixture tree's TODO.md written twice is reported" \
	'"$WORK/cv/TODO.md", written at lines' -- cv_seen
want_broken_none "conventions: ...and a HISTORY.md written once, then appended to, is not" \
	'"$WORK/cv/HISTORY.md", written' -- cv_seen
want_out "conventions: ...and a plan's file under todo/ written twice is" \
	'"$WORK/cv/todo/plans/p1.md", written at lines' -- cv_seen
want_broken_none "conventions: ...and one written once is not" \
	'"$WORK/cv/todo/plans/p2.md", written' -- cv_seen
want_out "conventions: ...and one written twice through a variable holding its folder" \
	'"$WORK/cv/todo/plans/p3.md", written at lines' -- cv_seen
want_broken_none "conventions: ...never once, then once more after the variable is set again" \
	'"$WORK/cv/todo/plans/p4.md", written' -- cv_seen
# cv_trees HEADLINE WANT -- the trees the report under HEADLINE lists,
# sorted, are exactly WANT.
cv_trees() {
	[ "$_cv_rc" -lt 2 ] || return 2
	_tt=$(printf '%s\n' "$_cv_out" | awk -v h="$1" '
		index($0, h) { on = 1; next }
		on && /^ +"\$WORK\/[^"]*":/ { t = $1; sub(/^"\$WORK\//, "", t); sub(/":$/, "", t); print t; next }
		{ on = 0 }' | LC_ALL=C sort | tr '\n' ' ')
	[ "$_tt" = "$2 " ] && return 0
	echo "reported trees: $_tt"
	return 1
}
want_out "conventions: a fixture tree named in two sections is reported" \
	'"$WORK/tt_shared": [another section] (line' -- cv_seen
# tt_alias, tt_looped and tt_shared, and none of tt_own, tt_loop, tt_pre, cv,
# tt_file.log, tt_var or tt_read; tt_arg, tt_argl and tt_body through a
# helper, and neither tt_only nor tt_not; tt_hdc below a usage comment that
# shows a here-document.
want_green "conventions: ...through a loop or a variable too, and no other tree" -- \
	cv_trees 'selftest_toys.sh names one fixture tree in two sections' \
	'tt_alias tt_arg tt_argl tt_body tt_hdc tt_looped tt_shared'
want_out "conventions: ...and through a helper's positional parameter" \
	'"$WORK/tt_arg": [a fourth section] (line' -- cv_seen
# tt_pre and tt_premk, and neither tt_prer nor cv; and each tree V154's
# writes go into.
want_green "conventions: a write from a section into a tree made before the first is reported" -- \
	cv_trees 'selftest_toys.sh writes from a section into a fixture tree made before the first' \
	'tt_pre tt_prebq tt_precp tt_pregit tt_preif tt_preln tt_premk tt_premv tt_prerm tt_presed tt_preshift tt_presub tt_pretee tt_pretest tt_pretouch'

# cv_lines FILE "N N ..." -- true when the lines of FILE that the run above
# reported are exactly those, in any report. Says what it saw when not.
cv_lines() {
	[ "$_cv_rc" -lt 2 ] || return 2
	_cl=$(printf '%s\n' "$_cv_out" | sed -n "s|^ *$1:\([0-9][0-9]*\):.*|\1|p" | sort -n -u | tr '\n' ' ')
	[ "$_cl" = "$2 " ] && return 0
	echo "reported lines: $_cl (want: $2)"
	return 1
}
want_green "conventions: a find of its own that skips symlinks is reported" -- \
	cv_lines tools/conventions.sh "2"
want_out "conventions: a runner's message quoting one subject is reported" \
	"a runner's message names one project, or cites a page" -- cv_seen
want_green "conventions: ...its message line, not the comment or a program's name" -- \
	cv_lines tools/probe_quote.sh "5 9"
want_green "conventions: ...and a sourced library's message saying what the subject says" -- \
	cv_lines tools/probe_saylib.sh "4"
want_broken_none "conventions: ...but not a library no runner and no check script sources" \
	'probe_termlib.sh:' -- cv_seen
want_green "conventions: ...and a # line a here-document prints, not one it writes to a file" -- \
	cv_lines tools/probe_hdquote.sh "13 19"
# The project names come from the module table, never from a list kept in the
# check: one of the Piscine's names let the first Common Core project through.
# A workspace of its own (cv6) whose table holds a Piscine module the old list
# could not spell (C 94) and a Common Core one (cursus/ft_toy); a runner that
# names each, in an echo and in a here-document it prints, beside a program's
# own name and a comment, which are no project's. And a BUILD file that types
# out the Norm, beside one that loads it from tools/defs.bzl.
mkdir -p "$WORK/cv6/tools" "$WORK/cv6/c-piscine/c-piscine-c-94" "$WORK/cv6/cursus/ft_toy"
cv_submit "c-piscine/c-piscine-c-94 cursus/ft_toy" > "$WORK/cv6/tools/submit.sh"
printf 'q = {"wildcards": "The Norm, v9.9, I.1: \\"name it\\""}\n' \
	> "$WORK/cv6/c-piscine/c-piscine-c-94/BUILD.bazel"
printf 'q = {"wildcards": NORM_NO_WILDCARDS}\n' > "$WORK/cv6/cursus/ft_toy/BUILD.bazel"
{
	printf '#!/bin/sh\nset -u\n. "$RL_LIB"\n'
	printf '# ft_toy is where this rule came from\n'
	printf 'echo "  Ft_Toy asks for it."\n'
	printf 'echo "  C 94 asks for it too."\n'
	printf 'cat <<EOF\n'
	printf '  The ft-toy subject says so.\n'
	printf 'EOF\n'
	printf 'echo "  replay: ./ft_toy x, or my_ft_toy.c"\n'
} > "$WORK/cv6/tools/probe_names.sh"
# Run only where its arms run, as cv's is.
_cv6_out=""
_cv6_rc=0
if st_mine; then
	_cv6_out=$(env BUILD_WORKSPACE_DIRECTORY="$WORK/cv6" "$SH" "$TOOLS/conventions.sh" 2>&1)
	_cv6_rc=$?
fi
cv6_lines() {  # cv6_lines FILE "N N ...": the lines of FILE cv6's run reported
	[ "$_cv6_rc" -lt 2 ] || { printf '%s\n' "$_cv6_out"; return 2; }
	_cl=$(printf '%s\n' "$_cv6_out" | sed -n "s|^ *$1:\([0-9][0-9]*\):.*|\1|p" | sort -n -u | tr '\n' ' ')
	[ "$_cl" = "$2 " ] && return 0
	echo "reported lines: $_cl (want: $2)"
	return 1
}
want_green "conventions: a project's name from the module table is reported, a heredoc's too" -- \
	cv6_lines tools/probe_names.sh "5 6 8"
cv6_seen() { printf '%s\n' "$_cv6_out"; return "$_cv6_rc"; }
want_out "conventions: a BUILD file typing out the Norm is reported" \
	'c-piscine/c-piscine-c-94/BUILD.bazel quotes the Norm in words of its own' -- cv6_seen
want_broken_none "conventions: ...and one loading it is not" \
	'cursus/ft_toy/BUILD.bazel quotes the Norm' -- cv6_seen
# Every probe a c_mem_check names opens with a header of its own, where its
# fault is written down and what asan_check.sh prints under a red (V149). A
# workspace of its own (cvh): a probe whose comment comes after an #include,
# one that opens with the 42 banner, one whose comment says nothing, a call
# whose probe is not there; quiet, a unit's probe over several lines, its
# call read and its probe found in tests/<unit>/, and a one-line header.
_cvh=c-piscine/c-piscine-c-92
mkdir -p "$WORK/cvh/tools" "$WORK/cvh/$_cvh/tests/ex00" "$WORK/cvh/$_cvh/tests/ex01" \
	"$WORK/cvh/$_cvh/tests/toy_len"
cv_submit "$_cvh" > "$WORK/cvh/tools/submit.sh"
{
	printf 'c_mem_check(num = "00", fn = "ft_a", probe = "mem_bare.c")\n\n'
	printf 'c_mem_check(\n    num = "00",\n    fn = "ft_b",\n    probe = "mem_banner.c",\n)\n\n'
	printf 'c_mem_check(num = "01", fn = "ft_c", probe = "mem_empty.c")\n\n'
	printf 'c_mem_check(num = "01", fn = "ft_d", probe = "mem_gone.c")\n\n'
	printf 'c_mem_check(\n    unit = "toy_len",\n    probe = "mem_ok.c")\n\n'
	printf 'c_mem_check(num = "01", fn = "ft_e", probe = "mem_one.c")\n'
} > "$WORK/cvh/$_cvh/BUILD.bazel"
printf '#include <stdlib.h>\n/* A block of exactly n bytes: a read past it is caught. */\n' \
	> "$WORK/cvh/$_cvh/tests/ex00/mem_bare.c"
printf '%s\nint\tmain(void);\n' "$FR_H" > "$WORK/cvh/$_cvh/tests/ex00/mem_banner.c"
printf '/*\n *\n */\nint\tmain(void);\n' > "$WORK/cvh/$_cvh/tests/ex01/mem_empty.c"
printf '/*\n * A string in a block of exactly its length plus one: a read past\n * the terminator is caught.\n */\n' \
	> "$WORK/cvh/$_cvh/tests/toy_len/mem_ok.c"
printf '/* One block of n bytes, nothing valid after it. */\n' > "$WORK/cvh/$_cvh/tests/ex01/mem_one.c"
_cvh_out=""
_cvh_rc=0
if st_mine; then
	_cvh_out=$(env BUILD_WORKSPACE_DIRECTORY="$WORK/cvh" "$SH" "$TOOLS/conventions.sh" 2>&1)
	_cvh_rc=$?
fi
cvh_seen() { printf '%s\n' "$_cvh_out"; return "$_cvh_rc"; }
want_out "conventions: a memory probe with no header of its own is reported" \
	"$_cvh/tests/ex00/mem_bare.c:1: opens with no header comment ($_cvh/BUILD.bazel:1)" -- cvh_seen
want_out "conventions: ...one opening with the 42 banner" \
	"$_cvh/tests/ex00/mem_banner.c:1: opens with a 42 banner" -- cvh_seen
want_out "conventions: ...one whose header says nothing" \
	"$_cvh/tests/ex01/mem_empty.c:1: its header comment says nothing" -- cvh_seen
want_out "conventions: ...and a call whose probe is not there" \
	"$_cvh/BUILD.bazel:11: its probe $_cvh/tests/ex01/mem_gone.c is not there" -- cvh_seen
want_broken_none "conventions: ...not a unit's probe with a header" 'mem_ok.c' -- cvh_seen
want_broken_none "conventions: ...whose call, naming its unit, is read" \
	'is not a literal string' -- cvh_seen
want_broken_none "conventions: ...nor a one-line header" 'mem_one.c' -- cvh_seen
# The runners that say why a raised test sits where it does (defs.bzl's
# _LIB_RUNNERS, which c_levels()' audit reads) are exactly those that source
# runner_lib.sh. A workspace of its own (cvr): a listed runner that sources
# it, one that sources it unlisted, and a listed one that sources nothing.
mkdir -p "$WORK/cvr/tools" "$WORK/cvr/c-piscine/c-piscine-c-93"
cv_submit "c-piscine/c-piscine-c-93" > "$WORK/cvr/tools/submit.sh"
printf '\n' > "$WORK/cvr/c-piscine/c-piscine-c-93/BUILD.bazel"
printf '#!/bin/sh\nset -u\n. "$RL_LIB"\n' > "$WORK/cvr/tools/probe_says.sh"
printf '#!/bin/sh\nset -u\n. "$RL_LIB"\n' > "$WORK/cvr/tools/probe_unlisted.sh"
printf '#!/bin/sh\nset -u\n:\n' > "$WORK/cvr/tools/probe_silent.sh"
printf '_LIB_RUNNERS = [\n    "//tools:probe_says.sh",\n    "//tools:probe_silent.sh",\n]\n' \
	> "$WORK/cvr/tools/defs.bzl"
# The runners whose gated tests the audit holds to a --gate-label (defs.bzl's
# _GATE_LABEL_RUNNERS) are exactly those whose option loop takes it and
# --gate-differ: one listed that takes both, one unlisted that does, and a
# listed one that takes neither (probe_silent.sh).
printf '#!/bin/sh\nset -u\ncase $1 in\n\t--gate-differ) shift 2 ;;\n\t--gate-label) shift 2 ;;\nesac\n' \
	> "$WORK/cvr/tools/probe_glabel.sh"
cp "$WORK/cvr/tools/probe_glabel.sh" "$WORK/cvr/tools/probe_glabel_unlisted.sh"
printf '_GATE_LABEL_RUNNERS = [\n    "//tools:probe_glabel.sh",\n    "//tools:probe_silent.sh",\n]\n' \
	>> "$WORK/cvr/tools/defs.bzl"
# And a runner that takes a gate and not the name of the test it waits for
# (V169): its SKIP line can name no test.
printf '#!/bin/sh\nset -u\ncase $1 in\n\t--gate-differ) shift 2 ;;\nesac\n' \
	> "$WORK/cvr/tools/probe_gdiff.sh"
# README.md's worked red is held to the files it shows: its legend kept a
# sentence diff_output.sh had dropped, under a cell showing a line end the
# expected file does not have. In cvr: a toy exercise whose one expected
# line has no end, its hint, and a diff_output.sh composing its legend as
# the real one does; a README showing the old legend, the cell with a $ and
# a hint no row begins with (reported), then one showing what the runner
# prints (quiet).
mkdir -p "$WORK/cvr/c-piscine/c-piscine-c-93/tests/ex01"
printf 'abc' > "$WORK/cvr/c-piscine/c-piscine-c-93/tests/ex01/expected.txt"
printf '# hints\nWhat comes after a?\n' > "$WORK/cvr/c-piscine/c-piscine-c-93/tests/ex01/clues.tsv"
{
	printf '#!/bin/sh\n'
	printf '%s\n' "if (dollar)  mk[++nmarks] = \"\$ is where a line ended\"" \
		'legend = "In the table, " rl_vis_join(mk, nmarks)'
} > "$WORK/cvr/tools/diff_output.sh"
cvr_readme() {  # cvr_readme CELL LEGEND HINT [EX]: a README whose worked red shows them
	{
		printf '# Toy\n\n```sh\ncd c-piscine/c-piscine-c-93/deliverable/ex01\n42 test\n```\n\n```\n'
		printf '  THE LOG OF //c-piscine/c-piscine-c-93:%s_output\n\n' "${4:-ex01}"
		printf ' CASE   | EXPECTED | GOT       | STATUS\n line 1 | %s | (no line) | FAIL <\n' "$1"
		[ -z "$2" ] || printf ' %s\n' "$2"
		printf ' HINTS:\n   * %s [...]\n```\n' "$3"
	} > "$WORK/cvr/README.md"
}
cvr_readme 'abc$' 'In the failing rows, $ is where a line ended.' 'What comes before z?'
! st_mine || env BUILD_WORKSPACE_DIRECTORY="$WORK/cvr" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvr.out" 2>&1
cvr_seen() { cv_saved "$WORK/cvr.out"; }
want_out "conventions: README's worked red showing a line end its file lacks" \
	'line 1: the table shows "abc$", and c-piscine/c-piscine-c-93/tests/ex01/expected.txt gives "abc"' -- cvr_seen
want_out "conventions: ...and a legend the runner does not print there" \
	'the legend "In the failing rows, $ is where a line ended." is shown under cells holding no mark' -- cvr_seen
want_out "conventions: ...and a hint no row of its clues.tsv begins with" \
	'the hint shown begins no row of c-piscine/c-piscine-c-93/tests/ex01/clues.tsv' -- cvr_seen
cvr_readme 'abc' '' 'What comes after a?'
cvr_again() { env BUILD_WORKSPACE_DIRECTORY="$WORK/cvr" "$SH" "$TOOLS/conventions.sh" 2>&1; }
want_broken_none "conventions: ...but not one showing what the runner prints" \
	"README.md's worked red" -- cvr_again
# The table is checked against the target 42 names above it, THE LOG OF: the
# same table under another exercise's name is that exercise's file's to match.
mkdir -p "$WORK/cvr/c-piscine/c-piscine-c-93/tests/ex02"
printf 'xyz' > "$WORK/cvr/c-piscine/c-piscine-c-93/tests/ex02/expected.txt"
cvr_readme 'abc' '' 'What comes after a?' ex02
want_out "conventions: ...and checks it against the target THE LOG OF names" \
	'line 1: the table shows "abc", and c-piscine/c-piscine-c-93/tests/ex02/expected.txt gives "xyz"' -- cvr_again
cvr_readme 'abc' '' 'What comes after a?'
want_out "conventions: a runner sourcing runner_lib.sh missing from _LIB_RUNNERS" \
	'sources the library, not listed: tools/probe_unlisted.sh' -- cvr_seen
want_out "conventions: ...and one listed that sources nothing" \
	'listed, and sources nothing: tools/probe_silent.sh' -- cvr_seen
want_broken_none "conventions: ...but not one listed that sources it" \
	'tools/probe_says.sh' -- cvr_seen
want_out "conventions: a runner taking --gate-differ and --gate-label missing from _GATE_LABEL_RUNNERS" \
	'takes both, not listed: tools/probe_glabel_unlisted.sh' -- cvr_seen
want_out "conventions: ...and one listed that takes neither" \
	'listed, and takes not both: tools/probe_silent.sh' -- cvr_seen
want_broken_none "conventions: ...but not one listed that takes both" \
	'takes not both: tools/probe_glabel.sh' -- cvr_seen
want_out "conventions: a runner taking --gate-differ and no --gate-label" \
	'takes --gate-differ, no --gate-label: tools/probe_gdiff.sh' -- cvr_seen
want_broken_none "conventions: ...but not one taking both" \
	'no --gate-label: tools/probe_glabel' -- cvr_seen
want_out "conventions: a signal trap that does not exit is reported" \
	'tools/probe_trap.sh:4:' -- cv_seen
want_broken_none "conventions: ...and cleanup on EXIT, exit on TERM, is not" \
	'tools/probe_trap_ok.sh:' -- cv_seen
want_out "conventions: a runner's own trap beside runner_lib's is reported" \
	'tools/probe_libtrap.sh:5:' -- cv_seen
# Each read in its own rule's report alone: a probe's name is in other
# rules' reports too (no Usage block, no require line).
cv_inrule() {  # cv_inrule HEADING: the lines of the report under that heading
	printf '%s\n' "$_cv_out" | awk -v h="FAIL: $1" 'index($0, h) { on = 1; next } /^  FAIL: / { on = 0 } on'
	return "$_cv_rc"
}
want_out "conventions: a script reading the loader's lines itself is reported" \
	"tools/probe_ldparse.sh:3: sed -n 's/.*calling init" -- cv_inrule "a script reads the loader's lines itself"
want_out "conventions: ...in a folder under tools/ too" \
	'tools/cc_toolchain/probe_ldparse.sh:3: echo "${1#*calling init: }"' -- cv_inrule "a script reads the loader's lines itself"
want_broken_none "conventions: ...never one naming them in a comment" \
	'tools/probe_ldparse_ok.sh' -- cv_inrule "a script reads the loader's lines itself"
want_out "conventions: a script probing a tool under LD_DEBUG=libs itself is reported" \
	'tools/probe_ldprobe.sh:3: env -u LD_DEBUG_OUTPUT' -- \
	cv_inrule "a script runs a program under LD_DEBUG=libs itself"
want_out "conventions: ...in a folder under tools/ too" \
	'tools/cc_toolchain/probe_ldprobe.sh:3: LD_DEBUG=libs "$1" --version' -- \
	cv_inrule "a script runs a program under LD_DEBUG=libs itself"
want_broken_none "conventions: ...never one naming it in a comment" \
	'tools/probe_ldprobe_ok.sh' -- cv_inrule "a script runs a program under LD_DEBUG=libs itself"
want_out "conventions: a runner reading --inc-file itself is reported" \
	'tools/probe_incfile.sh:5: --inc-file)' -- cv_inrule "a runner reads its --inc-file list itself"
want_broken_none "conventions: ...never one calling rl_inc_file" \
	'tools/probe_incfile_ok.sh' -- cv_inrule "a runner reads its --inc-file list itself"
want_out "conventions: a runner bounding a run itself is reported" \
	'probe_budget.sh:9: bounds a run itself' -- cv_seen
want_broken_none "conventions: ...never one that says it bounds itself, and why" \
	'probe_bound_ok.sh:' -- cv_seen
want_out "conventions: ...whose marker covers the line below it alone" \
	'probe_bound_far.sh:13: bounds a run itself' -- cv_seen
want_out "conventions: ...and exempts no runner that sources runner_lib" \
	'probe_bound_lib.sh:13: bounds a run itself' -- cv_seen
want_out "conventions: ...nor one a test names in its srcs" \
	'probe_bound_test.sh:12: bounds a run itself' -- cv_seen
want_out "conventions: a test's runner must source runner_lib, or say" \
	'tools/probe_budget.sh: named in the srcs of a test' -- cv_seen
want_broken_none "conventions: ...one that says it runs no student code need not" \
	'tools/probe_cut.sh: named in the srcs' -- cv_seen
want_broken_none "conventions: ...and a sh_binary's srcs is not a test" \
	'tools/probe_bin.sh' -- cv_seen
want_out "conventions: ...and running the program bare is reported" \
	'probe_budget.sh:10: runs "$BIN" outside rl_run' -- cv_seen
want_broken_none "conventions: a script naming the option loop only in a comment is no runner to the SKIP rule" \
	'probe_doc_loop.sh has a SKIP' -- cv_seen
want_out "conventions: ...and a bound spelt behind if" 'probe_budget.sh:11: bounds a run itself' -- cv_seen
want_out "conventions: ...behind while" 'probe_budget.sh:12: bounds a run itself' -- cv_seen
want_out "conventions: ...behind env" 'probe_budget.sh:13: bounds a run itself' -- cv_seen
want_out "conventions: ...and behind exec" 'probe_budget.sh:14: bounds a run itself' -- cv_seen
want_out "conventions: ...and behind setsid" 'probe_budget.sh:15: bounds a run itself' -- cv_seen
want_out "conventions: ...where the program it bounds runs outside rl_run too" \
	'probe_budget.sh:15: runs "$BIN" outside rl_run' -- cv_seen
want_broken_none "conventions: ...never a case on the program's name" \
	'runs "$BIN" outside rl_run: case' -- cv_seen
want_green "conventions: a program run by path, whatever wraps it or names it" -- \
	cv_lines tools/probe_shapes.sh "10 11 12 13 14 15"
want_green "conventions: a cut of a stream's start, in any runner" -- \
	cv_lines tools/probe_cut.sh "4 5 6 7 8 17 18"
want_green "conventions: a byte renderer of a script's own, in every form" -- \
	cv_lines tools/probe_render.sh "11 12 13 14 17 18 19 20 21"
want_green "conventions: a runner looking for a sanitizer's report itself" -- \
	cv_lines tools/probe_sanrep.sh "12 15"
want_green "conventions: a diff shown raw, not rl_udiff's or one that only answers" -- \
	cv_lines tools/probe_udiff.sh "13 14 15 22"
want_green "conventions: a legend of the marks as fixed text, not one marked or read off" -- \
	cv_lines tools/probe_legend.sh "13 15 23"
want_green "conventions: an args word quoted by hand, not shell_word's own" -- \
	cv_lines tools/probe_quote.bzl "6 9 10 11 12"
want_green "conventions: a tab written \\t inside [ ] of a grep or sed" -- \
	cv_lines tools/probe_blank.sh "11 12"
want_green "conventions: an escape a test program writes, undeclared" -- \
	cv_lines "$_cv_esc/ex00/test_esc.c" "6 7"
want_broken_none "conventions: ...one its c_function declares is not" \
	'test_esc_ok.c' -- cv_seen
want_broken_none "conventions: ...nor is a reading's main its own case declares, whatever the call says" \
	'read_esc_own.c' -- cv_seen
want_green "conventions: ...but one whose case does not is, though the call declares it" -- \
	cv_lines "$_cv_esc/ex01/read_esc.c" "4"
want_broken_none "conventions: ...and its sibling whose case declares it is not" \
	'read_esc_ok.c' -- cv_seen
want_green "conventions: ...and one a c_header case shows, though a c_function declares it" -- \
	cv_lines "$_cv_esc/ex01/both_esc.c" "4"
# The harness is also handed to another package by exports_files (the
# selftest builds C 02 ex12's): that wires it to no runner, so no table.
want_broken_none "conventions: ...nor a c_diff harness's, exported too" 'diff_esc.c writes an escape' -- cv_seen
want_out "conventions: ...and a header no call names is" \
	"$_cv_esc/ex01/orphan_esc.h writes an escape" -- cv_seen
want_green "conventions: ...and a test program that is a symlink is read" -- \
	cv_lines "$_cv_esc/ex02/test_link.c" "4"
want_green "conventions: ...and one writing it through notation.h, undeclared" -- \
	cv_lines "$_cv_esc/ex03/test_nt.c" "2 6"
want_broken_none "conventions: ...never the same file its c_function declares" \
	'test_nt_ok.c' -- cv_seen
want_green "conventions: ...and one writing it through fd_capture.h, undeclared" -- \
	cv_lines "$_cv_esc/ex03/test_fc.c" "1"
want_out "conventions: an _ESC_BY_MACRO entry with no escape is reported" \
	"_ESC_BY_MACRO lists c-piscine/c-piscine-rush-00/tests/ex00/rush_capture.h" -- cv_seen
rm -f "$WORK/cv/$_cv_esc/ex00/test_esc.c" "$WORK/cv/$_cv_esc/ex01/test_esc_ok.c" \
	"$WORK/cv/$_cv_esc/ex01/read_esc.c" "$WORK/cv/$_cv_esc/ex01/read_esc_ok.c" \
	"$WORK/cv/$_cv_esc/ex00/read_esc_own.c" "$WORK/cv/$_cv_esc/ex01/both_esc.c" \
	"$WORK/cv/$_cv_esc/ex01/diff_esc.c" "$WORK/cv/$_cv_esc/ex01/orphan_esc.h" \
	"$WORK/cv/$_cv_esc/ex02/test_link.c"
rm -rf "$WORK/cv_esc_src" "$WORK/cv/$_cv_esc/ex03"
want_out "conventions: a contract units.awk cannot read is named, with its line" \
	'units.awk: c-piscine/c-piscine-c-89/BUILD.bazel:4: ' -- cv_seen
want_broken_none "conventions: ...never one it reads" 'units.awk: c-piscine/c-piscine-c-88/' -- cv_seen
want_broken_none "conventions: ...as it does a contract written entry by entry" \
	'c-piscine/c-piscine-c-88/BUILD.bazel: ex0' -- cv_seen
want_green "conventions: a trap wherever a command starts" -- \
	cv_lines tools/probe_trap2.sh "3 4"
want_green "conventions: ...elif's condition too" -- cv_lines tools/probe_trap3.sh "3"
want_out "conventions: what env, xargs, nohup, stdbuf and time run is a call" \
	'calls:    cut env grep head sort tr xargs' -- \
	cv_inrule "tools/probe_reqwrap.sh's require list does not match what it calls"
want_green "conventions: a clue file read by any name, or taken for nothing" -- \
	cv_lines tools/probe_clue2.sh "5 9"
want_green "conventions: ...an alias of it read by a redirect" -- \
	cv_lines tools/probe_clue3.sh "11"
want_broken_none "conventions: rl_run before it, even continued, is not" \
	'tools/probe_budget_ok.sh:' -- cv_seen
want_out "conventions: a runner of student code missing from defs.bzl's list" \
	'_EXIT_STATUS_RUNNERS lacks //tools:probe_budget_ok.sh' -- cv_seen
want_out "conventions: a runner's bare head on captured output is reported" \
	'probe_excerpt.sh:4:' -- cv_seen
want_broken_none "conventions: ...a value, a marked line, rl_excerpt are not" \
	'tools/probe_excerpt_ok.sh:' -- cv_seen
cv_rawcap() {  # the lines of probe_rawcap.sh its own rule reports, and the status
	_cr=$(cv_inrule "a runner prints what a run wrote without the renderer" |
		sed -n 's|^ *tools/probe_rawcap\.sh:\([0-9][0-9]*\):.*|\1|p' | tr '\n' ' ')
	[ "$_cv_rc" -lt 2 ] || return 2
	[ "$_cr" = "4 6 9 " ] && return 0
	echo "reported lines: $_cr (want: 4 6 9)"
	return 1
}
want_green "conventions: a runner's raw cat of what a run wrote, by rl_run, a group or a function" -- \
	cv_rawcap
want_out "conventions: a runner reading clues.tsv itself is reported" \
	'probe_clue.sh:3:' -- cv_seen
want_broken_none "conventions: ...forwarding and testing it are not" \
	'tools/probe_clue_ok.sh:' -- cv_seen
want_out "conventions: a library's probe loop is checked like require" \
	"probe_lib.sh's require list does not match" -- cv_seen
want_out "conventions: ...and a library with no loop that calls a tool is reported" \
	'probe_libnoloop.sh calls PATH commands and declares none' -- cv_seen
want_out "conventions: ...ls among them" \
	'probe_libls.sh calls PATH commands and declares none' -- cv_seen
want_broken_none "conventions: ...while one that calls none is not" \
	'probe_libnone.sh' -- cv_seen
want_broken_none "conventions: a name in a quoted awk program is not a call" \
	'probe_awkvar.sh' -- cv_seen
want_broken_none "conventions: ...nor in one spanning lines" \
	'probe_awkvar2.sh' -- cv_seen
want_broken_none "conventions: ...nor an awk regex or an empty string there" \
	'probe_awkvar3.sh' -- cv_seen
want_broken_none "conventions: sh -c's string, \$(( \$( ) )), a -- command run" \
	'probe_wordrun.sh' -- cv_seen
want_broken_none "conventions: ...sh -ec's, sh -e -c's, a double-quoted one" \
	'probe_wordrun2.sh' -- cv_seen
want_broken_none "conventions: a tool a written program runs, declared" \
	'probe_writes.sh' -- cv_seen
want_out "conventions: ...and undeclared, is drift" \
	"probe_writes_bare.sh's require list does not match" -- cv_seen
want_out "conventions: ...and declared with no reason, is drift too" \
	"probe_writes_bald.sh's require list does not match" -- cv_seen
want_broken_none "conventions: ...an optional or unknown one it names is not" \
	'probe_writes_opt.sh' -- cv_seen
want_out "conventions: an optional line with no reason exempts nothing" \
	"probe_optional_bald.sh's require list does not match" -- cv_seen
want_out "conventions: ...nor does a no-require line with none" \
	"probe_norequire_bald.sh calls PATH commands and declares none" -- cv_seen
want_out "conventions: a word after -- counts after any helper (kept)" \
	"probe_dashdash.sh's require list does not match" -- cv_seen
want_green "conventions: a comment's line-number pointer is reported" -- \
	cv_lines tools/probe_ptr.sh "2 3 11 12"
want_green "conventions: ...and a docstring's, on every line it spans" -- \
	cv_lines tools/probe_ptr.py "2 4 5 7"
want_green "conventions: ...and a page's, not its fence or quoted output" -- \
	cv_lines docs/probe_ptr.md "2"
want_out "conventions: a generated exercise's clue header must say whose" \
	'c-piscine-c-98/tests/ex00/clues.tsv:1:' -- cv_seen
want_broken_none "conventions: ...and one naming module, exercise, turn-in is fine" \
	'c-piscine-c-98/tests/ex01/clues.tsv:1:' -- cv_seen
want_out "conventions: a C copy of a grader's function is reported" \
	'tests/ex00/graded_copy.c:1: defines cv_graded' -- cv_seen
want_broken_none "conventions: ...a declaration and a call are not" \
	'graded_call.c' -- cv_seen
want_out "conventions: a provided C copy of a turned-in function is reported" \
	'tests/ex02/provided/cv_owed.c:1: defines cv_owed, which c-piscine/c-piscine-c-97 ex00 turns in' -- cv_seen
want_out "conventions: ...and one whose name is on the line below its type" \
	'tests/ex01/split_copy.c:2: defines cv_split' -- cv_seen
want_out "conventions: ...and the exempt stdio copy, at any other path" \
	'c-piscine-c-97/tests/ft_putchar.c:3: defines ft_putchar' -- cv_seen
want_broken_none "conventions: ...not a stub, a declaration or a call from main" \
	'tests/ex00/placeholder.c' -- cv_seen
want_broken_none "conventions: ...not main() itself" 'main_harness.c' -- cv_seen
want_broken_none "conventions: ...not the copy in deliverable/" 'deliverable/ex00/cv_owed.c' -- cv_seen
want_broken_none "conventions: ...not the exempt path while it stays stdio" \
	'c-piscine-reloaded/c-piscine-reloaded/tests/ft_putchar.c' -- cv_seen
want_out "conventions: a grader library listing a name its crate lacks" \
	'the call over grader/cv_other.rs lists exports = [cv_one cv_two], and the crate exports cv_one' -- cv_seen
want_broken_none "conventions: ...and one listing exactly the crate's is not" \
	'the call over grader/cv.rs' -- cv_seen
want_out "conventions: a Rust toolchain and an i686 core of two versions are reported" \
	'versions = ["1.2.3"]) and its i686 rust-std disagree' -- cv_seen
want_out "conventions: a rust-std pin MODULE.bazel does not fetch is reported" \
	'pins rust-std-i686 1.2.5, which MODULE.bazel does not fetch' -- cv_seen
want_broken_none "conventions: ...and a rustc pin it does is not" 'pins rustc 1.2.3' -- cv_seen
want_out "conventions: a python_version other than the python row's is reported" \
	'tools/pins.tsv pins python 3.9.1, and MODULE.bazel also names python_version 3.9.2' -- cv_seen
want_broken_none "conventions: ...and the sites naming the pinned one are not" \
	'python_version 3.9.1' -- cv_seen
want_out "conventions: a knob a runner reads with no row in the table" \
	'probe_knob.sh reads PROBE_NEW (default 3); the table has no row for it' -- cv_seen
want_out "conventions: ...one the table gives another default" \
	'probe_knob.sh reads PROBE_KNOB with default 8; the table says 7' -- cv_seen
want_out "conventions: ...and a row nothing under tools/ reads" \
	'PROBE_DEAD: nothing under tools/ reads it' -- cv_seen
want_out "conventions: ...nor one read only as the start of a longer name" \
	'PROBE_PFX: nothing under tools/ reads it' -- cv_seen
want_broken_none "conventions: ...a default the table gives in words is not" \
	'PROBE_WORDS' -- cv_seen
want_broken_none "conventions: ...nor a variable the runner assigns itself" \
	'PROBE_SET' -- cv_seen
want_broken_none "conventions: ...nor a row of another section" \
	'PROBE_AFTER' -- cv_seen
# A SETTING OF THE LIBRARY'S THAT NOTHING RESETS (V36): rl_gate read
# RL_GATE_PASS and RL_GATE_LABEL as ${NAME:-}, an empty default the knob rule
# above does not see, and a runner that set neither took the environment's.
# A workspace of its own (cvl): a toy runner_lib.sh reading six such names --
# one never reset, one reset where it is sourced, one it exports, one _test()
# hands a runner (defs.bzl's env), one with a row in the environment table,
# and one of Bazel's.
mkdir -p "$WORK/cvl/tools" "$WORK/cvl/docs" "$WORK/cvl/c-piscine/c-piscine-c-92"
cv_submit "c-piscine/c-piscine-c-92" > "$WORK/cvl/tools/submit.sh"
printf '\n' > "$WORK/cvl/c-piscine/c-piscine-c-92/BUILD.bazel"
{
	printf '%s\n' '# shellcheck shell=sh' 'RL_TOY_RESET=""' 'rl_toy() {'
	for _v in RL_TOY_LEFT RL_TOY_RESET RL_TOY_EXPORTED RL_TOY_GIVEN RL_TOY_ROW TEST_TOY; do
		printf '\t[ -z "${%s:-}" ] || echo "%s"\n' "$_v" "$_v"
	done
	printf '%s\n' '	export RL_TOY_EXPORTED' '}'
} > "$WORK/cvl/tools/runner_lib.sh"
printf 'def _test(env):\n    env["RL_TOY_GIVEN"] = "x"\n' > "$WORK/cvl/tools/defs.bzl"
printf '# Reference\n\n## Environment variables\n\n| variable | default | does |\n|---|---|---|\n| `RL_TOY_ROW` | unset | what the toy library reads |\n' \
	> "$WORK/cvl/docs/reference.md"
! st_mine || env BUILD_WORKSPACE_DIRECTORY="$WORK/cvl" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvl.out" 2>&1
cvl_seen() { cv_saved "$WORK/cvl.out"; }
want_out "conventions: a library setting nothing resets is reported" \
	'tools/runner_lib.sh reads ${RL_TOY_LEFT:-} and never resets it' -- cvl_seen
want_broken_none "conventions: ...not one reset where the library is sourced" \
	'${RL_TOY_RESET:-}' -- cvl_seen
want_broken_none "conventions: ...nor one the library exports" '${RL_TOY_EXPORTED:-}' -- cvl_seen
want_broken_none "conventions: ...nor one _test() hands a runner" '${RL_TOY_GIVEN:-}' -- cvl_seen
want_broken_none "conventions: ...nor one with a row in the table" '${RL_TOY_ROW:-}' -- cvl_seen
want_broken_none "conventions: ...nor one of Bazel's" '${TEST_TOY:-}' -- cvl_seen

# Two fixture modules, each a sanitized function with a c_diff, which the
# sections below add to. Neither names a harness that is there yet, so each
# run of conventions here reports c-99's (and c-98's) as missing, from the
# @addr check near the end of the file.
{
	printf 'c_function(num = "07", fn = "ft_x", test = "t.c", sanitize = True)\n\n'
	printf 'c_diff(\n    num = "07",\n    fn = "ft_x",\n    harness = "d.c",\n'
	printf '    oracle_fn = "o",\n)\n'
} > "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
{
	printf 'c_function(num = "07", fn = "ft_x", test = "t.c", sanitize = True)\n\n'
	printf 'c_diff(\n    num = "07",\n    fn = "ft_x",\n    harness = "d.c",\n'
	printf '    oracle_fn = "o",\n)\n'
} > "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"

# The level ladder is written down once, in docs/reference.md. submit.sh's
# help carried a third copy of it, which lost allocfail and told anyone
# reading it that `robust` ran less than it does; c-13's BUILD comment put diff
# a level up. A rung (a level followed by the layers it runs) and a ladder
# (three level names opening lines) are refused anywhere else, and naming a
# level alone is not. The layer names come from _LAYER_LEVEL, and the fixture's
# is made up on purpose, so the arms do not move with the real layer set.
printf '_LAYER_LEVEL = {\n    "norm": 1,\n    "widget": 3,\n}\n' \
	> "$WORK/cv/tools/defs.bzl"
#
# The REMOTES table holds no URL either: those live in .submit-remotes, a file
# of the student's own, and a row with one is reported, commented out or not.
# Both are planted in one fixture and read from one run, then moved out of the
# way and read from a second: a run of this script is the slow part of an arm.
mkdir -p "$WORK/cv/docs"
printf 'bazel test //m:robust    # + widget, norm\nbazel test //m:strict\n' > "$WORK/cv/README.md"
printf 'The levels:\n\n  basic   what 42 grades\n  strict  more\n  robust  still more\n' \
	> "$WORK/cv/docs/testing.md"
cv_submit "$_cv_mods" | sed 's|^c-piscine/c-piscine-c-99=REPLACE_ME$|# c-piscine/c-piscine-c-99=git@example.invalid:mine|' \
	> "$WORK/cv/tools/submit.sh"
# The ladder check read a list of files written into it, and the list had no
# module README, no AGENTS.md: a new project's README could carry a ladder
# unread. It reads every file of a readable kind now, but not the local dot
# directories .gitignore lists, where the owner's notes may say anything. A
# rung is also a SINGLE layer, at the end of a line or before 'and': it used
# to need a comma after the first.
printf 'Run it\nfrom the root:\nbazel test //m:strict  # + widget\n' \
	> "$WORK/cv/c-piscine/c-piscine-c-98/README.md"
printf 'Levels here:\nrobust + widget and norm\n' > "$WORK/cv/AGENTS.md"
mkdir -p "$WORK/cv/.claude-backup"
printf 'strict: widget, norm\n' > "$WORK/cv/.claude-backup/notes.md"
# A page's command that loops `for` over a listing of the tree splits every
# name at its blanks: a page's loop reported a fixture named
# `toy_twice copy.c` as `toy_twice`, twice. Its `while read` twin is the form
# the rule asks for.
printf '%s\n' '```sh' 'for f in $(git ls-files "*/deliverable/*"); do' '    echo "$f"' 'done' '```' \
	> "$WORK/cv/docs/loop.md"
printf '%s\n' '```sh' 'git ls-files -z | tr "\0" "\n" | while IFS= read -r f; do' '    echo "$f"' 'done' '```' \
	> "$WORK/cv/docs/readloop.md"
# ...and a script, which runs on every clone: the conventions rule read pages
# only, and answer_scan.sh's listing of the zone, a git listing without -z
# piped into `while read`, passed an answer named with an accent unread (git
# quotes such a name). Its pipeline is followed across a line ending in `|`;
# the -z twin, a comment and --error-unmatch are not lists. ($_cv_ls keeps
# this file's own lines from being such a listing.)
_cv_ls=ls-files
printf '%s\n' '#!/bin/sh' 'for f in $(find . -name "*.c"); do' '	echo "$f"' 'done' \
	> "$WORK/cv/docs/loop.sh"
# ...and conventions.sh's own lists, of hint files (hint_more) and of unit
# folders (unit_dirs): `for c in ... $(hint_more ...)` split a unit's
# 'clues copy.tsv' into two names, and no rule over hints read it. Read
# anywhere in the word list; the list a rule reads instead is quiet.
printf '%s\n' '#!/bin/sh' 'for c in "$m"/tests/ex*/x $(hint_more "$m" x); do' '	echo "$c"' 'done' \
	'for d in "$m"/tests/ex[0-9][0-9] $(unit_dirs "$m"); do echo "$d"; done' > "$WORK/cv/docs/hintloop.sh"
printf '%s\n' '#!/bin/sh' 'hint_files r "$m" hints.r x' \
	'while IFS= read -r c <&3; do echo "$c"; done 3< "$lex_d/hints.r"' \
	'for c in "$m"/tests/ex*/x; do echo "$c"; done' > "$WORK/cv/docs/hintread.sh"
printf '%s\n' '#!/bin/sh' "git $_cv_ls -- '*/deliverable/*' |" '	while IFS= read -r f; do' \
	'		echo "$f"' '	done' > "$WORK/cv/docs/quoted.sh"
printf '%s\n' '#!/bin/sh' "git $_cv_ls -z -- '*/deliverable/*' | tr '\\0' '\\n' |" \
	'	while IFS= read -r f; do' '		echo "$f"' '	done' \
	"# git $_cv_ls -- x | while read -r f; do :; done" \
	"git $_cv_ls --error-unmatch -- x > /dev/null || while false; do :; done" \
	> "$WORK/cv/docs/zlist.sh"
# ...and the reader of such a list (TO VERIFY V58): `while read -r f` strips
# the blanks at both ends of each name, so `y.c ` was read as `y.c`. A loop
# reading one variable a line gives its read an IFS; one reading two fields
# wants its splitting, and a loop written inside a string is no loop. And a
# read without -r drops each backslash, with an IFS of its own or without
# (review of W7-V58: the rule matched `read -r` alone).
printf '%s\n' '#!/bin/sh' 'find . -name "*.c" | while read -r f; do' '	echo "$f"' 'done' \
	'printf "%s\n" a | while IFS= read f; do echo "$f"; done' \
	'printf "%s\n" a | while read f; do echo "$f"; done' > "$WORK/cv/docs/trimloop.sh"
printf '%s\n' '#!/bin/sh' 'while read -r _case _row; do echo "$_row"; done < x' \
	'printf "%s\n" a | while IFS= read -r f; do echo "$f"; done' \
	"printf '%s\\n' 'while read -r l; do echo \"\$l\"; done'" > "$WORK/cv/docs/fields.sh"
# A compiler from the box (TO VERIFY V28, V38): a test script whose compiler
# defaults to the box's `cc`, as the selftests' did, and a runner declaring
# `cc` optional without saying it is by hand only. The by-hand one is not.
printf '%s\n' '#!/bin/sh' 'set -u' 'CC=${TOY_CC:-cc}' '"$CC" -o x x.c' > "$WORK/cv/tools/tests/boxcc.sh"
printf '%s\n' '#!/bin/sh' '# conventions: optional cc -- probed below, and skipped without' 'set -u' \
	> "$WORK/cv/tools/boxrun.sh"
printf '%s\n' '#!/bin/sh' '# conventions: optional cc -- by hand only: a toy' 'set -u' \
	> "$WORK/cv/tools/handrun.sh"
# ...and a runner whose compiler is a variable defaulting to the box's, with
# no --cc: the shape asan_check.sh and allocfail_check.sh had, which no
# declaration names, since "$CC" is no name (review of W7-V38: a toy written
# so went unreported). Its twin by hand only is quiet, and the default spelled
# as a command, `"${X:-gcc-10}" -o ...`, is found as the assignment is.
printf '%s\n' '#!/bin/sh' 'set -u' 'CC="${TOYVAR_CC:-cc}"' '"$CC" -Wall -Werror x.c -o x' \
	> "$WORK/cv/tools/toyvar_check.sh"
printf '%s\n' '#!/bin/sh' '# conventions: optional cc -- by hand only: a toy' 'set -u' 'CC="${HANDVAR_CC:-cc}"' \
	> "$WORK/cv/tools/handvar.sh"
printf '%s\n' '#!/bin/sh' 'set -u' '"${TOYRUN_CC:-gcc-10}" -o x x.c' > "$WORK/cv/tools/toyrun.sh"
# _PINNED_CC_RUNNERS held to the runners, both ways (review of W7-V38): a
# runner taking --cc that is not listed, a row for one that takes none, a
# runner proving a linker listed as never linking, one listed as linking
# that never proves one, a row that is no pair, and a row for a runner that
# is not there are each reported. The listed pair is quiet, its row split
# over five lines as buildifier may lay it out: a reader of one row a line
# read no row there, and so reported nothing in the reverse directions.
cv_cc_case() {  # the argument loop of a toy runner taking --cc, and its rl_cc_pin
	printf '%s\n' 'while [ $# -gt 0 ]; do' '	case "$1" in' '		--cc) CC=$2; shift 2 ;;' \
		'		*) shift ;;' '	esac' 'done' 'rl_cc_pin "$CC" "" ""'
}
# ...and one taking --cc that never calls rl_cc_pin, one that calls it and
# keeps a copy of its --cc-lib check besides (the five runners that compile
# before they inspect kept one, and never asked the loader which libraries
# the compiler took, V321), and a compile_check.sh that does both: it kept
# its own longest, and is held to the rule like the rest.
printf '%s\n' '#!/bin/sh' 'case "$1" in --cc) CC=$2 ;; esac' '"$CC" -c x.c -o x.o' \
	> "$WORK/cv/tools/toynopin_check.sh"
{
	printf '#!/bin/sh\n'; cv_cc_case
	printf '%s\n' "[ -d \"\$_d\" ] || echo \"toycopy_check.sh: --cc-lib directory '\$_d' does not exist.\" >&2"
} > "$WORK/cv/tools/toycopy_check.sh"
{
	printf '%s\n' '#!/bin/sh' 'case "$1" in --cc) CC=$2 ;; esac'
	printf '%s\n' "[ -d \"\$_d\" ] || echo \"compile_check.sh: --cc-lib directory '\$_d' does not exist.\" >&2"
} > "$WORK/cv/tools/compile_check.sh"
{ printf '#!/bin/sh\n'; cv_cc_case; } > "$WORK/cv/tools/toynew_check.sh"
printf '#!/bin/sh\nset -u\n' > "$WORK/cv/tools/toyrow_check.sh"
{
	printf '#!/bin/sh\n'; cv_cc_case
	printf '%s\n' 'rl_ld_pin "$CC" "$LD" "$LD_LIBS" "$WORK/ld"' '"$CC" "$RL_LDFLAG" x.c -o x'
} > "$WORK/cv/tools/toyld_check.sh"
{ printf '#!/bin/sh\n'; cv_cc_case; printf '"$CC" -c x.c -o x.o\n'; } > "$WORK/cv/tools/toynold_check.sh"
{
	printf '#!/bin/sh\n'; cv_cc_case
	printf '%s\n' 'rl_ld_pin "$CC" "$LD" "$LD_LIBS" "$WORK/ld"' '"$CC" "$RL_LDFLAG" -c x.c -o x.o' \
		'"$CC" "$RL_LDFLAG" x.o -o x'
} > "$WORK/cv/tools/toypair_check.sh"
{ printf '#!/bin/sh\n'; cv_cc_case; } > "$WORK/cv/tools/toybad_check.sh"
# ...and a runner that proves its linker and then runs its compiler without
# RL_LDFLAG (review of W7-V38: header_check.sh and method_check.sh carried
# it on their link line alone, and the --ld audit proves only that the flag
# was handed over). The link continued over two lines is reported; a list
# built with the flag, a message naming "$CC" and `command -v` are not
# commands that compile.
{
	printf '#!/bin/sh\n'; cv_cc_case
	printf '%s\n' 'rl_ld_pin "$CC" "$LD" "$LD_LIBS" "$WORK/ld"' '"$CC" "$RL_LDFLAG" -c x.c -o x.o' \
		'if ! "$CC" x.o \' '	-o x; then exit 1; fi' 'echo "$CC failed"; command -v "$CC"'
} > "$WORK/cv/tools/toyforget_check.sh"
{
	printf '#!/bin/sh\n'; cv_cc_case
	printf '%s\n' 'rl_ld_pin "$CC" "$LD" "$LD_LIBS" "$WORK/ld"' 'rl_list_add CFLAGS "$RL_LDFLAG" -O0' \
		'"$CC" $CFLAGS -c x.c -o x.o' '"$CC" "$RL_LDFLAG" x.o -o x' \
		'# Its compiler is NOT pinned: a comment out of date, as two runners kept one.'
} > "$WORK/cv/tools/toylist_check.sh"
printf '%s\n' '_PINNED_CC_RUNNERS = {' '    "//tools:toyrow_check.sh": ("always", "never"),' \
	'    "//tools:toyld_check.sh": ("always", "never"),' \
	'    "//tools:toynold_check.sh": ("always", "always"),' \
	'    "//tools:toypair_check.sh": (' '        "always",' '        "always",' '    ),  # a toy' \
	'    "//tools:toybad_check.sh": "always",' \
	'    "//tools:toyforget_check.sh": ("always", "always"),' \
	'    "//tools:toylist_check.sh": ("always", "always"),' \
	'    "//tools:toygone_check.sh": ("always", "never"),' '}' >> "$WORK/cv/tools/defs.bzl"
# The exempt ft_putchar.c is exempt for being stdio; once it calls write(),
# it is the answer it was written not to be.
printf '#include <unistd.h>\n\nvoid\tft_putchar(char c)\n{\n\twrite(1, &c, 1);\n}\n' \
	> "$WORK/cv/c-piscine-reloaded/c-piscine-reloaded/tests/ft_putchar.c"
# A layer named at a level, against the fixture's _LAYER_LEVEL (norm 1,
# widget 3). Reported: the widget at level 1 (line 1), and again with its
# name capitalised (5). Quiet: norm at basic, in backticks (2), the widget at
# robust (3), a word that is no layer (4), and the zone's copy of the file.
mkdir -p "$WORK/cv/c-piscine/c-piscine-c-98/deliverable/ex00"
printf '%s\n' 'The widget sits at level 1 (basic), so a beginner meets it.' \
	'Here `norm` stays at basic.' 'The widget is at robust.' 'This toy sits at level 1.' \
	'Widget sits at Level 1.' \
	> "$WORK/cv/c-piscine/c-piscine-c-98/levels.txt"
cp "$WORK/cv/c-piscine/c-piscine-c-98/levels.txt" "$WORK/cv/c-piscine/c-piscine-c-98/deliverable/ex00/"
! st_mine || conv > "$WORK/cv.ladder" 2>&1
want_out "conventions: the exempt ft_putchar.c, once it calls write(), is reported" \
	'c-piscine-reloaded/c-piscine-reloaded/tests/ft_putchar.c:3: defines ft_putchar' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: a level with its layers, outside the reference" \
	'README.md:1: bazel test //m:robust    # + widget, norm' -- cv_saved "$WORK/cv.ladder"
want_broken_none "conventions: ...but not a level named alone" 'README.md:2:' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: the levels defined over again" 'docs/testing.md:3:' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: a rung in a module's README, one layer" \
	'c-piscine/c-piscine-c-98/README.md:3:' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: ...and in AGENTS.md, before 'and'" 'AGENTS.md:2:' -- cv_saved "$WORK/cv.ladder"
want_broken_none "conventions: ...but not in a local dot directory" \
	'.claude-backup' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: a page's for loop over a listing of files" \
	'docs/loop.md:2: for f in $(git ls-files' -- cv_saved "$WORK/cv.ladder"
want_broken_none "conventions: ...but not its while-read twin" \
	'docs/readloop.md' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: a script's for loop over a listing of files" \
	'docs/loop.sh:2: for f in $(find' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: ...a for list holding hint_more's, after a glob" \
	'docs/hintloop.sh:2: for c in "$m"/tests/ex*/x $(hint_more' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: ...or unit_dirs'" \
	'docs/hintloop.sh:5: for d in "$m"/tests/ex[0-9][0-9] $(unit_dirs' -- cv_saved "$WORK/cv.ladder"
want_broken_none "conventions: ...but not the list read a name a line, nor a glob" \
	'docs/hintread.sh' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: a git listing without -z read by a while loop" \
	"docs/quoted.sh:2: git $_cv_ls -- '*/deliverable/*' |" -- cv_saved "$WORK/cv.ladder"
want_broken_none "conventions: ...but not one with -z, a comment or --error-unmatch" \
	'docs/zlist.sh' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: a one-name loop with read's default IFS is reported" \
	'docs/trimloop.sh:2: find . -name "*.c" | while read -r f; do   <- no IFS=' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: ...and one whose read is not raw (no -r)" \
	'docs/trimloop.sh:5: printf "%s\n" a | while IFS= read f; do echo "$f"; done   <- no -r' -- \
	cv_saved "$WORK/cv.ladder"
want_out "conventions: ...or lacks both" \
	'docs/trimloop.sh:6: printf "%s\n" a | while read f; do echo "$f"; done   <- no IFS=, no -r' -- \
	cv_saved "$WORK/cv.ladder"
want_broken_none "conventions: ...but not two fields, IFS= of its own, or a string" \
	'docs/fields.sh' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: a test script's compiler defaulting to the box's is reported" \
	'tools/tests/boxcc.sh:3: CC=${TOY_CC:-cc}' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: ...and a runner's optional cc that is not by hand only" \
	'tools/boxrun.sh:2: # conventions: optional cc -- probed below' -- cv_saved "$WORK/cv.ladder"
want_broken_none "conventions: ...but not one that is by hand only" \
	'tools/handrun.sh' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: a runner's compiler variable defaulting to the box's cc" \
	'tools/toyvar_check.sh:3: CC="${TOYVAR_CC:-cc}"' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: ...and a default run as a command" \
	'tools/toyrun.sh:3: "${TOYRUN_CC:-gcc-10}" -o x x.c' -- cv_saved "$WORK/cv.ladder"
want_broken_none "conventions: ...but not one that is by hand only" \
	'tools/handvar.sh' -- cv_saved "$WORK/cv.ladder"
cv_rule() { cv_block "$WORK/cv.ladder" "$1"; }  # cv_rule HEADLINE -- that report of the run above, alone
want_out "conventions: a runner taking --cc, not in _PINNED_CC_RUNNERS" \
	"tools/toynew_check.sh takes --cc and is not in tools/defs_toolchain.bzl's _PINNED_CC_RUNNERS" -- cv_saved "$WORK/cv.ladder"
want_out "conventions: ...a row for a runner that takes no --cc" \
	"_PINNED_CC_RUNNERS lists tools/toyrow_check.sh, which takes no --cc" -- cv_saved "$WORK/cv.ladder"
want_out "conventions: ...a linker proved by a runner listed as never linking" \
	"tools/toyld_check.sh proves a linker with rl_ld_pin, and _PINNED_CC_RUNNERS does not say it links" -- \
	cv_saved "$WORK/cv.ladder"
want_out "conventions: ...one listed as linking that proves none" \
	"_PINNED_CC_RUNNERS says tools/toynold_check.sh links, and it never calls rl_ld_pin" -- \
	cv_saved "$WORK/cv.ladder"
want_out "conventions: ...a row that is no pair of strings" \
	"    toybad_check.sh" -- cv_rule "a row of tools/defs_toolchain.bzl's _PINNED_CC_RUNNERS could not be read"
want_out "conventions: ...a row for a runner that is not there" \
	"    //tools:toygone_check.sh" -- \
	cv_rule "_PINNED_CC_RUNNERS lists a runner that is not in tools/"
want_broken_none "conventions: ...never the listed pair, its row over five lines" \
	'toypair_check.sh' -- cv_rule _PINNED_CC_RUNNERS
want_out "conventions: a runner taking --cc that never calls rl_cc_pin" \
	"tools/toynopin_check.sh takes --cc and never proves it with rl_cc_pin" -- cv_saved "$WORK/cv.ladder"
want_out "conventions: ...one that keeps its own --cc-lib check besides" \
	"tools/toycopy_check.sh:9:[ -d" -- cv_rule "tools/toycopy_check.sh checks --cc-lib directories itself"
want_out "conventions: ...compile_check.sh too, which kept its own longest" \
	'tools/compile_check.sh takes --cc and never proves it with rl_cc_pin' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: ...and its own check" \
	'tools/compile_check.sh:3:[ -d' -- cv_rule 'tools/compile_check.sh checks --cc-lib directories itself'
want_broken_none "conventions: ...nor a runner that calls it" \
	'toypair_check.sh' -- cv_rule 'never proves it with rl_cc_pin'
want_out "conventions: a listed runner whose comment says it is not pinned" \
	'tools/toylist_check.sh:13:# Its compiler is NOT pinned' -- cv_rule 'a comment of it says it is not pinned'
want_out "conventions: a link without RL_LDFLAG in a runner that proved its linker" \
	'tools/toyforget_check.sh:11: if ! "$CC" x.o \' -- \
	cv_rule 'a runner that proves a linker runs its compiler without it'
want_broken_none "conventions: ...never a message or command -v naming the compiler" \
	'toyforget_check.sh:13' -- cv_rule 'a runner that proves a linker runs its compiler without it'
want_broken_none "conventions: ...nor a list built with it, nor every command carrying it" \
	'toylist_check.sh' -- cv_rule 'a runner that proves a linker runs its compiler without it'
want_broken_none "conventions: ...and the pair, each of its commands carrying it" \
	'toypair_check.sh' -- cv_rule 'a runner that proves a linker runs its compiler without it'
want_out "conventions: a URL in the REMOTES table is reported" \
	'c-piscine/c-piscine-c-99=git@example.invalid:mine' -- cv_saved "$WORK/cv.ladder"
want_out "conventions: a layer named at a level it does not sit at" \
	'c-piscine/c-piscine-c-98/levels.txt:1:The widget sits at level 1 (basic), so a beginner meets it. (widget sits at robust)' -- \
	cv_rule 'a text names a layer at a level it does not sit at'
want_out "conventions: ...its name capitalised" \
	'c-piscine/c-piscine-c-98/levels.txt:5:Widget sits at Level 1. (widget sits at robust)' -- \
	cv_rule 'a text names a layer at a level it does not sit at'
for _lv in 2 3 4; do
	want_broken_none "conventions: ...never one at its own level, nor no layer (line $_lv)" \
		"levels.txt:$_lv:" -- cv_rule 'a text names a layer at a level it does not sit at'
done
want_broken_none "conventions: ...nor the zone's copy" \
	'c-piscine/c-piscine-c-98/deliverable/ex00/levels.txt:1:' -- \
	cv_rule 'a text names a layer at a level it does not sit at'
rm -rf "$WORK/cv/c-piscine/c-piscine-c-98/README.md" "$WORK/cv/AGENTS.md" \
	"$WORK/cv/.claude-backup" "$WORK/cv/c-piscine/c-piscine-c-98/levels.txt" \
	"$WORK/cv/c-piscine/c-piscine-c-98/deliverable"
cat "$WORK/cv/README.md" "$WORK/cv/docs/testing.md" > "$WORK/cv/docs/reference.md"
rm -f "$WORK/cv/README.md" "$WORK/cv/docs/testing.md" "$WORK/cv/docs/loop.md" "$WORK/cv/docs/readloop.md" \
	"$WORK/cv/docs/loop.sh" "$WORK/cv/docs/quoted.sh" "$WORK/cv/docs/zlist.sh" \
	"$WORK/cv/docs/trimloop.sh" "$WORK/cv/docs/fields.sh" \
	"$WORK/cv/tools/tests/boxcc.sh" "$WORK/cv/tools/boxrun.sh" "$WORK/cv/tools/handrun.sh" \
	"$WORK/cv/tools/toyvar_check.sh" "$WORK/cv/tools/handvar.sh" "$WORK/cv/tools/toyrun.sh" \
	"$WORK/cv/tools/toynew_check.sh" "$WORK/cv/tools/toyrow_check.sh" "$WORK/cv/tools/toyld_check.sh" \
	"$WORK/cv/tools/toynold_check.sh" "$WORK/cv/tools/toypair_check.sh" "$WORK/cv/tools/toybad_check.sh" \
	"$WORK/cv/tools/toyforget_check.sh" "$WORK/cv/tools/toylist_check.sh" \
	"$WORK/cv/tools/toynopin_check.sh" "$WORK/cv/tools/toycopy_check.sh" "$WORK/cv/tools/compile_check.sh"
sed '/^_PINNED_CC_RUNNERS = {$/,/^}$/d' "$WORK/cv/tools/defs.bzl" > "$WORK/cv_defs.tmp" &&
	mv "$WORK/cv_defs.tmp" "$WORK/cv/tools/defs.bzl"
cv_submit "$_cv_mods" > "$WORK/cv/tools/submit.sh"
! st_mine || conv > "$WORK/cv.ladder" 2>&1
# (An absence proves nothing from a run that stopped early: this run still
# reports the fixture's missing sanitize harness, from a check after both.)
want_out "conventions: the second run ran to the end" \
	'c-piscine/c-piscine-c-99/tests/ex07/t.c, a sanitize harness its c_function names, does not exist' -- \
	cv_saved "$WORK/cv.ladder"
want_broken_none "conventions: ...both are docs/reference.md's to hold" \
	'the level ladder is spelled out' -- cv_saved "$WORK/cv.ladder"
want_broken_none "conventions: ...and a table of REPLACE_ME is not" \
	'REMOTES table holds a row' -- cv_saved "$WORK/cv.ladder"
rm -rf "$WORK/cv/docs" "$WORK/cv.ladder"

