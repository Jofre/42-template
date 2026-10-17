/* Memory-safety probe for ft_memchr. Each block is a heap block of exactly
 * n bytes, with nothing after its last byte, and c is in none of them (a NUL
 * in the middle of one): a correct search reads all n bytes and stops, and
 * a read of the byte after them lands in a redzone. n 0 is handed a block of
 * 0 bytes, where any read at all is one. libc's memcpy fills the input;
 * the call under test is the ft_ one. A test input, not code. */
#include <stdlib.h>
#include <string.h>

void	*ft_memchr(const void *s, int c, size_t n);

int	main(void)
{
	char	*b7;
	char	*b0;

	b7 = malloc(7);
	b0 = malloc(0);
	if (b7 && b0)
	{
		memcpy(b7, "ab\0c\xe9" "fg", 7);
		ft_memchr(b7, 'z', 7);
		ft_memchr(b7, 0x80, 7);
		ft_memchr(b0, 'a', 0);
	}
	free(b7);
	free(b0);
	return (0);
}
