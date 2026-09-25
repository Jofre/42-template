#include "ft_btree.h"
#include <stdio.h>
#include <stdlib.h>

static int	cmp_int(void *a, void *b)
{
	return (*(int *)a - *(int *)b);
}

/* Every node the test finds is recorded here once, and freed from here: the
 * tree is looked at only through the literal paths below, never walked. */
static t_btree	*g_found[32];
static int		g_nfound;

static void	remember(t_btree *node)
{
	int	i;

	if (node == NULL)
		return ;
	i = 0;
	while (i < g_nfound)
		if (g_found[i++] == node)
			return ;
	if (g_nfound < 32)
		g_found[g_nfound++] = node;
}

/* The node at the end of PATH: one step per letter from the root, L down the
 * left link and R down the right. NULL as soon as a link is empty. */
static t_btree	*at(t_btree *root, const char *path)
{
	while (root != NULL && *path != '\0')
	{
		if (*path == 'L')
			root = root->left;
		else
			root = root->right;
		path++;
	}
	return (root);
}

static void	show(const char *label, t_btree *node)
{
	if (node)
		printf("%s set %d\n", label, *(int *)node->item);
	else
		printf("%s NULL\n", label);
}

/* Print what the tree holds at PATH, under LABEL, and keep it for freeing. */
static void	probe(const char *label, t_btree *root, const char *path)
{
	show(label, at(root, path));
	remember(at(root, path));
}

/* Where the subject's rule (lower on the left, higher or equal on the right)
 * puts 5 3 8 1 4 7 9 2 6 inserted in that order, worked out by hand one insert
 * at a time, and checked again by the oracle's model (oracle/src/c13.rs,
 * "ex04 fixture routes"). NODES lists the items' paths in insertion order;
 * EMPTY lists every child slot of that tree that must stay empty -- an extra
 * node anywhere hangs off one of them. Together they pin the whole tree, which
 * is why nothing else needs to be printed. */
static const char	*g_nodes[9] = {"", "L", "R", "LL", "LR", "RL", "RR",
	"LLR", "RLL"};
static const char	*g_empty[10] = {"LLL", "LLRL", "LLRR", "LRL", "LRR",
	"RLLL", "RLLR", "RLR", "RRL", "RRR"};

int	main(void)
{
	int		vals[9] = {5, 3, 8, 1, 4, 7, 9, 2, 6};
	int		dups[3] = {5, 5, 5};
	t_btree	*root;
	t_btree	*droot;
	int		i;

	root = NULL;
	i = 0;
	while (i < 9)
	{
		btree_insert_data(&root, &vals[i], cmp_int);
		i++;
	}
	printf("-- item at each path (L = left, R = right) --\n");
	probe("root", root, g_nodes[0]);
	i = 1;
	while (i < 9)
	{
		probe(g_nodes[i], root, g_nodes[i]);
		i++;
	}
	printf("-- slots that must stay empty --\n");
	i = 0;
	while (i < 10)
	{
		probe(g_empty[i], root, g_empty[i]);
		i++;
	}
	droot = NULL;
	i = 0;
	while (i < 3)
	{
		btree_insert_data(&droot, &dups[i], cmp_int);
		i++;
	}
	printf("-- dup root --\n");
	probe("root", droot, "");
	probe("left", droot, "L");
	probe("right", droot, "R");
	probe("right-right", droot, "RR");
	/* This block keeps its four rows. The dup tree's other empty slots are
	 * not printed, but whatever a wrong insert put there is still freed. */
	remember(at(droot, "RL"));
	remember(at(droot, "RRL"));
	remember(at(droot, "RRR"));
	i = 0;
	while (i < g_nfound)
		free(g_found[i++]);
	return (0);
}
