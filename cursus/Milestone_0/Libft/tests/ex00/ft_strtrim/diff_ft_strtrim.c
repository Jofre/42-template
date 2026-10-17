/* Live-differential reader harness for ft_strtrim.
 * Line: <hexS1>\t<hexSet>\t<hexTrimmed>. The string and the set, two hex
 * digits per byte, then what the returned string holds up to its NUL, as
 * hex -- or NULL when ft_strtrim returned NULL. The result is freed. See
 * tools/diffio.h. */
#include "diffio.h"

char	*ft_strtrim(char const *s1, char const *set);

int	main(void)
{
	char			*line;
	size_t			linecap;
	char			*f[3];
	unsigned char	*s1;
	unsigned char	*set;
	char			*res;

	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		s1 = dio_unhex(f[0], NULL, 0);
		set = dio_unhex(f[1], NULL, 0);
		res = ft_strtrim((char *)s1, (char *)set);
		printf("%s\t%s\t", f[0], f[1]);
		if (res == NULL)
			printf("NULL");
		else
			dio_puthex((unsigned char *)res, strlen(res));
		printf("\n");
		free(res);
		free(s1);
		free(set);
	}
	free(line);
	return (0);
}
