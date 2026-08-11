/* Memory-safety probe for ft_list_find — run under AddressSanitizer.
 * ft_list_find walks a list comparing each element's data against data_ref with
 * the caller's cmp, and stops at the first match. The two things a walk can get
 * wrong are both invisible to output diffing when the answer happens to be
 * right: stepping PAST the terminating NULL, and reading the data pointer of a
 * node it has already gone past.
 * Every node below is its own heap block and every data is a heap block of
 * EXACTLY the bytes it holds, so a read one step beyond either lands in a
 * redzone rather than on a live neighbour. The searched-for value is absent in
 * one case on purpose: that is the run which walks the whole list and so is the
 * one that steps off the end if the stop condition is wrong.
 * This is a test input, not an implementation. */
#include "ft_list.h"
#include <stdlib.h>
#include <string.h>

static int	cmp_str(char *a, char *b)
{
	return (strcmp(a, b));
}

static t_list	*node(const char *s)
{
	t_list	*n;
	size_t	len;

	n = malloc(sizeof(t_list));
	len = strlen(s);
	n->data = malloc(len + 1);
	memcpy(n->data, s, len + 1);
	n->next = NULL;
	return (n);
}

static void	free_list(t_list *b)
{
	t_list	*tmp;

	while (b != NULL)
	{
		tmp = b;
		b = b->next;
		free(tmp->data);
		free(tmp);
	}
}

int	main(void)
{
	t_list	*a;
	char	*want;

	a = node("one");
	a->next = node("two");
	a->next->next = node("three");
	want = malloc(4);
	memcpy(want, "two", 4);
	ft_list_find(a, want, (int (*)())cmp_str);
	free(want);
	/* Absent on purpose: this walk reaches the end of the list. */
	want = malloc(5);
	memcpy(want, "nope", 5);
	ft_list_find(a, want, (int (*)())cmp_str);
	free(want);
	free_list(a);
	/* An empty list must be answered without dereferencing anything. */
	want = malloc(2);
	memcpy(want, "x", 2);
	ft_list_find(NULL, want, (int (*)())cmp_str);
	free(want);
	return (0);
}
