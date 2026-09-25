/* Live-differential reader harness for ft_ultimate_range.
 * Line: <min>\t<max>. Prints the returned size, then the array through the
 * int** out-parameter comma-joined (or NULL when the pointer is left NULL).
 * See tools/diffio.h. */
#include "diffio.h"

int	ft_ultimate_range(int **range, int min, int max);

int	main(void)
{
	char	line[8192];
	char	*f[3];
	int		min;
	int		max;
	int		*range;
	int		ret;
	int		i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		min = (int)strtol(f[0], NULL, 10);
		max = (int)strtol(f[1], NULL, 10);
		range = NULL;
		ret = ft_ultimate_range(&range, min, max);
		printf("%s\t%s\t%d\t", f[0], f[1], ret);
		if (!range)
			printf("NULL");
		else
		{
			i = 0;
			while (i < ret)
			{
				printf("%s%d", i ? "," : "", range[i]);
				i++;
			}
		}
		printf("\n");
		free(range);
	}
	return (0);
}
