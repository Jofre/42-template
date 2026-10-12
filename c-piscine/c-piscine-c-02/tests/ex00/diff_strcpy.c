/* Live-differential reader harness for ft_strcpy.
 * Line: <hexSrc>\t<hexDestContent>\t1. Copies src into a dest buffer prefilled
 * with 0xff (so a missing terminator is caught), reprints the dest content
 * (hex, up to the terminating NUL), then a trailing 1/0 for "returned dest".
 * See tools/diffio.h. */
#include "diffio.h"

char	*ft_strcpy(char *dest, char *src);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[2];
	unsigned char	*src;
	unsigned char	*dest;
	size_t			slen;
	char			*ret;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB (finding 041), past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		src = dio_unhex(f[0], &slen, 0);
		dest = dio_garbage(slen + 1);
		ret = ft_strcpy((char *)dest, (char *)src);
		printf("%s\t", f[0]);
		dio_puthex(dest, dio_caplen(dest, slen + 1));
		printf("\t%d\n", ret == (char *)dest);
		free(src);
		free(dest);
	}
	free(line);
	return (0);
}
