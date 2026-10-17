/* Live-differential reader harness for ft_count_if.
 * Line: <n>\t<tok0,tok1,...>\t<count>\t<tokens-after-the-call>. n in
 * decimal, the tokens, each one string, two hex digits per byte,
 * comma-separated; then what ft_count_if returned, in decimal; and the FOURTH
 * column, the array re-read after the call: ft_count_if is read-only over it
 * and the strings it points at.
 *
 * Fixed predicate f(s) = (s[0] is a lowercase vowel). Builds a NULL-terminated
 * char**, calls ft_count_if, and reprints the four columns. See diffio.h. */
#include "diffio.h"

int	ft_count_if(char **tab, int length, int (*f)(char *));

static int	vowel_first(char *s)
{
	char	c;

	c = s[0];
	return (c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u');
}

int	main(void)
{
	char	*line;
	size_t	linecap;
	char	*f[3];
	char	**arr;
	int		n;
	int		res;
	int		i;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus holds
	 * arrays of 5000 strings (finding 041), and a fixed buffer stops on the
	 * first line longer than it. */
	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 3) < 3)
			continue ;
		n = (int)strtol(f[0], NULL, 10);
		/* echo the input fields first: what the call does to the array is
		 * re-read from it afterwards. */
		printf("%s\t%s\t", f[0], f[1]);
		arr = dio_hex_n(f[1], n);
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
		dio_free_list(arr, n);
	}
	free(line);
	return (0);
}
