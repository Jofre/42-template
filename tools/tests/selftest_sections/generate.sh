# ------------------------------------------------------------------ generate
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A mixed project (Piscine Reloaded) writes some exercises by hand in
# deliverable/ and generates the others into it, and generate.sh must never wipe
# hand-written work. Here: ANY file while the generator is still a skeleton --
# the student who wrote their shell turn-in straight into the gitignored
# deliverable/exNN would lose it for good. Made-up module, made-up generator.
mkdir -p "$WORK/gen/mod/generators" "$WORK/gen/mod/deliverable/ex03"
printf '#!/bin/sh\n# ex03 — made-up\n# TODO: write the commands that create this deliverable in the current dir.\n:\n' \
	> "$WORK/gen/mod/generators/ex03.sh"
printf 'written by hand\n' > "$WORK/gen/mod/deliverable/ex03/by_hand.txt"
want_broken "generate: a skeleton generator never wipes a hand-made file" \
	'has no commands yet' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" mod
want_green "generate: ...which is still there" -- \
	test -f "$WORK/gen/mod/deliverable/ex03/by_hand.txt"
printf '#!/bin/sh\nprintf selftest > selftest-output\n' > "$WORK/gen/mod/generators/ex03.sh"
# A generator WITH commands does not make the hand-made file its own: it did
# not produce by_hand.txt, so replacing the folder would delete it. This was a
# silent wipe while any written generator was allowed to rebuild the folder.
want_broken "generate: a file the generator did not make survives" \
	'did not' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" mod
want_green "generate: ...which is still there" -- \
	test -f "$WORK/gen/mod/deliverable/ex03/by_hand.txt"
rm -f "$WORK/gen/mod/deliverable/ex03/by_hand.txt"
want_green "generate: a generator with commands rebuilds the directory" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" mod
want_green "generate: ...leaving only what it made" -- \
	sh -c '[ -f "$1/selftest-output" ] && [ ! -e "$1/by_hand.txt" ]' _ \
		"$WORK/gen/mod/deliverable/ex03"
# Its OWN earlier output is not a stranger: the next run replaces it.
printf '#!/bin/sh\nprintf again > selftest-output\n' > "$WORK/gen/mod/generators/ex03.sh"
want_green "generate: its own earlier output is replaced" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" mod
want_green "generate: ...by this run's" -- \
	grep -qx again "$WORK/gen/mod/deliverable/ex03/selftest-output"
want_green "generate: ...and no scratch dir is left behind" -- \
	test ! -e "$WORK/gen/mod/.generating-ex03"

# 42's tarball saved in the exercise's folder, the place every message used to
# point at: the harness reads it only from the one path tools/resources.tsv
# names, and the next generate deleted it. Refused, with that path. The
# fixture's registry lists the made-up modules' files the way the real one
# lists shell-00's tarball: which file, and its one path.
mkdir -p "$WORK/gen/tools"
{
	printf 'tgz\tresources.tar.gz\ttgz/resources.tar.gz\tharness\t*resources.tar.gz\t-\t-\tfixture\n'
	printf 'notgz\tresources.tar.gz\tnotgz/resources.tar.gz\tharness\t*resources.tar.gz\t-\t-\tfixture\n'
	printf 'reg\tin.bin\treg/data/in.bin\tharness\t*in.bin\t-\t-\tfixture\n'
} > "$WORK/gen/tools/resources.tsv"
mkdir -p "$WORK/gen/tgz/generators" "$WORK/gen/tgz/deliverable/ex07"
printf '#!/bin/sh\nprintf b > b\n' > "$WORK/gen/tgz/generators/ex07.sh"
printf 'not a real tarball\n' > "$WORK/gen/tgz/deliverable/ex07/resources.tar.gz"
want_broken "generate: resources.tar.gz in deliverable/exNN is refused" \
	'      tgz/resources.tar.gz' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" tgz
want_green "generate: ...and survives" -- \
	test -f "$WORK/gen/tgz/deliverable/ex07/resources.tar.gz"
printf 'not a real tarball\n' > "$WORK/gen/tgz/resources.tar.gz"
want_broken "generate: ...and with one at the root too, says so" \
	'A copy is already there' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" tgz
rm -f "$WORK/gen/tgz/resources.tar.gz"

# The registry decides what is staged for a generator and from where: a file
# registered at reg/data/in.bin reaches the generator as ./in.bin, and is gone
# from the output it leaves. Before the registry the one staged file was
# hard-coded, resources.tar.gz from the module root, so a new project's file
# needed a new branch in this script.
mkdir -p "$WORK/gen/reg/generators" "$WORK/gen/reg/data"
printf 'registered bytes\n' > "$WORK/gen/reg/data/in.bin"
printf '#!/bin/sh\ncp in.bin out\n' > "$WORK/gen/reg/generators/ex01.sh"
want_green "generate: a registered file reaches the generator" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" reg
want_green "generate: ...from the path the registry names" -- \
	grep -qx 'registered bytes' "$WORK/gen/reg/deliverable/ex01/out"
want_green "generate: ...and is not left in the output" -- \
	test ! -e "$WORK/gen/reg/deliverable/ex01/in.bin"
# ...however the project is spelled: tab completion adds a trailing /, and the
# registry lookup compared the name literally, so it staged nothing, silently.
rm -rf "$WORK/gen/reg/deliverable"
want_green "generate: ./reg/ is the registry's reg" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" ./reg/
want_green "generate: ...and its file reaches the generator" -- \
	grep -qx 'registered bytes' "$WORK/gen/reg/deliverable/ex01/out"
# A project that is not there is not "skipped": a mistyped name exited 0, as
# if it had been generated, saying so only on a stderr line. One that is there
# and has no generators/ (a C project) still is.
want_broken "generate: a project that is not there fails the run" \
	'nosuch (no such project)' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" nosuch
mkdir -p "$WORK/gen/cmod/deliverable/ex00"
want_green "generate: ...one with no generators/ is skipped" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" cmod

# A generator that fails is not "generated". Its partial output never
# replaces the deliverable, and the run says which one failed.
mkdir -p "$WORK/gen/bad/generators"
printf '#!/bin/sh\nprintf half > half\nexit 3\n' > "$WORK/gen/bad/generators/ex01.sh"
want_red   "generate: a failing generator fails the run" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" bad
want_out   "generate: ...and says so" 'generator failed' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" bad
want_broken_none "generate: ...never that it generated it" \
	'generated bad/deliverable/ex01' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" bad
want_green "generate: ...and its partial output is not installed" -- \
	test ! -e "$WORK/gen/bad/deliverable/ex01/half"

# One refusal used to `exit 2` on the spot, silently skipping every later
# exercise and, under //tools:generate, every later module. Now the run goes
# on, and the end names what was not generated.
mkdir -p "$WORK/gen/m1/generators" "$WORK/gen/m1/deliverable/ex01" \
	"$WORK/gen/m2/generators"
printf '#!/bin/sh\nprintf x > out\n' > "$WORK/gen/m1/generators/ex01.sh"
printf '#!/bin/sh\nprintf x > out\n' > "$WORK/gen/m1/generators/ex02.sh"
printf '#!/bin/sh\nprintf x > out\n' > "$WORK/gen/m2/generators/ex01.sh"
printf 'int\tx;\n' > "$WORK/gen/m1/deliverable/ex01/by_hand.c"
want_broken "generate: a refusal is listed at the end" \
	'm1 ex01 (refused, see above)' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" m1 m2
want_green "generate: ...later exercises are still generated" -- \
	test -f "$WORK/gen/m1/deliverable/ex02/out"
want_green "generate: ...and later modules too" -- \
	test -f "$WORK/gen/m2/deliverable/ex01/out"
# ...and the worst of them sets the exit status: a failure followed by a
# refusal is still 2, never the 1 the failure alone would earn.
mkdir -p "$WORK/gen/mix/generators" "$WORK/gen/mix/deliverable/ex02"
printf '#!/bin/sh\nexit 3\n' > "$WORK/gen/mix/generators/ex01.sh"
printf '#!/bin/sh\nprintf x > out\n' > "$WORK/gen/mix/generators/ex02.sh"
printf 'int\tx;\n' > "$WORK/gen/mix/deliverable/ex02/by_hand.c"
want_broken "generate: a failure and a refusal together exit 2" \
	'mix ex01 (generator failed, exit 3)' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" mix

# deliverable/exNN as a FILE: the turn-in saved AS deliverable/ex03 rather than
# inside it. Every check above looks inside a folder, so it passed them all and
# was deleted without a word.
mkdir -p "$WORK/gen/asfile/generators" "$WORK/gen/asfile/deliverable"
printf '#!/bin/sh\n# ex03 — made-up\n:\n' > "$WORK/gen/asfile/generators/ex03.sh"
printf 'my turn-in\n' > "$WORK/gen/asfile/deliverable/ex03"
want_broken "generate: a FILE named deliverable/exNN is refused" \
	'is a file, not a folder' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" asfile
want_green "generate: ...and survives" -- \
	grep -qx 'my turn-in' "$WORK/gen/asfile/deliverable/ex03"

# The third reason a file can be "not produced on this run": the generator
# exited 0 and made nothing this time -- shell-00 ex07's, when 42's tarball is
# missing. The refusal called the student's own output a leftover to delete.
# The registry lists the tarball for the module, and it has none.
mkdir -p "$WORK/gen/notgz/generators" "$WORK/gen/notgz/deliverable/ex01"
printf 'fixtures = glob(["resources.tar.gz"], allow_empty = True)\n' \
	> "$WORK/gen/notgz/BUILD.bazel"
printf '#!/bin/sh\n[ -f resources.tar.gz ] && printf x > out\nexit 0\n' \
	> "$WORK/gen/notgz/generators/ex01.sh"
printf 'x' > "$WORK/gen/notgz/deliverable/ex01/out"
want_broken "generate: output it did not make this time: says it may be that" \
	'fail to make it this time' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" notgz
want_broken "generate: ...and names the missing tarball's place" \
	'notgz/resources.tar.gz' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" notgz

# Output holding a directory its owner cannot write into, which the permission
# exercises make. rm -rf could not empty the old one, so it survived the
# delete, the mv put the new output INSIDE it as deliverable/ex01/.generating-
# ex01, and the run said "generated" and exited 0 -- a scratch dir submit would
# have pushed. Made-up generator: a folder, a file in it, the folder read-only.
mkdir -p "$WORK/gen/ro/generators"
printf '#!/bin/sh\nmkdir d && printf x > d/f && chmod 555 d\n' > "$WORK/gen/ro/generators/ex01.sh"
! st_mine || env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" ro > /dev/null 2>&1
want_green "generate: output with a read-only folder is regenerated" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" ro
want_green "generate: ...in place, never inside the old output" -- \
	sh -c '[ -f "$1/d/f" ] && [ ! -e "$1/.generating-ex01" ]' _ "$WORK/gen/ro/deliverable/ex01"
# And when the delete fails anyway -- a file open in another program, or not
# the student's to delete; here an rm that refuses that one folder -- the
# exercise is refused and named, never "generated".
mkdir -p "$WORK/gen-rm"
printf '#!/bin/sh\nfor a; do case "$a" in */deliverable/ex01) exit 1 ;; esac; done\nexec %s "$@"\n' \
	"$(command -v rm)" > "$WORK/gen-rm/rm"
chmod +x "$WORK/gen-rm/rm"
want_broken "generate: an old output it cannot delete is refused" \
	'could not delete the old ro/deliverable/ex01' -- \
	once env PATH="$WORK/gen-rm:$PATH" BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" ro
want_broken_without "generate: ...never that it generated it" \
	'generated ro/deliverable/ex01' -- \
	once env PATH="$WORK/gen-rm:$PATH" BUILD_WORKSPACE_DIRECTORY="$WORK/gen" "$SH" "$TOOLS/generate.sh" ro
want_green "generate: ...and leaves no scratch dir, inside it or beside it" -- \
	sh -c '[ ! -e "$1/deliverable/ex01/.generating-ex01" ] && [ ! -e "$1/.generating-ex01" ]' _ \
		"$WORK/gen/ro"
chmod -R u+w "$WORK/gen/ro"

# Whether a generator is still its skeleton is stub_check.sh's verdict, the
# one the template build asks of the same file: generate read it with a
# copy of its own, which nothing held to stub_check's. One shape a run,
# each with a hand-made file in its folder, so a skeleton is refused ("has
# no commands yet") and a written generator is not; stub_check --file
# judges the same file. An empty generator is a skeleton to generate, as it
# always was, while stub_check refuses it as no stub either.
gs_verdicts() {  # gs_verdicts CONTENT -- generate's verdict, then stub_check's
	rm -rf "$WORK/genshape" &&
		mkdir -p "$WORK/genshape/mod/generators" "$WORK/genshape/mod/deliverable/ex00" || return 2
	printf '%b' "$1" > "$WORK/genshape/mod/generators/ex00.sh"
	printf 'by hand\n' > "$WORK/genshape/mod/deliverable/ex00/hand.txt"
	_gs_g=$(env BUILD_WORKSPACE_DIRECTORY="$WORK/genshape" "$SH" "$TOOLS/generate.sh" mod 2>&1)
	case "$_gs_g" in *'has no commands yet'*) _gs_gv=skeleton ;; *) _gs_gv=written ;; esac
	"$SH" "$TOOLS/stub_check.sh" --file "$WORK/genshape/mod/generators/ex00.sh" > /dev/null 2>&1
	case $? in 0) _gs_sv=skeleton ;; 1) _gs_sv=written ;; *) _gs_sv=refused ;; esac
	echo "$_gs_gv $_gs_sv"
}
gs_agree() {  # gs_agree CONTENT WANT -- generate says WANT, as stub_check does
	_gs_v=$(gs_verdicts "$1")
	[ "$_gs_v" = "$2 $2" ] && return 0
	echo "generate, stub_check: $_gs_v (want $2 from both)"
	return 1
}
want_green "generate: a ':' generator is a skeleton, as stub_check says" -- gs_agree ':\n' skeleton
want_green "generate: ...and a 'true' one" -- gs_agree 'true\n' skeleton
want_green "generate: ...and an indented ':'" -- gs_agree '  :  \n' skeleton
want_green "generate: ...and one of comments and blank lines" -- gs_agree '# a note\n\n' skeleton
want_green "generate: ...and the shipped shape, #! line, description and ':'" -- \
	gs_agree '#!/bin/sh\n# ex00: made-up\n# TODO: write the commands.\n:\n' skeleton
want_green "generate: one with a command is written, as stub_check says" -- \
	gs_agree 'printf selftest > out\n' written
gs_empty() {
	_gs_v=$(gs_verdicts '')
	[ "$_gs_v" = "skeleton refused" ] && return 0
	echo "generate, stub_check: $_gs_v (want skeleton refused)"
	return 1
}
want_green "generate: an empty one is a skeleton, which stub_check refuses" -- gs_empty
