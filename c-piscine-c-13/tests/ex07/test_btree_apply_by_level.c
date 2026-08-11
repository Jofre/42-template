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

static void	apply(void *item, int level, int first)
{
	printf("level=%d first=%d item=%d\n", level, first, *(int *)item);
}

int	main(void)
{
	int		mix[6] = {1, 2, 3, 4, 5, 6};
	int		rl[6] = {11, 22, 33, 55, 66, 77};
	int		one = 9;
	t_btree	*root;
	t_btree	*single;
	t_btree	*right;

	printf("-- null --\n");
	btree_apply_by_level(NULL, apply);
	printf("-- single --\n");
	single = new_node(&one);
	btree_apply_by_level(single, apply);
	printf("-- mixed --\n");
	root = new_node(&mix[0]);
	root->left = new_node(&mix[1]);
	root->right = new_node(&mix[2]);
	root->left->left = new_node(&mix[3]);
	root->left->right = new_node(&mix[4]);
	root->right->right = new_node(&mix[5]);
	btree_apply_by_level(root, apply);
	printf("-- right leaning --\n");
	right = new_node(&rl[0]);
	right->left = new_node(&rl[1]);
	right->right = new_node(&rl[2]);
	right->left->right = new_node(&rl[3]);
	right->right->right = new_node(&rl[4]);
	right->right->right->right = new_node(&rl[5]);
	btree_apply_by_level(right, apply);
	free_tree(single);
	free_tree(root);
	free_tree(right);
	return (0);
}
