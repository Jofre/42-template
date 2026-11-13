# ------------------------------------------------------------------ postcreate
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# .devcontainer/postcreate.sh, which the dev container runs once when it is
# created, gives the container's Bazel a disk cache: two build lines in the
# container's own ~/.bazelrc, the cache where tools/drives.sh puts setup.sh's
# and the same 4G cap, and no startup option. Run here in a toy checkout (the
# script, the drive list it reads, 42's installer, which it runs first) with a
# HOME of its own, so no arm reads or writes the home of whoever runs it.
# XDG_CACHE_HOME and C_PISCINE_SCRATCH are cleared and /goinfre named absent,
# so the drive list's answer is the sandbox's cache folder on any machine.
PCR="$WORK/pcr"
mkdir -p "$PCR/ws/.devcontainer" "$PCR/ws/tools/fortytwo" "$PCR/ws/inside" \
	"$PCR/home" "$PCR/own" "$PCR/named" "$PCR/other"
: > "$PCR/ws/MODULE.bazel"
cp "$TOOLS/../.devcontainer/postcreate.sh" "$PCR/ws/.devcontainer/postcreate.sh"
cp "$TOOLS/drives.sh" "$PCR/ws/tools/drives.sh"
cp "$TOOLS/42.sh" "$PCR/ws/tools/42.sh"
cp "$TOOLS/fortytwo/install.sh" "$PCR/ws/tools/fortytwo/install.sh"
pcr_run() {  # pcr_run HOME [VAR=VALUE...] -- postcreate.sh in the toy checkout
	_pcr_home=$1
	shift
	env -u XDG_CACHE_HOME -u C_PISCINE_SCRATCH HOME="$_pcr_home" USER=probe \
		C_PISCINE_GOINFRE="$PCR/no-goinfre" "$@" "$SH" "$PCR/ws/.devcontainer/postcreate.sh"
}
PCR_GC="build --experimental_disk_cache_gc_max_size=4G"
pcr_run "$PCR/home" > "$PCR/first.out" 2>&1
want_green "postcreate: writes ~/.bazelrc, with the disk cache" -- \
	grep -qxF "build --disk_cache=$PCR/home/.cache/42-piscine/bazel-disk" "$PCR/home/.bazelrc"
want_green "postcreate: ...and its 4G cap" -- grep -qxF "$PCR_GC" "$PCR/home/.bazelrc"
# Two lines and nothing else: a startup option there would be read after every
# checkout's .bazelrc.local and win over it.
want_green "postcreate: ...and no other option, startup or build" -- \
	sh -c '[ "$(grep -v "^[[:blank:]]*#" "$1" | grep -c "[^[:blank:]]")" = 2 ]' _ "$PCR/home/.bazelrc"
want_out "postcreate: ...and says where the cache is" \
	"$PCR/home/.cache/42-piscine/bazel-disk" -- cat "$PCR/first.out"
cp "$PCR/home/.bazelrc" "$PCR/first.rc" 2> /dev/null
pcr_run "$PCR/home" > /dev/null 2>&1
want_green "postcreate: run again, ~/.bazelrc is unchanged" -- \
	cmp -s "$PCR/first.rc" "$PCR/home/.bazelrc"
# The drive list's own answer, not a path of the script's: C_PISCINE_SCRATCH
# overrules every candidate there, so it has to here.
pcr_run "$PCR/named" C_PISCINE_SCRATCH="$PCR/scratch" > /dev/null 2>&1
want_green "postcreate: the cache is where tools/drives.sh says" -- \
	grep -qxF "build --disk_cache=$PCR/scratch/bazel-disk" "$PCR/named/.bazelrc"
# A ~/.bazelrc of yours: kept, line for line, and a disk cache it already names
# stays the only one (a line appended after it would win). Its last line has no
# newline, which an append must not run into.
printf '# mine\nbuild --jobs=2\nbuild --disk_cache=%s/elsewhere' "$PCR" > "$PCR/own/.bazelrc"
cp "$PCR/own/.bazelrc" "$PCR/own.before"
pcr_run "$PCR/own" > /dev/null 2>&1
want_green "postcreate: a ~/.bazelrc of yours keeps its lines" -- \
	sh -c '[ "$(head -n 3 "$1")" = "$(cat "$2")" ]' _ "$PCR/own/.bazelrc" "$PCR/own.before"
want_green "postcreate: ...its disk cache stays the only one" -- \
	sh -c '[ "$(grep -c -- "--disk_cache=" "$1")" = 1 ]' _ "$PCR/own/.bazelrc"
want_green "postcreate: ...and gets the cap" -- grep -qxF "$PCR_GC" "$PCR/own/.bazelrc"
# Only the cap went in, so the note over it is one that fits a cap alone: it
# used to say "this container's disk cache", over no cache line at all.
want_green "postcreate: ...under a note that fits the cap alone" -- \
	grep -qxF "# added by .devcontainer/postcreate.sh, for Bazel's disk cache" "$PCR/own/.bazelrc"
cp "$PCR/own/.bazelrc" "$PCR/own.after" 2> /dev/null
pcr_run "$PCR/own" > /dev/null 2>&1
want_green "postcreate: ...and a second run changes nothing" -- \
	cmp -s "$PCR/own.after" "$PCR/own/.bazelrc"
# The workspace is bind-mounted from the host, so nothing of this goes into
# it: neither the rc file (a home inside the checkout) nor the cache.
want_out "postcreate: a home inside the workspace gets no ~/.bazelrc, and says so" \
	"inside the workspace" -- pcr_run "$PCR/ws/inside"
want_green "postcreate: ...none" -- test ! -e "$PCR/ws/inside/.bazelrc"
want_out "postcreate: a cache inside the workspace is refused, and says so" \
	"inside the workspace" -- pcr_run "$PCR/other" C_PISCINE_SCRATCH="$PCR/ws/cache"
want_green "postcreate: ...and nothing is made there" -- test ! -e "$PCR/ws/cache"
want_green "postcreate: ...nor a ~/.bazelrc naming it" -- test ! -e "$PCR/other/.bazelrc"
# The prediction is only that: the real choice probes each candidate for
# real, and one the prediction took can fail there, so the drive list goes on
# to the next. Here /goinfre's folder for you is a link to nothing, and the
# cache dir is inside the workspace, where the real choice lands. The
# prediction finds nothing at the link (test -e follows it) and takes the
# folder it would go in, which is writable; mkdir -p refuses the link, for
# root too. A plain file there no
# longer does: the prediction refuses it as well, the real choice never runs,
# and no arm below reaches what it cleans up. So the fixture is checked first.
mkdir -p "$PCR/goinfre" "$PCR/fall" "$PCR/rel"
ln -s "$PCR/nowhere" "$PCR/goinfre/probe"
want_green "postcreate: the fixture: the prediction takes /goinfre, the real probe refuses it" -- \
	"$SH" -c '. "$1" && DRIVES_DRY=1 && drives_probe "$2" && unset DRIVES_DRY &&
		! drives_probe "$2"' \
	_ "$PCR/ws/tools/drives.sh" "$PCR/goinfre/probe"
want_out "postcreate: a cache the real choice puts in the workspace is refused" \
	"inside the workspace" -- \
	pcr_run "$PCR/fall" C_PISCINE_GOINFRE="$PCR/goinfre" XDG_CACHE_HOME="$PCR/ws/xdg"
want_green "postcreate: ...and no ~/.bazelrc names it" -- test ! -e "$PCR/fall/.bazelrc"
# The real probe made that folder, and its parent, to write a byte in it: an
# empty folder left in the checkout the host shares. What it made goes, and
# nothing else: a folder that was there before stays, empty or not.
want_green "postcreate: ...and the folders its probe made there are gone" -- \
	test ! -e "$PCR/ws/xdg"
mkdir -p "$PCR/ws/had" "$PCR/ws/hadall/42-piscine"
pcr_run "$PCR/fall" C_PISCINE_GOINFRE="$PCR/goinfre" XDG_CACHE_HOME="$PCR/ws/had" > /dev/null 2>&1
want_green "postcreate: ...a folder that was there before stays" -- test -d "$PCR/ws/had"
want_green "postcreate: ...and the one made in it goes" -- test ! -e "$PCR/ws/had/42-piscine"
want_out "postcreate: ...a cache folder that was there before is refused too" \
	"inside the workspace" -- \
	pcr_run "$PCR/fall" C_PISCINE_GOINFRE="$PCR/goinfre" XDG_CACHE_HOME="$PCR/ws/hadall"
want_green "postcreate: ...and stays" -- test -d "$PCR/ws/hadall/42-piscine"
# A cache dir given with a trailing slash: the drive list tidies it before
# the join (V168), and every folder the probe made still goes.
pcr_run "$PCR/fall" C_PISCINE_GOINFRE="$PCR/goinfre" XDG_CACHE_HOME="$PCR/ws/deep/a/b/" > /dev/null 2>&1
want_green "postcreate: ...and a cache dir with a trailing slash leaves no folder it made" -- \
	test ! -e "$PCR/ws/deep"
# The drive list refusing outright, as it does a relative C_PISCINE_SCRATCH:
# its reason, a green exit, and no ~/.bazelrc.
want_out "postcreate: a drive list that refuses is named, with its reason" \
	"Bazel gets no disk cache here: C_PISCINE_SCRATCH is set to 'rel'" -- \
	pcr_run "$PCR/rel" C_PISCINE_SCRATCH=rel
want_green "postcreate: ...exits 0" -- pcr_run "$PCR/rel" C_PISCINE_SCRATCH=rel
want_green "postcreate: ...and writes no ~/.bazelrc" -- test ! -e "$PCR/rel/.bazelrc"
# A .bazelrc.local the host's setup.sh wrote, rooting Bazel under a home this
# container may not write (V239): every Bazel run here stopped with a bare
# mkdir FATAL. The checkout's file is the host's too, so it is left alone, and
# the container's own ~/.bazelrc, which Bazel reads after it, gets a root of
# the container's own: tools/bazel's default here. Below a folder of mode
# 555, as the container's /home is to its user.
mkdir -p "$PCR/ro" "$PCR/roh" "$PCR/rok" "$PCR/roq" "$PCR/rod/.bazelrc" "$PCR/rof" &&
	chmod 555 "$PCR/ro"
PCR_RO="startup --output_user_root=$PCR/ro/x/bazel"
printf '%s\n' "$PCR_RO" > "$PCR/ws/.bazelrc.local"
want_out "postcreate: a .bazelrc.local root it cannot create is named" \
	"$PCR/ws/.bazelrc.local" -- pcr_run "$PCR/roh"
want_green "postcreate: ...and ~/.bazelrc gets a root of the container's own" -- \
	grep -qxF "startup --output_user_root=$PCR/roh/.cache/42-piscine/bazel" "$PCR/roh/.bazelrc"
pcr_roots() {  # pcr_roots HOME -- run again: still one root line in HOME's ~/.bazelrc
	pcr_run "$1" > /dev/null 2>&1
	[ "$(grep -c -- "--output_user_root" "$1/.bazelrc")" = 1 ]
}
want_green "postcreate: ...and a second run adds no second one" -- pcr_roots "$PCR/roh"
want_green "postcreate: ...and the checkout's .bazelrc.local is left as it was" -- \
	sh -c '[ "$(cat "$1")" = "$2" ]' _ "$PCR/ws/.bazelrc.local" "$PCR_RO"
# With no root of the container's own either (a relative C_PISCINE_SCRATCH),
# or a ~/.bazelrc it cannot write (a folder here), it says so and writes none.
want_out "postcreate: ...and with no root of its own, says what to set" \
	"No root of the container's own qualifies either" -- pcr_run "$PCR/roq" C_PISCINE_SCRATCH=rel
want_green "postcreate: ...writing no startup line" -- \
	sh -c '! grep -qs -- --output_user_root "$1"' _ "$PCR/roq/.bazelrc"
want_out "postcreate: ...and a ~/.bazelrc it cannot write is named" \
	"could not write $PCR/rod/.bazelrc; Bazel cannot start in this container" -- pcr_run "$PCR/rod"
# ...by the script alone: the shell's own error for the redirection that
# failed ("postcreate.sh: <line>: cannot create ...") came first, in both rc
# writers, and read as a crash (V330). No line the script prints holds
# "postcreate.sh:", which every shell's error starts with. The disk cache's
# refusal is named too, and a folder said to be one.
want_broken_none "postcreate: ...without the shell's own error" \
	"postcreate.sh:" -- pcr_run "$PCR/rod"
want_out "postcreate: ...and the disk cache's refusal is named too" \
	"could not write $PCR/rod/.bazelrc; Bazel gets no disk cache here" -- pcr_run "$PCR/rod"
want_out "postcreate: ...saying the ~/.bazelrc is a folder" \
	"($PCR/rod/.bazelrc is a folder: it has to be a file)" -- pcr_run "$PCR/rod"
# Below a plain file, mkdir fails for root too, and drives_probe's prediction
# says so now: it used to walk past the file and call the root creatable,
# and the container got no root of its own.
: > "$PCR/plain"
printf 'startup --output_user_root=%s/plain/x/bazel\n' "$PCR" > "$PCR/ws/.bazelrc.local"
pcr_run "$PCR/rof" > /dev/null 2>&1
want_green "postcreate: a .bazelrc.local root below a plain file gets one too" -- \
	grep -qxF "startup --output_user_root=$PCR/rof/.cache/42-piscine/bazel" "$PCR/rof/.bazelrc"
# A root it can create is the host's business and this one's alike: no line,
# in a ~/.bazelrc the run did write. A negated grep alone passed on no file
# at all (grep's 2, negated), which is what a run that died first leaves.
printf 'startup --output_user_root=%s/mine/bazel\n' "$PCR" > "$PCR/ws/.bazelrc.local"
pcr_run "$PCR/rok" > /dev/null 2>&1
want_green "postcreate: a .bazelrc.local root it can create gets no startup line" -- \
	sh -c '[ -f "$1" ] && [ "$(grep -c -- --output_user_root "$1")" = 0 ]' _ "$PCR/rok/.bazelrc"
want_green "postcreate: ...and still writes its ~/.bazelrc" -- \
	grep -qxF "build --disk_cache=$PCR/rok/.cache/42-piscine/bazel-disk" "$PCR/rok/.bazelrc"
rm -f "$PCR/ws/.bazelrc.local"
chmod 755 "$PCR/ro"
