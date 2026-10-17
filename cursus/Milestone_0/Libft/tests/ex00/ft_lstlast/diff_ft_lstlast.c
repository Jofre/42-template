/* Live-differential reader harness for ft_lstlast.
 * Line: <csv>\t<last>. Builds the list of the comma-joined ints (never the
 * empty list), each node's content the int carried as (void *)(intptr_t)v,
 * and reprints the input and the content of the node ft_lstlast returns, as
 * an int -- NULL when it returns NULL, and a sentence when it returns a
 * pointer that is none of the list's nodes. */
#include <stdint.h>
#include "libft.h"
#include "diffio.h"

t_list	*ft_lstlast(t_list *lst);

/* The case's list, built by construction: one block of exactly n nodes, node
 * i holding tab[i] and linked to node i + 1, the last one's next NULL (the
 * block is zeroed). One free of the block releases the case. */
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
	int		i;
	t_list	*blk;
	t_list	*got;

	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		tab = dio_csv_ints(f[0], &n);
		blk = build(tab, n);
		got = ft_lstlast(n > 0 ? blk : NULL);
		i = 0;
		while (i < n && got != &blk[i])
			i++;
		if (got == NULL)
			printf("%s\tNULL\n", f[0]);
		else if (i == n)
			printf("%s\t(a pointer to none of the list's nodes)\n", f[0]);
		else
			printf("%s\t%d\n", f[0], (int)(intptr_t)got->content);
		free(blk);
		free(tab);
	}
	free(line);
	return (0);
}
