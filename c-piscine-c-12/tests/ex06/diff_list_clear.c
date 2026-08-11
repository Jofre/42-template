/* Live-differential reader harness for ft_list_clear.
 * Line: <csv>\t<freeCount>. Builds a list (data = (void*)(intptr_t)v), clears
 * it with a free_fct that only tallies how many times it is invoked, and
 * reprints <csv>\t<count>. A correct clear calls free_fct once per element,
 * so the count equals the list size. */
#include "ft_list.h"
#include "diffio.h"
#include <stdint.h>

void	ft_list_clear(t_list *begin_list, void (*free_fct)(void *));

static int	g_freed;

static void	count_free(void *data)
{
	(void)data;
	g_freed++;
}

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

int	main(void)
{
	char	line[8192];
	char	*f[2];
	int		tab[64];
	int		n;
	t_list	*begin;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		n = parse_csv(f[0], tab);
		begin = build_ip(tab, n);
		g_freed = 0;
		ft_list_clear(begin, &count_free);
		printf("%s\t%d\n", f[0], g_freed);
	}
	return (0);
}
