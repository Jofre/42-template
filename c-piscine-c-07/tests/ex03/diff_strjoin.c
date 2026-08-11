/* Live-differential reader harness for ft_strjoin.
 * Line: <size>\t<count>\t<hexSep>\t<hexStr0>...<hexStr(count-1)>. Builds the
 * strs array, joins, and prints the result content as hex (or NULL).
 * size == count here. See tools/diffio.h. */
#include "diffio.h"

char	*ft_strjoin(int size, char **strs, char *sep);

int	main(void)
{
	char			line[16384];
	char			*f[32];
	int				nf;
	int				size;
	int				count;
	unsigned char	*sep;
	char			**strs;
	char			*res;
	int				k;

	while (dio_line(line, sizeof(line)))
	{
		nf = dio_split(line, f, 32);
		if (nf < 3)
			continue ;
		size = (int)strtol(f[0], NULL, 10);
		count = (int)strtol(f[1], NULL, 10);
		sep = dio_unhex(f[2], NULL, 0);
		if (nf < 3 + count)
			continue ;
		strs = (char **)malloc(sizeof(char *) * (count ? count : 1));
		k = 0;
		while (k < count)
		{
			strs[k] = (char *)dio_unhex(f[3 + k], NULL, 0);
			k++;
		}
		res = ft_strjoin(size, strs, (char *)sep);
		printf("%s\t%s\t%s\t", f[0], f[1], f[2]);
		k = 0;
		while (k < count)
		{
			printf("%s\t", f[3 + k]);
			k++;
		}
		if (!res)
			printf("NULL");
		else
			dio_puthex((unsigned char *)res, strlen(res));
		printf("\n");
		k = 0;
		while (k < count)
			free(strs[k++]);
		free(strs);
		free(sep);
		free(res);
	}
	return (0);
}
