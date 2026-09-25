/* Live-differential reader harness for ft_strlen.
 * Line: <hexstr>\t<len>. Decodes the hex field, reprints <hexstr>\t, then the
 * student's ft_strlen result. Bodies never contain 0x00. See tools/diffio.h. */
#include "diffio.h"

int	ft_strlen(char *str);

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
		printf("%s\t%d\n", f[0], ft_strlen((char *)s));
		free(s);
	}
	return (0);
}
