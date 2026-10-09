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

/* 5000 ints, -2500 to 2499 in a shuffled order (i * 7919 % 5000 visits
 * every value once, 7919 sharing no factor with 5000), and the result checked
 * against what sorting them must give by construction, then shown as ONE line:
 * the sorted run, abridged, or the first value out of place. The subject
 * bounds no size, so every reading agrees on this case, and it is past every
 * capacity a copy is usually given (16, 64, 256, 1024, 4096): a function that
 * works through a fixed-size array of its own gets it wrong here, or dies
 * (finding 041). */
static void	test_long(void)
{
	static int	tab[5000];
	int			i;

	i = 0;
	while (i < 5000)
	{
		tab[i] = i * 7919 % 5000 - 2500;
		i++;
	}
	ft_sort_int_tab(tab, 5000);
	printf("5000 ints, shuffled\t");
	i = 0;
	while (i < 5000 && tab[i] == i - 2500)
		i++;
	if (i == 5000)
		printf("-2500 -2499 ... 2498 2499\n");
	else
		printf("tab[%d] is %d, not %d\n", i, tab[i], i - 2500);
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
	test_long();
	return (0);
}
