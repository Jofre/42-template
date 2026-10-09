/* Live-differential reader harness for ft_any.
 * Line: <n>\t<tok0,tok1,...>\t<0|1>\t<tokens-after-the-call>. n in decimal,
 * the tokens, each one string, two hex digits per byte, comma-separated; then
 * 1 if ft_any returned non-zero, else 0; and the FOURTH column, the array
 * re-read after the call: ft_any is read-only over it and the strings it
 * points at.
 *
 * Fixed predicate f(s) = (strlen(s) >= 3). Builds a NULL-terminated char**,
 * calls ft_any, and reprints the four columns. See diffio.h. */
#include "diffio.h"

int	ft_any(char **tab, int (*f)(char *));

static int	is_long(char *s)
{
	return (strlen(s) >= 3);
}

int	main(void)
{
	char	line[65536];
	char	*f[3];
	char	**arr;
	int		n;
	int		res;
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
		res = ft_any(arr, is_long);
		printf("%d\t", !!res);
		/* re-echo the tokens AFTER the call: ft_any is read-only over the
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
	return (0);
}
