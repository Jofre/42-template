#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>

/* Print each node's data, one per line, reading at most `cap` nodes, and
 * record each node in `seen` so it can be freed once the printing is over.
 * A list still going after `cap` nodes -- more nodes than the calls made, or
 * a list that loops back on itself -- gets a line saying so instead of an
 * endless run. Returns how many nodes were recorded. */
static int	print_list(t_list *l, t_list **seen, int cap)
{
	int	k;

	k = 0;
	while (l != NULL && k < cap)
	{
		printf("%s\n", (char *)l->data);
		seen[k++] = l;
		l = l->next;
	}
	if (l != NULL)
		printf("...(list still going after %d nodes)\n", cap);
	return (k);
}

/* Free each recorded node once. A node is recorded twice only when the list
 * loops back on itself; it is freed at its first slot only, so that mistake
 * stays a readable wrong answer instead of turning into a double-free crash. */
static void	free_seen(t_list **seen, int k)
{
	int	i;
	int	j;

	i = 0;
	while (i < k)
	{
		j = 0;
		while (j < i && seen[j] != seen[i])
			j++;
		if (j == i)
			free(seen[i]);
		i++;
	}
}

int	main(void)
{
	t_list	*begin;
	t_list	*seen[5];

	begin = NULL;
	ft_list_push_back(&begin, "a");
	ft_list_push_back(&begin, "b");
	ft_list_push_back(&begin, "c");
	ft_list_push_back(&begin, "d");
	/* four calls made four nodes, so the bound is five */
	free_seen(seen, print_list(begin, seen, 5));
	begin = NULL;
	ft_list_push_back(&begin, "solo");
	printf("%d\n", begin != NULL);
	if (begin != NULL)
	{
		printf("%s\n", (char *)begin->data);
		printf("%d\n", begin->next == NULL);
		free(begin);
	}
	return (0);
}
