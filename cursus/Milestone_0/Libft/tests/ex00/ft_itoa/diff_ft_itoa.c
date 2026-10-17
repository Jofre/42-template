/* Live-differential reader harness for ft_itoa.
 * Line: <n>\t<decimal>. The int in decimal, then the string ft_itoa returned,
 * raw -- digits and '-' are all it may hold -- or NULL when it returned NULL.
 * The result is freed. See tools/diffio.h. */
#include "diffio.h"

char	*ft_itoa(int n);

int	main(void)
{
	char	*line;
	size_t	linecap;
	char	*f[2];
	char	*res;

	line = NULL;
	linecap = 0;
	while (dio_getline(&line, &linecap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		res = ft_itoa((int)strtol(f[0], NULL, 10));
		printf("%s\t%s\n", f[0], res ? res : "NULL");
		free(res);
	}
	free(line);
	return (0);
}
