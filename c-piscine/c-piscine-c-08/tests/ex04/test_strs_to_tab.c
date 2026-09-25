#include "ft_stock_str.h"
#include <stdio.h>
#include <stdlib.h>

struct s_stock_str	*ft_strs_to_tab(int ac, char **av);

/* One labeled line per element: the size, whether .str aliases av[i] (it should)
 * and whether .copy is a NEW allocation distinct from av[i] (it should). */
static void	show_elem(char *label, t_stock_str *tab, char **av, int i)
{
	printf("%s\tstr=%s size=%d copy=%s str_is_av=%d copy_is_new=%d\n",
		label, tab[i].str, tab[i].size, tab[i].copy,
		tab[i].str == av[i], tab[i].copy != av[i]);
}

int	main(void)
{
	char		*av[4];
	char		*empty[1];
	t_stock_str	*tab;
	int			i;

	av[0] = "zero";
	av[1] = "";
	av[2] = "a";
	av[3] = "fortytwo!";
	tab = ft_strs_to_tab(4, av);
	if (!tab)
		return (printf("four cases\tNULL\n"), 0);
	show_elem("[0] \"zero\"", tab, av, 0);
	show_elem("[1] \"\" (empty)", tab, av, 1);
	show_elem("[2] \"a\"", tab, av, 2);
	show_elem("[3] \"fortytwo!\"", tab, av, 3);
	printf("%s\tterminator_null:%d\n", "terminator (str == NULL)", tab[4].str == 0);
	i = 0;
	while (i < 4)
		free(tab[i++].copy);
	free(tab);
	empty[0] = 0;
	tab = ft_strs_to_tab(0, empty);
	printf("%s\tterminator_null:%d\n", "ac=0 (terminator only)", tab && tab[0].str == 0);
	free(tab);
	return (0);
}
