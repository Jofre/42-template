/* Live-differential reader harness for ft_list_last.
 * Line: <csv>\t<lastValue|NULL>. Builds a list (data = (void*)(intptr_t)v),
 * calls ft_list_last, and reprints <csv>\t<data-of-last | NULL>. */
#include "ft_list.h"
#include "diffio.h"
#include <stdint.h>

t_list	*ft_list_last(t_list *begin_list);

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

int	main(void)
{
	char	line[8192];
	char	*f[2];
	int		tab[64];
	int		n;
	t_list	*r;
	t_list	*head;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		n = parse_csv(f[0], tab);
		head = build_ip(tab, n);
		r = ft_list_last(head);
		if (r == NULL)
			printf("%s\tNULL\n", f[0]);
		else
			printf("%s\t%d\n", f[0], (int)(intptr_t)r->data);
		free(head);
	}
	return (0);
}
