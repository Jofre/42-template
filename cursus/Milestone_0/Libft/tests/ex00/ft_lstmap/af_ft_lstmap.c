/* Allocation-failure probe for ft_lstmap. A test input, not a solution.
 *
 * af_case() makes ONE call into the library, on a list of three nodes of the
 * probe's own: the layer runs it once per malloc the call reaches, refusing a
 * different one each time, and asks that the call return NULL, as its box
 * says it does when an allocation fails. f's results come from the probe's
 * own allocator (this file's malloc is never refused, see
 * tools/allocfail_shim.c), and del frees them: when a refusal hits, the
 * contents f already made are the ones del is for. */
#include <stdlib.h>
#include "libft.h"

t_list	*ft_lstmap(t_list *lst, void *(*f)(void *), void (*del)(void *));

static void	*f(void *content)
{
	int	*r;

	r = malloc(sizeof(int));
	if (r != NULL)
		*r = *(int *)content * 3 - 1;
	return (r);
}

static void	del(void *content)
{
	free(content);
}

void	*af_case(void)
{
	static int		value[3] = {1, 2, 3};
	static t_list	node[3];

	node[0].content = &value[0];
	node[0].next = &node[1];
	node[1].content = &value[1];
	node[1].next = &node[2];
	node[2].content = &value[2];
	node[2].next = NULL;
	return (ft_lstmap(&node[0], &f, &del));
}
