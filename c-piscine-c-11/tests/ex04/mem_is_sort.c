/* Memory-safety probe for ft_is_sort — run under AddressSanitizer.
 * ft_is_sort compares adjacent elements of tab[0..length-1] via f and must
 * never read tab[length]; the classic slip is comparing tab[i] with tab[i+1]
 * for i up to length-1, which reads tab[length]. tab below is a heap block of
 * EXACTLY length ints, so a correct scan stops at tab[length-1] while that stray
 * read lands out of bounds and ASan aborts. Sorted data forces a full traversal
 * (no early exit); length 0 and 1 must not compare past the end. Test input. */
#include <stdlib.h>

int	ft_is_sort(int *tab, int length, int (*f)(int, int));

/* Ascending comparator: negative when a precedes b. */
static int	ascending(int a, int b)
{
	return (a - b);
}

/* Fills an exact-sized sorted heap block and checks it. */
static void	run(int length)
{
	int	*tab;
	int	i;

	tab = malloc(sizeof(int) * length);
	i = 0;
	while (i < length)
	{
		tab[i] = i;
		i++;
	}
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
