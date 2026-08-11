/* Memory-safety probe for ft_rev_int_tab — run under AddressSanitizer.
 * ft_rev_int_tab reverses tab[0..size) in place: it must read and write only
 * indices 0..size-1 and never touch index `size`. Each buffer below is a HEAP
 * block sized EXACTLY `size` ints (no slack), so a correct reversal stays in
 * bounds — while any off-by-one that reads or writes tab[size] runs past the
 * block and ASan flags it. Sizes 1 and 0 are included; with size 0 the array
 * must not be dereferenced at all. This is a test input, not an implementation.
 */
#include <stdlib.h>

void	ft_rev_int_tab(int *tab, int size);

static int	*fill(int size)
{
	int	*tab;
	int	i;

	tab = malloc(sizeof(int) * size);
	i = 0;
	while (i < size)
	{
		tab[i] = i;
		i++;
	}
	return (tab);
}

int	main(void)
{
	int	*big;
	int	*one;
	int	*zero;

	big = fill(4);
	one = fill(1);
	zero = fill(0);
	ft_rev_int_tab(big, 4);
	ft_rev_int_tab(one, 1);
	ft_rev_int_tab(zero, 0);
	free(big);
	free(one);
	free(zero);
	return (0);
}
