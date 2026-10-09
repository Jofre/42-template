/* Live-differential reader harness for ft_list_remove_if.
 * Line: <csv>\t<ref>\t<result-csv>\t<free_fct calls>. Builds a list (data =
 * malloc'd int*) and removes every element for which cmp_int(data, &ref) == 0
 * (value == ref), then serialises the remaining sequence and how many times
 * free_fct was called: once per removed element, the subject's "The data from
 * an element to be erased should be freed using free_fct" (finding 130).
 * free_fct only counts: the harness frees every int itself once the case is
 * over, so a call on the wrong pointer is a divergence, never a crash.
 * cmp_int answers "equal" only when it is called as the subject writes it,
 * (*cmp)(list_ptr->data, data_ref), so a swapped call removes nothing and
 * diverges too (finding 126). Values and ref share a small range so removals
 * are common. */
#include "ft_list.h"
#include "diffio.h"

void	ft_list_remove_if(t_list **begin_list, void *data_ref,
			int (*cmp)(), void (*free_fct)(void *));

static void	*g_ref;
static int		g_freed;

/* Equal only when the second argument is the reference this harness passed,
 * by identity: the subject's order. */
static int	cmp_int(void *a, void *b)
{
	if (b != g_ref)
		return (1);
	return (*(int *)a - *(int *)b);
}

static void	count_free(void *data)
{
	(void)data;
	g_freed++;
}

/* The case's list, built by construction: n nodes, node i's data a malloc'd
 * int holding tab[i] (kept in `data` too, for the harness to free), and node
 * i linked to node i + 1 by index; calloc leaves the last node's next NULL.
 * Every node and every int is its own heap block, because ft_list_remove_if
 * releases the nodes it removes one at a time, so nothing here may share a
 * block. `node` only holds the pointers while they are linked. */
static t_list	*build_int(t_list **node, void **data, int *tab, int n)
{
	int	i;

	if (n == 0)
		return (NULL);
	i = 0;
	while (i < n)
	{
		node[i] = calloc(1, sizeof(t_list));
		data[i] = malloc(sizeof(int));
		*(int *)data[i] = tab[i];
		node[i]->data = data[i];
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
	return (k);
}

/* Free the survivors' nodes ser_int recorded, and every int of the case,
 * after each case; the removed nodes are already gone, released by the
 * function under test. Without this every case's allocations are retained for
 * the whole run: measured 246 MB peak RSS at the wired count of 400000, on a
 * suite whose own README calls the campus box memory-tight. A node is recorded
 * twice only when the list loops back on itself; it is freed at its first slot
 * only, so that mistake stays a readable wrong answer instead of turning into
 * a double-free crash. */
static void	free_seen(t_list **seen, int k, void **data, int n)
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
	i = 0;
	while (i < n)
		free(data[i++]);
}

int	main(void)
{
	char	*line;
	size_t	cap;
	char	*f[3];
	int		*tab;
	int		n;
	int		ref;
	t_list	**node;
	void	**data;
	t_list	**seen;
	t_list	*begin;
	int		k;

	/* A line of any length (tools/diffio.h): the corpus holds lists and
	 * trees of hundreds and thousands of nodes (finding 041). */
	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		tab = dio_csv_ints(f[0], &n);
		node = (t_list **)dio_alloc((size_t)n, sizeof(t_list *));
		data = (void **)dio_alloc((size_t)n, sizeof(void *));
		seen = (t_list **)dio_alloc((size_t)(n + 1), sizeof(t_list *));
		ref = (int)strtol(f[1], NULL, 10);
		begin = build_int(node, data, tab, n);
		g_ref = &ref;
		g_freed = 0;
		ft_list_remove_if(&begin, &ref, &cmp_int, &count_free);
		printf("%s\t%s\t", f[0], f[1]);
		k = ser_int(begin, n + 1, seen);
		printf("\t%d\n", g_freed);
		free_seen(seen, k, data, n);
		free(seen);
		free(data);
		free(node);
		free(tab);
	}
	free(line);
	return (0);
}
