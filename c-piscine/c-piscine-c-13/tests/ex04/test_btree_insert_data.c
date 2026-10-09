#include "ft_btree.h"
#include <stdio.h>
#include <stdlib.h>

static int	cmp_int(void *a, void *b)
{
	return (*(int *)a - *(int *)b);
}

/* Every node the test finds is recorded here once, and freed from here: the
 * tree is looked at only through literal paths, never walked. */
static t_btree	*g_found[1024];
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
	if (g_nfound < 1024)
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

/* The teardown's reach: every route of DEPTH steps or fewer from the root,
 * each spelled out as a path of L and R -- the binary digits of a counter --
 * and looked up through at(), whatever it reaches remembered for freeing.
 * That is every one of the 2^(DEPTH+1) - 1 routes, so nothing is walked, and
 * nothing is done to a node but noting it. A tree built by DEPTH inserts has
 * no node deeper than that, so every node an insert linked in -- where the
 * subject's rule puts it or anywhere else -- is found and freed, and valgrind
 * reports only what the function allocated and never linked (finding 137:
 * fixed routes used to leave a wrongly placed node unfreed, and valgrind blamed
 * the function for the test's own teardown). At most 9 here, and g_found holds
 * a node per route. */
static void	remember_routes(t_btree *root, int depth)
{
	char	path[16];
	int		len;
	int		bits;
	int		i;

	len = 0;
	while (len <= depth)
	{
		bits = 0;
		while (bits < (1 << len))
		{
			i = 0;
			while (i < len)
			{
				if ((bits >> i) & 1)
					path[i] = 'R';
				else
					path[i] = 'L';
				i++;
			}
			path[len] = '\0';
			remember(at(root, path));
			bits++;
		}
		len++;
	}
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
	/* Both trees are freed through every route as deep as their inserts:
	 * what a wrong insert put anywhere is freed too, printed or not. */
	remember_routes(root, 9);
	remember_routes(droot, 3);
	i = 0;
	while (i < g_nfound)
		free(g_found[i++]);
	return (0);
}
