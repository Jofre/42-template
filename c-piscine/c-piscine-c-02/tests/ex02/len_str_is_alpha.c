/* Length-series harness for ft_str_is_alpha (perf, tools/perf_test.sh).
 *
 * Line: <letters>, a string of ANY length, every byte a letter of either case
 * -- the series grows one string (oracle `c02_str_is_alpha_len <seed> <cases>
 * <length>`) -- read whole with getline(3).
 *
 * It CHECKS its own result, by construction: a string of letters alone gets
 * 1. The first wrong one is exit 3, and the series reports that length as
 * wrong rather than timing it. Nothing is printed; perf_run discards stdout.
 */
#include <stdio.h>
#include <stdlib.h>

int	ft_str_is_alpha(char *str);

int	main(void)
{
	char	*line;
	size_t	cap;
	ssize_t	got;

	line = NULL;
	cap = 0;
	while ((got = getline(&line, &cap, stdin)) > 0)
	{
		if (line[got - 1] == '\n')
			line[got - 1] = '\0';
		if (ft_str_is_alpha(line) != 1)
			return (3);
	}
	free(line);
	return (0);
}
