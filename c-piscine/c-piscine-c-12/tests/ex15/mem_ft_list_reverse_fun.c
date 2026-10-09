/* Memory-safety probe for ft_list_reverse_fun — run under AddressSanitizer.
 * The probe says nothing about HOW to reverse; it only makes the memory honest
 * so that whatever you do is checked. Every node is its own heap block and
 * every data is a heap block of exactly its own size, so a read of a node or a
 * datum the function has already passed lands in a redzone instead of on
 * something that happens to still hold a plausible value.
 * Lengths 3, 2, 1 and 0 are all run, because a reversal that mishandles the
 * ends is usually still right for one of them — a single length proves little.
 * So are 300 and 5000, past every capacity a copy is usually given (16, 64,
 * 256, 1024, 4096): the subject bounds no length, and a function that works
 * through room of its own fixed size writes past its end there (finding 041).
 * Note the caller's head pointer is what is freed afterwards, so whatever the
 * function does must leave that pointer usable.
 * This is a test input, not an implementation. */
#include "ft_list.h"
#include <stdlib.h>

/* Free what the caller's head reaches -- node and datum -- reading at most
 * `cap` nodes: the length built, plus one. Every node is recorded before any
 * is freed, so nothing is read after it has been released. The record is
 * deliberately NOT de-duplicated: a node reached twice, or a datum now held by
 * two nodes, is released twice, which ASan reports -- exactly what this probe
 * is for. */
static void	free_list(t_list *b, int cap)
{
	t_list	**seen;
	int		k;
	int		i;

	seen = malloc(sizeof(t_list *) * cap);
	if (seen == NULL)
		exit(2);
	k = 0;
	while (b != NULL && k < cap)
	{
		seen[k++] = b;
		b = b->next;
	}
	i = 0;
	while (i < k)
	{
		free(seen[i]->data);
		free(seen[i]);
		i++;
	}
	free(seen);
}

/* The probe's list, built by construction: n nodes, node i holding a malloc'd
 * int i and linked to node i + 1 by index; calloc leaves the last node's next
 * NULL. Each node and each int is its own heap block. */
static t_list	*build(t_list **node, int n)
{
	int	i;

	if (n == 0)
		return (NULL);
	i = 0;
	while (i < n)
	{
		node[i] = calloc(1, sizeof(t_list));
		node[i]->data = malloc(sizeof(int));
		*(int *)node[i]->data = i;
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
	static const int	lens[] = {3, 2, 1, 0, 300, 5000};
	t_list				**node;
	t_list				*b;
	int					n;
	size_t				k;

	k = 0;
	while (k < sizeof(lens) / sizeof(lens[0]))
	{
		n = lens[k];
		node = malloc(sizeof(t_list *) * (n + 1));
		if (node == NULL)
			return (2);
		b = build(node, n);
		ft_list_reverse_fun(b);
		free_list(b, n + 1);
		free(node);
		k++;
	}
	return (0);
}
