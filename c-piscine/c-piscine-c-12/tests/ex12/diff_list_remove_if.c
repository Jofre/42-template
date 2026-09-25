/* Live-differential reader harness for ft_list_remove_if.
 * Line: <csv>\t<ref>\t<result-csv>. Builds a list (data = malloc'd int*) and
 * removes every element for which cmp_int(data, &ref) == 0 (value == ref),
 * freeing the data with libc free, then serialises the remaining sequence.
 * Values and ref share a small range so removals are common. */
#include "ft_list.h"
#include "diffio.h"

void	ft_list_remove_if(t_list **begin_list, void *data_ref,
			int (*cmp)(), void (*free_fct)(void *));

static int	cmp_int(void *a, void *b)
{
	return (*(int *)a - *(int *)b);
}

static int	parse_csv(char *s, int *tab)
{
	int		n;
	char	*p;

	n = 0;
	p = s;
	while (*p)
	{
		tab[n++] = (int)strtol(p, &p, 10);
		if (*p == ',')
			p++;
	}
	return (n);
}

/* The case's list, built by construction: n nodes, node i's data a malloc'd
 * int holding tab[i], and node i linked to node i + 1 by index; calloc leaves
 * the last node's next NULL. Every node and every int is its own heap block,
 * because ft_list_remove_if releases what it removes one element at a time --
 * the data through the libc free it is handed, and the node -- so nothing here
 * may share a block. `node` only holds the pointers while they are linked. */
static t_list	*build_int(t_list **node, int *tab, int n)
{
	int	i;

	if (n == 0)
		return (NULL);
	i = 0;
	while (i < n)
	{
		node[i] = calloc(1, sizeof(t_list));
		node[i]->data = malloc(sizeof(int));
		*(int *)node[i]->data = tab[i];
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

/* Serialise the surviving data as csv, reading at most `cap` nodes: the
 * case's length before the call, plus one. A list still going after that can
 * only be looping back on itself, since the case never had more nodes; it gets
 * a marker instead of an endless walk, which is what such a list used to cost
 * this layer (a timeout). Each node read is recorded in `seen`, and the count
 * returned, so the survivors can be freed without walking the list again. */
static int	ser_int(t_list *l, int cap, t_list **seen)
{
	int	k;

	k = 0;
	while (l && k < cap)
	{
		if (k > 0)
			printf(",");
		printf("%d", *(int *)l->data);
		seen[k++] = l;
		l = l->next;
	}
	if (l)
		printf(",...(list still going after %d nodes)", cap);
	printf("\n");
	return (k);
}

/* Free the survivors ser_int recorded -- node AND the int it points at --
 * after each case; the removed elements are already gone, released by the
 * function under test. Without this every case's allocations are retained for
 * the whole run: measured 246 MB peak RSS at the wired count of 400000, on a
 * suite whose own README calls the campus box memory-tight. A node is recorded
 * twice only when the list loops back on itself; it is freed at its first slot
 * only, so that mistake stays a readable wrong answer instead of turning into
 * a double-free crash. */
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
		{
			free(seen[i]->data);
			free(seen[i]);
		}
		i++;
	}
}

int	main(void)
{
	char	line[8192];
	char	*f[3];
	int		tab[64];
	int		n;
	int		ref;
	t_list	*node[64];
	t_list	*seen[65];
	t_list	*begin;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		n = parse_csv(f[0], tab);
		ref = (int)strtol(f[1], NULL, 10);
		begin = build_int(node, tab, n);
		ft_list_remove_if(&begin, &ref, &cmp_int, &free);
		printf("%s\t%s\t", f[0], f[1]);
		free_seen(seen, ser_int(begin, n + 1, seen));
	}
	return (0);
}
