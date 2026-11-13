# ----------------------------------------------------------------- norminette
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The Norm layer decides the verdict for every exercise in the repo, and it is
# the one layer whose tool is a pinned third-party program rather than our own
# shell. What is checked here is the RUNNER: that it forwards files, that it
# distinguishes a norm violation (1) from a broken harness (2), and that it does
# not simply pass everything.
#
# The 42 header is itself a Norm rule, so both fixtures are stamped with one
# from the repo's own generator rather than a hand-aligned copy pasted in here —
# a fixture that failed for the wrong reason would make the green arm useless
# and the red arm meaningless. LOGIN42/EMAIL42 are set so the result does not
# depend on whose .vscode/settings.json this ran against.
_hdr() {
	LOGIN42=selftest EMAIL42=selftest@42.fr \
		"$SH" "$TOOLS/gen_header.sh" "$1" > "$WORK/$1"
}
_hdr norm_ok.c
printf '\nint\tmain(void)\n{\n\treturn (0);\n}\n' >> "$WORK/norm_ok.c"
_hdr norm_bad.c
# Spaces instead of tabs, and a brace on the declaration line: two violations
# that need no knowledge of any exercise.
printf '\nint main(void) {\n    return (0);\n}\n' >> "$WORK/norm_bad.c"
want_green "norminette: a norm-compliant file passes" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_ok.c"
want_red   "norminette: a norm violation fails" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_bad.c"
# ...and says how to compare a norminette of your own with the pinned one:
# 42's command, not the bazel run it types (V306).
want_out   "norminette: ...naming 42 doctor --drift to compare yours" \
	'42 doctor --drift compares yours with the one above.' -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_bad.c"

# ANY FILE'S Error!, NOT THE LAST FILE'S. The pinned norminette sets its exit
# status from the last file it checked, and the runner trusted that status, so
# `bad ok` passed with "the Norm is satisfied" printed under "bad: Error!".
# Every macro lists headers after sources, which left the graded .c files of
# C 12, C 13, the rushes and BSQ effectively un-normed.
want_red   "norminette: an Error in a non-last file still fails" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" \
		"$WORK/norm_bad.c" "$WORK/norm_ok.c"
want_out   "norminette: ...and names the file that failed" \
	'the Norm is not satisfied in: norm_bad.c' -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" \
		"$WORK/norm_bad.c" "$WORK/norm_ok.c"
# The footer that says why norminette's own `echo $?` disagrees, both ways: it
# is owed on that run, where norminette exited 0, and it is wrong on a lone
# bad file, where norminette exited 1. The first arm also pins the fact the
# runner's ANY FILE comment states about the pinned version: a pin that
# computes its status over every file turns it red, and that comment with it.
want_out   "norminette: ...and says norminette's own status was 0" \
	'norminette itself exited 0' -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" \
		"$WORK/norm_bad.c" "$WORK/norm_ok.c"
want_broken_none "norminette: ...never when norminette exited 1" \
	'itself exited 0' -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_bad.c"

# A FILE norminette CANNOT PARSE ends its run there, printing nothing for the
# other files -- so a log showing one verdict for two files must say so.
_hdr norm_parse.c
printf '\nint\tmain(void)\n{\n\tif (1 {\n}\n' >> "$WORK/norm_parse.c"
want_out   "norminette: a parse stop says the rest went unchecked" \
	'judged 1 of the' -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" \
		"$WORK/norm_ok.c" "$WORK/norm_parse.c"
want_broken_none "norminette: ...an Error that parsed says no such thing" \
	'could not parse' -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_bad.c"
# NO COLOUR CODE IN THE LOG (TO VERIFY V57). The pinned norminette colours
# BRACE_NEWLINE's and the space codes' text, and a parse stop's message
# whatever it is told; in a saved test.log each is an ESC[..m around the
# words. Neither path may leave one.
_esc=$(printf '\033')
want_broken_none "norminette: no colour code reaches the log" "$_esc" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_bad.c"
want_broken_none "norminette: ...nor from a file it cannot parse" "$_esc" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" \
		"$WORK/norm_ok.c" "$WORK/norm_parse.c"
# The Notice twin cannot look for Notices past a parse stop, so it skips --
# and, like every SKIP, fails under NO_SKIP=1. Its plain twin reports the file.
want_green "norminette: --notices-only skips past a parse stop" -- \
	env -u NO_SKIP "$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" \
		--notices-only "$WORK/norm_ok.c" "$WORK/norm_parse.c"
want_out   "norminette: ...and says it skipped" \
	'SKIP — norminette stopped at a file it could not parse' -- \
	env -u NO_SKIP "$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" \
		--notices-only "$WORK/norm_ok.c" "$WORK/norm_parse.c"
# The plain target it points at is named by what it tests (RL_UNIT_KIND), and
# a kind no contract has is the harness's fault.
want_out   "norm: ...whose plain target is the unit's" \
	'target of this project reports that file.' -- \
	env -u NO_SKIP RL_UNIT_KIND=project "$SH" "$TOOLS/norminette_test.sh" \
		--norminette "$NORMINETTE" --notices-only "$WORK/norm_ok.c" "$WORK/norm_parse.c"
want_broken "norm: ...and the norm layer's" "norminette_test.sh: RL_UNIT_KIND is 'lesson'" -- \
	env -u NO_SKIP RL_UNIT_KIND=lesson "$SH" "$TOOLS/norminette_test.sh" \
		--norminette "$NORMINETTE" --notices-only "$WORK/norm_ok.c" "$WORK/norm_parse.c"
want_red   "norminette: ...which NO_SKIP=1 turns into a failure" -- \
	env NO_SKIP=1 "$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" \
		--notices-only "$WORK/norm_ok.c" "$WORK/norm_parse.c"
# ...while one it skipped for no reason it printed is the harness's fault.
mkdir -p "$WORK/norm_empty_dir.c"
want_broken "norminette: a file judged by nobody is refused" \
	'judged 1 of the 2' -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" \
		"$WORK/norm_ok.c" "$WORK/norm_empty_dir.c"
# ...and so is a status nothing printed explains: every file OK!, no Notice,
# and still exit 1. A stand-in norminette is the only way to get one; the
# real one's non-zero exits all come with an Error! or a Notice (the Notice
# arms below are that premise's other side).
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in *.c) echo "${a##*/}: OK!" ;; esac; done\nexit 1\n' \
	> "$WORK/norm_stand_in"
chmod +x "$WORK/norm_stand_in"
want_broken "norminette: an unexplained status is refused" \
	'nothing here explains that status' -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$WORK/norm_stand_in" "$WORK/norm_ok.c"

# WHAT RAN, stated rather than assumed. The OK line used to name
# -R CheckForbiddenSourceHeader on every target, although norminette keeps
# only the last -R and the c-08 headers pass -R CheckDefine after it: the flag
# the log named did not reproduce the verdict. The rule printed, and the
# command given to reproduce it, are now the effective one.
want_out   "norminette: the log names the -R that took effect" \
	'with -R CheckDefine --' -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" \
		-R CheckDefine "$WORK/norm_ok.c"
# That command is 42's, which types the bazel run (V306): the files as the
# test names them, then what norminette is handed after `--`.
want_out   "norminette: ...and a command that reproduces it" \
	"42 norm $WORK/norm_ok.c -- -R CheckDefine" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" \
		-R CheckDefine "$WORK/norm_ok.c"
# A relative file, as every norm target names its files, is given as it is:
# 42 finds it from where it is typed, where `bazel run` needed "$PWD/". From
# $WORK, with a stand-in norminette that passes every file.
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in *.c) echo "${a##*/}: OK!" ;; esac; done\n' \
	> "$WORK/norm_stand_ok"
chmod +x "$WORK/norm_stand_ok"
norm_rel() {
	_nt=$(cd "$TOOLS" && pwd) || return 2
	( cd "$WORK" && "$SH" "$_nt/norminette_test.sh" --norminette "$WORK/norm_stand_ok" \
		-R CheckDefine norm_ok.c )
}
want_out   "norminette: ...a relative file given as it is" \
	'42 norm norm_ok.c -- -R CheckDefine' -- norm_rel
# The version is the one the binary reports, asked here the same way, so the
# arm follows the pin rather than restating it.
_normv=$("$NORMINETTE" -v 2> /dev/null | awk '/^norminette [0-9]/ { v = $2; sub(/,.*/, "", v); print v; exit }')
want_out   "norminette: ...and the version the binary reported" \
	"ran:  norminette ${_normv:-(none reported)} (" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_ok.c"

# NOTICES. norminette prints "OK!" for a file whose only finding is a Notice
# and still exits 1, and the runner passed the 1 through with nothing said.
# Which of the two a grader goes by is a reading no subject settles, so the
# plain target passes with a warning and its --notices-only twin, at strict,
# fails -- each on its own reason, so the twin leaves Errors alone.
_hdr norm_notice.c
printf '\nint\tg_x;\n\nint\tmain(void)\n{\n\treturn (g_x);\n}\n' >> "$WORK/norm_notice.c"
want_green "norminette: a Notice alone passes the plain target" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_notice.c"
want_out   "norminette: ...with a warning that names the twin" \
	'*_notice twin of this target' -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_notice.c"
want_red   "norminette: --notices-only fails on it" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" --notices-only \
		"$WORK/norm_notice.c"
want_out   "norminette: ...and calls that this harness's reading" \
	"is this harness's reading, never the" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" --notices-only \
		"$WORK/norm_notice.c"
want_broken_none "norminette: ...which the plain target's warning never states" \
	"this harness's reading" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_notice.c"
want_red   "norminette: ...wherever the Notice sits in the run" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" --notices-only \
		"$WORK/norm_notice.c" "$WORK/norm_ok.c"
want_green "norminette: ...leaves an Error to the plain target" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" --notices-only \
		"$WORK/norm_bad.c"
want_broken_none "norminette: a clean file shows no Notice warning" \
	'WARNING' -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" "$WORK/norm_ok.c"
# The twin's note that an Error is the plain target's business, both ways.
want_out   "norminette: the twin passes an Error on, and says so" \
	"plain norm target's verdict" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" --notices-only \
		"$WORK/norm_bad.c"
want_broken_none "norminette: ...and says nothing of one on a clean run" \
	"plain norm target's verdict" -- \
	"$SH" "$TOOLS/norminette_test.sh" --norminette "$NORMINETTE" --notices-only \
		"$WORK/norm_ok.c"

