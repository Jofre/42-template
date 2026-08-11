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

static t_list	*node(int v)
{
	t_list	*n;

	n = malloc(sizeof(t_list));
	n->data = malloc(sizeof(int));
	*(int *)n->data = v;
	n->next = NULL;
	return (n);
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

static t_list	*build(int n)
{
	t_list	*head;
	t_list	*cur;
	int		i;

	if (n == 0)
		return (NULL);
	head = node(0);
	cur = head;
	i = 1;
	while (i < n)
	{
		cur->next = node(i);
		cur = cur->next;
		i++;
	}
	return (head);
}

int	main(void)
{
	t_list	*b;
	int		n;

	n = 3;
	while (n >= 0)
	{
		b = build(n);
		ft_list_reverse_fun(b);
		free_list(b);
		n--;
	}
	return (0);
}
