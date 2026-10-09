/* Live-differential reader harness for ft_list_reverse_fun.
 * Line: <csv>\t<reversed-csv> -- the same corpus as ex08's ft_list_reverse
 * (oracle c12_list_reverse): both subjects ask for the list's elements in the
 * reverse order, and differ only in what the caller holds, a head by value
 * here. Builds the list (data = (void*)(intptr_t)v), calls the function on its
 * head, and serialises what that SAME head reaches afterwards: the caller
 * cannot be handed a new one, so that is the list the caller sees.
 * See tools/diffio.h. */
#include "ft_list.h"
#include "diffio.h"
#include <stdint.h>

void	ft_list_reverse_fun(t_list *begin_list);

/* How many ints the csv holds: one more than its commas, none when empty. */
static int	count_csv(const char *s)
{
	int	n;

	if (*s == '\0')
		return (0);
	n = 1;
	while ((s = strchr(s, ',')) != NULL)
	{
		n++;
		s++;
	}
	return (n);
}

/* The case's list, built by construction: ONE calloc'd block of n nodes, node
 * i carrying the csv's i-th value and linked to node i + 1 by index -- calloc
 * leaves the last node's next NULL. The block's address is the head (NULL for
 * an empty case), and a single free of it releases the whole case afterwards,
 * whatever the call did to the links. Sized from the case and read from a line
 * of any length (dio_getline): no capacity of this harness's own decides how
 * long a list can be (finding 041). */
static t_list	*build_ip(char *s, int n)
{
	t_list	*blk;
	char	*p;
	int		i;

	if (n == 0)
		return (NULL);
	blk = calloc(n, sizeof(t_list));
	if (blk == NULL)
		exit(2);
	p = s;
	i = 0;
	while (i < n)
	{
		blk[i].data = (void *)(intptr_t)strtol(p, &p, 10);
		if (*p == ',')
			p++;
		if (i + 1 < n)
			blk[i].next = &blk[i + 1];
		i++;
	}
	return (blk);
}

/* Serialise the list's data as csv, reading at most `cap` nodes: the case's
 * length plus one. A list still going after that can only be looping back on
 * itself, since the case has no more nodes than that; it gets a marker instead
 * of an endless walk. For a list that ends where it should, the output is the
 * plain csv the reference prints. */
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
	char	*line;
	size_t	cap;
	char	*f[2];
	int		n;
	t_list	*blk;

	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		n = count_csv(f[0]);
		blk = build_ip(f[0], n);
		ft_list_reverse_fun(blk);
		printf("%s\t", f[0]);
		ser_ip(blk, n + 1);
		free(blk);
	}
	free(line);
	return (0);
}
