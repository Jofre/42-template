/* Length-series harness for ft_strstr (perf, tools/perf_test.sh).
 *
 * Line: <letters>, a string of ANY length whose only "zzz" is its last three
 * bytes -- the series grows one string (oracle `c03_strstr_len <seed> <cases>
 * <length>`), and a string shorter than three holds no 'z' at all -- read
 * whole with getline(3). The needle is "zzz", so a search reads the whole
 * string to find it.
 *
 * It CHECKS its own result, where the generator put the needle: the last
 * three bytes, or NULL for a string shorter than three. The first wrong one
 * is exit 3, and the series reports that length as wrong rather than timing
 * it. Nothing is printed; perf_run discards stdout.
 */
#include <stdio.h>
#include <stdlib.h>

char	*ft_strstr(char *str, char *to_find);

int	main(void)
{
	char	*line;
	size_t	cap;
	ssize_t	got;
	char	*at;

	line = NULL;
	cap = 0;
	while ((got = getline(&line, &cap, stdin)) > 0)
	{
		if (line[got - 1] == '\n')
			line[--got] = '\0';
		at = ft_strstr(line, "zzz");
		if (got >= 3 && at != line + got - 3)
			return (3);
		if (got < 3 && at != NULL)
			return (3);
	}
	free(line);
	return (0);
}
