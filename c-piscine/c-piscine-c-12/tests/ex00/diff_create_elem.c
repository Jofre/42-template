/* Live-differential reader harness for ft_create_elem.
 * Line: <v>\t<v>\t1. Creates one element whose data is the int carried as
 * (void*)(intptr_t)v, and reprints <v>\t<data-as-int>\t<next==NULL?1:0>
 * (or just <v>\t"NULL" if the student returned NULL). The trailing flag
 * asserts the lone node's `next` link is initialised to NULL. */
#include "ft_list.h"
#include "diffio.h"
#include <stdint.h>

t_list	*ft_create_elem(void *data);

int	main(void)
{
	char	*line;
	size_t	cap;
	char	*f[2];
	long	v;
	t_list	*e;

	/* A line of any length (tools/diffio.h): the corpus holds lists and
	 * trees of hundreds and thousands of nodes (finding 041). */
	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		v = strtol(f[0], NULL, 10);
		e = ft_create_elem((void *)(intptr_t)v);
		if (e == NULL)
			printf("%s\tNULL\n", f[0]);
		else
		{
			printf("%s\t%d\t%d\n", f[0], (int)(intptr_t)e->data,
				e->next == NULL);
			free(e);
		}
	}
	free(line);
	return (0);
}
