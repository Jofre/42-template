/* Memory-safety probe for ft_ultimate_range — run under AddressSanitizer.
 * ft_ultimate_range allocates an array of exactly (max - min) ints, stores it
 * through *range, fills it with min .. max - 1 and returns the length. It must
 * write only indices 0 .. (max - min - 1) into its own block. ASan watches that
 * block: a `<= n` fill loop writes one int past the end and is reported as a
 * heap-buffer-overflow. The size-1 range (7, 8) leaves no room for slack; the
 * empty (5, 5) and reversed (5, 2) ranges must allocate nothing, leave *range
 * NULL and return 0 without writing. This is a test input, not a solution. */
#include <stdlib.h>

int	ft_ultimate_range(int **range, int min, int max);

int	main(void)
{
	int				*arr;
	volatile int	len;

	arr = NULL;
	len = ft_ultimate_range(&arr, -3, 3);
	free(arr);
	arr = NULL;
	len = ft_ultimate_range(&arr, 7, 8);
	free(arr);
	arr = NULL;
	len = ft_ultimate_range(&arr, 5, 5);
	free(arr);
	arr = NULL;
	len = ft_ultimate_range(&arr, 5, 2);
	free(arr);
	(void)len;
	return (0);
}
