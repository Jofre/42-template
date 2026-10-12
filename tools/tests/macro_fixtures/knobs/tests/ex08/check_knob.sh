#!/bin/sh
# The toy check-mode exercise's check, named by shell_exercise's `check`
# (see ../../BUILD.bazel). No test runs it: the package proves the wiring.
# shellcheck source=tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-toy.sh}
ck_require "toy.sh exists" test -f "$D"
ck_report
