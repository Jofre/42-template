/* Memory-safety probe for ft_strupcase — run under AddressSanitizer.
 * strupcase walks its string IN PLACE, reading and upcasing each byte until the
 * terminating NUL, which it must not pass. Each str below is a
 * HEAP buffer of EXACTLY strlen + 1 bytes (NUL-terminated), so a correct
 * strupcase touches str[0..len] and stops, while any off-by-one that scans,
 * writes, or re-terminates one slot too far reaches str[len + 1] — one past the
 * buffer — which ASan flags as a heap-buffer-overflow. Cases cover the empty
 * string and length 1. This is a test, not a solution. */
#include <stdlib.h>

char	*ft_strupcase(char *str);

int	main(void)
{
	char	*str;

	str = malloc(6);
	str[0] = 'H';
	str[1] = 'e';
	str[2] = 'l';
	str[3] = 'l';
	str[4] = 'o';
	str[5] = '\0';
	ft_strupcase(str);
	free(str);
	str = malloc(2);
	str[0] = 'a';
	str[1] = '\0';
	ft_strupcase(str);
	free(str);
	str = malloc(1);
	str[0] = '\0';
	ft_strupcase(str);
	free(str);
	return (0);
}
