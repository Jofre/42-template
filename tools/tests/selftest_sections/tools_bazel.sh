# ------------------------------------------------------------- tools/bazel
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The wrapper bazelisk runs instead of Bazel. .bazelrc used to send every
# checkout without a .bazelrc.local to /tmp/bazelcache -- one path for every
# user of a machine, so on a campus box the second student's build waited on the
# first one's lock or could not write the directory at all (finding 001). An rc
# file cannot say "per user"; a wrapper can. So these pin what it adds and, as
# much, what it must NOT touch: a root you named on the command line or in an rc
# file, and every argument as you typed it.
#
# Driven the way bazelisk drives it: from a checkout's tools/, with BAZEL_REAL
# naming the Bazel to run -- here a fake that prints what it was handed, one
# argument a line. The knobs stand in for /goinfre and for campus, and name a
# legacy root that does not exist unless an arm makes it.
mkdir -p "$WORK/bw/ws/tools" "$WORK/bw/home" "$WORK/bw/goinfre"
cp "$TOOLS/bazel" "$WORK/bw/ws/tools/bazel"
cp "$TOOLS/drives.sh" "$WORK/bw/ws/tools/drives.sh"
printf 'build --keep_going\n' > "$WORK/bw/ws/.bazelrc"
printf '#!/bin/sh\nfor a in "$@"; do printf "ARG:%%s\\n" "$a"; done\n' > "$WORK/bw/real"
chmod +x "$WORK/bw/real"
# A campus box has a /goinfre and nothing else does, so the stand-in exists
# only for the campus runs.
# Outside a container, whatever runs this, unless BW_REMOTE (REMOTE_CONTAINERS)
# or BW_DOCKERENV (the file Docker writes) says otherwise.
bw_run() {  # bw_run CAMPUS ARGS... -- the wrapper, from the fixture checkout
	_bwc=$1
	shift
	_bwg="$WORK/bw/no-goinfre"
	[ "$_bwc" = 1 ] && _bwg="$WORK/bw/goinfre"
	env BAZEL_REAL="$WORK/bw/real" HOME="$WORK/bw/home" USER=probe \
		XDG_CACHE_HOME="$WORK/bw/home/.cache" C_PISCINE_CAMPUS="$_bwc" \
		C_PISCINE_GOINFRE="$_bwg" C_PISCINE_LEGACY_ROOT="$WORK/bw/legacy" \
		REMOTE_CONTAINERS="${BW_REMOTE:-}" \
		C_PISCINE_DOCKERENV="${BW_DOCKERENV:-$WORK/bw/no-dockerenv}" \
		"$SH" "$WORK/bw/ws/tools/bazel" "$@"
}
want_out "bazel wrapper: off campus, a root in the cache dir" \
	"ARG:--output_user_root=$WORK/bw/home/.cache/42-piscine/bazel" -- bw_run 0 info
want_out "bazel wrapper: on campus, a root in /goinfre/\$USER" \
	"ARG:--output_user_root=$WORK/bw/goinfre/probe/bazel" -- bw_run 1 info
# Arguments pass through whole, in order, after the one it adds.
bw_args() { bw_run 0 test "//a b:c" --test_arg="x y" | tr '\n' '|'; }
want_out "bazel wrapper: your arguments reach Bazel untouched" \
	"ARG:test|ARG://a b:c|ARG:--test_arg=x y|" -- bw_args
# A root you chose wins, and no second one is added.
want_broken_none "bazel wrapper: a command-line root is left alone" \
	"ARG:--output_user_root=$WORK/bw" -- bw_run 0 --output_user_root=/elsewhere info
printf 'startup --output_user_root=%s/mine\n' "$WORK/bw" > "$WORK/bw/ws/.bazelrc.local"
want_broken_none "bazel wrapper: ...and so is one .bazelrc.local sets" \
	"ARG:--output_user_root" -- bw_run 0 info
# ...unless Bazel will not read that file for this command.
want_out "bazel wrapper: ...but not under --noworkspace_rc" \
	"ARG:--output_user_root=$WORK/bw/home/.cache" -- bw_run 0 --noworkspace_rc info
# That root is one this machine can create, so nothing is said about it.
bw_err() { { bw_run 0 info > /dev/null; } 2>&1; }
bw_quiet() { _bwq=$(bw_err) && [ -z "$_bwq" ]; }
want_green "bazel wrapper: ...and says nothing of a root it can create" -- bw_quiet
# A root it can NOT create (V239): a .bazelrc.local the host's setup.sh wrote
# names a folder under a home this dev container may not write, and Bazel
# then stops with a bare mkdir FATAL. The wrapper still passes the root
# through and runs Bazel unchanged, but first says which file set it and,
# in a container, the step that fixes it without editing the file the host
# shares. Below a folder of mode 555, as the container's /home is to its
# user.
mkdir -p "$WORK/bw/ro" && chmod 555 "$WORK/bw/ro"
printf 'startup --output_user_root=%s/ro/x/bazel\n' "$WORK/bw" > "$WORK/bw/ws/.bazelrc.local"
bw_in() { ( BW_REMOTE=true && bw_err ); }
want_out "bazel wrapper: a root it cannot create names the rc file" \
	"$WORK/bw/ws/.bazelrc.local" -- bw_in
want_out "bazel wrapper: ...and the step, which edits no shared file" \
	"sh .devcontainer/postcreate.sh" -- bw_in
: > "$WORK/bw/dockerenv"
bw_marker() { ( BW_DOCKERENV="$WORK/bw/dockerenv" && bw_err ); }
want_out "bazel wrapper: ...Docker's file says container as well" \
	"sh .devcontainer/postcreate.sh" -- bw_marker
bw_plain() { [ "$(BW_REMOTE=true && bw_run 0 info 2> /dev/null)" = "ARG:info" ]; }
want_green "bazel wrapper: ...and runs Bazel with the arguments unchanged" -- bw_plain
# On a host, postcreate.sh's ~/.bazelrc root would outrank every checkout's
# recorded one there: the file is named, and no container step.
want_out "bazel wrapper: ...outside a container, the file alone" \
	"$WORK/bw/ws/.bazelrc.local sets the output root" -- bw_err
want_broken_none "bazel wrapper: ...and no container step" \
	"postcreate" -- bw_err
# Set by an rc file of the command line's, the file is named, and the step
# that answers a host's .bazelrc.local is not offered, container or not.
printf 'startup --output_user_root=%s/ro/y/bazel\n' "$WORK/bw" > "$WORK/bw/extra.rc"
rm -f "$WORK/bw/ws/.bazelrc.local"
bw_extra() { ( BW_REMOTE=true && bw_run 0 --bazelrc="$WORK/bw/extra.rc" info > /dev/null ) 2>&1; }
want_out "bazel wrapper: a --bazelrc root it cannot create names that file" \
	"$WORK/bw/extra.rc sets the output root $WORK/bw/ro/y/bazel" -- bw_extra
want_broken_none "bazel wrapper: ...and no container step for it either" "postcreate" -- bw_extra
chmod 755 "$WORK/bw/ro"
rm -f "$WORK/bw/ws/.bazelrc.local"
# The one exception, so that the change relocated nobody: off campus, a legacy
# root that is already yours, and already holds this checkout's output base, is
# kept. On campus it never is -- that is where it was shared. An output base is
# the folder Bazel writes DO_NOT_BUILD_HERE in, naming its workspace.
bw_base() {  # bw_base ROOT -- plant the fixture checkout's output base there
	mkdir -p "$1/base"
	printf '%s' "$WORK/bw/ws" > "$1/base/DO_NOT_BUILD_HERE"
}
bw_base "$WORK/bw/legacy"
want_out "bazel wrapper: off campus, your old shared-path root is kept" \
	"ARG:--output_user_root=$WORK/bw/legacy" -- bw_run 0 info
want_out "bazel wrapper: ...and on campus it is not" \
	"ARG:--output_user_root=$WORK/bw/goinfre/probe/bazel" -- bw_run 1 info
rm -rf "$WORK/bw/legacy"
# ...but only a root that holds THIS checkout's state, which is what keeping it
# is for. Any old copy run once on the machine (an old clone, an old template
# checked out to compare) creates the old root, and every current checkout
# without a .bazelrc.local then moved there: a second server on a cold output
# base, the warm one in the per-user root left running, orphaned.
bw_root() {  # what drives_bazel_root answers for the fixture checkout, off campus
	env HOME="$WORK/bw/home" USER=probe XDG_CACHE_HOME="$WORK/bw/home/.cache" \
		C_PISCINE_CAMPUS=0 C_PISCINE_GOINFRE="$WORK/bw/no-goinfre" \
		C_PISCINE_LEGACY_ROOT="$WORK/bw/legacy" \
		"$SH" -c '. "$1/tools/drives.sh" && drives_bazel_root "$1"' _ "$WORK/bw/ws"
}
mkdir -p "$WORK/bw/legacy/other"
printf '%s' "$WORK/bw/elsewhere" > "$WORK/bw/legacy/other/DO_NOT_BUILD_HERE"
want_out "bazel wrapper: an old root holding none of this checkout is not kept" \
	"ARG:--output_user_root=$WORK/bw/home/.cache/42-piscine/bazel" -- bw_run 0 info
bw_base "$WORK/bw/home/.cache/42-piscine/bazel"
bw_base "$WORK/bw/legacy"
want_out "drives: a per-user root holding this checkout wins over the old one" \
	"$WORK/bw/home/.cache/42-piscine/bazel" -- bw_root
want_broken_none "drives: ...and the old root is not named" "$WORK/bw/legacy" -- bw_root
rm -rf "$WORK/bw/legacy" "$WORK/bw/home/.cache/42-piscine/bazel"
# A base names its workspace by the path Bazel saw, which may be the physical
# one: a checkout reached through a symbolic link is still found in it.
mkdir -p "$WORK/bw/legacy/base"
( cd "$WORK/bw/ws" && pwd -P | tr -d '\n' ) > "$WORK/bw/legacy/base/DO_NOT_BUILD_HERE"
ln -s "$WORK/bw/ws" "$WORK/bw/ws-link"
bw_link() {
	env HOME="$WORK/bw/home" USER=probe XDG_CACHE_HOME="$WORK/bw/home/.cache" \
		C_PISCINE_CAMPUS=0 C_PISCINE_GOINFRE="$WORK/bw/no-goinfre" \
		C_PISCINE_LEGACY_ROOT="$WORK/bw/legacy" \
		"$SH" -c '. "$1/tools/drives.sh" && drives_bazel_root "$1"' _ "$WORK/bw/ws-link"
}
want_out "drives: ...and is found through a symbolic link" "$WORK/bw/legacy" -- bw_link
rm -rf "$WORK/bw/legacy" "$WORK/bw/ws-link"
# The system rc, which Bazel reads first. C_PISCINE_SYSTEM_BAZELRC stands in
# for /etc/bazel.bazelrc, and this file points it at one that does not exist
# (at the top); here, at a toy one that names a root. The root is read, the
# wrapper adds none of its own over it, and a checkout's .bazelrc.local still
# wins; the campus warning never names the system rc as one read after that
# file, which it is not.
printf 'startup --output_user_root=%s/sysrc/root\n' "$WORK/bw" > "$WORK/bw/system.bazelrc"
bw_sys() { ( C_PISCINE_SYSTEM_BAZELRC="$WORK/bw/system.bazelrc" && export C_PISCINE_SYSTEM_BAZELRC && "$@" ); }
bw_rcroot() { "$SH" -c '. "$1/tools/drives.sh" && printf "[%s]\n" "$(drives_rc_root "$1")"' _ "$WORK/bw/ws"; }
want_out "drives: the system rc the knob names is read" \
	"[$WORK/bw/sysrc/root]" -- bw_sys bw_rcroot
want_broken_none "bazel wrapper: ...and a root it sets is left alone" \
	"ARG:--output_user_root" -- bw_sys bw_run 0 info
printf 'startup --output_user_root=%s/mine\n' "$WORK/bw" > "$WORK/bw/ws/.bazelrc.local"
want_out "drives: ...before .bazelrc.local, whose root wins" \
	"[$WORK/bw/mine]" -- bw_sys bw_rcroot
rm -f "$WORK/bw/ws/.bazelrc.local"
bw_syswarn() {
	env HOME="$WORK/bw/home" USER=probe C_PISCINE_CAMPUS=1 C_PISCINE_GOINFRE="$WORK/bw/goinfre" \
		"$SH" -c '. "$1/tools/drives.sh" && drives_root_warning "$2" "$1"' _ \
		"$WORK/bw/ws" "$WORK/bw/home/.cache/42-piscine/bazel"
}
want_out "drives: ...and the campus warning, for a root in the home" \
	'which is inside your home' -- bw_sys bw_syswarn
want_broken_none "drives: ...never names it as read after .bazelrc.local" \
	"$WORK/bw/system.bazelrc" -- bw_sys bw_syswarn
# A cache dir, a /goinfre stand-in or a home given with a trailing slash
# (V168): the choice is joined with one slash, never <dir>//42-piscine, which
# setup.sh prints and writes into the --disk_cache line. And a home ending in
# / still holds a root in its cache: the doubled join was what let such a home
# match, so tidying the join alone would have let the campus warning pass a
# root under it. That home is named for the login, as a campus home is, so
# the root is the user's alone and only being in the home makes it no place.
bw_tidy() {  # bw_tidy VAR=VALUE... -- the drive list's choice, predicted, in brackets
	env -u C_PISCINE_SCRATCH HOME="$WORK/bw/home" USER=probe \
		XDG_CACHE_HOME="$WORK/bw/home/.cache" C_PISCINE_GOINFRE="$WORK/bw/no-goinfre" \
		DRIVES_DRY=1 "$@" \
		"$SH" -c '. "$1" && drives_choose && printf "[%s]\n" "$DRIVES_SCRATCH"' _ "$WORK/bw/ws/tools/drives.sh"
}
want_out "drives: a cache dir ending in / joins with one slash" \
	"[$WORK/bw/home/.cache/42-piscine]" -- bw_tidy XDG_CACHE_HOME="$WORK/bw/home/.cache/"
want_out "drives: ...and a /goinfre stand-in ending in two" \
	"[$WORK/bw/goinfre/probe]" -- bw_tidy C_PISCINE_GOINFRE="$WORK/bw/goinfre//"
# With no user name -- USER unset, and an `id -un` that fails, as in a
# container run as --user N with no passwd line -- the per-user scratch is
# the uid's: an empty name made it the shared /goinfre/ (or /tmp/) itself.
# The stand-in id knows uid 4242 and no name for it.
mkdir -p "$WORK/bw/noname/bin" "$WORK/bw/noname/goinfre"
printf '#!/bin/sh\ncase "$*" in\n\t-u) echo 4242 ;;\n\t*) echo "id: cannot find name for user ID 4242" >&2; exit 1 ;;\nesac\n' \
	> "$WORK/bw/noname/bin/id"
chmod +x "$WORK/bw/noname/bin/id"
bw_noname() {  # the drive list's choice, predicted, with no user name
	env -u C_PISCINE_SCRATCH -u USER PATH="$WORK/bw/noname/bin:$PATH" HOME="$WORK/bw/home" \
		XDG_CACHE_HOME="$WORK/bw/home/.cache" C_PISCINE_GOINFRE="$WORK/bw/noname/goinfre" \
		DRIVES_DRY=1 \
		"$SH" -c '. "$1" && drives_choose && printf "[%s]\n" "$DRIVES_SCRATCH"' _ "$WORK/bw/ws/tools/drives.sh"
}
want_out "drives: with no user name, the per-user scratch is the uid's" \
	"[$WORK/bw/noname/goinfre/4242]" -- bw_noname
mkdir -p "$WORK/bw/users/probe"
bw_homeslash() {  # bw_homeslash SCRIPT -- SCRIPT, with a home ending in /
	env -u C_PISCINE_SCRATCH -u XDG_CACHE_HOME HOME="$WORK/bw/users/probe/" USER=probe \
		C_PISCINE_GOINFRE="$WORK/bw/no-goinfre" DRIVES_DRY=1 \
		"$SH" -c ". \"\$1\" && $1" _ "$WORK/bw/ws/tools/drives.sh"
}
want_green "drives: a home ending in / holds the paths under it" -- \
	bw_homeslash "drives_under_home '$WORK/bw/users/probe/.cache/42-piscine/bazel'"
want_green "drives: ...and the root chosen in its cache is no place on campus" -- \
	bw_homeslash 'drives_choose && ! drives_root_ok "$DRIVES_SCRATCH/bazel"'
# A C_PISCINE_SCRATCH it cannot use is never passed on, and it says so. A
# relative one was: the probe made the directory in whatever folder `bazel`
# was typed in, and Bazel was handed a relative root. Now it adds nothing,
# which leaves Bazel's own default -- and that is said, because otherwise the
# place you named is replaced without a word.
bw_rel() { ( cd "$WORK/bw" && C_PISCINE_SCRATCH=rel/scratch && export C_PISCINE_SCRATCH && "$@" ); }
want_broken_none "bazel wrapper: a relative C_PISCINE_SCRATCH is not passed on" \
	"ARG:--output_user_root" -- bw_rel bw_run 0 info
want_out "bazel wrapper: ...and it says why" \
	"which must be an absolute path" -- bw_rel bw_run 0 info
want_green "bazel wrapper: ...and makes no directory for it" -- test ! -e "$WORK/bw/rel"
# Run by hand, with no Bazel to hand over to, it says what it is, exit 2.
want_broken "bazel wrapper: without BAZEL_REAL it refuses and says why" \
	"BAZEL_REAL is not set" -- env -u BAZEL_REAL "$SH" "$WORK/bw/ws/tools/bazel" info

