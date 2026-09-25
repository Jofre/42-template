/* Memory-safety probe for ft_strcapitalize — run under AddressSanitizer.
 * strcapitalize walks its string IN PLACE, upcasing the first letter of each
 * word and lowercasing the rest, up to the terminating NUL, which it must not
 * pass — even though it inspects the PREVIOUS byte for word boundaries, it must
 * never read before str[0] or write past the NUL. Each str below is a HEAP
 * buffer of EXACTLY strlen + 1 bytes (NUL-terminated); a correct strcapitalize
 * touches str[0..len] and stops, while any off-by-one that scans, writes, or
 * re-terminates one slot too far reaches str[len + 1] — one past the buffer —
 * which ASan flags as a heap-buffer-overflow. Cases include a multi-word string
 * with separators, the empty string, and length 1. A test, not a solution. */
#include <stdlib.h>

char	*ft_strcapitalize(char *str);

int	main(void)
{
	char	*str;

	str = malloc(12);
	str[0] = 'h';
	str[1] = 'i';
	str[2] = ' ';
	str[3] = 't';
	str[4] = 'h';
	str[5] = 'e';
	str[6] = 'r';
	str[7] = 'e';
	str[8] = '4';
	str[9] = 'y';
	str[10] = 'o';
	str[11] = '\0';
	ft_strcapitalize(str);
	free(str);
	str = malloc(2);
	str[0] = 'a';
	str[1] = '\0';
	ft_strcapitalize(str);
	free(str);
	str = malloc(1);
	str[0] = '\0';
	ft_strcapitalize(str);
	free(str);
	return (0);
}
