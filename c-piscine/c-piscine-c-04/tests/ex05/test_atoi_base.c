#include <stdio.h>

int	ft_atoi_base(char *str, char *base);

/* Prints "<label>\t<value>"; tools/diff_output.sh (--labeled) puts <label> in
 * its own column. Cases ordered trivial -> conceptually hardest, so the first
 * failing row is the most fundamental. Labels contain no TAB. */
static void	test(char *label, char *str, char *base)
{
	printf("%s\t%d\n", label, ft_atoi_base(str, base));
}

int	main(void)
{
	/* basic parse in a few bases */
	test("\"42\" base \"0123456789\"", "42", "0123456789");
	test("\"101010\" base \"01\"", "101010", "01");
	test("\"2A\" base \"0123456789ABCDEF\"", "2A", "0123456789ABCDEF");
	test("\"euoopp\" base \"poneygua\"", "euoopp", "poneygua");

	/* stop at the first char not in the base */
	test("\"1A\" base \"0123456789\"", "1A", "0123456789");
	test("\"1012\" base \"01\"", "1012", "01");

	/* signs */
	test("\"   -101010\" base \"01\"", "   -101010", "01");
	test("\"-euo\" base \"poneygua\"", "-euo", "poneygua");
	test("\"   ---+--+42ab\" base \"0123456789\"", "   ---+--+42ab", "0123456789");
	test("\"--101\" base \"01\"", "--101", "01");
	test("\"- 42\" base \"0123456789\"", "- 42", "0123456789");
	test("\"+ 7\" base \"0123456789\"", "+ 7", "0123456789");

	/* edge magnitudes */
	test("\"2147483647\" base \"0123456789\"", "2147483647", "0123456789");
	test("\"-2147483648\" base \"0123456789\"", "-2147483648", "0123456789");
	test("\"   -80000000\" base \"0123456789ABCDEF\"", "   -80000000", "0123456789ABCDEF");

	/* empty / whitespace-only / signs-only str */
	test("\"\" base \"01\"", "", "01");
	test("\"   \" base \"01\"", "   ", "01");
	test("\"  +-+\" base \"01\"", "  +-+", "01");

	/* invalid base -> 0 */
	test("\"42\" base \"\" (empty)", "42", "");
	test("\"42\" base \"a\" (len 1)", "42", "a");
	test("\"42\" base \"aba\" (dup)", "42", "aba");
	test("\"42\" base \"ab+c\" (has +)", "42", "ab+c");
	test("\"42\" base \"ab-c\" (has -)", "42", "ab-c");
	test("\"42\" base \"ab c\" (has space)", "42", "ab c");
	test("\"42\" base \"ab\\tc\" (has tab)", "42", "ab\tc");

	/* digits ARE in base but base itself is invalid -> 0 */
	test("\"101\" base \"01 \" (space in base)", "101", "01 ");
	test("\"11\" base \"01+\" (plus in base)", "11", "01+");
	test("\"11\" base \"01-\" (minus in base)", "11", "01-");

	return (0);
}
