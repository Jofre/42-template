#include <limits.h>
#include <stddef.h>
#include <stdio.h>

/* ft_memset with a c outside 0..255, which "the constant byte c" (man
 * memset) leaves open: a target of its own, above basic, whose clue says
 * what it expects. Each row fills 3 bytes of a 6-byte buffer of 'X' (0x58)
 * and shows every byte of it in hex, with what the call returned ("s" for
 * the pointer it was handed). */
void	*ft_memset(void *s, int c, size_t n);

static const char	*who(void *ret, void *s)
{
	if (ret == s)
		return ("s");
	if (ret == NULL)
		return ("NULL");
	return ("another pointer");
}

static void	row(const char *label, int c)
{
	unsigned char	buf[6] = {'X', 'X', 'X', 'X', 'X', 'X'};
	size_t			i;
	void			*ret;

	ret = ft_memset(buf, c, 3);
	printf("%s\tret=%s bytes=", label, who(ret, buf));
	i = 0;
	while (i < sizeof(buf))
	{
		printf(i ? " %02x" : "%02x", buf[i]);
		i++;
	}
	printf("\n");
}

int	main(void)
{
	row("353 (256 + 'a'), n 3", 256 + 'a');
	row("256, n 3", 256);
	row("-1, n 3", -1);
	row("-23, n 3", -23);
	row("INT_MIN, n 3", INT_MIN);
	row("INT_MAX, n 3", INT_MAX);
	return (0);
}
