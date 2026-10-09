#include <stdio.h>
#include <limits.h>

int	ft_iterative_factorial(int nb);

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases are ordered trivial -> hardest, so
 * the first failing row is the most fundamental thing to fix. */
static void	test(char *label, int nb)
{
	printf("%s\t%d\n", label, ft_iterative_factorial(nb));
}

int	main(void)
{
	test("1!", 1);
	test("2!", 2);
	test("3!", 3);
	test("4!", 4);
	test("5!", 5);
	test("0!", 0);
	test("10!", 10);
	test("12!", 12);
	test("(-1)!", -1);
	test("(-5)!", -5);
	test("INT_MIN!", INT_MIN);
	return (0);
}
