#!/bin/sh
# Regenerate the disposable deliverable/ tree of one or more shell modules from
# their generators/. The student's answer lives in generators/exNN.sh; this turns
# those answers into the files that get submitted.
#
# Run via Bazel (so it can find the repo root and write the source tree):
#     bazel run //c-piscine/c-piscine-shell-00:generate          # one module
#     bazel run //tools:generate                        # every shell module
#
# Each generators/exNN.sh runs with its current directory set to a freshly wiped
# deliverable/exNN (so a previous run's leftover files / odd permissions can never
# get in the way). If the module ships a resources.tar.gz, a copy is placed in the
# scratch dir for the generator to use and removed afterwards.
#
# Only exercises WITH a generator are touched, which is what lets one project
# mix the two kinds (Piscine Reloaded: shell ex00-ex05 generated, C ex06-ex27
# hand-written). And a generator is never allowed to wipe hand-written work: a
# deliverable/exNN holding C sources, headers or a Makefile is refused, loudly,
# because a generators/exNN.sh created for the wrong number would otherwise
# delete the student's code without a word. The same goes for a deliverable/exNN
# holding ANY file while its generator is still the skeleton it shipped as: the
# easy mistake in a mixed project is to write find_sh.sh straight into
# deliverable/ex03 the way ex06-ex27 are written, and that directory is
# gitignored, so the work was never committed and a wipe loses it for good.

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
require awk basename cp dirname mkdir rm

# Repo root: from `bazel run` it's BUILD_WORKSPACE_DIRECTORY; run directly it's the
# parent of tools/.
WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"

[ "$#" -gt 0 ] || { echo "generate.sh: need at least one module name" >&2; exit 2; }

# Is generator $1 still a skeleton -- nothing in it but comments, blank lines
# and the no-op `:` it ships with? Same reading as tools/stub_check.sh's.
skeleton() {
	awk '
		{ l = $0; gsub(/^[ \t]+|[ \t]+$/, "", l) }
		l == "" || l ~ /^#/ || l == ":" || l == "true" { next }
		{ found = 1; exit }
		END { exit found ? 1 : 0 }
	' "$1"
}

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
		for _f in "$out"/*.c "$out"/*.h "$out"/Makefile; do
			[ -e "$_f" ] || continue
			echo "generate.sh: $MOD/deliverable/$ex holds hand-written work ($(basename "$_f"))," >&2
			echo "  and generators/$ex.sh would wipe it. Is the generator numbered for the" >&2
			echo "  wrong exercise? Nothing was generated for $ex." >&2
			exit 2
		done
		if skeleton "$g"; then
			for _f in "$out"/* "$out"/.[!.]* "$out"/..?*; do
				[ -e "$_f" ] || [ -L "$_f" ] || continue
				echo "generate.sh: $MOD/deliverable/$ex holds $(basename "$_f"), but" >&2
				echo "  generators/$ex.sh has no commands yet, so generating would wipe it" >&2
				echo "  and put nothing back. In this project deliverable/$ex is rebuilt" >&2
				echo "  from the generator and never committed: write the commands that" >&2
				echo "  create your turn-in in generators/$ex.sh. Nothing was generated for $ex." >&2
				exit 2
			done
		fi
		rm -rf "$out"
		mkdir -p "$out"
		[ -n "$res" ] && cp "$res" "$out/resources.tar.gz"
		( cd "$out" && sh "$g" )
		[ -n "$res" ] && rm -f "$out/resources.tar.gz"
		echo "generated $MOD/deliverable/$ex"
	done
done
