/* Live-differential reader harness for btree_insert_data.
 * Line: <seq>\t<infix-hex-csv>\t<prefix-hex-csv>. seq = comma-joined lowercase-
 * hex byte-strings ("" = empty tree). BST-inserts every string with strcmp
 * (lower left, equal-or-higher right), then reprints <seq>\t the infix (sorted)
 * traversal and \t the prefix (pre-order) traversal, both comma-joined hex. The
 * prefix column is SHAPE-sensitive: infix alone is the sorted multiset and so
 * cannot see where equal keys land, but pre-order exposes the equal-goes-right
 * rule. Both are walked locally over the struct (no dependence on the student's
 * apply_prefix). Needs btree_create_node (linked via deps). See diffio.h. */
#include "diffio.h"
#include "ft_btree.h"

static int	cmp_str(void *a, void *b)
{
	return (strcmp((char *)a, (char *)b));
}

static void	put_hex_str(const char *s)
{
	const char	*hex = "0123456789abcdef";

	while (*s)
	{
		putchar(hex[(unsigned char)*s >> 4]);
		putchar(hex[(unsigned char)*s & 15]);
		s++;
	}
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

static void	free_tree(t_btree *root)
{
	if (root == NULL)
		return ;
	free_tree(root->left);
	free_tree(root->right);
	free(root);
}

static void	infix_collect(t_btree *r, int *first)
{
	if (r == NULL)
		return ;
	infix_collect(r->left, first);
	if (!*first)
		putchar(',');
	*first = 0;
	put_hex_str((char *)r->item);
	infix_collect(r->right, first);
}

static void	prefix_collect(t_btree *r, int *first)
{
	if (r == NULL)
		return ;
	if (!*first)
		putchar(',');
	*first = 0;
	put_hex_str((char *)r->item);
	prefix_collect(r->left, first);
	prefix_collect(r->right, first);
}

int	main(void)
{
	char	line[8192];
	char	*f[2];
	char	*items[64];
	t_btree	*root;
	int		n;
	int		i;
	int		first;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		printf("%s\t", f[0]);
		n = decode_seq(f[0], items, 64);
		root = NULL;
		i = 0;
		while (i < n)
			btree_insert_data(&root, items[i++], cmp_str);
		first = 1;
		infix_collect(root, &first);
		putchar('\t');
		first = 1;
		prefix_collect(root, &first);
		putchar('\n');
		free_tree(root);
		i = 0;
		while (i < n)
			free(items[i++]);
	}
	return (0);
}
