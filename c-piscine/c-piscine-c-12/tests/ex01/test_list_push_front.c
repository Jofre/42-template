#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>

/* Print each node's data, one row per node labelled "<call>: node <n>",
 * reading at most `cap` nodes, and record each node in `seen` so it can be
 * freed once the printing is over. A list still going after `cap` nodes --
 * more nodes than the calls made, or a list that loops back on itself -- gets
 * a row saying so instead of an endless run. Returns how many nodes were
 * recorded.
 *
 * The last row is left without its newline, which free_seen() prints once the
 * nodes are freed: a crash in free() then stops the table on this list's own
 * last row, which diff_output.sh marks, and not on the next call's row. Every
 * other row's newline comes just before the next node is read, so a crash
 * reading a node still marks that node's row. */
static int	print_list(char *call, t_list *l, t_list **seen, int cap)
{
	int	k;

	k = 0;
	while (l != NULL && k < cap)
	{
		if (k > 0)
			printf("\n");
		printf("%s: node %d\t%s", call, k + 1, (char *)l->data);
		seen[k++] = l;
		l = l->next;
	}
	if (l != NULL)
		printf("\n%s: the list ends\tno, still going after %d nodes",
			call, cap);
	return (k);
}

/* Free each recorded node once, then end the row print_list() left open (it
 * left one when it recorded a node). A node is recorded twice only when the
 * list loops back on itself; it is freed at its first slot only, so that
 * mistake stays a readable wrong answer instead of turning into a
 * double-free crash. */
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
	if (k > 0)
		printf("\n");
}

int	main(void)
{
	t_list	*begin;
	t_list	*seen[5];

	begin = NULL;
	ft_list_push_front(&begin, "a");
	ft_list_push_front(&begin, "b");
	ft_list_push_front(&begin, "c");
	ft_list_push_front(&begin, "d");
	/* four calls made four nodes, so the bound is five */
	free_seen(seen, print_list("four calls", begin, seen, 5));
	begin = NULL;
	ft_list_push_front(&begin, "solo");
	if (begin == NULL)
		printf("one call on an empty list: head\tstill NULL\n");
	else
	{
		printf("one call on an empty list: head's data\t%s\n",
			(char *)begin->data);
		if (begin->next == NULL)
			printf("one call on an empty list: next is NULL\tyes");
		else
			printf("one call on an empty list: next is NULL\tno");
		free(begin);
		printf("\n");
	}
	return (0);
}
