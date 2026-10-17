/* Live-differential reader harness for ft_strncmp.
 * Line: <hexS1>\t<hexS2>\t<n>\t<sign>. The two strings, two hex digits per
 * byte, n in decimal (18446744073709551615 is SIZE_MAX), then the SIGN of
 * what ft_strncmp returned: -1, 0 or 1. man 3 strncmp promises a sign, and
 * only the sign is compared. See tools/diffio.h. */
#include "diffio.h"

int	ft_strncmp(const char *s1, const char *s2, size_t n);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[4];
	unsigned char	*a;
	unsigned char	*b;
	size_t			n;
	int				r;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB, past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 4) < 3)
			continue ;
		a = dio_unhex(f[0], NULL, 0);
		b = dio_unhex(f[1], NULL, 0);
		n = (size_t)strtoull(f[2], NULL, 10);
		r = ft_strncmp((const char *)a, (const char *)b, n);
		printf("%s\t%s\t%s\t%d\n", f[0], f[1], f[2], (r > 0) - (r < 0));
		free(a);
		free(b);
	}
	free(line);
	return (0);
}
