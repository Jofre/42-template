/* Live-differential reader harness for toy_cat, the toy library's member.
 * Line: <n>\t<whether toy_cat returned NULL>. The input as the reference
 * wrote it, then 1 or 0. See tools/diffio.h. */
#include "diffio.h"

char	*toy_cat(char *s);

int	main(void)
{
	char	line[256];
	char	*f[2];
	char	*r;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		r = toy_cat(f[0]);
		printf("%s\t%d\n", f[0], r == NULL);
		free(r);
	}
	return (0);
}
