#include "ft_list.h"
#include <stdio.h>
#include <string.h>

/* The comparator handed to the function: libc strcmp, which a test is free to
 * use. The fixture never prints what it returns, only what the function did
 * with it. */
static int	cmp_str(void *a, void *b)
{
	return (strcmp((char *)a, (char *)b));
}

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column. The found node is rendered by its data
 * cast as (char *), exactly as the original test reads it; a NULL result (no
 * node matched) is rendered as the text "NULL". Cases are ordered
 * trivial -> hardest, so the first failing row is the most fundamental fix. */
static void	test(char *label, t_list *begin, void *data_ref, int (*cmp)())
{
	t_list	*r;

	r = ft_list_find(begin, data_ref, cmp);
	if (r == NULL)
		printf("%s\tNULL\n", label);
	else
		printf("%s\t%s\n", label, (char *)r->data);
}

/* When two nodes both match, the contract is to return the FIRST one. This
 * renders "first" only when the returned pointer is the earlier node, "other"
 * for a later matching node, or "NULL" if nothing was returned at all. */
static void	test_first(char *label, t_list *begin, void *data_ref,
		int (*cmp)(), t_list *expect)
{
	t_list	*r;

	r = ft_list_find(begin, data_ref, cmp);
	if (r == NULL)
		printf("%s\tNULL\n", label);
	else if (r == expect)
		printf("%s\tfirst\n", label);
	else
		printf("%s\tother\n", label);
}

int	main(void)
{
	t_list	d;
	t_list	c;
	t_list	b;
	t_list	a;
	t_list	dup1;
	t_list	dup0;

	d.data = "d";
	d.next = NULL;
	c.data = "c";
	c.next = &d;
	b.data = "b";
	b.next = &c;
	a.data = "a";
	a.next = &b;
	test("find head", &a, "a", &cmp_str);
	test("find middle", &a, "c", &cmp_str);
	test("find tail", &a, "d", &cmp_str);
	test("not found", &a, "zzz", &cmp_str);
	test("empty list", NULL, "a", &cmp_str);
	dup1.data = "dup";
	dup1.next = NULL;
	dup0.data = "dup";
	dup0.next = &dup1;
	test_first("duplicate returns earliest", &dup0, "dup", &cmp_str, &dup0);
	return (0);
}
