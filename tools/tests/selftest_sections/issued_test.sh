# ------------------------------------------------------------------ issued_test
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A file 42 issues that the subject turns in (Rush 02's numbers.dict) is in
# the turn-in: red at basic while it is missing, worded from the registry's
# row, and a harness error for a path the registry does not list as turned in.
mkdir -p "$WORK/it/p/ex00"
printf 'p\tthe.dict\tp/ex00/the.dict\tturn-in\t*.dict\t-\t-\tthe intranet, beside the subject\n' > "$WORK/it/reg.tsv"
printf 'p\tthe.tar\tp/the.tar\tharness\t*the.tar\t-\t-\tthe intranet\n' >> "$WORK/it/reg.tsv"
: > "$WORK/it/none.list"
printf 'p/ex00/the.dict\n' > "$WORK/it/found.list"
# From the folder the paths start in, as a test runs from its runfiles root.
_it_runner=$(cd "$TOOLS" && pwd)/issued_test.sh
it_run() { (cd "$WORK/it" && "$SH" "$_it_runner" --registry reg.tsv "$@"); }
want_red   "issued_test: a turn-in file that is missing is red" -- \
	it_run --path p/ex00/the.dict --found-list none.list
want_out   "issued_test: ...saying where to get it, from the registry" 'the intranet, beside the subject' -- \
	it_run --path p/ex00/the.dict --found-list none.list
want_out   "issued_test: ...and where it goes" '      p/ex00/the.dict' -- \
	it_run --path p/ex00/the.dict --found-list none.list
: > "$WORK/it/p/ex00/the.dict"
want_red   "issued_test: an empty one is red too" -- \
	it_run --path p/ex00/the.dict --found-list found.list
printf '0: zero\n' > "$WORK/it/p/ex00/the.dict"
want_green "issued_test: one that is there is green" -- \
	it_run --path p/ex00/the.dict --found-list found.list
want_broken "issued_test: a path the registry does not list is a harness error" 'has no row' -- \
	it_run --path p/ex01/the.dict --found-list none.list
want_broken "issued_test: ...so is a file the harness reads and never turns in" "not turn-in" -- \
	it_run --path p/the.tar --found-list none.list

