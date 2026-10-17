#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "libft.h"

/* ft_lstiter's basic table. Its box (Libft, p.16): "Iterates through the
 * list 'lst' and applies the function 'f' to the content of each node." A
 * NULL first node is the empty list.
 *
 * Every list is the test's own: node a holds the int A, node b the int B, and
 * so on, each content a pointer to an int of the test's. f is the test's too:
 * it notes which content it was handed, by name and in the order the calls
 * came, and adds 10 to the int a content points to. A row prints names and
 * values, never addresses, and a list afterwards node by node, by where each
 * node is. */
void	ft_lstiter(t_list *lst, void (*f)(void *));

#define SMALL 3
#define MANY 5000

static t_list	g_node[MANY];
static int		g_value[MANY];
static int		g_order[MANY + 1];
static int		g_ncalls;
static int		g_made;

/* The test's f: notes the content's index (g_made for a pointer that is none
 * of the contents) and adds 10 to the int behind a content of the test's. */
static void	f(void *content)
{
	int	i;

	i = 0;
	while (i < g_made && content != &g_value[i])
		i++;
	if (g_ncalls <= MANY)
		g_order[g_ncalls] = i;
	g_ncalls++;
	if (i < g_made)
		g_value[i] += 10;
}

/* n nodes, node i holding a pointer to g_value[i], which starts at v + i,
 * linked in order; the first one, NULL when n is 0. */
static t_list	*make(int n, int v)
{
	int	i;

	i = 0;
	while (i < n)
	{
		g_value[i] = v + i;
		g_node[i].content = &g_value[i];
		g_node[i].next = (i + 1 < n) ? &g_node[i + 1] : NULL;
		i++;
	}
	g_made = n;
	g_ncalls = 0;
	return (n > 0 ? &g_node[0] : NULL);
}

/* The row of f's calls on a small list, by name, in the order they came. */
static void	calls(const char *label)
{
	int	k;

	printf("%s: f called with\t", label);
	if (g_ncalls == 0)
		printf("(no call)");
	k = 0;
	while (k < g_ncalls && k <= MANY)
	{
		printf("%s", k == 0 ? "" : " ");
		if (g_order[k] < g_made)
			printf("%c", 'A' + g_order[k]);
		else
			printf("?");
		k++;
	}
	printf("\n");
}

/* The row of the list from lst afterwards: each node by where it is, with
 * the int its content points to, reading one node more than the list had. */
static void	show(const char *label, t_list *lst)
{
	int	k;
	int	i;

	printf("%s: afterwards\t", label);
	k = 0;
	while (lst != NULL && k <= g_made)
	{
		i = 0;
		while (i < g_made && lst != &g_node[i])
			i++;
		if (i == g_made)
		{
			printf("%s(a node the test did not make)", k == 0 ? "" : " ");
			break ;
		}
		printf("%s%c=", k == 0 ? "" : " ", 'a' + i);
		if (lst->content == &g_value[i])
			printf("%d", g_value[i]);
		else
			printf("(another content)");
		lst = lst->next;
		k++;
	}
	printf("\n");
}

/* MANY nodes: whether f was handed each content once, in list order. */
static void	many(void)
{
	int	k;

	ft_lstiter(make(MANY, 0), &f);
	k = 0;
	while (k < g_ncalls && k < MANY && g_order[k] == k)
		k++;
	printf("%d nodes: f called with\t", MANY);
	if (k == MANY && g_ncalls == MANY)
		printf("each content once, in list order\n");
	else if (k == g_ncalls)
		printf("%d calls, the contents of the first %d nodes\n", g_ncalls, k);
	else
		printf("call %d is not the content of node %d\n", k + 1, k + 1);
}

int	main(void)
{
	t_list	*lst;

	ft_lstiter(make(0, 0), &f);
	calls("NULL (the empty list)");
	lst = make(SMALL, 1);
	ft_lstiter(lst, &f);
	calls("[a b c]");
	show("[a b c], f adds 10", lst);
	lst = make(1, 7);
	ft_lstiter(lst, &f);
	calls("[a]");
	show("[a], f adds 10", lst);
	many();
	return (0);
}
