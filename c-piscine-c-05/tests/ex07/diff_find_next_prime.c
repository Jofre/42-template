/* Live-differential reader harness for ft_find_next_prime. Line: <nb>. */
#include "diffio.h"

int	ft_find_next_prime(int nb);

int	main(void)
{
	char	line[256];
	char	*f[2];
	int		nb;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		nb = (int)strtol(f[0], NULL, 10);
		printf("%s\t%d\n", f[0], ft_find_next_prime(nb));
	}
	return (0);
}
