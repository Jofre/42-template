# ------------------------------- conventions: the maintainer's records, todo/
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The maintainer's records are TODO.md, HISTORY.md and the folder todo/,
# which holds the plans TODO.md points at. None ships, and every rule on
# what ships skips all three: cvrec holds a probe line for each such rule
# twice, in a page that ships (docs/shipped.md, reported) and in a file
# under todo/ (quiet). Its build's list names notes/ and not todo/, so the
# file under todo/ is quiet because it is a record: the rules that read the
# list skip what it names too, and on main would pass over a record that
# way whatever they made of the records. Its records are in order, so none
# of the rules on them speaks: the plan's package says where it stands, and
# its retro-audit has a row for each item of the toy checklist. The paths
# are spelt through $_td, so this file cites no record of its own.
_td=todo
mkdir -p "$WORK/cvrec/tools" "$WORK/cvrec/m" "$WORK/cvrec/docs" "$WORK/cvrec/$_td"
cv_submit m > "$WORK/cvrec/tools/submit.sh"
: > "$WORK/cvrec/m/BUILD.bazel"
printf '%s\n' '# TODO' '' 'Open: the plan.' > "$WORK/cvrec/TODO.md"
printf '%s\n' '## 23. A plan' '' '- WP-01 [P1 S] a package [DONE in wave 1]' '' \
	'- **Retro-audit, today.** The rows.' '' '| 1 | A | x |' '| 2 | B | x |' '' '**Packages**' \
	> "$WORK/cvrec/$_td/23-plan.md"
printf '%s\n' '# History' '' '## TO VERIFY leads, settled' '' '- **V2, nothing there** -- DROPPED.' \
	> "$WORK/cvrec/HISTORY.md"
printf '%s\n' '# Adding a project' '' '1. **A.** (unchecked)' '2. **B.** (unchecked)' \
	> "$WORK/cvrec/docs/new-project.md"
# The probes, from line 2 of each file: the oracle's source (2), a full
# run's size (3), a CI (4), a citation of the record (5), a whole-repo test
# run in a block (9-11), a reading named in other words (12), the level
# ladder spelt out (13-15), a loop over a listing (16), a read that trims
# its name (17) and an editor task the toy's tasks.json lacks (18). Each
# word a rule looks for is put together by printf, and each block's lines go
# to a file, so this file holds none of them where a rule reads.
{
	printf '%s/src/q1.%s holds the shape.\n' oracle rs
	printf 'A full run of this repo is 9 %s.\n' GB
	printf 'NO_SKIP=1 (set in %s) forces it open.\n' CI
	printf 'See HISTORY%s §21.\n' .md
	printf '\nRun:\n\n```\nbazel test //...\n```\n'
	printf 'It takes the subject%s reading.\n' "'s"
	printf '%s: the first rung.\n' basic strict robust
	printf 'for f in $(%s .); do :; done\n' find
	printf '%s read -r f; do :; done < list\n' while
	printf 'Run Task, then `Toy: %s`.\n' 'test it all'
} > "$WORK/cvrec.probes"
{ printf '# Probes\n'; cat "$WORK/cvrec.probes"; } > "$WORK/cvrec/$_td/probes.md"
{ printf '# Shipped\n'; cat "$WORK/cvrec.probes"; } > "$WORK/cvrec/docs/shipped.md"
mkdir -p "$WORK/cvrec/.vscode"
{
	printf '{\n  "version": "2.0.0",\n  "tasks": [\n'
	cv_task "Toy: test this module" "bazel test //m:basic" 1
	printf '  ]\n}\n'
} > "$WORK/cvrec/.vscode/tasks.json"
# cvrecx breaks each rule on the records: a plan whose first package says
# nothing of where it stands (line 3) and whose second is DONE with
# something left (4), and whose retro-audit has a row for no item (9) and
# none for item 3; and a second retro-audit, in another plan.
mkdir -p "$WORK/cvrecx/tools" "$WORK/cvrecx/m" "$WORK/cvrecx/docs" "$WORK/cvrecx/$_td"
cv_submit m > "$WORK/cvrecx/tools/submit.sh"
: > "$WORK/cvrecx/m/BUILD.bazel"
printf '%s\n' '# TODO' '' 'Open: the plans.' > "$WORK/cvrecx/TODO.md"
printf '%s\n' '## 23. A plan' '' '- WP-01 [P1 S] a package' '- WP-02 [P1 S] another [DONE in wave 2; left: a thing]' '' \
	'- **Retro-audit, today.** The rows.' '' '| 1 | A | x |' '| 2 | B | x |' '| 9 | I | x |' '' '**Packages**' \
	> "$WORK/cvrecx/$_td/23-plan.md"
printf '%s\n' '- **Retro-audit, again.** The rows.' > "$WORK/cvrecx/$_td/29-later.md"
printf '%s\n' '# History' '' '## TO VERIFY leads, settled' '' '- **V12, settled** -- FIXED.' \
	> "$WORK/cvrecx/HISTORY.md"
printf '%s\n' '# Adding a project' '' '1. **A.** (unchecked)' '2. **B.** (unchecked)' '3. **C.** (unchecked)' \
	> "$WORK/cvrecx/docs/new-project.md"
# cvrecn is a clone's tree: a todo/ of its own, a checklist with no
# retro-audit, which a clone need not keep, and leads in its TODO.md, which
# are its own: one number given twice, one past the last main gave, and one
# that is on no record, each of which main is held to (cvrecl2, below).
mkdir -p "$WORK/cvrecn/tools" "$WORK/cvrecn/m" "$WORK/cvrecn/docs" "$WORK/cvrecn/$_td"
cv_submit m > "$WORK/cvrecn/tools/submit.sh"
: > "$WORK/cvrecn/m/BUILD.bazel"
_cvl_new=$((471 + 1))
printf '%s\n' '# TODO' '' "Open: V1, V$_cvl_new." '' '**V1. A lead**' '' '**V1. A second draft**' \
	> "$WORK/cvrecn/TODO.md"
printf 'Ideas.\n' > "$WORK/cvrecn/$_td/ideas.md"
printf '%s\n' '# Adding a project' '' '1. **A.** (unchecked)' > "$WORK/cvrecn/docs/new-project.md"
_cvrec_trees="cvrec cvrecx cvrecn"
if st_mine; then
	for _t in $_cvrec_trees; do
		env BUILD_WORKSPACE_DIRECTORY="$WORK/$_t" "$SH" "$TOOLS/conventions.sh" > "$WORK/$_t.out" 2>&1
	done
fi
for _h in "names the oracle's source" "quotes a full run's size" "says a CI runs the checks" \
	'cites a section or an item of TODO.md' 'a doc shows a whole-repo test run' \
	'a reading is named in other words' 'the level ladder is spelled out' \
	'a list of files is not read one name per line' 'a loop reads one name a line' \
	'a doc names an editor task'; do
	want_out "conventions: $_h, in a page that ships" \
		'docs/shipped.md:' -- cvi_rule cvrec "$_h"
	want_broken_none "conventions: ...never in a file under todo/, a record ($_h)" \
		"$_td/probes.md" -- cvi_rule cvrec "$_h"
done
for _h in 'does not say where it stands' \
	'marked DONE with something left' 'more than one retro-audit' \
	'retro-audit and docs/new-project.md'; do
	want_broken_none "conventions: records in order are quiet ($_h)" \
		'FAIL' -- cvi_rule cvrec "$_h"
done
want_out "conventions: a package in a plan under todo/, by its own path" \
	"$_td/23-plan.md:3: WP-01" -- cvi_rule cvrecx 'does not say where it stands'
want_out "conventions: ...and one DONE with something left" \
	"$_td/23-plan.md:4: WP-02" -- cvi_rule cvrecx 'marked DONE with something left'
want_out "conventions: a retro-audit found in a plan under todo/" \
	"the table at $_td/23-plan.md:6" -- cvi_rule cvrecx 'retro-audit and docs/new-project.md'
want_out "conventions: ...with a row for no item" \
	'row 9 names no item' -- cvi_rule cvrecx 'retro-audit and docs/new-project.md'
want_out "conventions: ...and an item with no row" \
	'item 3 of docs/new-project.md has no row' -- cvi_rule cvrecx 'retro-audit and docs/new-project.md'
want_out "conventions: a second retro-audit" \
	"$_td/29-later.md:1" -- cvi_rule cvrecx 'more than one retro-audit'
want_broken_none "conventions: a clone's checklist with no retro-audit is quiet" \
	'FAIL' -- cvi_rule cvrecn 'hold no retro-audit'
