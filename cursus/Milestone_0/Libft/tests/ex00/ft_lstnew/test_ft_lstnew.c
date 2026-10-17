#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "libft.h"

/* ft_lstnew's basic table. Its box (Libft, p.14): "Allocates memory (using
 * malloc(3)) and returns a new node. The 'content' member variable is
 * initialized with the given parameter 'content'. The variable 'next' is
 * initialized to NULL."
 *
 * Each row is "<call>: <what it looks at>\t<what it found>". When a call
 * returns NULL there is no node to look at, and each of that call's rows says
 * so instead of disappearing. A node comes from malloc(3), so the test hands
 * each one back to free(3), once, as any caller would: the valgrind layer,
 * basic here, reads those frees. A call's nodes are freed before its last
 * row's newline, so a crash in free() marks that row, not the next call's. */
t_list	*ft_lstnew(void *content);

#define MANY 5000

/* The two rows of one call: what content holds, and what next holds. The
 * second is left without its newline, which the caller prints once the node
 * is freed. */
static void	rows(const char *call, t_list *node, void *content)
{
	if (node == NULL)
	{
		printf("%s: content\t(NULL returned, no node)\n", call);
		printf("%s: next\t(NULL returned, no node)", call);
		return ;
	}
	if (node->content == content)
		printf("%s: content\tthe pointer passed\n", call);
	else
		printf("%s: content\tanother pointer\n", call);
	if (node->next == NULL)
		printf("%s: next\tNULL", call);
	else
		printf("%s: next\tnot NULL", call);
}

/* One call, its rows, and its node freed. */
static void	one(const char *call, void *content)
{
	t_list	*node;

	node = ft_lstnew(content);
	rows(call, node, content);
	free(node);
	printf("\n");
}

/* Two calls with the same content, both nodes alive at once: a caller who
 * keeps two nodes holds two of them. Freed once each, and once in all when
 * both calls returned the same one. */
static void	two(void)
{
	static int	x = 7;
	t_list		*a;
	t_list		*b;

	a = ft_lstnew(&x);
	b = ft_lstnew(&x);
	if (a == NULL || b == NULL)
		printf("two calls, same content: nodes\t(NULL returned)");
	else if (a == b)
		printf("two calls, same content: nodes\tthe same node twice");
	else
		printf("two calls, same content: nodes\ttwo nodes");
	free(a);
	if (b != a)
		free(b);
	printf("\n");
}

/* MANY calls, each with its own content, every node alive until the end:
 * how many came back holding the content they were given and a NULL next. */
static void	many(void)
{
	static int	tab[MANY];
	t_list		**node;
	int			right;
	int			i;

	node = calloc(MANY, sizeof(*node));
	if (node == NULL)
		exit(1);
	right = 0;
	i = 0;
	while (i < MANY)
	{
		node[i] = ft_lstnew(&tab[i]);
		if (node[i] != NULL && node[i]->content == &tab[i]
			&& node[i]->next == NULL)
			right++;
		i++;
	}
	printf("%d calls: content and next right\t%d of %d", MANY, right, MANY);
	i = 0;
	while (i < MANY)
		free(node[i++]);
	free(node);
	printf("\n");
}

int	main(void)
{
	static int	x = 42;
	static char	text[] = "forty-two";

	one("ft_lstnew(\"forty-two\")", text);
	one("ft_lstnew(&x)", &x);
	one("ft_lstnew(NULL)", NULL);
	two();
	many();
	return (0);
}
