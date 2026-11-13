#include <stdio.h>

int	toy_tally(int n);

/* The mandatory part: its program is built from its own files alone. */
int	main(void)
{
	printf("zero\t%d\n", toy_tally(0));
	return (0);
}
