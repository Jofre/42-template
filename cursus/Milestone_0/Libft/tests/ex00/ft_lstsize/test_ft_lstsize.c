#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "libft.h"

/* ft_lstsize's basic table. Its box (Libft, p.15): "Counts the number of
 * nodes in the list.", returning "The length of the list" as an unsigned
 * int, printed here with %u. A NULL first node is the empty list.
 *
 * Every list is the test's own, built by construction: n nodes in one block,
 * node i linked to node i + 1, the last one's next NULL. Its length is n
 * because n nodes were linked, so each row's expected value is the n its
 * label names. */
unsigned int	ft_lstsize(t_list *lst);

/* The row for a list of n nodes. */
static void	size_of(const char *label, int n)
{
	t_list	*blk;
	int		i;

	if (n == 0)
	{
		printf("%s\t%u\n", label, ft_lstsize(NULL));
		return ;
	}
	blk = calloc((size_t)n, sizeof(t_list));
	if (blk == NULL)
		exit(1);
	i = 0;
	while (i + 1 < n)
	{
		blk[i].next = &blk[i + 1];
		i++;
	}
	printf("%s\t%u\n", label, ft_lstsize(blk));
	free(blk);
}

int	main(void)
{
	size_of("NULL (the empty list)", 0);
	size_of("1 node", 1);
	size_of("2 nodes", 2);
	size_of("3 nodes", 3);
	size_of("5 nodes", 5);
	size_of("5000 nodes", 5000);
	size_of("70000 nodes", 70000);
	return (0);
}
