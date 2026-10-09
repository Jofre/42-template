/* Length-series harness for ft_sort_int_tab (perf, tools/perf_test.sh).
 *
 * Line: <csv>, comma-joined decimal ints, of ANY length -- the series grows
 * one input (oracle `c01_sort_int_tab_len <seed> <cases> <length>`), so the
 * line is read whole with getline(3) and the array is a heap block of exactly
 * its size.
 *
 * It CHECKS its own result, because nothing else compares these long outputs:
 * ascending, and the same multiset of values as far as a sum can tell. The
 * first wrong one is exit 3, and the series reports that length as wrong
 * rather than timing it. Nothing is printed; perf_run discards stdout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void	ft_sort_int_tab(int *tab, int size);

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

int	main(void)
{
	char		*line;
	size_t		cap;
	ssize_t		got;
	int			*tab;
	int			n;
	int			i;
	char		*p;
	long long	before;
	long long	after;

	line = NULL;
	cap = 0;
	while ((got = getline(&line, &cap, stdin)) > 0)
	{
		if (line[got - 1] == '\n')
			line[got - 1] = '\0';
		n = count_csv(line);
		tab = (int *)malloc(sizeof(int) * (size_t)(n > 0 ? n : 1));
		if (tab == NULL)
			return (2);
		before = 0;
		p = line;
		i = 0;
		while (i < n)
		{
			tab[i] = (int)strtol(p, &p, 10);
			before += tab[i++];
			if (*p == ',')
				p++;
		}
		ft_sort_int_tab(tab, n);
		after = 0;
		i = 0;
		while (i < n)
		{
			if (i > 0 && tab[i - 1] > tab[i])
				return (3);
			after += tab[i++];
		}
		if (after != before)
			return (3);
		free(tab);
	}
	free(line);
	return (0);
}
