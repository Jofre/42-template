/* Live-differential reader harness for ft_list_merge.
 * Line: <csv1>\t<csv2>\t<merged-csv>. Builds two lists whose data is an int*,
 * places the second at the end of the first, and serialises the resulting
 * data sequence.
 *
 * NEITHER INPUT IS SORTED, and that is the difference from ex17's harness. This
 * subject asks for concatenation -- "places elements of a list begin2 at the end
 * of another list begin1" -- so each list keeping its own order IS the
 * requirement, and a corpus of sorted pairs would be passed by an
 * implementation that sorted. There is no comparator here for the same reason.
 */
#include "ft_list.h"
#include "diffio.h"

void	ft_list_merge(t_list **begin_list1, t_list *begin_list2);

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

/* One of the case's two lists, built by construction: ONE calloc'd block of
 * n nodes, node i's data pointing at tab[i] -- the caller's parsed values,
 * which therefore hold the ints themselves -- and node i linked to node i + 1
 * by index; calloc leaves the last node's next NULL. The block's address is
 * the head (NULL for an empty list), and a single free of each block releases
 * the whole case afterwards, whatever the call did to the links. That free is
 * not optional: without it every case's nodes are retained for the whole run,
 * measured at 246 MB peak RSS at the wired count of 400000, on a suite whose
 * own README calls the campus box memory-tight. */
static t_list	*build_int(int *tab, int n)
{
	t_list	*blk;
	int		i;

	if (n == 0)
		return (NULL);
	blk = calloc(n, sizeof(t_list));
	i = 0;
	while (i < n)
	{
		blk[i].data = &tab[i];
		if (i + 1 < n)
			blk[i].next = &blk[i + 1];
		i++;
	}
	return (blk);
}

/* Serialise the list's data as csv, reading at most `cap` nodes: both lists'
 * lengths together, plus one. A list still going after that can only be
 * looping back on itself, since the case has no more nodes than that; it gets
 * a marker instead of an endless walk, which is what such a list used to cost
 * this layer (a timeout). For a list that ends where it should, the output is
 * the plain csv the reference prints. */
static void	ser_int(t_list *l, int cap)
{
	int	k;

	k = 0;
	while (l && k < cap)
	{
		if (k > 0)
			printf(",");
		printf("%d", *(int *)l->data);
		k++;
		l = l->next;
	}
	if (l)
		printf(",...(list still going after %d nodes)", cap);
	printf("\n");
}

int	main(void)
{
	char	line[8192];
	char	*f[3];
	int		tab1[64];
	int		tab2[64];
	int		n1;
	int		n2;
	t_list	*blk1;
	t_list	*blk2;
	t_list	*begin1;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		n1 = parse_csv(f[0], tab1);
		n2 = parse_csv(f[1], tab2);
		blk1 = build_int(tab1, n1);
		blk2 = build_int(tab2, n2);
		begin1 = blk1;
		ft_list_merge(&begin1, blk2);
		printf("%s\t%s\t", f[0], f[1]);
		ser_int(begin1, n1 + n2 + 1);
		free(blk1);
		free(blk2);
	}
	return (0);
}
