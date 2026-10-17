/* Live-differential reader harness for ft_strncmp.
 * Line: <hexA>\t<hexB>\t<n>\t<sign>. The two strings, two hex digits per
 * byte, n in decimal, then the SIGN of what ft_strncmp returned for them: -1,
 * 0 or 1. man strncmp promises a sign, and here only the sign is compared.
 * See tools/diffio.h. */
#include "diffio.h"

int	ft_strncmp(char *s1, char *s2, unsigned int n);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[4];
	unsigned char	*a;
	unsigned char	*b;
	unsigned int	n;
	int				r;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB (finding 041), past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 4) < 3)
			continue ;
		a = dio_unhex(f[0], NULL, 0);
		b = dio_unhex(f[1], NULL, 0);
		n = (unsigned int)strtoul(f[2], NULL, 10);
		r = ft_strncmp((char *)a, (char *)b, n);
		printf("%s\t%s\t%s\t%d\n", f[0], f[1], f[2], (r > 0) - (r < 0));
		free(a);
		free(b);
	}
	free(line);
	return (0);
}
