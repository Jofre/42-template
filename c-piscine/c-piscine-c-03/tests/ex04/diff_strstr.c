/* Live-differential reader harness for ft_strstr.
 * Line: <hexHay>\t<hexNeedle>\t<hexTail>. The haystack and the needle, two
 * hex digits per byte, then what the returned pointer points at, up to its
 * NUL, as hex -- or NULL when ft_strstr returned NULL. */
#include "diffio.h"

char	*ft_strstr(char *str, char *to_find);

int	main(void)
{
	char			line[8192];
	char			*f[3];
	unsigned char	*hay;
	unsigned char	*needle;
	char			*p;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		hay = dio_unhex(f[0], NULL, 0);
		needle = dio_unhex(f[1], NULL, 0);
		p = ft_strstr((char *)hay, (char *)needle);
		printf("%s\t%s\t", f[0], f[1]);
		if (!p)
			printf("NULL");
		else
			dio_puthex((unsigned char *)p, strlen(p));
		printf("\n");
		free(hay);
		free(needle);
	}
	return (0);
}
