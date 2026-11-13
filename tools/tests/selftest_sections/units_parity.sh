# --------------------------------------------------------------- units parity
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# //tools/tests:units_parity holds the contract read as text (tools/units.awk,
# and first_red's modes over it) to the contract the macros read (:units,
# :test_units, subject.json), package by package. On toy packages written
# here: a pair that agrees is green; each way they can part is red, naming
# what parted; a check that cannot run is exit 2, never a pass.
UP=$(CDPATH='' cd "$(dirname "$ST_SELF")" && pwd)/units_parity_test.sh
UP_TOOLS=$(cd "$TOOLS" && pwd)
# up_pkg DIR -- a toy package: an exercise on one line, one spread over
# lines, a mandatory part, and the files the macros would write beside it.
up_pkg() {
	mkdir -p "$1"
	printf '%s\n' 'subject(' '    grader = "moulinette",' '    group = False,' '    exercises = {' \
		'        "00": exercise(page = 1, dir = "ex00/", files = [], allowed = None),' \
		'        "01": exercise(' '            page = 1,' '            dir = "ex01/",' '            files = [],' \
		'            allowed = None,' '        ),' '    },' '    mandatory = [' '        "00",' '    ],' \
		'    mandatory_quote = "Toy",' ')' > "$1/BUILD.bazel"
	printf 'ex00\texercise\tmandatory\tdeliverable/ex00\tfolder\t-\nex01\texercise\toptional\tdeliverable/ex01\tfolder\t-\n' > "$1/units.txt"
	printf 'ex00_output\tex00\nex01_output\tex01\n' > "$1/test_units.txt"
	printf '{"memory_graded":{}}\n' > "$1/subject.json"
	printf 'ex00_output diff_output.sh\nex01_output diff_output.sh\nex00 suite ex00\n' > "$1/layers.txt"
}
# up_run DIR [OPTION...] -- the runner on DIR's package, with the real
# units.awk and first_red.
up_run() {
	_upr=$1
	shift
	"$SH" "$UP" --units-awk "$UP_TOOLS/units.awk" --first-red "$UP_TOOLS/first_red.sh" --package "$_upr/units.txt" "$@"
}
for _u in ok folder label order req graded awk drop none empty_u empty_t unsorted short \
	flist fpart fpartbad fconcat; do up_pkg "$WORK/up/$_u"; done
# A library: ft_onemore's tests start with ft_one's name, though not with
# ft_one_, so a reading that drops the underscore files them under ft_one.
mkdir -p "$WORK/up/lib"
printf '%s\n' 'subject(' '    grader = "both",' '    group = False,' '    units = {' \
	'        "libone": unit(page = 1, files = ["Makefile"], allowed = ["malloc"],' \
	'            functions = {' '                "ft_one": [],' '                "ft_onemore": ["malloc"],' '            }),' \
	'    },' ')' > "$WORK/up/lib/BUILD.bazel"
printf 'libone\tlibrary\t-\tdeliverable\tfolder\t-\nft_one\tfunction\t-\tdeliverable\tdefines\tlibone\nft_onemore\tfunction\t-\tdeliverable\tdefines\tlibone\n' > "$WORK/up/lib/units.txt"
printf 'deliverable_files\t-\nft_one_output\tft_one\nft_onemore_output\tft_onemore\nlibone_build\tlibone\n' > "$WORK/up/lib/test_units.txt"
printf '{"units":{"libone":{"dir":null,"files":["Makefile"],"optional":[],"provided":{}}},"memory_graded":{}}\n' > "$WORK/up/lib/subject.json"
mkdir -p "$WORK/up/libmis" && cp "$WORK/up/lib/"* "$WORK/up/libmis/"
printf 'deliverable_files\t-\nft_one_output\tft_one\nft_onemore_output\tft_one\nlibone_build\tlibone\n' > "$WORK/up/libmis/test_units.txt"
# A package of units: a library and its functions, each a unit of its own,
# turned in at the root. Its targets begin with the unit's name, and
# subject.json keys its file lists by that name.
mkdir -p "$WORK/up/named"
printf '%s\n' 'subject(' '    grader = "both",' '    group = False,' '    units = {' \
	'        "libtoy": unit(page = 1, files = ["Makefile"], allowed = [],' \
	'            functions = {' '                "toy_len": [],' '                "toy_up": [],' '            }),' \
	'    },' ')' > "$WORK/up/named/BUILD.bazel"
printf 'libtoy\tlibrary\t-\tdeliverable\tfolder\t-\ntoy_len\tfunction\t-\tdeliverable\tdefines\tlibtoy\ntoy_up\tfunction\t-\tdeliverable\tdefines\tlibtoy\n' > "$WORK/up/named/units.txt"
printf 'deliverable_files\t-\nlibtoy_build\tlibtoy\ntoy_len_output\ttoy_len\ntoy_up_output\ttoy_up\n' > "$WORK/up/named/test_units.txt"
printf '{"units":{"libtoy":{"dir":null,"files":["Makefile"],"optional":[],"provided":{}}},"memory_graded":{}}\n' > "$WORK/up/named/subject.json"
mkdir -p "$WORK/up/namedf" && cp "$WORK/up/named/"* "$WORK/up/namedf/"
printf '{"units":{"libtoy":{"dir":null,"files":["Makefile","x.c"],"optional":[],"provided":{}}},"memory_graded":{}}\n' > "$WORK/up/namedf/subject.json"
mkdir -p "$WORK/up/namedd" && cp "$WORK/up/named/"* "$WORK/up/namedd/"
printf 'libtoy\tlibrary\t-\tdeliverable/libtoy\tfolder\t-\ntoy_len\tfunction\t-\tdeliverable\tdefines\tlibtoy\ntoy_up\tfunction\t-\tdeliverable\tdefines\tlibtoy\n' > "$WORK/up/namedd/units.txt"
# A project divided into two parts at the root that share their files: a
# bare make builds one, and a rule of the Makefile, its goal, the other.
# subject.json holds each part's goal, and units.awk's rows=goals reads it.
mkdir -p "$WORK/up/parts"
printf '%s\n' 'subject(' '    grader = "both",' '    group = False,' '    units = {' \
	'        "sorter": unit(page = 1, files = ["Makefile"], optional = ["*.c", "*.h"], allowed = None),' \
	'        "checker": unit(page = 2, files = ["Makefile"], optional = ["*.c", "*.h"], allowed = None,' \
	'            goal = "bonus", goal_quote = "Toy, p.2"),' \
	'    },' '    mandatory = ["sorter"],' '    mandatory_quote = "Toy",' ')' > "$WORK/up/parts/BUILD.bazel"
printf 'sorter\tpart\tmandatory\tdeliverable\tgoal\t-\nchecker\tpart\toptional\tdeliverable\tgoal\t-\n' > "$WORK/up/parts/units.txt"
printf 'checker_build\tchecker\ndeliverable_files\t-\nsorter_build\tsorter\n' > "$WORK/up/parts/test_units.txt"
printf '{"units":{"sorter":{"dir":null,"files":["Makefile"],"optional":["*.c","*.h"],"provided":{},"goal":null},"checker":{"dir":null,"files":["Makefile"],"optional":["*.c","*.h"],"provided":{},"goal":"bonus"}},"memory_graded":{}}\n' > "$WORK/up/parts/subject.json"
mkdir -p "$WORK/up/partsx" && cp "$WORK/up/parts/"* "$WORK/up/partsx/"
sed 's/"goal":"bonus"/"goal":"bonsu"/' "$WORK/up/parts/subject.json" > "$WORK/up/partsx/subject.json"
# Each mutant, one way to part.
sed 's#deliverable/ex01#deliverable/ex1#' "$WORK/up/ok/units.txt" > "$WORK/up/folder/units.txt"
printf 'ex00_output\tex00\nex01_output\tex00\n' > "$WORK/up/label/test_units.txt"
printf 'ex01\texercise\toptional\tdeliverable/ex01\tfolder\t-\nex00\texercise\tmandatory\tdeliverable/ex00\tfolder\t-\n' > "$WORK/up/order/units.txt"
printf 'ex00\texercise\toptional\tdeliverable/ex00\tfolder\t-\nex01\texercise\toptional\tdeliverable/ex01\tfolder\t-\n' > "$WORK/up/req/units.txt"
printf '{"memory_graded":{"leaks":"x","access":"y"}}\n' > "$WORK/up/graded/subject.json"
sed 's/^        "01": exercise($/        "01": _EX01,/' "$WORK/up/ok/BUILD.bazel" > "$WORK/up/awk/BUILD.bazel"
: > "$WORK/up/empty_u/units.txt"
: > "$WORK/up/empty_t/test_units.txt"
printf 'ex01_output\tex01\nex00_output\tex00\n' > "$WORK/up/unsorted/test_units.txt"
printf 'ex02_output diff_output.sh\n' >> "$WORK/up/short/layers.txt"
printf 'BEGIN { print "ex00\\texercise\\tmandatory\\tdeliverable/ex00\\tfolder\\t-"; exit 0 }\n' > "$WORK/up/drop.awk"
printf 'BEGIN { exit 1 }\n' > "$WORK/up/none.awk"
mkdir -p "$WORK/up/nowhere" && : > "$WORK/up/nowhere/units.txt"
# The file lists: subject.json's, as Starlark evaluated them, against
# units.awk's rows=files. A list it reads whole is the JSON's, in order; one
# it reads in part (an operand it cannot evaluate) holds only names the
# JSON lists.
printf '{"exercises":{"00":{"files":["x.c"],"optional":[],"provided":{}}},"memory_graded":{}}\n' > "$WORK/up/flist/subject.json"
for _u in fpart fpartbad; do
	sed 's/^\(        "00": exercise(.*\)files = \[\]/\1files = ["a.c"] + owed()/' "$WORK/up/ok/BUILD.bazel" > "$WORK/up/$_u/BUILD.bazel"
done
printf '{"exercises":{"00":{"files":["a.c","b.c"],"optional":[],"provided":{}}},"memory_graded":{}}\n' > "$WORK/up/fpart/subject.json"
printf '{"exercises":{"00":{"files":["b.c"],"optional":[],"provided":{}}},"memory_graded":{}}\n' > "$WORK/up/fpartbad/subject.json"
sed 's/^\(        "00": exercise(.*\)files = \[\]/\1files = ["a.c", "ft_" + "b.c"]/' "$WORK/up/ok/BUILD.bazel" > "$WORK/up/fconcat/BUILD.bazel"
printf '{"exercises":{"00":{"files":["a.c","ft_b.c"],"optional":[],"provided":{}}},"memory_graded":{}}\n' > "$WORK/up/fconcat/subject.json"
want_green "units parity: a package read alike as text and by the macros" -- \
	up_run "$WORK/up/ok" --layers "$WORK/up/ok/layers.txt"
want_green "units parity: ...a library, ft_one_ never claiming ft_onemore's tests" -- up_run "$WORK/up/lib"
want_green "units parity: a package of units, each test under its unit" -- up_run "$WORK/up/named"
want_red "units parity: ...and a unit's file list the macros read otherwise" -- up_run "$WORK/up/namedf"
want_out "units parity: ...and a unit's folder, named with first_red's reading" \
	'libtoy: first_red reads deliverable, :units says deliverable/libtoy' -- up_run "$WORK/up/namedd"
want_green "units parity: a project in parts, each part's goal read alike" -- up_run "$WORK/up/parts"
want_red "units parity: a part's goal the macros read otherwise" -- up_run "$WORK/up/partsx"
want_out "units parity: ...shown as the two goals" "'<' is the macros' goals" -- up_run "$WORK/up/partsx"
want_red "units parity: a unit's folder the macros read otherwise" -- up_run "$WORK/up/folder"
want_out "units parity: ...named, with first_red's reading" \
	'ex01: first_red reads deliverable/ex01, :units says deliverable/ex1' -- up_run "$WORK/up/folder"
want_red "units parity: a test filed under another unit" -- up_run "$WORK/up/label"
want_out "units parity: ...shown as the two rows" "'<' is :test_units, the macros' row" -- up_run "$WORK/up/label"
want_out "units parity: ...and a function's test under a shorter name" \
	"'<' is :test_units, the macros' row" -- up_run "$WORK/up/libmis"
want_out "units parity: units in another order than --written's" \
	"'<' is :units' exercise and part" -- up_run "$WORK/up/order"
want_out "units parity: a mandatory unit --written calls optional" \
	"'<' is :units' exercise and part" -- up_run "$WORK/up/req"
want_out "units parity: memory_graded read otherwise" "the contract says 'graded'" -- up_run "$WORK/up/graded"
want_red "units parity: a contract line units.awk cannot read" -- up_run "$WORK/up/awk"
want_out "units parity: ...is a red quoting its FILE:LINE" \
	"units.awk: $WORK/up/awk/BUILD.bazel:6:" -- up_run "$WORK/up/awk"
want_out "units parity: a units.awk that drops a unit" \
	"'<' is :units, the macros' row; '>' is units.awk's" -- \
	"$SH" "$UP" --units-awk "$WORK/up/drop.awk" --first-red "$UP_TOOLS/first_red.sh" --package "$WORK/up/ok/units.txt"
want_out "units parity: a units.awk that finds no subject(" 'finds no subject( call' -- \
	"$SH" "$UP" --units-awk "$WORK/up/none.awk" --first-red "$UP_TOOLS/first_red.sh" --package "$WORK/up/ok/units.txt"
want_out "units parity: an empty :units checks nothing" 'an empty :units checks nothing' -- up_run "$WORK/up/empty_u"
want_out "units parity: an empty :test_units checks nothing" \
	'an empty :test_units checks nothing' -- up_run "$WORK/up/empty_t"
want_out "units parity: targets out of order" 'not in order, or one is listed twice' -- up_run "$WORK/up/unsorted"
want_out "units parity: a test :layers lists and :test_units lacks" 'ex02_output' -- \
	up_run "$WORK/up/short" --layers "$WORK/up/short/layers.txt"
want_red "units parity: a file list the macros read otherwise" -- up_run "$WORK/up/flist"
want_out "units parity: ...named, with both readings" \
	'ex00 files: the macros list [x.c]; units.awk reads nothing' -- up_run "$WORK/up/flist"
want_green "units parity: a list read in part, each name it read listed" -- up_run "$WORK/up/fpart"
want_red "units parity: a list read in part holding a name the macros do not list" -- \
	up_run "$WORK/up/fpartbad"
want_out "units parity: ...named" \
	'ex00 files: read in part, and what it read holds [a.c], which the macros do not list' -- \
	up_run "$WORK/up/fpartbad"
want_green "units parity: no piece of an expression read as a file name" -- up_run "$WORK/up/fconcat"
want_broken "units parity: no --package is no pass" 'a --package at least are required' -- \
	"$SH" "$UP" --units-awk "$UP_TOOLS/units.awk" --first-red "$UP_TOOLS/first_red.sh"
want_broken "units parity: ...nor a package with no :test_units staged" 'test_units.txt is not staged' -- \
	"$SH" "$UP" --units-awk "$UP_TOOLS/units.awk" --first-red "$UP_TOOLS/first_red.sh" --package "$WORK/up/nowhere/units.txt"
# ...nor an empty one: the loop over the packages skips a blank line, and
# the run passed having checked nothing ("OK — 0 check(s)").
want_broken "units parity: an empty --package is refused" 'needs a value' -- \
	"$SH" "$UP" --units-awk "$UP_TOOLS/units.awk" --first-red "$UP_TOOLS/first_red.sh" --package ''
# ...nor an empty --layers: its loop skips a blank line too, and a run meant
# to hold a layers listing passed over a package without it.
want_broken "units parity: ...nor an empty --layers" 'needs a value' -- \
	up_run "$WORK/up/ok" --layers ''
# A --package of nothing but a newline is no empty word, and is a blank line
# of the list the loop reads: no package is checked, and the last guard
# refuses the run, which said OK having checked nothing without it.
_up_nl='
'
want_broken "units parity: a run that checked no package is refused" 'no package was checked' -- \
	"$SH" "$UP" --units-awk "$UP_TOOLS/units.awk" --first-red "$UP_TOOLS/first_red.sh" --package "$_up_nl"
# ...and a --layers of nothing but a newline: the package is checked, so
# that guard is met, but no layers listing was, and the run said OK.
want_broken "units parity: a run handed --layers that checked no listing is refused" 'no layers listing was checked' -- \
	up_run "$WORK/up/ok" --layers "$_up_nl"

