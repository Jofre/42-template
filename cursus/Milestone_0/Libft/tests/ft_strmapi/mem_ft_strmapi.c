/* Memory-safety probe for ft_strmapi -- run under AddressSanitizer and the
 * pinned memcheck. Each s below is a HEAP block with no slack at all ("abc"
 * a 4-byte block, the empty string a 1-byte block), filled byte by byte, so
 * a read past its terminator lands outside the block; and ASan flags
 * ft_strmapi if its own block is too small for what it writes into it. The
 * f is the harness's own and gives back the byte it is handed. The results
 * are freed, never read: a stub's NULL is a result like any other here. A
 * test input, not an implementation. */
#include <stdlib.h>

char	*ft_strmapi(char const *s, char (*f)(unsigned int, char));

static char	same(unsigned int i, char c)
{
	(void)i;
	return (c);
}

int	main(void)
{
	char	*abc;
	char	*empty;

	abc = malloc(4);
	empty = malloc(1);
	if (abc == NULL || empty == NULL)
		return (1);
	abc[0] = 'a';
	abc[1] = 'b';
	abc[2] = 'c';
	abc[3] = '\0';
	empty[0] = '\0';
	free(ft_strmapi(abc, same));
	free(ft_strmapi(empty, same));
	free(abc);
	free(empty);
	return (0);
}
