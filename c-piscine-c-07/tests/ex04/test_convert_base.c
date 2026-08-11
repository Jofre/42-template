#include <stdio.h>
#include <stdlib.h>

char	*ft_convert_base(char *nbr, char *base_from, char *base_to);

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. The conversion result is malloc'd, so we
 * print it on a single line then free it; an invalid request prints (null).
 * Cases are ordered trivial -> hardest, so the first failing row is the most
 * fundamental thing to fix. */
static void	test(char *label, char *nbr, char *from, char *to)
{
	char	*res;

	res = ft_convert_base(nbr, from, to);
	printf("%s\t%s\n", label, res ? res : "(null)");
	free(res);
}

int	main(void)
{
	test("dec to binary 42", "42", "0123456789", "01");
	test("zero to binary", "0", "0123456789", "01");
	test("leading plus 42", "+42", "0123456789", "0123456789");
	test("hex FF to decimal", "FF", "0123456789ABCDEF", "0123456789");
	test("neg dec to hex", "-42", "0123456789", "0123456789ABCDEF");
	test("binary to decimal", "101010", "01", "0123456789");
	test("lowercase hex to uppercase hex", "ff",
		"0123456789abcdef", "0123456789ABCDEF");
	test("atoi rules signs and junk", "   ---+--+42ab", "0123456789", "01");
	test("INT_MAX to hex", "2147483647", "0123456789", "0123456789ABCDEF");
	test("INT_MIN to hex", "-2147483648", "0123456789", "0123456789ABCDEF");
	test("base_to contains plus", "42", "0123456789", "bad+base");
	test("base_to duplicate char", "42", "0123456789", "aa");
	test("base_from length below two", "42", "0", "0123456789");
	test("base_to empty", "42", "0123456789", "");
	test("base_from isolated plus", "42", "01+", "0123456789");
	test("base_to isolated minus", "42", "0123456789", "01-");
	test("base_from duplicate char", "42", "00", "0123456789");
	return (0);
}
