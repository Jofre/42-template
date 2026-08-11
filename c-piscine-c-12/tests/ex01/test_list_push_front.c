#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>

int	main(void)
{
	t_list	*begin;
	t_list	*tmp;

	begin = NULL;
	ft_list_push_front(&begin, "a");
	ft_list_push_front(&begin, "b");
	ft_list_push_front(&begin, "c");
	ft_list_push_front(&begin, "d");
	while (begin != NULL)
	{
		printf("%s\n", (char *)begin->data);
		tmp = begin;
		begin = begin->next;
		free(tmp);
	}
	begin = NULL;
	ft_list_push_front(&begin, "solo");
	printf("%d\n", begin != NULL);
	if (begin != NULL)
	{
		printf("%s\n", (char *)begin->data);
		printf("%d\n", begin->next == NULL);
		free(begin);
	}
	return (0);
}
