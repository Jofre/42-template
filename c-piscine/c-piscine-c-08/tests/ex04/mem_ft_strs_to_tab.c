/* Memory-safety probe for ft_strs_to_tab — run under AddressSanitizer.
 * ft_strs_to_tab(ac, av) turns the FIRST ac strings of av into a struct array,
 * so a correct version reads only av[0..ac-1], never av[ac]. Each av below is
 * a HEAP block of EXACTLY ac char* (no slack) and each string a HEAP block of
 * exactly strlen+1 bytes, so any read at index == ac — or one byte past a
 * string's NUL — is a guaranteed buffer overflow ASan flags, while a correct
 * call returns a tab we free cleanly (str aliases av, copy is a fresh block).
 * ac 0 and 1 are exercised too: with ac 0 the array is a 0-byte block that must
 * never be dereferenced. This is a test input, not an implementation. */
#include "ft_stock_str.h"
#include <stdlib.h>
#include <string.h>

t_stock_str	*ft_strs_to_tab(int ac, char **av);

/* Copy ac strings into a heap array of EXACTLY ac blocks of strlen+1 bytes. */
static char	**build_av(int ac, char **src)
{
	char	**av;
	int		i;
	size_t	len;

	av = malloc(sizeof(char *) * (size_t)ac);
	i = 0;
	while (i < ac)
	{
		len = strlen(src[i]);
		av[i] = malloc(len + 1);
		memcpy(av[i], src[i], len + 1);
		i++;
	}
	return (av);
}

/* Free the tab the function returned: each fresh copy, then the array. */
static void	free_tab(t_stock_str *tab, int ac)
{
	int	i;

	if (!tab)
		return ;
	i = 0;
	while (i < ac)
		free(tab[i++].copy);
	free(tab);
}

/* Free the probe's own exact-sized av and its strings (str aliased av). */
static void	free_av(char **av, int ac)
{
	int	i;

	i = 0;
	while (i < ac)
		free(av[i++]);
	free(av);
}

/* Build an exact-sized av, run the function on it, then release everything. */
static void	run(int ac, char **src)
{
	char		**av;
	t_stock_str	*tab;

	av = build_av(ac, src);
	tab = ft_strs_to_tab(ac, av);
	free_tab(tab, ac);
	free_av(av, ac);
}

int	main(void)
{
	char	*four[4];
	char	*one[1];

	four[0] = "zero";
	four[1] = "";
	four[2] = "a";
	four[3] = "fortytwo!";
	one[0] = "x";
	run(4, four);
	run(1, one);
	run(0, four);
	return (0);
}
