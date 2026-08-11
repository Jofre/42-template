#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>

int	main(void)
{
	t_list	*elem;
	int		x;

	x = 42;
	elem = ft_create_elem("forty-two");
	if (elem == NULL)
		printf("NULL\n");
	else
	{
		printf("%s\n", (char *)elem->data);
		printf("%d\n", elem->next == NULL);
		free(elem);
	}
	elem = ft_create_elem(&x);
	if (elem == NULL)
		printf("NULL\n");
	else
	{
		printf("%d\n", elem->data == (void *)&x);
		printf("%d\n", elem->next == NULL);
		free(elem);
	}
	elem = ft_create_elem(NULL);
	if (elem == NULL)
		printf("NULL\n");
	else
	{
		printf("%d\n", elem->data == NULL);
		printf("%d\n", elem->next == NULL);
		free(elem);
	}
	return (0);
}
