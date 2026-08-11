#include "ft_list.h"
#include <stdio.h>

static t_list	*build(t_list *nodes, char **data, int n)
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
	t_list	na[4];
	t_list	nb[4];
	char	*d1[] = {"a", "b"};
	char	*d2[] = {"c", "d"};
	t_list	*begin1;

	printf("--- both ---\n");
	begin1 = build(na, d1, 2);
	ft_list_merge(&begin1, build(nb, d2, 2));
	show(begin1);
	printf("--- empty1 ---\n");
	begin1 = NULL;
	ft_list_merge(&begin1, build(nb, d2, 2));
	show(begin1);
	printf("--- empty2 ---\n");
	begin1 = build(na, d1, 2);
	ft_list_merge(&begin1, NULL);
	show(begin1);
	printf("--- both empty ---\n");
	begin1 = NULL;
	ft_list_merge(&begin1, NULL);
	show(begin1);
	printf("--- singles ---\n");
	begin1 = build(na, d1, 1);
	ft_list_merge(&begin1, build(nb, d2, 1));
	show(begin1);
	return (0);
}
