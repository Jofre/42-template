/* Memory-safety probe for btree_apply_by_level — run under AddressSanitizer.
 *
 * WHY THIS EXISTS. A breadth-first walk needs somewhere to remember the nodes
 * it has reached but not yet visited, and how much room that takes is not the
 * author's to choose: it is a property of the tree the function is handed —
 * how wide its widest level is, and how deep it goes. Nothing else in this
 * suite ever hands the function a tree big enough for a guessed capacity to
 * show. The fixture's largest tree is 6 nodes, and the corpus is capped twice
 * over — the oracle draws at most 10 items (oracle/src/c13.rs) and this
 * exercise's diff harness decodes at most 64. So a walk whose capacity is a
 * constant reproduces tests/ex07/expected.txt BYTE FOR BYTE (measured), is
 * clean under ASan+UBSan on the fixture's shapes, and survives the 400k
 * differential and the 200k crash-fuzz without a murmur. The board says the
 * guess was fine.
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
 *   1. A COMPLETE tree of depth 10 — 1023 nodes, bottom level 512 wide. Room
 *      for waiting nodes that was fixed at a round number (64, 128, 256 …) is
 *      written past while the walk crosses that level.
 *   2. A 200-deep alternating SPINE — one node per level, so it is never wide,
 *      but anything kept PER LEVEL in room fixed at "trees are not that deep"
 *      is written past. Measured, so the two shapes are not redundant: each
 *      reds a variant — byte-exact on the fixture too — that the other leaves
 *      green, because the complete tree is only ten levels deep and the spine
 *      is never more than one node wide.
 *
 * Together they say: a tree's width and its depth both come from the caller's
 * data, and the probe fails a capacity chosen as a constant, at any of the
 * sizes such a guess lands on — the trees here need 512 across and 200 down.
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

/* The biggest tree below: complete, ten levels. */
#define MAX_NODES 1023

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

/* A complete tree of DEPTH levels, numbered the way a heap is: the children of
 * node i are nodes 2i + 1 and 2i + 2. Deterministic — same tree on every run,
 * no entropy, no reliance on ASLR. */
static t_btree	*plant_complete(int depth)
{
	int	n;
	int	i;

	n = (1 << depth) - 1;
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
	btree_apply_by_level(plant_complete(1), &tally);
	release();
	btree_apply_by_level(plant_complete(10), &tally);
	release();
	btree_apply_by_level(plant_spine(200), &tally);
	release();
	return (0);
}
