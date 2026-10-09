/* Live-differential reader harness for ft_atoi.
 * Line: <hexStr>\t<returned int>. The string, two hex digits per byte, then
 * what ft_atoi returned for it, in decimal. */
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
