/* Memory-safety probe for btree_apply_by_level — run under AddressSanitizer.
 *
 * WHY THIS EXISTS. A breadth-first walk needs somewhere to remember the nodes
 * it has reached but not yet visited, and the cheapest thing to reach for is a
 * fixed-size array: `t_btree *cur[64]; t_btree *nxt[64];`. That version is
 * indistinguishable from a correct one on everything else this repo runs. It
 * reproduces tests/ex07/expected.txt BYTE FOR BYTE (measured), it is clean
 * under ASan+UBSan on the fixture's shapes, and it survives the 400k
 * differential and the 200k crash-fuzz without a murmur. It has to: the
 * fixture's largest tree is 6 nodes, and the corpus is capped twice over — the
 * oracle draws at most 10 items (oracle/src/c13.rs) and this exercise's
 * diff harness declares `char *items[64]`. Nothing in the suite ever hands the
 * function a level wider than a couple of nodes, so the capacity guess is never
 * contradicted and the board says the guess was fine.
 *
 * The valgrind layer cannot substitute for this one. The classic form of the
 * bug puts the queue on the STACK, and memcheck does not police stack frames;
 * even the malloc'd variant of the same mistake never overflows on a 6-node
 * tree. Width is the axis nothing else measures, so it is measured here.
 *
 * WHAT THE PROBE DOES. It hands the function trees whose SHAPE is adversarial,
 * and asserts nothing at all about the output — deciding whether the visit
 * order, the level numbers and is_first_elem are right is the *_output and
 * *_diff layers' job, and duplicating them here would only produce a second
 * red saying the same thing. Two shapes, aimed at the two ways a capacity gets
 * guessed:
 *
 *   1. A COMPLETE tree of depth 10 — 1023 nodes, bottom level 512 wide. Any
 *      buffer sized for a number the author picked (64, 128, 256 …) is written
 *      past while the walk crosses that level. A queue sized from the caller's
 *      data — count the nodes, then allocate — never is.
 *   2. A 200-deep alternating SPINE — one node per level, so it overflows no
 *      queue, but it does overflow the other guess: an array indexed by LEVEL
 *      (level boundaries, per-level heads, a per-level counter) sized for
 *      "trees are not that deep". Measured, so the two shapes are not
 *      redundant: a variant whose queue IS sized from the node count but whose
 *      boundaries live in an `int level_end[64]` — byte-exact on the fixture
 *      too — is red on this shape and green on shape 1, which is only ten
 *      levels deep. Together they say: a tree's width and its depth are both
 *      properties of the caller's data, not constants you may choose.
 *
 * Every allocation is EXACT — one malloc(sizeof(t_btree)) per node and one
 * malloc(sizeof(int)) per item — so a stray read or write anywhere near a node
 * or its item lands in a sanitizer redzone rather than on a harmless
 * neighbouring byte. NULL and the one-node tree are exercised too: a walk that
 * primes its queue before testing the root has nowhere to hide on them.
 *
 * A correct implementation is clean on all four inputs; verified before this
 * landed. This is a test input, not an implementation. */
#include "ft_btree.h"
#include <stdlib.h>

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

/* Exact-sized node + exact-sized item, so there is no slack on either side. */
static t_btree	*new_node(int id)
{
	t_btree	*node;
	int		*item;

	node = malloc(sizeof(t_btree));
	item = malloc(sizeof(int));
	*item = id;
	node->item = item;
	node->left = NULL;
	node->right = NULL;
	return (node);
}

/* Deterministic: same tree on every run, no entropy, no reliance on ASLR. */
static t_btree	*build_complete(int depth, int id)
{
	t_btree	*node;

	if (depth <= 0)
		return (NULL);
	node = new_node(id);
	node->left = build_complete(depth - 1, id * 2);
	node->right = build_complete(depth - 1, id * 2 + 1);
	return (node);
}

/* One node per level, alternating sides so neither a left-only nor a
 * right-only assumption is the shape that gets exercised. */
static t_btree	*build_spine(int depth)
{
	t_btree	*head;
	t_btree	*node;

	head = NULL;
	while (depth > 0)
	{
		node = new_node(depth);
		if (depth % 2 == 0)
			node->left = head;
		else
			node->right = head;
		head = node;
		depth--;
	}
	return (head);
}

static void	free_tree(t_btree *root)
{
	if (root == NULL)
		return ;
	free_tree(root->left);
	free_tree(root->right);
	free(root->item);
	free(root);
}

int	main(void)
{
	t_btree	*tree;

	btree_apply_by_level(NULL, &tally);
	tree = build_complete(1, 1);
	btree_apply_by_level(tree, &tally);
	free_tree(tree);
	tree = build_complete(10, 1);
	btree_apply_by_level(tree, &tally);
	free_tree(tree);
	tree = build_spine(200);
	btree_apply_by_level(tree, &tally);
	free_tree(tree);
	return (0);
}
