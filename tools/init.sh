#!/bin/sh
# init.sh — one-time setup after cloning this repo.    Run with:
#     bazel run //tools:init                       # interactive prompts
#     bazel run //tools:init -- --login jdoe --email jdoe@student.42campus.fr
#
# Stores your 42 login + email where BOTH the kube.42header VS Code extension and
# submit (tools/submit.sh) read them — the "42header.username" / "42header.email"
# keys in .vscode/settings.json — then points this repo's LOCAL git identity at
# the same values so your commits are attributed correctly.
#
# Usage:
#   bazel run //tools:init [-- --login LOGIN --email EMAIL]
#
#   --login   your 42 login; prompted for if omitted
#   --email   your 42 email; prompted for if omitted
#
# Both are written to .vscode/settings.json and the local git identity, which is
# where every 42 header stamped afterwards gets its name from.
#
# It also looks at where Bazel keeps this checkout's state, once, because init
# is the one command every newcomer runs: on a campus box a root inside the
# quota'd $HOME, or one with no login in it, is warned about here (finding
# 001). The check is tools/drives.sh's, the same one setup.sh and env_drift use,
# and its advice names the directory to move to.
#
# And it ends by naming ONE module's basic suite, the way setup.sh and the
# README do: the whole repo is more than a first run needs, and on a campus box
# more than it can afford (finding 006). Submitting has its own page.

set -u

# Where `bazel run` started this: inside the output base Bazel is using, which
# is how the warning below reads the root back rather than predicting it.
START_PWD=$PWD

# The external commands this runner takes from PATH. See diff_output.sh for why
# they are declared and probed; exit 2, never 1, because this says the check
# never ran rather than that the code under test is wrong.
require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "init.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat dirname git grep mkdir mktemp rm sed

# Repo root: from `bazel run` it's BUILD_WORKSPACE_DIRECTORY; run directly it's the
# parent of tools/.
WS="${BUILD_WORKSPACE_DIRECTORY:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$WS" || exit 1
SETTINGS=".vscode/settings.json"

LOGIN=""
EMAIL=""
# `--flag` with nothing after it used to die as "2: parameter not set" from
# `set -u` -- the right exit code wrapped in raw shell. Same loop in every
# runner, so the fix is the same three lines in every runner.
need() { [ "$2" -ge 2 ] || { echo "init.sh: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
	case "$1" in
		--login) need "$1" "$#"; LOGIN="$2"; shift 2 ;;
		--email) need "$1" "$#"; EMAIL="$2"; shift 2 ;;
		-h|--help) echo "usage: bazel run //tools:init [-- --login L --email E]"; exit 0 ;;
		*) echo "init.sh: unknown argument: $1" >&2; exit 2 ;;
	esac
done

# Prompt for anything not supplied on the command line.
INTERACTIVE=0
if [ -z "$LOGIN" ]; then
	INTERACTIVE=1
	printf 'Your 42 login                  (e.g. jdoe): '
	read -r LOGIN
fi
if [ -z "$EMAIL" ]; then
	INTERACTIVE=1
	printf 'Your 42 email (e.g. jdoe@student.42campus.fr): '
	read -r EMAIL
fi

trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
LOGIN=$(trim "$LOGIN")
EMAIL=$(trim "$EMAIL")

[ -n "$LOGIN" ] || { echo "init.sh: login cannot be empty." >&2; exit 1; }
[ -n "$EMAIL" ] || { echo "init.sh: email cannot be empty." >&2; exit 1; }
case "$EMAIL" in
	*@*.*) : ;;
	*) echo "init.sh: '$EMAIL' does not look like an email address." >&2; exit 1 ;;
esac

mkdir -p .vscode
[ -f "$SETTINGS" ] || printf '{\n}\n' > "$SETTINGS"

# Escape characters that are special on the replacement side of sed.
esc() { printf '%s' "$1" | sed 's/[&\\|]/\\&/g'; }

set_key() { # set_key <42header-suffix> <value>
	k=$1
	v=$(esc "$2")
	tmp=$(mktemp) || exit 1
	if grep -q "\"42header.$k\"" "$SETTINGS"; then
		sed "s|\(\"42header.$k\"[[:space:]]*:[[:space:]]*\"\)[^\"]*\"|\1$v\"|" "$SETTINGS" > "$tmp"
	else
		# insert the key right after the first opening brace
		awk -v ins="  \"42header.$k\": \"$2\"," \
			'!done && /{/ { print; print ins; done = 1; next } { print }' "$SETTINGS" > "$tmp"
	fi || {
		echo "init.sh: could not prepare the new $SETTINGS; it was left as it was." >&2
		rm -f "$tmp"; exit 1; }
	# Into the file, not moved over it: a mktemp file is 0600, and mv would
	# leave settings.json with that mode. Rewriting in place keeps mode and owner.
	# `>` empties it first, so a write that fails part-way leaves it cut short
	# and $tmp is the only whole copy: kept, and named.
	if ! cat "$tmp" > "$SETTINGS"; then
		echo "init.sh: could not write $SETTINGS, which may now be cut short." >&2
		echo "  Its full new contents are in $tmp; once it can be written again" >&2
		echo "  (is the disk full?), put them back with:  cat '$tmp' > '$SETTINGS'" >&2
		exit 1
	fi
	rm -f "$tmp"
}

set_key username "$LOGIN"
set_key email "$EMAIL"

# Local git identity (this repo only — your global ~/.gitconfig is left untouched).
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	git config user.name "$LOGIN"
	git config user.email "$EMAIL"
	GIT_NOTE="local git identity set"
else
	GIT_NOTE="not inside a git repo — skipped git config"
fi

printf '\nDone.\n'
printf '  42header.username = %s\n' "$LOGIN"
printf '  42header.email    = %s\n' "$EMAIL"
printf '  %s\n' "$GIT_NOTE"

# Existing files still carry the placeholder header identity. Offer to re-stamp
# them now (rewrites the 11-line 42 header of every deliverable, body untouched).
RESTAMP=n
if [ "$INTERACTIVE" = 1 ]; then
	printf '\nRe-stamp every file header with this identity now? [y/N]: '
	read -r RESTAMP
fi
case "$RESTAMP" in
	[yY]*)
		sh tools/reset_headers.sh && printf 'Headers re-stamped.\n' ;;
	*)
		printf '\nTo stamp your identity onto the existing file headers later, run:\n'
		printf '    42 header --reset --all\n' ;;
esac

# On a campus box, where this checkout's Bazel state is -- and nothing
# anywhere else. tools/drives.sh is read from the workspace, like every other
# script that asks it. It was looked for beside $0, which under `bazel run` is
# bazel-bin's symlink to this file with nothing beside it: the check quietly
# never ran for the one command every newcomer runs, while the selftest ran it
# from tools/ and stayed green. It now runs it the way `bazel run` does too.
if [ -r "$WS/tools/drives.sh" ]; then
	# shellcheck source=drives.sh
	. "$WS/tools/drives.sh"
	drives_campus
	if [ "$DRIVES_CAMPUS" = 1 ]; then
		_warn=$(drives_root_warning "$(drives_state_of "$WS" "$START_PWD" "$0")" "$WS")
		[ -z "$_warn" ] || printf '\n%s\n' "$_warn"
	fi
else
	printf '\ninit.sh: %s is missing, so where Bazel keeps this\n' "$WS/tools/drives.sh" >&2
	printf '  checkout'\''s state was not checked. Is the checkout complete?\n' >&2
fi

# The README's next step, as `42` types it: a newcomer follows the last thing
# on screen, and docs/bazel.md says what it runs underneath.
printf '\nNext, from the top folder of this checkout, the tests of C 00 ex01:\n'
printf '    cd c-piscine/c-piscine-c-00/deliverable/ex01\n'
printf '    42 test\n'
printf 'README.md (step 3) reads that red with you. Pushing to 42 is\n'
printf 'docs/submitting.md.\n'
