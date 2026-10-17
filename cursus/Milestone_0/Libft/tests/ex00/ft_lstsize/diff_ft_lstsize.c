/* Live-differential reader harness for ft_lstsize.
 * Line: <csv>\t<size>. Builds the list of the comma-joined ints, each node's
 * content the int carried as (void *)(intptr_t)v, and reprints the input and
 * what ft_lstsize returns for it (%u: it returns an unsigned int). */
#include <stdint.h>
#include "libft.h"
#include "diffio.h"

unsigned int	ft_lstsize(t_list *lst);

/* The case's list, built by construction: one block of exactly n nodes, node
 * i holding tab[i] and linked to node i + 1, the last one's next NULL (the
 * block is zeroed). The block's address is the first node, NULL when n is 0,
 * and one free of it releases the case. */
static t_list	*build(int *tab, int n)
{
	t_list	*blk;
	int		i;

	blk = (t_list *)dio_alloc((size_t)n, sizeof(t_list));
	i = 0;
	while (i < n)
	{
		blk[i].content = (void *)(intptr_t)tab[i];
		if (i + 1 < n)
			blk[i].next = &blk[i + 1];
		i++;
	}
	return (blk);
}

int	main(void)
{
	char	*line;
	size_t	cap;
	char	*f[2];
	int		*tab;
	int		n;
	t_list	*blk;

	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		tab = dio_csv_ints(f[0], &n);
		blk = build(tab, n);
		printf("%s\t%u\n", f[0], ft_lstsize(n > 0 ? blk : NULL));
		free(blk);
		free(tab);
	}
	free(line);
	return (0);
}
