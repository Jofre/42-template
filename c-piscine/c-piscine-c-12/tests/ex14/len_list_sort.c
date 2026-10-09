/* Length-series harness for ft_list_sort (perf, tools/perf_test.sh).
 *
 * Line: <csv>, comma-joined decimal ints in [-100000, 100000], of ANY length
 * -- the series grows one list (oracle `c12_list_sort_len <seed> <cases>
 * <length>`), so the line is read whole with getline(3) and the nodes are one
 * heap block of exactly the list's length, built by construction as
 * diff_list_sort.c builds them, with the same comparator (the values are
 * bounded so *a - *b never overflows).
 *
 * It CHECKS its own result, because nothing else compares these long outputs:
 * the list still has its n nodes and ends there, ascending, and the same values
 * as far as a sum can tell. The first wrong one is exit 3, and the series
 * reports that length as wrong rather than timing it. Nothing is printed;
 * perf_run discards stdout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ft_list.h"

void	ft_list_sort(t_list **begin_list, int (*cmp)());

static int	cmp_int(void *a, void *b)
{
	return (*(int *)a - *(int *)b);
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

/* Whether the list holds n nodes, ascending, summing to `want`. */
static int	sorted_ok(t_list *l, int n, long long want)
{
	long long	sum;
	int			k;
	int			prev;

	sum = 0;
	k = 0;
	prev = 0;
	while (l && k <= n)
	{
		if (k > 0 && prev > *(int *)l->data)
			return (0);
		prev = *(int *)l->data;
		sum += prev;
		k++;
		l = l->next;
	}
	return (l == NULL && k == n && sum == want);
}

int	main(void)
{
	char		*line;
	size_t		cap;
	ssize_t		got;
	int			*tab;
	t_list		*blk;
	t_list		*begin;
	int			n;
	int			i;
	char		*p;
	long long	sum;

	line = NULL;
	cap = 0;
	while ((got = getline(&line, &cap, stdin)) > 0)
	{
		if (line[got - 1] == '\n')
			line[got - 1] = '\0';
		n = count_csv(line);
		tab = (int *)malloc(sizeof(int) * (size_t)(n > 0 ? n : 1));
		blk = (t_list *)calloc((size_t)(n > 0 ? n : 1), sizeof(t_list));
		if (tab == NULL || blk == NULL)
			return (2);
		sum = 0;
		p = line;
		i = 0;
		while (i < n)
		{
			tab[i] = (int)strtol(p, &p, 10);
			sum += tab[i];
			blk[i].data = &tab[i];
			if (i + 1 < n)
				blk[i].next = &blk[i + 1];
			i++;
			if (*p == ',')
				p++;
		}
		begin = n > 0 ? blk : NULL;
		ft_list_sort(&begin, &cmp_int);
		if (!sorted_ok(begin, n, sum))
			return (3);
		free(blk);
		free(tab);
	}
	free(line);
	return (0);
}
