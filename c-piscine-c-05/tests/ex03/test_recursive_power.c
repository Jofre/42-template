#include <stdio.h>
#include <limits.h>

int	ft_recursive_power(int nb, int power);

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases are ordered trivial -> hardest, so
 * the first failing row is the most fundamental thing to fix. */
static void	test(char *label, int nb, int power)
{
	printf("%s\t%d\n", label, ft_recursive_power(nb, power));
}

int	main(void)
{
	test("5^0", 5, 0);
	test("0^0", 0, 0);
	test("7^1", 7, 1);
	test("2^3", 2, 3);
	test("0^5", 0, 5);
	test("1^100", 1, 100);
	test("-2^2", -2, 2);
	test("-2^3", -2, 3);
	test("2^-3", 2, -3);
	test("5^INT_MIN", 5, INT_MIN);
	test("10^9", 10, 9);
	test("2^30", 2, 30);
	return (0);
}
