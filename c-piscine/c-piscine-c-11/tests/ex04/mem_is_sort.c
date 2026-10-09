/* Memory-safety probe for ft_is_sort — run under AddressSanitizer.
 * ft_is_sort compares neighbouring elements via f and must never read past
 * the last one; the classic slip is reading one slot past the end while
 * comparing neighbours. tab below is a heap block of EXACTLY length ints, so
 * that stray read lands out of bounds and ASan aborts. Sorted data forces a
 * full traversal (no early exit); length 0 and 1 must not compare past the
 * end. Test input. */
#include <stdlib.h>
#include <string.h>

int	ft_is_sort(int *tab, int length, int (*f)(int, int));

/* Ascending comparator: negative when a precedes b. */
static int	ascending(int a, int b)
{
	return (a - b);
}

/* Copies sorted literal values into an exact-sized heap block and checks
 * it. */
static void	run(int length)
{
	static const int	vals[] = {0, 1, 2, 3, 4};
	int					*tab;

	tab = malloc(sizeof(int) * length);
	if (tab && length > 0)
		memcpy(tab, vals, sizeof(int) * length);
	ft_is_sort(tab, length, &ascending);
	free(tab);
}

int	main(void)
{
	run(0);
	run(1);
	run(5);
	return (0);
}
