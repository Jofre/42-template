/* Memory-safety probe for ft_list_find — run under AddressSanitizer.
 * ft_list_find walks a list comparing each element's data against data_ref with
 * the caller's cmp, and stops at the first match. The two things a walk can get
 * wrong are both invisible to output diffing when the answer happens to be
 * right: stepping PAST the terminating NULL, and reading the data pointer of a
 * node it has already gone past.
 * Every node below is its own heap block and every data is a heap block of
 * EXACTLY the bytes it holds, so a read one step beyond either lands in a
 * redzone rather than on a live neighbour. The searched-for value is absent in
 * one case on purpose: that is the run which walks the whole list and so is the
 * one that steps off the end if the stop condition is wrong.
 * This is a test input, not an implementation. */
#include "ft_list.h"
#include <stdlib.h>
#include <string.h>

static int	cmp_str(char *a, char *b)
{
	return (strcmp(a, b));
}

/* The probe's list, built by construction: node i holds an exactly-sized
 * strdup'd copy of words[i] and is linked to node i + 1 by index; calloc
 * leaves the last node's next NULL. Each node is its own calloc'd block. The
 * pointers stay in `node`, and everything is freed from there afterwards,
 * without walking the list again. */
static void	build(t_list **node, char **words, int n)
{
	int	i;

	i = 0;
	while (i < n)
	{
		node[i] = calloc(1, sizeof(t_list));
		node[i]->data = strdup(words[i]);
		i++;
	}
	i = 0;
	while (i + 1 < n)
	{
		node[i]->next = node[i + 1];
		i++;
	}
}

int	main(void)
{
	char	*words[3];
	t_list	*node[3];
	char	*want;
	int		i;

	words[0] = "one";
	words[1] = "two";
	words[2] = "three";
	build(node, words, 3);
	want = malloc(4);
	memcpy(want, "two", 4);
	ft_list_find(node[0], want, (int (*)())cmp_str);
	free(want);
	/* Absent on purpose: this walk reaches the end of the list. */
	want = malloc(5);
	memcpy(want, "nope", 5);
	ft_list_find(node[0], want, (int (*)())cmp_str);
	free(want);
	i = 0;
	while (i < 3)
	{
		free(node[i]->data);
		free(node[i]);
		i++;
	}
	/* An empty list must be answered without dereferencing anything. */
	want = malloc(2);
	memcpy(want, "x", 2);
	ft_list_find(NULL, want, (int (*)())cmp_str);
	free(want);
	return (0);
}
