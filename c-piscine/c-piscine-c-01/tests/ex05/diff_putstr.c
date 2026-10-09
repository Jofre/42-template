/* Live-differential reader harness for ft_putstr.
 * Line: <hexstr>\t<rawstring>. Decodes the hex field, reprints <hexstr>\t, then
 * calls ft_putstr (which must write the raw bytes to fd 1), then a newline.
 * The reference emits the identical raw bytes as its output column, so a correct
 * ft_putstr makes the two byte-identical. Bodies never contain 0x00 or 0x0a.
 * See tools/diffio.h. */
#include "diffio.h"

void	ft_putstr(char *str);

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
		printf("%s\t", f[0]);
		fflush(stdout);
		ft_putstr((char *)s);
		printf("\n");
		free(s);
	}
	return (0);
}
