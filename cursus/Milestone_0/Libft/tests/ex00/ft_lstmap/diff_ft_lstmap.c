/* Live-differential reader harness for ft_lstmap.
 * Line: <csv>\t<result-csv>. Builds the list of the comma-joined ints, node
 * i's content a pointer to the i-th int, maps it with the harness's f -- a new
 * int from malloc(3), x*3-1 for the int x a content points to -- and reprints
 * the input and the new list's ints, comma-joined, first node first (empty
 * for a NULL result). The values stay within 1000000 of 0, so x*3-1 fits an
 * int. */
#include <stdint.h>
#include "libft.h"
#include "diffio.h"

t_list	*ft_lstmap(t_list *lst, void *(*f)(void *), void (*del)(void *));

/* f's results in this case, in the order it made them, and which del freed. */
static int		**g_made;
static char		*g_freed;
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
		g_freed = realloc(g_freed, g_room);
		if (g_made == NULL || g_freed == NULL)
			dio_fail("out of memory for f's results");
	}
	r = malloc(sizeof(int));
	if (r == NULL)
		dio_fail("out of memory for f's result");
	*r = *(int *)content * 3 - 1;
	g_freed[g_nmade] = 0;
	g_made[g_nmade++] = r;
	return (r);
}

/* The harness's del: frees a content f made, once. */
static void	del(void *content)
{
	long	i;

	i = made(content, 0);
	if (i >= 0 && !g_freed[i])
	{
		g_freed[i] = 1;
		free(content);
	}
}

/* Whether node p is one of the n nodes of blk. */
static int	ours(const t_list *p, const t_list *blk, int n)
{
	int	i;

	i = 0;
	while (i < n && p != &blk[i])
		i++;
	return (i < n);
}

/* The new list from res, its ints comma-joined, reading at most n + 1 nodes;
 * a content del has freed is named, never read. Each node read that is not
 * one of blk's is recorded in seen, and how many returned, so the caller
 * frees them. */
static int	ser(t_list *res, const t_list *blk, int n, t_list **seen)
{
	int		k;
	int		j;
	long	m;

	k = 0;
	while (res != NULL && k < n + 1)
	{
		if (k > 0)
			printf(",");
		m = made(res->content, (size_t)k);
		if (m >= 0 && g_freed[m])
			printf("(a content del freed)");
		else if (m >= 0)
			printf("%d", *g_made[m]);
		else
			printf("(a content f did not make)");
		j = 0;
		while (j < k && seen[j] != res)
			j++;
		if (!ours(res, blk, n) && j == k)
			seen[k] = res;
		else
			seen[k] = NULL;
		k++;
		res = res->next;
	}
	if (res != NULL)
		printf(",...(list still going after %d nodes)", n + 1);
	printf("\n");
	return (k);
}

int	main(void)
{
	char	*line;
	size_t	cap;
	/* conventions: bounded -- dio_split never fills more than its count, 2 */
	char	*fl[2];
	int		*tab;
	int		n;
	int		i;
	int		k;
	t_list	*blk;
	t_list	**seen;

	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, fl, 2) < 1)
			continue ;
		tab = dio_csv_ints(fl[0], &n);
		blk = (t_list *)dio_alloc((size_t)n, sizeof(t_list));
		seen = (t_list **)dio_alloc((size_t)n + 1, sizeof(t_list *));
		i = 0;
		while (i < n)
		{
			blk[i].content = &tab[i];
			if (i + 1 < n)
				blk[i].next = &blk[i + 1];
			i++;
		}
		g_nmade = 0;
		printf("%s\t", fl[0]);
		k = ser(ft_lstmap(n > 0 ? blk : NULL, &f, &del), blk, n, seen);
		while (k-- > 0)
			free(seen[k]);
		while (g_nmade > 0)
		{
			g_nmade--;
			if (!g_freed[g_nmade])
				free(g_made[g_nmade]);
		}
		free(seen);
		free(blk);
		free(tab);
	}
	free(g_made);
	free(g_freed);
	free(line);
	return (0);
}
