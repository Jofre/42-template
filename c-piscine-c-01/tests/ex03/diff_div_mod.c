/* Live-differential reader harness for ft_div_mod.
 * Line: <a>\t<b>\t<div>\t<mod>. Reads a and b, calls ft_div_mod, and reprints
 * <a>\t<b>\t<div>\t<mod>. Inputs never trigger C UB (b != 0, never INT_MIN/-1).
 * See tools/diffio.h. */
#include "diffio.h"

void	ft_div_mod(int a, int b, int *div, int *mod);

int	main(void)
{
	char	line[8192];
	char	*f[4];
	int		a;
	int		b;
	int		d;
	int		m;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 4) < 2)
			continue ;
		a = (int)strtol(f[0], NULL, 10);
		b = (int)strtol(f[1], NULL, 10);
		d = 0;
		m = 0;
		ft_div_mod(a, b, &d, &m);
		printf("%s\t%s\t%d\t%d\n", f[0], f[1], d, m);
	}
	return (0);
}
