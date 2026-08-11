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

static t_list	*build_ip(int *tab, int n)
{
	t_list	*head;
	t_list	*tail;
	t_list	*node;
	int		i;

	head = NULL;
	tail = NULL;
	i = 0;
	while (i < n)
	{
		node = malloc(sizeof(t_list));
		node->data = (void *)(intptr_t)tab[i];
		node->next = NULL;
		if (!head)
			head = node;
		else
			tail->next = node;
		tail = node;
		i++;
	}
	return (head);
}

/* Free the list this harness owns, after each case. Without it every case's
 * nodes are retained for the whole run: measured 246 MB peak RSS at the wired
 * count of 400000, on a suite whose own README calls the campus box
 * memory-tight. `head` exists so the list is still reachable to free -- it used
 * to be built inline as an argument and lost the moment the call returned. */
static void	free_ip(t_list *l)
{
	t_list	*next;

	while (l)
	{
		next = l->next;
		free(l);
		l = next;
	}
}

int	main(void)
{
	char			line[8192];
	char			*f[3];
	int				tab[64];
	int				n;
	unsigned int	idx;
	t_list			*head;
	t_list			*r;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		n = parse_csv(f[0], tab);
		idx = (unsigned int)strtoul(f[1], NULL, 10);
		head = build_ip(tab, n);
		r = ft_list_at(head, idx);
		if (r == NULL)
			printf("%s\t%s\tNULL\n", f[0], f[1]);
		else
			printf("%s\t%s\t%d\n", f[0], f[1], (int)(intptr_t)r->data);
		free_ip(head);
	}
	return (0);
}
