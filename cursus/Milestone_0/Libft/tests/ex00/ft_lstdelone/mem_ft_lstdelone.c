/* Memory-safety probe for ft_lstdelone, run under AddressSanitizer and
 * memcheck. A test input, not a solution.
 *
 * Aimed at a node read after it was freed, and at a node freed that was not
 * the one handed over. Each node is its own heap block of exactly
 * sizeof(t_list), each content a 1-byte block, so a read of a freed node, or a
 * second free of any block, lands on memory the checker watches. The node
 * handed over and its content are never touched again here; the other nodes
 * and contents are freed by the probe at the end, once, as the box says they
 * survive the call. An untouched stub frees nothing and reads nothing, and
 * leaks are not this layer's question, so it passes. */
#include <stdlib.h>
#include "libft.h"

void	ft_lstdelone(t_list *lst, void (*del)(void *));

static void	del(void *content)
{
	free(content);
}

static t_list	*node(t_list *next)
{
	t_list	*n;

	n = malloc(sizeof(t_list));
	if (n == NULL)
		exit(1);
	n->content = malloc(1);
	if (n->content == NULL)
		exit(1);
	n->next = next;
	return (n);
}

int	main(void)
{
	t_list	*c;
	t_list	*b;
	t_list	*a;

	c = node(NULL);
	b = node(c);
	a = node(b);
	ft_lstdelone(b, &del);
	free(a->content);
	free(a);
	free(c->content);
	free(c);
	a = node(NULL);
	ft_lstdelone(a, &del);
	return (0);
}
