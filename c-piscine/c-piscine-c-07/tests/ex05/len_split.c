/* Length-series harness for ft_split (perf, tools/perf_test.sh).
 *
 * Line: <string><TAB><words>, the string <length> words of letters between
 * runs of '_' and '-', of ANY length -- the series grows one string (oracle
 * `c07_split_len <seed> <cases> <length>`) -- and after the tab the words the
 * generator laid down, comma-joined. It is read whole with getline(3), and
 * the string is split with the charset "_-".
 *
 * It CHECKS its own result against those words, because nothing else compares
 * these long outputs: one string per word, the same bytes, in order, and the
 * NULL that ends the array right after the last. It splits nothing itself.
 * The first wrong one is exit 3, and the series reports that length as wrong
 * rather than timing it. Every string the result holds, and the array, are
 * freed, as a caller of ft_split must. Nothing is printed; perf_run discards
 * stdout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char	**ft_split(char *str, char *charset);

static int	same_words(char **got, char *want)
{
	char	*w;
	int		i;

	i = 0;
	w = strtok(want, ",");
	while (w != NULL)
	{
		if (got[i] == NULL || strcmp(got[i], w) != 0)
			return (0);
		i++;
		w = strtok(NULL, ",");
	}
	return (got[i] == NULL);
}

int	main(void)
{
	char	*line;
	size_t	cap;
	ssize_t	got;
	char	*tab;
	char	**words;
	int		i;
	int		ok;

	line = NULL;
	cap = 0;
	while ((got = getline(&line, &cap, stdin)) > 0)
	{
		if (line[got - 1] == '\n')
			line[got - 1] = '\0';
		tab = strchr(line, '\t');
		if (tab == NULL)
			return (2);
		*tab = '\0';
		words = ft_split(line, "_-");
		if (words == NULL)
			return (3);
		ok = same_words(words, tab + 1);
		i = 0;
		while (words[i] != NULL)
			free(words[i++]);
		free(words);
		if (!ok)
			return (3);
	}
	free(line);
	return (0);
}
