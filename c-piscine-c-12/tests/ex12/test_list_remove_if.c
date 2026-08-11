#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>

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

static char	*dup_str(char *s)
{
	int		i;
	char	*r;

	i = 0;
	while (s[i])
		i++;
	r = malloc((i + 1) * sizeof(char));
	i = 0;
	while (s[i])
	{
		r[i] = s[i];
		i++;
	}
	r[i] = '\0';
	return (r);
}

static t_list	*build(char **arr, int n)
{
	t_list	*head;
	t_list	*tail;
	t_list	*node;
	int		i;

	head = NULL;
	tail = NULL;
	i = 0;
	while (i < n)
	{
		node = malloc(sizeof(t_list));
		node->data = dup_str(arr[i]);
		node->next = NULL;
		if (!head)
			head = node;
		else
			tail->next = node;
		tail = node;
		i++;
	}
	return (head);
}

static void	show_free(t_list *l)
{
	t_list	*tmp;

	if (!l)
		printf("(empty)\n");
	while (l)
	{
		printf("%s\n", (char *)l->data);
		tmp = l;
		l = l->next;
		free(tmp->data);
		free(tmp);
	}
}

static void	run(char **arr, int n, char *target, char *label)
{
	t_list	*begin;

	begin = build(arr, n);
	ft_list_remove_if(&begin, target, &cmp_str, &free);
	printf("%s\n", label);
	show_free(begin);
}

int	main(void)
{
	char	*a[] = {"keep", "del", "keep2", "del"};
	char	*b[] = {"del", "a", "b"};
	char	*c[] = {"a", "b", "del"};
	char	*d[] = {"a", "del", "del", "b", "del"};
	char	*e[] = {"z", "z", "z"};
	char	*f[] = {"a", "b"};

	run(a, 4, "del", "--- interleaved ---");
	run(b, 3, "del", "--- remove head ---");
	run(c, 3, "del", "--- remove tail ---");
	run(d, 5, "del", "--- consecutive ---");
	run(e, 3, "z", "--- remove all ---");
	run(f, 2, "q", "--- no match ---");
	return (0);
}
