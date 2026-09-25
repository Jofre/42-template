#include <stdio.h>
#include <limits.h>

void	ft_is_negative(int n);

/* ft_is_negative writes one char ('N'/'P') with write(); setbuf(NULL) keeps the
 * printf labels interleaved in order with that write. Prints "<label>\t<N|P>". */
static void	test(char *label, int n)
{
	printf("%s\t", label);
	ft_is_negative(n);
	printf("\n");
}

int	main(void)
{
	setbuf(stdout, NULL);
	test("0 (zero)", 0);
	test("1", 1);
	test("42", 42);
	test("-1", -1);
	test("-42", -42);
	test("INT_MAX", INT_MAX);
	test("INT_MIN", INT_MIN);
	return (0);
}
