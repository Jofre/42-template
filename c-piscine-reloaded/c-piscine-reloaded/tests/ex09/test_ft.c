#include <stdio.h>
#include <limits.h>

void	ft_ft(int *nbr);

/* Prints "<label>\t<value of n after ft_ft>". Every case must end up 42. */
static void	test(char *label, int start)
{
	int	n;

	n = start;
	ft_ft(&n);
	printf("%s\t%d\n", label, n);
}

int	main(void)
{
	test("start 0", 0);
	test("start 7", 7);
	test("already 42", 42);
	test("negative (-1)", -1);
	test("INT_MAX", INT_MAX);
	test("INT_MIN", INT_MIN);
	return (0);
}
