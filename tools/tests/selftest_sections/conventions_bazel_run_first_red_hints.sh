# ------------------------------------ conventions: bazel run, first-red hints
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A script `bazel run` starts must find its files in the workspace: under
# `bazel run` nothing sits beside $0, not even a data dependency. init.sh and
# env_drift.sh read tools/drives.sh from a variable holding the directory of
# $0, both exited 2 under `bazel run`, and every arm stayed green, because the
# arms ran them from tools/. The binary is a module's, naming the script by
# label, as a module's generate target names tools/generate.sh.
# The folder of $0 is found with CDPATH emptied (the rule after it, below),
# and a variable holding it is followed in each form that empties it:
# probe_run2.sh's. The fixtures spell `cd` as c%s, so this file holds no cd
# of $0's folder itself.
printf 'sh_binary(\n    name = "run",\n    srcs = ["//tools:probe_run.sh"],\n)\n' \
	>> "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
printf 'sh_binary(\n    name = "run2",\n    srcs = ["//tools:probe_run2.sh"],\n)\n' \
	>> "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
printf '#!/bin/sh\nset -u\n_d=${0%%/*}\n. "$_d/helper.sh"\n' \
	> "$WORK/cv/tools/probe_run.sh"
{
	printf '#!/bin/sh\nset -u\n_h=$(CDPATH=%s c%s "$(dirname "$0")" && pwd)\n. "$_h/helper2.sh"\n' "''" d
	printf '_g=$(CDPATH= c%s "$(dirname "$0")" && pwd)\n. "$_g/helper3.sh"\n' d
} > "$WORK/cv/tools/probe_run2.sh"
! st_mine || conv > "$WORK/cv.beside" 2>&1
cv_beside() { cv_saved "$WORK/cv.beside"; }
want_out "conventions: a file read only beside \$0 is reported" \
	"tools/probe_run.sh:4: helper.sh, beside \$0 and nowhere else" -- \
	cv_beside
want_out "conventions: ...through a variable set by CDPATH='' cd too" \
	"tools/probe_run2.sh:4: helper2.sh, beside \$0 and nowhere else" -- \
	cv_beside
want_out "conventions: ...or by CDPATH= cd" \
	"tools/probe_run2.sh:6: helper3.sh, beside \$0 and nowhere else" -- \
	cv_beside
rm -f "$WORK/cv.beside" "$WORK/cv/tools/probe_run2.sh"
{
	printf '#!/bin/sh\nset -u\n'
	cv_require probe_run.sh
	printf 'require dirname\n'
	printf 'WS="${BUILD_WORKSPACE_DIRECTORY:-$(CDPATH= c%s "$(dirname "$0")/.." && pwd)}"\n' d
	printf 'H="$(CDPATH=%s c%s "$(dirname "$0")" && pwd)/helper.sh"\n' "''" d
	printf '[ -f "$H" ] || H="$WS/tools/helper.sh"\n. "$H"\n'
} > "$WORK/cv/tools/probe_run.sh"
# A cd to the folder of $0 with CDPATH left as the user set it: under an
# exported CDPATH=. it prints the folder it found, and the lookup captures
# two lines. Each form a script writes it in, and the forms that empty it.
{
	printf '#!/bin/sh\nset -u\n'
	printf 'W=$(c%s "$(dirname "$0")/.." && pwd)\n' d
	printf 'V=$(c%s -P -- "${0%%/*}" && pwd -P)\n' d
	printf 'c%s "$(dirname -- "$0")" || exit 2\n' d
} > "$WORK/cv/tools/probe_cdpath.sh"
{
	printf '#!/bin/sh\nset -u\n'
	printf '# W=$(c%s "$(dirname "$0")/.." && pwd), in a comment\n' d
	printf 'W=$(CDPATH= c%s "$(dirname "$0")/.." && pwd)\n' d
	printf 'V=$(CDPATH=%s c%s -P -- "${0%%/*}" && pwd -P)\n' "''" d
	printf 'CDPATH="" c%s "$(dirname -- "$0")" || exit 2\n' d
	printf 'U=$(CDPATH=%s c%s "$(dirname "$PROBE_SELF")" && pwd)\n' "''" d
} > "$WORK/cv/tools/probe_cdpath_ok.sh"
# A variable that holds $0 is followed, in the file that sets it and in
# another (a selftest section cds to the folder of the driver's ST_SELF),
# whether it is $0 bare, quoted or a default; one that holds something
# built from $0 is not, there or elsewhere: its basename, its folder, the
# checkout found from it.
{
	printf '#!/bin/sh\nset -u\nPROBE_SELF=${PROBE_GIVEN:-$0}\nPROBE_BASE=${0##*/}\n'
	printf 'W=$(c%s "$(dirname "$PROBE_SELF")" && pwd)\n' d
	printf 'B=$(c%s "$(dirname "$PROBE_BASE")" && pwd)\n' d
	printf 'PROBE_HERE=$(dirname "$0")\nPROBE_ROOT=$(CDPATH=%s c%s "$(dirname "$0")" && pwd)\nPROBE_ME="$0"\n' "''" d
	printf 'H=$(c%s "$(dirname "$PROBE_HERE")" && pwd)\n' d
	printf 'R=$(c%s "$(dirname "$PROBE_ROOT")" && pwd)\n' d
	printf 'M=$(c%s "$(dirname "$PROBE_ME")" && pwd)\n' d
} > "$WORK/cv/tools/probe_cdpath_var.sh"
{
	printf '#!/bin/sh\nset -u\nU=$(c%s "$(dirname "${PROBE_SELF}")" && pwd)\n' d
	printf 'PROBE_ROOT=/opt/probe/root\nR=$(c%s "$(dirname "$PROBE_ROOT")" && pwd)\n' d
} > "$WORK/cv/tools/probe_cdpath_use.sh"
! st_mine || conv > "$WORK/cv.beside" 2>&1
cv_cdpath() { cv_block "$WORK/cv.beside" "a cd to the folder of \$0 keeps the user's CDPATH"; }
want_broken_none "conventions: ...and one looked for in the workspace too is not" \
	"beside \$0 and nowhere else" -- \
	cv_beside
want_out "conventions: a cd to \$0's folder that keeps CDPATH is reported" \
	"tools/probe_cdpath.sh:3: " -- \
	cv_cdpath
want_out "conventions: ...through \${0%/*} and cd -P -- too" \
	"tools/probe_cdpath.sh:4: " -- \
	cv_cdpath
want_out "conventions: ...and outside a \$(...)" \
	"tools/probe_cdpath.sh:5: " -- \
	cv_cdpath
want_broken_none "conventions: ...and one that empties CDPATH is not" \
	"tools/probe_cdpath_ok.sh" -- \
	cv_cdpath
want_out "conventions: ...through a variable that holds \$0" \
	"tools/probe_cdpath_var.sh:5: " -- \
	cv_cdpath
want_out "conventions: ...set in another file too" \
	"tools/probe_cdpath_use.sh:3: " -- \
	cv_cdpath
want_broken_none "conventions: ...never one that holds \$0's basename" \
	"tools/probe_cdpath_var.sh:6: " -- \
	cv_cdpath
want_out "conventions: ...one set to \"\$0\" is followed too" \
	"tools/probe_cdpath_var.sh:12: " -- \
	cv_cdpath
want_broken_none "conventions: ...one that holds \$0's folder is not" \
	"tools/probe_cdpath_var.sh:10: " -- \
	cv_cdpath
want_broken_none "conventions: ...nor the checkout found from it" \
	"tools/probe_cdpath_var.sh:11: " -- \
	cv_cdpath
want_broken_none "conventions: ...nor its name set to a folder in another file" \
	"tools/probe_cdpath_use.sh:5: " -- \
	cv_cdpath
rm -f "$WORK/cv.beside" "$WORK/cv/tools/probe_run.sh" "$WORK/cv/tools/probe_cdpath.sh" \
	"$WORK/cv/tools/probe_cdpath_ok.sh" "$WORK/cv/tools/probe_cdpath_var.sh" \
	"$WORK/cv/tools/probe_cdpath_use.sh"
cp "$WORK/cv/b99.orig" "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"

# First-red hints. ft_display_file shipped a member-less hint that listed the
# program's steps joined by a single "then", and the untouched stub printed it.
# An invented exercise here, in each shape the check has to tell apart: that
# form (reported); the same kind of row as a C file's fourth, keyed row, which
# a stub's first red does not reach (quiet); numbered steps in the fourth row
# of a SHELL exercise, whose rows all fire at once (reported, so the BUILD
# parse is proven too); a question that names an order without giving one
# -- "the first page", "then the author" -- (quiet); steps marked only by
# "and after that" and "and finally", which the detector once counted after
# punctuation alone (reported); and a plain statement, which the rule's "is a
# question" rules out (reported).
_cv99=$WORK/cv/c-piscine/c-piscine-c-99/tests
_cv98=$WORK/cv/c-piscine/c-piscine-c-98/tests
mkdir -p "$_cv99/ex00" "$_cv99/ex01" "$_cv99/ex02" "$_cv99/ex03" \
	"$_cv98/ex21" "$_cv98/ex05"
printf 'Fold the paper along the line, then cut along the crease.\n' \
	> "$_cv99/ex00/clues.tsv"
printf 'Fold it and after that cut it, and finally glue it: which glue holds?\n' \
	> "$_cv99/ex02/clues.tsv"
printf 'The crease goes on the outside.\n' > "$_cv99/ex03/clues.tsv"
{
	printf 'What is a crease?\tcrease\n'
	printf 'Which way does it fold?\tfold\n'
	printf 'How long is the cut?\tcut\n'
	printf 'Fold it, then cut it.\tedge\n'
} > "$_cv99/ex01/clues.tsv"
printf 'shell_exercise(num = "05", mode = "check")\n' \
	>> "$WORK/cv/c-piscine/c-piscine-c-98/BUILD.bazel"
{
	printf 'What is a crease?\tcrease\n'
	printf 'Which way does it fold?\tfold\n'
	printf 'How long is the cut?\tcut\n'
	printf '1) Fold it. 2) Cut it.\tedge\n'
} > "$_cv98/ex05/clues.tsv"
printf 'What is on the first page: the title, then the author? Where does it end?\n' \
	> "$_cv98/ex21/clues.tsv"

# cv_rows RUN CLUES: in the run saved to RUN, the FAIL line for one clue
# file and the first row reported under it, so an arm that names a reason
# also names the file that gave it.
cv_rows() { cv_saved "$1" grep -A1 -F -- "$2 has a first-red hint"; }

# The six arms below ask about one tree, so they read ONE run of it, made
# only where they run (cv5's reason, below), with its status (cv_saved):
# cv_rows_fr is cv_rows over it.
! st_mine || conv > "$WORK/cv.firstred" 2>&1
cv_firstred() { cv_saved "$WORK/cv.firstred"; }
cv_rows_fr() { cv_rows "$WORK/cv.firstred" "$1"; }

want_out "conventions: a first-red hint chained with then is reported" \
	'c-piscine/c-piscine-c-99/tests/ex00/clues.tsv has a first-red hint written as steps' -- \
	cv_firstred

want_broken_none "conventions: a keyed fourth row is out of first-red reach" \
	'c-piscine/c-piscine-c-99/tests/ex01/clues.tsv has a first-red' -- \
	cv_firstred

want_out "conventions: every row of a shell exercise's clues is checked" \
	'line 4 (numbered steps)' -- \
	cv_rows_fr c-piscine/c-piscine-c-98/tests/ex05/clues.tsv

want_broken_none "conventions: a question naming an order is not a step list" \
	'c-piscine/c-piscine-c-98/tests/ex21/clues.tsv has a first-red' -- \
	cv_firstred

want_out "conventions: \"and finally\", \"and after that\" count as steps" \
	'line 1 (2 sequencing words)' -- \
	cv_rows_fr c-piscine/c-piscine-c-99/tests/ex02/clues.tsv

want_out "conventions: a first-red statement with no question is reported" \
	'line 1 (no question)' -- \
	cv_rows_fr c-piscine/c-piscine-c-99/tests/ex03/clues.tsv
rm -f "$WORK/cv.firstred"

