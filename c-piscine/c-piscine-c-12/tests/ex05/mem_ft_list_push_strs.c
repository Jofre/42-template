/* Memory-safety probe for ft_list_push_strs — run under AddressSanitizer.
 * ft_list_push_strs(size, strs) builds a list from the FIRST `size` strings of
 * strs, so a correct version reads only strs[0..size-1], never strs[size].
 * Each strs below is a HEAP block of EXACTLY `size` char * (no slack), so a
 * read at index == size is a guaranteed heap-buffer-overflow that ASan flags,
 * while a correct version returns a list we then free. Sizes 0 and 1 are
 * exercised too: with size 0 the array is a 0-byte block, never dereferenced.
 * This is a test input, not an implementation. */
#include "ft_list.h"
#include <stdlib.h>

static char	**make_strs(int size)
{
	static char	*words[3] = {"one", "two", "three"};
	char		**strs;
	int			i;

	strs = malloc(sizeof(char *) * (size_t)size);
	i = 0;
	while (i < size)
	{
		strs[i] = words[i % 3];
		i++;
	}
	return (strs);
}

/* Free the list the function returned, reading at most `cap` nodes: the size
 * it was asked for, plus one. Every node is recorded before any is freed, so
 * nothing is read after it has been released. The record is deliberately NOT
 * de-duplicated: a list that loops back on itself records a node twice, and
 * the double free that follows is a report this probe should raise. */
static void	free_list(t_list *begin, int cap)
{
	t_list	*seen[4];
	int		k;
	int		i;

	k = 0;
	while (begin != NULL && k < cap)
	{
		seen[k++] = begin;
		begin = begin->next;
	}
	i = 0;
	while (i < k)
		free(seen[i++]);
}

static void	call_case(int size)
{
	char	**strs;
	t_list	*begin;

	strs = make_strs(size);
	begin = ft_list_push_strs(size, strs);
	free_list(begin, size + 1);
	free(strs);
}

int	main(void)
{
	call_case(3);
	call_case(1);
	call_case(0);
	return (0);
}
