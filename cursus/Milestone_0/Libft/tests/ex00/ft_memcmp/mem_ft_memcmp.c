/* Memory-safety probe for ft_memcmp. Both blocks are heap blocks of exactly
 * n bytes, with nothing after their last byte, and they hold the same bytes
 * (a NUL in the middle): a correct comparison reads all n pairs and stops,
 * and a read of the byte after them, in either block, lands in a redzone.
 * n 0 is handed two blocks of 0 bytes, where any read at all is one.
 * libc's memcpy fills the input; the call under test is the ft_ one. A test
 * input, not code. */
#include <stdlib.h>
#include <string.h>

int	ft_memcmp(const void *s1, const void *s2, size_t n);

int	main(void)
{
	char	*a7;
	char	*b7;
	char	*a0;
	char	*b0;

	a7 = malloc(7);
	b7 = malloc(7);
	a0 = malloc(0);
	b0 = malloc(0);
	if (a7 && b7 && a0 && b0)
	{
		memcpy(a7, "ab\0c\xe9" "fg", 7);
		memcpy(b7, "ab\0c\xe9" "fg", 7);
		ft_memcmp(a7, b7, 7);
		ft_memcmp(a0, b0, 0);
	}
	free(a7);
	free(b7);
	free(a0);
	free(b0);
	return (0);
}
