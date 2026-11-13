/* Live-differential reader harness for ft_strdup.
 * Line: <hexS>\t<hexDup>. The source, two hex digits per byte, then what the
 * returned copy holds up to its NUL, as hex -- read no further than one byte
 * past the source's length -- or NULL when ft_strdup returned NULL, or SAME
 * when it returned the source itself, which is no copy. See
 * tools/diffio.h. */
#include "diffio.h"

char	*ft_strdup(const char *s);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[2];
	unsigned char	*src;
	size_t			len;
	char			*res;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB, past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		dio_split(line, f, 2);
		src = dio_unhex(f[0], &len, 0);
		res = ft_strdup((const char *)src);
		printf("%s\t", f[0]);
		if (res == NULL)
			printf("NULL");
		else if (res == (char *)src)
			printf("SAME");
		else
			dio_puthex((unsigned char *)res,
				dio_caplen((unsigned char *)res, len + 1));
		printf("\n");
		if (res != (char *)src)
			free(res);
		free(src);
	}
	free(line);
	return (0);
}
