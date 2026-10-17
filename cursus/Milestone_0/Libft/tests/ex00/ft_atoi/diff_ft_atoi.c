/* Live-differential reader harness for ft_atoi.
 * Line: <hexS>\t<int>. The string, two hex digits per byte, then what
 * ft_atoi returned for it, in decimal. No string of the corpus spells a
 * number outside the int range. See tools/diffio.h. */
#include "diffio.h"

int	ft_atoi(const char *nptr);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[2];
	unsigned char	*s;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB, past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		s = dio_unhex(f[0], NULL, 0);
		printf("%s\t%d\n", f[0], ft_atoi((const char *)s));
		free(s);
	}
	free(line);
	return (0);
}
