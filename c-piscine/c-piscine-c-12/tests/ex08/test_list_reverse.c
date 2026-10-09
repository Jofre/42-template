#include "ft_list.h"
#include <stdio.h>

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each row in its own column: first the reversed list's data, one row
 * per node, then one row per property of the links, each labelled with what
 * it checks and answered "yes" or "no". */
static void	yes_no(char *what, int holds)
{
	if (holds)
		printf("%s\tyes\n", what);
	else
		printf("%s\tno\n", what);
}

int	main(void)
{
	t_list	a;
	t_list	b;
	t_list	c;
	t_list	solo;
	t_list	*begin;
	t_list	*walk;
	int		k;

	c.data = "3";
	c.next = NULL;
	b.data = "2";
	b.next = &c;
	a.data = "1";
	a.next = &b;
	begin = &a;
	ft_list_reverse(&begin);
	/* Print at most four nodes: three exist, so a fourth can only mean the
	 * list now loops back on itself, and it gets a row saying so instead of
	 * an endless run. */
	walk = begin;
	k = 0;
	while (walk != NULL && k < 4)
	{
		printf("three nodes: node %d\t%s\n", k + 1, (char *)walk->data);
		walk = walk->next;
		k++;
	}
	if (walk != NULL)
		printf("three nodes: the list ends\tno, still going after %d nodes\n",
			k);
	yes_no("three nodes: *begin_list is the old last node", begin == &c);
	yes_no("three nodes: its next is the old middle node",
		begin != NULL && begin->next == &b);
	yes_no("three nodes: the middle's next is the old first node",
		begin != NULL && begin->next != NULL && begin->next->next == &a);
	yes_no("three nodes: the old first node's next is NULL", a.next == NULL);
	solo.data = "only";
	solo.next = NULL;
	begin = &solo;
	ft_list_reverse(&begin);
	yes_no("one node: *begin_list is still that node", begin == &solo);
	yes_no("one node: its next is still NULL",
		begin != NULL && begin->next == NULL);
	begin = NULL;
	ft_list_reverse(&begin);
	yes_no("empty list: *begin_list is still NULL", begin == NULL);
	return (0);
}
