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

/* 5000 nodes, node i holding the int i, and what the caller's head reaches
 * afterwards checked against the reversal by construction, then shown as ONE
 * line: the reversal, abridged, or the first node out of place. The subject
 * bounds no length, so every reading agrees on this case, and it is past every
 * capacity a copy is usually given (16, 64, 256, 1024, 4096): a function that
 * works through room of its own fixed size gets it wrong here, or dies
 * (finding 041). */
#define LONG 5000

static void	test_long(void)
{
	static t_list	nodes[LONG];
	static int		vals[LONG];
	static void		*data[LONG];
	t_list			*l;
	int				k;

	k = 0;
	while (k < LONG)
	{
		vals[k] = k;
		data[k] = &vals[k];
		k++;
	}
	printf("--- 5000 nodes ---\n");
	l = build(nodes, data, LONG);
	ft_list_reverse_fun(l);
	k = 0;
	while (l && k < LONG && *(int *)l->data == LONG - 1 - k)
	{
		l = l->next;
		k++;
	}
	if (k == LONG && l == NULL)
		printf("4999 4998 ... 1 0\n");
	else if (k == LONG)
		printf("...(list still going after %d nodes)\n", LONG);
	else if (l == NULL)
		printf("the list ends after %d nodes, not %d\n", k, LONG);
	else
		printf("node %d holds %d, not %d\n", k, *(int *)l->data, LONG - 1 - k);
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
	test_long();
	return (0);
}
