#include <stdio.h>
#include <limits.h>

void	ft_ultimate_div_mod(int *a, int *b);

/* *a becomes a/b and *b becomes a%b (in place). Prints "<label>\tdiv:..,mod:..". */
static void	test(char *label, int a, int b)
{
	ft_ultimate_div_mod(&a, &b);
	printf("%s\tdiv: %d, mod: %d\n", label, a, b);
}

int	main(void)
{
	test("13 / 5", 13, 5);
	test("7 / 1", 7, 1);
	test("0 / 5", 0, 5);
	test("-13 / 5 (neg dividend)", -13, 5);
	test("13 / -5 (neg divisor)", 13, -5);
	test("-13 / -5 (both neg)", -13, -5);
	test("-7 / 2", -7, 2);
	test("INT_MIN / 2", INT_MIN, 2);
	test("INT_MAX / 7", INT_MAX, 7);
	return (0);
}
