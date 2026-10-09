#include "ft_list.h"
#include <stdio.h>
#include <stdlib.h>

/* Prints "<label>\t<value>" so tools/diff_output.sh (run with --labeled) can
 * show each row in its own column. Every label names the property its row
 * checks -- "next is NULL", "data is the pointer passed" -- and the value is
 * "yes" or "no", or the string the element holds. When the call returns NULL
 * there is no element to look at, and each of that call's rows says so
 * instead of disappearing, so the table keeps its shape. */
static void	yes_no(char *call, char *what, int holds)
{
	if (holds)
		printf("%s: %s\tyes\n", call, what);
	else
		printf("%s: %s\tno\n", call, what);
}

static void	none(char *call, char *what)
{
	printf("%s: %s\t(NULL returned, no element)\n", call, what);
}

int	main(void)
{
	t_list	*elem;
	int		x;

	x = 42;
	elem = ft_create_elem("forty-two");
	if (elem == NULL)
	{
		none("string", "data");
		none("string", "next is NULL");
	}
	else
	{
		printf("string: data\t%s\n", (char *)elem->data);
		yes_no("string", "next is NULL", elem->next == NULL);
		free(elem);
	}
	elem = ft_create_elem(&x);
	if (elem == NULL)
	{
		none("int pointer", "data is the pointer passed");
		none("int pointer", "next is NULL");
	}
	else
	{
		yes_no("int pointer", "data is the pointer passed",
			elem->data == (void *)&x);
		yes_no("int pointer", "next is NULL", elem->next == NULL);
		free(elem);
	}
	elem = ft_create_elem(NULL);
	if (elem == NULL)
	{
		none("NULL data", "data is NULL");
		none("NULL data", "next is NULL");
	}
	else
	{
		yes_no("NULL data", "data is NULL", elem->data == NULL);
		yes_no("NULL data", "next is NULL", elem->next == NULL);
		free(elem);
	}
	return (0);
}
