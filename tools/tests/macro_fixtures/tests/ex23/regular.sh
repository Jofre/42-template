#!/bin/sh
# The toy redirect exercise's reading, emitted at strict as ex23_regular: a
# reading runs the same turn-in, so it reads the same fixture.
# shellcheck source=../../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D=${1:-toy.sh}
ck_require "toy.sh exists" test -f "$D"
ck_report
