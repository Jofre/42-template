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

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. The comparator is supplied here and passed
 * straight to ft_is_sort. Cases are ordered trivial -> hardest, so the first
 * failing row is the most fundamental thing to fix.
 *
 * ONLY ROWS BOTH READINGS AGREE ON. The subject says "sorted" and never says
 * whether an array in the REVERSE of the order f describes counts, so this
 * basic table holds no such array: every row here has the same answer whether
 * the reverse order counts or not, and so does the diff layer's corpus
 * (c11_is_sort). One reading is a target of its own at strict,
 * ex04_reverse_output, over test_is_sort_reverse.c, whose hint states it as
 * this harness's reading: no basic file names it (AGENTS.md section 2). */
static void	test(char *label, int *tab, int length, int (*f)(int, int))
{
	printf("%s\t%d\n", label, ft_is_sort(tab, length, f));
}

int	main(void)
{
	int	one[] = {42};
	int	empty[] = {0};
	int	sorted[] = {1, 2, 2, 3, 10};
	int	equal[] = {5, 5, 5};
	int	unsorted[] = {1, 5, 2, 8};
	int	zigzag[] = {1, 3, 2};
	int	desc[] = {10, 3, 2, 1};

	test("single element", one, 1, &ascending);
	test("empty array", empty, 0, &ascending);
	test("non-decreasing ascending", sorted, 5, &ascending);
	test("all equal elements", equal, 3, &ascending);
	test("out of order", unsorted, 4, &ascending);
	test("up then down", zigzag, 3, &ascending);
	test("descending data descending cmp", desc, 4, &descending);
	return (0);
}
