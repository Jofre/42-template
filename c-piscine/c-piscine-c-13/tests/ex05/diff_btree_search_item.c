/* Live-differential reader harness for btree_search_item.
 * Line: <seq>\t<shape>\t<hexQuery>\t<hexFound|NULL>. seq = the items, comma-
 * joined hex; shape = where each one hangs ("-" the root, "3L" left of item 3).
 * Links the tree from those two, runs the student's btree_search_item with a
 * strcmp comparator that answers "no match" to a call not handing it the
 * query (in either place), and reprints <seq>\t<shape>\t<hexQuery>\t then the found
 * item's bytes (hex) or NULL. See diffio.h. */
#include "diffio.h"
#include "ft_btree.h"

/* The query this case passes. Either argument may be it -- the subject
 * fixes no order for cmpf's two (WP-46's decision) -- but one of them must
 * be: a call that hands cmpf something else (a node, the same item twice) is
 * answered "no match" without reading it, so a search that never hands over
 * data_ref finds nothing and the record diverges. */
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
 * by the reference (oracle/src/c13.rs), which keeps this harness free of any
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
		if (dio_split(line, f, 4) < 3)
			continue ;
		printf("%s\t%s\t%s\t", f[0], f[1], f[2]);
		q = dio_unhex(f[2], NULL, 0);
		items = dio_hex_list(f[0], &n);
		pool = calloc(n, sizeof(t_btree));
		root = plant(pool, items, f[1], n);
		g_query = q;
		res = btree_search_item(root, (void *)q, cmp_str);
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
