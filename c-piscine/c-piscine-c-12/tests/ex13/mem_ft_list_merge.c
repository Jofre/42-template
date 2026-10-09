/* Memory-safety probe for ft_list_merge — run under AddressSanitizer.
 * ft_list_merge puts the second list at the end of the first and takes no copy:
 * afterwards the two lists are ONE list of the same nodes, so every node must
 * still be reachable exactly once and none may have been freed or duplicated.
 * Every node here is its own heap block, and the merged result is freed once,
 * through the caller's head: the nodes that head reaches are recorded first and
 * freed from the record -- so a node linked twice is released twice, which
 * ASan reports as a use-after-free or a double free, and a walk that runs past
 * the end of either list shows up as a heap-buffer-overflow. (A node dropped
 * from the chain is simply never freed; leaks are not this layer's finding.)
 * The empty cases are the interesting ones and are run in both orders: an empty
 * first list has no last node to attach to, and an empty second list must not
 * disturb the first.
 * This is a test input, not an implementation. */
#include "ft_list.h"
#include <stdlib.h>

/* One of the probe's lists, built by construction: n nodes, node i holding a
 * malloc'd int base + i and linked to node i + 1 by index; calloc leaves the
 * last node's next NULL. Each node and each int is its own heap block. */
static t_list	*build(t_list **node, int n, int base)
{
	int	i;

	if (n == 0)
		return (NULL);
	i = 0;
	while (i < n)
	{
		node[i] = calloc(1, sizeof(t_list));
		node[i]->data = malloc(sizeof(int));
		*(int *)node[i]->data = base + i;
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

/* Free what the caller's head reaches -- node and int -- reading at most `cap`
 * nodes: both lengths together, plus one. Every node is recorded before any is
 * freed, so nothing is read after it has been released. The record is
 * deliberately NOT de-duplicated: a node reached twice is released twice, and
 * that is exactly the report this probe exists to raise. */
static void	free_list(t_list *b, int cap)
{
	t_list	*seen[6];
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

static void	call_case(int n1, int n2)
{
	t_list	*na[3];
	t_list	*nb[2];
	t_list	*a;

	a = build(na, n1, 0);
	ft_list_merge(&a, build(nb, n2, 100));
	free_list(a, n1 + n2 + 1);
}

int	main(void)
{
	call_case(3, 2);
	call_case(1, 1);
	call_case(0, 2);
	call_case(2, 0);
	call_case(0, 0);
	return (0);
}
