/* Live-differential reader harness for ft_memcmp.
 * Line: <hexA>\t<hexB>\t<n>\t<sign>, two blocks in hex, n in decimal, sign
 * -1, 0 or 1: the sign of the result, which is all man memcmp promises.
 * Decodes each block into a heap block of exactly its length, calls
 * ft_memcmp(a, b, n) and reprints the three input fields and the sign of
 * what it returned. See tools/diffio.h. */
#include "diffio.h"

int	ft_memcmp(const void *s1, const void *s2, size_t n);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[4];
	unsigned char	*a;
	unsigned char	*b;
	size_t			alen;
	size_t			blen;
	size_t			n;
	int				r;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * blocks past 4 KiB. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 4) < 3)
			continue ;
		a = dio_unhex_exact(f[0], &alen);
		b = dio_unhex_exact(f[1], &blen);
		n = (size_t)strtoull(f[2], NULL, 10);
		if (n > alen || n > blen)
			dio_fail("a case asks for more bytes than its blocks hold");
		r = ft_memcmp(a, b, n);
		printf("%s\t%s\t%s\t%d\n", f[0], f[1], f[2], (r > 0) - (r < 0));
		free(a);
		free(b);
	}
	free(line);
	return (0);
}
