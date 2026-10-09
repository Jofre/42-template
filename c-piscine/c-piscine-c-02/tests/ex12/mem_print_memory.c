/* Memory-safety probe for ft_print_memory — run under AddressSanitizer.
 * print_memory reads exactly `size` bytes starting at addr and dumps them as a
 * hex + ascii table (16 bytes per row). addr[0..size-1] is the whole read
 * window; index size must never be touched. Each block below is a HEAP buffer
 * sized EXACTLY `size`, so a correct dump reads 0..size-1 and stops, while an
 * off-by-one that reads addr[size] (a row/ascii loop scanning one slot too far,
 * e.g. counting a full 16-byte row on a short final line) hits a
 * heap-buffer-overflow that ASan flags. Sizes cover a partial row (5), a full
 * row (16) and a full-plus-partial (17); size 1 reads only addr[0]; size 0 must
 * read nothing (0-byte block — any load is an overflow). fill() initialises the
 * bytes in-bounds so the dump is not reading indeterminate memory. This is a
 * test input, not an implementation. */
#include <stdlib.h>

void	*ft_print_memory(void *addr, unsigned int size);

static void	fill(unsigned char *p, unsigned int n)
{
	unsigned int	i;

	i = 0;
	while (i < n)
	{
		p[i] = (unsigned char)i;
		i++;
	}
}

int	main(void)
{
	unsigned char	*b1;
	unsigned char	*b5;
	unsigned char	*b16;
	unsigned char	*b17;
	unsigned char	*b0;

	b1 = malloc(1);
	b5 = malloc(5);
	b16 = malloc(16);
	b17 = malloc(17);
	b0 = malloc(0);
	fill(b1, 1);
	fill(b5, 5);
	fill(b16, 16);
	fill(b17, 17);
	ft_print_memory(b1, 1);
	ft_print_memory(b5, 5);
	ft_print_memory(b16, 16);
	ft_print_memory(b17, 17);
	ft_print_memory(b0, 0);
	free(b1);
	free(b5);
	free(b16);
	free(b17);
	free(b0);
	return (0);
}
