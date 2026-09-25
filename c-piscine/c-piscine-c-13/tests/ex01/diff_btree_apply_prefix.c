/* Live-differential reader harness for btree_apply_prefix.
 * Line: <seq>\t<shape>\t<prefix-hex-csv>. seq = the items, comma-joined hex;
 * shape = where each one hangs ("-" the root, "3L" left of item 3). Links the
 * tree from those two, reprints <seq>\t<shape>\t then drives the student's
 * btree_apply_prefix with a fixed applyf that emits each item's bytes as
 * lowercase hex, comma-separated. See tools/diffio.h. */
#include "diffio.h"
#include "ft_btree.h"

static int	g_first;

static void	apply_print(void *item)
{
	if (!g_first)
		putchar(',');
	g_first = 0;
	dio_puthex((unsigned char *)item, strlen((char *)item));
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
	char	line[8192];
	char	*f[3];
	char	*items[64];
	t_btree	*pool;
	t_btree	*root;
	int		n;
	int		i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		printf("%s\t%s\t", f[0], f[1]);
		n = decode_seq(f[0], items, 64);
		pool = calloc(n, sizeof(t_btree));
		root = plant(pool, items, f[1], n);
		g_first = 1;
		btree_apply_prefix(root, apply_print);
		putchar('\n');
		free(pool);
		i = 0;
		while (i < n)
			free(items[i++]);
	}
	return (0);
}
