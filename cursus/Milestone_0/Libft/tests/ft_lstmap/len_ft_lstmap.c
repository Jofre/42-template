/* Length-series harness for ft_lstmap (perf, tools/perf_test.sh).
 *
 * Line: <csv>, comma-joined decimal ints in [-100000, 100000], of ANY length
 * -- the series grows one list -- so the line is read whole with getline(3).
 * The list handed over is one heap block of exactly the list's length, node i
 * holding a pointer to the i-th int, built by construction as diff_ft_lstmap.c
 * builds it, and f is that harness's: a new int, x*3-1 (the values are
 * bounded, so it fits).
 *
 * It CHECKS its own result, because nothing else compares these long outputs:
 * the new list has exactly n nodes, none of them the block's, and node i
 * holds a result of f's that del did not free, held by no other node, equal
 * to three times the i-th int, less one. The first wrong one is exit 3, and
 * the series reports that length as wrong rather than timing it. Nothing is
 * printed; perf_run discards stdout.
 *
 * Nothing is freed while the list is followed: the walk reads at most n + 1
 * nodes and records each in an array, and only a list found right is freed,
 * from that array and from f's own table of results. A right list has n
 * distinct nodes: a node met twice would repeat what follows it, so the list
 * could not end after n.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libft.h"

t_list	*ft_lstmap(t_list *lst, void *(*f)(void *), void (*del)(void *));

/* f's results in this case, in the order it made them, and the state of
 * each: 0 made, 1 freed by del, 2 held by a node of the new list. */
static int		**g_made;
static char		*g_state;
static size_t	g_nmade;
static size_t	g_room;

/* Which of f's results p is, the k-th tried first; -1 when it is none. */
static long	made(const void *p, size_t k)
{
	size_t	i;

	if (k < g_nmade && p == g_made[k])
		return ((long)k);
	i = 0;
	while (i < g_nmade && p != g_made[i])
		i++;
	return (i < g_nmade ? (long)i : -1);
}

/* The harness's f: a new int, three times the one content points to, less
 * one, noted so the harness can free it. */
static void	*f(void *content)
{
	int	*r;

	if (g_nmade == g_room)
	{
		g_room = g_room ? 2 * g_room : 64;
		g_made = realloc(g_made, g_room * sizeof(*g_made));
		g_state = realloc(g_state, g_room);
		if (g_made == NULL || g_state == NULL)
			exit(2);
	}
	r = malloc(sizeof(int));
	if (r == NULL)
		exit(2);
	*r = *(int *)content * 3 - 1;
	g_state[g_nmade] = 0;
	g_made[g_nmade++] = r;
	return (r);
}

/* The harness's del: frees a content f made, once. */
static void	del(void *content)
{
	long	i;

	i = made(content, 0);
	if (i >= 0 && g_state[i] == 0)
	{
		g_state[i] = 1;
		free(content);
	}
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

/* Whether the new list from res holds n nodes, none of the block's, node i
 * holding a live result of f's, its own, equal to tab[i] * 3 - 1, and ends
 * there. At most n + 1 nodes are read, each recorded in seen. */
static int	mapped_ok(t_list *res, const int *tab, int n, const t_list *blk,
	t_list **seen)
{
	int		k;
	long	m;

	k = 0;
	while (res != NULL && k < n + 1)
	{
		seen[k] = res;
		if (k == n || ((uintptr_t)res >= (uintptr_t)blk
				&& (uintptr_t)res < (uintptr_t)(blk + n)))
			return (0);
		m = made(res->content, (size_t)k);
		if (m < 0 || g_state[m] != 0 || *g_made[m] != tab[k] * 3 - 1)
			return (0);
		g_state[m] = 2;
		res = res->next;
		k++;
	}
	return (k == n && res == NULL);
}

int	main(void)
{
	char	*line;
	size_t	cap;
	ssize_t	got;
	int		*tab;
	t_list	*blk;
	t_list	**seen;
	int		n;
	int		i;
	char	*p;

	line = NULL;
	cap = 0;
	while ((got = getline(&line, &cap, stdin)) > 0)
	{
		if (line[got - 1] == '\n')
			line[got - 1] = '\0';
		n = count_csv(line);
		tab = (int *)malloc(sizeof(int) * (size_t)(n > 0 ? n : 1));
		blk = (t_list *)calloc((size_t)(n > 0 ? n : 1), sizeof(t_list));
		seen = (t_list **)calloc((size_t)n + 1, sizeof(t_list *));
		if (tab == NULL || blk == NULL || seen == NULL)
			return (2);
		p = line;
		i = 0;
		while (i < n)
		{
			tab[i] = (int)strtol(p, &p, 10);
			blk[i].content = &tab[i];
			if (i + 1 < n)
				blk[i].next = &blk[i + 1];
			i++;
			if (*p == ',')
				p++;
		}
		g_nmade = 0;
		if (!mapped_ok(ft_lstmap(n > 0 ? blk : NULL, &f, &del), tab, n, blk,
				seen))
			return (3);
		i = 0;
		while (i < n)
			free(seen[i++]);
		while (g_nmade > 0)
		{
			g_nmade--;
			if (g_state[g_nmade] != 1)
				free(g_made[g_nmade]);
		}
		free(seen);
		free(blk);
		free(tab);
	}
	free(g_made);
	free(g_state);
	free(line);
	return (0);
}
