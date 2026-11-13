# ------------------------------------- conventions: a project's own page, docs
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A group project and a Common Core one each have a page of their own
# (findings 175, 178: BSQ had none, and its open questions sat in BUILD
# comments). cvp holds five toy projects: a group one with no page
# (reported), a group one with its README.md, a rush whose only page is its
# section of docs/rushes.md (reported: the rushes were let off so once, and
# their sections are their READMEs now), a one-person Piscine project with no
# page (both quiet), and a Common Core project with none (reported). The contract
# lines are a subject() call's, as a project's BUILD file writes them. And a
# sixth, cursus/newproj, a Common Core project with no page that nobody has
# put in the REMOTES table yet: the page rule walked the table alone and
# never saw it, and nothing said it was missing from the table either.
_cvp_mods="c-piscine/c-piscine-c-87 c-piscine/c-piscine-c-86 c-piscine/c-piscine-rush-87 c-piscine/c-piscine-c-85 cursus/toyproj"
mkdir -p "$WORK/cvp/tools" "$WORK/cvp/docs"
for _m in $_cvp_mods cursus/newproj; do mkdir -p "$WORK/cvp/$_m"; done
cv_submit "$_cvp_mods" > "$WORK/cvp/tools/submit.sh"
: > "$WORK/cvp/cursus/newproj/BUILD.bazel"
for _m in c-piscine/c-piscine-c-87 c-piscine/c-piscine-c-86 c-piscine/c-piscine-rush-87; do
	printf 'subject(\n    grader = "defense",\n    group = True,\n    exercises = {},\n)\n' \
		> "$WORK/cvp/$_m/BUILD.bazel"
done
printf 'subject(\n    grader = "moulinette",\n    group = False,\n    exercises = {},\n)\n' \
	> "$WORK/cvp/c-piscine/c-piscine-c-85/BUILD.bazel"
: > "$WORK/cvp/cursus/toyproj/BUILD.bazel"
printf '# c-piscine-c-86\n' > "$WORK/cvp/c-piscine/c-piscine-c-86/README.md"
printf '# The rushes\n\n## rush-87 — a toy\n' > "$WORK/cvp/docs/rushes.md"
# A project in a course folder that no module of the table lives in yet
# (c-piscine-toy/c-piscine-toy-00, its BUILD file opening with its
# contract): the rule walked the course folders of the table's modules and
# cursus/, so a new course's first project was seen by none of the rules
# that walk those folders until someone put it in the table, the very step
# the rule exists to ask for.
mkdir -p "$WORK/cvp/c-piscine-toy/c-piscine-toy-00"
printf 'subject(\n    grader = "moulinette",\n    group = False,\n    exercises = {},\n)\n' \
	> "$WORK/cvp/c-piscine-toy/c-piscine-toy-00/BUILD.bazel"
# And //tools:generate, whose args are the projects it regenerates, written
# by hand: C 85 and C 87 have a generators/ folder, and the args name C 85
# and C 86, which has none. Another target before it names C 87, so a
# reading that ran past the generate target's own call would find it.
for _m in c-piscine/c-piscine-c-85 c-piscine/c-piscine-c-87; do
	mkdir -p "$WORK/cvp/$_m/generators"
	printf '#!/bin/sh\n# ex00: a toy.\n:\n' > "$WORK/cvp/$_m/generators/ex00.sh"
done
{
	printf 'sh_binary(\n    name = "other",\n    srcs = ["other.sh"],\n    args = ["c-piscine/c-piscine-c-87"],\n)\n\n'
	printf 'sh_binary(\n    name = "generate",\n    srcs = ["generate.sh"],\n    args = [\n'
	printf '        "c-piscine/c-piscine-c-85",\n        "c-piscine/c-piscine-c-86",\n    ],\n)\n'
} > "$WORK/cvp/tools/BUILD.bazel"
# And two checks with nothing to read: C 85's BUILD file names a test main
# that is not there to read, and its one clues.tsv has neither an
# expected.txt nor a program case to give it labels. Each check passed
# having read nothing, as the dead-label one did under `bazel test` until
# the expected outputs were declared to it.
printf 'c_test(\n    num = "00",\n    test = "test_toy.c",\n)\n' \
	>> "$WORK/cvp/c-piscine/c-piscine-c-85/BUILD.bazel"
mkdir -p "$WORK/cvp/c-piscine/c-piscine-c-85/tests/ex00"
printf 'What does line 1 print?\tline 1\n' > "$WORK/cvp/c-piscine/c-piscine-c-85/tests/ex00/clues.tsv"
# And the checklist for a new project (WP-74), which says what holds each of
# its items, by name. Line 3, a load-time check tools/defs.bzl defines, and
# a table it assigns; line 5, one it does not define and one it does not
# assign, wrapped across the item's lines; line 7, an item that says
# neither "Checked by:" nor "(unchecked)"; line 8, one that is unchecked;
# line 9, a rule of conventions.sh quoted by its heading's start, one headed
# in capitals and no number ("A CR IN ..."), and one no heading starts with;
# line 12, a subject's words in the same shape, before "Checked by:", which
# name no rule, and after it the headline a rule reports of a selftest file,
# "..." for what it fills in, wrapped across the item's lines; line 15, a
# quote that ends two such headlines, which holds one of them. AGENTS.md
# never names the page.
mkdir -p "$WORK/cvp/tools"
printf 'def toy_problem(x):\n    return None\n\n_TOY_TABLE = {}\n' > "$WORK/cvp/tools/defs.bzl"
{
	printf '# Adding a project\n\n'
	printf '1. **A.** Checked by: `toy_problem`, from `_TOY_TABLE`.\n'
	printf '2. **B.** Checked by: `gone_problem`, from\n'
	printf '   `_GONE_TABLE`.\n'
	printf '\n'
	printf '3. **C.** Nothing says what holds it.\n'
	printf '4. **D.** (unchecked)\n'
	printf '5. **E.** Checked by: `//tools:conventions` ("Every work package in the\n'
	printf '   records"), ("A CR IN A FILE GIT WOULD REWRITE"), ("A clues.tsv is\n'
	printf '   read by rl_clues") and ("No rule is headed this way").\n'
	printf '6. **F.** A function the grader brings ("we will use our x") is linked.\n'
	printf '   Checked by: `toy_problem`, and the rule that "calls ... and never\n'
	printf '   defines it".\n'
	printf '7. **G.** Checked by: `toy_problem`, and the rule on a toy "in two sections".\n'
} > "$WORK/cvp/docs/new-project.md"
# A plan whose work packages say where they stand, but the second (line 4);
# and the fifth (line 7) is marked DONE with something left, which is PARTLY
# DONE (WP-83 and WP-88 once were).
printf '# TODO\n\n- WP-01 [P0 M] a package -- 001 [DONE in wave 1]\n- WP-02 [P1 S] another -- 002\n- WP-03 [P2 L] a third -- 003 [PARTLY DONE: one thing left]\n- WP-04 [P3 S] a fourth -- 004 [OPEN]\n- WP-05 [P1 M] a fifth -- 005 [DONE in wave 2; left: one thing]\n' \
	> "$WORK/cvp/TODO.md"
# And its retro-audit of the checklist above (items 1-6): a row for item 9,
# which the checklist does not have, and none for items 5 and 6. Shaped as
# TODO.md writes it: the table at the margin, its follow-ups indented, and
# after them a bold line that is no bullet ("**Packages**"), past which a
# "| 5 |" row belongs to some other table. The scan once stopped only at the
# next "- **" bullet, which TODO.md does not have, and read to the end.
printf '\n- **Retro-audit, today.** The rows.\n\n| # | item | held by |\n|---|---|---|\n| 1 | A | x |\n| 2 | B | x |\n| 3 | C | x |\n| 4 | D | x |\n| 9 | I | x |\n\n  Follow-ups, one per gap:\n  - **G1** (item 3): a gap.\n\n**Packages**\n\n| 5 | not a row of the audit |\n' \
	>> "$WORK/cvp/TODO.md"
# AGENTS.md names a table tools/defs.bzl assigns and one it does not, a
# load-time check it defines and one it does not. It never names the one file
# conventions.sh's TURNIN_FN_ALLOW exempts (Reloaded's ft_putchar.c), so that
# exemption is reported: a second one added to the script alone would be an
# exception AGENTS.md says does not exist.
printf '# AGENTS.md\n\nRead the docs. A raise goes in `_TOY_TABLE`, a manual test in\n`_GONE_LIST`. `toy_problem` refuses it, `gone_problem` too.\n' \
	> "$WORK/cvp/AGENTS.md"
# Projects one level deeper, as the Common Core groups them
# (cursus/Milestone_0/Libft): cursus/Group_9/deepproj, which opens its
# contract, has no page and no row in the table; and c-piscine-deep, a course
# folder whose one project is at that depth. A project folder's own folders
# hold no other project (deepproj/sub/), and neither does tools/, whose macro
# fixtures open a contract as a project does, nor docs/. The walk read
# <course>/<project>/ alone, and saw none of the deep ones.
mkdir -p "$WORK/cvp/cursus/Group_9/deepproj/sub" "$WORK/cvp/c-piscine-deep/Group_1/c-piscine-deep-00" \
	"$WORK/cvp/tools/tests/mf/levels/deliverable" "$WORK/cvp/docs/x/y"
for _m in cursus/Group_9/deepproj c-piscine-deep/Group_1/c-piscine-deep-00 tools/tests/mf/levels docs/x/y; do
	printf 'subject(\n    grader = "moulinette",\n    group = False,\n    exercises = {},\n)\n' \
		> "$WORK/cvp/$_m/BUILD.bazel"
done
: > "$WORK/cvp/cursus/Group_9/deepproj/sub/BUILD.bazel"
# And three scripts that walk the course folders by name, as the header
# re-stamp and the stub check do: one whose COURSE_NAMES leaves out
# c-piscine-toy, the course folder above (reported, by name); one that
# lists it (quiet); and a reset_headers.sh whose loop hand-lists the
# folders, with no COURSE_NAMES line to hold to the tree (reported). Only
# conventions' own list of course folders discovered the tree; these lists
# were each written by hand, and a new course went unwalked by all of them.
printf '#!/bin/sh\nCOURSE_NAMES="c-piscine cursus"\n' > "$WORK/cvp/tools/walk_some.sh"
printf '#!/bin/sh\nCOURSE_NAMES="c-piscine c-piscine-deep c-piscine-toy cursus"\n' > "$WORK/cvp/tools/walk_all.sh"
printf '#!/bin/sh\nfor _c in c-piscine cursus; do\n\t:\ndone\n' > "$WORK/cvp/tools/reset_headers.sh"
if st_mine; then
	env BUILD_WORKSPACE_DIRECTORY="$WORK/cvp" "$SH" "$TOOLS/conventions.sh" > "$WORK/cvp.out" 2>&1
fi
want_out "conventions: a group project with no page of its own is reported" \
	'    c-piscine/c-piscine-c-87' -- cvi_rule cvp 'has no page of its own'
want_out "conventions: ...and a Common Core project with none" \
	'    cursus/toyproj' -- cvi_rule cvp 'has no page of its own'
want_broken_none "conventions: ...never one with its README.md" \
	'c-piscine-c-86' -- cvi_rule cvp 'has no page of its own'
want_out "conventions: ...and a rush whose only page is a section of docs/rushes.md" \
	'    c-piscine/c-piscine-rush-87' -- cvi_rule cvp 'has no page of its own'
want_broken_none "conventions: ...nor a one-person Piscine project" \
	'c-piscine-c-85' -- cvi_rule cvp 'has no page of its own'
want_out "conventions: ...nor misses a project the REMOTES table does not list" \
	'    cursus/newproj' -- cvi_rule cvp 'has no page of its own'
want_out "conventions: a project folder missing from the REMOTES table" \
	'    cursus/newproj' -- cvi_rule cvp 'has no row in tools/submit.sh'
want_broken_none "conventions: ...never one the table lists" \
	'toyproj' -- cvi_rule cvp 'has no row in tools/submit.sh'
want_out "conventions: ...and one in a course folder the table does not name" \
	'    c-piscine-toy/c-piscine-toy-00' -- cvi_rule cvp 'has no row in tools/submit.sh'
want_out "conventions: ...and one a level deeper, in a group folder" \
	'    cursus/Group_9/deepproj' -- cvi_rule cvp 'has no row in tools/submit.sh'
want_out "conventions: ...and one a level deeper in a course of its own" \
	'    c-piscine-deep/Group_1/c-piscine-deep-00' -- cvi_rule cvp 'has no row in tools/submit.sh'
want_broken_none "conventions: ...never a folder inside a project" \
	'deepproj/sub' -- cvi_rule cvp 'has no row in tools/submit.sh'
want_broken_none "conventions: ...nor tools/'s fixtures, or docs/" \
	'/levels' -- cvi_rule cvp 'has no row in tools/submit.sh'
want_out "conventions: a deep Common Core project with no page is reported" \
	'    cursus/Group_9/deepproj' -- cvi_rule cvp 'has no page of its own'
want_out "conventions: a project with generators/ that //tools:generate skips" \
	'c-piscine/c-piscine-c-87: has a generators/ folder' -- \
	cvi_rule cvp "//tools:generate's args"
want_out "conventions: ...and one it names that has none" \
	'c-piscine/c-piscine-c-86: named by //tools:generate' -- \
	cvi_rule cvp "//tools:generate's args"
want_broken_none "conventions: ...never one it names that has one" \
	'c-piscine-c-85' -- cvi_rule cvp "//tools:generate's args"
want_out "conventions: a test-main check that read none of the mains named" \
	'name one on 1 line(s)' -- cvi_rule cvp 'the test-main check read no test_*.c'
want_out "conventions: a dead-label check that compared no clues.tsv" \
	'compared none of the 1 clues.tsv' -- cvi_rule cvp 'the dead-label check compared none'
want_broken_none "conventions: ...never one that found some" \
	'found no clues.tsv' -- cvi_rule cvp 'the dead-label check'
want_out "conventions: a script's COURSE_NAMES without a course folder of the tree" \
	'    tools/walk_some.sh: c-piscine-toy' -- cvi_rule cvp 'COURSE_NAMES misses a course folder'
want_out "conventions: ...nor a course folder whose project is a level deeper" \
	'    tools/walk_some.sh: c-piscine-deep' -- cvi_rule cvp 'COURSE_NAMES misses a course folder'
want_broken_none "conventions: ...never one that lists them all" \
	'walk_all' -- cvi_rule cvp 'COURSE_NAMES misses a course folder'
want_broken_none "conventions: ...and tools/, which holds fixtures, is no course" \
	': tools' -- cvi_rule cvp 'COURSE_NAMES misses a course folder'
want_broken_none "conventions: ...nor docs/" \
	': docs' -- cvi_rule cvp 'COURSE_NAMES misses a course folder'
want_out "conventions: ...and a course walker with no COURSE_NAMES to read" \
	'    tools/reset_headers.sh' -- cvi_rule cvp 'walks the course folders by a list'
want_out "conventions: a checklist item that says nothing holds it" \
	'docs/new-project.md:7: item 3 says neither' -- \
	cvi_rule cvp 'docs/new-project.md promises a check'
want_out "conventions: ...a load-time check no .bzl defines, wrapped or not" \
	'`gone_problem` is no function' -- cvi_rule cvp 'docs/new-project.md promises a check'
want_out "conventions: ...a table no .bzl assigns" \
	'`_GONE_TABLE` is no table' -- cvi_rule cvp 'docs/new-project.md promises a check'
want_out "conventions: ...a rule no heading of conventions.sh starts with" \
	'("No rule is headed this way") opens the heading of no rule' -- \
	cvi_rule cvp 'docs/new-project.md promises a check'
want_out "conventions: ...and an AGENTS.md that never sends an agent there" \
	'AGENTS.md never names docs/new-project.md' -- \
	cvi_rule cvp 'docs/new-project.md promises a check'
want_broken_none "conventions: ...never a check that exists, or an unchecked item" \
	'toy_problem' -- cvi_rule cvp 'docs/new-project.md promises a check'
want_broken_none "conventions: ...nor a table that is assigned" \
	'_TOY_TABLE' -- cvi_rule cvp 'docs/new-project.md promises a check'
want_broken_none "conventions: ...nor a rule quoted by its heading's start" \
	'Every work package' -- cvi_rule cvp 'docs/new-project.md promises a check'
want_broken_none "conventions: ...nor one headed in capitals, with no number" \
	'A CR IN' -- cvi_rule cvp 'docs/new-project.md promises a check'
want_broken_none "conventions: ...nor a subject's words before Checked by" \
	'we will use' -- cvi_rule cvp 'docs/new-project.md promises a check'
# The other way round: a rule that holds a runner to tools/runner_lib.sh and
# that no item quotes (rl_udiff's and rl_sanitized's were added to the script
# and not to the page), beside one item 5 quotes. The rules are this script's
# own, so the toy page leaves most of them out.
want_out "conventions: a runner_lib rule no checklist item quotes" \
	"rule \"A diff a log shows is made and shown by tools/runner_lib.sh's rl_udiff.\" holds a runner" -- \
	cvi_rule cvp 'docs/new-project.md promises a check'
want_broken_none "conventions: ...never one an item quotes" \
	'rule "A clues.tsv is read by rl_clues' -- cvi_rule cvp 'docs/new-project.md promises a check'
# And a headline a rule reports of a selftest file, which no item quotes (the
# two fixture PATH rules were added to the script and not to the page, V154),
# beside the one item 6 quotes, "..." for what the headline fills in. Item 7's
# "in two sections" ends two headlines and holds the first: the second is
# reported, as a new rule whose headline ends like an old one's would be
# (the review of V154).
want_out "conventions: a selftest rule's headline no checklist item quotes" \
	'reports "$f writes from a section into a fixture tree made before the first section" of a selftest file' -- \
	cvi_rule cvp 'docs/new-project.md promises a check'
want_broken_none "conventions: ...never one an item quotes, \"...\" for its words" \
	'never defines it" of a selftest' -- cvi_rule cvp 'docs/new-project.md promises a check'
want_broken_none "conventions: ...nor one a quote ends" \
	'reports "$f names one toy exercise in two sections"' -- cvi_rule cvp 'docs/new-project.md promises a check'
want_out "conventions: ...but a quote holds one headline, not each it ends" \
	'reports "$f names one fixture tree in two sections" of a selftest file, and no item quotes it' -- \
	cvi_rule cvp 'docs/new-project.md promises a check'
# A rule whose loop reads the sections one file each, after the drivers,
# is a rule of a selftest file too: its headline is held the same way.
want_out "conventions: ...and one whose loop reads the sections one file each" \
	'reports "$f defines an arm helper outside tools/tests/selftest_lib.sh" of a selftest file' -- \
	cvi_rule cvp 'docs/new-project.md promises a check'
want_out "conventions: a work package that does not say where it stands" \
	'TODO.md:4: WP-02' -- cvi_rule cvp 'does not say where it stands'
want_broken_none "conventions: ...never one done" \
	'WP-01' -- cvi_rule cvp 'does not say where it stands'
want_broken_none "conventions: ...nor one partly done" \
	'WP-03' -- cvi_rule cvp 'does not say where it stands'
want_broken_none "conventions: ...nor one open" \
	'WP-04' -- cvi_rule cvp 'does not say where it stands'
want_out "conventions: a package marked DONE with something left" \
	'TODO.md:7: WP-05' -- cvi_rule cvp 'marked DONE with something left'
want_broken_none "conventions: ...never one DONE with nothing left" \
	'WP-01' -- cvi_rule cvp 'marked DONE with something left'
want_broken_none "conventions: ...nor one PARTLY DONE with its left" \
	'WP-03' -- cvi_rule cvp 'marked DONE with something left'
want_out "conventions: a checklist item with no row in the retro-audit" \
	'item 6 of docs/new-project.md has no row' -- cvi_rule cvp 'retro-audit and docs/new-project.md'
want_out "conventions: ...and a row for no item" \
	'row 9 names no item' -- cvi_rule cvp 'retro-audit and docs/new-project.md'
want_out "conventions: ...read only up to the line that ends the bullet" \
	'item 5 of docs/new-project.md has no row' -- cvi_rule cvp 'retro-audit and docs/new-project.md'
want_broken_none "conventions: ...never an item with its row" \
	'item 4 ' -- cvi_rule cvp 'retro-audit and docs/new-project.md'
want_out "conventions: AGENTS.md naming a table no .bzl assigns" \
	'`_GONE_LIST` is no table' -- cvi_rule cvp 'AGENTS.md names machinery'
want_broken_none "conventions: ...never one it assigns" \
	'_TOY_TABLE' -- cvi_rule cvp 'AGENTS.md names machinery'
want_out "conventions: ...a load-time check no .bzl defines" \
	'`gone_problem` is no function' -- cvi_rule cvp 'AGENTS.md names machinery'
want_broken_none "conventions: ...never one a .bzl defines" \
	'toy_problem' -- cvi_rule cvp 'AGENTS.md names machinery'
want_out "conventions: an exemption of conventions.sh that AGENTS.md does not name" \
	'    c-piscine-reloaded/c-piscine-reloaded/tests/ft_putchar.c' -- \
	cvi_rule cvp 'a file TURNIN_FN_ALLOW exempts is not named'

