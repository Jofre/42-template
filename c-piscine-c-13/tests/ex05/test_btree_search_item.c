#include "ft_btree.h"
#include <stdio.h>
#include <stdlib.h>

typedef struct s_kv
{
	int		key;
	char	tag;
}	t_kv;

static int	cmp_kv(void *a, void *b)
{
	return (((t_kv *)a)->key - ((t_kv *)b)->key);
}

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

static void	report(void *res)
{
	if (res)
		printf("found key=%d tag=%c\n", ((t_kv *)res)->key,
			((t_kv *)res)->tag);
	else
		printf("not found\n");
}

int	main(void)
{
	t_kv	a = {5, 'A'};
	t_kv	b = {5, 'B'};
	t_kv	g = {3, 'G'};
	t_kv	e = {5, 'E'};
	t_kv	f = {5, 'F'};
	t_kv	m = {20, 'M'};
	t_kv	k = {10, 'K'};
	t_kv	r = {30, 'R'};
	t_kv	p = {25, 'P'};
	t_kv	s = {40, 'S'};
	t_kv	x = {1, 'X'};
	t_kv	c = {5, 'C'};
	t_kv	l = {5, 'L'};
	t_kv	d = {5, 'D'};
	t_kv	n5 = {5, '?'};
	t_kv	n3 = {3, '?'};
	t_kv	n99 = {99, '?'};
	t_kv	n30 = {30, '?'};
	t_kv	n25 = {25, '?'};
	t_kv	n40 = {40, '?'};
	t_btree	*t1;
	t_btree	*t2;
	t_btree	*t3;
	t_btree	*t4;

	t1 = new_node(&a);
	t1->left = new_node(&b);
	t1->left->left = new_node(&g);
	t2 = new_node(&e);
	t2->right = new_node(&f);
	t3 = new_node(&m);
	t3->left = new_node(&k);
	t3->right = new_node(&r);
	t3->right->left = new_node(&p);
	t3->right->right = new_node(&s);
	t4 = new_node(&x);
	t4->right = new_node(&c);
	t4->right->left = new_node(&l);
	t4->right->right = new_node(&d);
	printf("-- null tree --\n");
	report(btree_search_item(NULL, &n5, cmp_kv));
	printf("-- t1 search 5 (inorder first = B) --\n");
	report(btree_search_item(t1, &n5, cmp_kv));
	printf("-- t1 search 3 (leaf = G) --\n");
	report(btree_search_item(t1, &n3, cmp_kv));
	printf("-- t1 search 99 (absent) --\n");
	report(btree_search_item(t1, &n99, cmp_kv));
	printf("-- t2 search 5 (inorder first = E) --\n");
	report(btree_search_item(t2, &n5, cmp_kv));
	printf("-- t3 search 30 (right child = R) --\n");
	report(btree_search_item(t3, &n30, cmp_kv));
	printf("-- t3 search 25 (right subtree left = P) --\n");
	report(btree_search_item(t3, &n25, cmp_kv));
	printf("-- t3 search 40 (right-right = S) --\n");
	report(btree_search_item(t3, &n40, cmp_kv));
	printf("-- t4 search 5 (infix first in right subtree = L) --\n");
	report(btree_search_item(t4, &n5, cmp_kv));
	free_tree(t1);
	free_tree(t2);
	free_tree(t3);
	free_tree(t4);
	return (0);
}
