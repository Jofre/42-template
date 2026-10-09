/* Memory-safety probe for btree_apply_by_level — run under AddressSanitizer.
 *
 * WHY THIS EXISTS. A breadth-first walk needs somewhere to remember the nodes
 * it has reached but not yet visited, and how much room that takes is not the
 * author's to choose: it is a property of the tree the function is handed —
 * how wide its widest level is, and how deep it goes. The fixture's
 * hand-wired trees are 6 nodes at most, and the differential's largest trees
 * hold 2000 items. So a walk whose capacity is a constant past those
 * reproduces them BYTE FOR BYTE, is clean under ASan+UBSan on their shapes,
 * and survives the differential and the crash-fuzz without a murmur. The
 * fixture's one big tree (the same 20000 nodes as below) says it outright
 * when such a walk visits a node wrong; this probe is what catches the walk
 * that writes past its room and happens to visit everything right anyway.
 *
 * The valgrind layer cannot substitute for this one. Room of a fixed size
 * usually lives on the STACK, and memcheck does not police stack frames; even
 * a heap block of a guessed size never overflows on a 6-node tree. Width and
 * depth are the axes nothing else measures, so they are measured here.
 *
 * WHAT THE PROBE DOES. It hands the function trees whose SHAPE is adversarial,
 * and asserts nothing at all about the output — deciding whether the visit
 * order, the level numbers and is_first_elem are right is the *_output and
 * *_diff layers' job, and duplicating them here would only produce a second
 * red saying the same thing. Two shapes, one per axis:
 *
 *   1. A HEAP-SHAPED tree of 20000 nodes — every level full but the last,
 *      which is filled from the left: fifteen levels, 8192 nodes on the widest
 *      one and 3617 on the last. Room for waiting nodes fixed at a round
 *      number (64, 256, 1024, 4096, 16384 …) is written past while the walk
 *      crosses those levels.
 *   2. A 5000-deep alternating SPINE — one node per level, so it is never wide,
 *      but anything kept PER LEVEL in room fixed at "trees are not that deep"
 *      is written past. Measured, so the two shapes are not redundant: each
 *      reds a variant — byte-exact on the fixture too — that the other leaves
 *      green, because the heap is only fifteen levels deep and the spine is
 *      never more than one node wide.
 *
 * Together they say: a tree's width and its depth both come from the caller's
 * data, and the probe fails a capacity chosen as a constant, at any of the
 * sizes such a guess lands on. The first version of this probe used a complete
 * tree of 1023 nodes and a 200-deep spine and claimed exactly that — and room
 * for 1024 waiting nodes passed it (finding 041). The sizes now sit past every
 * power of two a guess is likely to stop at.
 *
 * Every allocation is EXACT — one block the size of a node per node, and one
 * the size of an int per item — so a stray read or write anywhere near a node
 * or its item lands in a sanitizer redzone rather than on a harmless
 * neighbouring byte. NULL and the one-node tree are exercised too: a walk that
 * primes its queue before testing the root has nowhere to hide on them.
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
