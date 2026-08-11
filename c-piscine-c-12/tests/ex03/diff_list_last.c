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
 * memory-tight. */
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
		free_ip(head);
	}
	return (0);
}
