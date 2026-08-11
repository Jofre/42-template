/* Live-differential reader harness for btree_create_node.
 * Line: <hexItem>\t<hexItem>\tNULL\tNULL. Decodes the item, creates a node,
 * reprints <hexItem>\t then the stored item's bytes (hex), whether each child
 * is NULL, and a trailing 1/0 for "node->item is the SAME pointer we passed in"
 * (a correct create_node stores the pointer, it does not copy the bytes).
 * Items never contain 0x00. See tools/diffio.h. */
#include "diffio.h"
#include "ft_btree.h"

static void	put_item_hex(const char *s)
{
	const char	*hex = "0123456789abcdef";

	while (*s)
	{
		putchar(hex[(unsigned char)*s >> 4]);
		putchar(hex[(unsigned char)*s & 15]);
		s++;
	}
}

int	main(void)
{
	char			line[8192];
	char			*f[4];
	unsigned char	*item;
	t_btree			*node;

	while (dio_line(line, sizeof(line)))
	{
		if (dio_split(line, f, 4) < 1)
			continue ;
		item = dio_unhex(f[0], NULL, 0);
		node = btree_create_node((void *)item);
		if (node == NULL)
		{
			printf("%s\tNULLNODE\n", f[0]);
			free(item);
			continue ;
		}
		printf("%s\t", f[0]);
		put_item_hex((char *)node->item);
		printf("\t%s\t%s\t%d\n", node->left ? "SET" : "NULL",
			node->right ? "SET" : "NULL", node->item == (void *)item);
		free(node);
		free(item);
	}
	return (0);
}
