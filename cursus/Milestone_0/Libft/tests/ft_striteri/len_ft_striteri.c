/* Length-series harness for ft_striteri (perf, tools/perf_test.sh).
 *
 * Line: <letters>, a string of ANY length, every byte a letter of either case
 * -- the series grows one string (oracle `c02_str_is_alpha_len <seed> <cases>
 * <length>`) -- read whole with getline(3), and handed to ft_striteri with
 * the harness's own f, which writes nothing and counts its calls.
 *
 * It CHECKS its own result, by construction: one call per letter, and the
 * line unchanged. The first wrong one is exit 3, and the series reports that
 * length as wrong rather than timing it. Nothing is printed; perf_run
 * discards stdout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void	ft_striteri(char *s, void (*f)(unsigned int, char*));

static size_t	g_calls;

static void	count(unsigned int i, char *p)
{
	(void)i;
	(void)p;
	g_calls++;
}

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
			line[--got] = '\0';
		g_calls = 0;
		ft_striteri(line, count);
		if (g_calls != (size_t)got || strlen(line) != (size_t)got)
			return (3);
	}
	free(line);
	return (0);
}
