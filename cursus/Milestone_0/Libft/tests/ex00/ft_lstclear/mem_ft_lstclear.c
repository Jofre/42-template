/* Memory-safety probe for ft_lstclear, run under AddressSanitizer and
 * memcheck. A test input, not a solution.
 *
 * Aimed at a node read after it was freed -- its next, most often -- and at a
 * block freed twice. Each node is its own heap block of exactly
 * sizeof(t_list), each content a 1-byte block, so either lands on memory the
 * checker watches. The nodes handed over and their contents are never touched
 * again here; in the second call, which clears from the second node through
 * the first one's next, the first node and its content survive and are freed
 * by the probe at the end. An untouched stub frees nothing and reads nothing,
 * and leaks are not this layer's question, so it passes. */
#include <stdlib.h>
#include "libft.h"

void	ft_lstclear(t_list **lst, void (*del)(void *));

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
	t_list	*lst;
	t_list	*a;

	lst = node(node(node(NULL)));
	ft_lstclear(&lst, &del);
	a = node(node(node(NULL)));
	ft_lstclear(&a->next, &del);
	free(a->content);
	free(a);
	return (0);
}
