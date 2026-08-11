/* Memory-safety probe for ft_list_merge — run under AddressSanitizer.
 * ft_list_merge puts the second list at the end of the first and takes no copy:
 * afterwards the two lists are ONE list of the same nodes, so every node must
 * still be reachable exactly once and none may have been freed or duplicated.
 * Every node here is its own heap block, and the merged result is freed once
 * from the caller's head — so a node dropped from the chain shows up as a leak,
 * a node linked twice as a double free, and a walk that runs past the end of
 * either list as a heap-buffer-overflow.
 * The empty cases are the interesting ones and are run in both orders: an empty
 * first list has no last node to attach to, and an empty second list must not
 * disturb the first.
 * This is a test input, not an implementation. */
#include "ft_list.h"
#include <stdlib.h>

static t_list	*node(int v)
{
	t_list	*n;

	n = malloc(sizeof(t_list));
	n->data = malloc(sizeof(int));
	*(int *)n->data = v;
	n->next = NULL;
	return (n);
}

static t_list	*build(int n, int base)
{
	t_list	*head;
	t_list	*cur;
	int		i;

	if (n == 0)
		return (NULL);
	head = node(base);
	cur = head;
	i = 1;
	while (i < n)
	{
		cur->next = node(base + i);
		cur = cur->next;
		i++;
	}
	return (head);
}

static void	free_list(t_list *b)
{
	t_list	*tmp;

	while (b != NULL)
	{
		tmp = b;
		b = b->next;
		free(tmp->data);
		free(tmp);
	}
}

static void	call_case(int n1, int n2)
{
	t_list	*a;
	t_list	*b;

	a = build(n1, 0);
	b = build(n2, 100);
	ft_list_merge(&a, b);
	free_list(a);
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
