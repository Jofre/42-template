/* Live-differential reader harness for ft_list_foreach_if.
 * Line: <csv>\t<ref>\t<result-csv>. Builds a list (data = malloc'd int*) and
 * applies the FIXED callback add_100 (x -> x+100) to every element for which
 * cmp_int(data, &ref) == 0 (i.e. value == ref), then serialises the result.
 * Values and ref share a small range so matches are common. */
#include "ft_list.h"
#include "diffio.h"

void	ft_list_foreach_if(t_list *begin_list, void (*f)(void *),
			void *data_ref, int (*cmp)(void *, void *));

static void	add_100(void *p)
{
	*(int *)p = *(int *)p + 100;
}

static int	cmp_int(void *a, void *b)
{
	return (*(int *)a - *(int *)b);
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

static t_list	*build_int(int *tab, int n)
{
	t_list	*head;
	t_list	*tail;
	t_list	*node;
	int		*d;
	int		i;

	head = NULL;
	tail = NULL;
	i = 0;
	while (i < n)
	{
		node = malloc(sizeof(t_list));
		d = malloc(sizeof(int));
		*d = tab[i];
		node->data = d;
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

static void	ser_int(t_list *l)
{
	int	first;

	first = 1;
	while (l)
	{
		if (!first)
			printf(",");
		printf("%d", *(int *)l->data);
		first = 0;
		l = l->next;
	}
	printf("\n");
}

/* Free the list this harness owns, after each case -- node AND the int each
 * node points at. Without it every case's allocations are retained for the
 * whole run: measured 246 MB peak RSS at the wired count of 400000, on a suite
 * whose own README calls the campus box memory-tight. */
static void	free_int(t_list *l)
{
	t_list	*next;

	while (l)
	{
		next = l->next;
		free(l->data);
		free(l);
		l = next;
	}
}

int	main(void)
{
	char	line[8192];
	char	*f[3];
	int		tab[64];
	int		n;
	int		ref;
	t_list	*begin;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		n = parse_csv(f[0], tab);
		ref = (int)strtol(f[1], NULL, 10);
		begin = build_int(tab, n);
		ft_list_foreach_if(begin, &add_100, &ref, &cmp_int);
		printf("%s\t%s\t", f[0], f[1]);
		ser_int(begin);
		free_int(begin);
	}
	return (0);
}
