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

/* The list the function is handed, built by construction: n nodes, node i
 * holding its own strdup'd copy of arr[i] and linked to node i + 1 by index;
 * calloc leaves the last node's next NULL. Every node and every string is its
 * own heap block, because the function releases the elements it removes one
 * at a time -- the string through the libc free it is handed, and the node --
 * so none of them may share a block. */
static t_list	*build(char **arr, int n)
{
	t_list	*node[5];
	int		i;

	if (n == 0)
		return (NULL);
	i = 0;
	while (i < n)
	{
		node[i] = calloc(1, sizeof(t_list));
		node[i]->data = strdup(arr[i]);
		i++;
	}
	i = 0;
	while (i + 1 < n)
	{
		node[i]->next = node[i + 1];
		i++;
	}
	return (node[0]);
}

/* Print what survived, one element per line, reading at most `cap` nodes --
 * the list's length before the call, plus one -- and recording each node
 * reached; then free the survivors, string and node, from that record. The
 * removed elements are already gone, released by the function itself. A list
 * still going after `cap` nodes can only be looping back on itself, and gets
 * a line saying so instead of an endless run; its repeated node is freed at
 * its first slot only, so that mistake stays a readable wrong answer instead
 * of turning into a double-free crash. */
static void	show_free(t_list *l, int cap)
{
	t_list	*seen[6];
	int		k;
	int		i;
	int		j;

	if (!l)
		printf("(empty)\n");
	k = 0;
	while (l && k < cap)
	{
		printf("%s\n", (char *)l->data);
		seen[k++] = l;
		l = l->next;
	}
	if (l)
		printf("...(list still going after %d nodes)\n", cap);
	i = 0;
	while (i < k)
	{
		j = 0;
		while (j < i && seen[j] != seen[i])
			j++;
		if (j == i)
		{
			free(seen[i]->data);
			free(seen[i]);
		}
		i++;
	}
}

static void	run(char **arr, int n, char *target, char *label)
{
	t_list	*begin;

	begin = build(arr, n);
	ft_list_remove_if(&begin, target, &cmp_str, &free);
	printf("%s\n", label);
	show_free(begin, n + 1);
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
