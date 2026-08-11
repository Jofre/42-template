/* Memory-safety probe for ft_foreach — run under AddressSanitizer.
 * ft_foreach applies f to tab[0..length-1] and must never read tab[length].
 * Each tab below is a heap block sized EXACTLY length ints (no slack), so a
 * correct traversal touches only 0..length-1 while a stray read at index
 * length lands out of bounds and ASan aborts. length 0 must not dereference
 * tab at all. This is a test input, not an implementation. */
#include <stdlib.h>

void	ft_foreach(int *tab, int length, void (*f)(int));

/* Consumes one element; its body is irrelevant, the read happens in ft_foreach. */
static void	touch(int n)
{
	(void)n;
}

/* Fills an exact-sized heap block 0..length-1 and runs ft_foreach on it. */
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
	ft_foreach(tab, length, &touch);
	free(tab);
}

int	main(void)
{
	run(0);
	run(1);
	run(3);
	return (0);
}
