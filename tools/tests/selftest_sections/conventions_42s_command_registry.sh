# ------------------------------------------- conventions: 42's command registry
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Every run target of a BUILD file is named in tools/fortytwo/commands.tsv,
# and every label a row names is declared (conventions.sh, "EVERY RUN TARGET
# IS A 42 COMMAND"). cvk is a toy checkout with 42 in it: a tools target, a
# shell project's :generate, and the registry, taken through each state in
# plain code, so every shard sees the same tree. It is this section's own:
# built in cvq, another section's tree, its runs read that section's modules.
mkdir -p "$WORK/cvk/tools/fortytwo" "$WORK/cvk/c-piscine/c-piscine-shell-90"
cv_submit "c-piscine/c-piscine-shell-90" > "$WORK/cvk/tools/submit.sh"
: > "$WORK/cvk/tools/42.sh"
printf '%s\n' 'sh_binary(name = "init", srcs = ["init.sh"])' \
	'sh_binary(name = "planted", srcs = ["planted.sh"])' > "$WORK/cvk/tools/BUILD.bazel"
printf '%s\n' 'sh_binary(' '    name = "generate",' '    srcs = ["//tools:generate.sh"],' ')' \
	> "$WORK/cvk/c-piscine/c-piscine-shell-90/BUILD.bazel"
convk() { env BUILD_WORKSPACE_DIRECTORY="$WORK/cvk" "$SH" "$TOOLS/conventions.sh"; }
want_out "conventions: a checkout with 42 and no registry is reported" \
	"tools/fortytwo/commands.tsv is missing" -- convk
cvk_rows() {
	printf 'init\t\t//tools:init\tstudent\tSet your login.\n'
	printf 'generate\t[project]\t//<project>:generate\tstudent\tWrite the deliverables.\n'
	printf '%s' "$1"
}
cvk_rows "" > "$WORK/cvk/tools/fortytwo/commands.tsv"
want_out "conventions: a run target no row names is reported" \
	"//tools:planted is a run target no row names" -- convk
cvk_rows "$(printf -- '-\t\t//tools:planted\tinternal\tNo command runs it, and this says why.')
" > "$WORK/cvk/tools/fortytwo/commands.tsv"
want_broken_none "conventions: ...and with an internal row, nothing is" \
	"commands.tsv and the BUILD files disagree" -- convk
cvk_rows "$(printf -- '-\t\t//tools:planted\tinternal\tWhy.\ngone\t\t//tools:gone\tstudent\tA renamed target.')
" > "$WORK/cvk/tools/fortytwo/commands.tsv"
want_out "conventions: a row naming a target nobody declares is reported" \
	"names //tools:gone, which tools/BUILD.bazel does not declare" -- convk
cvk_rows "$(printf -- '-\t\t//tools:planted\tinternal\tWhy.\nfmt\t\t//<project>:format\tstudent\tNo project has it.')
" > "$WORK/cvk/tools/fortytwo/commands.tsv"
want_out "conventions: ...and so is a project target no project declares" \
	"names //<project>:format, and no project declares :format" -- convk
cvk_rows "$(printf -- '-\t\t//tools:planted\tinternal\tWhy.\naudit\t\tsh tools/gone.sh\tstudent\tA script that moved.')
" > "$WORK/cvk/tools/fortytwo/commands.tsv"
want_out "conventions: ...and a script a row runs that is not there" \
	"runs sh tools/gone.sh, which is not there" -- convk
# 42 never passes Bazel a flag that costs a cache or an answer (conventions.sh,
# "42 NEVER PASSES BAZEL A FLAG"): one in code, the same word in a docstring,
# which may name it, and a row that runs bazel coverage.
printf '%s\n' 'ARGV = ["bazel", "test", "--watchfs"]' '"""--watchfs is never passed."""' \
	> "$WORK/cvk/tools/fortytwo/planted.py"
cvk_rows "$(printf -- '-\t\t//tools:planted\tinternal\tWhy.\ncov\t\tbazel coverage\tstudent\tNo.')
" > "$WORK/cvk/tools/fortytwo/commands.tsv"
! st_mine || convk > "$WORK/cvk.flags" 2>&1
want_out "conventions: 42 passing Bazel a banned flag is reported" \
	'tools/fortytwo/planted.py:1: "--watchfs' -- cv_saved "$WORK/cvk.flags"
want_broken_none "conventions: ...a docstring naming it is not" \
	"tools/fortytwo/planted.py:2" -- cv_saved "$WORK/cvk.flags"
want_out "conventions: ...and a row that runs bazel coverage is" \
	"tools/fortytwo/commands.tsv:4: bazel coverage" -- cv_saved "$WORK/cvk.flags"
# Only `42 config` and `42 units` run nothing (conventions.sh, "EVERY RUN
# TARGET IS A 42 COMMAND", its third point): a third row with an empty RUNS
# is reported by its line, and neither of those two is.
cvk_rows "$(printf -- '-\t\t//tools:planted\tinternal\tWhy.\nconfig\t[list]\t\tstudent\tSettings.\nunits\t[project]\t\tstudent\tUnits.\nlist\t\t\tstudent\tA third.')
" > "$WORK/cvk/tools/fortytwo/commands.tsv"
! st_mine || convk > "$WORK/cvk.empty" 2>&1
want_out "conventions: a third command that runs nothing is reported" \
	"line 6: list" -- cv_saved "$WORK/cvk.empty"
want_broken_none "conventions: ...never config" \
	"line 4: config" -- cv_saved "$WORK/cvk.empty"
want_broken_none "conventions: ...nor units" \
	"line 5: units" -- cv_saved "$WORK/cvk.empty"
rm -f "$WORK/cvk.flags" "$WORK/cvk.empty"

