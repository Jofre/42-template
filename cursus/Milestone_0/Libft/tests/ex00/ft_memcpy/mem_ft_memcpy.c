/* Memory-safety probe for ft_memcpy. src and dest are separate heap blocks
 * of exactly n bytes each, with nothing after their last byte: a read past
 * src's n-th byte, or a write past dest's, lands in a redzone. n 0 is handed
 * two blocks of 0 bytes, where any access at all is one. src holds a NUL
 * in the middle, which must not stop the copy. libc's memcpy fills the
 * input; the call under test is the ft_ one. A test input, not code. */
#include <stdlib.h>
#include <string.h>

void	*ft_memcpy(void *dest, const void *src, size_t n);

int	main(void)
{
	char	*s7;
	char	*d7;
	char	*s0;
	char	*d0;

	s7 = malloc(7);
	d7 = malloc(7);
	s0 = malloc(0);
	d0 = malloc(0);
	if (s7 && d7 && s0 && d0)
	{
		memcpy(s7, "ab\0c\xe9" "fg", 7);
		ft_memcpy(d7, s7, 7);
		ft_memcpy(d0, s0, 0);
	}
	free(s7);
	free(d7);
	free(s0);
	free(d0);
	return (0);
}
