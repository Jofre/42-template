#include <stdio.h>
#include <limits.h>

int	ft_fibonacci(int index);

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases are ordered trivial -> hardest, so
 * the first failing row is the most fundamental thing to fix. */
static void	test(char *label, int index)
{
	printf("%s\t%d\n", label, ft_fibonacci(index));
}

int	main(void)
{
	test("index 0", 0);
	test("index 1", 1);
	test("index 2", 2);
	test("index 3", 3);
	test("index 4", 4);
	test("index 5", 5);
	test("index 6", 6);
	test("index 7", 7);
	test("index 10", 10);
	test("index 20", 20);
	test("index 30", 30);
	test("index -1", -1);
	test("index -5", -5);
	test("index INT_MIN", INT_MIN);
	return (0);
}
