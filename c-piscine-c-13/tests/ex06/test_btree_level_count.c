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

int	main(void)
{
	int		v = 0;
	t_btree	*single;
	t_btree	*ld;
	t_btree	*rd;
	t_btree	*lh;
	t_btree	*rh;

	single = new_node(&v);
	ld = new_node(&v);
	ld->left = new_node(&v);
	ld->left->left = new_node(&v);
	ld->left->left->left = new_node(&v);
	rd = new_node(&v);
	rd->right = new_node(&v);
	rd->right->right = new_node(&v);
	rd->right->right->right = new_node(&v);
	lh = new_node(&v);
	lh->right = new_node(&v);
	lh->left = new_node(&v);
	lh->left->left = new_node(&v);
	lh->left->left->left = new_node(&v);
	lh->left->left->left->left = new_node(&v);
	rh = new_node(&v);
	rh->left = new_node(&v);
	rh->right = new_node(&v);
	rh->right->right = new_node(&v);
	rh->right->right->right = new_node(&v);
	rh->right->right->right->right = new_node(&v);
	printf("%d\n", btree_level_count(NULL));
	printf("%d\n", btree_level_count(single));
	printf("%d\n", btree_level_count(ld));
	printf("%d\n", btree_level_count(rd));
	printf("%d\n", btree_level_count(lh));
	printf("%d\n", btree_level_count(rh));
	free_tree(single);
	free_tree(ld);
	free_tree(rd);
	free_tree(lh);
	free_tree(rh);
	return (0);
}
