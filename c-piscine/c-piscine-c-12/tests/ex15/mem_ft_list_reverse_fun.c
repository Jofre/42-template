/* Memory-safety probe for ft_list_reverse_fun — run under AddressSanitizer.
 * The probe says nothing about HOW to reverse; it only makes the memory honest
 * so that whatever you do is checked. Every node is its own heap block and
 * every data is a heap block of exactly its own size, so a read of a node or a
 * datum the function has already passed lands in a redzone instead of on
 * something that happens to still hold a plausible value.
 * Lengths 3, 2, 1 and 0 are all run, because a reversal that mishandles the
 * ends is usually still right for one of them — a single length proves little.
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
	t_list	*seen[4];
	int		k;
	int		i;

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
	t_list	*node[3];
	t_list	*b;
	int		n;

	n = 3;
	while (n >= 0)
	{
		b = build(node, n);
		ft_list_reverse_fun(b);
		free_list(b, n + 1);
		n--;
	}
	return (0);
}
