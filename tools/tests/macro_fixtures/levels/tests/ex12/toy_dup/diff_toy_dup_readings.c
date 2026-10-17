/* The reading's own reader harness for toy_dup, the toy library's member:
 * the same cases as diff_toy_dup.c, each result read another way.
 * Line: <n>\t<the length of what toy_dup returned, -1 for NULL>. The input
 * as the reference wrote it, then that length. See tools/diffio.h. */
#include "diffio.h"

char	*toy_dup(int n);

int	main(void)
{
	char	line[256];
	char	*f[2];
	char	*r;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		r = toy_dup((int)strtol(f[0], NULL, 10));
		if (r == NULL)
			printf("%s\t-1\n", f[0]);
		else
			printf("%s\t%d\n", f[0], (int)strlen(r));
		free(r);
	}
	return (0);
}
