/* Length-series harness for ft_strmapi (perf, tools/perf_test.sh).
 *
 * Line: <letters>, a string of ANY length, every byte a letter of either case
 * -- the series grows one string (oracle `c02_str_is_alpha_len <seed> <cases>
 * <length>`) -- read whole with getline(3), and mapped with the harness's own
 * f, which gives back the byte it is handed.
 *
 * It CHECKS its own result, by construction: that f changes nothing, so the
 * result is the line itself. The first wrong one is exit 3, and the series
 * reports that length as wrong rather than timing it. Each result is freed.
 * Nothing is printed; perf_run discards stdout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char	*ft_strmapi(char const *s, char (*f)(unsigned int, char));

static char	same(unsigned int i, char c)
{
	(void)i;
	return (c);
}

int	main(void)
{
	char	*line;
	size_t	cap;
	ssize_t	got;
	char	*r;
	int		ok;

	line = NULL;
	cap = 0;
	while ((got = getline(&line, &cap, stdin)) > 0)
	{
		if (line[got - 1] == '\n')
			line[got - 1] = '\0';
		r = ft_strmapi(line, same);
		ok = (r != NULL && strcmp(r, line) == 0);
		free(r);
		if (!ok)
			return (3);
	}
	free(line);
	return (0);
}
