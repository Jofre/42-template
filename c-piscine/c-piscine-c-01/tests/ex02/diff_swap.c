/* Live-differential reader harness for ft_swap.
 * Line: <a>\t<b>\t<newA>\t<newB> (ints). Reads a and b, swaps them, and
 * reprints <a>\t<b>\t<a'>\t<b'>. See tools/diffio.h. */
#include "diffio.h"

void	ft_swap(int *a, int *b);

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
		ft_swap(&a, &b);
		printf("%s\t%s\t%d\t%d\n", f[0], f[1], a, b);
	}
	return (0);
}
