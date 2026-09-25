#include <stdio.h>
#include <limits.h>

void	ft_sort_int_tab(int *tab, int size);

static void	print_tab(int *tab, int size)
{
	int	i;

	i = 0;
	while (i < size)
	{
		printf("%d", tab[i]);
		if (i < size - 1)
			printf(" ");
		i++;
	}
	printf("\n");
}

/* Sorts tab[0..size) ascending in place, then prints "<label>\t" + the first
 * `show` elements (show lets a size-0 call still display the untouched array). */
static void	test(char *label, int *tab, int size, int show)
{
	ft_sort_int_tab(tab, size);
	printf("%s\t", label);
	print_tab(tab, show);
}

int	main(void)
{
	int	one[1] = {7};
	int	empty[1] = {99};
	int	sorted[4] = {1, 2, 3, 4};
	int	rev[4] = {4, 3, 2, 1};
	int	dups[6] = {5, 2, 9, 1, 5, 6};
	int	neg[6] = {3, -1, -1, 2, 0, -5};
	int	lim[5] = {INT_MAX, 0, INT_MIN, -1, 1};

	test("single {7}", one, 1, 1);
	test("size 0 (no-op)", empty, 0, 1);
	test("already sorted", sorted, 4, 4);
	test("reversed", rev, 4, 4);
	test("with duplicates", dups, 6, 6);
	test("negatives", neg, 6, 6);
	test("INT_MIN & INT_MAX", lim, 5, 5);
	return (0);
}
