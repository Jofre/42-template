#!/bin/sh
# conventions.sh — enforce the house style the harness teaches by example.
#
# WHY THIS EXISTS, separately from selftest.sh.
# selftest.sh asks "can a layer report OK having checked nothing" -- it guards
# CORRECTNESS. This guards the other thing this repo is for: a student reads the
# harness to learn how Bazel, shell runners and C test mains are written, and
# copies what they see. So a convention that is followed 94 times and broken 3
# times does not teach a convention -- it teaches that the rule is optional.
# Every check below was a real defect found by hand once; this is what stops the
# next one arriving unnoticed.
#
# Each check names the file, the rule, and WHY the rule exists, because a lint
# failure that only says "line 40" teaches nothing.
#
# Usage:
#   bazel run //tools:conventions
#
# HERMETIC BY RULE. Every tool this runs is fetched and pinned by Bazel, never
# found on the host. A campus machine is not yours to configure -- different
# boxes carry different shells and different tool versions, some have no curl at
# all -- so a check whose result depends on which machine you sat down at is not
# a check. `command -v shellcheck` was exactly that, and is gone: the binary now
# arrives as an argument from MODULE.bazel, pinned by sha256.
set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "conventions.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk basename cat cksum cmp comm cut dirname find grep head mktemp od rm sed sort tail tr uniq xargs

# conventions: runs no student code -- it reads the repository and runs the pinned linters over it
# conventions: harness tool SHELLCHECK BUILDIFIER -- the pinned linters, from MODULE.bazel

SHELLCHECK=""
BUILDIFIER=""
# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "conventions.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--shellcheck) need "$1" "$#"; SHELLCHECK="$2"; shift 2 ;;
		--buildifier) need "$1" "$#"; BUILDIFIER="$2"; shift 2 ;;
		*) echo "conventions.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done

# Repo-wide: it has to SEE every runner and every test main. That used to make
# this a sh_binary and nothing else, on the ground that listing ~140 files in a
# sandboxed sh_test's `data` -- and updating that list whenever a module gained
# a test -- is a convention nobody keeps, which is the failure this script
# exists to prevent. The answer was to stop listing files: c_levels() emits each
# module's :conventions_srcs from a glob, so //tools/tests:conventions grades
# the same script on every `bazel test` run. The binary stays, and stays
# authoritative, because only it sees files nobody declared to Bazel at all.
# Absolutise the tool paths BEFORE the cd -- they arrive runfiles-relative and
# stop resolving the moment the working directory moves. Written out rather than
# looped through `eval` on purpose: eval hides the assignment from shellcheck,
# which then reports the variable as never set. A lint you have to suppress is
# worse than three lines of plain shell.
case "$SHELLCHECK" in
	""|/*) ;;
	*) SHELLCHECK="$PWD/$SHELLCHECK" ;;
esac
case "$BUILDIFIER" in
	""|/*) ;;
	*) BUILDIFIER="$PWD/$BUILDIFIER" ;;
esac

# The scratch directory: the lexer's command lists (cmds_of, below), and
# every list of files a loop here reads. A list of files is read one name per
# line, `while IFS= read -r f; do ... done < "$lex_d/files"`, never walked
# `for f in $(find ...)`: that splits a name at its blanks, and a tree holds
# such names (the rule "A list of files is read one name per line", below,
# holds every script and page to it, this one too).
lex_d=$(mktemp -d) || { echo "conventions.sh: cannot create a scratch directory" >&2; exit 2; }
trap 'rm -rf "$lex_d"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# The root to scan, in the three ways this script is reached:
#
#   bazel run  BUILD_WORKSPACE_DIRECTORY is the real workspace. Authoritative:
#              it sees files nobody declared to Bazel at all.
#   bazel test TEST_SRCDIR/TEST_WORKSPACE is the runfiles tree, which is already
#              the working directory -- deriving it from $0 lands in bazel-bin
#              instead, and every check then reports on an empty tree while the
#              script goes on printing verdicts.
#   by hand    the parent of tools/.
if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
	WS="$BUILD_WORKSPACE_DIRECTORY"
elif [ -n "${TEST_SRCDIR:-}" ]; then
	WS="$TEST_SRCDIR/${TEST_WORKSPACE:-_main}"
else
	WS="$(cd "$(dirname "$0")/.." && pwd)"
fi
# The runfiles root, captured before the cd: @buildifier_prebuilt's wrapper
# finds the real binary through a path relative to the working directory,
# so it has to be invoked from here rather than from the workspace.
RUNFILES_ROOT="$PWD"
# This script's own folder, also before the cd: a check that runs a tool of
# the harness uses the workspace's copy, and this one where the workspace is
# a selftest's fixture tree that holds no such tool.
CONV_HOME=$(cd "$(dirname "$0")" && pwd)
cd "$WS" || { echo "conventions.sh: cannot enter '$WS'" >&2; exit 2; }

# WHAT THIS RUN CAN SEE IS ASSERTED, NOT ASSUMED.
#
# This script runs two ways: `bazel run //tools:conventions`, from the real
# workspace, where `find .` reaches everything; and //tools/tests:conventions,
# from a runfiles tree holding only what was declared. The second is the point
# -- a style gate nobody remembers to run is not a gate -- but it introduces the
# failure this whole file exists to prevent: a scan that silently covers less
# than it used to and goes on reporting OK.
#
# So the modules are counted against tools/submit.sh's REMOTES table, which
# TODO.md already names as the authority for which modules exist. A module the
# table knows and this run cannot see means the file list is short, and a short
# file list is a smaller gate reporting the same green. Exit 2: nothing was
# checked properly, which is a broken harness rather than a broken convention.
#
# The keys are read only between `REMOTES='` and its closing quote, whatever
# they look like. They used to be matched by shape, `^c-piscine-[a-z0-9-]*=`,
# and when the projects moved under a course folder (c-piscine/c-piscine-c-05)
# that matched nothing: the list came back empty, this guard had nothing to
# miss, and every check below that walks the modules walked none -- green, and
# checking nothing. Hence also the floor: a table with no modules is a parse
# that failed, not a repo with nothing in it.
#
# Every module-scanning check below walks THIS list rather than globbing for
# module folders. A glob encodes where modules live and how deep; the moment
# they move it matches nothing, silently. The list is where they live.
#
# A COMMENTED-OUT row counts too. Commenting a row out is how a person stops
# PUSHING a module -- submit.sh calls it "the one gesture a person makes to
# disable a module" -- not how they delete it, and a scan that quietly dropped
# the module with it would be the shrunken-scan-reporting-green this guard is
# here to prevent. A comment that is prose rather than a KEY=... row is not one.
MODULES=$(awk '
	!inb && $0 == "REMOTES='"'"'" { inb = 1; next }
	inb && /^'"'"'/ { exit }
	inb {
		line = $0
		sub(/^[ \t]*#[ \t]*/, "", line)
		sub(/[ \t]#.*$/, "", line)
		if (index(line, "=") == 0) next
		k = substr(line, 1, index(line, "=") - 1)
		gsub(/^[ \t]+|[ \t]+$/, "", k)
		sub(/\/+$/, "", k)
		if (k ~ /^[A-Za-z0-9_.\/-]+$/ && !(k in seen)) { seen[k] = 1; print k }
	}' tools/submit.sh 2> /dev/null)
if [ -z "$MODULES" ]; then
	echo "conventions.sh: found no modules in tools/submit.sh's REMOTES table" >&2
	echo "  Every check that walks the modules would walk none and report OK." >&2
	echo "  The table is the block between REMOTES=' and its closing quote." >&2
	exit 2
fi
missing_modules=""
for _m in $MODULES; do
	[ -f "$_m/BUILD.bazel" ] || missing_modules="$missing_modules $_m"
done
if [ -n "$missing_modules" ]; then
	echo "conventions.sh: cannot see the BUILD file of:$missing_modules" >&2
	echo "  tools/submit.sh's REMOTES table says those modules exist, so this" >&2
	echo "  run would be scanning less than the repo holds and reporting on it" >&2
	echo "  as though it had scanned everything. If this is the sh_test, add" >&2
	echo "  each module's :conventions_srcs to //tools/tests:conventions." >&2
	exit 2
fi

FAILS=0
report() {
	FAILS=$((FAILS + 1))
	echo ""
	echo "  FAIL: $1"
	shift
	# Empty arguments are skipped rather than printed as a blank indented line:
	# several callers pass a detail that is conditional (a `comm` difference that
	# came out empty, an exemption list a file does not have), and a stray band
	# of whitespace in the middle of a failure reads as truncated output.
	#
	# An argument of several lines -- a helper's list of offending lines --
	# has each line indented, not only its first: echo would indent the first
	# and leave the rest at the helper's own margin, out of line with the
	# report's other details.
	for line in "$@"; do
		[ -n "$line" ] || continue
		printf '%s\n' "$line" | sed 's/^/        /'
	done
}

# text_files [FIND-ACTION...]: every file the repo-wide text checks below
# read -- all of it but the zone, deliverable/ and generators/ (the student's
# to write, and a generator ships as a skeleton, so what it says on this branch
# never reaches the template), Bazel's convenience symlinks, and every dot
# DIRECTORY but the ones the repo tracks (.devcontainer, .github, .vscode;
# .github's issue forms and pages ship with the template, and went unread
# until a rule needed them): .git, and
# the local ones .gitignore lists, .cache, .claude-backup (the owner's
# AI-memory copy, whose notes are free to say anything) and a .generating-* a
# killed generate left. Dot FILES stay: .bazelrc and .gitignore ship. Under
# `bazel test` that is what was declared to Bazel; under `bazel run`, the
# whole working tree. With no action it prints the paths, one per line.
text_files() {
	[ $# -gt 0 ] || set -- -print
	find . \
		-path './bazel-*' -prune -o \
		-path '*/deliverable/*' -prune -o \
		-path '*/generators/*' -prune -o \
		\( -type d -name '.*' ! -path . ! -path ./.devcontainer ! -path ./.github ! -path ./.vscode \) -prune -o \
		! -type d "$@" 2> /dev/null
}

echo "conventions: checking the style the harness teaches by example"

# ---------------------------------------------------------------------------
# 1. Every runner sets -u.
#
# A runner is a script tools/*.sh that parses flags. Without `set -u`, a typo'd
# or renamed flag leaves its variable empty instead of erroring, and an empty
# --expected or --bin can turn a real check into a no-op that still exits 0.
# That is the exact shape of every false green selftest.sh was written for.
# Sourced libraries are exempt: they run inside their caller's options.
#
# COMMENTS ARE STRIPPED BEFORE THE MATCH, and that is not fastidiousness: a
# runner whose header explains the option-loop convention in prose was detected
# as having one, so this check and the next fired on a file that has no flags at
# all. Same class of bug as the one the require scanner below avoids by matching
# only in command position -- a detector that reads comments is describing the
# documentation rather than the code.
is_flag_parser() {
	grep -v '^[[:blank:]]*#' "$1" | grep -qE 'while \[ \$# -gt 0 \]'
}
for f in tools/*.sh; do
	grep -q '^# shellcheck shell=' "$f" && continue          # sourced library
	is_flag_parser "$f" || continue
	grep -qE '^set -[eux]*u' "$f" || report \
		"$f does not 'set -u'" \
		"Every other flag-parsing runner does. Without it a renamed or" \
		"misspelled flag leaves its variable empty rather than failing, and" \
		"an empty --expected or --bin silently turns a check into a no-op."
done

# ---------------------------------------------------------------------------
# 2. Every runner documents its flags.
#
# The runners are the worked examples a student copies when writing their own
# test. One without a Usage block is a dead end: the only way to learn its
# interface is to read the argument parser.
for f in tools/*.sh; do
	grep -q '^# shellcheck shell=' "$f" && continue
	is_flag_parser "$f" || continue
	grep -qE '^# Usage:' "$f" || report \
		"$f has no '# Usage:' block" \
		"Every other runner documents its flags there. It is the first thing" \
		"anyone reads when copying one of these as a template."
done

# ---------------------------------------------------------------------------
# 3. shellcheck finds no error or warning.
#
# Notes are allowed through on purpose: SC2015 (a && b || c) and SC2086 (unquoted
# expansion) fire on idioms this repo uses deliberately and reads fine. Errors
# and warnings are the ones that change behaviour.
#
# SCOPE IS THE WHOLE REPO, not tools/. For most of this file's life it read
# tools/*.sh and tools/tests/*.sh and nothing else, which left roughly forty
# shell files unlinted: .devcontainer/postcreate.sh, all eighteen shell-module
# generators, every tests/exNN/check.sh, and the two fixture helpers under the
# rushes. Those are read by students at least as often as the runners are -- the
# generators ARE the shell modules' answer -- so a convention they do not follow
# is a convention taught in one half of the repo and contradicted in the other.
#
# deliverable/ is excluded and must stay excluded: those are graded artifacts,
# the student's alone, and this repo does not lint someone's exercise. (Shell
# deliverables are generated from generators/ anyway, so the source of anything
# wrong there is already in scope.)
#
# -x on the check.sh files, because each one sources tools/shell_check.sh and
# without it shellcheck reports SC1091 for a file it was simply not told to
# follow.
#
# tools/fortytwo/ (the installer of the `42` command) is named for the same
# reason as the toolchain below: the wide scan prunes ./tools.
#
# tools/cc_toolchain/ is named explicitly, and it has to be: the wide scan below
# prunes ./tools, and the list here used to stop at tools/tests -- so the pinned
# C++ toolchain's wrappers, which every compile and link in the repo runs
# through, would have been the one shell code nothing linted. Its linker
# wrappers are named `ld.bfd`, `ar` and so on without an extension, because
# clang finds a linker by exact name, so they are listed rather than globbed.
if [ -n "$SHELLCHECK" ] && [ -x "$SHELLCHECK" ]; then
	sc=$("$SHELLCHECK" -x -f gcc -S warning tools/*.sh tools/tests/*.sh tools/bazel \
		tools/fortytwo/*.sh tools/cc_toolchain/*.sh \
		tools/cc_toolchain/ar tools/cc_toolchain/ld tools/cc_toolchain/ld.bfd \
		tools/cc_toolchain/ld.gold tools/cc_toolchain/nm tools/cc_toolchain/objcopy \
		tools/cc_toolchain/objdump tools/cc_toolchain/strip 2> /dev/null || true)
	# Built with `set --` rather than an unquoted command substitution: the
	# latter is SC2046, and a lint this script cannot pass itself is not a lint.
	# It skips what text_files() skips (V113): a dot folder the repo does not
	# track (the owner's gitignored .research/ held a peer's script, reported
	# here) and a student's generators/, which its exercise's own lint layer
	# reads (shell_test.sh's lint mode). .devcontainer, .github and .vscode are read.
	set --
	text_files -name '*.sh' -print | grep -v '^\./tools/' | sort > "$lex_d/files"
	while IFS= read -r wf; do
		set -- "$@" "$wf"
	done < "$lex_d/files"
	sc_wide=$("$SHELLCHECK" -x -f gcc -S warning "$@" 2> /dev/null || true)
	sc=$(printf '%s\n%s\n' "$sc" "$sc_wide" | grep -v '^$' || true)
	if [ -n "$sc" ]; then
		report "shellcheck reports errors or warnings" "$sc"
	fi
else
	report "no pinned shellcheck was supplied" \
		"This check must never fall back to a host shellcheck: its version" \
		"decides which warnings exist, so a host copy makes the result depend" \
		"on the machine. Pass --shellcheck \$(location @shellcheck_linux_x86_64//:shellcheck)."
fi

# ---------------------------------------------------------------------------
# 4. buildifier finds no semantic warnings, except the documented backlog.
#
# Nothing is excluded any more. function-docstring-args and
# function-docstring-header used to be, because the older macros in defs.bzl
# predated the rule and documenting ~150 parameters was its own change; that
# change has landed, so the reason is gone and an exclusion whose reason is gone
# only misleads the next reader.
#
# Worth recording, because it changes what this line is worth: with the
# exclusion removed the suite passes, but a deliberately BROKEN docstring -- a
# probe .bzl with an Args: block missing one of its two parameters -- did not
# trip it either, in this buildifier and with these flags. So the docstrings are
# documented on their own merits (the macros are the API a student reads to
# learn how tests are written here), and not because anything is checking them.
# Do not assume this rule has teeth without re-testing it with a probe.
if [ -z "$BUILDIFIER" ] || [ ! -x "$BUILDIFIER" ]; then
	report "no pinned buildifier was supplied" \
		"Its version decides which lint warnings exist, so a host copy makes" \
		"the result depend on the machine. Pass --buildifier" \
		"\$(location @buildifier_prebuilt//:buildifier)."
else
	# PROVE IT RAN, before believing that it found nothing.
	#
	# @buildifier_prebuilt ships a WRAPPER, not the binary: buildifier.bash
	# locates the real one at a path relative to the WORKING DIRECTORY, and
	# falls back to $RUNFILES_DIR only when that is set to the runfiles parent.
	# Run it from anywhere else and it prints "Unable to locate buildifier
	# runfile: ..." on stderr and EXITS 0 -- and the filter below, which keeps
	# only `file:line:` diagnostics, drops that line. The check then reported no
	# warnings because it had received none, having linted nothing at all.
	#
	# That was LIVE, and it is why this block is shaped like this: `bazel run
	# //tools:conventions` cds to the workspace root, so this half of check 4 was
	# inert on every hand-run the repo has ever done, while the gate printed OK.
	# Found by giving the same script a second caller -- //tools/tests:conventions
	# stays inside the runfiles tree, and started reporting warnings the binary
	# had never once looked for.
	#
	# So: invoke it from the runfiles root and hand it the workspace as an
	# argument, and probe --version first. A tool that will not run is a broken
	# harness, not a clean repo.
	bf_ver=$(cd "$RUNFILES_ROOT" && "$BUILDIFIER" --version 2>&1 || true)
	case "$bf_ver" in
		*"buildifier version"*)
			bf=$(cd "$RUNFILES_ROOT" && "$BUILDIFIER" --lint=warn --mode=check -r "$WS" 2>&1 |
				grep -v '^bazel-' |
				grep -E '^\S+:[0-9]+:' || true)
			# Reported relative to the workspace, like every other check here.
			bf=$(printf '%s' "$bf" | sed "s|^$WS/||")
			if [ -n "$bf" ]; then
				report "buildifier reports semantic warnings" "$bf"
			fi
			;;
		*)
			report "the pinned buildifier will not run" \
				"$(printf '%s' "$bf_ver" | head -2)" \
				"It answered --version with something that is not a version, so the" \
				"lint would report no warnings because it linted no files -- not" \
				"because there are none. The wrapper finds the real binary through a" \
				"path relative to the working directory; when it cannot, it says so on" \
				"stderr and still exits 0."
			;;
	esac
fi

# ---------------------------------------------------------------------------
# 5. No test main defines a non-static, non-main function.
#
# This is the one that matters most pedagogically. At evaluation the student's
# .c is linked together with a main they have never seen, so every name they
# define without `static` shares one namespace with the harness's. That is what
# the symbols layer checks and what c-11's callback exercises make students most
# likely to trip over -- a helper called first_is_upper in BOTH files is a
# duplicate-symbol link error pointing at a file they did not write.
#
# So a harness main that leaks its own helpers demonstrates the mistake while
# testing for it. c-08 is exempt, and so is Piscine Reloaded's ex23 (c-08 ex03
# again): those mains are the SUBJECT's own code, transcribed, and the exercise
# is to make them compile. (ex03's second main, test_point_int.c, is the
# harness's own and defines nothing but main, so it leaks nothing either.)
for f in $(for _m in $MODULES; do
	[ -d "$_m/tests" ] && find "$_m/tests" -name 'test_*.c'
done | sort); do
	case "$f" in
		c-piscine/c-piscine-c-08/* | */c-piscine/c-piscine-c-08/*) continue ;;
		*c-piscine-reloaded/c-piscine-reloaded/tests/ex23/*) continue ;;
	esac
	leaked=$(awk '
		/^[a-zA-Z_].*\(.*\)[ \t]*$/ && !/^static/ && !/^int[ \t]+main/ && !/;[ \t]*$/ {
			printf "%d: %s\n", NR, $0
		}' "$f")
	if [ -n "$leaked" ]; then
		report "$f defines a non-static helper" \
			"$leaked" \
			"At evaluation this file is linked with the student's .c. A helper" \
			"defined without 'static' collides with one of the same name in" \
			"their code -- the exact failure the symbols layer teaches about." \
			"Mark it static, or move it into main."
	fi
done

# ---------------------------------------------------------------------------
# 6. Every SKIP honours NO_SKIP.
#
# A gated layer skips when it cannot say anything useful -- no compiler, no
# valgrind, correctness still red -- and exits 0 so the suite stays green on a
# machine that cannot host it. That is right for a student and dangerous for a
# maintainer, because a layer that skips everywhere is indistinguishable from a
# layer that passes everywhere. NO_SKIP=1 is the whole answer to that:
#
#   bazel test //... --test_env=NO_SKIP=1
#
# forces every gate open, so anything still green is green on merit. A skip that
# ignores NO_SKIP is worse than no gate at all -- it is invisible to the one
# mechanism built to find it. ilp32_test.sh ignored it at three of four skips and
# stayed green across 94 targets on any box where zig could not run.
#
# The rule: a shell-level `exit 0` within a few lines of a SKIP message must have
# a NO_SKIP guard above it in the same block.
for f in tools/*.sh; do
	grep -q '^# shellcheck shell=' "$f" && continue          # sourced library
	grep -qE 'while \[ \$# -gt 0 \]' "$f" || continue        # not a flag parser
	case "$f" in
		tools/submit.sh) continue ;;                         # a push tool, not a layer
	esac
	unguarded=$(awk '
		/SKIP/     { skip = NR }
		/NO_SKIP/  { guard = NR }
		# Shell-level only: `exit 0` alone on a line, or ending one as the last
		# command of a case arm. An `exit 0` inside an embedded awk program sits
		# mid-line inside braces, so neither form reaches it.
		#
		# ONE GUARD PER SKIP. The guard is CONSUMED here, and that is the whole
		# difference between this and what it used to do: it asked only whether
		# some NO_SKIP appeared in the 30 lines above, so a runner with a
		# guarded skip followed by an unguarded one passed -- the second skip
		# was covered by the first skips guard, from a different stanza, about
		# a different condition. ilp32_test.sh ignored NO_SKIP at three of four
		# skips, which is the shape this check exists to catch, and the shape
		# it could be blind to.
		/^[ \t]*exit 0[ \t]*$/ || /;[ \t]*exit 0[ \t]*(;;)?[ \t]*$/ {
			if (skip && NR - skip <= 6) {
				if (!guard || NR - guard > 30)
					printf "%d: this SKIP exits 0 with no NO_SKIP guard of its own above it\n", NR
				guard = 0
				skip = 0
			}
		}' "$f")
	if [ -n "$unguarded" ]; then
		report "$f has a SKIP that NO_SKIP cannot force" \
			"$unguarded" \
			"Add the guard every other runner uses, so the forced sweep can see it:" \
			"    [ \"\${NO_SKIP:-0}\" != \"1\" ] || {" \
			"            echo \"NO_SKIP set: <what was not checked, and why>\"" \
			"            exit 1" \
			"    }" \
			"A layer that skips on every machine looks exactly like one that passes" \
			"on every machine. NO_SKIP=1 is what tells them apart -- a skip it" \
			"cannot force is invisible to the only check that would catch it."
	fi
done

# ---------------------------------------------------------------------------
# N. Every runner declares #!/bin/sh, and that line is load-bearing.
#
# This repo does not pin /bin/sh. It does not need to, PROVIDED the runners are
# shell-agnostic -- and two things enforce that. shellcheck refuses a bashism
# statically, but ONLY because it infers the POSIX dialect from this shebang:
# change one runner to #!/bin/bash and SC3xxx stops firing for it, silently, and
# that runner may then quietly depend on bash. //tools/tests:selftest_bash is
# the other half, replaying every arm with bash interpreting each runner.
#
# So the shebang is checked here rather than assumed. Sourced libraries are
# exempt -- they have no shebang by design and carry `# shellcheck shell=sh`
# instead, which tells the linter the same thing.
#
# Whole repo, minus deliverable/, for the same reason check 3 widened: a
# generator or a check.sh with a bash shebang is a file shellcheck stops
# policing, and those are read as examples too.
find . \
	-path './bazel-*' -prune -o \
	-path '*/deliverable/*' -prune -o \
	-name '*.sh' -print 2> /dev/null | sort > "$lex_d/files"
while IFS= read -r f; do
	if grep -q '^# shellcheck shell=sh' "$f"; then
		continue
	fi
	if ! head -n 1 "$f" | grep -q '^#!/bin/sh$'; then
		report \
			"$f does not start with #!/bin/sh" \
			"shellcheck infers the POSIX dialect from that line. Any other" \
			"shebang turns off the SC3xxx warnings that keep this runner" \
			"portable, and nothing else would notice -- the repo deliberately" \
			"runs on the system shell rather than pinning one."
	fi
done < "$lex_d/files"

# ---------------------------------------------------------------------------
# N. Every script declares the external commands it takes from PATH.
#
# THE FAILURE THIS EXISTS FOR IS SILENT. `grep -qE "AddressSanitizer" "$ERR" &&
# ...` on a machine with no grep does not error: it reads exactly like "no
# match". asan_run.sh then skips its sanitizer branch and reports a real ASan
# finding under the generic "died on signal 6" headline. The verdict happens to
# stay red there -- ASan aborts, so the crash branch below catches it -- but
# that is luck, not design, and the same shape sits in a dozen sibling runners
# where it would decide the verdict outright.
#
# The remedy is the one item 6 settled for /bin/sh: prove the USAGE is sound
# rather than pin the binaries. Each script says which commands it needs, probes
# for them once at startup, and exits 2 -- "the check never ran" -- if one is
# absent. This check is what stops that list going stale, by recomputing it from
# what the script actually calls.
#
# HOW THE LIST IS COMPUTED. Only names in the vocabulary below, and only in
# COMMAND position -- line start, or after | ; & ( $( ` -- so `# see also grep`
# in a comment and `--diff` in a flag name do not count. A tool reached through
# a variable ($NM, $DIFFER, $NORM) is a path Bazel handed in, already pinned and
# already failing loudly, so it is deliberately not in scope.
#
# THE VOCABULARY IS NOT JUST COREUTILS, and that was a real hole. It listed 24
# always-there commands, so the eight tools whose answer actually decides a
# verdict -- cc, git, comm, md5sum, make, perl, shellcheck, timeout -- were
# invisible to this check. Worse, because the comparison is equality, a script
# that CORRECTLY declared `git` would have been reported as drifted: the one
# thing this check exists to encourage was the one thing it punished. Anything a
# script can call has to be nameable here, or the guarantee is only about the
# commands that were never going to be missing anyway.
#
# Three exemptions, all declared in the file rather than listed here, so the
# reason travels with the code:
#   * a sourced library (`# shellcheck shell=`), which runs inside its caller's
#     options;
#   * `# conventions: no-require`, today only env-audit.sh -- it PROBES a host,
#     so a missing tool is its finding to report rather than a reason to refuse;
#   * `# conventions: optional <tool> -- <why>`, for a command the script
#     probes with `command -v` and then DEGRADES or SKIPs without. Those must
#     not go in `require`, which exits 2 on absence, so they are named one at a
#     time with the reason beside them. Naming each one is the point: "this tool
#     is allowed to be missing" is a decision about what the layer still
#     guarantees, and it should be reviewable rather than implied by a word
#     being absent from a list.
#
# A sourced library has no require() of its own -- it runs inside its caller,
# and the caller's list is computed from the CALLER's text. So a library that
# takes commands from PATH probes them itself, in a loop spelled
# `for _<x>_t in <commands>; do` (tools/runner_lib.sh), and that loop is its
# declaration, checked here the same way. A library with no such loop calls
# nothing from PATH and is skipped.
for f in tools/*.sh tools/tests/*.sh; do
	libdecl=""
	if grep -q '^# shellcheck shell=' "$f"; then
		libdecl=$(sed -n 's/^for _[a-z]*_t in \([a-z0-9 ._-]*\); do$/\1/p' "$f" | head -n 1)
		[ -n "$libdecl" ] || continue
	fi
	grep -q '^# conventions: no-require' "$f" && continue
	optional=$(sed -n 's/^# conventions: optional \([a-z0-9_.-]*\).*/\1/p' "$f" |
		sort -u | tr '\n' ' ')
	used=$(awk -v optional="$optional" '
		BEGIN {
			split("grep sed awk sort tr wc cut head tail od cmp diff find " \
			      "xargs basename dirname mktemp date chmod cp mv rm mkdir " \
			      "ln readlink env comm cc git make md5sum nm perl python3 " \
			      "sha256sum shellcheck tar timeout valgrind cat touch tee " \
			      "uniq sleep id uname expr seq stat rmdir paste nl " \
			      "cksum pandoc pdftotext weasyprint fold", v, " ")
			for (i in v) vocab[v[i]] = 1
			split("if then else elif do done while until case esac ! { } fi", k, " ")
			for (i in k) kw[k[i]] = 1
			split(optional, o, " ")
			for (i in o) if (o[i] != "") exempt[o[i]] = 1
		}
		# Drop the literal text inside double quotes, keeping whatever a $( )
		# inside them contains. Without this, `echo "cannot read symbols from
		# $src (nm failed)"` splits at the paren and reads `nm` as a command --
		# the same class of miss as reading comments, which the strip above
		# already fixed, and it reported a phantom `nm` in forbidden_symbols.sh.
		#
		# The quoting state has to be a STACK, not a flag, because a command
		# substitution re-opens quoting inside a quoted string:
		#
		#     [ "$(git ls-files -s "$f" | cut -d" " -f1)" = "100755" ]
		#
		# A flat scanner pairs the quote before $f with the one after it, then
		# treats ` | cut -d` as quoted text and drops a real call. Each $( )
		# pushes the outer state and starts fresh; ) pops it back.
		function strip_quoted(s,   out, i, c, d, inq, stack) {
			out = ""; d = 0; inq = 0
			for (i = 1; i <= length(s); i++) {
				c = substr(s, i, 1)
				if (c == "\\") {
					if (!inq) out = out c substr(s, i + 1, 1)
					i++
					continue
				}
				if (c == "$" && substr(s, i + 1, 1) == "(") {
					stack[d] = inq
					d++; inq = 0
					out = out "$("
					i++
					continue
				}
				if (c == ")" && d > 0) {
					d--; inq = stack[d]
					out = out ")"
					continue
				}
				if (c == "\"") { inq = !inq; continue }
				if (!inq) out = out c
			}
			return out
		}
		{
			line = $0
			sub(/^[ \t]*#.*/, "", line)
			if (line == "") next
			# A trap ARGUMENT is a command list that runs later, so its
			# contents are command position -- but they are quoted, so the
			# scanner saw only the word `trap`. Every runner that cleans up
			# after itself does it with `trap "rm ..." EXIT`, and once the
			# hand-written rm calls were replaced by traps, three scripts were
			# reported as no longer calling rm while still very much needing it.
			# Unwrap the single-quoted form (the only one the repo uses; a bare
			# `trap some_function EXIT` names a shell function, not a command,
			# and correctly does not count).
			# rl_traps (tools/runner_lib.sh) takes the same argument and
			# hands it to trap, so it is unwrapped the same way.
			if (match(line, /^[ \t]*(trap|rl_traps)[ \t]+\047/)) {
				sub(/^[ \t]*(trap|rl_traps)[ \t]+\047/, "", line)
				sub(/\047[^\047]*$/, "", line)
			}
			line = strip_quoted(line)
			gsub(/\$\(/, "\n", line)
			gsub(/[|;&()`]/, "\n", line)
			n = split(line, frag, "\n")
			for (i = 1; i <= n; i++) {
				s = frag[i]
				sub(/^[ \t]*/, "", s)
				while (1) {
					if (match(s, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
						sub(/^[^ \t]+[ \t]*/, "", s); continue
					}
					w = s; sub(/[ \t].*/, "", w)
					if (w in kw) { sub(/^[^ \t]+[ \t]*/, "", s); continue }
					break
				}
				# `command -v X` IS A USE OF X, and this scanner used to miss
				# every one of them because the command word is `command`.
				# That is the hole that lets a runner probe a tool, degrade
				# silently when it is absent, and declare nothing either way:
				# the tool appears in no `require` list, so nothing exits 2
				# without it, and no `# conventions: optional` line is forced,
				# so nobody ever wrote down what the layer still guarantees
				# when it is gone. A probe is exactly the case the optional
				# declaration exists for.
				if (match(s, /^command[ \t]+-[A-Za-z]*v[ \t]+[A-Za-z0-9_.-]+/)) {
					probe = substr(s, RSTART, RLENGTH)
					sub(/^command[ \t]+-[A-Za-z]*v[ \t]+/, "", probe)
					if ((probe in vocab) && !(probe in exempt)) seen[probe] = 1
				}
				w = s; sub(/[ \t].*/, "", w)
				if ((w in vocab) && !(w in exempt)) seen[w] = 1
			}
		}
		END { for (w in seen) print w }' "$f" | sort | tr '\n' ' ')
	if [ -n "$libdecl" ]; then
		declared=$(printf '%s\n' "$libdecl" | tr ' ' '\n' | grep -v '^$' | sort | tr '\n' ' ')
	else
		declared=$(grep -m1 '^require ' "$f" | cut -d' ' -f2- | tr ' ' '\n' |
			grep -v '^$' | sort | tr '\n' ' ')
	fi
	[ -z "$used" ] && [ -z "$declared" ] && continue
	if [ -z "$declared" ]; then
		report "$f calls PATH commands and declares none" \
			"uses: $used" \
			"Add the helper every other script carries, right after set -u:" \
			"    require() {" \
			"            for _t in \"\$@\"; do" \
			"                    command -v \"\$_t\" > /dev/null 2>&1 && continue" \
			"                    echo \"$(basename "$f"): required command '\$_t' is not on PATH\" >&2" \
			"                    exit 2" \
			"            done" \
			"    }" \
			"    require $used" \
			"A missing tool used as a predicate answers 'false' rather than" \
			"failing, which is a wrong verdict nothing else in the suite can see."
	elif [ "$used" != "$declared" ]; then
		report "$f's require list does not match what it calls" \
			"declared: $declared" \
			"calls:    $used" \
			"${optional:+already exempt: $optional}" \
			"A list that has drifted is worse than none: it reads as a" \
			"guarantee that the probe covers this script, and it does not." \
			"If the tool is one this script PROBES and then degrades or skips" \
			"without, it does not belong in require -- that exits 2 on absence." \
			"Say so instead, one line per tool, and the check will exempt it:" \
			"    # conventions: optional <tool> -- <what stops being checked>"
	fi
done

# ---------------------------------------------------------------------------
# N. The documented layer table matches the one the build actually uses.
#
# THIS IS THE CHECK THE DOCS DID NOT HAVE. README.md used to state that the
# selftest covered "18 of the 25 runners, in 66 arms" when it was 25 of 25 in
# far more
# and that allocfail was enabled on "c-08 ex04 alone" (c-07 ex00 had it too).
# Both were written true and went stale, and nothing could notice, because a
# number in prose is not connected to the thing it describes.
#
# The rule the docs now follow is "state rules, not counts" -- but ONE table has
# to enumerate, because a reader needs to look layers up. So that table is
# checked: every tag in _LAYER_LEVEL must appear in docs/reference.md with the
# same level, and the table must name no layer the build does not emit. Adding a
# layer without documenting it, or renaming one, fails here.
#
# It compares the SET and the LEVEL, not the wording. What each layer checks is
# prose, and prose is not the build's to verify.
LEVELS=$(awk '
	/^_LAYER_LEVEL = \{/ { inmap = 1; next }
	inmap && /^\}/        { inmap = 0 }
	inmap && /^\t*[ ]*"/ {
		tag = $0
		sub(/^[ \t]*"/, "", tag); sub(/".*/, "", tag)
		lvl = $0
		sub(/^[^:]*:[ ]*/, "", lvl); sub(/[^0-9].*/, "", lvl)
		if (lvl != "") print tag, lvl
	}' tools/defs.bzl | sort)

DOCTABLE=$(awk -F'|' '
	/^\| `[a-z0-9_]+` \| (basic|strict|robust|complete) \|/ {
		tag = $2; gsub(/[ `]/, "", tag)
		lvl = $3; gsub(/ /, "", lvl)
		n = (lvl == "basic") ? 1 : (lvl == "strict") ? 2 : (lvl == "robust") ? 3 : 4
		print tag, n
	}' docs/reference.md | sort)

if [ -z "$DOCTABLE" ]; then
	report "docs/reference.md has no layer table this check can read" \
		"It looks for rows shaped: | \`norm\` | basic | what it checks |" \
		"If the table moved, move this check with it -- a lint that silently" \
		"matches nothing is the false green this file exists to prevent."
elif [ "$LEVELS" != "$DOCTABLE" ]; then
	# Temp files rather than process substitution: <(...) is bash, and every
	# runner here is POSIX sh. This check's own first draft used it and the
	# static-lint rule three checks up refused it, which is the arrangement
	# working. (Nor may a comment begin with the word that names those
	# directives -- the linter reads it as one and stops parsing.)
	_lvl_tmp=$(mktemp) || _lvl_tmp=""
	_doc_tmp=$(mktemp) || _doc_tmp=""
	printf '%s\n' "$LEVELS" > "$_lvl_tmp"
	printf '%s\n' "$DOCTABLE" > "$_doc_tmp"
	report "docs/reference.md's layer table disagrees with _LAYER_LEVEL" \
		"in defs.bzl but not documented, or documented at another level:" \
		"$(comm -23 "$_lvl_tmp" "$_doc_tmp" | sed 's/^/    /')" \
		"documented but not in defs.bzl, or at another level:" \
		"$(comm -13 "$_lvl_tmp" "$_doc_tmp" | sed 's/^/    /')" \
		"_LAYER_LEVEL is the source of truth: it is what tags every test." \
		"Fix the table, or the mapping, so a reader looking a layer up gets" \
		"the level the build will actually give them."
	rm -f "$_lvl_tmp" "$_doc_tmp"
fi

# ---------------------------------------------------------------------------
# N. first_red's stub-green layers are layers, at basic.
#
# tools/first_red.sh files a red in one of these layers, at basic, on a
# written exercise as the student's to fix first (FIX FIRST), and reads every
# other fact about a target -- its layer, its level, a raise -- from
# tools/defs.bzl. Its list once spelled compile_clang and compile_gcc, which
# are target suffixes and no layer, and claimed this check while none
# existed. Each name must be a key of _LAYER_LEVEL at level 1.
_sg=$(sed -n "s/^STUB_GREEN='\(.*\)'$/\1/p" tools/first_red.sh)
if [ -z "$_sg" ]; then
	report "tools/first_red.sh has no STUB_GREEN='...' line this check can read" \
		"If it moved, move this check with it: a lint that matches nothing is" \
		"the false green this file exists to prevent."
else
	_sgbad=""
	for _l in $_sg; do
		printf '%s\n' "$LEVELS" | grep -qx "$_l 1" || _sgbad="$_sgbad $_l"
	done
	[ -z "$_sgbad" ] || report \
		"tools/first_red.sh's STUB_GREEN names what is no basic layer:$_sgbad" \
		"It is the list of layers a fresh stub passes, as _LAYER_LEVEL in" \
		"tools/defs.bzl names them; a target's suffix (compile_clang) is not" \
		"one, and first_red reads suffixes from _SUFFIX_LAYER itself."
fi

# ---------------------------------------------------------------------------
# N. The target-name, raised-target and manual-target tables match the ones
#    c_levels()' audit reads.
#
# The audit (tools/defs.bzl, _audit_problems) fails a module while loading
# when a test's name ends in no suffix of _SUFFIX_LAYER or in another layer's,
# when a test sits above that suffix's level and _RAISED does not list it, or
# when a manual test matches no pattern of _MANUAL. Those three tables are
# what a reader looks a target up in, so docs/reference.md prints them, and
# this holds each printed table to its constant, row for row, as the layer
# table is held to _LAYER_LEVEL above: a suffix, a raise or a manual target
# added to one and not the other fails here (findings 002, 038, 072 -- none of
# them was in a document before). It compares the keys, the layers and the
# levels, not the prose. _RAISED's tools/tests/ entries prove the mechanism on
# a toy package and are not documented.
# awk reads the tables as written: one entry per line, as buildifier leaves
# them.
SUFFIXES=$(awk '
	/^_LAYER_LEVEL = \{/ { inl = 1; next }
	inl && /^\}/ { inl = 0 }
	inl && /^[ \t]*"[a-z0-9_]+": [0-9]/ {
		k = $1; gsub(/[":]/, "", k)
		v = $2; gsub(/[^0-9]/, "", v)
		lv[k] = v
	}
	/^_SUFFIX_LAYER = \{/ { inmap = 1; next }
	inmap && /^\}/ { inmap = 0 }
	inmap && /^[ \t]*"_/ {
		line = $0
		gsub(/[" (),:]/, " ", line)
		split(line, f, " ")
		lvl = (f[3] == "None") ? lv[f[2]] : f[3]
		split("basic strict robust complete", names, " ")
		print f[1], f[2], names[lvl + 0]
	}' tools/defs.bzl | sort)
DOC_SUFFIXES=$(awk -F'|' '
	/^## / { sec = $0 }
	sec == "## Target names" && /^\| `_[a-z0-9_]+` \| `[a-z0-9_]+` \| [a-z]+ \|/ {
		a = $2; b = $3; c = $4
		gsub(/[ `]/, "", a); gsub(/[ `]/, "", b); gsub(/ /, "", c)
		print a, b, c
	}' docs/reference.md | sort)
RAISED=$(awk '
	/^_RAISED = \{/ { inmap = 1; next }
	inmap && /^\}/ { inmap = 0 }
	inmap && /^[ \t]*"/ {
		line = $0
		gsub(/[",:]/, " ", line)
		split(line, f, " ")
		if (f[1] ~ /^tools\//) next
		split("basic strict robust complete", names, " ")
		print "//" f[1] ":" f[2], names[f[3]]
	}' tools/defs.bzl | sort)
DOC_RAISED=$(awk -F'|' '
	/^## / { sec = $0 }
	sec == "## Targets raised above their layer" && /^\| `\/\/[^`]+` \| [a-z]+ \|/ {
		a = $2; b = $3
		gsub(/[ `]/, "", a); gsub(/ /, "", b)
		print a, b
	}' docs/reference.md | sort)
MANUAL=$(awk '
	/^_MANUAL = \[/ { inl = 1; next }
	inl && /^\]/ { inl = 0 }
	inl && /^[ \t]*"/ { line = $0; gsub(/[", \t]/, "", line); if (line !~ /^tools\//) print "//" line }' tools/defs.bzl | sort)
DOC_MANUAL=$(awk -F'|' '
	/^## / { sec = $0 }
	sec == "## Manual targets" && /^\| `\/\/[^`]+` \|/ { a = $2; gsub(/[ `]/, "", a); print a }' docs/reference.md | sort)
# same_table HEADING CONSTANT FROM_DEFS FROM_DOCS
same_table() {
	if [ -z "$3" ] || [ -z "$4" ]; then
		report "docs/reference.md's \"$1\" or tools/defs.bzl's $2 reads as empty" \
			"A table this check cannot find is not a table it checked. It looks for" \
			"the rows under the heading \"## $1\", and for $2's entries one per" \
			"line; if either moved, move this check with it."
		return
	fi
	[ "$3" = "$4" ] && return
	_a=$(mktemp) || _a=""
	_b=$(mktemp) || _b=""
	printf '%s\n' "$3" > "$_a"
	printf '%s\n' "$4" > "$_b"
	report "docs/reference.md's \"$1\" disagrees with tools/defs.bzl's $2" \
		"in $2, and not in the table as it is there:" \
		"$(comm -23 "$_a" "$_b" | sed 's/^/    /')" \
		"in the table, and not in $2:" \
		"$(comm -13 "$_a" "$_b" | sed 's/^/    /')" \
		"$2 is what c_levels()' audit reads when a module loads; the table is" \
		"what a reader looks the target up in. Change both, or neither."
	rm -f "$_a" "$_b"
}
same_table "Target names" _SUFFIX_LAYER "$SUFFIXES" "$DOC_SUFFIXES"
same_table "Targets raised above their layer" _RAISED "$RAISED" "$DOC_RAISED"
same_table "Manual targets" _MANUAL "$MANUAL" "$DOC_MANUAL"

# ---------------------------------------------------------------------------
# N. README.md's worked red agrees with the files it shows.
#
# A newcomer's first comparison is README.md's "read one red": the table of
# the stub's run of the target it names, its legend and its hint. Its legend
# kept the sentence diff_output.sh had dropped ("In the failing rows, $ is
# where a line ended", the runner now saying "In the table, ..."), and its
# EXPECTED cell showed a line end the expected file does not have, so no
# legend at all is printed there. So, from the target the block names -- the
# "THE LOG OF //M:exNN_output" line `42 test` prints above the table, or a
# "bazel test //M:exNN_output --test_output=errors" line before the block --
# and that exercise's files:
# each "(no line)" row's EXPECTED cell is the expected file's line, with a $
# exactly where the file ends that line; a legend line is there exactly when
# a cell shows a $, and reads as diff_output.sh composes it; and the hint
# shown, before its "[...]", begins a row of the exercise's clues.tsv. Only
# printable text is compared: a line holding anything else is reported as
# unreadable rather than guessed at.
if [ -f README.md ]; then
	_rx=$(awk '
		/^bazel test \/\/[^ ]+:ex[0-9][0-9]_output --test_output=errors/ && t == "" {
			t = $3
		}
		/^```/ { inb = !inb; if (!inb && got) exit; next }
		inb && !got && /^ +THE LOG OF \/\/[^ ]+:ex[0-9][0-9]_output$/ { t = $4 }
		inb && t != "" && /^ CASE +\| EXPECTED/ { got = 1 }
		inb && got { print }
		END { if (got) print "TARGET\t" t }' README.md)
	_rt=$(printf '%s\n' "$_rx" | awk -F'\t' '$1 == "TARGET" { print $2 }')
	_rm=${_rt#//}; _rm=${_rm%%:*}
	_re=${_rt##*:}; _re=${_re%%_*}
	_rexp="$_rm/tests/$_re/expected.txt"
	_rclu="$_rm/tests/$_re/clues.tsv"
	_rleg=$(sed -n 's/.*legend = "\(In the table, \)" mk\[1\].*/\1/p' tools/diff_output.sh)
	_rdol=$(sed -n 's/.*mk\[++nmarks\] = "\(\$ is where a line ended\)".*/\1/p' tools/diff_output.sh)
	if [ -z "$_rt" ] || [ ! -f "$_rexp" ] || [ -z "$_rleg" ] || [ -z "$_rdol" ]; then
		report "README.md's worked red cannot be checked" \
			"It looks for the block holding \" CASE   | EXPECTED\" under a line" \
			"\"THE LOG OF //<module>:exNN_output\" in it (as \`42 test\` prints it), or" \
			"after a line \"bazel test //<module>:exNN_output --test_output=errors\"," \
			"for that exercise's tests/exNN/expected.txt (here: ${_rexp:-none found}), and" \
			"for diff_output.sh's legend (legend = \"In the table, \" ...). If one" \
			"moved, move this check with it."
	else
		# Whether the file's last line ends: getline reads it back the same
		# either way, so its last byte says.
		_rend=0
		[ "$(tail -c 1 "$_rexp" | od -An -tx1 | tr -d ' \n')" != 0a ] || _rend=1
		_rbad=$(printf '%s\n' "$_rx" | LEG="$_rleg$_rdol." CLU="$_rclu" ENDS="$_rend" LC_ALL=C awk -F'|' -v xf="$_rexp" '
			BEGIN {
				n = 0
				while ((getline l < xf) > 0) { e[++n] = l }
				close(xf)
				ends = ENVIRON["ENDS"]
			}
			/^TARGET\t/ { next }
			$1 ~ /^ line [0-9]+ $/ && $3 ~ /\(no line\)/ {
				k = $1; gsub(/[^0-9]/, "", k)
				c = $2; gsub(/^ +| +$/, "", c)
				w = e[k]
				if (w ~ /[^ -~]/ || w ~ /[$\\]/) { printf "    line %d of %s holds what this check does not render\n", k, xf; next }
				if (k < n || ends == 1) w = w "$"
				if (c != w) printf "    line %d: the table shows \"%s\", and %s gives \"%s\"\n", k, c, xf, w
				if (w ~ /\$$/) dollar = 1
			}
			/^ In the / { leg = $0; sub(/^ /, "", leg) }
			/^   \* / { hint = $0; sub(/^   \* /, "", hint); sub(/ *\[\.\.\.\]$/, "", hint) }
			END {
				if (dollar && leg != ENVIRON["LEG"])
					printf "    the legend reads \"%s\", and diff_output.sh prints \"%s\"\n", leg, ENVIRON["LEG"]
				if (!dollar && leg != "")
					printf "    the legend \"%s\" is shown under cells holding no mark: diff_output.sh prints none\n", leg
				if (hint != "") {
					found = 0
					while ((getline l < ENVIRON["CLU"]) > 0)
						if (l !~ /^#/ && index(l, hint) == 1) found = 1
					if (!found) printf "    the hint shown begins no row of %s\n", ENVIRON["CLU"]
				}
			}') || _rbad="    (the check itself failed: its awk program stopped)"
		[ -z "$_rbad" ] || report \
			"README.md's worked red disagrees with what $_rt prints" \
			"$_rbad" \
			"It is a newcomer's first comparison, and it has to read as their" \
			"terminal will. Run the target on a stub and copy what it prints." \
			"(The rows, the legend and the first hint are compared here.)"
	fi
fi

# ---------------------------------------------------------------------------
# N. A readings corpus's hints name the level its target sits at, and above
#    strict call its question a convention.
#
# An exNN_readings target sits at strict, the diff layer's level, where it
# reads a sentence the subject leaves ambiguous, and at robust or complete
# where its cases are ones the subject's words do not reach, so that what
# the reference does with them is a convention of this repo's own
# (docs/reference.md, "Run contract"). Its hint file is where a student
# learns which. C 11 ex06's corpus of bytes above 0x7f under "ascii order"
# was filed at strict as "its reading" while C 06 ex03's, the same
# question, sat at robust as a convention (the wave 5 review), and moving
# it left a hint that went on saying strict. So the hint file of a
# _readings target (tests/exNN/*clues_readings*) names no level but the one
# the target sits at -- _RAISED's, or strict -- and says "convention" above
# strict and not at it. Comment lines are left out, and a hint wraps, so
# each file is read as one text.
for _m in $MODULES; do
	for c in "$_m"/tests/ex*/*clues_readings*; do
		[ -f "$c" ] || continue
		_rx=${c%/*}
		_rx=${_rx##*/}
		_rt="//$_m:${_rx}_readings"
		_rl=$(printf '%s\n' "$RAISED" | awk -v t="$_rt" '$1 == t { print $2 }')
		[ -n "$_rl" ] || _rl=strict
		_rtext=$(grep -v '^[[:blank:]]*#' "$c" | tr -s '[:space:]' ' ')
		_rsaid=$(printf '%s\n' "$_rtext" | grep -o -i -w -E 'at (basic|strict|robust|complete)' |
			awk '{ print tolower($2) }' | sort -u | grep -v -x -F "$_rl" | tr '\n' ' ')
		[ -z "$_rsaid" ] || report \
			"$c says its target sits at ${_rsaid% }, and ${_rx}_readings sits at $_rl" \
			"The hint is what tells a student how far up the ladder the question" \
			"sits. Say the level the target sits at: tools/defs.bzl's _RAISED, or" \
			"strict, the diff layer's, when it lists none."
		_rconv=""
		printf '%s' "$_rtext" | grep -q -i 'convention' && _rconv=1
		case $_rl in
			robust | complete)
				[ -n "$_rconv" ] || report \
					"$c is the hint of ${_rx}_readings, at $_rl, and does not call its question a convention" \
					"Above strict, a readings corpus holds cases the subject's words do" \
					"not reach, and what the reference does with them is this repo's" \
					"decision, which the Run contract says is said (docs/reference.md):" \
					"\"a convention this repo chose, at $_rl\"." ;;
			*)
				[ -z "$_rconv" ] || report \
					"$c is the hint of ${_rx}_readings, at $_rl, and calls its question a convention" \
					"A convention of this repo's own sits at robust or complete" \
					"(docs/reference.md, \"Run contract\"), never at strict: either the" \
					"question is a reading of an ambiguous sentence, and the hint says so," \
					"or the target goes up (c_diff's readings \"level\", and _RAISED)." ;;
		esac
	done
done

# And any text in a module's folder that names a target _RAISED lists, with
# a level, names the one it sits at. C 07's ex04_base_to_space_output came
# down from robust to strict (the owner's ruling, 2026-10-09) and a hint of
# its exercise went on saying robust (the review of that change). A text
# names a level as "<target>, at <level>", the target and the level in
# backticks or not.
_lvbad=$(printf '%s\n' "$RAISED" | while read -r _rt _rl; do
	[ -n "$_rt" ] || continue
	_rm=${_rt#//}
	_rm=${_rm%%:*}
	_rn=${_rt##*:}
	[ -d "$_rm" ] || continue
	grep -rnowE "${_rn}\`?,? at \`?(basic|strict|robust|complete)" "$_rm" 2> /dev/null |
		awk -v l="$_rl" -v t="$_rn" '{
			s = $0; sub(/.* at `?/, "", s)
			if (s != l) print $0 " (" t " sits at " l ")"
		}'
done)
[ -z "$_lvbad" ] || report \
	"a text names a raised target at a level it does not sit at" \
	"$_lvbad" \
	"Say the level the target sits at: tools/defs.bzl's _RAISED, which" \
	"docs/reference.md prints. A student reads it to know how far up the" \
	"ladder the question is."

# ---------------------------------------------------------------------------
# N. The tests of a whole module are named the same in the three places that
#    read them.
#
# A module's test that belongs to no exercise -- deliverable_files, the pushed
# files outside every exercise folder (finding 052) -- is let through by
# c_levels()' audit from _MODULE_TESTS, is filed by first_red.sh under its own
# name from MODULE_TESTS (never as "the next exercise", nor demoted over a
# stub), and is looked up in docs/reference.md. A name added to one and not
# the others is a red nobody reads correctly, so the three are held together.
MODTESTS=$(awk '
	/^_MODULE_TESTS = \{/ { inm = 1; next }
	inm && /^\}/ { inm = 0 }
	inm && /^[ \t]*"/ { k = $1; gsub(/[":]/, "", k); print k }' tools/defs.bzl | sort)
FR_MODTESTS=$(sed -n "s/^MODULE_TESTS='\(.*\)'\$/\1/p" tools/first_red.sh | tr ' ' '\n' | sed '/^$/d' | sort)
if [ -z "$MODTESTS" ]; then
	report "tools/defs.bzl's _MODULE_TESTS reads as empty" \
		"A table this check cannot find is not a table it checked: it looks for" \
		"_MODULE_TESTS = { with one \"name\": \"layer\" entry per line."
elif [ "$MODTESTS" != "$FR_MODTESTS" ]; then
	report "tools/first_red.sh's MODULE_TESTS disagrees with tools/defs.bzl's _MODULE_TESTS" \
		"defs.bzl: $(printf '%s' "$MODTESTS" | tr '\n' ' ')" \
		"first_red.sh: $(printf '%s' "$FR_MODTESTS" | tr '\n' ' ')" \
		"A test of the whole module that first_red does not know is filed as an" \
		"exercise named '-', and a files red over a stub is demoted to 'not written'."
fi
for _mt in $MODTESTS; do
	grep -qF "\`$_mt\`" docs/reference.md 2> /dev/null && continue
	report "docs/reference.md never names $_mt, a test of the whole module" \
		"c_levels() emits it in every module (tools/defs.bzl's _MODULE_TESTS);" \
		"a reader who meets it red has to be able to look it up."
done

# ---------------------------------------------------------------------------
# N. The files layers leave out exactly what //tools:submit leaves out of the
#    push.
#
# The files layers report what is pushed (finding 102: the whole tree), so a
# file the push never carries is not theirs to report, and one it carries is.
# Two lists say which: tools/defs.bzl's _BUILD_PRODUCTS, the globs' excludes,
# and tools/submit.sh's ':(exclude)' pathspecs. They are held to the same
# extensions here. And a .git directory: submit keeps its scratch repository
# at deliverable/.git, which git never pushes, and while the globs took it
# in, the first submit turned every files layer that walks the whole tree red
# over .git/HEAD -- and the next submit's gate refused the module over it.
BP_DEFS=$(sed -n 's/^_BUILD_PRODUCTS = \[\(.*\)\]$/\1/p' tools/defs.bzl 2> /dev/null |
	tr -d '" ' | tr ',' '\n' | sed '/^$/d' | sort -u)
BP_SUBMIT=$(grep -o "':(exclude)[^']\{1,\}'" tools/submit.sh 2> /dev/null |
	sed "s/^':(exclude)//; s/'\$//" | sort -u)
if [ -z "$BP_DEFS" ] || [ -z "$BP_SUBMIT" ]; then
	report "the files layers' excludes and //tools:submit's could not both be read" \
		"tools/defs.bzl's '_BUILD_PRODUCTS = [...]' on one line: $(printf '%s' "$BP_DEFS" | tr '\n' ' ')" \
		"tools/submit.sh's ':(exclude)PATTERN' pathspecs: $(printf '%s' "$BP_SUBMIT" | tr '\n' ' ')" \
		"A list this check cannot find is not a list it compared."
elif [ "$BP_DEFS" != "$BP_SUBMIT" ]; then
	report "the files layers leave out other files than //tools:submit leaves out of the push" \
		"tools/defs.bzl's _BUILD_PRODUCTS: $(printf '%s' "$BP_DEFS" | tr '\n' ' ')" \
		"tools/submit.sh's ':(exclude)': $(printf '%s' "$BP_SUBMIT" | tr '\n' ' ')" \
		"A file in one list only is either reported and never pushed, or pushed" \
		"and never reported."
fi
if [ -n "$BP_DEFS" ] && ! grep -qF '"/**/.git/**"' tools/defs.bzl 2> /dev/null; then
	report "tools/defs.bzl's globs of the turn-in take in a .git directory" \
		"_not_build_products leaves out no '/**/.git/**': //tools:submit keeps its" \
		"scratch repository at deliverable/.git, git never pushes it, and a files" \
		"layer that walks the tree reports .git/HEAD as a file nobody asked for."
fi
# And the list is USED: every glob in tools/defs.bzl of a whole tree -- a
# pattern ending in /** -- leaves it out through _not_build_products, unless
# the tree is the harness's own (tests/). The check above held the list
# right while _stray_exercise globbed a stray folder without it, and a .o a
# hand-run of make left there was reported as pushed "with the rest", which
# //tools:submit never pushes. A call is read whole, over every line it
# spans, so the exclude may sit on a line of its own.
BP_GLOBS=$(awk '
	# q: the string the scan is in ("", a quote, or a triple quote, which
	# alone spans lines); open: inside a glob call, depth its parentheses.
	function scan(s,    i, c, t, p) {
		for (i = 1; i <= length(s); i++) {
			c = substr(s, i, 1)
			t = substr(s, i, 3)
			if (q != "") {
				if (open) buf = buf c
				if (length(q) == 3 && t == q) {
					if (open) buf = buf substr(s, i + 1, 2)
					i += 2
					q = ""
				} else if (c == "\\") {
					i++
					if (open) buf = buf substr(s, i, 1)
				} else if (c == q)
					q = ""
				continue
			}
			if (c == "#") break
			if (t == "\"\"\"" || t == "\047\047\047") {
				q = t
				if (open) buf = buf t
				i += 2
				continue
			}
			if (c == "\"" || c == "\047") {
				q = c
				if (open) buf = buf c
				continue
			}
			if (!open) {
				p = substr(s, i)
				if (p ~ /^(native\.glob|turnin_glob)\(/ && substr(s, i - 4, 4) != "def " &&
					(i == 1 || substr(s, i - 1, 1) !~ /[A-Za-z0-9_.]/)) {
					open = 1
					depth = 0
					start = NR
					buf = ""
					i = index(p, "(") + i - 2
				}
				continue
			}
			buf = buf c
			if (c == "(") depth++
			else if (c == ")" && --depth == 0) {
				if (buf ~ /\/\*\*"/ && buf !~ /"tests\// && buf !~ /_not_build_products\(/)
					print "tools/defs.bzl:" start
				open = 0
			}
		}
		# A one-quote string ends with its line; only a triple one goes on.
		if (length(q) == 1) q = ""
		if (open) buf = buf " "
	}
	{ scan($0) }' tools/defs.bzl 2> /dev/null)
if [ -n "$BP_GLOBS" ]; then
	report "a glob of a whole turn-in tree takes in what //tools:submit never pushes" \
		"$BP_GLOBS" \
		"Each globs a pattern ending in /** with no exclude = _not_build_products(...):" \
		"a .o or a .git a hand-run of make or submit left there is listed as a file of" \
		"the turn-in, and a files layer reports it as pushed when it never is."
fi

# ---------------------------------------------------------------------------
# N. A script that calls need() defines it.
#
# `need "$1" "$#"` is the three-line guard that turns `--flag` with nothing
# after it into "--flag needs a value" and exit 2, instead of a raw `set -u`
# death whose STATUS DEPENDS ON THE SHELL (dash 2, bash 1). It is a per-file
# helper, so calling it in a file that never defines it is a no-op: the shell
# reports "need: not found", exits 127, and the `;` after the call swallows
# that so argument parsing carries straight on into the unguarded "$2".
#
# It is silent in exactly the way this repo cares about -- no verdict changes,
# every arm stays green, and the guarantee is simply absent. Both selftest
# scripts spent a while in that state after the guard was rolled out across the
# runners with an editor rather than by hand, and no test noticed.
# A FIXTURE PATH MUST CARRY EVERY TOOL THE RUNNER IT DRIVES DECLARES.
#
# Some arms build a directory of symlinks and run a runner with PATH set to it,
# to prove the runner finds a pinned tool by the pinned route rather than off
# the box. The list is written by hand. A tool added to that runner's `require`
# line and not to the list makes the runner exit 2 -- "required command is not
# on PATH" -- which want_red/want_green report as "nothing was checked": an arm
# failing for a reason unrelated to what it tests.
#
# THIS HAS NOW HAPPENED FOUR TIMES on one branch: `rm`, then `sed`+`tail`, then
# `awk`, then `id`. The fixture's own comment states the rule; saying it is not
# enough.
#
# FULL COVERAGE, no allowance. An earlier version of this check tolerated ONE
# missing tool, on the theory that the arm is deliberately hiding one -- and
# that allowance is what let `id` through. It was wrong on the facts: in every
# fixture here the hidden thing is NOT in the require list at all. valgrind and
# the 32-bit compiler both arrive by flag (--valgrind, --zig) or are declared
# `# conventions: optional`, so the require list is exactly what must be
# present.
#
# Only fixtures that are actually USED are checked. selftest.sh:849 builds one
# for cycles_check and no arm ever sets PATH to it, so enforcing there would be
# a false red on dead code -- reported separately below, because a fixture
# nobody uses is a guarantee nobody gets.
_fixtmp=$(mktemp)
for f in tools/tests/selftest*.sh; do
	[ -f "$f" ] || continue
	awk '
		/^for _t in .*; do$/ { loop = $0; lineno = NR; next }
		loop && /ln -sf/ {
			if (match($0, /\$WORK\/[A-Za-z0-9_\/]+\//)) {
				dir = substr($0, RSTART, RLENGTH)
				sub(/\/[^\/]*$/, "", dir)
			}
			inloop = 1
		}
		loop && /^done$/ {
			if (inloop) print lineno "\t" dir "\t" loop
			loop = ""; inloop = 0; dir = ""
		}
	' "$f" > "$_fixtmp"
	# A HERE-FILE, NOT A PIPE. `awk ... | while read` runs the loop in a
	# SUBSHELL, so every FAILS increment inside it is discarded when the
	# subshell exits -- this check printed its findings and then reported
	# "conventions: OK — every check passed" in the same breath. That is the
	# defect class this whole file exists to catch, committed inside the check
	# written to catch it. tools/submit.sh:*/REMOTES carries the same note for
	# the same reason.
	while IFS="$(printf '\t')" read -r _ln _dir _loop; do
		[ -n "$_dir" ] || continue
		# Used at all? A fixture nobody points PATH at proves nothing.
		if ! grep -qF "PATH=\"$_dir\"" "$f"; then
			report "$f:$_ln builds a fixture PATH ($_dir) that no arm uses" \
				"A directory of symlinks nobody sets PATH to is a guarantee" \
				"nobody gets -- it reads as coverage and provides none." \
				"Either point an arm at it or delete it."
			continue
		fi
		_runner=$(sed -n "$_ln,\$p" "$f" | grep -m1 -oE 'TOOLS/[a-z0-9_]+\.sh')
		[ -n "$_runner" ] || continue
		_runner="tools/${_runner#TOOLS/}"
		[ -f "$_runner" ] || continue
		_req=$(sed -n 's/^require \(.*\)/\1/p' "$_runner" | head -1)
		[ -n "$_req" ] || continue
		# A runner that sources tools/runner_lib.sh needs what the library
		# probes as well: it exits 2 the same way when one is missing.
		if grep -q '^\. "\$RL_LIB"$' "$_runner"; then
			_req="$_req $(sed -n 's/^for _rl_t in \(.*\); do$/\1/p' tools/runner_lib.sh | head -n 1)"
		fi
		# NORMALISE FIRST. The loop line ends `... readlink; do`, so the last
		# tool's token is `readlink;` and a plain space-delimited test says it is
		# absent -- which is how this check's first run reported `id` and
		# `readlink` missing from fixtures that plainly listed them.
		_loopn=$(printf '%s' "$_loop" | tr ';' ' ')
		_missing=""
		for _t in $_req; do
			case " $_loopn " in *" $_t "*) continue ;; esac
			_missing="$_missing $_t"
		done
		[ -z "$_missing" ] && continue
		report "$f:$_ln's fixture PATH is missing what $_runner requires" \
			"missing:$_missing" \
			"The runner exits 2 on an absent required tool, which want_red" \
			"reports as 'nothing was checked' -- the arm then fails for a" \
			"reason that has nothing to do with what it tests." \
			"Got wrong four times: rm, then sed and tail, then awk, then id."
	done < "$_fixtmp"
done
rm -f "$_fixtmp"

# ...and the same rule for the selftest files' OWN helpers.
#
# The need() case above is one instance of a general shape: a shell function
# called in a file that does not define it is "not found", exit 127, and the
# `;` or the newline after it swallows that. Nothing goes red.
#
# It happened again, in the arms rather than the runners. selftest.sh defines
# want_red, want_green, want_out, want_broken and want_broken_none;
# selftest_slow.sh defines only the first, third and fourth. Three arms written
# against want_out/want_broken_none in selftest_slow SILENTLY DID NOT RUN -- the
# arm count went 17 to 19 where five arms had been added, and the file still
# reported "0 failed". An arm that does not run is worse than an arm that does
# not exist, because the count says otherwise.
#
# A call is read wherever a command starts, not only at the start of a line
# (V47): behind `! st_mine ||`, `&&`, `;` or a pipe, as an `if`'s or a
# loop's condition, after `then`, `else` or `do`, inside `{`, `(` or `$(`.
# Read at the start of a line alone, an arm written `! st_mine || want_x`
# with no want_x went as unseen as one at the start did before this rule.
# A comment line is no call: it may name an old helper.
for f in tools/tests/selftest*.sh; do
	[ -f "$f" ] || continue
	for _w in $(grep -v '^[[:blank:]]*#' "$f" |
		grep -oE '(^|[;&|!({]|\$\(|(^|[[:blank:]])(if|then|else|elif|do|while|until))[[:blank:]]*(want|later)_[a-z_]+' |
		grep -oE '(want|later)_[a-z_]+$' | sort -u); do
		grep -q "^$_w()" "$f" && continue
		report "$f calls $_w() and never defines it" \
			"An undefined function is '$_w: not found' and exit 127, swallowed" \
			"by the newline after it -- so the ARM SILENTLY DOES NOT RUN while" \
			"the file still reports 0 failed and the count quietly drops." \
			"Either define it here or express the arm with the helpers this" \
			"file has: a status assertion (want_red/want_green) is stronger" \
			"than a text one anyway."
	done
done

# ...and each toy exercise of the conventions fixtures belongs to one block.
#
# The arms that judge a check script write it into a toy exercise of an
# invented module ("$_cv99/exNN/check.sh") and run this script over the tree.
# Two blocks once wrote the same toy's check.sh: the stdin arms and, further
# down, the stable/script arms, which rewrote it. Each group passed only
# because its own run came before the other's write; a reorder, or one more
# run read by the first group's range, and one group judges the other's
# script (V11). So a toy exercise's file is written (`>`) by one statement:
# a block that needs a toy takes a number nobody uses.
#
# And a toy is a FOLDER as well as its files (V37). A merge once gave six
# toys to two blocks, and the rule above, which matched a literal `>
# "$_cvNN/exNN/..."` alone, saw none of it: one block wrote its toys and
# then `rm -rf`'d them, another wrote `"$_cv99/$_e/diff_x.c"` in a loop. On
# the tree the rule then read, nine toys were shared that way -- c-98 ex10
# a c_program's in one section and a shell exercise's in another, ex05's
# check.sh copied into another section's clue toy. So, read as the shell
# reads it -- a statement over its continuation lines, a loop's words for
# its variable, a helper's argument for its $1 (a helper on one line too,
# whose body names a toy outright where it is defined), a toy variable for
# its path (`_cv99=$WORK/cv/.../tests`), here-documents and comments skipped:
#
#   a toy's file is written by one statement (`>`, `>|`, `2>` and `&>`
#   truncate it alike; `>>` appends);
#   a toy is made (`mkdir`) by one statement;
#   a toy is named in one section of its file (`# ----- name`, the unit
#   the shards deal: an arm reads only its own section's fixtures there).
toy_uses() {  # toy_uses FILE -- KIND TOY FILE LINE SECTION, tab-separated
	awk '
	function expand(s,   v) {
		for (v in val) {
			gsub("\\$\\{" v "\\}", val[v], s)
			gsub("\\$" v "/", val[v] "/", s)
		}
		return s
	}
	# A toy is $WORK/<tree>/<module>/tests/exNN, or a toy variable this
	# file never assigns, "$_cvNN/exNN", as it is spelt.
	function emit(kind, s, at,   t, toy, f) {
		while (match(s, /"(\$WORK\/[A-Za-z0-9_]+\/[^"$ ]*\/tests|\$_cv[A-Za-z0-9_]*)\/ex[0-9]+[^"$ ]*/)) {
			t = substr(s, RSTART + 1, RLENGTH - 1)
			s = substr(s, RSTART + RLENGTH)
			match(t, /\/ex[0-9]+/)
			toy = substr(t, 1, RSTART + RLENGTH - 1)
			f = substr(t, RSTART + RLENGTH)
			print kind "\t" toy "\t" f "\t" at "\t" sec
		}
	}
	function one(s, at,   m, w) {
		if (s ~ /(^|[;&|{( \t])mkdir[ \t]/) { emit("mk", s, at); return }
		m = s
		# A write truncates: `>`, `>|`, `2>` (a numbered descriptor) and
		# `&>` (both streams) alike; an append (`>>`) is none.
		while (match(m, /(^|[^>])>\|?[ \t]*"\$[^"]*"/)) {
			w = substr(m, RSTART, RLENGTH)
			m = substr(m, RSTART + RLENGTH)
			sub(/^[^"]*/, "", w)
			emit("wr", w, at)
		}
		emit("use", s, at)
	}
	function judge(st, at,   s, w, n, i, ww, t, f, a) {
		if (st ~ /^[ \t]*#/) return
		# A helper: a statement of its body naming $1 is judged at each
		# call, with the word the call passes.
		if (infn != "" && (index(st, "$1") > 0 || index(st, "${1}") > 0)) {
			tpl[infn, ++ntpl[infn]] = st
			return
		}
		if (match(st, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]+[^ \t]+/)) {
			f = st
			sub(/^[ \t]*/, "", f)
			a = f
			sub(/[ \t].*/, "", f)
			sub(/^[^ \t]+[ \t]+/, "", a)
			sub(/[ \t].*/, "", a)
			gsub(/["\047]/, "", a)
			if (ntpl[f] > 0) {
				for (i = 1; i <= ntpl[f]; i++) {
					t = tpl[f, i]
					gsub(/\$\{1\}|\$1/, a, t)
					one(expand(t), at)
				}
				return
			}
		}
		s = st
		# A loop: each of its words, for its variable, to its done.
		if (match(s, /(^|[;&|{( \t])for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t][^;]*;[ \t]*do/)) {
			w = substr(s, RSTART, RLENGTH)
			sub(/^.*for[ \t]+/, "", w)
			lv = w
			sub(/[ \t].*/, "", lv)
			sub(/^[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t]+/, "", w)
			sub(/[ \t]*;[ \t]*do$/, "", w)
			lw = w
		}
		s = expand(s)
		if (lv != "" && (index(s, "$" lv "/") > 0 || index(s, "${" lv "}") > 0)) {
			n = split(lw, ww, /[ \t]+/)
			for (i = 1; i <= n; i++) {
				t = s
				gsub("\\$\\{" lv "\\}", ww[i], t)
				gsub("\\$" lv "/", ww[i] "/", t)
				one(t, at)
			}
		} else
			one(s, at)
		if (st ~ /(^|[;& \t])done([ \t;)]|$)/) lv = ""
	}
	BEGIN { sec = "(no section)" }
	hd != "" { t = $0; sub(/^\t*/, "", t); if (t == hd) hd = ""; next }
	/^# -----+ / { sec = $0; sub(/^# -+ /, "", sec); next }
	{
		# A here-document, outside quotes: an even count of each before it.
		if ($0 !~ /^[ \t]*#/ && match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
			pre = substr($0, 1, RSTART - 1)
			h = substr($0, RSTART, RLENGTH)
			nq = gsub(/\047/, "", pre)
			nd = gsub(/"/, "", pre)
			if (nq % 2 == 0 && nd % 2 == 0) {
				hd = h
				gsub(/[<\-"\047 \t]/, "", hd)
			}
		}
		# A toy variable: a plain path, its own toy variables spelt out.
		if (match($0, /^[ \t]*_cv[A-Za-z0-9_]*=/)) {
			v = $0
			sub(/^[ \t]*/, "", v)
			sub(/=.*/, "", v)
			x = $0
			sub(/^[^=]*=/, "", x)
			gsub(/"/, "", x)
			for (k in raw) { gsub("\\$\\{" k "\\}", raw[k], x); gsub("\\$" k "/", raw[k] "/", x) }
			delete raw[v]
			delete val[v]
			if (x ~ /^\$WORK\/[A-Za-z0-9_\/.-]+$/ || x ~ /^[A-Za-z0-9_\/.-]+$/) raw[v] = x
			if (x ~ /^\$WORK\/[A-Za-z0-9_]+\/[A-Za-z0-9_\/.-]*\/tests(\/ex[0-9]+)?$/ ||
			    x ~ /^[a-z][A-Za-z0-9_\/.-]*\/tests(\/ex[0-9]+)?$/)
				val[v] = x
		}
		if (!cont && match($0, /^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{/)) {
			infn = substr($0, 1, index($0, "(") - 1)
			ntpl[infn] = 0
			# A helper on one line: a body naming $1 is judged at each call;
			# one that names a toy outright is judged here, as a body over
			# many lines is, statement by statement.
			if ($0 ~ /\}[ \t]*(#.*)?$/) {
				b = $0
				sub(/^[^{]*\{[ \t]*/, "", b)
				sub(/[ \t;]*\}[ \t]*(#.*)?$/, "", b)
				f1 = infn
				infn = ""
				if (index(b, "$1") > 0 || index(b, "${1}") > 0) tpl[f1, ++ntpl[f1]] = b
				else judge(b, FNR)
			}
			next
		}
		if (cont) st = st " " $0
		else { st = $0; at = FNR }
		if ($0 ~ /\\$/) { cont = 1; sub(/\\$/, "", st); next }
		cont = 0
		judge(st, at)
		if (infn != "" && st ~ /^\}/) infn = ""
	}' "$1"
}
for f in tools/tests/selftest*.sh; do
	[ -f "$f" ] || continue
	toy_uses "$f" > "$lex_d/toys"
	_tw=$(awk -F'\t' '$1 == "wr" { k = "\"" $2 $3 "\""
			if (!((k, $4) in s)) { s[k, $4] = 1; n[k]++; at[k] = at[k] " " $4 } }
		END { for (k in n) if (n[k] > 1) printf "    %s, written at lines%s\n", k, at[k] }' "$lex_d/toys" | sort)
	[ -z "$_tw" ] || report "$f writes one toy exercise's file from two blocks" \
		"$_tw" \
		"Each block passes only while its own conventions run comes before the" \
		"other block's write: reordered, one judges the other's file. Give one" \
		"of them a toy exercise number no other block writes."
	_tm=$(awk -F'\t' '$1 == "mk" { k = "\"" $2 "\""
			if (!((k, $4) in s)) { s[k, $4] = 1; n[k]++; at[k] = at[k] " " $4 } }
		END { for (k in n) if (n[k] > 1) printf "    %s, made at lines%s\n", k, at[k] }' "$lex_d/toys" | sort)
	[ -z "$_tm" ] || report "$f makes one toy exercise from two statements" \
		"$_tm" \
		"Two blocks that each make a toy share it: what one leaves in it, the" \
		"other's run reads. Give one of them a toy exercise number no other" \
		"block uses."
	_ts=$(awk -F'\t' '{ k = "\"" $2 "\""
			if (!((k, $5) in s)) { s[k, $5] = 1; n[k]++; at[k] = at[k] " [" $5 "] (line " $4 ")" } }
		END { for (k in n) if (n[k] > 1) printf "    %s:%s\n", k, at[k] }' "$lex_d/toys" | sort)
	[ -z "$_ts" ] || report "$f names one toy exercise in two sections" \
		"$_ts" \
		"A shard runs the arms of some sections only, and every section's plain" \
		"code: a toy two sections use is one block's fixture read by another's" \
		"arms. Give the later block a toy exercise number of its own."
done
rm -f "$lex_d/toys"

# ...and so are a fixture tree's TODO.md and HISTORY.md, each by one statement.
#
# Several rules read them at once -- the TO VERIFY numbers, the settled
# leads, the work packages, the build script's exemption -- so several
# blocks of arms need lines in them, and two blocks once wrote the
# conventions toy's TODO.md: the TO VERIFY arms, and 460 lines further down
# the template build's arms, which rewrote it. Each passed only because its own
# run came first (V26). So a fixture tree's TODO.md or HISTORY.md is written
# (`>`) by one statement holding every block's lines; an append is no
# rewrite. A tree's other files are rewritten on purpose, a variant per run
# (submit.sh, defs.bzl, .bazelrc), and are not held to this.
for f in tools/tests/selftest*.sh; do
	[ -f "$f" ] || continue
	_rw=$(grep -nE '(^|[^>])>[[:blank:]]*"\$WORK/[A-Za-z0-9_]+/(TODO|HISTORY)\.md"' "$f" |
		sed -E 's/^([0-9]+):.*>[[:blank:]]*("\$WORK\/[A-Za-z0-9_]+\/(TODO|HISTORY)\.md").*/\1 \2/' |
		awk '{ n[$2]++; at[$2] = at[$2] " " $1 }
			END { for (t in n) if (n[t] > 1) printf "    %s, written at lines%s\n", t, at[t] }' | sort)
	[ -z "$_rw" ] || report "$f writes a fixture tree's TODO.md or HISTORY.md from two statements" \
		"$_rw" \
		"Several rules read these files, so several blocks need lines in them." \
		"Each block passes only while its own conventions run comes before the" \
		"other's write. Write the file once, holding every block's lines."
done

for f in tools/*.sh tools/tests/*.sh; do
	grep -q 'need "\$1" "\$#"' "$f" || continue
	grep -q '^need()' "$f" && continue
	report "$f calls need() and never defines it" \
		"An undefined function is 'need: not found' and exit 127, swallowed by" \
		"the ';' that follows it -- so parsing continues into the bare \$2 the" \
		"guard exists to prevent, and nothing anywhere goes red." \
		"Add the three lines every other runner carries:" \
		"    need() { [ \"\$2\" -ge 2 ] || { echo \"$(basename "$f"): \$1 needs a value\" >&2; exit 2; }; }"
done

# ---------------------------------------------------------------------------
# THE RUNNER RULES, and their two tools: which scripts are runners, and where
# in a script a command is.
#
# The rules below keep what tools/runner_lib.sh writes once from being written
# again by hand: a time budget, signal traps that end the script, excerpts that
# say what they dropped, one reading of clues.tsv. Their first versions matched
# the shapes today's runners have -- an option spelled --bin, a trap at the
# start of a line, `head -N` but not `head -c N`, a variable named CLUES -- and
# a probe runner with another spelling passed every one of them (review of wave
# 3's runner library, reproduced on probe runners). A rule for projects not
# written yet has to key on what a runner IS and on where a command IS, never
# on how today's happen to be spelled.
#
# WHICH SCRIPTS ARE RUNNERS is a property. A tools/*.sh a test names in its
# srcs -- in tools/defs.bzl, where the macros emit them, or in any BUILD file
# by hand -- is a runner; so is a script that sources tools/runner_lib.sh, which
# is how a gate another runner calls is one. A sh_binary's srcs is not a test.
test_runners=$(
	for _b in tools/defs.bzl tools/BUILD.bazel tools/tests/BUILD.bazel oracle/BUILD.bazel; do
		[ -f "$_b" ] && echo "$_b"
	done
	for _m in $MODULES; do
		[ -f "$_m/BUILD.bazel" ] && echo "$_m/BUILD.bazel"
	done
)
test_runners=$(for _b in $test_runners; do
	awk '
		/^[ \t]*[A-Za-z_][A-Za-z0-9_.]*\(/ { call = $0; sub(/^[ \t]*/, "", call); sub(/\(.*/, "", call) }
		match($0, /srcs = \["\/\/tools:[a-z0-9_]+\.sh"/) {
			if (call == "sh_binary") next
			r = substr($0, RSTART, RLENGTH)
			sub(/.*:/, "", r); sub(/"$/, "", r)
			print r
		}' "$_b"
done | sort -u)
lib_sourcers=$(for f in tools/*.sh; do
	[ "$f" = tools/runner_lib.sh ] && continue
	grep -q '^\. "\$RL_LIB"$' "$f" && echo "${f#tools/}"
done)
RUNNERS=$(for _r in $test_runners $lib_sourcers; do
	[ -f "tools/$_r" ] && echo "tools/$_r"
done | sort -u)

# WHERE A COMMAND IS is read from the shell, not matched on its lines. sh_cmds
# FILE prints one line per simple command:
#
#     LINE <TAB> CONTEXT <TAB> MARKS <TAB> WORDS <TAB> DEPTH <TAB> PIPED
#
#   LINE     where it starts
#   CONTEXT  "top", or "sub:WORD" inside a $( ) or backticks, WORD being the
#            first word of the command around it ("=" for the value of an
#            assignment, "cmd" for one in command position itself)
#   MARKS    every `# conventions:` comment on its line or in the block of
#            comment lines right above it
#   WORDS    its words as written, quotes kept, split by \037; a tab inside
#            one is \035, a newline \036, and a $( ) inside one is $(.)
#   DEPTH    how many $( ) deep it is
#   PIPED    "|" when its output goes down a pipe
#
# It knows quotes (single ones across lines, as an awk program spans them),
# $( ), backticks, ${ }, $(( )), comments, backslash-newline, here-documents
# (whose bodies it skips) and case patterns (which are never commands). What
# it does not know -- eval, sh -c STRING, aliases -- no runner uses. Each file
# is read once, here, and every rule below reads the result.
sh_cmds() {
	awk '
	BEGIN {
		US = "\037"
		d = 0
		push("C")
		ctx[d] = "top"
		nh = 0; hcur = 0; hmode = 0
	}
	function push(k) {
		d++
		fk[d] = k
		if (k == "C" || k == "B") {
			nw[d] = 0; cur[d] = ""; inw[d] = 0; pdep[d] = 0; sline[d] = 0; issub[d] = 0; pat[d] = 0
		}
	}
	function owner(   i) {
		for (i = d; i > 0; i--) if (fk[i] == "C" || fk[i] == "B") return i
		return 1
	}
	function addc(s,   o) {
		o = owner()
		if (!inw[o] && nw[o] == 0 && !sline[o]) {
			sline[o] = L
			if (!lstart) lstart = L
		}
		cur[o] = cur[o] s
		inw[o] = 1
	}
	function endw(o) {
		if (!inw[o]) return
		nw[o]++
		w[o, nw[o]] = cur[o]
		cur[o] = ""
		inw[o] = 0
		# In a case: `esac` where a pattern would start closes it, and the
		# header `case WORD in` is a command of its own, with patterns after it.
		if (pat[o] && nw[o] == 1 && w[o, 1] == "esac") { nw[o] = 0; sline[o] = 0; pat[o] = 0; return }
		if (!pat[o] && nw[o] == 3 && w[o, 1] == "case" && w[o, 3] == "in") { emit(o); pat[o] = 1 }
	}
	# The marks that apply to a command starting on line l: on that line, on
	# the line it ends on, and in the comment lines right above it or above
	# the line its whole command list began on (a || continued with a \).
	function marks(l,   s, k) {
		s = mk[l]
		if (L != l && (L in mk)) s = s " " mk[L]
		for (k = l - 1; k > 0 && (k in conly); k--) if (k in mk) s = s " " mk[k]
		if (lstart && lstart < l)
			for (k = lstart - 1; k > 0 && (k in conly); k--) if (k in mk) s = s " " mk[k]
		return s
	}
	function endc(o) {
		endw(o)
		# A pattern goes on until its ): a newline inside one ends nothing.
		if (pat[o]) return
		emit(o)
	}
	function emit(o,   s, i) {
		for (i = 1; i <= nw[o]; i++) gsub(/\t/, "\035", w[o, i])
		if (nw[o] > 0) {
			mks = marks(sline[o]); gsub(/[\t\036]/, " ", mks)
			cx = ctx[o]; gsub(/[\t\036]/, " ", cx)
			s = sline[o] "\t" cx "\t" mks "\t" w[o, 1]
			for (i = 2; i <= nw[o]; i++) s = s US w[o, i]
			print s "\t" o "\t" (piped ? "|" : "")
		}
		nw[o] = 0
		sline[o] = 0
	}
	# The context a command substitution opens in: the first word of the command
	# around it ("=" when it is the value of an assignment, "cmd" when it is
	# itself in command position).
	function subctx(o,   i, x) {
		for (i = 1; i <= nw[o]; i++) {
			x = w[o, i]
			if (x !~ /^[A-Za-z_][A-Za-z0-9_]*=/) return "sub:" x
		}
		if (inw[o] && cur[o] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) return "sub:="
		if (nw[o] > 0) return "sub:="
		return "sub:cmd"
	}
	function subpush(k,   c) {
		c = subctx(owner())
		push(k)
		ctx[d] = c
		issub[d] = 1
	}
	# $(( ... )): an arithmetic expansion, taken whole as part of the word.
	function arith(line, i,   j, dep, c) {
		dep = 0
		for (j = i + 1; j <= length(line); j++) {
			c = substr(line, j, 1)
			if (c == "(") dep++
			else if (c == ")") { dep--; if (dep == 0) break }
		}
		addc("$((.))")
		return j
	}
	{
		L = FNR
		line = $0
		if (hmode) {
			l = line
			if (hstrip[hcur + 1]) sub(/^\t+/, "", l)
			if (l == hdel[hcur + 1]) {
				hcur++
				if (hcur >= nh) hmode = 0
			}
			next
		}
		if (d == 1 && line ~ /^[ \t]*#/) conly[L] = 1
		n = length(line)
		cont = 0
		for (i = 1; i <= n; i++) {
			c = substr(line, i, 1)
			k = fk[d]
			if (k == "S") {
				addc(c)
				if (c == "\047") d--
				continue
			}
			if (k == "D" || k == "P") {
				if (c == "\\") { addc(c substr(line, i + 1, 1)); i++; continue }
				if (k == "D" && c == "\"") { addc(c); d--; continue }
				if (k == "P") {
					if (c == "{") pb[d]++
					if (c == "}") { pb[d]--; if (pb[d] == 0) { addc(c); d--; continue } }
					if (c == "\"") { addc(c); push("D"); continue }
				}
				if (c == "$" && substr(line, i + 1, 2) == "((") { i = arith(line, i); continue }
				if (c == "$" && substr(line, i + 1, 1) == "(") { addc("$(.)"); subpush("C"); i++; continue }
				if (c == "$" && substr(line, i + 1, 1) == "{") { addc("${"); push("P"); pb[d] = 1; i++; continue }
				if (c == "`") { addc("`.`"); subpush("B"); continue }
				addc(c)
				continue
			}
			# A command list: the script itself, a $( ), a backtick.
			o = d
			if (c == "\\") {
				if (i == n) { cont = 1; break }
				addc(c substr(line, i + 1, 1)); i++; continue
			}
			if (c == "\047") { addc(c); push("S"); continue }
			if (c == "\"") { addc(c); push("D"); continue }
			if (c == "`") {
				if (k == "B") { endc(o); d--; continue }
				addc("`.`"); subpush("B"); continue
			}
			if (c == "$") {
				if (substr(line, i + 1, 2) == "((") { i = arith(line, i); continue }
				if (substr(line, i + 1, 1) == "(") { addc("$(.)"); subpush("C"); i++; continue }
				if (substr(line, i + 1, 1) == "{") { addc("${"); push("P"); pb[d] = 1; i++; continue }
				addc(c); continue
			}
			if (c == "#" && !inw[o]) {
				rest = substr(line, i)
				if (rest ~ /# conventions:/) mk[L] = (L in mk) ? mk[L] " " rest : rest
				break
			}
			if (c == " " || c == "\t") { endw(o); continue }
			if (c == ";") {
				if (substr(line, i + 1, 1) == ";") { i++; endc(o); pat[o] = 1; continue }
				endc(o); continue
			}
			if (c == "&") {
				if (inw[o] && cur[o] ~ /[<>]$/) { addc(c); continue }
				if (substr(line, i + 1, 1) == "&") i++
				endc(o); continue
			}
			if (c == "|") {
				if (inw[o] && cur[o] ~ />$/) { addc(c); continue }
				if (pat[o]) { endw(o); continue }
				if (substr(line, i + 1, 1) == "|") { i++; endc(o); continue }
				piped = 1; endc(o); piped = 0; continue
			}
			if (c == "(") {
				if (pat[o]) continue
				endc(o); pdep[o]++; continue
			}
			if (c == ")") {
				# The ) of a case pattern: what came before it is a pattern, not a command.
				if (pat[o]) { endw(o); nw[o] = 0; sline[o] = 0; pat[o] = 0; continue }
				if (issub[o] && pdep[o] == 0 && k == "C") { endc(o); d--; continue }
				if (pdep[o] > 0) pdep[o]--
				endc(o)
				continue
			}
			if (c == "<" && substr(line, i + 1, 1) == "<") {
				j = i + 2; strip = 0
				if (substr(line, j, 1) == "-") { strip = 1; j++ }
				while (substr(line, j, 1) ~ /[ \t]/) j++
				del = ""
				while (j <= n) {
					c2 = substr(line, j, 1)
					if (c2 ~ /[ \t;&|<>)]/) break
					del = del c2; j++
				}
				gsub(/[\047"\\]/, "", del)
				nh++; hdel[nh] = del; hstrip[nh] = strip
				endw(o); addc("<<" del); endw(o)
				i = j - 1
				continue
			}
			if (c == "<" || c == ">") {
				if (inw[o] && cur[o] !~ /^[0-9]*$/ && cur[o] !~ /[<>]$/) endw(o)
				addc(c); continue
			}
			addc(c)
		}
		if (cont) next
		k = fk[d]
		if (k == "S" || k == "D" || k == "P") addc("\036")
		else { endc(d); lstart = 0 }
		if (nh > hcur) hmode = 1
	}
	END {
		while (d > 0) {
			if (fk[d] == "C" || fk[d] == "B") endc(d)
			d--
		}
	}' "$1"
}
cmds_of() {  # cmds_of FILE -- the path of FILE's sh_cmds, made on first use
	_co="$lex_d/$(printf '%s' "$1" | tr '/' '_').cmds"
	[ -f "$_co" ] || sh_cmds "$1" > "$_co"
	printf '%s\n' "$_co"
}

# ---------------------------------------------------------------------------
# N. The cycles row names every exercise whose c_cycles leaves cases out.
#
# docs/reference.md's `cycles` row lists, after "`c_cycles`' `max_unit`:",
# the exercises whose c_cycles call leaves a corpus's capacity cases out, so
# a reader knows which reports skip them. It named C 07 ex05 and C 09 ex02
# after six more had been given one. Each C module's BUILD file is read for
# its c_cycles calls, whole, at any indentation, and the row is held to the
# exercises whose call sets max_unit ("C NN exAA and exBB, C MM exCC").
mu_build=$(for _m in $MODULES; do
	case "$_m" in */c-piscine-c-[0-9][0-9]) ;; *) continue ;; esac
	[ -f "$_m/BUILD.bazel" ] || continue
	awk -v mod="C ${_m##*-}" '
		!inc { p = index($0, "c_cycles("); if (p == 0) next; inc = 1; t = ""; d = 0; $0 = substr($0, p + 8) }
		{
			l = $0; sub(/#.*/, "", l); t = t " " l
			d += gsub(/\(/, "(", l) - gsub(/\)/, ")", l)
			if (d > 0) next
			inc = 0
			if (t !~ /[(,][ \t]*max_unit[ \t]*=/) next
			if (match(t, /[(,][ \t]*num[ \t]*=[ \t]*"[0-9][0-9]"/)) {
				n = substr(t, RSTART, RLENGTH); sub(/^[^"]*"/, "", n); sub(/"$/, "", n)
				print mod " ex" n
			} else
				print mod " (num not written out)"
		}
	' "$_m/BUILD.bazel"
done | sort -u)
mu_doc=$(awk '
	/^\| `cycles` \|/ {
		r = $0
		if (!sub(/.*`c_cycles`'"'"' `max_unit`: */, "", r)) exit
		sub(/\).*/, "", r)
		n = split(r, w, /[ ,]+/)
		for (i = 1; i <= n; i++) {
			if (w[i] == "C" && w[i + 1] ~ /^[0-9][0-9]$/) { mod = "C " w[i + 1]; i++ }
			else if (w[i] ~ /^ex[0-9][0-9]$/ && mod != "") print mod " " w[i]
		}
	}' docs/reference.md 2> /dev/null | sort -u)
mu_text=$(for _m in $MODULES; do
	case "$_m" in */c-piscine-c-[0-9][0-9]) ;; *) continue ;; esac
	grep -l 'max_unit' "$_m/BUILD.bazel" 2> /dev/null
done)
if [ -n "$mu_text" ] && [ -z "$mu_build" ]; then
	# A BUILD file says max_unit and no call was read: the pattern broke.
	report "no c_cycles call with max_unit was read, and these BUILD files name it" \
		"$(printf '%s\n' "$mu_text" | sed 's/^/    /')" \
		"The search above no longer reads them, so this check holds nothing." \
		"Fix the pattern."
elif [ "$mu_build" != "$mu_doc" ]; then
	report "docs/reference.md's cycles row and the c_cycles calls with max_unit disagree" \
		"$(printf '%s\n' "$mu_build" | sed 's/^/    BUILD: /')" \
		"$(printf '%s\n' "$mu_doc" | sed 's/^/    docs:  /')" \
		"List, after \"\`c_cycles\`' \`max_unit\`:\", every exercise whose c_cycles" \
		"call sets max_unit, as \"C 07 ex03 and ex05, C 09 ex02\"."
fi

# ---------------------------------------------------------------------------
# N. Every knob a runner reads from the environment is in docs/reference.md's
#    table, with the default the runner uses; and every knob the table names
#    is read by something.
#
# DIFF_MAX_ROWS was documented as the cap on "a diff report" and one runner
# read it; five others had a number of their own -- two behind knobs the table
# named, three hard-coded -- so a student who raised it as the table said saw
# the same ten rows (finding 167). Nothing held the table to the runners.
#
# A KNOB is a variable a runner reads as ${NAME:-default} and never assigns:
# it comes from --test_env or not at all. The runners are the ones the rules
# below call runners, and tools/runner_lib.sh, which all of them source. Each
# knob needs a row in "## Environment variables" (either table there), and
# where the row gives its default as one literal in backquotes, it must be the
# default the runner uses. A default the table gives in words ("8 MiB", "a
# tenth of the test's limit") is left to the reader. Bazel's own variables and
# the system's (TEST_*, HOME, TMPDIR ...) are not knobs of this repo's.
#
# The other way round, a row whose variable nothing reads any more -- a knob
# retired in favour of another -- is a row that tells a student to set
# something that does nothing: its name must appear in a line of code (not a
# comment) somewhere under tools/.
knob_reads() {  # knob_reads FILE -- "NAME DEFAULT FILE" per knob FILE reads
	awk -v f="$1" '
		/^[ \t]*#/ { next }
		{
			line = $0
			# Assignments: NAME= at the start of a command.
			rest = line
			while (match(rest, /(^|[;&|( \t])(export[ \t]+|readonly[ \t]+|local[ \t]+)?[A-Z][A-Z0-9_]*=/)) {
				a = substr(rest, RSTART, RLENGTH)
				sub(/^[;&|( \t]*/, "", a); sub(/^(export|readonly|local)[ \t]+/, "", a); sub(/=$/, "", a)
				assigned[a] = 1
				rest = substr(rest, RSTART + RLENGTH)
			}
			if (match(line, /(^|[ \t;])(read|for)[ \t]/)) {
				n = split(substr(line, RSTART), w, /[ \t;]+/)
				for (i = 1; i <= n; i++) if (w[i] ~ /^[A-Z][A-Z0-9_]*$/) assigned[w[i]] = 1
			}
			rest = line
			while (match(rest, /\$\{[A-Z][A-Z0-9_]*:-[^}$]+\}/)) {
				r = substr(rest, RSTART + 2, RLENGTH - 3)
				name = r; sub(/:-.*/, "", name)
				def = r; sub(/^[A-Z0-9_]*:-/, "", def)
				if (!(name in seen)) { seen[name] = def; order[++k] = name }
				rest = substr(rest, RSTART + RLENGTH)
			}
		}
		END {
			for (i = 1; i <= k; i++) {
				n = order[i]
				if (n in assigned) continue
				if (n ~ /^(TEST_|BUILD_|LC_|XDG_)/) continue
				if (n ~ /^(RUNFILES_DIR|HOME|USER|TMPDIR|LANG|TZ|SHELL|PATH|TERM|PWD)$/) continue
				printf "%s %s %s\n", n, seen[n], f
			}
		}' "$1"
}
knob_rows=$(awk -F'|' '
	/^## / { sec = $0 }
	sec == "## Environment variables" && /^\| `[A-Z][A-Z0-9_]*`(, `[A-Z][A-Z0-9_]*`)* \|/ {
		names = $2; def = $3
		gsub(/^ +| +$/, "", def)
		if (def ~ /^`[^`]*`$/) { gsub(/`/, "", def) } else def = "(words)"
		n = split(names, nn, ",")
		for (i = 1; i <= n; i++) { x = nn[i]; gsub(/[ `]/, "", x); print x, def }
	}' docs/reference.md 2> /dev/null)
knob_bad=$(for f in $RUNNERS tools/runner_lib.sh; do [ -f "$f" ] && knob_reads "$f"; done | sort -u |
	while read -r _kn _kd _kf; do
		_row=$(printf '%s\n' "$knob_rows" | awk -v n="$_kn" '$1 == n { print $2; exit }')
		if [ -z "$_row" ]; then
			printf '    %s reads %s (default %s); the table has no row for it\n' "$_kf" "$_kn" "$_kd"
		elif [ "$_row" != "(words)" ] && [ "$_row" != "$_kd" ]; then
			printf '    %s reads %s with default %s; the table says %s\n' "$_kf" "$_kn" "$_kd" "$_row"
		fi
	done)
knob_dead=$(printf '%s\n' "$knob_rows" | while read -r _kn _kd; do
	[ -n "$_kn" ] || continue
	# -R, not -r: under bazel test every file here is a symlink into the
	# source tree, and -r does not follow one -- every row read as dead.
	grep -Rsq --include='*.sh' --include='*.bzl' --include='*.c' --include='*.py' --include='BUILD.bazel' \
		-e "^[^#]*$_kn" tools .bazelrc 2> /dev/null && continue
	printf '    %s: nothing under tools/ reads it\n' "$_kn"
done)
[ -z "$knob_bad$knob_dead" ] || report "docs/reference.md's environment table and the runners disagree" \
	"$knob_bad" \
	"$knob_dead" \
	"A knob a runner reads is one a student can set, and the table is where" \
	"they look it up: each needs a row, with the default the runner really" \
	"uses. A row for a knob nothing reads tells them to set something that" \
	"does nothing -- delete it. (A knob is a variable a runner reads with a" \
	"default for when it is unset, and never assigns.)"

# ---------------------------------------------------------------------------
# N. A setting tools/runner_lib.sh reads with an empty default is reset when
#    the library is sourced, unless it comes from the environment on purpose.
#
# rl_gate read RL_GATE_PASS and RL_GATE_LABEL as ${NAME:-}, and only the two
# runners that set them reset them: bsq_check.sh and both rush runners set
# neither, so a value in the environment -- a --test_env, a hand run -- reached
# their gates, a label turning the corpus SKIP into a case's and a word of the
# differ's options breaking the gate (V36). The rule above sees a knob only
# where the default is not empty. So every name the library reads as
# ${NAME:-} is assigned at the start of one of its lines (its reset, when it
# is sourced), or is one the environment hands over by design: Bazel's own
# (TEST_* ...), a row of docs/reference.md's environment table, one
# tools/defs.bzl's _test() sets for a runner (env["NAME"]), or one the library
# exports to the runners it starts.
if [ -f tools/runner_lib.sh ]; then
	rl_unreset=$(grep -v '^[[:blank:]]*#' tools/runner_lib.sh |
		grep -o '\${[A-Z][A-Z0-9_]*:-}' | sed 's/^\${//; s/:-}$//' | sort -u |
		while IFS= read -r _rn; do
			grep -q "^$_rn=" tools/runner_lib.sh && continue
			case "$_rn" in
				TEST_* | BUILD_* | LC_* | XDG_* | RUNFILES_DIR | HOME | USER | TMPDIR | LANG | TZ | SHELL | PATH | TERM | PWD) continue ;;
			esac
			printf '%s\n' "$knob_rows" | awk -v n="$_rn" '$1 == n { f = 1 } END { exit !f }' && continue
			grep -v '^[[:blank:]]*#' tools/runner_lib.sh |
				grep -Eq "(^|[;[:blank:]])export[[:blank:]]([^#]*[[:blank:]])?$_rn([[:blank:]]|$)" && continue
			grep -qF "env[\"$_rn\"]" tools/defs.bzl 2> /dev/null && continue
			printf '    tools/runner_lib.sh reads ${%s:-} and never resets it\n' "$_rn"
		done)
	[ -z "$rl_unreset" ] || report "a setting of tools/runner_lib.sh reaches its runners from the environment" \
		"$rl_unreset" \
		"A runner that sets the setting itself after sourcing the library is" \
		"fine; one that does not takes whatever the environment holds. Reset it" \
		"where the library is sourced, NAME=\"\" on a line of its own, as" \
		"RL_GATE_WHY is. If the environment is meant to set it, give it a row in" \
		"docs/reference.md's environment table."
fi

# ---------------------------------------------------------------------------
# N. A test's runner sources tools/runner_lib.sh, or says it runs no student
# code.
#
# The time budget, the traps that end the script, and how a run ended are the
# library's; a runner that does not source it has none of them. Every runner
# that runs student code sources it today, and the few that run none (norm,
# compile, files, the oracle's self-check, this script) say so in one line --
# so that a new runner is one or the other by a decision someone can read,
# not by a pattern it happened to escape:
#     # conventions: runs no student code -- <what it runs instead>
runner_decl=$(for f in $RUNNERS; do
	grep -q '^\. "\$RL_LIB"$' "$f" && continue
	grep -qE '^# conventions: runs no student code -- .+' "$f" && continue
	printf '    %s: named in the srcs of a test\n' "$f"
done)
[ -z "$runner_decl" ] || report \
	"a test's runner neither sources tools/runner_lib.sh nor says it runs no student code" \
	"$runner_decl" \
	"A runner that runs the student's program needs the library's time budget," \
	"its traps and its reading of how a run ended (see its header for how to" \
	"source it). One that runs none says so near the top, with what it runs" \
	"instead:" \
	"    # conventions: runs no student code -- <what it runs instead>"

# ---------------------------------------------------------------------------
# N. A signal trap ENDS the script.
#
# `trap 'rm -rf "$T"' EXIT INT TERM` was in about thirty scripts, and it does
# not do what it reads as. A trap on a signal that does not exit RESUMES the
# script where the signal landed: on Bazel's SIGTERM the scratch directory was
# deleted and the runner carried on without it -- "Directory nonexistent", then
# a verdict about files that were gone, sometimes exit 0 (finding 066). The
# cleanup goes on EXIT, and each signal trap exits with the status a death by
# that signal reports:
#
#     trap 'rm -rf "$T"' EXIT
#     trap 'exit 143' TERM
#     trap 'exit 130' INT
#
# which is what tools/runner_lib.sh's rl_traps does for a runner. A trap whose
# action calls a function of the same file that exits is fine too; '' (ignore)
# and - (reset) change no control flow and are not checked. A trap is found
# wherever a command can start -- after ;, &&, ||, {, (, then, do, else -- not
# only at the start of a line: `T=$(mktemp -d); trap ... EXIT INT TERM` was
# the shape the line-start form missed.
#
# trap_check FILE MODE -- MODE noexit: each signal trap that does not exit;
# MODE any: every trap.
trap_check() {
	awk -v f="$1" -v mode="$2" '
		BEGIN {
			split("if then else elif do while until ! { } time", k, " ")
			for (i in k) kw[k[i]] = 1
		}
		# First pass, the script: the functions whose body exits.
		FNR == NR {
			raw[FNR] = $0
			if (match($0, /^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{/)) {
				fn = $0; sub(/\(.*/, "", fn); infn = 1
				if ($0 ~ /\}[ \t]*$/) {
					if ($0 ~ /(^|[^A-Za-z0-9_])exit([^A-Za-z0-9_]|$)/) exits[fn] = 1
					infn = 0
				}
				next
			}
			if (infn && /^\}/) { infn = 0; next }
			if (infn && /(^|[^A-Za-z0-9_])exit([^A-Za-z0-9_]|$)/) exits[fn] = 1
			next
		}
		{
			split($0, r, "\t")
			nw = split(r[4], w, "\037")
			for (q = 1; q <= nw; q++) { gsub(/\035/, "\t", w[q]); gsub(/\036/, "\n", w[q]) }
			i = 1
			while (i <= nw && ((w[i] in kw) || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++
			if (i > nw || w[i] != "trap") next
			if (mode == "any") { printf "    %s:%d: %s\n", f, r[1], raw[r[1]]; next }
			act = w[i + 1]
			if (act ~ /^\047.*\047$/ || act ~ /^".*"$/) act = substr(act, 2, length(act) - 2)
			if (act == "" || act == "-") next
			sigs = " "
			for (j = i + 2; j <= nw; j++) sigs = sigs w[j] " "
			if (sigs !~ / (SIG)?(INT|TERM|HUP|QUIT) / && sigs !~ / (1|2|3|15) /) next
			if (act ~ /(^|[^A-Za-z0-9_])exit([^A-Za-z0-9_]|$)/) next
			x = act; sub(/^[ \t]*/, "", x); sub(/[ \t;].*/, "", x)
			if (x in exits) next
			printf "    %s:%d: %s\n", f, r[1], raw[r[1]]
		}' "$1" "$(cmds_of "$1")"
}
noexit=$(
	{
		for f in tools/*.sh tools/tests/*.sh tools/cc_toolchain/*.sh; do
			[ -f "$f" ] && echo "$f"
		done
		for _m in $MODULES; do
			[ -d "$_m/tests" ] && find "$_m/tests" -name '*.sh' 2> /dev/null
		done
	} | sort -u | while IFS= read -r f; do trap_check "$f" noexit; done
)
[ -z "$noexit" ] || report \
	"a signal trap cleans up and then lets the script carry on" \
	"$noexit" \
	"A trap on INT or TERM that does not exit RESUMES the script after it" \
	"runs: on Bazel's SIGTERM the scratch files are deleted and the script goes" \
	"on without them. Put the cleanup on EXIT and end on the signal:" \
	"    trap '<cleanup>' EXIT" \
	"    trap 'exit 143' TERM" \
	"    trap 'exit 130' INT" \
	"or, in a runner, rl_traps '<cleanup>' (tools/runner_lib.sh)."

# In a runner that sources tools/runner_lib.sh, rl_traps is the only trap: a
# `trap ... EXIT` of its own would replace the library's, which removes the
# file each run's ending is read from, and a signal trap of its own would
# replace the ones that end the runner.
libtrap=$(for f in $lib_sourcers; do trap_check "tools/$f" any; done)
[ -z "$libtrap" ] || report \
	"a runner sets a trap of its own beside tools/runner_lib.sh's" \
	"$libtrap" \
	"Use rl_traps '<cleanup>': it runs the cleanup on EXIT with the library's" \
	"own, and ends the runner on TERM, INT and HUP."

# ---------------------------------------------------------------------------
# N. Student code runs under the time budget.
#
# Bazel kills a test at TEST_TIMEOUT, and a runner still running student code
# then prints nothing: the log holds "-- Test timed out --" and the student
# learns neither which input nor why. rust_diff.sh ran the student's harness
# with no limit at all, cycles_check.sh ran callgrind with none, and the
# runners that did bound a run each picked a fixed cap blind to the test's own
# limit (finding 066). tools/runner_lib.sh's rl_tmo derives each run's limit
# from what is left of TEST_TIMEOUT, less a margin to write the report in, and
# rl_overrun says "did not finish within Ns: an infinite loop, or too slow on
# <case>". So:
#
#   * no script spells `timeout` itself: a hand-rolled bound is one that does
#     not know the test's limit, and one that kills the helper reporting how
#     the run ended (tools/exit_status enforces rl_tmo's limit itself);
#   * a runner starts a program by path only through rl_run. A program named
#     by a variable or a path -- "$BIN", $PROG, "$WORK/probe", ./a.out, also
#     after env, exec, valgrind, setarch, taskset, nice, stdbuf, xargs or sh --
#     is the student's code until the runner says otherwise. The option it
#     came in by, and what the runner built it from, do not matter: a runner
#     that compiles the student's sources and runs $WORK/probe runs student
#     code as surely as one handed --bin.
#
# What the runner says otherwise with is a declaration, for a harness tool it
# starts by path on purpose -- the pinned compiler, the oracle, another runner
# that keeps the same budget:
#     # conventions: harness tool NAME [NAME...] -- <what it is>
# anywhere in the file exempts $NAME in command position, and
#     # conventions: harness tool -- <why>
# on the line, or in the comments right above it, exempts that one command.
budget_bad=$(for f in tools/*.sh; do
	[ "$f" = tools/conventions.sh ] && continue
	# The tool's name is assembled inside awk: written out, this very line
	# would read to the require scanner above as a call to it.
	awk -v f="$f" '
		BEGIN {
			t = "time" "out"
			re = "command -v " t "|" t " -s |(^|[;&|(!{]|then |do |else )[ \t]*" t "[ \t]"
		}
		/^[ \t]*#/ { next }
		$0 ~ re { printf "    %s:%d: bounds a run itself: %s\n", f, FNR, $0 }' "$f"
done
for f in $RUNNERS; do
	_tools=$(sed -n 's/^[[:blank:]]*# conventions: harness tool \([A-Za-z_][A-Za-z0-9_ ]*\) -- ..*/\1/p' "$f" | tr '\n' ' ')
	awk -v f="$f" -v tools="$_tools" '
		BEGIN {
			split("if then else elif do while until ! { } time", k, " ")
			for (i in k) kw[k[i]] = 1
			n = split(tools, t, " ")
			for (i = 1; i <= n; i++) tool[t[i]] = 1
			# The programs that run another, by how their options go.
			split("exec command nohup builtin setsid valgrind strace ltrace linux32 linux64 i386 x86_64", k, " ")
			for (i in k) wrap[k[i]] = "opts"
			split("nice stdbuf ionice xargs", k, " ")
			for (i in k) wrap[k[i]] = "args"
			split("setarch taskset chrt", k, " ")
			for (i in k) wrap[k[i]] = "one"
			split("sh bash dash", k, " ")
			for (i in k) wrap[k[i]] = "shell"
		}
		FNR == NR { raw[FNR] = $0; next }
		function isredir(x) { return x ~ /^[0-9]*(<<?-?|>>?|<>|>\||[<>]&)/ }
		function bareop(x) { return x ~ /^[0-9]*(<<?-?|>>?|<>|>\|)$/ }
		# The variable a word begins with: "$X", $X, ${X}, "$X/...".
		function varof(x,   v) {
			v = x
			sub(/^"/, "", v)
			if (v !~ /^\$/) return ""
			sub(/^\$\{?/, "", v)
			if (v ~ /^[@*#?0-9]/) return substr(v, 1, 1)
			sub(/[^A-Za-z0-9_].*/, "", v)
			return v
		}
		function by_path(x) { return x ~ /^"?\$/ || x ~ /^"?\.\.?\// }
		{
			split($0, r, "\t")
			nw = split(r[4], w, "\037")
			m = 0
			for (i = 1; i <= nw; i++) {
				if (isredir(w[i])) { if (bareop(w[i])) i++; continue }
				m++; v[m] = w[i]
			}
			i = 1
			while (i <= m && ((v[i] in kw) || v[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++
			if (i > m || v[i] == "rl_run") next
			if (v[i] == "command" && v[i + 1] ~ /^-[A-Za-z]*[vV]/) next
			# Past the programs that run another: what they run is the
			# program in question.
			while (i <= m) {
				x = v[i]
				if (x == "env") {
					i++
					while (i <= m && (v[i] ~ /^-/ || v[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) {
						if (v[i] == "-u") i++
						i++
					}
					continue
				}
				if (wrap[x] == "opts") {
					i++
					while (i <= m && v[i] ~ /^-/) i++
					continue
				}
				if (wrap[x] == "args") {
					i++
					while (i <= m && v[i] ~ /^-/) { if (v[i] ~ /^-[nioecItLPsdaE]$/) i++; i++ }
					continue
				}
				if (wrap[x] == "one") {
					i++
					while (i <= m && v[i] ~ /^-/) i++
					i++
					while (i <= m && v[i] ~ /^-/) i++
					continue
				}
				# sh FILE runs FILE; sh -c STRING and sh -n (read, never
				# run) are not a path this scan can follow.
				if (wrap[x] == "shell") {
					i++
					while (i <= m && v[i] ~ /^-/) { if (v[i] ~ /[cn]/) { i = m + 1; break } i++ }
					if (i <= m && by_path(v[i])) break
					i = m + 1
					continue
				}
				break
			}
			if (i > m) next
			p = v[i]
			if (!by_path(p) || (varof(p) in tool)) next
			if (r[3] ~ /# conventions: harness tool --/) next
			line = raw[r[1]]
			sub(/^[ \t]+/, "", line)
			printf "    %s:%d: runs %s outside rl_run: %s\n", f, r[1], p, line
		}' "$f" "$(cmds_of "$f")"
done)
[ -z "$budget_bad" ] || report \
	"student code runs outside the time budget" \
	"$budget_bad" \
	"A program a runner starts by path is the student's until the runner says" \
	"otherwise, and runs through tools/runner_lib.sh:" \
	"    rl_tmo \"\$CAP\" || { rl_overrun \"<what>\"; exit 1; }" \
	"    rl_run \"\$BIN\" ...; rl_classify \"\$?\"" \
	"(or rl_sweep_next / rl_sweep_ran in a loop). Its limit is the test's own," \
	"less a margin to report in, so an overrun is said, never a bare Bazel" \
	"TIMEOUT with an empty log. A harness tool started by path on purpose --" \
	"the pinned compiler, the oracle, a runner that keeps the same budget --" \
	"is declared once in the file:" \
	"    # conventions: harness tool NAME -- <what it is>" \
	"or, for one command, in a comment on the line above it:" \
	"    # conventions: harness tool -- <why>"

# ---------------------------------------------------------------------------
# N. A test stages what its runner sources and runs student code through.
#
# A runner that sources tools/runner_lib.sh cannot start without it in the
# test's data, and one that runs student code (rl_tmo, rl_run) cannot run it
# without tools/exit_status: both stop with exit 2, a wiring error. That is
# loud, but it can be LATE. A gated layer skips while the exercise is a stub
# and first runs student code once the student's answer passes the gate --
# so a new project's hand-written sh_test that forgot one of the two passes
# every run its author makes and then hands the student a harness error.
# defs.bzl's _test() stages both for every macro-made test (runner_lib.sh for
# all, exit_status for the runners in _EXIT_STATUS_RUNNERS); so:
#
#   * every tools/*.sh that calls rl_tmo, rl_run or rl_ready is in
#     _EXIT_STATUS_RUNNERS;
#   * every sh_test written by hand in a BUILD file whose srcs is such a
#     runner lists //tools:exit_status, and one whose runner sources
#     runner_lib.sh lists //tools:runner_lib.sh -- in its data, or in a list
#     named in its data (BSQ_GATE_DATA).
lib_runners=""
wait_runners=""
for f in tools/*.sh; do
	[ "$f" = tools/runner_lib.sh ] && continue
	grep -q '^\. "\$RL_LIB"$' "$f" || continue
	lib_runners="$lib_runners ${f#tools/}"
	# A command, not a comment or a message, that makes a run: read from
	# sh_cmds, since a comment naming rl_run is not a use of it.
	awk -F'\t' '{
			n = split($4, w, "\037")
			for (i = 1; i <= n; i++) if (w[i] ~ /^rl_(tmo|run|ready|sweep_next)$/) { found = 1; exit }
		}
		END { exit !found }' "$(cmds_of "$f")" &&
		wait_runners="$wait_runners ${f#tools/}"
done
_esr=$(sed -n '/^_EXIT_STATUS_RUNNERS = \[/,/^\]/p' tools/defs.bzl)
staging_bad=$(
	for r in $wait_runners; do
		printf '%s\n' "$_esr" | grep -qF "\"//tools:$r\"" ||
			printf '    tools/defs.bzl: _EXIT_STATUS_RUNNERS lacks //tools:%s, which runs student code\n' "$r"
	done
	for _m in $MODULES; do
		[ -f "$_m/BUILD.bazel" ] || continue
		awk -v f="$_m/BUILD.bazel" -v libr=" $lib_runners " -v waitr=" $wait_runners " '
			# Top-level lists, by name, for a data attribute that names one.
			/^[A-Z_][A-Z0-9_]* = \[/ { lname = $1; ltext[lname] = ""; inlist = 1 }
			inlist { ltext[lname] = ltext[lname] $0 "\n"; if ($0 ~ /^\]/) inlist = 0; next }
			/^[ \t]*sh_test\(/ { inb = 1; depth = 0; body = ""; start = FNR }
			inb {
				body = body $0 "\n"
				t = $0
				depth += gsub(/\(/, "(", t)
				t = $0
				depth -= gsub(/\)/, ")", t)
				if (depth > 0) next
				inb = 0
				if (!match(body, /srcs = \["\/\/tools:[a-z0-9_]+\.sh"\]/)) next
				r = substr(body, RSTART, RLENGTH)
				sub(/^srcs = \["\/\/tools:/, "", r); sub(/"\]$/, "", r)
				all = body
				for (n in ltext) if (index(body, n)) all = all ltext[n]
				tname = body; sub(/^[^"]*"/, "", tname); sub(/".*/, "", tname)
				if (index(libr, " " r " ") && !index(all, "\"//tools:runner_lib.sh\""))
					printf "    %s:%d: sh_test %s runs %s without //tools:runner_lib.sh in its data\n", f, start, tname, r
				if (index(waitr, " " r " ") && !index(all, "\"//tools:exit_status\""))
					printf "    %s:%d: sh_test %s runs %s without //tools:exit_status in its data\n", f, start, tname, r
			}' "$_m/BUILD.bazel"
	done
)
[ -z "$staging_bad" ] || report \
	"a test does not stage what its runner needs" \
	"$staging_bad" \
	"A runner that sources tools/runner_lib.sh needs it in the test's data, and" \
	"one that runs student code needs //tools:exit_status too. Without them it" \
	"stops with a wiring error -- often only once a student's answer passes the" \
	"gate in front of it. Macro-made tests get both from defs.bzl's _test()."

# And tools/defs.bzl's _LIB_RUNNERS, which c_levels()' audit reads to refuse
# a raised test whose runner prints nothing of why it is raised (rl__raised
# is the library's), is exactly the scripts above that source the library:
# one missing there refuses a raise its runner would explain, and one too
# many lets a raise through to a runner whose red says nothing of it.
_lbr=$(sed -n '/^_LIB_RUNNERS = \[/,/^\]/p' tools/defs.bzl 2> /dev/null |
	sed -n 's|^ *"//tools:\([A-Za-z0-9_.-]*\)",$|\1|p' | sort -u)
_lbw=$(for r in $lib_runners; do echo "$r"; done | sort -u)
if [ -z "$_lbr" ]; then
	report "tools/defs.bzl has no _LIB_RUNNERS list this check can read" \
		"c_levels()' audit reads it to tell a runner that says why a raised test" \
		"sits above its layer from one that does not. Keep it as one" \
		"\"//tools:<runner>.sh\", per line, between _LIB_RUNNERS = [ and ]."
elif [ "$_lbr" != "$_lbw" ]; then
	report "tools/defs.bzl's _LIB_RUNNERS is not the list of runners that source tools/runner_lib.sh" \
		"$(printf '%s\n' "$_lbr" > "$lex_d/lbr"; printf '%s\n' "$_lbw" > "$lex_d/lbw"
			comm -23 "$lex_d/lbr" "$lex_d/lbw" | sed 's|^|    listed, and sources nothing: tools/|'
			comm -13 "$lex_d/lbr" "$lex_d/lbw" | sed 's|^|    sources the library, not listed: tools/|')" \
		"The audit lets a test _RAISED lists run only on a runner of this list," \
		"since rl__raised (tools/runner_lib.sh) is what prints, under its red, why" \
		"it sits above its layer. Make the list the scripts in tools/ whose line" \
		"'. \"\$RL_LIB\"' sources the library."
fi

# ---------------------------------------------------------------------------
# N. A runner cuts captured output with rl_excerpt, which says what it dropped.
#
# `sed 's/^/  /' "$ERR" | head -10` was the only form in the runners, and it
# never said how much it dropped: a build failure's explanation was cut under
# unrelated hints, and nobody could tell (finding 165). rl_excerpt FILE N NAME
# prints N lines, then "K more line(s), full text in test.outputs/NAME", and
# keeps the whole file there.
#
# Checked in every runner (above), for every way to keep the start of a
# stream: head -N, -n N, -c N; tail -n N; sed -n '1,Np' and sed Nq; awk
# 'NR<=N'. A cut is not an excerpt when what it keeps never reaches the log:
# taken into a variable ($( ) that is not echo's or printf's argument), written
# to a file, or piped into cmp, wc, read or grep -q. A cut that does reach the
# log and is not of output -- the header comment of a source file -- says so
# in a comment right above it:
#     # conventions: not-an-excerpt -- <why>
excerpt_bad=$(for f in $RUNNERS; do
	awk -v f="$f" '
		BEGIN {
			split("if then else elif do while until ! { } time", k, " ")
			for (i in k) kw[k[i]] = 1
		}
		FNR == NR { raw[FNR] = $0; next }
		function isredir(x) { return x ~ /^[0-9]*(<<?-?|>>?|<>|>\||[<>]&)/ }
		function bareop(x) { return x ~ /^[0-9]*(<<?-?|>>?|<>|>\|)$/ }
		function unq(x) { gsub(/^["\047]|["\047]$/, "", x); return x }
		# How much a count keeps: a number; 0 for +N (from line N on, not a
		# cut); -1 for one this scan cannot read, which counts as a cut.
		function num(x) {
			x = unq(x)
			if (x ~ /^[0-9]+$/) return x + 0
			if (x ~ /^\+/) return 0
			return -1
		}
		function kept(n) { return n >= 2 || n < 0 }
		# The cut v[1..m] makes, or "" when it makes none. One line (head -1)
		# is a value, not an excerpt.
		function cut_of(   i, x, hasn) {
			if (v[1] == "head" || v[1] == "tail") {
				for (i = 2; i <= m; i++) {
					x = v[i]
					if (x ~ /^-[0-9]+$/) return kept(substr(x, 2) + 0) ? x : ""
					if (x ~ /^-[nc]$/) return kept(num(v[i + 1])) ? x " " v[i + 1] : ""
					if (x ~ /^-[nc]./) return kept(num(substr(x, 3))) ? x : ""
					if (x ~ /^--(lines|bytes)=/) return kept(num(substr(x, index(x, "=") + 1))) ? x : ""
				}
				return (v[1] == "head") ? "head" : ""
			}
			if (v[1] == "sed") {
				hasn = 0
				for (i = 2; i <= m; i++) {
					x = unq(v[i])
					if (x == "-n") { hasn = 1; continue }
					if (hasn && x ~ /(^|[^0-9])1,[0-9]+p/) return v[i]
					if (x ~ /^[0-9]+q$/ && substr(x, 1, length(x) - 1) + 0 >= 2) return v[i]
				}
				return ""
			}
			if (v[1] == "awk") {
				for (i = 2; i <= m; i++) {
					x = v[i]
					if (x !~ /^\047/) continue
					if (x ~ /NR[ \t]*<=?[ \t]*[0-9]+/ || x ~ /NR[ \t]*>=?[ \t]*[0-9]+[ \t]*\{[ \t]*exit/)
						return "awk NR"
					return ""
				}
			}
			return ""
		}
		# The end of a pipeline that keeps what it reads from the log.
		function silent(   x) {
			if (v[1] == "cmp" || v[1] == "wc" || v[1] == "read" || v[1] == "test" || v[1] == "[") return 1
			if (v[1] == "grep") for (x = 2; x <= m; x++) if (v[x] ~ /^-[A-Za-z]*[qcl]/) return 1
			return 0
		}
		function say(l, c,   s) {
			s = raw[l]; sub(/^[ \t]+/, "", s)
			printf "    %s:%d: %s: %s\n", f, l, c, s
		}
		{
			split($0, r, "\t")
			ctx = r[2]; dep = r[5]; piped = (r[6] == "|")
			nw = split(r[4], w, "\037")
			for (q = 1; q <= nw; q++) { gsub(/\035/, "\t", w[q]); gsub(/\036/, "\n", w[q]) }
			m = 0; tofile = 0
			for (i = 1; i <= nw; i++) {
				if (isredir(w[i])) {
					x = w[i]
					if (bareop(x)) { i++; x = x w[i] }
					if (x ~ /^1?>>?[^&]/ && x !~ /\/dev\/(stdout|stderr)/) tofile = 1
					continue
				}
				m++; v[m] = w[i]
			}
			i = 1
			while (i <= m && ((v[i] in kw) || v[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++
			if (i > 1) { for (j = i; j <= m; j++) v[j - i + 1] = v[j]; m = m - i + 1 }
			# The rest of a pipeline a cut feeds: where it ends decides
			# whether the cut reaches the log.
			if (dep in pend) {
				if (tofile || (m >= 1 && silent())) delete pend[dep]
				else if (!piped) { say(pl[dep], pend[dep]); delete pend[dep] }
				if (dep in pend) next
			}
			if (m < 1 || tofile) next
			if (ctx ~ /^sub:/ && ctx != "sub:echo" && ctx != "sub:printf") next
			if (r[3] ~ /# conventions: not-an-excerpt --/) next
			c = cut_of()
			if (c == "") next
			if (piped) { pend[dep] = c; pl[dep] = r[1] }
			else say(r[1], c)
		}
		END { for (x in pend) say(pl[x], pend[x]) }' "$f" "$(cmds_of "$f")"
done)
[ -z "$excerpt_bad" ] || report \
	"a runner cuts captured output without saying how much it dropped" \
	"$excerpt_bad" \
	"Use rl_excerpt FILE N NAME [PREFIX] (tools/runner_lib.sh): N lines, then" \
	"'K more line(s), full text in test.outputs/NAME', with the whole file" \
	"kept there. A bare head reads as the whole story and is not."

# runner_scripts -- every shell script that can run or report on student
# code: tools/*.sh, the toolchain's wrappers, and each module's tests/*.sh,
# one per line. The rules on what a runner may do for itself read this list,
# so a rule written for tools/*.sh alone does not miss the script a module
# keeps beside its tests (the review of V50).
runner_scripts() {
	{
		for f in tools/*.sh tools/cc_toolchain/*.sh; do
			[ -f "$f" ] && echo "$f"
		done
		for _m in $MODULES; do
			[ -d "$_m/tests" ] && find "$_m/tests" -name '*.sh' 2> /dev/null
		done
	} | sort -u
}

# ---------------------------------------------------------------------------
# N. A sanitizer's options are set by rl_sanitizers, and by nothing else.
#
# Four runners set ASAN_OPTIONS and UBSAN_OPTIONS by hand, and they differed:
# two overwrote the caller's keys, and none named a symbolizer, so the
# sanitizer looked for an llvm-symbolizer on PATH -- a report that reads one
# way on one machine and another on the next -- and, finding none on this
# repo's own boxes, printed every frame as a bare offset into a binary in
# Bazel's cache (finding 051). rl_sanitizers (tools/runner_lib.sh) sets the
# keys once, the caller's last, and hands over the pinned llvm-symbolizer, or
# explicitly none; a symbolizer path set anywhere else would be the PATH
# search again in other clothes.
san_bad=$(runner_scripts | while IFS= read -r f; do
	case "$f" in tools/runner_lib.sh | tools/conventions.sh) continue ;; esac
	grep -nE '^[^#]*([A-Z]+SAN_OPTIONS=|ASAN_SYMBOLIZER_PATH|external_symbolizer_path)' "$f" |
		sed "s|^|    $f:|"
done)
[ -z "$san_bad" ] || report \
	"a runner sets a sanitizer's options by hand" \
	"$san_bad" \
	"Call rl_sanitizers DIR [SYMBOLIZER LIBFILE] (tools/runner_lib.sh) before the" \
	"instrumented runs: the harness's keys, the caller's last, and the pinned" \
	"symbolizer or none -- never one a PATH search finds."

# ---------------------------------------------------------------------------
# N. A sanitizer's report is recognised by tools/runner_lib.sh's rl_sanitized.
#
# asan_run.sh, argv_table.sh and rl_mem_run each grepped the run's stderr for
# the sanitizers' banners, with two lists of them, and rust_diff.sh's replay
# did not look: its header then said how the run ended in SIGABRT's words --
# an assertion, stack smashing or a glibc heap error -- above the sanitizer's
# own report, since abort_on_error=1 ends every finding with SIGABRT (V50).
# rl_sanitized FILE is the one test, and words the ending when the report is
# there. So, outside comments, a pattern naming a sanitizer's banner -- a
# grep, awk or sed line holding "Sanitizer" or "runtime error:", or such a
# word beside a | of an alternation -- is reported.
sanrep_bad=$(runner_scripts | while IFS= read -r f; do
	case "$f" in tools/runner_lib.sh | tools/conventions.sh) continue ;; esac
	awk -v f="$f" '
		/^[ \t]*#/ { next }
		/(grep|awk|sed)[^#]*(Sanitizer|runtime error:)/ || /Sanitizer\|/ || /\|[A-Za-z]*Sanitizer/ {
			l = $0; sub(/^[ \t]+/, "", l)
			printf "    %s:%d: %s\n", f, FNR, l
		}' "$f"
done)
[ -z "$sanrep_bad" ] || report \
	"a runner looks for a sanitizer's report itself" \
	"$sanrep_bad" \
	"Call rl_sanitized FILE (tools/runner_lib.sh) on the run's stderr: true when" \
	"a report is there, and after rl_classify it says in RL_WHY that the" \
	"sanitizer stopped the run, where SIGABRT's own words named every cause" \
	"but that one."

# ---------------------------------------------------------------------------
# N. A runner that sets the sanitizers up asks rl_sanitized how its run ended.
#
# The rule above finds a runner that looks for a report itself. The other
# form of the same fault is a runner that never looks: rust_diff.sh's replay
# called rl_sanitizers and never asked, so its header said how the run ended
# in SIGABRT's words above the sanitizer's own report (V50), and asan_check.sh
# called every ending but OK an out-of-bounds access, its probe's own return
# status included (V70). So, outside comments, a script that calls
# rl_sanitizers also calls rl_sanitized, or rl_mem_run, which asks it. A
# script that runs an instrumented build only to learn whether it passed,
# and shows nothing of how it ended, says so on a line of its own:
#
#     # conventions: shows no sanitizer report -- <why>
sanask_bad=$(runner_scripts | while IFS= read -r f; do
	case "$f" in tools/runner_lib.sh | tools/conventions.sh) continue ;; esac
	awk -v f="$f" '
		/^[ \t]*#[ \t]*conventions: shows no sanitizer report --/ { exempt = 1 }
		/^[ \t]*#/ { next }
		!at && /(^|[^A-Za-z0-9_])rl_sanitizers([^A-Za-z0-9_]|$)/ { at = FNR; l = $0 }
		/(^|[^A-Za-z0-9_])(rl_sanitized|rl_mem_run)([^A-Za-z0-9_]|$)/ { asks = 1 }
		END {
			if (at && !asks && !exempt) {
				sub(/^[ \t]+/, "", l)
				printf "    %s:%d: %s\n", f, at, l
			}
		}' "$f"
done)
[ -z "$sanask_bad" ] || report \
	"a runner sets the sanitizers up and never asks how its run ended" \
	"$sanask_bad" \
	"After rl_classify, call rl_sanitized FILE (tools/runner_lib.sh) on the" \
	"run's stderr: a report there is the sanitizer's finding, and RL_WHY then" \
	"says it stopped the run; no report is some other ending, to be said as" \
	"that. A run read only for whether it passed says so on a line of its own:" \
	"# conventions: shows no sanitizer report -- <why>."

# ---------------------------------------------------------------------------
# N. A runner that symbolises a sanitizer's report is in _SYMBOLIZER_RUNNERS.
#
# Without a symbolizer rl_sanitizers sets symbolize=0, and every frame of the
# report is a bare offset into a binary in Bazel's cache (finding 051). Each
# macro used to add _symbolizer_args() by hand, so one that forgot was that
# finding again, silently; tools/defs.bzl's _test() now refuses, while
# loading, a test of a runner in _SYMBOLIZER_RUNNERS whose args hand it none
# (symbolizer_problem). That holds only for the runners listed there, so: a
# runner that hands rl_sanitizers a symbolizer is listed, and a listed runner
# hands it one. A corpus runner hands it one through rl_mem_ready, which
# passes rl_sanitizers the --symbolizer its rl_mem_opt took: the five
# corpus runners' --sanitized twins were left out of the table, and their
# reports unsymbolised, because none of them called rl_sanitizers itself.
_sym_rows=$(sed -n '/^_SYMBOLIZER_RUNNERS = {$/,/^}$/p' tools/defs.bzl 2>/dev/null |
	sed -n 's#^[[:blank:]]*"//tools:\([a-z0-9_]*\.sh\)": .*#\1#p')
for f in tools/*.sh; do
	case "$f" in tools/runner_lib.sh | tools/conventions.sh) continue ;; esac
	if grep -v '^[[:blank:]]*#' "$f" |
		grep -qE 'rl_sanitizers[[:blank:]]+[^[:blank:]]+[[:blank:]]+[^[:blank:]]|(^|[^_A-Za-z0-9])rl_mem_ready([[:blank:]]|$)'; then
		printf '%s\n' "$_sym_rows" | grep -qx "${f#tools/}" || report \
			"$f symbolises a sanitizer's report and is not in tools/defs.bzl's _SYMBOLIZER_RUNNERS" \
			"_test() refuses a test that hands a listed runner no --symbolizer, so a" \
			"macro that forgets _symbolizer_args() is caught while loading. List it," \
			"with the flag that makes it show a report (None: every run does)."
	elif printf '%s\n' "$_sym_rows" | grep -qx "${f#tools/}"; then
		report "tools/defs.bzl's _SYMBOLIZER_RUNNERS lists $f, which hands rl_sanitizers no symbolizer" \
			"A row for a runner that never symbolises makes _test() demand args it" \
			"ignores. Remove the row, or pass the symbolizer to rl_sanitizers."
	fi
done

# ---------------------------------------------------------------------------
# N. A runner that compiles is in _PINNED_CC_RUNNERS, and one that links
# proves its linker.
#
# tools/defs.bzl's _test() refuses, while loading, a test of a runner in
# _PINNED_CC_RUNNERS whose args hand it no --cc where it compiles, or no --ld
# where it links (pinned_cc_problem). It caught c_function's symbols test,
# handed the pinned nm and no compiler, the day it was written -- and holds
# only for the runners listed. So: a runner that takes --cc is listed, and a
# listed one takes it; one that proves a linker with rl_ld_pin is listed as
# linking, and one listed as linking proves it. asan_check.sh and
# allocfail_check.sh took clang-12 and cc from PATH, and four runners linked
# with the box's /usr/bin/ld, before either half existed (TO VERIFY V38).
#
# The table is read as Starlark lays it out, not as one line a row: a row
# reflowed by buildifier, or a tuple split over lines, is still a row. A key
# whose value is no pair of strings, a row for a runner that is not in
# tools/, and a table of no rows at all are each reported: a reader that
# matched nothing would report nothing, in the very rule meant to catch a
# runner left out (review of W7-V38).

# pcc_takes FILE -- whether FILE takes --cc: a case pattern naming it, on a
# line that is no comment. One test for both rules below, so a runner one of
# them counts as taking the pinned compiler is one the other does too.
pcc_takes() {
	grep -v '^[[:blank:]]*#' "$1" | grep -qE '(^|[[:blank:];(|])--cc[|)]'
}
# _pcc_table: one line a row, "RUNNER COMPILES LINKS" ("RUNNER ? ?" for a
# value that is no pair of strings), or "none" without a table.
_pcc_table=$(awk '
	!on && /^_PINNED_CC_RUNNERS[[:blank:]]*=[[:blank:]]*\{/ { on = 1 }
	on {
		l = $0; sub(/#.*/, "", l); t = t " " l
		o = gsub(/\{/, "{", l); c = gsub(/\}/, "}", l); depth += o - c
		if (depth <= 0) exit
	}
	END {
		if (!on) { print "none"; exit }
		while (match(t, /"\/\/tools:[^"]*"/)) {
			k = substr(t, RSTART + 9, RLENGTH - 10)
			t = substr(t, RSTART + RLENGTH)
			if (match(t, /^[[:blank:]]*:[[:blank:]]*\([[:blank:]]*"[^"]*"[[:blank:]]*,[[:blank:]]*"[^"]*"[[:blank:]]*,?[[:blank:]]*\)/)) {
				split(substr(t, RSTART, RLENGTH), q, "\"")
				t = substr(t, RSTART + RLENGTH)
				print k, q[2], q[4]
			} else
				print k, "?", "?"
		}
	}' tools/defs.bzl 2> /dev/null)
_pcc_rows=""
if [ -f tools/defs.bzl ] && [ "$_pcc_table" != none ]; then
	[ -n "$_pcc_table" ] || report "tools/defs.bzl's _PINNED_CC_RUNNERS has no row this could read" \
		"Every rule that holds the table to the runners would then pass in silence." \
		"Keep each row a \"//tools:NAME.sh\": (\"COMPILES\", \"LINKS\") entry."
	_pcc_bad=$(printf '%s\n' "$_pcc_table" | awk 'NF && ($2 == "?" || $1 !~ /^[a-z0-9_]+\.sh$/) { print "    " $1 }')
	[ -z "$_pcc_bad" ] || report "a row of tools/defs.bzl's _PINNED_CC_RUNNERS could not be read" \
		"$_pcc_bad" \
		"Each value is a pair of strings, (\"COMPILES\", \"LINKS\"), each \"always\"," \
		"\"never\" or the flag that makes the runner do it; each key a //tools:*.sh."
	_pcc_gone=$(printf '%s\n' "$_pcc_table" | while read -r _r _c _l; do
		[ -n "$_r" ] && [ ! -f "tools/$_r" ] && printf '    //tools:%s\n' "$_r"
	done)
	[ -z "$_pcc_gone" ] || report "tools/defs.bzl's _PINNED_CC_RUNNERS lists a runner that is not in tools/" \
		"$_pcc_gone" \
		"A row for a runner renamed or removed holds nothing to the table. Remove" \
		"it, or rename it with its runner."
	_pcc_rows=$(printf '%s\n' "$_pcc_table" | awk 'NF && $2 != "?" { print $1, $3 }')
fi
for f in tools/*.sh; do
	# student_build.sh is no test's runner: it is the script of a BUILD
	# action, which tools/student_build.bzl hands the C toolchain's own
	# compiler and linker (//tools/cc_toolchain), command lines and all.
	case "$f" in tools/runner_lib.sh | tools/conventions.sh | tools/student_build.sh) continue ;; esac
	_pr=$(printf '%s\n' "$_pcc_rows" | awk -v r="${f#tools/}" '$1 == r { print $2 }')
	if pcc_takes "$f"; then
		[ -n "$_pr" ] || report \
			"$f takes --cc and is not in tools/defs.bzl's _PINNED_CC_RUNNERS" \
			"_test() refuses a test that hands a listed runner no --cc (or no --ld" \
			"where it links), so a macro that forgets _pinned_cc_args() is caught" \
			"while loading. List it, with when it compiles and when it links."
	elif [ -n "$_pr" ]; then
		report "tools/defs.bzl's _PINNED_CC_RUNNERS lists $f, which takes no --cc" \
			"A row for a runner that compiles nothing makes _test() demand args it" \
			"ignores. Remove the row, or take the pinned compiler with --cc."
	fi
	# A listed runner's tests are handed the pinned compiler, so a comment of
	# it saying the compiler is not pinned is out of date: symbols_test.sh's
	# and forbidden_symbols.sh's said so, and why, for a day after both were
	# listed (review of W7-V38).
	if [ -n "$_pr" ]; then
		_np=$(grep -niE '^[[:blank:]]*#.*not[[:blank:]]+(be[[:blank:]]+)?pinned' "$f" | sed "s|^|    $f:|")
		[ -z "$_np" ] || report "$f is in _PINNED_CC_RUNNERS, and a comment of it says it is not pinned" \
			"$_np" \
			"Every test of it is handed the pinned compiler (pinned_cc_problem refuses" \
			"one that is not). Say so, and that its *_CC default is for a hand run."
	fi
	_lp=0
	grep -v '^[[:blank:]]*#' "$f" | grep -qE '(^|[^_A-Za-z0-9])rl_ld_pin[[:blank:]]' && _lp=1
	if [ "$_lp" = 1 ] && { [ -z "$_pr" ] || [ "$_pr" = never ]; }; then
		report "$f proves a linker with rl_ld_pin, and _PINNED_CC_RUNNERS does not say it links" \
			"_test() asks a test for --ld only where the table says the runner links."
	elif [ "$_lp" = 0 ] && [ -n "$_pr" ] && [ "$_pr" != never ]; then
		report "tools/defs.bzl's _PINNED_CC_RUNNERS says $f links, and it never calls rl_ld_pin" \
			"A link by the pinned clang runs whatever ld it finds unless it is handed" \
			"one: the clang package has none, so that is the box's /usr/bin/ld. Take" \
			"--ld and --ld-lib, call rl_ld_pin (tools/runner_lib.sh) before the first" \
			"link, and put \"\$RL_LDFLAG\" on every compiler command."
	fi
done

# ---------------------------------------------------------------------------
# N. A runner that proves a linker hands it to every compiler command.
#
# rl_ld_pin proves the pinned ld.bfd and sets RL_LDFLAG (-BDIR/), and a link
# runs it only when the command carries that flag: one written without it
# runs the box's /usr/bin/ld while the runner still reports itself pinned,
# and pinned_cc_problem's --ld audit proves only that the flag was handed
# over, never that it was used. header_check.sh and method_check.sh carried
# it on their link line alone (review of W7-V38). runner_lib.sh's contract
# is every command, compile or link, so that nobody has to know which of
# them link; a file that calls rl_ld_pin is held to it here. Each command
# that runs the compiler it handed rl_ld_pin -- at the start of a line or
# after ; & | ( ! or a keyword, a command continued with \ read whole --
# carries RL_LDFLAG, itself or through a list built with it (rl_list_add
# NAME "$RL_LDFLAG" ...).
_ldf=$(for f in tools/*.sh; do
	case "$f" in tools/runner_lib.sh | tools/conventions.sh) continue ;; esac
	awk -v f="$f" '
		NR == FNR {
			if ($0 ~ /^[[:blank:]]*#/) next
			if (match($0, /(^|[^A-Za-z0-9_])rl_ld_pin[[:blank:]]+"?\$\{?[A-Za-z_][A-Za-z0-9_]*/)) {
				v = substr($0, RSTART, RLENGTH); sub(/.*\$\{?/, "", v); cc[v] = 1
			}
			if (match($0, /(^|[^A-Za-z0-9_])rl_list_add[[:blank:]]+[A-Za-z_][A-Za-z0-9_]*[[:blank:]].*RL_LDFLAG/)) {
				v = substr($0, RSTART, RLENGTH); sub(/.*rl_list_add[[:blank:]]+/, "", v)
				sub(/[[:blank:]].*/, "", v); lst[v] = 1
			}
			next
		}
		{
			if (cont == "") {
				if ($0 ~ /^[[:blank:]]*#/) next
				at = FNR; text = $0
			}
			l = $0
			if (l ~ /\\$/) { cont = cont substr(l, 1, length(l) - 1) " "; next }
			l = cont l; cont = ""
			sub(/[[:blank:]]#.*$/, "", l)
			gsub(/\047[^\047]*\047/, "", l)
			for (v in cc) {
				pat = "(^|[;&|(!]|(^|[^A-Za-z0-9_])(if|then|do|else|elif|while|until))[[:blank:]]*\"?\\$\\{?" v "\\}?\"?([[:blank:]]|$)"
				if (l !~ pat) continue
				ok = (l ~ /RL_LDFLAG/)
				for (n in lst)
					if (index(l, "$" n) || index(l, "${" n "}")) ok = 1
				if (!ok) printf "    %s:%d: %s\n", f, at, text
				break
			}
		}' "$f" "$f"
done)
[ -z "$_ldf" ] || report "a runner that proves a linker runs its compiler without it" \
	"$_ldf" \
	"Put \"\$RL_LDFLAG\" on the command (\${RL_LDFLAG:+\"\$RL_LDFLAG\"} where a mode of the" \
	"runner links nothing and leaves it empty): a link without it runs this" \
	"machine's /usr/bin/ld. A compile ignores the flag, so every command takes it."

# ---------------------------------------------------------------------------
# N. No runner compiles with a compiler from PATH.
#
# cycles_check.sh and ref_compare.sh built their -O2 binaries with `cc`, the
# box's compiler (clang-12 on the box they were written on and on campus, but
# whatever answers to `cc` anywhere else), and a box with none SKIPped them
# (TO VERIFY V38's class). A compiler a runner runs by name has to be
# declared -- in `require`, or as `# conventions: optional cc` -- by the rule
# that computes what a script takes from PATH, so that declaration is read
# here: a tools/*.sh that names a compiler there is reported, unless its
# optional line says the name is reached by hand only, never by a test Bazel
# runs (ilp32_test.sh's -m32 fallback without --zig; a maintainer's script
# run inside the image).
#
# And the shape the asan and allocfail defects actually had: a compiler held
# in a variable that defaults to one on the box, CC="${SOMETHING_CC:-cc}" --
# which no declaration above sees, since "$CC" is not a name. The selftests
# built every fixture so too, and a box with no `cc` skipped them whole,
# green, having checked nothing (TO VERIFY V28). A variable named CC (or
# ending in _CC) set from such a default, or any variable defaulting to a
# compiler's name, is reported in every tools/*.sh and tools/tests/*.sh that
# takes no --cc, unless an optional line names that compiler as by hand
# only. A runner that takes --cc is in _PINNED_CC_RUNNERS (the rule above),
# where tools/defs.bzl refuses a test that does not hand it one, so its
# default is the hand-run one. Naming the compiler in the no-Docker docs
# excuses nothing: a rule that took that as the remedy (review of WP-85)
# let exactly such a runner through, because `cc` is named there for the
# Makefile layers (review of W7-V38).
_pcc_names="cc|gcc|clang|gcc-[0-9]+|clang-[0-9]+"
_pcc_box=$(for f in tools/*.sh tools/tests/*.sh; do
	[ -f "$f" ] || continue
	case "$f" in tools/runner_lib.sh | tools/conventions.sh) continue ;; esac
	grep -m1 '^require ' "$f" | tr ' ' '\n' | grep -qxE "$_pcc_names" &&
		printf '    %s: requires a compiler from PATH\n' "$f"
	grep -nE "^# conventions: optional ($_pcc_names) " "$f" |
		grep -v -- ' -- by hand only' | sed "s|^\([0-9]*\):|    $f:\1: |"
	pcc_takes "$f" && continue
	awk -v f="$f" -v names="^($_pcc_names)\$" '
		/^# conventions: optional [^ ]+ -- by hand only/ { hand[$4] = 1 }
		/^[[:blank:]]*#/ { next }
		match($0, /^[[:blank:]]*((export|readonly|local)[[:blank:]]+)?([A-Za-z_][A-Za-z0-9_]*=|:[[:blank:]]+)?"?\$\{[A-Za-z_][A-Za-z0-9_]*:?[-=][A-Za-z0-9.+_-]+\}/) {
			m = substr($0, RSTART, RLENGTH)
			v = m; sub(/^[[:blank:]]*((export|readonly|local)[[:blank:]]+)?/, "", v)
			lhs = ""
			if (match(v, /^[A-Za-z_][A-Za-z0-9_]*=/)) lhs = substr(v, 1, RLENGTH - 1)
			in_ = m; sub(/.*\$\{/, "", in_)
			var = in_; sub(/:?[-=].*/, "", var)
			def = in_; sub(/^[A-Za-z_][A-Za-z0-9_]*:?[-=]/, "", def); sub(/\}$/, "", def)
			if (lhs ~ /(^|_)CC$/ || var ~ /(^|_)CC$/ || def ~ names) {
				n++; at[n] = FNR; nm[n] = def; tx[n] = $0
			}
		}
		END {
			for (i = 1; i <= n; i++)
				if (!(nm[i] in hand)) printf "    %s:%d: %s\n", f, at[i], tx[i]
		}' "$f"
done)
[ -z "$_pcc_box" ] || report "a runner compiles with a compiler from PATH" \
	"$_pcc_box" \
	"Take the pinned clang-12 (--cc, --cc-lib, --cc-under) and, where it links," \
	"the pinned ld.bfd (--ld, --ld-lib), proved by rl_cc_pin and rl_ld_pin" \
	"(tools/runner_lib.sh), and list the runner in _PINNED_CC_RUNNERS. A name" \
	"reached by hand only says so: \"# conventions: optional cc -- by hand only: ...\"."

# ---------------------------------------------------------------------------
# N. Bytes are rendered by tools/runner_lib.sh, and by nothing else.
#
# A table, an argument line and an excerpt each show captured bytes, and there
# were six ways of doing it: ^X in the output table, \xHH in rl_vis and in
# rl_excerpt, a '?' in shell_check's excerpt, "\?" in rush01_check.sh, and
# sed's octal `l` in progname_test.sh. One byte read differently in each
# layer's log, and an expected line ending in a literal $ read as one that
# ended there. RL_AWK_VIS is the one renderer -- rl_vis and rl_excerpt use it,
# and an awk program of a runner's own starts with it and calls rl_vis_exact
# or rl_vis_text. What makes a renderer of one's own is what it writes, so
# that is what this looks for, outside comments: a \x before a formatted hex
# byte, a caret before a byte plus 64, a class of control bytes replaced by
# something, and sed's `l` command.
render_bad=$(
	runner_scripts | while IFS= read -r f; do
		case "$f" in tools/runner_lib.sh | tools/conventions.sh) continue ;; esac
		awk -v f="$f" '
			/^[ \t]*#/ { next }
			/\\+x%0?2[xX]/ || /%c"[^)]*\+[ \t]*64/ ||
			/(g?sub\(|tr |sed )[^#]*(\[\[:cntrl:\]\]|\[\\0?01-)/ ||
			/sed( +-[A-Za-z]+)* +\047?[0-9,$]*l\047?([ ;|)]|$)/ {
				l = $0; sub(/^[ \t]+/, "", l)
				printf "    %s:%d: %s\n", f, FNR, l
			}' "$f"
	done
)
[ -z "$render_bad" ] || report \
	"a script renders bytes with an escape of its own" \
	"$render_bad" \
	"Render them with tools/runner_lib.sh: rl_vis MODE for a stream, rl_excerpt" \
	"for captured text, and in an awk program of your own, start it with" \
	"\"\$RL_AWK_VIS\" and call rl_vis_exact (bytes that are compared) or" \
	"rl_vis_text (text that is read). One renderer, so a byte reads the same" \
	"in every layer's log."

# ---------------------------------------------------------------------------
# N. A legend of the renderer's marks is read off what is shown.
#
# The rule above keeps one renderer; the key to its marks was still written
# by hand. bsq_check.sh, argv_check.sh and rush02_check.sh each printed a
# legend fixed once -- "\t a tab, \\ a backslash, \x24 a dollar sign" --
# under want and got lines that held none of these, and a reader looked for
# the tab the key promised (wave 5's review). tools/runner_lib.sh names the
# marks a shown text holds: rl_vis_legend over a file of it, rl_shown_legend
# over the lines of the blocks a report printed. So a line, outside comments,
# of a script other than the library that pairs a mark with what it stands
# for -- a backslash pair, \t, \n, \x24 or \xHH followed by "a backslash",
# "a tab", "a newline" or "a line break", "a dollar", "a byte" and the like
# -- is reported. A text that states the notation for another reader (an
# error telling a harness author what a test program must write) says so in
# the comment block right above its command, which then holds over the
# command's continuation lines:
#
#     # conventions: notation, not a legend -- <why>
legend_bad=$(
	runner_scripts | while IFS= read -r f; do
		case "$f" in tools/runner_lib.sh | tools/conventions.sh) continue ;; esac
		awk -v f="$f" '
			/^[ \t]*$/ { mark = 0; next }
			/^[ \t]*#/ {
				if (index($0, "# conventions: notation, not a legend -- ")) mark = 1
				next
			}
			{
				if (mark) { held = 1; mark = 0 }
				if (held) {
					if ($0 !~ /\\$/) held = 0
					next
				}
				t = tolower($0)
				if (t ~ /\\\\+[ \t]+(is[ \t]+)?(an?[ \t]+|one[ \t]+)?backslash/ ||
				    t ~ /\\+t,?[ \t]+(is[ \t]+)?an?[ \t]+tab/ ||
				    t ~ /\\+n,?[ \t]+(is[ \t]+)?(an?|the)[ \t]+(newline|line break)/ ||
				    t ~ /\\+x24,?[ \t]+(is[ \t]+)?an?[ \t]+dollar/ ||
				    t ~ /\\+xhh,?[ \t]+(is[ \t]+)?(an?|one|any)[ \t]+([a-z]+[ \t]+)?byte/) {
					l = $0; sub(/^[ \t]+/, "", l)
					printf "    %s:%d: %s\n", f, FNR, l
				}
			}' "$f"
	done
)
[ -z "$legend_bad" ] || report \
	"a script prints a legend of the renderer's marks as fixed text" \
	"$legend_bad" \
	"Name the marks from the text shown: rl_vis_legend FILE over the rendered" \
	"lines, or rl_shown_legend ERE over the blocks rl_block printed, the ERE" \
	"naming the labels the rendered bytes follow (tools/runner_lib.sh). A" \
	"legend fixed once names a tab or a backslash under lines that hold none." \
	"A text stating the notation for a harness author says so above its" \
	"command: '# conventions: notation, not a legend -- <why>'."

# ---------------------------------------------------------------------------
# N. Where two outputs part is found and shown by tools/runner_lib.sh alone.
#
# The rule above reads what a renderer WRITES, and od writes its own escapes
# without any of them appearing in the script: after the wave 4 merges,
# file_check.sh showed the bytes around a first difference with `od -c`
# (octal, "351" for 0xe9), diff_output.sh's byte-stream summary with
# `od -tx1` after a `cmp -l` of its own, and oracle_fixtures.sh read the
# byte out of cmp's sentence -- three ways of finding it and three of showing
# it, beside rl_first_diff, which two runners already used. So, outside
# comments: od given a character format (-c, -a, -t c, -t a), which is a
# rendering; od given a skip (-j), which cuts a window out of a file; and cmp
# whose report is read (-l, -b, or piped on without -s), which finds the
# byte. od reading a few bytes from a file's start into a comparison (a
# magic number, a last byte) is none of these.
diffwin_bad=$(
	runner_scripts | while IFS= read -r f; do
		case "$f" in tools/runner_lib.sh | tools/conventions.sh) continue ;; esac
		awk -v f="$f" '
			# The words of the command that starts at the head of s: up to
			# a pipe, a ; or & or a closing ), into w[1..n]; the rest of
			# the line, from that pipe on, in tail.
			function cmdwords(s,   e) {
				e = match(s, /[|;&)]/)
				tail = e ? substr(s, e) : ""
				return split(e ? substr(s, 1, e - 1) : s, w, /[ \t]+/)
			}
			/^[ \t]*#/ { next }
			{
				bad = 0
				l = $0
				while (match(l, /(^|[^A-Za-z0-9_.\/-])od[ \t]/)) {
					l = substr(l, RSTART + RLENGTH)
					n = cmdwords(l)
					for (i = 1; i <= n; i++) {
						# -A, -N, -w and -S carry their value (-An): not flags.
						if (w[i] ~ /^-[ANwS]/) continue
						if (w[i] ~ /^-t/) {
							t = (w[i] == "-t") ? w[i + 1] : substr(w[i], 3)
							if (t ~ /^[ac]/) bad = 1
							continue
						}
						if (w[i] ~ /^--(skip-bytes|format=[ac])/) bad = 1
						else if (w[i] ~ /^-[A-Za-z]*[acj]/) bad = 1
					}
				}
				l = $0
				while (match(l, /(^|[^A-Za-z0-9_.\/-])cmp[ \t]/)) {
					l = substr(l, RSTART + RLENGTH)
					n = cmdwords(l)
					quiet = 0
					for (i = 1; i <= n; i++) {
						if (w[i] ~ /^-[A-Za-z]*[lb]/ || w[i] ~ /^--(verbose|print-bytes)/) bad = 1
						if (w[i] ~ /^-[A-Za-z]*s/ || w[i] ~ /^--(quiet|silent)/) quiet = 1
					}
					if (!quiet && tail ~ /^\|/) bad = 1
				}
				if (bad) {
					l = $0; sub(/^[ \t]+/, "", l)
					printf "    %s:%d: %s\n", f, FNR, l
				}
			}' "$f"
	done
)
[ -z "$diffwin_bad" ] || report \
	"a script finds or shows where two outputs part by itself" \
	"$diffwin_bad" \
	"Use tools/runner_lib.sh: rl_first_diff WANT GOT for the byte where they" \
	"part, and rl_diff_window WANT GOT INDENT to show it -- the byte, each side" \
	"from just before it in rl_vis's rendering, and a ^ under it. One way to" \
	"find it and one to show it, so a byte reads the same in every layer's log."

# ---------------------------------------------------------------------------
# N. A diff a log shows is made and shown by tools/runner_lib.sh's rl_udiff.
#
# The rules above read what a script writes itself; a diff writes the
# student's bytes as they are. progname_test.sh's `diff -a -u` put a NUL its
# program printed in test.log raw (`file` called the log "data", grep a
# binary file), and shell_test.sh's `diff -u` showed a carriage return or a
# trailing space in a turn-in exactly as it showed the expected line -- and a
# NUL as "Binary files X and Y differ", naming two scratch files (V51). So,
# outside comments, a diff run where a command starts -- `diff`, or the pinned
# one a runner is handed as $DIFF -- is reported, unless it only answers
# whether two files differ (-q, --brief, or its output sent to /dev/null).
# `git diff` is git's, and a word "diff" that is an argument is no command.
udiff_bad=$(
	runner_scripts | while IFS= read -r f; do
		case "$f" in tools/runner_lib.sh | tools/conventions.sh) continue ;; esac
		awk -v f="$f" '
			# d[i]ff: the word spelled out after a | reads as a call of it
			# to the require scanner of this very file.
			/^[ \t]*#/ { next }
			{
				l = $0
				while (match(l, /(^[ \t]*|[;|&(][ \t]*|(^|[ \t])(if|then|else|do|while|until|!)[ \t]+)("\$\{?DIFF\}?"|\$\{?DIFF\}?|d[i]ff)[ \t]/)) {
					seg = substr(l, RSTART + RLENGTH)
					l = seg
					e = match(seg, /[;|&)]/)
					if (e) seg = substr(seg, 1, e - 1)
					if (seg ~ /(^|[ \t])(-[A-Za-z]*q[A-Za-z]*|--brief|--quiet)([ \t]|$)/) continue
					if (seg ~ /(^|[^0-9])1?>[ \t]*\/dev\/null/) continue
					s = $0; sub(/^[ \t]+/, "", s)
					printf "    %s:%d: %s\n", f, FNR, s
					break
				}
			}' "$f"
	done
)
[ -z "$udiff_bad" ] || report \
	"a script shows a diff that it did not make with rl_udiff" \
	"$udiff_bad" \
	"Use tools/runner_lib.sh: rl_udiff \"\$DIFF\" WANT GOT [WANT_LABEL GOT_LABEL]" \
	"runs the pinned diff with -a and shows every line through the one" \
	"renderer, each end marked with \$, and a legend of the marks shown. A" \
	"diff printed raw puts a NUL in the log and hides a trailing space or a" \
	"carriage return; for whether two files differ, cmp -s says it alone."

# ---------------------------------------------------------------------------
# N. A grep or sed pattern spells a blank [[:blank:]], never [ \t].
#
# Inside a bracket expression POSIX reads \t as two characters, a backslash
# and a t, and so does GNU grep, the one on campus and in every test here:
# `grep '^[ \t]*#'` skips a comment indented with spaces, keeps one indented
# with a tab, and skips any line that starts with a t. GNU sed reads it as a
# tab, other seds do not, and neither does a grep that other tools stand in
# for (ugrep reads a tab), so a pattern tried in one shell can hold there and
# miss every tab under Bazel. Three sat in this file (wave 3's review). awk
# reads \t as a tab everywhere, and so does tr, so neither is concerned; a
# grep -P pattern is PCRE, where \t is a tab too. A command is read from the
# shell (sh_cmds), so a grep inside an awk program is not taken for one.
blank_bad=$(
	{
		for f in tools/*.sh tools/tests/*.sh tools/cc_toolchain/*.sh; do
			[ -f "$f" ] && echo "$f"
		done
		for _m in $MODULES; do
			[ -d "$_m/tests" ] && find "$_m/tests" -name '*.sh' 2> /dev/null
		done
	} | sort -u | while IFS= read -r f; do
		awk -v f="$f" '
			BEGIN {
				split("if then else elif do while until ! { } time command exec", k, " ")
				for (i in k) kw[k[i]] = 1
			}
			FNR == NR { raw[FNR] = $0; next }
			{
				split($0, r, "\t")
				nw = split(r[4], w, "\037")
				i = 1
				while (i <= nw && ((w[i] in kw) || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++
				if (i > nw) next
				c = w[i]; sub(/.*\//, "", c)
				if (c != "grep" && c != "egrep" && c != "fgrep" && c != "sed") next
				for (j = i + 1; j <= nw; j++) {
					if (w[j] ~ /^-[A-Za-z]*P/) next
					if (w[j] ~ /\[[^]]*\\t[^]]*\]/) {
						l = raw[r[1]]; sub(/^[ \t]+/, "", l)
						printf "    %s:%d: %s\n", f, r[1], l
						next
					}
				}
			}' "$f" "$(cmds_of "$f")"
	done
)
[ -z "$blank_bad" ] || report \
	"a grep or sed pattern writes a tab as \\t inside [ ]" \
	"$blank_bad" \
	"Write [[:blank:]] (a space or a tab) or [[:space:]]: inside a bracket" \
	"expression GNU grep reads \\t as a backslash and a t, so the pattern" \
	"misses every tab and matches every t -- and only GNU sed reads it as a tab."

# ---------------------------------------------------------------------------
# N. A clues.tsv is read by rl_clues, and by nothing else.
#
# Each runner used to carry its own clue printer, and they drifted:
# rush01_check.sh printed the file verbatim, '#' maintainer comments included,
# twenty lines deep (finding 149); rust_diff.sh and shell_test.sh printed whole
# rows, member labels and all; the output layer capped at CLUE_MODE and the
# others at a hard-coded three. The rule is one: '#' and blank lines are never
# printed, only the hint column is, at most CLUE_MODE (default 3), keyed to the
# failing cases where there are any -- rl_clues in tools/runner_lib.sh, or
# rl_legend for a diff_clues.txt legend, which is prose.
#
# The file a runner is handed comes in by an option arm, --clues) or any
# --...clue...) / --...hint...) one, and the variable that arm stores it in is
# followed wherever it goes, whatever it is called: an alias (X="$CLUES")
# carries it on. Reading it -- as an argument of any command, or a < redirect
# -- is reported; testing it ([ -f "$X" ]), naming it in a message, handing it
# to rl_clues or rl_legend, and forwarding it to another runner (--clues "$X")
# are not reading it. A script with such an arm must also print what it takes
# with rl_clues or rl_legend, or forward it: an arm that goes nowhere shows a
# student no hint at all. The older net stays beside it: a line that reads a
# variable named like a clue file (CLUE, HINT) with a text tool.
clue_bad=$(for f in tools/*.sh; do
	case "$f" in tools/runner_lib.sh | tools/conventions.sh) continue ;; esac
	awk -v f="$f" '
		/^[ \t]*#/ { next }
		/cluefile/ ||
		(/\$\{?[A-Z_]*(CLUE|HINT)[A-Z_]*\}?/ &&
		 /(^|[;&|(]|then |do )[ \t]*(cut|grep|sed|awk|cat|head|tail|while)[ \t]|<[ \t]*"?\$\{?[A-Z_]*(CLUE|HINT)/) {
			printf "    %s:%d: %s\n", f, FNR, $0
		}' "$f"
	awk -v f="$f" '
		BEGIN {
			split("if then else elif do while until ! { } time", k, " ")
			for (i in k) kw[k[i]] = 1
			split("[ test rl_clues rl_legend echo printf set export local readonly", k, " ")
			for (i in k) allowed[k[i]] = 1
		}
		function refs(x, v) { return x ~ ("\\$\\{?" v "([^A-Za-z0-9_]|$)") }
		# First pass, the script: the option arms that take a clue file, and
		# the variable each keeps it in.
		FNR == NR {
			raw[FNR] = $0
			if (match($0, /^[ \t]*--[a-z-]*(clue|hint)[a-z-]*\)/)) {
				opt = substr($0, RSTART, RLENGTH)
				sub(/^[ \t]*/, "", opt); sub(/\)$/, "", opt)
				opts[opt] = FNR
				s = $0
				while (match(s, /[A-Za-z_][A-Za-z0-9_]*=("\$\{?2\}?"|\$\{?2\}?|\$\([a-z_]+ "\$2"\))([ \t;]|$)/)) {
					x = substr(s, RSTART, RLENGTH); sub(/=.*/, "", x)
					var[x] = 1
					s = substr(s, RSTART + RLENGTH)
				}
			}
			next
		}
		{
			split($0, r, "\t")
			nw = split(r[4], w, "\037")
			for (q = 1; q <= nw; q++) { gsub(/\035/, "\t", w[q]); gsub(/\036/, "\n", w[q]) }
			i = 1
			while (i <= nw && (w[i] in kw)) i++
			if (i > nw) next
			if (w[i] == "rl_clues" || w[i] == "rl_legend") used = 1
			if (w[i] != "echo" && w[i] != "printf")
				for (j = i; j <= nw; j++) for (o in opts) if (index(w[j], o)) fwd = 1
			# Only assignments: an alias of the file carries it on.
			allasg = 1
			for (j = i; j <= nw; j++) if (w[j] !~ /^[A-Za-z_][A-Za-z0-9_]*=/) allasg = 0
			if (allasg) {
				for (j = i; j <= nw; j++) {
					n = w[j]; sub(/=.*/, "", n)
					val = substr(w[j], length(n) + 2)
					for (x in var) if (val ~ ("^\"?\\$\\{?" x "\\}?\"?$")) alias[n] = 1
				}
				for (n in alias) var[n] = 1
				next
			}
			while (i <= nw && w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) i++
			if (i > nw) next
			for (j = i + 1; j <= nw; j++) for (x in var) {
				if (!refs(w[j], x)) continue
				redir = (w[j] ~ /^[0-9]*</ || w[j - 1] ~ /^[0-9]*<$/)
				if ((w[i] in allowed) && !redir) continue
				if (w[j - 1] ~ /^--/) continue
				s = raw[r[1]]; sub(/^[ \t]+/, "", s)
				printf "    %s:%d: reads the clue file ($%s) itself: %s\n", f, r[1], x, s
			}
		}
		END {
			for (o in opts) if (!used && !fwd)
				printf "    %s:%d: takes %s, and neither prints it with rl_clues or rl_legend nor forwards it\n", f, opts[o], o
		}' "$f" "$(cmds_of "$f")"
done)
[ -z "$clue_bad" ] || report \
	"a runner reads clues.tsv with its own rule" \
	"$clue_bad" \
	"Print hints with rl_clues FILE [FAILED [FIRST [CASE [LAYER]]]]" \
	"(tools/runner_lib.sh), or rl_legend FILE for a diff_clues.txt. A layer that" \
	"is not the output test passes its own key as LAYER (valgrind_test.sh's" \
	"\"valgrind\"): its rows show first, the output test's under a heading" \
	"saying whose they are. One reading rule means a maintainer's '#' note" \
	"never reaches a student and CLUE_MODE means the same everywhere."

# ---------------------------------------------------------------------------
# N. A generated exercise's clues.tsv says whose it is, on its first line:
#
#     # clues.tsv for <module> exNN (<turn-in>) ...
#
# One header had lost its module's name, one named no turn-in, and one carried
# a title from another language's edition of the subject (finding 019). The
# line is a maintainer's and never printed (rl_clues skips '#'), but it is how
# anyone reading the file -- docs/testing.md invites it -- tells which exercise
# it is, and a shell exercise's file is often read by a twin in another module
# (twin_of), where the folder around it names the wrong one. Checked for every
# exercise with a generators/exNN.sh, whose turn-in no C prototype names.
hdr_bad=$(for _m in $MODULES; do
	[ -d "$_m/generators" ] || continue
	for _g in "$_m"/generators/ex*.sh; do
		[ -f "$_g" ] || continue
		_ex=${_g##*/}
		_ex=${_ex%.sh}
		_c="$_m/tests/$_ex/clues.tsv"
		[ -f "$_c" ] || continue
		_h=$(sed -n 1p "$_c")
		case "$_h" in
			"# clues.tsv for ${_m##*/} $_ex ("?*")"*) ;;
			*) printf '    %s:1: %s\n' "$_c" "$_h" ;;
		esac
	done
done)
[ -z "$hdr_bad" ] || report \
	"a generated exercise's clues.tsv does not say whose it is" \
	"$hdr_bad" \
	"Its first line reads: # clues.tsv for <module> exNN (<turn-in>), with the" \
	"module's folder name, the exercise, and the file the subject says to turn in."

# ---------------------------------------------------------------------------
# N. Every clue label names a case that actually exists.
#
# A clues.tsv row is `<hint><TAB><case label><TAB><case label>...`, and the hint
# fires when one of those cases fails. A label that matches no case is
# therefore a gate that can never open -- the hint is still reachable through
# its OTHER labels, so nothing goes red and nobody finds out. c-02 ex09 carried
# one for as long as the file has existed: a row about word boundaries listed
# "punctuation/+ as separators", a description of a case rather than the label
# of one, while the two cases that actually exercise punctuation (the subject
# transcripts) went unlisted.
#
# What a label may be, from what the runners key hints on:
#   - a label of the exercise's expected.txt (its first tab field); in a
#     program's folder, a label of a case that says "labeled": True (its
#     expected file's first field), and of no other .txt there: an unlabeled
#     output's rows are keyed "line N";
#   - "line N", the label diff_output.sh gives row N of an unlabelled table,
#     for an N the expected output has;
#   - the name of one of the exercise's c_program cases (diff_output.sh,
#     valgrind_test.sh --case), whose rows are bare lines: a program case is
#     a test of its own, and its name is the only key a hint about it can have
#     (finding 155). Such a file is checked with no expected.txt beside it,
#     and "line N" is then any N: each case has an output file of its own;
#   - the name a test written by hand passes as --case (a corpus runner's
#     target, bsq_check.sh and rush01_check.sh), which is a case of the
#     program as well;
#   - "valgrind", in a program's file: valgrind_test.sh fires it on a case's
#     memory arm and nowhere else, so a memory hint comes first there.
#
# One dead label in 130 files is the kind of thing only a machine finds, and the
# cost of not finding it is a hint that does not appear when it is needed.
#
# The case names are read from each module's BUILD.bazel: every
# `"name": "<case>"` inside a c_program( call, with the call's num, and for a
# case that says `"labeled": True` its `"expected"` file, whose rows are keyed
# by their labels -- one line per case, "<folder>\t<name>\t<file or empty>".
# A call runs from its `c_program(` line to the next line that starts in the
# first column, which is buildifier's layout. A case is a dict one brace deep
# in the call, read token by token (a string, a brace, True), so one written
# on one line and one laid out over several read alike, and a dict inside a
# case (cwd_files) is not taken for one.
_prog_cases=$(for _m in $MODULES; do
	[ -f "$_m/BUILD.bazel" ] || continue
	awk -v m="$_m" '
		function flush(   i) {
			if (inb && num != "")
				for (i = 1; i <= n; i++) print m "/tests/ex" num "\t" nm[i] "\t" lx[i]
			inb = 0; n = 0; num = ""; depth = 0; key = ""
		}
		function close_case() {
			if (cv["name"] != "") {
				nm[++n] = cv["name"]
				lx[n] = (cv["labeled"] == "True") ? cv["expected"] : ""
			}
			split("", cv)
		}
		/^[^ \t#]/ && !/^c_program\(/ { if (inb) { take(); flush() } ; next }
		/^c_program\(/ { flush(); inb = 1 }
		inb { take() }
		function take(   s, i, j, L, c, str) {
			s = $0
			sub(/#.*/, "", s)
			if (num == "" && match(s, /num[ \t]*=[ \t]*"[0-9][0-9]"/)) {
				num = substr(s, RSTART, RLENGTH); gsub(/[^0-9]/, "", num)
			}
			s = $0
			L = length(s)
			for (i = 1; i <= L; i++) {
				c = substr(s, i, 1)
				if (c == "#") break
				if (c == "\"") {
					for (j = i + 1; j <= L && substr(s, j, 1) != "\""; j++)
						if (substr(s, j, 1) == "\\") j++
					str = substr(s, i + 1, j - i - 1)
					if (substr(s, j + 1) ~ /^[ \t]*:/) key = str
					else { if (depth == 1 && key != "") cv[key] = str; key = "" }
					i = j
				} else if (c == "{") {
					if (++depth == 1) split("", cv)
					key = ""
				} else if (c == "}") {
					if (depth-- == 1) close_case()
					key = ""
				} else if (substr(s, i, 4) == "True") {
					if (depth == 1 && key != "") cv[key] = "True"
					key = ""; i += 3
				} else if (c !~ /[ \t:]/) key = ""
			}
		}
		END { flush() }' "$_m/BUILD.bazel"
	# And the name a test written by hand keys its hints to (--case): a
	# target replaying a corpus through a runner of its own (BSQ's and
	# Rush 01's ex00_readings, Rush 01's ex00_sweep) is a case of the
	# program too, keyed by its name after exNN_ in the one clues.tsv. The
	# exercise is the call's own (`name =` or corpus_memory's `stem =`), and
	# the name is the string literal right after "--case", on its line or the
	# next that holds anything. Anything else there -- a Starlark variable,
	# an expression -- cannot be read from the text, and is reported as such
	# (case_unreadable, below): read as the next quoted string on any later
	# line, it made some other word a case, and a clue row keyed to that word
	# passed the dead-label check.
	awk -v m="$_m" -v uf="$lex_d/case_unreadable" '
		/^[^ \t#]/ { ex = ""; want = 0 }
		ex == "" && match($0, /^[ \t]*(name|stem)[ \t]*=[ \t]*"ex[0-9][0-9]_/) {
			s = substr($0, RSTART, RLENGTH); sub(/^[^"]*"/, "", s); ex = substr(s, 1, 4)
		}
		function take(text) {
			if (match(text, /^[ \t]*"[^"]*"/)) {
				v = substr(text, RSTART, RLENGTH); sub(/^[ \t]*"/, "", v); sub(/"$/, "", v)
				if (ex != "") print m "/tests/" ex "\t" v "\t"
			} else
				printf "    %s/BUILD.bazel:%d: %s\n", m, FNR, $0 >> uf
		}
		{
			line = $0; sub(/#.*/, "", line)
			if (want) {
				if (line ~ /^[ \t]*$/) next
				want = 0
				take(line)
				next
			}
			if (line ~ /"--case"[ \t]*,/) {
				rest = line; sub(/.*"--case"[ \t]*,/, "", rest)
				if (rest ~ /^[ \t]*$/) want = 1
				else take(rest)
			}
		}' "$_m/BUILD.bazel"
done)
if [ -s "$lex_d/case_unreadable" ]; then
	report "a BUILD file passes --case a value this check cannot read" \
		"$(cat "$lex_d/case_unreadable")" \
		"The dead-label check below reads the name a hand-written test keys its" \
		"hints to from the BUILD text, as the string literal after \"--case\"." \
		"A variable or an expression there cannot be read, and a guess made some" \
		"other word a case. Write the case's name as a string literal."
fi
# prog_labels DIR -- the expected file of each labeled c_program case of
# DIR, one path per line: the files whose first fields are labels there.
prog_labels() {
	printf '%s\n' "$_prog_cases" | awk -F'\t' -v d="$1" '$1 == d && $3 != "" { print d "/" $3 }'
}
# cat_each -- the files named one per line on stdin, those that exist.
cat_each() {
	while IFS= read -r _f; do
		[ -f "$_f" ] && cat "$_f"
	done
	return 0
}
for c in $(for _m in $MODULES; do
	for _c in "$_m"/tests/ex*/clues*.tsv; do
		[ -f "$_c" ] && echo "$_c"
	done
done); do
	d=${c%/*}
	e="$d/expected.txt"
	names=$(printf '%s\n' "$_prog_cases" | awk -F'\t' -v d="$d" '$1 == d { print $2 }')
	# A case's own hint file (clues_<x>.tsv) is the next rule's, and only
	# its: both read the program's folder, and two rules over one file
	# disagreed -- this one took a program's names alone, the next the
	# labels of the folder's .txt files too, so a row keyed to a row of a
	# labeled program case was allowed there and reported here (V12).
	case "${c##*/}" in
		clues.tsv) [ -f "$e" ] || [ -n "$names" ] || continue ;;
		*) continue ;;
	esac
	# In a program's folder each case has an output file of its own, and a
	# labeled one's rows are keyed by their labels (diff_output.sh puts a
	# failing row's label in FAILED beside the case's name): the labeled
	# cases' files give labels, and only theirs. Every other output is keyed
	# "line N", so the first field of one of its lines -- a sentence the
	# program prints -- is no label, and a hint keyed to it never fires.
	labs=$e
	[ -z "$names" ] || labs=$(prog_labels "$d")
	dead=$(NAMES="$names" LABS="$labs" awk -F'\t' '
		BEGIN {
			nf = split(ENVIRON["LABS"], lf, "\n")
			for (j = 1; j <= nf; j++)
				while ((getline l < lf[j]) > 0) { ne++; split(l, a, "\t"); lab[a[1]] = 1 }
			nn = split(ENVIRON["NAMES"], pn, "\n")
			for (i = 1; i <= nn; i++) if (pn[i] != "") { lab[pn[i]] = 1; prog = 1 }
		}
		/^[ \t]*#/ || /^[ \t]*$/ { next }
		{
			for (i = 2; i <= NF; i++) {
				if ($i == "" || ($i in lab)) continue
				if ($i ~ /^line [1-9][0-9]*$/ && (prog || substr($i, 6) + 0 <= ne)) continue
				if ($i == "valgrind" && prog) continue
				printf "    line %d: %s\n", NR, $i
			}
		}' "$c")
	[ -z "$dead" ] || report \
		"$c names a case that does not exist" \
		"$dead" \
		"A clue fires when one of the cases it lists fails. A label matching no" \
		"case is a gate that can never open, and because the hint is still" \
		"reachable through its other labels nothing ever goes red. Use a label" \
		"of expected.txt exactly as it is written there (in a program's folder," \
		"of a case that says \"labeled\": True), \"line N\" for a row of an" \
		"unlabelled output, the" \
		"\"name\" of one of the exercise's c_program cases, or \"valgrind\" for a" \
		"program's memory arms."
done

# The same for a case's own hint file (clues_<something>.tsv), which a case of
# c_header or c_program, or a reading of c_function, names beside its own
# expected file. Which expected file goes with which hint file is the BUILD's
# to say, so the rule here is looser: a label must be a case in SOME .txt file
# of the same folder. A typo still matches none; before this, only the
# first-red check read these files, and no check held their labels to a case.
# In a program's folder the labels the rule above accepts there -- a case's
# name, "line N", "valgrind", a labeled case's row -- are cases too, and those
# alone: both rules read the same folder, and one must never report what the
# other was written to allow, nor allow what the other reports.
for c in $(for _m in $MODULES; do
	for _c in "$_m"/tests/ex*/clues_*.tsv; do
		[ -f "$_c" ] && echo "$_c"
	done
done); do
	d=${c%/*}
	names=$(printf '%s\n' "$_prog_cases" | awk -F'\t' -v d="$d" '$1 == d { print $2 }')
	labs=$(printf '%s\n' "$d"/*.txt)
	[ -z "$names" ] || labs=$(prog_labels "$d")
	dead=$(printf '%s\n' "$labs" | cat_each | NAMES="$names" awk -F'\t' -v c="$c" '
		{ lab[$1] = 1 }
		END {
			nn = split(ENVIRON["NAMES"], pn, "\n")
			for (i = 1; i <= nn; i++) if (pn[i] != "") { lab[pn[i]] = 1; prog = 1 }
			while ((getline l < c) > 0) {
				n++
				if (l ~ /^[ \t]*#/ || l ~ /^[ \t]*$/) continue
				k = split(l, f, "\t")
				for (i = 2; i <= k; i++) {
					if (f[i] == "" || (f[i] in lab)) continue
					if (prog && (f[i] ~ /^line [1-9][0-9]*$/ || f[i] == "valgrind")) continue
					printf "    line %d: %s\n", n, f[i]
				}
			}
		}')
	[ -z "$dead" ] || report \
		"$c names a case that no expected file in ${d#./} holds" \
		"$dead" \
		"A clue fires when one of the cases it lists fails, so a label that" \
		"names no case is a gate that never opens. Use the label exactly as" \
		"the case's expected file (the .txt beside it) writes it, or, in a" \
		"program's folder, a case's \"name\", \"line N\", \"valgrind\" or a row" \
		"of a case that says \"labeled\": True."
done

# ---------------------------------------------------------------------------
# N. A differential harness names its columns in the shape the diff layer reads.
#
# rust_diff.sh prints a divergence as raw records -- hex inputs, then outputs --
# and the only key to them is the "Line:" paragraph of the harness's header
# comment, which its print_columns shows under the divergences. That paragraph
# was free-form for years, and 23 harnesses fell out of it (finding 058): nine
# had no "Line:" at all, so a student got bare hex and nothing to decode it
# with; fourteen wrote the sentence on the `/*` line, which printed with the
# `/*` and the words before it; others named the inputs and not the output.
#
# The shape: within the first 12 lines (all print_columns reads), a comment
# line whose text BEGINS with "Line:" -- ` * Line: <col>\t<col>...` -- never
# the `/*` line itself. What it must say, every printed column named, inputs
# and output alike, is the author's to keep; this checks what a machine can.
for _m in $MODULES; do
	[ -d "$_m/tests" ] || continue
	find "$_m/tests" -name 'diff_*.c' 2> /dev/null | sort > "$lex_d/files"
	while IFS= read -r h; do
		# The first line naming "Line:" decides; awk's END runs after an
		# `exit` too, so it speaks only when no line did.
		why=$(sed -n '1,12p' "$h" | awk '
			/Line:/ {
				seen = 1
				if ($0 ~ /\/\*/)
					print "its \"Line:\" sentence is on the /* line"
				else if ($0 !~ /^[ \t]*\*[ \t]*Line:/)
					print "its \"Line:\" sentence does not begin its comment line"
				exit
			}
			END { if (!seen) print "no comment line in its first 12 begins with \"Line:\"" }')
		[ -z "$why" ] || report \
			"$h: $why" \
			"The diff layer prints its divergences as raw records, and a legend read" \
			"from this header is the only key to them. Open the header with a line" \
			"of its own, ' * Line: <col>\\t<col>...', naming every column the harness" \
			"prints, inputs and output alike (tools/rust_diff.sh, print_columns)."
	done < "$lex_d/files"
done

# ---------------------------------------------------------------------------
# N. A string harness's legend has a line for the bytes above 0x7f.
#
# A char is signed here, so a test or comparison of a byte goes wrong on
# 0x80-0xff in ways no ASCII input shows, and WP-38 seeded those bytes into
# the string corpora (finding 061) and gave each legend a family line for
# them ("only strings holding a byte of 0x80 or more -> ..."): without it a
# divergence on such a byte reads as noise. Nothing held the next harness to
# it. So a harness that DECODES BYTES -- a diff_*.c calling one of
# tools/diffio.h's hex readers, dio_unhex, dio_unhexn, dio_hex_n or
# dio_hex_list -- has, in a diff_clues*.txt beside it (the folder's legend,
# or a readings target's diff_clues_readings.txt), a line naming 0x80 or
# 0x7f, or says in a maintainer's line of one of them why no byte of them
# reaches the code under test: '# conventions: no byte family -- REASON'
# (C 13's items and C 11's tokens, which only the harness's own functions
# read). One place for that reason, the legend's maintainer lines, as for
# every other note a legend carries. It was keyed on the word "hex" in the
# header's first twelve lines, so a harness describing its input as
# "escaped bytes" or "raw bytes" was skipped; what it does is what decides
# now, and a harness with no legend at all is held too. A harness decoding
# hex with code of its own is not seen, and none does: diffio's readers are
# how the harnesses take bytes (the rule on arrays sized from the case,
# below, sends them there). Whether the corpus does seed such bytes is the
# generator's, which this cannot read; a string corpus that seeds none
# should seed some.
byte_bad=$(for _m in $MODULES; do
	[ -d "$_m/tests" ] || continue
	find "$_m/tests" -name 'diff_*.c' \( -type f -o -type l \) 2> /dev/null | sort > "$lex_d/files"
	while IFS= read -r _h; do
		grep -Eq '(^|[^A-Za-z0-9_])dio_(unhexn?|hex_n|hex_list)[[:blank:]]*\(' "$_h" || continue
		_named=""
		for _c in "${_h%/*}"/diff_clues*.txt; do
			[ -f "$_c" ] || continue
			grep -v '^[[:blank:]]*#' "$_c" | grep -q -i -e '0x80' -e '0x7f' && _named=1
			grep -q '^[[:blank:]]*# conventions: no byte family -- [^[:blank:]]' "$_c" && _named=1
		done
		[ -n "$_named" ] || echo "    $_h"
	done < "$lex_d/files"
done)
[ -z "$byte_bad" ] || report \
	"a string harness's legend names no family for the bytes above 0x7f" \
	"$byte_bad" \
	"Its corpus hands the code under test bytes, and a char is signed here: a" \
	"test of a byte that goes wrong on 0x80-0xff shows as divergences nothing" \
	"in the legend explains. Add a family line for them to a diff_clues*.txt" \
	"beside it (\"only strings holding a byte of 0x80 or more -> ...\", a" \
	"question, never the fix), or say there why none reaches the code:" \
	"'# conventions: no byte family -- REASON'."

# ---------------------------------------------------------------------------
# N. A differential harness that reads a result as never written starts it
#    at two values.
#
# A harness that prints "untouched" for an out-parameter still holding the
# value it started at reads a missing store as one. A fixture's rows are
# fixed, so one starting value no row expects does that there. A corpus can
# expect any value of the type, so one starting value is a value some case
# may expect, and on that case a function that skipped the store matches
# the reference: C 01 ex03's harness started at 0, a quotient many cases
# expect (wave 4), and any one value that replaced it is a quotient too. So
# each case runs from two, and a result is untouched only when it kept its
# start both times (C 01 ex03's diff_div_mod.c, PRESET_A and PRESET_B); a
# function that stores, stores the same value both times. A diff_*.c that
# prints "untouched" defines two PRESET_ values at least.
for _m in $MODULES; do
	[ -d "$_m/tests" ] || continue
	find "$_m/tests" -name 'diff_*.c' 2> /dev/null | sort > "$lex_d/files"
	while IFS= read -r h; do
		grep -q '"untouched"' "$h" || continue
		_np=$(grep -c -E '^[[:blank:]]*#[[:blank:]]*define[[:blank:]]+PRESET_[A-Za-z0-9_]+[[:blank:]]' "$h")
		[ "$_np" -ge 2 ] || report \
			"$h reads a result as never written (\"untouched\") from fewer than two starting values" \
			"A corpus can expect any value of the type, so a single starting value" \
			"is one some case expects, and there a function that never stores its" \
			"result matches the reference. Run each case from two values" \
			"(#define PRESET_A, PRESET_B), and print untouched only for a result" \
			"that kept its start both times, as C 01 ex03's diff_div_mod.c does."
	done < "$lex_d/files"
done

# ---------------------------------------------------------------------------
# N. A differential harness hands the function under test no zeroed buffer.
#
# C 03's appenders ran on destinations from calloc (finding 057): the byte
# where a terminator belongs was 0 before the call, so an ft_strcat that never
# wrote one printed the right string, and neither the diff nor its ASan twin
# could tell. The fix there was a destination whose free bytes are 0xff, and
# tools/diffio.h holds it once -- dio_garbage(cap), and dio_dest(s, len, cap)
# for one that holds a string already -- so the next harness asks for it
# rather than writing the four lines again.
#
# What this sees, in a tests/**/diff_*.c: a buffer that starts zeroed --
# calloc (not of a struct: a list's or a tree's nodes are zeroed so their
# links are NULL), memset to 0, bzero, dio_unhex with a non-zero pad, a char
# array with an initialiser, a static char array -- or that starts unset,
# which on a fresh page is zeroed as often as not -- malloc (not of a
# struct), a char array declared and never set -- whose own name then
# appears in a call to the function under test (an ft_ function, or one the
# harness declares at column 0). A memset to a byte that is not 0 fills it;
# 0 is every spelling of it (0x00, '\x00', (0)...).
# Such a buffer needs its reason written on its line or in the comment right
# above it:
#
#     /* conventions: zeroed -- <why the zeros cannot hide a missing write> */
#
# It follows the buffer's name to the call, not copies of the pointer: after
# `p = buf; ft_x(p)` it sees nothing, and a reviewer still reads that. The
# curated fixtures (test_*.c) are not held to it: they zero-fill on purpose in
# rows that test something else, and what they owe is one row that does not
# -- a judgement about the exercise, not a pattern.
zeroed_handed() {  # zeroed_handed FILE -- one line per zeroed buffer handed on unexplained
	LC_ALL=C awk '
		function ident_in(s, v,    i, a, b) {
			# v as a whole identifier somewhere in s
			while ((i = index(s, v)) > 0) {
				a = (i > 1) ? substr(s, i - 1, 1) : ""
				b = substr(s, i + length(v), 1)
				if (a !~ /[A-Za-z0-9_]/ && b !~ /[A-Za-z0-9_]/) return 1
				s = substr(s, i + length(v))
			}
			return 0
		}
		function lastid(s,    r) {
			# the last identifier of s: the variable of "(char *)buf" or "&x.y"
			r = ""
			while (match(s, /[A-Za-z_][A-Za-z0-9_]*/)) {
				r = substr(s, RSTART, RLENGTH)
				s = substr(s, RSTART + RLENGTH)
			}
			return r
		}
		function zero(v, why) {
			if (v == "") return
			nz++; zv[nz] = v; zl[nz] = FNR; zw[nz] = why
			zok[nz] = (FNR == markline || markline > lastcode)
		}
		function iszero(x) {
			# Every spelling of a zero byte: 0, 00, 0x00, 0u, (0), (char)0,
			# and the character constants \0, \000 and \x00. One spelling
			# missed was a zeroing read as a fill, which cleared the buffer
			# it zeroed.
			gsub(/[ \t]/, "", x)
			while (x ~ /^\(.*\)$/ || x ~ /^\((unsigned|signed)?(char|int)\)/) {
				if (x ~ /^\(.*\)$/ && x !~ /^\((unsigned|signed)?(char|int)\)./) x = substr(x, 2, length(x) - 2)
				else sub(/^\((unsigned|signed)?(char|int)\)/, "", x)
			}
			return x ~ /^(0+|0[xX]0+)[uUlL]*$/ || x ~ /^\047\\(0+|[xX]0+)\047$/
		}
		{
			raw = $0; code = ""; cmt = ""
			# Split the line into code and comment text, across /* */ blocks.
			while (raw != "") {
				if (incmt) {
					i = index(raw, "*/")
					if (i == 0) { cmt = cmt raw; raw = ""; break }
					cmt = cmt substr(raw, 1, i - 1); raw = substr(raw, i + 2); incmt = 0
					continue
				}
				i = index(raw, "/*"); j = index(raw, "//")
				if (j > 0 && (i == 0 || j < i)) { code = code substr(raw, 1, j - 1); cmt = cmt substr(raw, j + 2); raw = ""; break }
				if (i == 0) { code = code raw; raw = ""; break }
				code = code substr(raw, 1, i - 1); raw = substr(raw, i + 2); incmt = 1
			}
			if (cmt ~ /conventions: zeroed -- [^ ]/) markline = FNR
			if (code ~ /^[ \t]*$/) next
			# The functions under test: a prototype at column 0.
			if (code ~ /^[A-Za-z]/ && code !~ /^(static|typedef|extern|return)[ \t]/ &&
				code ~ /\)[ \t]*;[ \t]*$/ && match(code, /[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/)) {
				f = substr(code, RSTART, RLENGTH); sub(/[ \t]*\($/, "", f)
				if (f != "main") under[f] = 1
			}
			# What starts zeroed.
			if (match(code, /[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?[ \t]*=[ \t]*(\([^)]*\)[ \t]*)?calloc[ \t]*\(/)) {
				rest = substr(code, RSTART + RLENGTH)
				if (rest !~ /sizeof[ \t]*\([ \t]*(t_|struct)/) {
					s = substr(code, RSTART, RLENGTH); sub(/[ \t]*(\[[^]]*\])?[ \t]*=.*$/, "", s)
					zero(s, "calloc")
				}
			}
			# A memset to 0 zeroes; one to any other byte fills (below).
			mset = ""
			if (match(code, /memset[ \t]*\([^,]*,[^,]*,/)) {
				s = substr(code, RSTART, RLENGTH); sub(/^memset[ \t]*\(/, "", s)
				mval = s; sub(/^[^,]*,/, "", mval); sub(/,$/, "", mval)
				sub(/,.*$/, "", s)
				mset = lastid(s)
				if (iszero(mval)) { zero(mset, "memset to 0"); mset = "" }
			}
			if (match(code, /bzero[ \t]*\([^,]*,/)) {
				s = substr(code, RSTART, RLENGTH); sub(/^bzero[ \t]*\(/, "", s); sub(/,.*$/, "", s)
				zero(lastid(s), "bzero")
			}
			if (match(code, /[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?[ \t]*=[ \t]*(\([^)]*\)[ \t]*)?dio_unhex[ \t]*\([^;]*\)/)) {
				s = substr(code, RSTART, RLENGTH)
				pad = s; sub(/\)[^)]*$/, "", pad); sub(/^.*,[ \t]*/, "", pad)
				if (!iszero(pad)) {
					sub(/[ \t]*(\[[^]]*\])?[ \t]*=.*$/, "", s)
					zero(s, "dio_unhex with pad " pad)
				}
			}
			if (match(code, /static[ \t]+(unsigned[ \t]+|signed[ \t]+)?char[ \t*]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\[/)) {
				s = substr(code, RSTART, RLENGTH); sub(/[ \t]*\[$/, "", s)
				zero(lastid(s), "a static array")
			} else if (match(code, /char[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\[[^]]*\][ \t]*=/)) {
				s = substr(code, RSTART, RLENGTH); sub(/[ \t]*\[.*$/, "", s)
				zero(lastid(s), "an initialised array")
			} else if (match(code, /char[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\[[^]]*\][ \t]*;/) &&
				code !~ /(^|[^A-Za-z0-9_])extern[ \t]/) {
				# Never set at all: what a fresh stack page holds, 0 as often
				# as not.
				s = substr(code, RSTART, RLENGTH); sub(/[ \t]*\[.*$/, "", s)
				zero(lastid(s), "an array never set")
			}
			# The char pointers declared here, for the malloc below: every
			# declarator of `char *a, *b = NULL;` and every parameter of a
			# list, never a function that returns one (`char *f(`).
			rest = code
			while (match(rest, /(^|[^A-Za-z0-9_])char[ \t]*\*[ \t]*[A-Za-z_][A-Za-z0-9_]*/)) {
				s = substr(rest, RSTART, RLENGTH)
				rest = substr(rest, RSTART + RLENGTH)
				if (rest !~ /^[ \t]*\(/) charp[lastid(s)] = 1
				while (match(rest, /^[ \t]*(=[^,;()]*)?,[ \t]*\*[ \t]*[A-Za-z_][A-Za-z0-9_]*/)) {
					s = substr(rest, RSTART, RLENGTH)
					rest = substr(rest, RSTART + RLENGTH)
					charp[lastid(s)] = 1
				}
			}
			# What malloc hands back holds whatever the allocator left: on a
			# fresh page, zeros. A char buffer only -- the cast says so, or
			# the pointer was declared char * -- since an array of ints or of
			# pointers the harness fills whole has no free bytes to hide a
			# terminator in.
			if (match(code, /[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?[ \t]*=[ \t]*(\([^)]*\)[ \t]*)?malloc[ \t]*\(/)) {
				s = substr(code, RSTART, RLENGTH)
				cast = ""
				if (match(s, /\([^)]*\)[ \t]*malloc/)) { cast = substr(s, RSTART, RLENGTH); sub(/[ \t]*malloc$/, "", cast) }
				sub(/[ \t]*(\[[^]]*\])?[ \t]*=.*$/, "", s)
				if (cast ~ /^\([ \t]*((un)?signed[ \t]+)?char[ \t]*\*[ \t]*\)$/ || (cast == "" && (s in charp)))
					zero(s, "malloc, its bytes never set")
			}
			# A buffer filled with a byte that is not 0 is not zeroed any
			# more: the 0xff of dio_garbage, written out by hand.
			if (mset != "")
				for (k = nz; k >= 1; k--) if (zv[k] == mset) { zok[k] = 1; break }
			# Every call line, kept for the end: a prototype may follow main.
			ncall++; cl[ncall] = code; cn[ncall] = FNR
			lastcode = FNR
		}
		END {
			for (k = 1; k <= nz; k++) {
				if (zok[k]) continue
				for (c = 1; c <= ncall; c++) {
					if (cn[c] < zl[k]) continue
					line = cl[c]; hit = ""
					while (match(line, /[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/)) {
						f = substr(line, RSTART, RLENGTH); sub(/[ \t]*\($/, "", f)
						after = substr(line, RSTART + RLENGTH)
						if ((f in under || f ~ /^ft_/) && ident_in(after, zv[k])) { hit = f; break }
						line = after
					}
					if (hit != "") {
						printf "line %d: %s (%s) reaches %s() on line %d\n", zl[k], zv[k], zw[k], hit, cn[c]
						break
					}
				}
			}
		}' "$1"
}
for _m in $MODULES; do
	[ -d "$_m/tests" ] || continue
	find "$_m/tests" -name 'diff_*.c' 2> /dev/null | sort > "$lex_d/files"
	while IFS= read -r h; do
		zh=$(zeroed_handed "$h")
		[ -z "$zh" ] || report \
			"$h hands the function under test a buffer that starts zeroed" \
			"$zh" \
			"In a zeroed buffer the byte where a terminator belongs is 0 before the" \
			"call, so a function that never writes one looks right (finding 057)." \
			"Take the buffer from tools/diffio.h's dio_garbage(cap) -- or" \
			"dio_dest(s, len, cap) for one holding a string already -- whose free" \
			"bytes are 0xff. Where the zeros cannot hide a missing write, say why" \
			"on that line or in the comment right above it:" \
			"    /* conventions: zeroed -- <why> */"
	done < "$lex_d/files"
done

# ---------------------------------------------------------------------------
# N. No runner and no clue sends a student to read the oracle.
#
# //oracle ships in every clone because the layers compare against it at run
# time, and it solves most of the exercises -- some arms in plain loops that
# carry over to C almost line for line (oracle/README.md, "Why Rust"). A student
# finds it where they choose to look: the README's table, and oracle/README.md,
# whose first section says what reading one costs. A test log is not that place.
# The refcost layer's last paragraph named //oracle and said reading it was
# allowed, on every passing c-00 and ten-queens run, one sentence after asking
# the student to take the question to a peer rather than to a tool that would
# simply tell them.
#
# So a runner may say a layer USES the oracle ("//oracle has no bench arm for
# ft_x yet" is plumbing), but no line of a runner, a module's check.sh, a
# clues.tsv or a test harness's string literals may put the oracle beside a word
# for reading it. The oracle counts when the line names its path (//oracle,
# oracle/, a .rs file) or calls it "the Rust oracle" or its "source". Comments
# are skipped -- a whole comment line, a trailing "# ..." on a line of shell,
# everything in a C file outside its string literals -- because they are written
# for whoever maintains the check, and several say which arm a fixture came
# from; so is the shell builtin (`while read -r x`), which reads a line and
# nobody's source. The files are the ones the sh_test can see as well as
# `bazel run` -- tools/*.sh and each module's :conventions_srcs -- so the two
# ways of running this agree.
#
# It is a line-by-line scan, so it catches the form the refcost paragraph had,
# not every phrasing of it: a door split across two echo lines gets past it.
# Joining neighbouring lines was tried and flags plumbing that happens to sit
# above a "see the subject", so a reviewer still reads new prose for this.
oracle_door=$(
	{
		for f in tools/*.sh; do echo "$f"; done
		for _m in $MODULES; do
			[ -d "$_m/tests" ] && find "$_m/tests" \( -name '*.sh' -o -name 'clues.tsv' \
				-o -name 'test_*.c' \) 2> /dev/null
		done
	} | sort -u | while IFS= read -r f; do
		awk -v f="$f" '
			# What of this line could reach a student.
			function text(line,   out) {
				if (f ~ /\.c$/) {
					out = ""
					while (match(line, /"([^"\\]|\\.)*"/)) {
						out = out " " substr(line, RSTART + 1, RLENGTH - 2)
						line = substr(line, RSTART + RLENGTH)
					}
					return out
				}
				if (line ~ /^[ \t]*#/)
					return ""
				sub(/[ \t]+#[^"\047]*$/, "", line)
				return line
			}
			{
				l = tolower(text($0))
				gsub(/(^|[^a-z_])read[ \t]+-[a-z]+/, " ", l)
			}
			(l ~ /(\/\/oracle|oracle\/|[a-z0-9_]\.rs([^a-z0-9_]|$))/ ||
			 (l ~ /(^|[^a-z])oracle([^a-z]|$)/ && l ~ /(^|[^a-z])(rust|source)([^a-z]|$)/)) &&
			l ~ /(^|[^a-z])(read[a-z]*|see|open[a-z]*|look[a-z]*)([^a-z]|$)/ {
				printf "    %s:%d: %s\n", f, NR, $0
			}' "$f"
	done
)
[ -z "$oracle_door" ] || report \
	"a runner or a clue points a student at the oracle's source" \
	"$oracle_door" \
	"Say what the layer measured -- the input, both outputs, the numbers --" \
	"and stop there. The oracle solves the exercise; a log that names it hands" \
	"the answer to whoever is curious at the moment the question is open. The" \
	"oracle's own README is where a student learns what that costs, first."

# ...nor may the part of a memory probe's header that asan_check.sh prints
# under its FAIL: the first comment within the probe's first 20 lines, read
# as a sentence to the student (tools/asan_check.sh, "The probe's OWN header
# comment"). There the oracle's PATH alone says where the answer lives -- a
# log may not say where one is (docs/design.md, "Measure the axis") -- and
# C 13 ex07's named oracle/src/c13.rs, in a sentence about the corpus that
# was no longer true (the mutation run of 2026-10-03, c13b obs. 2). The same
# extraction asan_check.sh runs, then a path of the oracle in any form.
probe_door=$(
	for _m in $MODULES; do
		[ -d "$_m/tests" ] && find "$_m/tests" \( -type f -o -type l \) -name 'mem_*.c' 2> /dev/null
	done | sort | while IFS= read -r f; do
		# Lines 1-20, from the first line opening a comment to the line
		# closing it: what asan_check.sh's two seds keep.
		awk -v f="$f" '
			NR > 20 || done { exit }
			# As sed reads a range: the line that opens it is not checked
			# for its close, so a one-line comment runs on to the next "*/".
			opened {
				if ($0 ~ /\*\//) done = 1
			}
			!opened && /^\/\*/ { opened = 1 }
			opened {
				l = tolower($0)
				if (l ~ /(\/\/oracle|oracle\/|[a-z0-9_]\.rs([^a-z0-9_]|$))/)
					printf "    %s:%d: %s\n", f, NR, $0
			}' "$f"
	done
)
[ -z "$probe_door" ] || report \
	"a memory probe's printed header names where the oracle lives" \
	"$probe_door" \
	"asan_check.sh prints this comment under every red of the probe: say" \
	"what the probe hands the function and what it catches, never where the" \
	"reference is. The oracle's own README is where a student meets it."

# ---------------------------------------------------------------------------
# N. A project's BUILD comment names neither the oracle's source nor a reading.
#
# A project's BUILD file ships, and its comments are prose a student reads
# (the owner's ruling, 2026-10-09; AGENTS.md section 2, "Shipped teaching
# prose"). So a comment there never points at the oracle's source -- the
# door the rules above shut in a log, a clue and a probe's header -- and
# never names a reading: only the strict target's own hint and its row of
# docs/reference.md state one. V94's census found 25 comment lines naming a
# file of oracle/src and four that said "this harness's reading", among them
# what the readings were. A reading stated in other words ("newest first,
# the direction ls sorts in") is past what this reads: the author is that
# check, as AGENTS.md section 0 says of prose.
#
# Read: each module's BUILD.bazel and .bzl files, whole-line comments and
# the comment after code on a line (a `#` with no string open before it).
# The label wraps, so a comment line is read with the one before it. The
# files are the ones :conventions_srcs hands the sh_test, so `bazel test`
# and `bazel run` read the same.
build_door=$(
	for _m in $MODULES; do
		[ -d "$_m" ] && find "$_m" -maxdepth 1 \( -type f -o -type l \) \
			\( -name BUILD.bazel -o -name '*.bzl' \) -print 2> /dev/null
	done | sort | while IFS= read -r f; do
		awk -v f="$f" '
			function comment(l,   i, c, q) {
				q = ""
				for (i = 1; i <= length(l); i++) {
					c = substr(l, i, 1)
					if (q != "") {
						if (c == "\\") i++
						else if (c == q) q = ""
					} else if (c == "\"" || c == "\047") q = c
					else if (c == "#") return substr(l, i + 1)
				}
				return ""
			}
			function norm(t) {
				gsub(/\342\200\231/, "\047", t)
				return tolower(t)
			}
			{
				c = comment($0)
				if (c == "") { pn = 0; next }
				t = norm(c)
				src = t ~ /oracle\/src|[a-z0-9_]\.rs([^a-z0-9_]|$)/
				lbl = t ~ /(this|the) harness\047s reading/
				if (src)
					printf "S    %s:%d: %s\n", f, NR, $0
				if (lbl)
					printf "L    %s:%d: %s\n", f, NR, $0
				else if (pn && !plbl) {
					j = pt " " t
					gsub(/[[:blank:]]+/, " ", j)
					if (j ~ /(this|the) harness\047s reading/)
						printf "L    %s:%d: %s (wrapped onto line %d)\n", f, pn, pr, NR
				}
				pt = t; pr = $0; pn = NR; plbl = lbl
			}' "$f"
	done
)
build_src=$(printf '%s\n' "$build_door" | sed -n 's/^S//p')
build_lbl=$(printf '%s\n' "$build_door" | sed -n 's/^L//p')
[ -z "$build_src" ] || report \
	"a project's BUILD comment names the oracle's source" \
	"$build_src" \
	"A project's BUILD file ships, and a student reads its comments (the" \
	"owner's ruling, 2026-10-09; AGENTS.md section 2). Say what the" \
	"reference does, never where its source is." \
	"${_bd_private-}"
[ -z "$build_lbl" ] || report \
	"a project's BUILD comment carries this harness's label for a reading" \
	"$build_lbl" \
	"A project's BUILD file ships, and a student reads its comments (the" \
	"owner's ruling, 2026-10-09; AGENTS.md section 2). Name the target that" \
	"holds one reading, never the reading: only its own hint and its row of" \
	"docs/reference.md state it."

# ---------------------------------------------------------------------------
# N. A runner quotes no subject of its own accord.
#
# A runner is shared by every project that calls it, so a sentence written into
# it is quoted at every one of them. make_test.sh quoted C 09's definitions of
# clean, fclean and re at C 10, Rush 02 and BSQ, whose subjects define none;
# allocfail_check.sh sent C 07 to "if an error occurs", which only C 08 says;
# valgrind_test.sh sent every student to "the paragraph on memory management"
# of subjects that have none (finding 082). What a subject says reaches a
# runner from its call site -- make_test --quotes, allocfail_check --rule,
# valgrind_test --rule -- where it is written once, with where it is from.
#
# So no message of a runner -- an echo, a printf, an awk print, a verdict( or
# say( call, or a line of a here-document it prints -- names a project or cites
# a page: a project's name or "p.N" there is a sentence of one subject said to
# all of them.
#
# A RUNNER ONE PROJECT CALLS restates its subject without naming it: Rush 01's
# and BSQ's printed "the subject prints it verbatim" and "the subject picks the
# one closest to the TOP" (V90). The owner's ruling, 2026-10-09: such a runner
# takes the sentence from its call site too (--quotes, tools/runner_lib.sh's
# rl_quote). So in a runner that exactly one module's BUILD.bazel runs (its
# label as a test's `srcs` or a corpus_memory `runner`) and no macro of
# tools/defs.bzl emits as a test's `srcs` -- its tables of runner facts
# (_RUNNER_CHOICES, _LIB_RUNNERS) do not count -- a message also never says
# what "the subject" says, reads, prints, picks, fixes, sets, requires, asks,
# lists, gives or states. A runner the macros call speaks to every project,
# and its "the files the subject asks for" is the call site's contract read
# back, so the phrase is not judged there.
#
# A program's own name is not a project's (rush02_check.sh's ./rush-02 replay
# line), and neither is a word inside a path or a longer name. Comments are
# skipped, in a here-document too: they say where a rule came from, for
# whoever maintains the runner. A message continued over lines ending in a
# backslash is read whole, its strings joined, and reported at its first line
# (not one built in a $( ), whose output is an argument of another command);
# two separate echo lines are still read one by one. awk's print counts where
# it starts a statement, never as a word inside a string.
#
# THE NAMES COME FROM THE MODULE TABLE (tools/submit.sh's REMOTES), never from
# a list kept here: a list of the Piscine's names let the first Common Core
# project through, as a list of path shapes once let BSQ through the zone
# rule. A module's name is its folder's less its course's prefix
# (c-piscine/c-piscine-c-09 is c-09, cursus/libft is libft), or the course's
# less its first word where the module is the course (c-piscine-reloaded is
# piscine-reloaded), matched in any case with a blank, - or _ (or nothing)
# between its words: "C 09", "Rush 02", "BSQ", "Piscine Reloaded", "Libft".
project_names=$(for _m in $MODULES; do
	_c=${_m%%/*}
	_b=${_m##*/}
	case "$_b" in
		"$_c"-*) _b=${_b#"$_c"-} ;;
		"$_c") _b=${_b#*-} ;;
	esac
	printf '%s\n' "$_b" | tr 'A-Z' 'a-z'
done | sort -u)
subject_leak=$(for f in $RUNNERS; do
	_own=0
	_lbl="//tools:${f#tools/}"
	if ! grep -qF "srcs = [\"$_lbl\"" tools/defs.bzl; then
		_n=0
		for _m in $MODULES; do
			[ -f "$_m/BUILD.bazel" ] || continue
			if grep -qF "srcs = [\"$_lbl\"" "$_m/BUILD.bazel" ||
				grep -qF "runner = \"$_lbl\"" "$_m/BUILD.bazel"; then
				_n=$((_n + 1))
			fi
		done
		[ "$_n" -eq 1 ] && _own=1
	fi
	awk -v f="$f" -v names="$project_names" -v own="$_own" '
		BEGIN {
			n = split(names, nm, "\n")
			for (i = 1; i <= n; i++) {
				w = nm[i]
				gsub(/[-_ ]+/, "[-_ ]?", w)
				pat[i] = "(^|[^a-z0-9_./-])" w "([^a-z0-9_]|$)"
			}
		}
		# A here-document is read to its delimiter, as its lines print.
		hd != "" {
			t = $0
			sub(/^\t*/, "", t)
			if (t == hd) { hd = ""; next }
			if (t ~ /^[ \t]*#/) next
			l = $0; at = NR; first = $0
			judge()
			next
		}
		# The rest of a message continued with a backslash.
		more {
			l = l " " $0
			if (!(more = ($0 ~ /\\[ \t]*$/))) judge()
			next
		}
		/^[ \t]*#/ { next }
		match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/) {
			hd = substr($0, RSTART, RLENGTH)
			gsub(/[<\-"\047 \t]/, "", hd)
		}
		!/(^|[;&|({ \t])(echo|printf)[ \t(]/ && !/(^|[;{)])[ \t]*print[ \t(]/ &&
		    !/(^|[^A-Za-z0-9_])(verdict|say)\(/ { next }
		{
			l = $0; at = NR; first = $0
			sub(/[ \t]+#[^"\047]*$/, "", l)
			more = ($0 ~ /\\[ \t]*$/ && $0 !~ /\$\([ \t]*(echo|printf)/)
			if (!more) judge()
		}
		END { if (more) judge() }
		function judge(    i, low, j) {
			low = tolower(l)
			for (i = 1; i <= n; i++)
				if (pat[i] != "" && low ~ pat[i]) { hit(); return }
			if (l ~ /(^|[^A-Za-z0-9_])p\.[0-9]/) { hit(); return }
			# Its words as they print: escapes, quotes and the joins between
			# the strings of one message gone.
			j = low
			gsub(/\\[nt]/, " ", j)
			gsub(/["\047\\]/, " ", j)
			gsub(/[ \t]+/, " ", j)
			if (own && j ~ /(^|[^a-z])the subject (says|reads|prints|picks|fixes|sets|requires|asks|lists|gives|states)([^a-z]|$)/) hit()
		}
		function hit() { printf "    %s:%d: %s\n", f, at, first }' "$f"
done)
[ -z "$subject_leak" ] || report \
	"a runner's message names one project, or cites a page of one subject" \
	"$subject_leak" \
	"A runner speaks to every project that calls it. Take the sentence from" \
	"the call site, where the project's own subject is quoted once (c_make's" \
	"quotes, c_function's allocfail_rule, c_program's memory_rule, and" \
	"runner_quotes() for a runner one project calls), or say the rule the" \
	"layer applies and whose rule it is."

# ---------------------------------------------------------------------------
# N. A hint that can fire at first red asks a question; it never lists steps.
#
# ft_display_file's only hint (C 10 ex00, and its Reloaded twin ex27) opened
# with the program's whole main path, step by step, and it had no case label,
# so the untouched stub printed it on the very first run. It shipped in two
# projects of the public template. docs/design.md already said a hint "does
# not name the algorithm"; nothing checked it, and a review that looked for
# questions would have passed it, because its second sentence was one.
#
# The rows checked are the ones a student can meet before writing anything:
#   - a row with no case label, which fires on any failure;
#   - the first three rows of a clues*.tsv: a stub fails nearly every case,
#     three is the cap, and the nothing-matches fallback, header_check and
#     valgrind_test print the first three whatever failed;
#   - every row of a shell exercise's clues.tsv: the exercise runs as a single
#     case, so every row fires at once (three shown, CLUE_MODE=all the rest);
#   - every row of a file whose rows name a program's cases (c_program's
#     "name", which diff_output.sh and valgrind_test.sh take as --case). A
#     program case is a test of its own, and the rows keyed to OTHER cases
#     drop out of it, so "the first three rows" means nothing there: a row
#     keyed to a case fires on that case's test wherever it sits, and one
#     keyed to "line N" or "valgrind" fires on every case's, from any row.
#     The three-row rule passed both from the tenth line of the file.
# diff_clues.txt is out of scope: its layer speaks only once the fixture is
# green, and its entries wrap across lines, so a per-line reading means nothing.
#
# The detector finds the MARKED forms of a step list: numbered steps, two
# sequencing words in one row (then, an adverbial first, next opening a
# sentence, finally or after that opening a clause, afterwards), or an
# instruction chained with "then" ("fold it, then cut it"). The last is the one
# ft_display_file's row had, with a single "then". A clause can open on "and"
# as well as on punctuation, so "..., and finally glue it" counts; "next" is
# the exception, because "and next to it" is a place, not a step. It also
# reports a row with no question in it at all: the rule asks for a question,
# and a statement that fires at first red hands over a fact the student has
# not asked for yet, often the fix itself (BSQ, the rushes and a dozen shell
# rows were statements until this check). Both are floors. An outline with no
# marker, or one wrapped around a single question, gets past it, so the rule
# in docs/design.md is still the author's to keep; this catches the forms that
# shipped.
#
# One false positive to know: a row that DESCRIBES an output's layout with two
# "then"s ("the address, then the bytes, then the characters") counts two
# sequencing words, although the order it gives is the output's, not a method.
# List the parts instead ("three parts per line: the address, the bytes and the
# characters"): a list already reads left to right. C 02 ex12's row was
# reworded that way.
first_red_steps() {  # first_red_steps FILE SHELL(0|1) [PROGRAM-CASE-NAMES]
	NAMES="${3:-}" awk -v shell="$2" '
	function steplike(text,   t, w, nw, i, prev, nx, j, mk, imp) {
		t = tolower(text)
		if ((t ~ /(^|[ \t(])1[.)]([ \t]|$)/ && t ~ /(^|[ \t(])2[.)]([ \t]|$)/) ||
		    (t ~ /(^|[^a-z])step 1([^0-9]|$)/ && t ~ /(^|[^a-z])step 2([^0-9]|$)/))
			return "numbered steps"
		# Punctuation becomes its own token, so "then" can be read against
		# what stands on either side of it. A dash reads as a comma.
		gsub(/—|–/, " , ", t)
		gsub(/[.;:!?]/, " . ", t)
		gsub(/,/, " , ", t)
		gsub(/[^a-z0-9_., ]/, " ", t)
		nw = split(t, w, / +/)
		mk = 0
		imp = ""
		for (i = 1; i <= nw; i++) {
			prev = (i > 1) ? w[i - 1] : "."
			nx = (i < nw) ? w[i + 1] : "."
			if (w[i] == "then") {
				mk++
				# "then" opening a clause, followed by a bare verb: an
				# instruction. "then the title", "then returns it" and
				# "then two" describe rather than instruct, and do not count.
				if (prev ~ /^(\.|,|and|)$/ && nx ~ /^[a-z]+$/ && !(nx in STOP) &&
				    nx !~ /(s|ed|ing|ly)$/)
					imp = "then " nx
			} else if (w[i] == "first") {
				# "the first page" is an ordinal; "fold it first" is a step.
				if (!(prev in DET)) mk++
			} else if (w[i] == "next") {
				if (prev ~ /^(\.|,|)$/) mk++
			} else if (w[i] == "finally") {
				if (prev ~ /^(\.|,|and|)$/) mk++
			} else if (w[i] == "afterwards") {
				mk++
			} else if (w[i] == "after" && nx == "that") {
				j = (i + 2 <= nw) ? w[i + 2] : "."
				if (prev ~ /^(\.|,|and|)$/ || j ~ /^(\.|,)$/) mk++
			}
		}
		if (imp != "") return "an instruction chained with \"" imp "\""
		if (mk >= 2) return mk " sequencing words"
		if (text !~ /\?/) return "no question"
		return ""
	}
	BEGIN {
		n = split("the a an its it their they them you your this that these " \
			"those what which who whose how why when where whether is are was " \
			"were be been does did has had have can could will would should " \
			"must may might not no only also still again each every one two " \
			"three four five six seven eight nine ten all both either neither " \
			"some any more less same other another at in on for from with to " \
			"by of into onto over under as than so if then and or but nothing " \
			"none there here we our my he she his her", s, " ")
		for (i = 1; i <= n; i++) STOP[s[i]] = 1
		n = split("the a an its their your his her this that these those " \
			"which whose each every very whichever", s, " ")
		for (i = 1; i <= n; i++) DET[s[i]] = 1
		n = split(ENVIRON["NAMES"], s, "\n")
		prog = 0
		for (i = 1; i <= n; i++) if (s[i] != "") prog = 1
	}
	/^[ \t]*#/ || /^[ \t]*$/ { next }
	{
		k++
		nf = split($0, f, "\t")
		keyed = 0
		for (i = 2; i <= nf; i++) if (f[i] != "") keyed = 1
		if (!shell && !prog && keyed && k > 3) next
		why = steplike(f[1])
		if (why != "")
			printf "    line %d (%s): %s...\n", FNR, why, substr(f[1], 1, 60)
	}' "$1"
}

for _m in $MODULES; do
	# The shell exercises of this module, as exNN words: every row of theirs is
	# printed on any failure.
	_shell_ex=$(awk '
		/^shell_exercise\(/ { s = 1 }
		s && match($0, /num[ \t]*=[ \t]*"[0-9]+"/) {
			n = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", n)
			print "ex" n; s = 0
		}' "$_m/BUILD.bazel" | tr '\n' ' ')
	for c in "$_m"/tests/ex*/clues*.tsv; do
		[ -f "$c" ] || continue
		_ex=${c%/*}
		_ex=${_ex##*/}
		_sh=0
		case " $_shell_ex " in
			*" $_ex "*) _sh=1 ;;
		esac
		_names=$(printf '%s\n' "$_prog_cases" | awk -F'\t' -v d="${c%/*}" '$1 == d { print $2 }')
		steps=$(first_red_steps "$c" "$_sh" "$_names")
		[ -z "$steps" ] || report \
			"$c has a first-red hint written as steps or as a statement" \
			"$steps" \
			"This row can fire before the student has written anything: it has" \
			"no case label, is among the file's first three rows, belongs to a" \
			"program whose cases (all of which the stub fails) each show their own" \
			"rows, or to a shell exercise, whose rows all fire at once. Written as" \
			"steps, it is" \
			"the exercise's outline handed over at the moment the exercise asks" \
			"them to find it; written as a statement, it hands over a fact they" \
			"have not asked for yet, often the fix. Ask about the concept instead" \
			"-- which man page, which sentence of the subject, what happens when" \
			"-- and let the student put the steps in order. See docs/design.md," \
			"'Feedback names the bug class, never the algorithm'."
	done
done

# The "why" of each row of docs/reference.md's "Targets raised above their
# layer" is a hint too: rl__raised prints it under that target's red, often
# before any other. It is read as a hint is, from a file of reference.md's
# own line count holding the why cells alone (raised_whys), so a report
# names reference.md's line: here for the step markers, and below for a
# wider type. Not for a question: a why says why a test sits where it does,
# no fact about how to write the answer, and that it states no expected
# value is the author's to keep (docs/design.md).
raised_whys() {  # raised_whys FILE: reference.md's why cells, at their lines
	awk -F'|' '
		/^## / { sec = $0 }
		{
			w = ""
			if (sec == "## Targets raised above their layer" && $0 ~ /^\| `\/\/[^`]+` \| [a-z]+ \|/) {
				w = $4
				for (i = 5; i < NF; i++) w = w "|" $i
				gsub(/^ +| +$/, "", w)
			}
			print w
		}' docs/reference.md > "$1"
}
_whys="$lex_d/raised_whys"
: > "$_whys"
if [ -f docs/reference.md ]; then
	raised_whys "$_whys"
	steps=$(first_red_steps "$_whys" 1 | grep -v '(no question)')
	[ -z "$steps" ] || report \
		"docs/reference.md has a raised target's why written as steps" \
		"$(printf '%s\n' "$steps" | sed 's/^    line /    docs\/reference.md:/')" \
		"rl__raised prints this cell under the target's red, before the student" \
		"has asked for anything. Say why the test sits above its layer -- the" \
		"sentence the subject leaves open, the reading this target holds -- and" \
		"never the order in which to write the answer (docs/design.md)."
fi

# ---------------------------------------------------------------------------
# N. A hint about a value that does not fit names no type to widen into.
#
# Four clues once answered an overflow with "a wider type" or "a type wide
# enough" (finding 060), and the ilp32 layer, run on the same exercise,
# then failed the long the student reached for: C promises long only 32
# bits, as on the box the layer builds for. The owner's answer (WP-75): a
# hint asks whether the value has to be formed at all, or whether every
# type it passes through holds it on every platform, and points at what C
# promises about each type's width (docs/testing.md, under ilp32) as
# knowledge; it never names a type to widen into, nor dictates a
# construction. Two diff hints, C 04 ex03's and ex05's, still answered "the
# accumulator's type" after that (found twice in wave 5), so this reads
# every hint a module ships: the hint column of each clues*.tsv row, and
# each line of a diff_clues*.txt, a readings target's included ('#' lines
# are maintainers' and never printed). A diff hint wraps, so each line of a
# legend is read joined to the one before it too, for a phrase split across
# a line end. The forms it knows: wider/widen/wide enough, a bigger,
# larger or longer type or integer, a type (that is) big or large enough,
# the accumulator's type, and moving it into a long (a long string is no
# type). A hint that recommends a type in other words gets past them, so
# the rule is still the author's to keep. A hint about a counter narrower
# than int (Rush 00's 128 or 256 wide) names the variable's type, not one
# to move to, and is not one of these. The raised targets' why cells
# (raised_whys, above) are read too.
widen_lines() {  # widen_lines FILE NAME: the lines of a hint file that name a wider type
	awk -F'\t' -v f="$2" '
		function widens(t) {
			return t ~ /wider|widen|wide enough|(big|large)( enough)? type|type (that is )?(big|large|wide) enough/ ||
			    t ~ /accumulator.?s type|(larger|bigger|longer) (integer )?type|(larger|bigger) integer/ ||
			    t ~ /(use|switch to|move it to|into|store it in|hold it in) (a |an )?(long long|unsigned long|long|int64_t|size_t)([.,;:?!)]|$| instead| variable| accumulator)/
		}
		/^[ \t]*#/ { next }
		{
			t = tolower(f ~ /\.tsv$/ ? $1 : $0)
			hit = widens(t)
			if (hit)
				printf "    %s:%d: %s\n", f, NR, substr($0, 1, 70)
			else if (f ~ /diff_clues[^\/]*\.txt$/ && pn && !phit) {
				j = pt " " t
				gsub(/[ \t]+/, " ", j)
				if (widens(j))
					printf "    %s:%d: %s (wrapped onto line %d)\n", f, pn, substr(pr, 1, 70), NR
			}
			pt = t; pr = $0; pn = NR; phit = hit
		}' "$1"
}
widen_bad=$(for _m in $MODULES; do
	for _c in "$_m"/tests/ex*/clues*.tsv "$_m"/tests/ex*/diff_clues*.txt; do
		[ -f "$_c" ] || continue
		widen_lines "$_c" "$_c"
	done
done
widen_lines "$_whys" docs/reference.md)
[ -z "$widen_bad" ] || report \
	"a hint answers an overflow with a wider type" \
	"$widen_bad" \
	"C promises long only 32 bits, the same as int on the box the ilp32 layer" \
	"builds for, so a hint that sends the student to a wider type sends them" \
	"to the construction that layer fails. Ask whether the value has to be" \
	"formed at all -- does anything computed on the way to it not fit? -- and" \
	"point at what C promises about each type's width: docs/testing.md, under" \
	"ilp32 (WP-75 in TODO.md section 23)."

# ---------------------------------------------------------------------------
# N. A reading is named only as this harness's, and only in a hint a strict
#    test prints.
#
# The owner's ruling of 2026-10-03 (AGENTS.md section 2; docs/design.md): only
# the strict target that tests one reading of a sentence the subject leaves
# open may state that reading, in its own hint and its own row of
# docs/reference.md, always as "this harness's reading" and never as the
# subject's; no basic hint, clue or doc names it. Before it, one repository
# named a reading seven ways ("this repo's reading", "the reading this target
# takes", "the reading taken", "a reading of this harness", "this table
# reads", "these strict cases read ... as", "strict reads ... as"), and two
# of Rush 02's rows that stated a strict reading were keyed to the basic case
# beside it, so the basic red printed the reading (wave 6).
#
# The parts a machine can read:
#
#  THE WORDING. A reading is named by that label and by no other name: in
#  every hint (a clues*.tsv row's hint, a line of a diff_clues*.txt), every
#  line a check script or a runner (tools/*.sh) prints, a raised target's why
#  in docs/reference.md, and every page that ships (the *.md files outside
#  the zone, but the maintainer's TODO.md, HISTORY.md and docs/publishing.md).
#  In a hint, a script, a runner or a why the verbs it was stated with count
#  too ("strict reads", "this table reads", "this harness reads ... as" or
#  "this check reads ... as", up to four words between); a page may describe a
#  target in its own words. The reference is no owner of a reading either
#  ("the reference's reading", "the oracle's"): it holds this harness's. A
#  sentence wraps, so a line is read with the one before it: a legend's and a
#  page's as they are, a script's by what each line prints (between its
#  first quote and its last), as wave 6's review found diff_output.sh calling
#  a status of this repo's rule "this repo's reading" over two echo lines.
#
#  WHERE THE LABEL IS. A hint that says "this harness's reading" is one only
#  a strict test prints:
#   - a clue file whose every test sits at strict, read from the BUILD file:
#     a call's `clues =` is its basic tests', and a case's or a reading's
#     "clues" sits at its "level", basic where it names none;
#   - in a program's one keyed clues.tsv, a row keyed only to cases at
#     strict, or to a readings corpus's --case (a `_readings` target sits at
#     strict by its suffix); a row keyed to nothing fires on every case,
#     basic ones too;
#   - a check script a shell exercise's `readings` names, never the
#     exercise's check.sh, which its basic output test runs;
#   - a readings corpus's own legend (a c_diff's `readings` "diff_clues"),
#     which exNN_readings alone prints, at strict by the diff layer unless
#     its "level" raises it; its ASan twin is handed no legend (defs.bzl).
#     A plain corpus's legend never carries it, reported below (V42).
#  A hint at basic that carries it is reported, and one above strict too, a
#  raised readings corpus's legend among them: a case there is a convention
#  of this repo's, never a reading.
#
#  A PAGE STATES A READING only in its target's own row of docs/reference.md
#  (rd_states, below), when it states it with the label.
#
# A reading named in other words (a passive "is read as" among them: too
# many sentences say it of a byte or a path), a page that states one without
# the label, and whether the hint that carries the label is the reading's own
# target's, are the author's (docs/new-project.md, item 44).
rd_other='this (repo|repository)\047s (own )?reading|reading (this|the) (repo|repository|harness|target|table|case) (takes|took|chose|holds)|the reading taken|(a|one) reading of this (harness|repo|repository)|(repo|repository|harness|target|table|case) takes one reading|the subject\047s (own )?reading|(reference|oracle)\047s (own )?reading'
rd_w='([[:blank:]]+[^[:blank:]]+)?'
rd_verb="(^|[^a-z])(strict|this table|this target|this strict case|these strict cases) reads?([^a-z]|\$)|this (harness|check) reads?${rd_w}${rd_w}${rd_w}${rd_w}[[:blank:]]+as([^a-z]|\$)"
rd_label='this harness\047s reading'
# rd_words FILE KIND [NAME]: the lines of FILE that name a reading in other
# words than the label, as "    NAME:LINE: excerpt". KIND says what a line
# is: tsv (a clue row, whose first field is the hint), legend (a diff legend,
# which wraps), sh (a script: comment lines are not printed, and what a line
# prints wraps onto the next), why (the why cells of docs/reference.md, at
# their lines) or page (prose: the other names only, and it wraps). A
# typographic apostrophe reads as a plain one, and so does a shell's '"'"'.
rd_words() {
	awk -v kind="$2" -v name="${3:-$1}" -v other="$rd_other" -v verb="$rd_verb" '
		function norm(s) {
			gsub(/\342\200\231/, "\047", s)
			gsub(/\047\042\047\042\047/, "\047", s)
			return tolower(s)
		}
		function named(t) { return t ~ other || (kind != "page" && t ~ verb) }
		# What a line of a script says, to be read with the next: the text
		# between its first quote and its last (the words of an echo or a
		# printf), or the whole line where it has none.
		function said(t) {
			if (kind != "sh" || t !~ /["\047]/) return t
			sub(/^[^"\047]*["\047]/, "", t)
			sub(/["\047][^"\047]*$/, "", t)
			return t
		}
		kind != "why" && /^[[:blank:]]*#/ { pn = 0; next }
		# The rows of the raised targets in reference.md are read as whys, above.
		kind == "page" && name == "docs/reference.md" && /^\| `\/\// { pn = 0; next }
		{
			if (kind == "tsv") { split($0, f, "\t"); t = norm(f[1]) }
			else t = norm($0)
			hit = named(t)
			if (hit)
				printf "    %s:%d: %s\n", name, NR, substr($0, 1, 80)
			else if ((kind == "legend" || kind == "page" || kind == "sh") && pn && !phit) {
				j = pt " " said(t)
				gsub(/[[:blank:]]+/, " ", j)
				if (named(j))
					printf "    %s:%d: %s (wrapped onto line %d)\n", name, pn, substr(pr, 1, 80), NR
			}
			pt = said(t); pr = $0; pn = NR; phit = hit
		}' "$1"
}
# The pages that ship: every *.md outside the zone, but the maintainer's.
rd_pages=$(text_files -name '*.md' ! -path ./TODO.md ! -path ./HISTORY.md \
	! -path ./docs/publishing.md ! -path './tools/tests/*' -print |
	sed 's|^\./||' | sort)
rd_bad=$(
	for _m in $MODULES; do
		for _c in "$_m"/tests/ex*/clues*.tsv; do
			[ -f "$_c" ] && rd_words "$_c" tsv
		done
		for _c in "$_m"/tests/ex*/diff_clues*.txt; do
			[ -f "$_c" ] && rd_words "$_c" legend
		done
		for _c in "$_m"/tests/ex*/*.sh; do
			[ -f "$_c" ] && rd_words "$_c" sh
		done
	done
	for _c in tools/*.sh; do
		[ "$_c" = tools/conventions.sh ] || rd_words "$_c" sh
	done
	rd_words "$_whys" why docs/reference.md
	printf '%s\n' "$rd_pages" | while IFS= read -r _c; do
		[ -z "$_c" ] || rd_words "$_c" page
	done
)
[ -z "$rd_bad" ] || report \
	"a reading is named in other words than \"this harness's reading\"" \
	"$rd_bad" \
	"The owner's ruling (2026-10-03, AGENTS.md section 2): the strict target" \
	"that tests one reading of a sentence the subject leaves open states it" \
	"in its own hint and its row of docs/reference.md, always as \"this" \
	"harness's reading\", never as the subject's. One label is what lets this" \
	"script find a reading wherever it is named, and tell the student whose" \
	"it is; a page that names the target may say so in its own words, never" \
	"the reading itself."

# A page states a reading -- the label, then what the reading is ("this
# harness's reading is", "...:", "takes", "covers") -- only in the one place
# the ruling gives it: the target's own row of docs/reference.md, a raised
# target's row or a cell that opens with the target's name ("`exNN_literal`,
# this harness's reading: ..."). Wave 6's review found two rows of the
# target-name table (`_newest_first`, `_regular`) stating the shell readings
# a second time, beside each exercise's own row. A sentence wraps, so a line
# is read with the one before it.
rd_state='this harness\047s reading( of "[^"]*")?([[:blank:]]+(is|takes|covers)([^a-z]|$)|[[:blank:]]*:)'
rd_states() {
	awk -v name="$1" -v state="$rd_state" '
		function norm(s) {
			gsub(/\342\200\231/, "\047", s)
			return tolower(s)
		}
		function own(t) {
			return name == "docs/reference.md" &&
				(t ~ /^\| `\/\// || t ~ /`ex(nn|[0-9][0-9])_[a-z0-9_]+`, this harness\047s reading/)
		}
		/^[[:blank:]]*#/ { pn = 0; next }
		{
			t = norm($0); o = own(t)
			hit = !o && t ~ state
			if (hit)
				printf "    %s:%d: %s\n", name, NR, substr($0, 1, 80)
			else if (pn && !phit && !o && !po) {
				j = pt " " t
				gsub(/[[:blank:]]+/, " ", j)
				if (j ~ state)
					printf "    %s:%d: %s (wrapped onto line %d)\n", name, pn, substr(pr, 1, 80), NR
			}
			pt = t; pr = $0; pn = NR; phit = hit; po = o
		}' "$1"
}
rd_st=$(printf '%s\n' "$rd_pages" | while IFS= read -r _c; do
	[ -z "$_c" ] || rd_states "$_c"
done)
[ -z "$rd_st" ] || report \
	"a page states a reading outside its target's row of docs/reference.md" \
	"$rd_st" \
	"The owner's ruling (2026-10-03, AGENTS.md section 2): only the strict" \
	"target's own hint and its own row of docs/reference.md state the reading" \
	"it tests. Any other page, and any other row, names the target that holds" \
	"one reading and the question it answers, never the reading: a second" \
	"statement is a second thing to keep in step, and a page a student reads" \
	"first."

# A runner points at a reading; it never states one (V41's review). A
# runner (tools/*.sh) is shared by every project that calls it, and the
# reading is the strict target's to state, in the hint its call site hands
# over and its row of docs/reference.md. Rush 01's runner printed "Under this
# harness's reading (its hints below), the values are single digits ..." --
# the label, then the reading -- and nothing saw it: the rules above read a
# runner for other names and a page for "is", "takes", "covers" or a colon.
# So in what a runner prints, the label (with "of it", or of a quoted
# sentence, and a parenthesis after it, as they come) is followed by the end
# of what it says, or by a word that points: at the input at hand ("this
# argument", "these"), at where the reading is stated ("which its hints
# below state"), or at whose it is ("never the subject's"). A colon, "is",
# "takes", "covers" or any other word there is a reading stated. A sentence
# that names its rule first ("That a Notice fails is this harness's
# reading"), as a mode only a strict target runs may, is the author's. What a
# line prints is read with the line before it, as rd_words reads it, and a
# shell's \047 or '"'"' reads as a plain apostrophe.
rd_runner() {
	awk -v name="$1" -v label="$rd_label" '
		function norm(s) {
			gsub(/\342\200\231/, "\047", s)
			gsub(/\047\042\047\042\047/, "\047", s)
			gsub(/\\047/, "\047", s)
			return tolower(s)
		}
		function said(t) {
			if (t !~ /["\047]/) return t
			sub(/^[^"\047]*["\047]/, "", t)
			sub(/["\047][^"\047]*$/, "", t)
			return t
		}
		function states(t,   r, w) {
			while (match(t, label)) {
				r = substr(t, RSTART + RLENGTH)
				t = r
				sub(/^[[:blank:]]+of[[:blank:]]+(it|"[^"]*")/, "", r)
				sub(/^[[:blank:]]*\([^)]*\)/, "", r)
				if (r ~ /^[[:blank:]]*:/ || r ~ /^[[:blank:]]+(is|takes|covers)([^a-z]|$)/) return 1
				sub(/^[[:blank:]]*,?[[:blank:]]*/, "", r)
				if (r !~ /^[a-z]/) continue
				w = r
				sub(/[^a-z].*/, "", w)
				if (w !~ /^(this|these|never|which|its)$/) return 1
			}
			return 0
		}
		/^[[:blank:]]*#/ { pn = 0; next }
		{
			t = said(norm($0))
			hit = states(t)
			if (hit)
				printf "    %s:%d: %s\n", name, NR, substr($0, 1, 80)
			else if (pn && !phit) {
				j = pt " " t
				gsub(/[[:blank:]]+/, " ", j)
				if (states(j))
					printf "    %s:%d: %s (wrapped onto line %d)\n", name, pn, substr(pr, 1, 80), NR
			}
			pt = t; pr = $0; pn = NR; phit = hit
		}' "$1"
}
rd_run=$(for _c in tools/*.sh; do
	[ "$_c" = tools/conventions.sh ] || rd_runner "$_c"
done)
[ -z "$rd_run" ] || report \
	"a runner states a reading after its label" \
	"$rd_run" \
	"A runner is shared by every project that calls it; the reading belongs" \
	"to the strict target that tests it, in the hint its call site hands" \
	"over and its row of docs/reference.md (the owner's ruling, 2026-10-03," \
	"AGENTS.md section 2). After \"this harness's reading\", say what it makes" \
	"of the input at hand (\"this argument\"), where it is stated (\"which its" \
	"hints below state\") or whose it is (\"never the subject's\"), never what" \
	"it is."

# Who prints each hint, from the BUILD files: one line a fact,
#   C <folder> <file> <level>   a clue file handed to tests at that level
#   P <folder> <case> <level>   a case (or a reading) of the exercise
#   S <folder> <script>         a reading's check script (shell_exercise)
#   D <folder> <file>           the legend a c_diff's plain corpus prints
#   R <folder> <file> <level>   the legend a c_diff's readings corpus prints,
#                               at its "level" (2, strict, where it names none)
# A call runs from its first-column `name(` line to the next line that
# starts in the first column (buildifier's layout), read token by token, so
# a call on one line and one laid out over many read alike. A dict one brace
# deep is a case, a reading, or a shell exercise's readings; `level` is a
# number, and a case that names none sits at basic.
rd_owners=$(for _m in $MODULES; do
	[ -f "$_m/BUILD.bazel" ] || continue
	awk -v m="$_m" '
		function endcall(   i, f) {
			if (incall && num != "") {
				f = m "/tests/ex" num
				if (kv["clues"] != "")
					print "C\t" f "\t" kv["clues"] "\t" (kv["level"] != "" ? kv["level"] : 1)
				if (call == "c_diff" && kv["diff_clues"] != "")
					print "D\t" f "\t" kv["diff_clues"]
				for (i = 1; i <= ne; i++) print et[i] "\t" f "\t" ev[i]
			}
			incall = 0; num = ""; ne = 0; split("", kv); pd = 0; bd = 0; kd = 0
			kw = ""; eq = 0; key = ""
		}
		function emit(t, v) { et[++ne] = t; ev[ne] = v }
		function closedict(   k, lv) {
			lv = (dv["level"] != "") ? dv["level"] : 1
			if (dv["clues"] != "") emit("C", dv["clues"] "\t" lv)
			if (dv["name"] != "" && (dkw == "cases" || dkw == "readings")) emit("P", dv["name"] "\t" lv)
			if (call == "shell_exercise" && dkw == "readings")
				for (k in dv) if (dv[k] ~ /\.sh$/) emit("S", dv[k])
			if (call == "c_diff" && dkw == "readings" && dv["diff_clues"] != "")
				emit("R", dv["diff_clues"] "\t" ((dv["level"] != "") ? dv["level"] : 2))
			split("", dv)
		}
		function value(v) {
			if (pd == 1 && bd == 0 && kd == 0 && eq && kw != "") {
				kv[kw] = v
				if (kw == "num") num = v
			} else if (bd == 1 && key != "") dv[key] = v
			key = ""; eq = 0
		}
		/^[A-Za-z_][A-Za-z0-9_]*\(/ {
			endcall()
			incall = 1
			call = $0; sub(/\(.*/, "", call)
		}
		/^[^ \t#)\]]/ && !/^[A-Za-z_][A-Za-z0-9_]*\(/ { if (incall) endcall(); next }
		incall {
			s = $0; L = length(s)
			for (i = 1; i <= L; i++) {
				c = substr(s, i, 1)
				if (c == "#") break
				if (c == "\"") {
					for (j = i + 1; j <= L && substr(s, j, 1) != "\""; j++)
						if (substr(s, j, 1) == "\\") j++
					str = substr(s, i + 1, j - i - 1)
					i = j
					if (bd == 1 && substr(s, i + 1) ~ /^[ \t]*:/) { key = str; continue }
					value(str)
				} else if (c ~ /[0-9]/) {
					t = c
					while (i < L && substr(s, i + 1, 1) ~ /[0-9]/) { i++; t = t substr(s, i, 1) }
					value(t)
				} else if (c ~ /[A-Za-z_]/) {
					t = c
					while (i < L && substr(s, i + 1, 1) ~ /[A-Za-z0-9_]/) { i++; t = t substr(s, i, 1) }
					if (pd == 1 && bd == 0 && kd == 0) { kw = t; eq = 0 }
					else if (t == "True" || t == "False") value(t)
				} else if (c == "=") {
					if (substr(s, i + 1, 1) == "=") i++
					else if (pd == 1 && bd == 0 && kd == 0) eq = 1
				} else if (c == "(") pd++
				else if (c == ")") pd--
				else if (c == "[") kd++
				else if (c == "]") kd--
				else if (c == "{") { if (++bd == 1) { split("", dv); dkw = kw; key = "" } }
				else if (c == "}") { if (bd-- == 1) closedict(); key = "" }
				else if (c == "," && pd == 1 && bd == 0 && kd == 0) { kw = ""; eq = 0 }
			}
		}
		END { endcall() }' "$_m/BUILD.bazel"
done)
# rd_label_rows FILE MODE [STRICT [ABOVE]]: the rows of FILE that carry the
# label and a test other than a strict one prints, each as "basic<TAB>row"
# or "above<TAB>row". MODE basic or above: every such row, the file being one
# a test at that level is handed. MODE keyed: a program's keyed rows, STRICT
# the cases at strict and ABOVE those above it, one per line; a row keyed to
# any other case, or to none, is basic. MODE sh: a check script's printed
# lines, which its basic output test prints.
rd_label_rows() {
	STRICT="${3:-}" ABOVE="${4:-}" awk -v mode="$2" -v label="$rd_label" -v f="$1" '
		BEGIN {
			n = split(ENVIRON["STRICT"], k, "\n"); for (i = 1; i <= n; i++) if (k[i] != "") st[k[i]] = 1
			n = split(ENVIRON["ABOVE"], k, "\n"); for (i = 1; i <= n; i++) if (k[i] != "") up[k[i]] = 1
		}
		/^[[:blank:]]*#/ { next }
		{
			t = $0
			gsub(/\342\200\231/, "\047", t)
			gsub(/\047\042\047\042\047/, "\047", t)
			if (mode != "sh") { split(t, x, "\t"); t = x[1] }
			if (tolower(t) !~ label) next
			lv = (mode == "above") ? "above" : "basic"; why = ""
			if (mode == "keyed") {
				nk = split($0, x, "\t"); low = ""; high = ""; keyed = 0
				for (i = 2; i <= nk; i++) {
					if (x[i] == "") continue
					keyed = 1
					if (x[i] in st) continue
					if (x[i] in up) high = high (high == "" ? "" : ", ") x[i]
					else low = low (low == "" ? "" : ", ") x[i]
				}
				if (!keyed) why = " (keyed to no case, so every case)"
				else if (low != "") why = " (keyed to " low ")"
				else if (high != "") { lv = "above"; why = " (keyed to " high ", above strict)" }
				else next
			}
			printf "%s\t    %s:%d: %s%s\n", lv, f, NR, substr($0, 1, 70), why
		}' "$1"
}
rd_rows=$(for _m in $MODULES; do
	for _c in "$_m"/tests/ex*/clues*.tsv; do
		[ -f "$_c" ] || continue
		_d=${_c%/*}
		_b=${_c##*/}
		if [ "$_b" = clues.tsv ] &&
			printf '%s\n' "$_prog_cases" | awk -F'\t' -v d="$_d" '$1 == d { f = 1 } END { exit !f }'; then
			_st=$( { printf '%s\n' "$rd_owners" | awk -F'\t' -v d="$_d" '$1 == "P" && $2 == d && $4 == 2 { print $3 }'
				printf '%s\n' "$_prog_cases" | awk -F'\t' -v d="$_d" '$1 == d && $2 ~ /readings$/ { print $2 }'; } )
			_hi=$(printf '%s\n' "$rd_owners" | awk -F'\t' -v d="$_d" '$1 == "P" && $2 == d && $4 > 2 { print $3 }')
			rd_label_rows "$_c" keyed "$_st" "$_hi"
		else
			# Who the file is handed to: basic where a call or a case at
			# basic is, or where no BUILD line names it; above where only
			# tests above strict are, past one at strict.
			_lv=$(printf '%s\n' "$rd_owners" | awk -F'\t' -v d="$_d" -v b="$_b" '
				$1 == "C" && $2 == d && $3 == b { n++; if ($4 < 2) lo = 1; else if ($4 > 2) hi = 1 }
				END { print (!n || lo) ? "basic" : (hi ? "above" : "strict") }')
			[ "$_lv" = strict ] || rd_label_rows "$_c" "$_lv"
		fi
	done
	for _c in "$_m"/tests/ex*/*.sh; do
		[ -f "$_c" ] || continue
		printf '%s\n' "$rd_owners" | awk -F'\t' -v d="${_c%/*}" -v b="${_c##*/}" '
			$1 == "S" && $2 == d && $3 == b { f = 1 } END { exit !f }' || rd_label_rows "$_c" sh
	done
done)
rd_basic=$(printf '%s\n' "$rd_rows" | awk -F'\t' '$1 == "basic" { sub(/^[^\t]*\t/, ""); print }')
[ -z "$rd_basic" ] || report \
	"a hint a basic test prints names this harness's reading" \
	"$rd_basic" \
	"No basic hint names the reading of a sentence the subject leaves open" \
	"(the owner's ruling, 2026-10-03, AGENTS.md section 2): a correct answer" \
	"under either reading is green at basic, and a hint printed there reads as" \
	"the rule. Ask which sentence decides, and name the target that holds one" \
	"reading if you must; the reading itself goes in that target's own hint:" \
	"a clue file only its strict cases are handed, a keyed row naming only" \
	"them, or the check script its shell exercise's readings names."
# rd_legend_label FILE: the lines of a diff legend that carry the label, as
# "    FILE:LINE: text". A legend wraps, so a line is read with the one
# before it.
rd_legend_label() {
	awk -v f="$1" -v label="$rd_label" '
		{
			t = $0
			gsub(/\342\200\231/, "\047", t)
			sub(/^[[:blank:]]+/, "", t)
			if (tolower(t) ~ label) printf "    %s:%d: %s\n", f, NR, t
			else if (NR > 1 && tolower(p " " t) ~ label && tolower(p) !~ label)
				printf "    %s:%d: %s (wrapped onto line %d)\n", f, NR - 1, p, NR
			p = t
		}' "$1"
}
# A readings corpus raised above strict ("level": 3 or 4) prints its legend
# there, so that legend is a hint above strict: C 11 ex06's, whose order of
# a byte above 0x7f is a convention of this repo's, says so in other words.
# Its ASan twin is handed no legend at all (defs.bzl, c_diff's `readings`).
rd_leg_above=$(printf '%s\n' "$rd_owners" | awk -F'\t' '$1 == "R" && $4 > 2 { print $2 "/" $3 }' | sort -u |
	while IFS= read -r _l; do
		[ -f "$_l" ] && rd_legend_label "$_l" | sed 's/$/ (a readings legend above strict)/'
	done)
rd_above=$(printf '%s\n' "$rd_rows" | awk -F'\t' '$1 == "above" { sub(/^[^\t]*\t/, ""); print }')
rd_above=$(printf '%s\n%s\n' "$rd_above" "$rd_leg_above" | sed '/^$/d')
[ -z "$rd_above" ] || report \
	"a hint a test above strict prints names this harness's reading" \
	"$rd_above" \
	"Only the strict target that tests one reading of a sentence the subject" \
	"leaves open states it (the owner's ruling, 2026-10-03, AGENTS.md section" \
	"2). A case above strict is a convention of this repo's where the" \
	"subject's words do not reach it (reference.md, \"Run contract\"), and its" \
	"hint says the rule is this repo's; a reading placed there by mistake" \
	"moves to strict, with its hint."
# And never in the legend of a plain diff corpus (V42). A c_diff's corpus
# holds only the cases every reading agrees on (docs/testing.md, "When a
# sentence has two readings"); the ones a reading decides are its
# `readings` corpus's, a target of its own, whose legend states it. C 04
# ex04 and ex05 and C 07 ex04 held a reading in the plain corpus, at strict
# by its layer, and their legends said "this harness's reading, at strict":
# the label is the part a machine sees. A plain legend may still name the
# target that holds a reading, in other words. A legend wraps, so a line is
# read with the one before it.
rd_plain=$(printf '%s\n' "$rd_owners" | awk -F'\t' '$1 == "D" { print $2 "/" $3 }' | sort -u |
	while IFS= read -r _l; do
		[ -f "$_l" ] && rd_legend_label "$_l"
	done)
[ -z "$rd_plain" ] || report \
	"a plain diff corpus's legend names this harness's reading" \
	"$rd_plain" \
	"A diff corpus holds only what every reading of the subject agrees on. A" \
	"case a reading decides goes to the c_diff's readings corpus, a target of" \
	"its own at strict (readings = {\"oracle_fn\": ..., \"diff_clues\": ...})," \
	"and its own legend states the reading; this one asks which sentence" \
	"decides, and may name that target."

# ---------------------------------------------------------------------------
# N. A check script runs the turn-in only through ck_run, and asks for it first.
#
# Three lessons from one student-test run, each of which cost a correct
# answer its explanation or handed a missing one a list of passes:
#
#   - Every check that ran a turned-in script sent its stderr to /dev/null and
#     never read its status, copying the idiom tools/shell_check.sh itself
#     taught. A script dash could not run showed content failures and a hint
#     about something else; one that printed the right names and then died on
#     an unclosed `if` passed 9/9. ck_run keeps both and shows them. So a
#     check script never runs a script itself, in any of the ways below.
#   - The checks went on after "x.sh exists" failed, and every check that
#     asserts an absence passed on the output of nothing. So the first check a
#     script registers is ck_require, which ends the list when it fails.
#   - A script dash cannot parse was never named as one. So a check script
#     that runs a script with `sh` through ck_run also calls ck_sh_parses.
#   - A check that builds a git repository read git's configuration from the
#     host: /etc/gitconfig, and the user's own (core.excludesFile, a pager,
#     commit signing, colour) whenever the check ran outside Bazel's HOME.
#     Each can change what the fixture holds or what the turn-in prints, so
#     the verdict depended on the machine (Shell 00 ex06, WP-29). So a check
#     script that runs git sets and exports GIT_CONFIG_NOSYSTEM, a HOME of
#     its own and XDG_CONFIG_HOME before its first git command, for the
#     fixture and the run alike: git reads $XDG_CONFIG_HOME/git/config, and
#     its default ignore file there, whenever that variable is set, whatever
#     HOME says, and a run outside Bazel's cleared environment inherits it.
#     Its git is found wherever a command can stand, by the split the first
#     rule uses (below): `h=$(git rev-parse HEAD)` and `cd r && git init` are
#     git commands as much as a line that starts with git. A git first run
#     inside a function defined above the settings is reported though the
#     settings come before the call: move the function below them.
#     It also unsets, before that first git, what a run outside Bazel's
#     cleared environment would inherit about where the repository is and
#     which configuration it takes (GIT_INHERITED, below).
#
# And one from a later fix (finding 026). A check whose program reads a fixed
# path is handed a fixture in its place by a preload library
# (tools/path_redirect.c), which ck_run loads into the turn-in's runs and
# nothing else, once shell_test.sh has proven it takes on the machine. A check
# script that sets LD_PRELOAD, or names the library itself, redirects its own
# reads too -- the reference's, and the run it makes on the machine's own
# file -- or runs the turn-in on a redirect nothing proved. So a check script
# names neither, outside a comment.
#
# And one from Shell 01 ex08's review. ck_run runs the turn-in with its stdin
# on /dev/null: a check that ran it inside a `while read` loop over its cases
# handed it the rest of the list, and a program that read its stdin swallowed
# every case after the first -- PASS over pairs that never ran. So a check
# that pipes into ck_run, or redirects its stdin (`... | ck_run`,
# `ck_run ... < file`, a here-document), feeds the turn-in nothing, and is
# reported: it reads as a test of input the program never gets. A loop's own
# `done < file` is the loop's, and is not one.
#
# A tests/exNN/check.sh that does not load the library at all is reported
# too, since none of this could reach it.
#
# What the first rule reads. Each line is split the way the shell splits it:
# quotes removed from each word, the commands inside $(...) and `...` read
# as commands of their own, redirections dropped. In each simple command, the
# words that run another command are stepped over -- assignments, `!`, `if`,
# `exec`, `command`, `env` and its flags, `timeout` and its duration, `nice`,
# `nohup`, `xargs`, `stdbuf`, and the library's own `ck LABEL` and
# `ck_require LABEL` -- and the command word left is reported when it is:
#   - a shell (sh, bash, dash, ksh, zsh, by any path) given anything but
#     `-c`: `ck "runs" sh "$D"`, `timeout 5 sh "$D"`, `env -i sh "$D"`;
#   - `./name`, or a name ending in .sh;
#   - the turn-in itself: a variable the script hands ck_require,
#     ck_sh_parses or ck_executable, or a positional parameter, alone or
#     after `./`, `.` or `source`;
#   - `eval`, whose words are read again as a command line.
# A `sh -c SCRIPT` is the check's own inline predicate, so it is not reported
# for itself: SCRIPT is read by these same rules, where `sh "$1"` or `"$1"` is
# the turn-in run by another name (`sh -c 'sh "$1" | grep -q .' _ "$D"`).
#
# Limits, each a way past this scan that no line-by-line reading closes. A
# turn-in some other program reads -- ft_magic through file(1) -- is the
# author's to route through ck_run; no scan can tell "file -m ft_magic" from
# any other use of file(1). A command word the script computes ("$SHELL",
# "$(printf sh)"), a program that runs its arguments that is not listed above
# (find -exec, busybox), and a shell reached through a function defined in
# another file are not seen. A here-document's body is skipped whole. The
# second rule reads the first line at line start that calls a check helper,
# so a helper function defined above ck_require that calls ck inside it would
# be misread.
shcheck_runs() {  # shcheck_runs FILE [git] -> each line that runs a script outside ck_run
	# The file is read twice: first for the names it gives the turn-in, then
	# for the lines that run it. With "git", the lines that run git instead,
	# in any of the places a command can stand (the git rule below).
	awk -v FIND="${2:-}" '
		# The index of the character that closes the bracket opened at i,
		# quotes and backslashes honoured; the end of s when nothing does.
		function closer(s, i, op, cl,   depth, c, q, n) {
			depth = 0; q = ""; n = length(s)
			for (; i <= n; i++) {
				c = substr(s, i, 1)
				if (q == "\047") { if (c == q) q = ""; continue }
				if (c == "\\") { i++; continue }
				if (q == "\"") { if (c == q) q = ""; continue }
				if (c == "\"" || c == "\047") { q = c; continue }
				if (c == op) depth++
				else if (c == cl && --depth == 0) return i
			}
			return n
		}
		function push(d, w) {
			if (REDIR[d]) { REDIR[d] = 0; return }
			NW[d]++; W[d, NW[d]] = w
		}
		# A word that names the turn-in: a variable handed to ck_require,
		# ck_sh_parses or ck_executable, or a positional parameter.
		function turnin(w,   v) {
			sub(/^\.\//, "", w)
			if (w ~ /^\$\{?([0-9@*])\}?$/) return 1
			if (w !~ /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$/) return 0
			v = w; gsub(/[${}]/, "", v)
			return (v in TURNIN)
		}
		# Split s into simple commands, judging each; the commands inside
		# $(...) and `...` are split and judged one depth down.
		function lex(s, d,   i, n, c, cw, has, j, e, inner) {
			NW[d] = 0; REDIR[d] = 0; n = length(s); cw = ""; has = 0
			for (i = 1; i <= n + 1; i++) {
				c = (i <= n) ? substr(s, i, 1) : "\n"
				if (c == "\\") {
					if (i < n) { cw = cw substr(s, i + 1, 1); has = 1 }
					i++; continue
				}
				if (c == "\047") {
					e = index(substr(s, i + 1), "\047")
					if (e == 0) e = n - i + 1
					cw = cw substr(s, i + 1, e - 1); has = 1; i += e; continue
				}
				if (c == "\"") {
					for (j = i + 1; j <= n; j++) {
						c = substr(s, j, 1)
						if (c == "\\") { cw = cw substr(s, j + 1, 1); j++; continue }
						if (c == "\"") break
						if (c == "$" && substr(s, j + 1, 1) == "(") {
							e = closer(s, j + 1, "(", ")")
							inner = substr(s, j + 2, e - j - 2)
							# $((...)) is arithmetic: no command in it.
							if (substr(s, j + 2, 1) != "(") lex(inner, d + 1)
							cw = cw "$(" inner ")"; j = e; continue
						}
						if (c == "`") {
							e = index(substr(s, j + 1), "`")
							if (e == 0) e = n - j + 1
							inner = substr(s, j + 1, e - 1)
							lex(inner, d + 1)
							cw = cw "`" inner "`"; j += e; continue
						}
						cw = cw c
					}
					i = j; has = 1; continue
				}
				if (c == "$" && substr(s, i + 1, 1) == "(") {
					e = closer(s, i + 1, "(", ")")
					inner = substr(s, i + 2, e - i - 2)
					if (substr(s, i + 2, 1) != "(") lex(inner, d + 1)
					cw = cw "$(" inner ")"; has = 1; i = e; continue
				}
				if (c == "$" && substr(s, i + 1, 1) == "{") {
					e = closer(s, i + 1, "{", "}")
					cw = cw substr(s, i, e - i + 1); has = 1; i = e; continue
				}
				if (c == "`") {
					e = index(substr(s, i + 1), "`")
					if (e == 0) e = n - i + 1
					inner = substr(s, i + 1, e - 1)
					lex(inner, d + 1)
					cw = cw "`" inner "`"; has = 1; i += e; continue
				}
				if (c == "#" && !has) { i = n; c = "\n" }
				if (c == " " || c == "\t") {
					if (has) push(d, cw)
					cw = ""; has = 0; continue
				}
				if (c == ">" || c == "<") {
					# 2>/dev/null: the fd number and the target are no words.
					if (has && cw !~ /^[0-9]+$/) push(d, cw)
					cw = ""; has = 0
					while (substr(s, i + 1, 1) ~ /[<>&|-]/) i++
					REDIR[d] = 1; continue
				}
				if (c ~ /[;&|()\n]/) {
					if (has) push(d, cw)
					cw = ""; has = 0
					judge(d); NW[d] = 0; REDIR[d] = 0; continue
				}
				cw = cw c; has = 1
			}
		}
		function judge(d,   k, n, w, j, rest) {
			n = NW[d]; k = 1
			while (k <= n) {
				w = W[d, k]
				if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || (w in KW)) { k++; continue }
				if (w == "ck" || w == "ck_require") { k += 2; continue }
				# What ck_run runs is the turn-in, or a program the check
				# chose: in the git reading it is a command like any other.
				# Past the options of ck_run, in any order (-C DIR and
				# --no-redirect), and then its output file.
				if (FIND != "" && w == "ck_run") {
					for (k++; k <= n; ) {
						if (W[d, k] == "-C") k += 2
						else if (W[d, k] == "--no-redirect") k++
						else break
					}
					k++
					continue
				}
				if (w in PREFIX) {
					for (k++; k <= n && W[d, k] ~ /^-/; k++) {
						if (W[d, k] == "--") { k++; break }
						if ((w SUBSEP W[d, k]) in TAKES) k++
					}
					if (w == "timeout") k++
					continue
				}
				break
			}
			if (k > n) return
			w = W[d, k]
			if (FIND != "") {
				if (w == FIND || substr(w, length(w) - length(FIND)) == "/" FIND) {
					HIT = 1; return
				}
			}
			if (w ~ /^(\/usr)?(\/bin\/)?(sh|bash|dash|ksh|zsh)$/) {
				for (j = k + 1; j <= n && W[d, j] ~ /^[-+][A-Za-z]+$/; j++)
					if (W[d, j] ~ /^-[A-Za-z]*c/) { lex(W[d, j + 1], d + 1); return }
				if (FIND == "") HIT = 1
				return
			}
			if (FIND != "") {
				if (w == "eval") {
					rest = ""
					for (j = k + 1; j <= n; j++) rest = rest " " W[d, j]
					lex(rest, d + 1)
				}
				return
			}
			if (w ~ /^\.\/./ || (w ~ /\.sh$/ && w !~ /[*?[]/) || turnin(w)) { HIT = 1; return }
			if ((w == "." || w == "source") && k < n && turnin(W[d, k + 1])) { HIT = 1; return }
			if (w == "eval") {
				rest = ""
				for (j = k + 1; j <= n; j++) rest = rest " " W[d, j]
				lex(rest, d + 1)
			}
		}
		BEGIN {
			split("if then else elif do done while until ! { } exec time command nohup", k, " ")
			for (i in k) KW[k[i]] = 1
			split("env timeout nice xargs stdbuf", k, " ")
			for (i in k) PREFIX[k[i]] = 1
			# The flags of those that take a value as the next word.
			split("env -u|env -C|env -S|timeout -s|timeout -k|timeout --signal|" \
			      "timeout --kill-after|nice -n|xargs -n|xargs -I|xargs -L|" \
			      "xargs -P|xargs -d|xargs -a|xargs -E|xargs -s|stdbuf -i|" \
			      "stdbuf -o|stdbuf -e", k, "|")
			for (i in k) { split(k[i], p, " "); TAKES[p[1], p[2]] = 1 }
		}
		# Pass 1: the names the script gives the turn-in.
		NR == FNR {
			if ($0 ~ /^[ \t]*(ck_require|ck_sh_parses|ck_executable)[ \t]/) {
				s = $0
				while (match(s, /\$\{?[A-Za-z_][A-Za-z0-9_]*/)) {
					v = substr(s, RSTART, RLENGTH); gsub(/[${]/, "", v)
					TURNIN[v] = 1
					s = substr(s, RSTART + RLENGTH)
				}
			}
			next
		}
		# A here-document body is data, read to its delimiter.
		hd != "" { t = $0; sub(/^\t*/, "", t); if (t == hd) hd = ""; next }
		/^[ \t]*#/ && acc == "" { next }
		{
			# A backslash-newline continues the command: judge it whole,
			# and report it at the line it starts on.
			if (acc == "") { at = FNR; whole = $0 } else whole = whole " " $0
			if (sub(/\\$/, "", $0)) { acc = acc $0 " "; next }
			line = acc $0
			acc = ""
			if (match(line, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
				hd = substr(line, RSTART, RLENGTH); gsub(/[<\-"\047 \t]/, "", hd)
			}
			HIT = 0
			lex(line, 0)
			if (HIT) printf "    line %d: %s\n", at, whole
		}' "$1" "$1"
}
shcheck_first() {  # shcheck_first FILE -> "LINE HELPER" of the first check it registers
	awk '
		/^[ \t]*#/ { next }
		match($0, /^[ \t]*ck(_eq|_require|_final_newline|_no_final_newline|_executable|_listed_at|_no_operator|_sh_parses)?([ \t]|$)/) {
			w = $0; sub(/^[ \t]*/, "", w); sub(/[ \t].*/, "", w)
			print FNR, w
			exit
		}' "$1"
}
shcheck_runs_sh() {  # shcheck_runs_sh FILE -> 0 when a ck_run in it runs sh
	awk '
		/^[ \t]*#/ && acc == "" { next }
		{
			# A ck_run whose command goes on over a backslash-newline is
			# read whole: the sh is often on the second line.
			if (sub(/\\$/, "", $0)) { acc = acc $0 " "; next }
			line = acc $0
			acc = ""
			if (line ~ /^[ \t]*ck_run[ \t]/ && line ~ /[ \t](\/bin\/)?sh([ \t]|$)/) {
				found = 1
				exit
			}
		}
		END { exit !found }' "$1"
}
# And one from wave 4's one renderer. A check script's own printing of what a
# run wrote -- `printf '  got: %s\n' "$out"`, `head -3 "$raw"` -- reached the
# log raw: a carriage return the turn-in printed read as nothing, an escape
# sequence repainted the terminal, and "42 file " beside "42 file" looked
# equal. The library shows it through the one renderer: ck_eq's two values,
# ck_detail's lines, ck_run's stderr block (tools/shell_check.sh). So a line
# that prints, by a command of its own (echo, printf, cat, head, tail; not
# piped on, not redirected, not inside a $(...)), a file ck_run wrote --
# its OUTFILE, OUTFILE.err -- or a variable set from one, or from such a
# variable, is reported. A count taken of one (wc, grep -c) is a number, and
# is not. Limits: a run made other than through ck_run, and a value passed
# through a function's arguments, are not followed.
shcheck_raw_prints() {  # shcheck_raw_prints FILE -> each line printing a run's bytes itself
	awk '
		function strip_subst(s,   out, i, n, c, depth) {
			out = ""; depth = 0; n = length(s)
			for (i = 1; i <= n; i++) {
				c = substr(s, i, 1)
				if (c == "$" && substr(s, i + 1, 1) == "(") { depth++; i++; continue }
				if (depth > 0) {
					if (c == "(") depth++
					else if (c == ")") depth--
					continue
				}
				out = out c
			}
			return out
		}
		function norm(w) { gsub(/"/, "", w); gsub(/[{}]/, "", w); return w }
		function mentions(s,   k) {
			for (k in T) if (index(s, k) > 0) return 1
			return 0
		}
		/^[ \t]*#/ { next }
		{
			line = $0
			if (match(line, /(^|[;&|{(]|then|do)[ \t]*ck_run[ \t]/)) {
				n = split(substr(line, RSTART + RLENGTH), w, /[ \t]+/)
				for (i = 1; i <= n; i++) {
					if (w[i] == "") continue
					if (w[i] == "-C") { i++; continue }
					if (w[i] == "--no-redirect") continue
					f = norm(w[i]); T[f] = 1; T[f ".err"] = 1
					break
				}
			}
			if (match(line, /^[ \t]*(local[ \t]+)?[A-Za-z_][A-Za-z0-9_]*=\$\(/)) {
				v = substr(line, RSTART, RLENGTH)
				sub(/^[ \t]*(local[ \t]+)?/, "", v); sub(/=.*/, "", v)
				r = substr(line, RSTART + RLENGTH)
				# A count (wc, grep -c): spelt w[c] so the require scan, which
				# reads command words, does not take it for a call of ours.
				if (r !~ /(^|[|;( \t])(w[c]|grep[ \t]+-[a-zA-Z]*c)[ \t]/ && mentions(norm(r))) T["$" v] = 1
			}
			bare = strip_subst(line)
			if (bare ~ /(^|[;&{(]|then|do|else)[ \t]*(echo|printf|cat|head|tail)([ \t]|$)/ &&
			    bare !~ /\|[ \t]*[a-z]/ && bare !~ />/ && mentions(norm(bare)))
				printf "    line %d: %s\n", FNR, $0
		}' "$1"
}
# What a check that runs git unsets first (the git rule, below).
GIT_INHERITED="GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT"
for f in $(for _m in $MODULES; do
	[ -d "$_m/tests" ] && find "$_m/tests" -name '*.sh' 2> /dev/null
done | sort); do
	# A check script that never loads the library escapes every rule below,
	# and is a checklist with no ck_report guard besides. shell_exercise runs
	# tests/exNN/check.sh, so that name is held to it.
	if ! grep -q 'SHELL_CHECK_LIB' "$f"; then
		case "$f" in
			*/check.sh) report "$f does not load tools/shell_check.sh" \
				"shell_exercise runs it with SHELL_CHECK_LIB set: start it with" \
				". \"\${SHELL_CHECK_LIB:?}\" and run the turn-in through ck_run, so" \
				"the rules this file keeps for check scripts reach it too." ;;
		esac
		continue
	fi
	shown=$(shcheck_raw_prints "$f")
	[ -z "$shown" ] || report \
		"$f prints what a run wrote without the renderer" \
		"$shown" \
		"Show it through tools/shell_check.sh: ck_eq LABEL GOT WANT for a value" \
		"beside what it should be, ck_detail for the lines a failure has to" \
		"name. Both render every byte a terminal would hide or act on (\\xHH," \
		"\\t), and ck_detail cuts and keeps a long one; printed raw, a carriage" \
		"return or a trailing space the turn-in wrote is invisible in the log."
	runs=$(shcheck_runs "$f")
	[ -z "$runs" ] || report \
		"$f runs a script outside ck_run" \
		"$runs" \
		"Run the turn-in with ck_run OUTFILE sh \"\$D\" (tools/shell_check.sh)," \
		"then judge OUTFILE: ck_run keeps what the script wrote to stderr and" \
		"its exit status, and prints them where the run happens, before the" \
		"checks that judge it, when there is something to see. Run any other" \
		"way -- inside a ck predicate, under timeout, in a \$(...) -- a script" \
		"/bin/sh cannot run fails with no line saying why, and the student is" \
		"sent after the wrong problem."
	first=$(shcheck_first "$f")
	case "$first" in
		"" | *" ck_require") ;;
		*) report \
			"$f registers a check before ck_require (line ${first% *}: ${first#* })" \
			"Its first check must be ck_require on the turn-in, which ends the" \
			"list when the file is missing. Checks that run on a missing file" \
			"pass whenever they assert an absence -- no spaces, no look-alike --" \
			"so a stub collected PASS lines for properties of nothing." ;;
	esac
	pre=$(awk '!/^[ \t]*#/ && /LD_PRELOAD|CK_REDIRECT_LIB/ { printf "    line %d: %s\n", FNR, $0 }' "$f")
	[ -z "$pre" ] || report "$f preloads a library itself" \
		"$pre" \
		"A fixed path the turn-in reads is redirected by its shell_exercise" \
		"call (redirect = {path: fixture}), and ck_run applies it to the" \
		"turn-in's runs alone, once the runner has proven it here. Loaded by" \
		"the check, it also redirects the check's own reads and the run meant" \
		"for the machine's own file (ck_run --no-redirect)."
	# Quoted text left out first, so a `<` or `|` inside an argument is not
	# read as a redirection; `||` is not a pipe.
	fed=$(awk '
		/^[ \t]*#/ && acc == "" { next }
		{
			if (acc == "") at = FNR
			if (sub(/\\$/, "", $0)) { acc = acc $0 " "; next }
			line = acc $0
			acc = ""
			l = line
			gsub(/"([^"\\]|\\.)*"/, "\"\"", l)
			gsub(/\047[^\047]*\047/, "\047\047", l)
			if (l ~ /(^|[^|])\|[ \t]*ck_run([ \t]|$)/ ||
			    (l ~ /^[ \t]*ck_run[ \t]/ && l ~ /[^0-9]<[^(&]/))
				printf "    line %d: %s\n", at, line
		}' "$f")
	[ -z "$fed" ] || report "$f feeds ck_run a stdin the turn-in never reads" \
		"$fed" \
		"ck_run runs the turn-in with its stdin on /dev/null, so a check that" \
		"runs it once per line of a list cannot hand it the rest of the list." \
		"What is piped or redirected into ck_run reaches nothing: a check" \
		"written that way tests input the program never gets. No shell subject" \
		"gives a turn-in input on stdin; if one ever does, ck_run needs an" \
		"option for it, and a selftest arm."
	if shcheck_runs_sh "$f" && ! grep -Eq '^[[:blank:]]*ck_sh_parses[[:blank:]]' "$f"; then
		report "$f runs a script with sh and never asks whether sh can parse it" \
			"Call ck_sh_parses on it after ck_require: the shell subjects require" \
			"shell exercises to be executable with /bin/sh, and dash runs a script" \
			"line by line, so one that prints the right thing and then dies on a" \
			"syntax error passes every check of what it printed."
	fi
	# git as a command wherever a command can stand -- at the start of a
	# line, after ;, &&, || or |, inside $(...) or `...`, after if or ! or
	# an assignment, under env or ck_run -- read by shcheck_runs' own split
	# (a comment, or git inside a quoted argument, is not one). The three
	# settings anywhere before the first such line, each assigned and
	# exported; XDG_CONFIG_HOME may be unset instead. [[:blank:]], not
	# [ \t]: inside a bracket POSIX reads \t as a backslash and a t, so a
	# tab-indented line would be missed.
	_git1=$(shcheck_runs "$f" git | sed -n '1s/^    line \([0-9][0-9]*\):.*/\1/p')
	if [ -n "$_git1" ]; then
		_pre=$(head -n "$_git1" "$f")
		_miss=""
		for _v in GIT_CONFIG_NOSYSTEM HOME XDG_CONFIG_HOME; do
			if [ "$_v" = XDG_CONFIG_HOME ] && printf '%s\n' "$_pre" |
				grep -Eq '^[[:blank:]]*unset([[:blank:]].*)?[[:blank:]]XDG_CONFIG_HOME([[:blank:];]|$)'; then
				continue
			fi
			printf '%s\n' "$_pre" | grep -Eq "^[[:blank:]]*(export[[:blank:]]+)?$_v=" &&
				printf '%s\n' "$_pre" | grep -Eq "^[[:blank:]]*export([[:blank:]].*)?[[:blank:]]$_v([[:blank:]=;]|\$)" &&
				continue
			_miss="$_miss $_v"
		done
		# And what a run outside Bazel's cleared environment inherits that
		# says where the repository is or which configuration it takes:
		# GIT_DIR would point the fixture's `git init` somewhere else, and
		# GIT_CONFIG_GLOBAL or GIT_CONFIG_PARAMETERS/COUNT bring config back
		# whatever HOME says. Each named in an `unset` before the first git.
		_umiss=""
		for _v in $GIT_INHERITED; do
			printf '%s\n' "$_pre" |
				grep -Eq "^[[:blank:]]*unset([[:blank:]].*)?[[:blank:]]$_v([[:blank:];]|\$)" ||
				_umiss="$_umiss $_v"
		done
		[ -z "$_umiss" ] || report "$f runs git (line $_git1) under what the environment says of git" \
			"Not unset before it:$_umiss. A run outside bazel test inherits" \
			"them: GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, GIT_OBJECT_DIRECTORY and" \
			"GIT_COMMON_DIR move the repository the fixture builds, and" \
			"GIT_CONFIG_GLOBAL, GIT_CONFIG_PARAMETERS and GIT_CONFIG_COUNT bring the" \
			"host's configuration back whatever HOME says. Unset them before the" \
			"first git command, as Shell 00 ex06's check does."
		[ -z "$_miss" ] || report "$f runs git (line $_git1) under the host's configuration" \
			"Not set and exported before it:$_miss. Before its first git" \
			"command, set and export GIT_CONFIG_NOSYSTEM=1, a HOME of its own" \
			"(HOME=\$(mktemp -d)) and XDG_CONFIG_HOME=\"\$HOME/.config\", as Shell 00" \
			"ex06's check does: /etc/gitconfig, ~/.gitconfig and" \
			"\$XDG_CONFIG_HOME/git/ can add ignore rules, a pager, colour or" \
			"signing, and the fixture, or what the turn-in prints, would then" \
			"depend on the machine. git reads \$XDG_CONFIG_HOME/git/config and" \
			"its default ignore file there whenever that is set, whatever HOME" \
			"says, and GIT_CONFIG_GLOBAL=/dev/null does not cover that ignore file."
	fi
done

# ---------------------------------------------------------------------------
# N. A twin is its exercise's call again, and its README names the folder.
#
# shell_exercise(twin_of = "//<module>:exNN") reads another project's tests
# for an exercise that repeats it (Piscine Reloaded's ex00-ex05). They used to
# be copies, and a fix reached one of each pair. Sharing the FILES closed that
# for the scripts, and left the same drift one level up: which readings run,
# and whether the oracle, env and fixtures reach the check, are still written
# on two calls. A second reading added to Shell 00 ex08's call and not to
# Reloaded ex02's gives Reloaded no target for it, and nothing goes red. So
# every argument of a twin's call but its number and its deliverable's name
# is compared with the call it names; a difference is reported, both sides
# shown. `wording` is left out too: it is each subject's own sentence for
# what the shared check quotes, which is where twins differ by design (Shell
# 01 ex02's "files", Reloaded ex03's "file names"); a check that quotes a
# sentence a call does not give stops with exit 2 when it runs (ck_wording).
#
# The macro reports a test file copied back into the twin's own tests/exMM/,
# and a missing README there, on the twin's exMM_twin target. What it cannot
# do is read a file: so the one thing a student who opens that folder finds,
# its README.md, is checked here to name the folder twin_of reads, and not
# one the call no longer points at.
#
# And a copy made WITHOUT twin_of -- the next project that repeats an
# exercise, its tests copied in -- is two files a fix has to find, exactly
# what twin_of removed. A copy is never byte for byte: whoever makes one
# fixes its header comment, and all fourteen of the Reloaded copies differed
# from their source in a comment line; two differed in code too, by the
# archive's name alone. A scan for identical files found one of the fourteen.
# So two test files of shell exercises in different modules are compared by
# their lines, with comment-only and blank lines left out and runs of blanks
# squeezed, and a line that differs from the other file's in one word of four
# or more still counts as the same line. The lines this file requires of
# every check script are left out too -- the library's load line, ck_require,
# ck_sh_parses on the turn-in, a plain `ck_run OUT sh FILE`, ck_report -- since
# every check script has them, copied or not: counted, they made up most of
# what two unrelated scripts shared, and a short script was most of the way to
# a copy on them alone. A pair is reported when 80% of the lines of each are
# alike, or when the smaller has ten lines or more and 80% of them are alike:
# a copy that gained checks afterwards. Measured on the fourteen (the 4cab14a
# tree), each scores 87% or more (ex00's literal.sh; the rest 98% or more);
# two unrelated check scripts, Shell 00 ex04's and Shell 01 ex06's, share at
# most 42% (48% with the required lines counted).
#
# Only the files this run can see are compared, so what it cannot see is said
# rather than skipped: every file a shell_exercise call names (its expected
# file, its check script, each reading's script) has to be here. Run by hand
# it always is. Under Bazel it is what conventions_srcs globs, and a test file
# named some other way needs its pattern added there (c_levels in
# tools/defs.bzl): the expected files were not in it, and the copy of Shell 00
# ex00's was never compared.
shcalls() {  # shcalls BUILD -> "NUM<TAB>KEY<TAB>VALUE" for every argument of every shell_exercise call
	awk '
		# The index of the quote that closes the string opening at i.
		function strend(s, i,   q, n, c) {
			q = substr(s, i, 1); n = length(s)
			for (i++; i <= n; i++) {
				c = substr(s, i, 1)
				if (c == "\\") { i++; continue }
				if (c == q) return i
			}
			return n
		}
		# One call'"'"'s arguments, whitespace and comments already gone: split
		# at the commas outside brackets and strings, each value as written.
		function emit(a,   n, i, c, depth, piece, k, num, e) {
			gsub(/,\]/, "]", a); gsub(/,\}/, "}", a); gsub(/,\)/, ")", a)
			a = a ","; n = length(a); depth = 0; piece = ""; k = 0; num = ""
			for (i = 1; i <= n; i++) {
				c = substr(a, i, 1)
				if (c == "\"" || c == "\047") {
					e = strend(a, i); piece = piece substr(a, i, e - i + 1); i = e
					continue
				}
				if (c ~ /[[({]/) depth++
				if (c ~ /[])}]/) depth--
				if (c == "," && depth == 0) {
					if (match(piece, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
						k++
						key[k] = substr(piece, 1, RLENGTH - 1)
						val[k] = substr(piece, RLENGTH + 1)
						if (key[k] == "num") { num = val[k]; gsub(/"/, "", num) }
					}
					piece = ""
					continue
				}
				piece = piece c
			}
			for (i = 1; i <= k; i++) printf "%s\t%s\t%s\n", num, key[i], val[i]
		}
		{ buf = buf $0 "\n" }
		END {
			n = length(buf)
			for (i = 1; i <= n; i++) {
				c = substr(buf, i, 1)
				if (c == "#") { while (i < n && substr(buf, i + 1, 1) != "\n") i++; continue }
				if (c == "\"" || c == "\047") { i = strend(buf, i); continue }
				if (substr(buf, i, 15) != "shell_exercise(") continue
				if (i > 1 && substr(buf, i - 1, 1) ~ /[A-Za-z0-9_.]/) continue
				a = ""; depth = 1
				for (j = i + 15; j <= n; j++) {
					c = substr(buf, j, 1)
					if (c == "#") { while (j < n && substr(buf, j + 1, 1) != "\n") j++; continue }
					if (c == "\"" || c == "\047") {
						e = strend(buf, j); a = a substr(buf, j, e - j + 1); j = e
						continue
					}
					if (c ~ /[[({]/) depth++
					if (c ~ /[])}]/ && --depth == 0) break
					if (c !~ /[ \t\n]/) a = a c
				}
				emit(a)
				i = j
			}
		}' "$1"
}
for _m in $MODULES; do
	_calls=$(shcalls "$_m/BUILD.bazel")
	# A here-document, not a pipe, for the reason the fixture-PATH check
	# above gives: a `| while` loop is a subshell, and every FAILS increment
	# in it is lost -- the report printed, the run still said OK.
	_twins=$(printf '%s\n' "$_calls" | awk -F '\t' '
		$2 == "twin_of" { v = $3; gsub(/"/, "", v); print $1, v }')
	while read -r _num _twin; do
		[ -n "$_twin" ] || continue
		_ex=ex$_num
		_d="$_m/tests/$_ex"
		_spkg=${_twin#//}
		_spkg=${_spkg%%:*}
		_sex=${_twin##*:}
		_src="$_spkg/tests/$_sex/"
		# A missing README is the twin target's to report, so a run that
		# reaches here without one says nothing more about it.
		if [ -f "$_d/README.md" ] && ! grep -qF -- "$_src" "$_d/README.md"; then
			report "$_d/README.md does not name $_src" \
				"$_ex's shell_exercise call reads its tests from there" \
				"(twin_of = \"$_twin\"), so a README that points anywhere else" \
				"sends a student to tests that are not the ones that ran."
		fi
		if [ ! -f "$_spkg/BUILD.bazel" ]; then
			report "$_m's $_ex names a twin whose BUILD this run cannot see ($_twin)" \
				"twin_of names a module, and its shell_exercise call for the" \
				"exercise is what this one's call is compared with."
			continue
		fi
		_cmp=$(
			{
				printf '%s\n' "$_calls" | awk -F '\t' -v n="$_num" \
					'$1 == n { print "here\t" $2 "\t" $3 }'
				shcalls "$_spkg/BUILD.bazel" | awk -F '\t' -v n="${_sex#ex}" \
					'$1 == n { print "there\t" $2 "\t" $3 }'
			} | awk -F '\t' '
				$1 == "there" { src = 1 }
				$2 == "num" || $2 == "deliverable" || $2 == "twin_of" || $2 == "wording" { next }
				{ v[$1, $2] = $3; k[$2] = 1 }
				END {
					if (!src) { print "none"; exit }
					for (x in k) {
						h = (("here", x) in v) ? v["here", x] : "(not given)"
						t = (("there", x) in v) ? v["there", x] : "(not given)"
						if (h != t) printf "%s: %s here, %s there\n", x, h, t
					}
				}' | sort)
		if [ "$_cmp" = none ]; then
			report "$_m's $_ex names a twin that has no shell_exercise call ($_twin)" \
				"$_spkg/BUILD.bazel declares no shell_exercise(num = \"${_sex#ex}\"), so" \
				"the tests this exercise reads belong to nothing that runs them."
		elif [ -n "$_cmp" ]; then
			report "$_m's $_ex is not called the way its twin is ($_twin)" \
				"$_cmp" \
				"Its tests are that exercise's, and what the call says comes with" \
				"them: which readings run, the mode, the oracle, env, fixtures," \
				"files and tags. Given on one call and not the other, it runs for" \
				"one project only and nothing says so. Write the arguments the" \
				"way the twin's call does; only the deliverable's name may differ" \
				"(Reloaded's exo.tar, Shell 00's exo2.tar), and the subject's own" \
				"words for a sentence its check quotes (wording)."
		fi
	done <<-TWINS
		$_twins
	TWINS
done
# The copies: every test file of every shell exercise, "MODULE<TAB>PATH",
# and beside it, what this run could not see of what the calls name.
_tfiles=""
_unseen=""
for _m in $MODULES; do
	_calls=$(shcalls "$_m/BUILD.bazel")
	for _n in $(printf '%s\n' "$_calls" | awk -F '\t' '
		$2 == "num" { v = $3; gsub(/"/, "", v); print v }'); do
		for _f in "$_m/tests/ex$_n"/*; do
			[ -f "$_f" ] || continue
			[ "${_f##*/}" != README.md ] || continue
			_tfiles="$_tfiles$_m	$_f
"
		done
	done
	# "NUM<TAB>FILE" for each test file a call names in a string literal: the
	# expected file (diff), the check script and each reading's (check). A
	# twin's are its twin's, and seen there.
	_unseen="$_unseen$(printf '%s\n' "$_calls" | awk -F '\t' '
		function lit(v) { return v ~ /^"[^"]*"$/ ? substr(v, 2, length(v) - 2) : "" }
		{ k[$1, $2] = $3; nums[$1] = 1 }
		END {
			for (x in nums) {
				if ((x, "twin_of") in k) continue
				m = lit(k[x, "mode"])
				if (m == "diff")
					print x "\t" (((x, "expected") in k) ? lit(k[x, "expected"]) : "expected.txt")
				if (m != "check") continue
				print x "\t" (((x, "check") in k) ? lit(k[x, "check"]) : "check.sh")
				r = k[x, "readings"]
				gsub(/[{}]/, "", r)
				c = split(r, p, ",")
				for (i = 1; i <= c; i++) {
					v = p[i]
					sub(/^[^:]*:/, "", v)
					print x "\t" lit(v)
				}
			}
		}' | while IFS='	' read -r _n _f; do
			[ -n "$_f" ] || continue
			[ -f "$_m/tests/ex$_n/$_f" ] || printf '    %s\n' "$_m/tests/ex$_n/$_f"
		done)
"
done
_unseen=$(printf '%s' "$_unseen" | grep .)
[ -z "$_unseen" ] || report "the copy scan below cannot see a test file a shell_exercise call names" \
	"$_unseen" \
	"So it was compared with nothing, and a copy of it would go unreported." \
	"Under Bazel this run sees what each module's conventions_srcs globs" \
	"(c_levels in tools/defs.bzl): add the file's pattern there. Run by hand," \
	"the file is missing, and the call names something that is not there."
# A pair of files is a copy when their lines are alike (see above). Each line
# is keyed as itself and, with four words or more, once per word with that
# word blanked out; two lines that share a key are alike. For each file, the
# count of its lines alike to one of each other module's files is then read
# off the keys, and the pair is judged on it.
_copies=$(printf '%s' "$_tfiles" | awk -F '\t' '
	NF == 2 {
		f++; mod[f] = $1; path[f] = $2
		while ((getline l < $2) > 0) {
			sub(/^[ \t]+/, "", l)
			sub(/[ \t]+$/, "", l)
			if (l == "" || l ~ /^#/) continue
			gsub(/[ \t]+/, " ", l)
			# The lines this file requires of every check script are in
			# every check script, copied or not (see above).
			if (l ~ /^[.] "?[$][{]?SHELL_CHECK_LIB[^ ]*$/ || l ~ /^ck_report( |$)/ ||
				l ~ /^ck_require / || l ~ /^ck_sh_parses [^ ]+$/ ||
				l ~ /^ck_run [^ ]+ (\/bin\/)?sh [^ ]+$/) continue
			if ((f, l) in seen) continue
			seen[f, l] = 1
			lno = ++n[f]
			key["=" l] = key["=" l] " " f ":" lno
			w = split(l, wd, " ")
			if (w < 4) continue
			for (x = 1; x <= w; x++) {
				v = ""
				for (y = 1; y <= w; y++) v = v " " (y == x ? SUBSEP : wd[y])
				key["~" v] = key["~" v] " " f ":" lno
			}
		}
		close($2)
	}
	END {
		for (k in key) {
			c = split(substr(key[k], 2), o, " ")
			if (c < 2) continue
			for (a = 1; a <= c; a++) {
				split(o[a], fa, ":")
				for (b = 1; b <= c; b++) {
					split(o[b], fb, ":")
					if (mod[fa[1]] == mod[fb[1]]) continue
					if ((fa[1], fa[2], fb[1]) in hit) continue
					hit[fa[1], fa[2], fb[1]] = 1
					alike[fa[1], fb[1]]++
				}
			}
		}
		for (p in alike) {
			split(p, ij, SUBSEP)
			i = ij[1]; j = ij[2]
			if (path[i] > path[j] || !((j, i) in alike)) continue
			ri = alike[i, j] / n[i]; rj = alike[j, i] / n[j]
			s = n[i] <= n[j] ? i : j
			rs = s == i ? ri : rj
			if ((ri >= 0.8 && rj >= 0.8) || (n[s] >= 10 && rs >= 0.8))
				printf "    %s and %s (%d of %d lines alike)\n", path[i], path[j],
					alike[s, s == i ? j : i], n[s]
		}
	}' | sort)
[ -z "$_copies" ] || report "a shell exercise's test file is a copy of another module's" \
	"$_copies" \
	"Comments, blank lines and the lines every check script must have are" \
	"left out, and a line that differs in one word counts as alike. One" \
	"exercise repeats the other: declare the repeat with twin_of on its" \
	"shell_exercise call (see shell_exercise in tools/defs.bzl), delete the" \
	"copy, and leave a README.md in its folder naming the one it reads. Two" \
	"copies are two files a fix has to find, and the Reloaded ones drifted." \
	"If the two exercises only look alike, their tests differ where the" \
	"subjects do; make them say so."

# ---------------------------------------------------------------------------
# N. A C exercise that repeats another module's says so, and its tests stay
#    that exercise's.
#
# Piscine Reloaded repeats sixteen C exercises, and each tests/ folder was a
# copy of the one it repeats, byte for byte -- ex27's seven expected files,
# three fixtures and three hint files C 10 ex00's, its case list written out
# a second time in its BUILD file: a fix that reached one copy left the other
# behind, and nothing said so (the shell twins share one source, twin_of; a C
# exercise's macros name their files from their own folder). So c_twin(num,
# of = "//<module>:exNN") declares the repeat, and this holds the two to each
# other: the two tests/ folders file for file and byte for byte, and, where
# either is a c_program call, their `cases` token for token, in whatever
# layout, once comments are left out and each folder's own tests/exNN/ is
# read as one (a call it cannot match is reported, never passed). And a tests/
# folder of three files or more that is all a copy of another module's, with
# no such line, is reported: the next repeat copied in.
ctwin_calls() {  # ctwin_calls MODULE -> "MODULE<TAB>exNN<TAB>TWIN" per c_twin(num = "NN", of = "...")
	awk -v m="$1" '
		/^c_twin\(/ {
			l = $0
			n = l; sub(/.*num = "/, "", n); sub(/".*/, "", n)
			o = l; sub(/.*of = "/, "", o); sub(/".*/, "", o)
			if (n != l && o != l) print m "\tex" n "\t" o
		}
	' "$1/BUILD.bazel"
}
ccases() {  # ccases BUILD exNN -> that c_program call's `cases`, one line; "(no cases)"; "UNREADABLE"; or nothing
	# Each c_program( call, at any indentation and in any layout -- one line
	# or many, `num` and `cases` on the call's own line or not -- is read whole
	# (brackets counted outside strings, comments left out). The one whose
	# num is "NN" gives its cases list on one line: blanks outside strings
	# and a comma before a closing bracket dropped, tests/exNN/ read as
	# tests/exXX/, so two layouts of one list compare equal. A call whose
	# num is not a literal (a comprehension's variable) cannot be matched:
	# UNREADABLE, unless a literal call matched, so the pair is reported and
	# never compared equal on two empty readings, as a one-line call once was.
	awk -v want="${2#ex}" -v ex="$2" '
		# code(l): l without its comment, strings kept whole.
		function code(l,   i, c, out, q) {
			out = ""; q = 0
			for (i = 1; i <= length(l); i++) {
				c = substr(l, i, 1)
				if (q) {
					out = out c
					if (c == "\\") { i++; out = out substr(l, i, 1) }
					else if (c == "\"") q = 0
					continue
				}
				if (c == "#") break
				if (c == "\"") q = 1
				out = out c
			}
			return out
		}
		# depth(t, o, c): how many o more than c outside strings.
		function depth(t, o, c,   i, ch, q, d) {
			q = 0; d = 0
			for (i = 1; i <= length(t); i++) {
				ch = substr(t, i, 1)
				if (q) {
					if (ch == "\\") i++
					else if (ch == "\"") q = 0
					continue
				}
				if (ch == "\"") q = 1
				else if (ch == o) d++
				else if (ch == c) d--
			}
			return d
		}
		# list(t): t from its first "[" to the "]" that closes it, blanks
		# outside strings dropped, and a comma before "]" or "}".
		function list(t,   i, ch, q, d, out) {
			q = 0; d = 0; out = ""
			for (i = index(t, "["); i <= length(t); i++) {
				ch = substr(t, i, 1)
				if (q) {
					out = out ch
					if (ch == "\\") { i++; out = out substr(t, i, 1) }
					else if (ch == "\"") q = 0
					continue
				}
				if (ch == " " || ch == "\t") continue
				if (ch == "\"") q = 1
				if ((ch == "]" || ch == "}") && substr(out, length(out), 1) == ",")
					out = substr(out, 1, length(out) - 1)
				out = out ch
				if (ch == "[") d++
				else if (ch == "]" && --d == 0) break
			}
			return out
		}
		function call_done(t,   n, c) {
			if (match(t, /[(,][ \t]*num[ \t]*=[ \t]*"[^"]*"/)) {
				n = substr(t, RSTART, RLENGTH); sub(/^[^"]*"/, "", n); sub(/"$/, "", n)
				if (n != want) return
				found = 1
				if (!match(t, /[(,][ \t]*cases[ \t]*=[ \t]*\[/)) { print "(no cases)"; return }
				c = list(substr(t, RSTART))
				gsub("tests/" ex "/", "tests/exXX/", c)
				print c
			} else if (match(t, /[(,][ \t]*num[ \t]*=/))
				unlit = 1
		}
		{
			l = code($0)
			if (!inc) {
				p = index(l, "c_program(")
				if (p == 0 || (p > 1 && substr(l, p - 1, 1) ~ /[A-Za-z0-9_.]/)) next
				l = substr(l, p + length("c_program"))
				inc = 1; text = ""; d = 0
			}
			text = text " " l
			d += depth(l, "(", ")")
			if (d <= 0) { inc = 0; call_done(text) }
		}
		END { if (!found && unlit) print "UNREADABLE" }
	' "$1"
}
_ctw=$(for _m in $MODULES; do [ -f "$_m/BUILD.bazel" ] && ctwin_calls "$_m"; done)
_ctwin_bad=""
_oldifs=$IFS
IFS='
'
for _t in $_ctw; do
	IFS=$_oldifs
	_tm=$(printf '%s' "$_t" | cut -f1)
	_tex=$(printf '%s' "$_t" | cut -f2)
	_src=$(printf '%s' "$_t" | cut -f3)
	_sm=${_src#//}
	_sm=${_sm%%:*}
	_sex=${_src##*:}
	if [ ! -d "$_sm/tests/$_sex" ] || [ ! -f "$_sm/BUILD.bazel" ]; then
		_ctwin_bad="$_ctwin_bad
    $_tm $_tex: c_twin(of = ...) names $_src, which has no tests/$_sex"
		continue
	fi
	_lt=$(cd "$_tm/tests/$_tex" && find . \( -type f -o -type l \) | sort)
	_ls=$(cd "$_sm/tests/$_sex" && find . \( -type f -o -type l \) | sort)
	[ "$_lt" = "$_ls" ] || _ctwin_bad="$_ctwin_bad
    $_tm/tests/$_tex and $_sm/tests/$_sex hold different files: $(printf '%s\n%s\n' "$_lt" "$_ls" | sort | uniq -u | tr '\n' ' ')"
	for _f in $(printf '%s\n' "$_lt"); do
		[ -f "$_sm/tests/$_sex/$_f" ] || continue
		cmp -s "$_tm/tests/$_tex/$_f" "$_sm/tests/$_sex/$_f" || _ctwin_bad="$_ctwin_bad
    ${_f#./} differs between $_tm/tests/$_tex and $_sm/tests/$_sex"
	done
	_cct=$(ccases "$_tm/BUILD.bazel" "$_tex")
	_ccs=$(ccases "$_sm/BUILD.bazel" "$_sex")
	if [ "$_cct" = UNREADABLE ] || [ "$_ccs" = UNREADABLE ]; then
		_ctwin_bad="$_ctwin_bad
    the c_program calls of $_tm $_tex and $_src cannot be compared: one has no
    c_program(num = \"NN\") with its number written out, and a call whose num
    is a variable cannot be matched; write that call with its own number"
	elif [ "$_cct" != "$_ccs" ]; then
		_ctwin_bad="$_ctwin_bad
    the cases of $_tm's c_program(num = \"${_tex#ex}\") differ from $_src's"
	fi
	IFS='
'
done
IFS=$_oldifs
[ -z "$_ctwin_bad" ] || report "a C exercise declared a twin (c_twin), and the two have drifted" \
	"$_ctwin_bad" \
	"A fix made to one copy is still to be made to the other: the twin's tests" \
	"and cases are the exercise's it repeats, with its own number."
# Undeclared: a tests/exNN folder of three files or more, every one byte for
# byte a file of another module's tests/exMM, the same names -- read with the
# name of a prototype.h's include guard left out, which every module spells
# after itself. Ten of Piscine Reloaded's folders were copies of a Piscine
# exercise's but for that one line, so none was seen as one, and a fix to
# one copy (C 01 ex03's out-parameters) had nothing to make it reach the
# other.
_csig_dir() {  # _csig_dir DIR -> one checksum of its file names and contents, guard names left out
	(cd "$1" && find . \( -type f -o -type l \) | sort | while IFS= read -r _f; do
		printf '%s %s\n' "$_f" "$(sed -e '/^#[[:blank:]]*ifndef[[:blank:]][[:blank:]]*PROTOTYPE_[A-Z0-9_]*_H[[:blank:]]*$/d' \
			-e '/^#[[:blank:]]*define[[:blank:]][[:blank:]]*PROTOTYPE_[A-Z0-9_]*_H[[:blank:]]*$/d' "$_f" | cksum)"
	done) | cksum | cut -d' ' -f1
}
_csig=$(for _m in $MODULES; do
	[ -d "$_m/tests" ] || continue
	for _d in "$_m"/tests/ex[0-9][0-9]; do
		[ -d "$_d" ] || continue
		_n=$(find "$_d" \( -type f -o -type l \) | awk 'END { print NR }')
		[ "$_n" -ge 3 ] || continue
		printf '%s\t%s\n' "$(_csig_dir "$_d")" "$_d"
	done
done | sort)
_cdup=$(printf '%s\n' "$_csig" | awk -F'\t' -v tw="$_ctw" '
	BEGIN {
		n = split(tw, rows, "\n")
		for (i = 1; i <= n; i++) {
			split(rows[i], f, "\t")
			if (f[3] == "") continue
			sm = f[3]; sub(/^\/\//, "", sm); se = sm; sub(/:.*/, "", sm); sub(/.*:/, "", se)
			declared[f[1] "/tests/" f[2] "\t" sm "/tests/" se] = 1
			declared[sm "/tests/" se "\t" f[1] "/tests/" f[2]] = 1
		}
	}
	NF == 2 {
		if ($1 == prev && !((pd "\t" $2) in declared)) {
			a = pd; b = $2; sub(/\/tests\/.*/, "", a); sub(/\/tests\/.*/, "", b)
			if (a != b) printf "    %s and %s\n", pd, $2
		}
		prev = $1; pd = $2
	}')
[ -z "$_cdup" ] || report "a test folder is a copy of another module's, and no c_twin says so" \
	"$_cdup" \
	"One exercise repeats the other: say so beside its calls," \
	"c_twin(num = \"NN\", of = \"//<module>:exMM\"), so the two are held to each other; or, if" \
	"they only look alike, make their tests differ where the subjects do."

# ---------------------------------------------------------------------------
# N. A shell exercise's call says what its check script relies on.
#
# Two facts about a turn-in are written on its shell_exercise call and relied
# on by its check script, and each pair can drift apart:
#
#   - `script`: the turn-in is a script, so the call emits its lint targets,
#     exNN_posix (strict) and exNN_lint (robust). The norm layer used to read
#     the generator alone, and nothing said which turn-ins were scripts, so
#     the file 42 grades was never linted (finding 024). A check that asks
#     ck_sh_parses of the turn-in is checking a script: a call without
#     `script` leaves that script unlinted. And a call with `script` whose
#     check never asks /bin/sh to parse the turn-in lints, above basic, a
#     script no basic target asked /bin/sh to read. A diff-mode exercise is
#     a script when it runs the turn-in with /bin/sh (run = True and no
#     interp): the runner parses it then. And script = "./name" says the
#     subject's example runs it as ./name, which lets its #! line pick the
#     shell exNN_posix reads it for; a check asks for the execute bit
#     (ck_executable) for that same reason, so either without the other
#     says two different things about how the subject runs one file.
#   - `stable`: the check compares two runs of the generator (ck_stable), and
#     only a call with stable = True makes the second one. A check that calls
#     ck_stable without it, or a call that says it over a check that never
#     compares, stops that check with exit 2 when it runs; this says so
#     before anyone does. (Finding 013 first used it on Shell 00 ex03's key;
#     the owner reversed that on 2026-10-04, since making the key is the
#     exercise: no call says stable = True today.)
#
# A twin's call is compared with its exercise's (the rule above), so only the
# calls that read their own tests are held here.
for _m in $MODULES; do
	[ -f "$_m/BUILD.bazel" ] || continue
	_calls=$(shcalls "$_m/BUILD.bazel")
	for _n in $(printf '%s\n' "$_calls" | awk -F '\t' '$2 == "num" { v = $3; gsub(/"/, "", v); print v }'); do
		_kv=$(printf '%s\n' "$_calls" | awk -F '\t' -v n="$_n" '$1 == n { print $2 "\t" $3 }')
		printf '%s\n' "$_kv" | grep -q '^twin_of	' && continue
		_mode=$(printf '%s\n' "$_kv" | awk -F '\t' '$1 == "mode" { v = $2; gsub(/"/, "", v); print v }')
		_script=$(printf '%s\n' "$_kv" | awk -F '\t' '$1 == "script" { v = $2; gsub(/"/, "", v); print v }')
		[ "$_script" != None ] || _script=""
		_stable=$(printf '%s\n' "$_kv" | awk -F '\t' '$1 == "stable" { print $2 }')
		_parses=0
		_compares=0
		_execs=-
		if [ "$_mode" = check ]; then
			_chk=$(printf '%s\n' "$_kv" | awk -F '\t' '$1 == "check" { v = $2; gsub(/"/, "", v); print v }')
			_f="$_m/tests/ex$_n/${_chk:-check.sh}"
			[ -f "$_f" ] || continue
			grep -Eq '^[ 	]*ck_sh_parses[ 	]' "$_f" && _parses=1
			grep -Eq '^[ 	]*ck_stable[ 	]' "$_f" && _compares=1
			_execs=0
			grep -Eq '^[ 	]*ck_executable[ 	]' "$_f" && _execs=1
		else
			_f="$_m/BUILD.bazel"
			printf '%s\n' "$_kv" | grep -q '^run	True$' &&
				! printf '%s\n' "$_kv" | grep -q '^interp	' && _parses=1
		fi
		if [ "$_parses" = 1 ] && [ -z "$_script" ]; then
			report "$_m's ex$_n turns in a script, and its call does not say so" \
				"Its test asks /bin/sh to parse the turn-in ($_f), so the turn-in" \
				"is a script; give its shell_exercise call script = \"sh\" (or" \
				"\"./name\" or \"bash\", where the subject's example runs it that" \
				"way), which lints it. Without it, what 42 grades is never linted" \
				"(see script in shell_exercise, tools/defs.bzl)."
		elif [ "$_parses" = 0 ] && [ -n "$_script" ]; then
			report "$_m's ex$_n says script = \"$_script\", and its test never parses the turn-in" \
				"/bin/sh parsing it is the basic half of a script's lint: call" \
				"ck_sh_parses on the turn-in in $_f, or drop script from the" \
				"call if the turn-in is not a script."
		fi
		if [ "$_execs" = 1 ] && [ -n "$_script" ] && [ "$_script" != ./name ]; then
			report "$_f asks for the execute bit, and $_m's ex$_n call says script = \"$_script\"" \
				"ck_executable is for a turn-in the subject's example runs as" \
				"./name, and so is script = \"./name\": it lets the script's #!" \
				"line pick the shell its exNN_posix reads it for. Say \"./name\" on" \
				"the call, or drop ck_executable if the subject never runs it so."
		elif [ "$_execs" = 0 ] && [ "$_script" = ./name ]; then
			report "$_m's ex$_n says script = \"./name\", and $_f never asks for the execute bit" \
				"A turn-in the subject's example runs as ./name cannot run without" \
				"it: call ck_executable on the turn-in, or say \"sh\" on the call" \
				"if the subject never runs it as ./name."
		fi
		if [ "$_compares" = 1 ] && [ "$_stable" != True ]; then
			report "$_f calls ck_stable, and $_m's ex$_n call does not say stable = True" \
				"ck_stable compares two runs of the generator, and only a call with" \
				"stable = True makes the second one: without it the check stops" \
				"with exit 2 when it runs (see stable in shell_exercise, tools/defs.bzl)."
		elif [ "$_compares" = 0 ] && [ "$_stable" = True ]; then
			report "$_m's ex$_n says stable = True, and $_f never calls ck_stable" \
				"The second run of the generator would be compared with nothing," \
				"which the check refuses (exit 2) when it runs. Call ck_stable on" \
				"the turn-in, or drop stable from the call."
		fi
	done
done

# ---------------------------------------------------------------------------
# N. The level ladder is written down once, in docs/reference.md.
#
# Which layers each level runs used to be spelled out in six places: the
# reference's tables, a .bazelrc comment, c-13's BUILD file, the README, the
# testing guide and three blocks of tools/submit.sh. The reference's copy is
# checked against _LAYER_LEVEL (the check above); the others were checked by
# nobody, and they drifted the way unchecked copies do -- c-13's comment put
# `diff` a level above where the build runs it, and submit's help text once
# left allocfail out of the level it belongs to. docs/design.md: state each fact
# once, where it is checked, and point to it everywhere else.
#
# Two shapes are refused outside the reference, in every file of the kinds a
# person reads -- Markdown, shell, Starlark, BUILD files, .bazelrc, clue
# tables, Python, Rust, TOML -- that text_files reaches. That is what both ways
# of running this can see: a module's README, AGENTS.md and oracle/README.md
# arrive in the sh_test through the conventions_srcs filegroups. The list of
# files used to be written out here, and it left out every module README, so a
# new project's README could carry a ladder unread.
#
#   a rung    a level name followed by layers, `+` or not: what a level runs,
#             which is exactly what drifts. A list of them (LEVEL: LAYER,
#             LAYER) or a single one (LEVEL  # + LAYER, at the end of a line,
#             or LEVEL + LAYER and LAYER) -- the single form was missed while
#             a comma was required after the first layer. The layer names are
#             _LAYER_LEVEL's, so a new layer is covered the day it is added.
#   a ladder  three or more of the four level names each opening a line
#             within sixty: the levels defined over again, as a list or as
#             one paragraph per level.
#
# Naming a level is fine -- `bazel test //<module>:strict`, "raised to strict"
# -- and so is a single layer's level where the sentence is about that layer
# ("symbols runs at strict").
#
# Not scanned: docs/reference.md, which holds the ladder; TODO.md and
# HISTORY.md, the maintainer's plan and record, which say what a level WILL
# run or DID, dated, and never ship; and tools/defs.bzl. _LAYER_LEVEL, the
# ladder as data, lives there and is the source the reference is checked
# against. The comment above it and c_levels' docstring still repeat the
# ladder in prose, and this exemption should narrow to _LAYER_LEVEL itself
# once they point here too.
LADDER_LAYERS=$(printf '%s\n' "$LEVELS" | cut -d' ' -f1 | grep . | tr '\n' '|' | sed 's/|$//')
ladder_copies=$(
	text_files \
		\( -name '*.md' -o -name '*.sh' -o -name '*.bzl' -o -name 'BUILD.bazel' \
		-o -name 'BUILD' -o -name 'MODULE.bazel' -o -name '.bazelrc' -o -name '*.tsv' \
		-o -name '*.py' -o -name '*.rs' -o -name '*.toml' \) \
		! -path ./docs/reference.md ! -path ./tools/defs.bzl \
		! -path ./TODO.md ! -path ./HISTORY.md \
		-exec awk -v layers="$LADDER_LAYERS" '
			function flush(   i, j, n) {
				for (i = 1; i <= c; i++) {
					if (!(i in lv)) continue
					n = 0; split("", seen)
					for (j = i; j < i + 60 && j <= c; j++)
						if ((j in lv) && !(lv[j] in seen)) { seen[lv[j]] = 1; n++ }
					if (n >= 3 && !(i in hit)) {
						printf "    %s:%d: %s\n", f, i, line[i]
						break
					}
				}
			}
			BEGIN {
				rung = "(^|[^A-Za-z_])(basic|strict|robust|complete)[:= \t]+(#[ \t]*)?(\\+[ \t]*)?(" layers ")[ \t]*(,|$|and[ \t])"
			}
			FNR == 1 {
				if (f != "") flush()
				f = FILENAME; sub(/^\.\//, "", f)
				c = 0; split("", lv); split("", hit); split("", line)
			}
			{
				c = FNR
				if (layers != "" && $0 ~ rung) { printf "    %s:%d: %s\n", f, FNR, $0; hit[FNR] = 1 }
				l = $0
				sub(/^[ \t#*\/|>`-]*[0-9]*[ \t.)`]*/, "", l)
				if (match(l, /^(basic|strict|robust|complete)([^A-Za-z_]|$)/)) {
					w = substr(l, 1, RLENGTH); sub(/[^a-z]$/, "", w); lv[FNR] = w
				}
				line[FNR] = $0
			}
			END { if (f != "") flush() }' {} + | sort
)
[ -z "$ladder_copies" ] || report \
	"the level ladder is spelled out outside docs/reference.md" \
	"$ladder_copies" \
	"Which layers each level runs is stated once, in docs/reference.md ('The" \
	"four levels', 'The layers'), and checked there against _LAYER_LEVEL." \
	"Name the level and point at the reference; a second copy is one that" \
	"drifts with nothing to notice."

# ---------------------------------------------------------------------------
# N. The REMOTES table in tools/submit.sh holds no URL.
#
# Every row there is REPLACE_ME, always: the table is the list of modules, and
# a student's Vogsphere URLs live in .submit-remotes, a file of their own
# (docs/design.md: per-student state never lives inside a harness file). A URL
# typed into the table is one a harness update then collides with, and one
# that identifies its owner -- the URLs hold the login -- in a file every clone
# shares, and the template build had to scrub. A commented-out row counts:
# commenting a row out leaves its URL in the file.
remotes_live=$(awk '
	!inb && $0 == "REMOTES='"'"'" { inb = 1; next }
	inb && /^'"'"'/ { exit }
	inb {
		line = $0
		sub(/^[ \t]*#[ \t]*/, "", line)
		sub(/[ \t]#.*$/, "", line)
		if (index(line, "=") == 0) next
		v = substr(line, index(line, "=") + 1)
		gsub(/^[ \t]+|[ \t]+$/, "", v)
		if (v != "REPLACE_ME") printf "    tools/submit.sh:%d: %s\n", NR, $0
	}' tools/submit.sh 2> /dev/null)
[ -z "$remotes_live" ] || report \
	"tools/submit.sh's REMOTES table holds a row that is not REPLACE_ME" \
	"$remotes_live" \
	"The URL belongs in .submit-remotes at the repo root, one KEY=URL line per" \
	"module (docs/submitting.md). Put it there and set the row back to" \
	"REPLACE_ME."

# ---------------------------------------------------------------------------
# N. A sanitized exercise's diff layer gates on the sanitized fixture.
#
# THIS ONE COST THREE LAYERS ON A FINISHED EXERCISE, silently, for as long as
# the exercise has existed.
#
# The diff/perf layers do not run until the exercise's OWN output fixture
# passes, because fuzzing a wrong answer reports the same wrongness thousands of
# times. That gate re-runs diff_output.sh over the fixture -- and it has to run
# it the same WAY the exercise's own output layer does. `sanitize` normalises a
# leading address column to an offset, and that changes the VERDICT, not just
# the rendering.
#
# c-02 ex12 (ft_print_memory) set c_function(sanitize = True) and its c_diff did
# not pass gate_sanitize. So the gate compared a real, ASLR-randomised address
# against a fixture written in offsets, decided a correct exercise was red, and
# ex12_diff, ex12_diff_asan and ex12_perf skipped -- reporting PASS, forever, on
# the most intricate deliverable in the module. Reproduced before it was fixed:
# ex12_output PASSED in the same run in which ex12_diff printed "SKIP -- this
# exercise's own output fixture is not passing yet".
#
# defs.bzl's docstring already said "MUST match", in those words. A rule stated
# in a docstring is a rule nothing checks, which is how it was wrong.
#
# Starlark macros cannot see each other's arguments, so this is checked here,
# where both calls are just text in the same file.
for _m in $MODULES; do
	f="$_m/BUILD.bazel"
	mismatched=$(awk '
		function flush(   n) {
			if (kind == "") return
			n = buf
			sub(/.*num[ \t]*=[ \t]*"/, "", n); sub(/".*/, "", n)
			# [^_] so that gate_sanitize does not match as sanitize.
			if (kind == "c_function") {
				if (buf ~ /[^_]sanitize[ \t]*=[ \t]*True/) fn[n] = 1
			} else if (buf ~ /gate_sanitize[ \t]*=[ \t]*True/) {
				df[n] = 1
			}
			kind = ""; buf = ""
		}
		{
			line = $0
			sub(/#.*/, "", line)
			if (kind == "" && line ~ /^(c_function|c_diff)\(/) {
				kind = line; sub(/\(.*/, "", kind)
				buf = ""; depth = 0
			}
			if (kind != "") {
				buf = buf " " line
				o = gsub(/\(/, "(", line)
				c = gsub(/\)/, ")", line)
				depth += o - c
				if (depth <= 0) flush()
			}
		}
		END { for (n in fn) if (!(n in df)) printf "    ex%s\n", n }
	' "$f")
	[ -z "$mismatched" ] || report \
		"$f has a c_function(sanitize) whose c_diff does not gate on it" \
		"$mismatched" \
		"Add gate_sanitize = True to that exercise's c_diff. Without it the" \
		"gate reads the fixture the other way round from the layer it guards," \
		"decides a PASSING exercise is red, and the diff, diff_asan and perf" \
		"layers then skip forever while the suite looks green."
done

# ---------------------------------------------------------------------------
# N. A runner's list of words from its command line is one word per line.
#
# Every runner gathers words from its arguments -- each --src, an -I per
# header, the options it forwards to diff_output.sh -- and they were joined
# with a blank (SRCS="$SRCS $2") and expanded bare. A path holding a blank then
# arrived as two words and one holding a * was globbed on its way through:
# header_check.sh reported a correct header "not found" and broke on a clues
# path with a usage error, and seven more runners did the same. runner_lib.sh's
# LISTS OF WORDS is the one way: rl_list_add, and rl_split_on / rl_split_off
# around the expansion. So a line that appends to a variable, joined with a
# blank, a word that names a positional parameter ($1..$9) is refused in every
# script under tools/; a joined list of the script's own words is not, and
# neither is a line under a comment saying why it is no such list:
#     # conventions: not-a-list -- <a message line, never expanded bare>
_lists=$(for f in tools/*.sh; do
	[ -f "$f" ] || continue
	awk -v f="$f" '
		/^[[:blank:]]*# conventions: not-a-list -- / { told = FNR; next }
		/^[[:blank:]]*#/ { next }
		told && FNR == told + 1 { next }
		{
			line = $0
			while (match(line, /[A-Za-z_][A-Za-z0-9_]*="\$\{?[A-Za-z_][A-Za-z0-9_]*(:[-+][^}]*)?\}? /)) {
				a = substr(line, RSTART, RLENGTH)
				rest = substr(line, RSTART + RLENGTH)
				v = a; sub(/=.*/, "", v)
				w = a; sub(/^[^=]*="\$\{?/, "", w); sub(/[^A-Za-z0-9_].*/, "", w)
				val = rest; sub(/".*/, "", val)
				if (v == w && val ~ /\$\{?[1-9]/) { printf "    %s:%d: %s\n", f, FNR, $0; break }
				line = rest
			}
		}' "$f"
done)
[ -z "$_lists" ] || report "a runner joins words from its command line with a blank" \
	"$_lists" \
	"Expanded bare, a path holding a blank arrives as two words and one" \
	"holding a * is globbed. Build the list with rl_list_add and expand it" \
	"between rl_split_on and rl_split_off (tools/runner_lib.sh, LISTS OF WORDS)."

# ---------------------------------------------------------------------------
# N. A list of files is read one name per line, whole.
#
# A page's commands are copied and run as they stand, on trees nobody here has
# seen, and a script runs on every clone. `for f in $(git ls-files ...)` splits
# every name at its blanks, and a tree holds such names -- a file manager's
# `ft_x copy.c`, the macro fixtures' `toy_twice (1).c`: a runbook's loop for
# "what still needs stubbing" reported `.../ex05/toy_twice` twice, a file that
# does not exist, and never looked at the two that do. stub_check.sh walked its
# lists the same way and passed a staged answer with a blank in its name. So no
# Markdown page and no shell script outside the zone loops `for` over the
# output of git ls-files, git ls-tree, git grep, git diff, find or ls: it
# writes the listing to a file, or pipes it, and reads it with
# `while IFS= read -r f`.
#
# And a git listing read that way is made with -z, through `tr '\0' '\n'`:
# without it git quotes a name holding a byte above 0x7f, a double quote or a
# backslash ("ft_acc\303\251.c"), and a quoted name is no file.
# answer_scan.sh listed the zone so, and an answer named with an accent had its
# definitions never read: a static helper only it names, in a harness file,
# passed as "OK ... none outside the zone". The pipeline is followed across
# lines that end in `|` or `\`; `--error-unmatch` names a path, it lists none.
_list_loops=$(text_files \( -name '*.md' -o -name '*.sh' \) ! -path ./TODO.md ! -path ./HISTORY.md \
	-exec awk -v bq="$(printf '\140')" '
	BEGIN {
		split("ls-files ls-tree grep diff", g, " "); for (i in g) lists[g[i]] = 1
		# A string, not a /regex/: the require-list scanner above reads a
		# word after a ( as a command, and git is not one this script runs.
		gitls = "(^|[^A-Za-z0-9_-])git([[:blank:]]+-C[[:blank:]]+[^[:blank:]]+)?[[:blank:]]+(ls-files|ls-tree)([[:blank:]]|$)"
	}
	FNR == 1 { pipe = ""; at = 0 }
	function where() { f = FILENAME; sub(/^\.\//, "", f); return f }
	match($0, /^[[:blank:]]*for[[:blank:]]+[A-Za-z_][A-Za-z0-9_]*[[:blank:]]+in[[:blank:]]+/) {
		r = substr($0, RLENGTH + 1)
		# What follows `in`: a $( or a backquote, then the command.
		if (substr(r, 1, 2) == "\044(") r = substr(r, 3)
		else if (substr(r, 1, 1) == bq) r = substr(r, 2)
		else r = ""
		sub(/^[[:blank:]]+/, "", r)
		split(r, w, /[[:blank:]]+/)
		sub(/[);]+$/, "", w[1]); sub(/[);]+$/, "", w[2])
		if (w[1] == "find" || w[1] == "ls" || (w[1] == "git" && (w[2] in lists)))
			printf "    %s:%d: %s\n", where(), FNR, $0
	}
	# A git listing of paths, without -z, piped on into a while loop.
	{
		l = $0
		# A comment, and a Markdown table row, which ends in a | too.
		if (pipe == "" && l !~ /^[[:blank:]]*[#|]/ &&
		    l ~ gitls &&
		    l !~ /(^|[[:blank:]])-z([[:blank:]]|$)/ && l !~ /--error-unmatch/) {
			pipe = l; at = FNR; text = $0
		} else if (pipe != "")
			pipe = pipe " " l
		if (pipe == "") next
		if (pipe ~ /\|[[:blank:]]*while[[:blank:]]/) {
			printf "    %s:%d: %s\n", where(), at, text
			pipe = ""
		} else if (l !~ /(\||\\)[[:blank:]]*$/)
			pipe = ""
	}' {} + | sort)
[ -z "$_list_loops" ] || report "a list of files is not read one name per line, whole" \
	"$_list_loops" \
	"\`for f in \$(...)\` splits every name at its blanks, and a tree holds" \
	"names with blanks (a duplicate's \`ft_x copy.c\`); git quotes a name with" \
	"a byte above 0x7f unless it is asked for -z. Write the listing to a file," \
	"or pipe it, from \`git ls-files -z ... | tr '\\0' '\\n'\`, into" \
	"\`while IFS= read -r f; do ... done\`."

# ...and the reader is part of it. `while read -r f` keeps a line whole except
# for its ends: read strips the blanks IFS holds from both, so a name read so
# loses a trailing blank (`./y.c ` comes out `./y.c`, a file that does not
# exist) and a git listing's name its leading one. The rule above named the
# reader and never looked at it, and conventions.sh read its own lists that
# way in seven rules (TO VERIFY V58). So a loop that reads ONE variable a
# line gives that read its IFS: `while IFS= read -r f`. One variable is the
# shape of a line meant whole; a loop reading two or more (`while read -r
# _case _row`) wants its splitting and is not this. Matched in command
# position only, with quoted text taken out first, so a toy script written
# as a string and a page that names the form in backquotes are not loops.
# And a read without -r, which also takes each backslash as an escape and
# drops it (`a\b.c` read as `ab.c`), whatever its IFS: the rule matched
# `read -r` alone, so a one-name `while read f` passed it (review of
# W7-V58). Each line says which of the two it lacks.
_trim_loops=$(text_files \( -name '*.md' -o -name '*.sh' \) ! -path ./TODO.md ! -path ./HISTORY.md \
	-exec awk '
	function where() { f = FILENAME; sub(/^\.\//, "", f); return f }
	/^[[:blank:]]*[#|]/ { next }
	{
		l = $0
		gsub(/\047[^\047]*\047/, "", l)
		gsub(/"[^"]*"/, "", l)
		if (!match(l, /(^|[|;&({!]|[^A-Za-z0-9_](do|then|else))[[:blank:]]*while[[:blank:]]+(IFS=[^[:blank:]]*[[:blank:]]+)?read([[:blank:]]+-[A-Za-z]+)*[[:blank:]]+[A-Za-z_][A-Za-z0-9_]*[[:blank:]]*([;<)|&]|$)/))
			next
		m = substr(l, RSTART, RLENGTH)
		ifs = (m ~ /while[[:blank:]]+IFS=/)
		raw = (m ~ /read([[:blank:]]+-[A-Za-z]+)*[[:blank:]]+-[A-Za-z]*r/)
		if (ifs && raw) next
		printf "    %s:%d: %s   <- %s\n", where(), FNR, $0, \
			(!ifs && !raw ? "no IFS=, no -r" : !ifs ? "no IFS=" : "no -r")
	}' {} + | sort)
[ -z "$_trim_loops" ] || report "a loop reads one name a line, and its read changes the name" \
	"$_trim_loops" \
	"\`read -r f\` strips the blanks at both ends of the line, so a name that" \
	"begins or ends with one is read as another file; \`read f\`, without -r," \
	"also drops each backslash. A loop that reads the whole line into one" \
	"variable sets IFS for its read alone, and reads raw:" \
	"\`while IFS= read -r f; do ... done\`."

# ---------------------------------------------------------------------------
# N. A test program that writes an escape of its own declares it.
#
# diff_output.sh renders the bytes of a failing cell (\xHH, \t, the backslash
# doubled), and a test program whose value holds a byte that cannot travel raw
# -- Rush 00's whole rectangle on one row, C 02 ex01's NUL padding -- writes it
# escaped already. Rendered as raw bytes, such a cell was escaped a second
# time: Rush 00's "/\\\n" showed as "/\\\\\\n" under a legend saying \\ is one
# backslash, and C 02 ex01's "\0" as "\\0". Nothing tied the two together, and
# no arm saw it: pass and fail were right, only the first red a student reads
# was wrong. So a test program that WRITES an escape -- a print call whose
# string literal starts with an escaped backslash ("\\0", "\\x%02x", "\\%c"),
# or putchar('\\') -- is one of:
#   - named by a c_function that says escaped_values = True, which passes
#     diff_output.sh --escaped-values (the runner then checks the expected
#     file is in the notation, so declaring it and writing "\0" fails too);
#   - named only by a measuring macro (c_diff, c_cycles, c_perf,
#     c_reference_cost, c_mem_check), whose runners compare its fields with the
#     oracle's and never show them in a table, or by exports_files, which
#     hands the file to another package (the selftest builds C 02 ex12's diff
#     harness) and wires it to no runner at all;
#   - listed below with the macro that wires it and passes the flag itself,
#     which this check reads in defs.bzl so the entry cannot outlive it.
# A comment is not code: the notation can be described anywhere. One entry
# per line, FILE:MACRO.
_ESC_BY_MACRO='c-piscine/c-piscine-rush-00/tests/ex00/rush_capture.h:rush_variant'
_esc_writes() {  # _esc_writes FILE: its code lines that write an escape
	awk '
		/^[[:blank:]]*(\/\*|\*|\/\/)/ { next }
		{
			line = $0
			if ((line ~ /(^|[^A-Za-z0-9_])(s?n?printf|fprintf|dprintf|f?puts|write)[[:blank:]]*\(/ &&
			     index(line, "\"\\\\")) ||
			    line ~ /(^|[^A-Za-z0-9_])f?putc(har)?[[:blank:]]*\([[:blank:]]*\047\\\\\047/)
				printf "    %s:%d: %s\n", FILENAME, FNR, $0
		}' "$1"
}
_macro_passes_escaped() {  # _macro_passes_escaped NAME: defs.bzl's NAME passes the flag
	awk -v m="$1" '
		index($0, "def " m "(") == 1 { inm = 1; next }
		inm && /^def / { exit }
		inm && index($0, "\"--escaped-values\"") { found = 1; exit }
		END { exit !found }' tools/defs.bzl 2> /dev/null
}
_esc_ifs=$IFS
IFS='
'
for _m in $MODULES; do
	[ -d "$_m/tests" ] || continue
	find "$_m/tests" \( -type f -o -type l \) \( -name '*.c' -o -name '*.h' \) | sort > "$lex_d/files"
	while IFS= read -r _ef; do
		_ew=$(_esc_writes "$_ef")
		[ -n "$_ew" ] || continue
		_eb=${_ef##*/}
		# Every call of the module's BUILD that names the file: its macro,
		# and 1 when it says escaped_values = True.
		_ec=$(awk -v b="$_eb" '
			function flush() {
				if (kind != "" && (index(buf, "\"" b "\"") || index(buf, "/" b "\"")))
					printf "%s %d\n", kind, (buf ~ /escaped_values[ \t]*=[ \t]*True/)
				kind = ""; buf = ""
			}
			{
				line = $0
				sub(/#.*/, "", line)
				if (kind == "" && line ~ /^[a-z_][a-z0-9_]*\(/) {
					kind = line; sub(/\(.*/, "", kind)
					buf = ""; depth = 0
				}
				if (kind != "") {
					buf = buf " " line
					depth += gsub(/\(/, "(", line) - gsub(/\)/, ")", line)
					if (depth <= 0) flush()
				}
			}' "$_m/BUILD.bazel")
		case "$_ec" in *"c_function 1"*) continue ;; esac
		_eo=$(printf '%s\n' "$_ec" | awk '
			NF && $1 !~ /^(c_diff|c_cycles|c_perf|c_reference_cost|c_mem_check|exports_files)$/ { print $1 }')
		[ -n "$_ec" ] && [ -z "$_eo" ] && continue
		if [ -z "$_ec" ]; then
			_emac=""
			for _ee in $_ESC_BY_MACRO; do
				[ "${_ee%%:*}" = "$_ef" ] && _emac=${_ee#*:}
			done
			if [ -n "$_emac" ] && _macro_passes_escaped "$_emac"; then continue; fi
			if [ -n "$_emac" ]; then
				_ewhy="conventions.sh lists it as wired by $_emac, and $_emac in tools/defs.bzl passes no --escaped-values."
			else
				_ewhy="No call in $_m/BUILD.bazel names it, and conventions.sh's _ESC_BY_MACRO lists no macro that wires it."
			fi
		else
			_ewhy="$_m/BUILD.bazel names it in $(printf '%s' "$_eo" | sort -u | tr '\n' ' ')with no escaped_values = True."
		fi
		report "$_ef writes an escape of its own into the values a table shows" \
			"$_ew" "$_ewhy" \
			"diff_output.sh renders a cell's bytes itself, so a value escaped" \
			"already is escaped twice (\"/\\\\\\n\" shown as \"/\\\\\\\\\\\\n\") unless the" \
			"fixture says it is: write the notation of diff_output.sh's" \
			"HARNESS-ESCAPED VALUES and set escaped_values = True on the" \
			"c_function (a macro that wires the file passes --escaped-values" \
			"itself, and is listed in _ESC_BY_MACRO). Or print the bytes raw."
	done < "$lex_d/files"
done
for _ee in $_ESC_BY_MACRO; do
	[ -n "$(_esc_writes "${_ee%%:*}" 2> /dev/null)" ] && continue
	report "conventions.sh's _ESC_BY_MACRO lists ${_ee%%:*}, which writes no escape" \
		"An entry nothing needs exempts the next file that takes its name." \
		"Remove it, or fix the path."
done
IFS=$_esc_ifs

# ---------------------------------------------------------------------------
# N. A dump's harness publishes the addresses it passes.
#
# c_function(sanitize = True) is for a hex dump whose address column ASLR
# moves on every run. diff_output.sh --sanitize compares each row's address
# with the one the harness published on an "@addr <16 hex>" line before the
# dump; a harness that publishes none leaves it the old rule, which compares
# the column's width, case and step and never its value, so a program that
# never touched the pointer passed (finding 048). C 02 ex12's harness
# publishes; nothing made the next one. So the test program of every
# c_function that says sanitize = True, and each of its readings' (which get
# the flag too), writes "@addr" somewhere in its code.
_san_ifs=$IFS
IFS='
'
# The calls are read as Starlark reads them, wherever they sit -- indented
# in a list comprehension too -- and the harness from `test` by keyword or
# by position (num, fn, test). A call whose num or harness is not a literal,
# or whose harness is not there, is reported rather than passed over: a
# check that cannot find the harness it is for has checked nothing.
for _m in $MODULES; do
	[ -f "$_m/BUILD.bazel" ] || continue
	# "OK NN FILE" for the harness and every reading main of each c_function
	# call that says sanitize = True; "UNREAD LINE WHY" for one this cannot
	# resolve.
	for _sp in $(LC_ALL=C awk '
		# The line with its comment cut, a # inside a string kept.
		function uncomment(l,    i, c, q, out) {
			out = ""; q = ""
			for (i = 1; i <= length(l); i++) {
				c = substr(l, i, 1)
				if (q != "") {
					out = out c
					if (c == "\\") { out = out substr(l, i + 1, 1); i++ }
					else if (c == q) q = ""
					continue
				}
				if (c == "#") break
				if (c == "\"" || c == "\047") q = c
				out = out c
			}
			return out
		}
		function trim(x) { sub(/^[ \t\n]+/, "", x); sub(/[ \t\n]+$/, "", x); return x }
		function lit(x) {
			x = trim(x)
			if (x ~ /^"[^"]*"$/) return substr(x, 2, length(x) - 2)
			return ""
		}
		{ text = text uncomment($0) "\n" }
		END {
			npos = split("num fn test srcs hdrs expected sanitize", pname, " ")
			rest = text; off = 0
			while (match(rest, /(^|[^A-Za-z0-9_.])c_function[ \t\n]*\(/)) {
				at = off + RSTART + RLENGTH
				pre = substr(text, 1, at - 1)
				line = 1 + gsub(/\n/, "\n", pre)
				# The arguments, to the matching parenthesis, split at
				# the commas outside brackets and strings.
				na = 0; cur = ""; d = 0; q = ""
				for (i = at; i <= length(text); i++) {
					c = substr(text, i, 1)
					if (q != "") {
						cur = cur c
						if (c == "\\") { cur = cur substr(text, i + 1, 1); i++ }
						else if (c == q) q = ""
						continue
					}
					if (c == "\"" || c == "\047") { q = c; cur = cur c; continue }
					if (c == "(" || c == "[" || c == "{") d++
					if (c == ")" || c == "]" || c == "}") {
						if (d == 0) break
						d--
					}
					if (c == "," && d == 0) { arg[++na] = cur; cur = ""; continue }
					cur = cur c
				}
				if (trim(cur) != "") arg[++na] = cur
				off = i
				rest = substr(text, off + 1)
				split("", val)
				npos_seen = 0
				for (k = 1; k <= na; k++) {
					a = trim(arg[k])
					if (match(a, /^[A-Za-z_][A-Za-z0-9_]*[ \t\n]*=[^=]/)) {
						key = a; sub(/[ \t\n]*=.*/, "", key)
						v = a; sub(/^[^=]*=/, "", v)
						val[key] = trim(v)
					} else if (a ~ /^\*/) {
						val["**"] = a
					} else {
						npos_seen++
						if (npos_seen <= npos) val[pname[npos_seen]] = a
					}
				}
				san = ("sanitize" in val) ? val["sanitize"] : "False"
				if (san == "False") continue
				if (san != "True") { print "UNREAD " line " its sanitize is not the literal True or False"; continue }
				n = lit(val["num"])
				if (n !~ /^[0-9][0-9]$/) { print "UNREAD " line " its num is not a literal \"NN\""; continue }
				t = ("test" in val) ? lit(val["test"]) : ""
				if (t == "" || t ~ /[ \t]/) { print "UNREAD " line " its test, the harness, is not a literal file name"; continue }
				print "OK " n " " t
				body = ""
				for (k = 1; k <= na; k++) body = body "," arg[k]
				while (match(body, /"main"[ \t\n]*:[ \t\n]*"[^"]*"/)) {
					f = substr(body, RSTART, RLENGTH); sub(/^"main"[^"]*"/, "", f); sub(/"$/, "", f)
					print "OK " n " " f
					body = substr(body, RSTART + RLENGTH)
				}
			}
		}' "$_m/BUILD.bazel"); do
		_sv=${_sp#* }
		case $_sp in
		UNREAD\ *)
			report "$_m/BUILD.bazel:${_sv%% *}: a c_function says sanitize = True, and this check cannot find its harness" \
				"Why: ${_sv#* }." \
				"This check reads each sanitize harness for its @addr line, and one it" \
				"cannot find is one it has not checked. Write num and test as literal" \
				"strings (num = \"NN\", test = \"test_x.c\") in a call of its own."
			continue ;;
		esac
		_sf="$_m/tests/ex${_sv%% *}/${_sv#* }"
		if [ ! -f "$_sf" ]; then
			report "$_sf, a sanitize harness its c_function names, does not exist" \
				"This check reads each sanitize harness for its @addr line, and one that" \
				"is not there is one it has not checked. Fix the name, or the call."
			continue
		fi
		awk '/^[[:blank:]]*(\/\*|\*|\/\/)/ { next } index($0, "@addr") { f = 1 } END { exit !f }' \
			"$_sf" && continue
		report "$_sf publishes no @addr line, and its c_function says sanitize = True" \
			"diff_output.sh --sanitize checks each row's address against the one the" \
			"harness published before the dump (\"@addr <16 lowercase hex>\", a line of" \
			"its own). Without one it can compare only the column's width, case and" \
			"step, never the value: a dump that never touched the pointer passes." \
			"Write the address you pass before each call, as" \
			"c-piscine/c-piscine-c-02/tests/ex12/test_print_memory.c does."
	done
done
IFS=$_san_ifs

# ---------------------------------------------------------------------------
# N. A harness that checks a printed address puts the block above 4 GiB.
#
# An address cut to 32 bits is the real one when the block it points into
# sits below 4 GiB, and a reader harness's heap does: the readers are linked
# position-dependent, so the heap starts just after the image, and C 02
# ex12's diff passed 100000 cases over a dump that narrowed every address
# (finding 048, the mutation run of 2026-10-03). tools/diffio.h's dio_high
# moves a block above 4 GiB, or the harness stops. So, in any module's
# tests/, outside comments:
#   - a C file that includes diffio.h and turns a pointer into a number (a
#     "(uintptr_t)" cast) calls dio_high;
#   - a test program that publishes an address ("@addr") calls it too, or
#     says where its blocks live on a line of its own -- an output fixture's
#     local arrays are on the stack, near the top of the address space:
#         /* conventions: above 4 GiB -- <where its blocks are, and why> */
# The next harness that checks a printed address -- Common Core ft_printf's
# %p is the obvious one -- would otherwise meet the same trap, with nothing
# to say so (docs/new-project.md, item 22).
_hi_ifs=$IFS
IFS='
'
for _m in $MODULES; do
	[ -d "$_m/tests" ] || continue
	find "$_m/tests" \( -type f -o -type l \) -name '*.c' | sort > "$lex_d/files"
	while IFS= read -r _hf; do
		_hk=$(awk '
			/^[[:blank:]]*(\/\*|\*|\/\/)/ { next }
			/^[[:blank:]]*#[[:blank:]]*include[[:blank:]]*"diffio\.h"/ { dio = 1 }
			index($0, "(uintptr_t)") { cast = 1 }
			index($0, "@addr") { pub = 1 }
			index($0, "dio_high(") { high = 1 }
			END {
				if (high) exit
				if (dio && cast) print "reader"
				else if (pub) print "publisher"
			}' "$_hf")
		[ -n "$_hk" ] || continue
		grep -qE 'conventions: above 4 GiB -- .+' "$_hf" && continue
		if [ "$_hk" = reader ]; then
			report "$_hf turns a pointer into a number, and puts no block above 4 GiB" \
				"It includes diffio.h and casts to uintptr_t, the way a harness checks" \
				"an address the function printed against the one it passed. A reader" \
				"is linked position-dependent and its heap sits below 4 GiB, where an" \
				"address cut to 32 bits is the real one, so the check cannot see it" \
				"(finding 048). Pass the block through dio_high (tools/diffio.h) before" \
				"the call, as c-piscine/c-piscine-c-02/tests/ex12/diff_print_memory.c" \
				"does, or say why it needs none, on a line of its own:" \
				"    /* conventions: above 4 GiB -- <where its blocks are, and why> */"
		else
			report "$_hf publishes an address, and does not say its blocks are above 4 GiB" \
				"An address the test program publishes (@addr) is checked against what" \
				"the function printed, and below 4 GiB an address cut to 32 bits is the" \
				"real one (finding 048). Pass the block through dio_high (tools/diffio.h)," \
				"or say where its blocks live, on a line of its own:" \
				"    /* conventions: above 4 GiB -- <where its blocks are, and why> */"
		fi
	done < "$lex_d/files"
done
IFS=$_hi_ifs

# ---------------------------------------------------------------------------
# N. The harness's own output fixtures print unbuffered, and nothing else does;
#    and only they are read case by case after a crash.
#
# diff_output.sh sends a program's stdout to a file, where the C library
# buffers it fully: a fixture that crashed in its fifth case took the lines of
# the first four down with it, every row of the table read "(no line)", and
# the hints went to the exercise's most basic concept -- whatever the student
# had got right (findings 064 and 129). tools/unbuffered_stdout.c fixes that
# by construction, and defs.bzl builds every output fixture through
# _output_fixture_binary so none can miss it. With it, the output test passes
# diff_output.sh --harness-fixture, and a missing row is then called the case that was
# running -- a claim that is false of any other binary, where a crash can take
# buffered lines with it. diff_output.sh refuses --harness-fixture on a binary without
# the library's marker, at run time; these checks catch the same mistakes at
# review time, where nothing has to crash first:
#   - an output fixture built without it: a harness main (the macro's
#     test_f, or a tests/ file named test_*.c or survive_*.c) as the harness
#     of a _student_bin, or in the srcs of a cc_binary, in defs.bzl -- or ANY
#     tests/ file in the srcs of a cc_binary in a module BUILD, which builds
#     no binary of its own;
#   - the library reaching a binary that is not one: _output_fixture_binary
#     around anything but a harness main -- a student's program is graded
#     buffered, as the grader runs it, and the diff, perf, cycles and refcost
#     binaries measure what a write per printf would change -- and any BUILD
#     file outside tools/ naming the library;
#   - --harness-fixture on a binary the same macro did not build with
#     _output_fixture_binary (the --bin value just before it names the
#     variable), or anywhere in a module BUILD, whose hand-written tests run a
#     student's program or a gate.
# Starlark cannot see which binary a runner will be handed, so this is read
# from the text, like the gate_sanitize check above.
_ub=$(awk '
	function flush(   srcs, nm) {
		# What the binary is built around: its `harness` (a _student_bin, and
		# so an _output_fixture_binary), or the srcs of a cc_binary.
		srcs = buf
		if (srcs ~ /harness[ \t]*=/) sub(/.*harness[ \t]*=/, "", srcs)
		else sub(/.*srcs[ \t]*=/, "", srcs)
		sub(/,[ \t]*(srcs|hdrs|deps|copts|includes|tags|linkopts|features|archive|dir|asan|diffio|makefile|make_data|prototype)[ \t]*=.*/, "", srcs)
		tname = buf; sub(/.*name[ \t]*=[ \t]*/, "", tname); sub(/,.*/, "", tname)
		harness = (srcs ~ /test_f|\/test_[a-z0-9_]*\.c|\/survive_[a-z0-9_]*\.c/)
		if ((kind == "cc_binary" || kind == "_student_bin") && harness)
			printf "    line %d: a %s built from a harness main, not through _output_fixture_binary (%s)\n", start, kind, srcs
		measures = (tname ~ /diff|perf|cycles|refcost|asan|probe/)
		if (kind == "_output_fixture_binary" && (!harness || measures))
			printf "    line %d: _output_fixture_binary around something that is not an output fixture (%s)\n", start, srcs
		if (kind == "_output_fixture_binary") fx[tname] = 1
		kind = ""; buf = ""
	}
	# A new def forgets the fixtures the last one built.
	/^def / { split("", fx); lastbin = ""; wantbin = 0 }
	{
		line = $0
		sub(/#.*/, "", line)
		if (kind == "" && line ~ /^[ \t]*(cc_binary|_student_bin|_output_fixture_binary)\(/) {
			kind = line; sub(/^[ \t]*/, "", kind); sub(/\(.*/, "", kind)
			buf = ""; depth = 0; start = FNR
		}
		if (kind != "") {
			buf = buf " " line
			o = gsub(/\(/, "(", line)
			c = gsub(/\)/, ")", line)
			depth += o - c
			if (depth <= 0) flush()
		}
		# The variable the last --bin named: "$(location :%s)" % binname.
		if (wantbin) {
			v = line
			if (sub(/.*%[ \t]*/, "", v)) { sub(/[^A-Za-z0-9_].*/, "", v); lastbin = v }
			wantbin = 0
		}
		if (line ~ /"--bin",/) wantbin = 1
		if (line ~ /"--harness-fixture"/ && !(lastbin in fx))
			printf "    line %d: --harness-fixture on %s, which this macro did not build with _output_fixture_binary\n", FNR, (lastbin == "" ? "a binary it names no variable for" : lastbin)
	}' tools/defs.bzl)
[ -z "$_ub" ] || report \
	"tools/defs.bzl builds an output fixture without unbuffered stdout, gives the library to another binary, or passes --harness-fixture for one it did not build" \
	"$_ub" \
	"Build a harness main that diff_output.sh runs with _output_fixture_binary," \
	"and nothing else, and pass --harness-fixture only for such a binary: see" \
	"tools/unbuffered_stdout.c for why, and for where that library must never go."
for _m in $MODULES; do
	_ubm=$(grep -n 'unbuffered_stdout\|"--harness-fixture"' "$_m/BUILD.bazel" 2> /dev/null)
	[ -z "$_ubm" ] || report \
		"$_m/BUILD.bazel names tools/unbuffered_stdout or passes --harness-fixture" \
		"$_ubm" \
		"Only defs.bzl links it, only into the harness's own output fixtures," \
		"and only their output tests pass --harness-fixture. A module that links it by" \
		"hand can reach a student's program, which is graded buffered, the way" \
		"the grader runs it; and --harness-fixture on one would call its first missing" \
		"row the case that was running when a crash can take buffered lines."
	_cbm=$(awk '
		/^[ \t]*#/ { next }
		/^[ \t]*cc_binary\(/ { p = 1; buf = ""; start = FNR }
		p { buf = buf $0 }
		p && /\)/ {
			o = gsub(/\(/, "(", buf); c = gsub(/\)/, ")", buf)
			if (o <= c) { p = 0; if (buf ~ /tests\//) printf "    line %d: a cc_binary built from a tests/ file\n", start }
		}' "$_m/BUILD.bazel" 2> /dev/null)
	[ -z "$_cbm" ] || report \
		"$_m/BUILD.bazel builds its own binary from a tests/ file" \
		"$_cbm" \
		"A module builds no test program by hand: the macros in tools/defs.bzl" \
		"build each one, and an output fixture through _output_fixture_binary," \
		"which links tools/unbuffered_stdout.c and lets its output test say so."
done

# ---------------------------------------------------------------------------
# N. How a program ended is read from tools/exit_status, never guessed from
#    its status.
#
# The shell reports "killed by signal N" as 128+N, which is also a status a
# program can return: `return (-1);` is 255. Reading every status above 128 as
# a crash told a student whose program returned -1 on an error input that it
# "died on signal 127", and failed it at basic, where the Run contract judges
# no status at all (review of wave 3's output tables). tools/exit_status asks
# waitpid(), which knows, and every runner reads it through tools/runner_lib.sh
# (rl_run, rl_classify); perf_run and shell_check.sh's ck_run say it by name.
# A debt list here once exempted, by name, the runners that still guessed;
# wave 3 emptied it, so it is gone, and no script may guess.
#
# THE GUESS HAS MANY SPELLINGS, and this rule once matched two of them:
# `-gt 128` and `- 128)`. `-gt 127`, `$((rc-128))`, `-eq 134`, `= "137"` and a
# `139)` case label all passed (review of wave 3). What it matches now, on a
# line that is not a comment -- exactly this, no more:
#   * -gt, -ge, -lt or -le, blanks, then a number from 120 to 129, bare or in
#     double quotes: the line between a return and a signal, or the shell's
#     126 and 127;
#   * 128 subtracted from anything that ends in a letter, a digit, `_`, `}`,
#     `)`, `"` or `?` -- a name, ${...}, $?, a quoted string -- with or without
#     blanks around the minus: `$((rc-128))`, `$(($? - 128))`;
#   * -eq, -ne or an `=` (so ==, != and the arithmetic <= and >= as well),
#     blanks, then a number from 130 to 139 or 150 to 159, bare or in double
#     quotes: a signal from SIGINT to SIGSEGV (an interrupt, a crash, an
#     abort, a kill), or SIGXCPU, SIGXFSZ or SIGSYS;
#   * one of those numbers alone as a case label, bare or in double quotes, at
#     the start of a line or after a `|`: `139)`, `134 | 139)`, `"137")`.
# It is a net for the spellings met so far, not a parser, and lets through
# what it does not name: `>` or `<` against any number (`$((rc > 128))`), -gt
# or -lt against 130-159, the 140s (141, SIGPIPE; 143, SIGTERM), a case glob
# (`13[0-9])`), a number in single quotes, and one with no blank after its
# operator (`-eq137`). An awk `length(s) > 150` is no status, and is not
# matched either. The one spelling it used to let through on purpose, a
# timeout arm `124 | 137)`, is a guess too now: tools/exit_status keeps the
# time itself (--timeout) and reports "timeout", so no reader has that arm
# and a 137 is only ever a SIGKILL.
#
# A line that tests a status that is not a program's says so right above it,
# the way a cut that is not an excerpt does:
#     # conventions: not-a-program-status -- <whose status, and why a number>
# tools/student_build.sh's died() is the one today: it judges the pinned
# toolchain's own status inside a build action, where tools/exit_status is not
# an input, and reads 126 or more as "did not answer" without naming a signal.
_EXIT_GUESS_RE='-(gt|ge|le|lt)[[:space:]]+"?12[0-9]"?([^0-9]|$)'
_EXIT_GUESS_RE="$_EXIT_GUESS_RE"'|[[:alnum:]_}")?][[:space:]]*-[[:space:]]*128([^0-9]|$)'
_EXIT_GUESS_RE="$_EXIT_GUESS_RE"'|(-eq|-ne|!?=)[[:space:]]+"?1[35][0-9]"?([^0-9]|$)'
_EXIT_GUESS_RE="$_EXIT_GUESS_RE"'|(^[[:space:]]*|\|[[:space:]]*)"?1[35][0-9]"?[[:space:]]*[|)]'
for _f in tools/*.sh; do
	[ -f "$_f" ] || continue
	_g=$(grep -nE -- "$_EXIT_GUESS_RE" "$_f" | grep -vE '^[0-9]+:[[:space:]]*#')
	# The lines right below a not-a-program-status line are not reported.
	_ok=$(grep -nE '^[[:space:]]*# conventions: not-a-program-status -- .+' "$_f" |
		cut -d: -f1 | while IFS= read -r _n; do echo $((_n + 1)); done | tr '\n' '|')
	[ -z "$_g" ] || [ -z "$_ok" ] || _g=$(printf '%s\n' "$_g" | grep -vE "^(${_ok%|}):")
	[ -z "$_g" ] || report \
		"$_f reads how a program ended from its status" \
		"$_g" \
		"A status above 128 is also what a program returns from -1 (255)." \
		"Run the program with rl_run and read how it ended with rl_classify" \
		"(tools/runner_lib.sh, \"THE HELPER THAT SAYS HOW A RUN ENDED\"):" \
		"RL_CAUSE says ok, exit, signal, runaway, timeout, noexec or stopped." \
		"A line that tests a status that is not a program's says so right" \
		"above it: # conventions: not-a-program-status -- <why>"
done

# ---------------------------------------------------------------------------
# N. .bazelrc keeps runfiles trees OUT of the output tree.
#
# Without `build --nobuild_runfile_links` Bazel writes a symlink forest per test
# into bazel-out, mirroring every data file it names, and keeps it. MEASURED,
# one output base after a full `bazel test //...`: 2,101,054 inodes with the
# trees, 86,160 without -- the ilp32 layer alone was 1.57M of them, 96 trees of
# zig's whole SDK. Bytes, almost none, which is why nothing warns: on 2026-08-14
# `df -h` read 19% while `df -i` read 100%, and every tool on the box failed
# with ENOSPC on file creation, the agent's own included.
#
# A line that removes nothing visible and fixes a failure nobody sees until the
# machine stops is exactly the kind a tidy-up deletes, so it is held here.
if ! grep -qE '^build[[:space:]]+--nobuild_runfile_links([[:space:]]|$)' .bazelrc; then
	report \
		".bazelrc no longer sets build --nobuild_runfile_links" \
		"Every test's runfiles tree then lands in bazel-out and stays there:" \
		"~2.1M inodes per output base on this suite, against ~86k without." \
		"Inodes are a fixed count per filesystem and exhaust long before" \
		"bytes do; when they run out, nothing on the machine can create a" \
		"file. See the note beside the flag in .bazelrc."
fi

# ---------------------------------------------------------------------------
# N. .bazelrc keeps going after a build error.
#
# A student's compile error, leftover main() or missing turn-in file is a BUILD
# error here, and without --keep_going the first one ends the run: measured,
# 113 of C 01's 117 targets NO STATUS over one leftover main(). docs/testing.md
# tells students they never need -k because this line sets it, so losing it
# turns one of their commonest mistakes back into a run that says nothing.
if ! grep -qE '^build[[:space:]]+--keep_going([[:space:]]|$)' .bazelrc; then
	report \
		".bazelrc no longer sets build --keep_going" \
		"Without it the first build error ends the whole run, and every target" \
		"that had not run yet prints NO STATUS. A student's own code no longer" \
		"fails the build (it becomes a stand-in), so the error it stops at is the" \
		"harness's: a file of its own, a download that failed -- and then every" \
		"exercise of the run says nothing. docs/testing.md promises the flag is" \
		"on. See the note beside it in .bazelrc."
fi

# ---------------------------------------------------------------------------
# N. Python targets print no banner on a fresh clone: no implicit __init__.py,
#    and every pinned requirement held to its files' hashes.
#
# rules_python printed two DEBUG/WARNING banners on every analysis -- a target
# "using implicit __init__.py creation", and a requirement file "generated
# without hashes" -- the first thing a student read on a fresh clone, and
# nothing they could act on (finding 047). The first is silenced repo-wide by
# .bazelrc's --incompatible_default_to_explicit_init_py, which has to stay
# while any BUILD file declares a Python target; the second by a --hash on
# every requirement of each file MODULE.bazel hands rules_python
# (requirements_lock), which a new requirement has to carry too.
_py_targets=$(text_files | grep -E '(^|/)BUILD(\.bazel)?$' | while IFS= read -r _pf; do
	grep -lE '^[[:blank:]]*py_(binary|test|library)\(' "$_pf"
done)
if [ -n "$_py_targets" ] && ! grep -qE '^(common|build)[[:blank:]]+--incompatible_default_to_explicit_init_py([[:blank:]]|$)' .bazelrc; then
	report ".bazelrc no longer sets --incompatible_default_to_explicit_init_py" \
		"$(printf '%s\n' "$_py_targets" | sed 's/^/declared in: /')" \
		"Without it rules_python makes an empty __init__.py in every folder of" \
		"a Python target's runfiles and says so in a WARNING banner on every" \
		"analysis, which a student reads as an error. See the note beside the" \
		"flag in .bazelrc."
fi
for _rq in $(sed -n 's|^[[:blank:]]*requirements_lock[[:blank:]]*=[[:blank:]]*"//\([^:"]*\):\([^"]*\)".*|\1/\2|p' MODULE.bazel 2> /dev/null); do
	[ -f "$_rq" ] || { report "MODULE.bazel names $_rq as a requirements_lock, and it is not there"; continue; }
	_unhashed=$(awk '
		/^[[:blank:]]*(#|$)/ && !cont { next }
		{
			line = $0
			if (!cont) { req = line; start = FNR; hashed = 0 }
			if (line ~ /--hash=sha256:[0-9a-f]+/) hashed = 1
			cont = (line ~ /\\[[:blank:]]*$/)
			if (!cont && !hashed) { sub(/[[:blank:]]*\\?[[:blank:]]*$/, "", req); printf "    %s:%d: %s\n", FILENAME, start, req }
		}' "$_rq")
	[ -z "$_unhashed" ] || report "$_rq has a requirement with no --hash" \
		"$_unhashed" \
		"Without a hash rules_python takes every file the index lists for the" \
		"version and prints \"generated without hashes\" each time Bazel starts." \
		"Add the version's files' SHA256 from PyPI, as the file's header says."
done

# ---------------------------------------------------------------------------
# N. .bazelrc.local must be imported AFTER anything it is meant to override.
#
# Bazel takes the LAST value it reads for a startup option, so an import at the
# top of .bazelrc cannot override a startup flag set below it. That is not a
# style point: the import sat above `startup --output_user_root=/tmp/bazelcache`
# for as long as this repo has existed, so tools/setup.sh wrote a redirect into
# .bazelrc.local, printed "output_user_root -> /goinfre/you/bazel", and Bazel
# went on using a shared /tmp path with no login in it -- on exactly the
# machines the redirect was written for. The docs had even described the trap
# while .bazelrc was falling into it.
#
# Nothing else could have caught this: every layer still passed, because they
# all ran fine out of the wrong directory.
IMPORT_LINE=$(grep -n '^try-import %workspace%/\.bazelrc\.local' .bazelrc |
	tail -n 1 | cut -d: -f1)
LAST_STARTUP=$(grep -n '^startup ' .bazelrc | tail -n 1 | cut -d: -f1)
if [ -z "$IMPORT_LINE" ]; then
	report \
		".bazelrc no longer imports .bazelrc.local" \
		"tools/setup.sh writes that file, and every per-checkout override" \
		"documented in docs/environment.md goes through it."
elif [ -n "$LAST_STARTUP" ] && [ "$IMPORT_LINE" -lt "$LAST_STARTUP" ]; then
	report \
		".bazelrc imports .bazelrc.local (line $IMPORT_LINE) BEFORE a startup option (line $LAST_STARTUP)" \
		"Bazel takes the LAST value read for a startup option, so the local" \
		"file cannot override that line -- it is read and then discarded." \
		"tools/setup.sh writes --output_user_root there; imported early, the" \
		"redirect it reports is not the one Bazel uses. Move the try-import to" \
		"the bottom of .bazelrc."
fi

# ---------------------------------------------------------------------------
# N. No tracked rc file names a shared place for Bazel's state.
#
# An rc file cannot say "per user" -- it expands %workspace% and nothing else --
# so any absolute path written in one is ONE path for every user of a machine.
# .bazelrc carried `startup --output_user_root=/tmp/bazelcache` as the fallback
# for every checkout without a .bazelrc.local, and on a campus box the second
# student's build then waited on the first one's lock or could not write the
# directory at all (finding 001). The per-user default is tools/bazel's job,
# the wrapper bazelisk runs (tools/drives.sh chooses); .bazelrc.local, which
# setup.sh writes, is per checkout and gitignored.
#
# EVERY rc file, and every flag that places state. The first version read two
# files and one flag, and an imported tools/*.bazelrc, or a shared path in
# --disk_cache, --repository_cache or --output_base, is the same collision.
# So: each file whose name holds "bazelrc" (the BUILD files declare them to
# //tools/tests:conventions by glob), except .bazelrc.local, and in it every
# line that is not a comment and gives a startup option, or one of the flags
# below, an absolute or home path. %workspace% is per checkout, so it is fine.
# The example is copied and edited by hand, so it may show a path a reader
# must replace (CHANGEME), never one that works as it is.
_state_flags='output_user_root|output_base|install_base|disk_cache|repository_cache|distdir'
find . -path './bazel-*' -prune -o -path ./.git -prune -o \
	\( -type f -o -type l \) -name '*bazelrc*' ! -name .bazelrc.local -print 2> /dev/null | sort > "$lex_d/files"
while IFS= read -r _rc; do
	_rc=${_rc#./}
	_line=$(grep -vE '^[[:space:]]*#' "$_rc" | grep -v CHANGEME |
		grep -E -e "--($_state_flags)[=[:space:]]+[\"']?(/|~|\\\$HOME)" \
			-e "^[[:space:]]*startup[[:space:]].*--[a-z_]+[=[:space:]]+[\"']?(/|~|\\\$HOME)" |
		head -n 1)
	if [ -n "$_line" ]; then
		report \
			"$_rc names a shared place for Bazel's state: $_line" \
			"An rc file cannot say 'per user', so that path is shared by every user" \
			"of the machine: on campus the second student's build waits on the" \
			"first one's lock, or cannot write the directory at all. tools/bazel" \
			"supplies a per-user root; a per-checkout path goes in .bazelrc.local."
	fi
done < "$lex_d/files"
if [ ! -x tools/bazel ] && [ -f tools/bazel ]; then
	report "tools/bazel is not executable" \
		"bazelisk runs the wrapper only if it is executable, and silently runs" \
		"Bazel without it -- which is Bazel's own ~/.cache/bazel: on campus, the" \
		"quota'd home."
fi

# ---------------------------------------------------------------------------
# N. 42's own files are registered, and every message names the one path.
#
# tools/resources.tsv lists each file 42 issues beside a subject, with the one
# path the harness reads it from. They were handled one file at a time, and the
# texts disagreed: shell-00's tarball "in its folder" (read as deliverable/ex07,
# which generate rebuilds) in one message and "next to BUILD.bazel" in another;
# rush-02's dictionary "wherever you like" while the subject's one-argument
# form reads it from a fixed place (findings 016, 161). So, per row: the path is
# inside the project and outside tests/; every file in named-in names the exact
# path; and every consumer is a label in the project (the target itself is run
# by the cold-clone rehearsal, which checks that it SKIPs naming the path). And
# anywhere a student reads: no line pairs a registered name with "its folder",
# "the exercise's folder" or "wherever you like".
#
# AND HOW EACH BUILD FILE NAMES IT, read as Starlark rather than as lines. The
# file is absent from the template, so a BUILD file that names it as a bare
# label -- `fixtures = ["resources.tar.gz"]` -- is an error that takes the whole
# package down there and nowhere else, which is why shell-00 stages it with
# glob([...], allow_empty = True). The rule used to be "BUILD names the file",
# grepped, which a comment satisfied (rush-02's did), and its one-file-glob
# detector matched a glob only when written on one line, so buildifier's
# layout escaped it. Now every string in every BUILD file is read with the
# call and keyword it sits in (build_strings), and per row:
#
#   * the project's BUILD files name the file outside a comment;
#   * each time, inside a glob with allow_empty = True, or in a list of file
#     NAMES (NAME_ATTRS, CALL.KEYWORD: exercise()'s files and optional in the
#     subject() contract, names under the turn-in directory that the files
#     layer matches and _deliverable_srcs globs, never labels; c_issued's
#     file, which it globs), or as a value of a case
#     dict that maps labels to names (NAME_DICTS: c_program's cwd_files, whose
#     values are what a staged file is CALLED in the run folder -- a program
#     that opens 42's file by name is given the harness's own under it, and a
#     name is no label) -- anything else is a label, and reported. A new
#     attribute that takes names rather than labels is added to NAME_ATTRS or
#     NAME_DICTS, with why. NAME_ATTRS names the call as well as the keyword:
#     it held bare keywords, so any call's `file =` was a name, and a macro
#     whose `file` takes a label would have passed here and broken the
#     template;
#   * a row whose role is turn-in has a c_issued(file = <its name>) in its
#     project: the subject turns the file in, so a turn-in without it must be
#     red at basic, and nothing else says so -- the template ships no copy and
#     its .gitignore keeps a student's out of commits (finding 162);
#
# and every glob of one literal file, anywhere, is a registered file's path:
# the shape that stages a file the checkout may not have is 42's material's.
NAME_ATTRS=" exercise.files exercise.optional c_issued.file "
NAME_DICTS=" cwd_files "
build_strings() {  # build_strings FILE... -- S and G records, tab-separated
	# S FILE LINE VALUE GLOB-ID KEYWORD CALL CALL-ID DKEY DOUTER
	#     one per string literal outside a comment; KEYWORD, CALL and CALL-ID
	#     are the innermost call's (sh_binary, srcs, and a number unique to
	#     that call in the run). DKEY and DOUTER place it in the dict literals
	#     inside that call: DKEY is the key of the innermost dict's entry it is
	#     (in) the value of, or "KEY" when it is that dict's key itself, and
	#     DOUTER the key the innermost dict is the value of -- so in
	#     cases = [{"cwd_files": {"a.dict": "numbers.dict"}}], "numbers.dict"
	#     has DKEY a.dict and DOUTER cwd_files, and "a.dict" has DKEY KEY.
	# G FILE LINE GLOB-ID ALLOW-EMPTY N FIRST   one per glob() call, N patterns
	awk '
		function flush(   t, n, i, c, q, v, sl, j, wd, d, g, k, ch, cn, ci, d1, d2, dk1, do1) {
			t = buf
			n = length(t)
			i = 1
			lno = 1
			dep = 0
			last = ""
			lid = ""
			while (i <= n) {
				c = substr(t, i, 1)
				if (c == "\n") { lno++; i++; continue }
				if (c == " " || c == "\t" || c == "\r" || c == "\\") { i++; continue }
				if (c == "#") {
					while (i <= n && substr(t, i, 1) != "\n") i++
					continue
				}
				if (c == "\"" || c == SQ) {
					q = c
					sl = lno
					v = ""
					if (substr(t, i, 3) == q q q) {
						i += 3
						while (i <= n && substr(t, i, 3) != q q q) {
							ch = substr(t, i, 1)
							if (ch == "\n") lno++
							if (ch == "\\") { v = v substr(t, i + 1, 1); i += 2; continue }
							v = v ch
							i++
						}
						i += 3
					} else {
						i++
						while (i <= n) {
							ch = substr(t, i, 1)
							if (ch == "\\") { v = v substr(t, i + 1, 1); i += 2; continue }
							if (ch == q || ch == "\n") break
							v = v ch
							i++
						}
						i++
					}
					# The innermost glob around it, and the keyword argument of
					# the innermost call: the attribute it is a value of.
					g = 0
					for (d = dep; d >= 1; d--) if (fg[d]) { g = fg[d]; break }
					k = ""
					cn = ""
					ci = 0
					for (d = dep; d >= 1; d--) if (ft[d] == "(") { k = fk[d]; cn = fc[d]; ci = fi[d]; break }
					# Its place in the dict literals inside that call.
					if (dep >= 1 && ft[dep] == "{" && dpos[dep] == "key") dk[dep] = v
					d1 = 0
					d2 = 0
					for (d = dep; d >= 1 && ft[d] != "("; d--) if (ft[d] == "{") { if (!d1) d1 = d; else if (!d2) d2 = d }
					dk1 = ""
					do1 = ""
					if (d1) dk1 = (d1 == dep && dpos[d1] == "key") ? "KEY" : dk[d1]
					if (d2) do1 = dk[d2]
					printf "S\t%s\t%d\t%s\t%d\t%s\t%s\t%d\t%s\t%s\n", file, sl, v, g, k, cn, ci, dk1, do1
					# A pattern of a glob: directly in the list that is its
					# first positional argument, or its include =.
					if (dep >= 2 && ft[dep] == "[" && fg[dep - 1] && (fk[dep - 1] == "" || fk[dep - 1] == "include")) {
						gn[fg[dep - 1]]++
						if (gn[fg[dep - 1]] == 1) gp[fg[dep - 1]] = v
					}
					last = "str"
					continue
				}
				if (c ~ /[A-Za-z_]/) {
					j = i
					while (j <= n && substr(t, j, 1) ~ /[A-Za-z0-9_]/) j++
					wd = substr(t, i, j - i)
					i = j
					if (last == "eq" && dep >= 1 && fg[dep] && fk[dep] == "allow_empty" && wd == "True")
						ga[fg[dep]] = 1
					last = "id"
					lid = wd
					continue
				}
				if (c == "(" || c == "[" || c == "{") {
					dep++
					ft[dep] = c
					fk[dep] = ""
					fg[dep] = 0
					fc[dep] = (c == "(" && last == "id") ? lid : ""
					fi[dep] = ++nc
					dk[dep] = ""
					dpos[dep] = (c == "{") ? "key" : ""
					if (c == "(" && last == "id" && lid == "glob") {
						ng++
						fg[dep] = ng
						ga[ng] = 0
						gn[ng] = 0
						gp[ng] = ""
						gl[ng] = lno
					}
					last = "open"
					i++
					continue
				}
				if (c == ")" || c == "]" || c == "}") {
					if (dep >= 1) {
						if (fg[dep])
							printf "G\t%s\t%d\t%d\t%d\t%d\t%s\n", file, gl[fg[dep]], fg[dep], ga[fg[dep]], gn[fg[dep]], gp[fg[dep]]
						dep--
					}
					last = "close"
					i++
					continue
				}
				if (c == "=") {
					if (substr(t, i + 1, 1) == "=") { i += 2; last = "op"; continue }
					if (last == "id" && dep >= 1 && ft[dep] == "(") fk[dep] = lid
					last = "eq"
					i++
					continue
				}
				if (c == ":" && dep >= 1 && ft[dep] == "{") {
					dpos[dep] = "val"
					last = "op"
					i++
					continue
				}
				if (c == ",") {
					if (dep >= 1 && ft[dep] == "(") fk[dep] = ""
					if (dep >= 1 && ft[dep] == "{") { dpos[dep] = "key"; dk[dep] = "" }
					last = "comma"
					i++
					continue
				}
				last = "op"
				i++
			}
		}
		# A single quote, which this program cannot spell inside the shell
		# quotes it is written in.
		BEGIN { SQ = sprintf("%c", 39) }
		FNR == 1 && NR > 1 { flush() }
		FNR == 1 { file = FILENAME; buf = "" }
		{ buf = buf $0 "\n" }
		END { if (NR > 0) flush() }
	' "$@"
}
_builds=$(find . -path './bazel-*' -prune -o -name BUILD.bazel -print 2> /dev/null | sed 's|^\./||' | sort)
# shellcheck disable=SC2086  # one word per BUILD file; none has a space
_bs=$(build_strings $_builds)
if [ ! -f tools/resources.tsv ]; then
	report "tools/resources.tsv is missing" \
		"It is the registry of 42's own files (resources.tar.gz, numbers.dict):" \
		"the template build strips from it, and the messages are checked against it."
else
	_rows=$(awk -F'\t' '!/^#/ && NF' tools/resources.tsv)
	_bad=$(printf '%s\n' "$_rows" | awk -F'\t' '
		!NF { next }
		NF != 8 { print "a row has " NF " columns, not 8: " $0; next }
		$4 != "harness" && $4 != "turn-in" { print $2 ": role \"" $4 "\" is neither harness nor turn-in" }
		index($3, $1 "/") != 1 { print $2 ": path " $3 " is not inside " $1 }
		$3 ~ /(^|\/)tests\// { print $2 ": path " $3 " is under tests/, which the template strip spares" }')
	[ -z "$_bad" ] || report "tools/resources.tsv has malformed rows" "$_bad"
	_names=""
	_oldifs=$IFS
	IFS='
'
	for _row in $_rows; do
		IFS=$_oldifs
		_rp=$(printf '%s' "$_row" | cut -f1)
		_rf=$(printf '%s' "$_row" | cut -f2)
		_rpath=$(printf '%s' "$_row" | cut -f3)
		_rrole=$(printf '%s' "$_row" | cut -f4)
		_rcons=$(printf '%s' "$_row" | cut -f6)
		_rnamed=$(printf '%s' "$_row" | cut -f7)
		_names="$_names $_rf"
		if [ ! -f "$_rp/BUILD.bazel" ]; then
			report "tools/resources.tsv: $_rf belongs to $_rp, which has no BUILD.bazel" \
				"A row for a project that does not exist strips and checks nothing."
		else
			# Every string in the project's BUILD files that is the file: its
			# line, the glob it is in and whether that allows empty, and the
			# attribute it is a value of.
			_uses=$(printf '%s\n' "$_bs" | awk -F'\t' -v p="$_rp/" -v f="$_rf" '
				$1 == "G" && index($2, p) == 1 { ae[$2 "\t" $4] = $5 }
				$1 == "S" && index($2, p) == 1 && ($4 == f || substr($4, length($4) - length(f)) == "/" f) {
					n++; file[n] = $2; line[n] = $3; g[n] = $5; kw[n] = $6; cl[n] = $7
					dn[n] = ($10 != "" && $9 != "KEY") ? $10 : ""
				}
				END {
					for (i = 1; i <= n; i++)
						print file[i] "|" line[i] "|" (g[i] ? "glob" : "-") "|" ae[file[i] "\t" g[i]] "|" kw[i] "|" dn[i] "|" cl[i]
				}')
			if [ -z "$_uses" ]; then
				report "tools/resources.tsv: $_rp's BUILD files never name $_rf outside a comment" \
					"The registry says the project uses it; its BUILD file should say how" \
					"(the glob that stages it, the files list that allows it)."
			fi
			# `|`, not a tab: a tab is IFS white space, so an empty field
			# between two would vanish and shift the rest.
			_labels=$(printf '%s\n' "$_uses" | while IFS='|' read -r _uf _ul _ug _ua _uk _ud _uc; do
				[ -n "$_uf" ] || continue
				if [ "$_ug" = glob ]; then
					[ "$_ua" = 1 ] || echo "$_uf:$_ul: in a glob without allow_empty = True"
				else
					case "$NAME_ATTRS" in
						*" ${_uc:-none}.${_uk:-none} "*) continue ;;
					esac
					case "$NAME_DICTS" in
						*" ${_ud:-none} "*) continue ;;
					esac
					echo "$_uf:$_ul: as a label${_uk:+ (in $_uk)}"
				fi
			done)
			if [ "$_rrole" = turn-in ] && ! printf '%s\n' "$_bs" | awk -F'\t' -v p="$_rp/" -v f="$_rf" '
				$1 == "S" && index($2, p) == 1 && $4 == f && $6 == "file" && $7 == "c_issued" { ok = 1 }
				END { exit !ok }'; then
				report "tools/resources.tsv: $_rf is turned in, and $_rp has no c_issued(file = \"$_rf\")" \
					"The subject makes it part of the turn-in, the template ships no copy" \
					"and its .gitignore keeps a student's out of every commit, so nothing" \
					"else says when it is missing: c_issued's test fails at basic until" \
					"it is there (tools/defs.bzl)."
			fi
			[ -z "$_labels" ] || report "a BUILD file names 42's $_rf in a way that breaks the template" \
				"$_labels" \
				"The file is not in the template, so a label naming it -- or a glob that" \
				"may not match nothing -- is an error that takes the whole package down" \
				"there. Stage it with glob([\"$_rf\"], allow_empty = True), as shell-00 does."
		fi
		for _t in $(printf '%s' "$_rcons" | tr ',' ' '); do
			[ "$_t" = "-" ] && continue
			_tp=${_t#//}
			_tp=${_tp%%:*}
			case "$_t" in
				//"$_rp":* | //"$_rp"/*:*) ;;
				*) report "tools/resources.tsv: $_rf's consumer $_t is not a target of $_rp" \
					"A consumer is a test in the project that reads the file and SKIPs" \
					"while it is absent; the rehearsal runs each one on the template." ;;
			esac
			[ -f "$_tp/BUILD.bazel" ] || report "tools/resources.tsv: $_rf's consumer $_t names a package with no BUILD.bazel"
		done
		for _nf in $(printf '%s' "$_rnamed" | tr ',' ' '); do
			[ "$_nf" = "-" ] && continue
			# The template build applies the patch and deletes it, so on the
			# template its passages are the README's.
			[ "$_nf" = tools/template_docs.patch ] && [ ! -f "$_nf" ] && _nf=README.md
			if [ ! -f "$_nf" ]; then
				report "tools/resources.tsv: $_rf is to be named in $_nf, which does not exist"
			elif ! grep -qF "$_rpath" "$_nf"; then
				report "$_nf mentions $_rf without its one path, $_rpath" \
					"tools/resources.tsv says this text tells a student where 42's file" \
					"goes; a path it does not spell out is read as the nearest folder," \
					"and deliverable/ is rebuilt or pushed."
			fi
		done
		IFS='
'
	done
	IFS=$_oldifs
	set -- README.md docs/*.md tools/*.sh tools/template_docs.patch
	find . -path './bazel-*' -prune -o -path '*/tests/*' -name '*.sh' -print 2> /dev/null | sort > "$lex_d/files"
	while IFS= read -r _tf; do
		set -- "$@" "$_tf"
	done < "$lex_d/files"
	for _rf in $_names; do
		_vague=$(grep -nIE -i "its folder|exercise'?s? folder|exercise'?s directory|wherever you like" \
			"$@" 2> /dev/null | grep -F "$_rf" || true)
		[ -z "$_vague" ] || report "a text sends a student to a vague place for 42's $_rf" \
			"$_vague" \
			"tools/resources.tsv names the one path it goes to: say that path."
	done
	# Every glob of ONE literal file (no * ? [), however it is laid out.
	_single=$(printf '%s\n' "$_bs" | awk -F'\t' '$1 == "G" && $6 == 1 && $7 !~ /[*?[]/ { print $2 "\t" $3 "\t" $7 }')
	_oldifs=$IFS
	IFS='
'
	for _g in $_single; do
		IFS=$_oldifs
		_gf=$(printf '%s' "$_g" | cut -f1)
		_gl=$(printf '%s' "$_g" | cut -f2)
		_lit=$(printf '%s' "$_g" | cut -f3)
		_bd=${_gf%/BUILD.bazel}
		[ "$_bd" != BUILD.bazel ] || _bd=.
		printf '%s\n' "$_rows" | awk -F'\t' -v w="$_bd/$_lit" '$3 == w { ok = 1 } END { exit !ok }' ||
			report "$_gf:$_gl globs the single file $_lit, which tools/resources.tsv does not list for $_bd" \
				"A one-name glob with allow_empty stages a file the checkout may not" \
				"have: 42's material, stripped from the template. Register it, so the" \
				"strip, the ignore rule, the placeholder and every message follow."
		IFS='
'
	done
	IFS=$_oldifs
fi

# ---------------------------------------------------------------------------
# N. A script `bazel run` starts finds its files in the workspace, not beside $0.
#
# Under `bazel run`, $0 is bazel-bin's link to the script and nothing sits
# beside it: not another source file of the package, and not a data
# dependency either -- data lands in the runfiles tree, which is the working
# directory, not the directory of $0. init.sh and env_drift.sh sourced
# tools/drives.sh from beside $0, so both exited 2 under `bazel run` on every
# machine while every selftest arm stayed green: the arms ran them from tools/,
# where drives.sh is. So, in the script of every sh_binary (read from the BUILD
# files as Starlark, so a module's generate target reaches tools/generate.sh
# too): a path built on the directory of $0 -- `$(dirname "$0")/x`,
# `$(cd "$(dirname "$0")" && pwd)/x`, `${0%/*}/x` -- names a file the script
# must ALSO look for in the workspace, on another line naming the same file and
# $BUILD_WORKSPACE_DIRECTORY, or $WS where WS is set from it. Beside $0 first
# is fine: that is how the selftest reaches a runner. `$(dirname "$0")/..`
# alone, the workspace of a hand run, is exempt, because WS takes
# BUILD_WORKSPACE_DIRECTORY before it. A variable holding the directory of $0
# is followed (init.sh's was `_self_dir=${0%/*}`); one derived from it by any
# other step is not.
_srb=$(printf '%s\n' "$_bs" | awk -F'\t' '$1 == "S" && $7 == "sh_binary" && $6 == "srcs" { print $2 "\t" $4 }')
_srp=""
_oldifs=$IFS
IFS='
'
for _sb in $_srb; do
	IFS=$_oldifs
	_sbf=${_sb%%	*}
	_sbl=${_sb#*	}
	_sbd=${_sbf%/BUILD.bazel}
	[ "$_sbd" != BUILD.bazel ] || _sbd=.
	case "$_sbl" in
		@*) _sbp="" ;;
		//*:*) _sbp=${_sbl#//}; _sbp="${_sbp%%:*}/${_sbp#*:}" ;;
		//*) _sbp="" ;;
		:*) _sbp="$_sbd/${_sbl#:}" ;;
		*) _sbp="$_sbd/$_sbl" ;;
	esac
	_sbp=${_sbp#./}
	[ -n "$_sbp" ] && [ -f "$_sbp" ] && _srp="$_srp
$_sbp"
	IFS='
'
done
IFS=$_oldifs
for _sp in $(printf '%s\n' "$_srp" | sed '/^$/d' | sort -u); do
	_beside=$(awk -v f="$_sp" '
		# rest: what follows a directory of $0 on line i. A path under it is
		# recorded, except the parent alone.
		function ref(i, rest,   p, n) {
			sub(/^"/, "", rest)
			if (!match(rest, /^\/[A-Za-z0-9_.\/-]+/)) return
			p = substr(rest, 2, RLENGTH - 1)
			if (p == ".." || p == "../") return
			n = p
			sub(/\/+$/, "", n)
			sub(/.*\//, "", n)
			if (n == "" || n == "." || n == "..") return
			nr++; RL[nr] = i; RP[nr] = p; RN[nr] = n
		}
		/^[[:space:]]*#/ { next }
		{ L[NR] = $0; N = NR }
		/^[[:space:]]*WS=.*BUILD_WORKSPACE_DIRECTORY/ { ws = 1 }
		END {
			# The variables that hold the directory of $0 itself -- init.sh
			# kept it in _self_dir, and the lookup read "$_self_dir/drives.sh".
			for (i = 1; i <= N; i++) {
				if (!(i in L)) continue
				s = L[i]
				while (match(s, /(^|[^A-Za-z_0-9$])[A-Za-z_][A-Za-z_0-9]*=/)) {
					a = substr(s, RSTART, RLENGTH)
					s = substr(s, RSTART + RLENGTH)
					sub(/^[^A-Za-z_]/, "", a)
					sub(/=$/, "", a)
					v = s
					sub(/;.*/, "", v)
					gsub(/["[:space:]]/, "", v)
					if (v == "${0%/*}" || v == "$(dirname$0)" || v == "$(cd$(dirname$0)&&pwd)")
						DV[a] = 1
				}
			}
			for (i = 1; i <= N; i++) {
				if (!(i in L)) continue
				t = L[i]
				while (match(t, /dirname "?\$0"?\)|\$\{0%\/\*\}/)) {
					rest = substr(t, RSTART + RLENGTH)
					t = rest
					sub(/^"?[[:space:]]*&&[[:space:]]*pwd[[:space:]]*\)/, "", rest)
					ref(i, rest)
				}
				for (v in DV) {
					t = L[i]
					while ((k = index(t, "$" v)) > 0) {
						t = substr(t, k + length(v) + 1)
						if (t !~ /^[A-Za-z_0-9]/) ref(i, t)
					}
					t = L[i]
					while ((k = index(t, "${" v "}")) > 0) {
						t = substr(t, k + length(v) + 3)
						ref(i, t)
					}
				}
			}
			for (r = 1; r <= nr; r++) {
				ok = 0
				for (j in L) {
					if (j + 0 == RL[r] || !index(L[j], RN[r])) continue
					if (index(L[j], "BUILD_WORKSPACE_DIRECTORY") ||
					    (ws && (index(L[j], "$WS") || index(L[j], "${WS")))) { ok = 1; break }
				}
				if (!ok) printf "%s%s:%d: %s, beside $0 and nowhere else\n", (shown++ ? "        " : ""), f, RL[r], RP[r]
			}
		}' "$_sp")
	[ -z "$_beside" ] || report "a script bazel run starts looks for a file beside \$0 only" \
		"$_beside" \
		"Under \`bazel run\`, \$0 is bazel-bin's link to the script and nothing is" \
		"beside it -- not even a data dependency, which lands in the runfiles tree." \
		"Look in the workspace too: \"\$WS/tools/<file>\", with WS set from" \
		"BUILD_WORKSPACE_DIRECTORY, as init.sh and env_drift.sh read drives.sh."
done

# ---------------------------------------------------------------------------
# N. CHANGELOG.md has one dated line per publish, newest first.
#
# The template is published as a chain a colleague pulls (docs/publishing.md),
# and this file is how they learn what a pull cannot do for them. The template
# build's --chain refuses a publish without exactly one new dated line; this
# keeps the file in the shape that check reads between publishes: every entry
# "- YYYY-MM-DD: ..." except at most one "- next publish: ...", first.
if [ -f CHANGELOG.md ]; then
	_cl=$(awk '
		/^- / {
			n++
			if ($0 ~ /^- next publish: [^ ]/) { if (n != 1) print "line " NR ": the next-publish line is not the first entry"; next }
			if ($0 !~ /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]: [^ ]/) print "line " NR ": not \"- YYYY-MM-DD: what to do\""
		}' CHANGELOG.md)
	[ -z "$_cl" ] || report "CHANGELOG.md has entries the publish check cannot read" "$_cl"
fi

# ---------------------------------------------------------------------------
# DO THE PIN SITES AGREE WITH pins.tsv?
#
# pins.tsv calls itself "the single statement of which tool versions this repo
# expects" and its `pinned-in` column names, for each row, the file that
# actually installs that version. Nothing checked that the two agree, and for
# five tools -- shellcheck, zig, buildifier, Bazel and bazelisk -- nothing
# could, because they had no row at all.
#
# Two of the five decide verdicts: the shell layer runs the pinned shellcheck
# and the ilp32 layer runs the pinned zig. A pin recorded in one place and moved
# in the other is the failure this file exists to catch, and env_drift cannot:
# it compares the pin against the MACHINE, so a pin that no longer matches
# MODULE.bazel is invisible to it as long as the fetch still succeeds.
#
# bazel and bazelisk are the reason this check has to exist rather than being
# folded into env_drift. Their pins.tsv rows carry `-` as the version command
# -- asking either one its version from inside a `bazel run` re-enters Bazel and
# contends for the lock that run holds -- so this IS their check.
pin_want() { awk -F'\t' -v t="$1" '$1 == t { print $3; exit }' tools/pins.tsv; }

pins_agree() {  # pins_agree TOOL EXPECTED-STRING FILE DESCRIPTION
	[ "$2" = "$(pin_want "$1")" ] && return 0
	report \
		"tools/pins.tsv pins $1 at '$(pin_want "$1")', but $3 says '$2'" \
		"$4" \
		"pins.tsv is what env_drift, the campus audit and docs/environment.md" \
		"all read, so the version people SEE pinned is not the one installed."
}

if [ -f tools/pins.tsv ]; then
	pins_agree bazel "$(cat .bazelversion 2>/dev/null)" ".bazelversion" \
		"That file is what bazelisk reads, so it decides the Bazel every build runs."
	pins_agree bazelisk \
		"$(sed -n 's/^BAZELISK_VERSION=//p' tools/setup.sh | head -n 1)" \
		"tools/setup.sh" \
		"setup.sh is how a student off campus installs the launcher."

	# The Dockerfile installs the same two, and the checksums are the point:
	# setup.sh's own comment calls a checksum "the only thing standing between
	# 'we downloaded a launcher' and 'we downloaded and executed whatever that
	# URL served today'", so the two must not be pinning different bytes.
	_dv=$(sed -n 's/^ARG BAZELISK_VERSION=//p' .devcontainer/Dockerfile | head -n 1)
	_sv=$(sed -n 's/^BAZELISK_VERSION=//p' tools/setup.sh | head -n 1)
	if [ "$_dv" != "$_sv" ]; then
		report \
			".devcontainer/Dockerfile installs bazelisk $_dv, tools/setup.sh installs $_sv" \
			"The same repo would then ship two different launchers depending on" \
			"whether you used the container or ran setup.sh by hand."
	fi
	_ds=$(sed -n 's/^ARG BAZELISK_SHA256_AMD64=//p' .devcontainer/Dockerfile | head -n 1)
	_ss=$(sed -n 's/^BAZELISK_SHA256=//p' tools/setup.sh | head -n 1)
	if [ "$_ds" != "$_ss" ]; then
		report \
			"the bazelisk sha256 in .devcontainer/Dockerfile and tools/setup.sh differ" \
			"Dockerfile: $_ds" \
			"setup.sh:   $_ss" \
			"Two digests for one pinned version means at least one is wrong, and" \
			"a checksum nobody cross-checks is a checksum of the wrong file."
	fi

	# The three Bazel-fetched ones, against MODULE.bazel. Matched on the version
	# NUMBER inside each row rather than the whole line, because these rows
	# record what the tool PRINTS ("version: 0.10.0"), which is not the string
	# MODULE.bazel spells.
	_zw=$(pin_want zig)
	if ! grep -q "zig-linux-x86_64-$_zw" MODULE.bazel; then
		report \
			"tools/pins.tsv pins zig $_zw, which MODULE.bazel does not fetch" \
			"The ilp32 layer runs the fetched zig, so this is the version that" \
			"decides whether an exercise passes at -m32."
	fi
	_sw=$(pin_want shellcheck | tr -dc '0-9.')
	if ! grep -q "shellcheck-v$_sw" MODULE.bazel; then
		report \
			"tools/pins.tsv pins shellcheck $_sw, which MODULE.bazel does not fetch" \
			"The shell layer runs the fetched shellcheck, so this version decides" \
			"which warnings exist and therefore which submissions are red."
	fi
	# buildifier is pinned in two places for two audiences: MODULE.bazel for
	# `bazel run //:buildifier`, the Dockerfile for the editor extension's copy
	# on PATH. A student formatting in the editor and the repo checking in CI
	# must be running the same formatter.
	_bw=$(pin_want buildifier | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
	_bd=$(sed -n 's/^ARG BUILDIFIER_VERSION=v//p' .devcontainer/Dockerfile | head -n 1)
	if [ "$_bw" != "$_bd" ]; then
		report \
			"tools/pins.tsv pins buildifier $_bw, .devcontainer/Dockerfile installs $_bd" \
			"The editor extension uses the container's copy and the repo uses" \
			"MODULE.bazel's, so two versions means two different formatters."
	fi
	if ! grep -q "buildifier_prebuilt\", version = \"$_bw" MODULE.bazel; then
		report \
			"tools/pins.tsv pins buildifier $_bw, which MODULE.bazel does not name" \
			"buildifier_prebuilt's version begins with the buildifier version it" \
			"carries; if it no longer does, one of the two moved alone."
	fi

	# strlcpy(3bsd) and strlcat(3bsd), C 02 ex10's and C 03 ex05's manual
	# page: glibc 2.35 has neither function, so on Ubuntu 22.04 the page ships
	# only in libbsd-dev, and `man strlcpy` in the image said "No manual entry"
	# (finding 054). The image takes the two pages out of a .deb at
	# LIBBSD_DEV_VERSION, checked against LIBBSD_DEV_SHA256, and pins.tsv's
	# row states that version. And the package itself never goes in: its
	# <bsd/string.h> and -lbsd would let code build in the image that does not
	# build on a campus box without them.
	if [ -f .devcontainer/Dockerfile ]; then
		pins_agree libbsd-dev \
			"$(sed -n 's/^ARG LIBBSD_DEV_VERSION=//p' .devcontainer/Dockerfile | head -n 1)" \
			".devcontainer/Dockerfile (ARG LIBBSD_DEV_VERSION)" \
			"The image takes strlcpy's and strlcat's manual pages from that .deb."
		if grep -q '^ARG LIBBSD_DEV_VERSION=' .devcontainer/Dockerfile &&
			! grep -qE '^ARG LIBBSD_DEV_SHA256=[0-9a-f]{64}$' .devcontainer/Dockerfile; then
			report \
				".devcontainer/Dockerfile fetches libbsd-dev with no sha256 to check it against" \
				"ARG LIBBSD_DEV_SHA256 is the digest the archive's Packages index gives for" \
				"libbsd-dev_<LIBBSD_DEV_VERSION>_amd64.deb; without it the image unpacks" \
				"whatever the mirror served that day."
		fi
		# Any install of one, in any layout: a package alone on its line of
		# a long apt list, or beside others on one line (`apt-get install -y
		# sudo libbsd-dev`, as the RUN creating the user lays it out), or a downloaded
		# .deb handed to dpkg -i. An instruction is its lines up to one that
		# does not end in a backslash, less its comment lines, which Docker
		# drops; its commands are split at && || ; and |, and a command that
		# installs is reported for every word naming a libbsd package. The
		# pages' own RUN downloads the .deb and unpacks it with dpkg-deb,
		# which installs nothing.
		_lb=$(awk '
			/^[[:blank:]]*#/ { next }
			{ if (ins == "") at = NR; ins = ins " " $0 }
			/\\[[:blank:]]*$/ { next }
			{
				n = split(ins, cmd, /&&|[;|]/)
				for (i = 1; i <= n; i++) {
					if (cmd[i] !~ /(^|[[:blank:]])apt(-get)?[[:blank:]](.*[[:blank:]])?install([[:blank:]]|$)/ &&
						cmd[i] !~ /(^|[[:blank:]])dpkg[[:blank:]]+(-i|--install)([[:blank:]]|$)/) continue
					w = split(cmd[i], word, /[[:blank:]]+/)
					for (j = 1; j <= w; j++)
						if (word[j] ~ /^([^[:blank:]]*\/)?libbsd[a-z0-9.+_-]*(=[^[:blank:]]*)?$/)
							printf "%d: %s\n", at, word[j]
				}
				ins = ""
			}' .devcontainer/Dockerfile)
		[ -z "$_lb" ] || report \
			".devcontainer/Dockerfile installs a libbsd package" \
			"$_lb" \
			"Only strlcpy's and strlcat's manual pages belong in the image; the" \
			"package would add <bsd/string.h> and a libbsd to link, so code would" \
			"build there that does not build on a campus box without them."
	fi
fi

# ---------------------------------------------------------------------------
# N. A tool the image installs only for a student's own hands is in
# docs/environment.md's list of what the docs ask you to run by hand.
#
# docs/environment.md listed what the HARNESS borrows from the box, and
# nothing else, so a student off the dev container had no line telling them to
# install gdb, lldb-12, valgrind or gcc-10, which the study guide drills, nor
# strlcpy's manual page, which C 02 sends them to (findings 054, 198). A row of
# tools/pins.tsv whose only pin site is .devcontainer/Dockerfile is exactly
# such a tool: no layer runs it, and only the image installs it. So is a
# Python package the Dockerfile pip-installs at NAME==VERSION (norminette,
# pypdf): the harness's own Python is tools/requirements.txt, which Bazel
# fetches, so what the image adds is for the terminal. Each one is named, as
# `tool`, in that list, and where the list gives a NAME==VERSION to install it
# is the image's version.
if [ -f tools/pins.tsv ]; then
	_hand=$(awk -F'\t' '/^#/ { next }
		NF >= 5 && $5 ~ /^\.devcontainer\/Dockerfile( |$)/ && $5 !~ /\+/ { print $1 }' tools/pins.tsv)
	# The pip installs, an instruction at a time as the libbsd rule above
	# reads them: NAME==VERSION, one per line.
	_pip=""
	[ ! -f .devcontainer/Dockerfile ] || _pip=$(awk '
		/^[[:blank:]]*#/ { next }
		{ ins = ins " " $0 }
		/\\[[:blank:]]*$/ { next }
		{
			n = split(ins, cmd, /&&|[;|]/)
			for (i = 1; i <= n; i++) {
				if (cmd[i] !~ /(^|[[:blank:]])pip3?[[:blank:]](.*[[:blank:]])?install([[:blank:]]|$)/) continue
				w = split(cmd[i], word, /[[:blank:]]+/)
				for (j = 1; j <= w; j++)
					if (word[j] ~ /^[A-Za-z0-9][A-Za-z0-9._-]*==[^[:blank:]]+$/) print word[j]
			}
			ins = ""
		}' .devcontainer/Dockerfile)
	[ -z "$_pip" ] || _hand=$(printf '%s\n%s\n' "$_hand" "$(printf '%s\n' "$_pip" | sed 's/==.*//')" | sed '/^$/d')
	if [ -n "$_hand" ]; then
		# The section runs to the next heading; a '#' line inside a code
		# fence is a shell comment, not one.
		_hl=$(awk '/^```/ { f = !f } !f && /^#+ / { on = ($0 ~ /^#+ What the docs ask you to run by hand/); next } on' \
			docs/environment.md 2> /dev/null)
		if [ -z "$_hl" ]; then
			report "docs/environment.md has no section \"What the docs ask you to run by hand\"" \
				"The image installs these for a student's own hands alone: $(printf '%s' "$_hand" | tr '\n' ' ')" \
				"No layer runs them; the image installs them for a student's own use, so" \
				"a student without the image needs that section to know they exist."
		else
			_hm=$(printf '%s\n' "$_hand" | while IFS= read -r _t; do
				printf '%s\n' "$_hl" | grep -qF -- "\`$_t\`" || printf '    %s\n' "$_t"
			done)
			[ -z "$_hm" ] || report \
				"docs/environment.md's list of what you run by hand does not name every tool only the image installs" \
				"$_hm" \
				"Each is a tools/pins.tsv row whose only pin site is .devcontainer/Dockerfile," \
				"or a Python package the Dockerfile pip-installs: no layer runs it, so the" \
				"list is the one place a student without the image learns to install it." \
				"Name it there as \`tool\`."
			_hv=$(printf '%s\n' "$_pip" | while IFS= read -r _p; do
				[ -n "$_p" ] || continue
				printf '%s\n' "$_hl" | grep -oE -- "${_p%%==*}==[^[:blank:]\`,)]+" | sort -u |
					while IFS= read -r _g; do
						[ "$_g" = "$_p" ] || printf '    %s, where the image installs %s\n' "$_g" "$_p"
					done
			done)
			[ -z "$_hv" ] || report \
				"docs/environment.md's list of what you run by hand gives another version than the image" \
				"$_hv" \
				"A student installing it by hand gets the version the list names; the" \
				"dev container's is .devcontainer/Dockerfile's pip install, so the two" \
				"say the same."
		fi
	fi
fi

# ---------------------------------------------------------------------------
# N. A function whose manual page only libbsd-dev ships: the image carries the
# page, and a printed clue that sends a student to it says where it is.
#
# glibc 2.35 has none of LIBBSD_PAGES, so on Ubuntu 22.04 each one's page is
# libbsd-dev's, in section 3bsd, and the image extracts each such page by name
# from the pinned .deb (.devcontainer/Dockerfile), installing nothing else of
# the package (finding 054). C 02 ex10 and C 03 ex05 reproduce strlcpy and
# strlcat; libft's ft_strnstr is the next one, and its page, strnstr.3bsd, is
# in the same .deb. So a BUILD.bazel that turns in ft_<name>.c for one of them
# has the image extract usr/share/man/man3/<name>.3bsd.gz. And a printed line
# of a clue file (in a .tsv, not a '#' one: rl_clues never prints those) that
# sends a student to `man <name>` names section 3bsd, where the page is, and
# man.openbsd.org, which has it where no package installed it: a campus box,
# or a Linux without libbsd-dev, answers `man strlcpy` with "No manual entry"
# (review of WP-85). A name joins LIBBSD_PAGES when a subject reproduces a
# function glibc 2.35 lacks.
LIBBSD_PAGES="strlcpy strlcat strnstr"
if [ -f .devcontainer/Dockerfile ]; then
	_lp=$(for _n in $LIBBSD_PAGES; do
		_b=$(text_files -name BUILD.bazel -exec grep -lE "^[^#]*\"ft_$_n\\.c\"" {} + | sed 's|^\./||' | sort | head -n 1)
		[ -n "$_b" ] || continue
		grep -qF "./usr/share/man/man3/$_n.3bsd.gz" .devcontainer/Dockerfile ||
			printf '    %s turns in ft_%s.c, and the image has no %s.3bsd\n' "$_b" "$_n" "$_n"
	done)
	[ -z "$_lp" ] || report \
		".devcontainer/Dockerfile does not carry the manual page of a function a subject reproduces" \
		"$_lp" \
		"That page ships only in libbsd-dev, which the image never installs: add" \
		"./usr/share/man/man3/<name>.3bsd.gz to the members the libbsd-dev RUN" \
		"extracts (a page that is a link, as strlcat's is, needs its target too)."
fi
_lc=$(text_files \( -name '*clues*.tsv' -o -name '*clues*.txt' \) -exec awk -v names="$LIBBSD_PAGES" '
	FNR == 1 { f = FILENAME; sub(/^\.\//, "", f) }
	f ~ /\.tsv$/ && /^#/ { next }
	{
		n = split(names, nm, " ")
		for (i = 1; i <= n; i++)
			if ($0 ~ ("man[[:blank:]]+([0-9][0-9a-z]*[[:blank:]]+)?" nm[i] "([^a-z0-9_]|$)") &&
				($0 !~ ("man[[:blank:]]+3bsd[[:blank:]]+" nm[i]) || $0 !~ /man\.openbsd\.org/)) {
				printf "    %s:%d: man %s\n", f, FNR, nm[i]
				break
			}
	}' {} + | sort)
[ -z "$_lc" ] || report \
	"a printed clue sends a student to a libbsd-only manual page without saying where it is" \
	"$_lc" \
	"Write \`man 3bsd <name>\`, the section the page is in, and man.openbsd.org's" \
	"page beside it: without libbsd-dev, as on a campus box that lacks it, \`man" \
	"<name>\` answers \"No manual entry\". Keep the line a question."

# THE RUST TOOLCHAIN AND THE i686 CORE THE GRADER'S FUNCTIONS ARE BUILT ON.
# tools/grader_lib.bzl compiles C 12's and C 13's own constructors for i686
# with the toolchain's rustc against a rust-std fetched on its own, and rustc
# loads a `core` only from its own version ("found crate `core` compiled by an
# incompatible version of rustc"). rules_rust's default version moves with
# rules_rust, so MODULE.bazel writes the version out, and both downloads must
# name that one version: the toolchain's `versions`, and the rust-std URL and
# strip_prefix. A bump of one alone is a build error at best -- this names it.
#
# pins.tsv states both versions too (its rustc and rust-std-i686 rows), as it
# states every tool's, so each is held to MODULE.bazel as zig's row is: a pin
# nobody compares with the fetch pins nothing.
if [ -f MODULE.bazel ]; then
	_rv=$(sed -n 's/^    versions = \["\([0-9][0-9.]*\)"\],$/\1/p' MODULE.bazel | head -n 1)
	if [ -f tools/pins.tsv ]; then
		_rpw=$(pin_want rustc | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
		_spw=$(pin_want rust-std-i686)
		[ -n "$_rpw" ] && [ "$_rpw" = "$_rv" ] || report \
			"tools/pins.tsv pins rustc ${_rpw:-(no row)}, and MODULE.bazel's toolchain is ${_rv:-?}" \
			"rules_rust fetches the version MODULE.bazel's rust.toolchain names, and" \
			"the grader's own functions are compiled with it: move both together."
		[ -n "$_spw" ] && grep -q "rust-std-$_spw-i686-unknown-linux-musl" MODULE.bazel || report \
			"tools/pins.tsv pins rust-std-i686 ${_spw:-(no row)}, which MODULE.bazel does not fetch" \
			"The grader's own functions are compiled for i686 against that rust-std's" \
			"core; the version in its url and strip_prefix is the one that decides."
	fi
	_sn=$(grep -c "rust-std-$_rv-i686-unknown-linux-musl" MODULE.bazel)
	_sa=$(grep -c 'rust-std-[0-9][0-9.]*-i686-unknown-linux-musl' MODULE.bazel)
	if [ -z "$_rv" ] || [ "$_sn" -lt 2 ] || [ "$_sn" != "$_sa" ]; then
		report \
			"MODULE.bazel's Rust toolchain (versions = [\"${_rv:-?}\"]) and its i686 rust-std disagree" \
			"The grader's own functions (tools/grader_lib.bzl) are compiled for i686" \
			"by the toolchain's rustc against that rust-std's core, which loads only" \
			"in the rustc of its own version. Move both to one version: the" \
			"toolchain's versions, and the rust-std's url and strip_prefix (the sha256" \
			"is in rules_rust's known_shas.bzl, as rust-std-<version>-i686-unknown-linux-musl.tar.xz)."
	fi
fi

# THE WAITING BLOCK README.md SHOWS IS THE ONE A RED LOG PRINTS. README's
# step 3 shows a beginner's first red output log, and rl_waiting
# (tools/runner_lib.sh) prints its last lines. A sample that drifts from the
# runner teaches a log nobody sees: the block was added to every red log
# while README's sample had none of it, and its first wording said "shows
# PASSED" of tests the `:basic` run README has them make never starts. Each
# line rl_waiting echoes is a line of README.md.
if [ -f README.md ] && [ -f tools/runner_lib.sh ]; then
	_wl=$(sed -n '/^rl_waiting() {/,/^}/p' tools/runner_lib.sh |
		sed -n 's/^[[:blank:]]*echo "\(.*\)"$/\1/p')
	if [ -z "$_wl" ]; then
		report "tools/runner_lib.sh's rl_waiting echoes no line this can read" \
			"README.md's step 3 shows the block it prints; keep it one echo \"...\" a line."
	else
		_wm=$(printf '%s\n' "$_wl" | while IFS= read -r _l; do
			grep -qxF -- "$_l" README.md || printf '    %s\n' "$_l"
		done)
		[ -z "$_wm" ] || report \
			"README.md's sample red log does not show rl_waiting's block as it prints it" \
			"$_wm" \
			"Step 3 shows a beginner the log their first red prints; put the block" \
			"there as tools/runner_lib.sh's rl_waiting writes it."
	fi
fi

# ---------------------------------------------------------------------------
# N. A doc's whole-repo test command says it needs memory to spare, and the
# editor's default test task runs one module.
#
# A campus box has about 2.5 GB free at idle and a whole-repo run needs more
# (docs/environment.md, "Memory: the habits matter more than the flags"), yet
# the first commands a newcomer met ran it: init's closing line, README's flow
# line and triage example, testing.md's triage, and the editor's default test
# task (finding 006). Each names one module's suite now. A `bazel test //...`
# a doc still shows in a code block says, on its own line, that it needs
# memory to spare -- the reader copying it is the one who needs to know.
# TODO.md and HISTORY.md are records, not instructions. In .vscode/tasks.json
# the default test task never runs //..., and a task that does says so in its
# label, which is all a menu shows.
_wr=$(text_files -name '*.md' ! -path ./TODO.md ! -path ./HISTORY.md \
	-exec awk '
		FNR == 1 { f = FILENAME; sub(/^\.\//, "", f); fe = 0 }
		/^[[:blank:]]*```/ { fe = !fe; next }
		fe && /bazel test([[:blank:]]+-[^[:blank:]]+)*[[:blank:]]+\/\/\.\.\.([[:blank:]]|$)/ && !/memory/ {
			printf "    %s:%d: %s\n", f, FNR, $0
		}' {} + | sort -t: -k1,1 -k2,2n)
[ -z "$_wr" ] || report \
	"a doc shows a whole-repo test run without saying it needs memory to spare" \
	"$_wr" \
	"On a campus box (about 2.5 GB free) bazel test //... is more than the" \
	"machine has; one module's suite (bazel test //<course>/<project>:basic) is" \
	"what to show. Where the whole repo is the point, say on that line, in a" \
	"comment, that it needs memory to spare."
# And what a runner prints. A SKIP paragraph is the first command many a
# newcomer copies, and five of them printed `bazel test //...
# --test_env=NO_SKIP=1` (review of WP-83). An echo or printf of tools/*.sh
# that shows a whole-repo test is reported as a doc's is, unless its line
# says it needs memory; tools/runner_lib.sh's rl_noskip_cmd names the test
# itself.
_wp=$(for _f in tools/*.sh; do
	[ -f "$_f" ] || continue
	awk -v f="$_f" '
		/^[[:blank:]]*#/ { next }
		/(^|[[:blank:];&|(])(echo|printf)[[:blank:]]/ &&
			/bazel test([[:blank:]]+-[^[:blank:]]+)*[[:blank:]]+\/\/\.\.\.([^A-Za-z0-9_\/:.-]|$)/ && !/memory/ {
			printf "    %s:%d: %s\n", f, FNR, $0
		}' "$_f"
done)
[ -z "$_wp" ] || report \
	"a runner prints a whole-repo test without saying it needs memory to spare" \
	"$_wp" \
	"Name the test instead: \$(rl_noskip_cmd) prints \`bazel test <this target>" \
	"--test_env=NO_SKIP=1\`, which runs the one test the reader is looking at."
if [ -f .vscode/tasks.json ]; then
	# One task is one object of the "tasks" list, a "{" and a "}" alone on
	# their lines, as the file is laid out; a task's inner objects ("group",
	# "presentation") sit on one line each. What a task runs is every line of
	# it but its comments and its label: the default task keeps its command
	# in a multi-line "args" array, and a rule that read only the lines
	# naming "command" or "args" never saw it (review of WP-83).
	_wt=$(awk '
		/^[[:blank:]]*\{[[:blank:]]*$/ { depth++; if (depth == 2) { lab = ""; cmd = ""; def = 0 } }
		/"label"[[:blank:]]*:/ { lab = $0; sub(/.*"label"[[:blank:]]*:[[:blank:]]*"/, "", lab); sub(/".*/, "", lab); next }
		depth == 2 && !/^[[:blank:]]*\/\// { cmd = cmd $0 }
		/"isDefault"[[:blank:]]*:[[:blank:]]*true/ { def = 1 }
		/^[[:blank:]]*\}[[:blank:]]*,?[[:blank:]]*$/ {
			if (depth == 2 && cmd ~ /\/\/\.\.\./) {
				if (def) printf "    the default test task runs the whole repo: \"%s\"\n", lab
				else if (lab !~ /memory/) printf "    a task runs the whole repo and its label does not say so: \"%s\"\n", lab
			}
			depth--
		}' .vscode/tasks.json)
	[ -z "$_wt" ] || report \
		".vscode/tasks.json sends a newcomer to the whole repo" \
		"$_wt" \
		"Run Test Task runs the default one, and the editor's menu shows only a" \
		"label: the default runs one module's :basic suite, and a whole-repo task" \
		"says in its label that it needs memory to spare."
	# A doc names a task by its label, which is all the menu shows, and the
	# label it names is one the file has: docs/testing.md went on sending
	# readers to `Bazel: test all` after that label had changed and the
	# default had become one module (review of WP-83), and the rule above
	# reads only the file. So a backticked span of a shipped doc that begins
	# the way a label does, up to its first ": " ("Bazel: "), is a label.
	_labels=$(sed -n 's/^[[:blank:]]*"label"[[:blank:]]*:[[:blank:]]*"\(.*\)",\{0,1\}[[:blank:]]*$/\1/p' \
		.vscode/tasks.json | tr '\n' '\t')
	_wl=""
	[ -z "$_labels" ] || _wl=$(text_files -name '*.md' ! -path ./TODO.md ! -path ./HISTORY.md \
		-exec awk -v labels="$_labels" '
			BEGIN {
				n = split(labels, lab, "\t")
				for (i = 1; i <= n; i++) {
					if (lab[i] == "") continue
					known[lab[i]] = 1
					k = index(lab[i], ": ")
					if (k > 0) pre[substr(lab[i], 1, k + 1)] = 1
				}
			}
			FNR == 1 { f = FILENAME; sub(/^\.\//, "", f) }
			{
				line = $0
				while (match(line, /`[^`]+`/)) {
					span = substr(line, RSTART + 1, RLENGTH - 2)
					line = substr(line, RSTART + RLENGTH)
					for (p in pre)
						if (index(span, p) == 1 && !(span in known)) {
							printf "    %s:%d: `%s`\n", f, FNR, span
							break
						}
				}
			}' {} + | sort -t: -k1,1 -k2,2n)
	[ -z "$_wl" ] || report \
		"a doc names an editor task that .vscode/tasks.json does not have" \
		"$_wl" \
		"The editor's Run Task menu shows labels, so a doc that names one sends" \
		"its reader looking for it there. The labels it has:" \
		"$(printf '%s' "$_labels" | tr '\t' '\n' | sed '/^$/d; s/^/    /')"
fi

# EVERY RUST COMPILE DENIES WARNINGS. A warning rustc prints is not a red
# build, so it lands -- a needless `mut` in oracle/src/c08.rs printed "1
# warning emitted" in the middle of every cold build -- and the first person
# to read it is a student on their first run, in output that is not theirs.
# With -Dwarnings it is a red build on the author's machine instead, and the
# toolchain is pinned (the rule above), so the set of warnings cannot move
# under anyone else.
#
# EACH COMPILE, NOT EACH FILE. Every rules_rust target (a rust_*( call, from
# it to the parenthesis that closes it) names the flag, or a list of this
# file's that holds it; and so does every function that runs the
# toolchain's rustc itself (tools/grader_lib.bzl). Checked per file at
# first, a second target in oracle/BUILD.bazel -- a rust_test, say -- passed
# on the flag the first one names. Not rules_rust's extra_rustc_flags for
# the whole build: those reach every crate, a fetched one's included.
rust_warnings() {  # rust_warnings FILE -- "    FILE:LINE (what)" per compile that does not deny warnings
	awk -v f="$1" '
		function code(l) { sub(/^[[:space:]]*#.*/, "", l); return l }
		FNR == NR {
			l = code($0)
			if (l ~ /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*\[/) {
				lname = l; sub(/[[:space:]]*=.*/, "", lname); inl = 1
			}
			if (inl && index(l, "\"-Dwarnings\"")) flagged[lname] = 1
			if (inl && (l ~ /^\]/ || (l ~ /^[A-Za-z_]/ && l ~ /\][[:space:]]*$/))) inl = 0
			next
		}
		function names_flag(l,   n) {
			if (index(l, "\"-Dwarnings\"")) return 1
			for (n in flagged) if (l ~ ("(^|[^A-Za-z0-9_])" n "([^A-Za-z0-9_]|$)")) return 1
			return 0
		}
		{ l = code($0) }
		!inb && l ~ /^[[:space:]]*(native\.)?rust_[a-z_]+\(/ { inb = 1; depth = 0; start = FNR; has = 0 }
		inb {
			if (names_flag(l)) has = 1
			t = l; o = gsub(/\(/, "", t); t = l; c = gsub(/\)/, "", t); depth += o - c
			if (depth <= 0) { if (!has) printf "    %s:%d (a rules_rust target)\n", f, start; inb = 0 }
		}
		/^def / { if (indef && runs && !dhas) printf "    %s:%d (a function that runs rustc)\n", f, dstart; indef = 1; dstart = FNR; runs = 0; dhas = 0 }
		/^[^[:space:]#]/ && !/^def / { if (indef && runs && !dhas) printf "    %s:%d (a function that runs rustc)\n", f, dstart; indef = 0 }
		indef {
			if (l ~ /executable = [A-Za-z_.]*rustc,/) runs = 1
			if (names_flag(l)) dhas = 1
		}
		END { if (indef && runs && !dhas) printf "    %s:%d (a function that runs rustc)\n", f, dstart }
	' "$1" "$1"
}
_rw=$(text_files \( -name BUILD.bazel -o -name '*.bzl' \) -exec grep -lE \
	'^[[:space:]]*(native\.)?rust_[a-z_]+\(|executable = [A-Za-z_.]*rustc,' {} + | sort |
	while IFS= read -r _f; do
		rust_warnings "$_f" | sed "s#^    \./#    #"
	done)
[ -z "$_rw" ] || report \
	"a Rust compile that does not deny warnings" \
	"$_rw" \
	"rustc's warnings then reach a student's first run as noise in a build" \
	"that is not theirs. Add \"-Dwarnings\" to its rustc flags (rustc_flags," \
	"or the flag list the action passes), and fix what it then refuses."

# ---------------------------------------------------------------------------
# N. A function the GRADER brings is never written in C outside the zone.
#
# C 12 and C 13 say the grader links its own ft_create_elem / btree_create_node
# from exercise 01 on, and the harness does the same with a copy compiled from
# Rust (tools/grader_lib.bzl): every grader_library() crate exports the
# grader's functions with #[no_mangle]. A copy in C -- under tests/, in a
# fixture, in a tool -- is the answer to the exercise that writes it, outside
# the zone (AGENTS.md section 0). tools/answer_scan.sh would not see a fresh
# one: it compares with the zone's own answer four lines at a time, and a
# constructor's body is shorter than that. So each name such a crate exports
# is refused as a DEFINITION in any .c or .h outside deliverable/ and
# generators/; a declaration, which a test needs in order to call it, is not
# one. The crates are found from the grader_library() calls themselves, so the
# next grader's function is covered the day its crate is.
#
# Each call's `exports` is the list the subject contract checks a `linked`
# function against while it is analysed (tools/subject.bzl's linked_problem():
# analysis cannot read a crate), so it is held here to the crate's own
# #[no_mangle] functions, all of them and no other. A name listed there and
# not exported would pass the contract and fail to link in every program of
# the exercise, a red that reads as the student's.
#
# gl_calls prints one line per call: "<BUILD dir>|<src>|<export> <export>...".
# A call ends at a ")" at the start of a line, as buildifier writes one; its
# `exports` may be on one line or one name per line.
gl_calls() {
	find . -path './bazel-*' -prune -o -path ./.git -prune -o \
		-name BUILD.bazel -print 2> /dev/null | sort | while IFS= read -r _b; do
		awk -v d="${_b%/BUILD.bazel}" '
			function flush() {
				if (g) print d "|" src "|" ex
				g = 0; lst = 0; src = ""; ex = ""
			}
			function names(t,   v) {
				while (match(t, /"[^"]+"/)) {
					v = substr(t, RSTART + 1, RLENGTH - 2)
					ex = ex (ex == "" ? "" : " ") v
					t = substr(t, RSTART + RLENGTH)
				}
			}
			/^[ \t]*grader_library\(/ { flush(); g = 1; next }
			!g { next }
			/^\)/ { flush(); next }
			lst { names($0); if ($0 ~ /\]/) lst = 0; next }
			match($0, /^[ \t]*src[ \t]*=[ \t]*"[^"]+"/) {
				v = substr($0, RSTART, RLENGTH)
				sub(/^[ \t]*src[ \t]*=[ \t]*"/, "", v)
				sub(/"$/, "", v)
				src = v
			}
			/^[ \t]*exports[ \t]*=/ {
				t = $0
				sub(/^[^=]*=/, "", t)
				names(t)
				if (t !~ /\]/) lst = 1
			}
			END { flush() }' "$_b"
	done
}
# gl_exported CRATE: the functions it exports with #[no_mangle] extern "C",
# one per line.
gl_exported() {
	awk '
		/^[ \t]*#\[no_mangle\]/ { mark = 1; next }
		mark && match($0, /extern "C" fn [A-Za-z_][A-Za-z0-9_]*/) {
			v = substr($0, RSTART, RLENGTH)
			sub(/.* fn /, "", v)
			print v
		}
		!/^[ \t]*(#|\/\/)/ { mark = 0 }' "$1"
}
_gl_list=$(gl_calls)
_gl_crates=$(printf '%s\n' "$_gl_list" | while IFS='|' read -r _d _s _e; do
	[ -n "$_s" ] && echo "$_d/$_s"
done)
_gl_names=$(for _c in $_gl_crates; do
	[ -f "$_c" ] || continue
	gl_exported "$_c"
done | sort -u)
_gl_bad=$(printf '%s\n' "$_gl_list" | while IFS='|' read -r _d _s _e; do
	[ -n "$_d" ] || continue
	_c="$_d/$_s"
	[ -f "$_c" ] || continue
	_have=$(gl_exported "$_c" | sort -u | tr '\n' ' ')
	_want=$(printf '%s\n' $_e | sort -u | tr '\n' ' ')
	[ "$_have" = "$_want" ] || {
		_have=${_have% }
		printf '    %s/BUILD.bazel: the call over %s lists exports = [%s], and the crate exports %s\n' \
			"${_d#./}" "$_s" "${_want% }" "${_have:-nothing}"
	}
done)
[ -z "$_gl_bad" ] || report \
	"a grader_library()'s exports and its crate's #[no_mangle] functions differ" \
	"$_gl_bad" \
	"The subject contract checks every function an exercise's \`linked\` takes" \
	"from a library against that library's \`exports\` (tools/subject.bzl," \
	"linked_problem()), which cannot read the crate. List exactly the crate's" \
	"#[no_mangle] extern \"C\" functions there."
if [ -n "$_gl_names" ]; then
	_gl_hits=$(find . -path './bazel-*' -prune -o -path ./.git -prune -o \
		-path '*/deliverable/*' -prune -o -path '*/generators/*' -prune -o \
		\( -name '*.c' -o -name '*.h' \) -print 2> /dev/null | sort |
		while IFS= read -r _f; do
			awk -v names="$_gl_names" '
				BEGIN {
					n = split(names, a, /[ \t\n]+/)
					for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1
				}
				# The rest of a signature that began on an earlier line: a
				# brace before any semicolon is a body.
				pend != "" {
					b = index($0, "{"); c = index($0, ";")
					if (b && (!c || b < c)) {
						printf "    %s:%d: defines %s\n", FILENAME, start, pend
						pend = ""
					} else if (c)
						pend = ""
					next
				}
				/^[A-Za-z_]/ {
					for (fn in want) {
						if (!match($0, "(^|[^A-Za-z0-9_])" fn "[ \t]*[(]"))
							continue
						rest = substr($0, RSTART)
						b = index(rest, "{"); c = index(rest, ";")
						if (b && (!c || b < c))
							printf "    %s:%d: defines %s\n", FILENAME, FNR, fn
						else if (!c) {
							pend = fn
							start = FNR
						}
					}
				}' "$_f"
		done)
	[ -z "$_gl_hits" ] || report \
		"a function a grader_library() crate exports is defined in C outside the zone" \
		"$_gl_hits" \
		"The grader's own function is compiled from Rust (tools/grader_lib.bzl), and" \
		"written in C it is the answer to the exercise that writes it, outside the" \
		"zone (AGENTS.md section 0). Declare it and call it; the macros link the" \
		"grader's copy wherever an exercise's contract names it in \`linked\`."
fi

# ---------------------------------------------------------------------------
# N. A function a student turns in is never written outside the zone.
#
# The rule above covers a function only once an author has chosen `linked`
# for it: it refuses a C copy of the names a grader_library() crate exports.
# The next project's author can still reach the same answer by another door:
# write the grader's function as a `provided` C file under tests/ (the shape
# Reloaded's ft_putchar.c set), or keep "the grader's copy" of a constructor
# in a test main, a fixture or a tool. tools/answer_scan.sh cannot see a
# fresh one -- it compares with the zone's own answers, and on the template
# there are none -- and a function body is shorter than the four lines it
# compares at a time.
#
# So the names are taken from what is turned in: every function a subject()
# contract's `files` names a source for (X.c turns in X, by 42's one-function-
# per-file convention; main.c is a program, not a function) may be DEFINED
# outside deliverable/ and generators/ only as a stub -- in the body, the
# whitelist tools/stub_check.sh holds a turned-in stub to: (void) casts, a
# trivial return, nothing else. A placeholder that compiles (C 09 ex01's
# grader srcs/, Reloaded ex24's, C 08 ex00's test main) is one; anything that
# does the work is the answer of the exercise that turns it in. A declaration,
# which a test needs in order to call one, is not a definition. Names come from
# every contract in the repository, so one project's placeholder for another
# project's exercise is held to it too, and the next project's names are
# covered the day its contract is written.
#
# TURNIN_FN_ALLOW: the definitions that do the work on purpose, by path, each
# with its reason. Reloaded's tests/ft_putchar.c is the grader's ft_putchar,
# which every exercise that may call it links; it is written with stdio,
# which no Piscine exercise authorises, so that it is not C 00 ex00's answer
# (its header comment). Exempt while it stays that: a write() in it is
# reported like any other body. It is the one exception, not a pattern:
# AGENTS.md section 4 names it, a path here that AGENTS.md does not name is
# reported (the AGENTS.md rule, at the end), and a second one is the owner's
# to allow.
TURNIN_FN_ALLOW='c-piscine-reloaded/c-piscine-reloaded/tests/ft_putchar.c'

# turnin_fns prints one line per function a contract turns in:
# "<function> <BUILD dir> ex<NN>". A contract is the subject( call, which
# buildifier closes with a ")" at the start of a line; its exercises' `files`
# lists may be on one line or several.
turnin_fns() {
	find . -path './bazel-*' -prune -o -path ./.git -prune -o \
		-name BUILD.bazel -print 2> /dev/null | sort | while IFS= read -r _b; do
		_d=${_b%/BUILD.bazel}
		awk -v d="${_d#./}" '
			function take(t,   v) {
				while (match(t, /"[^"]+"/)) {
					v = substr(t, RSTART + 1, RLENGTH - 2)
					t = substr(t, RSTART + RLENGTH)
					sub(/.*\//, "", v)
					if (v !~ /^[A-Za-z_][A-Za-z0-9_]*\.c$/) continue
					sub(/\.c$/, "", v)
					if (v != "main") print v " " d " ex" ex
				}
			}
			/^subject\(/ { inb = 1; next }
			inb && /^\)/ { inb = 0; lst = 0; next }
			!inb { next }
			match($0, /"[0-9][0-9]"[ \t]*:/) { ex = substr($0, RSTART + 1, 2) }
			lst {
				if ((i = index($0, "]")) > 0) { take(substr($0, 1, i - 1)); lst = 0 }
				else take($0)
				next
			}
			match($0, /(^|[^A-Za-z_])files[ \t]*=[ \t]*\[/) {
				t = substr($0, RSTART + RLENGTH)
				if ((i = index(t, "]")) > 0) take(substr(t, 1, i - 1))
				else { take(t); lst = 1 }
			}' "$_b"
	done
}
_tf_list=$(turnin_fns | sort -u -k1,1)
if [ -n "$_tf_list" ]; then
	_tf_hits=$(find . -path './bazel-*' -prune -o -path ./.git -prune -o \
		-path '*/deliverable/*' -prune -o -path '*/generators/*' -prune -o \
		\( -name '*.c' -o -name '*.h' \) -print 2> /dev/null | sed 's#^\./##' | sort |
		while IFS= read -r _f; do
			_tf_allow=0
			case " $TURNIN_FN_ALLOW " in
				*" $_f "*) _tf_allow=1 ;;
			esac
			awk -v list="$_tf_list" -v allow="$_tf_allow" '
				BEGIN {
					n = split(list, a, "\n")
					for (i = 1; i <= n; i++) {
						split(a[i], w, " ")
						if (w[1] != "") whose[w[1]] = w[2] " " w[3]
					}
				}
				# One statement, or the text before a brace, of a body: what
				# a stub may hold, as tools/stub_check.sh judges a turned-in
				# .c -- nothing, a (void) cast, a trivial return. In an
				# allowed file, anything but a call of write().
				function judge(t) {
					gsub(/^[ \t]+|[ \t]+$/, "", t)
					if (allow) {
						if (t ~ /(^|[^A-Za-z0-9_])write[ \t]*[(]/) worked = 1
						return
					}
					if (t == "" || t == ";" || t ~ /^\(void\)[ \t]*[A-Za-z_][A-Za-z_0-9]*[ \t]*;$/ ||
					    t ~ /^return[ \t]*\([ \t]*(0|NULL)[ \t]*\)[ \t]*;$/ ||
					    t ~ /^return[ \t]*;$/)
						return
					worked = 1
				}
				# Strings, characters and comments carry no braces.
				{
					line = $0
					gsub(/"([^"\\]|\\.)*"/, "\"\"", line)
					gsub(/'"'"'([^'"'"'\\]|\\.)*'"'"'/, "'"''"'", line)
					sub(/\/\/.*$/, "", line)
				}
				incomment && line ~ /\*\// { sub(/^.*\*\//, "", line); incomment = 0 }
				incomment { next }
				{ gsub(/\/\*([^*]|\*+[^*\/])*\*+\//, "", line) }
				line ~ /\/\*/ { sub(/\/\*.*$/, "", line); incomment = 1 }
				# Preprocessor lines hold no definition this rule reads.
				line ~ /^[ \t]*#/ { next }
				{
					# At file scope, a line naming one of the functions before
					# any brace or semicolon starts a signature: wherever the
					# return type is, and however it is indented.
					if (depth == 0 && cur == "" && pend == "") {
						head = line
						sub(/[{;].*$/, "", head)
						for (fn in whose)
							if (match(head, "(^|[^A-Za-z0-9_])" fn "[ \t]*[(]")) {
								pend = fn; start = FNR
								break
							}
					}
					t = line
					while ((p = match(t, /[{};]/)) > 0) {
						c = substr(t, p, 1)
						if (cur != "") seg = seg " " substr(t, 1, p - 1)
						t = substr(t, p + 1)
						if (c == ";") {
							if (cur != "") { judge(seg ";"); seg = "" }
							else if (depth == 0) pend = ""
						} else if (c == "{") {
							if (cur != "") { judge(seg); seg = "" }
							else if (pend != "" && depth == 0) {
								cur = pend; pend = ""; base = depth; worked = 0; seg = ""
							}
							depth++
						} else {
							if (cur != "") { judge(seg); seg = "" }
							if (depth > 0) depth--
							if (cur != "" && depth == base) {
								if (worked)
									printf "    %s:%d: defines %s, which %s turns in (%s.c)\n", \
										FILENAME, start, cur, whose[cur], cur
								cur = ""
							}
						}
					}
					if (cur != "") seg = seg " " t
				}' "$_f"
		done)
	[ -z "$_tf_hits" ] || report \
		"a function a subject has the student turn in is written outside the zone" \
		"$_tf_hits" \
		"Outside deliverable/ and generators/ such a function may be declared, or" \
		"defined as a stub that compiles ((void) casts and a trivial return, as" \
		"tools/stub_check.sh holds a turned-in stub to): a body that does the work" \
		"is that exercise's answer outside the zone (AGENTS.md section 0), wherever" \
		"it sits and whatever it is for. A function the GRADER brings is the" \
		"contract's \`linked\`, compiled from Rust (tools/grader_lib.bzl); a" \
		"placeholder the grader's files need is a stub; a file that must do the" \
		"work for another reason is named in this rule's TURNIN_FN_ALLOW, with" \
		"the reason beside it."
fi

# ---------------------------------------------------------------------------
# N. No deliverable can break the build graph.
#
# A student's tree is in every state at some point: a syntax error, a leftover
# main(), a file not written yet, a file the subject never asked for, sources
# kept in a subfolder. The harness used to meet each of those as a BUILD error.
# A cc_binary over deliverable sources that did not compile was FAILED TO BUILD
# with no log (and, before --keep_going, the end of the whole run); a literal
# deliverable path that was not there was a "missing input file"; a glob of the
# turn-in that came back empty with allow_empty = False, or with no allow_empty
# at all, failed the LOADING of the package -- every target in the module with
# no result, over one missing file. Findings 034, 108, 128 and 172.
#
# The fix is structural (tools/defs.bzl's module docstring: every program built
# from a student's files goes through _student_bin(), every turn-in path through
# a glob or _zone()), and these checks keep the next project inside it. The
# part no lint can see -- that a macro filters every path it is handed -- is
# proven by //tools/tests:macro_fixtures_test, on toy exercises in every broken
# state.
#
# WHICH FILES. The BUILD file of every package that can hold a turn-in: each
# module in the REMOTES table, every other BUILD file under the course folders
# those modules live in (a project not in the table yet is still a project),
# and the toy exercises' package. And every .bzl file under tools/, since that
# is where a macro that builds a student's code is written.
COURSE_DIRS=$(for _m in $MODULES; do printf '%s\n' "${_m%%/*}"; done | sort -u)
TURNIN_BUILDS=$({
	for _m in $MODULES; do printf '%s/BUILD.bazel\n' "$_m"; done
	for _c in $COURSE_DIRS cursus; do
		[ -d "$_c" ] && find "$_c" -name BUILD.bazel
	done
	[ ! -d tools/tests/macro_fixtures ] || find tools/tests/macro_fixtures -name BUILD.bazel
} | sed 's#^\./##' | sort -u)
TOOLS_BZL=$(find tools -name '*.bzl' | sort)

# (a) No cc_binary, cc_library or genrule where a student's code can reach it.
#     A C rule fails the build when that code does not compile, and a genrule
#     over it fails the build on whatever its command meets; student_build.bzl's
#     rules write a stand-in program instead, one red test per layer.
for f in $TOOLS_BZL $TURNIN_BUILDS; do
	hits=$(grep -nE '^[^#]*(^|[^_A-Za-z])(cc_binary|cc_library|cc_test|genrule)[[:blank:]]*\(|^load\([^)]*"(cc_binary|cc_library)"' "$f" || true)
	[ -z "$hits" ] || report \
		"$f builds with a cc_binary, cc_library or genrule" \
		"$hits" \
		"Code a student writes must never be compiled by a Bazel C++ rule, nor" \
		"run through a genrule: one that does not compile is a BUILD error, not" \
		"a red test. Use the macros in tools/defs.bzl, which build through" \
		"_student_bin() (or student_lib() for a unit no macro declares); what" \
		"does not build then becomes a stand-in program that fails each test" \
		"that runs it, in the compiler's words."
done

# (b) Every glob of a turn-in may come back empty, and drops a name no label
#     can carry. An empty folder, or one that keeps its sources in a
#     subfolder, is the student's state; it must fail the tests that needed the
#     files, never the loading of the package (Bazel 8 and later refuse an
#     empty glob unless it says allow_empty = True). And "main (1).c" is a
#     name a desktop gives a copy: a parenthesis ends a $(location ...) early
#     and a blank is split by sh_test's args. So a package's BUILD file globs
#     its turn-in through tools/defs.bzl's turnin_glob(), which does both, and
#     a .bzl under tools/ that must glob one itself says allow_empty = True.
for f in $TURNIN_BUILDS; do
	bad=$(awk '
		{ line = $0; sub(/#.*/, "", line) }
		!inglob && line ~ /(^|[^_A-Za-z.])glob\(/ {
			inglob = 1; buf = ""; start = NR; depth = 0
			line = substr(line, index(line, "glob("))
		}
		inglob {
			buf = buf " " line
			depth += gsub(/\(/, "(", line) - gsub(/\)/, ")", line)
			if (depth <= 0) {
				inglob = 0
				if (buf ~ /"(deliverable|generators)\//)
					printf "    line %d\n", start
			}
		}' "$f")
	[ -z "$bad" ] || report \
		"$f globs a turn-in with glob(), not turnin_glob()" \
		"$bad" \
		"Use turnin_glob() from tools/defs.bzl: it may come back empty -- a" \
		"file not written yet fails the tests that needed it, not the loading" \
		"of the whole package -- and it leaves out a name no label can carry" \
		"(\"main (1).c\"), which the files layer reports by its real name."
done
for f in $TOOLS_BZL; do
	bad=$(awk '
		{ line = $0; sub(/#.*/, "", line) }
		!inglob && line ~ /(^|[^_A-Za-z])glob\(/ {
			inglob = 1; buf = ""; start = NR; depth = 0
			line = substr(line, index(line, "glob("))
		}
		inglob {
			buf = buf " " line
			depth += gsub(/\(/, "(", line) - gsub(/\)/, ")", line)
			if (depth <= 0) {
				inglob = 0
				if (buf ~ /"(deliverable|generators)\// && buf !~ /allow_empty[ \t]*=[ \t]*True/)
					printf "    line %d\n", start
			}
		}' "$f")
	[ -z "$bad" ] || report \
		"$f globs a turn-in without allow_empty = True" \
		"$bad" \
		"A glob of deliverable/ or generators/ that comes back empty -- a file" \
		"not written yet, a layout with a subfolder -- fails the LOADING of the" \
		"whole package: every target of the module with no result. Say" \
		"allow_empty = True, and let the tests that needed the files fail."
done

# (c) No literal turn-in path in a module BUILD file outside a defs.bzl macro
#     call. The macros pass every path they are given through _zone(), which
#     drops a file that is not there; a literal handed to anything else (a
#     hand-written sh_test's data, a filegroup, a top-level list) is a declared
#     input, and "missing input file" when the student deletes or renames it.
#     A path whose only use is len("deliverable/exNN/") -- cutting the prefix off
#     what a glob found -- declares nothing.
MACROS=$(sed -n 's/^def \([a-z][a-z_0-9]*\)(.*/\1/p' tools/defs.bzl | tr '\n' ' ')
#     A list comprehension of macro calls ([c_files(...) for num in ...]) is
#     read as the macro it calls.
for f in $TURNIN_BUILDS; do
	bad=$(awk -v macros="$MACROS" '
		BEGIN { n = split(macros, m, " "); for (i = 1; i <= n; i++) ok[m[i]] = 1 }
		{ line = $0; sub(/#.*/, "", line) }
		line ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/ { cur = line; sub(/[ \t]*\(.*/, "", cur) }
		line ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*=/ { cur = "=" }
		line ~ /^\[/ { cur = "[" }
		cur == "[" && line ~ /^[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/ {
			cur = line; sub(/^[ \t]+/, "", cur); sub(/[ \t]*\(.*/, "", cur)
		}
		{
			t = line
			gsub(/len\("(deliverable|generators)\/[^"]*"\)/, "", t)
			if (t ~ /"(deliverable|generators)\/[^"*]*"/ && !(cur in ok))
				printf "    line %d: %s\n", NR, $0
		}' "$f")
	[ -z "$bad" ] || report \
		"$f names a turn-in file outside a tools/defs.bzl macro" \
		"$bad" \
		"Pass it to the macro that uses it: every macro filters the paths it is" \
		"given through _zone(), so a file the student has not written, or has" \
		"renamed, fails that exercise's tests instead of the package's build."
done

# (d) Every runner that runs a built program recognises the stand-in, and every
#     test that runs one stages the contract. A program that did not build is a
#     script that prints the compiler's words and exits 86 (tools/standin.sh);
#     graded as a program, it was "memory-clean" to asan_run.sh and hundreds
#     of wrong outputs to bsq_check.sh (findings 165, 173).
#
#     Two ways to be found. By option: a runner taking --bin or --student-bin
#     runs what it is handed. And by what a test hands it: tools/defs.bzl's
#     _test() refuses, while loading, a test whose data name a student_binary
#     of its package (by kind, or by the ending _student_bin() holds its name
#     to) unless its runner is in _STANDIN_RUNNERS -- which catches a runner that
#     takes its program as a plain argument, as progname_test.sh does -- and
#     this checks every runner listed there as "checks" does call
#     standin_check, and every one listed as "gate" takes --gate-bin (the
#     program then runs only as its correctness gate, through diff_output.sh,
#     which checks it). A --gate-bin alone is not a reason to call it: the
#     gate's own runner does.
for f in tools/*.sh; do
	grep -q '^# shellcheck shell=' "$f" && continue
	grep -v '^[[:blank:]]*#' "$f" | grep -qE '^[[:blank:]]*--(bin|student-bin)\)' || continue
	grep -v '^[[:blank:]]*#' "$f" | grep -q 'standin_check ' || report \
		"$f runs a built program and never asks whether it is a stand-in" \
		"Source tools/standin.sh and call standin_check on the program before" \
		"running it (after the correctness gate, if the runner has one). A" \
		"stand-in graded as a program is a report about code that never built."
done
_sr_rows=$(sed -n '/^_STANDIN_RUNNERS = {$/,/^}$/p' tools/defs.bzl |
	sed -n 's#^[[:blank:]]*"//tools:\([a-z0-9_]*\.sh\)": "\([a-z]*\)",.*#\1 \2#p')
[ -n "$_sr_rows" ] || report \
	"tools/defs.bzl has no _STANDIN_RUNNERS table this can read" \
	"_test() refuses a test that hands a student_binary to a runner outside" \
	"it, and this checks each runner listed there. With no rows read, nothing" \
	"is checked: keep it one '\"//tools:<runner>.sh\": \"checks|gate\",' per line."
# A heredoc, not a pipe: report() counts into this shell's FAILS.
while read -r _sr _how; do
	[ -n "$_sr" ] || continue
	f="tools/$_sr"
	if [ ! -f "$f" ]; then
		report "tools/defs.bzl's _STANDIN_RUNNERS names $f, which does not exist" \
			"A row for a runner that is gone lets its name be reused unchecked."
		continue
	fi
	case "$_how" in
		checks)
			grep -v '^[[:blank:]]*#' "$f" | grep -q 'standin_check ' || report \
				"$f is listed in _STANDIN_RUNNERS as checking for a stand-in, and never does" \
				"tools/defs.bzl hands it programs built from a student's files on the" \
				"strength of that row. Source tools/standin.sh and call standin_check" \
				"on the program before running it." ;;
		gate)
			grep -v '^[[:blank:]]*#' "$f" | grep -qE '^[[:blank:]]*--gate-bin\)' || report \
				"$f is listed in _STANDIN_RUNNERS as running a program only as its gate, and takes no --gate-bin" \
				"A \"gate\" row says the program runs only through diff_output.sh, as" \
				"the correctness gate, which checks for a stand-in. Make it \"checks\"" \
				"and call standin_check, or hand the program over as --gate-bin." ;;
		*)
			report "tools/defs.bzl's _STANDIN_RUNNERS gives $f the kind '$_how'" \
				"The kinds are \"checks\" and \"gate\"." ;;
	esac
done <<SR_EOF
$_sr_rows
SR_EOF
STANDIN_RUNNERS=$(for f in tools/*.sh; do
	grep -v '^[[:blank:]]*#' "$f" | grep -q 'standin_check ' && basename "$f"
done | tr '\n' ' ')
for f in $TURNIN_BUILDS; do
	bad=$(awk -v runners="$STANDIN_RUNNERS" '
		BEGIN { n = split(runners, r, " "); for (i = 1; i <= n; i++) uses[r[i]] = 1 }
		function flush() {
			if (start && runner != "" && (runner in uses) && buf !~ /"\/\/tools:standin\.sh"/)
				printf "    line %d: %s\n", start, runner
			start = 0; buf = ""; runner = ""
		}
		{ line = $0; sub(/#.*/, "", line) }
		line ~ /(^|[^_A-Za-z])sh_test\(/ { flush(); start = NR; depth = 0 }
		start {
			buf = buf " " line
			if (match(line, /"\/\/tools:[a-z0-9_]+\.sh"/) && runner == "" && line ~ /srcs/) {
				runner = substr(line, RSTART + 9, RLENGTH - 10)
			}
			depth += gsub(/\(/, "(", line) - gsub(/\)/, ")", line)
			if (depth <= 0) flush()
		}
		END { flush() }' "$f")
	[ -z "$bad" ] || report \
		"$f has a hand-written sh_test whose runner reads tools/standin.sh, without it in data" \
		"$bad" \
		"The runner finds the stand-in contract in the test's runfiles and exits" \
		"2 without it. Tests emitted by tools/defs.bzl get it from _test(); a" \
		"sh_test written by hand lists \"//tools:standin.sh\" in its data."
done

# ---------------------------------------------------------------------------
# N. A runner that asks what standard error is held to is asked at every call.
#
# A corpus runner's standard error is the call site's choice, never a default
# (tools/runner_lib.sh, STANDARD ERROR, A CHOICE AT EVERY CALL): file_check.sh
# ignored it unless a call remembered --stderr-empty, and argv_check.sh,
# bsq_check.sh and rush02_check.sh threw it away on every run (review of
# WP-50). tools/defs.bzl refuses, while loading, a call to a runner in
# _RUNNER_CHOICES that makes the choice zero or two times; a runner that takes
# the pair and has no row there is one whose next call can forget it, and a
# row for a runner that does not take it refuses every call to that runner.
# So every tools/*.sh whose option loop takes --stderr-empty has a
# _STDERR_CHOICE row in _RUNNER_CHOICES and calls rl_stderr_choice (its own
# refusal, for a call made by hand), and every such row names one that does.
_rc_rows=$(sed -n '/^_RUNNER_CHOICES = {$/,/^}$/p' tools/defs.bzl 2> /dev/null |
	sed -n 's#^[[:blank:]]*"//tools:\([a-z0-9_]*\.sh\)": \[.*_STDERR_CHOICE.*#\1#p')
if [ -z "$_rc_rows" ]; then
	report "tools/defs.bzl has no _RUNNER_CHOICES table this can read" \
		"_test() refuses a call that does not say what a corpus runner holds" \
		"standard error to, by the rows of that table. With no rows read, nothing" \
		"is checked: keep it one '\"//tools:<runner>.sh\": [_STDERR_CHOICE],' per line."
else
	choice_bad=$(
		for f in tools/*.sh; do
			grep -v '^[[:blank:]]*#' "$f" | grep -qE '^[[:blank:]]*--stderr-empty\)' || continue
			printf '%s\n' "$_rc_rows" | grep -qx "${f#tools/}" ||
				printf '    %s takes --stderr-empty, and _RUNNER_CHOICES has no row for it\n' "$f"
			grep -v '^[[:blank:]]*#' "$f" | grep -qE '(^|[^_a-z])rl_stderr_choice([^_a-z]|$)' ||
				printf '    %s takes --stderr-empty, and never calls rl_stderr_choice\n' "$f"
		done
		for _r in $_rc_rows; do
			if [ ! -f "tools/$_r" ]; then
				printf '    _RUNNER_CHOICES names tools/%s, which does not exist\n' "$_r"
			elif ! grep -v '^[[:blank:]]*#' "tools/$_r" | grep -qE '^[[:blank:]]*--stderr-empty\)'; then
				printf '    _RUNNER_CHOICES names tools/%s, which takes no --stderr-empty\n' "$_r"
			fi
		done
	)
	[ -z "$choice_bad" ] || report \
		"a runner's standard-error choice and _RUNNER_CHOICES disagree" \
		"$choice_bad" \
		"A runner that takes --stderr-empty / --stderr-ignored REASON is listed in" \
		"tools/defs.bzl's _RUNNER_CHOICES with [_STDERR_CHOICE], so every call is" \
		"made to choose while loading, and calls rl_stderr_choice, so a call by" \
		"hand is too. A row there names a runner that takes the pair."
fi
# The same both ways for --quotes, the subject's sentences a runner one project
# calls quotes (V90; tools/runner_lib.sh, "A SUBJECT'S SENTENCE COMES FROM THE
# CALL SITE"): a runner that calls rl_quotes_ready has a _QUOTES_CHOICE row,
# so a call without the file fails while loading, and a row names a runner
# that checks it.
_rq_rows=$(sed -n '/^_RUNNER_CHOICES = {$/,/^}$/p' tools/defs.bzl 2> /dev/null |
	sed -n 's#^[[:blank:]]*"//tools:\([a-z0-9_]*\.sh\)": \[.*_QUOTES_CHOICE.*#\1#p')
quotes_bad=$(
	for f in tools/*.sh; do
		[ "$f" = tools/runner_lib.sh ] && continue
		grep -v '^[[:blank:]]*#' "$f" | grep -qE '(^|[^_a-z])rl_quotes_ready[[:blank:]]' || continue
		printf '%s\n' "$_rq_rows" | grep -qx "${f#tools/}" ||
			printf '    %s calls rl_quotes_ready, and _RUNNER_CHOICES gives it no _QUOTES_CHOICE\n' "$f"
	done
	for _r in $_rq_rows; do
		if [ ! -f "tools/$_r" ]; then
			printf '    _RUNNER_CHOICES names tools/%s, which does not exist\n' "$_r"
		elif ! grep -v '^[[:blank:]]*#' "tools/$_r" | grep -qE '(^|[^_a-z])rl_quotes_ready[[:blank:]]'; then
			printf '    _RUNNER_CHOICES gives tools/%s _QUOTES_CHOICE, and it never calls rl_quotes_ready\n' "$_r"
		fi
	done
)
[ -z "$quotes_bad" ] || report \
	"a runner's --quotes and _RUNNER_CHOICES disagree" \
	"$quotes_bad" \
	"A runner that checks its --quotes file (rl_quotes_ready) is listed in" \
	"tools/defs.bzl's _RUNNER_CHOICES with _QUOTES_CHOICE, so a call without" \
	"the subject's sentences fails while loading; a row with _QUOTES_CHOICE" \
	"names a runner that checks them."

# ---------------------------------------------------------------------------
# N. Every test in a BUILD file is a macro's or hand_test()'s.
#
# A test written with sh_test() directly carries whatever tags its author
# typed, and the exercise tag is the one they left out: twelve hand-written
# tests were in no :exNN suite, while the docs promised every layer there
# (findings 070, 074, 175) -- _test() derived that tag, and lvl_tags(), which
# they used, did not. hand_test() goes through _test(), so there is one way
# to write a test, and c_levels()' audit holds every test of a project to the
# module-wide rules at once. lvl_tags() is left for a test rule that is not
# an sh_test, outside every project (//tools/cc_toolchain's), so a project's
# BUILD file does not call it either.
find . -name BUILD.bazel -not -path './bazel-*' | sed 's#^\./##' | sort > "$lex_d/files"
while IFS= read -r f; do
	hits=$(grep -nE '^[^#]*(^|[^_A-Za-z"])sh_test[[:blank:]]*\(|^load\(.*"sh_test"' "$f" || true)
	[ -z "$hits" ] || report \
		"$f declares a test with sh_test()" \
		"$hits" \
		"Declare it with hand_test(name, layer, ...) from //tools:defs.bzl: it" \
		"derives the exercise tag and the level ladder the way every macro's" \
		"test gets them, and c_levels()' audit reads them (docs/reference.md," \
		"\"Suites\")."
done < "$lex_d/files"
for f in $TURNIN_BUILDS; do
	hits=$(grep -nE '^[^#]*(^|[^_A-Za-z])lvl_tags[[:blank:]]*\(' "$f" || true)
	[ -z "$hits" ] || report \
		"$f calls lvl_tags()" \
		"$hits" \
		"lvl_tags() gives a layer and a level, and no exercise tag: a test it" \
		"tags is in no :exNN suite. In a project, hand_test() or a macro."
done

# ---------------------------------------------------------------------------
# N. A word of a test's `args` is quoted by shell_word(), and by nothing else.
#
# Bazel expands a test's `args` ($(...), $$) and then splits them as a shell
# would, so a sentence, a file name with a blank or a '$' has to be quoted to
# arrive as itself. There were two ways of doing it: _shell_word ('"'"' for
# an apostrophe, and a '$' refused, its docstring saying one cannot be quoted)
# behind stderr_ignored() and exit_quote, and an inline `'" + x.replace("$",
# "$$").replace("'", ...) + "'` at --stray, at --wording and in
# starlark_unit.bzl, which quoted a '$' without trouble. So one call site
# refused what the other passed, for the same kind of word. What a quoting of
# one's own writes is an apostrophe replaced, a '$' doubled by hand
# (c_cycles' unit_expr did that alone, and so refused the quotes it could not
# carry), or a single quote opened or closed around a value -- "'%s'" % x,
# "'" + x + "'" -- the naive form, which splits at the value's first
# apostrophe and loses its '$'. That is what this looks for, outside
# comments, in every .bzl and BUILD file but in shell_word's own body. A
# possessive ("%s's", + "'s") is no quote.
_sq_bad=$(find . \( -name BUILD.bazel -o -name '*.bzl' \) -not -path './bazel-*' 2> /dev/null |
	sed 's#^\./##' | sort | while IFS= read -r f; do
		awk -v f="$f" '
			/^def / { inq = ($0 ~ /^def shell_word\(/) }
			/^[^ \t#]/ && !/^def / { inq = 0 }
			/^[ \t]*#/ || inq { next }
			index($0, ".replace(\"\047\"") || index($0, ".replace(\047\\\047\047") ||
			index($0, ".replace(\"$\"") ||
			/\047%[a-z]/ || /%[a-z]\047([^a-z]|$)/ ||
			/\047" *\+/ || /\+ *"\047([^A-Za-z]|$)/ {
				l = $0; sub(/^[ \t]+/, "", l)
				printf "    %s:%d: %s\n", f, FNR, l
			}' "$f"
	done)
[ -z "$_sq_bad" ] || report \
	"a .bzl or BUILD file quotes a word of a test's args by hand" \
	"$_sq_bad" \
	"Pass it through shell_word() from //tools:defs.bzl: it doubles each '\$'" \
	"(Bazel expands \$(...) and \$\$ in args) and single-quotes the whole, each" \
	"apostrophe as '\\\\'' (Bazel then splits args as a shell would), so the" \
	"runner receives exactly the text. One quoting, so no call site refuses" \
	"what another passes."

# ---------------------------------------------------------------------------
# N. Every project reads its turn-in from ONE subject contract.
#
# What an exercise turns in, where, what the grader brings and what it may
# call are facts of the subject, and they used to be typed again at every call
# site that needed one -- a c_files() list, an `allowed`, a header in `hdrs`, a
# `provided_hdrs`, an overlay, a glob of deliverable/exNN -- each copy decided
# on its own, often from the answer beside it. They disagreed: C 12 ex08's
# header was optional to one layer and a build input to the rest, C 09 ex01
# compiled the grader's srcs/ as the student's work, BSQ turned in under an
# ex00/ its subject never names (findings 096, 128, 177; TODO.md §23). Now
# each project's BUILD file opens with subject() (tools/subject.bzl), the
# macros read everything from it, and the parameters that took a second copy
# are gone. c_levels() fails in a package without a contract; these two rules
# keep the shape where a load cannot see it.
#
# (e) A BUILD file that calls a tools/defs.bzl macro calls subject() FIRST: a
#     macro called before it has no contract to read and fails, and a file
#     where the contract sits below the calls reads as if it came from them.
for f in $TURNIN_BUILDS; do
	first=$(awk -v macros="$MACROS subject" '
		BEGIN { n = split(macros, m, " "); for (i = 1; i <= n; i++) ok[m[i]] = 1 }
		{ line = $0; sub(/#.*/, "", line) }
		line ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/ || line ~ /^\[?[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/ {
			name = line; sub(/^\[?[ \t]*/, "", name); sub(/[ \t]*\(.*/, "", name)
			if (name in ok) { print NR " " name; exit }
		}' "$f")
	[ -n "$first" ] || continue
	[ "${first#* }" = subject ] && continue
	report \
		"$f calls ${first#* } (line ${first%% *}) before any subject()" \
		"A project's BUILD file opens with its subject contract (tools/subject.bzl):" \
		"where each exercise turns in, its files, what the grader brings, what it" \
		"may call -- transcribed from the subject's header boxes. Every macro reads" \
		"those from it, and one called before it has nothing to read."
done

# (e2) tools/first_red.sh reads each exercise's turn-in folder from the
#     contract too -- it runs outside Bazel, on a log, so it reads the
#     subject() call as written rather than the JSON the macros read -- and
#     that reading holds only for the form every project writes it in. So it
#     has to find an entry for every exercise the project tests: a contract
#     written another way (a comprehension, an entry on a helper's line)
#     would leave first_red guessing nothing and calling a written exercise
#     "not written yet". //tools/tests:macro_fixtures_test holds the same
#     reading to the macros' own turnin_dir() for every exercise of every
#     project (each module's :turnin_dirs, which c_levels() emits) and of the
#     toy ones: finding an entry is this check's, reading the right folder
#     from it is that test's.
#     The workspace's copy is the one read (under bazel test, the runfiles
#     tree, which holds //tools:conventions_srcs); a selftest's fixture tree
#     holds none, and there the one beside this script is.
fr_unread=""
_frsh="$WS/tools/first_red.sh"
[ -f "$_frsh" ] || _frsh="$CONV_HOME/first_red.sh"
[ -f "$_frsh" ] || {
	echo "conventions.sh: tools/first_red.sh is neither in $WS nor beside this script" >&2
	exit 2
}
for f in $TURNIN_BUILDS; do
	_fm=${f%/BUILD.bazel}
	[ -d "$_fm/tests" ] || continue
	grep -q '^subject(' "$f" || continue
	for _ft in "$_fm"/tests/ex[0-9][0-9]; do
		[ -d "$_ft" ] || continue
		# conventions: harness tool -- first_red.sh --turnin reads a BUILD file and runs nothing
		sh "$_frsh" --turnin "$_fm" "${_ft##*/}" > /dev/null 2>&1 && continue
		fr_unread="$fr_unread
    $f: ${_ft##*/}"
	done
done
[ -z "$fr_unread" ] || report \
	"tools/first_red.sh cannot read an exercise's turn-in folder from its subject()" \
	"${fr_unread#?}" \
	"Write each entry as the other projects do, one \"NN\": exercise(...) per" \
	"exercise inside subject( ... ), with dir = \"exNN/\" or dir = None: that is" \
	"the form tools/first_red.sh reads (its turnin_of) when it decides whether an" \
	"exercise is written."

# (f) No turn-in path is spelled outside the contract's readers. Every path a
#     layer builds starts from turnin_dir(), which is the subject's "Turn-in
#     directory" line or deliverable/ itself; a "deliverable/..." written
#     anywhere else is the layout decided a second time -- the exNN convention
#     that put BSQ under ex00/. In tools/defs.bzl only the readers themselves
#     may say it -- and the readers of the whole pushed tree, whose root is
#     deliverable/ whatever the subject says (_misplaced, _student_folders,
#     _outside_exercises). In a project's BUILD file nothing may: a call site that must
#     name one turn-in file (a unit of another exercise's sources) builds it
#     with turnin_file(num, name), which fails unless the contract lets the
#     exercise hold that file -- a literal did not, and a path to a folder the
#     contract no longer has was quietly dropped by _zone(). Code only:
#     comments and docstrings may say where things go.
f=tools/defs.bzl
if [ -f "$f" ]; then
	bad=$(awk '
		function code(s) { sub(/#.*/, "", s); return s }
		/^def / { fn = $2; sub(/\(.*/, "", fn) }
		{
			line = $0
			n = gsub(/"""/, "&", line)
			if (indoc) { if (n % 2) indoc = 0; next }
			if (n % 2) { indoc = 1; next }
			if (n) next
			c = code(line)
			if (c ~ /"deliverable(\/|")/ && fn != "turnin_dir" && fn != "_where" && fn != "_in_zone" && fn != "_nested_in_turnin" && fn != "_misplaced" && fn != "_student_folders" && fn != "_outside_exercises")
				printf "    line %d (%s): %s\n", NR, fn, $0
		}' "$f")
	[ -z "$bad" ] || report \
		"$f spells a turn-in directory outside the subject contract's readers" \
		"$bad" \
		"Build the path from turnin_dir(num): it is the subject's turn-in line, or" \
		"deliverable/ itself where the subject has none. A macro that writes" \
		"\"deliverable/\" + ex decides the layout for the subject, which is how BSQ" \
		"ended up under an ex00/ its subject never names."
fi
for f in $TURNIN_BUILDS; do
	bad=$(awk '
		{
			line = $0
			n = gsub(/"""/, "&", line)
			if (indoc) { if (n % 2) indoc = 0; next }
			if (n % 2) { indoc = 1; next }
			if (n) next
			c = $0; sub(/#.*/, "", c)
			if (c ~ /"(deliverable|generators)(\/|")/) printf "    line %d: %s\n", NR, $0
		}' "$f")
	[ -z "$bad" ] || report \
		"$f spells a turn-in path at a call site" \
		"$bad" \
		"Name the file with turnin_file(\"NN\", \"name\") from //tools:defs.bzl: it" \
		"builds the path from the subject() contract, and fails while loading when" \
		"the contract does not let that exercise hold the file. A literal decides" \
		"the layout a second time, and quietly stops matching when the contract" \
		"moves the turn-in (BSQ's ex00/ -> deliverable/)."
done

# (g) A layer's headers reach its runner's include path through _inc_args()
#     alone. The include path a layer compiles with is the GRADER's: a header
#     beside the sources is found there, one in a subfolder only through the
#     Makefile's -I or a #include that names the subfolder. The per-header loop
#     -- `for h in hdrs: args += ["--hdr", "$(location %s)" % h]` -- put every
#     staged header's directory on -I, and the compile layers went green on a
#     turn-in the grader cannot compile (a header in includes/, beside a
#     stand-in program that said exactly that).
f=tools/defs.bzl
if [ -f "$f" ]; then
	bad=$(awk '
		/^def / { fn = $2; sub(/\(.*/, "", fn) }
		{ c = $0; sub(/#.*/, "", c) }
		c ~ /\[ *"--(hdr|inc)", *"\$\(location %s\)" *% *[A-Za-z_]+ *\]/ && fn != "_inc_args" {
			printf "    line %d (%s): %s\n", NR, fn, $0
		}' "$f")
	[ -z "$bad" ] || report \
		"$f puts headers on a runner's include path outside _inc_args()" \
		"$bad" \
		"Pass them with args += _inc_args(\"--hdr\", hdrs): it leaves a header in a" \
		"subfolder of the turn-in off the path, as the grader's compile line does."
fi

# (h) A BUILD file quotes the Norm through tools/defs.bzl's NORM_* constants,
#     never in words of its own. The Norm binds every project that turns in a
#     Makefile, so its sentence is one fact, and it was typed out at five call
#     sites -- a revision of the Norm would have had to find all five (AGENTS.md
#     §6, "declare a project's facts once"). A string that cites the Norm by
#     its version is the shape every copy took.
for f in $TURNIN_BUILDS; do
	[ -f "$f" ] || continue
	hits=$(grep -n '"The Norm, v[0-9]' "$f" || true)
	[ -z "$hits" ] || report \
		"$f quotes the Norm in words of its own" \
		"$hits" \
		"Load the sentence from tools/defs.bzl (NORM_NO_WILDCARDS, NORM_NO_RELINK)," \
		"or add a NORM_* constant there for one it lacks: a sentence of the Norm" \
		"is every project's, and written once."
done

# ---------------------------------------------------------------------------
# N. No runner names the grader; the project's contract does.
#
# Who grades a project is a fact of its subject: the Moulinette (a program,
# every Piscine module and BSQ), or the evaluators at a defense (the rushes,
# "not verified by a program"). Every runner used to say "the Moulinette" in
# its own words, and told a rush team that a forbidden call was "an outright
# KO at the Moulinette", which grades no rush (finding 145). Now the contract's
# `grader` reaches every test as RL_GRADER, and tools/runner_lib.sh's rl_at
# words it ("at the Moulinette", "at the defense"). So:
#
#   (a) no source under tools/ that a test runs and that prints -- a runner
#       in shell, and the harness's own C and Python (exit_status.c,
#       perf_run.c, norminette_main.py, ...) -- says "Moulinette" in its
#       code; comments and docstrings may, to say why. rl_at is the one place
#       that may. tools/*.bzl is not in it: a macro's words reach a person
#       through fail() while a BUILD file loads, which speaks to whoever edits
#       one, and a runner's words through its own source, which (a) reads.
#       tools/tests/ is not either: the selftest prints to the harness's
#       maintainers, and its fixtures name graders on purpose;
#   (b) a project graded only at a defense says "Moulinette" in nothing it
#       prints: its hints and its tests' own files. Its BUILD comments may,
#       to say that nothing grades it that way. Which projects those are is
#       read from each BUILD file's subject() call -- its `grader` keyword, a
#       string literal -- never from the text anywhere in the file, which a
#       comment quoting another project's contract would match (and a
#       contract spelled differently would not). A subject() whose grader is
#       not a literal is reported: neither this check nor the template build
#       could read it.

# code_of FILE -- FILE's lines that are code, as "N:line": comments and (for
# Python) docstrings dropped, by the file's extension. Approximate on purpose
# -- a comment marker inside a string literal is taken for one -- which errs
# toward reading LESS as code, never more.
code_of() {
	case "$1" in
		*.sh)
			grep -n '' "$1" | grep -v '^[0-9]*:[[:space:]]*#' ;;
		*.c | *.h)
			awk '{
				line = $0; out = ""
				while (line != "") {
					if (inc) {
						e = index(line, "*/")
						if (e == 0) { line = ""; break }
						line = substr(line, e + 2); inc = 0; continue
					}
					b = index(line, "/*"); l = index(line, "//")
					if (l > 0 && (b == 0 || l < b)) { out = out substr(line, 1, l - 1); line = ""; break }
					if (b == 0) { out = out line; line = ""; break }
					out = out substr(line, 1, b - 1); line = substr(line, b + 2); inc = 1
				}
				if (out ~ /[^ \t]/) print NR ":" out
			}' "$1" ;;
		*.py)
			awk '{
				line = $0
				n = gsub(/"""/, "&", line)
				if (indoc || n > 0) { if (n % 2 == 1) indoc = !indoc; next }
				sub(/#.*/, "", line)
				if (line ~ /[^ \t]/) print NR ":" line
			}' "$1" ;;
	esac
}

# contract_grader BUILD -- the `grader` its subject() call names: the
# literal's value, "?" when it is not a string literal, nothing when the
# file calls no subject(). The call is read whole, from "subject(" at the
# start of a line to its closing parenthesis, comments dropped.
contract_grader() {
	awk '
		!ins && !done && /^subject[ \t]*\(/ { ins = 1 }
		ins {
			line = $0; sub(/#.*/, "", line)
			call = call " " line
			n = length(line)
			for (i = 1; i <= n; i++) {
				c = substr(line, i, 1)
				if (c == "(") depth++
				else if (c == ")" && --depth == 0) { ins = 0; done = 1; break }
			}
		}
		END {
			if (call == "") exit
			if (match(call, /[(, \t]grader[ \t]*=[ \t]*"[a-z]*"/)) {
				g = substr(call, RSTART, RLENGTH)
				sub(/^[^"]*"/, "", g); sub(/"$/, "", g)
				print g
			} else
				print "?"
		}' "$1"
}

bad=""
for f in tools/*.sh tools/*.c tools/*.h tools/*.py; do
	[ -f "$f" ] || continue
	# The one place that may, and this check, which has to spell what it seeks.
	case "$f" in tools/runner_lib.sh | tools/conventions.sh) continue ;; esac
	hits=$(code_of "$f" | grep 'Moulinette' | sed "s|^|    $f:|")
	[ -z "$hits" ] || bad="$bad$hits
"
done
[ -z "$bad" ] || report \
	"a runner names the grader in its own words" \
	"$bad" \
	"Say where it costs through runner_lib.sh's rl_at (\"an outright KO \$(rl_at)\"):" \
	"the project's subject() contract says who grades it, and a rush is graded" \
	"at a defense, by people, not by the Moulinette. A harness program in C or" \
	"Python that prints a cost leaves the grader to the runner that starts it."
for f in $TURNIN_BUILDS; do
	g=$(contract_grader "$f")
	d=${f%/BUILD.bazel}
	case "$g" in
		"" | moulinette | both) continue ;;
		defense) ;;
		*)
			report \
				"$f's subject() gives no grader this check can read" \
				"Write it as a string literal -- grader = \"moulinette\", \"defense\" or" \
				"\"both\" -- in the subject() call itself (tools/subject.bzl)."
			continue ;;
	esac
	[ -d "$d/tests" ] || continue
	hits=$(grep -rn 'Moulinette' "$d/tests" 2> /dev/null | sed 's/^/    /')
	[ -z "$hits" ] || report \
		"$d is graded at a defense, and its tests/ says Moulinette" \
		"$hits" \
		"Its subject says no program grades it: what a student reads there names" \
		"the defense (its hints), or no grader at all (runner_lib.sh's rl_at)."
done

# ---------------------------------------------------------------------------
# N. Every //oracle arm that writes a project's fixtures is held by a test.
#
# A named case reads its input and its expected output from files under
# tests/, and where a project has them written by the reference --
# `oracle bsq_fixtures`, `oracle rush00_fixtures`, one record per file --
# tools/oracle_fixtures.sh is what keeps the two together: it fails when a
# file differs from its record, and when a file its --owns patterns match is
# named by no record (a hand-typed one joining them unseen). That holds only
# where a project declares the test. BSQ's BUILD file said its fixtures were
# "generated from //oracle's first record, so the two cannot drift", and
# nothing held them to it. So an arm answering to "<name>_fixtures" -- the
# name, as a string literal, in oracle/src/*.rs -- is passed as `--fn` by a
# test in some BUILD.bazel that runs //tools:oracle_fixtures.sh: a reference
# that writes files nothing compares is a fixture free to drift. The converse
# needs no rule: a --fn that names no arm gets no record, which the runner
# refuses (exit 2).
fixture_arms=$(find oracle/src -name '*.rs' 2> /dev/null | sort | while IFS= read -r f; do
	grep -v '^[[:blank:]]*//' "$f" | grep -o '"[a-z0-9_]*_fixtures"' | tr -d '"' |
		sed "s#\$# $f#"
done | sort -u)
fixture_tests=$(find . -name BUILD.bazel -not -path './bazel-*' | sed 's#^\./##' | sort |
	while IFS= read -r f; do
		grep -q 'oracle_fixtures\.sh' "$f" && printf '%s\n' "$f"
	done)
if [ -z "$fixture_arms" ] && [ -d oracle/src ]; then
	# BSQ's, Rush 00's and Rush 02's arms are there; finding none means the
	# pattern stopped matching, and every arm would be held to nothing.
	report \
		"no //oracle arm named *_fixtures was found in oracle/src" \
		"bsq_fixtures, rush00_fixtures and rush02_fixtures are there: the search above no longer" \
		"reads them, so this check holds nothing. Fix the pattern."
fi
unheld=$(printf '%s\n' "$fixture_arms" | while read -r arm src; do
	[ -n "$arm" ] || continue
	held=""
	for b in $fixture_tests; do
		grep -q "\"$arm\"" "$b" && { held=1; break; }
	done
	[ -n "$held" ] || printf '    %s (%s)\n' "$arm" "$src"
done)
[ -z "$unheld" ] || report \
	"an //oracle arm writes fixtures that no test compares" \
	"$unheld" \
	"Declare the project's exNN_oracle_fixtures: a hand_test running" \
	"//tools:oracle_fixtures.sh with --fn <the arm>, --in-dir-of a file in the" \
	"fixtures' directory and --owns for every pattern of files the arm writes" \
	"(c-piscine/c-piscine-bsq/BUILD.bazel has one)."

# The files a fixture test holds to //oracle are its --owns patterns, written
# in its BUILD file. Rush 00's tests/ex00/regen.sh passed the same patterns
# again, by hand, to tools/oracle_fixtures.sh -- one list in two places,
# which drift -- where `bazel run //<project>:exNN_oracle_fixtures -- --write`
# runs the test's own. So no script beside a project's tests passes --owns.
owns_copies=$(find . -path './bazel-*' -prune -o -path '*/tests/*' -name '*.sh' -print 2> /dev/null |
	sed 's#^\./##' | sort | while IFS= read -r f; do
		case "$f" in tools/*) continue ;; esac
		grep -n -e '--owns' "$f" 2> /dev/null | grep -v '^[0-9]*:[[:blank:]]*#' | sed "s#^#    $f:#"
	done)
[ -z "$owns_copies" ] || report \
	"a script beside a project's tests passes --owns to oracle_fixtures.sh" \
	"$owns_copies" \
	"The patterns are the BUILD file's, as its exNN_oracle_fixtures test passes" \
	"them: run that test with \`bazel run //<project>:exNN_oracle_fixtures -- --write\`" \
	"(c-piscine/c-piscine-rush-00/tests/ex00/regen.sh does), not a second copy."

# ---------------------------------------------------------------------------
# N. A file list of this script sees a runfiles tree's files.
#
# Under `bazel test` this script reads a runfiles tree, where every file is a
# symlink, and `find -type f` skips a symlink. The escape rule and the
# rc-file rule listed their files that way: under the test they saw none and
# passed, while `bazel run` reported C 03 ex05's test program (V23). So a find
# here that asks for regular files asks for symlinks too. (The words are
# split below so this rule does not read itself.) The workspace's copy, or
# this script's own where the workspace is a selftest fixture that has none.
_tfs=tools/conventions.sh
[ -f "$_tfs" ] || _tfs="$CONV_HOME/conventions.sh"
_tf=$(awk -v t='-type' '
	/^[[:blank:]]*#/ { next }
	index($0, t " f") && !index($0, t " l") { l = $0; sub(/^[[:blank:]]+/, "", l); printf "    tools/conventions.sh:%d: %s\n", FNR, l }' \
	"$_tfs") || report "tools/conventions.sh could not be read to check its own file lists" \
	"Looked for at $_tfs."
[ -z "$_tf" ] || report "tools/conventions.sh lists files with a find that skips symlinks" \
	"$_tf" \
	"Under bazel test the tree it reads is runfiles, every file a symlink, so" \
	"a find for regular files alone finds none, and the rule passes having" \
	"read nothing. Ask for both: \\( -type f -o -type l \\)."

# ---------------------------------------------------------------------------
# A CR IN A FILE GIT WOULD REWRITE.
#
# .gitattributes opens with `* text=auto eol=lf`: a text file's CR LF becomes
# LF when it is committed. So a file holding a CR byte is committed without
# it unless a -text (or binary) rule there covers it, and the checkout that
# wrote it goes on testing bytes no clone has: Rush 02's crlf.dict, whose line
# endings ARE its case, was committed with LF only, so on every clone the
# case tested nothing and ex00_oracle_fixtures failed, while here both were
# green. Every file this run sees that git would rewrite must match a -text
# or binary pattern of .gitattributes. What git rewrites is a file it reads as
# text holding a CR LF: one with a NUL, or with a lone CR (one no LF follows),
# it takes for binary and commits as it is, CR LFs included (git's
# convert_is_binary; checked with git 2.34 on `a\rb\n` and `a\rb\r\n`), so
# such a file is not reported -- this rule once named every file holding a CR.
# c_levels()' conventions_srcs lists every exercise's tests/ folder, so the
# test sees the fixtures too.
#
# And a harness TEXT file -- a clues*.tsv, a shell script, a BUILD or .bzl
# file -- holds no CR at all, whichever -text rule covers it. Those are read as
# text by the runners and Bazel, never handed to a program as a case's bytes,
# so a CR in one is an editor's. The -text rule once covered every file under
# an exercise's tests/, and a CR typed into a clue there was committed as it
# was and exempted from the check above too.
CR=$(printf '\r')
# _git_strips FILE: it holds a CR LF and no lone CR, so text=auto rewrites it.
_git_strips() {
	LC_ALL=C od -An -v -tx1 "$1" | LC_ALL=C awk '
		{ for (i = 1; i <= NF; i++) { if (p == "0d") { if ($i == "0a") crlf = 1; else lone = 1 }; p = $i } }
		END { if (p == "0d") lone = 1; exit !(crlf && !lone) }'
}
if [ -f .gitattributes ] && awk '!/^#/ && $1 == "*" { for (i = 2; i <= NF; i++) if ($i ~ /^text/) f = 1 } END { exit !f }' .gitattributes; then
	_exempt=$(awk '!/^#/ && NF >= 2 { for (i = 2; i <= NF; i++) if ($i == "-text" || $i == "binary") { print $1; break } }' .gitattributes)
	_cr=$(find . \( -path './bazel-*' -o -path ./.git \) -prune -o \( -type f -o -type l \) -print0 2> /dev/null |
		LC_ALL=C xargs -0 grep -lI "$CR" 2> /dev/null | sed 's|^\./||' | while IFS= read -r _f; do
			_ok=0
			set -f
			for _p in $_exempt; do
				# gitattributes' ** to the shell's *, anchored at the root
				# unless the pattern starts with a wildcard.
				_g=$(printf '%s' "$_p" | sed 's|^\*\*/|*/|; s|/\*\*$|/*|; s|/\*\*/|/*/|g')
				case "$_g" in \** | /*) ;; *) _g="/$_g" ;; esac
				# shellcheck disable=SC2254 # $_g is the pattern, unquoted on purpose.
				case "/$_f" in $_g) _ok=1; break ;; esac
			done
			set +f
			case "${_f##*/}" in
				clues*.tsv | *.sh | BUILD.bazel | BUILD | *.bzl)
					echo "    $_f (a harness text file, which no -text rule exempts)" ;;
				*) [ "$_ok" = 1 ] || ! _git_strips "$_f" || echo "    $_f" ;;
			esac
		done)
	[ -z "$_cr" ] || report "a file holds a CR byte that .gitattributes' text rule strips when it is committed" \
		"$_cr" \
		"What is committed, and what every clone gets, is the file without its" \
		"CRs, so a case that needs them tests nothing there. Where the bytes are" \
		"the point, put the file in its exercise's tests/exNN/fixtures/, which" \
		".gitattributes' -text rule covers; anywhere else -- and always in a" \
		"clue, a script or a BUILD file -- drop the CRs."
fi

# ---------------------------------------------------------------------------
# N. A harness sizes what it fills from its input from the case.
#
# A reader harness (tests/exNN/diff_*.c) decodes each corpus line into arrays
# and hands them to the student's function. Thirty of them did it into fixed
# ones -- int tab[64], char *items[64], char *arr[513], a 64 KiB pipe read --
# sized for the corpus of the day. The first case past that size overflowed
# the harness's own stack, or was silently cut short or skipped, and either
# way the differ blamed the student for an answer to a case nobody wrote
# (finding 041). tools/diffio.h now decodes into arrays sized from the line
# (dio_csv_ints, dio_hex_list, dio_hex_n, dio_split_all, dio_alloc), and
# this holds every harness to it: no array of constant size, but the two
# bounded by construction -- the `line` (or `g_line`) dio_line reads into (it
# exits 2 on a longer one) and the fields `f` dio_split fills (never past its
# count) -- and a constant table with an initializer, which no corpus fills.
# An array the input never reaches -- a label snprintf'd from two ints, say --
# says so on its line or in the comment right above it:
#
#     /* conventions: bounded -- <what bounds it> */
#
# Which harnesses: every C file under an exercise's tests/ that READS ITS
# CASES -- dio_line or dio_getline, fread or fgets from stdin, getline, a
# read() on descriptor 0 -- whatever its name. It was every diff_*.c, by name,
# and Rush 00's sweep and defense harnesses read their cases from stdin under
# another (survive_rush.c, test_defense.c); a curated fixture that reads no
# input, whose arrays hold the cases it was written with, is not one.
_reads_cases() {  # _reads_cases FILE: it reads its cases from input
	case "${1##*/}" in diff_*.c) return 0 ;; esac
	grep -Eq '(^|[^A-Za-z0-9_])(dio_line|dio_getline|getline)[[:blank:]]*\(|(fread|fgets)[[:blank:]]*\([^;]*stdin|(^|[^A-Za-z0-9_])read[[:blank:]]*\([[:blank:]]*(0|STDIN_FILENO)[[:blank:]]*,' "$1"
}
for f in $(for _m in $MODULES; do
	[ -d "$_m/tests" ] && find "$_m/tests" -name '*.c'
done | sort); do
	_reads_cases "$f" || continue
	bad=$(awk '
		{
			# The marker, in a comment on this line or the line above.
			if (index($0, "conventions: bounded -- ")) mark = NR
		}
		/^[ \t]*(\/\*|\*)/ { next }
		{
			l = $0
			sub(/\/\*.*$/, "", l)
			sub(/\/\/.*$/, "", l)
			if (l !~ /^[ \t]*(static[ \t]+)?(const[ \t]+)?((unsigned|signed|long|short)[ \t]+)*[A-Za-z_][A-Za-z_0-9]*[ \t]+[* \t]*[A-Za-z_][A-Za-z_0-9]*[ \t]*\[[^]]+\]/) next
			if (l ~ /=/) next
			name = l
			sub(/\[.*/, "", name)
			sub(/.*[ \t*]/, "", name)
			if (name ~ /(^|_)line$/ || name == "f") next
			if (mark == NR || mark == NR - 1) next
			printf "%d: %s\n", NR, $0
		}' "$f")
	[ -z "$bad" ] || report "$f fills an array of fixed size from the corpus" \
		"$bad" \
		"The first case bigger than that size overflows the harness, or is cut" \
		"short, and the differ blames the student. Decode it with tools/diffio.h's" \
		"case-sized helpers (dio_csv_ints, dio_hex_list, dio_hex_n, dio_split_all," \
		"dio_alloc): see \"SIZED FROM THE CASE\" there. An array the input never" \
		"reaches says what bounds it: /* conventions: bounded -- <why> */"
done

# ---------------------------------------------------------------------------
# N. A runner that replays a generated corpus can replay it under the memory
#    checkers, and tools/defs.bzl's _CORPUS_RUNNERS lists exactly those runners.
#
# Every generated corpus -- Rush 01's sweep, Rush 02's dictionaries, BSQ's
# maps, C 06's arguments, C 10's files -- ran on the plain build only, while
# the memory layers ran each fixed case alone, so a path only generated input
# reaches was never memory-checked (finding 113). The corpus runners take
# --sanitized and --valgrind through tools/runner_lib.sh's rl_mem_* now, and
# c_levels()' audit holds a package's plain replay to its memory twins -- for
# the runners _CORPUS_RUNNERS names, and only those. So the next corpus runner
# cannot slip past either: one that takes --bin and --oracle and sweeps
# (rl_sweep_next) calls rl_mem_opt and rl_mem_run and is listed, and every
# runner listed exists and does. The audit matches each plain replay to twins
# of the SAME corpus -- its arguments less _CORPUS_RUN_OPTS -- since one twin
# per runner left BSQ's stdin and grouped maps checked nowhere; every option
# that table names is one a listed runner takes.
if [ -f tools/defs.bzl ]; then
	_cr=$(sed -n '/^_CORPUS_RUNNERS = \[/,/^\]/p' tools/defs.bzl)
	if [ -z "$_cr" ]; then
		report "tools/defs.bzl has no _CORPUS_RUNNERS list this can read" \
			"c_levels()' audit holds a corpus replay to its memory twins for the" \
			"runners listed there. Keep it one '\"//tools:<runner>.sh\",' per line."
	fi
	for f in tools/*.sh; do
		[ "$f" = tools/runner_lib.sh ] && continue
		_cw=$(awk -F'\t' '{ n = split($4, w, "\037"); for (i = 1; i <= n; i++) print w[i] }' \
			"$(cmds_of "$f")" | sort -u)
		_sweeps=0
		_mem=0
		_listed=0
		printf '%s\n' "$_cw" | grep -qx 'rl_sweep_next' && _sweeps=1
		printf '%s\n' "$_cw" | grep -qx 'rl_mem_opt' &&
			printf '%s\n' "$_cw" | grep -qx 'rl_mem_run' && _mem=1
		printf '%s\n' "$_cr" | grep -qF "\"//tools:${f#tools/}\"" && _listed=1
		_corpus=0
		if [ "$_sweeps" = 1 ] &&
			grep -v '^[[:blank:]]*#' "$f" | grep -qE '^[[:blank:]]*--bin\)' &&
			grep -v '^[[:blank:]]*#' "$f" | grep -qE '^[[:blank:]]*--oracle\)'; then
			_corpus=1
		fi
		if [ "$_corpus" = 1 ] && [ "$_mem" = 0 ]; then
			report "$f replays a generated corpus and cannot replay it under a memory checker" \
				"Take --sanitized and --valgrind through tools/runner_lib.sh (rl_mem_opt," \
				"rl_mem_ready, rl_mem_pick, rl_mem_run, rl_mem_tally), so corpus_memory()" \
				"can give every corpus its ASan and memcheck twins (finding 113)."
		fi
		if [ "$_corpus$_mem" != 00 ] && [ "$_listed" = 0 ]; then
			report "$f replays a corpus, and tools/defs.bzl's _CORPUS_RUNNERS does not list it" \
				"c_levels()' audit holds a package's corpus replay to its memory twins" \
				"only for the runners listed there."
		fi
	done
	# _CORPUS_RUN_OPTS, the options that choose no corpus, which the audit
	# leaves out when it matches a plain replay to its twins: a row naming an
	# option no corpus runner takes is a stale one, and one renamed in a runner
	# but not here would let the audit read a corpus option as a judging one.
	_cro=$(sed -n '/^_CORPUS_RUN_OPTS = {/,/^}/p' tools/defs.bzl |
		sed -n 's/^[[:blank:]]*"\(--[a-z-]*\)": [01],.*/\1/p')
	if [ -z "$_cro" ]; then
		report "tools/defs.bzl has no _CORPUS_RUN_OPTS table this can read" \
			"c_levels()' audit matches each plain corpus replay to its memory twins" \
			"by the arguments left when those options are taken out. Keep it one" \
			"'\"--option\": <how many values>,' per line."
	fi
	_crfiles=$(printf '%s\n' "$_cr" | sed -n 's#^[[:blank:]]*"//tools:\([A-Za-z0-9_]*\.sh\)",.*#tools/\1#p')
	for _o in $_cro; do
		_taken=0
		for _r in $_crfiles; do
			[ -f "$_r" ] || continue
			if grep -v '^[[:blank:]]*#' "$_r" | grep -qE -- "(^|[[:blank:]|])$_o([[:blank:]]*[|)])"; then
				_taken=1
				break
			fi
		done
		[ "$_taken" = 1 ] || report \
			"tools/defs.bzl's _CORPUS_RUN_OPTS lists $_o, which no corpus runner takes" \
			"The audit leaves those options out when it matches a plain replay to its" \
			"twins; a row for an option that is gone, or renamed, is one the next" \
			"corpus option can collide with unnoticed."
	done
	for _r in $(printf '%s\n' "$_cr" | sed -n 's#^[[:blank:]]*"//tools:\([A-Za-z0-9_]*\.sh\)",.*#\1#p'); do
		if [ ! -f "tools/$_r" ]; then
			report "tools/defs.bzl's _CORPUS_RUNNERS names tools/$_r, which does not exist" \
				"A row for a runner that is gone lets its name be reused unchecked."
		elif ! awk -F'\t' '{ n = split($4, w, "\037"); for (i = 1; i <= n; i++) if (w[i] == "rl_mem_opt") f = 1 } END { exit !f }' \
			"$(cmds_of "tools/$_r")"; then
			report "tools/defs.bzl's _CORPUS_RUNNERS lists tools/$_r, which takes no memory-checker option" \
				"corpus_memory() hands it --sanitized or --valgrind, and it would refuse" \
				"them. Take them through runner_lib.sh's rl_mem_opt."
		fi
	done
fi

# ---------------------------------------------------------------------------
# N. A corpus runner's gate is tools/runner_lib.sh's rl_gate.
#
# A corpus runner SKIPs while the subject's example is red, and two of them
# ran that example themselves, each its own way. BSQ's ran the program with no
# argument at all, so a correct program read an empty standard input, printed
# "map error", and every BSQ corpus target SKIPped on every correct tree
# without NO_SKIP=1. rl_gate is the one gate: it fails open, says why when the
# differ cannot judge, and runs the program with the arguments it is handed --
# which c_levels()' audit holds to an output test of the package
# (tools/defs.bzl, _gate_problems). So a runner _CORPUS_RUNNERS lists that
# takes --gate-differ calls rl_gate, and never starts the differ it was given
# itself: a command that runs the variable --gate-differ sets is reported.
if [ -f tools/defs.bzl ]; then
	for _r in $(sed -n '/^_CORPUS_RUNNERS = \[/,/^\]/p' tools/defs.bzl |
		sed -n 's#^[[:blank:]]*"//tools:\([A-Za-z0-9_]*\.sh\)",.*#tools/\1#p'); do
		[ -f "$_r" ] || continue
		# The variable --gate-differ's value goes into, from the option loop.
		_gv=$(awk '
			/^[ \t]*#/ { next }
			/^[ \t]*--gate-differ\)/ && match($0, /[A-Za-z_][A-Za-z0-9_]*="\$2"/) {
				print substr($0, RSTART, RLENGTH - 5)
				exit
			}' "$_r")
		[ -n "$_gv" ] || continue
		_gw=$(awk -F'\t' '{ n = split($4, w, "\037"); print w[1] }' "$(cmds_of "$_r")" | sort -u)
		printf '%s\n' "$_gw" | grep -qx 'rl_gate' || report \
			"$_r takes --gate-differ and never calls rl_gate" \
			"Its gate is then a copy of its own: call tools/runner_lib.sh's" \
			"rl_gate NAME \"\$$_gv\" BIN EXPECTED ARG..., with the arguments the" \
			"example's own output test passes."
		_hand=$(awk -F'\t' -v v="$_gv" '
			{
				n = split($4, w, "\037")
				if (w[1] == "rl_gate") next
				for (i = 1; i <= n; i++)
					if (w[i] == "\"$" v "\"" || w[i] == "$" v || w[i] == "\"${" v "}\"") {
						if (i == 1 || (i == 2 && (w[1] == "sh" || w[1] == "exec"))) {
							printf "    %s:%d\n", f, $1
							break
						}
					}
			}' f="$_r" "$(cmds_of "$_r")")
		[ -z "$_hand" ] || report "$_r runs its gate itself" \
			"$_hand" \
			"rl_gate runs it, fails open, and says why when it cannot judge: hand it" \
			"the differ instead of starting it here."
	done
fi

# ---------------------------------------------------------------------------
# N. perf's failing lines are written once, and the docs say the same ones.
#
# The perf layer reports cost and fails only past three lines of this repo's
# own -- a growth exponent, a slowdown and a memory multiple against the
# reference. They were stated in four places that disagreed: the docs said
# "neither perf nor cycles can fail a test" while the runner gated, and its
# banner promised it "only fails when the numbers suggest the code would break
# something" (finding 043). A student who reads "cannot fail" and sees red
# learns to distrust the whole ladder. So the runner's defaults, c_perf's
# defaults and the two docs that state them are held to the same numbers.
f=tools/perf_test.sh
if [ -f "$f" ]; then
	_pg() { sed -n "s/^$1=\"\([0-9.]*\)\"$/\1/p" "$f" | head -n 1; }
	_pe=$(_pg GATE_EXPONENT); _ps=$(_pg GATE_SLOWDOWN); _pm=$(_pg GATE_MEMORY)
	if [ -z "$_pe" ] || [ -z "$_ps" ] || [ -z "$_pm" ]; then
		report "$f does not set GATE_EXPONENT, GATE_SLOWDOWN and GATE_MEMORY as plain numbers" \
			"Each is one line, NAME=\"number\", so this check can hold the docs to it."
	else
		bad=""
		if [ -f tools/defs.bzl ]; then
			for _kv in "gate_exponent:$_pe" "gate_slowdown:$_ps" "gate_memory:$_pm"; do
				grep -qE "^[[:blank:]]+${_kv%%:*} = \"${_kv#*:}\",\$" tools/defs.bzl ||
					bad="$bad
    tools/defs.bzl: c_perf's ${_kv%%:*} default is not \"${_kv#*:}\""
			done
		fi
		if [ -f docs/testing.md ]; then
			_sec=$(awk '/^## The two cost layers/ { on = 1; next } /^## / { on = 0 } on' docs/testing.md)
			for _w in "n^$_pe" "$_ps times" "$_pm times"; do
				printf '%s\n' "$_sec" | grep -qF -- "$_w" ||
					bad="$bad
    docs/testing.md (\"The two cost layers\") does not say \"$_w\""
			done
		fi
		if [ -f docs/reference.md ]; then
			_row=$(grep -E '^\| `perf` \|' docs/reference.md | head -n 1)
			for _w in "$_pe" "${_ps}x" "${_pm}x"; do
				printf '%s\n' "$_row" | grep -qF -- "$_w" ||
					bad="$bad
    docs/reference.md (the perf layer's row) does not say \"$_w\""
			done
		fi
		bad=$(printf '%s\n' "$bad" | sed '/^$/d')
		[ -z "$bad" ] || report \
			"perf's failing lines are not the same everywhere they are stated" \
			"$f fails past n^$_pe, ${_ps}x the reference's time, ${_pm}x its memory;" \
			"$bad" \
			"A layer the docs call informative that turns red teaches a student to" \
			"distrust the ladder. Change the number in every place at once."
	fi
fi

# ---------------------------------------------------------------------------
# N. A page's relative links and anchors resolve.
#
# The pages link one another by path and by heading -- reference.md#run-contract,
# rushes.md#rush-02--numbers-into-words -- and nothing held them: a heading
# reworded, a page moved or a project's README renamed broke a link with no
# test to say so. w5-docs checked its six pages by hand with a throwaway script
# (V40). So every Markdown page a clone carries (text_files: not under
# deliverable/ or generators/, nor in the local dot folders), less HISTORY.md,
# which keeps every path as it was when written: each relative link -- an
# inline [text](target) or a reference definition [name]: target, outside
# code -- names a file or folder that exists, from the page's own folder; and
# an anchor (#a, or page.md#a) names a heading of that page as GitHub makes its
# id -- lower case, every character but a letter, a mark, a number, '_', a
# blank or '-' dropped (an em dash, a section sign, an arrow), each blank a
# '-', a repeated heading's id numbered -1, -2 -- or an <a id="..."> there.
# Read byte by byte (LC_ALL=C), so the lower case reaches Latin-1 and Latin
# Extended-A, and what is dropped is exact through Latin-1 and by block
# above it (slug(), below): a heading in another script is the author's. A
# footnote's definition ([^1]: text) is no link. A link with a scheme
# (https:, mailto:) is no file of this tree, and is not followed.
#
# What this run can see: under `bazel test` the tree is the runfiles, so a page
# links only to files some conventions_srcs declares (the root package lists
# LICENSE for README's link); a link to one it does not is reported as
# missing, and the fix is to declare it there or not to link it.
text_files -name '*.md' ! -path ./HISTORY.md -print | sed 's|^\./||' | sort > "$lex_d/pages"
while IFS= read -r _f; do
	LC_ALL=C awk '
	function slug(t,   s, u, o, code, n, i, j, c) {
		s = t
		sub(/[ \t]+#+[ \t]*$/, "", s)
		sub(/^[ \t]+/, "", s)
		sub(/[ \t]+$/, "", s)
		while (match(s, /!?\[[^]]*\]\([^)]*\)/)) {
			u = substr(s, RSTART, RLENGTH)
			sub(/^!?\[/, "", u)
			sub(/\]\([^)]*\)$/, "", u)
			s = substr(s, 1, RSTART - 1) u substr(s, RSTART + RLENGTH)
		}
		gsub(/<[^>]*>/, "", s)
		# Emphasis is markup, not text: a run of _ at the edge of a word goes,
		# outside a code span (between backticks every byte is text).
		o = ""
		code = 0
		n = length(s)
		for (i = 1; i <= n; i++) {
			c = substr(s, i, 1)
			if (c == "`") code = !code
			if (c != "_" || code) { o = o c; continue }
			j = i
			while (j <= n && substr(s, j, 1) == "_") j++
			if (i > 1 && substr(s, i - 1, 1) ~ /[A-Za-z0-9]/ && j <= n && substr(s, j, 1) ~ /[A-Za-z0-9]/)
				o = o substr(s, i, j - i)
			i = j - 1
		}
		s = o
		# Lower case, a capital of Latin-1 and Latin Extended-A too: under
		# LC_ALL=C tolower() changes ASCII alone.
		o = ""
		n = length(s)
		for (i = 1; i <= n; i++) {
			c = substr(s, i, 2)
			if (c in lc) { o = o lc[c]; i++ }
			else o = o substr(s, i, 1)
		}
		s = tolower(o)
		# What GitHub drops: every character but a letter, a mark, a
		# number of a word (not a superscript or a fraction), a connector
		# (_), a blank or a hyphen. ASCII and Latin-1 exactly; above them,
		# general punctuation (an em dash), currency signs, arrows, the
		# mathematical, technical and drawing blocks through U+2BFF, and
		# supplemental punctuation and the CJK radicals (U+2E00-U+2FFF).
		gsub(/[\001-\037\177]/, "", s)
		gsub(/[]\\!"#$%&()*+,.\/:;<=>?@[^`{|}~]/, "", s)
		gsub(/\047/, "", s)
		gsub(/\302[\200-\251\253-\264\266-\271\273-\277]|\303\227|\303\267/, "", s)
		gsub(/\342\200[\200-\276]|\342\201[\201-\223\225-\257]|\342\202[\240-\277]|\342\203[\200-\217]/, "", s)
		gsub(/\342\206[\220-\277]|\342\207[\200-\277]|\342[\210-\257][\200-\277]|\342[\270-\277][\200-\277]/, "", s)
		gsub(/ /, "-", s)
		return s
	}
	# u8(V): the code point V, below U+0800, as UTF-8.
	function u8(v) { return sprintf("%c%c", 192 + int(v / 64), 128 + v % 64) }
	BEGIN {
		# The capitals of Latin-1 (U+00C0-U+00DE, but the sign at U+00D7)
		# are their small letters less 0x20; Latin Extended-A pairs a
		# capital with the code point after it, even ones first, then odd
		# ones (U+0139-U+0148 and U+0179-U+017E), and U+0178 is U+00FF.
		for (k = 192; k <= 222; k++) if (k != 215) lc[u8(k)] = u8(k + 32)
		for (k = 256; k <= 382; k++) {
			if (k == 304 || k == 305 || k == 312 || k == 329 || k == 376) continue
			if ((k >= 313 && k <= 328) || k >= 377) { if (k % 2 == 1) lc[u8(k)] = u8(k + 1) }
			else if (k % 2 == 0) lc[u8(k)] = u8(k + 1)
		}
		lc[u8(376)] = u8(255)
	}
	function anchor(h,   a) {
		a = h
		if (h in seen) a = h "-" seen[h]
		seen[h]++
		print "A\t" FILENAME "\t" a
	}
	function link(u) {
		sub(/[ \t].*/, "", u)
		gsub(/^<|>$/, "", u)
		if (u != "" && u !~ /^[A-Za-z][A-Za-z0-9+.-]*:/) print "L\t" FILENAME "\t" FNR "\t" u
	}
	FNR == 1 { fence = 0; prev = ""; split("", seen) }
	/^[ \t]*(```|~~~)/ { fence = !fence; prev = ""; next }
	fence { next }
	{
		l = $0
		if (match(l, /^##?#?#?#?#?[ \t]+/))
			anchor(slug(substr(l, RLENGTH + 1)))
		else if (l ~ /^(=+|-+)[ \t]*$/ && prev !~ /^[ \t]*$/ && prev !~ /^[ \t]*[-*+|>]/)
			anchor(slug(prev))
		# An anchor of its own: <a id="..."> or <a name="...">.
		while (match(l, /<a[ \t]+[a-z]+="[^"]+"/)) {
			u = substr(l, RSTART, RLENGTH)
			l = substr(l, RSTART + RLENGTH)
			k = u
			sub(/^<a[ \t]+/, "", k)
			sub(/=.*/, "", k)
			sub(/^[^"]*"/, "", u)
			sub(/"$/, "", u)
			if (k == "name" || k == "id") print "A\t" FILENAME "\t" u
		}
		l = $0
		gsub(/``[^`]*``|`[^`]*`/, "", l)
		# A reference definition; a footnote ([^1]: its text) is none.
		if (match(l, /^[ \t]?[ \t]?[ \t]?\[[^]^][^]]*\]:[ \t]*[^ \t]/)) {
			u = l
			sub(/^[ \t]*\[[^]]+\]:[ \t]*/, "", u)
			link(u)
		}
		while (match(l, /\]\([^) \t]+([ \t]+"[^"]*")?\)/)) {
			u = substr(l, RSTART + 2, RLENGTH - 3)
			l = substr(l, RSTART + RLENGTH)
			link(u)
		}
		prev = $0
	}' "$_f"
done < "$lex_d/pages" > "$lex_d/links"
_lk=$(awk -F'\t' '
	$1 == "A" { has[$2 "#" $3] = 1; next }
	$1 == "L" {
		f = $2; u = $4; p = u; a = ""
		k = index(u, "#")
		if (k > 0) { p = substr(u, 1, k - 1); a = substr(u, k + 1) }
		if (p == "") t = f
		else {
			d = f
			if (d ~ /\//) sub(/\/[^\/]*$/, "", d); else d = ""
			t = (substr(p, 1, 1) == "/" ? p : (d == "" ? p : d "/" p))
			n = split(t, seg, "/"); m = 0; up = 0
			for (i = 1; i <= n; i++) {
				if (seg[i] == "." || seg[i] == "") continue
				if (seg[i] == "..") { if (m > 0) m--; else up = 1; continue }
				out[++m] = seg[i]
			}
			t = ""
			for (i = 1; i <= m; i++) t = t (i > 1 ? "/" : "") out[i]
			if (up || substr(p, 1, 1) == "/") t = "/"
		}
		print f "\t" $3 "\t" u "\t" t "\t" a
	}' "$lex_d/links" | while IFS='	' read -r _f _n _u _t _a; do
	if [ "$_t" = / ] || { [ ! -e "$_t" ] && [ -n "$_t" ]; }; then
		printf '    %s:%s: %s (no such file or folder)\n' "$_f" "$_n" "$_u"
	elif [ -n "$_a" ]; then
		case "$_t" in
			*.md) grep -qxF "A	$_t	$_a" "$lex_d/links" ||
				printf '    %s:%s: %s (no heading of %s has that id)\n' "$_f" "$_n" "$_u" "$_t" ;;
		esac
	fi
done)
[ -z "$_lk" ] || report "a page links to a file, folder or heading that is not there" \
	"$_lk" \
	"A relative link is read from the page's own folder; an anchor is the id" \
	"GitHub gives a heading: lower case, punctuation dropped, a blank a '-'." \
	"Under bazel test the tree is what the conventions_srcs declare, so a page" \
	"links only to a file one of them lists."
rm -f "$lex_d/pages" "$lex_d/links"

# ---------------------------------------------------------------------------
# N. Every lead of TODO.md's TO VERIFY list has a number of its own.
#
# AGENTS.md section 5 sends every agent that notices something to that list,
# and a review settles each lead by its number. Two merges that each added a
# draft left V4 and V5 written twice, worded slightly differently, and a
# review that settled "V4" could not say which one it had read. The file is
# the maintainer's, and a fresh clone has none until its first lead: nothing
# to check then.
if [ -f TODO.md ]; then
	_tv=$(sed -n 's/^\*\*V\([0-9][0-9]*\)\. .*/\1/p' TODO.md | sort -n |
		awk 'seen[$0]++ == 1 { print "    V" $0 }')
	[ -z "$_tv" ] || report \
		"TODO.md's TO VERIFY list gives two leads one number" \
		"$_tv" \
		"A lead is settled by its number, so a second one under it is either a" \
		"stale draft of the first (keep the later wording) or a new lead that" \
		"needs the next free number."
fi
# ...and no number HISTORY.md has settled (V32). Two branches cut from one
# commit each gave a V27 and a V28 to different leads: one branch's were open
# in TODO.md, the other's fixed on its branch and written only into
# HISTORY.md's "TO VERIFY leads, settled", and the merge passed this rule,
# which read TODO.md alone. A settled line opens "- **V7, what it was",
# "- **V30 (new; ...), what it was" or "- **V1 and V6 (review): what was
# left"; its numbers are the ones before its first comma, colon, bracket or
# dash, and a number settled once is taken: a lead it does not settle, or a
# lead a review reopens, takes the next number free in both files. A review's
# fix of a settled lead is its "VN (review)" line there, not a lead here.
if [ -f TODO.md ] && [ -f HISTORY.md ]; then
	_tvs=$(awk '/^## / { on = ($0 ~ /^## TO VERIFY leads, settled/); next }
		on && /^- \*\*V[0-9]/ {
			h = substr($0, 5)
			sub(/(,|:| \(| --|\*\*).*/, "", h)
			while (match(h, /V[0-9]+/)) {
				print substr(h, RSTART + 1, RLENGTH - 1)
				h = substr(h, RSTART + RLENGTH)
			}
		}' HISTORY.md | sort -n -u)
	_tvb=$(sed -n 's/^\*\*V\([0-9][0-9]*\)\. .*/\1/p' TODO.md | sort -n -u |
		awk -v s="$_tvs" 'BEGIN { n = split(s, a, "\n"); for (i = 1; i <= n; i++) set[a[i]] = 1 }
			$0 in set { print "    V" $0 }')
	[ -z "$_tvb" ] || report \
		"a TO VERIFY lead's number is open in TODO.md and settled in HISTORY.md" \
		"$_tvb" \
		"HISTORY.md's \"TO VERIFY leads, settled\" has a line for each, so the" \
		"number is taken: give the open lead the next number free in both files" \
		"(a review's fix of a settled lead is a \"VN (review)\" line there)."
fi

# ---------------------------------------------------------------------------
# N. Every work package in TODO.md says where it stands.
#
# Section 23's plan lists its packages one line each ("- WP-NN [P2 M] ...").
# Wave 4 closed forty-nine of them, and for a day the list said nothing of
# it: a reader of the plan saw them all open, and the only record of what was
# done sat in a file outside the repository (w5-docs). So each package line
# ends by saying where it stands -- "[DONE ...]", "[PARTLY DONE ...: what is
# left]", or "[OPEN ...]" -- and a wave that changes one changes its line.
#
# And a package with something left is not DONE. Three lines once read
# "[DONE in wave 5; left: ...]" (WP-83, whose own text says to check the
# campus facts "before calling the fixes done", and WP-88), and a reader who
# counts the DONE markers counts them closed. So "left" inside a "[DONE"
# marker is reported too: that package is PARTLY DONE.
if [ -f TODO.md ]; then
	_wp=$(awk '/^- WP-[0-9]+ \[P[0-9]/ && !/\[(PARTLY DONE|DONE|OPEN)/ {
		w = $2; printf "    TODO.md:%d: %s\n", FNR, w }' TODO.md)
	[ -z "$_wp" ] || report \
		"a work package in TODO.md does not say where it stands" \
		"$_wp" \
		"End its line with [DONE in wave N], [PARTLY DONE: what is left] or" \
		"[OPEN], so the plan says what the waves did without a second record."
	# The "[DONE" marker's own text, up to its closing bracket, and a
	# "left" in it as a word ("left:", "Left:", "; left ").
	_wpl=$(awk '/^- WP-[0-9]+ \[P[0-9]/ {
		k = index($0, "[DONE"); if (k == 0) next
		m = substr($0, k); e = index(m, "]"); if (e > 0) m = substr(m, 1, e)
		if (tolower(m) ~ /(^|[^a-z])left([^a-z]|$)/) printf "    TODO.md:%d: %s\n", FNR, $2 }' TODO.md)
	[ -z "$_wpl" ] || report \
		"a work package in TODO.md is marked DONE with something left" \
		"$_wpl" \
		"A package with work left is [PARTLY DONE in wave N: ... Left: what is" \
		"left], so the DONE markers count only the packages that are closed."
fi

# ---------------------------------------------------------------------------
# N. TODO.md's retro-audit has a row for every item of docs/new-project.md.
#
# The retro-audit (TODO.md section 23) holds each rule of the new-project
# checklist against every project, so the projects written before a rule are
# checked for it too, and each gap is a follow-up (WP-74's decision). An item
# added to the checklist without its row is a rule nobody held the old
# projects to. So once TODO.md has the table -- its rows "| N | item | ..." --
# its numbers are the checklist's numbers, no more and no fewer.
#
# The table is read from the "- **Retro-audit" bullet to the first line that
# is neither indented, blank nor a row of a table: in TODO.md that is the
# "**Packages**" line after the bullet, not another bullet, and a scan that
# stopped only at the next "- **" ran to the end of the file, counting any
# later table's "| N |" rows as the audit's.
if [ -f TODO.md ] && [ -f docs/new-project.md ] && grep -q '^- \*\*Retro-audit' TODO.md; then
	_ra_items=$(sed -n 's/^\([0-9][0-9]*\)\. .*/\1/p' docs/new-project.md | sort -n -u)
	_ra_rows=$(awk '/^- \*\*Retro-audit/ { on = 1; next }
		on && /^[^[:blank:]|]/ { exit }
		on && /^[[:blank:]]*\| [0-9]+ \|/ { n = $0; sub(/^[[:blank:]]*\| /, "", n); sub(/ .*/, "", n); print n }' TODO.md | sort -n -u)
	_ra=$(printf '%s\n' "$_ra_items" | while IFS= read -r _i; do
		[ -n "$_i" ] || continue
		printf '%s\n' "$_ra_rows" | grep -qx "$_i" || printf '    item %s of docs/new-project.md has no row\n' "$_i"
	done
	printf '%s\n' "$_ra_rows" | while IFS= read -r _i; do
		[ -n "$_i" ] || continue
		printf '%s\n' "$_ra_items" | grep -qx "$_i" || printf '    row %s names no item of docs/new-project.md\n' "$_i"
	done)
	[ -z "$_ra" ] || report \
		"TODO.md's retro-audit and docs/new-project.md disagree" \
		"$_ra" \
		"Each checklist item is held against every project in the table, one row" \
		"per item, and a gap becomes a follow-up under it."
fi

# ---------------------------------------------------------------------------
# N. Every project folder has a row in tools/submit.sh's REMOTES table.
#
# The table is the list of modules (the guard at the top of this script): a
# rule that walks $MODULES walks the table, //tools:submit pushes the table,
# and the test of this script sees only the files of the modules
# tools/tests/BUILD.bazel's _MODULES names, which the guard holds to the
# table. A project folder left out of it is checked by none of those, and
# nothing said so: the rule that the table holds no URL passes on a table
# that is short. So every folder of a course folder (the course folders the
# table's modules live in, and cursus/) that holds a BUILD.bazel -- one
# folder per project, AGENTS.md section 4 -- is a module of the table.
#
# Only a run that sees the files nobody declared can find one: `bazel run
# //tools:conventions`, on the workspace. The test sees the registered
# modules' files alone, so for it this rule is quiet by construction.
PROJECT_DIRS=$({
	for _m in $MODULES; do printf '%s\n' "$_m"; done
	for _c in $COURSE_DIRS cursus; do
		[ -d "$_c" ] || continue
		for _b in "$_c"/*/BUILD.bazel; do
			[ -e "$_b" ] && printf '%s\n' "${_b%/BUILD.bazel}"
		done
	done
} | sort -u)
_unreg=""
for _p in $PROJECT_DIRS; do
	printf '%s\n' "$MODULES" | grep -qxF "$_p" && continue
	_unreg="$_unreg
    $_p"
done
_unreg=$(printf '%s\n' "$_unreg" | sed '/^$/d')
[ -z "$_unreg" ] || report \
	"a project folder has no row in tools/submit.sh's REMOTES table" \
	"$_unreg" \
	"Add a row <path>=REPLACE_ME to the REMOTES table in tools/submit.sh (the" \
	"URL goes in .submit-remotes), and the module's label to _MODULES in" \
	"tools/tests/BUILD.bazel, so every check, the test and //tools:submit see it."

# ---------------------------------------------------------------------------
# N. A group project, and every Common Core project, has a page of its own.
#
# BSQ was "the same shape as a rush", and nothing a student reads said how its
# tests are built, how a failing map is run again, or which questions its
# subject leaves open: docs/rushes.md spoke to the rushes alone, and the open
# questions sat in BUILD comments and the oracle's header (findings 175, 178).
# A project's own explanation lives beside its BUILD file, in a README.md, as
# Piscine Reloaded's does (docs/design.md: what explains one thing lives with
# it), and a shared page keeps only what is shared (WP-74's decision). So a
# module whose subject() says group = True, and every module under cursus/,
# has that page -- or, for a rush, which predates the rule, the section of
# docs/rushes.md headed by its name: the folder's name less its course's
# "c-piscine-" ("## rush-00 ..."). docs/new-project.md says what the page
# holds. A Piscine module that is neither keeps the shared pages.
#
# WHICH PROJECTS. Every folder of a course folder that holds a BUILD.bazel
# (PROJECT_DIRS, which the rule before this one lists), not only the modules of
# the REMOTES table: walking the table alone, a cursus project nobody had
# registered yet was reported by nothing, the case this rule exists for.
_pg=""
for _m in $PROJECT_DIRS; do
	case "$_m" in
		cursus/*) ;;
		*)
			awk '
				/^subject\(/ { on = 1 }
				on && /^[[:blank:]]*group[[:blank:]]*=[[:blank:]]*True/ { found = 1 }
				on && /^\)/ { exit }
				END { exit !found }' "$_m/BUILD.bazel" || continue ;;
	esac
	[ -f "$_m/README.md" ] && continue
	_pgs=${_m##*/}
	_pgs=${_pgs#c-piscine-}
	[ -f docs/rushes.md ] && grep -q "^## $_pgs " docs/rushes.md && continue
	[ -z "$_pg" ] || _pg="$_pg
"
	_pg="$_pg    $_m"
done
[ -z "$_pg" ] || report \
	"a group project, or a Common Core one, has no page of its own" \
	"$_pg" \
	"Write a README.md beside its BUILD.bazel: what is turned in and where, how" \
	"its tests are built, its corpora and how to replay a failing case, its" \
	"settings, and each question its subject leaves open with what basic checks" \
	"(docs/new-project.md; c-piscine/c-piscine-bsq/README.md is the model)."

# ---------------------------------------------------------------------------
# N. docs/new-project.md says what holds each item, and what it names exists.
#
# The checklist for a new project is where the lessons of the student-test
# run are carried to the next one (WP-74), and a checklist rots two ways: an
# item nobody can tell is enforced, and an item whose check was renamed or
# removed while the page still promised it. So each numbered item says
# "Checked by:" or "(unchecked)"; every load-time check it names in
# backticks (a `..._problem` or `..._problems`) is a function tools/*.bzl
# defines; every private table it names (`_RAISED`, `_STANDIN_RUNNERS`) is
# one tools/*.bzl assigns; and every rule of this script it quotes,
# `//tools:conventions` ("..."), opens the heading of a rule here (the line
# after the rule's row of dashes, less its "N. ": what the quote must start;
# a few rules are headed in capitals and no number, "A CR IN A FILE GIT
# WOULD REWRITE", and are quoted so). The other way round, every rule here
# that holds a runner to tools/runner_lib.sh is quoted by some item, so the
# page names all of them to the author of a new runner. And AGENTS.md
# sends an agent there before it adds a project or a layer (WP-74's
# decision), so the page is read, not only kept.
if [ -f docs/new-project.md ]; then
	# One line per item, its lines joined so a name or a quote wrapped across
	# a line end is read whole: "MISS <line> <number>" for an item that says
	# neither, "CHECK <text>" with what follows its "Checked by:" -- the one
	# place a quote is a rule's heading, not a subject's words.
	_npi=$(awk '
		function done_item() {
			if (num == "") return
			k = index(item, "Checked by")
			if (k > 0) print "CHECK " substr(item, k)
			else if (item !~ /\(unchecked\)/) print "MISS " at " " num
			num = ""; item = ""
		}
		/^[0-9]+\. / { done_item(); num = $1; sub(/\.$/, "", num); at = FNR; item = $0; next }
		num != "" && /^[[:blank:]]+[^[:blank:]]/ { l = $0; sub(/^[[:blank:]]+/, "", l); item = item " " l; next }
		{ done_item() }
		END { done_item() }' docs/new-project.md)
	_np=$(printf '%s\n' "$_npi" | sed -n 's/^MISS \([0-9]*\) \(.*\)/    docs\/new-project.md:\1: item \2 says neither "Checked by:" nor "(unchecked)"/p')
	_npc=$(printf '%s\n' "$_npi" | sed -n 's/^CHECK //p')
	_npdefs=$(cat tools/*.bzl 2> /dev/null)
	# This script's own headings: $0, which is this file under `bazel run`
	# and under the sh_test alike (named after the test there), found from
	# CONV_HOME, since a relative $0 means nothing once the cd above is done.
	_nprules=$(awk 'p ~ /^# ----------/ && /^# / { h = substr($0, 3); sub(/^(N|[0-9]+)\. /, "", h); print h }
		{ p = $0 }' "$CONV_HOME/${0##*/}")
	for _n in $(printf '%s\n' "$_npc" | grep -oE '`_?[a-z][a-z0-9_]*_problems?`' | tr -d '`' | sort -u); do
		printf '%s\n' "$_npdefs" | grep -qE "^def $_n\(" ||
			_np="$_np
    \`$_n\` is no function tools/*.bzl defines"
	done
	for _n in $(printf '%s\n' "$_npc" | grep -oE '`_[A-Z][A-Z0-9_]*`' | tr -d '`' | sort -u); do
		printf '%s\n' "$_npdefs" | grep -qE "^${_n}[[:blank:]]*=" ||
			_np="$_np
    \`$_n\` is no table tools/*.bzl assigns"
	done
	_npq=$(printf '%s\n' "$_npc" | grep -oE '\("[^"]+"\)' | sed 's/^("//; s/")$//')
	_oldifs=$IFS
	IFS='
'
	for _q in $_npq; do
		IFS=$_oldifs
		printf '%s\n' "$_nprules" | awk -v q="$_q" 'index($0, q) == 1 { f = 1 } END { exit !f }' ||
			_np="$_np
    (\"$_q\") opens the heading of no rule of tools/conventions.sh"
		IFS='
'
	done
	IFS=$_oldifs
	# And the other way round, for the rules that hold a runner to
	# tools/runner_lib.sh (a heading naming the file or one of its rl_
	# helpers): each is quoted by some item, so the checklist a new runner's
	# author reads names every one. Two of them, rl_udiff's and rl_sanitized's,
	# were added to this script and not to the page (the review of V51/V50).
	_nplib=$(printf '%s\n' "$_nprules" | grep -E 'tools/runner_lib\.sh|(^|[^A-Za-z0-9_])rl_[a-z]')
	_oldifs=$IFS
	IFS='
'
	for _r in $_nplib; do
		IFS=$_oldifs
		printf '%s\n' "$_npq" | awk -v r="$_r" 'index(r, $0) == 1 { f = 1 } END { exit !f }' ||
			_np="$_np
    rule \"$_r\" holds a runner to tools/runner_lib.sh, and no item quotes it"
		IFS='
'
	done
	IFS=$_oldifs
	[ -f AGENTS.md ] && grep -qF 'docs/new-project.md' AGENTS.md ||
		_np="$_np
    AGENTS.md never names docs/new-project.md"
	_np=$(printf '%s\n' "$_np" | sed '/^$/d')
	[ -z "$_np" ] || report \
		"docs/new-project.md promises a check it cannot point to" \
		"$_np" \
		"Each item ends with \"Checked by:\" and the check that fails when the item" \
		"is broken, or \"(unchecked)\". A check it names is a load-time function" \
		"of tools/*.bzl, a table assigned there, or a rule of this script quoted" \
		"by the start of its heading, //tools:conventions (\"...\"); rename them" \
		"together. A rule holding a runner to tools/runner_lib.sh is quoted by" \
		"an item, item 66 when no other fits. AGENTS.md section 6 sends an agent" \
		"adding a project there."
fi

# ---------------------------------------------------------------------------
# N. What AGENTS.md names, the harness has; what the harness exempts,
#    AGENTS.md names.
#
# The rules AGENTS.md gives name their machinery the way docs/new-project.md
# does (section 6: `_RAISED`, `_MANUAL`), and an agent reads them as
# promises: a table or a load-time check it names is one tools/*.bzl has, or
# the sentence is a rule nothing enforces that reads as one something does.
if [ -f AGENTS.md ]; then
	_agdefs=$(cat tools/*.bzl 2> /dev/null)
	_ag=""
	_agtext=$(cat AGENTS.md)
	for _n in $(printf '%s\n' "$_agtext" | grep -oE '`_?[a-z][a-z0-9_]*_problems?`' | tr -d '`' | sort -u); do
		printf '%s\n' "$_agdefs" | grep -qE "^def $_n\(" ||
			_ag="$_ag
    \`$_n\` is no function tools/*.bzl defines"
	done
	for _n in $(printf '%s\n' "$_agtext" | grep -oE '`_[A-Z][A-Z0-9_]*`' | tr -d '`' | sort -u); do
		printf '%s\n' "$_agdefs" | grep -qE "^${_n}[[:blank:]]*=" ||
			_ag="$_ag
    \`$_n\` is no table tools/*.bzl assigns"
	done
	_ag=$(printf '%s\n' "$_ag" | sed '/^$/d')
	[ -z "$_ag" ] || report \
		"AGENTS.md names machinery the harness does not have" \
		"$_ag" \
		"A rule that names the table or the load-time check holding it is read" \
		"as enforced. Rename the two together, or say the rule is the reviewer's."
	# And the other way: an exception this script makes to AGENTS.md's rules
	# is one AGENTS.md names. A file outside the zone that defines a turned-in
	# function and does its work (TURNIN_FN_ALLOW) is allowed once, Reloaded's
	# ft_putchar.c, and AGENTS.md section 4 names it as the one exception, not
	# a pattern: a second entry added here alone would make that sentence
	# false and the exception a pattern nobody ruled on. Naming it there is
	# changing AGENTS.md, which is the owner's to rule on.
	_agx=""
	for _x in $TURNIN_FN_ALLOW; do
		printf '%s\n' "$_agtext" | grep -qF "\`${_x##*/}\`" ||
			_agx="$_agx
    $_x"
	done
	_agx=$(printf '%s\n' "$_agx" | sed '/^$/d')
	[ -z "$_agx" ] || report \
		"a file TURNIN_FN_ALLOW exempts is not named in AGENTS.md" \
		"$_agx" \
		"AGENTS.md section 4 names the one file outside the zone allowed to define" \
		"a turned-in function that does its work. Another is the owner's to allow:" \
		"name it there, with why, or make the file a stub."
fi


# ---------------------------------------------------------------------------
# EVERY RUN TARGET IS A 42 COMMAND, OR SAYS WHY NOT.
#
# `42 help` is how a student finds what this harness can do, and it is
# printed from tools/fortytwo/commands.tsv. A run target added to a BUILD
# file without a row there is an action nobody finds; a row naming a target
# since renamed is a command that fails the day someone types it. So, both
# ways:
#   * every sh_binary and py_binary of a BUILD file -- tools' own, and a
#     project's, as a shell project's :generate -- is named in some row's
#     RUNS: //PKG:NAME, or //<project>:NAME for a target of a project. A
#     target no command may run gets an `internal` row whose text says why;
#   * every label a row names is declared: //PKG:NAME by a `name = "NAME"` in
#     PKG/BUILD.bazel, //PKG/... by that BUILD file being there, and
#     //<project>:NAME by some project's BUILD file. `sh FILE` names a file
#     that is there, and `bazel CMD` is Bazel's own command. Nothing else
#     goes in RUNS.
# A workspace with neither tools/42.sh nor the registry (a selftest's toy)
# has nothing to hold; one with 42 and no registry is reported.
if [ -f tools/42.sh ] || [ -f tools/fortytwo/commands.tsv ]; then
	if [ ! -f tools/fortytwo/commands.tsv ]; then
		report "tools/fortytwo/commands.tsv is missing" \
			"It is 42's registry: \`42 help\` is printed from it, and every run" \
			"target of a BUILD file is named in it."
	else
		# PKG <tab> NAME <tab> BIN: every name = "NAME" of a call, BIN 1 for
		# a sh_binary or py_binary. PKG is the BUILD file's folder.
		printf '%s\n' "$_bs" | awk -F'\t' '
			$1 == "S" && $6 == "name" && $7 != "" {
				d = $2
				sub(/\/?BUILD\.bazel$/, "", d)
				print d "\t" $4 "\t" ($7 == "sh_binary" || $7 == "py_binary")
			}' | sort -u > "$lex_d/cmd_names"
		# shellcheck disable=SC2086  # one word per module; none has a space
		printf '%s\n' $MODULES > "$lex_d/cmd_modules"
		_cmd_bad=$(awk -F'\t' '
			FILENAME == ARGV[1] { declared[$1 ":" $2] = 1; if ($3) bin[$1 ":" $2] = 1; tname[$2] = tname[$2] " " $1; next }
			FILENAME == ARGV[2] { project[$0] = 1; next }
			/^#/ || !NF { next }
			NF != 5 { print "    line " FNR " has " NF " columns, not 5: " $0; next }
			{
				n = split($3, w, " ")
				for (i = 1; i <= n; i++) {
					if (w[i] == "bazel" && i < n) { i++; continue }
					if (w[i] == "sh" && i < n) {
						i++
						if ((getline junk < w[i]) < 0) print "    line " FNR " runs sh " w[i] ", which is not there"
						close(w[i])
						continue
					}
					if (w[i] !~ /^\/\//) { print "    line " FNR ": \"" w[i] "\" is no label, no `bazel CMD` and no `sh FILE`"; continue }
					l = substr(w[i], 3)
					if (l ~ /\/\.\.\.$/) {
						pk = substr(l, 1, length(l) - 4)
						if ((getline junk < (pk "/BUILD.bazel")) < 0) print "    line " FNR " names " w[i] ", and " pk "/BUILD.bazel is not there"
						close(pk "/BUILD.bazel")
						continue
					}
					c = index(l, ":")
					if (c == 0) { print "    line " FNR " names " w[i] ", which names no target (//PKG:NAME)"; continue }
					pk = substr(l, 1, c - 1); tgt = substr(l, c + 1)
					if (pk == "<project>") {
						ok = 0
						m = split(tname[tgt], ps, " ")
						for (j = 1; j <= m; j++) if (ps[j] in project) { ok = 1; covered["<project>:" tgt] = 1 }
						if (!ok) print "    line " FNR " names " w[i] ", and no project declares :" tgt
						continue
					}
					if (!((pk ":" tgt) in declared)) print "    line " FNR " names " w[i] ", which " pk "/BUILD.bazel does not declare"
					covered[pk ":" tgt] = 1
				}
			}
			END {
				for (k in bin) {
					c = index(k, ":"); pk = substr(k, 1, c - 1); tgt = substr(k, c + 1)
					if (k in covered) continue
					if ((pk in project) && (("<project>:" tgt) in covered)) continue
					print "    //" k " is a run target no row names"
				}
			}' "$lex_d/cmd_names" "$lex_d/cmd_modules" tools/fortytwo/commands.tsv | sort)
		[ -z "$_cmd_bad" ] || report \
			"tools/fortytwo/commands.tsv and the BUILD files disagree" \
			"$_cmd_bad" \
			"A run target is an action, and \`42 help\` is how a student finds one:" \
			"give it a row (an internal one says why no command runs it), and name" \
			"in a row only what a BUILD file declares."
	fi
fi

# ---------------------------------------------------------------------------
# 42 NEVER PASSES BAZEL A FLAG THAT COSTS THE STUDENT THEIR CACHE OR AN ANSWER.
#
# `42` runs Bazel for someone who cannot tell a slow run from a broken one, so
# a few words never appear in its code, each for a measured reason:
#   --output_user_root   moves all of Bazel's state off the root setup.sh and
#                        tools/bazel chose, and the next run starts cold (about
#                        700 MB of downloads for C 00 alone);
#   --watchfs            has the server watch files, which is undefined on 9p
#                        and network file systems, where checkouts live;
#   --action_env         discards the analysis cache whenever its value moves;
#   --notrim_test_configuration
#                        makes the --test_env that `42 clues` sets discard the
#                        analysis cache, which trimming (Bazel 9's default)
#                        keeps;
#   coverage             an interrupted coverage run can leave the server
#                        holding its command lock in Bazel 9.2.0, and 42
#                        interrupts runs (bazelbuild/bazel#30435);
#   query --output=build, xml, proto, jsonproto or streamed_jsonproto
#                        print a rule's attribute values, and a test's can name
#                        the reference it compares with: `--show_starlark`
#                        reads locations and labels only.
# Matched as a whole quoted word ("--watchfs", '--action_env=X') in
# tools/fortytwo/*.py (not its tests, which name them to prove they are
# absent), in tools/42.sh's code, and in the RUNS of a commands.tsv row.
# Comments and docstrings may name them, even first, as in """--watchfs is
# ...""". A flag built from pieces is beyond a grep; starlark.py's one built
# --output is held by its own test.
if [ -f tools/42.sh ]; then
	_ft_flags='--(output_user_root|watchfs|action_env|notrim_test_configuration)'
	_ft_out='--output=(build|xml|proto|jsonproto|streamed_jsonproto)'
	_ft_bad=$(
		for f in tools/fortytwo/*.py; do
			[ -f "$f" ] || continue
			awk -v F="$f" -v q="'" -v fl="$_ft_flags" -v ou="$_ft_out" '
				/^[[:blank:]]*#/ { next }
				{
					o = "[\"" q "]"
					if (match($0, o fl "[\"" q "=]") || match($0, o ou o) || match($0, o "coverage" o))
						print "    " F ":" NR ": " substr($0, RSTART, RLENGTH)
				}' "$f"
		done
		awk -v fl="$_ft_flags" -v ou="$_ft_out" '
			/^[[:blank:]]*#/ { next }
			$0 ~ fl || $0 ~ ou || $0 ~ /(^|[[:blank:]])coverage([[:blank:]]|$)/ {
				print "    tools/42.sh:" NR ": " $0
			}' tools/42.sh
		if [ -f tools/fortytwo/commands.tsv ]; then
			awk -F '\t' -v fl="$_ft_flags" -v ou="$_ft_out" '
				/^#/ { next }
				$3 ~ fl || $3 ~ ou || $3 ~ /(^|[[:blank:]])bazel[[:blank:]]+coverage([[:blank:]]|$)/ {
					print "    tools/fortytwo/commands.tsv:" NR ": " $3
				}' tools/fortytwo/commands.tsv
		fi
	)
	[ -z "$_ft_bad" ] || report \
		"42 passes Bazel a flag it must never pass" \
		"$_ft_bad" \
		"Each one costs a student their cache, their time or an answer: the" \
		"comment above this rule in tools/conventions.sh says which and why."
fi

# ---------------------------------------------------------------------------
# N. A page that says to re-run on a still tree says how.
#
# A run that saw a file change while it ran can leave a test result cached
# for the version it read, and a plain re-run on a still tree serves it
# again: compile layers showed PASSED over a file that does not compile, in
# 15 of 24 trials (V111). So a paragraph of AGENTS.md, README.md or docs/
# that tells someone to re-run on a still tree names --nocache_test_results
# in the same paragraph. A paragraph is the lines between blank lines, and a
# list item starts one of its own; the phrase may wrap.
_still=""
for _sf in AGENTS.md README.md docs/*.md; do
	[ -f "$_sf" ] || continue
	_still="$_still
$(awk -v f="$_sf" '
		function flush() {
			if (tolower(p) ~ /still[[:space:]]+tree/ && p !~ /--nocache_test_results/)
				printf "    %s:%d\n", f, start
			p = ""; start = 0
		}
		/^[[:space:]]*$/ { flush(); next }
		/^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]/ { flush() }
		{ if (!start) start = NR; p = p " " $0 }
		END { flush() }' "$_sf")"
done
_still=$(printf '%s\n' "$_still" | sed '/^$/d')
[ -z "$_still" ] || report \
	"a page says to re-run on a still tree, and not with --nocache_test_results" \
	"$_still" \
	"A run that saw a file change can leave a result cached for the version" \
	"it read, and a plain re-run on a still tree serves it again. Name" \
	"--nocache_test_results in that paragraph, and the recipe for a test" \
	"program that still behaves like the old file: bazel shutdown, then" \
	"--nocache_test_results --use_action_cache=false."

echo ""
if [ "$FAILS" -eq 0 ]; then
	echo "conventions: OK — every check passed."
	exit 0
fi
echo "conventions: FAIL — $FAILS convention(s) broken."
echo ""
echo "  These are not cosmetic. The harness is what a student reads to learn how"
echo "  tests are written here, so a rule followed everywhere except one file"
echo "  does not teach a rule -- it teaches that the rule is optional."
exit 1
