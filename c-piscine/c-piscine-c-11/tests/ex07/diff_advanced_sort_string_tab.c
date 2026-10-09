/* Live-differential reader harness for ft_advanced_sort_string_tab.
 * Line: <n>\t<tok0,...>\t<sortedTok0,...>. n in decimal, then the tokens
 * before the call and the array after it; each token is one string, two hex
 * digits per byte, and the tokens are comma-separated.
 *
 * Fixed comparator cmp = strcmp. Builds a NULL-terminated char**, sorts it in
 * place via cmp, reprints <n>\t<tokens>\t<sorted-tokens>. See diffio.h. */
#include "diffio.h"

void	ft_advanced_sort_string_tab(char **tab, int (*cmp)(char *, char *));

static int	cmp_strcmp(char *a, char *b)
{
	return (strcmp(a, b));
}

int	main(void)
{
	char	line[65536];
	char	*f[3];
	char	**arr;
	int		n;
	int		i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 3)
			continue ;
		n = (int)strtol(f[0], NULL, 10);
		/* echo the input fields first: what the call does to the array is
		 * re-read from it afterwards. */
		printf("%s\t%s\t", f[0], f[1]);
		arr = dio_hex_n(f[1], n);
		ft_advanced_sort_string_tab(arr, cmp_strcmp);
		i = 0;
		while (i < n)
		{
			if (i)
				printf(",");
			dio_puthex((unsigned char *)arr[i], strlen(arr[i]));
			i++;
		}
		printf("\n");
		dio_free_list(arr, n);
	}
	return (0);
}
