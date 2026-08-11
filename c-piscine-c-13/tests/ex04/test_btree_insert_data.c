#include "ft_btree.h"
#include <stdio.h>
#include <stdlib.h>

static int	cmp_int(void *a, void *b)
{
	return (*(int *)a - *(int *)b);
}

static void	prefix_print(t_btree *root)
{
	if (root == NULL)
		return ;
	printf("%d\n", *(int *)root->item);
	prefix_print(root->left);
	prefix_print(root->right);
}

static void	infix_print(t_btree *root)
{
	if (root == NULL)
		return ;
	infix_print(root->left);
	printf("%d\n", *(int *)root->item);
	infix_print(root->right);
}

static void	free_tree(t_btree *root)
{
	if (root == NULL)
		return ;
	free_tree(root->left);
	free_tree(root->right);
	free(root);
}

static void	show(const char *label, t_btree *node)
{
	if (node)
		printf("%s set %d\n", label, *(int *)node->item);
	else
		printf("%s NULL\n", label);
}

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
	printf("-- infix (sorted) --\n");
	infix_print(root);
	printf("-- prefix (shape) --\n");
	prefix_print(root);
	droot = NULL;
	i = 0;
	while (i < 3)
	{
		btree_insert_data(&droot, &dups[i], cmp_int);
		i++;
	}
	printf("-- dup root --\n");
	show("root", droot);
	show("left", droot ? droot->left : NULL);
	show("right", droot ? droot->right : NULL);
	if (droot && droot->right)
		show("right-right", droot->right->right);
	else
		printf("right-right NULL\n");
	free_tree(root);
	free_tree(droot);
	return (0);
}
