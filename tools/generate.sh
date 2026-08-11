#!/bin/sh
# Regenerate the disposable deliverable/ tree of one or more shell modules from
# their generators/. The student's answer lives in generators/exNN.sh; this turns
# those answers into the files that get submitted.
#
# Run via Bazel (so it can find the repo root and write the source tree):
#     bazel run //c-piscine-shell-00:generate          # one module
#     bazel run //tools:generate                        # every shell module
#
# Each generators/exNN.sh runs with its current directory set to a freshly wiped
# deliverable/exNN (so a previous run's leftover files / odd permissions can never
# get in the way). If the module ships a resources.tar.gz, a copy is placed in the
# scratch dir for the generator to use and removed afterwards.

set -u

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "generate.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require basename cp dirname mkdir rm

# Repo root: from `bazel run` it's BUILD_WORKSPACE_DIRECTORY; run directly it's the
# parent of tools/.
WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"

[ "$#" -gt 0 ] || { echo "generate.sh: need at least one module name" >&2; exit 2; }

for MOD in "$@"; do
	dir="$WS/$MOD"
	if [ ! -d "$dir/generators" ]; then
		echo "generate.sh: no generators/ in $MOD — skipped" >&2
		continue
	fi
	res=""
	[ -f "$dir/resources.tar.gz" ] && res="$dir/resources.tar.gz"
	for g in "$dir"/generators/ex*.sh; do
		[ -f "$g" ] || continue
		ex=$(basename "$g" .sh)
		out="$dir/deliverable/$ex"
		rm -rf "$out"
		mkdir -p "$out"
		[ -n "$res" ] && cp "$res" "$out/resources.tar.gz"
		( cd "$out" && sh "$g" )
		[ -n "$res" ] && rm -f "$out/resources.tar.gz"
		echo "generated $MOD/deliverable/$ex"
	done
done
