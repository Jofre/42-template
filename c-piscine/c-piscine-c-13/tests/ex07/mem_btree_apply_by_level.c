/* Memory-safety probe for btree_apply_by_level — run under AddressSanitizer.
 *
 * WHY THIS EXISTS. The fixture's hand-wired trees are 6 nodes at most, and
 * the differential's largest trees hold 2000 items. A function can be right
 * on every one of them, clean under ASan+UBSan on their shapes, and still
 * read or write out of bounds on a tree much wider or much deeper than they
 * are. The fixture's one big tree (the same 20000 nodes as below) reports a
 * node visited wrong; this probe reports an access out of bounds even when
 * every node is visited right. It asserts nothing about the output.
 *
 * The valgrind layer cannot substitute for this one: memcheck does not police
 * stack frames, and a heap block too small for these trees is never
 * overflowed by a 6-node one. Width and depth are the axes nothing else
 * measures, so they are measured here.
 *
 * WHAT THE PROBE DOES. It hands the function trees whose SHAPE is extreme.
 * Whether the visit order, the level numbers and is_first_elem are right is
 * the *_output and *_diff layers' job, and checking them here would only
 * produce a second red saying the same thing. Two shapes, one per axis:
 *
 *   1. WIDTH: a HEAP-SHAPED tree of 20000 nodes — every level full but the
 *      last, which is filled from the left: fifteen levels, 8192 nodes on the
 *      widest one and 3617 on the last.
 *   2. DEPTH: a 5000-deep alternating SPINE — one node per level, so it is
 *      never more than one node wide.
 *
 * Measured, so the two shapes are not redundant: each reds a toy variant —
 * byte-exact on the fixture too — that the other leaves green, because the
 * heap is only fifteen levels deep and the spine is one node wide. A tree's
 * width and depth both come from the caller's data, so the sizes sit past
 * every power of two a fixed capacity is likely to stop at. The first version
 * of this probe used a complete tree of 1023 nodes and a 200-deep spine, and
 * a toy with a fixed capacity of 1024 passed it (finding 041).
 *
 * Every allocation is EXACT — one block the size of a node per node, and one
 * the size of an int per item — so a stray read or write anywhere near a node
 * or its item lands in a sanitizer redzone rather than on a harmless
 * neighbouring byte. NULL and the one-node tree are exercised too.
 *
 * A correct implementation is clean on all four inputs; verified before this
 * landed. This is a test input, not an implementation. */
#include "ft_btree.h"
#include <stdlib.h>

/* The biggest tree below: the heap-shaped one. */
#define MAX_NODES 20000

/* Consumed so the item pointer is really dereferenced: a node whose item was
 * mangled by a stray write is then a read of freed/redzoned memory, not a value
 * quietly ignored. Nothing is printed and nothing is compared. */
static int	g_checksum;

static void	tally(void *item, int current_level, int is_first_elem)
{
	(void)current_level;
	(void)is_first_elem;
	g_checksum += *(int *)item;
}

/* Every node and every item of the current tree, recorded as they are made,
 * so the tree is freed from these arrays and never walked. */
static t_btree	*g_node[MAX_NODES];
static int		*g_item[MAX_NODES];
static int		g_count;

/* N nodes, each its own exact-sized block holding its own exact-sized item
 * (id i + 1), every link empty: the shape is wired afterwards, by index. */
static void	make_nodes(int n)
{
	int	i;

	g_count = n;
	i = 0;
	while (i < n)
	{
		g_node[i] = calloc(1, sizeof(t_btree));
		g_item[i] = malloc(sizeof(int));
		*g_item[i] = i + 1;
		g_node[i]->item = g_item[i];
		i++;
	}
}

/* A tree of N nodes numbered the way a heap is: the children of node i are
 * nodes 2i + 1 and 2i + 2, so every level is full but the last, which fills
 * from the left. Deterministic — same tree on every run, no entropy, no
 * reliance on ASLR. */
static t_btree	*plant_heap(int n)
{
	int	i;

	make_nodes(n);
	i = 0;
	while (i < n)
	{
		if (2 * i + 1 < n)
			g_node[i]->left = g_node[2 * i + 1];
		if (2 * i + 2 < n)
			g_node[i]->right = g_node[2 * i + 2];
		i++;
	}
	return (g_node[0]);
}

/* One node per level, each hanging off the one above it on alternating sides,
 * so neither a left-only nor a right-only assumption is the shape that gets
 * exercised. */
static t_btree	*plant_spine(int depth)
{
	int	i;

	make_nodes(depth);
	i = 0;
	while (i + 1 < depth)
	{
		if (i % 2 == 0)
			g_node[i]->right = g_node[i + 1];
		else
			g_node[i]->left = g_node[i + 1];
		i++;
	}
	return (g_node[0]);
}

static void	release(void)
{
	while (g_count > 0)
	{
		g_count--;
		free(g_item[g_count]);
		free(g_node[g_count]);
	}
}

int	main(void)
{
	btree_apply_by_level(NULL, &tally);
	btree_apply_by_level(plant_heap(1), &tally);
	release();
	btree_apply_by_level(plant_heap(20000), &tally);
	release();
	btree_apply_by_level(plant_spine(5000), &tally);
	release();
	return (0);
}
