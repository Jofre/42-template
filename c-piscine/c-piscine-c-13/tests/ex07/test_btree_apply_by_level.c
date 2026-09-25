#include "ft_btree.h"
#include <stdio.h>
#include <string.h>

static void	apply(void *item, int level, int first)
{
	printf("level=%d first=%d item=%d\n", level, first, *(int *)item);
}

/* Every tree is wired by hand in a zeroed array on the stack: node i holds
 * value i of the matching int array, a link exists only where a line below
 * sets it, and there is nothing to free. */
int	main(void)
{
	int		mix[6] = {1, 2, 3, 4, 5, 6};
	int		rl[6] = {11, 22, 33, 55, 66, 77};
	int		one = 9;
	t_btree	single;
	t_btree	m[6];
	t_btree	w[6];
	int		i;

	memset(&single, 0, sizeof(single));
	memset(m, 0, sizeof(m));
	memset(w, 0, sizeof(w));
	single.item = &one;
	i = 0;
	while (i < 6)
	{
		m[i].item = &mix[i];
		w[i].item = &rl[i];
		i++;
	}
	m[0].left = &m[1];
	m[0].right = &m[2];
	m[1].left = &m[3];
	m[1].right = &m[4];
	m[2].right = &m[5];
	w[0].left = &w[1];
	w[0].right = &w[2];
	w[1].right = &w[3];
	w[2].right = &w[4];
	w[4].right = &w[5];
	printf("-- null --\n");
	btree_apply_by_level(NULL, apply);
	printf("-- single --\n");
	btree_apply_by_level(&single, apply);
	printf("-- mixed --\n");
	btree_apply_by_level(&m[0], apply);
	printf("-- right leaning --\n");
	btree_apply_by_level(&w[0], apply);
	return (0);
}
