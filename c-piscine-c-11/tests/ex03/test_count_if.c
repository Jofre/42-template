#include <stdio.h>

int	ft_count_if(char **tab, int length, int (*f)(char *));

/* Predicate: truthy (1) when the first character is an uppercase letter. */
static int	first_is_upper(char *s)
{
	if (s[0] >= 'A' && s[0] <= 'Z')
		return (1);
	return (0);
}

/* Predicate returning a truthy value that is NOT 1 (100) on a match, so a
 * correct count adds one per match instead of summing the returned values. */
static int	upper_weight(char *s)
{
	if (s[0] >= 'A' && s[0] <= 'Z')
		return (100);
	return (0);
}

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases are ordered trivial -> hardest, so
 * the first failing row is the most fundamental thing to fix. The test passes
 * the predicate to apply as a function pointer. */
static void	test(char *label, char **tab, int length, int (*f)(char *))
{
	printf("%s\t%d\n", label, ft_count_if(tab, length, f));
}

int	main(void)
{
	char	*tab[] = {"Apple", "banana", "Cherry", "Date", "egg"};
	char	*none[] = {"a", "b", "c"};
	char	*all[] = {"A", "B", "C"};
	char	*bounded[] = {"A", "B", "C", "D", NULL};

	test("length 0 counts nothing", tab, 0, &first_is_upper);
	test("no element matches", none, 3, &first_is_upper);
	test("every element matches", all, 3, &first_is_upper);
	test("some match some do not", tab, 5, &first_is_upper);
	test("match returns 100 not 1", tab, 5, &upper_weight);
	test("length bounds the scan", bounded, 2, &first_is_upper);
	return (0);
}
