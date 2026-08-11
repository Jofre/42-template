#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>

static void	clear_print(t_list *begin)
{
	t_list	*tmp;

	while (begin != NULL)
	{
		printf("%s\n", (char *)begin->data);
		tmp = begin;
		begin = begin->next;
		free(tmp);
	}
}

int	main(void)
{
	char	*strs[3];
	t_list	*begin;

	strs[0] = "one";
	strs[1] = "two";
	strs[2] = "three";
	begin = ft_list_push_strs(3, strs);
	clear_print(begin);
	begin = ft_list_push_strs(1, strs);
	printf("%d\n", begin != NULL);
	clear_print(begin);
	begin = ft_list_push_strs(0, strs);
	printf("%d\n", begin == NULL);
	clear_print(begin);
	return (0);
}
