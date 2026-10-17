/* Live-differential reader harness for ft_memcpy.
 * Line: <hexSrc>\t<n>\t<hexDestBefore>\t<hexDestAfter>\t<retIsDest>, each
 * hex field a whole block, n in decimal, retIsDest 1 when the call returned
 * the dest it was handed. Decodes src and dest into two separate heap blocks
 * of exactly their lengths (they never overlap), calls ft_memcpy(dest, src,
 * n) and reprints the three input fields, dest in hex and (ret == dest).
 * See tools/diffio.h. */
#include "diffio.h"

void	*ft_memcpy(void *dest, const void *src, size_t n);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[5];
	unsigned char	*src;
	unsigned char	*dest;
	size_t			slen;
	size_t			dlen;
	size_t			n;
	void			*ret;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * blocks past 4 KiB. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 5) < 3)
			continue ;
		src = dio_unhex_exact(f[0], &slen);
		dest = dio_unhex_exact(f[2], &dlen);
		n = (size_t)strtoull(f[1], NULL, 10);
		if (n > slen || n > dlen)
			dio_fail("a case asks for more bytes than its blocks hold");
		ret = ft_memcpy(dest, src, n);
		printf("%s\t%s\t%s\t", f[0], f[1], f[2]);
		dio_puthex(dest, dlen);
		printf("\t%d\n", ret == dest);
		free(src);
		free(dest);
	}
	free(line);
	return (0);
}
