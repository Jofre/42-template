/* Memory-safety probe for ft_rev_int_tab — run under AddressSanitizer.
 * ft_rev_int_tab reverses tab[0..size) in place: it must read and write only
 * indices 0..size-1 and never touch index `size`. Each buffer below is a HEAP
 * block sized EXACTLY `size` ints (no slack), so a correct reversal stays in
 * bounds — while any off-by-one that reads or writes tab[size] runs past the
 * block and ASan flags it. Sizes 1 and 0 are included; with size 0 the array
 * must not be dereferenced at all. This is a test input, not an implementation.
 */
#include <stdlib.h>
#include <string.h>

void	ft_rev_int_tab(int *tab, int size);

/* An exact-size heap block holding the first `size` literal values below. */
static int	*fill(int size)
{
	static const int	vals[] = {0, 1, 2, 3};
	int					*tab;

	tab = malloc(sizeof(int) * size);
	if (tab && size > 0)
		memcpy(tab, vals, sizeof(int) * size);
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
