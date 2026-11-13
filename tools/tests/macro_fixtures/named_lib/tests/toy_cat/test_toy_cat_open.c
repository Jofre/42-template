#include <stdio.h>
#include <stdlib.h>

char	*toy_cat(char *s);

/* A case the toy subject leaves open: its own main, its own level. */
int	main(void)
{
	char	*s;

	s = toy_cat(NULL);
	printf("from_null\t%d\n", s == NULL);
	free(s);
	return (0);
}
