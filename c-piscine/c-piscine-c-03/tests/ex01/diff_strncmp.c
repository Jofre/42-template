/* Live-differential reader harness for ft_strncmp.
 * Line: <hexA>\t<hexB>\t<n>\t<returned int>. The two strings, two hex digits
 * per byte, n in decimal, then what ft_strncmp returned for them, in decimal:
 * the int itself, not only its sign. See tools/diffio.h. */
#include "diffio.h"

int	ft_strncmp(char *s1, char *s2, unsigned int n);

int	main(void)
{
	char			line[8192];
	char			*f[4];
	unsigned char	*a;
	unsigned char	*b;
	unsigned int	n;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 4) < 3)
			continue ;
		a = dio_unhex(f[0], NULL, 0);
		b = dio_unhex(f[1], NULL, 0);
		n = (unsigned int)strtoul(f[2], NULL, 10);
		printf("%s\t%s\t%s\t%d\n", f[0], f[1], f[2],
			ft_strncmp((char *)a, (char *)b, n));
		free(a);
		free(b);
	}
	return (0);
}
