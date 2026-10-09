/* Memory-safety probe for ft_foreach — run under AddressSanitizer.
 * ft_foreach applies f to tab[0..length-1] and must never read tab[length].
 * Each tab below is a heap block sized EXACTLY length ints (no slack), so a
 * correct traversal touches only 0..length-1 while a stray read at index
 * length lands out of bounds and ASan aborts. length 0 must not dereference
 * tab at all. This is a test input, not an implementation. */
#include <stdlib.h>
#include <string.h>

void	ft_foreach(int *tab, int length, void (*f)(int));

/* Consumes one element; its body is irrelevant, the read happens in ft_foreach. */
static void	touch(int n)
{
	(void)n;
}

/* Copies literal values into an exact-sized heap block and runs ft_foreach
 * on it. */
static void	run(int length)
{
	static const int	vals[] = {0, 1, 2};
	int					*tab;

	tab = malloc(sizeof(int) * length);
	if (tab && length > 0)
		memcpy(tab, vals, sizeof(int) * length);
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
