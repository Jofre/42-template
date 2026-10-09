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

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each tree in its own row. */
static void	test(char *label, t_btree *root)
{
	printf("%s\t%d\n", label, btree_level_count(root));
}

/* Every tree is wired by hand in an array on the stack, so there is nothing to
 * free. ld/rd are four-node chains down one side; lh/rh put one extra node on
 * the short side of a five-deep chain, so only the long side is the height.
 * lr/rl put their deepest node at the end of an INNER path -- down one side,
 * then zigzagging towards the middle -- while both outer edges, the path that
 * only ever goes left and the one that only ever goes right, stop two levels
 * down: the height there is reached by no outer edge. */
int	main(void)
{
	int		v = 0;
	t_btree	single;
	t_btree	ld[4];
	t_btree	rd[4];
	t_btree	lh[6];
	t_btree	rh[6];
	t_btree	lr[6];
	t_btree	rl[6];

	fill(&single, 1, &v);
	fill(ld, 4, &v);
	fill(rd, 4, &v);
	fill(lh, 6, &v);
	fill(rh, 6, &v);
	fill(lr, 6, &v);
	fill(rl, 6, &v);
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
	lr[0].left = &lr[1];
	lr[0].right = &lr[2];
	lr[1].right = &lr[3];
	lr[3].left = &lr[4];
	lr[4].right = &lr[5];
	rl[0].left = &rl[1];
	rl[0].right = &rl[2];
	rl[2].left = &rl[3];
	rl[3].right = &rl[4];
	rl[4].left = &rl[5];
	test("empty tree", NULL);
	test("single node", &single);
	test("left chain of four", ld);
	test("right chain of four", rd);
	test("long left side, one node on the right", lh);
	test("long right side, one node on the left", rh);
	test("deepest on an inner path, left then right", lr);
	test("deepest on an inner path, right then left", rl);
	return (0);
}
