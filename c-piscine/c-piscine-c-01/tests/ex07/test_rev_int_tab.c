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

/* 5000 ints, 0 to 4999, and the result checked against what reversing them
 * must give by construction, then shown as ONE line: the reversal, abridged,
 * or the first value out of place. The subject bounds no size, so every
 * reading agrees on this case, and it is past every capacity a copy is
 * usually given (16, 64, 256, 1024, 4096): a function that works through a
 * fixed-size array of its own gets it wrong here, or dies (finding 041). */
static void	test_long(void)
{
	static int	tab[5000];
	int			i;

	i = 0;
	while (i < 5000)
	{
		tab[i] = i;
		i++;
	}
	ft_rev_int_tab(tab, 5000);
	printf("5000 ints {0..4999}\t");
	i = 0;
	while (i < 5000 && tab[i] == 4999 - i)
		i++;
	if (i == 5000)
		printf("4999 4998 ... 1 0\n");
	else
		printf("tab[%d] is %d, not %d\n", i, tab[i], 4999 - i);
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
	test_long();
	return (0);
}
