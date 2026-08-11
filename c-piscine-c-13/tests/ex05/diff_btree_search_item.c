/* Live-differential reader harness for btree_search_item.
 * Line: <seq>\t<hexQuery>\t<hexFound|NULL>. Builds the tree with a local strcmp
 * BST insert (lower left, equal-or-higher right), runs the student's
 * btree_search_item with the same strcmp comparator, and reprints
 * <seq>\t<hexQuery>\t then the found item's bytes (hex) or NULL. See diffio.h. */
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
	char			line[8192];
	char			*f[3];
	char			*items[64];
	unsigned char	*q;
	t_btree			*root;
	void			*res;
	int				n;
	int				i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		printf("%s\t%s\t", f[0], f[1]);
		q = dio_unhex(f[1], NULL, 0);
		n = decode_seq(f[0], items, 64);
		root = NULL;
		i = 0;
		while (i < n)
			loc_insert(&root, items[i++]);
		res = btree_search_item(root, (void *)q, cmp_str);
		if (res)
			put_hex_str((char *)res);
		else
			printf("NULL");
		putchar('\n');
		free_tree(root);
		i = 0;
		while (i < n)
			free(items[i++]);
		free(q);
	}
	return (0);
}
