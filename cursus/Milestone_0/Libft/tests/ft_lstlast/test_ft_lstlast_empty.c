#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "libft.h"

/* ft_lstlast on the empty list, a strict target of its own: the box (Libft,
 * p.15) returns the "Last node of the list", and the empty list has none, so
 * what comes back for it is a reading. Its hint (clues_empty.tsv) says which
 * this target tests. One row of the basic table comes first, so that a
 * function that returns the same thing for every list is not green here. */
t_list	*ft_lstlast(t_list *lst);

int	main(void)
{
	t_list	node[3];
	t_list	*got;
	int		i;

	node[0].content = NULL;
	node[0].next = &node[1];
	node[1].content = NULL;
	node[1].next = &node[2];
	node[2].content = NULL;
	node[2].next = NULL;
	got = ft_lstlast(&node[0]);
	i = 0;
	while (i < 3 && got != &node[i])
		i++;
	if (got == NULL)
		printf("3 nodes\tNULL\n");
	else if (i == 3)
		printf("3 nodes\t(a node the test did not make)\n");
	else
		printf("3 nodes\tnode %d\n", i + 1);
	got = ft_lstlast(NULL);
	if (got == NULL)
		printf("NULL (the empty list)\tNULL\n");
	else
		printf("NULL (the empty list)\t(a pointer, not NULL)\n");
	return (0);
}
