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
require awk basename cat comm cut dirname find grep head mktemp rm sed sort tail tr

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

# Repo-wide, like stub_check.sh: it has to SEE every runner
# and every test main, and a sandboxed sh_test only sees what is in its `data`.
# Listing ~140 files there -- and updating that list whenever a module gains a
# test -- would be a convention nobody keeps, which is the failure this script
# exists to prevent. So it is a sh_binary run from the workspace root.
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

WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$WS" || { echo "conventions.sh: cannot enter '$WS'" >&2; exit 2; }

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
	for line in "$@"; do
		[ -n "$line" ] || continue
		echo "        $line"
	done
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
	grep -v '^[ \t]*#' "$1" | grep -qE 'while \[ \$# -gt 0 \]'
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
if [ -n "$SHELLCHECK" ] && [ -x "$SHELLCHECK" ]; then
	sc=$("$SHELLCHECK" -f gcc -S warning tools/*.sh tools/tests/*.sh 2> /dev/null || true)
	# Built with `set --` rather than an unquoted command substitution: the
	# latter is SC2046, and a lint this script cannot pass itself is not a lint.
	set --
	for wf in $(find . \
		-path './bazel-*' -prune -o \
		-path '*/deliverable/*' -prune -o \
		-path ./tools -prune -o \
		-name '*.sh' -print 2> /dev/null | sort); do
		set -- "$@" "$wf"
	done
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
if [ -n "$BUILDIFIER" ] && [ -x "$BUILDIFIER" ]; then
	bf=$("$BUILDIFIER" --lint=warn --mode=check -r . 2>&1 |
		grep -v '^bazel-' |
		grep -E '^\S+:[0-9]+:' || true)
	if [ -n "$bf" ]; then
		report "buildifier reports semantic warnings" "$bf"
	fi
else
	report "no pinned buildifier was supplied" \
		"Its version decides which lint warnings exist, so a host copy makes" \
		"the result depend on the machine. Pass --buildifier" \
		"\$(location @buildifier_prebuilt//:buildifier)."
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
# testing for it. c-08 is exempt: those mains are the SUBJECT's own code,
# transcribed, and the exercise is to make them compile.
for f in $(find c-piscine-*/tests -name 'test_*.c' 2> /dev/null | sort); do
	case "$f" in
		c-piscine-c-08/*) continue ;;
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
		/^[ \t]*exit 0[ \t]*$/ || /;[ \t]*exit 0[ \t]*(;;)?[ \t]*$/ {
			if (skip && NR - skip <= 6 && (!guard || NR - guard > 30))
				printf "%d: this SKIP exits 0 with no NO_SKIP guard above it\n", NR
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
for f in $(find . \
	-path './bazel-*' -prune -o \
	-path '*/deliverable/*' -prune -o \
	-name '*.sh' -print 2> /dev/null | sort); do
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
done

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
for f in tools/*.sh tools/tests/*.sh; do
	grep -q '^# shellcheck shell=' "$f" && continue
	grep -q '^# conventions: no-require' "$f" && continue
	optional=$(sed -n 's/^# conventions: optional \([a-z0-9_.-]*\).*/\1/p' "$f" |
		sort -u | tr '\n' ' ')
	used=$(awk -v optional="$optional" '
		BEGIN {
			split("grep sed awk sort tr wc cut head tail od cmp diff find " \
			      "xargs basename dirname mktemp date chmod cp mv rm mkdir " \
			      "ln readlink env comm cc git make md5sum nm perl python3 " \
			      "sha256sum shellcheck tar timeout valgrind cat touch tee " \
			      "uniq sleep id uname expr seq stat rmdir paste nl", v, " ")
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
			if (match(line, /^[ \t]*trap[ \t]+\047/)) {
				sub(/^[ \t]*trap[ \t]+\047/, "", line)
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
				w = s; sub(/[ \t].*/, "", w)
				if ((w in vocab) && !(w in exempt)) seen[w] = 1
			}
		}
		END { for (w in seen) print w }' "$f" | sort | tr '\n' ' ')
	declared=$(grep -m1 '^require ' "$f" | cut -d' ' -f2- | tr ' ' '\n' |
		grep -v '^$' | sort | tr '\n' ' ')
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
# N. Every clue label names a case that actually exists.
#
# A clues.tsv row is `<hint><TAB><case label><TAB><case label>...`, and the hint
# fires when one of those cases fails. A label that matches no line of the
# exercise's expected.txt is therefore a gate that can never open -- the hint is
# still reachable through its OTHER labels, so nothing goes red and nobody finds
# out. c-02 ex09 carried one for as long as the file has existed: a row about
# word boundaries listed "punctuation/+ as separators", a description of a case
# rather than the label of one, while the two cases that actually exercise
# punctuation (the subject transcripts) went unlisted.
#
# One dead label in 130 files is the kind of thing only a machine finds, and the
# cost of not finding it is a hint that does not appear when it is needed.
for c in c-piscine-*/tests/ex*/clues.tsv; do
	[ -f "$c" ] || continue
	e="${c%/clues.tsv}/expected.txt"
	[ -f "$e" ] || continue
	dead=$(awk -F'\t' -v e="$e" '
		BEGIN { while ((getline l < e) > 0) { split(l, a, "\t"); lab[a[1]] = 1 } }
		/^[ \t]*#/ || /^[ \t]*$/ { next }
		{
			for (i = 2; i <= NF; i++)
				if ($i != "" && !($i in lab))
					printf "    line %d: %s\n", NR, $i
		}' "$c")
	[ -z "$dead" ] || report \
		"$c names a case that does not exist" \
		"$dead" \
		"A clue fires when one of the cases it lists fails. A label matching no" \
		"line of ${e##*/} is a gate that can never open, and because the hint is" \
		"still reachable through its other labels nothing ever goes red." \
		"Use the case label exactly as it appears in ${e##*/}."
done

# ---------------------------------------------------------------------------
# N. submit.sh's ladder names every layer the gate can actually run.
#
# There is a THIRD copy of the layer table, and it is the one nobody was
# checking: the help text tools/submit.sh prints for an unknown --gate-level.
# It listed `robust = diff, diff_asan, asan` and omitted allocfail, which has
# been a level-3 layer since it was written -- so someone reading it to decide
# which rung to submit at was told the rung ran less than it does.
#
# Only MEMBERSHIP is checked, not the level: docs/reference.md's table is where
# the level mapping is verified, and duplicating that here would just be a
# fourth copy. `oracle` and `selftest` are excluded because they live outside
# every module, so no submit gate can reach them -- docs/reference.md says so
# in as many words.
SUBMIT_LADDER=$(sed -n '/valid levels, each also running/,/set it per-user/p' tools/submit.sh)
if [ -z "$SUBMIT_LADDER" ]; then
	report "tools/submit.sh has no gate-level ladder this check can read" \
		"It looks for the block between 'valid levels, each also running' and" \
		"'set it per-user'. If that help text moved, move this check with it --" \
		"a lint that silently matches nothing is the false green this file" \
		"exists to prevent."
else
	missing=""
	for tag in $(printf '%s\n' "$LEVELS" | cut -d' ' -f1); do
		case "$tag" in
			oracle | selftest) continue ;;
		esac
		printf '%s' "$SUBMIT_LADDER" | grep -qF -- "$tag" || missing="$missing $tag"
	done
	[ -z "$missing" ] || report \
		"tools/submit.sh's gate ladder does not name every layer" \
		"missing:$missing" \
		"_LAYER_LEVEL in defs.bzl is what the gate actually selects, via the" \
		"cumulative lvl_* tags. A layer missing from this help text is one" \
		"somebody chooses a submission rung without knowing about."
fi

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
for f in c-piscine-*/BUILD.bazel; do
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
		"tools/setup.sh writes that file, and every per-machine override" \
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
fi

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
