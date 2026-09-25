/* Live-differential reader harness for ft_sort_string_tab.
 * Line: <n>\t<tok0,...>\t<sortedTok0,...>. tokens = lowercase-hex C strings.
 * Builds a NULL-terminated char**, sorts it in place (strcmp order), reprints
 * <n>\t<tokens>\t<sorted-tokens>. See diffio.h. */
#include "diffio.h"

void	ft_sort_string_tab(char **tab);

static void	build_tab(char *field, int n, char **arr)
{
	char	*toks[512];
	char	*p;
	int		i;

	p = field;
	if (n > 0)
	{
		toks[0] = p;
		i = 1;
		while (i < n)
		{
			p = strchr(p, ',');
			*p++ = '\0';
			toks[i++] = p;
		}
	}
	i = 0;
	while (i < n)
	{
		arr[i] = (char *)dio_unhex(toks[i], NULL, 0);
		i++;
	}
	arr[n] = NULL;
}

int	main(void)
{
	char	line[65536];
	char	*f[3];
	char	*arr[513];
	int		n;
	int		i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 3)
			continue ;
		n = (int)strtol(f[0], NULL, 10);
		/* echo the input fields BEFORE build_tab mutates f[1] (it splits the
		 * comma-joined tokens in place by writing NULs over the commas). */
		printf("%s\t%s\t", f[0], f[1]);
		build_tab(f[1], n, arr);
		ft_sort_string_tab(arr);
		i = 0;
		while (i < n)
		{
			if (i)
				printf(",");
			dio_puthex((unsigned char *)arr[i], strlen(arr[i]));
			i++;
		}
		printf("\n");
		i = 0;
		while (i < n)
			free(arr[i++]);
	}
	return (0);
}
