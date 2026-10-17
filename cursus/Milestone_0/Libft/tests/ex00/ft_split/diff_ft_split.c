/* Live-differential reader harness for ft_split.
 * Line: <hexS>\t<hexC>\t<count>\t<hexTok>...\t<returned an array>. The
 * string, two hex digits per byte, the delimiter as two hex digits, how many
 * strings the returned array holds before its NULL, each string as hex, then
 * 1 or 0 for "returned a non-NULL array". See tools/diffio.h.
 *
 * The reference's count (the third field) caps the walk: the entry where
 * the reference has its NULL is read, and when it is not NULL the count says
 * one string too many while that entry is neither printed nor freed -- a
 * wrong answer may never have set it. Each string printed is freed, then the
 * array, as the box (p.11) says the caller releases it. */
#include "diffio.h"

char	**ft_split(char const *s, char c);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[4];
	unsigned char	*s;
	unsigned char	*c;
	char			**res;
	long			want;
	long			n;
	long			k;

	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 4) < 3)
			continue ;
		s = dio_unhex(f[0], NULL, 0);
		c = dio_unhex(f[1], NULL, 0);
		want = strtol(f[2], NULL, 10);
		res = ft_split((char *)s, (char)c[0]);
		n = 0;
		while (res && n <= want && res[n])
			n++;
		printf("%s\t%s\t%ld", f[0], f[1], n);
		k = 0;
		while (k < n && k < want)
		{
			printf("\t");
			dio_puthex((unsigned char *)res[k], strlen(res[k]));
			k++;
		}
		printf("\t%d\n", res != NULL);
		k = 0;
		while (k < n && k < want)
			free(res[k++]);
		free(res);
		free(s);
		free(c);
	}
	free(line);
	return (0);
}
