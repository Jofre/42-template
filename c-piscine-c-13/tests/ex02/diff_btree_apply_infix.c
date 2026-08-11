/* Live-differential reader harness for btree_apply_infix.
 * Line: <seq>\t<infix-hex-csv>. Builds the tree with a local strcmp BST
 * insert (lower left, equal-or-higher right), reprints <seq>\t then drives the
 * student's btree_apply_infix with a fixed applyf that emits each item's
 * bytes as lowercase hex, comma-separated. See tools/diffio.h. */
#include "diffio.h"
#include "ft_btree.h"

static int	g_first;

static void	apply_print(void *item)
{
	const char	*hex = "0123456789abcdef";
	const char	*s = (const char *)item;

	if (!g_first)
		putchar(',');
	g_first = 0;
	while (*s)
	{
		putchar(hex[(unsigned char)*s >> 4]);
		putchar(hex[(unsigned char)*s & 15]);
		s++;
	}
}

static t_btree	*new_node(void *item)
{
	t_btree	*node;

	node = malloc(sizeof(t_btree));
	node->item = item;
	node->left = NULL;
	node->right = NULL;
	return (node);
}

static void	loc_insert(t_btree **root, void *item)
{
	if (*root == NULL)
	{
		*root = new_node(item);
		return ;
	}
	if (strcmp((char *)item, (char *)(*root)->item) < 0)
		loc_insert(&(*root)->left, item);
	else
		loc_insert(&(*root)->right, item);
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

int	main(void)
{
	char	line[8192];
	char	*f[2];
	char	*items[64];
	t_btree	*root;
	int		n;
	int		i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 2) < 1)
			continue ;
		printf("%s\t", f[0]);
		n = decode_seq(f[0], items, 64);
		root = NULL;
		i = 0;
		while (i < n)
			loc_insert(&root, items[i++]);
		g_first = 1;
		btree_apply_infix(root, apply_print);
		putchar('\n');
		free_tree(root);
		i = 0;
		while (i < n)
			free(items[i++]);
	}
	return (0);
}
