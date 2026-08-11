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

static int	parse_csv(char *s, int *tab)
{
	int		n;
	char	*p;

	n = 0;
	p = s;
	while (*p)
	{
		tab[n++] = (int)strtol(p, &p, 10);
		if (*p == ',')
			p++;
	}
	return (n);
}

int	main(void)
{
	char	line[8192];
	char	*f[2];
	int		tab[64];
	int		size;
	int		i;
	int		*res;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		size = parse_csv(f[0], tab);
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
	}
	return (0);
}
