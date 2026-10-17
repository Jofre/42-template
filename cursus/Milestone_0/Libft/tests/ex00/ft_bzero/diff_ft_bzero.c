/* Live-differential reader harness for ft_bzero.
 * Line: <hexBefore>\t<n>\t<hexAfter>, hexBefore the whole block before the
 * call and hexAfter after it, n in decimal. Decodes hexBefore into a heap
 * block of exactly its length, calls ft_bzero(block, n) and reprints the
 * two input fields and the block in hex. See tools/diffio.h. */
#include "diffio.h"

/* conventions: zeroed -- the prototype of the function under test, which
 * zeroes nothing here: no buffer is set to 0 before it is handed over. */
void	ft_bzero(void *s, size_t n);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[3];
	unsigned char	*block;
	size_t			len;
	size_t			n;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * blocks past 4 KiB. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		block = dio_unhex_exact(f[0], &len);
		n = (size_t)strtoull(f[1], NULL, 10);
		if (n > len)
			dio_fail("a case asks for more bytes than its block holds");
		/* conventions: zeroed -- this call IS the function under test: block
		 * holds the case's own bytes (dio_unhex_exact, from the hex), never
		 * zeros put there by the harness. */
		ft_bzero(block, n);
		printf("%s\t%s\t", f[0], f[1]);
		dio_puthex(block, len);
		printf("\n");
		free(block);
	}
	free(line);
	return (0);
}
