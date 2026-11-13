# ------------------------------------------------------------------ probe_under
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Bazel's --run_under for measuring what a case list catches: every program a
# runner is handed to run becomes PROBE_STANDIN, under the name it replaces,
# and the reference (--baseline-bin) is left alone. The toy runner runs its
# --bin and names its --baseline-bin; the stand-in says what it stands in for.
mkdir -p "$WORK/pu"
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do case $1 in --bin) "$2"; shift 2 ;; --baseline-bin) echo "reference ${2##*/}"; shift 2 ;; *) shift ;; esac; done\n' \
	> "$WORK/pu/runner.sh"
printf '#!/bin/sh\necho "the student program ran"\n' > "$WORK/pu/ex01_bin"
printf '#!/bin/sh\necho "stand-in as ${0##*/} for ${PROBE_BIN##*/}"\n' > "$WORK/pu/standin"
chmod +x "$WORK/pu/runner.sh" "$WORK/pu/ex01_bin" "$WORK/pu/standin"
pu_run() {  # pu_run STANDIN RUNNER-ARGS...
	_pu=$1; shift
	env PROBE_STANDIN="$_pu" TEST_TMPDIR="$WORK/pu" \
		"$SH" "$TOOLS/probe_under.sh" "$WORK/pu/runner.sh" "$@"
}
want_out   "probe_under: the stand-in runs in the program's place, under its name" \
	'stand-in as ex01_bin for ex01_bin' -- \
	pu_run "$WORK/pu/standin" --bin "$WORK/pu/ex01_bin" --baseline-bin "$WORK/pu/ref"
want_broken_none "probe_under: ...and the program does not run" 'the student program ran' -- \
	pu_run "$WORK/pu/standin" --bin "$WORK/pu/ex01_bin"
want_out   "probe_under: ...while the reference is left alone" 'reference ref' -- \
	pu_run "$WORK/pu/standin" --bin "$WORK/pu/ex01_bin" --baseline-bin "$WORK/pu/ref"
want_out   "probe_under: a test with no program says its verdict is not the probe's" \
	'its verdict is not the stand-in' -- pu_run "$WORK/pu/standin" --other x
want_broken "probe_under: no stand-in refuses" 'set the stand-in' -- \
	"$SH" "$TOOLS/probe_under.sh" "$WORK/pu/runner.sh" --bin "$WORK/pu/ex01_bin"
want_broken "probe_under: a relative stand-in refuses" 'must be absolute' -- \
	pu_run pu/standin --bin "$WORK/pu/ex01_bin"

# A real runner, through the flag it takes its program by: progname_test.sh
# took it as a plain argument, so a probe ran the student's program in every
# _progname target and said the test was handed none. The stand-in prints
# what it stands in for, and the runner shows what it printed.
want_out   "probe_under: progname_test.sh's program is swapped too" \
	'stand-in as a.out for ex01_bin' -- \
	env PROBE_STANDIN="$WORK/pu/standin" TEST_TMPDIR="$WORK/pu" \
		"$SH" "$TOOLS/probe_under.sh" "$SH" "$TOOLS/progname_test.sh" --bin "$WORK/pu/ex01_bin"
