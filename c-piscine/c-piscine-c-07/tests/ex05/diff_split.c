/* Live-differential reader harness for ft_split.
 * Line: <hexStr>\t<hexCharset>. Prints the token count, then each token content
 * as hex (tab-separated), and a trailing 1/0 for "returned a non-NULL array".
 * See tools/diffio.h. */
#include "diffio.h"

char	**ft_split(char *str, char *charset);

int	main(void)
{
	char			line[8192];
	char			*f[3];
	unsigned char	*str;
	unsigned char	*charset;
	char			**res;
	int				count;
	int				k;

	while (dio_line(line, sizeof(line)))
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
	return (0);
}
