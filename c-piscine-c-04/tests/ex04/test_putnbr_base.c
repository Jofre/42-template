#include <stdio.h>

void	ft_putnbr_base(int nbr, char *base);

/* Prints "<label>\t" then lets ft_putnbr_base write() its output, then "\n".
 * setbuf(stdout, NULL) keeps the printf labels in order with the write() bytes
 * so each case stays on its own line. An invalid base prints nothing, leaving
 * the value column empty. Cases ordered trivial -> conceptually hardest. */
static void	test(char *label, int nbr, char *base)
{
	printf("%s\t", label);
	ft_putnbr_base(nbr, base);
	printf("\n");
}

int	main(void)
{
	setbuf(stdout, NULL);

	test("42 decimal", 42, "0123456789");
	test("-42 decimal", -42, "0123456789");
	test("42 binary", 42, "01");
	test("255 hex", 255, "0123456789ABCDEF");
	test("123456 custom base8", 123456, "poneygua");
	test("-123456 custom base8", -123456, "poneygua");

	test("0 decimal", 0, "0123456789");
	test("0 binary", 0, "01");
	test("0 custom base8", 0, "poneygua");

	test("base empty \"\"", 42, "");
	test("base length 1 \"a\"", 42, "a");
	test("base duplicate \"aba\"", 42, "aba");
	test("base duplicate \"00\"", 42, "00");
	test("base with plus \"ab+c\"", 42, "ab+c");
	test("base with minus \"ab-c\"", 42, "ab-c");

	test("INT_MIN decimal", -2147483648, "0123456789");
	test("INT_MIN hex", -2147483648, "0123456789ABCDEF");
	test("INT_MIN binary", -2147483648, "01");
	return (0);
}
