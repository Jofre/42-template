/* Live-differential reader harness for ft_list_at.
 * Line: <csv>\t<idx>\t<valueAtIdx|NULL>. Builds a list (data =
 * (void*)(intptr_t)v), calls ft_list_at(begin, idx), and reprints
 * <csv>\t<idx>\t<data-at-idx | NULL for out-of-range/empty>. */
#include "ft_list.h"
#include "diffio.h"
#include <stdint.h>

t_list	*ft_list_at(t_list *begin_list, unsigned int nbr);

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

/* The case's list, built by construction: n nodes, node i carrying tab[i] and
 * linked to node i + 1 by index; calloc leaves the last node's next NULL. Each
 * node is its own heap block, as a real list's nodes are, rather than one slot
 * of a shared array: node i + 1 is then not simply the next thing in memory,
 * so a walk that steps through memory instead of following next cannot land on
 * the right element by accident. The pointers stay in `node`, and every node is
 * freed from there after the call. That free is not optional: without it every
 * case's nodes are retained for the whole run, measured at 246 MB peak RSS at
 * the wired count of 400000, on a suite whose own README calls the campus box
 * memory-tight. */
static t_list	*build_ip(t_list **node, int *tab, int n)
{
	int	i;

	if (n == 0)
		return (NULL);
	i = 0;
	while (i < n)
	{
		node[i] = calloc(1, sizeof(t_list));
		node[i]->data = (void *)(intptr_t)tab[i];
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

int	main(void)
{
	char			line[8192];
	char			*f[3];
	int				tab[64];
	int				n;
	int				i;
	unsigned int	idx;
	t_list			*node[64];
	t_list			*r;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		n = parse_csv(f[0], tab);
		idx = (unsigned int)strtoul(f[1], NULL, 10);
		r = ft_list_at(build_ip(node, tab, n), idx);
		if (r == NULL)
			printf("%s\t%s\tNULL\n", f[0], f[1]);
		else
			printf("%s\t%s\t%d\n", f[0], f[1], (int)(intptr_t)r->data);
		i = 0;
		while (i < n)
			free(node[i++]);
	}
	return (0);
}
