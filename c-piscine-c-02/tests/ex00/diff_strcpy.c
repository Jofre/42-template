/* Live-differential reader harness for ft_strcpy.
 * Line: <hexSrc>\t<hexDestContent>\t1. Copies src into a dest buffer prefilled
 * with 0xff (so a missing terminator is caught), reprints the dest content
 * (hex, up to the terminating NUL), then a trailing 1/0 for "returned dest".
 * See tools/diffio.h. */
#include "diffio.h"

char	*ft_strcpy(char *dest, char *src);

int	main(void)
{
	char			line[8192];
	char			*f[2];
	unsigned char	*src;
	unsigned char	*dest;
	size_t			slen;
	char			*ret;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		src = dio_unhex(f[0], &slen, 0);
		dest = (unsigned char *)malloc(slen + 1);
		memset(dest, 0xff, slen + 1);
		ret = ft_strcpy((char *)dest, (char *)src);
		printf("%s\t", f[0]);
		dio_puthex(dest, dio_caplen(dest, slen + 1));
		printf("\t%d\n", ret == (char *)dest);
		free(src);
		free(dest);
	}
	return (0);
}
