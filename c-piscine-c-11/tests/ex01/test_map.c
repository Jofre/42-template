#include <stdio.h>
#include <stdlib.h>

int	*ft_map(int *tab, int length, int (*f)(int));

/* The f handed to ft_map: doubles each value, applied via the function
 * pointer. The mapped array should hold double_int of every element. */
static int	double_int(int n)
{
	return (n * 2);
}

/* Prints "<label>\t" then BOTH arrays on one line: the mapped result first,
 * bracketed [v] with no spaces, then the original input the same way, so
 * tools/diff_output.sh --labeled shows one case per row. ft_map must return a
 * NEW array and leave the input untouched, so input=[..] must echo the source.
 * A length-0 result renders mapped=[] input=[] (empty-allocation path). Cases
 * run trivial -> hardest, so the first failing row is the most fundamental. */
static void	test(char *label, int *tab, int length, int (*f)(int))
{
	int	*res;
	int	i;

	res = ft_map(tab, length, f);
	printf("%s\tmapped=", label);
	if (res)
	{
		i = 0;
		while (i < length)
		{
			printf("[%d]", res[i]);
			i++;
		}
		free(res);
	}
	printf(" input=");
	i = 0;
	while (i < length)
	{
		printf("[%d]", tab[i]);
		i++;
	}
	printf("\n");
}

int	main(void)
{
	int	one[] = {21};
	int	few[] = {1, 2, 3};
	int	mixed[] = {1, 2, 3, 42, -5, 0};
	int	negs[] = {-1, -2, -3, -4};
	int	empty[] = {7};

	test("single element", one, 1, &double_int);
	test("three ascending", few, 3, &double_int);
	test("mixed signs and zero", mixed, 6, &double_int);
	test("all negative", negs, 4, &double_int);
	test("length zero", empty, 0, &double_int);
	return (0);
}
