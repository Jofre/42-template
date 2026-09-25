/* Live-differential reader harness for ft_list_push_front.
 * Line: <csv>\t<result-csv>. Pushes each int (in csv order, data =
 * (void*)(intptr_t)v) onto the front of an initially-empty list, then
 * serialises the resulting data sequence (== input reversed). */
#include "ft_list.h"
#include "diffio.h"
#include <stdint.h>

void	ft_list_push_front(t_list **begin_list, void *data);

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

/* Serialise the list's data as csv, reading at most `cap` nodes: the case's
 * length plus one, so a list one node too long still prints whole. A list
 * still going after that -- longer than the pushes can explain, or looping
 * back on itself -- gets a marker instead of an endless walk (a looping list
 * used to cost this layer a timeout). Each node read is recorded in `seen`,
 * and the count returned, so the caller can free them without walking the
 * list a second time. */
static int	ser_ip(t_list *l, int cap, t_list **seen)
{
	int	k;

	k = 0;
	while (l && k < cap)
	{
		if (k > 0)
			printf(",");
		printf("%d", (int)(intptr_t)l->data);
		seen[k++] = l;
		l = l->next;
	}
	if (l)
		printf(",...(list still going after %d nodes)", cap);
	printf("\n");
	return (k);
}

/* Free the nodes ser_ip recorded, after each case. Without it every case's
 * nodes are retained for the whole run: measured 246 MB peak RSS at the wired
 * count of 400000 on sorted_list_merge, on a suite whose own README calls the
 * campus box memory-tight. The nodes are released AFTER the call and from the
 * record, so whatever the function left behind is what gets released -- which
 * is also why the one exercise that frees its own nodes (ft_list_clear) has no
 * call to this. A node is recorded twice only when the list loops back on
 * itself; it is freed at its first slot only, so that mistake stays a readable
 * wrong answer instead of turning into a double-free crash. */
static void	free_seen(t_list **seen, int k)
{
	int	i;
	int	j;

	i = 0;
	while (i < k)
	{
		j = 0;
		while (j < i && seen[j] != seen[i])
			j++;
		if (j == i)
			free(seen[i]);
		i++;
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
	t_list	*seen[65];

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		n = parse_csv(f[0], tab);
		begin = NULL;
		i = 0;
		while (i < n)
		{
			ft_list_push_front(&begin, (void *)(intptr_t)tab[i]);
			i++;
		}
		printf("%s\t", f[0]);
		free_seen(seen, ser_ip(begin, n + 1, seen));
	}
	return (0);
}
