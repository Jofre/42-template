/* Memory-safety probe for ft_striteri -- run under AddressSanitizer and the
 * pinned memcheck. Each s below is a writable HEAP block with no slack at
 * all ("abc" a 4-byte block, the empty string a 1-byte block), filled byte
 * by byte, so a read past its terminator lands outside the block. The f is
 * the harness's own and writes nothing. A test input, not an
 * implementation. */
#include <stdlib.h>

void	ft_striteri(char *s, void (*f)(unsigned int, char*));

static void	look(unsigned int i, char *p)
{
	(void)i;
	(void)p;
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
	ft_striteri(abc, look);
	ft_striteri(empty, look);
	free(abc);
	free(empty);
	return (0);
}
