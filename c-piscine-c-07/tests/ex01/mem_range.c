/* Memory-safety probe for ft_range — run under AddressSanitizer.
 * ft_range allocates an array of exactly (max - min) ints and fills it with
 * min .. max - 1, so it must write only indices 0 .. (max - min - 1) into its
 * own block. ASan watches that block: a `<= n` fill loop writes one int past the
 * end and is reported as a heap-buffer-overflow. The size-1 range (7, 8) leaves
 * no room for slack; the empty (5, 5) and reversed (5, 2) ranges must allocate
 * nothing and return NULL without writing at all. This is a test input, not an
 * implementation. */
#include <stdlib.h>

int	*ft_range(int min, int max);

int	main(void)
{
	int	*r;

	r = ft_range(-3, 3);
	free(r);
	r = ft_range(7, 8);
	free(r);
	r = ft_range(5, 5);
	free(r);
	r = ft_range(5, 2);
	free(r);
	return (0);
}
