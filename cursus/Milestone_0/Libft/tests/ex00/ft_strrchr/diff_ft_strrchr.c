/* Live-differential reader harness for ft_strrchr.
 * Line: <hexS>\t<c>\t<off|NULL>. The string, two hex digits per byte, c in
 * decimal, then where the returned pointer points: its offset from the
 * start of the string, in decimal, NULL, or OUTSIDE for a pointer that is
 * neither into the string nor at its terminator. See tools/diffio.h. */
#include "diffio.h"

char	*ft_strrchr(const char *s, int c);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[3];
	unsigned char	*s;
	size_t			len;
	char			*p;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB, past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		s = dio_unhex(f[0], &len, 0);
		p = ft_strrchr((const char *)s, (int)strtol(f[1], NULL, 10));
		printf("%s\t%s\t", f[0], f[1]);
		if (p == NULL)
			printf("NULL\n");
		else if (p >= (char *)s && p <= (char *)s + len)
			printf("%zu\n", (size_t)(p - (char *)s));
		else
			printf("OUTSIDE\n");
		free(s);
	}
	free(line);
	return (0);
}
