/*
 * Memory-safety probe for ft_count_if (Piscine Reloaded) — run under ASan.
 *
 * The array is allocated to hold exactly its elements plus the terminating
 * NULL, so a walk that does not stop at the NULL reads one pointer past the
 * block, and ASan reports it -- a bug a stack array hides, since the bytes after
 * it are usually readable. The result is not checked here: that is the output
 * layer's job, and this probe is about memory alone.
 */
#include <ctype.h>
#include <stdlib.h>

int	ft_count_if(char **tab, int (*f)(char *));

static int	first_is_upper(char *s)
{
	if (isupper((unsigned char)s[0]))
		return (1);
	return (0);
}

/* Builds an exact-sized heap array of `n` strings plus its NULL, and scans it. */
static void	run(int n)
{
	char		**tab;
	int			i;
	static char	*words[] = {"Apple", "berry", "Cherry", "date"};

	tab = malloc(sizeof(char *) * (n + 1));
	if (!tab)
		return ;
	i = 0;
	while (i < n)
	{
		tab[i] = words[i];
		i++;
	}
	tab[n] = NULL;
	ft_count_if(tab, &first_is_upper);
	free(tab);
}

int	main(void)
{
	run(0);
	run(1);
	run(4);
	return (0);
}
