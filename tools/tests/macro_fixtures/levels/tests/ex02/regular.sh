#!/bin/sh
# The toy shell exercise's second reading, emitted at strict as ex02_regular.
# shellcheck source=../../../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-toy.sh}
ck_require "toy.sh exists" test -f "$D"
ck_report
