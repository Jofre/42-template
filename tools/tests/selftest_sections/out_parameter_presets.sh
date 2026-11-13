# ------------------------------------------------------- out-parameter presets
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# An out-parameter starts at a value no row expects (finding 076's class).
#
# C 01 ex03's fixture preset its two ints to 0, a value three rows expect, so
# a ft_div_mod that stored nothing through them matched those rows: the fixture
# could not show whether it wrote them. Built here over a body that stores
# nothing at all -- a toy that answers nothing -- no line it prints may be a
# line of the expected file. Piscine Reloaded's ex11 is the same folder
# (c_twin).
printf '%s\n' 'void	ft_div_mod(int a, int b, int *div, int *mod)' '{' \
	'	(void)a;' '	(void)b;' '	(void)div;' '	(void)mod;' '}' > "$WORK/divmod_none.c"
toy_cc "$WORK/divmod_none" \
	"$ROOT/c-piscine/c-piscine-c-01/tests/ex03/test_div_mod.c" "$WORK/divmod_none.c"
"$WORK/divmod_none" > "$WORK/divmod_none.out" 2> /dev/null || : > "$WORK/divmod_none.out"
divmod_none_misses() {  # no line the body prints is an expected row
	[ -s "$WORK/divmod_none.out" ] || return 2
	! grep -qxF -f "$WORK/divmod_none.out" "$ROOT/c-piscine/c-piscine-c-01/tests/ex03/expected.txt"
}
want_green "fixture: C 01 ex03 over a body that stores nothing matches no expected row" -- \
	divmod_none_misses
want_out "fixture: ...and its rows say the pointers were untouched" \
	'0 / 5	div: untouched, mod: untouched' -- cat "$WORK/divmod_none.out"

