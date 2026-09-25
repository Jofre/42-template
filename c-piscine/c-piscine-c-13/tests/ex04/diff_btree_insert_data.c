/* Live-differential reader harness for btree_insert_data.
 * Line: <seq>\t<paths>\t<found-csv>. seq = comma-joined lowercase-hex byte-
 * strings, inserted in order with a strcmp comparator ("" = empty tree). paths
 * = routes from the root, one letter per step (L left, R right, "." the root
 * itself): first where each inserted item must end up, in insertion order, then
 * every child slot that must stay EMPTY. Reprints <seq>\t<paths>\t then, per
 * route, what the student's tree holds at its end: the item's bytes (hex), or
 * NULL. A lost node reads NULL where an item was due; an extra one, an item
 * where NULL was due. Needs btree_create_node (linked via deps). See diffio.h. */
#include "diffio.h"
#include "ft_btree.h"

/* Routes per line: two per item plus one, for at most 64 items. */
#define MAX_FOUND 160

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

/* The node at the end of one route: a step per letter from the root, L down
 * the left link and R down the right, stopping as soon as a link is empty.
 * The routes are the reference's (oracle/src/c13.rs works out where each item
 * belongs), so this harness never chooses a way through the tree and holds no
 * traversal: it only goes and looks where it is told. */
static t_btree	*follow(t_btree *root, const char *route)
{
	while (root != NULL && *route != '\0' && *route != ',')
	{
		if (*route == 'L')
			root = root->left;
		else if (*route == 'R')
			root = root->right;
		route++;
	}
	return (root);
}

/* Every node seen at the end of a route, recorded once -- a tree gone wrong
 * can show one node at two routes -- so the nodes are freed from this array
 * rather than by walking the tree. A correct tree has all n of its nodes at
 * the first n routes, so all of them are found. */
static void	remember(t_btree **found, int *nfound, t_btree *node)
{
	int	i;

	if (node == NULL)
		return ;
	i = 0;
	while (i < *nfound)
		if (found[i++] == node)
			return ;
	if (*nfound < MAX_FOUND)
		found[(*nfound)++] = node;
}

static void	report(t_btree *root, char *routes, t_btree **found, int *nfound)
{
	t_btree	*node;
	char	*p;

	p = routes;
	while (p != NULL)
	{
		if (p != routes)
			putchar(',');
		node = follow(root, p);
		if (node)
			dio_puthex((unsigned char *)node->item,
				strlen((char *)node->item));
		else
			printf("NULL");
		remember(found, nfound, node);
		p = strchr(p, ',');
		if (p != NULL)
			p++;
	}
}

int	main(void)
{
	char	line[8192];
	char	*f[3];
	char	*items[64];
	t_btree	*found[MAX_FOUND];
	t_btree	*root;
	int		nfound;
	int		n;
	int		i;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 3) < 2)
			continue ;
		printf("%s\t%s\t", f[0], f[1]);
		n = decode_seq(f[0], items, 64);
		root = NULL;
		i = 0;
		while (i < n)
			btree_insert_data(&root, items[i++], cmp_str);
		nfound = 0;
		report(root, f[1], found, &nfound);
		putchar('\n');
		i = 0;
		while (i < nfound)
			free(found[i++]);
		i = 0;
		while (i < n)
			free(items[i++]);
	}
	return (0);
}
