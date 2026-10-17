/* Live-differential reader harness for ft_strlen.
 * Line: <hexS>\t<len>. The string, two hex digits per byte, then what
 * ft_strlen returned for it, in decimal. The strings hold no NUL; see
 * tools/diffio.h. */
#include "diffio.h"

size_t	ft_strlen(const char *s);

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
		printf("%s\t%zu\n", f[0], ft_strlen((const char *)s));
		free(s);
	}
	free(line);
	return (0);
}
