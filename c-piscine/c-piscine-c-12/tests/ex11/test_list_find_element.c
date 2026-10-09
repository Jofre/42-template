#include "ft_list.h"
#include <stdio.h>
#include <string.h>

t_list	*ft_list_find(t_list *begin_list, void *data_ref, int (*cmp)());

/* THE READING THIS HARNESS TAKES, AT STRICT (ex11_element_output). The subject
 * says ft_list_find "returns the address of the first element's data", and its
 * prototype returns a t_list *: the element, its data pointer, or the address
 * of its data field could each be what is meant. The basic table
 * (test_list_find.c) accepts all three, since they agree on which element is
 * found. This one takes the prototype's reading -- a t_list * points at an
 * element -- and says, for each case that finds something, which of the three
 * came back. */

static int	cmp_str(void *a, void *b)
{
	return (strcmp((char *)a, (char *)b));
}

/* What r is, relative to the element the case finds: the element itself, its
 * data pointer, the address of its data field, or none of those. Pointers are
 * compared, never followed. */
static void	test(char *label, t_list *begin, char *data_ref, t_list *want)
{
	t_list	*r;

	r = ft_list_find(begin, data_ref, &cmp_str);
	if (r == want)
		printf("%s\tthe element\n", label);
	else if (r == NULL)
		printf("%s\tNULL\n", label);
	else if ((void *)r == want->data)
		printf("%s\tthe element's data pointer\n", label);
	else if ((void *)r == (void *)&want->data)
		printf("%s\tthe address of the element's data field\n", label);
	else
		printf("%s\tsome other pointer\n", label);
}

int	main(void)
{
	t_list	n[3];
	char	s[3][2];
	char	ref[2];

	strcpy(s[0], "a");
	strcpy(s[1], "b");
	strcpy(s[2], "c");
	n[0].data = s[0];
	n[0].next = &n[1];
	n[1].data = s[1];
	n[1].next = &n[2];
	n[2].data = s[2];
	n[2].next = NULL;
	test("find head: what is returned", &n[0], strcpy(ref, "a"), &n[0]);
	test("find middle: what is returned", &n[0], strcpy(ref, "b"), &n[1]);
	test("find tail: what is returned", &n[0], strcpy(ref, "c"), &n[2]);
	return (0);
}
