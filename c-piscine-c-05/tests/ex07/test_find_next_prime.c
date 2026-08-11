#include <stdio.h>

int	ft_find_next_prime(int nb);

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases are ordered trivial -> hardest, so
 * the first failing row is the most fundamental thing to fix. */
static void	test(char *label, int nb)
{
	printf("%s\t%d\n", label, ft_find_next_prime(nb));
}

int	main(void)
{
	test("nb is 2 (already prime)", 2);
	test("nb is 3 (already prime)", 3);
	test("nb is 4 (next is 5)", 4);
	test("nb is 13 (already prime)", 13);
	test("nb is 14 (next after 13)", 14);
	test("nb is 20", 20);
	test("nb is 97 (already prime)", 97);
	test("nb below 2: zero", 0);
	test("nb below 2: one", 1);
	test("nb negative", -5);
	test("big prime 2147483629", 2147483629);
	test("INT_MAX is prime", 2147483647);
	return (0);
}
