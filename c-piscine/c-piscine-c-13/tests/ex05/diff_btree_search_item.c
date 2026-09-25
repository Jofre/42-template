/* Live-differential reader harness for btree_search_item.
 * Line: <seq>\t<shape>\t<hexQuery>\t<hexFound|NULL>. seq = the items, comma-
 * joined hex; shape = where each one hangs ("-" the root, "3L" left of item 3).
 * Links the tree from those two, runs the student's btree_search_item with a
 * strcmp comparator, and reprints <seq>\t<shape>\t<hexQuery>\t then the found
 * item's bytes (hex) or NULL. See diffio.h. */
#include "diffio.h"
#include "ft_btree.h"

static int	cmp_str(void *a, void *b)
{
	return (strcmp((char *)a, (char *)b));
}

static int	decode_seq(char *field, char **items, int maxn)
{
	int		n;
	char	*p;
	char	*comma;

	n = 0;
	p = field;
	if (*p == '\0')
		return (0);
	while (*p && n < maxn)
	{
		comma = strchr(p, ',');
		if (comma)
			*comma = '\0';
		items[n++] = (char *)dio_unhex(p, NULL, 0);
		if (!comma)
			break ;
		p = comma + 1;
	}
	return (n);
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
	char			line[8192];
	char			*f[4];
	char			*items[64];
	unsigned char	*q;
	t_btree			*pool;
	t_btree			*root;
	void			*res;
	int				n;
	int				i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 4) < 3)
			continue ;
		printf("%s\t%s\t%s\t", f[0], f[1], f[2]);
		q = dio_unhex(f[2], NULL, 0);
		n = decode_seq(f[0], items, 64);
		pool = calloc(n, sizeof(t_btree));
		root = plant(pool, items, f[1], n);
		res = btree_search_item(root, (void *)q, cmp_str);
		if (res)
			dio_puthex((unsigned char *)res, strlen((char *)res));
		else
			printf("NULL");
		putchar('\n');
		free(pool);
		i = 0;
		while (i < n)
			free(items[i++]);
		free(q);
	}
	return (0);
}
