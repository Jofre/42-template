#include "ft_btree.h"
#include <stdio.h>
#include <string.h>

static void	apply(void *item, int level, int first)
{
	printf("level=%d first=%d item=%d\n", level, first, *(int *)item);
}

/* THE BIG TREE: 20000 nodes numbered the way a heap is, the children of node
 * i being nodes 2i + 1 and 2i + 2 -- every level full but the last, which
 * fills from the left: fifteen levels, 8192 nodes on the widest. The subject
 * bounds no size, and its three arguments decide everything else, so every
 * reading agrees on what the walk must do here: visit node k (item k) k-th,
 * at level floor(log2(k + 1)), first exactly when k + 1 is a power of two.
 * That is checked by construction as the walk goes, and shown as ONE line,
 * not 20000: past every capacity room for waiting nodes is usually given
 * (64, 256, 1024, 4096, 16384), a walk that keeps them in room of its own
 * fixed size gets it wrong here, or dies (finding 041). */
#define BIG 20000

static t_btree	g_big[BIG];
static int		g_bigitem[BIG];
static int		g_seen;
static int		g_bad;
static char		g_why[160];

static int	level_of(int k)
{
	int	level;

	level = 0;
	while ((2 << level) - 1 <= k)
		level++;
	return (level);
}

static void	check_big(void *item, int level, int first)
{
	int	k;

	k = g_seen++;
	if (g_bad)
		return ;
	if (k >= BIG)
		snprintf(g_why, sizeof(g_why), "more than %d visits", BIG);
	else if (*(int *)item != k)
		snprintf(g_why, sizeof(g_why), "visit %d was item %d, not %d", k,
			*(int *)item, k);
	else if (level != level_of(k))
		snprintf(g_why, sizeof(g_why), "item %d had level %d, not %d", k,
			level, level_of(k));
	else if (first != (((k + 1) & k) == 0))
		snprintf(g_why, sizeof(g_why), "item %d had first=%d, not %d", k,
			first, ((k + 1) & k) == 0);
	else
		return ;
	g_bad = 1;
}

static void	test_big(void)
{
	int	i;

	i = 0;
	while (i < BIG)
	{
		g_bigitem[i] = i;
		g_big[i].item = &g_bigitem[i];
		if (2 * i + 1 < BIG)
			g_big[i].left = &g_big[2 * i + 1];
		if (2 * i + 2 < BIG)
			g_big[i].right = &g_big[2 * i + 2];
		i++;
	}
	printf("-- 20000 nodes, heap-shaped --\n");
	btree_apply_by_level(&g_big[0], check_big);
	if (!g_bad && g_seen != BIG)
		snprintf(g_why, sizeof(g_why), "%d visits, not %d", g_seen, BIG);
	if (g_bad || g_seen != BIG)
		printf("%s\n", g_why);
	else
		printf("20000 visits in level order, levels 0..14, one first per level\n");
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
	test_big();
	return (0);
}
