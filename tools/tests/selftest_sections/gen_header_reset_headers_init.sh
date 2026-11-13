# -------------------------------------------------- gen_header, reset_headers, init
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# The header tools rewrite files the student owns, so what they must never do
# is damage one. gen_header printed the C form for every name, and a C comment
# on a Makefile's first line stops make with "missing separator"; it now follows
# the file name the way the 42 editor plugins do, and refuses a name it has no
# form for. reset_headers and init moved a mktemp file over the one they
# rewrote, which left it at mode 0600: an executable lost its execute bit.
mkdir -p "$WORK/hdr/mk"
LOGIN42=selftest EMAIL42=selftest@42.fr \
	"$SH" "$TOOLS/gen_header.sh" Makefile > "$WORK/hdr/mk.hdr"
cat "$WORK/hdr/mk.hdr" > "$WORK/hdr/mk/Makefile"
printf 'all:\n\t@echo built\n' >> "$WORK/hdr/mk/Makefile"
want_green "gen_header: a Makefile's header is one make parses" -- \
	make -s -C "$WORK/hdr/mk"
want_green "gen_header: ...eleven lines, every one 80 columns" -- \
	awk 'length($0) != 80 { bad = 1 } END { exit bad || NR != 11 }' "$WORK/hdr/mk.hdr"
want_green "gen_header: a script's header is # comments too" -- \
	sh -c '"$1" "$2" x.sh | head -n 1 | grep -qx "# \*\{76\} #"' _ \
		"$SH" "$TOOLS/gen_header.sh"
want_broken "gen_header: a type with no header form is refused" \
	'no 42 header format' -- \
	"$SH" "$TOOLS/gen_header.sh" notes.txt
# The identity is the one VS Code and the 42header extension read, which
# skip comments: a login commented out above the live one stamped "By: old"
# (V186), and so did one in a "[c]" override (V307). gen_header asks the
# workspace's tools/identity.sh, the reader tools/submit.sh and `42 config
# get` ask too; tools/fortytwo/tests/test_config.py holds all three to it.
mkdir -p "$WORK/hdr/cm/.vscode" "$WORK/hdr/cm/tools"
cp "$TOOLS/identity.sh" "$WORK/hdr/cm/tools/identity.sh"
printf '{\n  // "42header.username": "old",\n  "42header.username": "new",\n  "42header.email": "n@x.fr"\n}\n' \
	> "$WORK/hdr/cm/.vscode/settings.json"
want_out "gen_header: a // line is not the identity it stamps" 'By: new <n@x.fr>' -- \
	env -u LOGIN42 -u EMAIL42 BUILD_WORKSPACE_DIRECTORY="$WORK/hdr/cm" \
	"$SH" "$TOOLS/gen_header.sh" x.c
printf '{\n  "[c]": { "42header.username": "old" },\n  "42header.email": "n@x.fr"\n}\n' \
	> "$WORK/hdr/cm/.vscode/settings.json"
want_out "gen_header: ...nor is a \"[c]\" override's" 'By: marvin <n@x.fr>' -- \
	env -u LOGIN42 -u EMAIL42 BUILD_WORKSPACE_DIRECTORY="$WORK/hdr/cm" \
	"$SH" "$TOOLS/gen_header.sh" x.c

# reset_headers runs from a workspace root and calls tools/gen_header.sh there,
# so the fixture is a small workspace of its own.
mkdir -p "$WORK/rh/tools" "$WORK/rh/m"
cp "$TOOLS/gen_header.sh" "$WORK/rh/tools/gen_header.sh"
LOGIN42=before EMAIL42=before@42.fr \
	"$SH" "$TOOLS/gen_header.sh" x.c > "$WORK/rh/m/x.c"
printf '\nint\tg_x;\n' >> "$WORK/rh/m/x.c"
tail -n +12 "$WORK/rh/m/x.c" > "$WORK/rh/body"
chmod 755 "$WORK/rh/m/x.c"
want_green "reset_headers: a headered file is re-stamped" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/rh" LOGIN42=after EMAIL42=after@42.fr \
	"$SH" "$TOOLS/reset_headers.sh" m/x.c
want_green "reset_headers: ...with the new identity" -- \
	grep -q 'By: after <after@42.fr>' "$WORK/rh/m/x.c"
want_green "reset_headers: ...keeping the file's mode" -- \
	test -n "$(find "$WORK/rh/m/x.c" -perm 0755)"
want_green "reset_headers: ...and its body, byte for byte" -- \
	sh -c 'tail -n +12 "$1" | cmp -s - "$2"' _ "$WORK/rh/m/x.c" "$WORK/rh/body"
# A write that fails. `cat "$tmp" > "$f"` empties the file before writing, so
# one that fails part-way (a full disk) leaves it cut short, and the old code
# then deleted $tmp, the only whole copy, and went on to cut the next file short
# too. A read-only file stands in for the full disk: its write fails the same
# way, minus the damage.
mkdir -p "$WORK/rh/tmp"
cp "$WORK/rh/m/x.c" "$WORK/rh/m/a.c"
cp "$WORK/rh/m/x.c" "$WORK/rh/m/b.c"
chmod 444 "$WORK/rh/m/a.c"
# The failed run happens once (once), and each arm reads what it printed:
# the message is the student's only way back to the whole copy, and arms
# that looked for any whole copy in TMPDIR passed on a message that named
# no file and gave no command to put it back. a.c stays as it is until
# every one of them has run.
rh_fail() {  # rh_fail -- the run whose write to m/a.c fails
	once env BUILD_WORKSPACE_DIRECTORY="$WORK/rh" TMPDIR="$WORK/rh/tmp" \
		LOGIN42=third EMAIL42=third@42.fr "$SH" "$TOOLS/reset_headers.sh" m/a.c m/b.c
}
rh_kept() {  # rh_kept -- true when the file the message names holds the whole new copy
	_rh_t=$(rh_fail | awk 'p { sub(/^[[:blank:]]+/, ""); print; exit } /are in:$/ { p = 1 }')
	[ -n "$_rh_t" ] || { echo "no file named after 'are in:'"; return 1; }
	grep -q "By: third" "$_rh_t" && tail -n +12 "$_rh_t" | cmp -s - "$WORK/rh/body"
}
want_red "reset_headers: a write that fails stops the run" -- rh_fail
want_out "reset_headers: ...saying how to put the whole copy back" \
	"cat '$WORK/rh/tmp/" -- rh_fail
want_green "reset_headers: ...keeping the whole file where it says" -- rh_kept
want_broken_none "reset_headers: ...and touching nothing after it" \
	'By: third' -- cat "$WORK/rh/m/b.c"
chmod 644 "$WORK/rh/m/a.c"
# A file found under a folder is named as it is. `for f in $TARGETS` split
# `x copy.c` -- the name a file manager gives a duplicate -- into `x` and
# `copy.c`, skipped both as having no header, and the file kept the identity
# it had: the template build's own count then stopped it on a file nothing
# had touched.
mkdir -p "$WORK/rh/m2"
cp "$WORK/rh/m/b.c" "$WORK/rh/m2/x copy.c"
want_green "reset_headers: a name with a blank is re-stamped" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/rh" LOGIN42=blank EMAIL42=blank@42.fr \
	"$SH" "$TOOLS/reset_headers.sh" m2
want_green "reset_headers: ...with the new identity" -- \
	grep -q 'By: blank <blank@42.fr>' "$WORK/rh/m2/x copy.c"
# A run that did nothing it was asked to do is no success. A named path that
# does not exist -- a typo, or a path relative to a module, which `bazel run`
# reads from the repo root -- was dropped by find with its error thrown away,
# and the run said "reset 0 file(s)" and exited 0, beside good paths too. And
# a gen_header that failed counted as a plain skip, so init.sh printed
# "Headers re-stamped." over headers left as they were. Here the workspace's
# own gen_header is a stand-in that refuses, as one missing a tool does.
rh_run() {  # rh_run DIR LOGIN PATH...: reset_headers in the workspace DIR
	_rhw=$1; _rhl=$2; shift 2
	env BUILD_WORKSPACE_DIRECTORY="$_rhw" LOGIN42="$_rhl" EMAIL42="$_rhl@42.fr" \
		"$SH" "$TOOLS/reset_headers.sh" "$@"
}
want_broken "reset_headers: a named path that does not exist is refused" \
	"m/no-such.c" -- rh_run "$WORK/rh" typo m/no-such.c
want_broken "reset_headers: ...beside one that does, too" \
	"m/no-such.c" -- rh_run "$WORK/rh" typo m/b.c m/no-such.c
want_broken_none "reset_headers: ...touching neither" 'By: typo' -- cat "$WORK/rh/m/b.c"
mkdir -p "$WORK/rhg/tools" "$WORK/rhg/m"
printf '#!/bin/sh\necho "gen_header.sh: required command awk is not on PATH" >&2\nexit 2\n' \
	> "$WORK/rhg/tools/gen_header.sh"
cp "$WORK/rh/m/b.c" "$WORK/rhg/m/x.c"
cp "$WORK/rhg/m/x.c" "$WORK/rhg/x.before"
want_red "reset_headers: a gen_header that fails fails the run" -- rh_run "$WORK/rhg" gen m/x.c
want_out "reset_headers: ...counting the file as failed" "failed 1" -- rh_run "$WORK/rhg" gen m/x.c
want_green "reset_headers: ...and leaving it as it was" -- cmp -s "$WORK/rhg/m/x.c" "$WORK/rhg/x.before"

# init writes the identity into .vscode/settings.json. Its own git repo, so
# the `git config` it runs lands in the fixture and nowhere else.
mkdir -p "$WORK/in/.vscode" "$WORK/in/tools"
git init -q "$WORK/in"
# The workspace's own tools/drives.sh, which init reads for its campus check,
# and tools/identity.sh, which writes what init is given.
cp "$TOOLS/drives.sh" "$WORK/in/tools/drives.sh"
cp "$TOOLS/identity.sh" "$WORK/in/tools/identity.sh"
printf '{\n  "editor.tabSize": 4\n}\n' > "$WORK/in/.vscode/settings.json"
chmod 644 "$WORK/in/.vscode/settings.json"
want_green "init: records the identity" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	"$SH" "$TOOLS/init.sh" --login selftest --email selftest@42.fr
want_green "init: ...in settings.json" -- \
	grep -q '"42header.username": "selftest"' "$WORK/in/.vscode/settings.json"
want_green "init: ...keeping its mode" -- \
	test -n "$(find "$WORK/in/.vscode/settings.json" -perm 0644)"
# A value that could not be stored as typed is refused, and the file is left
# as it was: `a"b` went in between the quotes as it came, and left a
# settings.json no JSON reader could open. tools/identity.sh is the one
# writer, `42 config set login|email` writes through it too, and init has it
# check both values before it writes either.
want_red "init: a login holding a '\"' is refused" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	"$SH" "$TOOLS/init.sh" --login 'a"b' --email selftest@42.fr
want_out "init: ...and says what a login holds" "letters, digits, '.', '_' and '-'" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	"$SH" "$TOOLS/init.sh" --login 'a"b' --email selftest@42.fr
want_broken_none "init: ...leaving settings.json as it was" 'a"b' -- \
	cat "$WORK/in/.vscode/settings.json"
want_red "init: an email with a blank is refused" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	"$SH" "$TOOLS/init.sh" --login fresh --email 'fresh @42.fr'
want_broken_none "init: ...before the login beside it is written" '"fresh"' -- \
	cat "$WORK/in/.vscode/settings.json"
want_red "init: a login that is an email is refused" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	"$SH" "$TOOLS/init.sh" --login selftest@42.fr --email selftest@42.fr
# ...and a settings.json it cannot write is a failure, never "Done.", that
# changes nothing: the git identity, set before the file, is put back, and no
# temporary file is left behind.
mkdir -p "$WORK/in-tmp"
chmod 444 "$WORK/in/.vscode/settings.json"
want_red "init: a settings.json it cannot write fails the run" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	TMPDIR="$WORK/in-tmp" "$SH" "$TOOLS/init.sh" --login other --email other@42.fr
want_green "init: ...with the git identity put back" -- \
	sh -c 'test "$(git -C "$1" config --local --get user.name)" = selftest' _ "$WORK/in"
want_green "init: ...the email too" -- \
	sh -c 'test "$(git -C "$1" config --local --get user.email)" = selftest@42.fr' _ "$WORK/in"
want_green "init: ...and no file left behind" -- \
	sh -c 'test -z "$(find "$1" -mindepth 1)"' _ "$WORK/in-tmp"
chmod 644 "$WORK/in/.vscode/settings.json"

# A tool identity.sh needs and does not find is no refused value: the check
# never ran, so init says 2, as identity.sh does, and never the 1 of a refusal.
mkdir -p "$WORK/in_noawk"
for _t in sh "$SH" cat dirname git grep head id mkdir mktemp od rm sed tail tr uname; do
	ln -sf "$(command -v "$_t")" "$WORK/in_noawk/$_t" 2> /dev/null
done
want_broken "init: a tool identity.sh lacks is a 2, never a refusal" \
	"required command 'awk' is not on PATH" -- \
	env PATH="$WORK/in_noawk" BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	"$SH" "$TOOLS/init.sh" --login selftest --email selftest@42.fr

# A file that can take the login and not the email changes neither: the
# shape was found only when the email was set, after the new login was
# written beside the old email.
cp "$WORK/in/.vscode/settings.json" "$WORK/in-settings.keep"
printf '{\n  "42header.username": "oldl",\n  "42header.email": "old@x.fr", "a": 1\n}\n' \
	> "$WORK/in/.vscode/settings.json"
want_red "init: a file that cannot take the email is refused" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	"$SH" "$TOOLS/init.sh" --login newl --email new@x.fr
want_green "init: ...with the login left as it was" -- \
	grep -q '"42header.username": "oldl"' "$WORK/in/.vscode/settings.json"
cp "$WORK/in-settings.keep" "$WORK/in/.vscode/settings.json"
# ...and so does a git identity it cannot set: behind a stale lock, `git
# config` failed after settings.json held the new login, beside the old email.
: > "$WORK/in/.git/config.lock"
want_red "init: a git identity it cannot set is refused" -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	"$SH" "$TOOLS/init.sh" --login lockl --email lock@x.fr
want_broken_none "init: ...writing neither key" '"lockl"' -- \
	cat "$WORK/in/.vscode/settings.json"
rm -f "$WORK/in/.git/config.lock"
# A git email it cannot set, once the git login is set, puts the login back.
mkdir -p "$WORK/in_gitfail"
printf '#!/bin/sh\ncase "$*" in *"user.email gitfail@x.fr") exit 1 ;; esac\nexec "%s" "$@"\n' \
	"$(command -v git)" > "$WORK/in_gitfail/git"
chmod +x "$WORK/in_gitfail/git"
want_red "init: a git email it cannot set is refused" -- \
	env PATH="$WORK/in_gitfail:$PATH" BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	"$SH" "$TOOLS/init.sh" --login gitfail --email gitfail@x.fr
want_green "init: ...with the git login put back" -- \
	sh -c 'test "$(git -C "$1" config --local --get user.name)" = selftest' _ "$WORK/in"
want_broken_none "init: ...and settings.json left as it was" '"gitfail"' -- \
	cat "$WORK/in/.vscode/settings.json"

# Its last words are the next thing a newcomer types. They were `bazel test
# //...` -- the whole repo, which the README and docs/environment.md both say
# not to run on a campus box -- and an edit to a harness file (finding 006).
# Then one module's :basic suite, typed as Bazel, while the README's next step
# is `42 test` in C 00's ex01: a newcomer follows the last thing on screen, and
# left the README's path there. Now the README's own step, and no Bazel line.
want_out "init: its closing text names the README's first test" \
	'cd c-piscine/c-piscine-c-00/deliverable/ex01' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	"$SH" "$TOOLS/init.sh" --login selftest --email selftest@42.fr
want_out "init: ...and the headers' re-stamp as 42 types it" \
	'42 header --reset --all' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	"$SH" "$TOOLS/init.sh" --login selftest --email selftest@42.fr
want_broken_none "init: ...never a Bazel command to type" \
	'    bazel ' -- \
	env BUILD_WORKSPACE_DIRECTORY="$WORK/in" GIT_CEILING_DIRECTORIES="$WORK" \
	"$SH" "$TOOLS/init.sh" --login selftest --email selftest@42.fr

# ...and on a campus box, where this checkout's Bazel state is (finding 001),
# read back from the output base `bazel run` started it in: the one command
# every newcomer runs is where a shared or quota'd root gets named. Launched
# the way `bazel run //tools:init` launches it, by env_drift's br_run above,
# over a layout br_tree builds for these arms alone (bri): init looked for
# drives.sh beside $0 too, and the warning silently never fired there.
br_tree bri
want_out "init: on campus, a shared Bazel root is warned about" \
	'which is not yours alone' -- br_run bri shared init 1 --login selftest --email selftest@42.fr
want_broken_none "init: ...a per-user one is not" \
	'WARNING: Bazel keeps' -- br_run bri probe/bazel init 1 --login selftest --email selftest@42.fr
want_broken_none "init: ...and off campus neither is" \
	'WARNING: Bazel keeps' -- br_run bri shared init 0 --login selftest --email selftest@42.fr

