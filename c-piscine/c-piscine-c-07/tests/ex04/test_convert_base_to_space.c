#include <stdio.h>
#include <stdlib.h>

char	*ft_convert_base(char *nbr, char *base_from, char *base_to);

/* A base_to holding whitespace: a case the subject leaves open. This target
 * tests one reading of it, at strict (c-07's BUILD says why), and its hint
 * says which.
 *
 * Prints "<label>\t[<result>]", the brackets so that a space at either end of
 * the result can be seen; an invalid request prints (null). The result is
 * freed before the row's newline, so a crash in free() marks this row. */
static void	test(char *label, char *nbr, char *from, char *to)
{
	char	*res;

	res = ft_convert_base(nbr, from, to);
	if (res)
		printf("%s\t[%s]", label, res);
	else
		printf("%s\t(null)", label);
	free(res);
	printf("\n");
}

int	main(void)
{
	test("space is the second symbol, negative", "-5", "0123456789", "0 ");
	test("space is the last symbol", "7", "0123456789", "01 ");
	test("zero, and the first symbol is a space", "0", "0123456789", " 1");
	return (0);
}
