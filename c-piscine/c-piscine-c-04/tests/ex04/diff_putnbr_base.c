/* Live-differential reader harness for ft_putnbr_base.
 * Line: <n>\t<hexBase>\t<what it wrote>. The int in decimal, the base, two
 * hex digits per byte, then the bytes ft_putnbr_base wrote to fd 1, as they
 * are (empty when it wrote nothing).
 *
 * Reprints "<n>\t<hexbase>\t", lets ft_putnbr_base write() its output, then
 * "\n". A base never holds whitespace, '+' or '-', so the printed column never
 * holds a tab or a newline and never disturbs the line. */
#include "diffio.h"

void	ft_putnbr_base(int nbr, char *base);

int	main(void)
{
	char			line[8192];
	char			*f[3];
	unsigned char	*base;
	int				n;

	setbuf(stdout, NULL);
	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		n = (int)strtol(f[0], NULL, 10);
		base = dio_unhex(f[1], NULL, 0);
		printf("%s\t%s\t", f[0], f[1]);
		ft_putnbr_base(n, (char *)base);
		printf("\n");
		free(base);
	}
	return (0);
}
