/* Live-differential reader harness for ft_strcmp.
 * Line: <hexA>\t<hexB>\t<returned int>. The two strings, two hex digits per
 * byte, then what ft_strcmp returned for them, in decimal: the int itself, not
 * only its sign. See tools/diffio.h. */
#include "diffio.h"

int	ft_strcmp(char *s1, char *s2);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[3];
	unsigned char	*a;
	unsigned char	*b;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * strings past 4 KiB (finding 041), past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		a = dio_unhex(f[0], NULL, 0);
		b = dio_unhex(f[1], NULL, 0);
		printf("%s\t%s\t%d\n", f[0], f[1], ft_strcmp((char *)a, (char *)b));
		free(a);
		free(b);
	}
	free(line);
	return (0);
}
