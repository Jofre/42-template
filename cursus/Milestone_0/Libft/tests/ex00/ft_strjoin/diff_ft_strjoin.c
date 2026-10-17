/* Live-differential reader harness for ft_strjoin.
 * Line: <hexS1>\t<hexS2>\t<hexJoined>. The two strings, two hex digits per
 * byte, then what the returned string holds up to its NUL, as hex -- or NULL
 * when ft_strjoin returned NULL. The result is freed. See tools/diffio.h. */
#include "diffio.h"

char	*ft_strjoin(char const *s1, char const *s2);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[3];
	unsigned char	*s1;
	unsigned char	*s2;
	char			*res;

	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		s1 = dio_unhex(f[0], NULL, 0);
		s2 = dio_unhex(f[1], NULL, 0);
		res = ft_strjoin((char *)s1, (char *)s2);
		printf("%s\t%s\t", f[0], f[1]);
		if (res == NULL)
			printf("NULL");
		else
			dio_puthex((unsigned char *)res, strlen(res));
		printf("\n");
		free(res);
		free(s1);
		free(s2);
	}
	free(line);
	return (0);
}
