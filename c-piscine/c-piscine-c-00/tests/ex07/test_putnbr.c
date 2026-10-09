#include <stdio.h>
#include <limits.h>

void	ft_putnbr(int nb);

/* ft_putnbr writes the digits with write(); setbuf(NULL) keeps the printf labels
 * interleaved in order. Prints "<label>\t<number>". */
static void	test(char *label, int nb)
{
	printf("%s\t", label);
	ft_putnbr(nb);
	printf("\n");
}

int	main(void)
{
	setbuf(stdout, NULL);
	test("0", 0);
	test("7", 7);
	test("10", 10);
	test("42", 42);
	test("100", 100);
	test("-1", -1);
	test("-10", -10);
	test("-42", -42);
	test("INT_MAX", INT_MAX);
	test("INT_MIN", INT_MIN);
	return (0);
}
