#!/bin/sh
# fetched_needed.sh -- every shared library a fetched tool loads is fetched
# too, or named in docs/environment.md's list of what the harness borrows.
#
# WHY. The tools that decide a verdict are fetched (MODULE.bazel), and each
# names the shared libraries it needs, by soname, in its dynamic section. The
# loader looks for each on the path the wrappers give it, then in the box's
# own folders. One the fetch carries and the test stages comes from the pin;
# any other comes from the box, and on a box without it the tool does not
# start at all: the fetched clang-12 exited 127 on a release with no
# libxml2.so.2 (TO VERIFY V238), a library nothing here had ever said it
# needed, while docs/environment.md named a cc, perl and a locale (TO VERIFY
# V244). The page now lists the libraries, and this holds the list to the
# programs themselves, both ways: red on a library a program needs that is
# neither staged beside it nor listed, and red on one listed that no program
# needs any more (pinned since, or no longer named).
#
# WHAT IS READ. Each --elf, then every library it needs that its tree stages,
# then theirs: the closure through the fetch. A library the box supplies is
# never opened, because what it needs in turn depends on the box, and a check
# does not depend on the host; the page names those "what they load", outside
# the list. Staged means staged for this test: a library in the fetched
# repository that no target stages is not where any loader looks, so it is
# not counted as carried. A library is staged when a --lib folder holds it,
# or, for the file that needs it, a folder that file's RUNPATH or RPATH
# names from $ORIGIN, or when it is named by a path from $ORIGIN and the
# file is there (python3 names its libpython so, and rustc finds its
# libraries through a RUNPATH: V324). $ORIGIN is the staged file's own
# folder, folded by name and never through a link: the loader takes a
# program's through its links, so this is the stricter reading for a
# program and the loader's own for a library. A library named by any other
# path is the box's, and since the list holds sonames, never paths, it is
# named in a section of its own. The dynamic section is read by the pinned objdump
# (objdump -p), not by the pinned readelf, which loads a library the binutils
# package does not carry (MODULE.bazel, binutils_x86_64_linux_gnu).
#
# Usage:
#   fetched_needed.sh --objdump FILE --objdump-lib FILE --doc FILE
#                     (--tree NAME [--lib FILE]... --elf FILE...)...
#
#   --objdump      the pinned x86_64-linux-gnu-objdump
#   --objdump-lib  a file beside the libbfd it loads: that folder goes first on
#                  objdump's loader path
#   --doc          docs/environment.md: the sonames in backquotes between its
#                  two fetched_needed markers are the list
#   --tree NAME    a fetched repository; the --lib and --elf after it are its
#   --lib FILE     FILE's folder is one the tree's tools load from (a wrapper
#                  puts it on the loader's path), and what is staged there is
#                  a library the tree carries; a folder a RUNPATH names from
#                  $ORIGIN needs none
#   --elf FILE     a program of the tree that a layer runs
#
# Exit 0: the list and the programs agree. 1: they do not, each difference
# named. 2: nothing was checked (a file missing, objdump failing, no markers).
set -u

require() {
	for _t in "$@"; do
		command -v "$_t" > /dev/null 2>&1 && continue
		echo "fetched_needed.sh: required command '$_t' is not on PATH" >&2
		exit 2
	done
}
require awk cat cp dirname grep mktemp mv rm sort

RL_NAME=fetched_needed
case $0 in */*) RL_LIB=${0%/*}/../runner_lib.sh ;; *) RL_LIB=../runner_lib.sh ;; esac
[ -f "$RL_LIB" ] || RL_LIB=${TEST_SRCDIR:-/nonexistent}/${TEST_WORKSPACE:-_main}/tools/runner_lib.sh
[ -f "$RL_LIB" ] || { echo "fetched_needed.sh: tools/runner_lib.sh is not staged (list //tools:runner_lib.sh in the test's data)" >&2; exit 2; }
# shellcheck source=tools/runner_lib.sh
. "$RL_LIB"

OBJDUMP=""
OBJDUMP_LIB=""
DOC=""
WORK=$(mktemp -d) || { echo "fetched_needed.sh: mktemp failed" >&2; exit 2; }
rl_traps 'rm -rf "$WORK"'

need() { [ "$2" -ge 2 ] || { echo "fetched_needed.sh: $1 needs a value" >&2; exit 2; }; }
# vis WORD -- a soname or a path, as every log shows bytes.
vis() { printf '%s' "$1" | rl_vis arg; }

# Each tree's name, folders and programs go to files of its own, one line
# each: tN.name, tN.libs, tN.elfs.
n=0
while [ $# -gt 0 ]; do
	case "$1" in
		--objdump) need "$1" "$#"; OBJDUMP=$2; shift 2 ;;
		--objdump-lib) need "$1" "$#"; OBJDUMP_LIB=$2; shift 2 ;;
		--doc) need "$1" "$#"; DOC=$2; shift 2 ;;
		--tree)
			need "$1" "$#"
			n=$((n + 1))
			printf '%s\n' "$2" > "$WORK/t$n.name"
			: > "$WORK/t$n.libs"
			: > "$WORK/t$n.elfs"
			shift 2 ;;
		--lib | --elf)
			need "$1" "$#"
			[ "$n" -gt 0 ] || { echo "fetched_needed.sh: $1 before any --tree" >&2; exit 2; }
			[ -f "$2" ] || { echo "fetched_needed.sh: $1 $(vis "$2") is not a file (is it in the test's data?)" >&2; exit 2; }
			printf '%s\n' "$2" >> "$WORK/t$n.${1#--}s"
			shift 2 ;;
		*) echo "fetched_needed.sh: unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$OBJDUMP" ] && [ -n "$OBJDUMP_LIB" ] && [ -n "$DOC" ] || {
	echo "fetched_needed.sh: --objdump, --objdump-lib and --doc are required" >&2
	exit 2
}
[ -x "$OBJDUMP" ] || { echo "fetched_needed.sh: --objdump $(vis "$OBJDUMP") is not an executable file" >&2; exit 2; }
OBJDUMP_DIR=$(dirname "$OBJDUMP_LIB")
[ -d "$OBJDUMP_DIR" ] || { echo "fetched_needed.sh: --objdump-lib's folder $(vis "$OBJDUMP_DIR") does not exist" >&2; exit 2; }
[ -f "$DOC" ] || { echo "fetched_needed.sh: --doc $(vis "$DOC") is not a file" >&2; exit 2; }
[ "$n" -gt 0 ] || { echo "fetched_needed.sh: no --tree, so nothing to read" >&2; exit 2; }
i=1
while [ "$i" -le "$n" ]; do
	[ -s "$WORK/t$i.elfs" ] || { echo "fetched_needed.sh: --tree $(vis "$(cat "$WORK/t$i.name")") names no --elf" >&2; exit 2; }
	i=$((i + 1))
done

# THE LIST: every backquoted soname between the two markers, one a line. The
# markers are HTML comments, which the page does not show. A page without
# them is no list at all (exit 2); markers around no name are an empty list,
# which the programs then disagree with name by name.
awk '
	/<!-- fetched_needed:/ { inside = 1; seen++; next }
	/<!-- end fetched_needed -->/ { if (inside) closed = 1; inside = 0; next }
	inside {
		line = $0
		while (match(line, /`[^`]*`/)) {
			w = substr(line, RSTART + 1, RLENGTH - 2)
			line = substr(line, RSTART + RLENGTH)
			if (w ~ /^[A-Za-z0-9_+.-]+\.so(\.[0-9]+)*$/ && !(w in got)) { got[w] = 1; print w }
		}
	}
	END { if (seen != 1 || !closed) exit 3 }' "$DOC" > "$WORK/doc.list"
case $? in
	0) ;;
	3)
		echo "fetched_needed.sh: $(vis "$DOC") has no list between one" >&2
		echo "  '<!-- fetched_needed: ... -->' line and one '<!-- end fetched_needed -->'" >&2
		echo "  line, so there is nothing to hold the programs to. The list is the" >&2
		echo "  borrowed libraries' bullet of \"What the harness borrows from the box\"." >&2
		exit 2 ;;
	*) echo "fetched_needed.sh: could not read $(vis "$DOC")" >&2; exit 2 ;;
esac

# fold_path PATH -- PATH with its . and .. folded by name, never through a link.
fold_path() {
	printf '%s\n' "$1" | awk '{
		abs = substr($0, 1, 1) == "/"
		n = split($0, p, "/"); k = 0
		for (j = 1; j <= n; j++) {
			if (p[j] == "" || p[j] == ".") continue
			if (p[j] == ".." && k > 0 && q[k] != "..") { k--; continue }
			if (p[j] == ".." && abs) continue
			q[++k] = p[j]
		}
		out = abs ? "/" : ""
		for (j = 1; j <= k; j++) out = out (j > 1 ? "/" : "") q[j]
		print (out == "" ? "." : out)
	}'
}

# origin FILE WORD -- WORD with its leading $ORIGIN or ${ORIGIN} made FILE's
# folder, folded; nothing, and exit 1, when WORD does not start so.
origin() {
	case "$2" in
		'$ORIGIN' | '$ORIGIN/'*) fold_path "$(dirname "$1")${2#?ORIGIN}" ;;
		'${ORIGIN}' | '${ORIGIN}/'*) fold_path "$(dirname "$1")${2#??ORIGIN?}" ;;
		*) return 1 ;;
	esac
}

# needed FILE -- the sonames (or paths) FILE's dynamic section names, one a
# line, into $WORK/needed, and the folders its RUNPATH or RPATH names from
# $ORIGIN into $WORK/runpath (any other entry is a folder of the box's);
# exit 2 when objdump cannot read it.
needed() {
	if ! LD_LIBRARY_PATH="$OBJDUMP_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
		"$OBJDUMP" -p "$1" > "$WORK/objdump.out" 2> "$WORK/objdump.err"; then
		echo "fetched_needed.sh: the pinned objdump could not read $(vis "$1"):" >&2
		rl_excerpt "$WORK/objdump.err" 5 objdump-error.txt >&2
		exit 2
	fi
	awk '$1 == "NEEDED" { print $2 }' "$WORK/objdump.out" > "$WORK/needed"
	awk '$1 == "RUNPATH" || $1 == "RPATH" { n = split($2, e, ":"); for (j = 1; j <= n; j++) print e[j] }' \
		"$WORK/objdump.out" | while IFS= read -r e; do origin "$1" "$e"; done > "$WORK/runpath"
}

# THE CLOSURE, tree by tree: a round reads the files queued, and queues each
# library they need that a folder of the tree stages; a soname no folder has
# goes to borrowed.tsv as "soname<TAB>tree<TAB>file", and a path no staged
# file answers to paths.tsv the same way. A file is read once.
: > "$WORK/borrowed.tsv"
: > "$WORK/paths.tsv"
: > "$WORK/read"
i=1
while [ "$i" -le "$n" ]; do
	tree=$(cat "$WORK/t$i.name")
	cp "$WORK/t$i.elfs" "$WORK/queue"
	while [ -s "$WORK/queue" ]; do
		: > "$WORK/next"
		while IFS= read -r f; do
			grep -qxF -- "$f" "$WORK/read" && continue
			printf '%s\n' "$f" >> "$WORK/read"
			needed "$f"
			while IFS= read -r s; do
				found=""
				case "$s" in
					*/*)
						p=$(origin "$f" "$s") && [ -f "$p" ] && found=$p
						if [ -z "$found" ]; then
							printf '%s\t%s\t%s\n' "$s" "$tree" "${f##*/}" >> "$WORK/paths.tsv"
							continue
						fi ;;
					*)
						while IFS= read -r l; do
							d=$(dirname "$l")
							if [ -e "$d/$s" ]; then found="$d/$s"; break; fi
						done < "$WORK/t$i.libs"
						[ -n "$found" ] || while IFS= read -r d; do
							if [ -e "$d/$s" ]; then found="$d/$s"; break; fi
						done < "$WORK/runpath" ;;
				esac
				if [ -n "$found" ]; then
					printf '%s\n' "$found" >> "$WORK/next"
				else
					printf '%s\t%s\t%s\n' "$s" "$tree" "${f##*/}" >> "$WORK/borrowed.tsv"
				fi
			done < "$WORK/needed"
		done < "$WORK/queue"
		mv "$WORK/next" "$WORK/queue"
	done
	i=$((i + 1))
done
_read=$(awk 'END { print NR }' "$WORK/read")

# Who needs each borrowed soname, "tree: file, file; tree: file", one line a
# soname, sorted by soname: the report's right column.
awk -F '\t' '
	{
		if (!($1 in at)) { names[++k] = $1; at[$1] = "" }
		key = $1 SUBSEP $2
		if (!(key in trees)) { trees[key] = ""; order[$1] = order[$1] (order[$1] == "" ? "" : "\t") $2 }
		if (index(" " trees[key] " ", " " $3 " ") == 0) trees[key] = trees[key] (trees[key] == "" ? "" : " ") $3
	}
	END {
		for (j = 1; j <= k; j++) {
			s = names[j]; out = ""
			m = split(order[s], t, "\t")
			for (q = 1; q <= m; q++) {
				fl = trees[s SUBSEP t[q]]; gsub(/ /, ", ", fl)
				out = out (q > 1 ? "; " : "") t[q] ": " fl
			}
			print s "\t" out
		}
	}' "$WORK/borrowed.tsv" | LC_ALL=C sort > "$WORK/who.tsv"

# The two directions.
: > "$WORK/missing.tsv"
while IFS= read -r line; do
	s=${line%%"	"*}
	grep -qxF -- "$s" "$WORK/doc.list" || printf '%s\n' "$line" >> "$WORK/missing.tsv"
done < "$WORK/who.tsv"
: > "$WORK/stale"
while IFS= read -r s; do
	awk -F '\t' -v s="$s" '$1 == s { found = 1 } END { exit !found }' "$WORK/who.tsv" ||
		printf '%s\n' "$s" >> "$WORK/stale"
done < "$WORK/doc.list"

# row SONAME WHO -- one line of a report, both parts through the renderer.
row() { printf '    %-24s %s\n' "$(vis "$1")" "$(vis "$2")"; }

if [ ! -s "$WORK/missing.tsv" ] && [ ! -s "$WORK/stale" ] && [ ! -s "$WORK/paths.tsv" ]; then
	echo "fetched_needed: OK -- $_read programs and libraries of $n fetched trees read;"
	echo "  each library they load from the box is in $(vis "$DOC")'s list, and the"
	echo "  list names no other:"
	while IFS= read -r line; do row "${line%%"	"*}" "${line#*"	"}"; done < "$WORK/who.tsv"
	exit 0
fi

echo "fetched_needed: FAIL -- the libraries the fetched tools load from the box,"
echo "  and the list of them in $(vis "$DOC"), disagree ($_read programs and"
echo "  libraries of $n fetched trees read)."
if [ -s "$WORK/missing.tsv" ]; then
	echo ""
	echo "  Loaded from the box, and not in the list (the library, then who needs it):"
	while IFS= read -r line; do row "${line%%"	"*}" "${line#*"	"}"; done < "$WORK/missing.tsv"
fi
if [ -s "$WORK/stale" ]; then
	echo ""
	echo "  In the list, and no fetched tool loads it from the box:"
	while IFS= read -r s; do row "$s" ""; done < "$WORK/stale"
fi
if [ -s "$WORK/paths.tsv" ]; then
	echo ""
	echo "  Named by a path no staged file answers to (the path, then who names it):"
	LC_ALL=C sort -u "$WORK/paths.tsv" | while IFS="	" read -r s t fl; do row "$s" "$t: $fl"; done
	echo "  The list holds sonames, never paths: a library named by a path that"
	echo "  starts at \$ORIGIN is the pinned one when the target stages it where"
	echo "  that path points from the file that names it. Any other path is the"
	echo "  machine's."
fi
[ -s "$WORK/missing.tsv" ] || [ -s "$WORK/stale" ] || exit 1
echo ""
echo "  A library a fetched tool needs is the pinned one only when a package in"
echo "  MODULE.bazel carries it and the target stages it in the folder the"
echo "  tool's wrapper puts on the loader's path (the tree's :runtime). Any other"
echo "  comes from the machine, and a machine without it cannot start the tool."
echo "  So fetch and stage it, or add it to the list (\"What the harness borrows"
echo "  from the box\"), saying which tool loads it. One listed that nothing"
echo "  loads from the box any more is a requirement the page no longer has:"
echo "  take it out."
exit 1
