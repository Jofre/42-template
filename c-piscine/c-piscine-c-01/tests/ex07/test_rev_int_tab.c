#include <stdio.h>
#include <limits.h>

void	ft_rev_int_tab(int *tab, int size);

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

/* Reverses tab[0..size) in place, then prints "<label>\t" + the first `show`
 * elements (show lets a size-0 call still display the untouched array). */
static void	test(char *label, int *tab, int size, int show)
{
	ft_rev_int_tab(tab, size);
	printf("%s\t", label);
	print_tab(tab, show);
}

int	main(void)
{
	int	one[1] = {42};
	int	empty[1] = {99};
	int	two[2] = {10, 20};
	int	even[4] = {1, 2, 3, 4};
	int	odd[5] = {1, 2, 3, 4, 5};
	int	mix[6] = {-1, -1, 0, 7, -3, INT_MIN};

	test("single {42}", one, 1, 1);
	test("size 0 (no-op)", empty, 0, 1);
	test("two {10,20}", two, 2, 2);
	test("even len {1..4}", even, 4, 4);
	test("odd len {1..5}", odd, 5, 5);
	test("with INT_MIN", mix, 6, 6);
	return (0);
}
