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

static void	show(t_list *l)
{
	if (!l)
		printf("(empty)\n");
	while (l)
	{
		printf("%s\n", (char *)l->data);
		l = l->next;
	}
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
	show(begin);
	printf("--- odd ---\n");
	begin = build(nodes, three, 3);
	ft_list_reverse_fun(begin);
	show(begin);
	printf("--- two ---\n");
	begin = build(nodes, two, 2);
	ft_list_reverse_fun(begin);
	show(begin);
	printf("--- single ---\n");
	begin = build(nodes, one, 1);
	ft_list_reverse_fun(begin);
	show(begin);
	printf("--- empty ---\n");
	begin = NULL;
	ft_list_reverse_fun(begin);
	show(begin);
	return (0);
}
