/* Live-differential reader harness for ft_strupcase.
 * Line: <hexStr>\t<hexResult>\t1. Case transform is in place and length-
 * preserving (never introduces a NUL), so all original bytes are reprinted as
 * hex, then a trailing 1/0 for "returned the str pointer it was given". */
#include "diffio.h"

char	*ft_strupcase(char *str);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[2];
	unsigned char	*s;
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
		s = dio_unhex(f[0], &slen, 0);
		ret = ft_strupcase((char *)s);
		printf("%s\t", f[0]);
		dio_puthex(s, slen);
		printf("\t%d\n", ret == (char *)s);
		free(s);
	}
	free(line);
	return (0);
}
