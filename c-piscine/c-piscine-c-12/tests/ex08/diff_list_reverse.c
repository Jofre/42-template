/* Live-differential reader harness for ft_list_reverse.
 * Line: <csv>\t<reversed-csv>. Builds a list (data = (void*)(intptr_t)v),
 * reverses it in place, and serialises the resulting data sequence. */
#include "ft_list.h"
#include "diffio.h"
#include <stdint.h>

void	ft_list_reverse(t_list **begin_list);

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

/* The case's list, built by construction: ONE calloc'd block of n nodes, node
 * i carrying tab[i] and linked to node i + 1 by index -- calloc leaves the last
 * node's next NULL. The block's address is the head (NULL for an empty case),
 * and a single free of it releases the whole case afterwards, whatever the call
 * did to the links. That free is not optional: without it every case's nodes
 * are retained for the whole run, measured at 246 MB peak RSS at the wired
 * count of 400000, on a suite whose own README calls the campus box
 * memory-tight. */
static t_list	*build_ip(int *tab, int n)
{
	t_list	*blk;
	int		i;

	if (n == 0)
		return (NULL);
	blk = calloc(n, sizeof(t_list));
	i = 0;
	while (i < n)
	{
		blk[i].data = (void *)(intptr_t)tab[i];
		if (i + 1 < n)
			blk[i].next = &blk[i + 1];
		i++;
	}
	return (blk);
}

/* Serialise the list's data as csv, reading at most `cap` nodes: the case's
 * length plus one. A list still going after that can only be looping back on
 * itself, since the case has no more nodes than that; it gets a marker instead
 * of an endless walk, which is what such a list used to cost this layer (a
 * timeout). For a list that ends where it should, the output is the plain csv
 * the reference prints. */
static void	ser_ip(t_list *l, int cap)
{
	int	k;

	k = 0;
	while (l && k < cap)
	{
		if (k > 0)
			printf(",");
		printf("%d", (int)(intptr_t)l->data);
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
	char	*f[2];
	int		tab[64];
	int		n;
	t_list	*blk;
	t_list	*begin;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		n = parse_csv(f[0], tab);
		blk = build_ip(tab, n);
		begin = blk;
		ft_list_reverse(&begin);
		printf("%s\t", f[0]);
		ser_ip(begin, n + 1);
		free(blk);
	}
	return (0);
}
