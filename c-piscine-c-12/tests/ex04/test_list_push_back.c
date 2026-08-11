#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>

int	main(void)
{
	t_list	*begin;
	t_list	*tmp;

	begin = NULL;
	ft_list_push_back(&begin, "a");
	ft_list_push_back(&begin, "b");
	ft_list_push_back(&begin, "c");
	ft_list_push_back(&begin, "d");
	while (begin != NULL)
	{
		printf("%s\n", (char *)begin->data);
		tmp = begin;
		begin = begin->next;
		free(tmp);
	}
	begin = NULL;
	ft_list_push_back(&begin, "solo");
	printf("%d\n", begin != NULL);
	if (begin != NULL)
	{
		printf("%s\n", (char *)begin->data);
		printf("%d\n", begin->next == NULL);
		free(begin);
	}
	return (0);
}
