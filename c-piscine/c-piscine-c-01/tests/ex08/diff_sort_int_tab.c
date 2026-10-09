/* Live-differential reader harness for ft_sort_int_tab.
 * Line: <csv>\t<sorted-csv>, csv = comma-joined decimal ints ("" for size 0).
 * Parses the array, calls ft_sort_int_tab in place (ascending), and reprints
 * <csv>\t<result-csv>. See tools/diffio.h. */
#include "diffio.h"

void	ft_sort_int_tab(int *tab, int size);

/* How many ints the csv holds: one more than its commas, none when empty. */
static int	count_csv(const char *s)
{
	int	n;

	if (*s == '\0')
		return (0);
	n = 1;
	while ((s = strchr(s, ',')) != NULL)
	{
		n++;
		s++;
	}
	return (n);
}

static void	parse_csv(char *s, int *tab, int n)
{
	int		i;
	char	*p;

	i = 0;
	p = s;
	while (i < n)
	{
		tab[i++] = (int)strtol(p, &p, 10);
		if (*p == ',')
			p++;
	}
}

/* The array is a HEAP BLOCK of exactly `size` ints, sized from the case
 * itself, and the line is read whole however long it is (dio_getline). The
 * corpus holds arrays of thousands of ints, past every capacity a student
 * might pick (finding 041); a fixed tab[64] here overflowed on the first of
 * them, and a line[8192] cut it in two. Exact-size, size 0 included, so
 * under ASan (exNN_diff_asan) one step past the end is caught at the edge of
 * the array itself. */
int	main(void)
{
	char	*line;
	size_t	cap;
	char	*f[2];
	int		*tab;
	int		size;
	int		i;

	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		size = count_csv(f[0]);
		tab = (int *)malloc(sizeof(int) * (size_t)size);
		if (tab == NULL && size > 0)
			return (2);
		parse_csv(f[0], tab, size);
		ft_sort_int_tab(tab, size);
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
		free(tab);
	}
	free(line);
	return (0);
}
