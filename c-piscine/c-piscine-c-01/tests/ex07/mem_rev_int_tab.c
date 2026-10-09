/* Memory-safety probe for ft_rev_int_tab — run under AddressSanitizer.
 * ft_rev_int_tab reverses tab[0..size) in place: it must read and write only
 * indices 0..size-1 and never touch index `size`. Each buffer below is a HEAP
 * block sized EXACTLY `size` ints (no slack), so a correct reversal stays in
 * bounds — while any off-by-one that reads or writes tab[size] runs past the
 * block and ASan flags it. Sizes 1 and 0 are included; with size 0 the array
 * must not be dereferenced at all. So are 300 and 5000, past every capacity a
 * copy on the stack is usually given (16, 64, 256, 1024, 4096): the subject
 * bounds no size, and a function that works through such a copy writes past
 * its end there (finding 041). This is a test input, not an implementation.
 *
 * THE VALUES ARE NO SIZE. Filled with 0, 1, 2 ..., a copy into a 16-int local
 * array stopped itself under memcheck: the 18th store landed on the function's
 * own `size`, wrote 17 there, and the loop ended inside the frame, where
 * memcheck sees nothing (the mutation run of 2026-10-03). Filled with values
 * near INT_MAX instead, a store that lands on a count makes it a count no loop
 * reaches, and the overrun goes on out of the frame, where memcheck sees it.
 * That depends on where the compiler put the array; the ASan layers see a
 * stack overrun wherever it lands.
 */
#include <limits.h>
#include <stdlib.h>

void	ft_rev_int_tab(int *tab, int size);

/* An exact-size heap block holding INT_MAX, INT_MAX - 1 ... down to
 * INT_MAX - (size - 1): distinct, so a reversal shows, and none a size. */
static int	*fill(int size)
{
	int	*tab;
	int	i;

	tab = malloc(sizeof(int) * size);
	i = 0;
	while (tab && i < size)
	{
		tab[i] = INT_MAX - i;
		i++;
	}
	return (tab);
}

int	main(void)
{
	static const int	sizes[] = {4, 1, 0, 300, 5000};
	int					*tab;
	size_t				k;

	k = 0;
	while (k < sizeof(sizes) / sizeof(sizes[0]))
	{
		tab = fill(sizes[k]);
		ft_rev_int_tab(tab, sizes[k]);
		free(tab);
		k++;
	}
	return (0);
}
