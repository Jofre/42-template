#!/bin/sh
# Shell 00 ex08, and Piscine Reloaded ex02, which repeats it (its BUILD call
# names this file through twin_of) — clean: a single command that DISPLAYS the
# editor backups (*~ and #*#) in the current tree and deletes them, touching
# nothing else.
#
# The subject requires two behaviours: "Displays the found files AND deletes
# them." The old check ran clean with stdout thrown away, so it only ever
# verified the deletion half — a solution that deletes but never displays, or
# one that does not display each found path on its own newline-terminated line,
# passed here yet KO'd on the byte-exact Moulinette. We now capture the RAW
# output and assert the display too.
#
# The exact set of displayed names IS checked against a CONTROLLED fixture we
# seed ourselves, via PLAIN pass/fail (the expected set is never printed, and the
# fixture names are spec-pattern examples, not the solution). Determinism is safe
# because we own the tree; find's traversal order is normalised away by comparing
# sorted basenames, so this holds on any host regardless of filesystem order.
#
# THE FIXTURE holds what every reading of the subject agrees on: the backups
# ("end with ~", "start and end with #"), an unrelated file, and the near-miss
# names that tell those two patterns from looser ones -- a name that only
# starts with #, one that only ends with #, one with ~ inside it and one that
# starts with ~. Each must survive and must not be displayed. It holds no
# DIRECTORY named like a backup: whether "all files" takes one in, the subject
# does not say, and man find, which it points to, calls a directory a file.
# regular.sh reads "files" as regular files, at strict (the exercise's
# exNN_regular target), with directories of its own.
# shellcheck source=../../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

C=${1:-clean}
printf "  CHECK: %s\n" "$C"

# Resolve an absolute path to the deliverable so it survives a cd into the sandbox.
case "$C" in
	/*) CA=$C ;;
	*)  CA=$(pwd)/$C ;;
esac

ck_require "clean file exists" test -f "$CA"
# Both subjects: shell exercises must be executable with /bin/sh.
ck_sh_parses "$CA"

# Spec: only ONE command is allowed, "no ';' or '&&'" or other chaining. Read
# here as the shell reads the file: a ';', '&&' or '||' that joins two commands
# fails, and so does a second command on a line of its own -- two lines are two
# commands under any reading of the sentence, with no operator needed. A quoted
# or backslash-escaped ';' is an argument, not an operator, and one in a
# comment is text, so both pass here. The subject's words can also be read as
# banning the ';' character outright; that reading is literal.sh's, at strict
# (the exercise's exNN_literal target), because the subject does not settle which one it means. This
# used to grep the whole file for the bytes and call any hit "sequencing".
ck_no_operator "is a single command (no ';' '&&' '||' joining two, no second command line)" "$CA" \
	';' '&&' '||' newline

# Behaviour: run clean inside an isolated tree seeded with backup + normal files,
# capturing its RAW stdout (the "display" half) to a file so the trailing-newline
# byte is preserved.
SB=$(mktemp -d)
: > "$SB/test~"
: > "$SB/#test#"
: > "$SB/normal_file"
mkdir -p "$SB/sub"
: > "$SB/sub/nested~"
# The near misses: each fails one half of a pattern.
: > "$SB/#draft"
: > "$SB/notes#"
: > "$SB/notes~old"
: > "$SB/~draft"

raw=$(mktemp)
ck_run -C "$SB" "$raw" sh "$CA"

# --- deletion half (unchanged) -------------------------------------------------
ck "deletes a ~-suffixed backup (test~)"        test ! -e "$SB/test~"
ck "deletes a #...#-wrapped backup (#test#)"    test ! -e "$SB/#test#"
ck "deletes backups in subdirectories too"      test ! -e "$SB/sub/nested~"
ck "keeps an unrelated file (normal_file)"      test -e "$SB/normal_file"
ck "keeps a file that only starts with # (#draft)" test -e "$SB/#draft"
ck "keeps a file that only ends with # (notes#)"   test -e "$SB/notes#"
ck "keeps a file with ~ inside its name, not at its end (notes~old)" test -e "$SB/notes~old"
ck "keeps a file that starts with ~ (~draft)"      test -e "$SB/~draft"
ck "leaves the clean script itself in place"    test -f "$CA"

# --- display half (NEW) --------------------------------------------------------
# Must actually display the found files: each found path on its own
# newline-terminated line, the last one included. A missing final newline is a
# real Moulinette KO that the shell-stripping $(...) capture is blind to.
ck_final_newline "displays the found files, one per line (trailing newline)" "$raw"

# Exact display set on our controlled fixture: the displayed names (basename,
# so an absolute/relative/'./'-prefixed path all normalise) must be EXACTLY the
# seeded backups — no more, no fewer, so none of the near misses either.
# Plain pass/fail; the expected set is a fixture constant and is never printed.
disp_bn=$(sed 's:.*/::' "$raw" 2>/dev/null | sort)
want_bn=$(printf '%s\n' 'test~' '#test#' 'nested~' | sort)
ck "displays exactly the found backup files, by name (nothing more, nothing less)" \
	test "$disp_bn" = "$want_bn"

# And it must never list the file it correctly left alone: asked of a display
# that exists. A clean that displays nothing has not shown it leaves
# normal_file out, and passing it here would be a PASS about output never
# printed.
ck "does not display the untouched file (normal_file)" \
	sh -c '[ -s "$1" ] && ! grep -Fq "normal_file" "$1"' _ "$raw"

rm -rf "$SB"
rm -f "$raw" "$raw.err"
ck_report
