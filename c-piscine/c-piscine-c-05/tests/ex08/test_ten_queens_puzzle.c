#include <stdio.h>

int	ft_ten_queens_puzzle(void);

/* The boards are what the function PRINTS, one unlabelled row each; the last
 * row is what it RETURNED, labelled "return value" (tools/diff_output.sh
 * --labeled gives a line with no tab its line number as its case). */

int	main(void)
{
	int	res;

	res = ft_ten_queens_puzzle();
	printf("return value\t%d\n", res);
	return (0);
}
