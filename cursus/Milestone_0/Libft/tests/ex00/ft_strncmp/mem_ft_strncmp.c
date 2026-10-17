/* Memory probe for ft_strncmp, run under AddressSanitizer
 * (ex00_ft_strncmp_asan) and memcheck (ex00_ft_strncmp_probe_memcheck).
 * Every buffer is a HEAP block with no slack:
 *   - two 3-byte blocks "abc", NO terminator, n = 3: man 3 strncmp compares
 *     "only the first (at most) n bytes", so index 3 is never read;
 *   - "abc" and "abd" with their terminators, n = SIZE_MAX: the comparison
 *     ends at the first difference, inside both blocks;
 *   - "ab" and "ab" with their terminators, n = SIZE_MAX: the comparison
 *     ends at the terminators, the last byte of both blocks.
 * What the calls return is the output layer's to check. This is a test
 * input, not an implementation. */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int	ft_strncmp(const char *s1, const char *s2, size_t n);

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
	char			*b[6];
	volatile int	r;
	int				i;

	b[0] = exact("abc", 3);
	b[1] = exact("abc", 3);
	b[2] = exact("abc", 4);
	b[3] = exact("abd", 4);
	b[4] = exact("ab", 3);
	b[5] = exact("ab", 3);
	r = ft_strncmp(b[0], b[1], 3);
	r = ft_strncmp(b[2], b[3], SIZE_MAX);
	r = ft_strncmp(b[4], b[5], SIZE_MAX);
	(void)r;
	i = 0;
	while (i < 6)
		free(b[i++]);
	return (0);
}
