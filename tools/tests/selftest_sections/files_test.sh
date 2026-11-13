# ------------------------------------------------------------------ files_test
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
want_green "files: exactly the required set passes" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --actual a.c
want_red   "files: a missing required file fails" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --required b.c --actual a.c
want_green "files: an extra file only warns by default" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --actual a.c --actual z.txt
want_red   "files: --strict makes an extra file fail" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --actual a.c --actual z.txt --strict
# --actual takes a NAME as given, the path from the turn-in directory, as
# --actual-list does: it kept only the last part, so a copy in a subfolder
# was taken for the required file, and two of one name were one (V316).
want_red   "files: --actual: a nested copy is not the required name" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required x --actual sub/x --strict
want_out   "files: ...and is named as an extra, folder and all" '    sub/x' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required x --actual sub/x --strict
want_out   "files: ...and beside the required file, still one" '    sub/x' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required x --actual x --actual sub/x
# A built program -- a file named as the program the exercise builds
# (--program, c_program's name or c_make's artifact) -- is what a build left
# behind, and fails even where an extra file only warns (WP-59's ruling).
want_red   "files: a built program fails even without --strict" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --actual a.c --actual toy \
		--program toy
want_out   "files: ...named as a built program" 'A BUILT PROGRAM, left in the turn-in' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --actual a.c --actual toy \
		--program toy
# What builds the program is named by its kind (RL_UNIT_KIND), and a kind no
# contract has is the harness's fault.
want_out   "files: ...named as the program an exercise builds" \
	'It is named as the program this exercise builds' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --actual a.c --actual toy \
		--program toy
want_out   "files: ...named as the program a library builds" \
	'It is named as the program this library builds' -- \
	env RL_UNIT_KIND=library "$SH" "$TOOLS/files_test.sh" --label t --required a.c \
		--actual a.c --actual toy --program toy
want_broken "files: ...and the files layer's" "files_test.sh: RL_UNIT_KIND is 'lesson'" -- \
	env RL_UNIT_KIND=lesson "$SH" "$TOOLS/files_test.sh" --label t --required a.c \
		--actual a.c --actual toy --program toy
want_green "files: ...and a file of another name still only warns" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --actual a.c --actual toy.txt \
		--program toy
# A name with a blank or a parenthesis -- what a desktop calls a copy -- is ONE
# file. It reaches this layer as a line of a name list (c_files), never as a
# label: it used to be split into "a" and "copy.c", or to fail the analysis of
# every layer that named it.
printf 'a.c\na copy.c\na (1).c\n' > "$WORK/files_names.txt"
want_red   "files: copies named with a blank and a ( are extra" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c \
		--actual-list "$WORK/files_names.txt" --strict
want_out   "files: ...each reported whole, by its real name" "'a copy.c'" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c \
		--actual-list "$WORK/files_names.txt" --strict
want_out   "files: ...the ( one too" "'a (1).c'" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c \
		--actual-list "$WORK/files_names.txt" --strict
want_broken_none "files: ...and never as its pieces" "    copy.c" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c \
		--actual-list "$WORK/files_names.txt" --strict
want_broken "files: a name list that is not there refuses" 'no name list' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --actual-list "$WORK/no-such-list"
# What the subject() contract hands it (tools/subject.bzl). A file the GRADER
# brings (--provided) is never the student's to turn in: a copy is reported
# under a heading of its own, and fails where extras fail. Where the subject
# lets files sit in subfolders, a name is a path from the turn-in directory,
# and a nested copy of a required name is not that name.
printf 'a.c\nft_putchar.c\n' > "$WORK/files_prov.txt"
want_red   "files: a copy of what the grader brings fails a strict subject" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --provided ft_putchar.c \
		--actual-list "$WORK/files_prov.txt" --strict
want_out   "files: ...under a heading saying the grader brings it" 'FILES THE GRADER BRINGS' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --provided ft_putchar.c \
		--actual-list "$WORK/files_prov.txt"
want_broken_none "files: ...and not as a file nobody asked for" 'DID NOT ASK FOR' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --provided ft_putchar.c \
		--actual-list "$WORK/files_prov.txt"
want_green "files: a grader's file the subject also allows is the student's" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --provided ft_putchar.c \
		--optional ft_putchar.c --actual-list "$WORK/files_prov.txt" --strict
# Names are compared WHOLE, as the lists give them: the contract arms of this
# runner. That a name reaching it is the file's path from the turn-in
# directory (srcs/main.c, never main.c) is tools/defs.bzl's doing, and is
# checked where it happens: //tools/tests:macro_fixtures_test's root toy,
# //tools/tests/macro_fixtures/named_prog.
printf 'Makefile\nsrcs/main.c\nincludes/bsq.h\n' > "$WORK/files_tree.txt"
want_green "files: path names match whole, as listed" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --optional srcs/main.c \
		--optional includes/bsq.h --actual-list "$WORK/files_tree.txt" --strict
want_red   "files: ...so srcs/main.c is not a required main.c" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --required main.c \
		--optional srcs/main.c --optional includes/bsq.h --actual-list "$WORK/files_tree.txt"
# A turn-in at the ROOT of deliverable/ (--root: the subject has no turn-in
# directory) whose files sit in an ex00/ folder: every one of them is "not
# asked for" and the Makefile "missing", which is true and says nothing about
# the fix. The report names it: move them up.
printf 'ex00/Makefile\nex00/bsq.c\n' > "$WORK/files_rootex.txt"
want_out   "files: a root turn-in kept in ex00/ is told to move up" \
	'git mv deliverable/ex00/* deliverable/' -- \
	"$SH" "$TOOLS/files_test.sh" --label deliverable --required Makefile --optional '*.c' \
		--actual-list "$WORK/files_rootex.txt" --root
want_broken_none "files: ...never where the subject has a turn-in directory" 'git mv' -- \
	"$SH" "$TOOLS/files_test.sh" --label deliverable --required Makefile --optional '*.c' \
		--actual-list "$WORK/files_rootex.txt"
# The PASS line claims only what it established: "exactly the files the
# subject asks for" is false the moment an allowed-but-unnamed file is there
# (finding 164), and a subject that names no file gets a row saying so
# rather than an empty table (finding 124).
want_out   "files: files allowed without a name are listed as such" \
	'every file the subject names is here, and the rest are' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --optional srcs/main.c \
		--optional includes/bsq.h --actual-list "$WORK/files_tree.txt"
want_broken_none "files: ...never as exactly the files the subject asks for" \
	'exactly the files the subject asks for' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --optional srcs/main.c \
		--optional includes/bsq.h --actual-list "$WORK/files_tree.txt"
want_out   "files: a subject that names no file says so" '(the subject names no file)' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --optional srcs/main.c \
		--optional includes/bsq.h --optional Makefile --actual-list "$WORK/files_tree.txt"
want_out   "files: ...and its PASS claims only that nothing was unasked" \
	'nothing here the subject did not allow' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --optional srcs/main.c \
		--optional includes/bsq.h --optional Makefile --actual-list "$WORK/files_tree.txt"
want_broken_none "files: ...never 'exactly the files' over a list it has not got" \
	'exactly the files the subject asks for' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --optional srcs/main.c \
		--optional includes/bsq.h --optional Makefile --actual-list "$WORK/files_tree.txt"
want_out   "files: an allowed file is listed as allowed, not required" \
	'ALLOWED, NOT REQUIRED' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --optional srcs/main.c \
		--optional includes/bsq.h --actual-list "$WORK/files_tree.txt"
# --expected: a name the subject asks for that another layer reports missing
# (a shell exercise's turn-in, which exNN_output reports with its clues). It
# is listed either way, and never fails here; the PASS says only what holds
# (finding 017: the shell files layer printed "exactly the files the subject
# asks for" over a generator that had made nothing).
want_green "files: an expected file not produced does not fail here" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --expected out.txt --strict
want_out   "files: ...but is named, as not produced" 'not produced' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --expected out.txt --strict
want_broken_none "files: ...and no PASS says the files are exactly right" \
	'exactly the files the subject asks for' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --expected out.txt --strict
want_broken_none "files: ...nor that the subject names no file" \
	'(the subject names no file)' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --expected out.txt --strict
want_out   "files: an expected file that is there is present" \
	'exactly the files the subject asks for' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --expected out.txt --actual out.txt --strict
want_red   "files: ...and an extra beside it still fails a strict subject" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --expected out.txt --actual out.txt \
		--actual oops.txt --strict
want_red   "files: ...as it does beside one not produced" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --expected out.txt --actual oops.txt --strict
# The warning about an extra file fits who grades: a person at a defense can be
# told why a file is there, a program cannot (--grader, from the contract).
want_out   "files: an extra at a defense: be ready to say why" 'Be ready to say WHY' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --grader defense \
		--actual a.c --actual z.txt
want_broken_none "files: ...never where a program grades it" 'Be ready to say WHY' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --grader moulinette \
		--actual a.c --actual z.txt
want_out   "files: ...where it says nobody can be told why" 'nobody can tell it why' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --grader moulinette \
		--actual a.c --actual z.txt
want_broken "files: a grader it does not know refuses" 'moulinette, defense or both' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c --grader peers --actual a.c
# A folder the student made for an exercise the subject does not have
# (--stray, from c_levels()): all of it is extra, under the rule for extras,
# and the report names the exercises the subject has.
printf 'toy.c\n' > "$WORK/files_stray.txt"
: > "$WORK/files_stray_empty.txt"
want_red   "files: a folder for no exercise fails a strict subject" -- \
	"$SH" "$TOOLS/files_test.sh" --label deliverable/ex09 --stray ex00,ex01 \
		--actual-list "$WORK/files_stray.txt" --strict
# --strict is about an exercise's own file list, which a subject may leave
# open; no list reaches a folder of no exercise (finding 052).
want_red   "files: ...and one where extras only warn" -- \
	"$SH" "$TOOLS/files_test.sh" --label deliverable/ex09 --stray ex00,ex01 \
		--actual-list "$WORK/files_stray.txt"
want_out   "files: ...naming the exercises the subject has" 'ex00 ex01' -- \
	"$SH" "$TOOLS/files_test.sh" --label deliverable/ex09 --stray ex00,ex01 \
		--actual-list "$WORK/files_stray.txt"
want_out   "files: an empty one is not pushed, and says so" 'git pushes no empty folder' -- \
	"$SH" "$TOOLS/files_test.sh" --label deliverable/ex09 --stray ex00,ex01 \
		--actual-list "$WORK/files_stray_empty.txt" --strict
want_green "files: ...and passes, with a warning" -- \
	"$SH" "$TOOLS/files_test.sh" --label deliverable/ex09 --stray ex00,ex01 \
		--actual-list "$WORK/files_stray_empty.txt" --strict
# THE WHOLE TURN-IN DIRECTORY (finding 102): c_files lists the tree, so a copy
# kept in a subfolder reaches this runner by its path, and is extra -- never
# the required name it shares a basename with.
printf 'a.c\nold/a.c\n' > "$WORK/files_nested.txt"
want_red   "files: a copy kept in a subfolder is extra" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c \
		--actual-list "$WORK/files_nested.txt" --strict
want_out   "files: ...named by its path, and said to be pushed" 'is pushed all the same' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c \
		--actual-list "$WORK/files_nested.txt" --strict
# The copy alone: old/a.c is in the turn-in and a.c is not, and a basename
# match would read it as present.
printf 'old/a.c\n' > "$WORK/files_nested_only.txt"
want_red   "files: ...and it does not stand for a missing required name" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c \
		--actual-list "$WORK/files_nested_only.txt"
want_out   "files: ...which is reported missing" 'MISSING' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required a.c \
		--actual-list "$WORK/files_nested_only.txt"
# THE REST OF THE PUSHED TREE (--outside, the module's deliverable_files,
# finding 052): a file at the root of deliverable/ or in a folder that is no
# exercise's fails, whatever --strict says, and names each by its path.
printf 'notes.txt\nex5/a.c\n' > "$WORK/files_outside.txt"
want_red   "files: a file outside every exercise folder fails" -- \
	"$SH" "$TOOLS/files_test.sh" --label m/deliverable --outside ex00,ex01 \
		--actual-list "$WORK/files_outside.txt"
want_out   "files: ...naming it by its path from deliverable/" '    ex5/a.c' -- \
	"$SH" "$TOOLS/files_test.sh" --label m/deliverable --outside ex00,ex01 \
		--actual-list "$WORK/files_outside.txt"
want_green "files: nothing outside the exercise folders passes" -- \
	"$SH" "$TOOLS/files_test.sh" --label m/deliverable --outside ex00,ex01 \
		--actual-list "$WORK/files_stray_empty.txt"
# WHAT THE MAKEFILE BUILDS (--built, finding 164): a .c the subject allows as
# one of "all the necessary files" and the Makefile never compiles is not
# necessary, and counts as extra. Where make could not plan ("unknown") or the
# Makefile compiles nothing yet (a stub), no .c is judged, and it says why.
printf 'Makefile\nmain.c\nsrcs/x.c\ntest.c\n' > "$WORK/files_mk.txt"
printf 'main.c\nsrcs/x.c\n' > "$WORK/files_built.txt"
printf 'main.c\nsrcs/x.c\ntest.c\n' > "$WORK/files_built_all.txt"
printf 'unknown\n' > "$WORK/files_built_unknown.txt"
: > "$WORK/files_built_none.txt"
want_red   "files: a .c the Makefile does not build fails a strict subject" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --optional main.c \
		--optional srcs/x.c --optional test.c --actual-list "$WORK/files_mk.txt" \
		--built "$WORK/files_built.txt" --strict
want_out   "files: ...under a heading of its own" 'SOURCES YOUR MAKEFILE DOES NOT BUILD' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --optional main.c \
		--optional srcs/x.c --optional test.c --actual-list "$WORK/files_mk.txt" \
		--built "$WORK/files_built.txt" --strict
# It says what the layer counts, never what the exercise takes: that only a
# source the Makefile compiles is turned in is this layer's inference.
want_out   "files: ...saying what this layer counts" \
	'This layer counts a source as turned in only when the Makefile compiles it.' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --optional main.c \
		--optional srcs/x.c --optional test.c --actual-list "$WORK/files_mk.txt" \
		--built "$WORK/files_built.txt" --strict
want_green "files: every .c built is every .c allowed" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --optional main.c \
		--optional srcs/x.c --optional test.c --actual-list "$WORK/files_mk.txt" \
		--built "$WORK/files_built_all.txt" --strict
want_broken_none "files: ...and names no source as unbuilt" 'DOES NOT BUILD' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --optional main.c \
		--optional srcs/x.c --optional test.c --actual-list "$WORK/files_mk.txt" \
		--built "$WORK/files_built_all.txt" --strict
want_green "files: a make that could not plan judges no .c" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --optional main.c \
		--optional srcs/x.c --optional test.c --actual-list "$WORK/files_mk.txt" \
		--built "$WORK/files_built_unknown.txt" --strict
want_out   "files: ...and says which layer says why" 'ex00_build says why make stopped' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --optional main.c \
		--optional srcs/x.c --optional test.c --actual-list "$WORK/files_mk.txt" \
		--built "$WORK/files_built_unknown.txt" --strict --build-target ex00_build
want_green "files: a stub Makefile that compiles nothing judges no .c" -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile --optional main.c \
		--optional srcs/x.c --optional test.c --actual-list "$WORK/files_mk.txt" \
		--built "$WORK/files_built_none.txt" --strict
want_broken "files: a build list that is not there refuses" 'no build manifest' -- \
	"$SH" "$TOOLS/files_test.sh" --label t --required Makefile \
		--actual-list "$WORK/files_mk.txt" --built "$WORK/no-such-manifest"

# A PROJECT IN PARTS, ALL AT THE ROOT: a part's own test judges the files it
# names (--extras-elsewhere), and one test judges the rest of the folder once
# for every part (--union). The folder: an invented project whose base part
# names toy.c, toy_utils.c and toy.h, whose bonus part names toy_bonus.c,
# toy_utils_bonus.c and toy_bonus.h, both naming the Makefile; and two files
# no part asks for.
FT="$TOOLS/files_test.sh"
mkdir -p "$WORK/ftparts"
printf '%s\n' Makefile toy.c toy_utils.c toy.h toy_bonus.c toy_utils_bonus.c toy_bonus.h \
	junk.c notes.txt > "$WORK/ftparts/names"
printf '%s\n' toy.c toy_utils.c > "$WORK/ftparts/built_base"
printf '%s\n' toy_bonus.c toy_utils_bonus.c > "$WORK/ftparts/built_bonus"
printf 'unknown\n' > "$WORK/ftparts/built_unknown"
# shellcheck disable=SC2120 # the arms below pass it flags, through want_red and want_broken
ft_base() {
	"$SH" "$FT" --label toy_base --actual-list "$WORK/ftparts/names" \
		--required Makefile --required toy.c --required toy_utils.c --required toy.h \
		--sibling toy_bonus.c --sibling toy_utils_bonus.c --sibling toy_bonus.h \
		--extras-elsewhere deliverable_files "$@"
}
# shellcheck disable=SC2120 # it takes flags as ft_base does, though no arm below passes one
ft_bonus() {
	"$SH" "$FT" --label toy_bonus --actual-list "$WORK/ftparts/names" \
		--required Makefile --required toy_bonus.c --required toy_utils_bonus.c \
		--required toy_bonus.h \
		--sibling toy.c --sibling toy_utils.c --sibling toy.h \
		--extras-elsewhere deliverable_files "$@"
}
ft_union() {
	"$SH" "$FT" --label deliverable --actual-list "$WORK/ftparts/names" --union \
		--sibling Makefile --sibling toy.c --sibling toy_utils.c --sibling toy.h \
		--sibling toy_bonus.c --sibling toy_utils_bonus.c --sibling toy_bonus.h "$@"
}
want_green "files_test: a part's own files are all it judges" -- ft_base
want_out "files_test: ...another part's files are that part's" 'FILES ANOTHER PART' -- ft_base
want_out "files_test: ...the rest are counted, and sent on" \
	'2 other file(s) here no part of this project asks for' -- ft_base
want_broken_none "files_test: ...never listed here" 'junk.c' -- ft_base
want_green "files_test: so is the other part's" -- ft_bonus
want_red "files_test: a part's own missing file is red" -- \
	ft_base --required toy_more.c
want_red "files_test: the folder's test judges the rest, once" -- ft_union --strict
want_out "files_test: ...naming each file no part asks for" 'notes.txt' -- ft_union --strict
want_green "files_test: ...and warns where extras only warn" -- ft_union
# Each file no part asks for is reported by one test of the three.
ft_parts_said() {
	echo "junk.c reported $({ ft_base; ft_bonus; ft_union --strict; } 2>&1 | grep -c 'junk\.c') time(s)"
}
want_out "files_test: a stray is reported once, not once a part" 'reported 1 time(s)' -- ft_parts_said
want_red "files_test: a program a part builds fails the folder's test" -- \
	ft_union --program toy_check --actual toy_check
want_red "files_test: a .c no part's build compiles is unbuilt" -- \
	ft_union --optional junk.c --strict \
		--built "$WORK/ftparts/built_base" --built "$WORK/ftparts/built_bonus"
want_out "files_test: ...asked of every part's build" "SOURCES NO PART'S BUILD COMPILES" -- \
	ft_union --optional junk.c --strict \
		--built "$WORK/ftparts/built_base" --built "$WORK/ftparts/built_bonus"
want_out "files_test: ...and none is judged while a part's is unknown" \
	'could not plan the build of every part' -- \
	ft_union --optional junk.c \
		--built "$WORK/ftparts/built_base" --built "$WORK/ftparts/built_unknown"
want_broken "files_test: a part's test refuses the folder's flags" \
	'cannot be combined with: --strict --program' -- ft_base --strict --program toy
want_broken "files_test: the folder's test requires no file" \
	'cannot be combined with: --required' -- ft_union --required toy.c
want_broken "files_test: --sibling needs one of the two" 'for --extras-elsewhere or --union' -- \
	"$SH" "$FT" --label t --actual Makefile --sibling toy.c
want_broken "files_test: --built is given once outside --union" 'is given once' -- \
	"$SH" "$FT" --label t --actual Makefile \
		--built "$WORK/ftparts/built_base" --built "$WORK/ftparts/built_bonus"

