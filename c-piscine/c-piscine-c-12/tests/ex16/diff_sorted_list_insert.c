/* Live-differential reader harness for ft_sorted_list_insert.
 * Line: <sorted-csv>\t<value>\t<result-csv>. Builds an already-sorted list
 * whose data is an int*, inserts one more value with the FIXED
 * comparator cmp_int (ascending: *(int*)a - *(int*)b), and serialises the
 * resulting data sequence. Input values are bounded so the comparator's
 * subtraction never overflows. */
#include "ft_list.h"
#include "diffio.h"

void	ft_sorted_list_insert(t_list **begin_list, void *data, int (*cmp)());

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

/* The case's list, built by construction: n nodes, node i's data pointing at
 * tab[i] -- the caller's parsed values, which therefore hold the ints
 * themselves -- and node i linked to node i + 1 by index; calloc leaves the
 * last node's next NULL. Each node is its own calloc'd block, like the one the
 * function adds, so that after the call every node in the list is released the
 * same way, one free each, whoever made it. `node` only holds the pointers
 * while they are linked. */
static t_list	*build_int(t_list **node, int *tab, int n)
{
	int	i;

	if (n == 0)
		return (NULL);
	i = 0;
	while (i < n)
	{
		node[i] = calloc(1, sizeof(t_list));
		node[i]->data = &tab[i];
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

/* Serialise the list's data as csv, reading at most `cap` nodes: the case's
 * length after the insertion, plus one, so a list one node too long still
 * prints whole. A list still going after that -- longer than one insertion
 * can explain, or looping back on itself -- gets a marker instead of an
 * endless walk (a looping list used to cost this layer a timeout). Each node
 * read is recorded in `seen`, and the count returned, so the caller can free
 * them without walking the list a second time. */
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

/* Free the nodes ser_int recorded, after each case: the harness's own and the
 * one the function added. The ints live in tab and x, so there is no data to
 * free. Without this every case's nodes are retained for the whole run:
 * measured 246 MB peak RSS at the wired count of 400000, on a suite whose own
 * README calls the campus box memory-tight. A node is recorded twice only when
 * the list loops back on itself; it is freed at its first slot only, so that
 * mistake stays a readable wrong answer instead of turning into a double-free
 * crash. */
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
	char	line[8192];
	char	*f[3];
	int		tab[64];
	int		n;
	int		x;
	t_list	*node[64];
	t_list	*seen[66];
	t_list	*begin;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		n = parse_csv(f[0], tab);
		begin = build_int(node, tab, n);
		x = (int)strtol(f[1], NULL, 10);
		ft_sorted_list_insert(&begin, &x, &cmp_int);
		printf("%s\t%s\t", f[0], f[1]);
		free_seen(seen, ser_int(begin, n + 2, seen));
	}
	return (0);
}
