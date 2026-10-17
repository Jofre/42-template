/* Memory probe for ft_strrchr, run under AddressSanitizer
 * (ex00_ft_strrchr_asan) and memcheck (ex00_ft_strrchr_probe_memcheck). Each
 * string is a HEAP block with no slack: "abc" fills a 4-byte block,
 * terminator included, and "" a 1-byte block. The calls look for a byte that
 * is not there and for the terminator itself, so a search that goes on past
 * the NUL reads outside the block, where both tools report it. The result
 * is never dereferenced, and what it is is the output layer's to check.
 * This is a test input, not an implementation. */
#include <stdlib.h>

char	*ft_strrchr(const char *s, int c);

int	main(void)
{
	char			*abc;
	char			*empty;
	char *volatile	r;

	abc = malloc(4);
	empty = malloc(1);
	if (abc == NULL || empty == NULL)
		return (1);
	abc[0] = 'a';
	abc[1] = 'b';
	abc[2] = 'c';
	abc[3] = '\0';
	empty[0] = '\0';
	r = ft_strrchr(abc, 'z');
	r = ft_strrchr(abc, '\0');
	r = ft_strrchr(abc, 'a');
	r = ft_strrchr(empty, 'z');
	r = ft_strrchr(empty, '\0');
	(void)r;
	free(abc);
	free(empty);
	return (0);
}
