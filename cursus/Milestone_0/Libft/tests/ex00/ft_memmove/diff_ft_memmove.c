/* Live-differential reader harness for ft_memmove.
 * Line: <hexBuf>\t<srcOff>\t<dstOff>\t<n>\t<hexBufAfter>\t<retIsDest>, one
 * block before and after the call (hex), src = block + srcOff and dest =
 * block + dstOff (decimal), so the two may overlap either way or be the
 * same, n in decimal, retIsDest 1 when the call returned the dest it was
 * handed. Decodes the block into a heap block of exactly its length, calls
 * ft_memmove(dest, src, n) and reprints the four input fields, the block in
 * hex and (ret == dest). See tools/diffio.h. */
#include "diffio.h"

void	*ft_memmove(void *dest, const void *src, size_t n);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[6];
	unsigned char	*block;
	size_t			len;
	size_t			so;
	size_t			d_o;
	size_t			n;
	void			*ret;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * blocks past 4 KiB. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 6) < 4)
			continue ;
		block = dio_unhex_exact(f[0], &len);
		so = (size_t)strtoull(f[1], NULL, 10);
		d_o = (size_t)strtoull(f[2], NULL, 10);
		n = (size_t)strtoull(f[3], NULL, 10);
		if (so > len || d_o > len || n > len - so || n > len - d_o)
			dio_fail("a case asks for more bytes than its block holds");
		ret = ft_memmove(block + d_o, block + so, n);
		printf("%s\t%s\t%s\t%s\t", f[0], f[1], f[2], f[3]);
		dio_puthex(block, len);
		printf("\t%d\n", ret == block + d_o);
		free(block);
	}
	free(line);
	return (0);
}
