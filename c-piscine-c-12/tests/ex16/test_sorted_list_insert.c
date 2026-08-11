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

static int	cmp_int(void *a, void *b)
{
	return (*(int *)a - *(int *)b);
}

static void	print_free_str(t_list *l)
{
	t_list	*tmp;

	while (l)
	{
		printf("%s\n", (char *)l->data);
		tmp = l;
		l = l->next;
		free(tmp);
	}
}

static void	print_free_int(t_list *l)
{
	t_list	*tmp;

	while (l)
	{
		printf("%d\n", *(int *)l->data);
		tmp = l;
		l = l->next;
		free(tmp);
	}
}

int	main(void)
{
	char	*words[] = {"banana", "apple", "cherry", "apple", "date",
		"aardvark"};
	int		arr[] = {3, -1, 3, 0, -5, 10};
	t_list	*begin;
	int		i;

	begin = NULL;
	i = 0;
	while (i < 6)
	{
		ft_sorted_list_insert(&begin, words[i], &cmp_str);
		i++;
	}
	printf("--- strings ---\n");
	print_free_str(begin);
	begin = NULL;
	i = 0;
	while (i < 6)
	{
		ft_sorted_list_insert(&begin, &arr[i], &cmp_int);
		i++;
	}
	printf("--- ints ---\n");
	print_free_int(begin);
	return (0);
}
