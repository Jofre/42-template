/* Live-differential reader harness for ft_is_sort.
 * Line: <csv>\t<0|1>\t<csv-after-the-call>. csv = comma-joined decimal ints
 * ("" for size 0). The THIRD column is the array re-read after the call:
 * ft_is_sort must not reorder it, and that column is what checks it.
 * Fixed comparator cmp(a,b) = a - b (ascending; inputs are range-limited by the
 * reference so the subtraction never overflows int). Parses the array, calls
 * ft_is_sort, reprints <csv>\t<result>. See diffio.h. */
#include "diffio.h"

int	ft_is_sort(int *tab, int length, int (*f)(int, int));

static int	cmp_asc(int a, int b)
{
	return (a - b);
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
	int		res;
	int		i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 2)
			continue ;
		size = parse_csv(f[0], tab);
		res = ft_is_sort(tab, size, cmp_asc);
		printf("%s\t%d\t", f[0], !!res);
		/* re-echo tab AFTER the call: ft_is_sort is a pure query and must not
		 * reorder its input array. */
		i = 0;
		while (i < size)
		{
			if (i)
				printf(",");
			printf("%d", tab[i]);
			i++;
		}
		printf("\n");
	}
	return (0);
}
