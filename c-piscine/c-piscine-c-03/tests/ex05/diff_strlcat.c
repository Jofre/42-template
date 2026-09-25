/* Live-differential reader harness for ft_strlcat.
 * Line: <hexDest>\t<destcap>\t<hexSrc>\t<size>. Prints the resulting buffer
 * content (hex, bounded by cap) and the return value. */
#include "diffio.h"

unsigned int	ft_strlcat(char *dest, char *src, unsigned int size);

int	main(void)
{
	char			line[8192];
	char			*f[6];
	size_t			dlen;
	size_t			cap;
	unsigned int	size;
	unsigned char	*draw;
	unsigned char	*buf;
	unsigned char	*src;
	unsigned int	ret;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 6) < 4)
			continue ;
		draw = dio_unhex(f[0], &dlen, 0);
		cap = strtoul(f[1], NULL, 10);
		buf = (unsigned char *)calloc(cap, 1);
		memcpy(buf, draw, dlen);
		src = dio_unhex(f[2], NULL, 0);
		size = (unsigned int)strtoul(f[3], NULL, 10);
		ret = ft_strlcat((char *)buf, (char *)src, size);
		printf("%s\t%s\t%s\t%s\t", f[0], f[1], f[2], f[3]);
		dio_puthex(buf, dio_caplen(buf, cap));
		printf("\t%u\n", ret);
		free(draw);
		free(buf);
		free(src);
	}
	return (0);
}
