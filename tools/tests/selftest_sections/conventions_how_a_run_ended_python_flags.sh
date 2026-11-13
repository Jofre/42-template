# --------------------------------- conventions: how a run ended, Python flags
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The same guess in the other spellings the rule once let through (review of
# wave 3): one probe each, one run of the gate, one arm per probe. The
# timeout arm `124 | 137)` was let through while a timeout killed
# tools/exit_status too; the helper keeps the time itself now, so that arm is
# a guess like the others. An awk length test that happens to hold 150, and a
# status test under a not-a-program-status line (tools/student_build.sh's
# toolchain), must stay quiet. So must a guess in tools/tests/, which the rule
# does not read: no runner lives there, and the selftests' own probes hold
# the pattern on purpose (TO VERIFY V142).
_cv_g() { printf '#!/bin/sh\nset -u\nrc=0\n%s\n' "$2" > "$WORK/cv/tools/probe_g_$1.sh"; }
_cv_g gt127 'if [ "$rc" -gt 127 ]; then :; fi'
_cv_g nospace "$(printf 'sig=$((rc-%s))' 128)"
_cv_g dollarq "$(printf 'sig=$(($? - %s))' 128)"
_cv_g eq "$(printf 'if [ "$rc" -eq %s ]; then :; fi' 134)"
_cv_g str "$(printf 'if [ "$rc" = "%s" ]; then :; fi' 137)"
_cv_g label "$(printf 'case "$rc" in\n\t%s) : ;;\nesac' 139)"
_cv_g timeout "$(printf 'case "$rc" in\n\t%s | %s) : ;;\nesac' 124 137)"
_cv_g awk "$(printf 'awk %s' "'{ if (length(\$0) > 150) print }'")"
_cv_g toolchain "$(printf '# conventions: not-a-program-status -- %s\nif [ "$rc" %s %s ]; then :; fi' \
	'a probe: a compiler, not a program' -ge 126)"
_cv_g untold "$(printf '# a plain comment\nif [ "$rc" %s %s ]; then :; fi' -ge 126)"
printf '#!/bin/sh\nset -u\nrc=0\nif [ "$rc" -gt 128 ]; then :; fi\n' \
	> "$WORK/cv/tools/tests/probe_g_tests.sh"
# The same run holds a script naming signals in a table of its own, beside
# runner_lib.sh's rl_signame, and one that names a signal in a comment.
printf '#!/bin/sh\nset -u\ncase "${1:-}" in\n\t7) echo "SIGBUS (bus error)" ;;\nesac\n' \
	> "$WORK/cv/tools/probe_sigtab.sh"
printf '#!/bin/sh\nset -u\n# the kernel stops it with SIGXFSZ (exit 153)\n:\n' \
	> "$WORK/cv/tools/probe_sigsaid.sh"
# And three runners that read how a run ended: one files a run stopped
# from outside with a signal in a case arm, one in a test, and one refuses
# it on its own line before its crash arm, a comment naming the pair.
printf '#!/bin/sh\nset -u\ncase "$RL_CAUSE" in\n\t"signal" | "runaway" | "stopped") echo crash ;;\nesac\n' \
	> "$WORK/cv/tools/probe_stop_arm.sh"
printf '#!/bin/sh\nset -u\nif [ "$RL_CAUSE" = signal ] || [ "$RL_CAUSE" = stopped ]; then echo crash; fi\n' \
	> "$WORK/cv/tools/probe_stop_test.sh"
printf '#!/bin/sh\nset -u\n# never signal | stopped)\n[ "$RL_CAUSE" != stopped ] || rl_unjudged "case 1"\ncase "$RL_CAUSE" in\n\tsignal) echo crash ;;\n\tstopped) exit 2 ;;\nesac\n' \
	> "$WORK/cv/tools/probe_stop_ok.sh"
# And an option loop whose arms read $2: one with no guard, which a trailing
# --c would end in set -u's own words, and three that are guarded (need, a
# test of $#, a default).
printf '%s\n' '#!/bin/sh' 'set -u' 'while [ $# -gt 0 ]; do' '	case "$1" in' \
	'		--a) need "$1" "$#"; A=$2; shift 2 ;;' \
	'		--b) [ $# -ge 2 ] || exit 2; B=$2; shift 2 ;;' \
	'		--c)' '			C="$2"' '			shift 2 ;;' \
	'		--d) D=${2:-x}; shift 2 ;;' '		*) break ;;' '	esac' 'done' \
	> "$WORK/cv/tools/probe_needarm.sh"
# The two shapes the arm reader once lost its place in: a one-line case on a
# line of its own inside a guarded arm, before an unguarded --b; and an arm
# whose patterns have blanks around their |, unguarded (--e | --f) and
# guarded (--g | --h).
printf '%s\n' '#!/bin/sh' 'set -u' 'while [ $# -gt 0 ]; do' '	case "$1" in' \
	'		--a) need "$1" "$#"' '			case "$2" in /*) A=$2 ;; *) A="$PWD/$2" ;; esac' \
	'			shift 2 ;;' '		--b) B="$2"; shift 2 ;;' '		*) break ;;' '	esac' 'done' \
	> "$WORK/cv/tools/probe_needcase.sh"
printf '%s\n' '#!/bin/sh' 'set -u' 'while [ $# -gt 0 ]; do' '	case "$1" in' \
	'		--e | --f) E="$2"; shift 2 ;;' \
	'		--g | --h) need "$1" "$#"; G=$2; shift 2 ;;' '		*) break ;;' '	esac' 'done' \
	> "$WORK/cv/tools/probe_needspace.sh"
# A library user's unguarded arm, which is told to call the library's guard.
printf '%s\n' '#!/bin/sh' 'set -u' '. "$RL_LIB"' 'while [ $# -gt 0 ]; do' '	case "$1" in' \
	'		--x) X="$2"; shift 2 ;;' '		*) break ;;' '	esac' 'done' \
	> "$WORK/cv/tools/probe_libarm.sh"
# A library user with a need() of its own beside rl_need, and a script that
# calls rl_need without sourcing the library.
printf '%s\n' '#!/bin/sh' 'set -u' '. "$RL_LIB"' \
	'need() { [ "$2" -ge 2 ] || exit 2; }' > "$WORK/cv/tools/probe_libneed.sh"
printf '%s\n' '#!/bin/sh' 'set -u' 'while [ $# -gt 0 ]; do' '	case "$1" in' \
	'		--a) rl_need "$1" "$#"; A=$2; shift 2 ;;' '		*) break ;;' '	esac' 'done' \
	> "$WORK/cv/tools/probe_rlneed.sh"
! st_mine || conv > "$WORK/cv_guess.out" 2>&1
# Read with its status (cv_saved), so a run that broke fails every arm below
# as a harness error instead of being grepped for a line.
cv_guess() { cv_saved "$WORK/cv_guess.out"; }
for _s in gt127 nospace dollarq eq str label timeout; do
	want_out "conventions: the guess spelt as '$_s' is reported" \
		"probe_g_$_s.sh reads how a program ended from its status" -- cv_guess
done
want_broken_none "conventions: ...not a 150 that is no status" \
	'probe_g_awk.sh reads how' -- cv_guess
want_broken_none "conventions: ...nor a line marked not-a-program-status" \
	'probe_g_toolchain.sh reads how' -- cv_guess
want_out "conventions: ...which a plain comment above does not do" \
	'probe_g_untold.sh reads how a program ended from its status' -- cv_guess
want_broken_none "conventions: ...nor a guess in tools/tests/, which it does not read" \
	'probe_g_tests.sh reads how' -- cv_guess
want_out "conventions: a signal table outside rl_signame is reported" \
	'probe_sigtab.sh names a signal in a table of its own' -- cv_guess
want_broken_none "conventions: ...not a signal named in a comment" \
	'probe_sigsaid.sh names' -- cv_guess
want_broken_none "conventions: ...nor rl_signame's own table" \
	'runner_lib.sh names a signal' -- cv_guess
want_out "conventions: a case arm filing stopped beside signal is reported" \
	'probe_stop_arm.sh files a run stopped from outside beside a signal' -- cv_guess
want_out "conventions: ...and a test of the two on one line" \
	'probe_stop_test.sh files a run stopped from outside beside a signal' -- cv_guess
want_broken_none "conventions: ...never stopped refused on its own" \
	'probe_stop_ok.sh files' -- cv_guess
want_out "conventions: an option arm reading \$2 with no need() is reported" \
	'tools/probe_needarm.sh:7: --c)' -- cv_guess
want_out "conventions: ...told to call its own need()" \
	'tools/probe_needarm.sh:7: --c): call need "$1" "$#", this file'"'"'s own need()' -- cv_guess
want_out "conventions: ...and a runner_lib user, rl_need" \
	'tools/probe_libarm.sh:6: --x): call rl_need "$1" "$#" (this file sources runner_lib.sh)' -- cv_guess
want_broken_none "conventions: ...never one guarded by need" \
	'tools/probe_needarm.sh:5:' -- cv_guess
want_broken_none "conventions: ...nor by a test of \$#" \
	'tools/probe_needarm.sh:6:' -- cv_guess
want_broken_none "conventions: ...nor by a default" \
	'tools/probe_needarm.sh:10:' -- cv_guess
want_out "conventions: ...nor lost after a one-line case in an arm" \
	'tools/probe_needcase.sh:8: --b)' -- cv_guess
want_broken_none "conventions: ...whose own arm is guarded" \
	'tools/probe_needcase.sh:5:' -- cv_guess
want_out "conventions: ...an arm with blanks around its | is read" \
	'tools/probe_needspace.sh:5: --e | --f)' -- cv_guess
want_broken_none "conventions: ...and passed when guarded" \
	'tools/probe_needspace.sh:6:' -- cv_guess
want_out "conventions: a runner_lib user with a need() of its own is reported" \
	'probe_libneed.sh sources runner_lib.sh and defines a need() of its own' -- cv_guess
want_out "conventions: ...and rl_need called with no runner_lib.sh sourced" \
	'probe_rlneed.sh calls rl_need and never sources runner_lib.sh' -- cv_guess
want_broken_none "conventions: ...never the library's own call" \
	'runner_lib.sh calls rl_need' -- cv_guess
rm -f "$WORK"/cv/tools/probe_g_*.sh "$WORK/cv/tools/tests/probe_g_tests.sh" "$WORK/cv_guess.out" \
	"$WORK/cv/tools/probe_sigtab.sh" "$WORK/cv/tools/probe_sigsaid.sh" \
	"$WORK/cv/tools/probe_needarm.sh" "$WORK/cv/tools/probe_needcase.sh" \
	"$WORK/cv/tools/probe_needspace.sh" "$WORK/cv/tools/probe_libarm.sh" \
	"$WORK/cv/tools/probe_libneed.sh" \
	"$WORK/cv/tools/probe_rlneed.sh"
want_broken_none "conventions: ...and with no guess, nothing is" \
	'reads how a program ended from its status' -- \
	conv

# --keep_going in .bazelrc. Without it a student's compile error ends the run
# and the rest says NO STATUS, and the docs promise it is on. A .bazelrc that
# only mentions the flag in a comment, or sets it for one command, is not one
# that sets it; the fixture's .bazelrc is removed again after, as it came.
printf '# build --keep_going\ntest --keep_going\n' > "$WORK/cv/.bazelrc"
want_out "conventions: a .bazelrc without build --keep_going is reported" \
	".bazelrc no longer sets build --keep_going" -- \
	conv
printf 'build --keep_going\n' > "$WORK/cv/.bazelrc"
want_broken_none "conventions: and one that sets it is not" \
	".bazelrc no longer sets build --keep_going" -- \
	conv

# Python targets print no rules_python banner on a fresh clone (finding 047):
# a BUILD file declaring one needs .bazelrc's explicit-init flag, and every
# requirement of a file MODULE.bazel hands rules_python carries a --hash (a
# continued line counts as its requirement's). One run without the flag, one
# with; the fixture's files go back as they came.
_cv_mod_sum=$(sha256sum < "$WORK/cv/MODULE.bazel")
cp "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel" "$WORK/cv_c98_py.bak"
printf '\npy_binary(\n    name = "p",\n    srcs = ["p.py"],\n)\n' \
	>> "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
cp "$WORK/cv/MODULE.bazel" "$WORK/cv_module_py.bak"
printf 'pip.parse(\n    requirements_lock = "//tools:req.txt",\n)\n' > "$WORK/cv/MODULE.bazel"
printf '# pinned\na==1 \\\n    --hash=sha256:00ff\nb==2\n' > "$WORK/cv/tools/req.txt"
! st_mine || conv > "$WORK/cv.py" 2>&1
want_out "conventions: a Python target without the explicit-init flag" \
	'.bazelrc no longer sets --incompatible_default_to_explicit_init_py' -- cv_saved "$WORK/cv.py"
want_out "conventions: a requirement with no --hash is reported" \
	'tools/req.txt:4: b==2' -- cv_saved "$WORK/cv.py"
want_broken_none "conventions: ...and a hashed one over two lines is not" \
	'tools/req.txt:2:' -- cv_saved "$WORK/cv.py"
printf 'build --keep_going\ncommon --incompatible_default_to_explicit_init_py\n' > "$WORK/cv/.bazelrc"
want_broken_none "conventions: ...and with the flag, the Python target is fine" \
	'explicit_init_py' -- conv
cp "$WORK/cv_c98_py.bak" "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
cp "$WORK/cv_module_py.bak" "$WORK/cv/MODULE.bazel"
rm -f "$WORK/cv/tools/req.txt" "$WORK/cv.py" "$WORK/cv_c98_py.bak" "$WORK/cv_module_py.bak"
rm -f "$WORK/cv/.bazelrc"
want_green "conventions: the Python-flags block puts the fixture's MODULE.bazel back" -- \
	sh -c '[ "$(sha256sum < "$1")" = "$2" ]' _ "$WORK/cv/MODULE.bazel" "$_cv_mod_sum"

# An output root in a tracked rc file. An rc file cannot say "per user", so the
# `startup --output_user_root=/tmp/bazelcache` .bazelrc carried was one path
# for every user of a campus box: the second student's build waited on the
# first one's lock (finding 001). tools/bazel supplies the per-user default
# now, and this keeps the shared literal from coming back. A commented one is
# not a setting.
printf 'build --keep_going\nstartup --output_user_root=/tmp/bazelcache\n' > "$WORK/cv/.bazelrc"
want_out "conventions: a .bazelrc naming an output root is reported" \
	".bazelrc names a shared place for Bazel's state" -- \
	conv
printf 'build --keep_going\n# startup --output_user_root=/tmp/x\n' > "$WORK/cv/.bazelrc"
want_broken_none "conventions: ...and a commented one is not" \
	".bazelrc names a shared place" -- \
	conv
# ...in ANY rc file and ANY flag that places state. The rule read two files and
# one flag, and an imported tools/*.bazelrc with a shared --disk_cache is the
# same collision. %workspace% is per checkout, the example's CHANGEME is a path
# to replace, and .bazelrc.local is the one file where an absolute path is the
# point (setup.sh writes it, per checkout, gitignored).
printf 'build --disk_cache=/tmp/shared-cache\n' > "$WORK/cv/tools/ci.bazelrc"
printf 'startup --output_user_root=/tmp/CHANGEME-login/bazel\n' > "$WORK/cv/.bazelrc.local.example"
printf 'startup --output_user_root=/goinfre/probe/bazel\n' > "$WORK/cv/.bazelrc.local"
! st_mine || conv > "$WORK/cv.rcfiles" 2>&1
want_out "conventions: a shared --disk_cache in another rc file is reported" \
	"tools/ci.bazelrc names a shared place for Bazel's state" -- \
	cv_saved "$WORK/cv.rcfiles"
want_broken_none "conventions: ...not the example's CHANGEME" \
	".bazelrc.local.example names a shared place" -- \
	cv_saved "$WORK/cv.rcfiles"
want_broken_none "conventions: ...nor .bazelrc.local" \
	".bazelrc.local names a shared place" -- \
	cv_saved "$WORK/cv.rcfiles"
rm -f "$WORK/cv.rcfiles"
printf 'build --disk_cache=%%workspace%%/.cache\n' > "$WORK/cv/tools/ci.bazelrc"
want_broken_none "conventions: ...nor a path under %workspace%" \
	"tools/ci.bazelrc names" -- \
	conv
# ...and one that is a symlink, as under `bazel test` every file is (V23).
printf 'build --disk_cache=/tmp/shared-cache\n' > "$WORK/cv_linked.rc"
ln -s "$WORK/cv_linked.rc" "$WORK/cv/tools/linked.bazelrc"
want_out "conventions: ...and one in an rc file that is a symlink" \
	"tools/linked.bazelrc names a shared place for Bazel's state" -- \
	conv
rm -f "$WORK/cv/tools/linked.bazelrc" "$WORK/cv_linked.rc"
rm -f "$WORK/cv/.bazelrc" "$WORK/cv/tools/ci.bazelrc" "$WORK/cv/.bazelrc.local.example" \
	"$WORK/cv/.bazelrc.local"

