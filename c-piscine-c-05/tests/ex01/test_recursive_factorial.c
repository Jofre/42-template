#include <stdio.h>
#include <limits.h>

int	ft_recursive_factorial(int nb);

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases are ordered trivial -> hardest, so
 * the first failing row is the most fundamental thing to fix. */
static void	test(char *label, int nb)
{
	printf("%s\t%d\n", label, ft_recursive_factorial(nb));
}

int	main(void)
{
	test("factorial of 0", 0);
	test("factorial of 1", 1);
	test("factorial of 2", 2);
	test("factorial of 3", 3);
	test("factorial of 4", 4);
	test("factorial of 5", 5);
	test("negative -1", -1);
	test("negative -5", -5);
	test("INT_MIN", INT_MIN);
	test("factorial of 10", 10);
	test("factorial of 12", 12);
	return (0);
}
