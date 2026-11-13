/* Live-differential reader harness for ft_strstr.
 * Line: <hexHay>\t<hexNeedle>\t<off|NULL>. The haystack and the needle, two
 * hex digits per byte, then where the returned pointer points: its offset
 * from the start of the haystack, in decimal, NULL, or OUTSIDE for a pointer
 * that is neither into the haystack nor at its terminator. */
#include "diffio.h"

char	*ft_strstr(char *str, char *to_find);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[3];
	unsigned char	*hay;
	unsigned char	*needle;
	size_t			hlen;
	char			*p;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB (finding 041), past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		dio_fields(line, f, 3, 2);
		hay = dio_unhex(f[0], &hlen, 0);
		needle = dio_unhex(f[1], NULL, 0);
		p = ft_strstr((char *)hay, (char *)needle);
		printf("%s\t%s\t", f[0], f[1]);
		if (!p)
			printf("NULL\n");
		else if (p >= (char *)hay && p <= (char *)hay + hlen)
			printf("%zu\n", (size_t)(p - (char *)hay));
		else
			printf("OUTSIDE\n");
		free(hay);
		free(needle);
	}
	free(line);
	return (0);
}
