/* Live-differential reader harness for ft_atoi_base. Reference line:
 *   <hexstr>\t<hexbase>\t<int>
 * Decodes str and base, reprints "<hexstr>\t<hexbase>\t<student int>". */
#include "diffio.h"

int	ft_atoi_base(char *str, char *base);

int	main(void)
{
	char			line[8192];
	char			*f[3];
	unsigned char	*s;
	unsigned char	*base;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		s = dio_unhex(f[0], NULL, 0);
		base = dio_unhex(f[1], NULL, 0);
		printf("%s\t%s\t%d\n", f[0], f[1], ft_atoi_base((char *)s, (char *)base));
		free(s);
		free(base);
	}
	return (0);
}
