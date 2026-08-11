#include <stdio.h>

void	ft_foreach(int *tab, int length, void (*f)(int));

/* The function pointer handed to ft_foreach. It renders one element inline as
 * "[n]" (no newline) so a whole call lands on a single labeled line, e.g.
 * [1][2][3]. */
static void	show(int n)
{
	printf("[%d]", n);
}

/* Prints "<label>\t" then lets ft_foreach apply show() to each element, then a
 * newline. So tools/diff_output.sh --labeled shows one case per row. An empty
 * application prints just the label. Cases run trivial -> hardest, so the first
 * failing row is the most fundamental thing to fix. */
static void	test(char *label, int *tab, int length)
{
	printf("%s\t", label);
	ft_foreach(tab, length, &show);
	printf("\n");
}

int	main(void)
{
	int	tab[] = {1, 2, 3, 42, -5, 0};

	test("single element", tab, 1);
	test("three positives in order", tab, 3);
	test("full array negatives and zero", tab, 6);
	test("length zero applies to nothing", tab, 0);
	return (0);
}
