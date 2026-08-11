#include "ft_btree.h"
#include <stdio.h>
#include <stdlib.h>

static t_btree	*new_node(void *item)
{
	t_btree	*node;

	node = malloc(sizeof(t_btree));
	node->item = item;
	node->left = NULL;
	node->right = NULL;
	return (node);
}

static void	free_tree(t_btree *root)
{
	if (root == NULL)
		return ;
	free_tree(root->left);
	free_tree(root->right);
	free(root);
}

static void	print_item(void *item)
{
	printf("%d\n", *(int *)item);
}

int	main(void)
{
	int		bal[7] = {1, 2, 3, 4, 5, 6, 7};
	int		one = 42;
	int		lch[3] = {10, 20, 30};
	int		rch[3] = {100, 200, 300};
	t_btree	*root;
	t_btree	*single;
	t_btree	*lchain;
	t_btree	*rchain;

	printf("-- null --\n");
	btree_apply_prefix(NULL, print_item);
	printf("-- single --\n");
	single = new_node(&one);
	btree_apply_prefix(single, print_item);
	printf("-- balanced --\n");
	root = new_node(&bal[3]);
	root->left = new_node(&bal[1]);
	root->right = new_node(&bal[5]);
	root->left->left = new_node(&bal[0]);
	root->left->right = new_node(&bal[2]);
	root->right->left = new_node(&bal[4]);
	root->right->right = new_node(&bal[6]);
	btree_apply_prefix(root, print_item);
	printf("-- left chain --\n");
	lchain = new_node(&lch[2]);
	lchain->left = new_node(&lch[1]);
	lchain->left->left = new_node(&lch[0]);
	btree_apply_prefix(lchain, print_item);
	printf("-- right chain --\n");
	rchain = new_node(&rch[0]);
	rchain->right = new_node(&rch[1]);
	rchain->right->right = new_node(&rch[2]);
	btree_apply_prefix(rchain, print_item);
	free_tree(single);
	free_tree(root);
	free_tree(lchain);
	free_tree(rchain);
	return (0);
}
