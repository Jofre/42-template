/* Memory-safety probe for ft_split -- run under AddressSanitizer and the
 * pinned memcheck. Each s below is a HEAP block with no slack at all, its
 * bytes copied in with the terminator, so a read past its terminator lands
 * outside the block: a word at the very end, a delimiter at the very end,
 * delimiters alone, and the empty string (a 1-byte block). Some of these are
 * cases the box (p.11) leaves open; no reading of them lets a function read
 * past s, which is all this probe asks. Each call states the most strings
 * any reading of its case gives, and the array that comes back is walked to
 * its NULL but never past that many entries: one it may hold under some
 * reading is freed, and none beyond is read, since a wrong answer may never
 * have set it. Then the array is freed; a stub's NULL is walked not at all.
 * A test input, not an implementation. */
#include <stdlib.h>
#include <string.h>

char	**ft_split(char const *s, char c);

static void	call(const char *text, size_t n, char c, size_t most)
{
	char	*s;
	char	**res;
	size_t	i;

	s = malloc(n + 1);
	if (s == NULL)
		exit(1);
	memcpy(s, text, n + 1);
	res = ft_split(s, c);
	i = 0;
	while (res != NULL && i < most && res[i] != NULL)
		free(res[i++]);
	free(res);
	free(s);
}

int	main(void)
{
	call("a b", 3, ' ', 2);
	call("ab", 2, ' ', 1);
	call("a b ", 4, ' ', 3);
	call(" a", 2, ' ', 2);
	call("   ", 3, ' ', 4);
	call("", 0, ' ', 1);
	call("a\xe9", 2, '\xe9', 2);
	return (0);
}
