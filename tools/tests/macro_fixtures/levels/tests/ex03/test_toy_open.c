#include <stdio.h>

int	toy_two(int n);

/* A case the toy subject leaves open: its own main, its own level. */
int	main(void)
{
	printf("negative\t%d\n", toy_two(-1));
	return (0);
}
