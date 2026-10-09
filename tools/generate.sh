#!/bin/sh
# Regenerate the disposable deliverable/ tree of one or more generator-based
# modules from their generators/. The student's answer lives in
# generators/exNN.sh; this turns those answers into the files that get submitted.
#
# Run via Bazel (so it can find the repo root and write the source tree):
#     bazel run //c-piscine/c-piscine-shell-00:generate   # one module
#     bazel run //tools:generate     # every generated exercise: Shell 00, Shell 01
#                                    # and Piscine Reloaded ex00-ex05
#
# Each generators/exNN.sh runs with its current directory set to a fresh, empty
# scratch directory beside deliverable/ (so a previous run's leftover files / odd
# permissions can never get in the way), and what it leaves there REPLACES
# deliverable/exNN -- only if the generator exited 0, and only if nothing in
# deliverable/exNN would be lost. 42's own files that a module's tests read
# (tools/resources.tsv, role `harness`: shell-00's resources.tar.gz) are copied
# from the one path the registry names into the scratch dir, under their own
# name, for the generator to use, and removed before the result is moved into
# place.
#
# Only exercises WITH a generator are touched, which is what lets one project
# mix the two kinds (Piscine Reloaded: shell ex00-ex05 generated, C ex06-ex27
# hand-written). And generate never deletes a file it did not make. It refuses,
# names the file, and moves on to the next exercise, when deliverable/exNN is a
# file rather than a folder, or when it holds:
#   * C sources, headers or a Makefile -- a generators/exNN.sh created for the
#     wrong number would otherwise delete the student's code without a word;
#   * one of 42's registered files (resources.tar.gz), saved in the exercise's
#     folder rather than at the one path tools/resources.tsv names, which is
#     the only place the harness reads it;
#   * ANY file while the generator is still the skeleton it shipped as: the easy
#     mistake in a mixed project is to write find_sh.sh straight into
#     deliverable/ex03 the way ex06-ex27 are written, and that directory is
#     gitignored, so the work was never committed and a wipe loses it for good;
#   * any file the generator did not produce on this run: something put there by
#     hand, or an earlier version's output under a name it no longer writes.
#
# A refusal does not stop the run, which would silently skip every later
# exercise and, under //tools:generate, every later module: each one is
# recorded, the run carries on, and the end of the run lists everything that was
# not generated. Exit status: 0 = every exercise generated; 1 = a generator
# failed (its own error is above); 2 = something was refused or could not be put
# in place, or the run could not start -- 2 whenever both happened. And never
# "generated" unless the result is in place: //tools:submit stops a module on
# any of them.

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
require awk basename chmod cp dirname find mkdir mv rm sed

# Repo root: from `bazel run` it's BUILD_WORKSPACE_DIRECTORY; run directly it's the
# parent of tools/.
WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"

[ "$#" -gt 0 ] || { echo "generate.sh: need at least one module name" >&2; exit 2; }

# 42's files this module's tests read, one "NAME<TAB>PATH" line each, from
# tools/resources.tsv: the rows for $1 whose role is harness. Nothing when the
# registry is not there -- a workspace without one has no such files.
harness_files() {
	[ -r "$WS/tools/resources.tsv" ] || return 0
	awk -F'\t' -v m="$1" '!/^#/ && NF >= 4 && $1 == m && $4 == "harness" { print $2 "\t" $3 }' \
		"$WS/tools/resources.tsv"
}

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

# What was not generated, one "MODULE exNN (why)" line each, for the summary,
# and the exit status the worst of them earns.
NOT_DONE=""
WORST=0
not_done() { # not_done <why> <exit status>
	# conventions: not-a-list -- lines of the summary, printed whole and never split
	NOT_DONE="$NOT_DONE  $MOD${ex:+ $ex} ($1)
"
	[ "$2" -gt "$WORST" ] && WORST=$2
}
refused() { not_done "refused, see above" 2; }

# Delete $1 and say whether it is gone. Write permission first: a generator can
# leave a directory its owner cannot write into (the permission exercises make
# exactly that), and rm -rf cannot empty one. It then fails half-way and leaves
# the folder there -- and mv, handed an existing directory, moves the new output
# INTO it instead of in its place. Never through a symbolic link.
wipe() {
	[ -n "$1" ] || return 0
	[ -d "$1" ] && [ ! -L "$1" ] && chmod -R u+w "$1" 2> /dev/null
	rm -rf "$1"
	[ ! -e "$1" ] && [ ! -L "$1" ]
}

# Copy each registered file this module's generators may read into the scratch
# dir, by its own name; and take them out again before the output is judged, so
# they are never mistaken for, or installed as, the generator's output.
stage_harness_files() {
	_ifs=$IFS
	IFS='
'
	for _r in $res; do
		[ -e "$WS/${_r#*	}" ] || continue
		cp "$WS/${_r#*	}" "$SCRATCH/${_r%%	*}" || { IFS=$_ifs; return 1; }
	done
	IFS=$_ifs
}
unstage_harness_files() {
	_ifs=$IFS
	IFS='
'
	for _r in $res; do
		rm -f "$SCRATCH/${_r%%	*}"
	done
	IFS=$_ifs
}

# The scratch dir sits in the module folder rather than in $TMPDIR so that the
# final move is a rename on one filesystem: a copy across filesystems can turn
# the hard links and symbolic links a generator made into plain files. Never
# inside deliverable/: //tools:submit pushes that folder as it is on disk, so a
# scratch dir left there by a killed run would be pushed to 42.
#
# An interrupt ends the run rather than moving on to the next exercise, and the
# EXIT trap then removes the scratch dir of the one it stopped.
SCRATCH=""
trap 'wipe "$SCRATCH"' EXIT
trap 'exit 2' INT TERM

for MOD in "$@"; do
	# As the registry spells a project: no leading ./ and no trailing /, which
	# tab completion adds. The lookup below compares the name literally, so
	# `c-piscine/c-piscine-shell-00/` staged no tarball, silently, while every
	# other step here worked.
	while :; do
		case "$MOD" in
			./*) MOD=${MOD#./} ;;
			*/) MOD=${MOD%/} ;;
			*) break ;;
		esac
	done
	dir="$WS/$MOD"
	ex=""
	# A project that is not there is a name typed wrong, not one with nothing
	# to generate: it used to be "skipped" too, and the run exited 0.
	if [ ! -d "$dir" ]; then
		echo "generate.sh: there is no project $MOD in $WS" >&2
		not_done "no such project" 2; continue
	fi
	if [ ! -d "$dir/generators" ]; then
		echo "generate.sh: no generators/ in $MOD — skipped" >&2
		continue
	fi
	res=$(harness_files "$MOD")
	for g in "$dir"/generators/ex*.sh; do
		[ -f "$g" ] || continue
		ex=$(basename "$g" .sh)
		out="$dir/deliverable/$ex"
		# First: every check below looks INSIDE a folder, so a file here passes
		# them all, and replacing it with the generator's folder deletes it. It
		# is a turn-in written to deliverable/exNN rather than into it.
		if { [ -e "$out" ] || [ -L "$out" ]; } && [ ! -d "$out" ]; then
			echo "generate.sh: $MOD/deliverable/$ex is a file, not a folder, and generating" >&2
			echo "  $ex would replace it with the folder generators/$ex.sh builds. Move it" >&2
			echo "  out of the way: deliverable/$ex is rebuilt from the generator on every" >&2
			echo "  run, and your turn-in files are what the generator makes inside it." >&2
			echo "  Nothing was generated for $ex." >&2
			refused; continue
		fi
		hand=""
		for _f in "$out"/*.c "$out"/*.h "$out"/Makefile; do
			[ -e "$_f" ] && { hand=$(basename "$_f"); break; }
		done
		if [ -n "$hand" ]; then
			echo "generate.sh: $MOD/deliverable/$ex holds hand-written work ($hand)," >&2
			echo "  and generators/$ex.sh would wipe it. Is the generator numbered for the" >&2
			echo "  wrong exercise? Nothing was generated for $ex." >&2
			refused; continue
		fi
		# Before the skeleton check, whose advice ("write the commands") would
		# be true and beside the point: the file is in the wrong folder.
		_misplaced=""
		_ifs=$IFS
		IFS='
'
		for _r in $res; do
			[ -e "$out/${_r%%	*}" ] && { _misplaced=$_r; break; }
		done
		IFS=$_ifs
		if [ -n "$_misplaced" ]; then
			_rn=${_misplaced%%	*}
			_rp=${_misplaced#*	}
			echo "generate.sh: $MOD/deliverable/$ex holds $_rn, and generating" >&2
			echo "  $ex would wipe it: deliverable/$ex is rebuilt from the generator every" >&2
			echo "  time. The harness reads this file of 42's from ONE place:" >&2
			echo "      $_rp" >&2
			if [ -e "$WS/$_rp" ]; then
				echo "  A copy is already there, so delete the one in deliverable/$ex." >&2
				echo "  Nothing was generated for $ex." >&2
			else
				echo "  Move it there. Nothing was generated for $ex." >&2
			fi
			refused; continue
		fi
		if skeleton "$g"; then
			_left=""
			for _f in "$out"/* "$out"/.[!.]* "$out"/..?*; do
				[ -e "$_f" ] || [ -L "$_f" ] || continue
				_left=$(basename "$_f"); break
			done
			if [ -n "$_left" ]; then
				echo "generate.sh: $MOD/deliverable/$ex holds $_left, but" >&2
				echo "  generators/$ex.sh has no commands yet, so generating would wipe it" >&2
				echo "  and put nothing back. In this project deliverable/$ex is rebuilt" >&2
				echo "  from the generator and never committed: write the commands that" >&2
				echo "  create your turn-in in generators/$ex.sh. Nothing was generated for $ex." >&2
				refused; continue
			fi
		fi

		# Checked: a scratch dir that is not fresh and empty would hand this
		# run's check below files the generator did not make.
		SCRATCH="$dir/.generating-$ex"
		if ! wipe "$SCRATCH" || ! mkdir "$SCRATCH" || ! stage_harness_files; then
			echo "generate.sh: could not set up an empty $MOD/.generating-$ex to run" >&2
			echo "  generators/$ex.sh in (see the error above). Nothing was generated for $ex." >&2
			wipe "$SCRATCH"; SCRATCH=""
			not_done "could not set up its scratch dir" 2; continue
		fi
		( cd "$SCRATCH" && sh "$g" )
		grc=$?
		unstage_harness_files
		if [ "$grc" -ne 0 ]; then
			echo "generate.sh: generator failed: $MOD/generators/$ex.sh exited $grc" >&2
			echo "  (whatever it printed is above). deliverable/$ex was left as it was." >&2
			wipe "$SCRATCH"; SCRATCH=""
			not_done "generator failed, exit $grc" 1; continue
		fi

		# Everything already in deliverable/exNN must be something this run
		# produced too. By path, recursively; a name the generator writes again
		# is its own output from an earlier run, and replacing it is the point.
		lost=""
		if [ -d "$out" ]; then
			lost=$(cd "$out" && find . ! -path . -print | sed 's|^\./||' |
				while IFS= read -r _p; do
					[ -e "$SCRATCH/$_p" ] || [ -L "$SCRATCH/$_p" ] || printf '%s\n' "$_p"
				done)
		fi
		if [ -n "$lost" ]; then
			echo "generate.sh: $MOD/deliverable/$ex holds what generators/$ex.sh did not" >&2
			echo "  produce on this run, so replacing the folder would delete it:" >&2
			printf '%s\n' "$lost" | sed -n '1,10s/^/      /p' >&2
			_n=$(printf '%s\n' "$lost" | sed -n '$=')
			[ "$_n" -gt 10 ] && echo "      ... and $((_n - 10)) more" >&2
			# Three causes, and the first is the one a leftover-shaped list
			# hides: the generator exited 0 but made nothing this time (shell-00
			# ex07 does, when 42's tarball is missing).
			echo "  Did generators/$ex.sh fail to make it this time? It exited 0, but" >&2
			echo "  read what it printed above. Left over from an earlier version of" >&2
			echo "  your generator? Delete it. Put there by hand? Move it out:" >&2
			echo "  deliverable/$ex is rebuilt from the generator and never committed." >&2
			_ifs=$IFS
			IFS='
'
			for _r in $res; do
				[ -e "$WS/${_r#*	}" ] && continue
				echo "  This module has no ${_r%%	*}, so a generator that reads it had" >&2
				echo "  nothing to read. 42 issues it; save it as" >&2
				echo "      ${_r#*	}" >&2
			done
			IFS=$_ifs
			echo "  Nothing was generated for $ex." >&2
			wipe "$SCRATCH"; SCRATCH=""
			refused; continue
		fi

		# Both steps checked. An old folder that is still there after the
		# delete (a file in it open elsewhere, or not the student's to delete)
		# would take the scratch dir INSIDE it on the mv -- and submit pushes
		# deliverable/ as it is on disk.
		if ! wipe "$out"; then
			echo "generate.sh: could not delete the old $MOD/deliverable/$ex to replace it" >&2
			echo "  (is a file in it open in another program, or owned by another user?)." >&2
			echo "  What is left of it is incomplete: run generate again once it can be" >&2
			echo "  deleted. Nothing was generated for $ex." >&2
			wipe "$SCRATCH"; SCRATCH=""
			refused; continue
		fi
		if ! mkdir -p "$dir/deliverable" || ! mv "$SCRATCH" "$out"; then
			echo "generate.sh: could not move the output of generators/$ex.sh into" >&2
			echo "  $MOD/deliverable/$ex (see the error above). Nothing was generated for $ex." >&2
			wipe "$SCRATCH"; SCRATCH=""
			not_done "could not be put in place" 2; continue
		fi
		SCRATCH=""
		echo "generated $MOD/deliverable/$ex"
	done
done

if [ -n "$NOT_DONE" ]; then
	echo "" >&2
	echo "generate.sh: not generated:" >&2
	printf '%s' "$NOT_DONE" >&2
fi
exit "$WORST"
