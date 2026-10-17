#include <stdio.h>
#include <stdlib.h>

char	*toy_cat(char *s);

/* The toy library's toy_cat, in its own folder: a member whose own box
 * allows malloc and free, so its call keeps the leak layer and both
 * allocation-failure sweeps. */
int	main(void)
{
	char	*s;

	s = toy_cat("");
	printf("null\t%d\n", s == NULL);
	free(s);
	return (0);
}
