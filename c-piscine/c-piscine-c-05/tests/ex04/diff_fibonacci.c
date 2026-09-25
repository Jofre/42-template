/* Live-differential reader harness for ft_fibonacci. Line: <index>. */
#include "diffio.h"

int	ft_fibonacci(int index);

int	main(void)
{
	char	line[256];
	char	*f[2];
	int		index;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		index = (int)strtol(f[0], NULL, 10);
		printf("%s\t%d\n", f[0], ft_fibonacci(index));
	}
	return (0);
}
