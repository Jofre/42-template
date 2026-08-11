#include <stdio.h>
#include <limits.h>

void	ft_div_mod(int a, int b, int *div, int *mod);

/* Prints "<label>\tdiv: <a/b>, mod: <a%b>" written through the two pointers. */
static void	test(char *label, int a, int b)
{
	int	d;
	int	m;

	d = 0;
	m = 0;
	ft_div_mod(a, b, &d, &m);
	printf("%s\tdiv: %d, mod: %d\n", label, d, m);
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
