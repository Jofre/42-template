/* Memory probe for ft_atoi, run under AddressSanitizer (ex00_ft_atoi_asan)
 * and memcheck (ex00_ft_atoi_probe_memcheck). Each string is a HEAP block
 * holding it and its terminator, with no slack: "", "-", "   " and "42".
 * A read past the terminator -- looking for one more space, one more sign
 * or one more digit -- lands outside the block, where both tools report
 * it. What ft_atoi returns is the output layer's to check. This is a test
 * input, not an implementation. */
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

int	ft_atoi(const char *nptr);

static char	*exact(const char *s, size_t n)
{
	char	*b;

	b = malloc(n);
	if (b == NULL)
		exit(1);
	memcpy(b, s, n);
	return (b);
}

int	main(void)
{
	char			*b[4];
	volatile int	r;
	int				i;

	b[0] = exact("", 1);
	b[1] = exact("-", 2);
	b[2] = exact("   ", 4);
	b[3] = exact("42", 3);
	i = 0;
	while (i < 4)
	{
		r = ft_atoi(b[i]);
		free(b[i]);
		i++;
	}
	(void)r;
	return (0);
}
