#include "ft_list.h"
#include <stdio.h>

static int	cmp_str(void *a, void *b)
{
	char	*s1;
	char	*s2;

	s1 = (char *)a;
	s2 = (char *)b;
	while (*s1 && *s1 == *s2)
	{
		s1++;
		s2++;
	}
	return ((unsigned char)*s1 - (unsigned char)*s2);
}

static int	cmp_int(void *a, void *b)
{
	return (*(int *)a - *(int *)b);
}

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

static void	show_str(t_list *l)
{
	if (!l)
		printf("(empty)\n");
	while (l)
	{
		printf("%s\n", (char *)l->data);
		l = l->next;
	}
}

static void	show_int(t_list *l)
{
	while (l)
	{
		printf("%d\n", *(int *)l->data);
		l = l->next;
	}
}

static void	run_str(t_list *nodes, void **data, int n, char *label)
{
	t_list	*begin;

	begin = build(nodes, data, n);
	ft_list_sort(&begin, &cmp_str);
	printf("%s\n", label);
	show_str(begin);
}

int	main(void)
{
	t_list	nodes[5];
	int		arr[5];
	void	*ints[5];
	void	*u[] = {"banana", "apple", "cherry"};
	void	*s[] = {"apple", "banana", "cherry"};
	void	*r[] = {"cherry", "banana", "apple"};
	void	*dup[] = {"banana", "apple", "apple", "cherry"};
	void	*one[] = {"solo"};
	t_list	*begin;
	int		i;

	run_str(nodes, u, 3, "--- unsorted ---");
	run_str(nodes, s, 3, "--- sorted ---");
	run_str(nodes, r, 3, "--- reverse ---");
	run_str(nodes, dup, 4, "--- dups ---");
	run_str(nodes, one, 1, "--- single ---");
	printf("--- empty ---\n");
	begin = NULL;
	ft_list_sort(&begin, &cmp_str);
	show_str(begin);
	arr[0] = 3;
	arr[1] = -1;
	arr[2] = -5;
	arr[3] = 0;
	arr[4] = 3;
	i = 0;
	while (i < 5)
	{
		ints[i] = &arr[i];
		i++;
	}
	begin = build(nodes, ints, 5);
	ft_list_sort(&begin, &cmp_int);
	printf("--- ints ---\n");
	show_int(begin);
	return (0);
}
