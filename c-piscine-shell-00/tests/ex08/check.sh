#!/bin/sh
# ex08 — clean: a single command that DISPLAYS the editor backups (*~ and #*#)
# in the current tree and deletes them, touching nothing else.
#
# The subject requires two behaviours: "Displays the found files AND deletes
# them." The old check ran clean with stdout thrown away, so it only ever
# verified the deletion half — a solution that deletes but never displays (e.g.
# drops find's -print), or one whose display lacks the natural trailing newline,
# passed here yet KO'd on the byte-exact Moulinette. We now capture the RAW
# output and assert the display too.
#
# The exact set of displayed names IS checked against a CONTROLLED fixture we
# seed ourselves, via PLAIN pass/fail (the expected set is never printed, and the
# fixture names are spec-pattern examples, not the solution). Determinism is safe
# because we own the tree; find's traversal order is normalised away by comparing
# sorted basenames, so this holds on any host regardless of filesystem order.
# shellcheck source=../../../tools/shell_check.sh
. "${SHELL_CHECK_LIB:?}"

C=${1:-clean}
printf "  CHECK: %s\n" "$C"

# Resolve an absolute path to the deliverable so it survives a cd into the sandbox.
case "$C" in
	/*) CA=$C ;;
	*)  CA=$(pwd)/$C ;;
esac

ck "clean file exists" test -f "$CA"

# Spec: only ONE command is allowed (no ';', '&&', '||' command sequencing).
body=$(cat "$CA" 2>/dev/null)
ck "is a single command (no ';' '&&' '||' sequencing)" \
	sh -c 'printf "%s" "$1" | grep -Eq ";|&&|\|\|" && exit 1 || exit 0' _ "$body"

# Behaviour: run clean inside an isolated tree seeded with backup + normal files,
# capturing its RAW stdout (the "display" half) to a file so the trailing-newline
# byte is preserved.
SB=$(mktemp -d)
: > "$SB/test~"
: > "$SB/#test#"
: > "$SB/normal_file"
mkdir -p "$SB/sub"
: > "$SB/sub/nested~"

raw=$(mktemp)
( cd "$SB" && sh "$CA" ) > "$raw" 2>/dev/null

# --- deletion half (unchanged) -------------------------------------------------
ck "deletes a ~-suffixed backup (test~)"        test ! -e "$SB/test~"
ck "deletes a #...#-wrapped backup (#test#)"    test ! -e "$SB/#test#"
ck "deletes backups in subdirectories too"      test ! -e "$SB/sub/nested~"
ck "keeps an unrelated file (normal_file)"      test -e "$SB/normal_file"
ck "leaves the clean script itself in place"    test -f "$CA"

# --- display half (NEW) --------------------------------------------------------
# Must actually display the found files, line-oriented, ending with a newline —
# the natural terminator of find's -print. A missing final newline is a real
# Moulinette KO that the shell-stripping $(...) capture is blind to.
ck_final_newline "displays the found files, one per line (trailing newline)" "$raw"

# Exact display set on our controlled fixture: the displayed names (basename,
# so an absolute/relative/'./'-prefixed path all normalise) must be EXACTLY the
# seeded backups — no more, no fewer. Plain pass/fail; the expected set is a
# fixture constant and is never printed.
disp_bn=$(sed 's:.*/::' "$raw" 2>/dev/null | sort)
want_bn=$(printf '%s\n' 'test~' '#test#' 'nested~' | sort)
ck "displays exactly the found backup files, by name (nothing more, nothing less)" \
	test "$disp_bn" = "$want_bn"

# And it must never list the file it correctly left alone.
ck "does not display the untouched file (normal_file)" \
	sh -c 'grep -Fq "normal_file" "$1" && exit 1 || exit 0' _ "$raw"

rm -rf "$SB"
rm -f "$raw"
ck_report
