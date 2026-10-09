/* Live-differential reader harness for ft_ultimate_range.
 * Line: <min>\t<max>\t<returned size>\t<ints>. min and max in decimal, what
 * ft_ultimate_range returned, then the array it left in the int **
 * out-parameter, comma-joined -- NULL when that pointer is left NULL, and
 * UNTOUCHED when the function never wrote it.
 *
 * *range starts out pointing at a local sentinel, never at NULL, so a
 * function that leaves it alone prints UNTOUCHED -- which the reference never
 * prints -- where the subject says "range will point to NULL" (finding 076).
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
	int		sentinel;
	int		ret;
	int		i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		min = (int)strtol(f[0], NULL, 10);
		max = (int)strtol(f[1], NULL, 10);
		range = &sentinel;
		ret = ft_ultimate_range(&range, min, max);
		printf("%s\t%s\t%d\t", f[0], f[1], ret);
		if (range == &sentinel)
		{
			printf("UNTOUCHED\n");
			continue ;
		}
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
