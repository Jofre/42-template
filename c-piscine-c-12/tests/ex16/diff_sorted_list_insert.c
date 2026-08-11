/* Live-differential reader harness for ft_sorted_list_insert.
 * Line: <sorted-csv>\t<value>\t<result-csv>. Builds an already-sorted list
 * whose data is a malloc'd int*, inserts one more value with the FIXED
 * comparator cmp_int (ascending: *(int*)a - *(int*)b), and serialises the
 * resulting data sequence. Input values are bounded so the comparator's
 * subtraction never overflows. */
#include "ft_list.h"
#include "diffio.h"

void	ft_sorted_list_insert(t_list **begin_list, void *data, int (*cmp)());

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
	int		*x;
	t_list	*begin;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		n = parse_csv(f[0], tab);
		begin = build_int(tab, n);
		x = malloc(sizeof(int));
		*x = (int)strtol(f[1], NULL, 10);
		ft_sorted_list_insert(&begin, x, &cmp_int);
		printf("%s\t%s\t", f[0], f[1]);
		ser_int(begin);
		free_int(begin);
	}
	return (0);
}
