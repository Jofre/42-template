#include <stdio.h>
#include <limits.h>

void	ft_swap(int *a, int *b);

/* Prints "<label>\t<a> <b>" after swapping two distinct variables. */
static void	test(char *label, int a, int b)
{
	int	x;
	int	y;

	x = a;
	y = b;
	ft_swap(&x, &y);
	printf("%s\t%d %d\n", label, x, y);
}

int	main(void)
{
	int	z;

	test("11 & 22", 11, 22);
	test("-5 & 7", -5, 7);
	test("0 & 0", 0, 0);
	test("INT_MIN & INT_MAX", INT_MIN, INT_MAX);
	z = 42;
	ft_swap(&z, &z);
	printf("%s\t%d\n", "same pointer (a == b)", z);
	return (0);
}
