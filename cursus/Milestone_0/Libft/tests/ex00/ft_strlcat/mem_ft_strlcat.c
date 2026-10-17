/* Memory probe for ft_strlcat, run under AddressSanitizer
 * (ex00_ft_strlcat_asan) and memcheck (ex00_ft_strlcat_probe_memcheck).
 * Every buffer is a HEAP block with no slack, and every dst is a C string
 * whose block is exactly `size` bytes:
 *   - "ab" and its terminator in a 5-byte block, size 5, src "cd": the
 *     result "abcd" and its terminator fill the block exactly;
 *   - "ab" and its terminator in a 3-byte block, size 3, src "cd": there is
 *     room for no byte of src ("at most size - strlen(dst) - 1 bytes"), and
 *     dst[3] is outside the block.
 * Each src is a block holding its string and terminator only, so a read
 * past its NUL is caught too. What the calls return is the output layer's
 * to check. This is a test input, not an implementation. */
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

size_t	ft_strlcat(char *dst, const char *src, size_t size);

static char	*exact(const char *s, size_t n)
{
	char	*b;

	b = malloc(n);
	if (b == NULL)
		exit(1);
	memcpy(b, s, n);
	return (b);
}

int	main(void)
{
	char			*d[2];
	char			*s[2];
	volatile size_t	r;

	d[0] = exact("ab\0XX", 5);
	d[1] = exact("ab", 3);
	s[0] = exact("cd", 3);
	s[1] = exact("cd", 3);
	r = ft_strlcat(d[0], s[0], 5);
	r = ft_strlcat(d[1], s[1], 3);
	(void)r;
	free(d[0]);
	free(d[1]);
	free(s[0]);
	free(s[1]);
	return (0);
}
