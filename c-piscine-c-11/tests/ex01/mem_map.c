/* Memory-safety probe for ft_map — run under AddressSanitizer.
 * ft_map reads tab[0..length-1], allocates a new array and returns it; it must
 * never read tab[length]. Each tab below is a heap block sized EXACTLY length
 * ints, so a correct map touches only 0..length-1 while a read at index length
 * is out of bounds and ASan aborts. The returned array is freed so LeakSanitizer
 * stays quiet. length 0 must not dereference tab. Test input, not a solution. */
#include <stdlib.h>

int	*ft_map(int *tab, int length, int (*f)(int));

/* Maps each value to its double. */
static int	twice(int n)
{
	return (n * 2);
}

/* Fills an exact-sized heap block, maps it and frees both arrays. */
static void	run(int length)
{
	int	*tab;
	int	*res;
	int	i;

	tab = malloc(sizeof(int) * length);
	i = 0;
	while (i < length)
	{
		tab[i] = i;
		i++;
	}
	res = ft_map(tab, length, &twice);
	free(res);
	free(tab);
}

int	main(void)
{
	run(0);
	run(1);
	run(4);
	return (0);
}
