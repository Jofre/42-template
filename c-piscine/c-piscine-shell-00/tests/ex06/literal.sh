#!/bin/sh
# Shell 00 ex06, read literally -- its ex06_literal target, at strict.
#
# "lists all the existing files ignored by your Git repository", and the
# example is git's own listing of files, one per line. check.sh (basic)
# grades what every reading of that agrees on; this reads the example word
# for word, which settles two things the subject's sentence leaves open:
#   - a directory ignored as a whole can be listed two ways, each file in it
#     or the one line dir/, and git itself prints either. check.sh accepts
#     both. Read literally, "files" is each ignored file by its path, and a
#     directory is not listed in their place;
#   - the subject names no order. check.sh checks none. Read literally, the
#     lines come in the order git prints a listing: by path, byte by byte
#     (the example's .DS_Store before mywork.c~ is that order too). That is
#     not the order a locale's `sort` gives, nor the order a directory is
#     walked in, so the fixture's names tell them apart.
# Whether 42 grades either of them, the subject does not say -- which is what
# puts this at strict and not at basic (docs/reference.md, "Run contract").
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D="${1:-git_ignore.sh}"
case "$D" in /*) ;; *) D="$PWD/$D" ;; esac
printf "  CHECK: %s, this harness's reading at strict: as the example lists files, each one, in git's order\n" "$D"

ck_require "git_ignore.sh exists" test -f "$D"
ck_sh_parses "$D"

# The repository's own rules and nothing else, as in check.sh.
GIT_CONFIG_NOSYSTEM=1
HOME=$(mktemp -d)
XDG_CONFIG_HOME="$HOME/.config"
export GIT_CONFIG_NOSYSTEM HOME XDG_CONFIG_HOME
# Nor where the repository is, or which configuration it takes, from what a
# run outside Bazel's cleared environment would inherit.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
unset GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

# build/ is ignored as a whole and holds two files, one of them in a
# subdirectory of its own; beside it, names whose byte order (an uppercase
# letter before a lowercase one, a dot before both) is neither a locale's
# order nor the order they are created in.
repo=$(mktemp -d)
(
	cd "$repo" || exit 1
	git init -q . || exit 1
	git config user.email tester@example.com
	git config user.name tester
	printf '*.log\n.DS_Store\nbuild/\n' > .gitignore
	mkdir -p build/deep
	for f in build/deep/b.o alpha.log .DS_Store build/a.o Zeta.log; do
		: > "$f"
	done
	git add .gitignore || exit 1
	git commit -q -m fixture || exit 1
) > /dev/null 2>&1 || { ck "fixture repository created" false; ck_report; }

raw=$(mktemp)
ck_run -C "$repo" "$raw" sh "$D"

ck "lists each file of the ignored directory by its path (build/a.o)" \
	grep -qx build/a.o "$raw"
ck "...nested ones too (build/deep/b.o)" grep -qx build/deep/b.o "$raw"
ck "does not list the directory in their place (build/, build/deep/)" \
	sh -c '[ -s "$1" ] && ! grep -qx -e build/ -e build/deep/ "$1"' _ "$raw"
# The order, asked of a listing that exists. Byte order, written out:
#   .DS_Store  Zeta.log  alpha.log  build/a.o  build/deep/b.o
ck "lists the paths in the order git prints them, byte by byte (.DS_Store, Zeta.log, alpha.log, build/...)" \
	sh -c '[ -s "$1" ] && LC_ALL=C sort -c "$1"' _ "$raw"

rm -f "$raw" "$raw.err"
rm -rf "$repo" "$HOME"
ck_report
