/* Memory probe for ft_strnstr, run under AddressSanitizer
 * (ex00_ft_strnstr_asan) and memcheck (ex00_ft_strnstr_probe_memcheck).
 * Every string is a HEAP block holding it and its terminator, with no
 * slack, and every call passes a len past big's end: man 3bsd strnstr says
 * "Characters that appear after a '\0' character are not searched", so a
 * search that goes on past big's NUL reads outside the block. The calls
 * look for a little that is absent, one longer than big (its last byte
 * would sit past big's NUL), one that ends on big's last byte, and an empty
 * one in an empty big. The result is never dereferenced; what it is is the
 * output layer's to check. This is a test input, not an implementation. */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

char	*ft_strnstr(const char *big, const char *little, size_t len);

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
	char *volatile	r;
	int				i;

	b[0] = exact("abcdef", 7);
	b[1] = exact("xyz", 4);
	b[2] = exact("abcdefg", 8);
	b[3] = exact("def", 4);
	b[4] = exact("", 1);
	b[5] = exact("", 1);
	r = ft_strnstr(b[0], b[1], 100);
	r = ft_strnstr(b[0], b[2], SIZE_MAX);
	r = ft_strnstr(b[0], b[3], 7);
	r = ft_strnstr(b[4], b[5], 10);
	r = ft_strnstr(b[4], b[1], 10);
	(void)r;
	i = 0;
	while (i < 6)
		free(b[i++]);
	return (0);
}
