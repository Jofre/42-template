/* Length-series harness for ft_strtrim (perf, tools/perf_test.sh).
 *
 * Line: <letters>, a string of ANY length, every byte a letter of either case
 * -- the series grows one string (oracle `c02_str_is_alpha_len <seed> <cases>
 * <length>`) -- read whole with getline(3), and trimmed of the set "-",
 * which holds no letter.
 *
 * It CHECKS its own result, by construction: nothing at either end is in the
 * set, so the result is the line itself. The first wrong one is exit 3, and
 * the series reports that length as wrong rather than timing it. Each result
 * is freed. Nothing is printed; perf_run discards stdout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char	*ft_strtrim(char const *s1, char const *set);

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
		r = ft_strtrim(line, "-");
		ok = (r != NULL && strcmp(r, line) == 0);
		free(r);
		if (!ok)
			return (3);
	}
	free(line);
	return (0);
}
