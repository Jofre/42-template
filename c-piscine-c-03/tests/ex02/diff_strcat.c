/* Live-differential reader harness for ft_strcat.
 * Line: <hexDest>\t<destcap>\t<hexSrc>. Allocates a destcap buffer, seeds it
 * with dest (NUL-terminated by the zeroed tail), appends src, prints the
 * resulting string content as hex, and a trailing 1/0 for "returned dest". */
#include "diffio.h"

char	*ft_strcat(char *dest, char *src);

int	main(void)
{
	char			line[8192];
	char			*f[4];
	size_t			dlen;
	size_t			cap;
	unsigned char	*draw;
	unsigned char	*buf;
	unsigned char	*src;
	char			*ret;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 4) < 3)
			continue ;
		draw = dio_unhex(f[0], &dlen, 0);
		cap = strtoul(f[1], NULL, 10);
		buf = (unsigned char *)calloc(cap, 1);
		memcpy(buf, draw, dlen);
		src = dio_unhex(f[2], NULL, 0);
		ret = ft_strcat((char *)buf, (char *)src);
		printf("%s\t%s\t%s\t", f[0], f[1], f[2]);
		dio_puthex(buf, dio_caplen(buf, cap));
		printf("\t%d\n", ret == (char *)buf);
		free(draw);
		free(buf);
		free(src);
	}
	return (0);
}
