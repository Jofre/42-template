/* Memory-safety probe for ft_strlcpy — run under AddressSanitizer.
 * strlcpy writes at most `size` bytes into dest: up to size-1 copied chars plus
 * a terminating '\0', so dest[0..size-1] is the whole write window and index
 * size must never be touched. Each dest below is a HEAP buffer sized EXACTLY
 * `size`, so a correct strlcpy writes 0..size-1 and stops, while an off-by-one
 * that stores dest[size] (a copy loop bounded by size instead of size-1) hits a
 * heap-buffer-overflow that ASan flags. src is a normal NUL-terminated string
 * (strlcpy must strlen it), longer than size in the truncating cases. size 1
 * writes only the terminator dest[0]; size 0 must write nothing at all (dest is
 * a 0-byte block — any store is an overflow). This is a test input, not code. */
#include <stdlib.h>

unsigned int	ft_strlcpy(char *dest, char *src, unsigned int size);

int	main(void)
{
	char	*d4;
	char	*d6;
	char	*d1;
	char	*d0;

	d4 = malloc(4);
	d6 = malloc(6);
	d1 = malloc(1);
	d0 = malloc(0);
	ft_strlcpy(d4, "Hello", 4);
	ft_strlcpy(d6, "Hello", 6);
	ft_strlcpy(d1, "Hi", 1);
	ft_strlcpy(d0, "Hi", 0);
	free(d4);
	free(d6);
	free(d1);
	free(d0);
	return (0);
}
