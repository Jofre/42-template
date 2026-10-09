#!/bin/sh
# The toy shell exercise's check (see ../../BUILD.bazel): what a check for a
# script turn-in with stable = True holds -- the parse check the call's
# script = "sh" relies on, and the comparison of the generator's two runs.
# shellcheck source=../../../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-toy.sh}
ck_require "toy.sh exists" test -f "$D"
ck_sh_parses "$D"
ck_stable "toy.sh is the same on every run of the generator" "$D"
ck_report
