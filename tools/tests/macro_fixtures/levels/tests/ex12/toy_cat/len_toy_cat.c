/* Length-series harness for toy_cat, the toy library's member (perf,
 * tools/perf_test.sh, c_perf's `length`).
 *
 * Line: a string of letters of ANY length -- the series grows one string
 * (a real //oracle length arm of that line shape stands in for a toy arm,
 * as the toy's replays borrow theirs) -- read whole with getline(3). A
 * NULL result is wrong, exit 3, and the series reports that length as
 * wrong rather than timing it. Nothing is printed. */
#include <stdio.h>
#include <stdlib.h>

char	*toy_cat(char *s);

int	main(void)
{
	char	*line;
	char	*r;
	size_t	cap;
	ssize_t	got;

	line = NULL;
	cap = 0;
	while ((got = getline(&line, &cap, stdin)) > 0)
	{
		if (line[got - 1] == '\n')
			line[got - 1] = '\0';
		r = toy_cat(line);
		if (r == NULL)
			return (3);
		free(r);
	}
	free(line);
	return (0);
}
