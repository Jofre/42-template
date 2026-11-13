/* Live-differential reader harness for btree_search_item.
 * Line: <seq>\t<shape>\t<hexQuery>\t<at>\t<hexFound|NULL>. seq = the items,
 * comma-joined hex; shape = where each one hangs ("-" the root, "3L" left of
 * item 3); at = which item of seq the returned pointer is, by its index, or
 * -1 when it is none of them. Links the tree from seq and shape, runs the
 * student's btree_search_item with a strcmp comparator that answers "no
 * match" to a call not handing it the query (in either place), and reprints
 * <seq>\t<shape>\t<hexQuery>\t, then <at>\t and the bytes (hex) the returned
 * pointer points at, or NULL. See diffio.h. */
#include "diffio.h"
#include "ft_btree.h"

void	*btree_search_item(t_btree *root, void *data_ref,
			int (*cmpf)(void *, void *));

/* The query this case passes. Either argument may be it -- the subject
 * fixes no order for cmpf's two (WP-46's decision) -- but one of them must
 * be: a call where neither argument is the query (a node, one item twice)
 * is answered "no match" without reading it, so a search that never hands
 * over data_ref finds nothing and the record diverges. That is all this
 * comparator refuses: a call handing it the query as both arguments is
 * read, and matches. The output fixture's cmp_kv is the stricter one
 * (test_btree_search_item.c): it refuses, and counts, every call that does
 * not pair data_ref with an item of the tree. */
static void	*g_query;

static int	cmp_str(void *a, void *b)
{
	if (a != g_query && b != g_query)
		return (1);
	return (strcmp((char *)a, (char *)b));
}

/* The tree is built BY CONSTRUCTION from the oracle's shape: pool[i] holds
 * items[i] and is linked under pool[parent] on the side the shape names. The
 * pool comes zeroed, so every link the shape does not set stays empty. Nothing
 * here compares an item or walks a tree -- where each item belongs was decided
 * by the reference, which keeps this harness free of any
 * insert, and the whole tree is one block to free. */
static t_btree	*plant(t_btree *pool, char **items, char *shape, int n)
{
	t_btree	*root;
	char	*p;
	long	parent;
	int		i;

	root = NULL;
	p = shape;
	i = 0;
	while (i < n && p != NULL)
	{
		pool[i].item = items[i];
		if (*p == '-')
			root = &pool[i];
		else
		{
			parent = strtol(p, &p, 10);
			if (*p == 'L')
				pool[parent].left = &pool[i];
			else
				pool[parent].right = &pool[i];
		}
		p = strchr(p, ',');
		if (p != NULL)
			p++;
		i++;
	}
	return (root);
}

/* Which node's item `res` is: its index in the pool, which is its index in
 * seq, or -1 for a pointer that is no node's item. Equal items have the same
 * bytes, so only the pointer says which of them came back. */
static int	pool_index(t_btree *pool, int n, void *res)
{
	int	i;

	i = 0;
	while (i < n)
	{
		if (pool[i].item == res)
			return (i);
		i++;
	}
	return (-1);
}

int	main(void)
{
	char			*line;
	size_t			cap;
	char			*f[4];
	char			**items;
	unsigned char	*q;
	t_btree			*pool;
	t_btree			*root;
	void			*res;
	int				n;

	/* A line of any length (tools/diffio.h): the corpus holds lists and
	 * trees of hundreds and thousands of nodes (finding 041). */
	line = NULL;
	cap = 0;
	while (dio_getline(&line, &cap))
	{
		dio_fields(line, f, 4, 3);
		printf("%s\t%s\t%s\t", f[0], f[1], f[2]);
		q = dio_unhex(f[2], NULL, 0);
		items = dio_hex_list(f[0], &n);
		pool = calloc(n, sizeof(t_btree));
		root = plant(pool, items, f[1], n);
		g_query = q;
		res = btree_search_item(root, (void *)q, cmp_str);
		printf("%d\t", pool_index(pool, n, res));
		if (res)
			dio_puthex((unsigned char *)res, strlen((char *)res));
		else
			printf("NULL");
		putchar('\n');
		free(pool);
		dio_free_list(items, n);
		free(q);
	}
	free(line);
	return (0);
}
