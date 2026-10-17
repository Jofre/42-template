/* Live-differential reader harness for ft_lstiter.
 * Line: <csv>\t<result-csv>. Builds the list of the comma-joined ints, node i's
 * content a pointer to the i-th int, applies the harness's f -- which turns
 * the int x a content points to into x*3-1, in place -- and reprints the
 * input and the ints afterwards, comma-joined, in list order. The values stay
 * within 1000000 of 0, so x*3-1 fits an int. */
#include <stdint.h>
#include "libft.h"
#include "diffio.h"

void	ft_lstiter(t_list *lst, void (*f)(void *));

/* The harness's f: the int the content points to, times 3, minus 1. */
static void	f(void *content)
{
	*(int *)content = *(int *)content * 3 - 1;
}

int	main(void)
{
	char	*line;
	size_t	cap;
	/* conventions: bounded -- dio_split never fills more than its count, 2 */
	char	*fl[2];
	int		*tab;
	int		n;
	int		i;
	t_list	*blk;

	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, fl, 2) < 1)
			continue ;
		tab = dio_csv_ints(fl[0], &n);
		blk = (t_list *)dio_alloc((size_t)n, sizeof(t_list));
		i = 0;
		while (i < n)
		{
			blk[i].content = &tab[i];
			if (i + 1 < n)
				blk[i].next = &blk[i + 1];
			i++;
		}
		ft_lstiter(n > 0 ? blk : NULL, &f);
		printf("%s\t", fl[0]);
		i = 0;
		while (i < n)
		{
			printf("%s%d", i > 0 ? "," : "", tab[i]);
			i++;
		}
		printf("\n");
		free(blk);
		free(tab);
	}
	free(line);
	return (0);
}
