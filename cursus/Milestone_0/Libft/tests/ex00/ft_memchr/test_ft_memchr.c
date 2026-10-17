#include <stddef.h>
#include <stdio.h>

/* ft_memchr's fixture: each row searches a block and shows where the
 * returned pointer points, as s+N (N bytes from the start of the block), or
 * NULL. Most rows search the 11 bytes "Hello", a NUL, "World". */
void	*ft_memchr(const void *s, int c, size_t n);

static void	show(const char *label, const unsigned char *s, size_t len,
	void *ret)
{
	if (ret == NULL)
		printf("%s\tNULL\n", label);
	else if ((const unsigned char *)ret >= s
		&& (const unsigned char *)ret < s + len)
		printf("%s\ts+%zu\n", label, (size_t)((const unsigned char *)ret - s));
	else
		printf("%s\ta pointer outside the block\n", label);
}

static void	hello(const char *label, int c, size_t n)
{
	static const unsigned char	s[11] = {'H', 'e', 'l', 'l', 'o', '\0',
		'W', 'o', 'r', 'l', 'd'};

	show(label, s, sizeof(s), ft_memchr(s, c, n));
}

/* 5000 bytes, 'a' and NUL in turn, the last one 0xe9 and the only one. */
static void	big(void)
{
	static unsigned char	s[5000];
	size_t					i;

	i = 0;
	while (i < sizeof(s))
	{
		s[i] = (unsigned char)(i % 2 ? 0 : 'a');
		i++;
	}
	s[4999] = 0xe9;
	show("0xe9 (233), n 5000, only the last byte (past 4096)", s, sizeof(s),
		ft_memchr(s, 0xe9, 5000));
}

int	main(void)
{
	static const unsigned char	high[2] = {'a', 0xe9};

	hello("'W', n 11", 'W', 11);
	hello("'l', n 11 (two of them)", 'l', 11);
	hello("'z', n 11 (none)", 'z', 11);
	hello("'o', n 4 (the 'o' is the 5th byte)", 'o', 4);
	hello("'o', n 5", 'o', 5);
	hello("'H', n 0", 'H', 0);
	hello("'\\0', n 11", '\0', 11);
	hello("'d', n 11 (after the NUL)", 'd', 11);
	show("'a' then byte 0xe9, 233 (0xe9), n 2", high, 2, ft_memchr(high, 233, 2));
	show("'a' then byte 0xe9, -23, n 2", high, 2, ft_memchr(high, -23, 2));
	hello("256 + 'H' (328), n 11", 256 + 'H', 11);
	hello("-256, n 11", -256, 11);
	big();
	return (0);
}
