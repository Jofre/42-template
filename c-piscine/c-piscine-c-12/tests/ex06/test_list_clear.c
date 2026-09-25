#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void	del(void *data)
{
	printf("free %s\n", (char *)data);
	free(data);
}

/* The list ft_list_clear is handed, built by construction: n nodes, each its
 * own calloc'd block (the function frees them one at a time, so they cannot
 * share one) holding its own strdup'd copy of s for `del` to free, and node i
 * linked to node i + 1 by index; calloc leaves the last node's next NULL. */
static t_list	*build(t_list **node, char *s, int n)
{
	int	i;

	i = 0;
	while (i < n)
	{
		node[i] = calloc(1, sizeof(t_list));
		node[i]->data = strdup(s);
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

int	main(void)
{
	t_list	*node[3];

	ft_list_clear(NULL, &del);
	ft_list_clear(build(node, "solo", 1), &del);
	ft_list_clear(build(node, "x", 3), &del);
	return (0);
}
