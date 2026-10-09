#include <stdio.h>

int	ft_is_sort(int *tab, int length, int (*f)(int, int));

static int	ascending(int a, int b)
{
	return (a - b);
}

static int	descending(int a, int b)
{
	return (b - a);
}

/* ex04_reverse_output, at strict: "sorted" read as this harness reads it.
 *
 * The subject never says whether an array in the REVERSE of the order f
 * describes counts as sorted. This harness reads it as counting -- either
 * direction is sorted -- and every row below is such an array, so each one's
 * answer is 1 under that reading, by construction, and 0 under the other.
 * Nothing at basic depends on it: test_is_sort.c holds only arrays both
 * readings agree on, and so does the diff layer's corpus.
 *
 * Prints "<label>\t<value>", as test_is_sort.c does. */
static void	test(char *label, int *tab, int length, int (*f)(int, int))
{
	printf("%s\t%d\n", label, ft_is_sort(tab, length, f));
}

int	main(void)
{
	int	two[] = {2, 1};
	int	desc[] = {10, 3, 2, 1};
	int	ties[] = {5, 5, 3, 1, 1};
	int	asc[] = {-4, 0, 7, 9};

	test("two elements against f", two, 2, &ascending);
	test("descending data ascending cmp", desc, 4, &ascending);
	test("descending with ties ascending cmp", ties, 5, &ascending);
	test("ascending data descending cmp", asc, 4, &descending);
	return (0);
}
