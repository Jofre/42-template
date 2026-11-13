/* Memory-safety probe for ft_strtrim -- run under AddressSanitizer and the
 * pinned memcheck. Each s1 and set below is a HEAP block with no slack at
 * all, its bytes copied in with the terminator: a read past either
 * terminator lands outside its block. "xxxx" with set "x" is all set bytes
 * from the first byte of its block to its terminator, where a scan from the
 * end that does not stop at the start reads before the block; "" is a
 * 1-byte block. The results are freed, never read: a stub's NULL is a
 * result like any other here. A test input, not an implementation. */
#include <stdlib.h>
#include <string.h>

char	*ft_strtrim(char const *s1, char const *set);

static char	*exact(const char *s, size_t n)
{
	char	*b;

	b = malloc(n + 1);
	if (b == NULL)
		exit(1);
	memcpy(b, s, n + 1);
	return (b);
}

static void	call(const char *s1, size_t n1, const char *set, size_t n2)
{
	char	*a;
	char	*b;

	a = exact(s1, n1);
	b = exact(set, n2);
	free(ft_strtrim(a, b));
	free(a);
	free(b);
}

int	main(void)
{
	call("xxhixx", 6, "x", 1);
	call("xxxx", 4, "x", 1);
	call("x", 1, "x", 1);
	call("hi", 2, "", 0);
	call("", 0, "x", 1);
	call("", 0, "", 0);
	call("ab", 2, "ba", 2);
	return (0);
}
