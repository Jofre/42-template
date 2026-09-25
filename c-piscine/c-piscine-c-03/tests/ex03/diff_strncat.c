/* Live-differential reader harness for ft_strncat.
 * Line: <hexDest>\t<destcap>\t<hexSrc>\t<n>. */
#include "diffio.h"

char	*ft_strncat(char *dest, char *src, unsigned int nb);

int	main(void)
{
	char			line[8192];
	char			*f[5];
	size_t			dlen;
	size_t			cap;
	unsigned char	*draw;
	unsigned char	*buf;
	unsigned char	*src;
	unsigned int	n;
	char			*ret;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 5) < 4)
			continue ;
		draw = dio_unhex(f[0], &dlen, 0);
		cap = strtoul(f[1], NULL, 10);
		buf = (unsigned char *)calloc(cap, 1);
		memcpy(buf, draw, dlen);
		src = dio_unhex(f[2], NULL, 0);
		n = (unsigned int)strtoul(f[3], NULL, 10);
		ret = ft_strncat((char *)buf, (char *)src, n);
		printf("%s\t%s\t%s\t%s\t", f[0], f[1], f[2], f[3]);
		dio_puthex(buf, dio_caplen(buf, cap));
		printf("\t%d\n", ret == (char *)buf);
		free(draw);
		free(buf);
		free(src);
	}
	return (0);
}
