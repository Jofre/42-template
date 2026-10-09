#!/bin/sh
# 42 -- one command over this repo's Bazel harness (docs/testing.md, "The 42
# command"). This file only finds the checkout and a python3, then hands over
# to tools/fortytwo/main.py; every command is described in
# tools/fortytwo/commands.tsv, which `42 help` prints.
#
# Usage:
#   sh tools/42.sh [command] [args]      # from anywhere inside a checkout
#   bazel run //tools:42 -- [command]    # the same, before setup.sh has run
#   42 [command] [args]                  # once setup.sh has installed the shim
#
# Exit status: the command's own -- for a test run, Bazel's (0 all passed,
# 3 a test failed, 1 something did not build, 4 nothing to run, 8 stopped).
# 2 is a usage error, as it is for Bazel.
#
# WHERE THE CHECKOUT IS. Under `bazel run` this script sits in a runfiles tree
# inside the output base, so its own path says nothing about the checkout:
# Bazel names the checkout in BUILD_WORKSPACE_DIRECTORY and the folder the
# command was typed in in BUILD_WORKING_DIRECTORY. Run directly, the checkout
# is the folder above tools/, and the folder typed in is the current one.
set -u

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "42.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require dirname

if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
	FT_WS=$BUILD_WORKSPACE_DIRECTORY
	FT_CWD=${BUILD_WORKING_DIRECTORY:-$BUILD_WORKSPACE_DIRECTORY}
else
	FT_WS=$(cd "$(dirname "$0")/.." && pwd) || exit 2
	FT_CWD=$PWD
fi
export FT_WS FT_CWD

# 3.10 is the python3 of Ubuntu 22.04, the campus release tools/pins.tsv
# records (no campus capture has confirmed the python3 yet). Without
# a python3 that new, the one thing 42 cannot do is run, so it says what to
# type instead: the Bazel command and the report 42 would have read.
# conventions: optional python3 -- probed here; without it 42 runs nothing and prints the Bazel command to type instead
if ! command -v python3 > /dev/null 2>&1 ||
	! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2> /dev/null; then
	echo "42: needs python3 3.10 or newer, and this machine has $(python3 --version 2> /dev/null || echo none)." >&2
	echo "    Without it, run the tests of a project as 42 would:" >&2
	echo "    bazel test //c-piscine/c-piscine-c-05/... --test_tag_filters=lvl_basic,-manual 2>&1 | sh tools/first_red.sh" >&2
	exit 2
fi

# -I: no PYTHONPATH, no user site-packages, no current folder on sys.path, so
# a file named like a module in the folder you stand in is never imported.
exec python3 -I "$FT_WS/tools/fortytwo/main.py" "$@"
