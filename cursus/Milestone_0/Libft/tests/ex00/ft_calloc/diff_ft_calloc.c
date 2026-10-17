/* Live-differential reader harness for ft_calloc.
 * Line: <nmemb>\t<size>\t<what>, nmemb and size in decimal, what one of
 * zeroed (a block of nmemb x size bytes, every one 0), nonnull (nmemb or
 * size 0, and a pointer that is not NULL), NULL, or NOTZERO (a block with a
 * byte that is not 0). Calls ft_calloc(nmemb, size), reads every byte of
 * the block it got, then fills it with 0xa5 before freeing it, so that a
 * later case asking for the same size is likely handed a block that is not
 * 0 already. See tools/diffio.h. */
#include "diffio.h"

void	*ft_calloc(size_t nmemb, size_t size);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[3];
	unsigned char	*p;
	size_t			nmemb;
	size_t			size;
	size_t			total;
	size_t			i;
	int				clean;

	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		nmemb = (size_t)strtoull(f[0], NULL, 10);
		size = (size_t)strtoull(f[1], NULL, 10);
		p = (unsigned char *)ft_calloc(nmemb, size);
		printf("%s\t%s\t", f[0], f[1]);
		if (p == NULL)
		{
			printf("NULL\n");
			continue ;
		}
		/* What a block of nmemb x size bytes holds is read in full; a block
		 * shorter than that is a read past it, which ASan reports in the
		 * twin of this layer. */
		total = nmemb * size;
		clean = 1;
		i = 0;
		while (i < total)
			clean &= (p[i++] == 0);
		memset(p, 0xa5, total);
		if (nmemb == 0 || size == 0)
			printf("nonnull\n");
		else
			printf("%s\n", clean ? "zeroed" : "NOTZERO");
		free(p);
	}
	free(line);
	return (0);
}
