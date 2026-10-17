/* Live-differential reader harness for ft_strcmp (c-09 ex00 libft).
 * Line: <hexA>\t<hexB>\t<sign>. The two strings, two hex digits per
 * byte, then the SIGN of what ft_strcmp returned for them: -1, 0 or 1. man
 * strcmp promises a sign, and here only the sign is compared. See
 * tools/diffio.h. */
#include "diffio.h"

int	ft_strcmp(char *s1, char *s2);

int	main(void)
{
	char			line[8192];
	char			*f[3];
	unsigned char	*a;
	unsigned char	*b;
	int				r;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		a = dio_unhex(f[0], NULL, 0);
		b = dio_unhex(f[1], NULL, 0);
		r = ft_strcmp((char *)a, (char *)b);
		printf("%s\t%s\t%d\n", f[0], f[1], (r > 0) - (r < 0));
		free(a);
		free(b);
	}
	return (0);
}
