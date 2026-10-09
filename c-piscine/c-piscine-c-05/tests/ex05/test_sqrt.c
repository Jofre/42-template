#include <stdio.h>
#include <limits.h>

int	ft_sqrt(int nb);

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases run trivial -> conceptually hardest. */
static void	test(char *label, int nb)
{
	printf("%s\t%d\n", label, ft_sqrt(nb));
}

int	main(void)
{
	test("sqrt of 0", 0);
	test("sqrt of 1", 1);
	test("sqrt of 4", 4);
	test("sqrt of 9", 9);
	test("sqrt of 16", 16);
	test("sqrt of 25", 25);
	test("sqrt of 100", 100);
	test("sqrt of 144", 144);
	test("sqrt of 2 (not a square)", 2);
	test("sqrt of 3 (not a square)", 3);
	test("sqrt of 12 (not a square)", 12);
	test("sqrt of 26 (not a square)", 26);
	test("sqrt of -4 (negative)", -4);
	test("sqrt of INT_MIN", INT_MIN);
	test("sqrt of 2147395600 (large square)", 2147395600);
	test("sqrt of 2147395599 (one below)", 2147395599);
	test("sqrt of 2147395601 (one above)", 2147395601);
	test("sqrt of INT_MAX", INT_MAX);
	return (0);
}
