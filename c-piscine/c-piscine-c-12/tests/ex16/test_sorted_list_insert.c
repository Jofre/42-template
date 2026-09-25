#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The comparator handed to the function: libc strcmp, which a test is free to
 * use. The fixture never prints what it returns, only what the function did
 * with it. */
static int	cmp_str(void *a, void *b)
{
	return (strcmp((char *)a, (char *)b));
}

static int	cmp_int(void *a, void *b)
{
	return (*(int *)a - *(int *)b);
}

/* Print each node's data, one per line, reading at most `cap` nodes, and
 * record each node in `seen` so it can be freed once the printing is over.
 * A list still going after `cap` nodes -- more nodes than the insertions
 * made, or a list that loops back on itself -- gets a line saying so instead
 * of an endless run. Returns how many nodes were recorded. */
static int	print_str(t_list *l, t_list **seen, int cap)
{
	int	k;

	k = 0;
	while (l && k < cap)
	{
		printf("%s\n", (char *)l->data);
		seen[k++] = l;
		l = l->next;
	}
	if (l)
		printf("...(list still going after %d nodes)\n", cap);
	return (k);
}

/* The same, for a list whose data points at ints. */
static int	print_int(t_list *l, t_list **seen, int cap)
{
	int	k;

	k = 0;
	while (l && k < cap)
	{
		printf("%d\n", *(int *)l->data);
		seen[k++] = l;
		l = l->next;
	}
	if (l)
		printf("...(list still going after %d nodes)\n", cap);
	return (k);
}

/* Free each recorded node once; the data are the arrays in main, not heap
 * blocks. A node is recorded twice only when the list loops back on itself;
 * it is freed at its first slot only, so that mistake stays a readable wrong
 * answer instead of turning into a double-free crash. */
static void	free_seen(t_list **seen, int k)
{
	int	i;
	int	j;

	i = 0;
	while (i < k)
	{
		j = 0;
		while (j < i && seen[j] != seen[i])
			j++;
		if (j == i)
			free(seen[i]);
		i++;
	}
}

int	main(void)
{
	char	*words[] = {"banana", "apple", "cherry", "apple", "date",
		"aardvark"};
	int		arr[] = {3, -1, 3, 0, -5, 10};
	t_list	*begin;
	t_list	*seen[7];
	int		i;

	/* six insertions each time, so the bound is seven */
	begin = NULL;
	i = 0;
	while (i < 6)
	{
		ft_sorted_list_insert(&begin, words[i], &cmp_str);
		i++;
	}
	printf("--- strings ---\n");
	free_seen(seen, print_str(begin, seen, 7));
	begin = NULL;
	i = 0;
	while (i < 6)
	{
		ft_sorted_list_insert(&begin, &arr[i], &cmp_int);
		i++;
	}
	printf("--- ints ---\n");
	free_seen(seen, print_int(begin, seen, 7));
	return (0);
}
