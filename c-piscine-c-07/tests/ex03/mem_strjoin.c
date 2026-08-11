/* Memory-safety probe for ft_strjoin — run under AddressSanitizer.
 * ft_strjoin concatenates exactly `size` strings from the `strs` array, placing
 * `sep` between consecutive ones. It must read only strs[0 .. size-1] and never
 * strs[size]. Each array below is a HEAP block sized for EXACTLY `size` char
 * pointers, so a stray read of strs[size] (e.g. a `<= size` loop bound) lands
 * one element past the block and ASan reports a heap-buffer-overflow. size 1
 * never consults `sep`; size 0 must return an allocated empty string without
 * dereferencing strs at all. This is a test input, not an implementation. */
#include <stdlib.h>

char	*ft_strjoin(int size, char **strs, char *sep);

static char	**make(int size, char *fill)
{
	char	**strs;
	int		i;

	strs = malloc(sizeof(char *) * size);
	i = 0;
	while (i < size)
	{
		strs[i] = fill;
		i++;
	}
	return (strs);
}

int	main(void)
{
	char	**three;
	char	**one;
	char	**zero;
	char	*r;

	three = make(3, "ab");
	r = ft_strjoin(3, three, "-");
	free(r);
	free(three);
	one = make(1, "solo");
	r = ft_strjoin(1, one, "sep-ignored");
	free(r);
	free(one);
	zero = make(0, "x");
	r = ft_strjoin(0, zero, "-");
	free(r);
	free(zero);
	return (0);
}
