/* Live-differential reader harness for ft_count_if.
 * Line: <n>\t<tok0,tok1,...>\t<count>\t<tokens-after-the-call>. tokens =
 * lowercase-hex C strings. The FOURTH column is the array re-read after the
 * call: ft_count_if is read-only over it and the strings it points at.
 * Fixed predicate f(s) = (s[0] is a lowercase vowel). Builds a NULL-terminated
 * char**, calls ft_count_if, reprints <n>\t<tokens>\t<count>. See diffio.h. */
#include "diffio.h"

int	ft_count_if(char **tab, int length, int (*f)(char *));

static int	vowel_first(char *s)
{
	char	c;

	c = s[0];
	return (c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u');
}

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
	int		res;
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
		res = ft_count_if(arr, n, vowel_first);
		printf("%d\t", res);
		/* re-echo the tokens AFTER the call: ft_count_if is read-only over the
		 * array and the strings it points at. */
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
