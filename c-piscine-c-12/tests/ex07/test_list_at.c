#include "ft_list.h"
#include <stdio.h>

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. A returned node is rendered as its data
 * cast to (char *), exactly as the original test did; a node that does not
 * exist (index out of range, or an empty list) is rendered as "NULL". Cases
 * are ordered trivial -> hardest, so the first failing row is the most
 * fundamental thing to fix. */
static void	test(char *label, t_list *begin, unsigned int nbr)
{
	t_list	*r;

	r = ft_list_at(begin, nbr);
	if (r == NULL)
		printf("%s\tNULL\n", label);
	else
		printf("%s\t%s\n", label, (char *)r->data);
}

int	main(void)
{
	t_list	node[5];
	int		i;

	node[0].data = "a";
	node[1].data = "b";
	node[2].data = "c";
	node[3].data = "d";
	node[4].data = "e";
	i = 0;
	while (i < 4)
	{
		node[i].next = &node[i + 1];
		i++;
	}
	node[4].next = NULL;
	test("index 0 first node", node, 0);
	test("index 2 middle node", node, 2);
	test("index 4 last node", node, 4);
	test("index 5 one past end", node, 5);
	test("index 9 far past end", node, 9);
	test("empty list index 0", NULL, 0);
	return (0);
}
