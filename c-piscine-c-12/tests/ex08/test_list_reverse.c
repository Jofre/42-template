#include "ft_list.h"
#include <stdio.h>

int	main(void)
{
	t_list	a;
	t_list	b;
	t_list	c;
	t_list	solo;
	t_list	*begin;
	t_list	*walk;

	c.data = "3";
	c.next = NULL;
	b.data = "2";
	b.next = &c;
	a.data = "1";
	a.next = &b;
	begin = &a;
	ft_list_reverse(&begin);
	walk = begin;
	while (walk != NULL)
	{
		printf("%s\n", (char *)walk->data);
		walk = walk->next;
	}
	printf("%d\n", begin == &c);
	printf("%d\n", begin != NULL && begin->next == &b);
	printf("%d\n", begin != NULL && begin->next != NULL
		&& begin->next->next == &a);
	printf("%d\n", a.next == NULL);
	solo.data = "only";
	solo.next = NULL;
	begin = &solo;
	ft_list_reverse(&begin);
	printf("%d\n", begin == &solo);
	printf("%d\n", begin != NULL && begin->next == NULL);
	begin = NULL;
	ft_list_reverse(&begin);
	printf("%d\n", begin == NULL);
	return (0);
}
