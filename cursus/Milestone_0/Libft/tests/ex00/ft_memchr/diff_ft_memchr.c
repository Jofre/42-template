/* Live-differential reader harness for ft_memchr.
 * Line: <hexBuf>\t<c>\t<n>\t<off|NULL>, the whole block in hex, c and n in
 * decimal, then where the returned pointer points: its offset from the
 * start of the block in decimal, or NULL (OUTSIDE when it points anywhere
 * else). Decodes the block into a heap block of exactly its length, calls
 * ft_memchr(block, c, n) and reprints the three input fields and the
 * result. See tools/diffio.h. */
#include "diffio.h"

void	*ft_memchr(const void *s, int c, size_t n);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[4];
	unsigned char	*block;
	unsigned char	*ret;
	size_t			len;
	size_t			n;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * blocks past 4 KiB. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 4) < 3)
			continue ;
		block = dio_unhex_exact(f[0], &len);
		n = (size_t)strtoull(f[2], NULL, 10);
		if (n > len)
			dio_fail("a case asks for more bytes than its block holds");
		ret = (unsigned char *)ft_memchr(block, (int)strtol(f[1], NULL, 10), n);
		printf("%s\t%s\t%s\t", f[0], f[1], f[2]);
		if (ret == NULL)
			printf("NULL\n");
		else if (ret >= block && ret < block + len)
			printf("%zu\n", (size_t)(ret - block));
		else
			printf("OUTSIDE\n");
		free(block);
	}
	free(line);
	return (0);
}
