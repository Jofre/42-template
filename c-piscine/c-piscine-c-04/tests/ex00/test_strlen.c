#include <stdio.h>

int	ft_strlen(char *str);

/* Prints "<label>\t<length>"; tools/diff_output.sh (--labeled) puts <label> in
 * its own column. Cases ordered trivial -> conceptually harder. */
static void	test(char *label, char *s)
{
	printf("%s\t%d\n", label, ft_strlen(s));
}

int	main(void)
{
	test("\"\" (empty)", "");
	test("\"a\" (one char)", "a");
	test("\"Hello\"", "Hello");
	test("\"0\" (the digit zero)", "0");
	test("\"1234567890\"", "1234567890");
	test("\" \" (single space)", " ");
	test("\"a b c\" (spaces count)", "a b c");
	test("\"  leading and trailing  \"", "  leading and trailing  ");
	test("embedded tabs \"x\\ty\\tz\"", "x\ty\tz");
	test("long (40 chars)", "0123456789012345678901234567890123456789");
	return (0);
}
