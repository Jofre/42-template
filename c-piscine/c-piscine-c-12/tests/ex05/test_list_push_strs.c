#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>

/* Print each node's data, one row per node labelled "<call>: node <n>",
 * reading at most `cap` nodes, and record each node in `seen` so it can be
 * freed once the printing is over. A list still going after `cap` nodes --
 * more nodes than the size asked for, or a list that loops back on itself --
 * gets a row saying so instead of an endless run. Returns how many nodes were
 * recorded. */
static int	print_list(char *call, t_list *l, t_list **seen, int cap)
{
	int	k;

	k = 0;
	while (l != NULL && k < cap)
	{
		printf("%s: node %d\t%s\n", call, k + 1, (char *)l->data);
		seen[k++] = l;
		l = l->next;
	}
	if (l != NULL)
		printf("%s: the list ends\tno, still going after %d nodes\n",
			call, cap);
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
	char	*strs[3];
	t_list	*begin;
	t_list	*seen[4];

	strs[0] = "one";
	strs[1] = "two";
	strs[2] = "three";
	/* each bound is the size asked for, plus one */
	begin = ft_list_push_strs(3, strs);
	free_seen(seen, print_list("size 3", begin, seen, 4));
	begin = ft_list_push_strs(1, strs);
	if (begin == NULL)
		printf("size 1: a list is returned\tno, NULL\n");
	free_seen(seen, print_list("size 1", begin, seen, 2));
	begin = ft_list_push_strs(0, strs);
	if (begin == NULL)
		printf("size 0: the list returned is empty\tyes, NULL\n");
	free_seen(seen, print_list("size 0", begin, seen, 1));
	return (0);
}
