/* Live-differential reader harness for ft_foreach.
 * Line: <csv>\t<visited-csv>\t<csv-after-the-call>. csv = comma-joined decimal
 * ints ("" for size 0). The THIRD column is the array re-read after the call:
 * ft_foreach must not modify it, and that column is what checks it.
 * The fixed callback appends each received value to a buffer; after ft_foreach
 * returns we reprint <csv>\t<visited-csv> from that buffer, so a correct impl
 * (visits each element once, in order) matches the reference. See diffio.h. */
#include "diffio.h"

void	ft_foreach(int *tab, int length, void (*f)(int));

/* What the callback received, in a buffer sized from each case: one slot
 * more than the array has, so a call too many still shows, and a long array
 * is never cut short (tools/diffio.h, "SIZED FROM THE CASE"). */
static int	*g_buf;
static int	g_cap;
static int	g_n;

static void	collect(int x)
{
	if (g_n < g_cap)
		g_buf[g_n++] = x;
}

int	main(void)
{
	char	line[8192];
	char	*f[2];
	int		*tab;
	int		size;
	int		i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		tab = dio_csv_ints(f[0], &size);
		g_cap = size + 1;
		g_buf = (int *)dio_alloc((size_t)g_cap, sizeof(int));
		g_n = 0;
		ft_foreach(tab, size, collect);
		printf("%s\t", f[0]);
		i = 0;
		while (i < g_n)
		{
			if (i)
				printf(",");
			printf("%d", g_buf[i]);
			i++;
		}
		/* re-echo tab AFTER the call: asserts ft_foreach did not mutate it. */
		printf("\t");
		i = 0;
		while (i < size)
		{
			if (i)
				printf(",");
			printf("%d", tab[i]);
			i++;
		}
		printf("\n");
		free(g_buf);
		free(tab);
	}
	return (0);
}
