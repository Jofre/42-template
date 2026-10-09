/* Memory-safety probe for ft_sort_int_tab — run under AddressSanitizer.
 * ft_sort_int_tab sorts tab[0..size) ascending in place: every compare and swap
 * must stay within indices 0..size-1 and never reach index `size`. Each buffer
 * below is a HEAP block sized EXACTLY `size` ints (no slack) filled in DESCENDING
 * order so the sort actually compares and swaps across the whole range — a
 * correct sort stays in bounds, while any off-by-one that reads or writes
 * tab[size] runs past the block and ASan flags it. Sizes 1 and 0 are included;
 * with size 0 the array must not be dereferenced. So are 300 and 5000, past
 * every capacity a copy on the stack is usually given (16, 64, 256, 1024,
 * 4096): the subject bounds no size (finding 041). A test input, not a solution.
 */
#include <stdlib.h>

void	ft_sort_int_tab(int *tab, int size);

static int	*fill_desc(int size)
{
	int	*tab;
	int	i;

	tab = malloc(sizeof(int) * size);
	i = 0;
	while (tab && i < size)
	{
		tab[i] = size - i;
		i++;
	}
	return (tab);
}

int	main(void)
{
	static const int	sizes[] = {5, 1, 0, 300, 5000};
	int					*tab;
	size_t				k;

	k = 0;
	while (k < sizeof(sizes) / sizeof(sizes[0]))
	{
		tab = fill_desc(sizes[k]);
		ft_sort_int_tab(tab, sizes[k]);
		free(tab);
		k++;
	}
	return (0);
}
