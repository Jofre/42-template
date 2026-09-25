#include "ft_list.h"
#include <stdio.h>

static t_list	*build(t_list *nodes, void **data, int n)
{
	int	i;

	if (n == 0)
		return (NULL);
	i = 0;
	while (i < n)
	{
		nodes[i].data = data[i];
		if (i + 1 < n)
			nodes[i].next = &nodes[i + 1];
		else
			nodes[i].next = NULL;
		i++;
	}
	return (&nodes[0]);
}

/* Print each node's data, one per line, reading at most `cap` nodes: the
 * number of nodes the case built, plus one. A list still going after that can
 * only be looping back on itself, since no more nodes exist; it gets a line
 * saying so instead of an endless run. */
static void	show(t_list *l, int cap)
{
	int	k;

	if (!l)
		printf("(empty)\n");
	k = 0;
	while (l && k < cap)
	{
		printf("%s\n", (char *)l->data);
		l = l->next;
		k++;
	}
	if (l)
		printf("...(list still going after %d nodes)\n", cap);
}

int	main(void)
{
	t_list	nodes[4];
	void	*four[] = {"1", "2", "3", "4"};
	void	*three[] = {"1", "2", "3"};
	void	*two[] = {"1", "2"};
	void	*one[] = {"5"};
	t_list	*begin;

	printf("--- even ---\n");
	begin = build(nodes, four, 4);
	ft_list_reverse_fun(begin);
	show(begin, 5);
	printf("--- odd ---\n");
	begin = build(nodes, three, 3);
	ft_list_reverse_fun(begin);
	show(begin, 4);
	printf("--- two ---\n");
	begin = build(nodes, two, 2);
	ft_list_reverse_fun(begin);
	show(begin, 3);
	printf("--- single ---\n");
	begin = build(nodes, one, 1);
	ft_list_reverse_fun(begin);
	show(begin, 2);
	printf("--- empty ---\n");
	begin = NULL;
	ft_list_reverse_fun(begin);
	show(begin, 1);
	return (0);
}
