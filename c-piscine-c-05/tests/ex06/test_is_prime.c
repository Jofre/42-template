#include <stdio.h>
#include <limits.h>

int	ft_is_prime(int nb);

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases are ordered trivial -> hardest, so
 * the first failing row is the most fundamental thing to fix. */
static void	test(char *label, int nb)
{
	printf("%s\t%d\n", label, ft_is_prime(nb));
}

int	main(void)
{
	test("zero", 0);
	test("one", 1);
	test("two", 2);
	test("three", 3);
	test("minus one", -1);
	test("minus five", -5);
	test("INT_MIN", INT_MIN);
	test("four", 4);
	test("twelve", 12);
	test("eleven", 11);
	test("seventeen", 17);
	test("ninety seven", 97);
	test("nine", 9);
	test("twenty five", 25);
	test("forty nine", 49);
	test("one billion eight", 1000000008);
	test("one billion seven", 1000000007);
	test("INT_MAX minus one", 2147483646);
	test("INT_MAX", 2147483647);
	test("fifteen", 15);
	test("twenty one", 21);
	test("thirty five", 35);
	test("one billion five", 1000000005);
	test("nine nine nine prime", 999999937);
	return (0);
}
