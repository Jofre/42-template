/* Live-differential reader harness for ft_map.
 * Line: <csv>\t<mapped-csv>\t<csv-after-the-call>. The THIRD column is the
 * input array re-read after the call: ft_map returns a NEW array and must
 * leave its input untouched. Fixed transform f(x) = x*3 - 1 (inputs are
 * range-limited by the reference so this never overflows int). Parses the
 * array, calls ft_map, reprints <csv>\t<mapped-csv>. See diffio.h. */
#include "diffio.h"

int	*ft_map(int *tab, int length, int (*f)(int));

static int	triple(int x)
{
	return (x * 3 - 1);
}

int	main(void)
{
	char	*line;
	size_t	linecap;
	char	*f[2];
	int		*tab;
	int		size;
	int		i;
	int		*res;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * arrays of 5000 ints (finding 041), past what a line buffer holds. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		tab = dio_csv_ints(f[0], &size);
		res = ft_map(tab, size, triple);
		printf("%s\t", f[0]);
		if (res)
		{
			i = 0;
			while (i < size)
			{
				if (i)
					printf(",");
				printf("%d", res[i]);
				i++;
			}
		}
		else
			printf("NULL");
		/* re-echo tab AFTER the call: ft_map returns a NEW array and must
		 * leave its input untouched. */
		printf("\t");
		i = 0;
		while (i < size)
		{
			if (i)
				printf(",");
			printf("%d", tab[i]);
			i++;
		}
		printf("\n");
		free(res);
		free(tab);
	}
	free(line);
	return (0);
}
