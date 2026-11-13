#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "libft.h"

/* ft_lstdelone's basic table. Its box (Libft, p.15): "Takes a node as
 * parameter and frees its content using the function 'del'. Free the node
 * itself but does NOT free the next node."
 *
 * Every node is the test's own and holds a content of its own from
 * malloc(3): node a holds A, node b holds B, and so on. Only the node handed
 * over comes from malloc(3), since the function frees it; its neighbours a
 * and c are static, so a neighbour freed by mistake is a free(3) of a block
 * malloc(3) never made, caught inside the call, on the case that did it, and
 * the rows that follow only ever read memory that is still the test's. del is the test's: it notes
 * the content it was called with, by name, and frees it, once. A row about
 * another node reads its two fields without following them. Whether the node
 * handed over was freed is the valgrind layer's question (basic here): a
 * correct function leaves no block of its node behind, and the test frees
 * every content the call must not touch, before the newline of the case's
 * last row: a crash in free() then marks that row, not the next case's. */
void	ft_lstdelone(t_list *lst, void (*del)(void *));

#define NODES 3

static t_list	g_a;
static t_list	g_c;
static t_list	*g_node[NODES];
static char		*g_content[NODES];
static int		g_deleted[NODES];
static int		g_made;
static char		g_log[64];
static int		g_logged;

/* The test's del: notes which content it was handed (a ? for a pointer that
 * is none of this case's contents) and frees a content the first time only,
 * so a second call shows in the table instead of crashing. */
static void	del(void *content)
{
	int	i;

	i = 0;
	while (i < g_made && content != g_content[i])
		i++;
	if (g_logged + 2 < (int) sizeof(g_log))
	{
		if (g_logged > 0)
			g_log[g_logged++] = ' ';
		g_log[g_logged++] = (i < g_made) ? (char)('A' + i) : '?';
	}
	if (i < g_made && !g_deleted[i])
	{
		g_deleted[i] = 1;
		free(content);
	}
}

/* The case's nodes a .. of n, already placed in g_node by the caller: each
 * given its content and linked in that order. The slots past n are emptied,
 * so nothing of an earlier case is ever matched. */
static void	make(int n)
{
	int	i;

	i = 0;
	while (i < NODES)
	{
		g_content[i] = NULL;
		g_deleted[i] = 0;
		if (i >= n)
			g_node[i] = NULL;
		i++;
	}
	i = 0;
	while (i < n)
	{
		g_content[i] = malloc(1);
		if (g_node[i] == NULL || g_content[i] == NULL)
			exit(1);
		g_content[i][0] = (char)('A' + i);
		g_node[i]->content = g_content[i];
		g_node[i]->next = (i + 1 < n) ? g_node[i + 1] : NULL;
		i++;
	}
	g_made = n;
	g_logged = 0;
	g_log[0] = '\0';
}

/* The row of del's calls, in the order they came. */
static void	calls(const char *label)
{
	g_log[g_logged] = '\0';
	printf("%s: del called with\t%s\n", label,
		g_logged == 0 ? "(no call)" : g_log);
}

/* The row of node k's two fields, read and never followed. The caller ends
 * the row. */
static void	fields(const char *label, int k, t_list *next)
{
	printf("%s: %c\tcontent %s, next %s", label, 'a' + k,
		g_node[k]->content == g_content[k] ? "unchanged" : "changed",
		g_node[k]->next == next ? "unchanged" : "changed");
}

int	main(void)
{
	t_list	*b;

	g_node[0] = &g_a;
	g_node[1] = malloc(sizeof(t_list));
	g_node[2] = &g_c;
	make(3);
	b = g_node[1];
	ft_lstdelone(b, &del);
	calls("delete b of [a b c]");
	fields("delete b of [a b c]", 0, b);
	printf("\n");
	fields("delete b of [a b c]", 2, NULL);
	free(g_content[0]);
	if (!g_deleted[2])
		free(g_content[2]);
	printf("\n");
	g_node[0] = malloc(sizeof(t_list));
	make(1);
	ft_lstdelone(g_node[0], &del);
	calls("delete a lone node a");
	return (0);
}
