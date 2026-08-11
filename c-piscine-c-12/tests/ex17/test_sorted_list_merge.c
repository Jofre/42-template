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

static void	run_str(t_list *na, void **d1, int n1,
			t_list *nb, void **d2, int n2, char *label)
{
	t_list	*begin1;

	begin1 = build(na, d1, n1);
	ft_sorted_list_merge(&begin1, build(nb, d2, n2), &cmp_str);
	printf("%s\n", label);
	show_str(begin1);
}

int	main(void)
{
	t_list	na[3];
	t_list	nb[3];
	int		a1[3];
	int		a2[3];
	void	*p1[3];
	void	*p2[3];
	void	*il1[] = {"apple", "cherry"};
	void	*il2[] = {"banana", "date"};
	void	*hu1[] = {"c", "e"};
	void	*hu2[] = {"a", "b"};
	void	*ab[] = {"a", "b"};
	t_list	*begin1;

	run_str(na, il1, 2, nb, il2, 2, "--- interleave ---");
	run_str(na, hu1, 2, nb, hu2, 2, "--- head update ---");
	run_str(na, NULL, 0, nb, ab, 2, "--- empty1 ---");
	run_str(na, ab, 2, nb, NULL, 0, "--- empty2 ---");
	run_str(na, NULL, 0, nb, NULL, 0, "--- both empty ---");
	a1[0] = 1;
	a1[1] = 3;
	a2[0] = 2;
	a2[1] = 3;
	p1[0] = &a1[0];
	p1[1] = &a1[1];
	p2[0] = &a2[0];
	p2[1] = &a2[1];
	begin1 = build(na, p1, 2);
	ft_sorted_list_merge(&begin1, build(nb, p2, 2), &cmp_int);
	printf("--- ints dups ---\n");
	show_int(begin1);
	a1[0] = -5;
	a1[1] = 0;
	a1[2] = 3;
	a2[0] = -1;
	a2[1] = 2;
	p1[0] = &a1[0];
	p1[1] = &a1[1];
	p1[2] = &a1[2];
	p2[0] = &a2[0];
	p2[1] = &a2[1];
	begin1 = build(na, p1, 3);
	ft_sorted_list_merge(&begin1, build(nb, p2, 2), &cmp_int);
	printf("--- ints neg ---\n");
	show_int(begin1);
	return (0);
}
