/* Live-differential reader harness for ft_split.
 * Line: <hexStr>\t<hexCharset>\t<count>\t<hexWord>...\t<returned an array>.
 * The string and the separators, two hex digits per byte, how many words the
 * returned array holds, each word as hex, then 1 or 0 for "returned a
 * non-NULL array". See tools/diffio.h. */
#include "diffio.h"

char	**ft_split(char *str, char *charset);

/* The line is read whole however long it is (dio_getline): the corpus holds
 * strings of thousands of words (finding 041), which a line[8192] cut in two. */
int	main(void)
{
	char			*line;
	size_t			cap;
	char			*f[3];
	unsigned char	*str;
	unsigned char	*charset;
	char			**res;
	int				count;
	int				k;

	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		str = dio_unhex(f[0], NULL, 0);
		charset = dio_unhex(f[1], NULL, 0);
		res = ft_split((char *)str, (char *)charset);
		count = 0;
		while (res && res[count])
			count++;
		printf("%s\t%s\t%d", f[0], f[1], count);
		k = 0;
		while (k < count)
		{
			printf("\t");
			dio_puthex((unsigned char *)res[k], strlen(res[k]));
			k++;
		}
		printf("\t%d\n", res != NULL);
		if (res)
		{
			k = 0;
			while (k < count)
				free(res[k++]);
			free(res);
		}
		free(str);
		free(charset);
	}
	free(line);
	return (0);
}
