#include <stdio.h>
#include <limits.h>

void	ft_ultimate_ft(int *********nbr);

/* The 9-star pointer chain all leads to the same int n. Each case resets n,
 * calls ft_ultimate_ft, and prints the result (must be 42). */
static void	test(char *label, int *********p9, int *n, int start)
{
	*n = start;
	ft_ultimate_ft(p9);
	printf("%s\t%d\n", label, *n);
}

int	main(void)
{
	int	n;
	int	*p1;
	int	**p2;
	int	***p3;
	int	****p4;
	int	*****p5;
	int	******p6;
	int	*******p7;
	int	********p8;
	int	*********p9;

	p1 = &n;
	p2 = &p1;
	p3 = &p2;
	p4 = &p3;
	p5 = &p4;
	p6 = &p5;
	p7 = &p6;
	p8 = &p7;
	p9 = &p8;
	test("start 0", p9, &n, 0);
	test("start 7", p9, &n, 7);
	test("already 42", p9, &n, 42);
	test("INT_MIN", p9, &n, INT_MIN);
	return (0);
}
