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
	int		k;

	c.data = "3";
	c.next = NULL;
	b.data = "2";
	b.next = &c;
	a.data = "1";
	a.next = &b;
	begin = &a;
	ft_list_reverse(&begin);
	/* Print at most four nodes: three exist, so a fourth can only mean the
	 * list now loops back on itself, and it gets a line saying so instead of
	 * an endless run. */
	walk = begin;
	k = 0;
	while (walk != NULL && k < 4)
	{
		printf("%s\n", (char *)walk->data);
		walk = walk->next;
		k++;
	}
	if (walk != NULL)
		printf("...(list still going after %d nodes)\n", k);
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
