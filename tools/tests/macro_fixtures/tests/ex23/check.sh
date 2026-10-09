#!/bin/sh
# The toy redirect exercise's check (see ../../BUILD.bazel): its runs read
# toy.conf, beside this file, wherever the turn-in opens /etc/toy.conf. What
# the redirect does to a run is shell_test.sh's, proven by the selftest's
# --redirect arms; this toy proves the macro hands it to every target that
# runs the turn-in (:redirect_args).
# shellcheck source=../../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-toy.sh}
ck_require "toy.sh exists" test -f "$D"
ck_sh_parses "$D"
ck_report
