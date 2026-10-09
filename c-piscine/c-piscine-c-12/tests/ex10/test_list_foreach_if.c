#include "ft_list.h"
#include <stdio.h>
#include <string.h>

void	ft_list_foreach_if(t_list *begin_list, void (*f)(void *),
			void *data_ref, int (*cmp)(void *, void *));

static void	print_str(void *data)
{
	printf("%s\n", (char *)data);
}

static void	add_100(void *data)
{
	*(int *)data += 100;
}

/* What cmp must be called with, as the subject writes it:
 * (*cmp)(list_ptr->data, data_ref). g_ref is the data_ref the current call
 * passed, and g_data the current list's data pointers; a call with anything
 * else -- the two swapped, say -- is noted, and the fixture's last row says
 * so. The comparison each cmp returns is the same either way round, so a
 * swapped call changes that row alone. */
static void	*g_ref;
static void	*g_data[8];
static int	g_n;
static int	g_swapped;

static void	note_call(void *a, void *b)
{
	int	i;
	int	known;

	known = 0;
	i = 0;
	while (i < g_n)
		if (g_data[i++] == a)
			known = 1;
	if (b != g_ref || !known)
		g_swapped = 1;
}

/* The comparators handed to the function: libc strcmp, which a test is free
 * to use, and an int compare. The fixture never prints what they return, only
 * what the function did with it. */
static int	cmp_str(void *a, void *b)
{
	note_call(a, b);
	return (strcmp((char *)a, (char *)b));
}

static int	cmp_int(void *a, void *b)
{
	note_call(a, b);
	return (*(int *)a - *(int *)b);
}

/* Registers the list of `n` nodes starting at `l` as the current call's. */
static void	expect(t_list *l, void *ref)
{
	g_n = 0;
	while (l != NULL && g_n < 8)
	{
		g_data[g_n++] = l->data;
		l = l->next;
	}
	g_ref = ref;
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
	char	match[6];

	strcpy(match, "match");
	d.data = "match";
	d.next = NULL;
	c.data = "match";
	c.next = &d;
	b.data = "x";
	b.next = &c;
	a.data = "match";
	a.next = &b;
	printf("--- str (head, middle, tail match) ---\n");
	expect(&a, match);
	ft_list_foreach_if(&a, &print_str, match, &cmp_str);
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
	expect(&m0, &ref);
	ft_list_foreach_if(&m0, &add_100, &ref, &cmp_int);
	printf("%d %d %d %d %d\n", nums[0], nums[1], nums[2], nums[3], nums[4]);
	printf("--- nomatch (ref 5 vs 1,2,3) ---\n");
	nums[0] = 1;
	nums[1] = 2;
	nums[2] = 3;
	m0.next = &m1;
	m1.next = &m2;
	m2.next = NULL;
	expect(&m0, &ref);
	ft_list_foreach_if(&m0, &add_100, &ref, &cmp_int);
	printf("%d %d %d\n", nums[0], nums[1], nums[2]);
	printf("--- empty ---\n");
	expect(NULL, match);
	ft_list_foreach_if(NULL, &print_str, match, &cmp_str);
	printf("(no crash)\n");
	if (g_swapped)
		printf("cmp called as (*cmp)(list_ptr->data, data_ref)\tno, swapped\n");
	else
		printf("cmp called as (*cmp)(list_ptr->data, data_ref)\tyes\n");
	return (0);
}
