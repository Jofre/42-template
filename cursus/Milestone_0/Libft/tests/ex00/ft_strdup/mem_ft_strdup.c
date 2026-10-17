/* Memory probe for ft_strdup, run under AddressSanitizer
 * (ex00_ft_strdup_asan) and memcheck (ex00_ft_strdup_probe_memcheck). Each
 * s is a HEAP block with no slack: "a" is a 2-byte block holding 'a' and
 * the terminator, and the empty string a 1-byte block holding only the
 * terminator, both filled byte by byte. A read past the terminator lands
 * outside the block, and both tools flag ft_strdup too when its own block
 * is too small for what it writes into it. The copies are freed as they
 * come, a NULL one included (free(NULL) does nothing). This is a test
 * input, not an implementation. */
#include <stdlib.h>

char	*ft_strdup(const char *s);

int	main(void)
{
	char	*s;
	char	*empty;
	char	*d;

	s = malloc(2);
	empty = malloc(1);
	if (s == NULL || empty == NULL)
		return (1);
	s[0] = 'a';
	s[1] = '\0';
	empty[0] = '\0';
	d = ft_strdup(s);
	free(d);
	d = ft_strdup(empty);
	free(d);
	free(s);
	free(empty);
	return (0);
}
