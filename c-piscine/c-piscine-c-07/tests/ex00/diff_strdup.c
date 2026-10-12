/* Live-differential reader harness for ft_strdup.
 * Line: <hexSrc>\t<hexCopy>. The source, two hex digits per byte, then what
 * the returned copy holds up to its NUL, as hex -- or NULL when ft_strdup
 * returned NULL. See tools/diffio.h. */
#include "diffio.h"

char	*ft_strdup(char *src);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[2];
	unsigned char	*src;
	char			*res;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB (finding 041), past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		src = dio_unhex(f[0], NULL, 0);
		res = ft_strdup((char *)src);
		printf("%s\t", f[0]);
		if (!res)
			printf("NULL");
		else
			dio_puthex((unsigned char *)res, strlen(res));
		printf("\n");
		free(src);
		free(res);
	}
	free(line);
	return (0);
}
