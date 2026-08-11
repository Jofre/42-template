/* Live-differential reader harness for ft_foreach.
 * Line: <csv>\t<visited-csv>\t<csv-after-the-call>. csv = comma-joined decimal
 * ints ("" for size 0). The THIRD column is the array re-read after the call:
 * ft_foreach must not modify it, and that column is what checks it.
 * The fixed callback appends each received value to a buffer; after ft_foreach
 * returns we reprint <csv>\t<visited-csv> from that buffer, so a correct impl
 * (visits each element once, in order) matches the reference. See diffio.h. */
#include "diffio.h"

void	ft_foreach(int *tab, int length, void (*f)(int));

static int	g_buf[8192];
static int	g_n;

static void	collect(int x)
{
	if (g_n < (int)(sizeof(g_buf) / sizeof(g_buf[0])))
		g_buf[g_n++] = x;
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

int	main(void)
{
	char	line[8192];
	char	*f[2];
	int		tab[64];
	int		size;
	int		i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		size = parse_csv(f[0], tab);
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
	}
	return (0);
}
