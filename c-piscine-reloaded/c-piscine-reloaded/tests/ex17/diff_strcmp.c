/* Live-differential reader harness for ft_strcmp. Reads reference cases
 *   <hexA>\t<hexB>[\t...]
 * from stdin and reprints <hexA>\t<hexB>\t<student result>. See tools/diffio.h. */
#include "diffio.h"

int	ft_strcmp(char *s1, char *s2);

int	main(void)
{
	char			line[8192];
	char			*f[3];
	unsigned char	*a;
	unsigned char	*b;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		a = dio_unhex(f[0], NULL, 0);
		b = dio_unhex(f[1], NULL, 0);
		printf("%s\t%s\t%d\n", f[0], f[1], ft_strcmp((char *)a, (char *)b));
		free(a);
		free(b);
	}
	return (0);
}
