#include "ft_list.h"
#include <stdio.h>

static void	print_str(void *data)
{
	printf("%s\n", (char *)data);
}

static void	add_one(void *data)
{
	*(int *)data += 1;
}

int	main(void)
{
	t_list	c;
	t_list	b;
	t_list	a;
	int		nums[3];
	t_list	n2;
	t_list	n1;
	t_list	n0;

	c.data = "c";
	c.next = NULL;
	b.data = "b";
	b.next = &c;
	a.data = "a";
	a.next = &b;
	printf("--- order ---\n");
	ft_list_foreach(&a, &print_str);
	printf("--- single ---\n");
	a.next = NULL;
	ft_list_foreach(&a, &print_str);
	printf("--- empty ---\n");
	ft_list_foreach(NULL, &print_str);
	printf("(no crash)\n");
	printf("--- mutate ---\n");
	nums[0] = 1;
	nums[1] = 2;
	nums[2] = 3;
	n2.data = &nums[2];
	n2.next = NULL;
	n1.data = &nums[1];
	n1.next = &n2;
	n0.data = &nums[0];
	n0.next = &n1;
	ft_list_foreach(&n0, &add_one);
	printf("%d %d %d\n", nums[0], nums[1], nums[2]);
	return (0);
}
