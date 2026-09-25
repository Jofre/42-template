#include "ft_btree.h"
#include <stdio.h>
#include <string.h>

typedef struct s_kv
{
	int		key;
	char	tag;
}	t_kv;

static int	cmp_kv(void *a, void *b)
{
	return (((t_kv *)a)->key - ((t_kv *)b)->key);
}

static void	report(void *res)
{
	if (res)
		printf("found key=%d tag=%c\n", ((t_kv *)res)->key,
			((t_kv *)res)->tag);
	else
		printf("not found\n");
}

/* Every tree is wired by hand in a zeroed array on the stack: a link exists
 * only where a line below sets it, and there is nothing to free. */
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
	t_btree	t1[3];
	t_btree	t2[2];
	t_btree	t3[5];
	t_btree	t4[4];

	memset(t1, 0, sizeof(t1));
	memset(t2, 0, sizeof(t2));
	memset(t3, 0, sizeof(t3));
	memset(t4, 0, sizeof(t4));
	t1[0].item = &a;
	t1[1].item = &b;
	t1[2].item = &g;
	t1[0].left = &t1[1];
	t1[1].left = &t1[2];
	t2[0].item = &e;
	t2[1].item = &f;
	t2[0].right = &t2[1];
	t3[0].item = &m;
	t3[1].item = &k;
	t3[2].item = &r;
	t3[3].item = &p;
	t3[4].item = &s;
	t3[0].left = &t3[1];
	t3[0].right = &t3[2];
	t3[2].left = &t3[3];
	t3[2].right = &t3[4];
	t4[0].item = &x;
	t4[1].item = &c;
	t4[2].item = &l;
	t4[3].item = &d;
	t4[0].right = &t4[1];
	t4[1].left = &t4[2];
	t4[1].right = &t4[3];
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
	return (0);
}
