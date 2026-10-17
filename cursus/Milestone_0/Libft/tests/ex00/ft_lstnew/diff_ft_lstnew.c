/* Live-differential reader harness for ft_lstnew.
 * Line: <v>\t<content>\t<nextIsNull>. Makes one node whose content is the int
 * v carried as (void *)(intptr_t)v, and reprints v, the content the node holds
 * read back as an int, and 1 when its next is NULL (0 when it is not) -- or
 * v and NULL alone, when ft_lstnew returned NULL. Each node is freed. */
#include <stdint.h>
#include "libft.h"
#include "diffio.h"

t_list	*ft_lstnew(void *content);

int	main(void)
{
	char	*line;
	size_t	cap;
	char	*f[3];
	long	v;
	t_list	*node;

	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		if (dio_split(line, f, 3) < 1)
			continue ;
		v = strtol(f[0], NULL, 10);
		node = ft_lstnew((void *)(intptr_t)v);
		if (node == NULL)
			printf("%s\tNULL\n", f[0]);
		else
		{
			printf("%s\t%d\t%d\n", f[0], (int)(intptr_t)node->content,
				node->next == NULL);
			free(node);
		}
	}
	free(line);
	return (0);
}
