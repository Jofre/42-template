/* Live-differential reader harness for ft_lstclear.
 * Line: <csv>\t<delCount>\t<headNull>. Builds the list of the comma-joined
 * ints, each node its own heap block (the function frees them one by one)
 * whose content is the int carried as (void *)(intptr_t)v, clears it, and
 * reprints the input, how many times del was called, and 1 when the pointer
 * to the list holds NULL afterwards (0 when it does not). */
#include <stdint.h>
#include "libft.h"
#include "diffio.h"

void	ft_lstclear(t_list **lst, void (*del)(void *));

static long	g_calls;

/* The harness's del: the contents are ints, not blocks, so there is nothing
 * to free; it counts its calls. */
static void	del(void *content)
{
	(void)content;
	g_calls++;
}

/* The case's list: n nodes in node[0 .. n - 1], each its own heap block of
 * exactly one t_list, node i holding tab[i] and linked to node i + 1; NULL
 * when n is 0. Nothing here frees the nodes: that is the function's job, and a
 * node it leaves behind is the valgrind layer's question, not this one's. */
static t_list	*build(t_list **node, int *tab, int n)
{
	int	i;

	if (n == 0)
		return (NULL);
	i = 0;
	while (i < n)
	{
		node[i] = (t_list *)dio_alloc(1, sizeof(t_list));
		node[i]->content = (void *)(intptr_t)tab[i];
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
	char	*f[3];
	int		*tab;
	int		n;
	t_list	**node;
	t_list	*lst;

	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, f, 3) < 1)
			continue ;
		tab = dio_csv_ints(f[0], &n);
		node = (t_list **)dio_alloc((size_t)n, sizeof(t_list *));
		lst = build(node, tab, n);
		g_calls = 0;
		ft_lstclear(&lst, &del);
		printf("%s\t%ld\t%d\n", f[0], g_calls, lst == NULL);
		free(node);
		free(tab);
	}
	free(line);
	return (0);
}
