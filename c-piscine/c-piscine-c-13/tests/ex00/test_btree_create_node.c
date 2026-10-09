#include "ft_btree.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int	main(void)
{
	char	*item;
	int		num;
	t_btree	*node;
	t_btree	*nnode;
	t_btree	*inode;
	t_btree	*dnode;
	void	*junk[32];
	void	*drain[7];
	int		i;

	item = "hello";
	num = 42;
	node = btree_create_node(item);
	if (node == NULL)
	{
		printf("node is NULL\n");
		return (0);
	}
	printf("item: %s\n", (char *)node->item);
	printf("left: %s\n", node->left ? "set" : "NULL");
	printf("right: %s\n", node->right ? "set" : "NULL");
	/* Each result is checked before it is read. The first one was, and the
	 * next three were not -- so a btree_create_node that returns NULL for
	 * some input (rejecting a NULL item is a reading someone will try) died
	 * here with a SEGV instead of printing the row that names the case. A
	 * crash is the least informative way this layer can fail, and it is the
	 * harness choosing it rather than the deliverable. */
	nnode = btree_create_node(NULL);
	if (nnode == NULL)
		printf("null node is NULL\n");
	else
	{
		printf("null item: %s\n", nnode->item == NULL ? "NULL" : "set");
		printf("null left: %s\n", nnode->left ? "set" : "NULL");
		printf("null right: %s\n", nnode->right ? "set" : "NULL");
	}
	inode = btree_create_node(&num);
	if (inode == NULL)
		printf("int node is NULL\n");
	else
	{
		printf("int item: %d\n", *(int *)inode->item);
		printf("int left: %s\n", inode->left ? "set" : "NULL");
		printf("int right: %s\n", inode->right ? "set" : "NULL");
	}
	free(node);
	free(nnode);
	free(inode);
	i = 0;
	while (i < 32)
	{
		junk[i] = malloc(sizeof(t_btree));
		memset(junk[i], 0xFF, sizeof(t_btree));
		i++;
	}
	i = 0;
	while (i < 32)
		free(junk[i++]);
	i = 0;
	while (i < 7)
		drain[i++] = malloc(sizeof(t_btree));
	dnode = btree_create_node("dirt");
	if (dnode == NULL)
		printf("dirty node is NULL\n");
	else
	{
		printf("dirty item: %s\n", (char *)dnode->item);
		printf("dirty left: %s\n", dnode->left ? "set" : "NULL");
		printf("dirty right: %s\n", dnode->right ? "set" : "NULL");
	}
	i = 0;
	while (i < 7)
		free(drain[i++]);
	free(dnode);
	return (0);
}
