/* Live-differential reader harness for ft_strjoin.
 * Line: <size>\t<count>\t<hexSep>\t<hexStr0>...\t<hexResult>. size and the
 * number of strings in decimal (the same number here), the separator and
 * each string, two hex digits per byte, then what the returned string holds
 * up to its NUL, as hex -- or NULL when ft_strjoin returned NULL.
 * See tools/diffio.h. */
#include "diffio.h"

char	*ft_strjoin(int size, char **strs, char *sep);

int	main(void)
{
	char			*line;
	size_t			cap;
	char			**f;
	int				nf;
	int				size;
	int				count;
	unsigned char	*sep;
	char			**strs;
	char			*res;
	int				k;

	/* A line of any length (tools/diffio.h, dio_getline): the corpus joins
	 * hundreds of strings in one case, past every round capacity. */
	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		/* Every field, however many strings the case joins: f[32] held 28
		 * of them and silently skipped a case with more (tools/diffio.h,
		 * "SIZED FROM THE CASE"). */
		f = dio_split_all(line, &nf);
		if (nf < 3)
		{
			free(f);
			continue ;
		}
		size = (int)strtol(f[0], NULL, 10);
		count = (int)strtol(f[1], NULL, 10);
		if (count < 0 || nf < 3 + count)
			dio_fail("a strjoin case holds fewer strings than its count");
		sep = dio_unhex(f[2], NULL, 0);
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
		free(f);
	}
	free(line);
	return (0);
}
