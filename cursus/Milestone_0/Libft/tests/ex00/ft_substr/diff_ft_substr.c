/* Live-differential reader harness for ft_substr.
 * Line: <hexS>\t<start>\t<len>\t<hexSub>. The string, two hex digits per
 * byte, start and len in decimal (len at most 4294967295, or 2^64-1 for
 * SIZE_MAX, so strtoull gives this build's SIZE_MAX either way), then what
 * the returned string holds up to its NUL, as hex -- or NULL when ft_substr
 * returned NULL. The result is freed. See tools/diffio.h. */
#include "diffio.h"

char	*ft_substr(char const *s, unsigned int start, size_t len);

int	main(void)
{
	char				*line;
	size_t				linecap;
	char				*f[4];
	unsigned char		*s;
	unsigned long long	len;
	char				*res;

	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 4) < 3)
			continue ;
		s = dio_unhex(f[0], NULL, 0);
		len = strtoull(f[2], NULL, 10);
		if (len > (unsigned long long)SIZE_MAX)
			len = SIZE_MAX;
		res = ft_substr((char *)s, (unsigned int)strtoul(f[1], NULL, 10),
				(size_t)len);
		printf("%s\t%s\t%s\t", f[0], f[1], f[2]);
		if (res == NULL)
			printf("NULL");
		else
			dio_puthex((unsigned char *)res, strlen(res));
		printf("\n");
		free(res);
		free(s);
	}
	free(line);
	return (0);
}
