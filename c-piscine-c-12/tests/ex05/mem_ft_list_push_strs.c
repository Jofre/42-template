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

static void	free_list(t_list *begin)
{
	t_list	*tmp;

	while (begin != NULL)
	{
		tmp = begin;
		begin = begin->next;
		free(tmp);
	}
}

static void	call_case(int size)
{
	char	**strs;
	t_list	*begin;

	strs = make_strs(size);
	begin = ft_list_push_strs(size, strs);
	free_list(begin);
	free(strs);
}

int	main(void)
{
	call_case(3);
	call_case(1);
	call_case(0);
	return (0);
}
