/* Live-differential reader harness for ft_atoi. Reference line:
 *   <hexstr>\t<int>
 * Decodes the string, reprints "<hexstr>\t<student int>". */
#include "diffio.h"

int	ft_atoi(char *str);

int	main(void)
{
	char			line[8192];
	char			*f[2];
	unsigned char	*s;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		s = dio_unhex(f[0], NULL, 0);
		printf("%s\t%d\n", f[0], ft_atoi((char *)s));
		free(s);
	}
	return (0);
}
