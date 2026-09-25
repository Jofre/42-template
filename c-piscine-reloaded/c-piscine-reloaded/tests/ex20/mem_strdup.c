/* Memory-safety probe for ft_strdup — run under AddressSanitizer.
 * Each `src` below is a HEAP block with no slack at all: "a" is a 2-byte block
 * holding 'a' and the terminator, and the empty string is a 1-byte block
 * holding only the terminator. Both are filled in by hand, byte by byte. Any
 * read past the terminator lands outside the block, and ASan reports a
 * heap-buffer-overflow. ASan likewise flags ft_strdup if its own block is too
 * small for what it writes into it. This is a test input, not an
 * implementation. */
#include <stdlib.h>

char	*ft_strdup(char *src);

int	main(void)
{
	char	*src;
	char	*empty;
	char	*dup;

	src = malloc(2);
	if (!src)
		return (1);
	src[0] = 'a';
	src[1] = '\0';
	dup = ft_strdup(src);
	free(dup);
	free(src);
	empty = malloc(1);
	if (!empty)
		return (1);
	empty[0] = '\0';
	dup = ft_strdup(empty);
	free(dup);
	free(empty);
	return (0);
}
