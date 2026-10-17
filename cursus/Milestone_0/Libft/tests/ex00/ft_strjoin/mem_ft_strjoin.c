/* Memory-safety probe for ft_strjoin -- run under AddressSanitizer and the
 * pinned memcheck. Each string below is a HEAP block with no slack at all
 * ("ab" a 3-byte block, the empty string a 1-byte block), its bytes copied
 * in with the terminator, so a read past either terminator lands outside its
 * block; and ASan flags ft_strjoin if its own block is too small for what it
 * writes into it.
 * The results are freed, never read: a stub's NULL is a result like any
 * other here. A test input, not an implementation. */
#include <stdlib.h>
#include <string.h>

char	*ft_strjoin(char const *s1, char const *s2);

static char	*exact(const char *s, size_t n)
{
	char	*b;

	b = malloc(n + 1);
	if (b == NULL)
		exit(1);
	memcpy(b, s, n + 1);
	return (b);
}

int	main(void)
{
	char	*ab;
	char	*cd;
	char	*e1;
	char	*e2;

	ab = exact("ab", 2);
	cd = exact("cd", 2);
	e1 = exact("", 0);
	e2 = exact("", 0);
	free(ft_strjoin(ab, cd));
	free(ft_strjoin(ab, e1));
	free(ft_strjoin(e1, cd));
	free(ft_strjoin(e1, e2));
	free(ab);
	free(cd);
	free(e1);
	free(e2);
	return (0);
}
