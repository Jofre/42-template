#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "libft.h"

/* ft_lstmap's basic table. Its box (Libft, p.16): "Iterates through the list
 * 'lst', applies the function 'f' to each node's content, and creates a new
 * list resulting of the successive applications of the function 'f'. The
 * 'del' function is used to delete the content of a node if needed." It
 * returns "The new list." A NULL first node is the empty list.
 *
 * The list handed over is the test's own: node k holds a pointer to an int of
 * the test's. f is the test's too: it notes which content it was handed, in
 * the order the calls came, and returns a new int from malloc(3), three times
 * the one it was handed, less one -- so a node of the new list shows which
 * call made its content. del notes its calls and frees a content f made, once.
 * Every call here succeeds, so del has nothing to delete. A row prints values
 * and names, never addresses; a walk stops after one node more than the list
 * handed over, so a list that loops back on itself still prints.
 *
 * Afterwards the test frees the new list's nodes, each once, and every
 * content f made that del did not free: what a caller who owns the new list
 * frees. The valgrind layer (basic here) reads what is left. */
t_list	*ft_lstmap(t_list *lst, void *(*f)(void *), void (*del)(void *));

#define MANY 5000
#define MADE (2 * MANY + 8)

static t_list	g_node[MANY];
static int		g_value[MANY];
static int		g_n;
static int		g_fcall[MANY + 1];
static int		g_nf;
static int		*g_made[MADE];
static int		g_freed[MADE];
static int		g_nmade;
static int		g_ndel;

/* Which of the test's contents p is, or g_n when it is none of them. */
static int	original(const void *p)
{
	int	i;

	i = 0;
	while (i < g_n && p != &g_value[i])
		i++;
	return (i);
}

/* Which of f's results p is, or -1 when it is none of them. */
static int	made(const void *p)
{
	int	i;

	i = 0;
	while (i < g_nmade && p != g_made[i])
		i++;
	return (i < g_nmade ? i : -1);
}

/* The test's f: notes the content it was handed and returns a new int, three
 * times that content's int less one (0 for a pointer that is none of the
 * contents). */
static void	*f(void *content)
{
	int	i;
	int	*r;

	i = original(content);
	if (g_nf <= MANY)
		g_fcall[g_nf] = i;
	g_nf++;
	r = malloc(sizeof(int));
	if (r == NULL)
		exit(1);
	*r = (i < g_n) ? g_value[i] * 3 - 1 : 0;
	if (g_nmade < MADE)
	{
		g_freed[g_nmade] = 0;
		g_made[g_nmade++] = r;
	}
	return (r);
}

/* The test's del: counts its calls, and frees a content f made, once. */
static void	del(void *content)
{
	int	i;

	g_ndel++;
	i = made(content);
	if (i >= 0 && !g_freed[i])
	{
		g_freed[i] = 1;
		free(content);
	}
}

/* The list handed over: n nodes in order, node k's content pointing to an int
 * holding v0 + k; NULL when n is 0. */
static t_list	*make(int n, int v0)
{
	int	i;

	i = 0;
	while (i < n)
	{
		g_value[i] = v0 + i;
		g_node[i].content = &g_value[i];
		g_node[i].next = (i + 1 < n) ? &g_node[i + 1] : NULL;
		i++;
	}
	g_n = n;
	g_nf = 0;
	g_nmade = 0;
	g_ndel = 0;
	return (n > 0 ? &g_node[0] : NULL);
}

/* Whether node p is one of the test's own nodes. */
static int	ours(const t_list *p)
{
	int	i;

	i = 0;
	while (i < g_n && p != &g_node[i])
		i++;
	return (i < g_n);
}

/* The new list's nodes, read one more than the list handed over had, and
 * freed once each -- never a node of the test's own. Called before the
 * newline of the case's last row, so a crash in free() marks that row, not
 * the next case's. */
static void	release(t_list *res)
{
	t_list	**seen;
	int		k;
	int		j;

	seen = calloc((size_t)g_n + 2, sizeof(*seen));
	if (seen == NULL)
		exit(1);
	k = 0;
	while (res != NULL && k <= g_n && !ours(res))
	{
		j = 0;
		while (j < k && seen[j] != res)
			j++;
		if (j < k)
			break ;
		seen[k++] = res;
		res = res->next;
	}
	while (k-- > 0)
		free(seen[k]);
	free(seen);
	k = 0;
	while (k < g_nmade)
	{
		if (!g_freed[k])
			free(g_made[k]);
		k++;
	}
}

/* The row of f's calls on a small list: the int behind each content it was
 * handed, in the order the calls came. */
static void	fcalls(const char *label)
{
	int	k;

	printf("%s: f called with\t", label);
	if (g_nf == 0)
		printf("(no call)");
	k = 0;
	while (k < g_nf && k <= MANY)
	{
		printf("%s", k == 0 ? "" : " ");
		if (g_fcall[k] < g_n)
			printf("%d", g_value[g_fcall[k]]);
		else
			printf("(a pointer that is no content of the list)");
		k++;
	}
	printf("\n");
}

/* The rows of the new list from res: its contents' ints, and how many of
 * its nodes are the test's own. A content del has freed is named, never
 * read, as len_ft_lstmap.c does. */
static void	result(const char *label, t_list *res)
{
	int	k;
	int	m;
	int	shared;

	printf("%s: new list\t", label);
	if (res == NULL)
		printf("NULL");
	shared = 0;
	k = 0;
	while (res != NULL && k <= g_n)
	{
		printf("%s", k == 0 ? "" : " ");
		if (ours(res))
			shared++;
		m = made(res->content);
		if (m >= 0 && g_freed[m])
			printf("(a content del freed)");
		else if (m >= 0)
			printf("%d", *g_made[m]);
		else if (original(res->content) < g_n)
			printf("(a content of the list handed over)");
		else
			printf("(a content f did not make)");
		res = res->next;
		k++;
	}
	if (res != NULL)
		printf(" ...(still going after %d nodes)", g_n + 1);
	printf("\n");
	printf("%s: nodes of the list handed over in it\t%d\n", label, shared);
}

/* The row of the list handed over, afterwards: each node by where it is,
 * with its content's int, reading one node more than it had. */
static void	before(const char *label, t_list *lst)
{
	int	k;

	printf("%s: list handed over, afterwards\t", label);
	k = 0;
	while (lst != NULL && k <= g_n && lst == &g_node[k])
	{
		if (lst->content != &g_value[k])
			break ;
		printf("%s%d", k == 0 ? "" : " ", g_value[k]);
		lst = lst->next;
		k++;
	}
	if (k < g_n || lst != NULL)
		printf("%s(changed at node %d)", k == 0 ? "" : " ", k + 1);
	printf("\n");
}

static void	small(const char *label, int n, int v0)
{
	t_list	*lst;
	t_list	*res;

	lst = make(n, v0);
	res = ft_lstmap(lst, &f, &del);
	fcalls(label);
	result(label, res);
	before(label, lst);
	printf("%s: del called\t%d time(s)", label, g_ndel);
	release(res);
	printf("\n");
}

/* MANY nodes: whether the new list holds MANY nodes, node k holding f's
 * result for node k's content, and none of the test's own. */
static void	many(void)
{
	t_list	*res;
	t_list	*p;
	int		k;

	res = ft_lstmap(make(MANY, -2500), &f, &del);
	p = res;
	k = 0;
	while (p != NULL && k < MANY && !ours(p) && k < g_nmade
		&& p->content == g_made[k] && g_fcall[k] == k)
	{
		p = p->next;
		k++;
	}
	printf("%d nodes: new list\t", MANY);
	if (k == MANY && p == NULL)
		printf("%d new nodes, node k holding f's result for node k", MANY);
	else if (p == NULL)
		printf("ends after %d right nodes", k);
	else
		printf("node %d is not f's result for node %d", k + 1, k + 1);
	release(res);
	printf("\n");
}

int	main(void)
{
	t_list	*res;

	make(0, 0);
	res = ft_lstmap(NULL, &f, &del);
	printf("NULL (the empty list): result\t%s\n", res == NULL ? "NULL" : "not NULL");
	printf("NULL (the empty list): calls\tf %d, del %d\n", g_nf, g_ndel);
	small("[1 2 3]", 3, 1);
	small("[7]", 1, 7);
	many();
	return (0);
}
