/* Live-differential reader harness for ft_putnbr. Reference line:
 *   <n>\t<printed-decimal>
 * Reprints "<n>\t" then lets ft_putnbr write() its digits, then "\n", so the
 * whole line matches the reference byte-for-byte for a correct impl. */
#include "diffio.h"

void	ft_putnbr(int nb);

int	main(void)
{
	char	line[8192];
	char	*f[2];
	int		n;

	setbuf(stdout, NULL);
	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		n = (int)strtol(f[0], NULL, 10);
		printf("%s\t", f[0]);
		ft_putnbr(n);
		printf("\n");
	}
	return (0);
}
