/* Live-differential reader harness for ft_lstadd_front.
 * Line: <csv>\t<result-csv>. Starting from the empty list, adds one node per
 * int of the comma-joined input, in input order, each node's content the int
 * carried as (void *)(intptr_t)v, and reprints the input and the list *lst
 * leads to afterwards, its contents comma-joined, first node first. */
#include <stdint.h>
#include "libft.h"
#include "diffio.h"

void	ft_lstadd_front(t_list **lst, t_list *new);

/* Before each call new->next is set to this node, in no list: a list that
 * reaches it afterwards prints a z there. */
static t_list	g_z;

/* The list from lst, contents comma-joined, reading at most `cap` nodes: the
 * case's length plus one, so a list one node too long still prints whole,
 * and one that loops back on itself gets a marker instead of an endless
 * walk. */
static void	ser(t_list *lst, int cap)
{
	int	k;

	k = 0;
	while (lst != NULL && k < cap)
	{
		if (k > 0)
			printf(",");
		if (lst == &g_z)
			printf("z");
		else
			printf("%d", (int)(intptr_t)lst->content);
		lst = lst->next;
		k++;
	}
	if (lst != NULL)
		printf(",...(list still going after %d nodes)", cap);
	printf("\n");
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
	t_list	*lst;

	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		tab = dio_csv_ints(f[0], &n);
		blk = (t_list *)dio_alloc((size_t)n, sizeof(t_list));
		lst = NULL;
		i = 0;
		while (i < n)
		{
			blk[i].content = (void *)(intptr_t)tab[i];
			blk[i].next = &g_z;
			ft_lstadd_front(&lst, &blk[i]);
			i++;
		}
		printf("%s\t", f[0]);
		ser(lst, n + 1);
		free(blk);
		free(tab);
	}
	free(line);
	return (0);
}
