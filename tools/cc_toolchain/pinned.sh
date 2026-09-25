# shellcheck shell=sh
# (sourced library, never executed, so it has no shebang -- this directive
#  tells shellcheck the dialect without implying the file is a program.)
#
# pinned.sh -- find a FETCHED repository from inside a C++ toolchain action.
#
# Sourced by clang.sh and binutils.sh, which Bazel runs as the pinned C++
# toolchain's compiler, archiver and linkers. They exist because a fetched tool
# that cannot find its own libraries does not fail: the loader answers from the
# box's /lib and the "pinned" tool runs the machine's code under a pinned name.
# Bazel gives compile actions no way to set LD_LIBRARY_PATH (measured -- see
# TODO.md §21), so the tool itself has to.
#
# pinned_repo NAME prints the repository's directory relative to the working
# directory, in the two layouts these scripts are ever run from:
#
#   external/<canonical name>   a build action; the cwd is the exec root
#   ../<canonical name>         a test; the cwd is <target>.runfiles/_main
#
# The canonical name is matched by glob (*deb_archive*NAME) rather than spelled,
# because Bazel's scheme for it has changed once already -- `~` became `+` --
# and a spelled name would break on the next change with a "not found" that
# reads like a broken fetch. Exactly one match is required. Zero or two is a
# refusal, never a fallback: the fallback is the machine's own tool, which is
# the thing this whole package exists to stop.
#
# RELATIVE on purpose. clang runs with -no-canonical-prefixes, so the path it is
# exec'd by becomes the path it reports its own headers under, and Bazel accepts
# a header only at the exec-root-relative path it staged it at.
pinned_repo() {
	_pr_found=""
	for _pr_d in external/*deb_archive*"$1" ../*deb_archive*"$1"; do
		[ -d "$_pr_d" ] || continue
		if [ -n "$_pr_found" ]; then
			echo "pinned toolchain: two staged copies of $1 ($_pr_found and $_pr_d)." >&2
			echo "  Refusing to guess which one this build is pinned to." >&2
			return 1
		fi
		_pr_found=$_pr_d
	done
	if [ -z "$_pr_found" ]; then
		echo "pinned toolchain: cannot find the fetched $1 from $PWD" >&2
		echo "  (looked for external/*$1 and ../*$1). Its files are not among this" >&2
		echo "  action's inputs, which is a wiring error in tools/cc_toolchain." >&2
		echo "  Refusing rather than falling back to this machine's own tool." >&2
		return 1
	fi
	printf '%s' "$_pr_found"
}
