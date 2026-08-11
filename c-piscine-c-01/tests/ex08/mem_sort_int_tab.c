/* Memory-safety probe for ft_sort_int_tab — run under AddressSanitizer.
 * ft_sort_int_tab sorts tab[0..size) ascending in place: every compare and swap
 * must stay within indices 0..size-1 and never reach index `size`. Each buffer
 * below is a HEAP block sized EXACTLY `size` ints (no slack) filled in DESCENDING
 * order so the sort actually compares and swaps across the whole range — a
 * correct sort stays in bounds, while any off-by-one that reads or writes
 * tab[size] runs past the block and ASan flags it. Sizes 1 and 0 are included;
 * with size 0 the array must not be dereferenced. A test input, not a solution.
 */
#include <stdlib.h>

void	ft_sort_int_tab(int *tab, int size);

static int	*fill_desc(int size)
{
	int	*tab;
	int	i;

	tab = malloc(sizeof(int) * size);
	i = 0;
	while (i < size)
	{
		tab[i] = size - i;
		i++;
	}
	return (tab);
}

int	main(void)
{
	int	*big;
	int	*one;
	int	*zero;

	big = fill_desc(5);
	one = fill_desc(1);
	zero = fill_desc(0);
	ft_sort_int_tab(big, 5);
	ft_sort_int_tab(one, 1);
	ft_sort_int_tab(zero, 0);
	free(big);
	free(one);
	free(zero);
	return (0);
}
