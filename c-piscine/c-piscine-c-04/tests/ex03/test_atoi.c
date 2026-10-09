#include <stdio.h>

int	ft_atoi(char *str);

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases are ordered trivial -> hardest, so
 * the first failing row is the most fundamental thing to fix. */
static void	test(char *label, char *str)
{
	printf("%s\t%d\n", label, ft_atoi(str));
}

int	main(void)
{
	test("plain 42", "42");
	test("single digit 7", "7");
	test("just 0", "0");
	test("leading zeros 000123", "000123");
	test("single plus", "+42");
	test("single minus", "-42");
	test("tab then number", "\t-5");
	test("all whitespace bytes then number", " \t\n\v\f\r-123");
	test("spaces then plus then digit", "   +1");
	test("empty string", "");
	test("starts with letters", "abc");
	test("only spaces", "   ");
	test("sign but no digit", "   +a");
	test("digits then a minus", "12-3");
	test("digits then letters", "  +0042xyz");
	test("two minus signs", "  --123");
	test("many mixed signs", "++--++-456");
	test("signs then digits then junk", "   +--+1234ab567");
	test("only signs no digit", "  +-+");
	test("space after minus sign", "- 42");
	test("space after plus sign", "+ 7");
	test("INT_MIN literal", "-2147483648");
	test("INT_MAX literal", "2147483647");
	return (0);
}
