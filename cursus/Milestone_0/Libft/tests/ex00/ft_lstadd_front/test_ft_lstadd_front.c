#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include "libft.h"

/* ft_lstadd_front's basic table. Its box (Libft, p.14): "Adds the node 'new'
 * at the beginning of the list.", lst being "The address of a pointer to the
 * first node of a list". A NULL first node is the empty list.
 *
 * Every node is the test's own, never one of ft_lstnew's, so a red here is
 * about this function alone. The small cases' nodes are named a, b, c, ... by
 * WHERE they are, not by what they hold: each row prints the list *lst leads
 * to afterwards, node by node, so a node copied instead of linked shows. Before
 * each call new->next is set to a node of the test's that is in no list, z,
 * which no list may reach afterwards. A walk stops after one node more than
 * the test made, so a list that loops back on itself still prints. */
void	ft_lstadd_front(t_list **lst, t_list *new);

#define SMALL 8
#define MANY 5000

static t_list	g_node[SMALL];
static t_list	g_z;

/* The row: label, then the nodes from lst, by name; "(empty)" for none. */
static void	show(const char *label, t_list *lst)
{
	int	k;
	int	i;

	printf("%s\t", label);
	if (lst == NULL)
		printf("(empty)");
	k = 0;
	while (lst != NULL && k <= SMALL)
	{
		i = 0;
		while (i < SMALL && lst != &g_node[i])
			i++;
		printf("%s", k == 0 ? "" : " ");
		if (lst == &g_z)
			printf("z");
		else if (i == SMALL)
		{
			printf("(a node the test did not make)");
			break ;
		}
		else
			printf("%c", 'a' + i);
		lst = lst->next;
		k++;
	}
	if (lst != NULL && k > SMALL)
		printf(" ...(still going after %d nodes)", SMALL + 1);
	printf("\n");
}

/* The list a, b, ... of n nodes, linked in that order; NULL when n is 0. */
static t_list	*list(int n)
{
	int	i;

	i = 0;
	while (i < SMALL)
	{
		g_node[i].content = NULL;
		g_node[i].next = (i + 1 < n) ? &g_node[i + 1] : NULL;
		i++;
	}
	g_z.content = NULL;
	g_z.next = NULL;
	if (n == 0)
		return (NULL);
	return (&g_node[0]);
}

/* Node k of the test's, with its next set to z: what the call is handed. */
static t_list	*fresh(int k)
{
	g_node[k].next = &g_z;
	return (&g_node[k]);
}

/* MANY nodes in one block, node 1 added in front of nodes 2 .. MANY: whether
 * *lst then leads through all of them, in order, and ends. */
static void	many(void)
{
	t_list	*blk;
	t_list	*lst;
	int		k;

	blk = calloc(MANY, sizeof(t_list));
	if (blk == NULL)
		exit(1);
	k = 1;
	while (k + 1 < MANY)
	{
		blk[k].next = &blk[k + 1];
		k++;
	}
	blk[0].next = &g_z;
	lst = &blk[1];
	ft_lstadd_front(&lst, &blk[0]);
	k = 0;
	while (lst != NULL && k < MANY && lst == &blk[k])
	{
		lst = lst->next;
		k++;
	}
	printf("nodes 2 to %d, then node 1\t", MANY);
	if (k == MANY && lst == NULL)
		printf("%d nodes, 1 to %d in order\n", MANY, MANY);
	else if (lst == NULL)
		printf("ends after %d nodes\n", k);
	else if (k == MANY)
		printf("still going after %d nodes\n", MANY);
	else
		printf("node %d is not the one put there\n", k + 1);
	free(blk);
}

int	main(void)
{
	t_list	*lst;

	lst = list(0);
	ft_lstadd_front(&lst, fresh(0));
	show("empty list, then a", lst);
	lst = list(1);
	ft_lstadd_front(&lst, fresh(1));
	show("[a], then b", lst);
	lst = list(3);
	ft_lstadd_front(&lst, fresh(3));
	show("[a b c], then d", lst);
	lst = list(0);
	ft_lstadd_front(&lst, fresh(0));
	ft_lstadd_front(&lst, fresh(1));
	ft_lstadd_front(&lst, fresh(2));
	show("empty list, then a, b and c", lst);
	many();
	return (0);
}
