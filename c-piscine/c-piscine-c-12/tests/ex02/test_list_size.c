#include "ft_list.h"
#include <stdio.h>

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. Cases are ordered trivial -> hardest, so
 * the first failing row is the most fundamental thing to fix.
 *
 * ft_list_size returns the number of nodes in the list, so the value rendered
 * is simply that integer. */
static void	test(char *label, t_list *begin)
{
	printf("%s\t%d\n", label, ft_list_size(begin));
}

int	main(void)
{
	t_list	e[5];
	int		i;

	i = 0;
	while (i < 5)
	{
		e[i].data = "x";
		e[i].next = NULL;
		i++;
	}
	/* single isolated node */
	test("single node", &e[4]);
	/* two linked nodes */
	e[0].next = &e[1];
	test("two nodes", &e[0]);
	/* three linked nodes */
	e[1].next = &e[2];
	test("three nodes", &e[0]);
	/* five linked nodes */
	e[2].next = &e[3];
	e[3].next = &e[4];
	test("five nodes", &e[0]);
	/* the empty (NULL) list */
	test("empty NULL list", NULL);
	return (0);
}
