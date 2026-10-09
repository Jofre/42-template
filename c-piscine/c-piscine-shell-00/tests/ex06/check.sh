#!/bin/sh
# ex06 — git_ignore.sh lists the files git ignores in the repository it runs in.
#
# THE TERMINATOR. The listing is one path per line, each line terminated by a
# newline: the subject's `bash git_ignore.sh | cat -e` example ends EVERY entry
# (incl. the last) with a `$`, so a trailing newline is required. A shell
# `$(...)` capture silently strips that final newline, so the RAW bytes are
# captured too and the terminator asserted on them.
#
# THE NAMES, NOT THEIR ORDER. The listing is then held to a CONTROLLED fixture
# built here: the set of paths it must hold, a plain pass/fail whose expected
# value is fixture names this check created -- not the solution. The
# Moulinette compares stdout byte for byte, so it sees the order too; but the
# subject names none, and an order it does not state is a reading, which
# this repo checks at strict and never at basic (docs/design.md, "Do not let a
# layer invent a requirement"). literal.sh holds git's order (below). midLS
# (ex04) is read the same way: either direction of its date order at basic,
# one at strict.
#
# THE FIXTURE uses every ignore source a repository carries, so a script that
# reads only one of them is seen: the top-level .gitignore, a .gitignore in a
# subdirectory (its rules apply below it only), and .git/info/exclude. The
# per-user excludes file is left out, and switched off with the rest of the
# host's and the user's git configuration: it is not the repository's, and it
# differs from one machine to the next. The fixture also holds what must NOT be
# listed, under every reading: a tracked file a pattern matches (gitignore(5):
# files already tracked are not affected), a tracked file no pattern matches,
# an untracked file no pattern matches, and a top-level file matching only the
# subdirectory's pattern.
#
# A nested file is listed as the path git prints for it from the repository's
# top, sub/draft.tmp: the subject's example is git's own output, and a bare
# name cannot say which of two same-named files is meant. The directory build/,
# ignored as a whole, can be listed file by file or as the one line build/ --
# git itself prints either, and the subject does not settle it. literal.sh
# reads "files" as each file, at strict (the exercise's exNN_literal target).
#
# No execute-bit check: the subject's example runs the script through bash, which
# needs none, and the bit is required only where a subject runs the file as
# ./name (docs/reference.md, "Run contract").
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

D="${1:-git_ignore.sh}"
case "$D" in /*) ;; *) D="$PWD/$D" ;; esac
printf "  CHECK: %s\n" "$D"

ck_require "git_ignore.sh exists" test -f "$D"
# The subject: shell exercises must be executable with /bin/sh -- its example
# runs this one through bash, and the general rule still holds.
ck_sh_parses "$D"

# No configuration but the repository's own: not the system's, not the user's
# (whose core.excludesFile, or ~/.config/git/ignore, would add rules of its
# own), for the fixture and for the run alike.
GIT_CONFIG_NOSYSTEM=1
HOME=$(mktemp -d)
XDG_CONFIG_HOME="$HOME/.config"
export GIT_CONFIG_NOSYSTEM HOME XDG_CONFIG_HOME
# Nor where the repository is, or which configuration it takes, from what a
# run outside Bazel's cleared environment would inherit.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
unset GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

#   path             tracked   ignored by
#   .gitignore       yes       --            (*.log, .DS_Store, build/)
#   sub/.gitignore   yes       --            (*.tmp)
#   tracked.txt      yes       --
#   forced.log       yes       (*.log, but tracked: not ignored)
#   alpha.log        no        .gitignore
#   one.log          no        .gitignore
#   .DS_Store        no        .gitignore
#   build/a.o        no        .gitignore (build/)
#   build/b.o        no        .gitignore (build/)
#   sub/draft.tmp    no        sub/.gitignore
#   local.bak        no        .git/info/exclude
#   notes.tmp        no        -- (sub/'s *.tmp does not reach it)
#   untracked.txt    no        --
repo=$(mktemp -d)
(
	cd "$repo" || exit 1
	git init -q . || exit 1
	git config user.email tester@example.com
	git config user.name tester
	printf '*.log\n.DS_Store\nbuild/\n' > .gitignore
	mkdir -p sub build .git/info
	printf '*.tmp\n' > sub/.gitignore
	printf 'local.bak\n' >> .git/info/exclude
	for f in tracked.txt forced.log alpha.log one.log .DS_Store build/a.o \
		build/b.o sub/draft.tmp local.bak notes.tmp untracked.txt; do
		: > "$f"
	done
	git add .gitignore sub/.gitignore tracked.txt || exit 1
	git add -f forced.log || exit 1
	git commit -q -m fixture || exit 1
) > /dev/null 2>&1 || { ck "fixture repository created" false; ck_report; }

# One run, from the repository's top, two views: the RAW bytes (with any
# trailing newline) and the shell-stripped form of them.
raw=$(mktemp)
ck_run -C "$repo" "$raw" sh "$D"
out=$(cat "$raw")
got=$(printf '%s\n' "$out" | LC_ALL=C sort)

# Each source of ignore rules, one line each.
has() { printf '%s\n' "$out" | grep -qxF -- "$1"; }
ck "lists a file the top-level .gitignore ignores (one.log)" has one.log
ck "lists an ignored dotfile (.DS_Store)" has .DS_Store
ck "lists a file .git/info/exclude ignores (local.bak)" has local.bak
ck "lists a file sub/.gitignore ignores, by its path from the top (sub/draft.tmp)" \
	has sub/draft.tmp
ck "lists the ignored directory build/: as build/, or each of its files" \
	sh -c 'printf "%s\n" "$1" | grep -qx -e build/ -e build/a.o' _ "$out"

# What must not appear. An absence is only seen in output that exists: a
# script that prints nothing has not left these out, it has listed nothing.
lacks() { [ -n "$out" ] && ! has "$1"; }
ck "does NOT list a tracked file a pattern matches (forced.log)" lacks forced.log
ck "does NOT list a tracked file (tracked.txt)" lacks tracked.txt
ck "does NOT list an untracked file no rule ignores (untracked.txt)" lacks untracked.txt
ck "does NOT list a file only another directory's .gitignore matches (notes.tmp)" \
	lacks notes.tmp

# Trailing newline present: every entry (including the last) is terminated by
# a newline, as the subject's `| cat -e` shows. This is the exact-match KO
# class the `$(...)` capture above is blind to.
ck_final_newline "output ends with a newline (each entry line-terminated)" "$raw"

# The whole listing for this controlled fixture, as a set: one path per
# line, nothing else, with build/ in either of its two forms. Plain
# pass/fail — the expected value is fixture names, never the solution.
each=$(printf '%s\n' .DS_Store alpha.log build/a.o build/b.o local.bak one.log sub/draft.tmp |
	LC_ALL=C sort)
whole=$(printf '%s\n' .DS_Store alpha.log build/ local.bak one.log sub/draft.tmp | LC_ALL=C sort)
ck "lists exactly the ignored files, one path per line (build/ either way)" \
	sh -c '[ "$1" = "$2" ] || [ "$1" = "$3" ]' _ "$got" "$each" "$whole"

rm -f "$raw" "$raw.err"
rm -rf "$repo" "$HOME"
ck_report
