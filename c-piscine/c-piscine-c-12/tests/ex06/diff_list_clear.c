/* Live-differential reader harness for ft_list_clear.
 * Line: <csv>\t<freeCount>. Builds a list (data = (void*)(intptr_t)v), clears
 * it with a free_fct that only tallies how many times it is invoked, and
 * reprints <csv>\t<count>. A correct clear calls free_fct once per element,
 * so the count equals the list size. */
#include "ft_list.h"
#include "diffio.h"
#include <stdint.h>

void	ft_list_clear(t_list *begin_list, void (*free_fct)(void *));

static int	g_freed;

static void	count_free(void *data)
{
	(void)data;
	g_freed++;
}

/* The case's list, built by construction: n nodes, node i carrying tab[i] and
 * linked to node i + 1 by index; calloc leaves the last node's next NULL. Each
 * node is its own calloc'd block because ft_list_clear frees them one at a
 * time, so they cannot share one. `node` only holds the pointers while they are
 * linked: the list is the function's to free, and nothing here frees it. */
static t_list	*build_ip(t_list **node, int *tab, int n)
{
	int	i;

	if (n == 0)
		return (NULL);
	i = 0;
	while (i < n)
	{
		node[i] = calloc(1, sizeof(t_list));
		node[i]->data = (void *)(intptr_t)tab[i];
		i++;
	}
	i = 0;
	while (i + 1 < n)
	{
		node[i]->next = node[i + 1];
		i++;
	}
	return (node[0]);
}

int	main(void)
{
	char	*line;
	size_t	cap;
	char	*f[2];
	int		*tab;
	int		n;
	t_list	**node;
	t_list	*begin;

	/* A line of any length (tools/diffio.h): the corpus holds lists and
	 * trees of hundreds and thousands of nodes (finding 041). */
	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		tab = dio_csv_ints(f[0], &n);
		node = (t_list **)dio_alloc((size_t)n, sizeof(t_list *));
		begin = build_ip(node, tab, n);
		g_freed = 0;
		ft_list_clear(begin, &count_free);
		printf("%s\t%d\n", f[0], g_freed);
		free(node);
		free(tab);
	}
	free(line);
	return (0);
}
