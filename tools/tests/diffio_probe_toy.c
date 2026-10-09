/* diffio_probe_toy.c -- the invented function diffio_probe.c reads: it makes
 * a three-field record and writes the first and the last field, never the
 * middle one. A file of its own, so the reader's compiler cannot see which
 * field goes unwritten. */
#include <stdlib.h>

typedef struct s_trio
{
	void	*a;
	void	*b;
	void	*c;
}	t_trio;

t_trio	*toy_trio_new(void *c)
{
	t_trio	*t;

	t = malloc(sizeof(t_trio));
	if (t == NULL)
		return (NULL);
	t->a = NULL;
	t->c = c;
	return (t);
}
