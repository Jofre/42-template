#!/bin/sh
# regen.sh — regenerate this exercise's fixtures from the Rust reference.
#
# Maintenance helper only; no BUILD rule depends on it. Run it after changing
# the curated case list (oracle/src/rush00.rs, const FIXED), the survival
# cases (const SURVIVE) or anything else `oracle rush00_fixtures` writes:
#
#     sh c-piscine/c-piscine-rush-00/tests/ex00/regen.sh
#
# It runs the reference's own self-check, then
#
#     bazel run //c-piscine/c-piscine-rush-00:ex00_oracle_fixtures -- --write
#
# which rewrites, in this directory, every file that test holds to the
# reference. Which files those are is written once, in the BUILD file's
# RUSH00_OWNED: this script used to pass the same patterns again, by hand,
# a third copy of one list (the test's data was the second).
set -eu

HERE=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# The repo root is the nearest directory above that holds MODULE.bazel. It used
# to be a fixed "../../..", which named the root only while this module sat at
# the top level; one course folder deeper it named the course folder, and the
# script went looking for the oracle in a bazel-bin that is not there.
ROOT=$HERE
while [ ! -f "$ROOT/MODULE.bazel" ]; do
	[ "$ROOT" = / ] && { echo "regen.sh: no MODULE.bazel above $HERE" >&2; exit 1; }
	ROOT=$(dirname "$ROOT")
done
command -v bazel > /dev/null 2>&1 || { echo "regen.sh: needs bazel, the repo's one entry point" >&2; exit 1; }
cd "$ROOT"

bazel run --ui_event_filters=-info --noshow_progress //oracle:oracle -- check > /dev/null ||
	{ echo "regen.sh: oracle self-check FAILED — refusing to regenerate" >&2; exit 1; }
bazel run --ui_event_filters=-info --noshow_progress \
	//c-piscine/c-piscine-rush-00:ex00_oracle_fixtures -- --write > /dev/null ||
	{ echo "regen.sh: could not write the fixtures" >&2; exit 1; }

echo "regen.sh: fixtures rewritten in $HERE"
