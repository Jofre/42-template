#include <stdio.h>
#include <stdlib.h>

int	*ft_range(int min, int max);

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. A range is rendered on ONE line with each
 * element bracketed, e.g. [1][2][3]; a NULL result prints "NULL". Cases are
 * ordered trivial -> hardest, so the first failing row is the most fundamental
 * thing to fix. The array is freed after printing. */
static void	test(char *label, int min, int max)
{
	int	*tab;
	int	size;
	int	i;

	tab = ft_range(min, max);
	if (!tab)
	{
		printf("%s\tNULL\n", label);
		return ;
	}
	size = max - min;
	printf("%s\t", label);
	i = 0;
	while (i < size)
	{
		printf("[%d]", tab[i]);
		i++;
	}
	printf("\n");
	free(tab);
}

int	main(void)
{
	test("four ascending", 1, 5);
	test("crosses zero", -3, 3);
	test("single element at zero", 0, 1);
	test("single element non-zero", 42, 43);
	test("negatives only", -5, -2);
	test("min equals max", 5, 5);
	test("min greater than max", 10, 3);
	return (0);
}
