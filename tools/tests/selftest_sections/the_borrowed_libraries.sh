# --------------------------------------------------- the borrowed libraries
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# //tools/tests:fetched_needed (tools/tests/fetched_needed.sh) holds the list
# in docs/environment.md of the libraries the fetched tools load from the box
# to the tools themselves, both ways (TO VERIFY V244). Its own run reads the
# real trees, which only a change of fetch can make disagree with the page.
# Here a toy tree does: its program needs a library the tree stages
# (libst-carried), which needs one it does not (libst-deep), and a second
# library no tree carries (libst-invented, a soname no box has). Pages list
# exactly those, too few, one too many, none, or have no markers: each
# difference red and named, a page with no list refused, and the closure
# through the staged library proven by a red that only it can find.
mkdir -p "$WORK/fnd/lib" "$WORK/fnd/box"
# shellcheck disable=SC2016 # the backquotes are the page's Markdown
if st_mine; then
	printf 'int\tst_deep(void)\n{\n\treturn (5);\n}\n' > "$WORK/fnd/deep.c"
	printf 'int\tst_deep(void);\n\nint\tst_carried(void)\n{\n\treturn (st_deep());\n}\n' \
		> "$WORK/fnd/carried.c"
	printf 'int\tst_invented(void)\n{\n\treturn (7);\n}\n' > "$WORK/fnd/invented.c"
	printf 'int\tst_carried(void);\nint\tst_invented(void);\n\nint\tmain(void)\n{\n\treturn (st_carried() + st_invented());\n}\n' \
		> "$WORK/fnd/main.c"
	toy_cc "$WORK/fnd/box/libst-deep.so.5" -shared -fPIC -Wl,-soname,libst-deep.so.5 \
		"$WORK/fnd/deep.c" &&
		toy_cc "$WORK/fnd/box/libst-invented.so.7" -shared -fPIC -Wl,-soname,libst-invented.so.7 \
			"$WORK/fnd/invented.c" &&
		toy_cc "$WORK/fnd/lib/libst-carried.so.3" -shared -fPIC -Wl,-soname,libst-carried.so.3 \
			"$WORK/fnd/carried.c" \
			"$WORK/fnd/box/libst-deep.so.5" &&
		toy_cc "$WORK/fnd/prog" "$WORK/fnd/main.c" "$WORK/fnd/lib/libst-carried.so.3" \
			"$WORK/fnd/box/libst-invented.so.7" -Wl,-rpath-link,"$WORK/fnd/box"
	# fnd_page NAME LINE... -- a page whose list holds the LINEs, between
	# the two markers; a soname outside them, and a package name inside,
	# are no part of the list.
	fnd_page() {
		_fp=$1
		shift
		{
			printf '# A toy page\n\nBorrowed: `libst-outside.so.9` is named here, outside the list.\n\n'
			printf '<!-- fetched_needed: the toy list -->\n'
			for _fl in "$@"; do printf '%s\n' "$_fl"; done
			printf '<!-- end fetched_needed -->\n'
		} > "$WORK/fnd/$_fp.md"
	}
	fnd_page ok '- `libc.so.6`, `libst-deep.so.5` (`libst-pkg`) and' '  `libst-invented.so.7`.'
	fnd_page noinv '- `libc.so.6` and `libst-deep.so.5`.'
	fnd_page nodeep '- `libc.so.6` and `libst-invented.so.7`.'
	fnd_page stale '- `libc.so.6`, `libst-deep.so.5`, `libst-invented.so.7`' '  and `libst-gone.so.1`.'
	fnd_page empty
	printf '# A toy page\n\n- `libc.so.6`, `libst-deep.so.5` and `libst-invented.so.7`.\n' \
		> "$WORK/fnd/nomark.md"
	{ cat "$WORK/fnd/ok.md"; cat "$WORK/fnd/ok.md"; } > "$WORK/fnd/twice.md"
fi
fnd() {  # fnd PAGE [--no-lib] -- the check over the toy tree and PAGE
	_fdoc=$1
	shift
	if [ "${1:-}" = --no-lib ]; then
		set -- --tree toy --elf "$WORK/fnd/prog"
	else
		set -- --tree toy --lib "$WORK/fnd/lib/libst-carried.so.3" --elf "$WORK/fnd/prog"
	fi
	"$SH" "$TOOLS/tests/fetched_needed.sh" --objdump "$OBJDUMP" --objdump-lib "$NM_LIB" \
		--doc "$WORK/fnd/$_fdoc.md" "$@"
}
want_green "fetched_needed: a page listing what the toy loads" -- fnd ok
want_out   "fetched_needed: ...says who loads each, through the tree" \
	'toy: libst-carried.so.3' -- fnd ok
want_red   "fetched_needed: an invented soname not in the list" -- fnd noinv
want_out   "fetched_needed: ...is named" 'libst-invented.so.7' -- fnd noinv
want_red   "fetched_needed: one only a staged library loads" -- fnd nodeep
want_out   "fetched_needed: ...is named by its soname" 'libst-deep.so.5' -- fnd nodeep
want_out   "fetched_needed: ...with who loads it" \
	'toy: libst-carried.so.3' -- fnd nodeep
want_red   "fetched_needed: a library the tree does not stage" -- fnd ok --no-lib
want_out   "fetched_needed: ...is the one named" 'libst-carried.so.3' -- fnd ok --no-lib
want_red   "fetched_needed: a library listed that nothing loads" -- fnd stale
want_out   "fetched_needed: ...is named as listed for nothing" \
	'In the list, and no fetched tool loads it' -- fnd stale
want_red   "fetched_needed: an empty list" -- fnd empty
want_broken "fetched_needed: a page with no markers has no list" 'has no list' -- fnd nomark
want_broken "fetched_needed: a page with two lists has none" 'has no list' -- fnd twice
want_broken "fetched_needed: a file objdump cannot read is refused" \
	'could not read' -- \
	"$SH" "$TOOLS/tests/fetched_needed.sh" --objdump "$OBJDUMP" --objdump-lib "$NM_LIB" \
		--doc "$WORK/fnd/ok.md" --tree toy --elf "$WORK/fnd/main.c"
# A LIBRARY BY $ORIGIN (V324). The fetched python3 names its libpython by a
# path from $ORIGIN, and rustc finds its libraries through a RUNPATH of
# $ORIGIN/../lib, with names no --lib could keep up with. The check took the
# path for a soname the page lacked, a red no page could clear, and never
# looked in a RUNPATH folder. Toy trees: pt names its library by such a
# path, pt0 is the same program without the library, ln/bin/prog is a link
# to pt's (the folder is the staged file's, never the link's target), rp
# finds its library through a RUNPATH from $ORIGIN, and rpabs through one
# that names a folder by its absolute path, a folder of the box's. The
# loader reads ${ORIGIN} as it reads $ORIGIN: rpb finds its library through
# a RUNPATH of ${ORIGIN}/lib, and rpb0 is the same program without that
# folder. Not ${ORIGIN}/../lib: with its braces left in, that path still
# folds to the right folder, so a check that never strips them passed.
mkdir -p "$WORK/fnd/pt/bin" "$WORK/fnd/pt/lib" "$WORK/fnd/pt0/bin" "$WORK/fnd/ln/bin" \
	"$WORK/fnd/rp/bin" "$WORK/fnd/rp/lib" "$WORK/fnd/rpabs/bin" "$WORK/fnd/rpabs/lib" \
	"$WORK/fnd/rpb/bin/lib" "$WORK/fnd/rpb0/bin"
# shellcheck disable=SC2016 # $ORIGIN is the loader's, not the shell's
if st_mine; then
	printf 'int\tst_deep(void);\n\nint\tmain(void)\n{\n\treturn (st_deep());\n}\n' > "$WORK/fnd/use_deep.c"
	toy_cc "$WORK/fnd/pt/lib/libst-path.so.2" -shared -fPIC -Wl,-soname,'$ORIGIN/../lib/libst-path.so.2' \
		"$WORK/fnd/deep.c" &&
		toy_cc "$WORK/fnd/pt/bin/prog" "$WORK/fnd/use_deep.c" "$WORK/fnd/pt/lib/libst-path.so.2"
	cp "$WORK/fnd/pt/bin/prog" "$WORK/fnd/pt0/bin/prog"
	ln -s "$WORK/fnd/pt/bin/prog" "$WORK/fnd/ln/bin/prog"
	for _ft in rp rpabs; do
		toy_cc "$WORK/fnd/$_ft/lib/libst-run.so.3" -shared -fPIC -Wl,-soname,libst-run.so.3 \
			"$WORK/fnd/deep.c"
	done
	toy_cc "$WORK/fnd/rp/bin/prog" "$WORK/fnd/use_deep.c" -L"$WORK/fnd/rp/lib" -l:libst-run.so.3 \
		-Wl,--enable-new-dtags,-rpath,'$ORIGIN/../lib'
	toy_cc "$WORK/fnd/rpabs/bin/prog" "$WORK/fnd/use_deep.c" -L"$WORK/fnd/rpabs/lib" -l:libst-run.so.3 \
		-Wl,--enable-new-dtags,-rpath,"$WORK/fnd/rpabs/lib"
	toy_cc "$WORK/fnd/rpb/bin/lib/libst-run.so.3" -shared -fPIC -Wl,-soname,libst-run.so.3 \
		"$WORK/fnd/deep.c" &&
		toy_cc "$WORK/fnd/rpb/bin/prog" "$WORK/fnd/use_deep.c" -L"$WORK/fnd/rpb/bin/lib" \
			-l:libst-run.so.3 -Wl,--enable-new-dtags,-rpath,'${ORIGIN}/lib' &&
		cp "$WORK/fnd/rpb/bin/prog" "$WORK/fnd/rpb0/bin/prog"
	fnd_page libc '- `libc.so.6`.'
fi
fnd_t() {  # fnd_t TREE -- the check over toy tree TREE's bin/prog, no --lib
	"$SH" "$TOOLS/tests/fetched_needed.sh" --objdump "$OBJDUMP" --objdump-lib "$NM_LIB" \
		--doc "$WORK/fnd/libc.md" --tree toy --elf "$WORK/fnd/$1/bin/prog"
}
want_green "fetched_needed: a library named by a path from \$ORIGIN, staged there" -- fnd_t pt
want_out   "fetched_needed: ...is read" '2 programs and libraries' -- fnd_t pt
want_red   "fetched_needed: ...and not staged there" -- fnd_t pt0
want_out   "fetched_needed: ...is named by its path" 'ORIGIN/../lib/libst-path.so.2' -- fnd_t pt0
want_red   "fetched_needed: ...nor through a link to where it is" -- fnd_t ln
want_green "fetched_needed: a library in a RUNPATH folder from \$ORIGIN" -- fnd_t rp
want_red   "fetched_needed: ...but not in one named by its absolute path" -- fnd_t rpabs
want_out   "fetched_needed: ...which is named as loaded from the box" 'libst-run.so.3' -- fnd_t rpabs
want_green "fetched_needed: a library in a RUNPATH folder from \${ORIGIN}" -- fnd_t rpb
want_red   "fetched_needed: ...and not when that folder is missing" -- fnd_t rpb0

