/* Live-differential reader harness for ft_memset.
 * Line: <hexBefore>\t<c>\t<n>\t<hexAfter>\t<retIsS>, hexBefore the whole
 * block before the call and hexAfter after it, c and n in decimal, retIsS 1
 * when the call returned the s it was handed. Decodes hexBefore into a heap
 * block of exactly its length, calls ft_memset(block, c, n) and reprints
 * the three input fields, the block in hex and (ret == block).
 * See tools/diffio.h. */
#include "diffio.h"

void	*ft_memset(void *s, int c, size_t n);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[5];
	unsigned char	*block;
	size_t			len;
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
		block = dio_unhex_exact(f[0], &len);
		n = (size_t)strtoull(f[2], NULL, 10);
		if (n > len)
			dio_fail("a case asks for more bytes than its block holds");
		ret = ft_memset(block, (int)strtol(f[1], NULL, 10), n);
		printf("%s\t%s\t%s\t", f[0], f[1], f[2]);
		dio_puthex(block, len);
		printf("\t%d\n", ret == block);
		free(block);
	}
	free(line);
	return (0);
}
