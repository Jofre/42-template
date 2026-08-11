/* Memory-safety probe for ft_strncpy — run under AddressSanitizer.
 * strncpy's n bounds BOTH the dest write window (dest[0..n-1]) AND the src read
 * (it copies at most n bytes of src). Two hazards, both made a guaranteed ASan
 * overflow by using exactly-sized HEAP buffers:
 *   - dest: an off-by-one copy/pad loop writes dest[n], one past an exact-size dest.
 *   - src : a loop that tests src[i] BEFORE checking i < n reads src[n] when src
 *           is a non-NUL-terminated block of EXACTLY n bytes.
 * A correct strncpy (bound checked before the dereference) is clean on all cases,
 * incl. sizes 1 and 0. This is a test input, not an implementation. */
#include <stdlib.h>

char	*ft_strncpy(char *dest, char *src, unsigned int n);

int	main(void)
{
	char	*dst;
	char	*src;

	dst = malloc(4);
	ft_strncpy(dst, "abcd", 4);
	free(dst);
	dst = malloc(4);
	ft_strncpy(dst, "Hi", 4);
	free(dst);
	dst = malloc(1);
	ft_strncpy(dst, "Z", 1);
	free(dst);
	dst = malloc(0);
	ft_strncpy(dst, "", 0);
	free(dst);
	src = malloc(3);
	src[0] = 'a';
	src[1] = 'b';
	src[2] = 'c';
	dst = malloc(3);
	ft_strncpy(dst, src, 3);
	free(src);
	free(dst);
	return (0);
}
