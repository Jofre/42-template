#include "ft_list.h"
#include <stdio.h>
#include <string.h>

t_list	*ft_list_find(t_list *begin_list, void *data_ref, int (*cmp)());

/* WHAT THIS TABLE ASKS, AND WHAT IT LEAVES TO THE STRICT LEVEL. The subject
 * says ft_list_find "returns the address of the first element's data", and
 * its prototype returns a t_list *. Those two can be read three ways: the
 * element itself, the element's data pointer, or the address of the element's
 * data field. Every reading agrees on WHICH element is meant -- the first one
 * cmp matches -- and on NULL when none does; that is all this table asks, at
 * basic. Which of the three is returned is a reading, and is checked at strict
 * alone (test_list_find_element.c, ex11_element_output). */

/* What cmp must be called with, as the subject writes it:
 * (*cmp)(list_ptr->data, data_ref). g_ref is the data_ref the current call
 * passed; a call with anything else -- the two swapped, say -- is noted, and
 * the table's last row says so. strcmp answers the same either way round, so
 * a swapped call changes that row alone. */
static void	*g_ref;
static int	g_swapped;

/* The nodes this fixture built, so that a returned pointer is only ever
 * followed when it is one of them. A pointer that is not is compared, never
 * dereferenced: comparing pointers for equality is defined whatever they point
 * to; following one is not. */
static t_list	*g_nodes[8];
static int		g_count;

static void	known(t_list *node)
{
	g_nodes[g_count] = node;
	g_count++;
}

/* The node a returned pointer designates under any of the three readings --
 * the node, its data, or the address of its data field -- or NULL when it
 * designates none of them. */
static t_list	*designated(void *r)
{
	int	i;

	i = 0;
	while (i < g_count)
	{
		if (r == (void *)g_nodes[i] || r == g_nodes[i]->data
			|| r == (void *)&g_nodes[i]->data)
			return (g_nodes[i]);
		i++;
	}
	return (NULL);
}

static int	cmp_str(void *a, void *b)
{
	int	i;
	int	is_data;

	is_data = 0;
	i = 0;
	while (i < g_count)
		if (g_nodes[i++]->data == a)
			is_data = 1;
	if (b != g_ref || !is_data)
		g_swapped = 1;
	return (strcmp((char *)a, (char *)b));
}

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each case in its own column: the string held by the element the result
 * designates, "NULL" for a NULL result, or "no element of the list, nor its
 * data" for any other pointer. Cases are ordered trivial -> hardest, so the
 * first failing row is the most fundamental fix. */
static void	test(char *label, t_list *begin, char *data_ref)
{
	t_list	*r;
	t_list	*node;

	g_ref = data_ref;
	r = ft_list_find(begin, data_ref, &cmp_str);
	node = designated(r);
	if (r == NULL)
		printf("%s\tNULL\n", label);
	else if (node != NULL)
		printf("%s\t%s\n", label, (char *)node->data);
	else
		printf("%s\tno element of the list, nor its data\n", label);
}

/* When two nodes both match, the result designates the FIRST one under every
 * reading. This renders "first" when it designates the earlier node, "other"
 * for a later one, "NULL" for nothing, and "no element of the list, nor its
 * data" for any other pointer. */
static void	test_first(char *label, t_list *begin, char *data_ref,
		t_list *expect)
{
	t_list	*r;
	t_list	*node;

	g_ref = data_ref;
	r = ft_list_find(begin, data_ref, &cmp_str);
	node = designated(r);
	if (r == NULL)
		printf("%s\tNULL\n", label);
	else if (node == expect)
		printf("%s\tfirst\n", label);
	else if (node != NULL)
		printf("%s\tother\n", label);
	else
		printf("%s\tno element of the list, nor its data\n", label);
}

/* 5000 nodes, node i holding the string "n<i>", and data_ref the last one's
 * string: the match is found only at the end of the list, which is checked by
 * construction and shown as ONE row -- the 5000th node (under any of the three
 * readings: the node, its data, or the address of its data field), an earlier
 * one, NULL, or no node of the list. The subject bounds no length, so every
 * reading agrees on this case, and it is past every capacity a function is
 * usually given room for (16, 64, 256, 1024, 4096): one that walks through
 * room of its own fixed size gets it wrong here, or dies (finding 041). Its
 * own comparator, which notes nothing: the row about cmp's arguments is the
 * six-node table's. */
#define LONG 5000

static int	cmp_long(void *a, void *b)
{
	return (strcmp((char *)a, (char *)b));
}

static void	test_long(void)
{
	static t_list	nodes[LONG];
	static char		names[LONG][8];
	char			ref[8];
	t_list			*r;
	int				k;

	k = 0;
	while (k < LONG)
	{
		snprintf(names[k], sizeof(names[k]), "n%d", k);
		nodes[k].data = names[k];
		nodes[k].next = (k + 1 < LONG) ? &nodes[k + 1] : NULL;
		k++;
	}
	snprintf(ref, sizeof(ref), "n%d", LONG - 1);
	r = ft_list_find(&nodes[0], ref, &cmp_long);
	k = 0;
	while (k < LONG && r != (void *)&nodes[k] && r != nodes[k].data
		&& r != (void *)&nodes[k].data)
		k++;
	if (r == NULL)
		printf("5000-node list, the match its last node\tNULL\n");
	else if (k == LONG - 1)
		printf("5000-node list, the match its last node\tthe 5000th\n");
	else if (k < LONG)
		printf("5000-node list, the match its last node\tnode %d\n", k + 1);
	else
		printf("5000-node list, the match its last node\tno element of the list, nor its data\n");
}

int	main(void)
{
	t_list	n[6];
	char	s[6][4];
	char	ref[4];

	strcpy(s[0], "a");
	strcpy(s[1], "b");
	strcpy(s[2], "c");
	strcpy(s[3], "d");
	strcpy(s[4], "dup");
	strcpy(s[5], "dup");
	n[0].data = s[0];
	n[0].next = &n[1];
	n[1].data = s[1];
	n[1].next = &n[2];
	n[2].data = s[2];
	n[2].next = &n[3];
	n[3].data = s[3];
	n[3].next = NULL;
	n[4].data = s[4];
	n[4].next = &n[5];
	n[5].data = s[5];
	n[5].next = NULL;
	g_count = 0;
	while (g_count < 6)
		known(&n[g_count]);
	test("find head", &n[0], strcpy(ref, "a"));
	test("find middle", &n[0], strcpy(ref, "c"));
	test("find tail", &n[0], strcpy(ref, "d"));
	test("not found", &n[0], strcpy(ref, "zzz"));
	test("empty list", NULL, strcpy(ref, "a"));
	test_first("duplicate returns earliest", &n[4], strcpy(ref, "dup"), &n[4]);
	test_long();
	if (g_swapped)
		printf("cmp called as (*cmp)(list_ptr->data, data_ref)\tno, swapped\n");
	else
		printf("cmp called as (*cmp)(list_ptr->data, data_ref)\tyes\n");
	return (0);
}
