/* Memory-safety probe for ft_substr -- run under AddressSanitizer and the
 * pinned memcheck. Each s below is a HEAP block with no slack at all: "abc"
 * is a 4-byte block, three letters and the terminator, and the empty string
 * a 1-byte block holding only the terminator, each filled byte by byte. A
 * read past the terminator lands outside the block. The calls start on the
 * terminator, with len past the end and with len SIZE_MAX, where a length
 * worked out from len instead of from what is left of s reads, or allocates,
 * too far. Every start is at most strlen(s). The results are freed, never
 * read: a stub's NULL is a result like any other here. A test input, not an
 * implementation. */
#include <stdint.h>
#include <stdlib.h>

char	*ft_substr(char const *s, unsigned int start, size_t len);

static void	call(const char *s, unsigned int start, size_t len)
{
	free(ft_substr(s, start, len));
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
	call(abc, 0, 3);
	call(abc, 1, 1);
	call(abc, 3, 5);
	call(abc, 2, SIZE_MAX);
	call(abc, 0, SIZE_MAX);
	call(abc, 1, 100);
	call(empty, 0, 5);
	call(empty, 0, SIZE_MAX);
	free(abc);
	free(empty);
	return (0);
}
