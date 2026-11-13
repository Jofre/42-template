#!/bin/sh
# env_drift.sh — has anything drifted from what tools/pins.tsv expects?
#
# The script of //tools:env_drift, and only its launcher: what it compares,
# how it grades a difference and why it warns rather than fails are
# tools/env_drift.py's, and its header says each.
#
# Usage:
#   bazel run //tools:env_drift [-- [--strict] [--report]]
#
# ON THE PYTHON BAZEL FETCHED, NEVER ON THE BOX'S. This has to run, and say
# what it found, on a machine with no python3 at all: that is a machine
# whose norminette cannot start, which is one of the things it reports. A
# py_binary would not: its own launcher starts on the python3 on PATH, and
# stops with "/usr/bin/env: 'python3': No such file or directory" before
# any of this runs (the owner's decision of 2026-10-31). So the target
# hands over the fetched interpreter itself, ENV_DRIFT_PYTHON, and the file
# it runs, ENV_DRIFT_MAIN, both paths in its runfiles; a relative one is
# read from the directory this started in, as Bazel writes them. -I keeps
# the environment and the user's site out of the interpreter, and -X utf8
# lets every byte a tool prints come back out as it went in.
#
# Neither is the probes' business: both are taken out of the environment
# before the interpreter starts, so every tool it asks sees what the caller
# gave this script. Python started in the C locale sets LC_CTYPE for itself
# and its children, which nothing can turn off, so what LC_CTYPE was here
# goes with the call ("=<value>", or nothing for none), and env_drift.py
# puts it back. Its $0 and $PWD go too: which `bazel run` started it is read
# from them (tools/drives.sh, drives_run_base).
set -u

py=${ENV_DRIFT_PYTHON:-}
main=${ENV_DRIFT_MAIN:-}
if [ -z "$py" ] || [ -z "$main" ]; then
	echo "env_drift.sh: ENV_DRIFT_PYTHON and ENV_DRIFT_MAIN are unset, so there is no Python to run" >&2
	echo "  tools/env_drift.py with: run it as bazel run //tools:env_drift" >&2
	exit 2
fi
case "$py" in /*) ;; *) py="$PWD/$py" ;; esac
case "$main" in /*) ;; *) main="$PWD/$main" ;; esac
if [ ! -x "$py" ] || [ ! -f "$main" ]; then
	echo "env_drift.sh: ENV_DRIFT_PYTHON ($py) is no executable, or ENV_DRIFT_MAIN ($main)" >&2
	echo "  no file: fix //tools:env_drift's env, and run it as bazel run //tools:env_drift" >&2
	exit 2
fi
unset ENV_DRIFT_PYTHON ENV_DRIFT_MAIN
exec "$py" -I -X utf8 "$main" "$0" "$PWD" "${LC_CTYPE+=$LC_CTYPE}" "$@"
