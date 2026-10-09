#include "ft_btree.h"
#include <stdio.h>
#include <string.h>

static void	print_item(void *item)
{
	printf("%d\n", *(int *)item);
}

/* Every tree is wired by hand in a zeroed array on the stack: node i holds
 * value i of the matching int array, a link exists only where a line below
 * sets it, and there is nothing to free. */
int	main(void)
{
	int		bal[7] = {1, 2, 3, 4, 5, 6, 7};
	int		one = 42;
	int		lch[3] = {10, 20, 30};
	int		rch[3] = {100, 200, 300};
	t_btree	single;
	t_btree	b[7];
	t_btree	l[3];
	t_btree	r[3];
	int		i;

	memset(&single, 0, sizeof(single));
	memset(b, 0, sizeof(b));
	memset(l, 0, sizeof(l));
	memset(r, 0, sizeof(r));
	single.item = &one;
	i = 0;
	while (i < 7)
	{
		b[i].item = &bal[i];
		i++;
	}
	i = 0;
	while (i < 3)
	{
		l[i].item = &lch[i];
		r[i].item = &rch[i];
		i++;
	}
	b[3].left = &b[1];
	b[3].right = &b[5];
	b[1].left = &b[0];
	b[1].right = &b[2];
	b[5].left = &b[4];
	b[5].right = &b[6];
	l[2].left = &l[1];
	l[1].left = &l[0];
	r[0].right = &r[1];
	r[1].right = &r[2];
	printf("-- null --\n");
	btree_apply_suffix(NULL, print_item);
	printf("-- single --\n");
	btree_apply_suffix(&single, print_item);
	printf("-- balanced --\n");
	btree_apply_suffix(&b[3], print_item);
	printf("-- left chain --\n");
	btree_apply_suffix(&l[2], print_item);
	printf("-- right chain --\n");
	btree_apply_suffix(&r[0], print_item);
	return (0);
}
