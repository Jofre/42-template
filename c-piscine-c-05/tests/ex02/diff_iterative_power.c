/* Live-differential reader harness for ft_iterative_power. Line: <nb>\t<power>. */
#include "diffio.h"

int	ft_iterative_power(int nb, int power);

int	main(void)
{
	char	line[256];
	char	*f[3];
	int		nb;
	int		power;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		nb = (int)strtol(f[0], NULL, 10);
		power = (int)strtol(f[1], NULL, 10);
		printf("%s\t%s\t%d\n", f[0], f[1], ft_iterative_power(nb, power));
	}
	return (0);
}
