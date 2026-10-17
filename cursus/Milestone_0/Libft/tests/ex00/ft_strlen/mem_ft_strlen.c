/* Memory probe for ft_strlen, run under AddressSanitizer (ex00_ft_strlen_asan)
 * and memcheck (ex00_ft_strlen_probe_memcheck). Each string is a HEAP block
 * with no slack: "abc" fills a 4-byte block, terminator included, and the
 * empty string is a 1-byte block holding only its terminator, filled in byte
 * by byte. A read past the terminator lands outside the block, where both
 * tools report it. What ft_strlen returns is not checked here: the output
 * layer does that. This is a test input, not an implementation. */
#include <stddef.h>
#include <stdlib.h>

size_t	ft_strlen(const char *s);

int	main(void)
{
	char			*abc;
	char			*empty;
	volatile size_t	r;

	abc = malloc(4);
	empty = malloc(1);
	if (abc == NULL || empty == NULL)
		return (1);
	abc[0] = 'a';
	abc[1] = 'b';
	abc[2] = 'c';
	abc[3] = '\0';
	empty[0] = '\0';
	r = ft_strlen(abc);
	r = ft_strlen(empty);
	(void)r;
	free(abc);
	free(empty);
	return (0);
}
