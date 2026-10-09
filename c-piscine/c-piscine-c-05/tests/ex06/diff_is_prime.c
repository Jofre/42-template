/* Live-differential reader harness for ft_is_prime.
 * Line: <nb>\t<returned int>. The input as the reference wrote it, then what
 * ft_is_prime returned for it, in decimal. See tools/diffio.h. */
#include "diffio.h"

int	ft_is_prime(int nb);

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
		printf("%s\t%d\n", f[0], ft_is_prime(nb));
	}
	return (0);
}
