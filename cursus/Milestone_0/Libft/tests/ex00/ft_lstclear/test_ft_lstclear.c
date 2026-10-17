#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "libft.h"

/* ft_lstclear's basic table. Its box (Libft, p.16): "Deletes and frees the
 * given node and all its successors, using the function 'del' and free(3).
 * Finally, set the pointer to the list to NULL." A pointer to the list that
 * holds NULL is the empty list.
 *
 * Every node is the test's own, each from its own malloc(3) since the
 * function frees them, and each holds a content of its own from malloc(3)
 * too: node a holds A, node b holds B, and so on. del is the test's: it notes
 * the content it was called with, by name, and frees it, once. The box says
 * nothing of the order of the calls, so a row lists del's calls sorted by
 * name: what it checks is that each content was handed over, once. Whether
 * the nodes were freed is the valgrind layer's question (basic here): a
 * correct function leaves no block of theirs behind, and the test frees every
 * node and content the call must not touch, before the newline of the case's
 * last row: a crash in free() then marks that row, not the next case's. A
 * pointer left behind is printed as NULL or not, never followed. */
void	ft_lstclear(t_list **lst, void (*del)(void *));

#define NODES 4
#define MANY 5000

static t_list	*g_node[MANY];
static char		*g_content[MANY];
static int		g_deleted[MANY];
static int		g_calls[MANY + 1];
static int		g_made;

/* The test's del: counts each content it is handed (the last slot counts
 * pointers that are none of the contents) and frees a content the first time
 * only, so a second call shows in the table instead of crashing. */
static void	del(void *content)
{
	int	i;

	i = 0;
	while (i < g_made && content != g_content[i])
		i++;
	g_calls[i == g_made ? MANY : i]++;
	if (i < g_made && !g_deleted[i])
	{
		g_deleted[i] = 1;
		free(content);
	}
}

/* n nodes, each with its content, linked in order; the first one. */
static t_list	*make(int n)
{
	int	i;

	i = 0;
	while (i < n)
	{
		g_node[i] = malloc(sizeof(t_list));
		g_content[i] = malloc(1);
		if (g_node[i] == NULL || g_content[i] == NULL)
			exit(1);
		g_content[i][0] = (char)('A' + i % 26);
		g_node[i]->content = g_content[i];
		g_node[i]->next = NULL;
		g_deleted[i] = 0;
		g_calls[i] = 0;
		i++;
	}
	g_calls[MANY] = 0;
	g_made = n;
	i = 0;
	while (i + 1 < n)
	{
		g_node[i]->next = g_node[i + 1];
		i++;
	}
	return (n > 0 ? g_node[0] : NULL);
}

/* The row of del's calls on a small list: each content's name once per call,
 * sorted, a ? per call with a pointer that is no content. */
static void	calls(const char *label)
{
	int	i;
	int	k;
	int	any;

	printf("%s: del called with\t", label);
	any = 0;
	i = (g_made == 0) ? MANY : 0;
	while (i <= MANY)
	{
		k = 0;
		while (k < g_calls[i])
		{
			printf("%s%c", any ? " " : "", i == MANY ? '?' : 'A' + i);
			any = 1;
			k++;
		}
		i = (i + 1 == g_made) ? MANY : i + 1;
	}
	printf("%s\n", any ? "" : "(no call)");
}

/* What a pointer the call left behind holds: NULL, or not. The caller ends
 * the row. */
static void	after(const char *label, const char *what, t_list *p)
{
	printf("%s: %s afterwards\t%s", label, what, p == NULL ? "NULL" : "not NULL");
}

/* MANY nodes cleared: whether del was handed each content once. */
static void	many(void)
{
	t_list	*lst;
	int		i;
	int		never;
	int		more;

	lst = make(MANY);
	ft_lstclear(&lst, &del);
	never = 0;
	more = 0;
	i = 0;
	while (i < MANY)
	{
		never += (g_calls[i] == 0);
		more += (g_calls[i] > 1);
		i++;
	}
	printf("%d nodes: del called with\t", MANY);
	if (never == 0 && more == 0 && g_calls[MANY] == 0)
		printf("each of the %d contents, once\n", MANY);
	else
		printf("%d contents never, %d more than once, %d other pointers\n",
			never, more, g_calls[MANY]);
	after("5000 nodes", "*lst", lst);
	i = 0;
	while (i < MANY)
	{
		if (!g_deleted[i])
			free(g_content[i]);
		i++;
	}
	printf("\n");
}

int	main(void)
{
	t_list	*lst;
	t_list	*a;

	lst = make(0);
	ft_lstclear(&lst, &del);
	calls("*lst NULL");
	after("*lst NULL", "*lst", lst);
	printf("\n");
	lst = make(1);
	ft_lstclear(&lst, &del);
	calls("[a]");
	after("[a]", "*lst", lst);
	printf("\n");
	lst = make(3);
	ft_lstclear(&lst, &del);
	calls("[a b c]");
	after("[a b c]", "*lst", lst);
	printf("\n");
	a = make(3);
	ft_lstclear(&a->next, &del);
	calls("from b of [a b c]");
	after("from b of [a b c]", "a->next", a->next);
	printf("\n");
	printf("from b of [a b c]: a's content afterwards\t%s",
		a->content == g_content[0] ? "unchanged" : "changed");
	if (!g_deleted[0])
		free(g_content[0]);
	free(a);
	printf("\n");
	many();
	return (0);
}
