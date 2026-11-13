# ------------------------------------------------------------ oracle_fixtures
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# Holds a project's named fixtures to the //oracle arm that writes them. A fake
# reference prints the records, as `oracle bsq_fixtures` does: a path under the
# fixtures' directory, a TAB, the bytes escaped the way printf %b reads them.
mkdir -p "$WORK/of/tests/fixtures"
printf 'fixtures/a.map\t1.ox\\n.\\n\na.txt\tx\\n\n' > "$WORK/of/records"
printf '../escape.txt\tx\\n\n' > "$WORK/of/records_unsafe"
printf '#!/bin/sh\ncat "%s"\n' "$WORK/of/records" > "$WORK/of/oracle.sh"
printf '#!/bin/sh\ncat "%s"\n' "$WORK/of/records_unsafe" > "$WORK/of/oracle_unsafe.sh"
printf '#!/bin/sh\nexit 0\n' > "$WORK/of/oracle_empty.sh"
chmod +x "$WORK/of"/*.sh
printf '1.ox\n.\n' > "$WORK/of/tests/fixtures/a.map"
printf 'x\n' > "$WORK/of/tests/a.txt"
of_run() { _ofo=$1; shift; "$SH" "$TOOLS/oracle_fixtures.sh" --oracle "$WORK/of/$_ofo.sh" \
	--fn toy_fixtures --in-dir-of "$WORK/of/tests/a.txt" \
	--owns 'fixtures/*.map' --owns '*.txt' "$@"; }
want_green "oracle_fixtures: files the reference writes pass"   -- of_run oracle
# WHAT THE REFERENCE OWNS: a file an --owns pattern matches that no record
# names -- the next case's map and output, typed by hand -- fails, where it
# used to pass unseen because only the named files were compared; a file
# beside them that no pattern matches (the hints) is not this test's.
printf 'Which rule?\n' > "$WORK/of/tests/clues.tsv"
want_green "oracle_fixtures: ...and a file no --owns matches is not its business" -- of_run oracle
printf 'x\n' > "$WORK/of/tests/typed.txt"
printf '1.ox\n.\n' > "$WORK/of/tests/fixtures/typed.map"
want_red   "oracle_fixtures: a file it owns and does not write fails" -- of_run oracle
want_out   "oracle_fixtures: ...naming it" 'UNOWNED  fixtures/typed.map' -- of_run oracle
want_out   "oracle_fixtures: ...and each of them" 'UNOWNED  typed.txt' -- of_run oracle
rm -f "$WORK/of/tests/typed.txt" "$WORK/of/tests/fixtures/typed.map"
want_broken "oracle_fixtures: no --owns is refused" 'need at least one --owns' -- \
	"$SH" "$TOOLS/oracle_fixtures.sh" --oracle "$WORK/of/oracle.sh" --fn toy_fixtures \
	--in-dir-of "$WORK/of/tests/a.txt"
want_broken "oracle_fixtures: an --owns that matches nothing is refused" 'matches no file' -- \
	of_run oracle --owns 'fixtures/*.mpa'
# ...as the shell globs it, whose '*' never crosses a '/': '*.map' is the
# directory's own maps, of which there is none. The records were asked with a
# case pattern, where it does, so the only map record, fixtures/a.map, made it
# own something, and a hand-typed fixtures/hand.map was never UNOWNED.
want_broken "oracle_fixtures: ...and one only a deeper record matches" 'matches no file' -- \
	of_run oracle --owns '*.map'
want_broken "oracle_fixtures: an --owns out of the directory is refused" 'a pattern is relative' -- \
	of_run oracle --owns '../*.txt'
printf 'y\n' > "$WORK/of/tests/a.txt"
want_red   "oracle_fixtures: a file edited by hand fails"       -- of_run oracle
want_out   "oracle_fixtures: ...naming it and where it parts" 'DIFFERS  a.txt' -- of_run oracle
want_out   "oracle_fixtures: ...in the window every runner shows" 'got,      from byte 1: y\n' -- \
	of_run oracle
rm -f "$WORK/of/tests/fixtures/a.map"
want_out   "oracle_fixtures: a file the reference names, missing" 'MISSING  fixtures/a.map' -- of_run oracle
want_green "oracle_fixtures: --write rewrites them"             -- of_run oracle --write
want_green "oracle_fixtures: ...and they then pass"             -- of_run oracle
want_broken "oracle_fixtures: a path out of the directory is refused" 'refusing the record' -- \
	of_run oracle_unsafe --write
want_green "oracle_fixtures: ...and nothing was written there" -- test ! -e "$WORK/of/escape.txt"
want_broken "oracle_fixtures: a reference with no record is refused" 'printed no record' -- \
	of_run oracle_empty
# One that fails is refused, and what it said reaches the log through the one
# renderer, cut at ten lines: 500 lines, the first with a control byte in it.
printf '#!/bin/sh\nprintf "bad\\001byte\\n" >&2\ni=1\nwhile [ $i -lt 500 ]; do echo "oracle line $i" >&2; i=$((i+1)); done\nexit 3\n' \
	> "$WORK/of/oracle_loud.sh"
chmod +x "$WORK/of/oracle_loud.sh"
OF_CTL=$(printf '\001')
want_broken "oracle_fixtures: a reference that fails is refused, cut" '490 more line(s)' -- \
	of_run oracle_loud
want_broken "oracle_fixtures: ...a control byte in what it said rendered" 'bad\x01byte' -- \
	of_run oracle_loud
want_broken_without "oracle_fixtures: ...and never sent raw" "$OF_CTL" -- of_run oracle_loud
# A last record with no newline after it is a record: written, and counted.
mkdir -p "$WORK/of/nonl"
: > "$WORK/of/nonl/anchor"
printf 'a.txt\tx\\n\nb.txt\ty\\n' > "$WORK/of/records_nonl"
printf '#!/bin/sh\ncat "%s"\n' "$WORK/of/records_nonl" > "$WORK/of/oracle_nonl.sh"
chmod +x "$WORK/of/oracle_nonl.sh"
of_nonl() { "$SH" "$TOOLS/oracle_fixtures.sh" --oracle "$WORK/of/oracle_nonl.sh" \
	--fn toy_fixtures --in-dir-of "$WORK/of/nonl/anchor" --owns '*.txt' "$@"; }
want_out   "oracle_fixtures: a last record with no newline is written" 'wrote 2 file(s)' -- \
	of_nonl --write
# shellcheck disable=SC2016 # the script is for the inner shell to expand
want_green "oracle_fixtures: ...the last one on disk with its bytes" -- \
	"$SH" -c '[ "$(cat "$1")" = y ]' _ "$WORK/of/nonl/b.txt"
want_green "oracle_fixtures: ...and then passes" -- of_nonl

