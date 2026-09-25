/* Live-differential reader harness for ft_str_is_lowercase.
 * Line: <hexStr>\t<0|1>. Reprints <hexStr>\t<student predicate result>. */
#include "diffio.h"

int	ft_str_is_lowercase(char *str);

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
		printf("%s\t%d\n", f[0], ft_str_is_lowercase((char *)s));
		free(s);
	}
	return (0);
}
