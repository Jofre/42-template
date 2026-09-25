#include "ft_btree.h"
#include <stdio.h>
#include <string.h>

/* Zero N nodes and give every one of them the same ITEM: no link exists until
 * main() sets one. */
static void	fill(t_btree *nodes, int n, void *item)
{
	memset(nodes, 0, n * sizeof(t_btree));
	while (n-- > 0)
		nodes[n].item = item;
}

/* Every tree is wired by hand in an array on the stack, so there is nothing to
 * free. ld/rd are four-node chains down one side; lh/rh put one extra node on
 * the short side of a five-deep chain, so only the long side is the height. */
int	main(void)
{
	int		v = 0;
	t_btree	single;
	t_btree	ld[4];
	t_btree	rd[4];
	t_btree	lh[6];
	t_btree	rh[6];

	fill(&single, 1, &v);
	fill(ld, 4, &v);
	fill(rd, 4, &v);
	fill(lh, 6, &v);
	fill(rh, 6, &v);
	ld[0].left = &ld[1];
	ld[1].left = &ld[2];
	ld[2].left = &ld[3];
	rd[0].right = &rd[1];
	rd[1].right = &rd[2];
	rd[2].right = &rd[3];
	lh[0].right = &lh[1];
	lh[0].left = &lh[2];
	lh[2].left = &lh[3];
	lh[3].left = &lh[4];
	lh[4].left = &lh[5];
	rh[0].left = &rh[1];
	rh[0].right = &rh[2];
	rh[2].right = &rh[3];
	rh[3].right = &rh[4];
	rh[4].right = &rh[5];
	printf("%d\n", btree_level_count(NULL));
	printf("%d\n", btree_level_count(&single));
	printf("%d\n", btree_level_count(ld));
	printf("%d\n", btree_level_count(rd));
	printf("%d\n", btree_level_count(lh));
	printf("%d\n", btree_level_count(rh));
	return (0);
}
