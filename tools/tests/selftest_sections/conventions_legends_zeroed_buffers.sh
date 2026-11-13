# ----------------------- conventions: legends, zeroed buffers, harness arrays
# shellcheck shell=sh # sourced by tools/tests/selftest.sh (THE SECTIONS), never run alone
# A differential harness's column legend (finding 058): the diff layer reads
# the "Line:" paragraph of its header, so the sentence opens a comment line of
# its own within the first 12. One fixture per shape: on the /* line
# (reported), none at all (reported), the shape itself (quiet), and the
# sentence after other words on a line of its own (reported).
# shellcheck disable=SC2154 # set in conventions_bazel_run_first_red_hints.sh
mkdir -p "$_cv99/ex40" "$_cv99/ex41" "$_cv99/ex42" "$_cv99/ex43"
printf '/* Harness for ft_x. Line: <hexA>\\t<n>. */\nint x;\n' > "$_cv99/ex40/diff_x.c"
printf '/* Harness for ft_x: reads records and reprints them. */\nint x;\n' \
	> "$_cv99/ex41/diff_x.c"
printf '/* Harness for ft_x.\n * Line: <hexA>\\t<n>\\t<returned int>. The input,\n * then the result. */\nint x;\n' \
	> "$_cv99/ex42/diff_x.c"
printf '/* Harness for ft_x.\n * Columns. Line: <hexA>\\t<n>. */\nint x;\n' \
	> "$_cv99/ex43/diff_x.c"
# Each fixture is reported or not under its own name: one run, read four ways.
! st_mine || conv > "$WORK/cv.legend" 2>&1
want_out "conventions: a Line: sentence on the /* line is reported" \
	'c-99/tests/ex40/diff_x.c: its "Line:" sentence is on the /* line' -- \
	cv_saved "$WORK/cv.legend"
want_out "conventions: a harness with no Line: sentence is reported" \
	'c-99/tests/ex41/diff_x.c: no comment line in its first 12 begins with "Line:"' -- \
	cv_saved "$WORK/cv.legend"
want_broken_none "conventions: a Line: line of its own is accepted" \
	'c-99/tests/ex42/diff_x.c' -- \
	cv_saved "$WORK/cv.legend"
want_out "conventions: a Line: sentence after other words is reported" \
	'c-99/tests/ex43/diff_x.c: its "Line:" sentence does not begin its comment line' -- \
	cv_saved "$WORK/cv.legend"
rm -f "$WORK/cv.legend"

# A c_cycles unit read off those columns: length() of a <hex...> column not
# halved (ex84, the shape of C 04 ex04's), and a halved column that is no
# hex (ex86, the shape C 07 ex03's once had), are reported; the written column
# itself (ex85) and a sum of two hex columns halved once (ex87) are not. And
# a unit read off a column the "Line:" does not name, one the reference adds
# of its own, is reported with no budget (ex89's second call, the shape C 05
# ex06's once had, $3 over a "Line:" of two) and with one (its first). The
# rule once asked only a call with a budget, and the report's closing advice
# reads every unit as a floor every answer shares. And
# a unit_expr holding a quoted word, written \" as Starlark escapes it
# (ex89's third, the shape of Libft's ft_memchr), is read whole: the rule
# once stopped at the first \", and checked nothing after it.
mkdir -p "$_cv99/ex84" "$_cv99/ex85" "$_cv99/ex86" "$_cv99/ex87" "$_cv99/ex89"
for _e in ex84 ex85; do
	printf '/* Harness for ft_x.\n * Line: <n>\\t<hexBase>\\t<what it wrote>. The int, the base, then\n * what it wrote. */\nint x;\n' \
		> "$_cv99/$_e/diff_x.c"
done
printf '/* Harness for ft_x.\n * Line: <size>\\t<hexStr0>...\\t<hexResult>. The size, then the strings. */\nint x;\n' \
	> "$_cv99/ex86/diff_x.c"
printf '/* Harness for ft_x.\n * Line: <hexA>\\t<hexB>\\t<returned int>. Two strings, then the result. */\nint x;\n' \
	> "$_cv99/ex87/diff_x.c"
cp "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel" "$WORK/cv.cyc.keep"
for _c in '84:length($2)' '85:length($3)' '86:length($1)/2' '87:(length($1)+length($2))/2'; do
	printf '\nc_cycles(\n    num = "%s",\n    fn = "ft_x",\n    oracle_fn = "x",\n    harness = "diff_x.c",\n    unit_expr = "%s",\n    unit_name = "byte",\n)\n' \
		"${_c%%:*}" "${_c#*:}"
done >> "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
printf '/* Harness for ft_x.\n * Line: <nb>\\t<returned int>. The int, then the result. */\nint x;\n' \
	> "$_cv99/ex89/diff_x.c"
for _c in '4:    budget = 20,\n' '3:'; do
	printf '\nc_cycles(\n    num = "89",\n    fn = "ft_x",\n    oracle_fn = "x",\n    harness = "diff_x.c",\n    unit_expr = "$%s",\n    unit_name = "step",\n%b)\n' \
		"${_c%%:*}" "${_c#*:}"
done >> "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
printf '\nc_cycles(\n    num = "89",\n    fn = "ft_x",\n    oracle_fn = "x",\n    harness = "diff_x.c",\n    unit_expr = "%s",\n    unit_name = "byte",\n)\n' \
	'($2 == \"0\" ? 1 : length($1)/2)' >> "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
! st_mine || conv > "$WORK/cv.cyc" 2>&1
mv "$WORK/cv.cyc.keep" "$WORK/cv/c-piscine/c-piscine-c-99/BUILD.bazel"
want_out "conventions: a unit counting a hex column whole is reported" \
	'length($2) counts <hexBase>, two hex digits a byte, and is not halved' -- cv_saved "$WORK/cv.cyc"
want_out "conventions: ...and one halving a column of no hex" \
	'length($1)/2 halves <size>, which is no hex column' -- cv_saved "$WORK/cv.cyc"
want_broken_none "conventions: ...but not a column counted as it is" \
	'c_cycles(num = "85")'"'"'s unit_expr' -- cv_saved "$WORK/cv.cyc"
want_broken_none "conventions: ...nor a sum of hex columns halved once" \
	'c_cycles(num = "87")'"'"'s unit_expr' -- cv_saved "$WORK/cv.cyc"
want_out "conventions: ...and a unit per a column the Line: does not name" \
	'unit_expr reads $3' -- cv_saved "$WORK/cv.cyc"
want_out "conventions: ...and so with a budget" \
	'unit_expr reads $4' -- cv_saved "$WORK/cv.cyc"
want_out "conventions: ...and a unit with a quoted word is read past it" \
	'length($1)/2 halves <nb>, which is no hex column' -- cv_saved "$WORK/cv.cyc"
rm -rf "$_cv99/ex84" "$_cv99/ex85" "$_cv99/ex86" "$_cv99/ex87" "$_cv99/ex89"

# A string harness's legend has a family line for the bytes above 0x7f
# (finding 061), or says why none reaches the code: one with neither
# (reported), one with the line, and one whose items only the harness reads,
# saying so in a maintainer's line (both quiet). What makes a string harness
# is that it decodes bytes with one of diffio's hex readers, whatever its
# header calls them: ex78's says "escaped bytes" and is held all the same,
# and a harness of numbers whose header names hex reads no byte (quiet).
# The legend is any diff_clues*.txt beside the harness: a readings target's
# diff_clues_readings.txt naming the family is enough (ex37, quiet), and a
# harness with no legend at all has none (ex38, reported).
mkdir -p "$_cv99/ex73" "$_cv99/ex74" "$_cv99/ex75" "$_cv99/ex76" "$_cv99/ex78" \
	"$_cv99/ex37" "$_cv99/ex38"
for _e in ex73 ex74 ex75 ex37 ex38; do
	printf '/* Harness for ft_x.\n * Line: <hexStr>\\t<n>. The string, two hex digits per byte. */\nint x;\nvoid r(char **f, size_t *n) { dio_unhex(f[0], n, 0); }\n' \
		> "$_cv99/$_e/diff_x.c"
done
printf '/* Harness for ft_y.\n * Line: <hexN>\\t<m>. Two ints, then the result. */\nint y;\n' > "$_cv99/ex76/diff_y.c"
# Past its first twelve lines, where the old rule read for the word.
{
	printf '/* Harness for ft_z.\n * Line: <s>\\t<n>. The strings, as escaped bytes.\n'
	printf ' *\n * (a header long enough that the code starts past line twelve)\n *\n *\n *\n *\n *\n *\n */\n'
	printf 'int z;\n\nvoid r(char *l, int *n) { dio_hex_list(l, n); }\n'
} > "$_cv99/ex78/diff_z.c"
printf '  One count per string.\n    * only long strings -> where the count stops\n' > "$_cv99/ex73/diff_clues.txt"
printf '  One count per string.\n    * only strings holding a byte of 0x80 or more -> how a char compares\n' \
	> "$_cv99/ex74/diff_clues.txt"
printf '# conventions: no byte family -- only the harness reads the items\n  One count per item.\n' \
	> "$_cv99/ex75/diff_clues.txt"
printf '  One sum per pair.\n' > "$_cv99/ex76/diff_clues.txt"
printf '  One count per list.\n    * only empty lists -> where the walk starts\n' > "$_cv99/ex78/diff_clues.txt"
printf '  One count per string.\n    * only long strings -> where the count stops\n' > "$_cv99/ex37/diff_clues.txt"
printf '  ex37_readings: one count per string.\n    * only strings holding a byte of 0x80 or more -> how a char compares\n' \
	> "$_cv99/ex37/diff_clues_readings.txt"
# The reader of a block exactly as long as its hex is one of diffio's too
# (ex79, reported like ex73), and a harness that decodes hex itself over
# dio_hv, the digit table those readers are built on, is reported by the
# rule after (V221: six Libft harnesses each carried such a decoder, which
# the family rule could not see); one calling a reader is not, though its
# comments name dio_hv.
mkdir -p "$_cv99/ex79" "$_cv99/ex83"
printf '/* Harness for ft_x.\n * Line: <hexBlock>\\t<n>.\n * dio_hv(), under the reader. */\nint x;\n// never dio_hv( here\nvoid r(char **f, size_t *n) { dio_unhex_exact(f[0], n); }\n' \
	> "$_cv99/ex79/diff_x.c"
printf '  One count per block.\n    * only empty blocks -> where the walk stops\n' > "$_cv99/ex79/diff_clues.txt"
printf '/* Harness for ft_w.\n * Line: <hexPair>. */\nint tv(const char *h) { return ((dio_hv(h[0]) << 4) | dio_hv(h[1])); }\nvoid tw(unsigned char *d, const char *h) {\n\t*d = dio_hv(h[0]);\n}\n' \
	> "$_cv99/ex83/diff_w.c"
printf '  One value per pair.\n    * only pairs of 0x80 or more -> how a char compares\n' > "$_cv99/ex83/diff_clues.txt"
! st_mine || conv > "$WORK/cv.bytes" 2>&1
cv_bytes() { cv_saved "$WORK/cv.bytes" grep -A6 -F "a string harness's legend names no family"; }
cv_hexown() { cv_saved "$WORK/cv.bytes" grep -A6 -F "a differential harness decodes hex with code of its own"; }
want_out "conventions: a string legend with no line for bytes above 0x7f is reported" \
	'c-99/tests/ex73/diff_x.c' -- cv_bytes
want_out "conventions: ...whatever its header calls the bytes" 'c-99/tests/ex78/diff_z.c' -- cv_bytes
want_out "conventions: ...and a string harness with no legend at all" 'c-99/tests/ex38/diff_x.c' -- cv_bytes
want_broken_none "conventions: ...not one with the line" 'c-99/tests/ex74/' -- cv_bytes
want_broken_none "conventions: ...nor one whose readings legend has it" 'c-99/tests/ex37/' -- cv_bytes
want_broken_none "conventions: ...nor one saying why no byte reaches the code" 'c-99/tests/ex75/' -- cv_bytes
want_broken_none "conventions: ...nor a harness of numbers" 'c-99/tests/ex76/' -- cv_bytes
want_out "conventions: ...and one reading a block of exactly its length is held too" \
	'c-99/tests/ex79/diff_x.c' -- cv_bytes
want_out "conventions: a harness decoding hex itself over dio_hv is reported, at its line" \
	'c-99/tests/ex83/diff_w.c:3' -- cv_hexown
want_out "conventions: ...and at a line that stores what it decodes through a pointer" \
	'c-99/tests/ex83/diff_w.c:5' -- cv_hexown
want_broken_none "conventions: ...not one calling diffio's readers" 'c-99/tests/ex7' -- cv_hexown
want_broken_none "conventions: ...nor its comments naming dio_hv" 'c-99/tests/ex79/' -- cv_hexown
rm -f "$WORK/cv.bytes"
rm -rf "$_cv99/ex79" "$_cv99/ex83"

# A differential harness that prints "untouched" for an out-parameter that
# kept its start: one starting value is one a corpus case can expect, so it
# starts from two (the wave 5 review: C 01 ex03's harness, which started at
# 0 and then at one other value). One toy per shape, read from one run: one
# preset (reported), two (quiet).
mkdir -p "$_cv99/ex62" "$_cv99/ex63"
_cv_pre_h='/* Harness for ft_x.\n * Line: <n>\t<out>. */\n#define PRESET_A 7\n'
_cv_pre_b='void ft_x(int *out);\nint main(void) { int o = PRESET_A; ft_x(&o); if (o == PRESET_A) printf("untouched"); return (0); }\n'
printf '%b' "$_cv_pre_h$_cv_pre_b" > "$_cv99/ex62/diff_x.c"
printf '%b' "$_cv_pre_h"'#define PRESET_B (-7)\n'"$_cv_pre_b" > "$_cv99/ex63/diff_x.c"
! st_mine || conv > "$WORK/cv.preset" 2>&1
cv_pre_seen() { cv_saved "$WORK/cv.preset"; }
want_out "conventions: an untouched read from one starting value is reported" \
	'c-99/tests/ex62/diff_x.c reads a result as never written ("untouched") from fewer than two starting values' -- \
	cv_pre_seen
want_broken_none "conventions: ...and one from two is not" \
	'c-99/tests/ex63/diff_x.c reads a result as never written' -- cv_pre_seen
rm -rf "$_cv99/ex62" "$_cv99/ex63" "$WORK/cv.preset"

# A readings corpus's hint file names the level its exNN_readings target sits
# at -- _RAISED's, or strict -- and above strict calls its question a
# convention (the wave 5 review: C 11 ex06's corpus moved to robust beside
# C 06 ex03's, the same question, and its hint went on saying strict). One
# toy per shape, read from one run: raised, saying so (quiet); raised, still
# saying strict and "reading" (reported twice); at strict, calling itself a
# convention (reported); at strict, saying so (quiet).
cp "$WORK/cv/tools/defs.bzl" "$WORK/cv_defs_readings.bak"
printf '_RAISED = {\n    "c-piscine/c-piscine-c-99:ex64_readings": 3,\n    "c-piscine/c-piscine-c-99:ex65_readings": 3,\n}\n' \
	>> "$WORK/cv/tools/defs.bzl"
mkdir -p "$_cv99/ex64" "$_cv99/ex65" "$_cv99/ex66" "$_cv99/ex67"
printf '  ex64_readings: every case here holds a mark.\n    * any of them -> the subject never\n      reaches one; a convention this repo chose, at robust. How is a mark read?\n' \
	> "$_cv99/ex64/diff_clues_readings.txt"
printf '  ex65_readings: every case here holds a mark.\n    * any of them -> its reading, at\n      strict. How is a mark read?\n' \
	> "$_cv99/ex65/diff_clues_readings.txt"
printf '  ex66_readings: every case here holds a mark.\n    * any of them -> a convention this repo chose, at strict. How is a mark read?\n' \
	> "$_cv99/ex66/diff_clues_readings.txt"
printf '# ex67_readings, at robust once.\nHow is a mark read? This harness reads it one way, its reading, at strict.\tmark\n' \
	> "$_cv99/ex67/clues_readings.tsv"
! st_mine || conv > "$WORK/cv.readings" 2>&1
cv_rd_seen() { cv_saved "$WORK/cv.readings"; }
want_broken_none "conventions: a raised readings hint saying its level and a convention is quiet" \
	'c-99/tests/ex64/diff_clues_readings.txt' -- cv_rd_seen
want_out "conventions: a raised readings hint that says strict is reported" \
	'c-99/tests/ex65/diff_clues_readings.txt says its target sits at strict, and ex65_readings sits at robust' -- \
	cv_rd_seen
want_out "conventions: ...and one that calls no convention" \
	'c-99/tests/ex65/diff_clues_readings.txt is the hint of ex65_readings, at robust, and does not call its question a convention' -- \
	cv_rd_seen
want_out "conventions: a convention at strict is reported" \
	'c-99/tests/ex66/diff_clues_readings.txt is the hint of ex66_readings, at strict, and calls its question a convention' -- \
	cv_rd_seen
want_broken_none "conventions: a reading at strict is quiet, its comment lines unread" \
	'c-99/tests/ex67/clues_readings.tsv says its target sits at' -- cv_rd_seen
cp "$WORK/cv_defs_readings.bak" "$WORK/cv/tools/defs.bzl"
rm -rf "$_cv99/ex64" "$_cv99/ex65" "$_cv99/ex66" "$_cv99/ex67" "$WORK/cv.readings"

# A zeroed buffer handed to the function under test (finding 057): C 03's
# appenders ran on calloc'd destinations, where the byte a terminator belongs
# in is 0 before the call and a missing one never shows. One fixture per
# shape: calloc'd and handed on (reported), the same with its reason written
# above it (quiet), a struct's nodes zeroed so their links are NULL (quiet),
# and an initialised array handed to a function the harness declares (reported).
mkdir -p "$_cv99/ex46" "$_cv99/ex47" "$_cv99/ex48" "$_cv99/ex49"
cat > "$_cv99/ex46/diff_x.c" <<'CV_ZERO'
/* Harness for ft_x.
 * Line: <hexA>\t<hexOut>. */
char	*ft_x(char *dest, char *src);

int	main(void)
{
	char	*buf;

	buf = calloc(16, 1);
	ft_x(buf, "ab");
	return (0);
}
CV_ZERO
cat > "$_cv99/ex47/diff_x.c" <<'CV_ZERO_SAID'
/* Harness for ft_x.
 * Line: <hexA>\t<hexOut>. */
char	*ft_x(char *dest, char *src);

int	main(void)
{
	char	*buf;

	/* conventions: zeroed -- the toy reads it and writes nothing */
	buf = calloc(16, 1);
	ft_x(buf, "ab");
	return (0);
}
CV_ZERO_SAID
cat > "$_cv99/ex48/diff_x.c" <<'CV_NODES'
/* Harness for ft_x.
 * Line: <n>\t<size>. */
int	ft_x(t_list *begin);

int	main(void)
{
	t_list	*blk;

	blk = calloc(4, sizeof(t_list));
	ft_x(blk);
	return (0);
}
CV_NODES
cat > "$_cv99/ex49/diff_x.c" <<'CV_ARRAY'
/* Harness for x_fill.
 * Line: <n>\t<hexOut>. */
void	x_fill(char *s, int n);

int	main(void)
{
	char	out[32] = "";

	x_fill(out, 3);
	return (0);
}
CV_ARRAY
# And a comment marker inside a literal is no comment: a // in a string
# (ex68) hid the rest of its line, the buffer the call hands on with it,
# and a /* in one (ex69) every line after it, to the next */ (both quiet
# before).
mkdir -p "$_cv99/ex68" "$_cv99/ex69"
cat > "$_cv99/ex68/diff_x.c" <<'CV_ZERO_SLASH'
/* Harness for ft_x.
 * Line: <hexA>\t<hexOut>. */
char	*ft_x(char *src, char *dest);

int	main(void)
{
	char	*buf;

	buf = calloc(16, 1);
	ft_x("a//b", buf);
	return (0);
}
CV_ZERO_SLASH
cat > "$_cv99/ex69/diff_x.c" <<'CV_ZERO_STAR'
/* Harness for ft_x.
 * Line: <hexA>\t<hexOut>. */
char	*ft_x(char *dest, char *src);

int	main(void)
{
	char	*buf;

	printf("/*");
	buf = calloc(16, 1);
	ft_x(buf, "ab");
	return (0);
}
CV_ZERO_STAR
! st_mine || conv > "$WORK/cv.zeroed" 2>&1
want_out "conventions: a calloc'd buffer handed to ft_x is reported" \
	'line 9: buf (calloc) reaches ft_x() on line 10' -- \
	cv_saved "$WORK/cv.zeroed"
want_broken_none "conventions: ...unless its reason is written above it" \
	'c-99/tests/ex47/diff_x.c hands' -- \
	cv_saved "$WORK/cv.zeroed"
want_broken_none "conventions: zeroed nodes of a struct are not reported" \
	'c-99/tests/ex48/diff_x.c hands' -- \
	cv_saved "$WORK/cv.zeroed"
want_out "conventions: an initialised array handed to a declared function is" \
	'out (an initialised array) reaches x_fill()' -- \
	cv_saved "$WORK/cv.zeroed"
want_out "conventions: a // inside a string hides no buffer after it" \
	'line 9: buf (calloc) reaches ft_x() on line 10' -- \
	cv_block "$WORK/cv.zeroed" 'c-99/tests/ex68/diff_x.c hands'
want_out "conventions: ...nor a /* inside one the lines below it" \
	'line 10: buf (calloc) reaches ft_x() on line 11' -- \
	cv_block "$WORK/cv.zeroed" 'c-99/tests/ex69/diff_x.c hands'
rm -f "$WORK/cv.zeroed"
rm -rf "$_cv99/ex68" "$_cv99/ex69"

# ...and a buffer that starts UNSET, which a fresh page holds as zeros as
# often as not: a char buffer from malloc, or a char array never set
# (reported); an array of ints from malloc, which the harness fills whole,
# and a char buffer filled with 0xff by hand (quiet). One run, read four ways.
mkdir -p "$_cv99/ex50" "$_cv99/ex51" "$_cv99/ex52"
cat > "$_cv99/ex50/diff_x.c" <<'CV_MALLOC'
/* Harness for ft_x.
 * Line: <hexA>\t<hexOut>. */
char	*ft_x(char *dest, char *src);

int	main(void)
{
	char	*buf;

	buf = malloc(16);
	ft_x(buf, "ab");
	return (0);
}
CV_MALLOC
cat > "$_cv99/ex51/diff_x.c" <<'CV_UNSET'
/* Harness for ft_x.
 * Line: <hexA>\t<hexOut>. */
char	*ft_x(char *dest, char *src);

int	main(void)
{
	char	out[32];

	ft_x(out, "ab");
	return (0);
}
CV_UNSET
cat > "$_cv99/ex52/diff_x.c" <<'CV_FILLED'
/* Harness for ft_x.
 * Line: <hexA>\t<hexOut>. */
char	*ft_x(char *dest, int *tab);

int	main(void)
{
	char	*buf;
	int		*tab;

	tab = (int *)malloc(sizeof(int) * 4);
	buf = (char *)malloc(16);
	memset(buf, 0xff, 16);
	ft_x(buf, tab);
	return (0);
}
CV_FILLED
# Every spelling of a zero byte zeroes, and every declarator of a char
# pointer is one: a memset to 0x00, '\x00', 00 or (0) was read as a fill,
# which cleared the buffer's entry, and in `char *a, *b;` only a was a char
# pointer, so b's malloc went unseen (each quiet before). A fill with 0x10
# still fills (quiet).
_cv_zero() {  # _cv_zero EX DECL LINE... -- a harness handing ft_x what the LINEs set up
	mkdir -p "$_cv99/$1"
	{
		printf '/* Harness for ft_x.\n * Line: <hexA>\\t<hexOut>. */\n'
		printf 'char\t*ft_x(char *dest, char *src);\n\nint\tmain(void)\n{\n\t%s\n\n' "$2"
		shift 2
		for _l in "$@"; do printf '\t%s\n' "$_l"; done
		printf '\treturn (0);\n}\n'
	} > "$_cv99/$1/diff_x.c"
}
_cv_zero ex56 'char	out[32];' 'memset(out, 0x00, sizeof(out));' 'ft_x(out, "ab");'
_cv_zero ex57 'char	*buf;' 'buf = malloc(16);' "memset(buf, '\\x00', 16);" 'ft_x(buf, "ab");'
_cv_zero ex58 'char	*a, *b;' 'a = NULL;' 'b = malloc(16);' 'ft_x(b, "ab");'
_cv_zero ex59 'char	out[32];' 'memset(out, 00, 32);' 'ft_x(out, "ab");'
_cv_zero ex60 'char	out[32];' 'memset(out, (0), 32);' 'ft_x(out, "ab");'
_cv_zero ex61 'char	out[32];' 'memset(out, 0x10, 32);' 'ft_x(out, "ab");'
! st_mine || conv > "$WORK/cv.unset" 2>&1
want_out "conventions: a memset to 0x00 zeroes" \
	'c-99/tests/ex56/diff_x.c hands' -- cv_saved "$WORK/cv.unset"
want_out "conventions: ...and one to \\x00, of a malloc'd buffer" \
	'c-99/tests/ex57/diff_x.c hands' -- cv_saved "$WORK/cv.unset"
want_out "conventions: the second char pointer of a declaration is one" \
	'b (malloc, its bytes never set) reaches ft_x()' -- cv_saved "$WORK/cv.unset"
want_out "conventions: a memset to 00 zeroes" \
	'c-99/tests/ex59/diff_x.c hands' -- cv_saved "$WORK/cv.unset"
want_out "conventions: a memset to (0) zeroes" \
	'c-99/tests/ex60/diff_x.c hands' -- cv_saved "$WORK/cv.unset"
want_broken_none "conventions: ...and one to 0x10 fills" \
	'c-99/tests/ex61/diff_x.c hands' -- cv_saved "$WORK/cv.unset"
want_out "conventions: a malloc'd char buffer handed to ft_x is reported" \
	'line 9: buf (malloc, its bytes never set) reaches ft_x() on line 10' -- cv_saved "$WORK/cv.unset"
want_out "conventions: ...and a char array never set" \
	'out (an array never set) reaches ft_x()' -- cv_saved "$WORK/cv.unset"
want_broken_none "conventions: ...but not an int array, nor a buffer filled with 0xff" \
	'c-99/tests/ex52/diff_x.c hands' -- cv_saved "$WORK/cv.unset"

# A harness that reads its cases, whatever its name, sizes what it fills
# from them (finding 041): a test_*.c reading dio_line into int tab[64]
# (reported), one reading nothing (quiet: its arrays hold the cases it was
# written with), and one whose array says what bounds it (quiet).
mkdir -p "$_cv99/ex53" "$_cv99/ex54" "$_cv99/ex55"
printf '#include "diffio.h"\nint\tmain(void)\n{\n\tchar\tline[64];\n\tint\t\ttab[64];\n\n\twhile (dio_line(line, sizeof(line)))\n\t\ttab[0] = 1;\n\treturn (0);\n}\n' \
	> "$_cv99/ex53/test_x.c"
printf 'int\tmain(void)\n{\n\tint\ttab[64];\n\n\ttab[0] = 1;\n\treturn (tab[0]);\n}\n' \
	> "$_cv99/ex54/test_x.c"
printf '#include "diffio.h"\nint\tmain(void)\n{\n\tchar\tline[64];\n\t/* conventions: bounded -- two ints */\n\tchar\tlabel[32];\n\n\twhile (dio_line(line, sizeof(line)))\n\t\tlabel[0] = 0;\n\treturn (0);\n}\n' \
	> "$_cv99/ex55/test_x.c"
# ...and three shapes it read past (ex88, one harness reading fgets): a
# buffer zeroed by its initialiser, {0}, which is no constant table; an
# array of structs, whose type is two words; and an array that is a
# declaration's second declarator. A static const table beside them is quiet.
mkdir -p "$_cv99/ex88"
cat > "$_cv99/ex88/test_y.c" <<'CV_FIXED_SHAPES'
#include <stdio.h>

struct s
{
	int	n;
};

int	main(void)
{
	char	buf[64] = {0};
	struct s	cases[64];
	int	n, vals[64];
	static const int	tab[4] = {1, 2, 3, 4};

	n = 0;
	while (fgets(buf, sizeof(buf), stdin))
		vals[n++] = tab[0] + cases[0].n;
	return (0);
}
CV_FIXED_SHAPES
# ...and a reader that skips a corpus line with too few fields, read from the
# same run: a guard on dio_split's count whose `continue` is on the next line,
# one on the same line, and one that tests something else first (all
# reported, each at its line); dio_fields, which stops the harness instead,
# and a dio_split whose count nobody reads (both quiet).
mkdir -p "$_cv99/ex99"
cat > "$_cv99/ex99/diff_drop.c" <<'CV_FIELD_DROP'
/* Toy reader harness.
 * Line: <n>\t<word>\t<answer>. */
#include "diffio.h"

int	main(void)
{
	char	line[64];
	char	*f[3];

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		if (dio_split(line, f, 3) < 3) continue ;
		if (line[0] == '#' || dio_split(line, f, 3) < 3)
			continue ;
		printf("%s\t%s\n", f[0], f[1]);
	}
	return (0);
}
CV_FIELD_DROP
cat > "$_cv99/ex99/diff_kept.c" <<'CV_FIELD_KEPT'
/* Toy reader harness.
 * Line: <n>\t<word>\t<answer>. */
#include "diffio.h"

int	main(void)
{
	char	line[64];
	char	*f[3];

	while (dio_line(line, sizeof(line)))
	{
		dio_fields(line, f, 3, 2);
		dio_split(line, f, 3);
		printf("%s\t%s\n", f[0], f[1]);
	}
	return (0);
}
CV_FIELD_KEPT
# ...and a reader that makes its own capture file, read from the same run:
# a mkstemp and an fcntl(F_DUPFD) of its own (both reported, each at its
# line); one that takes the file from tools/diffio.h, naming both words in
# its comment (quiet).
cat > "$_cv99/ex99/diff_capture.c" <<'CV_CAPTURE'
/* Toy reader harness.
 * Line: <s>\t<written>. */
#include "diffio.h"

int	main(void)
{
	char	*path;
	int		fd;
	int		hi;

	path = "x";
	fd = mkstemp(path);
	hi = fcntl(fd, F_DUPFD, 3);
	return (hi);
}
CV_CAPTURE
cat > "$_cv99/ex99/diff_fdok.c" <<'CV_FDOK'
/* Toy reader harness: its file is dio_fdcap_open's, never a mkstemp( of
 * its own, nor an F_DUPFD.
 * Line: <s>\t<written>. */
#include "diffio.h"

int	main(void)
{
	t_dio_fdcap	c;

	dio_fdcap_open(&c, "diff_toy");
	dio_fdcap_close(&c);
	return (0);
}
CV_FDOK
# The same for an output fixture, whose capture is tools/fd_capture.h's: a
# test_*.c with a mkstemp and an F_DUPFD of its own (reported), one naming
# both in a comment (quiet), and a memory probe that keeps its own file, as
# Libft's mem_ft_put*_fd.c do (quiet: the rule reads no mem_*.c).
cat > "$_cv99/ex99/test_capture.c" <<'CV_FIXCAP'
/* Toy output fixture.
 * Its own capture file. */
#include <stdlib.h>

int	main(void)
{
	char	*path;
	int		fd;
	int		hi;

	path = "x";
	fd = mkstemp(path);
	hi = fcntl(fd, F_DUPFD, 3);
	return (hi);
}
CV_FIXCAP
cp "$_cv99/ex99/test_capture.c" "$_cv99/ex99/mem_capture.c"
printf '/* Toy output fixture: its file is fd_capture.h'"'"'s, never a mkstemp( of\n * its own, nor an F_DUPFD. */\nint\tmain(void)\n{\n\treturn (0);\n}\n' \
	> "$_cv99/ex99/test_fdok.c"
# And a test main that defines its helpers without static, read from the
# same run (rule 5): one whose parameters the Norm wraps onto a second line,
# and one whose brace opens on its own line (both reported, each at its
# first line); a static one, wrapped too, and a wrapped prototype (quiet).
# The rule read only a line that ended in ')', which neither of the first
# two has.
mkdir -p "$_cv99/ex39"
cat > "$_cv99/ex39/test_leak.c" <<'CV_LEAK'
#include <unistd.h>

int	helper_a(int a,
		int b)
{
	return (a + b);
}

int	helper_b(void) {
	return (0);
}

static int	helper_s(int a,
		int b)
{
	return (a - b);
}

int	helper_p(int a,
		int b);

int	main(void)
{
	return (helper_a(1, 2) + helper_b() + helper_s(2, 1));
}
CV_LEAK
# And a harness beside a prototype.h declares, itself, each function that
# file declares and it calls, read from the same run: the turn-in header
# holds what its subject asks, which may be a structure alone. One calling
# ft_x with no declaration of its own (reported), and one declaring it as
# the Norm wraps it, before the call (quiet). A diff harness is held to it
# too (ex42's diff_x.c, reported): C 13's eight leaned on the header.
# shellcheck disable=SC2154 # set in conventions_bazel_run_first_red_hints.sh
mkdir -p "$_cv98/ex40" "$_cv98/ex41" "$_cv98/ex42"
for _e in ex40 ex41 ex42; do
	printf '#ifndef PROTOTYPE_X_H\n# define PROTOTYPE_X_H\n\n# include "ft_x.h"\nint\tft_x(int a,\n\t\tint b);\n\n#endif\n' \
		> "$_cv98/$_e/prototype.h"
done
printf '#include <stdio.h>\n#include "ft_x.h"\n\nint\tmain(void)\n{\n\tprintf("%%d\\n", ft_x(1, 2));\n\treturn (0);\n}\n' \
	> "$_cv98/ex40/test_x.c"
printf '#include <stdio.h>\n#include "ft_x.h"\n\nint\tft_x(int a,\n\t\tint b);\n\nint\tmain(void)\n{\n\tprintf("%%d\\n", ft_x(1, 2));\n\treturn (0);\n}\n' \
	> "$_cv98/ex41/test_x.c"
printf '/* Toy reader harness.\n * Line: <a>\\t<b>\\t<ft_x(a, b)>. */\n#include <stdio.h>\n#include "ft_x.h"\n\nint\tmain(void)\n{\n\tprintf("%%d\\n", ft_x(1, 2));\n\treturn (0);\n}\n' \
	> "$_cv98/ex42/diff_x.c"
! st_mine || conv > "$WORK/cv.fixed" 2>&1
want_out "conventions: a harness calling its prototype.h's function undeclared is reported" \
	'c-98/tests/ex40/test_x.c uses a function its prototype.h declares, with no declaration of its own' -- \
	cv_saved "$WORK/cv.fixed"
want_out "conventions: ...naming the line of the first use" \
	'c-98/tests/ex40/test_x.c:6: ft_x' -- cv_saved "$WORK/cv.fixed"
want_broken_none "conventions: ...never one declaring it, wrapped, before the call" \
	'c-98/tests/ex41/test_x.c' -- cv_saved "$WORK/cv.fixed"
want_out "conventions: ...and a diff harness calling it undeclared is too" \
	'c-98/tests/ex42/diff_x.c:8: ft_x' -- cv_saved "$WORK/cv.fixed"
cv_leak() { cv_block "$WORK/cv.fixed" 'c-99/tests/ex39/test_leak.c defines a non-static helper'; }
want_out "conventions: a test main's helper with its parameters wrapped is reported" \
	"$(printf '3: int\thelper_a(int a,')" -- cv_leak
want_out "conventions: ...and one whose brace opens on its line" \
	"$(printf '9: int\thelper_b(void) {')" -- cv_leak
want_broken_none "conventions: ...never a static one, wrapped too" 'helper_s' -- cv_leak
want_broken_none "conventions: ...nor a wrapped prototype" 'helper_p' -- cv_leak
want_out "conventions: a test_*.c that reads its cases into a fixed array is reported" \
	'c-99/tests/ex53/test_x.c fills an array of fixed size' -- cv_saved "$WORK/cv.fixed"
want_broken_none "conventions: ...not one that reads no input" \
	'c-99/tests/ex54/test_x.c fills' -- cv_saved "$WORK/cv.fixed"
want_broken_none "conventions: ...nor an array that says what bounds it" \
	'c-99/tests/ex55/test_x.c fills' -- cv_saved "$WORK/cv.fixed"
cv_fixed_shapes() { cv_block "$WORK/cv.fixed" 'c-99/tests/ex88/test_y.c fills an array of fixed size'; }
want_out "conventions: a fixed array an initialiser of {0} zeroes is reported too" \
	"$(printf '10: \tchar\tbuf[64] = {0};')" -- cv_fixed_shapes
want_out "conventions: ...and an array of structs" \
	"$(printf '11: \tstruct s\tcases[64];')" -- cv_fixed_shapes
want_out "conventions: ...and a declaration's second declarator" \
	"$(printf '12: \tint\tn, vals[64];')" -- cv_fixed_shapes
want_broken_none "conventions: ...never a static const table" 'tab[4]' -- cv_fixed_shapes
cv_field_drop() { cv_block "$WORK/cv.fixed" 'c-99/tests/ex99/diff_drop.c skips a corpus line'; }
want_out "conventions: a reader skipping a line with too few fields is reported" \
	"$(printf '12: \t\tif (dio_split(line, f, 3) < 2)')" -- cv_field_drop
want_out "conventions: ...and one whose continue is on its line" \
	"$(printf '14: \t\tif (dio_split(line, f, 3) < 3) continue ;')" -- cv_field_drop
want_out "conventions: ...and one that tests something else first" \
	"$(printf "15: \t\tif (line[0] == '#' || dio_split(line, f, 3) < 3)")" -- cv_field_drop
want_broken_none "conventions: ...never dio_fields, nor a count nobody reads" \
	'c-99/tests/ex99/diff_kept.c' -- cv_block "$WORK/cv.fixed" 'skips a corpus line'
cv_capture() { cv_block "$WORK/cv.fixed" 'c-99/tests/ex99/diff_capture.c makes its own capture file'; }
want_out "conventions: a reader that makes its own capture file is reported" \
	"$(printf '12: \tfd = mkstemp(path);')" -- cv_capture
want_out "conventions: ...and one that keeps a descriptor with F_DUPFD" \
	"$(printf '13: \thi = fcntl(fd, F_DUPFD, 3);')" -- cv_capture
want_broken_none "conventions: ...never one that takes it from diffio.h" \
	'c-99/tests/ex99/diff_fdok.c' -- cv_block "$WORK/cv.fixed" 'makes its own capture file'
cv_fixcap() { cv_block "$WORK/cv.fixed" 'c-99/tests/ex99/test_capture.c makes its own capture file'; }
want_out "conventions: ...and an output fixture that makes its own" \
	"$(printf '12: \tfd = mkstemp(path);')" -- cv_fixcap
want_broken_none "conventions: ...never a fixture naming both in a comment" \
	'c-99/tests/ex99/test_fdok.c' -- cv_block "$WORK/cv.fixed" 'makes its own capture file'
want_broken_none "conventions: ...nor a memory probe, which keeps its own" \
	'c-99/tests/ex99/mem_capture.c' -- cv_block "$WORK/cv.fixed" 'makes its own capture file'
rm -f "$WORK/cv.unset" "$WORK/cv.fixed"
rm -rf "$_cv99/ex39" "$_cv99/ex88" "$_cv99/ex99" "$_cv98/ex40" "$_cv98/ex41" "$_cv98/ex42"

