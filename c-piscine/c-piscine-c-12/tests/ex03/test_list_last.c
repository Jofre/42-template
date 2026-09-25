#include "ft_list.h"
#include <stdio.h>

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. For a returned node we render its data as
 * the original test does, (char *); a NULL result renders as the text "NULL".
 * Cases are ordered trivial -> hardest, so the first failing row is the most
 * fundamental thing to fix. */
static void	test(char *label, t_list *node)
{
	if (node == NULL)
		printf("%s\tNULL\n", label);
	else
		printf("%s\t%s\n", label, (char *)node->data);
}

int	main(void)
{
	t_list	a;
	t_list	b;
	t_list	c;
	t_list	solo;

	c.data = "last";
	c.next = NULL;
	b.data = "mid";
	b.next = &c;
	a.data = "first";
	a.next = &b;
	solo.data = "only";
	solo.next = NULL;
	test("empty list", ft_list_last(NULL));
	test("single element", ft_list_last(&solo));
	test("tail of three", ft_list_last(&a));
	return (0);
}
