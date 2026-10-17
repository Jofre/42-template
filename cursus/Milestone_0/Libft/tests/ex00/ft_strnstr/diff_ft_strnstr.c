/* Live-differential reader harness for ft_strnstr.
 * Line: <hexBig>\t<hexLittle>\t<len>\t<off|NULL>. big and little, two hex
 * digits per byte, len in decimal (18446744073709551615 is SIZE_MAX), then
 * where the returned pointer points: its offset from the start of big, in
 * decimal, NULL, or OUTSIDE for a pointer that is neither into big nor at
 * its terminator. See tools/diffio.h. */
#include "diffio.h"

char	*ft_strnstr(const char *big, const char *little, size_t len);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[4];
	unsigned char	*big;
	unsigned char	*little;
	size_t			blen;
	char			*p;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB, past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 4) < 3)
			continue ;
		big = dio_unhex(f[0], &blen, 0);
		little = dio_unhex(f[1], NULL, 0);
		p = ft_strnstr((const char *)big, (const char *)little,
				(size_t)strtoull(f[2], NULL, 10));
		printf("%s\t%s\t%s\t", f[0], f[1], f[2]);
		if (p == NULL)
			printf("NULL\n");
		else if (p >= (char *)big && p <= (char *)big + blen)
			printf("%zu\n", (size_t)(p - (char *)big));
		else
			printf("OUTSIDE\n");
		free(big);
		free(little);
	}
	free(line);
	return (0);
}
