/* Memory-safety probe for ft_strcpy — run under AddressSanitizer.
 * strcpy WRITES dest, copying every byte of src plus the terminating NUL. The
 * dest below is a HEAP buffer of EXACTLY strlen(src) + 1 bytes, so a correct
 * strcpy fills dest[0..len] and stops, while any off-by-one (an extra copy, or
 * a terminator stored one slot too far) writes dest[len + 1] — one past the
 * buffer — which ASan flags as a heap-buffer-overflow. src is a heap block of
 * EXACTLY len + 1 bytes (NUL-terminated) so a stray over-read of src is caught
 * too. Cases cover the empty string and length 1. This is a test, not a
 * solution. */
#include <stdlib.h>

char	*ft_strcpy(char *dest, char *src);

int	main(void)
{
	char	*dest;
	char	*src;

	src = malloc(6);
	src[0] = 'H';
	src[1] = 'e';
	src[2] = 'l';
	src[3] = 'l';
	src[4] = 'o';
	src[5] = '\0';
	dest = malloc(6);
	ft_strcpy(dest, src);
	free(src);
	free(dest);
	src = malloc(2);
	src[0] = 'Z';
	src[1] = '\0';
	dest = malloc(2);
	ft_strcpy(dest, src);
	free(src);
	free(dest);
	src = malloc(1);
	src[0] = '\0';
	dest = malloc(1);
	ft_strcpy(dest, src);
	free(src);
	free(dest);
	return (0);
}
