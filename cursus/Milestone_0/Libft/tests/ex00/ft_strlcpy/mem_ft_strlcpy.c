/* Memory probe for ft_strlcpy, run under AddressSanitizer
 * (ex00_ft_strlcpy_asan) and memcheck (ex00_ft_strlcpy_probe_memcheck).
 * strlcpy writes at most `size` bytes into dst: dst[0..size-1] is the whole
 * window, and index size is never touched. Each dst below is a HEAP block of
 * EXACTLY size bytes, so a store to dst[size] lands outside it; size 1 writes
 * only dst[0], and size 0 nothing at all, into a 0-byte block. Each src is a
 * heap block holding its string and terminator with no slack, so reading
 * past src's NUL is caught as well. What the calls return is the output
 * layer's to check. This is a test input, not an implementation. */
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

size_t	ft_strlcpy(char *dst, const char *src, size_t size);

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
	char			*src;
	char			*hi;
	char			*d[4];
	volatile size_t	r;

	src = exact("Hello", 6);
	hi = exact("Hi", 3);
	d[0] = malloc(4);
	d[1] = malloc(6);
	d[2] = malloc(1);
	d[3] = malloc(0);
	if (d[0] == NULL || d[1] == NULL || d[2] == NULL)
		return (1);
	r = ft_strlcpy(d[0], src, 4);
	r = ft_strlcpy(d[1], src, 6);
	r = ft_strlcpy(d[2], hi, 1);
	r = ft_strlcpy(d[3], hi, 0);
	(void)r;
	free(d[0]);
	free(d[1]);
	free(d[2]);
	free(d[3]);
	free(src);
	free(hi);
	return (0);
}
