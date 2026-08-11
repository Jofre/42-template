/* Live-differential reader harness for ft_list_push_back.
 * Line: <csv>\t<result-csv>. Pushes each int (in csv order, data =
 * (void*)(intptr_t)v) onto the back of an initially-empty list, then
 * serialises the resulting data sequence (== input order). */
#include "ft_list.h"
#include "diffio.h"
#include <stdint.h>

void	ft_list_push_back(t_list **begin_list, void *data);

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

static void	ser_ip(t_list *l)
{
	int	first;

	first = 1;
	while (l)
	{
		if (!first)
			printf(",");
		printf("%d", (int)(intptr_t)l->data);
		first = 0;
		l = l->next;
	}
	printf("\n");
}

/* Free the list this harness owns, after each case. Without it every case's
 * nodes are retained for the whole run: measured 246 MB peak RSS at the wired
 * count of 400000 on sorted_list_merge, on a suite whose own README calls the
 * campus box memory-tight. The list is freed AFTER the call, so whatever the
 * function left behind is what gets released -- which is also why the one
 * exercise that frees its own nodes (ft_list_clear) has no call to this. */
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
	int		i;
	t_list	*begin;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		n = parse_csv(f[0], tab);
		begin = NULL;
		i = 0;
		while (i < n)
		{
			ft_list_push_back(&begin, (void *)(intptr_t)tab[i]);
			i++;
		}
		printf("%s\t", f[0]);
		ser_ip(begin);
		free_ip(begin);
	}
	return (0);
}
