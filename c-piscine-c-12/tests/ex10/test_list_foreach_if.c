#include "ft_list.h"
#include <stdio.h>

static void	print_str(void *data)
{
	printf("%s\n", (char *)data);
}

static void	add_100(void *data)
{
	*(int *)data += 100;
}

static int	cmp_str(void *a, void *b)
{
	char	*s1;
	char	*s2;

	s1 = (char *)a;
	s2 = (char *)b;
	while (*s1 && *s1 == *s2)
	{
		s1++;
		s2++;
	}
	return ((unsigned char)*s1 - (unsigned char)*s2);
}

static int	cmp_int(void *a, void *b)
{
	return (*(int *)a - *(int *)b);
}

int	main(void)
{
	t_list	d;
	t_list	c;
	t_list	b;
	t_list	a;
	int		nums[5];
	int		ref;
	t_list	m4;
	t_list	m3;
	t_list	m2;
	t_list	m1;
	t_list	m0;

	d.data = "match";
	d.next = NULL;
	c.data = "match";
	c.next = &d;
	b.data = "x";
	b.next = &c;
	a.data = "match";
	a.next = &b;
	printf("--- str (head, middle, tail match) ---\n");
	ft_list_foreach_if(&a, &print_str, "match", &cmp_str);
	printf("--- mutate (ref 5) ---\n");
	nums[0] = 5;
	nums[1] = 7;
	nums[2] = 5;
	nums[3] = 9;
	nums[4] = 5;
	ref = 5;
	m4.data = &nums[4];
	m4.next = NULL;
	m3.data = &nums[3];
	m3.next = &m4;
	m2.data = &nums[2];
	m2.next = &m3;
	m1.data = &nums[1];
	m1.next = &m2;
	m0.data = &nums[0];
	m0.next = &m1;
	ft_list_foreach_if(&m0, &add_100, &ref, &cmp_int);
	printf("%d %d %d %d %d\n", nums[0], nums[1], nums[2], nums[3], nums[4]);
	printf("--- nomatch (ref 5 vs 1,2,3) ---\n");
	nums[0] = 1;
	nums[1] = 2;
	nums[2] = 3;
	m0.next = &m1;
	m1.next = &m2;
	m2.next = NULL;
	ft_list_foreach_if(&m0, &add_100, &ref, &cmp_int);
	printf("%d %d %d\n", nums[0], nums[1], nums[2]);
	printf("--- empty ---\n");
	ft_list_foreach_if(NULL, &print_str, "match", &cmp_str);
	printf("(no crash)\n");
	return (0);
}
