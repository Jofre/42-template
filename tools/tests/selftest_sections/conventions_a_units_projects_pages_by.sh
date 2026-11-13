# --------------------------- conventions: a units project's pages, by name
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A project divided into units has no exNN, and a page that names one sends
# a student to a target that does not exist. cvux holds two such projects
# -- a Common Core library and a Piscine project, each with a subject() call
# naming units -- and a rush of exercises, with submit.sh's own short_name()
# appended as the short-name arms append it. docs/red.md names the library's
# exercises in every form the rule reads, the library's own README.md in the
# forms only its own page is held to; docs/green.md and the project's other
# page name what may be named: a convention with no project, a project of
# exercises, a unit's own targets, a folder that is not there. CHANGELOG.md
# and TODO.md, which keep old names on purpose, name them too. cvux2's
# library has a contract units.awk cannot read, which is said, not passed.
_ux_mods="cursus/Milestone_9/Toylib c-piscine/c-piscine-zsq c-piscine/c-piscine-rush-79"
mkdir -p "$WORK/cvux/tools" "$WORK/cvux/docs"
for _m in $_ux_mods; do mkdir -p "$WORK/cvux/$_m"; done
cv_submit "$_ux_mods" > "$WORK/cvux/tools/submit.sh"
{
	awk '/^short_name\(\) \{$/ { f = 1 } f { print } f && /^\}$/ { exit }' "$TOOLS/submit.sh"
	printf '%s\n' 'while read -r m; do' '	short_name "$m"' 'done'
} >> "$WORK/cvux/tools/submit.sh"
for _u in toylib:cursus/Milestone_9/Toylib zsq:c-piscine/c-piscine-zsq; do
	printf 'subject(\n    grader = "both",\n    group = False,\n    units = {\n        "%s": unit(\n            page = 1,\n            files = ["Makefile"],\n            allowed = None,\n        ),\n    },\n)\n' \
		"${_u%%:*}" > "$WORK/cvux/${_u#*:}/BUILD.bazel"
done
printf 'subject(\n    grader = "defense",\n    group = True,\n    exercises = {\n        "00": exercise(\n            page = 1,\n            dir = "ex00/",\n            files = ["Makefile"],\n            allowed = None,\n        ),\n    },\n)\n' \
	> "$WORK/cvux/c-piscine/c-piscine-rush-79/BUILD.bazel"
printf '%s\n' \
	'Run `bazel test //cursus/Milestone_9/Toylib:ex00`.' \
	'Or //cursus/Milestone_9/Toylib:ex00_norm alone.' \
	'Its hints are in cursus/Milestone_9/Toylib/tests/ex00/clues.tsv.' \
	'It turns in cursus/Milestone_9/Toylib/deliverable/ex00/.' \
	'Type `42 test toylib ex00`.' \
	'Or `42 test --dry-run Toylib ex00`.' \
	"Toylib's \`ex00_files\` holds the rest." \
	'| `ex00_globals` | Toylib | none |' \
	'The square is `42 test zsq ex00`.' \
	'Type `42 test --level strict toylib ex00`.' \
	'Type `42 test toylib --level strict ex00`.' \
	'Type `42 test toylib --dry-run ex00`.' > "$WORK/cvux/docs/red.md"
printf '%s\n' \
	'Its suite is `:ex00`.' \
	'Its norm target is `ex00_norm`.' \
	'The clues sit in tests/ex00/.' \
	'Type `42 test ex00`.' \
	'The rush is `42 test rush-79 ex00`.' \
	'Type `42 test --level strict ex00`.' \
	'It turns in deliverable/ex00/.' \
	'Type `42 test norm ex00`.' > "$WORK/cvux/cursus/Milestone_9/Toylib/README.md"
printf '%s\n' \
	"The rush's //c-piscine/c-piscine-rush-79:ex00_output says it." \
	"Every exercise has \`exNN_norm\`; C 00's suite is \`:ex00\`." \
	'| `ex00_output` | C 00 | the output |' \
	'| `toylib_globals` | Toylib | none |' \
	'Run //cursus/Milestone_9/Toylib:toylib_norm and `42 test toylib`.' > "$WORK/cvux/docs/green.md"
printf 'There is no `ex00/` folder: the files sit at the root.\n' \
	> "$WORK/cvux/c-piscine/c-piscine-zsq/README.md"
printf '%s\n' '- //cursus/Milestone_9/Toylib:ex00_norm is now :toylib_norm.' > "$WORK/cvux/CHANGELOG.md"
printf '%s\n' '- //cursus/Milestone_9/Toylib:ex00_norm' > "$WORK/cvux/TODO.md"
mkdir -p "$WORK/cvux2"
cp -R "$WORK/cvux/." "$WORK/cvux2/"
printf 'subject(\n    grader = "both",\n    group = False,\n    units = UNITS,\n)\n' \
	> "$WORK/cvux2/cursus/Milestone_9/Toylib/BUILD.bazel"
if st_mine; then
	for _t in cvux cvux2; do
		env BUILD_WORKSPACE_DIRECTORY="$WORK/$_t" "$SH" "$TOOLS/conventions.sh" > "$WORK/$_t.out" 2>&1
	done
fi
cvux_rule() { cvi_rule cvux 'a page names an exercise target, suite, folder or 42 word'; }
_ux_t=docs/red.md
_ux_o=cursus/Milestone_9/Toylib/README.md
want_out "conventions: a units project's exercise, by its label, is reported" \
	"$_ux_t:1: //cursus/Milestone_9/Toylib:ex00 (cursus/Milestone_9/Toylib)" -- cvux_rule
want_out "conventions: ...and one of its exNN targets" \
	"$_ux_t:2: //cursus/Milestone_9/Toylib:ex00_norm (" -- cvux_rule
want_out "conventions: ...its folder under tests/" \
	"$_ux_t:3: cursus/Milestone_9/Toylib/tests/ex00 (" -- cvux_rule
want_out "conventions: ...and under deliverable/" \
	"$_ux_t:4: cursus/Milestone_9/Toylib/deliverable/ex00 (" -- cvux_rule
want_out "conventions: ...after its short name in a 42 command" \
	"$_ux_t:5: 42 test toylib ex00 (" -- cvux_rule
want_out "conventions: ...after its folder's name, past a flag" \
	"$_ux_t:6: 42 test --dry-run Toylib ex00 (" -- cvux_rule
want_out "conventions: ...as the project's own target" \
	"$_ux_t:7: Toylib's \`ex00_files\` (" -- cvux_rule
want_out "conventions: ...in a table row naming the project" \
	"$_ux_t:8: \`ex00_globals\` (" -- cvux_rule
want_out "conventions: ...and a Piscine project's, by its short name" \
	"$_ux_t:9: 42 test zsq ex00 (c-piscine/c-piscine-zsq)" -- cvux_rule
want_out "conventions: ...its suite, in its own page" \
	"$_ux_o:1: :ex00 (cursus/Milestone_9/Toylib)" -- cvux_rule
want_out "conventions: ...an exNN target, in its own page" \
	"$_ux_o:2: ex00_norm (" -- cvux_rule
want_out "conventions: ...a tests/exNN folder, in its own page" \
	"$_ux_o:3: tests/ex00 (" -- cvux_rule
want_out "conventions: ...and a 42 command's last word, in its own page" \
	"$_ux_o:4: 42 test ex00 (" -- cvux_rule
# A 42 command's flags, --level's word among them, before and after the
# project's name; in its own page, a deliverable/exNN folder and a word
# before the exNN that is no module's.
want_out "conventions: ...past --level and its word" \
	"$_ux_t:10: 42 test --level strict toylib ex00 (" -- cvux_rule
want_out "conventions: ...or after the project's name" \
	"$_ux_t:11: 42 test toylib --level strict ex00 (" -- cvux_rule
want_out "conventions: ...as a flag after the project's name" \
	"$_ux_t:12: 42 test toylib --dry-run ex00 (" -- cvux_rule
want_out "conventions: ...past --level, in its own page" \
	"$_ux_o:6: 42 test --level strict ex00 (" -- cvux_rule
want_out "conventions: ...a deliverable/exNN folder, in its own page" \
	"$_ux_o:7: deliverable/ex00 (" -- cvux_rule
want_out "conventions: ...after a word that names no module, in its own page" \
	"$_ux_o:8: 42 test norm ex00 (" -- cvux_rule
want_broken_none "conventions: ...but never another project's exercise, in its own page" \
	"$_ux_o:5:" -- cvux_rule
want_broken_none "conventions: ...never a project of exercises" \
	'rush-79' -- cvux_rule
want_broken_none "conventions: ...nor a page that names no project" \
	'docs/green.md' -- cvux_rule
want_broken_none "conventions: ...nor a folder a page says is not there" \
	'c-piscine-zsq/README.md' -- cvux_rule
want_broken_none "conventions: ...nor CHANGELOG.md" \
	'CHANGELOG.md:' -- cvux_rule
want_broken_none "conventions: ...nor a record" \
	'TODO.md' -- cvux_rule
want_out "conventions: a units project whose contract cannot be read is said, not passed" \
	'cursus/Milestone_9/Toylib/BUILD.bazel' -- \
	cvi_rule cvux2 'cannot be checked against a contract units.awk cannot read'
rm -rf "$WORK/cvux" "$WORK/cvux2" "$WORK/cvux.out" "$WORK/cvux2.out"

