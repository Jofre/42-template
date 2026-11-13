/* Memory-safety probe for ft_memmove. One heap block of exactly 8 bytes,
 * with nothing on either side of it: 6 bytes moved two places up inside it,
 * then two places down, then onto themselves, so every byte the calls read
 * or write is in the block and a step outside it, at either end, lands in
 * a redzone. n 0 is handed a block of 0 bytes, where any access at all is
 * one. libc's memcpy fills the input; the call under test is the ft_ one.
 * A test input, not code. */
#include <stdlib.h>
#include <string.h>

void	*ft_memmove(void *dest, const void *src, size_t n);

int	main(void)
{
	char	*b8;
	char	*b0;

	b8 = malloc(8);
	b0 = malloc(0);
	if (b8 && b0)
	{
		memcpy(b8, "ab\0c\xe9" "fgh", 8);
		ft_memmove(b8 + 2, b8, 6);
		ft_memmove(b8, b8 + 2, 6);
		ft_memmove(b8, b8, 8);
		ft_memmove(b0, b0, 0);
	}
	free(b8);
	free(b0);
	return (0);
}
