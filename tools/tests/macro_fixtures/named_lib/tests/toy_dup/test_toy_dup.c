#include <stdio.h>
#include <stdlib.h>

char	*toy_dup(int n);

/* The toy library's toy_dup, in its own folder: a member whose own box
 * allows malloc, so its call keeps the leak layer. */
int	main(void)
{
	char	*s;

	s = toy_dup(0);
	printf("null\t%d\n", s == NULL);
	free(s);
	return (0);
}
