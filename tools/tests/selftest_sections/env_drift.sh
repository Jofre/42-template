# ------------------------------------------------------------------ env_drift
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Not a test layer -- it is the maintainer's answer to "has campus upgraded
# anything?" -- but its grading is comparison logic, and comparison logic that
# stops comparing is the exact shape every other arm in this file hunts. It
# earned these the hard way: two versions of its version extractor returned the
# wrong answer for a pin written as a bare "3.3.58", one of them silently
# grading a correct toolchain as a different major release.
#
# `printf` with a literal tab, because pins.tsv is tab-separated and a fixture
# written with spaces would be read as one enormous tool name -- which grades as
# missing, and would pass a want_red arm while proving nothing.
mkdir -p "$WORK/drift"
# What //tools:env_drift hands its launcher: the fetched python3 (--python)
# and the file it runs, absolute, since the arms start the launcher from
# directories of their own. Taken out again at the end of this section.
ENV_DRIFT_PYTHON=$(cd "$(dirname "$PYTHON")" && pwd)/${PYTHON##*/}
ENV_DRIFT_MAIN=$(cd "$TOOLS" && pwd)/env_drift.py
export ENV_DRIFT_PYTHON ENV_DRIFT_MAIN
_pin() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" campus "$2" "$3" fixture; }

# Exactly what the box reports: no drift, whatever the string looks like.
_pin true "GNU coreutils 8.32" "echo GNU coreutils 8.32" > "$WORK/drift/same.tsv"
want_out "env_drift: a version that matches is not drift" 'true        campus  ok' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/same.tsv"

# A repackaging: same version, different wrapper text. The whole reason the
# expected value stopped being a substring was to keep seeing real differences
# WITHOUT reporting this one.
_pin true "GNU coreutils 8.32" "echo Debian coreutils 8.32-4" > "$WORK/drift/pkg.tsv"
want_out "env_drift: a repackaged same version is forgiven, not hidden" 'ok (repackaged)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/pkg.tsv"

# ...but a campus pin is campus's EXACT string (the owner's ruling,
# 2026-10-14), so on a campus box the repackaging still asks for the edit, in
# the drift line's own form. It stays out of the drift count and out of
# --strict: the version did not move. Off campus nothing changes.
want_out "env_drift: on campus, a repackaged campus pin prints its re-pin edit" \
	'true (repackaged): GNU coreutils 8.32  ->  Debian coreutils 8.32-4   (edit fixture and tools/pins.tsv)' -- \
	env C_PISCINE_CAMPUS=1 "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/pkg.tsv"
want_green "env_drift: ...which --strict does not count as drift" -- \
	env C_PISCINE_CAMPUS=1 "$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/pkg.tsv"
want_broken_none "env_drift: off campus, a repackaged pin asks for no edit" \
	'(repackaged):' -- \
	env C_PISCINE_CAMPUS=0 "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/pkg.tsv"
want_out "env_drift: ...and still says there is nothing to do" \
	'Same version, different package build. Nothing to do.' -- \
	env C_PISCINE_CAMPUS=0 "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/pkg.tsv"

# The one the old substring pin could not see at all: campus moved by a patch
# release. `clang version 12.` swallowed this silently.
_pin true "GNU coreutils 8.32" "echo GNU coreutils 8.32.1" > "$WORK/drift/patch.tsv"
want_out "env_drift: a patch-level move is reported, not swallowed" 'DRIFT (patch)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/patch.tsv"

_pin true "GNU coreutils 8.32" "echo GNU coreutils 9.1" > "$WORK/drift/major.tsv"
want_out "env_drift: a major move is graded as one" 'DRIFT (major)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/major.tsv"

# A line that ends in ANOTHER program's version: `ip -V` ends in libbpf's,
# `ssh -V` in OpenSSL's. Graded by its last number alone, iproute2 moving a
# whole major release under the same libbpf read "repackaged" and passed
# --strict. The tool's own number comes first, and a move of it is drift;
# a new Ubuntu revision with both numbers unchanged is still a repackaging.
_pin true "ip utility, iproute2-5.15.0, libbpf 0.5.0" \
	"echo ip utility, iproute2-6.1.0, libbpf 0.5.0" > "$WORK/drift/first.tsv"
want_out "env_drift: a move of the tool's own (first) number is drift" \
	'DRIFT (major)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/first.tsv"
want_red "env_drift: ...which --strict fails on" -- \
	env C_PISCINE_CAMPUS=1 "$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/first.tsv"
_pin true "OpenSSH_8.9p1 Ubuntu-3ubuntu0.17, OpenSSL 3.0.2 15 Mar 2022" \
	"echo OpenSSH_8.9p1 Ubuntu-3ubuntu0.18, OpenSSL 3.0.2 15 Mar 2022" > "$WORK/drift/rev.tsv"
want_out "env_drift: ...and a new revision of the same two is not" \
	'ok (repackaged)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/rev.tsv"

# A pin written as a bare number, which is how the norminette pin is written and
# where both extractor bugs lived. It must grade exactly like any other.
printf 'true\tcampus\t3.3.58\techo 3.3.58\tfixture\n' > "$WORK/drift/bare.tsv"
want_out "env_drift: a bare version number grades like any other" 'true        campus  ok' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/bare.tsv"

# And the third comparison. The pin and the box agree; what BAZEL FETCHED does
# not, which is the case that had nothing watching it until the fetched
# toolchain existed. It must be loud even though the box looks fine.
printf 'true\tcampus\t8.32\techo 8.32\tfixture\tSELFTEST_FETCHED\n' \
	> "$WORK/drift/fetch.tsv"
printf '#!/bin/sh\necho "GNU coreutils 9.9"\n' > "$WORK/drift/fetched.sh"
chmod +x "$WORK/drift/fetched.sh"
want_out "env_drift: a fetch that disagrees with its own pin is loud" 'FETCH DRIFT' -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/fetch.tsv"
want_red "env_drift: --strict fails on fetch drift the box cannot show" -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched.sh" \
		"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/fetch.tsv"

# A campus tool that is ABSENT must reach --strict. It counted into MISSING and
# into neither of the two lists --strict actually looks at, so a box carrying
# none of the pinned tools printed a wall of MISSING and exited 0 -- the one
# kind of machine the flag exists to reject was the one it accepted.
printf 'no-such-tool-42\tcampus\t1.0\tno-such-tool-42 --version\tfixture\n' \
	> "$WORK/drift/absent.tsv"
want_out "env_drift: an absent campus tool is named in the drift list" \
	'no-such-tool-42 (missing)' -- \
	env C_PISCINE_CAMPUS=1 "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/absent.tsv"
want_red "env_drift: --strict fails on a campus tool that is not installed" -- \
	"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/absent.tsv"

# WHO THE ADVICE IS FOR (finding 005). The drift list says "worth acting on"
# and "re-pin by hand" -- advice for whoever keeps the pins, about the machines
# the grade comes from. Printed on a student's own laptop it told them to edit
# the harness over a difference that is not theirs to fix: the pins describe
# campus, not their machine. So: the list on a campus box, one line of
# "nothing to do" anywhere else, and --strict the same on both.
# C_PISCINE_CAMPUS decides the banner in place of /goinfre, which a sandbox
# cannot make.
want_broken_none "env_drift: off campus, no re-pin advice" \
	'worth acting on' -- \
	env C_PISCINE_CAMPUS=0 "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/absent.tsv"
want_out "env_drift: ...but one line saying there is nothing to do" \
	'nothing to do here' -- \
	env C_PISCINE_CAMPUS=0 "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/absent.tsv"
want_out "env_drift: on campus, the advice names who acts on it" \
	'sh tools/env-audit.sh' -- \
	env C_PISCINE_CAMPUS=1 "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/absent.tsv"
# The report it asks for carries the student's login and the machine's name
# (env-audit.sh writes both), and an issue on the public template is a page
# anyone can read: the advice says so before it says to attach it.
want_out "env_drift: ...and to take their login out of the report first" \
	'replace your login' -- \
	env C_PISCINE_CAMPUS=1 "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/absent.tsv"
want_out "env_drift: ...and the machine's name out of its file name" \
	'rename it (its file name is the machine' -- \
	env C_PISCINE_CAMPUS=1 "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/absent.tsv"
want_red "env_drift: --strict still fails off campus" -- \
	env C_PISCINE_CAMPUS=0 "$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/absent.tsv"

# WHERE THIS CHECKOUT'S STATE IS (finding 001), read back from the output base
# the running `bazel run` uses. A campus base with no login in its path is one
# a second student collides on; one with the login is theirs alone; and off
# campus there is nothing to warn about.
#
# RUN AS `bazel run` RUNS IT, and that is the point of the layout. $0 is
# bazel-bin's symlink to the script, with nothing beside it, and the working
# directory is <target>.runfiles/_main inside the output base. These arms used
# to start the script from tools/, in a directory that merely looked like an
# output base: tools/drives.sh sat beside it there, and nowhere under `bazel
# run`, where the script looked for it -- so it exited 2 on every machine
# (setup.sh's step 4 always "did not complete") while every arm here was green.
# And any directory under an execroot was read as this checkout's state,
# including the sandbox a test runs in. So: bazel-bin's layout, no drives.sh
# anywhere in it, the workspace in BUILD_WORKSPACE_DIRECTORY as Bazel sets it,
# and two output bases, one under a folder named for the login. The same
# launcher runs init's arms below, over a tree of their own: init writes
# its git identity into the workspace it is run in.
_dr_tools=$(cd "$TOOLS" && pwd)
br_tree() {  # br_tree TREE -- that layout at $WORK/TREE
	mkdir -p "$WORK/$1/ws/tools" "$WORK/$1/home"
	cp "$TOOLS/drives.sh" "$WORK/$1/ws/tools/drives.sh"
	cp "$TOOLS/identity.sh" "$WORK/$1/ws/tools/identity.sh"
	git init -q "$WORK/$1/ws"
	for _brp in shared probe/bazel; do
		_brb="$WORK/$1/$_brp/0a1b/execroot/_main/bazel-out/k8-fastbuild/bin/tools"
		mkdir -p "$_brb/env_drift.runfiles/_main/tools" "$_brb/init.runfiles/_main/tools"
		ln -s "$_dr_tools/env_drift.sh" "$_brb/env_drift"
		ln -s "$_dr_tools/init.sh" "$_brb/init"
	done
}
br_tree br
br_run() {  # br_run TREE BASE-PARENT TARGET CAMPUS ARGS... -- as `bazel run //tools:TARGET`
	_brr=$1
	_brb="$WORK/$1/$2/0a1b/execroot/_main/bazel-out/k8-fastbuild/bin/tools"
	_brt=$3
	_brc=$4
	shift 4
	( cd "$_brb/$_brt.runfiles/_main" &&
		env BUILD_WORKSPACE_DIRECTORY="$WORK/$_brr/ws" BUILD_WORKING_DIRECTORY="$WORK/$_brr/ws" \
			GIT_CEILING_DIRECTORIES="$WORK" C_PISCINE_CAMPUS="$_brc" USER=probe \
			HOME="$WORK/$_brr/home" C_PISCINE_GOINFRE="$WORK/$_brr/no-goinfre" \
			"$SH" "$_brb/$_brt" "$@" )
}
want_green "env_drift: runs the way bazel run runs it" -- \
	br_run br shared env_drift 0 --pins "$WORK/drift/same.tsv"
want_out "env_drift: on campus, a shared Bazel root is warned about" \
	'which is not yours alone' -- br_run br shared env_drift 1 --pins "$WORK/drift/same.tsv"
want_broken_none "env_drift: ...a per-user one is not" \
	'WARNING: Bazel keeps' -- br_run br probe/bazel env_drift 1 --pins "$WORK/drift/same.tsv"
want_broken_none "env_drift: ...and off campus neither is" \
	'WARNING: Bazel keeps' -- br_run br shared env_drift 0 --pins "$WORK/drift/same.tsv"
# ...and a directory in some OTHER execroot -- a test's own runfiles, often in
# a sandbox -- is not this checkout's state: from there the root is predicted
# from the workspace, here a per-user one.
dr_elsewhere() {
	( cd "$WORK/br/shared/0a1b/execroot/_main" &&
		env C_PISCINE_CAMPUS=1 USER=probe HOME="$WORK/br/home" \
			C_PISCINE_SCRATCH="$WORK/br/probe" \
			"$SH" "$_dr_tools/env_drift.sh" --pins "$WORK/drift/same.tsv" )
}
want_broken_none "env_drift: another tree's execroot is not read as its state" \
	'WARNING: Bazel keeps' -- dr_elsewhere

# An unset HERMETIC_* means the pin-vs-fetch comparison did not happen. It used
# to print an advisory line and `continue` without counting anything, so the
# third of the three comparisons this script calls non-optional could vanish one
# variable at a time while the run still reported no drift.
#
# Two rows, so that ONE of them is set: all of them unset is a hand-run outside
# Bazel, where there is nothing fetched to compare and saying "drift" would cry
# wolf on every standalone invocation. That distinction is the fix, not the
# counter.
{
	printf 'true\tcampus\t8.32\techo 8.32\tfixture\tSELFTEST_FETCHED\n'
	printf 'true\tcampus\t8.32\techo 8.32\tfixture\tSELFTEST_UNSET\n'
} > "$WORK/drift/halfset.tsv"
printf '#!/bin/sh\necho "GNU coreutils 8.32"\n' > "$WORK/drift/fetched_ok.sh"
chmod +x "$WORK/drift/fetched_ok.sh"
want_out "env_drift: an unset HERMETIC_* is a comparison that did not run" \
	'NOT COMPARED' -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched_ok.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/halfset.tsv"
want_red "env_drift: --strict fails when a pinned binary was never compared" -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched_ok.sh" \
		"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/halfset.tsv"
# ...and neither it, nor a variable naming no executable, is a pin edited
# in one place, which the FETCH DRIFT banner says of every line it lists:
# each is a fault of //tools:env_drift's data, listed under a banner of its
# own (V326). Counted all the same, and --strict still fails on them.
want_broken_none "env_drift: ...listed under no banner that blames a pin" 'FETCH DRIFT' -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched_ok.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/halfset.tsv"
want_out "env_drift: ...but under one that names the target's data" \
	"each line is a fault in //tools:env_drift's" -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched_ok.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/halfset.tsv"
want_out "env_drift: a fetched path that is not there is MISSING" \
	"fetched:  MISSING at $WORK/drift/nowhere.sh" -- \
	env SELFTEST_FETCHED="$WORK/drift/nowhere.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/fetch.tsv"
want_broken_none "env_drift: ...which blames no pin edit" 'FETCH DRIFT' -- \
	env SELFTEST_FETCHED="$WORK/drift/nowhere.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/fetch.tsv"
want_red "env_drift: ...and --strict fails on" -- \
	env SELFTEST_FETCHED="$WORK/drift/nowhere.sh" \
		"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/fetch.tsv"
printf '#!/bin/sh\necho 8.32\n' > "$WORK/drift/noexec.sh"
want_out "env_drift: a fetched path that is no executable is named so" \
	"names $WORK/drift/noexec.sh, which is not an executable" -- \
	env SELFTEST_FETCHED="$WORK/drift/noexec.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/fetch.tsv"
want_broken_none "env_drift: ...and blames no pin edit either" 'FETCH DRIFT' -- \
	env SELFTEST_FETCHED="$WORK/drift/noexec.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/fetch.tsv"

# KIND `fetched`: the box is not consulted. shellcheck, zig and buildifier are
# downloaded against a sha256 and every layer runs the downloaded copy, so this
# machine's apt shellcheck 0.8.0 beside our pinned 0.10.0 is not a finding --
# and reporting it as one would put a permanent red in front of the check whose
# whole value is that a red means something. The box here reports 9.9 and the
# pin says 8.32; the only verdict that may appear is the fetch's.
printf 'true\tfetched\t8.32\ttrue --version\tfixture\tSELFTEST_FETCHED\n' \
	> "$WORK/drift/fetchedkind.tsv"
printf '#!/bin/sh\necho "GNU coreutils 8.32"\n' > "$WORK/drift/fk_ok.sh"
chmod +x "$WORK/drift/fk_ok.sh"
want_broken_none "env_drift: a fetched-kind row ignores the box's copy" \
	'DRIFT' -- \
	env SELFTEST_FETCHED="$WORK/drift/fk_ok.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/fetchedkind.tsv"
# ...and it is still COMPARED. A kind that silences the box half and counts
# nothing would be a row that can never fail -- which is the shape this whole
# file exists to hunt.
printf '#!/bin/sh\necho "GNU coreutils 9.9"\n' > "$WORK/drift/fk_bad.sh"
chmod +x "$WORK/drift/fk_bad.sh"
want_red "env_drift: --strict still fails on a fetched-kind mismatch" -- \
	env SELFTEST_FETCHED="$WORK/drift/fk_bad.sh" \
		"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/fetchedkind.tsv"

# A version command of `-` is "recorded here, deliberately not probed" -- bazel
# and bazelisk, which cannot be asked their version from inside a `bazel run`
# without contending for the lock that run holds. It must say so rather than
# treat `-` as a command, which would report the tool MISSING and, for a
# campus-kind row, fail --strict on a machine with nothing wrong with it.
printf 'bazel\tours\t9.2.0\t-\t.bazelversion\n' > "$WORK/drift/recorded.tsv"
want_out "env_drift: a not-probed pin says so instead of probing" \
	'recorded 9.2.0 (not probed: .bazelversion)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/recorded.tsv"
want_green "env_drift: ...and --strict does not fail on one" -- \
	"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/recorded.tsv"
# ...whatever its kind: rust-std-i686 is a FETCHED row with `-`, a library
# with no command. And a fetched row with no fetched-as column (rustc, which
# no layer of a student's runs) names no fetched binary to compare. Both
# printed "not taken from this box" and were counted in no bucket, so the
# summary line did not account for every row of pins.tsv.
{
	printf 'rust-std\tfetched\t1.0\t-\tfixture\n'
	printf 'rustc\tfetched\trustc 1.0\trustc --version\tfixture\n'
} > "$WORK/drift/recfetched.tsv"
want_out "env_drift: a fetched row with - is recorded, not taken from the box" \
	'rust-std    fetched recorded 1.0 (not probed: fixture)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/recfetched.tsv"
want_out "env_drift: ...and so is one with no fetched-as column" \
	'rustc       fetched recorded rustc 1.0 (not probed: no fetched-as column; fixture)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/recfetched.tsv"
want_out "env_drift: ...each counted in the summary line" \
	'0 unrunnable, 2 recorded' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/recfetched.tsv"

# THE FIRST LINE WITH A VERSION ON IT, not the first line with content. perl
# forced this once (a blank first line); shellcheck went further -- its
# --version prints a fixed banner first and "version: 0.10.0" on the line after,
# so pinning "the first line with content" pins a string identical in every
# release, i.e. a pin that can never report drift.
# No escape for the space in "version: 0.10.0": the row is a COMMAND, split on
# whitespace, and dash's `printf %b` reads \0400 as a four-digit octal escape
# rather than \040 followed by a zero -- so the fixture printed "version:.10.0"
# and the arm failed on its own quoting rather than on the runner. The banner is
# the point; the space is not.
printf 'true\tcampus\tversion:0.10.0\tprintf %%s\\n Banner version:0.10.0\tfixture\n' \
	> "$WORK/drift/banner.tsv"
want_out "env_drift: a banner before the version is skipped" \
	'true        campus  ok' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/banner.tsv"

# The fetch probe must use the ROW's flags. `zig --version` is an error -- the
# subcommand is `zig version` -- so a hardcoded --version reports the pinned zig
# as unversioned and grades a correct fetch as major drift.
printf 'zig\tfetched\t0.13.0\tzig version\tfixture\tSELFTEST_FETCHED\n' \
	> "$WORK/drift/subcmd.tsv"
printf '#!/bin/sh\n[ "$1" = version ] || { echo "error: unknown flag $1" >&2; exit 1; }\necho 0.13.0\n' \
	> "$WORK/drift/zigish.sh"
chmod +x "$WORK/drift/zigish.sh"
want_out "env_drift: the fetch probe uses the row's own flags" \
	'fetched:  ok (0.13.0)' -- \
	env SELFTEST_FETCHED="$WORK/drift/zigish.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/subcmd.tsv"

# THE C++ TOOLCHAIN BAZEL CACHED, which no pins row can see. `cc_binary` uses
# Bazel's auto-detected toolchain; detection runs ONCE per output base and
# writes ABSOLUTE paths into local_config_cc's BUILD. It does not re-run because
# PATH changed -- so a student who had Homebrew on PATH when it ran, and then
# uninstalled Homebrew (which this repo recommends, because that brew shadows
# the pinned binutils), gets every link dying with
# "execvp(~/.linuxbrew/bin/ar): No such file or directory". That happened on a
# campus box. pins.tsv's `ar` row cannot catch it: the box's ar is present and
# correct; what is broken is the path a cached toolchain still points at.
mkdir -p "$WORK/drift/ws/tools" \
	"$WORK/drift/our/abc123/external/rules_cc++cc_configure_extension+local_config_cc"
cp "$TOOLS/pins.tsv" "$WORK/drift/ws/tools/pins.tsv" 2>/dev/null || \
	printf 'true\tours\t1\ttrue --version\tfixture\n' > "$WORK/drift/ws/tools/pins.tsv"
cp "$TOOLS/drives.sh" "$WORK/drift/ws/tools/drives.sh"
printf 'startup --output_user_root=%s/drift/our\n' "$WORK" > "$WORK/drift/ws/.bazelrc.local"
_ccb="$WORK/drift/our/abc123/external/rules_cc++cc_configure_extension+local_config_cc/BUILD"

dr_toolchain() {
	env BUILD_WORKSPACE_DIRECTORY="$WORK/drift/ws" "$SH" "$TOOLS/env_drift.sh"
}
# The BUILD as rules_cc writes it (read off one this machine's Bazel
# generated): tool_paths opens with its first pair, takes one pair a line,
# and closes on the last. Written on one line, as every fixture here once
# was, it hid that this read no path at all from the real file.
dr_ccbuild() {  # dr_ccbuild FILE AR LD -- a local_config_cc BUILD, its ar at AR and its ld at LD
	printf 'cc_toolchain_config(\n    name = "local",\n    cxx_builtin_include_directories = ["/usr/include",\n    "/usr/include/c++/10"],\n    tool_paths = {"ar": "%s",\n        "ld": "%s",\n        "cpp-module-deps-scanner": "deps_scanner_wrapper.sh",\n        "validate_static_library": "validate_static_library.sh"},\n    compile_flags = ["-fstack-protector",\n    "-Wall"],\n)\n' \
		"$2" "$3" > "$1"
}

dr_ccbuild "$_ccb" /nonexistent/linuxbrew/bin/ar /bin/sh
want_out "env_drift: a cached toolchain path that vanished is named" \
	'/nonexistent/linuxbrew/bin/ar' -- dr_toolchain
dr_ccbuild "$_ccb" /bin/sh /nonexistent/linuxbrew/bin/ld
want_out "env_drift: ...on whichever line of the dict it is" \
	'/nonexistent/linuxbrew/bin/ld' -- dr_toolchain
# ...and it must stay QUIET when every recorded tool resolves, or it is a
# permanent red that teaches people to skim the whole report.
dr_ccbuild "$_ccb" /bin/sh /bin/sh
want_broken_none "env_drift: a healthy toolchain is not reported" \
	'STALE C++' -- dr_toolchain
# ...and on a checkout with NO .bazelrc.local, the usual case now that
# tools/bazel supplies a per-user root: this read that one file with a sed of
# its own, so there it looked at nothing. It asks tools/drives.sh for the root,
# predicted the way the wrapper chooses it -- here from C_PISCINE_SCRATCH.
mv "$WORK/drift/ws/.bazelrc.local" "$WORK/drift/ws/bazelrc.local.aside"
_ccd="$WORK/drift/scr/bazel/abc123/external/rules_cc++cc_configure_extension+local_config_cc"
mkdir -p "$_ccd"
dr_ccbuild "$_ccd/BUILD" /nonexistent/wrapper/bin/ar /bin/sh
dr_default() {
	env BUILD_WORKSPACE_DIRECTORY="$WORK/drift/ws" C_PISCINE_SCRATCH="$WORK/drift/scr" \
		HOME="$WORK/drift/home" "$SH" "$TOOLS/env_drift.sh"
}
want_out "env_drift: ...also on the wrapper's default root" \
	'/nonexistent/wrapper/bin/ar' -- dr_default
mv "$WORK/drift/ws/bazelrc.local.aside" "$WORK/drift/ws/.bazelrc.local"

# ...but a hand-run with NOTHING set is not a finding: outside Bazel none of the
# HERMETIC_* variables exist, and every standalone --strict would otherwise fail
# for a reason that has nothing to do with the box.
want_green "env_drift: a hand-run outside Bazel is not fetch drift" -- \
	"$SH" "$TOOLS/env_drift.sh" --strict --pins "$WORK/drift/same.tsv"

# A pin that is not a version at all. `default-std <cc>` asks a compiler what
# standard it assumes when nobody says -- the answer that decides whether five
# of c-12's contracts accept correct code -- and it has to grade like any other
# row rather than falling through the version extractor as "no number found".
printf 'true\tcampus\t201710L gnu\tdefault-std %s\tfixture\n' "$CC" \
	> "$WORK/drift/std.tsv"
want_out "env_drift: it can pin a compiler's default standard" 'true        campus  ok' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/std.tsv"
printf 'true\tcampus\t202311L gnu\tdefault-std %s\tfixture\n' "$CC" \
	> "$WORK/drift/std_bad.tsv"
want_out "env_drift: and a moved standard is drift, not a shrug" 'DRIFT' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/std_bad.tsv"

# A row whose NAME is not the name of any binary. glibc is asked with `ldd
# --version`, because a C library has no executable of its own, and testing the
# row name reported the runtime every deliverable links against as MISSING on a
# machine that obviously has it. The presence check has to follow the command.
printf 'not_a_binary_name\tcampus\t8.32\techo 8.32\tfixture\n' > "$WORK/drift/named.tsv"
want_out "env_drift: a row named after no binary is not missing" \
	'not_a_binary_name campus  ok' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/named.tsv"

# A fetched binary whose own libraries are not where it says they are. This
# shipped, briefly, as a path built by appending /.. to a FILE: the directory
# does not exist, the loader falls back to the machine's own libraries, and the
# fetched compiler reports the right version while not being the fetched
# compiler at all. Green, wrong, and invisible -- so the directories are checked
# rather than assumed, and the check has an arm.
want_out "env_drift: libraries that are not there is not a pass" 'UNRUNNABLE' -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched.sh" \
		SELFTEST_FETCHED_LIBS="$WORK/drift/nowhere/libnope.so" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/fetch.tsv"
# ...and that is a fault of the target's data, never "the pin was edited in
# one place", which the FETCH DRIFT banner says of every line it lists.
want_broken_none "env_drift: ...which is no fetch drift" 'FETCH DRIFT' -- \
	env SELFTEST_FETCHED="$WORK/drift/fetched.sh" \
		SELFTEST_FETCHED_LIBS="$WORK/drift/nowhere/libnope.so" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/fetch.tsv"

# A fetched binary that does not START (V243). On a system newer than the
# pins, the fetched binutils found no libbfd-2.38-system.so, exited 127, and
# the status was lost in a pipe: grade() read "2.38" in the loader's error,
# which is the pin, and printed "fetched: ok", with --strict exit 0. And a
# valgrind that could not start its tool graded "major" under the banner
# that blames a pin edited in one place. Both are UNRUNNABLE, counted in
# the summary line `42 doctor` reads, and --strict fails on them.
printf 'true\tcampus\tGNU nm (GNU Binutils for Ubuntu) 2.38\techo GNU nm (GNU Binutils for Ubuntu) 2.38\tfixture\tSELFTEST_FETCHED\n' \
	> "$WORK/drift/nostart.tsv"
printf '#!/bin/sh\necho "$0: error while loading shared libraries: libbfd-2.38-system.so: cannot open shared object file: No such file or directory" >&2\nexit 127\n' \
	> "$WORK/drift/noload.sh"
chmod +x "$WORK/drift/noload.sh"
dr_noload() {
	env SELFTEST_FETCHED="$WORK/drift/noload.sh" "$SH" "$TOOLS/env_drift.sh" "$@" \
		--pins "$WORK/drift/nostart.tsv"
}
want_out "env_drift: a fetched tool the loader cannot start is UNRUNNABLE" \
	'fetched:  UNRUNNABLE (exit 127: ' -- dr_noload
want_broken_none "env_drift: ...never ok, whatever version its error names" \
	'fetched:  ok' -- dr_noload
want_out "env_drift: ...counted in the summary line 42 doctor reads" \
	'0 fetch-drift, 1 unrunnable, 0 recorded' -- dr_noload
want_out "env_drift: ...under a banner that names the dev container" \
	'The dev container' -- dr_noload
want_red "env_drift: ...and --strict fails on it" -- dr_noload --strict
printf 'true\tcampus\tvalgrind-3.18.1\techo valgrind-3.18.1\tfixture\tSELFTEST_FETCHED\n' \
	> "$WORK/drift/vg.tsv"
# A stand-in valgrind.bin: the pinned version where $VALGRIND_LIB holds its
# tool, as the real one does, and its start failure everywhere else.
mkdir -p "$WORK/drift/vgtools"
: > "$WORK/drift/vgtools/memcheck-amd64-linux"
printf '#!/bin/sh\nif [ -f "${VALGRIND_LIB:-/nonexistent}/memcheck-amd64-linux" ]; then echo valgrind-3.18.1; exit 0; fi\necho "valgrind: failed to start tool '"'"'memcheck'"'"' for platform '"'"'amd64-linux'"'"': No such file or directory" >&2\nexit 1\n' \
	> "$WORK/drift/vgish.sh"
chmod +x "$WORK/drift/vgish.sh"
dr_vg() {  # dr_vg [NAME=VALUE...]
	env SELFTEST_FETCHED="$WORK/drift/vgish.sh" "$@" "$SH" "$TOOLS/env_drift.sh" \
		--pins "$WORK/drift/vg.tsv"
}
want_out "env_drift: a valgrind that cannot start its tool is UNRUNNABLE" \
	"fetched:  UNRUNNABLE (exit 1: valgrind: failed to start tool" -- dr_vg
want_broken_none "env_drift: ...and no fetch drift" 'FETCH DRIFT' -- dr_vg
want_out "env_drift: valgrind is started with its tool directory" \
	'fetched:  ok (valgrind-3.18.1)' -- \
	dr_vg SELFTEST_FETCHED_TOOLS="$WORK/drift/vgtools/memcheck-amd64-linux"
# A compiler whose driver answers --version while every compile fails (gcc's
# cc1 loads libraries the driver does not): asked to compile too, it is
# UNRUNNABLE, and the compile it could not do is named.
printf '#!/bin/sh\n[ "$1" = -fsyntax-only ] || { echo "GNU nm (GNU Binutils for Ubuntu) 2.38"; exit 0; }\necho "cc1: error while loading shared libraries: libisl.so.22: cannot open shared object file" >&2\nexit 1\n' \
	> "$WORK/drift/nocc1.sh"
chmod +x "$WORK/drift/nocc1.sh"
want_out "env_drift: a compiler that answers --version and cannot compile" \
	'fetched:  UNRUNNABLE (-fsyntax-only -x c /dev/null, exit 1: cc1: error' -- \
	env SELFTEST_FETCHED="$WORK/drift/nocc1.sh" SELFTEST_FETCHED_COMPILE="-fsyntax-only -x c /dev/null" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/nostart.tsv"
printf '#!/bin/sh\n[ "$1" = -fsyntax-only ] && exit 0\necho "GNU nm (GNU Binutils for Ubuntu) 2.38"\n' \
	> "$WORK/drift/okcc.sh"
chmod +x "$WORK/drift/okcc.sh"
want_out "env_drift: ...and one that compiles is ok" \
	'fetched:  ok (GNU nm (GNU Binutils for Ubuntu) 2.38)' -- \
	env SELFTEST_FETCHED="$WORK/drift/okcc.sh" SELFTEST_FETCHED_COMPILE="-fsyntax-only -x c /dev/null" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/nostart.tsv"

# A fetched binary that is ANOTHER TOOL (V327): objdump handed to the nm row,
# say, both 2.38. Graded on its numbers alone it read "ok", --strict exit 0.
# Its line has to hold the pin's words before the version, anywhere in it:
# the fetched gcc-10 names itself "x86_64-linux-gnu-gcc-10 (Ubuntu ...".
printf '#!/bin/sh\necho "GNU objdump (GNU Binutils for Ubuntu) 2.38"\n' \
	> "$WORK/drift/othertool.sh"
chmod +x "$WORK/drift/othertool.sh"
dr_other() {
	env SELFTEST_FETCHED="$WORK/drift/othertool.sh" "$SH" "$TOOLS/env_drift.sh" "$@" \
		--pins "$WORK/drift/nostart.tsv"
}
want_out "env_drift: a fetched binary of another tool is drift" \
	'fetched:  DRIFT (another tool)' -- dr_other
want_out "env_drift: ...naming the pin's words its line lacks" \
	"lacks the pin's words 'GNU nm (GNU Binutils for Ubuntu)'" -- dr_other
want_red "env_drift: ...which --strict fails on" -- dr_other --strict
printf 'true\tcampus\tgcc-10 (Ubuntu 10.5.0-1ubuntu1~22.04.3) 10.5.0\techo 10.5.0\tfixture\tSELFTEST_FETCHED\n' \
	> "$WORK/drift/gccname.tsv"
printf '#!/bin/sh\necho "x86_64-linux-gnu-gcc-10 (Ubuntu 10.5.0-1ubuntu1~22.04.3) 10.5.0"\n' \
	> "$WORK/drift/gccname.sh"
chmod +x "$WORK/drift/gccname.sh"
want_out "env_drift: ...but words after a prefix of its own are the tool" \
	'fetched:  ok (x86_64-linux-gnu-gcc-10 (Ubuntu' -- \
	env SELFTEST_FETCHED="$WORK/drift/gccname.sh" \
		"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/gccname.tsv"

# A tool of this BOX that does not start (V328). Its version command's
# status was lost in a pipe, as the fetch half's was before V243: a loader
# error naming libbfd-2.38, the pin's number, read "ok (repackaged)", with
# --strict exit 0, and on a campus box a re-pin to that error. It is DID
# NOT START now, counted with the missing, and its fetch is still compared.
printf 'nm\tcampus\tGNU nm (GNU Binutils for Ubuntu) 2.38\t%s --version\tfixture\tSELFTEST_FETCHED\n' \
	"$WORK/drift/noload.sh" > "$WORK/drift/boxnostart.tsv"
dr_boxno() {  # dr_boxno [NAME=VALUE...]
	env SELFTEST_FETCHED="$WORK/drift/okcc.sh" "$@" "$SH" "$TOOLS/env_drift.sh" \
		--pins "$WORK/drift/boxnostart.tsv"
}
want_out "env_drift: a box tool the loader cannot start DID NOT START" \
	'nm          campus  DID NOT START (exit 127: ' -- dr_boxno
want_broken_none "env_drift: ...never ok, whatever version its error names" \
	'campus  ok' -- dr_boxno
want_out "env_drift: ...counted with the missing" \
	'0 match, 0 drifted, 1 missing, 0 fetch-drift' -- dr_boxno
want_out "env_drift: ...its fetch still compared" \
	'fetched:  ok (GNU nm (GNU Binutils for Ubuntu) 2.38)' -- dr_boxno
want_red "env_drift: ...which --strict fails on too" -- \
	env SELFTEST_FETCHED="$WORK/drift/okcc.sh" "$SH" "$TOOLS/env_drift.sh" --strict \
		--pins "$WORK/drift/boxnostart.tsv"
want_broken_none "env_drift: ...and on campus no re-pin to its error" \
	'repackaged' -- dr_boxno C_PISCINE_CAMPUS=1
want_out "env_drift: ...but a drift line blaming the machine" \
	'nm (did not start): expected GNU nm (GNU Binutils for Ubuntu) 2.38;' -- \
	dr_boxno C_PISCINE_CAMPUS=1
want_broken_none "env_drift: ...and no re-pin advice under it" \
	're-pins by hand' -- dr_boxno C_PISCINE_CAMPUS=1
want_out "env_drift: ...but the machine named as the fault" \
	"the machine's fault, not the pins'" -- dr_boxno C_PISCINE_CAMPUS=1
want_out "env_drift: ...a campus tool that drifted still gets the re-pin advice" \
	're-pins by hand' -- \
	env C_PISCINE_CAMPUS=1 "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/absent.tsv"
printf '#!/bin/sh\necho "GNU nm (GNU Binutils for Ubuntu) 2.38"\nexit 139\n' > "$WORK/drift/boxdies.sh"
chmod +x "$WORK/drift/boxdies.sh"
printf 'nm\tcampus\tGNU nm (GNU Binutils for Ubuntu) 2.38\t%s --version\tfixture\n' \
	"$WORK/drift/boxdies.sh" > "$WORK/drift/boxdies.tsv"
want_out "env_drift: a box tool that prints its version and dies did not start" \
	'DID NOT START (exit 139: GNU nm (GNU Binutils for Ubuntu) 2.38)' -- \
	"$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/boxdies.tsv"

# --report names its file from the machine's name (V258). It was `hostname |
# tr -c ...`, which turned hostname's newline into "_" (drift-piscine_-...),
# and left the name empty where hostname was missing. Now as prime_trace.sh
# reads it: C_PISCINE_HOST, the kernel's, uname's, and "unknown" for
# anything that is no host name. Run in a workspace of its own, where it
# writes tools/env-reports/.
mkdir -p "$WORK/drift/rws/tools"
cp "$TOOLS/drives.sh" "$WORK/drift/rws/tools/drives.sh"
dr_report() {  # dr_report ENV-ARGS... -- its file's name, as it reports it
	env "$@" BUILD_WORKSPACE_DIRECTORY="$WORK/drift/rws" "$SH" "$TOOLS/env_drift.sh" \
		--report --pins "$WORK/drift/same.tsv"
}
_dr_host=""
[ -r /proc/sys/kernel/hostname ] && read -r _dr_host < /proc/sys/kernel/hostname
# conventions: optional uname -- the name env_drift falls back to without /proc;
# where neither exists, both say "unknown"
if [ -z "$_dr_host" ] && command -v uname > /dev/null 2>&1; then
	_dr_host=$(uname -n 2> /dev/null) || _dr_host=""
fi
case "$_dr_host" in '' | .* | *[!A-Za-z0-9._-]*) _dr_host=unknown ;; esac
want_out "env_drift: --report names its file from the machine's name" \
	"report written to tools/env-reports/drift-$_dr_host-2" -- dr_report -u C_PISCINE_HOST
want_out "env_drift: ...C_PISCINE_HOST first" \
	'report written to tools/env-reports/drift-box-1-2' -- dr_report C_PISCINE_HOST=box-1
want_out "env_drift: ...and unknown for a name no file can carry" \
	'report written to tools/env-reports/drift-unknown-2' -- dr_report 'C_PISCINE_HOST=bad name'
# ...and a report it could not write is said so, with exit 2, since what was
# asked for did not happen: over a tools/env-reports it could not create it
# printed both errors, then "report written to" and "commit it", exit 0.
mkdir -p "$WORK/drift/rws2/tools"
cp "$TOOLS/drives.sh" "$WORK/drift/rws2/tools/drives.sh"
: > "$WORK/drift/rws2/tools/env-reports"
dr_noreport() {
	env BUILD_WORKSPACE_DIRECTORY="$WORK/drift/rws2" "$SH" "$TOOLS/env_drift.sh" \
		--report --pins "$WORK/drift/same.tsv"
}
want_broken "env_drift: a report it cannot write is a refusal" \
	'report NOT written' -- dr_noreport
want_broken_without "env_drift: ...that never says it wrote one" \
	'report written to' -- dr_noreport

# A tools/drives.sh that fails is a run that cannot say which machine this
# is. It runs in a child sh, and only what it printed was kept: one that
# stopped on an unset variable read "machine: not a campus box ()", and the
# campus advice and the $HOME-quota warning went with it, exit 0. The shell
# this was ported from sourced it under set -u, and stopped there.
mkdir -p "$WORK/drift/bws/tools"
printf 'drives_campus() { DRIVES_CAMPUS=1; : "$DR_UNSET_42"; DRIVES_CAMPUS_WHY=x; }\n' \
	> "$WORK/drift/bws/tools/drives.sh"
dr_broken() {
	env -u DR_UNSET_42 BUILD_WORKSPACE_DIRECTORY="$WORK/drift/bws" "$SH" "$TOOLS/env_drift.sh" \
		--pins "$WORK/drift/same.tsv"
}
want_broken "env_drift: a tools/drives.sh that fails is a refusal" \
	'tools/drives.sh failed' -- dr_broken
want_broken_without "env_drift: ...never a machine that is no campus box" \
	'machine:' -- dr_broken
printf 'drives_campus() { DRIVES_CAMPUS=maybe; DRIVES_CAMPUS_WHY=x; }\n' \
	> "$WORK/drift/bws/tools/drives.sh"
want_broken "env_drift: ...and so is one that answers neither 0 nor 1" \
	"DRIVES_CAMPUS='maybe'" -- dr_broken

# ON THE PYTHON BAZEL FETCHED. The launcher runs tools/env_drift.py on the
# interpreter the target hands it, never on a python3 from PATH: a machine
# with none is one whose norminette cannot start, which is one of the things
# this has to be able to say. A stand-in that leaves a mark and starts the
# real one shows which ran; with none handed over, the launcher refuses and
# says how it is run. The refusals, and the run with no python3 on PATH
# below, are runs in //tools/tests:env_drift_test too, which keeps the
# launcher in //:gate_fast; they stay here as well, because :selftest_bash
# runs these arms under bash.
printf '#!/bin/sh\n: > "%s"\nexec "%s" "$@"\n' "$WORK/drift/py-ran" "$ENV_DRIFT_PYTHON" \
	> "$WORK/drift/py-standin"
chmod +x "$WORK/drift/py-standin"
want_out "env_drift: runs on the python3 it is handed" 'true        campus  ok' -- \
	env ENV_DRIFT_PYTHON="$WORK/drift/py-standin" "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/same.tsv"
want_green "env_drift: ...that one, and none from PATH" -- test -f "$WORK/drift/py-ran"
want_broken "env_drift: with no python3 handed over, says how to run it" \
	'run it as bazel run //tools:env_drift' -- \
	env -u ENV_DRIFT_PYTHON "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/same.tsv"
want_broken "env_drift: ...nor with no file to run on it" \
	'run it as bazel run //tools:env_drift' -- \
	env -u ENV_DRIFT_MAIN "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/same.tsv"
want_broken "env_drift: ...nor with one that is no program" \
	'is no executable' -- \
	env ENV_DRIFT_PYTHON="$WORK/drift/same.tsv" "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/same.tsv"
# And so, on a PATH with every program this one has but python3, it still
# runs to the end and says norminette is missing, as any absent tool is.
# Its probe printed "(norminette not importable)" instead, which was graded
# as a version: DRIFT (major), counted with the drifted, and on campus a
# re-pin to that text. (That PATH is made by this section's shard alone: it
# is a link for each program on PATH.)
mkdir -p "$WORK/drift/nopy"
_dr_ifs=$IFS
IFS=:
# shellcheck disable=SC2086 # split on IFS, the colons, on purpose
! st_mine || for _dr_d in $PATH; do
	[ -d "$_dr_d" ] || continue
	for _dr_f in "$_dr_d"/*; do
		case "${_dr_f##*/}" in python* | pydoc* | py3*) continue ;; esac
		[ -x "$_dr_f" ] && [ ! -e "$WORK/drift/nopy/${_dr_f##*/}" ] &&
			ln -s "$_dr_f" "$WORK/drift/nopy/${_dr_f##*/}"
	done
done
IFS=$_dr_ifs
printf 'norminette\tcampus\t3.3.58\tnorminette-version\tfixture\n' > "$WORK/drift/nopy.tsv"
want_out "env_drift: with no python3 on PATH, still says norminette is missing" \
	'norminette  campus  MISSING   (expected 3.3.58)' -- \
	env PATH="$WORK/drift/nopy" "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/nopy.tsv"
want_out "env_drift: ...counted with the missing, not the drifted" \
	'0 match, 0 drifted, 1 missing' -- \
	env PATH="$WORK/drift/nopy" "$SH" "$TOOLS/env_drift.sh" --pins "$WORK/drift/nopy.tsv"
unset ENV_DRIFT_PYTHON ENV_DRIFT_MAIN
