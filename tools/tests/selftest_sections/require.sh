# -------------------------------------------------------------------- require
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Every runner declares the external commands it takes from PATH and probes for
# them at startup. These arms are what make that a mechanism rather than a
# comment.
#
# THE BUG IT EXISTS FOR IS INVISIBLE WITHOUT THEM. `grep -qE "AddressSanitizer"
# "$ERR"` on a box with no grep does not error -- it reads as "no match", so
# asan_run.sh skips its sanitizer branch and announces a real ASan finding as
# "died on signal 6". Nothing in the suite could see that, because every arm we
# have runs on a machine where grep exists.
#
# So the PATH is built to hold everything a runner needs EXCEPT one tool, and
# the arm asserts the message names that tool. A directory holding nothing at
# all would not do: the shell itself would not be found and the runner would die
# 127 before reaching its own first line, which looks like a pass to a status
# check and proves nothing.
# Both runners source tools/runner_lib.sh, which probes its own commands (cat,
# chmod, cp, date, dirname, env, grep, mkdir, od, readlink). No `timeout`:
# tools/exit_status enforces the time limit.
mkdir -p "$WORK/req_full" "$WORK/req_nomktemp"
for _t in sh "$SH" awk cat chmod cmp cp date env head mkdir mktemp mv od rm sed tail tr wc grep dirname basename readlink; do
	ln -sf "$(command -v "$_t")" "$WORK/req_full/$_t" 2> /dev/null
	[ "$_t" = "mktemp" ] || ln -sf "$(command -v "$_t")" "$WORK/req_nomktemp/$_t" 2> /dev/null
done
printf 'x\n' > "$WORK/req_exp.txt"
printf '#!/bin/sh\nprintf "x\\n"\n' > "$WORK/req_bin"
chmod +x "$WORK/req_bin"

# The control. Same runner, same arguments, on a PATH that has everything: it
# must still work, or the two arms below would prove only that the PATH was
# broken.
want_green "require: a complete PATH leaves the runner working" -- \
	env PATH="$WORK/req_full" "$SH" "$TOOLS/diff_output.sh" \
		--bin "$WORK/req_bin" --expected "$WORK/req_exp.txt"

# One tool removed, and the message has to name THAT tool -- not the first in
# the list, and not a generic "something is missing". The whole value of the
# probe is that it turns an invisible degradation into a sentence someone can
# act on.
want_broken "require: a missing tool refuses with 2 and names it" \
	"required command 'mktemp' is not on PATH" -- \
	env PATH="$WORK/req_nomktemp" "$SH" "$TOOLS/diff_output.sh" \
		--bin "$WORK/req_bin" --expected "$WORK/req_exp.txt"

# asan_run.sh is the runner the whole item was raised about, so it gets its own
# arm rather than being assumed to behave like its sibling.
want_broken "require: asan_run refuses rather than mis-reporting a finding" \
	"required command 'mktemp' is not on PATH" -- \
	env PATH="$WORK/req_nomktemp" "$SH" "$TOOLS/asan_run.sh" --bin "$WORK/req_bin"

