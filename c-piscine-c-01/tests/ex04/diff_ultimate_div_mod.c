/* Live-differential reader harness for ft_ultimate_div_mod.
 * Line: <a>\t<b>\t<newA>\t<newB>. Reads a and b, calls ft_ultimate_div_mod
 * (which sets *a = a/b and *b = a%b in place), and reprints
 * <a>\t<b>\t<a'>\t<b'>. Inputs never trigger C UB. See tools/diffio.h. */
#include "diffio.h"

void	ft_ultimate_div_mod(int *a, int *b);

int	main(void)
{
	char	line[8192];
	char	*f[4];
	int		a;
	int		b;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 4) < 2)
			continue ;
		a = (int)strtol(f[0], NULL, 10);
		b = (int)strtol(f[1], NULL, 10);
		ft_ultimate_div_mod(&a, &b);
		printf("%s\t%s\t%d\t%d\n", f[0], f[1], a, b);
	}
	return (0);
}
