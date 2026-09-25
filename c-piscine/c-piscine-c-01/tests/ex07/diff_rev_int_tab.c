/* Live-differential reader harness for ft_rev_int_tab.
 * Line: <csv>\t<reversed-csv>, csv = comma-joined decimal ints ("" for size 0).
 * Parses the array, calls ft_rev_int_tab in place, and reprints
 * <csv>\t<result-csv>. See tools/diffio.h. */
#include "diffio.h"

void	ft_rev_int_tab(int *tab, int size);

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

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		size = parse_csv(f[0], tab);
		ft_rev_int_tab(tab, size);
		printf("%s\t", f[0]);
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
