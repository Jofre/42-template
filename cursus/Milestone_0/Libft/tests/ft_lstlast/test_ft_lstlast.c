#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "libft.h"

/* ft_lstlast's basic table. Its box (Libft, p.15): "Returns the last node of
 * the list.", lst being "The beginning of the list".
 *
 * Every list is the test's own, built by construction: n nodes in one block,
 * node k (counted from 1) linked to node k + 1, the last one's next NULL. Its
 * last node is node n because that is the one whose next was left NULL. A row
 * prints the node returned by where it is in the list, never its address:
 * "node k", NULL, or a word saying the test did not make it. The empty list
 * is not here: what ft_lstlast returns for it is its own target's question,
 * at strict. */
t_list	*ft_lstlast(t_list *lst);

/* The row for a list of n nodes, n at least 1. */
static void	last_of(const char *label, int n)
{
	t_list	*blk;
	t_list	*got;
	int		i;

	blk = calloc((size_t)n, sizeof(t_list));
	if (blk == NULL)
		exit(1);
	i = 0;
	while (i + 1 < n)
	{
		blk[i].next = &blk[i + 1];
		i++;
	}
	got = ft_lstlast(blk);
	i = 0;
	while (i < n && got != &blk[i])
		i++;
	if (got == NULL)
		printf("%s\tNULL\n", label);
	else if (i == n)
		printf("%s\t(a node the test did not make)\n", label);
	else
		printf("%s\tnode %d\n", label, i + 1);
	free(blk);
}

int	main(void)
{
	last_of("1 node", 1);
	last_of("2 nodes", 2);
	last_of("3 nodes", 3);
	last_of("5000 nodes", 5000);
	return (0);
}
