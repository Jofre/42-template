/* Live-differential reader harness for ft_range.
 * Line: <min>\t<max>. Prints the (max-min) returned ints comma-joined, or NULL
 * when the function returns NULL. See tools/diffio.h. */
#include "diffio.h"

int	*ft_range(int min, int max);

int	main(void)
{
	char	line[8192];
	char	*f[3];
	int		min;
	int		max;
	int		*tab;
	int		i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		min = (int)strtol(f[0], NULL, 10);
		max = (int)strtol(f[1], NULL, 10);
		tab = ft_range(min, max);
		printf("%s\t%s\t", f[0], f[1]);
		if (!tab)
			printf("NULL");
		else
		{
			i = 0;
			while (i < max - min)
			{
				printf("%s%d", i ? "," : "", tab[i]);
				i++;
			}
		}
		printf("\n");
		free(tab);
	}
	return (0);
}
