/* Live-differential reader harness for ft_str_is_numeric.
 * Line: <hexStr>\t<0|1>. Reprints <hexStr>\t<student predicate result>. */
#include "diffio.h"

int	ft_str_is_numeric(char *str);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[2];
	unsigned char	*s;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB (finding 041), past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		s = dio_unhex(f[0], NULL, 0);
		printf("%s\t%d\n", f[0], ft_str_is_numeric((char *)s));
		free(s);
	}
	free(line);
	return (0);
}
