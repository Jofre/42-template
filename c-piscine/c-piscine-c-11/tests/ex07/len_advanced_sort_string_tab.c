/* Length-series harness for ft_advanced_sort_string_tab (perf,
 * tools/perf_test.sh).
 *
 * Line: <csv>, comma-joined strings of a small alphabet, of ANY length -- the
 * series grows one array (oracle `c11_advanced_sort_string_tab_len <seed>
 * <cases> <length>`), so the line is read whole with getline(3) and the array
 * is a heap block of exactly its size plus the NULL that ends it.
 *
 * It CHECKS its own result, because nothing else compares these long outputs:
 * the array still ends at its NULL, every pair is in order by the comparator
 * it was handed (strcmp(3)), and it holds the same strings, as far as a sum of
 * their bytes and of their lengths can tell. The first wrong one is exit 3,
 * and the series reports that length as wrong rather than timing it. Nothing
 * is printed; perf_run discards stdout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void	ft_advanced_sort_string_tab(char **tab, int (*cmp)(char *, char *));

/* The comparator handed to the function: strcmp(3), so its order is checked
 * with strcmp too. */
static int	by_strcmp(char *a, char *b)
{
	return (strcmp(a, b));
}

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

static long long	weigh(char **tab, int n)
{
	long long	w;
	int			i;
	int			j;

	w = 0;
	i = 0;
	while (i < n)
	{
		j = 0;
		while (tab[i][j])
			w += (unsigned char)tab[i][j++] * 31 + 7;
		w += j * 1000003LL;
		i++;
	}
	return (w);
}

int	main(void)
{
	char		*line;
	size_t		cap;
	ssize_t		got;
	char		**tab;
	int			n;
	int			i;
	long long	before;

	line = NULL;
	cap = 0;
	while ((got = getline(&line, &cap, stdin)) > 0)
	{
		if (line[got - 1] == '\n')
			line[got - 1] = '\0';
		n = count_csv(line);
		tab = (char **)malloc(sizeof(char *) * (size_t)(n + 1));
		if (tab == NULL)
			return (2);
		i = 0;
		tab[i] = strtok(line, ",");
		while (tab[i] != NULL)
			tab[++i] = strtok(NULL, ",");
		if (i != n)
			return (2);
		before = weigh(tab, n);
		ft_advanced_sort_string_tab(tab, &by_strcmp);
		if (tab[n] != NULL || weigh(tab, n) != before)
			return (3);
		i = 1;
		while (i < n)
		{
			if (strcmp(tab[i - 1], tab[i]) > 0)
				return (3);
			i++;
		}
		free(tab);
	}
	free(line);
	return (0);
}
