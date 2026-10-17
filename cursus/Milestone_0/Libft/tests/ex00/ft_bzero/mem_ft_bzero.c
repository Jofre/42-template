/* Memory-safety probe for ft_bzero. Each call's n bytes from s end at its
 * heap block's last byte, so a write past the n-th byte lands in the redzone
 * after the block. In b7 and b1, s is the block's first byte too, so a write
 * before s lands in the redzone before it; b8 + 3 has three bytes of its own
 * block before s, which no checker sees written, so it guards the far end
 * only. n 0 is handed a block of 0 bytes, where any write at all is one. A
 * test input, not code. */
#include <stdlib.h>

void	ft_bzero(void *s, size_t n);

int	main(void)
{
	char	*b7;
	char	*b8;
	char	*b1;
	char	*b0;

	b7 = malloc(7);
	b8 = malloc(8);
	b1 = malloc(1);
	b0 = malloc(0);
	if (b7 && b8 && b1 && b0)
	{
		ft_bzero(b7, 7);
		ft_bzero(b8 + 3, 5);
		ft_bzero(b1, 1);
		ft_bzero(b0, 0);
	}
	free(b7);
	free(b8);
	free(b1);
	free(b0);
	return (0);
}
