# ------------------------------- conventions: the image's own tools, by hand
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# What the dev image installs for a student's own hands, over two toys. cvi
# breaks every rule: libbsd-dev's pages fetched at a version pins.tsv does not
# state, with no digest, and the package itself in the apt list; and a
# Dockerfile-only row (libbsd-dev) named outside docs/environment.md's list of
# what you run by hand, while another (widget) is named in it past a code
# fence whose '#' line is a shell comment, not a heading, and a row pinned in
# setup.sh too (gadget) is the harness's, which the list need not name.
# cvj has the same rows and no such list at all, where the image's pages
# came from finding 054 and the list from 198. A conventions run over a toy
# this small takes under a second, and each runs only in the shard whose
# arms read it.
#
# And what the review of WP-85 found the rules missed. cvi installs libbsd
# twice more, on one line beside another package (line 8, as the RUN
# creating the user lays out its apt step) and as a downloaded .deb handed to
# dpkg (line 9); pip-installs three packages for the terminal, one the list
# never names (doohickey), one it names at another version (gizmo) and one
# it names as it is (Whatsit); turns
# in ft_strnstr.c with no strnstr.3bsd in the image; prints a clue sending a
# student to `man strlcat` with no section and no fallback, beside a '#'
# line (never printed) and a row that has both; and has a runner taking
# toycc-9 from the box, beside one handed the pinned compiler (--cc). cvj's
# Dockerfile downloads libbsd-dev and unpacks two pages with dpkg-deb, which
# installs nothing; it turns in ft_strlcpy.c and carries strlcpy.3bsd; and
# its README's no-Docker paragraph names the toycc-9 its runner takes, which
# excuses nothing (review of W7-V38: `cc` was named there for the Makefile
# layers then, and a runner taking it from the box went unreported).
mkdir -p "$WORK/cvi/tools" "$WORK/cvi/c-piscine/c-piscine-c-88" "$WORK/cvi/.devcontainer" \
	"$WORK/cvi/docs" "$WORK/cvj/tools" "$WORK/cvj/c-piscine/c-piscine-c-88" "$WORK/cvj/.devcontainer"
for _t in cvi cvj; do
	mkdir -p "$WORK/$_t/c-piscine/c-piscine-c-88/tests/ex00"
	printf 'CC="${TOY_CC:-toycc-9}"\n' > "$WORK/$_t/tools/toy_check.sh"
	cv_submit "c-piscine/c-piscine-c-88" > "$WORK/$_t/tools/submit.sh"
	{
		printf 'widget\tcampus\twidget 1.0\twidget --version\t.devcontainer/Dockerfile\n'
		printf 'gadget\tcampus\tgadget 2.0\tgadget --version\ttools/setup.sh + .devcontainer/Dockerfile\n'
		printf 'libbsd-dev\tours\t1.0-1\t-\t.devcontainer/Dockerfile (LIBBSD_DEV_VERSION)\n'
	} > "$WORK/$_t/tools/pins.tsv"
done
printf 'FROM x\nARG LIBBSD_DEV_VERSION=1.0-2\nARG LIBBSD_DEV_SHA256=abc\nRUN apt-get install -y \\\n    widget=1.0 \\\n    libbsd-dev \\\n    && true\n' \
	> "$WORK/cvi/.devcontainer/Dockerfile"
{
	printf 'RUN apt-get update && apt-get install -y sudo libbsd0 && true\n'
	printf 'RUN dpkg -i /tmp/libbsd-dev.deb\n'
	printf 'RUN pip3 install --no-cache-dir gizmo==2.0\n'
	printf 'RUN pip3 install --no-cache-dir \\\n    doohickey==1.0 \\\n    Whatsit==3.0\n'
} >> "$WORK/cvi/.devcontainer/Dockerfile"
printf 'FROM x\nARG LIBBSD_DEV_VERSION=1.0-1\nARG LIBBSD_DEV_SHA256=%s\nRUN apt-get install -y \\\n    widget=1.0 \\\n    && true\n' \
	"$(printf '%064d' 0)" > "$WORK/cvj/.devcontainer/Dockerfile"
# And the image's apt pins of what MODULE.bazel fetches too (gcc-10, g++-10,
# binutils, make, valgrind), which nothing held together: cvi installs gcc-10
# and g++-10 at a revision its MODULE.bazel does not fetch, and binutils at
# one binutils-x86-64-linux-gnu is not fetched at, both reported; make at the
# fetched one, valgrind at it behind an epoch, and gdb, which is not fetched,
# are quiet.
printf 'RUN apt-get update && apt-get install -y \\\n    gcc-10=10.5.0-1ubuntu1~22.04.3 \\\n    g++-10=10.5.0-1ubuntu1~22.04.3 \\\n    binutils=2.38-4ubuntu2.12 \\\n    make=4.3-4.1build1 \\\n    valgrind=1:3.18.1-1ubuntu2 \\\n    gdb=12.1-0ubuntu1~22.04.2\n' \
	>> "$WORK/cvi/.devcontainer/Dockerfile"
{
	printf 'deb_archive(urls = ["http://x/pool/universe/g/gcc-10/gcc-10_10.5.0-1ubuntu1~22.04.4_amd64.deb"])\n'
	printf 'deb_archive(urls = ["http://x/pool/universe/g/gcc-10/libgcc-10-dev_10.5.0-1ubuntu1~22.04.3_amd64.deb"])\n'
	printf 'deb_archive(urls = ["http://x/pool/main/b/binutils/binutils-x86-64-linux-gnu_2.38-4ubuntu2.11_amd64.deb"])\n'
	printf 'deb_archive(urls = ["http://x/pool/main/m/make-dfsg/make_4.3-4.1build1_amd64.deb"])\n'
	printf 'deb_archive(urls = ["http://x/pool/main/v/valgrind/valgrind_3.18.1-1ubuntu2_amd64.deb"])\n'
} > "$WORK/cvi/MODULE.bazel"
# And its pip pins of what tools/requirements.txt pins too: gizmo, at
# another version there, and doohickey, at another one under another
# spelling of its name, are reported; Whatsit, at the same one under another
# spelling, and thingamajig, which the image does not install, are quiet.
{
	printf '# the build'"'"'s Python\ngizmo==2.1 \\\n    --hash=sha256:%064d\n' 0
	printf 'Doohickey==1.1\nwhatsit==3.0\nthingamajig==3.0\n'
} > "$WORK/cvi/tools/requirements.txt"
printf 'RUN wget -q -O /tmp/libbsd-dev.deb x/libbsd-dev_1.0-1_amd64.deb \\\n    && dpkg-deb --fsys-tarfile /tmp/libbsd-dev.deb | tar -x ./usr/share/man/man3/strlcpy.3bsd.gz\n' \
	>> "$WORK/cvj/.devcontainer/Dockerfile"
printf 'exercise(page = 1, dir = "ex00/", files = ["ft_strnstr.c"], allowed = [])\n' \
	> "$WORK/cvi/c-piscine/c-piscine-c-88/BUILD.bazel"
printf 'exercise(page = 1, dir = "ex00/", files = ["ft_strlcpy.c"], allowed = [])\n' \
	> "$WORK/cvj/c-piscine/c-piscine-c-88/BUILD.bazel"
{
	printf '# a header: man strlcat, never printed\n'
	printf 'What does it return? man 3bsd strlcpy says (no page installed? man.openbsd.org/strlcpy.3).\tcase one\n'
	printf 'What does it return? man strlcat says.\tcase two\n'
} > "$WORK/cvi/c-piscine/c-piscine-c-88/tests/ex00/clues.tsv"
printf 'while [ $# -gt 0 ]; do case "$1" in --cc) CC=$2; shift 2 ;; esac; done\nCC="${P_CC:-toycc-8}"\n' \
	> "$WORK/cvi/tools/toy_pinned.sh"
# A runner's SKIP text showing a whole-repo test (line 2, reported), beside
# one in a comment (3) and one whose printed line before says it needs
# memory (5), both quiet. Reported: one that says so only in a '#' note on
# its own line (6), which zsh runs as words of the command, and one whose
# line before says so in a comment, which is never printed (8).
{
	printf 'echo "  (bazel test //... --test_env=NO_SKIP=1)"\n'
	printf '# bazel test //... in a comment\n'
	printf 'echo "The whole repo needs memory to spare:"\n'
	printf 'echo "  bazel test //..."\n'
	printf 'echo "bazel test //...   # the whole repo: needs memory to spare"\n'
	printf '# the whole repo needs memory to spare\n'
	printf 'echo "  bazel test //..."\n'
} >> "$WORK/cvi/tools/toy_check.sh"
{
	printf '# Environment\n\n### What the docs ask you to run by hand\n\n'
	printf '```sh\n# a shell comment, not a heading\n```\n\n| `widget` | for your own hands |\n'
	printf '| `gizmo` | pip3 install --user gizmo==1.9 |\n| `Whatsit` | for your own hands |\n\n'
	printf '| **Your own Linux, no Docker** | a shell and a compiler |\n\n'
	printf '## Next\n\n| `libbsd-dev` | outside the list |\n'
} > "$WORK/cvi/docs/environment.md"
# And the first commands a newcomer copies (finding 006): a whole-repo test in
# a code block whose paragraph does not say it needs memory (lines 4 and 5,
# reported), with its flag before the pattern (5); one that says so only in
# a '#' note on its own line (6, reported: zsh runs the note); one whose
# paragraph says it (14, quiet); the same words in prose (1) and in TODO.md,
# a record (quiet); a module's /... (7, quiet). An editor whose default
# test task runs the whole repo, beside a task that does and whose label
# does not say so (both reported); cvj's default runs one module and its
# whole-repo task says it needs memory to spare (quiet).
{
	printf 'Run `bazel test //...` when you can.\n\n```sh\n'
	printf 'bazel test //... 2>&1 | sh tools/first_red.sh\n'
	printf 'bazel test --test_output=errors //...\n'
	printf 'bazel test //... --test_env=NO_SKIP=1   # the whole repo: needs memory to spare\n'
	printf 'bazel test //c-piscine/c-piscine-c-88/... --test_env=NO_SKIP=1\n```\n\n'
	printf 'The whole repo, which needs\nmemory to spare:\n\n```sh\n'
	printf 'bazel test //... --nocache_test_results\n```\n'
} > "$WORK/cvi/README.md"
printf '```\nbazel test //...   1742 targets\n```\n' > "$WORK/cvi/TODO.md"
printf 'The whole repo needs memory to spare:\n\n```sh\nbazel test //...\n```\n' > "$WORK/cvj/README.md"
# And the blocks a page fences otherwise (V140), each reported at its
# whole-repo test: a tilde fence (fence_tilde.md, line 4); a block in a
# quoted page, whose four-backtick fence a shorter one inside never closes
# (fence_four.md, line 7); and a block whose paragraph a tilde block ends,
# the memory sentence above that block being none of its own (fence_leak.md,
# line 7).
printf 'Run it:\n\n~~~sh\nbazel test //...\n~~~\n' > "$WORK/cvi/docs/fence_tilde.md"
printf 'A page, quoted whole:\n\n````md\nRun it:\n\n```sh\nbazel test //...\n```\n````\n' \
	> "$WORK/cvi/docs/fence_four.md"
printf 'The whole repo needs memory to spare:\n~~~sh\nls\n~~~\nA block of its own follows:\n```sh\nbazel test //...\n```\n' \
	> "$WORK/cvi/docs/fence_leak.md"
# And a page's shell blocks pasted into zsh, which runs a '#' note as words
# of the command (62 such lines when the rule came). Reported: a note after
# a command (line 5), a line that is only a note (9, in a bash block), a
# console block indented inside a list (15) and one fenced with tildes (19).
# Quiet: a script's '#!' line (4), a '#' inside quotes (23, and 25 inside a
# quote opened on the line before), after an escaped blank (26), not at a
# word's start (27), a heredoc's body (29 and 30), a C block's '#include'
# (35), an unmarked block's note (39) and a heading in prose (42). cvj's
# page has none.
{
	printf 'Run:\n\n```sh\n#!/bin/sh\nmake && make   # the second run does nothing\n```\n\n'
	printf '```bash\n# a note alone\n```\n\n'
	printf -- '- in a list:\n\n  ```console\n  $ ls   # a note\n  ```\n\n'
	printf '~~~zsh\nls  # a note\n~~~\n\n'
	printf '```sh\ngrep -c " # x" f\necho "a\n # b"\necho a\\ #b\ncut -d# -f1 f\n'
	printf 'cat > a.c <<EOF\n#include <unistd.h>\n #x\nEOF\n```\n\n'
	printf '```c\n #include <unistd.h>\n```\n\n'
	printf '```\nls  # a note\n```\n\n'
	printf '# A heading\n'
} > "$WORK/cvi/docs/paste.md"
# And a block that sets a variable to several words and expands it bare,
# which zsh hands on as one word (docs/split.md). Reported: `$m` (line 3)
# and `${m}` (8). Quiet: the same variable quoted (4 and 5) or inside single
# quotes (9), a variable of one word (7), an unmarked block (13) and a block
# that never set it (17).
{
	printf '```sh\nm='"'"'//a/... //b/...'"'"'\nbazel test $m\nbazel test "$m"\necho "${m}"\n'
	printf 'one=//a/...\nbazel test $one\nbazel test ${m} -k\necho '"'"'$m'"'"'\n```\n\n'
	printf '```\nbazel test $m\n```\n\n```sh\nbazel test $m\n```\n'
} > "$WORK/cvi/docs/split.md"
# And a script that shows a command to type with a '#' note
# (tools/paste_note.sh). Reported: a usage line of its header (4), one
# naming the script alone with one blank before its note (5), an echo (11)
# and a printf (12). Quiet: a usage line with its note on the line before
# (7), prose in the header (8), a comment below the header (10), a '#
# define' an echo quotes (13), a quoted '#' (14), a report's heading (15)
# and the script's own comment (16).
printf '%s\n' '#!/bin/sh' '# paste_note.sh -- a toy.' '#' \
	'#   sh tools/paste_note.sh --all   # a note on a usage line' \
	'#   paste_note.sh -n # dry-run' \
	'# Usage: a note before the command,' \
	'#   sh tools/paste_note.sh' \
	'# A count of the # signs  # in prose' \
	'' \
	'# bazel test //m:x   # below the header' \
	'echo "      rm -rf dir   # re-detects just this"' \
	'printf "  %s  # a note\n" bazel' \
	'echo "  not wrapped in #ifndef X_H / # define X_H"' \
	'echo "  grep -c '"'"'#'"'"' f"' \
	'echo "   # A heading"' \
	'x=1  # a comment' > "$WORK/cvi/tools/paste_note.sh"
# And a script's '# Usage:' block, whose indented lines are commands to type
# whatever word they start with (tools/usage_note.sh). Reported: a usage line
# starting with make (5), with cc and one blank before its note (6), and a
# continuation of the one before it (8). Quiet: a usage line with no note
# (7), and an option's description past the bare '#' that ends the block
# (10), as the harness's runners lay theirs out.
printf '%s\n' '#!/bin/sh' '# usage_note.sh -- a toy.' '#' '# Usage:' \
	'#   make -C toy   # builds it' \
	'#   cc -Wall a.c # one blank' \
	'#   norminette a.c' \
	'#       [-R CheckDefine]   # a continuation' \
	'#' \
	'#   --all   every case, # by number' \
	'' \
	'echo hi' > "$WORK/cvi/tools/usage_note.sh"
# And the command on the '# Usage:' line itself (tools/usage_tail.sh, V157):
# reported with a note after it, whatever its first word, make (2) or a
# script's own name (4); quiet with none (3).
printf '%s\n' '#!/bin/sh' '# Usage: make -C toy   # builds it' '# Usage: usage_tail.sh [-n]' \
	'# Usage: usage_tail.sh -x   # one case' '' 'echo hi' > "$WORK/cvi/tools/usage_tail.sh"
# And a session in an unmarked block (docs/session.md). Reported: a note
# after a shell's prompt (2), gdb's (3) and lldb's (4). Quiet: a quoted '#'
# (5), one inside a word (6), a debugger's output line (7) and a marked
# block, which the rule for those reads (11).
{
	printf '```\n$ ls   # a note\n(gdb) bt   # a note\n(lldb) run # a note\n'
	printf '$ grep -c " #" f\n$ cut -d# -f1 f\n#0  main () at a.c:3\n```\n\n'
	printf '```sh\n$ ls  # x\n```\n'
} > "$WORK/cvi/docs/session.md"
printf '\n**Your own Linux works without Docker too:** install `toycc-9`.\n' >> "$WORK/cvj/README.md"
mkdir -p "$WORK/cvi/.vscode" "$WORK/cvj/.vscode"
cv_task() {  # cv_task LABEL COMMAND DEFAULT -- one task object, as tasks.json lays it out
	printf '    {\n      "label": "%s",\n      "type": "shell",\n      "command": "%s",\n' "$1" "$2"
	if [ "$3" = 1 ]; then
		printf '      "group": { "kind": "test", "isDefault": true },\n'
	else
		printf '      "group": "test",\n'
	fi
	printf '      "problemMatcher": []\n    }%s\n' "${4:-}"
}
# cvi's default keeps its command in a multi-line "args" array, as the real
# file's does, and its label is not the one its docs name; cvj's docs name
# the label its default has.
{
	printf '{\n  // a { comment } line\n  "version": "2.0.0",\n  "tasks": [\n'
	printf '    {\n      "label": "Toy: test all",\n      "type": "process",\n'
	printf '      "command": "sh",\n      "args": [\n        "-c",\n'
	printf '        "exec bazel test //... --test_output=errors"\n      ],\n'
	printf '      "group": { "kind": "test", "isDefault": true },\n'
	printf '      "problemMatcher": []\n    },\n'
	cv_task "Toy: test everything" "bazel test //..." 0
	printf '  ]\n}\n'
} > "$WORK/cvi/.vscode/tasks.json"
printf '\nRun Task, then `Toy: test it all`; or `Toy: test everything`.\n' >> "$WORK/cvi/README.md"
{
	printf '{\n  "version": "2.0.0",\n  "tasks": [\n'
	cv_task "Toy: test this module" "bazel test //c-piscine/c-piscine-c-88:basic" 1 ,
	cv_task "Toy: test all (needs memory to spare)" "bazel test //..." 0
	printf '  ]\n}\n'
} > "$WORK/cvj/.vscode/tasks.json"
printf '\nRun Test Task: `Toy: test this module`.\n' >> "$WORK/cvj/README.md"
# And a shipped file that cites a section or an item of the maintainer's
# backlog or record, which the template ships without: by section (line 1),
# wrapped after the file's name (line 2), by lead (4), an item of the old
# board by number (5) and wrapped (6), and a file under the records'
# folder, todo/, by its path (10), from ./ (11), from ../ (15) and ../../
# (16), in a URL (17) and with a section after it (18) -- all reported. A
# mention that cites nothing (8), a tag named bare (9), a plan's file named
# by its pattern (12), the folder named bare (13), a toy's path that runs
# through a folder of that name (14), and the same citation in TODO.md stay
# quiet. Each file name is put together by printf, so this file cites
# nothing itself.
{
	printf '# the reason is recorded (TODO%s §23, WP-92).\n# rigour (TODO%s\n# section 23).\n' .md .md
	printf '# see HISTORY%s, V25.\n# not a substitute (see TODO %s 1)\n' .md item
	printf '# not manual (board\n# item 9): it passes.\n'
	printf '# a lead goes to the TO VERIFY list of TODO%s, which a clone lacks.\n' .md
	printf '# V111, WP-92 and finding 041 are names, and cite nothing.\n'
	printf '# the plan is in to%s/23-plan.md.\n# and ./to%s/25-plan.md says why.\n' 'do' 'do'
	printf '# a plan is filed as todo/NN-<name>.md.\n# the records folder, todo/, a clone lacks.\n'
	printf '# the toy writes "$WORK/t/todo/23-plan.md".\n'
	printf '# the plan is [here](../to%s/23-plan.md).\n# and ../../to%s/decisions/0001-x.md.\n' 'do' 'do'
	printf '# https://github.com/x/42/blob/main/to%s/notes/x.md says.\n' 'do'
	printf '# the reason is in to%s/23-plan.md, its section G5.\n' 'do'
} > "$WORK/cvi/tools/cite.sh"
printf 'See HISTORY%s §21.\n' .md >> "$WORK/cvi/TODO.md"
# And a shipped file that says a CI runs the checks, while the repo has none
# (V118): reported in cvi, which has no workflow (ci.sh 1 on one line, 2
# wrapped before its last word); a sentence saying there is none (4) stays
# quiet. cvj has a workflow under .github, so there the same lines are true.
for _t in cvi cvj; do
	printf '# NO_SKIP=1 (set in %s) forces it open.\n# the repo checking in\n# %s runs the same.\n# there is no %s in this repo.\n' \
		CI CI CI > "$WORK/$_t/tools/ci.sh"
done
mkdir -p "$WORK/cvj/.github/workflows"
printf 'on: push\n' > "$WORK/cvj/.github/workflows/check.yml"
# And a full run's size quoted outside tools/drives.sh: reported beside a full
# run (size.sh 1) and a build tree written with no space (3); quiet beside
# anything else (2), in tools/drives.sh, which keeps the figure, and in
# TODO.md, which quotes what it records. The unit is put in by printf, so
# this file quotes no size the rule reads.
printf '# A full run of this repo is 9 %s.\n# The download cache is 2.1 %s.\n# an 8.5%s build tree in RAM\n' \
	GB GB GB > "$WORK/cvi/tools/size.sh"
printf '# A full run takes 9 %s.\nDRIVES_FULL_GB=9\n' GB > "$WORK/cvi/tools/drives.sh"
printf 'A full run measured at 9 %s.\n' GB >> "$WORK/cvi/TODO.md"
# And the prime's scratch derived from an rc root outside tools/drives.sh:
# reported in tools/scratch.sh, quiet in drives.sh, which keeps the lookup.
# The `%` is put in by printf, so this file holds no derivation the rule reads.
printf '# scratch=${root%s/bazel}\n' % > "$WORK/cvi/tools/scratch.sh"
printf '# scratch=${root%s/bazel}\n' % >> "$WORK/cvi/tools/drives.sh"
# A macro's docstring that counts call sites, which the knobs fixture makes
# wrong. Reported: "nothing in the repo" (line 5), "no call site" wrapped
# before its verb (6), and "every existing call site" wrapped inside its
# words (10). Quiet: the second line of each wrapped phrase (7, 11), "no
# project" (8) and "nearly every call site" (9).
{
	printf 'def toy(srcs = None, hdrs = None, deps = None, outs = None):\n    """A toy.\n\n    Args:\n'
	printf '        srcs: the sources. Nothing in the repo overrides it.\n'
	printf '        hdrs: more headers. No call site\n            passes one today.\n'
	printf '        deps: more deps. No project passes one, and nearly every call site\n'
	printf '            passes labeled.\n'
	printf '        outs: the outputs. Name them -- every existing\n            call site does.\n    """\n'
} > "$WORK/cvi/tools/toy.bzl"
# And a C file whose header sends its reader to tools/diffio.h: reported
# without the #include (toy_rush.c), quiet with it (toy_line.c) and in the
# zone.
mkdir -p "$WORK/cvi/c-piscine/c-piscine-c-88/deliverable/ex00"
printf '/* A toy.\n * Line: <x>\\t<y>. See tools/diffio.h. */\nint\tmain(void)\n{\n\treturn (0);\n}\n' \
	> "$WORK/cvi/c-piscine/c-piscine-c-88/tests/ex00/toy_rush.c"
cp "$WORK/cvi/c-piscine/c-piscine-c-88/tests/ex00/toy_rush.c" "$WORK/cvi/c-piscine/c-piscine-c-88/deliverable/ex00/"
printf '/* A toy.\n * Line: <x>. See tools/diffio.h. */\n#include "diffio.h"\n\nint\tmain(void)\n{\n\treturn (0);\n}\n' \
	> "$WORK/cvi/c-piscine/c-piscine-c-88/tests/ex00/toy_line.c"
if st_mine; then
	for _t in cvi cvj; do
		env BUILD_WORKSPACE_DIRECTORY="$WORK/$_t" "$SH" "$TOOLS/conventions.sh" > "$WORK/$_t.out" 2>&1
	done
fi
# Each toy's run is read through the driver's cvi_rule TOY HEADLINE (A SAVED
# RUN OF THE CONVENTIONS CHECK), which gives a run cut short status 2.
# The shellcheck sweep reads what text_files() reads (V113): a dot folder the
# repo does not track (a gitignored one of the owner's held a peer's script
# it reported) and a student's generators/, which its own lint layer reads,
# are not the harness's code. .devcontainer is, and so is a module's folder.
# So is .github: its issue forms and pages ship with the template, and
# every rule that walks text_files() reads them -- shellcheck a script there,
# the link rule a page.
mkdir -p "$WORK/cvsc/.scratch" "$WORK/cvsc/.devcontainer" "$WORK/cvsc/.github" \
	"$WORK/cvsc/m/generators" "$WORK/cvsc/tools"
cv_submit m > "$WORK/cvsc/tools/submit.sh"
: > "$WORK/cvsc/m/BUILD.bazel"
# And a page that says to re-run on a still tree names --nocache_test_results
# in the same paragraph (V111): a plain re-run serves a result a run cached
# for a file that changed under it. README's paragraph wraps the phrase
# (reported, line 1); the page's first list item names it and the item after
# it the flag, so the item is reported (line 3); its last paragraph names
# both (quiet).
mkdir -p "$WORK/cvsc/docs"
printf 'When two runs disagree, re-run on a\nstill tree first.\n' > "$WORK/cvsc/README.md"
printf '# Toy\n\n- re-run on a still tree\n- with `--nocache_test_results`\n\nRun on a still tree with `--nocache_test_results`.\n' \
	> "$WORK/cvsc/docs/toy.md"
printf '# Toy\n\nSee [the guide](missing.md).\n' > "$WORK/cvsc/.github/toy.md"
for _f in .scratch/tilde.sh .devcontainer/tilde.sh .github/tilde.sh m/generators/ex00.sh m/tilde.sh; do
	printf '#!/bin/sh\necho "~/x"\n' > "$WORK/cvsc/$_f"
done
# A source directive tells shellcheck which file a `. "$VAR"` loads, and it
# opens that file from where it runs, the repository root. Written
# relative to the script's own folder it names nothing there: shellcheck
# follows nothing, says so in a note -S warning hides, and goes on (25 check
# scripts did). ex00's directive is the script's own relative path (reported);
# ex01's is the root's, ex02's is /dev/null, and a generator's is the
# student's (all three quiet).
mkdir -p "$WORK/cvsc/m/tests/ex00" "$WORK/cvsc/m/tests/ex01" "$WORK/cvsc/m/tests/ex02"
printf '# shellcheck shell=sh\ntoy() { :; }\n' > "$WORK/cvsc/tools/toy_lib.sh"
printf '#!/bin/sh\n# shellcheck source=../../../tools/toy_lib.sh\n. "${TOY_LIB:?}"\n' \
	> "$WORK/cvsc/m/tests/ex00/check.sh"
printf '#!/bin/sh\n# shellcheck source=tools/toy_lib.sh\n. "${TOY_LIB:?}"\n' \
	> "$WORK/cvsc/m/tests/ex01/check.sh"
printf '#!/bin/sh\n# shellcheck source=/dev/null\n. "${TOY_LIB:?}"\n' \
	> "$WORK/cvsc/m/tests/ex02/check.sh"
printf '#!/bin/sh\n# shellcheck source=../toy_lib.sh\n. "${TOY_LIB:?}"\n' \
	> "$WORK/cvsc/m/generators/ex01.sh"
if st_mine; then
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvsc" "$SH" "$TOOLS/conventions.sh" \
		--shellcheck "$SHELLCHECK" > "$WORK/cvsc.out" 2>&1
fi
want_out "conventions: shellcheck reads a script under .devcontainer" \
	'./.devcontainer/tilde.sh:2:' -- cvi_rule cvsc 'shellcheck reports'
want_out "conventions: ...and one in a module's folder" \
	'./m/tilde.sh:2:' -- cvi_rule cvsc 'shellcheck reports'
want_out "conventions: ...and one under .github" \
	'./.github/tilde.sh:2:' -- cvi_rule cvsc 'shellcheck reports'
want_out "conventions: a page under .github is read for its links" \
	'    .github/toy.md:3: missing.md' -- cvi_rule cvsc 'a page links to a file, folder or heading'
want_broken_none "conventions: ...never one under a dot folder the repo does not track" \
	'.scratch/' -- cvi_rule cvsc 'shellcheck reports'
want_broken_none "conventions: ...nor a student's generator" \
	'generators/' -- cvi_rule cvsc 'shellcheck reports'
want_out "conventions: a still tree with no --nocache_test_results is reported" \
	'    README.md:1' -- cvi_rule cvsc 'a page says to re-run on a still tree'
want_out "conventions: ...in a list item, whose next item is its own" \
	'    docs/toy.md:3' -- cvi_rule cvsc 'a page says to re-run on a still tree'
want_broken_none "conventions: ...never a paragraph that names it" \
	'docs/toy.md:6' -- cvi_rule cvsc 'a page says to re-run on a still tree'
# cvsc has a project with generators/ and no tools/BUILD.bazel: no
# generate target to hold to it, so nothing to say.
want_broken_none "conventions: no generate target, no word about its args" \
	'm: has a generators/ folder' -- cvi_rule cvsc "//tools:generate's args"
want_out "conventions: a source directive shellcheck cannot open from the root" \
	'    m/tests/ex00/check.sh:2: ../../../tools/toy_lib.sh' -- \
	cvi_rule cvsc 'a shellcheck source directive names a file'
want_broken_none "conventions: ...never one it can" \
	'ex01' -- cvi_rule cvsc 'a shellcheck source directive names a file'
want_broken_none "conventions: ...nor /dev/null" \
	'ex02' -- cvi_rule cvsc 'a shellcheck source directive names a file'
want_broken_none "conventions: ...nor one in a student's generator" \
	'generators/' -- cvi_rule cvsc 'a shellcheck source directive names a file'
# cvsc's module m has three folders under tests/ and no clues.tsv in any:
# the dead-label check's floor counted the clues.tsv it found, so a run
# that found none -- a glob that stopped matching, or files the run cannot
# see -- passed having compared nothing, and said nothing.
want_out "conventions: a dead-label check that found no clues.tsv at all" \
	'found no clues.tsv in the 3 folders' -- \
	cvi_rule cvsc 'the dead-label check found no clues.tsv'
# The shellcheck sweep runs in lanes in the background, read just before
# the verdict (V439): the verdict waits for a lane that is slow to answer,
# and a lane that ends as no shellcheck ends (0 clean, 1 something found)
# is reported, since what it printed may not be all it had to say. The
# stand-in is slow, finds something and exits 3.
mkdir -p "$WORK/cvsc_lane"
printf '#!/bin/sh\nsleep 1\necho "x.sh:1:1: warning: a late lane [SC0000]"\nexit 3\n' \
	> "$WORK/cvsc_lane/shellcheck"
chmod +x "$WORK/cvsc_lane/shellcheck"
if st_mine; then
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvsc" "$SH" "$TOOLS/conventions.sh" \
		--shellcheck "$WORK/cvsc_lane/shellcheck" > "$WORK/cvsc_lane.out" 2>&1
fi
want_out "conventions: the verdict waits for a slow shellcheck lane" \
	'x.sh:1:1: warning: a late lane' -- cvi_rule cvsc_lane 'shellcheck reports'
want_out "conventions: ...and reports one that exits neither 0 nor 1" \
	'Exit status of each lane that failed: 3' -- \
	cvi_rule cvsc_lane 'the pinned shellcheck did not finish'
# A runner one project calls restates its subject without naming it (V90):
# Rush 01's printed "the subject prints it verbatim", BSQ's restated its tie
# rule. Three runners in a tree of their own: probe_own.sh, which one module
# runs; probe_two.sh, which two do; probe_shared.sh, which a macro emits. All
# three are held to "the subject <verb>": a line that reads the call site's
# contract back says which option brings it.
mkdir -p "$WORK/cvq/tools" "$WORK/cvq/c-piscine/c-piscine-q1" "$WORK/cvq/c-piscine/c-piscine-q2"
cv_submit "c-piscine/c-piscine-q1 c-piscine/c-piscine-q2" > "$WORK/cvq/tools/submit.sh"
printf 'def m():\n    native.sh_test(name = "s", srcs = ["//tools:probe_shared.sh"])\n' \
	> "$WORK/cvq/tools/defs.bzl"
printf 'hand_test(\n    name = "a",\n    srcs = ["//tools:probe_own.sh"],\n)\n' \
	> "$WORK/cvq/c-piscine/c-piscine-q1/BUILD.bazel"
printf 'corpus_memory(\n    stem = "a",\n    runner = "//tools:probe_two.sh",\n)\n' \
	>> "$WORK/cvq/c-piscine/c-piscine-q1/BUILD.bazel"
printf 'hand_test(\n    name = "b",\n    srcs = ["//tools:probe_two.sh"],\n)\n' \
	> "$WORK/cvq/c-piscine/c-piscine-q2/BUILD.bazel"
# Reported: an awk print (6), a message continued over two lines (7), a
# verdict( (9) and a here-document's lines (14, and 13, a # line it prints,
# no comment). Quiet: a comment in the script (4), a sentence quoting nothing
# (10, 16), and a printf inside a $( ) whose next line continues another
# command (17). Reported too: a line under a marker naming an option it parses
# (23), which allows nothing in a runner one project calls: its sentence comes
# from the call site's quote. The same line in probe_shared.sh (11) is quiet.
cat > "$WORK/cvq/tools/probe_own.sh" <<'PROBE_OWN'
#!/bin/sh
set -u
. "$RL_LIB"
# The subject says this, for whoever maintains it
awk 'BEGIN {
	print "  the subject says the square is drawn top first"
	if (x) print "    the\n" \
	      "    subject picks one"
	verdict("k", "it printed Error;", "the subject prints it verbatim.")
	print "  as the call site quotes it:"
}'
cat <<EOT
# the subject says, in a here-document's comment
  The subject requires a newline.
EOT
echo "  The sentence, quoted from the call site:"
x=$(printf '%s' "the" \
	"subject says")
case "${1:-}" in
	--required) shift 2 ;;
esac
# conventions: the call site's --required -- the files its contract lists
echo "  the files the subject asks for"
PROBE_OWN
printf '#!/bin/sh\nset -u\n. "$RL_LIB"\necho "  the files the subject asks for"\n' \
	> "$WORK/cvq/tools/probe_two.sh"
# A runner every project calls is held to it too (V122): diff_output.sh's
# address-dump note said "as the subject asks" where only --sanitize, one
# exercise's option, reaches it. Reported: a branch one flag opens (13), and
# a marker naming an option the runner does not parse (16). Quiet: a line
# under a marker naming one it does (11), which reads the call site back.
# Reported too: a line a here-document prints below a marker-shaped line of
# its own (19), which prints and is no comment, so it allows nothing; and
# the subject that names, leaves, specifies, lets or allows (21 to 25), the
# verbs a runner's claims about a subject were found in after the first list.
# And a run of messages is read as one block (V162): a phrase split over two
# echo lines is reported at the first (27); quiet, the same split under a
# marker naming an option the runner parses, which covers the block (30),
# and two sentences side by side, which the join keeps apart (34). Under a
# marker, the message below it is covered and the next one judged alone is
# not: a second claim in the block is reported (39). And a printf of a lone
# newline ends a block as a bare echo does, so the split around it is
# quiet (41). A comment prints nothing and ends no block (V319): the split
# around one is reported (46). A here-document cat prints is a block too
# (V318): the split over its lines is reported at the first (51), and so
# is one sent to stderr (55); quiet, one a blank line breaks (59) and one
# written to a file (64). A message reported alone (72, 76) ends the block
# above it, which is still judged: a split above it is reported (69, and 74
# in a here-document), where a comment between them once hid it (the review
# of V319).
cat > "$WORK/cvq/tools/probe_shared.sh" <<'PROBE_SHARED'
#!/bin/sh
set -u
. "$RL_LIB"
while [ "$#" -gt 0 ]; do
	case "$1" in
		--required) shift 2 ;;
		--dump) DUMP=1; shift ;;
	esac
done
# conventions: the call site's --required -- the files its contract lists
echo "  the files the subject asks for"
if [ "${DUMP:-0}" = 1 ]; then
	echo "  print each address, as the subject asks."
fi
# conventions: the call site's --quotes -- an option this runner never reads
echo "  the subject says so."
cat <<EOT
# conventions: the call site's --required -- printed, not a comment
  the subject says so, in a here-document.
EOT
echo "  The subject names no exit status."
echo "  the subject leaves it open."
echo "  the subject specifies a newline."
echo "  the subject lets it exit 1."
echo "  the subject allows malloc."
# A phrase split over two messages that print one after the other.
echo "  print each address as the"
echo "  subject asks."
# conventions: the call site's --required -- the files its contract lists
echo "  the files the"
echo "  subject lists."

# Two sentences side by side.
echo "  This line is the subject."
echo "  Says nothing else."
# A marker covers the message below it, never the next one alone.
# conventions: the call site's --required -- the files its contract lists
echo "  the files the subject asks for"
echo "  and the subject says the rest."
# A printf of a lone newline ends a block, as a bare echo does.
echo "  print each address as the"
printf '\n'
echo "  subject asks."

# A phrase split around a comment, which prints nothing.
echo "  print each address as the"
# the comment between them
echo "  subject asks."

cat <<EOT
  print each address as the
  subject asks.
EOT
cat >&2 <<EOT
  print each address as the
  subject asks.
EOT
cat <<EOT
  print each address as the

  subject asks.
EOT
cat > "$WORK/x.awk" <<EOT
  print each address as the
  subject asks.
EOT

# A phrase split, a comment, then a message reported alone.
echo "  print each address as the"
echo "  subject asks."
# the comment between them
echo "  this one is for q1 alone."
cat <<EOT
  print each address as the
  subject asks.
  this one is for q1 alone.
EOT
PROBE_SHARED
# And a here-document in a $( ) inside double quotes is one, whose line
# prints when the variable is echoed (5; the review of V170).
printf '%s\n' '#!/bin/sh' 'set -u' '. "$RL_LIB"' 'msg="$(cat <<EOT' \
	'  this one is for q1 alone.' 'EOT' ')"' 'echo "$msg"' > "$WORK/cvq/tools/probe_hdq.sh"
# And a helper whose usage comment shows a here-document (V170): the <<eof
# there opens none, so the comment below it (7) is a comment and the case
# arm (8) code, neither printed: quiet.
printf '%s\n' '#!/bin/sh' 'set -u' '. "$RL_LIB"' 'say() {  # say TEXT <<eof -- one line of the log' \
	'	echo "  $1"' '}' '# As q1 lays it out, the subject says so.' 'case "${1:-}" in q1) say a ;; esac' \
	> "$WORK/cvq/tools/probe_hdc.sh"
# A project's BUILD comment ships (V94): it names neither the oracle's
# source nor a reading. q2's BUILD file, after its four lines of code:
# reported as the source, a path of the oracle's source (5) and a Rust file
# in the comment after code (9); as the label, wrapped over two comment lines (6)
# and with a typographic apostrophe (10); quiet, a string that holds a path
# and a # (8), the package //oracle (11). And a module's .bzl file is read
# as its BUILD file is.
{
	echo "# The reference is oracle/src/q2.rs's header."
	echo "# ex00_readings holds one reading, and this harness's"
	echo '# reading is that a count is digits.'
	echo 'x = "oracle/src/q2.rs # not a comment"'
	echo 'y = 1  # see q2.rs'
	printf '# the harness\342\200\231s reading of "x": y\n'
	echo '# //oracle answers it, and the README says so.'
} >> "$WORK/cvq/c-piscine/c-piscine-q2/BUILD.bazel"
echo '# from oracle/src/team.rs' > "$WORK/cvq/c-piscine/c-piscine-q1/team.bzl"
# Nor does any other shipped file name the reference's source (V123), a
# test file's comment and a runner's included. Reported: a comment line of a
# runner (probe_ref.sh 2) and one after its code (5), a selftest's comment
# (st.sh 1), a C file's block comment (toy_shape.c 2) and its // comment
# (5), a generated fixture's header (cases.tsv 1), a module's README (1), a
# page of docs/ (page.md 1), and a comment after a word holding an apostrophe
# (probe_ref.sh 7). Quiet: a runner's code and a string it echoes into
# /dev/null (probe_ref.sh 3, 4), a # inside a word of shell (6: ${f#...} and
# $#), the zone, the oracle's own folder, the maintainer's backlog (TODO.md),
# and the BUILD file the rule above reads.
mkdir -p "$WORK/cvq/tools/tests" "$WORK/cvq/c-piscine/c-piscine-q1/tests/ex00" \
	"$WORK/cvq/c-piscine/c-piscine-q1/deliverable/ex00" "$WORK/cvq/c-piscine/c-piscine-q1/generators" \
	"$WORK/cvq/oracle/src" "$WORK/cvq/docs"
printf '#!/bin/sh\n# The rule lives in oracle/src/q.rs.\nls oracle/src > /dev/null\n' > "$WORK/cvq/tools/probe_ref.sh"
printf 'echo "# oracle/src, in a string" > /dev/null\necho x  # as q_bonus.rs does\n' >> "$WORK/cvq/tools/probe_ref.sh"
printf 'x=${f#oracle/src/}; n=$#\necho it'"'"'s # as q_lone.rs does\n' >> "$WORK/cvq/tools/probe_ref.sh"
# What a runner prints is read too: UNOWNED's message once sent the student
# to the reference's source, and only its comments were read. Reported: an
# echo (probe_ref.sh 8), a printf to stderr (9), a printf's argument on the
# line it continues onto (16), a here-document cat prints (18), and an echo in
# a loop nothing redirects (27). Quiet: a printf into a file (10), one whose
# output is captured (11), an echo in a group written to a file (13), a
# here-document cat writes to a file (21), one a loop reads (24), and the
# argument of the command an echo pipes into (29). Reported too: an echo in
# a case arm (30), one sent to /dev/stderr (31), and a here-document sed
# prints (33). Quiet: an echo in a loop a $( captures from its first line
# (36), and one in a loop whose pipeline ends in a file (39). Reported: an
# echo sent to a quoted "/dev/stderr" (41) and a printf to a quoted
# '/dev/tty' (42). Quiet: one into a file whose quoted name only starts
# with /dev/stderr (43), and one whose name, unquoted, does (44). A string
# that runs on over lines is judged by the line that closes it (V141).
# Quiet: an awk program written to a file (its printf on 46), an echo of a
# single-quoted string to a file (52), and a program whose closing line
# sends it to one (56). Reported: an awk program printed (49) and an echo
# of a double-quoted string printed (54).
cat >> "$WORK/cvq/tools/probe_ref.sh" <<'PROBE_PRINTS'
echo "  none of them: edit oracle/src/x.rs, then --write."
printf 'from %s\n' "q_print.rs" >&2
printf '%s\n' oracle/src/q.rs > "$WORK/list"
x=$(printf '%s' oracle/src/q.rs)
{
	echo "oracle/src/q_group.rs"
} > "$WORK/group"
printf '%s %s\n' "a" \
	"oracle/src/q_cont.rs"
cat <<EOF
run oracle/src/q_doc.rs
EOF
cat > "$WORK/doc" <<'EOF'
oracle/src/q_file.rs
EOF
while IFS= read -r l; do :; done <<EOF
oracle/src/q_in.rs
EOF
for _f in a; do
	echo "$_f" "q_loop.rs"
done
echo "$x" | grep -q oracle/src
case x in *) echo "oracle/src/q_case.rs" >&2 ;; esac
echo "oracle/src/q_err.rs" > /dev/stderr
sed 's/^/  /' <<EOF
oracle/src/q_sed.rs
EOF
_n=$(for _f in a; do
	echo "oracle/src/q_cap.rs"
done)
for _f in a; do
	echo "oracle/src/q_sorted.rs"
done | sort > "$WORK/sorted"
echo "oracle/src/q_quoted.rs" > "/dev/stderr"
printf '%s\n' oracle/src/q_tty.rs >>'/dev/tty'
echo "oracle/src/q_log.rs" > "/dev/stderr.log"
echo oracle/src/q_ulog.rs > /dev/stderr.log
awk 'BEGIN {
	printf "see oracle/src/q_awkf.rs\n"
}' > "$WORK/awkf"
awk 'BEGIN {
	printf "see oracle/src/q_awko.rs\n"
}'
echo 'one line,
then oracle/src/q_echof.rs' > "$WORK/echof"
echo "one line,
then oracle/src/q_echoo.rs"
awk '{ n++
	printf "%s\n", "oracle/src/q_flat.rs" }' "$1" > "$WORK/flat"
PROBE_PRINTS
printf 'The shape is in oracle/src/q1.rs.\n' > "$WORK/cvq/docs/page.md"
printf 'oracle/src/q1.rs holds the shape.\n' > "$WORK/cvq/TODO.md"
printf '# the oracle'"'"'s main.rs, broken\n' > "$WORK/cvq/tools/tests/st.sh"
printf '/* The shape is the reference'"'"'s\n * (oracle/src/q1.rs). */\nint\tmain(void)\n{\n\treturn (0); // as q1_bonus.rs does\n}\n' \
	> "$WORK/cvq/c-piscine/c-piscine-q1/tests/ex00/toy_shape.c"
printf '# GENERATED from oracle/src/q1.rs\na\t1\t1\n' > "$WORK/cvq/c-piscine/c-piscine-q1/tests/ex00/cases.tsv"
printf 'The rule is in oracle/src/q1.rs.\n' > "$WORK/cvq/c-piscine/c-piscine-q1/README.md"
printf '/* oracle/src/q1.rs */\n' > "$WORK/cvq/c-piscine/c-piscine-q1/deliverable/ex00/q.c"
printf '#!/bin/sh\n# oracle/src/q1.rs\n' > "$WORK/cvq/c-piscine/c-piscine-q1/generators/ex00.sh"
printf '// see oracle/src/q.rs\n' > "$WORK/cvq/oracle/src/q.rs"
# No clue sends a student to read the oracle, in any hint file a module
# ships: the rule read a clues.tsv and a test_*.c alone. Reported: a case's
# own clue file (clues_x.tsv 1), a diff legend's line (diff_clues.txt 2)
# and a diff harness's string (diff_q.c 4). Quiet: the legend's # line,
# which no run prints (3).
printf 'Stuck? Read the Rust oracle source for this one.\n' \
	> "$WORK/cvq/c-piscine/c-piscine-q1/tests/ex00/clues_x.tsv"
printf '  One shape per line.\n    * any shape -> see the Rust oracle source\n# read the oracle source: a note\n' \
	> "$WORK/cvq/c-piscine/c-piscine-q1/tests/ex00/diff_clues.txt"
printf '/* Harness. */\nint\tmain(void)\n{\n\tputs("look at the oracle source");\n\treturn (0);\n}\n' \
	> "$WORK/cvq/c-piscine/c-piscine-q1/tests/ex00/diff_q.c"
if st_mine; then
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvq" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvq.out" 2>&1
fi
# cvq_rule_lines TOY HEADLINE PATHRE WANT: the lines of the files matching
# PATHRE that rule's report names, "N N ... ", or with PATHRE empty its
# path:line pairs, held to WANT; a run cut before its verdict line is a
# harness error (2), never a list that merely differs.
cvq_rule_lines() {
	_cqr=$(cvi_rule "$1" "$2")
	[ "$?" -lt 2 ] || { echo "the $1 run stopped before its verdict line"; return 2; }
	if [ -n "$3" ]; then
		_cl=$(printf '%s\n' "$_cqr" | sed -n "s|^ *$3:\([0-9][0-9]*\):.*|\1|p" | tr '\n' ' ')
	else
		_cl=$(printf '%s\n' "$_cqr" | sed -n 's|^ *\([^ :][^ :]*\):\([0-9][0-9]*\):.*|\1:\2|p' | tr '\n' ' ')
	fi
	[ "$_cl" = "$4" ] && return 0
	echo "reported: $_cl"
	echo "want:     $4"
	return 1
}
want_green "conventions: a one-project runner's \"the subject <verb>\" is reported, in awk, continued and marked" -- \
	cvq_rule_lines cvq 'names one project' 'tools/probe_own\.sh' '6 7 9 13 14 23 '
want_out "conventions: ...and in a runner two projects run" \
	'tools/probe_two.sh:4:' -- cvi_rule cvq 'names one project'
want_green "conventions: ...and in one a macro emits, in a branch one flag opens or a here-document" -- \
	cvq_rule_lines cvq 'names one project' 'tools/probe_shared\.sh' \
	'13 16 19 21 22 23 24 25 27 39 46 51 55 69 72 74 76 '
want_broken_none "conventions: ...never what follows a usage comment showing a here-document (V170)" \
	'tools/probe_hdc.sh:' -- cvi_rule cvq 'names one project'
want_out "conventions: ...but a line of a here-document a quoted \$( ) opens" \
	'tools/probe_hdq.sh:5:' -- cvi_rule cvq 'names one project'
want_green "conventions: a BUILD comment naming oracle/src or a .rs file is reported" -- \
	cvq_rule_lines cvq 'BUILD comment names the oracle' 'c-piscine/c-piscine-q2/BUILD\.bazel' '5 9 '
want_green "conventions: ...and one carrying this harness's label, wrapped or typographic" -- \
	cvq_rule_lines cvq 'BUILD comment carries this harness' 'c-piscine/c-piscine-q2/BUILD\.bazel' '6 10 '
want_out "conventions: ...in a module's .bzl file too" \
	'c-piscine/c-piscine-q1/team.bzl:1:' -- cvi_rule cvq 'BUILD comment names the oracle'
_cvq_ref="c-piscine/c-piscine-q1/README.md:1 c-piscine/c-piscine-q1/tests/ex00/cases.tsv:1"
_cvq_ref="$_cvq_ref c-piscine/c-piscine-q1/tests/ex00/toy_shape.c:2 c-piscine/c-piscine-q1/tests/ex00/toy_shape.c:5"
_cvq_ref="$_cvq_ref docs/page.md:1 tools/probe_ref.sh:2 tools/probe_ref.sh:5 tools/probe_ref.sh:7"
_cvq_ref="$_cvq_ref tools/probe_ref.sh:8 tools/probe_ref.sh:9 tools/probe_ref.sh:16 tools/probe_ref.sh:18"
_cvq_ref="$_cvq_ref tools/probe_ref.sh:27 tools/probe_ref.sh:30 tools/probe_ref.sh:31 tools/probe_ref.sh:33"
_cvq_ref="$_cvq_ref tools/probe_ref.sh:41 tools/probe_ref.sh:42 tools/probe_ref.sh:49 tools/probe_ref.sh:54"
_cvq_ref="$_cvq_ref tools/tests/st.sh:1 "
want_green "conventions: a test file's or a runner's comment or printed string naming the oracle's source is reported, and nothing else" -- \
	cvq_rule_lines cvq 'a shipped file names the oracle' '' "$_cvq_ref"
want_green "conventions: a case's clue file, a legend or a diff harness sending a student to the oracle is reported" -- \
	cvq_rule_lines cvq "a runner or a clue points a student at the oracle's source" \
	'c-piscine/c-piscine-q1/tests/ex00/[a-z_]*\.[a-z]*' '1 2 4 '
# And over a copy of that run cut before its verdict line.
! st_mine || sed '/^conventions: /d' "$WORK/cvq.out" > "$WORK/cvqcut.out"
want_broken "conventions: a line reader over a run cut before its verdict is a harness error" \
	'stopped before its verdict' -- cvq_rule_lines cvqcut 'names one project' 'tools/probe_own\.sh' '6 7 9 13 14 23 '
want_out "conventions: libbsd-dev pinned apart from the image's ARG" \
	"pins libbsd-dev at '1.0-1', but .devcontainer/Dockerfile (ARG LIBBSD_DEV_VERSION) says '1.0-2'" -- \
	cvi_rule cvi 'pins libbsd-dev'
want_out "conventions: ...fetched with no digest" \
	'fetches libbsd-dev with no sha256' -- cvi_rule cvi 'fetches libbsd-dev'
want_out "conventions: ...or installed whole, by its apt line" \
	'4: libbsd-dev' -- cvi_rule cvi 'installs a libbsd package'
want_out "conventions: ...or on one line, beside another package" \
	'8: libbsd0' -- cvi_rule cvi 'installs a libbsd package'
want_out "conventions: ...or as a .deb handed to dpkg" \
	'9: /tmp/libbsd-dev.deb' -- cvi_rule cvi 'installs a libbsd package'
want_out "conventions: a Dockerfile-only tool outside the hand-run list" \
	'    libbsd-dev' -- cvi_rule cvi 'what you run by hand does not name'
want_broken_none "conventions: ...never one named in it past a code fence" \
	'widget' -- cvi_rule cvi 'what you run by hand does not name'
want_broken_none "conventions: ...nor one the harness pins elsewhere too" \
	'gadget' -- cvi_rule cvi 'what you run by hand does not name'
want_out "conventions: an image's pip install outside the hand-run list" \
	'    doohickey' -- cvi_rule cvi 'what you run by hand does not name'
want_broken_none "conventions: ...never one the list names" \
	'gizmo' -- cvi_rule cvi 'what you run by hand does not name'
want_out "conventions: ...named at another version than the image's" \
	'gizmo==1.9, where the image installs gizmo==2.0' -- \
	cvi_rule cvi 'gives another version than the image'
want_out "conventions: an image's apt pin MODULE.bazel fetches at another revision" \
	'gcc-10=10.5.0-1ubuntu1~22.04.3, where MODULE.bazel fetches gcc-10_10.5.0-1ubuntu1~22.04.4' -- \
	cvi_rule cvi "the image's apt pin"
want_out "conventions: ...and g++-10, held to gcc-10's" \
	'g++-10=10.5.0-1ubuntu1~22.04.3, where MODULE.bazel fetches gcc-10_10.5.0-1ubuntu1~22.04.4' -- \
	cvi_rule cvi "the image's apt pin"
want_out "conventions: ...and binutils, to binutils-x86-64-linux-gnu's" \
	'binutils=2.38-4ubuntu2.12, where MODULE.bazel fetches binutils-x86-64-linux-gnu_2.38-4ubuntu2.11' -- \
	cvi_rule cvi "the image's apt pin"
want_broken_none "conventions: ...never one at the fetched revision" \
	'make=' -- cvi_rule cvi "the image's apt pin"
want_broken_none "conventions: ...nor one there behind an epoch" \
	'valgrind=' -- cvi_rule cvi "the image's apt pin"
want_broken_none "conventions: ...nor one MODULE.bazel does not fetch" \
	'gdb=' -- cvi_rule cvi "the image's apt pin"
# And a tool only the image installs, held to its pins.tsv row (cvdp).
# Reported, each on the line that holds the word: an apt pin whose version
# the row does not hold (thing, line 6); an ARG whose version is a prefix of
# the row's, no whole version of it (oldsrc, 4.1 against 4.10, line 3) or a
# suffix (leftsrc, 2.0 against 12.0, line 4); an apt pin whose upstream part
# the row names but whose revision is another than the row states (rev,
# line 9: Ubuntu's 3.4-1ubuntu1 where the row says 3.4-1ubuntu2); an apt
# pin that is only a piece of the row's string (piece, line 10: 7 in
# "piece-7 (Toy 7.1-2)"); a row whose pin-site note has a '+' inside its
# parentheses, at another version (noted, line 11); the tool installed
# with no version beside its ARG (srcthing, line 12); and a row the
# Dockerfile installs no version of (ghost). Quiet: an apt pin whose
# upstream part, past its epoch and less its revision, is the row's where
# the row states no revision (tool-12, as lldb-12's), ARGs at the row's
# version read as Docker reads them (srcthing; my-tool, a hyphen as '_';
# lowtool, a lower-case arg, indented and quoted; two on one line, pairtool),
# and a row with a second pin site, which the MODULE.bazel rule above holds
# (shared).
mkdir -p "$WORK/cvdp/tools" "$WORK/cvdp/.devcontainer" "$WORK/cvdp/m"
: > "$WORK/cvdp/m/BUILD.bazel"
cv_submit m > "$WORK/cvdp/tools/submit.sh"
{
	printf 'thing\tcampus\tthing (Toy) 2.0\tthing --version\t.devcontainer/Dockerfile\n'
	printf 'tool-12\tcampus\ttool version 12.0.1\ttool-12 --version\t.devcontainer/Dockerfile\n'
	printf 'srcthing\tcampus\tSrcthing (X) 3.1\tsrcthing --version\t.devcontainer/Dockerfile\n'
	printf 'oldsrc\tcampus\toldsrc 4.10\toldsrc --version\t.devcontainer/Dockerfile\n'
	printf 'leftsrc\tcampus\tleftsrc 12.0\tleftsrc --version\t.devcontainer/Dockerfile\n'
	printf 'my-tool\tcampus\tmy-tool 5.5\tmy-tool --version\t.devcontainer/Dockerfile\n'
	printf 'lowtool\tcampus\tlowtool 6.0\tlowtool --version\t.devcontainer/Dockerfile\n'
	printf 'pairtool\tcampus\tpairtool 8.1\tpairtool --version\t.devcontainer/Dockerfile\n'
	printf 'rev\tcampus\trev (Ubuntu 3.4-1ubuntu2) 3.4\trev --version\t.devcontainer/Dockerfile\n'
	printf 'piece\tcampus\tpiece-7 (Toy 7.1-2)\tpiece --version\t.devcontainer/Dockerfile\n'
	printf 'noted\tcampus\tnoted 1.0\tnoted --version\t.devcontainer/Dockerfile (noted + libnoted)\n'
	printf 'ghost\tcampus\tghost 1.0\tghost --version\t.devcontainer/Dockerfile\n'
	printf 'shared\tcampus\tshared 9.9\tshared --version\tMODULE.bazel + .devcontainer/Dockerfile (apt)\n'
} > "$WORK/cvdp/tools/pins.tsv"
{
	printf 'FROM x\nARG SRCTHING_VERSION=3.1\nARG OLDSRC_VERSION=4.1\nARG LEFTSRC_VERSION=2.0\n'
	printf 'RUN apt-get install -y \\\n    thing=1.9-1ubuntu1 \\\n    # a comment\n    tool-12=1:12.0.1-19ubuntu3 \\\n'
	printf '    rev=3.4-1ubuntu1 \\\n    piece=7 \\\n    noted=0.9 \\\n    srcthing \\\n    shared=1.0 \\\n    && true\n'
	printf 'ARG MY_TOOL_VERSION=5.5\n  arg LOWTOOL_VERSION="6.0"\nARG PAIRTOOL_VERSION=8.1 PAIRTOOL_SHA256=abc\n'
} > "$WORK/cvdp/.devcontainer/Dockerfile"
if st_mine; then
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvdp" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvdp.out" 2>&1
fi
want_out "conventions: a tool only the image installs, at another version than its row" \
	'.devcontainer/Dockerfile:6: thing=1.9-1ubuntu1, where tools/pins.tsv pins thing at "thing (Toy) 2.0"' -- \
	cvi_rule cvdp 'the image installs a tool only it pins'
want_out "conventions: ...an ARG whose version is a prefix of the row's" \
	'.devcontainer/Dockerfile:3: OLDSRC_VERSION=4.1, where tools/pins.tsv pins oldsrc at "oldsrc 4.10"' -- \
	cvi_rule cvdp 'the image installs a tool only it pins'
want_out "conventions: ...or a suffix of it" \
	'.devcontainer/Dockerfile:4: LEFTSRC_VERSION=2.0, where tools/pins.tsv pins leftsrc' -- \
	cvi_rule cvdp 'the image installs a tool only it pins'
want_out "conventions: ...an apt pin at another revision than the row states" \
	'.devcontainer/Dockerfile:9: rev=3.4-1ubuntu1, where tools/pins.tsv pins rev' -- \
	cvi_rule cvdp 'the image installs a tool only it pins'
want_out "conventions: ...an apt pin that is only a piece of the row's string" \
	'.devcontainer/Dockerfile:10: piece=7, where tools/pins.tsv pins piece' -- \
	cvi_rule cvdp 'the image installs a tool only it pins'
want_out "conventions: ...a row with a '+' in its pin-site note" \
	'.devcontainer/Dockerfile:11: noted=0.9, where tools/pins.tsv pins noted' -- \
	cvi_rule cvdp 'the image installs a tool only it pins'
want_out "conventions: ...the tool installed with no version beside its pin" \
	'.devcontainer/Dockerfile:12: srcthing, with no version, beside its pin' -- \
	cvi_rule cvdp 'the image installs a tool only it pins'
want_out "conventions: ...and a row the image installs no version of" \
	'ghost: tools/pins.tsv names .devcontainer/Dockerfile its pin site' -- \
	cvi_rule cvdp 'the image installs a tool only it pins'
want_broken_none "conventions: ...never an apt pin whose upstream part, past its epoch, is a row's with no revision" \
	'tool-12' -- cvi_rule cvdp 'the image installs a tool only it pins'
want_broken_none "conventions: ...nor an ARG at the row's version" \
	'SRCTHING_VERSION' -- cvi_rule cvdp 'the image installs a tool only it pins'
want_broken_none "conventions: ...nor one for a tool named with a hyphen" \
	'my-tool' -- cvi_rule cvdp 'the image installs a tool only it pins'
want_broken_none "conventions: ...nor an indented lower-case arg, quoted" \
	'lowtool' -- cvi_rule cvdp 'the image installs a tool only it pins'
want_broken_none "conventions: ...nor two ARGs on one line" \
	'pairtool' -- cvi_rule cvdp 'the image installs a tool only it pins'
want_broken_none "conventions: ...nor a row with a second pin site" \
	'shared' -- cvi_rule cvdp 'the image installs a tool only it pins'
want_out "conventions: an image's pip pin tools/requirements.txt pins at another version" \
	'gizmo==2.0, where tools/requirements.txt pins gizmo==2.1' -- \
	cvi_rule cvi "the image's pip pin"
want_out "conventions: ...its name read in any case, as pip reads it" \
	'doohickey==1.0, where tools/requirements.txt pins Doohickey==1.1' -- \
	cvi_rule cvi "the image's pip pin"
want_broken_none "conventions: ...never one at the same version, its name spelt otherwise" \
	'Whatsit' -- cvi_rule cvi "the image's pip pin"
want_broken_none "conventions: ...nor one the image does not install" \
	'thingamajig' -- cvi_rule cvi "the image's pip pin"
want_out "conventions: no hand-run list at all, naming what it must hold" \
	"for a student's own hands alone: widget libbsd-dev" -- \
	cvi_rule cvj 'has no section "What the docs ask you to run by hand"'
want_broken_none "conventions: ...and an image whose pages agree is not reported" \
	'libbsd' -- cvi_rule cvj 'libbsd'
want_out "conventions: a subject's libbsd-only function, its page not in the image" \
	'turns in ft_strnstr.c, and the image has no strnstr.3bsd' -- \
	cvi_rule cvi 'does not carry the manual page'
want_broken_none "conventions: ...never one whose page the image extracts" \
	'strlcpy' -- cvi_rule cvj 'does not carry the manual page'
want_out "conventions: a printed clue sending a student to man strlcat, bare" \
	'tests/ex00/clues.tsv:3: man strlcat' -- cvi_rule cvi 'a printed clue sends'
want_broken_none "conventions: ...never a '#' line, which is not printed" \
	'clues.tsv:1:' -- cvi_rule cvi 'a printed clue sends'
want_broken_none "conventions: ...nor one with the section and the fallback" \
	'clues.tsv:2:' -- cvi_rule cvi 'a printed clue sends'
want_out "conventions: a runner's compiler defaulting to one from the box" \
	'tools/toy_check.sh:1: CC="${TOY_CC:-toycc-9}"' -- \
	cvi_rule cvi 'a runner compiles with a compiler from PATH'
want_broken_none "conventions: ...never a runner handed the pinned one" \
	'toycc-8' -- cvi_rule cvi 'a runner compiles with a compiler from PATH'
want_out "conventions: ...and one the no-Docker paragraph names all the same" \
	'tools/toy_check.sh:1: CC="${TOY_CC:-toycc-9}"' -- \
	cvi_rule cvj 'a runner compiles with a compiler from PATH'
want_out "conventions: a doc's unmarked whole-repo test is reported" \
	'README.md:4: bazel test //... 2>&1 | sh tools/first_red.sh' -- \
	cvi_rule cvi 'a doc shows a whole-repo test run'
want_out "conventions: ...with a flag before the pattern too" \
	'README.md:5: bazel test --test_output=errors //...' -- \
	cvi_rule cvi 'a doc shows a whole-repo test run'
want_broken_none "conventions: ...never one in prose" \
	'README.md:1:' -- cvi_rule cvi 'a doc shows a whole-repo test run'
want_out "conventions: ...and one that says so only in a note on its line" \
	'README.md:6: bazel test //...' -- cvi_rule cvi 'a doc shows a whole-repo test run'
want_broken_none "conventions: ...nor one its paragraph says needs memory" \
	'README.md:14:' -- cvi_rule cvi 'a doc shows a whole-repo test run'
want_broken_none "conventions: ...nor a module's /..." \
	'README.md:7:' -- cvi_rule cvi 'a doc shows a whole-repo test run'
want_broken_none "conventions: ...nor TODO.md's, a record" \
	'TODO.md' -- cvi_rule cvi 'a doc shows a whole-repo test run'
want_out "conventions: ...and one in a tilde fence (V140)" \
	'docs/fence_tilde.md:4: bazel test //...' -- cvi_rule cvi 'a doc shows a whole-repo test run'
want_out "conventions: ...one a shorter fence inside a longer one leaves in its block" \
	'docs/fence_four.md:7: bazel test //...' -- cvi_rule cvi 'a doc shows a whole-repo test run'
want_out "conventions: ...and one whose paragraph a tilde block ends" \
	'docs/fence_leak.md:7: bazel test //...' -- cvi_rule cvi 'a doc shows a whole-repo test run'
want_out "conventions: a '#' note in a page's shell block is reported" \
	'docs/paste.md:5: make && make' -- cvi_rule cvi "a shell block in a page holds a '#' note"
want_out "conventions: ...and a line that is only a note" \
	'docs/paste.md:9: # a note alone' -- cvi_rule cvi "a shell block in a page holds a '#' note"
want_out "conventions: ...and one in a console block inside a list" \
	'docs/paste.md:15:   $ ls   # a note' -- cvi_rule cvi "a shell block in a page holds a '#' note"
want_out "conventions: ...and one in a block fenced with tildes" \
	'docs/paste.md:19: ls  # a note' -- cvi_rule cvi "a shell block in a page holds a '#' note"
want_out "conventions: ...and the whole-repo test's note in README.md" \
	'README.md:6: bazel test //...' -- cvi_rule cvi "a shell block in a page holds a '#' note"
want_broken_none "conventions: ...never a script's #! line" \
	'docs/paste.md:4:' -- cvi_rule cvi "a shell block in a page holds a '#' note"
for _zl in 23 25 26 27 29 30; do
	want_broken_none "conventions: ...nor a quoted, escaped, inner or heredoc '#' (line $_zl)" \
		"docs/paste.md:$_zl:" -- cvi_rule cvi "a shell block in a page holds a '#' note"
done
want_broken_none "conventions: ...nor a C block's #include" \
	'docs/paste.md:35:' -- cvi_rule cvi "a shell block in a page holds a '#' note"
want_broken_none "conventions: ...nor an unmarked block's note" \
	'docs/paste.md:39:' -- cvi_rule cvi "a shell block in a page holds a '#' note"
want_broken_none "conventions: ...nor a heading in prose" \
	'docs/paste.md:42:' -- cvi_rule cvi "a shell block in a page holds a '#' note"
want_broken_none "conventions: ...nor any line of a page with none" \
	'README.md' -- cvi_rule cvj "a shell block in a page holds a '#' note"
want_out "conventions: a block's bare \$m set to several words is reported" \
	'docs/split.md:3: bazel test $m' -- cvi_rule cvi 'a shell block expands a variable it set to several words'
want_out "conventions: ...and its \${m}" \
	'docs/split.md:8: bazel test ${m} -k' -- cvi_rule cvi 'a shell block expands a variable it set to several words'
for _zl in 4 5 7 9 13 17; do
	want_broken_none "conventions: ...never quoted, one word or unset (line $_zl)" \
		"docs/split.md:$_zl:" -- cvi_rule cvi 'a shell block expands a variable it set to several words'
done
want_broken_none "conventions: ...nor any line of a tree with none" \
	'.md:' -- cvi_rule cvj 'a shell block expands a variable it set to several words'
want_out "conventions: a usage line's '#' note in a script is reported" \
	'tools/paste_note.sh:4: #   sh tools/paste_note.sh --all' -- cvi_rule cvi "a script shows a command to type with a '#' note"
want_out "conventions: ...and one naming the script alone" \
	'tools/paste_note.sh:5: #   paste_note.sh -n' -- cvi_rule cvi "a script shows a command to type with a '#' note"
want_out "conventions: ...and an echoed command's" \
	'tools/paste_note.sh:11: echo "      rm -rf dir' -- cvi_rule cvi "a script shows a command to type with a '#' note"
want_out "conventions: ...and a printf's" \
	'tools/paste_note.sh:12: printf "  %s  # a note' -- cvi_rule cvi "a script shows a command to type with a '#' note"
for _zl in 7 8 10 13 14 15 16; do
	want_broken_none "conventions: ...never a note before, prose, # define or a comment (line $_zl)" \
		"tools/paste_note.sh:$_zl:" -- cvi_rule cvi "a script shows a command to type with a '#' note"
done
want_out "conventions: ...and a '# Usage:' block's line, whatever its first word" \
	'tools/usage_note.sh:5: #   make -C toy' -- cvi_rule cvi "a script shows a command to type with a '#' note"
want_out "conventions: ...with one blank before its note" \
	'tools/usage_note.sh:6: #   cc -Wall a.c' -- cvi_rule cvi "a script shows a command to type with a '#' note"
want_out "conventions: ...and a usage line's continuation" \
	'tools/usage_note.sh:8: #       [-R CheckDefine]' -- cvi_rule cvi "a script shows a command to type with a '#' note"
for _zl in 7 10; do
	want_broken_none "conventions: ...never a usage line with no note, nor past the block (line $_zl)" \
		"tools/usage_note.sh:$_zl:" -- cvi_rule cvi "a script shows a command to type with a '#' note"
done
want_out "conventions: ...and the command on the '# Usage:' line itself (V157)" \
	'tools/usage_tail.sh:2: # Usage: make -C toy' -- cvi_rule cvi "a script shows a command to type with a '#' note"
want_out "conventions: ...a script's own name there too" \
	'tools/usage_tail.sh:4: # Usage: usage_tail.sh -x' -- cvi_rule cvi "a script shows a command to type with a '#' note"
want_broken_none "conventions: ...never one with no note" \
	'tools/usage_tail.sh:3:' -- cvi_rule cvi "a script shows a command to type with a '#' note"
want_broken_none "conventions: ...nor any line of a tree with none" \
	'.sh:' -- cvi_rule cvj "a script shows a command to type with a '#' note"
want_out "conventions: a '#' note after a session's prompt is reported" \
	'docs/session.md:2: $ ls' -- cvi_rule cvi "a session in a page's block holds a '#' note"
want_out "conventions: ...and after gdb's" \
	'docs/session.md:3: (gdb) bt' -- cvi_rule cvi "a session in a page's block holds a '#' note"
want_out "conventions: ...and after lldb's" \
	'docs/session.md:4: (lldb) run' -- cvi_rule cvi "a session in a page's block holds a '#' note"
for _zl in 5 6 7 11; do
	want_broken_none "conventions: ...never quoted, inside a word, output or marked (line $_zl)" \
		"docs/session.md:$_zl:" -- cvi_rule cvi "a session in a page's block holds a '#' note"
done
want_broken_none "conventions: ...nor any line of a tree with none" \
	'.md:' -- cvi_rule cvj "a session in a page's block holds a '#' note"
want_out "conventions: a shipped file citing a backlog section is named" \
	'tools/cite.sh:1:' -- cvi_rule cvi 'cites a section or an item of TODO.md'
want_out "conventions: ...and one wrapped after the file's name" \
	'tools/cite.sh:2:' -- cvi_rule cvi 'cites a section or an item of TODO.md'
want_out "conventions: ...and the record's, by lead" \
	'tools/cite.sh:4:' -- cvi_rule cvi 'cites a section or an item of TODO.md'
want_out "conventions: ...and an item of the old board" \
	'tools/cite.sh:5:' -- cvi_rule cvi 'cites a section or an item of TODO.md'
want_out "conventions: ...and one wrapped before its number" \
	'tools/cite.sh:6:' -- cvi_rule cvi 'cites a section or an item of TODO.md'
want_broken_none "conventions: ...never a mention that cites nothing" \
	'tools/cite.sh:8:' -- cvi_rule cvi 'cites a section or an item of TODO.md'
want_broken_none "conventions: ...nor a tag named bare" \
	'tools/cite.sh:9:' -- cvi_rule cvi 'cites a section or an item of TODO.md'
want_out "conventions: a file under the records' folder, by its path" \
	'tools/cite.sh:10:' -- cvi_rule cvi 'cites a section or an item of TODO.md'
want_out "conventions: ...and from ./" \
	'tools/cite.sh:11:' -- cvi_rule cvi 'cites a section or an item of TODO.md'
for _zl in 12 13 14; do
	want_broken_none "conventions: ...never a pattern, the folder bare or a toy's path (line $_zl)" \
		"tools/cite.sh:$_zl:" -- cvi_rule cvi 'cites a section or an item of TODO.md'
done
for _zl in 15 16 17 18; do
	want_out "conventions: ...and from ../, in a URL, or with a section after it (line $_zl)" \
		"tools/cite.sh:$_zl:" -- cvi_rule cvi 'cites a section or an item of TODO.md'
done
want_broken_none "conventions: ...nor TODO.md's own" \
	'TODO.md:' -- cvi_rule cvi 'cites a section or an item of TODO.md'
want_out "conventions: a comment saying a CI runs the checks, with none" \
	'tools/ci.sh:1:' -- cvi_rule cvi 'says a CI runs the checks'
want_out "conventions: ...and one wrapped before its last word" \
	'tools/ci.sh:2:' -- cvi_rule cvi 'says a CI runs the checks'
want_broken_none "conventions: ...never one saying there is none" \
	'tools/ci.sh:4:' -- cvi_rule cvi 'says a CI runs the checks'
want_broken_none "conventions: ...nor any, once a workflow is there" \
	'tools/ci.sh' -- cvi_rule cvj 'says a CI runs the checks'
want_out "conventions: a full run's size quoted outside drives.sh" \
	'tools/size.sh:1:' -- cvi_rule cvi "quotes a full run's size"
want_out "conventions: ...and a build tree's, with no space" \
	'tools/size.sh:3:' -- cvi_rule cvi "quotes a full run's size"
want_broken_none "conventions: ...never another size" \
	'tools/size.sh:2:' -- cvi_rule cvi "quotes a full run's size"
want_broken_none "conventions: ...nor drives.sh's, which keeps it" \
	'tools/drives.sh:' -- cvi_rule cvi "quotes a full run's size"
want_broken_none "conventions: ...nor TODO.md's" \
	'TODO.md:' -- cvi_rule cvi "quotes a full run's size"
want_out "conventions: the prime's scratch derived outside drives.sh" \
	'tools/scratch.sh:1:' -- cvi_rule cvi "derives the prime's scratch"
want_broken_none "conventions: ...never in drives.sh, which keeps it" \
	'tools/drives.sh:' -- cvi_rule cvi "derives the prime's scratch"
want_out "conventions: an editor whose default test runs the whole repo, in its args" \
	'the default test task runs the whole repo: "Toy: test all"' -- \
	cvi_rule cvi 'tasks.json sends a newcomer to the whole repo'
want_out "conventions: ...and a whole-repo task that does not say so" \
	'its label does not say so: "Toy: test everything"' -- \
	cvi_rule cvi 'tasks.json sends a newcomer to the whole repo'
want_broken_none "conventions: ...never a module default and a marked task" \
	'whole repo' -- cvi_rule cvj 'whole'
want_out "conventions: a runner printing a whole-repo test" \
	'tools/toy_check.sh:2:' -- cvi_rule cvi 'a runner prints a whole-repo test'
want_broken_none "conventions: ...never in a comment" \
	'toy_check.sh:3:' -- cvi_rule cvi 'a runner prints a whole-repo test'
want_broken_none "conventions: ...nor one whose printed line before says it needs memory" \
	'toy_check.sh:5:' -- cvi_rule cvi 'a runner prints a whole-repo test'
want_out "conventions: ...but one saying so only in a '#' note on its line" \
	'tools/toy_check.sh:6:' -- cvi_rule cvi 'a runner prints a whole-repo test'
want_out "conventions: ...or in a comment before it, which is never printed" \
	'tools/toy_check.sh:8:' -- cvi_rule cvi 'a runner prints a whole-repo test'
want_broken_none "conventions: ...and the quiet one's command shows no '#' note to zsh" \
	'toy_check.sh:5:' -- cvi_rule cvi "a script shows a command to type with a '#' note"
want_out "conventions: a doc naming an editor task the file does not have" \
	'README.md:17: `Toy: test it all`' -- \
	cvi_rule cvi 'a doc names an editor task'
want_broken_none "conventions: ...never one it has" \
	'`Toy: test everything`' -- cvi_rule cvi 'a doc names an editor task'
want_broken_none "conventions: ...nor, in a repo whose docs name its labels, any" \
	'Toy' -- cvi_rule cvj 'a doc names an editor task'
want_out "conventions: a docstring saying nothing in the repo does it" \
	'tools/toy.bzl:5:' -- cvi_rule cvi "a macro's docstring says what no call site does"
want_out "conventions: ...and no call site, wrapped before its verb" \
	'tools/toy.bzl:6:' -- cvi_rule cvi "a macro's docstring says what no call site does"
want_out "conventions: ...and every existing call site, wrapped" \
	'tools/toy.bzl:10:' -- cvi_rule cvi "a macro's docstring says what no call site does"
for _cs in 8 9; do
	want_broken_none "conventions: ...never no project, nor nearly every call site (line $_cs)" \
		"tools/toy.bzl:$_cs:" -- cvi_rule cvi "a macro's docstring says what no call site does"
done
for _cs in 7 11; do
	want_broken_none "conventions: ...nor a wrapped phrase's second line (line $_cs)" \
		"tools/toy.bzl:$_cs:" -- cvi_rule cvi "a macro's docstring says what no call site does"
done
want_out "conventions: a C file pointing at diffio.h without including it" \
	'c-piscine/c-piscine-c-88/tests/ex00/toy_rush.c:2' -- \
	cvi_rule cvi 'a C file sends its reader to tools/diffio.h and does not include it'
want_broken_none "conventions: ...never one that includes it" \
	'toy_line.c' -- cvi_rule cvi 'a C file sends its reader to tools/diffio.h and does not include it'
want_broken_none "conventions: ...nor the zone's copy" \
	'c-piscine/c-piscine-c-88/deliverable/ex00/toy_rush.c:2' -- \
	cvi_rule cvi 'a C file sends its reader to tools/diffio.h and does not include it'

